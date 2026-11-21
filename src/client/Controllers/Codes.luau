--!strict
-- Codes-Controller (Paket 5.2)
-- Knopf "Code" in der Menüleiste und ein kleines Fenster: Textfeld, "Einlösen" und eine Meldungszeile.
-- Der Client prüft nichts selbst: Er schneidet den Text auf die Länge aus dem Schema und schickt ihn
-- (Remote RedeemCode). Ob der Code gilt, was er gibt und ob der Spieler gesperrt ist, entscheidet der
-- Server. Die Codes selbst stehen nur auf dem Server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Menüleiste und Fenster
local MENU_ORDER = 8 -- nach Zonen, Sammlung, Sandsturm, Kisten, Gems, Ausrüstung und Täglich
local WINDOW_FOOTER_HEIGHT = 0
local INPUT_HEIGHT = 48
local BUTTON_HEIGHT = 48
local MESSAGE_HEIGHT = 56
local MESSAGE_SECONDS = 6
local REDEEM_COOLDOWN_SECONDS = 3.2 -- etwas länger als das Server-Limit (1 Aufruf je 3 s)

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local ROW_COLOR = Color3.fromRGB(64, 52, 40)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local OK_COLOR = Color3.fromRGB(150, 210, 120)
local WARN_COLOR = Color3.fromRGB(235, 150, 90)
local BUTTON_COLOR = Color3.fromRGB(110, 150, 70)

local REASONS: { [string]: string } = {
    invalid = "Der Code ist ungültig oder abgelaufen.",
    alreadyRedeemed = "Diesen Code hast du schon eingelöst.",
    busy = "Einen Moment, bitte gleich noch einmal versuchen.",
    noProfile = "Dein Spielstand wird noch geladen.",
    error = "Das hat nicht geklappt. Bitte versuche es gleich noch einmal.",
    unknown = "Das hat nicht geklappt. Bitte versuche es gleich noch einmal.",
}

local CodesLogic = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("Codes") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

local Codes = {}

local player = Players.LocalPlayer

local function minutesText(seconds: number): string
    return `{math.max(math.floor(seconds / 60 + 0.5), 1)} Minuten`
end

local function rewardText(reward: any): string
    local kind = if type(reward) == "table" then reward.kind else nil
    if kind == "gems" and type(reward.amount) == "number" then
        return `+{math.floor(reward.amount)} Gems`
    elseif kind == "coinBoost" and type(reward.seconds) == "number" then
        return `2x Münzen, {minutesText(reward.seconds)}`
    elseif kind == "luck" and type(reward.seconds) == "number" then
        return `Glücks-Boost x2, {minutesText(reward.seconds)}`
    end
    return "Belohnung erhalten"
end

function Codes.Init() end

