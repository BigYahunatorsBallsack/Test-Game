--!strict
-- ToolVisual-Controller (Paket 2.4)
-- Zeigt das Werkzeug der aktuellen Stufe am Charakter. Das Modell besteht aus einfachen Formen
-- (Data/ToolLooks) und folgt dem Charakter. Bei einer höheren Stufe wächst es mit kurzer Animation
-- heraus, begleitet von einer Staubwolke und einem sanft gleitenden Kameraabstand. Alles nur
-- auf diesem Client, der Server zählt unabhängig davon. Der Wechsel selbst entscheidet das reine
-- Modul Logic/ToolLook.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Animation
local BURST_LIFETIME = NumberRange.new(0.5, 0.9)
local BURST_SPEED = NumberRange.new(8, 16)
local BURST_SIZE_FACTOR = 1.2 -- Größe der Wolke im Verhältnis zur Staubgröße der Stufe
local BURST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local CAMERA_EASING = Enum.EasingStyle.Quad
local MODEL_NAME = "ToolModel"
local BASE_MIN_ZOOM = 0.5 -- Standard von Roblox

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local ToolLook = loadShared("Logic", "ToolLook")
local ToolLooks = loadShared("Data", "ToolLooks")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any

local ToolVisual = {}

local player = Players.LocalPlayer
local currentToolId: string? = nil
local model: Model? = nil
local partOffsets: { { part: BasePart, local_: CFrame } } = {}
local follow: RBXScriptConnection? = nil
local scaleTween: Tween? = nil
local cameraTween: Tween? = nil
local popScale = 1

local function colorOf(hex: string): Color3
    local r = tonumber(string.sub(hex, 2, 3), 16) or 255
    local g = tonumber(string.sub(hex, 4, 5), 16) or 255
    local b = tonumber(string.sub(hex, 6, 7), 16) or 255
    return Color3.fromRGB(r, g, b)
end

local function materialOf(name: string): Enum.Material
    local ok, value = pcall(function()
        return (Enum.Material :: any)[name]
    end)
    if ok and typeof(value) == "EnumItem" then
        return value :: Enum.Material
    end
    return Enum.Material.SmoothPlastic
end

local function aliveRoot(): (BasePart?, Humanoid?)
    local character = player.Character
    local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
    local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
    if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
        return nil, nil
    end
    return root, humanoid
end

-- Höhe des Bodens unter dem Charakter, auf den sich y der Teile bezieht.
local function groundY(root: BasePart, humanoid: Humanoid): number
    return root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
end

local function clearModel()
    if follow ~= nil then
        follow:Disconnect()
        follow = nil
    end
    if scaleTween ~= nil then
        scaleTween:Cancel()
        scaleTween = nil
    end
    if model ~= nil then
        model:Destroy()
        model = nil
    end
    partOffsets = {}
    popScale = 1
end

local function placeParts(root: BasePart, humanoid: Humanoid)
    local ground = groundY(root, humanoid)
    -- Drehung nur um die Hochachse mitnehmen, damit das Modell beim Springen nicht kippt.
    local flat = CFrame.new(root.Position.X, ground, root.Position.Z)
        * CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0)
    for _, entry in partOffsets do
        local localCFrame = entry.local_
        local scaled = CFrame.new(localCFrame.Position * popScale) * (localCFrame - localCFrame.Position)
        entry.part.CFrame = flat * scaled
    end
end

local function buildModel(look: any, root: BasePart, humanoid: Humanoid)
    local folder = Instance.new("Model")
    folder.Name = MODEL_NAME
    for _, spec in look.parts do
        local part = Instance.new("Part")
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = true
        part.Color = colorOf(spec.colorHex)
        part.Material = materialOf(spec.material)
        if spec.shape == "Ball" then
            part.Shape = Enum.PartType.Ball
        elseif spec.shape == "Cylinder" then
            part.Shape = Enum.PartType.Cylinder
        else
            part.Shape = Enum.PartType.Block
        end
        part.Size = Vector3.new(spec.size.x, spec.size.y, spec.size.z)
        local rotation = spec.rotation
        local angles = if rotation ~= nil
            then CFrame.Angles(math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z))
            else CFrame.new()
        local localCFrame = CFrame.new(spec.offset.x, spec.offset.y, spec.offset.z) * angles
        part.Parent = folder
        table.insert(partOffsets, { part = part, local_ = localCFrame })
    end
    model = folder
    popScale = 1
    placeParts(root, humanoid)
    folder.Parent = workspace
    follow = RunService.Heartbeat:Connect(function()
        local currentRoot, currentHumanoid = aliveRoot()
        if currentRoot == nil or currentHumanoid == nil then
            return
        end
        placeParts(currentRoot, currentHumanoid)
    end)
