--!strict
-- Author the bucket load, tilt cylinder and hydraulic hoses on the seated excavator rig.
local rbx = require("@lune/roblox")
local fs = require("@lune/fs")
local C, V = rbx.CFrame.new, rbx.Vector3.new
local I = rbx.CFrame.identity
local Enum = rbx.Enum
local rgb = rbx.Color3.fromRGB

local source = rbx.deserializeModel(
    fs.readFile("assets/models/driver_cabs/DuneBaron_DriverCabs.rbxm")
)[1].mini_digger
local machine = source:Clone()
local root = machine.Root :: BasePart
local scoop = machine.Scoop :: BasePart
local stick = machine.Stick :: BasePart
local boom = machine.Boom :: BasePart
local turret = machine.Turret :: BasePart
local scale = machine.Scale
assert(scale > 0)
local origin = root.CFrame
local detail = rbx.Instance.new("Folder")
detail.Name, detail.Parent = "ExcavatorDetails", machine

local dark = rgb(31, 47, 54)
local rubber = rgb(34, 49, 56)
local steel = rgb(71, 96, 103)
local polished = rgb(154, 174, 178)
local ochre = rgb(198, 137, 54)
local sand = rgb(218, 172, 102)
local sandBright = rgb(234, 187, 116)

local function join(anchor: BasePart, part: BasePart, animated: boolean?): JointInstance
    local link = rbx.Instance.new(if animated then "Motor6D" else "Weld")
    link.Name = part.Name
    link.Part0, link.Part1 = anchor, part
    link.C0, link.C1 = anchor.CFrame:ToObjectSpace(part.CFrame), I
    link.Parent = part
    return link
end

local function part(
    parent: Instance,
    anchor: BasePart,
    name: string,
    localFrame: CFrame,
    size: Vector3,
    color: Color3,
    shape: Enum.PartType?,
    animated: boolean?,
    isSand: boolean?
): Part
    local p = rbx.Instance.new("Part")
    p.Name, p.Size, p.CFrame = name, size, anchor.CFrame * localFrame
    p.Color, p.Shape = color, shape or Enum.PartType.Block
    p.Material = if isSand then Enum.Material.Sand else Enum.Material.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
    p.Parent = parent
    join(anchor, p, animated)
    return p
end

local function frameBetween(a: Vector3, b: Vector3, side: Vector3): CFrame
    local axis = (b - a).Unit
    local z = (side - axis * axis:Dot(side)).Unit
    return rbx.CFrame.fromMatrix((a + b) * 0.5, axis, z:Cross(axis), z)
end

local function pipe(
    anchor: BasePart,
    name: string,
    a: Vector3,
    b: Vector3,
    diameter: number,
    color: Color3
): Part
    return part(
        detail,
        anchor,
        name,
        frameBetween(a, b, rbx.Vector3.xAxis),
        V((b - a).Magnitude + 0.039, diameter, diameter),
        color,
        Enum.PartType.Cylinder
    )
end

type Arm = { [string]: CFrame }
local kinematics: { [string]: Motor6D } = {}
for _, link in machine:GetDescendants() do
    if link:IsA("Motor6D") and link.Part1 then
        kinematics[link.Part1.Name] = link
    end
end

local function armAt(frame: Keyframe): Arm
    local cf, p = I, frame.Root
    local arm = {}
    for _, name in { "Turret", "Boom", "Stick", "Scoop" } do
        p = p[name]
        local j = kinematics[name]
        local change = p.CFrame
        cf = cf * j.C0 * C(change.Position * scale) * change.Rotation * j.C1:Inverse()
        arm[name] = cf
    end
    return arm
end

local rest: Arm = {}
for _, link in { turret, boom, stick, scoop } do
    rest[link.Name] = origin:ToObjectSpace(link.CFrame)
end
local function framesIn(sequence: KeyframeSequence): { Keyframe }
    local frames = sequence:GetChildren() :: { Keyframe }
    table.sort(frames, function(a, b)
        return a.Time < b.Time
    end)
    return frames
end

local work = framesIn(machine.Animations.WorkLoop)
local arms: { [Keyframe]: Arm } = {}
local loadTime, dumpTime
for _, frame in work do
    arms[frame] = armAt(frame)
    if frame:FindFirstChild("BucketLoaded") then
        loadTime = frame.Time
    end
    if frame:FindFirstChild("BucketDump") then
        dumpTime = frame.Time
    end
end
assert(loadTime and dumpTime)

