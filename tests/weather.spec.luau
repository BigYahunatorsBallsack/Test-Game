--!strict
-- Paket 2.5: Wetter aus der Serverzeit (reine Logik) und seine Daten.

local T = require("./lib/expect")
local Weather = require("../src/shared/Logic/Weather")
local WeatherData = require("../src/shared/Data/Weather")
local DataCheck = require("../src/shared/Logic/DataCheck")
local Zones = require("../src/shared/Data/Zones")

local function deepCopy(value: any, memo: { [any]: any }?): any
    if type(value) ~= "table" then
        return value
    end
    local seen = memo or {}
    if seen[value] ~= nil then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, inner in value do
        copy[deepCopy(key, seen)] = deepCopy(inner, seen)
    end
    return copy
end

T.describe("Wetter über die Serverzeit", function()
    T.it("dieselbe Zeit ergibt immer dasselbe Wetter", function()
        for _, t in { 0, 17.5, 90, 1234.56, 99999 } do
            T.expect(Weather.stateAt("oasis", t)).toEqual(Weather.stateAt("oasis", t))
        end
    end)

    T.it("das Dünenmeer und unbekannte Zonen haben nie Wetter", function()
        for t = 0, 5000, 37 do
            T.expect(Weather.stateAt("dunes", t).active).toBe(false)
            T.expect(Weather.stateAt("dunes", t).kind).toBe("clear")
            T.expect(Weather.stateAt("mars", t).kind).toBe("clear")
        end
    end)

    T.it("Regen in der Oase dauert in jedem Zyklus 90 s", function()
        local schedule = WeatherData.zones.oasis
        T.expect(schedule.kind).toBe("rain")
        T.expect(schedule.activeSeconds).toBe(90)
        T.expect(schedule.cycleSeconds).toBe(480)
        for cycle = 0, 3 do
            local start = schedule.offsetSeconds + cycle * schedule.cycleSeconds
            local activeSteps = 0
            for step = 0, schedule.cycleSeconds * 2 - 1 do
                local t = start + step * 0.5
                if t >= start + schedule.cycleSeconds then
                    break
                end
                if Weather.stateAt("oasis", t).active then
                    activeSteps += 1
                end
            end
            T.expect(activeSteps * 0.5).toBe(90)
        end
    end)

    T.it("Stärke blendet ein und aus und bleibt zwischen 0 und 1", function()
        local start = WeatherData.zones.oasis.offsetSeconds
        local fade = WeatherData.fadeSeconds
        T.expect(Weather.stateAt("oasis", start).strength).toBe(0)
        T.expect(Weather.stateAt("oasis", start + fade / 2).strength).toBeCloseTo(0.5, 1e-9)
        T.expect(Weather.stateAt("oasis", start + fade).strength).toBe(1)
        local last = start + WeatherData.zones.oasis.activeSeconds
        T.expect(Weather.stateAt("oasis", last - fade / 2).strength).toBeCloseTo(0.5, 1e-9)
        for t = 0, 1000, 3 do
            local s = Weather.stateAt("oasis", t).strength
            T.expect(s >= 0 and s <= 1).toBe(true)
        end
    end)

    T.it("Dauer-Wetter (Dunst der Ruinenstadt) ist immer aktiv und hat kein Loch am Zyklusende", function()
        local cycle = WeatherData.zones.ruins.cycleSeconds
        T.expect(Weather.stateAt("ruins", cycle - 0.01).active).toBe(true)
        T.expect(Weather.stateAt("ruins", cycle - 0.01).strength).toBe(1)
        T.expect(Weather.stateAt("ruins", cycle + 0.01).strength).toBe(1)
        for t = 0, 3000, 11 do
            T.expect(Weather.stateAt("ruins", t).active).toBe(true)
        end
    end)

    T.it("Fundchance-Bonus gilt nur, solange das Wetter läuft (für Paket 2.6)", function()
        local start = WeatherData.zones.oasis.offsetSeconds
        T.expect(Weather.stateAt("oasis", start + 10).findChanceBonusBp).toBe(WeatherData.zones.oasis.findChanceBonusBp)
        T.expect(Weather.stateAt("oasis", start + 200).findChanceBonusBp).toBe(0)
    end)

    T.it("kaputte Zeit (NaN, unendlich) ergibt klares Wetter", function()
        T.expect(Weather.stateAt("oasis", 0 / 0).kind).toBe("clear")
        T.expect(Weather.stateAt("oasis", math.huge).kind).toBe("clear")
    end)

    T.it("secondsUntil und secondsLeft passen zum Zyklus", function()
        local schedule = WeatherData.zones.oasis
        local beforeStart = Weather.stateAt("oasis", schedule.offsetSeconds + schedule.cycleSeconds - 30)
        T.expect(beforeStart.active).toBe(false)
        T.expect(beforeStart.secondsUntil).toBeCloseTo(30, 1e-9)
        local inside = Weather.stateAt("oasis", schedule.offsetSeconds + 20)
        T.expect(inside.secondsLeft).toBeCloseTo(schedule.activeSeconds - 20, 1e-9)
    end)
end)

T.describe("Daten des Wetters", function()
    local function errorsFor(change: (any) -> ()): string
        local data: any = deepCopy(DataCheck.defaults())
        change(data)
        return table.concat(DataCheck.run(data), "\n")
    end

    T.it("die echten Tabellen bestehen, jede Zone mit Wetter existiert", function()
        T.expect(errorsFor(function(data: any) end)).toBe("")
        for zoneId in WeatherData.zones do
            T.expect(Zones.byId[zoneId] ~= nil).toBe(true)
        end
    end)

    T.it("kaputte Zeitpläne und Looks werden abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.Weather.zones.oasis.activeSeconds = 9999
        end)).toContain("länger als cycleSeconds")
        T.expect(errorsFor(function(data: any)
            data.Weather.zones.oasis.cycleSeconds = 0
        end)).toContain("cycleSeconds")
        T.expect(errorsFor(function(data: any)
            data.Weather.zones.mars = { kind = "rain", cycleSeconds = 10, activeSeconds = 5, offsetSeconds = 0, findChanceBonusBp = 0 }
        end)).toContain("unbekannte Zone")
        T.expect(errorsFor(function(data: any)
            data.Weather.zones.oasis.kind = "schnee"
        end)).toContain("steht nicht in Weather.looks")
        T.expect(errorsFor(function(data: any)
            data.Weather.looks.rain.tintHex = "blau"
        end)).toContain("tintHex")
        T.expect(errorsFor(function(data: any)
            data.Weather.looks.rain.atmosphereDensity = 2
        end)).toContain("atmosphereDensity")
        T.expect(errorsFor(function(data: any)
            data.Weather.fadeSeconds = 0
        end)).toContain("fadeSeconds")
    end)
end)

T.finish()
