--!strict
-- Authoring only. Add a survey platform outside the Colossus equipment routes.
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
local Y = Vector3.yAxis
local name = "ColossusSurveyOverlookV1"
local siteX, siteZ = -288, -78
local destination: Instance?
local head: Vector3
local height: (number, number) -> number

if offline then
    height = require("./ColossusSurface").height
    head = V(-472.9, 35.35, -24)
else
    local run = game:GetService("RunService")
    assert(
        run:IsStudio() and not run:IsRunning() and game.PlaceId == 135831532782380,
        "Use Every Last Grain in Studio Edit"
    )
    local world = workspace:FindFirstChild("DuneBaronWorld")
    assert(
        world and world:GetAttribute("ColossusTerrainRevision") == 1,
        "Colossus V1 terrain is required"
    )
    local art =
        assert(world:FindFirstChild("ColossusArtV1"), "Install the Colossus landmarks first")
    destination = assert(art:FindFirstChild("Grabungsstätte"), "Colossus excavation art missing")
    assert(not destination:FindFirstChild(name), "The survey overlook is already installed")
    local statue = assert(art:FindFirstChild("Koloss"), "Colossus statue missing")
    local neck = assert(statue:FindFirstChild("Kopf und Hals"), "Colossus head group missing")
    local carved = neck:FindFirstChild("Carved sandstone head")
    assert(carved and carved:IsA("BasePart"), "Colossus head has no survey target")
    head = carved.CFrame.Position
    local params = RaycastParams.new()
    params.FilterType, params.FilterDescendantsInstances, params.IgnoreWater =
        Enum.RaycastFilterType.Include, { workspace.Terrain }, true
    height = function(x, z)
        return assert(
            workspace:Raycast(V(x, 160, z), V(0, -260, 0), params),
            "Survey stand terrain missing"
        ).Position.Y
    end
end

local origin = V(siteX, height(siteX, siteZ), siteZ)
local at = CFrame.lookAt(origin, V(head.X, origin.Y, head.Z))
local model = Instance.new("Model")
model.Name, model.WorldPivot = name, at
model:SetAttribute("Owner", "DuneBaronColossusSurveyOverlook")
model:SetAttribute("ArtVersion", 1)
model:SetAttribute("SiteX", siteX)
model:SetAttribute("SiteZ", siteZ)
model:SetAttribute("SurveyTarget", head)

local function group(label: string): Folder
    local folder = Instance.new("Folder")
    folder.Name, folder.Parent = label, model
    return folder
end

local structure, approach, canvas, optics, desk =
    group("TimberDeck"),
    group("RidgeStair"),
    group("ShadeCanvas"),
    group("SightTube"),
    group("SurveyDesk")
local wood, edge, endGrain = rgb(143, 92, 56), rgb(102, 67, 45), rgb(187, 132, 83)
local sandstone, pale, cut = rgb(189, 131, 80), rgb(225, 175, 113), rgb(144, 96, 70)
local linen, seam, brass = rgb(229, 198, 143), rgb(179, 144, 102), rgb(191, 142, 73)
local bronze, dark, green = rgb(123, 92, 58), rgb(60, 53, 49), rgb(47, 105, 101)
local teal, glass = rgb(67, 134, 126), rgb(113, 171, 168)

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
    p.Anchored, p.CanTouch, p.CanCollide, p.CanQuery = true, false, solid == true, solid == true
    p.Parent = parent
    return p
end

local function beam(
    parent: Instance,
    label: string,
    a: Vector3,
    b: Vector3,
    thick: number,
    wide: number,
    c: Color3,
    material: Enum.Material,
    solid: boolean?,
    round: boolean?
): Part
    local axis = (b - a).Unit
    local guide = if math.abs(axis.Y) > 0.94 then at.LookVector else Y
    local up = (guide - axis * guide:Dot(axis)).Unit
    return part(
        parent,
        label,
        CFrame.fromMatrix((a + b) / 2, axis, up),
        V((b - a).Magnitude, thick, wide),
        c,
        material,
        solid,
        if round then Enum.PartType.Cylinder else nil
    )
end

local function loc(x: number, y: number, z: number): Vector3
    return at:PointToWorldSpace(V(x, y, z))
end

local function ground(x: number, z: number): Vector3
    local p = loc(x, 0, z)
    return V(p.X, height(p.X, p.Z), p.Z)