-- A pinned tilt cylinder sits outside the stick channel and turns with the bucket.
local pinA, pinB = V(0.65, -1.47, -0.82), V(0.65, -0.43, -0.31)
local barrelLength, rodLength = 1.405, 1.115
local function cylinderFrames(arm: Arm): (CFrame, CFrame)
    local a = arm.Stick:PointToWorldSpace(pinA)
    local b = arm.Scoop:PointToWorldSpace(pinB)
    local axis = (b - a).Unit
    local barrel = frameBetween(a, a + axis * barrelLength, arm.Turret.RightVector)
    local rod = frameBetween(b - axis * rodLength, b, arm.Turret.RightVector)
    return barrel, rod
end

local barrelAt, rodAt = cylinderFrames(rest)
local barrel = part(
    detail,
    root,
    "BucketTiltBarrel",
    barrelAt,
    V(barrelLength, 0.229, 0.229),
    ochre,
    Enum.PartType.Cylinder,
    true
)
local rod = part(
    detail,
    root,
    "BucketTiltRod",
    rodAt,
    V(rodLength, 0.132, 0.132),
    polished,
    Enum.PartType.Cylinder,
    true
)
part(
    detail,
    barrel,
    "Bucket Tilt Gland",
    C(barrelLength / 2 - 0.060, 0, 0),
    V(0.132, 0.279, 0.279),
    dark,
    Enum.PartType.Cylinder
)
part(
    detail,
    rod,
    "Bucket Tilt Rod Eye",
    C(rodLength / 2 - 0.033, 0, 0),
    V(0.160, 0.220, 0.220),
    steel,
    Enum.PartType.Cylinder
)
part(
    detail,
    stick,
    "Tilt Cylinder Stick Bracket",
    C(0.414, pinA.Y + 0.024, pinA.Z),
    V(0.335, 0.273, 0.325),
    ochre
)
part(
    detail,
    scoop,
    "Tilt Cylinder Bucket Bracket",
    C(0.414, pinB.Y + 0.113, pinB.Z + 0.06),
    V(0.378, 0.272, 0.390),
    steel
)
for _, row in { { stick, pinA }, { scoop, pinB } } do
    local anchor, center = row[1] :: BasePart, row[2] :: Vector3
    part(
        detail,
        anchor,
        "Tilt Cylinder Hinge Pin",
        C(center - V(0.102, 0, 0)),
        V(0.338, 0.187, 0.187),
        steel,
        Enum.PartType.Cylinder
    )
    part(
        detail,
        anchor,
        "Tilt Cylinder Pin Cap",
        C(center + V(0.089, 0, 0)),
        V(0.053, 0.161, 0.161),
        polished,
        Enum.PartType.Cylinder
    )
end

-- The two rubber spans are supported at the knuckle by fixed pipe ends.
local spanPieces = 6
local function connectorPoints(lane: number): (Vector3, Vector3)
    local x = 0.646 + 0.180 * lane
    local row = (lane - 1) * 0.027
    return V(x, 1.99 - row, -2.62 - row), V(x, -0.50 - row, -0.38 + row)
end

local function hosePoints(arm: Arm, lane: number): { Vector3 }
    local endOnBoom, endOnStick = connectorPoints(lane)
    local a = arm.Boom:PointToWorldSpace(endOnBoom)
    local d = arm.Stick:PointToWorldSpace(endOnStick)
    local fixedOffset = arm.Turret.RightVector * 0.124
    local b = a + fixedOffset + arm.Boom:VectorToWorldSpace(V(0, 0.077, -0.31))
    local c = d + fixedOffset + arm.Stick:VectorToWorldSpace(V(0, 0.21, 0.19))
    local points = {}
    for s = 0, spanPieces do
        local t, u = s / spanPieces, 1 - s / spanPieces
        points[s + 1] = a * u ^ 3 + b * (3 * u ^ 2 * t) + c * (3 * u * t ^ 2) + d * t ^ 3
    end
    return points
end

local hoses = {}
local function strap(anchor: BasePart, point: Vector3, armSide: number, name: string)
    local edge = point.X + 0.053
    part(
        detail,
        anchor,
        name,
        C((armSide + edge) / 2, point.Y, point.Z),
        V(edge - armSide, 0.132, 0.153),
        dark
    )
