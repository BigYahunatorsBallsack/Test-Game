--!strict
-- Paket 4.7: kleine Quoten-Simulation im normalen Testlauf. Je Kiste 20.000 Öffnungen über den
-- echten Kaufweg `CrateOpen.open`, einmal einzeln, einmal in 10 + 1 Paketen. Kern und Schwellen wie
-- im großen Lauf (scripts/lib/cratesim.luau, Bericht docs/balance/crates_sim_4_7.md).
--
-- Lockerer als im großen Lauf: nur 20 Batches für die Pity-Kisten. Das Batch-Sigma ist dann selbst
-- unsicher (t-Verteilung mit 19 Freiheitsgraden), darum 5 statt 4 Sigma. Die relative Schwelle
-- skaliert mit sqrt(1.000.000 / n), bei 20.000 Öffnungen also gut 7 %. Fester Startwert: Das Ergebnis
-- ist bei jedem Lauf gleich.

local T = require("./lib/expect")
local Sim = require("../scripts/lib/cratesim")
local Crates = require("../src/shared/Data/Crates")

local OPENINGS = 20_000
local SEED = 4747
local BATCHES = 20
local THRESHOLDS = table.clone(Sim.DEFAULT_THRESHOLDS)
THRESHOLDS.batchSigma = 5

local started = os.clock()
local runs = Sim.runAll(OPENINGS, SEED, BATCHES, THRESHOLDS)
local seconds = os.clock() - started

local function find(crateId: string, mode: string): any
    for _, run in runs do
        if run.stats.crateId == crateId and run.stats.mode == mode then
            return run
        end
    end
    error(`kein Lauf {crateId}/{mode}`)
end

T.describe("Zufall und Statistik-Helfer", function()
    T.it("gleicher Startwert ergibt dieselbe Folge, Werte liegen in [0, 1)", function()
        local a, b = Sim.newRandom(123), Sim.newRandom(123)
        local other = Sim.newRandom(124)
        local differs = false
        for _ = 1, 1000 do
            local x = a()
            T.expect(x).toBe(b())
            T.expect(x >= 0 and x < 1).toBe(true)
            if other() ~= x then
                differs = true
            end
        end
        T.expect(differs).toBe(true)
    end)

    T.it("Chi-Quadrat- und F-Verteilung treffen Tabellenwerte", function()
        T.expect(Sim.chiSquareP(3.841459, 1)).toBeCloseTo(0.05, 1e-6)
        T.expect(Sim.chiSquareP(11.0705, 5)).toBeCloseTo(0.05, 1e-6)
        T.expect(Sim.chiSquareP(19.6751, 11)).toBeCloseTo(0.05, 1e-5)
        T.expect(Sim.fTestP(2.4665, 4, 96)).toBeCloseTo(0.05, 1e-4)
        T.expect(Sim.fTestP(3.0069, 4, 16)).toBeCloseTo(0.05, 1e-4)
    end)

    T.it("die eigene Pity-Kette stimmt mit CrateRoll.longRunRates überein", function()
        for _, crate in Crates.list do
            if crate.pity then
                T.expect(Sim.targets(crate).crossDiff < 1e-12).toBe(true)
            end
        end
    end)
end)

T.describe(`Simulation über CrateOpen.open ({OPENINGS} Öffnungen je Kiste und Lauf)`, function()
    for _, crate in Crates.list do
        for _, mode in Sim.MODES do
            T.it(`{crate.id}, {Sim.MODE_NAMES[mode]}: alle Schwellen eingehalten`, function()
                local run = find(crate.id, mode)
                T.expect(run.eval.failures).toEqual({})
                T.expect(run.stats.openings >= OPENINGS).toBe(true)
            end)
        end
    end

    T.it("Pity-Grenzen werden nie überschritten, auch über Paketgrenzen", function()
        for _, crate in Crates.list do
            if crate.pity then
                for _, mode in Sim.MODES do
                    local stats = find(crate.id, mode).stats
                    T.expect(stats.maxNoEpic <= crate.pity.epic - 1).toBe(true)
                    T.expect(stats.maxNoLegendary <= crate.pity.legendary - 1).toBe(true)
                    T.expect(stats.triggerMismatch).toBe(0)
                    T.expect(stats.counterMismatch).toBe(0)
                end
            end
        end
    end)

    T.it("die Auswertung erkennt eine verschobene Quote und eine Seltenheit mit Quote 0", function()
        local stats = table.clone(find("wood", "single").stats)
        local counts = table.clone(stats.rarityCount)
        counts[3] = math.floor(counts[3] * 0.8) -- Selten 20 % zu selten (rund 9 Sigma)
        counts[5] = 1 -- Legendär hat in der Holzkiste Quote 0
        stats.rarityCount = counts
        local eval = Sim.evaluate(stats, THRESHOLDS)
        local joined = table.concat(eval.failures, "\n")
        T.expect(string.find(joined, "Selten", 1, true) ~= nil).toBe(true)
        T.expect(string.find(joined, "Quote 0", 1, true) ~= nil).toBe(true)
    end)

    T.it("läuft unter 3 Sekunden", function()
        print(`  Simulation: {string.format("%.2f", seconds)} s`)
        T.expect(seconds < 3).toBe(true)
    end)
end)

T.finish()
