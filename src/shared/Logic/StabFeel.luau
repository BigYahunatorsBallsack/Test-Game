--!strict
-- Gefühl beim Stechen (Überarbeitung Ü4): reine Rechnung ohne Roblox-API, Lune-Tests in
-- tests/stabfeel.spec.luau. Zahlen in Data/StabFeel und Data/StabSounds.

local DefaultData = require("../Data/StabFeel")
local DefaultSounds = require("../Data/StabSounds")

export type Vec = { x: number, y: number, z: number }
export type Kick = { studs: number, degrees: number }
export type SoundPick = { soundId: string, volume: number, pitch: number }

local StabFeel = {}

local SOUND_ID_PATTERN = "^rbxassetid://%d+$"

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function easeOut(x: number): number
    return 1 - (1 - x) * (1 - x)
end

local function easeInOut(x: number): number
    return x * x * (3 - 2 * x)
end

-- Spielt den Clip in der Dauer eines Werkzeugtakts ab.
function StabFeel.animationSpeed(interval: number, data: any?): number
    if not isFinite(interval) or interval <= 0 then
        return 1
    end
    return (data or DefaultData).arm.animationSeconds / interval
end

-- Fortschritt des laufenden Stichs in [0, 1), nil, wenn gerade kein Stich läuft.
function StabFeel.phase(now: number, stabAt: number?, interval: number): number?
    if stabAt == nil or not isFinite(now) or not isFinite(stabAt) or not isFinite(interval) or interval <= 0 then
        return nil
    end
    local p = (now - stabAt) / interval
    if p < 0 or p >= 1 then
        return nil
    end
    return p
end

-- Ausschlag der Arme während eines Stichs: 0 in Ruhe, 1 ganz eingestochen.
function StabFeel.armStroke(phase: number, data: any?): number
    local arm = (data or DefaultData).arm
    if not isFinite(phase) or phase <= 0 or phase >= 1 then
        return 0
    end
    if phase < arm.strikeEnd then
        return easeOut(phase / arm.strikeEnd)
    end
    if phase < arm.holdEnd then
        return 1
    end
    return 1 - easeInOut((phase - arm.holdEnd) / (1 - arm.holdEnd))
end

-- Anteil des Takts, der bis zum nächsten Stich noch fehlt: 1 direkt nach dem Stich, 0 beim Takt.
function StabFeel.ringFraction(now: number, lastStabAt: number?, nextStabAt: number?): number
    if lastStabAt == nil or nextStabAt == nil or not isFinite(now) or nextStabAt <= lastStabAt then
        return 0
    end
    return math.clamp((nextStabAt - now) / (nextStabAt - lastStabAt), 0, 1)
end

-- Größe des Takt-Rings in Pixeln.
function StabFeel.ringSize(fraction: number, data: any?): number
    local ring = (data or DefaultData).ring
    local f = if isFinite(fraction) then math.clamp(fraction, 0, 1) else 0
    return ring.minSize + (ring.maxSize - ring.minSize) * f
end

-- Stärke des Kamera-Rucks für einen Stich. Auf Grafikstufe "minimal" kein Ruck.
function StabFeel.cameraKick(layer: number?, level: string, data: any?): Kick
    local cam = (data or DefaultData).camera
    if level == "minimal" then
        return { studs = 0, degrees = 0 }
    end
    local depth = if isFinite(layer) then math.max(0, (layer :: number) - 1) else 0
    local factor = 1 + depth * cam.layerStep
    factor = math.min(factor, cam.maxFactor)
    return { studs = cam.studs * factor, degrees = cam.degrees * factor }
end

-- Verlauf des Rucks über die Zeit: 0 am Anfang, 1 ganz unten, wieder 0 am Ende.
function StabFeel.kickEnvelope(elapsed: number, data: any?): number
    local cam = (data or DefaultData).camera
    if not isFinite(elapsed) or elapsed <= 0 or elapsed >= cam.seconds then
        return 0
    end
    local x = elapsed / cam.seconds
    if x < cam.downShare then
        return easeOut(x / cam.downShare)
    end
    return 1 - easeInOut((x - cam.downShare) / (1 - cam.downShare))
