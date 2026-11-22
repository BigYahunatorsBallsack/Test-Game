--!strict
-- ToolVisual-Controller (Paket 2.4)
-- Zeigt das Werkzeug JEDES Spielers vor dem Charakter. Das Modell besteht aus einfachen Formen
-- (Data/ToolLooks). Der Server setzt die Spieler-Attribute `ToolId` und `Collecting`, der Client
-- liest sie nur (er kann sie für andere nicht ändern, und der Server rechnet unabhängig davon).
-- Beim Sammeln bewegen sich Teile (motions) und der Sand fließt (sandFlow). Bei einer höheren
-- Stufe wächst das Modell heraus (Staubwolke), für den eigenen Charakter gleitet zusätzlich der
-- Kameraabstand. Weit entfernte Spieler bekommen weder Bewegung noch Sandfluss, bei schwachem
-- Gerät (Grafikstufe "minimal", Controllers/Graphics) entfällt der Sandfluss ganz, auf "schlank"
-- gibt es weniger Partikel, keine Schatten fremder Werkzeuge und eine kürzere Bewegungsentfernung. Welche Änderung eine Animation
-- bekommt, entscheidet das reine Modul Logic/ToolLook.
-- Werkzeug-Variante (Paket 4.3): Das Attribut `ToolVariantId` färbt die Teile der aktuellen Stufe um
-- (Farbe aus Data/ItemLooks gemischt, Material der Variante), die Form bleibt die der Stufe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Animation und Darstellung
local BURST_LIFETIME = NumberRange.new(0.5, 0.9)
local BURST_SPEED = NumberRange.new(8, 16)
local BURST_SIZE_FACTOR = 1.2 -- Größe der Wolke im Verhältnis zur Staubgröße der Stufe
local FLOW_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FLOW_END_SIZE_FACTOR = 0.4
local FLOW_GRAVITY_FACTOR = 0.5 -- nur Fontäne (eruption)
local SAND_COLOR = Color3.fromRGB(230, 200, 117)
local CAMERA_EASING = Enum.EasingStyle.Quad
local SOUND_VOLUME = 0.5
local SOUND_MAX_DISTANCE = 80
local BASE_MIN_ZOOM = 0.5 -- Standard von Roblox
local VARIANT_TINT = 0.65 -- Anteil der Variantenfarbe an der Teilefarbe (0 = Original, 1 = nur Variante)
local FOLDER_NAME = "ToolModels"
local FLOW_PART_NAME = "Flow"

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local ToolLook = loadShared("Logic", "ToolLook")
local ToolLooks = loadShared("Data", "ToolLooks")
local ItemLooks = loadShared("Data", "ItemLooks")
local FirstPersonData = loadShared("Data", "FirstPerson")
local DigAim = loadShared("Logic", "DigAim")
local Dig = require(script.Parent:WaitForChild("Dig") :: ModuleScript) :: any
local Graphics = require(script.Parent:WaitForChild("Graphics") :: ModuleScript) :: any

local ToolVisual = {}

type Entry = {
    toolId: string,
    variantId: string, -- Werkzeug-Variante beim Bau ("" = keine)
    look: any,
    model: Model,
    parts: { BasePart }, -- Teile in der Reihenfolge von look.parts
    baseSizes: { Vector3 },
    baseCFrames: { CFrame }, -- Lage relativ zum Boden unter dem Charakter
    flowPart: BasePart?,
    flowCFrame: CFrame,
    emitter: ParticleEmitter?,
    sound: Sound?,
    popStart: number?,
    popScale: number,
    lastScale: number,
    nextFarUpdate: number,
    castShadow: boolean, -- Schatten der Teile gerade an? (Grafikstufe, Paket 3.6)
}

local localPlayer = Players.LocalPlayer
local entries: { [Player]: Entry } = {}
local folder: Folder? = nil
local cameraTween: Tween? = nil

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

local function rootOf(player: Player): (BasePart?, Humanoid?)
    local character = player.Character
    local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
    local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
    if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
        return nil, nil
    end
    return root, humanoid
end

-- Fläche unter dem Charakter, auf die sich y der Teile bezieht, mit der Blickrichtung (nur Drehung
-- um die Hochachse, damit das Modell beim Springen nicht kippt).
local function groundFrame(root: BasePart, humanoid: Humanoid): CFrame
    local ground = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
    local _, yaw = root.CFrame:ToEulerAnglesYXZ()
    return CFrame.new(root.Position.X, ground, root.Position.Z) * CFrame.Angles(0, yaw, 0)
end

local function angles(rotation: any): CFrame
    if rotation == nil then
        return CFrame.new()
    end
    return CFrame.Angles(math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z))
end

