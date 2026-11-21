--!strict
-- Paket 2.6: Fundstücke auswürfeln (Chance, Seltenheit, Auswahl, Wert, erster Fund sicher) und die
-- Sammelzeit, die Collecting dafür liefert.

local T = require("./lib/expect")
local FindRoll = require("../src/shared/Logic/FindRoll")
local Collecting = require("../src/shared/Logic/Collecting")
local Collection = require("../src/shared/Logic/Collection")
local Profile = require("../src/shared/Logic/Profile")
local BigNum = require("../src/shared/Logic/BigNum")
local FindOdds = require("../src/shared/Data/FindOdds")
local Finds = require("../src/shared/Data/Finds")
local Rarities = require("../src/shared/Data/Rarities")
local WeatherData = require("../src/shared/Data/Weather")
local Economy = require("../src/shared/Data/Economy")

local NOW = 1_700_000_000

local function deepCopy(value: any, memo: { [any]: any }?): any
    if type(value) ~= "table" then
        return value
    end
    local seen = memo or {}
    if seen[value] ~= nil then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, inner in value do
        copy[deepCopy(key, seen)] = deepCopy(inner, seen)
    end
    return copy
end

local function fresh(): any
    return Profile.default(NOW)
end

-- Zufall aus einer festen Liste (danach immer 0,5).
local function sequence(values: { number }): () -> number
    local index = 0
    return function(): number
        index += 1
        return values[index] or 0.5
    end
end

local function input(profile: any, zoneId: string, seconds: number, random: () -> number, extra: { [string]: any }?): FindRoll.Input
    local result: any = {
        profile = profile,
        zoneId = zoneId,
        seconds = seconds,
        serverTime = 200, -- in der Oase kein Regen (Zyklus 480, aktiv 0 bis 90)
        sessionSeconds = seconds,
        random = random,
    }
    if extra then
        for key, value in extra do
            result[key] = value
        end
    end
    return result
end

local function rainTime(): number
    return WeatherData.zones.oasis.offsetSeconds + 45 -- mitten im Regen, volle Stärke
end

T.describe("Chance", function()
    T.it("Dünenmeer ohne Glück: findChancePerSecond, in der Oase mal 1,2", function()
        local profile = fresh()
        T.expect(FindRoll.chancePerSecond(profile, "dunes", 200)).toBeCloseTo(FindOdds.findChancePerSecond / 10000, 1e-12)
        T.expect(FindRoll.chancePerSecond(profile, "oasis", 200)).toBeCloseTo(0.02 * 1.2, 1e-12)
        T.expect(FindRoll.chancePerSecond(profile, "ruins", 200)).toBeCloseTo(0.02 * 2, 1e-12)
        T.expect(FindRoll.chancePerSecond(profile, "gibt_es_nicht", 200)).toBe(0)
    end)

    T.it("der Glück-Ast multipliziert die Chance", function()
        local profile = fresh()
        profile.nodes.luck_1 = true -- +10 %
        T.expect(FindRoll.chancePerSecond(profile, "dunes", 200)).toBeCloseTo(0.02 * 1.1, 1e-12)
        profile.nodes.luck_2 = true -- +10 %
        T.expect(FindRoll.chancePerSecond(profile, "dunes", 200)).toBeCloseTo(0.02 * 1.2, 1e-12)
        profile.nodes.unbekannter_knoten = true -- unbekannte Knoten ändern nichts
        T.expect(FindRoll.chancePerSecond(profile, "dunes", 200)).toBeCloseTo(0.02 * 1.2, 1e-12)
    end)

    T.it("Regen in der Oase erhöht die Chance, nur solange er aktiv ist, am Rand anteilig", function()
        local profile = fresh()
        local bonus = WeatherData.zones.oasis.findChanceBonusBp / 10000
        local base = FindRoll.chancePerSecond(profile, "oasis", 200)
        T.expect(FindRoll.chancePerSecond(profile, "oasis", rainTime())).toBeCloseTo(base * (1 + bonus), 1e-12)
        local fading = FindRoll.chancePerSecond(profile, "oasis", WeatherData.zones.oasis.offsetSeconds + WeatherData.fadeSeconds / 2)
        T.expect(fading > base).toBe(true)
        T.expect(fading < base * (1 + bonus)).toBe(true)
        -- Außerhalb des Regens und in Zonen ohne Fundbonus bleibt es bei der Grundchance.
        T.expect(FindRoll.chancePerSecond(profile, "oasis", 300)).toBeCloseTo(base, 1e-12)
        T.expect(FindRoll.chancePerSecond(profile, "canyon", 150)).toBeCloseTo(0.02 * 1.4, 1e-12)
    end)

    T.it("Chance im Fenster: 1 - (1 - p)^t, nie über 100 %, ohne Zeit keine Chance", function()
        T.expect(FindRoll.chanceInWindow(0.02, 10)).toBeCloseTo(1 - 0.98 ^ 10, 1e-12)
        T.expect(FindRoll.chanceInWindow(0.02, 0)).toBe(0)
        T.expect(FindRoll.chanceInWindow(0.02, -4)).toBe(0)
        T.expect(FindRoll.chanceInWindow(0.02, 0 / 0)).toBe(0)
        T.expect(FindRoll.chanceInWindow(0.02, math.huge)).toBe(0)
        T.expect(FindRoll.chanceInWindow(0, 10)).toBe(0)
        T.expect(FindRoll.chanceInWindow(1, 0.001)).toBe(1)
        T.expect(FindRoll.chanceInWindow(5, 1)).toBe(1)
        T.expect(FindRoll.chanceInWindow(0.02, 1e9) <= 1).toBe(true)
    end)

    T.it("kleine Fenster summieren sich zu derselben Chance wie ein großes", function()
        local p = 0.02
        local small = 1
        for _ = 1, 40 do
            small *= 1 - FindRoll.chanceInWindow(p, 0.25)
        end
        T.expect(1 - small).toBeCloseTo(FindRoll.chanceInWindow(p, 10), 1e-9)
    end)
end)

