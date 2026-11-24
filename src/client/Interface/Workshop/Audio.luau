--!strict
local ContentProvider = game:GetService("ContentProvider")
local Audio = {}

type Cue = "select" | "learn" | "major" | "equip"
local CLICK = "rbxasset://sounds/volume_slider.ogg"
local MECHANICAL = "rbxasset://sounds/action_footsteps_plastic.mp3"
local config = {
    select = { name = "Knotenauswahl", asset = "", volume = 0.15, fallback = CLICK, speed = 1.12 },
    learn = { name = "KnotenGelernt", asset = "", volume = 0.24, fallback = CLICK, speed = 0.88 },
    major = {
        name = "FaehigkeitGelernt",
        asset = "",
        volume = 0.30,
        fallback = CLICK,
        speed = 1.35,
    },
    equip = {
        name = "VarianteAusgeruestet",
        asset = "",
        volume = 0.22,
        fallback = MECHANICAL,
        speed = 1.5,
    },
}

local function sound(
    parent: Instance,
    name: string,
    id: string,
    volume: number,
    speed: number
): Sound
    local cue = Instance.new("Sound")
    cue.Name, cue.SoundId, cue.Volume, cue.PlaybackSpeed = name, id, volume, speed
    cue.Parent = parent
    return cue
end

function Audio.mount(parent: Instance)
    local bank = Instance.new("Folder")
    bank.Name = "WerkstattSounds"
    bank.Parent = parent
    local performance: { [string]: Sound } = {}
    local fallback: { [string]: Sound } = {}
    local assets: { Sound } = {}
    for key, entry in config do
        fallback[key] =
            sound(bank, entry.name .. "Reserve", entry.fallback, entry.volume * 0.48, entry.speed)
        if entry.asset ~= "" then
            local clip = sound(bank, entry.name, entry.asset, entry.volume, 1)
            performance[key] = clip
            table.insert(assets, clip)
        end
    end
    if #assets > 0 then
        task.defer(function()
            ContentProvider:PreloadAsync(assets)
        end)
    end

    local selection: Sound? = nil
    local feedback: Sound? = nil
    local lastSelect = -math.huge
    local function play(key: Cue)
        local clip = performance[key]
        local selected = if clip and clip.IsLoaded then clip else fallback[key]
        if key == "select" then
            local now = os.clock()
            if (feedback and feedback.IsPlaying) or now - lastSelect < 0.085 then
                return
            end
            if selection then
                selection:Stop()
            end
            selection = selected
            lastSelect = now
        else
            if selection then
                selection:Stop()
                selection = nil
            end
            if feedback then
                feedback:Stop()
            end
            feedback = selected
        end
        selected:Play()
    end
    local function stop()
        if selection then
            selection:Stop()
            selection = nil
        end
        if feedback then
            feedback:Stop()
            feedback = nil
        end
    end
    return { play = play, stop = stop }
end

return Audio
