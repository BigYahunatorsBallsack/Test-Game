--!strict
-- Add rest stones and distinct branch markers to the existing oasis approach.
local offline = game == nil
local rbx = if offline then require("@lune/roblox") else nil
local Instance = if rbx then rbx.Instance else Instance
local CFrame = if rbx then rbx.CFrame else CFrame
local Vector3 = if rbx then rbx.Vector3 else Vector3
local Color3 = if rbx then rbx.Color3 else Color3
local Enum = if rbx then rbx.Enum else Enum
local C, V, rgb = CFrame.new, Vector3.new, Color3.fromRGB

local fs = if offline then require("@lune/fs") else nil
local terrainY: (number, number) -> number
local destination: Instance?
local modelName = "OasisApproachWayfinding"
if offline then
    terrainY = require("../OasisApproachSurface").height
else
    local run = game:GetService("RunService")
    assert(
        run:IsStudio() and not run:IsRunning() and game.PlaceId == 135831532782380,
        "Use Every Last Grain in Studio Edit"
    )
    local world = workspace:FindFirstChild("DuneBaronWorld")
    assert(world and world:GetAttribute("OasisTerrainRevision") == 1, "Oase V1 terrain is required")
    destination =
        assert(world:FindFirstChild("OasisArtV1"), "Install the existing oasis landmarks first")
    assert(not destination:FindFirstChild(modelName), "This approach kit is already installed")
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { workspace.Terrain }
    params.IgnoreWater = true
    terrainY = function(x, z)
        local hit = workspace:Raycast(V(x, 123, z), V(0, -160, 0), params)
        assert(hit, "Expected solid terrain at the oasis approach")
        return hit.Position.Y
    end
end

local model = Instance.new("Model")
model.Name = modelName
model.WorldPivot = C(224.8, terrainY(224.8, 550.7), 550.7)
model:SetAttribute("Owner", "DuneBaronOasisApproach")
model:SetAttribute("ArtVersion", 1)

local function group(name: string): Folder
    local f = Instance.new("Folder")
    f.Name, f.Parent = name, model
    return f
end
local rest, fork, branch = group("WaysideRest"), group("ForkMarker"), group("OchreTrail")
local sandstone = Enum.Material.Sandstone
local wood = Enum.Material.WoodPlanks
local fabric = Enum.Material.Fabric
local rust = rgb(168, 102, 69)
local taupe = rgb(167, 127, 91)
local beige = rgb(211, 165, 111)
local cream = rgb(225, 185, 132)
local dark = rgb(107, 71, 51)
local grain = rgb(153, 110, 67)
local ochre = rgb(231, 171, 75)
local orange = rgb(197, 126, 54)
local teal = rgb(36, 110, 110)
local agedTeal = rgb(74, 139, 128)
local rope = rgb(173, 131, 77)
local up = Vector3.yAxis

local function part(
    parent: Instance,
    name: string,
    cf: CFrame,
    size: Vector3,
    color: Color3,
    shape: Enum.PartType?,
    material: Enum.Material?
): Part
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
    p.Shape, p.Material = shape or Enum.PartType.Block, material or sandstone
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
    p.Parent = parent
    return p
end

local function beam(
    parent: Instance,
    name: string,
    a: Vector3,
    b: Vector3,
    width: number,
    color: Color3,
    material: Enum.Material,
    round: boolean?
): Part
    local axis = (b - a).Unit
    local hint = if math.abs(axis.Y) > 0.95 then Vector3.zAxis else up
    local y = (hint - axis * axis:Dot(hint)).Unit
    return part(
        parent,
        name,
        CFrame.fromMatrix((a + b) * 0.5, axis, y),
        V((b - a).Magnitude, width, width),
        color,
        if round then Enum.PartType.Cylinder else nil,
        material
    )
end

