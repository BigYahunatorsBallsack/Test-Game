--!strict
-- Kisten auswürfeln (Paket 4.2). Rein, ohne Roblox-API, Lune-Tests in tests/crateroll.spec.luau.
--
-- Eine Tabelle für Anzeige und Auswurf: `displayOdds` (Kisten-Fenster) und `roll` (Server) lesen
-- beide über `oddsOf` dieselbe Quotentabelle `Crates.byId[id].odds` (Hundertstel-Prozent,
-- 10000 = 100 %). Es gibt keine Kopie und keine zweite Quelle, darum können angezeigte und
-- gewürfelte Quoten nie auseinanderlaufen.
--
-- Der Zufall kommt als Funktion `random() -> [0, 1)` herein (im Spiel `Random.new()` des Servers,
-- in Tests feste Folgen). Jede Öffnung braucht genau zwei Zahlen:
--  1. Seltenheit: Los = floor(r x Summe) + 1, also 1 bis 10000 bei der vollen Tabelle. Die
--     Seltenheiten belegen in Rang-Reihenfolge (Rarities) aufeinanderfolgende Bereiche so breit wie
--     ihre Quote. Seltenheiten mit Quote 0 kommen nie vor.
--  2. Item: gleich verteilt unter den Items der Kiste mit dieser Seltenheit (Reihenfolge wie in
--     CrateItems.list).
-- Ein Zufallswert, der keine Zahl in [0, 1) ist, ist ein Fehler (error), damit ein kaputter
-- Zufallsgeber nie still eine Seltenheit bevorzugt. CrateOpen fängt den Fehler ab und bucht nichts.
--
-- Pity (nur Kisten mit `pity` in den Daten, Grenzen dort, z. B. 15 und 60; jede Kiste hat ihren
-- eigenen Zähler `profile.pity[kistenId]`):
--  * `sinceLegendary >= pity.legendary - 1`: diese Öffnung ist mindestens Legendär. Gewürfelt wird
--    nur unter Legendär und besser, im Verhältnis der Tabelle.
--  * sonst `sinceEpic >= pity.epic - 1`: mindestens Episch (unter Episch und besser, im Verhältnis
--    der Tabelle).
--  * Greifen beide, gewinnt die Legendär-Garantie.
-- Zähler danach (`advance`): Legendär oder besser setzt beide auf 0, Episch setzt nur `sinceEpic`
-- auf 0 (`sinceLegendary` zählt weiter), alles darunter zählt beide um 1 hoch. Kisten ohne `pity`
-- ändern keinen Zähler. "Oder besser" heißt Rang >= Rang der Stufe (Rarities); die Schlüssel der
-- Pity-Tabelle (`epic`, `legendary`) sind die Seltenheits-IDs.
--
-- `data` ist für Tests überschreibbar ({ Crates = ..., CrateItems = ..., Rarities = ... }), wie
-- bei Wind und Sandstorm.

local CratesData = require("../Data/Crates")
local CrateItemsData = require("../Data/CrateItems")
local RaritiesData = require("../Data/Rarities")

-- Pity-Stufen in der Reihenfolge, in der sie geprüft werden (die höhere zuerst, sie gewinnt).
-- `tier` ist der Schlüssel in `crate.pity` und zugleich die Seltenheits-ID, `counter` das Feld im
-- Zähler des Profils.
local PITY_TIERS: { { tier: string, counter: string } } = {
    { tier = "legendary", counter = "sinceLegendary" },
    { tier = "epic", counter = "sinceEpic" },
}

export type Counters = { sinceEpic: number, sinceLegendary: number }

export type OddsRow = {
    rarityId: string,
    name: string, -- Anzeigename der Seltenheit
    colorHex: string,
    odds: number, -- Hundertstel-Prozent, dieselbe Zahl wie in der Quotentabelle
}

export type Display = {
    crateId: string,
    odds: { [string]: number }, -- dieselbe Referenz wie Crates.byId[id].odds
    rows: { OddsRow }, -- alle Seltenheiten nach Rang, auch die mit Quote 0
    pity: { epic: number, legendary: number }?, -- Pity-Grenzen der Kiste (nil = keine)
}

