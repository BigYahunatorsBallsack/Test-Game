--!strict
-- Export the existing starter clips and their sand art with Lune.
local fs = require("@lune/fs")
local rbx = require("@lune/roblox")
local luau = require("@lune/luau")
local new, V, C, A, E =
    rbx.Instance.new, rbx.Vector3.new, rbx.CFrame.new, rbx.CFrame.Angles, rbx.Enum
local output = "assets/models/starter_sand_fx/"
local source = fs.readFile(output .. "StarterSandFX.luau")
luau.compile(source)
local pack = new("Folder")
pack.Name = "DuneBaronStarterSand"
local module = new("ModuleScript")
module.Name, module.Source, module.Parent = "StarterSandFX", source, pack

local function part(
    parent: Instance,
    class: string,
    name: string,
    size: Vector3,
    at: CFrame,
    fixed: boolean
)
    local item = new(class)
    item.Name, item.Size, item.CFrame = name, size, at
    item.Material, item.Transparency = E.Material.Sand, 1
    item.Anchored, item.Massless, item.CastShadow = fixed, true, false
    item.CanCollide, item.CanQuery, item.CanTouch = false, false, false
    item.Parent = parent
    return item
end

local function load(tool: string, scale: number)
    local folder = new("Folder")
    folder.Name, folder.Parent = tool .. "Load", module
    local function put(name: string, size: Vector3, pos: Vector3, angle: number, tone: string)
        local chunk =
            part(folder, "WedgePart", name, size * scale, C(pos * scale) * A(0, angle, 0), false)
        chunk:SetAttribute("Tone", tone)
    end
    put("Bank", V(0.65, 0.18, 0.38), V(0, 0.072, 0.015), 0.10, "base")
    put("Crest", V(0.46, 0.15, 0.32), V(-0.02, 0.10, -0.07), math.pi + 0.17, "highlight")
    put("Sand lip", V(0.55, 0.085, 0.19), V(0.015, 0.029, -0.17), math.pi - 0.13, "shadow")
end

load("Hand", 0.55)
load("Shovel", 1)

local cut = part(module, "Part", "CutOrigin", V(0.10, 0.08, 0.10), C(), true)
local pour = part(module, "Part", "PourOrigin", V(0.09, 0.08, 0.13), C(), true)

local function sequence(samples: { { number } }): NumberSequence
    local keys = {}
    for i, t in samples do
        keys[i] = rbx.NumberSequenceKeypoint.new(t[1], t[2], t[3] or 0)
    end
    return rbx.NumberSequence.new(keys)
end

local function particle(parent: BasePart, name: string, dust: boolean, directed: boolean)
    local emitter = new("ParticleEmitter")
    emitter.Name, emitter.Enabled, emitter.Rate = name, false, 0
    emitter.Texture = "rbxasset://textures/particles/"
        .. (if dust then "smoke_main.dds" else "SquareParticle.png")
    emitter.EmissionDirection = if directed then E.NormalId.Front else E.NormalId.Top
    emitter.SpreadAngle = if directed then rbx.Vector2.new(13, 13) else rbx.Vector2.new(64, 64)
    emitter.Speed = if dust then rbx.NumberRange.new(1.05, 2.45) else rbx.NumberRange.new(1.34, 3.2)
    emitter.Lifetime = if dust
        then rbx.NumberRange.new(0.28, 0.48)
        else rbx.NumberRange.new(0.16, 0.33)
    emitter.Acceleration = V(0, if dust then 1.05 elseif directed then -21 else -8.6, 0)
    emitter.Drag = if directed then 0 elseif dust then 1.26 else 0.38
    emitter.LightInfluence, emitter.LockedToPart = 0.73, false
    emitter.Rotation, emitter.RotSpeed = rbx.NumberRange.new(0, 360), rbx.NumberRange.new(-95, 95)
    emitter.Transparency = if dust
        then sequence({ { 0, 0.77 }, { 0.24, 0.56 }, { 0.67, 0.76 }, { 1, 1 } })
        else sequence({ { 0, 0.12 }, { 0.73, 0.38 }, { 1, 1 } })
    emitter.Size = if dust
        then sequence({ { 0, 0.27 }, { 0.50, 0.64, 0.15 }, { 1, 1.03, 0.22 } })
        else sequence({ { 0, 0.075, 0.028 }, { 0.79, 0.052, 0.018 }, { 1, 0.026 } })
    emitter.Parent = parent
end

particle(cut, "Dust", true, false)
particle(cut, "Grains", false, false)
particle(pour, "Stream", false, true)

local hand =
    rbx.deserializeModel(fs.readFile("assets/models/hand_scoop/DuneBaron_HandScoop.rbxm"))[1]
local equipment = rbx.deserializeModel(
    fs.readFile("assets/models/equipment_animation/DuneBaron_Equipment_Animations.rbxm")
)[1]
hand.Parent = pack
equipment.shovel:Clone().Parent = pack

local bytes = rbx.serializeModel({ pack })
local roundtrip = rbx.deserializeModel(bytes)[1]
local reloaded = roundtrip.StarterSandFX
assert(reloaded.Source == source)
for _, tool in { "HandLoad", "ShovelLoad" } do
    local folder = reloaded:FindFirstChild(tool)
    assert(#folder:GetChildren() == 3)
    for _, piece in folder:GetChildren() do
        assert(
            piece.Massless
                and not piece.Anchored
                and not piece.CanCollide
                and piece.Transparency == 1
        )
    end
end
assert(not reloaded.CutOrigin.Dust.Enabled and not reloaded.PourOrigin.Stream.Enabled)
assert(roundtrip.DuneBaronHandScoop.HandScoopLoop.Loop and roundtrip.shovel.ShovelWorkLoop.Loop)
fs.writeFile(output .. "DuneBaron_Starter_Sand_FX.rbxm", bytes)
print("Starter clips and sand art verified after serialization")
