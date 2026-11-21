--!strict
-- Quoten-Simulation (Paket 4.7), Kern. Benutzt von scripts/cratesim.luau (großer Lauf mit Bericht)
-- und tests/cratesim.spec.luau (kleiner Lauf im normalen Testlauf).
--
-- Jede Öffnung läuft über den echten Kaufweg `CrateOpen.open` auf einem Testprofil (Policy erlaubt,
-- Saison an). Gems bzw. Münzen werden vor dem Kauf aufgefüllt; Pity und Inventar bleiben unberührt.
-- Die Sollwerte rechnet dieses Modul möglichst unabhängig vom geprüften Code:
--  * Kisten ohne Pity: Quote / Summe der Tabelle (direkt aus Data/Crates).
--  * Kisten mit Pity: `CrateRoll.longRunRates` (Vorgabe im Plan). Zur Gegenprobe rechnet
--    `pityChain` dieselbe Markov-Kette hier noch einmal nur aus den Daten nach.
--  * Item: Rate der Seltenheit / Poolgröße (Pool direkt aus Data/CrateItems).
-- Zufall: eigener xoshiro128** mit festem Startwert, 53 Bit je Zahl. Gleicher Startwert ergibt
-- dieselbe Folge, unabhängig von math.random und der Lune-Version.
--
-- Streuung:
--  * Ohne Pity sind die Öffnungen unabhängig: Binomial-Sigma sqrt(n p (1 - p)), Pearson-Chi-Quadrat
--    über alle Items (Freiheitsgrade = Items - 1).
--  * Mit Pity hängen benachbarte Öffnungen zusammen (Zähler). Das Binomial-Sigma ist dann nur eine
--    Näherung. Darum Batch-Means: Der Lauf wird in B gleich lange Blöcke geteilt (viel länger als
--    ein Pity-Zyklus von höchstens 60 Öffnungen), Sigma = Streuung der Block-Raten / sqrt(B).
--    Chi-Quadrat wird geteilt: (a) Items innerhalb der Seltenheit (exakt multinomial, weil der
--    Item-Wurf nicht von der Pity abhängt), (b) Seltenheiten mit Hotelling-T² über die Block-Raten
--    (F-Verteilung). Das naive Pearson-Chi-Quadrat über alle Items steht nur zur Info im Bericht.

local CrateOpen = require("../../src/shared/Logic/CrateOpen")
local CrateRoll = require("../../src/shared/Logic/CrateRoll")
local Profile = require("../../src/shared/Logic/Profile")
local BigNum = require("../../src/shared/Logic/BigNum")
local Crates = require("../../src/shared/Data/Crates")
local CrateItems = require("../../src/shared/Data/CrateItems")
local Rarities = require("../../src/shared/Data/Rarities")

local NOW = 1_700_000_000
local TWO32 = 4294967296
local TWO53 = 9007199254740992
local GEM_TOP_UP = 1_000_000 -- Gem-Stand nach dem Auffüllen (unter maxGems)
local COIN_START = 1e9 -- Münzstand vor jeder Holzkisten-Öffnung

local M = {}

M.MODES = { "single", "bundle" }
M.MODE_NAMES = { single = "Einzeln", bundle = "10 + 1 Pakete" }

-- Schwellen (Plan 4.7, Begründungen im Bericht).
M.DEFAULT_THRESHOLDS = {
    sigma = 4, -- |Abweichung| in Sigma, Seltenheiten, Items und Garantie-Raten
    batchSigma = 4, -- dasselbe mit Batch-Means-Sigma (Pity-Kisten)
    relShareMin = 0.10, -- Relativ-Regel nur ab diesem Anteil
    relAt1M = 0.01, -- erlaubte relative Abweichung bei 1.000.000 Öffnungen, skaliert mit sqrt(1e6 / n)
    pMin = 0.001, -- Chi-Quadrat bzw. Hotelling: p muss darüber liegen
    crossCheck = 1e-12, -- longRunRates gegen eigene Markov-Kette
}

---------------------------------------------------------------------------------------------------
-- Zufall: xoshiro128** (32 Bit), Startzustand über splitmix32/fmix32.

local function imul(a: number, b: number): number
    local bLow = b % 65536
    local bHigh = (b - bLow) / 65536
    return ((a * bHigh) % 65536 * 65536 + a * bLow) % TWO32
