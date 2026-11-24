--!strict
-- Analytics-Service (Paket 6.3): schickt die wichtigsten Zahlen an AnalyticsService (Creator Dashboard).
--   * Tutorial-Trichter (LogOnboardingFunnelStepEvent): Schritt n beim Erreichen, "done" am Ende. Zeigt, wo
--     neue Spieler abbrechen.
--   * Käufe (LogEconomyEvent, Quelle IAP, Währung Gems): jeder neue Eintrag im Kaufprotokoll genau einmal.
--   * Sitzung (LogCustomEvent): session_start mit Rückkehr (neu oder Tage seit dem letzten Besuch) und
--     session_end mit Sitzungslänge in Eimern.
-- Die Regeln stehen in Logic/Analytics (Lune-Tests tests/analytics.spec.luau), Namen und Grenzen in
-- Data/Analytics. Der Service liest nur das Profil (ein Takt alle tickSeconds), ändert nichts und hat keine
-- Remote. Jeder Aufruf von AnalyticsService läuft in pcall: Ein Fehler hier stört nie das Spiel. In Studio
-- (logInStudio = false) wird nur ins Ausgabefenster geschrieben. Es werden nie Spielernamen gesendet.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()

local shared = ReplicatedStorage:WaitForChild("Shared")
local AnalyticsLogic = require(shared:WaitForChild("Logic"):WaitForChild("Analytics") :: ModuleScript) :: any
local AnalyticsData = require(shared:WaitForChild("Data"):WaitForChild("Analytics") :: ModuleScript) :: any
local TutorialLogic = require(shared:WaitForChild("Logic"):WaitForChild("Tutorial") :: ModuleScript) :: any

local servicesFolder = script.Parent
local PlayerData: any = nil

local Analytics = {}

type Tracker = { startedAt: number, loggedStep: number, seenPurchases: { [string]: boolean }, loadedAt: number }

local trackers: { [Player]: Tracker } = {}

local function log(message: string)
    warn(`[Analytics] {message}`)
end

-- Sendet, wenn nicht in Studio (oder logInStudio), und schreibt sonst nur eine Zeile.
local function send(label: string, call: () -> ())
    if IS_STUDIO and not AnalyticsData.logInStudio then
        print(`[Analytics] (Studio, nicht gesendet) {label}`)
        return
    end
    local ok, err = pcall(call)
    if not ok then
        log(`{label} fehlgeschlagen: {tostring(err)}`)
    end
end

local function logTutorialStep(player: Player, profile: any, tracker: Tracker)
    local step = TutorialLogic.stepOf(profile)
    if step <= tracker.loggedStep then
        return
    end
    local info = AnalyticsLogic.tutorialStep(step)
    if info == nil then
        return
    end
    tracker.loggedStep = step
    send(`Trichter {info.step} {info.name}`, function()
        AnalyticsService:LogOnboardingFunnelStepEvent(player, info.step, info.name)
    end)
end

local function logPurchases(player: Player, profile: any, tracker: Tracker)
    for _, entry in AnalyticsLogic.newPurchases(profile.purchaseLog, tracker.seenPurchases) do
        send(`Kauf {entry.productId} {entry.gems} Gems`, function()
            AnalyticsService:LogEconomyEvent(
                player,
                Enum.AnalyticsEconomyFlowType.Source,
                AnalyticsData.currencyName,
                if type(profile.gems) == "number" then profile.gems else 0,
                entry.gems,
                Enum.AnalyticsEconomyTransactionType.IAP.Name,
                entry.productId
            )
        end)
    end
end

local function onLoaded(player: Player, profile: any)
    if trackers[player] ~= nil or player.Parent == nil then
        return
    end
    local now = os.time()
    local tracker: Tracker = { startedAt = os.clock(), loggedStep = 0, seenPurchases = {}, loadedAt = now }
    trackers[player] = tracker
    -- Vorhandene Käufe nur merken (nicht noch einmal melden).
    AnalyticsLogic.newPurchases(profile.purchaseLog, tracker.seenPurchases, true)
    local info = AnalyticsLogic.returnInfo(profile.lastSeen, profile.createdAt, now)
    if info ~= nil then
        send(`session_start neu={info.isNew} Tage={info.days}`, function()
            AnalyticsService:LogCustomEvent(player, AnalyticsData.events.sessionStart, info.days, AnalyticsLogic.cleanFields({ isNew = if info.isNew then "yes" else "no" }))
        end)
    end
    -- Wer das Tutorial schon fertig hat, liefert keinen Trichter mehr (zählt nur Neue und Laufende).
    if not TutorialLogic.isDone(profile) then
        logTutorialStep(player, profile, tracker)
    else
        tracker.loggedStep = math.huge
    end
end

local function tick()
    for player, tracker in trackers do
        local profile = PlayerData.get(player)
        if profile ~= nil then
            if tracker.loggedStep ~= math.huge then
                logTutorialStep(player, profile, tracker)
                if TutorialLogic.isDone(profile) then
                    tracker.loggedStep = math.huge
                end
            end
            logPurchases(player, profile, tracker)
        end
    end
end

local function onRemoving(player: Player)
    local tracker = trackers[player]
    trackers[player] = nil
    if tracker == nil then
        return
    end
    local seconds = os.clock() - tracker.startedAt
    local bucket = AnalyticsLogic.sessionBucket(seconds)
    if bucket == nil then
        return
    end
    send(`session_end {bucket} {math.floor(seconds)} s`, function()
        AnalyticsService:LogCustomEvent(player, AnalyticsData.events.sessionEnd, math.floor(seconds), AnalyticsLogic.cleanFields({ bucket = bucket }))
    end)
end

function Analytics.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
end

function Analytics.Start()
    PlayerData.onLoaded(function(player: Player, profile: any)
        local ok, err = pcall(onLoaded, player, profile)
        if not ok then
            log(`Laden für {player.Name} fehlgeschlagen: {tostring(err)}`)
        end
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        pcall(onRemoving, player)
    end)
    task.spawn(function()
        while true do
            local ok, err = pcall(tick)
            if not ok then
                log(`Takt fehlgeschlagen: {tostring(err)}`)
            end
            task.wait(AnalyticsData.tickSeconds)
        end
    end)
end

return Analytics
