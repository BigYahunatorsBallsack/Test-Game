--!strict
-- Bildraten-Wächter (Paket 1.4), ohne Roblox-API.
-- Misst die Bildrate in Fenstern (Terrain.perf.windowSeconds). Liegt sie downAfterSeconds
-- lang unter lowFps, wechselt der Modus auf "fallback" (keine Terrain-Verformung, nur
-- sinkende Sandscheibe und Partikel). Liegt sie upAfterSeconds lang über highFps, geht es
-- zurück auf "full". Nach maxSwitches Wechseln bleibt es bei "fallback", damit der Modus
-- nicht hin und her springt. Ein erzwungener Modus (zum Testen) gilt immer.

export type Mode = "full" | "fallback"

export type State = {
    config: any,
    startedAt: number,
    mode: Mode,
    forced: Mode?,
    switches: number,
    frames: number,
    frameTime: number,
    windowStart: number,
    lastFps: number?,
    lowSince: number?,
    highSince: number?,
}

local PerfGuard = {}

function PerfGuard.new(config: any, now: number): State
    return {
        config = config,
        startedAt = now,
        mode = "full",
        forced = nil,
        switches = 0,
        frames = 0,
        frameTime = 0,
        windowStart = now,
        lastFps = nil,
        lowSince = nil,
        highSince = nil,
    }
end

-- Aktueller Modus (erzwungener Modus zuerst).
function PerfGuard.mode(state: State): Mode
    return state.forced or state.mode
end

-- Modus erzwingen ("full" oder "fallback") oder mit nil an den Wächter zurückgeben.
function PerfGuard.setForced(state: State, mode: Mode?)
    state.forced = mode
end

-- Zuletzt gemessene Bildrate (nil, solange noch kein Fenster voll ist).
function PerfGuard.fps(state: State): number?
    return state.lastFps
end

-- Ein volles Fenster [windowStart, now] mit der Bildrate fps auswerten.
local function evaluate(state: State, fps: number, windowStart: number, now: number)
    local perf = state.config
    if fps < perf.lowFps then
        state.highSince = nil
        state.lowSince = state.lowSince or windowStart
    elseif fps > perf.highFps then
        state.lowSince = nil
        state.highSince = state.highSince or windowStart
    else
        state.lowSince = nil
        state.highSince = nil
    end
    if state.mode == "full" and state.lowSince ~= nil and now - state.lowSince >= perf.downAfterSeconds then
        state.mode = "fallback"
        state.switches += 1
        state.lowSince = nil
    elseif
        state.mode == "fallback"
        and state.highSince ~= nil
        and now - state.highSince >= perf.upAfterSeconds
        and state.switches < perf.maxSwitches
    then
        state.mode = "full"
        state.switches += 1
        state.highSince = nil
    end
end

-- Ein Bild melden (`dt` = Dauer des Bilds in Sekunden). Gibt den aktuellen Modus zurück.
-- Ein Fenster zählt ab seinem Beginn: Ist es zu langsam, gilt die Bildrate ab dann als zu
-- niedrig, bis ein Fenster das Gegenteil zeigt.
function PerfGuard.sample(state: State, now: number, dt: number): Mode
    local perf = state.config
    if now - state.startedAt < perf.warmupSeconds then
        state.windowStart = now
        state.frames = 0
        state.frameTime = 0
        return PerfGuard.mode(state)
    end
    if dt > 0 and dt == dt and dt < math.huge then
        state.frames += 1
        state.frameTime += dt
    end
    if now - state.windowStart >= perf.windowSeconds and state.frameTime > 0 then
        local fps = state.frames / state.frameTime
        state.lastFps = fps
        evaluate(state, fps, state.windowStart, now)
        state.windowStart = now
        state.frames = 0
        state.frameTime = 0
    end
    return PerfGuard.mode(state)
end

return PerfGuard