local function triangle(
    parent: Instance,
    name: string,
    a: Vector3,
    b: Vector3,
    c: Vector3,
    thickness: number,
    color: Color3,
    material: Enum.Material
)
    local ab, ac, bc = b - a, c - a, c - b
    if ab.Magnitude > ac.Magnitude and ab.Magnitude > bc.Magnitude then
        c, a = a, c
    elseif ac.Magnitude > bc.Magnitude then
        a, b = b, a
    end
    ab, ac, bc = b - a, c - a, c - b
    local normal = ac:Cross(ab)
    local axis, x = bc.Unit, normal.Unit
    local y = axis:Cross(x)
    local high = math.abs(ab:Dot(y))
    for _, piece in
        { { b, axis, x, math.abs(ab:Dot(axis)) }, { c, -axis, -x, math.abs(ac:Dot(axis)) } }
    do
        if piece[4] > 0.01 and high > 0.01 then
            local p = Instance.new("WedgePart")
            p.Name, p.Size = name, V(thickness, high, piece[4])
            p.CFrame = CFrame.fromMatrix((a + piece[1]) / 2, piece[3], y, piece[2])
            p.Color, p.Material = color, material
            p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
            p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
            p.Parent = parent
        end
    end
end

local function ground(x: number, z: number): Vector3
    return V(x, terrainY(x, z), z)
end

local function horizontal(base: Vector3, toward: Vector3): CFrame
    return CFrame.lookAt(base, V(toward.X, base.Y, toward.Z))
end

-- A small wind wall and bench borrow the existing rise beside the road.
local restX, restZ = 164, 465
local restFrame = horizontal(ground(restX, restZ), V(176, 0, 482))
local function restPoint(u: number, v: number): Vector3
    local p = restFrame:PointToWorldSpace(V(u, 0, v))
    return ground(p.X, p.Z)
end
local function restAt(u: number, v: number, y: number): CFrame
    local p = restFrame:PointToWorldSpace(V(u, 0, v))
    return (restFrame - restFrame.Position) + V(p.X, y, p.Z)
end
local padHeights = {}
for i = -2, 2 do
    local p = restPoint(-0.394, i * 1.16)
    table.insert(padHeights, p.Y)
end
local seatY = math.max(table.unpack(padHeights)) + 0.77
for side = -1, 1, 2 do
    for i = 0, 4 do
        local u = if side == 1 then -1.43 else -1.34 + 0.354 * i
        local v = if side == 1 then -3.08 + 1.50 * i else -3.12
        local y = restPoint(u, v).Y
        local h = 0.60 + 0.093 * math.sin(i * 1.15 + side)
        part(
            rest,
            "Windbreak Basal Stone",
            restAt(u, v, y + 0.153) * CFrame.Angles(0, 0.026 * (-1) ^ i, 0),
            V(if side == 1 then 0.783 else 0.584, h, if side == 1 then 1.49 else 0.93),
            if i % 3 == 0 then rust else beige
        )
        if side == 1 or i < 3 then
            local h2 = 0.482 + 0.131 * math.cos(i * 1.73)
            part(
                rest,
                "Crumbled Upper Stone",
                restAt(u - 0.067, v - 0.088, y + 0.153 + h / 2 + h2 / 2)
                    * CFrame.Angles(0.031 * i, 0.037 * (-1) ^ i, 0),
                V(if side == 1 then 0.752 else 0.547, h2, if side == 1 then 1.32 else 0.824),
                if i % 2 == 0 then cream else taupe
            )
        end
    end
end
for _, v in { -1.84, 0.0, 1.84 } do
    local under = restPoint(-0.43, v).Y - 0.15
    local height = seatY - under
    part(
        rest,
        "Rest Bench Foot",
        restAt(-0.43, v, under + height / 2),
        V(0.92, height, 0.731),
        taupe
    )
end
for i = 0, 3 do
    part(
        rest,
        "Weathered Bench Slab",
        restAt(-0.43, -2.16 + 1.439 * i, seatY + 0.116 + 0.017 * math.sin(i)),
        V(1.11, 0.243, 1.405),
        if i % 3 == 0 then beige else cream
    )