-- Drehung von +Y auf die Richtung `dir` (für die Emissionsrichtung des Sandflusses).
local function alignY(dir: Vector3): CFrame
    local axis = Vector3.yAxis:Cross(dir)
    if axis.Magnitude < 1e-4 then
        return if dir.Y >= 0 then CFrame.new() else CFrame.Angles(math.pi, 0, 0)
    end
    return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(Vector3.yAxis:Dot(dir), -1, 1)))
end

local function axisVector(axis: string?): Vector3
    if axis == "x" then
        return Vector3.xAxis
    elseif axis == "z" then
        return Vector3.zAxis
    end
    return Vector3.yAxis
end

local function destroyEntry(player: Player)
    local entry = entries[player]
    if entry ~= nil then
        entry.model:Destroy()
        entries[player] = nil
    end
end

local function newFlow(look: any, model: Model): (BasePart?, CFrame, ParticleEmitter?, Sound?)
    local flow = look.sandFlow
    local needsFlow = flow.rate > 0
    local needsSound = look.loopSoundId ~= ""
    if not needsFlow and not needsSound then
        return nil, CFrame.new(), nil, nil
    end
    local from = Vector3.new(flow.from.x, flow.from.y, flow.from.z)
    local to = Vector3.new(flow.to.x, flow.to.y, flow.to.z)
    local dir = to - from
    local localCFrame = CFrame.new(from) * alignY(if dir.Magnitude > 1e-4 then dir.Unit else Vector3.yAxis)

    local part = Instance.new("Part")
    part.Name = FLOW_PART_NAME
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Transparency = 1
    part.Size = Vector3.new(0.2, 0.2, 0.2)
    part.Parent = model

    local emitter: ParticleEmitter? = nil
    if needsFlow then
        local e = Instance.new("ParticleEmitter")
        e.Enabled = false
        e.Rate = flow.rate
        e.Texture = FLOW_TEXTURE
        e.Lifetime = NumberRange.new(flow.lifetime * 0.8, flow.lifetime)
        e.Speed = NumberRange.new(flow.speed * 0.8, flow.speed)
        e.SpreadAngle = Vector2.new(flow.spread, flow.spread)
        e.EmissionDirection = Enum.NormalId.Top
        e.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, flow.size),
            NumberSequenceKeypoint.new(1, flow.size * FLOW_END_SIZE_FACTOR),
        })
        e.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(1, 1),
        })
        e.Color = ColorSequence.new(SAND_COLOR)
        e.LightInfluence = 1
        if flow.kind == "eruption" then
            e.Acceleration = Vector3.new(0, -workspace.Gravity * FLOW_GRAVITY_FACTOR, 0)
        end
        e.Parent = part
        emitter = e
    end
    local sound: Sound? = nil
    if needsSound then
        local snd = Instance.new("Sound")
        snd.SoundId = look.loopSoundId
        snd.Looped = true
        snd.Volume = SOUND_VOLUME
        snd.RollOffMaxDistance = SOUND_MAX_DISTANCE
        snd.Parent = part
        sound = snd
    end
    return part, localCFrame, emitter, sound
end

local function buildEntry(player: Player, toolId: string, animated: boolean, variantId: string): Entry
    local look = ToolLook.of(toolId)
    local variant = ItemLooks.byId[variantId]
    if variant ~= nil and variant.kind ~= "toolVariant" then
        variant = nil
    end
    local model = Instance.new("Model")
    model.Name = player.Name

    local parts: { BasePart } = {}
    local baseSizes: { Vector3 } = {}
    local baseCFrames: { CFrame } = {}
    for index, spec in look.parts do
        local part = Instance.new("Part")
        part.Name = `Part{index}` -- Controllers/FirstPerson blendet Teile vor den Augen über die Nummer aus
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = true
        part.Color = colorOf(spec.colorHex)
        part.Material = materialOf(spec.material)
        if variant ~= nil then
            part.Color = part.Color:Lerp(colorOf(variant.colorHex), VARIANT_TINT)
            part.Material = materialOf(variant.material)
        end
        if spec.shape == "Ball" then
            part.Shape = Enum.PartType.Ball
        elseif spec.shape == "Cylinder" then
            part.Shape = Enum.PartType.Cylinder
        else
            part.Shape = Enum.PartType.Block
        end
        local size = Vector3.new(spec.size.x, spec.size.y, spec.size.z)
        part.Size = size
        part.Parent = model
        table.insert(parts, part)
        table.insert(baseSizes, size)
        table.insert(baseCFrames, CFrame.new(spec.offset.x, spec.offset.y, spec.offset.z) * angles(spec.rotation))
    end
    local flowPart, flowCFrame, emitter, sound = newFlow(look, model)

    local startScale = if animated and #parts > 0 then ToolLooks.change.popStartScale else 1
    local entry: Entry = {
        toolId = toolId,
        variantId = if variant ~= nil then variantId else "",
        look = look,
        model = model,
        parts = parts,
        baseSizes = baseSizes,
        baseCFrames = baseCFrames,
        flowPart = flowPart,
        flowCFrame = flowCFrame,
        emitter = emitter,
        sound = sound,
        popStart = if startScale < 1 then os.clock() else nil,
        popScale = startScale,
        lastScale = -1,
        nextFarUpdate = 0,
        castShadow = true,
    }
    model.Parent = folder
    return entry
