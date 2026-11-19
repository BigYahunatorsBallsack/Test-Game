--!strict
-- Screen (Paket 3.6): Hilfsmodul der Client-Controller, kein eigener Controller (steht deshalb
-- nicht in init.client). Es besitzt
--   * die Menüleiste: Zonen, Sammlung, Sandsturm (und was später dazukommt) melden ihren Knopf mit
--     `addMenuButton` an. Am PC steht die Leiste als Reihe unten links, am Handy als Spalte rechts
--     unter dem Knopf "Baum" (außerhalb von Steuerknüppel und Sprungknopf),
--   * das Fenster-Gerüst `createWindow`: Kopfzeile mit Schließen-Knopf (44 px), scrollbarer Inhalt,
--     optionaler Reiterstreifen und fester Fuß, Größe aus der Bildschirmgröße. Es ist immer nur ein
--     Fenster offen: Öffnen schließt die anderen, der Baum schließt alle,
--   * den aktuellen Plan der Oberfläche (`layout`) für HUD, Tutorial, Reveal und Graben-Knopf.
-- Die Rechnung steht in Logic/ScreenLayout, die Zahlen in Data/Screen (beide mit Lune getestet).
-- Dieses Modul liest nur die Bildschirmgröße und setzt Positionen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Ebenen: Menüleiste unter dem Baum (5), Fenster darüber, aber unter Sandwand (8) und Reveal (10).
local MENU_DISPLAY_ORDER = 4
local WINDOW_DISPLAY_ORDER = 6

-- Animation
local WINDOW_FADE_SECONDS = 0.18
local WINDOW_FADE_EASING = Enum.EasingStyle.Quad
local WINDOW_TRANSPARENCY = 0.08

-- Darstellung
local BODY_SCROLLBAR = 6
local BODY_SIDE_PADDING = 8
local TITLE_MAX_TEXT = 24
local BUTTON_MAX_TEXT = 20
local BUTTON_MIN_TEXT = 11
local BUTTON_TRANSPARENCY = 0.25

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local CLOSE_COLOR = Color3.fromRGB(80, 66, 52)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local ScreenLayout = loadShared("Logic", "ScreenLayout")
local ScreenData = loadShared("Data", "Screen")

local Screen = {}

export type Window = {
    name: string,
    frame: Frame,
    title: TextLabel,
    closeButton: TextButton,
    sub: Frame, -- Streifen unter der Kopfzeile (zum Beispiel Reiter), Höhe aus `subHeight`
    body: ScrollingFrame, -- scrollbarer Inhalt mit UIListLayout (Reihenfolge über LayoutOrder)
    footer: Frame, -- fester Fuß, Höhe aus `footerHeight`
    open: () -> (),
    close: () -> (),
    toggle: () -> (),
    isOpen: () -> boolean,
}

type MenuEntry = { id: string, order: number, button: TextButton }
type WindowEntry = { window: Window, kind: string, applySize: () -> () }

local menuGui: ScreenGui? = nil
local windowGui: ScreenGui? = nil
local menuEntries: { MenuEntry } = {}
local windowEntries: { WindowEntry } = {}
local currentLayout: any = nil
local listeners: { (any) -> () } = {}
local relayoutQueued = false

-- Handy oder Tablet ohne Tastatur.
function Screen.isTouch(): boolean
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function setInsets(gui: ScreenGui)
    -- Nichts unter dem Roblox-Menü oder der Notch. Ältere Studio-Versionen kennen CoreUISafe nicht
    -- (siehe SkillTree), dann gilt der Standard des Spiels.
    local ok, coreUiSafe = pcall(function(): any
        return (Enum.ScreenInsets :: any).CoreUISafe
    end)
    if ok and coreUiSafe ~= nil then
        gui.ScreenInsets = coreUiSafe
    end
end

-- Größe der sicheren Fläche. Steht sie noch nicht fest (erstes Bild), gilt die Kameragröße.
local function viewportSize(): { width: number, height: number }
    local gui = menuGui
    if gui ~= nil and gui.AbsoluteSize.X > 0 and gui.AbsoluteSize.Y > 0 then
        return { width = gui.AbsoluteSize.X, height = gui.AbsoluteSize.Y }
    end
    local camera = workspace.CurrentCamera
    if camera ~= nil and camera.ViewportSize.X > 0 then
        return { width = camera.ViewportSize.X, height = camera.ViewportSize.Y }
    end
    return { width = 1024, height = 768 }
end

local function visibleMenuEntries(): { MenuEntry }
    local list: { MenuEntry } = {}
    for _, entry in menuEntries do
        if entry.button.Visible then
            table.insert(list, entry)
        end
    end
    table.sort(list, function(a: MenuEntry, b: MenuEntry)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.id < b.id
    end)
    return list
end

