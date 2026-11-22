--!strict
-- Ego-Perspektive: reine Rechnung ohne Roblox-API, Lune-Tests in tests/firstperson.spec.luau.
-- Die Zahlen stehen in Data/FirstPerson, der Controller Controllers/FirstPerson setzt das Ergebnis
-- um (Schulter-Gelenke, Transparenz, Mauszeiger). Alle Winkel in Grad.

local DefaultData = require("../Data/FirstPerson")
local Tools = require("../Data/Tools")

export type Pose = { x: number, y: number, z: number }
export type ArmPoses = { right: Pose, left: Pose }
export type MotionState = {
    pitch: number, -- Blickneigung in Grad (oben positiv)
    t: number, -- Zeit in Sekunden
    collecting: boolean,
    speed: number, -- Laufgeschwindigkeit in Studs pro Sekunde
}
export type CursorState = {
    windowOpen: boolean,
    treeOpen: boolean,
    toggled: boolean,
    guiNeedsCursor: boolean,
}

local FirstPerson = {}

local TAU = 2 * math.pi

-- Körperteile der Arme bei R15 und R6. Nur diese bleiben in der Ego-Perspektive sichtbar.
local ARM_PARTS: { [string]: boolean } = {
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    ["Left Arm"] = true,
    ["Right Arm"] = true,
}

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function num(value: any, fallback: number): number
    return if isFinite(value) then value else fallback
end

function FirstPerson.isArmPart(name: string): boolean
    return ARM_PARTS[name] == true
end

-- Blickneigung aus der y-Komponente der Blickrichtung (Einheitsvektor).
function FirstPerson.pitchFromLook(lookY: number): number
    return math.deg(math.asin(math.clamp(num(lookY, 0), -1, 1)))
end

-- Armstil zum Werkzeug, unbekannte Werkzeuge bekommen den Standard.
function FirstPerson.armStyle(toolId: string?, data: any?): any
    local d = data or DefaultData
    local style = if type(toolId) == "string" then d.arms[toolId] else nil
    return style or d.arms[d.defaultArms]
end

-- Haltung beider Arme. Der linke Arm ist schon gespiegelt (y und z mit umgekehrtem Vorzeichen),
-- der Controller wendet beide Werte gleich an.
function FirstPerson.armPose(toolId: string?, state: MotionState, data: any?): ArmPoses
    local d = data or DefaultData
    local style = FirstPerson.armStyle(toolId, d)
    local cam = d.camera
    local t = num(state.t, 0)
    local pitch = math.clamp(num(state.pitch, 0), cam.minPitch, cam.maxPitch) * cam.pitchFollow

    local right = { x = style.right.x + pitch, y = style.right.y, z = style.right.z }
    local left = { x = style.left.x + pitch, y = style.left.y, z = style.left.z }

    -- Wippen beim Laufen, die Arme im Gegentakt.
    local walk = d.walk
    local speedFactor = if walk.fullSpeed > 0 then math.clamp(num(state.speed, 0) / walk.fullSpeed, 0, 1) else 0
    local bob = speedFactor * walk.bobDegrees * math.sin(TAU * walk.bobHz * t)
    right.x += bob
    left.x -= bob

    -- Schwung beim Sammeln.
    if state.collecting then
        local dig = d.digStyles[style.dig]
        if dig ~= nil and dig.period > 0 then
            local phase = t / dig.period
            local sr = math.sin(TAU * phase)
            local sl = math.sin(TAU * (phase + dig.leftPhase))
            right.x += dig.swing.x * sr
            right.y += dig.swing.y * sr
            right.z += dig.swing.z * sr
            left.x += dig.swing.x * sl
            left.y += dig.swing.y * sl
            left.z += dig.swing.z * sl
            if dig.shake > 0 and dig.shakeHz > 0 then
                local shake = dig.shake * math.sin(TAU * dig.shakeHz * t)
                right.x += shake
                left.x -= shake
            end
        end
    end

    return { right = right, left = { x = left.x, y = -left.y, z = -left.z } }
end

-- Glättung: Anteil, um den ein Wert in `dt` Sekunden auf sein Ziel zugeht (0 bis 1).
function FirstPerson.smoothAlpha(dt: number, rate: number): number
    if not isFinite(dt) or dt <= 0 or not isFinite(rate) or rate <= 0 then
        return if isFinite(dt) and dt > 0 then 1 else 0
    end
    return 1 - math.exp(-rate * dt)
end

function FirstPerson.approachPose(current: Pose, target: Pose, alpha: number): Pose
    local a = math.clamp(num(alpha, 1), 0, 1)
    return {
        x = current.x + (target.x - current.x) * a,
        y = current.y + (target.y - current.y) * a,
        z = current.z + (target.z - current.z) * a,
    }
end

-- Ist der Mauszeiger frei? (Nur am PC, am Handy ist die Maus nie gesperrt.)
function FirstPerson.cursorFree(state: CursorState): boolean
    return state.windowOpen or state.treeOpen or state.toggled or state.guiNeedsCursor
end

function FirstPerson.isToggleKey(keyName: string, data: any?): boolean
    local d = data or DefaultData
    return table.find(d.cursor.toggleKeys, keyName) ~= nil
end

