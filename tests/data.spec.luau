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
        local validKinds: { [string]: boolean } =
            { coins = true, gems = true, boost = true, crate = true, fixedItem = true }
        for _, reward in Economy.daily.days do
            T.expect(validKinds[reward.kind]).toBe(true)
            if reward.kind == "boost" then
                T.expect(type(reward.boostId) == "string" and reward.boostId ~= "").toBe(true)
                T.expect((reward.durationSeconds or 0) > 0).toBe(true)
            else
                T.expect(reward.amount > 0).toBe(true)
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
        expectError(broken(function(d) d.FindOdds.findChancePerSecond = 0 end), "findChancePerSecond")
        expectError(broken(function(d) d.FindOdds.findBaseValue = 0 end), "findBaseValue")
        expectError(broken(function(d) d.FindOdds.zoneFindChanceFactor.ruins = nil end), "ruins")
        expectError(broken(function(d) d.Economy.daily.days[2].kind = "geld" end), "unbekannte Art")
        expectError(broken(function(d) d.Economy.daily.days[1].boostId = nil end), "boostId")
        expectError(broken(function(d) d.Economy.daily.days[1].durationSeconds = 0 end), "durationSeconds")
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

T.finish()