end

local function floorY(x: number, z: number): number
    return ground(x, z).Y - origin.Y
end

local count, tread, sideDoor = 13, 0.96, -6.31
local stairZ = 1.13
local entry = sideDoor - count * tread
local entryY =
    math.min(floorY(entry, stairZ - 1.87), floorY(entry, stairZ), floorY(entry, stairZ + 1.87))
local deckY = 2.67
for _, x in { -6.2, 0, 6.2 } do
    for _, z in { -4.7, 0, 4.7 } do
        deckY = math.max(deckY, floorY(x, z) + 0.72)
    end
end
for i = 2, count do
    local x = entry + tread * (i - 0.12)
    local surface = math.max(floorY(x, stairZ - 1.73), floorY(x, stairZ), floorY(x, stairZ + 1.73))
    deckY = math.max(deckY, entryY + (surface - entryY + 0.14) * count / i + 0.045)
end
model:SetAttribute("DeckY", origin.Y + deckY)

for _, x in { -5.46, 5.46 } do
    for _, z in { -3.64, 3.64 } do
        local bottom = ground(x, z)
        local top = loc(x, deckY - 0.42, z)
        part(
            structure,
            "Stone Shelter Foot",
            C(bottom - Y * 0.10) * at.Rotation,
            V(1.63, 0.83, 1.69),
            cut,
            mat.Sandstone,
            true
        )
        beam(structure, "Cedar Deck Pile", bottom + Y * 0.24, top, 0.66, 0.70, wood, mat.Wood, true)
        beam(
            structure,
            "Piled Deck Brace",
            bottom + Y * 0.38,
            loc(x * 0.56, deckY - 0.43, z),
            0.31,
            0.44,
            endGrain,
            mat.Wood
        )
    end
end
for _, z in { -3.73, 3.73 } do
    part(
        structure,
        "Deck Stringer",
        at * C(0, deckY - 0.46, z),
        V(12.54, 0.48, 0.54),
        edge,
        mat.Wood,
        true
    )
end
for i = -4, 4 do
    part(
        structure,
        "Bleached Deck Board",
        at * C(0, deckY - 0.155, i * 1.03),
        V(12.67, 0.31, 1.036),
        wood:Lerp(endGrain, 0.15 + (i % 3) * 0.11),
        mat.WoodPlanks,
        true
    )
end

local function guard(x0: number, z0: number, x1: number, z1: number)
    for _, y in { 0.87, 2.06 } do
        beam(
            structure,
            "Fitted Guard Rail",
            loc(x0, deckY + y, z0),
            loc(x1, deckY + y, z1),
            0.26,
            0.34,
            if y > 1 then green else wood,
            mat.Wood,
            true
        )
    end
end
for _, p in
    {
        { -5.96, -4.39 },
        { 0, -4.39 },
        { 5.96, -4.39 },
        { 5.96, 0 },
        { 5.96, 4.34 },
        { 0, 4.34 },
        { -5.96, 4.34 },
        { -5.96, -1.02 },
        { -5.96, 3.19 },
    }
do
    part(
        structure,
        "Guard Rail Post",
        at * C(p[1], deckY + 1.06, p[2]),
        V(0.35, 2.23, 0.40),
        wood,
        mat.Wood,
        true
    )
    part(
        structure,
        "Capped Rail Tenon",
        at * C(p[1], deckY + 2.19, p[2]),
        V(0.43, 0.14, 0.47),
        endGrain,
        mat.Wood
    )
end
guard(-5.96, -4.39, 5.96, -4.39)
guard(5.96, -4.39, 5.96, 4.34)
guard(5.96, 4.34, -5.96, 4.34)
guard(-5.96, -4.39, -5.96, -1.02)
guard(-5.96, 3.19, -5.96, 4.34)

for i = 1, count do
    local x = entry + (i - 0.5) * tread
    local top = entryY + (deckY - 0.045 - entryY) * i / count
    local lower = math.min(floorY(x, stairZ - 1.85), floorY(x, stairZ), floorY(x, stairZ + 1.85))
        - 0.33
    local deep = math.max(0.28, top - lower)
    part(
        approach,
        "Wide Stair Tread",
        at * C(x, top - deep / 2, stairZ),
        V(tread + 0.028, deep, 3.94),
        sandstone:Lerp(pale, (i % 3) * 0.21),
        mat.Sandstone,
        true
    )
