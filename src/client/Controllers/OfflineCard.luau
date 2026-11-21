--!strict
-- OfflineCard-Controller (Paket 5.3)
-- Karte "Schön, dass du wieder da bist": Der Server zahlt den Offline-Ertrag beim Laden (Services/Offline) und
-- schickt den Bericht im StateSync (`offline`). Der Client zeigt jeden Bericht (id) einmal an und
-- rechnet nichts: Zeit, Münzen und Grenze stehen im Bericht. Die Karte erscheint nie während Tutorial,
-- Reveal oder eines offenen Fensters (wie der Angebots-Hinweis aus 4.5) und wartet dann.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Zeiten und Maße
local CHECK_SECONDS = 1
local CARD_DISPLAY_ORDER = 8 -- unter dem Kaufbanner (9) und den Reveals (10 bis 12)
local CARD_SIZE = Vector2.new(380, 200)

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local ACCENT_COLOR = Color3.fromRGB(255, 190, 90)
local BUTTON_COLOR = Color3.fromRGB(110, 150, 70)

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local BigNum = loadShared("Logic", "BigNum")
local EconomyData = loadShared("Data", "Economy")
local TutorialLogic = loadShared("Logic", "Tutorial")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any
local Reveal = require(script.Parent:WaitForChild("Reveal") :: ModuleScript) :: any
local CrateShop = require(script.Parent:WaitForChild("CrateShop") :: ModuleScript) :: any

local OfflineCard = {}

local player = Players.LocalPlayer

-- "3 Std. 20 Min." oder "45 Min." (Sekunden werden abgerundet auf ganze Minuten).
local function durationText(seconds: number): string
    local minutes = math.max(math.floor(seconds / 60), 1)
    local hours = minutes // 60
    local rest = minutes % 60
    if hours > 0 and rest > 0 then
        return `{hours} Std. {rest} Min.`
    elseif hours > 0 then
        return `{hours} Std.`
    end
    return `{rest} Min.`
end

local function hoursText(seconds: number): string
    return `{math.floor(seconds / 3600 + 0.5)} Std.`
end

local function newLabel(parent: Instance, position: UDim2, size: UDim2, font: Enum.Font, color: Color3, text: string): TextLabel
    local l = Instance.new("TextLabel")
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

function OfflineCard.Init() end

function OfflineCard.Start()
    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronOfflineCard"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = CARD_DISPLAY_ORDER
    gui.Parent = player:WaitForChild("PlayerGui")

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.4)
    card.Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
    card.BackgroundColor3 = PANEL_COLOR
    card.BackgroundTransparency = 0.1
    card.Visible = false
    card.Active = true
    card.Parent = gui
    Instance.new("UICorner").Parent = card
    local stroke = Instance.new("UIStroke")
    stroke.Color = ACCENT_COLOR
    stroke.Thickness = 2
    stroke.Parent = card

    local titleLabel = newLabel(card, UDim2.new(0, 14, 0, 10), UDim2.new(1, -28, 0, 34), Enum.Font.GothamBold, ACCENT_COLOR, "Schön, dass du wieder da bist")
    local bodyLabel = newLabel(card, UDim2.new(0, 14, 0, 50), UDim2.new(1, -28, 0, 70), Enum.Font.GothamBold, TEXT_COLOR, "")
    local noteLabel = newLabel(card, UDim2.new(0, 14, 0, 122), UDim2.new(1, -28, 0, 24), Enum.Font.Gotham, MUTED_COLOR, "")
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "Close"
    closeButton.AnchorPoint = Vector2.new(0.5, 1)
    closeButton.Position = UDim2.new(0.5, 0, 1, -10)
    closeButton.Size = UDim2.new(1, -28, 0, 38)
    closeButton.BackgroundColor3 = BUTTON_COLOR
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextColor3 = TEXT_COLOR
    closeButton.TextScaled = true
    closeButton.Text = "Weiter"
    closeButton.Parent = card
    Instance.new("UICorner").Parent = closeButton

    local latest: any = nil -- jüngster Bericht aus dem StateSync
    local shownId = 0
    local tutorialStep = 1

    State.onChanged(function(snapshot: any)
        tutorialStep = if type(snapshot.tutorialStep) == "number" then snapshot.tutorialStep else 1
        local report = snapshot.offline
        if type(report) == "table" and type(report.id) == "number" then
            latest = report
        end
    end)

    local function show(report: any)
        local cap = if type(report.capSeconds) == "number" then report.capSeconds else 0
        if report.ok == true and report.coins ~= nil then
            titleLabel.Text = "Schön, dass du wieder da bist"
            bodyLabel.Text = `Du warst {durationText(report.awaySeconds)} weg. Dein Begleiter hat {BigNum.format(BigNum.deserialize(report.coins))} Münzen gesammelt.`
            if report.capped == true then
                noteLabel.Text = `Grenze erreicht: {hoursText(cap)} (mit Auto-Dig {hoursText(EconomyData.offline.autoDigHours * 3600)}).`
            else
                noteLabel.Text = ""
            end
        else
            titleLabel.Text = "Kein Begleiter"
            bodyLabel.Text = "Rüste einen Begleiter aus, dann sammelt er auch, wenn du weg bist."
            noteLabel.Text = ""
        end
        card.Visible = true
    end

    closeButton.Activated:Connect(function()
        card.Visible = false
    end)

    task.spawn(function()
        while true do
            task.wait(CHECK_SECONDS)
            local report = latest
            if report ~= nil and report.id > shownId and not card.Visible
                and (report.ok == true or report.reason == "noCompanion")
                and tutorialStep > TutorialLogic.count()
                and not Reveal.isBusy() and not CrateShop.isRevealing()
                and not Screen.isAnyWindowOpen() then
                shownId = report.id
                pcall(show, report)
            elseif report ~= nil and report.id > shownId and report.ok ~= true and report.reason ~= "noCompanion" then
                shownId = report.id -- nichts anzuzeigen (zum Beispiel noGain)
            end
        end
    end)
end

return OfflineCard
