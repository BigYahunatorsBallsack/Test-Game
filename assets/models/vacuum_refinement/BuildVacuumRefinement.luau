--!strict
-- Offline authoring for the vacuum robot's intake and sand tank.
local rbx = require("@lune/roblox")
local fs = require("@lune/fs")
local C, V = rbx.CFrame.new, rbx.Vector3.new
local I = rbx.CFrame.identity
local axes = rbx.Vector3
local Enum = rbx.Enum
local rgb = rbx.Color3.fromRGB

local source = rbx.deserializeModel(
    fs.readFile("assets/models/equipment_sand_fx/DuneBaron_Equipment_SandFX.rbxm")
)[1].vacuum_robot
local robot = source:Clone()
local root = robot.Root :: BasePart
local intake = robot.Intake :: BasePart
local origin = root.CFrame
local work = robot.Animations.WorkLoop :: KeyframeSequence
local detail = rbx.Instance.new("Folder")
detail.Name, detail.Parent = "IntakeAndTank", robot

local bodyYellow = (robot["Intake Shoe"] :: BasePart).Color
local deepTeal = rgb(31, 77, 85)
local graphite = rgb(29, 42, 48)
local shadow = rgb(17, 26, 31)
local steel = rgb(85, 110, 117)
local warmMetal = rgb(196, 137, 54)

local function weld(parent: BasePart, part: BasePart, animated: boolean?)
    local link = rbx.Instance.new(if animated then "Motor6D" else "Weld")
    link.Name = part.Name
    link.Part0, link.Part1 = parent, part
    link.C0, link.C1 = parent.CFrame:ToObjectSpace(part.CFrame), I
    link.Parent = part
end

local function add(
    name: string,
    anchor: BasePart,
    localFrame: CFrame,
    size: Vector3,
    color: Color3,
    shape: Enum.PartType?,
    animated: boolean?
): Part
    local part = rbx.Instance.new("Part")
    part.Name, part.Size, part.Color = name, size, color
    part.CFrame, part.Shape = origin * localFrame, shape or Enum.PartType.Block
    part.Material = Enum.Material.SmoothPlastic
    part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
    part.Massless = true
    part.Parent = detail
    weld(anchor, part, animated)
    return part
end

local function refit(part: BasePart, anchor: BasePart, localFrame: CFrame, size: Vector3)
    local old = part:FindFirstChildWhichIsA("WeldConstraint")
    assert(old and old.Part0 == anchor and old.Part1 == part, part.Name)
    old:Destroy()
    part.Size, part.CFrame = size, origin * localFrame
    weld(anchor, part)
end

local function angle(x: number, y: number, z: number): CFrame
    return rbx.CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function pipe(
    name: string,
    start: Vector3,
    finish: Vector3,
    diameter: number,
    color: Color3
): Part
    local axis = (finish - start).Unit
    local hint = if math.abs(axis.Y) > 0.95 then axes.zAxis else axes.yAxis
    local up = (hint - axis * hint:Dot(axis)).Unit
    local frame = rbx.CFrame.fromMatrix((start + finish) * 0.5, axis, up)
    return add(
        name,
        root,
        frame,
        V((finish - start).Magnitude, diameter, diameter),
        color,
        Enum.PartType.Cylinder
    )
end

-- A real open slot around the existing WorkOrigin, with a baffle set behind the lip.
local shoe = robot["Intake Shoe"] :: Part
local mouth = robot["Intake Mouth"] :: Part
local intakeX = origin:ToObjectSpace(shoe.CFrame).X
local function atNozzle(x: number, y: number, z: number): CFrame
    return C(intakeX + x, y, z)
end
refit(shoe, intake, atNozzle(0, 0.312, -1.718), V(0.826, 0.089, 0.528))
refit(mouth, intake, atNozzle(0, 0.241, -1.748), V(0.633, 0.138, 0.075))
mouth.Color = shadow
local hazard = robot["Hazard Panel"] :: Part
refit(hazard, intake, atNozzle(0, 0.317, -1.990), V(0.619, 0.078, 0.030))
for _, stripe in robot:GetChildren() do
    if stripe.Name == "Safety Stripe" and stripe:IsA("BasePart") then
        local before = origin:ToObjectSpace(stripe.CFrame)
        refit(stripe, intake, before + V(0, 0.067, -0.018), V(0.072, 0.070, 0.016))
    end
end
add("Intake Lower Lip", intake, atNozzle(0, 0.173, -1.974), V(0.811, 0.037, 0.106), steel)
add("Intake Floor", intake, atNozzle(0, 0.172, -1.85), V(0.662, 0.036, 0.168), graphite)
for _, sign in { -1, 1 } do
    add(
        "Intake Cheek",
        intake,
        atNozzle(sign * 0.367, 0.231, -1.733),
        V(0.094, 0.145, 0.515),
        bodyYellow
    )
    add(
        "Intake Skid",
        intake,
        atNozzle(sign * 0.371, 0.166, -1.770),
        V(0.10, 0.032, 0.364),
        graphite
    )
    add(
        "Intake Rivet",
        intake,
        atNozzle(sign * 0.367, 0.314, -1.996) * angle(0, 90, 0),
        V(0.023, 0.044, 0.044),
        steel,
        Enum.PartType.Cylinder
    )
