--!strict
-- Offline reconstruction of the authored dig basin over Dunes V3.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local V = require("@lune/roblox").Vector3.new
local dunes = require("../../duenenmeer_v3/OasisApproachSurface")

local src = fs.readFile("assets/world/koloss_v1/BuildColossusTerrain.editor.luau")
local bounds = assert(src:match("(local MIN,MAX=[^\r\n]+)"))
local anchor = assert(src:match("(local anchor=V%([^\r\n]+)"))
local first = assert(src:find("local roads=", 1, true))
local last = assert(src:find("local function voxel(", first, true))
local form, road, roads, low, high = luau.load(
    "local V=...\n"
        .. bounds
        .. "\n"
        .. anchor
        .. "\n"
        .. src:sub(first, last - 1)
        .. "\nreturn profile,road,roads,MIN,MAX"
)(V)

local function sample(x: number, z: number): number
    local prior = dunes.sample(x, z)
    if x < low.X or x > high.X or z < low.Z or z > high.Z then
        return prior
    end
    return form(x, z, prior)
end

local function height(x: number, z: number): number
    local x0, z0 = math.floor((x - 2) / 4) * 4 + 2, math.floor((z - 2) / 4) * 4 + 2
    local u, v = (x - x0) / 4, (z - z0) / 4
    local a = sample(x0, z0) * (1 - u) + sample(x0 + 4, z0) * u
    local b = sample(x0, z0 + 4) * (1 - u) + sample(x0 + 4, z0 + 4) * u
    return a * (1 - v) + b * v + 2
end

local function distance(x: number, z: number): number
    local minimum = math.huge
    for _, track in roads do
        local d = road(x, z, track)
        minimum = math.min(minimum, d)
    end
    return minimum
end

return table.freeze({ height = height, distance = distance, roads = roads })
