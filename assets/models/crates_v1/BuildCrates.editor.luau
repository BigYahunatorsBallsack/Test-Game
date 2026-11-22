-- Studio Edit or Lune. Builds the crate models, animation clips, and reveal effects.
local offline = game == nil
local roblox = if offline then require("@lune/roblox") else nil
local fs = if offline then require("@lune/fs") else nil
local Instance = if roblox then roblox.Instance else Instance
local CFrame = if roblox then roblox.CFrame else CFrame
local Color3 = if roblox then roblox.Color3 else Color3
local Vector3 = if roblox then roblox.Vector3 else Vector3
local Vector2 = if roblox then roblox.Vector2 else Vector2
local ColorSequence = if roblox then roblox.ColorSequence else ColorSequence
local NumberSequence = if roblox then roblox.NumberSequence else NumberSequence
local NumberSequenceKeypoint = if roblox then roblox.NumberSequenceKeypoint else NumberSequenceKeypoint
local NumberRange = if roblox then roblox.NumberRange else NumberRange
local Enum = if roblox then roblox.Enum else Enum
local C, V, rgb = CFrame.new, Vector3.new, Color3.fromRGB
local M = Enum.Material
local pi = math.pi
local rad = math.rad
local packName = "DuneBaronCrateRigs"
local owner = "DuneBaronCrateArt"

local function instance(class, name, parent)
    local p = Instance.new(class)
    p.Name, p.Parent = name, parent
    return p
end

local function part(parent, name, frame, size, color, material, joint, shape)
    local p = instance("Part", name, parent)
    p.Size, p.CFrame, p.Color, p.Material = size, frame, color, material or M.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored, p.Massless = joint == nil, joint ~= nil
    p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
    if shape == "Sphere" then
        local mesh = instance("SpecialMesh", "Rounded head", p)
        mesh.MeshType = Enum.MeshType.Sphere
    elseif shape == "Cylinder" then
        p.Shape = Enum.PartType.Cylinder
    end
    if joint then
        local weld = instance("Weld", "ShapeWeld", p)
        weld.Part0, weld.Part1, weld.C0 = joint, p, joint.CFrame:ToObjectSpace(frame)
    end
    return p
end

local function pivot(model, parent, name, at)
    local p = part(model, name, C(at), V(.045,.045,.045), rgb(31,31,31))
    p.Transparency, p.CastShadow = 1, false
    if parent then
        local hinge = instance("Motor6D", name .. "Joint", parent)
        hinge.Part0, hinge.Part1, hinge.C0 = parent, p, parent.CFrame:ToObjectSpace(p.CFrame)
        p.Anchored, p.Massless = false, true
    end
    return p
end

local specs = {
    {id="wood", title="Holzkiste", w=2.48, d=2.22, h=1.63, lid=.391,
        panel=rgb(152,85,45), trim=rgb(63,57,53), light=rgb(180,109,61), inside=rgb(98,64,40),
        pin=rgb(156,138,112), lock=rgb(216,157,58), bodyMat=M.WoodPlanks, trimMat=M.SmoothPlastic,
        open=.81, close=.57, wait=.24, angle=101, spring=3.7,
        glow={color=rgb(255,180,90), spark=rgb(255,210,117), size=1.78, reach=4.8, peak=3.2, fade=.43, count=8}},
    {id="iron", title="Eisenkiste", w=2.79, d=2.43, h=1.59, lid=.427,
        panel=rgb(57,65,73), trim=rgb(83,94,105), light=rgb(103,115,121), inside=rgb(48,53,58),
        pin=rgb(139,150,153), lock=rgb(210,155,63), bodyMat=M.Metal, trimMat=M.Metal,
        open=1.16, close=.84, wait=.31, angle=99, spring=1.6,
        glow={color=rgb(104,181,255), spark=rgb(181,222,255), size=2.10, reach=5.7, peak=4.4, fade=.50, count=13}},
    {id="gold", title="Goldkiste", w=2.98, d=2.59, h=1.83, lid=.472,
        panel=rgb(54,50,49), trim=rgb(219,157,40), light=rgb(242,192,72), inside=rgb(84,60,46),
        pin=rgb(247,210,123), lock=rgb(242,185,68), bodyMat=M.SmoothPlastic, trimMat=M.Metal,
        open=.98, close=.68, wait=.26, angle=105, spring=2.7,
        glow={color=rgb(255,174,45), spark=rgb(255,223,86), size=2.70, reach=6.6, peak=6.5, fade=.62, count=20}},
    {id="event", title="Event-Kiste", w=3.10, d=2.73, h=1.91, lid=.509,
        panel=rgb(26,83,88), trim=rgb(199,151,85), light=rgb(231,184,110), inside=rgb(33,61,65),
        pin=rgb(230,196,129), lock=rgb(215,171,103), bodyMat=M.SmoothPlastic, trimMat=M.Sandstone,
        open=1.28, close=.78, wait=.34, angle=108, spring=2.4,
        glow={color=rgb(76,242,241), spark=rgb(170,132,255), size=2.96, reach=7.2, peak=7.3, fade=.69, count=24}},
}

