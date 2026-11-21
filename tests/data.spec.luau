--!strict
-- Paket 0.1: Datentabellen laden ohne Roblox-API und bestehen die DataCheck-Prüfung.

local T = require("./lib/expect")
local DataCheck = require("../src/shared/Logic/DataCheck")

local Rarities = require("../src/shared/Data/Rarities")
local Tools = require("../src/shared/Data/Tools")
local SandTypes = require("../src/shared/Data/SandTypes")
local Zones = require("../src/shared/Data/Zones")
local FindOdds = require("../src/shared/Data/FindOdds")
local Finds = require("../src/shared/Data/Finds")
local Crates = require("../src/shared/Data/Crates")
local GemPacks = require("../src/shared/Data/GemPacks")
local Products = require("../src/shared/Data/Products")
local Economy = require("../src/shared/Data/Economy")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local OffersData = require("../src/shared/Data/Offers")

-- Tiefe Kopie, die gemeinsame Referenzen (Event-Kiste = Goldkiste) erhält.
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

local function freshDataSet(): DataCheck.DataSet
    return deepCopy(DataCheck.defaults())
end

local function expectError(errors: { string }, fragment: string)
    T.expect(#errors > 0).toBe(true)
    T.expect(table.concat(errors, "\n")).toContain(fragment)
end

T.describe("Datentabellen (0.1)", function()
    T.it("alle Datenmodule laden und DataCheck findet keine Fehler", function()
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("Farben sind Hex-Text und keine Roblox-Typen", function()
        for _, rarity in Rarities.list do
            T.expect(type(rarity.colorHex)).toBe("string")
        end
        for _, sandType in SandTypes.list do
            T.expect(type(sandType.colorHex)).toBe("string")
        end
    end)

    T.it("jede Quotentabelle ergibt 10000 (Fundquoten und Kisten)", function()
        local checked = 0
        local function sum(odds: { [string]: number }): number
            local total = 0
            for _, value in odds do
                total += value
            end
            return total
        end
        for _, odds in FindOdds.tables do
            T.expect(sum(odds)).toBe(10000)
            checked += 1
        end
        for _, odds in Crates.Odds do
            T.expect(sum(odds)).toBe(10000)
            checked += 1
        end
        T.expect(checked).toBe(4)
    end)

    T.it("Quoten sind ganze Zahlen ab 0 mit bekannten Seltenheiten", function()
        local function check(odds: { [string]: number })
            for rarityId, value in odds do
                T.expect(Rarities.byId[rarityId] ~= nil).toBe(true)
                T.expect(value >= 0 and value % 1 == 0).toBe(true)
            end
        end
        for _, odds in FindOdds.tables do
            check(odds)
        end
        for _, odds in Crates.Odds do
            check(odds)
        end
    end)

    T.it("Tippfehler-Seltenheit und Bruchzahl werden gemeldet", function()
        local data = freshDataSet()
        data.Crates.Odds.wood.comon = 0
        expectError(DataCheck.run(data), "unbekannte Seltenheit")

        local data2 = freshDataSet()
        data2.Crates.Odds.iron.common = 3500.5
        data2.Crates.Odds.iron.uncommon = 3999.5
        expectError(DataCheck.run(data2), "ganze Zahl")

        local data3 = freshDataSet()
        data3.Crates.Odds.iron.common = 3600
        data3.Crates.Odds.iron.uncommon = 3900
        data3.Crates.Odds.iron.rare = 2100
        data3.Crates.Odds.iron.epic = 400
        data3.Crates.Odds.iron.legendary = -100
        expectError(DataCheck.run(data3), "ganze Zahl ab 0")
    end)

    T.it("eine absichtlich kaputte Tabelle (Summe 9999) lässt die Prüfung fehlschlagen", function()
        local data = freshDataSet()
        data.FindOdds.tables.base.common = 6999
        expectError(DataCheck.run(data), "Quoten ergeben 9999 statt 10000")

        local data2 = freshDataSet()
        data2.Crates.Odds.gold.mythic = 49
        expectError(DataCheck.run(data2), "9999")
    end)

    T.it("neue Quotentabellen werden automatisch mitgeprüft", function()
        local data = freshDataSet()
        data.FindOdds.tables.rain = { common = 5000, rare = 4999 }
        expectError(DataCheck.run(data), "FindOdds.rain")
        local data2 = freshDataSet()
        data2.Crates.Odds.silver = { common = 10001 }
        expectError(DataCheck.run(data2), "Crates.Odds.silver")
    end)

    T.it("die Event-Kiste verweist auf dieselbe Quotentabelle wie die Goldkiste", function()
        T.expect(rawequal(Crates.byId.event.odds, Crates.byId.gold.odds)).toBe(true)
        T.expect(rawequal(Crates.byId.gold.odds, Crates.Odds.gold)).toBe(true)

        local data = freshDataSet()
        local copy = deepCopy(data.Crates.byId.gold.odds)
        data.Crates.byId.event.odds = copy
        data.Crates.list[4].odds = copy
        expectError(DataCheck.run(data), "Event-Kiste")
    end)

    T.it("alle IDs sind pro Tabelle eindeutig", function()
        local modules: { [string]: any } = {
            Rarities = Rarities,
            Tools = Tools,
            SandTypes = SandTypes,
            Zones = Zones,
            Crates = Crates,
            GemPacks = GemPacks,
            Products = Products,
            UpgradeTree = UpgradeTree,
        }
        for name, module in modules do
            local seen: { [string]: boolean } = {}
            for _, entry in module.list do
                T.expect(seen[entry.id]).toBeNil()
                seen[entry.id] = true
            end
            local count = 0
            for _ in module.byId do
                count += 1
            end
            T.expect(count).toBe(#module.list)
            T.expect(name ~= "").toBe(true)
        end

        local data = freshDataSet()
        table.insert(data.Zones.list, data.Zones.list[1])
        expectError(DataCheck.run(data), "doppelt")
    end)

    T.it("Werkzeuge steigen streng, die Hand kostet 0, jede Stufe hat einen Knoten", function()
        T.expect(Tools.list[1].cost).toBe(0)
        for index = 2, #Tools.list do
            T.expect(Tools.list[index].sandPerSecond > Tools.list[index - 1].sandPerSecond).toBe(true)
            T.expect(Tools.list[index].cost > Tools.list[index - 1].cost).toBe(true)
            T.expect(UpgradeTree.byId[Tools.list[index].nodeId] ~= nil).toBe(true)
        end

        local data = freshDataSet()
        data.Tools.list[3].sandPerSecond = 5
        expectError(DataCheck.run(data), "sandPerSecond muss streng steigen")

        local data2 = freshDataSet()
        data2.Tools.list[1].cost = 1
        expectError(DataCheck.run(data2), "Hand muss 0 Münzen kosten")

        local data3 = freshDataSet()
        data3.Tools.list[4].nodeId = "gibt_es_nicht"
        expectError(DataCheck.run(data3), "fehlt in UpgradeTree")
    end)

    T.it("Zonen verweisen auf Sandsorten und auf start oder einen existierenden Knoten", function()
        for _, zone in Zones.list do
            T.expect(SandTypes.byId[zone.sandTypeId] ~= nil).toBe(true)
            T.expect(zone.requires == "start" or UpgradeTree.byId[zone.requires] ~= nil).toBe(true)
        end
        T.expect(Zones.byId.oasis.requires).toBe("collect_tool_3")
        T.expect(Zones.byId.canyon.requires).toBe("collect_tool_4")
        T.expect(Zones.byId.salt_lake.requires).toBe("collect_tool_5")
        T.expect(Zones.byId.ruins.requires).toBe("sandstorm_ruins")

        local data = freshDataSet()
        data.Zones.byId.oasis.sandTypeId = "pink"
        expectError(DataCheck.run(data), "unbekannte Sandsorte")

        local data2 = freshDataSet()
        data2.Zones.byId.canyon.requires = 5000
        expectError(DataCheck.run(data2), "requires muss")

        local data3 = freshDataSet()
        data3.Zones.byId.canyon.requires = "collect_milestone_9"
        expectError(DataCheck.run(data3), "fehlt in UpgradeTree")
    end)

    T.it("Gem-Pakete: Bonus stimmt auf 1 Prozentpunkt, Gems und Robux steigen", function()
        local smallest = GemPacks.list[1]
        for index, pack in GemPacks.list do
            local bonus = ((pack.gems / pack.robux) / (smallest.gems / smallest.robux) - 1) * 100
            T.expect(math.abs(bonus - pack.bonusPercentConcept) <= 1).toBe(true)
            if index > 1 then
                T.expect(pack.gems > GemPacks.list[index - 1].gems).toBe(true)
                T.expect(pack.robux > GemPacks.list[index - 1].robux).toBe(true)
            end
        end

        local data = freshDataSet()
        data.GemPacks.list[3].bonusPercentConcept = 25
        expectError(DataCheck.run(data), "Bonus")

        local data2 = freshDataSet()
        data2.GemPacks.list[2].robux = 30
        expectError(DataCheck.run(data2), "steigen")
    end)

    T.it("Kisten: Preis über 0, Währung coins oder gems, Pity 15/60, 10er-Paket 10 zu 11", function()
        for _, crate in Crates.list do
            T.expect(crate.price > 0).toBe(true)
            T.expect(crate.currency == "coins" or crate.currency == "gems").toBe(true)
        end
        local pity = Crates.byId.gold.pity :: any
        T.expect(pity.epic).toBe(15)
        T.expect(pity.legendary).toBe(60)
        T.expect(Crates.bundle.buy).toBe(10)
        T.expect(Crates.bundle.get).toBe(11)

        local data = freshDataSet()
        data.Crates.byId.iron.price = 0
        expectError(DataCheck.run(data), "price muss größer als 0")

        local data2 = freshDataSet()
        data2.Crates.byId.wood.currency = "robux"
        expectError(DataCheck.run(data2), "currency")

        local data3 = freshDataSet()
        data3.Crates.byId.gold.pity.epic = 20
        expectError(DataCheck.run(data3), "pity")

        local data4 = freshDataSet()
        data4.Crates.bundle.get = 12
        expectError(DataCheck.run(data4), "bundle")
    end)

    T.it("Finds: 6 Sets zu je 5 pro Zone, 150 Fundstücke", function()
        T.expect(#Finds.sets).toBe(#Zones.list * 6)
        T.expect(#Finds.list).toBe(#Zones.list * 30)
        for _, findSet in Finds.sets do
            T.expect(Zones.byId[findSet.zoneId] ~= nil).toBe(true)
            T.expect(findSet.size).toBe(5)
        end
    end)

    T.it("Knoten verlangen nur existierende Knoten und der Baum hat keinen Zyklus", function()
        local data = freshDataSet()
        data.UpgradeTree.byId.collect_tool_2.requires = { "collect_tool_3" }
        expectError(DataCheck.run(data), "Zyklus")
    end)

    T.it("alle Balance-Werte sind gesetzt und positiv", function()
        T.expect(Economy.baseCoinsPerSand > 0).toBe(true)
        T.expect(Economy.startTankCapacity > 0).toBe(true)
        T.expect(Economy.bigTankMultiplier > 1).toBe(true)
        T.expect(FindOdds.findChancePerSecond > 0).toBe(true)
        T.expect(FindOdds.findBaseValue > 0).toBe(true)
        for _, zone in Zones.list do
            T.expect(FindOdds.zoneFindChanceFactor[zone.id] > 0).toBe(true)
        end
        T.expect(#Economy.daily.days).toBe(6)
        -- Arten der Daily Reward seit Paket 5.1 (Logic/Daily): Boosts mit Sekunden, Gems mit Menge.
        local validKinds: { [string]: boolean } = { coinBoost = true, luck = true, gems = true }
        for _, reward in Economy.daily.days do
            T.expect(validKinds[reward.kind]).toBe(true)
            if reward.kind == "gems" then
                T.expect((reward.amount or 0) > 0).toBe(true)
            else
                T.expect((reward.seconds or 0) > 0).toBe(true)
            end
        end
        T.expect(Products.byId.double_coins.productId).toBe(0)
    end)

    T.it("DataCheck meldet fehlende oder ungültige Balance-Werte", function()
        local function broken(change: (data: any) -> ()): { string }
            local data = freshDataSet()
            change(data)
            return DataCheck.run(data)
        end
        expectError(broken(function(d) d.Economy.baseCoinsPerSand = 0 end), "baseCoinsPerSand")
        expectError(broken(function(d) d.Economy.startTankCapacity = 0 end), "startTankCapacity")
        expectError(broken(function(d) d.Economy.bigTankMultiplier = 1 end), "bigTankMultiplier")
        -- Offline-Ertrag (5.3)
        expectError(broken(function(d) d.Economy.offline.rateFactor = 0 end), "rateFactor")
        expectError(broken(function(d) d.Economy.offline.rateFactor = 1.5 end), "rateFactor")
        expectError(broken(function(d) d.Economy.offline.rateFactor = nil end), "rateFactor")
        expectError(broken(function(d) d.Economy.offline.autoDigHours = 120 end), "höchstens 48")
        expectError(broken(function(d) d.Economy.offline.minSeconds = -1 end), "minSeconds")
        expectError(broken(function(d) d.Economy.offline.minSeconds = 4 * 3600 end), "minSeconds")
        expectError(broken(function(d) d.FindOdds.findChancePerSecond = 0 end), "findChancePerSecond")
        expectError(broken(function(d) d.FindOdds.findBaseValue = 0 end), "findBaseValue")
        expectError(broken(function(d) d.FindOdds.zoneFindChanceFactor.ruins = nil end), "ruins")
        expectError(broken(function(d) d.Economy.daily.days[2].kind = "geld" end), "unbekannte Art")
        expectError(broken(function(d) d.Economy.daily.days[1].seconds = nil end), "seconds")
        expectError(broken(function(d) d.Economy.daily.days[1].seconds = 0 end), "seconds")
        expectError(broken(function(d) table.remove(d.Economy.daily.days) end), "Tag 1 bis 6")
    end)
end)

T.describe("Knoten und Tutorial (1.6)", function()
    local function broken(change: (data: any) -> ()): { string }
        local data = freshDataSet()
        change(data)
        return DataCheck.run(data)
    end

    T.it("eine kaputte Fassung schlägt fehl", function()
        expectError(broken(function(d) d.UpgradeTree.byId.tank_1.name = nil end), "name fehlt")
        expectError(broken(function(d) d.UpgradeTree.byId.tank_1.description = "" end), "description fehlt")
        expectError(broken(function(d) d.UpgradeTree.byId.tank_1.effect.kind = "magie" end), "unbekannte Wirkung")
        expectError(broken(function(d) d.UpgradeTree.byId.tank_1.effect.capacity = 0 end), "setTank")
        expectError(broken(function(d) d.UpgradeTree.byId.collect_rate_1.effect.bp = 1.5 end), "rateBonus")
        expectError(broken(function(d) d.UpgradeTree.byId.tank_2.effect.capacity = 30 end), "Tank muss größer sein")
        expectError(broken(function(d) d.Tutorial.steps = {} end), "Tutorial.steps")
        expectError(broken(function(d) d.Tutorial.steps[3].done.nodeId = "gibt_es_nicht" end), "fehlt in UpgradeTree")
        expectError(broken(function(d) d.Tutorial.steps[1].done.kind = "magie" end), "unbekannte Bedingung")
        expectError(broken(function(d) d.Tutorial.steps[1].target = "mond" end), "unbekanntes Ziel")
        expectError(broken(function(d) d.Tutorial.steps[1].text = "" end), "text fehlt")
        expectError(broken(function(d) d.Tutorial.steps[2].id = d.Tutorial.steps[1].id end), "doppelt")
        expectError(broken(function(d) d.Tutorial.steps[4].highlightNodeId = "x" end), "highlightNodeId")
        expectError(broken(function(d) d.World.sandField = nil end), "sandField")
        expectError(broken(function(d) d.Tutorial.showUpgradesFromStep = 9 end), "showUpgradesFromStep")
        expectError(broken(function(d) d.Tutorial.steps[1].done.amount = 99 end), "startTankCapacity")
        expectError(broken(function(d) d.UpgradeTree.byId.sandstorm_1.granted = nil end), "gehören zusammen")
        expectError(broken(function(d) d.UpgradeTree.byId.tank_1.cost = 0 end), "Preis über 0")
    end)
end)

T.describe("Terrain-Daten (1.4)", function()
    local function broken(change: (data: any) -> ()): { string }
        local data = freshDataSet()
        change(data)
        return DataCheck.run(data)
    end

    T.it("jede Werkzeugstufe hat eine Lochgröße, Materialien sind Text", function()
        local Terrain = require("../src/shared/Data/Terrain")
        for _, tool in Tools.list do
            T.expect(Terrain.holeByTool[tool.id] ~= nil).toBe(true)
        end
        for _, name in Terrain.diggableMaterials do
            T.expect(type(name)).toBe("string")
        end
        T.expect(Terrain.chunkSize % Terrain.voxelSize).toBe(0)
    end)

    T.it("eine kaputte Fassung schlägt fehl", function()
        expectError(broken(function(d) d.Terrain.chunkSize = 10 end), "chunkSize")
        expectError(broken(function(d) d.Terrain.holeByTool.mega_machine = nil end), "mega_machine")
        expectError(broken(function(d) d.Terrain.holeByTool.hand.radius = 0 end), "hand.radius")
        expectError(broken(function(d) d.Terrain.holeByTool.hand.depth = 99 end), "depth")
        expectError(broken(function(d) d.Terrain.defaultToolId = "bagger" end), "defaultToolId")
        expectError(broken(function(d) d.Terrain.dig.intervalSeconds = 0 end), "intervalSeconds")
        expectError(broken(function(d) d.Terrain.dig.maxDepthStuds = 0 / 0 end), "maxDepthStuds")
        expectError(broken(function(d) d.Terrain.regrow.steps = 1.5 end), "steps")
        expectError(broken(function(d) d.Terrain.regrow.maxWritesPerUpdate = 0 end), "maxWritesPerUpdate")
        expectError(broken(function(d) d.Terrain.perf.highFps = d.Terrain.perf.lowFps end), "highFps")
        expectError(broken(function(d) d.Terrain.diggableMaterials = { 5 } end), "diggableMaterials")
        expectError(broken(function(d) d.Terrain.placeholderField.material = nil end), "material")
        expectError(broken(function(d) d.Terrain.placeholderField.sandTypeId = "pink" end), "sandTypeId")
        expectError(broken(function(d) d.Terrain = nil end), "Terrain fehlt")
    end)
end)

T.describe("Käufe (4.1)", function()
    local function broken(change: (data: any) -> ()): { string }
        local data = freshDataSet()
        change(data)
        return DataCheck.run(data)
    end

    T.it("Economy.purchases hat die Werte aus dem Plan und besteht die Prüfung", function()
        T.expect(Economy.purchases).toEqual({
            receiptCacheSize = 100,
            purchaseLogSize = 50,
            saveTimeoutSeconds = 30,
            maxGems = 10_000_000,
        })
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("DataCheck meldet purchases-Werte außerhalb der Grenzen", function()
        expectError(broken(function(d) d.Economy.purchases = nil end), "Economy.purchases: Tabelle fehlt")
        expectError(broken(function(d) d.Economy.purchases.receiptCacheSize = 0 end), "receiptCacheSize")
        expectError(broken(function(d) d.Economy.purchases.receiptCacheSize = 49 end), "receiptCacheSize muss eine ganze Zahl von 50")
        expectError(broken(function(d) d.Economy.purchases.receiptCacheSize = 1001 end), "receiptCacheSize")
        expectError(broken(function(d) d.Economy.purchases.receiptCacheSize = 10.5 end), "receiptCacheSize")
        expectError(broken(function(d) d.Economy.purchases.purchaseLogSize = 0 end), "purchaseLogSize")
        expectError(broken(function(d) d.Economy.purchases.purchaseLogSize = 501 end), "purchaseLogSize")
        expectError(broken(function(d) d.Economy.purchases.saveTimeoutSeconds = 0 end), "saveTimeoutSeconds")
        expectError(broken(function(d) d.Economy.purchases.saveTimeoutSeconds = 121 end), "saveTimeoutSeconds")
        expectError(broken(function(d) d.Economy.purchases.saveTimeoutSeconds = 0 / 0 end), "saveTimeoutSeconds")
        expectError(broken(function(d) d.Economy.purchases.maxGems = 0 end), "maxGems")
        expectError(broken(function(d) d.Economy.purchases.maxGems = 999_999 end), "maxGems muss eine ganze Zahl von 1000000")
        expectError(broken(function(d) d.Economy.purchases.maxGems = 2e9 end), "maxGems")
        expectError(broken(function(d) d.Economy.purchases.maxGems = "viel" end), "maxGems")
        expectError(broken(function(d) d.Economy.purchases.maxGems = 5000 end), "mehr Gems als Economy.purchases.maxGems")
        -- Belege mindestens so viele wie Protokolleinträge.
        expectError(broken(function(d)
            d.Economy.purchases.receiptCacheSize = 100
            d.Economy.purchases.purchaseLogSize = 101
        end), "receiptCacheSize muss mindestens so groß wie purchaseLogSize sein")
        -- Die Grenzen selbst sind erlaubt.
        T.expect(broken(function(d)
            d.Economy.purchases.receiptCacheSize = 1000
            d.Economy.purchases.purchaseLogSize = 500
            d.Economy.purchases.saveTimeoutSeconds = 120
            d.Economy.purchases.maxGems = 1e9
        end)).toEqual({})
        T.expect(broken(function(d)
            d.Economy.purchases.receiptCacheSize = 50
            d.Economy.purchases.purchaseLogSize = 50
            d.Economy.purchases.saveTimeoutSeconds = 1
            d.Economy.purchases.maxGems = 1_000_000
        end)).toEqual({})
        T.expect(broken(function(d)
            d.Economy.purchases.purchaseLogSize = 1
        end)).toEqual({})
    end)

    T.it("DataCheck meldet doppelte ProductIds, der Platzhalter 0 darf mehrfach vorkommen", function()
        expectError(broken(function(d)
            d.GemPacks.byId.gems_100.productId = 111
            d.GemPacks.byId.gems_550.productId = 111
        end), "productId 111 ist doppelt")
        expectError(broken(function(d)
            d.GemPacks.byId.gems_1200.productId = 222
            d.Products.byId.starter_pack.productId = 222
        end), "productId 222 ist doppelt")
        expectError(broken(function(d)
            d.Products.byId.coin_boost.productId = 333
            d.Products.byId.season_pass.productId = 333
        end), "productId 333 ist doppelt")
        expectError(broken(function(d)
            d.Products.byId.double_coins.productId = 444
            d.Products.byId.auto_dig.productId = 444
        end), "productId 444 ist doppelt")
        -- Gamepasses und Developer Products haben bei Roblox getrennte Nummernkreise.
        T.expect(broken(function(d)
            d.Products.byId.big_tank.productId = 555
            d.GemPacks.byId.gems_100.productId = 555
        end)).toEqual({})
        -- Echte Daten: alle 0 (Platzhalter), keine Meldung.
        for _, pack in GemPacks.list do
            T.expect(pack.productId).toBe(0)
        end
    end)

    T.it("DataCheck meldet eine Produkt-ID, die in GemPacks und in Products steht", function()
        local errors = broken(function(d)
            local copy = table.clone(d.Products.byId.coin_boost)
            copy.id = "gems_550"
            table.insert(d.Products.list, copy)
            d.Products.byId.gems_550 = copy
        end)
        expectError(errors, 'Produkt-ID "gems_550" steht in GemPacks und in Products')
        -- Auch als Gamepass: Handler und Studio-Käufe finden Produkte über diese ID.
        local asPass = broken(function(d)
            d.Products.byId.big_tank.id = "gems_100"
            d.Products.byId.gems_100 = d.Products.byId.big_tank
            d.Products.byId.big_tank = nil
        end)
        expectError(asPass, 'Produkt-ID "gems_100" steht in GemPacks und in Products')
        T.expect(DataCheck.run()).toEqual({})
    end)
end)

T.describe("Kisten und Kisten-Items (4.2)", function()
    local CrateItems = require("../src/shared/Data/CrateItems")

    -- Entfernt alle Items, auf die `match` zutrifft, aus list und byId.
    local function removeItems(data: any, match: (item: any) -> boolean)
        local kept = {}
        for _, item in data.CrateItems.list do
            if match(item) then
                data.CrateItems.byId[item.id] = nil
            else
                table.insert(kept, item)
            end
        end
        data.CrateItems.list = kept
    end

    T.it("echte Daten: Gold- und Event-Kiste haben Pity 15/60 in eigenen Tabellen", function()
        T.expect(DataCheck.run()).toEqual({})
        T.expect(Crates.byId.event.pity).toEqual({ epic = 15, legendary = 60 })
        T.expect(rawequal(Crates.byId.event.pity, Crates.byId.gold.pity)).toBe(false)
        T.expect(Crates.byId.wood.pity).toBeNil()
        T.expect(Crates.byId.iron.pity).toBeNil()
    end)

    T.it("echte Daten: jede Seltenheit mit Quote über 0 hat in jeder Kiste mindestens 3 Items (Soll)", function()
        for _, crate in Crates.list do
            for rarityId, share in crate.odds do
                local count = 0
                for _, item in CrateItems.list do
                    if item.rarity == rarityId and table.find(item.crates, crate.id) ~= nil then
                        count += 1
                    end
                end
                if share > 0 then
                    T.expect(count >= 3).toBe(true)
                else
                    T.expect(count).toBe(0)
                end
            end
        end
    end)

    T.it("DataCheck meldet Quoten, die nicht 10000 ergeben", function()
        local data = freshDataSet()
        data.Crates.Odds.gold.uncommon = 3999
        expectError(DataCheck.run(data), "Quoten ergeben 9999 statt 10000")
        local data2 = freshDataSet()
        data2.Crates.Odds.wood.epic = 101
        expectError(DataCheck.run(data2), "Quoten ergeben 10001 statt 10000")
    end)

    T.it("DataCheck meldet eine Seltenheit mit Quote über 0 ohne Items im Pool", function()
        local data = freshDataSet()
        removeItems(data, function(item)
            return item.rarity == "mythic" and table.find(item.crates, "gold") ~= nil
        end)
        expectError(DataCheck.run(data), 'Kiste "gold" hat keine Items der Seltenheit "mythic"')

        local data2 = freshDataSet()
        removeItems(data2, function(item)
            return item.rarity == "common" and table.find(item.crates, "wood") ~= nil
        end)
        expectError(DataCheck.run(data2), 'Kiste "wood" hat keine Items der Seltenheit "common"')
    end)

    T.it("DataCheck meldet eine falsche Pity der Event-Kiste und eine unerreichbare Garantie", function()
        local data = freshDataSet()
        data.Crates.byId.event.pity = nil
        expectError(DataCheck.run(data), "Crates event: pity muss epic = 15 und legendary = 60 sein")

        local data2 = freshDataSet()
        data2.Crates.byId.event.pity.legendary = 61
        expectError(DataCheck.run(data2), "Crates event: pity")

        local data3 = freshDataSet()
        data3.Crates.byId.iron.pity = { epic = 15, legendary = 60 } -- Eisen hat keine Legendär-Quote
        expectError(DataCheck.run(data3), 'Crates "iron".pity.legendary: keine Seltenheit ab "legendary"')

        local data4 = freshDataSet()
        data4.Crates.byId.wood.pity = { epic = 0, legendary = 2.5 }
        local errors = table.concat(DataCheck.run(data4), "\n")
        T.expect(errors).toContain('Crates "wood".pity.epic muss eine ganze Zahl ab 1 sein')
        T.expect(errors).toContain('Crates "wood".pity.legendary muss eine ganze Zahl ab 1 sein')
    end)

    T.it("DataCheck meldet kaputte Items: doppelte ID, Seltenheit, Art, Kiste, Event-Exklusivität, Wirkung", function()
        local function broken(change: (data: any) -> ()): { string }
            local data = freshDataSet()
            change(data)
            return DataCheck.run(data)
        end
        expectError(
            broken(function(d)
                table.insert(d.CrateItems.list, d.CrateItems.list[1])
            end),
            'CrateItems: id "skin_common_1" ist doppelt'
        )
        expectError(
            broken(function(d)
                d.CrateItems.byId.skin_rare_1.rarity = "selten"
            end),
            'CrateItems "skin_rare_1": unbekannte Seltenheit "selten"'
        )
        expectError(
            broken(function(d)
                d.CrateItems.byId.skin_rare_1.kind = "hat"
            end),
            'CrateItems "skin_rare_1": kind muss'
        )
        expectError(
            broken(function(d)
                d.CrateItems.byId.skin_rare_1.crates = { "wood", "silver" }
            end),
            'CrateItems "skin_rare_1": unbekannte Kiste "silver"'
        )
        expectError(
            broken(function(d)
                d.CrateItems.byId.skin_rare_1.crates = {}
            end),
            'CrateItems "skin_rare_1": crates muss mindestens eine Kiste nennen'
        )
        expectError(
            broken(function(d)
                d.CrateItems.byId.skin_rare_3.crates = { "event", "gold" }
            end),
            'CrateItems "skin_rare_3": Items der Event-Kiste dürfen nur in "event" stehen'
        )
        expectError(
            broken(function(d)
                d.CrateItems.byId.skin_rare_1.effectBp = d.Economy.items.maxEffectBp + 1
            end),
            'CrateItems "skin_rare_1": effectBp muss eine ganze Zahl von 0 bis Economy.items.maxEffectBp'
        )
        expectError(
            broken(function(d)
                d.CrateItems.byId.skin_rare_1.effectBp = 12.5
            end),
            'CrateItems "skin_rare_1": effectBp muss eine ganze Zahl'
        )
        expectError(
            broken(function(d)
                d.CrateItems.byId.skin_legendary_1.crates = { "gold", "wood" }
            end),
            'CrateItems "skin_legendary_1": kann aus Kiste "wood" nie fallen'
        )
        expectError(
            broken(function(d)
                d.CrateItems.byId.skin_rare_1.name = ""
            end),
            'CrateItems "skin_rare_1": name fehlt'
        )
        expectError(
            broken(function(d)
                d.CrateItems = nil
            end),
            "CrateItems: list fehlt"
        )
        T.expect(DataCheck.run()).toEqual({})
    end)
end)

T.describe("Kisten-Items mit Wirkung und Aussehen (4.3)", function()
    local function broken(change: (data: any) -> ()): { string }
        local data = freshDataSet()
        change(data)
        return DataCheck.run(data)
    end

    T.it("jedes Item hat einen Wert in den Grenzen und ein passendes Aussehen", function()
        local data = freshDataSet()
        T.expect(DataCheck.run(data)).toEqual({})
        T.expect(#data.ItemLooks.list).toBe(#data.CrateItems.list)
        for _, item in data.CrateItems.list do
            T.expect(item.effectBp > 0).toBe(true)
            T.expect(data.ItemLooks.byId[item.id].kind).toBe(item.kind)
        end
    end)

    T.it("DataCheck meldet kaputte Sterne-Regeln", function()
        expectError(broken(function(d) d.Economy.items = nil end), "Economy.items: Tabelle fehlt")
        expectError(broken(function(d) d.Economy.items.maxStars = 1 end), "Economy.items.maxStars")
        expectError(broken(function(d) d.Economy.items.starBonusBp = -1 end), "Economy.items.starBonusBp")
        expectError(broken(function(d) d.Economy.items.maxTotalBonusBp = 0 end), "Economy.items.maxTotalBonusBp")
        expectError(broken(function(d) d.Economy.items.maxTotalBonusBp = 9000 end), "überschreiten maxTotalBonusBp")
        expectError(broken(function(d) d.Economy.items.maxEffectBp = 5000 end), "überschreiten maxTotalBonusBp")
        expectError(broken(function(d) d.Economy.items.copiesToMerge = { 1, 2, 3 } end), "genau maxStars - 1 Einträge")
        expectError(broken(function(d) d.Economy.items.copiesToMerge = { 1, 0, 3, 4 } end), "copiesToMerge[2]")
    end)

    T.it("DataCheck meldet ein fehlendes oder kaputtes Aussehen", function()
        expectError(
            broken(function(d)
                table.remove(d.ItemLooks.list, 1)
                d.ItemLooks.byId.skin_common_1 = nil
            end),
            'ItemLooks: Item "skin_common_1" hat kein Aussehen'
        )
        expectError(
            broken(function(d) d.ItemLooks.byId.skin_rare_1.kind = "companion" end),
            'ItemLooks "skin_rare_1": kind "companion" passt nicht zum Item ("skin")'
        )
        expectError(
            broken(function(d) d.ItemLooks.byId.skin_rare_1.colorHex = "rot" end),
            'ItemLooks "skin_rare_1": colorHex und accentHex'
        )
        expectError(
            broken(function(d) d.ItemLooks.byId.companion_rare_1.size = 5 end),
            'ItemLooks "companion_rare_1": size muss zwischen'
        )
        expectError(
            broken(function(d) d.ItemLooks.byId.companion_rare_1.shape = "Dreieck" end),
            'ItemLooks "companion_rare_1": shape'
        )
        expectError(
            broken(function(d)
                table.insert(d.ItemLooks.list, { id = "geist", kind = "skin", colorHex = "#FFFFFF", accentHex = "#000000", material = "Fabric" })
            end),
            'ItemLooks "geist": kein Item mit dieser ID in CrateItems'
        )
    end)
end)

T.describe("Gamepasses und Münz-Boost (4.4)", function()
    local function broken(change: (data: any) -> ()): { string }
        local data = freshDataSet()
        change(data)
        return DataCheck.run(data)
    end

    T.it("jeder Gamepass hat eine bekannte Wirkung, jede Wirkung genau einmal, Faktoren größer als 1", function()
        local perks: { [string]: number } = {}
        for _, product in Products.list do
            if product.kind == "gamepass" then
                T.expect(type(product.perk)).toBe("string")
                local perk = product.perk :: string
                perks[perk] = (perks[perk] or 0) + 1
            else
                T.expect(product.perk).toBeNil()
            end
        end
        T.expect(perks).toEqual({ doubleCoins = 1, autoDig = 1, bigTank = 1 })
        T.expect(Economy.doubleCoinsMultiplier > 1).toBe(true)
        T.expect(Economy.bigTankMultiplier > 1).toBe(true)
        T.expect(Economy.coinBoost.multiplier > 1).toBe(true)
        T.expect(Products.byId.coin_boost.kind).toBe("developerProduct")
        T.expect(Products.byId.coin_boost.consumable).toBe(true)
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("DataCheck meldet Gamepasses ohne oder mit unbekannter Wirkung und doppelte Wirkungen", function()
        expectError(broken(function(d) d.Products.byId.big_tank.perk = nil end), 'Products "big_tank": Gamepass ohne bekannte Wirkung')
        expectError(broken(function(d) d.Products.byId.big_tank.perk = "tripleTank" end), 'perk "tripleTank"')
        expectError(broken(function(d) d.Products.byId.big_tank.perk = "doubleCoins" end), 'Wirkung "doubleCoins" muss genau einem Gamepass gehören (gefunden: 2)')
        expectError(broken(function(d) d.Products.byId.big_tank.perk = "doubleCoins" end), 'Wirkung "bigTank" muss genau einem Gamepass gehören (gefunden: 0)')
        expectError(broken(function(d) d.Products.byId.season_pass.perk = "autoDig" end), 'Products "season_pass": perk gibt es nur bei Gamepasses')
    end)

    T.it("DataCheck meldet Faktoren, die nicht endlich und größer als 1 sind", function()
        for _, bad in { 1, 0.5, 0, -2, 0 / 0, math.huge } do
            expectError(broken(function(d) d.Economy.doubleCoinsMultiplier = bad end), "Economy.doubleCoinsMultiplier muss endlich und größer als 1 sein")
            expectError(broken(function(d) d.Economy.bigTankMultiplier = bad end), "Economy.bigTankMultiplier muss endlich und größer als 1 sein")
            expectError(broken(function(d) d.Economy.coinBoost.multiplier = bad end), "Economy.coinBoost.multiplier muss endlich und größer als 1 sein")
        end
        expectError(broken(function(d) d.Economy.doubleCoinsMultiplier = nil end), "doubleCoinsMultiplier")
        expectError(broken(function(d) d.Economy.coinBoost = nil end), "Economy.coinBoost")
        expectError(broken(function(d) d.Economy.coinBoost.durationSeconds = 0 end), "Economy.coinBoost")
    end)

    T.it("DataCheck verlangt den Münz-Boost als Developer Product und Verbrauchsprodukt", function()
        expectError(broken(function(d) d.Products.byId.coin_boost.consumable = false end), 'Products "coin_boost": muss ein Developer Product und ein Verbrauchsprodukt sein')
        expectError(broken(function(d) d.Products.byId.coin_boost.kind = "gamepass"; d.Products.byId.coin_boost.perk = nil end), 'Products "coin_boost": muss ein Developer Product')
        expectError(broken(function(d)
            d.Products.byId.coin_boost = nil
            for index, product in d.Products.list do
                if product.id == "coin_boost" then
                    table.remove(d.Products.list, index)
                    break
                end
            end
        end), 'Products: "coin_boost" (Münz-Boost) fehlt')
    end)
end)

T.describe("Angebote (4.5)", function()
    local function broken(change: (data: any) -> ()): { string }
        local data = freshDataSet()
        change(data)
        return DataCheck.run(data)
    end

    T.it("die echten Angebote bestehen die Prüfung (Starterpaket: starter_pack, feste Items, 24 h, 300 Gems)", function()
        T.expect(#OffersData.list >= 1).toBe(true)
        T.expect(OffersData.byId.starter.productId).toBe("starter_pack")
        T.expect(Products.byId.starter_pack.kind).toBe("developerProduct")
        T.expect(Products.byId.starter_pack.oneTime).toBe(true)
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("Angebote verweisen auf bekannte Developer Products mit Einmalkauf, je Angebot ein eigenes", function()
        expectError(broken(function(d) d.Offers.byId.starter.productId = "gibt_es_nicht" end), 'productId "gibt_es_nicht" steht nicht in Products')
        expectError(broken(function(d) d.Offers.byId.starter.productId = "double_coins" end), 'Produkt "double_coins" muss ein Developer Product mit oneTime = true sein')
        expectError(broken(function(d) d.Offers.byId.starter.productId = "coin_boost" end), 'Produkt "coin_boost" muss ein Developer Product mit oneTime = true sein')
        expectError(broken(function(d) d.Products.byId.starter_pack.oneTime = false end), "oneTime = true")
        expectError(broken(function(d) d.Offers.byId.starter.productId = "gems_550" end), "steht nicht in Products")
        expectError(broken(function(d)
            local copy = table.clone(d.Offers.byId.starter)
            copy.id = "zweites"
            table.insert(d.Offers.list, copy)
            d.Offers.byId.zweites = copy
        end), 'gehört schon zum Angebot "starter"')
    end)

    T.it("Items sind feste, bekannte Items: keine Kiste, kein Zufall, je Art höchstens eines, lückenlose Liste", function()
        expectError(broken(function(d) d.Offers.byId.starter.items = { "gold" } end), '"gold" ist eine Kiste (Zufall)')
        expectError(broken(function(d) d.Offers.byId.starter.items = { "gibt_es_nicht" } end), 'Item "gibt_es_nicht" steht nicht in CrateItems')
        expectError(broken(function(d) d.Offers.byId.starter.items = { "toolVariant_rare_1", "toolVariant_common_1" } end), "höchstens ein Item je Art")
        expectError(broken(function(d) d.Offers.byId.starter.items = { "skin_rare_1", "skin_rare_1" } end), "höchstens ein Item je Art")
        expectError(broken(function(d) d.Offers.byId.starter.items = { [1] = "skin_rare_1", [3] = "companion_rare_1" } end), "lückenlose Liste")
        expectError(broken(function(d) d.Offers.byId.starter.items = "skin_rare_1" end), "items muss eine Liste sein")
        expectError(broken(function(d) d.Offers.byId.starter.crateId = "gold" end), 'unbekanntes Feld "crateId"')
        expectError(broken(function(d) d.Offers.byId.starter.randomItems = { "skin_rare_1" } end), 'unbekanntes Feld "randomItems"')
        expectError(broken(function(d)
            d.Offers.byId.starter.items = {}
            d.Offers.byId.starter.gems = 0
        end), "Angebot ohne Inhalt")
    end)

    T.it("Fenster, Gems, Seltenheit, Auslöser, priority und IDs sind gültig", function()
        for _, bad in { 0, -1, 0 / 0, math.huge, "24" } do
            expectError(broken(function(d) d.Offers.byId.starter.windowHours = bad end), "windowHours muss endlich und größer als 0 sein")
        end
        for _, bad in { -1, 1.5, 0 / 0, math.huge, "300", Economy.purchases.maxGems + 1 } do
            expectError(broken(function(d) d.Offers.byId.starter.gems = bad end), "gems muss eine ganze Zahl von 0 bis Economy.purchases.maxGems sein")
        end
        expectError(broken(function(d) d.Offers.byId.starter.minRarityId = "selten" end), 'minRarityId "selten" steht nicht in Rarities')
        expectError(broken(function(d) d.Offers.byId.starter.trigger = "login" end), 'unbekannter Auslöser "login"')
        for _, bad in { 0 / 0, math.huge, "1" } do
            expectError(broken(function(d) d.Offers.byId.starter.priority = bad end), "priority muss eine endliche Zahl sein")
        end
        expectError(broken(function(d)
            table.insert(d.Offers.list, table.clone(d.Offers.byId.starter))
        end), 'Offers: id "starter" ist doppelt')
        expectError(broken(function(d) d.Offers = nil end), "Offers: list fehlt")
        -- gültige Ränder
        T.expect(broken(function(d) d.Offers.byId.starter.gems = 0 end)).toEqual({})
        T.expect(broken(function(d) d.Offers.byId.starter.windowHours = 0.5 end)).toEqual({})
    end)
end)

T.describe("Daily Reward und Glücks-Boost (5.1)", function()
    local function broken(change: (data: any) -> ()): { string }
        local data = freshDataSet()
        change(data)
        return DataCheck.run(data)
    end

    T.it("die echten Werte: Plan aus phase0_startwerte, Start nach der Schaufel, Glück x2", function()
        local daily = Economy.daily
        T.expect(daily.days).toEqual({
            { day = 1, kind = "coinBoost", seconds = 600 },
            { day = 2, kind = "gems", amount = 5 },
            { day = 3, kind = "coinBoost", seconds = 900 },
            { day = 4, kind = "gems", amount = 10 },
            { day = 5, kind = "luck", seconds = 900 },
            { day = 6, kind = "gems", amount = 20 },
        })
        T.expect(daily.day7).toEqual({ day = 7, kind = "crate", crateId = "iron" })
        T.expect(Economy.luckBoost).toEqual({ multiplier = 2 })
        -- Der Startknoten ist der Knoten, der die Schaufel freischaltet (aus den Daten, keine feste Zahl).
        T.expect(UpgradeTree.byId[daily.startNodeId].effect).toEqual({ kind = "setTool", toolId = "shovel" })
        T.expect(Tools.byId.shovel.nodeId).toBe(daily.startNodeId)
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("Tage: unbekannte Art, falscher Tag, fremde Felder, ungültige Menge oder Dauer", function()
        expectError(broken(function(d) d.Economy.daily.days[2].kind = "boost" end), "unbekannte Art")
        expectError(broken(function(d) d.Economy.daily.days[3].day = 4 end), "day muss 3 sein")
        expectError(broken(function(d) d.Economy.daily.days[1].durationSeconds = 600 end), 'Feld "durationSeconds" gehört nicht zur Art "coinBoost"')
        expectError(broken(function(d) d.Economy.daily.days[2].crateId = "iron" end), 'Feld "crateId" gehört nicht zur Art "gems"')
        expectError(broken(function(d) d.Economy.daily.days[2].amount = 2.5 end), "amount muss eine ganze Zahl")
        expectError(broken(function(d) d.Economy.daily.days[2].amount = 0 end), "amount muss eine ganze Zahl")
        expectError(broken(function(d) d.Economy.daily.days[2].amount = d.Economy.purchases.maxGems + 1 end), "höchstens maxGems")
        expectError(broken(function(d) d.Economy.daily.days[5].seconds = 0 / 0 end), "seconds muss eine ganze Zahl")
        expectError(broken(function(d) d.Economy.daily.days[5].seconds = 1.5 end), "seconds muss eine ganze Zahl")
        expectError(broken(function(d) d.Economy.daily.days = {} end), "Tag 1 bis 6")
    end)

    T.it("Tag 7: Eisenkiste aus Crates, keine fremden Felder", function()
        expectError(broken(function(d) d.Economy.daily.day7.crateId = "gold" end), "Tag 7 muss die Eisenkiste sein")
        expectError(broken(function(d) d.Economy.daily.day7.kind = "gems" end), "Tag 7 muss die Eisenkiste sein")
        expectError(broken(function(d) d.Economy.daily.day7 = nil end), "Tag 7 muss die Eisenkiste sein")
        expectError(broken(function(d) d.Economy.daily.day7.amount = 1 end), 'Feld "amount" gehört nicht zu Tag 7')
        expectError(broken(function(d) d.Crates.byId.iron = nil end), 'Kiste "iron" fehlt in Crates')
        expectError(broken(function(d) d.Crates.byId.iron.eventOnly = true end), "oder ist eine Event-Kiste")
    end)

    T.it("Startknoten: steht in UpgradeTree und wird gekauft, nicht vergeben", function()
        expectError(broken(function(d) d.Economy.daily.startNodeId = "schaufel" end), 'startNodeId "schaufel" steht nicht in UpgradeTree')
        expectError(broken(function(d) d.Economy.daily.startNodeId = nil end), "startNodeId")
        expectError(broken(function(d) d.Economy.daily.startNodeId = 2 end), "startNodeId")
        expectError(broken(function(d) d.Economy.daily.startNodeId = "sandstorm_1" end), 'startNodeId "sandstorm_1" wird vergeben, nicht gekauft')
        T.expect(broken(function(d) d.Economy.daily.startNodeId = "collect_tool_3" end)).toEqual({})
    end)

    T.it("Glücks-Boost: Faktor endlich und größer als 1", function()
        for _, bad in { 1, 0.5, 0 / 0, math.huge, "2" } do
            expectError(broken(function(d) d.Economy.luckBoost.multiplier = bad end), "Economy.luckBoost.multiplier")
        end
        expectError(broken(function(d) d.Economy.luckBoost = nil end), "Economy.luckBoost.multiplier")
        T.expect(broken(function(d) d.Economy.luckBoost.multiplier = 1.5 end)).toEqual({})
    end)
end)

T.describe("Direktkauf und Ersatzgegenstand (4.6)", function()
    local function broken(change: (data: any) -> ()): { string }
        local data = freshDataSet()
        change(data)
        return DataCheck.run(data)
    end

    T.it("die echten Werte bestehen die Prüfung", function()
        T.expect(Economy.directShop).toEqual({ roundSignificantDigits = 2, monotoneFloor = true, crates = { "iron", "gold" } })
        T.expect(Economy.daily.day7FallbackItemId).toBe("toolVariant_uncommon_1")
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("Ersatzgegenstand Tag 7: festes Item aus CrateItems, kein Event-Item", function()
        expectError(broken(function(d) d.Economy.daily.day7FallbackItemId = "daily_fallback_item" end), 'day7FallbackItemId "daily_fallback_item" steht nicht in CrateItems')
        expectError(broken(function(d) d.Economy.daily.day7FallbackItemId = "gold" end), "steht nicht in CrateItems") -- eine Kiste ist kein festes Item
        expectError(broken(function(d) d.Economy.daily.day7FallbackItemId = nil end), "steht nicht in CrateItems")
        expectError(broken(function(d) d.Economy.daily.day7FallbackItemId = 5 end), "steht nicht in CrateItems")
        expectError(broken(function(d) d.Economy.daily.day7FallbackItemId = "skin_mythic_2" end), 'day7FallbackItemId "skin_mythic_2" ist ein Event-Item')
        T.expect(broken(function(d) d.Economy.daily.day7FallbackItemId = "skin_common_1" end)).toEqual({})
    end)

    T.it("Kisten der Preisrechnung: bekannt, Gems, keine Event-Kiste, keine doppelt, nicht leer", function()
        expectError(broken(function(d) d.Economy.directShop.crates = { "iron", "diamant" } end), 'unbekannte Kiste "diamant"')
        expectError(broken(function(d) d.Economy.directShop.crates = { "wood", "gold" } end), 'Kiste "wood" muss in Gems kosten')
        expectError(broken(function(d) d.Economy.directShop.crates = { "gold", "event" } end), 'Kiste "event" ist eine Event-Kiste')
        expectError(broken(function(d) d.Economy.directShop.crates = { "gold", "gold" } end), 'Kiste "gold" steht doppelt')
        expectError(broken(function(d) d.Economy.directShop.crates = {} end), "muss mindestens eine Kiste nennen")
        expectError(broken(function(d) d.Economy.directShop.crates = "gold" end), "muss mindestens eine Kiste nennen")
        expectError(broken(function(d) d.Economy.directShop = nil end), "Economy.directShop: Tabelle fehlt")
        T.expect(broken(function(d) d.Economy.directShop.crates = { "gold" } end)).toEqual({})
    end)

    T.it("Stellen ganze Zahl von 1 bis 4, monotoneFloor Boolean", function()
        for _, bad in { 0, 5, 2.5, 0 / 0, "2" } :: { any } do
            expectError(broken(function(d) d.Economy.directShop.roundSignificantDigits = bad end), "roundSignificantDigits muss eine ganze Zahl von 1 bis 4 sein")
        end
        for _, bad in { "ja", 1, nil } :: { any } do
            expectError(broken(function(d) d.Economy.directShop.monotoneFloor = bad end), "monotoneFloor muss true oder false sein")
        end
        T.expect(broken(function(d) d.Economy.directShop.roundSignificantDigits = 4 end)).toEqual({})
        T.expect(broken(function(d) d.Economy.directShop.monotoneFloor = false end)).toEqual({})
    end)

    T.it("ein Preis über maxGems wird gemeldet", function()
        expectError(broken(function(d) d.Crates.byId.gold.price = 40_000 end), 'Direktkauf "skin_mythic_1": Preis')
    end)
end)

T.finish()
