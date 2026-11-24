--!strict
local GuiService = game:GetService("GuiService")
local Input = game:GetService("UserInputService")
local Art = require(script.Parent.Art)
local Search = require(script.Parent.Search)
local C = Art.c
local RESULT_LIMIT = 30

local SearchPanel = {}

function SearchPanel.mount(root, config)
    local index = Search.build(config.book.tabs, config.kinds)
    local backdrop = Art.box(root, "Upgradesuche", C.ink, 150)
    backdrop.BackgroundTransparency = 0.18
    backdrop.Active = true
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.Visible = false
    local card = Art.box(backdrop, "Suchkarte", C.panel, 151)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.new(1, -16, 1, -20)
    card.SelectionGroup = true
    card.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
    card.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
    card.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
    card.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
    local bounds = Instance.new("UISizeConstraint")
    bounds.MaxSize = Vector2.new(540, 575)
    bounds.Parent = card
    Art.round(card, 10)
    Art.edge(card, C.brass, 2)

    local close = Art.button(card, "Schliessen", "×")
    close.TextSize = 24
    close.Position = UDim2.new(1, -56, 0, 8)
    close.Size = UDim2.fromOffset(44, 44)
    local heading = Art.text(card, "Titel", "Upgrades finden", 24, C.bright, true)
    heading.Font = Enum.Font.Antique
    heading.Position = UDim2.fromOffset(14, 8)
    heading.Size = UDim2.new(1, -74, 0, 44)

    local field = Instance.new("TextBox")
    field.Name = "Suchfeld"
    field.Text = ""
    field.ClearTextOnFocus = false
    field.PlaceholderText = "Name, Gerät oder Art"
    field.PlaceholderColor3 = C.mute
    field.TextColor3 = C.ivory
    field.TextSize = 16
    field.Font = Enum.Font.GothamMedium
    field.TextXAlignment = Enum.TextXAlignment.Left
    field.BackgroundColor3 = C.ink
    field.BorderSizePixel = 0
    field.Position = UDim2.fromOffset(14, 58)
    field.Size = UDim2.new(1, -28, 0, 48)
    field.ZIndex = card.ZIndex + 1
    field.Parent = card
    Art.round(field, 6)
    local outline = Art.edge(field, C.edge, 2)
    local inset = Instance.new("UIPadding")
    inset.PaddingLeft = UDim.new(0, 10)
    inset.PaddingRight = UDim.new(0, 10)
    inset.Parent = field

    local feedback = Art.text(card, "Treffer", "", 13, C.mute, false)
    feedback.Position = UDim2.fromOffset(14, 112)
    feedback.Size = UDim2.new(1, -28, 0, 38)
    local list = Instance.new("ScrollingFrame")
    list.Name = "Ergebnisse"
    list.BorderSizePixel = 0
    list.BackgroundTransparency = 1
    list.ScrollingDirection = Enum.ScrollingDirection.Y
    list.ScrollBarImageColor3 = C.brass
    list.ScrollBarThickness = 5
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.CanvasSize = UDim2.fromOffset(0, 0)
    list.Position = UDim2.fromOffset(14, 157)
    list.Size = UDim2.new(1, -28, 1, -170)
    list.ZIndex = card.ZIndex + 1
    list.Parent = card
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = list

    local results: { string } = {}
    local statusLabels: { [string]: any } = {}
    local function dismiss()
        if not backdrop.Visible then
            return false
        end
        backdrop.Visible = false
        field:ReleaseFocus()
        config.setOpen(false)
        return true
    end
    local function choose(id)
        if id and dismiss() then
            config.choose(config.book.byId[id])
        end
    end
    local function render()
        if not backdrop.Visible then
            return
        end
        for _, child in list:GetChildren() do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        table.clear(statusLabels)
        local matches, total = Search.find(index, string.sub(field.Text, 1, 128), RESULT_LIMIT)
        results = matches
        feedback.Text = if not string.find(field.Text, "%S")
            then "Zum Beispiel Tiefenkante II oder Förderband."
            elseif total == 0 then "Keine passenden Upgrades gefunden."
            elseif total > RESULT_LIMIT then "Die ersten "
                .. RESULT_LIMIT
                .. " von "
                .. total
                .. " Treffern"
            elseif total == 1 then "1 Treffer"
            else total .. " Treffer"
        list.CanvasPosition = Vector2.zero
        for order, id in results do
            local node = config.book.byId[id]
            local button = Art.button(list, id, "")
            button.LayoutOrder = order
            button.Size = UDim2.new(1, -8, 0, 54)
            local icon = Art.image(button, "Motiv")
            Art.rect(icon, 6, 6, 42, 42)
            Art.nodeIcon(icon, node)
            local name = Art.text(button, "Name", node.name, 15, C.ivory, true)
            name.Position = UDim2.fromOffset(54, 3)
            name.Size = UDim2.new(1, -64, 0, 24)
            local context = Art.text(button, "Status", "", 12, C.mute, false)
            context.Position = UDim2.fromOffset(54, 28)
            context.Size = UDim2.new(1, -64, 0, 21)
            statusLabels[id] = context
            button.Activated:Connect(function()
                choose(id)
            end)
        end
    end
    local function refresh()
        if backdrop.Visible then
            for id, label in statusLabels do
                local node = config.book.byId[id]
                label.Text = config.book.byTab[node.page].name
                    .. "  ·  "
                    .. config.statusText(node)
            end
        end
    end
    field:GetPropertyChangedSignal("Text"):Connect(function()
        render()
        refresh()
    end)
    field.Focused:Connect(function()
        outline.Color = C.bright
    end)
    field.FocusLost:Connect(function(enterPressed)
        outline.Color = C.edge
        if enterPressed then
            choose(results[1])
        end
    end)
    close.Activated:Connect(dismiss)
    return {
        open = function()
            config.setOpen(true)
            backdrop.Visible = true
            render()
            refresh()
            local method = Input:GetLastInputType()
            if method.Name:find("Gamepad") then
                GuiService.SelectedObject = field
            elseif method ~= Enum.UserInputType.Touch then
                field:CaptureFocus()
            end
        end,
        dismiss = dismiss,
        refresh = refresh,
    }
end

return SearchPanel
