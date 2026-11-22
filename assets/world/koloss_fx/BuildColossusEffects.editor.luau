--!strict
-- Builds a portable Koloss art-effects package in Studio Edit or with Lune.
local offline = game == nil
local roblox = if offline then require("@lune/roblox") else nil
local fs = if offline then require("@lune/fs") else nil
local luau = if offline then require("@lune/luau") else nil
local Instance = if roblox then roblox.Instance else Instance
local CFrame = if roblox then roblox.CFrame else CFrame
local Vector2 = if roblox then roblox.Vector2 else Vector2
local Vector3 = if roblox then roblox.Vector3 else Vector3
local Color3 = if roblox then roblox.Color3 else Color3
local ColorSequence = if roblox then roblox.ColorSequence else ColorSequence
local NumberRange = if roblox then roblox.NumberRange else NumberRange
local NumberSequence = if roblox then roblox.NumberSequence else NumberSequence
local NumberSequenceKeypoint = if roblox then roblox.NumberSequenceKeypoint else NumberSequenceKeypoint
local Enum = if roblox then roblox.Enum else Enum

local C, V, rgb = CFrame.new, Vector3.new, Color3.fromRGB
local n = NumberRange.new
local name = "DuneBaronColossusEffects"
local owner = "DuneBaronColossusFxArt"

local moduleSource = [==[
--!strict
-- One local instance for an event viewer. The controller supplies confirmed event cues.
local TweenService = game:GetService("TweenService")
local holdAndFade = TweenInfo.new(1.02,Enum.EasingStyle.Quad,Enum.EasingDirection.Out,0,false,.12)
local up = Vector3.yAxis

local function burst(origin: Instance)
    for _, node in origin:GetChildren() do
        if node:IsA("ParticleEmitter") then
            node:Emit(node:GetAttribute("BurstCount") :: number)
        end
    end
end

local function mount(parent: Instance)
    local pack = assert(script.Parent)
    local stage = Instance.new("Folder")
    stage.Name = "ColossusLocalEffects"
    local dust = assert(pack:FindFirstChild("SectionBurst")):Clone() :: BasePart
    local core = assert(pack:FindFirstChild("ReliefPulse")):Clone() :: BasePart
    local epicenter = assert(core:FindFirstChild("Epicenter"))
    local light = assert(epicenter:FindFirstChildWhichIsA("PointLight"))
    dust.Parent,core.Parent = stage,stage
    stage.Parent = parent

    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Include
    ray.FilterDescendantsInstances = {workspace.Terrain}
    ray.IgnoreWater = true
    local pulse = TweenService:Create(light,holdAndFade,{Brightness=0})
    local dead = false
    local api = {}

    function api.Section(center: Vector3)
        if dead or not stage:IsDescendantOf(workspace) then return end
        dust.CFrame = CFrame.new(center)
        for _, origin in dust:GetChildren() do
            if not origin:IsA("Attachment") then continue end
            local offset = origin:GetAttribute("RestOffset") :: Vector3
            local target = center+offset
            local hit = workspace:Raycast(target+up*30,-up*64,ray)
            if not hit then continue end
            local horizontal = Vector3.new(offset.X,0,offset.Z).Unit
            local tangent = horizontal-hit.Normal*horizontal:Dot(hit.Normal)
            local position = hit.Position+hit.Normal*.34
            origin.WorldCFrame = CFrame.lookAt(position, position+tangent+hit.Normal*.49)
            burst(origin)
        end
    end

    function api.Complete(relief: BasePart)
        if dead or not stage:IsDescendantOf(workspace) or not relief:IsDescendantOf(workspace) then return end
        local normal = relief.CFrame.RightVector
        if normal.Y<0 then normal = -normal end
        local surface = relief.Position+normal*(relief.Size.X*.5+.28)
        core.CFrame = CFrame.lookAt(surface,surface+normal,relief.CFrame.LookVector)
        pulse:Cancel()
        light.Brightness = light:GetAttribute("PeakBrightness") :: number
        for _, origin in core:GetChildren() do burst(origin) end
        pulse:Play()
    end

    function api.Destroy()
        if dead then return end
        dead = true
        pulse:Cancel()
        pulse:Destroy()
        stage:Destroy()
    end

    return api
end

return table.freeze({Mount=mount})
]==]

local pack = Instance.new("Folder")
pack.Name = name
pack:SetAttribute("Owner",owner)
pack:SetAttribute("ArtRevision",1)
pack:SetAttribute("ReliefName","Dark teal stone inlay")
local module = Instance.new("ModuleScript")
module.Name,module.Source,module.Parent = "Effects",moduleSource,pack

local function part(label: string): Part
    local root = Instance.new("Part")
    root.Name,root.Size = label,V(.10,.10,.10)
    root.Anchored,root.Transparency,root.CastShadow = true,1,false
    root.CanCollide, root.CanTouch, root.CanQuery = false,false,false
    root.Parent = pack
    return root
end

local function attachment(parent: BasePart, label: string, offset: Vector3, direction: Vector3): Attachment
    local p = Instance.new("Attachment")
    p.Name,p.CFrame = label,CFrame.lookAt(offset,offset+direction)
    p.Parent = parent
    return p
end

local function curve(stops: {{number}}): NumberSequence
    local keypoints = {}
    for _, stop in stops do
        table.insert(keypoints,NumberSequenceKeypoint.new(stop[1],stop[2],stop[3] or 0))
    end
    return NumberSequence.new(keypoints)
end

