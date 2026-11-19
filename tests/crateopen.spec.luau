--!strict
-- Paket 4.2: Kisten öffnen auf dem Server (Logic/CrateOpen). Bezahlen, Würfe, Pity und Inventar in
-- einem Block; Policy fail-closed; Event nur in der Saison; Fehler und Warten buchen nichts; Pity
-- übersteht Speichern und Laden; Gratis-Öffnung.

local T = require("./lib/expect")
local serde = require("@lune/serde")
local CrateOpen = require("../src/shared/Logic/CrateOpen")
local CrateRoll = require("../src/shared/Logic/CrateRoll")
local Profile = require("../src/shared/Logic/Profile")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local BigNum = require("../src/shared/Logic/BigNum")
local Crates = require("../src/shared/Data/Crates")
local CrateItems = require("../src/shared/Data/CrateItems")
local Rarities = require("../src/shared/Data/Rarities")

local NOW = 1_700_000_000
local SEED = 777

local gold = Crates.byId.gold
local wood = Crates.byId.wood
local iron = Crates.byId.iron
local event = Crates.byId.event

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

local function constant(value: number): () -> number
    return function(): number
        return value
    end
end

-- Kontext für eine erlaubte Öffnung (Policy bekannt und frei, keine Saison).
local function allowed(random: (() -> number)?): any
    return { random = random or constant(0), restricted = false, inSeason = false }
end

local function fresh(): any
    return Profile.default(NOW)
end

local function rich(): any
    local profile = fresh()
    profile.gems = 1_000_000
    profile.coins = BigNum.serialize(BigNum.new(1, 9))
    return profile
end

local function inventoryCount(profile: any, itemId: string): number
    local item = CrateItems.byId[itemId]
    local field = CrateOpen.INVENTORY_FIELDS[item.kind]
    return profile.inventory[field][itemId] or 0
end

local function rank(rarityId: string): number
    return Rarities.byId[rarityId].rank
end

