--!strict
-- Offline reconstruction of the Canyon-to-Salt-Lake terrain blend.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local V = require("@lune/roblox").Vector3.new
local canyon = require("../../canyon_v1/lastenstation/CanyonSurface")

local src = fs.readFile("assets/world/salzsee_v1/BuildSaltLakeTerrain.editor.luau")
local bounds = assert(src:match("(local MIN,MAX=[^\r\n]+)"))
local lake = assert(src:match("(local CX,CZ,RX,RZ,WATER=[^\r\n]+)"))
local first = assert(src:find("local roads=", 1, true))
local last = assert(src:find("local function voxel(", first, true))
local form, road, roads, smooth, low, high, water = luau.load(
    "local V=...\n"
        .. bounds
        .. "\n"
        .. lake
        .. "\n"
        .. src:sub(first, last - 1)
        .. "\nreturn form,road,roads,smooth,MIN,MAX,WATER"
)(V)

local function sample(x: number, z: number): (number, number, number, number, number)
    local prior, _, bluff = canyon.sample(x, z)
    if x < low.X or x > high.X or z < low.Z or z > high.Z then
        return prior, 0, bluff, 8, 999
    end
    local mix = smooth((x - low.X) / 91)
    if x < 1152 then
        mix *= smooth(math.min(z - low.Z, high.Z - z) / 93)
    end
    local target, ring, stone, distance = form(x, z)
    local y = prior + (target - prior) * mix
    return y, mix, bluff * (1 - mix) + stone * mix, ring, distance
end

local function height(x: number, z: number): number
    local x0, z0 = math.floor((x - 2) / 4) * 4 + 2, math.floor((z - 2) / 4) * 4 + 2
    local u, v = (x - x0) / 4, (z - z0) / 4
    local a = sample(x0, z0) * (1 - u) + sample(x0 + 4, z0) * u
    local b = sample(x0, z0 + 4) * (1 - u) + sample(x0 + 4, z0 + 4) * u
    return a * (1 - v) + b * v + 2
end

return table.freeze({ height = height, sample = sample, road = road, roads = roads, water = water })
