--!strict
-- Koloss-Service (Paket 5.6): das Server-Event "Der Koloss".
-- Am Wochenende der Koloss-Woche graben alle Spieler eines Servers gemeinsam. Jede Sekunde, die ein
-- Spieler in der Event-Zone wirklich Sand sammelt, füllt den Balken dieses Servers. Bei 100 % bekommen
-- alle Spieler im Server ihre Belohnung nach Beitrag.
--
-- Die Regeln stehen im reinen Modul Logic/Koloss (Lune-Tests in tests/koloss.spec.luau), die Zahlen in
-- Data/Koloss. Hier hängen nur Server-Uhr, Spieler, StateSync, Workspace-Attribute und Takt dran. Es
-- gibt keine Remote und kein Profilfeld außer dem Merker `profile.seasons[saisonId].koloss`.
--
-- Fortschritt: Events.addZoneSeconds ruft `Koloss.addZoneSeconds(player, zoneId, seconds)` mit den
-- Sekunden, die der Finds-Takt vom Server gerechnet hat (Collecting findSeconds, je Takt höchstens
-- 10 s). Das ist die einzige Stelle, die Fortschritt bucht. Der Stand lebt nur im Speicher dieses
-- Servers.
--
-- StateSync (über Sand.addSnapshotProvider):
--   koloss = { state, seasonId, progress, target, completed, you, tierId?, claimed, secondsLeft,
--              secondsToStart }   (Logic/Koloss.view, nur der eigene Beitrag)
-- Notify { kind = "kolossDone", tierId, tierName, rewards } an jeden Spieler, der bei 100 % eine
-- Belohnung bekommt.
--
-- Workspace-Attribute für Modell, Terrain und Effekte des Kolosses (auf Server und Clients lesbar):
--   KolossProgress  Zahl von 0 bis 1 (Fortschritt dieses Servers)
--   KolossState     "closed", "open" oder "complete"
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"; wirkt auf den Server):
--   game.Players.Name:SetAttribute("DebugSeason", "koloss")      -- Zeit im Fenster des Kolosses
--   game.Players.Name:SetAttribute("DebugKoloss", "progress:N")  -- N Sekunden gutschreiben
--   game.Players.Name:SetAttribute("DebugKoloss", "complete")    -- sofort auf 100 %
--   game.Players.Name:SetAttribute("DebugKoloss", "reset")       -- Stand auf 0
-- Das Attribut wird nach dem Lesen gelöscht. Außerhalb von Studio gibt es keinen Listener.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Takt, der Zustandswechsel erkennt und den Balken den Spielern in der Event-Zone neu sendet (Sekunden).
local SYNC_SECONDS = 5
-- Studio-Hilfe: Spieler-Attribut ("progress:N", "complete", "reset").
local DEBUG_ATTRIBUTE = "DebugKoloss"
local PROGRESS_ATTRIBUTE = "KolossProgress"
local STATE_ATTRIBUTE = "KolossState"

local shared = ReplicatedStorage:WaitForChild("Shared")
local KolossLogic = require(shared:WaitForChild("Logic"):WaitForChild("Koloss") :: ModuleScript) :: any
local SeasonsLogic = require(shared:WaitForChild("Logic"):WaitForChild("Seasons") :: ModuleScript) :: any
local ZonesData = require(shared:WaitForChild("Data"):WaitForChild("Zones") :: ModuleScript) :: any

local servicesFolder = script.Parent
local SeasonClock = require(servicesFolder:WaitForChild("SeasonClock") :: ModuleScript) :: any
local IS_STUDIO = RunService:IsStudio()

local Koloss = {}

local PlayerData: any = nil
local Sand: any = nil
local Net: any = nil

-- Stand dieses Servers (nur im Speicher).
local event = KolossLogic.newEvent()
local dirty = false -- Fortschritt hat sich seit dem letzten Takt geändert
local lastKey = ""

local function log(message: string)
    warn(`[Koloss] {message}`)
end

local function refresh(player: Player)
    local ok, err = pcall(Sand.refresh, player)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
end

local function refreshAll()
    for _, player in Players:GetPlayers() do
        if PlayerData.get(player) ~= nil then
            refresh(player)
        end
    end
end

-- Zustand für das Attribut: fertig, offen (Fortschritt läuft oder Fenster offen) oder geschlossen.
local function stateName(): string
    if event.completed then
        return "complete"
    end
    if event.progress > 0 or KolossLogic.window(os.time()).state == "open" then
        return "open"
    end
    return "closed"
end

local function publishAttributes()
    local target = KolossLogic.targetSeconds()
    Workspace:SetAttribute(PROGRESS_ATTRIBUTE, math.clamp(event.progress / target, 0, 1))
    Workspace:SetAttribute(STATE_ATTRIBUTE, stateName())
end

