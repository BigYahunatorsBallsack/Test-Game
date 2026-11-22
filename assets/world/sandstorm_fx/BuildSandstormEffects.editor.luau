--!strict
-- Portable client-side art for a confirmed Prestige transition.
local offline = game == nil
local roblox = if offline then require("@lune/roblox") else nil
local fs = if offline then require("@lune/fs") else nil
local luau = if offline then require("@lune/luau") else nil
local Instance = if roblox then roblox.Instance else Instance
local Vector2 = if roblox then roblox.Vector2 else Vector2
local Vector3 = if roblox then roblox.Vector3 else Vector3
local Color3 = if roblox then roblox.Color3 else Color3
local ColorSequence = if roblox then roblox.ColorSequence else ColorSequence
local NumberRange = if roblox then roblox.NumberRange else NumberRange
local NumberSequence = if roblox then roblox.NumberSequence else NumberSequence
local NumberSequenceKeypoint = if roblox then roblox.NumberSequenceKeypoint else NumberSequenceKeypoint
local Enum = if roblox then roblox.Enum else Enum

local packageName = "DuneBaronSandstormEffects"
local owner = "DuneBaronSandstormArt"
local binderSource = [==[
--!strict
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local gust = TweenInfo.new(.61,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local neutral = Color3.new(1,1,1)

local function mount(parent: PlayerGui)
    local pack = assert(script.Parent)
    local duration = pack:GetAttribute("DurationSeconds") :: number
    local clearAt = pack:GetAttribute("ClearAtSeconds") :: number
    local clearing = TweenInfo.new(duration-clearAt,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
    local dust = assert(pack:FindFirstChild("SandVolume")):Clone() :: Part
    local tint = assert(pack:FindFirstChild("AmberGrade")):Clone() :: ColorCorrectionEffect
    dust.Parent = workspace
    tint.Parent = Lighting
    local particles: {ParticleEmitter} = {}
    for _, node in dust:GetChildren() do
        if node:IsA("ParticleEmitter") then table.insert(particles,node) end
    end

    local gui = Instance.new("ScreenGui")
    gui.Name,gui.DisplayOrder,gui.ResetOnSpawn = "DuneBaronSandstormVeil",8,false
    gui.IgnoreGuiInset = true
    gui.ScreenInsets = Enum.ScreenInsets.None
    gui.ClipToDeviceSafeArea = false
    gui.Enabled = false
    gui.Parent = parent

    local veil = Instance.new("Frame")
    veil.Name,veil.BorderSizePixel = "SandVeil",0
    veil.BackgroundColor3,veil.BackgroundTransparency = Color3.fromRGB(209,152,87),1
    veil.Size,veil.Active = UDim2.fromScale(1,1),false
    veil.Parent = gui
    local falloff = Instance.new("UIGradient")
    falloff.Rotation = -15
    falloff.Color = ColorSequence.new(Color3.fromRGB(243,204,147),Color3.fromRGB(169,107,55))
    falloff.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,.09),
        NumberSequenceKeypoint.new(.46,.20),
        NumberSequenceKeypoint.new(1,.51),
    })
    falloff.Parent = veil

    local version = 0
    local active,dead = false,false
    local follow: RBXScriptConnection?
    local motions: {Tween} = {}

    local function animate(target: Instance, timing: TweenInfo, goal: {[string]: any})
        local tween = TweenService:Create(target,timing,goal)
        table.insert(motions,tween)
        tween:Play()
    end

    local function clear()
        version += 1
        active = false
        if follow then follow:Disconnect() follow=nil end
        for _, tween in motions do tween:Cancel() tween:Destroy() end
        table.clear(motions)
        for _, e in particles do e.Enabled=false e:Clear() end
        tint.Enabled,gui.Enabled = false,false
        tint.TintColor,tint.Saturation,tint.Brightness,tint.Contrast = neutral,0,0,0
        veil.BackgroundTransparency = 1
    end

    local function followCamera()
        local camera = workspace.CurrentCamera
        if not camera then return end
        dust.CFrame = camera.CFrame*CFrame.new(-7.3,-1.7,-19)
    end

    local api = {}
    api.DurationSeconds = duration

    function api.Play(finished: (() -> ())?): boolean
        if active or dead then return false end
        clear()
        local stamp = version
        active = true
        local reduced = GuiService.ReducedMotionEnabled
        if not reduced then
            followCamera()
            follow = RunService.RenderStepped:Connect(followCamera)
            for _, e in particles do e.Enabled=true end
        end
        gui.Enabled,tint.Enabled = true,true
        animate(veil,gust,{BackgroundTransparency = if reduced then .67 else .31})
        animate(tint,gust,{
            TintColor = if reduced then Color3.fromRGB(255,235,204) else Color3.fromRGB(255,210,151),
            Saturation = if reduced then -.12 else -.33,
            Brightness = if reduced then -.008 else -.055,
            Contrast = .025,
        })
        task.delay(clearAt,function()
            if stamp~=version then return end
            for _, e in particles do e.Enabled=false end
            animate(veil,clearing,{BackgroundTransparency=1})
            animate(tint,clearing,{TintColor=neutral,Saturation=0,Brightness=0,Contrast=0})
        end)
        task.delay(duration,function()
            if stamp~=version then return end
            clear()
            if finished then finished() end
        end)
        return true
    end

    api.Stop = clear
    function api.Destroy()
        if dead then return end
        dead = true
        clear()
        dust:Destroy()
        tint:Destroy()
        gui:Destroy()
    end
    return api
end

return table.freeze({Mount=mount})
]==]

