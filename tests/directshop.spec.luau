--!strict
-- Paket 4.6: Direktkauf von Kisten-Items gegen Gems (Logic/DirectShop). Preise aus den Daten
-- (Erwartungswert der günstigsten Gem-Kiste, aufgerundet, monotone Untergrenze), Kauf nur bei
-- gesperrter oder unbekannter Policy, genau der Preis wird abgebucht, kein halbes Buchen.

local T = require("./lib/expect")
local DirectShop = require("../src/shared/Logic/DirectShop")
local CrateRoll = require("../src/shared/Logic/CrateRoll")
local Profile = require("../src/shared/Logic/Profile")
local Equipment = require("../src/shared/Logic/Equipment")
local Crates = require("../src/shared/Data/Crates")
local CrateItems = require("../src/shared/Data/CrateItems")
local Rarities = require("../src/shared/Data/Rarities")
local Economy = require("../src/shared/Data/Economy")

local NOW = 1_700_000_000

-- Sollpreise des balance-analyst (docs/balance/directshop_4_6.md, Spalte "Mit Untergrenze").
local EXPECTED_PRICES: { [string]: number } = {
    common = 1200,
    uncommon = 1200, -- Untergrenze, Erwartungswert 1.000
    rare = 2000,
    epic = 8000,
    legendary = 25000,
    mythic = 230000,
}
local EXPECTED_COMPANION_RARE_2 = 5100 -- nur in Gold, Erwartungswert 5.055,76

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

local function sameValue(a: any, b: any): boolean
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in a do
        if not sameValue(value, b[key]) then
            return false
        end
    end
    for key in b do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Daten mit geänderter Direktkauf-Einstellung (die echten Tabellen bleiben unberührt).
local function withConfig(change: { [string]: any }): any
    local economy = table.clone(Economy) :: any
    local cfg = table.clone(Economy.directShop) :: any
    for key, value in change do
        cfg[key] = value
    end
    economy.directShop = cfg
    return { Economy = economy }
end

local function isEventOnly(item: any): boolean
    for _, crateId in item.crates do
        if Crates.byId[crateId].eventOnly ~= true then
            return false
        end
    end
    return true
end

local function richProfile(gems: number?): any
    local profile = Profile.default(NOW)
    profile.gems = gems or 1_000_000
    return profile
end

local function copiesOf(profile: any, itemId: string): number
    local item = CrateItems.byId[itemId]
    return profile.inventory[Equipment.INVENTORY_FIELDS[item.kind]][itemId] or 0
end

local RESTRICTED = { policyState = "restricted" }

