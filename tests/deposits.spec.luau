--!strict
-- Überarbeitung Ü2: Lagerstätten und Stich (Logic/Deposits, Data/Deposits, Remote Stab).

local T = require("./lib/expect")
local Deposits = require("../src/shared/Logic/Deposits")
local Data = require("../src/shared/Data/Deposits")
local Tools = require("../src/shared/Data/Tools")
local Terrain = require("../src/shared/Data/Terrain")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local Validate = require("../src/shared/Logic/Validate")
local DataCheck = require("../src/shared/Logic/DataCheck")

local ROOT = { x = 0, y = 3, z = 0 }
local POINT = { x = 6, y = 0, z = 0 }
local REACH = 8
local SHOVEL = Deposits.stabSeconds("shovel")

local function input(now: number, overrides: { [string]: any }?): any
    local value: any = {
        now = now,
        root = ROOT,
        point = POINT,
        reachMax = REACH,
        toolId = "shovel",
        held = false,
        isSand = true,
        space = 1000000,
        rate = 100,
    }
    if overrides ~= nil then
        for key, v in overrides do
            value[key] = v
        end
    end
    return value
end

-- Sticht `count`-mal im genauen Takt ab `start` und gibt die Ergebnisse zurück.
local function stabMany(state: any, start: number, count: number, overrides: { [string]: any }?): ({ any }, number)
    local results = {}
    local t = start
    for _ = 1, count do
        table.insert(results, Deposits.stab(state, input(t, overrides)))
        t += SHOVEL
    end
    return results, t
end

