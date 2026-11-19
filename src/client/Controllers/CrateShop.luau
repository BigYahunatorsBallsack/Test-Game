--!strict
-- CrateShop-Controller (Paket 4.2)
-- Knopf "Kisten" in der Menüleiste (Controllers/Screen) und ein Fenster mit den Kisten, die nicht
-- nur in der Saison laufen (Holz, Eisen, Gold). Vor dem Kauf steht je Kiste: Preis, die Quotentabelle
-- mit allen sechs Seltenheiten (auch die mit 0 %) und bei Kisten mit Pity der Zähler "garantiert in
-- N Öffnungen". Anzeige und Auswurf lesen dieselbe Tabelle (Data/Crates), der Client würfelt nichts.
-- "Öffnen" und "10 + 1 öffnen" schicken `OpenCrate(crateId, count)` ohne Werte. Die Antwort des Servers
-- (Gewinne, Pity, Kontostand) spielt der Reveal ab: Kiste wackelt, lädt sich in der Farbe der höchsten
-- Seltenheit auf, springt auf, dann kommen die Karten. Ein Tipp überspringt, der nächste schließt.
-- Der Reveal blockiert nichts: Der Hintergrund fängt keine Eingaben ab, nur der Knopf unten
-- ("Überspringen", danach "Schließen") ist anklickbar. Sammeln und Laufen gehen weiter.
-- In Regionen mit gesperrten Zufallsitems (Server meldet `cratesAllowed ~= true`) fehlt der Knopf,
-- und das Fenster schließt sich. Der Server lehnt Öffnungen dort ohnehin ab.
-- Auf den Karten steht der Bonus des Items auf die Sammelrate (Paket 4.3) und bei einem Duplikat der
-- Fortschritt zum nächsten Stern; ausrüsten und verschmelzen im Fenster "Ausrüstung" (EquipmentMenu).
-- Sounds: leere IDs bis Paket 3.5.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

-- Menüleiste und Fenster
local MENU_ORDER = 4 -- nach Zonen, Sammlung und Sandsturm
local FOOTER_HEIGHT = 64
local MESSAGE_SECONDS = 3
local OPEN_COOLDOWN_SECONDS = 1.3 -- gegen Doppeltippen, etwas länger als das Server-Limit (1 s), damit Netzschwankungen es nicht reißen

-- Reveal
local REVEAL_DISPLAY_ORDER = 12 -- über Fund-Reveal (10, 11)
local CHEST_SIZE = 96
local SHAKE_SECONDS = 0.9
local SHAKE_ANGLE = 10
local SHAKE_STEPS = 6
local GLOW_SECONDS = 0.3
local POP_SECONDS = 0.25
local POP_EASING = Enum.EasingStyle.Back
local CARD_FADE_SECONDS = 0.22
local CARD_STAGGER_SECONDS = 0.12 -- Abstand zwischen den Karten beim 10er-Paket
local CARD_SINGLE_SIZE = Vector2.new(240, 150)
local CARD_GRID_SIZE = Vector2.new(150, 84)
local GRID_COLUMNS = 4
local GRID_GAP = 8
local SKIP_BUTTON_WIDTH = 200
local SKIP_BUTTON_HEIGHT = 48
local MIN_REVEAL_SECONDS_FOR_SKIP = 0.2 -- so kurz nach dem Start zählt ein Tipp noch nicht

-- Sounds (Paket 3.5). Leer = kein Ton.
local SOUND_IDS = { shake = "", pop = "", legendary = "" }

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local ROW_COLOR = Color3.fromRGB(64, 52, 40)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local GOOD_COLOR = Color3.fromRGB(150, 220, 120)
local WARN_COLOR = Color3.fromRGB(235, 150, 90)
local BUTTON_COLOR = Color3.fromRGB(80, 66, 52)
local BUY_COLOR = Color3.fromRGB(230, 200, 117)
local GEM_COLOR = Color3.fromRGB(120, 200, 235)
local CHEST_COLOR = Color3.fromRGB(120, 86, 52)
local DIM_COLOR = Color3.fromRGB(0, 0, 0)

