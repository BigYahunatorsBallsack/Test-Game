--!strict
-- GemShop-Controller (Paket 4.1)
-- Knopf "Gems: N" unten links (neben "Sandsturm"), zeigt den Gem-Stand und öffnet eine schlichte
-- Liste der Gem-Pakete (Menge, Preis in Robux, Bonus). "Kaufen" öffnet nur den Roblox-Kaufdialog
-- (PromptProductPurchase). Die Gutschrift bucht allein der Server in ProcessReceipt. Der Client
-- schickt keine Mengen, und sein Kauf-Signal ist kein Beweis für irgendetwas.
-- Rückmeldung: Notify kind = "gemsBought" (erst nach dem Speichern gesendet) zeigt ein Banner
-- "+N Gems" und lässt den Zähler hochzählen. Der schöne Shop mit Angeboten kommt in Paket 4.5,
-- die Kisten-Quoten-Anzeige in 4.2/4.6.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Knopf und Fenster
local BUTTON_POSITION = UDim2.new(0, 458, 1, -72)
local BUTTON_SIZE = UDim2.new(0, 150, 0, 48)
local PANEL_SCALE = Vector2.new(0.92, 0.8)
local PANEL_MAX_SIZE = Vector2.new(480, 440)
local PANEL_FADE_SECONDS = 0.18
local PANEL_EASING = Enum.EasingStyle.Quad
local ROW_HEIGHT = 56
local ROW_GAP = 8
local MESSAGE_SECONDS = 3
local BUY_COOLDOWN_SECONDS = 1.5 -- gegen Doppeltippen, der Server prüft alles Weitere

-- Zähler und Banner
local COUNT_SECONDS = 0.8 -- so lange zählt der Stand nach einer Gutschrift hoch
local COUNT_EASING = Enum.EasingStyle.Quad
local BANNER_SECONDS = 2.6
local BANNER_FADE_SECONDS = 0.3

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local ROW_COLOR = Color3.fromRGB(64, 52, 40)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local GOOD_COLOR = Color3.fromRGB(150, 220, 120)
local WARN_COLOR = Color3.fromRGB(235, 150, 90)
local BUTTON_COLOR = Color3.fromRGB(80, 66, 52)
local GEM_COLOR = Color3.fromRGB(120, 200, 235)

local TEXT_MISSING_PRODUCT = "Noch nicht eingerichtet."
local TEXT_BUY_FAILED = "Der Kaufdialog ließ sich nicht öffnen."
local TEXT_FULL = "Zu viele Gems: Gib erst welche aus."

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local GemPacks = loadShared("Data", "GemPacks")
local Economy = loadShared("Data", "Economy")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any

local GemShop = {}

local player = Players.LocalPlayer

-- Tausenderpunkt wie im Konzept ("1.200 Gems").
local function groupedNumber(value: number): string
    local text = tostring(math.floor(value))
    local result = text
    while true do
        local replaced, count = string.gsub(result, "^(-?%d+)(%d%d%d)", "%1.%2")
        result = replaced
        if count == 0 then
            break
        end
    end
    return result
end

local function newText(parent: Instance, name: string, position: UDim2, size: UDim2, font: Enum.Font, color: Color3, text: string): TextLabel
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Position = position
    l.Size = size
    l.Font = font
    l.TextColor3 = color
    l.TextScaled = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextWrapped = true
    l.Text = text
    l.Parent = parent
    return l
end

function GemShop.Init() end

