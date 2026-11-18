--!strict
-- Paket 2.2: Was der Spieler im Baum sieht (Zustände, Linien, Zähler, Fokus, Karte).

local T = require("./lib/expect")
local TreeView = require("../src/shared/Logic/TreeView")
local TreeLayout = require("../src/shared/Logic/TreeLayout")
local TreePurchase = require("../src/shared/Logic/TreePurchase")
local Profile = require("../src/shared/Logic/Profile")
local BigNum = require("../src/shared/Logic/BigNum")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")

local NOW = 1_700_000_000
local layout = TreeLayout.compute()

local function profileWith(coins: number, owned: { string }?): any
    local profile = Profile.default(NOW)
    profile.coins = BigNum.serialize(BigNum.new(coins))
    for _, id in owned or {} do
        profile.nodes[id] = true
    end
    return profile
end

local function lineStyle(view: TreeView.View, from: string, to: string): string?
    for _, line in view.lines do
        if line.from == from and line.to == to then
            return line.style
        end
    end
    return nil
end

T.describe("Zustände", function()
    T.it("neuer Spieler mit 0 Münzen: Einstiegsknoten zu teuer, Nachfolger Silhouetten, Rest verborgen", function()
        local view = TreeView.build(profileWith(0), layout)
        for _, id in { "collect_rate_1", "tank_1", "collect_tool_2" } do
            T.expect(view.nodes[id]).toBe("expensive")
        end
        for _, id in { "tank_2", "luck_1", "collect_rate_2", "sell_1", "collect_tool_3" } do
            T.expect(view.nodes[id]).toBe("silhouette")
        end
        for _, id in { "tank_3", "collect_rate_3", "luck_2", "tank_4", "collect_tool_6" } do
            T.expect(view.nodes[id]).toBe("hidden")
        end
        T.expect(view.counter).toBe(0)
    end)

    T.it("der Sandsturm-Knoten bleibt verborgen, bis er vergeben ist", function()
        T.expect(TreeView.build(profileWith(1e30), layout).nodes.sandstorm_1).toBe("hidden")
        T.expect(TreeView.build(profileWith(0, { "sandstorm_1" }), layout).nodes.sandstorm_1).toBe("owned")
    end)

    T.it("mit genug Münzen wird ein Knoten kaufbar, auch bei sehr großen Werten", function()
        T.expect(TreeView.build(profileWith(15), layout).nodes.collect_rate_1).toBe("affordable")
        T.expect(TreeView.build(profileWith(14), layout).nodes.collect_rate_1).toBe("expensive")
        local profile = profileWith(0)
        profile.coins = BigNum.serialize(BigNum.new(1e20))
        local view = TreeView.build(profile, layout)
        T.expect(view.nodes.collect_rate_1).toBe("affordable")
        T.expect(view.nodes.collect_tool_2).toBe("affordable")
    end)

    T.it("nach einem Kauf: gekauft, Nachfolger kaufbar, die Reihe dahinter wird Silhouette", function()
        local view = TreeView.build(profileWith(1000, { "collect_tool_2" }), layout)
        T.expect(view.nodes.collect_tool_2).toBe("owned")
        T.expect(view.nodes.collect_tool_3).toBe("affordable")
        T.expect(view.nodes.sell_1).toBe("affordable")
        T.expect(view.nodes.sell_2).toBe("silhouette")
        T.expect(view.nodes.sell_3).toBe("hidden")
        T.expect(view.nodes.tank_4).toBe("hidden")
        local view2 = TreeView.build(profileWith(1000, { "collect_tool_2", "collect_tool_3", "sell_1" }), layout)
        T.expect(view2.nodes.sell_2).toBe("affordable")
        T.expect(view2.nodes.sell_3).toBe("silhouette")
        T.expect(view2.nodes.sell_4).toBe("hidden")
    end)

    T.it("der Zustand passt zu TreePurchase: nur kaufbare Knoten sind kaufbar oder zu teuer", function()
        local profile = profileWith(5000, { "collect_tool_2", "tank_1", "tank_2" })
        local view = TreeView.build(profile, layout)
        for _, node in UpgradeTree.list do
            local state = TreePurchase.nodeState(profile, node.id)
            local visual = view.nodes[node.id]
            if state == "owned" then
                T.expect(visual).toBe("owned")
            elseif state == "available" then
                T.expect(visual == "affordable" or visual == "expensive").toBe(true)
            else
                T.expect(visual == "silhouette" or visual == "hidden").toBe(true)
            end
        end
    end)

    T.it("unbekannte oder entfernte IDs im Profil werden nicht gezeichnet und ändern nichts", function()
        local plain = TreeView.build(profileWith(100), layout)
        local odd = TreeView.build(profileWith(100, { "gibt_es_nicht", "entfernter_knoten" }), layout)
        T.expect(odd.nodes).toEqual(plain.nodes)
        T.expect(odd.lines).toEqual(plain.lines)
        T.expect(odd.counter).toBe(plain.counter)
        T.expect(odd.nodes.gibt_es_nicht).toBeNil()
    end)
end)

