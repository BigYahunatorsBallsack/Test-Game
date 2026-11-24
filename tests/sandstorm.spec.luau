--!strict
-- Paket 2.7: Sandsturm (Prestige), Windkristalle, Reset, Bonus und Zonen nach dem Sturm.

local T = require("./lib/expect")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local Wind = require("../src/shared/Logic/Wind")
local Collecting = require("../src/shared/Logic/Collecting")
local Collection = require("../src/shared/Logic/Collection")
local FindRoll = require("../src/shared/Logic/FindRoll")
local TreePurchase = require("../src/shared/Logic/TreePurchase")
local TreeEffects = require("../src/shared/Logic/TreeEffects")
local ZoneLogic = require("../src/shared/Logic/Zones")
local Profile = require("../src/shared/Logic/Profile")
local Migrations = require("../src/shared/Logic/Migrations")
local BigNum = require("../src/shared/Logic/BigNum")
local DataCheck = require("../src/shared/Logic/DataCheck")
local Validate = require("../src/shared/Logic/Validate")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local Economy = require("../src/shared/Data/Economy")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local ZonesData = require("../src/shared/Data/Zones")

local NOW = 1_700_000_000

local function deepCopy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in value do
        copy[key] = deepCopy(inner)
    end
    return copy
end

local function fresh(): any
    return Profile.default(NOW)
end

-- Testwerte (Einheit 1 Mio., Wurzel, Faktor 1, schon ab 1 Kristall): glatte Zahlen zum Prüfen.
-- Die echten Werte aus Economy.sandstorm prüft der Block "Echte Werte" weiter unten.
local DATA = { Economy = { sandstorm = { requiresNode = "collect_tool_4", crystalUnit = 1_000_000, crystalExponent = 0.5, crystalScale = 1, minCrystals = 1, maxCrystals = 100_000 } } }
local cfg = DATA.Economy.sandstorm

-- Ein Spieler am Ende eines Laufs: Canyon frei, Werkzeug Mini-Bagger, Einnahmen 100 Mio. (10 Kristalle).
local function runner(earned: BigNum.BigNum?): any
    local profile = fresh()
    profile.nodes = { collect_tool_2 = true, collect_tool_3 = true, collect_tool_4 = true, sell_1 = true }
    profile.zones = { dunes = true, oasis = true, canyon = true }
    profile.currentZone = "canyon"
    profile.coins = BigNum.serialize(BigNum.new(3, 7))
    profile.runEarned = BigNum.serialize(earned or BigNum.new(1, 8))
    return profile
end

local function listContains(list: { string }, value: string): boolean
    return table.find(list, value) ~= nil
end

T.describe("Kristallformel", function()
    T.it("exakte Quadrate bleiben exakt, es wird abgerundet, unter der Einheit gibt es nichts", function()
        local value = function(m: number, e: number): number
            return Sandstorm.crystalsFor(BigNum.new(m, e), DATA)
        end
        T.expect(value(4, 6)).toBe(2)
        T.expect(value(1, 8)).toBe(10)
        T.expect(value(9, 8)).toBe(30)
        T.expect(value(1, 9)).toBe(31) -- 31,6 wird abgerundet
        T.expect(value(9.9, 5)).toBe(0) -- 0,99 Einheiten
        T.expect(Sandstorm.crystalsFor(BigNum.zero(), DATA)).toBe(0)
    end)

    T.it("steigt mit den Einnahmen, aber langsamer als diese (Wurzel)", function()
        local last = -1
        for exponent = 6, 14 do
            local crystals = Sandstorm.crystalsFor(BigNum.new(1, exponent), DATA)
            T.expect(crystals > last).toBe(true)
            last = crystals
        end
        local ten = Sandstorm.crystalsFor(BigNum.new(1, 9), DATA)
        local hundred = Sandstorm.crystalsFor(BigNum.new(1, 11), DATA)
        T.expect(hundred < ten * 100).toBe(true)
    end)

    T.it("ist bei riesigen Einnahmen endlich und höchstens die Obergrenze, kaputte Zahlen ergeben 0", function()
        local huge = Sandstorm.crystalsFor(BigNum.new(1, 300), DATA)
        T.expect(huge <= cfg.maxCrystals).toBe(true)
        T.expect(huge).toBe(cfg.maxCrystals)
        T.expect(Sandstorm.crystalsFor({ m = 0 / 0, e = 3 }, DATA)).toBe(0)
        T.expect(Sandstorm.crystalsFor({ m = 1, e = math.huge }, DATA)).toBe(0)
        T.expect(Sandstorm.crystalsFor({ m = -5, e = 3 }, DATA)).toBe(0)
    end)

    T.it("die Werte lassen sich für Tests überschreiben", function()
        local data = { Economy = { sandstorm = { requiresNode = "collect_tool_4", crystalUnit = 1000, crystalExponent = 1, crystalScale = 2, minCrystals = 1, maxCrystals = 50 } } }
        T.expect(Sandstorm.crystalsFor(BigNum.new(1, 4), data)).toBe(20) -- 2 x 10
        T.expect(Sandstorm.crystalsFor(BigNum.new(1, 9), data)).toBe(50) -- Obergrenze
    end)
end)

