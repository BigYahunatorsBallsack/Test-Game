--!strict
-- Hud-Controller (Paket 1.2, schlichte Fassung bis zum UI-Paket)
-- Zeigt Münzen, Tank (Balken und Zahl) und kurze Meldungen (Verkauft, Tank voll, zu weit).
-- Alle Werte kommen vom Server (State). Zahlen erscheinen über BigNum.format (K, M, B, T ...).
-- Maße und Plätze kommen aus Data/Screen je Größenklasse (Paket 3.6): am Handy ein kleineres Panel,
-- damit Tutorial-Banner, Menüspalte und Steuerung Platz haben.
-- Überarbeitung Ü4: Beim Verkaufen fliegen Münzen zum Münzzähler (Interface/SaleFeedback).
-- Überarbeitung Ü5: Stil aus Interface/Theme und Kit (Panel mit Verlauf und Kontur, Münz- und
-- Sand-Icon, runde Schrift). Plätze bleiben aus Data/Screen, damit Menüleiste und Tutorial passen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Animationen
local TANK_BAR_TWEEN_SECONDS = 0.15
local TANK_BAR_EASING = Enum.EasingStyle.Quad
local TOAST_FADE_SECONDS = 0.25
local TOAST_VISIBLE_SECONDS = 1.6
local TOAST_EASING = Enum.EasingStyle.Sine
-- Countdown des Münz-Boosts (Paket 4.4): so oft wird die Restzeit neu geschrieben
local BOOST_TICK_SECONDS = 0.5

local Theme = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("Theme") :: ModuleScript) :: any -- Ü5: ein Stil
local UI = Theme.ui

-- Farben aus Interface/Theme (Ü5)
local TANK_FILL_COLOR = UI.accent
local TANK_FULL_COLOR = UI.danger
local PERKS_COLOR = UI.accent -- Zeile "Pässe und Boost"

local MESSAGES = {
    tankFull = "Tank voll! Ab zum Händlerstand.",
    tankEmpty = "Der Tank ist leer.",
    sellTooFar = "Zu weit vom Händlerstand entfernt.",
    cellEmpty = "Hier ist nichts mehr. Ein paar Schritte weiter graben.", -- Überarbeitung Ü2
}

local BigNum = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("BigNum") :: ModuleScript) :: any
local Zones = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Zones") :: ModuleScript) :: any
local Tools = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Tools") :: ModuleScript) :: any
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any
local Kit = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("Kit") :: ModuleScript) :: any
local Icons = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("Icons") :: ModuleScript) :: any
local SaleFeedback = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("SaleFeedback") :: ModuleScript) :: any

local TOAST_HEIGHT = 36

local Hud = {}

-- Gespeicherte Zahl {m, e} als Anzeigetext (K, M, B, T, deutsches Komma).
local function display(value: any): string
    return BigNum.format(BigNum.deserialize(value))
end

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

-- Faktor als Text mit deutschem Komma (2 -> "2", 2.5 -> "2,5").
local function factorText(value: number): string
    local text = if value % 1 == 0 then tostring(math.floor(value)) else string.format("%.1f", value)
    local replaced = string.gsub(text, "%.", ",")
    return replaced
end

-- Gewöhnliche Zahl (zum Beispiel die Tank-Kapazität) als Anzeigetext.
local function displayNumber(value: number): string
    return BigNum.format(BigNum.new(value))
end

-- Hundertstel-Prozent als Text mit deutschem Komma (200 -> "2", 250 -> "2,5").
local function percentText(bp: number): string
    local value = bp / 100
    local text = if value % 1 == 0 then tostring(math.floor(value)) else string.format("%.1f", value)
    local replaced = string.gsub(text, "%.", ",")
    return replaced
end

local function label(parent: Instance, name: string, position: UDim2, size: UDim2): TextLabel
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Position = position
    l.Size = size
    Kit.title(l)
    l.TextScaled = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

function Hud.Init() end

