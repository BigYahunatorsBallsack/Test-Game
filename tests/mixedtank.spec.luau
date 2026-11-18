--!strict
-- Paket 2.5: Gemischter Tank (Sand je Sandsorte), Zonenwechsel beim Sammeln, Migration.

local T = require("./lib/expect")
local Collecting = require("../src/shared/Logic/Collecting")
local Profile = require("../src/shared/Logic/Profile")
local Migrations = require("../src/shared/Logic/Migrations")
local BigNum = require("../src/shared/Logic/BigNum")
local Economy = require("../src/shared/Data/Economy")
local SandTypes = require("../src/shared/Data/SandTypes")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local PlayerSession = require("../src/shared/Logic/PlayerSession")
local FakeStore = require("./lib/fakestore")

local NOW = 1_700_000_000

local function fresh(): (any, Collecting.State)
    local profile: any = Profile.default(NOW)
    -- Größter Tank, damit die Tests nicht an der Kapazität scheitern.
    for _, node in UpgradeTree.list do
        if node.effect.kind == "setTank" then
            profile.nodes[node.id] = true
        end
    end
    return profile, Collecting.newState(NOW)
end

local function mixNumber(profile: any, typeId: string): number
    return BigNum.toNumber(BigNum.deserialize(profile.tankMix[typeId]))
end

local function tankNumber(profile: any): number
    return BigNum.toNumber(BigNum.deserialize(profile.tank))
end

local function coinsNumber(profile: any): number
    return BigNum.toNumber(BigNum.deserialize(profile.coins))
end

-- Sammelt `grains` Sand in der aktuellen Zone (Hand: 1 Sand pro Sekunde), gibt die neue Zeit zurück.
local function collect(state: Collecting.State, profile: any, from: number, grains: number): number
    local t = from
    Collecting.setHolding(state, profile, true, t)
    for _ = 1, grains do
        t += 1
        Collecting.setHolding(state, profile, true, t)
    end
    Collecting.setHolding(state, profile, false, t)
    return t
end

