--!strict
-- Lagerstätten und Stich (Überarbeitung Ü2). Rein, ohne Roblox-API, Lune-Tests in
-- tests/deposits.spec.luau. Zahlen in Data/Deposits.
--
-- Der Client sendet nur "Stich bei Punkt P" (und ob er durch Halten kam). Der Server misst den Takt
-- mit seiner eigenen Uhr, prüft die Reichweite vom Charakter aus und ob unter P Sand liegt (Strahl im
-- Service), und rechnet die Menge aus Rate, Takt, Schicht und Stich-Faktor. Es gibt keinen Parameter
-- für eine Menge.
--
-- Zustand je Spieler (nur im Speicher des Servers, nicht gespeichert):
--   cells       Zelle -> { dug = Stiche, lastAt = Zeit des letzten Stichs }
--   count       Anzahl gemerkter Zellen
--   budgetAt    frühester Zeitpunkt für den nächsten Stich (mit Spielraum slackSeconds)
--   lastStabAt  Zeit des letzten angenommenen Stichs (für "sauber"), nil am Anfang
--   carry       Bruchteil eines Korns aus dem letzten Stich
--   diggingUntil bis dann gilt der Spieler als "sammelt" (Anzeige)

local Data = require("../Data/Deposits")

export type Vec3 = { x: number, y: number, z: number }

export type Cell = { dug: number, lastAt: number }

export type State = {
    cells: { [string]: Cell },
    count: number,
    budgetAt: number,
    lastStabAt: number?,
    carry: number,
    diggingUntil: number,
}

export type StabInput = {
    now: number, -- Server-Uhr
    root: Vec3?, -- Position des Charakters (nil: kein lebender Charakter)
    point: Vec3, -- Zielpunkt aus der Remote
    reachMax: number, -- Reichweite des Werkzeugs (Logic/DigAim.reach(...).max)
    toolId: string?,
    held: boolean, -- Stich kam durch Halten (nie sauber)
    isSand: boolean, -- liegt unter dem Punkt grabbarer Sand (Strahl auf dem Server)
    space: number, -- ganze Körner, die noch in den Tank passen (Collecting.space)
    rate: number, -- Sand pro Sekunde (Collecting.rateOf)
}

export type StabResult = {
    ok: boolean, -- Stich angenommen (Zelle verbraucht, Takt gezählt)
    reason: string?, -- bei ok = false: badInput, tooSoon, reach, notSand, full oder empty
    added: number, -- ganze Körner in den Tank
    layer: number?, -- Schicht, aus der gestochen wurde (1 = oben)
    clean: boolean, -- sauberer Stich
    full: boolean, -- Tank ist jetzt voll
    emptyNow: boolean, -- Zelle ist nach diesem Stich leer
    seconds: number, -- Sammelzeit für den Fundwürfel (ein Takt je angenommenem Stich)
    cellKey: string?,
}

local Deposits = {}

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validPoint(p: any): boolean
    return type(p) == "table" and isFinite(p.x) and isFinite(p.y) and isFinite(p.z)
end

function Deposits.newState(): State
    return { cells = {}, count = 0, budgetAt = -math.huge, lastStabAt = nil, carry = 0, diggingUntil = -math.huge }
end

-- Takt des Werkzeugs in Sekunden.
function Deposits.stabSeconds(toolId: string?, data: any?): number
    local stab = (data or Data).stab
    local value = if toolId ~= nil then stab.secondsByTool[toolId] else nil
    if not isFinite(value) or value <= 0 then
        return stab.defaultSeconds
    end
    return value
end

-- Stiche, bis eine Zelle leer ist.
function Deposits.totalStabs(data: any?): number
    local total = 0
    for _, layer in (data or Data).layers do
        total += layer.stabs
    end
    return total
end

-- Schicht für eine Zelle mit `dug` Stichen (nächster Stich). nil = Zelle leer.
function Deposits.layerOf(dug: number, data: any?): (number?, any?)
    local passed = 0
    for index, layer in (data or Data).layers do
        passed += layer.stabs
        if dug < passed then
            return index, layer
        end
    end
    return nil, nil
end

-- Schlüssel der Zelle unter dem Punkt (waagrecht).
function Deposits.cellKey(x: number, z: number, data: any?): string
    local size = (data or Data).cellStuds
    return `{math.floor(x / size)},{math.floor(z / size)}`
end

-- Zelle mit Nachfüllen: Ist der letzte Stich `refillSeconds` her, ist sie wieder voll.
function Deposits.cellOf(state: State, key: string, now: number, data: any?): Cell?
    local cell = state.cells[key]
    if cell ~= nil and now - cell.lastAt >= (data or Data).refillSeconds then
        state.cells[key] = nil
        state.count -= 1
        return nil
    end
    return cell
end

