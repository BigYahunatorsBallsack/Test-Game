--!strict
-- Sammlung, Sets, Bonus und Zonenbuch (Paket 2.6). Rein, ohne Roblox-API, Lune-Tests in
-- tests/collection.spec.luau.
--
-- Gespeichert wird nur `profile.finds` (Fundstück-ID -> Anzahl). Alles andere (Slots, Sets, Bonus,
-- Zonenbücher) wird bei jedem Aufruf aus der Tabelle `Finds` berechnet, so braucht ein Update der
-- Tabellen keine Migration. Unbekannte IDs im Profil bleiben gespeichert, zählen aber nicht.
--
-- Doppelte Funde werden sofort für ihren festen Wert verkauft (Entscheidung 18.11.2026): `record`
-- bucht ihn auf `profile.coins`.

local BigNum = require("./BigNum")
local Wind = require("./Wind")
local FindsData = require("../Data/Finds")
local CollectionData = require("../Data/Collection")

export type SetProgress = {
    setId: string,
    zoneId: string,
    index: number,
    have: number, -- gefundene Slots
    size: number,
    complete: boolean,
    bonusBp: number, -- Bonus dieses Sets, nur wenn es fertig ist
}

export type Recorded = {
    findId: string,
    zoneId: string,
    rarityId: string,
    isNew: boolean,
    count: number, -- Anzahl dieses Fundstücks nach dem Fund
    coins: BigNum.BigNum?, -- nur bei einem doppelten Fund: die verkauften Münzen
    setId: string,
    setHave: number,
    setSize: number,
    setCompleted: boolean, -- das Set wurde mit diesem Fund fertig
    zoneBookCompleted: boolean, -- das Zonenbuch wurde mit diesem Fund fertig
    bonusBpBefore: number,
    bonusBpAfter: number,
}

local Collection = {}

-- Obergrenze des Zählers pro Fundstück, damit er nie überläuft.
local MAX_COUNT = 2 ^ 31

-- Anzahl eines Fundstücks im Profil. Kaputte Werte zählen als 0.
function Collection.countOf(profile: any, findId: string): number
    local finds = profile.finds
    if type(finds) ~= "table" then
        return 0
    end
    local count = finds[findId]
    if type(count) ~= "number" or count ~= count or count < 1 or count == math.huge then
        return 0
    end
    return math.floor(count)
end

-- Fortschritt je Set (in der Reihenfolge von `Finds.sets`). `data` ist für Tests überschreibbar.
function Collection.progress(profile: any, data: any?): { SetProgress }
    local finds = if data and data.Finds then data.Finds else FindsData
    local bonuses = if data and data.Collection then data.Collection.setBonusBp else CollectionData.setBonusBp
    local have: { [string]: number } = {}
    for _, find in finds.list do
        if Collection.countOf(profile, find.id) > 0 then
            have[find.setId] = (have[find.setId] or 0) + 1
        end
    end
    local result: { SetProgress } = {}
    for _, findSet in finds.sets do
        local slots = have[findSet.id] or 0
        local complete = slots >= findSet.size
        table.insert(result, {
            setId = findSet.id,
            zoneId = findSet.zoneId,
            index = findSet.index,
            have = slots,
            size = findSet.size,
            complete = complete,
            bonusBp = if complete then (bonuses[findSet.index] or 0) else 0,
        })
    end
    return result
end

-- Summe der Boni aller fertigen Sets (Hundertstel-Prozent).
function Collection.bonusBp(profile: any, data: any?): number
    local total = 0
    for _, set in Collection.progress(profile, data) do
        total += set.bonusBp
    end
    return total
end

-- Faktor auf die Münzen pro Sand (1 = kein Bonus).
function Collection.bonusMultiplier(profile: any, data: any?): number
    return (10000 + Collection.bonusBp(profile, data)) / 10000
end

-- Welche Zonenbücher sind fertig (alle Sets der Zone fertig)? Zone-ID -> true.
function Collection.completedBooks(profile: any, data: any?): { [string]: boolean }
    local finds = if data and data.Finds then data.Finds else FindsData
    local complete: { [string]: number } = {}
    for _, set in Collection.progress(profile, data) do
        if set.complete then
            complete[set.zoneId] = (complete[set.zoneId] or 0) + 1
        end
    end
    local result: { [string]: boolean } = {}
    for zoneId, count in complete do
        if count >= finds.SETS_PER_ZONE then
            result[zoneId] = true
        end
    end
    return result
end

-- Wie viele verschiedene bekannte Fundstücke hat der Spieler?
function Collection.distinctFound(profile: any, data: any?): number
    local finds = if data and data.Finds then data.Finds else FindsData
    local total = 0
    for _, find in finds.list do
        if Collection.countOf(profile, find.id) > 0 then
            total += 1
        end
    end
    return total
end

-- Zustand für die Anzeige beim Client: Anzahl je bekanntem Fund (nur > 0), Bonus und Bücher.
function Collection.summary(profile: any, data: any?): any
    local finds = if data and data.Finds then data.Finds else FindsData
    local counts: { [string]: number } = {}
    for _, find in finds.list do
        local count = Collection.countOf(profile, find.id)
        if count > 0 then
            counts[find.id] = count
        end
    end
    local sets = Collection.progress(profile, data)
    local bonus = 0
    for _, set in sets do
        bonus += set.bonusBp
    end
    return {
        counts = counts,
        bonusBp = bonus,
        books = Collection.completedBooks(profile, data),
    }
end

-- Bucht einen Fund: Zähler +1; ist er schon bekannt, werden `value` Münzen gutgeschrieben (sofort
-- verkauft). Gibt nil zurück, wenn der Fund unbekannt ist. Ändert `profile.finds`, `profile.coins` und `profile.runEarned`.
function Collection.record(profile: any, findId: string, value: BigNum.BigNum, data: any?): Recorded?
    local finds = if data and data.Finds then data.Finds else FindsData
    local find = finds.byId[findId]
    if find == nil then
        return nil
    end
    local bonusBefore = Collection.bonusBp(profile, data)
    local booksBefore = Collection.completedBooks(profile, data)
    local before = Collection.countOf(profile, findId)
    if type(profile.finds) ~= "table" then
        profile.finds = {}
    end
    local count = math.min(before + 1, MAX_COUNT)
    profile.finds[findId] = count

    local coins: BigNum.BigNum? = nil
    if before > 0 then
        coins = value
        Wind.credit(profile, value) -- zählt auch für die Kristalle des nächsten Sturms
    end

    local setHave, setSize, setComplete = 0, 0, false
    for _, set in Collection.progress(profile, data) do
        if set.setId == find.setId then
            setHave, setSize, setComplete = set.have, set.size, set.complete
            break
        end
    end
    local bonusAfter = Collection.bonusBp(profile, data)
    local booksAfter = Collection.completedBooks(profile, data)
    return {
        findId = findId,
        zoneId = find.zoneId,
        rarityId = find.rarityId,
        isNew = before == 0,
        count = count,
        coins = coins,
        setId = find.setId,
        setHave = setHave,
        setSize = setSize,
        setCompleted = before == 0 and setComplete,
        zoneBookCompleted = booksAfter[find.zoneId] == true and booksBefore[find.zoneId] ~= true,
        bonusBpBefore = bonusBefore,
        bonusBpAfter = bonusAfter,
    }
end

return Collection
