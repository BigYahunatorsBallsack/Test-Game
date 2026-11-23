--!strict
-- Friends-Service (Paket 5.7): Freunde-Bonus.
-- Der Server zählt, wie viele Spieler im selben Server mit dem Spieler befreundet sind
-- (`Player:IsFriendsWith`, je Paar einmal geprüft und gemerkt). Aus der Zahl macht Logic/Social den
-- Münz-Faktor (10 % je Freund, höchstens 50 %, Data/Social). Den Faktor übernimmt Sand
-- (`Sand.setFriendFactor`): Er gilt beim Verkauf, in der Anzeige und bei den Sandsturm-Münzen (Upgrades
-- nutzt Sand.optionsFor), nicht beim Offline-Ertrag.
-- Der Client sendet nichts. Ein Fehler bei der Freundschaftsprüfung ändert den Faktor nicht (kein Freund).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local SocialLogic = require(shared:WaitForChild("Logic"):WaitForChild("Social") :: ModuleScript) :: any

local servicesFolder = script.Parent
local Sand: any = nil

local Friends = {}

-- Geprüfte Paare: friendOf[userIdA][userIdB] = true/false (immer in beide Richtungen eingetragen).
local friendOf: { [number]: { [number]: boolean } } = {}

local function log(message: string)
    warn(`[Friends] {message}`)
end

-- Anzahl der Freunde, die gerade im Server sind.
local function countFor(player: Player): number
    local present = {}
    for _, other in Players:GetPlayers() do
        table.insert(present, other.UserId)
    end
    return SocialLogic.countFriends(player.UserId, present, friendOf[player.UserId])
end

local function apply(player: Player)
    if player.Parent == nil then
        return
    end
    local ok, err = pcall(Sand.setFriendFactor, player, SocialLogic.bonusFactor(countFor(player)))
    if not ok then
        log(`Faktor für {player.Name} nicht gesetzt: {tostring(err)}`)
    end
end

-- Prüft ein Paar (wartet auf Roblox) und aktualisiert beide Faktoren.
local function checkPair(a: Player, b: Player)
    local ok, result = pcall(function(): boolean
        return a:IsFriendsWith(b.UserId)
    end)
    if not ok then
        log(`Freundschaft {a.Name}/{b.Name} nicht prüfbar: {tostring(result)}`)
        return
    end
    if a.Parent == nil or b.Parent == nil then
        return -- einer ist inzwischen gegangen: kein Eintrag für ihn anlegen
    end
    friendOf[a.UserId] = friendOf[a.UserId] or {}
    friendOf[b.UserId] = friendOf[b.UserId] or {}
    friendOf[a.UserId][b.UserId] = result == true
    friendOf[b.UserId][a.UserId] = result == true
    apply(a)
    apply(b)
end

local function onPlayerAdded(player: Player)
    for _, other in Players:GetPlayers() do
        if other ~= player then
            local known = friendOf[player.UserId]
            if known == nil or known[other.UserId] == nil then
                task.spawn(checkPair, player, other)
            else
                apply(player)
                apply(other)
            end
        end
    end
end

local function onPlayerRemoving(player: Player)
    friendOf[player.UserId] = nil
    for userId, known in friendOf do
        known[player.UserId] = nil
        local other = Players:GetPlayerByUserId(userId)
        if other ~= nil then
            task.defer(apply, other)
        end
    end
end

function Friends.Init()
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
end

function Friends.Start()
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayerAdded, player)
    end
end

return Friends
