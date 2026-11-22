--!strict
-- Bake display poses from the current rigs and build a replacement ArtV2.MachineYard.
local rbx = require("@lune/roblox")
local fs = require("@lune/fs")
local C, V = rbx.CFrame.new, rbx.Vector3.new
local I = rbx.CFrame.identity
local Enum = rbx.Enum
local rgb = rbx.Color3.fromRGB

local ground, slab = 6.00, 6.14
local yard = rbx.Instance.new("Folder")
yard.Name = "MachineYard"
yard:SetAttribute("ArtRevision", 4)
yard:SetAttribute("SurfaceY", ground)

local function folder(parent: Instance, name: string): Folder
    local f = rbx.Instance.new("Folder")
    f.Name, f.Parent = name, parent
    return f
end

local machines = folder(yard, "Displays")
local paving = folder(yard, "Paving")
local shop = folder(yard, "ServiceShelter")
local dressing = folder(yard, "YardDressing")
local solids = folder(yard, "Collision")
local unitY, unitZ = rbx.Vector3.yAxis, rbx.Vector3.zAxis
local slate = rgb(74, 105, 111)
local steel = rgb(61, 77, 80)
local dark = rgb(42, 53, 55)
local brass = rgb(193, 139, 62)
local teal = rgb(49, 112, 115)
local tealLight = rgb(65, 128, 128)
local rust = rgb(151, 87, 60)
local mutedRed = rgb(155, 74, 49)
local wood = rgb(137, 98, 65)
local canvas = rgb(221, 193, 142)
local stone = rgb(172, 143, 111)
local mediumStone = rgb(187, 157, 125)
local lightStone = rgb(211, 176, 134)

local function part(
    parent: Instance,
    name: string,
    cf: CFrame,
    size: Vector3,
    color: Color3,
    shape: Enum.PartType?,
    material: Enum.Material?
): Part
    local p = rbx.Instance.new("Part")
    p.Name, p.CFrame, p.Size, p.Color = name, cf, size, color
    p.Shape, p.Material = shape or Enum.PartType.Block, material or Enum.Material.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
    p.Parent = parent
    return p
end

local function boxCollider(name: string, cf: CFrame, size: Vector3)
    local collider = part(solids, name, cf, size, dark)
    collider.Transparency, collider.CanCollide, collider.CanQuery = 1, true, true
    collider.CastShadow = false
end

local function beam(
    parent: Instance,
    name: string,
    a: Vector3,
    b: Vector3,
    width: number,
    color: Color3,
    shape: Enum.PartType?
): Part
    local x = (b - a).Unit
    local hint = if math.abs(x.Y) > 0.94 then unitZ else unitY
    local y = (hint - x * hint:Dot(x)).Unit
    return part(
        parent,
        name,
        rbx.CFrame.fromMatrix((a + b) / 2, x, y),
        V((b - a).Magnitude + 0.02, width, width),
        color,
        shape
    )
end