T.describe("Glücks-Boost (5.1)", function()
    local LUCK = Economy.luckBoost.multiplier

    local function boosted(untilTime: number): any
        local profile = fresh()
        profile.boosts.luckUntil = untilTime
        return profile
    end

    T.it("verdoppelt die Chance pro Sekunde, solange er läuft (Uhr unixTime), danach wieder einfach", function()
        local plain = fresh()
        local profile = boosted(NOW + 900)
        local base = FindRoll.chancePerSecond(plain, "dunes", 200, nil, NOW)
        T.expect(LUCK).toBe(2)
        T.expect(FindRoll.chancePerSecond(profile, "dunes", 200, nil, NOW)).toBeCloseTo(base * LUCK, 1e-12)
        T.expect(FindRoll.chancePerSecond(profile, "dunes", 200, nil, NOW + 899)).toBeCloseTo(base * LUCK, 1e-12)
        T.expect(FindRoll.chancePerSecond(profile, "dunes", 200, nil, NOW + 900)).toBeCloseTo(base, 1e-12)
        -- Ohne unixTime zählt serverTime (beide Unix-Sekunden).
        T.expect(FindRoll.chancePerSecond(profile, "dunes", NOW, nil)).toBeCloseTo(base * LUCK, 1e-12)
        T.expect(FindRoll.chancePerSecond(profile, "dunes", NOW + 900, nil)).toBeCloseTo(base, 1e-12)
    end)

    T.it("eigener Faktor: multipliziert mit Glück-Ast, Zone und Wetter, höchstens 1", function()
        local profile = boosted(NOW + 900)
        profile.nodes.luck_1 = true -- +10 %
        T.expect(FindRoll.chancePerSecond(profile, "dunes", 200, nil, NOW)).toBeCloseTo(0.02 * 1.1 * LUCK, 1e-12)
        T.expect(FindRoll.chancePerSecond(profile, "ruins", 200, nil, NOW)).toBeCloseTo(0.02 * 2 * 1.1 * LUCK, 1e-12)
        local bonus = WeatherData.zones.oasis.findChanceBonusBp / 10000
        T.expect(FindRoll.chancePerSecond(profile, "oasis", rainTime(), nil, NOW)).toBeCloseTo(0.02 * 1.2 * 1.1 * LUCK * (1 + bonus), 1e-12)
        local data = { FindOdds = { findChancePerSecond = 8000, zoneFindChanceFactor = FindOdds.zoneFindChanceFactor } }
        T.expect(FindRoll.chancePerSecond(profile, "dunes", 200, data, NOW)).toBe(1)
    end)

    T.it("ändert nur, ob ein Fund fällt, nie Seltenheit, Fundstück oder Wert", function()
        local plain = fresh()
        plain.finds = { [Finds.list[1].id] = 1 } -- kein "Erster Fund sicher"
        local profile = deepCopy(plain)
        profile.boosts.luckUntil = NOW + 900
        -- Zwischen p und 2p: nur mit Boost ein Fund.
        local p = FindRoll.chanceInWindow(FindRoll.chancePerSecond(plain, "dunes", 200, nil, NOW), 1)
        local between = p * 1.5
        T.expect(FindRoll.roll(input(plain, "dunes", 1, sequence({ between, 0.5, 0.5 }), { unixTime = NOW }))).toBeNil()
        T.expect(FindRoll.roll(input(profile, "dunes", 1, sequence({ between, 0.5, 0.5 }), { unixTime = NOW })) ~= nil).toBe(true)
        -- Fällt in beiden ein Fund, ist alles danach gleich (dieselbe Quotentabelle, derselbe Pool).
        math.randomseed(51)
        for _ = 1, 300 do
            local r2, r3 = math.random(), math.random()
            local a = FindRoll.roll(input(plain, "dunes", 1, sequence({ 0, r2, r3 }), { unixTime = NOW }))
            local b = FindRoll.roll(input(profile, "dunes", 1, sequence({ 0, r2, r3 }), { unixTime = NOW }))
            T.expect(a ~= nil).toBe(true)
            T.expect(b).toEqual(a)
        end
    end)
end)