end
for lane = 1, 2 do
    local a, b = connectorPoints(lane)
    local feed = V(a.X, 0.565 - lane * 0.04, -0.421 - lane * 0.024)
    local waist = V(a.X, 1.765 - lane * 0.03, -1.345 - lane * 0.022)
    local knee = V(a.X, 2.150 - lane * 0.027, -2.146)
    local outlet = V(b.X, -1.388 - lane * 0.035, -0.819 - lane * 0.029)
    pipe(boom, "Boom Hydraulic Line", feed, waist, 0.079, steel)
    pipe(boom, "Boom Hydraulic Line", waist, knee, 0.079, steel)
    pipe(boom, "Boom Hydraulic Line", knee, a, 0.079, steel)
    pipe(stick, "Stick Hydraulic Line", b, outlet, 0.079, steel)
    for _, endpoints in { { boom, a, knee }, { stick, b, outlet } } do
        local anchor, pin, toward =
            endpoints[1] :: BasePart, endpoints[2] :: Vector3, endpoints[3] :: Vector3
        pipe(anchor, "Hydraulic Coupling", pin, pin + (toward - pin).Unit * 0.164, 0.129, polished)
    end
    strap(boom, feed, 0.368, "Boom Hydraulic Feed")
    strap(boom, waist, 0.371, "Boom Hydraulic Line Strap")
    strap(boom, knee, 0.345, "Knuckle Hydraulic Mount")
    strap(stick, b, 0.276, "Stick Hydraulic Mount")
    strap(stick, outlet, 0.266, "Stick Hydraulic Distributor")
    local sample = hosePoints(rest, lane)
    local bake = {}
    for _, frame in work do
        bake[frame] = hosePoints(arms[frame], lane)
    end
    local links = {}
    for i = 1, spanPieces do
        local at = frameBetween(sample[i], sample[i + 1], rest.Turret.RightVector)
        local length = (sample[i + 1] - sample[i]).Magnitude
        for _, pts in bake do
            length = math.max(length, (pts[i + 1] - pts[i]).Magnitude)
        end
        local segment = part(
            detail,
            root,
            string.format("HydraulicHose%d_%02d", lane, i),
            at,
            V(length + 0.028, 0.097, 0.097),
            rubber,
            Enum.PartType.Cylinder,
            true
        )
        links[i] = { segment = segment, at = at }
    end
    hoses[lane] = links
end

-- The existing visual-effect binder shows the payload at BucketLoaded and
-- hands visibility back to the grain burst at BucketDump.
machine.SandFxBucketLoad:Destroy()
local payloadAt = C(0, -1.296, -0.192)
local payload = part(
    machine,
    scoop,
    "SandFxBucketLoad",
    payloadAt,
    V(1.64, 0.375, 1.052),
    sand,
    Enum.PartType.Ball,
    true,
    true
)
part(
    payload,
    payload,
    "Sand Crest",
    C(-0.235, 0.107, -0.114) * rbx.CFrame.Angles(0, 0.19, -0.10),
    V(0.917, 0.304, 0.686),
    sandBright,
    Enum.PartType.Ball,
    nil,
    true
)
part(
    payload,
    payload,
    "Sand Shoulder",
    C(0.369, 0.063, 0.082) * rbx.CFrame.Angles(0, -0.17, 0.14),
    V(0.687, 0.251, 0.705),
    rgb(226, 179, 105),
    Enum.PartType.Ball,
    nil,
    true
)
part(
    payload,
    payload,
    "Sand Crumble",
    C(0.230, 0.133, 0.298) * rbx.CFrame.Angles(0.07, 0.19, -0.15),
    V(0.493, 0.151, 0.298),
    sandBright,
    Enum.PartType.Ball,
    nil,
    true
)
payload.Transparency = 1
for _, child in payload:GetChildren() do
    if child:IsA("BasePart") then
        child.Transparency = 1
    end
end
for _, attachment in scoop:GetChildren() do
    if attachment.Name == "SandFxBucketPour" then
        attachment.CFrame += V(0, -0.025, 0.173)
    end
end

local mod = machine.SandEffects :: ModuleScript
local function replaceLiteral(s: string, before: string, after: string): string
    local first, last = s:find(before, 1, true)
    assert(first and last, before)
    assert(not s:find(before, last + 1, true), before)
    return s:sub(1, first - 1) .. after .. s:sub(last + 1)
