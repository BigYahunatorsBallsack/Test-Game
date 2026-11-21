--!strict
-- Codes-Service (Paket 5.2)
-- Zuständig: Codes einlösen (Remote RedeemCode), Zähler falscher Versuche und Sperre je Spieler,
-- Prüfung der Code-Tabelle beim Serverstart, Studio-Hilfe DebugCodes.
--
-- Die Codes stehen nur auf dem Server (src/server/Data/Codes, liegt in ServerScriptService und wird
-- nie zum Client repliziert). Die Regeln stehen im reinen Modul Logic/Codes (Lune-Tests in
-- tests/codes.spec.luau): normalize, redeem (Belohnung und Merker in einem Block ohne Warten), attempt
-- (Zähler und Sperre), check (Tabelle). Hier hängen nur Remote, Uhren, Profil, gemeinsame Sperre und
-- Anzeige dran.
--
-- RedeemCode: RemoteFunction mit genau einem Text (1 bis 24 Zeichen; Schema und Limit 1 je 3 s in
-- RemoteSpec). Antwort:
--   { ok = true, reward }
--     reward = { kind = "gems", amount, capped? } | { kind = "coinBoost", seconds } | { kind = "luck", seconds }
--     (amount = tatsächlich gutgeschriebene Gems, capped = true nur bei maxGems)
--   { ok = false, reason = "locked", secondsLeft }   secondsLeft: ganze Zahl ab 1
--   { ok = false, reason }  reason: invalid, alreadyRedeemed, busy, noProfile, error
-- Unbekannt, abgelaufen, noch nicht begonnen und ungültige Eingabe sind alle "invalid" (kein Hinweis,
-- ob es den Code gibt). Ein Aufruf über dem Limit wird von Net verworfen (Antwort nil).
--
-- Sperre: MAX_FAILURES falsche Versuche (Grund "invalid") sperren den Spieler LOCK_SECONDS lang. Schon
-- der Versuch, der die Sperre auslöst, antwortet "locked". In der Sperre wird jeder Text abgelehnt,
-- auch ein richtiger Code, ohne die Tabelle anzusehen. Ein Erfolg setzt den Zähler zurück; nach der
-- Sperre beginnt er neu. Andere Gründe (alreadyRedeemed, busy, noProfile, error) zählen nicht. Zähler
-- und Sperre liegen nur im Speicher dieses Servers, je UserId, mit der Uhr os.clock. Beim Verlassen
-- wird der Zähler gelöscht; eine laufende Sperre bleibt bis zu ihrem Ende stehen, damit ein schneller
-- Rejoin auf diesen Server sie nicht aufhebt (danach wird auch sie gelöscht).
--
-- Die Einlösung läuft unter derselben Sperre je Spieler wie OpenCrate, BuyDirectItem und ClaimDaily
-- (Crates.runExclusive; gleichzeitig: "busy"), damit Gems und Boosts eines Spielers nie gleichzeitig
-- gebucht werden. Die Unix-Zeit für Gültigkeit und Boosts ist os.time (nie eine Zeit vom Client).
-- Gespeichert wird wie bei Daily über das Autosave von ProfileStore: Belohnung und Merker
-- (profile.codes) liegen gemeinsam im Profil, ein Absturz vor dem Speichern verliert beides zusammen
-- (dann ist der Code erneut einlösbar, nie doppelt). Ohne aktive Sitzung gibt es "noProfile". Nach
-- einem Erfolg sendet runExclusive den Zustand neu (Sand.refresh).
--
-- Start: Logic/Codes.check prüft die Tabelle in Init. Bei Fehlern bricht der Serverstart mit allen
-- Texten ab (wie DataCheck in init.server.luau). Die Texte nennen die Code-ID, nie den Code.
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"):
--   game.Players.Name:SetAttribute("DebugCodes", "reset")  -- alle Codes wieder einlösbar, Sperre weg
-- Das Attribut wird danach gelöscht, damit derselbe Befehl erneut wirkt. Außerhalb von Studio gibt es
-- keinen Listener, das Attribut wird nie gelesen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Falsche Versuche (Grund "invalid") bis zur Sperre.
local MAX_FAILURES = 5
-- Dauer der Sperre je Spieler (Sekunden).
local LOCK_SECONDS = 60
-- Studio-Hilfe: Spieler-Attribut ("reset").
local DEBUG_CODES_ATTRIBUTE = "DebugCodes"
-- Text im Protokoll der gemeinsamen Sperre (Crates.runExclusive).
local LOCK_LABEL = "Code einlösen"

local IS_STUDIO = RunService:IsStudio()

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local CodesLogic = loadShared("Logic", "Codes")

local servicesFolder = script.Parent
local CodesData: any = nil
local PlayerData: any = nil
local Crates: any = nil
local Net: any = nil

local Codes = {}

local LIMITS = { maxFailures = MAX_FAILURES, lockSeconds = LOCK_SECONDS }

-- Zähler und Sperre je UserId (Logic/Codes.attempt). Nur Spieler mit Fehlversuchen oder Sperre.
local attempts: { [number]: any } = {}
-- Spieler, deren Studio-Hilfe schon verbunden ist.
local handled: { [Player]: boolean } = {}

local function log(message: string)
    warn(`[Codes] {message}`)
end

-- Server-Uhr in Unix-Sekunden für Gültigkeit der Codes und Boosts (wie Daily und Münz-Boost).
local function unixNow(): number
    return os.time()
