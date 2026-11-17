--!strict
-- Upgrades-Service
-- Zuständig: Skilltree-Käufe (PurchaseNode), Voraussetzungen, Zonen-Freischaltung über
-- Knoten-IDs, Sandsturm (Prestige). Paket 1.6 bringt den Mini-Kauf (PurchaseNode für die
-- ersten Knoten), 2.1 baut den ganzen Baum darauf, 2.5 die Zonen und 2.7 den Sandsturm.
--
-- Die Regeln stehen im reinen Modul Logic/TreePurchase (Lune-Tests). Der Client schickt nur
-- die Knoten-ID, der Server prüft Voraussetzungen und Münzen und antwortet mit ok und Grund.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local TreePurchase = require(shared:WaitForChild("Logic"):WaitForChild("TreePurchase") :: ModuleScript) :: any

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local Net: any = nil

local Upgrades = {}

local function onPurchaseNode(player: Player, nodeId: string): any
    local profile = PlayerData.get(player)
    if profile == nil then
        return { ok = false, reason = "unknown" }
    end
    local ok, reason = TreePurchase.buy(profile, nodeId)
    if ok then
        -- Rate, Tank, Tutorial und Anzeige neu berechnen und an den Client schicken. Ein Fehler
        -- dabei darf den schon gebuchten Kauf nicht als Fehlschlag melden.
        local refreshed, err = pcall(Sand.refresh, player)
        if not refreshed then
            warn(`[Upgrades] Anzeige nach Kauf von {nodeId} fehlgeschlagen: {tostring(err)}`)
        end
        return { ok = true }
    end
    return { ok = false, reason = reason }
end

function Upgrades.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Upgrades.Start()
    Net.on("PurchaseNode", onPurchaseNode)
end

return Upgrades
