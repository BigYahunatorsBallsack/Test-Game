--!strict
-- Paket 2.2: Platz der Knoten im Baum (reine Logik) und die Daten dazu.

local T = require("./lib/expect")
local TreeLayout = require("../src/shared/Logic/TreeLayout")
local DataCheck = require("../src/shared/Logic/DataCheck")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local Config = require("../src/shared/Data/TreeLayout")

-- Tiefe Kopie, die gemeinsame Referenzen (list und byId zeigen auf dieselben Knoten) erhält.
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

-- Baum mit zusätzlichen Knoten (für Baum-Updates). byId wird neu aufgebaut.
local function treeWith(extra: { any }, change: ((any) -> ())?): any
    local list = deepCopy(UpgradeTree.list)
    for _, node in extra do
        table.insert(list, node)
    end
    if change ~= nil then
        change(list)
    end
    local byId = {}
    for _, node in list do
        byId[node.id] = node
    end
    return { list = list, byId = byId }
end

local layout = TreeLayout.compute()

T.describe("Platz im Baum", function()
    T.it("jeder Knoten bekommt genau eine Position, keine zwei teilen eine Zelle", function()
        local taken: { [string]: string } = {}
        for _, node in UpgradeTree.list do
            local placement = layout.nodes[node.id]
            T.expect(placement == nil).toBe(false)
            local key = `{placement.column}:{placement.row}`
            T.expect(taken[key]).toBeNil()
            taken[key] = node.id
        end
    end)

    T.it("ein Knoten liegt höher als seine Voraussetzungen in derselben Spalte", function()
        for _, node in UpgradeTree.list do
            local here = layout.nodes[node.id]
            for _, required in node.requires do
                local there = layout.nodes[required]
                if there.column == here.column then
                    T.expect(here.row).toBeGreaterThan(there.row)
                    T.expect(here.y).toBeLessThan(there.y) -- y wächst nach unten
                end
            end
        end
    end)

    T.it("Werkzeuge stehen in der Mitte, Tank und Glück links, Rate und Verkauf rechts", function()
        for _, node in UpgradeTree.list do
            local column = layout.nodes[node.id].column
            local kind = node.effect.kind
            if kind == "setTool" then
                T.expect(column).toBe(0)
            elseif kind == "setTank" or kind == "luckBonus" then
                T.expect(column).toBeLessThan(0)
            elseif kind == "rateBonus" or kind == "sellBonus" then
                T.expect(column).toBeGreaterThan(0)
            end
        end
    end)

    T.it("ein Knoten, der ein Werkzeug verlangt, liegt im Band dieses Werkzeugs oder darüber", function()
        local function toolBand(nodeId: string): number
            return layout.nodes[nodeId].band
        end
        -- Das Band wächst mit jedem Werkzeug, die Werkzeuge liegen in aufsteigender Reihe.
        local tools = { "collect_tool_2", "collect_tool_3", "collect_tool_4", "collect_tool_5", "collect_tool_6" }
        for index, toolId in tools do
            T.expect(toolBand(toolId)).toBe(index)
        end
        for _, node in UpgradeTree.list do
            for _, required in node.requires do
                if UpgradeTree.byId[required].effect.kind == "setTool" then
                    T.expect(layout.nodes[node.id].band >= toolBand(required)).toBe(true)
                    T.expect(layout.nodes[node.id].row >= layout.nodes[required].row).toBe(true)
                end
            end
        end
    end)

    T.it("gleiche Daten ergeben immer dieselben Koordinaten", function()
        local again = TreeLayout.compute()
        T.expect(again).toEqual(layout)
        local copy = TreeLayout.compute(treeWith({}), deepCopy(Config))
        T.expect(copy.nodes).toEqual(layout.nodes)
    end)

    T.it("die Fläche umschließt alle Knoten mit Rand, der Start liegt unten bei 0", function()
        local half = Config.nodeSize / 2
        for _, placement in layout.nodes do
            T.expect(placement.x - half >= layout.area.minX + Config.margin).toBe(true)
            T.expect(placement.x + half <= layout.area.maxX - Config.margin).toBe(true)
            T.expect(placement.y - half >= layout.area.minY + Config.margin).toBe(true)
            T.expect(placement.y + half <= layout.area.maxY - Config.margin).toBe(true)
        end
        T.expect(layout.start.x).toBe(0)
        T.expect(layout.start.y).toBe(0)
        T.expect(layout.area.maxY >= half + Config.margin).toBe(true)
        T.expect(layout.area.width).toBeCloseTo(layout.area.maxX - layout.area.minX, 1e-9)
        T.expect(layout.area.height).toBeCloseTo(layout.area.maxY - layout.area.minY, 1e-9)
    end)

    T.it("pro Werkzeug gibt es eine Bandlinie mit dem Werkzeug-Knoten, von unten nach oben", function()
        T.expect(#layout.bands).toBe(5)
        local lastY = 0
        for index, band in layout.bands do
            T.expect(band.index).toBe(index)
            T.expect(band.toolId == nil).toBe(false)
            T.expect(band.y).toBeLessThan(lastY)
            lastY = band.y
            -- Das Werkzeug steht direkt über seiner Bandlinie.
            T.expect(layout.nodes[band.toolId :: string].y).toBeLessThan(band.y)
        end
    end)
end)

T.describe("Baum-Update", function()
    T.it("ein neuer Knoten am Ende eines Asts bekommt einen freien Platz, andere bleiben stehen", function()
        local extended = treeWith({
            {
                id = "luck_7",
                name = "Neu",
                description = "Neu",
                branch = "luck",
                requires = { "luck_6" },
                cost = 5_000_000_000,
                effect = { kind = "luckBonus", bp = 1000 },
            },
        })
        local after = TreeLayout.compute(extended)
        T.expect(after.nodes.luck_7 == nil).toBe(false)
        T.expect(after.nodes.luck_7.row).toBeGreaterThan(after.nodes.luck_6.row)
        for id, placement in layout.nodes do
            T.expect(after.nodes[id]).toEqual(placement)
        end
    end)

    T.it("ein neuer Knoten in einem oberen Band verschiebt die Knoten darunter nie", function()
        local extended = treeWith({
            {
                id = "tank_13",
                name = "Neu",
                description = "Neu",
                branch = "tank",
                requires = { "tank_12" },
                cost = 5_000_000_000,
                effect = { kind = "setTank", capacity = 10_000_000 },
            },
            {
                id = "sell_9",
                name = "Neu",
                description = "Neu",
                branch = "sell",
                requires = { "sell_8" },
                cost = 5_000_000_000,
                effect = { kind = "sellBonus", bp = 1000 },
            },
        })
        local after = TreeLayout.compute(extended)
        for id, placement in layout.nodes do
            if placement.band < 5 then
                T.expect(after.nodes[id]).toEqual(placement)
            end
        end
    end)

    T.it("ein festgenagelter Knoten (pos) behält seinen Platz", function()
        local pinned = treeWith({}, function(list: { any })
            for _, node in list do
                if node.id == "sell_3" then
                    node.pos = { column = 2, row = 30 }
                end
            end
        end)
        local after = TreeLayout.compute(pinned)
        T.expect(after.nodes.sell_3.column).toBe(2)
        T.expect(after.nodes.sell_3.row).toBe(30)
        T.expect(after.nodes.sell_3.x).toBe(2 * Config.columnSpacing)
        T.expect(after.nodes.sell_3.y).toBe(-30 * Config.rowSpacing)
        -- Der Baum bleibt erreichbar: Die Fläche wächst bis zum festgenagelten Knoten.
        T.expect(after.area.minY <= after.nodes.sell_3.y - Config.nodeSize / 2).toBe(true)
    end)

    T.it("ein neuer Ast bekommt Platz in einer neuen Spalte, ohne dass etwas verrutscht", function()
        local config = deepCopy(Config)
        config.columns.luckBonus = -3 -- Spalte frei machen und verschieben
        local after = TreeLayout.compute(nil, config)
        for _, node in UpgradeTree.list do
            if node.effect.kind ~= "luckBonus" then
                T.expect(after.nodes[node.id]).toEqual(layout.nodes[node.id])
            end
        end
    end)
end)

T.describe("Daten der Baumansicht", function()
    T.it("DataCheck meldet für die echten Daten keine Fehler", function()
        T.expect(DataCheck.run()).toEqual({})
    end)

    local function errorsFor(change: (any) -> ()): string
        local data: any = deepCopy(DataCheck.defaults())
        change(data)
        return table.concat(DataCheck.run(data), "\n")
    end

    T.it("zwei Wirkungen in derselben Spalte werden abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.TreeLayout.columns.sellBonus = data.TreeLayout.columns.rateBonus
        end)).toContain("teilen sich die Spalte")
    end)

    T.it("eine Wirkung ohne Spalte wird abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.TreeLayout.columns.luckBonus = nil
        end)).toContain("hat keine Spalte")
    end)

    T.it("ungültige Zoomgrenzen werden abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.TreeLayout.zoom.max = data.TreeLayout.zoom.min
        end)).toContain("zoom.max muss über zoom.min liegen")
        T.expect(errorsFor(function(data: any)
            data.TreeLayout.zoom.start = 5
        end)).toContain("zoom.start")
    end)

    T.it("zu kleine Knoten bei kleinstem Zoom werden abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.TreeLayout.zoom.min = 0.3
        end)).toContain("minTouchPixels")
    end)

    T.it("Knoten, die sich berühren würden, werden abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.TreeLayout.rowSpacing = data.TreeLayout.nodeSize
        end)).toContain("rowSpacing")
    end)

    T.it("pos mit unbekannter Spalte oder Reihe 0 wird abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.UpgradeTree.list[1].pos = { column = 42, row = 1 }
        end)).toContain("pos.column")
        T.expect(errorsFor(function(data: any)
            data.UpgradeTree.list[1].pos = { column = 0, row = 0 }
        end)).toContain("pos braucht")
    end)

    T.it("pos auf dem Platz eines anderen Knotens wird als Kollision gemeldet", function()
        T.expect(errorsFor(function(data: any)
            local tank1 = layout.nodes.tank_1
            data.UpgradeTree.byId.tank_2.pos = { column = tank1.column, row = tank1.row }
            for _, node in data.UpgradeTree.list do
                if node.id == "tank_2" then
                    node.pos = { column = tank1.column, row = tank1.row }
                end
            end
        end)).toContain("liegt auf demselben Platz")
    end)

    T.it("Handy-Werte: startCompact außerhalb von min und max wird abgelehnt (Paket 3.6)", function()
        T.expect(errorsFor(function(data: any)
            data.TreeLayout.zoom.startCompact = 5
        end)).toContain("startCompact muss zwischen min und max")
        T.expect(errorsFor(function(data: any)
            data.TreeLayout.zoom.startCompact = nil
        end)).toContain("startCompact muss eine Zahl größer als 0")
    end)

    T.it("Handy-Werte: tapMaxMovePixelsTouch unter tapMaxMovePixels wird abgelehnt (Paket 3.6)", function()
        T.expect(errorsFor(function(data: any)
            data.TreeLayout.tapMaxMovePixelsTouch = 4
        end)).toContain("tapMaxMovePixelsTouch darf nicht unter")
    end)

    T.it("ein Platzhalter-Look ohne Farbe wird abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.TreeLayout.looks.setTank.color = { 255, 0 }
        end)).toContain("drei ganze Zahlen")
    end)
end)

T.finish()
