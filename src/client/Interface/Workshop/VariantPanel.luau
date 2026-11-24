--!strict
local GuiService = game:GetService("GuiService")
local Input = game:GetService("UserInputService")
local Art = require(script.Parent.Art)
local Preview = require(script.Parent.Preview)
local C = Art.c

local VariantPanel = {}

function VariantPanel.mount(root, config)
    local backdrop = Art.box(root, "Variantenvergleich", C.ink, 150)
    backdrop.BackgroundTransparency = 0.18
    backdrop.Active = true
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.Visible = false
    local panel = Art.box(backdrop, "Tafel", C.panel, 151)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Size = UDim2.new(1, -16, 1, -18)
    panel.SelectionGroup = true
    panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
    panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
    panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
    panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
    local bounds = Instance.new("UISizeConstraint")
    bounds.MaxSize = Vector2.new(860, 645)
    bounds.Parent = panel
    Art.edge(panel, C.brass, 2)
    Art.round(panel, 10)

    local heading = Art.text(panel, "Titel", "", 24, C.bright, true)
    heading.Font = Enum.Font.Antique
    heading.Position = UDim2.fromOffset(16, 6)
    heading.Size = UDim2.new(1, -79, 0, 46)
    local close = Art.button(panel, "Schliessen", "×")
    close.TextSize = 24
    close.Position = UDim2.new(1, -56, 0, 8)
    close.Size = UDim2.fromOffset(44, 44)
    local replay = Art.button(panel, "Abspielen", "Beide Vorschauen starten")
    replay.Position = UDim2.new(0, 14, 1, -57)
    replay.Size = UDim2.new(1, -28, 0, 44)
    local cards = Instance.new("ScrollingFrame")
    cards.Name = "Varianten"
    cards.Position = UDim2.fromOffset(14, 58)
    cards.Size = UDim2.new(1, -28, 1, -124)
    cards.CanvasSize = UDim2.new()
    cards.AutomaticCanvasSize = Enum.AutomaticSize.Y
    cards.ScrollingDirection = Enum.ScrollingDirection.Y
    cards.ScrollBarThickness = 5
    cards.ScrollBarImageColor3 = C.brass
    cards.BackgroundTransparency = 1
    cards.BorderSizePixel = 0
    cards.ZIndex = panel.ZIndex + 1
    cards.Parent = panel
    local grid = Instance.new("UIGridLayout")
    grid.CellPadding = UDim2.fromOffset(12, 10)
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = cards

    local openPage
    local cardsById = {}
    local function resize()
        local availableWidth = cards.AbsoluteSize.X
        local wide = availableWidth >= 595
        local cardWidth = if wide then availableWidth * 0.5 - 7 else availableWidth - 7
        local imageHeight = math.clamp(math.floor((cardWidth - 24) * 2 / 3), 128, 252)
        grid.CellSize = if wide
            then UDim2.new(0.5, -7, 0, imageHeight + 245)
            else UDim2.new(1, -7, 0, imageHeight + 245)
        grid.FillDirectionMaxCells = if wide then 2 else 1
        heading.TextSize = if wide then 24 else 18
    end
    cards:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
    local function clear()
        for _, entry in cardsById do
            entry.preview.clear()
            entry.frame:Destroy()
        end
        table.clear(cardsById)
    end
    local function pressPreview()
        if openPage then
            for _, entry in cardsById do
                entry.preview.show(
                    openPage.id,
                    entry.variant,
                    GuiService.ReducedMotionEnabled,
                    entry.accent
                )
            end
        end
    end
    local function dismiss()
        if not openPage then
            return false
        end
        openPage = nil
        backdrop.Visible = false
        clear()
        config.setOpen(false)
        return true
    end
    local function refresh()
        for id, entry in cardsById do
            local status, color = config.statusText(config.book.byId[id])
            entry.status.Text = status
            entry.status.TextColor3 = color
        end
    end
    local function newCard(page, node, index)
        local accent = if index == 1 then C.bright else C.leaf
        local variant = node.sprite % 4 + 1
        local shell = Art.box(cards, node.id, C.ink, 153)
        shell.LayoutOrder = index
        Art.round(shell, 7)
        Art.edge(shell, C.edge, 1.5)
        local icon = Art.image(shell, "Motiv")
        Art.nodeIcon(icon, node)
        Art.rect(icon, 10, 8, 48, 48)
        Art.round(icon, 5)
        local name = Art.text(shell, "Name", node.name, 23, accent, true)
        name.Font = Enum.Font.Antique
        name.Position = UDim2.fromOffset(68, 7)
        name.Size = UDim2.new(1, -80, 0, 50)

        local scene = Art.image(shell, "Ego")
        Art.scene(scene, page.row, variant)
        scene.Position = UDim2.fromOffset(12, 64)
        scene.Size = UDim2.new(1, -24, 1, -245)
        scene.ClipsDescendants = true
        Art.round(scene, 5)
        local function label(key, value, fromBottom, height, size, color)
            local item = Art.text(shell, key, value, size, color, false)
            item.Position = UDim2.new(0, 12, 1, -fromBottom)
            item.Size = UDim2.new(1, -24, 0, height)
            return item
        end
        label("Wirkung", node.description, 174, 64, 14, C.ivory).TextYAlignment =
            Enum.TextYAlignment.Top
        local status = label("Status", "", 107, 22, 13, C.bright)
        local requirement = config.book.byId[node.requires[1]]
        if requirement then
            label("Voraussetzung", "Setzt " .. requirement.name .. " voraus", 86, 23, 12, C.mute)
        end
        local view = Art.button(shell, "ZumKnoten", "Zum Knoten")
        view.Position = UDim2.new(0, 12, 1, -54)
        view.Size = UDim2.new(1, -24, 0, 44)
        view.Activated:Connect(function()
            if dismiss() then
                config.choose(node)
            end
        end)
        cardsById[node.id] = {
            frame = shell,
            preview = Preview.new(scene),
            variant = variant,
            accent = accent,
            status = status,
        }
    end

    close.Activated:Connect(dismiss)
    replay.Activated:Connect(pressPreview)
    backdrop.Destroying:Connect(clear)
    return {
        open = function(page)
            if openPage then
                return
            end
            openPage = page
            config.setOpen(true)
            heading.Text = page.name .. " · Varianten"
            backdrop.Visible = true
            resize()
            cards.CanvasPosition = Vector2.zero
            for index, id in page.variants do
                newCard(page, config.book.byId[id], index)
            end
            refresh()
            pressPreview()
            if Input:GetLastInputType().Name:find("Gamepad") then
                GuiService.SelectedObject = replay
            end
        end,
        dismiss = dismiss,
        refresh = refresh,
    }
end

return VariantPanel
