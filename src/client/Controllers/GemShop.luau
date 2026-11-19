--!strict
-- GemShop-Controller (Paket 4.1, Handy-Durchgang 3.6)
-- Knopf "Gems: N" in der Menüleiste (Controllers/Screen), zeigt den Gem-Stand und öffnet ein Fenster
-- mit den Gem-Paketen (Menge, Preis in Robux, Bonus). "Kaufen" öffnet nur den Roblox-Kaufdialog
-- (PromptProductPurchase). Die Gutschrift bucht allein der Server in ProcessReceipt. Der Client
-- schickt keine Mengen, und sein Kauf-Signal ist kein Beweis für irgendetwas.
-- Rückmeldung: Notify kind = "gemsBought" (erst nach dem Speichern gesendet) zeigt ein Banner
-- "+N Gems" und lässt den Zähler hochzählen. Der schöne Shop mit Angeboten kommt in Paket 4.5.
--
-- Pässe und Boosts (Paket 4.4): Unter den Gem-Paketen stehen die Gamepasses und der Münz-Boost aus
-- Data/Products. "Kaufen" öffnet nur PromptGamePassPurchase bzw. PromptProductPurchase; ob ein Pass
-- wirkt, entscheidet allein der Server (Snapshot-Feld `passes`). Wer Auto-Dig besitzt, schaltet es
-- in dessen Zeile an und aus (Remote SetAutoDig, nur ein Boolean). Die Restzeit des Boosts kommt
-- vom Server (`coinBoostSeconds`) und zählt hier nur lokal herunter.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Menüleiste und Zeilen
local MENU_ORDER = 5 -- Platz in der Menüleiste (nach Zonen, Sammlung, Sandsturm und Kisten)
local FOOTER_HEIGHT = 64
local ROW_HEIGHT = 64
local MESSAGE_SECONDS = 3
local BUY_COOLDOWN_SECONDS = 1.5 -- gegen Doppeltippen, der Server prüft alles Weitere
local PERK_ROW_HEIGHT = 92 -- Zeilen der Pässe (Wirkungstext braucht zwei Zeilen)
local PERK_SECTION_ORDER = 100 -- LayoutOrder der Überschrift "Pässe und Boosts" (nach den Gem-Paketen)
local SECTION_HEIGHT = 34
local TOGGLE_COOLDOWN_SECONDS = 0.6 -- Auto-Dig-Schalter, der Server hat sein eigenes Limit
local BOOST_TICK_SECONDS = 0.5 -- so oft wird die Restzeit des Boosts neu geschrieben

-- Zähler und Banner
local COUNT_SECONDS = 0.8 -- so lange zählt der Stand nach einer Gutschrift hoch
local COUNT_EASING = Enum.EasingStyle.Quad
local BANNER_SECONDS = 2.6
local BANNER_FADE_SECONDS = 0.3
local BANNER_DISPLAY_ORDER = 9

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
local TEXT_SECTION = "Pässe und Boosts"
local TEXT_OWNED = "Gekauft"
local TEXT_SOON = "Bald"
local TEXT_AUTO_ON = "Auto: an"
local TEXT_AUTO_OFF = "Auto: aus"
local TEXT_BOOST_BOUGHT = "Münz-Boost aktiv!"
local TEXT_BOOST_REALTIME = "Läuft in Echtzeit, auch offline"
local TOGGLE_ON_COLOR = Color3.fromRGB(150, 220, 120)
local PASS_COLOR = Color3.fromRGB(255, 214, 110)

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local GemPacks = loadShared("Data", "GemPacks")
local Products = loadShared("Data", "Products")
local Economy = loadShared("Data", "Economy")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

local GemShop = {}

local player = Players.LocalPlayer

-- Sekunden als "m:ss" oder ab einer Stunde "h:mm:ss".
local function clockText(seconds: number): string
    local total = math.max(math.ceil(seconds), 0)
    local h = total // 3600
    local m = (total % 3600) // 60
    local sec = total % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, sec)
    end
    return string.format("%d:%02d", m, sec)
end

-- Produkte für den Bereich "Pässe und Boosts": alle Gamepasses und die Verbrauchsprodukte (Münz-Boost).
local function isPerkProduct(product: any): boolean
    return product.kind == "gamepass" or (product.kind == "developerProduct" and product.consumable == true)
end

