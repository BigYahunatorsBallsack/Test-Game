--!strict
-- Soziales (Paket 5.7): Freunde-Bonus, Wochen-Rangliste und Sammlung besuchen. Rein, ohne Roblox-API,
-- Lune-Tests in tests/social.spec.luau. Die Services (Friends, Leaderboard) kümmern sich um DataStore,
-- Freundschaft und Namen und rufen hier nur Regeln auf.
--
-- Wert einer Sammlung = Summe der Wertfaktoren (Data/Rarities) aller VERSCHIEDENEN bekannten Fundstücke.
-- Doppelte zählen nicht, so lässt sich der Wert nicht durch Dauer-Farmen aufblasen.

local Collection = require("./Collection")
local Seasons = require("./Seasons")
local FindsData = require("../Data/Finds")
local RaritiesData = require("../Data/Rarities")
local SocialData = require("../Data/Social")

export type Data = { Social: any?, Finds: any?, Rarities: any?, Collection: any? }

local Social = {}

-- Höchster Wert, der je gespeichert oder angezeigt wird (Schutz vor kaputten Daten).
Social.MAX_VALUE = 1e9
-- Längster Name in einer Antwort.
Social.MAX_NAME_LENGTH = 50
-- Versionsmarke des Auszugs.
Social.SHOWCASE_VERSION = 1
-- Der 5. Januar 1970 war ein Montag: Ab hier zählen die Wochen.
local MONDAY_OFFSET = 4 * Seasons.SECONDS_PER_DAY
Social.MONDAY_OFFSET = MONDAY_OFFSET

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isWholeId(value: any): boolean
    return isFinite(value) and value >= 1 and value % 1 == 0 and value <= 2 ^ 53
end

local function socialOf(data: Data?): any
    if data ~= nil and data.Social ~= nil then
        return data.Social
    end
    return SocialData
end

local function findsOf(data: Data?): any
    if data ~= nil and data.Finds ~= nil then
        return data.Finds
    end
    return FindsData
end

local function raritiesOf(data: Data?): any
    if data ~= nil and data.Rarities ~= nil then
        return data.Rarities
    end
    return RaritiesData
end

-- Freunde-Faktor auf die Münzen: 1 + perFriendBp/10000 je Freund, höchstens 1 + maxBp/10000.
-- Kaputte Zahl, negativ oder NaN: 1.
function Social.bonusFactor(friendCount: any, data: Data?): number
    local cfg = socialOf(data).friends
    if not isFinite(friendCount) or friendCount < 1 or type(cfg) ~= "table" then
        return 1
    end
    if not isFinite(cfg.perFriendBp) or cfg.perFriendBp < 0 or not isFinite(cfg.maxBp) or cfg.maxBp < 0 then
        return 1
    end
    local bp = math.min(math.floor(friendCount) * cfg.perFriendBp, cfg.maxBp)
    return 1 + bp / 10000
end

-- Wie viele der anwesenden Spieler sind Freunde von `selfId`? `known[userId] == true` heißt befreundet.
-- Man zählt sich nie selbst, jede UserId nur einmal, nur Anwesende.
function Social.countFriends(selfId: any, presentIds: any, known: any): number
    if type(presentIds) ~= "table" or type(known) ~= "table" then
        return 0
    end
    local seen: { [any]: boolean } = {}
    local count = 0
    for _, userId in presentIds do
        if userId ~= selfId and not seen[userId] and known[userId] == true then
            seen[userId] = true
            count += 1
        end
    end
    return count
end

-- Soll der Wert jetzt in den Speicher der Woche geschrieben werden? Nur mit Wert über 0, und nur wenn er
-- gestiegen ist oder die Woche (der Speichername) gewechselt hat: Eine Sitzung über Montag 0 Uhr schreibt
-- ihren Wert so auch in die neue Woche.
function Social.shouldWrite(value: any, writtenValue: any, writtenStoreName: any, storeName: any): boolean
    if not isFinite(value) or value <= 0 or type(storeName) ~= "string" then
        return false
    end
    if writtenStoreName ~= storeName then
        return true
    end
    return not isFinite(writtenValue) or value > writtenValue
