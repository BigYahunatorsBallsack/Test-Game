--!strict
-- OfferHint-Controller (Paket 4.5)
-- Kleine Karte am Rand, die auf ein laufendes Angebot hinweist (zum Beispiel das Starterpaket):
-- "Name · noch H:MM:SS" mit "Ansehen" (öffnet den Shop beim Reiter "Angebote") und "X". Sie
-- blockiert nichts: Die Karte ist klein, liegt am Rand und verschwindet nach HINT_VISIBLE_SECONDS
-- von selbst. Konzept-Regel: Angebote erscheinen nach dem Reveal und nie davor.
--
-- Wann ein Hinweis kommen darf, entscheidet die reine Funktion Logic/Offers.nextHint (Lune-Tests):
-- nicht während ein Fund- oder Kisten-Reveal läuft oder wartet, nicht im Tutorial, nicht bei
-- offenem Fenster, je Angebot höchstens einmal pro Sitzung, mehrere nach Priorität. Beginnt ein
-- Reveal, während der Hinweis steht, verschwindet er sofort und darf später wiederkommen.
-- Ob ein Angebot läuft und wie lange, kommt allein vom Server (Snapshot-Feld `offers`); der Client
-- zählt die Zeit nur lokal herunter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Zeiten
local CHECK_SECONDS = 1 -- so oft wird geprüft, ob ein Hinweis kommen darf
local HINT_VISIBLE_SECONDS = 10
local MIN_SEEN_SECONDS = 2 -- weniger lange sichtbar (ein Reveal kam dazwischen): der Hinweis darf wiederkommen
local MAX_REPEATS = 2 -- so oft darf ein Hinweis nach einem Reveal höchstens wiederkommen
local SLIDE_SECONDS = 0.25
local SLIDE_EASING = Enum.EasingStyle.Quad
local COUNTDOWN_TICK_SECONDS = 0.5
local HINT_DISPLAY_ORDER = 8 -- unter dem Kaufbanner (9) und den Reveals (10 bis 12)

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local OFFER_COLOR = Color3.fromRGB(255, 190, 90)
local BUTTON_COLOR = Color3.fromRGB(80, 66, 52)

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local OffersLogic = loadShared("Logic", "Offers")
local OffersData = loadShared("Data", "Offers")
local ProductsData = loadShared("Data", "Products")
local TutorialLogic = loadShared("Logic", "Tutorial")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any
local Reveal = require(script.Parent:WaitForChild("Reveal") :: ModuleScript) :: any
local CrateShop = require(script.Parent:WaitForChild("CrateShop") :: ModuleScript) :: any
local GemShop = require(script.Parent:WaitForChild("GemShop") :: ModuleScript) :: any

local OfferHint = {}

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

-- Größe, Anker und Plätze (gezeigt, versteckt) wie bei der kleinen Fundkarte (Data/Screen: smallCard).
local function placement(): (Vector2, Vector2, UDim2, UDim2)
    local c = Screen.classData().smallCard
    local size = Vector2.new(c.w, c.h)
    if c.side == "left" then
        return size, Vector2.new(0, c.anchorY), UDim2.new(0, c.margin, c.yScale, c.yOffset), UDim2.new(0, -(c.w + c.margin), c.yScale, c.yOffset)
    end
    return size, Vector2.new(1, c.anchorY), UDim2.new(1, -c.margin, c.yScale, c.yOffset), UDim2.new(1, c.w + c.margin, c.yScale, c.yOffset)
end

local function newLabel(parent: Instance, position: UDim2, size: UDim2, font: Enum.Font, color: Color3, text: string): TextLabel
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = position
    l.Size = size
    l.Font = font
    l.TextColor3 = color
    l.TextScaled = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = parent
    return l
end

function OfferHint.Init() end

