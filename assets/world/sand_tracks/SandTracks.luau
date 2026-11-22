--!strict
-- Local presentation. Each stamp consumes a supplied foot contact.
local RunService = game:GetService("RunService")
local rgb = Color3.fromRGB

local TRACK_COUNT = 18
local UPDATE_RATE = 0.10
local DEPTH_BIAS = -0.013
local SOLE_ON_GROUND = CFrame.Angles(-math.pi / 2, 0, 0)

type Preset = {
    edge: Color3,
    core: Color3,
    tread: Color3,
    dust: Color3,
    grains: Color3,
    opacity: number,
    hold: number,
    fade: number,
    puffs: number,
    specks: number,
}

local PRESETS: { [string]: Preset } = {
    yellow = {
        edge = rgb(245, 208, 142),
        core = rgb(151, 103, 52),
        tread = rgb(108, 69, 34),
        dust = rgb(224, 185, 122),
        grains = rgb(236, 191, 119),
        opacity = 0.78,
        hold = 3.2,
        fade = 3.8,
        puffs = 3,
        specks = 3,
    },
    red = {
        edge = rgb(225, 144, 98),
        core = rgb(118, 58, 43),
        tread = rgb(82, 39, 29),
        dust = rgb(196, 116, 82),
        grains = rgb(208, 129, 83),
        opacity = 0.84,
        hold = 4.1,
        fade = 4.5,
        puffs = 2,
        specks = 2,
    },
    white = {
        edge = rgb(252, 248, 229),
        core = rgb(142, 142, 135),
        tread = rgb(105, 113, 107),
        dust = rgb(232, 223, 204),
        grains = rgb(247, 239, 213),
        opacity = 0.79,
        hold = 2.8,
        fade = 3.9,
        puffs = 3,
        specks = 4,
    },
    crystal = {
        edge = rgb(220, 245, 236),
        core = rgb(111, 143, 148),
        tread = rgb(77, 119, 124),
        dust = rgb(215, 235, 224),
        grains = rgb(158, 219, 225),
        opacity = 0.76,
        hold = 2.7,
        fade = 3.4,
        puffs = 1,
        specks = 6,
    },
    black = {
        edge = rgb(107, 99, 113),
        core = rgb(32, 30, 37),
        tread = rgb(17, 15, 23),
        dust = rgb(103, 93, 110),
        grains = rgb(123, 108, 125),
        opacity = 0.88,
        hold = 3.2,
        fade = 4.0,
        puffs = 3,
        specks = 3,
    },
}

type Tone = "edge" | "core" | "tread"
type Layer = { frame: Frame, tone: Tone, strength: number }
type Stamp = {
    holder: BasePart,
    gui: SurfaceGui,
    dust: ParticleEmitter,
    grains: ParticleEmitter,
    layers: { Layer },
    opacity: number,
    fadeAt: number,
    expireAt: number,
}

local function display(stamp: Stamp, opacity: number)
    for _, layer in stamp.layers do
        layer.frame.BackgroundTransparency = 1 - layer.strength * opacity
    end
end

local function makeStamp(root: Folder): Stamp
    local holder = (script:FindFirstChild("Footprint") :: BasePart):Clone()
    local gui = holder:FindFirstChild("Sole") :: SurfaceGui
    local dust = holder:FindFirstChild("Dust") :: ParticleEmitter
    local grains = holder:FindFirstChild("Grains") :: ParticleEmitter
    local layers: { Layer } = {}
    for _, item in gui:GetChildren() do
        if item:IsA("Frame") then
            table.insert(layers, {
                frame = item,
                tone = item:GetAttribute("Tone") :: Tone,
                strength = item:GetAttribute("Strength") :: number,
            })
        end
    end
    holder.Parent = root
    return {
        holder = holder,
        gui = gui,
        dust = dust,
        grains = grains,
        layers = layers,
        opacity = 0,
        fadeAt = 0,
        expireAt = 0,
    }
end

local SandTracks = {}
local unmount: (() -> ())?

function SandTracks.Mount()
    assert(RunService:IsClient(), "Mount sand tracks on the client")
    if unmount then
        unmount()
    end
    local root = Instance.new("Folder")
    root.Name = "LocalSandTracks"
    local stamps = table.create(TRACK_COUNT)
    for i = 1, TRACK_COUNT do
        stamps[i] = makeStamp(root)
    end
    root.Parent = workspace

    local cursor = 0
    local elapsed = 0
    local accumulated = 0
    local destroyed = false
    local connection = RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        accumulated += dt
        if accumulated < UPDATE_RATE then
            return
        end
        accumulated %= UPDATE_RATE
        for _, stamp in stamps do
            if stamp.gui.Enabled then
                if elapsed >= stamp.expireAt then
                    stamp.gui.Enabled = false
                elseif elapsed > stamp.fadeAt then
                    local alpha = (stamp.expireAt - elapsed) / (stamp.expireAt - stamp.fadeAt)
                    display(stamp, stamp.opacity * alpha)
                end
            end
        end
    end)

    local function destroy()
        if not destroyed then
            destroyed = true
            connection:Disconnect()
            root:Destroy()
            unmount = nil
        end
    end
    unmount = destroy

    return {
        Stamp = function(sandTypeId: string, contact: CFrame, left: boolean): boolean
            local preset = PRESETS[sandTypeId]
            if destroyed or not preset then
                return false
            end
            cursor = cursor % TRACK_COUNT + 1
            local stamp = stamps[cursor]
            stamp.dust:Clear()
            stamp.grains:Clear()
            local twist = if left then -0.096 else 0.096
            stamp.holder.CFrame = contact
                * CFrame.new(0, DEPTH_BIAS, 0)
                * CFrame.Angles(0, twist, 0)
                * SOLE_ON_GROUND
            stamp.opacity = preset.opacity
            stamp.fadeAt = elapsed + preset.hold
            stamp.expireAt = stamp.fadeAt + preset.fade
            for _, layer in stamp.layers do
                layer.frame.BackgroundColor3 = preset[layer.tone]
            end
            display(stamp, stamp.opacity)
            stamp.gui.Enabled = true
            stamp.dust.Color = ColorSequence.new(preset.dust)
            stamp.grains.Color = ColorSequence.new(preset.grains)
            stamp.dust:Emit(preset.puffs)
            stamp.grains:Emit(preset.specks)
            return true
        end,
        Destroy = destroy,
    }
end

return SandTracks
