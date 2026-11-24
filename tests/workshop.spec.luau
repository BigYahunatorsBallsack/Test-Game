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
local planner = readData(main.StudyPlan)
local trial = readData(main.Trial)
local deviceStats = readData(main.DeviceStats)
local art = luau.load(main.Art.Source, {
    environment = {
        script = main.Art,
        require = readData,
        Vector2 = roblox.Vector2,
        Color3 = roblox.Color3,
    },
})()
local mapView = luau.load(main.MapView.Source, {
    environment = { Vector2 = roblox.Vector2 },
})()

T.describe("Werkstatt-Export", function()
    T.it("sechs Geräte mit je 48 Knoten und 75 Knoten für den Lauf", function()
        local total = 0
        for _, page in catalog.tabs do
            total += #page.nodes
            if page.row ~= nil then
                T.expect(#page.nodes).toBe(48)
                T.expect(#page.variants).toBe(2)
                local first = catalog.byId[page.variants[1]]
                local second = catalog.byId[page.variants[2]]
                T.expect(first.kind).toBe("variant")
                T.expect(second.kind).toBe("variant")
                T.expect(first.page).toBe(page.id)
                T.expect(second.page).toBe(page.id)
                T.expect(first.sprite % 4 + 1).toBe(2)
                T.expect(second.sprite % 4 + 1).toBe(3)
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
    T.it("meldet nur neu erfüllte Voraussetzungen, auch bei verzweigten Pfaden", function()
        local shovel = catalog.byTab.shovel.nodes
        local before = { collect_tool_2 = true }
        local after = { collect_tool_2 = true, tiefstich = true }
        T.expect(navigation.newlyReachable(shovel, before, after)).toEqual({
            "tiefstich_upgrade",
            "tiefstich_m2_1",
        })
        local oneBranch = { collect_tool_2 = true, shovel_p3_1 = true, shovel_p3_2 = true }
        local bothBranches = table.clone(oneBranch)
        bothBranches.shovel_p3_3 = true
        T.expect(navigation.newlyReachable(shovel, oneBranch, bothBranches))
            .toEqual({ "shovel_p3_4" })
        local firstVariant = { tiefstich_a_m1_1 = true }
        local completed = { tiefstich_a_m1_1 = true, tiefstich_a_m1_2 = true }
        T.expect(navigation.newlyReachable(shovel, firstVariant, completed))
            .toEqual({ "tiefstich_master" })
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
    T.it("berechnet einen günstigen Lernweg aus dem tatsächlichen Besitz", function()
        local owned = { collect_tool_2 = true }
        local plan = planner.find(catalog.byId, "tiefstich_master", owned)
        local steps, total = {}, 0
        for _, id in plan.steps do
            assert(not steps[id] and not owned[id], id)
            local n = catalog.byId[id]
            for _, parent in n.requires do
                assert(steps[parent] or owned[parent], parent)
            end
            steps[id] = true
            total += n.cost
        end
        T.expect(plan.steps[#plan.steps]).toBe("tiefstich_master")
        T.expect(plan.cost).toBe(total)
        local ready = planner.find(catalog.byId, "tiefstich_master", { tiefstich_b_m2_2 = true })
        T.expect(ready.steps).toEqual({ "tiefstich_master" })
        T.expect(ready.cost).toBe(catalog.byId.tiefstich_master.cost)
        local complete = planner.find(catalog.byId, "tiefstich_master", { tiefstich_master = true })
        T.expect(#complete.steps).toBe(0)
    end)
    T.it("vergleicht komplette Alternativen und zählt geteilte Voraussetzungen einmal", function()
        local function node(id, cost, requires, requiresAny)
            return { id = id, cost = cost, requires = requires, requiresAny = requiresAny or {} }
        end
        local nodes = {
            goal = node("goal", 10, { "alternative", "festerZweig" }),
            festerZweig = node("festerZweig", 5, { "gemeinsam" }),
            alternative = node("alternative", 0, {}, { "eins", "zwei" }),
            eins = node("eins", 1, { "gemeinsam" }),
            zwei = node("zwei", 3, {}),
            gemeinsam = node("gemeinsam", 20, {}),
        }
        local plan = planner.find(nodes, "goal", {})
        T.expect(plan.cost).toBe(36)
        T.expect(plan.steps).toEqual({ "gemeinsam", "eins", "alternative", "festerZweig", "goal" })
    end)
    T.it("hält einen Kartenpunkt beim Zoom und beim Verschieben des Zoomankers fest", function()
        local v = roblox.Vector2.new
        local viewport = v(400, 460)
        local board = v(1050, 1300)
        local originalPan = v(220, 400)
        local pointer = v(140, 220)
        local world = mapView.worldAt(pointer, originalPan, mapView.offset(board, viewport), 1)
        local newPointer = v(150, 170)
        local zoomed = board * 1.2
        local pan = mapView.panAt(world, newPointer, zoomed, viewport, 1.2)
        local newWorld = mapView.worldAt(newPointer, pan, mapView.offset(zoomed, viewport), 1.2)
        assert((newWorld - world).Magnitude < 0.01)
    end)
    T.it("zentriert eine schmalere Karte und hält den Ausschnitt innerhalb des Baums", function()
        local v = roblox.Vector2.new
        local viewport = v(1200, 550)
        local board = v(1050, 1300)
        local offset = mapView.offset(board, viewport)
        T.expect(offset.X).toBe(75)
        local view = mapView.panAt(v(525, 700), viewport / 2, board, viewport, 1)
        T.expect(view.X).toBe(0)
        T.expect(view.Y).toBe(425)
        local edge = mapView.panAt(v(1050, 1300), viewport / 2, board, viewport, 1)
        T.expect(edge.Y).toBe(750)
    end)
    T.it("navigiert entlang passender Knoten und überspringt keine näheren Stufen", function()
        local origin = { id = "mitte", x = 100, y = 100 }
        local nodes = {
            origin,
            { id = "links", x = 50, y = 100 },
            { id = "beinaheUnten", x = 145, y = 145 },
            { id = "naechsteStufe", x = 100, y = 180 },
            { id = "spaeteStufe", x = 100, y = 310 },
        }
        local v = roblox.Vector2.new
        T.expect(mapView.neighbor(nodes, origin, v(-1, 0))).toBe("links")
        T.expect(mapView.neighbor(nodes, origin, v(0, 1))).toBe("naechsteStufe")
        T.expect(mapView.neighbor(nodes, origin, v(0, -1))).toBeNil()
    end)
    T.it("startet eigenständige Probeläufe mit getrenntem Besitz und Guthaben", function()
        local owned = { collect_tool_2 = true }
        local gates = { "start", "collect_tool_2", "collect_tool_3" }
        local hand = trial.start("hand", owned, 72, gates)
        T.expect(hand.owned).toEqual({})
        T.expect(hand.coins).toBe(100)
        local copied = trial.start("snapshot", owned, 72, gates)
        T.expect(copied.owned).toEqual(owned)
        T.expect(copied.coins).toBe(72)
        copied.owned.collect_tool_2 = false
        copied.variants.shovel = "tiefstich_a"
        T.expect(owned.collect_tool_2).toBe(true)
        local all = trial.start("all", owned, 72, gates)
        T.expect(all.owned)
            .toEqual({ collect_tool_2 = true, collect_tool_3 = true, sandstorm_1 = true })
        T.expect(all.coins).toBe(1000000000)
        T.expect(all.variants).toEqual({})
    end)
    T.it("ordnet jedem Gerät vier eigene Ego-Szenen zu", function()
        local portraits = {}
        for row = 0, 5 do
            for variant = 1, 4 do
                local label: any = {}
                art.scene(label, row, variant)
                local rect = label.ImageRectOffset
                local size = label.ImageRectSize
                local key = label.Image .. tostring(rect)
                assert(not portraits[key], "Ego-Szene doppelt verwendet")
                assert(rect.X + size.X <= 1008 and rect.Y + size.Y <= 1008)
                portraits[key] = true
                if variant == 4 then
                    T.expect(label.Image).toBe(art.masteryScenes)
                end
            end
        end
    end)
    T.it("addiert Werte je Gerät und Fähigkeit, ohne Bonusgruppen zu vermischen", function()
        local ids = {
            tiefstich = true,
            tiefstich_m2_1 = true,
            tiefstich_m2_2 = true,
            shovel_crown = true,
            shovel_p1_1 = true,
            shovel_p1_3 = true,
            tiefstich_a = true,
            tiefstich_a_m1_1 = true,
            tiefstich_b = true,
            tiefstich_b_m1_1 = true,
        }
        local groups, byTarget = deviceStats.collect(catalog.byTab.shovel.nodes, ids)
        T.expect(#groups).toBe(5)
        T.expect(deviceStats.format(byTarget.tiefstich.cooldown, "s")).toBe("7,2 s")
        T.expect(deviceStats.format(groups[1].values[1].total, "%", true)).toBe("+8 %")
        T.expect(#byTarget.tiefstich_a.values).toBe(1)
        T.expect(byTarget.tiefstich_a.values[1].stat).toBe("Schnitttiefe")
        T.expect(#byTarget.tiefstich_b.values).toBe(1)
        T.expect(byTarget.tiefstich_b.values[1].stat).toBe("Rinnenlänge")
        local before, after = deviceStats.projection(catalog.byId.tiefstich_m2_3, byTarget)
        T.expect(deviceStats.format(before, "s")).toBe("7,2 s")
        T.expect(deviceStats.format(after, "s")).toBe("6,8 s")
    end)
end)
T.finish()
