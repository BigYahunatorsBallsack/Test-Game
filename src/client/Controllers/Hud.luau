--!strict
-- Hud-Controller (Paket 1.2, schlichte Fassung bis zum UI-Paket)
-- Zeigt Münzen, Tank (Balken und Zahl) und kurze Meldungen (Verkauft, Tank voll, zu weit).
-- Alle Werte kommen vom Server (State). Zahlen erscheinen über BigNum.format (K, M, B, T ...).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Animationen
local TANK_BAR_TWEEN_SECONDS = 0.15
local TANK_BAR_EASING = Enum.EasingStyle.Quad
local TOAST_FADE_SECONDS = 0.25
local TOAST_VISIBLE_SECONDS = 1.6
local TOAST_EASING = Enum.EasingStyle.Sine

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local TANK_FILL_COLOR = Color3.fromRGB(230, 200, 117)
local TANK_FULL_COLOR = Color3.fromRGB(220, 120, 60)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)

local MESSAGES = {
    tankFull = "Tank voll! Ab zum Händlerstand.",
    tankEmpty = "Der Tank ist leer.",
    sellTooFar = "Zu weit vom Händlerstand entfernt.",
}

local BigNum = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("BigNum") :: ModuleScript) :: any
local Zones = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Zones") :: ModuleScript) :: any
local Tools = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Tools") :: ModuleScript) :: any
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any

local Hud = {}

-- Gespeicherte Zahl {m, e} als Anzeigetext (K, M, B, T, deutsches Komma).
local function display(value: any): string
    return BigNum.format(BigNum.deserialize(value))
end

-- Gewöhnliche Zahl (zum Beispiel die Tank-Kapazität) als Anzeigetext.
local function displayNumber(value: number): string
    return BigNum.format(BigNum.new(value))
end

local function label(parent: Instance, name: string, position: UDim2, size: UDim2): TextLabel
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Position = position
    l.Size = size
    l.Font = Enum.Font.GothamBold
    l.TextColor3 = TEXT_COLOR
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
    panel.BackgroundColor3 = PANEL_COLOR
    panel.BackgroundTransparency = 0.25
    panel.Position = UDim2.new(0, 16, 0, 16)
    panel.Size = UDim2.new(0, 240, 0, 84)
    panel.Parent = gui
    Instance.new("UICorner").Parent = panel

    local coinsLabel = label(panel, "Coins", UDim2.new(0, 12, 0, 6), UDim2.new(1, -24, 0, 30))
    coinsLabel.Text = "Münzen: 0"

    local bar = Instance.new("Frame")
    bar.Name = "TankBar"
    bar.BackgroundColor3 = Color3.new(0, 0, 0)
    bar.BackgroundTransparency = 0.5
    bar.Position = UDim2.new(0, 12, 0, 44)
    bar.Size = UDim2.new(1, -24, 0, 28)
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
    local toolLabel = label(gui, "Tool", UDim2.new(0, 28, 0, 104), UDim2.new(0, 320, 0, 22))
    toolLabel.Text = ""

    local toast = label(gui, "Toast", UDim2.new(0.5, -200, 0.75, 0), UDim2.new(0, 400, 0, 36))
    toast.TextXAlignment = Enum.TextXAlignment.Center
    toast.TextTransparency = 1
    toast.TextStrokeTransparency = 1

    gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

    local barTween = TweenInfo.new(TANK_BAR_TWEEN_SECONDS, TANK_BAR_EASING)
    State.onChanged(function(snapshot: any)
        coinsLabel.Text = `Münzen: {display(snapshot.coins)}`
        local tool = Tools.byId[snapshot.toolId]
        local zone = Zones.byId[snapshot.zoneId]
        local zoneText = if zone ~= nil then `{zone.name} · ` else ""
        toolLabel.Text = if tool ~= nil then `{zoneText}{tool.name} · {displayNumber(snapshot.rate)}/s` else zoneText
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
            showToast(`+{display(payload.earned)} Münzen`)
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
