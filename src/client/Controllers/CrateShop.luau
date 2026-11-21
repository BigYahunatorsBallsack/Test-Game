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
-- Quoten (Paket 4.6, Roblox-Regel für bezahlte Zufallsitems): Die Karte zeigt die Quoten der nächsten
-- Öffnung dieses Spielers (CrateRoll.effectiveOdds; steht eine Pity-Garantie an, nur die garantierten
-- Seltenheiten), die Zähler bis zur Garantie mit Kosten in Gems und die Stelle der Garantie im Paket.
-- "Details" zeigt jedes Item mit seiner Quote (CrateRoll.itemOdds), die Pity-Regel in Zahlen und den
-- Rundungshinweis. Texte und Formatierung in Logic/OddsView.
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
local PITY_TEXT_HEIGHT = 110 -- bis fünf Zeilen: anstehende Garantie mit Quoten, zwei Zähler, Satz zum Paket
local DETAILS_BUTTON_HEIGHT = 36
local DETAILS_ROW_HEIGHT = 22
local DETAILS_HEADER_HEIGHT = 26
local DETAILS_NOTE_HEIGHT = 40
local DETAILS_FOOTER_HEIGHT = 64
local TEXT_DETAILS = "Details: alle Items und Quoten"
local TEXT_BACK = "Zurück zu den Kisten"

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

-- Event-Kiste (Paket 5.4): Höhe der Saison-Zeile und Texte. Der Server entscheidet, ob die Kiste
-- offen ist (Snapshot `season`); der Client rechnet nur den Countdown herunter.
local SEASON_LINE_HEIGHT = 40
local SEASON_TICK_SECONDS = 1
local SEASON_ENDS_TEXT = "Saison endet in %s"
local SEASON_NEXT_TEXT = "Nächste Saison in %s"
local SEASON_CLOSED_TEXT = "Diese Woche ist die Event-Kiste geschlossen."

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
local CrateRoll = loadShared("Logic", "CrateRoll")
local OddsView = loadShared("Logic", "OddsView")
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

local function priceText(crate: any, count: number): string
    local total = crate.price * (if count == 10 then Crates.bundle.buy else 1)
    if crate.currency == "gems" then
        return `{total} Gems`
    end
    return `{BigNum.format(BigNum.new(total))} Münzen`
end

-- "3 Tage 4 Std", "5 Std 12 Min" oder "12 Min" (mindestens 1 Min).
local function leftText(seconds: number): string
    local minutes = math.max(math.ceil(seconds / 60), 1)
    local days = math.floor(minutes / 1440)
    local hours = math.floor((minutes % 1440) / 60)
    if days > 0 then
        return `{days} {if days == 1 then "Tag" else "Tage"} {hours} Std`
    end
    if hours > 0 then
        return `{hours} Std {minutes % 60} Min`
    end
    return `{minutes} Min`
end

-- Text der Saison-Zeile einer Event-Kiste (Paket 5.4), siehe seasonView.
local function seasonText(view: string, seconds: number, hint: string?): string
    if view == "open" then
        local ends = string.format(SEASON_ENDS_TEXT, leftText(seconds))
        return if hint ~= nil then `{hint}\n{ends}` else ends
    end
    if view == "closed" then
        return SEASON_CLOSED_TEXT
    end
    if view == "next" then
        return string.format(SEASON_NEXT_TEXT, leftText(seconds))
    end
    return ""
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