T.describe("Sand je Sandsorte", function()
    T.it("gesammelter Sand landet in der Sorte der aktuellen Zone, die Summe stimmt mit dem Tank", function()
        local profile, state = fresh()
        collect(state, profile, NOW, 6)
        T.expect(tankNumber(profile)).toBe(6)
        T.expect(mixNumber(profile, "yellow")).toBe(6)
        T.expect(profile.tankMix.red).toBeNil()
    end)

    T.it("100 Sand im Dünenmeer, Wechsel zur Oase, 100 Sand dort: Verkauf zahlt 100 x 1 plus 100 x 3", function()
        local profile, state = fresh()
        profile.nodes.collect_tool_2 = true
        profile.nodes.collect_rate_1 = true
        -- Schaufel: 5 Sand pro Sekunde, Rate-Bonus ignorieren wir, indem wir Sand direkt zählen lassen.
        profile.nodes.collect_rate_1 = nil
        local t = collect(state, profile, NOW, 20) -- 100 Sand
        T.expect(tankNumber(profile)).toBe(100)
        Collecting.setZone(state, profile, "oasis", t)
        t = collect(state, profile, t, 20)
        T.expect(tankNumber(profile)).toBe(200)
        T.expect(mixNumber(profile, "yellow")).toBe(100)
        T.expect(mixNumber(profile, "red")).toBe(100)
        local earned = Collecting.sell(state, profile, t)
        local factorYellow = SandTypes.byId.yellow.priceFactor
        local factorRed = SandTypes.byId.red.priceFactor
        T.expect(BigNum.toNumber(earned :: any)).toBe(Economy.baseCoinsPerSand * (100 * factorYellow + 100 * factorRed))
        T.expect(coinsNumber(profile)).toBe(Economy.baseCoinsPerSand * (100 * factorYellow + 100 * factorRed))
        T.expect(tankNumber(profile)).toBe(0)
        T.expect(next(profile.tankMix)).toBeNil()
    end)

    T.it("der Preis hängt nicht vom Stand ab: Dünensand in der Ruinenstadt verkaufen bringt Dünenpreis", function()
        local profile, state = fresh()
        local t = collect(state, profile, NOW, 10)
        Collecting.setZone(state, profile, "ruins", t) -- Spieler steht jetzt in der Ruinenstadt
        local earned = Collecting.sell(state, profile, t)
        T.expect(BigNum.toNumber(earned :: any)).toBe(10 * Economy.baseCoinsPerSand * SandTypes.byId.yellow.priceFactor)
    end)

    T.it("die Tankgröße zählt die Summe aller Sorten", function()
        local profile, state = fresh()
        profile.nodes = {}
        local capacity = Collecting.capacityOf(profile)
        local t = collect(state, profile, NOW, 5)
        Collecting.setZone(state, profile, "oasis", t)
        t = collect(state, profile, t, capacity) -- will mehr, als hineinpasst
        T.expect(tankNumber(profile)).toBe(capacity)
        T.expect(mixNumber(profile, "yellow") + mixNumber(profile, "red")).toBe(capacity)
        T.expect(Collecting.isFull(profile)).toBe(true)
    end)

    T.it("Zonenwechsel während des Sammelns: erst mit der alten Sorte abrechnen, dann die neue", function()
        local profile, state = fresh()
        Collecting.setHolding(state, profile, true, NOW)
        -- 4 Sekunden in den Dünen (der Client hat zuletzt bei NOW + 1 aufgefrischt), dann Wechsel bei NOW + 4.
        Collecting.setHolding(state, profile, true, NOW + 1)
        Collecting.setHolding(state, profile, true, NOW + 2)
        Collecting.setHolding(state, profile, true, NOW + 3)
        local result = Collecting.setZone(state, profile, "oasis", NOW + 4)
        T.expect(result.added).toBe(1) -- die letzte Sekunde (3 bis 4) zählt noch nach Dünen
        T.expect(mixNumber(profile, "yellow")).toBe(4)
        T.expect(profile.currentZone).toBe("oasis")
        Collecting.setHolding(state, profile, true, NOW + 4)
        Collecting.update(state, profile, NOW + 6)
        T.expect(mixNumber(profile, "yellow")).toBe(4)
        T.expect(mixNumber(profile, "red")).toBe(2)
        T.expect(tankNumber(profile)).toBe(6)
    end)

    T.it("Sand ohne Eintrag im Mix (alte Daten, Debug-Werte) zählt zum Preis der aktuellen Zone", function()
        local profile, state = fresh()
        profile.tank = BigNum.serialize(BigNum.new(40))
        profile.tankMix = {}
        profile.currentZone = "canyon"
        local earned = Collecting.sell(state, profile, NOW)
        T.expect(BigNum.toNumber(earned :: any)).toBe(40 * Economy.baseCoinsPerSand * SandTypes.byId.white.priceFactor)
    end)

    T.it("unbekannte Sorte und kaputte Werte im Mix werden nicht bezahlt, der Rest schon", function()
        local profile, state = fresh()
        profile.tank = BigNum.serialize(BigNum.new(30))
        profile.tankMix = { yellow = { m = 2, e = 1 }, gibt_es_nicht = { m = 5, e = 0 }, red = { m = "x", e = 0 } }
        -- yellow 20 Sand zu Preis 1, gibt_es_nicht (5) und red (kaputt) zählen nicht im Mix,
        -- der Rest (30 - 20 = 10) wird zum Preis der aktuellen Zone (Dünenmeer) bezahlt.
        local earned = Collecting.sell(state, profile, NOW)
        T.expect(BigNum.toNumber(earned :: any)).toBe(30 * Economy.baseCoinsPerSand * SandTypes.byId.yellow.priceFactor)
    end)

    T.it("leerer Tank: nichts zu verkaufen", function()
        local profile, state = fresh()
        local earned = Collecting.sell(state, profile, NOW)
        T.expect(earned).toBeNil()
    end)

    T.it("der Verkauf-Ast wirkt auf jede Sorte", function()
        local profile, state = fresh()
        profile.nodes.sell_1 = true
        local base = Collecting.priceOf(profile, "yellow")
        T.expect(base > Economy.baseCoinsPerSand * 1).toBe(true)
        T.expect(Collecting.priceOf(profile, "red")).toBeCloseTo(base * 3, 1e-9)
        T.expect(Collecting.priceOf(profile, "gibt_es_nicht")).toBe(0)
    end)
end)

