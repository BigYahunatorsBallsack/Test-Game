--!strict
-- Paket 1.4: Bildraten-Wächter mit simulierter Uhr.

local T = require("./lib/expect")
local PerfGuard = require("../src/shared/Logic/PerfGuard")
local Terrain = require("../src/shared/Data/Terrain")

local perf = Terrain.perf

-- Bilder mit fester Bildrate von `from` bis `to` melden. Gibt den letzten Modus zurück.
local function run(state: any, from: number, to: number, fps: number): string
    local dt = 1 / fps
    local t = from
    local mode = PerfGuard.mode(state)
    while t + dt <= to + 1e-9 do
        t += dt
        mode = PerfGuard.sample(state, t, dt)
    end
    return mode
end

T.describe("Bildraten-Wächter", function()
    T.it("in der Aufwärmzeit wird nichts entschieden", function()
        local state = PerfGuard.new(perf, 0)
        T.expect(run(state, 0, perf.warmupSeconds - 0.1, 10)).toBe("full")
        T.expect(PerfGuard.fps(state)).toBeNil()
    end)

    T.it("ein kurzer Einbruch wechselt nicht", function()
        local state = PerfGuard.new(perf, 0)
        run(state, 0, 20, 60)
        run(state, 20, 21.5, 20)
        T.expect(run(state, 21.5, 40, 60)).toBe("full")
        T.expect(PerfGuard.fps(state)).toBeCloseTo(60, 0.5)
    end)

    T.it("dauerhaft niedrige Bildrate wechselt nach downAfterSeconds auf fallback", function()
        local state = PerfGuard.new(perf, 0)
        run(state, 0, 10, 60)
        T.expect(run(state, 10, 10 + perf.downAfterSeconds - 0.5, 25)).toBe("full")
        T.expect(run(state, 10 + perf.downAfterSeconds - 0.5, 10 + perf.downAfterSeconds + perf.windowSeconds + 0.1, 25)).toBe("fallback")
    end)

    T.it("über highFps für upAfterSeconds geht es zurück auf full", function()
        local state = PerfGuard.new(perf, 0)
        run(state, 0, 10, 60)
        run(state, 10, 20, 25)
        T.expect(PerfGuard.mode(state)).toBe("fallback")
        T.expect(run(state, 20, 20 + perf.upAfterSeconds - 1, 60)).toBe("fallback")
        T.expect(run(state, 20 + perf.upAfterSeconds - 1, 20 + perf.upAfterSeconds + perf.windowSeconds + 0.1, 60)).toBe("full")
    end)

    T.it("eine Bildrate zwischen lowFps und highFps ändert nichts", function()
        local mid = (perf.lowFps + perf.highFps) / 2
        local state = PerfGuard.new(perf, 0)
        T.expect(run(state, 0, 60, mid)).toBe("full")
        run(state, 60, 70, 20)
        T.expect(PerfGuard.mode(state)).toBe("fallback")
        T.expect(run(state, 70, 130, mid)).toBe("fallback")
    end)

    T.it("nach maxSwitches Wechseln bleibt es bei fallback", function()
        local state = PerfGuard.new(perf, 0)
        local t = 10
        run(state, 0, t, 60)
        -- Zehnmal abwechselnd langsam und schnell: nur maxSwitches Wechsel finden statt.
        for _ = 1, 10 do
            run(state, t, t + 10, 20)
            t += 10
            run(state, t, t + 20, 60)
            t += 20
        end
        T.expect(state.switches).toBe(perf.maxSwitches)
        T.expect(PerfGuard.mode(state)).toBe("fallback")
        T.expect(run(state, t, t + 300, 60)).toBe("fallback")
    end)

    T.it("ein erzwungener Modus gilt immer", function()
        local state = PerfGuard.new(perf, 0)
        PerfGuard.setForced(state, "fallback")
        T.expect(run(state, 0, 30, 60)).toBe("fallback")
        PerfGuard.setForced(state, nil)
        T.expect(PerfGuard.mode(state)).toBe("full")
        PerfGuard.setForced(state, "full")
        T.expect(run(state, 30, 60, 10)).toBe("full")
        -- Der Wächter misst trotzdem weiter: ohne Zwang gilt sein Ergebnis.
        PerfGuard.setForced(state, nil)
        T.expect(PerfGuard.mode(state)).toBe("fallback")
    end)

    T.it("ungültige Bilddauern werden ignoriert", function()
        local state = PerfGuard.new(perf, 0)
        run(state, 0, 10, 60)
        PerfGuard.sample(state, 10.01, 0 / 0)
        PerfGuard.sample(state, 10.02, math.huge)
        PerfGuard.sample(state, 10.03, 0)
        PerfGuard.sample(state, 10.04, -1)
        T.expect(run(state, 10.04, 30, 60)).toBe("full")
        T.expect(PerfGuard.fps(state)).toBeCloseTo(60, 0.5)
    end)
end)

T.finish()
