--!strict
-- Authoring only. Furnish the original archive without moving its walls or find model.
local offline = game == nil
local rbx = if offline then require("@lune/roblox") else nil
local Instance = if rbx then rbx.Instance else Instance
local Vector3 = if rbx then rbx.Vector3 else Vector3
local CFrame = if rbx then rbx.CFrame else CFrame
local Color3 = if rbx then rbx.Color3 else Color3
local Enum = if rbx then rbx.Enum else Enum
local fs = if offline then require("@lune/fs") else nil
local V, C, A, rgb = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local mat = Enum.Material
local modelName = "ArchiveInteriorV1"
local floor: CFrame
local destination: Instance?

if offline then
    local y = require("../karawanenrelief/RuinsSurface").height(2090, 931)
    floor = C(2090, y - 5.465, 931) * A(0, -0.32, 0)
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
    local district = assert(world:FindFirstChild("RuinsArtV1"), "Install the ruins landmarks first")
    local halls = assert(district:FindFirstChild("BuriedStructures"), "Buried structures missing")
    destination =
        assert(halls:FindFirstChild("Versandetes Archiv"), "The original archive is required")
    assert(not destination:FindFirstChild(modelName), "Archive interior already installed")
    local center = destination:GetAttribute("Center")
    assert(
        typeof(center) == "Vector3" and destination:GetAttribute("ArtBurial") == true,
        "Unexpected archive metadata"
    )
    local centralSlab: BasePart? = nil
    local closest = math.huge
    for _, candidate in destination:GetChildren() do
        if not (candidate:IsA("BasePart") and candidate.Name == "Buried floor slab") then
            continue
        end
        local p = candidate.CFrame.Position
        local distance = (V(p.X, center.Y, p.Z) - center).Magnitude
        if distance >= closest then
            continue
        end
        closest, centralSlab = distance, candidate
    end
    assert(centralSlab and closest < 0.6, "Central archive floor slab missing")
    floor = centralSlab.CFrame * C(0, centralSlab.Size.Y / 2, 0)
end

local model = Instance.new("Model")
model.Name, model.WorldPivot = modelName, floor
model:SetAttribute("Owner", "DuneBaronArchiveInterior")
model:SetAttribute("ArtVersion", 1)
model:SetAttribute("ArtBurial", true)
model:SetAttribute("InteriorFloorY", floor.Y)

local function group(name: string): Folder
    local folder = Instance.new("Folder")
    folder.Name, folder.Parent = name, model
    return folder
end

local case, bureau, loose =
    group("ClayTabletRegister"), group("ReadingDesk"), group("ScatteredArchiveFragments")
local supported = group("UnearthedMasonry")
local ochre, light, cut = rgb(184, 127, 85), rgb(225, 175, 118), rgb(140, 93, 65)
local wood, edge, endGrain = rgb(118, 79, 52), rgb(83, 55, 42), rgb(162, 112, 69)
local clay, fired, cream = rgb(170, 95, 62), rgb(139, 73, 52), rgb(238, 195, 131)
local teal, jade, bronze = rgb(55, 116, 113), rgb(94, 146, 128), rgb(151, 110, 63)

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

local function verticalDisc(
    parent: Instance,
    name: string,
    cf: CFrame,
    diameter: number,
    h: number,
    color: Color3,
    material: Enum.Material
): Part
    return part(
        parent,
        name,
        cf * A(0, 0, math.pi / 2),
        V(h, diameter, diameter),
        color,
        material,
        false,
        Enum.PartType.Cylinder
    )
end

