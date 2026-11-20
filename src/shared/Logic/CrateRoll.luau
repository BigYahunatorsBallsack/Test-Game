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
-- Quoten der nächsten Öffnung (Paket 4.6): `effectiveOdds(kiste, zähler)` liefert die Gewichte, mit
-- denen die NÄCHSTE Öffnung bei diesem Zählerstand würfelt. Ohne anstehende Garantie ist das die
-- Tabelle selbst, mit Garantie nur die Seltenheiten ab der garantierten Stufe (Gewichte aus der
-- Tabelle). `roll` würfelt die Seltenheit genau über diese Funktion, das Kisten-Fenster zeigt sie an.
-- Anzeige und Wurf haben also eine Rechnung. `itemOdds` rechnet daraus die Quote je Item (exakter
-- Bruch), `longRunRates` die Langzeitrate je Seltenheit mit Pity (Grundlage der Direktkauf-Preise).
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

export type Effective = {
    -- Gewichte je Seltenheit (Hundertstel-Prozent). Ohne Garantie dieselbe Referenz wie die
    -- Quotentabelle der Kiste (nicht verändern!), mit Garantie eine neue Tabelle: jede bekannte
    -- Seltenheit, unter der garantierten Stufe mit 0.
    odds: { [string]: number },
    total: number, -- Summe der Gewichte über 0; Quote = Gewicht / total
    guarantee: string?, -- "epic" oder "legendary", wenn die nächste Öffnung garantiert ist
}

