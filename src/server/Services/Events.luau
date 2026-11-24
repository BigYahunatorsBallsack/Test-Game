--!strict
-- Events-Service (Paket 5.4: Event-Kalender)
-- Zuständig: Saison-Kalender aus Data/Seasons, Zustand im StateSync, Antwort auf "ist die Event-Kiste
-- offen?" für Crates. Das Server-Event "Der Koloss" und die Event-Zone folgen in 5.5 und 5.6.
--
-- Die Regeln stehen im reinen Modul Logic/Seasons (Lune-Tests in tests/seasons.spec.luau). Hier
-- hängen nur Server-Uhr (os.time, nie eine Zeit vom Client), StateSync und Takt dran. Es gibt hier
-- keine Remote: Abholen und Kauf des Saison-Passes (Paket 5.5b) liegen in Services/SeasonPasses, die
-- Saison-Punkte schreibt `addZoneSeconds` (Paket 5.5).
--
-- StateSync (über Sand.addSnapshotProvider):
--   season = { active, id?, name?, week?, phaseId?, phaseName?, hint?, secondsLeft?, crateId?, crateOpen?,
--              next? = { id, name, crateId, secondsToNext } }   (Logic/Seasons.state)
--   seasonPass = { seasonId, points, maxPoints, tier, tiers, premium, claimed = { free, premium },
--                  canBuy, ended, claimSecondsLeft }   (Logic/SeasonPass.view, Paket 5.5b)
--     während der laufenden Saison mit Stufen und in der Abholfrist danach (ended = true, canBuy = false);
--     sonst fehlt das Feld.
-- Ein Takt alle SEASON_CHECK_SECONDS erkennt Saison- und Wochenwechsel sowie den Wechsel in die und
-- aus der Abholfrist und sendet allen geladenen Spielern den Zustand neu. Den Countdown zählt der
-- Client selbst herunter.
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"; wirkt nur auf diesen Spieler):
--   game.Players.Name:SetAttribute("DebugSeason", "week:1")  -- mitten in Woche 1 (bis "week:4")
--   game.Players.Name:SetAttribute("DebugSeason", "ended")   -- ein Tag nach dem Saisonende (Abholfrist, 5.5b)
--   game.Players.Name:SetAttribute("DebugSeason", "off")     -- vor allen Saisons: "Nächste Saison in ..."
--   game.Players.Name:SetAttribute("DebugSeason", "clear")   -- zurück zur echten Zeit
-- "week:N" und "ended" gelten für die laufende, sonst die nächste, sonst die erste Saison der Tabelle.
-- Das Attribut wird nach dem Lesen gelöscht, die Einstellung bleibt, bis "clear" kommt. Außerhalb von
-- Studio gibt es keinen Listener, das Attribut wird nie gelesen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Takt, der Saison- und Wochenwechsel erkennt und den Zustand neu sendet (Sekunden).
local SEASON_CHECK_SECONDS = 5
-- Studio-Hilfe: Spieler-Attribut ("week:N", "off", "clear").
local DEBUG_ATTRIBUTE = "DebugSeason"

local shared = ReplicatedStorage:WaitForChild("Shared")
local SeasonsLogic = require(shared:WaitForChild("Logic"):WaitForChild("Seasons") :: ModuleScript) :: any
local SeasonPassLogic = require(shared:WaitForChild("Logic"):WaitForChild("SeasonPass") :: ModuleScript) :: any

local servicesFolder = script.Parent
local SeasonClock = require(servicesFolder:WaitForChild("SeasonClock") :: ModuleScript) :: any
local IS_STUDIO = RunService:IsStudio()

local Events = {}

local PlayerData: any = nil
local Sand: any = nil
local Koloss: any = nil

-- Letzter gesendeter Stand je Spieler (Saison-ID und Woche), damit der Takt nur bei Wechseln sendet.
local lastKey: { [Player]: string } = {}
local handled: { [Player]: boolean } = {}

local function log(message: string)
    warn(`[Events] {message}`)
end

-- Zeit, nach der der Kalender für diesen Spieler rechnet: die Server-Uhr (SeasonClock), in Studio mit
-- Debug-Einstellung die gewählte Woche.
local function timeFor(player: Player): number
    return SeasonClock.timeFor(player)
end

-- Teil des Schlüssels für den Saison-Pass: Saison und "läuft" oder "Abholfrist", sonst "none". Ändert
-- er sich (Saisonende, Ende der Abholfrist), sendet der Takt neu (Paket 5.5b).
local function passKeyOf(time: number): string
    local ok, current = pcall(SeasonPassLogic.current, time)
    if not ok or type(current) ~= "table" then
        return "none"
    end
    return `{tostring(current.season.id)}:{if current.ended then "grace" else "run"}`
end

