--!strict
-- Koloss-Anzeige (Paket 5.6)
-- Kleine Leiste oben in der Mitte, solange das Server-Event "Der Koloss" läuft: "Der Koloss: 42 %" mit
-- Balken, dazu der eigene Beitrag. Nach dem Fenster verschwindet sie. Bei 100 % meldet der Server mit
-- Notify "kolossDone" die erreichte Stufe und die Belohnung, die Karte bleibt kurz stehen.
-- Der Client zeigt nur an: Fortschritt, Beitrag, Stufe und Belohnung kommen allein vom Server (Snapshot-
-- Feld `koloss`, Notify). Es gibt keine Remote für das Event.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Größen und Zeiten
local DISPLAY_ORDER = 7 -- unter dem Kaufbanner (9) und dem Angebotshinweis (8)
local BAR_WIDTH = 300
local BAR_HEIGHT = 46
local TOP_OFFSET = 8
local PROGRESS_HEIGHT = 10
local DONE_VISIBLE_SECONDS = 12
local COUNTDOWN_TICK_SECONDS = 0.5

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local FILL_COLOR = Color3.fromRGB(255, 190, 90)
local DONE_COLOR = Color3.fromRGB(110, 150, 70)
local BAR_BACK_COLOR = Color3.fromRGB(64, 52, 40)

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local KolossLogic = loadShared("Logic", "Koloss")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any

local KolossBar = {}

local player = Players.LocalPlayer

local function minutesText(seconds: number): string
    return `{math.max(math.floor(seconds / 60 + 0.5), 1)} Min.`
end

local function rewardText(reward: any): string
    local kind = if type(reward) == "table" then reward.kind else nil
    if kind == "gems" then
        return `{if type(reward.amount) == "number" then reward.amount else 0} Gems`
    elseif kind == "coinBoost" then
        return `2x Münzen, {minutesText(reward.seconds)}`
    elseif kind == "luck" then
        return `Glück x2, {minutesText(reward.seconds)}`
    end
    return "?"
end

local function newLabel(parent: Instance, name: string, position: UDim2, size: UDim2, font: Enum.Font, color: Color3, text: string): TextLabel
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Position = position
    l.Size = size
    l.Font = font
    l.TextColor3 = color
    l.TextScaled = true
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = parent
    return l
end

function KolossBar.Init() end