T.describe("Bezahlen", function()
    T.it("Goldkiste kostet price Gems, das Item landet im Inventar, die Pity zählt", function()
        local profile = fresh()
        profile.gems = gold.price + 5
        local result = CrateOpen.open(profile, "gold", 1, allowed())
        T.expect(result.ok).toBe(true)
        T.expect(profile.gems).toBe(5)
        T.expect(result.gems).toBe(5)
        T.expect(#result.results).toBe(1)
        local prize = result.results[1]
        T.expect(inventoryCount(profile, prize.itemId)).toBe(1)
        T.expect(prize.isNew).toBe(true)
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 1, sinceLegendary = 1 })
        T.expect(result.pity).toEqual({ sinceEpic = 1, sinceLegendary = 1 })
        T.expect(result.highest).toBe(prize.rarityId)
    end)

    T.it("10er-Paket: bezahlt werden 10, geöffnet 11, jede Öffnung zählt für die Pity", function()
        local profile = fresh()
        profile.gems = gold.price * Crates.bundle.buy
        local result = CrateOpen.open(profile, "gold", 10, allowed())
        T.expect(result.ok).toBe(true)
        T.expect(profile.gems).toBe(0)
        T.expect(#result.results).toBe(Crates.bundle.get)
        T.expect(#result.results).toBe(11)
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 11, sinceLegendary = 11 })
    end)

    T.it("im 10er-Paket greift die Pity mitten im Paket", function()
        local function triggeredOf(result: any): { string }
            local list = {}
            for index, prize in result.results do
                if prize.pityTriggered ~= nil then
                    table.insert(list, `{index}:{prize.pityTriggered}:{prize.rarityId}`)
                end
            end
            return list
        end
        -- Mit Zufall 0 fällt ohne Garantie immer Ungewöhnlich. Start 10/20: Öffnung 5 hat
        -- sinceEpic 14 und wird Episch, danach zählen 6 bis 11 wieder hoch.
        local profile = rich()
        profile.pity.gold = { sinceEpic = 10, sinceLegendary = 20 }
        local result = CrateOpen.open(profile, "gold", 10, allowed())
        T.expect(triggeredOf(result)).toEqual({ "5:epic:epic" })
        T.expect(result.highest).toBe("epic")
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 6, sinceLegendary = 31 })
        -- Start 10/55: bei Öffnung 5 sind beide fällig (14/59), Legendär gewinnt.
        local second = rich()
        second.pity.gold = { sinceEpic = 10, sinceLegendary = 55 }
        local result2 = CrateOpen.open(second, "gold", 10, allowed())
        T.expect(triggeredOf(result2)).toEqual({ "5:legendary:legendary" })
        T.expect(result2.highest).toBe("legendary")
        T.expect(second.pity.gold).toEqual({ sinceEpic = 6, sinceLegendary = 6 })
    end)

    T.it("Holzkiste kostet Münzen (Zahlentyp), auch bei sehr großen Beständen", function()
        local profile = fresh()
        profile.coins = BigNum.serialize(BigNum.new(wood.price))
        local result = CrateOpen.open(profile, "wood", 1, allowed())
        T.expect(result.ok).toBe(true)
        T.expect(BigNum.eq(BigNum.deserialize(profile.coins), BigNum.zero())).toBe(true)
        T.expect(profile.gems).toBe(0)

        local big = fresh()
        big.coins = BigNum.serialize(BigNum.new(5, 30))
        local bundle = CrateOpen.open(big, "wood", 10, allowed())
        T.expect(bundle.ok).toBe(true)
        T.expect(#bundle.results).toBe(11)
        T.expect(BigNum.lt(BigNum.deserialize(big.coins), BigNum.new(5, 30)) or BigNum.eq(BigNum.deserialize(big.coins), BigNum.new(5, 30))).toBe(true)

        local exact = fresh()
        exact.coins = BigNum.serialize(BigNum.new(wood.price * Crates.bundle.buy + 7))
        T.expect(CrateOpen.open(exact, "wood", 10, allowed()).ok).toBe(true)
        T.expect(BigNum.toNumber(BigNum.deserialize(exact.coins))).toBe(7)
    end)

    T.it("Holz- und Eisenkiste haben keine Pity und ändern keinen Zähler", function()
        local profile = rich()
        local pityBefore = deepCopy(profile.pity)
        local a = CrateOpen.open(profile, "wood", 10, allowed())
        local b = CrateOpen.open(profile, "iron", 10, allowed())
        T.expect(a.ok and b.ok).toBe(true)
        T.expect(a.pity).toBeNil()
        T.expect(b.pity).toBeNil()
        T.expect(profile.pity).toEqual(pityBefore)
        T.expect(profile.pity.wood).toBeNil()
        T.expect(profile.gems).toBe(1_000_000 - iron.price * 10)
    end)

    T.it("zu wenig Gems oder Münzen: Grund notEnoughGems bzw. notEnoughCoins, Profil unverändert", function()
        local profile = fresh()
        profile.gems = gold.price - 1
        profile.coins = BigNum.serialize(BigNum.new(wood.price - 1))
        local before = deepCopy(profile)
        T.expect(CrateOpen.open(profile, "gold", 1, allowed()).reason).toBe("notEnoughGems")
        T.expect(CrateOpen.open(profile, "iron", 1, allowed()).ok).toBe(true) -- 399 reichen für Eisen
        profile = deepCopy(before)
        profile.gems = gold.price * Crates.bundle.buy - 1 -- 10 Einzelpreise minus 1
        local before10 = deepCopy(profile)
        T.expect(CrateOpen.open(profile, "gold", 10, allowed()).reason).toBe("notEnoughGems")
        T.expect(profile).toEqual(before10)
        T.expect(CrateOpen.open(profile, "wood", 1, allowed()).reason).toBe("notEnoughCoins")
        T.expect(profile).toEqual(before10)

        local broke = fresh()
        broke.gems = 0 / 0 -- kaputter Stand zählt wie 0
        broke.coins = { m = -5, e = 3 }
        local brokeBefore = deepCopy(broke)
        T.expect(CrateOpen.open(broke, "iron", 1, allowed()).reason).toBe("notEnoughGems")
        T.expect(CrateOpen.open(broke, "wood", 1, allowed()).reason).toBe("notEnoughCoins")
        T.expect(broke).toEqual(brokeBefore)
    end)
end)