local pack = instance("Folder",packName)
pack:SetAttribute("Owner",owner)
pack:SetAttribute("AssetRevision",2)

local revealSource = [==[
--!strict
-- Bind on the client before playing the crate's Open track.
local TweenService = game:GetService("TweenService")
local PEAK_HOLD_SECONDS = 0.08

local function bind(crate: Model, openTrack: AnimationTrack): RBXScriptConnection
    local origin = (crate.PrimaryPart :: BasePart):FindFirstChild("RevealOrigin") :: Attachment
    local light = origin:FindFirstChild("RevealLight") :: PointLight
    local flare = origin:FindFirstChild("Flare") :: ParticleEmitter
    local sparkles = origin:FindFirstChild("Sparkles") :: ParticleEmitter
    local motes = origin:FindFirstChild("Motes") :: ParticleEmitter
    local peak = light:GetAttribute("PeakBrightness") :: number
    local fade = TweenInfo.new(
        light:GetAttribute("FadeSeconds") :: number,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out,
        0,
        false,
        PEAK_HOLD_SECONDS
    )
    local sparkCount = sparkles:GetAttribute("BurstCount") :: number
    local moteCount = motes:GetAttribute("BurstCount") :: number
    local pulse = TweenService:Create(light, fade, {Brightness = 0})

    return openTrack:GetMarkerReachedSignal("Reveal"):Connect(function()
        if not origin:IsDescendantOf(workspace) then
            return
        end
        pulse:Cancel()
        light.Brightness = peak
        flare:Emit(1)
        sparkles:Emit(sparkCount)
        motes:Emit(moteCount)
        pulse:Play()
    end)
end

return table.freeze({Bind = bind})
]==]

local function curve(...)
    local points = {}
    for _,pair in {...} do
        table.insert(points,NumberSequenceKeypoint.new(pair[1],pair[2]))
    end
    return NumberSequence.new(points)
end

