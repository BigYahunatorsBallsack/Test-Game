--!strict
-- Authoring only. Build the overlook and its editable windsock loop.
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
local name = "SaltLakeWindwatchV1"
local destination: Instance?
local height: (number, number) -> number

if offline then
    height = require("./SaltLakeSurface").height
else
    local run = game:GetService("RunService")
    assert(
        run:IsStudio() and not run:IsRunning() and game.PlaceId == 135831532782380,
        "Use Every Last Grain in Studio Edit"
    )
    local world = workspace:FindFirstChild("DuneBaronWorld")
    assert(
        world and world:GetAttribute("SaltLakeTerrainRevision") == 1,
        "Salt Lake V1 terrain is required"
    )
    destination =
        assert(world:FindFirstChild("SaltLakeArtV1"), "Install the salt lake landmarks first")
    assert(not destination:FindFirstChild(name), "The windwatch is already installed")
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { workspace.Terrain }
    params.IgnoreWater = true
    height = function(x, z)
        return assert(
            workspace:Raycast(V(x, 184, z), V(0, -224, 0), params),
            "Salt lake ground missing"
        ).Position.Y
    end
end

local siteX, siteZ = 1227, 837
local origin = V(siteX, height(siteX, siteZ), siteZ)
local at = CFrame.lookAt(origin, origin + V(-1, 0, -0.83))
local model = Instance.new("Model")
model.Name, model.WorldPivot = name, at
model:SetAttribute("Owner", "DuneBaronWindwatch")
model:SetAttribute("ArtVersion", 1)
model:SetAttribute("SiteX", siteX)
model:SetAttribute("SiteZ", siteZ)

local function group(label: string): Folder
    local folder = Instance.new("Folder")
    folder.Name, folder.Parent = label, model
    return folder
end

local deck, mast, fabric, clips =
    group("Lookout"), group("SignalMast"), group("Windsock"), group("AnimationClips")
local stone, pale, shadow = rgb(188, 168, 130), rgb(225, 209, 171), rgb(154, 134, 101)
local wood, bleached = rgb(118, 80, 57), rgb(165, 122, 82)
local dark, turquoise, green = rgb(62, 70, 67), rgb(57, 123, 122), rgb(37, 89, 90)
local brass, clay, linen = rgb(177, 127, 69), rgb(198, 83, 53), rgb(239, 218, 172)

local function part(
    parent: Instance,
    label: string,
    cf: CFrame,
    size: Vector3,
    color: Color3,
    material: Enum.Material,
    solid: boolean?,
    shape: Enum.PartType?
): Part
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color, p.Material = label, size, cf, color, material
    p.Shape = shape or Enum.PartType.Block
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, solid == true, solid == true, false
    p.Parent = parent
    return p
end

local function beam(
    parent: Instance,
    label: string,
    a: Vector3,
    b: Vector3,
    wide: number,
    deep: number,
    color: Color3,
    material: Enum.Material,
    solid: boolean?,
    round: boolean?
): Part
    local axis = (b - a).Unit
    local up = if math.abs(axis.Y) > 0.94 then at.LookVector else Y
    local normal = (up - axis * up:Dot(axis)).Unit
    return part(
        parent,
        label,
        CFrame.fromMatrix((a + b) * 0.5, axis, normal),
        V((b - a).Magnitude, wide, deep),
        color,
        material,
        solid,
        if round then Enum.PartType.Cylinder else nil
    )
end

local function site(x: number, y: number, z: number): Vector3
    return at:PointToWorldSpace(V(x, y, z))
end

local function floor(x: number, z: number): Vector3
    local p = site(x, 0, z)
    return V(p.X, height(p.X, p.Z), p.Z)
end

