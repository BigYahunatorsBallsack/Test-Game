--!strict
-- Build the static model library with Lune from the project root.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance, Enum = roblox.Instance, roblox.Enum
local V, C, A, rgb =
    roblox.Vector3.new, roblox.CFrame.new, roblox.CFrame.Angles, roblox.Color3.fromRGB
local mat = Enum.Material
local stone, pale, darkStone = rgb(193, 139, 94), rgb(224, 172, 119), rgb(126, 87, 67)
local teal, glaze, copper = rgb(44, 99, 101), rgb(86, 159, 151), rgb(122, 76, 51)
local metal, wood, canvas = rgb(56, 49, 52), rgb(92, 63, 54), rgb(194, 131, 93)
local pack = Instance.new("Folder")
pack.Name = "DuneBaronRuinsWayfinding"
pack:SetAttribute("ZoneId", "ruins")

local function part(
    parent: Model,
    name: string,
    cf: CFrame,
    size: Vector3,
    color: Color3,
    material: Enum.Material
)
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, cf, color, material
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end

local function model(name: string): Model
    local item = Instance.new("Model")
    item.Name, item.Parent = name, pack
    local pivot = part(item, "TerrainPivot", C(), V(0.1, 0.1, 0.1), stone, mat.Sandstone)
    pivot.Transparency, pivot.CastShadow = 1, false
    item.PrimaryPart = pivot
    return item
end

local function block(
    parent: Model,
    name: string,
    x: number,
    y: number,
    z: number,
    w: number,
    h: number,
    d: number,
    color: Color3,
    material: Enum.Material
)
    return part(parent, name, C(x, y, z), V(w, h, d), color, material)
end

local function disc(
    parent: Model,
    name: string,
    z: number,
    y: number,
    diameter: number,
    depth: number,
    color: Color3
)
    local p = part(
        parent,
        name,
        C(0, y, z) * A(0, math.pi / 2, 0),
        V(depth, diameter, diameter),
        color,
        mat.Sandstone
    )
    p.Shape = Enum.PartType.Cylinder
end

do
    local m = model("Karawanenlaterne")
    block(m, "Foundation", 0, 0.08, 0, 3.10, 0.86, 3.10, darkStone, mat.Sandstone)
    block(m, "Plinth", 0, 0.72, 0, 2.64, 0.48, 2.64, pale, mat.Sandstone)
    block(m, "Sandstone shaft", 0, 2.76, 0, 1.64, 3.60, 1.64, stone, mat.Sandstone)
    block(m, "Glazed collar", 0, 3.87, 0, 1.69, 0.31, 1.69, teal, mat.Marble)
    block(m, "Capital", 0, 4.65, 0, 2.30, 0.32, 2.30, pale, mat.Sandstone)
    block(m, "Lantern tray", 0, 4.90, 0, 1.98, 0.21, 1.98, metal, mat.Metal)
    local amber = block(m, "Honey glass", 0, 5.79, 0, 1.54, 1.64, 1.54, rgb(255, 175, 74), mat.Neon)
    for _, x in { -0.82, 0.82 } do
        for _, z in { -0.82, 0.82 } do
            block(m, "Dark mullion", x, 5.78, z, 0.24, 1.66, 0.24, metal, mat.Metal)
        end
    end
    for _, side in { -1, 1 } do
        block(
            m,
            "Copper crossbar",
            0,
            5.36,
            side * 0.79,
            1.64,
            0.11,
            0.13,
            copper,
            mat.CorrodedMetal
        )
        block(
            m,
            "Copper crossbar",
            side * 0.79,
            5.36,
            0,
            0.13,
            0.11,
            1.64,
            copper,
            mat.CorrodedMetal
        )
    end
    block(m, "Overhanging cap", 0, 6.63, 0, 2.26, 0.24, 2.26, metal, mat.Metal)
    block(m, "Bronze cap shoulder", 0, 6.86, 0, 1.69, 0.24, 1.69, copper, mat.CorrodedMetal)
    block(m, "Bronze cap crown", 0, 7.07, 0, 1.14, 0.20, 1.14, copper, mat.CorrodedMetal)
    block(m, "Finial", 0, 7.24, 0, 0.38, 0.20, 0.38, metal, mat.Metal)

    local light = Instance.new("PointLight")
    light.Name, light.Color = "Lantern light", rgb(255, 172, 87)
    light.Brightness, light.Range, light.Shadows = 0.87, 14, false
    light.Parent = amber
end