local function revealEffects(model, origin, glow)
    local effect = instance("ModuleScript","RevealEffects",model)
    effect.Source = revealSource

    local light = instance("PointLight","RevealLight",origin)
    light.Color, light.Range, light.Brightness = glow.color,glow.reach,0
    light.Shadows = false
    light:SetAttribute("PeakBrightness",glow.peak)
    light:SetAttribute("FadeSeconds",glow.fade)

    local texturePath = "rbxasset://textures/particles/"
    local function emitter(name, texture, color)
        local e = instance("ParticleEmitter",name,origin)
        e.Texture, e.Color = texturePath .. texture, color
        e.Enabled, e.Rate = false,0
        e.LightEmission, e.LightInfluence = 1,0
        e.EmissionDirection = Enum.NormalId.Top
        return e
    end

    local white = rgb(255,255,255)
    local flare = emitter("Flare","sparkles_main.dds",ColorSequence.new(white:Lerp(glow.color,.60),glow.color))
    flare.Lifetime = NumberRange.new(glow.fade*.79)
    flare.Speed = NumberRange.new(2.2)
    flare.Size = curve({0,.39},{.19,glow.size},{.62,glow.size*1.11},{1,glow.size*1.14})
    flare.Transparency = curve({0,.28},{.14,.02},{.44,.32},{1,1})
    flare.ZOffset = .21

    local sparkles = emitter("Sparkles","sparkles_main.dds",ColorSequence.new(white:Lerp(glow.spark,.56),glow.spark))
    sparkles.Lifetime = NumberRange.new(.40,glow.fade+.28)
    sparkles.Speed = NumberRange.new(2.6,glow.size*2.5)
    sparkles.SpreadAngle = Vector2.new(48,48)
    sparkles.Acceleration = V(0,-5.8,0)
    sparkles.Drag = 1.7
    sparkles.Size = curve({0,.035},{.13,.23},{.47,.15},{1,0})
    sparkles.Transparency = curve({0,.35},{.12,0},{.55,.22},{1,1})
    sparkles.Rotation, sparkles.RotSpeed = NumberRange.new(-45,45),NumberRange.new(-115,115)
    sparkles:SetAttribute("BurstCount",glow.count)

    local motes = emitter("Motes","SquareParticle.png",ColorSequence.new(glow.color,glow.spark))
    motes.Lifetime = NumberRange.new(.27,glow.fade+.17)
    motes.Speed = NumberRange.new(2.8,glow.size*3.6)
    motes.SpreadAngle = Vector2.new(66,66)
    motes.Acceleration = V(0,-8.4,0)
    motes.Drag = 2.3
    motes.Size = curve({0,.02},{.12,.12},{.57,.065},{1,0})
    motes.Transparency = curve({0,.20},{.14,.07},{.46,.19},{1,1})
    motes.Rotation, motes.RotSpeed = NumberRange.new(0,90),NumberRange.new(-85,85)
    motes:SetAttribute("BurstCount",math.floor(glow.count*.72))
end

