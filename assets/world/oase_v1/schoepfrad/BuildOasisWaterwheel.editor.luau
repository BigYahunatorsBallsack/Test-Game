--!strict
-- Authoring only. Make a terracotta-bucket waterwheel and its editable rotation clip.
local offline = game == nil
local rbx = if offline then require("@lune/roblox") else nil
local Instance = if rbx then rbx.Instance else Instance
local Vector3 = if rbx then rbx.Vector3 else Vector3
local CFrame = if rbx then rbx.CFrame else CFrame
local Color3 = if rbx then rbx.Color3 else Color3
local Enum = if rbx then rbx.Enum else Enum
local fs = if offline then require("@lune/fs") else nil
local V, C, A, rgb = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local Y = Vector3.yAxis
local mat = Enum.Material
local modelName = "OldOasisWaterwheelV1"
local siteX, siteZ = 388.8, 668.4
local destination: Instance?
local height: (number, number) -> number
local waterY: number

if offline then
    height = require("../../duenenmeer_v3/OasisApproachSurface").height
    -- The preview reconstructs both terrain and water from voxel-center samples.
    waterY = 10.5
else
    local run = game:GetService("RunService")
    assert(
        run:IsStudio() and not run:IsRunning() and game.PlaceId == 135831532782380,
        "Use Every Last Grain in Studio Edit"
    )
    local world = workspace:FindFirstChild("DuneBaronWorld")
    assert(
        world and world:GetAttribute("OasisTerrainRevision") == 1,
        "Oasis V1 terrain is required"
    )
    local art = assert(world:FindFirstChild("OasisArtV1"), "Install the oasis landmarks first")
    local structures = assert(art:FindFirstChild("Structures"), "Oasis structures missing")
    assert(structures:FindFirstChild("OldSpringTerrace"), "The old spring terrace is required")
    destination = structures
    assert(not destination:FindFirstChild(modelName), "The waterwheel is already installed")
    local solid = RaycastParams.new()
    solid.FilterType, solid.FilterDescendantsInstances, solid.IgnoreWater =
        Enum.RaycastFilterType.Include, { workspace.Terrain }, true
    local liquid = RaycastParams.new()
    liquid.FilterType, liquid.FilterDescendantsInstances, liquid.IgnoreWater =
        Enum.RaycastFilterType.Include, { workspace.Terrain }, false
    local function hit(x: number, z: number, params: RaycastParams): RaycastResult
        return assert(
            workspace:Raycast(V(x, 101, z), V(0, -160, 0), params),
            "Oasis terrain missing"
        )
    end
    height = function(x, z)
        return hit(x, z, solid).Position.Y
    end
    local water = hit(siteX, siteZ, liquid)
    assert(
        water.Material == mat.Water and water.Position.Y - height(siteX, siteZ) >= 1.25,
        "The wheel site must remain immersed"
    )
    waterY = water.Position.Y
end

local pivotPoint = V(siteX, waterY + 4.52, siteZ)
local axle = CFrame.lookAt(pivotPoint, pivotPoint + V(0.94, 0, 0.34))
local model = Instance.new("Model")
model.Name, model.WorldPivot = modelName, axle
model:SetAttribute("Owner", "DuneBaronOasisWaterwheel")
model:SetAttribute("ArtVersion", 1)
model:SetAttribute("SiteX", siteX)
model:SetAttribute("SiteZ", siteZ)
model:SetAttribute("WaterY", waterY)

local function group(name: string): Folder
    local f = Instance.new("Folder")
    f.Name, f.Parent = name, model
    return f
end

local foundation, rotor, channel, clips =
    group("BearingPiers"), group("BucketWheel"), group("StoneHeadTank"), group("AnimationClips")
local wood, edge, endGrain = rgb(137, 87, 52), rgb(96, 59, 38), rgb(185, 132, 82)
local clay, lip, baseClay = rgb(182, 91, 56), rgb(210, 117, 70), rgb(128, 69, 49)
local stone, light, cut = rgb(192, 139, 93), rgb(228, 185, 126), rgb(157, 111, 77)
local metal, bronze = rgb(67, 69, 60), rgb(173, 131, 76)
local tile, teal = rgb(62, 126, 117), rgb(36, 102, 99)

local function part(
    parent: Instance,
    name: string,
    cf: CFrame,
    size: Vector3,
    color: Color3,
    material: Enum.Material,
    solid: boolean?,
    shape: Enum.PartType?
): Part
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, cf, color, material
    p.Shape = shape or Enum.PartType.Block
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored, p.CanTouch, p.CanCollide, p.CanQuery = true, false, solid == true, solid == true
    p.Parent = parent
    return p
