--!strict
-- Build the RBXM with Lune from the project root.
local fs = require("@lune/fs")
local rbx = require("@lune/roblox")
local luau = require("@lune/luau")
local V, Enum, new = rbx.Vector3.new, rbx.Enum, rbx.Instance.new
local root = "assets/world/sand_tracks/"
local source = fs.readFile(root .. "SandTracks.luau")
luau.compile(source)
local pack = new("Folder")
pack.Name = "DuneBaronSandTracks"
local module = new("ModuleScript")
module.Name, module.Source, module.Parent = "SandTracks", source, pack

local holder = new("Part")
holder.Name, holder.Size, holder.Transparency = "Footprint", V(0.70, 1.12, 0.06), 1
holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
holder.CastShadow, holder.Parent = false, module

local gui = new("SurfaceGui")
gui.Name, gui.Face, gui.Enabled = "Sole", Enum.NormalId.Back, false
gui.SizingMode, gui.CanvasSize = Enum.SurfaceGuiSizingMode.FixedSize, rbx.Vector2.new(96, 160)
gui.AlwaysOnTop, gui.LightInfluence, gui.MaxDistance = false, 0.48, 65
gui.Parent = holder

local function pad(
    name: string,
    x: number,
    y: number,
    width: number,
    length: number,
    corner: number,
    tone: string,
    strength: number,
    z: number,
    rotation: number?
)
    local shape = new("Frame")
    shape.Name = name
    shape.Position, shape.Size = rbx.UDim2.fromOffset(x, y), rbx.UDim2.fromOffset(width, length)
    shape.BorderSizePixel, shape.BackgroundTransparency, shape.ZIndex = 0, 1, z
    shape.Rotation = rotation or 0
    shape:SetAttribute("Tone", tone)
    shape:SetAttribute("Strength", strength)
    shape.Parent = gui
    local round = new("UICorner")
    round.CornerRadius, round.Parent = rbx.UDim.new(0, corner), shape
end

pad("Toe edge", 11, 6, 74, 77, 25, "edge", 0.72, 1)
pad("Arch edge", 29, 58, 37, 61, 13, "edge", 0.58, 1)
pad("Heel edge", 17, 105, 62, 49, 16, "edge", 0.71, 1)
pad("Toe", 15, 10, 65, 69, 22, "core", 0.83, 2)
pad("Arch", 31, 65, 32, 49, 11, "core", 0.74, 2)
pad("Heel", 21, 107, 54, 43, 13, "core", 0.81, 2)
pad("Forefoot tread", 25, 30, 45, 10, 3, "tread", 0.54, 3, -12)
pad("Midfoot tread", 25, 48, 45, 10, 3, "tread", 0.57, 3, 12)
pad("Heel tread", 32, 125, 31, 11, 3, "tread", 0.52, 3, -6)

local function keys(points: { { number } }): NumberSequence
    local result = {}
    for i, row in points do
        result[i] = rbx.NumberSequenceKeypoint.new(row[1], row[2], row[3] or 0)
    end
    return rbx.NumberSequence.new(result)
end

local function emitter(name: string, texture: string, isDust: boolean)
    local item = new("ParticleEmitter")
    item.Name, item.Texture = name, "rbxasset://textures/particles/" .. texture
    item.Enabled, item.Rate, item.LockedToPart = false, 0, false
    item.EmissionDirection, item.SpreadAngle = Enum.NormalId.Back, rbx.Vector2.new(65, 65)
    item.LightInfluence, item.LightEmission = 0.78, if isDust then 0.02 else 0.09
    item.Speed = if isDust then rbx.NumberRange.new(0.95, 2.45) else rbx.NumberRange.new(1.75, 4.3)
    item.Lifetime = if isDust
        then rbx.NumberRange.new(0.28, 0.51)
        else rbx.NumberRange.new(0.19, 0.35)
    item.Rotation = rbx.NumberRange.new(0, 360)
    item.RotSpeed = rbx.NumberRange.new(-95, 95)
    item.Drag = if isDust then 1.3 else 0.6
    item.Acceleration = V(0, if isDust then 0.78 else -8.0, 0)
    item.Transparency = if isDust
        then keys({ { 0, 0.80 }, { 0.16, 0.56 }, { 0.58, 0.72 }, { 1, 1 } })
        else keys({ { 0, 0.19 }, { 0.49, 0.40 }, { 1, 1 } })
    item.Size = if isDust
        then keys({ { 0, 0.23, 0.08 }, { 0.48, 0.78, 0.18 }, { 1, 1.19, 0.25 } })
        else keys({ { 0, 0.052, 0.021 }, { 0.62, 0.044, 0.012 }, { 1, 0.025 } })
    item.Parent = holder
end

emitter("Dust", "smoke_main.dds", true)
emitter("Grains", "SquareParticle.png", false)

local payload = rbx.serializeModel({ pack })
local verified = rbx.deserializeModel(payload)[1]
local template = verified.SandTracks.Footprint
assert(verified.SandTracks.Source == source)
assert(
    template.Anchored
        and not template.CanCollide
        and not template.CanQuery
        and not template.CanTouch
)
assert(not template.Sole.Enabled and not template.Dust.Enabled and not template.Grains.Enabled)
assert(#template.Sole:GetChildren() == 9)
for _, layer in template.Sole:GetChildren() do
    assert(layer:IsA("Frame") and layer:GetAttribute("Strength") and layer:GetAttribute("Tone"))
end
fs.writeFile(root .. "DuneBaron_Sand_Tracks.rbxm", payload)
print("Sand track assets verified", #verified:GetDescendants(), "instances")
