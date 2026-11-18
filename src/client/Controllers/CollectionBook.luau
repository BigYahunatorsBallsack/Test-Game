--!strict
-- CollectionBook-Controller (Paket 2.6)
-- Sammlungsbuch: Knopf "Sammlung" unten links (neben "Zonen"), Reiter je Zone, je Zone 6 Sets mit
-- 5 Slots. Ein gefundener Slot zeigt den Namen in der Farbe seiner Seltenheit, ein fehlender ein
-- "?" mit dem Rand seiner Seltenheit, damit man sieht, was noch fehlt. Je Set steht der Bonus,
-- oben der Gesamtbonus, unten die Belohnung des Zonenbuchs. Alle Werte kommen vom Server
-- (CollectionSync über State), der Client rechnet nichts Maßgebliches.
--
-- Das Fenster passt sich der Bildschirmbreite an (Größe in Anteilen, mit Obergrenze).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Darstellung
local BUTTON_POSITION = UDim2.new(0, 144, 1, -72)
local BUTTON_SIZE = UDim2.new(0, 140, 0, 48)
local PANEL_SCALE = Vector2.new(0.92, 0.82)
local PANEL_MAX_SIZE = Vector2.new(640, 520)
local PANEL_FADE_SECONDS = 0.18
local PANEL_EASING = Enum.EasingStyle.Quad
local TAB_HEIGHT = 36
local SET_ROW_HEIGHT = 78
local SET_ROW_GAP = 8
local SLOT_GAP = 6
local DIM_TRANSPARENCY = 0.55

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local ROW_COLOR = Color3.fromRGB(64, 52, 40)
local SLOT_COLOR = Color3.fromRGB(50, 41, 31)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local TAB_ACTIVE_COLOR = Color3.fromRGB(230, 200, 117)
local TAB_COLOR = Color3.fromRGB(80, 66, 52)
local DONE_COLOR = Color3.fromRGB(150, 220, 120)

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local Finds = loadShared("Data", "Finds")
local Rarities = loadShared("Data", "Rarities")
local Zones = loadShared("Data", "Zones")
local CollectionData = loadShared("Data", "Collection")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any

local CollectionBook = {}

local player = Players.LocalPlayer

local function percentText(bp: number): string
    local value = bp / 100
    local text = if value % 1 == 0 then tostring(math.floor(value)) else string.format("%.1f", value)
    local replaced = string.gsub(text, "%.", ",")
    return replaced
end

-- Funde je Zone und Set in Slot-Reihenfolge (aus Data/Finds, einmal gebaut).
local function buildLayout(): { [string]: { { set: any, finds: { any } } } }
    local perSet: { [string]: { any } } = {}
    for _, find in Finds.list do
        perSet[find.setId] = perSet[find.setId] or {}
        table.insert(perSet[find.setId], find)
    end
    local result: { [string]: { { set: any, finds: { any } } } } = {}
    for _, set in Finds.sets do
        result[set.zoneId] = result[set.zoneId] or {}
        table.insert(result[set.zoneId], { set = set, finds = perSet[set.id] or {} })
    end
    return result
end

local function newText(parent: Instance, position: UDim2, size: UDim2, font: Enum.Font, color: Color3, text: string, align: Enum.TextXAlignment?): TextLabel
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = position
    l.Size = size
    l.Font = font
    l.TextColor3 = color
    l.TextScaled = true
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = parent
    return l
end

function CollectionBook.Init() end