local REASONS: { [string]: string } = {
    notEnoughGems = "Zu wenig Gems. Im Gems-Fenster gibt es Pakete.",
    notEnoughCoins = "Zu wenig Münzen.",
    restricted = "Kisten sind hier nicht verfügbar.",
    notInSeason = "Diese Kiste gibt es nur in der Saison.",
    unknownCrate = "Diese Kiste gibt es nicht.",
    badCount = "Das geht gerade nicht.",
    noProfile = "Dein Spielstand lädt noch.",
    busy = "Einen Moment, die letzte Kiste wird noch geöffnet.",
    error = "Verbindung unterbrochen. Prüfe deinen Kontostand.",
    unknown = "Das geht gerade nicht.",
}

local KIND_NAMES: { [string]: string } = {
    skin = "Skin",
    companion = "Begleiter",
    toolVariant = "Werkzeug-Variante",
}

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local BigNum = loadShared("Logic", "BigNum")
local Crates = loadShared("Data", "Crates")
local Rarities = loadShared("Data", "Rarities")
local CrateItems = loadShared("Data", "CrateItems")
local EquipmentLogic = loadShared("Logic", "Equipment")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

local CrateShop = {}

local player = Players.LocalPlayer

local function hexColor(hex: string): Color3
    local r = tonumber(string.sub(hex, 2, 3), 16) or 255
    local g = tonumber(string.sub(hex, 4, 5), 16) or 255
    local b = tonumber(string.sub(hex, 6, 7), 16) or 255
    return Color3.fromRGB(r, g, b)
end

-- Quote in Hundertstel-Prozent als Text ("4,5 %").
local function oddsText(bp: number): string
    local value = bp / 100
    local text = if value % 1 == 0 then tostring(math.floor(value)) else string.format("%.1f", value)
    local replaced = string.gsub(text, "%.", ",")
    return `{replaced} %`
end

local function priceText(crate: any, count: number): string
    local total = crate.price * (if count == 10 then Crates.bundle.buy else 1)
    if crate.currency == "gems" then
        return `{total} Gems`
    end
    return `{BigNum.format(BigNum.new(total))} Münzen`
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

-- Hundertstel-Prozent als Text mit deutschem Komma: 575 -> "5,75", 500 -> "5".
local function bonusPercentText(bp: number): string
    local text = string.format("%.2f", bp / 100)
    text = string.gsub(text, "0+$", "")
    text = string.gsub(text, "%.$", "")
    return (string.gsub(text, "%.", ","))
end

-- Bonus des Gewinns auf die Sammelrate und bei Duplikaten der Fortschritt zum nächsten Stern, soweit
-- der letzte Zustand des Servers (StateSync) schon da ist. Nur Anzeige: Der Server rechnet allein.
local function itemNote(result: any): (string?, string?)
    local item = CrateItems.byId[tostring(result.itemId)]
    if item == nil then
        return nil, nil
    end
    local snapshot: any = State.get()
    local stars = 1
    if snapshot ~= nil and type(snapshot.itemStars) == "table" then
        stars = EquipmentLogic.starsOf({ itemStars = snapshot.itemStars }, item.id)
    end
    local bonus = `+{bonusPercentText(EquipmentLogic.itemBonusBp(item, stars))} % Sammelrate`
    if result.isNew == true or snapshot == nil or type(snapshot.inventory) ~= "table" then
        return bonus, nil
    end
    local bucket = snapshot.inventory[EquipmentLogic.INVENTORY_FIELDS[item.kind]]
    local copies = if type(bucket) == "table" then bucket[item.id] else nil
    local cost = EquipmentLogic.mergeCost({ itemStars = snapshot.itemStars or {} }, item.id)
    if type(copies) ~= "number" or cost == nil then
        return bonus, nil
    end
    return bonus, `{copies} von {cost + 1} Kopien bis ★{stars + 1}`
end

local function playSound(key: string)
    local id = SOUND_IDS[key]
    if id == nil or id == "" then
        return
    end
    local sound = Instance.new("Sound")
    sound.SoundId = id
    sound.Parent = SoundService
    sound.Ended:Once(function()
        sound:Destroy()
    end)
    sound:Play()
end