-- Halbe Ausdehnung des gedrehten Quaders entlang der Weltachsen (Drehung wie CFrame.Angles:
-- erst z, dann y, dann x, Winkel in Grad).
local function rotatedHalf(size: any, rotation: any?): (number, number, number)
    local hx, hy, hz = size.x / 2, size.y / 2, size.z / 2
    if rotation == nil then
        return hx, hy, hz
    end
    local rx, ry, rz = math.rad(rotation.x or 0), math.rad(rotation.y or 0), math.rad(rotation.z or 0)
    local cx, sx = math.cos(rx), math.sin(rx)
    local cy, sy = math.cos(ry), math.sin(ry)
    local cz, sz = math.cos(rz), math.sin(rz)
    -- R = Rx * Ry * Rz
    local m11, m12, m13 = cy * cz, -cy * sz, sy
    local m21, m22, m23 = cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy
    local m31, m32, m33 = sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy
    return math.abs(m11) * hx + math.abs(m12) * hy + math.abs(m13) * hz,
        math.abs(m21) * hx + math.abs(m22) * hy + math.abs(m23) * hz,
        math.abs(m31) * hx + math.abs(m32) * hy + math.abs(m33) * hz
end

-- Nummern der Teile eines Werkzeug-Aussehens (Data/ToolLooks), die im Sicht-Gang vor den Augen
-- liegen. `scale` ist die aktuelle Größe des Modells (Einblenden beim Wechsel), Standard 1.
function FirstPerson.blockingParts(look: any, eyeHeight: number, data: any?, scale: number?): { number }
    local d = data or DefaultData
    local lane = d.toolView.lane
    local eye = num(eyeHeight, d.toolView.defaultEyeHeight)
    local s = num(scale, 1)
    local result: { number } = {}
    for index, spec in look.parts do
        local hx, hy, hz = rotatedHalf(spec.size, spec.rotation)
        hx, hy, hz = hx * s, hy * s, hz * s
        local px, py, pz = spec.offset.x * s, spec.offset.y * s, spec.offset.z * s
        local overlapX = math.abs(px) - hx < lane.halfWidth
        local overlapY = math.abs(py - eye) - hy < lane.halfHeight
        -- Vorn ist z negativ: der Gang reicht von -nearZ bis -farZ.
        local overlapZ = pz + hz > -lane.farZ and pz - hz < -lane.nearZ
        if overlapX and overlapY and overlapZ then
            table.insert(result, index)
        end
    end
    return result
end

-- Prüft die Tabelle. Gibt eine Liste von Fehlertexten zurück (leer = alles gut).
function FirstPerson.check(data: any?, toolList: { any }?): { string }
    local d = data or DefaultData
    local errors: { string } = {}
    local function bad(text: string)
        table.insert(errors, text)
    end
    local cam = d.camera
    if not isFinite(cam.fieldOfView) or cam.fieldOfView < 1 or cam.fieldOfView > 120 then
        bad("camera.fieldOfView muss zwischen 1 und 120 liegen")
    end
    if not isFinite(cam.pitchFollow) or cam.pitchFollow < 0 or cam.pitchFollow > 1 then
        bad("camera.pitchFollow muss zwischen 0 und 1 liegen")
    end
    if not isFinite(cam.minPitch) or not isFinite(cam.maxPitch) or cam.minPitch > cam.maxPitch then
        bad("camera.minPitch muss kleiner als maxPitch sein")
    end
    for _, field in { "inward", "up", "forward" } do
        if not isFinite(cam.shoulderShift[field]) or math.abs(cam.shoulderShift[field]) > 2 then
            bad(`camera.shoulderShift.{field} muss eine Zahl bis 2 Studs sein`)
        end
    end
    if type(d.cursor.toggleKeys) ~= "table" or #d.cursor.toggleKeys == 0 then
        bad("cursor.toggleKeys braucht mindestens eine Taste")
    end
    if not isFinite(d.cursor.checkSeconds) or d.cursor.checkSeconds <= 0 then
        bad("cursor.checkSeconds muss größer als 0 sein")
    end
    if not isFinite(d.smoothing) or d.smoothing <= 0 then
        bad("smoothing muss größer als 0 sein")
    end
    if d.arms[d.defaultArms] == nil then
        bad(`defaultArms "{tostring(d.defaultArms)}" fehlt in arms`)
    end
    for id, style in d.arms do
        if d.digStyles[style.dig] == nil then
            bad(`arms.{id}: unbekannter Grabstil "{tostring(style.dig)}"`)
        end
        for _, side in { "right", "left" } do
            local pose = style[side]
            if pose == nil or not isFinite(pose.x) or not isFinite(pose.y) or not isFinite(pose.z) then
                bad(`arms.{id}.{side} braucht x, y und z`)
            end
        end
    end
    for id, dig in d.digStyles do
        if not isFinite(dig.period) or dig.period <= 0 then
            bad(`digStyles.{id}.period muss größer als 0 sein`)
        end
        if not isFinite(dig.leftPhase) or dig.leftPhase < 0 or dig.leftPhase > 1 then
            bad(`digStyles.{id}.leftPhase muss zwischen 0 und 1 liegen`)
        end
    end
    for _, tool in toolList or Tools.list do
        if d.arms[tool.id] == nil then
            bad(`arms: Werkzeug "{tool.id}" hat keine Armhaltung`)
        end
    end
    local view = d.toolView
    if not isFinite(view.fadeTo) or view.fadeTo < 0 or view.fadeTo > 1 then
        bad("toolView.fadeTo muss zwischen 0 und 1 liegen")
    end
    local lane = view.lane
    if not (isFinite(lane.halfWidth) and lane.halfWidth > 0 and isFinite(lane.halfHeight) and lane.halfHeight > 0) then
        bad("toolView.lane braucht positive halfWidth und halfHeight")
    end
    if not (isFinite(lane.nearZ) and isFinite(lane.farZ) and lane.nearZ >= 0 and lane.farZ > lane.nearZ) then
        bad("toolView.lane: 0 <= nearZ < farZ")
    end
    return errors
end

return FirstPerson
