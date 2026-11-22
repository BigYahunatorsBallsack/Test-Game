--!strict
-- Authoring only. Add a ruined lookout behind the standing ridge columns.
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
local mat = Enum.Material
local name = "WatchridgeLookoutV1"
local destination: Instance?
local height: (number, number) -> number

if offline then
    height = require("../karawanenrelief/RuinsSurface").height
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
    assert(not destination:FindFirstChild(name), "The ridge lookout is already installed")
    local ray = RaycastParams.new()
    ray.FilterType, ray.FilterDescendantsInstances, ray.IgnoreWater =
        Enum.RaycastFilterType.Include, { workspace.Terrain }, true
    height = function(x, z)
        return assert(workspace:Raycast(V(x, 180, z), V(0, -250, 0), ray), "Ridge ground missing").Position.Y
    end
end

local x, z = 2363, 849
local origin = V(x, height(x, z), z)
local at = CFrame.lookAt(origin, origin + V(-0.94, 0, 0.34))
local model = Instance.new("Model")
model.Name, model.WorldPivot = name, at
model:SetAttribute("Owner", "DuneBaronWatchridge")
model:SetAttribute("ArtVersion", 1)
model:SetAttribute("SiteX", x)
model:SetAttribute("SiteZ", z)

local function group(label: string): Folder
    local f = Instance.new("Folder")
    f.Name, f.Parent = label, model
    return f
end

local access, masonry, mosaic, bowl, remnants =
    group("RidgeSteps"),
    group("RuinRing"),
    group("CompassMosaic"),
    group("SignalBowl"),
    group("BrokenBanners")
local stone, light, cut = rgb(184, 127, 86), rgb(225, 175, 117), rgb(139, 94, 71)
local dust, red, mortar = rgb(205, 151, 101), rgb(166, 100, 64), rgb(108, 72, 55)
local teal, jade, bronze = rgb(57, 118, 114), rgb(87, 144, 130), rgb(124, 92, 63)
local darkMetal, ash = rgb(67, 55, 53), rgb(72, 60, 59)

local function part(
    parent: Instance,
    label: string,
    cf: CFrame,
    size: Vector3,
    color: Color3,
    solid: boolean?,
    shape: Enum.PartType?,
    material: Enum.Material?
): Part
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color, p.Material =
        label, size, cf, color, material or mat.Sandstone
    p.Shape = shape or Enum.PartType.Block
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, solid == true, solid == true, false
    p.Parent = parent
    return p
end

local function disc(
    parent: Instance,
    label: string,
    center: CFrame,
    diameter: number,
    deep: number,
    color: Color3,
    solid: boolean?,
    material: Enum.Material?
): Part
    return part(
        parent,
        label,
        center * A(0, 0, math.pi / 2),
        V(deep, diameter, diameter),
        color,
        solid,
        Enum.PartType.Cylinder,
        material
    )
end

local function yAt(localX: number, localZ: number): number
    local p = at:PointToWorldSpace(V(localX, 0, localZ))
    return height(p.X, p.Z) - origin.Y
end

local radius, stackSides = 9.40, 12
local deckY = math.max(0.75, yAt(0, 0) + 0.40)
for i = 0, 15 do
    local theta = i * math.pi / 8
    deckY = math.max(deckY, yAt(radius * math.sin(theta), radius * math.cos(theta)) + 0.36)
end
model:SetAttribute("DeckY", origin.Y + deckY)
disc(masonry, "Buried Round Foundation", at * C(0, deckY - 2.37, 0), 19.02, 4.16, cut, true)
disc(masonry, "Dressed Outer Cornice", at * C(0, deckY - 0.34, 0), 19.04, 0.49, dust, true)
disc(masonry, "Worn Pavement", at * C(0, deckY - 0.127, 0), radius * 2, 0.254, stone, true)

-- Lower the two courses surrounding the city-facing entrance and leave gaps in the back wall.
local heights = { 4, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 2 }
local wallRadius = 8.67
local course = 1.24
for i = 0, stackSides - 1 do
    local whole = heights[i + 1]
    if whole == 0 then
        continue
    end
    local theta = i * math.pi * 2 / stackSides
    local nearEntry = i == 5 or i == 7
    local wall = at * A(0, theta, 0) * C(0, deckY, wallRadius)
    local wide = if nearEntry then 3.40 else 4.60
    for row = 1, whole do
        local proportion = 0.50 + (if (row + i) % 2 == 0 then 0.14 else -0.14)
        local first = wide * proportion
        local second = wide - first
        local y = course * (row - 0.5)
        local battered = (row - 1) * 0.098
        local c = stone:Lerp(if (i + row) % 3 == 0 then cut else light, 0.11 + 0.10 * (i % 3))
        if row == whole and whole >= 3 and i % 2 == 1 then
            part(
                masonry,
                "Broken Upper Course",
                wall * C(-wide / 2 + first / 2, y - 0.09, -battered) * A(0, 0.048, 0.084),
                V(first - 0.04, course * 0.88, 1.53),
                c,
                true
            )
        else
            part(
                masonry,
                "Split Sandstone Course",
                wall * C(-wide / 2 + first / 2, y, -battered),
                V(first - 0.045, course - 0.025, 1.79),
                c,
                true
            )
            part(
                masonry,
                "Split Sandstone Course",
                wall * C(wide / 2 - second / 2, y, -battered),
                V(second - 0.045, course - 0.032, 1.79),
                c:Lerp(dust, 0.18),
                true
            )
        end
        if row == 2 and whole >= 4 then
            part(
                masonry,
                "Traces of Glazed Band",
                wall * C(-0.23 + i * 0.045, y, 0.88 - battered),
                V(wide * 0.60, 0.22, 0.13),
                teal,
                false,
                nil,
                mat.Slate
            )
        end
    end
    if whole < 3 then
        part(
            masonry,
            "Chipped Low Coping",
            wall * C(0.02, whole * course + 0.105, 0) * A(0, 0.06, -0.015),
            V(wide + 0.11, 0.31, 1.96),
            light,
            true
        )
    end
