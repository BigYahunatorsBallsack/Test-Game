--!strict
-- Dig-Controller (Paket 1.4)
-- Gräbt Mulden ins Terrain, solange der Spieler sammelt, nur auf diesem Client. Terrain-
-- Änderungen eines Clients erreichen weder den Server noch andere Spieler, der Server zählt
-- den Sand unabhängig davon (Sand-Service). Die Regeln (welche Blöcke, wie tief, wann
-- nachwachsen) stehen in Logic/SandDig, die Zahlen in Data/Terrain. Hier werden nur Voxel
-- gelesen und geschrieben, Partikel gezeigt und die Rückfallvariante gezeichnet.
-- Ego-Perspektive: Das Loch entsteht dort, wohin Fadenkreuz oder freie Maus zeigen (Logic/DigAim),
-- begrenzt auf die Reichweite des Werkzeugs, nicht mehr fest vor dem Charakter.
--
-- Modi: "full" verformt das Terrain. "fallback" (schwaches Gerät, Logic/PerfGuard) lässt das
-- Terrain in Ruhe und zeigt nur eine sinkende Sandscheibe und Partikel.
-- Zum Testen in der Client-Befehlszeile:
--   game.Players.LocalPlayer:SetAttribute("DigMode", "fallback")  -- oder "full", nil = automatisch

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- Partikel
local PARTICLE_COUNT_FALLBACK = 14
local PARTICLE_LIFETIME = NumberRange.new(0.35, 0.7)
local PARTICLE_SPEED = NumberRange.new(5, 11)
local PARTICLE_SPREAD_DEGREES = 55
local PARTICLE_SIZE_START_FACTOR = 1 -- Startgröße = Staubgröße der Stufe (Data/ToolLooks)
local PARTICLE_SIZE_END_FACTOR = 0.33
local PARTICLE_TRANSPARENCY = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.1),
    NumberSequenceKeypoint.new(1, 1),
})
local PARTICLE_GRAVITY_FACTOR = 0.6
local PARTICLE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- Rückfallvariante: sinkende Sandscheibe
local DISC_THICKNESS = 0.2
local DISC_START_DIAMETER = 0.4
local DISC_GROW_SECONDS = 0.25
local DISC_GROW_EASING = Enum.EasingStyle.Quad
local DISC_SINK_STUDS = 0.12
local DISC_DARKEN = 0.25 -- Anteil Schwarz in der Farbe der Scheibe
local DISC_FADE_SECONDS = 1.2
local DISC_FADE_EASING = Enum.EasingStyle.Sine
local MAX_DISCS = 24

-- Anzeige für den Handy-Test (Platz im HUD-Stapel aus Data/Screen: lines.debugY)
local OVERLAY_REFRESH_SECONDS = 0.5
local OVERLAY_TEXT_COLOR = Color3.fromRGB(255, 248, 230)

