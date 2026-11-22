--!strict
-- A visual confirmation for a sale that has already succeeded.
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)

local px, size = UDim2.fromOffset, UDim2.new
local center = Vector2.new(0.5, 0.5)
local pop = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local fadeIn = TweenInfo.new(0.14, Enum.EasingStyle.Quad)
local fadeOut = TweenInfo.new(0.25, Enum.EasingStyle.Sine)
local emerge = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local arrive = TweenInfo.new(0.44, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local scatter = {
    Vector2.new(-67, -39),
    Vector2.new(-35, -68),
    Vector2.new(3, -78),
    Vector2.new(43, -66),
    Vector2.new(71, -38),
}

local function make(class: string, name: string, parent: Instance): any
    local node = Instance.new(class)
    node.Name, node.Parent = name, parent
    return node
end

local function coin(parent: Instance, name: string, side: number): ImageLabel
    local item = make("ImageLabel", name, parent) :: ImageLabel
    item.Size, item.AnchorPoint, item.BackgroundTransparency = px(side, side), center, 1
    item.ScaleType = Enum.ScaleType.Fit
    Icons.Set(item, "icon_currency_coin")
    return item
end

local function mount(gui: PlayerGui)
    local layer = make("ScreenGui", "DuneBaronSaleFeedback", gui) :: ScreenGui
    layer.DisplayOrder = 33
    layer.ResetOnSpawn = false
    layer.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    layer.ClipToDeviceSafeArea = true
    local area = make("Frame", "SafeArea", layer) :: Frame
    area.BackgroundTransparency, area.Size = 1, size(1, 0, 1, 0)
    area.Active = false

    local card = make("CanvasGroup", "SaleCard", area) :: CanvasGroup
    card.Size, card.Position, card.AnchorPoint = size(1, -24, 0, 74), size(0.5, 0, 0.66, 0), center
    card.Visible, card.Active = false, false
    make("UICorner", "CardCorners", card).CornerRadius = UDim.new(0, 13)
    make("UISizeConstraint", "CardBounds", card).MaxSize = Vector2.new(282, 74)
    Theme.Paint(card, Theme.panel, 3)
    local rim = card:FindFirstChild("ColorRim") :: UIStroke
    rim.Color = Theme.gold.rim
    local scale = make("UIScale", "CardScale", card) :: UIScale
    local badge = coin(card, "CoinBadge", 57)
    badge.Position = size(0, 37, 0.5, 0)

    local amount = make("TextLabel", "Amount", card) :: TextLabel
    amount.Position, amount.Size, amount.BackgroundTransparency = px(72, 10), size(1, -84, 0, 31), 1
    amount.TextXAlignment, amount.TextScaled = Enum.TextXAlignment.Left, true
    local textBounds = make("UITextSizeConstraint", "TextBounds", amount) :: UITextSizeConstraint
    textBounds.MinTextSize, textBounds.MaxTextSize = 13, 30
    Theme.Lettering(amount, 2.4)
    amount.TextColor3 = Theme.gold.rim
    local unit = make("TextLabel", "Unit", card) :: TextLabel
    unit.Position, unit.Size, unit.BackgroundTransparency = px(73, 42), size(1, -85, 0, 20), 1
    unit.TextXAlignment, unit.TextSize, unit.Text = Enum.TextXAlignment.Left, 15, "Münzen"
    Theme.Lettering(unit, 1.5)

    local flying: { ImageLabel } = {}
    for i = 1, #scatter do
        local particle = coin(area, "CoinBurst" .. i, 26)
        particle.Visible, particle.ZIndex = false, 5
        table.insert(flying, particle)
    end
    local running: { Tween } = {}
    local expiry: thread?
    local token = 0
    local destroyed = false

    local function clear()
        token += 1
        if expiry then
            task.cancel(expiry)
            expiry = nil
        end
        for _, motion in running do
            motion:Cancel()
            motion:Destroy()
        end
        table.clear(running)
        for _, sparkle in flying do
            sparkle.Visible = false
        end
    end

    local function animate(target: Instance, timing: TweenInfo, goal: { [string]: any }): Tween
        local frame = TweenService:Create(target, timing, goal)
        table.insert(running, frame)
        frame:Play()
        return frame
    end

    local function inArea(at: Vector2, edge: number): Vector2
        local bounds = area.AbsoluteSize
        return Vector2.new(
            math.clamp(at.X, edge, math.max(edge, bounds.X - edge)),
            math.clamp(at.Y, edge, math.max(edge, bounds.Y - edge))
        )
    end

    local api = {}

    function api.Show(earnedText: string, coinCounter: GuiObject?)
        if destroyed or earnedText == "" then
            return
        end
        clear()
        local stamp = token
        local reduced = GuiService.ReducedMotionEnabled
        amount.Text = "+" .. earnedText
        card.Visible, card.GroupTransparency = true, 0.22
        scale.Scale = if reduced then 1 else 0.91
        animate(card, fadeIn, { GroupTransparency = 0 })

        if not reduced then
            animate(scale, pop, { Scale = 1 })
            local origin = badge.AbsolutePosition + badge.AbsoluteSize * 0.5 - area.AbsolutePosition
            if area.AbsoluteSize.X > 0 and area.AbsoluteSize.Y > 0 then
                origin = inArea(origin, 15)
                for i, sparkle in flying do
                    local arc = inArea(origin + scatter[i], 15)
                    sparkle.Position, sparkle.Rotation = px(origin.X, origin.Y), 11 * (i - 3)
                    sparkle.Size, sparkle.Visible, sparkle.ImageTransparency = px(26, 26), true, 0
                    local first = animate(sparkle, emerge, { Position = px(arc.X, arc.Y) })
                    first.Completed:Once(function(state)
                        if token ~= stamp or state ~= Enum.PlaybackState.Completed then
                            return
                        end
                        local goal = inArea(arc + Vector2.new(0, -29), 12)
                        if coinCounter and coinCounter.Parent and coinCounter.Visible then
                            goal = inArea(
                                coinCounter.AbsolutePosition
                                    + coinCounter.AbsoluteSize * 0.5
                                    - area.AbsolutePosition,
                                9
                            )
                        end
                        animate(sparkle, arrive, {
                            Position = px(goal.X, goal.Y),
                            Size = px(9, 9),
                            ImageTransparency = 1,
                        }).Completed:Once(function()
                            if token == stamp then
                                sparkle.Visible = false
                            end
                        end)
                    end)
                end
            end
        end

        expiry = task.delay(1.30, function()
            expiry = nil
            if token ~= stamp then
                return
            end
            animate(card, fadeOut, { GroupTransparency = 1 }).Completed:Once(function()
                if token == stamp then
                    card.Visible = false
                end
            end)
        end)
    end

    function api.Destroy()
        if destroyed then
            return
        end
        destroyed = true
        clear()
        layer:Destroy()
    end

    return api
end

return table.freeze({ Mount = mount })
