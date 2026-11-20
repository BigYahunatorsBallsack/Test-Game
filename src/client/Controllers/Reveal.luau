--!strict
-- Reveal-Controller (Paket 2.6)
-- Zeigt jeden Fund, den der Server meldet (Notify, kind = "find"): ein Platzhalter-Objekt steigt aus
-- dem Sand (nur auf dem eigenen Bildschirm), dazu eine Karte. Gewöhnliche und Ungewöhnliche Funde
-- bekommen eine kleine Karte am Rand, ab Selten gibt es eine große Karte in der Mitte mit Aufladen,
-- Lichtstoß in der Seltenheitsfarbe und (Mythisch) einem Bildschirmblitz. Der Reveal blockiert nie:
-- Sammeln und Laufen gehen weiter, ein Tipp auf die Karte überspringt sie. Mehrere Funde laufen
-- nacheinander. Alle Werte kommen vom Server, der Client rechnet nichts.
--
-- Handy (Paket 3.6): Die Karten liegen auf der sicheren Fläche und folgen der Größenklasse aus
-- Data/Screen (kleine Karte am Handy links unter dem HUD, damit sie die Menüspalte nicht verdeckt).
-- Auf Grafikstufe "minimal" entfallen Lichtstoß, Blitz und das Objekt im Sand, auf "schlank" das Licht.
--
-- Sounds: leere IDs bis Paket 3.5 (leer = kein Ton, kein Fehler). Meshes: Platzhalter-Teile bis 3.2.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

-- Warteschlange
local QUEUE_MAX = 12 -- mehr wartende Reveals werden verworfen (die Münzen sind trotzdem gebucht)
local SHORT_MODE_FROM_QUEUE = 3 -- ab so vielen wartenden Reveals laufen alle kurz

-- Kleine Karte (Gewöhnlich, Ungewöhnlich): Größe und Platz stehen in Data/Screen (smallCard)
local SMALL_SLIDE_SECONDS = 0.25
local SMALL_SLIDE_EASING = Enum.EasingStyle.Quad
local SMALL_HOLD_SECONDS: { [string]: number } = { common = 1.0, uncommon = 1.4 }
local SMALL_HOLD_SHORT_SECONDS = 0.45

-- Große Karte (ab Selten): Aufladen, Lichtstoß, Karte (Größe in Data/Screen: bigCard)
local BIG_CARD_SIDE_MARGIN = 12 -- Abstand zum Bildrand bei schmalem Bildschirm
local CARD_POP_SECONDS = 0.28
local CARD_POP_EASING = Enum.EasingStyle.Back
local CARD_POP_START_SCALE = 0.6
local CARD_LEAVE_SECONDS = 0.25
local GLOW_START_SIZE = 20
local GLOW_CHARGED_SIZE = 220
local GLOW_BURST_SIZE = 560
local GLOW_BURST_SECONDS = 0.35
local GLOW_START_TRANSPARENCY = 0.5
local FLASH_SECONDS = 0.5
local SHORT_CHARGE_SECONDS = 0.12
local SHORT_HOLD_SECONDS = 0.8
local DUPLICATE_CHARGE_FACTOR = 0.5 -- doppelte Funde laden kürzer auf

-- Ablauf je Seltenheit (Aufladen und Halten in Sekunden)
local REVEAL: { [string]: { big: boolean, charge: number, hold: number, flash: boolean } } = {
    common = { big = false, charge = 0, hold = 0, flash = false },
    uncommon = { big = false, charge = 0, hold = 0, flash = false },
    rare = { big = true, charge = 0.4, hold = 1.8, flash = false },
    epic = { big = true, charge = 0.7, hold = 2.2, flash = false },
    legendary = { big = true, charge = 1.0, hold = 2.6, flash = false },
    mythic = { big = true, charge = 1.2, hold = 3.2, flash = true },
}

-- Banner (Set fertig, Zonenbuch fertig)
local BANNER_SECONDS = 2.2
local BANNER_COLOR = Color3.fromRGB(255, 200, 80)

