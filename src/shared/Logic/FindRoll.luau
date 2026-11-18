--!strict
-- Fundstücke auswürfeln (Paket 2.6). Rein, ohne Roblox-API, Lune-Tests in tests/findroll.spec.luau.
--
-- Der Server ruft `roll` mit der echten Sammelzeit auf (Sekunden, in denen Sand in den Tank floss).
-- Der Zufall kommt als Funktion `random() -> [0, 1)` herein, damit Tests feste Werte nutzen können.
--
--  1. Chance pro Sekunde = findChancePerSecond x Zonenfaktor x Glück-Ast x (1 + Wetter-Bonus).
--  2. Chance im Fenster  = 1 - (1 - p)^Sekunden (höchstens ein Fund pro Aufruf).
--  3. Seltenheit nach der Quotentabelle der Zone. Glück ändert nur die Chance, nie die Verteilung.
--  4. Fundstück gleich verteilt unter den Funden der Zone mit dieser Seltenheit (fehlt sie, die
--     nächst tiefere Stufe).
--  5. Wert = findBaseValue x Sandfaktor x Grundrate des Werkzeugs x Wertfaktor der Seltenheit
--     x Windkristall-Faktor (Paket 2.7), beim Fund festgeschrieben. Kein Knoten-Bonus, damit
--     Horten sich nicht lohnt.
--  6. Erster Fund sicher: noch kein bekannter Fund und genug Sitzungssekunden, dann ein
--     Gewöhnlicher Fund.

local BigNum = require("./BigNum")
local Collection = require("./Collection")
local TreeEffects = require("./TreeEffects")
local Wind = require("./Wind")
local WeatherLogic = require("./Weather")
local FindOddsData = require("../Data/FindOdds")
local FindsData = require("../Data/Finds")
local RaritiesData = require("../Data/Rarities")
local SandTypesData = require("../Data/SandTypes")
local ZonesData = require("../Data/Zones")

export type Roll = {
    find: any, -- Eintrag aus Data/Finds
    rarityId: string,
    value: BigNum.BigNum, -- fester Wert in Münzen
    forced: boolean, -- kam durch "Erster Fund sicher"
}

export type Input = {
    profile: any,
    zoneId: string,
    seconds: number, -- echte Sammelzeit seit dem letzten Aufruf
    serverTime: number, -- Serverzeit für das Wetter
    sessionSeconds: number, -- Sammelzeit dieser Sitzung (inklusive `seconds`)
    random: () -> number,
}

local FindRoll = {}

local function isGoodNumber(value: any): boolean
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Chance pro Sekunde in [0, 1]. `data` ist für Tests überschreibbar.
function FindRoll.chancePerSecond(profile: any, zoneId: string, serverTime: number, data: any?): number
    local odds = if data and data.FindOdds then data.FindOdds else FindOddsData
    local zoneFactor = (odds.zoneFindChanceFactor[zoneId] or 0) / 10000
    local weather = WeatherLogic.stateAt(zoneId, serverTime, if data and data.Weather then data.Weather else nil)
    local weatherFactor = 1 + weather.findChanceBonusBp * weather.strength / 10000
    local p = (odds.findChancePerSecond / 10000) * zoneFactor * TreeEffects.luckMultiplier(profile) * weatherFactor
    if not isGoodNumber(p) then
        return 0
    end
    return math.clamp(p, 0, 1)
end

-- Chance auf mindestens einen Fund in `seconds` Sekunden.
function FindRoll.chanceInWindow(perSecond: number, seconds: number): number
    if not isGoodNumber(perSecond) or not isGoodNumber(seconds) or perSecond <= 0 or seconds <= 0 then
        return 0
    end
    if perSecond >= 1 then
        return 1
    end
    return 1 - (1 - perSecond) ^ seconds
end

-- Seltenheit nach einer Quotentabelle (Hundertstel-Prozent, Summe 10000). `r` in [0, 1).
function FindRoll.pickRarity(odds: { [string]: number }, r: number, rarities: any?): string
    local list = if rarities then rarities.list else RaritiesData.list
    local target = math.clamp(r, 0, 0.999999999) * 10000
    local sum = 0
    local last = list[1].id
    for _, rarity in list do
        local share = odds[rarity.id]
        if type(share) == "number" and share > 0 then
            sum += share
            last = rarity.id
            if target < sum then
                return rarity.id
            end
        end
    end
    return last -- Rundungsrest: die letzte Stufe mit Anteil
end

-- Funde einer Zone, nach Seltenheit sortiert. Gebaut aus `finds.list`, gemerkt je Tabelle.
local indexCache: { [any]: { [string]: { [string]: { any } } } } = setmetatable({}, { __mode = "k" }) :: any

