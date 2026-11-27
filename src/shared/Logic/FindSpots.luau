--!strict
-- Fundstellen im Sand (Überarbeitung Ü3). Rein, ohne Roblox-API, Lune-Tests in
-- tests/findspots.spec.luau. Zahlen in Data/FindSpots, Zellen und Schichten aus Logic/Deposits.
--
-- Zustand je Spieler (nur im Speicher des Servers):
--   spots          aktive Stellen { id, key, x, y, z, layer, expiresAt }
--   nextId         laufende Nummer
--   stabsNoFind    angenommene Stiche dieser Sitzung, solange der Spieler noch nie etwas gefunden hat
--   firstSpawned   die Stelle "Erster Fund sicher" wurde schon angelegt
--
-- Ablauf je angenommenem Stich (`onStab`):
--   1. Abgelaufene Stellen und Stellen anderer Zonen entfernen.
--   2. Treffer: Liegt eine Stelle in der Zelle des Stichs und ist die gestochene Schicht mindestens ihre
--      Schicht, ist sie gefunden (genau ein Fund, die Stelle ist weg).
--   3. Erster Fund sicher (einmal): noch nie etwas gefunden und genug Stiche, dann eine Stelle in Schicht 1
--      eine Zelle hinter dem Stich (vom Charakter aus gesehen). Ihr Fund ist immer "Gewöhnlich" (forced),
--      wie die alte Regel "Erster Fund sicher". Ohne Fundchance in der Zone (rateFactor 0) keine Stellen.
--   4. Sonst mit der Chance aus Rate und Sekunden eine neue Stelle in minDistance bis maxDistance vom
--      Stich, wenn weniger als maxActive aktiv sind. `surfaceAt(x, z)` (Strahl im Service) liefert die
--      Höhe des Sandes oder nil
--      (nil auch für eine andere Zone oder eine schon angegrabene Zelle).

local Data = require("../Data/FindSpots")
local DepositData = require("../Data/Deposits")
local Deposits = require("./Deposits")

export type Spot = { id: number, key: string, zoneId: string, x: number, y: number, z: number, layer: number, expiresAt: number, forced: boolean }

export type State = {
    spots: { Spot },
    nextId: number,
    stabsNoFind: number,
    firstSpawned: boolean,
}

export type StabInput = {
    now: number,
    zoneId: string, -- aktuelle Zone; Stellen anderer Zonen fallen weg (Reise, Sturm)
    point: { x: number, y: number, z: number }, -- Stichstelle
    root: { x: number, z: number }, -- Charakter (für die Richtung der ersten Stelle)
    layer: number, -- gestochene Schicht
    seconds: number, -- Graben in diesem Stich (Takt)
    rateFactor: number, -- Zone, Glück, Boost, Wetter (FindRoll.chanceFactor)
    neverFound: boolean, -- Sammlung ist leer
    random: () -> number,
    surfaceAt: (x: number, z: number) -> number?,
}

export type StabOutcome = {
    found: Spot?, -- getroffene Stelle (genau ein Fund); `forced` = erste Stelle, Fund ist "Gewöhnlich"
    changed: boolean, -- Liste der Stellen hat sich geändert (an den Client senden)
}

local FindSpots = {}

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function FindSpots.newState(): State
    return { spots = {}, nextId = 0, stabsNoFind = 0, firstSpawned = false }
end

-- Entfernt abgelaufene Stellen. Gibt true zurück, wenn eine entfernt wurde.
function FindSpots.expire(state: State, now: number): boolean
    local changed = false
    for index = #state.spots, 1, -1 do
        if now >= state.spots[index].expiresAt then
            table.remove(state.spots, index)
            changed = true
        end
    end
    return changed
end

-- Schicht einer neuen Stelle nach den Gewichten. `r` in [0, 1).
function FindSpots.pickLayer(r: number, data: any?): number
    local weights = (data or Data).layerWeights
    local total = 0
    for _, w in weights do
        total += w
    end
    local target = math.clamp(r, 0, 0.999999999) * total
    local sum = 0
    for index, w in weights do
        sum += w
        if target < sum then
            return index
        end
    end
    return #weights
end

-- Chance auf eine neue Stelle in `seconds` Sekunden Graben.
function FindSpots.spawnChance(seconds: number, rateFactor: number, data: any?): number
    local source = data or Data
    if not isFinite(seconds) or not isFinite(rateFactor) or seconds <= 0 or rateFactor <= 0 then
        return 0
    end
    local perSecond = math.clamp(source.spawnPerSecond * rateFactor, 0, 1)
    return 1 - (1 - perSecond) ^ seconds
end

local function hasKey(state: State, key: string): boolean
    for _, spot in state.spots do
        if spot.key == key then
            return true
        end
    end
    return false
end

local function add(state: State, input: StabInput, x: number, y: number, z: number, layer: number, source: any, forced: boolean?): Spot
    state.nextId += 1
    local spot: Spot = {
        id = state.nextId,
        key = Deposits.cellKey(x, z, DepositData),
        zoneId = input.zoneId,
        forced = forced == true,
        x = x,
        y = y,
        z = z,
        layer = layer,
        expiresAt = input.now + source.lifetimeSeconds,
    }
    table.insert(state.spots, spot)
    return spot
end

