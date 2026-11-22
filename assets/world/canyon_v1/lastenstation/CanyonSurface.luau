--!strict
-- Reconstruct the authored Canyon layers over the dunes and oasis for offline exports.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local V = require("@lune/roblox").Vector3.new
local baseTerrain = require("../../duenenmeer_v3/OasisApproachSurface")

local src = fs.readFile("assets/world/canyon_v1/BuildCanyonTerrain.editor.luau")
local bounds = assert(src:match("(local MIN, MAX = [^\r\n]+)"))
local profile = assert(src:find("local canal =", 1, true))
local stop = assert(src:find("local function vox(", profile, true))
local section, shape, low, high = luau.load(
    "local V=...\n"
        .. bounds
        .. "\n"
        .. src:sub(profile, stop - 1)
        .. "\nreturn section,profile,MIN,MAX"
)(V)

local function sample(x: number, z: number): (number, number, number)
    local prior = baseTerrain.sample(x, z)
    if x < low.X or x > high.X or z < low.Z or z > high.Z then
        return prior, 0, 0
    end
    local axis, bed, width = section(x)
    local y, blend, bluff = shape(x, z, axis, bed, width)
    return prior + (y - prior) * blend, blend, bluff
end

local function height(x: number, z: number): number
    local x0, z0 = math.floor((x - 2) / 4) * 4 + 2, math.floor((z - 2) / 4) * 4 + 2
    local u, v = (x - x0) / 4, (z - z0) / 4
    local a = sample(x0, z0) * (1 - u) + sample(x0 + 4, z0) * u
    local b = sample(x0, z0 + 4) * (1 - u) + sample(x0 + 4, z0 + 4) * u
    return a * (1 - v) + b * v + 2
end

return table.freeze({ height = height, sample = sample, section = section })