end

local function applyCamera(look: any, animated: boolean)
    -- In der Ego-Perspektive bleibt die Kamera im Kopf (Controllers/FirstPerson), große Maschinen
    -- werden dort vor den Augen durchscheinend statt die Kamera zurückzuziehen.
    if FirstPersonData.enabled then
        return
    end
    local target = BASE_MIN_ZOOM + look.cameraBonusStuds
    if cameraTween ~= nil then
        cameraTween:Cancel()
        cameraTween = nil
    end
    if localPlayer.CameraMaxZoomDistance < target then
        localPlayer.CameraMaxZoomDistance = target + 8
    end
    if not animated then
        localPlayer.CameraMinZoomDistance = target
        return
    end
    cameraTween = TweenService:Create(
        localPlayer,
        TweenInfo.new(ToolLooks.change.cameraSeconds, CAMERA_EASING, Enum.EasingDirection.Out),
        { CameraMinZoomDistance = target }
    )
    cameraTween:Play()
end

local function burst(look: any, at: CFrame)
    local anchor = Instance.new("Part")
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.CFrame = at
    local emitter = Instance.new("ParticleEmitter")
    emitter.Enabled = false
    emitter.Texture = FLOW_TEXTURE
    emitter.Lifetime = BURST_LIFETIME
    emitter.Speed = BURST_SPEED
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Size = NumberSequence.new(look.dust.size * BURST_SIZE_FACTOR)
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Color = ColorSequence.new(SAND_COLOR)
    emitter.Parent = anchor
    anchor.Parent = folder
    emitter:Emit(math.max(1, math.ceil(ToolLooks.change.burstCount * Graphics.settings().particleFactor)))
    task.delay(BURST_LIFETIME.Max + 0.2, function()
        anchor:Destroy()
    end)
end

-- Lage eines Teils mit Bewegung zur Zeit t. `base` ist die Ruhelage relativ zum Boden.
local function moved(base: CFrame, motion: any, t: number): CFrame
    local value = ToolLook.motionAt(motion, t)
    if motion.kind == "swing" or motion.kind == "spin" then
        local rotation = CFrame.fromAxisAngle(axisVector(motion.axis), math.rad(value))
        return base * rotation
    elseif motion.kind == "bob" then
        return CFrame.new(axisVector(motion.axis) * value) * base
    elseif motion.kind == "slide" then
        local v = motion.vector
        local dir = Vector3.new(v.x, v.y, v.z)
        return CFrame.new((if dir.Magnitude > 1e-4 then dir.Unit else Vector3.yAxis) * value) * base
    end
    return base
end

