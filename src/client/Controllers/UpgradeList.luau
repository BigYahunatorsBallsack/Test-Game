--!strict
-- UpgradeList-Controller (Paket 1.6, schlichte Fassung bis zum Baum in Paket 2.2)
-- Zeigt die Knoten, die der Spieler gerade kaufen kann (Voraussetzungen erfüllt), mit Preis,
-- aufsteigend nach Preis. Zu teure sind ausgegraut. Ein Klick schickt nur die Knoten-ID an den
-- Server (PurchaseNode), der alles prüft. Alle Werte kommen vom Server (State).
-- Vor Schritt Tutorial.showUpgradesFromStep ist die Liste versteckt, damit Anfänger nicht von
-- Knöpfen abgelenkt werden. Der Knoten des aktuellen Tutorial-Schritts leuchtet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Layout
local MAX_ROWS = 4
local PANEL_WIDTH = 270
local ROW_HEIGHT = 46
local ROW_GAP = 6
local HEADER_HEIGHT = 26
local FEEDBACK_HEIGHT = 22
local PANEL_MARGIN = 16

-- Animationen
local FADE_SECONDS = 0.25
local FADE_EASING = Enum.EasingStyle.Sine
local HIGHLIGHT_PULSE_SECONDS = 0.6
local HIGHLIGHT_EASING = Enum.EasingStyle.Sine
local PURCHASE_FLASH_SECONDS = 0.35
local FEEDBACK_VISIBLE_SECONDS = 2

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local ROW_AFFORD_COLOR = Color3.fromRGB(96, 78, 44)
local ROW_LOCKED_COLOR = Color3.fromRGB(58, 52, 46)
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 220, 120)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local TEXT_DIM_COLOR = Color3.fromRGB(170, 160, 145)

local MESSAGES = {
    coins = "Zu wenig Münzen.",
    requires = "Dafür fehlt noch ein anderes Upgrade.",
    owned = "Schon gekauft.",
    unknown = "Das geht gerade nicht.",
    granted = "Das geht gerade nicht.",
    busy = "Einen Moment ...",
}
local BOUGHT_TEXT = "Gekauft: "

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local BigNum = loadShared("Logic", "BigNum")
local TreePurchase = loadShared("Logic", "TreePurchase")
local TutorialData = loadShared("Data", "Tutorial")
local UpgradeTree = loadShared("Data", "UpgradeTree")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any

local UpgradeList = {}

type Row = {
    button: TextButton,
    price: TextLabel,
    stroke: UIStroke,
    pulse: Tween?,
}

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

function UpgradeList.Init() end

