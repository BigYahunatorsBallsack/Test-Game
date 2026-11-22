-- Studio command only. Sculpt the Dünenmeer using a continuous sand heightfield.
-- Run in Edit on the existing Every Last Grain art scene.
assert(game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
    "Run the Dünenmeer terrain tool in Studio Edit mode")
assert(game.PlaceId == 135831532782380, "Unexpected place")
local world = workspace:FindFirstChild("DuneBaronWorld")
assert(world and world:FindFirstChild("ArtV2"), "Dünenmeer ArtV2 scene is required")
local terrain = workspace.Terrain
local storage = game:GetService("ServerStorage")
local lighting = game:GetService("Lighting")
local backupName = "DuneBaron_PreDuneTerrainV3"
local backup = storage:FindFirstChild(backupName)
assert(not backup or backup:GetAttribute("Owner") == "DuneBaronArtV3", "Backup name collision")
assert(not backup or backup:GetAttribute("BuildStatus") ~= "Running", "Terrain build is already running")

local V = Vector3
local GRID, TILE = 4, 128
local MIN, MAX = -1152, 1152
local LOW, HIGH = -12, 104
-- The original authored dune volumes fit in this region above LOW.
local savedMin = Vector3int16.new(-80, LOW / GRID, -80)
local savedMax = Vector3int16.new(80, HIGH / GRID, 80)
local sand = Enum.Material.Sand
local air = Enum.Material.Air
local TILES_PER_SIDE = (MAX - MIN) / TILE

if not backup then
    backup = Instance.new("Folder")
    backup.Name = backupName
    backup:SetAttribute("Owner", "DuneBaronArtV3")
    backup:SetAttribute("SandColor", terrain:GetMaterialColor(sand))
    backup:SetAttribute("OldClockTime", lighting.ClockTime)
    backup:SetAttribute("BoundsMin", V.new(MIN, LOW, MIN))
    backup:SetAttribute("BoundsMax", V.new(MAX, HIGH, MAX))
    backup.Parent = storage
    local oldTerrain = terrain:CopyRegion(Region3int16.new(savedMin, savedMax))
    oldTerrain.Name = "OldTerrain"
    oldTerrain.Parent = backup
    local oldLighting = Instance.new("Folder")
    oldLighting.Name = "OldAtmospheres"
    oldLighting.Parent = backup
    for _, item in lighting:GetChildren() do
        if item:IsA("Atmosphere") then
            item:Clone().Parent = oldLighting
        end
    end
    local faces = world.ArtV2:FindFirstChild("RockFaces")
    if faces then faces.Parent = backup end
end

local function smooth(t)
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function distanceToRect(x, z, x0, z0, x1, z1)
    return math.sqrt(math.max(x0 - x, 0, x - x1)^2 + math.max(z0 - z, 0, z - z1)^2)
end

-- A broad windward face climbs toward a narrow crest. The slip face returns
-- to the lower dune field over a shorter run, with a softened toe.
local function ridge(phase, crest)
    local t = phase % 1
    if t < crest then
        local p = t / crest
        return p * p * (1.58 - 0.58 * p)
    end
    local p = (1 - t) / (1 - crest)
    return p * p * (2.18 - 1.18 * p)
end