T.describe("Migration auf Version 2", function()
    local function v1Profile(zone: string, tank: any): any
        local profile: any = Profile.default(NOW)
        profile.version = 1
        profile.tankMix = nil
        profile.currentZone = zone
        profile.tank = tank
        return profile
    end

    T.it("alter Tank 500 in der Oase wird zu 500 rotem Sand", function()
        local migrated, status = Profile.migrate(v1Profile("oasis", { m = 5, e = 2 }), nil, NOW)
        local profile: any = migrated
        T.expect(status).toBe("ok")
        T.expect(profile.version).toBe(Migrations.CURRENT_VERSION)
        T.expect(profile.tank).toEqual({ m = 5, e = 2 })
        T.expect(profile.tankMix).toEqual({ red = { m = 5, e = 2 } })
    end)

    T.it("leerer Tank bleibt leer, unbekannte Zone fällt auf Gelb", function()
        local empty: any = Profile.migrate(v1Profile("oasis", { m = 0, e = 0 }), nil, NOW)
        T.expect(empty.tankMix).toEqual({})
        local odd: any = Profile.migrate(v1Profile("gibt_es_nicht", { m = 3, e = 1 }), nil, NOW)
        T.expect(odd.tankMix).toEqual({ yellow = { m = 3, e = 1 } })
    end)

    T.it("kaputter Tank wird nicht in den Mix kopiert", function()
        local profile: any = Profile.migrate(v1Profile("oasis", { m = 0 / 0, e = 1 }), nil, NOW)
        T.expect(profile.tankMix).toEqual({})
    end)

    T.it("eine zweite Migration ändert nichts mehr", function()
        local first = Profile.migrate(v1Profile("canyon", { m = 7, e = 1 }), nil, NOW)
        local second, status = Profile.migrate(first, nil, NOW + 999)
        T.expect(status).toBe("ok")
        T.expect(second).toEqual(first)
    end)

    T.it("Speichern und Laden über den Fake-Speicher: Tank und Mix bleiben gleich, der Verkauf zahlt gleich", function()
        local world = FakeStore.newWorld()
        local key = PlayerSession.keyFor(77)
        world.saved[key] = v1Profile("white_zone_gibt_es_nicht", { m = 2, e = 1 })
        local clock = { time = NOW }
        local function server(name: string): any
            return PlayerSession.new({
                store = FakeStore.newServer(world, name),
                now = function()
                    return clock.time
                end,
                kick = function() end,
                log = function() end,
            })
        end
        local a: any = server("A")
        local profile: any = a.load(77, function()
            return true
        end)
        T.expect(profile.version).toBe(2)
        T.expect(profile.tankMix).toEqual({ yellow = { m = 2, e = 1 } })
        -- Der Spieler sammelt in der Oase weiter und speichert.
        local state = Collecting.newState(NOW)
        profile.currentZone = "oasis"
        profile.nodes.tank_1 = true
        collect(state, profile, NOW, 5)
        a.release(77)
        local b: any = server("B")
        local again: any = b.load(77, function()
            return true
        end)
        T.expect(again.tank).toEqual(profile.tank)
        T.expect(again.tankMix).toEqual(profile.tankMix)
        local earned = Collecting.sell(Collecting.newState(NOW), again, NOW)
        T.expect(BigNum.toNumber(earned :: any)).toBe(20 * 1 + 5 * 3)
    end)

    T.it("Profile.sanitize entfernt kaputte Zahlen im Mix, der Rest bleibt, kaputter Sand zählt als 0", function()
        local profile: any = Profile.default(NOW)
        profile.tankMix = { yellow = { m = 1, e = 1 }, red = { m = 0 / 0, e = 0 } }
        Profile.sanitize(profile, NOW)
        T.expect(profile.tankMix.yellow).toEqual({ m = 1, e = 1 })
        T.expect(BigNum.deserialize(profile.tankMix.red)).toEqual({ m = 0, e = 0 })
    end)
end)

T.finish()
