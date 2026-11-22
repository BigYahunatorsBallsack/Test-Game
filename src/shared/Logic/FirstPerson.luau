--!strict
-- Ego-Perspektive: reine Rechnung ohne Roblox-API, Lune-Tests in tests/firstperson.spec.luau.
-- Die Zahlen stehen in Data/FirstPerson, der Controller Controllers/FirstPerson setzt das Ergebnis
-- um (Hände vor der Kamera, Transparenz, Mauszeiger). Winkel in Grad, Längen in Studs.

local DefaultData = require("../Data/FirstPerson")
local Tools = require("../Data/Tools")

export type Vec = { x: number, y: number, z: number }
export type GroupPose = { move: Vec, turn: Vec }
export type ViewPose = { right: GroupPose, left: GroupPose }
export type MotionState = {
    t: number, -- Zeit in Sekunden
    collecting: boolean,
    speed: number, -- Laufgeschwindigkeit in Studs pro Sekunde
}
export type Sway = { yaw: number, pitch: number }
export type CursorState = {
    windowOpen: boolean,
    treeOpen: boolean,
    toggled: boolean,
    guiNeedsCursor: boolean,
}

local FirstPerson = {}

local TAU = 2 * math.pi
local SHAPES = { Block = true, Cylinder = true, Ball = true }
local PAINTS = { skin = true, sleeve = true }

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function num(value: any, fallback: number): number
    return if isFinite(value) then value else fallback
end

local function zero(): Vec
    return { x = 0, y = 0, z = 0 }
end

-- Was die rechte Hand beim Werkzeug hält, unbekannte Werkzeuge bekommen den Standard.
function FirstPerson.toolView(toolId: string?, data: any?): any
    local d = data or DefaultData
    local view = if type(toolId) == "string" then d.tools[toolId] else nil
    return view or d.tools[d.defaultTool]
end

-- Versatz beider Hände gegenüber ihrem Anker: Graben (nur die Vorwärtsbewegung, dann zurück),
-- Zittern der Fernsteuerung und Wippen beim Laufen.
function FirstPerson.viewPose(toolId: string?, state: MotionState, data: any?): ViewPose
    local d = data or DefaultData
    local view = FirstPerson.toolView(toolId, d)
    local t = num(state.t, 0)
    local right: GroupPose = { move = zero(), turn = zero() }
    local left: GroupPose = { move = zero(), turn = zero() }

    if state.collecting then
        local dig = d.digStyles[view.dig]
        if dig ~= nil and dig.period > 0 then
            local stroke = math.max(0, math.sin(TAU * t / dig.period))
            right.move = { x = dig.move.x * stroke, y = dig.move.y * stroke, z = dig.move.z * stroke }
            right.turn = { x = dig.turn.x * stroke, y = dig.turn.y * stroke, z = dig.turn.z * stroke }
            left.move.y += dig.move.y * dig.leftFactor * stroke
            if dig.shake > 0 and dig.shakeHz > 0 then
                right.move.x += dig.shake * math.sin(TAU * dig.shakeHz * t)
                right.move.y += dig.shake * math.cos(TAU * dig.shakeHz * t)
            end
        end
    end

    local walk = d.walk
    local k = if walk.fullSpeed > 0 then math.clamp(num(state.speed, 0) / walk.fullSpeed, 0, 1) else 0
    if k > 0 then
        local bob = walk.bobStuds * k * math.sin(TAU * walk.bobHz * t)
        local side = walk.swayStuds * k * math.cos(math.pi * walk.bobHz * t)
        right.move.y += bob
        right.move.x += side
        left.move.y -= bob
        left.move.x += side
    end

    return { right = right, left = left }
end

-- Glättung: Anteil, um den ein Wert in `dt` Sekunden auf sein Ziel zugeht (0 bis 1).
function FirstPerson.smoothAlpha(dt: number, rate: number): number
    if not isFinite(dt) or dt <= 0 then
        return 0
    end
    if not isFinite(rate) or rate <= 0 then
        return 1
    end
    return 1 - math.exp(-rate * dt)
end

-- Nachziehen beim Umsehen. `yawDelta` und `pitchDelta`: Drehung der Kamera seit dem letzten Bild
-- in Bogenmaß. Ergebnis in Grad, die Hände neigen sich gegen die Drehung.
function FirstPerson.swayStep(current: Sway, yawDelta: number, pitchDelta: number, dt: number, data: any?): Sway
    local d = data or DefaultData
    local cfg = d.sway
    local targetYaw = math.clamp(-num(yawDelta, 0) * cfg.degreesPerRadian, -cfg.maxDegrees, cfg.maxDegrees)
    local targetPitch = math.clamp(-num(pitchDelta, 0) * cfg.degreesPerRadian, -cfg.maxDegrees, cfg.maxDegrees)
    local a = FirstPerson.smoothAlpha(dt, cfg.smoothing)
    return {
        yaw = current.yaw + (targetYaw - current.yaw) * a,
        pitch = current.pitch + (targetPitch - current.pitch) * a,
    }
end

-- Füllstand des Tanks (0 bis 1). Ungültige Werte zählen als leer.
function FirstPerson.tankRatio(tank: number, capacity: number): number
    if not isFinite(tank) or not isFinite(capacity) or capacity <= 0 then
        return 0
    end
    return math.clamp(tank / capacity, 0, 1)
