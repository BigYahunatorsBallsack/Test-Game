--!strict
-- Static authoring model for the first black-sand dunes before the caravan gate.
local offline = game == nil
local rbx = if offline then require("@lune/roblox") else nil
local Instance = if rbx then rbx.Instance else Instance
local Vector2 = if rbx then rbx.Vector2 else Vector2
local Vector3 = if rbx then rbx.Vector3 else Vector3
local CFrame = if rbx then rbx.CFrame else CFrame
local Color3 = if rbx then rbx.Color3 else Color3
local Enum = if rbx then rbx.Enum else Enum
local fs = if offline then require("@lune/fs") else nil
local P, V, C, A, rgb = Vector2.new, Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local Y = Vector3.yAxis
local material = Enum.Material
local modelName = "BuriedCaravanReliefV1"
local destination: Instance?
local height: (number, number) -> number

if offline then
    height = require("./RuinsSurface").height
else
    local run = game:GetService("RunService")
    assert(
        run:IsStudio() and not run:IsRunning() and game.PlaceId == 135831532782380,
        "Use Every Last Grain in Studio Edit"
    )
    local world = workspace:FindFirstChild("DuneBaronWorld")
    assert(
        world and world:GetAttribute("RuinsTerrainRevision") == 1,
        "Ruins V1 terrain is required"
    )
    destination = assert(world:FindFirstChild("RuinsArtV1"), "Install the ruins landmarks first")
    assert(not destination:FindFirstChild(modelName), "Caravan relief already installed")
    local filter = RaycastParams.new()
    filter.FilterType, filter.FilterDescendantsInstances, filter.IgnoreWater =
        Enum.RaycastFilterType.Include, { workspace.Terrain }, true
    height = function(x, z)
        return assert(
            workspace:Raycast(V(x, 180, z), V(0, -250, 0), filter),
            "Ruins ground missing"
        ).Position.Y
    end
end

local siteX, siteZ = 1806, 841
local groundPosition = V(siteX, height(siteX, siteZ), siteZ)
local at = CFrame.lookAt(groundPosition, groundPosition + V(-0.88, 0, 0.94))
local face = at * A(math.rad(18), 0, math.rad(-4))
local model = Instance.new("Model")
model.Name, model.WorldPivot = modelName, at
model:SetAttribute("Owner", "DuneBaronCaravanRelief")
model:SetAttribute("ArtVersion", 1)
model:SetAttribute("SiteX", siteX)
model:SetAttribute("SiteZ", siteZ)
local revealFocus = face:PointToWorldSpace(V(0, -1.65, -1.10))
model:SetAttribute("RevealFocusX", revealFocus.X)
model:SetAttribute("RevealFocusZ", revealFocus.Z)

local function group(name: string): Folder
    local f = Instance.new("Folder")
    f.Name, f.Parent = name, model
    return f
end

local foundation, slab, carving, buried, rubble =
    group("Foundation"),
    group("SlantedStela"),
    group("CaravanPanel"),
    group("BuriedFreightMarks"),
    group("BrokenSurround")
local sand, light, cut = rgb(186, 128, 83), rgb(228, 176, 113), rgb(153, 101, 67)
local pale, shadow, bronze = rgb(243, 193, 128), rgb(113, 71, 51), rgb(160, 113, 69)
local teal, deepTeal, glazed = rgb(63, 129, 128), rgb(43, 101, 104), rgb(106, 154, 142)

local function part(
    parent: Instance,
    name: string,
    cf: CFrame,
    size: Vector3,
    color: Color3,
    solid: boolean?,
    shape: Enum.PartType?,
    mat: Enum.Material?
): Part
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
    p.Shape, p.Material = shape or Enum.PartType.Block, mat or material.Sandstone
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, solid == true, solid == true, false
    p.Parent = parent
    return p
end

