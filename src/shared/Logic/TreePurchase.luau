--!strict
-- Kauf eines Skilltree-Knotens (Paket 1.6 Mini-Kauf, Paket 2.1 ganzer Baum). Rein, ohne
-- Roblox-API, Lune-Tests in tests/treepurchase.spec.luau und tests/skilltree.spec.luau.
--
-- Der Client schickt nur die Knoten-ID (PurchaseNode). Der Server prüft alles hier:
-- Knoten bekannt, nicht vergeben, noch nicht gekauft, Voraussetzungen erfüllt, genug Münzen.
-- Es gibt keinen Parameter für einen Preis. Ein zweiter schneller Aufruf trifft auf
-- "owned", weil der Kauf ohne Warten im selben Aufruf abgeschlossen wird.

local BigNum = require("./BigNum")
local UpgradeTree = require("../Data/UpgradeTree")

export type Reason = "unknown" | "granted" | "owned" | "requires" | "coins"

-- Zustand eines Knotens für die Anzeige (Paket 2.2): gekauft, kaufbar (Voraussetzungen erfüllt,
-- Geld egal) oder im Nebel (Voraussetzungen fehlen, oder vom Sandsturm vergeben und noch nicht
-- erhalten). Konzept: "Nur gekaufte und direkt erreichbare Knoten sind sichtbar."
export type NodeState = "owned" | "available" | "fog"

local TreePurchase = {}

local function owns(profile: any, nodeId: string): boolean
    return profile.nodes[nodeId] == true
end

-- Ist der Knoten kaufbar (Voraussetzungen erfüllt, nicht gekauft, nicht vergeben)?
-- Geld wird hier nicht geprüft (für die Anzeige "sichtbar, aber zu teuer").
function TreePurchase.availability(profile: any, nodeId: string): Reason?
    local node = UpgradeTree.byId[nodeId]
    if node == nil then
        return "unknown"
    end
    -- Vergebene Knoten (Sandsturm) lassen sich nie kaufen, auch wenn `granted` vergessen wurde.
    if node.granted == true or node.effect.kind == "grantedBySandstorm" then
        return "granted"
    end
    if owns(profile, nodeId) then
        return "owned"
    end
    for _, required in node.requires do
        if not owns(profile, required) then
            return "requires"
        end
    end
    return nil
end

-- Kann der Spieler den Knoten jetzt kaufen? Gibt nil zurück, wenn ja, sonst den Grund.
function TreePurchase.check(profile: any, nodeId: string): Reason?
    local reason = TreePurchase.availability(profile, nodeId)
    if reason ~= nil then
        return reason
    end
    local node = UpgradeTree.byId[nodeId]
    local coins = BigNum.deserialize(profile.coins)
    if BigNum.compare(coins, BigNum.new(node.cost)) < 0 then
        return "coins"
    end
    return nil
end

-- Kauft den Knoten. Gibt (true, nil) bei Erfolg zurück, sonst (false, Grund). Ändert
-- profile.coins und profile.nodes nur bei Erfolg.
function TreePurchase.buy(profile: any, nodeId: string): (boolean, Reason?)
    local reason = TreePurchase.check(profile, nodeId)
    if reason ~= nil then
        return false, reason
    end
    local node = UpgradeTree.byId[nodeId]
    local coins = BigNum.deserialize(profile.coins)
    profile.coins = BigNum.serialize(BigNum.sub(coins, BigNum.new(node.cost)))
    profile.nodes[nodeId] = true
    return true, nil
end

-- Knoten, die der Spieler jetzt sieht (Voraussetzungen erfüllt, nicht gekauft, nicht vergeben),
-- aufsteigend nach Preis, bei gleichem Preis nach ID.
function TreePurchase.visible(profile: any): { string }
    local ids: { string } = {}
    for _, node in UpgradeTree.list do
        if TreePurchase.availability(profile, node.id) == nil then
            table.insert(ids, node.id)
        end
    end
    table.sort(ids, function(a: string, b: string)
        local ca, cb = UpgradeTree.byId[a].cost, UpgradeTree.byId[b].cost
        if ca ~= cb then
            return ca < cb
        end
        return a < b
    end)
    return ids
end

-- Zustand eines bekannten Knotens. Unbekannte IDs ergeben nil.
function TreePurchase.nodeState(profile: any, nodeId: string): NodeState?
    if UpgradeTree.byId[nodeId] == nil then
        return nil
    end
    if owns(profile, nodeId) then
        return "owned"
    end
    if TreePurchase.availability(profile, nodeId) == nil then
        return "available"
    end
    return "fog"
end

-- Zustand aller Knoten des Baums (ID -> Zustand).
function TreePurchase.treeState(profile: any): { [string]: NodeState }
    local result: { [string]: NodeState } = {}
    for _, node in UpgradeTree.list do
        result[node.id] = TreePurchase.nodeState(profile, node.id) :: NodeState
    end
    return result
end

return TreePurchase
