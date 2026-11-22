--!strict
-- Authoring only. Build the track, loading winch and sanded-over service hatch.
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
local name = "CanyonLoadingStationV1"
local destination: Instance?
local height: (number, number) -> number

if offline then
    height = require("./CanyonSurface").height
else
    local run = game:GetService("RunService")
    assert(
        run:IsStudio() and not run:IsRunning() and game.PlaceId == 135831532782380,
        "Use Every Last Grain in Studio Edit"
    )
    local world = workspace:FindFirstChild("DuneBaronWorld")
    assert(
        world and world:GetAttribute("CanyonTerrainRevision") == 1,
        "Canyon V1 terrain is required"
    )
    destination = assert(world:FindFirstChild("CanyonArtV1"), "Install the canyon landmarks first")
    assert(not destination:FindFirstChild(name), "Loading station already installed")
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { workspace.Terrain }
    params.IgnoreWater = true
    height = function(x, z)
        local hit = workspace:Raycast(V(x, 188, z), V(0, -224, 0), params)
        return assert(hit, "Canyon ground missing").Position.Y
    end
end

local siteX, siteZ = 620, 686
local frame = C(siteX, height(siteX, siteZ), siteZ) * A(0, math.rad(19), 0)
local model = Instance.new("Model")
model.Name, model.WorldPivot = name, frame
model:SetAttribute("Owner", "DuneBaronCanyonLoadingStation")
model:SetAttribute("ArtVersion", 1)
model:SetAttribute("SiteX", siteX)
model:SetAttribute("SiteZ", siteZ)

local function group(label: string): Folder
    local item = Instance.new("Folder")
    item.Name, item.Parent = label, model
    return item
end

local track, cart, hoist, hatch =
    group("SandedTrack"), group("LoadedMineCart"), group("TimberHoist"), group("ServiceHatch")
local oak, lightOak, endGrain = rgb(122, 80, 52), rgb(154, 104, 67), rgb(173, 120, 76)
local metal, rust, pin = rgb(57, 57, 54), rgb(111, 66, 42), rgb(194, 146, 83)
local teal, edge, shade = rgb(45, 99, 99), rgb(66, 129, 124), rgb(30, 65, 64)
local redStone, limestone, mortar = rgb(179, 122, 88), rgb(215, 164, 120), rgb(146, 98, 76)
local rope = rgb(183, 142, 85)

local function part(
    parent: Instance,
    label: string,
    cf: CFrame,
    size: Vector3,
    color: Color3,
    material: Enum.Material,
    shape: Enum.PartType?
): Part
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color, p.Material = label, size, cf, color, material
    p.Shape = shape or Enum.PartType.Block
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
    p.Parent = parent
    return p
end

local function beam(
    parent: Instance,
    label: string,
    a: Vector3,
    b: Vector3,
    width: number,
    depth: number,
    color: Color3,
    material: Enum.Material,
    shape: Enum.PartType?
)
    local along = (b - a).Unit
    local hint = if math.abs(along.Y) > 0.94 then frame.LookVector else Y
    local normal = (hint - hint:Dot(along) * along).Unit
    return part(
        parent,
        label,
        CFrame.fromMatrix((a + b) * 0.5, along, normal),
        V((b - a).Magnitude, width, depth),
        color,
        material,
        shape
    )
end

local function site(x: number, y: number, z: number): Vector3
    return frame:PointToWorldSpace(V(x, y, z))
end

local function ground(x: number, z: number): Vector3
    local p = site(x, 0, z)
    return V(p.X, height(p.X, p.Z), p.Z)
end

-- Ballast and sleepers are buried at the ends. Continuous rails carry the visible wheel flanges.
local railSamples = {
    { -15, -0.13 },
    { -11.9, 0.09 },
    { -8.6, 0.27 },
    { -4.5, 0.33 },
    { 1.0, 0.39 },
    { 5.3, 0.51 },
    { 8.6, 0.25 },
    { 11.6, -0.25 },
}
local trackY = ground(0, -3.2).Y
local function rail(x: number, row: { number }): Vector3
    local p = site(x, 0, row[1])
    local y = if row[1] < -8 or row[1] > 6 then height(p.X, p.Z) else trackY
    return V(p.X, y + row[2], p.Z)