-- Kann der Spieler die Kiste nach dem letzten Zustand des Servers bezahlen? Nur für die Anzeige.
local function canAfford(snapshot: any, crate: any, count: number): boolean
    local total = crate.price * (if count == 10 then Crates.bundle.buy else 1)
    if crate.currency == "gems" then
        return type(snapshot.gems) == "number" and snapshot.gems >= total
    end
    return BigNum.compare(BigNum.deserialize(snapshot.coins), BigNum.new(total)) >= 0
end

-- Für den Shop (Paket 4.5): Läuft gerade ein Kisten-Reveal? Kann das Kisten-Fenster geöffnet werden?
local revealActive = false
local openWindow: (() -> ())? = nil

function CrateShop.isRevealing(): boolean
    return revealActive
end

-- Öffnet das Kisten-Fenster (nur wenn der Server Kisten erlaubt, sonst tut es nichts).
function CrateShop.open()
    if openWindow ~= nil then
        openWindow()
    end
end

function CrateShop.Init() end

function CrateShop.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local openCrate = remotes:WaitForChild("OpenCrate") :: RemoteFunction
    local controls = Screen.controls()

    local window = Screen.createWindow({
        name = "CrateWindow",
        title = "Kisten",
        kind = "wide",
        footerHeight = FOOTER_HEIGHT,
    })
    local openButton = Screen.addMenuButton("CratesButton", "Kisten", MENU_ORDER)
    openButton.Visible = false -- erst, wenn der Server Kisten erlaubt
    openWindow = function()
        if openButton.Visible then
            window.open()
        end
    end
    openButton.Activated:Connect(window.toggle)

    local balanceLabel = newText(window.footer, "Balance", UDim2.new(0, 12, 0, 4), UDim2.new(1, -24, 0, 26), Enum.Font.GothamBold, GEM_COLOR, "")
    local messageLabel = newText(window.footer, "Message", UDim2.new(0, 12, 0, 34), UDim2.new(1, -24, 0, 24), Enum.Font.GothamBold, WARN_COLOR, "")

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

    -- Reveal ------------------------------------------------------------------------------
    local revealGui = Instance.new("ScreenGui")
    revealGui.Name = "DuneBaronCrateReveal"
    revealGui.ResetOnSpawn = false
    revealGui.DisplayOrder = REVEAL_DISPLAY_ORDER
    revealGui.IgnoreGuiInset = true
    revealGui.Enabled = false
    revealGui.Parent = player:WaitForChild("PlayerGui")

    local dim = Instance.new("Frame") -- nur Abdunkelung: fängt keine Eingaben ab (Active = false)
    dim.Name = "Dim"
    dim.Size = UDim2.fromScale(1, 1)
    dim.BackgroundColor3 = DIM_COLOR
    dim.BackgroundTransparency = 0.45
    dim.Active = false
    dim.Parent = revealGui

    local skipButton = Instance.new("TextButton") -- einziger anklickbarer Teil des Reveals
    skipButton.Name = "Skip"
    skipButton.AnchorPoint = Vector2.new(0.5, 1)
    skipButton.Position = UDim2.new(0.5, 0, 1, -24)
    skipButton.Size = UDim2.fromOffset(SKIP_BUTTON_WIDTH, SKIP_BUTTON_HEIGHT)
    skipButton.BackgroundColor3 = BUTTON_COLOR
    skipButton.Font = Enum.Font.GothamBold
    skipButton.TextColor3 = TEXT_COLOR
    skipButton.TextScaled = true
    skipButton.Text = "Überspringen"
    skipButton.ZIndex = 5
    skipButton.Parent = revealGui
    Instance.new("UICorner").Parent = skipButton
    local skipPadding = Instance.new("UIPadding")
    skipPadding.PaddingTop = UDim.new(0, 8)
    skipPadding.PaddingBottom = UDim.new(0, 8)
    skipPadding.Parent = skipButton

    local stage = Instance.new("Frame")
    stage.Name = "Stage"
    stage.BackgroundTransparency = 1
    stage.AnchorPoint = Vector2.new(0.5, 0.5)
    stage.Position = UDim2.fromScale(0.5, 0.5)
    stage.Size = UDim2.fromScale(0.92, 0.8)
    stage.Parent = revealGui
    local stageConstraint = Instance.new("UISizeConstraint")
    stageConstraint.MaxSize = Vector2.new(720, 520)
    stageConstraint.Parent = stage

    local chest = Instance.new("Frame")
    chest.Name = "Chest"
    chest.AnchorPoint = Vector2.new(0.5, 0.5)
    chest.Position = UDim2.fromScale(0.5, 0.5)
    chest.Size = UDim2.fromOffset(CHEST_SIZE, CHEST_SIZE)
    chest.BackgroundColor3 = CHEST_COLOR
    chest.Parent = stage
    Instance.new("UICorner").Parent = chest
    local chestStroke = Instance.new("UIStroke")
    chestStroke.Thickness = 4
    chestStroke.Color = MUTED_COLOR
    chestStroke.Parent = chest

    local cardHolder = Instance.new("Frame")
    cardHolder.Name = "Cards"
    cardHolder.BackgroundTransparency = 1
    cardHolder.Size = UDim2.fromScale(1, 1)
    cardHolder.Parent = stage

    local revealToken = 0
    local revealStartedAt = 0
    local skipRequested = false
    local revealFinished = true
    revealActive = false

    local function closeReveal()
        revealToken += 1
        revealGui.Enabled = false
        revealFinished = true
        revealActive = false
        for _, child in cardHolder:GetChildren() do
            child:Destroy()
        end
    end

    local function makeCard(result: any, size: Vector2, position: UDim2): Frame
        local rarity = Rarities.byId[result.rarityId] or Rarities.list[1]
        local color = hexColor(rarity.colorHex)
        local card = Instance.new("Frame")
        card.Name = tostring(result.itemId)
        card.AnchorPoint = Vector2.new(0.5, 0.5)
        card.Position = position
        card.Size = UDim2.fromOffset(size.X, size.Y)
        card.BackgroundColor3 = PANEL_COLOR
        card.BackgroundTransparency = 1
        card.Parent = cardHolder
        Instance.new("UICorner").Parent = card
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 3
        stroke.Color = color
        stroke.Transparency = 1
        stroke.Parent = card
        local small = size.Y < 100
        local rarityLabel = newText(card, "Rarity", UDim2.new(0, 6, 0, 4), UDim2.new(1, -12, 0, if small then 16 else 22), Enum.Font.GothamBold, color, rarity.name, Enum.TextXAlignment.Center)
        local nameLabel = newText(card, "Name", UDim2.new(0, 6, 0, if small then 22 else 30), UDim2.new(1, -12, 0, if small then 34 else 50), Enum.Font.GothamBold, TEXT_COLOR, tostring(result.name), Enum.TextXAlignment.Center)
        local tag = if result.isNew == true then "Neu" else "Duplikat"
        if result.pityTriggered ~= nil then
            tag = `{tag} · Garantie`
        end
        local kindName = KIND_NAMES[tostring(result.kind)] or ""
        local bonusText, progressText = itemNote(result)
        if progressText ~= nil and not small then
            tag = `Duplikat · {progressText}`
        end
        local infoLabel = newText(card, "Info", UDim2.new(0, 6, 1, if small then -22 else -30), UDim2.new(1, -12, 0, if small then 18 else 24), Enum.Font.Gotham, if result.isNew == true then GOOD_COLOR else MUTED_COLOR, if small then tag else `{kindName} · {tag}`, Enum.TextXAlignment.Center)
        -- Texte starten unsichtbar und blenden mit der Karte ein.
        local labels: { TextLabel } = { rarityLabel, nameLabel, infoLabel }
        if bonusText ~= nil and not small then
            local bonusLabel = newText(card, "Bonus", UDim2.new(0, 6, 0, 84), UDim2.new(1, -12, 0, 20), Enum.Font.GothamBold, GOOD_COLOR, bonusText, Enum.TextXAlignment.Center)
            table.insert(labels, bonusLabel)
        end
        for _, label in labels do
            label.TextTransparency = 1
        end
        return card
    end

    local function fadeInCard(card: Frame, instant: boolean)
        local info = TweenInfo.new(if instant then 0 else CARD_FADE_SECONDS, Enum.EasingStyle.Quad)
        TweenService:Create(card, info, { BackgroundTransparency = 0.05 }):Play()
        local stroke = card:FindFirstChildOfClass("UIStroke")
        if stroke ~= nil then
            TweenService:Create(stroke, info, { Transparency = 0 }):Play()
        end
        for _, child in card:GetChildren() do
            if child:IsA("TextLabel") then
                TweenService:Create(child, info, { TextTransparency = 0 }):Play()
            end
        end
    end

    local function waitOrSkip(seconds: number): boolean
        local untilTime = os.clock() + seconds
        while os.clock() < untilTime do
            if skipRequested then
                return true
            end
            task.wait()
        end
        return skipRequested
    end

    local function playReveal(reply: any)
        revealToken += 1
        local token = revealToken
        revealFinished = false
        revealActive = true
        skipRequested = false
        revealStartedAt = os.clock()
        for _, child in cardHolder:GetChildren() do
            child:Destroy()
        end
        local results: { any } = reply.results
        local highest = Rarities.byId[reply.highest] or Rarities.list[1]
        local highestColor = hexColor(highest.colorHex)
        revealGui.Enabled = true
        skipButton.Text = "Überspringen"
        chest.Visible = true
        chest.Rotation = 0
        chest.Size = UDim2.fromOffset(CHEST_SIZE, CHEST_SIZE)
        chest.BackgroundColor3 = CHEST_COLOR
        chestStroke.Color = MUTED_COLOR

        -- 1. Wackeln
        playSound("shake")
        local stepSeconds = SHAKE_SECONDS / SHAKE_STEPS
        for step = 1, SHAKE_STEPS do
            if token ~= revealToken then
                return
            end
            local angle = if step % 2 == 1 then SHAKE_ANGLE else -SHAKE_ANGLE
            TweenService:Create(chest, TweenInfo.new(stepSeconds, Enum.EasingStyle.Sine), { Rotation = angle }):Play()
            if waitOrSkip(stepSeconds) then
                break
            end
        end
        if token ~= revealToken then
            return
        end

        -- 2. Aufladen in der Farbe der höchsten Seltenheit, aufspringen
        TweenService:Create(chest, TweenInfo.new(GLOW_SECONDS), { Rotation = 0, BackgroundColor3 = highestColor }):Play()
        chestStroke.Color = highestColor
        if not skipRequested then
            waitOrSkip(GLOW_SECONDS)
        end
        if token ~= revealToken then
            return
        end
        playSound(if highest.rank >= 5 then "legendary" else "pop")
        TweenService:Create(chest, TweenInfo.new(POP_SECONDS, POP_EASING), { Size = UDim2.fromOffset(CHEST_SIZE * 1.4, CHEST_SIZE * 1.4) }):Play()
        waitOrSkip(POP_SECONDS)
        if token ~= revealToken then
            return
        end
        chest.Visible = false

        -- 3. Karten
        local total = #results
        local stageSize = stage.AbsoluteSize
        for index, result in results do
            local card: Frame
            if total == 1 then
                card = makeCard(result, CARD_SINGLE_SIZE, UDim2.fromScale(0.5, 0.5))
            else
                local column = (index - 1) % GRID_COLUMNS
                local row = math.floor((index - 1) / GRID_COLUMNS)
                local columns = math.min(GRID_COLUMNS, total)
                local rows = math.ceil(total / GRID_COLUMNS)
                local gridW = columns * CARD_GRID_SIZE.X + (columns - 1) * GRID_GAP
                local gridH = rows * CARD_GRID_SIZE.Y + (rows - 1) * GRID_GAP
                local x = stageSize.X / 2 - gridW / 2 + CARD_GRID_SIZE.X / 2 + column * (CARD_GRID_SIZE.X + GRID_GAP)
                local y = stageSize.Y / 2 - gridH / 2 + CARD_GRID_SIZE.Y / 2 + row * (CARD_GRID_SIZE.Y + GRID_GAP)
                card = makeCard(result, CARD_GRID_SIZE, UDim2.fromOffset(x, y))
            end
            fadeInCard(card, skipRequested)
            if not skipRequested then
                waitOrSkip(CARD_STAGGER_SECONDS)
            end
            if token ~= revealToken then
                return
            end
        end
        skipButton.Text = "Schließen"
        revealFinished = true -- die Karten bleiben bis "Schließen" stehen: revealActive bleibt wahr
        skipRequested = false
    end

    skipButton.Activated:Connect(function()
        if revealFinished then
            closeReveal()
        elseif os.clock() - revealStartedAt >= MIN_REVEAL_SECONDS_FOR_SKIP then
            skipRequested = true
        end
    end)

    -- Kisten-Karten im Fenster ----------------------------------------------------------------
    local snapshotNow: any = nil
    local busy = false
    local lastOpenAt = 0
    local cards: { [string]: { frame: Frame, pity: TextLabel?, single: TextButton, bundle: TextButton } } = {}

    local function tryOpen(crate: any, count: number)
        if busy then
            showMessage(REASONS.busy)
            return
        end
        local now = os.clock()
        if now - lastOpenAt < OPEN_COOLDOWN_SECONDS then
            return
        end
        lastOpenAt = now
        local snapshot = State.get()
        if snapshot ~= nil and not canAfford(snapshot, crate, count) then
            showMessage(if crate.currency == "gems" then REASONS.notEnoughGems else REASONS.notEnoughCoins)
            return
        end
        busy = true
        task.spawn(function()
            local ok, reply = pcall(function(): any
                return openCrate:InvokeServer(crate.id, count)
            end)
            busy = false
            if not ok or type(reply) ~= "table" then
                showMessage(REASONS.error)
                return
            end
            if reply.ok ~= true or type(reply.results) ~= "table" or #reply.results == 0 then
                showMessage(REASONS[tostring(reply.reason)] or REASONS.unknown)
                return
            end
            -- Fenster zu, damit der Reveal frei steht; der Spieler sieht danach das Spiel.
            window.close()
            local revealOk = pcall(playReveal, reply)
            if not revealOk then
                closeReveal() -- ein Fehler im Reveal darf das Vollbild nicht hängen lassen
            end
        end)
    end

    local order = 0
    for _, crate in Crates.list do
        if not crate.eventOnly then
            order += 1
            local frame = Instance.new("Frame")
            frame.Name = crate.id
            frame.LayoutOrder = order
            frame.Size = UDim2.new(1, 0, 0, 0)
            frame.AutomaticSize = Enum.AutomaticSize.Y
            frame.BackgroundColor3 = ROW_COLOR
            frame.BackgroundTransparency = 0.2
            frame.Parent = window.body
            Instance.new("UICorner").Parent = frame
            local pad = Instance.new("UIPadding")
            pad.PaddingTop = UDim.new(0, 8)
            pad.PaddingBottom = UDim.new(0, 8)
            pad.PaddingLeft = UDim.new(0, 10)
            pad.PaddingRight = UDim.new(0, 10)
            pad.Parent = frame
            local layout = Instance.new("UIListLayout")
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Padding = UDim.new(0, 4)
            layout.Parent = frame

            local line = 0
            local function nextLine(): number
                line += 1
                return line
            end

            local title = newText(frame, "Title", UDim2.new(), UDim2.new(1, 0, 0, 26), Enum.Font.GothamBold, TEXT_COLOR, `{crate.name}: {priceText(crate, 1)}`)
            title.LayoutOrder = nextLine()

            -- Quotentabelle: alle Seltenheiten in Rang-Reihenfolge von oben (selten) nach unten.
            for index = #Rarities.list, 1, -1 do
                local rarity = Rarities.list[index]
                local value = crate.odds[rarity.id] or 0
                local row = Instance.new("Frame")
                row.Name = `Odds_{rarity.id}`
                row.LayoutOrder = nextLine()
                row.Size = UDim2.new(1, 0, 0, 20)
                row.BackgroundTransparency = 1
                row.Parent = frame
                local color = hexColor(rarity.colorHex)
                newText(row, "Name", UDim2.new(), UDim2.new(0.6, 0, 1, 0), Enum.Font.GothamBold, if value > 0 then color else MUTED_COLOR, rarity.name)
                newText(row, "Value", UDim2.fromScale(0.6, 0), UDim2.fromScale(0.4, 1), Enum.Font.GothamBold, if value > 0 then TEXT_COLOR else MUTED_COLOR, oddsText(value), Enum.TextXAlignment.Right)
            end

            local pityLabel: TextLabel? = nil
            if crate.pity ~= nil then
                local created = newText(frame, "Pity", UDim2.new(), UDim2.new(1, 0, 0, 40), Enum.Font.Gotham, GOOD_COLOR, "")
                created.LayoutOrder = nextLine()
                pityLabel = created
            end

            local buttons = Instance.new("Frame")
            buttons.Name = "Buttons"
            buttons.LayoutOrder = nextLine()
            buttons.Size = UDim2.new(1, 0, 0, controls.rowButtonH)
            buttons.BackgroundTransparency = 1
            buttons.Parent = frame

            local function makeButton(name: string, anchorX: number, text: string, count: number): TextButton
                local b = Instance.new("TextButton")
                b.Name = name
                b.AnchorPoint = Vector2.new(anchorX, 0)
                b.Position = UDim2.fromScale(anchorX, 0)
                b.Size = UDim2.new(0.49, 0, 1, 0)
                b.BackgroundColor3 = BUY_COLOR
                b.Font = Enum.Font.GothamBold
                b.TextColor3 = PANEL_COLOR
                b.TextScaled = true
                b.Text = text
                b.Parent = buttons
                Instance.new("UICorner").Parent = b
                local p = Instance.new("UIPadding")
                p.PaddingTop = UDim.new(0, 8)
                p.PaddingBottom = UDim.new(0, 8)
                p.PaddingLeft = UDim.new(0, 4)
                p.PaddingRight = UDim.new(0, 4)
                p.Parent = b
                b.Activated:Connect(function()
                    tryOpen(crate, count)
                end)
                return b
            end
            local single = makeButton("Single", 0, `Öffnen\n{priceText(crate, 1)}`, 1)
            local bundle = makeButton("Bundle", 1, `{Crates.bundle.buy} + {Crates.bundle.get - Crates.bundle.buy} öffnen\n{priceText(crate, 10)}`, 10)
            cards[crate.id] = { frame = frame, pity = pityLabel, single = single, bundle = bundle }
        end
    end

    -- Anzeige auffrischen: Pity-Zähler, Kontostand, ausgegraute Knöpfe ---------------------------
    local function refresh()
        local snapshot = snapshotNow
        if snapshot == nil then
            return
        end
        local allowed = snapshot.cratesAllowed == true
        openButton.Visible = allowed
        if not allowed and window.isOpen() then
            window.close()
        end
        balanceLabel.Text = `Du hast {snapshot.gems or 0} Gems und {BigNum.format(BigNum.deserialize(snapshot.coins))} Münzen`
        local pity = snapshot.pity
        for crateId, card in cards do
            local crate = Crates.byId[crateId]
            if card.pity ~= nil and crate.pity ~= nil then
                local counters = if type(pity) == "table" then pity[crateId] else nil
                local sinceEpic = if counters ~= nil and type(counters.sinceEpic) == "number" then counters.sinceEpic else 0
                local sinceLegendary = if counters ~= nil and type(counters.sinceLegendary) == "number" then counters.sinceLegendary else 0
                local epicLeft = math.max(crate.pity.epic - sinceEpic, 1)
                local legendaryLeft = math.max(crate.pity.legendary - sinceLegendary, 1)
                card.pity.Text = `Episch oder besser garantiert in {epicLeft} Öffnungen.\nLegendär oder besser garantiert in {legendaryLeft} Öffnungen.`
            end
            local singleOk = canAfford(snapshot, crate, 1)
            card.single.BackgroundColor3 = if singleOk then BUY_COLOR else BUTTON_COLOR
            card.single.TextColor3 = if singleOk then PANEL_COLOR else MUTED_COLOR
            local bundleOk = canAfford(snapshot, crate, 10)
            card.bundle.BackgroundColor3 = if bundleOk then BUY_COLOR else BUTTON_COLOR
            card.bundle.TextColor3 = if bundleOk then PANEL_COLOR else MUTED_COLOR
        end
    end

    State.onChanged(function(snapshot: any)
        snapshotNow = snapshot
        refresh()
    end)
end

return CrateShop
