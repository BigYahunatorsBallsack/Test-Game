--!strict
-- EquipmentMenu-Controller (Paket 4.3)
-- Knopf "Ausrüstung" in der Menüleiste (Controllers/Screen) und ein Fenster mit drei Reitern: Skins,
-- Begleiter, Werkzeuge. Jede Karte zeigt ein besessenes Kisten-Item mit Name (Seltenheitsfarbe), Stern,
-- Bonus auf die Sammelrate, Zahl der Exemplare und den Knöpfen "Ausrüsten"/"Abnehmen" und
-- "Verschmelzen". Im Fuß steht der Gesamtbonus aller ausgerüsteten Items.
--
-- Der Client rechnet nur für die Anzeige (Bonus aus Logic/Equipment, derselben Tabelle wie der Server).
-- Er schickt `EquipItem(slot, itemId)` und `MergeItem(itemId)` ohne Werte, Besitz, Kopien und Bonus
-- bestimmt der Server, die Antwort ist nur ok oder ein Grund. Den neuen Stand liefert der StateSync.
-- Ausrüsten und Verschmelzen gehen auch in Regionen mit gesperrten Zufallsitems (nichts wird gekauft).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Menüleiste und Fenster
local MENU_ORDER = 6 -- nach Zonen, Sammlung, Sandsturm, Kisten und Gems
local SUB_HEIGHT = 48
local FOOTER_HEIGHT = 64
local ROW_PADDING = 8
local MESSAGE_SECONDS = 3
local ACTION_COOLDOWN_SECONDS = 0.6 -- gegen Doppeltippen, länger als das Limit des Servers (2 Aufrufe je Sekunde)

local Theme = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("Theme") :: ModuleScript) :: any -- Ü5: ein Stil
local UI = Theme.ui
local Kit = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("Kit") :: ModuleScript) :: any

-- Farben aus Interface/Theme (Ü5)
local PANEL_COLOR = UI.panel
local ROW_COLOR = UI.row
local TEXT_COLOR = UI.text
local MUTED_COLOR = UI.muted
local GOOD_COLOR = UI.good
local WARN_COLOR = UI.warn
local BUTTON_COLOR = UI.button
local ACTIVE_TAB_COLOR = UI.accent
local EQUIP_COLOR = UI.accent
local MERGE_COLOR = UI.good

local TABS = {
    { slot = "skin", label = "Skins" },
    { slot = "companion", label = "Begleiter" },
    { slot = "toolVariant", label = "Werkzeuge" },
}

-- Der Hinweis auf das Kisten-Fenster erscheint nur, wo Kisten erlaubt sind (cratesAllowed).
local EMPTY_TEXTS: { [string]: string } = {
    skin = "Noch kein Skin.",
    companion = "Noch kein Begleiter.",
    toolVariant = "Noch keine Werkzeug-Variante.",
}
local EMPTY_CRATES_HINT = " Kisten gibt es im Kisten-Fenster."
-- Wo Kisten gesperrt sind (Policy bekannt gesperrt oder unbekannt), gibt es den Direktkauf im Shop (Paket 4.6).
local EMPTY_DIRECT_HINT = " Items gibt es im Shop unter Direktkauf."

local REASONS: { [string]: string } = {
    notOwned = "Das Item hast du nicht.",
    wrongSlot = "Das passt nicht in diesen Platz.",
    unknownItem = "Dieses Item gibt es nicht.",
    notEnoughCopies = "Dafür fehlen Kopien.",
    maxStars = "Höchster Stern erreicht.",
    noProfile = "Dein Spielstand lädt noch.",
    error = "Das hat nicht geklappt. Versuch es gleich noch einmal.",
    unknown = "Das geht gerade nicht.",
}

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local CrateItems = loadShared("Data", "CrateItems")
local Rarities = loadShared("Data", "Rarities")
local Economy = loadShared("Data", "Economy")
local EquipmentLogic = loadShared("Logic", "Equipment")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