end
for _, z in { stairZ - 1.90, stairZ + 1.90 } do
    local lowerY = entryY + (deckY - entryY) * 0.06
    local a, b = loc(entry + 0.77, lowerY + 2.03, z), loc(sideDoor + 0.30, deckY + 2.04, z)
    beam(approach, "Continuous Stair Rail", a, b, 0.22, 0.30, endGrain, mat.Wood, true)
    for _, t in { 0.0, 0.34, 0.68, 0.97 } do
        local p = a:Lerp(b, t)
        local bottom = V(p.X, math.min(p.Y - 1.94, height(p.X, p.Z) + 0.17), p.Z)
        beam(approach, "Lapped Stair Post", bottom, p, 0.26, 0.29, wood, mat.Wood, true)
    end
end
for i, p in { { -275.8, -61.5 }, { -279.7, -64.0 }, { -282.2, -62.6 } } do
    local y = height(p[1], p[2])
    part(
        approach,
        "Exposed Approach Paver",
        C(p[1], y + 0.035, p[2]) * A(0.04, 0.7 * i, 0.05),
        V(2.22, 0.30, 1.37),
        sandstone,
        mat.Sandstone
    )
end

-- Strips follow a shallow sag over the back half of the deck.
for _, x in { -5.42, 5.42 } do
    for _, z in { -0.02, 4.09 } do
        local top = deckY + (if z < 1 then 6.47 else 7.24)
        local postZ = if x < 0 and z < 1 then -1.21 else z
        beam(
            canvas,
            "Awning Post",
            loc(x, deckY - 0.12, postZ),
            loc(x, top + 0.17, postZ),
            0.43,
            0.43,
            wood,
            mat.Wood,
            true
        )
        beam(
            canvas,
            "Canvas Tie",
            loc(x, top - 0.38, postZ),
            loc(x, top - 0.11, postZ),
            0.51,
            0.51,
            seam,
            mat.Fabric,
            false,
            true
        )
        if postZ ~= z then
            beam(
                canvas,
                "Cantilevered Awning Finger",
                loc(x, top, postZ - 0.12),
                loc(x, top, z + 0.22),
                0.19,
                0.24,
                wood,
                mat.Wood
            )
        end
    end
end
for _, q in { { -0.02, 6.47 }, { 4.09, 7.24 } } do
    beam(
        canvas,
        "Awning Cross Rope",
        loc(-5.72, deckY + q[2], q[1]),
        loc(5.72, deckY + q[2], q[1]),
        0.15,
        0.16,
        seam,
        mat.Fabric,
        false,
        true
    )
end
for row = 1, 4 do
    local a, b = (row - 1) / 4, row / 4
    local z1, z2 = -0.07 + 4.33 * a, -0.07 + 4.33 * b
    local y1 = deckY + 6.46 + 0.81 * a - 0.51 * math.sin(math.pi * a)
    local y2 = deckY + 6.46 + 0.81 * b - 0.51 * math.sin(math.pi * b)
    local along = V(0, y2 - y1, z2 - z1)
    local cf = at
        * CFrame.fromMatrix(
            V(0, (y1 + y2) / 2, (z1 + z2) / 2),
            Vector3.xAxis,
            along.Unit:Cross(Vector3.xAxis),
            along.Unit
        )
    for strip = -2, 2 do
        part(
            canvas,
            "Stitched Linen Panel",
            cf * C(strip * 2.31, 0, 0),
            V(2.32, 0.095, along.Magnitude + 0.035),
            if strip == -1 or strip == 2
                then teal:Lerp(linen, 0.22)
                else linen:Lerp(seam, 0.06 * (strip % 3)),
            mat.Fabric
        )
    end
end

-- The sighting axis points at the original head. A dark inner aperture sits inside the front rim.
local scopeCenter = loc(-1.83, deckY + 4.42, -2.73)
local axis = (head - scopeCenter).Unit
local up = (Y - axis * axis:Dot(Y)).Unit
local scope = CFrame.fromMatrix(scopeCenter, axis, up)
for _, spec in
    {
        { -1.15, 1.52, 0.43, dark },
        { 0.04, 1.15, 0.66, green },
        { 0.96, 0.88, 0.82, bronze },
        { -1.88, 0.27, 0.58, bronze },
        { -1.99, 0.13, 0.52, dark },
    }
