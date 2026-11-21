--!strict
-- Offline-Service (Paket 5.3)
-- Beim Laden des Profils zahlt der Begleiter den Offline-Ertrag (Logic/Offline.apply, Server-Uhr
-- os.time, nie eine Zeit vom Client) und der StateSync trägt den Bericht für die Karte "Willkommen
-- zurück" (`offline`). Es gibt keine Remote: Der Client kann nichts auslösen oder melden.
--
-- StateSync (über Sand.addSnapshotProvider):
--   offline = { id, ok, reason?, seconds, awaySeconds, capSeconds, capped, coins? } (Logic/Offline.snapshotOf)
-- `id` zählt je Bericht hoch (der Client zeigt jede id einmal). Der Bericht bleibt für die Sitzung im
-- Speicher des Servers; gespeichert wird nur das Profil (coins, runEarned, lastSeen) über das Autosave.
-- Ein Absturz vor dem Speichern verliert Münzen und lastSeen zusammen (dann zahlt der nächste Beitritt
-- für denselben Zeitraum, nie doppelt).
--
-- Reihenfolge: Offline muss in SERVICE_NAMES nach Sand stehen (dessen onLoaded prüft die Zone zuerst).
--
-- Pässe: Die Grenze von 12 Stunden gilt, wenn `profile.passes` den Pass beim Laden schon enthält (er
-- wird mit dem Kauf gespeichert). Ein Pass, der erst beim Laden vom Marktplatz bestätigt wird, zählt
-- erst beim nächsten Mal (zahlt höchstens zu wenig).
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"):
--   game.Players.Name:SetAttribute("DebugOffline", 30)       -- so tun, als wäre der Spieler 30 Minuten weg gewesen
--   game.Players.Name:SetAttribute("DebugOffline", 1000)     -- über die Grenze: "Grenze erreicht"
-- Das setzt lastSeen zurück und zahlt sofort; das Attribut wird danach gelöscht.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local servicesFolder = script.Parent
local shared = ReplicatedStorage:WaitForChild("Shared")
local OfflineLogic = require(shared:WaitForChild("Logic"):WaitForChild("Offline") :: ModuleScript) :: any

local DEBUG_ATTRIBUTE = "DebugOffline"
local DEBUG_MAX_MINUTES = 100000
local IS_STUDIO = RunService:IsStudio()

local Offline = {}

local PlayerData: any
local Sand: any

local reports: { [Player]: { [string]: any } } = {}
local counter = 0
local handled: { [Player]: boolean } = {}

local function log(text: string)
    print(`[Offline] {text}`)
end

local function unixNow(): number
    return os.time()
end

local function pay(player: Player, profile: any)
    local report = OfflineLogic.apply(profile, unixNow())
    if report.reason == "error" then
        warn(`[Offline] Ertrag für {player.Name} nicht gerechnet (Fehler)`)
    end
    if report.reason == "tooShort" or report.reason == "badTime" or report.reason == "noProfile" or report.reason == "error" then
        if report.reason ~= "tooShort" then
            reports[player] = nil
        end
        return
    end
    counter += 1
    reports[player] = OfflineLogic.snapshotOf(report, counter)
end

local function snapshotFor(player: Player): { [string]: any }
    local report = reports[player]
    if report == nil then
        return {}
    end
    return { offline = report }
end

local function connectStudioHelper(player: Player)
    player:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
        local value = player:GetAttribute(DEBUG_ATTRIBUTE)
        if value == nil then
            return
        end
        player:SetAttribute(DEBUG_ATTRIBUTE, nil)
        if type(value) ~= "number" or value ~= value or value <= 0 or value > DEBUG_MAX_MINUTES then
            log(`Studio: {DEBUG_ATTRIBUTE} erwartet Minuten (Zahl von 1 bis {DEBUG_MAX_MINUTES})`)
            return
        end
        local profile = PlayerData.get(player)
        if profile == nil then
            log(`Studio: Profil von {player.Name} ist noch nicht geladen`)
            return
        end
        profile.lastSeen = unixNow() - value * 60
        pay(player, profile)
        Sand.refresh(player)
    end)
end

local function onPlayerAdded(player: Player)
    if handled[player] then
        return
    end
    handled[player] = true
    connectStudioHelper(player)
end

function Offline.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
end

function Offline.Start()
    if type(Sand.addSnapshotProvider) == "function" then
        Sand.addSnapshotProvider(snapshotFor)
    else
        log("Sand.addSnapshotProvider fehlt: der Client bekommt keinen Offline-Bericht")
    end
    PlayerData.onLoaded(function(player: Player, profile: any)
        local ok, err = pcall(pay, player, profile)
        if not ok then
            warn(`[Offline] Fehler beim Offline-Ertrag für {player.Name}: {tostring(err)}`)
        end
        Sand.refresh(player) -- zweiter StateSync mit dem Bericht und den neuen Münzen
    end)
    if IS_STUDIO then
        Players.PlayerAdded:Connect(onPlayerAdded)
        for _, player in Players:GetPlayers() do
            onPlayerAdded(player)
        end
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        reports[player] = nil
        handled[player] = nil
    end)
end

return Offline