end

local function beam(
    parent: Instance,
    name: string,
    a: Vector3,
    b: Vector3,
    width: number,
    thickness: number,
    c: Color3,
    material: Enum.Material,
    solid: boolean?,
    round: boolean?
): Part
    local tangent = (b - a).Unit
    local helper = if math.abs(tangent.Y) > 0.95 then axle.LookVector else Y
    local up = (helper - tangent * helper:Dot(tangent)).Unit
    return part(
        parent,
        name,
        CFrame.fromMatrix((a + b) / 2, tangent, up),
        V((b - a).Magnitude, width, thickness),
        c,
        material,
        solid,
        if round then Enum.PartType.Cylinder else nil
    )
end

local function loc(x: number, y: number, z: number): Vector3
    return axle:PointToWorldSpace(V(x, y, z))
end

local function floor(x: number, z: number): Vector3
    local p = loc(x, 0, z)
    return V(p.X, height(p.X, p.Z), p.Z)
end

-- Narrow masonry piers hold the axle outside the moving rims.
for _, sign in { -1, 1 } do
    local x = sign * 2.18
    local ground = floor(x, 0)
    local capY = axle.Y - 0.55
    local rise = capY - ground.Y + 0.50
    part(
        foundation,
        "Submerged Pier Foot",
        C(ground - Y * 0.13) * axle.Rotation,
        V(1.48, 0.85, 2.28),
        cut,
        mat.Sandstone,
        true
    )
    for row = 1, 6 do
        local h = rise / 6
        local y = h * (row - 0.5) - 0.50
        local c = if row % 3 == 0
            then cut:Lerp(stone, 0.64)
            else stone:Lerp(light, (row % 3) * 0.14)
        part(
            foundation,
            "Stacked Bearing Pier",
            C(ground + Y * y) * axle.Rotation * A(0, sign * (row % 2) * 0.024, 0),
            V(1.13 + (6 - row) * 0.085, h - 0.017, 1.76 - row * 0.065),
            c,
            mat.Sandstone,
            true
        )
    end
    part(
        foundation,
        "Dressed Bearing Cap",
        axle * C(x, -0.56, 0),
        V(1.47, 0.34, 1.49),
        light,
        mat.Sandstone,
        true
    )
    part(
        foundation,
        "Cedar Axle Seat",
        axle * C(x, -0.285, 0),
        V(1.16, 0.31, 0.99),
        wood,
        mat.Wood,
        true
    )
    part(
        foundation,
        "Bronze Bearing Collar",
        axle * C(x, 0, 0),
        V(0.84, 0.82, 0.82),
        bronze,
        mat.CorrodedMetal,
        false,
        Enum.PartType.Cylinder
    )
end

local root = part(rotor, "AxleRoot", axle, V(0.12, 0.12, 0.12), metal, mat.Metal)
root.Transparency, root.CastShadow = 1, false
local pivot = part(rotor, "WheelRotor", axle, V(0.20, 0.20, 0.20), wood, mat.Wood)
pivot.Transparency, pivot.CastShadow, pivot.Anchored, pivot.Massless = 1, false, false, true
local motor = Instance.new("Motor6D")
motor.Name, motor.Part0, motor.Part1, motor.Parent = "AxleHinge", root, pivot, root

local function attach(p: Part): Part
    p.Anchored, p.Massless = false, true
    local w = Instance.new("WeldConstraint")
    w.Part0, w.Part1, w.Parent = pivot, p, p
    return p
end

local function moving(
    name: string,
    offset: CFrame,
    size: Vector3,
    c: Color3,
    material: Enum.Material,
    shape: Enum.PartType?
): Part
    return attach(part(rotor, name, axle * offset, size, c, material, false, shape))
end

moving("Hardwood Axle", C(-0.15, 0, 0), V(5.65, 0.42, 0.42), edge, mat.Wood, Enum.PartType.Cylinder)
moving("Carved Wheel Hub", C(), V(1.56, 1.32, 1.32), wood, mat.Wood, Enum.PartType.Cylinder)
for _, sign in { -1, 1 } do
    moving(
        "Hub Plate",
        C(sign * 0.805, 0, 0),
        V(0.15, 1.24, 1.24),
        bronze,
        mat.CorrodedMetal,
        Enum.PartType.Cylinder
    )
end