T.describe("Seltenheit und Auswahl", function()
    local odds = FindOdds.tables.base

    T.it("pickRarity folgt den Grenzen der Quotentabelle", function()
        T.expect(FindRoll.pickRarity(odds, 0)).toBe("common")
        T.expect(FindRoll.pickRarity(odds, 0.6999)).toBe("common")
        T.expect(FindRoll.pickRarity(odds, 0.7)).toBe("uncommon")
        T.expect(FindRoll.pickRarity(odds, 0.9199)).toBe("uncommon")
        T.expect(FindRoll.pickRarity(odds, 0.92)).toBe("rare")
        T.expect(FindRoll.pickRarity(odds, 0.9799)).toBe("rare")
        T.expect(FindRoll.pickRarity(odds, 0.98)).toBe("epic")
        T.expect(FindRoll.pickRarity(odds, 0.9959)).toBe("epic")
        T.expect(FindRoll.pickRarity(odds, 0.996)).toBe("legendary")
        T.expect(FindRoll.pickRarity(odds, 0.9995)).toBe("mythic")
        T.expect(FindRoll.pickRarity(odds, 0.999999)).toBe("mythic")
        T.expect(FindRoll.pickRarity(odds, 5)).toBe("mythic") -- außerhalb: auf den Rand gezwungen
        T.expect(FindRoll.pickRarity(odds, -1)).toBe("common")
    end)

    T.it("200.000 Würfe treffen jede Seltenheit innerhalb der Toleranz der Tabelle", function()
        math.randomseed(2026)
        local draws = 200000
        local counts: { [string]: number } = {}
        for _ = 1, draws do
            local id = FindRoll.pickRarity(odds, math.random())
            counts[id] = (counts[id] or 0) + 1
        end
        for _, rarity in Rarities.list do
            local p = odds[rarity.id] / 10000
            local expected = draws * p
            local sigma = math.sqrt(draws * p * (1 - p))
            local got = counts[rarity.id] or 0
            T.expect(math.abs(got - expected) <= 5 * sigma + 1).toBe(true)
        end
    end)

    T.it("Glück ändert nur die Chance, nie die Seltenheit: gleicher Zufall, gleiche Stufe", function()
        local plain = fresh()
        local lucky = fresh()
        for id in { luck_1 = 1, luck_2 = 1, luck_3 = 1, luck_4 = 1, luck_5 = 1, luck_6 = 1 } do
            lucky.nodes[id] = true
        end
        -- 0,0 für die Chance (immer ein Treffer), 0,95 für die Seltenheit, 0,3 für die Auswahl.
        local a = FindRoll.roll(input(plain, "dunes", 5, sequence({ 0, 0.95, 0.3 }))) :: FindRoll.Roll
        local b = FindRoll.roll(input(lucky, "dunes", 5, sequence({ 0, 0.95, 0.3 }))) :: FindRoll.Roll
        T.expect(a.rarityId).toBe("rare")
        T.expect(b.rarityId).toBe("rare")
        T.expect(a.find.id).toBe(b.find.id)
    end)

    T.it("pickFind: der Fund kommt aus der Zone und hat die Seltenheit, gleich verteilt", function()
        for _, zoneId in { "dunes", "oasis", "canyon", "salt_lake", "ruins" } do
            for _, rarity in Rarities.list do
                local seen: { [string]: number } = {}
                for step = 0, 99 do
                    local find = FindRoll.pickFind(zoneId, rarity.id, step / 100)
                    T.expect(find ~= nil).toBe(true)
                    T.expect(find.zoneId).toBe(zoneId)
                    T.expect(find.rarityId).toBe(rarity.id)
                    seen[find.id] = (seen[find.id] or 0) + 1
                end
                local distinct, minCount, maxCount = 0, math.huge, 0
                for _, count in seen do
                    distinct += 1
                    minCount = math.min(minCount, count)
                    maxCount = math.max(maxCount, count)
                end
                local available = 0
                for _, find in Finds.list do
                    if find.zoneId == zoneId and find.rarityId == rarity.id then
                        available += 1
                    end
                end
                T.expect(distinct).toBe(available) -- jeder Fund der Zone mit dieser Stufe kommt vor
                T.expect(maxCount - minCount <= 100 / available + 1).toBe(true)
            end
        end
    end)

    T.it("fehlt eine Seltenheit in der Zone, kommt die nächst tiefere", function()
        local data: any = { Finds = deepCopy(Finds), Rarities = Rarities }
        local kept = {}
        for _, find in data.Finds.list do
            if not (find.zoneId == "dunes" and (find.rarityId == "mythic" or find.rarityId == "legendary")) then
                table.insert(kept, find)
            end
        end
        data.Finds.list = kept
        T.expect(FindRoll.pickFind("dunes", "mythic", 0.5, data).rarityId).toBe("epic")
        -- Gar keine Funde in der Zone: nichts.
        T.expect(FindRoll.pickFind("zone_ohne_funde", "common", 0.5, data)).toBeNil()
        T.expect(FindRoll.pickFind("dunes", "gibt_es_nicht", 0.5, data)).toBeNil()
    end)
end)