local function extent(cf: CFrame, piece: BasePart): Vector3
    local size = piece.Size
    if
        piece:IsA("Part")
        and (piece.Shape == Enum.PartType.Cylinder or piece.Shape == Enum.PartType.Ball)
    then
        local axis, up, forward =
            cf.RightVector * size.X, cf.UpVector * size.Y, cf.LookVector * size.Z
        local function radial(a: number, b: number, c: number): number
            return if piece.Shape == Enum.PartType.Cylinder
                then (math.abs(a) + math.sqrt(b * b + c * c)) / 2
                else math.sqrt(a * a + b * b + c * c) / 2
        end
        return V(
            radial(axis.X, up.X, forward.X),
            radial(axis.Y, up.Y, forward.Y),
            radial(axis.Z, up.Z, forward.Z)
        )
    end
    local function abs(v: Vector3): Vector3
        return V(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
    end
    return (abs(cf.RightVector) * size.X + abs(cf.UpVector) * size.Y + abs(cf.LookVector) * size.Z)
        / 2
end

local function changesAt(motion: KeyframeSequence, at: number): { [string]: CFrame }
    local frames = motion:GetChildren()
    table.sort(frames, function(a, b)
        return a.Time < b.Time
    end)
    local first, last = frames[1], frames[1]
    for i = 2, #frames do
        first, last = frames[i - 1], frames[i]
        if at <= last.Time then
            break
        end
    end
    local fraction = math.clamp((at - first.Time) / (last.Time - first.Time), 0, 1)
    local values = {}
    for _, node in first.Root:GetDescendants() do
        assert(node:IsA("Pose") and values[node.Name] == nil)
        values[node.Name] =
            node.CFrame:Lerp(last.Root:FindFirstChild(node.Name, true).CFrame, fraction)
    end
    return values
end

type Bay = {
    name: string,
    folder: string,
    file: string,
    x: number,
    z: number,
    yaw: number,
    pose: number,
    pad: Vector3,
    padZ: number,
    stopX: number,
    stopsZ: number,
}
local bays: { Bay } = {
    {
        name = "bucket_chain",
        folder = "conveyor_refinement",
        file = "DuneBaron_ConveyorRefinement",
        x = 22.5,
        z = -27.85,
        yaw = 12,
        pose = 0.16,
        pad = V(8.55, 0.25, 12.21),
        padZ = -0.93,
        stopX = 3.62,
        stopsZ = -6.17,
    },
    {
        name = "mini_digger",
        folder = "excavator_refinement",
        file = "DuneBaron_ExcavatorRefinement",
        x = 37.6,
        z = -27.05,
        yaw = 10,
        pose = 1.44,
        pad = V(9.30, 0.25, 12.25),
        padZ = -1.52,
        stopX = 3.52,
        stopsZ = -6.49,
    },
    {
        name = "vacuum_robot",
        folder = "vacuum_refinement",
        file = "DuneBaron_VacuumRefinement",
        x = 51.05,
        z = -24.25,
        yaw = 15,
        pose = 0,
        pad = V(5.41, 0.25, 5.34),
        padZ = -0.21,
        stopX = 2.13,
        stopsZ = -2.56,
    },
    {
        name = "mega_machine",
        folder = "harvester_refinement",
        file = "DuneBaron_HarvesterRefinement",
        x = 68.23,
        z = -28.45,
        yaw = -5,
        pose = 0.76,
        pad = V(19.25, 0.25, 22.05),
        padZ = -1.48,
        stopX = 8.46,
        stopsZ = -11.13,
    },
}

local function boxForMachine(name: string, place: CFrame)
    if name == "bucket_chain" then
        boxCollider(name .. " Frame", place * C(0, 0.42, 0.27), V(4.89, 0.64, 6.22))
        boxCollider(name .. " Hopper", place * C(0, 1.24, 2.4), V(4.12, 2.26, 2.8))
    elseif name == "mini_digger" then
        boxCollider(name .. " Chassis", place * C(0, 0.91, 0.08), V(5.84, 1.64, 5.57))
        boxCollider(name .. " Body", place * C(0, 2.82, 0.37), V(4.37, 2.13, 3.89))
    elseif name == "vacuum_robot" then
        boxCollider(name .. " Chassis", place * C(0, 0.48, 0.064), V(2.67, 0.86, 2.42))
    else
        boxCollider(name .. " Chassis", place * C(0, 2.06, 1.21), V(15.47, 4.12, 13.28))
        boxCollider(name .. " Drums", place * C(0, 2.76, -8.18), V(12.58, 4.31, 4.50))
    end
end

local function park(bay: Bay)
    local path = string.format("assets/models/%s/%s.rbxm", bay.folder, bay.file)
    local model = rbx.deserializeModel(fs.readFile(path))[1] :: Model
    assert(model.Name == bay.name and model.PrimaryPart == model.Root)
    local root = model.Root :: BasePart
    local snapshots = changesAt(model.Animations.WorkLoop, bay.pose)
    local joints, geometry = {}, {}
    local all = model:GetDescendants()
    for _, p in all do
        if p:IsA("BasePart") then
            table.insert(geometry, p)
        end
        if p:IsA("JointInstance") or p:IsA("WeldConstraint") then
            assert(p.Part1 and not joints[p.Part1])
            joints[p.Part1] = p
        end
    end
    local transforms = { [root] = I }
    local function localPose(p: BasePart): CFrame
        if transforms[p] then
            return transforms[p]
        end
        local j = assert(joints[p], p.Name)
        local host = localPose(assert(j.Part0))
        local at
        if j:IsA("WeldConstraint") then
            at = host * j.Part0.CFrame:ToObjectSpace(p.CFrame)
        else
            local pose = if j:IsA("Motor6D") then snapshots[p.Name] or I else I
            at = host * j.C0 * C(pose.Position * model.Scale) * pose.Rotation * j.C1:Inverse()
        end
        transforms[p] = at
        return at
    end
    local minY = math.huge
    for _, p in geometry do
        local at = localPose(p)
        local feet = if bay.name == "bucket_chain"
            then p.Name == "Skid" or p.Name == "Outrigger Skid"
            elseif bay.name == "vacuum_robot" then p.Name == "Tire Cleat"
            else p.Name:match("^Tread%d")
        if feet then
            minY = math.min(minY, at.Y - extent(at, p).Y)
        end
    end
    assert(minY < 0.4)
    local transform = C(bay.x, slab - minY + 0.013, bay.z)
        * rbx.CFrame.Angles(0, math.rad(180 + bay.yaw), 0)
    local remove = {}
    for _, obj in all do
        if
            obj:IsA("JointInstance")
            or obj:IsA("WeldConstraint")
            or obj:IsA("ParticleEmitter")
            or obj:IsA("ModuleScript")
            or obj:IsA("AnimationController")
            or obj:IsA("KeyframeSequence")
        then
            table.insert(remove, obj)
        end
    end
    for _, obj in remove do
        obj:Destroy()
    end
    local low, high = math.huge, -math.huge
    for _, p in geometry do
        p.CFrame = transform * transforms[p]
        p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
        if p.Name == "SandFxBucketLoad" or p.Parent.Name == "SandFxBucketLoad" then
            p.Transparency = 0
        end
        if p.Transparency < 0.99 then
            local ext = extent(p.CFrame, p)
            low, high = math.min(low, p.CFrame.Y - ext.Y), math.max(high, p.CFrame.Y + ext.Y)
        end
    end
    model.Name, model.Parent = "Display_" .. bay.name, machines
    model:SetAttribute("DisplayOnly", true)
    model:SetAttribute("WorkPoseTime", bay.pose)
    model:SetAttribute("VisibleHeightStuds", math.round((high - low) * 100) / 100)
    assert(
        low >= slab - 0.10,
        string.format("%s low %.3f, slab %.3f, running datum %.3f", model.Name, low, slab, minY)
    )
    boxForMachine(bay.name, transform)

    local level = (transform - transform.Position) + V(bay.x, slab - bay.pad.Y / 2, bay.z)
    local frame = level * C(0, 0, bay.padZ)
    local pad = part(paving, "Service Footing", frame, bay.pad, stone, nil, Enum.Material.Sandstone)
    pad:SetAttribute("Display", bay.name)
    pad.CastShadow = false
    local edge = slab + 0.037
    for _, sign in { -1, 1 } do
        local rail = level * C(sign * bay.stopX, edge - level.Y, bay.stopsZ)
        part(
            paving,
            "Bay Marker Stone",
            rail,
            V(0.83, 0.171, 0.57),
            lightStone,
            nil,
            Enum.Material.Sandstone
        )
        part(paving, "Bay Marker Inset", rail * C(0, 0.094, 0), V(0.565, 0.035, 0.335), teal)
        local padRail = frame * C(sign * (bay.pad.X / 2 - 0.18), bay.pad.Y / 2 + 0.009, -0.41)
        part(paving, "Footing Edge Inlay", padRail, V(0.089, 0.028, bay.pad.Z - 2.08), mediumStone)
    end
end

for _, settings in bays do
    park(settings)
end

-- A line of staggered sandstone slabs leads from the lane to the display bays.
for i = 0, 22 do
    local x = 14.95 + i * 2.91
    local z = -11.09 - 0.26 * math.cos(i * 0.49)
    local yaw = 0.049 * math.sin(i * 1.30)
    part(
        paving,
        "Aisle Paver",
        C(x, 6.049, z) * rbx.CFrame.Angles(0, yaw, 0),
        V(2.74, 0.124, 1.38 + 0.24 * math.sin(i * 2.1)),
        if i % 4 == 2 then stone else mediumStone,
        nil,
        Enum.Material.Sandstone
    ).CastShadow =
        false
    if i % 3 == 0 then
        part(
            paving,
            "Aisle Shoulder",
            C(x + 0.47, 6.045, z - 1.24) * rbx.CFrame.Angles(0, -yaw, 0),
            V(1.71, 0.115, 0.67),
            lightStone,
            nil,
            Enum.Material.Sandstone
        ).CastShadow =
            false
    end
end

local sx, sz = 46.40, -39.43
local function S(x: number, y: number, z: number): CFrame
    return C(sx + x, y, sz + z)
end

part(
    shop,
    "Shelter Footing",
    S(0, 6.045, 0.05),
    V(13.45, 0.22, 7.16),
    mediumStone,
    nil,
    Enum.Material.Sandstone
)
local roof = S(0, 12.19, -0.04) * rbx.CFrame.Angles(math.rad(-6.5), 0, 0)
for i = -3, 3 do
    local roofColor = if i % 3 == 1
        then rgb(67, 117, 118)
        else if i % 2 == 0 then teal else tealLight
    part(shop, "Weathered Roof Panel", roof * C(i * 1.985, 0, 0), V(1.98, 0.192, 8.53), roofColor)
    for _, seam in { -0.92, 0.91 } do
        part(
            shop,
            "Raised Panel Seam",
            roof * C(i * 1.985 + seam, 0.133, 0),
            V(0.104, 0.109, 8.55),
            slate
        )
    end
end
for _, z in { -4.20, 4.20 } do
    part(shop, "Roof Drip Edge", roof * C(0, -0.006, z), V(14.20, 0.236, 0.152), dark)
end

for _, x in { -6.08, 0, 6.08 } do
    for _, z in { -3.13, 3.13 } do
        local yTop = 12.19 + z * 0.115
        part(
            shop,
            "Post Block",
            S(x, 6.27, z),
            V(0.72, 0.40, 0.71),
            stone,
            nil,
            Enum.Material.Sandstone
        )
        part(
            shop,
            "Steel Shelter Post",
            S(x, (6.29 + yTop) / 2, z),
            V(0.255, yTop - 6.29, 0.254),
            dark
        )
        part(shop, "Post Shoe", S(x, 6.60, z), V(0.382, 0.38, 0.386), slate)
        boxCollider("Shelter Post", S(x, (6.12 + yTop) / 2, z), V(0.59, yTop - 6.12, 0.59))
        for _, direction in { -1, 1 } do
            if math.abs(x + direction) > 6.3 then
                continue
            end
            beam(
                shop,
                "Post Knee Brace",
                S(x, yTop - 0.87, z).Position,
                S(x + direction * 0.84, yTop - 0.24, z).Position,
                0.163,
                slate
            )
        end
    end
    beam(shop, "Slope Rafter", S(x, 11.77, -3.64).Position, S(x, 12.53, 3.64).Position, 0.225, dark)
end
for _, z in { -3.12, 3.12 } do
    part(shop, "Shelter Header", S(0, 12.18 + 0.115 * z - 0.19, z), V(13.11, 0.33, 0.237), dark)
end

for i = -4, 4 do
    local x = i * 1.35
    local y = 7.54 + 0.045 * math.sin(i * 2.4)
    local c = if i % 2 == 0 then rgb(126, 117, 99) else rgb(114, 110, 97)
    part(
        shop,
        "Rear Windbreak Slat",
        S(x, y, -3.18),
        V(1.318, 2.69, 0.179),
        c,
        nil,
        Enum.Material.WoodPlanks
    )
end
for _, y in { 6.72, 8.47 } do
    part(shop, "Rear Windbreak Batten", S(0, y, -3.08), V(12.35, 0.162, 0.146), dark)
end
boxCollider("Rear Windbreak", S(0, 7.48, -3.18), V(12.10, 2.62, 0.28))
for _, x in { -3.31, 3.31 } do
    local stem = part(shop, "Shop Lamp Frame", S(x, 11.91, 0.58), V(1.02, 0.156, 0.37), dark)
    part(
        shop,
        "Shop Lamp Glass",
        S(x, 11.798, 0.58),
        V(0.79, 0.10, 0.23),
        rgb(240, 218, 163),
        nil,
        Enum.Material.Neon
    )
    local bulb = rbx.Instance.new("PointLight")
    bulb.Name, bulb.Brightness, bulb.Range, bulb.Shadows = "Warm Workshop Light", 0.28, 12, false
    bulb.Color, bulb.Parent = rgb(255, 215, 159), stem
end

-- Bench, vise, parts drawers and wall-mounted service tools.
local benchX, benchZ = -2.72, -2.03
part(
    shop,
    "Bench Top",
    S(benchX, 8.57, benchZ),
    V(5.44, 0.227, 1.66),
    wood,
    nil,
    Enum.Material.WoodPlanks
)
part(shop, "Bench Lower Shelf", S(benchX, 6.76, benchZ), V(5.19, 0.112, 1.45), slate)
for _, x in { -2.42, 2.42 } do
    for _, z in { -0.65, 0.65 } do
        part(shop, "Bench Leg", S(benchX + x, 7.41, benchZ + z), V(0.182, 2.11, 0.183), dark)
    end
end
boxCollider("Workbench", S(benchX, 7.44, benchZ), V(5.41, 2.42, 1.62))
part(shop, "Vise Base", S(-4.55, 8.72, -1.50), V(0.79, 0.154, 0.46), steel)
part(shop, "Vise Body", S(-4.55, 8.92, -1.54), V(0.546, 0.316, 0.40), teal)
for _, x in { -4.79, -4.31 } do
    part(shop, "Vise Jaw", S(x, 9.11, -1.54), V(0.166, 0.211, 0.408), steel)
end
beam(
    shop,
    "Vise Screw Handle",
    S(-4.81, 8.94, -1.30).Position,
    S(-4.26, 8.94, -1.30).Position,
    0.062,
    brass,
    Enum.PartType.Cylinder
)

part(shop, "Tool Chest", S(-5.26, 7.39, 0.23), V(1.77, 2.32, 1.18), mutedRed)
for i = 1, 3 do
    part(shop, "Tool Chest Drawer", S(-5.26, 6.61 + i * 0.45, 0.84), V(1.58, 0.341, 0.06), rust)
    part(
        shop,
        "Tool Chest Drawer Pull",
        S(-5.26, 6.64 + i * 0.45, 0.90),
        V(0.80, 0.063, 0.092),
        brass
    )
end
boxCollider("Tool Chest", S(-5.26, 7.35, 0.25), V(1.77, 2.47, 1.22))

part(shop, "Tool Board", S(-2.87, 9.47, -2.99), V(4.40, 1.65, 0.104), wood)
local function wrench(x: number, y: number, twist: number)
    local cf = S(x, y, -2.91) * rbx.CFrame.Angles(0, 0, twist)
    for _, side in { -1, 1 } do
        local jaw = cf * C(side * 0.137, 0.355, 0) * rbx.CFrame.Angles(0, 0, -side * 0.29)
        part(shop, "Hanging Spanner Jaw", jaw, V(0.108, 0.27, 0.083), slate)
    end
    part(shop, "Hanging Spanner Head", cf * C(0, 0.255, 0), V(0.33, 0.145, 0.093), slate)
    part(shop, "Hanging Spanner Handle", cf * C(0, -0.045, 0), V(0.098, 0.553, 0.081), steel)
end
wrench(-3.94, 9.53, -0.16)
wrench(-3.08, 9.53, 0.10)
part(
    shop,
    "Hammer Handle",
    S(-2.17, 9.39, -2.891) * rbx.CFrame.Angles(0, 0, -0.12),
    V(0.112, 0.801, 0.098),
    brass
)
part(shop, "Hammer Head", S(-2.11, 9.78, -2.85), V(0.447, 0.171, 0.178), dark)
part(shop, "Bench Oil Can", S(-0.72, 8.86, -2.29), V(0.38, 0.49, 0.43), mutedRed)
beam(
    shop,
    "Oil Can Spout",
    S(-0.60, 9.01, -2.28).Position,
    S(-0.23, 9.18, -2.21).Position,
    0.071,
    steel,
    Enum.PartType.Cylinder
)
for i = 0, 2 do
    local wedge = S(-2.50 + i * 0.36, 8.77, -1.77) * rbx.CFrame.Angles(0, 0.28 - 0.11 * i, 0)
    part(shop, "Spare Bucket Tooth", wedge, V(0.240, 0.188, 0.48), slate, Enum.PartType.Wedge)
end

-- An open two-tier parts rack displays an idler, tread pads and a coiled hose.
for _, x in { 1.03, 5.47 } do
    for _, z in { -2.86, -1.20 } do
        part(shop, "Parts Rack Upright", S(x, 7.59, z), V(0.163, 2.91, 0.172), steel)
    end
end
for _, y in { 6.66, 7.80 } do
    part(shop, "Parts Rack Shelf", S(3.24, y, -2.04), V(4.55, 0.136, 1.81), slate)
end
boxCollider("Parts Rack", S(3.24, 7.34, -2.03), V(4.55, 2.10, 1.81))
for i = 0, 1 do
    part(
        shop,
        "Spare Idler",
        S(4.12, 6.82 + i * 0.19, -2.09) * rbx.CFrame.Angles(0, 0, math.pi / 2),
        V(0.171, 1.067, 1.067),
        dark,
        Enum.PartType.Cylinder
    )
    part(
        shop,
        "Spare Idler Hub",
        S(4.12, 6.94 + i * 0.19, -2.09) * rbx.CFrame.Angles(0, 0, math.pi / 2),
        V(0.095, 0.383, 0.383),
        brass,
        Enum.PartType.Cylinder
    )
end
for i = 0, 3 do
    part(
        shop,
        "Spare Track Pad",
        S(2.06, 6.83 + i * 0.106, -2.02) * rbx.CFrame.Angles(0, i * 0.052, 0),
        V(0.98, 0.101, 0.61),
        steel
    )
end
local ringCenter = S(4.19, 8.427, -2.14).Position
for loop = 1, 2 do
    local radius = 0.466 - loop * 0.092
    for i = 0, 13 do
        local function at(a: number): Vector3
            return ringCenter + V(math.cos(a) * radius, math.sin(a) * radius, 0.033 * loop)
        end
        beam(
            shop,
            "Coiled Hydraulic Hose",
            at((i - 0.09) * math.pi / 7),
            at((i + 1.09) * math.pi / 7),
            0.099,
            dark,
            Enum.PartType.Cylinder
        )
    end
end
part(shop, "Parts Tray", S(2.25, 7.99, -2.03), V(1.16, 0.258, 0.91), rust)
for _, x in { 1.98, 2.29, 2.54 } do
    part(
        shop,
        "Parts Tray Coupling",
        S(x, 8.148, -2.01) * rbx.CFrame.Angles(0, 0.14 * x, 0),
        V(0.285, 0.129, 0.129),
        brass,
        Enum.PartType.Cylinder
    )
end

-- Water and oil drums sit on a pallet at the rear edge of the workshop.
for i, row in { { 56.02, -38.55, 1.41 }, { 57.94, -38.79, 1.27 }, { 57.08, -40.08, 1.27 } } do
    local x, z, diameter = row[1], row[2], row[3]
    local height = 1.61 - 0.082 * i
    for k = -1, 1 do
        part(
            dressing,
            "Drum Pallet Slat",
            C(x + k * 0.39, 6.148, z),
            V(0.352, 0.181, 1.56),
            wood,
            nil,
            Enum.Material.WoodPlanks
        )
    end
    local turn = rbx.CFrame.Angles(0, 0, math.pi / 2)
    part(
        dressing,
        "Service Drum",
        C(x, 6.24 + height / 2, z) * turn,
        V(height, diameter, diameter),
        if i == 1 then teal else rust,
        Enum.PartType.Cylinder
    )
    for _, y in { 0.224, height - 0.188 } do
        part(
            dressing,
            "Service Drum Hoop",
            C(x, 6.24 + y, z) * turn,
            V(0.096, diameter + 0.071, diameter + 0.071),
            dark,
            Enum.PartType.Cylinder
        )
    end
    part(
        dressing,
        "Service Drum Filler Cap",
        C(x + 0.18, 6.29 + height, z - 0.163) * turn,
        V(0.089, 0.230, 0.230),
        brass,
        Enum.PartType.Cylinder
    )
    boxCollider(
        "Service Drum",
        C(x, 6.26 + height / 2, z),
        V(diameter * 0.94, height, diameter * 0.94)
    )
end

-- Entrance marker and short use-worn rails on the back of the service area.
local signX, signZ = 16.67, -16.78
for _, x in { -1.07, 1.07 } do
    part(dressing, "Workshop Waymark Post", C(signX + x, 7.60, signZ), V(0.169, 3.21, 0.181), dark)
    part(dressing, "Workshop Waymark Foot", C(signX + x, 6.15, signZ), V(0.46, 0.31, 0.52), stone)
end
part(dressing, "Workshop Waymark Board", C(signX, 8.45, signZ), V(2.58, 1.07, 0.154), teal)
for _, y in { 7.947, 8.952 } do
    part(dressing, "Workshop Waymark Trim", C(signX, y, signZ + 0.02), V(2.62, 0.088, 0.173), dark)
end
local symbol = C(signX, 8.43, signZ + 0.097) * rbx.CFrame.Angles(0, 0, -0.78)
part(dressing, "Waymark Spanner Handle", symbol * C(0, -0.082, 0), V(0.136, 0.51, 0.051), canvas)
part(dressing, "Waymark Spanner Jaw", symbol * C(0, 0.166, 0), V(0.327, 0.132, 0.066), canvas)
for _, sign in { -1, 1 } do
    part(
        dressing,
        "Waymark Spanner Jaw",
        symbol * C(sign * 0.126, 0.298, 0) * rbx.CFrame.Angles(0, 0, -sign * 0.17),
        V(0.110, 0.221, 0.066),
        canvas
    )
end
for _, run in { { 18.04, 27.23, -36.64 }, { 61.64, 77.30, -40.12 } } do
    local x0, x1, z = run[1], run[2], run[3]
    for _, x in { x0, (x0 + x1) / 2, x1 } do
        part(dressing, "Low Rear Guard Post", C(x, 6.72, z), V(0.24, 1.47, 0.238), dark)
    end
    part(
        dressing,
        "Low Rear Guard Rail",
        C((x0 + x1) / 2, 7.21, z),
        V(x1 - x0 + 0.21, 0.153, 0.156),
        slate
    )
end

local path = "assets/world/machine_yard/DuneBaron_MachineYard.rbxm"
local bytes = rbx.serializeModel({ yard })
local restored = rbx.deserializeModel(bytes)[1]
assert(restored.Name == "MachineYard" and #restored.Displays:GetChildren() == 4)
local bounds = {}
for _, model in restored.Displays:GetChildren() do
    assert(model.PrimaryPart and model.PrimaryPart.Anchored and model:GetAttribute("DisplayOnly"))
    bounds[model.Name] = model:GetAttribute("VisibleHeightStuds")
    for _, p in model:GetDescendants() do
        if p:IsA("BasePart") then
            assert(p.Anchored and not p.CanCollide)
        end
        assert(not p:IsA("ModuleScript") and not p:IsA("KeyframeSequence") and not p:IsA("Motor6D"))
    end
end
assert(
    bounds.Display_vacuum_robot < 3
        and bounds.Display_mega_machine > bounds.Display_mini_digger * 1.65
)
assert(bounds.Display_bucket_chain > bounds.Display_vacuum_robot * 2.5)
fs.writeFile(path, bytes)
print(path, "4 full-scale displays, a workshop and a clear aisle")
