--!strict
-- CollectionBook-Controller (Paket 2.6, Handy-Durchgang 3.6)
-- Sammlungsbuch: Knopf "Sammlung" in der Menüleiste (Controllers/Screen), Reiter je Zone (44 px hoch,
-- seitlich scrollbar), Fundnamen umbrechen auf zwei Zeilen, je Zone 6 Sets mit
-- 5 Slots. Ein gefundener Slot zeigt den Namen in der Farbe seiner Seltenheit, ein fehlender ein
-- "?" mit dem Rand seiner Seltenheit, damit man sieht, was noch fehlt. Je Set steht der Bonus,
-- oben der Gesamtbonus, unten die Belohnung des Zonenbuchs. Alle Werte kommen vom Server
-- (CollectionSync über State), der Client rechnet nichts Maßgebliches.
--
-- Das Fenster passt sich dem Bildschirm an (Controllers/Screen, Art "wide"), die Sets scrollen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Darstellung
local MENU_ORDER = 2 -- Platz in der Menüleiste (nach den Zonen)
local TAB_WIDTH = 112
local TAB_GAP = 6
local FOOTER_HEIGHT = 58
local SET_ROW_HEIGHT = 118 -- Ü5: Platz für die Fund-Bilder
local SLOT_GAP = 6
local SLOT_MIN_TEXT = 11
local SLOT_MAX_TEXT = 13
local TAB_SCROLL_MARGIN = 8

local Theme = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("Theme") :: ModuleScript) :: any -- Ü5: ein Stil
local UI = Theme.ui
local Kit = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("Kit") :: ModuleScript) :: any
local Icons = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("Icons") :: ModuleScript) :: any
local ICON_SHARE = 0.62 -- Anteil der Platzhöhe für das Bild (Ü5)

-- Farben aus Interface/Theme (Ü5)
local PANEL_COLOR = UI.panel
local ROW_COLOR = UI.row
local SLOT_COLOR = UI.slot
local TEXT_COLOR = UI.text
local MUTED_COLOR = UI.muted
local TAB_ACTIVE_COLOR = UI.accent
local TAB_COLOR = UI.button
local DONE_COLOR = UI.good

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local Finds = loadShared("Data", "Finds")
local Rarities = loadShared("Data", "Rarities")
local Zones = loadShared("Data", "Zones")
local CollectionData = loadShared("Data", "Collection")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

