--!strict
-- FirstPerson-Controller: Ego-Perspektive mit Händen im Bild.
-- * Kamera: Roblox-Modus LockFirstPerson, Sichtfeld und Kamera-Versatz aus Data/FirstPerson.
-- * Hände (Viewmodel): Zwei Gruppen aus einfachen Teilen hängen an der Kamera, nur auf diesem
--   Client (Ordner unter workspace.CurrentCamera). Rechts die Hand mit dem Werkzeug (Schaufel, bei
--   Maschinen die Fernsteuerung), links die Hand mit dem Eimer. Der Sand im Eimer zeigt den Tank.
--   Beim Sammeln sticht die Schaufel, beim Laufen wippen die Hände, beim Umsehen ziehen sie nach.
--   Die Rechnung steht im reinen Modul Logic/FirstPerson, die Teile in Data/FirstPerson.
-- * Eigene Maschine: Hält die Hand das Werkzeug schon (Hand, Schaufel), wird das Weltmodell vor dem
--   eigenen Charakter ausgeblendet. Bei Maschinen werden nur die Teile direkt vor den Augen
--   durchscheinend. Umhang und Schärpe des eigenen Skins werden ausgeblendet. Andere Spieler sehen
--   Avatar, Skin und Werkzeug unverändert.
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
local SKIN_REFRESH_SECONDS = 1 -- so oft wird die Hautfarbe vom Avatar übernommen
local RENDER_STEP_NAME = "DuneBaronFirstPerson"
local VIEWMODEL_NAME = "DuneBaronViewmodel"
local TOOL_MODELS_FOLDER = "ToolModels" -- Controllers/ToolVisual
local ITEM_MODELS_FOLDER = "ItemModels" -- Controllers/ItemVisual
local TOOL_PART_PREFIX = "Part" -- ToolVisual benennt die Teile "Part1", "Part2", ...
local EYE_ROUNDING = 0.25 -- Augenhöhe auf so viele Studs gerundet, bevor die Sicht neu gerechnet wird
local SKIN_PART_NAMES = { "RightHand", "Right Arm", "RightLowerArm", "LeftHand", "Left Arm" }

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local Data = loadShared("Data", "FirstPerson")
local Logic = loadShared("Logic", "FirstPerson")
local ToolLook = loadShared("Logic", "ToolLook")
local BigNum = loadShared("Logic", "BigNum")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Input = require(script.Parent:WaitForChild("Input") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

local FirstPerson = {}

type Piece = { part: BasePart, cf: CFrame, paint: string? }
type Group = { pieces: { Piece } }

local player = Players.LocalPlayer
local cursorToggled = false
local guiNeedsCursor = false
local cursorFree = false
local fadeKey = ""
local fadeSet: { [string]: boolean } = {}

local model: Model? = nil
local rightGroup: Group = { pieces = {} }
local leftGroup: Group = { pieces = {} }
local itemPieces: { Piece } = {}
local itemId = ""
local fillPart: BasePart? = nil
local skinColor: Color3? = nil
local nextSkinRefresh = 0
local sway = { yaw = 0, pitch = 0 }
local lastYaw: number? = nil
local lastPitch: number? = nil

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
    return if ok and value ~= nil then value else Enum.Material.SmoothPlastic
end

local function angles(rotation: any): CFrame
    if rotation == nil then
        return CFrame.new()
    end
    return CFrame.Angles(math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z))
end

local function localFrame(spec: any): CFrame
    return CFrame.new(spec.offset.x, spec.offset.y, spec.offset.z) * angles(spec.rotation)
end

local function newPart(name: string, shape: string, size: Vector3, color: Color3, material: Enum.Material): BasePart
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Massless = true
    part.Shape = if shape == "Ball" then Enum.PartType.Ball elseif shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
    part.Size = size
    part.Color = color
    part.Material = material
    part.Parent = model
    return part
end

local function paintColor(spec: any): Color3
    if spec.paint == "skin" and skinColor ~= nil then
        return skinColor :: Color3
    elseif spec.paint == "sleeve" then
        return colorOf(Data.viewmodel.sleeveHex)
    end
    return colorOf(spec.colorHex)
end

local function addPieces(target: { Piece }, specs: { any })
    for index, spec in specs do
        local part = newPart(spec.name or `Part{index}`, spec.shape, Vector3.new(spec.size.x, spec.size.y, spec.size.z), paintColor(spec), materialOf(spec.material))
        table.insert(target, { part = part, cf = localFrame(spec), paint = spec.paint })
    end
