--!strict
-- SkillTree-Controller (Paket 2.2): der Skilltree als Vollbild-Ebene, ersetzt die schlichte
-- Upgrade-Liste aus 1.6. Der Baum entsteht aus den Daten: Logic/TreeLayout rechnet die Plätze,
-- Logic/TreeView die Zustände (gekauft, kaufbar, zu teuer, Silhouette, verborgen), Logic/TreeCamera
-- Zoom, Verschieben und Tippen. Dieser Controller zeichnet nur und liest Eingaben.
--
-- Bedienung: Knopf "Baum" (mit Zähler bezahlbarer Knoten) öffnet die Ebene. Ziehen verschiebt,
-- Zwei-Finger-Geste, Mausrad und Plus/Minus zoomen. Ein Tippen auf einen Knoten öffnet eine Karte,
-- gekauft wird nur über den Knopf auf der Karte (nie beim Ziehen). Der Client schickt nur die
-- Knoten-ID (PurchaseNode), der Server prüft und bucht. Alle Werte kommen vom Server (State).
-- Solange der Baum offen ist, ist das Sammeln pausiert (Input.setSuspended).
-- Die Freischalt-Animation (Ring, Lichtimpuls, Kamerafahrt) kommt in Paket 2.3.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Layout (Pixel auf dem Bildschirm)
local BUTTON_SIZE = Vector2.new(124, 46)
local BUTTON_MARGIN = 16
local ICON_BUTTON_SIZE = 46 -- Schließen, Plus, Minus: mindestens 44 px zum Antippen
local EDGE_MARGIN = 12
local HEADER_HEIGHT = 46
local CARD_MARGIN = 14
local CARD_WIDTH_DESKTOP = 330
local CARD_HEIGHT_DESKTOP = 214
local CARD_HEIGHT_MOBILE = 184
local BUY_BUTTON_HEIGHT = 50
local BADGE_SIZE = 24

-- Baumfläche (Weltpixel bei Zoom 1)
local LINE_WIDTH = 6
local DASH_LENGTH = 12
local DASH_GAP = 9
local BAND_LINE_HEIGHT = 2
local BAND_LABEL_HEIGHT = 14 -- passt in die Lücke zwischen zwei Reihen
local FOG_GAP = 30 -- Abstand zwischen dem Nebel und dem obersten sichtbaren Knoten
local PRICE_HEIGHT = 18
local RING_GROW = 18
local SELECT_STROKE = 4
local NODE_STROKE = 3

-- Animationen
local FADE_SECONDS = 0.2
local FADE_EASING = Enum.EasingStyle.Sine
local PULSE_SECONDS = 0.8
local PULSE_EASING = Enum.EasingStyle.Sine
local BREATH_SECONDS = 1.6
local FEEDBACK_VISIBLE_SECONDS = 2
local FOG_TOP_TRANSPARENCY = 0.15

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local BACKDROP_COLOR = Color3.fromRGB(34, 27, 20)
local BACKDROP_TRANSPARENCY = 0.08
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local BUTTON_COLOR = Color3.fromRGB(96, 78, 44)
local BUTTON_DIM_COLOR = Color3.fromRGB(58, 52, 46)
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 220, 120)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local TEXT_DIM_COLOR = Color3.fromRGB(170, 160, 145)
local LINE_LIT_COLOR = Color3.fromRGB(255, 236, 190)
local LINE_DIM_COLOR = Color3.fromRGB(120, 108, 90)
local FOG_COLOR = Color3.fromRGB(214, 198, 170)
local SILHOUETTE_COLOR = Color3.fromRGB(46, 40, 34)
local EXPENSIVE_COLOR = Color3.fromRGB(70, 62, 52)
local STROKE_OWNED_COLOR = Color3.fromRGB(255, 244, 214)
local STROKE_AFFORD_COLOR = Color3.fromRGB(255, 230, 150)
local STROKE_DIM_COLOR = Color3.fromRGB(92, 82, 70)
local SELECT_COLOR = Color3.fromRGB(255, 255, 255)

-- Texte
local OPEN_TEXT = "Baum"
local TITLE_TEXT = "Skilltree"
local CLOSE_TEXT = "X"
local ZOOM_IN_TEXT = "+"
local ZOOM_OUT_TEXT = "-"
local OWNED_TEXT = "Gekauft"
local UNKNOWN_NAME = "???"
local UNKNOWN_DESCRIPTION = "Noch im Nebel."
local NEEDS_TEXT = "Braucht: "
local BUY_TEXT = "Kaufen"
local BOUGHT_TEXT = "Gekauft: "
local HIDDEN_BUY_TEXT = "Noch nicht möglich"
local MESSAGES = {
    coins = "Zu wenig Münzen.",
    requires = "Dafür fehlt noch ein anderes Upgrade.",
    owned = "Schon gekauft.",
    unknown = "Das geht gerade nicht.",
    granted = "Das geht gerade nicht.",
    busy = "Einen Moment ...",
}

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local BigNum = loadShared("Logic", "BigNum")
local TreeLayout = loadShared("Logic", "TreeLayout")
local TreeView = loadShared("Logic", "TreeView")
local TreeCamera = loadShared("Logic", "TreeCamera")
local LayoutConfig = loadShared("Data", "TreeLayout")
local TutorialData = loadShared("Data", "Tutorial")
local UpgradeTree = loadShared("Data", "UpgradeTree")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Input = require(script.Parent:WaitForChild("Input") :: ModuleScript) :: any