local ringN, ringRadius = 20, 4.83
local chord = 2 * ringRadius * math.sin(math.pi / ringN)
for i = 0, ringN - 1 do
    local at = A((i + 0.5) * 2 * math.pi / ringN, 0, 0)
        * C(0, 0, ringRadius * math.cos(math.pi / ringN))
    for _, sign in { -1, 1 } do
        moving(
            "Weathered Outer Felloe",
            at * C(0.59 * sign, 0, 0),
            V(0.31, chord + 0.07, 0.34),
            wood:Lerp(endGrain, 0.13 + (i % 3) * 0.11),
            mat.WoodPlanks
        )
        if i % 2 == 0 then
            moving(
                "Felloe Rivet",
                at * C(0.758 * sign, 0, -0.026),
                V(0.083, 0.20, 0.20),
                bronze,
                mat.CorrodedMetal,
                Enum.PartType.Cylinder
            )
        end
    end
end

for i = 0, 7 do
    local ray = A(i * math.pi / 4, 0, 0)
    moving(
        "Tapered Cedar Spoke",
        ray * C(0, 0, 2.70),
        V(0.38, 0.40, 4.33),
        wood:Lerp(endGrain, i % 2 * 0.15),
        mat.Wood
    )
    moving("Spoke To Rim Yoke", ray * C(0, 0, 4.48), V(1.27, 0.26, 0.49), endGrain, mat.Wood)
end

-- The open side faces the direction of rotation. The short spout points to the beside-wheel intake.
local buckets = 12
for i = 0, buckets - 1 do
    local around = A(i * 2 * math.pi / buckets, 0, 0) * C(0, 0, 4.51)
    local c = clay:Lerp(lip, (i % 3) * 0.13)
    moving("Bucket Seat", around * C(0, -0.275, -0.16), V(1.32, 0.23, 0.44), edge, mat.Wood)
    moving(
        "Earthenware Bucket Bottom",
        around * C(0, -0.207, 0),
        V(0.93, 0.18, 0.59),
        baseClay,
        mat.Sandstone
    )
    for _, s in { -1, 1 } do
        moving(
            "Earthenware Bucket Side",
            around * C(0, 0.030, s * 0.267) * A(s * 0.11, 0, 0),
            V(1.05, 0.60, 0.12),
            c,
            mat.Sandstone
        )
        local h = if s > 0 then 0.39 else 0.54
        moving(
            "Earthenware Bucket End",
            around * C(s * 0.477, -0.27 + h * 0.5, 0) * A(0, 0, -s * 0.12),
            V(0.13, h, 0.48),
            c:Lerp(baseClay, 0.15),
            mat.Sandstone
        )
        moving(
            "Worn Bucket Rim",
            around * C(0, 0.322, s * 0.304),
            V(1.12, 0.08, 0.11),
            lip,
            mat.Sandstone
        )
    end
    moving(
        "Short Terracotta Pouring Lip",
        around * C(0.626, 0.093, 0) * A(0, 0, -0.17),
        V(0.43, 0.11, 0.42),
        lip,
        mat.Sandstone
    )
end

-- The hand grip turns with the axle on the opposite side to the trough.
moving("Outboard Hand-Crank", C(-2.975, 0.33, 0), V(0.17, 0.87, 0.20), bronze, mat.CorrodedMetal)
moving(
    "Hand-Crank Grip",
    C(-3.29, 0.72, 0),
    V(0.64, 0.23, 0.23),
    endGrain,
    mat.Wood,
    Enum.PartType.Cylinder
)

-- The intake is outside the rotor envelope. A narrow, braced aqueduct ends above its stone tank.
local cx = 1.86
local first, last = loc(cx, 4.14, -0.18), loc(cx, 2.79, -8.37)
local midpoint = (first + last) / 2
local bed = CFrame.lookAt(midpoint, last, Y)
local length = (last - first).Magnitude
part(channel, "Carved Cedar Channel", bed, V(1.44, 0.35, length), edge, mat.Wood, true)
for i = 1, 7 do
    local z = (i - 4) * length / 7
    part(
        channel,
        "Worn Turquoise Channel Tile",
        bed * C(0, 0.209, z),
        V(1.11, 0.084, length / 7 - 0.024),
        teal:Lerp(tile, i % 3 * 0.17),
        mat.Marble
    )
end
for _, sign in { -1, 1 } do
    part(
        channel,
        "Timber Channel Lip",
        bed * C(sign * 0.665, 0.245, 0),
        V(0.16, 0.47, length),
        endGrain,
        mat.Wood
    )
