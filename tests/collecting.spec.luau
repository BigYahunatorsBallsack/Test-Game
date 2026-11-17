--!strict
-- Paket 1.2: Sammeln, Tank, Verkaufen (reine Logik mit simulierter Uhr).

local T = require("./lib/expect")
local Collecting = require("../src/shared/Logic/Collecting")
local Profile = require("../src/shared/Logic/Profile")
local BigNum = require("../src/shared/Logic/BigNum")
local Validate = require("../src/shared/Logic/Validate")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local Economy = require("../src/shared/Data/Economy")
local World = require("../src/shared/Data/World")

local NOW = 1_700_000_000
local CAPACITY = Economy.startTankCapacity
local TIMEOUT = Economy.collecting.holdTimeoutSeconds

local function tankOf(profile: any): number
    return BigNum.toNumber(BigNum.deserialize(profile.tank))
end

local function coinsOf(profile: any): BigNum.BigNum
    return BigNum.deserialize(profile.coins)
end

local function fresh(): (any, Collecting.State)
    return Profile.default(NOW), Collecting.newState(NOW)
end

-- Hält `seconds` lang, mit Auffrischung jede Sekunde (wie der Client).
local function holdFor(state: Collecting.State, profile: any, from: number, seconds: number): number
    local t = from
    Collecting.setHolding(state, profile, true, t)
    while t + 1 <= from + seconds do
        t += 1
        Collecting.setHolding(state, profile, true, t)
    end
    if t < from + seconds then
        t = from + seconds
        Collecting.update(state, profile, t)
    end
    return t
end

T.describe("Sand aus Zeit und Rate", function()
    T.it("Hand: 3 s halten ergibt 3 Sand", function()
        local profile, state = fresh()
        Collecting.setHolding(state, profile, true, NOW)
        Collecting.update(state, profile, NOW + 1)
        Collecting.setHolding(state, profile, true, NOW + 1)
        Collecting.update(state, profile, NOW + 2)
        Collecting.setHolding(state, profile, true, NOW + 2)
        Collecting.setHolding(state, profile, false, NOW + 3)
        T.expect(tankOf(profile)).toBe(3)
    end)

    T.it("Schaufel (collect_tool_2): 5 Sand pro Sekunde", function()
        local profile, state = fresh()
        profile.nodes.collect_tool_2 = true
        T.expect(Collecting.rateOf(profile)).toBe(5)
        Collecting.setHolding(state, profile, true, NOW)
        Collecting.setHolding(state, profile, false, NOW + 2)
        T.expect(tankOf(profile)).toBe(10)
    end)

    T.it("höchstes gekauftes Werkzeug zählt, unbekannte Knoten nicht", function()
        local profile = Profile.default(NOW)
        profile.nodes.collect_tool_2 = true
        profile.nodes.collect_tool_3 = true
        profile.nodes.collect_tool_99 = true
        profile.nodes.unbekannt = true
        T.expect(Collecting.toolOf(profile).id).toBe("bucket_chain")
        profile.nodes.collect_tool_3 = false
        T.expect(Collecting.toolOf(profile).id).toBe("shovel")
    end)
end)

T.describe("Client kann keine Mengen melden", function()
    local def = RemoteSpec.byName.SetCollecting
    local schema = def.schema :: { Validate.Rule }

    T.it("SetCollecting nimmt nur einen Wahrheitswert", function()
        T.expect((Validate.check(schema, { true }, 1))).toBe(true)
        T.expect((Validate.check(schema, { 1e9 }, 1))).toBe(false)
        T.expect((Validate.check(schema, { true, 1e9 }, 2))).toBe(false)
        T.expect((Validate.check(schema, { "1000000" }, 1))).toBe(false)
    end)

    T.it("Sell nimmt keine Argumente", function()
        local sellSchema = RemoteSpec.byName.Sell.schema :: { Validate.Rule }
        T.expect((Validate.check(sellSchema, {}, 0))).toBe(true)
        T.expect((Validate.check(sellSchema, { 1e9 }, 1))).toBe(false)
    end)

    T.it("viele SetCollecting(true) in kurzer Zeit erzeugen nicht mehr Sand", function()
        local profile, state = fresh()
        for i = 0, 100 do
            Collecting.setHolding(state, profile, true, NOW + i * 0.01)
        end
        Collecting.setHolding(state, profile, false, NOW + 1)
        T.expect(tankOf(profile)).toBe(1)
    end)
end)