export type Roll = {
    item: any, -- Eintrag aus CrateItems
    rarityId: string,
    pityTriggered: string?, -- "epic" oder "legendary", wenn eine Garantie gegriffen hat
    pity: Counters?, -- neuer Zählerstand (neue Tabelle), nil bei Kisten ohne Pity
}

local CrateRoll = {}

local function cratesOf(data: any?): any
    return if data and data.Crates then data.Crates else CratesData
end

local function itemsOf(data: any?): any
    return if data and data.CrateItems then data.CrateItems else CrateItemsData
end

local function raritiesOf(data: any?): any
    return if data and data.Rarities then data.Rarities else RaritiesData
end

-- Die eine Quotentabelle einer Kiste. Anzeige und Wurf lesen nur hierüber.
function CrateRoll.oddsOf(crate: any): { [string]: number }
    return crate.odds
end

-- Quoten für das Kisten-Fenster: alle Seltenheiten in Rang-Reihenfolge mit der Zahl aus der
-- Tabelle. nil bei unbekannter Kiste.
function CrateRoll.displayOdds(crateId: string, data: any?): Display?
    local crate = cratesOf(data).byId[crateId]
    if crate == nil then
        return nil
    end
    local odds = CrateRoll.oddsOf(crate)
    local rows: { OddsRow } = {}
    for _, rarity in raritiesOf(data).list do
        local share = odds[rarity.id]
        table.insert(rows, {
            rarityId = rarity.id,
            name = rarity.name,
            colorHex = rarity.colorHex,
            odds = if type(share) == "number" then share else 0,
        })
    end
    return { crateId = crate.id, odds = odds, rows = rows, pity = crate.pity }
end

-- Zähler als saubere ganze Zahlen ab 0 (kaputte oder fehlende Werte zählen als 0).
local function counterValue(value: any): number
    if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
        return 0
    end
    return math.floor(value)
end

-- Saubere Kopie eines Zählerstands (nil oder kaputt ergibt 0/0).
function CrateRoll.counters(value: any): Counters
    local source = if type(value) == "table" then value else {}
    return {
        sinceEpic = counterValue(source.sinceEpic),
        sinceLegendary = counterValue(source.sinceLegendary),
    }
end

-- Rang einer Seltenheit (0, wenn unbekannt).
local function rankOf(rarityId: string, data: any?): number
    local rarity = raritiesOf(data).byId[rarityId]
    return if rarity then rarity.rank else 0
end

-- Welche Garantie greift bei diesem Zählerstand? nil = keine. Liefert die Stufe ("legendary" oder
-- "epic"). Kisten ohne `pity` haben nie eine Garantie.
function CrateRoll.guarantee(crate: any, counters: any): string?
    local pity = crate.pity
    if type(pity) ~= "table" then
        return nil
    end
    local state = CrateRoll.counters(counters)
    for _, entry in PITY_TIERS do
        local limit = pity[entry.tier]
        if type(limit) == "number" and (state :: any)[entry.counter] >= limit - 1 then
            return entry.tier
        end
    end
    return nil
end

-- Neuer Zählerstand nach einer Öffnung mit Ergebnis `rarityId` (neue Tabelle). Kisten ohne `pity`
-- ändern nichts: dann kommt nil zurück.
function CrateRoll.advance(crate: any, counters: any, rarityId: string, data: any?): Counters?
    if type(crate.pity) ~= "table" then
        return nil
    end
    local state = CrateRoll.counters(counters)
    local rank = rankOf(rarityId, data)
    -- Jeder Zähler zählt hoch, außer das Ergebnis erreicht seine Stufe: Legendär oder besser
    -- erreicht beide Stufen (beide 0), Episch nur die epische (nur sinceEpic 0).
    local nextState: any = { sinceEpic = state.sinceEpic + 1, sinceLegendary = state.sinceLegendary + 1 }
    for _, entry in PITY_TIERS do
        local tierRank = rankOf(entry.tier, data)
        if tierRank > 0 and rank >= tierRank then
            nextState[entry.counter] = 0
        end
    end
    return nextState