local function indexOf(finds: any): { [string]: { [string]: { any } } }
    local cached = indexCache[finds]
    if cached ~= nil then
        return cached
    end
    local index: { [string]: { [string]: { any } } } = {}
    for _, find in finds.list do
        local perZone = index[find.zoneId]
        if perZone == nil then
            perZone = {}
            index[find.zoneId] = perZone
        end
        local bucket = perZone[find.rarityId]
        if bucket == nil then
            bucket = {}
            perZone[find.rarityId] = bucket
        end
        table.insert(bucket, find)
    end
    indexCache[finds] = index
    return index
end

-- Wählt ein Fundstück der Zone mit der Seltenheit; fehlt sie dort, die nächst tiefere Stufe.
function FindRoll.pickFind(zoneId: string, rarityId: string, r: number, data: any?): any?
    local finds = if data and data.Finds then data.Finds else FindsData
    local rarities = if data and data.Rarities then data.Rarities else RaritiesData
    local perZone = indexOf(finds)[zoneId]
    if perZone == nil then
        return nil
    end
    local rank = if rarities.byId[rarityId] then rarities.byId[rarityId].rank else 0
    while rank >= 1 do
        local rarity = rarities.list[rank]
        local bucket = perZone[rarity.id]
        if bucket ~= nil and #bucket > 0 then
            local pick = math.floor(math.clamp(r, 0, 0.999999999) * #bucket) + 1
            return bucket[pick]
        end
        rank -= 1
    end
    return nil
end

-- Wert eines Fundstücks in Münzen. `toolRate` ist die Grundrate des Werkzeugs (ohne Knoten-Boni).
function FindRoll.valueOf(zoneId: string, rarityId: string, toolRate: number, data: any?): BigNum.BigNum
    local odds = if data and data.FindOdds then data.FindOdds else FindOddsData
    local rarities = if data and data.Rarities then data.Rarities else RaritiesData
    local sandTypes = if data and data.SandTypes then data.SandTypes else SandTypesData
    local zones = if data and data.Zones then data.Zones else ZonesData
    local zone = zones.byId[zoneId]
    local sandType = if zone then sandTypes.byId[zone.sandTypeId] else nil
    local rarity = rarities.byId[rarityId]
    if sandType == nil or rarity == nil or not isGoodNumber(toolRate) or toolRate <= 0 then
        return BigNum.zero()
    end
    -- Ganze Münzen: ein Fundwert mit Bruchteil (Faktoren aus Datenänderungen) wird abgerundet.
    return BigNum.floor(BigNum.new(odds.findBaseValue * sandType.priceFactor * toolRate * rarity.valueFactor))
end

-- Würfelt für das Fenster. Gibt nil zurück, wenn kein Fund fällt. `data` ist für Tests überschreibbar
-- (Felder FindOdds, Finds, Rarities, SandTypes, Zones, Weather, Collection).
function FindRoll.roll(input: Input, data: any?): Roll?
    local odds = if data and data.FindOdds then data.FindOdds else FindOddsData
    if not isGoodNumber(input.seconds) or input.seconds <= 0 then
        return nil
    end
    local profile = input.profile
    local zoneId = input.zoneId
    local tableName = odds.zoneOddsTable[zoneId]
    local oddsTable = if tableName then odds.tables[tableName] else nil
    if oddsTable == nil then
        return nil
    end

    local forced = false
    local rarityId: string
    local noFindsYet = Collection.distinctFound(profile, data) == 0
    if noFindsYet and input.sessionSeconds >= odds.firstFindGuaranteeSeconds then
        forced = true
        rarityId = "common"
    else
        local chance = FindRoll.chanceInWindow(FindRoll.chancePerSecond(profile, zoneId, input.serverTime, data), input.seconds)
        if input.random() >= chance then
            return nil
        end
        rarityId = FindRoll.pickRarity(oddsTable, input.random(), if data and data.Rarities then data.Rarities else nil)
    end

    local find = FindRoll.pickFind(zoneId, rarityId, input.random(), data)
    if find == nil then
        return nil
    end
    local toolRate = TreeEffects.of(profile).tool.sandPerSecond
    -- Windkristalle (Paket 2.7) gelten für alle Münzen, auch für den Fundwert. Das ist kein
    -- Horten-Anreiz: der Wert ist beim Fund festgeschrieben und ein Duplikat wird sofort verkauft.
    local value = BigNum.floor(BigNum.mulNumber(FindRoll.valueOf(zoneId, find.rarityId, toolRate, data), Wind.multiplier(profile)))
    return {
        find = find,
        rarityId = find.rarityId,
        value = value,
        forced = forced,
    }
end

return FindRoll