end
part(
    channel,
    "Flared Capture Mouth",
    axle * C(1.51, 4.07, -0.28) * A(0.09, 0, 0.08),
    V(0.97, 0.19, 1.26),
    bronze,
    mat.CorrodedMetal
)
part(
    channel,
    "Ceramic Pour Spout",
    axle * C(cx, 2.66, -8.64) * A(-0.34, 0, 0),
    V(0.80, 0.16, 1.20),
    lip,
    mat.Sandstone
)

for i, z in { -1.03, -4.25 } do
    local x = 2.02 + i * 0.11
    local g = floor(x, z)
    local top = loc(x, if i == 1 then 3.89 else 3.34, z)
    part(
        channel,
        "Raised Aqueduct Foot",
        C(g + Y * 0.12) * axle.Rotation,
        V(1.30, 0.71, 1.26),
        cut,
        mat.Sandstone,
        true
    )
    beam(channel, "Cedar Aqueduct Support", g + Y * 0.30, top, 0.52, 0.58, wood, mat.Wood, true)
    beam(
        channel,
        "Counter Brace",
        loc(x, if i == 1 then 1.5 else 0.9, z),
        loc(2.56, if i == 1 then 3.44 else 3.04, z - 1.45),
        0.27,
        0.31,
        endGrain,
        mat.Wood
    )
    part(
        channel,
        "Glazed Support Strap",
        C(top - Y * 0.47) * axle.Rotation,
        V(0.65, 0.22, 0.65),
        teal,
        mat.CorrodedMetal
    )
end

local tank = axle * C(cx + 0.31, 2.19, -9.60)
for _, x in { -1.04, 1.04 } do
    local p = tank:PointToWorldSpace(V(x, 0, 0))
    local y = height(p.X, p.Z)
    local h = p.Y - y + 0.32
    for row = 1, 5 do
        local course = h / 5
        part(
            channel,
            "Tank Masonry Pier",
            C(p.X, y - 0.50 + (row - 0.5) * course, p.Z) * axle.Rotation,
            V(0.90 + (5 - row) * 0.07, course - 0.02, 1.74),
            stone:Lerp(light, (row % 3) * 0.17),
            mat.Sandstone,
            true
        )
    end
end
part(
    channel,
    "Stone Catch Tank Base",
    tank * C(0, 0.001, 0),
    V(3.43, 0.45, 2.84),
    cut,
    mat.Sandstone,
    true
)
part(
    channel,
    "Turquoise Tank Interior",
    tank * C(0, 0.245, 0),
    V(2.77, 0.09, 2.15),
    tile,
    mat.Marble
)
for _, sign in { -1, 1 } do
    part(
        channel,
        "Stone Tank Long Rim",
        tank * C(sign * 1.45, 0.39, 0),
        V(0.48, 0.55, 2.84),
        light,
        mat.Sandstone,
        true
    )
    part(
        channel,
        "Stone Tank Short Rim",
        tank * C(0, 0.39, sign * 1.185),
        V(2.48, 0.55, 0.46),
        stone,
        mat.Sandstone,
        true
    )
end

local controller = Instance.new("AnimationController")
controller.Parent = model
Instance.new("Animator", controller)
local sequence = Instance.new("KeyframeSequence")
sequence.Name, sequence.Loop, sequence.Priority, sequence.Parent =
    "WaterwheelTurnLoop", true, Enum.AnimationPriority.Idle, clips
local duration, frames = 9.6, 48
sequence:SetAttribute("DurationSeconds", duration)
for i = 0, frames do
    local f = Instance.new("Keyframe")
    f.Time, f.Parent = duration * i / frames, sequence
    local r = Instance.new("Pose")
    r.Name, r.Weight, r.Parent = root.Name, 0, f
    local p = Instance.new("Pose")
    p.Name, p.CFrame = pivot.Name, A(-math.pi * 2 * (i % frames) / frames, 0, 0)
    p.Weight, p.EasingStyle, p.Parent = 1, Enum.PoseEasingStyle.Linear, r
end

if rbx and fs then
    local path = "assets/world/oase_v1/schoepfrad/DuneBaron_OasisWaterwheel.rbxm"
    local bytes = rbx.serializeModel({ model })
    local copy = rbx.deserializeModel(bytes)[1]
    assert(
        copy.AnimationClips.WaterwheelTurnLoop.Loop
            and #copy.AnimationClips.WaterwheelTurnLoop:GetChildren() == frames + 1
    )
    for _, child in copy:GetDescendants() do
        assert(not child:IsA("LuaSourceContainer"))
    end
    fs.writeFile(path, bytes)
    print(path, #copy:GetDescendants(), "instances including the wheel clip")
else
    model.Parent = destination
    print(modelName, "placed beside OldSpringTerrace")
end
