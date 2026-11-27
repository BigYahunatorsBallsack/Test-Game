--!strict
-- Fundstellen-Glitzern (Überarbeitung Ü3). Der Server schickt die Lage der eigenen Fundstellen
-- ("FindSpots", Liste { id, x, y, z }). Hier entsteht an jeder Stelle ein leichtes Glitzern, sichtbar
-- bis Data/FindSpots.glitterDistanceStuds. Nur Anzeige: Ob und was gefunden wird, entscheidet der
-- Server beim Stich. Schöneres Aussehen kommt in Ü4 (Assets von ChatGPT).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Aussehen (Startwerte bis Ü4)
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPARKLE_RATE = 6
local SPARKLE_LIFETIME = NumberRange.new(0.5, 1.1)
local SPARKLE_SPEED = NumberRange.new(0.5, 1.5)
local SPARKLE_SIZE = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.35),
    NumberSequenceKeypoint.new(1, 0),
})
local SPARKLE_COLOR = Color3.fromRGB(255, 236, 170)
local SPARKLE_SPREAD = 2 -- halbe Breite der Fläche, aus der es glitzert (Studs)
local LIGHT_RANGE = 6
local LIGHT_BRIGHTNESS = 0.6
local LIFT_STUDS = 0.3 -- knapp über der Oberfläche
local VISIBILITY_CHECK_SECONDS = 0.5

local shared = ReplicatedStorage:WaitForChild("Shared")
local FindSpotsData = require(shared:WaitForChild("Data"):WaitForChild("FindSpots") :: ModuleScript) :: any

local FindSpotsController = {}

local player = Players.LocalPlayer
local folder: Folder? = nil
local markers: { [number]: BasePart } = {}

local function createMarker(spot: any): BasePart
    local part = Instance.new("Part")
    part.Name = `Fundstelle_{spot.id}`
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Transparency = 1
    part.Size = Vector3.new(SPARKLE_SPREAD * 2, 0.2, SPARKLE_SPREAD * 2)
    part.Position = Vector3.new(spot.x, spot.y + LIFT_STUDS, spot.z)

    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = SPARKLE_TEXTURE
    emitter.Rate = SPARKLE_RATE
    emitter.Lifetime = SPARKLE_LIFETIME
    emitter.Speed = SPARKLE_SPEED
    emitter.Size = SPARKLE_SIZE
    emitter.Color = ColorSequence.new(SPARKLE_COLOR)
    emitter.LightEmission = 1
    emitter.EmissionDirection = Enum.NormalId.Top
    emitter.Enabled = false
    emitter.Parent = part

    local light = Instance.new("PointLight")
    light.Range = LIGHT_RANGE
    light.Brightness = LIGHT_BRIGHTNESS
    light.Color = SPARKLE_COLOR
    light.Enabled = false
    light.Parent = part

    part.Parent = folder
    return part
end

local function apply(list: any)
    if type(list) ~= "table" then
        return
    end
    local keep: { [number]: boolean } = {}
    for _, spot in list do
        if type(spot) == "table" and type(spot.id) == "number" and type(spot.x) == "number" and type(spot.y) == "number" and type(spot.z) == "number" then
            keep[spot.id] = true
            if markers[spot.id] == nil then
                markers[spot.id] = createMarker(spot)
            end
        end
    end
    for id, part in markers do
        if not keep[id] then
            part:Destroy()
            markers[id] = nil
        end
    end
end

-- Glitzern nur in der Nähe (spart Partikel am Handy).
local function refreshVisibility()
    local character = player.Character
    local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
    local limit = FindSpotsData.glitterDistanceStuds
    for _, part in markers do
        local near = root ~= nil and root:IsA("BasePart") and (part.Position - root.Position).Magnitude <= limit
        local emitter = part:FindFirstChildOfClass("ParticleEmitter")
        local light = part:FindFirstChildOfClass("PointLight")
        if emitter ~= nil then
            emitter.Enabled = near
        end
        if light ~= nil then
            light.Enabled = near
        end
    end
end

function FindSpotsController.Init() end

function FindSpotsController.Start()
    local f = Instance.new("Folder")
    f.Name = "FindSpots"
    f.Parent = workspace
    folder = f
    local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FindSpots") :: RemoteEvent
    remote.OnClientEvent:Connect(function(list: any)
        apply(list)
        refreshVisibility()
    end)
    local nextCheck = 0
    RunService.Heartbeat:Connect(function()
        local t = os.clock()
        if t >= nextCheck then
            nextCheck = t + VISIBILITY_CHECK_SECONDS
            refreshVisibility()
        end
    end)
end

return FindSpotsController
