--!strict
-- Studio Edit or Lune. Builds a portable artist-authored effect for the Sandwurm clips.
local offline = game == nil
local roblox = if offline then require("@lune/roblox") else nil
local fs = if offline then require("@lune/fs") else nil
local Instance = if roblox then roblox.Instance else Instance
local CFrame = if roblox then roblox.CFrame else CFrame
local Vector3 = if roblox then roblox.Vector3 else Vector3
local Vector2 = if roblox then roblox.Vector2 else Vector2
local Color3 = if roblox then roblox.Color3 else Color3
local ColorSequence = if roblox then roblox.ColorSequence else ColorSequence
local NumberRange = if roblox then roblox.NumberRange else NumberRange
local NumberSequence = if roblox then roblox.NumberSequence else NumberSequence
local NumberSequenceKeypoint = if roblox then roblox.NumberSequenceKeypoint else NumberSequenceKeypoint
local Enum = if roblox then roblox.Enum else Enum
local V, C, rgb = Vector3.new, CFrame.new, Color3.fromRGB

local packageName = "DuneBaronSandwormSandFX"
local owner = "DuneBaronSandwormFxArt"
local pack = Instance.new("Folder")
pack.Name = packageName
pack:SetAttribute("Owner",owner)
pack:SetAttribute("SandFxRevision",1)

local code = [==[
--!strict
-- Call on the client with the three loaded non-looped tracks for one worm.
type Tracks = { Emerge: AnimationTrack, Bite: AnimationTrack, Burrow: AnimationTrack }
type Origin = {
    node: Attachment,
    localFrame: CFrame,
    space: string,
    delaySeconds: number,
    particles: {ParticleEmitter},
}

local function bind(worm: Model, tracks: Tracks): () -> ()
    local skin = assert(worm.PrimaryPart,"Expected a Sandwurm rig with a primary mesh")
    local head = skin:FindFirstChild("Head",true)
    assert(head and head:IsA("Bone"),"Expected the Sandwurm rig with Head bone")
    local headBone = head :: Bone
    local anchor = script.Parent:FindFirstChild("SandFxAnchor"):Clone() :: BasePart
    anchor.CFrame = worm:GetPivot()
    anchor.Parent = worm

    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Include
    ray.FilterDescendantsInstances = {workspace.Terrain}
    ray.IgnoreWater = true
    local up = Vector3.yAxis
    local connections: {RBXScriptConnection} = {}
    local byMarker: {[string]: {Origin}} = {}
    local active = true

    for _, child in anchor:GetChildren() do
        if not child:IsA("Attachment") then continue end
        local marker = child:GetAttribute("Marker") :: string
        local emitters: {ParticleEmitter} = {}
        for _, emitter in child:GetChildren() do
            if emitter:IsA("ParticleEmitter") then table.insert(emitters,emitter) end
        end
        if not byMarker[marker] then byMarker[marker] = {} end
        table.insert(byMarker[marker],{
            node=child,localFrame=child.CFrame,space=child:GetAttribute("Space") :: string,
            delaySeconds=child:GetAttribute("DelaySeconds") :: number,particles=emitters,
        })
    end

    local function fire(origin: Origin, track: AnimationTrack)
        if not active or not track.IsPlaying or not worm:IsDescendantOf(workspace) then return end
        local source = if origin.space=="Head" then headBone.TransformedWorldCFrame else worm:GetPivot()
        local frame = source*origin.localFrame
        if origin.space=="Sand" then
            local hit = workspace:Raycast(frame.Position+24*up,-56*up,ray)
            if not hit then return end
            local forward = frame.LookVector
            local planar = Vector3.new(forward.X,0,forward.Z)
            local tangent = planar - hit.Normal*planar:Dot(hit.Normal)
            forward = tangent + hit.Normal*forward.Y
            local surface = hit.Position+hit.Normal*.19
            frame = CFrame.lookAt(surface,surface+forward)
        end
        origin.node.WorldCFrame = frame
        for _, e in origin.particles do e:Emit(e:GetAttribute("BurstCount") :: number) end
    end

    local function connect(track: AnimationTrack, marker: string)
        table.insert(connections, track:GetMarkerReachedSignal(marker):Connect(function()
            for _, origin in byMarker[marker] do
                if origin.delaySeconds>0 then
                    task.delay(origin.delaySeconds,fire,origin,track)
                else
                    fire(origin,track)
                end
            end
        end))
    end
    connect(tracks.Emerge,"SandWarning")
    connect(tracks.Emerge,"Breach")
    connect(tracks.Bite,"Bite")
    connect(tracks.Burrow,"Burrow")

    return function()
        if not active then return end
        active = false
        for _, item in connections do item:Disconnect() end
        anchor:Destroy()
    end
end

return table.freeze({Bind = bind})
]==]

