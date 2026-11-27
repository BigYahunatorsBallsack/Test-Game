--!strict
local Art = {}
local tierArt = require(script.Parent.TierArt)
-- Überarbeitung Ü5: ein Stil. Die Werkstatt nimmt die Farben aus Interface/Theme statt eigener.
local Theme = require(script.Parent.Parent.Theme)
Art.c = {
    ink = Theme.ink,
    board = Theme.ui.slot,
    panel = Theme.ui.panel,
    leaf = Theme.ui.good,
    brass = Theme.ui.accent,
    bright = Theme.gold.rim,
    ivory = Theme.text,
    mute = Theme.ui.muted,
    lock = Theme.ui.button,
    edge = Theme.ui.row,
    dark = Theme.ui.backdrop,
    wood = Theme.ui.slot,
    warn = Theme.ui.warn,
    white = Theme.ui.white,
}
Art.font = Theme.font
Art.symbols = "rbxassetid://121329522523108"
Art.scenes = "rbxassetid://133913310301503"
Art.variantScenes = { "rbxassetid://127194462292023", "rbxassetid://139759034484553" }
Art.masteryScenes = "rbxassetid://85422764371102"
Art.materials = "rbxassetid://76841357655479"
Art.gearTiers = "rbxassetid://134288678818985"
Art.supportTiers = "rbxassetid://71482682642103"
local core = "rbxassetid://108358749257413"
local offsets = {
    icon_currency_sand = { 480, 0 },
    icon_node_storage_tank = { 0, 320 },
    icon_node_selling_scales = { 160, 240 },
    icon_node_luck_compass = { 320, 160 },
    icon_currency_wind_crystal = { 0, 80 },
    icon_node_collect_bucket_chain = { 80, 320 },
    icon_node_collect_excavator = { 160, 320 },
    icon_node_collect_hand = { 240, 320 },
    icon_node_collect_harvester = { 320, 320 },
    icon_node_collect_shovel = { 400, 320 },
    icon_node_collect_suction_robot = { 480, 320 },
}

function Art.box(parent, name, color, z)
    local obj = Instance.new("Frame")
    obj.Name = name
    obj.BackgroundColor3 = color or Art.c.board
    obj.BackgroundTransparency = if color then 0 else 1
    obj.BorderSizePixel = 0
    obj.ZIndex = z or parent.ZIndex
    obj.Parent = parent
    return obj
end
function Art.rect(obj, x, y, w, h)
    obj.Position = UDim2.fromOffset(x, y)
    obj.Size = UDim2.fromOffset(w, h)
    return obj
end
function Art.round(obj, r)
    local v = Instance.new("UICorner")
    v.CornerRadius = UDim.new(0, r)
    v.Parent = obj
    return v
end
function Art.edge(obj, color, w)
    local v = Instance.new("UIStroke")
    v.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    v.Thickness = w or 1
    v.Color = color
    v.Parent = obj
    return v
end
function Art.gradient(obj, a, b, angle)
    local v = Instance.new("UIGradient")
    v.Color = ColorSequence.new(a, b)
    v.Rotation = angle or 90
    v.Parent = obj
end
function Art.text(parent, name, str, size, color, bold, z)
    local o = Instance.new("TextLabel")
    o.Name = name
    o.Text = str
    o.TextSize = size
    o.TextColor3 = color or Art.c.ivory
    o.Font = if bold then Theme.font.bold else Theme.font.body
    o.BackgroundTransparency = 1
    o.TextXAlignment = Enum.TextXAlignment.Left
    o.TextWrapped = true
    o.ZIndex = z or parent.ZIndex + 1
    o.Parent = parent
    return o
end
function Art.button(parent, name, str)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Text = str
    b.TextSize = 14
    b.Font = Theme.font.bold
    b.TextColor3 = Art.c.ivory
    b.BackgroundColor3 = Art.c.panel
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.ZIndex = if parent:IsA("GuiObject") then parent.ZIndex + 1 else 1
    b.Parent = parent
    Art.round(b, 6)
    Art.edge(b, Art.c.edge, 1)
    return b
end
function Art.image(parent, name)
    local o = Instance.new("ImageLabel")
    o.Name = name
    o.BackgroundTransparency = 1
    o.BorderSizePixel = 0
    o.ZIndex = parent.ZIndex + 1
    o.Parent = parent
    return o
end
local swatches = {
    chart = Vector2.new(0, 0),
    wood = Vector2.new(504, 0),
    steel = Vector2.new(0, 504),
    brass = Vector2.new(504, 504),
}

function Art.surface(parent, material, transparency)
    local image = Art.image(parent, "Oberflaeche")
    image.ZIndex = parent.ZIndex
    image.Size = UDim2.fromScale(1, 1)
    image.Image = Art.materials
    image.ImageRectOffset = swatches[material]
    image.ImageRectSize = Vector2.new(504, 504)
    image.ImageTransparency = transparency
    return image
end
function Art.icon(image, sprite, iconName)
    if sprite ~= nil then
        image.Image = Art.symbols
        image.ImageRectSize = Vector2.new(144, 144)
        image.ImageRectOffset = Vector2.new(sprite % 4 * 144, math.floor(sprite / 4) * 144)
    else
        local p = assert(offsets[iconName], tostring(iconName))
        image.Image = core
        image.ImageRectSize = Vector2.new(80, 80)
        image.ImageRectOffset = Vector2.new(p[1], p[2])
    end
end
function Art.scene(image, row, variant)
    if variant == 2 or variant == 3 then
        image.Image = Art.variantScenes[if row < 3 then 1 else 2]
        image.ImageRectOffset = Vector2.new((variant - 2) * 504, (row % 3) * 336)
    else
        image.Image = if variant == 4 then Art.masteryScenes else Art.scenes
        image.ImageRectOffset = Vector2.new(row % 2 * 504, math.floor(row / 2) * 336)
    end
    image.ImageRectSize = Vector2.new(504, 336)
end
function Art.nodeIcon(image, node)
    local entry = tierArt[node.id]
    if not entry then
        Art.icon(image, node.sprite, node.core)
        return
    end
    local gear = entry[1] == "gear"
    local tile = if gear then 84 else 112
    local columns = if gear then 12 else 9
    image.Image = if gear then Art.gearTiers else Art.supportTiers
    image.ImageRectSize = Vector2.new(tile, tile)
    image.ImageRectOffset =
        Vector2.new(entry[2] % columns * tile, math.floor(entry[2] / columns) * tile)
    image:SetAttribute("Bildstufe", entry[3])
end
function Art.bezel(parent, roundness)
    local ring = Art.box(parent, "Messingfassung", Theme.ui.white, parent.ZIndex)
    ring.Size = UDim2.fromScale(1, 1)
    Art.round(ring, roundness)
    local sheen = Instance.new("UIGradient")
    sheen.Rotation = 49
    sheen.Color = Theme.gold.fill -- Ü5: goldener Rand aus Theme statt Messing
    sheen.Parent = ring
    return ring
end
function Art.line(parent, a, b, color, width, z, name)
    local line = Art.box(parent, name or "Trace", color, z)
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    local mid = (a + b) * 0.5
    line.Position = UDim2.fromOffset(mid.X, mid.Y)
    line.Size = UDim2.fromOffset((b - a).Magnitude, width)
    line.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
    return line
end
return Art
