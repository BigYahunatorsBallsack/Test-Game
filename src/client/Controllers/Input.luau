--!strict
-- Input-Controller
-- Übersetzt Eingaben in Absichten für den Server: Sammeltaste halten (SetCollecting) und
-- den Prompt am Händlerstand (Sell). Sendet nie Mengen oder Preise.
-- Solange gehalten wird, schickt der Client SetCollecting(true) alle
-- Economy.collecting.holdRefreshSeconds; bleibt das aus, stoppt der Server von selbst.
--
-- Handy (Paket 3.6): Statt des kleinen Standard-Knopfs von Roblox gibt es einen eigenen, großen
-- runden Knopf "Graben" links neben dem Sprungknopf (Platz aus Logic/ScreenLayout). Halten sammelt,
-- Loslassen (auch abseits des Knopfs) und Abbrechen stoppen. Springen und Laufen gehen gleichzeitig.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ACTION_NAME = "DuneBaronCollect"
-- Linke Maustaste halten (PC), R2 (Gamepad). E bleibt frei für den Prompt am Händlerstand.
local COLLECT_INPUTS: { any } = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 }
-- Attribut am ProximityPrompt des Händlerstands (gesetzt vom Server, Sand-Service).
local SELL_PROMPT_ATTRIBUTE = "SellPrompt"

-- Graben-Knopf am Handy
local DIG_DISPLAY_ORDER = 3 -- unter Menüleiste (4) und Baum (5)
local DIG_BUTTON_TEXT = "Graben"
local DIG_BUTTON_COLOR = Color3.fromRGB(230, 200, 117)
local DIG_BUTTON_HELD_COLOR = Color3.fromRGB(255, 232, 150)
local DIG_BUTTON_TEXT_COLOR = Color3.fromRGB(40, 32, 24)
local DIG_BUTTON_TRANSPARENCY = 0.15
local DIG_BUTTON_HELD_TRANSPARENCY = 0

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Economy") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

local Input = {}

local holding = false
local holdToken = 0
local suspended = false
local setHolding: (boolean) -> () = function(_value: boolean) end
local digGui: ScreenGui? = nil
local refreshDigButton: () -> () = function() end

function Input.isHolding(): boolean
    return holding
end

local function bindCollect()
    -- Kein Standard-Knopf von Roblox: Am Handy gibt es den eigenen Graben-Knopf.
    ContextActionService:BindAction(ACTION_NAME, function(_name: string, inputState: Enum.UserInputState, _input: InputObject)
        if inputState == Enum.UserInputState.Begin then
            setHolding(true)
        elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
            setHolding(false)
        end
        return Enum.ContextActionResult.Sink
    end, false, table.unpack(COLLECT_INPUTS))
end

-- Pausiert das Sammeln, solange der Skilltree offen ist (Paket 2.2): Die Aktion wird gelöst,
-- der Graben-Knopf am Handy verschwindet, und ein laufendes Halten endet.
function Input.setSuspended(value: boolean)
    if suspended == value then
        return
    end
    suspended = value
    if value then
        setHolding(false)
        ContextActionService:UnbindAction(ACTION_NAME)
    else
        bindCollect()
    end
    refreshDigButton()
end

-- Der eigene Graben-Knopf: ein runder Knopf, der nur am Touch-Gerät erscheint.
local function createDigButton()
    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronDig"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = DIG_DISPLAY_ORDER

    local button = Instance.new("TextButton")
    button.Name = "DigButton"
    button.AutoButtonColor = false
    button.BackgroundColor3 = DIG_BUTTON_COLOR
    button.BackgroundTransparency = DIG_BUTTON_TRANSPARENCY
    button.Font = Enum.Font.GothamBold
    button.TextColor3 = DIG_BUTTON_TEXT_COLOR
    button.TextScaled = true
    button.Text = DIG_BUTTON_TEXT
    button.Visible = false
    button.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = button
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 18)
    padding.PaddingBottom = UDim.new(0, 18)
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.Parent = button

    -- Der Finger, der den Knopf hält. Ende, Abbruch oder Loslassen woanders lösen ihn.
    local heldBy: InputObject? = nil
    local function setLook(held: boolean)
        button.BackgroundColor3 = if held then DIG_BUTTON_HELD_COLOR else DIG_BUTTON_COLOR
        button.BackgroundTransparency = if held then DIG_BUTTON_HELD_TRANSPARENCY else DIG_BUTTON_TRANSPARENCY
    end
    local function release()
        if heldBy ~= nil then
            heldBy = nil
            setLook(false)
            setHolding(false)
        end
    end

    button.InputBegan:Connect(function(input: InputObject)
        if suspended or heldBy ~= nil then
            return
        end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            heldBy = input
            setLook(true)
            setHolding(true)
        end
    end)
    UserInputService.InputEnded:Connect(function(input: InputObject)
        if input == heldBy then
            release()
        end
    end)
    -- Fällt das Fenster aus dem Fokus (Anruf, App-Wechsel), endet das Halten ebenfalls.
    UserInputService.WindowFocusReleased:Connect(release)

    refreshDigButton = function()
        local layout = Screen.layout()
        local rect = layout.dig
        local show = rect ~= nil and not suspended
        button.Visible = show
        if rect ~= nil then
            button.Position = UDim2.fromOffset(rect.x, rect.y)
            button.Size = UDim2.fromOffset(rect.w, rect.h)
        end
        if not show then
            release()
        end
    end

    gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    digGui = gui
    Screen.onLayoutChanged(function()
        refreshDigButton()
    end)
    refreshDigButton()
end

function Input.Init() end

function Input.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local setCollecting = remotes:WaitForChild("SetCollecting") :: RemoteEvent
    local sell = remotes:WaitForChild("Sell") :: RemoteEvent

    setHolding = function(value: boolean)
        if holding == value then
            return
        end
        holding = value
        holdToken += 1
        setCollecting:FireServer(value)
        if value then
            local token = holdToken
            task.spawn(function()
                while holding and holdToken == token do
                    task.wait(Economy.collecting.holdRefreshSeconds)
                    if holding and holdToken == token then
                        setCollecting:FireServer(true)
                    end
                end
            end)
        end
    end

    if not suspended then
        bindCollect()
    end
    createDigButton()

    ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
        if prompt:GetAttribute(SELL_PROMPT_ATTRIBUTE) == true then
            sell:FireServer()
        end
    end)
end

return Input