local function build(box)
    local m = instance("Model",box.id,pack)
    m:SetAttribute("CrateId",box.id)
    m:SetAttribute("DisplayName",box.title)
    m:SetAttribute("ForwardAxis","-Z")
    m:SetAttribute("DesignReference","assets/icons/crates/icon_crates_".. box.id .. "_01.png")
    instance("Animator","Animator",instance("AnimationController","AnimationController",m))

    local root = pivot(m,nil,"Root",V(0,0,0))
    m.PrimaryPart = root
    local w,d,h,l = box.w,box.d,box.h,box.lid
    local seam = if box.id == "event" then .088 else .044
    local lidY = h + seam
    local latchOffset = .14
    local latchY = h-.178
    local lid = pivot(m,root,"Lid",V(0,lidY,d/2+.165))
    local latch = pivot(m,root,"Latch",V(0,latchY,-d/2-.117-latchOffset))
    local emit = instance("Attachment","RevealOrigin",root)
    emit.Position = V(0,h+.32,-.072)
    revealEffects(m,emit,box.glow)

    local geo = instance("Folder","Geometry",m)
    local bodyGeo = instance("Folder","Case",geo)
    local lidGeo = instance("Folder","Lid",geo)
    local hingeGeo = instance("Folder","Latch",geo)
    local function body(name,cf,size,color,material,shape)
        return part(bodyGeo,name,cf,size,color or box.panel,material or box.bodyMat,root,shape)
    end
    local function top(name,cf,size,color,material,shape)
        return part(lidGeo,name,cf,size,color or box.panel,material or box.bodyMat,lid,shape)
    end
    local function clasp(name,cf,size,color,material,shape)
        return part(hingeGeo,name,cf-V(0,0,latchOffset),size,color or box.lock,material or box.trimMat,latch,shape)
    end

    local floor = .205
    local thickness = .148
    body("Solid base plate",C(0,floor/2,0),V(w,floor,d))
    body("Interior floor liner",C(0,floor+.025,0),V(w-thickness*2-.026,.048,d-thickness*2-.026),box.inside,M.Fabric)
    for _,side in {-1,1} do
        body("Side wall",C(side*(w-thickness)/2,(h+floor)/2,0),V(thickness,h-floor,d))
        body("End wall",C(0,(h+floor)/2,side*(d-thickness)/2),V(w-2*thickness,h-floor,thickness))
        body("Inset side lining",C(side*(w/2-thickness-.009),(h+floor)/2,0),
            V(.021,h-floor-.115,d-2*thickness-.035),box.inside,M.Fabric)
        body("Inset end lining",C(0,(h+floor)/2,side*(d/2-thickness-.009)),
            V(w-2*thickness-.045,h-floor-.115,.021),box.inside,M.Fabric)
    end

    top("Lid plate",C(0,lidY+l*.49,0),V(w+.078,l*.73,d+.072))
    top("Lid inner panel",C(0,lidY+l*.091,0),V(w-.24,l*.13,d-.227),box.inside,M.Fabric)
    local trim, light = box.trim, box.light
    for _,side in {-1,1} do
        for _,dir in {-1,1} do
            local at = V(side*(w/2-.116),0,dir*(d/2-.109))
            body("Reinforced corner boot",C(at + V(0,.212,0)),V(.41,.408,.398),trim,box.trimMat)
            body("Corner column",C(at + V(0,h*.497,0)),V(.287,h*.74,.277),trim,box.trimMat)
            top("Lid corner cap",C(at + V(0,lidY+l*.512,0)),V(.43,l+.031,.421),
                if box.id=="wood" then trim else light,box.trimMat)
        end
    end

    for face = 0,3 do
        local angle = face*pi/2
        local side = face%2 == 1
        local span, depth = if side then d else w, if side then w else d
        local outer = CFrame.Angles(0,angle,0)*C(0,0,-depth/2)
        body("Lower edge strap",outer*C(0,.250,-.041),V(span-.289,.227,.090),trim,box.trimMat)
        body("Upper lip",outer*C(0,h-.083,-.041),V(span-.259,.142,.091),trim,box.trimMat)
        local bandColor = if box.id=="event" then rgb(34,108,112) elseif box.id=="wood" then light else trim
        local bandMaterial = if box.id=="event" then M.SmoothPlastic elseif box.id=="wood" then M.WoodPlanks else box.trimMat
        top("Lid band",outer*C(0,lidY+l*.424,-.053),V(span-.278,l*.882,.115),bandColor,bandMaterial)
        if box.id == "wood" then
            for row = 1,3 do
                local widths = {span-.42,span-.452,span-.471}
                body("Raised plank",outer*C(.017*(row-2),.345+(row-.50)*(h-.55)/3,-.018),
                    V(widths[row],(h-.55)/3-.034,.047),box.panel:Lerp(light,.14*row),M.WoodPlanks)
            end
            for _,s in {-1,1} do
                body("Square nail head",outer*C(s*(span/2-.148),.196,-.103),V(.068,.071,.035),box.pin,M.Metal)
            end
        elseif box.id == "iron" then
            body("Inset iron panel",outer*C(0,h*.569,-.018),V(span-.55,h*.500,.051),box.panel:Lerp(trim,.22),M.Metal)
            for _,s in {-1,1} do
                for _,y in {.192,h-.088} do
                    body("Domed rivet",outer*C(s*(span/2-.157),y,-.106),V(.144,.144,.081),box.pin,M.Metal,"Sphere")
                end
                top("Rivet on the lid band",outer*C(s*(span/2-.147),lidY+l*.57,-.11),V(.134,.134,.076),box.pin,M.Metal,"Sphere")
            end
        else
            local accent = if box.id=="event" then box.light else box.lock
            body("Recessed decorative panel",outer*C(0,h*.555,-.022),V(span-.481,h*.55,.062),
                box.panel:Lerp(box.inside,.17),M.SmoothPlastic)
            local ornament = outer*C(0,h*.568,-.068)*CFrame.Angles(0,0,pi/4)
            body("Diamond ornament surround",ornament,V(.609,.609,.101),trim,box.trimMat)
            body("Diamond ornament face",ornament*C(0,0,-.05),V(.521,.52,.077),accent,box.trimMat)
            if box.id == "event" then
                body("Cyan seam under lid",outer*C(0,h+seam*.40,-.036),V(span+.04,seam*.64,.118),rgb(86,214,220),M.Neon)
            end
        end
    end

    if box.id == "wood" then
        for i = -1,1 do
            top("Lid plank",C(0,lidY+l*.92,i*d*.244),V(w-.411,.063,d*.231),box.panel:Lerp(light,(i+2)*.16),M.WoodPlanks)
        end
    else
        top("Raised lid field",C(0,lidY+l*.885,0),V(w-.448,.103,d-.411),box.panel:Lerp(light,if box.id=="gold" then .47 else .20),box.bodyMat)
        for _,s in {-1,1} do
            top("Long lid rim",C(s*(w/2-.165),lidY+l*.975,0),V(.20,.102,d-.397),light,box.trimMat)
            top("Short lid rim",C(0,lidY+l*.975,s*(d/2-.159)),V(w-.402,.102,.194),light,box.trimMat)
        end
    end

    for _,s in {-1,1} do
        local x = s*w*.286
        body("Back hinge plate",C(x,h-.192,d/2+.046),V(.37,.35,.098),trim,box.trimMat)
        body("Fixed hinge barrel",C(x,lidY,d/2+.165),V(.266,.164,.164),trim,box.trimMat,"Cylinder")
        top("Moving hinge knuckle",C(x+.165,lidY,d/2+.165),V(.097,.171,.171),light,box.trimMat,"Cylinder")
        top("Hinge leaf",C(x,lidY+l*.292,d/2+.092),V(.29,.25,.176),trim,box.trimMat)
    end

    -- The keeper is attached to the lid. The lock swings out on its own pivot.
    local front = -d/2
    top("Lid keeper",C(0,lidY+l*.46,front-.105),V(if box.id=="iron" then .431 else .346,l*.72,.158),trim,box.trimMat)
    body("Latch mount",C(0,latchY-.035,front-.085),V(.425,.127,.18),trim,box.trimMat)
    for _,s in {-1,1} do
        body("Latch fork",C(s*.188,latchY,front-.201),V(.045,.098,.147),trim,box.trimMat)
    end
    body("Latch hinge pin",latch.CFrame,V(.417,.092,.092),box.pin,box.trimMat,"Cylinder")
    if box.id=="wood" or box.id=="iron" then
        clasp("Latch tongue",C(0,latchY-.057,front-.1),V(.316,.158,.105),trim,box.trimMat)
        clasp("Brass lock",C(0,latchY-.236,front-.168),V(if box.id=="iron" then .514 else .423,.340,.179),box.lock,M.Metal)
        if box.id=="iron" then
            clasp("Keyhole head",C(0,latchY-.193,front-.267),V(.094,.092,.020),rgb(38,37,36),M.SmoothPlastic,"Sphere")
            clasp("Keyhole stem",C(0,latchY-.263,front-.269),V(.047,.094,.014),rgb(38,37,36),M.SmoothPlastic)
        end
    else
        clasp("Short release lever",C(0,latchY-.071,front-.121),V(.248,.229,.121),box.lock,box.trimMat)
        clasp("Release lever thumb plate",C(0,latchY-.167,front-.157),V(.321,.084,.123),light,box.trimMat)
    end

    return m,instance("Folder","Animations",m)