end

local function applyCamera(look: any, animated: boolean)
    local target = BASE_MIN_ZOOM + look.cameraBonusStuds
    if cameraTween ~= nil then
        cameraTween:Cancel()
        cameraTween = nil
    end
    if player.CameraMaxZoomDistance < target then
        player.CameraMaxZoomDistance = target + 8
    end
    if not animated then
        player.CameraMinZoomDistance = target
        return
    end
    cameraTween = TweenService:Create(
        player,
        TweenInfo.new(ToolLooks.change.cameraSeconds, CAMERA_EASING, Enum.EasingDirection.Out),
        { CameraMinZoomDistance = target }
    )
    cameraTween:Play()
end

local function burst(look: any, root: BasePart, humanoid: Humanoid)
    local anchor = Instance.new("Part")
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.Position = Vector3.new(root.Position.X, groundY(root, humanoid) + 1, root.Position.Z + 4)
    local emitter = Instance.new("ParticleEmitter")
    emitter.Enabled = false
    emitter.Texture = BURST_TEXTURE
    emitter.Lifetime = BURST_LIFETIME
    emitter.Speed = BURST_SPEED
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Size = NumberSequence.new(look.dust.size * BURST_SIZE_FACTOR)
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Color = ColorSequence.new(Color3.fromRGB(230, 200, 117))
    emitter.Parent = anchor
    anchor.Parent = workspace
    emitter:Emit(ToolLooks.change.burstCount)
    task.delay(BURST_LIFETIME.Max + 0.2, function()
        anchor:Destroy()
    end)
end

local function setTool(toolId: string, animated: boolean)
    local look = ToolLook.of(toolId)
    clearModel()
    local root, humanoid = aliveRoot()
    if root == nil or humanoid == nil then
        -- Charakter noch nicht da: beim nächsten Zustand erneut versuchen.
        currentToolId = nil
        return
    end
    buildModel(look, root, humanoid)
    applyCamera(look, animated)
    if animated and #look.parts > 0 then
        popScale = ToolLooks.change.popStartScale
        local value = Instance.new("NumberValue")
        value.Value = popScale
        local style = (Enum.EasingStyle :: any)[ToolLooks.change.popEasing] or Enum.EasingStyle.Back
        local tween = TweenService:Create(
            value,
            TweenInfo.new(ToolLooks.change.popSeconds, style, Enum.EasingDirection.Out),
            { Value = 1 }
        )
        value.Changed:Connect(function(v: number)
            popScale = v
        end)
        tween.Completed:Connect(function()
            popScale = 1
            value:Destroy()
        end)
        scaleTween = tween
        tween:Play()
    end
    if animated then
        burst(look, root, humanoid)
    end
    currentToolId = toolId
end

local function onState(snapshot: any)
    local toolId = snapshot.toolId
    if type(toolId) ~= "string" then
        return
    end
    local change = ToolLook.change(currentToolId, toolId)
    if change == "none" and model ~= nil then
        return
    end
    setTool(toolId, change == "upgrade")
end

function ToolVisual.Init() end

function ToolVisual.Start()
    State.onChanged(onState)
    -- Nach dem Wiederbeleben das Modell neu bauen (der Charakter ist ein neuer).
    player.CharacterAdded:Connect(function()
        local snapshot = State.get()
        currentToolId = nil
        if snapshot ~= nil then
            task.defer(onState, snapshot)
        end
    end)
end

return ToolVisual