-- The open face of this register looks across the hall. Deep shelf space is kept dark.
local rack = floor * C(8.11, 0, -1.27) * A(0, math.pi / 2, 0)
part(
    case,
    "Carved Base Plinth",
    rack * C(0, 0.22, 0),
    V(7.84, 0.44, 2.41),
    cut,
    mat.Sandstone,
    true
)
part(
    case,
    "Shadowed Register Back",
    rack * C(0, 1.65, 1.00),
    V(7.36, 2.63, 0.23),
    edge,
    mat.WoodPlanks,
    true
)
for _, x in { -3.66, 3.66 } do
    for row = 1, 3 do
        part(
            case,
            "Stacked Register End",
            rack * C(x + (row % 2) * 0.045, 0.43 + (row - 0.5) * 0.91, 0),
            V(0.61, 0.884, 2.22),
            if row % 2 == 0 then light else ochre,
            mat.Sandstone,
            true
        )
    end
end
for i, y in { 0.51, 1.72, 2.81 } do
    part(
        case,
        "Worn Shelf Board",
        rack * C(0, y, -0.045),
        V(7.20, 0.20, 2.08),
        if i == 3 then ochre else wood,
        if i == 3 then mat.Sandstone else mat.WoodPlanks,
        true
    )
    part(
        case,
        "Glazed Front Strip",
        rack * C(0, y, -1.10),
        V(7.15, 0.10, 0.075),
        if i == 3 then teal else endGrain,
        if i == 3 then mat.Marble else mat.Wood
    )
end
for _, x in { -1.18, 1.21 } do
    for _, y in { 1.105, 2.25 } do
        part(
            case,
            "Register Divider",
            rack * C(x, y, -0.08),
            V(0.15, if y < 2 then 1.01 else 0.87, 2.03),
            wood,
            mat.Wood,
            true
        )
    end
end

-- Deliberately leave several spaces empty. The tablets have waxed edges and impressed seals.
for i, row in
    {
        { -2.80, 0.61, -0.23, 0.86, 0.28 },
        { -2.20, 0.61, -0.34, 0.78, -0.11 },
        { -1.68, 0.61, -0.20, 0.91, 0.16 },
        { -0.47, 0.61, -0.30, 0.75, 0.11 },
        { 0.09, 0.61, -0.37, 0.81, -0.16 },
        { 0.62, 0.61, -0.18, 0.71, 0.22 },
        { 2.01, 0.61, -0.25, 0.90, -0.06 },
        { 2.67, 0.61, -0.14, 0.81, 0.14 },
        { -2.71, 1.82, -0.14, 0.73, 0.13 },
        { -2.09, 1.82, -0.18, 0.77, -0.19 },
        { -0.34, 1.82, -0.30, 0.81, 0.09 },
        { 0.29, 1.82, -0.14, 0.87, 0.25 },
        { 2.25, 1.82, -0.38, 0.74, 0.08 },
        { 2.89, 1.82, -0.18, 0.83, -0.15 },
    }
do
    local h, tilt = row[4], row[5]
    local front = rack * C(row[1], row[2] + h * 0.50, row[3]) * A(0, tilt, 0.05 * math.sin(i))
    local tone = if i % 4 == 0 then teal else clay:Lerp(ochre, (i % 3) * 0.20)
    part(case, "Clay Register Tablet", front, V(0.47, h, 0.18), tone, mat.Sandstone)
    part(
        case,
        "Smoothed Tablet Lip",
        front * C(0, h * 0.34, -0.103),
        V(0.34, 0.085, 0.045),
        tone:Lerp(cream, 0.26),
        mat.Sandstone
    )
    part(
        case,
        "Impressed Tablet Seal",
        front * C(0.05, h * 0.12, -0.098) * A(0, math.pi / 2, 0),
        V(0.04, 0.133, 0.133),
        if i % 4 == 0 then jade else fired,
        mat.Slate,
        false,
        Enum.PartType.Cylinder
    )
    for z = 1, 2 do
        part(
            case,
            "Tablet Incision",
            front * C(-0.02, -h * (0.13 + z * 0.13), -0.10),
            V(0.24 - z * 0.031, 0.043, 0.026),
            tone:Lerp(edge, 0.43),
            mat.Slate
        )
    end
end

