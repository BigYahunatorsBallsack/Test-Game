--!strict
-- Build a hand-authored caravan wreck against the V3 dune surface.
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
local modelName = "LostCaravanWreck"
if offline then
    terrainY = require("../OasisApproachSurface").height
else
    local run = game:GetService("RunService")
    assert(
        run:IsStudio() and not run:IsRunning() and game.PlaceId == 135831532782380,
        "Use Every Last Grain in Studio Edit"
    )
    local world = workspace:FindFirstChild("DuneBaronWorld")
    assert(world and world:GetAttribute("DunesTerrainRevision") == 3, "The V3 terrain is required")
    assert(world:GetAttribute("OasisTerrainRevision") == 1, "The Oase V1 terrain is required")
    destination = assert(world:FindFirstChild("ArtV3"), "Place the existing V3 landmarks first")
    assert(not destination:FindFirstChild(modelName), "This caravan wreck is already installed")
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { workspace.Terrain }
    params.IgnoreWater = true
    terrainY = function(wx, wz)
        local hit = workspace:Raycast(V(wx, 113, wz), V(0, -145, 0), params)
        assert(hit, "Expected solid terrain at the caravan wreck")
        return hit.Position.Y
    end
end

local function landing(x: number, z: number, height: number?): Vector3
    return V(x, terrainY(x, z) + (height or 0), z)
end

local model = Instance.new("Model")
local x, z = 246, 548
model.Name, model.WorldPivot = modelName, C(landing(x, z))
model:SetAttribute("Owner", "DuneBaronLostCaravan")
model:SetAttribute("ArtVersion", 2)
model:SetAttribute("SiteX", x)
model:SetAttribute("SiteZ", z)
local function group(name: string): Folder
    local o = Instance.new("Folder")
    o.Name, o.Parent = name, model
    return o
end
local cart, wreckage, supplies, spoor, clues =
    group("Wagon"),
    group("BrokenAxle"),
    group("ScatteredCargo"),
    group("DisturbedSand"),
    group("Approach")

local paleWood = rgb(174, 123, 80)
local timber = rgb(129, 83, 55)
local darkWood = rgb(92, 63, 49)
local bark = rgb(112, 78, 57)
local fresh = rgb(196, 146, 97)
local iron = rgb(85, 76, 63)
local rim = rgb(129, 114, 88)
local brass = rgb(174, 126, 67)
local sand = rgb(205, 119, 78)
local canvas = rgb(209, 177, 127)
local worn = rgb(182, 149, 104)
local teal = rgb(59, 113, 111)
local faded = rgb(86, 128, 119)
local clay = rgb(176, 100, 65)
local weathered = { timber, paleWood, rgb(145, 99, 65), rgb(154, 102, 68), bark }
local unitX, unitY, unitZ = Vector3.xAxis, Vector3.yAxis, Vector3.zAxis

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
    p.Shape = shape or Enum.PartType.Block
    p.Material = material or Enum.Material.WoodPlanks
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
    p.Parent = parent
    return p
end

local function run(
    parent: Instance,
    name: string,
    a: Vector3,
    b: Vector3,
    width: number,
    thickness: number,
    color: Color3,
    guide: Vector3?,
    kind: Enum.PartType?,
    material: Enum.Material?
): Part
    local axis = (b - a).Unit
    local hint = guide or (if math.abs(axis.Y) > 0.94 then unitZ else unitY)
    local up = (hint - axis * hint:Dot(axis)).Unit
    local cf = CFrame.fromMatrix((a + b) * 0.5, axis, up)
    return part(
        parent,
        name,
        cf,
        V((b - a).Magnitude + 0.024, width, thickness),
        color,
        kind,
        material
    )
end