T.describe("Halten und Loslassen", function()
    T.it("ohne Halten entsteht kein Sand", function()
        local profile, state = fresh()
        Collecting.update(state, profile, NOW + 100)
        T.expect(tankOf(profile)).toBe(0)
    end)

    T.it("nach dem Loslassen zählt die Zeit nicht, nach erneutem Halten wieder", function()
        local profile, state = fresh()
        Collecting.setHolding(state, profile, true, NOW)
        Collecting.setHolding(state, profile, false, NOW + 2)
        Collecting.update(state, profile, NOW + 50)
        T.expect(tankOf(profile)).toBe(2)
        Collecting.setHolding(state, profile, true, NOW + 50)
        Collecting.setHolding(state, profile, false, NOW + 52)
        T.expect(tankOf(profile)).toBe(4)
    end)

    T.it("Bruchteile gehen nicht verloren, der Tank enthält ganze Körner", function()
        local profile, state = fresh()
        Collecting.setHolding(state, profile, true, NOW)
        Collecting.update(state, profile, NOW + 0.5)
        T.expect(tankOf(profile)).toBe(0)
        Collecting.update(state, profile, NOW + 1)
        T.expect(tankOf(profile)).toBe(1)
    end)

    T.it("ohne Auffrischung zählt nur die Zeit bis zur Frist", function()
        local profile, state = fresh()
        profile.nodes.collect_tool_2 = true -- 5 pro s, Tank reicht für 3 s
        Collecting.setHolding(state, profile, true, NOW)
        Collecting.update(state, profile, NOW + 60)
        T.expect(tankOf(profile)).toBe(math.floor(5 * TIMEOUT))
        T.expect(state.holding).toBe(false)
    end)

    T.it("eine rückwärts springende Uhr erzeugt keinen Sand", function()
        local profile, state = fresh()
        Collecting.setHolding(state, profile, true, NOW)
        local r = Collecting.update(state, profile, NOW - 1000)
        T.expect(r.added).toBe(0)
        T.expect(tankOf(profile)).toBe(0)
        Collecting.setHolding(state, profile, true, NOW - 1000)
        Collecting.update(state, profile, NOW - 999)
        T.expect(tankOf(profile)).toBe(1)
    end)
end)

T.describe("Voller Tank", function()
    T.it("100 s halten füllt genau bis zur Kapazität und meldet voll", function()
        local profile, state = fresh()
        local t = holdFor(state, profile, NOW, 100)
        T.expect(tankOf(profile)).toBe(CAPACITY)
        T.expect(state.holding).toBe(false)
        local r = Collecting.setHolding(state, profile, true, t)
        T.expect(r.full).toBe(true)
        T.expect(state.holding).toBe(false)
        Collecting.update(state, profile, t + 100)
        T.expect(tankOf(profile)).toBe(CAPACITY)
    end)

    T.it("der Schritt, der den Tank füllt, meldet voll", function()
        local profile, state = fresh()
        profile.tank = BigNum.serialize(BigNum.new(CAPACITY - 1))
        Collecting.setHolding(state, profile, true, NOW)
        local r = Collecting.update(state, profile, NOW + 2)
        T.expect(r.added).toBe(1)
        T.expect(r.full).toBe(true)
    end)

    T.it("Kapazitätsfaktor (Großer Tank) verdoppelt", function()
        local profile = Profile.default(NOW)
        T.expect(Collecting.capacityOf(profile, { capacityMultiplier = Economy.bigTankMultiplier })).toBe(CAPACITY * 2)
    end)
end)