-- Wie viele Stiche hat die Zelle unter dem Punkt schon (0 = voll)?
function Deposits.dugAt(state: State, x: number, z: number, now: number, data: any?): number
    local cell = Deposits.cellOf(state, Deposits.cellKey(x, z, data), now, data)
    return if cell ~= nil then cell.dug else 0
end

-- Liegt der Punkt in Reichweite des Charakters?
function Deposits.inReach(root: Vec3, point: Vec3, reachMax: number, data: any?): boolean
    local reach = (data or Data).reach
    local dx, dz = point.x - root.x, point.z - root.z
    local limit = reachMax + reach.toleranceStuds
    return dx * dx + dz * dz <= limit * limit and math.abs(point.y - root.y) <= reach.maxHeightStuds
end

-- Vergisst aufgefüllte Zellen, notfalls die ältesten, bis höchstens maxTrackedCells übrig sind.
function Deposits.prune(state: State, now: number, data: any?)
    local source = data or Data
    if state.count <= source.maxTrackedCells then
        return
    end
    for key, cell in state.cells do
        if now - cell.lastAt >= source.refillSeconds then
            state.cells[key] = nil
            state.count -= 1
        end
    end
    while state.count > source.maxTrackedCells do
        local oldestKey: string? = nil
        local oldestAt = math.huge
        for key, cell in state.cells do
            if cell.lastAt < oldestAt then
                oldestAt = cell.lastAt
                oldestKey = key
            end
        end
        if oldestKey == nil then
            break
        end
        state.cells[oldestKey] = nil
        state.count -= 1
    end
end

local function reject(reason: string): StabResult
    return { ok = false, reason = reason, added = 0, layer = nil, clean = false, full = reason == "full", emptyNow = false, seconds = 0, cellKey = nil }
end

-- Käme ein Stich jetzt zu früh? Günstige Vorprüfung für den Server vor Strahl und Rechnung.
function Deposits.tooSoon(state: State, now: number, toolId: string?, data: any?): boolean
    return now < state.budgetAt - (data or Data).stab.slackSeconds
end

-- Ein Stich. Ändert `state` nur bei Annahme (ok = true).
function Deposits.stab(state: State, input: StabInput, data: any?): StabResult
    local source = data or Data
    local now = input.now
    if not isFinite(now) or not validPoint(input.point) or not isFinite(input.reachMax) or not isFinite(input.rate) or input.rate < 0 or not isFinite(input.space) then
        return reject("badInput")
    end
    local root = input.root
    if root == nil or not validPoint(root) then
        return reject("badInput")
    end
    local stab = source.stab
    local interval = Deposits.stabSeconds(input.toolId, source)
    -- Takt zuerst: zu frühe Stiche kosten keine weitere Prüfung.
    if Deposits.tooSoon(state, now, input.toolId, source) then
        return reject("tooSoon")
    end
    if not Deposits.inReach(root, input.point, input.reachMax, source) then
        return reject("reach")
    end
    if not input.isSand then
        return reject("notSand")
    end
    local space = math.max(math.floor(input.space), 0)
    if space <= 0 then
        return reject("full")
    end
    local key = Deposits.cellKey(input.point.x, input.point.z, source)
    local cell = Deposits.cellOf(state, key, now, source)
    local dug = if cell ~= nil then cell.dug else 0
    local layerIndex, layer = Deposits.layerOf(dug, source)
    if layerIndex == nil or layer == nil then
        return reject("empty")
    end

    -- Angenommen: Takt, sauber oder normal, Menge.
    local last = state.lastStabAt
    local gap = if last ~= nil then now - last else math.huge
    local clean = not input.held and gap >= interval - stab.slackSeconds and gap <= interval + stab.cleanWindowSeconds
    state.budgetAt = math.max(state.budgetAt, now) + interval
    state.lastStabAt = now
    state.diggingUntil = now + interval * source.diggingHoldTakts

    local factor = if clean then stab.cleanFactor else stab.plainFactor
    local accrued = input.rate * interval * layer.factor * factor + state.carry
    local whole = math.floor(accrued)
    state.carry = accrued - whole
    local added = math.min(whole, space)
    local full = added >= space
    if full then
        state.carry = 0 -- wie beim Halten: ein angefangenes Korn verfällt, wenn der Tank voll ist
    end

    if cell == nil then
        cell = { dug = 0, lastAt = now }
        state.cells[key] = cell
        state.count += 1
    end
    local c = cell :: Cell
    c.dug = dug + 1
    c.lastAt = now
    Deposits.prune(state, now, source)

    return {
        ok = true,
        reason = nil,
        added = added,
        layer = layerIndex,
        clean = clean,
        full = full,
        emptyNow = Deposits.layerOf(dug + 1, source) == nil,
        seconds = interval,
        cellKey = key,
    }
end

-- Gilt der Spieler gerade als "sammelt" (für die Anzeige von Armen und Maschinen)?
function Deposits.isDigging(state: State?, now: number): boolean
    return state ~= nil and now < state.diggingUntil