T.describe("Echte Werte (Balance 2.7)", function()
    local real = Economy.sandstorm

    T.it("Startwerte vom balance-analyst: Einheit 1 Mio., Exponent 0,25, Faktor 4, mindestens 20 Kristalle", function()
        T.expect(real.crystalUnit).toBe(1_000_000)
        T.expect(real.crystalExponent).toBe(0.25)
        T.expect(real.crystalScale).toBe(4)
        T.expect(real.minCrystals).toBe(20)
        T.expect(UpgradeTree.byId.sandstorm_ruins.cost).toBe(250_000_000)
    end)

    T.it("ein Sturm direkt nach dem Mini-Bagger (etwa 26.000 Münzen) bringt 1 Kristall und ist damit zu wenig, 625 Mio. geben gerade 20", function()
        T.expect(Sandstorm.crystalsFor(BigNum.new(2.6, 4))).toBe(1)
        local early = runner(BigNum.new(2.6, 4))
        T.expect(Sandstorm.check(early)).toBe("tooFew")
        T.expect(Sandstorm.crystalsFor(BigNum.new(6.25, 8))).toBe(20)
        T.expect(Sandstorm.crystalsFor(BigNum.new(1, 9))).toBe(22) -- 4 x 1000^0,25 = 22,5
    end)

    T.it("der Sturm geht erst ab minCrystals, die Vorschau nennt die Einnahmen dafür", function()
        local profile = runner(BigNum.new(1, 8)) -- 4 x 100^0,25 = 12 Kristalle
        local view = Sandstorm.preview(profile)
        T.expect(view.gain).toBe(12)
        T.expect(view.ready).toBe(false)
        T.expect(view.reason).toBe("tooFew")
        T.expect(view.unlocked).toBe(true) -- der Knopf ist schon da
        T.expect(view.minCrystals).toBe(20)
        T.expect(BigNum.toNumber(BigNum.deserialize(view.needed))).toBeCloseTo(6.25e8, 1)
        profile.runEarned = BigNum.serialize(BigNum.new(1, 9))
        T.expect(Sandstorm.check(profile)).toBeNil()
    end)

    T.it("earningsFor ist die Umkehrung der Formel", function()
        for _, crystals in { 1, 5, 20, 100, 5000 } do
            local earned = Sandstorm.earningsFor(crystals)
            local back = Sandstorm.crystalsFor(earned)
            T.expect(back >= crystals).toBe(true)
            T.expect(back <= crystals + 1).toBe(true)
        end
    end)
end)

