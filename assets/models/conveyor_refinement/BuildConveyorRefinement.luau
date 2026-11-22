--!strict
-- Offline authoring for the larger bucket conveyor and its continuous work cycle.
local rbx = require("@lune/roblox")
local fs = require("@lune/fs")
local C, V = rbx.CFrame.new, rbx.Vector3.new
local I = rbx.CFrame.identity
local Enum = rbx.Enum
local rgb = rbx.Color3.fromRGB

local source = rbx.deserializeModel(
    fs.readFile("assets/models/equipment_sand_fx/DuneBaron_Equipment_SandFX.rbxm")
)[1].bucket_chain
local conveyor = source:Clone()
local root = conveyor.Root :: BasePart
local origin = root.CFrame
local work = conveyor.Animations.WorkLoop :: KeyframeSequence
local detail = rbx.Instance.new("Folder")
detail.Name, detail.Parent = "ConveyorDetails", conveyor

local graphite = rgb(33, 54, 60)
local steel = rgb(75, 108, 118)
local teal = rgb(35, 101, 109)
local gold = rgb(214, 159, 57)
local sand = rgb(219, 171, 101)
local lightSand = rgb(232, 188, 118)

local welded: { [BasePart]: WeldConstraint } = {}
local motors: { [BasePart]: Motor6D } = {}
for _, item in conveyor:GetDescendants() do
    if item:IsA("WeldConstraint") then
        welded[item.Part1] = item
    end
    if item:IsA("Motor6D") then
        motors[item.Part1] = item
    end
end

local function weld(from: BasePart, part: BasePart, animated: boolean?)
    local link = rbx.Instance.new(if animated then "Motor6D" else "Weld")
    link.Name = part.Name
    link.Part0, link.Part1 = from, part
    link.C0, link.C1 = from.CFrame:ToObjectSpace(part.CFrame), I
    link.Parent = part
end

local function add(
    name: string,
    anchor: BasePart,
    at: CFrame,
    size: Vector3,
    color: Color3,
    shape: Enum.PartType?,
    animated: boolean?,
    sandy: boolean?
): Part
    local part = rbx.Instance.new("Part")
    part.Name, part.Size, part.Color = name, size, color
    part.CFrame, part.Shape = origin * at, shape or Enum.PartType.Block
    part.Material = if sandy then Enum.Material.Sand else Enum.Material.SmoothPlastic
    part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
    part.Massless = true
    part.Parent = detail
    weld(anchor, part, animated)
    return part
end

local function relocate(part: BasePart, frame: CFrame)
    local link = assert(welded[part], part.Name)
    local anchor = assert(link.Part0)
    welded[part] = nil
    link:Destroy()
    part.CFrame = origin * frame
    weld(anchor, part)
end

local function strut(name: string, start: Vector3, stop: Vector3, width: number, color: Color3)
    local axis = (stop - start).Unit
    local up = axis:Cross(rbx.Vector3.xAxis).Unit
    local frame = rbx.CFrame.fromMatrix((start + stop) * 0.5, axis, up)
    add(name, root, frame, V((stop - start).Magnitude, width, width), color)
end

local function sortedKeys(clip: KeyframeSequence): { Keyframe }
    local keys = clip:GetChildren() :: { Keyframe }
    table.sort(keys, function(a, b)
        return a.Time < b.Time
    end)
    return keys
end

