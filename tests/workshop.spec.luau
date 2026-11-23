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
end)
T.finish()
