--!strict
-- Leaderboard-Service (Paket 5.7): Wochen-Rangliste der wertvollsten Sammlung und Besuch der Sammlung
-- eines Freundes. Die Regeln stehen im reinen Modul Logic/Social (Lune-Tests tests/social.spec.luau),
-- Werte in Data/Social. Hier hängen nur DataStore, Freundesliste, Namen und die Remotes dran.
--
-- Rangliste: Der Wert einer Sammlung (Logic/Social.collectionValue) wird höchstens alle
-- `writeSeconds` je Spieler und beim Verlassen in einen OrderedDataStore der Woche geschrieben (nur
-- steigend, UpdateAsync mit Maximum). Alle `readSeconds` liest der Server die Top-Liste neu in einen
-- Zwischenspeicher. Der Client fragt nur diesen Speicher ab.
-- Auszug: Mit dem Wert schreibt der Server einen kleinen öffentlichen Auszug (nur IDs der Fundstücke)
-- in einen DataStore. Gelesen wird er nur über ViewCollection, und nur für Freunde.
--
-- Remotes (alle RemoteFunction, Schema und Limit in RemoteSpec; der Client nennt nie einen Spieler):
--   GetLeaderboard()      -> { ok = true, week, secondsLeft, entries = { { rank, name, value, you } }, you = { value, rank? } }
--                            oder { ok = false, reason }
--   GetFriends()          -> { ok = true, friends = { { slot, name } } } oder { ok = false, reason }
--   ViewCollection(slot)  -> { ok = true, view } oder { ok = false, reason }
--                            reason: notFriend, noShowcase, busy, error
-- Ein Fehler in DataStore oder Roblox-Diensten bleibt hier (pcall) und stört weder Sammeln noch
-- Verkaufen noch Speichern. In Studio haben die Speicher einen eigenen Namen (Data/Social.studioSuffix).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Takt, der Werte prüft und fällige Schreibvorgänge startet (Sekunden).
local TICK_SECONDS = 5
-- Name, den die Rangliste zeigt, wenn Roblox keinen liefert.
local FALLBACK_NAME = "Spieler"
-- Höchstzahl Seiten, die GetFriendsAsync gelesen werden (je Seite bis zu 200 Freunde).
local MAX_FRIEND_PAGES = 3
-- So lange gilt ein gelesener Auszug eines Freundes (Sekunden).
local SHOWCASE_CACHE_SECONDS = 60
-- Ab so vielen gemerkten Auszügen werden abgelaufene gelöscht.
local MAX_SHOWCASES = 200
-- Reserve im DataStore-Budget: darunter lesen und schreiben wir nicht, ProfileStore hat Vorrang.
local BUDGET_RESERVE = 30
-- Höchstens so viele Auszug-Lesevorgänge (Cache-Fehlschläge) je Spieler und Minute.
local SHOWCASE_READS_PER_MINUTE = 6
-- Mindestabstand zwischen zwei Warnungen zum DataStore (Sekunden).
local WARN_INTERVAL_SECONDS = 60
-- So lange wartet das Schreiben beim Verlassen auf einen laufenden Schreibvorgang (Sekunden).
local FLUSH_WAIT_SECONDS = 5
-- Kurze Pause zwischen zwei Namensabfragen (Sekunden), schont die Rate.
local NAME_PAUSE_SECONDS = 0.2

local IS_STUDIO = RunService:IsStudio()

local shared = ReplicatedStorage:WaitForChild("Shared")
local SocialLogic = require(shared:WaitForChild("Logic"):WaitForChild("Social") :: ModuleScript) :: any
local SocialData = require(shared:WaitForChild("Data"):WaitForChild("Social") :: ModuleScript) :: any

local servicesFolder = script.Parent
local PlayerData: any = nil
local Net: any = nil

local Leaderboard = {}

type Pending = { value: number, showcase: any }

