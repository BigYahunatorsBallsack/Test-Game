--!strict
-- Presentation for a confirmed find. The caller supplies the ID and collection state.
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Catalog = require(script.Parent.Catalog) :: any
local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)

type FindRow = { name: string, icon: string, rarity: string, zoneName: string }
type Rarity = { label: string, seconds: number, shine: boolean }
local appearances: { [string]: Rarity } = {
    common = { label = "Gewöhnlich", seconds = 2.45, shine = false },
    uncommon = { label = "Ungewöhnlich", seconds = 2.60, shine = false },
    rare = { label = "Selten", seconds = 2.85, shine = true },
    epic = { label = "Episch", seconds = 3.10, shine = true },
    legendary = { label = "Legendär", seconds = 3.40, shine = true },
    mythic = { label = "Mythisch", seconds = 3.75, shine = true },
}
local zoneNames = {
    duenenmeer = "Dünenmeer",
    oase = "Oase",
    canyon = "Canyon",
    salzsee = "Salzsee",
    ruinenstadt = "Ruinenstadt",
} :: { [string]: string }
local finds: { [string]: FindRow } = {}
for zone, rows in Catalog.finds do
    for _, row in rows do
        finds[row.id] =
            { name = row.name, icon = row.icon, rarity = row.rarity, zoneName = zoneNames[zone] }
    end
end