local function updateEntry(player: Player, entry: Entry, root: BasePart, humanoid: Humanoid, now: number)
    local view = ToolLooks.view
    local graphics = Graphics.settings()
    local camera = workspace.CurrentCamera
    local near = camera == nil or (camera.CFrame.Position - root.Position).Magnitude <= view.motionDistanceStuds * graphics.motionDistanceFactor
    if not near and now < entry.nextFarUpdate then
        return
    end
    entry.nextFarUpdate = now + view.farUpdateSeconds

    -- Schatten fremder Werkzeuge nur auf "hoch" (das eigene Werkzeug behält seinen Schatten).
    local shadows = graphics.toolShadows == true or player == localPlayer
    if entry.castShadow ~= shadows then
        entry.castShadow = shadows
        for _, part in entry.parts do
            part.CastShadow = shadows
        end
    end

    -- Herauswachsen
    if entry.popStart ~= nil then
        local alpha = math.clamp((now - entry.popStart) / ToolLooks.change.popSeconds, 0, 1)
        local style = (Enum.EasingStyle :: any)[ToolLooks.change.popEasing] or Enum.EasingStyle.Back
        local eased = TweenService:GetValue(alpha, style, Enum.EasingDirection.Out)
        local start = ToolLooks.change.popStartScale
        entry.popScale = start + (1 - start) * eased
        if alpha >= 1 then
            entry.popScale = 1
            entry.popStart = nil
        end
    end
    local scale = entry.popScale
    if scale ~= entry.lastScale then
        for index, part in entry.parts do
            part.Size = entry.baseSizes[index] * scale
        end
        entry.lastScale = scale
    end

    local collecting = near and player:GetAttribute("Collecting") == true
    local flowOn = collecting and graphics.sandFlow == true
    local ground = groundFrame(root, humanoid)
    local cframes: { CFrame } = table.create(#entry.parts)
    for index, base in entry.baseCFrames do
        cframes[index] = base
    end
    if collecting then
        for _, motion in entry.look.motions do
            local index = motion.part
            if entry.baseCFrames[index] ~= nil then
                cframes[index] = moved(entry.baseCFrames[index], motion, now)
            end
        end
    end
    for index, cf in cframes do
        local position = cf.Position * scale
        cframes[index] = ground * (CFrame.new(position) * (cf - cf.Position))
    end
    local list: { BasePart } = table.clone(entry.parts)
    if entry.flowPart ~= nil then
        table.insert(list, entry.flowPart)
        local fp = entry.flowCFrame
        local flowWorld = ground * (CFrame.new(fp.Position * scale) * (fp - fp.Position))
        -- Ego-Perspektive: Beim eigenen Charakter beginnt der Sandfluss dort, wo gerade gegraben
        -- wird (Fadenkreuz, Controllers/Dig), und fliegt zur Maschine.
        local aim = if player == localPlayer then Dig.aimPoint() else nil
        if aim ~= nil then
            local flow = entry.look.sandFlow
            local toWorld = ground * Vector3.new(flow.to.x * scale, flow.to.y * scale, flow.to.z * scale)
            local dir = toWorld - aim
            flowWorld = CFrame.new(aim) * alignY(if dir.Magnitude > 1e-4 then dir.Unit else Vector3.yAxis)
            if entry.emitter ~= nil then
                local speed = DigAim.flowSpeed(dir.Magnitude, flow.lifetime, flow.speed)
                entry.emitter.Speed = NumberRange.new(speed * 0.8, speed)
            end
        elseif entry.emitter ~= nil and player == localPlayer then
            local flow = entry.look.sandFlow
            entry.emitter.Speed = NumberRange.new(flow.speed * 0.8, flow.speed)
        end
        table.insert(cframes, flowWorld)
    end
    if #list > 0 then
        workspace:BulkMoveTo(list, cframes, Enum.BulkMoveMode.FireCFrameChanged)
    end
    if entry.emitter ~= nil then
        entry.emitter.Rate = entry.look.sandFlow.rate * graphics.particleFactor
        entry.emitter.Enabled = flowOn
    end
    if entry.sound ~= nil then
        entry.sound.Playing = collecting
    end
end

local function onFrame()
    local now = os.clock()
    for _, player in Players:GetPlayers() do
        local toolId = player:GetAttribute("ToolId")
        local root, humanoid = rootOf(player)
        if type(toolId) ~= "string" or root == nil or humanoid == nil then
            -- Noch nicht bereit oder tot: Modell entfernen, bei Rückkehr neu bauen.
            destroyEntry(player)
            continue
        end
        local entry = entries[player]
        local change = ToolLook.change(if entry ~= nil then entry.toolId else nil, toolId)
        local variantAttribute = player:GetAttribute("ToolVariantId")
        local variantLook = if type(variantAttribute) == "string" then ItemLooks.byId[variantAttribute] else nil
        local variantId = if variantLook ~= nil and variantLook.kind == "toolVariant" then variantLook.id else ""
        if entry == nil or change ~= "none" or entry.variantId ~= variantId then
            local animated = change == "upgrade"
            destroyEntry(player)
            entry = buildEntry(player, toolId, animated, variantId)
            entries[player] = entry
            if animated then
                burst(entry.look, groundFrame(root, humanoid) * CFrame.new(entry.look.workPoint.x, 1, entry.look.workPoint.z))
            end
            if player == localPlayer then
                applyCamera(entry.look, animated)
            end
        end
        updateEntry(player, entry :: Entry, root, humanoid, now)
    end
end

function ToolVisual.Init() end

function ToolVisual.Start()
    local existing = workspace:FindFirstChild(FOLDER_NAME)
    if existing ~= nil then
        existing:Destroy()
    end
    local f = Instance.new("Folder")
    f.Name = FOLDER_NAME
    f.Parent = workspace
    folder = f
    Players.PlayerRemoving:Connect(destroyEntry)
    RunService.Heartbeat:Connect(function()
        local ok, err = pcall(onFrame)
        if not ok then
            warn("[ToolVisual] " .. tostring(err))
        end
    end)
end

return ToolVisual