function KolossBar.Start()
    local gui = Instance.new("ScreenGui")
    gui.Name = "KolossGui"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = DISPLAY_ORDER
    gui.Parent = player:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Name = "Bar"
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.Position = UDim2.new(0.5, 0, 0, TOP_OFFSET)
    frame.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
    frame.BackgroundColor3 = PANEL_COLOR
    frame.BackgroundTransparency = 0.15
    frame.Visible = false
    frame.Parent = gui
    Instance.new("UICorner").Parent = frame
    local limit = Instance.new("UISizeConstraint")
    limit.MaxSize = Vector2.new(BAR_WIDTH, 400)
    limit.Parent = frame

    local title = newLabel(frame, "Title", UDim2.new(0, 10, 0, 4), UDim2.new(0.62, 0, 0, 20), Enum.Font.GothamBold, TEXT_COLOR, "Der Koloss")
    local info = newLabel(frame, "Info", UDim2.new(0.62, 0, 0, 4), UDim2.new(0.38, -10, 0, 20), Enum.Font.Gotham, MUTED_COLOR, "")
    info.TextXAlignment = Enum.TextXAlignment.Right
    local back = Instance.new("Frame")
    back.Name = "Back"
    back.Position = UDim2.new(0, 10, 0, BAR_HEIGHT - PROGRESS_HEIGHT - 6)
    back.Size = UDim2.new(1, -20, 0, PROGRESS_HEIGHT)
    back.BackgroundColor3 = BAR_BACK_COLOR
    back.Parent = frame
    Instance.new("UICorner").Parent = back
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = FILL_COLOR
    fill.Parent = back
    Instance.new("UICorner").Parent = fill
    local reward = newLabel(frame, "Reward", UDim2.new(0, 10, 0, BAR_HEIGHT), UDim2.new(1, -20, 0, 0), Enum.Font.Gotham, TEXT_COLOR, "")
    reward.Visible = false
    reward.AutomaticSize = Enum.AutomaticSize.Y
    reward.TextScaled = false
    reward.TextSize = 14

    local koloss: any = nil
    local endsAt = 0 -- os.clock, wann das Fenster endet (nur Anzeige)
    local doneUntil = 0 -- bis dahin bleibt die Belohnungskarte stehen
    local rewardTextValue = ""

    local function render()
        local now = os.clock()
        local showDone = now < doneUntil
        local open = koloss ~= nil and koloss.state == "open"
        frame.Visible = showDone or open
        if not frame.Visible then
            return
        end
        if showDone then
            title.Text = "Der Koloss ist ausgegraben!"
            info.Text = ""
            fill.Size = UDim2.fromScale(1, 1)
            fill.BackgroundColor3 = DONE_COLOR
            reward.Text = rewardTextValue
            reward.Visible = rewardTextValue ~= ""
            frame.Size = UDim2.fromOffset(BAR_WIDTH, if reward.Visible then BAR_HEIGHT + 22 else BAR_HEIGHT)
            return
        end
        reward.Visible = false
        frame.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
        local target = if type(koloss.target) == "number" and koloss.target > 0 then koloss.target else 1
        local progress = if type(koloss.progress) == "number" then koloss.progress else 0
        local ratio = math.clamp(progress / target, 0, 1)
        -- Außerhalb der Event-Zone kommt kein neuer Stand an: der Server-Stand steht als Attribut bereit.
        local published = workspace:GetAttribute("KolossProgress")
        if type(published) == "number" and published == published then
            ratio = math.max(ratio, math.clamp(published, 0, 1))
        end
        fill.Size = UDim2.fromScale(ratio, 1)
        fill.BackgroundColor3 = if koloss.completed == true then DONE_COLOR else FILL_COLOR
        if koloss.completed == true then
            title.Text = "Der Koloss ist ausgegraben!"
            info.Text = ""
        else
            local left = math.max(endsAt - now, 0)
            title.Text = `Der Koloss: {math.floor(ratio * 100)} %`
            local you = if type(koloss.you) == "number" then koloss.you else 0
            info.Text = `Du: {math.floor(you / 60)} Min. · noch {math.floor(left / 3600)} Std.`
            if koloss.claimed == true then
                info.Text ..= " · Belohnung schon erhalten"
            end
        end
    end

    State.onChanged(function(snapshot: any)
        local entry = snapshot.koloss
        koloss = if type(entry) == "table" then entry else nil
        if koloss ~= nil then
            local seconds = if type(koloss.secondsLeft) == "number" and koloss.secondsLeft == koloss.secondsLeft then math.max(koloss.secondsLeft, 0) else 0
            endsAt = os.clock() + seconds
        end
        render()
    end)

    State.onNotify(function(payload: any)
        if type(payload) ~= "table" or payload.kind ~= KolossLogic.NOTIFY_KIND then
            return
        end
        local parts: { string } = {}
        if type(payload.rewards) == "table" then
            for _, item in payload.rewards do
                table.insert(parts, rewardText(item))
            end
        end
        local tierName = if type(payload.tierName) == "string" then payload.tierName else ""
        rewardTextValue = `{tierName}: {table.concat(parts, ", ")}`
        doneUntil = os.clock() + DONE_VISIBLE_SECONDS
        render()
    end)

    task.spawn(function()
        while true do
            task.wait(COUNTDOWN_TICK_SECONDS)
            if frame.Visible or koloss ~= nil then
                render()
            end
        end
    end)
end

return KolossBar