type Look = {
    texture: string, colors: ColorSequence, count: number, size: NumberSequence, alpha: NumberSequence,
    life: NumberRange, speed: NumberRange, spread: number, gravity: number, drag: number, additive: number,
}
local function emitter(parent: Attachment,label: string,look: Look)
    local e = Instance.new("ParticleEmitter")
    e.Name,e.Texture = label,"rbxasset://textures/particles/"..look.texture
    e.Enabled,e.Rate = false,0
    e.Color,e.Size,e.Transparency = look.colors,look.size,look.alpha
    e.Lifetime,e.Speed,e.Drag = look.life,look.speed,look.drag
    e.Acceleration = V(0,look.gravity,0)
    e.SpreadAngle,e.EmissionDirection = Vector2.new(look.spread,look.spread),Enum.NormalId.Front
    e.LightEmission,e.LightInfluence = look.additive,if look.additive>.2 then .04 else .66
    e.Rotation,e.RotSpeed = n(0,360),n(-110,110)
    e:SetAttribute("BurstCount",look.count)
    e.Parent = parent
end

local section = part("SectionBurst")
local powder: Look = {
    texture="smoke_main.dds",colors=ColorSequence.new(rgb(207,155,96),rgb(239,197,143)),count=4,
    size=curve({{0,.90},{.30,3.8,.52},{1,5.1,.65}}),alpha=curve({{0,.58},{.18,.19},{.52,.40},{1,1}}),
    life=n(.59,.98),speed=n(2.8,6.3),spread=34,gravity=.55,drag=1.65,additive=0,
}
local grains: Look = {
    texture="SquareParticle.png",colors=ColorSequence.new(rgb(194,130,68),rgb(218,168,104)),count=11,
    size=curve({{0,.21,.062},{.49,.18,.052},{1,.103}}),alpha=curve({{0,.03},{.73,.11},{1,1}}),
    life=n(.32,.54),speed=n(4.5,10.2),spread=32,gravity=-34,drag=.63,additive=0,
}
for i=1,8 do
    local angle = math.pi*2*(i/8+.04)
    local dir = V(math.cos(angle),0,math.sin(angle))
    local radius = 4.65+.80*math.sin(1.54*i)
    local at = attachment(section,"Flank"..i,dir*radius,dir+V(0,.49,0))
    at:SetAttribute("RestOffset",dir*radius)
    emitter(at,"Dust",powder)
    emitter(at,"Grit",grains)
end

local finish = part("ReliefPulse")
local bright = attachment(finish,"Epicenter",V(0,0,0),V(0,0,-1))
local light = Instance.new("PointLight")
light.Name,light.Color,light.Range,light.Brightness = "ReliefLight",rgb(65,235,219),30,0
light.Shadows = false
light:SetAttribute("PeakBrightness",6.4)
light.Parent = bright
emitter(bright,"TealFlare",{
    texture="sparkles_main.dds",colors=ColorSequence.new(rgb(193,255,242),rgb(64,230,219)),count=1,
    size=curve({{0,2.4},{.25,8.8},{.70,10.9},{1,11.4}}),alpha=curve({{0,.64},{.15,.06},{.44,.36},{1,1}}),
    life=n(.84,.84),speed=n(.85),spread=0,gravity=0,drag=0,additive=1,
})
local glints: Look = {
    texture="sparkles_main.dds",colors=ColorSequence.new(rgb(166,255,227),rgb(255,199,111)),count=7,
    size=curve({{0,.24,.05},{.25,.42,.12},{1,.09}}),alpha=curve({{0,.43},{.19,.07},{.58,.29},{1,1}}),
    life=n(.49,.91),speed=n(3.0,6.5),spread=38,gravity=-5.0,drag=.88,additive=.81,
}
for i=1,6 do
    local theta = math.pi*2*i/6
    local dir=V(math.cos(theta),math.sin(theta),0)
    local edge = attachment(finish,"ReliefEdge"..i,dir*6.28,dir*.44+V(0,0,-1))
    emitter(edge,"Glints",glints)
end

local function verify(root: Folder)
    assert(root.Effects.Source==moduleSource and root.ReliefPulse.Epicenter.ReliefLight.Brightness==0)
    assert(#root.SectionBurst:GetChildren()==8 and #root.ReliefPulse:GetChildren()==7)
    local count=0
    for _, inst in root:GetDescendants() do
        if inst:IsA("ParticleEmitter") then
            assert(not inst.Enabled and inst.Rate==0 and inst:GetAttribute("BurstCount")>0)
            count+=1
        elseif inst:IsA("BasePart") then
            assert(inst.Transparency==1 and inst.Anchored and not inst.CanCollide and not inst.CanQuery)
        end
    end
    assert(count==23)
    return count
end

if roblox and fs and luau then
    local output = "assets/world/koloss_fx/DuneBaron_Colossus_FX.rbxm"
    luau.compile(moduleSource)
    local bytes = roblox.serializeModel({pack})
    local restored = roblox.deserializeModel(bytes)[1]
    print(output,verify(restored))
    fs.writeFile(output,bytes)
    assert(fs.readFile(output)==bytes)
else
    local run = game:GetService("RunService")
    assert(run:IsStudio() and not run:IsRunning() and game.PlaceId==135831532782380,"Use Every Last Grain in Studio Edit")
    local storage = game:GetService("ServerStorage")
    local existing = storage:FindFirstChild(name)
    assert(not existing or existing:GetAttribute("Owner")==owner)
    local count = verify(pack)
    if existing then existing:Destroy() end
    pack.Parent = storage
    return {path=pack:GetFullName(),emitters=count}
end