end

local function destroyPieces(list: { Piece })
    for _, piece in list do
        piece.part:Destroy()
    end
    table.clear(list)
end

local function buildViewmodel(camera: Camera)
    if model ~= nil then
        model:Destroy()
    end
    local m = Instance.new("Model")
    m.Name = VIEWMODEL_NAME
    model = m
    rightGroup = { pieces = {} }
    leftGroup = { pieces = {} }
    table.clear(itemPieces)
    itemId = ""
    local vm = Data.viewmodel
    addPieces(rightGroup.pieces, vm.rightArm)
    addPieces(leftGroup.pieces, vm.leftArm)
    addPieces(leftGroup.pieces, vm.bucket)
    local fill = vm.fill
    fillPart = newPart("Fill", "Cylinder", Vector3.new(fill.minHeight, fill.diameter, fill.diameter), colorOf(fill.colorHex), materialOf(fill.material))
    m.Parent = camera
end

-- Werkzeug in der rechten Hand wechseln, wenn sich das Werkzeug geändert hat.
local function ensureItem(view: any)
    if view.item == itemId then
        return
    end
    destroyPieces(itemPieces)
    itemId = view.item
    local item = Data.viewmodel.items[view.item]
    if item ~= nil then
        addPieces(itemPieces, item.parts)
    end
end

local function refreshSkin(character: Model)
    for _, name in SKIN_PART_NAMES do
        local part = character:FindFirstChild(name)
        if part ~= nil and part:IsA("BasePart") then
            skinColor = part.Color
            break
        end
    end
    for _, list in { rightGroup.pieces, leftGroup.pieces, itemPieces } do
        for _, piece in list do
            if piece.paint == "skin" and skinColor ~= nil then
                piece.part.Color = skinColor :: Color3
            end
        end
    end
end

local function setViewmodelVisible(visible: boolean)
    local m = model
    if m ~= nil then
        local parent: Instance? = if visible then workspace.CurrentCamera else nil
        if m.Parent ~= parent then
            m.Parent = parent
        end
    end
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

-- Eigenes Werkzeug-Modell in der Welt: ganz ausblenden (die Hand hält es) oder nur die Teile vor
-- den Augen durchscheinend machen (Maschinen).
local function updateWorldTool(camera: Camera, character: Model, toolId: string?, view: any)
    local folder = workspace:FindFirstChild(TOOL_MODELS_FOLDER)
    local worldModel = if folder ~= nil then folder:FindFirstChild(player.Name) else nil
    if worldModel == nil then
        return
    end
    if not view.hideWorldTool then
        local ground = groundY(character)
        local eye = if ground ~= nil then camera.CFrame.Position.Y - ground else Data.toolView.defaultEyeHeight
        eye = math.floor(eye / EYE_ROUNDING + 0.5) * EYE_ROUNDING
        local key = `{tostring(toolId)}|{eye}`
        if key ~= fadeKey then
            fadeKey = key
            table.clear(fadeSet)
            for _, index in Logic.blockingParts(ToolLook.of(toolId), eye, Data) do
                fadeSet[TOOL_PART_PREFIX .. index] = true
            end
        end
    end
    for _, part in worldModel:GetChildren() do
        if part:IsA("BasePart") then
            part.LocalTransparencyModifier = if view.hideWorldTool then 1 elseif fadeSet[part.Name] then Data.toolView.fadeTo else 0
        end
    end
end

local function hideOwnItems()
    local folder = workspace:FindFirstChild(ITEM_MODELS_FOLDER)
    local itemModel = if folder ~= nil then folder:FindFirstChild(player.Name) else nil
    if itemModel == nil then
        return
    end
    for _, name in Data.hiddenItemParts do
        local part = itemModel:FindFirstChild(name)
        if part ~= nil and part:IsA("BasePart") then
            part.LocalTransparencyModifier = 1
        end
    end
end

local function tankRatio(): number
    local snapshot = State.get()
    if snapshot == nil then
        return 0
    end
    local ok, tank = pcall(function()
        return BigNum.toNumber(BigNum.deserialize(snapshot.tank))
    end)
    return Logic.tankRatio(if ok then tank else 0, snapshot.capacity)