end

local function fmix(x: number): number
    local z = x
    z = imul(bit32.bxor(z, bit32.rshift(z, 16)), 0x85EBCA6B)
    z = imul(bit32.bxor(z, bit32.rshift(z, 13)), 0xC2B2AE35)
    return bit32.bxor(z, bit32.rshift(z, 16))
end

-- Zufallsgeber `() -> [0, 1)` für einen Startwert (ganze Zahl). Gleicher Startwert, gleiche Folge.
function M.newRandom(seed: number): () -> number
    local x = math.floor(seed) % TWO32
    local state = {}
    for i = 1, 4 do
        x = (x + 0x9E3779B9) % TWO32
        state[i] = fmix(x)
    end
    local s0, s1, s2, s3 = state[1], state[2], state[3], state[4]
    if s0 == 0 and s1 == 0 and s2 == 0 and s3 == 0 then
        s0 = 1
    end
    local function next32(): number
        local result = (bit32.lrotate((s1 * 5) % TWO32, 7) * 9) % TWO32
        local t = bit32.lshift(s1, 9)
        s2 = bit32.bxor(s2, s0)
        s3 = bit32.bxor(s3, s1)
        s1 = bit32.bxor(s1, s2)
        s0 = bit32.bxor(s0, s3)
        s2 = bit32.bxor(s2, t)
        s3 = bit32.lrotate(s3, 11)
        return result
    end
    return function(): number
        local a = bit32.rshift(next32(), 5) -- 27 Bit
        local b = bit32.rshift(next32(), 6) -- 26 Bit
        return (a * 67108864 + b) / TWO53
    end
end

-- Startwert eines Laufs aus Basis-Startwert, Kisten-Nummer und Modus-Nummer.
function M.runSeed(seed: number, crateIndex: number, modeIndex: number): number
    return fmix((math.floor(seed) * 1000 + crateIndex * 10 + modeIndex) % TWO32)
end

-- 32-Bit-Prüfsumme (FNV-1a) eines Textes.
function M.checksum(text: string): string
    local h = 2166136261
    for i = 1, #text do
        h = imul(bit32.bxor(h, string.byte(text, i)), 16777619)
    end
    return string.format("%08x", h)
end

---------------------------------------------------------------------------------------------------
-- Statistik: log-Gamma, regularisierte Gamma- und Beta-Funktion.

local LANCZOS = { 76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5 }

local function lgamma(x: number): number
    local y = x
    local tmp = x + 5.5
    tmp -= (x + 0.5) * math.log(tmp)
    local ser = 1.000000000190015
    for _, c in LANCZOS do
        y += 1
        ser += c / y
    end
    return -tmp + math.log(2.5066282746310005 * ser / x)
end

-- Q(a, x) = 1 - P(a, x), obere regularisierte Gamma-Funktion.
local function gammaQ(a: number, x: number): number
    if x <= 0 then
        return 1
    end
    local gln = lgamma(a)
    if x < a + 1 then
        local ap, sum = a, 1 / a
        local del = sum
        for _ = 1, 10000 do
            ap += 1
            del *= x / ap
            sum += del
            if math.abs(del) < math.abs(sum) * 1e-15 then
                break
            end
        end
        return 1 - sum * math.exp(-x + a * math.log(x) - gln)
    end
    local tiny = 1e-300
    local b = x + 1 - a
    local c = 1 / tiny
    local d = 1 / b
    local h = d
    for i = 1, 10000 do
        local an = -i * (i - a)
        b += 2
        d = an * d + b
        if math.abs(d) < tiny then
            d = tiny
        end
        c = b + an / c
        if math.abs(c) < tiny then
            c = tiny
        end
        d = 1 / d
        local del = d * c
        h *= del
        if math.abs(del - 1) < 1e-15 then
            break
        end
    end
    return math.exp(-x + a * math.log(x) - gln) * h
end

-- p-Wert des Chi-Quadrat-Tests: P(X >= chi2) bei df Freiheitsgraden.
function M.chiSquareP(chi2: number, df: number): number
    if df <= 0 then
        return 1
    end
    return gammaQ(df / 2, chi2 / 2)
end