T.describe("Verkaufen", function()
    T.it("leert den Tank und bucht Münzen nach Sandsorte (Dünen x1, Oase x3)", function()
        local profile, state = fresh()
        profile.tank = BigNum.serialize(BigNum.new(10))
        local earned = Collecting.sell(state, profile, NOW)
        T.expect(BigNum.toNumber(earned :: any)).toBe(10)
        T.expect(tankOf(profile)).toBe(0)
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(10)

        profile.currentZone = "oasis"
        profile.tank = BigNum.serialize(BigNum.new(10))
        Collecting.sell(state, profile, NOW)
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(40)
    end)

    T.it("leerer Tank bucht nichts", function()
        local profile, state = fresh()
        local earned = Collecting.sell(state, profile, NOW)
        T.expect(earned).toBeNil()
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(0)
    end)

    T.it("rechnet laufendes Sammeln bis jetzt ab, bevor verkauft wird", function()
        local profile, state = fresh()
        Collecting.setHolding(state, profile, true, NOW)
        Collecting.sell(state, profile, NOW + 2)
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(2)
        T.expect(tankOf(profile)).toBe(0)
    end)

    T.it("addiert über den Zahlentyp auf große Münzstände", function()
        local profile, state = fresh()
        profile.coins = BigNum.serialize(BigNum.new(1.5, 20))
        profile.tank = BigNum.serialize(BigNum.new(10))
        Collecting.sell(state, profile, NOW)
        local coins = coinsOf(profile)
        T.expect(coins.e).toBe(20)
        T.expect(coins.m).toBeCloseTo(1.5, 1e-12)

        profile.coins = BigNum.serialize(BigNum.new(2, 18))
        profile.tank = BigNum.serialize(BigNum.new(3, 17))
        profile.currentZone = "ruins" -- x150
        Collecting.sell(state, profile, NOW)
        local big = coinsOf(profile)
        -- 2e18 + 3e17 * 150 = 4,7e19
        T.expect(big.e).toBe(19)
        T.expect(big.m).toBeCloseTo(4.7, 1e-9)
    end)

    T.it("ungültige Zone fällt auf das Dünenmeer zurück", function()
        local profile, state = fresh()
        profile.currentZone = "gibt_es_nicht"
        profile.tank = BigNum.serialize(BigNum.new(7))
        Collecting.sell(state, profile, NOW)
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(7)
    end)

    T.it("nur in Reichweite des Händlerstands", function()
        local range = World.sellStand.rangeStuds
        T.expect(Collecting.inRange(0, 0, 0, range)).toBe(true)
        T.expect(Collecting.inRange(range, 0, 0, range)).toBe(true)
        T.expect(Collecting.inRange(range, 1, 0, range)).toBe(false)
        T.expect(Collecting.inRange(0 / 0, 0, 0, range)).toBe(false)
    end)
end)

T.describe("BigNum-Rechnen (Paket 1.2)", function()
    T.it("add, sub, mulNumber, compare, floor, toNumber für kleine Werte", function()
        local a, b = BigNum.new(123), BigNum.new(77)
        T.expect(BigNum.toNumber(BigNum.add(a, b))).toBeCloseTo(200, 1e-9)
        T.expect(BigNum.toNumber(BigNum.sub(a, b))).toBeCloseTo(46, 1e-9)
        T.expect(BigNum.toNumber(BigNum.sub(b, a))).toBeCloseTo(-46, 1e-9)
        T.expect(BigNum.toNumber(BigNum.mulNumber(a, 3))).toBeCloseTo(369, 1e-9)
        T.expect(BigNum.compare(a, b)).toBe(1)
        T.expect(BigNum.compare(b, a)).toBe(-1)
        T.expect(BigNum.compare(a, BigNum.new(123))).toBe(0)
        T.expect(BigNum.toNumber(BigNum.floor(BigNum.new(12.7)))).toBe(12)
        T.expect(BigNum.toNumber(BigNum.add(BigNum.zero(), a))).toBeCloseTo(123, 1e-9)
    end)

    T.it("über 10^15", function()
        local a = BigNum.new(5, 30)
        local b = BigNum.new(5, 30)
        local sum = BigNum.add(a, b)
        T.expect(sum.e).toBe(31)
        T.expect(sum.m).toBeCloseTo(1, 1e-12)
        -- Ein winziger Summand fällt unter die Genauigkeit und ändert nichts.
        T.expect(BigNum.eq(BigNum.add(a, BigNum.new(1)), a)).toBe(true)
        T.expect(BigNum.lt(BigNum.new(9.99, 40), BigNum.new(1, 41))).toBe(true)
        local product = BigNum.mulNumber(BigNum.new(2, 300), 5e10)
        T.expect(product.e).toBe(311)
        T.expect(product.m).toBeCloseTo(1, 1e-12)
        T.expect(BigNum.eq(BigNum.floor(a), a)).toBe(true)
        T.expect(BigNum.compare(BigNum.new(-1, 20), BigNum.new(1, 2))).toBe(-1)
    end)
end)

T.describe("Datenprüfung (Paket 1.2)", function()
    local DataCheck = require("../src/shared/Logic/DataCheck")

    T.it("die echten Tabellen bestehen", function()
        T.expect(#DataCheck.run()).toBe(0)
    end)

    T.it("kaputte Sammel-Frist oder Händler-Reichweite fallen auf", function()
        local data: any = DataCheck.defaults()
        local economy = table.clone(data.Economy)
        economy.collecting = { holdRefreshSeconds = 1, holdTimeoutSeconds = 0.5 }
        data.Economy = economy
        T.expect(#DataCheck.run(data) > 0).toBe(true)

        local data2: any = DataCheck.defaults()
        data2.World = { sellStand = { tag = "SellStand", placeholderPosition = { x = 0, y = 0, z = 0 }, rangeStuds = 5, promptDistanceStuds = 10 } }
        T.expect(#DataCheck.run(data2) > 0).toBe(true)
    end)
end)

T.finish()