end

-- Liest eine Zufallszahl und prüft sie. Wirft bei allem außerhalb von [0, 1).
local function draw(random: () -> number): number
    local r = random()
    if type(r) ~= "number" or r ~= r or r < 0 or r >= 1 then
        error(`CrateRoll: Zufallswert {tostring(r)} liegt nicht in [0, 1)`)
    end
    return r
end

-- Seltenheit nach der Tabelle, nur unter Seltenheiten ab Rang `minRank`, im Verhältnis der Quoten.
-- `r` in [0, 1). Wirft, wenn keine Seltenheit ab diesem Rang eine Quote über 0 hat.
function CrateRoll.pickRarity(odds: { [string]: number }, r: number, minRank: number?, data: any?): string
    local floorRank = minRank or 1
    local eligible: { { id: string, share: number } } = {}
    local total = 0
    for _, rarity in raritiesOf(data).list do
        local share = odds[rarity.id]
        if rarity.rank >= floorRank and type(share) == "number" and share > 0 then
            table.insert(eligible, { id = rarity.id, share = share })
            total += share
        end
    end
    if total <= 0 then
        error(`CrateRoll: keine Seltenheit ab Rang {floorRank} mit Quote über 0`)
    end
    local ticket = math.min(math.floor(r * total) + 1, total) -- 1 bis Summe
    local upper = 0
    for _, entry in eligible do
        upper += entry.share
        if ticket <= upper then
            return entry.id
        end
    end
    return eligible[#eligible].id -- nicht erreichbar, die Bereiche decken 1 bis Summe ab
end

-- Pools je Item-Tabelle: Kisten-ID -> Seltenheit -> Items (Reihenfolge wie in list).
local poolCache: { [any]: { [string]: { [string]: { any } } } } = setmetatable({}, { __mode = "k" }) :: any

local function poolsOf(items: any): { [string]: { [string]: { any } } }
    local cached = poolCache[items]
    if cached ~= nil then
        return cached
    end
    local pools: { [string]: { [string]: { any } } } = {}
    for _, item in items.list do
        for _, crateId in item.crates do
            local perCrate = pools[crateId]
            if perCrate == nil then
                perCrate = {}
                pools[crateId] = perCrate
            end
            local bucket = perCrate[item.rarity]
            if bucket == nil then
                bucket = {}
                perCrate[item.rarity] = bucket
            end
            table.insert(bucket, item)
        end
    end
    poolCache[items] = pools
    return pools
end

-- Items der Kiste mit dieser Seltenheit (leere Liste, wenn keine). Nicht verändern.
function CrateRoll.pool(crateId: string, rarityId: string, data: any?): { any }
    local perCrate = poolsOf(itemsOf(data))[crateId]
    return if perCrate and perCrate[rarityId] then perCrate[rarityId] else {}
end

-- Eine Öffnung. `counters` ist der Zählerstand dieser Kiste vor der Öffnung (nil = 0/0). Ändert
-- nichts, das Ergebnis enthält den neuen Zählerstand. Wirft bei kaputtem Zufall oder leerem Pool.
function CrateRoll.roll(crate: any, counters: any, random: () -> number, data: any?): Roll
    local tier = CrateRoll.guarantee(crate, counters)
    local minRank = if tier then rankOf(tier, data) else 1
    if minRank < 1 then
        error(`CrateRoll: Pity-Stufe "{tostring(tier)}" ist keine bekannte Seltenheit`)
    end
    local rarityId = CrateRoll.pickRarity(CrateRoll.oddsOf(crate), draw(random), minRank, data)
    local pool = CrateRoll.pool(crate.id, rarityId, data)
    if #pool == 0 then
        error(`CrateRoll: Kiste "{tostring(crate.id)}" hat keine Items der Seltenheit "{rarityId}"`)
    end
    local index = math.min(math.floor(draw(random) * #pool) + 1, #pool)
    return {
        item = pool[index],
        rarityId = rarityId,
        pityTriggered = tier,
        pity = CrateRoll.advance(crate, counters, rarityId, data),
    }
end

return CrateRoll
