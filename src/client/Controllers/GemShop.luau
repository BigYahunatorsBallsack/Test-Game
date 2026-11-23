--!strict
-- GemShop-Controller (Paket 4.1, Handy-Durchgang 3.6)
-- Knopf "Gems: N" in der Menüleiste (Controllers/Screen), zeigt den Gem-Stand und öffnet ein Fenster
-- mit den Gem-Paketen (Menge, Preis in Robux, Bonus). "Kaufen" öffnet nur den Roblox-Kaufdialog
-- (PromptProductPurchase). Die Gutschrift bucht allein der Server in ProcessReceipt. Der Client
-- schickt keine Mengen, und sein Kauf-Signal ist kein Beweis für irgendetwas.
-- Rückmeldung: Notify kind = "gemsBought" (erst nach dem Speichern gesendet) zeigt ein Banner
-- "+N Gems" und lässt den Zähler hochzählen.
--
-- Shop (Paket 4.5): Das Fenster heißt "Shop" und hat Reiter: "Angebote" (nur sichtbar, solange der
-- Server ein Angebot als aktiv meldet, Snapshot-Feld `offers`), "Gems", "Pässe" und "Kisten" (öffnet
-- das Kisten-Fenster, nur wenn der Server Kisten erlaubt). Läuft ein Angebot, öffnet der Shop bei
-- "Angebote". Kauf wie bei den Gem-Paketen: Der Client öffnet nur PromptProductPurchase, Inhalt,
-- Preis und Zeitfenster stehen in Data/Offers und Data/Products, der Server bucht allein. Den
-- Countdown zählt der Client nur lokal herunter (Restzeit kommt vom Server).
--
-- Pässe und Boosts (Paket 4.4): Unter den Gem-Paketen stehen die Gamepasses und der Münz-Boost aus
-- Data/Products. "Kaufen" öffnet nur PromptGamePassPurchase bzw. PromptProductPurchase; ob ein Pass
-- wirkt, entscheidet allein der Server (Snapshot-Feld `passes`). Wer Auto-Dig besitzt, schaltet es
-- in dessen Zeile an und aus (Remote SetAutoDig, nur ein Boolean). Die Restzeit des Boosts kommt
-- vom Server (`coinBoostSeconds`) und zählt hier nur lokal herunter.
--
-- Policy (Paket 4.6): Preise zeigt der Shop aus dem Creator Dashboard (Controllers/ProductPrices, Ersatz
-- ist die Tabelle, Logic/PriceView), nicht verkaufte Produkte heißen "Nicht verfügbar". Sind Kisten für
-- den Spieler gesperrt (Snapshot `cratePolicy` "restricted" oder "unknown"), steht statt "Kisten" der
-- Reiter "Direktkauf": jedes Kisten-Item außer Event-Items zum festen Gem-Preis aus Logic/DirectShop.
-- "Kaufen" schickt nur `BuyDirectItem(itemId)`, Preis und Buchung bestimmt der Server.

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
local SUB_HEIGHT = 48 -- Streifen mit den Reitern
local TAB_GAP = 6
local TAB_ORDER = { "offers", "gems", "perks", "crates", "direct" }
local TAB_LABELS: { [string]: string } = { offers = "Angebote", gems = "Gems", perks = "Pässe", crates = "Kisten", direct = "Direktkauf" }
local DIRECT_SECTION_ORDER = 300 -- LayoutOrder der Direktkauf-Zeilen (Paket 4.6)
local DIRECT_ROW_HEIGHT = 84
local DIRECT_INTRO_HEIGHT = 56
local DIRECT_BUY_COOLDOWN_SECONDS = 0.6 -- der Server erlaubt 2 Käufe pro Sekunde
local DIRECT_CONFIRM_SECONDS = 3 -- so lange wartet "Wirklich kaufen?" auf den zweiten Tipp
local OFFER_ROW_HEIGHT = 128
local OFFER_TICK_SECONDS = 0.5 -- so oft wird der Countdown der Angebote neu geschrieben
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
local TEXT_NOT_FOR_SALE = "Gerade nicht im Verkauf."
local TEXT_AUTO_ON = "Auto: an"
local TEXT_AUTO_OFF = "Auto: aus"
local TEXT_BOOST_BOUGHT = "Münz-Boost aktiv!"
local TEXT_BOOST_REALTIME = "Läuft in Echtzeit, auch offline"
local TOGGLE_ON_COLOR = Color3.fromRGB(150, 220, 120)
local PASS_COLOR = Color3.fromRGB(255, 214, 110)
local TAB_ACTIVE_COLOR = Color3.fromRGB(120, 200, 235)
local OFFER_COLOR = Color3.fromRGB(255, 190, 90)
local TEXT_OFFER_BOUGHT = "Angebot erhalten!"
local TEXT_OFFER_FALLBACK_NAME = "Angebot" -- Ersatz-Gems ohne bekanntes Produkt (Meldung "duplicate")
local TEXT_OFFER_OVER = "Vorbei"
local TEXT_OFFER_DONE = "Gekauft"
local TEXT_OFFER_PENDING = "Wird gutgeschrieben…"
local OFFER_PENDING_SECONDS = 60 -- so lange gilt ein bezahlter Kauf als "wird gutgeschrieben", falls kein Snapshot kommt

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local GemPacks = loadShared("Data", "GemPacks")
local Products = loadShared("Data", "Products")
local Offers = loadShared("Data", "Offers")
local CrateItems = loadShared("Data", "CrateItems")
local Economy = loadShared("Data", "Economy")
local Rarities = loadShared("Data", "Rarities")
local PriceView = loadShared("Logic", "PriceView")
local DirectShop = loadShared("Logic", "DirectShop")
local EquipmentLogic = loadShared("Logic", "Equipment")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any
local CrateShop = require(script.Parent:WaitForChild("CrateShop") :: ModuleScript) :: any
local ProductPrices = require(script.Parent:WaitForChild("ProductPrices") :: ModuleScript) :: any