end
local rug = restAt(-0.36, 1.37, seatY + 0.257)
part(rest, "Rolled Bench Mat", rug, V(0.94, 0.076, 1.47), teal, nil, fabric)
for i = -2, 2 do
    part(
        rest,
        "Worn Mat Stripe",
        rug * C(0, 0.043, i * 0.276),
        V(0.91, 0.018, 0.104),
        if i % 2 == 0 then agedTeal else beige,
        nil,
        fabric
    )
end
for i = 0, 3 do
    local v = -2.52 + i * 1.65
    local p = restPoint(0.98, v)
    part(
        rest,
        "Resting Place Flat Stone",
        restAt(0.98, v, p.Y + 0.018) * CFrame.Angles(0, -0.071 * i, 0.025 * (i - 1)),
        V(0.92, 0.162, 0.93 + 0.077 * i),
        i % 2 == 0 and beige or rust,
        Enum.PartType.Wedge
    )
end
local pot = restPoint(-0.21, -3.37)
local turn = CFrame.Angles(0, 0, math.pi / 2)
part(
    rest,
    "Water Jar Foot",
    C(pot + V(0, 0.104, 0)) * turn,
    V(0.18, 0.67, 0.67),
    rust,
    Enum.PartType.Cylinder
)
part(
    rest,
    "Water Jar Body",
    C(pot + V(0, 0.57, 0)),
    V(0.91, 0.93, 0.91),
    rust,
    Enum.PartType.Ball,
    Enum.Material.SmoothPlastic
)
part(
    rest,
    "Water Jar Shoulder",
    C(pot + V(0, 0.89, 0)),
    V(0.713, 0.37, 0.713),
    beige,
    Enum.PartType.Ball,
    Enum.Material.SmoothPlastic
)
part(
    rest,
    "Water Jar Lip",
    C(pot + V(0, 1.079, 0)) * turn,
    V(0.103, 0.57, 0.57),
    taupe,
    Enum.PartType.Cylinder
)
part(
    rest,
    "Water Jar Glaze",
    C(pot + V(0, 0.877, 0)) * turn,
    V(0.065, 0.745, 0.745),
    teal,
    Enum.PartType.Cylinder,
    Enum.Material.SmoothPlastic
)

local restMast = restPoint(-1.85, 2.795)
part(rest, "Rest Flag Foot", C(restMast + V(0, 0.087, 0)), V(0.69, 0.471, 0.718), taupe)
beam(rest, "Rest Flagpole", restMast, restMast + V(0.041, 3.76, -0.028), 0.137, dark, wood, true)
local fa, fb, fc, fd =
    restMast + V(0.04, 3.57, -0.028),
    restMast + V(0.06, 3.01, -0.015),
    restMast + V(0.20, 3.51, 0.91),
    restMast + V(0.21, 3.04, 0.80)
triangle(rest, "Teal Rest Pennant", fa, fb, fc, 0.039, teal, fabric)
triangle(rest, "Teal Rest Pennant", fb, fd, fc, 0.039, agedTeal, fabric)

-- Both pointer ends face their real destinations at the fork.
local markX, markZ = 224.8, 550.7
local land = ground(markX, markZ)
part(
    fork,
    "Fork Marker Cairn",
    C(land + V(0, 0.078, 0)) * CFrame.Angles(0.031, 0.28, -0.06),
    V(1.17, 0.476, 1.05),
    rust
)
part(
    fork,
    "Fork Marker Upper Stone",
    C(land + V(0.046, 0.386, 0.011)) * CFrame.Angles(-0.08, 0.41, 0.031),
    V(0.91, 0.311, 0.81),
    beige
)
beam(
    fork,
    "Fork Marker Timber",
    land + V(0, 0.31, 0),
    land + V(0.04, 2.94, -0.047),
    0.225,
    dark,
    wood
)