-- Sucht einen Punkt mit Sand im Ring um `center` und legt dort eine Stelle an. nil, wenn keiner passt.
local function spawnAround(state: State, input: StabInput, source: any): Spot?
    local center = input.point
    local stabKey = Deposits.cellKey(center.x, center.z, DepositData)
    for _ = 1, source.spawnTries do
        local angle = input.random() * math.pi * 2
        local distance = source.minDistanceStuds + input.random() * (source.maxDistanceStuds - source.minDistanceStuds)
        local x = center.x + math.cos(angle) * distance
        local z = center.z + math.sin(angle) * distance
        local key = Deposits.cellKey(x, z, DepositData)
        if key ~= stabKey and not hasKey(state, key) then
            local y = input.surfaceAt(x, z)
            if y ~= nil and isFinite(y) then
                return add(state, input, x, y, z, FindSpots.pickLayer(input.random(), source), source)
            end
        end
    end
    return nil
end

-- Stelle "Erster Fund sicher": eine Zelle hinter dem Stich (vom Charakter weg), sonst die Stichzelle.
local function spawnFirst(state: State, input: StabInput, source: any): Spot
    local p = input.point
    local dx, dz = p.x - input.root.x, p.z - input.root.z
    local length = math.sqrt(dx * dx + dz * dz)
    local step = DepositData.cellStuds
    if length > 0.01 then
        local x, z = p.x + dx / length * step, p.z + dz / length * step
        local y = input.surfaceAt(x, z)
        if y ~= nil and isFinite(y) and not hasKey(state, Deposits.cellKey(x, z, DepositData)) then
            return add(state, input, x, y, z, 1, source, true)
        end
    end
    -- Rückfall: in der Stichzelle selbst (der nächste Stich dort findet sie).
    for index = #state.spots, 1, -1 do
        if state.spots[index].key == Deposits.cellKey(p.x, p.z, DepositData) then
            table.remove(state.spots, index)
        end
    end
    return add(state, input, p.x, p.y, p.z, 1, source, true)
end

-- Ein angenommener Stich. Ändert `state`.
function FindSpots.onStab(state: State, input: StabInput, data: any?): StabOutcome
    local source = data or Data
    local changed = FindSpots.expire(state, input.now)
    -- Stellen einer anderen Zone (nach Reise oder Sandsturm) fallen weg und blockieren keine neuen.
    for index = #state.spots, 1, -1 do
        if state.spots[index].zoneId ~= input.zoneId then
            table.remove(state.spots, index)
            changed = true
        end
    end
    local key = Deposits.cellKey(input.point.x, input.point.z, DepositData)
    for index, spot in state.spots do
        if spot.key == key and input.layer >= spot.layer then
            table.remove(state.spots, index)
            state.stabsNoFind = 0
            return { found = spot, changed = true }
        end
    end

    if not isFinite(input.rateFactor) or input.rateFactor <= 0 then
        return { found = nil, changed = changed } -- Zone ohne Funde: keine Stellen
    end

    if input.neverFound and not state.firstSpawned then
        state.stabsNoFind += 1
        if state.stabsNoFind >= source.firstFindStabs then
            state.firstSpawned = true
            spawnFirst(state, input, source)
            return { found = nil, changed = true }
        end
    end

    if #state.spots < source.maxActive and input.random() < FindSpots.spawnChance(input.seconds, input.rateFactor, source) then
        if spawnAround(state, input, source) ~= nil then
            changed = true
        end
    end
    return { found = nil, changed = changed }
end

-- Liste für den Client (nur Lage, keine Schicht und keine Seltenheit).
function FindSpots.view(state: State): { { id: number, x: number, y: number, z: number } }
    local list = {}
    for _, spot in state.spots do
        table.insert(list, { id = spot.id, x = spot.x, y = spot.y, z = spot.z })
    end
    return list
end

-- Prüft die Tabelle (für DataCheck).
function FindSpots.check(data: any, layerCount: number?): { string }
    local errors: { string } = {}
    local function fail(text: string)
        table.insert(errors, `FindSpots: {text}`)
    end
    if type(data) ~= "table" then
        fail("Tabelle fehlt")
        return errors
    end
    local function positive(key: string, allowZero: boolean?)
        local v = data[key]
        if not isFinite(v) or v < 0 or (not allowZero and v == 0) then
            fail(`{key} muss eine Zahl über 0 sein`)
        end
    end
    for _, key in { "maxActive", "spawnPerSecond", "minDistanceStuds", "maxDistanceStuds", "spawnTries", "lifetimeSeconds", "firstFindStabs", "rayUpStuds", "rayLengthStuds", "glitterDistanceStuds" } do
        positive(key)
    end
    positive("baseChanceFactor", true)
    if isFinite(data.minDistanceStuds) and isFinite(data.maxDistanceStuds) and data.minDistanceStuds >= data.maxDistanceStuds then
        fail("minDistanceStuds muss kleiner als maxDistanceStuds sein")
    end
    if isFinite(data.spawnPerSecond) and data.spawnPerSecond > 1 then
        fail("spawnPerSecond darf höchstens 1 sein")
    end
    if isFinite(data.baseChanceFactor) and data.baseChanceFactor > 1 then
        fail("baseChanceFactor darf höchstens 1 sein")
    end
    for _, key in { "maxActive", "spawnTries", "firstFindStabs" } do
        if isFinite(data[key]) and data[key] % 1 ~= 0 then
            fail(`{key} muss eine ganze Zahl sein`)
        end
    end
    if type(data.layerWeights) ~= "table" or #data.layerWeights == 0 then
        fail("layerWeights fehlt")
    else
        local total = 0
        for index, w in data.layerWeights do
            if not isFinite(w) or w < 0 then
                fail(`layerWeights[{index}] muss eine Zahl ab 0 sein`)
            else
                total += w
            end
        end
        if total <= 0 then
            fail("layerWeights braucht ein Gewicht über 0")
        end
        if layerCount ~= nil and #data.layerWeights > layerCount then
            fail(`layerWeights hat mehr Einträge als Data/Deposits Schichten ({layerCount})`)
        end
    end
    return errors
end

return FindSpots