local function relayout()
    relayoutQueued = false
    if menuGui == nil then
        return
    end
    local visible = visibleMenuEntries()
    local layout = ScreenLayout.compute(viewportSize(), Screen.isTouch(), #visible)
    currentLayout = layout
    for index, entry in visible do
        local rect = layout.menu[index]
        if rect ~= nil then
            entry.button.Position = UDim2.fromOffset(rect.x, rect.y)
            entry.button.Size = UDim2.fromOffset(rect.w, rect.h)
        end
    end
    for _, entry in windowEntries do
        entry.applySize()
    end
    for _, listener in table.clone(listeners) do
        task.spawn(listener, layout)
    end
end

local function queueRelayout()
    if relayoutQueued then
        return
    end
    relayoutQueued = true
    task.defer(relayout)
end

local function ensure()
    if menuGui ~= nil then
        return
    end
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    local menu = Instance.new("ScreenGui")
    menu.Name = "DuneBaronMenu"
    menu.ResetOnSpawn = false
    menu.DisplayOrder = MENU_DISPLAY_ORDER
    setInsets(menu)
    menu.Parent = playerGui
    menuGui = menu

    local windows = Instance.new("ScreenGui")
    windows.Name = "DuneBaronWindows"
    windows.ResetOnSpawn = false
    windows.DisplayOrder = WINDOW_DISPLAY_ORDER
    setInsets(windows)
    windows.Parent = playerGui
    windowGui = windows

    menu:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueRelayout)
    UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(queueRelayout)
    UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(queueRelayout)
    relayout()
end

-- Aktueller Plan der Oberfläche (siehe Logic/ScreenLayout).
function Screen.layout(): any
    ensure()
    if currentLayout == nil then
        relayout()
    end
    return currentLayout
end

-- Maße der Bedienelemente in Fenstern (Data/Screen: controls).
function Screen.controls(): any
    return ScreenData.controls
end

-- Zahlen der aktuellen Größenklasse aus Data/Screen (HUD-Maße, Karten, Banner ...).
function Screen.classData(): any
    return ScreenLayout.classData(Screen.layout().class)
end

-- Meldet sich ab, wenn die zurückgegebene Funktion aufgerufen wird.
function Screen.onLayoutChanged(listener: (any) -> ()): () -> ()
    ensure()
    table.insert(listeners, listener)
    return function()
        local index = table.find(listeners, listener)
        if index ~= nil then
            table.remove(listeners, index)
        end
    end
end

-- Knopf in der Menüleiste. `order` bestimmt die Reihenfolge (klein = zuerst). Der Controller darf
-- Text, Farbe und Sichtbarkeit ändern: ein unsichtbarer Knopf nimmt keinen Platz in der Leiste.
function Screen.addMenuButton(id: string, text: string, order: number): TextButton
    ensure()
    local gui = menuGui :: ScreenGui
    local button = Instance.new("TextButton")
    button.Name = id
    button.BackgroundColor3 = PANEL_COLOR
    button.BackgroundTransparency = BUTTON_TRANSPARENCY
    button.Font = Enum.Font.GothamBold
    button.TextColor3 = TEXT_COLOR
    button.TextScaled = true
    button.TextWrapped = true
    button.Text = text
    button.Parent = gui
    Instance.new("UICorner").Parent = button
    local constraint = Instance.new("UITextSizeConstraint")
    constraint.MaxTextSize = BUTTON_MAX_TEXT
    constraint.MinTextSize = BUTTON_MIN_TEXT
    constraint.Parent = button
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 4)
    padding.PaddingRight = UDim.new(0, 4)
    padding.PaddingTop = UDim.new(0, 2)
    padding.PaddingBottom = UDim.new(0, 2)
    padding.Parent = button
    table.insert(menuEntries, { id = id, order = order, button = button })
    button:GetPropertyChangedSignal("Visible"):Connect(queueRelayout)
    relayout()
    return button
end

-- Ist irgendein Fenster offen? (Angebots-Hinweise warten darauf, Paket 4.5.)
function Screen.isAnyWindowOpen(): boolean
    for _, entry in windowEntries do
        if entry.window.isOpen() then
            return true
        end
    end
    return false
end

function Screen.closeAllWindows()
    for _, entry in windowEntries do
        entry.window.close()
    end
end

export type WindowSpec = {
    name: string,
    title: string,
    kind: string?, -- "narrow" (Standard) oder "wide"
    subHeight: number?, -- Höhe des Streifens unter der Kopfzeile
    footerHeight: number?, -- Höhe des festen Fußes
    onOpen: (() -> ())?,
    onClose: (() -> ())?,
}

