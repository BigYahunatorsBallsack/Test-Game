--!strict
-- Insert the accompanying RBXM in ServerStorage, then run in Studio Edit.
local placements = {
    { name = "Tor Nord", template = "Karawanenlaterne", x = 1863, z = 846, yaw = 9 },
    { name = "Tor Süd", template = "Karawanenlaterne", x = 1863, z = 886, yaw = -11 },
    { name = "Abzweig Nord", template = "Siegelstele", x = 1924, z = 840, yaw = 65 },
    { name = "Abzweig Archiv", template = "Siegelstele", x = 2085, z = 893, yaw = -18 },
    { name = "Abzweig Tempel", template = "Siegelstele", x = 2228, z = 861, yaw = 61 },
    { name = "Spur am Archiv", template = "GrabungsspurArchiv", x = 2097, z = 911, yaw = -18 },
    {
        name = "Spur an der Siegelkammer",
        template = "GrabungsspurSiegelkammer",
        x = 2130,
        z = 826,
        yaw = 16,
    },
}

local run = game:GetService("RunService")
assert(
    run:IsStudio() and not run:IsRunning() and game.PlaceId == 135831532782380,
    "Use Every Last Grain in Studio Edit"
)
local world = assert(workspace:FindFirstChild("DuneBaronWorld"), "Dune Baron world missing")
local art = assert(world:FindFirstChild("RuinsArtV1"), "Build Ruins V1 first")
local library = assert(
    game:GetService("ServerStorage"):FindFirstChild("DuneBaronRuinsWayfinding"),
    "Import the RBXM first"
)
assert(library:GetAttribute("ZoneId") == "ruins", "Unexpected model library")

local name = "RuinsWayfindingV1"
local previous = art:FindFirstChild(name)
assert(
    not previous or previous:GetAttribute("Owner") == "DuneBaronRuinsWayfinding",
    "Destination already in use"
)
local folder = Instance.new("Folder")
folder.Name = name
folder:SetAttribute("Owner", "DuneBaronRuinsWayfinding")

local filter = RaycastParams.new()
filter.FilterType = Enum.RaycastFilterType.Include
filter.FilterDescendantsInstances = { workspace.Terrain }
filter.IgnoreWater = true

for _, placement in placements do
    local source = library:FindFirstChild(placement.template)
    assert(source and source:IsA("Model"), "Missing template " .. placement.template)
    local origin = Vector3.new(placement.x, 170, placement.z)
    local hit = assert(
        workspace:Raycast(origin, Vector3.new(0, -235, 0), filter),
        "Terrain missing at " .. placement.name
    )
    assert(hit.Normal.Y >= 0.90, "Terrain too steep at " .. placement.name)
    local clone = source:Clone()
    clone.Name = placement.name
    clone:PivotTo(CFrame.new(hit.Position) * CFrame.Angles(0, math.rad(placement.yaw), 0))
    clone.Parent = folder
end

if previous then
    previous:Destroy()
end
folder.Parent = art
print(folder:GetFullName(), #folder:GetChildren(), "models placed")
