--!strict
-- Author the cutter head and sand elevator on the existing harvester rig.
local rbx = require("@lune/roblox")
local fs = require("@lune/fs")
local C, V = rbx.CFrame.new, rbx.Vector3.new
local I = rbx.CFrame.identity
local Enum = rbx.Enum
local rgb = rbx.Color3.fromRGB

local source = rbx.deserializeModel(
    fs.readFile("assets/models/driver_cabs/DuneBaron_DriverCabs.rbxm")
)[1].mega_machine
local machine = source:Clone()
local root = machine.Root :: BasePart
local origin = root.CFrame
local work = machine.Animations.WorkLoop :: KeyframeSequence
local detail = rbx.Instance.new("Folder")
detail.Name, detail.Parent = "CutterAndElevator", machine

local dark = rgb(34, 49, 56)
local steel = rgb(68, 87, 94)
local worn = rgb(155, 175, 177)
local ochre = rgb(197, 138, 50)
local teal = rgb(41, 101, 109)
local sand = rgb(218, 172, 103)
local lightSand = rgb(237, 191, 116)

local function join(anchor: BasePart, part: BasePart, animated: boolean?)
    local link = rbx.Instance.new(if animated then "Motor6D" else "Weld")
    link.Name = part.Name
    link.Part0, link.Part1 = anchor, part
    link.C0, link.C1 = anchor.CFrame:ToObjectSpace(part.CFrame), I
    link.Parent = part
end

local function part(
    name: string,
    anchor: BasePart,
    at: CFrame,
    size: Vector3,
    tint: Color3,
    shape: Enum.PartType?,
    animated: boolean?,
    sandy: boolean?
): Part
    local piece = rbx.Instance.new("Part")
    piece.Name, piece.CFrame, piece.Size = name, origin * at, size
    piece.Color, piece.Shape = tint, shape or Enum.PartType.Block
    piece.Material = if sandy then Enum.Material.Sand else Enum.Material.SmoothPlastic
    piece.TopSurface, piece.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    piece.CanCollide, piece.CanTouch, piece.CanQuery = false, false, false
    piece.Massless, piece.Parent = true, detail
    join(anchor, piece, animated)
    return piece
end

local function lift(partToMove: BasePart, height: number)
    local link = assert(partToMove:FindFirstChildWhichIsA("WeldConstraint"), partToMove.Name)
    assert(link.Part0 == root and link.Part1 == partToMove)
    link:Destroy()
    partToMove.CFrame += V(0, height, 0)
    join(root, partToMove)
end

local heights = {
    ["Front Lip"] = 0.44,
    ["Hazard Panel"] = 0.57,
    ["Safety Stripe"] = 0.57,
    ["Intake Work Light Housing"] = 0.49,
    ["Intake Work Light"] = 0.49,
}
for _, piece in machine:GetChildren() do
    if not piece:IsA("BasePart") then
        continue
    end
    if piece.Name == "Cutter" or piece.Name == "Replaceable Lug" then
        piece:Destroy()
    elseif heights[piece.Name] then
        lift(piece, heights[piece.Name])
    elseif piece.Name == "Intake Side Armour" then
        local at = origin:ToObjectSpace(piece.CFrame)
        local side = math.sign(at.X)
        part(
            "Side Armour Wear Rail",
            root,
            at * C(side * 0.435, -1.32, 0),
            V(0.19, 0.29, 4.28),
            steel
        )
        for _, z in { -1.66, 1.56 } do
            part(
                "Side Armour Fastener",
                root,
                at * C(side * 0.47, -0.73, z),
                V(0.126, 0.26, 0.26),
                worn,
                Enum.PartType.Cylinder
            )
        end
    end
end

