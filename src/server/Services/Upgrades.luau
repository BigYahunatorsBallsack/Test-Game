--!strict
-- Upgrades-Service
-- Zuständig: Skilltree-Käufe (PurchaseNode), Voraussetzungen, Zonen-Freischaltung (ZoneService) über
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
local Sandstorm = require(shared:WaitForChild("Logic"):WaitForChild("Sandstorm") :: ModuleScript) :: any

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local ZoneService: any = nil
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
        -- Neue Zonen freischalten und melden (Paket 2.5). Ein Fehler darf den Kauf nicht kippen.
        local unlocked, unlockErr = pcall(ZoneService.unlockNew, player)
        if not unlocked then
            warn(`[Upgrades] Zonen-Freischaltung nach Kauf von {nodeId} fehlgeschlagen: {tostring(unlockErr)}`)
        end
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

-- Sandsturm auslösen (Paket 2.7). Der Client schickt nichts, die Kristalle rechnet allein der Server.
-- Alles bis `Sandstorm.apply` läuft ohne Warten in einem Aufruf: ein zweiter schneller Aufruf trifft
-- auf das schon zurückgesetzte Profil und bekommt "requires". Fehler in der Nacharbeit (Zone,
-- Anzeige) dürfen den schon gebuchten Sturm nicht als Fehlschlag melden.
local function onPrestige(player: Player): any
    local profile = PlayerData.get(player)
    if profile == nil then
        return { ok = false, reason = "unknown" }
    end
    -- Das offene Sammelfenster zählt noch zum alten Lauf (Sand im Tank). Die Fundzeit der letzten
    -- Zehntelsekunden verfällt mit dem Lauf (`Sand.resetAfterStorm`), das ist beabsichtigt.
    local settled, settleErr = pcall(Sand.settle, player)
    if not settled then
        warn(`[Upgrades] Abrechnung vor dem Sandsturm fehlgeschlagen: {tostring(settleErr)}`)
    end
    local result, reason = Sandstorm.apply(profile)
    if result == nil then
        return { ok = false, reason = reason }
    end
    -- Jeder Schritt der Nacharbeit einzeln, damit ein Fehler die übrigen nicht verhindert.
    local function step(label: string, fn: () -> ())
        local worked, err = pcall(fn)
        if not worked then
            warn(`[Upgrades] {label} nach dem Sandsturm fehlgeschlagen: {tostring(err)}`)
        end
    end
    step("Sammelzustand", function()
        Sand.resetAfterStorm(player)
    end)
    step("Zonenwechsel", function()
        ZoneService.resetAfterStorm(player)
    end)
    step("Meldung", function()
        Net.fire(player, "Notify", {
            kind = "sandstorm",
            crystals = result.crystals,
            total = result.total,
            bonusBp = result.bonusBpAfter,
            prestiges = result.prestiges,
            first = result.first,
        })
    end)
    step("Anzeige", function()
        Sand.refresh(player)
    end)
    -- Die Antwort trägt dieselben Werte, damit der Client die Animation auch dann zeigt, wenn die
    -- Meldung ausgefallen ist.
    return {
        ok = true,
        crystals = result.crystals,
        total = result.total,
        bonusBp = result.bonusBpAfter,
        first = result.first,
    }
end

function Upgrades.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    ZoneService = require(servicesFolder:WaitForChild("ZoneService") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Upgrades.Start()
    Net.on("PurchaseNode", onPurchaseNode)
    Net.on("Prestige", onPrestige)
end

return Upgrades