local CollectionBook = {}

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

    local controls = Screen.controls()
    local refresh: () -> () = function() end
    local window = Screen.createWindow({
        name = "CollectionWindow",
        title = "Sammlung",
        kind = "wide",
        subHeight = controls.tabH + 4,
        footerHeight = FOOTER_HEIGHT,
        onOpen = function()
            -- Das Buch startet in der aktuellen Zone des Spielers.
            local snapshot = State.get()
            if snapshot ~= nil and layout[snapshot.zoneId] ~= nil then
                selectedZone = snapshot.zoneId
            end
            refresh()
        end,
    })
    local openButton = Screen.addMenuButton("CollectionButton", "Sammlung", MENU_ORDER)

    -- Gesamtbonus und Zonenbuch im festen Fuß, damit sie beim Scrollen der Sets stehen bleiben.
    local bonusLabel = newText(window.footer, UDim2.new(0, 12, 0, 2), UDim2.new(1, -24, 0, 22), Theme.font.bold, DONE_COLOR, "")
    bonusLabel.Name = "Bonus"
    local bookLabel = newText(window.footer, UDim2.new(0, 12, 0, 26), UDim2.new(1, -24, 0, 30), Theme.font.bold, MUTED_COLOR, "")
    bookLabel.Name = "Book"
    bookLabel.TextWrapped = true

    -- Reiter je Zone, seitlich scrollbar
    local tabs = Instance.new("ScrollingFrame")
    tabs.Name = "Tabs"
    tabs.BackgroundTransparency = 1
    tabs.BorderSizePixel = 0
    tabs.Size = UDim2.fromScale(1, 1)
    tabs.CanvasSize = UDim2.new()
    tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
    tabs.ScrollingDirection = Enum.ScrollingDirection.X
    tabs.ScrollBarThickness = 0
    tabs.Parent = window.sub
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, TAB_GAP)
    tabLayout.Parent = tabs

    local scroll = window.body

    local tabButtons: { [string]: TextButton } = {}
    local setRows: { { frame: Frame, label: TextLabel, bonus: TextLabel, slots: { { frame: Frame, name: TextLabel, stroke: UIStroke } } } } = {}

    for index, zone in Zones.list do
        local tab = Instance.new("TextButton")
        Kit.flat(tab)
        tab.Name = zone.id
        tab.LayoutOrder = index
        tab.Size = UDim2.fromOffset(TAB_WIDTH, controls.tabH)
        tab.BackgroundColor3 = TAB_COLOR
        tab.Font = Theme.font.bold
        tab.TextColor3 = TEXT_COLOR
        tab.TextScaled = true
        tab.Text = zone.name
        tab.Parent = tabs
        Instance.new("UICorner").Parent = tab
        local tabPadding = Instance.new("UIPadding")
        tabPadding.PaddingTop = UDim.new(0, 8)
        tabPadding.PaddingBottom = UDim.new(0, 8)
        tabPadding.PaddingLeft = UDim.new(0, 6)
        tabPadding.PaddingRight = UDim.new(0, 6)
        tabPadding.Parent = tab
        tabButtons[zone.id] = tab
    end

    for index = 1, 6 do
        local frame = Instance.new("Frame")
        frame.LayoutOrder = index
        frame.Size = UDim2.new(1, 0, 0, SET_ROW_HEIGHT)
        frame.BackgroundColor3 = ROW_COLOR
        frame.BackgroundTransparency = 0.2
        frame.Parent = scroll
        Instance.new("UICorner").Parent = frame
        local label = newText(frame, UDim2.new(0, 10, 0, 4), UDim2.new(0.5, -10, 0, 20), Theme.font.bold, TEXT_COLOR, "")
        local bonus = newText(frame, UDim2.new(0.5, 0, 0, 4), UDim2.new(0.5, -10, 0, 20), Theme.font.bold, MUTED_COLOR, "", Enum.TextXAlignment.Right)
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
            -- Ü5: Bild des Fundstücks (Atlas), fehlende als dunkle Silhouette; Name darunter.
            local picture = Instance.new("ImageLabel")
            picture.Name = "Icon"
            picture.BackgroundTransparency = 1
            picture.AnchorPoint = Vector2.new(0.5, 0)
            picture.Position = UDim2.new(0.5, 0, 0, 2)
            picture.Size = UDim2.new(1, -6, ICON_SHARE, -2)
            picture.ScaleType = Enum.ScaleType.Fit
            picture.Parent = slotFrame
            local name = newText(slotFrame, UDim2.new(0, 3, ICON_SHARE, 0), UDim2.new(1, -6, 1 - ICON_SHARE, -2), Theme.font.bold, TEXT_COLOR, "?", Enum.TextXAlignment.Center)
            -- Lange Namen brechen auf zwei Zeilen um und werden nicht winzig.
            name.TextWrapped = true
            local nameConstraint = Instance.new("UITextSizeConstraint")
            nameConstraint.MinTextSize = SLOT_MIN_TEXT
            nameConstraint.MaxTextSize = SLOT_MAX_TEXT
            nameConstraint.Parent = name
            slots[slot] = { frame = slotFrame, name = name, stroke = stroke, picture = picture }
        end
        setRows[index] = { frame = frame, label = label, bonus = bonus, slots = slots }
    end

    refresh = function()
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
                    if find ~= nil and type(find.icon) == "string" then
                        pcall(Icons.Set, slotRow.picture, find.icon)
                        slotRow.picture.Visible = true
                        slotRow.picture.ImageColor3 = if found then UI.white else UI.black
                        slotRow.picture.ImageTransparency = if found then 0 else 0.45
                    else
                        slotRow.picture.Visible = false
                    end
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

    -- Der gewählte Reiter bleibt im sichtbaren Streifen.
    local function showSelectedTab()
        local tab = tabButtons[selectedZone]
        if tab == nil then
            return
        end
        local left = tab.AbsolutePosition.X - tabs.AbsolutePosition.X + tabs.CanvasPosition.X
        local right = left + tab.AbsoluteSize.X
        local visibleWidth = tabs.AbsoluteSize.X
        local position = tabs.CanvasPosition.X
        if left - TAB_SCROLL_MARGIN < position then
            position = math.max(left - TAB_SCROLL_MARGIN, 0)
        elseif right + TAB_SCROLL_MARGIN > position + visibleWidth then
            position = right + TAB_SCROLL_MARGIN - visibleWidth
        end
        tabs.CanvasPosition = Vector2.new(position, 0)
    end

    for zoneId, tab in tabButtons do
        tab.Activated:Connect(function()
            selectedZone = zoneId
            scroll.CanvasPosition = Vector2.zero
            refresh()
            showSelectedTab()
        end)
    end

    openButton.Activated:Connect(window.toggle)

    State.onCollectionChanged(function()
        if window.isOpen() then
            refresh()
        end
    end)
    State.onChanged(function()
        if window.isOpen() then
            refresh()
        end
    end)
end

return CollectionBook