end

for i, row in railSamples do
    local left, right = rail(-1.73, row), rail(1.73, row)
    local sleeper = (left + right) * 0.5 - Y * 0.18
    part(
        track,
        "Buried Oak Sleeper",
        CFrame.fromMatrix(sleeper, (right - left).Unit, Y),
        V(4.5, 0.25, 0.48),
        if i % 2 == 0 then lightOak else oak,
        mat.WoodPlanks
    )
    if i == 1 then
        continue
    end
    for _, x in { -1.73, 1.73 } do
        local a, b = rail(x, railSamples[i - 1]), rail(x, row)
        beam(track, "Weathered Rail Web", a, b, 0.17, 0.19, rust, mat.Metal)
        beam(track, "Steel Running Face", a + Y * 0.11, b + Y * 0.11, 0.09, 0.25, metal, mat.Metal)
    end
end

local cartZ = -2.0
local p = site(0, 0, cartZ)
local chassis = C(p.X, trackY + 1.04, p.Z) * frame.Rotation * A(math.rad(-0.65), 0, 0)
part(cart, "Iron Chassis", chassis * C(0, 0.13, 0), V(4.46, 0.31, 5.88), metal, mat.Metal)
for _, z in { -1.91, 1.91 } do
    local a, b = chassis:PointToWorldSpace(V(-2.01, 0, z)), chassis:PointToWorldSpace(V(2.01, 0, z))
    beam(cart, "Axle", a, b, 0.25, 0.25, metal, mat.Metal, Enum.PartType.Cylinder)
    for _, side in { -1, 1 } do
        local axle = chassis * C(side * 1.73, 0, z)
        part(
            cart,
            "Flanged Steel Wheel",
            axle,
            V(0.39, 1.02, 1.02),
            metal,
            mat.Metal,
            Enum.PartType.Cylinder
        )
        part(
            cart,
            "Oxidized Wheel Face",
            axle * C(side * 0.207, 0, 0),
            V(0.068, 0.78, 0.78),
            rust,
            mat.Metal,
            Enum.PartType.Cylinder
        )
        part(
            cart,
            "Wheel Hub",
            axle * C(side * 0.252, 0, 0),
            V(0.114, 0.45, 0.45),
            pin,
            mat.Metal,
            Enum.PartType.Cylinder
        )
    end
end

part(cart, "Cargo Floor", chassis * C(0, 0.53, 0), V(3.84, 0.23, 5.12), shade, mat.Metal)
for _, side in { -1, 1 } do
    local sidewall = chassis * C(side * 2.10, 1.40, 0) * A(0, 0, -side * 0.18)
    part(cart, "Flared Side Panel", sidewall, V(0.18, 1.84, 5.32), teal, mat.Metal)
    part(cart, "Rolled Rim", sidewall * C(0, 0.93, 0), V(0.31, 0.20, 5.50), edge, mat.Metal)
    for _, z in { -2.47, 0, 2.47 } do
        part(
            cart,
            "Side Rib",
            sidewall * C(side * 0.118, -0.015, z),
            V(0.14, 1.65, 0.24),
            shade,
            mat.Metal
        )
        part(
            cart,
            "Copper Rivet",
            sidewall * C(side * 0.198, 0.63, z),
            V(0.07, 0.14, 0.14),
            pin,
            mat.Metal,
            Enum.PartType.Cylinder
        )
    end
    local tail = chassis * C(0, 1.42, side * 2.635) * A(side * 0.13, 0, 0)
    part(cart, "End Panel", tail, V(4.15, 1.87, 0.16), teal, mat.Metal)
    part(cart, "End Rim", tail * C(0, 0.93, 0), V(4.49, 0.20, 0.29), edge, mat.Metal)
    part(
        cart,
        "Tow Coupling",
        chassis * C(0, 0.22, side * 3.02),
        V(0.52, 0.35, 0.48),
        rust,
        mat.Metal
    )
