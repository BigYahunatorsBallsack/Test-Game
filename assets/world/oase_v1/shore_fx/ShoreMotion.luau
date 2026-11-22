--!strict
-- Client-side scenery for Oasis V1.
local RunService = game:GetService("RunService")
local MAX_DISTANCE = 72
local UPDATE_INTERVAL = 1 / 24
local DOCK_POINTS = { Vector2.new(320.7, 608.9), Vector2.new(309.3, 612.4) }
local mounted: { [Instance]: () -> () } = {}

type Ring = {
    holder: BasePart,
    surface: SurfaceGui,
    frame: Frame,
    stroke: UIStroke,
    cadence: number,
    phase: number,
    maxAlpha: number,
}

local function addRing(
    parent: Instance,
    position: Vector3,
    size: number,
    cadence: number,
    phase: number,
    maxAlpha: number
): Ring
    local holder = (script:FindFirstChild("Ripple") :: BasePart):Clone()
    holder.Size = Vector3.new(size, 0.05, size)
    holder.CFrame = CFrame.new(position)
    holder.Parent = parent
    local surface = holder:FindFirstChild("RingSurface") :: SurfaceGui
    local frame = surface:FindFirstChild("Ring") :: Frame
    return {
        holder = holder,
        surface = surface,
        frame = frame,
        stroke = frame:FindFirstChild("Line") :: UIStroke,
        cadence = cadence,
        phase = phase,
        maxAlpha = maxAlpha,
    }
end

local function animateRing(ring: Ring, elapsed: number, eye: Vector3?)
    local visible = eye ~= nil and (eye - ring.holder.CFrame.Position).Magnitude <= MAX_DISTANCE
    ring.surface.Enabled = visible
    if visible then
        local t = (elapsed / ring.cadence + ring.phase) % 1
        local diameter = 0.21 + 0.72 * (1 - (1 - t) ^ 1.36)
        ring.frame.Size = UDim2.fromScale(diameter, diameter)
        ring.stroke.Transparency = 1 - ring.maxAlpha * math.sin(t * math.pi) ^ 1.38
    end
end

local ShoreMotion = {}

function ShoreMotion.Mount(art: Folder, springSoundId: string?): () -> ()
    assert(RunService:IsClient(), "Mount oasis scenery on the client")
    local structures = art:FindFirstChild("Structures")
    local terrace = structures and structures:FindFirstChild("OldSpringTerrace")
    local tiles = terrace and terrace:FindFirstChild("Old Turquoise Tiles")
    local spout = terrace and terrace:FindFirstChild("Broken Water Spout")
    assert(
        tiles and tiles:IsA("BasePart") and spout and spout:IsA("BasePart"),
        "Oasis V1 terrace is required"
    )
    assert(art:IsDescendantOf(workspace), "Oasis art must be in Workspace")
    if mounted[art] then
        mounted[art]()
    end

    local effects = Instance.new("Folder")
    effects.Name = "LocalShoreFX"
    local source = (script:FindFirstChild("Spring") :: BasePart):Clone()
    source.CFrame = tiles.CFrame * CFrame.new(0, tiles.Size.Y / 2 + 0.075, 0)
    source.Parent = effects

    local start = source:FindFirstChild("Spout") :: Attachment
    local impact = source:FindFirstChild("SurfaceImpact") :: Attachment
    local face = spout.CFrame * CFrame.new(0, -0.22, -spout.Size.Z / 2)
    local lip = face:PointToWorldSpace(Vector3.new(0, 0, -0.115))
    start.CFrame = CFrame.fromMatrix(
        source.CFrame:PointToObjectSpace(lip),
        Vector3.new(0, -0.5, -1).Unit,
        Vector3.xAxis
    )
    local body = source:FindFirstChild("Trickle") :: Beam
    local highlight = source:FindFirstChild("Highlight") :: Beam
    local drops = impact:FindFirstChild("Splash") :: ParticleEmitter
    local sound = impact:FindFirstChild("Platschen") :: Sound
    if springSoundId and springSoundId ~= "" then
        sound.SoundId = springSoundId
    end

    local sheen = (script:FindFirstChild("Pool") :: BasePart):Clone()
    sheen.Size = Vector3.new(tiles.Size.X - 0.2, 0.055, tiles.Size.Z - 0.2)
    sheen.CFrame = source.CFrame * CFrame.new(0, -0.035, 0)
    sheen.Parent = effects
    local support = (script:FindFirstChild("SpoutSupport") :: BasePart):Clone()
    support.CFrame = spout.CFrame * CFrame.new(0, -0.88, 0.22)
    support.Parent = effects
    for _, name in { "GlazedOutlet", "OutletOpening" } do
        local fitting = (script:FindFirstChild(name) :: BasePart):Clone()
        local depth = if name == "GlazedOutlet" then 0.035 else 0.083
        fitting.CFrame = face * CFrame.new(0, 0, -depth) * CFrame.Angles(0, math.pi / 2, 0)
        fitting.Parent = effects
    end
    local springRing = addRing(
        effects,
        source.CFrame:PointToWorldSpace(impact.CFrame.Position),
        1.7,
        2.15,
        0,
        0.42
    )

    local wet = RaycastParams.new()
    wet.FilterType = Enum.RaycastFilterType.Include
    wet.FilterDescendantsInstances = { workspace.Terrain }
    wet.IgnoreWater = false
    local dockRings: { Ring } = {}
    for i, point in DOCK_POINTS do
        local hit =
            workspace:Raycast(Vector3.new(point.X, 96, point.Y), Vector3.new(0, -120, 0), wet)
        if hit and hit.Material == Enum.Material.Water then
            local surface = hit.Position + Vector3.new(0, 0.07, 0)
            table.insert(dockRings, addRing(effects, surface, 6.7, 5.3 + i * 0.45, i * 0.27, 0.36))
            table.insert(
                dockRings,
                addRing(
                    effects,
                    surface + Vector3.new(0, 0.009, 0),
                    4.7,
                    5.3 + i * 0.45,
                    0.43 + i * 0.27,
                    0.24
                )
            )
        end
    end

    local elapsed = 0
    local tick = 0
    local streamVisible = false
    local connection: RBXScriptConnection?
    local function destroy()
        if connection then
            connection:Disconnect()
            connection = nil
        end
        effects:Destroy()
        mounted[art] = nil
    end

    effects.Parent = art
    if sound.SoundId ~= "" then
        sound:Play()
    end
    connection = RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        tick += dt
        if tick < UPDATE_INTERVAL then
            return
        end
        tick %= UPDATE_INTERVAL
        if
            not art:IsDescendantOf(workspace)
            or not tiles:IsDescendantOf(art)
            or not spout:IsDescendantOf(art)
        then
            destroy()
            return
        end
        local camera = workspace.CurrentCamera
        local eye = camera and camera.CFrame.Position
        local close = eye ~= nil and (eye - source.CFrame.Position).Magnitude <= MAX_DISTANCE
        if close ~= streamVisible then
            streamVisible = close
            body.Enabled, highlight.Enabled, drops.Enabled = close, close, close
        end
        if close then
            highlight.Width0 = 0.115 + 0.014 * math.sin(elapsed * 8.2)
        end
        animateRing(springRing, elapsed, eye)
        for _, ring in dockRings do
            animateRing(ring, elapsed, eye)
        end
    end)

    mounted[art] = destroy
    return function()
        if mounted[art] == destroy then
            destroy()
        end
    end
end

return ShoreMotion
