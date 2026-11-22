--!strict
-- Studio Edit helper for the two GLBs in this folder.
local placements = {
    {
        asset = "canyon_fossil_workbench",
        label = "Fossilien-Werkbank",
        x = 649,
        z = 733,
        heading = 12,
        embed = 0.27,
    },
    {
        asset = "canyon_quartz_seam",
        label = "Quarzader",
        x = 895,
        z = 767,
        heading = -19,
        embed = 0.40,
    },
}

local run = game:GetService("RunService")
assert(
    run:IsStudio() and not run:IsRunning() and game.PlaceId == 135831532782380,
    "Use Every Last Grain in Studio Edit"
)
local world = assert(workspace:FindFirstChild("DuneBaronWorld"), "Dune Baron world missing")
local art = assert(world:FindFirstChild("CanyonArtV1"), "Canyon V1 art missing")
local library = assert(
    game:GetService("ServerStorage"):FindFirstChild("DuneBaronCanyonDetails"),
    "Import both Canyon GLBs first"
)
local name = "CanyonExpeditionDetailsV1"
local previous = art:FindFirstChild(name)
assert(
    not previous or previous:GetAttribute("Owner") == "DuneBaronCanyonDetails",
    "Destination already in use"
)

local filter = RaycastParams.new()
filter.FilterType = Enum.RaycastFilterType.Include
filter.FilterDescendantsInstances = { workspace.Terrain }
filter.IgnoreWater = true
local additions = Instance.new("Folder")
additions.Name = name
additions:SetAttribute("Owner", "DuneBaronCanyonDetails")

for _, site in placements do
    local source = library:FindFirstChild(site.asset)
    assert(
        source and (source:IsA("Model") or source:IsA("BasePart")),
        "Missing Canyon model " .. site.asset
    )
    local origin = Vector3.new(site.x, 170, site.z)
    local hit = assert(
        workspace:Raycast(origin, Vector3.new(0, -205, 0), filter),
        "Terrain missing at " .. site.label
    )
    assert(hit.Normal.Y >= 0.90, "Terrain too steep at " .. site.label)

    local prop = source:Clone()
    prop.Name = site.label
    local at = CFrame.new(hit.Position - Vector3.new(0, site.embed, 0))
        * CFrame.Angles(0, math.rad(site.heading), 0)
    prop:PivotTo(at)
    local bounds, size
    if prop:IsA("Model") then
        bounds, size = prop:GetBoundingBox()
    else
        bounds, size = prop.CFrame, prop.Size
    end
    assert(math.abs(size.Y - 4.1) < 0.18, "Set GLB import scale to Studs for " .. site.asset)
    local delta = at.Y - (bounds.Y - size.Y / 2)
    prop:PivotTo(at + Vector3.new(0, delta, 0))
    local parts = prop:GetDescendants()
    table.insert(parts, prop)
    for _, piece in parts do
        if piece:IsA("BasePart") then
            piece.Anchored, piece.CanCollide, piece.CanTouch, piece.CanQuery =
                true, false, false, false
        end
    end
    prop.Parent = additions
end

if previous then
    previous:Destroy()
end
additions.Parent = art
print(additions:GetFullName())
