--!strict
-- Überarbeitung Ü3: Fundstellen im Sand (Logic/FindSpots, Data/FindSpots, FindRoll.fromSpot,
-- FindRoll.chanceFactor, Remote FindSpots).

local T = require("./lib/expect")
local FindSpots = require("../src/shared/Logic/FindSpots")
local Data = require("../src/shared/Data/FindSpots")
local Deposits = require("../src/shared/Logic/Deposits")
local DepositData = require("../src/shared/Data/Deposits")
local FindRoll = require("../src/shared/Logic/FindRoll")
local FindOdds = require("../src/shared/Data/FindOdds")
local Profile = require("../src/shared/Logic/Profile")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local DataCheck = require("../src/shared/Logic/DataCheck")

local NOW = 1_700_000_000
local CELL = DepositData.cellStuds
local SAND_Y = 5

local function copy(t: { [string]: any }): { [string]: any }
    local result = {}
    for k, v in t do
        result[k] = v
    end
    return result
end

-- Zufall aus einer festen Liste (danach immer `rest`).
local function sequence(values: { number }, rest: number?): () -> number
    local index = 0
    return function(): number
        index += 1
        return values[index] or rest or 0.5
    end
end

-- Kleiner fester Zufall (Lune hat kein Random): lineare Kongruenz, Werte in [0, 1).
local function seeded(seed: number): () -> number
    local s = (seed * 7919 + 12345) % 2147483647
    return function(): number
        s = (s * 48271) % 2147483647
        return s / 2147483647
    end
end

local function sandEverywhere(_x: number, _z: number): number?
    return SAND_Y
end

local function input(now: number, overrides: { [string]: any }?): any
    local value: any = {
        now = now,
        zoneId = "dunes",
        point = { x = 4, y = SAND_Y, z = 4 },
        root = { x = -2, z = 4 },
        layer = 1,
        seconds = 0.45,
        rateFactor = 1,
        neverFound = false,
        random = seeded(1),
        surfaceAt = sandEverywhere,
    }
    if overrides ~= nil then
        for key, v in overrides do
            value[key] = v
        end
    end
    return value
end

-- Datensatz, in dem jeder Stich sicher eine Stelle anlegt.
local function alwaysSpawn(): any
    local data = copy(Data)
    data.spawnPerSecond = 1
    return data
end

local function horizontalDistance(a: any, b: any): number
    return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