local SkillTree = {}

type NodeEntry = {
    frame: Frame,
    stroke: UIStroke,
    glyph: TextLabel,
    price: TextLabel,
    ring: Frame,
    ringStroke: UIStroke,
    ringPulse: Tween?,
    breath: Tween?,
    color: Color3,
    lastKey: string, -- Zustand beim letzten Einfärben, damit nichts unnötig neu gesetzt wird
}

local function colorOf(rgb: { number }): Color3
    return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function dimmed(color: Color3, factor: number): Color3
    return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

local function label(parent: Instance, name: string, position: UDim2, size: UDim2, font: Enum.Font, xAlign: Enum.TextXAlignment): TextLabel
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Position = position
    l.Size = size
    l.Font = font
    l.TextColor3 = TEXT_COLOR
    l.TextScaled = true
    l.TextXAlignment = xAlign
    l.Parent = parent
    return l
end

local function roundButton(parent: Instance, name: string, text: string, size: UDim2): TextButton
    local button = Instance.new("TextButton")
    button.Name = name
    button.AutoButtonColor = true
    button.Text = text
    button.Font = Enum.Font.GothamBold
    button.TextScaled = true
    button.TextColor3 = TEXT_COLOR
    button.BackgroundColor3 = BUTTON_COLOR
    button.Size = size
    button.Parent = parent
    Instance.new("UICorner").Parent = button
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = button
    return button
end

function SkillTree.Init() end