T.describe("Sperren (fail-closed)", function()
    T.it("restricted = true oder unbekannt (nil) lehnt jede Kiste ab, auch die Holzkiste", function()
        for _, restricted in { true, nil :: any, "false" :: any, 0 :: any } do
            for _, crate in Crates.list do
                for _, count in { 1, 10 } do
                    local profile = rich()
                    local before = deepCopy(profile)
                    local ctx = { random = constant(0), restricted = restricted, inSeason = true }
                    local result = CrateOpen.open(profile, crate.id, count, ctx)
                    T.expect(result.ok).toBe(false)
                    T.expect(result.reason).toBe("restricted")
                    T.expect(profile).toEqual(before)
                end
            end
        end
    end)

    T.it("ohne Kontext gilt die Policy als unbekannt, also gesperrt", function()
        local profile = rich()
        local before = deepCopy(profile)
        T.expect(CrateOpen.open(profile, "wood", 1, nil :: any).reason).toBe("restricted")
        T.expect(CrateOpen.openFree(profile, "wood", nil :: any).reason).toBe("restricted")
        T.expect(profile).toEqual(before)
    end)

    T.it("Event-Kiste außerhalb der Saison: notInSeason, Profil unverändert", function()
        for _, inSeason in { false, nil :: any, 1 :: any } do
            local profile = rich()
            local before = deepCopy(profile)
            local result = CrateOpen.open(profile, "event", 1, { random = constant(0), restricted = false, inSeason = inSeason })
            T.expect(result.reason).toBe("notInSeason")
            T.expect(profile).toEqual(before)
        end
        local profile = rich()
        T.expect(CrateOpen.openFree(profile, "event", allowed()).reason).toBe("notInSeason")
    end)

    T.it("unbekannte Kiste, falsche Anzahl, kein Profil", function()
        local profile = rich()
        local before = deepCopy(profile)
        T.expect(CrateOpen.open(profile, "silver", 1, allowed()).reason).toBe("unknownCrate")
        T.expect(CrateOpen.open(profile, 5 :: any, 1, allowed()).reason).toBe("unknownCrate")
        for _, count in { 0, 2, 11, -1, 1.5, "1" :: any, nil :: any } do
            T.expect(CrateOpen.open(profile, "gold", count, allowed()).reason).toBe("badCount")
        end
        T.expect(profile).toEqual(before)
        T.expect(CrateOpen.open(nil, "gold", 1, allowed()).reason).toBe("noProfile")
    end)
end)

T.describe("Event-Kiste in der Saison", function()
    T.it("eigener Pity-Zähler pity.event, die Goldkiste zählt getrennt", function()
        local profile = rich()
        local ctx = { random = constant(0), restricted = false, inSeason = true }
        local result = CrateOpen.open(profile, "event", 10, ctx)
        T.expect(result.ok).toBe(true)
        T.expect(profile.pity.event).toEqual({ sinceEpic = 11, sinceLegendary = 11 })
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 0, sinceLegendary = 0 })
        for _, prize in result.results do
            T.expect(CrateItems.byId[prize.itemId].crates).toEqual({ "event" })
        end
        CrateOpen.open(profile, "gold", 1, ctx)
        T.expect(profile.pity.event).toEqual({ sinceEpic = 11, sinceLegendary = 11 })
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 1, sinceLegendary = 1 })
        -- Die 15. Event-Öffnung ohne Episch ist Episch.
        local more = CrateOpen.open(profile, "event", 10, ctx)
        T.expect(more.results[4].pityTriggered).toBe("epic")
        T.expect(rank(more.results[4].rarityId) >= rank("epic")).toBe(true)
    end)

    T.it("ein Profil ohne pity.event bekommt den Zähler beim ersten Öffnen", function()
        local profile = rich()
        profile.pity = { gold = { sinceEpic = 3, sinceLegendary = 3 } }
        local result = CrateOpen.open(profile, "event", 1, { random = constant(0), restricted = false, inSeason = true })
        T.expect(result.ok).toBe(true)
        T.expect(profile.pity.event).toEqual({ sinceEpic = 1, sinceLegendary = 1 })
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 3, sinceLegendary = 3 })
    end)
end)

