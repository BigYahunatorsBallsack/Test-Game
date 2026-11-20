--!strict
-- Paket 4.2: Kisten auswürfeln (Logic/CrateRoll). Quoten-Simulation, Pity, feste Zufallsfolgen,
-- Anzeige und Auswurf aus derselben Tabelle.
--
-- Die Simulationen nutzen math.random mit festem Startwert: Das Ergebnis ist bei jedem Lauf
-- gleich (kein zufälliges Rot), geprüft wird trotzdem gegen die Streuung (4 Standardabweichungen).

local T = require("./lib/expect")
local CrateRoll = require("../src/shared/Logic/CrateRoll")
local Crates = require("../src/shared/Data/Crates")
local CrateItems = require("../src/shared/Data/CrateItems")
local Rarities = require("../src/shared/Data/Rarities")

-- Öffnungen je Kiste in den Simulationen (Plan: 200.000). Dauer siehe Ausgabe am Ende jedes Blocks.
local SIMULATION_OPENINGS = 200_000
local SIGMA_LIMIT = 4
local SEED = 4242
-- Referenz des balance-analyst (docs/balance/crates_4_2.md, "Sollwerte für Lune", exakt mit Brüchen
-- gerechnet), Goldkiste mit Pity 15/60. Ändern sich Quoten oder Grenzen, muss die Rechnung dort neu.
local BALANCE_LEGENDARY_PLUS = 0.053868
local BALANCE_EPIC_PLUS = 0.208823
local BALANCE_MYTHIC = 0.005387
local BALANCE_ROUNDING = 5e-7 -- die Referenz ist auf 6 Stellen gerundet

-- Zufallsfolge aus festen Werten. Wirft, wenn sie aufgebraucht ist (dann stimmt der Test nicht).
local function sequence(values: { number }): () -> number
    local index = 0
    return function(): number
        index += 1
        local value = values[index]
        if value == nil then
            error(`Zufallsfolge nach {index - 1} Werten aufgebraucht`)
        end
        return value
    end
end

-- Immer derselbe Wert (für lange Folgen).
local function constant(value: number): () -> number
    return function(): number
        return value
    end
end

local gold = Crates.byId.gold
local event = Crates.byId.event
local wood = Crates.byId.wood

-- Rang einer Seltenheit.
local function rank(rarityId: string): number
    return Rarities.byId[rarityId].rank
end

-- Exakte Rate "Legendär oder besser" (und "Episch oder besser") bei Pity, über die stationäre
-- Verteilung der Markov-Kette über (sinceEpic, sinceLegendary). Liest Quoten und Grenzen aus der
-- Kiste, rechnet aber unabhängig von CrateRoll (eigene Übergänge).
local function exactPityRates(crate: any): (number, number, number)
    local odds = crate.odds
    local E, L = crate.pity.epic, crate.pity.legendary
    local pLeg, pEpic, pBelow = 0, 0, 0
    for _, rarity in Rarities.list do
        local share = (odds[rarity.id] or 0) / 10000
        if rarity.rank >= rank("legendary") then
            pLeg += share
        elseif rarity.rank >= rank("epic") then
            pEpic += share
        else
            pBelow += share
        end
    end
    -- Wahrscheinlichkeiten je Zustand: (Legendär+, Episch, darunter)
    local function outcome(e: number, l: number): (number, number, number)
        if l >= L - 1 then
            return 1, 0, 0
        elseif e >= E - 1 then
            local total = pLeg + pEpic
            return pLeg / total, pEpic / total, 0
        end
        return pLeg, pEpic, pBelow
    end
    local function index(e: number, l: number): number
        return l * E + e + 1
    end
    local states = E * L
    local dist = table.create(states, 0)
    dist[index(0, 0)] = 1
    for _ = 1, 100_000 do
        local nextDist = table.create(states, 0)
        for l = 0, L - 1 do
            for e = 0, E - 1 do
                local mass = dist[index(e, l)]
                if mass > 0 then
                    local a, b, c = outcome(e, l)
                    nextDist[index(0, 0)] += mass * a
                    if b > 0 then
                        nextDist[index(0, math.min(l + 1, L - 1))] += mass * b
                    end
                    if c > 0 then
                        nextDist[index(math.min(e + 1, E - 1), math.min(l + 1, L - 1))] += mass * c
                    end
                end
            end
        end
        local delta = 0
        for i = 1, states do
            delta = math.max(delta, math.abs(nextDist[i] - dist[i]))
        end
        dist = nextDist
        if delta < 1e-16 then
            break
        end
    end
    local rateLeg, rateEpicPlus, rateMythic = 0, 0, 0
    local mythicShareOfLeg = (odds.mythic or 0) / ((odds.legendary or 0) + (odds.mythic or 0))
    for l = 0, L - 1 do
        for e = 0, E - 1 do
            local mass = dist[index(e, l)]
            local a, b = outcome(e, l)
            rateLeg += mass * a
            rateEpicPlus += mass * (a + b)
            rateMythic += mass * a * mythicShareOfLeg
        end
    end
    return rateLeg, rateEpicPlus, rateMythic
end

