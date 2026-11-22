--!strict
-- Author the caravan cache against the V3 terrain. Studio usage is Edit-only.
local offline = game == nil
local rbx = if offline then require("@lune/roblox") else nil
local Instance = if rbx then rbx.Instance else Instance
local CFrame = if rbx then rbx.CFrame else CFrame
local Vector3 = if rbx then rbx.Vector3 else Vector3
local Color3 = if rbx then rbx.Color3 else Color3
local Enum = if rbx then rbx.Enum else Enum
local C, V, rgb = CFrame.new, Vector3.new, Color3.fromRGB

local x, z, yaw = 109, 347, math.rad(230)
local cacheName = "BuriedCaravanCache"
local base = C(x, 0, z) * CFrame.Angles(0, yaw, 0)
local terrainY: (number, number) -> number
local destination: Instance?
local fs = if offline then require("@lune/fs") else nil
if offline then
    local source = assert(fs).readFile("assets/world/duenenmeer_v3/BuildDunes.editor.luau")
    local a = assert(source:find("local function smooth(", 1, true))
    local b = assert(source:find("local function makeTileArrays(", 1, true))
    local heightAt = require("@lune/luau").load(source:sub(a, b - 1) .. "\nreturn heightAt")()
    terrainY = function(wx, wz)
        local xv, zv = math.floor((wx - 2) / 4) * 4 + 2, math.floor((wz - 2) / 4) * 4 + 2
        local u, v = (wx - xv) / 4, (wz - zv) / 4
        local a0 = heightAt(xv, zv) * (1 - u) + heightAt(xv + 4, zv) * u
        local a1 = heightAt(xv, zv + 4) * (1 - u) + heightAt(xv + 4, zv + 4) * u
        return a0 * (1 - v) + a1 * v + 2
    end
else
    local run = game:GetService("RunService")
    assert(
        run:IsStudio() and not run:IsRunning() and game.PlaceId == 135831532782380,
        "Use Every Last Grain in Studio Edit"
    )
    local world = workspace:FindFirstChild("DuneBaronWorld")
    assert(world and world:GetAttribute("DunesTerrainRevision") == 3, "The V3 terrain is required")
    destination = assert(world:FindFirstChild("ArtV3"), "Place the existing V3 landmarks first")
    assert(not destination:FindFirstChild(cacheName), "This caravan cache is already installed")
    local terrain = workspace.Terrain
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { terrain }
    terrainY = function(wx, wz)
        local hit = workspace:Raycast(V(wx, 117, wz), V(0, -150, 0), params)
        assert(hit and hit.Material == Enum.Material.Sand, "Expected sand at the caravan cache")
        return hit.Position.Y
    end
end

local function landing(u: number, v: number): (Vector3, number)
    local p = base:PointToWorldSpace(V(u, 0, v))
    return p, terrainY(p.X, p.Z)
end

local minSurface, maxSurface = math.huge, -math.huge
for side = -2, 2 do
    for front = -2, 2 do
        local _, y = landing(side * 2.92, front * 2.58)
        minSurface, maxSurface = math.min(minSurface, y), math.max(maxSurface, y)
    end
end
assert(maxSurface - minSurface < 1.96, "The ground is too uneven for this chamber")
local floorY = maxSurface - 3.27
local courseSeam = floorY + 0.75
local wallTop = math.min(minSurface - 0.52, floorY + 1.97)
assert(wallTop - courseSeam > 0.50)
local chamber = (base - base.Position) + V(x, floorY, z)

local model = Instance.new("Model")
model.Name = cacheName
model.WorldPivot = C(x, floorY, z) * CFrame.Angles(0, yaw, 0)
model:SetAttribute("Owner", "DuneBaronCaravanCache")
model:SetAttribute("ArtVersion", 1)
model:SetAttribute("FloorY", floorY)
model:SetAttribute("SiteX", x)
model:SetAttribute("SiteZ", z)
local function folder(name: string): Folder
    local o = Instance.new("Folder")
    o.Name, o.Parent = name, model
    return o
end
local hints, buried, probes = folder("SurfaceHints"), folder("BuriedStone"), folder("DigProbes")