-- A planar three-point surface becomes a pair of thin native wedges.
local function panel(
    parent: Instance,
    name: string,
    a: Vector3,
    b: Vector3,
    c: Vector3,
    thickness: number,
    color: Color3,
    material: Enum.Material,
    castsShadow: boolean
)
    local ab, ac, bc = b - a, c - a, c - b
    if ab.Magnitude > ac.Magnitude and ab.Magnitude > bc.Magnitude then
        c, a = a, c
    elseif ac.Magnitude > bc.Magnitude then
        a, b = b, a
    end
    ab, ac, bc = b - a, c - a, c - b
    local normal = ac:Cross(ab)
    if normal.Magnitude < 0.008 then
        return
    end
    local axis, xAxis = bc.Unit, normal.Unit
    local up = axis:Cross(xAxis)
    local high = math.abs(ab:Dot(up))
    for _, half in
        { { b, axis, xAxis, math.abs(ab:Dot(axis)) }, { c, -axis, -xAxis, math.abs(ac:Dot(axis)) } }
    do
        if half[4] > 0.007 and high > 0.007 then
            local wedge = Instance.new("WedgePart")
            wedge.Name, wedge.Size = name, V(thickness, high, half[4])
            wedge.CFrame = CFrame.fromMatrix((a + half[1]) / 2, half[3], up, half[2])
            wedge.Color, wedge.Material, wedge.CastShadow = color, material, castsShadow
            wedge.TopSurface, wedge.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
            wedge.Anchored, wedge.CanCollide, wedge.CanTouch, wedge.CanQuery =
                true, false, false, false
            wedge.Parent = parent
        end
    end
end

local function frameOnSand(wx: number, wz: number, yaw: number, height: number?): CFrame
    local riseX = (terrainY(wx + 0.7, wz) - terrainY(wx - 0.7, wz)) / 1.4
    local riseZ = (terrainY(wx, wz + 0.7) - terrainY(wx, wz - 0.7)) / 1.4
    local normal = V(-riseX, 1, -riseZ).Unit
    local right = V(math.cos(yaw), 0, -math.sin(yaw))
    right = (right - normal * right:Dot(normal)).Unit
    return CFrame.fromMatrix(landing(wx, wz, height), right, normal)
end

local function crate(parent: Instance, at: CFrame, scale: number, broken: boolean?)
    local function slat(name: string, x: number, y: number, z: number, size: Vector3, tone: Color3)
        part(parent, name, at * C(x * scale, y * scale, z * scale), size * scale, tone)
    end
    for i = 0, 3 do
        slat(
            "Crate Floor Slat",
            -0.55 + 0.362 * i,
            0.087,
            0.0,
            V(0.331, 0.167, 1.11),
            weathered[(i + 2) % 5 + 1]
        )
    end
    for _, side in { -1, 1 } do
        for i = 0, 2 do
            if broken and i == 2 and side == 1 then
                continue
            end
            slat(
                "Crate End Slat",
                0.035 * i,
                0.226 + i * 0.246,
                side * 0.54,
                V(1.43, 0.229, 0.114),
                weathered[(i + side) % 5 + 1]
            )
        end
        slat("Crate Side Slat", side * 0.695, 0.27, 0.0, V(0.123, 0.36, 1.12), timber)
        if not broken or side == 1 then
            slat("Crate Upper Slat", side * 0.695, 0.591, -0.028, V(0.118, 0.246, 1.09), paleWood)
        end
    end
    for _, side in { -1, 1 } do
        slat("Crate Iron Strap", side * 0.584, 0.328, 0.607, V(0.117, 0.577, 0.044), iron)
    end
end