-- Fenster in der Mitte des Bildschirms. Der Inhalt kommt in `body` (scrollt), `sub` und `footer`
-- füllt der Controller selbst. Öffnen schließt alle anderen Fenster.
function Screen.createWindow(spec: WindowSpec): Window
    ensure()
    local gui = windowGui :: ScreenGui
    local controls = ScreenData.controls
    local kind = spec.kind or "narrow"
    local subHeight = spec.subHeight or 0
    local footerHeight = spec.footerHeight or 0

    local frame = Instance.new("Frame")
    frame.Name = spec.name
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.BackgroundColor3 = PANEL_COLOR
    frame.BackgroundTransparency = WINDOW_TRANSPARENCY
    frame.Active = true -- Tipps auf das Fenster erreichen nicht die Welt dahinter
    frame.Visible = false
    frame.Parent = gui
    Instance.new("UICorner").Parent = frame

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(16, 0)
    title.Size = UDim2.new(1, -(controls.closeButton + 32), 0, controls.headerH)
    title.Font = Enum.Font.GothamBold
    title.TextColor3 = TEXT_COLOR
    title.TextScaled = true
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = spec.title
    title.Parent = frame
    local titleConstraint = Instance.new("UITextSizeConstraint")
    titleConstraint.MaxTextSize = TITLE_MAX_TEXT
    titleConstraint.Parent = title
    local titlePadding = Instance.new("UIPadding")
    titlePadding.PaddingTop = UDim.new(0, 8)
    titlePadding.PaddingBottom = UDim.new(0, 8)
    titlePadding.Parent = title

    local closeButton = Instance.new("TextButton")
    closeButton.Name = "Close"
    closeButton.AnchorPoint = Vector2.new(1, 0)
    closeButton.Position = UDim2.new(1, -8, 0, (controls.headerH - controls.closeButton) / 2)
    closeButton.Size = UDim2.fromOffset(controls.closeButton, controls.closeButton)
    closeButton.BackgroundColor3 = CLOSE_COLOR
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextColor3 = TEXT_COLOR
    closeButton.TextScaled = true
    closeButton.Text = "X"
    closeButton.Parent = frame
    Instance.new("UICorner").Parent = closeButton
    local closePadding = Instance.new("UIPadding")
    closePadding.PaddingTop = UDim.new(0, 8)
    closePadding.PaddingBottom = UDim.new(0, 8)
    closePadding.PaddingLeft = UDim.new(0, 8)
    closePadding.PaddingRight = UDim.new(0, 8)
    closePadding.Parent = closeButton

    local sub = Instance.new("Frame")
    sub.Name = "Sub"
    sub.BackgroundTransparency = 1
    sub.Position = UDim2.new(0, BODY_SIDE_PADDING, 0, controls.headerH)
    sub.Size = UDim2.new(1, -2 * BODY_SIDE_PADDING, 0, subHeight)
    sub.Visible = subHeight > 0
    sub.Parent = frame

    local footer = Instance.new("Frame")
    footer.Name = "Footer"
    footer.BackgroundTransparency = 1
    footer.AnchorPoint = Vector2.new(0, 1)
    footer.Position = UDim2.fromScale(0, 1)
    footer.Size = UDim2.new(1, 0, 0, footerHeight)
    footer.Visible = footerHeight > 0
    footer.Parent = frame

    local body = Instance.new("ScrollingFrame")
    body.Name = "Body"
    body.BackgroundTransparency = 1
    body.BorderSizePixel = 0
    body.Position = UDim2.new(0, BODY_SIDE_PADDING, 0, controls.headerH + subHeight)
    body.Size = UDim2.new(1, -2 * BODY_SIDE_PADDING, 1, -(controls.headerH + subHeight + footerHeight + 4))
    body.CanvasSize = UDim2.new()
    body.AutomaticCanvasSize = Enum.AutomaticSize.Y
    body.ScrollingDirection = Enum.ScrollingDirection.Y
    body.ScrollBarThickness = BODY_SCROLLBAR
    body.Parent = frame
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, controls.rowGap)
    list.Parent = body
    local bodyPadding = Instance.new("UIPadding")
    bodyPadding.PaddingRight = UDim.new(0, BODY_SCROLLBAR + 2)
    bodyPadding.Parent = body

    local isOpen = false
    local fade = TweenInfo.new(WINDOW_FADE_SECONDS, WINDOW_FADE_EASING)
    local window: any = {
        name = spec.name,
        frame = frame,
        title = title,
        closeButton = closeButton,
        sub = sub,
        body = body,
        footer = footer,
    }

    function window.isOpen(): boolean
        return isOpen
    end

    function window.close()
        if not isOpen then
            return
        end
        isOpen = false
        frame.Visible = false
        if spec.onClose ~= nil then
            spec.onClose()
        end
    end

    function window.open()
        if isOpen then
            return
        end
        for _, entry in windowEntries do
            if entry.window ~= window then
                entry.window.close()
            end
        end
        isOpen = true
        body.CanvasPosition = Vector2.zero
        frame.BackgroundTransparency = 1
        frame.Visible = true
        TweenService:Create(frame, fade, { BackgroundTransparency = WINDOW_TRANSPARENCY }):Play()
        if spec.onOpen ~= nil then
            spec.onOpen()
        end
    end

    function window.toggle()
        if isOpen then
            window.close()
        else
            window.open()
        end
    end

    closeButton.Activated:Connect(window.close)

    local function applySize()
        local size = ScreenLayout.windowSize(viewportSize(), kind)
        frame.Size = UDim2.fromOffset(size.width, size.height)
    end
    table.insert(windowEntries, { window = window :: Window, kind = kind, applySize = applySize })
    applySize()
    return window :: Window
end

return Screen