local pack = Instance.new("Folder")
pack.Name = packageName
pack:SetAttribute("Owner",owner)
pack:SetAttribute("DurationSeconds",2.4)
pack:SetAttribute("ClearAtSeconds",.91)

local binder = Instance.new("ModuleScript")
binder.Name,binder.Source,binder.Parent = "Transition",binderSource,pack

local volume = Instance.new("Part")
volume.Name,volume.Size = "SandVolume",Vector3.new(31,13,16.5)
volume.Anchored,volume.Transparency,volume.CastShadow = true,1,false
volume.CanCollide,volume.CanQuery,volume.CanTouch = false,false,false
volume.Parent = pack

local tint = Instance.new("ColorCorrectionEffect")
tint.Name,tint.Enabled,tint.Parent = "AmberGrade",false,pack

local function curve(stops: {{number}}): NumberSequence
    local keys = {}
    for _, row in stops do table.insert(keys,NumberSequenceKeypoint.new(row[1],row[2],row[3] or 0)) end
    return NumberSequence.new(keys)
end

local function dust(label: string,texture: string,rate: number,alpha: NumberSequence,sizes: NumberSequence,isDust: boolean)
    local item = Instance.new("ParticleEmitter")
    item.Name,item.Enabled,item.Rate = label,false,rate
    item.Texture = "rbxasset://textures/particles/"..texture
    item.Color = ColorSequence.new(Color3.fromRGB(223,170,110),Color3.fromRGB(242,202,143))
    item.EmissionDirection = Enum.NormalId.Right
    item.LockedToPart = true
    item.Speed = if isDust then NumberRange.new(19,31) else NumberRange.new(34,55)
    item.Lifetime = if isDust then NumberRange.new(.58,1.05) else NumberRange.new(.32,.68)
    item.SpreadAngle = if isDust then Vector2.new(13,10) else Vector2.new(16,12)
    item.Rotation,item.RotSpeed = NumberRange.new(0,360),NumberRange.new(-95,95)
    item.Acceleration = Vector3.new(0,if isDust then .5 else -5.9,0)
    item.LightInfluence,item.Drag = .56,if isDust then .63 else .25
    item.Size,item.Transparency = sizes,alpha
    item.Parent = volume
end
dust("WindborneDust","smoke_main.dds",29,
    curve({{0,.91},{.16,.47},{.53,.61},{1,1}}),
    curve({{0,2.4,.59},{.36,6.6,1.3},{1,9.3,.87}}),true)
dust("PassingGrains","SquareParticle.png",68,
    curve({{0,.17},{.17,.06},{.65,.23},{1,1}}),
    curve({{0,.061,.018},{.31,.119,.047},{1,.062}}),false)

local function verify(root: Folder)
    assert(root.Transition.Source==binderSource and not root.AmberGrade.Enabled)
    assert(root.SandVolume.Anchored and root.SandVolume.Transparency==1 and not root.SandVolume.CanQuery)
    assert(#root.SandVolume:GetChildren()==2 and root:GetAttribute("DurationSeconds")==2.4)
    for _, emitter in root.SandVolume:GetChildren() do
        assert(emitter:IsA("ParticleEmitter") and not emitter.Enabled and emitter.LockedToPart)
    end
end

if roblox and fs and luau then
    luau.compile(binderSource)
    local output = "assets/world/sandstorm_fx/DuneBaron_Sandstorm_FX.rbxm"
    local data = roblox.serializeModel({pack})
    verify(roblox.deserializeModel(data)[1])
    fs.writeFile(output,data)
    assert(fs.readFile(output)==data)
    print(output,"verified")
else
    local run = game:GetService("RunService")
    assert(run:IsStudio() and not run:IsRunning() and game.PlaceId==135831532782380,"Use Every Last Grain in Studio Edit")
    local storage = game:GetService("ServerStorage")
    local old = storage:FindFirstChild(packageName)
    assert(not old or old:GetAttribute("Owner")==owner)
    verify(pack)
    if old then old:Destroy() end
    pack.Parent = storage
    return {path=pack:GetFullName(),duration=pack:GetAttribute("DurationSeconds")}
end