end

local function wrapAngle(a: number): number
    return (a + math.pi) % (2 * math.pi) - math.pi
end

local function onRender(dt: number)
    local character = player.Character
    local camera = workspace.CurrentCamera
    local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
    if character == nil or camera == nil or humanoid == nil or humanoid.Health <= 0 then
        setViewmodelVisible(false)
        return
    end
    if model == nil then
        buildViewmodel(camera)
    end
    setViewmodelVisible(true)

    local now = os.clock()
    if now >= nextSkinRefresh then
        nextSkinRefresh = now + SKIN_REFRESH_SECONDS
        refreshSkin(character)
    end

    local toolAttribute = player:GetAttribute("ToolId")
    local toolId: string? = if type(toolAttribute) == "string" then toolAttribute else nil
    local view = Logic.toolView(toolId, Data)
    ensureItem(view)

    -- Nachziehen beim Umsehen.
    local camCF = camera.CFrame
    local look = camCF.LookVector
    local yaw = math.atan2(-look.X, -look.Z)
    local pitch = math.asin(math.clamp(look.Y, -1, 1))
    local yawDelta = if lastYaw ~= nil then wrapAngle(yaw - lastYaw) else 0
    local pitchDelta = if lastPitch ~= nil then pitch - lastPitch else 0
    lastYaw, lastPitch = yaw, pitch
    sway = Logic.swayStep(sway, yawDelta, pitchDelta, dt, Data)
    local base = camCF * CFrame.Angles(math.rad(sway.pitch), math.rad(sway.yaw), 0)

    local root = character:FindFirstChild("HumanoidRootPart")
    local velocity = if root ~= nil and root:IsA("BasePart") then root.AssemblyLinearVelocity else Vector3.zero
    local pose = Logic.viewPose(toolId, {
        t = now,
        collecting = player:GetAttribute("Collecting") == true or Input.isHolding(),
        speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude,
    }, Data)

    local vm = Data.viewmodel
    local function groupFrame(anchor: any, groupPose: any): CFrame
        local m, t = groupPose.move, groupPose.turn
        return base * localFrame(anchor) * CFrame.new(m.x, m.y, m.z) * angles(t)
    end
    local rightCF = groupFrame(vm.right, pose.right)
    local leftCF = groupFrame(vm.left, pose.left)

    local parts: { BasePart } = {}
    local frames: { CFrame } = {}
    for _, piece in rightGroup.pieces do
        table.insert(parts, piece.part)
        table.insert(frames, rightCF * piece.cf)
    end
    for _, piece in itemPieces do
        table.insert(parts, piece.part)
        table.insert(frames, rightCF * piece.cf)
    end
    for _, piece in leftGroup.pieces do
        table.insert(parts, piece.part)
        table.insert(frames, leftCF * piece.cf)
    end
    local fp = fillPart
    if fp ~= nil then
        local fill = Logic.bucketFill(tankRatio(), Data)
        fp.Size = Vector3.new(fill.height, vm.fill.diameter, vm.fill.diameter)
        table.insert(parts, fp)
        table.insert(frames, leftCF * CFrame.new(0, fill.centerY, 0) * CFrame.Angles(0, 0, math.rad(90)))
    end
    workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)

    updateWorldTool(camera, character, toolId, view)
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
    local function applyCamera()
        local camera = workspace.CurrentCamera
        if camera ~= nil then
            camera.FieldOfView = Data.camera.fieldOfView
            if model ~= nil then
                (model :: Model).Parent = camera
            end
        end
    end
    applyCamera()
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(applyCamera)

    local modal, crosshair, hint = buildGui()
    local hintUntil = 0
    local function onCharacter(character: Model)
        nextSkinRefresh = 0
        fadeKey = ""
        lastYaw, lastPitch = nil, nil
        if UserInputService.KeyboardEnabled and not Screen.isTouch() then
            hintUntil = os.clock() + Data.cursor.hintSeconds
        end
        local humanoid = character:WaitForChild("Humanoid", 10)
        if humanoid ~= nil and humanoid:IsA("Humanoid") then
            local o = Data.camera.offset
            humanoid.CameraOffset = Vector3.new(o.x, o.y, o.z)
        end
    end
    if player.Character ~= nil then
        task.spawn(onCharacter, player.Character)
    end
    player.CharacterAdded:Connect(onCharacter)

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