function CollectionBook.Start()
    local layout = buildLayout()
    local selectedZone: string = Zones.list[1].id

    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronCollection"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 6

    local openButton = Instance.new("TextButton")
    openButton.Name = "CollectionButton"
    openButton.Position = BUTTON_POSITION
    openButton.Size = BUTTON_SIZE
    openButton.BackgroundColor3 = PANEL_COLOR
    openButton.BackgroundTransparency = 0.25
    openButton.Font = Enum.Font.GothamBold
    openButton.TextColor3 = TEXT_COLOR
    openButton.TextScaled = true
    openButton.Text = "Sammlung"
    openButton.Parent = gui
    Instance.new("UICorner").Parent = openButton

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromScale(PANEL_SCALE.X, PANEL_SCALE.Y)
    panel.BackgroundColor3 = PANEL_COLOR
    panel.BackgroundTransparency = 0.1
    panel.Visible = false
    panel.Parent = gui
    Instance.new("UICorner").Parent = panel
    local constraint = Instance.new("UISizeConstraint")
    constraint.MaxSize = PANEL_MAX_SIZE
    constraint.Parent = panel

    local title = newText(panel, UDim2.new(0, 16, 0, 8), UDim2.new(0.5, -24, 0, 30), Enum.Font.GothamBold, TEXT_COLOR, "Sammlung")
    local bonusLabel = newText(panel, UDim2.new(0.5, 0, 0, 10), UDim2.new(0.5, -64, 0, 26), Enum.Font.GothamBold, DONE_COLOR, "", Enum.TextXAlignment.Right)
    title.Name = "Title"
    bonusLabel.Name = "Bonus"

    local closeButton = Instance.new("TextButton")
    closeButton.AnchorPoint = Vector2.new(1, 0)
    closeButton.Position = UDim2.new(1, -8, 0, 8)
    closeButton.Size = UDim2.new(0, 40, 0, 32)
    closeButton.BackgroundColor3 = TAB_COLOR
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextColor3 = TEXT_COLOR
    closeButton.TextScaled = true
    closeButton.Text = "X"
    closeButton.Parent = panel
    Instance.new("UICorner").Parent = closeButton

    -- Reiter je Zone
    local tabs = Instance.new("Frame")
    tabs.BackgroundTransparency = 1
    tabs.Position = UDim2.new(0, 12, 0, 46)
    tabs.Size = UDim2.new(1, -24, 0, TAB_HEIGHT)
    tabs.Parent = panel
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.Parent = tabs

    -- Inhalt: Sets als scrollbare Liste
    local scroll = Instance.new("ScrollingFrame")
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.Position = UDim2.new(0, 12, 0, 46 + TAB_HEIGHT + 8)
    scroll.Size = UDim2.new(1, -24, 1, -(46 + TAB_HEIGHT + 8 + 52))
    scroll.CanvasSize = UDim2.new(0, 0, 0, 6 * (SET_ROW_HEIGHT + SET_ROW_GAP))
    scroll.ScrollBarThickness = 6
    scroll.Parent = panel

    local bookLabel = newText(panel, UDim2.new(0, 16, 1, -44), UDim2.new(1, -32, 0, 34), Enum.Font.GothamBold, MUTED_COLOR, "")
    bookLabel.Name = "Book"

    local tabButtons: { [string]: TextButton } = {}
    local setRows: { { frame: Frame, label: TextLabel, bonus: TextLabel, slots: { { frame: Frame, name: TextLabel, stroke: UIStroke } } } } = {}

    for _, zone in Zones.list do
        local tab = Instance.new("TextButton")
        tab.Name = zone.id
        tab.Size = UDim2.new(0.2, -4, 1, 0)
        tab.BackgroundColor3 = TAB_COLOR
        tab.Font = Enum.Font.GothamBold
        tab.TextColor3 = TEXT_COLOR
        tab.TextScaled = true
        tab.Text = zone.name
        tab.Parent = tabs
        Instance.new("UICorner").Parent = tab
        tabButtons[zone.id] = tab
    end

    for index = 1, 6 do
        local frame = Instance.new("Frame")
        frame.Position = UDim2.new(0, 0, 0, (index - 1) * (SET_ROW_HEIGHT + SET_ROW_GAP))
        frame.Size = UDim2.new(1, -10, 0, SET_ROW_HEIGHT)
        frame.BackgroundColor3 = ROW_COLOR
        frame.BackgroundTransparency = 0.2
        frame.Parent = scroll
        Instance.new("UICorner").Parent = frame
        local label = newText(frame, UDim2.new(0, 10, 0, 4), UDim2.new(0.5, -10, 0, 20), Enum.Font.GothamBold, TEXT_COLOR, "")
        local bonus = newText(frame, UDim2.new(0.5, 0, 0, 4), UDim2.new(0.5, -10, 0, 20), Enum.Font.GothamBold, MUTED_COLOR, "", Enum.TextXAlignment.Right)
        local slotHolder = Instance.new("Frame")
        slotHolder.BackgroundTransparency = 1
        slotHolder.Position = UDim2.new(0, 8, 0, 28)
        slotHolder.Size = UDim2.new(1, -16, 1, -34)
        slotHolder.Parent = frame
        local slotLayout = Instance.new("UIListLayout")
        slotLayout.FillDirection = Enum.FillDirection.Horizontal
        slotLayout.Padding = UDim.new(0, SLOT_GAP)
        slotLayout.Parent = slotHolder
        local slots = {}
        for slot = 1, 5 do
            local slotFrame = Instance.new("Frame")
            slotFrame.Size = UDim2.new(0.2, -SLOT_GAP, 1, 0)
            slotFrame.BackgroundColor3 = SLOT_COLOR
            slotFrame.Parent = slotHolder
            Instance.new("UICorner").Parent = slotFrame
            local stroke = Instance.new("UIStroke")
            stroke.Thickness = 2
            stroke.Parent = slotFrame
            local name = newText(slotFrame, UDim2.new(0, 4, 0, 2), UDim2.new(1, -8, 1, -4), Enum.Font.GothamBold, TEXT_COLOR, "?", Enum.TextXAlignment.Center)
            slots[slot] = { frame = slotFrame, name = name, stroke = stroke }
        end
        setRows[index] = { frame = frame, label = label, bonus = bonus, slots = slots }
    end

    local function refresh()
        local collection = State.getCollection()
        local counts = if collection ~= nil then collection.counts else {}
        local bonusBp = if collection ~= nil then collection.bonusBp else 0
        local books = if collection ~= nil then collection.books else {}
        bonusLabel.Text = `Sammlungsbonus: +{percentText(bonusBp)} %`

        local snapshot = State.get()
        for _, zone in Zones.list do
            local tab = tabButtons[zone.id]
            local unlocked = snapshot ~= nil and type(snapshot.zonesUnlocked) == "table" and snapshot.zonesUnlocked[zone.id] == true
            tab.BackgroundColor3 = if zone.id == selectedZone then TAB_ACTIVE_COLOR else TAB_COLOR
            tab.TextColor3 = if zone.id == selectedZone then PANEL_COLOR else TEXT_COLOR
            tab.TextTransparency = if unlocked then 0 else 0.4 -- gesperrte Zonen bleiben sichtbar, nur matter
        end

        local zoneLayout = layout[selectedZone] or {}
        local completeSets = 0
        for index, row in setRows do
            local entry = zoneLayout[index]
            row.frame.Visible = entry ~= nil
            if entry ~= nil then
                local have = 0
                for slot, slotRow in row.slots do
                    local find = entry.finds[slot]
                    local rarity = if find ~= nil then Rarities.byId[find.rarityId] else nil
                    local color = if rarity ~= nil then Color3.fromHex(rarity.colorHex) else MUTED_COLOR
                    slotRow.stroke.Color = color
                    local count = if find ~= nil then counts[find.id] else nil
                    local found = type(count) == "number" and count > 0
                    if found then
                        have += 1
                        slotRow.name.Text = find.name
                        slotRow.name.TextColor3 = color
                    else
                        slotRow.name.Text = "?"
                        slotRow.name.TextColor3 = MUTED_COLOR
                    end
                end
                local complete = have >= entry.set.size
                if complete then
                    completeSets += 1
                end
                row.label.Text = `Set {entry.set.index}: {have}/{entry.set.size}`
                row.label.TextColor3 = if complete then DONE_COLOR else TEXT_COLOR
                row.bonus.Text = `+{percentText(CollectionData.setBonusBp[entry.set.index] or 0)} %{if complete then " fertig" else ""}`
                row.bonus.TextColor3 = if complete then DONE_COLOR else MUTED_COLOR
            end
        end

        local book = CollectionData.zoneBooksByZone[selectedZone]
        if book ~= nil then
            if books[selectedZone] == true then
                bookLabel.Text = `Zonenbuch fertig: Titel „{book.title}", Skin {book.toolSkinId}`
                bookLabel.TextColor3 = DONE_COLOR
            else
                bookLabel.Text = `Zonenbuch: Titel „{book.title}" und Werkzeug-Skin ({completeSets}/6 Sets)`
                bookLabel.TextColor3 = MUTED_COLOR
            end
        end
    end

    for zoneId, tab in tabButtons do
        tab.Activated:Connect(function()
            selectedZone = zoneId
            scroll.CanvasPosition = Vector2.zero
            refresh()
        end)
    end

    local fade = TweenInfo.new(PANEL_FADE_SECONDS, PANEL_EASING)
    local function setOpen(open: boolean)
        panel.Visible = open
        if open then
            panel.BackgroundTransparency = 1
            TweenService:Create(panel, fade, { BackgroundTransparency = 0.1 }):Play()
            -- Das Buch startet in der aktuellen Zone des Spielers.
            local snapshot = State.get()
            if snapshot ~= nil and layout[snapshot.zoneId] ~= nil then
                selectedZone = snapshot.zoneId
            end
            refresh()
        end
    end
    openButton.Activated:Connect(function()
        setOpen(not panel.Visible)
    end)
    closeButton.Activated:Connect(function()
        setOpen(false)
    end)

    gui.Parent = player:WaitForChild("PlayerGui")

    State.onCollectionChanged(function()
        if panel.Visible then
            refresh()
        end
    end)
    State.onChanged(function()
        if panel.Visible then
            refresh()
        end
    end)
end

return CollectionBook