T.describe("Deposits: Daten", function()
    T.it("DataCheck meldet nichts, Nachwachsen im Terrain gleich der Auffüllzeit", function()
        for _, message in DataCheck.run() do
            T.expect(string.find(message, "Deposits", 1, true)).toBeNil()
        end
        T.expect(Terrain.regrow.delaySeconds).toBe(Data.refillSeconds)
    end)

    T.it("jedes Werkzeug hat einen Takt", function()
        for _, tool in Tools.list do
            T.expect(Data.stab.secondsByTool[tool.id] ~= nil).toBe(true)
        end
        T.expect(Deposits.stabSeconds("gibtsnicht")).toBe(Data.stab.defaultSeconds)
    end)

    T.it("check meldet kaputte Werte", function()
        local broken = table.clone(Data)
        broken.layers = { { name = "", stabs = 0, factor = -1 } }
        broken.refillSeconds = 0
        T.expect(#Deposits.check(broken) >= 4).toBe(true)
        T.expect(#Deposits.check(Data, nil, 8)).toBe(1) -- Terrain wächst anders nach
    end)
end)

T.describe("Deposits: Prüfungen", function()
    T.it("Ziel außerhalb der Reichweite, zu hoch, ohne Charakter oder kaputt: kein Sand", function()
        local state = Deposits.newState()
        T.expect(Deposits.stab(state, input(10, { point = { x = 20, y = 0, z = 0 } })).reason).toBe("reach")
        T.expect(Deposits.stab(state, input(10, { point = { x = 2, y = 30, z = 0 } })).reason).toBe("reach")
        T.expect(Deposits.stab(state, input(10, { root = false })).reason).toBe("badInput")
        T.expect(Deposits.stab(state, input(10, { point = { x = 0 / 0, y = 0, z = 0 } })).reason).toBe("badInput")
        T.expect(Deposits.stab(state, input(10, { point = { x = math.huge, y = 0, z = 0 } })).reason).toBe("badInput")
        T.expect(Deposits.stab(state, input(10, { rate = -1 })).reason).toBe("badInput")
        T.expect(state.count).toBe(0)
    end)

    T.it("Reichweite mit Spielraum: genau an der Grenze geht, knapp darüber nicht", function()
        local limit = REACH + Data.reach.toleranceStuds
        local state = Deposits.newState()
        T.expect(Deposits.stab(state, input(10, { point = { x = limit, y = 0, z = 0 } })).ok).toBe(true)
        T.expect(Deposits.stab(state, input(20, { point = { x = limit + 0.01, y = 0, z = 0 } })).reason).toBe("reach")
    end)

    T.it("kein Sand unter dem Punkt: kein Stich", function()
        local state = Deposits.newState()
        local result = Deposits.stab(state, input(10, { isSand = false }))
        T.expect(result.reason).toBe("notSand")
        T.expect(result.added).toBe(0)
    end)

    T.it("zwei Stiche schneller als der Takt: der zweite zählt nicht", function()
        local state = Deposits.newState()
        T.expect(Deposits.stab(state, input(10)).ok).toBe(true)
        local early = Deposits.stab(state, input(10 + SHOVEL - Data.stab.slackSeconds - 0.01))
        T.expect(early.reason).toBe("tooSoon")
        T.expect(Deposits.stab(state, input(10 + SHOVEL - Data.stab.slackSeconds + 0.001)).ok).toBe(true)
    end)

    T.it("tooSoon (Vorprüfung im Service) stimmt mit stab überein", function()
        local state = Deposits.newState()
        T.expect(Deposits.tooSoon(state, 10, "shovel")).toBe(false)
        Deposits.stab(state, input(10))
        local early = 10 + SHOVEL - Data.stab.slackSeconds - 0.01
        T.expect(Deposits.tooSoon(state, early, "shovel")).toBe(true)
        T.expect(Deposits.stab(state, input(early)).reason).toBe("tooSoon")
        T.expect(Deposits.tooSoon(state, 10 + SHOVEL, "shovel")).toBe(false)
    end)

    T.it("über viele Stiche höchstens einer je Takt, auch wenn jeder etwas zu früh kommt", function()
        local state = Deposits.newState()
        local accepted = 0
        local t = 0
        local stepEarly = SHOVEL - Data.stab.slackSeconds * 0.5
        for _ = 1, 200 do
            if Deposits.stab(state, input(t, { point = { x = 6, y = 0, z = (accepted % 5) * 8 } })).ok then
                accepted += 1
            end
            t += stepEarly
        end
        -- In der Zeit t passen höchstens t / Takt + 1 Stiche (plus der Spielraum einmal).
        T.expect(accepted <= math.floor((t + Data.stab.slackSeconds) / SHOVEL) + 1).toBe(true)
    end)

    T.it("Tank voll: kein Sand, Zelle wird nicht verbraucht, Takt nicht gezählt", function()
        local state = Deposits.newState()
        local result = Deposits.stab(state, input(10, { space = 0 }))
        T.expect(result.reason).toBe("full")
        T.expect(result.full).toBe(true)
        T.expect(state.count).toBe(0)
        T.expect(state.lastStabAt).toBeNil()
    end)

    T.it("Tank läuft voll: Menge gekappt, Bruchteil verfällt", function()
        local state = Deposits.newState()
        local result = Deposits.stab(state, input(10, { space = 3, rate = 1000 }))
        T.expect(result.ok).toBe(true)
        T.expect(result.added).toBe(3)
        T.expect(result.full).toBe(true)
        T.expect(state.carry).toBe(0)
    end)
end)

T.describe("Deposits: Schichten", function()
    T.it("nach 4 Stichen Schicht 2, nach 10 Schicht 3, nach 18 leer", function()
        local state = Deposits.newState()
        local results = stabMany(state, 0, Deposits.totalStabs() + 1)
        T.expect(results[1].layer).toBe(1)
        T.expect(results[4].layer).toBe(1)
        T.expect(results[5].layer).toBe(2)
        T.expect(results[10].layer).toBe(2)
        T.expect(results[11].layer).toBe(3)
        T.expect(results[18].layer).toBe(3)
        T.expect(results[18].emptyNow).toBe(true)
        T.expect(results[17].emptyNow).toBe(false)
        T.expect(results[19].reason).toBe("empty")
        T.expect(Deposits.totalStabs()).toBe(18)
    end)

    T.it("die Menge folgt dem Faktor der Schicht", function()
        local state = Deposits.newState()
        local results = stabMany(state, 0, 18, { rate = 1000 })
        -- Saubere Stiche ab dem zweiten: Menge = Rate * Takt * Schicht-Faktor
        local base = 1000 * SHOVEL * Data.stab.cleanFactor
        T.expect(results[2].clean).toBe(true)
        T.expect(math.abs(results[2].added - base * Data.layers[1].factor) <= 1).toBe(true)
        T.expect(math.abs(results[6].added - base * Data.layers[2].factor) <= 1).toBe(true)
        T.expect(math.abs(results[12].added - base * Data.layers[3].factor) <= 1).toBe(true)
    end)

    T.it("Nachbarzelle ist voll, auch wenn eine Zelle leer ist", function()
        local state = Deposits.newState()
        local _, t = stabMany(state, 0, 18)
        T.expect(Deposits.stab(state, input(t)).reason).toBe("empty")
        local neighbor = Deposits.stab(state, input(t, { point = { x = 6, y = 0, z = Data.cellStuds } }))
        T.expect(neighbor.ok).toBe(true)
        T.expect(neighbor.layer).toBe(1)
    end)

    T.it("leere Zelle ist nach der Auffüllzeit wieder voll, vorher nicht", function()
        local state = Deposits.newState()
        local _, t = stabMany(state, 0, 18)
        local lastAt = t - SHOVEL
        T.expect(Deposits.stab(state, input(lastAt + Data.refillSeconds - 1)).reason).toBe("empty")
        local refilled = Deposits.stab(state, input(lastAt + Data.refillSeconds))
        T.expect(refilled.ok).toBe(true)
        T.expect(refilled.layer).toBe(1)
    end)

    T.it("ein leerer Stich verlängert das Auffüllen nicht", function()
        local state = Deposits.newState()
        local _, t = stabMany(state, 0, 18)
        local lastAt = t - SHOVEL
        for k = 1, 10 do
            Deposits.stab(state, input(lastAt + k * 5))
        end
        T.expect(Deposits.stab(state, input(lastAt + Data.refillSeconds)).ok).toBe(true)
    end)
end)

T.describe("Deposits: Takt und Halten", function()
    T.it("sauberer Stich nur im Fenster nach dem Takt, nicht davor und nicht danach", function()
        local state = Deposits.newState()
        T.expect(Deposits.stab(state, input(0)).clean).toBe(false) -- erster Stich: kein Takt davor
        T.expect(Deposits.stab(state, input(SHOVEL)).clean).toBe(true)
        local t = SHOVEL * 2 + Data.stab.cleanWindowSeconds
        T.expect(Deposits.stab(state, input(t)).clean).toBe(true)
        local late = t + SHOVEL + Data.stab.cleanWindowSeconds + 0.01
        T.expect(Deposits.stab(state, input(late)).clean).toBe(false)
    end)

    T.it("Halten: Stiche im Takt, nie mit Bonus, Menge mit plainFactor", function()
        local state = Deposits.newState()
        local results = stabMany(state, 0, 4, { held = true, rate = 1000 })
        for _, r in results do
            T.expect(r.ok).toBe(true)
            T.expect(r.clean).toBe(false)
        end
        T.expect(math.abs(results[2].added - 1000 * SHOVEL * Data.stab.plainFactor) <= 1).toBe(true)
    end)

    T.it("Bruchteile werden mitgenommen (Hand: halbes Korn je Stich)", function()
        local state = Deposits.newState()
        local hand = Deposits.stabSeconds("hand")
        local total = 0
        for k = 0, 3 do
            local r = Deposits.stab(state, input(k * hand, { held = true, toolId = "hand", rate = 1 }))
            T.expect(r.ok).toBe(true)
            total += r.added
        end
        T.expect(total).toBe(math.floor(4 * hand * Data.stab.plainFactor))
    end)

    T.it("Fundzeit: ein Takt je angenommenem Stich, 0 bei Ablehnung", function()
        local state = Deposits.newState()
        T.expect(Deposits.stab(state, input(0)).seconds).toBe(SHOVEL)
        T.expect(Deposits.stab(state, input(0.01)).seconds).toBe(0)
    end)

    T.it("isDigging: kurz nach einem Stich an, danach aus", function()
        local state = Deposits.newState()
        T.expect(Deposits.isDigging(state, 0)).toBe(false)
        Deposits.stab(state, input(10))
        T.expect(Deposits.isDigging(state, 10 + SHOVEL)).toBe(true)
        T.expect(Deposits.isDigging(state, 10 + SHOVEL * Data.diggingHoldTakts + 0.01)).toBe(false)
    end)
end)

T.describe("Deposits: Speicher", function()
    T.it("höchstens maxTrackedCells Zellen, aufgefüllte und älteste fliegen raus", function()
        local data = table.clone(Data)
        data.maxTrackedCells = 5
        local state = Deposits.newState()
        local t = 0
        for k = 1, 12 do
            local point = { x = 6, y = 0, z = k * data.cellStuds }
            T.expect(Deposits.stab(state, input(t, { point = point, reachMax = 1000 }), data).ok).toBe(true)
            t += SHOVEL
        end
        T.expect(state.count).toBe(5)
        local keys = 0
        for _ in state.cells do
            keys += 1
        end
        T.expect(keys).toBe(5)
    end)
end)

T.describe("Deposits: Remote Stab", function()
    T.it("hat kein Mengen-Argument, nur Punkt und Halten, und ein Limit", function()
        local def = RemoteSpec.byName.Stab
        T.expect(def ~= nil).toBe(true)
        T.expect(#def.schema).toBe(4)
        T.expect(def.limit ~= nil).toBe(true)
        T.expect(select(1, Validate.check(def.schema, { 1.5, 2, -3.25, true }, 4))).toBe(true)
    end)

    T.it("Schema lehnt zusätzliche Argumente, NaN, unendlich, zu große Zahlen und Texte ab", function()
        local schema = RemoteSpec.byName.Stab.schema
        T.expect(select(1, Validate.check(schema, { 1, 2, 3, true, 99 }, 5))).toBe(false)
        T.expect(select(1, Validate.check(schema, { 0 / 0, 2, 3, true }, 4))).toBe(false)
        T.expect(select(1, Validate.check(schema, { math.huge, 2, 3, true }, 4))).toBe(false)
        T.expect(select(1, Validate.check(schema, { Data.coordinateLimit + 1, 2, 3, true }, 4))).toBe(false)
        T.expect(select(1, Validate.check(schema, { "1", 2, 3, true }, 4))).toBe(false)
        T.expect(select(1, Validate.check(schema, { 1, 2, 3, 1 }, 4))).toBe(false)
    end)
end)

T.finish()
