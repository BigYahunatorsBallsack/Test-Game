--!strict
-- Input-Controller
-- Übersetzt Eingaben in Absichten für den Server: Sammeltaste halten (SetCollecting) und
-- den Prompt am Händlerstand (Sell). Sendet nie Mengen oder Preise.
-- Solange gehalten wird, schickt der Client SetCollecting(true) alle
-- Economy.collecting.holdRefreshSeconds; bleibt das aus, stoppt der Server von selbst.

local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ACTION_NAME = "DuneBaronCollect"
-- Linke Maustaste halten (PC), R2 (Gamepad), Bildschirmknopf (Handy). E bleibt frei für
-- den Prompt am Händlerstand.
local COLLECT_INPUTS: { any } = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 }
local TOUCH_BUTTON_TITLE = "Graben"
local TOUCH_BUTTON_POSITION = UDim2.new(1, -150, 1, -150)
-- Attribut am ProximityPrompt des Händlerstands (gesetzt vom Server, Sand-Service).
local SELL_PROMPT_ATTRIBUTE = "SellPrompt"

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Economy") :: ModuleScript) :: any

local Input = {}

local holding = false
local holdToken = 0
local suspended = false
local setHolding: (boolean) -> () = function(_value: boolean) end

function Input.isHolding(): boolean
    return holding
end

local function bindCollect()
    ContextActionService:BindAction(ACTION_NAME, function(_name: string, inputState: Enum.UserInputState, _input: InputObject)
        if inputState == Enum.UserInputState.Begin then
            setHolding(true)
        elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
            setHolding(false)
        end
        return Enum.ContextActionResult.Sink
    end, true, table.unpack(COLLECT_INPUTS))
    ContextActionService:SetTitle(ACTION_NAME, TOUCH_BUTTON_TITLE)
    ContextActionService:SetPosition(ACTION_NAME, TOUCH_BUTTON_POSITION)
end

-- Pausiert das Sammeln, solange der Skilltree offen ist (Paket 2.2): Die Aktion wird gelöst
-- (damit auch der Bildschirmknopf am Handy verschwindet), und ein laufendes Halten endet.
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

    ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
        if prompt:GetAttribute(SELL_PROMPT_ATTRIBUTE) == true then
            sell:FireServer()
        end
    end)
end

return Input
