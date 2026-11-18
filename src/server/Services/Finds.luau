--!strict
-- Finds-Service (Paket 2.6)
-- Zuständig: Fundstücke auswürfeln, in die Sammlung buchen, doppelte Funde sofort verkaufen und
-- Meldungen an den Client schicken.
--
-- Die Regeln stehen in den reinen Modulen Logic/FindRoll (Chance, Seltenheit, Auswahl, Wert) und
-- Logic/Collection (Sammlung, Sets, Bonus, Buchung), beide mit Lune-Tests. Hier hängen nur
-- Zeit, Zufall, Profil und Remotes dran.
--
-- Der Client sendet nichts: Funde entstehen allein aus der Sammelzeit, die der Server in
-- Collecting.update misst (Sand floss wirklich in den Tank). Es gibt darum keine Remote vom
-- Client zum Server. Das Wetter liest der Server aus seiner eigenen Zeit (GetServerTimeNow).
--
-- Studio-Hilfe (nur in Studio, in der Befehlszeile der Ansicht "Server"): Am Spieler das Attribut "DebugFindSet" auf eine Set-ID setzen
-- (z. B. "dunes_set_1") oder "DebugFindZone" auf eine Zonen-ID (z. B. "oasis"), dann trägt der
-- Server alle Fundstücke dieses Sets oder der Zone in die Sammlung ein.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wie oft der Server die gesammelte Zeit würfelt (s). Gleich wie der Sand-Tick.
local TICK_SECONDS = 0.25
-- Mehr Sammelzeit pro Zone und Tick zählt nie (Schutz gegen Ausreißer, z. B. nach einem Hänger).
local MAX_SECONDS_PER_TICK = 10
local DEBUG_SET_ATTRIBUTE = "DebugFindSet"
local DEBUG_ZONE_ATTRIBUTE = "DebugFindZone"

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local FindRoll = loadShared("Logic", "FindRoll")
local Collection = loadShared("Logic", "Collection")
local BigNum = loadShared("Logic", "BigNum")
local FindsData = loadShared("Data", "Finds")

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local Net: any = nil

local Finds = {}

local random = Random.new()
-- Sammelzeit dieser Sitzung je Spieler (für "Erster Fund sicher").
local sessionSeconds: { [Player]: number } = {}

local function serverTime(): number
    return workspace:GetServerTimeNow()
end

-- Schickt dem Spieler die ganze Sammlung zur Anzeige.
local function syncCollection(player: Player)
    local profile = PlayerData.get(player)
    if profile == nil then
        return
    end
    Net.fire(player, "CollectionSync", Collection.summary(profile))
end

-- Bucht einen Fund und meldet ihn dem Spieler.
local function award(player: Player, profile: any, roll: any, zoneId: string)
    local recorded = Collection.record(profile, roll.find.id, roll.value)
    if recorded == nil then
        return
    end
    Net.fire(player, "Notify", {
        kind = "find",
        findId = recorded.findId,
        zoneId = zoneId,
        rarityId = recorded.rarityId,
        isNew = recorded.isNew,
        count = recorded.count,
        coins = if recorded.coins ~= nil then BigNum.serialize(recorded.coins) else nil,
        setId = recorded.setId,
        setHave = recorded.setHave,
        setSize = recorded.setSize,
        setCompleted = recorded.setCompleted,
        zoneBookCompleted = recorded.zoneBookCompleted,
        bonusBp = recorded.bonusBpAfter,
    })
    syncCollection(player)
    Sand.refresh(player) -- Münzen aus einem Duplikat und der neue Preis mit Bonus
end

-- Würfelt die gesammelte Zeit eines Spielers.
local function tickPlayer(player: Player)
    local profile = PlayerData.get(player)
    if profile == nil then
        return
    end
    local taken = Sand.takeFindSeconds(player)
    for zoneId, seconds in taken do
        local clamped = math.min(seconds, MAX_SECONDS_PER_TICK)
        local total = (sessionSeconds[player] or 0) + clamped
        sessionSeconds[player] = total
        local roll = FindRoll.roll({
            profile = profile,
            zoneId = zoneId,
            seconds = clamped,
            serverTime = serverTime(),
            sessionSeconds = total,
            random = function(): number
                return random:NextNumber()
            end,
        })
        if roll ~= nil then
            award(player, profile, roll, zoneId)
        end
    end
end

local function tick()
    for _, player in Players:GetPlayers() do
        local ok, err = pcall(tickPlayer, player)
        if not ok then
            warn(`[Finds] Fehler beim Würfeln für {player.Name}: {tostring(err)}`)
        end
    end
end

-- Studio-Hilfe: füllt ein Set oder eine Zone in der Sammlung.
local function connectStudioHelper(player: Player)
    local function apply(attribute: string)
        local value = player:GetAttribute(attribute)
        local profile = PlayerData.get(player)
        if type(value) ~= "string" or profile == nil then
            return
        end
        local added = 0
        for _, find in FindsData.list do
            local matches = if attribute == DEBUG_SET_ATTRIBUTE then find.setId == value else find.zoneId == value
            if matches and Collection.countOf(profile, find.id) == 0 then
                profile.finds[find.id] = 1
                added += 1
            end
        end
        print(`[Finds] Studio: {player.Name} {attribute} = {value}, {added} Fundstücke eingetragen`)
        syncCollection(player)
        Sand.refresh(player)
    end
    for _, attribute in { DEBUG_SET_ATTRIBUTE, DEBUG_ZONE_ATTRIBUTE } do
        player:GetAttributeChangedSignal(attribute):Connect(function()
            apply(attribute)
        end)
    end
end

function Finds.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Finds.Start()
    PlayerData.onLoaded(function(player: Player, _profile: any)
        sessionSeconds[player] = 0
        syncCollection(player)
    end)
    local function onAdded(player: Player)
        if RunService:IsStudio() then
            connectStudioHelper(player)
        end
    end
    for _, player in Players:GetPlayers() do
        onAdded(player)
    end
    Players.PlayerAdded:Connect(onAdded)
    Players.PlayerRemoving:Connect(function(player: Player)
        sessionSeconds[player] = nil
    end)

    task.spawn(function()
        while true do
            task.wait(TICK_SECONDS)
            tick()
        end
    end)
end

return Finds