end
local moduleSource = mod.Source
moduleSource = replaceLiteral(
    moduleSource,
    '    local cargo = rig:FindFirstChild("SandFxBucketLoad")',
    [=[    local cargo = rig:FindFirstChild("SandFxBucketLoad")
    local loadParts: {BasePart} = {}
    if cargo and cargo:IsA("BasePart") then
        table.insert(loadParts, cargo)
        for _, piece in cargo:GetChildren() do
            if piece:IsA("BasePart") then table.insert(loadParts, piece) end
        end
    end

    local function showLoad(visible: boolean)
        for _, piece in loadParts do
            piece.Transparency = if visible then 0 else 1
        end
    end]=]
)
moduleSource = replaceLiteral(
    moduleSource,
    '        if cargo and cargo:IsA("BasePart") then cargo.Transparency = 1 end',
    "        showLoad(false)"
)
moduleSource = replaceLiteral(
    moduleSource,
    [=[    if cargo and cargo:IsA("BasePart") then
        local sand = cargo
        on("BucketLoaded", function() sand.Transparency = 0 end)
        on("BucketDump", function() sand.Transparency = 1 end)
    end]=],
    [=[    if #loadParts > 0 then
        on("BucketLoaded", function() showLoad(true) end)
        on("BucketDump", function() showLoad(false) end)
    end]=]
)
mod.Source = moduleSource

local function channel(container: Pose, name: string, delta: CFrame)
    local p = rbx.Instance.new("Pose")
    p.Name, p.CFrame = name, C(delta.Position / scale) * delta.Rotation
    p.Weight, p.EasingStyle, p.Parent = 1, Enum.PoseEasingStyle.Linear, container
end

local function smooth(x: number): number
    local u = math.clamp(x, 0, 1)
    return u * u * (3 - 2 * u)
end

local function loadMotion(time: number): CFrame
    local tip = smooth((time - (dumpTime - 0.285)) / 0.285) * (1 - smooth((time - dumpTime) / 0.32))
    local settle = 0.023
        * math.sin(math.max(0, time - loadTime) * 22)
        * (1 - smooth((time - loadTime) / 0.42))
    return C(0, settle + 0.047 * tip, 0.424 * tip) * rbx.CFrame.Angles(-0.085 * tip, 0, 0.03 * tip)
end

local variants = { work, framesIn(machine.DriverAnimations.WorkWithJoysticks) }
for _, keyframes in variants do
    for _, frame in keyframes do
        local arm = armAt(frame)
        local drive, extension = cylinderFrames(arm)
        channel(frame.Root, barrel.Name, barrelAt:ToObjectSpace(drive))
        channel(frame.Root, rod.Name, rodAt:ToObjectSpace(extension))
        for lane, hose in hoses do
            local pts = hosePoints(arm, lane)
            for i, link in hose do
                local frameAt = frameBetween(pts[i], pts[i + 1], arm.Turret.RightVector)
                channel(frame.Root, link.segment.Name, link.at:ToObjectSpace(frameAt))
            end
        end
        channel(frame.Root.Turret.Boom.Stick.Scoop, payload.Name, loadMotion(frame.Time))
    end
end

machine:SetAttribute("BucketAndHydraulicsRevision", 1)
local path = "assets/models/excavator_refinement/DuneBaron_ExcavatorRefinement.rbxm"
local bytes = rbx.serializeModel({ machine })
local restored = rbx.deserializeModel(bytes)[1]
assert(
    restored.Name == "mini_digger"
        and restored.PrimaryPart == restored.Root
        and restored.Scale == scale
)
assert(restored.Turret.DriverRoot.CFrame == source.Turret.DriverRoot.CFrame)
assert(restored.Scoop.WorkOrigin.CFrame == source.Scoop.WorkOrigin.CFrame)
assert(restored.SandEffects.Source == moduleSource)
for _, motion in { restored.Animations.WorkLoop, restored.DriverAnimations.WorkWithJoysticks } do
    local keys = framesIn(motion)
    assert(motion.Loop and #keys == #work)
    local found = 0
    for _, frame in keys do
        for _, name in { "BucketCut", "BucketLoaded", "BucketDump" } do
            if frame:FindFirstChild(name) then
                found += 1
            end
        end
        assert(frame.Root.BucketTiltRod and frame.Root.BucketTiltBarrel)
        assert(frame.Root.Turret.Boom.Stick.Scoop.SandFxBucketLoad)
    end
    assert(found == 3)
    for _, p in keys[1].Root:GetDescendants() do
        if
            p.Name:match("^HydraulicHose")
            or p.Name:match("^BucketTilt")
            or p.Name == payload.Name
        then
            local delta =
                p.CFrame:ToObjectSpace(keys[#keys].Root:FindFirstChild(p.Name, true).CFrame)
            assert(delta.Position.Magnitude < 0.00015 and delta.LookVector.Z < -0.99999, p.Name)
        end
    end
end
fs.writeFile(path, bytes)
print(path, "2 updated work clips, pin-mounted cylinder and 12 moving hose segments")