end

-- Punkt auf dem Bogen eines Sandklumpens vom Loch (`from`) zum Eimer (`to`), `t` in [0, 1].
function StabFeel.throwPoint(from: Vec, to: Vec, t: number, data: any?): Vec
    local arc = (data or DefaultData).throw.arcStuds
    local k = if isFinite(t) then math.clamp(t, 0, 1) else 0
    local lift = 4 * arc * k * (1 - k)
    return {
        x = from.x + (to.x - from.x) * k,
        y = from.y + (to.y - from.y) * k + lift,
        z = from.z + (to.z - from.z) * k,
    }
end

-- Anteil Schwarz in der Farbe des Klumpens je Schicht.
function StabFeel.darken(layer: number?, data: any?): number
    local throw = (data or DefaultData).throw
    local depth = if isFinite(layer) then math.max(0, (layer :: number) - 1) else 0
    return math.clamp(depth * throw.layerDarken, 0, throw.maxDarken)
end

-- Wie viele Klumpen dieser Stich wirft, wenn schon `active` fliegen.
function StabFeel.throwCount(level: string, active: number, data: any?): number
    local throw = (data or DefaultData).throw
    local per = throw.perStab[level] or 0
    local max = throw.maxActive[level] or 0
    return math.max(0, math.min(per, max - math.max(0, active)))
end

-- Hüpfer des Eimer-Sands nach einem Stich (Studs nach oben).
function StabFeel.bucketBump(elapsed: number, data: any?): number
    local bucket = (data or DefaultData).bucket
    if not isFinite(elapsed) or elapsed <= 0 or elapsed >= bucket.bumpSeconds then
        return 0
    end
    return bucket.bumpStuds * math.sin(math.pi * elapsed / bucket.bumpSeconds)
end

