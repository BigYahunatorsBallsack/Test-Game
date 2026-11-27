--!strict
local GuiService = game:GetService("GuiService")
local Input = game:GetService("UserInputService")
local Art = require(script.Parent.Art)
local Trial = require(script.Parent.Trial)
local C = Art.c

local TrialPanel = {}
local icons = {
    hand = "icon_node_collect_hand",
    snapshot = "icon_node_luck_compass",
    all = "icon_node_collect_harvester",
}

function TrialPanel.mount(root, config)
    local backdrop = Art.box(root, "ProbelaufAuswahl", C.ink, 150)
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundTransparency = 0.18
    backdrop.Active = true
    backdrop.Visible = false
    local panel = Art.box(backdrop, "Tafel", C.panel, 151)
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.new(1, -16, 1, -16)
    panel.SelectionGroup = true
    panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
    panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
    panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
    panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
    Art.round(panel, 10)
    Art.edge(panel, C.brass, 2)
    Art.round(Art.surface(panel, "steel", 0.32), 10)
    local bounds = Instance.new("UISizeConstraint")
    bounds.MaxSize = Vector2.new(530, if config.trialOnly then 365 else 453)
    bounds.Parent = panel
    local title = Art.text(panel, "Titel", "Probelauf", 25, C.bright, true)
    title.Font = Art.font.title
    title.Position = UDim2.fromOffset(14, 6)
    title.Size = UDim2.new(1, -74, 0, 47)
    local close = Art.button(panel, "Schliessen", "×")
    close.TextSize = 24
    close.Position = UDim2.new(1, -56, 0, 8)
    close.Size = UDim2.fromOffset(44, 44)
    local summary = Art.text(panel, "Hinweis", "", 13, C.ivory, false)
    summary.Position = UDim2.fromOffset(14, 59)
    summary.Size = UDim2.new(1, -28, 0, 43)

    local list = Instance.new("ScrollingFrame")
    list.Name = "Startpunkte"
    list.Size = UDim2.new(1, -27, 1, -164)
    list.Position = UDim2.fromOffset(14, 106)
    list.ScrollBarImageColor3 = C.brass
    list.ScrollBarThickness = 4
    list.ScrollingDirection = Enum.ScrollingDirection.Y
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.CanvasSize = UDim2.new()
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.ZIndex = panel.ZIndex + 1
    list.Parent = panel
    local stack = Instance.new("UIListLayout")
    stack.SortOrder = Enum.SortOrder.LayoutOrder
    stack.Padding = UDim.new(0, 7)
    stack.Parent = list

    local resume = Art.button(panel, "Fortsetzen", "Fortsetzen")
    local live = Art.button(panel, "ZumSpielstand", "Zum Spielstand")
    live.Position = UDim2.new(0.5, 3, 1, -53)
    live.Size = UDim2.new(0.5, -17, 0, 44)
    local function dismiss()
        if not backdrop.Visible then
            return false
        end
        backdrop.Visible = false
        config.setOpen(false)
        return true
    end
    local buttons = {}
    for order, preset in Trial.presets do
        if config.trialOnly and preset.id == "snapshot" then
            continue
        end
        local row = Art.button(list, preset.id, "")
        row.LayoutOrder = order
        row.Size = UDim2.new(1, -6, 0, 78)
        local icon = Art.image(row, "Symbol")
        Art.icon(icon, nil, icons[preset.id])
        Art.rect(icon, 8, 9, 48, 48)
        local name = Art.text(row, "Name", preset.name, 15, C.bright, true)
        name.Position = UDim2.fromOffset(64, 5)
        name.Size = UDim2.new(1, -72, 0, 28)
        local caption = Art.text(row, "Beschreibung", preset.description, 12, C.ivory, false)
        caption.Position = UDim2.fromOffset(64, 33)
        caption.Size = UDim2.new(1, -72, 0, 40)
        buttons[preset.id] = row
        row.Activated:Connect(function()
            if dismiss() then
                config.start(preset.id)
            end
        end)
    end
    resume.Activated:Connect(function()
        if dismiss() then
            config.resume()
        end
    end)
    live.Activated:Connect(function()
        if dismiss() then
            config.leave()
        end
    end)
    close.Activated:Connect(dismiss)
    return {
        open = function(preset: string?, active: boolean)
            config.setOpen(true)
            local hasRun = preset ~= nil
            summary.Text = if hasRun
                then "Ein neuer Startpunkt ersetzt deinen bisherigen Probelauf."
                else "Wähle einen Startpunkt. Die Testmünzen gelten nur für diesen Probelauf."
            resume.Visible = hasRun
            resume.Position = UDim2.new(0, 14, 1, -53)
            local showLive = active and not config.trialOnly
            resume.Size =
                UDim2.new(if showLive then 0.5 else 1, if showLive then -17 else -28, 0, 44)
            live.Visible = showLive
            for id, row in buttons do
                row.UIStroke.Color = if preset == id then C.brass else C.edge
            end
            list.CanvasPosition = Vector2.zero
            backdrop.Visible = true
            if Input:GetLastInputType().Name:find("Gamepad") then
                GuiService.SelectedObject = if hasRun then resume else buttons.hand
            end
        end,
        dismiss = dismiss,
    }
end

return TrialPanel