local EquipmentMenu = {}

local function hexColor(hex: string): Color3
    local r = tonumber(string.sub(hex, 2, 3), 16) or 255
    local g = tonumber(string.sub(hex, 4, 5), 16) or 255
    local b = tonumber(string.sub(hex, 6, 7), 16) or 255
    return Color3.fromRGB(r, g, b)
end

-- Hundertstel-Prozent als Text mit deutschem Komma: 575 -> "5,75", 500 -> "5".
local function percentText(bp: number): string
    local text = string.format("%.2f", bp / 100)
    text = string.gsub(text, "0+$", "")
    text = string.gsub(text, "%.$", "")
    return (string.gsub(text, "%.", ","))
end

local function newText(parent: Instance, name: string, position: UDim2, size: UDim2, font: Enum.Font, color: Color3, text: string, align: Enum.TextXAlignment?): TextLabel
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Position = position
    l.Size = size
    l.Font = font
    l.TextColor3 = color
    l.TextScaled = true
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextWrapped = true
    l.Text = text
    l.Parent = parent
    return l
end

local function newButton(parent: Instance, name: string, color: Color3, textColor: Color3): TextButton
    local b = Instance.new("TextButton")
    Kit.flat(b)
    b.Name = name
    b.BackgroundColor3 = color
    b.Font = Theme.font.bold
    b.TextColor3 = textColor
    b.TextScaled = true
    b.Parent = parent
    Instance.new("UICorner").Parent = b
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, 8)
    p.PaddingBottom = UDim.new(0, 8)
    p.PaddingLeft = UDim.new(0, 4)
    p.PaddingRight = UDim.new(0, 4)
    p.Parent = b
    return b
end

-- Besessene Items der Art, beste Seltenheit zuerst, dann nach Name.
local function ownedItems(snapshot: any, slot: string): { any }
    local inventory = if type(snapshot.inventory) == "table" then snapshot.inventory[EquipmentLogic.INVENTORY_FIELDS[slot]] else nil
    local result: { any } = {}
    if type(inventory) ~= "table" then
        return result
    end
    for _, item in CrateItems.list do
        local count = inventory[item.id]
        if item.kind == slot and type(count) == "number" and count >= 1 then
            table.insert(result, item)
        end
    end
    table.sort(result, function(a: any, b: any): boolean
        local rankA = Rarities.byId[a.rarity].rank
        local rankB = Rarities.byId[b.rarity].rank
        if rankA ~= rankB then
            return rankA > rankB
        end
        return a.name < b.name
    end)
    return result
end

function EquipmentMenu.Init() end