-- A small stack and a stoppered clay cylinder sit above the shelves.
for i = 1, 3 do
    part(
        case,
        "Stacked Fragment",
        rack * C(-2.20 + i * 0.047, 2.93 + i * 0.10, -0.14) * A(0, -0.24 + i * 0.17, 0.04),
        V(1.09 - i * 0.09, 0.13, 0.65),
        if i == 2 then teal else ochre,
        mat.Sandstone
    )
end
local vessel = rack * C(2.28, 2.92, 0.24)
verticalDisc(case, "Sealed Clay Tube", vessel * C(0, 0.34, 0), 0.76, 0.69, clay, mat.Sandstone)
verticalDisc(case, "Tube Shoulder", vessel * C(0, 0.73, 0), 0.64, 0.23, light, mat.Sandstone)
verticalDisc(case, "Wrapped Tube Stopper", vessel * C(0, 0.90, 0), 0.50, 0.19, teal, mat.Fabric)

-- The desk is set aside from the central buried find. The inscribed panel slopes up at the back.
local tableAt = floor * C(-6.43, 0, 0.45) * A(0, -0.13, 0)
for _, x in { -1.67, 1.67 } do
    part(
        bureau,
        "Dressed Desk Foot",
        tableAt * C(x, 0.20, 0),
        V(1.21, 0.40, 2.08),
        cut,
        mat.Sandstone,
        true
    )
    part(
        bureau,
        "Stone Desk Support",
        tableAt * C(x, 1.05, 0.10),
        V(0.89, 1.87, 1.81),
        ochre,
        mat.Sandstone,
        true
    )
end
part(
    bureau,
    "Reading Desk Apron",
    tableAt * C(0, 1.87, 0),
    V(4.70, 0.29, 2.54),
    cut,
    mat.Sandstone,
    true
)
part(
    bureau,
    "Smooth Reading Surface",
    tableAt * C(0, 2.12, 0),
    V(4.95, 0.31, 2.69),
    light,
    mat.Sandstone,
    true
)
part(
    bureau,
    "Desk Glaze Trim",
    tableAt * C(-0.12, 2.07, 1.376),
    V(3.35, 0.13, 0.073),
    teal,
    mat.Marble
)

local tablet = tableAt * C(-0.33, 2.51, -0.10) * A(0.18, 0, 0)
part(
    bureau,
    "Sloping Register Support",
    tableAt * C(-0.33, 2.399, -0.77),
    V(2.67, 0.25, 0.40),
    cut,
    mat.Sandstone
)
part(bureau, "Inclined Stone Register", tablet, V(2.92, 0.29, 1.73), cut, mat.Sandstone)
part(
    bureau,
    "Ochre Register Face",
    tablet * C(0, 0.158, 0),
    V(2.74, 0.10, 1.55),
    ochre,
    mat.Sandstone
)
for _, x in { -1.34, 1.34 } do
    part(
        bureau,
        "Glazed Register Side",
        tablet * C(x, 0.235, 0),
        V(0.08, 0.062, 1.52),
        teal,
        mat.Marble
    )
end
for i = -1, 1 do
    local cx = i * 0.78
    verticalDisc(
        bureau,
        "Lacquer Order Seal",
        tablet * C(cx, 0.224, -0.325),
        0.41,
        0.072,
        if i == 0 then teal else fired,
        mat.Marble
    )
    if i == 0 then
        verticalDisc(
            bureau,
            "Worn Inlay Center",
            tablet * C(cx, 0.267, -0.325),
            0.18,
            0.04,
            jade,
            mat.Marble
        )
    end
    for row = 1, 3 do
        part(
            bureau,
            "Chiselled Tally Channel",
            tablet * C(cx - 0.05, 0.211, -0.048 + row * 0.166) * A(0, 0.04 * i, 0),
            V(0.49 - 0.067 * row, 0.022, 0.054),
            cut:Lerp(edge, 0.25),
            mat.Slate
        )
    end
end

