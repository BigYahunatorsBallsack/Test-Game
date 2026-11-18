--!strict
-- Sandstorm-Controller (Paket 2.7)
-- Knopf "Sandsturm" unten links (neben "Sammlung"), sichtbar sobald der Knoten für den Canyon
-- gekauft ist (der Server meldet das in `storm.unlocked`). Der Knopf öffnet ein Fenster mit der
-- Vorschau (Kristalle jetzt, Bonus davor und danach) und der Liste "wird zurückgesetzt" und "bleibt".
-- "Sturm auslösen" fragt einmal nach (zweiter Tipp innerhalb von CONFIRM_SECONDS), dann schickt der
-- Client `Prestige` ohne Werte. Alle Zahlen kommen vom Server, der Client rechnet nichts Maßgebliches.
-- Nach dem Sturm (Notify kind = "sandstorm") zieht eine Sandwand über den Bildschirm, danach kommt
-- ein Banner mit den neuen Kristallen. Sounds: leere IDs bis Paket 3.5.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

-- Knopf und Fenster
local BUTTON_POSITION = UDim2.new(0, 292, 1, -72)
local BUTTON_SIZE = UDim2.new(0, 150, 0, 48)
local PANEL_SCALE = Vector2.new(0.92, 0.8)
local PANEL_MAX_SIZE = Vector2.new(480, 440)
local PANEL_FADE_SECONDS = 0.18
local PANEL_EASING = Enum.EasingStyle.Quad
local CONFIRM_SECONDS = 4 -- so lange gilt der zweite Tipp als Bestätigung
local MESSAGE_SECONDS = 3
local READY_PULSE_SECONDS = 0.8 -- der Knopf pulsiert, wenn der Sturm Kristalle bringt
local READY_PULSE_TRANSPARENCY = 0.05

-- Sturm-Animation: Wand von links, Halten, Wand nach rechts
local WALL_IN_SECONDS = 0.9
local WALL_HOLD_SECONDS = 0.5
local WALL_OUT_SECONDS = 1.1
local WALL_EASING = Enum.EasingStyle.Sine
local WALL_TRANSPARENCY = 0.08
local BANNER_SECONDS = 3.2
local BANNER_FADE_SECONDS = 0.3

-- Sounds (Paket 3.5). Leer = kein Ton.
local SOUND_IDS = { storm = "" }

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local ROW_COLOR = Color3.fromRGB(64, 52, 40)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local GOOD_COLOR = Color3.fromRGB(150, 220, 120)
local WARN_COLOR = Color3.fromRGB(235, 150, 90)
local BUTTON_COLOR = Color3.fromRGB(80, 66, 52)
local READY_COLOR = Color3.fromRGB(230, 200, 117)
local WALL_COLOR = Color3.fromRGB(214, 178, 112)

local REASONS: { [string]: string } = {
    requires = "Der Sandsturm ist noch nicht möglich.",
    tooFew = "Der Sturm lohnt sich noch nicht: im Lauf fehlt noch Verdienst.",
    unknown = "Das geht gerade nicht.",
}

local RESET_TEXT = "Wird zurückgesetzt: Münzen, Tank, Werkzeug, alle Upgrades und alle Zonen außer dem Dünenmeer."
local KEEP_TEXT = "Bleibt: Sammlung und Skins, Gems, Windkristalle, Tutorial."

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local BigNum = loadShared("Logic", "BigNum")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any

local Sandstorm = {}

local player = Players.LocalPlayer

local function percentText(bp: number): string
    local value = bp / 100
    local text = if value % 1 == 0 then tostring(math.floor(value)) else string.format("%.1f", value)
    local replaced = string.gsub(text, "%.", ",")
    return replaced
end

local function numberText(value: number): string
    return BigNum.format(BigNum.new(value))
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

function Sandstorm.Init() end