local function pointer(
    name: string,
    destinationX: number,
    destinationZ: number,
    height: number,
    primary: Color3,
    tip: Color3
)
    local heading = V(destinationX - markX, 0, destinationZ - markZ).Unit
    local at = CFrame.fromMatrix(land + V(0.027, height, -0.03), heading, up)
    part(fork, name .. " Arm", at * C(0.655, 0, 0), V(1.69, 0.418, 0.191), primary, nil, wood)
    local a, b, c =
        at:PointToWorldSpace(V(1.48, -0.308, 0)),
        at:PointToWorldSpace(V(1.48, 0.308, 0)),
        at:PointToWorldSpace(V(2.07, 0, 0))
    triangle(fork, name .. " Tip", a, b, c, 0.181, tip, wood)
    for _, side in { -1, 1 } do
        part(
            fork,
            name .. " Inlay",
            at * C(0.89, 0, side * 0.102) * CFrame.Angles(0, 0, 0.78),
            V(0.198, 0.19, 0.026),
            tip
        )
        part(
            fork,
            "Pointer Pin",
            at * C(0.22, 0, side * 0.115),
            V(0.085, 0.085, 0.043),
            rope,
            nil,
            Enum.Material.Metal
        )
    end
end
pointer("Oasis Pointer", 221, 565, 2.43, teal, agedTeal)
pointer("Wreck Pointer", 246, 548, 1.59, orange, ochre)

for i, row in { { 228.78, 552.37, 1.61 }, { 235.33, 548.86, 1.26 }, { 240.73, 550.25, 1.33 } } do
    local at = ground(row[1], row[2])
    local h = row[3]
    part(
        branch,
        "Tie-stone",
        C(at + V(0, 0.055, 0)) * CFrame.Angles(0.12, 0.31 * i, 0.10),
        V(0.661, 0.281, 0.553),
        if i % 2 == 0 then rust else beige,
        Enum.PartType.Wedge
    )
    local top = at + V(0.166, h, -0.073)
    beam(branch, "Low Trail Stake", at + V(0, -0.092, 0), top, 0.113, dark, wood, true)
    local rag0, rag1 = top + V(0, -0.125, 0), top + V(-0.022, -0.596, 0.040)
    local rag2, rag3 = top + V(0.498, -0.204, 0.311), top + V(0.429, -0.517, 0.223)
    triangle(branch, "Ochre Trail Strip", rag0, rag1, rag2, 0.039, ochre, fabric)
    triangle(branch, "Darker Fold", rag1, rag3, rag2, 0.039, orange, fabric)
    beam(
        branch,
        "Trail Cloth Tie",
        rag0 + V(-0.065, 0.01, 0),
        rag0 + V(0.069, 0.034, 0.04),
        0.068,
        rope,
        fabric,
        true
    )
end

model:SetAttribute("RestX", restX)
model:SetAttribute("RestZ", restZ)
model:SetAttribute("ApproachForkX", 214.1)
model:SetAttribute("ApproachForkZ", 555.2)
model:SetAttribute("OasisGateX", 221)
model:SetAttribute("OasisGateZ", 565)
model:SetAttribute("WreckX", 246)
model:SetAttribute("WreckZ", 548)

if rbx and fs then
    local path = "assets/world/duenenmeer_v3/oasis_approach/DuneBaron_OasisApproach.rbxm"
    local bytes = rbx.serializeModel({ model })
    local copy = rbx.deserializeModel(bytes)[1]
    assert(#copy:GetChildren() == 3 and #copy.OchreTrail:GetChildren() >= 18)
    for _, p in copy:GetDescendants() do
        if p:IsA("BasePart") then
            assert(p.Anchored and not p.CanQuery and not p.CanCollide)
        end
        assert(not p:IsA("LuaSourceContainer"))
    end
    fs.writeFile(path, bytes)
    print(path, #copy:GetDescendants(), "instances")
else
    model.Parent = destination
    print(modelName, "placed next to the existing oasis approach")
end