end

local function smooth(t)
    t = math.clamp(t,0,1)
    return t*t*(3-2*t)
end

local function opening(spec,u)
    local endSwing = .84
    local q = math.clamp((u-spec.wait)/(endSwing-spec.wait),0,1)
    local swing = spec.angle*smooth(q)
    if u > .73 and u < 1 then swing += spec.spring*math.sin(pi*(u-.73)/.27) end
    local release = 51*smooth(u/(spec.wait*.81))
    return rad(swing),rad(release)
end

local function clip(box, model, folder, isOpen)
    local name = if isOpen then "Open" else "Close"
    local seq = instance("KeyframeSequence",name,folder)
    seq.Loop,seq.Priority = false,Enum.AnimationPriority.Action
    seq:SetAttribute("RigId",model.Name)
    local duration = if isOpen then box.open else box.close
    local count = math.ceil(duration*30)
    local reveal, release = false,false
    for i = 0,count do
        local u=i/count
        local key=instance("Keyframe","Keyframe",seq)
        key.Time=duration*u
        local root=instance("Pose","Root",key)
        root.Weight=0
        local lid, latch = opening(box,if isOpen then u else 1-u)
        for _,piece in {{"Lid",lid},{"Latch",latch}} do
            local p=instance("Pose",piece[1],root)
            p.CFrame=CFrame.Angles(piece[2],0,0)
            p.Weight=1
            p.EasingStyle=Enum.PoseEasingStyle.Linear
        end
        if isOpen then
            if not release and u>=box.wait*.81 then
                instance("KeyframeMarker","Unlatch",key)
                release=true
            end
            if not reveal and lid>=rad(72) then
                instance("KeyframeMarker","Reveal",key)
                reveal=true
            end
        elseif i==count-1 then
            instance("KeyframeMarker","Latch",key)
        end
    end
    return seq