-- The deck is level. The long salt-worn piers extend down into the different slopes.
local stairRun, stairFront, steps = 0.81, -4.33, 5
local entry = stairFront - steps * stairRun
local entryY = math.min(floor(-1.85, entry).Y, floor(0, entry).Y, floor(1.85, entry).Y) - origin.Y
local deckTop = math.max(entryY + 1.78, floor(0, -4.25).Y - origin.Y + 1.15)
for _, x in { -4.25, 4.25 } do
    for _, z in { -3.30, 3.30 } do
        local p = floor(x, z)
        local top = site(x, deckTop - 0.42, z)
        local h = top.Y - p.Y + 0.75
        part(
            deck,
            "Buried Limestone Foot",
            C(p - Y * 0.12) * at.Rotation,
            V(2.42, 0.88, 2.32),
            shadow,
            mat.Limestone,
            true
        )
        part(
            deck,
            "Saltstone Pier",
            C(top - Y * h / 2) * at.Rotation,
            V(1.74, h, 1.72),
            stone,
            mat.Limestone,
            true
        )
        part(
            deck,
            "Dressed Pier Cap",
            C(top - Y * 0.15) * at.Rotation,
            V(2.32, 0.42, 2.35),
            pale,
            mat.Limestone,
            true
        )
    end
end
for i = -4, 4 do
    part(
        deck,
        "Bleached Deck Plank",
        at * C(0, deckTop - 0.20, i * 0.96),
        V(10.24, 0.40, 0.962),
        wood:Lerp(bleached, 0.5 + (i % 3) * 0.15),
        mat.WoodPlanks,
        true
    )
end
for _, x in { -4.48, 4.48 } do
    part(
        deck,
        "Deck Stringer",
        at * C(x, deckTop - 0.55, 0),
        V(0.52, 0.46, 8.82),
        wood,
        mat.Wood,
        true
    )
end

for i = 1, steps do
    local z = entry + stairRun * (i - 0.5)
    local y = entryY + (deckTop - entryY) * i / steps
    local below = math.min(floor(-1.6, z).Y, floor(0, z).Y, floor(1.6, z).Y) - origin.Y - 0.48
    local h = math.max(y - below, 0.29)
    part(
        deck,
        "Broad Limestone Step",
        at * C(0, y - h * 0.5, z),
        V(3.72 + (steps - i) * 0.13, h, stairRun + 0.02),
        if i % 2 == 0 then pale else stone,
        mat.Limestone,
        true
    )
end

for _, x in { -4.85, 4.85 } do
    for _, z in { -3.6, 0.0, 3.85 } do
        part(
            deck,
            "Sea-Worn Rail Post",
            at * C(x, deckTop + 1.01, z),
            V(0.35, 2.16, 0.35),
            wood,
            mat.Wood,
            true
        )
        part(
            deck,
            "Brass Rail Cap",
            at * C(x, deckTop + 2.11, z),
            V(0.44, 0.12, 0.44),
            brass,
            mat.Metal
        )
    end
    for _, y in { 0.71, 1.65 } do
        part(
            deck,
            "Side Guard Rail",
            at * C(x, deckTop + y, 0.13),
            V(0.24, 0.31, 7.79),
            if y > 1 then green else wood,
            mat.Wood,
            true
        )
    end
end
for _, x in { -3.37, 3.37 } do
    part(
        deck,
        "Entry Guard Rail",
        at * C(x, deckTop + 1.5, -3.6),
        V(2.85, 0.31, 0.24),
        green,
        mat.Wood,
        true
    )
end
part(
    deck,
    "Lake-Facing Guard Rail",
    at * C(0, deckTop + 1.65, 3.85),
    V(9.92, 0.31, 0.25),
    green,
    mat.Wood,
    true
)

-- An inset brass sight gives the platform a lake-facing point of interest.
part(
    deck,
    "Sight Plinth",
    at * C(2.32, deckTop + 0.88, 2.67),
    V(1.16, 1.79, 1.20),
    stone,
    mat.Limestone,
    true
)
part(
    deck,
    "Bronze Sight Plate",
    at * C(2.32, deckTop + 1.81, 2.67),
    V(1.63, 0.14, 1.55),
    brass,
    mat.Metal
)
beam(
    deck,
    "Compass Dial",
    site(2.32, deckTop + 1.87, 2.67),
    site(2.32, deckTop + 1.98, 2.67),
    1.25,
    1.25,
    green,
    mat.Metal,
    false,
    true
)
part(
    deck,
    "Lakeward Pointer",
    at * C(2.32, deckTop + 2.00, 2.73) * A(0, 0.32, 0),
    V(0.13, 0.055, 0.99),
    pale,
    mat.Metal
)