end

-- The buried treads reach the disc without a final lip and are anchored in the irregular slope.
local count, tread, topZ = 8, 0.91, -8.97
local entry = topZ - tread * count
local startY = math.min(yAt(-2.01, entry), yAt(0, entry), yAt(2.01, entry))
model:SetAttribute("ApproachRise", deckY - startY)
for i = 1, count do
    local z = entry + (i - 0.5) * tread
    local y = startY + (deckY - 0.045 - startY) * i / count
    local low = math.min(yAt(-2.11, z), yAt(0, z), yAt(2.11, z)) - 0.66
    local h = math.max(0.27, y - low)
    part(
        access,
        "Rounded Ridge Stair",
        at * C(0, y - h / 2, z),
        V(4.78 + (count - i) * 0.105, h, tread + 0.035),
        if i % 3 == 0 then light else dust,
        true
    )
end

local footprints = {
    { 2345.8, 875.0 },
    { 2346.1, 871.2 },
    { 2346.4, 867.9 },
    { 2346.8, 864.5 },
    { 2347.8, 861.5 },
    { 2348.8, 858.0 },
}
for i, p in footprints do
    local center = C(p[1], height(p[1], p[2]) - 0.055, p[2])
        * A(0.05, 0.28 + i * 0.31, 0.12 * math.sin(i))
    part(
        access,
        "Half-Covered Approach Stone",
        center,
        V(2.03 + 0.31 * math.sin(i * 3), 0.34, 1.24),
        stone:Lerp(cut, 0.33),
        false
    )
end

-- Mosaics and directional inlays lie on the walkable pavement.
disc(mosaic, "Mosaic Stone Rim", at * C(0, deckY + 0.023, -1.02), 7.30, 0.048, mortar)
disc(mosaic, "Polished Inset Field", at * C(0, deckY + 0.038, -1.02), 6.84, 0.065, light)
disc(
    mosaic,
    "Inset Copper Axis",
    at * C(0, deckY + 0.081, -1.02),
    1.18,
    0.087,
    bronze,
    false,
    mat.CorrodedMetal
)
disc(mosaic, "Turquoise Pin", at * C(0, deckY + 0.133, -1.02), 0.52, 0.065, jade, false, mat.Marble)

local function tile(label: string, a: Vector2, b: Vector2, c: Vector2, y: number, color: Color3)
    local p, q, r =
        at:PointToWorldSpace(V(a.X, y, a.Y)),
        at:PointToWorldSpace(V(b.X, y, b.Y)),
        at:PointToWorldSpace(V(c.X, y, c.Y))
    local ab, ac, bc = q - p, r - p, r - q
    if ab.Magnitude > ac.Magnitude and ab.Magnitude > bc.Magnitude then
        p, r = r, p
    elseif ac.Magnitude > bc.Magnitude then
        p, q = q, p
    end
    ab, ac, bc = q - p, r - p, r - q
    local axis, x = bc.Unit, ac:Cross(ab).Unit
    local y = axis:Cross(x)
    local h = math.abs(ab:Dot(y))
    for _, corner in
        { { q, axis, x, math.abs(ab:Dot(axis)) }, { r, -axis, -x, math.abs(ac:Dot(axis)) } }
    do
        if h <= 0.008 or corner[4] <= 0.008 then
            continue
        end
        part(
            mosaic,
            label,
            CFrame.fromMatrix((p + corner[1]) / 2, corner[3], y, corner[2]),
            V(0.045, h, corner[4]),
            color,
            false,
            Enum.PartType.Wedge,
            mat.Slate
        )
    end
end

