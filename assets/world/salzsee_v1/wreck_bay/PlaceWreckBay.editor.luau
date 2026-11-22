--!strict
-- Place the imported GLBs in the Salt Lake V1 art scene from Studio Edit.
local STUDIO_PLACE = 135831532782380
local OWNER = "DuneBaronWreckBayV2"
local ARCHIVE = "DuneBaronWrackbuchtV1"
local V, C, A = Vector3.new, CFrame.new, CFrame.Angles
local rad = math.rad

local run = game:GetService("RunService")
assert(
    run:IsStudio() and not run:IsRunning() and game.PlaceId == STUDIO_PLACE,
    "Use Every Last Grain in Studio Edit"
)
local world = assert(workspace:FindFirstChild("DuneBaronWorld"), "Dune Baron world missing")
local art = assert(world:FindFirstChild("SaltLakeArtV1"), "Salt Lake V1 art missing")
local landmarks = assert(art:FindFirstChild("Landmarks"), "Salt Lake landmarks missing")
local current = landmarks:FindFirstChild("Wrackbucht")
assert(current and current:IsA("Folder"), "The assembled Wrackbucht is required")
local storage = game:GetService("ServerStorage")
local library = assert(storage:FindFirstChild(OWNER), "Import the two Wrackbucht GLBs first")
local original = current:GetAttribute("Owner") ~= OWNER
assert(not original or not storage:FindFirstChild(ARCHIVE), "Original wreck archive already in use")

local waterline = world:GetAttribute("SaltLakeWaterLine")
assert(
    typeof(waterline) == "number" and math.abs(waterline - 16.2) < 0.1,
    "Salt Lake V1 waterline required"
)
local filter = RaycastParams.new()
filter.FilterType = Enum.RaycastFilterType.Include
filter.FilterDescendantsInstances = { workspace.Terrain }
filter.IgnoreWater = true
local ground =
    assert(workspace:Raycast(V(1286, 175, 790), V(0, -235, 0), filter), "Wreck ground missing")
assert(ground.Normal.Y >= 0.90 and ground.Position.Y > waterline + 2, "Wreck ground has changed")
local dockPose = C(1311, waterline, 796) * A(0, rad(18), 0)
local wetEnd = dockPose:PointToWorldSpace(V(0, 0, 6))
filter.IgnoreWater = false
local wet =
    assert(workspace:Raycast(wetEnd + V(0, 96, 0), V(0, -122, 0), filter), "Dock shoreline missing")
assert(wet.Material == Enum.Material.Water, "Dock pilings must reach the water")

local bay = Instance.new("Folder")
bay.Name = "Wrackbucht"
bay:SetAttribute("Owner", OWNER)

local function addModel(id: string, label: string, at: CFrame, center: Vector3, expected: Vector3)
    local template = library:FindFirstChild(id)
    assert(template and (template:IsA("Model") or template:IsA("BasePart")), "Missing model " .. id)
    local prop = template:Clone()
    prop.Name = label
    prop:PivotTo(C())

    -- Check and recover the imported pivot in the orientation of the GLB axes.
    local bounds, size
    if prop:IsA("Model") then
        bounds, size = prop:GetBoundingBox()
    else
        bounds, size = prop.CFrame, prop.Size
    end
    assert((size - expected).Magnitude < 0.20, "Import as Studs with the default axes for " .. id)
    prop:PivotTo(at * C(center - bounds.Position))

    local parts = prop:GetDescendants()
    table.insert(parts, prop)
    for _, piece in parts do
        if piece:IsA("BasePart") then
            piece.Anchored, piece.CanCollide, piece.CanTouch, piece.CanQuery =
                true, false, false, false
        end
    end
    prop.Parent = bay
end

local wreckPose = C(ground.Position - V(0, 1.20, 0)) * A(0, rad(31), 0) * A(rad(5), 0, rad(-4))
addModel(
    "salt_lake_wreck",
    "Versalztes Wrack",
    wreckPose,
    V(-0.1016, 3.9077, -1.6792),
    V(11.8872, 8.3711, 28.2087)
)
addModel(
    "salt_lake_dock",
    "Alter Anleger",
    dockPose,
    V(0, -0.6333, -0.55),
    V(6.502, 7.2547, 16.0098)
)

local floor = Instance.new("Part")
local centerZ = -3.775
local deckHeight = 1.62 - 0.037 * centerZ
floor.Name = "Intakte Planken"
floor.Size = V(5.28, 0.22, 8.95)
floor.CFrame = dockPose * C(0, deckHeight - 0.117, centerZ) * A(math.atan(0.037), 0, 0)
floor.Anchored, floor.CanCollide, floor.CanTouch = true, true, false
floor.Transparency, floor.CastShadow, floor.Parent = 1, false, bay

if original then
    current.Name, current.Parent = ARCHIVE, storage
else
    current:Destroy()
end
bay.Parent = landmarks
print(bay:GetFullName())