local GemShop = {}

-- Vom Angebots-Hinweis (Controllers/OfferHint) benutzt: öffnet den Shop beim Reiter "Angebote".
local openOffersTab: (() -> ())? = nil
function GemShop.openOffers()
    if openOffersTab ~= nil then
        openOffersTab()
    end
end

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

-- Preis aus dem Creator Dashboard (Controllers/ProductPrices), sonst aus der Tabelle (Paket 4.6).
local function priceInfo(isPass: boolean, productId: number): any
    if productId <= 0 then
        return nil
    end
    return ProductPrices.info(isPass, productId)
end
local function productButtonText(product: any): string
    return PriceView.buttonText(product.productId, priceInfo(product.kind == "gamepass", product.productId), product.priceRobux)
end
local function productBuyable(product: any): boolean
    return PriceView.buyable(product.productId, priceInfo(product.kind == "gamepass", product.productId))
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
    -- Reiter: Welche Zeilen zu welchem Reiter gehören, steht in `tabRows`. Die Funktionen werden
    -- unten gesetzt (das Fenster braucht onOpen vorher).
    local tabRows: { [string]: { GuiObject } } = { offers = {}, gems = {}, perks = {}, direct = {} }
    local activeTab = "gems"
    local applyTabs: () -> () = function() end
    local chooseTab: () -> () = function() end

    local window = Screen.createWindow({
        name = "GemWindow",
        title = "Shop",
        kind = "narrow",
        subHeight = SUB_HEIGHT,
        footerHeight = FOOTER_HEIGHT,
        onOpen = function()
            chooseTab()
            applyTabs()
        end,
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

    local offerDot = false -- läuft ein Angebot? Dann hängt ein Punkt am Menüknopf (Paket 4.5)
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
        openButton.Text = `Gems: {groupedNumber(value)}{if offerDot then " •" else ""}`
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
    local buyButtons: { [string]: { button: TextButton, bonus: TextLabel, pack: any } } = {}
    -- Über der Obergrenze würde das Paket gekappt: nicht kaufen lassen (der Server kappt trotzdem).
    local function wouldOverflow(pack: any): boolean
        return targetGems + pack.gems > Economy.purchases.maxGems
    end
    local function refreshButtons()
        for _, entry in buyButtons do
            local pack = entry.pack
            if pack.productId ~= 0 then
                entry.button.Text = if wouldOverflow(pack) then "Voll" else PriceView.buttonText(pack.productId, priceInfo(false, pack.productId), pack.robux)
            end
            -- Bonus aus den echten Preisen (gleiches Einstiegspaket wie im Konzept).
            local base = GemPacks.list[1]
            local bonus = PriceView.gemBonusPercent(pack.gems, PriceView.robux(priceInfo(false, pack.productId), pack.robux), base.gems, PriceView.robux(priceInfo(false, base.productId), base.robux))
            if bonus == nil then
                bonus = pack.bonusPercentConcept
            end
            entry.bonus.Text = if pack == base then "Einstieg" elseif (bonus :: number) > 0 then `+{bonus} % Bonus` else "Kein Bonus"
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
        table.insert(tabRows.gems, row)

        newText(row, "Name", UDim2.new(0, 12, 0, 8), UDim2.new(0.5, -12, 0, 26), Enum.Font.GothamBold, TEXT_COLOR, pack.name)
        local bonusText = if pack.bonusPercentConcept > 0 then `+{pack.bonusPercentConcept} % Bonus` else "Einstieg"
        local bonusLabel = newText(row, "Bonus", UDim2.new(0, 12, 0, 36), UDim2.new(0.5, -12, 0, 20), Enum.Font.Gotham, GOOD_COLOR, bonusText)

        local buy = Instance.new("TextButton")
        buy.Name = "Buy"
        buy.AnchorPoint = Vector2.new(1, 0.5)
        buy.Position = UDim2.new(1, -8, 0.5, 0)
        buy.Size = UDim2.new(0.42, 0, 0, controls.rowButtonH)
        buy.BackgroundColor3 = if pack.productId == 0 then BUTTON_COLOR else GEM_COLOR
        buy.Font = Enum.Font.GothamBold
        buy.TextColor3 = if pack.productId == 0 then MUTED_COLOR else PANEL_COLOR
        buy.TextScaled = true
        buy.Text = PriceView.buttonText(pack.productId, priceInfo(false, pack.productId), pack.robux)
        buy.Parent = row
        Instance.new("UICorner").Parent = buy
        local buyPadding = Instance.new("UIPadding")
        buyPadding.PaddingTop = UDim.new(0, 8)
        buyPadding.PaddingBottom = UDim.new(0, 8)
        buyPadding.Parent = buy

        buyButtons[pack.id] = { button = buy, bonus = bonusLabel, pack = pack }
        buy.Activated:Connect(function()
            if pack.productId == 0 then
                showMessage(TEXT_MISSING_PRODUCT)
                return
            end
            if not PriceView.buyable(pack.productId, priceInfo(false, pack.productId)) then
                showMessage(TEXT_NOT_FOR_SALE)
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
    table.insert(tabRows.perks, section)

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
                    button.Text = productButtonText(product)
                    styleButton(button, productBuyable(product), PASS_COLOR)
                    status.Text = ""
                end
            else
                button.Text = productButtonText(product)
                styleButton(button, productBuyable(product), PASS_COLOR)
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
        table.insert(tabRows.perks, row)

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
            if not productBuyable(product) then
                showMessage(TEXT_NOT_FOR_SALE)
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

    -- Direktkauf (Paket 4.6) ---------------------------------------------------------------------
    -- Nur wo Kisten gesperrt sind (Policy `ArePaidRandomItemsRestricted` oder unbekannt): jedes Kisten-
    -- Item außer Event-Items zum festen Preis in Gems, ohne Zufall. Preise aus Logic/DirectShop
    -- (dieselbe Funktion wie auf dem Server). Der Client schickt nur die Item-ID (BuyDirectItem).
    local DIRECT_REASONS: { [string]: string } = {
        notEnoughGems = "Zu wenig Gems. Im Reiter Gems gibt es Pakete.",
        cratesAllowed = "Hier gibt es Kisten, der Direktkauf ist geschlossen.",
        notOffered = "Dieses Item gibt es nicht im Direktkauf.",
        unknownItem = "Dieses Item gibt es nicht.",
        noProfile = "Dein Spielstand lädt noch.",
        busy = "Einen Moment, der letzte Kauf läuft noch.",
        error = "Verbindung unterbrochen. Prüfe deinen Kontostand.",
        unknown = "Das geht gerade nicht.",
    }
    local DIRECT_KIND_NAMES: { [string]: string } = { skin = "Skin", companion = "Begleiter", toolVariant = "Werkzeug-Variante" }
    local function hex(hexText: string): Color3
        local r = tonumber(string.sub(hexText, 2, 3), 16) or 255
        local g = tonumber(string.sub(hexText, 4, 5), 16) or 255
        local b = tonumber(string.sub(hexText, 6, 7), 16) or 255
        return Color3.fromRGB(r, g, b)
    end

    local DIRECT_INTRO_RESTRICTED = "Kisten gibt es in deiner Region nicht. Hier kaufst du jedes Item direkt, ohne Zufall. Der Preis entspricht den durchschnittlichen Kosten über Kisten."
    local DIRECT_INTRO_UNKNOWN = "Kisten sind gerade nicht verfügbar. Hier kaufst du jedes Item direkt, ohne Zufall. Der Preis entspricht den durchschnittlichen Kosten über Kisten."
    local directIntro = newText(window.body, "DirectIntro", UDim2.new(), UDim2.new(1, 0, 0, DIRECT_INTRO_HEIGHT), Enum.Font.Gotham, MUTED_COLOR, DIRECT_INTRO_RESTRICTED)
    directIntro.LayoutOrder = DIRECT_SECTION_ORDER
    directIntro.Visible = false
    table.insert(tabRows.direct, directIntro)

    local directRows: { { entry: any, info: TextLabel, button: TextButton } } = {}
    local directSnapshot: any = nil
    local directBusy = false
    local lastDirectAt = 0
    local buyDirect = remotes:WaitForChild("BuyDirectItem") :: RemoteFunction

    -- Zwei Tipps je Kauf: der erste fragt nach (Preise bis über 200.000 Gems), der zweite kauft.
    local confirmItemId: string? = nil
    local confirmUntil = 0

    local function renderDirect()
        local snapshot = directSnapshot
        directIntro.Text = if snapshot ~= nil and snapshot.cratePolicy == "unknown" then DIRECT_INTRO_UNKNOWN else DIRECT_INTRO_RESTRICTED
        if confirmItemId ~= nil and os.clock() > confirmUntil then
            confirmItemId = nil
        end
        local gems = if snapshot ~= nil and type(snapshot.gems) == "number" then snapshot.gems else 0
        for _, row in directRows do
            local item = CrateItems.byId[row.entry.itemId]
            local copies = 0
            local stars = 1
            if snapshot ~= nil and type(snapshot.inventory) == "table" and item ~= nil then
                local bucket = snapshot.inventory[EquipmentLogic.INVENTORY_FIELDS[item.kind]]
                local count = if type(bucket) == "table" then bucket[item.id] else nil
                copies = if type(count) == "number" then count else 0
                if type(snapshot.itemStars) == "table" then
                    stars = EquipmentLogic.starsOf({ itemStars = snapshot.itemStars }, item.id)
                end
            end
            local bonusBp = if item ~= nil then EquipmentLogic.itemBonusBp(item, 1) else 0
            local ownText = if copies > 0 then ` · Besitz: {copies} (★{stars})` else ""
            row.info.Text = `{DIRECT_KIND_NAMES[row.entry.kind] or row.entry.kind} · +{bonusBp / 100} % Sammelrate{ownText}`
            local affordable = gems >= row.entry.price
            row.button.Text = if confirmItemId == row.entry.itemId then `Wirklich? {groupedNumber(row.entry.price)} Gems` else `{groupedNumber(row.entry.price)} Gems`
            row.button.BackgroundColor3 = if affordable and not directBusy then GEM_COLOR else BUTTON_COLOR
            row.button.TextColor3 = if affordable and not directBusy then PANEL_COLOR else MUTED_COLOR
        end
    end

    local catalog = DirectShop.catalog()
    table.sort(catalog, function(a: any, b: any): boolean
        local rankA = if Rarities.byId[a.rarityId] then Rarities.byId[a.rarityId].rank else 0
        local rankB = if Rarities.byId[b.rarityId] then Rarities.byId[b.rarityId].rank else 0
        if rankA ~= rankB then
            return rankA < rankB
        end
        return a.price < b.price
    end)
    for index, entry in catalog do
        local rarity = Rarities.byId[entry.rarityId]
        local row = Instance.new("Frame")
        row.Name = `Direct_{entry.itemId}`
        row.LayoutOrder = DIRECT_SECTION_ORDER + index
        row.Size = UDim2.new(1, 0, 0, DIRECT_ROW_HEIGHT)
        row.BackgroundColor3 = ROW_COLOR
        row.BackgroundTransparency = 0.2
        row.Visible = false
        row.Parent = window.body
        Instance.new("UICorner").Parent = row
        table.insert(tabRows.direct, row)

        local title = if rarity ~= nil then `{entry.name} ({rarity.name})` else entry.name
        newText(row, "Name", UDim2.new(0, 12, 0, 6), UDim2.new(0.6, -12, 0, 26), Enum.Font.GothamBold, if rarity ~= nil then hex(rarity.colorHex) else TEXT_COLOR, title)
        local info = newText(row, "Info", UDim2.new(0, 12, 0, 36), UDim2.new(0.6, -12, 0, 40), Enum.Font.Gotham, MUTED_COLOR, "")
        info.TextYAlignment = Enum.TextYAlignment.Top

        local buy = Instance.new("TextButton")
        buy.Name = "Buy"
        buy.AnchorPoint = Vector2.new(1, 0.5)
        buy.Position = UDim2.new(1, -8, 0.5, 0)
        buy.Size = UDim2.new(0.36, 0, 0, controls.rowButtonH)
        buy.Font = Enum.Font.GothamBold
        buy.TextScaled = true
        buy.Text = `{groupedNumber(entry.price)} Gems`
        buy.Parent = row
        Instance.new("UICorner").Parent = buy
        local buyPadding = Instance.new("UIPadding")
        buyPadding.PaddingTop = UDim.new(0, 8)
        buyPadding.PaddingBottom = UDim.new(0, 8)
        buyPadding.Parent = buy

        table.insert(directRows, { entry = entry, info = info, button = buy })
        buy.Activated:Connect(function()
            if directBusy then
                showMessage(DIRECT_REASONS.busy)
                return
            end
            if confirmItemId ~= entry.itemId or os.clock() > confirmUntil then
                confirmItemId = entry.itemId
                confirmUntil = os.clock() + DIRECT_CONFIRM_SECONDS
                renderDirect()
                task.delay(DIRECT_CONFIRM_SECONDS + 0.05, renderDirect)
                return
            end
            confirmItemId = nil
            local now = os.clock()
            if now - lastDirectAt < DIRECT_BUY_COOLDOWN_SECONDS then
                return
            end
            lastDirectAt = now
            directBusy = true
            renderDirect()
            task.spawn(function()
                local ok, reply = pcall(function(): any
                    return buyDirect:InvokeServer(entry.itemId)
                end)
                directBusy = false
                if not ok or type(reply) ~= "table" then
                    showMessage(DIRECT_REASONS.error)
                elseif reply.ok ~= true then
                    showMessage(DIRECT_REASONS[tostring(reply.reason)] or DIRECT_REASONS.unknown)
                else
                    showBanner(`{entry.name} gekauft!`)
                    showMessage("Ausrüsten im Fenster Ausrüstung.")
                end
                renderDirect()
            end)
        end)
    end

    State.onChanged(function(snapshot: any)
        directSnapshot = snapshot
        renderDirect()
    end)

    -- Angebote und Reiter (Paket 4.5) ------------------------------------------------------------
    local offersState: { [string]: { state: string, endsAt: number } } = {}
    local cratesAllowed = false
    local directOpen = false -- Kisten hier gesperrt: Direktkauf statt Kisten (Paket 4.6)
    local forceOffers = false
    local offerRows: { { offer: any, product: any, row: Frame, status: TextLabel, button: TextButton } } = {}
    -- Kaufdialog offen oder Kauf bezahlt, aber der Server hat noch nicht bestätigt: kein zweiter Kauf
    -- über die Oberfläche (ein zweiter bezahlter Beleg bekäme vom Server nur Ersatz-Gems, kein Paket).
    local offerDialogOpen: { [string]: boolean } = {}
    local offerPendingSince: { [string]: number } = {}
    local function offerPending(offerId: string): boolean
        local since = offerPendingSince[offerId]
        if since ~= nil and os.clock() - since >= OFFER_PENDING_SECONDS then
            offerPendingSince[offerId] = nil
            since = nil
        end
        return offerDialogOpen[offerId] == true or since ~= nil
    end

    local function offerLeft(offerId: string): number
        local entry = offersState[offerId]
        if entry == nil or entry.state ~= "active" then
            return 0
        end
        return math.max(entry.endsAt - os.clock(), 0)
    end
    local function anyOfferActive(): boolean
        for _, offer in Offers.list do
            if offerLeft(offer.id) > 0 then
                return true
            end
        end
        return false
    end

    -- Angebote nach Priorität (kleinere Zahl zuerst), je Angebot eine Zeile.
    local sortedOffers: { any } = table.clone(Offers.list)
    table.sort(sortedOffers, function(a: any, b: any): boolean
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.id < b.id
    end)
    for index, offer in sortedOffers do
        local product = Products.byId[offer.productId]
        if product == nil then
            continue
        end
        local row = Instance.new("Frame")
        row.Name = `Offer_{offer.id}`
        row.LayoutOrder = index
        row.Size = UDim2.new(1, 0, 0, OFFER_ROW_HEIGHT)
        row.BackgroundColor3 = ROW_COLOR
        row.BackgroundTransparency = 0.2
        row.Visible = false
        row.Parent = window.body
        Instance.new("UICorner").Parent = row

        newText(row, "Name", UDim2.new(0, 12, 0, 6), UDim2.new(0.6, -12, 0, 26), Enum.Font.GothamBold, OFFER_COLOR, product.name)
        local names: { string } = {}
        table.insert(names, `{groupedNumber(offer.gems)} Gems`)
        for _, itemId in offer.items do
            local item = CrateItems.byId[itemId]
            table.insert(names, if item ~= nil then item.name else itemId)
        end
        local contents = newText(row, "Contents", UDim2.new(0, 12, 0, 34), UDim2.new(0.6, -12, 0, 62), Enum.Font.Gotham, TEXT_COLOR, table.concat(names, " · "))
        contents.TextYAlignment = Enum.TextYAlignment.Top
        local status = newText(row, "Status", UDim2.new(0, 12, 1, -26), UDim2.new(0.6, -12, 0, 22), Enum.Font.GothamBold, GOOD_COLOR, "")

        local buy = Instance.new("TextButton")
        buy.Name = "Buy"
        buy.AnchorPoint = Vector2.new(1, 0.5)
        buy.Position = UDim2.new(1, -8, 0.5, 0)
        buy.Size = UDim2.new(0.34, 0, 0, controls.rowButtonH)
        buy.Font = Enum.Font.GothamBold
        buy.TextScaled = true
        buy.Parent = row
        Instance.new("UICorner").Parent = buy
        local buyPadding = Instance.new("UIPadding")
        buyPadding.PaddingTop = UDim.new(0, 8)
        buyPadding.PaddingBottom = UDim.new(0, 8)
        buyPadding.Parent = buy

        table.insert(offerRows, { offer = offer, product = product, row = row, status = status, button = buy })
        buy.Activated:Connect(function()
            if offerLeft(offer.id) <= 0 then
                return
            end
            if product.productId == 0 then
                showMessage(TEXT_MISSING_PRODUCT)
                return
            end
            if not productBuyable(product) then
                showMessage(TEXT_NOT_FOR_SALE)
                return
            end
            if offerPending(offer.id) then
                return
            end
            local now = os.clock()
            if now - lastBuyAt < BUY_COOLDOWN_SECONDS then
                return
            end
            lastBuyAt = now
            offerDialogOpen[offer.id] = true
            local ok = pcall(function()
                MarketplaceService:PromptProductPurchase(player, product.productId)
            end)
            if not ok then
                offerDialogOpen[offer.id] = nil
                showMessage(TEXT_BUY_FAILED)
            end
        end)
    end

    -- Dialog zu: bezahlt = Kauf wartet auf die Bestätigung des Servers (Snapshot "bought").
    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, isPurchased: boolean)
        if userId ~= player.UserId then
            return
        end
        for _, entry in offerRows do
            if entry.product.productId == productId then
                offerDialogOpen[entry.offer.id] = nil
                if isPurchased then
                    offerPendingSince[entry.offer.id] = os.clock()
                end
            end
        end
    end)

    -- Zeilen der Angebote: aktiv = kaufbar mit Countdown, gekauft = "Gekauft", sonst verborgen.
    local function renderOffers()
        for _, entry in offerRows do
            local state = if offersState[entry.offer.id] ~= nil then offersState[entry.offer.id].state else "hidden"
            local left = offerLeft(entry.offer.id)
            if left > 0 and offerPending(entry.offer.id) then
                entry.status.Text = TEXT_OFFER_PENDING
                entry.button.Text = TEXT_OFFER_PENDING
                entry.button.BackgroundColor3 = BUTTON_COLOR
                entry.button.TextColor3 = MUTED_COLOR
            elseif left > 0 then
                entry.status.Text = `Noch {clockText(left)}`
                local buyable = productBuyable(entry.product)
                entry.button.Text = productButtonText(entry.product)
                entry.button.BackgroundColor3 = if buyable then OFFER_COLOR else BUTTON_COLOR
                entry.button.TextColor3 = if buyable then PANEL_COLOR else MUTED_COLOR
            elseif state == "bought" then
                entry.status.Text = TEXT_OFFER_DONE
                entry.button.Text = TEXT_OFFER_DONE
                entry.button.BackgroundColor3 = BUTTON_COLOR
                entry.button.TextColor3 = MUTED_COLOR
            else
                entry.status.Text = TEXT_OFFER_OVER
            end
        end
    end

    -- Reiterstreifen im Fensterkopf. Sichtbar sind nur Reiter, die etwas zeigen.
    local tabButtons: { [string]: TextButton } = {}
    for _, tabId in TAB_ORDER do
        local b = Instance.new("TextButton")
        b.Name = `Tab_{tabId}`
        b.Font = Enum.Font.GothamBold
        b.TextScaled = true
        b.Text = TAB_LABELS[tabId]
        b.Parent = window.sub
        Instance.new("UICorner").Parent = b
        local p = Instance.new("UIPadding")
        p.PaddingTop = UDim.new(0, 6)
        p.PaddingBottom = UDim.new(0, 6)
        p.Parent = b
        tabButtons[tabId] = b
    end

    local function tabAvailable(tabId: string): boolean
        if tabId == "offers" then
            return anyOfferActive()
        elseif tabId == "crates" then
            return cratesAllowed
        elseif tabId == "direct" then
            return directOpen
        end
        return true
    end

    applyTabs = function()
        if activeTab ~= "crates" and not tabAvailable(activeTab) then
            activeTab = "gems"
        end
        local visibleTabs: { string } = {}
        for _, tabId in TAB_ORDER do
            local available = tabAvailable(tabId)
            tabButtons[tabId].Visible = available
            if available then
                table.insert(visibleTabs, tabId)
            end
        end
        for index, tabId in visibleTabs do
            local b = tabButtons[tabId]
            b.Size = UDim2.new(1 / #visibleTabs, -TAB_GAP, 1, -8)
            b.Position = UDim2.new((index - 1) / #visibleTabs, TAB_GAP / 2, 0, 4)
            local active = tabId == activeTab
            b.BackgroundColor3 = if active then (if tabId == "offers" then OFFER_COLOR else TAB_ACTIVE_COLOR) else BUTTON_COLOR
            b.TextColor3 = if active then PANEL_COLOR else TEXT_COLOR
        end
        for tabId, rows in tabRows do
            for _, row in rows do
                if tabId == "offers" then
                    continue
                end
                row.Visible = tabId == activeTab
            end
        end
        for _, entry in offerRows do
            local state = if offersState[entry.offer.id] ~= nil then offersState[entry.offer.id].state else "hidden"
            entry.row.Visible = activeTab == "offers" and (offerLeft(entry.offer.id) > 0 or state == "bought")
        end
        renderOffers()
        local dot = anyOfferActive()
        if dot ~= offerDot then
            offerDot = dot
            renderGems(shownGems)
        end
    end
    applyTabs()

    -- Beim Öffnen: läuft ein Angebot, steht der Shop bei "Angebote", sonst bei den Gems.
    chooseTab = function()
        if forceOffers or anyOfferActive() then
            activeTab = "offers"
        elseif activeTab == "offers" or activeTab == "crates" or (activeTab == "direct" and not directOpen) then
            activeTab = "gems"
        end
        forceOffers = false
    end

    openOffersTab = function()
        forceOffers = true
        window.open()
    end

    for tabId, b in tabButtons do
        b.Activated:Connect(function()
            if tabId == "crates" then
                CrateShop.open()
                return
            end
            activeTab = tabId
            applyTabs()
        end)
    end

    -- Countdown der Angebote lokal herunterzählen; abgelaufene verschwinden von selbst.
    task.spawn(function()
        local lastActive = false
        while true do
            task.wait(OFFER_TICK_SECONDS)
            local active = anyOfferActive()
            if active ~= lastActive then
                applyTabs() -- ein Angebot ist abgelaufen oder begonnen: Reiter und Punkt neu
            elseif window.isOpen() then
                renderOffers()
            end
            lastActive = active
        end
    end)

    State.onChanged(function(snapshot: any)
        local now = os.clock()
        local nextState: { [string]: { state: string, endsAt: number } } = {}
        if type(snapshot.offers) == "table" then
            for offerId, entry in snapshot.offers do
                if type(offerId) == "string" and type(entry) == "table" and type(entry.state) == "string" then
                    local seconds = if type(entry.secondsLeft) == "number" and entry.secondsLeft == entry.secondsLeft then math.max(entry.secondsLeft, 0) else 0
                    nextState[offerId] = { state = entry.state, endsAt = now + seconds }
                end
            end
        end
        offersState = nextState
        for offerId, entry in nextState do
            if entry.state ~= "active" then
                offerPendingSince[offerId] = nil -- gebucht (oder abgelaufen): die Sperre ist nicht mehr nötig
            end
        end
        cratesAllowed = snapshot.cratesAllowed == true
        directOpen = DirectShop.isOpen(snapshot.cratePolicy) and not cratesAllowed
        applyTabs()
    end)

    -- Neue Preise von Roblox: Knöpfe neu schreiben (Paket 4.6).
    ProductPrices.onChanged(function()
        refreshButtons()
        renderPerkRows()
        renderOffers()
    end)

    State.onNotify(function(payload: any)
        if payload.kind == "gemsBought" and type(payload.gems) == "number" and payload.gems > 0 then
            showBanner(`+{groupedNumber(math.floor(payload.gems))} Gems`)
        elseif payload.kind == "boostBought" then
            showBanner(TEXT_BOOST_BOUGHT)
        elseif payload.kind == "offerBought" then
            local offer = if type(payload.offerId) == "string" then Offers.byId[payload.offerId] else nil
            local product = if offer ~= nil then Products.byId[offer.productId] else nil
            if payload.duplicate == true then
                -- Kein Paket (schon gekauft oder Fenster vorbei): der Server hat nur Ersatz-Gems gebucht.
                local name = if product ~= nil then product.name else TEXT_OFFER_FALLBACK_NAME
                local gems = if type(payload.gems) == "number" then math.floor(payload.gems) else 0
                showBanner(if gems > 0 then `{name} nicht verfügbar: +{groupedNumber(gems)} Gems` else `{name} nicht verfügbar`)
            else
                showBanner(if product ~= nil then `{product.name} erhalten!` else TEXT_OFFER_BOUGHT)
            end
        end
    end)
end

return GemShop
