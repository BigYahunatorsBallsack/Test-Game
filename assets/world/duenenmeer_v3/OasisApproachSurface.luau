--!strict
-- Offline surface estimate for placement previews where Oase V1 overlays the dunes.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rbx = require("@lune/roblox")

local function section(source: string, start: string, stop: string): string
    local a = assert(source:find(start, 1, true), start)
    local b = assert(source:find(stop, a, true), stop)
    return source:sub(a, b - 1)
end

local dunes = fs.readFile("assets/world/duenenmeer_v3/BuildDunes.editor.luau")
local duneHeight = luau.load(
    section(dunes, "local function smooth(", "local function makeTileArrays(")
        .. "\nreturn heightAt"
)()
local oasis = fs.readFile("assets/world/oase_v1/BuildOasisTerrain.editor.luau")
local boundary = assert(oasis:match("(local XMIN, XMAX, ZMIN, ZMAX[^\r\n]+)"))
local water = assert(oasis:match("(local WATER, CX, CZ[^\r\n]+)"))
local xmin, xmax, zmin, zmax = luau.load(boundary .. "\nreturn XMIN,XMAX,ZMIN,ZMAX")()
local oasisProfile = luau.load(
    "local V=...\n"
        .. boundary
        .. "\n"
        .. water
        .. "\n"
        .. section(oasis, "local function smooth(", "local function build(")
        .. "\nreturn profile"
)(rbx.Vector3.new)

local function sample(x: number, z: number): (number, number, number)
    local dune = duneHeight(x, z)
    if x < xmin or x > xmax or z < zmin or z > zmax then
        return dune, 0, math.huge
    end
    local target, influence, _, _, roadDistance = oasisProfile(x, z)
    return dune + (target - dune) * influence, influence, roadDistance
end

local function height(x: number, z: number): number
    local x0, z0 = math.floor((x - 2) / 4) * 4 + 2, math.floor((z - 2) / 4) * 4 + 2
    local u, v = (x - x0) / 4, (z - z0) / 4
    local a = sample(x0, z0) * (1 - u) + sample(x0 + 4, z0) * u
    local b = sample(x0, z0 + 4) * (1 - u) + sample(x0 + 4, z0 + 4) * u
    -- Match the center-of-cell surface offset used by the local dig preview.
    return a * (1 - v) + b * v + 2
end

return table.freeze({ height = height, sample = sample })
