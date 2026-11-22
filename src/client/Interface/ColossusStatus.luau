--!strict
-- Displays the progress snapshot supplied by the Colossus event controller.
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)

type Snapshot = { progress: number, lastSection: ("northHand" | "feet")? }
local sectionText = {
    northHand = "Nordhand freigelegt",
    feet = "Füße freigelegt",
}
local motion = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local px, size = UDim2.fromOffset, UDim2.new

local function make(class: string, name: string, parent: Instance): any
    local node = Instance.new(class)
    node.Name, node.Parent = name, parent
    return node
end

local function corners(node: GuiObject, radius: number)
    make("UICorner", "Corners", node).CornerRadius = UDim.new(0, radius)
end

local function label(
    parent: GuiObject,
    name: string,
    pos: UDim2,
    bounds: UDim2,
    fontSize: number
): TextLabel
    local node = make("TextLabel", name, parent) :: TextLabel
    node.Position, node.Size, node.BackgroundTransparency = pos, bounds, 1
    node.TextSize, node.TextXAlignment = fontSize, Enum.TextXAlignment.Left
    Theme.Lettering(node, if fontSize > 20 then 2.1 else 1.45)
    return node
end

local function mount(gui: PlayerGui)
    local layer = make("ScreenGui", "DuneBaronColossusStatus", gui) :: ScreenGui
    layer.DisplayOrder = 12
    layer.ResetOnSpawn = false
    layer.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    layer.ClipToDeviceSafeArea = true
    local area = make("Frame", "SafeArea", layer) :: Frame
    area.BackgroundTransparency, area.Size = 1, size(1, 0, 1, 0)
    local card = make("Frame", "EventProgress", area) :: Frame
    card.Size, card.Visible = size(1, -24, 0, 98), false
    make("UISizeConstraint", "CardBounds", card).MaxSize = Vector2.new(354, 98)
    corners(card, 13)
    Theme.Paint(card, Theme.panel, 3)
    local border = card:FindFirstChild("ColorRim") :: UIStroke

    local icon = make("Frame", "StoneSetting", card) :: Frame
    icon.Size, icon.Position = px(29, 29), px(18, 19)
    icon.Rotation = 45
    corners(icon, 4)
    Theme.Paint(icon, Theme.gold, 2)
    local gem = make("Frame", "TealInlay", icon) :: Frame
    gem.Size, gem.Position = px(18, 18), size(0.5, 0, 0.5, 0)
    gem.AnchorPoint = Vector2.new(0.5, 0.5)
    corners(gem, 3)
    Theme.Paint(gem, Theme.teal, 1.4)

    local heading = label(card, "EventName", px(62, 11), size(1, -125, 0, 26), 22)
    heading.Text = "Der Koloss"
    local caption = label(card, "StatusText", px(62, 41), size(1, -75, 0, 20), 14)
    local percent = label(card, "Percent", size(1, -68, 0, 12), px(53, 26), 21)
    percent.TextXAlignment = Enum.TextXAlignment.Right
    local track = make("Frame", "ProgressTrack", card) :: Frame
    track.Size, track.Position = size(1, -28, 0, 12), px(14, 72)
    track.BorderSizePixel, track.BackgroundColor3, track.ClipsDescendants = 0, Theme.ink, true
    corners(track, 6)
    local fill = make("Frame", "Fill", track) :: Frame
    fill.Size = size(0, 0, 1, 0)
    corners(fill, 6)

    local function layout()
        local compact = area.AbsoluteSize.X < 780
        card.AnchorPoint = Vector2.new(if compact then 0.5 else 1, 0)
        card.Position = if compact then size(0.5, 0, 0, 153) else size(1, -14, 0, 12)
    end
    local resize = area:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
    layout()

    local progressTween: Tween?
    local current: number? = nil
    local currentSection: string? = nil
    local done = false
    local destroyed = false
    local function stop()
        if progressTween then
            progressTween:Cancel()
            progressTween:Destroy()
            progressTween = nil
        end
    end

    local api = {}

    function api.Update(snapshot: Snapshot?)
        if destroyed then
            return
        end
        if not snapshot then
            stop()
            card.Visible, current, currentSection = false, nil, nil
            done = false
            fill.Size = size(0, 0, 1, 0)
            return
        end
        if snapshot.progress ~= snapshot.progress then
            return
        end
        local ratio = math.clamp(snapshot.progress, 0, 1)
        local section = snapshot.lastSection
        local isComplete = ratio >= 1
        if current == nil or done ~= isComplete then
            local swatch = if isComplete then Theme.gold else Theme.teal
            Theme.Paint(fill, swatch, 0)
            border.Color = swatch.rim
            percent.TextColor3 = swatch.rim
        end
        if current == nil or section ~= currentSection or done ~= isComplete then
            caption.Text = if isComplete
                then "Koloss freigelegt"
                elseif section then sectionText[section] or "Gemeinsame Ausgrabung"
                else "Gemeinsame Ausgrabung"
        end
        if current ~= ratio then
            percent.Text = tostring(math.floor(ratio * 100)) .. "%"
            stop()
            local width = size(ratio, 0, 1, 0)
            if GuiService.ReducedMotionEnabled or current == nil then
                fill.Size = width
            else
                progressTween = TweenService:Create(fill, motion, { Size = width })
                progressTween:Play()
            end
        end
        current, currentSection, done = ratio, section, isComplete
        card.Visible = true
    end

    function api.Destroy()
        if destroyed then
            return
        end
        destroyed = true
        stop()
        resize:Disconnect()
        layer:Destroy()
    end

    return api
end

return table.freeze({ Mount = mount })