function Codes.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local redeemCode = remotes:WaitForChild("RedeemCode") :: RemoteFunction

    local window = Screen.createWindow({
        name = "CodeWindow",
        title = "Code einlösen",
        kind = "narrow",
        footerHeight = WINDOW_FOOTER_HEIGHT,
    })
    local openButton = Screen.addMenuButton("CodeButton", "Code", MENU_ORDER)
    openButton.Activated:Connect(window.toggle)

    local body = window.body

    local hint = Instance.new("TextLabel")
    hint.Name = "Hint"
    hint.LayoutOrder = 1
    hint.BackgroundTransparency = 1
    hint.Size = UDim2.new(1, 0, 0, 40)
    hint.Font = Enum.Font.Gotham
    hint.TextColor3 = MUTED_COLOR
    hint.TextScaled = true
    hint.TextWrapped = true
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.Text = "Gib einen Code ein. Jeder Code geht einmal je Spieler."
    hint.Parent = body

    local input = Instance.new("TextBox")
    input.Name = "Input"
    input.LayoutOrder = 2
    input.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
    input.BackgroundColor3 = ROW_COLOR
    input.Font = Enum.Font.GothamBold
    input.TextColor3 = TEXT_COLOR
    input.PlaceholderText = "CODE"
    input.PlaceholderColor3 = MUTED_COLOR
    input.TextScaled = true
    input.ClearTextOnFocus = false
    input.Text = ""
    input.Parent = body
    Instance.new("UICorner").Parent = input

    local redeemButton = Instance.new("TextButton")
    redeemButton.Name = "Redeem"
    redeemButton.LayoutOrder = 3
    redeemButton.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
    redeemButton.BackgroundColor3 = BUTTON_COLOR
    redeemButton.Font = Enum.Font.GothamBold
    redeemButton.TextColor3 = TEXT_COLOR
    redeemButton.TextScaled = true
    redeemButton.Text = "Einlösen"
    redeemButton.Parent = body
    Instance.new("UICorner").Parent = redeemButton

    local message = Instance.new("TextLabel")
    message.Name = "Message"
    message.LayoutOrder = 4
    message.BackgroundTransparency = 1
    message.Size = UDim2.new(1, 0, 0, MESSAGE_HEIGHT)
    message.Font = Enum.Font.GothamBold
    message.TextColor3 = WARN_COLOR
    message.TextScaled = true
    message.TextWrapped = true
    message.TextXAlignment = Enum.TextXAlignment.Left
    message.Text = ""
    message.Parent = body

    local messageToken = 0
    local function showMessage(text: string, color: Color3)
        messageToken += 1
        local token = messageToken
        message.Text = text
        message.TextColor3 = color
        task.delay(MESSAGE_SECONDS, function()
            if token == messageToken then
                message.Text = ""
            end
        end)
    end

    -- Auf die Länge des Schemas schneiden, damit die Remote den Aufruf nicht verwirft.
    input:GetPropertyChangedSignal("Text"):Connect(function()
        if #input.Text > CodesLogic.MAX_LENGTH * 2 then
            input.Text = string.sub(input.Text, 1, CodesLogic.MAX_LENGTH * 2)
        end
    end)

    local busy = false
    local lastAt = -math.huge
    local function submit()
        if busy or os.clock() - lastAt < REDEEM_COOLDOWN_SECONDS then
            showMessage(REASONS.busy, WARN_COLOR)
            return
        end
        -- Rand abschneiden und das öffentliche Format prüfen: ein Tippfehler im Format kostet so keinen
        -- Fehlversuch auf dem Server.
        local text = CodesLogic.normalize(string.match(input.Text, "^%s*(.-)%s*$"))
        if input.Text == "" then
            return
        end
        if text == nil then
            showMessage(REASONS.invalid, WARN_COLOR)
            return
        end
        busy = true
        lastAt = os.clock()
        local ok, reply = pcall(function(): any
            return redeemCode:InvokeServer(text)
        end)
        busy = false
        if not ok or type(reply) ~= "table" then
            showMessage(REASONS.busy, WARN_COLOR) -- nil: Limit des Servers, kurz warten
            return
        end
        if reply.ok == true then
            input.Text = ""
            local capped = type(reply.reward) == "table" and reply.reward.capped == true
            showMessage(if capped then "Eingelöst. Dein Gem-Konto ist voll, es gab keine Gems mehr." else `Eingelöst: {rewardText(reply.reward)}`, OK_COLOR)
        elseif reply.reason == "locked" then
            local seconds = if type(reply.secondsLeft) == "number" and reply.secondsLeft == reply.secondsLeft then math.max(math.ceil(reply.secondsLeft), 1) else 60
            showMessage(`Zu viele falsche Codes. Bitte warte {seconds} Sekunden.`, WARN_COLOR)
        else
            showMessage(REASONS[tostring(reply.reason)] or REASONS.unknown, WARN_COLOR)
        end
    end
    redeemButton.Activated:Connect(submit)
    input.FocusLost:Connect(function(enterPressed: boolean)
        if enterPressed then
            submit()
        end
    end)
end

return Codes
