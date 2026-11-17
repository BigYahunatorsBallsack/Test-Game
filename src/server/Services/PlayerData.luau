--!strict
-- PlayerData-Service
-- Lädt, hält und speichert die Spielerprofile mit ProfileStore (Wally, ServerPackages).
-- Den Ablauf (Migration, Fehlerfälle, Sitzungssperre, lastSeen) regelt das reine Modul
-- Logic/PlayerSession; hier wird nur ProfileStore als Speicher angeschlossen.
--
-- Für andere Services:
--   PlayerData.get(player)       -> Profil (lebende Tabelle, Änderungen werden gespeichert) oder nil
--   PlayerData.isLoaded(player)  -> boolean
--   PlayerData.onLoaded(fn)      -> fn(player, profile), sobald ein Profil geladen ist
--
-- In Studio wird ein eigener DataStore benutzt (STUDIO_STORE_NAME), Live-Daten bleiben unberührt.
-- Studio-Hilfe (nur in Studio): In der Befehlszeile (Ansicht "Server") Attribute am Spieler
-- setzen, z. B. game.Players.Name:SetAttribute("DebugCoins", 12345) oder
-- game.Players.Name:SetAttribute("DebugGems", 50). Der Server übernimmt den Wert ins Profil.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Name des DataStores. Ändern nur mit Migrationsplan: ein neuer Name heißt neue, leere Profile.
local STORE_NAME = "PlayerData_v1"
-- In Studio ein eigener Store, damit Tests (und die Studio-Hilfe) nie Live-Spielstände ändern.
local STUDIO_STORE_NAME = "PlayerData_Studio_v1"
-- Nach so vielen Sekunden gibt das Laden auf, und der Spieler bekommt eine Meldung.
local LOAD_TIMEOUT_SECONDS = 120
-- Wartezeit zwischen zwei Prüfungen, ob ein alter Ladevorgang (schneller Rejoin) fertig ist.
local BUSY_POLL_SECONDS = 0.5
-- Studio-Hilfe: Attributnamen am Spieler.
local DEBUG_COINS_ATTRIBUTE = "DebugCoins"
local DEBUG_GEMS_ATTRIBUTE = "DebugGems"

local shared = ReplicatedStorage:WaitForChild("Shared")
local logic = shared:WaitForChild("Logic")
local PlayerSession = require(logic:WaitForChild("PlayerSession") :: ModuleScript) :: any
local BigNum = require(logic:WaitForChild("BigNum") :: ModuleScript) :: any
local ProfileStore = require(
    ServerScriptService:WaitForChild("ServerPackages"):WaitForChild("ProfileStore") :: ModuleScript
) :: any

local PlayerData = {}

local manager: any = nil
local loadedCallbacks: { (Player, any) -> () } = {}

local function log(message: string)
    warn(`[PlayerData] {message}`)
end

-- Schließt ein ProfileStore-Profil an die Schnittstelle von PlayerSession an.
local function wrapProfile(profile: any, userId: number): any
    profile:AddUserId(userId) -- DSGVO: Profil dem Spieler zuordnen
    return {
        getData = function(): any
            return profile.Data
        end,
        setData = function(data: any)
            profile.Data = data
        end,
        onSave = function(callback: () -> ())
            profile.OnSave:Connect(callback)
        end,
        onSessionEnd = function(callback: () -> ())
            profile.OnSessionEnd:Connect(callback)
        end,
        endSession = function()
            profile:EndSession()
        end,
    }
end

local function newStore(profileStore: any): any
    return {
        startSession = function(key: string, cancel: () -> boolean): any
            -- Mit Cancel gilt das eigene Zeitlimit von ProfileStore nicht mehr, darum hier.
            local startedAt = os.clock()
            local ok, profile = pcall(function()
                return profileStore:StartSessionAsync(key, {
                    Cancel = function(): boolean
                        return cancel() or os.clock() - startedAt > LOAD_TIMEOUT_SECONDS
                    end,
                })
            end)
            if not ok then
                log(`StartSessionAsync fehlgeschlagen ({key}): {tostring(profile)}`)
                return nil
            end
            if profile == nil then
                return nil
            end
            local userId = tonumber(string.match(key, "%d+$")) or 0
            return wrapProfile(profile, userId)
        end,
    }
end

local function playerByUserId(userId: number): Player?
    return Players:GetPlayerByUserId(userId)
end