local function betacf(a: number, b: number, x: number): number
    local tiny = 1e-300
    local qab, qap, qam = a + b, a + 1, a - 1
    local c, d = 1, 1 - qab * x / qap
    if math.abs(d) < tiny then
        d = tiny
    end
    d = 1 / d
    local h = d
    for m = 1, 10000 do
        local m2 = 2 * m
        local aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1 + aa * d
        if math.abs(d) < tiny then
            d = tiny
        end
        c = 1 + aa / c
        if math.abs(c) < tiny then
            c = tiny
        end
        d = 1 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1 + aa * d
        if math.abs(d) < tiny then
            d = tiny
        end
        c = 1 + aa / c
        if math.abs(c) < tiny then
            c = tiny
        end
        d = 1 / d
        local del = d * c
        h *= del
        if math.abs(del - 1) < 1e-15 then
            break
        end
    end
    return h
end

-- Regularisierte unvollständige Beta-Funktion I_x(a, b).
local function betaI(a: number, b: number, x: number): number
    if x <= 0 then
        return 0
    elseif x >= 1 then
        return 1
    end
    local front = math.exp(lgamma(a + b) - lgamma(a) - lgamma(b) + a * math.log(x) + b * math.log(1 - x))
    if x < (a + 1) / (a + b + 2) then
        return front * betacf(a, b, x) / a
    end
    return 1 - front * betacf(b, a, 1 - x) / b
end

-- p-Wert des F-Tests: P(F >= f) bei (d1, d2) Freiheitsgraden.
function M.fTestP(f: number, d1: number, d2: number): number
    if f <= 0 then
        return 1
    end
    return betaI(d2 / 2, d1 / 2, d2 / (d2 + d1 * f))
end

-- Löst A x = b (Gauß mit Pivotsuche). Gibt nil zurück, wenn A singulär ist.
local function solve(matrix: { { number } }, rhs: { number }): { number }?
    local n = #rhs
    local a: { { number } } = {}
    for i = 1, n do
        a[i] = table.clone(matrix[i])
        a[i][n + 1] = rhs[i]
    end
    for col = 1, n do
        local pivot = col
        for row = col + 1, n do
            if math.abs(a[row][col]) > math.abs(a[pivot][col]) then
                pivot = row
            end
        end
        if math.abs(a[pivot][col]) < 1e-300 then
            return nil
        end
        a[col], a[pivot] = a[pivot], a[col]
        for row = 1, n do
            if row ~= col then
                local factor = a[row][col] / a[col][col]
                for k = col, n + 1 do
                    a[row][k] -= factor * a[col][k]
                end
            end
        end
    end
    local x = {}
    for i = 1, n do
        x[i] = a[i][n + 1] / a[i][i]
    end
    return x
end

---------------------------------------------------------------------------------------------------
-- Sollwerte aus den Daten.

local function rankOf(rarityId: string): number
    return Rarities.byId[rarityId].rank
end

-- Pool je Seltenheit direkt aus CrateItems (Reihenfolge wie in der Liste).
function M.pools(crateId: string): { [string]: { any } }
    local pools: { [string]: { any } } = {}
    for _, rarity in Rarities.list do
        pools[rarity.id] = {}
    end
    for _, item in CrateItems.list do
        if table.find(item.crates, crateId) then
            table.insert(pools[item.rarity], item)
        end
    end
    return pools
end