local binder = Instance.new("ModuleScript")
binder.Name,binder.Source,binder.Parent = "SandEffects",code,pack
local anchor = Instance.new("Part")
anchor.Name = "SandFxAnchor"
anchor.CFrame = C()
anchor.Size = V(.09,.09,.09)
anchor.Transparency, anchor.CastShadow = 1,false
anchor.Anchored = true
anchor.CanCollide,anchor.CanTouch,anchor.CanQuery = false,false,false
anchor.Parent = pack

local function spot(marker: string, name: string, at: Vector3, heading: Vector3, delaySeconds: number, space: string): Attachment
    local a = Instance.new("Attachment")
    a.Name = name
    a.CFrame = CFrame.lookAt(at,at+heading)
    a:SetAttribute("Marker",marker)
    a:SetAttribute("Space",space)
    a:SetAttribute("DelaySeconds",delaySeconds)
    a.Parent = anchor
    return a
end

local function sequence(points: {{number}}): NumberSequence
    local keys = {}
    for _, p in points do
        table.insert(keys,NumberSequenceKeypoint.new(p[1],p[2],p[3] or 0))
    end
    return NumberSequence.new(keys)
end

type Look = {
    count: number, life: NumberRange, speed: NumberRange, size: number,
    spread: number, drag: number, acceleration: Vector3, dust: boolean, warning: boolean?,
}
local function sand(origin: Attachment, look: Look)
    local d, size = look.dust, look.size
    local p = Instance.new("ParticleEmitter")
    p.Name = if d then "SandDust" else "SandGrains"
    p.Texture = "rbxasset://textures/particles/"..(if d then "smoke_main.dds" else "SquareParticle.png")
    p.Rate, p.Enabled = 0,false
    p.Lifetime, p.Speed, p.Drag, p.Acceleration = look.life,look.speed,look.drag,look.acceleration
    p.EmissionDirection = Enum.NormalId.Front
    p.SpreadAngle = Vector2.new(look.spread,look.spread)
    p.Rotation, p.RotSpeed = NumberRange.new(0,360),NumberRange.new(-105,105)
    p.LightInfluence = .69
    p.Color = if look.warning then ColorSequence.new(rgb(157,105,62),rgb(211,164,108))
        elseif d then ColorSequence.new(rgb(223,165,98),rgb(233,194,136))
        else ColorSequence.new(rgb(201,142,73),rgb(169,112,62))
    p.Size = if d then sequence({{0,.29*size},{.27,.75*size,.17*size},{1,size,.14*size}})
        else sequence({{0,size,.32*size},{.58,.81*size,.23*size},{1,.42*size,.10*size}})
    p.Transparency = if look.warning then sequence({{0,.44},{.15,.11},{.50,.28},{1,1}})
        elseif d then sequence({{0,.64},{.17,.27},{.49,.44},{1,1}})
        else sequence({{0,.05},{.62,.12},{.91,.62},{1,1}})
    p:SetAttribute("BurstCount",look.count)
    p.Parent = origin
end

local function radial(index: number, total: number, offset: number): Vector3
    local angle = (index/total + offset)*math.pi*2
    return V(math.cos(angle),0,math.sin(angle))
end
local n = NumberRange.new

local warningDust = {count=3,life=n(.48,.70),speed=n(3.2,5.1),size=3.1,spread=19,drag=1.7,acceleration=V(0,1.2,0),dust=true,warning=true}
local warningGrain = {count=4,life=n(.28,.47),speed=n(3.7,6.25),size=.157,spread=22,drag=1.05,acceleration=V(0,-16,0),dust=false}
for layer=1,2 do
    local total = if layer==1 then 8 else 10
    for i=1,total do
        local dir = radial(i,total,layer*.051)
        local radius = (if layer==1 then 3.1 else 7.15) + .6*math.sin(i*2.11)
        local delaySeconds = (layer-1)*.188+(i%3)*.029
        local source = spot("SandWarning","WarningRipple",dir*radius,dir+V(0,.63,0),delaySeconds,"Sand")
        sand(source,warningDust)
        sand(source,warningGrain)
    end