-- Gegenprobe über die Erneuerungsrechnung: Rate = 1 / erwarteter Abstand zwischen zwei
-- Legendär-oder-besser. Nach einem Legendär ist sinceLegendary bei der n-ten Öffnung n - 1, darum
-- reicht die Verteilung über sinceEpic.
local function renewalLegendaryRate(crate: any): number
    local odds = crate.odds
    local E, L = crate.pity.epic, crate.pity.legendary
    local pLeg = ((odds.legendary or 0) + (odds.mythic or 0)) / 10000
    local pEpic = (odds.epic or 0) / 10000
    local pBelow = 1 - pLeg - pEpic
    local dist = table.create(E, 0) -- dist[e + 1]: noch kein Legendär, sinceEpic = e
    dist[1] = 1
    local expected = 0
    for n = 1, L do
        local alive = 0
        for e = 0, E - 1 do
            alive += dist[e + 1]
        end
        expected += alive -- P(T >= n)
        if n == L then
            break
        end
        local nextDist = table.create(E, 0)
        for e = 0, E - 1 do
            local mass = dist[e + 1]
            if e >= E - 1 then
                local total = pLeg + pEpic
                nextDist[1] += mass * pEpic / total
            else
                nextDist[1] += mass * pEpic
                nextDist[e + 2] += mass * pBelow
            end
        end
        dist = nextDist
    end
    return 1 / expected
end

local function withinSigma(count: number, n: number, p: number): (boolean, number)
    local sigma = math.sqrt(n * p * (1 - p))
    local deviation = math.abs(count - n * p)
    return deviation <= SIGMA_LIMIT * sigma + 1e-9, if sigma > 0 then deviation / sigma else 0
end