end

-- Wert einer Sammlung aus einem Profil (nur `finds`).
function Social.collectionValue(profile: any, data: Data?): number
    local rarities = raritiesOf(data)
    local total = 0
    for _, find in findsOf(data).list do
        if Collection.countOf(profile, find.id) > 0 then
            local rarity = rarities.byId[find.rarityId]
            if rarity ~= nil and isFinite(rarity.valueFactor) and rarity.valueFactor > 0 then
                total += rarity.valueFactor
            end
        end
    end
    return math.min(math.floor(total), Social.MAX_VALUE) -- der OrderedDataStore nimmt nur ganze Zahlen
end

-- Wochenindex (Woche von Montag 0 Uhr UTC bis Montag 0 Uhr UTC, Ende ausschließend). Kaputte Zeit: nil.
function Social.weekIndex(unixNow: any): number?
    if not isFinite(unixNow) or unixNow < MONDAY_OFFSET then
        return nil
    end
    return math.floor((unixNow - MONDAY_OFFSET) / Seasons.WEEK_SECONDS)
end

-- Sekunden bis zum Ende der Woche (nächster Montag 0 Uhr UTC), ab 1. Kaputte Zeit: 0.
function Social.secondsLeftInWeek(unixNow: any): number
    local week = Social.weekIndex(unixNow)
    if week == nil then
        return 0
    end
    return MONDAY_OFFSET + (week + 1) * Seasons.WEEK_SECONDS - math.floor(unixNow)
end

-- Name des OrderedDataStore dieser Woche. nil bei kaputter Zeit.
function Social.weekStoreName(unixNow: any, isStudio: boolean, data: Data?): string?
    local week = Social.weekIndex(unixNow)
    if week == nil then
        return nil
    end
    local cfg = socialOf(data).leaderboard
    return `{cfg.store}{if isStudio then cfg.studioSuffix else ""}_{week}`
end

-- Name des Auszug-Speichers.
function Social.showcaseStoreName(isStudio: boolean, data: Data?): string
    local cfg = socialOf(data).leaderboard
    return `{cfg.showcaseStore}{if isStudio then cfg.studioSuffix else ""}`
end

-- Säubert die Roh-Einträge der Rangliste ({ userId, value } oder { key, value }): nur ganze UserIds,
-- endliche Werte über 0, jede UserId einmal, absteigend nach Wert, höchstens topCount. Ergebnis:
-- Liste { rank, userId, value }.
function Social.cleanEntries(raw: any, data: Data?): { { rank: number, userId: number, value: number } }
    local result: { { rank: number, userId: number, value: number } } = {}
    if type(raw) ~= "table" then
        return result
    end
    local seen: { [number]: boolean } = {}
    for _, entry in raw do
        if type(entry) == "table" then
            local userId = entry.userId
            if userId == nil and type(entry.key) == "string" then
                userId = tonumber(entry.key)
            end
            local value = entry.value
            if isWholeId(userId) and not seen[userId] and isFinite(value) and value > 0 then
                seen[userId] = true
                table.insert(result, { rank = 0, userId = userId, value = math.min(math.floor(value), Social.MAX_VALUE) })
            end
        end
    end
    table.sort(result, function(a, b)
        if a.value ~= b.value then
            return a.value > b.value
        end
        return a.userId < b.userId
    end)
    local limit = socialOf(data).leaderboard.topCount
    while #result > limit do
        table.remove(result)
    end
    for index, entry in result do
        entry.rank = index
    end
    return result
end