-- Spielt den Reveal für eine Antwort im Format von OpenCrate ab (Daily Reward Tag 7, Paket 5.1).
-- Gibt false zurück, wenn der Controller noch nicht bereit ist.
local playExternal: ((any) -> ())? = nil
function CrateShop.playReveal(reply: any): boolean
    if playExternal == nil or type(reply) ~= "table" or type(reply.results) ~= "table" or #reply.results == 0 then
        return false
    end
    playExternal(reply)
    return true
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
    local openDetails: (crate: any) -> () = function(_crate: any) end
    local refreshCards: () -> () = function() end
    local cards: { [string]: { frame: Frame, seasonLine: TextLabel?, pity: TextLabel?, single: TextButton, bundle: TextButton, oddsTitle: TextLabel, oddsRows: { [string]: { name: TextLabel, value: TextLabel, color: Color3 } } } } = {}

    -- Pity-Stand einer Kiste aus dem letzten Zustand des Servers (fehlt = 0/0).
    local function countersOf(snapshot: any, crateId: string): any
        local pity = if snapshot ~= nil then snapshot.pity else nil
        return if type(pity) == "table" and type(pity[crateId]) == "table" then pity[crateId] else nil
    end

    -- Event-Kiste (Paket 5.4): Stand der Saison für diese Kiste aus dem letzten Zustand des Servers.
    -- "open": die Saison der Kiste läuft und die Woche erlaubt das Öffnen; "next": diese Saison
    -- kommt als nächste (Kiste gesperrt, Quoten bleiben sichtbar); "hidden" (auch "none"): keine
    -- Saison dieser Kiste läuft oder kommt (Karte unsichtbar). Dazu die Sekunden
    -- (Countdown, seit dem Snapshot heruntergezählt).
    local seasonSyncedAt = os.clock()
    local function seasonView(crateId: string): (string, number, string?)
        local season = if snapshotNow ~= nil then snapshotNow.season else nil
        if type(season) ~= "table" then
            return "none", 0, nil
        end
        local elapsed = os.clock() - seasonSyncedAt
        if season.active == true then
            if season.crateId ~= crateId then
                return "hidden", 0, nil
            end
            local left = if type(season.secondsLeft) == "number" then math.max(season.secondsLeft - elapsed, 0) else 0
            return (if season.crateOpen == true then "open" else "closed"), left, season.hint
        end
        local nextSeason = season.next
        if type(nextSeason) == "table" then
            if nextSeason.crateId ~= crateId then
                return "hidden", 0, nil
            end
            local left = if type(nextSeason.secondsToNext) == "number" then math.max(nextSeason.secondsToNext - elapsed, 0) else 0
            return "next", left, nil
        end
        return "none", 0, nil
    end

    -- Quoten der nächsten Öffnung in die Karte schreiben (dieselbe Funktion, über die der Server
    -- würfelt). Seltenheiten, die gerade nicht vorkommen können, stehen grau mit 0 %.
    -- Die Tabelle ist immer die normale (jedes mögliche Ergebnis, auch im 10 + 1 Paket nach einer
    -- Garantie). Steht eine Garantie an, nennt die Pity-Zeile ihre Quoten zusätzlich (OddsView.dueLine).
    local function renderOdds(card: any, crate: any, _counters: any)
        local effective = CrateRoll.effectiveOdds(crate, nil)
        card.oddsTitle.Text = OddsView.oddsTitle(nil)
        card.oddsTitle.TextColor3 = MUTED_COLOR
        for rarityId, row in card.oddsRows do
            local weight = effective.odds[rarityId] or 0
            local possible = weight > 0 and effective.total > 0
            row.name.TextColor3 = if possible then row.color else MUTED_COLOR
            row.value.TextColor3 = if possible then TEXT_COLOR else MUTED_COLOR
            row.value.Text = OddsView.percentText(if possible then weight / effective.total else 0)
        end
    end

    -- Details-Fenster: alle Items der Kiste mit ihrer Quote, die Pity-Regel in Zahlen und der
    -- Rundungshinweis. Liest dieselben Funktionen wie der Server (CrateRoll.itemOdds).
    local detailsWindow = Screen.createWindow({
        name = "CrateDetailsWindow",
        title = "Details",
        kind = "wide",
        footerHeight = DETAILS_FOOTER_HEIGHT,
    })
    local backButton = Instance.new("TextButton")
    backButton.Name = "Back"
    backButton.AnchorPoint = Vector2.new(0.5, 0.5)
    backButton.Position = UDim2.fromScale(0.5, 0.5)
    backButton.Size = UDim2.new(1, -24, 0, controls.rowButtonH)
    backButton.BackgroundColor3 = BUTTON_COLOR
    backButton.Font = Enum.Font.GothamBold
    backButton.TextColor3 = TEXT_COLOR
    backButton.TextScaled = true
    backButton.Text = TEXT_BACK
    backButton.Parent = detailsWindow.footer
    Instance.new("UICorner").Parent = backButton
    local backPad = Instance.new("UIPadding")
    backPad.PaddingTop = UDim.new(0, 8)
    backPad.PaddingBottom = UDim.new(0, 8)
    backPad.Parent = backButton
    backButton.Activated:Connect(function()
        detailsWindow.close()
        window.open()
    end)

    local detailsCrateId: string? = nil
    local function renderDetails()
        local crateId = detailsCrateId
        if crateId == nil then
            return
        end
        local crate = Crates.byId[crateId]
        for _, child in detailsWindow.body:GetChildren() do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        detailsWindow.title.Text = `Details: {crate.name}`
        local order = 0
        local function add(height: number, font: Enum.Font, color: Color3, text: string, align: Enum.TextXAlignment?): TextLabel
            order += 1
            local label = newText(detailsWindow.body, `Line{order}`, UDim2.new(), UDim2.new(1, 0, 0, height), font, color, text, align)
            label.LayoutOrder = order
            return label
        end

        local counters = countersOf(snapshotNow, crateId)

        -- Items nach Seltenheit gruppiert (höchste zuerst); itemOdds liefert sie schon so sortiert.
        local function addSection(title: string, titleColor: Color3, sectionCounters: any)
            add(DETAILS_HEADER_HEIGHT, Enum.Font.GothamBold, titleColor, title)
            local effective = CrateRoll.effectiveOdds(crate, sectionCounters)
            local items = CrateRoll.itemOdds(crateId, sectionCounters)
            local groups: { { rarityId: string, entries: { any } } } = {}
            for _, entry in items do
                local last = groups[#groups]
                if last == nil or last.rarityId ~= entry.rarityId then
                    last = { rarityId = entry.rarityId, entries = {} }
                    table.insert(groups, last)
                end
                table.insert(last.entries, entry)
            end
            for _, group in groups do
                local rarity = Rarities.byId[group.rarityId]
                local weight = effective.odds[group.rarityId] or 0
                local share = if effective.total > 0 then weight / effective.total else 0
                local first = group.entries[1]
                local each = first.numerator / first.denominator
                add(DETAILS_HEADER_HEIGHT, Enum.Font.GothamBold, if rarity then hexColor(rarity.colorHex) else TEXT_COLOR, `{if rarity then rarity.name else group.rarityId}: {OddsView.percentText(share)}, Quote je Item: {OddsView.percentText(each)}`)
                for _, entry in group.entries do
                    local kindName = KIND_NAMES[entry.kind] or tostring(entry.kind)
                    add(DETAILS_ROW_HEIGHT, Enum.Font.Gotham, TEXT_COLOR, `   {entry.name} ({kindName}): {OddsView.percentText(entry.numerator / entry.denominator)}`)
                end
            end
        end

        -- Normale Tabelle: jedes mögliche Ergebnis. Danach die Quoten einer garantierten Öffnung je Stufe.
        addSection(OddsView.oddsTitle(nil), TEXT_COLOR, nil)
        local dueLine = OddsView.dueLine(crate, counters)
        if dueLine ~= nil then
            add(DETAILS_NOTE_HEIGHT, Enum.Font.GothamBold, GOOD_COLOR, dueLine)
        end
        for _, tier in { "epic", "legendary" } do
            local tierCounters = OddsView.dueCounters(crate, tier)
            if tierCounters ~= nil then
                addSection(`Garantierte Öffnung ({if tier == "epic" then "Episch" else "Legendär"} oder besser)`, GOOD_COLOR, tierCounters)
            end
        end

        for _, line in OddsView.pityRules(crate) do
            add(DETAILS_NOTE_HEIGHT, Enum.Font.Gotham, GOOD_COLOR, line)
        end
        if crate.pity ~= nil then
            for _, line in OddsView.pityLines(crate, counters) do
                add(DETAILS_ROW_HEIGHT, Enum.Font.Gotham, GOOD_COLOR, line)
            end
        end
        add(DETAILS_NOTE_HEIGHT, Enum.Font.Gotham, MUTED_COLOR, OddsView.bundleRule(Crates.bundle.buy, Crates.bundle.get))
        add(DETAILS_NOTE_HEIGHT, Enum.Font.Gotham, MUTED_COLOR, OddsView.ROUNDING_NOTE)
    end

    openDetails = function(crate: any)
        detailsCrateId = crate.id
        local ok, err = pcall(renderDetails)
        if not ok then
            warn(`[CrateShop] Details für {crate.id} fehlgeschlagen: {tostring(err)}`)
            return
        end
        detailsWindow.open()
    end

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
        if crate.eventOnly and seasonView(crate.id) ~= "open" then
            showMessage(REASONS.notInSeason) -- nur Hinweis: der Server entscheidet ohnehin
            return
        end
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
            -- Neuer Pity-Stand sofort aus der Antwort (nicht erst mit dem nächsten StateSync), damit die
            -- Karte nie eine Garantie zeigt, die schon verbraucht ist (Sicherheitsprüfung 4.6, M1).
            if type(reply.pity) == "table" and snapshotNow ~= nil then
                local nextSnapshot = table.clone(snapshotNow)
                local pity = if type(nextSnapshot.pity) == "table" then table.clone(nextSnapshot.pity) else {}
                pity[crate.id] = reply.pity
                nextSnapshot.pity = pity
                snapshotNow = nextSnapshot
                refreshCards()
            end
            -- Fenster zu, damit der Reveal frei steht; der Spieler sieht danach das Spiel.
            window.close()
            local revealOk = pcall(playReveal, reply)
            if not revealOk then
                closeReveal() -- ein Fehler im Reveal darf das Vollbild nicht hängen lassen
            end
        end)
    end

    playExternal = function(reply: any)
        local revealOk = pcall(playReveal, reply)
        if not revealOk then
            closeReveal()
        end
    end

    local order = 0
    for _, crate in Crates.list do
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

        -- Event-Kiste (Paket 5.4): Zeile mit Saison-Countdown oder Hinweis. Die Karte selbst ist nur
        -- zu sehen, wenn die Saison dieser Kiste läuft oder als nächste kommt (`refresh`).
        local seasonLine: TextLabel? = nil
        if crate.eventOnly then
            frame.Visible = false
            local created = newText(frame, "Season", UDim2.new(), UDim2.new(1, 0, 0, SEASON_LINE_HEIGHT), Enum.Font.GothamBold, GOOD_COLOR, "")
            created.LayoutOrder = nextLine()
            seasonLine = created
        end

        -- Quotentabelle: alle Seltenheiten in Rang-Reihenfolge von oben (selten) nach unten. Die Werte
        -- schreibt `refresh` aus CrateRoll.effectiveOdds (bei anstehender Garantie die Quoten der
        -- nächsten Öffnung dieses Spielers, Paket 4.6).
        local oddsTitle = newText(frame, "OddsTitle", UDim2.new(), UDim2.new(1, 0, 0, 20), Enum.Font.Gotham, MUTED_COLOR, OddsView.oddsTitle(nil))
        oddsTitle.LayoutOrder = nextLine()
        local oddsRows: { [string]: { name: TextLabel, value: TextLabel, color: Color3 } } = {}
        for index = #Rarities.list, 1, -1 do
            local rarity = Rarities.list[index]
            local row = Instance.new("Frame")
            row.Name = `Odds_{rarity.id}`
            row.LayoutOrder = nextLine()
            row.Size = UDim2.new(1, 0, 0, 20)
            row.BackgroundTransparency = 1
            row.Parent = frame
            local color = hexColor(rarity.colorHex)
            local nameLabel = newText(row, "Name", UDim2.new(), UDim2.new(0.6, 0, 1, 0), Enum.Font.GothamBold, MUTED_COLOR, rarity.name)
            local valueLabel = newText(row, "Value", UDim2.fromScale(0.6, 0), UDim2.fromScale(0.4, 1), Enum.Font.GothamBold, MUTED_COLOR, "", Enum.TextXAlignment.Right)
            oddsRows[rarity.id] = { name = nameLabel, value = valueLabel, color = color }
        end

        local pityLabel: TextLabel? = nil
        if crate.pity ~= nil then
            local created = newText(frame, "Pity", UDim2.new(), UDim2.new(1, 0, 0, PITY_TEXT_HEIGHT), Enum.Font.Gotham, GOOD_COLOR, "")
            created.LayoutOrder = nextLine()
            pityLabel = created
        end

        -- "Details": alle Items mit ihrer Quote (Roblox verlangt ein Wort am Knopf, kein nacktes Symbol).
        local detailsButton = Instance.new("TextButton")
        detailsButton.Name = "Details"
        detailsButton.LayoutOrder = nextLine()
        detailsButton.Size = UDim2.new(1, 0, 0, DETAILS_BUTTON_HEIGHT)
        detailsButton.BackgroundColor3 = BUTTON_COLOR
        detailsButton.Font = Enum.Font.GothamBold
        detailsButton.TextColor3 = TEXT_COLOR
        detailsButton.TextScaled = true
        detailsButton.Text = TEXT_DETAILS
        detailsButton.Parent = frame
        Instance.new("UICorner").Parent = detailsButton
        local detailsPad = Instance.new("UIPadding")
        detailsPad.PaddingTop = UDim.new(0, 6)
        detailsPad.PaddingBottom = UDim.new(0, 6)
        detailsPad.Parent = detailsButton
        detailsButton.Activated:Connect(function()
            openDetails(crate)
        end)

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
        cards[crate.id] = { frame = frame, seasonLine = seasonLine, pity = pityLabel, single = single, bundle = bundle, oddsTitle = oddsTitle, oddsRows = oddsRows }
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
        if not allowed and detailsWindow.isOpen() then
            detailsWindow.close()
        elseif detailsWindow.isOpen() then
            pcall(renderDetails) -- Pity-Stand hat sich geändert: Quoten der nächsten Öffnung neu
        end
        balanceLabel.Text = `Du hast {snapshot.gems or 0} Gems und {BigNum.format(BigNum.deserialize(snapshot.coins))} Münzen`
        for crateId, card in cards do
            local crate = Crates.byId[crateId]
            local counters = countersOf(snapshot, crateId)
            renderOdds(card, crate, counters)
            if card.pity ~= nil and crate.pity ~= nil then
                local lines = OddsView.pityLines(crate, counters)
                local dueLine = OddsView.dueLine(crate, counters)
                if dueLine ~= nil then
                    table.insert(lines, 1, dueLine)
                end
                local bundleText = OddsView.bundleText(crate, counters, Crates.bundle.get)
                if bundleText ~= nil then
                    table.insert(lines, bundleText)
                end
                card.pity.Text = table.concat(lines, "\n")
            end
            local seasonOpen = true
            if card.seasonLine ~= nil then
                local view, seconds, hint = seasonView(crateId)
                seasonOpen = view == "open"
                card.frame.Visible = view == "open" or view == "next" or view == "closed"
                card.seasonLine.Text = seasonText(view, seconds, hint)
                card.seasonLine.TextColor3 = if seasonOpen then GOOD_COLOR else WARN_COLOR
            end
            local singleOk = seasonOpen and canAfford(snapshot, crate, 1)
            card.single.BackgroundColor3 = if singleOk then BUY_COLOR else BUTTON_COLOR
            card.single.TextColor3 = if singleOk then PANEL_COLOR else MUTED_COLOR
            local bundleOk = seasonOpen and canAfford(snapshot, crate, 10)
            card.bundle.BackgroundColor3 = if bundleOk then BUY_COLOR else BUTTON_COLOR
            card.bundle.TextColor3 = if bundleOk then PANEL_COLOR else MUTED_COLOR
        end
    end

    refreshCards = refresh
    State.onChanged(function(snapshot: any)
        snapshotNow = snapshot
        seasonSyncedAt = os.clock()
        refresh()
    end)
    -- Countdown der Saison-Zeile: einmal pro Sekunde, nur solange das Fenster offen ist.
    task.spawn(function()
        while true do
            task.wait(SEASON_TICK_SECONDS)
            if window.isOpen() and snapshotNow ~= nil then
                pcall(refresh)
            end
        end
    end)
end

return CrateShop
