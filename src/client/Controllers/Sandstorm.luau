--!strict
-- Sandstorm-Controller (Paket 2.7, Handy-Durchgang 3.6)
-- Knopf "Sandsturm" in der Menüleiste (Controllers/Screen), sichtbar sobald der Knoten für den Canyon
-- gekauft ist (der Server meldet das in `storm.unlocked`). Der Knopf öffnet ein Fenster mit der
-- Vorschau (Kristalle jetzt, Bonus davor und danach) und der Liste "wird zurückgesetzt" und "bleibt".
-- "Sturm auslösen" fragt einmal nach (zweiter Tipp innerhalb von CONFIRM_SECONDS), dann schickt der
-- Client `Prestige` ohne Werte. Das Fenster scrollt, der Knopf "Sturm auslösen" und die Meldung
-- stehen in einem festen Fuß und verdecken so keinen Text. Alle Zahlen kommen vom Server, der Client rechnet nichts Maßgebliches.
-- Nach dem Sturm (Notify kind = "sandstorm") zieht eine Sandwand über den Bildschirm, danach kommt
-- ein Banner mit den neuen Kristallen. Sounds: leere IDs bis Paket 3.5.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

-- Knopf und Fenster
local MENU_ORDER = 3 -- Platz in der Menüleiste (nach Zonen und Sammlung)
local FOOTER_HEIGHT = 82
local GO_BUTTON_HEIGHT = 48
local BOX_PADDING = 12
local TEXT_SIZE_BIG = 18
local TEXT_SIZE_NORMAL = 16
local TEXT_SIZE_SMALL = 14
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
local BANNER_MARGIN = 24 -- Abstand des Banners zum Bildrand bei schmalem Bildschirm
local BANNER_SECONDS = 3.2
local BANNER_FADE_SECONDS = 0.3

-- Sounds (Paket 3.5). Leer = kein Ton.
local SOUND_IDS = { storm = "" }

local Theme = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("Theme") :: ModuleScript) :: any -- Ü5: ein Stil
local UI = Theme.ui
local SandstormResultUi = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("SandstormResult") :: ModuleScript) :: any
local Kit = require(script.Parent.Parent:WaitForChild("Interface"):WaitForChild("Kit") :: ModuleScript) :: any

-- Farben aus Interface/Theme (Ü5)
local PANEL_COLOR = UI.panel
local ROW_COLOR = UI.row
local TEXT_COLOR = UI.text
local MUTED_COLOR = UI.muted
local GOOD_COLOR = UI.good
local WARN_COLOR = UI.warn
local BUTTON_COLOR = UI.button
local READY_COLOR = UI.accent
local WALL_COLOR = UI.accent