local mx, mz, sockY = -2.72, 1.44, deckTop + 10.65
part(
    mast,
    "Mast Pedestal",
    at * C(mx, deckTop + 0.40, mz),
    V(2.14, 0.80, 2.18),
    stone,
    mat.Limestone,
    true
)
part(
    mast,
    "Main Salt-Stained Mast",
    at * C(mx, deckTop + 5.57, mz),
    V(0.63, 10.30, 0.60),
    wood,
    mat.Wood,
    true
)
for _, y in { deckTop + 1.0, deckTop + 6.35, sockY - 0.28 } do
    part(mast, "Oxidized Mast Strap", at * C(mx, y, mz), V(0.75, 0.31, 0.72), green, mat.Metal)
end
for _, x in { -3.82, -1.05 } do
    beam(
        mast,
        "Diagonal Mast Brace",
        site(x, deckTop + 0.19, 2.95),
        site(mx, deckTop + 4.02, mz),
        0.29,
        0.33,
        bleached,
        mat.Wood
    )
end

-- Five fabric sections overlap at their seams and share an anchored root.
local wind = C(site(mx, sockY, mz)) * A(0, math.rad(28), 0)
beam(
    mast,
    "Swivel Arm",
    wind.Position,
    wind:PointToWorldSpace(V(1.12, 0, 0)),
    0.14,
    0.14,
    dark,
    mat.Metal,
    false,
    true
)
local mouth = wind * C(1.12, 0, 0)
local root = part(fabric, "WindsockRoot", mouth, V(0.14, 0.14, 0.14), dark, mat.Metal)
root.Transparency, root.CastShadow = 1, false
local segmentNames = { "Throat", "BodyNear", "BodyFar", "Taper", "Tail" }
local lengths = { 1.03, 1.07, 1.22, 1.03, 0.90 }
local radii = { 0.84, 0.80, 0.68, 0.55, 0.42, 0.31 }
local sides = 8

local function ring(cf: CFrame, x: number, radius: number, side: number): Vector3
    local a = math.pi * 2 * side / sides
    return cf:PointToWorldSpace(V(x, math.sin(a) * radius, math.cos(a) * radius))
end

local function fasten(p: BasePart, pivot: BasePart)
    p.Anchored, p.Massless = false, true
    local w = Instance.new("WeldConstraint")
    w.Part0, w.Part1, w.Parent = pivot, p, p
end

local function triangle(a: Vector3, b: Vector3, c: Vector3, color: Color3, pivot: Part)
    if (b - a).Magnitude > (c - b).Magnitude and (b - a).Magnitude > (c - a).Magnitude then
        a, c = c, a
    elseif (c - a).Magnitude > (c - b).Magnitude then
        a, b = b, a
    end
    local ab, ac, bc = b - a, c - a, c - b
    local axis, x = bc.Unit, ac:Cross(ab).Unit
    local y = axis:Cross(x)
    local rise = math.abs(ab:Dot(y))
    for _, shape in
        { { b, axis, x, math.abs(ab:Dot(axis)) }, { c, -axis, -x, math.abs(ac:Dot(axis)) } }
    do
        if rise <= 0.009 or shape[4] <= 0.009 then
            continue
        end
        local cf = CFrame.fromMatrix((a + shape[1]) / 2, shape[3], y, shape[2])
        local piece = part(
            fabric,
            "Tapered Canvas",
            cf,
            V(0.029, rise, shape[4]),
            color,
            mat.Fabric,
            false,
            Enum.PartType.Wedge
        )
        fasten(piece, pivot)
    end