local DIG_MODE_ATTRIBUTE = "DigMode"
local TOOL_MODELS_FOLDER = "ToolModels" -- Ordner von Controllers/ToolVisual, Teile blockieren den Strahl nicht
local DEFAULT_SAND_COLOR = Color3.fromRGB(230, 200, 117)

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local TerrainData = loadShared("Data", "Terrain")
local Zones = loadShared("Data", "Zones")
local SandTypes = loadShared("Data", "SandTypes")
local SandDig = loadShared("Logic", "SandDig")
local PerfGuard = loadShared("Logic", "PerfGuard")
local ToolLook = loadShared("Logic", "ToolLook")
local BigNum = loadShared("Logic", "BigNum")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Input = require(script.Parent:WaitForChild("Input") :: ModuleScript) :: any
local Graphics = require(script.Parent:WaitForChild("Graphics") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any
local FirstPerson = require(script.Parent:WaitForChild("FirstPerson") :: ModuleScript) :: any
local DigAim = loadShared("Logic", "DigAim")
local FirstPersonData = loadShared("Data", "FirstPerson")

local VOXEL = TerrainData.voxelSize
local CHUNK = TerrainData.chunkSize
local AIR = Enum.Material.Air

local Dig = {}

local player = Players.LocalPlayer
local terrain = workspace.Terrain
local digState: any = nil
local perf: any = nil
-- Originalzustand je Block (Schlüssel aus SandDig.chunkKey).
local baselines: { [string]: any } = {}
local diggable: { [any]: boolean } = {}
local discs: { BasePart } = {}
local discFolder: Folder? = nil
local emitter: ParticleEmitter? = nil
local emitterAttachment: Attachment? = nil
local lastMode = "full"
local errorsShown = 0
local MAX_ERRORS_SHOWN = 5

local function vec(v: Vector3): any
    return { x = v.X, y = v.Y, z = v.Z }
end

local function regionOf(cx: number, cy: number, cz: number): Region3
    local o = SandDig.chunkOrigin(TerrainData, cx, cy, cz)
    local min = Vector3.new(o.x, o.y, o.z)
    return Region3.new(min, min + Vector3.new(CHUNK, CHUNK, CHUNK))
end

local function readGrid(cx: number, cy: number, cz: number): any
    local materials, occupancies = terrain:ReadVoxels(regionOf(cx, cy, cz), VOXEL)
    return {
        origin = SandDig.chunkOrigin(TerrainData, cx, cy, cz),
        n = CHUNK // VOXEL,
        voxelSize = VOXEL,
        occ = occupancies,
        mat = materials,
    }
end

local function writeGrid(cx: number, cy: number, cz: number, grid: any)
    terrain:WriteVoxels(regionOf(cx, cy, cz), VOXEL, grid.mat, grid.occ)
end

local function sandColor(): Color3
    local snapshot = State.get()
    local zone = if snapshot ~= nil then Zones.byId[snapshot.zoneId] else nil
    local sandType = if zone ~= nil then SandTypes.byId[zone.sandTypeId] else nil
    if sandType == nil then
        return DEFAULT_SAND_COLOR
    end
    return Color3.fromHex(sandType.colorHex)
end

local function aliveRoot(): BasePart?
    local character = player.Character
    if character == nil then
        return nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
        return nil
    end
    return root
end

-- Gräbt der Spieler gerade? Nur wenn er hält und der Server das Sammeln bestätigt hat
-- (nicht am Stand, nicht tot, Tank nicht voll).
local function wantsDig(): boolean
    if not Input.isHolding() then
        return false
    end
    local snapshot = State.get()
    if snapshot == nil or not snapshot.collecting then
        return false
    end
    local tank = BigNum.deserialize(snapshot.tank)
    return BigNum.lt(tank, BigNum.new(snapshot.capacity))
end

local function rayParams(): RaycastParams
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude: { Instance } = {}
    if player.Character ~= nil then
        table.insert(exclude, player.Character)
    end
    if discFolder ~= nil then
        table.insert(exclude, discFolder)
    end
    local toolModels = workspace:FindFirstChild(TOOL_MODELS_FOLDER)
    if toolModels ~= nil then
        table.insert(exclude, toolModels)
    end
    params.FilterDescendantsInstances = exclude
    params.IgnoreWater = true
    return params
end

-- Wohin zeigt der Spieler? Strahl aus der Kamera durch das Fadenkreuz (Bildmitte), bei freier Maus
-- durch den Mauszeiger. Gibt den Treffer waagrecht zurück, nil = nichts getroffen (Himmel).
local function aimHit(params: RaycastParams): any?
    local camera = workspace.CurrentCamera
    if camera == nil then
        return nil
    end
    local ray: Ray
    if FirstPerson.isCursorFree() then
        local mouse = UserInputService:GetMouseLocation()
        ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
    else
        local size = camera.ViewportSize
        ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
    end
    local result = workspace:Raycast(ray.Origin, ray.Direction.Unit * FirstPersonData.aim.rayLengthStuds, params)
    if result == nil then
        return nil
    end
    return { x = result.Position.X, z = result.Position.Z }
end

-- Trefferpunkt auf grabbarem Terrain dort, wohin der Spieler zielt (begrenzt auf die Reichweite
-- des Werkzeugs, Logic/DigAim), sonst nil.
local function findGround(root: BasePart, toolId: string?): RaycastResult?
    local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
    local dig = TerrainData.dig
    local params = rayParams()
    local target = DigAim.target(
        { x = root.Position.X, z = root.Position.Z },
        { x = look.X, z = look.Z },
        aimHit(params),
        DigAim.reach(toolId)
    )
    if target == nil then
        return nil
    end
    local origin = Vector3.new(target.x, root.Position.Y + dig.rayUpStuds, target.z)
    local result = workspace:Raycast(origin, Vector3.new(0, -dig.rayLengthStuds, 0), params)
    if result == nil or result.Instance ~= terrain or not diggable[result.Material] then
        return nil
    end
    return result
end

local function emitParticles(position: Vector3, count: number, toolId: string?)
    if emitter == nil or emitterAttachment == nil then
        return
    end
    local size = ToolLook.of(toolId).dust.size
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, size * PARTICLE_SIZE_START_FACTOR),
        NumberSequenceKeypoint.new(1, size * PARTICLE_SIZE_END_FACTOR),
    })
    emitterAttachment.WorldPosition = position
    emitter.Color = ColorSequence.new(sandColor())
    emitter:Emit(count)
end