end

for _,box in specs do
    local model, folder = build(box)
    clip(box,model,folder,true)
    clip(box,model,folder,false)
end

if offline then
    local path = "assets/models/crates_v1/DuneBaron_Crates.rbxm"
    local bytes = roblox.serializeModel({pack})
    local restored = roblox.deserializeModel(bytes)[1]
    local function ends(clip)
        local keys = clip:GetChildren()
        table.sort(keys,function(a,b) return a.Time<b.Time end)
        assert(keys[1].Time==0 and not clip.Loop)
        return keys[1].Root,keys[#keys].Root
    end
    assert(#restored:GetChildren()==4)
    for _,m in restored:GetChildren() do
        assert(m.PrimaryPart.Name=="Root" and #m.Animations:GetChildren()==2)
        local origin = m.Root.RevealOrigin
        assert(m.RevealEffects.Source==revealSource and origin.RevealLight.Brightness==0)
        for _,name in {"Flare","Sparkles","Motes"} do
            assert(origin[name]:IsA("ParticleEmitter") and not origin[name].Enabled and origin[name].Rate==0)
        end
        local closed,open=ends(m.Animations.Open)
        local closeStart,closeEnd=ends(m.Animations.Close)
        for _,name in {"Lid","Latch"} do
            assert(open[name].CFrame==closeStart[name].CFrame and closed[name].CFrame==closeEnd[name].CFrame)
        end
    end
    fs.writeFile(path,bytes)
    assert(fs.readFile(path)==bytes)
    print(path,"4 rigs and 8 clips verified")
else
    local run=game:GetService("RunService")
    assert(run:IsStudio() and not run:IsRunning(),"Use Studio Edit mode")
    assert(game.PlaceId==135831532782380,"Unexpected place")
    local storage=game:GetService("ServerStorage")
    local old=storage:FindFirstChild(packName)
    assert(not old or old:GetAttribute("Owner")==owner,"Existing folder belongs to another asset")
    if old then old:Destroy() end
    pack.Parent=storage
    return {path=pack:GetFullName(),rigs=4,clips=8}
end