T.describe("Kein halbes Buchen", function()
    T.it("ein Fehler mitten im Wurf lässt Bezahlung, Inventar und Pity unverändert", function()
        for failAt = 1, 22 do
            local profile = rich()
            profile.inventory.skins.skin_uncommon_1 = 2
            profile.pity.gold = { sinceEpic = 5, sinceLegendary = 9 }
            local before = deepCopy(profile)
            local calls = 0
            local exploding = function(): number
                calls += 1
                if calls == failAt then
                    error("Zufallsgeber kaputt")
                end
                return 0.5
            end
            local result = CrateOpen.open(profile, "gold", 10, allowed(exploding))
            T.expect(result.ok).toBe(false)
            T.expect(result.reason).toBe("error")
            T.expect(result.detail).toContain("Zufallsgeber kaputt")
            T.expect(profile).toEqual(before)
        end
    end)

    T.it("ein ungültiger Zufallswert mitten im Paket bucht nichts", function()
        local profile = rich()
        local before = deepCopy(profile)
        local calls = 0
        local result = CrateOpen.open(profile, "wood", 10, allowed(function(): number
            calls += 1
            return if calls == 15 then 1 else 0.3
        end))
        T.expect(result.reason).toBe("error")
        T.expect(profile).toEqual(before)
    end)

    T.it("wartet der Wurf (yield), wird abgebrochen und nichts gebucht", function()
        local profile = rich()
        local before = deepCopy(profile)
        local calls = 0
        local result = CrateOpen.open(profile, "gold", 10, allowed(function(): number
            calls += 1
            if calls == 3 then
                coroutine.yield()
            end
            return 0.5
        end))
        T.expect(result.reason).toBe("error")
        T.expect(result.detail).toContain("yield")
        T.expect(profile).toEqual(before)
    end)

    T.it("fehlt der Zufall, wird nichts gebucht", function()
        local profile = rich()
        local before = deepCopy(profile)
        T.expect(CrateOpen.open(profile, "gold", 1, { restricted = false } :: any).reason).toBe("error")
        T.expect(profile).toEqual(before)
    end)

    T.it("der Öffnen-Block läuft in einem Zug ohne zu warten", function()
        local profile = rich()
        local routine = coroutine.create(function()
            return CrateOpen.open(profile, "gold", 10, allowed(math.random))
        end)
        local ok, result = coroutine.resume(routine)
        T.expect(ok).toBe(true)
        T.expect(coroutine.status(routine)).toBe("dead")
        T.expect(result.ok).toBe(true)
    end)

    T.it("zwei Aufrufe nacheinander buchen zweimal genau den Preis (kein Doppel-Abzug, kein Gratis-Wurf)", function()
        local profile = fresh()
        profile.gems = gold.price
        T.expect(CrateOpen.open(profile, "gold", 1, allowed()).ok).toBe(true)
        local second = CrateOpen.open(profile, "gold", 1, allowed())
        T.expect(second.reason).toBe("notEnoughGems")
        T.expect(profile.gems).toBe(0)
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 1, sinceLegendary = 1 })
    end)
end)