function GemShop.Start()
    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronGemShop"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 8
    gui.IgnoreGuiInset = true

    local openButton = Instance.new("TextButton")
    openButton.Name = "GemsButton"
    openButton.Position = BUTTON_POSITION
    openButton.Size = BUTTON_SIZE
    openButton.BackgroundColor3 = BUTTON_COLOR
    openButton.BackgroundTransparency = 0.25
    openButton.Font = Enum.Font.GothamBold
    openButton.TextColor3 = GEM_COLOR
    openButton.TextScaled = true
    openButton.Text = "Gems: 0"
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

    newText(panel, "Title", UDim2.new(0, 16, 0, 10), UDim2.new(1, -72, 0, 32), Enum.Font.GothamBold, TEXT_COLOR, "Gems kaufen")
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "Close"
    closeButton.AnchorPoint = Vector2.new(1, 0)
    closeButton.Position = UDim2.new(1, -8, 0, 8)
    closeButton.Size = UDim2.new(0, 40, 0, 32)
    closeButton.BackgroundColor3 = BUTTON_COLOR
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextColor3 = TEXT_COLOR
    closeButton.TextScaled = true
    closeButton.Text = "X"
    closeButton.Parent = panel
    Instance.new("UICorner").Parent = closeButton

    local balanceLabel = newText(panel, "Balance", UDim2.new(0, 16, 0, 46), UDim2.new(1, -32, 0, 24), Enum.Font.GothamBold, GEM_COLOR, "Du hast 0 Gems")

    local list = Instance.new("ScrollingFrame")
    list.Name = "List"
    list.Position = UDim2.new(0, 12, 0, 78)
    list.Size = UDim2.new(1, -24, 1, -118)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 6
    list.CanvasSize = UDim2.new(0, 0, 0, #GemPacks.list * (ROW_HEIGHT + ROW_GAP))
    list.Parent = panel

    local messageLabel = newText(panel, "Message", UDim2.new(0, 16, 1, -34), UDim2.new(1, -32, 0, 24), Enum.Font.GothamBold, WARN_COLOR, "")

    -- Banner "+N Gems" (liegt über allem)
    local banner = newText(gui, "Banner", UDim2.new(0.5, -260, 0.32, 0), UDim2.new(0, 520, 0, 90), Enum.Font.GothamBold, GEM_COLOR, "")
    banner.TextXAlignment = Enum.TextXAlignment.Center
    banner.TextTransparency = 1
    banner.TextStrokeTransparency = 1
    banner.ZIndex = 21

    local shownGems = 0 -- was gerade angezeigt wird (zählt beim Gutschreiben hoch)
    local targetGems = 0
    local countToken = 0
    local messageToken = 0
    local bannerToken = 0
    local lastBuyAt = 0

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

    local function renderGems(value: number)
        openButton.Text = `Gems: {groupedNumber(value)}`
        balanceLabel.Text = `Du hast {groupedNumber(value)} Gems`
    end

    -- Zählt von der angezeigten Zahl auf `target`. Ein neuer Aufruf ersetzt den laufenden.
    local function countTo(target: number, animate: boolean)
        countToken += 1
        local token = countToken
        targetGems = target
        if not animate or target <= shownGems then
            shownGems = target
            renderGems(shownGems)
            return
        end
        local from = shownGems
        local startedAt = os.clock()
        task.spawn(function()
            while token == countToken do
                local t = math.clamp((os.clock() - startedAt) / COUNT_SECONDS, 0, 1)
                local eased = TweenService:GetValue(t, COUNT_EASING, Enum.EasingDirection.Out)
                shownGems = math.floor(from + (target - from) * eased)
                renderGems(shownGems)
                if t >= 1 then
                    break
                end
                task.wait()
            end
            if token == countToken then
                shownGems = target
                renderGems(shownGems)
            end
        end)
    end

    local function showBanner(gems: number)
        bannerToken += 1
        local token = bannerToken
        banner.Text = `+{groupedNumber(gems)} Gems`
        TweenService:Create(banner, TweenInfo.new(BANNER_FADE_SECONDS), { TextTransparency = 0, TextStrokeTransparency = 0.6 }):Play()
        task.delay(BANNER_SECONDS, function()
            if token ~= bannerToken then
                return
            end
            TweenService:Create(banner, TweenInfo.new(BANNER_FADE_SECONDS), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
        end)
    end

    -- Paketliste aus Data/GemPacks, einmal gebaut. Preise und Mengen stehen nur dort.
    local buyButtons: { [string]: { button: TextButton, pack: any } } = {}
    -- Über der Obergrenze würde das Paket gekappt: nicht kaufen lassen (der Server kappt trotzdem).
    local function wouldOverflow(pack: any): boolean
        return targetGems + pack.gems > Economy.purchases.maxGems
    end
    local function refreshButtons()
        for _, entry in buyButtons do
            local pack = entry.pack
            if pack.productId ~= 0 then
                entry.button.Text = if wouldOverflow(pack) then "Voll" else `{groupedNumber(pack.robux)} Robux`
            end
        end
    end
    for index, pack in GemPacks.list do
        local row = Instance.new("Frame")
        row.Name = pack.id
        row.Position = UDim2.new(0, 0, 0, (index - 1) * (ROW_HEIGHT + ROW_GAP))
        row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
        row.BackgroundColor3 = ROW_COLOR
        row.BackgroundTransparency = 0.2
        row.Parent = list
        Instance.new("UICorner").Parent = row

        newText(row, "Name", UDim2.new(0, 12, 0, 6), UDim2.new(0.5, -12, 0, 26), Enum.Font.GothamBold, TEXT_COLOR, pack.name)
        local bonusText = if pack.bonusPercentConcept > 0 then `+{pack.bonusPercentConcept} % Bonus` else "Einstieg"
        newText(row, "Bonus", UDim2.new(0, 12, 0, 32), UDim2.new(0.5, -12, 0, 18), Enum.Font.Gotham, GOOD_COLOR, bonusText)

        local buy = Instance.new("TextButton")
        buy.Name = "Buy"
        buy.AnchorPoint = Vector2.new(1, 0.5)
        buy.Position = UDim2.new(1, -8, 0.5, 0)
        buy.Size = UDim2.new(0.42, 0, 0, 40)
        buy.BackgroundColor3 = if pack.productId == 0 then BUTTON_COLOR else GEM_COLOR
        buy.Font = Enum.Font.GothamBold
        buy.TextColor3 = if pack.productId == 0 then MUTED_COLOR else PANEL_COLOR
        buy.TextScaled = true
        buy.Text = if pack.productId == 0 then "Bald" else `{groupedNumber(pack.robux)} Robux`
        buy.Parent = row
        Instance.new("UICorner").Parent = buy

        buyButtons[pack.id] = { button = buy, pack = pack }
        buy.Activated:Connect(function()
            if pack.productId == 0 then
                showMessage(TEXT_MISSING_PRODUCT)
                return
            end
            if wouldOverflow(pack) then
                showMessage(TEXT_FULL)
                return
            end
            local now = os.clock()
            if now - lastBuyAt < BUY_COOLDOWN_SECONDS then
                return
            end
            lastBuyAt = now
            local ok = pcall(function()
                MarketplaceService:PromptProductPurchase(player, pack.productId)
            end)
            if not ok then
                showMessage(TEXT_BUY_FAILED)
            end
        end)
    end

    local fade = TweenInfo.new(PANEL_FADE_SECONDS, PANEL_EASING)
    local function setOpen(open: boolean)
        panel.Visible = open
        messageLabel.Text = ""
        if open then
            panel.BackgroundTransparency = 1
            TweenService:Create(panel, fade, { BackgroundTransparency = 0.1 }):Play()
        end
    end
    openButton.Activated:Connect(function()
        setOpen(not panel.Visible)
    end)
    closeButton.Activated:Connect(function()
        setOpen(false)
    end)

    -- Zustand vom Server: der Stand ist maßgeblich. Steigt er ohne Meldung (zum Beispiel Daily
    -- Reward), zählt der Zähler trotzdem hoch.
    local first = true
    State.onChanged(function(snapshot: any)
        if type(snapshot.gems) ~= "number" then
            return
        end
        local gems = math.max(math.floor(snapshot.gems), 0)
        if gems == targetGems and not first then
            return
        end
        countTo(gems, not first)
        first = false
        refreshButtons()
    end)

    State.onNotify(function(payload: any)
        if payload.kind == "gemsBought" and type(payload.gems) == "number" and payload.gems > 0 then
            showBanner(math.floor(payload.gems))
        end
    end)

    gui.Parent = player:WaitForChild("PlayerGui")
end

return GemShop