local function wheel(parent: Instance, at: CFrame, radius: number, damaged: boolean)
    part(parent, "Wheel Hub", at, V(0.48, 0.445, 0.445), timber, Enum.PartType.Cylinder)
    part(
        parent,
        "Hub Collar",
        at * C(0.243, 0, 0),
        V(0.077, 0.347, 0.347),
        brass,
        Enum.PartType.Cylinder,
        Enum.Material.Metal
    )
    part(
        parent,
        "Hub Pin",
        at * C(0.295, 0, 0),
        V(0.07, 0.153, 0.153),
        iron,
        Enum.PartType.Cylinder,
        Enum.Material.Metal
    )
    local function position(a: number, r: number): Vector3
        return at:PointToWorldSpace(V(0, math.cos(a) * r, math.sin(a) * r))
    end
    for i = 0, 17 do
        if damaged and i >= 2 and i <= 6 then
            continue
        end
        local a, b = math.pi * i / 9, math.pi * (i + 1) / 9
        run(
            parent,
            "Wooden Wheel Rim",
            position(a, radius - 0.097),
            position(b, radius - 0.097),
            0.239,
            0.202,
            i % 4 == 0 and paleWood or timber,
            at.RightVector
        )
        run(
            parent,
            "Iron Tyre Band",
            position(a, radius + 0.017),
            position(b, radius + 0.017),
            0.254,
            0.055,
            rim,
            at.RightVector,
            nil,
            Enum.Material.Metal
        )
    end
    for i = 0, 7 do
        local a = (i + 0.27) * math.pi / 4
        local reach = if damaged and (i == 1 or i == 2)
            then radius * (i == 1 and 0.57 or 0.43)
            else radius - 0.133
        run(
            parent,
            "Wheel Spoke",
            position(a, 0.175),
            position(a, reach),
            0.142,
            0.129,
            weathered[i % 5 + 1],
            at.RightVector
        )
    end
end

-- Fit the remaining rear wheel and the broken front timber to the dune.
local resting = { V(-2.39, -1.90, 1.94), V(1.45, -0.319, -3.78) }
local body, contactGap = nil, math.huge
for pitch = -27, -5 do
    for roll = 2, 11 do
        local rotation = CFrame.Angles(0, math.rad(223), 0)
            * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
        local a, b =
            rotation:VectorToWorldSpace(resting[1]), rotation:VectorToWorldSpace(resting[2])
        local ya, yb = terrainY(x + a.X, z + a.Z) - a.Y, terrainY(x + b.X, z + b.Z) - b.Y
        local score = math.abs(ya - yb) + 0.002 * math.abs(pitch + 16) + 0.0013 * math.abs(roll - 7)
        if score < contactGap then
            contactGap = score
            body = C(x, (ya + yb) / 2 - 0.025, z) * rotation
        end
    end
end
assert(body and contactGap < 0.52, "The wagon feet no longer meet the dune")
model:SetAttribute("SupportResidual", contactGap)
local wagon = body
local function timberAt(
    name: string,
    at: CFrame,
    size: Vector3,
    tint: Color3,
    shape: Enum.PartType?
)
    return part(cart, name, wagon * at, size, tint, shape)
end
for _, sign in { -1, 1 } do
    timberAt("Wagon Underframe", C(sign * 1.77, -0.227, 0.10), V(0.38, 0.47, 7.85), bark)
    timberAt("Axle Bearing Block", C(sign * 1.71, -0.421, 1.94), V(0.655, 0.51, 0.73), darkWood)
    timberAt("Raised Side Deck Edge", C(sign * 2.087, 0.131, 0.122), V(0.25, 0.316, 7.55), timber)
end
timberAt(
    "Rear Axle",
    C(-0.18, -0.494, 1.94),
    V(4.79, 0.255, 0.273),
    darkWood,
    Enum.PartType.Cylinder
)
for i = 0, 13 do
    local step = -3.72 + i * 0.55
    local width = if i < 3 then 3.8 + 0.17 * i else 4.21
    timberAt(
        "Weathered Deck Board",
        C(0.033 * math.sin(i * 1.5), -0.014 + 0.022 * math.cos(i * 2.9), step),
        V(width, 0.151, 0.517),
        weathered[i % 5 + 1]
    )
    if i >= 5 then
        for _, u in { -1.85, 1.85 } do
            timberAt("Deck Nail", C(u, 0.069, step + 0.11), V(0.042, 0.026, 0.05), iron)
        end
    end