-- Zuletzt berechneter Wert je Spieler (mit Auszug), zuletzt geschriebener Wert und Zeitpunkt.
local latest: { [number]: Pending } = {}
local writtenValue: { [number]: number } = {}
local writtenAt: { [number]: number } = {}
local writing: { [number]: boolean } = {}
-- Zwischenspeicher der Rangliste.
local board: { weekName: string?, entries: { any }, readAt: number } = { weekName = nil, entries = {}, readAt = 0 }
local names: { [number]: string } = {}
-- Freundesliste je Spieler (vom Server gebaut), Auszüge anderer Spieler.
local friendLists: { [Player]: { at: number, list: { any } } } = {}
local busy: { [Player]: boolean } = {}
local showcaseCache: { [number]: { at: number, owned: any } } = {}
local lastWarnAt = -math.huge
local writtenStore: { [number]: string } = {}
local showcaseReads: { [Player]: { number } } = {}

local function log(message: string)
    warn(`[Leaderboard] {message}`)
end

local function unixNow(): number
    return os.time()
end

local function warnStoreOnce(err: any)
    if os.clock() - lastWarnAt >= WARN_INTERVAL_SECONDS then
        lastWarnAt = os.clock()
        log(`DataStore-Fehler (Rangliste oder Besuch): {tostring(err)}`)
    end
end

-- Wert und Auszug des Spielers neu berechnen. Wartet nie.
local function refreshLatest(player: Player)
    local profile = PlayerData.get(player)
    if profile == nil or not PlayerData.isActive(player.UserId) then
        return
    end
    local ok, value = pcall(SocialLogic.collectionValue, profile)
    if not ok or type(value) ~= "number" then
        return
    end
    local old = latest[player.UserId]
    if old ~= nil and old.value == value then
        return
    end
    local built, showcase = pcall(SocialLogic.buildShowcase, profile, unixNow())
    if built then
        latest[player.UserId] = { value = value, showcase = showcase }
    end
end

-- Schreibt Wert und Auszug eines Spielers (wartet auf Roblox). Nur, wenn der Wert größer ist als der
-- zuletzt geschriebene.
local function flush(userId: number)
    local pending = latest[userId]
    if pending == nil or pending.value <= 0 or writing[userId] then
        return
    end
    local storeName = SocialLogic.weekStoreName(unixNow(), IS_STUDIO)
    if storeName == nil then
        return
    end
    -- Neue Woche: der zuletzt geschriebene Wert gehört zur alten Woche und zählt nicht mehr.
    if not SocialLogic.shouldWrite(pending.value, writtenValue[userId], writtenStore[userId], storeName) then
        return
    end
    if DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync) < BUDGET_RESERVE then
        return -- zu knapp: im nächsten Takt wieder, ProfileStore hat Vorrang
    end
    writing[userId] = true
    writtenAt[userId] = os.clock() -- auch bei einem Fehler: höchstens ein Versuch je writeSeconds
    local value = pending.value
    local ok, err = pcall(function()
        local ordered = DataStoreService:GetOrderedDataStore(storeName)
        ordered:UpdateAsync(tostring(userId), function(old: any): any
            if type(old) == "number" and old >= value then
                return nil -- nie senken
            end
            return value
        end)
        local showcase = DataStoreService:GetDataStore(SocialLogic.showcaseStoreName(IS_STUDIO))
        showcase:SetAsync(tostring(userId), pending.showcase)
    end)
    writing[userId] = nil
    if ok then
        if Players:GetPlayerByUserId(userId) ~= nil then -- nicht für einen Spieler, der inzwischen weg ist
            writtenValue[userId] = value
            writtenStore[userId] = storeName
        end
    else
        warnStoreOnce(err)
    end
end

local function tickWrites()
    local interval = SocialData.leaderboard.writeSeconds
    for _, player in Players:GetPlayers() do
        refreshLatest(player)
        local at = writtenAt[player.UserId]
        if at == nil or os.clock() - at >= interval then
            task.spawn(flush, player.UserId)
        end
    end
end