T.describe("Gewinne und Inventar", function()
    T.it("jedes Item kommt aus dem Pool der Kiste und hat die gewürfelte Seltenheit", function()
        math.randomseed(SEED)
        for _, crate in Crates.list do
            local profile = rich()
            local ctx = { random = math.random, restricted = false, inSeason = true }
            for _ = 1, 100 do
                local result = CrateOpen.open(profile, crate.id, 10, ctx)
                T.expect(result.ok).toBe(true)
                for _, prize in result.results do
                    local item = CrateItems.byId[prize.itemId]
                    T.expect(item ~= nil).toBe(true)
                    T.expect(item.rarity).toBe(prize.rarityId)
                    T.expect(item.kind).toBe(prize.kind)
                    T.expect(item.name).toBe(prize.name)
                    T.expect(table.find(item.crates, crate.id) ~= nil).toBe(true)
                    T.expect((crate.odds[prize.rarityId] or 0) > 0 or prize.pityTriggered ~= nil).toBe(true)
                    T.expect(rank(result.highest) >= rank(prize.rarityId)).toBe(true)
                end
            end
        end
    end)

    T.it("Duplikate erhöhen den Zähler und sind nicht neu", function()
        local profile = rich()
        local result = CrateOpen.open(profile, "wood", 10, allowed(constant(0)))
        local itemId = result.results[1].itemId
        T.expect(result.results[1].isNew).toBe(true)
        for index = 2, 11 do
            T.expect(result.results[index].itemId).toBe(itemId)
            T.expect(result.results[index].isNew).toBe(false)
        end
        T.expect(inventoryCount(profile, itemId)).toBe(11)
        local again = CrateOpen.open(profile, "wood", 1, allowed(constant(0)))
        T.expect(again.results[1].isNew).toBe(false)
        T.expect(inventoryCount(profile, itemId)).toBe(12)
    end)

    T.it("Items landen nach ihrer Art in skins, companions oder toolVariants; anderes bleibt", function()
        local profile = rich()
        profile.inventory.skins.alt_skin = 3
        profile.finds = { dunes_s1_1 = 2 }
        math.randomseed(SEED + 3)
        local ctx = { random = math.random, restricted = false, inSeason = false }
        local seen: { [string]: number } = {}
        for _ = 1, 30 do
            local result = CrateOpen.open(profile, "iron", 10, ctx)
            for _, prize in result.results do
                seen[prize.itemId] = (seen[prize.itemId] or 0) + 1
            end
        end
        for itemId, count in seen do
            T.expect(inventoryCount(profile, itemId)).toBe(count)
        end
        T.expect(profile.inventory.skins.alt_skin).toBe(3)
        T.expect(profile.finds).toEqual({ dunes_s1_1 = 2 })
        local kinds = 0
        for _, field in { "skins", "companions", "toolVariants" } do
            if next(profile.inventory[field]) ~= nil then
                kinds += 1
            end
        end
        T.expect(kinds).toBe(3)
    end)

    T.it("die Antwort enthält nur Kopien, nie Tabellen des Profils", function()
        local profile = rich()
        local result = CrateOpen.open(profile, "gold", 1, allowed())
        T.expect(rawequal(result.pity, profile.pity.gold)).toBe(false)
        T.expect(rawequal(result.coins, profile.coins)).toBe(false)
        result.pity.sinceEpic = 99
        T.expect(profile.pity.gold.sinceEpic).toBe(1)
    end)
end)

T.describe("Gratis-Öffnung (Daily Reward, 5.1)", function()
    T.it("bucht nichts ab und zählt für die Pity", function()
        local profile = fresh()
        profile.gems = 0
        local result = CrateOpen.openFree(profile, "gold", allowed())
        T.expect(result.ok).toBe(true)
        T.expect(result.free).toBe(true)
        T.expect(profile.gems).toBe(0)
        T.expect(#result.results).toBe(1)
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 1, sinceLegendary = 1 })
        T.expect(inventoryCount(profile, result.results[1].itemId)).toBe(1)

        local poor = fresh()
        local coinsBefore = deepCopy(poor.coins)
        T.expect(CrateOpen.openFree(poor, "wood", allowed()).ok).toBe(true)
        T.expect(poor.coins).toEqual(coinsBefore)
    end)

    T.it("die Gratis-Öffnung gibt es nur einzeln und nur bei erlaubter Policy", function()
        local profile = rich()
        local before = deepCopy(profile)
        T.expect(CrateOpen.openFree(profile, "gold", { random = constant(0), restricted = true }).reason).toBe("restricted")
        T.expect(profile).toEqual(before)
    end)

    T.it("ein `free` im Kontext von open() macht die Öffnung nicht gratis", function()
        local profile = rich()
        local gemsBefore: number = profile.gems
        local ctx: any = allowed()
        ctx.free = true
        local result = CrateOpen.open(profile, "gold", 1, ctx)
        T.expect(result.ok).toBe(true)
        T.expect(result.free).toBe(false)
        T.expect(profile.gems).toBe(gemsBefore - Crates.byId.gold.price)
    end)
end)