end
for _, sign in { -1, 1 } do
    for i = 0, 3 do
        if sign == 1 and i <= 1 then
            continue
        end
        local v = -2.56 + i * 1.69
        timberAt(
            "Sideboard Plank",
            C(sign * 2.14, 0.431, v) * CFrame.Angles(0.018 * math.sin(i), 0, sign * 0.028),
            V(0.161, 0.532, 1.65),
            weathered[(i + sign) % 5 + 1]
        )
        timberAt(
            "Sideboard Stake",
            C(sign * 2.226, 0.438, v - 0.57),
            V(0.167, 0.948, 0.168),
            darkWood
        )
    end
end
timberAt(
    "Rear Gate",
    C(0, 0.438, 3.713) * CFrame.Angles(-0.089, 0, 0),
    V(4.27, 0.64, 0.19),
    paleWood
)
timberAt(
    "Fractured Forward Crossbeam",
    C(0.43, -0.23, -3.80) * CFrame.Angles(-0.072, -0.011, 0.088),
    V(3.13, 0.37, 0.31),
    timber
)
for side = -1, 1, 2 do
    local a = wagon:PointToWorldSpace(V(side * 1.127, -0.19, -3.25))
    local b = wagon:PointToWorldSpace(V(side * 0.66, -0.41, if side == -1 then -5.85 else -4.69))
    run(cart, "Broken Drawbar", a, b, 0.219, 0.31, timber)
    local tip = wagon:PointToWorldSpace(V(side * 0.56, -0.39, if side == -1 then -6.1 else -4.94))
    run(cart, "Drawbar Splinter", b, tip, 0.11, 0.14, fresh)
end
wheel(cart, wagon * C(-2.39, -0.494, 1.94), 1.405, false)
timberAt(
    "Exposed Axle Stump",
    C(2.27, -0.494, 1.94),
    V(0.51, 0.32, 0.32),
    bark,
    Enum.PartType.Cylinder
)
timberAt(
    "Bent Axle Strap",
    C(2.422, -0.47, 1.93) * CFrame.Angles(0, 0.17, 0.22),
    V(0.14, 0.37, 0.482),
    iron
)

-- Two bent bows and the torn flank of a once continuous cover.
for _, set in { { 1.67, 1 }, { -0.01, 2 }, { -2.27, 3 } } do
    local v, i = set[1], set[2]
    local arch = {
        V(-2.19, 0.67, v),
        V(-2.08, 1.78, v + 0.051),
        V(-1.06, 2.36, v + 0.064),
        V(0.01, 2.49, v + 0.042),
        V(1.11, 2.28, v - 0.11),
        V(2.17, 1.69, v - 0.18),
        V(2.18, 0.67, v - 0.20),
    }
    for j = 1, #arch - 1 do
        if i == 3 and j >= 3 or i == 2 and j >= 5 then
            continue
        end
        local a, b = wagon:PointToWorldSpace(arch[j]), wagon:PointToWorldSpace(arch[j + 1])
        run(cart, "Bent Canopy Bow", a, b, 0.101, 0.118, j % 3 == 0 and paleWood or timber)
    end
end
local cloth = {
    {
        V(-2.14, 1.43, -2.16),
        V(-1.49, 2.05, -2.11),
        V(-0.71, 2.01, -1.76),
        V(0.22, 1.77, -1.44),
        V(1.05, 1.32, -1.67),
    },
    {
        V(-2.16, 1.41, -0.09),
        V(-1.22, 2.33, -0.01),
        V(0.10, 2.51, 0.02),
        V(1.08, 2.02, 0.08),
        V(2.12, 1.08, -0.18),
    },
    {
        V(-2.14, 1.72, 1.72),
        V(-1.09, 2.37, 1.76),
        V(0.03, 2.47, 1.59),
        V(1.15, 2.23, 1.49),
        V(2.13, 1.60, 1.48),
    },
}
for row = 1, 2 do
    for i = 1, 4 do
        local a, b = cloth[row][i], cloth[row][i + 1]
        local c, d = cloth[row + 1][i], cloth[row + 1][i + 1]
        local color = if i == 2 then faded elseif row == 1 then worn else canvas
        panel(
            cart,
            "Torn Canopy Cloth",
            wagon:PointToWorldSpace(a),
            wagon:PointToWorldSpace(b),
            wagon:PointToWorldSpace(c),
            0.038,
            color,
            Enum.Material.Fabric,
            true
        )
        if not (row == 1 and i == 4) then
            panel(
                cart,
                "Torn Canopy Cloth",
                wagon:PointToWorldSpace(b),
                wagon:PointToWorldSpace(d),
                wagon:PointToWorldSpace(c),
                0.038,
                color,
                Enum.Material.Fabric,
                true
            )
        end
    end