-- Platzhalter-Objekt im Sand
local SAND_OBJECT = {
    forwardStuds = 4, -- vor dem Charakter
    groundOffset = 2.5, -- Fußhöhe unter der Mitte des Charakters
    sinkStuds = 1.4, -- so tief startet es im Sand
    riseStuds = 1.8, -- so hoch steigt es über den Sand
    riseSeconds = 1.1,
    lingerSeconds = 0.9,
    fadeSeconds = 0.4,
    size = 1.1,
    lightRange = 14,
    lightBrightness = 2,
}

-- Sounds je Seltenheit (Paket 3.5). Leer = kein Ton.
local SOUND_IDS: { [string]: string } = {
    common = "",
    uncommon = "",
    rare = "",
    epic = "",
    legendary = "",
    mythic = "",
    setComplete = "",
}

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(200, 185, 160)

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local BigNum = loadShared("Logic", "BigNum")
local Finds = loadShared("Data", "Finds")
local Rarities = loadShared("Data", "Rarities")
local CollectionData = loadShared("Data", "Collection")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Graphics = require(script.Parent:WaitForChild("Graphics") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

local Reveal = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil -- Karten (sichere Fläche)
local fxGui: ScreenGui? = nil -- Lichtstoß und Blitz (ganzer Bildschirm)
local queue: { any } = {}
local running = false
local skip = false

local function percentText(bp: number): string
    local value = bp / 100
    local text = if value % 1 == 0 then tostring(math.floor(value)) else string.format("%.1f", value)
    local replaced = string.gsub(text, "%.", ",")
    return replaced
end

local function playSound(key: string)
    local id = SOUND_IDS[key]
    if id == nil or id == "" then
        return
    end
    local sound = Instance.new("Sound")
    sound.SoundId = id
    sound.Parent = SoundService
    sound:Play()
    Debris:AddItem(sound, 8)
end

-- Wartet `seconds`, bricht aber ab, sobald der Spieler die Karte antippt.
local function pause(seconds: number)
    local elapsed = 0
    while elapsed < seconds and not skip do
        elapsed += task.wait(0.05)
    end
end

local function label(parent: Instance, position: UDim2, size: UDim2, font: Enum.Font, color: Color3, text: string): TextLabel
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = position
    l.Size = size
    l.Font = font
    l.TextColor3 = color
    l.TextScaled = true
    l.TextXAlignment = Enum.TextXAlignment.Center
    l.Text = text
    l.Parent = parent
    return l
end

-- Eine antippbare Karte mit farbigem Rand. Tipp überspringt das Warten.
local function makeCard(size: Vector2, color: Color3): TextButton
    local card = Instance.new("TextButton")
    card.AutoButtonColor = false
    card.Text = ""
    card.Size = UDim2.fromOffset(size.X, size.Y)
    card.BackgroundColor3 = PANEL_COLOR
    card.BackgroundTransparency = 0.1
    card.Parent = gui
    Instance.new("UICorner").Parent = card
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = 3
    stroke.Parent = card
    card.Activated:Connect(function()
        skip = true
    end)
    return card
end

local function setProgressText(payload: any): string
    local findSet = Finds.setsById[payload.setId]
    local index = if findSet ~= nil then findSet.index else 0
    return `Set {index}: {payload.setHave}/{payload.setSize}`
end

local function statusText(payload: any): string
    if payload.isNew then
        return "NEU"
    end
    if type(payload.coins) == "table" then
        return `Doppelt: +{BigNum.format(BigNum.deserialize(payload.coins))} Münzen`
    end
    return "Doppelt"
end

-- Platzhalter-Objekt, das aus dem Sand steigt (nur auf dem eigenen Bildschirm).
local function spawnSandObject(color: Color3)
    local graphics = Graphics.settings()
    if graphics.revealEffects ~= true then
        return -- schwaches Gerät: keine Effekte
    end
    local character = player.Character
    local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
    if root == nil or not root:IsA("BasePart") then
        return
    end
    local ground = root.Position + root.CFrame.LookVector * SAND_OBJECT.forwardStuds - Vector3.new(0, SAND_OBJECT.groundOffset, 0)
    local part = Instance.new("Part")
    part.Name = "FindReveal"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Size = Vector3.new(SAND_OBJECT.size, SAND_OBJECT.size, SAND_OBJECT.size)
    part.CFrame = CFrame.new(ground - Vector3.new(0, SAND_OBJECT.sinkStuds, 0)) * CFrame.Angles(math.rad(45), math.rad(35), 0)
    local light: PointLight? = nil
    if graphics.foundLight == true then
        local created = Instance.new("PointLight")
        created.Color = color
        created.Range = SAND_OBJECT.lightRange
        created.Brightness = SAND_OBJECT.lightBrightness
        created.Parent = part
        light = created
    end
    part.Parent = workspace
    Debris:AddItem(part, SAND_OBJECT.riseSeconds + SAND_OBJECT.lingerSeconds + SAND_OBJECT.fadeSeconds + 1)

    local rise = TweenInfo.new(SAND_OBJECT.riseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(part, rise, { CFrame = CFrame.new(ground + Vector3.new(0, SAND_OBJECT.riseStuds, 0)) * CFrame.Angles(math.rad(45), math.rad(215), 0) }):Play()
    task.delay(SAND_OBJECT.riseSeconds + SAND_OBJECT.lingerSeconds, function()
        if part.Parent == nil then
            return
        end
        local fade = TweenInfo.new(SAND_OBJECT.fadeSeconds)
        TweenService:Create(part, fade, { Transparency = 1 }):Play()
        if light ~= nil then
            TweenService:Create(light, fade, { Brightness = 0 }):Play()
        end
    end)
end

-- Größe, Anker und Plätze (gezeigt, versteckt) der kleinen Karte nach der Größenklasse.
local function smallPlacement(): (Vector2, Vector2, UDim2, UDim2)
    local c = Screen.classData().smallCard
    local size = Vector2.new(c.w, c.h)
    if c.side == "left" then
        return size, Vector2.new(0, c.anchorY), UDim2.new(0, c.margin, c.yScale, c.yOffset), UDim2.new(0, -(c.w + c.margin), c.yScale, c.yOffset)
    end
    return size, Vector2.new(1, c.anchorY), UDim2.new(1, -c.margin, c.yScale, c.yOffset), UDim2.new(1, c.w + c.margin, c.yScale, c.yOffset)
end

local function showSmall(payload: any, find: any, rarity: any, short: boolean)
    local color = Color3.fromHex(rarity.colorHex)
    local size, anchor, shown, hidden = smallPlacement()
    local card = makeCard(size, color)
    card.AnchorPoint = anchor
    card.Position = hidden
    label(card, UDim2.new(0, 10, 0.07, 0), UDim2.new(1, -20, 0.3, 0), Enum.Font.GothamBold, color, find.name)
    label(card, UDim2.new(0, 10, 0.4, 0), UDim2.new(1, -20, 0.24, 0), Enum.Font.GothamBold, TEXT_COLOR, `{rarity.name} · {statusText(payload)}`)
    label(card, UDim2.new(0, 10, 0.68, 0), UDim2.new(1, -20, 0.22, 0), Enum.Font.Gotham, MUTED_COLOR, setProgressText(payload))

    local slide = TweenInfo.new(SMALL_SLIDE_SECONDS, SMALL_SLIDE_EASING)
    TweenService:Create(card, slide, { Position = shown }):Play()
    pause(SMALL_SLIDE_SECONDS + (if short then SMALL_HOLD_SHORT_SECONDS else (SMALL_HOLD_SECONDS[rarity.id] or 1)))
    TweenService:Create(card, slide, { Position = hidden }):Play()
    task.wait(SMALL_SLIDE_SECONDS)
    card:Destroy()
end

local function showBig(payload: any, find: any, rarity: any, short: boolean)
    local color = Color3.fromHex(rarity.colorHex)
    local timing = REVEAL[rarity.id] or REVEAL.rare
    local charge = timing.charge
    local hold = timing.hold
    if short then
        charge = SHORT_CHARGE_SECONDS
        hold = SHORT_HOLD_SECONDS
    elseif not payload.isNew then
        charge *= DUPLICATE_CHARGE_FACTOR
    end
    local effects = Graphics.settings().revealEffects == true

    -- Aufladen: ein Licht in der Seltenheitsfarbe wächst in der Mitte.
    local glow: Frame? = nil
    if effects and charge > 0 then
        local g = Instance.new("Frame")
        g.AnchorPoint = Vector2.new(0.5, 0.5)
        g.Position = UDim2.fromScale(0.5, 0.5)
        g.Size = UDim2.fromOffset(GLOW_START_SIZE, GLOW_START_SIZE)
        g.BackgroundColor3 = color
        g.BackgroundTransparency = GLOW_START_TRANSPARENCY
        g.BorderSizePixel = 0
        g.Parent = fxGui
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = g
        TweenService:Create(
            g,
            TweenInfo.new(charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Size = UDim2.fromOffset(GLOW_CHARGED_SIZE, GLOW_CHARGED_SIZE) }
        ):Play()
        glow = g
    end
    if charge > 0 then
        task.wait(charge)
    end

    -- Lichtstoß und (Mythisch) Bildschirmblitz.
    if glow ~= nil then
        local burst = TweenInfo.new(GLOW_BURST_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(glow, burst, {
            Size = UDim2.fromOffset(GLOW_BURST_SIZE, GLOW_BURST_SIZE),
            BackgroundTransparency = 1,
        }):Play()
        Debris:AddItem(glow, GLOW_BURST_SECONDS + 0.1)
    end
    if effects and timing.flash and not short then
        local flash = Instance.new("Frame")
        flash.Size = UDim2.fromScale(1, 1)
        flash.BackgroundColor3 = Color3.new(1, 1, 1)
        flash.BackgroundTransparency = 0.3
        flash.BorderSizePixel = 0
        flash.Active = false
        flash.Parent = fxGui
        TweenService:Create(flash, TweenInfo.new(FLASH_SECONDS), { BackgroundTransparency = 1 }):Play()
        Debris:AddItem(flash, FLASH_SECONDS + 0.1)
    end

    -- Karte mit Namen, Seltenheit, Status und Set-Fortschritt.
    local bigData = Screen.classData().bigCard
    local viewportWidth = Screen.layout().viewport.width
    local card = makeCard(Vector2.new(math.min(bigData.w, math.max(viewportWidth - 2 * BIG_CARD_SIDE_MARGIN, 200)), bigData.h), color)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.45)
    local scale = Instance.new("UIScale")
    scale.Scale = CARD_POP_START_SCALE
    scale.Parent = card
    label(card, UDim2.new(0, 12, 0, 12), UDim2.new(1, -24, 0, 30), Enum.Font.GothamBold, color, string.upper(rarity.name))
    label(card, UDim2.new(0, 12, 0, 52), UDim2.new(1, -24, 0, 44), Enum.Font.GothamBold, TEXT_COLOR, find.name)
    label(card, UDim2.new(0, 12, 0, 108), UDim2.new(1, -24, 0, 30), Enum.Font.GothamBold, TEXT_COLOR, statusText(payload))
    label(card, UDim2.new(0, 12, 0, 146), UDim2.new(1, -24, 0, 24), Enum.Font.Gotham, MUTED_COLOR, setProgressText(payload))
    label(card, UDim2.new(0, 12, 1, -30), UDim2.new(1, -24, 0, 18), Enum.Font.Gotham, MUTED_COLOR, "Tippen zum Schließen")
    TweenService:Create(scale, TweenInfo.new(CARD_POP_SECONDS, CARD_POP_EASING), { Scale = 1 }):Play()

    pause(CARD_POP_SECONDS + hold)
    TweenService:Create(scale, TweenInfo.new(CARD_LEAVE_SECONDS), { Scale = 0 }):Play()
    task.wait(CARD_LEAVE_SECONDS)
    card:Destroy()
end

local function showBanner(text: string, subText: string?)
    local size, anchor, shown, hidden = smallPlacement()
    local card = makeCard(size, BANNER_COLOR)
    card.AnchorPoint = anchor
    card.Position = hidden
    label(card, UDim2.new(0, 10, 0.1, 0), UDim2.new(1, -20, 0.37, 0), Enum.Font.GothamBold, BANNER_COLOR, text)
    if subText ~= nil then
        label(card, UDim2.new(0, 10, 0.54, 0), UDim2.new(1, -20, 0.33, 0), Enum.Font.GothamBold, TEXT_COLOR, subText)
    end
    playSound("setComplete")
    local slide = TweenInfo.new(SMALL_SLIDE_SECONDS, SMALL_SLIDE_EASING)
    TweenService:Create(card, slide, { Position = shown }):Play()
    pause(SMALL_SLIDE_SECONDS + BANNER_SECONDS)
    TweenService:Create(card, slide, { Position = hidden }):Play()
    task.wait(SMALL_SLIDE_SECONDS)
    card:Destroy()
end

-- Ein Fund aus der Warteschlange: Objekt im Sand, Karte, danach Banner für Set und Zonenbuch.
local function show(payload: any, short: boolean)
    local find = Finds.byId[payload.findId]
    local rarity = Rarities.byId[payload.rarityId]
    if find == nil or rarity == nil then
        return
    end
    local timing = REVEAL[rarity.id] or REVEAL.common
    spawnSandObject(Color3.fromHex(rarity.colorHex))
    playSound(rarity.id)
    if timing.big then
        showBig(payload, find, rarity, short)
    else
        showSmall(payload, find, rarity, short)
    end
    if payload.setCompleted == true then
        local findSet = Finds.setsById[payload.setId]
        local index = if findSet ~= nil then findSet.index else 0
        skip = false
        showBanner(`Set {index} fertig!`, `Sammlungsbonus: +{percentText(payload.bonusBp or 0)} %`)
    end
    if payload.zoneBookCompleted == true then
        local book = CollectionData.zoneBooksByZone[payload.zoneId]
        skip = false
        showBanner("Zonenbuch fertig!", if book ~= nil then `Titel: {book.title}` else nil)
    end
end

local function process()
    if running then
        return
    end
    running = true
    task.spawn(function()
        while #queue > 0 do
            local payload = table.remove(queue, 1)
            skip = false
            local short = #queue >= SHORT_MODE_FROM_QUEUE
            local ok, err = pcall(show, payload, short)
            if not ok then
                warn(`[Reveal] Fehler bei der Anzeige: {tostring(err)}`)
            end
        end
        running = false
    end)
end

-- Läuft ein Fund-Reveal oder wartet einer in der Schlange? Angebots-Hinweise (Paket 4.5) kommen
-- erst danach.
function Reveal.isBusy(): boolean
    return running or #queue > 0
end

function Reveal.Init() end

function Reveal.Start()
    -- Lichtstoß und Blitz decken den ganzen Bildschirm, die Karten liegen auf der sicheren Fläche.
    local fx = Instance.new("ScreenGui")
    fx.Name = "DuneBaronRevealFx"
    fx.ResetOnSpawn = false
    fx.DisplayOrder = 10
    fx.IgnoreGuiInset = true
    fx.Parent = player:WaitForChild("PlayerGui")
    fxGui = fx
    local cards = Instance.new("ScreenGui")
    cards.Name = "DuneBaronReveal"
    cards.ResetOnSpawn = false
    cards.DisplayOrder = 11
    cards.Parent = player:WaitForChild("PlayerGui")
    gui = cards

    State.onNotify(function(payload: any)
        if payload.kind ~= "find" or type(payload.findId) ~= "string" or Finds.byId[payload.findId] == nil then
            return
        end
        if Rarities.byId[payload.rarityId] == nil then
            return
        end
        if #queue >= QUEUE_MAX then
            return
        end
        table.insert(queue, payload)
        process()
    end)
end

return Reveal