T.describe("Linien", function()
    T.it("gekauft zu gekauft hell, gekauft zu kaufbar gedämpft, zu Silhouetten gestrichelt, zu Verborgenem keine", function()
        local view = TreeView.build(profileWith(1000, { "tank_1", "tank_2" }), layout)
        T.expect(lineStyle(view, "tank_1", "tank_2")).toBe("lit")
        T.expect(lineStyle(view, "tank_2", "tank_3")).toBe("dim")
        T.expect(view.nodes.tank_3).toBe("affordable")
        -- tank_4 braucht auch Werkzeug 3: verborgen, solange Werkzeug 3 im Nebel liegt, sonst Silhouette.
        T.expect(view.nodes.tank_4).toBe("hidden")
        T.expect(lineStyle(view, "tank_3", "tank_4")).toBeNil()
        local view2 = TreeView.build(profileWith(1000, { "tank_1", "tank_2", "collect_tool_2" }), layout)
        T.expect(view2.nodes.tank_4).toBe("silhouette")
        T.expect(lineStyle(view2, "tank_3", "tank_4")).toBe("dashed")
    end)

    T.it("Silhouetten hängen gestrichelt an ihrem Vorgänger", function()
        local view = TreeView.build(profileWith(0), layout)
        T.expect(lineStyle(view, "tank_1", "tank_2")).toBe("dashed")
        T.expect(lineStyle(view, "tank_2", "tank_3")).toBeNil() -- tank_3 ist verborgen
    end)

    T.it("Sperren aus anderen Spalten sind keine Linien, sondern stehen bei \"Braucht\"", function()
        local view = TreeView.build(profileWith(1000, { "collect_tool_2" }), layout)
        T.expect(lineStyle(view, "collect_tool_2", "sell_1")).toBeNil()
        T.expect(lineStyle(view, "collect_tool_2", "luck_1")).toBeNil()
        T.expect(lineStyle(view, "collect_tool_2", "collect_tool_3")).toBe("dim") -- gleiche Spalte
        for _, line in view.lines do
            T.expect(layout.nodes[line.from].column).toBe(layout.nodes[line.to].column)
        end
        local view2 = TreeView.build(profileWith(0, {}), layout)
        T.expect(view2.needs.sell_1).toEqual({ "collect_tool_2" })
        T.expect(view2.needs.tank_4).toContain("collect_tool_3")
    end)

    T.it("Bandlinien: das Werkzeug des Bands bestimmt, ob die Linie sichtbar ist und einen Namen trägt", function()
        local view = TreeView.build(profileWith(0), layout)
        T.expect(view.bands[1].toolId).toBe("collect_tool_2")
        T.expect(view.bands[1].visual).toBe("expensive")
        T.expect(view.bands[2].visual).toBe("silhouette")
        T.expect(view.bands[3].visual).toBe("hidden")
    end)
end)

T.describe("Zähler und Fokus", function()
    T.it("der Zähler ist die Zahl der kaufbaren und bezahlbaren Knoten", function()
        T.expect(TreeView.build(profileWith(0), layout).counter).toBe(0)
        T.expect(TreeView.build(profileWith(15), layout).counter).toBe(1) -- nur collect_rate_1
        T.expect(TreeView.build(profileWith(50), layout).counter).toBe(3) -- rate_1, tank_1, Schaufel
        local view = TreeView.build(profileWith(1000, { "collect_tool_2" }), layout)
        local count = 0
        for _, visual in view.nodes do
            if visual == "affordable" then
                count += 1
            end
        end
        T.expect(view.counter).toBe(count)
    end)

    T.it("Fokus: Tutorial-Knoten, sonst billigster bezahlbarer, sonst billigster kaufbarer, sonst Start", function()
        local rich = TreeView.build(profileWith(100), layout)
        T.expect(TreeView.focus(rich, "collect_tool_2")).toBe("collect_tool_2")
        T.expect(TreeView.focus(rich, nil)).toBe("collect_rate_1") -- 15 Münzen
        T.expect(TreeView.focus(rich, "gibt_es_nicht")).toBe("collect_rate_1")
        T.expect(TreeView.focus(rich, "sell_3")).toBe("collect_rate_1") -- nicht kaufbar: wie ohne Tutorial
        local poor = TreeView.build(profileWith(0), layout)
        T.expect(TreeView.focus(poor, nil)).toBe("collect_rate_1") -- billigster kaufbarer
        local done = {}
        for _, node in UpgradeTree.list do
            if not node.granted then
                table.insert(done, node.id)
            end
        end
        T.expect(TreeView.focus(TreeView.build(profileWith(0, done), layout), nil)).toBeNil() -- alles gekauft: Start
    end)
end)

T.describe("Karte", function()
    T.it("Silhouetten geben weder Namen noch Preis her, verborgene und unbekannte nichts", function()
        local view = TreeView.build(profileWith(0), layout)
        local silhouette = TreeView.info(view, "tank_2")
        T.expect(silhouette == nil).toBe(false)
        T.expect((silhouette :: TreeView.Info).visual).toBe("silhouette")
        T.expect((silhouette :: TreeView.Info).name).toBeNil()
        T.expect((silhouette :: TreeView.Info).description).toBeNil()
        T.expect((silhouette :: TreeView.Info).cost).toBeNil()
        T.expect((silhouette :: TreeView.Info).needs).toEqual({ "tank_1" })
        T.expect(TreeView.info(view, "tank_3")).toBeNil()
        T.expect(TreeView.info(view, "gibt_es_nicht")).toBeNil()
    end)

    T.it("kaufbare Knoten zeigen Name, Wirkung und Preis, gekaufte keinen Preis", function()
        local view = TreeView.build(profileWith(1000, { "tank_1" }), layout)
        local open = TreeView.info(view, "tank_2") :: TreeView.Info
        T.expect(open.name).toBe(UpgradeTree.byId.tank_2.name)
        T.expect(open.description).toBe(UpgradeTree.byId.tank_2.description)
        T.expect(open.cost).toBe(UpgradeTree.byId.tank_2.cost)
        T.expect(open.needs).toEqual({})
        local owned = TreeView.info(view, "tank_1") :: TreeView.Info
        T.expect(owned.name).toBe(UpgradeTree.byId.tank_1.name)
        T.expect(owned.cost).toBeNil()
    end)
end)

T.finish()