local REASONS: { [string]: string } = {
    requires = "Der Sandsturm ist noch nicht möglich.",
    tooFew = "Der Sturm lohnt sich noch nicht: im Lauf fehlt noch Verdienst.",
    maxReached = "Maximum an Windkristallen erreicht: ein weiterer Sturm brächte nichts.",
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
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

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

-- Textzeile mit fester Schriftgröße, die in der Breite umbricht und in der Höhe mitwächst.
local function autoText(parent: Instance, name: string, order: number, font: Enum.Font, textSize: number, color: Color3, text: string): TextLabel
    local l = Instance.new("TextLabel")
    l.Name = name
    l.LayoutOrder = order
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1, 0, 0, 0)
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.Font = font
    l.TextSize = textSize
    l.TextColor3 = color
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
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

    -- Ebene für Sandwand und Banner (ganzer Bildschirm). Knopf und Fenster gehören Controllers/Screen.
    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronSandstorm"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 8
    gui.IgnoreGuiInset = true

    local controls = Screen.controls()
    local resetConfirm: () -> () = function() end
    local refresh: () -> () = function() end
    local messageLabel = newText(gui, "Message", UDim2.new(0, 16, 0, 2), UDim2.new(1, -32, 0, 22), Theme.font.bold, WARN_COLOR, "")
    local window = Screen.createWindow({
        name = "SandstormWindow",
        title = "Sandsturm",
        footerHeight = FOOTER_HEIGHT,
        onOpen = function()
            resetConfirm()
            messageLabel.Text = ""
            refresh()
        end,
        onClose = function()
            resetConfirm()
            messageLabel.Text = ""
        end,
    })
    local openButton = Screen.addMenuButton("StormButton", "Sandsturm", MENU_ORDER)
    openButton.BackgroundColor3 = BUTTON_COLOR
    openButton.Visible = false -- erst ab dem Knoten für den Canyon
    messageLabel.Parent = window.footer
    messageLabel.TextSize = TEXT_SIZE_NORMAL
    messageLabel.TextScaled = false

    -- Vorschau (scrollt mit dem Fenster)
    local previewBox = Instance.new("Frame")
    previewBox.Name = "Preview"
    previewBox.LayoutOrder = 1
    previewBox.Size = UDim2.new(1, 0, 0, 0)
    previewBox.AutomaticSize = Enum.AutomaticSize.Y
    previewBox.BackgroundColor3 = ROW_COLOR
    previewBox.BackgroundTransparency = 0.2
    previewBox.Parent = window.body
    Instance.new("UICorner").Parent = previewBox
    local previewPadding = Instance.new("UIPadding")
    previewPadding.PaddingTop = UDim.new(0, BOX_PADDING)
    previewPadding.PaddingBottom = UDim.new(0, BOX_PADDING)
    previewPadding.PaddingLeft = UDim.new(0, BOX_PADDING)
    previewPadding.PaddingRight = UDim.new(0, BOX_PADDING)
    previewPadding.Parent = previewBox
    local previewList = Instance.new("UIListLayout")
    previewList.SortOrder = Enum.SortOrder.LayoutOrder
    previewList.Padding = UDim.new(0, 6)
    previewList.Parent = previewBox
    local gainLabel = autoText(previewBox, "Gain", 1, Theme.font.bold, TEXT_SIZE_BIG, GOOD_COLOR, "")
    local bonusLabel = autoText(previewBox, "Bonus", 2, Theme.font.bold, TEXT_SIZE_NORMAL, TEXT_COLOR, "")
    local earnedLabel = autoText(previewBox, "Earned", 3, Theme.font.body, TEXT_SIZE_SMALL, MUTED_COLOR, "")
    local stormsLabel = autoText(previewBox, "Storms", 4, Theme.font.body, TEXT_SIZE_SMALL, MUTED_COLOR, "")

    autoText(window.body, "Reset", 2, Theme.font.body, TEXT_SIZE_NORMAL, WARN_COLOR, RESET_TEXT)
    autoText(window.body, "Keep", 3, Theme.font.body, TEXT_SIZE_NORMAL, GOOD_COLOR, KEEP_TEXT)

    local goButton = Instance.new("TextButton")

    Kit.flat(goButton)
    goButton.Name = "Go"
    goButton.AnchorPoint = Vector2.new(0.5, 1)
    goButton.Position = UDim2.new(0.5, 0, 1, -8)
    goButton.Size = UDim2.new(1, -32, 0, math.max(GO_BUTTON_HEIGHT, controls.rowButtonH))
    goButton.BackgroundColor3 = READY_COLOR
    goButton.Font = Theme.font.bold
    goButton.TextColor3 = PANEL_COLOR
    goButton.TextScaled = true
    goButton.Text = "Sturm auslösen"
    goButton.Parent = window.footer
    Instance.new("UICorner").Parent = goButton
    local goPadding = Instance.new("UIPadding")
    goPadding.PaddingTop = UDim.new(0, 8)
    goPadding.PaddingBottom = UDim.new(0, 8)
    goPadding.Parent = goButton

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

    local banner = newText(gui, "Banner", UDim2.fromScale(0.5, 0.32), UDim2.fromOffset(520, 90), Theme.font.bold, TEXT_COLOR, "")
    banner.AnchorPoint = Vector2.new(0.5, 0)
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

    resetConfirm = function()
        confirmToken += 1
        confirming = false
        goButton.Text = "Sturm auslösen"
    end

    refresh = function()
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
            if storm.worth == true then
                -- L2: Der nächste Knoten ist weit weg, ein neuer Lauf lohnt mehr als Weitersammeln.
                gainLabel.Text ..= "\nJetzt lohnt sich ein Sturm."
            end
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

    local function setOpen(open: boolean)
        if open then
            window.open()
        else
            window.close()
        end
    end
    openButton.Activated:Connect(window.toggle)

    local playStorm: (any) -> () -- unten definiert, der Knopf braucht sie schon

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
        elseif type(result.crystals) == "number" and type(result.bonusBp) == "number" then
            -- Die Animation startet hier oder über die Meldung "sandstorm", je nachdem, was zuerst
            -- kommt (`playing` verhindert, dass sie doppelt läuft).
            task.spawn(playStorm, result)
        end
    end)

    -- Animation: Wand von links, Halten, Wand nach rechts, dazu das Banner.
    local playing = false
    local okResult, mountedResult = pcall(SandstormResultUi.Mount, player:WaitForChild("PlayerGui"))
    local stormResult: any = if okResult then mountedResult else nil
    if not okResult then
        warn(`[Sandstorm] Ergebniskarte nicht verfügbar: {tostring(mountedResult)}`)
    end
    playStorm = function(payload: any)
        if playing then
            return
        end
        playing = true
        setOpen(false)
        -- Das Banner ist am schmalen Bildschirm schmaler als der Standard.
        local bannerData = Screen.classData().stormBanner
        banner.Size = UDim2.fromOffset(math.min(bannerData.w, Screen.layout().viewport.width - BANNER_MARGIN), bannerData.h)
        playSound("storm")
        wall.Position = UDim2.fromScale(-1, 0)
        wall.Visible = true
        local wallIn = TweenService:Create(wall, TweenInfo.new(WALL_IN_SECONDS, WALL_EASING, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) })
        wallIn:Play()
        wallIn.Completed:Wait()
        task.wait(WALL_HOLD_SECONDS) -- unter der Wand setzt der Server den Charakter zurück
        local wallOut = TweenService:Create(wall, TweenInfo.new(WALL_OUT_SECONDS, WALL_EASING, Enum.EasingDirection.In), { Position = UDim2.fromScale(1, 0) })
        wallOut:Play()
        -- Ü5: Ergebniskarte im Stil aus Interface/SandstormResult; ohne sie das alte Banner.
        local shown = stormResult ~= nil and pcall(stormResult.Show, {
            windCrystals = numberText(payload.crystals),
            unit = `Windkristalle · Bonus +{percentText(payload.bonusBp)} %`,
            ruinsUnlocked = payload.first == true,
        })
        if not shown then
            banner.Text = `+{numberText(payload.crystals)} Windkristalle · Bonus +{percentText(payload.bonusBp)} %`
            if payload.first == true then
                banner.Text ..= "\nDie Ruinenkarte öffnet die Ruinenstadt."
            end
            TweenService:Create(banner, TweenInfo.new(BANNER_FADE_SECONDS), { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
            task.delay(BANNER_SECONDS + WALL_OUT_SECONDS, function()
                TweenService:Create(banner, TweenInfo.new(BANNER_FADE_SECONDS), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
            end)
        end
        wallOut.Completed:Wait()
        wall.Visible = false
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