function SkillTree.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local purchase = remotes:WaitForChild("PurchaseNode") :: RemoteFunction

    local layout = TreeLayout.compute()
    local area = layout.area
    local half = LayoutConfig.nodeSize / 2
    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

    ---------------------------------------------------------------- Oberfläche
    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronTree"
    gui.ResetOnSpawn = false
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafe -- nichts unter dem Roblox-Menü oder der Notch
    gui.DisplayOrder = 5

    -- Knopf zum Öffnen, oben rechts, mit Zähler
    local openButton = roundButton(gui, "OpenButton", OPEN_TEXT, UDim2.fromOffset(BUTTON_SIZE.X, BUTTON_SIZE.Y))
    openButton.AnchorPoint = Vector2.new(1, 0)
    openButton.Position = UDim2.new(1, -BUTTON_MARGIN, 0, BUTTON_MARGIN)
    openButton.Visible = false
    local openStroke = Instance.new("UIStroke")
    openStroke.Color = HIGHLIGHT_COLOR
    openStroke.Thickness = 3
    openStroke.Transparency = 1
    openStroke.Parent = openButton
    local openPulse: Tween? = nil
    local badge = Instance.new("TextLabel")
    badge.Name = "Counter"
    badge.AnchorPoint = Vector2.new(0.5, 0.5)
    badge.Position = UDim2.new(1, -4, 0, 4)
    badge.Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE)
    badge.BackgroundColor3 = HIGHLIGHT_COLOR
    badge.TextColor3 = PANEL_COLOR
    badge.Font = Enum.Font.GothamBold
    badge.TextScaled = true
    badge.Visible = false
    badge.Parent = openButton
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(1, 0)
    badgeCorner.Parent = badge
    local badgePadding = Instance.new("UIPadding")
    badgePadding.PaddingTop = UDim.new(0, 3)
    badgePadding.PaddingBottom = UDim.new(0, 3)
    badgePadding.PaddingLeft = UDim.new(0, 3)
    badgePadding.PaddingRight = UDim.new(0, 3)
    badgePadding.Parent = badge

    -- Vollbild-Ebene
    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.BackgroundColor3 = BACKDROP_COLOR
    overlay.BackgroundTransparency = BACKDROP_TRANSPARENCY
    overlay.Visible = false
    overlay.ZIndex = 10
    overlay.Parent = gui

    -- Fläche für Gesten: liegt unter allen Knöpfen, damit die Knöpfe die Eingabe schlucken.
    local canvas = Instance.new("Frame")
    canvas.Name = "Canvas"
    canvas.Size = UDim2.fromScale(1, 1)
    canvas.BackgroundTransparency = 1
    canvas.ClipsDescendants = true
    canvas.Active = true
    canvas.ZIndex = 11
    canvas.Parent = overlay

    local world = Instance.new("Frame")
    world.Name = "World"
    world.BackgroundTransparency = 1
    world.Size = UDim2.fromOffset(area.width, area.height)
    world.ZIndex = 11
    world.Parent = canvas
    local worldScale = Instance.new("UIScale")
    worldScale.Parent = world

    local fog = Instance.new("Frame")
    fog.Name = "Fog"
    fog.BackgroundColor3 = FOG_COLOR
    fog.BorderSizePixel = 0
    fog.Position = UDim2.fromOffset(0, 0)
    fog.Size = UDim2.fromOffset(area.width, 0)
    fog.ZIndex = 11
    fog.Parent = world
    local fogGradient = Instance.new("UIGradient")
    fogGradient.Rotation = 90
    fogGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, FOG_TOP_TRANSPARENCY),
        NumberSequenceKeypoint.new(0.55, 0.55),
        NumberSequenceKeypoint.new(1, 1),
    })
    fogGradient.Parent = fog

    local bandFolder = Instance.new("Folder")
    bandFolder.Name = "Bands"
    bandFolder.Parent = world
    local lineFolder = Instance.new("Folder")
    lineFolder.Name = "Lines"
    lineFolder.Parent = world
    local nodeFolder = Instance.new("Folder")
    nodeFolder.Name = "Nodes"
    nodeFolder.Parent = world

    -- Kopfzeile: Titel, Münzen, Schließen
    local title = label(overlay, "Title", UDim2.new(0, EDGE_MARGIN, 0, EDGE_MARGIN), UDim2.fromOffset(220, 26), Enum.Font.GothamBold, Enum.TextXAlignment.Left)
    title.Text = TITLE_TEXT
    title.ZIndex = 12
    local coinsLabel = label(overlay, "Coins", UDim2.new(0, EDGE_MARGIN, 0, EDGE_MARGIN + 28), UDim2.fromOffset(240, 20), Enum.Font.Gotham, Enum.TextXAlignment.Left)
    coinsLabel.TextColor3 = TEXT_DIM_COLOR
    coinsLabel.ZIndex = 12
    local closeButton = roundButton(overlay, "Close", CLOSE_TEXT, UDim2.fromOffset(ICON_BUTTON_SIZE, ICON_BUTTON_SIZE))
    closeButton.AnchorPoint = Vector2.new(1, 0)
    closeButton.Position = UDim2.new(1, -BUTTON_MARGIN, 0, BUTTON_MARGIN)
    closeButton.ZIndex = 13

    -- Zoom-Knöpfe, links in der Mitte (so liegen sie weder unter der Karte noch unter dem Daumen)
    local zoomIn = roundButton(overlay, "ZoomIn", ZOOM_IN_TEXT, UDim2.fromOffset(ICON_BUTTON_SIZE, ICON_BUTTON_SIZE))
    zoomIn.AnchorPoint = Vector2.new(0, 1)
    zoomIn.Position = UDim2.new(0, EDGE_MARGIN, 0.5, -4)
    zoomIn.ZIndex = 13
    local zoomOut = roundButton(overlay, "ZoomOut", ZOOM_OUT_TEXT, UDim2.fromOffset(ICON_BUTTON_SIZE, ICON_BUTTON_SIZE))
    zoomOut.AnchorPoint = Vector2.new(0, 0)
    zoomOut.Position = UDim2.new(0, EDGE_MARGIN, 0.5, 4)
    zoomOut.ZIndex = 13

    -- Karte: unten am Handy, rechts am PC
    local card = Instance.new("Frame")
    card.Name = "Card"
    card.BackgroundColor3 = PANEL_COLOR
    card.BackgroundTransparency = 0.05
    card.Active = true
    card.Visible = false
    card.ZIndex = 14
    card.Parent = overlay
    if isMobile then
        card.AnchorPoint = Vector2.new(0.5, 1)
        card.Position = UDim2.new(0.5, 0, 1, -CARD_MARGIN)
        card.Size = UDim2.new(1, -2 * CARD_MARGIN - 2 * ICON_BUTTON_SIZE, 0, CARD_HEIGHT_MOBILE)
    else
        card.AnchorPoint = Vector2.new(1, 0.5)
        card.Position = UDim2.new(1, -CARD_MARGIN, 0.5, 0)
        card.Size = UDim2.fromOffset(CARD_WIDTH_DESKTOP, CARD_HEIGHT_DESKTOP)
    end
    Instance.new("UICorner").Parent = card
    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = STROKE_DIM_COLOR
    cardStroke.Thickness = 2
    cardStroke.Parent = card
    local cardName = label(card, "Name", UDim2.new(0, 14, 0, 8), UDim2.new(1, -28, 0, 26), Enum.Font.GothamBold, Enum.TextXAlignment.Left)
    cardName.ZIndex = 15
    local cardDescription = label(card, "Description", UDim2.new(0, 14, 0, 38), UDim2.new(1, -28, 0, 20), Enum.Font.Gotham, Enum.TextXAlignment.Left)
    cardDescription.TextColor3 = TEXT_DIM_COLOR
    cardDescription.ZIndex = 15
    local cardNeeds = label(card, "Needs", UDim2.new(0, 14, 0, 62), UDim2.new(1, -28, 0, 18), Enum.Font.Gotham, Enum.TextXAlignment.Left)
    cardNeeds.TextColor3 = HIGHLIGHT_COLOR
    cardNeeds.ZIndex = 15
    local cardFeedback = label(card, "Feedback", UDim2.new(0, 14, 0, 84), UDim2.new(1, -28, 0, 18), Enum.Font.Gotham, Enum.TextXAlignment.Left)
    cardFeedback.TextTransparency = 1
    cardFeedback.ZIndex = 15
    local buyButton = roundButton(card, "Buy", BUY_TEXT, UDim2.new(1, -28, 0, BUY_BUTTON_HEIGHT))
    buyButton.AnchorPoint = Vector2.new(0.5, 1)
    buyButton.Position = UDim2.new(0.5, 0, 1, -12)
    buyButton.ZIndex = 15

    gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

    ---------------------------------------------------------------- Zustand
    local layoutConfigLooks = LayoutConfig.looks
    local entries: { [string]: NodeEntry } = {}
    local positions: { [string]: { x: number, y: number } } = {} -- sichtbare Knoten (für das Tippen)
    local view: any = nil
    local lastSignature = ""
    local snapshot: any = nil
    local highlightId: string? = nil
    local selectedId: string? = nil
    local isOpen = false
    local busy = false
    local feedbackToken = 0
    local camera: any = { zoom = LayoutConfig.zoom.start, panX = 0, panY = 0 }

    local fadeInfo = TweenInfo.new(FADE_SECONDS, FADE_EASING)
    local function showFeedback(text: string)
        feedbackToken += 1
        local token = feedbackToken
        cardFeedback.Text = text
        TweenService:Create(cardFeedback, fadeInfo, { TextTransparency = 0 }):Play()
        task.delay(FEEDBACK_VISIBLE_SECONDS, function()
            if token == feedbackToken then
                TweenService:Create(cardFeedback, fadeInfo, { TextTransparency = 1 }):Play()
            end
        end)
    end

    local function viewport(): any
        local size = canvas.AbsoluteSize
        return { width = size.X, height = size.Y }
    end

    local function applyCamera()
        worldScale.Scale = camera.zoom
        world.Position = UDim2.fromOffset(camera.panX + area.minX * camera.zoom, camera.panY + area.minY * camera.zoom)
    end

    local function setCamera(next: any)
        camera = next
        applyCamera()
    end

    -- Punkt auf der Baumfläche (Weltkoordinaten, Start = 0/0) -> Position im Fläche-Rahmen.
    local function framePosition(x: number, y: number): UDim2
        return UDim2.fromOffset(x - area.minX, y - area.minY)
    end

    ---------------------------------------------------------------- Knoten
    local function setStrokeStyle(stroke: UIStroke, color: Color3, thickness: number, transparency: number)
        stroke.Color = color
        stroke.Thickness = thickness
        stroke.Transparency = transparency
    end

    local function stopBreath(entry: NodeEntry)
        if entry.breath ~= nil then
            (entry.breath :: Tween):Cancel()
            entry.breath = nil
        end
    end

    local function stopRingPulse(entry: NodeEntry)
        if entry.ringPulse ~= nil then
            (entry.ringPulse :: Tween):Cancel()
            entry.ringPulse = nil
        end
    end

    local function makeNode(nodeId: string): NodeEntry
        local node = UpgradeTree.byId[nodeId]
        local placement = layout.nodes[nodeId]
        local look = layoutConfigLooks[node.effect.kind]
        local color = colorOf(look.color)

        local frame = Instance.new("Frame")
        frame.Name = nodeId
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        frame.Position = framePosition(placement.x, placement.y)
        frame.Size = UDim2.fromOffset(LayoutConfig.nodeSize, LayoutConfig.nodeSize)
        frame.BackgroundColor3 = color
        frame.Visible = false
        frame.ZIndex = 13
        frame.Parent = nodeFolder
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 16)
        corner.Parent = frame
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = NODE_STROKE
        stroke.Parent = frame

        local glyph = label(frame, "Glyph", UDim2.new(0, 8, 0, 6), UDim2.new(1, -16, 1, -PRICE_HEIGHT - 12), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        glyph.Text = look.glyph
        glyph.ZIndex = 14
        local price = label(frame, "Price", UDim2.new(0, 4, 1, -PRICE_HEIGHT - 4), UDim2.new(1, -8, 0, PRICE_HEIGHT), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        price.ZIndex = 14

        -- Leuchtring für den Knoten des Tutorial-Schritts
        local ring = Instance.new("Frame")
        ring.Name = "Ring"
        ring.AnchorPoint = Vector2.new(0.5, 0.5)
        ring.Position = UDim2.fromScale(0.5, 0.5)
        ring.Size = UDim2.new(1, RING_GROW, 1, RING_GROW)
        ring.BackgroundTransparency = 1
        ring.Visible = false
        ring.ZIndex = 13
        ring.Parent = frame
        local ringCorner = Instance.new("UICorner")
        ringCorner.CornerRadius = UDim.new(0, 20)
        ringCorner.Parent = ring
        local ringStroke = Instance.new("UIStroke")
        ringStroke.Color = HIGHLIGHT_COLOR
        ringStroke.Thickness = 4
        ringStroke.Transparency = 0.1
        ringStroke.Parent = ring

        return {
            frame = frame,
            stroke = stroke,
            glyph = glyph,
            price = price,
            ring = ring,
            ringStroke = ringStroke,
            ringPulse = nil,
            breath = nil,
            color = color,
            lastKey = "",
        }
    end

    local function styleNode(nodeId: string)
        local entry = entries[nodeId]
        local visual: string = view.nodes[nodeId]
        local node = UpgradeTree.byId[nodeId]
        local key = visual .. "|" .. tostring(selectedId == nodeId) .. "|" .. tostring(highlightId == nodeId)
        if entry.lastKey == key then
            return
        end
        entry.lastKey = key
        if visual == "hidden" then
            entry.frame.Visible = false
            stopRingPulse(entry)
            stopBreath(entry)
            return
        end
        entry.frame.Visible = true

        stopBreath(entry)
        if visual == "owned" then
            entry.frame.BackgroundColor3 = entry.color
            setStrokeStyle(entry.stroke, STROKE_OWNED_COLOR, NODE_STROKE, 0)
            entry.glyph.Text = layoutConfigLooks[node.effect.kind].glyph
            entry.glyph.TextColor3 = TEXT_COLOR
            entry.price.Text = OWNED_TEXT
            entry.price.TextColor3 = TEXT_COLOR
        elseif visual == "affordable" then
            entry.frame.BackgroundColor3 = dimmed(entry.color, 0.62)
            setStrokeStyle(entry.stroke, STROKE_AFFORD_COLOR, NODE_STROKE, 0.1)
            entry.glyph.Text = layoutConfigLooks[node.effect.kind].glyph
            entry.glyph.TextColor3 = TEXT_COLOR
            entry.price.Text = BigNum.format(BigNum.new(node.cost))
            entry.price.TextColor3 = TEXT_COLOR
            if selectedId ~= nodeId then
                local tween = TweenService:Create(
                    entry.stroke,
                    TweenInfo.new(BREATH_SECONDS, FADE_EASING, Enum.EasingDirection.InOut, -1, true),
                    { Transparency = 0.6 }
                )
                entry.breath = tween
                tween:Play()
            end
        elseif visual == "expensive" then
            entry.frame.BackgroundColor3 = EXPENSIVE_COLOR
            setStrokeStyle(entry.stroke, STROKE_DIM_COLOR, NODE_STROKE, 0)
            entry.glyph.Text = layoutConfigLooks[node.effect.kind].glyph
            entry.glyph.TextColor3 = TEXT_DIM_COLOR
            entry.price.Text = BigNum.format(BigNum.new(node.cost))
            entry.price.TextColor3 = TEXT_DIM_COLOR
        else -- silhouette: dunkle Form ohne Namen und Preis
            entry.frame.BackgroundColor3 = SILHOUETTE_COLOR
            setStrokeStyle(entry.stroke, STROKE_DIM_COLOR, NODE_STROKE, 0.3)
            entry.glyph.Text = "?"
            entry.glyph.TextColor3 = TEXT_DIM_COLOR
            entry.price.Text = ""
        end

        if selectedId == nodeId then
            stopBreath(entry)
            setStrokeStyle(entry.stroke, SELECT_COLOR, SELECT_STROKE, 0)
        end

        local wantsRing = highlightId == nodeId and visual ~= "owned" and visual ~= "silhouette"
        entry.ring.Visible = wantsRing
        if wantsRing and entry.ringPulse == nil then
            local tween = TweenService:Create(
                entry.ringStroke,
                TweenInfo.new(PULSE_SECONDS, PULSE_EASING, Enum.EasingDirection.InOut, -1, true),
                { Transparency = 0.85 }
            )
            entry.ringPulse = tween
            tween:Play()
        elseif not wantsRing then
            stopRingPulse(entry)
        end
    end

    ---------------------------------------------------------------- Linien, Bänder, Nebel
    local function newLine(parent: Instance, x: number, yTop: number, length: number, style: string)
        local color = if style == "lit" then LINE_LIT_COLOR else LINE_DIM_COLOR
        if style ~= "dashed" then
            local line = Instance.new("Frame")
            line.Name = "Line"
            line.AnchorPoint = Vector2.new(0.5, 0)
            line.Position = framePosition(x, yTop)
            line.Size = UDim2.fromOffset(LINE_WIDTH, length)
            line.BackgroundColor3 = color
            line.BorderSizePixel = 0
            line.ZIndex = 12
            line.Parent = parent
            return
        end
        local offset = 0
        while offset < length do
            local dash = Instance.new("Frame")
            dash.Name = "Dash"
            dash.AnchorPoint = Vector2.new(0.5, 0)
            dash.Position = framePosition(x, yTop + offset)
            dash.Size = UDim2.fromOffset(LINE_WIDTH, math.min(DASH_LENGTH, length - offset))
            dash.BackgroundColor3 = color
            dash.BorderSizePixel = 0
            dash.ZIndex = 12
            dash.Parent = parent
            offset += DASH_LENGTH + DASH_GAP
        end
    end

    local function rebuildDecor()
        lineFolder:ClearAllChildren()
        bandFolder:ClearAllChildren()

        for _, line in view.lines do
            local from = layout.nodes[line.from]
            local to = layout.nodes[line.to]
            -- `to` liegt über `from` (kleineres y): Linie von der Oberkante von `from` bis zur Unterkante von `to`.
            local yTop = to.y + half
            local length = (from.y - half) - yTop
            if length > 0 then
                newLine(lineFolder, from.x, yTop, length, line.style)
            end
        end

        for _, band in view.bands do
            if band.visual ~= "hidden" then
                local rule = Instance.new("Frame")
                rule.Name = "Band" .. band.index
                rule.Position = framePosition(area.minX, band.y)
                rule.Size = UDim2.fromOffset(area.width, BAND_LINE_HEIGHT)
                rule.BackgroundColor3 = LINE_DIM_COLOR
                rule.BackgroundTransparency = 0.5
                rule.BorderSizePixel = 0
                rule.ZIndex = 11
                rule.Parent = bandFolder
                local name = label(rule, "Name", UDim2.new(0, 6, 0, -BAND_LABEL_HEIGHT - 1), UDim2.fromOffset(220, BAND_LABEL_HEIGHT), Enum.Font.GothamBold, Enum.TextXAlignment.Left)
                name.TextColor3 = TEXT_DIM_COLOR
                name.ZIndex = 11
                local tool = if band.toolId ~= nil then UpgradeTree.byId[band.toolId] else nil
                name.Text = if band.visual == "silhouette" or tool == nil then "?" else tool.name
            end
        end

        -- Nebel über dem obersten sichtbaren Knoten
        local topY = 0
        for nodeId, visual in view.nodes do
            if visual ~= "hidden" then
                topY = math.min(topY, layout.nodes[nodeId].y)
            end
        end
        local fogHeight = (topY - half - FOG_GAP) - area.minY
        fog.Visible = fogHeight > 0
        fog.Size = UDim2.fromOffset(area.width, math.max(fogHeight, 0))
    end

    ---------------------------------------------------------------- Karte
    local function neededNames(needs: { string }): string
        local names: { string } = {}
        for _, id in needs do
            local visual = view.nodes[id]
            local node = UpgradeTree.byId[id]
            if node ~= nil and visual ~= nil and visual ~= "hidden" and visual ~= "silhouette" then
                table.insert(names, node.name)
            else
                table.insert(names, UNKNOWN_NAME)
            end
        end
        return table.concat(names, ", ")
    end

    local function refreshCard()
        local id = selectedId
        local info = if id ~= nil and view ~= nil then TreeView.info(view, id) else nil
        if id == nil or info == nil then
            card.Visible = false
            return
        end
        card.Visible = true
        cardName.Text = info.name or UNKNOWN_NAME
        cardDescription.Text = info.description or UNKNOWN_DESCRIPTION
        cardNeeds.Text = if #info.needs > 0 then NEEDS_TEXT .. neededNames(info.needs) else ""
        if info.visual == "owned" then
            buyButton.Text = OWNED_TEXT
            buyButton.BackgroundColor3 = BUTTON_DIM_COLOR
            buyButton.TextColor3 = TEXT_DIM_COLOR
        elseif info.visual == "silhouette" then
            buyButton.Text = HIDDEN_BUY_TEXT
            buyButton.BackgroundColor3 = BUTTON_DIM_COLOR
            buyButton.TextColor3 = TEXT_DIM_COLOR
        else
            buyButton.Text = BUY_TEXT .. " " .. BigNum.format(BigNum.new(info.cost or 0))
            buyButton.BackgroundColor3 = if info.visual == "affordable" then BUTTON_COLOR else BUTTON_DIM_COLOR
            buyButton.TextColor3 = if info.visual == "affordable" then TEXT_COLOR else TEXT_DIM_COLOR
        end
    end

    local function selectNode(nodeId: string?)
        local previous = selectedId
        selectedId = nodeId
        if view ~= nil then
            if previous ~= nil and entries[previous] ~= nil then
                styleNode(previous)
            end
            if nodeId ~= nil and entries[nodeId] ~= nil then
                styleNode(nodeId)
            end
        end
        refreshCard()
    end

    local function onBuy()
        local id = selectedId
        if id == nil then
            return
        end
        local info = if view ~= nil then TreeView.info(view, id) else nil
        if info == nil or info.visual == "owned" or info.visual == "silhouette" then
            return
        end
        if busy then
            showFeedback(MESSAGES.busy)
            return
        end
        busy = true
        task.spawn(function()
            local ok, response = pcall(function(): any
                return purchase:InvokeServer(id)
            end)
            busy = false
            if not ok or type(response) ~= "table" then
                showFeedback(MESSAGES.unknown)
            elseif response.ok == true then
                local node = UpgradeTree.byId[id]
                showFeedback(BOUGHT_TEXT .. (if node ~= nil then node.name else id))
            else
                showFeedback(MESSAGES[response.reason] or MESSAGES.unknown)
            end
        end)
    end

    ---------------------------------------------------------------- Aktualisieren
    local function refresh(newSnapshot: any)
        snapshot = newSnapshot
        local step = newSnapshot.tutorialStep or 1
        local current = TutorialData.steps[step]
        highlightId = if current ~= nil then current.highlightNodeId else nil

        local profile = { nodes = newSnapshot.nodes or {}, coins = newSnapshot.coins }
        view = TreeView.build(profile, layout)

        openButton.Visible = step >= TutorialData.showUpgradesFromStep
        badge.Visible = view.counter > 0
        badge.Text = tostring(view.counter)
        coinsLabel.Text = "Münzen: " .. BigNum.format(BigNum.deserialize(newSnapshot.coins))

        -- Der Knopf pulsiert, solange das Tutorial auf einen Baumknoten zeigt und der Baum zu ist.
        local pulseOpen = highlightId ~= nil and not isOpen
        if pulseOpen and openPulse == nil then
            openStroke.Transparency = 0.1
            local tween = TweenService:Create(
                openStroke,
                TweenInfo.new(PULSE_SECONDS, PULSE_EASING, Enum.EasingDirection.InOut, -1, true),
                { Transparency = 0.85 }
            )
            openPulse = tween
            tween:Play()
        elseif not pulseOpen and openPulse ~= nil then
            (openPulse :: Tween):Cancel()
            openPulse = nil
            openStroke.Transparency = 1
        end

        -- Knoten anlegen (einmal) und neu einfärben, Linien nur bei Änderung neu bauen.
        positions = {}
        local parts: { string } = {}
        for _, node in UpgradeTree.list do
            if entries[node.id] == nil then
                entries[node.id] = makeNode(node.id)
            end
            local visual: string = view.nodes[node.id]
            table.insert(parts, visual)
            if visual ~= "hidden" then
                positions[node.id] = { x = layout.nodes[node.id].x, y = layout.nodes[node.id].y }
            end
            styleNode(node.id)
        end
        for _, line in view.lines do
            table.insert(parts, line.from .. ">" .. line.to .. ":" .. line.style)
        end
        for _, band in view.bands do
            table.insert(parts, "b" .. band.index .. band.visual)
        end
        local signature = table.concat(parts, ",")
        if signature ~= lastSignature then
            lastSignature = signature
            rebuildDecor()
        end
        if selectedId ~= nil and view.nodes[selectedId] == "hidden" then
            selectedId = nil
        end
        refreshCard()
    end

    ---------------------------------------------------------------- Öffnen und Schließen
    local function focusCamera()
        local focusId = TreeView.focus(view, highlightId)
        local target = if focusId ~= nil then layout.nodes[focusId] else layout.start
        local base = { zoom = LayoutConfig.zoom.start, panX = 0, panY = 0 }
        setCamera(TreeCamera.centerOn(base, { x = target.x, y = target.y }, viewport(), area))
    end

    local function open()
        if isOpen or view == nil then
            return
        end
        isOpen = true
        Input.setSuspended(true)
        overlay.Visible = true
        if canvas.AbsoluteSize.X <= 0 then
            task.wait() -- die Größe steht erst nach dem nächsten Bild fest
        end
        selectedId = nil
        refresh(snapshot)
        focusCamera()
    end

    local function close()
        if not isOpen then
            return
        end
        isOpen = false
        overlay.Visible = false
        selectedId = nil
        card.Visible = false
        Input.setSuspended(false)
        if snapshot ~= nil then
            refresh(snapshot)
        end
    end

    openButton.Activated:Connect(function()
        if isOpen then
            close()
        else
            open()
        end
    end)
    closeButton.Activated:Connect(close)
    buyButton.Activated:Connect(onBuy)
    zoomIn.Activated:Connect(function()
        local size = viewport()
        setCamera(TreeCamera.zoomAt(camera, LayoutConfig.zoom.buttonStep, { x = size.width / 2, y = size.height / 2 }, size, area))
    end)
    zoomOut.Activated:Connect(function()
        local size = viewport()
        setCamera(TreeCamera.zoomAt(camera, 1 / LayoutConfig.zoom.buttonStep, { x = size.width / 2, y = size.height / 2 }, size, area))
    end)
    canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if isOpen then
            setCamera(TreeCamera.clamp(camera, viewport(), area))
        end
    end)

    UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
        if isOpen and input.KeyCode == Enum.KeyCode.Escape then
            close()
        end
    end)

    ---------------------------------------------------------------- Gesten
    local pointers: { [InputObject]: Vector2 } = {}
    local order: { InputObject } = {}
    local gestureMoved = 0
    local gestureWasPinch = false

    local function localPosition(position: Vector3): Vector2
        return Vector2.new(position.X, position.Y) - canvas.AbsolutePosition
    end

    local function isPointerType(input: InputObject): boolean
        return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
    end

    local function point(v: Vector2): any
        return { x = v.X, y = v.Y }
    end

    local function tap(position: Vector2)
        local worldPoint = TreeCamera.toWorld(camera, point(position))
        local hit = TreeCamera.hitTest(positions, worldPoint)
        if hit ~= nil and hit == selectedId then
            selectNode(nil)
        else
            selectNode(hit)
        end
    end

    canvas.InputBegan:Connect(function(input: InputObject)
        if not isPointerType(input) or pointers[input] ~= nil then
            return
        end
        if #order == 0 then
            gestureMoved = 0
            gestureWasPinch = false
        end
        pointers[input] = localPosition(input.Position)
        table.insert(order, input)
        if #order >= 2 then
            gestureWasPinch = true
        end
    end)

    local function moveTo(input: InputObject, newPosition: Vector2)
        local old = pointers[input]
        if old == nil then
            return
        end
        gestureMoved += (newPosition - old).Magnitude
        if #order >= 2 and (input == order[1] or input == order[2]) then
            local first, second = order[1], order[2]
            local oldA, oldB = pointers[first], pointers[second]
            local newA = if input == first then newPosition else oldA
            local newB = if input == second then newPosition else oldB
            setCamera(TreeCamera.pinch(camera, point(oldA), point(oldB), point(newA), point(newB), viewport(), area))
        elseif #order == 1 then
            setCamera(TreeCamera.drag(camera, newPosition.X - old.X, newPosition.Y - old.Y, viewport(), area))
        end
        pointers[input] = newPosition
    end

    UserInputService.InputChanged:Connect(function(input: InputObject, _processed: boolean)
        if not isOpen then
            return
        end
        if input.UserInputType == Enum.UserInputType.Touch then
            if pointers[input] ~= nil then
                moveTo(input, localPosition(input.Position))
            end
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            -- Bei der Maus bewegt das MouseMovement-Objekt den gedrückten MouseButton1-Zeiger.
            for pointer in pointers do
                if pointer.UserInputType == Enum.UserInputType.MouseButton1 then
                    moveTo(pointer, localPosition(input.Position))
                end
            end
        elseif input.UserInputType == Enum.UserInputType.MouseWheel then
            local position = localPosition(input.Position)
            local size = viewport()
            if position.X >= 0 and position.Y >= 0 and position.X <= size.width and position.Y <= size.height then
                local factor = LayoutConfig.zoom.wheelStep ^ input.Position.Z
                setCamera(TreeCamera.zoomAt(camera, factor, point(position), size, area))
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
        if pointers[input] == nil then
            return
        end
        local last = pointers[input]
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            last = localPosition(input.Position)
        end
        pointers[input] = nil
        local index = table.find(order, input)
        if index ~= nil then
            table.remove(order, index)
        end
        if #order == 0 and isOpen and not gestureWasPinch and TreeCamera.isTap(gestureMoved) then
            tap(last)
        end
    end)

    State.onChanged(refresh)
end

return SkillTree
