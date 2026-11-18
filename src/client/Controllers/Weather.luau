--!strict
-- Weather-Controller (Paket 2.5)
-- Zeigt das Wetter der Zone, in der der eigene Charakter steht: Regen und Staubwind als Partikel
-- um die Kamera, Nebel und Dunst über Atmosphäre und Farbkorrektur. Das Wetter kommt als fester
-- Zyklus aus der Serverzeit (Logic/Weather), alle Clients sehen deshalb dasselbe, ohne dass der
-- Server etwas sendet. Beim Zonenwechsel blendet das alte Wetter aus, bevor das neue einblendet.
-- Auf schwachen Geräten (Rückfallvariante von Dig) entfallen die Partikel.
--
-- Eine vorhandene Atmosphäre im Lighting (zum Beispiel aus dem Look in Paket 3.4) bleibt die
-- Grundlage: Das Wetter überblendet ihre Werte und blendet sie danach zurück.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Darstellung
local EMITTER_PART_NAME = "DuneBaronWeatherEmitter"
local CC_NAME = "DuneBaronWeatherColor"
local ATMOSPHERE_NAME = "DuneBaronAtmosphere"
local EMITTER_HEIGHT_STUDS = 40 -- so hoch über der Kamera beginnen die Partikel
local EMITTER_AREA_STUDS = 80 -- Kantenlänge der Fläche über der Kamera
local EMITTER_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local PARTICLE_LIFETIME_SECONDS = 1.2
local MAX_FRAME_SECONDS = 0.1 -- Obergrenze für dt, damit ein Ruckler nicht springt

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local WeatherData = loadShared("Data", "Weather")
local WeatherLogic = loadShared("Logic", "Weather")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Dig = require(script.Parent:WaitForChild("Dig") :: ModuleScript) :: any

local Weather = {}

local atmosphere: Atmosphere? = nil
local color: ColorCorrectionEffect? = nil
local emitterPart: Part? = nil
local emitter: ParticleEmitter? = nil

-- Grundwerte der Atmosphäre (vor dem Wetter) und aktueller Mischzustand.
local base = {
    density = WeatherData.clear.atmosphereDensity,
    haze = WeatherData.clear.atmosphereHaze,
    color = Color3.fromHex(WeatherData.clear.atmosphereColorHex),
}
local blendKind = "clear"
local blendAmount = 0

local function setup()
    local existing = Lighting:FindFirstChildOfClass("Atmosphere")
    if existing ~= nil then
        atmosphere = existing
        base.density = existing.Density
        base.haze = existing.Haze
        base.color = existing.Color
    else
        local created = Instance.new("Atmosphere")
        created.Name = ATMOSPHERE_NAME
        created.Density = base.density
        created.Haze = base.haze
        created.Color = base.color
        created.Parent = Lighting
        atmosphere = created
    end
    local cc = Instance.new("ColorCorrectionEffect")
    cc.Name = CC_NAME
    cc.Parent = Lighting
    color = cc

    local part = Instance.new("Part")
    part.Name = EMITTER_PART_NAME
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Transparency = 1
    part.Size = Vector3.new(EMITTER_AREA_STUDS, 1, EMITTER_AREA_STUDS)
    local e = Instance.new("ParticleEmitter")
    e.Enabled = false
    e.Rate = 0
    e.Texture = EMITTER_TEXTURE
    e.Lifetime = NumberRange.new(PARTICLE_LIFETIME_SECONDS * 0.8, PARTICLE_LIFETIME_SECONDS)
    e.EmissionDirection = Enum.NormalId.Bottom
    e.Shape = Enum.ParticleEmitterShape.Box
    e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
    e.SpreadAngle = Vector2.new(8, 8)
    e.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    e.LightInfluence = 1
    e.Parent = part
    part.Parent = workspace
    emitterPart = part
    emitter = e
end

local function currentZoneId(): string?
    local snapshot = State.get()
    return if snapshot ~= nil then snapshot.zoneId else nil
end

local function step(dt: number)
    local atm, cc, part, e = atmosphere, color, emitterPart, emitter
    if atm == nil or cc == nil or part == nil or e == nil then
        return
    end
    dt = math.min(dt, MAX_FRAME_SECONDS)
    local zoneId = currentZoneId()
    local target = if zoneId ~= nil then WeatherLogic.stateAt(zoneId, workspace:GetServerTimeNow()) else nil
    local targetKind = if target ~= nil and target.active then target.kind else "clear"
    local targetStrength = if target ~= nil and target.active then target.strength else 0

    -- Altes Wetter erst ausblenden, dann das neue einblenden.
    local speed = dt / math.max(WeatherData.fadeSeconds, 1e-6)
    if blendKind ~= targetKind then
        blendAmount = math.max(blendAmount - speed, 0)
        if blendAmount <= 0 then
            blendKind = targetKind
        end
    else
        if blendAmount < targetStrength then
            blendAmount = math.min(blendAmount + speed, targetStrength)
        else
            blendAmount = math.max(blendAmount - speed, targetStrength)
        end
    end

    local look = WeatherData.looks[blendKind]
    local amount = if look ~= nil then blendAmount else 0
    local clear = WeatherData.clear
    if look ~= nil then
        atm.Density = base.density + (look.atmosphereDensity - base.density) * amount
        atm.Haze = base.haze + (look.atmosphereHaze - base.haze) * amount
        atm.Color = base.color:Lerp(Color3.fromHex(look.atmosphereColorHex), amount)
        cc.Brightness = clear.brightness + (look.brightness - clear.brightness) * amount
        cc.Saturation = clear.saturation + (look.saturation - clear.saturation) * amount
        cc.TintColor = Color3.fromHex(clear.tintHex):Lerp(Color3.fromHex(look.tintHex), amount)
    else
        atm.Density = base.density
        atm.Haze = base.haze
        atm.Color = base.color
        cc.Brightness = clear.brightness
        cc.Saturation = clear.saturation
        cc.TintColor = Color3.fromHex(clear.tintHex)
    end

    -- Partikel um die Kamera (nicht auf schwachen Geräten).
    local camera = workspace.CurrentCamera
    local particles = look ~= nil and look.particleRate > 0 and amount > 0.01 and camera ~= nil and not Dig.isFallback()
    if particles and look ~= nil and camera ~= nil then
        part.Position = camera.CFrame.Position + Vector3.new(0, EMITTER_HEIGHT_STUDS, 0)
        e.Rate = look.particleRate * amount
        e.Speed = NumberRange.new(look.particleSpeed * 0.9, look.particleSpeed)
        e.Acceleration = Vector3.new(look.particleWindStuds, 0, 0)
        e.Size = NumberSequence.new(look.particleSize)
        e.Color = ColorSequence.new(Color3.fromHex(look.particleColorHex))
        e.Enabled = true
    else
        e.Enabled = false
    end
end

function Weather.Init() end

function Weather.Start()
    setup()
    RunService.Heartbeat:Connect(function(dt: number)
        local ok, err = pcall(step, dt)
        if not ok then
            warn("[Weather] " .. tostring(err))
        end
    end)
end

return Weather
