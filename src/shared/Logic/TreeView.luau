--!strict
-- Was der Spieler im Baum sieht (Paket 2.2). Rein, ohne Roblox-API, Lune-Tests in
-- tests/treeview.spec.luau. Grundlage ist TreePurchase.nodeState (gekauft, kaufbar, Nebel) aus
-- 2.1, dazu kommen die Münzen und der Platz aus Logic/TreeLayout.
--
-- Sichtbare Zustände je Knoten (Konzept: "Nur gekaufte und direkt erreichbare Knoten sind
-- sichtbar"):
--   owned       gekauft
--   affordable  kaufbar und genug Münzen
--   expensive   kaufbar, aber zu wenig Münzen
--   silhouette  im Nebel, alle Voraussetzungen sind gekauft oder kaufbar (Form ohne Namen, Preis)
--   hidden      alles andere, dazu vergebene Knoten (Sandsturm), solange sie nicht erhalten sind
--
-- Linien laufen nur innerhalb einer Spalte (gerade, senkrecht). Verlangt ein Knoten etwas aus
-- einer anderen Spalte (zum Beispiel ein Werkzeug), steht das als "Braucht" auf der Karte.

local BigNum = require("./BigNum")
local TreePurchase = require("./TreePurchase")
local TreeLayout = require("./TreeLayout")
local UpgradeTree = require("../Data/UpgradeTree")

export type Visual = "owned" | "affordable" | "expensive" | "silhouette" | "hidden"
export type LineStyle = "lit" | "dim" | "dashed"

export type Line = { from: string, to: string, style: LineStyle }
export type BandView = { index: number, toolId: string?, y: number, visual: Visual }

export type View = {
    nodes: { [string]: Visual },
    lines: { Line },
    bands: { BandView },
    needs: { [string]: { string } }, -- noch nicht gekaufte Voraussetzungen je Knoten
    counter: number, -- Zahl der Knoten, die jetzt kaufbar und bezahlbar sind
}

export type Info = {
    visual: Visual,
    name: string?, -- fehlt bei Silhouetten
    description: string?, -- fehlt bei Silhouetten
    cost: number?, -- nur bei kaufbaren Knoten
    needs: { string },
}

local TreeView = {}

local function ownsNode(profile: any, nodeId: string): boolean
    return type(profile.nodes) == "table" and profile.nodes[nodeId] == true
end

-- Baut die Ansicht. `profile` braucht nodes (ID -> true) und coins (serialisiert wie im Profil
-- und im StateSync). `layout` kommt aus TreeLayout.compute.
function TreeView.build(profile: any, layout: TreeLayout.Layout): View
    local states = TreePurchase.treeState(profile)
    local coins = BigNum.deserialize(profile.coins)

    local nodes: { [string]: Visual } = {}
    local counter = 0
    for _, node in UpgradeTree.list do
        local state = states[node.id]
        local visual: Visual
        if state == "owned" then
            visual = "owned"
        elseif state == "available" then
            if BigNum.compare(coins, BigNum.new(node.cost)) >= 0 then
                visual = "affordable"
                counter += 1
            else
                visual = "expensive"
            end
        else
            visual = "silhouette"
            if node.granted == true or node.effect.kind == "grantedBySandstorm" then
                visual = "hidden"
            else
                for _, required in node.requires do
                    if states[required] ~= "owned" and states[required] ~= "available" then
                        visual = "hidden"
                        break
                    end
                end
            end
        end
        nodes[node.id] = visual
    end

    local lines: { Line } = {}
    local needs: { [string]: { string } } = {}
    for _, node in UpgradeTree.list do
        local missing: { string } = {}
        for _, required in node.requires do
            if not ownsNode(profile, required) then
                table.insert(missing, required)
            end
        end
        needs[node.id] = missing

        local visual = nodes[node.id]
        local here = layout.nodes[node.id]
        if visual ~= "hidden" and here ~= nil then
            for _, required in node.requires do
                local there = layout.nodes[required]
                local requiredVisual = nodes[required]
                if there ~= nil and there.column == here.column and requiredVisual ~= nil and requiredVisual ~= "hidden" then
                    local style: LineStyle
                    if visual == "silhouette" then
                        style = "dashed"
                    elseif visual == "owned" and requiredVisual == "owned" then
                        style = "lit"
                    else
                        style = "dim"
                    end
                    table.insert(lines, { from = required, to = node.id, style = style })
                end
            end
        end
    end

    local bands: { BandView } = {}
    for _, band in layout.bands do
        local visual: Visual = if band.toolId ~= nil then (nodes[band.toolId] or "hidden") else "hidden"
        table.insert(bands, { index = band.index, toolId = band.toolId, y = band.y, visual = visual })
    end

    return { nodes = nodes, lines = lines, bands = bands, needs = needs, counter = counter }
end

-- Angaben für die Karte. Silhouetten geben weder Namen noch Preis her, verborgene Knoten und
-- unbekannte IDs nichts (nil).
function TreeView.info(view: View, nodeId: string): Info?
    local node = UpgradeTree.byId[nodeId]
    local visual = view.nodes[nodeId]
    if node == nil or visual == nil or visual == "hidden" then
        return nil
    end
    local needs = view.needs[nodeId] or {}
    if visual == "silhouette" then
        return { visual = visual, needs = needs }
    end
    local cost: number? = nil
    if visual == "affordable" or visual == "expensive" then
        cost = node.cost
    end
    return { visual = visual, name = node.name, description = node.description, cost = cost, needs = needs }
end

local function cheapest(view: View, wanted: Visual): string?
    local best: string? = nil
    for _, node in UpgradeTree.list do
        if view.nodes[node.id] == wanted then
            if best == nil then
                best = node.id
            else
                local current = UpgradeTree.byId[best :: string]
                if node.cost < current.cost or (node.cost == current.cost and node.id < current.id) then
                    best = node.id
                end
            end
        end
    end
    return best
end

-- Knoten, auf den die Kamera beim Öffnen zeigt: der Knoten des Tutorial-Schritts, sonst der
-- billigste bezahlbare, sonst der billigste kaufbare, sonst nil (= der Start).
function TreeView.focus(view: View, tutorialNodeId: string?): string?
    if tutorialNodeId ~= nil then
        local visual = view.nodes[tutorialNodeId]
        if visual == "affordable" or visual == "expensive" then
            return tutorialNodeId
        end
    end
    return cheapest(view, "affordable") or cheapest(view, "expensive")
end

return TreeView
