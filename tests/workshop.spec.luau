--!strict
-- Test the actual Studio export, including Rojo's compiled JSON ModuleScripts.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local T = require("./lib/expect")
local base = require("../src/shared/Data/UpgradeTree")
local path = "assets/ui/skill_tree/werkstatt/ELG_Werkstatt.rbxm"
local root = roblox.deserializeModel(fs.readFile(path))[1]
local main = root.Workshop
local function readData(module: any): any
    return luau.load(module.Source)()
end
local catalog = luau.load(main.Catalog.Source, {
    environment = { script = main.Catalog, require = readData },
})().build(base.list)
local sprites = readData(main.TierArt)
local navigation = readData(main.Navigation)
local search = readData(main.Search)

T.describe("Werkstatt-Export", function()
    T.it("sechs Geräte mit je 48 Knoten und 75 Knoten für den Lauf", function()
        local total = 0
        for _, page in catalog.tabs do
            total += #page.nodes
            if page.row ~= nil then
                T.expect(#page.nodes).toBe(48)
            end
        end
        T.expect(#catalog.tabs).toBe(11)
        T.expect(total).toBe(363)
        for _, node in base.list do
            local drawn = catalog.byId[node.id]
            T.expect(drawn.live).toBe(true)
            T.expect(drawn.cost).toBe(node.cost)
            T.expect(drawn.requires).toEqual(node.requires)
        end
    end)
    T.it("alle Voraussetzungen existieren und alle Knoten sind erreichbar", function()
        local owned: { [string]: boolean } = { start = true }
        local function ready(node)
            for _, id in node.requires do
                assert(catalog.byId[id], id)
                if not owned[id] then
                    return false
                end
            end
            if #node.requiresAny == 0 then
                return true
            end
            for _, id in node.requiresAny do
                assert(catalog.byId[id], id)
                if owned[id] then
                    return true
                end
            end
            return false
        end
        for _ = 1, 363 do
            local added = 0
            for id, node in catalog.byId do
                if not owned[id] and ready(node) then
                    owned[id] = true
                    added += 1
                end
            end
            if added == 0 then
                break
            end
        end
        for id in catalog.byId do
            assert(owned[id], id)
        end
        T.expect(#catalog.byId.tiefstich_master.requiresAny).toBe(4)
        T.expect(#catalog.byId.shovel_p3_4.requires).toBe(2)
    end)
    T.it("jede Ausbaustufe hat ein eigenes Motiv innerhalb ihrer Reihe", function()
        local count = 0
        for id, binding in sprites do
            assert(catalog.byId[id], id)
            local max = if binding[1] == "gear" then 144 else 75
            assert(binding[2] >= 0 and binding[2] < max, id)
            count += 1
        end
        T.expect(count).toBe(339)
        for _, ids in catalog.families do
            local used = {}
            for _, id in ids do
                local binding = assert(sprites[id], id)
                local key = binding[1] .. tostring(binding[2])
                assert(not used[key], "Repeated sprite: " .. id)
                used[key] = true
            end
        end
    end)
    T.it("zeigt Pflichtwege und Alternativen bis zum nächsten gelernten Upgrade", function()
        local owned = { collect_tool_2 = true }
        local function learned(id)
            return owned[id] == true
        end
        local nodes, paths = navigation.route(catalog.byId, "tiefstich_master", learned)
        T.expect(nodes.tiefstich_master).toBe(2)
        T.expect(nodes.tiefstich_a).toBe(1)
        T.expect(nodes.tiefstich_b).toBe(1)
        T.expect(nodes.collect_tool_2).toBe(1)
        T.expect(paths.collect_tool_2).toBeNil()
        T.expect(nodes.shovel_p3_1).toBeNil()
        owned.tiefstich_a_m1_2 = true
        nodes, paths = navigation.route(catalog.byId, "tiefstich_master", learned)
        T.expect(paths.tiefstich_master.tiefstich_a_m1_2).toBe(2)
        T.expect(nodes.tiefstich_b).toBeNil()
        T.expect(nodes.tiefstich_a_m1_1).toBeNil()
        nodes = navigation.route(catalog.byId, "shovel_p3_4", learned)
        T.expect(nodes.shovel_p3_2).toBe(2)
        T.expect(nodes.shovel_p3_3).toBe(2)
    end)
    T.it("findet exakte Stufen, gemischte Gerätenamen und Umlaute in allen Ästen", function()
        local index = search.build(catalog.tabs, { mastery = "Meisterschaft" })
        T.expect(#index).toBe(363)
        local matches = search.find(index, "  TIEFENKANTE II  ", 30)
        T.expect(matches[1]).toBe("tiefstich_m1_2")
        matches = search.find(index, "schaufel meisterschaft", 30)
        T.expect(matches).toEqual({ "tiefstich_master" })
        matches = search.find(index, "FOERDERBAND RÜCKLAUF", 30)
        T.expect(matches[1]).toBe("doppeltakt_b")
        local limited, total = search.find(index, "Tank", 3)
        T.expect(#limited).toBe(3)
        assert(total >= 20)
        matches = search.find(index, "unbekannteswerkzeug", 30)
        T.expect(#matches).toBe(0)
    end)
end)
T.finish()