export type ItemOdds = {
    itemId: string,
    name: string,
    kind: string,
    rarityId: string,
    numerator: number, -- Gewicht der Seltenheit (ganze Zahl)
    denominator: number, -- total x Poolgröße (ganze Zahl); Quote = numerator / denominator
    percent: number, -- numerator / denominator x 100 (Gleitkomma, nur zur Anzeige)
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

-- Gültiges Gewicht: Zahl über 0 (NaN, nil und Text zählen wie 0).
local function isWeight(share: any): boolean
    return type(share) == "number" and share > 0 and share < math.huge
end

-- Summe der Gewichte bekannter Seltenheiten ab Rang `minRank`.
local function weightTotal(odds: { [string]: number }, minRank: number, data: any?): number
    local total = 0
    for _, rarity in raritiesOf(data).list do
        local share = odds[rarity.id]
        if rarity.rank >= minRank and isWeight(share) then
            total += share
        end
    end
    return total
end

-- Los ziehen: floor(r x total) + 1, also 1 bis total. Die Seltenheiten ab Rang `minRank` belegen in
-- Rang-Reihenfolge Bereiche so breit wie ihr Gewicht. `total` muss die Summe dieser Gewichte sein.
local function walk(odds: { [string]: number }, total: number, r: number, minRank: number, data: any?): string
    local ticket = math.min(math.floor(r * total) + 1, total) -- 1 bis Summe
    local upper = 0
    local last: string? = nil
    for _, rarity in raritiesOf(data).list do
        local share = odds[rarity.id]
        if rarity.rank >= minRank and isWeight(share) then
            upper += share
            last = rarity.id
            if ticket <= upper then
                return rarity.id
            end
        end
    end
    -- nicht erreichbar, die Bereiche decken 1 bis Summe ab
    if last == nil then
        error(`CrateRoll: keine Seltenheit ab Rang {minRank} mit Quote über 0`)
    end
    return last
end

-- Seltenheit nach der Tabelle, nur unter Seltenheiten ab Rang `minRank`, im Verhältnis der Quoten.
-- `r` in [0, 1). Wirft, wenn keine Seltenheit ab diesem Rang eine Quote über 0 hat.
function CrateRoll.pickRarity(odds: { [string]: number }, r: number, minRank: number?, data: any?): string
    local floorRank = minRank or 1
    local total = weightTotal(odds, floorRank, data)
    if total <= 0 then
        error(`CrateRoll: keine Seltenheit ab Rang {floorRank} mit Quote über 0`)
    end
    return walk(odds, total, r, floorRank, data)
end

-- Quoten der nächsten Öffnung bei diesem Zählerstand (nil = 0/0). Ohne anstehende Garantie: die
-- Tabelle selbst (dieselbe Referenz, nicht verändern). Mit Garantie: neue Tabelle mit allen
-- bekannten Seltenheiten, die unter der garantierten Stufe mit 0, die anderen mit ihrem Gewicht aus
-- der Tabelle. Die Tabelle der Kiste wird nie verändert. `roll` würfelt genau hierüber.
-- Wirft bei unbekannter Pity-Stufe oder wenn keine Seltenheit eine Quote über 0 hat.
function CrateRoll.effectiveOdds(crate: any, counters: any, data: any?): Effective
    local tier = CrateRoll.guarantee(crate, counters)
    local source = CrateRoll.oddsOf(crate)
    local odds = source
    local minRank = 1
    if tier ~= nil then
        minRank = rankOf(tier, data)
        if minRank < 1 then
            error(`CrateRoll: Pity-Stufe "{tostring(tier)}" ist keine bekannte Seltenheit`)
        end
        local filtered: { [string]: number } = {}
        for _, rarity in raritiesOf(data).list do
            local share = source[rarity.id]
            filtered[rarity.id] = if rarity.rank >= minRank and isWeight(share) then share else 0
        end
        odds = filtered
    end
    local total = weightTotal(odds, minRank, data)
    if total <= 0 then
        error(`CrateRoll: keine Seltenheit ab Rang {minRank} mit Quote über 0`)
    end
    return { odds = odds, total = total, guarantee = tier }
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
-- Die Seltenheit kommt aus `effectiveOdds` (dieselbe Funktion wie die Anzeige).
function CrateRoll.roll(crate: any, counters: any, random: () -> number, data: any?): Roll
    local effective = CrateRoll.effectiveOdds(crate, counters, data)
    local tier = effective.guarantee
    local rarityId = walk(effective.odds, effective.total, draw(random), 1, data)
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

-- Seltenheiten nach Rang, höchste zuerst (Kopie der Liste).
local function raritiesByRankDesc(data: any?): { any }
    local list = table.clone(raritiesOf(data).list)
    table.sort(list, function(a: any, b: any): boolean
        return a.rank > b.rank
    end)
    return list
end

-- Quote je Item der nächsten Öffnung bei diesem Zählerstand (nil = 0/0), für die Liste "Details".
-- Je Item ein exakter Bruch: Gewicht der Seltenheit / (total x Poolgröße), dazu `percent` zur Anzeige.
-- Nur Items, die gerade fallen können (Gewicht über 0). Sortiert nach Rang absteigend, innerhalb
-- einer Seltenheit in der Reihenfolge von CrateItems. Die Brüche ergeben zusammen genau 1, solange
-- jede Seltenheit mit Gewicht über 0 Items hat (DataCheck). Unbekannte Kiste: leere Liste.
function CrateRoll.itemOdds(crateId: string, counters: any?, data: any?): { ItemOdds }
    local crate = cratesOf(data).byId[crateId]
    if crate == nil then
        return {}
    end
    local effective = CrateRoll.effectiveOdds(crate, counters, data)
    local list: { ItemOdds } = {}
    for _, rarity in raritiesByRankDesc(data) do
        local weight = effective.odds[rarity.id]
        if isWeight(weight) then
            local pool = CrateRoll.pool(crate.id, rarity.id, data)
            local denominator = effective.total * #pool
            for _, item in pool do
                table.insert(list, {
                    itemId = item.id,
                    name = item.name,
                    kind = item.kind,
                    rarityId = rarity.id,
                    numerator = weight,
                    denominator = denominator,
                    percent = weight / denominator * 100,
                })
            end
        end
    end
    return list
end

-- Langzeitraten je Kiste, gemerkt mit einer Signatur der Eingaben (Quoten, Pity, Seltenheiten).
-- Ändert sich eine davon, wird neu gerechnet. Die Rechnung ist deterministisch, das Merken spart
-- nur Zeit (DirectShop fragt je Item).
local rateCache: { [any]: { signature: string, rates: { [string]: number } } } = setmetatable({}, { __mode = "k" }) :: any

local function rateSignature(crate: any, data: any?): string
    local parts: { string } = {}
    local odds = CrateRoll.oddsOf(crate)
    for _, rarity in raritiesOf(data).list do
        table.insert(parts, `{rarity.id}:{rarity.rank}:{tostring(odds[rarity.id])}`)
    end
    local pity = crate.pity
    if type(pity) == "table" then
        for _, entry in PITY_TIERS do
            table.insert(parts, `{entry.tier}={tostring(pity[entry.tier])}`)
        end
    end
    return table.concat(parts, ";")
end

-- Höchster sinnvoller Zählerstand einer Stufe: Grenze - 1 (ab dort greift die Garantie, alles
-- darüber verhält sich gleich). Ohne Grenze zählt der Zähler nie, er bleibt 0.
local function counterCap(pity: any, tier: string): number
    local limit = pity[tier]
    if type(limit) ~= "number" or limit ~= limit or limit < 1 or limit == math.huge then
        return 0
    end
    return math.floor(limit) - 1
end

-- Langzeitrate je Seltenheit mit Pity: stationäre Verteilung der Markov-Kette über
-- (sinceEpic, sinceLegendary). Die Kette benutzt dieselben Funktionen wie der Wurf
-- (effectiveOdds für die Quoten je Zustand, advance für den nächsten Zählerstand).
-- Exakte Lösung über Erneuerung: Die höchste Garantie setzt alle Zähler auf 0, also kehrt die
-- Kette spätestens nach der höchsten Grenze nach (0, 0) zurück. Von (0, 0) aus wird die Masse
-- Schritt für Schritt weitergereicht, bis alles zurück ist; die erwarteten Besuche je Zustand in
-- einem Zyklus, geteilt durch die erwartete Zykluslänge, sind die stationäre Verteilung.
local function pityRates(crate: any, data: any?): { [string]: number }
    local pity = crate.pity
    local capEpic = counterCap(pity, "epic")
    local capLegendary = counterCap(pity, "legendary")
    local width = capEpic + 1
    local stateCount = width * (capLegendary + 1)
    local function indexOf(e: number, l: number): number
        return math.min(l, capLegendary) * width + math.min(e, capEpic) + 1
    end
    local rarities = raritiesOf(data).list
    -- Übergänge je Zustand: { { rarityId, p, next } }
    local transitions: { { { rarityId: string, p: number, next: number } } } = table.create(stateCount)
    for l = 0, capLegendary do
        for e = 0, capEpic do
            local state = { sinceEpic = e, sinceLegendary = l }
            local effective = CrateRoll.effectiveOdds(crate, state, data)
            local list = {}
            for _, rarity in rarities do
                local weight = effective.odds[rarity.id]
                if isWeight(weight) then
                    local nextState = CrateRoll.advance(crate, state, rarity.id, data) :: Counters
                    table.insert(list, {
                        rarityId = rarity.id,
                        p = weight / effective.total,
                        next = indexOf(nextState.sinceEpic, nextState.sinceLegendary),
                    })
                end
            end
            transitions[indexOf(e, l)] = list
        end
    end

    local start = indexOf(0, 0)
    local visits = table.create(stateCount, 0)
    local current = table.create(stateCount, 0)
    current[start] = 1
    local remaining = 1
    -- Ein Zyklus ist höchstens so lang wie es Zustände gibt (der Zähler der höchsten Stufe steigt
    -- bis zur Garantie streng). +1 als Puffer.
    for _ = 1, stateCount + 1 do
        if remaining <= 0 then
            break
        end
        local nextMass = table.create(stateCount, 0)
        for index = 1, stateCount do
            local mass = current[index]
            if mass > 0 then
                visits[index] += mass
                for _, step in transitions[index] do
                    if step.next ~= start then
                        nextMass[step.next] += mass * step.p
                    end
                end
            end
        end
        current = nextMass
        remaining = 0
        for index = 1, stateCount do
            remaining += current[index]
        end
    end
    if remaining > 1e-12 then
        error(`CrateRoll: Pity-Kette der Kiste "{tostring(crate.id)}" kehrt nicht nach (0, 0) zurück`)
    end

    local cycleLength = 0
    for index = 1, stateCount do
        cycleLength += visits[index]
    end
    local rates: { [string]: number } = {}
    for _, rarity in rarities do
        rates[rarity.id] = 0
    end
    for index = 1, stateCount do
        local share = visits[index] / cycleLength
        if share > 0 then
            for _, step in transitions[index] do
                rates[step.rarityId] += share * step.p
            end
        end
    end
    return rates
end

-- Langzeitrate je Seltenheit und Öffnung (0 bis 1), über viele Öffnungen am Stück ab frischem
-- Zähler, mit Pity. Kisten ohne Pity: Gewicht / Summe der Tabelle (bei Summe 10000 also Quote /
-- 10000). Jede bekannte Seltenheit kommt vor (auch mit 0). Gibt eine neue Tabelle zurück.
function CrateRoll.longRunRates(crate: any, data: any?): { [string]: number }
    local signature = rateSignature(crate, data)
    local cached = rateCache[crate]
    if cached == nil or cached.signature ~= signature then
        local rates: { [string]: number }
        if type(crate.pity) == "table" then
            rates = pityRates(crate, data)
        else
            local effective = CrateRoll.effectiveOdds(crate, nil, data)
            rates = {}
            for _, rarity in raritiesOf(data).list do
                local weight = effective.odds[rarity.id]
                rates[rarity.id] = if isWeight(weight) then weight / effective.total else 0
            end
        end
        cached = { signature = signature, rates = rates }
        rateCache[crate] = cached
    end
    return table.clone((cached :: any).rates)
end

return CrateRoll
