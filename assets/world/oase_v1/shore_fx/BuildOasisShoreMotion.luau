--!strict
-- Build the RBXM from the project root with Lune.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local Instance, Enum = roblox.Instance, roblox.Enum
local V, rgb = roblox.Vector3.new, roblox.Color3.fromRGB

local root = "assets/world/oase_v1/shore_fx/"
local source = fs.readFile(root .. "ShoreMotion.luau")
luau.compile(source)
local pack = Instance.new("Folder")
pack.Name = "DuneBaronOasisShoreFX"
pack:SetAttribute("ZoneId", "oasis")

local motion = Instance.new("ModuleScript")
motion.Name, motion.Source, motion.Parent = "ShoreMotion", source, pack

local function anchor(name: string, transparency: number): Part
    local holder = Instance.new("Part")
    holder.Name, holder.Size, holder.Transparency = name, V(0.1, 0.1, 0.1), transparency
    holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
    holder.CastShadow, holder.Parent = false, motion
    return holder
end

local spring = anchor("Spring", 1)
local spout = Instance.new("Attachment")
spout.Name, spout.Parent = "Spout", spring
local landing = Instance.new("Attachment")
landing.Name = "Basin"
landing.CFrame = roblox.CFrame.fromMatrix(V(0, 0.01, -0.54), V(0, -1, -0.18).Unit, V(1, 0, 0))
landing.Parent = spring
local impact = Instance.new("Attachment")
impact.Name, impact.CFrame, impact.Parent =
    "SurfaceImpact", roblox.CFrame.new(landing.CFrame.Position), spring

local function flow(
    name: string,
    startWidth: number,
    endWidth: number,
    color: Color3,
    transparency: number
)
    local beam = Instance.new("Beam")
    beam.Name, beam.Attachment0, beam.Attachment1 = name, spout, landing
    beam.CurveSize0, beam.CurveSize1, beam.Segments = 0.27, 0.20, 10
    beam.Width0, beam.Width1 = startWidth, endWidth
    beam.Color = roblox.ColorSequence.new(color, rgb(220, 248, 229))
    beam.Transparency = roblox.NumberSequence.new({
        roblox.NumberSequenceKeypoint.new(0, transparency + 0.12),
        roblox.NumberSequenceKeypoint.new(0.19, transparency),
        roblox.NumberSequenceKeypoint.new(0.83, transparency + 0.09),
        roblox.NumberSequenceKeypoint.new(1, 0.93),
    })
    beam.FaceCamera, beam.Enabled = true, false
    beam.LightInfluence, beam.LightEmission = 0.42, 0.16
    beam.Parent = spring
    return beam
end

flow("Trickle", 0.30, 0.17, rgb(124, 222, 209), 0.18)
local highlight = flow("Highlight", 0.115, 0.052, rgb(218, 253, 226), 0.43)
highlight.ZOffset = 0.025

local droplets = Instance.new("ParticleEmitter")
droplets.Name, droplets.Texture = "Splash", "rbxasset://textures/particles/SquareParticle.png"
droplets.Color = roblox.ColorSequence.new(rgb(192, 251, 231), rgb(154, 222, 208))
droplets.Size = roblox.NumberSequence.new({
    roblox.NumberSequenceKeypoint.new(0, 0.095, 0.028),
    roblox.NumberSequenceKeypoint.new(1, 0.026),
})
droplets.Transparency = roblox.NumberSequence.new({
    roblox.NumberSequenceKeypoint.new(0, 0.27),
    roblox.NumberSequenceKeypoint.new(0.62, 0.45),
    roblox.NumberSequenceKeypoint.new(1, 1),
})
droplets.Lifetime, droplets.Speed =
    roblox.NumberRange.new(0.20, 0.36), roblox.NumberRange.new(0.92, 1.65)