T.describe("Wert", function()
    T.it("Wert = findBaseValue x Sandfaktor x Werkzeug-Grundrate x Wertfaktor", function()
        T.expect(BigNum.toNumber(FindRoll.valueOf("dunes", "common", 1))).toBe(3)
        T.expect(BigNum.toNumber(FindRoll.valueOf("oasis", "rare", 5))).toBe(3 * 3 * 5 * 15)
        T.expect(BigNum.toNumber(FindRoll.valueOf("ruins", "mythic", 6000))).toBe(3 * 150 * 6000 * 1500)
        T.expect(BigNum.toNumber(FindRoll.valueOf("dunes", "gibt_es_nicht", 1))).toBe(0)
        T.expect(BigNum.toNumber(FindRoll.valueOf("zone_x", "common", 1))).toBe(0)
        T.expect(BigNum.toNumber(FindRoll.valueOf("dunes", "common", 0 / 0))).toBe(0)
    end)

    T.it("der Wert nutzt das Werkzeug beim Fund und keine Knoten-Boni", function()
        local hand = fresh()
        local boosted = fresh()
        boosted.nodes.collect_rate_1 = true -- +50 % Sand pro Sekunde, wirkt nicht auf den Fundwert
        local shovel = fresh()
        shovel.nodes.collect_tool_2 = true
        local random = { 0, 0, 0 } -- Treffer, gewöhnlich, erster Fund
        local a = FindRoll.roll(input(hand, "dunes", 5, sequence(random))) :: FindRoll.Roll
        local b = FindRoll.roll(input(boosted, "dunes", 5, sequence(random))) :: FindRoll.Roll
        local c = FindRoll.roll(input(shovel, "dunes", 5, sequence(random))) :: FindRoll.Roll
        T.expect(BigNum.toNumber(a.value)).toBe(3)
        T.expect(BigNum.toNumber(b.value)).toBe(3)
        T.expect(BigNum.toNumber(c.value)).toBe(15) -- Schaufel: Grundrate 5
    end)
end)

