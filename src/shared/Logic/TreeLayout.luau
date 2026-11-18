--!strict
-- Platz jedes Knotens im Baum (Paket 2.2). Rein, ohne Roblox-API, Lune-Tests in
-- tests/treelayout.spec.luau. Es gibt keine handgesetzten Koordinaten: Alles folgt aus den
-- Daten (UpgradeTree) und den Zahlen aus Data/TreeLayout.
--
--   Spalte  aus der Wirkung des Knotens (TreeLayout.columns). Werkzeuge bilden den Stamm (0).
--   Band    Jedes Werkzeug öffnet ein Band. Ein Knoten gehört zum Band des höchsten Werkzeugs,
--           das er direkt oder über seine Voraussetzungen verlangt (Band 0 = Start, Hand).
--   Reihe   Im Band steht ein Knoten über seinen Voraussetzungen derselben Spalte, sonst nach
--           der Reihenfolge in der Tabelle. Die Bänder stapeln sich von unten nach oben, darum
--           verschiebt ein neuer Knoten in einem oberen Band nie die Knoten darunter.
--   pos     Optionales Feld im Knoten nagelt Spalte und Reihe fest (DataCheck prüft Kollisionen).
--
-- Koordinaten: x nach rechts, y nach unten, der Start liegt bei (0, 0), Knoten darüber haben
-- negatives y. Alles in Pixeln der Baumfläche bei Zoom 1. Rechnet aus gleichen Daten immer
-- dasselbe (keine Zufallswerte, keine Zeit).

local DefaultTree = require("../Data/UpgradeTree")
local DefaultConfig = require("../Data/TreeLayout")

export type Placement = {
    column: number,
    row: number, -- 1 = unterste Reihe über dem Start, größere Zahlen liegen weiter oben
    band: number,
    x: number,
    y: number,
}

export type Band = {
    index: number, -- 1 = Band der Schaufel
    toolId: string?, -- Werkzeug-Knoten, der das Band öffnet
    y: number, -- Höhe der Trennlinie unter dem Band
}

export type Area = {
    minX: number,
    minY: number,
    maxX: number,
    maxY: number,
    width: number,
    height: number,
}

export type Layout = {
    nodes: { [string]: Placement },
    start: { x: number, y: number },
    bands: { Band },
    area: Area,
}

local TreeLayout = {}

local function columnOf(config: any, node: any, fallback: number): number
    local kind = if type(node.effect) == "table" then node.effect.kind else nil
    local column = config.columns[kind]
    if type(column) == "number" then
        return column
    end
    return fallback
end

function TreeLayout.compute(tree: any?, config: any?): Layout
    local data: any = tree or DefaultTree
    local cfg: any = config or DefaultConfig
    local list: { any } = data.list
    local byId: { [string]: any } = data.byId

    local maxColumn = 0
    for _, column in cfg.columns do
        maxColumn = math.max(maxColumn, column)
    end
    local fallbackColumn = maxColumn + 1

    -- Band je Knoten (mit Wächter gegen Zyklen, die DataCheck meldet).
    local bandOf: { [string]: number } = {}
    local visiting: { [string]: boolean } = {}
    local function bandFor(nodeId: string): number
        local known = bandOf[nodeId]
        if known ~= nil then
            return known
        end
        local node = byId[nodeId]
        if node == nil or visiting[nodeId] then
            return 0
        end
        visiting[nodeId] = true
        local highest = 0
        for _, required in node.requires do
            highest = math.max(highest, bandFor(required))
        end
        visiting[nodeId] = nil
        local band = highest
        if node.effect.kind == "setTool" then
            band = highest + 1
        end
        bandOf[nodeId] = band
        return band
    end

    -- Gruppen je (Spalte, Band) ohne festgenagelte Knoten.
    type Entry = { id: string, order: number, depth: number }
    local groups: { [string]: { Entry } } = {}
    local groupColumn: { [string]: number } = {}
    local groupBand: { [string]: number } = {}
    local maxBand = 0
    local groupKey: { [string]: string } = {}
    for order, node in list do
        local band = bandFor(node.id)
        maxBand = math.max(maxBand, band)
        if node.pos == nil then
            local column = columnOf(cfg, node, fallbackColumn)
            local key = `{column}:{band}`
            if groups[key] == nil then
                groups[key] = {}
                groupColumn[key] = column
                groupBand[key] = band
            end
            groupKey[node.id] = key
            table.insert(groups[key], { id = node.id, order = order, depth = 0 })
        end
    end

    -- Tiefe in der Gruppe: nach den Voraussetzungen derselben Gruppe.
    for key, entries in groups do
        local depthOf: { [string]: number } = {}
        local function depthFor(id: string, guard: number): number
            local known = depthOf[id]
            if known ~= nil then
                return known
            end
            if guard > #entries then
                return 0
            end
            local deepest = -1
            for _, required in byId[id].requires do
                if groupKey[required] == key then
                    deepest = math.max(deepest, depthFor(required, guard + 1))
                end
            end
            depthOf[id] = deepest + 1
            return deepest + 1
        end
        for _, entry in entries do
            entry.depth = depthFor(entry.id, 0)
        end
        table.sort(entries, function(a: Entry, b: Entry)
            if a.depth ~= b.depth then
                return a.depth < b.depth
            end
            return a.order < b.order
        end)
    end

    -- Höhe jedes Bands = längste Spalte darin.
    local heights: { number } = {}
    for band = 0, maxBand do
        heights[band + 1] = 0
    end
    for key, entries in groups do
        local band = groupBand[key]
        heights[band + 1] = math.max(heights[band + 1], #entries)
    end
    local startRow: { number } = {}
    local nextRow = 1
    for band = 0, maxBand do
        startRow[band + 1] = nextRow
        nextRow += heights[band + 1]
    end

    local nodes: { [string]: Placement } = {}
    local function place(id: string, column: number, row: number, band: number)
        nodes[id] = {
            column = column,
            row = row,
            band = band,
            x = column * cfg.columnSpacing,
            y = -row * cfg.rowSpacing,
        }
    end
    for key, entries in groups do
        local band = groupBand[key]
        for index, entry in entries do
            place(entry.id, groupColumn[key], startRow[band + 1] + index - 1, band)
        end
    end
    for _, node in list do
        if node.pos ~= nil then
            place(node.id, node.pos.column, node.pos.row, bandFor(node.id))
        end
    end

    local bands: { Band } = {}
    for band = 1, maxBand do
        local toolId: string? = nil
        for _, node in list do
            if node.effect.kind == "setTool" and bandOf[node.id] == band then
                toolId = node.id
                break
            end
        end
        table.insert(bands, {
            index = band,
            toolId = toolId,
            y = -(startRow[band + 1] - 0.5) * cfg.rowSpacing,
        })
    end

    -- Fläche: alle Knoten plus Start, dazu Knotenhälfte und Rand.
    local half = cfg.nodeSize / 2 + cfg.margin
    local minX, maxX, minY, maxY = 0, 0, 0, 0
    for _, placement in nodes do
        minX = math.min(minX, placement.x)
        maxX = math.max(maxX, placement.x)
        minY = math.min(minY, placement.y)
        maxY = math.max(maxY, placement.y)
    end
    local area: Area = {
        minX = minX - half,
        maxX = maxX + half,
        minY = minY - half,
        maxY = maxY + half,
        width = maxX - minX + 2 * half,
        height = maxY - minY + 2 * half,
    }

    return { nodes = nodes, start = { x = 0, y = 0 }, bands = bands, area = area }
end

return TreeLayout