local offset, dimensions = UDim2.fromOffset, UDim2.new
local enter = TweenInfo.new(0.21, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local pop = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local exit = TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
local sheenPass = TweenInfo.new(0.53, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function make(class: string, name: string, parent: Instance): any
    local item = Instance.new(class)
    item.Name, item.Parent = name, parent
    return item
end

local function fitText(label: TextLabel, min: number, max: number)
    label.TextScaled = true
    local bounds = make("UITextSizeConstraint", "TextBounds", label)
    bounds.MinTextSize, bounds.MaxTextSize = min, max
end

local function text(
    card: GuiObject,
    name: string,
    p: UDim2,
    size: UDim2,
    min: number,
    max: number
): TextLabel
    local label = make("TextLabel", name, card)
    label.Size, label.Position, label.BackgroundTransparency = size, p, 1
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    Theme.Lettering(label, if max > 20 then 2.4 else 1.5)
    fitText(label, min, max)
    return label
end

local function image(plate: GuiObject, name: string, side: number): ImageLabel
    local item = make("ImageLabel", name, plate)
    item.BackgroundTransparency = 1
    item.Size, item.Position, item.AnchorPoint =
        offset(side, side), dimensions(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5)
    item.ScaleType = Enum.ScaleType.Fit
    return item
end

local FindReveal = {}

function FindReveal.Mount(gui: PlayerGui)
    local layer = make("ScreenGui", "DuneBaronFindReveal", gui) :: ScreenGui
    layer.DisplayOrder = 35
    layer.ResetOnSpawn = false
    layer.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    layer.ClipToDeviceSafeArea = true

    local card = make("CanvasGroup", "FindCard", layer) :: CanvasGroup
    card.Size, card.Position, card.AnchorPoint =
        dimensions(1, -24, 0, 132), dimensions(0.5, 0, 0, 14), Vector2.new(0.5, 0)
    card.GroupTransparency, card.Visible = 1, false
    make("UICorner", "Corners", card).CornerRadius = UDim.new(0, 14)
    make("UISizeConstraint", "CardBounds", card).MaxSize = Vector2.new(456, 132)
    Theme.Paint(card, Theme.panel, 3)
    local scale = make("UIScale", "EntranceScale", card) :: UIScale

    local plate = make("Frame", "IconPlate", card) :: Frame
    plate.Size, plate.Position, plate.ClipsDescendants = offset(98, 98), offset(12, 17), true
    make("UICorner", "Corners", plate).CornerRadius = UDim.new(0, 13)
    local shine = make("Frame", "Sheen", plate) :: Frame
    shine.Size, shine.BackgroundColor3, shine.BorderSizePixel =
        dimensions(1, 0, 1, 0), Color3.new(1, 1, 1), 0
    local gradient = make("UIGradient", "SheenFalloff", shine) :: UIGradient
    gradient.Rotation = 20
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.43, 1),
        NumberSequenceKeypoint.new(0.50, 0.52),
        NumberSequenceKeypoint.new(0.57, 1),
        NumberSequenceKeypoint.new(1, 1),
    })
    local ring = image(plate, "RarityFrame", 93)
    local icon = image(plate, "FindIcon", 69)
    ring.ZIndex, icon.ZIndex = 3, 4
    local heading = text(card, "State", offset(123, 12), dimensions(1, -176, 0, 22), 11, 16)
    local name = text(card, "FindName", offset(123, 36), dimensions(1, -176, 0, 49), 14, 28)
    local context = text(card, "RarityAndZone", offset(123, 89), dimensions(1, -136, 0, 26), 11, 15)

    local close = make("TextButton", "FundanzeigeSchliessen", card) :: TextButton
    close.Size, close.Position, close.AnchorPoint =
        offset(44, 44), dimensions(1, -4, 0, 4), Vector2.new(1, 0)
    close.Text, close.BackgroundTransparency, close.TextSize = "×", 1, 25
    close.Selectable = true
    Theme.Lettering(close, 2)

    local expiry: thread?
    local fade: Tween?
    local zoom: Tween?
    local sweep: Tween?
    local destroyed = false

    local function clearAnimation()
        if expiry then
            task.cancel(expiry)
            expiry = nil
        end
        if fade then
            fade:Cancel()
            fade = nil
        end
        if zoom then
            zoom:Cancel()
            zoom = nil
        end
        if sweep then
            sweep:Cancel()
            sweep = nil
        end
    end

    local function dismiss()
        if destroyed or not card.Visible then
            return
        end
        clearAnimation()
        local closing = TweenService:Create(card, exit, { GroupTransparency = 1 })
        fade = closing
        closing.Completed:Once(function(state)
            if fade == closing and state == Enum.PlaybackState.Completed then
                fade = nil
                card.Visible = false
            end
            closing:Destroy()
        end)
        closing:Play()
    end
    close.Activated:Connect(dismiss)

    local api = {}

    -- Zeigt einen Fund aus den Spieldaten (Überarbeitung Ü5): Name, Icon, Seltenheit, Zone kommen
    -- vom Aufrufer (Data/Finds), nicht aus dem Entwurfskatalog.
    local showRow: (row: FindRow, isNew: boolean) -> boolean

    function api.Show(id: string, isNew: boolean): boolean
        local row = finds[id]
        if destroyed or not row then
            return false
        end
        return showRow(row, isNew)
    end

    function api.ShowRow(row: FindRow, isNew: boolean): boolean
        if destroyed or appearances[row.rarity] == nil or Theme.finds[row.rarity] == nil then
            return false
        end
        return showRow(row, isNew)
    end

    showRow = function(row: FindRow, isNew: boolean): boolean
        clearAnimation()
        local rarity = appearances[row.rarity]
        local swatch = Theme.finds[row.rarity]
        local reduce = GuiService.ReducedMotionEnabled
        Theme.Paint(plate, swatch, 2)
        Icons.Set(icon, row.icon)
        Icons.Set(ring, "frame_rarity_" .. row.rarity)
        heading.Text = if isNew then "Neuer Fund!" else "Fund geborgen"
        heading.TextColor3 = if isNew then Theme.gold.rim else Theme.teal.rim
        name.Text = row.name
        context.Text = rarity.label .. "  ·  " .. row.zoneName
        context.TextColor3 = swatch.rim
        scale.Scale = if reduce then 1 else 0.955
        card.GroupTransparency, card.Visible = 0.17, true
        shine.Visible = rarity.shine and not reduce
        gradient.Offset = Vector2.new(-1, 0)
        fade = TweenService:Create(card, enter, { GroupTransparency = 0 })
        fade:Play()
        if not reduce then
            zoom = TweenService:Create(scale, pop, { Scale = 1 })
            zoom:Play()
        end
        if shine.Visible then
            sweep = TweenService:Create(gradient, sheenPass, { Offset = Vector2.new(1, 0) })
            sweep:Play()
        end
        expiry = task.delay(rarity.seconds, function()
            expiry = nil
            dismiss()
        end)
        return true
    end

    function api.Destroy()
        if destroyed then
            return
        end
        destroyed = true
        clearAnimation()
        layer:Destroy()
    end

    api.Dismiss = dismiss
    return api
end

return FindReveal