do
    local m = model("Siegelstele")
    block(m, "Buried stone footing", 0, 0.12, 0, 3.52, 0.76, 2.70, darkStone, mat.Sandstone)
    block(m, "Stele plinth", 0, 0.66, 0, 2.96, 0.44, 2.01, pale, mat.Sandstone)
    block(m, "Stone upright", 0, 2.91, 0, 2.46, 4.13, 1.34, stone, mat.Sandstone)
    block(m, "Shoulder course", 0, 5.03, 0, 2.84, 0.37, 1.61, pale, mat.Sandstone)
    block(m, "Crown", 0, 5.29, 0, 2.30, 0.20, 1.38, stone, mat.Sandstone)
    for _, side in { -1, 1 } do
        disc(m, "Round relief border", side * 0.68, 3.74, 1.92, 0.17, darkStone)
        disc(m, "Oxidized seal", side * 0.79, 3.74, 1.56, 0.10, teal)
        part(
            m,
            "Raised compass diamond",
            C(0, 3.74, side * 0.86) * A(0, 0, math.pi / 4),
            V(0.64, 0.64, 0.12),
            glaze,
            mat.Marble
        )
        block(m, "Horizontal inlay", 0, 2.26, side * 0.70, 1.58, 0.26, 0.13, teal, mat.Marble)
        block(m, "Short inlay", -0.28, 1.75, side * 0.70, 1.02, 0.19, 0.13, glaze, mat.Marble)
    end
end

local function survey(name: string, cloth: Color3, stripe: Color3)
    local m = model(name)
    for _, x in { -1.82, 1.82 } do
        block(m, "Survey stake", x, 1.35, 0, 0.25, 3.22, 0.26, wood, mat.Wood)
        block(m, "Wrapped cap", x, 2.79, 0, 0.33, 0.34, 0.34, canvas, mat.Fabric)
    end
    part(
        m,
        "Taut marking cord",
        C(0, 2.52, 0) * A(0, 0, -0.076),
        V(3.66, 0.082, 0.082),
        canvas,
        mat.Fabric
    )
    for index = 0, 2 do
        local x = 0.80 + index * 0.29
        local height = 0.75 - index * 0.13
        local cordY = 2.52 - x * math.tan(0.076)
        part(
            m,
            "Woven flag",
            C(x, cordY - height / 2 + 0.015, 0) * A(0, 0.14 - index * 0.17, -0.076),
            V(0.31, height, 0.085),
            cloth,
            mat.Fabric
        )
    end

    local tray = C(-0.53, 0.16, 1.05) * A(0, -0.15, 0)
    part(m, "Sample tray base", tray, V(1.59, 0.25, 1.02), wood, mat.WoodPlanks)
    for _, side in { -1, 1 } do
        part(m, "Tray rim", tray * C(0, 0.19, side * 0.47), V(1.59, 0.24, 0.12), wood, mat.Wood)
        part(m, "Tray rim", tray * C(side * 0.735, 0.19, 0), V(0.12, 0.24, 0.82), wood, mat.Wood)
    end
    part(
        m,
        "Linen sample wrap",
        tray * C(-0.27, 0.19, 0.095) * A(0, 0.19, 0),
        V(0.52, 0.24, 0.45),
        canvas,
        mat.Fabric
    )
    part(
        m,
        "Sample fragment",
        tray * C(0.32, 0.21, -0.09) * A(0.21, -0.3, 0.15),
        V(0.45, 0.26, 0.36),
        pale,
        mat.Sandstone
    )
    part(m, "Painted survey stripe", C(-1.82, 1.58, 0), V(0.27, 0.24, 0.28), stripe, mat.Fabric)
    part(
        m,
        "Probe handle",
        tray * C(0.35, 0.37, 0.49) * A(0, 0, 0.31),
        V(1.03, 0.11, 0.11),
        copper,
        mat.Wood
    )
end

survey("GrabungsspurArchiv", rgb(184, 96, 62), pale)
survey("GrabungsspurSiegelkammer", glaze, teal)

local path = "assets/world/ruinenstadt_v1/DuneBaron_Ruins_Wayfinding.rbxm"
local data = roblox.serializeModel({ pack })
local reloaded = roblox.deserializeModel(data)[1]
assert(reloaded.Name == pack.Name and #reloaded:GetChildren() == 4)
for _, item in reloaded:GetDescendants() do
    if item:IsA("Model") then
        assert(item.PrimaryPart and item.PrimaryPart.CFrame == C())
    elseif item:IsA("BasePart") then
        assert(item.Anchored and not item.CanCollide and not item.CanQuery and not item.CanTouch)
    end
end
fs.writeFile(path, data)
print(path, "verified", #reloaded:GetDescendants(), "instances")