T.describe("roll", function()
    T.it("ohne Sammelzeit oder mit kaputter Zeit fällt nichts", function()
        local profile = fresh()
        T.expect(FindRoll.roll(input(profile, "dunes", 0, sequence({ 0, 0, 0 })))).toBeNil()
        T.expect(FindRoll.roll(input(profile, "dunes", -2, sequence({ 0, 0, 0 })))).toBeNil()
        T.expect(FindRoll.roll(input(profile, "dunes", 0 / 0, sequence({ 0, 0, 0 })))).toBeNil()
        T.expect(FindRoll.roll(input(profile, "dunes", math.huge, sequence({ 0, 0, 0 })))).toBeNil()
    end)

    T.it("ein hoher Zufallswert für die Chance heißt: kein Fund", function()
        local profile = fresh()
        T.expect(FindRoll.roll(input(profile, "dunes", 1, sequence({ 0.99, 0, 0 })))).toBeNil()
        -- Chance im Fenster = 2 %: 0,019 trifft, 0,021 nicht.
        T.expect(FindRoll.roll(input(profile, "dunes", 1, sequence({ 0.019, 0, 0 }))) ~= nil).toBe(true)
        T.expect(FindRoll.roll(input(profile, "dunes", 1, sequence({ 0.021, 0, 0 })))).toBeNil()
    end)

    T.it("mit festem Zufall kommt das erwartete Fundstück aus der aktuellen Zone", function()
        local profile = fresh()
        local roll = FindRoll.roll(input(profile, "dunes", 5, sequence({ 0, 0, 0 }))) :: FindRoll.Roll
        T.expect(roll.find.id).toBe("dunes_s1_1")
        T.expect(roll.rarityId).toBe("common")
        T.expect(roll.forced).toBe(false)
        local oasis = FindRoll.roll(input(profile, "oasis", 5, sequence({ 0, 0, 0 }))) :: FindRoll.Roll
        T.expect(oasis.find.zoneId).toBe("oasis")
        T.expect(oasis.find.id).toBe("oasis_s1_1")
    end)

    T.it("eine Zone ohne Quotentabelle oder ohne Funde bringt nichts", function()
        local profile = fresh()
        local data: any = { FindOdds = deepCopy(FindOdds) }
        data.FindOdds.zoneOddsTable.dunes = nil
        T.expect(FindRoll.roll(input(profile, "dunes", 5, sequence({ 0, 0, 0 })), data)).toBeNil()
        T.expect(FindRoll.roll(input(profile, "gibt_es_nicht", 5, sequence({ 0, 0, 0 })))).toBeNil()
    end)

    T.it("Erster Fund sicher: nach 60 s ohne Fund kommt ein Gewöhnlicher, danach nie mehr", function()
        local profile = fresh()
        local miss = sequence({ 0.99, 0.99, 0.99 })
        -- 59 s: noch nichts (Zufall gibt keinen Treffer).
        T.expect(FindRoll.roll(input(profile, "dunes", 0.25, miss, { sessionSeconds = 59.9 }))).toBeNil()
        -- 60 s: ein Gewöhnlicher Fund, auch wenn der Zufall nichts gäbe.
        local forced = FindRoll.roll(input(profile, "dunes", 0.25, sequence({ 0.99, 0.99, 0.99 }), { sessionSeconds = 60 })) :: FindRoll.Roll
        T.expect(forced.forced).toBe(true)
        T.expect(forced.rarityId).toBe("common")
        T.expect(forced.find.zoneId).toBe("dunes")
        -- Hat der Spieler schon einen Fund, greift die Regel nie wieder.
        profile.finds.dunes_s1_1 = 1
        T.expect(FindRoll.roll(input(profile, "dunes", 0.25, sequence({ 0.99, 0.99, 0.99 }), { sessionSeconds = 9999 }))).toBeNil()
    end)

    T.it("ein unbekannter Fund im Profil zählt nicht als Fund für den sicheren ersten", function()
        local profile = fresh()
        profile.finds.alter_fund_xyz = 5
        local forced = FindRoll.roll(input(profile, "dunes", 0.25, sequence({ 0.99, 0.99, 0.99 }), { sessionSeconds = 61 }))
        T.expect(forced ~= nil).toBe(true)
    end)

    T.it("Trefferquote im Dünenmeer: etwa 2 % pro Sekunde (100.000 Läufe)", function()
        math.randomseed(77)
        local profile = fresh()
        profile.finds.dunes_s1_1 = 1 -- kein sicherer erster Fund
        local hits = 0
        local runs = 100000
        local random = math.random
        for _ = 1, runs do
            if FindRoll.roll(input(profile, "dunes", 1, random)) ~= nil then
                hits += 1
            end
        end
        local p = 0.02
        local sigma = math.sqrt(runs * p * (1 - p))
        T.expect(math.abs(hits - runs * p) <= 5 * sigma).toBe(true)
    end)

    T.it("gebucht über Collection.record: neu, dann doppelt mit Münzen in der Höhe des Fundwerts", function()
        local profile = fresh()
        local first = FindRoll.roll(input(profile, "dunes", 5, sequence({ 0, 0, 0 }))) :: FindRoll.Roll
        local one = Collection.record(profile, first.find.id, first.value) :: Collection.Recorded
        T.expect(one.isNew).toBe(true)
        local again = FindRoll.roll(input(profile, "dunes", 5, sequence({ 0, 0, 0 }), { sessionSeconds = 0 })) :: FindRoll.Roll
        local two = Collection.record(profile, again.find.id, again.value) :: Collection.Recorded
        T.expect(two.isNew).toBe(false)
        T.expect(BigNum.toNumber(BigNum.deserialize(profile.coins))).toBe(3)
    end)
end)

