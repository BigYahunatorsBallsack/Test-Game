--!strict
-- Tutorial-Controller (Paket 1.6)
-- Zeigt den Hinweis des aktuellen Schritts (Text oben in der Mitte) und einen Strahl samt
-- pulsierender Markierung zum Ziel (Sandfeld oder Händlerstand). Der Schritt kommt vom Server
-- (State.tutorialStep), der Client entscheidet nichts. Nach dem letzten Schritt verschwindet
-- alles.
-- Ziele: Teile mit dem Tag World.sandField.tag bzw. World.sellStand.tag, der nächste gewinnt.
-- Gibt es kein Sandfeld mit Tag, zeigt der Strahl auf das Platzhalter-Sandfeld (Data/Terrain).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Animationen und Anzeige
local BANNER_FADE_SECONDS = 0.35
local BANNER_FADE_EASING = Enum.EasingStyle.Sine
local BANNER_POSITION = UDim2.new(0.5, 0, 0, 16)
local BANNER_SIZE = UDim2.new(0, 460, 0, 64)
local MARKER_PULSE_SECONDS = 0.7
local MARKER_PULSE_EASING = Enum.EasingStyle.Sine
local MARKER_SIZE_MIN = 1.2
local MARKER_SIZE_MAX = 2.2
local MARKER_HEIGHT_STUDS = 3
local BEAM_WIDTH = 0.45
local BEAM_TRANSPARENCY = 0.35
local BEAM_START_HEIGHT_STUDS = 1
-- Näher als das am Ziel verschwindet der Strahl (man ist angekommen).
local ARRIVED_DISTANCE_STUDS = 10
local UPDATE_SECONDS = 0.2

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local STEP_TEXT_COLOR = Color3.fromRGB(230, 200, 117)
local MARKER_COLOR = Color3.fromRGB(255, 220, 120)

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local TutorialData = loadShared("Data", "Tutorial")
local TerrainData = loadShared("Data", "Terrain")
local World = loadShared("Data", "World")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any

local Tutorial = {}

local player = Players.LocalPlayer
local currentStep = 1
local STEP_COUNT = #TutorialData.steps

-- Nächstes Teil mit dem Tag zu `from`, sonst nil.
local function nearestTagged(tag: string, from: Vector3): Vector3?
    local best: Vector3? = nil
    local bestDistance = math.huge
    for _, instance in CollectionService:GetTagged(tag) do
        if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
            local distance = (instance.Position - from).Magnitude
            if distance < bestDistance then
                bestDistance = distance
                best = instance.Position
            end
        end
    end
    return best
end

local function targetPosition(target: string, from: Vector3): Vector3?
    if target == "stand" then
        return nearestTagged(World.sellStand.tag, from)
    elseif target == "sand" then
        local tagged = nearestTagged(World.sandField.tag, from)
        if tagged ~= nil then
            return tagged
        end
        local field = TerrainData.placeholderField
        if field.enabled then
            return Vector3.new(field.center.x, field.center.y + field.size.y / 2, field.center.z)
        end
    end
    return nil
end

function Tutorial.Init() end