T.describe("Bedingungen", function()
    T.it("ohne den Knoten für den Canyon: requires, Profil unverändert", function()
        local profile = runner()
        profile.nodes.collect_tool_4 = nil
        local before = deepCopy(profile)
        local result, reason = Sandstorm.apply(profile, DATA)
        T.expect(result).toBeNil()
        T.expect(reason).toBe("requires")
        T.expect(profile).toEqual(before)
        T.expect(Sandstorm.check(profile, DATA)).toBe("requires")
    end)

    T.it("mit dem Knoten, aber ohne einen Kristall im Lauf: tooFew, Profil unverändert", function()
        local profile = runner(BigNum.new(5, 5)) -- 0,5 Einheiten
        local before = deepCopy(profile)
        local result, reason = Sandstorm.apply(profile, DATA)
        T.expect(result).toBeNil()
        T.expect(reason).toBe("tooFew")
        T.expect(profile).toEqual(before)
    end)

    T.it("der Wert des vollen Tanks zählt zum Lauf (nichts geht verloren)", function()
        local profile = runner(BigNum.zero())
        profile.nodes.sell_1 = nil -- ohne Verkauf-Bonus, damit die Rechnung glatt aufgeht
        T.expect(Sandstorm.check(profile, DATA)).toBe("tooFew")
        -- 1,5 Mio. Sand in der Ruinenstadt zu 150 Münzen je Sand: 225 Mio. Einnahmen = 15 Kristalle.
        Collecting.addSand(profile, 1_500_000, "black")
        local view = Sandstorm.preview(profile, DATA)
        T.expect(view.ready).toBe(true)
        T.expect(view.gain).toBe(15)
        local result = Sandstorm.apply(profile, DATA)
        T.expect((result :: any).crystals).toBe(15)
        T.expect(profile.tank).toEqual({ m = 0, e = 0 })
        T.expect(profile.tankMix).toEqual({})
    end)

    T.it("die Vorschau ändert nichts und passt zum Ergebnis", function()
        local profile = runner()
        local before = deepCopy(profile)
        local view = Sandstorm.preview(profile, DATA)
        T.expect(profile).toEqual(before)
        T.expect(view.ready).toBe(true)
        T.expect(view.first).toBe(true)
        local result = Sandstorm.apply(profile, DATA)
        T.expect((result :: any).crystals).toBe(view.gain)
        T.expect((result :: any).total).toBe(view.crystalsAfter)
        T.expect((result :: any).bonusBpAfter).toBe(view.bonusBpAfter)
    end)

    T.it("gehalten an der Obergrenze: kein Gewinn, also tooFew, nie mehr als maxCrystals", function()
        local profile = runner(BigNum.new(1, 30))
        profile.windCrystals = cfg.maxCrystals
        T.expect(Sandstorm.check(profile, DATA)).toBe("tooFew")
        profile.windCrystals = cfg.maxCrystals - 3
        local result = Sandstorm.apply(profile, DATA)
        T.expect((result :: any).crystals).toBe(3)
        T.expect(profile.windCrystals).toBe(cfg.maxCrystals)
    end)

    T.it("ein riesiger Kristallwert im Profil macht den Faktor nicht unendlich (Obergrenze), sanitize kappt ihn", function()
        local profile = fresh()
        profile.windCrystals = 1e300
        T.expect(Wind.crystalsOf(profile)).toBe(Economy.sandstorm.maxCrystals)
        T.expect(Wind.multiplier(profile) < math.huge).toBe(true)
        local state = Collecting.newState(0)
        Collecting.addSand(profile, 10, "yellow")
        T.expect(Collecting.sell(state, profile, 0) ~= nil).toBe(true) -- wirft nicht
        Profile.sanitize(profile, NOW)
        T.expect(profile.windCrystals).toBe(Economy.sandstorm.maxCrystals)
    end)

    T.it("kaputte Profile werfen nicht (Knoten keine Tabelle, Kristalle NaN)", function()
        local profile = runner()
        profile.windCrystals = 0 / 0
        local view = Sandstorm.preview(profile, DATA)
        T.expect(view.crystalsNow).toBe(0)
        profile.nodes = "kaputt"
        T.expect(Sandstorm.check(profile, DATA)).toBe("requires")
        profile.nodes = { collect_tool_4 = true }
        profile.prestiges = "x"
        local result = Sandstorm.apply(profile, DATA)
        T.expect((result :: any).prestiges).toBe(1)
    end)
end)