T.describe("Sammelzeit aus Collecting", function()
    local function state(): any
        return Collecting.newState(NOW)
    end

    T.it("echte Sammelzeit wird je Zone gezählt und beim Abholen zurückgesetzt", function()
        local profile = fresh()
        local s = state()
        Collecting.setHolding(s, profile, true, NOW)
        Collecting.update(s, profile, NOW + 2)
        local taken = Collecting.takeFindSeconds(s)
        T.expect(taken.dunes).toBeCloseTo(2, 1e-9)
        T.expect(next(Collecting.takeFindSeconds(s))).toBeNil()
    end)

    T.it("ohne Halten keine Sammelzeit", function()
        local profile = fresh()
        local s = state()
        Collecting.update(s, profile, NOW + 10)
        T.expect(next(Collecting.takeFindSeconds(s))).toBeNil()
    end)

    T.it("Sammelzeit zählt auch bei Aufrufen über setHolding, sell und setZone", function()
        local profile = fresh()
        profile.zones.oasis = true
        local s = state()
        Collecting.setHolding(s, profile, true, NOW)
        Collecting.setHolding(s, profile, true, NOW + 1) -- Abrechnung über setHolding
        Collecting.setZone(s, profile, "oasis", NOW + 2, nil) -- erst alte Zone abrechnen
        Collecting.setHolding(s, profile, true, NOW + 3)
        Collecting.sell(s, profile, NOW + 4) -- Abrechnung über sell
        local taken = Collecting.takeFindSeconds(s)
        T.expect(taken.dunes).toBeCloseTo(2, 1e-9)
        T.expect(taken.oasis).toBeCloseTo(2, 1e-9)
    end)

    T.it("läuft der Tank in einem Fenster voll, zählt nur die Zeit bis voll", function()
        local profile = fresh()
        profile.nodes.collect_tool_2 = true
        profile.nodes.collect_tool_3 = true -- Eimerkette: 25 Sand pro Sekunde
        local s = state()
        Collecting.setHolding(s, profile, true, NOW)
        local capacity = Collecting.capacityOf(profile)
        local rate = Collecting.rateOf(profile)
        Collecting.update(s, profile, NOW + Economy.collecting.holdTimeoutSeconds)
        local taken = Collecting.takeFindSeconds(s)
        local expected = capacity / rate
        T.expect(expected < Economy.collecting.holdTimeoutSeconds).toBe(true)
        T.expect(taken.dunes).toBeCloseTo(expected, 1e-9)
    end)

    T.it("danach, bei vollem Tank, kommt keine weitere Sammelzeit dazu", function()
        local profile = fresh()
        local s = state()
        Collecting.setHolding(s, profile, true, NOW)
        for second = 1, 40 do
            Collecting.setHolding(s, profile, true, NOW + second)
        end
        local total = Collecting.takeFindSeconds(s).dunes or 0
        local capacity = Collecting.capacityOf(profile)
        T.expect(total <= capacity / Collecting.rateOf(profile) + 1e-9).toBe(true)
    end)

    T.it("rückwärts springende Uhr gibt keine Sammelzeit", function()
        local profile = fresh()
        local s = state()
        Collecting.setHolding(s, profile, true, NOW)
        Collecting.update(s, profile, NOW - 50)
        T.expect(next(Collecting.takeFindSeconds(s))).toBeNil()
    end)
end)