-- Tausenderpunkt wie im Konzept ("1.200 Gems").
local function groupedNumber(value: number): string
    local result = tostring(math.floor(value))
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
    local controls = Screen.controls()
    local window = Screen.createWindow({
        name = "GemWindow",
        title = "Gems und Pässe",
        kind = "narrow",
        footerHeight = FOOTER_HEIGHT,
    })
    local openButton = Screen.addMenuButton("GemsButton", "Gems: 0", MENU_ORDER)
    openButton.TextColor3 = GEM_COLOR
    openButton.Activated:Connect(window.toggle)

    -- Kontostand und Meldung im festen Fuß, damit sie beim Scrollen der Liste stehen bleiben.
    local balanceLabel = newText(window.footer, "Balance", UDim2.new(0, 12, 0, 4), UDim2.new(1, -24, 0, 26), Enum.Font.GothamBold, GEM_COLOR, "Du hast 0 Gems")
    local messageLabel = newText(window.footer, "Message", UDim2.new(0, 12, 0, 34), UDim2.new(1, -24, 0, 24), Enum.Font.GothamBold, WARN_COLOR, "")

    -- Banner "+N Gems" (liegt über allem)
    local bannerGui = Instance.new("ScreenGui")
    bannerGui.Name = "DuneBaronGemBanner"
    bannerGui.ResetOnSpawn = false
    bannerGui.DisplayOrder = BANNER_DISPLAY_ORDER
    bannerGui.IgnoreGuiInset = true
    local banner = newText(bannerGui, "Banner", UDim2.new(0.5, -260, 0.32, 0), UDim2.new(0, 520, 0, 90), Enum.Font.GothamBold, GEM_COLOR, "")
    banner.TextXAlignment = Enum.TextXAlignment.Center
    banner.TextTransparency = 1
    banner.TextStrokeTransparency = 1
    bannerGui.Parent = player:WaitForChild("PlayerGui")

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

    local function showBanner(text: string)
        bannerToken += 1
        local token = bannerToken
        banner.Text = text
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
        row.LayoutOrder = index
        row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
        row.BackgroundColor3 = ROW_COLOR
        row.BackgroundTransparency = 0.2
        row.Parent = window.body
        Instance.new("UICorner").Parent = row

        newText(row, "Name", UDim2.new(0, 12, 0, 8), UDim2.new(0.5, -12, 0, 26), Enum.Font.GothamBold, TEXT_COLOR, pack.name)
        local bonusText = if pack.bonusPercentConcept > 0 then `+{pack.bonusPercentConcept} % Bonus` else "Einstieg"
        newText(row, "Bonus", UDim2.new(0, 12, 0, 36), UDim2.new(0.5, -12, 0, 20), Enum.Font.Gotham, GOOD_COLOR, bonusText)

        local buy = Instance.new("TextButton")
        buy.Name = "Buy"
        buy.AnchorPoint = Vector2.new(1, 0.5)
        buy.Position = UDim2.new(1, -8, 0.5, 0)
        buy.Size = UDim2.new(0.42, 0, 0, controls.rowButtonH)
        buy.BackgroundColor3 = if pack.productId == 0 then BUTTON_COLOR else GEM_COLOR
        buy.Font = Enum.Font.GothamBold
        buy.TextColor3 = if pack.productId == 0 then MUTED_COLOR else PANEL_COLOR
        buy.TextScaled = true
        buy.Text = if pack.productId == 0 then "Bald" else `{groupedNumber(pack.robux)} Robux`
        buy.Parent = row
        Instance.new("UICorner").Parent = buy
        local buyPadding = Instance.new("UIPadding")
        buyPadding.PaddingTop = UDim.new(0, 8)
        buyPadding.PaddingBottom = UDim.new(0, 8)
        buyPadding.Parent = buy

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

    -- Pässe und Boosts (Paket 4.4): Überschrift und eine Zeile je Produkt aus Data/Products.
    local section = newText(window.body, "PerkSection", UDim2.new(), UDim2.new(1, 0, 0, SECTION_HEIGHT), Enum.Font.GothamBold, PASS_COLOR, TEXT_SECTION)
    section.LayoutOrder = PERK_SECTION_ORDER

    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local passes: { [string]: boolean } = {}
    local autoDigOn = false
    local boostEndsAt = 0
    local lastToggleAt = 0
    local perkRows: { { product: any, button: TextButton, status: TextLabel } } = {}

    local function sendAutoDig(enabled: boolean)
        local remote = remotes:FindFirstChild("SetAutoDig")
        if remote == nil then
            return
        end
        if remote:IsA("RemoteEvent") then
            remote:FireServer(enabled)
        elseif remote:IsA("RemoteFunction") then
            local invoker = remote :: RemoteFunction
            task.spawn(function()
                pcall(function()
                    invoker:InvokeServer(enabled)
                end)
            end)
        end
    end

    local function styleButton(button: TextButton, active: boolean, color: Color3)
        button.BackgroundColor3 = if active then color else BUTTON_COLOR
        button.TextColor3 = if active then PANEL_COLOR else MUTED_COLOR
    end

    local function renderPerkRows()
        local boostLeft = boostEndsAt - os.clock()
        for _, entry in perkRows do
            local product, button, status = entry.product, entry.button, entry.status
            if product.kind == "gamepass" then
                if passes[product.id] == true then
                    if product.perk == "autoDig" then
                        button.Text = if autoDigOn then TEXT_AUTO_ON else TEXT_AUTO_OFF
                        styleButton(button, autoDigOn, TOGGLE_ON_COLOR)
                    else
                        button.Text = TEXT_OWNED
                        styleButton(button, false, PASS_COLOR)
                    end
                    status.Text = TEXT_OWNED
                else
                    button.Text = if product.productId == 0 then TEXT_SOON else `{groupedNumber(product.priceRobux)} Robux`
                    styleButton(button, product.productId ~= 0, PASS_COLOR)
                    status.Text = ""
                end
            else
                button.Text = if product.productId == 0 then TEXT_SOON else `{groupedNumber(product.priceRobux)} Robux`
                styleButton(button, product.productId ~= 0, PASS_COLOR)
                -- Die Boost-Zeit läuft in echter Zeit, auch offline: das steht vor dem Kauf da (balance 4.4).
                status.Text = if boostLeft > 0 then `Läuft noch {clockText(boostLeft)}, auch offline` else TEXT_BOOST_REALTIME
            end
        end
    end

    for index, product in Products.list do
        if not isPerkProduct(product) then
            continue
        end
        local row = Instance.new("Frame")
        row.Name = product.id
        row.LayoutOrder = PERK_SECTION_ORDER + index
        row.Size = UDim2.new(1, 0, 0, PERK_ROW_HEIGHT)
        row.BackgroundColor3 = ROW_COLOR
        row.BackgroundTransparency = 0.2
        row.Parent = window.body
        Instance.new("UICorner").Parent = row

        newText(row, "Name", UDim2.new(0, 12, 0, 6), UDim2.new(0.55, -12, 0, 24), Enum.Font.GothamBold, TEXT_COLOR, product.name)
        local effect = newText(row, "Effect", UDim2.new(0, 12, 0, 32), UDim2.new(0.55, -12, 0, 36), Enum.Font.Gotham, MUTED_COLOR, product.effect)
        effect.TextYAlignment = Enum.TextYAlignment.Top
        local status = newText(row, "Status", UDim2.new(0, 12, 1, -22), UDim2.new(0.55, -12, 0, 18), Enum.Font.GothamBold, GOOD_COLOR, "")

        local buy = Instance.new("TextButton")
        buy.Name = "Buy"
        buy.AnchorPoint = Vector2.new(1, 0.5)
        buy.Position = UDim2.new(1, -8, 0.5, 0)
        buy.Size = UDim2.new(0.4, 0, 0, controls.rowButtonH)
        buy.Font = Enum.Font.GothamBold
        buy.TextScaled = true
        buy.Parent = row
        Instance.new("UICorner").Parent = buy
        local buyPadding = Instance.new("UIPadding")
        buyPadding.PaddingTop = UDim.new(0, 8)
        buyPadding.PaddingBottom = UDim.new(0, 8)
        buyPadding.Parent = buy

        table.insert(perkRows, { product = product, button = buy, status = status })
        buy.Activated:Connect(function()
            local owned = product.kind == "gamepass" and passes[product.id] == true
            if owned then
                if product.perk == "autoDig" then
                    local now = os.clock()
                    if now - lastToggleAt < TOGGLE_COOLDOWN_SECONDS then
                        return
                    end
                    lastToggleAt = now
                    sendAutoDig(not autoDigOn)
                end
                return
            end
            if product.productId == 0 then
                showMessage(TEXT_MISSING_PRODUCT)
                return
            end
            local now = os.clock()
            if now - lastBuyAt < BUY_COOLDOWN_SECONDS then
                return
            end
            lastBuyAt = now
            local ok = pcall(function()
                if product.kind == "gamepass" then
                    MarketplaceService:PromptGamePassPurchase(player, product.productId)
                else
                    MarketplaceService:PromptProductPurchase(player, product.productId)
                end
            end)
            if not ok then
                showMessage(TEXT_BUY_FAILED)
            end
        end)
    end
    renderPerkRows()

    -- Restzeit des Boosts lokal herunterzählen (der nächste Snapshot setzt sie wieder auf den Serverwert).
    task.spawn(function()
        while true do
            task.wait(BOOST_TICK_SECONDS)
            if boostEndsAt > 0 then
                renderPerkRows()
                if boostEndsAt <= os.clock() then
                    boostEndsAt = 0
                end
            end
        end
    end)

    State.onChanged(function(snapshot: any)
        local nextPasses: { [string]: boolean } = {}
        if type(snapshot.passes) == "table" then
            for id, value in snapshot.passes do
                if type(id) == "string" and value == true then
                    nextPasses[id] = true
                end
            end
        end
        passes = nextPasses
        autoDigOn = snapshot.autoDig == true
        local seconds = snapshot.coinBoostSeconds
        boostEndsAt = if type(seconds) == "number" and seconds == seconds and seconds > 0 then os.clock() + seconds else 0
        renderPerkRows()
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
            showBanner(`+{groupedNumber(math.floor(payload.gems))} Gems`)
        elseif payload.kind == "boostBought" then
            showBanner(TEXT_BOOST_BOUGHT)
        end
    end)
end

return GemShop