end
crate(cart, wagon * C(-0.80, 0.067, 2.39) * CFrame.Angles(0, 0.212, 0), 0.82, true)
part(
    cart,
    "Tied Caravan Bundle",
    wagon * C(0.74, 0.306, 1.86) * CFrame.Angles(0, 0.28, 0.085),
    V(1.08, 0.55, 0.69),
    teal,
    Enum.PartType.Ball,
    Enum.Material.Fabric
)
for _, u in { -0.31, 0.29 } do
    timberAt(
        "Bundle Strap",
        C(0.74 + u, 0.513, 1.85) * CFrame.Angles(0, 0.28, 0),
        V(0.098, 0.062, 0.589),
        paleWood
    )
end

local lostWheel = frameOnSand(250.42, 545.19, 0.37, 1.0) * CFrame.Angles(0.02, 0, 0.81)
wheel(wreckage, lostWheel, 1.405, true)
local axleAt = frameOnSand(238.51, 551.79, -0.41, 0.138)
part(wreckage, "Abandoned Axle Beam", axleAt * C(0.12, 0.067, 0.19), V(3.97, 0.316, 0.376), bark)
part(
    wreckage,
    "Broken Axle Tongue",
    axleAt * C(-1.12, 0.170, -0.56) * CFrame.Angles(0, -0.55, 0.13),
    V(2.96, 0.29, 0.269),
    timber
)
wheel(wreckage, axleAt * C(1.471, 0.115, -0.187) * CFrame.Angles(0.16, 0, 1.36), 1.16, true)
for i = 1, 6 do
    local a =
        frameOnSand(239.26 + i * 0.86, 552.37 + math.sin(i) * 0.97, 0.37 + i * 0.64, 0.075 * i / 6)
    part(
        wreckage,
        "Splintered Plank",
        a,
        V(0.55 + 0.259 * i, 0.125, 0.18 + 0.037 * i),
        weathered[i % 5 + 1],
        if i % 2 == 0 then Enum.PartType.Wedge else nil
    )
end
crate(supplies, frameOnSand(242.14, 545.85, -0.56), 1.02, true)
crate(supplies, frameOnSand(236.19, 552.94, 0.76), 0.59, true)
local roll = frameOnSand(243.37, 552.49, 0.22, 0.295)
part(
    supplies,
    "Fallen Fabric Roll",
    roll,
    V(1.32, 0.529, 0.517),
    faded,
    Enum.PartType.Cylinder,
    Enum.Material.Fabric
)
for _, u in { -0.42, 0.39 } do
    part(
        supplies,
        "Roll Twine",
        roll * C(u, 0, 0),
        V(0.079, 0.546, 0.542),
        worn,
        Enum.PartType.Cylinder,
        Enum.Material.Fabric
    )
end
for i = 0, 4 do
    local at = frameOnSand(235.22 + i * 1.19, 547.71 + 0.79 * math.sin(i * 0.68), 0.66 * i, 0.063)
    part(
        supplies,
        "Dropped Pottery Shard",
        at,
        V(0.463 + 0.057 * i, 0.135, 0.256),
        if i == 3 then teal else clay,
        Enum.PartType.Wedge,
        Enum.Material.SmoothPlastic
    )
end