do
    part(
        optics,
        "Fitted Survey Tube",
        scope * C(spec[1], 0, 0),
        V(spec[2], spec[3], spec[3]),
        spec[4],
        mat.CorrodedMetal,
        false,
        Enum.PartType.Cylinder
    )
end
for i = 0, 11 do
    local turn = A((i + 0.5) * math.pi / 6, 0, 0)
    part(
        optics,
        "Open Brass Objective Rim",
        scope * turn * C(1.45, 0, 0.421),
        V(0.235, 0.23, 0.102),
        brass,
        mat.CorrodedMetal
    )
end
part(
    optics,
    "Recessed Objective Lens",
    scope * C(1.45, 0, 0),
    V(0.035, 0.744, 0.744),
    dark:Lerp(glass, 0.68),
    mat.Glass,
    false,
    Enum.PartType.Cylinder
)
part(
    optics,
    "Recessed Eyepiece",
    scope * C(-2.06, 0, 0),
    V(0.035, 0.35, 0.35),
    green,
    mat.Glass,
    false,
    Enum.PartType.Cylinder
)
part(
    optics,
    "Azimuth Rest Block",
    scope * C(-0.02, -0.47, 0),
    V(0.73, 0.26, 0.64),
    brass,
    mat.CorrodedMetal
)
for i = 0, 2 do
    local theta = i * 2 * math.pi / 3 + 0.28
    local foot = loc(-1.83 + math.cos(theta) * 1.12, deckY + 0.12, -2.73 + math.sin(theta) * 1.03)
    part(
        optics,
        "Tripod Foot",
        C(foot - Y * 0.055) * at.Rotation,
        V(0.40, 0.15, 0.40),
        dark,
        mat.Metal
    )
    local top = scopeCenter - Y * 0.55 + V(math.cos(theta) * 0.17, 0, math.sin(theta) * 0.17)
    beam(optics, "Cedar Tripod Leg", foot, top, 0.26, 0.34, wood, mat.Wood, true)
    beam(
        optics,
        "Tripod Brass Collar",
        top - Y * 0.39,
        top - Y * 0.21,
        0.37,
        0.39,
        brass,
        mat.Metal
    )
end

local tableAt = at * C(2.99, deckY, 2.19) * A(0, 0.13, 0)
part(
    desk,
    "Sandstone Survey Table Top",
    tableAt * C(0, 2.43, 0),
    V(3.21, 0.30, 1.92),
    pale,
    mat.Sandstone,
    true
)
for _, x in { -1.07, 1.07 } do
    part(
        desk,
        "Survey Desk Legs",
        tableAt * C(x, 1.15, 0),
        V(0.41, 2.31, 1.37),
        wood,
        mat.Wood,
        true
    )
end
local sheet = tableAt * C(-0.21, 2.603, 0.10) * A(0, -0.17, 0)
part(desk, "Unmarked Basin Sketch", sheet, V(1.91, 0.05, 1.24), linen, mat.Fabric)
for i = 1, 5 do
    part(
        desk,
        "Sketch Contour",
        sheet * C((i - 3) * 0.28, 0.036, 0.09 + 0.08 * math.sin(i)) * A(0, 0.27 - i * 0.12, 0),
        V(0.31, 0.024, 0.044),
        i == 3 and green or seam,
        mat.Fabric
    )
end
part(
    desk,
    "Cedar Straightedge",
    tableAt * C(0.98, 2.68, -0.42) * A(0, -0.47, 0),
    V(1.2, 0.10, 0.14),
    endGrain,
    mat.Wood
)
part(
    desk,
    "Closed Sample Case",
    tableAt * C(-1.13, 2.82, -0.36) * A(0, 0.12, 0),
    V(0.60, 0.51, 0.57),
    green,
    mat.Wood,
    false
)

if rbx and fs then
    local path = "assets/world/koloss_v1/vermessungsstand/DuneBaron_ColossusSurveyOverlook.rbxm"
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
    print(path, #copy:GetDescendants(), "instances on the Colossus rim")
else
    model.Parent = destination
    print(name, "placed at the Colossus dig site")
end