end
for slot = -1, 1 do
    add(
        "Intake Baffle",
        intake,
        atNozzle(slot * 0.173, 0.235, -1.833),
        V(0.021, 0.090, 0.13),
        graphite
    )
end

local glass = robot["Glass Tank"] :: Part
local tank = origin:ToObjectSpace(glass.CFrame).Position
glass.Transparency = 0.79
glass.Color = rgb(132, 199, 205)

local intakePosition = origin:ToObjectSpace(intake.CFrame).Position
local radial = V(intakePosition.X - tank.X, 0, intakePosition.Z - tank.Z).Unit
local cross = V(-radial.Z, 0, radial.X)
local function inside(r: number, height: number, sideways: number?): Vector3
    return V(tank.X, height, tank.Z) + radial * r + cross * (sideways or 0)
end

-- The stationary feed lug overlaps the rotating hose at the ball joint.
local entry = inside(0.802, 1.462)
local elbow = inside(0.534, 1.516)
local exit = inside(0.333, 1.701)
pipe("Hose Swivel Seat", inside(0.616, 1.462), inside(0.91, 1.462), 0.337, graphite)
pipe("Swivel Lock Ring", inside(0.731, 1.462), inside(0.792, 1.462), 0.382, warmMetal)
add(
    "Hose Swivel Ball",
    intake,
    C(inside(0.856, 1.472)),
    V(0.337, 0.337, 0.337),
    graphite,
    Enum.PartType.Ball
)
pipe("Tank Inlet Elbow", entry, elbow, 0.184, deepTeal)
local outletAxis = (exit - elbow).Unit
local outletSide = outletAxis:Cross(axes.yAxis).Unit
local outletUp = outletSide:Cross(outletAxis)
pipe("Tank Inlet Neck", elbow, exit - outletAxis * 0.055, 0.167, deepTeal)
add("Inlet Elbow Join", root, C(elbow), V(0.183, 0.183, 0.183), deepTeal, Enum.PartType.Ball)
for i = 0, 11 do
    local turn = i * math.pi / 6
    local outward = outletUp * math.cos(turn) + outletSide * math.sin(turn)
    local center = exit - outletAxis * 0.026 + outward * 0.084
    add(
        "Tank Outlet Rim",
        root,
        rbx.CFrame.fromMatrix(center, outletAxis, outward),
        V(0.068, 0.038, 0.054),
        warmMetal
    )
end
pipe("Swivel Support", inside(0.759, 1.077), inside(0.759, 1.451), 0.287, graphite)
pipe("Support Foot", inside(0.759, 1.027), inside(0.759, 1.093), 0.325, steel)
add("Tank Latch", root, C(inside(0.708, 1.866, 0.091)), V(0.144, 0.131, 0.175), deepTeal)

local fill = robot["Visible Sand"] :: Part
local sandColor = rgb(227, 181, 111)
local darkSand = rgb(198, 149, 83)
refit(fill, root, C(tank.X, 1.163, tank.Z) * angle(0, 0, 90), V(0.220, 1.296, 1.296))
fill.Color = sandColor
add(
    "Pressure Indicator Body",
    root,
    C(tank.X, 1.950, tank.Z - 0.782),
    V(0.325, 0.124, 0.074),
    graphite
)
add(
    "Pressure Indicator Window",
    root,
    C(tank.X, 1.950, tank.Z - 0.824),
    V(0.246, 0.068, 0.025),
    deepTeal
)
local indicator = add(
    "PressureLight",
    root,
    C(tank.X, 1.950, tank.Z - 0.809),
    V(0.200, 0.035, 0.014),
    rgb(100, 235, 206),
    nil,
    true
)
indicator.Material = Enum.Material.Neon
indicator.CastShadow = false
local pile = add(
    "SandLandingMound",
    root,
    C(inside(0.18, 1.264)),
    V(0.54, 0.147, 0.483),
    sandColor,
    Enum.PartType.Ball,
    true
)
for i = 1, 9 do
    local a = i * 2.399963
    local radius = 0.255 + (i % 3) * 0.098
    local position = V(tank.X + math.cos(a) * radius, 1.273, tank.Z + math.sin(a) * radius)
    add(
        "Settled Grain",
        root,
        C(position) * angle(10, i * 39, 3),
        V(0.057, 0.028, 0.047),
        if i % 2 == 0 then darkSand else rgb(246, 205, 132),
        Enum.PartType.Ball
    )
end