T.describe("Tank mit Nachkommastellen (Review M1)", function()
    T.it("ein Bruchteil im Tank hält das Sammeln nicht endlos offen, es endet bei voll", function()
        local profile = fresh()
        local capacity = Collecting.capacityOf(profile)
        profile.tank = BigNum.serialize(BigNum.new(capacity - 0.5))
        local s = Collecting.newState(NOW)
        Collecting.setHolding(s, profile, true, NOW)
        local result = Collecting.update(s, profile, NOW + 2)
        T.expect(result.full).toBe(true)
        T.expect(s.holding).toBe(false)
        -- Danach kommt keine weitere Sammelzeit mehr dazu.
        Collecting.takeFindSeconds(s)
        Collecting.update(s, profile, NOW + 10)
        T.expect(next(Collecting.takeFindSeconds(s))).toBeNil()
    end)

    T.it("ein voller Tank ohne neues Halten gibt keine Sammelzeit", function()
        local profile = fresh()
        profile.tank = BigNum.serialize(BigNum.new(Collecting.capacityOf(profile)))
        local s = Collecting.newState(NOW)
        s.holding = true -- Halten lief schon (zum Beispiel nach einem Sandsturm)
        s.holdUntil = NOW + 100
        Collecting.update(s, profile, NOW + 2)
        T.expect(next(Collecting.takeFindSeconds(s))).toBeNil()
        T.expect(s.holding).toBe(false)
    end)

    T.it("kaputte Daten mit Chance über 100 % geben höchstens einen Fund je Aufruf", function()
        local data: any = { FindOdds = deepCopy(FindOdds) }
        data.FindOdds.findChancePerSecond = 20000
        local profile = fresh()
        profile.finds.dunes_s1_1 = 1
        local roll = FindRoll.roll(input(profile, "dunes", 1, sequence({ 0.999, 0, 0 })), data)
        T.expect(roll ~= nil).toBe(true) -- Chance gedeckelt auf 100 %, nie mehr als ein Fund
        T.expect(FindRoll.chancePerSecond(profile, "dunes", 200, data)).toBe(1)
    end)
end)

T.finish()