local existing = sortedKeys(work)
local duration = existing[#existing].Time
local marks = {}
for _, key in existing do
    if key:FindFirstChild("Discharge") then
        table.insert(marks, key.Time)
    end
end
assert(#marks == 9)

local lift = V(0, 0.19, 0)
local sprockets = { conveyor.Sprocket1, conveyor.Sprocket2 }
for _, roller in sprockets do
    local frame = origin:ToObjectSpace(roller.CFrame) + lift
    roller.CFrame = origin * frame
    motors[roller].C0 = frame
end
for part, link in welded do
    if
        table.find(sprockets, link.Part0)
        or part.Name == "Conveyor Rail"
        or part.Name == "Upper Chain"
        or part.Name == "Return Chain"
    then
        relocate(part, origin:ToObjectSpace(part.CFrame) + lift)
    elseif part.Name == "Hazard Panel" or part.Name == "Safety Stripe" then
        welded[part] = nil
        part:Destroy()
    end
end

local lower = origin:ToObjectSpace(sprockets[1].CFrame).Position
local upper = origin:ToObjectSpace(sprockets[2].CFrame).Position
local ascending = (upper - lower).Unit
local outer = V(0, ascending.Z, -ascending.Y)
local run = (upper - lower).Magnitude
local radius = 0.467
local arc = math.pi * radius
local returnArc = 2 * run + arc
local loopLength = 2 * (run + arc)
local pitch = loopLength / #marks
local dischargeDistance = run + radius * 2.12

local function orbit(distance: number): CFrame
    local d = distance % loopLength
    local at, up
    if d < run then
        at, up = lower + ascending * d, outer
    elseif d < run + arc then
        local theta = (d - run) / radius
        at, up = upper, outer * math.cos(theta) + ascending * math.sin(theta)
    elseif d < returnArc then
        at, up = upper - ascending * (d - run - arc), -outer
    else
        local theta = (d - returnArc) / radius
        at, up = lower, -outer * math.cos(theta) - ascending * math.sin(theta)
    end
    return rbx.CFrame.fromMatrix(at + up * radius, rbx.Vector3.xAxis, up)
end

-- Each successive discharge advances by one bucket pitch. Periodic Hermite
-- interpolation keeps velocity continuous through the authored sound cues.
local function cueTime(index: number): number
    return marks[index % #marks + 1] + math.floor(index / #marks) * duration
end

local function phase(time: number): number
    local index = -1
    while time >= cueTime(index + 1) do
        index += 1
    end
    local before, start, stop, after =
        cueTime(index - 1), cueTime(index), cueTime(index + 1), cueTime(index + 2)
    local dt = stop - start
    local u = (time - start) / dt
    local m0, m1 = 2 * dt / (stop - before), 2 * dt / (after - start)
    return index + u ^ 2 * (3 - 2 * u) + m0 * u * (1 - u) ^ 2 - m1 * u ^ 2 * (1 - u)
end

local function smooth(x: number): number
    local u = math.clamp(x, 0, 1)
    return u * u * (3 - 2 * u)
end

local function loadAmount(distance: number): number
    -- Measured from the feed tray to the open discharge lip.
    local pickup = returnArc + 0.80 * radius
    local d = (distance - pickup) % loopLength
    local dump = (dischargeDistance - pickup) % loopLength
    return smooth(d / 0.67) * (1 - smooth((d - dump + 0.13) / 0.32))
end

local function bucketDistance(index: number, progress: number): number
    return dischargeDistance + (progress + index - 5) * pitch
end

-- Ground-level feed pan and outboard skid extensions.
add("Feed Apron", root, C(0, 0.142, -4.72), V(2.42, 0.049, 2.14), teal)
add("Feed Wear Edge", root, C(0, 0.158, -5.812), V(2.41, 0.059, 0.16), steel)
add(
    "Intake Sand Bed",
    root,
    C(0, 0.183, -5.15),
    V(2.30, 0.060, 1.39),
    sand,
    Enum.PartType.Ball,
    nil,
    true
)
add(
    "Intake Sand Tail",
    root,
    C(-0.21, 0.198, -5.50),
    V(1.44, 0.145, 0.51),
    lightSand,
    Enum.PartType.Ball,
    nil,
    true
)
for _, side in { -1, 1 } do
    add(
        "Feed Guide",
        root,
        C(side * 1.33, 0.322, -4.73) * rbx.CFrame.Angles(0, side * 0.06, 0),
        V(0.23, 0.334, 2.18),
        teal
    )
    add(
        "Feed Guide Edge",
        root,
        C(side * 1.33, 0.505, -4.73) * rbx.CFrame.Angles(0, side * 0.06, 0),
        V(0.26, 0.078, 2.20),
        gold
    )
    add("Feed Mount", root, C(side * 1.28, 0.394, -3.55), V(0.32, 0.51, 0.28), graphite)
    add("Feed Bearing Support", root, C(side * 1.64, 0.714, lower.Z), V(0.145, 1.13, 0.33), steel)
    add("Feed Bearing Foot", root, C(side * 1.56, 0.182, lower.Z), V(0.37, 0.13, 0.63), graphite)
    add(
        "Feed Bearing Sleeve",
        root,
        C(side * 1.535, lower.Y, lower.Z),
        V(0.11, 0.26, 0.26),
        graphite,
        Enum.PartType.Cylinder
    )
    add("Outrigger Skid", root, C(side * 2.54, 0.288, 0.26), V(0.61, 0.345, 6.46), graphite)
    add("Skid Wear Strip", root, C(side * 2.68, 0.449, 0.28), V(0.26, 0.11, 6.13), steel)
    strut("Lateral Brace", V(side * 2.38, 0.48, -2.49), V(side * 2.38, 2.94, 0.42), 0.204, teal)
    for _, z in { -2.67, 3.20 } do
        add("Skid End Plate", root, C(side * 2.53, 0.306, z), V(0.66, 0.293, 0.23), graphite)
    end
    for i = 1, 4 do
        add(
            "Hopper Rib",
            root,
            C(side * (2.12 + (i % 2) * 0.025), 1.48, 1.32 + 0.70 * (i - 1))
                * rbx.CFrame.Angles(0, 0, -side * 0.145),
            V(0.13, 1.51, 0.141),
            teal
        )
    end
end
add("Feed Crossmember", root, C(0, 0.264, -3.11), V(5.35, 0.29, 0.41), graphite)

-- Tuck the drive ahead of the hopper wall so its casing stays out of the bin.
local drive = conveyor["Drive Housing"] :: BasePart
local driveAt = origin:ToObjectSpace(drive.CFrame) + V(0, 0, -0.94)
relocate(drive, driveAt)
local driveFace = driveAt.X - drive.Size.X / 2
add(
    "Drive Vent Plate",
    root,
    C(driveFace - 0.017, driveAt.Y, driveAt.Z),
    V(0.044, 0.735, 1.03),
    steel
)
for i = 1, 4 do
    add(
        "Drive Cooling Louvre",
        root,
        C(driveFace - 0.044, driveAt.Y + (i - 2.5) * 0.145, driveAt.Z),
        V(0.027, 0.077, 0.821),
        graphite
    )
end

local cargo, restOrbit, restFill = {}, {}, {}
for index = 1, #marks do
    local bucket = conveyor[string.format("Bucket%02d", index)] :: BasePart
    local distance = bucketDistance(index, phase(0))
    restOrbit[index], restFill[index] = orbit(distance), loadAmount(distance)
    local before = bucket.CFrame
    bucket.CFrame = origin * restOrbit[index]
    motors[bucket].C0 = restOrbit[index]
    for part, link in welded do
        if link.Part0 == bucket then
            relocate(part, restOrbit[index] * before:ToObjectSpace(part.CFrame))
        end
    end
    local floor = 0.123 + restFill[index] * 0.133
    local at = restOrbit[index] * C(0.025, floor, -0.030)
    local load = add(
        string.format("SandCargo%02d", index),
        bucket,
        at,
        V(1.66, 0.153, 0.408),
        sand,
        Enum.PartType.Ball,
        true,
        true
    )
    add(
        "Cargo Ridge",
        load,
        at * C(-0.385, 0.014, -0.019),
        V(0.75, 0.136, 0.330),
        lightSand,
        Enum.PartType.Ball,
        nil,
        true
    )
    cargo[index] = load
end

local bed = conveyor["Sand in Hopper"] :: BasePart
local bedAt = origin:ToObjectSpace(bed.CFrame)
local mound = add(
    "HopperLanding",
    root,
    C(0.10, 1.596, 2.48),
    V(2.15, 0.41, 1.38),
    lightSand,
    Enum.PartType.Ball,
    true,
    true
)
add(
    "Hopper Sand Shoulder",
    root,
    C(-0.84, 1.560, 2.86),
    V(1.43, 0.32, 0.97),
    sand,
    Enum.PartType.Ball,
    nil,
    true
)
add(
    "Hopper Sand Shoulder",
    root,
    C(0.96, 1.587, 2.32),
    V(1.27, 0.33, 0.94),
    sand,
    Enum.PartType.Ball,
    nil,
    true
)
bed.Color = sand
bed.Material = Enum.Material.Sand

-- Put the stream origin at the lip of the bucket that tips on each cue.
local dropPoint = orbit(dischargeDistance):PointToWorldSpace(V(0, 0.27, 0.325))
local discharge = root.Discharge :: Attachment
local shift = dropPoint - discharge.CFrame.Position
discharge.CFrame += shift
local landingDelay = 0.39
for _, attachment in root:GetChildren() do
    if attachment.Name == "SandFxConveyorStream" then
        attachment.CFrame += shift
        for _, particle in attachment:GetChildren() do
            if particle:IsA("ParticleEmitter") then
                particle.Lifetime = rbx.NumberRange.new(0.40, 0.49)
                particle.Size = rbx.NumberSequence.new({
                    rbx.NumberSequenceKeypoint.new(0, 0.084),
                    rbx.NumberSequenceKeypoint.new(1, 0.063),
                })
            end
        end
    elseif attachment.Name == "SandFxConveyorLanding" then
        local target = V(attachment.CFrame.X, 1.803, 2.48)
        attachment.CFrame += target - attachment.CFrame.Position
        for _, particle in attachment:GetChildren() do
            if particle:IsA("ParticleEmitter") then
                particle:SetAttribute("DelaySeconds", landingDelay)
            end
        end
    end
end
assert(dropPoint.Y > 4.8 and dropPoint.Z < bedAt.Z)

local function key(time: number): Keyframe
    local frame = rbx.Instance.new("Keyframe")
    frame.Name, frame.Time, frame.Parent = "Keyframe", time, work
    local pose = rbx.Instance.new("Pose")
    pose.Name, pose.Weight, pose.Parent = root.Name, 0, frame
    return frame
end

local function channel(parent: Pose, name: string, transform: CFrame): Pose
    local pose = parent:FindFirstChild(name) :: Pose?
    if not pose then
        pose = rbx.Instance.new("Pose")
        pose.Name, pose.Parent = name, parent
    end
    pose.CFrame = C(transform.Position / conveyor.Scale) * transform.Rotation
    pose.Weight, pose.EasingStyle = 1, Enum.PoseEasingStyle.Linear
    return pose
end

local function writeFrame(frame: Keyframe, time: number)
    local at = if time == duration then 0 else time
    local progress = phase(at)
    local rootPose = frame.Root :: Pose
    for i, load in cargo do
        local distance = bucketDistance(i, progress)
        local bucketPose = channel(
            rootPose,
            string.format("Bucket%02d", i),
            restOrbit[i]:ToObjectSpace(orbit(distance))
        )
        channel(bucketPose, load.Name, C(0, 0.133 * (loadAmount(distance) - restFill[i]), 0))
    end
    local rotation = rbx.CFrame.Angles((progress - phase(0)) * 12 * math.pi / #marks, 0, 0)
    for _, sprocket in sprockets do
        channel(rootPose, sprocket.Name, rotation)
    end
    local bounce = 0
    for _, stamp in marks do
        local age = (at - stamp - landingDelay) % duration
        if age < 0.24 then
            local f = age / 0.24
            bounce += 0.065 * math.sin(math.pi * f) ^ 2
        end
    end
    channel(rootPose, mound.Name, C(0, bounce, 0))
end

for i, frame in existing do
    if i > 1 then
        local previous = existing[i - 1].Time
        for slice = 1, 2 do
            local time = previous + (frame.Time - previous) * slice / 3
            writeFrame(key(time), time)
        end
    end
    writeFrame(frame, frame.Time)
end

local minY, maxY = math.huge, -math.huge
for _, part in conveyor:GetDescendants() do
    if not part:IsA("BasePart") or part.Transparency >= 1 then
        continue
    end
    local localFrame = origin:ToObjectSpace(part.CFrame)
    local height = (
        math.abs(localFrame.RightVector.Y) * part.Size.X
        + math.abs(localFrame.UpVector.Y) * part.Size.Y
        + math.abs(localFrame.LookVector.Y) * part.Size.Z
    ) / 2
    minY, maxY = math.min(minY, localFrame.Y - height), math.max(maxY, localFrame.Y + height)
end
conveyor:SetAttribute("RestHeightStuds", math.round((maxY - minY) * 100) / 100)
conveyor:SetAttribute("ConveyorWorkRevision", 1)
local bytes = rbx.serializeModel({ conveyor })
local restored = rbx.deserializeModel(bytes)[1]
assert(restored.Name == "bucket_chain" and restored.PrimaryPart == restored.Root)
assert(restored.Root.WorkOrigin.CFrame == source.Root.WorkOrigin.CFrame)
assert(restored.SandEffects.Source == source.SandEffects.Source)
local frames = sortedKeys(restored.Animations.WorkLoop)
assert(restored.Animations.WorkLoop.Loop and #frames == (#existing - 1) * 3 + 1)
assert(frames[1].Time == 0 and frames[#frames].Time == duration)
local dischargeCount = 0
for _, frame in frames do
    if frame:FindFirstChild("Discharge") then
        dischargeCount += 1
        assert(frame.Time == marks[dischargeCount])
    end
end
assert(dischargeCount == #marks)
for _, pose in frames[1].Root:GetDescendants() do
    assert(pose.CFrame == frames[#frames].Root:FindFirstChild(pose.Name, true).CFrame, pose.Name)
end
local path = "assets/models/conveyor_refinement/DuneBaron_ConveyorRefinement.rbxm"
fs.writeFile(path, bytes)
print(path, "9 buckets, 145 keys, 9 matched discharge cues")
