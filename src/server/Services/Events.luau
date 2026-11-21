--!strict
-- Events-Service (Paket 5.4: Event-Kalender)
-- Zuständig: Saison-Kalender aus Data/Seasons, Zustand im StateSync, Antwort auf "ist die Event-Kiste
-- offen?" für Crates. Das Server-Event "Der Koloss" und die Event-Zone folgen in 5.5 und 5.6.
--
-- Die Regeln stehen im reinen Modul Logic/Seasons (Lune-Tests in tests/seasons.spec.luau). Hier
-- hängen nur Server-Uhr (os.time, nie eine Zeit vom Client), StateSync und Takt dran. Es gibt keine
-- Remote und kein Profilfeld.
--
-- StateSync (über Sand.addSnapshotProvider):
--   season = { active, id?, name?, week?, phaseId?, phaseName?, hint?, secondsLeft?, crateId?, crateOpen?,
--              next? = { id, name, crateId, secondsToNext } }   (Logic/Seasons.state)
-- Ein Takt alle SEASON_CHECK_SECONDS erkennt Saison- und Wochenwechsel und sendet allen geladenen
-- Spielern den Zustand neu. Den Countdown zählt der Client selbst herunter.
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"; wirkt nur auf diesen Spieler):
--   game.Players.Name:SetAttribute("DebugSeason", "week:1")  -- mitten in Woche 1 (bis "week:4")
--   game.Players.Name:SetAttribute("DebugSeason", "off")     -- vor allen Saisons: "Nächste Saison in ..."
--   game.Players.Name:SetAttribute("DebugSeason", "clear")   -- zurück zur echten Zeit
-- "week:N" gilt für die laufende, sonst die nächste, sonst die erste Saison der Tabelle. Das Attribut
-- wird nach dem Lesen gelöscht, die Einstellung bleibt, bis "clear" kommt. Außerhalb von Studio gibt es
-- keinen Listener, das Attribut wird nie gelesen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Takt, der Saison- und Wochenwechsel erkennt und den Zustand neu sendet (Sekunden).
local SEASON_CHECK_SECONDS = 5
-- Studio-Hilfe: Spieler-Attribut ("week:N", "off", "clear").
local DEBUG_ATTRIBUTE = "DebugSeason"

local shared = ReplicatedStorage:WaitForChild("Shared")
local SeasonsLogic = require(shared:WaitForChild("Logic"):WaitForChild("Seasons") :: ModuleScript) :: any

local servicesFolder = script.Parent
local IS_STUDIO = RunService:IsStudio()

local Events = {}

local PlayerData: any = nil
local Sand: any = nil

-- Studio-Hilfe je Spieler: { action = "off" | "week", week = number? }. Leer = echte Zeit.
local debugOverrides: { [Player]: { action: string, week: number? } } = {}
-- Letzter gesendeter Stand je Spieler (Saison-ID und Woche), damit der Takt nur bei Wechseln sendet.
local lastKey: { [Player]: string } = {}
local handled: { [Player]: boolean } = {}

local function log(message: string)
    warn(`[Events] {message}`)
end

-- Server-Uhr in Unix-Sekunden (dieselbe wie Daily, Angebote und Kaufprotokoll).
local function unixNow(): number
    return os.time()
end

-- Zeit, nach der der Kalender für diesen Spieler rechnet: die Server-Uhr, in Studio mit
-- Debug-Einstellung die gewählte Woche.
local function timeFor(player: Player): number
    local now = unixNow()
    if IS_STUDIO then
        local override = debugOverrides[player]
        if override ~= nil then
            local shifted = SeasonsLogic.debugTime(override.action, override.week, now)
            if shifted ~= nil then
                return shifted
            end
        end
    end
    return now
end

local function keyOf(state: { [string]: any }): string
    if state.active == true then
        return `{state.id}:{state.week}`
    end
    local nextSeason = state.next
    return if type(nextSeason) == "table" then `pause:{nextSeason.id}` else "pause"
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
    local ok, state = pcall(function(): any
        return SeasonsLogic.state(timeFor(player))
    end)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(state)}`)
        return {}
    end
    if player.Parent == Players then
        lastKey[player] = keyOf(state)
    end
    return { season = state }
end

local function refresh(player: Player)
    local ok, err = pcall(Sand.refresh, player)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
end

-- Takt: bei Saison- oder Wochenwechsel allen geladenen Spielern den Zustand neu senden.
local function tick()
    for _, player in Players:GetPlayers() do
        if PlayerData.get(player) ~= nil then
            local ok, state = pcall(function(): any
                return SeasonsLogic.state(timeFor(player))
            end)
            if ok and lastKey[player] ~= nil and keyOf(state) ~= lastKey[player] then
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
            log(`Studio: {DEBUG_ATTRIBUTE} erwartet "week:1" bis "week:4", "off" oder "clear"`)
            return
        end
        if action == "clear" then
            debugOverrides[player] = nil
        else
            debugOverrides[player] = { action = action, week = week }
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
        debugOverrides[player] = nil
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