end

for i, row in
    {
        { -0.71, -1.29, 1.55 },
        { 0.57, -1.23, 1.45 },
        { 0.84, 0.14, 1.37 },
        { -0.63, 0.57, 1.69 },
        { 0.30, 1.49, 1.32 },
    }
do
    local s = row[3]
    local block = chassis
        * C(row[1], 0.65 + s * 0.40, row[2])
        * A(0.08 * i, i * 0.91, -0.10 * math.sin(i))
    part(
        cart,
        "Rough Sandstone Load",
        block,
        V(s, s * 0.78, s * 0.92),
        if i % 2 == 0 then redStone else limestone,
        mat.Sandstone,
        if i % 3 == 0 then Enum.PartType.Wedge else nil
    )
end

-- Four splayed timbers carry a horizontal drum with a hand crank and a hanging hook.
for _, x in { -3.9, 3.9 } do
    for _, z in { -3.0, 3.0 } do
        local base = ground(x, z + 4.8)
        part(
            hoist,
            "Footing Stone",
            C(base + Y * 0.09) * frame.Rotation,
            V(1.85, 0.64, 1.68),
            redStone,
            mat.Sandstone
        )
        beam(
            hoist,
            "Splayed Timber Leg",
            base + Y * 0.25,
            site(x, 8.83, 4.8 + z * 0.16),
            0.76,
            0.77,
            oak,
            mat.Wood
        )
    end
    beam(
        hoist,
        "Tension Brace",
        site(x, 2.65, 2.69),
        site(x, 6.90, 5.65),
        0.39,
        0.43,
        lightOak,
        mat.Wood
    )
    part(hoist, "Drum Bearing", frame * C(x, 7.69, 4.8), V(0.89, 0.76, 0.87), metal, mat.Metal)
    part(hoist, "Ridge Strap", frame * C(x, 8.84, 4.8), V(0.54, 1.12, 1.26), rust, mat.Metal)
end
part(
    hoist,
    "Notched Ridge Timber",
    frame * C(0, 8.83, 4.8),
    V(9.46, 0.78, 1.04),
    lightOak,
    mat.Wood
)
part(
    hoist,
    "Drum Axle",
    frame * C(0, 7.72, 4.8),
    V(9.11, 0.44, 0.44),
    metal,
    mat.Metal,
    Enum.PartType.Cylinder
)
part(
    hoist,
    "Wooden Winch Drum",
    frame * C(0, 7.72, 4.8),
    V(3.42, 1.13, 1.13),
    endGrain,
    mat.Wood,
    Enum.PartType.Cylinder
)
for _, x in { -1.76, 1.76 } do
    part(
        hoist,
        "Drum Flange",
        frame * C(x, 7.72, 4.8),
        V(0.21, 1.68, 1.68),
        metal,
        mat.Metal,
        Enum.PartType.Cylinder
    )
end
for i = -7, 7 do
    part(
        hoist,
        "Wrapped Rope",
        frame * C(i * 0.16, 7.72, 4.8),
        V(0.167, 1.27, 1.27),
        rope:Lerp(oak, (i % 3) * 0.085),
        mat.Fabric,
        Enum.PartType.Cylinder
    )
end
beam(
    hoist,
    "Suspended Cargo Rope",
    site(0.03, 7.73, 4.18),
    site(0.09, 3.55, 4.12),
    0.13,
    0.13,
    rope,
    mat.Fabric,
    Enum.PartType.Cylinder
)
local hook = {
    V(0.09, 3.58, 4.12),
    V(0.09, 3.10, 4.10),
    V(0.31, 2.84, 4.10),
    V(0.60, 2.89, 4.10),
    V(0.70, 3.13, 4.10),
}
for i = 2, #hook do
    local a, b = hook[i - 1], hook[i]
    beam(
        hoist,
        "Forged Cargo Hook",
        site(a.X, a.Y, a.Z),
        site(b.X, b.Y, b.Z),
        0.17,
        0.18,
        metal,
        mat.Metal,
        Enum.PartType.Cylinder
    )