function Hud.Start()
    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronHud"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Parent = gui
    Kit.window(panel)

    -- Münz-Icon links neben der Zahl, Zahl in Gold.
    local coinIcon = Instance.new("ImageLabel")
    coinIcon.Name = "CoinIcon"
    coinIcon.BackgroundTransparency = 1
    coinIcon.ScaleType = Enum.ScaleType.Fit
    coinIcon.Parent = panel
    pcall(Icons.Set, coinIcon, "icon_currency_coin")
    local coinsLabel = label(panel, "Coins", UDim2.new(), UDim2.new())
    coinsLabel.TextColor3 = UI.accent
    coinsLabel.Text = "0"

    local bar = Instance.new("Frame")
    bar.Name = "TankBar"
    bar.BackgroundColor3 = UI.slot
    bar.BackgroundTransparency = 0
    bar.ClipsDescendants = true
    bar.Parent = panel
    Instance.new("UICorner").Parent = bar

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.BackgroundColor3 = TANK_FILL_COLOR
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Parent = bar
    Instance.new("UICorner").Parent = fill

    local tankLabel = label(bar, "Tank", UDim2.new(0, 8, 0, 2), UDim2.new(1, -16, 1, -4))
    tankLabel.TextXAlignment = Enum.TextXAlignment.Center
    tankLabel.Text = "Tank 0 / 0"

    -- Werkzeugname und Rate unter dem Panel (Paket 2.4)
    local toolLabel = label(gui, "Tool", UDim2.new(), UDim2.new())
    toolLabel.Text = ""

    -- Windkristalle (Paket 2.7), nur sichtbar ab dem ersten Kristall
    local windLabel = label(gui, "Wind", UDim2.new(), UDim2.new())
    windLabel.Text = ""

    -- Pässe und Boost (Paket 4.4): Auto-Dig, Münz-Faktor und Restzeit des Boosts, nur wenn etwas wirkt
    local perksLabel = label(gui, "Perks", UDim2.new(), UDim2.new())
    perksLabel.TextColor3 = PERKS_COLOR
    perksLabel.Text = ""

    local toast = label(gui, "Toast", UDim2.new(), UDim2.new())
    toast.AnchorPoint = Vector2.new(0.5, 0)
    toast.TextXAlignment = Enum.TextXAlignment.Center
    toast.TextStrokeColor3 = UI.ink
    local toastOutline = toast:FindFirstChild("LetterOutline")
    if toastOutline ~= nil then
        toastOutline:Destroy() -- die Meldung blendet über TextStroke aus, eine Kontur bliebe stehen
    end
    toast.TextTransparency = 1
    toast.TextStrokeTransparency = 1

    -- Maße und Plätze nach Größenklasse (Data/Screen), neu bei jeder Änderung der Bildschirmgröße.
    local function applyLayout()
        local data = Screen.classData()
        local hud, lines = data.hud, data.lines
        panel.Position = UDim2.fromOffset(hud.x, hud.y)
        panel.Size = UDim2.fromOffset(hud.w, hud.h)
        coinIcon.Position = UDim2.fromOffset(hud.pad, hud.coinsY)
        coinIcon.Size = UDim2.fromOffset(hud.coinsH, hud.coinsH)
        coinsLabel.Position = UDim2.fromOffset(hud.pad + hud.coinsH + 6, hud.coinsY)
        coinsLabel.Size = UDim2.new(1, -2 * hud.pad - hud.coinsH - 6, 0, hud.coinsH)
        bar.Position = UDim2.fromOffset(hud.pad, hud.barY)
        bar.Size = UDim2.new(1, -2 * hud.pad, 0, hud.barH)
        toolLabel.Position = UDim2.fromOffset(hud.x + hud.pad, lines.toolY)
        toolLabel.Size = UDim2.fromOffset(lines.w, lines.h)
        windLabel.Position = UDim2.fromOffset(hud.x + hud.pad, lines.windY)
        windLabel.Size = UDim2.fromOffset(lines.w, lines.h)
        perksLabel.Position = UDim2.fromOffset(hud.x + hud.pad, lines.perksY)
        perksLabel.Size = UDim2.fromOffset(lines.w, lines.h)
        toast.Position = UDim2.new(0.5, 0, data.toast.yScale, 0)
        toast.Size = UDim2.fromOffset(data.toast.w, TOAST_HEIGHT)
    end
    applyLayout()
    Screen.onLayoutChanged(applyLayout)

    gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    -- Ü4: Münzflug beim Verkauf. Fällt er aus, bleibt die kurze Meldung.
    local okSale, saleFeedback = pcall(SaleFeedback.Mount, Players.LocalPlayer:WaitForChild("PlayerGui"))
    if not okSale then
        warn(`[Hud] Münzflug nicht verfügbar: {tostring(saleFeedback)}`)
        saleFeedback = nil
    end

    -- Zeile "Pässe und Boost". Die Restzeit kommt vom Server (seine Uhr), der Client zählt nur von
    -- dort lokal herunter, bis der nächste Snapshot kommt.
    local perks = { autoDig = false, multiplier = 1, boostEndsAt = 0, luckEndsAt = 0 }
    local function renderPerks()
        local parts: { string } = {}
        if perks.autoDig then
            table.insert(parts, "Auto-Dig")
        end
        if perks.multiplier > 1 then
            table.insert(parts, `Münzen x{factorText(perks.multiplier)}`)
        end
        local left = perks.boostEndsAt - os.clock()
        if left > 0 then
            table.insert(parts, `Boost {clockText(left)}`)
        end
        local luckLeft = perks.luckEndsAt - os.clock()
        if luckLeft > 0 then
            table.insert(parts, `Glück x2 {clockText(luckLeft)}`)
        end
        perksLabel.Text = table.concat(parts, " · ")
    end
    task.spawn(function()
        while true do
            task.wait(BOOST_TICK_SECONDS)
            if perks.boostEndsAt > 0 or perks.luckEndsAt > 0 then
                renderPerks()
                if perks.boostEndsAt <= os.clock() then
                    perks.boostEndsAt = 0
                end
                if perks.luckEndsAt <= os.clock() then
                    perks.luckEndsAt = 0
                end
            end
        end
    end)

    local barTween = TweenInfo.new(TANK_BAR_TWEEN_SECONDS, TANK_BAR_EASING)
    State.onChanged(function(snapshot: any)
        perks.autoDig = snapshot.autoDigOwned == true and snapshot.autoDig == true
        perks.multiplier = if type(snapshot.coinMultiplier) == "number" and snapshot.coinMultiplier == snapshot.coinMultiplier then snapshot.coinMultiplier else 1
        local boostSeconds = if type(snapshot.coinBoostSeconds) == "number" and snapshot.coinBoostSeconds == snapshot.coinBoostSeconds then snapshot.coinBoostSeconds else 0
        perks.boostEndsAt = if boostSeconds > 0 then os.clock() + boostSeconds else 0
        local luckSeconds = if type(snapshot.luckBoostSeconds) == "number" and snapshot.luckBoostSeconds == snapshot.luckBoostSeconds then snapshot.luckBoostSeconds else 0
        perks.luckEndsAt = if luckSeconds > 0 then os.clock() + luckSeconds else 0
        renderPerks()
        coinsLabel.Text = display(snapshot.coins)
        local tool = Tools.byId[snapshot.toolId]
        local zone = Zones.byId[snapshot.zoneId]
        local zoneText = if zone ~= nil then `{zone.name} · ` else ""
        toolLabel.Text = if tool ~= nil then `{zoneText}{tool.name} · {displayNumber(snapshot.rate)}/s` else zoneText
        windLabel.Text = if type(snapshot.windCrystals) == "number" and snapshot.windCrystals > 0 then `Windkristalle: {displayNumber(snapshot.windCrystals)} · +{percentText(snapshot.windBonusBp)} %` else ""
        local tank = BigNum.toNumber(BigNum.deserialize(snapshot.tank))
        local capacity = math.max(snapshot.capacity, 1)
        local ratio = math.clamp(tank / capacity, 0, 1)
        tankLabel.Text = `Tank {display(snapshot.tank)} / {displayNumber(snapshot.capacity)}`
        fill.BackgroundColor3 = if ratio >= 1 then TANK_FULL_COLOR else TANK_FILL_COLOR
        TweenService:Create(fill, barTween, { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
    end)

    local toastToken = 0
    local fadeTween = TweenInfo.new(TOAST_FADE_SECONDS, TOAST_EASING)
    local function showToast(text: string)
        toastToken += 1
        local token = toastToken
        toast.Text = text
        TweenService:Create(toast, fadeTween, { TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
        task.delay(TOAST_VISIBLE_SECONDS, function()
            if token == toastToken then
                TweenService:Create(toast, fadeTween, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
            end
        end)
    end

    State.onNotify(function(payload: any)
        if payload.kind == "sold" and type(payload.earned) == "table" then
            if saleFeedback ~= nil then
                saleFeedback.Show(display(payload.earned), coinsLabel)
            else
                showToast(`+{display(payload.earned)} Münzen`)
            end
        elseif payload.kind == "zoneUnlocked" and Zones.byId[payload.zoneId] ~= nil then
            showToast(`Neue Zone: {Zones.byId[payload.zoneId].name}`)
        elseif payload.kind == "zoneEntered" and Zones.byId[payload.zoneId] ~= nil then
            showToast(Zones.byId[payload.zoneId].name)
        elseif payload.kind == "zoneLocked" and Zones.byId[payload.zoneId] ~= nil then
            showToast(`{Zones.byId[payload.zoneId].name} ist noch gesperrt.`)
        elseif type(payload.kind) == "string" and MESSAGES[payload.kind] ~= nil then
            showToast(MESSAGES[payload.kind])
        end
    end)
end

return Hud