T.describe("FindSpots: Daten", function()
    T.it("DataCheck meldet nichts zu FindSpots", function()
        for _, message in DataCheck.run() do
            T.expect(string.find(message, "FindSpots", 1, true)).toBeNil()
        end
    end)

    T.it("check findet kaputte Werte", function()
        local bad = copy(Data)
        bad.minDistanceStuds = 40
        bad.spawnPerSecond = 2
        bad.maxActive = 2.5
        bad.layerWeights = { 0, 0 }
        local errors = FindSpots.check(bad, 3)
        T.expect(#errors >= 4).toBe(true)
        local tooMany = copy(Data)
        tooMany.layerWeights = { 1, 1, 1, 1 }
        T.expect(#FindSpots.check(tooMany, 3)).toBe(1)
        T.expect(#FindSpots.check(Data, #DepositData.layers)).toBe(0)
    end)

    T.it("Schicht nach Gewichten 20/60/20", function()
        T.expect(FindSpots.pickLayer(0)).toBe(1)
        T.expect(FindSpots.pickLayer(0.19)).toBe(1)
        T.expect(FindSpots.pickLayer(0.2)).toBe(2)
        T.expect(FindSpots.pickLayer(0.79)).toBe(2)
        T.expect(FindSpots.pickLayer(0.8)).toBe(3)
        T.expect(FindSpots.pickLayer(1)).toBe(3)
    end)
end)

T.describe("FindSpots: Entstehen", function()
    T.it("neue Stellen nur auf Sand und im Abstand minDistance bis maxDistance", function()
        local data = alwaysSpawn()
        local random = seeded(7)
        for round = 1, 200 do
            local state = FindSpots.newState()
            local point = { x = round * 3, y = SAND_Y, z = -round }
            FindSpots.onStab(state, input(0, { point = point, random = random }), data)
            T.expect(#state.spots).toBe(1)
            local spot = state.spots[1]
            local d = horizontalDistance(spot, point)
            T.expect(d >= Data.minDistanceStuds - 1e-9).toBe(true)
            T.expect(d <= Data.maxDistanceStuds + 1e-9).toBe(true)
            T.expect(spot.y).toBe(SAND_Y)
            T.expect(spot.key ~= Deposits.cellKey(point.x, point.z, DepositData)).toBe(true)
        end
    end)

    T.it("ohne Sand keine Stelle; Sand nur in einer Richtung trifft genau dort", function()
        local state = FindSpots.newState()
        local outcome = FindSpots.onStab(state, input(0, { surfaceAt = function()
            return nil
        end }), alwaysSpawn())
        T.expect(#state.spots).toBe(0)
        T.expect(outcome.changed).toBe(false)

        local onlyEast = function(x: number, _z: number): number?
            return if x > 4 then SAND_Y else nil
        end
        local state2 = FindSpots.newState()
        for _ = 1, 20 do
            FindSpots.onStab(state2, input(0, { surfaceAt = onlyEast, random = seeded(3) }), alwaysSpawn())
        end
        for _, spot in state2.spots do
            T.expect(spot.x > 4).toBe(true)
        end
    end)

    T.it("höchstens maxActive Stellen, in verschiedenen Zellen", function()
        local state = FindSpots.newState()
        local random = seeded(11)
        for i = 1, 50 do
            FindSpots.onStab(state, input(i, { random = random, point = { x = 1000, y = SAND_Y, z = 1000 } }), alwaysSpawn())
        end
        T.expect(#state.spots).toBe(Data.maxActive)
        local keys = {}
        for _, spot in state.spots do
            T.expect(keys[spot.key]).toBeNil()
            keys[spot.key] = true
        end
    end)

    T.it("Stellen verschwinden nach lifetimeSeconds", function()
        local state = FindSpots.newState()
        FindSpots.onStab(state, input(10, { point = { x = 500, y = SAND_Y, z = 500 } }), alwaysSpawn())
        T.expect(#state.spots).toBe(1)
        T.expect(FindSpots.expire(state, 10 + Data.lifetimeSeconds - 0.01)).toBe(false)
        T.expect(#state.spots).toBe(1)
        T.expect(FindSpots.expire(state, 10 + Data.lifetimeSeconds)).toBe(true)
        T.expect(#state.spots).toBe(0)
    end)

    T.it("Spawn-Chance: 1/40 je Sekunde, Faktor wirkt, kaputte Werte geben 0", function()
        T.expect(FindSpots.spawnChance(1, 1)).toBeCloseTo(Data.spawnPerSecond, 1e-12)
        T.expect(FindSpots.spawnChance(1, 2)).toBeCloseTo(Data.spawnPerSecond * 2, 1e-12)
        T.expect(FindSpots.spawnChance(0.45, 1)).toBeCloseTo(1 - (1 - Data.spawnPerSecond) ^ 0.45, 1e-12)
        T.expect(FindSpots.spawnChance(0, 1)).toBe(0)
        T.expect(FindSpots.spawnChance(1, 0)).toBe(0)
        T.expect(FindSpots.spawnChance(0 / 0, 1)).toBe(0)
        T.expect(FindSpots.spawnChance(1, math.huge)).toBe(0)
        T.expect(FindSpots.spawnChance(1, 1000)).toBe(1)
    end)

    T.it("im Mittel eine Stelle je ~40 s Graben (Simulation)", function()
        local random = seeded(5)
        local spawned = 0
        local seconds = 0
        for i = 1, 20000 do
            local state = FindSpots.newState()
            FindSpots.onStab(state, input(i, { random = random }))
            seconds += 0.45
            spawned += #state.spots
        end
        local perSecond = spawned / seconds
        T.expect(math.abs(perSecond - Data.spawnPerSecond) < Data.spawnPerSecond * 0.15).toBe(true)
    end)
end)

T.describe("FindSpots: Treffer", function()
    local function stateWith(layer: number): any
        local state = FindSpots.newState()
        state.nextId = 1
        table.insert(state.spots, {
            id = 1,
            key = Deposits.cellKey(20, 20, DepositData),
            zoneId = "dunes",
            forced = false,
            x = 20,
            y = SAND_Y,
            z = 20,
            layer = layer,
            expiresAt = 1000,
        })
        return state
    end
    local noSpawn = sequence({}, 0.999)

    T.it("Treffer nur in der Zelle der Stelle", function()
        local state = stateWith(1)
        local miss = FindSpots.onStab(state, input(0, { point = { x = 20 + CELL, y = SAND_Y, z = 20 }, random = noSpawn }))
        T.expect(miss.found).toBeNil()
        T.expect(#state.spots).toBe(1)
        local hit = FindSpots.onStab(state, input(0, { point = { x = 17, y = SAND_Y, z = 22 }, random = noSpawn }))
        T.expect(hit.found ~= nil).toBe(true)
        T.expect(hit.changed).toBe(true)
        T.expect(#state.spots).toBe(0)
    end)

    T.it("Treffer erst ab der Schicht der Stelle", function()
        local state = stateWith(2)
        local p = { x = 20, y = SAND_Y, z = 20 }
        T.expect(FindSpots.onStab(state, input(0, { point = p, layer = 1, random = noSpawn })).found).toBeNil()
        T.expect(FindSpots.onStab(state, input(0, { point = p, layer = 2, random = noSpawn })).found ~= nil).toBe(true)
        local deep = stateWith(2)
        T.expect(FindSpots.onStab(deep, input(0, { point = p, layer = 3, random = noSpawn })).found ~= nil).toBe(true)
    end)

    T.it("eine Stelle gibt genau einen Fund", function()
        local state = stateWith(1)
        local p = { x = 20, y = SAND_Y, z = 20 }
        local finds = 0
        for _ = 1, 10 do
            if FindSpots.onStab(state, input(0, { point = p, random = noSpawn })).found ~= nil then
                finds += 1
            end
        end
        T.expect(finds).toBe(1)
    end)

    T.it("abgelaufene Stelle wird nicht mehr gefunden", function()
        local state = stateWith(1)
        local outcome = FindSpots.onStab(state, input(1000, { point = { x = 20, y = SAND_Y, z = 20 }, random = noSpawn }))
        T.expect(outcome.found).toBeNil()
        T.expect(outcome.changed).toBe(true)
    end)

    T.it("Stellen einer anderen Zone fallen beim nächsten Stich weg (Reise, Sandsturm)", function()
        local state = stateWith(1)
        local outcome = FindSpots.onStab(state, input(0, { zoneId = "oasis", point = { x = 20, y = SAND_Y, z = 20 }, random = noSpawn }))
        T.expect(outcome.found).toBeNil()
        T.expect(outcome.changed).toBe(true)
        T.expect(#state.spots).toBe(0)
    end)

    T.it("neue Stellen merken sich ihre Zone", function()
        local state = FindSpots.newState()
        FindSpots.onStab(state, input(0, { zoneId = "oasis" }), alwaysSpawn())
        T.expect(state.spots[1].zoneId).toBe("oasis")
        T.expect(state.spots[1].forced).toBe(false)
    end)

    T.it("view zeigt nur Lage, keine Schicht", function()
        local view = FindSpots.view(stateWith(3))
        T.expect(#view).toBe(1)
        T.expect(view[1]).toEqual({ id = 1, x = 20, y = SAND_Y, z = 20 })
    end)
end)

T.describe("FindSpots: Erster Fund sicher", function()
    local noSpawn = sequence({}, 0.999)

    T.it("nach firstFindStabs Stichen eine Stelle in Schicht 1 eine Zelle hinter dem Stich", function()
        local state = FindSpots.newState()
        local p = { x = 4, y = SAND_Y, z = 4 }
        for i = 1, Data.firstFindStabs - 1 do
            local outcome = FindSpots.onStab(state, input(i, { neverFound = true, point = p, random = noSpawn }))
            T.expect(outcome.changed).toBe(false)
        end
        T.expect(#state.spots).toBe(0)
        local outcome = FindSpots.onStab(state, input(100, { neverFound = true, point = p, random = noSpawn }))
        T.expect(outcome.changed).toBe(true)
        T.expect(#state.spots).toBe(1)
        local spot = state.spots[1]
        T.expect(spot.layer).toBe(1)
        T.expect(spot.forced).toBe(true) -- Fund ist "Gewöhnlich" wie früher
        T.expect(spot.x).toBeCloseTo(4 + CELL, 1e-9) -- Charakter steht westlich, Stelle liegt östlich
        T.expect(spot.z).toBeCloseTo(4, 1e-9)
        -- Ein Stich in der Zelle der Stelle (Schicht 1) findet sie.
        local hit = FindSpots.onStab(state, input(101, { neverFound = true, point = { x = spot.x, y = SAND_Y, z = spot.z }, random = noSpawn }))
        T.expect(hit.found ~= nil).toBe(true)
    end)

    T.it("nur einmal je Sitzung, auch wenn die Stelle abläuft", function()
        local state = FindSpots.newState()
        for i = 1, Data.firstFindStabs do
            FindSpots.onStab(state, input(i, { neverFound = true, random = noSpawn }))
        end
        T.expect(#state.spots).toBe(1)
        FindSpots.expire(state, 10000)
        for i = 1, Data.firstFindStabs * 3 do
            FindSpots.onStab(state, input(10000 + i, { neverFound = true, random = noSpawn }))
        end
        T.expect(#state.spots).toBe(0)
    end)

    T.it("wer schon etwas gefunden hat, bekommt keine", function()
        local state = FindSpots.newState()
        for i = 1, Data.firstFindStabs * 2 do
            FindSpots.onStab(state, input(i, { neverFound = false, random = noSpawn }))
        end
        T.expect(#state.spots).toBe(0)
        T.expect(state.firstSpawned).toBe(false)
    end)

    T.it("ohne Sand hinter dem Stich liegt sie in der Stichzelle", function()
        local state = FindSpots.newState()
        local p = { x = 4, y = SAND_Y, z = 4 }
        local onlyHere = function(x: number, z: number): number?
            return if Deposits.cellKey(x, z, DepositData) == Deposits.cellKey(p.x, p.z, DepositData) then SAND_Y else nil
        end
        for i = 1, Data.firstFindStabs do
            FindSpots.onStab(state, input(i, { neverFound = true, point = p, surfaceAt = onlyHere, random = noSpawn }))
        end
        T.expect(#state.spots).toBe(1)
        T.expect(state.spots[1].key).toBe(Deposits.cellKey(p.x, p.z, DepositData))
    end)
end)

T.describe("FindSpots: Seltenheit und Faktoren", function()
    T.it("die erste Stelle gibt immer ein gewöhnliches Fundstück (FindRoll.build forced)", function()
        local roll = FindRoll.build(Profile.default(NOW), "dunes", "common", 0.3, true) :: any
        T.expect(roll.rarityId).toBe("common")
        T.expect(roll.forced).toBe(true)
    end)

    T.it("Seltenheit aus Stellen folgt der Quotentabelle (100k Würfe, ±0,5 Prozentpunkte)", function()
        local profile = Profile.default(NOW)
        local random = seeded(42)
        local counts: { [string]: number } = {}
        local n = 100000
        for _ = 1, n do
            local roll = FindRoll.fromSpot(profile, "dunes", random)
            T.expect(roll ~= nil).toBe(true)
            local id = (roll :: any).rarityId
            counts[id] = (counts[id] or 0) + 1
        end
        for rarityId, weight in FindOdds.tables.base do
            local share = (counts[rarityId] or 0) / n
            T.expect(math.abs(share - weight / 10000) < 0.005).toBe(true)
        end
    end)

    T.it("Glück-Ast und Zone ändern nur die Entstehungsrate, nicht die Seltenheit", function()
        local plain = Profile.default(NOW)
        local lucky = Profile.default(NOW)
        lucky.nodes.luck_1 = true
        T.expect(FindRoll.chanceFactor(plain, "dunes", 200)).toBeCloseTo(1, 1e-9)
        T.expect(FindRoll.chanceFactor(lucky, "dunes", 200) > 1).toBe(true)
        T.expect(FindRoll.chanceFactor(plain, "ruins", 200)).toBeCloseTo(2, 1e-9)
        T.expect(FindRoll.chanceFactor(plain, "gibt_es_nicht", 200)).toBe(0)
        -- Gleicher Zufall gibt dieselbe Seltenheit, egal ob Glück oder nicht.
        for i = 1, 200 do
            local a = FindRoll.fromSpot(plain, "dunes", seeded(i)) :: any
            local b = FindRoll.fromSpot(lucky, "dunes", seeded(i)) :: any
            T.expect(a.rarityId).toBe(b.rarityId)
        end
    end)

    T.it("Grundchance ohne Stelle ist ein Viertel und ohne 'Erster Fund nach 60 s'", function()
        T.expect(Data.baseChanceFactor).toBe(0.25)
        local profile = Profile.default(NOW)
        local function chanceOf(extra: { [string]: any }): number
            local hits = 0
            local rng = seeded(9)
            for _ = 1, 40000 do
                local value: any = {
                    profile = profile,
                    zoneId = "dunes",
                    seconds = 1,
                    serverTime = 200,
                    sessionSeconds = 1,
                    random = rng,
                }
                for k, v in extra do
                    value[k] = v
                end
                if FindRoll.roll(value) ~= nil then
                    hits += 1
                end
            end
            return hits / 40000
        end
        local full = chanceOf({})
        local base = chanceOf({ chanceFactor = Data.baseChanceFactor, noForced = true })
        T.expect(math.abs(base / full - 0.25) < 0.05).toBe(true)
        -- Lange Sitzung ohne Fund: mit noForced kein erzwungener Fund.
        local forced = FindRoll.roll({
            profile = profile,
            zoneId = "dunes",
            seconds = 1,
            serverTime = 200,
            sessionSeconds = FindOdds.firstFindGuaranteeSeconds + 1,
            random = sequence({}, 0.999),
            chanceFactor = Data.baseChanceFactor,
            noForced = true,
        } :: any)
        T.expect(forced).toBeNil()
    end)

    T.it("rateFactor 0 (z. B. unbekannte Zone) legt keine Stellen an, auch nicht die erste", function()
        local state = FindSpots.newState()
        for i = 1, 100 do
            FindSpots.onStab(state, input(i, { rateFactor = 0, neverFound = true, random = seeded(i) }), alwaysSpawn())
        end
        T.expect(#state.spots).toBe(0)
        T.expect(state.firstSpawned).toBe(false)
    end)
end)

T.describe("FindSpots: Remote", function()
    T.it("FindSpots ist Server->Client; keine neue Client->Server-Remote", function()
        T.expect(RemoteSpec.byName.FindSpots.direction).toBe("ServerToClient")
        T.expect(select(1, RemoteSpec.canRegister("FindSpots"))).toBe(false)
        local clientRemotes = 0
        for _, def in RemoteSpec.list do
            if def.direction == "ClientToServer" then
                clientRemotes += 1
            end
        end
        T.expect(clientRemotes).toBe(18) -- wie nach Ü2
    end)
end)