local function onPlayerAdded(player: Player)
    -- Schneller Rejoin: erst warten, bis der alte Ladevorgang für diese UserId beendet ist.
    while manager.isBusy(player.UserId) do
        task.wait(BUSY_POLL_SECONDS)
        if player.Parent ~= Players then
            return
        end
    end
    manager.load(player.UserId, function(): boolean
        return player.Parent == Players
    end)
end

local function onPlayerRemoving(player: Player)
    manager.release(player.UserId)
end

-- Studio-Hilfe: Attribute am Spieler ins Profil übernehmen. Nur in Studio, nie im Live-Spiel.
-- Attribute, die ein Client setzt, kommen nicht beim Server an, das ist also kein Zugang
-- für Exploits; die Prüfung auf Studio sorgt zusätzlich dafür, dass es live nichts tut.
local function connectStudioHelper(player: Player)
    local function apply(attribute: string)
        local value = player:GetAttribute(attribute)
        local profile = PlayerData.get(player)
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge or profile == nil then
            return
        end
        if attribute == DEBUG_COINS_ATTRIBUTE then
            profile.coins = BigNum.serialize(BigNum.new(math.max(value, 0)))
        else
            profile.gems = math.max(math.floor(value), 0)
        end
        print(`[PlayerData] Studio: {player.Name} Münzen = {profile.coins.m}e{profile.coins.e}, Gems = {profile.gems}`)
    end
    for _, attribute in { DEBUG_COINS_ATTRIBUTE, DEBUG_GEMS_ATTRIBUTE } do
        player:GetAttributeChangedSignal(attribute):Connect(function()
            apply(attribute)
        end)
    end
end

function PlayerData.get(player: Player): any
    return manager.get(player.UserId)
end

function PlayerData.isLoaded(player: Player): boolean
    return manager ~= nil and manager.isLoaded(player.UserId)
end

function PlayerData.onLoaded(callback: (Player, any) -> ())
    table.insert(loadedCallbacks, callback)
end

function PlayerData.Init()
    local storeName = if RunService:IsStudio() then STUDIO_STORE_NAME else STORE_NAME
    local profileStore = ProfileStore.New(storeName)
    ProfileStore.OnError:Connect(function(message: string, store: string, key: string)
        log(`ProfileStore-Fehler ({store}/{key}): {message}`)
    end)
    ProfileStore.OnCriticalToggle:Connect(function(isCritical: boolean)
        log(if isCritical then "ProfileStore meldet viele Fehler in Folge (kritisch)" else "ProfileStore wieder normal")
    end)
    manager = PlayerSession.new({
        store = newStore(profileStore),
        now = os.time,
        kick = function(userId: number, message: string)
            if ProfileStore.IsClosing then
                return -- Server fährt herunter, ProfileStore beendet die Sitzungen selbst
            end
            local player = playerByUserId(userId)
            if player ~= nil then
                player:Kick(message)
            end
        end,
        log = log,
    })
    manager.onLoaded(function(userId: number, profile: any)
        local player = playerByUserId(userId)
        if player == nil then
            return
        end
        print(`[PlayerData] {player.Name} geladen: Münzen {profile.coins.m}e{profile.coins.e}, Gems {profile.gems}`)
        for _, callback in loadedCallbacks do
            task.spawn(callback, player, profile)
        end
    end)

    -- Remotes nur annehmen, wenn das Profil geladen ist.
    local Net = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript) :: any
    Net.setProfileCheck(PlayerData.isLoaded)

    -- Ohne API-Zugriff (Studio) nutzt ProfileStore einen Test-Speicher: darauf hinweisen.
    task.spawn(function()
        while ProfileStore.DataStoreState == "NotReady" do
            task.wait(0.5)
        end
        if ProfileStore.DataStoreState ~= "Access" then
            warn(
                `[PlayerData] Kein DataStore-Zugriff ({ProfileStore.DataStoreState}): Test-Speicher aktiv, `
                    .. "nichts wird dauerhaft gespeichert. In Studio: Spieleinstellungen > Sicherheit > "
                    .. "Studio-Zugriff auf API-Dienste aktivieren."
            )
        end
    end)
end

function PlayerData.Start()
    Players.PlayerAdded:Connect(function(player: Player)
        if RunService:IsStudio() then
            connectStudioHelper(player)
        end
        onPlayerAdded(player)
    end)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    -- Spieler, die schon vor dem Start da waren (z. B. im Studio-Playtest).
    for _, player in Players:GetPlayers() do
        if RunService:IsStudio() then
            connectStudioHelper(player)
        end
        task.spawn(onPlayerAdded, player)
    end
end

return PlayerData
