--!strict
-- Offline reconstruction of the salt shelf and the black-sand approach.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local V = require("@lune/roblox").Vector3.new
local saltLake = require("../../salzsee_v1/windwarte/SaltLakeSurface")

local src = fs.readFile("assets/world/ruinenstadt_v1/BuildRuinsTerrain.editor.luau")
local bounds = assert(src:match("(local MIN,MAX=[^\r\n]+)"))
local a = assert(src:find("local roads=", 1, true))
local b = assert(src:find("local function voxel(", a, true))
local form, road, roads, smooth, low, high = luau.load(
    "local V=...\n"
        .. bounds
        .. "\n"
        .. src:sub(a, b - 1)
        .. "\nreturn form,road,roads,smooth,MIN,MAX"
)(V)

local function sample(x: number, z: number): (number, number, number)
    local prior, _, stone = saltLake.sample(x, z)
    if x < low.X or x > high.X or z < low.Z or z > high.Z then
        return prior, 0, stone
    end
    local target, rim = form(x, z)
    local mix = smooth((x - low.X) / 99)
    if x > 1714 and x < 1742 then
        mix += (1 - mix) * smooth((x - 1714) / 26)
    end
    return prior + (target - prior) * mix, mix, stone * (1 - mix) + rim * mix
end

local function height(x: number, z: number): number
    local x0, z0 = math.floor((x - 2) / 4) * 4 + 2, math.floor((z - 2) / 4) * 4 + 2
    local u, v = (x - x0) / 4, (z - z0) / 4
    local a = sample(x0, z0) * (1 - u) + sample(x0 + 4, z0) * u
    local b = sample(x0, z0 + 4) * (1 - u) + sample(x0 + 4, z0 + 4) * u
    return a * (1 - v) + b * v + 2
end

return table.freeze({ height = height, sample = sample, road = road, roads = roads })
