--!strict
-- Bind local sand effects to the exported starter work loops.
local RunService = game:GetService("RunService")
local DEFAULT_TINT = Color3.fromRGB(225, 183, 115)
local GRAVITY = Vector3.new(0, -21, 0)
local FOLLOW_UP_SECONDS = 0.054

local profiles = {
    Hand = {
        cut = "HandSandTouch",
        loaded = "HandLoaded",
        dump = "HandDeposit",
        dustCount = 3,
        cutCount = 7,
        pourCount = 9,
        followUp = { 5, 3 },
    },
    Shovel = {
        cut = "SpadeCut",
        loaded = "SpadeLoaded",
        dump = "SpadeDump",
        dustCount = 5,
        cutCount = 12,
        pourCount = 17,
        followUp = { 9, 5 },
    },
}

type Tool = "Hand" | "Shovel"
local bound: { [Attachment]: () -> () } = {}
local StarterSandFX = {}

function StarterSandFX.Bind(
    tool: Tool,
    workTrack: AnimationTrack,
    source: Attachment,
    sandTint: Color3?,
    receiver: Attachment?
): () -> ()
    assert(RunService:IsClient(), "Bind starter sand art on the client")
    local parent = source.Parent
    assert(
        parent and parent:IsA("BasePart") and source:IsDescendantOf(workspace),
        "Sand contact attachment is missing"
    )
    if bound[source] then
        bound[source]()
    end
    local profile = profiles[tool]
    local tint = sandTint or DEFAULT_TINT
    local shadow = tint:Lerp(Color3.new(0, 0, 0), 0.21)
    local highlight = tint:Lerp(Color3.fromRGB(255, 242, 207), 0.30)
    local fx = Instance.new("Folder")
    fx.Name = "LocalStarterSandFX"

    local load = (script:FindFirstChild(tool .. "Load") :: Folder):Clone()
    local clumps: { BasePart } = {}
    for _, piece in load:GetChildren() do
        if piece:IsA("BasePart") then
            local relative = source.CFrame * piece.CFrame
            piece.CFrame = parent.CFrame * relative
            local shade = piece:GetAttribute("Tone")
            piece.Color = if shade == "shadow"
                then shadow
                elseif shade == "highlight" then highlight
                else tint
            local joint = Instance.new("Weld")
            joint.Name = "LoadWeld"
            joint.Part0, joint.Part1 = parent, piece
            joint.C0, joint.C1 = relative, CFrame.identity
            joint.Parent = piece
            table.insert(clumps, piece)
        end
    end
    load.Parent = fx
    local cut = (script:FindFirstChild("CutOrigin") :: BasePart):Clone()
    local pour = (script:FindFirstChild("PourOrigin") :: BasePart):Clone()
    local dust = cut:FindFirstChild("Dust") :: ParticleEmitter
    local grains = cut:FindFirstChild("Grains") :: ParticleEmitter
    local stream = pour:FindFirstChild("Stream") :: ParticleEmitter
    dust.Color = ColorSequence.new(tint, highlight)
    grains.Color = ColorSequence.new(highlight, shadow)
    stream.Color = ColorSequence.new(highlight, tint)
    cut.Parent, pour.Parent = fx, fx
    fx.Parent = source

    local loaded, disposed = false, false
    local revision = 0
    local connections: { RBXScriptConnection } = {}
    local groundRay = RaycastParams.new()
    groundRay.FilterType = Enum.RaycastFilterType.Include
    groundRay.FilterDescendantsInstances = { workspace.Terrain }
    groundRay.IgnoreWater = true

    local function showLoad(visible: boolean)
        loaded = visible
        for _, piece in clumps do
            piece.Transparency = if visible then 0 else 1
        end
    end

    local function reset()
        revision += 1
        showLoad(false)
        dust:Clear()
        grains:Clear()
        stream:Clear()
    end

    local function emitPour(count: number)
        local origin = source.WorldPosition
        local flight = 0.27
        local delta = receiver
            and receiver:IsDescendantOf(workspace)
            and (receiver.WorldPosition - origin)
        if typeof(delta) == "Vector3" and delta.Magnitude >= 0.15 and delta.Magnitude <= 6 then
            flight = math.clamp(0.20 + delta.Magnitude * 0.035, 0.21, 0.37)
        else
            delta = Vector3.new(0, -1.32, 0.06)
        end
        local velocity = delta / flight - GRAVITY * (flight * 0.5)
        if velocity.Magnitude < 0.08 then
            velocity = Vector3.new(0, -0.08, 0)
        end
        local direction = velocity.Unit
        local vectorUp = if math.abs(direction.Y) > 0.95 then Vector3.zAxis else Vector3.yAxis
        pour.CFrame = CFrame.lookAt(origin, origin + direction, vectorUp)
        stream.Speed = NumberRange.new(velocity.Magnitude * 0.93, velocity.Magnitude * 1.07)
        stream.Lifetime = NumberRange.new(flight * 0.88, flight * 1.05)
        stream:Emit(count)
    end

    local function active(): boolean
        return not disposed and workTrack.IsPlaying and source:IsDescendantOf(workspace)
    end

    local function on(name: string, callback: () -> ())
        table.insert(
            connections,
            workTrack:GetMarkerReachedSignal(name):Connect(function()
                if active() then
                    callback()
                end
            end)
        )
    end

    on(profile.cut, function()
        reset()
        local origin = source.WorldPosition
        local hit =
            workspace:Raycast(origin + Vector3.new(0, 0.13, 0), Vector3.new(0, -1.32, 0), groundRay)
        cut.CFrame = CFrame.new(if hit then hit.Position + Vector3.new(0, 0.042, 0) else origin)
        dust:Emit(profile.dustCount)
        grains:Emit(profile.cutCount)
    end)
    on(profile.loaded, function()
        showLoad(true)
    end)
    on(profile.dump, function()
        if not loaded then
            return
        end
        showLoad(false)
        revision += 1
        local pourRevision = revision
        emitPour(profile.pourCount)
        for i, count in profile.followUp do
            task.delay(FOLLOW_UP_SECONDS * i, function()
                if active() and revision == pourRevision then
                    emitPour(count)
                end
            end)
        end
    end)
    table.insert(connections, workTrack.Stopped:Connect(reset))

    local function release()
        if disposed then
            return
        end
        disposed = true
        for _, connection in connections do
            connection:Disconnect()
        end
        fx:Destroy()
        bound[source] = nil
    end
    table.insert(
        connections,
        source.AncestryChanged:Connect(function()
            if not source:IsDescendantOf(workspace) then
                release()
            end
        end)
    )
    bound[source] = release
    return release
end

return StarterSandFX