local function digTerrain(now: number, hit: RaycastResult, toolId: string?, zoneId: string?)
    local result = SandDig.tryDig(digState, now, vec(hit.Position), toolId, zoneId)
    if result == nil then
        return
    end
    for _, ref in result.chunks do
        if ref.isNew then
            baselines[ref.key] = readGrid(ref.cx, ref.cy, ref.cz)
        end
        local grid = readGrid(ref.cx, ref.cy, ref.cz)
        if SandDig.carve(grid, result.center, result.radius, result.floorY, AIR, diggable) then
            writeGrid(ref.cx, ref.cy, ref.cz, grid)
        elseif ref.isNew then
            -- Block lag nur in der Luft oder im Fels: nicht merken.
            SandDig.forget(digState, ref.key)
            baselines[ref.key] = nil
        end
    end
    -- Auf schlanker Grafikstufe weniger Staub (mindestens ein Partikel).
    local dust = math.max(1, math.ceil(ToolLook.dustCount(toolId) * Graphics.settings().particleFactor))
    emitParticles(hit.Position, dust, toolId)
end

local function regrowChunk(action: any)
    local baseline = baselines[action.key]
    if baseline == nil then
        return
    end
    local grid = readGrid(action.cx, action.cy, action.cz)
    SandDig.blend(grid, baseline, action.t, AIR)
    writeGrid(action.cx, action.cy, action.cz, grid)
    if action.final then
        baselines[action.key] = nil
    end
end

local function digFallback(now: number, hit: RaycastResult, toolId: string?)
    if not SandDig.takeDigSlot(digState, now) or discFolder == nil then
        return
    end
    local hole = SandDig.holeFor(TerrainData, toolId)
    -- Breite der Mulde an der Oberfläche (Kugelkappe mit Tiefe hole.depth).
    local r = hole.radius
    local d = math.min(hole.depth, r)
    local diameter = 2 * math.sqrt(r * r - (r - d) * (r - d))

    if #discs >= MAX_DISCS then
        local oldest = table.remove(discs, 1)
        if oldest ~= nil then
            oldest:Destroy()
        end
    end
    local disc = Instance.new("Part")
    disc.Name = "DigMark"
    disc.Shape = Enum.PartType.Cylinder
    disc.Anchored = true
    disc.CanCollide = false
    disc.CanQuery = false
    disc.CanTouch = false
    disc.CastShadow = false
    disc.Material = Enum.Material.Sand
    disc.Color = sandColor():Lerp(Color3.new(0, 0, 0), DISC_DARKEN)
    disc.Size = Vector3.new(DISC_THICKNESS, DISC_START_DIAMETER, DISC_START_DIAMETER)
    local flat = CFrame.Angles(0, 0, math.pi / 2) -- Zylinderachse nach oben
    local top = hit.Position + Vector3.new(0, DISC_THICKNESS / 2 - 0.02, 0)
    disc.CFrame = CFrame.new(top) * flat
    disc.Parent = discFolder
    table.insert(discs, disc)

    TweenService:Create(disc, TweenInfo.new(DISC_GROW_SECONDS, DISC_GROW_EASING, Enum.EasingDirection.Out), {
        Size = Vector3.new(DISC_THICKNESS, diameter, diameter),
        CFrame = CFrame.new(top - Vector3.new(0, DISC_SINK_STUDS, 0)) * flat,
    }):Play()
    local regrow = TerrainData.regrow
    task.delay(regrow.delaySeconds + regrow.seconds, function()
        if disc.Parent == nil then
            return
        end
        local fade = TweenService:Create(disc, TweenInfo.new(DISC_FADE_SECONDS, DISC_FADE_EASING), { Transparency = 1 })
        fade.Completed:Connect(function()
            local index = table.find(discs, disc)
            if index ~= nil then
                table.remove(discs, index)
            end
            disc:Destroy()
        end)
        fade:Play()
    end)
    emitParticles(hit.Position, PARTICLE_COUNT_FALLBACK, toolId)
end

local function readForcedMode()
    local value = player:GetAttribute(DIG_MODE_ATTRIBUTE)
    if value == "full" or value == "fallback" then
        PerfGuard.setForced(perf, value)
    elseif value == nil then
        PerfGuard.setForced(perf, nil)
    else
        warn(`[Dig] DigMode muss "full", "fallback" oder nil sein, nicht {tostring(value)}`)
    end
end

local function createEffects()
    local folder = Instance.new("Folder")
    folder.Name = "DigMarks"
    folder.Parent = workspace
    discFolder = folder

    local attachment = Instance.new("Attachment")
    attachment.Name = "DigParticles"
    attachment.Parent = terrain
    emitterAttachment = attachment

    local e = Instance.new("ParticleEmitter")
    e.Enabled = false
    e.Rate = 0
    e.Texture = PARTICLE_TEXTURE
    e.Lifetime = PARTICLE_LIFETIME
    e.Speed = PARTICLE_SPEED
    e.SpreadAngle = Vector2.new(PARTICLE_SPREAD_DEGREES, PARTICLE_SPREAD_DEGREES)
    e.EmissionDirection = Enum.NormalId.Top
    e.Size = NumberSequence.new(ToolLook.of(nil).dust.size)
    e.Transparency = PARTICLE_TRANSPARENCY
    e.Acceleration = Vector3.new(0, -workspace.Gravity * PARTICLE_GRAVITY_FACTOR, 0)
    e.LightInfluence = 1
    e.Parent = attachment
    emitter = e
