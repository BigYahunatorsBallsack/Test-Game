--!strict
-- Wirkung der gekauften Skilltree-Knoten (Paket 2.1). Rein, ohne Roblox-API, Lune-Tests in
-- tests/skilltree.spec.luau.
--
-- Die Wirkung wird bei jedem Aufruf aus den gekauften Knoten-IDs und der aktuellen Tabelle
-- `UpgradeTree` berechnet und nie im Profil gespeichert. Ändert ein Update den Baum (Werte,
-- neue oder entfernte Knoten), gilt sofort die neue Tabelle, ohne Migration:
--  * Unbekannte (entfernte) Knoten-IDs im Profil bleiben gespeichert, wirken aber nicht.
--  * Ein gekaufter Knoten wirkt auch dann, wenn ein Update ihm eine neue Voraussetzung gibt,
--    die der Spieler noch nicht hat.
--
-- Wirkungen (Data/UpgradeTree):
--   setTool     das höchste freigeschaltete Werkzeug zählt (die Hand ist Start)
--   rateBonus   Hundertstel-Prozent auf die Grundrate des Werkzeugs, alle Boni addieren sich
--   setTank     neue Gesamt-Tankgröße, der höchste Wert zählt (sonst Economy.startTankCapacity)
--   sellBonus   Hundertstel-Prozent auf den Münzpreis pro Sand, alle Boni addieren sich
--   luckBonus   Hundertstel-Prozent auf die Fundchance, alle Boni addieren sich (Paket 2.6)

local Tools = require("../Data/Tools")
local UpgradeTree = require("../Data/UpgradeTree")
local Economy = require("../Data/Economy")

export type Effects = {
    tool: Tools.Tool,
    rateBonusBp: number,
    tankCapacity: number, -- ohne Gamepass-Faktor
    sellBonusBp: number,
    luckBonusBp: number,
}

local TreeEffects = {}

-- Besitzt der Spieler den Knoten, und kennt der Baum ihn?
function TreeEffects.owns(profile: any, nodeId: string): boolean
    local nodes = profile.nodes
    return type(nodes) == "table" and nodes[nodeId] == true and UpgradeTree.byId[nodeId] ~= nil
end

local function bpOf(node: UpgradeTree.Node): number
    local bp = node.effect.bp
    if type(bp) ~= "number" or bp ~= bp or bp < 0 or bp == math.huge then
        return 0
    end
    return bp
end

-- Alle Wirkungen auf einmal.
function TreeEffects.of(profile: any): Effects
    local result: Effects = {
        tool = Tools.byId.hand,
        rateBonusBp = 0,
        tankCapacity = Economy.startTankCapacity,
        sellBonusBp = 0,
        luckBonusBp = 0,
    }
    for _, tool in Tools.list do
        local owned = tool.nodeId == "start" or TreeEffects.owns(profile, tool.nodeId)
        if owned and tool.tier > result.tool.tier then
            result.tool = tool
        end
    end
    for _, node in UpgradeTree.list do
        if not TreeEffects.owns(profile, node.id) then
            continue
        end
        local kind = node.effect.kind
        if kind == "rateBonus" then
            result.rateBonusBp += bpOf(node)
        elseif kind == "sellBonus" then
            result.sellBonusBp += bpOf(node)
        elseif kind == "luckBonus" then
            result.luckBonusBp += bpOf(node)
        elseif kind == "setTank" then
            local capacity = node.effect.capacity
            if type(capacity) == "number" and capacity == capacity and capacity ~= math.huge then
                result.tankCapacity = math.max(result.tankCapacity, capacity)
            end
        end
    end
    return result
end

-- Faktor auf den Münzpreis pro Sand (1 = kein Bonus).
function TreeEffects.sellMultiplier(profile: any): number
    return (10000 + TreeEffects.of(profile).sellBonusBp) / 10000
end

-- Faktor auf die Fundchance pro Sekunde (1 = kein Bonus). Paket 2.6 multipliziert ihn mit
-- Economy/Zonen-Werten. Er ändert nur die Chance, nie die Verteilung der Seltenheiten.
function TreeEffects.luckMultiplier(profile: any): number
    return (10000 + TreeEffects.of(profile).luckBonusBp) / 10000
end

return TreeEffects
