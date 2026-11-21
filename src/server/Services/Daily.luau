--!strict
-- Daily-Service (Paket 5.1)
-- Zuständig: Daily Reward abholen (Remote ClaimDaily), Zustand im StateSync (`daily`,
-- `luckBoostSeconds`), Tageswechsel um 0 Uhr UTC, Studio-Hilfe DebugDaily.
--
-- Die Regeln stehen im reinen Modul Logic/Daily (Lune-Tests in tests/daily.spec.luau): Serie, Start,
-- Belohnungen aus Economy.daily, Tag 7 mit Policy, alles in einem Block ohne Warten. Hier hängen nur
-- Remote, Server-Uhr (os.time, nie eine Zeit vom Client), Profil, Policy (Crates.policyState), Zufall
-- und Anzeige dran.
--
-- ClaimDaily: RemoteFunction ohne Argumente (Schema und Limit in RemoteSpec). Antwort:
--   { ok = true, day, reward, crate? }
--     reward = { kind = "coinBoost", seconds } | { kind = "luck", seconds }
--            | { kind = "gems", amount, capped? } | { kind = "crate", crateId, itemId }
--            | { kind = "fixedItem", itemId, copies }
--     crate  = nur bei kind "crate": dasselbe Format wie die Antwort von OpenCrate (für den Reveal)
--   { ok = false, reason }  reason: notStarted, alreadyClaimed, policyPending, noProfile, busy, error
-- Die Abholung läuft unter derselben Sperre wie OpenCrate und BuyDirectItem (Crates.runExclusive),
-- damit Gems, Pity und Inventar eines Spielers nie gleichzeitig gebucht werden. Gespeichert wird wie
-- bei den Kisten über das Autosave von ProfileStore: Belohnung und Serie liegen gemeinsam im Profil,
-- ein Absturz vor dem Speichern verliert beides zusammen (dann ist die Abholung erneut möglich, nie
-- doppelt). Ohne aktive Sitzung (Profil wird nicht mehr gespeichert) gibt es "noProfile".
--
-- Tag 7 während der ersten Policy-Abfrage ("pending"): Der Service wartet ohne Sperre höchstens
-- POLICY_WAIT_SECONDS, bis die Abfrage fertig ist, und versucht es dann einmal neu. Läuft sie dann
-- noch, antwortet er "policyPending", nichts ist gebucht.
--
-- StateSync (über Sand.addSnapshotProvider, Server-Uhr beim Snapshot):
--   daily            = { started, day, canClaim, secondsLeft, streak } (Logic/Daily.state)
--   luckBoostSeconds = Restsekunden des Glücks-Boosts (Perks.luckBoostSeconds), ab 0
-- Ein Takt alle DAY_CHECK_SECONDS erkennt den Tageswechsel (0 Uhr UTC) und sendet allen geladenen
-- Spielern den Zustand neu. Den Ablauf des Glücks-Boosts zählt der Client selbst herunter.
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"):
--   game.Players.Name:SetAttribute("DebugDaily", "reset")      -- Serie leer, Tag 1 sofort abholbar
--   game.Players.Name:SetAttribute("DebugDaily", "yesterday")  -- als wäre gestern abgeholt, Serie bleibt
--   game.Players.Name:SetAttribute("DebugDaily", "day:6")      -- Serie 6, gestern abgeholt: Tag 7 abholbar
-- Das Attribut wird danach gelöscht, damit derselbe Befehl erneut wirkt. Außerhalb von Studio gibt es
-- keinen Listener, das Attribut wird nie gelesen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Tag 7 während der ersten Policy-Abfrage: so lange wartet ClaimDaily höchstens (Sekunden). Die
-- Abfrage selbst braucht mit allen Versuchen etwa 4 s (Crates: 3 Versuche, 2 s Pause).
local POLICY_WAIT_SECONDS = 6
-- So oft wird während des Wartens nachgesehen, ob die Abfrage fertig ist (Sekunden).
local POLICY_POLL_SECONDS = 0.25
-- Takt, der den Tageswechsel (0 Uhr UTC) erkennt und den Zustand neu sendet (Sekunden).
local DAY_CHECK_SECONDS = 5
-- Studio-Hilfe: Spieler-Attribut ("reset", "yesterday", "day:N").
local DEBUG_DAILY_ATTRIBUTE = "DebugDaily"
-- Gründe, die nur der Service kennt.
local BUSY_REASON = "busy"
local ERROR_REASON = "error"
local POLICY_PENDING_REASON = "policyPending"
-- Text im Protokoll der gemeinsamen Sperre (Crates.runExclusive).
local LOCK_LABEL = "Daily Reward"

local IS_STUDIO = RunService:IsStudio()

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local DailyLogic = loadShared("Logic", "Daily")
local Perks = loadShared("Logic", "Perks")

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local Crates: any = nil
local Net: any = nil

local Daily = {}

-- Ein Zufallsgeber je Server für die Eisenkiste an Tag 7 (nicht je Aufruf neu gesät).
local random = Random.new()
local function nextRandom(): number
    return random:NextNumber()
end

-- Läuft für diesen Spieler schon eine Abholung (auch während des Wartens auf die Policy)?
local claiming: { [Player]: boolean } = {}
-- Spieler, deren Studio-Hilfe schon verbunden ist.
local handled: { [Player]: boolean } = {}