end

local previous: BasePart = root
for i, label in segmentNames do
    local offset = C(if i == 1 then 0 else lengths[i - 1], 0, 0)
        * A(0, 0, math.rad(if i == 1 then -9 else -5))
    local pivot =
        part(fabric, label, previous.CFrame * offset, V(0.10, 0.10, 0.10), dark, mat.Fabric)
    pivot.Transparency, pivot.CastShadow, pivot.Massless, pivot.Anchored = 1, false, true, false
    local motor = Instance.new("Motor6D")
    motor.Name, motor.Part0, motor.Part1, motor.C0, motor.Parent =
        label .. "Hinge", previous, pivot, offset, previous
    local color = if i % 2 == 1 then clay else linen
    local start = if i == 1 then 0 else -0.11
    local finish = lengths[i] + (if i < #lengths then 0.10 else 0)
    for j = 0, sides - 1 do
        local a, b =
            ring(pivot.CFrame, start, radii[i], j), ring(pivot.CFrame, start, radii[i], j + 1)
        local c, d =
            ring(pivot.CFrame, finish, radii[i + 1], j),
            ring(pivot.CFrame, finish, radii[i + 1], j + 1)
        local tint = color:Lerp(if j % 3 == 0 then brass else dark, (j % 4) * 0.035)
        triangle(a, b, d, tint, pivot)
        triangle(a, d, c, tint, pivot)
        if i == 1 then
            local rim =
                beam(fabric, "Bound Mouth Hem", a, b, 0.085, 0.095, brass, mat.Fabric, false, true)
            fasten(rim, pivot)
            if j == 0 or j == 3 or j == 5 then
                local tether = beam(
                    fabric,
                    "Hoop Bridle",
                    pivot.CFrame.Position,
                    a,
                    0.045,
                    0.045,
                    dark,
                    mat.Fabric,
                    false,
                    true
                )
                fasten(tether, pivot)
            end
        end
    end
    previous = pivot
end

local animation = Instance.new("AnimationController")
animation.Parent = model
Instance.new("Animator", animation)
local clip = Instance.new("KeyframeSequence")
clip.Name, clip.Loop, clip.Priority, clip.Parent =
    "LakeWindLoop", true, Enum.AnimationPriority.Idle, clips
local duration, frames = 3.2, 48
clip:SetAttribute("DurationSeconds", duration)
for i = 0, frames do
    local frame = Instance.new("Keyframe")
    frame.Time, frame.Parent = i * duration / frames, clip
    local pose = Instance.new("Pose")
    pose.Name, pose.Weight, pose.Parent = root.Name, 0, frame
    local phase = (i % frames) * 2 * math.pi / frames
    for j, label in segmentNames do
        local nextPose = Instance.new("Pose")
        local lag = phase - 0.52 * j
        local twist = 0.025 * math.sin(2 * lag)
        local sway = (0.023 + j * 0.009) * math.sin(lag)
        local lift = (0.036 + j * 0.012) * math.sin(lag) + 0.014 * math.sin(2 * phase - j)
        nextPose.Name, nextPose.CFrame, nextPose.Weight = label, A(twist, sway, lift), 1
        nextPose.EasingStyle, nextPose.Parent = Enum.PoseEasingStyle.Linear, pose
        pose = nextPose
    end
end

if rbx and fs then
    local path = "assets/world/salzsee_v1/windwarte/DuneBaron_Windwatch.rbxm"
    local data = rbx.serializeModel({ model })
    local copy = rbx.deserializeModel(data)[1]
    local exported = copy.AnimationClips.LakeWindLoop
    assert(exported.Loop and #exported:GetChildren() == frames + 1)
    for _, child in copy:GetDescendants() do
        assert(not child:IsA("LuaSourceContainer"))
    end
    fs.writeFile(path, data)
    print(path, #copy:GetDescendants(), "instances including the editable clip")
else
    model.Parent = destination
    print(name, "placed in SaltLakeArtV1")
end