T.describe("Anzeige und Auswurf lesen dieselbe Tabelle", function()
    T.it("displayOdds liefert dieselbe Referenz und dieselben Zahlen wie Crates.byId[id].odds", function()
        for _, crate in Crates.list do
            local display = CrateRoll.displayOdds(crate.id) :: any
            T.expect(display ~= nil).toBe(true)
            T.expect(rawequal(display.odds, crate.odds)).toBe(true)
            T.expect(rawequal(display.odds, CrateRoll.oddsOf(crate))).toBe(true)
            T.expect(#display.rows).toBe(#Rarities.list)
            local sum = 0
            for index, row in display.rows do
                T.expect(row.rarityId).toBe(Rarities.list[index].id) -- Reihenfolge nach Rang
                T.expect(row.odds).toBe(crate.odds[row.rarityId] or 0)
                T.expect(row.name).toBe(Rarities.list[index].name)
                sum += row.odds
            end
            T.expect(sum).toBe(10000)
            T.expect(rawequal(display.pity, crate.pity)).toBe(true)
        end
        T.expect(CrateRoll.displayOdds("gibt_es_nicht")).toBeNil()
    end)

    T.it("die Event-Kiste zeigt dieselben Quoten wie die Goldkiste", function()
        local a = CrateRoll.displayOdds("gold") :: any
        local b = CrateRoll.displayOdds("event") :: any
        T.expect(rawequal(a.odds, b.odds)).toBe(true)
        T.expect(a.rows).toEqual(b.rows)
    end)

    T.it("eine geänderte Tabelle ändert Anzeige und Wurf zugleich (eine Quelle)", function()
        local odds = { common = 0, uncommon = 0, rare = 0, epic = 0, legendary = 0, mythic = 10000 }
        local crate = { id = "test", odds = odds, eventOnly = false }
        local items = {
            list = {
                { id = "m1", kind = "skin", name = "M1", rarity = "mythic", crates = { "test" }, effectBp = 0 },
                { id = "c1", kind = "skin", name = "C1", rarity = "common", crates = { "test" }, effectBp = 0 },
            },
        }
        local data = { Crates = { byId = { test = crate }, list = { crate } }, CrateItems = items }
        local display = CrateRoll.displayOdds("test", data) :: any
        T.expect(display.rows[6].odds).toBe(10000)
        for i = 1, 50 do
            local roll = CrateRoll.roll(crate, nil, constant((i - 1) / 50), data)
            T.expect(roll.rarityId).toBe("mythic")
        end
        -- Dieselbe Tabelle umstellen: Anzeige (Referenz) und Wurf folgen sofort.
        odds.mythic = 0
        odds.common = 10000
        T.expect(display.odds.common).toBe(10000)
        T.expect((CrateRoll.displayOdds("test", data) :: any).rows[1].odds).toBe(10000)
        T.expect(CrateRoll.roll(crate, nil, constant(0.5), data).rarityId).toBe("common")
    end)
end)

T.describe("Seltenheit und Item nach Tabelle (feste Zufallswerte)", function()
    T.it("die Lose 1 bis 10000 verteilen sich in Rang-Reihenfolge nach der Quote", function()
        -- Gold: uncommon 1-4000, rare 4001-8000, epic 8001-9500, legendary 9501-9950, mythic 9951-10000
        local cases = {
            { 0, "uncommon" },
            { 0.3999, "uncommon" },
            { 0.4, "rare" },
            { 0.7999, "rare" },
            { 0.8, "epic" },
            { 0.9499, "epic" },
            { 0.95, "legendary" },
            { 0.9949, "legendary" },
            { 0.995, "mythic" },
            { 0.99999, "mythic" },
        }
        for _, case in cases do
            T.expect(CrateRoll.pickRarity(gold.odds, case[1])).toBe(case[2])
        end
        -- Holz: Quote 0 bei Legendär und Mythisch, auch das letzte Los ist Episch.
        T.expect(CrateRoll.pickRarity(wood.odds, 0)).toBe("common")
        T.expect(CrateRoll.pickRarity(wood.odds, 0.99999)).toBe("epic")
    end)

    T.it("das Item kommt gleich verteilt aus dem Pool der Kiste mit dieser Seltenheit", function()
        local pool = CrateRoll.pool("gold", "mythic")
        T.expect(#pool >= 1).toBe(true)
        local first = CrateRoll.roll(gold, nil, sequence({ 0.999, 0 }))
        T.expect(first.rarityId).toBe("mythic")
        T.expect(first.item).toBe(pool[1])
        local last = CrateRoll.roll(gold, nil, sequence({ 0.999, 0.99999 }))
        T.expect(last.item).toBe(pool[#pool])
        for _, item in pool do
            T.expect(item.rarity).toBe("mythic")
            T.expect(table.find(item.crates, "gold") ~= nil).toBe(true)
        end
    end)

    T.it("die Event-Kiste würfelt nur Event-Items, die anderen Kisten nie Event-Items", function()
        math.randomseed(SEED)
        for _ = 1, 2000 do
            local roll = CrateRoll.roll(event, nil, math.random)
            T.expect(roll.item.crates).toEqual({ "event" })
            local other = CrateRoll.roll(gold, nil, math.random)
            T.expect(table.find(other.item.crates, "event")).toBeNil()
        end
    end)

    T.it("ein Zufallswert außerhalb von [0, 1) ist ein Fehler, kein stiller Wurf", function()
        for _, bad in { 1, 1.5, -0.01, 0 / 0, math.huge } do
            T.expect(function()
                CrateRoll.roll(gold, nil, constant(bad))
            end).toThrow("Zufallswert")
        end
        T.expect(function()
            CrateRoll.roll(gold, nil, (function()
                return "x"
            end) :: any)
        end).toThrow("Zufallswert")
    end)

    T.it("ein leerer Pool ist ein Fehler", function()
        local crate = { id = "leer", odds = { common = 10000 }, eventOnly = false }
        local data = { Crates = { byId = { leer = crate }, list = { crate } }, CrateItems = { list = {} } }
        T.expect(function()
            CrateRoll.roll(crate, nil, constant(0), data)
        end).toThrow("keine Items")
    end)
end)

T.describe("Pity mit festem Zufall", function()
    T.it("die 15. Öffnung ohne Episch ist Episch oder besser", function()
        local counters: any = nil
        for opening = 1, 15 do
            local roll = CrateRoll.roll(gold, counters, constant(0))
            if opening < 15 then
                T.expect(roll.rarityId).toBe("uncommon")
                T.expect(roll.pityTriggered).toBeNil()
            else
                T.expect(rank(roll.rarityId) >= rank("epic")).toBe(true)
                T.expect(roll.pityTriggered).toBe("epic")
            end
            counters = roll.pity
        end
        T.expect(counters).toEqual({ sinceEpic = 0, sinceLegendary = 15 })
    end)

    T.it("bei sinceEpic = 13 greift noch nichts, bei 14 die Episch-Garantie im Verhältnis der Tabelle", function()
        T.expect(CrateRoll.guarantee(gold, { sinceEpic = 13, sinceLegendary = 13 })).toBeNil()
        T.expect(CrateRoll.roll(gold, { sinceEpic = 13, sinceLegendary = 13 }, constant(0)).rarityId).toBe("uncommon")
        local at14 = { sinceEpic = 14, sinceLegendary = 14 }
        T.expect(CrateRoll.guarantee(gold, at14)).toBe("epic")
        -- Unter Episch und besser: epic 1-1500, legendary 1501-1950, mythic 1951-2000 (von 2000)
        T.expect(CrateRoll.roll(gold, at14, sequence({ 0, 0 })).rarityId).toBe("epic")
        T.expect(CrateRoll.roll(gold, at14, sequence({ 0.7499, 0 })).rarityId).toBe("epic")
        T.expect(CrateRoll.roll(gold, at14, sequence({ 0.75, 0 })).rarityId).toBe("legendary")
        T.expect(CrateRoll.roll(gold, at14, sequence({ 0.9749, 0 })).rarityId).toBe("legendary")
        T.expect(CrateRoll.roll(gold, at14, sequence({ 0.975, 0 })).rarityId).toBe("mythic")
    end)

    T.it("die 60. Öffnung ohne Legendär ist Legendär oder besser (auch wenn Episch zugleich fällig ist)", function()
        local counters: any = nil
        local epicPities = {}
        for opening = 1, 60 do
            local roll = CrateRoll.roll(gold, counters, constant(0))
            if roll.pityTriggered == "epic" then
                table.insert(epicPities, opening)
            end
            if opening == 60 then
                T.expect(roll.pityTriggered).toBe("legendary")
                T.expect(rank(roll.rarityId) >= rank("legendary")).toBe(true)
            else
                T.expect(rank(roll.rarityId) < rank("legendary")).toBe(true)
            end
            counters = roll.pity
        end
        T.expect(epicPities).toEqual({ 15, 30, 45 })
        T.expect(counters).toEqual({ sinceEpic = 0, sinceLegendary = 0 })
    end)

    T.it("greifen beide Garantien, gewinnt Legendär; gewürfelt wird unter Legendär und Mythisch", function()
        local both = { sinceEpic = 14, sinceLegendary = 59 }
        T.expect(CrateRoll.guarantee(gold, both)).toBe("legendary")
        -- legendary 1-450, mythic 451-500 (von 500)
        T.expect(CrateRoll.roll(gold, both, sequence({ 0, 0 })).rarityId).toBe("legendary")
        T.expect(CrateRoll.roll(gold, both, sequence({ 0.8999, 0 })).rarityId).toBe("legendary")
        T.expect(CrateRoll.roll(gold, both, sequence({ 0.9, 0 })).rarityId).toBe("mythic")
        local onlyLegendary = { sinceEpic = 3, sinceLegendary = 59 }
        T.expect(CrateRoll.roll(gold, onlyLegendary, sequence({ 0, 0 })).pityTriggered).toBe("legendary")
    end)

    T.it("Zähler: Legendär oder Mythisch setzt beide zurück, Episch nur sinceEpic, sonst beide +1", function()
        local start = { sinceEpic = 7, sinceLegendary = 30 }
        T.expect(CrateRoll.roll(gold, start, sequence({ 0.95, 0 })).pity).toEqual({ sinceEpic = 0, sinceLegendary = 0 })
        T.expect(CrateRoll.roll(gold, start, sequence({ 0.995, 0 })).pity).toEqual({ sinceEpic = 0, sinceLegendary = 0 })
        T.expect(CrateRoll.roll(gold, start, sequence({ 0.8, 0 })).pity).toEqual({ sinceEpic = 0, sinceLegendary = 31 })
        T.expect(CrateRoll.roll(gold, start, sequence({ 0.4, 0 })).pity).toEqual({ sinceEpic = 8, sinceLegendary = 31 })
        T.expect(CrateRoll.roll(gold, start, sequence({ 0, 0 })).pity).toEqual({ sinceEpic = 8, sinceLegendary = 31 })
        -- Der übergebene Zählerstand bleibt unverändert (neue Tabelle).
        T.expect(start).toEqual({ sinceEpic = 7, sinceLegendary = 30 })
    end)

    T.it("Kisten ohne Pity haben keine Garantie und ändern keinen Zähler", function()
        local big = { sinceEpic = 500, sinceLegendary = 500 }
        T.expect(CrateRoll.guarantee(wood, big)).toBeNil()
        local roll = CrateRoll.roll(wood, big, sequence({ 0, 0 }))
        T.expect(roll.rarityId).toBe("common")
        T.expect(roll.pityTriggered).toBeNil()
        T.expect(roll.pity).toBeNil()
        T.expect(CrateRoll.advance(Crates.byId.iron, big, "epic")).toBeNil()
    end)

    T.it("die Event-Kiste hat dieselben Grenzen wie Gold (15/60) in eigener Tabelle", function()
        T.expect(event.pity).toEqual({ epic = 15, legendary = 60 })
        T.expect(rawequal(event.pity, gold.pity)).toBe(false)
        local roll = CrateRoll.roll(event, { sinceEpic = 14, sinceLegendary = 0 }, sequence({ 0, 0 }))
        T.expect(roll.pityTriggered).toBe("epic")
        T.expect(roll.rarityId).toBe("epic")
        T.expect(roll.item.crates).toEqual({ "event" })
    end)

    T.it("kaputte Zählerstände zählen als 0", function()
        T.expect(CrateRoll.counters(nil)).toEqual({ sinceEpic = 0, sinceLegendary = 0 })
        T.expect(CrateRoll.counters({ sinceEpic = -3, sinceLegendary = 0 / 0 })).toEqual({ sinceEpic = 0, sinceLegendary = 0 })
        T.expect(CrateRoll.counters({ sinceEpic = 4.7, sinceLegendary = "9" })).toEqual({ sinceEpic = 4, sinceLegendary = 0 })
    end)
end)

T.describe(`Simulation: {SIMULATION_OPENINGS} Öffnungen je Kiste ohne Pity`, function()
    for _, crate in Crates.list do
        T.it(`{crate.id}: jede Seltenheit innerhalb von {SIGMA_LIMIT} Standardabweichungen, 0 % nie`, function()
            math.randomseed(SEED)
            local started = os.clock()
            local counts: { [string]: number } = {}
            local itemCounts: { [string]: number } = {}
            for _ = 1, SIMULATION_OPENINGS do
                -- Zählerstand nil bei jeder Öffnung: die Pity greift nie, gemessen wird die reine Tabelle.
                local roll = CrateRoll.roll(crate, nil, math.random)
                counts[roll.rarityId] = (counts[roll.rarityId] or 0) + 1
                itemCounts[roll.item.id] = (itemCounts[roll.item.id] or 0) + 1
                if roll.item.rarity ~= roll.rarityId then
                    error(`Item {roll.item.id} hat nicht die gewürfelte Seltenheit {roll.rarityId}`)
                end
            end
            local worst = 0
            for _, rarity in Rarities.list do
                local share = crate.odds[rarity.id] or 0
                local count = counts[rarity.id] or 0
                if share == 0 then
                    T.expect(count).toBe(0)
                else
                    local ok, sigmas = withinSigma(count, SIMULATION_OPENINGS, share / 10000)
                    worst = math.max(worst, sigmas)
                    if not ok then
                        error(`{crate.id}/{rarity.id}: {count} statt {SIMULATION_OPENINGS * share / 10000} ({sigmas} Sigma)`)
                    end
                    -- Innerhalb der Seltenheit gleich verteilt.
                    local pool = CrateRoll.pool(crate.id, rarity.id)
                    for _, item in pool do
                        local itemOk, itemSigmas = withinSigma(itemCounts[item.id] or 0, SIMULATION_OPENINGS, share / 10000 / #pool)
                        if not itemOk then
                            error(`{crate.id}/{item.id}: {itemCounts[item.id]} ({itemSigmas} Sigma)`)
                        end
                    end
                end
            end
            print(`      {crate.id}: größte Abweichung {string.format("%.2f", worst)} Sigma, {string.format("%.2f", os.clock() - started)} s`)
        end)
    end
end)

T.describe("Pity-Simulation Goldkiste", function()
    T.it("die exakte Markov-Rechnung stimmt mit der Erneuerungsrechnung überein", function()
        local rateLeg, rateEpic, rateMythic = exactPityRates(gold)
        local renewal = renewalLegendaryRate(gold)
        T.expect(rateLeg).toBeCloseTo(renewal, 1e-12)
        T.expect(rateLeg > 0.05).toBe(true) -- Pity hebt die Rate über die Tabelle (5 %)
        T.expect(rateEpic > 0.20).toBe(true)
        -- Gleich dem Wert des balance-analyst (unabhängige Rechnung in Python mit Brüchen).
        T.expect(rateLeg).toBeCloseTo(BALANCE_LEGENDARY_PLUS, BALANCE_ROUNDING)
        T.expect(rateEpic).toBeCloseTo(BALANCE_EPIC_PLUS, BALANCE_ROUNDING)
        T.expect(rateMythic).toBeCloseTo(BALANCE_MYTHIC, BALANCE_ROUNDING)
        -- Die Event-Kiste hat dieselben Quoten und Grenzen, also dieselben Raten.
        local eventLeg = exactPityRates(event)
        T.expect(eventLeg).toBeCloseTo(rateLeg, 1e-15)
        print(`      exakt: Legendär+ {string.format("%.6f", rateLeg)}, Episch+ {string.format("%.6f", rateEpic)}, Mythisch {string.format("%.6f", rateMythic)}`)
    end)

    T.it(`in {SIMULATION_OPENINGS} Öffnungen nie mehr als 14 ohne Episch+ und 59 ohne Legendär+, Rate wie exakt`, function()
        math.randomseed(SEED + 1)
        local started = os.clock()
        local counters: any = nil
        local withoutEpic, withoutLegendary = 0, 0
        local maxWithoutEpic, maxWithoutLegendary = 0, 0
        local legendaryPlus, epicPlus, mythic = 0, 0, 0
        for _ = 1, SIMULATION_OPENINGS do
            local roll = CrateRoll.roll(gold, counters, math.random)
            counters = roll.pity
            local r = rank(roll.rarityId)
            if r >= rank("epic") then
                epicPlus += 1
                withoutEpic = 0
            else
                withoutEpic += 1
                maxWithoutEpic = math.max(maxWithoutEpic, withoutEpic)
            end
            if r >= rank("legendary") then
                legendaryPlus += 1
                withoutLegendary = 0
            else
                withoutLegendary += 1
                maxWithoutLegendary = math.max(maxWithoutLegendary, withoutLegendary)
            end
            if roll.rarityId == "mythic" then
                mythic += 1
            end
            -- Der Zählerstand entspricht immer der gezählten Strecke.
            if counters.sinceEpic ~= withoutEpic or counters.sinceLegendary ~= withoutLegendary then
                error("Zähler und gezählte Strecke laufen auseinander")
            end
        end
        T.expect(maxWithoutEpic <= gold.pity.epic - 1).toBe(true)
        T.expect(maxWithoutLegendary <= gold.pity.legendary - 1).toBe(true)
        local rateLeg, rateEpic, rateMythic = exactPityRates(gold)
        -- Die binomiale Streuung ist eine obere Schranke: Pity macht die Folge gleichmäßiger.
        for _, check in { { "Legendär+", legendaryPlus, rateLeg }, { "Episch+", epicPlus, rateEpic }, { "Mythisch", mythic, rateMythic } } do
            local ok, sigmas = withinSigma(check[2] :: number, SIMULATION_OPENINGS, check[3] :: number)
            if not ok then
                error(`{check[1]}: {check[2]} statt {SIMULATION_OPENINGS * (check[3] :: number)} ({sigmas} Sigma)`)
            end
        end
        print(
            `      simuliert: Legendär+ {string.format("%.6f", legendaryPlus / SIMULATION_OPENINGS)}, längste Strecke ohne Episch+ {maxWithoutEpic}, ohne Legendär+ {maxWithoutLegendary}, {string.format("%.2f", os.clock() - started)} s`
        )
    end)
end)

-- ===================================================================================================
-- Paket 4.6: Quoten der nächsten Öffnung (effectiveOdds), Quote je Item (itemOdds), Langzeitraten.
-- ===================================================================================================

-- Werte des balance-analyst (docs/balance/directshop_4_6.md, exakte Brüche, auf 10 Stellen gerundet).
local BALANCE_GOLD_RATES = {
    common = 0,
    uncommon = 0.3955884537,
    rare = 0.3955884537,
    epic = 0.1549552381,
    legendary = 0.0484810690,
    mythic = 0.0053867854,
}
local BALANCE_10_DIGITS = 5e-11

-- Alle Zählerstände einer Kiste mit Pity (0 bis Grenze - 1 je Zähler), sonst nur nil.
local function counterStates(crate: any): { any }
    if crate.pity == nil then
        return { false }
    end
    local states = {}
    for l = 0, crate.pity.legendary - 1 do
        for e = 0, crate.pity.epic - 1 do
            table.insert(states, { sinceEpic = e, sinceLegendary = l })
        end
    end
    return states
end

local function stateOf(value: any): any
    return if value == false then nil else value
end

-- Der Wurf, wie er vor Paket 4.6 war (Kopie aus CrateRoll, unverändert): Seltenheit über
-- pickRarity mit Mindest-Rang, dann Item gleich verteilt. Dient als Vergleich für den neuen Weg
-- über effectiveOdds.
local function oldPickRarity(odds: { [string]: number }, r: number, minRank: number?): string
    local floorRank = minRank or 1
    local eligible: { { id: string, share: number } } = {}
    local total = 0
    for _, rarity in Rarities.list do
        local share = odds[rarity.id]
        if rarity.rank >= floorRank and type(share) == "number" and share > 0 then
            table.insert(eligible, { id = rarity.id, share = share })
            total += share
        end
    end
    if total <= 0 then
        error(`CrateRoll: keine Seltenheit ab Rang {floorRank} mit Quote über 0`)
    end
    local ticket = math.min(math.floor(r * total) + 1, total)
    local upper = 0
    for _, entry in eligible do
        upper += entry.share
        if ticket <= upper then
            return entry.id
        end
    end
    return eligible[#eligible].id
end

local function oldRoll(crate: any, counters: any, random: () -> number): any
    local tier = CrateRoll.guarantee(crate, counters)
    local minRank = if tier then rank(tier) else 1
    local r = random()
    if type(r) ~= "number" or r ~= r or r < 0 or r >= 1 then
        error("Zufallswert")
    end
    local rarityId = oldPickRarity(crate.odds, r, minRank)
    local pool = CrateRoll.pool(crate.id, rarityId)
    local index = math.min(math.floor(random() * #pool) + 1, #pool)
    return {
        itemId = pool[index].id,
        rarityId = rarityId,
        pityTriggered = tier,
        pity = CrateRoll.advance(crate, counters, rarityId),
    }
end

T.describe("effectiveOdds (4.6): Quoten der nächsten Öffnung", function()
    T.it("für jede Kiste und jeden Pity-Stand ergibt die Summe 100 %, mit Garantie nur Seltenheiten ab der Stufe", function()
        local checked = 0
        for _, crate in Crates.list do
            for _, raw in counterStates(crate) do
                local counters = stateOf(raw)
                local effective = CrateRoll.effectiveOdds(crate, counters)
                local tier = CrateRoll.guarantee(crate, counters)
                T.expect(effective.guarantee).toBe(tier)
                local sum = 0
                for _, rarity in Rarities.list do
                    local weight = effective.odds[rarity.id] or 0
                    sum += weight
                    if tier ~= nil and rarity.rank < rank(tier) then
                        T.expect(weight).toBe(0)
                    elseif weight > 0 then
                        T.expect(weight).toBe(crate.odds[rarity.id]) -- Gewicht aus der Tabelle
                    end
                end
                T.expect(sum).toBe(effective.total)
                local percent = 0
                for _, rarity in Rarities.list do
                    percent += (effective.odds[rarity.id] or 0) / effective.total * 100
                end
                T.expect(percent).toBeCloseTo(100, 1e-9)
                if tier == nil then
                    T.expect(rawequal(effective.odds, crate.odds)).toBe(true) -- dieselbe Referenz
                    T.expect(effective.total).toBe(10000)
                else
                    T.expect(rawequal(effective.odds, crate.odds)).toBe(false) -- neue Tabelle
                end
                checked += 1
            end
        end
        T.expect(checked).toBe(1 + 1 + 15 * 60 * 2)
    end)

    T.it("Gold kurz vor der Episch-Garantie: 75 / 22,5 / 2,5 %; vor Legendär: 90 / 10 %", function()
        local epic = CrateRoll.effectiveOdds(gold, { sinceEpic = 14, sinceLegendary = 14 })
        T.expect(epic.guarantee).toBe("epic")
        T.expect(epic.total).toBe(2000)
        T.expect(epic.odds).toEqual({ common = 0, uncommon = 0, rare = 0, epic = 1500, legendary = 450, mythic = 50 })
        local legendary = CrateRoll.effectiveOdds(gold, { sinceEpic = 14, sinceLegendary = 59 })
        T.expect(legendary.guarantee).toBe("legendary")
        T.expect(legendary.total).toBe(500)
        T.expect(legendary.odds.legendary / legendary.total).toBe(0.9)
        T.expect(legendary.odds.mythic / legendary.total).toBe(0.1)
        local none = CrateRoll.effectiveOdds(gold, { sinceEpic = 13, sinceLegendary = 58 })
        T.expect(none.guarantee).toBeNil()
    end)

    T.it("die Quotentabelle der Daten wird nie verändert", function()
        local before = table.clone(gold.odds)
        for _, raw in counterStates(gold) do
            local effective = CrateRoll.effectiveOdds(gold, stateOf(raw))
            if effective.guarantee ~= nil then
                effective.odds.mythic = 9999 -- eine Änderung am Ergebnis wirkt nicht zurück
            end
        end
        T.expect(gold.odds).toEqual(before)
        T.expect(rawequal(event.odds, gold.odds)).toBe(true)
    end)

    T.it("roll würfelt über effectiveOdds: für feste Zufallsfolgen dasselbe Ergebnis wie vor 4.6", function()
        local compared = 0
        for _, crate in Crates.list do
            local states = counterStates(crate)
            for seed = 1, 40 do
                math.randomseed(SEED * 100 + seed)
                local values: { number } = {}
                for i = 1, 2 * #states do
                    values[i] = math.random()
                end
                -- Ränder der Lose dazu: 0 und knapp unter 1.
                table.insert(values, 0)
                table.insert(values, 0.9999999999)
                for index, raw in states do
                    local counters = stateOf(raw)
                    for _, pair in { { values[2 * index - 1], values[2 * index] }, { values[#values - 1], values[#values] }, { values[#values], values[#values - 1] } } do
                        local newRoll = CrateRoll.roll(crate, counters, sequence({ pair[1], pair[2] }))
                        local old = oldRoll(crate, counters, sequence({ pair[1], pair[2] }))
                        if newRoll.item.id ~= old.itemId or newRoll.rarityId ~= old.rarityId or newRoll.pityTriggered ~= old.pityTriggered then
                            error(`{crate.id} bei {pair[1]}/{pair[2]}: neu {newRoll.item.id}, alt {old.itemId}`)
                        end
                        T.expect(newRoll.pity).toEqual(old.pity)
                        compared += 1
                    end
                end
            end
        end
        print(`      {compared} Würfe mit festen Zufallswerten verglichen`)
    end)

    T.it("Simulation: bei anstehender Garantie trifft der Wurf die angezeigten Quoten", function()
        math.randomseed(SEED + 2)
        local openings = 60_000
        for _, counters in { { sinceEpic = 14, sinceLegendary = 20 }, { sinceEpic = 3, sinceLegendary = 59 }, { sinceEpic = 0, sinceLegendary = 0 } } do
            local effective = CrateRoll.effectiveOdds(gold, counters)
            local counts: { [string]: number } = {}
            for _ = 1, openings do
                local roll = CrateRoll.roll(gold, counters, math.random)
                counts[roll.rarityId] = (counts[roll.rarityId] or 0) + 1
            end
            for _, rarity in Rarities.list do
                local p = (effective.odds[rarity.id] or 0) / effective.total
                local count = counts[rarity.id] or 0
                if p == 0 then
                    T.expect(count).toBe(0)
                else
                    local ok, sigmas = withinSigma(count, openings, p)
                    if not ok then
                        error(`{rarity.id}: {count} statt {openings * p} ({sigmas} Sigma)`)
                    end
                end
            end
        end
    end)
end)

T.describe("itemOdds (4.6): Quote je Item", function()
    T.it("jedes Item jeder Kiste kommt vor, Quote = Seltenheits-Quote / Poolgröße, exakte Summe 100 %", function()
        for _, crate in Crates.list do
            for _, raw in counterStates(crate) do
                local counters = stateOf(raw)
                local effective = CrateRoll.effectiveOdds(crate, counters)
                local entries = CrateRoll.itemOdds(crate.id, counters)
                local seen: { [string]: boolean } = {}
                local perRarity: { [string]: number } = {}
                local floatSum = 0
                for _, entry in entries do
                    T.expect(seen[entry.itemId]).toBeNil()
                    seen[entry.itemId] = true
                    local item = CrateItems.byId[entry.itemId]
                    T.expect(entry.rarityId).toBe(item.rarity)
                    T.expect(entry.name).toBe(item.name)
                    T.expect(entry.kind).toBe(item.kind)
                    local poolSize = #CrateRoll.pool(crate.id, entry.rarityId)
                    -- Exakt als Bruch aus ganzen Zahlen: Gewicht / (total x Poolgröße).
                    T.expect(entry.numerator).toBe(effective.odds[entry.rarityId])
                    T.expect(entry.denominator).toBe(effective.total * poolSize)
                    T.expect(entry.numerator % 1).toBe(0)
                    T.expect(entry.denominator % 1).toBe(0)
                    T.expect(entry.percent).toBeCloseTo(entry.numerator / entry.denominator * 100, 1e-12)
                    perRarity[entry.rarityId] = (perRarity[entry.rarityId] or 0) + 1
                    floatSum += entry.numerator / entry.denominator
                end
                -- Rationale Summe: je Seltenheit Poolgröße x Gewicht / (total x Poolgröße) = Gewicht / total,
                -- und die Gewichte ergeben zusammen total. Also genau 1.
                local weightSum = 0
                for rarityId, count in perRarity do
                    T.expect(count).toBe(#CrateRoll.pool(crate.id, rarityId))
                    weightSum += effective.odds[rarityId]
                end
                T.expect(weightSum).toBe(effective.total)
                T.expect(floatSum).toBeCloseTo(1, 1e-12)
                if counters == nil or effective.guarantee == nil then
                    -- Ohne Garantie: jedes Item mit dieser Kiste in `crates` kommt vor.
                    for _, item in CrateItems.list do
                        if table.find(item.crates, crate.id) ~= nil then
                            T.expect(seen[item.id]).toBe(true)
                        end
                    end
                else
                    for itemId in seen do
                        T.expect(rank(CrateItems.byId[itemId].rarity) >= rank(effective.guarantee :: string)).toBe(true)
                    end
                end
            end
        end
    end)

    T.it("sortiert nach Rang absteigend, innerhalb der Seltenheit in der Reihenfolge von CrateItems", function()
        local entries = CrateRoll.itemOdds("gold")
        local order: { [string]: number } = {}
        for index, item in CrateItems.list do
            order[item.id] = index
        end
        for index = 2, #entries do
            local a, b = entries[index - 1], entries[index]
            local ra, rb = rank(a.rarityId), rank(b.rarityId)
            T.expect(ra >= rb).toBe(true)
            if ra == rb then
                T.expect(order[a.itemId] < order[b.itemId]).toBe(true)
            end
        end
        T.expect(entries[1].rarityId).toBe("mythic")
        T.expect(entries[#entries].rarityId).toBe("uncommon")
        -- Goldkiste ohne Garantie: Mythisch 0,5 % / 3 Items je Item.
        T.expect(entries[1].numerator).toBe(50)
        T.expect(entries[1].denominator).toBe(30000)
        T.expect(CrateRoll.itemOdds("gibt_es_nicht")).toEqual({})
    end)
end)

T.describe("longRunRates (4.6): Langzeitrate je Seltenheit mit Pity", function()
    T.it("Goldkiste: stimmt mit der Markov-Rechnung dieses Tests und den Werten des balance-analyst überein", function()
        local rates = CrateRoll.longRunRates(gold)
        local rateLeg, rateEpic, rateMythic = exactPityRates(gold)
        T.expect(rates.legendary + rates.mythic).toBeCloseTo(rateLeg, 1e-12)
        T.expect(rates.epic + rates.legendary + rates.mythic).toBeCloseTo(rateEpic, 1e-12)
        T.expect(rates.mythic).toBeCloseTo(rateMythic, 1e-12)
        T.expect(rates.legendary + rates.mythic).toBeCloseTo(renewalLegendaryRate(gold), 1e-12)
        -- docs/balance/crates_4_2.md (6 Stellen)
        T.expect(rates.legendary + rates.mythic).toBeCloseTo(BALANCE_LEGENDARY_PLUS, BALANCE_ROUNDING)
        T.expect(rates.epic + rates.legendary + rates.mythic).toBeCloseTo(BALANCE_EPIC_PLUS, BALANCE_ROUNDING)
        T.expect(rates.mythic).toBeCloseTo(BALANCE_MYTHIC, BALANCE_ROUNDING)
        -- docs/balance/directshop_4_6.md (10 Stellen)
        for rarityId, expected in BALANCE_GOLD_RATES do
            T.expect(rates[rarityId]).toBeCloseTo(expected, BALANCE_10_DIGITS)
        end
        local sum = 0
        for _, value in rates do
            sum += value
        end
        T.expect(sum).toBeCloseTo(1, 1e-12)
        -- Event-Kiste: gleiche Quoten und Grenzen, gleiche Raten.
        local eventRates = CrateRoll.longRunRates(event)
        for rarityId, value in rates do
            T.expect(eventRates[rarityId]).toBeCloseTo(value, 1e-15)
        end
    end)

    T.it("Kisten ohne Pity: Quote / 10000; jede Seltenheit kommt vor; neue Tabelle je Aufruf", function()
        for _, crate in { wood, Crates.byId.iron } do
            local rates = CrateRoll.longRunRates(crate)
            for _, rarity in Rarities.list do
                T.expect(rates[rarity.id]).toBe((crate.odds[rarity.id] or 0) / 10000)
            end
        end
        local a = CrateRoll.longRunRates(gold)
        a.mythic = 1
        T.expect(CrateRoll.longRunRates(gold).mythic).toBeCloseTo(BALANCE_GOLD_RATES.mythic, BALANCE_10_DIGITS)
    end)

    T.it("eine geänderte Tabelle oder Pity wird neu gerechnet (kein veralteter Zwischenspeicher)", function()
        local odds = table.clone(gold.odds)
        local crate = { id = "probe", odds = odds, pity = { epic = 15, legendary = 60 }, currency = "gems", price = 400, eventOnly = false }
        local first = CrateRoll.longRunRates(crate)
        T.expect(first.mythic).toBeCloseTo(BALANCE_GOLD_RATES.mythic, BALANCE_10_DIGITS)
        crate.pity = { epic = 15, legendary = 30 }
        local second = CrateRoll.longRunRates(crate)
        T.expect(second.legendary + second.mythic > first.legendary + first.mythic).toBe(true)
        crate.pity = nil
        T.expect(CrateRoll.longRunRates(crate).mythic).toBe(0.005)
    end)

    T.it("Simulation: viele Öffnungen am Stück treffen die Langzeitraten", function()
        math.randomseed(SEED + 3)
        local openings = SIMULATION_OPENINGS
        local rates = CrateRoll.longRunRates(gold)
        local counts: { [string]: number } = {}
        local counters: any = nil
        for _ = 1, openings do
            local roll = CrateRoll.roll(gold, counters, math.random)
            counters = roll.pity
            counts[roll.rarityId] = (counts[roll.rarityId] or 0) + 1
        end
        for rarityId, p in rates do
            local count = counts[rarityId] or 0
            if p == 0 then
                T.expect(count).toBe(0)
            else
                local ok, sigmas = withinSigma(count, openings, p)
                if not ok then
                    error(`{rarityId}: {count} statt {openings * p} ({sigmas} Sigma)`)
                end
            end
        end
    end)
end)

T.finish()
