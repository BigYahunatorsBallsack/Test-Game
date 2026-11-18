--!strict
-- Upgrades-Service
-- Zuständig: Skilltree-Käufe (PurchaseNode), Voraussetzungen, Zonen-Freischaltung über
-- Knoten-IDs, Sandsturm (Prestige). Paket 1.6 bringt den Mini-Kauf (PurchaseNode für die
-- ersten Knoten), 2.1 den ganzen Baum (Äste Sammeln, Tank, Verkauf, Glück), 2.5 die Zonen und
-- 2.7 den Sandsturm.
--
-- Die Regeln stehen in den reinen Modulen Logic/TreePurchase (Kauf, Zustand der Knoten) und
-- Logic/TreeEffects (Wirkung), beide mit Lune-Tests. Der Client schickt nur die Knoten-ID, der
-- Server prüft Voraussetzungen und Münzen und antwortet mit ok und Grund. Der Kauf läuft ohne
-- Warten in einem Aufruf, darum kann ein zweiter schneller Aufruf nicht doppelt kaufen.
-- Gespeichert werden nur die gekauften IDs; die Wirkung kommt immer aus der aktuellen Tabelle.

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
    -- Erst das offene Sammelfenster mit der alten Rate abrechnen (sonst gälte eine neue Rate
    -- bis zu einem Takt rückwirkend). Ein Fehler dabei darf den Kauf nicht verhindern.
    local settled, settleErr = pcall(Sand.settle, player)
    if not settled then
        warn(`[Upgrades] Abrechnung vor dem Kauf von {nodeId} fehlgeschlagen: {tostring(settleErr)}`)
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