end

local liftDust = {count=3,life=n(.76,1.12),speed=n(5.0,10.1),size=5.45,spread=26,drag=1.85,acceleration=V(0,1.25,0),dust=true}
local thrust = {count=10,life=n(.52,.79),speed=n(18.0,29.0),size=.248,spread=20,drag=.28,acceleration=V(0,-59,0),dust=false}
for i=1,12 do
    local dir = radial(i,12,.027)
    local radius = 5.95+.77*math.sin(i*1.81)
    local source = spot("Breach","SandFan",dir*radius,dir*.72+V(0,1,0),(i%3)*.033,"Sand")
    sand(source,liftDust)
    sand(source,thrust)
end
for i=1,6 do
    local dir=radial(i,6,.084)
    local source = spot("Breach","FallingSand",dir*7.65,dir+V(0,.65,0),.108+(i%2)*.032,"Sand")
    sand(source,{count=7,life=n(.46,.71),speed=n(8.4,16),size=.192,spread=22,drag=.86,acceleration=V(0,-28,0),dust=false})
end

for _, side in {-1,1} do
    local source = spot("Bite","MouthEdge",V(side*5.9,3.14,.20),V(side,.18,-.32),0,"Head")
    sand(source,{count=12,life=n(.35,.54),speed=n(7.7,13.4),size=.179,spread=21,drag=.39,acceleration=V(0,-29,0),dust=false})
    sand(source,{count=2,life=n(.29,.43),speed=n(2.4,4.0),size=1.43,spread=25,drag=1.4,acceleration=V(0,-5.4,0),dust=true})
end

local collapseDust = {count=3,life=n(.50,.78),speed=n(6.2,10.2),size=3.28,spread=15,drag=1.4,acceleration=V(0,.36,0),dust=true}
local collapseGrain = {count=8,life=n(.39,.60),speed=n(11.0,17.1),size=.159,spread=13,drag=.44,acceleration=V(0,-15,0),dust=false}
for i=1,11 do
    local dir = radial(i,11,.017)
    local radius=7.9+.68*math.sin(i*1.42)
    local source = spot("Burrow","SandCollapse",dir*radius,-dir+V(0,.27,0),(i%3)*.038,"Sand")
    sand(source,collapseDust)
    sand(source,collapseGrain)
end
local settle = spot("Burrow","SettlingDust",V(0,0,0),V(.35,.21,.13),.214,"Sand")
sand(settle,{count=4,life=n(.66,.89),speed=n(1.4,3.9),size=4.24,spread=52,drag=2.0,acceleration=V(0,.82,0),dust=true})

local function verify(container: Folder): {[string]: number}
    assert(container.SandEffects.Source==code and container.SandFxAnchor.Transparency==1)
    local counts: {[string]: number} = {}
    for _, a in container.SandFxAnchor:GetChildren() do
        assert(a:IsA("Attachment"))
        local marker = a:GetAttribute("Marker") :: string
        counts[marker] = (counts[marker] or 0)+1
        for _, p in a:GetChildren() do
            assert(p:IsA("ParticleEmitter") and not p.Enabled and p.Rate==0)
        end
    end
    assert(counts.SandWarning==18 and counts.Breach==18 and counts.Bite==2 and counts.Burrow==12)
    return counts
end

if roblox and fs then
    local out = "assets/models/sandwurm_fx/DuneBaron_Sandworm_SandFX.rbxm"
    local bytes = roblox.serializeModel({pack})
    verify(roblox.deserializeModel(bytes)[1])
    fs.writeFile(out,bytes)
    assert(fs.readFile(out)==bytes)
    print(out,"four effects verified")
else
    local run = game:GetService("RunService")
    assert(run:IsStudio() and not run:IsRunning() and game.PlaceId==135831532782380,"Use Every Last Grain in Studio Edit")
    local storage = game:GetService("ServerStorage")
    local old = storage:FindFirstChild(packageName)
    assert(not old or old:GetAttribute("Owner")==owner)
    local counts=verify(pack)
    if old then old:Destroy() end
    pack.Parent = storage
    return {path=pack:GetFullName(),origins=counts}
end