T.describe("Reset", function()
    T.it("setzt Münzen und Werkzeugstufe zurück, behält aber Sammlung und Skins", function()
        local profile = runner()
        profile.finds = { dunes_s1_1 = 3, oasis_s2_4 = 1 }
        profile.inventory.skins = { skin_dunes_book = 1 }
        profile.inventory.companions = { fox = 1 }
        profile.inventory.toolVariants = { gold_shovel = 1 }
        local bonusBefore = Collection.bonusBp(profile)
        T.expect(Collecting.toolOf(profile).id).toBe("mini_digger")
        local result = Sandstorm.apply(profile, DATA)
        T.expect(result ~= nil).toBe(true)
        -- Weg:
        T.expect(profile.coins).toEqual({ m = 0, e = 0 })
        T.expect(profile.tank).toEqual({ m = 0, e = 0 })
        T.expect(profile.runEarned).toEqual({ m = 0, e = 0 })
        T.expect(Collecting.toolOf(profile).id).toBe("hand")
        T.expect(profile.nodes.collect_tool_4).toBeNil()
        T.expect(profile.nodes.sell_1).toBeNil()
        T.expect(TreeEffects.of(profile).sellBonusBp).toBe(0)
        -- Geblieben:
        T.expect(profile.finds).toEqual({ dunes_s1_1 = 3, oasis_s2_4 = 1 })
        T.expect(profile.inventory.skins).toEqual({ skin_dunes_book = 1 })
        T.expect(profile.inventory.companions).toEqual({ fox = 1 })
        T.expect(profile.inventory.toolVariants).toEqual({ gold_shovel = 1 })
        T.expect(Collection.bonusBp(profile)).toBe(bonusBefore)
    end)

    T.it("Gems, Belege, Kaufprotokoll, spent, Pity, Boosts, Daily, Codes, Tutorial und Zeitstempel bleiben unverändert", function()
        local profile = runner()
        profile.gems = 345
        profile.receipts = { "abc", "def" } -- Paket 4.1: Liste der PurchaseIds
        profile.purchaseLog = {
            { purchaseId = "abc", productId = "gems_100", gems = 100, robux = 49, time = NOW },
            { purchaseId = "def", productId = "gems_550", gems = 550, robux = 249, time = NOW + 1 },
        }
        profile.spent = { robux = 298, count = 2 }
        profile.pity = { gold = { sinceEpic = 4, sinceLegendary = 9 } }
        profile.boosts = { coinsUntil = NOW + 500 }
        profile.daily = { streak = 3, lastDay = 19_000 }
        profile.codes = { test_code = true } -- Paket 5.2: eingelöste Codes bleiben
        profile.tutorial = { step = 7 }
        profile.lastSeen = NOW + 10
        local keep = {}
        for _, field in Sandstorm.KEEP_FIELDS do
            keep[field] = deepCopy(profile[field])
        end
        Sandstorm.apply(profile, DATA)
        for _, field in Sandstorm.KEEP_FIELDS do
            T.expect(profile[field]).toEqual(keep[field])
        end
        T.expect(profile.gems).toBe(345)
        T.expect(profile.receipts).toEqual({ "abc", "def" })
        T.expect(#profile.purchaseLog).toBe(2)
        T.expect(profile.spent).toEqual({ robux = 298, count = 2 })
    end)

    T.it("jedes Feld aus Profile.default steht in genau einer Liste", function()
        local lists = { Sandstorm.RESET_FIELDS, Sandstorm.UPDATED_FIELDS, Sandstorm.KEEP_FIELDS }
        for field in Profile.default(NOW) do
            local hits = 0
            for _, list in lists do
                if listContains(list, field :: string) then
                    hits += 1
                end
            end
            if hits ~= 1 then
                print(`       Feld "{field}" steht in {hits} Listen`)
            end
            T.expect(hits).toBe(1)
        end
        local defaults: any = Profile.default(NOW)
        for _, list in lists do
            for _, field in list do
                T.expect(defaults[field] ~= nil).toBe(true)
            end
        end
    end)

    T.it("der erste Sturm vergibt sandstorm_1, ein zweiter behält ihn, prestiges zählt hoch", function()
        local profile = runner()
        T.expect(profile.nodes.sandstorm_1).toBeNil()
        local first = Sandstorm.apply(profile, DATA)
        T.expect((first :: any).first).toBe(true)
        T.expect(profile.nodes.sandstorm_1).toBe(true)
        T.expect(profile.prestiges).toBe(1)
        -- nächster Lauf
        profile.nodes.collect_tool_4 = true
        profile.runEarned = BigNum.serialize(BigNum.new(4, 6))
        local second = Sandstorm.apply(profile, DATA)
        T.expect((second :: any).first).toBe(false)
        T.expect(profile.nodes.sandstorm_1).toBe(true)
        T.expect(profile.prestiges).toBe(2)
    end)

    T.it("Kristalle werden bei zwei schnellen Aufrufen nur einmal gutgeschrieben", function()
        local profile = runner() -- 10 Kristalle
        local a, reasonA = Sandstorm.apply(profile, DATA)
        local b, reasonB = Sandstorm.apply(profile, DATA)
        T.expect((a :: any).crystals).toBe(10)
        T.expect(reasonA).toBeNil()
        T.expect(b).toBeNil()
        T.expect(reasonB).toBe("requires")
        T.expect(profile.windCrystals).toBe(10)
        T.expect(profile.prestiges).toBe(1)
    end)

    T.it("Kristalle sammeln sich über mehrere Stürme", function()
        local profile = runner()
        Sandstorm.apply(profile, DATA) -- 10
        profile.nodes.collect_tool_4 = true
        profile.runEarned = BigNum.serialize(BigNum.new(4, 6)) -- 2
        Sandstorm.apply(profile, DATA)
        T.expect(profile.windCrystals).toBe(12)
    end)

    T.it("auch unbekannte Knoten-IDs gehen zurück, nur vergebene Knoten bleiben (kein Gratis-Knoten durch einen älteren Server)", function()
        local profile = runner()
        profile.nodes.knoten_aus_neuerem_baum = true
        Sandstorm.apply(profile, DATA)
        T.expect(profile.nodes.knoten_aus_neuerem_baum).toBeNil()
        T.expect(profile.nodes.collect_tool_2).toBeNil()
        T.expect(profile.nodes).toEqual({ sandstorm_1 = true })
    end)

    T.it("danach läuft der Lauf von vorn: Hand, Kauf der Schaufel mit neuen Münzen", function()
        local profile = runner()
        Sandstorm.apply(profile, DATA)
        T.expect(TreePurchase.check(profile, "collect_rate_1")).toBe("coins")
        profile.coins = BigNum.serialize(BigNum.new(1, 3))
        local ok = TreePurchase.buy(profile, "collect_rate_1")
        T.expect(ok).toBe(true)
        T.expect(TreePurchase.check(profile, "collect_tool_4")).toBe("requires")
    end)
end)

T.describe("Einnahmen des Laufs (runEarned)", function()
    T.it("Verkäufe und verkaufte Duplikate zählen, Knotenkäufe nicht", function()
        local profile = fresh()
        local state = Collecting.newState(0)
        Collecting.addSand(profile, 10, "yellow")
        local earned = Collecting.sell(state, profile, 0)
        T.expect(BigNum.toNumber(earned :: any)).toBe(10)
        T.expect(BigNum.toNumber(Wind.runEarned(profile))).toBe(10)
        -- Duplikat: erster Fund neu, zweiter wird verkauft.
        Collection.record(profile, "dunes_s1_1", BigNum.new(7))
        Collection.record(profile, "dunes_s1_1", BigNum.new(7))
        T.expect(BigNum.toNumber(Wind.runEarned(profile))).toBe(17)
        T.expect(BigNum.toNumber(BigNum.deserialize(profile.coins))).toBe(17)
        -- Ein Knotenkauf senkt die Münzen, aber nicht die Einnahmen.
        profile.coins = BigNum.serialize(BigNum.new(15))
        TreePurchase.buy(profile, "collect_rate_1")
        T.expect(BigNum.toNumber(BigNum.deserialize(profile.coins))).toBe(0)
        T.expect(BigNum.toNumber(Wind.runEarned(profile))).toBe(17)
    end)

    T.it("Wind.credit ignoriert null und negative Beträge", function()
        local profile = fresh()
        Wind.credit(profile, BigNum.zero())
        Wind.credit(profile, { m = -5, e = 2 })
        T.expect(profile.coins).toEqual({ m = 0, e = 0 })
        T.expect(profile.runEarned).toEqual({ m = 0, e = 0 })
    end)
end)

T.describe("L1 (6.4): Münz-Faktor zählt nicht für runEarned", function()
    T.it("Verkauf mit Faktor 3: Münzen mal 3, runEarned ohne Faktor", function()
        local profile = fresh()
        Collecting.addSand(profile, 10, "yellow")
        local earned = Collecting.sell(Collecting.newState(0), profile, 0, { coinMultiplier = 3 })
        T.expect(BigNum.toNumber(earned :: any)).toBe(30)
        T.expect(BigNum.toNumber(BigNum.deserialize(profile.coins))).toBe(30)
        T.expect(BigNum.toNumber(Wind.runEarned(profile))).toBe(10)
    end)

    T.it("Sandsturm-Vorschau mit und ohne Faktor zeigt dieselben Einnahmen", function()
        local profile = fresh()
        Collecting.addSand(profile, 10, "yellow")
        local with = Sandstorm.runTotal(profile, { coinMultiplier = 3 })
        local without = Sandstorm.runTotal(profile)
        T.expect(with).toEqual(without)
    end)

    T.it("Wind.credit mit runAmount: nie mehr als der Betrag, 0 oder negativ zählt nichts", function()
        local profile = fresh()
        Wind.credit(profile, BigNum.new(30), BigNum.new(10))
        T.expect(BigNum.toNumber(Wind.runEarned(profile))).toBe(10)
        Wind.credit(profile, BigNum.new(5), BigNum.new(99))
        T.expect(BigNum.toNumber(Wind.runEarned(profile))).toBe(15)
        Wind.credit(profile, BigNum.new(5), { m = -1, e = 0 })
        Wind.credit(profile, BigNum.new(5), BigNum.zero())
        T.expect(BigNum.toNumber(Wind.runEarned(profile))).toBe(15)
        T.expect(BigNum.toNumber(BigNum.deserialize(profile.coins))).toBe(45)
    end)
end)

T.describe("Bonus der Windkristalle", function()
    T.it("N Kristalle machen den Preis pro Sand zum (1 + N x 2 %)-Fachen, zusammen mit den anderen Boni", function()
        local profile = fresh()
        profile.nodes = { sell_1 = true }
        local base = Collecting.priceOf(profile, "yellow")
        local collectionBase = Collection.bonusMultiplier(profile)
        profile.windCrystals = 10
        T.expect(Wind.bonusBp(profile)).toBe(2000)
        T.expect(Collecting.priceOf(profile, "yellow")).toBeCloseTo(base * 1.2, 1e-9)
        T.expect(Collecting.pricePerSand(profile)).toBeCloseTo(base * 1.2, 1e-9)
        -- Sammlungsbonus multipliziert sich dazu.
        for slot = 1, 5 do
            profile.finds[`dunes_s1_{slot}`] = 1
        end
        T.expect(Collection.bonusMultiplier(profile) > collectionBase).toBe(true)
        T.expect(Collecting.priceOf(profile, "yellow")).toBeCloseTo(base * 1.2 * Collection.bonusMultiplier(profile), 1e-9)
    end)

    T.it("der Verkauf zahlt mit dem Bonus, auch Sand ohne Mix-Eintrag", function()
        local profile = fresh()
        profile.windCrystals = 50 -- +100 %
        local state = Collecting.newState(0)
        Collecting.addSand(profile, 10, "yellow")
        local earned = Collecting.sell(state, profile, 0)
        T.expect(BigNum.toNumber(earned :: any)).toBe(20)
        profile.tank = BigNum.serialize(BigNum.new(10)) -- ohne Mix
        profile.tankMix = {}
        local earned2 = Collecting.sell(state, profile, 0)
        T.expect(BigNum.toNumber(earned2 :: any)).toBe(20)
    end)

    T.it("der Fundwert steigt mit den Kristallen genauso", function()
        local profile = fresh()
        profile.windCrystals = 0
        local function roll(): any
            return FindRoll.roll({
                profile = profile,
                zoneId = "dunes",
                seconds = 1,
                serverTime = 0,
                sessionSeconds = 1000, -- Erster Fund sicher: Gewöhnlicher Fund
                random = function(): number
                    return 0
                end,
            })
        end
        local plain: any = roll()
        profile.windCrystals = 50
        local boosted: any = roll()
        T.expect(plain.find.id).toBe(boosted.find.id)
        T.expect(BigNum.toNumber(boosted.value)).toBe(BigNum.toNumber(plain.value) * 2)
    end)

    T.it("ohne Kristalle ändert sich nichts (Faktor 1), kaputte Werte zählen als 0", function()
        local profile = fresh()
        T.expect(Wind.multiplier(profile)).toBe(1)
        profile.windCrystals = 0 / 0
        T.expect(Wind.multiplier(profile)).toBe(1)
        profile.windCrystals = -5
        T.expect(Wind.multiplier(profile)).toBe(1)
        profile.windCrystals = 2.9
        T.expect(Wind.crystalsOf(profile)).toBe(2)
    end)
end)

T.describe("Zonen nach dem Sturm", function()
    T.it("nur das Dünenmeer ist frei, Oase bis Salzsee kommen mit ihren Werkzeugen wieder", function()
        local profile = runner()
        Sandstorm.apply(profile, DATA)
        T.expect(profile.currentZone).toBe("dunes")
        T.expect(profile.zones).toEqual({ dunes = true })
        T.expect(ZoneLogic.isUnlocked(profile, "oasis")).toBe(false)
        T.expect(ZoneLogic.isUnlocked(profile, "canyon")).toBe(false)
        T.expect(ZoneLogic.isUnlocked(profile, "salt_lake")).toBe(false)
        profile.nodes.collect_tool_3 = true
        T.expect(ZoneLogic.unlockNew(profile)).toEqual({ "oasis" })
    end)

    T.it("die Ruinenstadt braucht in jedem Lauf sandstorm_ruins, vorher nicht einmal im ersten Lauf", function()
        local profile = runner()
        -- Vor dem ersten Sturm: nicht kaufbar, weil sandstorm_1 fehlt.
        profile.nodes.collect_tool_5 = true
        profile.coins = BigNum.serialize(BigNum.new(1, 12))
        T.expect(TreePurchase.check(profile, "sandstorm_ruins")).toBe("requires")
        T.expect(ZoneLogic.isUnlocked(profile, "ruins")).toBe(false)
        Sandstorm.apply(profile, DATA)
        -- Nach dem Sturm fehlt der Saugroboter, also noch immer nicht kaufbar.
        profile.coins = BigNum.serialize(BigNum.new(1, 12))
        T.expect(TreePurchase.check(profile, "sandstorm_ruins")).toBe("requires")
        profile.nodes.collect_tool_5 = true
        T.expect(TreePurchase.check(profile, "sandstorm_ruins")).toBeNil()
        local ok = TreePurchase.buy(profile, "sandstorm_ruins")
        T.expect(ok).toBe(true)
        T.expect(ZoneLogic.unlockNew(profile)).toEqual({ "salt_lake", "ruins" }) -- Saugroboter öffnet auch den Salzsee
        -- Der nächste Sturm sperrt sie wieder.
        profile.nodes.collect_tool_4 = true
        profile.runEarned = BigNum.serialize(BigNum.new(4, 6))
        Sandstorm.apply(profile, DATA)
        T.expect(ZoneLogic.isUnlocked(profile, "ruins")).toBe(false)
        T.expect(profile.nodes.sandstorm_ruins).toBeNil()
        T.expect(profile.nodes.sandstorm_1).toBe(true)
    end)

    T.it("Zone.resolve: Spieler im Canyon wird zurück an den Spawn des Dünenmeers gesetzt", function()
        local profile = runner()
        Sandstorm.apply(profile, DATA)
        -- Der Server setzt currentZone selbst, Position im Canyon wird als gesperrt zurückgeschoben.
        local inCanyon = { x = 500, y = 5, z = 0 }
        local World = require("../src/shared/Data/World")
        local area = World.zonesById.canyon
        inCanyon = { x = (area.bounds.minX + area.bounds.maxX) / 2, y = 5, z = (area.bounds.minZ + area.bounds.maxZ) / 2 }
        local pushed = ZoneLogic.resolve(profile, inCanyon)
        T.expect(pushed.kind).toBe("blocked")
        -- Ein Profil, dessen aktuelle Zone gesperrt ist (alter Stand, Daten-Update): "reset".
        profile.currentZone = "canyon"
        local reset = ZoneLogic.resolve(profile, inCanyon)
        T.expect(reset.kind).toBe("reset")
        T.expect(reset.zoneId).toBe("dunes")
    end)

    T.it("sandstorm_ruins wirkt nicht, wenn nur der Knoten da ist, ohne dass die Zone in der Tabelle steht", function()
        local profile = fresh()
        profile.nodes = { sandstorm_ruins = true }
        T.expect(ZoneLogic.isUnlocked(profile, "ruins")).toBe(true) -- Voraussetzung erfüllt
        T.expect(UpgradeTree.byId.sandstorm_ruins.effect.kind).toBe("zoneKey")
        T.expect(ZonesData.byId.ruins.requires).toBe("sandstorm_ruins")
    end)
end)

T.describe("Profil und Migration", function()
    T.it("ein Profil der Version 2 bekommt runEarned aus den Münzen, die Funde bleiben", function()
        local old: any = Profile.default(NOW)
        old.version = 2
        old.runEarned = nil
        old.coins = { m = 2.5, e = 6 }
        old.finds = { dunes_s1_1 = 2 }
        local migrated, status = Profile.migrate(old, nil, NOW)
        T.expect(status).toBe("ok")
        T.expect(migrated.version).toBe(Migrations.CURRENT_VERSION)
        T.expect((migrated :: any).runEarned).toEqual({ m = 2.5, e = 6 })
        T.expect((migrated :: any).finds).toEqual({ dunes_s1_1 = 2 })
    end)

    T.it("ein Profil mit kaputten Münzen bekommt runEarned 0", function()
        local old: any = Profile.default(NOW)
        old.version = 2
        old.runEarned = nil
        old.coins = "kaputt"
        local migrated = Profile.migrate(old, nil, NOW)
        T.expect((migrated :: any).runEarned).toEqual({ m = 0, e = 0 })
    end)

    T.it("sanitize: kaputtes oder negatives runEarned wird 0, Kristalle werden ganz und nie negativ", function()
        local profile = fresh()
        profile.runEarned = { m = 0 / 0, e = 3 }
        profile.windCrystals = 7.8
        profile.prestiges = -2
        Profile.sanitize(profile, NOW)
        T.expect(profile.runEarned).toEqual({ m = 0, e = 0 })
        T.expect(profile.windCrystals).toBe(7)
        T.expect(profile.prestiges).toBe(0)
        local second = fresh()
        second.runEarned = { m = -4, e = 2 }
        second.windCrystals = -3
        Profile.sanitize(second, NOW)
        T.expect(second.runEarned).toEqual({ m = 0, e = 0 })
        T.expect(second.windCrystals).toBe(0)
    end)

    T.it("ein Profil mit Sturm übersteht Migration und sanitize unverändert", function()
        local profile = runner()
        Sandstorm.apply(profile, DATA)
        local before = deepCopy(profile)
        local again = Profile.migrate(profile, nil, NOW)
        Profile.sanitize(again, NOW)
        T.expect(again).toEqual(before)
    end)
end)

T.describe("Datenprüfung und Remote", function()
    local function broken(change: (any) -> ()): { string }
        local data: any = DataCheck.defaults()
        data.Economy = deepCopy(data.Economy)
        change(data)
        return DataCheck.run(data)
    end

    local function hasError(errors: { string }, text: string)
        for _, line in errors do
            if string.find(line, text, 1, true) ~= nil then
                return
            end
        end
        print(`       fehlt: {text}; erhalten: {table.concat(errors, " | ")}`)
        T.expect(false).toBe(true)
    end

    T.it("die echten Daten bestehen", function()
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("unbekannter oder vergebener requiresNode, falsche Formelwerte und Grenzen werden gemeldet", function()
        hasError(broken(function(d) d.Economy.sandstorm.requiresNode = "gibt_es_nicht" end), "requiresNode")
        hasError(broken(function(d) d.Economy.sandstorm.requiresNode = "sandstorm_1" end), "vergeben")
        hasError(broken(function(d) d.Economy.sandstorm.crystalUnit = 0 end), "crystalUnit")
        hasError(broken(function(d) d.Economy.sandstorm.crystalExponent = 1.5 end), "crystalExponent")
        hasError(broken(function(d) d.Economy.sandstorm.crystalExponent = 0 end), "crystalExponent")
        hasError(broken(function(d) d.Economy.sandstorm.crystalScale = 5000 end), "crystalScale")
        hasError(broken(function(d) d.Economy.sandstorm.maxCrystals = 0 end), "maxCrystals")
        hasError(broken(function(d) d.Economy.sandstorm.maxCrystals = 100_000_000 end), "maxCrystals")
        hasError(broken(function(d) d.Economy.sandstorm.minCrystals = 0 end), "minCrystals")
        hasError(broken(function(d) d.Economy.sandstorm.minCrystals = d.Economy.sandstorm.maxCrystals + 1 end), "minCrystals")
        hasError(broken(function(d) d.Economy.sandstorm = nil end), "Economy.sandstorm")
    end)

    T.it("eine Zone darf keinen vom Sturm vergebenen Knoten verlangen", function()
        local data: any = DataCheck.defaults()
        local zones = deepCopy(data.Zones)
        zones.byId = {}
        for _, zone in zones.list do
            zones.byId[zone.id] = zone
            if zone.id == "ruins" then
                zone.requires = "sandstorm_1"
            end
        end
        data.Zones = zones
        hasError(DataCheck.run(data), "vergebenen Knoten")
    end)

    T.it("die erste Zone der Liste muss die Startzone sein (dorthin setzt der Sturm zurück)", function()
        local data: any = DataCheck.defaults()
        local zones = deepCopy(data.Zones)
        zones.list[1], zones.list[2] = zones.list[2], zones.list[1]
        data.Zones = zones
        hasError(DataCheck.run(data), "erste Zone")
    end)

    T.it("sandstorm_ruins verlangt sandstorm_1 und den Saugroboter und ist kaufbar", function()
        local node = UpgradeTree.byId.sandstorm_ruins
        T.expect(node.branch).toBe("sandstorm")
        T.expect(node.granted).toBeNil()
        T.expect(node.cost > 0).toBe(true)
        T.expect(listContains(node.requires, "sandstorm_1")).toBe(true)
        T.expect(listContains(node.requires, "collect_tool_5")).toBe(true)
    end)

    T.it("Remote Prestige: ohne Argumente ja, mit Argument (auch eine Menge) nein, Limit 1 pro 5 s", function()
        local def: any
        for _, entry in RemoteSpec.list do
            if entry.name == "Prestige" then
                def = entry
            end
        end
        T.expect(def ~= nil).toBe(true)
        T.expect(def.limit.calls).toBe(1)
        T.expect(def.limit.per).toBe(5)
        T.expect((Validate.check(def.schema, {}, 0))).toBe(true)
        T.expect((Validate.check(def.schema, { 999 }, 1))).toBe(false)
        T.expect((Validate.check(def.schema, { "windCrystals" }, 1))).toBe(false)
    end)
end)

T.finish()