local function snapshotFor(player: Player): { [string]: any }
    local profile = PlayerData.get(player)
    if profile == nil then
        return {}
    end
    local ok, view = pcall(function(): any
        return KolossLogic.view(event, profile, player.UserId, SeasonClock.timeFor(player))
    end)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(view)}`)
        return {}
    end
    if view == nil then
        return {}
    end
    return { koloss = view }
end

-- 100 %: Belohnung an alle aktiven Spieler im Server (Beitrag 0 gilt auch, siehe Data/Koloss).
local function distribute()
    local seasonId = event.seasonId
    if seasonId == nil then
        return
    end
    for _, player in Players:GetPlayers() do
        local profile = PlayerData.get(player)
        if profile ~= nil and PlayerData.isActive(player.UserId) then
            local contribution = event.contributions[player.UserId] or 0
            local ok, result = pcall(function(): any
                -- Boosts laufen mit der echten Server-Uhr, eine Studio-Verschiebung verlängert sie nicht.
                return KolossLogic.claim(profile, seasonId, contribution, { boostNow = os.time() })
            end)
            if not ok then
                log(`Belohnung für {player.Name} fehlgeschlagen: {tostring(result)}`)
            elseif result.ok == true then
                pcall(Net.fire, player, "Notify", {
                    kind = KolossLogic.NOTIFY_KIND,
                    tierId = result.tierId,
                    tierName = result.tierName,
                    rewards = result.rewards,
                })
            elseif result.reason ~= "claimed" then
                log(`Belohnung für {player.Name} abgelehnt: {tostring(result.reason)} {tostring(result.detail)}`)
            end
        end
    end
end

-- Aufruf aus Events.addZoneSeconds: Sekunden, die der Server in der Event-Zone gezählt hat. Zählt nur,
-- wenn die Zone zur laufenden Saison gehört und das Fenster offen ist (Logic/Koloss).
function Koloss.addZoneSeconds(player: Player, zoneId: string, seconds: number)
    local now = SeasonClock.timeFor(player)
    if SeasonsLogic.activeForZone(now, zoneId) == nil then
        return
    end
    local added = KolossLogic.addSeconds(event, now, player.UserId, seconds)
    if added.gained <= 0 then
        return
    end
    dirty = true
    if added.completed then
        publishAttributes()
        distribute()
        refreshAll()
    end
end

-- Takt: bei Zustandswechsel allen Spielern, sonst nur den Spielern in einer Event-Zone den Stand neu
-- senden (jeder Spieler sendet sonst bei jeder Meldung allen anderen einen Snapshot).
local function tick()
    local state = KolossLogic.window(os.time()).state
    local key = `{state}:{tostring(event.seasonId)}:{event.completed}`
    if key ~= lastKey then
        lastKey = key
        dirty = false
        publishAttributes()
        refreshAll()
        return
    end
    if not dirty then
        return
    end
    dirty = false
    publishAttributes()
    for _, player in Players:GetPlayers() do
        local profile = PlayerData.get(player)
        if profile ~= nil and ZonesData.eventById[profile.currentZone] ~= nil then
            refresh(player)
        end
    end
end

local function connectStudioHelper(player: Player)
    player:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
        local value = player:GetAttribute(DEBUG_ATTRIBUTE)
        if value == nil then
            return
        end
        player:SetAttribute(DEBUG_ATTRIBUTE, nil)
        local action, number, problem = KolossLogic.parseDebug(value)
        if action == nil then
            log(`Studio: {tostring(problem)}`)
            return
        end
        if action == "reset" then
            KolossLogic.reset(event, nil)
        else
            local seconds = if action == "complete" then KolossLogic.targetSeconds() else (number :: number)
            local added = KolossLogic.addSeconds(event, SeasonClock.timeFor(player), player.UserId, seconds)
            if added.gained <= 0 and seconds > 0 then
                log(`Studio: nichts gebucht, das Fenster ist zu (zuerst DebugSeason "koloss" setzen) oder das Event ist fertig`)
            end
            if added.completed then
                distribute()
            end
        end
        dirty = false
        publishAttributes()
        refreshAll()
    end)
end

function Koloss.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Koloss.Start()
    if type(Sand.addSnapshotProvider) == "function" then
        Sand.addSnapshotProvider(snapshotFor)
    else
        log("Sand.addSnapshotProvider fehlt: der Client bekommt keinen Koloss-Zustand")
    end
    publishAttributes()
    if IS_STUDIO then
        local handled: { [Player]: boolean } = {}
        local function onPlayerAdded(player: Player)
            if handled[player] then
                return
            end
            handled[player] = true
            connectStudioHelper(player)
        end
        Players.PlayerAdded:Connect(onPlayerAdded)
        for _, player in Players:GetPlayers() do
            onPlayerAdded(player)
        end
        Players.PlayerRemoving:Connect(function(player: Player)
            handled[player] = nil
        end)
    end
    task.spawn(function()
        while true do
            task.wait(SYNC_SECONDS)
            local ok, err = pcall(tick)
            if not ok then
                log(`Takt fehlgeschlagen: {tostring(err)}`)
            end
        end
    end)
end

return Koloss