end

local function createOverlay(): TextLabel
    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronDigDebug"
    gui.ResetOnSpawn = false
    local label = Instance.new("TextLabel")
    label.Name = "Info"
    label.BackgroundTransparency = 0.5
    label.BackgroundColor3 = Color3.new(0, 0, 0)
    label.Font = Enum.Font.Gotham
    label.TextScaled = true
    label.TextColor3 = OVERLAY_TEXT_COLOR
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = "Graben: ..."
    label.Parent = gui
    local function place(layout: any)
        local data = Screen.classData()
        label.Position = UDim2.fromOffset(layout.hud.x + data.hud.pad, data.lines.debugY)
        label.Size = UDim2.fromOffset(data.lines.w, data.lines.h)
    end
    place(Screen.layout())
    Screen.onLayoutChanged(place)
    gui.Parent = player:WaitForChild("PlayerGui")
    return label
end

local function overlayText(): string
    local mode = PerfGuard.mode(perf)
    local modeText = if mode == "full" then "Terrain" else "Rückfall"
    if perf.forced ~= nil then
        modeText ..= " (erzwungen)"
    end
    local fps = PerfGuard.fps(perf)
    local fpsText = if fps ~= nil then tostring(math.floor(fps + 0.5)) else "--"
    return `{modeText} | {fpsText} FPS | {SandDig.openCount(digState)}/{TerrainData.regrow.maxDirtyChunks} | {Graphics.level()}`
end

-- Läuft gerade die Rückfallvariante (schwaches Gerät)? ToolVisual spart dann den Sandfluss.
function Dig.isFallback(): boolean
    return perf ~= nil and PerfGuard.mode(perf) == "fallback"
end

function Dig.Init()
    -- Grabbar: die Materialien aus Terrain.diggableMaterials und das Terrain-Material jeder Sandsorte.
    local names: { string } = table.clone(TerrainData.diggableMaterials)
    for _, sandType in SandTypes.list do
        table.insert(names, sandType.terrainMaterial)
    end
    for _, name in names do
        local ok, material = pcall(function(): any
            return (Enum.Material :: any)[name]
        end)
        if ok and material ~= nil then
            diggable[material] = true
        else
            warn(`[Dig] Unbekanntes Material: {name}`)
        end
    end
end

function Dig.Start()
    local now = os.clock()
    digState = SandDig.new(TerrainData)
    perf = PerfGuard.new(TerrainData.perf, now)
    -- Der Rückfall des Wächters ist die Grafikstufe "minimal" (Paket 3.6).
    Graphics.setFallbackProvider(Dig.isFallback)
    Graphics.start()
    readForcedMode()
    player:GetAttributeChangedSignal(DIG_MODE_ATTRIBUTE):Connect(readForcedMode)
    createEffects()

    local overlay: TextLabel? = if TerrainData.debug.showOverlay then createOverlay() else nil
    local nextOverlayAt = 0

    RunService.Heartbeat:Connect(function(dt: number)
        local t = os.clock()
        local mode = PerfGuard.sample(perf, t, dt)
        if mode ~= lastMode then
            print(`[Dig] Modus: {mode}`)
            lastMode = mode
        end
        local root = aliveRoot()

        -- Nachwachsen läuft in beiden Modi weiter, damit offene Blöcke verschwinden.
        local ok, err = pcall(function()
            for _, action in SandDig.update(digState, t, if root ~= nil then vec(root.Position) else nil) do
                regrowChunk(action)
            end
            if root ~= nil and wantsDig() then
                local snapshot = State.get()
                local toolId = if snapshot ~= nil then snapshot.toolId else nil
                local hit = findGround(root, toolId)
                if hit ~= nil then
                    if mode == "full" then
                        digTerrain(t, hit, toolId, if snapshot ~= nil then snapshot.zoneId else nil)
                    else
                        digFallback(t, hit, toolId)
                    end
                end
            end
        end)
        if not ok and errorsShown < MAX_ERRORS_SHOWN then
            errorsShown += 1
            warn(`[Dig] Fehler: {tostring(err)}`)
        end

        if overlay ~= nil and t >= nextOverlayAt then
            nextOverlayAt = t + OVERLAY_REFRESH_SECONDS
            overlay.Text = overlayText()
        end
    end)
end

return Dig