end

-- Sand im Eimer: Höhe und Mitte (y relativ zum Anker der linken Gruppe).
function FirstPerson.bucketFill(ratio: number, data: any?): { height: number, centerY: number }
    local d = data or DefaultData
    local fill = d.viewmodel.fill
    local r = math.clamp(num(ratio, 0), 0, 1)
    local height = fill.minHeight + (fill.maxHeight - fill.minHeight) * r
    return { height = height, centerY = fill.bottomY + height / 2 }
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

local function isVec(v: any): boolean
    return type(v) == "table" and isFinite(v.x) and isFinite(v.y) and isFinite(v.z)
end

local function checkParts(label: string, parts: any, bad: (string) -> ())
    if type(parts) ~= "table" then
        bad(`{label}: Teileliste fehlt`)
        return
    end
    for index, part in parts do
        local where = `{label}[{index}]`
        if not SHAPES[part.shape] then
            bad(`{where}: unbekannte Form "{tostring(part.shape)}"`)
        end
        if not isVec(part.size) or part.size.x <= 0 or part.size.y <= 0 or part.size.z <= 0 then
            bad(`{where}: size braucht positive x, y und z`)
        end
        if not isVec(part.offset) then
            bad(`{where}: offset braucht x, y und z`)
        end
        if part.rotation ~= nil and not isVec(part.rotation) then
            bad(`{where}: rotation braucht x, y und z`)
        end
        if type(part.colorHex) ~= "string" or string.match(part.colorHex, "^#%x%x%x%x%x%x$") == nil then
            bad(`{where}: colorHex muss die Form #RRGGBB haben`)
        end
        if type(part.material) ~= "string" or part.material == "" then
            bad(`{where}: material fehlt`)
        end
        if part.paint ~= nil and not PAINTS[part.paint] then
            bad(`{where}: paint muss "skin" oder "sleeve" sein`)
        end
    end
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
    if not isVec(cam.offset) then
        bad("camera.offset braucht x, y und z")
    end
    if type(d.cursor.toggleKeys) ~= "table" or #d.cursor.toggleKeys == 0 then
        bad("cursor.toggleKeys braucht mindestens eine Taste")
    end
    if not isFinite(d.cursor.checkSeconds) or d.cursor.checkSeconds <= 0 then
        bad("cursor.checkSeconds muss größer als 0 sein")
    end

    local vm = d.viewmodel
    for _, side in { "right", "left" } do
        local anchor = vm[side]
        if anchor == nil or not isVec(anchor.offset) or not isVec(anchor.rotation) then
            bad(`viewmodel.{side} braucht offset und rotation`)
        elseif anchor.offset.z >= 0 then
            bad(`viewmodel.{side} muss vor der Kamera liegen (offset.z negativ)`)
        end
    end
    checkParts("viewmodel.rightArm", vm.rightArm, bad)
    checkParts("viewmodel.leftArm", vm.leftArm, bad)
    checkParts("viewmodel.bucket", vm.bucket, bad)
    for id, item in vm.items do
        checkParts(`viewmodel.items.{id}`, item.parts, bad)
    end
    local fill = vm.fill
    if not (isFinite(fill.minHeight) and isFinite(fill.maxHeight) and fill.minHeight > 0 and fill.maxHeight > fill.minHeight) then
        bad("viewmodel.fill: 0 < minHeight < maxHeight")
    end
    if not isFinite(fill.diameter) or fill.diameter <= 0 then
        bad("viewmodel.fill.diameter muss größer als 0 sein")
    end

    if d.tools[d.defaultTool] == nil then
        bad(`defaultTool "{tostring(d.defaultTool)}" fehlt in tools`)
    end
    for id, view in d.tools do
        if vm.items[view.item] == nil then
            bad(`tools.{id}: unbekanntes Teil für die Hand "{tostring(view.item)}"`)
        end
        if d.digStyles[view.dig] == nil then
            bad(`tools.{id}: unbekannter Grabstil "{tostring(view.dig)}"`)
        end
        if type(view.hideWorldTool) ~= "boolean" then
            bad(`tools.{id}.hideWorldTool muss true oder false sein`)
        end
    end
    for _, tool in toolList or Tools.list do
        if d.tools[tool.id] == nil then
            bad(`tools: Werkzeug "{tool.id}" fehlt`)
        end
    end
    for id, dig in d.digStyles do
        if not isFinite(dig.period) or dig.period <= 0 then
            bad(`digStyles.{id}.period muss größer als 0 sein`)
        end
        if not isVec(dig.move) or not isVec(dig.turn) then
            bad(`digStyles.{id} braucht move und turn`)
        end
        if not isFinite(dig.leftFactor) or dig.leftFactor < 0 or dig.leftFactor > 1 then
            bad(`digStyles.{id}.leftFactor muss zwischen 0 und 1 liegen`)
        end
    end
    local sway = d.sway
    if not (isFinite(sway.maxDegrees) and sway.maxDegrees >= 0 and isFinite(sway.smoothing) and sway.smoothing > 0) then
        bad("sway: maxDegrees ab 0 und smoothing größer als 0")
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