local function keyOf(state: { [string]: any }, time: number): string
    local passKey = passKeyOf(time)
    if state.active == true then
        return `{state.id}:{state.week}|{passKey}`
    end
    local nextSeason = state.next
    return (if type(nextSeason) == "table" then `pause:{nextSeason.id}` else "pause") .. `|{passKey}`
end

-- Ist die Event-Kiste dieses Spielers jetzt offen? Nur true für die Kiste der laufenden Saison in
-- einer Woche mit crateOpen. Bei einem Fehler false (Kiste bleibt zu).
function Events.inSeason(player: Player, crateId: string): boolean
    local ok, result = pcall(function(): boolean
        return SeasonsLogic.inSeason(timeFor(player), crateId)
    end)
    if not ok then
        log(`inSeason fehlgeschlagen: {tostring(result)}`)
        return false
    end
    return result == true
end

local function snapshotFor(player: Player): { [string]: any }
    local time = 0
    local ok, state = pcall(function(): any
        time = timeFor(player)
        return SeasonsLogic.state(time)
    end)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(state)}`)
        return {}
    end
    if player.Parent == Players then
        lastKey[player] = keyOf(state, time)
    end
    local result: { [string]: any } = { season = state }
    -- Saison-Pass (Paket 5.5, 5.5b): während der laufenden Saison mit Stufen und in der Abholfrist danach.
    local profile = PlayerData.get(player)
    if profile ~= nil then
        local okPass, view = pcall(SeasonPassLogic.view, profile, time)
        if not okPass then
            log(`Saison-Pass-Anzeige für {player.Name} fehlgeschlagen: {tostring(view)}`)
        elseif view ~= nil then
            result.seasonPass = view
        end
    end
    return result
end

local function refresh(player: Player)
    local ok, err = pcall(Sand.refresh, player)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
end

-- Sammelzeit in der Event-Zone gutschreiben (Aufruf aus dem Finds-Takt, Sekunden vom Server gerechnet).
-- Zählt nur für die laufende Saison, deren Zone `zoneId` ist und gerade offen ist (SeasonClock). Gibt
-- die neu gewonnenen Punkte zurück.
function Events.addZoneSeconds(player: Player, zoneId: string, seconds: number): number
    local profile = PlayerData.get(player)
    if profile == nil or not PlayerData.isActive(player.UserId) then
        return 0
    end
    local season = SeasonsLogic.activeForZone(timeFor(player), zoneId)
    if season == nil then
        return 0
    end
    -- Server-Event "Der Koloss" (Paket 5.6): dieselben Sekunden füllen den Balken dieses Servers.
    local counted, err = pcall(Koloss.addZoneSeconds, player, zoneId, seconds)
    if not counted then
        log(`Koloss fehlgeschlagen: {tostring(err)}`)
    end
    local gained = SeasonPassLogic.addSeconds(profile, season.id, seconds)
    if gained > 0 then
        refresh(player)
    end
    return gained
end

-- Takt: bei Saison- oder Wochenwechsel allen geladenen Spielern den Zustand neu senden.
local function tick()
    for _, player in Players:GetPlayers() do
        if PlayerData.get(player) ~= nil then
            local time = 0
            local ok, state = pcall(function(): any
                time = timeFor(player)
                return SeasonsLogic.state(time)
            end)
            if ok and lastKey[player] ~= nil and keyOf(state, time) ~= lastKey[player] then
                refresh(player)
            end
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
        local action, week = SeasonsLogic.parseDebug(value)
        if action == nil then
            log(`Studio: {DEBUG_ATTRIBUTE} erwartet "week:1" bis "week:4", "ended", "off" oder "clear"`)
            return
        end
        if action == "clear" then
            SeasonClock.set(player, nil, nil)
        else
            SeasonClock.set(player, action, week)
        end
        refresh(player)
    end)
end

local function onPlayerAdded(player: Player)
    if handled[player] then
        return
    end
    handled[player] = true
    connectStudioHelper(player)
end

function Events.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Koloss = require(servicesFolder:WaitForChild("Koloss") :: ModuleScript)
end

function Events.Start()
    if type(Sand.addSnapshotProvider) == "function" then
        Sand.addSnapshotProvider(snapshotFor)
    else
        log("Sand.addSnapshotProvider fehlt: der Client bekommt keinen Saison-Zustand")
    end
    if IS_STUDIO then
        Players.PlayerAdded:Connect(onPlayerAdded)
        for _, player in Players:GetPlayers() do
            onPlayerAdded(player)
        end
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        lastKey[player] = nil
        handled[player] = nil
    end)
    task.spawn(function()
        while true do
            task.wait(SEASON_CHECK_SECONDS)
            local ok, err = pcall(tick)
            if not ok then
                log(`Takt fehlgeschlagen: {tostring(err)}`)
            end
        end
    end)
end

return Events
