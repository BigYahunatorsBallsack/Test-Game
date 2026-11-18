--!strict
-- Wetter aus der Serverzeit (Paket 2.5). Rein, ohne Roblox-API, Lune-Tests in
-- tests/weather.spec.luau. Die Zeitpläne stehen in Data/Weather.
--
-- `stateAt` ist deterministisch: für dieselbe Zeit und Zone kommt immer dasselbe heraus, auf
-- dem Server wie auf jedem Client. Die Stärke blendet in `fadeSeconds` ein und aus.

local WeatherData = require("../Data/Weather")

export type State = {
    kind: string, -- "clear" oder die Art aus Data/Weather
    active: boolean,
    strength: number, -- 0 bis 1 (Ein- und Ausblenden)
    secondsLeft: number, -- Sekunden bis zum Ende (nur wenn aktiv), sonst 0
    secondsUntil: number, -- Sekunden bis zum nächsten Beginn (nur wenn nicht aktiv), sonst 0
    findChanceBonusBp: number, -- Bonus der Fundchance, nur solange aktiv (Paket 2.6)
}

local Weather = {}

local CLEAR: State = {
    kind = "clear",
    active = false,
    strength = 0,
    secondsLeft = 0,
    secondsUntil = 0,
    findChanceBonusBp = 0,
}

-- Wetter einer Zone zur Serverzeit `t` (Sekunden). Unbekannte Zone und kaputte Zeit: klar.
function Weather.stateAt(zoneId: string, t: number, data: any?): State
    local source = data or WeatherData
    local schedule = source.zones[zoneId]
    if schedule == nil or type(t) ~= "number" or t ~= t or t == math.huge or t == -math.huge then
        return table.clone(CLEAR)
    end
    local cycle = schedule.cycleSeconds
    local active = math.min(schedule.activeSeconds, cycle)
    local phase = (t - schedule.offsetSeconds) % cycle
    if phase >= active then
        return {
            kind = schedule.kind,
            active = false,
            strength = 0,
            secondsLeft = 0,
            secondsUntil = cycle - phase,
            findChanceBonusBp = 0,
        }
    end
    local fade = math.max(source.fadeSeconds, 1e-6)
    -- Dauerhaftes Wetter (aktiv gleich Zyklus) hat immer volle Stärke, kein Ein- und Ausblenden.
    local strength = 1
    if active < cycle then
        strength = math.min(math.clamp(phase / fade, 0, 1), math.clamp((active - phase) / fade, 0, 1))
    end
    return {
        kind = schedule.kind,
        active = true,
        strength = strength,
        secondsLeft = active - phase,
        secondsUntil = 0,
        findChanceBonusBp = schedule.findChanceBonusBp,
    }
end

return Weather