-- Low, connected crests bend away from the wagon across the lee side.
local p0, p1, p2, p3 =
    V(248.84, 0, 549.5), V(258.7, 0, 548.83), V(268.1, 0, 539.26), V(284.3, 0, 546.8)
local function center(t: number): Vector3
    local u = 1 - t
    return p0 * u ^ 3 + p1 * (3 * u ^ 2 * t) + p2 * (3 * u * t ^ 2) + p3 * t ^ 3
end
local function ridgePoint(t: number, cross: number, side: number): Vector3
    local p = center(t)
    local tangent = (center(math.min(1, t + 0.002)) - center(math.max(0, t - 0.002))).Unit
    local sideways = V(-tangent.Z, 0, tangent.X) * side
    local envelope = math.sin(math.pi * t) ^ 0.65
    p += sideways * (2.31 + 0.92 * envelope + cross * (0.87 + 0.33 * envelope))
    local hump = math.max(0, 1 - cross ^ 2) ^ 1.55 * envelope
    return landing(p.X, p.Z, -0.052 + hump * (if side == 1 then 0.574 else 0.402))
end
local rails = { -1, -0.36, 0.34, 1 }
for _, sign in { -1, 1 } do
    for i = 0, 10 do
        local t0, t1 = i / 11, (i + 1) / 11
        for j = 1, #rails - 1 do
            local a, b = ridgePoint(t0, rails[j], sign), ridgePoint(t0, rails[j + 1], sign)
            local c, d = ridgePoint(t1, rails[j], sign), ridgePoint(t1, rails[j + 1], sign)
            local color = sand:Lerp(rgb(220, 137, 83), 0.24 + 0.14 * math.cos(i * 0.77 + j))
            panel(
                spoor,
                "Wind-scoured Sand Crest",
                a,
                b,
                c,
                0.022,
                color,
                Enum.Material.Sand,
                false
            )
            panel(
                spoor,
                "Wind-scoured Sand Crest",
                b,
                d,
                c,
                0.022,
                color,
                Enum.Material.Sand,
                false
            )
        end
    end
end

for i, p in { { 231.23, 551.2 }, { 234.28, 552.01 }, { 237.8, 550.13 } } do
    local at = frameOnSand(p[1], p[2], 0.4 + 0.68 * i, 0.046)
    part(
        clues,
        if i == 1 then "Worn Transport Slat" else "Approach Pottery Shard",
        at,
        if i == 1 then V(0.68, 0.109, 0.254) else V(0.346 + i * 0.07, 0.117, 0.303),
        if i == 1 then paleWood elseif i == 2 then clay else faded,
        Enum.PartType.Wedge,
        if i == 1 then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic
    )
end
local reference = part(clues, "WreckFocus", C(landing(x, z)), V(0.11, 0.11, 0.11), teal)
reference.Transparency, reference.CastShadow = 1, false
reference:SetAttribute("SightlineX", 214.1)
reference:SetAttribute("SightlineZ", 555.2)
reference:SetAttribute("OuterTraceX", p3.X)
reference:SetAttribute("OuterTraceZ", p3.Z)

if rbx and fs then
    local path = "assets/world/duenenmeer_v3/caravan_wreck/DuneBaron_CaravanWreck.rbxm"
    local bytes = rbx.serializeModel({ model })
    local rebuilt = rbx.deserializeModel(bytes)[1]
    assert(rebuilt.Name == modelName and #rebuilt.DisturbedSand:GetChildren() > 140)
    for _, p in rebuilt:GetDescendants() do
        if p:IsA("BasePart") then
            assert(p.Anchored and not p.CanQuery and not p.CanCollide)
        end
        assert(not p:IsA("LuaSourceContainer"))
    end
    fs.writeFile(path, bytes)
    print(
        path,
        #rebuilt:GetDescendants(),
        "instances",
        math.round(contactGap * 1000) / 1000,
        "stud support residual"
    )
else
    model.Parent = destination
    print(modelName, "placed in ArtV3")
end