end
beam(hoist, "Crank Arm", site(4.55, 7.72, 4.8), site(4.55, 6.66, 5.36), 0.23, 0.27, rust, mat.Metal)
beam(
    hoist,
    "Wooden Crank Grip",
    site(4.50, 6.66, 5.36),
    site(5.36, 6.66, 5.36),
    0.29,
    0.29,
    endGrain,
    mat.Wood,
    Enum.PartType.Cylinder
)

-- The wall stands in front of the talus. The lowest course and latch sit within the sand.
local portalGround = ground(-0.15, 13.18)
local portal = C(portalGround) * frame.Rotation * A(0, math.rad(12), 0)
local hatchWidth, hatchHeight = 4.56, 1.62
for _, x in { -3.28, 3.28 } do
    for i = 0, 2 do
        part(
            hatch,
            "Stacked Jamb Stone",
            portal * C(x + (i % 2) * 0.17, (i - 0.5) * 1.13, 0),
            V(1.85 - i * 0.13, 1.10, 2.2),
            if i % 2 == 0 then redStone else limestone,
            mat.Sandstone
        )
    end
end
part(
    hatch,
    "Dressed Lintel",
    portal * C(0, 2.39, 0.04),
    V(8.69, 1.02, 2.31),
    limestone,
    mat.Sandstone
)
part(
    hatch,
    "Sandstone Recess",
    portal * C(0, hatchHeight - 0.34, 0.71),
    V(hatchWidth, 3.29, 0.81),
    mortar,
    mat.Sandstone
)
for i = -2, 2 do
    part(
        hatch,
        "Buried Shutter Board",
        portal * C(i * 0.82, hatchHeight - 0.86, 0.2) * A(0, 0, 0.012 * i),
        V(0.81, 2.73, 0.34),
        if i % 2 == 0 then oak else lightOak,
        mat.WoodPlanks
    )
end
part(
    hatch,
    "Tilted Iron Crossbar",
    portal * C(0.03, 0.10, -0.045) * A(0, 0, -0.11),
    V(4.51, 0.42, 0.17),
    metal,
    mat.Metal
)
part(hatch, "Buried Latch", portal * C(-0.38, -0.27, -0.17), V(0.43, 0.59, 0.23), pin, mat.Metal)
part(
    hatch,
    "Turquoise Lintel Inlay",
    portal * C(0, 2.43, -1.14),
    V(3.67, 0.43, 0.13),
    edge,
    mat.Slate
)

for i, loc in
    {
        { 3.18, -6.94, 0.68 },
        { 3.81, -7.65, 0.91 },
        { -4.20, -8.67, 0.76 },
        { -5.08, -8.13, 1.10 },
        { 4.35, 10.77, 1.27 },
        { 5.44, 10.01, 0.77 },
        { 2.66, 13.98, 0.92 },
    }
do
    local p = ground(loc[1], loc[2])
    local s = loc[3]
    part(
        hatch,
        "Slumped Talus",
        C(p + Y * 0.13) * A(0.10, i * 1.27, -0.08),
        V(s, s * 0.59, s * 0.87),
        if i % 2 == 0 then limestone else redStone,
        mat.Sandstone,
        Enum.PartType.Wedge
    )
end

if rbx and fs then
    local output = "assets/world/canyon_v1/lastenstation/DuneBaron_CanyonLoadingStation.rbxm"
    local bytes = rbx.serializeModel({ model })
    local rebuilt = rbx.deserializeModel(bytes)[1]
    assert(#rebuilt:GetChildren() == 4 and rebuilt:GetAttribute("ArtVersion") == 1)
    for _, item in rebuilt:GetDescendants() do
        assert(not item:IsA("LuaSourceContainer"))
        if item:IsA("BasePart") then
            assert(
                item.Anchored and not item.CanCollide and not item.CanQuery and not item.CanTouch
            )
        end
    end
    fs.writeFile(output, bytes)
    print(output, #rebuilt:GetDescendants(), "instances")
else
    model.Parent = destination
    print(name, "placed in CanyonArtV1")
end