local kit = tableAt * C(1.68, 2.275, 0.37) * A(0, -0.27, 0)
verticalDisc(
    bureau,
    "Bronze Stamp Tray",
    kit * C(0, 0.056, 0),
    0.81,
    0.15,
    bronze,
    mat.CorrodedMetal
)
verticalDisc(bureau, "Seal Impression", kit * C(0, 0.153, 0), 0.50, 0.09, clay, mat.Sandstone)
verticalDisc(bureau, "Seal Press Head", kit * C(-0.04, 0.27, 0), 0.37, 0.17, teal, mat.Marble)
verticalDisc(
    bureau,
    "Bronze Seal Grip",
    kit * C(-0.04, 0.45, 0),
    0.17,
    0.32,
    bronze,
    mat.CorrodedMetal
)
part(
    bureau,
    "Small Scribe Stylus",
    kit * C(-0.28, 0.07, -0.95) * A(0, -0.53, 0.07),
    V(0.15, 0.15, 0.90),
    endGrain,
    mat.Wood
)
part(
    bureau,
    "Stylus Nib",
    kit * C(-0.47, 0.075, -1.34) * A(0, -0.53, 0.07),
    V(0.12, 0.13, 0.21),
    bronze,
    mat.CorrodedMetal,
    false,
    Enum.PartType.Wedge
)

for i, row in
    {
        { 6.93, 3.58, 0.82 },
        { 7.43, 4.12, 0.61 },
        { 8.67, 3.54, 0.59 },
        { -8.97, 3.04, 0.82 },
        { -7.87, 3.48, 0.67 },
        { 6.50, -5.73, 0.76 },
        { -8.76, -2.52, 0.79 },
    }
do
    local s = row[3]
    local cf = floor * C(row[1], s * 0.12, row[2]) * A(0.045, i * 0.82, -0.07)
    part(
        loose,
        "Half-Buried Tablet Fragment",
        cf,
        V(s, s * 0.27, s * 0.69),
        if i % 3 == 0 then teal else clay,
        mat.Sandstone,
        false,
        if i % 2 == 0 then Enum.PartType.Wedge else nil
    )
    if i == 1 or i == 4 or i == 7 then
        part(
            loose,
            "Exposed Inlay Edge",
            cf * C(0.08, s * 0.140, 0.05),
            V(s * 0.51, 0.033, 0.085),
            jade,
            mat.Marble
        )
    end
end

-- The original exposed stones stay in place. These buried courses support them after a full cut.
for _, sign in { -1, 1 } do
    for row = 1, 3 do
        local x = sign * (4.28 + (row - 1) * 0.083)
        local y = 1.24 + (row - 0.5) * 1.27
        part(
            supported,
            "Shattered Entrance Jamb",
            floor * C(x, y, 6.27 - (row - 1) * 0.055) * A(0, sign * (0.03 + row * 0.028), 0),
            V(1.48 - row * 0.04, 1.279, 1.55 - row * 0.08),
            ochre:Lerp(cut, row * 0.10),
            mat.Sandstone,
            true
        )
    end
    part(
        supported,
        "Buried Crown Shoulder",
        floor * C(sign * 12.10, 4.77, -5.05) * A(0, sign * 0.038, 0),
        V(2.94, 0.81, 3.32),
        ochre,
        mat.Sandstone,
        true
    )
end

if rbx and fs then
    local path = "assets/world/ruinenstadt_v1/archiv_innenraum/DuneBaron_ArchiveInterior.rbxm"
    local modelBytes = rbx.serializeModel({ model })
    local copy = rbx.deserializeModel(modelBytes)[1]
    assert(#copy:GetChildren() == 4 and copy:GetAttribute("ArtBurial") == true)
    for _, p in copy:GetDescendants() do
        assert(not p:IsA("LuaSourceContainer"))
        if p:IsA("BasePart") then
            assert(p.Anchored and not p.CanTouch and p.CanCollide == p.CanQuery)
        end
    end
    fs.writeFile(path, modelBytes)
    print(path, #copy:GetDescendants(), "instances on the existing archive floor")
else
    model.Parent = destination
    print(modelName, "placed in Versandetes Archiv")
end