-- Eigene Markov-Kette der Pity nur aus den Daten (Gegenprobe zu CrateRoll.longRunRates).
-- Liefert Raten je Seltenheit und je Garantie (Anteil der Öffnungen mit dieser Garantie).
function M.pityChain(crate: any): ({ [string]: number }, { epic: number, legendary: number })
    local limitEpic = crate.pity.epic
    local limitLegendary = crate.pity.legendary
    local epicRank, legendaryRank = rankOf("epic"), rankOf("legendary")
    local width = limitEpic
    local function index(e: number, l: number): number
        return l * width + e + 1
    end
    local states = limitEpic * limitLegendary
    -- Übergänge je Zustand
    local moves: { { { rarityId: string, p: number, nextIndex: number } } } = {}
    local tierOf: { string? } = {}
    for l = 0, limitLegendary - 1 do
        for e = 0, limitEpic - 1 do
            local minRank, tier = 1, nil
            if l >= limitLegendary - 1 then
                minRank, tier = legendaryRank, "legendary"
            elseif e >= limitEpic - 1 then
                minRank, tier = epicRank, "epic"
            end
            local total = 0
            for _, rarity in Rarities.list do
                local w = crate.odds[rarity.id] or 0
                if rarity.rank >= minRank and w > 0 then
                    total += w
                end
            end
            local list = {}
            for _, rarity in Rarities.list do
                local w = crate.odds[rarity.id] or 0
                if rarity.rank >= minRank and w > 0 then
                    local ne, nl
                    if rarity.rank >= legendaryRank then
                        ne, nl = 0, 0
                    elseif rarity.rank >= epicRank then
                        ne, nl = 0, math.min(l + 1, limitLegendary - 1)
                    else
                        ne, nl = math.min(e + 1, limitEpic - 1), math.min(l + 1, limitLegendary - 1)
                    end
                    table.insert(list, { rarityId = rarity.id, p = w / total, nextIndex = index(ne, nl) })
                end
            end
            moves[index(e, l)] = list
            tierOf[index(e, l)] = tier
        end
    end
    local start = index(0, 0)
    local visits = table.create(states, 0)
    local current = table.create(states, 0)
    current[start] = 1
    for _ = 1, states + 1 do
        local nextMass = table.create(states, 0)
        local left = 0
        for i = 1, states do
            local mass = current[i]
            if mass > 0 then
                visits[i] += mass
                for _, step in moves[i] do
                    if step.nextIndex ~= start then
                        nextMass[step.nextIndex] += mass * step.p
                        left += mass * step.p
                    end
                end
            end
        end
        current = nextMass
        if left <= 0 then
            break
        end
    end
    local cycle = 0
    for i = 1, states do
        cycle += visits[i]
    end
    local rates: { [string]: number } = {}
    for _, rarity in Rarities.list do
        rates[rarity.id] = 0
    end
    local triggers = { epic = 0, legendary = 0 }
    for i = 1, states do
        local share = visits[i] / cycle
        for _, step in moves[i] do
            rates[step.rarityId] += share * step.p
        end
        local tier = tierOf[i]
        if tier ~= nil then
            (triggers :: any)[tier] += share
        end
    end
    return rates, triggers
end

-- Sollraten je Seltenheit (Plan: Holz/Eisen aus der Tabelle, Gold/Event aus longRunRates) und
-- die Gegenprobe (größte Differenz zur unabhängigen Rechnung).
function M.targets(crate: any): any
    local rates: { [string]: number } = {}
    local crossDiff = 0
    local triggers: any = nil
    local longRun = CrateRoll.longRunRates(crate)
    if type(crate.pity) == "table" then
        local own, ownTriggers = M.pityChain(crate)
        for _, rarity in Rarities.list do
            rates[rarity.id] = longRun[rarity.id] or 0
            crossDiff = math.max(crossDiff, math.abs(rates[rarity.id] - own[rarity.id]))
        end
        triggers = ownTriggers
    else
        local total = 0
        for _, rarity in Rarities.list do
            total += crate.odds[rarity.id] or 0
        end
        for _, rarity in Rarities.list do
            rates[rarity.id] = (crate.odds[rarity.id] or 0) / total
            crossDiff = math.max(crossDiff, math.abs(rates[rarity.id] - (longRun[rarity.id] or 0)))
        end
    end
    return { rarity = rates, triggers = triggers, crossDiff = crossDiff }
end

---------------------------------------------------------------------------------------------------
-- Simulation über CrateOpen.open.