function EquipmentMenu.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local equipRemote = remotes:WaitForChild("EquipItem") :: RemoteFunction
    local mergeRemote = remotes:WaitForChild("MergeItem") :: RemoteFunction
    local controls = Screen.controls()
    local rowHeight = controls.rowButtonH * 2 + ROW_PADDING * 3

    local activeSlot = TABS[1].slot
    local lastKey = ""
    local refreshHook: () -> () = function() end -- wird unten gesetzt (onOpen braucht es vorher)

    local window = Screen.createWindow({
        name = "EquipmentWindow",
        title = "Ausrüstung",
        kind = "wide",
        subHeight = SUB_HEIGHT,
        footerHeight = FOOTER_HEIGHT,
        onOpen = function()
            lastKey = "" -- beim Öffnen immer neu bauen
            refreshHook()
        end,
    })
    local openButton = Screen.addMenuButton("EquipmentButton", "Ausrüstung", MENU_ORDER)
    openButton.Activated:Connect(window.toggle)

    local bonusLabel = newText(window.footer, "Bonus", UDim2.new(0, 12, 0, 4), UDim2.new(1, -24, 0, 26), Theme.font.bold, GOOD_COLOR, "Sammelrate durch Items: +0 %")
    local messageLabel = newText(window.footer, "Message", UDim2.new(0, 12, 0, 34), UDim2.new(1, -24, 0, 24), Theme.font.bold, WARN_COLOR, "")

    local messageToken = 0
    local function showMessage(text: string)
        messageToken += 1
        local token = messageToken
        messageLabel.Text = text
        task.delay(MESSAGE_SECONDS, function()
            if token == messageToken then
                messageLabel.Text = ""
            end
        end)
    end

    -- Reiter -----------------------------------------------------------------------------------
    local tabButtons: { [string]: TextButton } = {}
    for index, tab in TABS do
        local b = Instance.new("TextButton")
        Kit.flat(b)
        b.Name = `Tab_{tab.slot}`
        b.Size = UDim2.new(1 / #TABS, -6, 1, -8)
        b.Position = UDim2.new((index - 1) / #TABS, 3, 0, 4)
        b.Font = Theme.font.bold
        b.TextScaled = true
        b.Text = tab.label
        b.Parent = window.sub
        Instance.new("UICorner").Parent = b
        local p = Instance.new("UIPadding")
        p.PaddingTop = UDim.new(0, 6)
        p.PaddingBottom = UDim.new(0, 6)
        p.Parent = b
        tabButtons[tab.slot] = b
    end

    -- Aktionen ---------------------------------------------------------------------------------
    local busy = false
    local lastActionAt = 0
    local function act(call: () -> any)
        if busy or os.clock() - lastActionAt < ACTION_COOLDOWN_SECONDS then
            return
        end
        lastActionAt = os.clock()
        busy = true
        task.spawn(function()
            local ok, reply = pcall(call)
            busy = false
            if not ok or type(reply) ~= "table" then
                showMessage(REASONS.error)
            elseif reply.ok ~= true then
                showMessage(REASONS[tostring(reply.reason)] or REASONS.unknown)
            end
            -- Den neuen Stand schickt der Server per StateSync, die Karten bauen sich dann neu.
        end)
    end

    -- Karten -----------------------------------------------------------------------------------
    local function refresh()
        local snapshot = State.get()
        if snapshot == nil then
            return
        end
        local bonusBp = if type(snapshot.equipBonusBp) == "number" then snapshot.equipBonusBp else 0
        bonusLabel.Text = `Sammelrate durch Items: +{percentText(bonusBp)} %`
        for _, tab in TABS do
            local button = tabButtons[tab.slot]
            local active = tab.slot == activeSlot
            button.BackgroundColor3 = if active then ACTIVE_TAB_COLOR else BUTTON_COLOR
            button.TextColor3 = if active then PANEL_COLOR else TEXT_COLOR
        end

        local items = ownedItems(snapshot, activeSlot)
        local equipped = if type(snapshot.equipped) == "table" then snapshot.equipped else {}
        local stars = if type(snapshot.itemStars) == "table" then snapshot.itemStars else {}
        local inventory = if type(snapshot.inventory) == "table" then snapshot.inventory[EquipmentLogic.INVENTORY_FIELDS[activeSlot]] else {}
        -- Nur neu bauen, wenn sich etwas Sichtbares geändert hat (der StateSync kommt oft, und ein neu
        -- gebauter Knopf würde ein laufendes Tippen verschlucken).
        local parts: { string } = { activeSlot, tostring(equipped[activeSlot]), tostring(snapshot.cratesAllowed == true), tostring(snapshot.cratePolicy) }
        for _, item in items do
            table.insert(parts, `{item.id}:{inventory[item.id]}:{stars[item.id] or 1}`)
        end
        local key = table.concat(parts, "|")
        if key == lastKey then
            return
        end
        lastKey = key

        for _, child in window.body:GetChildren() do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        if #items == 0 then
            local directHint = snapshot.cratePolicy == "restricted" or snapshot.cratePolicy == "unknown"
            local emptyText = EMPTY_TEXTS[activeSlot] .. (if snapshot.cratesAllowed == true then EMPTY_CRATES_HINT elseif directHint then EMPTY_DIRECT_HINT else "")
            local empty = newText(window.body, "Empty", UDim2.new(), UDim2.new(1, 0, 0, 56), Theme.font.body, MUTED_COLOR, emptyText)
            empty.LayoutOrder = 1
            return
        end
        for order, item in items do
            local copies = math.floor(inventory[item.id])
            local itemStars = math.clamp(math.floor(stars[item.id] or 1), 1, Economy.items.maxStars)
            local isEquipped = equipped[activeSlot] == item.id
            local rarity = Rarities.byId[item.rarity]
            local bonus = EquipmentLogic.itemBonusBp(item, itemStars)
            local cost: number? = nil
            if itemStars < Economy.items.maxStars then
                cost = Economy.items.copiesToMerge[itemStars]
            end
            local canMerge = cost ~= nil and copies - cost >= 1

            local row = Instance.new("Frame")
            row.Name = item.id
            row.LayoutOrder = order
            row.Size = UDim2.new(1, 0, 0, rowHeight)
            row.BackgroundColor3 = ROW_COLOR
            row.BackgroundTransparency = if isEquipped then 0 else 0.2
            row.Parent = window.body
            Instance.new("UICorner").Parent = row

            local nameLabel = newText(row, "Name", UDim2.new(0, 12, 0, 8), UDim2.new(0.55, -12, 0, 30), Theme.font.bold, hexColor(rarity.colorHex), `{item.name} {string.rep("★", itemStars)}`)
            nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            newText(row, "Bonus", UDim2.new(0, 12, 0, 42), UDim2.new(0.55, -12, 0, 22), Theme.font.bold, GOOD_COLOR, `+{percentText(bonus)} % Sammelrate`)
            local copiesText = if cost == nil
                then `Exemplare: {copies}. Höchster Stern.`
                else `Exemplare: {copies}. Nächster Stern: {cost} Kopien`
            newText(row, "Copies", UDim2.new(0, 12, 0, 68), UDim2.new(0.55, -12, 0, 22), Theme.font.body, if canMerge then TEXT_COLOR else MUTED_COLOR, copiesText)

            local equip = newButton(row, "Equip", EQUIP_COLOR, PANEL_COLOR)
            equip.AnchorPoint = Vector2.new(1, 0)
            equip.Position = UDim2.new(1, -8, 0, ROW_PADDING)
            equip.Size = UDim2.new(0.4, 0, 0, controls.rowButtonH)
            equip.Text = if isEquipped then "Abnehmen" else "Ausrüsten"
            equip.Activated:Connect(function()
                act(function(): any
                    return equipRemote:InvokeServer(activeSlot, if isEquipped then "" else item.id)
                end)
            end)

            local merge = newButton(row, "Merge", if canMerge then MERGE_COLOR else BUTTON_COLOR, if canMerge then PANEL_COLOR else MUTED_COLOR)
            merge.AnchorPoint = Vector2.new(1, 0)
            merge.Position = UDim2.new(1, -8, 0, ROW_PADDING * 2 + controls.rowButtonH)
            merge.Size = UDim2.new(0.4, 0, 0, controls.rowButtonH)
            merge.Text = "Verschmelzen"
            merge.Activated:Connect(function()
                if not canMerge then
                    showMessage(if cost == nil then REASONS.maxStars else REASONS.notEnoughCopies)
                    return
                end
                act(function(): any
                    return mergeRemote:InvokeServer(item.id)
                end)
            end)
        end
    end
    refreshHook = refresh

    for _, tab in TABS do
        tabButtons[tab.slot].Activated:Connect(function()
            activeSlot = tab.slot
            lastKey = ""
            refresh()
        end)
    end

    State.onChanged(function()
        if window.isOpen() then
            refresh()
        end
    end)
end

return EquipmentMenu