local function heightAt(x, z)
    local u = x * 0.61 + z * 0.7924
    local v = -x * 0.7924 + z * 0.61
    -- Crest lines wander laterally and break into saddles along their length.
    local bend = 40 * math.sin(v / 146 + 0.7) + 22 * math.noise(u / 330, v / 155, 1.73)
    local phase = (u + bend + 47) / 218
    local band = math.floor(phase)
    local long = math.noise(v / 164, band * 0.63, 9.1)
    local split = smooth((math.noise(v / 115, band * 0.88, 4.7) + 0.52) / 0.64)
    local amplitude = math.clamp(27 + 29 * long + 15 * split, 15, 57)
    local main = ridge(phase, 0.72)
    -- Smaller dunes lie in the hollows between the dominant rows.
    local drift = ridge((u * 0.94 - v * 0.28 + 11 * math.sin(v / 62) + 18) / 72, 0.68)
    local trough = (1 - main) * (4.8 + 4.2 * math.noise(x / 135, z / 159, 2.43)) * drift
    local basin = 3.5 + 6.8 * math.noise(x / 462, z / 386, 1.47)

    local coreDist = distanceToRect(x, z, -55, -46, 83, 130)
    local build = smooth((coreDist - 4) / 73)
    local exitX = 29 + 39 * math.sin((z - 115) / 142)
    local exitFade = smooth((z - 119) / 57) * (1 - smooth((z - 332) / 97))
    local pass = (1 - smooth((math.abs(x - exitX) - 11) / 37)) * exitFade
    local h = basin + amplitude * main + trough
    h -= pass * math.max(h - 8, 0) * 0.82

    -- Distant dunes rise just enough that the edge of the authored terrain is
    -- behind intervening sand ridges from the developed play area.
    local distance = math.max(math.abs(x), math.abs(z))
    local rim = smooth((distance - 855) / 264)
    h += rim * (15 + 6 * math.noise(x / 150, z / 150, 1.12))
    return 4 + (h - 4) * build
end

local function makeTileArrays()
    local materials, occupancy = {}, {}
    for x = 1, TILE / GRID do
        materials[x], occupancy[x] = {}, {}
        for y = 1, (HIGH - LOW) / GRID do
            materials[x][y], occupancy[x][y] = {}, {}
        end
    end
    return materials, occupancy
end

local function generate()
    local materials, occupancy = makeTileArrays()
    local done, nx, ny = 0, TILE / GRID, (HIGH - LOW) / GRID
    for x0 = MIN, MAX - TILE, TILE do
        for z0 = MIN, MAX - TILE, TILE do
            for ix = 1, nx do
                local x = x0 + (ix - 0.5) * GRID
                for iz = 1, nx do
                    local z = z0 + (iz - 0.5) * GRID
                    local height = heightAt(x, z)
                    for iy = 1, ny do
                        local fill = math.clamp((height - (LOW + (iy - 1) * GRID)) / GRID, 0, 1)
                        occupancy[ix][iy][iz] = fill
                        materials[ix][iy][iz] = if fill > 0 then sand else air
                    end
                end
            end
            local region = Region3.new(V.new(x0, LOW, z0), V.new(x0 + TILE, HIGH, z0 + TILE))
            terrain:WriteVoxels(region, GRID, materials, occupancy)
            done += 1
            if done % 3 == 0 then
                backup:SetAttribute("TilesWritten", done)
                task.wait()
            end
        end
    end

    for _, item in lighting:GetChildren() do
        if item:IsA("Atmosphere") then item:Destroy() end
    end
    local haze = Instance.new("Atmosphere")
    haze.Name = "DuneBaronHorizonHaze"
    haze.Density = 0.32
    haze.Offset = 0.16
    haze.Haze = 1.65
    haze.Glare = 0.12
    haze.Color = Color3.fromRGB(247, 217, 182)
    haze.Decay = Color3.fromRGB(159, 175, 193)
    haze.Parent = lighting
    lighting.ClockTime = 16.12
    terrain:SetMaterialColor(sand, Color3.fromRGB(235, 178, 106))

    world:SetAttribute("DunesTerrainExtentStuds", MAX - MIN)
    world:SetAttribute("DunesTerrainRevision", 3)
    backup:SetAttribute("TilesWritten", done)
    backup:SetAttribute("BuildStatus", "Ready")
end

backup:SetAttribute("BuildStatus", "Running")
backup:SetAttribute("TilesWritten", 0)
task.spawn(function()
    local ok, issue = pcall(generate)
    if not ok then
        backup:SetAttribute("BuildStatus", "Failed")
        backup:SetAttribute("BuildError", tostring(issue))
        warn(issue)
    end
end)
return { size = MAX - MIN, tiles = TILES_PER_SIDE^2, status = "running", backup = backup:GetFullName() }