local center = P(0, -1.02)
local mosaicOrigin = at:PointToWorldSpace(V(center.X, deckY, center.Y))
local templeBearing = at:VectorToObjectSpace(V(2262 - mosaicOrigin.X, 0, 849 - mosaicOrigin.Z))
local templeAngle = math.atan2(templeBearing.Z, templeBearing.X)
for i = 0, 7 do
    local theta = templeAngle + i * math.pi / 4
    local axis = P(math.cos(theta), math.sin(theta))
    local side = P(-axis.Y, axis.X)
    local reach = if i == 0 then 3.14 elseif i % 2 == 0 then 2.87 else 1.93
    local wing = if i % 2 == 0 then 0.35 else 0.21
    local root = center + axis * 0.48
    local shoulder = center + axis * 0.95
    local tip = center + axis * reach
    tile(
        if i == 0 then "Temple Bearing" else "Compass Point",
        root,
        shoulder + side * wing,
        tip,
        deckY + 0.105,
        if i % 2 == 0 then teal else bronze
    )
    tile(
        if i == 0 then "Temple Bearing Shaded Half" else "Compass Point Shaded Half",
        tip,
        shoulder - side * wing,
        root,
        deckY + 0.105,
        if i % 2 == 0 then jade else mortar
    )
end

-- The old signal fire is cold. Its rim and ash bed are separate pieces for visual depth.
local bx, bz = 0.23, 4.44
disc(bowl, "Signal Pedestal Plinth", at * C(bx, deckY + 0.20, bz), 3.39, 0.40, cut, true)
disc(bowl, "Dressed Brazier Pedestal", at * C(bx, deckY + 1.02, bz), 2.52, 1.32, dust, true)
disc(
    bowl,
    "Copper Brazier Base",
    at * C(bx, deckY + 1.72, bz),
    2.78,
    0.34,
    darkMetal,
    true,
    mat.CorrodedMetal
)
disc(bowl, "Ash And Stone Bed", at * C(bx, deckY + 1.92, bz), 2.78, 0.22, ash, false, mat.Slate)
for i = 0, 11 do
    local theta = i * math.pi / 6
    local radial = at * C(bx, deckY + 2.13, bz) * A(0, theta, 0)
    part(
        bowl,
        "Canted Copper Bowl Stave",
        radial * C(0, 0, 1.55) * A(0.44, 0, 0),
        V(0.87, 0.70, 0.16),
        bronze:Lerp(darkMetal, i % 3 * 0.20),
        false,
        nil,
        mat.CorrodedMetal
    )
    part(
        bowl,
        "Weathered Bronze Rim",
        radial * C(0, 0.35, 1.72),
        V(0.94, 0.16, 0.22),
        if i % 3 == 0 then teal else bronze,
        false,
        nil,
        mat.CorrodedMetal
    )
end
for i = 1, 7 do
    local theta = i * 2.399963
    part(
        bowl,
        "Cold Clinker",
        at
            * C(bx + math.sin(theta) * 0.91, deckY + 2.08, bz + math.cos(theta) * 0.96)
            * A(0.14, theta, -0.14),
        V(0.43, 0.25, 0.29),
        if i % 2 == 0 then darkMetal else ash,
        false,
        Enum.PartType.Wedge,
        mat.Slate
    )
end

-- A fallen lintel and two broken ceremonial banners frame the side of the ruin.
for i, p in
    {
        { -6.73, 2.31, 2.31 },
        { -7.46, 1.07, 0.84 },
        { 6.10, -2.29, 1.47 },
        { 6.49, -3.72, 0.75 },
        { -1.5, 7.18, 1.18 },
    }
do
    local s = p[3]
    local cf = at * C(p[1], deckY + s * 0.21, p[2]) * A(0.12, i * 0.93, 0.10)
    part(
        remnants,
        "Broken Masonry",
        cf,
        V(s * 1.55, s * 0.40, s * 0.79),
        stone:Lerp(red, i % 3 * 0.16),
        false,
        if i % 2 == 0 then Enum.PartType.Wedge else nil
    )
end
for _, sign in { -1, 1 } do
    local cf = at * C(sign * 3.08, deckY, -7.06) * A(0, -0.08 * sign, 0)
    part(remnants, "Carved Standard Foot", cf * C(0, 0.22, 0), V(1.69, 0.46, 1.34), cut, true)
    local top = if sign < 0 then 2.96 else 1.02
    part(
        remnants,
        "Fractured Banner Stone",
        cf * C(0, top * 0.50, 0) * A(0.02, 0, 0.07 * sign),
        V(1.03, top, 0.77),
        light,
        true
    )
    part(
        remnants,
        "Weathered Standard Inlay",
        cf * C(0.018, top * 0.55, -0.40),
        V(0.55, top * 0.33, 0.15),
        teal,
        false,
        nil,
        mat.Marble
    )
end

if rbx and fs then
    local path = "assets/world/ruinenstadt_v1/wachtgrat/DuneBaron_WatchridgeLookout.rbxm"
    local bytes = rbx.serializeModel({ model })
    local copy = rbx.deserializeModel(bytes)[1]
    assert(#copy:GetChildren() == 5 and copy:GetAttribute("ArtVersion") == 1)
    for _, p in copy:GetDescendants() do
        assert(not p:IsA("LuaSourceContainer"))
        if p:IsA("BasePart") then
            assert(p.Anchored and not p.CanTouch and p.CanCollide == p.CanQuery)
        end
    end
    fs.writeFile(path, bytes)
    print(path, #copy:GetDescendants(), "instances on the ridge")
else
    model.Parent = destination
    print(name, "placed in RuinsArtV1")
end