function Tutorial.Start()
    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronTutorial"
    gui.ResetOnSpawn = false

    local banner = Instance.new("Frame")
    banner.Name = "Banner"
    banner.AnchorPoint = Vector2.new(0.5, 0)
    banner.Position = BANNER_POSITION
    banner.Size = BANNER_SIZE
    banner.BackgroundColor3 = PANEL_COLOR
    banner.BackgroundTransparency = 1
    banner.Visible = false
    banner.Parent = gui
    Instance.new("UICorner").Parent = banner
    local constraint = Instance.new("UISizeConstraint")
    constraint.MaxSize = Vector2.new(460, 64)
    constraint.Parent = banner

    local stepLabel = Instance.new("TextLabel")
    stepLabel.Name = "Step"
    stepLabel.BackgroundTransparency = 1
    stepLabel.Position = UDim2.new(0, 12, 0, 4)
    stepLabel.Size = UDim2.new(1, -24, 0, 16)
    stepLabel.Font = Enum.Font.GothamBold
    stepLabel.TextColor3 = STEP_TEXT_COLOR
    stepLabel.TextScaled = true
    stepLabel.TextXAlignment = Enum.TextXAlignment.Left
    stepLabel.TextTransparency = 1
    stepLabel.Parent = banner

    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "Text"
    textLabel.BackgroundTransparency = 1
    textLabel.Position = UDim2.new(0, 12, 0, 22)
    textLabel.Size = UDim2.new(1, -24, 0, 38)
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextColor3 = TEXT_COLOR
    textLabel.TextScaled = true
    textLabel.TextWrapped = true
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.TextTransparency = 1
    textLabel.Parent = banner

    gui.Parent = player:WaitForChild("PlayerGui")

    -- Markierung und Strahl
    local folder = Instance.new("Folder")
    folder.Name = "TutorialMarker"
    folder.Parent = workspace

    local marker = Instance.new("Part")
    marker.Name = "Marker"
    marker.Shape = Enum.PartType.Ball
    marker.Anchored = true
    marker.CanCollide = false
    marker.CanQuery = false
    marker.CanTouch = false
    marker.CastShadow = false
    marker.Material = Enum.Material.Neon
    marker.Color = MARKER_COLOR
    marker.Transparency = 1
    marker.Size = Vector3.new(MARKER_SIZE_MIN, MARKER_SIZE_MIN, MARKER_SIZE_MIN)
    marker.Parent = folder
    local markerAttachment = Instance.new("Attachment")
    markerAttachment.Parent = marker

    local beam = Instance.new("Beam")
    beam.Name = "Beam"
    beam.Color = ColorSequence.new(MARKER_COLOR)
    beam.Width0 = BEAM_WIDTH
    beam.Width1 = BEAM_WIDTH
    beam.Transparency = NumberSequence.new(BEAM_TRANSPARENCY)
    beam.LightEmission = 1
    beam.FaceCamera = true
    beam.Segments = 1
    beam.Enabled = false
    beam.Attachment1 = markerAttachment
    beam.Parent = marker

    local pulse = TweenService:Create(
        marker,
        TweenInfo.new(MARKER_PULSE_SECONDS, MARKER_PULSE_EASING, Enum.EasingDirection.InOut, -1, true),
        { Size = Vector3.new(MARKER_SIZE_MAX, MARKER_SIZE_MAX, MARKER_SIZE_MAX) }
    )
    pulse:Play()

    local startAttachment: Attachment? = nil
    local function ensureStartAttachment(root: BasePart): Attachment
        local existing = root:FindFirstChild("TutorialBeamStart")
        if existing ~= nil and existing:IsA("Attachment") then
            return existing
        end
        local attachment = Instance.new("Attachment")
        attachment.Name = "TutorialBeamStart"
        attachment.Position = Vector3.new(0, BEAM_START_HEIGHT_STUDS - 3, 0)
        attachment.Parent = root
        return attachment
    end

    local fade = TweenInfo.new(BANNER_FADE_SECONDS, BANNER_FADE_EASING)
    local shownStep = 0
    local function showStep(step: number)
        if step == shownStep then
            return
        end
        shownStep = step
        local data = TutorialData.steps[step]
        if data == nil then
            TweenService:Create(banner, fade, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(stepLabel, fade, { TextTransparency = 1 }):Play()
            TweenService:Create(textLabel, fade, { TextTransparency = 1 }):Play()
            task.delay(BANNER_FADE_SECONDS, function()
                if shownStep > STEP_COUNT then
                    banner.Visible = false
                end
            end)
            return
        end
        banner.Visible = true
        stepLabel.Text = `Schritt {step} von {STEP_COUNT}`
        textLabel.Text = data.text
        TweenService:Create(banner, fade, { BackgroundTransparency = 0.25 }):Play()
        TweenService:Create(stepLabel, fade, { TextTransparency = 0 }):Play()
        TweenService:Create(textLabel, fade, { TextTransparency = 0 }):Play()
    end

    State.onChanged(function(snapshot: any)
        local step = snapshot.tutorialStep
        if type(step) == "number" then
            currentStep = step
            showStep(step)
        end
    end)

    -- Ziel regelmäßig nachführen (Teile werden gestreamt, der Charakter bewegt sich).
    local accumulated = 0
    RunService.Heartbeat:Connect(function(dt: number)
        accumulated += dt
        if accumulated < UPDATE_SECONDS then
            return
        end
        accumulated = 0
        local data = TutorialData.steps[currentStep]
        local character = player.Character
        local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
        if data == nil or root == nil or not root:IsA("BasePart") then
            beam.Enabled = false
            marker.Transparency = 1
            return
        end
        local position = targetPosition(data.target, root.Position)
        if position == nil or (position - root.Position).Magnitude < ARRIVED_DISTANCE_STUDS then
            beam.Enabled = false
            marker.Transparency = 1
            return
        end
        marker.Position = position + Vector3.new(0, MARKER_HEIGHT_STUDS, 0)
        marker.Transparency = 0.2
        startAttachment = ensureStartAttachment(root)
        beam.Attachment0 = startAttachment
        beam.Enabled = true
    end)
end

return Tutorial