local function triangle(
    parent: Instance,
    name: string,
    a: Vector3,
    b: Vector3,
    c: Vector3,
    depth: number,
    color: Color3,
    solid: boolean?,
    mat: Enum.Material?
)
    local ab, ac, bc = b - a, c - a, c - b
    if ab.Magnitude > ac.Magnitude and ab.Magnitude > bc.Magnitude then
        a, c = c, a
    elseif ac.Magnitude > bc.Magnitude then
        a, b = b, a
    end
    ab, ac, bc = b - a, c - a, c - b
    local x, z = ac:Cross(ab).Unit, bc.Unit
    local y = z:Cross(x)
    local rise = math.abs(ab:Dot(y))
    for _, corner in { { b, z, x, math.abs(ab:Dot(z)) }, { c, -z, -x, math.abs(ac:Dot(z)) } } do
        if rise <= 0.008 or corner[4] <= 0.008 then
            continue
        end
        part(
            parent,
            name,
            CFrame.fromMatrix((a + corner[1]) / 2, corner[3], y, corner[2]),
            V(depth, rise, corner[4]),
            color,
            solid,
            Enum.PartType.Wedge,
            mat
        )
    end
end

local function polygon(
    parent: Instance,
    name: string,
    points: { Vector2 },
    hub: Vector2,
    z: number,
    depth: number,
    color: Color3,
    solid: boolean?,
    mat: Enum.Material?
)
    local mid = face:PointToWorldSpace(V(hub.X, hub.Y, z))
    for i, a in points do
        local b = points[i % #points + 1]
        triangle(
            parent,
            name,
            mid,
            face:PointToWorldSpace(V(a.X, a.Y, z)),
            face:PointToWorldSpace(V(b.X, b.Y, z)),
            depth,
            color,
            solid,
            mat
        )
    end
end

local function line(
    parent: Instance,
    name: string,
    a: Vector2,
    b: Vector2,
    z: number,
    width: number,
    depth: number,
    color: Color3,
    mat: Enum.Material?
)
    local span = b - a
    local p = (a + b) / 2
    part(
        parent,
        name,
        face * C(p.X, p.Y, z) * A(0, 0, math.atan2(span.Y, span.X)),
        V(span.Magnitude + width * 0.28, width, depth),
        color,
        false,
        nil,
        mat
    )
end

local function disk(
    parent: Instance,
    name: string,
    center: Vector2,
    z: number,
    diameter: number,
    depth: number,
    color: Color3,
    mat: Enum.Material?
)
    part(
        parent,
        name,
        face * C(center.X, center.Y, z) * A(0, math.pi / 2, 0),
        V(depth, diameter, diameter),
        color,
        false,
        Enum.PartType.Cylinder,
        mat
    )
end

local surfaceZ = -0.914
local outline = {
    P(-5.45, -3.55),
    P(5.42, -3.55),
    P(5.38, 6.72),
    P(4.87, 7.72),
    P(2.42, 8.42),
    P(1.40, 9.12),
    P(-2.87, 9.07),
    P(-4.50, 8.47),
    P(-5.62, 7.20),
}
polygon(slab, "Fractured Sandstone Slab", outline, P(0, 2.7), 0, 1.80, sand, true)
local inset = {
    P(-4.84, -2.65),
    P(4.79, -2.65),
    P(4.80, 6.60),
    P(4.40, 7.11),
    P(1.96, 7.80),
    P(1.15, 8.31),
    P(-2.62, 8.30),
    P(-4.10, 7.80),
    P(-4.94, 6.93),
}
polygon(slab, "Recessed Relief Field", inset, P(0, 2.7), surfaceZ, 0.065, sand:Lerp(cut, 0.29))
for i, a in inset do
    local b = inset[i % #inset + 1]
    line(slab, "Weathered Chisel Lip", a, b, -0.965, 0.14, 0.15, light:Lerp(sand, i % 3 * 0.16))
end

-- Chamfered ends of the old lower plinth remain below the black dunes.
for i = -2, 2 do
    part(
        foundation,
        "Buried Stair Foundation",
        at * C(2.43 * i, -3.04 + 0.07 * (i % 2), 0.42),
        V(2.41, 1.44, 5.85),
        cut:Lerp(sand, (i % 3) * 0.15),
        true
    )
end
for i = -1, 1 do
    part(
        foundation,
        "Threshold Slab",
        at * C(3.34 * i, -2.16, -2.38),
        V(3.29, 0.58, 2.48),
        light:Lerp(sand, 0.24 + i * 0.09),
        true
    )
end

-- Hand-cut dromedary silhouette with a raised pack and a bronze-green saddle cloth.
local body = {
    P(-3.55, 3.62),
    P(-3.07, 4.35),
    P(-2.10, 4.50),
    P(-1.57, 5.24),
    P(-0.82, 5.59),
    P(-0.05, 5.39),
    P(0.60, 4.68),
    P(1.53, 4.61),
    P(2.15, 4.21),
    P(2.32, 3.63),
    P(1.79, 3.13),
    P(-1.88, 3.10),
    P(-3.02, 3.22),
}
polygon(carving, "Dromedary Body", body, P(-0.67, 3.96), -1.053, 0.23, light)
polygon(carving, "Arched Neck", {
    P(1.40, 4.16),
    P(1.91, 4.73),
    P(2.44, 6.26),
    P(2.71, 6.57),
    P(3.10, 6.46),
    P(2.97, 5.66),
    P(2.86, 4.70),
    P(2.30, 3.53),
    P(1.93, 3.45),
}, P(2.37, 4.74), -1.061, 0.21, light)
polygon(carving, "Dromedary Head", {
    P(2.48, 6.21),
    P(2.47, 6.63),
    P(2.57, 6.99),
    P(2.73, 7.03),
    P(2.84, 6.68),
    P(3.20, 6.53),
    P(3.94, 6.50),
    P(4.13, 6.18),
    P(3.91, 5.98),
    P(3.24, 6.00),
    P(2.83, 5.92),
}, P(3.05, 6.33), -1.070, 0.24, pale)
disk(carving, "Carved Eye", P(3.00, 6.41), -1.20, 0.115, 0.045, shadow)
line(carving, "Tail Ridge", P(-3.35, 3.90), P(-4.04, 3.26), -1.04, 0.24, 0.18, light)
line(carving, "Tail Tip", P(-4.04, 3.26), P(-4.12, 2.63), -1.04, 0.16, 0.18, light)

for i, leg in
    {
        { P(-2.60, 3.41), P(-2.28, 2.19), P(-2.88, 0.81), 0.37 },
        { P(-1.91, 3.33), P(-1.51, 2.08), P(-0.99, 0.69), 0.31 },
        { P(1.15, 3.35), P(0.94, 2.28), P(1.33, 0.82), 0.34 },
        { P(1.89, 3.35), P(2.07, 2.21), P(2.93, 1.31), 0.32 },
    }
do
    local color = if i % 2 == 1 then light else light:Lerp(sand, 0.3)
    line(carving, "Upper Leg", leg[1], leg[2], -1.046, leg[4], 0.20, color)
    line(carving, "Lower Leg", leg[2], leg[3], -1.046, leg[4] * 0.71, 0.20, color)
    line(carving, "Hoof", leg[3], leg[3] + P(0.37, 0.015), -1.06, 0.21, 0.22, color)
end

polygon(carving, "Turquoise Saddlecloth", {
    P(-1.97, 4.69),
    P(-1.38, 5.03),
    P(-0.15, 5.00),
    P(0.17, 4.52),
    P(-0.02, 3.62),
    P(-1.62, 3.57),
}, P(-0.93, 4.39), -1.207, 0.17, teal, false, material.Marble)
line(
    carving,
    "Saddlecloth Hem",
    P(-1.60, 3.73),
    P(-0.07, 3.76),
    -1.309,
    0.16,
    0.073,
    deepTeal,
    material.Marble
)
part(
    carving,
    "Packed Salt",
    face * C(-0.91, 4.87, -1.345) * A(0, 0, math.rad(-3)),
    V(1.24, 0.58, 0.16),
    pale,
    false,
    nil
)
line(carving, "Pack Strap", P(-1.16, 5.12), P(-1.10, 3.76), -1.458, 0.115, 0.092, bronze)
line(carving, "Pack Strap", P(-0.58, 5.10), P(-0.64, 3.76), -1.458, 0.105, 0.092, bronze)

local sun = P(-3.04, 6.58)
disk(carving, "Sun Seal Border", sun, -1.031, 1.75, 0.19, light)
disk(carving, "Inlaid Sun Seal", sun, -1.156, 1.44, 0.133, teal, material.Marble)
disk(carving, "Faded Sun Center", sun, -1.224, 0.55, 0.085, glazed, material.Marble)
for i = 0, 7 do
    local along = P(math.cos(i * math.pi / 4), math.sin(i * math.pi / 4))
    line(carving, "Sun Ray", sun + along * 0.40, sun + along * 0.61, -1.239, 0.081, 0.046, pale)
end

-- Unmarked crates and a wave band are hidden until the sand around the base is lowered.
line(buried, "Buried Border", P(-4.48, -1.09), P(4.44, -1.09), -1.00, 0.13, 0.15, light)
for i = -2, 2 do
    local x = i * 1.53
    local y = -1.72 + (i % 2) * 0.10
    part(buried, "Freight Stamp Base", face * C(x, y, -0.997), V(0.99, 0.83, 0.13), cut)
    for _, side in { -1, 1 } do
        line(
            buried,
            "Freight Stamp Edge",
            P(x + side * 0.39, y - 0.33),
            P(x + side * 0.39, y + 0.30),
            -1.099,
            0.092,
            0.117,
            pale
        )
    end
    line(
        buried,
        "Freight Stamp Top",
        P(x - 0.39, y + 0.3),
        P(x + 0.39, y + 0.3),
        -1.099,
        0.098,
        0.117,
        pale
    )
    line(
        buried,
        "Glazed Freight Diagonal",
        P(x - 0.29, y - 0.26),
        P(x + 0.28, y + 0.21),
        -1.084,
        0.14,
        0.11,
        if i % 2 == 0 then teal else bronze,
        material.Marble
    )
end
for i = 0, 9 do
    local x = -4.27 + i * 0.84
    line(
        buried,
        "Lower Wave Inlay",
        P(x, -2.44 + i % 2 * 0.12),
        P(x + 0.82, -2.44 + (i + 1) % 2 * 0.12),
        -1.000,
        0.088,
        0.12,
        glazed,
        material.Marble
    )
end

for i, path in
    {
        { P(1.39, 8.28), P(1.21, 7.71), P(0.92, 7.27), P(1.09, 6.96) },
        { P(-4.81, 2.31), P(-4.39, 2.12), P(-4.45, 1.71), P(-4.27, 1.32) },
    }
do
    for j = 2, #path do
        line(
            slab,
            "Eroded Fracture",
            path[j - 1],
            path[j],
            -0.965,
            0.086 - 0.012 * j,
            0.073,
            cut:Lerp(shadow, i * 0.13)
        )
    end
end

for i, node in
    {
        { -6.68, -1.73, 1.52 },
        { -7.86, -1.18, 0.98 },
        { -7.34, -3.32, 0.79 },
        { 6.81, -2.78, 1.70 },
        { 8.04, -3.19, 0.83 },
        { 6.10, 2.33, 1.45 },
        { -5.82, 3.61, 1.09 },
        { 1.05, -5.67, 0.95 },
        { -2.59, -6.41, 0.64 },
    }
do
    local p = at:PointToWorldSpace(V(node[1], 0, node[2]))
    local s = node[3]
    local resting = C(p.X, height(p.X, p.Z) + s * 0.09, p.Z) * A(0.13, i * 0.95, -0.07 * i)
    part(
        rubble,
        "Fractured Border Stone",
        resting,
        V(s * 1.58, s * 0.55, s),
        sand:Lerp(cut, i % 3 * 0.19),
        false,
        if i % 3 == 2 then Enum.PartType.Wedge else nil
    )
    if i == 1 or i == 4 then
        part(
            rubble,
            "Weathered Glaze Fragment",
            resting * C(0.12, s * 0.286, 0),
            V(s * 0.61, 0.09, s * 0.29),
            deepTeal,
            false,
            nil,
            material.Marble
        )
    end
end

if rbx and fs then
    local path = "assets/world/ruinenstadt_v1/karawanenrelief/DuneBaron_CaravanRelief.rbxm"
    local data = rbx.serializeModel({ model })
    local copy = rbx.deserializeModel(data)[1]
    assert(#copy:GetChildren() == 5 and copy:GetAttribute("ArtVersion") == 1)
    for _, p in copy:GetDescendants() do
        assert(not p:IsA("LuaSourceContainer"))
        if p:IsA("BasePart") then
            assert(p.Anchored and not p.CanTouch and p.CanCollide == p.CanQuery)
        end
    end
    fs.writeFile(path, data)
    print(path, #copy:GetDescendants(), "instances with buried relief")
else
    model.Parent = destination
    print(modelName, "placed in RuinsArtV1")
end