-- Each drum has three offset rows. The shoulder sits on the drum and carries a
-- wedge whose small radial envelope clears the lip and the two side lights.
for _, drum in { machine.Drum_L, machine.Drum_R } do
    local at = origin:ToObjectSpace(drum.CFrame)
    for row = -1, 1 do
        for tooth = 0, 7 do
            local slot = at
                * rbx.CFrame.Angles(tooth * math.pi / 4 + row * 0.235, 0, 0)
                * C(row * 1.85, 0, 0)
            part("Cutter Socket", drum, slot * C(0, 2.322, 0.063), V(0.94, 0.36, 0.739), ochre)
            part("Cutter Heel", drum, slot * C(0, 2.519, 0.190), V(0.73, 0.22, 0.39), steel)
            part(
                "Cutter Wedge",
                drum,
                slot * C(0, 2.659, -0.094),
                V(0.69, 0.36, 0.645),
                worn,
                Enum.PartType.Wedge
            )
        end
    end
end
part("Drum Divider", root, C(0, 3.65, -8.13), V(0.198, 4.83, 2.18), dark)
part(
    "Divider Wear Nose",
    root,
    C(0, 3.59, -9.32) * rbx.CFrame.Angles(0, math.pi, 0),
    V(0.20, 3.88, 1.46),
    steel,
    Enum.PartType.Wedge
)
part("Divider Mount", root, C(0, 6.05, -7.51), V(0.32, 0.52, 0.94), steel)

local bin = machine["Sand in Hopper"] :: BasePart
local tankX = origin:ToObjectSpace(bin.CFrame).X
local feed = V(tankX, 7.92, -7.07)
local exit = V(tankX, 11.35, -3.02)
local run = (exit - feed).Magnitude
local tangent = (exit - feed).Unit
local upward = V(0, tangent.Z, -tangent.Y)
local carrier = rbx.CFrame.fromMatrix(feed, rbx.Vector3.xAxis, upward)
local radius = 0.285
local halfTurn = math.pi * radius
local circuit = 2 * (run + halfTurn)
local laneCount = 6
local dischargeDistance = run + 0.25
local phaseAtFirstDump = 0.45
local startDistance = dischargeDistance - phaseAtFirstDump * circuit / laneCount

part("Elevator Pan", root, carrier * C(0, 0, run / 2), V(2.16, 0.347, run), dark)
part("Elevator Belt Face", root, carrier * C(0, 0.246, run / 2), V(1.95, 0.080, run), dark)
part("Elevator Return Face", root, carrier * C(0, -0.255, run / 2), V(1.95, 0.069, run), dark)
for _, side in { -1, 1 } do
    part(
        "Elevator Side Rail",
        root,
        carrier * C(side * 1.11, 0.049, run / 2),
        V(0.207, 0.74, run + 0.61),
        steel
    )
    part(
        "Elevator Wear Edge",
        root,
        carrier * C(side * 1.11, 0.432, run / 2),
        V(0.214, 0.078, run + 0.65),
        ochre
    )
    for _, distance in { 0.50, run - 0.52 } do
        part(
            "Elevator Gusset",
            root,
            carrier * C(side * 1.095, -0.322, distance),
            V(0.24, 0.38, 0.56),
            teal
        )
    end
end
for _, point in { feed, exit } do
    part(
        "Elevator Roller",
        root,
        C(point),
        V(2.019, radius * 2, radius * 2),
        dark,
        Enum.PartType.Cylinder
    )
end
part("Elevator Feed Base", root, carrier * C(0, -0.54, -0.12), V(2.66, 0.29, 0.96), steel)
part("Feed Housing Cap", root, carrier * C(0, 0.493, -0.24), V(2.52, 0.159, 0.58), ochre)
for _, side in { -1, 1 } do
    part(
        "Feed Housing Side",
        root,
        carrier * C(side * 1.16, -0.03, -0.20),
        V(0.285, 1.03, 0.76),
        steel
    )
end
part("Outlet Left Cheek", root, carrier * C(-1.04, 0.058, run + 0.36), V(0.15, 0.41, 0.40), teal)
part("Outlet Right Cheek", root, carrier * C(1.04, 0.058, run + 0.36), V(0.15, 0.41, 0.40), teal)