-- Name zu einer UserId (gemerkt). Wartet auf Roblox.
local function nameOf(userId: number): string
    local known = names[userId]
    if known ~= nil then
        return known
    end
    local ok, result = pcall(function(): string
        return Players:GetNameFromUserIdAsync(userId)
    end)
    local name = if ok and type(result) == "string" then SocialLogic.cleanName(result) else FALLBACK_NAME
    if ok then
        names[userId] = name
    end
    task.wait(NAME_PAUSE_SECONDS)
    return name
end

-- Liest die Top-Liste der Woche neu in den Zwischenspeicher.
local function readBoard()
    local storeName = SocialLogic.weekStoreName(unixNow(), IS_STUDIO)
    if storeName == nil then
        return
    end
    local ok, raw = pcall(function(): any
        local ordered = DataStoreService:GetOrderedDataStore(storeName)
        local pages = ordered:GetSortedAsync(false, SocialData.leaderboard.topCount)
        return pages:GetCurrentPage()
    end)
    if not ok then
        warnStoreOnce(raw)
        return
    end
    local clean = SocialLogic.cleanEntries(raw)
    for _, entry in clean do
        entry.name = nameOf(entry.userId)
    end
    board = { weekName = storeName, entries = clean, readAt = os.clock() }
end

-- Eigener Rang, wenn der Spieler in der Top-Liste steht.
local function rankOf(userId: number): number?
    for _, entry in board.entries do
        if entry.userId == userId then
            return entry.rank
        end
    end
    return nil
end

local function onGetLeaderboard(player: Player): any
    local profile = PlayerData.get(player)
    if profile == nil then
        return { ok = false, reason = "error" }
    end
    local ok, result = pcall(function(): any
        local now = unixNow()
        local week = SocialLogic.weekIndex(now)
        if week == nil then
            return { ok = false, reason = "error" }
        end
        local entries = {}
        for _, entry in board.entries do
            table.insert(entries, { rank = entry.rank, name = entry.name or FALLBACK_NAME, value = entry.value, you = entry.userId == player.UserId })
        end
        return {
            ok = true,
            week = week,
            secondsLeft = SocialLogic.secondsLeftInWeek(now),
            entries = entries,
            you = { value = SocialLogic.collectionValue(profile), rank = rankOf(player.UserId) },
        }
    end)
    if not ok then
        log(`GetLeaderboard für {player.Name} fehlgeschlagen: {tostring(result)}`)
        return { ok = false, reason = "error" }
    end
    return result
end

-- Freundesliste des Spielers von Roblox holen (wartet).
local function fetchFriends(player: Player): { any }?
    local ok, raw = pcall(function(): { any }
        local pages = Players:GetFriendsAsync(player.UserId)
        local collected: { any } = {}
        local limit = SocialData.leaderboard.maxFriends
        for _ = 1, MAX_FRIEND_PAGES do
            for _, item in pages:GetCurrentPage() do
                table.insert(collected, item)
            end
            if pages.IsFinished or #collected >= limit then
                break
            end
            pages:AdvanceToNextPageAsync()
        end
        return collected
    end)
    if not ok then
        log(`Freundesliste für {player.Name} nicht lesbar: {tostring(raw)}`)
        return nil
    end
    return SocialLogic.cleanFriends(raw)
end

local function onGetFriends(player: Player): any
    if busy[player] then
        return { ok = false, reason = "busy" }
    end
    local cached = friendLists[player]
    if cached == nil or os.clock() - cached.at >= SocialData.leaderboard.friendCacheSeconds then
        busy[player] = true
        local list = fetchFriends(player)
        busy[player] = nil
        if list == nil then
            return { ok = false, reason = "error" }
        end
        cached = { at = os.clock(), list = list }
        if player.Parent ~= nil then -- ein Spieler, der gegangen ist, bekommt keinen Eintrag mehr
            friendLists[player] = cached
        end
    end
    local friends = {}
    for slot, entry in (cached :: any).list do
        table.insert(friends, { slot = slot, name = entry.name })
    end
    return { ok = true, friends = friends }
end