end

-- Uhr der Sperre (Sekunden, monoton, nur auf diesem Server).
local function lockClock(): number
    return os.clock()
end

-- Profil nur, solange die Sitzung speichert (sonst ginge die Einlösung beim Verlassen verloren).
local function activeProfile(player: Player): any
    local profile = PlayerData.get(player)
    if profile == nil or not PlayerData.isActive(player.UserId) then
        return nil
    end
    return profile
end

-- Einlösen ohne Warten, unter der gemeinsamen Sperre mit OpenCrate, BuyDirectItem und ClaimDaily.
local function redeemNow(player: Player, text: string): any
    return Crates.runExclusive(player, LOCK_LABEL, function(): any
        local result = CodesLogic.redeem(activeProfile(player), CodesData, unixNow(), text)
        if result.ok == true then
            -- Nur die Belohnung für das Fenster (keine Code-ID, keinen Text).
            return { ok = true, reward = result.reward }
        end
        return result
    end)
end

local function onRedeemCode(player: Player, text: string): any
    local userId = player.UserId
    local now = lockClock()
    local previous = attempts[userId]
    local response, state = CodesLogic.attempt(previous, now, LIMITS, function(): any
        return redeemNow(player, text)
    end)
    if response.reason == CodesLogic.LOCKED and CodesLogic.lockSecondsLeft(previous, now) == 0 then
        -- Nur der Beginn einer Sperre kommt ins Protokoll (nie der eingegebene Text).
        log(`{player.Name} ({userId}) nach {MAX_FAILURES} falschen Codes für {LOCK_SECONDS} s gesperrt`)
    end
    if player.Parent ~= nil then
        attempts[userId] = if CodesLogic.isIdle(state) then nil else state
    end
    return response
end

-- Beim Verlassen: Fehlversuche und eine laufende Sperre bleiben noch so lange stehen wie eine Sperre.
local function forget(player: Player)
    handled[player] = nil
    local userId = player.UserId
    local state = attempts[userId]
    local secondsLeft = CodesLogic.lockSecondsLeft(state, lockClock())
    if secondsLeft <= 0 and type(state) == "table" and (state.failures or 0) > 0 then
        -- Fehlversuche ohne Sperre: auch sie überleben das Verlassen (sonst setzt ein Rejoin den Zähler
        -- zurück und die Sperre greift nie), und zwar so lange wie eine Sperre.
        secondsLeft = LOCK_SECONDS
    end
    if secondsLeft <= 0 then
        attempts[userId] = nil
        return
    end
    task.delay(secondsLeft, function()
        -- Ist der Spieler zurück und hat einen neuen Zustand, gehört der Eintrag wieder ihm.
        if attempts[userId] == state and Players:GetPlayerByUserId(userId) == nil then
            attempts[userId] = nil
        end
    end)
end

-- Studio-Hilfe: DebugCodes "reset" leert profile.codes und hebt die Sperre auf. Nur in Studio verbunden.
local function connectStudioHelper(player: Player)
    player:GetAttributeChangedSignal(DEBUG_CODES_ATTRIBUTE):Connect(function()
        local value = player:GetAttribute(DEBUG_CODES_ATTRIBUTE)
        if value == nil then
            return
        end
        player:SetAttribute(DEBUG_CODES_ATTRIBUTE, nil) -- derselbe Befehl soll erneut wirken
        local action, problem = CodesLogic.parseDebug(value)
        if action == nil then
            log(`Studio: {DEBUG_CODES_ATTRIBUTE}: {problem}`)
            return
        end
        local profile = PlayerData.get(player)
        if profile == nil then
            log(`Studio: {DEBUG_CODES_ATTRIBUTE}: Profil von {player.Name} ist noch nicht geladen`)
            return
        end
        profile.codes = {}
        attempts[player.UserId] = nil
        print(`[Codes] Studio: {player.Name} {DEBUG_CODES_ATTRIBUTE} = {tostring(value)}: alle Codes wieder einlösbar, Sperre aufgehoben`)
    end)
end

local function onPlayerAdded(player: Player)
    if handled[player] then
        return
    end
    handled[player] = true
    connectStudioHelper(player)
end

function Codes.Init()
    CodesData = require(servicesFolder.Parent:WaitForChild("Data"):WaitForChild("Codes") :: ModuleScript)
    local problems = CodesLogic.check(CodesData)
    if #problems > 0 then
        error("[Codes] Code-Tabelle fehlerhaft (src/server/Data/Codes):\n" .. table.concat(problems, "\n"))
    end
    if not RunService:IsStudio() then
        for _, row in CodesData.list do
            if (row.id == "welcome" and row.code == "WILLKOMMEN") or (row.id == "likes1000" and row.code == "1000LIKES") then
                error(`[Codes] Beispiel-Code "{row.id}" steht noch in src/server/Data/Codes: vor dem Start durch echte Codes ersetzen`)
            end
        end
    end
    print(`[Codes] Code-Tabelle geprüft: {#CodesData.list} Codes`)
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Crates = require(servicesFolder:WaitForChild("Crates") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Codes.Start()
    Net.on("RedeemCode", onRedeemCode)
    if IS_STUDIO then
        Players.PlayerAdded:Connect(onPlayerAdded)
        for _, player in Players:GetPlayers() do
            onPlayerAdded(player)
        end
    end
    Players.PlayerRemoving:Connect(forget)
end

return Codes