local function beltFrame(distance: number): CFrame
    local d = distance % circuit
    local center, outward
    if d < run then
        center, outward = feed + tangent * d, upward
    elseif d < run + halfTurn then
        local angle = (d - run) / radius
        center, outward = exit, upward * math.cos(angle) + tangent * math.sin(angle)
    elseif d < 2 * run + halfTurn then
        center, outward = exit - tangent * (d - run - halfTurn), -upward
    else
        local angle = (d - 2 * run - halfTurn) / radius
        center, outward = feed, -upward * math.cos(angle) - tangent * math.sin(angle)
    end
    return rbx.CFrame.fromMatrix(center + outward * radius, rbx.Vector3.xAxis, outward)
end

local function smooth(value: number): number
    local u = math.clamp(value, 0, 1)
    return u * u * (3 - 2 * u)
end

local function content(distance: number): CFrame
    local d = distance % circuit
    local fill = smooth((d - 0.15) / 0.42) * (1 - smooth((d - run + 0.15) / 0.34))
    return C(0.038, -0.185 + 0.280 * fill, 0.267 * fill)
end

local function station(i: number, phase: number): number
    return startDistance + circuit * (phase + (i - 1) / laneCount)
end

local lanes = {}
for i = 1, laneCount do
    local d = station(i, 0)
    local at, cargo = beltFrame(d), content(d)
    local paddle = part(
        string.format("ElevatorCleat%02d", i),
        root,
        at,
        V(1.84, 0.184, 0.182),
        rgb(92, 115, 121),
        nil,
        true
    )
    local load = part(
        string.format("ElevatorSand%02d", i),
        paddle,
        at * cargo,
        V(1.50, 0.122, 0.495),
        sand,
        Enum.PartType.Ball,
        true,
        true
    )
    local ridge = at * cargo * C(-0.22, 0.029, -0.033)
    part(
        "Elevator Sand Ridge",
        load,
        ridge * rbx.CFrame.Angles(0, 0.13, 0),
        V(0.77, 0.119, 0.34),
        lightSand,
        Enum.PartType.Ball,
        nil,
        true
    )
    part(
        "Elevator Loose Sand",
        load,
        at * cargo * C(0.39, 0.012, 0.062),
        V(0.45, 0.095, 0.34),
        rgb(226, 182, 109),
        Enum.PartType.Ball,
        nil,
        true
    )
    lanes[i] = { paddle = paddle, load = load, at = at, cargo = cargo }
end

bin.Color, bin.Material = sand, Enum.Material.Sand
part(
    "Hopper Bed Ridge",
    root,
    C(tankX + 0.23, 8.016, 0.10),
    V(2.20, 0.472, 2.26),
    sand,
    Enum.PartType.Ball,
    nil,
    true
)
local mound = part(
    "HopperSandLanding",
    root,
    C(tankX - 0.12, 8.039, -2.02),
    V(2.33, 0.515, 1.65),
    lightSand,
    Enum.PartType.Ball,
    true,
    true
)

local dropPoint = beltFrame(dischargeDistance):PointToWorldSpace(V(0, 0.082, 0.24))
local drop = rbx.Instance.new("Attachment")
drop.Name = "HopperDischarge"
drop.CFrame = rbx.CFrame.lookAt(dropPoint, dropPoint + V(0, -1, 0.32))
drop.Parent = root
local fxSource
for _, effect in root.SandFxCutterLeft:GetChildren() do
    if effect:IsA("ParticleEmitter") and effect:GetAttribute("BurstCount") == 15 then
        fxSource = effect
    end
end
assert(fxSource)
local grains = fxSource:Clone()
grains.Name, grains.Parent = "HopperGrainFall", drop
grains:SetAttribute("Side", nil)
grains:SetAttribute("Marker", "HopperDrop")
grains:SetAttribute("BurstCount", 11)
grains.Size = rbx.NumberSequence.new(0.155)
grains.Lifetime, grains.Speed = rbx.NumberRange.new(0.38, 0.48), rbx.NumberRange.new(1.9, 3.1)
grains.SpreadAngle, grains.Acceleration = rbx.Vector2.new(17, 14), V(0, -35, 0)

local function sortedKeys(clip: KeyframeSequence): { Keyframe }
    local frames = clip:GetChildren() :: { Keyframe }
    table.sort(frames, function(a, b)
        return a.Time < b.Time
    end)
    return frames
end