T.describe("Speichern, Laden, Sandsturm", function()
    -- Wie der DataStore: JSON hin und zurück, dann Laden wie PlayerSession (migrate, sanitize).
    local function saveAndLoad(profile: any): any
        local warnings = Profile.sanitize(profile, NOW)
        T.expect(warnings).toEqual({})
        local stored = serde.decode("json", serde.encode("json", profile))
        local loaded = Profile.migrate(stored, nil, NOW)
        T.expect(Profile.sanitize(loaded, NOW, { trimLists = false })).toEqual({})
        return loaded
    end

    T.it("der Pity-Zähler übersteht Speichern und Laden (Neustart) unverändert", function()
        local profile = rich()
        CrateOpen.open(profile, "gold", 10, allowed()) -- 11 ohne Episch
        CrateOpen.open(profile, "gold", 1, allowed())
        CrateOpen.open(profile, "event", 1, { random = constant(0), restricted = false, inSeason = true })
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 12, sinceLegendary = 12 })
        local loaded = saveAndLoad(profile)
        T.expect(loaded.pity).toEqual(profile.pity)
        T.expect(loaded.inventory).toEqual(profile.inventory)
        T.expect(loaded.gems).toBe(profile.gems)
        -- Nach dem Neustart zählt der Zähler weiter: die 15. Öffnung ist Episch.
        local after = CrateOpen.open(loaded, "gold", 10, allowed())
        T.expect(after.results[3].pityTriggered).toBe("epic")
    end)

    T.it("ein altes Profil ohne pity.event bekommt den Zähler beim Laden (fillDefaults)", function()
        local old = rich()
        old.pity = { gold = { sinceEpic = 4, sinceLegendary = 20 } }
        local stored = serde.decode("json", serde.encode("json", old))
        local loaded = Profile.migrate(stored, nil, NOW)
        T.expect(loaded.pity.event).toEqual({ sinceEpic = 0, sinceLegendary = 0 })
        T.expect(loaded.pity.gold).toEqual({ sinceEpic = 4, sinceLegendary = 20 })
        T.expect(Profile.default(NOW).pity.event).toEqual({ sinceEpic = 0, sinceLegendary = 0 })
    end)

    T.it("sanitize repariert Pity-Zähler: ganze Zahlen ab 0, gekappt auf Grenze - 1", function()
        local profile = fresh()
        profile.pity = {
            gold = { sinceEpic = -3, sinceLegendary = 12.7 },
            event = { sinceEpic = 400, sinceLegendary = 1e9 },
            wood = { sinceEpic = "x", sinceLegendary = 2.5 }, -- Kiste ohne Pity: nur säubern, nicht kappen
            iron = 7, -- kein Zählerstand
            future = { sinceEpic = 80 }, -- unbekannte Kiste: bleibt, Zähler gesäubert
        }
        local warnings = Profile.sanitize(profile, NOW)
        T.expect(#warnings > 0).toBe(true)
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 0, sinceLegendary = 12 })
        T.expect(profile.pity.event).toEqual({ sinceEpic = gold.pity.epic - 1, sinceLegendary = gold.pity.legendary - 1 })
        T.expect(profile.pity.wood).toEqual({ sinceEpic = 0, sinceLegendary = 2 })
        T.expect(profile.pity.iron).toBeNil()
        T.expect(profile.pity.future).toEqual({ sinceEpic = 80, sinceLegendary = 0 })
        -- Ein gekappter Stand löst die Garantie aus, wie der ungekappte.
        T.expect(CrateRoll.guarantee(event, profile.pity.event)).toBe("legendary")
        -- Ein zweiter Durchlauf ändert nichts mehr.
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})

        local broken = fresh()
        broken.pity = "kaputt"
        Profile.sanitize(broken, NOW)
        T.expect(broken.pity).toEqual(Profile.default(NOW).pity)
    end)

    T.it("der Sandsturm behält Pity und Inventar", function()
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "pity") ~= nil).toBe(true)
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "inventory") ~= nil).toBe(true)
        T.expect(table.find(Sandstorm.RESET_FIELDS, "pity")).toBeNil()
        local profile = rich()
        CrateOpen.open(profile, "gold", 10, allowed())
        CrateOpen.open(profile, "event", 1, { random = constant(0), restricted = false, inSeason = true })
        profile.nodes = { collect_tool_2 = true, collect_tool_3 = true, collect_tool_4 = true }
        profile.runEarned = BigNum.serialize(BigNum.new(1, 8))
        local pityBefore = deepCopy(profile.pity)
        local inventoryBefore = deepCopy(profile.inventory)
        local data = { Economy = { sandstorm = { requiresNode = "collect_tool_4", crystalUnit = 1_000_000, crystalExponent = 0.5, crystalScale = 1, minCrystals = 1, maxCrystals = 100_000 } } }
        local stormed = Sandstorm.apply(profile, data)
        T.expect(stormed ~= nil).toBe(true)
        T.expect(profile.pity).toEqual(pityBefore)
        T.expect(profile.inventory).toEqual(inventoryBefore)
    end)
end)

T.finish()