droplets.Acceleration, droplets.SpreadAngle = V(0, -4.7, 0), roblox.Vector2.new(21, 21)
droplets.Rate, droplets.LightInfluence, droplets.Enabled = 12, 0.38, false
droplets.EmissionDirection, droplets.Parent = Enum.NormalId.Top, impact

local sound = Instance.new("Sound")
sound.Name, sound.SoundId = "Platschen", ""
sound.Looped, sound.Volume = true, 0.40
sound.RollOffMinDistance, sound.RollOffMaxDistance = 4, 26
sound.RollOffMode, sound.Parent = Enum.RollOffMode.InverseTapered, impact

local pool = anchor("Pool", 0.42)
pool.Material, pool.Color = Enum.Material.SmoothPlastic, rgb(67, 159, 147)

local support = anchor("SpoutSupport", 0)
support.Size = V(1.38, 0.83, 0.94)
support.Material, support.Color = Enum.Material.Sandstone, rgb(193, 139, 94)
support.CastShadow = true

local outlet = anchor("GlazedOutlet", 0)
outlet.Shape, outlet.Size = Enum.PartType.Cylinder, V(0.09, 0.55, 0.55)
outlet.Material, outlet.Color = Enum.Material.SmoothPlastic, rgb(56, 125, 120)
local opening = anchor("OutletOpening", 0)
opening.Shape, opening.Size = Enum.PartType.Cylinder, V(0.055, 0.33, 0.33)
opening.Material, opening.Color = Enum.Material.SmoothPlastic, rgb(39, 67, 68)

local ring = anchor("Ripple", 1)
local surface = Instance.new("SurfaceGui")
surface.Name, surface.Face, surface.Enabled = "RingSurface", Enum.NormalId.Top, false
surface.SizingMode, surface.CanvasSize =
    Enum.SurfaceGuiSizingMode.FixedSize, roblox.Vector2.new(160, 160)
surface.MaxDistance, surface.LightInfluence, surface.AlwaysOnTop = 72, 0.24, false
surface.Parent = ring

local frame = Instance.new("Frame")
frame.Name, frame.AnchorPoint = "Ring", roblox.Vector2.new(0.5, 0.5)
frame.Size, frame.Position = roblox.UDim2.fromScale(0.3, 0.3), roblox.UDim2.fromScale(0.5, 0.5)
frame.BackgroundTransparency, frame.BorderSizePixel, frame.Parent = 1, 0, surface
local circle = Instance.new("UICorner")
circle.CornerRadius, circle.Parent = roblox.UDim.new(0.5, 0), frame
local line = Instance.new("UIStroke")
line.Name, line.Color = "Line", rgb(190, 245, 220)
line.Thickness, line.Transparency = 2.1, 1
line.ApplyStrokeMode, line.Parent = Enum.ApplyStrokeMode.Border, frame

local data = roblox.serializeModel({ pack })
local verified = roblox.deserializeModel(data)[1]
local module = verified.ShoreMotion
assert(module.Source == source)
for _, holder in module:GetChildren() do
    assert(
        holder.Anchored and not holder.CanCollide and not holder.CanQuery and not holder.CanTouch
    )
end
assert(module.Spring.Trickle.Attachment0 == module.Spring.Spout)
assert(module.Spring.Trickle.Attachment1 == module.Spring.Basin)
assert(not module.Spring.Highlight.Enabled and not module.Spring.SurfaceImpact.Splash.Enabled)
assert(module.Spring.SurfaceImpact.CFrame.Position == module.Spring.Basin.CFrame.Position)
assert(
    module.Spring.SurfaceImpact.Platschen.Looped
        and module.Spring.SurfaceImpact.Platschen.RollOffMaxDistance == 26
)
assert(
    not module.Ripple.RingSurface.Enabled and module.Ripple.RingSurface.Ring.Line.Transparency == 1
)
fs.writeFile(root .. "DuneBaron_Oasis_Shore_FX.rbxm", data)
print("Oasis shore model package verified", #verified:GetDescendants(), "instances")