T.describe("Direktpreis aus den Daten", function()
    T.it("die Preise entsprechen dem Balance-Dokument (2 Stellen, Untergrenze an)", function()
        T.expect(Economy.directShop.roundSignificantDigits).toBe(2)
        T.expect(Economy.directShop.monotoneFloor).toBe(true)
        T.expect(Economy.directShop.crates).toEqual({ "iron", "gold" })
        for _, item in CrateItems.list do
            local price = DirectShop.priceOf(item.id)
            if isEventOnly(item) then
                T.expect(price).toBeNil()
            elseif item.id == "companion_rare_2" then
                T.expect(price).toBe(EXPECTED_COMPANION_RARE_2)
            else
                T.expect(price).toBe(EXPECTED_PRICES[item.rarity])
            end
        end
    end)

    T.it("nie unter dem Erwartungswert der günstigsten Gem-Kiste (Einzelpreis), ganze Gems, höchstens maxGems", function()
        for _, item in CrateItems.list do
            local price = DirectShop.priceOf(item.id)
            if price == nil then
                continue
            end
            -- Erwartungswert unabhängig nachgerechnet: Einzelpreis / (Langzeitrate / Poolgröße), je Gem-Kiste.
            local best = math.huge
            for _, crateId in item.crates do
                local crate = Crates.byId[crateId]
                if crate.currency == "gems" and not crate.eventOnly then
                    local p = CrateRoll.longRunRates(crate)[item.rarity] / #CrateRoll.pool(crateId, item.rarity)
                    best = math.min(best, crate.price / p)
                end
            end
            T.expect(DirectShop.expectedValueOf(item.id)).toBeCloseTo(best, 1e-6)
            T.expect(price >= best - 1e-6).toBe(true)
            T.expect(price % 1).toBe(0)
            T.expect(price <= Economy.purchases.maxGems).toBe(true)
            -- Aufschlag durch die 2-Stellen-Rundung höchstens 10 % (ohne Untergrenze gerechnet).
            local unfloored = DirectShop.priceOf(item.id, withConfig({ monotoneFloor = false })) :: number
            T.expect(unfloored <= best * 1.1 + 1e-6).toBe(true)
        end
    end)

    T.it("Eisen ohne Pity rechnet exakt: 1000 bleibt 1000 (ohne Untergrenze)", function()
        local data = withConfig({ monotoneFloor = false })
        T.expect(DirectShop.priceOf("skin_uncommon_1", data)).toBe(1000)
        T.expect(DirectShop.priceOf("skin_common_1", data)).toBe(1200)
        T.expect(DirectShop.priceOf("skin_rare_1", data)).toBe(2000)
        T.expect(DirectShop.priceOf("skin_epic_1", data)).toBe(8000)
        T.expect(DirectShop.expectedValueOf("skin_uncommon_1", data)).toBe(1000)
    end)

    T.it("Untergrenze: jede Seltenheit kostet mindestens den Einstiegspreis jeder niedrigeren", function()
        local catalog = DirectShop.catalog()
        local entryByRank: { [number]: number } = {}
        for _, entry in catalog do
            local r = Rarities.byId[entry.rarityId].rank
            entryByRank[r] = math.min(entryByRank[r] or math.huge, entry.price)
        end
        for _, entry in catalog do
            local r = Rarities.byId[entry.rarityId].rank
            for otherRank, entryPrice in entryByRank do
                if otherRank < r then
                    T.expect(entry.price >= entryPrice).toBe(true)
                end
            end
        end
        -- Die Untergrenze hebt nur an.
        for _, entry in catalog do
            T.expect(entry.price >= (DirectShop.priceOf(entry.itemId, withConfig({ monotoneFloor = false })) :: number)).toBe(true)
        end
    end)

    T.it("andere Stellenzahl: 3 Stellen ergeben 1.150, 24.800 und 223.000", function()
        local data = withConfig({ roundSignificantDigits = 3, monotoneFloor = false })
        T.expect(DirectShop.priceOf("skin_common_1", data)).toBe(1150)
        T.expect(DirectShop.priceOf("skin_uncommon_1", data)).toBe(1000)
        T.expect(DirectShop.priceOf("skin_legendary_1", data)).toBe(24800)
        T.expect(DirectShop.priceOf("skin_mythic_1", data)).toBe(223000)
    end)

    T.it("Aufrunden auf gültige Stellen: Rechenfehler zählen nicht, sonst immer aufwärts", function()
        T.expect(DirectShop.roundUp(1000, 2)).toBe(1000)
        T.expect(DirectShop.roundUp(1000.0000000001, 2)).toBe(1000)
        T.expect(DirectShop.roundUp(999.9999999999, 2)).toBe(1000)
        T.expect(DirectShop.roundUp(1001, 2)).toBe(1100)
        T.expect(DirectShop.roundUp(1142.857, 2)).toBe(1200)
        T.expect(DirectShop.roundUp(222767.37, 2)).toBe(230000)
        T.expect(DirectShop.roundUp(5055.76, 2)).toBe(5100)
        T.expect(DirectShop.roundUp(99.5, 2)).toBe(100)
        T.expect(DirectShop.roundUp(5.3, 2)).toBe(6) -- nie unter ganzen Gems
        T.expect(DirectShop.roundUp(24751.93, 1)).toBe(30000)
    end)

    T.it("kein Preis: unbekannte Items, Event-Items, Items nur in Münz- oder Event-Kisten", function()
        T.expect(DirectShop.priceOf("gibt_es_nicht")).toBeNil()
        T.expect(DirectShop.priceOf(5 :: any)).toBeNil()
        T.expect(DirectShop.priceOf("skin_mythic_2")).toBeNil() -- Event
        T.expect(DirectShop.priceOf("toolVariant_uncommon_2")).toBeNil() -- Event
        -- Ein Item nur in der Holzkiste (Münzen) hat keinen Preis.
        local items = deepCopy(CrateItems)
        local woodOnly = { id = "skin_wood_only", kind = "skin", name = "Holz", rarity = "common", crates = { "wood" }, effectBp = 500 }
        table.insert(items.list, woodOnly)
        items.byId[woodOnly.id] = woodOnly
        T.expect(DirectShop.priceOf("skin_wood_only", { CrateItems = items })).toBeNil()
        -- Steht die Event-Kiste (fälschlich) in der Liste, bekommen Event-Items trotzdem keinen Preis.
        T.expect(DirectShop.priceOf("skin_mythic_2", withConfig({ crates = { "iron", "gold", "event" } }))).toBeNil()
        -- Nur Gold in der Liste: das Gold-Ergebnis gilt.
        T.expect(DirectShop.priceOf("skin_uncommon_1", withConfig({ crates = { "gold" }, monotoneFloor = false }))).toBe(4100)
    end)

    T.it("der Katalog hat genau die Items mit Preis, dieselben Preise wie priceOf, sortiert nach Seltenheit", function()
        local catalog = DirectShop.catalog()
        local count = 0
        for _, item in CrateItems.list do
            if not isEventOnly(item) then
                count += 1
            end
        end
        T.expect(#catalog).toBe(count)
        local lastRank = 0
        for _, entry in catalog do
            local item = CrateItems.byId[entry.itemId]
            T.expect(entry.price).toBe(DirectShop.priceOf(entry.itemId))
            T.expect(entry.kind).toBe(item.kind)
            T.expect(entry.rarityId).toBe(item.rarity)
            T.expect(entry.name).toBe(item.name)
            local r = Rarities.byId[entry.rarityId].rank
            T.expect(r >= lastRank).toBe(true)
            lastRank = r
        end
    end)

    T.it("Preise kommen aus den Daten: eine teurere Eisenkiste macht die Items teurer", function()
        local crates = deepCopy(Crates)
        crates.byId.iron.price = 200
        local data = { Crates = crates, Economy = withConfig({ monotoneFloor = false }).Economy }
        T.expect(DirectShop.priceOf("skin_rare_1", data)).toBe(4000)
        T.expect(DirectShop.priceOf("skin_uncommon_1", data)).toBe(2000)
    end)
end)

T.describe("Direktkauf: offen nur bei gesperrter oder unbekannter Policy", function()
    T.it("isOpen: restricted und unknown ja; pending, allowed, none und nil nein", function()
        T.expect(DirectShop.isOpen("restricted")).toBe(true)
        T.expect(DirectShop.isOpen("unknown")).toBe(true)
        for _, state in { "pending", "allowed", "none", "", "RESTRICTED", 1, true } :: { any } do
            T.expect(DirectShop.isOpen(state)).toBe(false)
        end
        T.expect(DirectShop.isOpen(nil)).toBe(false)
    end)

    T.it("nie während der ersten Abfrage und nie bei erlaubten Kisten: cratesAllowed, Profil unverändert", function()
        for _, state in { "pending", "allowed", "none" } do
            local profile = richProfile()
            local before = deepCopy(profile)
            local result = DirectShop.buy(profile, "skin_rare_1", { policyState = state })
            T.expect(result.ok).toBe(false)
            T.expect(result.reason).toBe("cratesAllowed")
            T.expect(profile).toEqual(before)
        end
        local profile = richProfile()
        T.expect(DirectShop.buy(profile, "skin_rare_1", nil :: any).reason).toBe("cratesAllowed")
        T.expect(DirectShop.buy(profile, "skin_rare_1", {}).reason).toBe("cratesAllowed")
    end)
end)

T.describe("Direktkauf: Buchung", function()
    T.it("genau der Preis wird abgebucht, Inventar +1, nichts ausgerüstet, Pity unverändert", function()
        for _, state in { "restricted", "unknown" } do
            local profile = richProfile(10_000)
            profile.pity.gold = { sinceEpic = 7, sinceLegendary = 33 }
            local before = deepCopy(profile)
            local result = DirectShop.buy(profile, "skin_rare_1", { policyState = state })
            T.expect(result).toEqual({ ok = true, itemId = "skin_rare_1", price = 2000, gems = 8000, copies = 1 })
            T.expect(profile.gems).toBe(8000)
            T.expect(copiesOf(profile, "skin_rare_1")).toBe(1)
            T.expect(profile.pity).toEqual(before.pity)
            T.expect(profile.equipped).toEqual(before.equipped)
            T.expect(profile.itemStars).toEqual(before.itemStars)
            -- Sonst ändert sich nur das Inventar.
            local changed = {}
            for key, value in profile do
                if not sameValue(value, before[key]) then
                    table.insert(changed, key)
                end
            end
            table.sort(changed)
            T.expect(changed).toEqual({ "gems", "inventory" })
        end
    end)

    T.it("zweimal kaufen: zweimal genau der Preis, zwei Exemplare; vorhandene Items bleiben", function()
        local profile = richProfile(5000)
        profile.inventory.companions.companion_rare_1 = 3
        T.expect(DirectShop.buy(profile, "skin_common_1", RESTRICTED).copies).toBe(1)
        local second = DirectShop.buy(profile, "skin_common_1", RESTRICTED)
        T.expect(second.copies).toBe(2)
        T.expect(second.gems).toBe(5000 - 2 * 1200)
        T.expect(profile.gems).toBe(2600)
        T.expect(profile.inventory.companions.companion_rare_1).toBe(3)
        -- Jede Art landet im eigenen Feld.
        DirectShop.buy(profile, "companion_common_1", RESTRICTED)
        DirectShop.buy(profile, "toolVariant_common_1", RESTRICTED)
        T.expect(profile.inventory.companions.companion_common_1).toBe(1)
        T.expect(profile.inventory.toolVariants.toolVariant_common_1).toBe(1)
        T.expect(profile.gems).toBe(200)
    end)

    T.it("genau genug Gems reicht, einer weniger nicht", function()
        local exact = richProfile(230000)
        T.expect(DirectShop.buy(exact, "skin_mythic_1", RESTRICTED).ok).toBe(true)
        T.expect(exact.gems).toBe(0)
        local short = richProfile(229999)
        local before = deepCopy(short)
        T.expect(DirectShop.buy(short, "skin_mythic_1", RESTRICTED).reason).toBe("notEnoughGems")
        T.expect(short).toEqual(before)
    end)

    T.it("Ablehnungen in fester Reihenfolge, Profil jeweils unverändert", function()
        local cases: { { any } } = {
            -- { Profil, Item, Policy, Grund }
            { richProfile(), "gibt_es_nicht", "allowed", "unknownItem" },
            { richProfile(), 42, "restricted", "unknownItem" },
            { nil, "gibt_es_nicht", "restricted", "unknownItem" },
            { richProfile(), "skin_mythic_2", "allowed", "notOffered" }, -- Event-Item, vor der Policy
            { nil, "skin_mythic_2", "restricted", "notOffered" },
            { nil, "skin_rare_1", "allowed", "cratesAllowed" },
            { nil, "skin_rare_1", "restricted", "noProfile" },
            { richProfile(0), "skin_rare_1", "restricted", "notEnoughGems" },
            { richProfile(1999), "skin_rare_1", "unknown", "notEnoughGems" },
        }
        for _, case in cases do
            local profile = case[1]
            local before = deepCopy(profile)
            local result = DirectShop.buy(profile, case[2], { policyState = case[3] })
            T.expect(result.ok).toBe(false)
            T.expect(result.reason).toBe(case[4])
            T.expect(profile).toEqual(before)
        end
    end)

    T.it("kaputter Gem-Stand zählt wie 0 (notEnoughGems), kaputtes Inventar wird ersetzt", function()
        for _, bad in { 0 / 0, -5, math.huge, "1000" } :: { any } do
            local profile = richProfile()
            profile.gems = bad
            T.expect(DirectShop.buy(profile, "skin_common_1", RESTRICTED).reason).toBe("notEnoughGems")
        end
        local profile = richProfile(1200)
        profile.inventory = "kaputt"
        local result = DirectShop.buy(profile, "skin_common_1", RESTRICTED)
        T.expect(result.ok).toBe(true)
        T.expect(profile.inventory.skins).toEqual({ skin_common_1 = 1 })
    end)
end)

T.describe("Direktkauf: kein halbes Buchen", function()
    T.it("ein Fehler im Block (unbekannte Item-Art) bucht nichts: Grund error mit detail", function()
        local items = deepCopy(CrateItems)
        items.byId.skin_rare_1.kind = "hut"
        local profile = richProfile(5000)
        local before = deepCopy(profile)
        local result = DirectShop.buy(profile, "skin_rare_1", { policyState = "restricted", data = { CrateItems = items } })
        T.expect(result.ok).toBe(false)
        T.expect(result.reason).toBe("error")
        T.expect(result.detail).toContain("Item-Art")
        T.expect(profile).toEqual(before)
    end)

    T.it("wartet der Block (yield), wird abgebrochen und nichts gebucht", function()
        -- Economy, das beim Zugriff auf die Gem-Regeln (nach der Preisrechnung) wartet.
        local economy = setmetatable({}, {
            __index = function(_: any, key: string): any
                if key == "purchases" then
                    coroutine.yield()
                end
                return (Economy :: any)[key]
            end,
        })
        local profile = richProfile(5000)
        local before = deepCopy(profile)
        local result = DirectShop.buy(profile, "skin_rare_1", { policyState = "restricted", data = { Economy = economy } })
        T.expect(result.ok).toBe(false)
        T.expect(result.reason).toBe("error")
        T.expect(result.detail).toContain("yield")
        T.expect(profile).toEqual(before)
    end)

    T.it("die Antwort enthält keine Tabellen des Profils", function()
        local profile = richProfile(5000)
        local result = DirectShop.buy(profile, "skin_rare_1", RESTRICTED)
        for _, value in result do
            T.expect(type(value) ~= "table").toBe(true)
        end
    end)
end)

T.describe("Ersatzgegenstand Tag 7 (Daily Reward)", function()
    T.it("ist die Kupferschaufel: festes Item, kein Event-Item, mit Direktpreis", function()
        local itemId = Economy.daily.day7FallbackItemId
        T.expect(itemId).toBe("toolVariant_uncommon_1")
        T.expect(CrateItems.byId[itemId] ~= nil).toBe(true)
        T.expect(isEventOnly(CrateItems.byId[itemId])).toBe(false)
        T.expect(DirectShop.priceOf(itemId)).toBe(1200)
    end)
end)

T.finish()