-- Ton zu einem Ereignis ("layer", "clean", "empty", "full"). `r` in [0, 1) für die Tonhöhe.
-- nil, wenn der Ton keine ID hat (stumm).
function StabFeel.pickSound(kind: string, layer: number?, r: number, sounds: any?): SoundPick?
    local s = sounds or DefaultSounds
    local cue: any
    if kind == "layer" then
        local index = if isFinite(layer) then math.clamp(math.floor(layer :: number), 1, #s.layers) else 1
        cue = s.layers[index]
    else
        cue = s[kind]
    end
    if type(cue) ~= "table" or type(cue.soundId) ~= "string" or cue.soundId == "" then
        return nil
    end
    local jitter = (if isFinite(r) then math.clamp(r, 0, 1) else 0.5) * 2 - 1
    return { soundId = cue.soundId, volume = cue.volume, pitch = cue.pitch * (1 + jitter * s.pitchJitter) }
end

-- Prüft beide Tabellen (für DataCheck). `levels` = Grafikstufen aus Data/Screen.
function StabFeel.check(data: any, sounds: any, levels: { string }?, layerCount: number?): { string }
    local errors: { string } = {}
    local function fail(text: string)
        table.insert(errors, `StabFeel: {text}`)
    end
    local function positive(label: string, value: any, allowZero: boolean?)
        if not isFinite(value) or value < 0 or (not allowZero and value == 0) then
            fail(`{label} muss eine Zahl über 0 sein`)
        end
    end
    if type(data) ~= "table" then
        fail("Tabelle fehlt")
        return errors
    end
    local arm, ring, cam, throw, bucket = data.arm, data.ring, data.camera, data.throw, data.bucket
    if type(arm) ~= "table" or type(ring) ~= "table" or type(cam) ~= "table" or type(throw) ~= "table" or type(bucket) ~= "table" then
        fail("arm, ring, camera, throw oder bucket fehlt")
        return errors
    end
    if not (isFinite(arm.strikeEnd) and isFinite(arm.holdEnd) and arm.strikeEnd > 0 and arm.strikeEnd <= arm.holdEnd and arm.holdEnd < 1) then
        fail("arm: 0 < strikeEnd <= holdEnd < 1")
    end
    if type(arm.animationId) ~= "string" or (arm.animationId ~= "" and string.match(arm.animationId, SOUND_ID_PATTERN) == nil) then
        fail(`arm.animationId muss leer oder "rbxassetid://" plus Ziffern sein`)
    end
    positive("arm.animationSeconds", arm.animationSeconds)
    positive("ring.minSize", ring.minSize)
    positive("ring.maxSize", ring.maxSize)
    if isFinite(ring.minSize) and isFinite(ring.maxSize) and ring.minSize >= ring.maxSize then
        fail("ring.minSize muss kleiner als ring.maxSize sein")
    end
    for _, key in { "thickness", "cleanFlashSeconds", "idleAfterTakts" } do
        positive(`ring.{key}`, ring[key])
    end
    for _, key in { "studs", "degrees", "seconds", "maxFactor" } do
        positive(`camera.{key}`, cam[key])
    end
    positive("camera.layerStep", cam.layerStep, true)
    if not (isFinite(cam.downShare) and cam.downShare > 0 and cam.downShare < 1) then
        fail("camera.downShare muss zwischen 0 und 1 liegen")
    end
    for _, key in { "seconds", "arcStuds", "size" } do
        positive(`throw.{key}`, throw[key])
    end
    positive("throw.layerDarken", throw.layerDarken, true)
    if not (isFinite(throw.maxDarken) and throw.maxDarken >= 0 and throw.maxDarken <= 1) then
        fail("throw.maxDarken muss zwischen 0 und 1 liegen")
    end
    for _, level in levels or {} do
        for _, key in { "perStab", "maxActive" } do
            local v = if type(throw[key]) == "table" then throw[key][level] else nil
            if not isFinite(v) or v < 0 or v % 1 ~= 0 then
                fail(`throw.{key}.{level} muss eine ganze Zahl ab 0 sein`)
            end
        end
    end
    positive("bucket.bumpStuds", bucket.bumpStuds, true)
    positive("bucket.bumpSeconds", bucket.bumpSeconds)

    if type(sounds) ~= "table" then
        fail("StabSounds fehlt")
        return errors
    end
    if not (isFinite(sounds.pitchJitter) and sounds.pitchJitter >= 0 and sounds.pitchJitter < 0.5) then
        fail("StabSounds.pitchJitter muss zwischen 0 und 0,5 liegen")
    end
    local function checkCue(label: string, cue: any)
        if type(cue) ~= "table" then
            fail(`StabSounds.{label} fehlt`)
            return
        end
        if type(cue.soundId) ~= "string" or (cue.soundId ~= "" and string.match(cue.soundId, SOUND_ID_PATTERN) == nil) then
            fail(`StabSounds.{label}.soundId muss leer oder "rbxassetid://" plus Ziffern sein`)
        end
        if not (isFinite(cue.volume) and cue.volume >= 0 and cue.volume <= 1) then
            fail(`StabSounds.{label}.volume muss zwischen 0 und 1 liegen`)
        end
        positive(`StabSounds.{label}.pitch`, cue.pitch)
    end
    if type(sounds.layers) ~= "table" or #sounds.layers == 0 then
        fail("StabSounds.layers fehlt")
    else
        for index, cue in sounds.layers do
            checkCue(`layers[{index}]`, cue)
        end
        if layerCount ~= nil and #sounds.layers ~= layerCount then
            fail(`StabSounds.layers braucht einen Ton je Schicht ({layerCount})`)
        end
    end
    for _, key in { "clean", "empty", "full" } do
        checkCue(key, sounds[key])
    end
    return errors
end

return StabFeel
