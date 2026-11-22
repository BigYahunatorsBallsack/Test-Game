--!strict
-- Zielen beim Graben (Ego-Perspektive): Wo entsteht das Loch? Rein, ohne Roblox-API, Lune-Tests in
-- tests/digaim.spec.luau. Die Zahlen stehen in Data/FirstPerson (`aim`), Data/Terrain (Lochgröße)
-- und Data/ToolLooks (Arbeitsspitze, Charakter-Quader). Alles nur Darstellung auf dem Client: Der
-- Server zählt den Sand unabhängig davon, es wird keine Position an den Server geschickt.
-- Punkte sind waagrecht { x, z } in Weltkoordinaten.

local FirstPersonData = require("../Data/FirstPerson")
local TerrainData = require("../Data/Terrain")
local ToolLooks = require("../Data/ToolLooks")
local ToolLook = require("./ToolLook")
local SandDig = require("./SandDig")

export type Point = { x: number, z: number }
export type Reach = { min: number, max: number, default: number }

local DigAim = {}

local SQRT2 = math.sqrt(2)

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validPoint(p: any): boolean
    return type(p) == "table" and isFinite(p.x) and isFinite(p.z)
end

-- Reichweite des Werkzeugs (waagrechter Abstand vom Charakter-Mittelpunkt).
--   min      das Loch erreicht den Charakter-Quader in keiner Richtung
--   default  Abstand der Arbeitsspitze (wie bisher fest vor dem Charakter)
--   max      Arbeitsspitze plus extraReachStuds
function DigAim.reach(toolId: string?, aimData: any?, terrain: any?): Reach
    local aim = aimData or FirstPersonData.aim
    local hole = SandDig.holeFor(terrain or TerrainData, toolId)
    local work = ToolLook.workPointOf(toolId)
    local halfWidth = ToolLooks.limits.characterBox.halfWidth
    local min = hole.radius + halfWidth * SQRT2 + aim.marginStuds
    local default = math.max(math.sqrt(work.x * work.x + work.z * work.z), min)
    local max = math.max(default + aim.extraReachStuds, min)
    return { min = min, max = max, default = default }
end

-- Zielpunkt des Lochs.
--   root     Position des Charakters
--   forward  Blickrichtung (waagrecht, muss nicht normiert sein)
--   hit      Treffer des Strahls aus der Kamera auf dem Boden, nil = Himmel oder nichts getroffen
-- Ohne Treffer: Arbeitsspitze in Blickrichtung. Mit Treffer: Richtung zum Treffer, Abstand auf
-- [min, max] begrenzt. Ungültige Eingaben ergeben nil (dann wird nicht gegraben).
function DigAim.target(root: Point, forward: Point, hit: Point?, reach: Reach): Point?
    if not validPoint(root) or not validPoint(forward) then
        return nil
    end
    local fLen = math.sqrt(forward.x * forward.x + forward.z * forward.z)
    local fx, fz = 0, 0
    if fLen > 1e-6 then
        fx, fz = forward.x / fLen, forward.z / fLen
    end
    if hit == nil or not validPoint(hit) then
        if fLen <= 1e-6 then
            return nil
        end
        return { x = root.x + fx * reach.default, z = root.z + fz * reach.default }
    end
    local dx, dz = hit.x - root.x, hit.z - root.z
    local dist = math.sqrt(dx * dx + dz * dz)
    local ux, uz
    if dist > 1e-6 then
        ux, uz = dx / dist, dz / dist
    elseif fLen > 1e-6 then
        ux, uz = fx, fz
    else
        return nil
    end
    local d = math.clamp(dist, reach.min, reach.max)
    return { x = root.x + ux * d, z = root.z + uz * d }
end

return DigAim