-- Hält den Zwischenspeicher der Auszüge klein: abgelaufene Einträge fliegen raus.
local function pruneShowcases()
    local count = 0
    for _ in showcaseCache do
        count += 1
    end
    if count <= MAX_SHOWCASES then
        return
    end
    local now = os.clock()
    for userId, entry in showcaseCache do
        if now - entry.at >= SHOWCASE_CACHE_SECONDS then
            showcaseCache[userId] = nil
        end
    end
end

-- Grenze für Cache-Fehlschläge: je Spieler höchstens SHOWCASE_READS_PER_MINUTE, und nur mit Restbudget.
local function allowShowcaseRead(player: Player): boolean
    if DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) < BUDGET_RESERVE then
        return false
    end
    local now = os.clock()
    local times = showcaseReads[player] or {}
    local recent = {}
    for _, at in times do
        if now - at < 60 then
            table.insert(recent, at)
        end
    end
    if #recent >= SHOWCASE_READS_PER_MINUTE then
        showcaseReads[player] = recent
        return false
    end
    table.insert(recent, now)
    showcaseReads[player] = recent
    return true
end

local function onViewCollection(player: Player, slot: any): any
    local cached = friendLists[player]
    -- Eine abgelaufene Liste gilt nicht mehr (wer entfreundet wurde, ist nicht mehr ansehbar).
    if cached == nil or os.clock() - cached.at >= SocialData.leaderboard.friendCacheSeconds then
        return { ok = false, reason = "notFriend" }
    end
    local entry = SocialLogic.friendAt(cached.list, slot)
    if entry == nil then
        return { ok = false, reason = "notFriend" }
    end
    if busy[player] then
        return { ok = false, reason = "busy" }
    end
    busy[player] = true
    local ok, result = pcall(function(): any
        local userId = entry.userId
        local known = showcaseCache[userId]
        if known == nil or os.clock() - known.at >= SHOWCASE_CACHE_SECONDS then
            if not allowShowcaseRead(player) then
                return { ok = false, reason = "busy" }
            end
            local store = DataStoreService:GetDataStore(SocialLogic.showcaseStoreName(IS_STUDIO))
            local raw = store:GetAsync(tostring(userId))
            known = { at = os.clock(), owned = SocialLogic.cleanShowcase(raw) }
            showcaseCache[userId] = known
            pruneShowcases()
        end
        if known.owned == nil then
            return { ok = false, reason = "noShowcase" }
        end
        return { ok = true, view = SocialLogic.view(known.owned, entry.name) }
    end)
    busy[player] = nil
    if not ok then
        warnStoreOnce(result)
        return { ok = false, reason = "error" }
    end
    return result
end

function Leaderboard.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Leaderboard.Start()
    Net.on("GetLeaderboard", onGetLeaderboard)
    Net.on("GetFriends", onGetFriends)
    Net.on("ViewCollection", onViewCollection)

    Players.PlayerRemoving:Connect(function(player: Player)
        local userId = player.UserId
        friendLists[player] = nil
        busy[player] = nil
        showcaseReads[player] = nil
        task.spawn(function()
            -- Läuft gerade ein Schreibvorgang, kurz warten, dann den letzten Stand schreiben.
            local deadline = os.clock() + FLUSH_WAIT_SECONDS
            while writing[userId] and os.clock() < deadline do
                task.wait(0.25)
            end
            pcall(flush, userId)
            latest[userId] = nil
            writtenValue[userId] = nil
            writtenAt[userId] = nil
            writtenStore[userId] = nil
        end)
    end)

    task.spawn(function()
        while true do
            local ok, err = pcall(tickWrites)
            if not ok then
                log(`Takt fehlgeschlagen: {tostring(err)}`)
            end
            task.wait(TICK_SECONDS)
        end
    end)
    task.spawn(function()
        while true do
            local ok, err = pcall(readBoard)
            if not ok then
                log(`Lesen der Rangliste fehlgeschlagen: {tostring(err)}`)
            end
            task.wait(SocialData.leaderboard.readSeconds)
        end
    end)
end

return Leaderboard
