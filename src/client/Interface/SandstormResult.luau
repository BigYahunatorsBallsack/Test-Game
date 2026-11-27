--!strict
-- Presents the already confirmed result of a Prestige reset.
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

type Result = { windCrystals: string, ruinsUnlocked: boolean, unit: string? } -- unit: Zeile unter der Zahl (Ü5)
local px, size = UDim2.fromOffset, UDim2.new
local appear = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local swell = TweenInfo.new(0.27, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local leave = TweenInfo.new(0.24, Enum.EasingStyle.Sine)

local function make(class: string, name: string, parent: Instance): any
    local node = Instance.new(class)
    node.Name, node.Parent = name, parent
    return node
end

local function text(
    host: GuiObject,
    name: string,
    pos: UDim2,
    bounds: UDim2,
    min: number,
    max: number
): TextLabel
    local label = make("TextLabel", name, host) :: TextLabel
    label.Position, label.Size, label.BackgroundTransparency = pos, bounds, 1
    label.TextXAlignment, label.TextWrapped, label.TextScaled = Enum.TextXAlignment.Left, true, true
    local constraint = make("UITextSizeConstraint", "TextBounds", label)
    constraint.MinTextSize, constraint.MaxTextSize = min, max
    Theme.Lettering(label, if max > 21 then 2.2 else 1.5)
    return label
end

local function mount(parent: PlayerGui)
    local screen = make("ScreenGui", "DuneBaronSandstormResult", parent) :: ScreenGui
    screen.DisplayOrder, screen.ResetOnSpawn = 34, false
    screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    screen.ClipToDeviceSafeArea = true
    local card = make("CanvasGroup", "Result", screen) :: CanvasGroup
    card.Position, card.AnchorPoint = size(0.5, 0, 0.22, 0), Vector2.new(0.5, 0)
    card.Visible = false
    make("UICorner", "CardCorners", card).CornerRadius = UDim.new(0, 15)
    make("UISizeConstraint", "CardBounds", card).MaxSize = Vector2.new(416, 149)
    Theme.Paint(card, Theme.panel, 3)
    local rim = card:FindFirstChild("ColorRim") :: UIStroke
    rim.Color = Theme.teal.rim
    local scale = make("UIScale", "EntranceScale", card) :: UIScale

    local badge = make("Frame", "CrystalBadge", card) :: Frame
    badge.Size, badge.Position = px(72, 72), px(14, 17)
    make("UICorner", "BadgeCorners", badge).CornerRadius = UDim.new(0, 13)
    Theme.Paint(badge, Theme.teal, 2)
    local gem = make("ImageLabel", "WindCrystal", badge) :: ImageLabel
    gem.Size, gem.Position, gem.BackgroundTransparency = px(61, 61), px(6, 6), 1
    gem.ScaleType = Enum.ScaleType.Fit
    Icons.Set(gem, "icon_currency_wind_crystal")
    local heading = text(card, "Heading", px(101, 12), size(1, -148, 0, 29), 13, 21)
    heading.Text = "Sandsturm vorüber"
    local reward = text(card, "CrystalAmount", px(101, 43), size(1, -115, 0, 31), 14, 28)
    reward.TextColor3 = Theme.teal.rim
    local label = text(card, "Unit", px(101, 77), size(1, -115, 0, 19), 12, 14)
    label.Text = "Windkristalle"
    local unlocked = text(card, "NewZone", px(14, 108), size(1, -28, 0, 25), 12, 15)
    unlocked.Text = "Ruinenstadt freigeschaltet"
    unlocked.TextColor3 = Theme.gold.rim
    local line = make("Frame", "Divider", card) :: Frame
    line.BorderSizePixel, line.BackgroundColor3 = 0, Theme.panel.rim
    line.BackgroundTransparency = 0.61
    line.Size, line.Position = size(1, -28, 0, 1), px(14, 103)

    local dismiss = make("TextButton", "ErgebnisSchliessen", card) :: TextButton
    dismiss.Size, dismiss.Position, dismiss.AnchorPoint =
        px(44, 44), size(1, -2, 0, 1), Vector2.new(1, 0)
    dismiss.Text, dismiss.TextSize, dismiss.BackgroundTransparency = "×", 25, 1
    dismiss.Selectable = true
    Theme.Lettering(dismiss, 2)

    local expiry: thread?
    local fade: Tween?
    local bounce: Tween?
    local generation = 0
    local gone = false

    local function clear()
        generation += 1
        if expiry then
            task.cancel(expiry)
            expiry = nil
        end
        if fade then
            fade:Cancel()
            fade:Destroy()
            fade = nil
        end
        if bounce then
            bounce:Cancel()
            bounce:Destroy()
            bounce = nil
        end
    end

    local function close()
        if gone or not card.Visible then
            return
        end
        clear()
        local stamp = generation
        local closing = TweenService:Create(card, leave, { GroupTransparency = 1 })
        fade = closing
        closing.Completed:Once(function(state)
            if stamp == generation and state == Enum.PlaybackState.Completed then
                card.Visible = false
            end
        end)
        closing:Play()
    end
    dismiss.Activated:Connect(close)

    local api = {}

    function api.Show(result: Result)
        if gone or result.windCrystals == "" then
            return
        end
        clear()
        reward.Text = "+" .. result.windCrystals
        label.Text = result.unit or "Windkristalle"
        unlocked.Visible, line.Visible = result.ruinsUnlocked, result.ruinsUnlocked
        card.Size = size(1, -24, 0, if result.ruinsUnlocked then 149 else 112)
        local reduced = GuiService.ReducedMotionEnabled
        scale.Scale = if reduced then 1 else 0.955
        card.Visible, card.GroupTransparency = true, 0.20
        fade = TweenService:Create(card, appear, { GroupTransparency = 0 })
        fade:Play()
        if not reduced then
            bounce = TweenService:Create(scale, swell, { Scale = 1 })
            bounce:Play()
        end
        expiry = task.delay(if result.ruinsUnlocked then 5.2 else 3.8, function()
            expiry = nil
            close()
        end)
    end

    function api.Destroy()
        if gone then
            return
        end
        gone = true
        clear()
        screen:Destroy()
    end

    return api
end

return table.freeze({ Mount = mount })