end

-- Prüft die Tabelle (für DataCheck). Gibt Fehlertexte zurück.
function Deposits.check(data: any, toolIds: { string }?, regrowDelaySeconds: number?): { string }
    local errors: { string } = {}
    local function fail(text: string)
        table.insert(errors, `Deposits: {text}`)
    end
    if type(data) ~= "table" then
        fail("Tabelle fehlt")
        return errors
    end
    if not isFinite(data.cellStuds) or data.cellStuds <= 0 or data.cellStuds % 4 ~= 0 then
        fail("cellStuds muss ein Vielfaches von 4 über 0 sein")
    end
    if type(data.layers) ~= "table" or #data.layers == 0 then
        fail("layers braucht mindestens eine Schicht")
    else
        for index, layer in data.layers do
            if type(layer.name) ~= "string" or layer.name == "" then
                fail(`Schicht {index}: name fehlt`)
            end
            if not isFinite(layer.stabs) or layer.stabs < 1 or layer.stabs % 1 ~= 0 then
                fail(`Schicht {index}: stabs muss eine ganze Zahl ab 1 sein`)
            end
            if not isFinite(layer.factor) or layer.factor <= 0 then
                fail(`Schicht {index}: factor muss über 0 sein`)
            end
        end
    end
    if not isFinite(data.refillSeconds) or data.refillSeconds <= 0 then
        fail("refillSeconds muss über 0 sein")
    elseif regrowDelaySeconds ~= nil and regrowDelaySeconds ~= data.refillSeconds then
        fail(`Terrain.regrow.delaySeconds ({regrowDelaySeconds}) muss refillSeconds ({data.refillSeconds}) sein`)
    end
    local stab = data.stab
    if type(stab) ~= "table" then
        fail("stab fehlt")
    else
        if not isFinite(stab.defaultSeconds) or stab.defaultSeconds < 0.1 then
            fail("stab.defaultSeconds muss mindestens 0,1 sein")
        end
        if type(stab.secondsByTool) ~= "table" then
            fail("stab.secondsByTool fehlt")
        else
            for toolId, seconds in stab.secondsByTool do
                if not isFinite(seconds) or seconds < 0.1 then
                    fail(`stab.secondsByTool.{tostring(toolId)} muss mindestens 0,1 sein`)
                end
                if toolIds ~= nil and table.find(toolIds, toolId) == nil then
                    fail(`stab.secondsByTool.{tostring(toolId)}: Werkzeug gibt es nicht`)
                end
            end
            if toolIds ~= nil then
                for _, toolId in toolIds do
                    if stab.secondsByTool[toolId] == nil then
                        fail(`stab.secondsByTool: Werkzeug {toolId} fehlt`)
                    end
                end
            end
        end
        if not isFinite(stab.slackSeconds) or stab.slackSeconds < 0 or stab.slackSeconds >= (stab.defaultSeconds or 0) then
            fail("stab.slackSeconds muss zwischen 0 und dem kleinsten Takt liegen")
        end
        if type(stab.secondsByTool) == "table" then
            for toolId, seconds in stab.secondsByTool do
                if isFinite(seconds) and isFinite(stab.slackSeconds) and stab.slackSeconds >= seconds then
                    fail(`stab.slackSeconds muss kleiner als der Takt von {tostring(toolId)} sein`)
                end
            end
        end
        if not isFinite(stab.cleanWindowSeconds) or stab.cleanWindowSeconds < 0 then
            fail("stab.cleanWindowSeconds darf nicht negativ sein")
        end
        for _, key in { "cleanFactor", "plainFactor" } do
            if not isFinite(stab[key]) or stab[key] <= 0 then
                fail(`stab.{key} muss über 0 sein`)
            end
        end
    end
    if not isFinite(data.autoDigFactor) or data.autoDigFactor <= 0 or data.autoDigFactor > 1 then
        fail("autoDigFactor muss über 0 und höchstens 1 sein")
    end
    local reach = data.reach
    if type(reach) ~= "table" then
        fail("reach fehlt")
    else
        for _, key in { "toleranceStuds", "maxHeightStuds", "rayUpStuds", "rayLengthStuds" } do
            if not isFinite(reach[key]) or reach[key] < 0 then
                fail(`reach.{key} muss eine Zahl ab 0 sein`)
            end
        end
    end
    if not isFinite(data.maxTrackedCells) or data.maxTrackedCells < 1 or data.maxTrackedCells % 1 ~= 0 then
        fail("maxTrackedCells muss eine ganze Zahl ab 1 sein")
    end
    if not isFinite(data.coordinateLimit) or data.coordinateLimit <= 0 then
        fail("coordinateLimit muss über 0 sein")
    end
    if not isFinite(data.diggingHoldTakts) or data.diggingHoldTakts <= 0 then
        fail("diggingHoldTakts muss über 0 sein")
    end
    return errors
end

return Deposits