local grains = {}
for i = 1, 9 do
    local shade = if i % 3 == 0 then darkSand else rgb(249, 203, 121)
    local size = if i % 3 == 2 then 0.045 else 0.064
    grains[i] = add(
        string.format("SandInTransit%02d", i),
        root,
        C(entry),
        V(size, size * 0.82, size * 0.92),
        shade,
        if i % 2 == 0 then Enum.PartType.Ball else nil,
        true
    )
    grains[i].CastShadow = false
end

local function transit(index: number, time: number): CFrame
    local start = 0.685 + math.floor((index - 1) / 2) * 0.133 + ((index - 1) % 2) * 0.038
    local age = time - start
    if age <= 0 or age >= 0.592 then
        return I
    end
    local scatter = ((index % 5) - 2) * 0.030
    local position: Vector3
    if age < 0.071 then
        position = entry:Lerp(elbow, age / 0.071)
    elseif age < 0.151 then
        position = elbow:Lerp(exit, (age - 0.071) / 0.080)
    elseif age < 0.315 then
        local fall = (age - 0.151) / 0.164
        position =
            inside(0.333 - fall * 0.155, 1.701 + 0.023 * fall - 0.552 * fall ^ 2, fall * scatter)
    elseif age < 0.436 then
        position = inside(0.178, 1.172, scatter):Lerp(inside(0.754, 1.122), (age - 0.315) / 0.121)
    elseif age < 0.546 then
        position = inside(0.754, 1.122):Lerp(inside(0.754, 1.462), (age - 0.436) / 0.110)
    else
        position = inside(0.754, 1.462):Lerp(entry, (age - 0.546) / 0.046)
    end
    return C(position - entry) * angle(age * 238, index * 36 + age * 195, age * 192)
end

local function pose(parent: Pose, part: BasePart, transform: CFrame)
    local item = rbx.Instance.new("Pose")
    item.Name = part.Name
    item.CFrame = C(transform.Position / robot.Scale) * transform.Rotation
    item.Weight, item.EasingStyle = 1, Enum.PoseEasingStyle.Linear
    item.Parent = parent
end

local engage, release
for _, frame in work:GetChildren() do
    if frame:FindFirstChild("IntakeEngage") then
        engage = frame.Time
    end
    if frame:FindFirstChild("IntakeRelease") then
        release = frame.Time
    end
end
assert(engage and release)
for _, frame in work:GetChildren() do
    for i, grain in grains do
        pose(frame.Root, grain, transit(i, frame.Time))
    end
    pose(
        frame.Root,
        indicator,
        if frame.Time >= engage and frame.Time < release then C(0, 0, -0.035) else I
    )
    local bump = 0
    if frame.Time > 0.94 and frame.Time < 1.82 then
        local f = (frame.Time - 0.94) / 0.88
        bump = 0.023 * math.sin(math.pi * f) ^ 2
            + 0.011 * math.sin(math.pi * f) * math.sin(6 * math.pi * f)
    end
    pose(frame.Root, pile, C(0, bump, 0))
end
robot:SetAttribute("IntakeAndTankRevision", 1)

local path = "assets/models/vacuum_refinement/DuneBaron_VacuumRefinement.rbxm"
local bytes = rbx.serializeModel({ robot })
local restored = rbx.deserializeModel(bytes)[1]
assert(restored.Name == "vacuum_robot" and restored.PrimaryPart == restored.Root)
assert(restored.Intake.WorkOrigin.CFrame == source.Intake.WorkOrigin.CFrame)
assert(restored.SandEffects.Source == source.SandEffects.Source)
local function keys(clip: KeyframeSequence): { Keyframe }
    local frames = clip:GetChildren() :: { Keyframe }
    table.sort(frames, function(a, b)
        return a.Time < b.Time
    end)
    return frames
end
local originalKeys = keys(source.Animations.WorkLoop)
local revisedKeys = keys(restored.Animations.WorkLoop)
assert(#originalKeys == #revisedKeys and restored.Animations.WorkLoop.Loop)
for i, frame in originalKeys do
    local revised = revisedKeys[i]
    assert(frame.Time == revised.Time)
    for _, jointPose in frame.Root:GetChildren() do
        assert(jointPose.CFrame == revised.Root[jointPose.Name].CFrame, jointPose.Name)
    end
    for _, marker in frame:GetChildren() do
        if marker:IsA("KeyframeMarker") then
            assert(revised:FindFirstChild(marker.Name), marker.Name)
        end
    end
    assert(#revised.Root:GetChildren() == #frame.Root:GetChildren() + #grains + 2)
end
for _, object in detail:GetChildren() do
    if object:FindFirstChildWhichIsA("Motor6D") then
        local first, last = revisedKeys[1], revisedKeys[#revisedKeys]
        assert(first.Root[object.Name].CFrame == I and last.Root[object.Name].CFrame == I)
    end
end
fs.writeFile(path, bytes)
print(path, "49 validated keys with original suction markers")
