--!strict
-- FirstPerson-Controller: Ego-Perspektive mit sichtbaren Armen.
-- * Kamera: Roblox-Modus LockFirstPerson, Sichtfeld und Kamera-Versatz aus Data/FirstPerson.
-- * Arme: Roblox blendet in der Ego-Perspektive den eigenen Körper aus. Die Arme (R15 und R6) werden
--   jedes Bild wieder sichtbar gemacht und über die Schultergelenke (C0) nach vorn ins Bild gedreht.
--   Die Haltung (Grundhaltung je Werkzeug, Blickneigung, Wippen beim Laufen, Schwung beim Sammeln)
--   rechnet das reine Modul Logic/FirstPerson. Änderungen an C0 bleiben auf diesem Client, andere
--   Spieler sehen den Charakter unverändert, die Lauf-Animationen von Roblox laufen weiter.
-- * Eigene Maschine: Teile direkt vor den Augen werden für den eigenen Blick durchscheinend
--   (LocalTransparencyModifier), Umhang und Schärpe des eigenen Skins werden ausgeblendet.
-- * Maus am PC: Sie ist zur Bildmitte gesperrt (Fadenkreuz). Offene Fenster, der Baum, Karten mit
--   Knöpfen (Data/FirstPerson cursorGuis) und die Alt-Taste geben sie frei (unsichtbarer Modal-Knopf).
-- Der Server merkt davon nichts, er rechnet Sand und Münzen unabhängig von der Kamera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Darstellung
local GUI_DISPLAY_ORDER = 2 -- unter Graben-Knopf (3), Menüleiste (4) und Fenstern (6)
local CROSSHAIR_COLOR = Color3.fromRGB(255, 248, 230)
local CROSSHAIR_STROKE_COLOR = Color3.fromRGB(40, 32, 24)
local HINT_COLOR = Color3.fromRGB(255, 248, 230)
local HINT_TEXT_SIZE = 14
local HINT_OFFSET_Y = 18 -- Pixel unter dem Fadenkreuz
local RENDER_STEP_NAME = "DuneBaronFirstPerson"
local TOOL_MODELS_FOLDER = "ToolModels" -- Controllers/ToolVisual
local ITEM_MODELS_FOLDER = "ItemModels" -- Controllers/ItemVisual
local TOOL_PART_PREFIX = "Part" -- ToolVisual benennt die Teile "Part1", "Part2", ...
local EYE_ROUNDING = 0.25 -- Augenhöhe auf so viele Studs gerundet, bevor die Sicht neu gerechnet wird

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local Data = loadShared("Data", "FirstPerson")
local Logic = loadShared("Logic", "FirstPerson")
local ToolLook = loadShared("Logic", "ToolLook")
local Input = require(script.Parent:WaitForChild("Input") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

local FirstPerson = {}

type Shoulder = { motor: Motor6D, original: CFrame, sign: number, pose: any }

local player = Players.LocalPlayer
local shoulders: { Shoulder } = {}
local armParts: { BasePart } = {}
local cursorToggled = false
local guiNeedsCursor = false
local cursorFree = false
local fadeKey = ""
local fadeSet: { [string]: boolean } = {}

local function poseRotation(pose: any): CFrame
    -- erst nach vorn heben (x), dann zur Seite spreizen (z), dann zur Mitte drehen (y)
    return CFrame.Angles(0, math.rad(pose.y), 0) * CFrame.Angles(0, 0, math.rad(pose.z)) * CFrame.Angles(math.rad(pose.x), 0, 0)
end

local function setupCharacter(character: Model)
    table.clear(shoulders)
    table.clear(armParts)
    fadeKey = ""
    local humanoid = character:WaitForChild("Humanoid", 10)
    if humanoid ~= nil and humanoid:IsA("Humanoid") then
        local o = Data.camera.offset
        humanoid.CameraOffset = Vector3.new(o.x, o.y, o.z)
    end
    local function addPart(part: Instance)
        if part:IsA("BasePart") and part.Parent == character and Logic.isArmPart(part.Name) then
            if table.find(armParts, part) == nil then
                table.insert(armParts, part)
            end
        end
    end
    local function addMotor(motor: Instance)
        if not motor:IsA("Motor6D") then
            return
        end
        local name = motor.Name
        local right = name == "RightShoulder" or name == "Right Shoulder"
        local left = name == "LeftShoulder" or name == "Left Shoulder"
        if not right and not left then
            return
        end
        for _, entry in shoulders do
            if entry.motor == motor then
                return
            end
        end
        table.insert(shoulders, {
            motor = motor,
            original = motor.C0,
            sign = if right then 1 else -1,
            pose = nil,
        })
    end
    for _, d in character:GetDescendants() do
        addPart(d)
        addMotor(d)
    end
    -- R15-Teile kommen manchmal nach CharacterAdded an.
    character.DescendantAdded:Connect(function(d: Instance)
        addPart(d)
        addMotor(d)
    end)
end

-- Ist der Knopf wirklich zu sehen (alle Eltern bis zur ScreenGui sichtbar)?
local function shown(object: GuiObject): boolean
    local current: Instance? = object
    while current ~= nil and not current:IsA("LayerCollector") do
        if current:IsA("GuiObject") and not (current :: GuiObject).Visible then
            return false
        end
        current = current.Parent
    end
    return current ~= nil
end

local function guiWantsCursor(playerGui: Instance): boolean
    for _, name in Data.cursor.cursorGuis do
        local gui = playerGui:FindFirstChild(name)
        if gui ~= nil and gui:IsA("ScreenGui") and gui.Enabled then
            for _, d in gui:GetDescendants() do
                if d:IsA("GuiButton") and shown(d) then
                    return true
                end
            end
        end
    end
    return false
end

local function groundY(character: Model): number?
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if root == nil or not root:IsA("BasePart") or humanoid == nil then
        return nil
    end
    return root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
end

-- Eigene Maschine: Teile im Sicht-Gang durchscheinend.
local function updateToolFade(camera: Camera, character: Model)
    local folder = workspace:FindFirstChild(TOOL_MODELS_FOLDER)
    local model = if folder ~= nil then folder:FindFirstChild(player.Name) else nil
    if model == nil then
        return
    end
    local toolId = player:GetAttribute("ToolId")
    local ground = groundY(character)
    local eye = if ground ~= nil then camera.CFrame.Position.Y - ground else Data.toolView.defaultEyeHeight
    eye = math.floor(eye / EYE_ROUNDING + 0.5) * EYE_ROUNDING
    local key = `{tostring(toolId)}|{eye}`
    if key ~= fadeKey then
        fadeKey = key
        table.clear(fadeSet)
        local look = ToolLook.of(if type(toolId) == "string" then toolId else nil)
        for _, index in Logic.blockingParts(look, eye, Data) do
            fadeSet[TOOL_PART_PREFIX .. index] = true
        end
    end
    for _, part in model:GetChildren() do
        if part:IsA("BasePart") then
            part.LocalTransparencyModifier = if fadeSet[part.Name] then Data.toolView.fadeTo else 0
        end
    end
end

local function hideOwnItems()
    local folder = workspace:FindFirstChild(ITEM_MODELS_FOLDER)
    local model = if folder ~= nil then folder:FindFirstChild(player.Name) else nil
    if model == nil then
        return
    end
    for _, name in Data.hiddenItemParts do
        local part = model:FindFirstChild(name)
        if part ~= nil and part:IsA("BasePart") then
            part.LocalTransparencyModifier = 1
        end
    end
end

local function onRender(dt: number)
    local character = player.Character
    local camera = workspace.CurrentCamera
    if character == nil or camera == nil then
        return
    end
    -- Arme sichtbar (Roblox setzt sie in der Ego-Perspektive jedes Bild auf unsichtbar).
    for _, part in armParts do
        part.LocalTransparencyModifier = 0
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    local velocity = if root ~= nil and root:IsA("BasePart") then root.AssemblyLinearVelocity else Vector3.zero
    local collecting = player:GetAttribute("Collecting") == true or Input.isHolding()
    local poses = Logic.armPose(player:GetAttribute("ToolId"), {
        pitch = Logic.pitchFromLook(camera.CFrame.LookVector.Y),
        t = os.clock(),
        collecting = collecting,
        speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude,
    }, Data)
    local alpha = Logic.smoothAlpha(dt, Data.smoothing)
    local shift = Data.camera.shoulderShift
    for _, entry in shoulders do
        if entry.motor.Parent == nil then
            continue
        end
        local target = if entry.sign > 0 then poses.right else poses.left
        entry.pose = if entry.pose == nil then target else Logic.approachPose(entry.pose, target, alpha)
        local original = entry.original
        local position = original.Position + Vector3.new(-entry.sign * shift.inward, shift.up, -shift.forward)
        entry.motor.C0 = CFrame.new(position) * poseRotation(entry.pose) * original.Rotation
    end

    updateToolFade(camera, character)
    hideOwnItems()
end

local function buildGui(): (TextButton, Frame, TextLabel)
    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronFirstPerson"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = GUI_DISPLAY_ORDER
    gui.IgnoreGuiInset = true

    -- Unsichtbarer Modal-Knopf: Solange er sichtbar ist, gibt Roblox die Maus frei.
    local modal = Instance.new("TextButton")
    modal.Name = "CursorRelease"
    modal.BackgroundTransparency = 1
    modal.Text = ""
    modal.Size = UDim2.fromOffset(0, 0)
    modal.Modal = true
    modal.Visible = false
    modal.Parent = gui

    local size = Data.crosshair.size
    local crosshair = Instance.new("Frame")
    crosshair.Name = "Crosshair"
    crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
    crosshair.Position = UDim2.fromScale(0.5, 0.5)
    crosshair.Size = UDim2.fromOffset(size, size)
    crosshair.BackgroundColor3 = CROSSHAIR_COLOR
    crosshair.BackgroundTransparency = Data.crosshair.transparency
    crosshair.BorderSizePixel = 0
    crosshair.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = crosshair
    local stroke = Instance.new("UIStroke")
    stroke.Color = CROSSHAIR_STROKE_COLOR
    stroke.Transparency = Data.crosshair.transparency
    stroke.Parent = crosshair

    local hint = Instance.new("TextLabel")
    hint.Name = "CursorHint"
    hint.AnchorPoint = Vector2.new(0.5, 0)
    hint.Position = UDim2.new(0.5, 0, 0.5, HINT_OFFSET_Y)
    hint.Size = UDim2.fromOffset(200, HINT_TEXT_SIZE + 6)
    hint.BackgroundTransparency = 1
    hint.Font = Enum.Font.GothamBold
    hint.TextSize = HINT_TEXT_SIZE
    hint.TextColor3 = HINT_COLOR
    hint.TextStrokeTransparency = 0.5
    hint.Text = Data.cursor.hintText
    hint.Visible = false
    hint.Parent = gui

    gui.Parent = player:WaitForChild("PlayerGui")
    return modal, crosshair, hint
end

function FirstPerson.isCursorFree(): boolean
    return cursorFree
end

function FirstPerson.Init() end

function FirstPerson.Start()
    if not Data.enabled then
        return
    end
    player.CameraMode = Enum.CameraMode.LockFirstPerson
    player.CameraMinZoomDistance = 0.5
    player.CameraMaxZoomDistance = 0.5
    local function applyFov()
        local camera = workspace.CurrentCamera
        if camera ~= nil then
            camera.FieldOfView = Data.camera.fieldOfView
        end
    end
    applyFov()
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(applyFov)

    local modal, crosshair, hint = buildGui()
    local hintUntil = 0
    local function showHint()
        if UserInputService.KeyboardEnabled and not Screen.isTouch() then
            hintUntil = os.clock() + Data.cursor.hintSeconds
        end
    end

    if player.Character ~= nil then
        task.spawn(setupCharacter, player.Character)
        showHint()
    end
    player.CharacterAdded:Connect(function(character: Model)
        setupCharacter(character)
        showHint()
    end)

    UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
        if input.UserInputType == Enum.UserInputType.Keyboard and Logic.isToggleKey(input.KeyCode.Name, Data) then
            cursorToggled = not cursorToggled
            hintUntil = 0
        end
    end)

    local playerGui = player:WaitForChild("PlayerGui")
    task.spawn(function()
        while true do
            local ok, result = pcall(guiWantsCursor, playerGui)
            guiNeedsCursor = ok and result == true
            task.wait(Data.cursor.checkSeconds)
        end
    end)

    RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
        cursorFree = Logic.cursorFree({
            windowOpen = Screen.isAnyWindowOpen(),
            treeOpen = Input.isSuspended(),
            toggled = cursorToggled,
            guiNeedsCursor = guiNeedsCursor,
        })
        modal.Visible = cursorFree
        crosshair.Visible = not cursorFree
        hint.Visible = not cursorFree and os.clock() < hintUntil
        local ok, err = pcall(onRender, dt)
        if not ok then
            warn("[FirstPerson] " .. tostring(err))
        end
    end)
end

return FirstPerson