local function channel(container: Instance, name: string, transform: CFrame, weight: number?): Pose
    local p = rbx.Instance.new("Pose")
    p.Name, p.Weight = name, weight or 1
    p.CFrame = C(transform.Position / machine.Scale) * transform.Rotation
    p.EasingStyle, p.Parent = Enum.PoseEasingStyle.Linear, container
    return p
end

local previousFrames = sortedKeys(work)
local duration = previousFrames[#previousFrames].Time
local drops = {}
for i = 1, laneCount do
    drops[i] = (i - 1 + phaseAtFirstDump) * duration / laneCount
end

local function writeFrame(frame: Keyframe, t: number)
    local time = if t == duration then 0 else t
    local parent = frame.Root :: Pose
    for index, lane in lanes do
        local d = station(index, time / duration)
        local push = channel(parent, lane.paddle.Name, lane.at:ToObjectSpace(beltFrame(d)))
        channel(push, lane.load.Name, lane.cargo:ToObjectSpace(content(d)))
    end
    local sway = 0
    for _, stamp in drops do
        local age = (time - stamp - 0.375) % duration
        if age < 0.17 then
            sway += 0.068 * math.sin(math.pi * age / 0.17) ^ 2
        end
    end
    channel(parent, mound.Name, C(0, sway, 0))
end

local function inbetween(a: Keyframe, b: Keyframe, time: number, marker: boolean?)
    local frame = rbx.Instance.new("Keyframe")
    frame.Name, frame.Time, frame.Parent = "Keyframe", time, work
    local basePose = channel(frame, "Root", I, 0)
    local f = (time - a.Time) / (b.Time - a.Time)
    for _, name in { "Drum_L", "Drum_R" } do
        channel(basePose, name, a.Root[name].CFrame:Lerp(b.Root[name].CFrame, f))
    end
    if marker then
        local cue = rbx.Instance.new("KeyframeMarker")
        cue.Name, cue.Parent = "HopperDrop", frame
    end
    writeFrame(frame, time)
end

for i, frame in previousFrames do
    if i > 1 then
        local before = previousFrames[i - 1]
        inbetween(before, frame, (before.Time + frame.Time) / 2)
        for _, stamp in drops do
            if stamp > before.Time and stamp <= frame.Time then
                inbetween(before, frame, stamp, true)
            end
        end
    end
    writeFrame(frame, frame.Time)
end

machine:SetAttribute("CutterAndElevatorRevision", 1)
local bytes = rbx.serializeModel({ machine })
local restored = rbx.deserializeModel(bytes)[1]
assert(restored.Name == "mega_machine" and restored.PrimaryPart == restored.Root)
assert(restored.Root.WorkOrigin.CFrame == source.Root.WorkOrigin.CFrame)
assert(restored.Root.DriverRoot.CFrame == source.Root.DriverRoot.CFrame)
assert(restored.Root.DriverMount.CFrame == source.Root.DriverMount.CFrame)
assert(restored.SandEffects.Source == source.SandEffects.Source)
assert(#restored.DriverAnimations:GetChildren() == 3)
local frames = sortedKeys(restored.Animations.WorkLoop)
local loads, pours = 0, 0
for i, frame in frames do
    if i > 1 then
        assert(frame.Time > frames[i - 1].Time)
    end
    if frame:FindFirstChild("CutterLoad") then
        loads += 1
    end
    if frame:FindFirstChild("HopperDrop") then
        pours += 1
        assert(math.abs(frame.Time - drops[pours]) < 0.000001)
    end
end
assert(loads == 2 and pours == laneCount and frames[#frames].Time == duration)
for _, channelPose in frames[1].Root:GetDescendants() do
    local first, last =
        channelPose.CFrame, frames[#frames].Root:FindFirstChild(channelPose.Name, true).CFrame
    local gap = first:ToObjectSpace(last)
    assert(gap.Position.Magnitude < 0.0001 and gap.LookVector.Z < -0.99999, channelPose.Name)
end
local path = "assets/models/harvester_refinement/DuneBaron_HarvesterRefinement.rbxm"
fs.writeFile(path, bytes)
print(path, "48 teeth with 6 transport cleats and 8 work cues")