function OfferHint.Start()
    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronOfferHint"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = HINT_DISPLAY_ORDER
    gui.Parent = player:WaitForChild("PlayerGui")

    -- Zustand der Angebote (Server) mit lokalem Ende, damit der Countdown ohne neuen Snapshot läuft.
    local offersState: { [string]: { state: string, endsAt: number } } = {}
    local tutorialStep = 1
    local shownThisSession: { [string]: boolean } = {}
    local repeats: { [string]: number } = {}
    local current: { offerId: string, card: Frame, token: number, shownAt: number }? = nil
    local hintToken = 0

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
        tutorialStep = if type(snapshot.tutorialStep) == "number" then snapshot.tutorialStep else 1
    end)

    -- Zustand für Logic/Offers.nextHint: aktiv zählt nur, solange das lokale Ende nicht erreicht ist.
    local function hintInput(): { [string]: { state: string, secondsLeft: number } }
        local now = os.clock()
        local result: { [string]: { state: string, secondsLeft: number } } = {}
        for offerId, entry in offersState do
            local left = math.max(entry.endsAt - now, 0)
            local state = entry.state
            if state == "active" and left <= 0 then
                state = "expired"
            end
            result[offerId] = { state = state, secondsLeft = left }
        end
        return result
    end

    local function remainingSeconds(offerId: string): number
        local entry = offersState[offerId]
        if entry == nil or entry.state ~= "active" then
            return 0
        end
        return math.max(entry.endsAt - os.clock(), 0)
    end

    -- Karte wegschieben und entfernen. `again` = der Hinweis darf später wiederkommen.
    local function hide(again: boolean)
        local shown = current
        if shown == nil then
            return
        end
        current = nil
        hintToken += 1
        local count = repeats[shown.offerId] or 0
        if again and count < MAX_REPEATS and os.clock() - shown.shownAt < MIN_SEEN_SECONDS then
            repeats[shown.offerId] = count + 1
            shownThisSession[shown.offerId] = nil
        end
        local _, _, _, hidden = placement()
        local tween = TweenService:Create(shown.card, TweenInfo.new(SLIDE_SECONDS, SLIDE_EASING), { Position = hidden })
        tween:Play()
        task.delay(SLIDE_SECONDS, function()
            shown.card:Destroy()
        end)
    end

    local function show(offerId: string)
        local offer = OffersData.byId[offerId]
        local product = if offer ~= nil then ProductsData.byId[offer.productId] else nil
        if offer == nil or product == nil then
            return
        end
        shownThisSession[offerId] = true
        hintToken += 1
        local token = hintToken

        local size, anchor, shown, hidden = placement()
        local card = Instance.new("Frame")
        card.Name = `Hint_{offerId}`
        card.AnchorPoint = anchor
        card.Size = UDim2.fromOffset(size.X, size.Y)
        card.Position = hidden
        card.BackgroundColor3 = PANEL_COLOR
        card.BackgroundTransparency = 0.15
        card.Parent = gui
        Instance.new("UICorner").Parent = card
        local stroke = Instance.new("UIStroke")
        stroke.Color = OFFER_COLOR
        stroke.Thickness = 2
        stroke.Parent = card

        newLabel(card, UDim2.new(0, 10, 0.06, 0), UDim2.new(1, -52, 0.28, 0), Enum.Font.GothamBold, OFFER_COLOR, product.name)
        local timeLabel = newLabel(card, UDim2.new(0, 10, 0.36, 0), UDim2.new(1, -20, 0.22, 0), Enum.Font.Gotham, TEXT_COLOR, "")

        local closeButton = Instance.new("TextButton")
        closeButton.Name = "Close"
        closeButton.AnchorPoint = Vector2.new(1, 0)
        closeButton.Position = UDim2.new(1, -6, 0, 6)
        closeButton.Size = UDim2.fromOffset(32, 28)
        closeButton.BackgroundColor3 = BUTTON_COLOR
        closeButton.Font = Enum.Font.GothamBold
        closeButton.TextColor3 = TEXT_COLOR
        closeButton.TextScaled = true
        closeButton.Text = "X"
        closeButton.Parent = card
        Instance.new("UICorner").Parent = closeButton
        local closePadding = Instance.new("UIPadding")
        closePadding.PaddingTop = UDim.new(0, 4)
        closePadding.PaddingBottom = UDim.new(0, 4)
        closePadding.Parent = closeButton

        local viewButton = Instance.new("TextButton")
        viewButton.Name = "View"
        viewButton.AnchorPoint = Vector2.new(0.5, 1)
        viewButton.Position = UDim2.new(0.5, 0, 1, -8)
        viewButton.Size = UDim2.new(1, -20, 0.32, 0)
        viewButton.BackgroundColor3 = OFFER_COLOR
        viewButton.Font = Enum.Font.GothamBold
        viewButton.TextColor3 = PANEL_COLOR
        viewButton.TextScaled = true
        viewButton.Text = "Ansehen"
        viewButton.Parent = card
        Instance.new("UICorner").Parent = viewButton
        local viewPadding = Instance.new("UIPadding")
        viewPadding.PaddingTop = UDim.new(0, 5)
        viewPadding.PaddingBottom = UDim.new(0, 5)
        viewPadding.Parent = viewButton

        current = { offerId = offerId, card = card, token = token, shownAt = os.clock() }
        TweenService:Create(card, TweenInfo.new(SLIDE_SECONDS, SLIDE_EASING), { Position = shown }):Play()

        closeButton.Activated:Connect(function()
            hide(false)
        end)
        viewButton.Activated:Connect(function()
            hide(false)
            GemShop.openOffers()
        end)

        -- Countdown und Selbstschluss: nach HINT_VISIBLE_SECONDS, bei Ablauf des Angebots oder wenn
        -- ein Reveal beginnt (dann darf der Hinweis später wiederkommen).
        local startedAt = os.clock()
        task.spawn(function()
            while current ~= nil and current.token == token do
                -- Ein Fehler hier darf die Karte nicht hängen lassen: Karte weg, Schleife endet.
                local ok = pcall(function()
                    local left = remainingSeconds(offerId)
                    timeLabel.Text = `Noch {clockText(left)}`
                    if left <= 0 or Screen.isAnyWindowOpen() then
                        hide(false)
                    elseif Reveal.isBusy() or CrateShop.isRevealing() then
                        hide(true)
                    elseif os.clock() - startedAt >= HINT_VISIBLE_SECONDS then
                        hide(false)
                    end
                end)
                if not ok then
                    hide(false)
                    return
                end
                task.wait(COUNTDOWN_TICK_SECONDS)
            end
        end)
    end

    task.spawn(function()
        while true do
            task.wait(CHECK_SECONDS)
            if current == nil then
                local ok, offerId = pcall(function(): string?
                    return OffersLogic.nextHint(hintInput(), {
                        revealBusy = Reveal.isBusy() or CrateShop.isRevealing(),
                        tutorialActive = tutorialStep <= TutorialLogic.count(),
                        windowOpen = Screen.isAnyWindowOpen(),
                        shownThisSession = shownThisSession,
                    })
                end)
                if ok and type(offerId) == "string" then
                    local shown = pcall(show, offerId)
                    if not shown then
                        hide(false)
                    end
                end
            end
        end
    end)
end

return OfferHint