function Sandstorm.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local prestige = remotes:WaitForChild("Prestige") :: RemoteFunction

    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronSandstorm"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 8
    gui.IgnoreGuiInset = true

    local openButton = Instance.new("TextButton")
    openButton.Name = "StormButton"
    openButton.Position = BUTTON_POSITION
    openButton.Size = BUTTON_SIZE
    openButton.BackgroundColor3 = BUTTON_COLOR
    openButton.BackgroundTransparency = 0.25
    openButton.Font = Enum.Font.GothamBold
    openButton.TextColor3 = TEXT_COLOR
    openButton.TextScaled = true
    openButton.Text = "Sandsturm"
    openButton.Visible = false -- erst ab dem Knoten für den Canyon
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

    newText(panel, "Title", UDim2.new(0, 16, 0, 10), UDim2.new(1, -72, 0, 32), Enum.Font.GothamBold, TEXT_COLOR, "Sandsturm")
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

    -- Vorschau
    local previewBox = Instance.new("Frame")
    previewBox.Name = "Preview"
    previewBox.Position = UDim2.new(0, 12, 0, 52)
    previewBox.Size = UDim2.new(1, -24, 0, 132)
    previewBox.BackgroundColor3 = ROW_COLOR
    previewBox.BackgroundTransparency = 0.2
    previewBox.Parent = panel
    Instance.new("UICorner").Parent = previewBox
    local gainLabel = newText(previewBox, "Gain", UDim2.new(0, 12, 0, 8), UDim2.new(1, -24, 0, 36), Enum.Font.GothamBold, GOOD_COLOR, "")
    local bonusLabel = newText(previewBox, "Bonus", UDim2.new(0, 12, 0, 50), UDim2.new(1, -24, 0, 26), Enum.Font.GothamBold, TEXT_COLOR, "")
    local earnedLabel = newText(previewBox, "Earned", UDim2.new(0, 12, 0, 80), UDim2.new(1, -24, 0, 22), Enum.Font.Gotham, MUTED_COLOR, "")
    local stormsLabel = newText(previewBox, "Storms", UDim2.new(0, 12, 0, 104), UDim2.new(1, -24, 0, 20), Enum.Font.Gotham, MUTED_COLOR, "")

    local resetLabel = newText(panel, "Reset", UDim2.new(0, 16, 0, 196), UDim2.new(1, -32, 0, 44), Enum.Font.Gotham, WARN_COLOR, RESET_TEXT)
    local keepLabel = newText(panel, "Keep", UDim2.new(0, 16, 0, 246), UDim2.new(1, -32, 0, 30), Enum.Font.Gotham, GOOD_COLOR, KEEP_TEXT)
    local messageLabel = newText(panel, "Message", UDim2.new(0, 16, 1, -104), UDim2.new(1, -32, 0, 24), Enum.Font.GothamBold, WARN_COLOR, "")
    resetLabel.TextXAlignment = Enum.TextXAlignment.Left

    local goButton = Instance.new("TextButton")
    goButton.Name = "Go"
    goButton.AnchorPoint = Vector2.new(0.5, 1)
    goButton.Position = UDim2.new(0.5, 0, 1, -16)
    goButton.Size = UDim2.new(1, -32, 0, 56)
    goButton.BackgroundColor3 = READY_COLOR
    goButton.Font = Enum.Font.GothamBold
    goButton.TextColor3 = PANEL_COLOR
    goButton.TextScaled = true
    goButton.Text = "Sturm auslösen"
    goButton.Parent = panel
    Instance.new("UICorner").Parent = goButton

    -- Sturm-Animation und Banner (liegen über allem)
    local wall = Instance.new("Frame")
    wall.Name = "Wall"
    wall.Size = UDim2.fromScale(1, 1)
    wall.Position = UDim2.fromScale(-1, 0)
    wall.BackgroundColor3 = WALL_COLOR
    wall.BackgroundTransparency = WALL_TRANSPARENCY
    wall.BorderSizePixel = 0
    wall.Visible = false
    wall.ZIndex = 20
    wall.Parent = gui

    local banner = newText(gui, "Banner", UDim2.new(0.5, -260, 0.32, 0), UDim2.new(0, 520, 0, 90), Enum.Font.GothamBold, TEXT_COLOR, "")
    banner.TextXAlignment = Enum.TextXAlignment.Center
    banner.TextTransparency = 1
    banner.TextStrokeTransparency = 1
    banner.ZIndex = 21

    local confirmToken = 0
    local confirming = false
    local busy = false
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

    local function resetConfirm()
        confirmToken += 1
        confirming = false
        goButton.Text = "Sturm auslösen"
    end

    local function refresh()
        local snapshot = State.get()
        local storm = if snapshot ~= nil then snapshot.storm else nil
        if storm == nil then
            openButton.Visible = false
            return
        end
        openButton.Visible = storm.unlocked == true
        openButton.Text = if storm.ready then `Sandsturm +{numberText(storm.gain)}` else "Sandsturm"
        if storm.ready then
            gainLabel.Text = `Du bekommst {numberText(storm.gain)} Windkristalle`
        elseif storm.reason == "tooFew" then
            -- Der Knopf ist schon da, der Sturm lohnt sich aber erst ab `minCrystals` Kristallen.
            gainLabel.Text = `Noch zu früh: ab {BigNum.format(BigNum.deserialize(storm.needed))} verdienten Münzen gibt es {storm.minCrystals} Kristalle.`
        else
            gainLabel.Text = REASONS[storm.reason or "unknown"] or REASONS.unknown
        end
        gainLabel.TextColor3 = if storm.ready then GOOD_COLOR else WARN_COLOR
        bonusLabel.Text = `Bonus auf alle Münzen: +{percentText(storm.bonusBpNow)} % → +{percentText(storm.bonusBpAfter)} %`
        earnedLabel.Text = `Verdient in diesem Lauf: {BigNum.format(BigNum.deserialize(storm.runEarned))}`
        stormsLabel.Text = if storm.first then "Dein erster Sandsturm." else `Bisherige Stürme: {storm.prestiges}`
        goButton.BackgroundColor3 = if storm.ready then READY_COLOR else BUTTON_COLOR
        goButton.AutoButtonColor = storm.ready
        if not storm.ready then
            resetConfirm()
        end
    end

    local fade = TweenInfo.new(PANEL_FADE_SECONDS, PANEL_EASING)
    local function setOpen(open: boolean)
        panel.Visible = open
        resetConfirm()
        messageLabel.Text = ""
        if open then
            panel.BackgroundTransparency = 1
            TweenService:Create(panel, fade, { BackgroundTransparency = 0.1 }):Play()
            refresh()
        end
    end
    openButton.Activated:Connect(function()
        setOpen(not panel.Visible)
    end)
    closeButton.Activated:Connect(function()
        setOpen(false)
    end)

    goButton.Activated:Connect(function()
        local snapshot = State.get()
        local storm = if snapshot ~= nil then snapshot.storm else nil
        if busy or storm == nil or storm.ready ~= true then
            if storm ~= nil and storm.reason ~= nil then
                showMessage(REASONS[storm.reason] or REASONS.unknown)
            end
            return
        end
        if not confirming then
            confirming = true
            confirmToken += 1
            local token = confirmToken
            goButton.Text = "Wirklich? Noch einmal tippen"
            task.delay(CONFIRM_SECONDS, function()
                if token == confirmToken then
                    resetConfirm()
                end
            end)
            return
        end
        resetConfirm()
        busy = true
        local ok, result = pcall(function(): any
            return prestige:InvokeServer()
        end)
        busy = false
        if not ok or type(result) ~= "table" then
            showMessage(REASONS.unknown)
        elseif result.ok ~= true then
            showMessage(REASONS[result.reason] or REASONS.unknown)
        end
        -- Bei Erfolg kommt die Animation über die Meldung "sandstorm".
    end)

    -- Animation: Wand von links, Halten, Wand nach rechts, dazu das Banner.
    local playing = false
    local function playStorm(payload: any)
        if playing then
            return
        end
        playing = true
        setOpen(false)
        playSound("storm")
        wall.Position = UDim2.fromScale(-1, 0)
        wall.Visible = true
        local wallIn = TweenService:Create(wall, TweenInfo.new(WALL_IN_SECONDS, WALL_EASING, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) })
        wallIn:Play()
        wallIn.Completed:Wait()
        task.wait(WALL_HOLD_SECONDS) -- unter der Wand setzt der Server den Charakter zurück
        local wallOut = TweenService:Create(wall, TweenInfo.new(WALL_OUT_SECONDS, WALL_EASING, Enum.EasingDirection.In), { Position = UDim2.fromScale(1, 0) })
        wallOut:Play()
        banner.Text = `+{numberText(payload.crystals)} Windkristalle · Bonus +{percentText(payload.bonusBp)} %`
        if payload.first == true then
            banner.Text ..= "\nDie Ruinenkarte öffnet die Ruinenstadt."
        end
        TweenService:Create(banner, TweenInfo.new(BANNER_FADE_SECONDS), { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
        wallOut.Completed:Wait()
        wall.Visible = false
        task.delay(BANNER_SECONDS, function()
            TweenService:Create(banner, TweenInfo.new(BANNER_FADE_SECONDS), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
        end)
        playing = false
    end

    State.onNotify(function(payload: any)
        if payload.kind ~= "sandstorm" or type(payload.crystals) ~= "number" or type(payload.bonusBp) ~= "number" then
            return
        end
        task.spawn(playStorm, payload)
    end)

    -- Der Knopf pulsiert, solange der Sturm Kristalle bringt.
    task.spawn(function()
        local pulseInfo = TweenInfo.new(READY_PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        while true do
            local snapshot = State.get()
            local ready = snapshot ~= nil and snapshot.storm ~= nil and snapshot.storm.ready == true
            if ready and openButton.Visible then
                openButton.BackgroundColor3 = READY_COLOR
                TweenService:Create(openButton, pulseInfo, { BackgroundTransparency = READY_PULSE_TRANSPARENCY }):Play()
                task.wait(READY_PULSE_SECONDS)
                TweenService:Create(openButton, pulseInfo, { BackgroundTransparency = 0.25 }):Play()
                task.wait(READY_PULSE_SECONDS)
            else
                openButton.BackgroundColor3 = BUTTON_COLOR
                openButton.BackgroundTransparency = 0.25
                task.wait(READY_PULSE_SECONDS)
            end
        end
    end)

    gui.Parent = player:WaitForChild("PlayerGui")
    State.onChanged(function()
        refresh()
    end)
end

return Sandstorm
