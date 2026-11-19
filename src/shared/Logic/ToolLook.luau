--!strict
-- Aussehen eines Werkzeugs (Paket 2.4). Rein, ohne Roblox-API, Lune-Tests in
-- tests/toollook.spec.luau. Die Zahlen stehen in Data/ToolLooks.

local Tools = require("../Data/Tools")
local ToolLooks = require("../Data/ToolLooks")
local TreeEffects = require("./TreeEffects")

export type Change = "none" | "upgrade" | "silent"

local ToolLook = {}

-- Aussehen zur Werkzeug-ID. Unbekannte oder leere IDs bekommen das Aussehen der Hand.
function ToolLook.of(toolId: string?): ToolLooks.Look
    local look = if type(toolId) == "string" then ToolLooks.byToolId[toolId] else nil
    return look or ToolLooks.byToolId[ToolLooks.defaultToolId]
end

local function tierOf(toolId: string?): number
    local tool = if type(toolId) == "string" then Tools.byId[toolId] else nil
    if tool == nil then
        tool = Tools.byId[ToolLooks.defaultToolId]
    end
    return if tool ~= nil then tool.tier else 1
end

-- Was passiert beim Wechsel von `before` zu `after`?
--   none     gleiche Stufe, nichts tun
--   upgrade  höhere Stufe: Modell wechseln mit Animation
--   silent   erster Zustand oder niedrigere Stufe (Sandsturm-Reset): Modell wechseln ohne Animation
function ToolLook.change(before: string?, after: string?): Change
    if before == nil then
        return "silent"
    end
    local a = tierOf(before)
    local b = tierOf(after)
    if b == a then
        return "none"
    elseif b > a then
        return "upgrade"
    end
    return "silent"
end

-- Partikel pro Graben.
function ToolLook.dustCount(toolId: string?): number
    return ToolLook.of(toolId).dust.count
end

-- Höchste Partikelzahl auf einmal: Staub beim Graben plus Wechsel-Wolke.
function ToolLook.particlePeak(toolId: string?): number
    return ToolLook.of(toolId).dust.count + ToolLooks.change.burstCount
end

-- Zusätzlicher Kamera-Abstand der Stufe in Studs.
function ToolLook.cameraBonus(toolId: string?): number
    return ToolLook.of(toolId).cameraBonusStuds
end

-- Attribute, die der Server am Spieler setzt, damit alle Clients das Werkzeug sehen.
-- Die Attribute enthalten nur das Ergebnis aus dem Baum, der Client kann sie nicht setzen.
function ToolLook.attributesFor(profile: any, holding: boolean): { ToolId: string, Collecting: boolean }
    return { ToolId = TreeEffects.of(profile).tool.id, Collecting = holding == true }
end

local function rotationMatrix(rotation: ToolLooks.Vec?): { { number } }
    if rotation == nil then
        return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
    end
    local a, b, c = math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z)
    local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    -- R = Rx * Ry * Rz (wie CFrame.Angles)
    local rx = { { 1, 0, 0 }, { 0, ca, -sa }, { 0, sa, ca } }
    local ry = { { cb, 0, sb }, { 0, 1, 0 }, { -sb, 0, cb } }
    local rz = { { cc, -sc, 0 }, { sc, cc, 0 }, { 0, 0, 1 } }
    local function mul(m: { { number } }, n: { { number } }): { { number } }
        local out = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
        for i = 1, 3 do
            for j = 1, 3 do
                local sum = 0
                for k = 1, 3 do
                    sum += m[i][k] * n[k][j]
                end
                out[i][j] = sum
            end
        end
        return out
    end
    return mul(mul(rx, ry), rz)
end

export type Box = { minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number }

-- Achsparalleler Hüllquader eines Teils, Drehung eingerechnet (für Zylinder und Kugel
-- großzügig als Quader).
function ToolLook.bounds(part: ToolLooks.Part): Box
    local r = rotationMatrix(part.rotation)
    local half = { part.size.x / 2, part.size.y / 2, part.size.z / 2 }
    local ext = { 0, 0, 0 }
    for i = 1, 3 do
        for j = 1, 3 do
            ext[i] += math.abs(r[i][j]) * half[j]
        end
    end
    return {
        minX = part.offset.x - ext[1],
        maxX = part.offset.x + ext[1],
        minY = part.offset.y - ext[2],
        maxY = part.offset.y + ext[2],
        minZ = part.offset.z - ext[3],
        maxZ = part.offset.z + ext[3],
    }
end

-- Schneidet kein Teil den Charakter-Quader?
function ToolLook.clearOfCharacter(look: ToolLooks.Look): (boolean, number?)
    local box = ToolLooks.limits.characterBox
    local hw, height = box.halfWidth, box.height
    for index, part in look.parts do
        local b = ToolLook.bounds(part)
        if b.maxX > -hw and b.minX < hw and b.maxZ > -hw and b.minZ < hw and b.maxY > 0 and b.minY < height then
            return false, index
        end
    end
    return true, nil
end

-- Liegt kein Teil im Kamera-Gang hinter dem Charakter?
function ToolLook.clearOfCameraLane(look: ToolLooks.Look): (boolean, number?)
    local lane = ToolLooks.limits.cameraLane
    local hw = ToolLooks.limits.characterBox.halfWidth
    for index, part in look.parts do
        local b = ToolLook.bounds(part)
        if b.maxX > -lane.halfWidth and b.minX < lane.halfWidth and b.maxZ > hw and b.minZ < lane.length then
            return false, index
        end
    end
    return true, nil
end

-- Arbeitsspitze der Stufe (unbekannt = Hand).
function ToolLook.workPointOf(toolId: string?): { x: number, z: number }
    return ToolLook.of(toolId).workPoint
end

-- Erreicht ein Loch mit diesem Radius an der Arbeitsspitze den Charakter-Quader nicht?
function ToolLook.holeClear(look: ToolLooks.Look, radius: number): boolean
    local hw = ToolLooks.limits.characterBox.halfWidth
    local dx = math.max(math.abs(look.workPoint.x) - hw, 0)
    local dz = math.max(math.abs(look.workPoint.z) - hw, 0)
    return math.sqrt(dx * dx + dz * dz) >= radius
end

-- Wert einer Bewegung zur Zeit t (Sekunden): Grad bei swing und spin, Studs bei bob und slide.
function ToolLook.motionAt(motion: ToolLooks.Motion, t: number): number
    local period = motion.period
    if type(period) ~= "number" or period <= 0 or t ~= t then
        return 0
    end
    local phase = (t / period) % 1
    if motion.kind == "swing" or motion.kind == "bob" then
        return motion.amplitude * math.sin(2 * math.pi * phase)
    elseif motion.kind == "spin" then
        return 360 * phase
    elseif motion.kind == "slide" then
        return motion.amplitude * (phase * 2 - 1)
    end
    return 0
end

-- Gleichzeitig lebende Sandfluss-Partikel.
function ToolLook.flowLoad(look: ToolLooks.Look): number
    return look.sandFlow.rate * look.sandFlow.lifetime
end

return ToolLook