-- Öffentlicher Auszug einer Sammlung: nur die IDs der besessenen bekannten Fundstücke, in der
-- Reihenfolge der Tabelle. `t` ist die Server-Zeit.
function Social.buildShowcase(profile: any, unixNow: any, data: Data?): { v: number, t: number, owned: { string } }
    local owned: { string } = {}
    for _, find in findsOf(data).list do
        if Collection.countOf(profile, find.id) > 0 then
            table.insert(owned, find.id)
        end
    end
    return { v = Social.SHOWCASE_VERSION, t = if isFinite(unixNow) then math.floor(unixNow) else 0, owned = owned }
end

-- Liest einen gespeicherten Auszug: nur bekannte IDs, jede einmal, nie mehr als der Katalog. Alles andere
-- (kein Auszug, falsche Version) ergibt nil.
function Social.cleanShowcase(raw: any, data: Data?): { [string]: boolean }?
    if type(raw) ~= "table" or raw.v ~= Social.SHOWCASE_VERSION or type(raw.owned) ~= "table" then
        return nil
    end
    local finds = findsOf(data)
    local owned: { [string]: boolean } = {}
    for _, id in raw.owned do
        if type(id) == "string" and finds.byId[id] ~= nil then
            owned[id] = true
        end
    end
    return owned
end

local function cleanName(name: any): string
    if type(name) ~= "string" then
        return "?"
    end
    return string.sub(name, 1, Social.MAX_NAME_LENGTH)
end

Social.cleanName = cleanName

-- Säubert die Freundesliste, die der Server von Roblox bekommt (Einträge { Id, Username, DisplayName }):
-- nur ganze UserIds, jede einmal, Namen gekürzt, höchstens maxFriends. Ergebnis { userId, name }.
function Social.cleanFriends(raw: any, data: Data?): { { userId: number, name: string } }
    local result: { { userId: number, name: string } } = {}
    if type(raw) ~= "table" then
        return result
    end
    local limit = socialOf(data).leaderboard.maxFriends
    local seen: { [number]: boolean } = {}
    for _, entry in raw do
        if #result >= limit then
            break
        end
        if type(entry) == "table" and isWholeId(entry.Id) and not seen[entry.Id] then
            seen[entry.Id] = true
            local name = if type(entry.DisplayName) == "string" and entry.DisplayName ~= "" then entry.DisplayName else entry.Username
            table.insert(result, { userId = entry.Id, name = cleanName(name) })
        end
    end
    return result
end

-- Der Besuch nennt nie einen Spieler, sondern einen Platz in der Liste, die der Server selbst
-- aufgebaut hat (Freunde des Besuchers). Ergebnis der Eintrag oder nil bei jedem ungültigen Platz.
function Social.friendAt(list: any, slot: any, data: Data?): { userId: number, name: string }?
    if type(list) ~= "table" or not isFinite(slot) or slot < 1 or slot % 1 ~= 0 or slot > socialOf(data).leaderboard.maxFriends then
        return nil
    end
    local entry = list[slot]
    if type(entry) ~= "table" or not isWholeId(entry.userId) then
        return nil
    end
    return entry
end

-- Anzeigeform für den Besuch: Name, Wert, Anzahl und die Liste der besessenen IDs, dazu Set-Fortschritt.
-- Nur Texte, Zahlen und Wahrheitswerte, nichts Schreibendes.
function Social.view(owned: { [string]: boolean }, name: any, data: Data?): { [string]: any }
    local finds = findsOf(data)
    local fake = { finds = {} :: { [string]: number } }
    local ids: { string } = {}
    for _, find in finds.list do
        if owned[find.id] == true then
            fake.finds[find.id] = 1
            table.insert(ids, find.id)
        end
    end
    local sets = {}
    for _, progress in Collection.progress(fake, data) do
        table.insert(sets, { setId = progress.setId, have = progress.have, size = progress.size, complete = progress.complete })
    end
    return {
        name = cleanName(name),
        value = Social.collectionValue(fake, data),
        found = #ids,
        total = #finds.list,
        owned = ids,
        sets = sets,
    }
end

return Social