function UpgradeList.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local purchase = remotes:WaitForChild("PurchaseNode") :: RemoteFunction

    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronUpgrades"
    gui.ResetOnSpawn = false

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(1, 0)
    panel.Position = UDim2.new(1, -PANEL_MARGIN, 0, PANEL_MARGIN)
    panel.Size = UDim2.new(0, PANEL_WIDTH, 0, HEADER_HEIGHT)
    panel.BackgroundColor3 = PANEL_COLOR
    panel.BackgroundTransparency = 0.25
    panel.Visible = false
    panel.Parent = gui
    Instance.new("UICorner").Parent = panel

    local header = label(panel, "Header", UDim2.new(0, 12, 0, 4), UDim2.new(1, -24, 0, HEADER_HEIGHT - 8), Enum.Font.GothamBold, Enum.TextXAlignment.Left)
    header.Text = "Upgrades"

    local feedback = label(panel, "Feedback", UDim2.new(0, 12, 1, -FEEDBACK_HEIGHT), UDim2.new(1, -24, 0, FEEDBACK_HEIGHT - 4), Enum.Font.Gotham, Enum.TextXAlignment.Left)
    feedback.TextTransparency = 1

    gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

    local rows: { [string]: Row } = {}
    local order: { string } = {}
    local busy = false
    local feedbackToken = 0

    local fadeInfo = TweenInfo.new(FADE_SECONDS, FADE_EASING)
    local function showFeedback(text: string)
        feedbackToken += 1
        local token = feedbackToken
        feedback.Text = text
        TweenService:Create(feedback, fadeInfo, { TextTransparency = 0 }):Play()
        task.delay(FEEDBACK_VISIBLE_SECONDS, function()
            if token == feedbackToken then
                TweenService:Create(feedback, fadeInfo, { TextTransparency = 1 }):Play()
            end
        end)
    end

    local function layout()
        local count = math.min(#order, MAX_ROWS)
        for index, nodeId in order do
            local row = rows[nodeId]
            row.button.Visible = index <= count
            row.button.Position = UDim2.new(0, 8, 0, HEADER_HEIGHT + (index - 1) * (ROW_HEIGHT + ROW_GAP))
        end
        local height = HEADER_HEIGHT + FEEDBACK_HEIGHT + 4
        if count > 0 then
            height += count * ROW_HEIGHT + (count - 1) * ROW_GAP
        end
        panel.Size = UDim2.new(0, PANEL_WIDTH, 0, height)
        feedback.Position = UDim2.new(0, 12, 1, -FEEDBACK_HEIGHT)
    end

    local function onClick(nodeId: string)
        if busy then
            showFeedback(MESSAGES.busy)
            return
        end
        busy = true
        task.spawn(function()
            local ok, response = pcall(function(): any
                return purchase:InvokeServer(nodeId)
            end)
            busy = false
            if not ok or type(response) ~= "table" then
                showFeedback(MESSAGES.unknown)
            elseif response.ok == true then
                local node = UpgradeTree.byId[nodeId]
                showFeedback(BOUGHT_TEXT .. (if node ~= nil then node.name else nodeId))
            else
                showFeedback(MESSAGES[response.reason] or MESSAGES.unknown)
            end
        end)
    end

    local function makeRow(nodeId: string): Row
        local node = UpgradeTree.byId[nodeId]
        local button = Instance.new("TextButton")
        button.Name = nodeId
        button.AutoButtonColor = true
        button.Text = ""
        button.Size = UDim2.new(1, -16, 0, ROW_HEIGHT)
        button.BackgroundColor3 = ROW_LOCKED_COLOR
        button.Parent = panel
        Instance.new("UICorner").Parent = button
        local stroke = Instance.new("UIStroke")
        stroke.Color = HIGHLIGHT_COLOR
        stroke.Thickness = 2
        stroke.Transparency = 1
        stroke.Parent = button

        local name = label(button, "Name", UDim2.new(0, 8, 0, 3), UDim2.new(0.6, -8, 0, 22), Enum.Font.GothamBold, Enum.TextXAlignment.Left)
        name.Text = node.name
        local description = label(button, "Description", UDim2.new(0, 8, 0, 25), UDim2.new(1, -16, 0, 16), Enum.Font.Gotham, Enum.TextXAlignment.Left)
        description.Text = node.description
        description.TextColor3 = TEXT_DIM_COLOR
        local price = label(button, "Price", UDim2.new(0.6, 0, 0, 3), UDim2.new(0.4, -8, 0, 22), Enum.Font.GothamBold, Enum.TextXAlignment.Right)
        price.Text = BigNum.format(BigNum.new(node.cost))

        button.Activated:Connect(function()
            onClick(nodeId)
        end)
        return { button = button, price = price, stroke = stroke, pulse = nil }
    end

    local function setHighlight(row: Row, on: boolean)
        if on and row.pulse == nil then
            row.stroke.Transparency = 0.2
            local tween = TweenService:Create(
                row.stroke,
                TweenInfo.new(HIGHLIGHT_PULSE_SECONDS, HIGHLIGHT_EASING, Enum.EasingDirection.InOut, -1, true),
                { Transparency = 0.9 }
            )
            row.pulse = tween
            tween:Play()
        elseif not on and row.pulse ~= nil then
            (row.pulse :: Tween):Cancel()
            row.pulse = nil
            row.stroke.Transparency = 1
        end
    end

    local function refresh(snapshot: any)
        local step = snapshot.tutorialStep or 1
        local show = step >= TutorialData.showUpgradesFromStep
        panel.Visible = show
        local owned = snapshot.nodes or {}
        local visible: { string } = TreePurchase.visible({ nodes = owned })
        -- Zeilen für verschwundene Knoten entfernen, neue anlegen.
        local wanted: { [string]: boolean } = {}
        for _, nodeId in visible do
            wanted[nodeId] = true
        end
        for nodeId, row in rows do
            if not wanted[nodeId] then
                setHighlight(row, false)
                row.button:Destroy()
                rows[nodeId] = nil
            end
        end
        for _, nodeId in visible do
            if rows[nodeId] == nil then
                rows[nodeId] = makeRow(nodeId)
            end
        end
        order = visible
        layout()
        local coins = BigNum.deserialize(snapshot.coins)
        local current = TutorialData.steps[step]
        local highlightId = if current ~= nil then current.highlightNodeId else nil
        for nodeId, row in rows do
            local node = UpgradeTree.byId[nodeId]
            local affordable = BigNum.compare(coins, BigNum.new(node.cost)) >= 0
            local goal = if affordable then ROW_AFFORD_COLOR else ROW_LOCKED_COLOR
            if row.button.BackgroundColor3 ~= goal then
                TweenService:Create(row.button, TweenInfo.new(PURCHASE_FLASH_SECONDS, FADE_EASING), { BackgroundColor3 = goal }):Play()
            end
            row.price.TextColor3 = if affordable then TEXT_COLOR else TEXT_DIM_COLOR
            setHighlight(row, highlightId == nodeId)
        end
    end

    layout()
    -- Ruft sofort einmal auf, wenn schon ein Zustand da ist.
    State.onChanged(refresh)
end

return UpgradeList