local function log(message: string)
    warn(`[Daily] {message}`)
end

-- Server-Uhr in Unix-Sekunden (dieselbe wie Münz-Boost, Angebote und Kaufprotokoll).
local function unixNow(): number
    return os.time()
end

-- Anzeige neu senden. Ein Fehler hier ändert nichts an der gebuchten Abholung.
local function refresh(player: Player)
    local ok, err = pcall(Sand.refresh, player)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
end

-- Profil nur, solange die Sitzung speichert (sonst ginge die Abholung beim Verlassen verloren).
local function activeProfile(player: Player): any
    local profile = PlayerData.get(player)
    if profile == nil or not PlayerData.isActive(player.UserId) then
        return nil
    end
    return profile
end

-- Ein Versuch ohne Warten, unter der gemeinsamen Sperre mit OpenCrate und BuyDirectItem.
local function claimNow(player: Player): any
    return Crates.runExclusive(player, LOCK_LABEL, function(): any
        local result = DailyLogic.claim(activeProfile(player), unixNow(), {
            policyState = Crates.policyState(player),
            random = nextRandom,
        })
        if result.ok == true then
            -- Nur die Felder für Fenster und Reveal (kein `daily`, den Zustand schickt der StateSync).
            return { ok = true, day = result.day, reward = result.reward, crate = result.crate }
        end
        return result
    end)
end

local function onClaimDaily(player: Player): any
    if claiming[player] then
        return { ok = false, reason = BUSY_REASON }
    end
    claiming[player] = true
    local ok, result = pcall(function(): any
        local first = claimNow(player)
        if first.reason ~= POLICY_PENDING_REASON then
            return first
        end
        -- Tag 7, die erste Policy-Abfrage läuft noch: ohne Sperre warten, dann einmal neu versuchen.
        local deadline = os.clock() + POLICY_WAIT_SECONDS
        while os.clock() < deadline and player.Parent ~= nil and Crates.policyState(player) == DailyLogic.POLICY_PENDING do
            task.wait(POLICY_POLL_SECONDS)
        end
        return claimNow(player)
    end)
    claiming[player] = nil
    if not ok then
        log(`Abholung für {player.Name} fehlgeschlagen: {tostring(result)}`)
        return { ok = false, reason = ERROR_REASON }
    end
    return result
end

-- Felder für den StateSync (Server-Uhr beim Snapshot). Wartet nie.
local function snapshotFor(player: Player): { [string]: any }
    local profile = PlayerData.get(player)
    if profile == nil then
        return {}
    end
    local now = unixNow()
    return {
        daily = DailyLogic.state(profile, now),
        luckBoostSeconds = Perks.luckBoostSeconds(profile, now),
    }
end

-- Sendet allen geladenen Spielern den Zustand neu, sobald ein neuer UTC-Tag beginnt.
local function watchDayChange()
    local shownDay = DailyLogic.dayOf(unixNow())
    while true do
        task.wait(DAY_CHECK_SECONDS)
        local today = DailyLogic.dayOf(unixNow())
        if today ~= shownDay then
            shownDay = today
            for _, player in Players:GetPlayers() do
                if PlayerData.isLoaded(player) then
                    refresh(player)
                end
            end
        end
    end
end

-- Studio-Hilfe: DebugDaily setzt die Serie (Logic/Daily.withDebug). Nur in Studio verbunden.
local function connectStudioHelper(player: Player)
    player:GetAttributeChangedSignal(DEBUG_DAILY_ATTRIBUTE):Connect(function()
        local value = player:GetAttribute(DEBUG_DAILY_ATTRIBUTE)
        if value == nil then
            return
        end
        player:SetAttribute(DEBUG_DAILY_ATTRIBUTE, nil) -- derselbe Befehl soll erneut wirken
        local action, streak, problem = DailyLogic.parseDebug(value)
        if action == nil then
            log(`Studio: {DEBUG_DAILY_ATTRIBUTE}: {problem}`)
            return
        end
        local profile = PlayerData.get(player)
        if profile == nil then
            log(`Studio: {DEBUG_DAILY_ATTRIBUTE}: Profil von {player.Name} ist noch nicht geladen`)
            return
        end
        local now = unixNow()
        profile.daily = DailyLogic.withDebug(profile, action, streak, now)
        local state = DailyLogic.state(profile, now)
        print(`[Daily] Studio: {player.Name} {DEBUG_DAILY_ATTRIBUTE} = {tostring(value)}: Serie {profile.daily.streak}, nächster Tag {state.day}, abholbar {tostring(state.canClaim)}`)
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

function Daily.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Crates = require(servicesFolder:WaitForChild("Crates") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Daily.Start()
    Net.on("ClaimDaily", onClaimDaily)
    if type(Sand.addSnapshotProvider) == "function" then
        Sand.addSnapshotProvider(snapshotFor)
    else
        log("Sand.addSnapshotProvider fehlt: der Client bekommt keinen Daily-Zustand")
    end
    task.spawn(watchDayChange)

    if IS_STUDIO then
        Players.PlayerAdded:Connect(onPlayerAdded)
        for _, player in Players:GetPlayers() do
            onPlayerAdded(player)
        end
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        claiming[player] = nil
        handled[player] = nil
    end)
end

return Daily