local deep = rgb(147, 104, 72)
local weathered = rgb(182, 136, 91)
local sandStone = rgb(211, 165, 111)
local cream = rgb(224, 185, 132)
local stoneColors = { weathered, sandStone, sandStone, cream, rgb(203, 151, 100) }
local teal = rgb(63, 117, 114)
local paleTeal = rgb(102, 144, 128)
local clay = rgb(162, 88, 59)
local clayRed = rgb(180, 103, 65)
local coral = rgb(194, 125, 86)
local darkCeramic = rgb(88, 55, 42)
local wood = rgb(119, 86, 62)

local function block(
    group: Instance,
    name: string,
    cf: CFrame,
    size: Vector3,
    tint: Color3,
    shape: Enum.PartType?,
    material: Enum.Material?
): Part
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color = name, size, cf, tint
    p.Shape = shape or Enum.PartType.Block
    p.Material = material or Enum.Material.Sandstone
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
    p.Parent = group
    return p
end

local function stone(
    name: string,
    u: number,
    y: number,
    v: number,
    size: Vector3,
    color: Color3,
    angle: number?
): Part
    return block(buried, name, chamber * C(u, y, v) * CFrame.Angles(0, angle or 0, 0), size, color)
end

-- A single foundation and a staggered floor continue beneath all three wall rows.
local footingBottom, footingTop = minSurface - 4.44, floorY - 0.369
stone(
    "Deep Sandstone Footing",
    0,
    (footingBottom + footingTop) / 2 - floorY,
    -0.06,
    V(10.82, footingTop - footingBottom, 9.55),
    weathered
)
stone("Foundation Slab", 0, -0.195, -0.06, V(11.13, 0.39, 9.83), deep)
for row = 0, 4 do
    for col = 0, 5 do
        local u = -4.25 + 1.705 * col + (if row % 2 == 0 then 0.035 else -0.048)
        local v = -3.58 + 1.66 * row
        local shade = stoneColors[(row * 2 + col * 3) % #stoneColors + 1]
        stone(
            "Worn Floor Slab",
            u,
            0.059 + math.sin(col + row * 2) * 0.014,
            v,
            V(1.63 - 0.062 * math.cos(row + col), 0.125, 1.585),
            shade,
            0.008 * math.sin(col * 3 + row)
        )
    end
end

for tier = 1, 2 do
    local y = if tier == 1 then floorY + 0.375 else (courseSeam + wallTop) / 2
    local height = if tier == 1 then 0.735 else wallTop - courseSeam - 0.021
    local step = if tier == 1 then 1.54 else 1.43
    for side = -1, 1, 2 do
        for i = 1, 5 do
            if tier == 2 and (side == 1 and (i == 2 or i == 3) or side == -1 and i == 4) then
                continue
            end
            local shade = stoneColors[(i * 3 + side + tier) % #stoneColors + 1]
            local turn = (math.sin(i * 5 + side + tier) * 0.012)
            stone(
                "Side Wall Course",
                side * (4.97 + 0.04 * math.sin(i)),
                y - floorY,
                -2.97 + (i - 1) * step + (tier - 1) * 0.24,
                V(1.08 + 0.052 * math.sin(i * 2), height, step - 0.024),
                shade,
                turn
            )
        end
    end
    for i = 0, 5 do
        if tier == 2 and i == 4 then
            continue
        end
        local shade = stoneColors[(i * 3 + tier) % #stoneColors + 1]
        stone(
            "Back Wall Course",
            -4.23 + i * 1.682 + (tier - 1) * 0.162,
            y - floorY,
            -4.12,
            V(1.64, height, 1.11 + 0.045 * math.cos(i)),
            shade,
            0.008 * math.cos(i + tier)
        )
    end
end

-- Two threshold stones and a low descent into the room.
for i, row in { { 0.24, 2.52, 3.98 }, { 0.53, 3.54, 3.78 }, { 0.84, 4.52, 3.58 } } do
    local high, v, width = row[1], row[2], row[3]
    stone(
        "Entrance Step",
        0.022 * math.sin(i),
        high / 2,
        v,
        V(width, high, 1.13),
        stoneColors[2 + i % 3]
    )
    stone("Step Wear Strip", 0.01, high + 0.009, v - 0.36, V(width - 0.20, 0.026, 0.198), weathered)
end
for _, sign in { -1, 1 } do
    stone("Entrance Wing", sign * 3.67, 0.432, 3.93, V(2.57, 0.82, 1.08), sandStone, sign * 0.014)
    stone("Broken Door Jamb", sign * 2.46, 1.06, 3.94, V(1.15, 0.63, 1.12), cream, sign * 0.019)
    stone("Jamb Glaze", sign * 2.48, 1.153, 4.504, V(0.526, 0.236, 0.043), teal)
end

-- Original turquoise seal, set into the floor between worn inlay strips.
local sealX, sealZ = -0.34, -0.72
local sealY = 0.154
local upright = CFrame.Angles(0, 0, math.pi / 2)
local function disc(
    name: string,
    u: number,
    y: number,
    v: number,
    depth: number,
    diameter: number,
    color: Color3
)
    return block(
        buried,
        name,
        chamber * C(u, y, v) * upright,
        V(depth, diameter, diameter),
        color,
        Enum.PartType.Cylinder,
        Enum.Material.Slate
    )
end
disc("Seal Bed", sealX, sealY, sealZ, 0.068, 2.59, deep)
disc("Verdigris Seal Ring", sealX, sealY + 0.035, sealZ, 0.068, 2.28, teal)
disc("Worn Inner Seal", sealX, sealY + 0.075, sealZ, 0.054, 1.64, paleTeal)
stone("Crossed Seal Diamond", sealX, sealY + 0.115, sealZ, V(0.76, 0.047, 0.76), cream, math.pi / 4)
for i = 0, 7 do
    local angle = math.pi * i / 4
    stone(
        "Seal Notch Inlay",
        sealX + math.cos(angle) * 0.975,
        sealY + 0.078,
        sealZ + math.sin(angle) * 0.975,
        V(0.125, 0.042, 0.193),
        cream,
        -angle
    )
end
for side = -1, 1, 2 do
    for i = -2, 2 do
        if side == 1 and i == 1 then
            continue
        end
        stone(
            "Glazed Floor Border",
            side * 2.37,
            0.168,
            -1.02 + i * 0.60,
            V(0.35, 0.059, 0.35),
            if (i + side) % 3 == 0 then cream else teal,
            math.pi / 4
        )
    end
end

-- Rear storage shelves have open fronts. Ceramic rims are modeled as rings.
stone("Rear Shelf Base", -2.88, 0.22, -3.01, V(3.21, 0.43, 1.48), weathered)
stone("Rear Shelf Lip", -2.88, 0.461, -2.30, V(3.18, 0.082, 0.118), cream)
stone("Rear Dividing Pier", -1.26, 0.622, -3.19, V(0.31, 1.19, 1.31), weathered)
stone("Right Storage Step", 3.55, 0.227, -2.96, V(2.02, 0.446, 1.41), weathered)

local function jar(at: CFrame, size: number, tint: Color3, scuffed: boolean)
    local function ceramic(name, cf, dim, col, kind)
        return block(buried, name, at * cf, dim * size, col, kind, Enum.Material.SmoothPlastic)
    end
    ceramic(
        "Storage Jar Foot",
        C(0, 0.099 * size, 0) * upright,
        V(0.176, 0.65, 0.65),
        darkCeramic,
        Enum.PartType.Cylinder
    )
    ceramic(
        "Storage Jar Belly",
        C(0, 0.413 * size, 0),
        V(0.89, 0.723, 0.89),
        tint,
        Enum.PartType.Ball
    )
    ceramic(
        "Storage Jar Shoulder",
        C(0, 0.680 * size, 0),
        V(0.735, 0.314, 0.735),
        tint,
        Enum.PartType.Ball
    )
    ceramic(
        "Storage Jar Neck",
        C(0, 0.812 * size, 0) * upright,
        V(0.133, 0.489, 0.489),
        tint,
        Enum.PartType.Cylinder
    )
    ceramic(
        "Jar Hollow",
        C(0, 0.895 * size, 0) * upright,
        V(0.032, 0.435, 0.435),
        darkCeramic,
        Enum.PartType.Cylinder
    )
    for i = 0, 13 do
        if scuffed and (i == 3 or i == 4 or i == 5) then
            continue
        end
        local a = i * 2 * math.pi / 14
        ceramic(
            "Jar Rolled Rim",
            C(math.cos(a) * 0.246 * size, 0.939 * size, math.sin(a) * 0.246 * size)
                * CFrame.Angles(0, -a, 0),
            V(0.071, 0.098, 0.131),
            coral,
            Enum.PartType.Block
        )
    end
    if not scuffed then
        ceramic(
            "Glazed Jar Band",
            C(0, 0.690 * size, 0) * upright,
            V(0.075, 0.735, 0.735),
            teal,
            Enum.PartType.Cylinder
        )
    end
end
jar(chamber * C(-3.92, 0.441, -3.04) * CFrame.Angles(0, 0.06, 0.008), 1.01, clayRed, false)
jar(chamber * C(-2.87, 0.446, -2.61) * CFrame.Angles(0, -0.27, -0.029), 0.67, clay, true)
jar(chamber * C(3.98, 0.447, -3.16) * CFrame.Angles(0, 0.55, 0.031), 0.94, clayRed, true)
jar(chamber * C(2.94, 0.446, -2.67) * CFrame.Angles(0, 1.83, -0.021), 0.66, clay, false)

local crate = chamber * C(-3.52, 0.126, 1.23) * CFrame.Angles(0, -0.157, 0)
local function plank(name: string, cf: CFrame, dim: Vector3, col: Color3)
    block(buried, name, crate * cf, dim, col, nil, Enum.Material.WoodPlanks)
end
plank("Weathered Crate Bottom", C(0, 0.093, 0), V(1.54, 0.154, 1.16), wood)
for _, side in { -1, 1 } do
    plank(
        "Broken Crate Side",
        C(side * 0.70, 0.322, 0) * CFrame.Angles(0, 0, side * 0.074),
        V(0.143, 0.51, 1.13),
        wood
    )
    plank("Crate Corner Strap", C(side * 0.648, 0.291, 0.502), V(0.126, 0.527, 0.134), deep)
end
plank(
    "Crate Rear Slat",
    C(-0.11, 0.402, -0.49) * CFrame.Angles(0, 0, -0.09),
    V(1.29, 0.21, 0.115),
    wood
)
plank(
    "Crate Broken Slat",
    C(-0.02, 0.13, 0.781) * CFrame.Angles(0.19, -0.37, 0.02),
    V(0.99, 0.137, 0.216),
    wood
)
for i, row in
    { { 2.94, 1.76, 0.39 }, { 3.47, 1.63, 0.32 }, { 3.26, 2.22, 0.47 }, { -1.6, -2.9, 0.37 } }
do
    stone(
        "Fallen Clay Fragment",
        row[1],
        0.154,
        row[2],
        V(row[3], 0.134, 0.31),
        if i % 2 == 0 then coral else clay,
        0.48 * i
    )
end

-- Low, separated hints sit on the current terrain, outside the two dig points.
local function clueFrame(u: number, v: number): CFrame
    local p, y = landing(u, v)
    return C(p.X, y, p.Z) * CFrame.Angles(0, yaw, 0)
end
local function pillarBelow(
    cap: CFrame,
    name: string,
    bottom: number,
    capBottom: number,
    width: number,
    length: number
)
    local rise = (capBottom - bottom) / 4
    for row = 0, 3 do
        local y = bottom + rise * (row + 0.5)
        local at = (cap - cap.Position) + V(cap.X, y, cap.Z)
        block(
            hints,
            name,
            at * C(0.034 * math.sin(row + 0.5), 0, -0.047) * CFrame.Angles(0, 0.027 * row, 0),
            V(width - row * 0.104, rise + 0.031, length - row * 0.043),
            if row % 3 == 2 then cream else sandStone
        )
    end
end
local lip = clueFrame(-4.65, 3.79)
pillarBelow(lip, "Buried Jamb Courses", floorY - 0.15, lip.Y - 0.296, 1.68, 0.958)
block(
    hints,
    "Exposed Door Jamb",
    lip * C(0, -0.073, 0) * CFrame.Angles(0, 0.117, -0.038),
    V(1.98, 0.623, 1.03),
    sandStone,
    nil
)
block(
    hints,
    "Chipped Glazed Edge",
    lip * C(0.27, 0.071, 0.50) * CFrame.Angles(0, 0.092, 0.03),
    V(0.91, 0.219, 0.122),
    teal,
    Enum.PartType.Wedge
)
block(
    hints,
    "Jamb Corner Spall",
    lip * C(-0.729, 0.209, -0.118) * CFrame.Angles(0, -0.13, -0.04),
    V(0.547, 0.24, 0.538),
    cream,
    Enum.PartType.Wedge
)
local rim = clueFrame(4.72, -1.69)
pillarBelow(rim, "Buried Side Pier Courses", floorY - 0.15, rim.Y - 0.489, 1.32, 1.12)
block(
    hints,
    "Weathered Upper Stone",
    rim * C(0, -0.235, 0) * CFrame.Angles(0, -0.22, 0.065),
    V(1.45, 0.672, 1.30),
    weathered,
    nil
)
for i, offset in { -0.41, 0.18, 0.64 } do
    block(
        hints,
        "Surface Pottery Shard",
        lip
            * C(offset, 0.259 - 0.020 * offset, 0.09 + 0.104 * math.cos(i * 2))
            * CFrame.Angles(0, i * 0.65, 0.05),
        V(0.263 + i * 0.031, 0.099, 0.238),
        if i == 2 then teal else coral,
        Enum.PartType.Wedge,
        Enum.Material.SmoothPlastic
    )
end
for i, q in { { 96.78, 340.1 }, { 98.11, 343.65 } } do
    local y = terrainY(q[1], q[2])
    local at = C(q[1], y, q[2]) * CFrame.Angles(0, 0.494 * i, 0.027)
    block(
        hints,
        "Broken Approach Stone",
        at * C(0, -0.124, 0),
        V(1.66 - i * 0.19, 0.384, 0.82),
        if i == 1 then cream else weathered,
        Enum.PartType.Wedge
    )
    if i == 2 then
        block(
            hints,
            "Approach Tile Shard",
            at * C(0.44, -0.01, -0.36),
            V(0.48, 0.127, 0.352),
            paleTeal,
            Enum.PartType.Wedge,
            Enum.Material.Slate
        )
    end
end

local function probe(name: string, u: number, v: number, top: number): BasePart
    local where, y = landing(u, v)
    local marker = block(probes, name, C(where.X, y, where.Z), V(0.12, 0.12, 0.12), teal)
    marker.Transparency, marker.CastShadow = 1, false
    marker:SetAttribute("ProbeX", where.X)
    marker:SetAttribute("ProbeZ", where.Z)
    marker:SetAttribute("SurfaceY", y)
    marker:SetAttribute("HiddenTopY", top)
    assert(y - top > 0.64 and y - top < 3.76)
    return marker
end
local main = probe("Vorratssiegel", sealX, sealZ, floorY + sealY + 0.139)
probe("Schwelle", 0, 3.95, floorY + 0.89)
probe("Vorratsnische", 3.77, -2.94, floorY + 1.32)
for _, name in { "ProbeX", "ProbeZ", "SurfaceY", "HiddenTopY" } do
    model:SetAttribute(name, main:GetAttribute(name))
end

-- Sample the roofline of the actual stone, once before saving and once in Edit.
local minCover = math.huge
for _, p in buried:GetChildren() do
    for _, dx in { -1, 0, 1 } do
        for _, dz in { -1, 0, 1 } do
            local top =
                p.CFrame:PointToWorldSpace(V(dx * p.Size.X / 2, p.Size.Y / 2, dz * p.Size.Z / 2))
            minCover = math.min(minCover, terrainY(top.X, top.Z) - top.Y)
        end
    end
end
assert(minCover > 0.27, string.format("Buried stone shows above the terrain (%.2f)", minCover))
model:SetAttribute("MinimumCoverStuds", minCover)
if rbx and fs then
    local path = "assets/world/duenenmeer_v3/caravan_cache/DuneBaron_BuriedCaravanCache.rbxm"
    local bytes = rbx.serializeModel({ model })
    local check = rbx.deserializeModel(bytes)[1]
    assert(check.Name == cacheName and #check.DigProbes:GetChildren() == 3)
    for _, p in check:GetDescendants() do
        if p:IsA("BasePart") then
            assert(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch)
        end
    end
    fs.writeFile(path, bytes)
    print(
        path,
        #buried:GetChildren(),
        "buried pieces",
        string.format("%.2f studs minimum cover", minCover)
    )
else
    model.Parent = destination
    print(cacheName, "placed in ArtV3; route and terrain retained")
end