-- Ein Lauf: `mode` "single" (nur Einzelöffnungen) oder "bundle" (nur 10 + 1 Pakete) bis etwa
-- `target` Öffnungen. `batches` = Zahl der Blöcke für Batch-Means.
function M.simulate(crateId: string, mode: string, target: number, seed: number, batches: number): any
    local crate = Crates.byId[crateId]
    assert(crate ~= nil, `unbekannte Kiste {crateId}`)
    local countArg = if mode == "single" then 1 else Crates.bundle.buy
    local perCall = if mode == "single" then 1 else Crates.bundle.get
    local priceFactor = if mode == "single" then 1 else Crates.bundle.buy
    local cost = crate.price * priceFactor
    local calls = math.ceil(target / perCall)
    local total = calls * perCall
    local hasPity = type(crate.pity) == "table"
    local limitEpic = if hasPity then crate.pity.epic else 0
    local limitLegendary = if hasPity then crate.pity.legendary else 0
    local epicRank, legendaryRank = rankOf("epic"), rankOf("legendary")

    -- Indizes für Seltenheiten, Items und Garantien.
    local rarityIndex: { [string]: number } = {}
    local rarityRank: { number } = {}
    for i, rarity in Rarities.list do
        rarityIndex[rarity.id] = i
        rarityRank[i] = rarity.rank
    end
    local pools = M.pools(crateId)
    local items: { any } = {}
    local itemIndex: { [string]: number } = {}
    for _, rarity in Rarities.list do
        for _, item in pools[rarity.id] do
            table.insert(items, item)
            itemIndex[item.id] = #items
        end
    end
    local rarityCount = table.create(#Rarities.list, 0)
    local itemCount = table.create(#items, 0)
    local batchSize = table.create(batches, 0)
    local batchRarity: { { number } } = {}
    local batchItem: { { number } } = {}
    local batchTrigger: { { number } } = {}
    for b = 1, batches do
        batchRarity[b] = table.create(#Rarities.list, 0)
        batchItem[b] = table.create(#items, 0)
        batchTrigger[b] = { 0, 0 } -- epic, legendary
    end

    local profile = Profile.default(NOW)
    profile.gems = GEM_TOP_UP
    local coinStart = BigNum.serialize(BigNum.new(COIN_START))
    local random = M.newRandom(seed)
    local ctx = { random = random, restricted = false, inSeason = true }

    local stats = {
        crateId = crateId,
        mode = mode,
        calls = calls,
        openings = total,
        batches = batches,
        items = items,
        rarityCount = rarityCount,
        itemCount = itemCount,
        batchSize = batchSize,
        batchRarity = batchRarity,
        batchItem = batchItem,
        batchTrigger = batchTrigger,
        triggers = { epic = 0, legendary = 0 },
        maxNoEpic = 0,
        maxNoLegendary = 0,
        failedCalls = 0,
        firstFailure = nil :: string?,
        unexpectedItems = 0,
        triggerMismatch = 0,
        counterMismatch = 0,
        paymentMismatch = 0,
        inventoryMismatch = 0,
        seconds = 0,
    }

    local sinceEpic, sinceLegendary = 0, 0
    local opened = 0
    local started = os.clock()
    for _ = 1, calls do
        -- Bezahlen vorbereiten (Pity und Inventar bleiben unberührt).
        local before = 0
        if crate.currency == "gems" then
            if profile.gems < cost then
                profile.gems = GEM_TOP_UP
            end
            before = profile.gems
        else
            profile.coins = table.clone(coinStart)
        end
        local result = CrateOpen.open(profile, crateId, countArg, ctx :: any)
        if not result.ok then
            stats.failedCalls += 1
            if stats.firstFailure == nil then
                stats.firstFailure = `{tostring(result.reason)} {tostring(result.detail)}`
            end
            continue
        end
        if crate.currency == "gems" then
            if before - profile.gems ~= cost or result.gems ~= profile.gems then
                stats.paymentMismatch += 1
            end
        else
            local left = BigNum.toNumber(BigNum.deserialize(profile.coins))
            if math.abs(left - (COIN_START - cost)) > 0.5 then
                stats.paymentMismatch += 1
            end
        end
        if #result.results ~= perCall then
            stats.failedCalls += 1
        end
        for _, prize in result.results do
            opened += 1
            local b = math.floor((opened - 1) * batches / total) + 1
            if b > batches then
                b = batches
            end
            batchSize[b] += 1
            local ri = rarityIndex[prize.rarityId]
            local ii = itemIndex[prize.itemId]
            local item = CrateItems.byId[prize.itemId]
            if ri == nil or ii == nil or item == nil or item.rarity ~= prize.rarityId then
                stats.unexpectedItems += 1
                continue
            end
            rarityCount[ri] += 1
            itemCount[ii] += 1
            batchRarity[b][ri] += 1
            batchItem[b][ii] += 1
            local rank = rarityRank[ri]
            if hasPity then
                local expected: string? = nil
                if sinceLegendary >= limitLegendary - 1 then
                    expected = "legendary"
                elseif sinceEpic >= limitEpic - 1 then
                    expected = "epic"
                end
                if prize.pityTriggered ~= expected then
                    stats.triggerMismatch += 1
                end
                if prize.pityTriggered == "epic" then
                    stats.triggers.epic += 1
                    batchTrigger[b][1] += 1
                elseif prize.pityTriggered == "legendary" then
                    stats.triggers.legendary += 1
                    batchTrigger[b][2] += 1
                end
                if rank >= legendaryRank then
                    sinceEpic, sinceLegendary = 0, 0
                elseif rank >= epicRank then
                    sinceEpic, sinceLegendary = 0, sinceLegendary + 1
                else
                    sinceEpic, sinceLegendary = sinceEpic + 1, sinceLegendary + 1
                end
                if sinceEpic > stats.maxNoEpic then
                    stats.maxNoEpic = sinceEpic
                end
                if sinceLegendary > stats.maxNoLegendary then
                    stats.maxNoLegendary = sinceLegendary
                end
            elseif prize.pityTriggered ~= nil then
                stats.triggerMismatch += 1
            end
        end
        if hasPity then
            local pity = result.pity
            if
                pity == nil
                or pity.sinceEpic ~= sinceEpic
                or pity.sinceLegendary ~= sinceLegendary
                or profile.pity[crateId].sinceEpic ~= sinceEpic
                or profile.pity[crateId].sinceLegendary ~= sinceLegendary
            then
                stats.counterMismatch += 1
            end
        end
    end
    stats.seconds = os.clock() - started
    stats.openingsSeen = opened

    -- Inventar: jedes gezählte Item liegt genau so oft im Profil.
    for i, item in items do
        local field = CrateOpen.INVENTORY_FIELDS[item.kind]
        local have = profile.inventory[field] and profile.inventory[field][item.id] or 0
        if have ~= itemCount[i] then
            stats.inventoryMismatch += 1
        end
    end
    return stats
end

---------------------------------------------------------------------------------------------------
-- Auswertung.

local function batchSigma(stats: any, values: (b: number) -> number): number
    -- Sigma der Gesamtzahl über Batch-Means: n * sd(Block-Raten) / sqrt(B).
    local batches = stats.batches
    local mean = 0
    local rates = table.create(batches, 0)
    for b = 1, batches do
        rates[b] = values(b) / stats.batchSize[b]
        mean += rates[b]
    end
    mean /= batches
    local ss = 0
    for b = 1, batches do
        ss += (rates[b] - mean) ^ 2
    end
    return stats.openings * math.sqrt(ss / (batches - 1) / batches)
end

local function deviation(count: number, expected: number, sigma: number): number
    if sigma > 0 then
        return (count - expected) / sigma
    end
    return if count == expected then 0 else math.huge
end

-- Wertet einen Lauf aus. Gibt Zeilen und eine Liste verletzter Schwellen zurück.
function M.evaluate(stats: any, thresholds: any?): any
    local limits = thresholds or M.DEFAULT_THRESHOLDS
    local crate = Crates.byId[stats.crateId]
    local hasPity = type(crate.pity) == "table"
    local target = M.targets(crate)
    local n = stats.openings
    local failures: { string } = {}
    local function fail(text: string)
        table.insert(failures, `{stats.crateId}/{M.MODE_NAMES[stats.mode]}: {text}`)
    end
    local sigmaLimit = if hasPity then limits.batchSigma else limits.sigma
    local relLimit = limits.relAt1M * math.sqrt(1e6 / n)
    local pools = M.pools(stats.crateId)

    local rarityRows = {}
    local worstZ, worstRel = 0, 0
    local worstZName, worstRelName = "-", "-"
    for ri, rarity in Rarities.list do
        local p = target.rarity[rarity.id]
        local count = stats.rarityCount[ri]
        local expected = n * p
        local binomial = math.sqrt(n * p * (1 - p))
        local sigma = binomial
        if hasPity and p > 0 then
            sigma = batchSigma(stats, function(b: number): number
                return stats.batchRarity[b][ri]
            end)
        end
        local row: any = {
            id = rarity.id,
            name = rarity.name,
            p = p,
            count = count,
            actual = count / n,
            z = 0,
            rel = 0,
            factor = if binomial > 0 then sigma / binomial else 0,
            relChecked = false,
        }
        if p <= 0 then
            if count > 0 then
                fail(`{rarity.name} hat Quote 0, kam aber {count}-mal`)
            end
        else
            row.z = deviation(count, expected, sigma)
            row.rel = (count - expected) / expected
            if math.abs(row.z) > math.abs(worstZ) then
                worstZ, worstZName = row.z, rarity.name
            end
            if math.abs(row.z) > sigmaLimit then
                fail(`{rarity.name}: {string.format("%.2f", row.z)} Sigma`)
            end
            if p >= limits.relShareMin then
                row.relChecked = true
                if math.abs(row.rel) > math.abs(worstRel) then
                    worstRel, worstRelName = row.rel, rarity.name
                end
                if math.abs(row.rel) >= relLimit then
                    fail(`{rarity.name}: relativ {string.format("%.3f", row.rel * 100)} %`)
                end
            end
        end
        table.insert(rarityRows, row)
    end

    local itemRows = {}
    local pearson, pearsonDf = 0, -1
    local withinChi, withinDf = 0, 0
    for ii, item in stats.items do
        local ri = table.find(Rarities.list, Rarities.byId[item.rarity]) :: number
        local poolSize = #pools[item.rarity]
        local p = target.rarity[item.rarity] / poolSize
        local count = stats.itemCount[ii]
        local expected = n * p
        local binomial = math.sqrt(n * p * (1 - p))
        local sigma = binomial
        if hasPity and p > 0 then
            sigma = batchSigma(stats, function(b: number): number
                return stats.batchItem[b][ii]
            end)
        end
        local row: any = { id = item.id, name = item.name, rarity = item.rarity, p = p, count = count, actual = count / n, z = 0, rel = 0 }
        if p <= 0 then
            if count > 0 then
                fail(`{item.id} hat Quote 0, kam aber {count}-mal`)
            end
        else
            row.z = deviation(count, expected, sigma)
            row.rel = (count - expected) / expected
            if math.abs(row.z) > math.abs(worstZ) then
                worstZ, worstZName = row.z, item.id
            end
            if math.abs(row.z) > sigmaLimit then
                fail(`{item.id}: {string.format("%.2f", row.z)} Sigma`)
            end
            pearson += (count - expected) ^ 2 / expected
            pearsonDf += 1
            -- innerhalb der Seltenheit
            local rarityTotal = stats.rarityCount[ri]
            if rarityTotal > 0 then
                local e = rarityTotal / poolSize
                withinChi += (count - e) ^ 2 / e
            end
        end
        table.insert(itemRows, row)
    end
    for _, rarity in Rarities.list do
        local ri = table.find(Rarities.list, rarity) :: number
        if target.rarity[rarity.id] > 0 and stats.rarityCount[ri] > 0 then
            withinDf += #pools[rarity.id] - 1
        end
    end

    local chi: any = {
        pearson = pearson,
        pearsonDf = pearsonDf,
        pearsonP = M.chiSquareP(pearson, pearsonDf),
        within = withinChi,
        withinDf = withinDf,
        withinP = M.chiSquareP(withinChi, withinDf),
    }
    if hasPity then
        -- Hotelling-T² über die Block-Raten der Seltenheiten mit Quote über 0 (die letzte fällt
        -- weg, die Raten ergeben zusammen 1).
        local used: { number } = {}
        for ri, rarity in Rarities.list do
            if target.rarity[rarity.id] > 0 then
                table.insert(used, ri)
            end
        end
        table.remove(used)
        local dims = #used
        local batches = stats.batches
        local means = table.create(dims, 0)
        local rows: { { number } } = {}
        for b = 1, batches do
            local row = {}
            for k, ri in used do
                row[k] = stats.batchRarity[b][ri] / stats.batchSize[b]
                means[k] += row[k] / batches
            end
            rows[b] = row
        end
        local cov: { { number } } = {}
        for i = 1, dims do
            cov[i] = table.create(dims, 0)
        end
        for b = 1, batches do
            for i = 1, dims do
                for j = 1, dims do
                    cov[i][j] += (rows[b][i] - means[i]) * (rows[b][j] - means[j]) / (batches - 1)
                end
            end
        end
        local d = {}
        for k, ri in used do
            d[k] = stats.rarityCount[ri] / n - target.rarity[Rarities.list[ri].id]
        end
        local x = solve(cov, d)
        local t2 = math.huge
        if x ~= nil then
            t2 = 0
            for k = 1, dims do
                t2 += d[k] * x[k]
            end
            t2 *= batches
        end
        local f = (batches - dims) / (dims * (batches - 1)) * t2
        chi.hotelling = t2
        chi.hotellingF = f
        chi.hotellingDf1 = dims
        chi.hotellingDf2 = batches - dims
        chi.hotellingP = if t2 == math.huge then 0 else M.fTestP(f, dims, batches - dims)
        if chi.withinP <= limits.pMin then
            fail(`Chi-Quadrat Items je Seltenheit p = {chi.withinP}`)
        end
        if chi.hotellingP <= limits.pMin then
            fail(`Hotelling-T² Seltenheiten p = {chi.hotellingP}`)
        end
    elseif chi.pearsonP <= limits.pMin then
        fail(`Chi-Quadrat p = {chi.pearsonP}`)
    end

    local pity: any = nil
    if hasPity then
        pity = {
            limitEpic = crate.pity.epic,
            limitLegendary = crate.pity.legendary,
            maxNoEpic = stats.maxNoEpic,
            maxNoLegendary = stats.maxNoLegendary,
            triggers = {},
        }
        if stats.maxNoEpic > crate.pity.epic - 1 then
            fail(`{stats.maxNoEpic} Öffnungen ohne Episch+ (Grenze {crate.pity.epic - 1})`)
        end
        if stats.maxNoLegendary > crate.pity.legendary - 1 then
            fail(`{stats.maxNoLegendary} Öffnungen ohne Legendär+ (Grenze {crate.pity.legendary - 1})`)
        end
        for k, tier in { "epic", "legendary" } do
            local p = target.triggers[tier]
            local count = stats.triggers[tier]
            local sigma = batchSigma(stats, function(b: number): number
                return stats.batchTrigger[b][k]
            end)
            local z = deviation(count, n * p, sigma)
            table.insert(pity.triggers, { tier = tier, p = p, count = count, actual = count / n, z = z })
            if math.abs(z) > sigmaLimit then
                fail(`Garantie {tier}: {string.format("%.2f", z)} Sigma`)
            end
        end
    end

    -- Ablauf-Kontrollen (müssen 0 sein).
    local controls = {
        { name = "Fehlgeschlagene Käufe", value = stats.failedCalls },
        { name = "Unerwartete Items (nicht im Pool oder falsche Seltenheit)", value = stats.unexpectedItems },
        { name = "Bezahlung falsch (Gems bzw. Münzen)", value = stats.paymentMismatch },
        { name = "Inventar weicht von der Zählung ab", value = stats.inventoryMismatch },
        { name = "pityTriggered weicht vom Zählerstand ab", value = stats.triggerMismatch },
        { name = "Pity-Zähler im Profil weicht ab", value = stats.counterMismatch },
        { name = "Öffnungen fehlen", value = stats.openings - stats.openingsSeen },
    }
    for _, control in controls do
        if control.value ~= 0 then
            fail(`{control.name}: {control.value}`)
        end
    end
    if target.crossDiff > limits.crossCheck then
        fail(`Sollwerte: longRunRates weicht um {target.crossDiff} von der eigenen Rechnung ab`)
    end
    if stats.firstFailure ~= nil then
        fail(`erster Fehlschlag: {stats.firstFailure}`)
    end

    return {
        crateId = stats.crateId,
        mode = stats.mode,
        openings = n,
        calls = stats.calls,
        hasPity = hasPity,
        sigmaLimit = sigmaLimit,
        relLimit = relLimit,
        rarityRows = rarityRows,
        itemRows = itemRows,
        chi = chi,
        pity = pity,
        controls = controls,
        crossDiff = target.crossDiff,
        worstZ = worstZ,
        worstZName = worstZName,
        worstRel = worstRel,
        worstRelName = worstRelName,
        failures = failures,
    }
end

-- Alle Kisten, beide Modi. Gibt { { stats, eval } } in fester Reihenfolge zurück.
function M.runAll(target: number, seed: number, batches: number, thresholds: any?, onRun: ((any, any) -> ())?): { any }
    local runs = {}
    for crateIndex, crate in Crates.list do
        for modeIndex, mode in M.MODES do
            local stats = M.simulate(crate.id, mode, target, M.runSeed(seed, crateIndex, modeIndex), batches)
            local eval = M.evaluate(stats, thresholds)
            table.insert(runs, { stats = stats, eval = eval })
            if onRun then
                onRun(stats, eval)
            end
        end
    end
    return runs
end

return M
