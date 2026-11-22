-- Studio Edit or Lune. This file builds native Roblox companion models and their clips.
local offline = game == nil
local roblox = if offline then require("@lune/roblox") else nil
local fs = if offline then require("@lune/fs") else nil
local Instance = if roblox then roblox.Instance else Instance
local CFrame = if roblox then roblox.CFrame else CFrame
local Color3 = if roblox then roblox.Color3 else Color3
local Vector3 = if roblox then roblox.Vector3 else Vector3
local Enum = if roblox then roblox.Enum else Enum
local C, V, rgb = CFrame.new, Vector3.new, Color3.fromRGB
local pi, tau = math.pi, 2 * math.pi
local ball, block = Enum.PartType.Ball, Enum.PartType.Block
local smooth = Enum.Material.SmoothPlastic
local ROOT_NAME = "DuneBaronCompanionRigs"
local OWNER = "DuneBaronCompanionArt"

local function create(class, name, parent)
    local p = Instance.new(class)
    p.Name = name
    p.Parent = parent
    return p
end

local function piece(parent, name, cf, size, color, shape)
    local p = create(if shape == "Wedge" then "WedgePart" else "Part", name, parent)
    p.CFrame, p.Size, p.Color, p.Material = cf, size, color, smooth
    p.Anchored, p.Massless = false, true
    p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    if shape == ball then
        -- Native Ball parts render round. A Sphere mesh follows the three box dimensions.
        local mesh = create("SpecialMesh", "Ellipsoid", p)
        mesh.MeshType = Enum.MeshType.Sphere
    end
    return p
end

local function ornament(rig, bone, name, cf, size, color, shape)
    local p = piece(rig.geometry, name, cf, size, color, shape)
    local weld = create("Weld", "ShapeWeld", p)
    weld.Part0, weld.Part1, weld.C0 = bone, p, bone.CFrame:ToObjectSpace(cf)
    return p
end

local function bone(rig, parent, name, at)
    local p = piece(rig.model, name, C(at), V(.05, .05, .05), rgb(0, 0, 0))
    p.Transparency, p.CastShadow = 1, false
    local node = {part = p, children = {}}
    if parent then
        local motor = create("Motor6D", name .. "Joint", parent.part)
        node.rest = parent.part.CFrame:ToObjectSpace(p.CFrame)
        motor.Part0, motor.Part1, motor.C0 = parent.part, p, node.rest
        table.insert(parent.children, node)
    end
    return node
end

local function oval(rig, node, name, at, size, color, rotation)
    return ornament(rig, node.part, name, C(at) * (rotation or C()), size, color, ball)
end

local function bar(rig, node, name, a, b, width, height, color, overlap, shape)
    local span = (b - a).Magnitude
    local up = if math.abs((b - a).Unit.Y) > .9 then V(0, 0, 1) else V(0, 1, 0)
    return ornament(rig, node.part, name, CFrame.lookAt((a + b) / 2, b, up),
        V(width, height, span + (overlap or 0)), color, shape or ball)
end

local pack = create("Folder", ROOT_NAME)
pack:SetAttribute("Owner", OWNER)
pack:SetAttribute("AssetRevision", 1)

local function newRig(id, display, bodyAt)
    local model = create("Model", id, pack)
    model:SetAttribute("CompanionId", id)
    model:SetAttribute("DisplayName", display)
    model:SetAttribute("ForwardAxis", "-Z")
    model:SetAttribute("DesignReference", "assets/reference/companions/ref_" .. id .. "_01.png")
    local rig = {model = model, geometry = create("Folder", "Geometry", model), legs = {}}
    rig.root = bone(rig, nil, "Root", V(0, 0, 0))
    rig.root.part.Anchored = true
    model.PrimaryPart = rig.root.part
    rig.body = bone(rig, rig.root, "Body", bodyAt)
    create("Animator", "Animator", create("AnimationController", "AnimationController", model))
    rig.clips = create("Folder", "Animations", model)
    return rig
end

local ink = rgb(47, 35, 33)
local glint = rgb(246, 224, 173)
local teal = rgb(37, 108, 113)
local deepTeal = rgb(31, 76, 83)
local brass = rgb(223, 167, 62)
local leather = rgb(149, 95, 49)

local function eye(rig, node, side, x, y, z, diameter)
    local yaw = CFrame.Angles(0, -side * .24, 0)
    oval(rig, node, "Dark eye", V(side * x, y, z), V(diameter, diameter * 1.08, diameter * .49), ink, yaw)
    oval(rig, node, "Eye catchlight", V(side * x - .020, y + .022, z - diameter * .235),
        V(diameter * .26, diameter * .27, .018), glint, yaw)
end

local function satchel(rig, at, size, goldBag)
    local node = rig.body.part
    local cf = C(at)
    local w, h, d = size.X, size.Y, size.Z
    ornament(rig, node, "Digging satchel", cf, size, if goldBag then brass else deepTeal)
    ornament(rig, node, "Satchel lid", cf * C(0, h * .43, -.012), V(w + .037, h * .28, d + .042), teal)
    ornament(rig, node, "Brass buckle", cf * C(0, h * .23, -d * .536), V(w * .34, h * .27, .038), brass)
    ornament(rig, node, "Back seam", cf * C(0, -h * .31, d * .508), V(w * .81, h * .095, .023), leather)
    for _,s in {-1, 1} do
        local a = at + V(s * w * .39, -.05, -d * .31)
        local b = a + V(s * w * .11, -h * .80, -d * .22)
        bar(rig, rig.body, "Leather harness", a, b, w * .114, w * .074, leather, .04, block)
    end
    local tool = cf * C(w * .53, .015, -.035) * CFrame.Angles(.09, .11, -.21)
    ornament(rig, node, "Mini spade shaft", tool * C(0, h * .16, 0), V(.064, h * 1.16, .067), leather)
    ornament(rig, node, "Spade grip", tool * C(0, h * .79, 0), V(.127, .068, .071), rgb(87, 61, 48))
    ornament(rig, node, "Steel spade blade", tool * C(0, -h * .49, 0),
        V(w * .164, h * .47, .047), rgb(75, 88, 94), ball)
    ornament(rig, node, "Tool loop", tool * C(0, -.015, 0), V(.096, .104, .08), brass)
end

local function wedgeEar(rig, side, x, y, z, hue, inset)
    local node = bone(rig, rig.head, if side == -1 then "EarLeft" else "EarRight", V(x, y, z))
    local lean = node.part.CFrame * CFrame.Angles(.045, side * -.08, -side * .32)
    for _,s in {-1, 1} do
        local rotation = CFrame.Angles(0, -s * pi / 2, 0)
        ornament(rig, node.part, "Tall ear edge", lean * C(s * .215, .525, 0) * rotation,
            V(.218, 1.05, .43), hue, "Wedge")
        ornament(rig, node.part, "Warm inner ear", lean * C(s * .144, .42, -.112) * rotation,
            V(.027, .75, .288), inset, "Wedge")
    end
    return node
end

local function roundEar(rig, side, x, y, z, hue, inset)
    local node = bone(rig, rig.head, if side == -1 then "EarLeft" else "EarRight", V(x, y, z))
    local at = node.part.CFrame * CFrame.Angles(-.105, -side * .25, -side * .21)
    ornament(rig, node.part, "Round ear", at * C(0, .12, 0), V(.66, .69, .26), hue, ball)
    ornament(rig, node.part, "Inner ear", at * C(0, .145, -.117), V(.507, .515, .072), inset, ball)
    return node
end

local function fourLegs(rig, frontZ, rearZ, x, hipY, footY, width, coat, socks)
    for _, leg in {{"ForeLeft", -1, frontZ, true}, {"ForeRight", 1, frontZ, true},
        {"HindLeft", -1, rearZ, false}, {"HindRight", 1, rearZ, false}} do
        local side, z = leg[2], leg[3]
        local hip = V(x * side, hipY + (if leg[4] then 0 else .024), z)
        local a, b = (hip.Y - footY) * .50, (hip.Y - footY) * .50
        local knee, ground = hip - V(0, a, 0), V(hip.X, footY, z)
        local upper = bone(rig, rig.body, leg[1], hip)
        local lower = bone(rig, upper, leg[1] .. "Shin", knee)
        local foot = bone(rig, lower, leg[1] .. "Paw", ground)
        oval(rig, upper, "Rounded upper leg", hip - V(0, a * .46, .015),
            V(width * (if leg[4] then 1 else 1.15), a + width * .54, width * 1.12), coat)
        oval(rig, lower, "Lower leg", knee - V(0, b * .48, 0),
            V(width * .83, b + width * .38, width * .91), coat)
        oval(rig, foot, "Matte paw", ground - V(0, 0, width * .24), V(width, footY * 2, width * 1.44), socks)
        table.insert(rig.legs, {upper = upper, lower = lower, foot = foot, hip = hip,
            target = ground, a = a, b = b, front = leg[4], side = side})
    end
end

local fennec = newRig("fennec", "Fennek", V(0, .90, .06))
do
    local coat, pale, tan = rgb(225, 155, 79), rgb(243, 217, 161), rgb(203, 119, 60)
    oval(fennec, fennec.body, "Long fox body", V(0, .96, .21), V(1.04, .94, 1.55), coat)
    oval(fennec, fennec.body, "Ivory chest", V(0, .97, -.35), V(.79, .81, .63), pale)
    fennec.head = bone(fennec, fennec.body, "Head", V(0, 1.29, -.50))
    oval(fennec, fennec.head, "Fox head", V(0, 1.54, -.68), V(1.18, .96, 1.02), coat)
    oval(fennec, fennec.head, "Narrow cream snout", V(0, 1.34, -1.09), V(.82, .39, .61), pale)
    oval(fennec, fennec.head, "Nose", V(0, 1.428, -1.39), V(.217, .133, .111), ink)
    for _,s in {-1, 1} do
        eye(fennec, fennec.head, s, .347, 1.58, -1.094, .134)
        oval(fennec, fennec.head, "Cheek fur", V(s * .362, 1.362, -.979), V(.366, .31, .44), pale)
    end
    fennec.ears = {wedgeEar(fennec, -1, -.44, 1.69, -.66, coat, rgb(242, 186, 133)),
        wedgeEar(fennec, 1, .44, 1.69, -.66, coat, rgb(242, 186, 133))}
    fourLegs(fennec, -.395, .68, .337, .81, .113, .303, coat, pale)
    local a, b, c = V(0, 1.020, .79), V(0, 1.12, 1.370), V(0, 1.36, 1.82)
    fennec.tail = bone(fennec, fennec.body, "Tail", a)
    fennec.tip = bone(fennec, fennec.tail, "TailTip", b)
    bar(fennec, fennec.tail, "Full fox brush", a - V(0, .071, .1), b, .54, .53, tan, .34)
    bar(fennec, fennec.tip, "Soft fox tail tip", b - V(0, .036, .082), c, .46, .43, pale, .20)
    satchel(fennec, V(0, 1.465, .46), V(.846, .405, .626), false)
end

local mouse = newRig("desert_mouse", "Wüstenmaus", V(0, .59, .025))
do
    local coat, pale, blush, paw = rgb(188, 127, 87), rgb(241, 207, 159), rgb(221, 151, 119), rgb(143, 88, 60)
    oval(mouse, mouse.body, "Round mouse body", V(0, .625, .105), V(.927, .786, 1.058), coat)
    oval(mouse, mouse.body, "Cream mouse chest", V(0, .608, -.218), V(.695, .613, .611), pale)
    mouse.head = bone(mouse, mouse.body, "Head", V(0, .869, -.341))
    oval(mouse, mouse.head, "Mouse head", V(0, 1.053, -.475), V(.963, .736, .812), coat)
    oval(mouse, mouse.head, "Small cream muzzle", V(0, .925, -.790), V(.685, .308, .391), pale)
    oval(mouse, mouse.head, "Mouse nose", V(0, .982, -.996), V(.132, .098, .088), rgb(128, 71, 61))
    for _,s in {-1, 1} do
        eye(mouse, mouse.head, s, .278, 1.116, -.800, .122)
        for j = 1, 2 do
            bar(mouse, mouse.head, "Whisker", V(s * .249, .920 - j * .021, -.944),
                V(s * (.507 + j * .041), .895 + j * .019, -.941 + j * .039), .018, .018, paw, .014)
        end
    end
    mouse.ears = {roundEar(mouse, -1, -.395, 1.212, -.494, coat, blush),
        roundEar(mouse, 1, .395, 1.212, -.494, coat, blush)}
    fourLegs(mouse, -.291, .405, .298, .472, .082, .218, coat, paw)
    local a, b, c = V(0, .44, .541), V(.155, .256, .972), V(.43, .399, 1.242)
    mouse.tail = bone(mouse, mouse.body, "Tail", a)
    mouse.tip = bone(mouse, mouse.tail, "TailTip", b)
    bar(mouse, mouse.tail, "Mouse tail base", a - V(0, .006, .054), a:Lerp(b, .60), .102, .097, blush, .105)
    bar(mouse, mouse.tail, "Tail into curl", a:Lerp(b, .54), b, .084, .083, blush, .085)
    bar(mouse, mouse.tip, "Tail curl", b, b:Lerp(c, .55) - V(0, .042, 0), .073, .073, blush, .077)
    bar(mouse, mouse.tip, "Tail taper", b:Lerp(c, .45) - V(0, .041, 0), c, .052, .056, blush, .060)
    satchel(mouse, V(0, 1.038, .315), V(.691, .333, .526), false)
end

local scarab = newRig("scarab", "Skarabäus", V(0, .414, 0))
do
    local dark, shell, edge = rgb(63, 56, 53), rgb(35, 126, 126), rgb(35, 93, 97)
    oval(scarab, scarab.body, "Scarab underside", V(0, .342, .055), V(1.05, .43, 1.46), dark)
    oval(scarab, scarab.body, "Teal carapace", V(0, .568, .108), V(1.138, .71, 1.50), shell)
    oval(scarab, scarab.body, "Dark carapace edge", V(0, .405, .129), V(1.155, .266, 1.52), edge)
    oval(scarab, scarab.body, "Gold shell seam", V(0, .670, .15), V(.072, .51, 1.407), brass)
    scarab.head = bone(scarab, scarab.body, "Head", V(0, .403, -.540))
    oval(scarab, scarab.head, "Round scarab head", V(0, .405, -.645), V(.684, .415, .596), dark)
    scarab.ears = {}
    for _,side in {-1, 1} do
        eye(scarab, scarab.head, side, .181, .448, -.881, .100)
        local a = V(.171 * side, .559, -.742)
        local b, c = a + V(.061 * side, .185, -.131), a + V(.149 * side, .208, -.262)
        local feeler = bone(scarab, scarab.head, if side == -1 then "FeelerLeft" else "FeelerRight", a)
        bar(scarab, feeler, "Feeler stem", a, b, .060, .060, dark, .073)
        bar(scarab, feeler, "Curved feeler", b, c, .052, .052, dark, .062)
        oval(scarab, feeler, "Feeler tip", c, V(.117, .083, .120), rgb(114, 87, 55))
        table.insert(scarab.ears, feeler)
        for i, z in {-.421, .071, .474} do
            local hip = V(.438 * side, .357, z)
            local knee = V((.675 + .025 * i) * side, .251, z + (i - 2) * .109)
            local tip = V((.768 + .036 * i) * side, .049, z + (i - 2) * .165)
            local name = (if side == -1 then "LegLeft" else "LegRight") .. i
            local joint = bone(scarab, scarab.body, name, hip)
            local tibia = bone(scarab, joint, name .. "Tip", knee)
            oval(scarab, joint, "Hip joint", hip, V(.236, .21, .23), dark)
            bar(scarab, joint, "Scarab leg", hip, knee, .140, .136, dark, .146)
            bar(scarab, tibia, "Scarab foot", knee, tip, .133, .118, dark, .106)
            oval(scarab, tibia, "Rounded scarab toe", tip, V(.142, .098, .133), dark)
            table.insert(scarab.legs, {upper = joint, lower = tibia, side = side, index = i, tip = tip,
                toeOffset = tibia.part.CFrame:PointToObjectSpace(tip)})
        end
    end
    satchel(scarab, V(0, 1.001, .219), V(.698, .305, .601), true)
end

local function solvePaw(rig, map, leg, target, pitch)
    local hip = rig.body.part.CFrame * map.Body * leg.upper.rest
    local v = hip:PointToObjectSpace(target)
    local a, b = leg.a, leg.b
    local d = math.clamp(math.sqrt(v.Y * v.Y + v.Z * v.Z), math.abs(a - b) + .0001, a + b - .0001)
    local shin = (if leg.front then -1 else 1) * math.acos(math.clamp((d * d - a * a - b * b) / (2 * a * b), -1, 1))
    local upper = math.atan2(-v.Z, -v.Y) - math.atan2(b * math.sin(shin), a + b * math.cos(shin))
    map[leg.upper.part.Name] = CFrame.Angles(upper, 0, 0)
    map[leg.lower.part.Name] = CFrame.Angles(shin, 0, 0)
    map[leg.foot.part.Name] = CFrame.Angles(-(pitch + upper + shin), 0, 0)
end

local function stroke(cycle, stride, lift, swing)
    if cycle < swing then
        local u = cycle / swing
        return stride * (.5 - u), lift * math.sin(pi * u)
    end
    return stride * ((cycle - swing) / (1 - swing) - .5), 0
end

local function scrape(u, second, reach, lift)
    local s = (u - (if second then .5 else 0)) * 2
    if s < 0 or s >= 1 then return 0, 0 end
    if s < .44 then return -reach * s / .44, lift * math.sin(pi * s / .44) end
    if s < .86 then return reach * (-1 + 1.32 * (s - .44) / .42), 0 end
    return reach * .32 * (1 - (s - .86) / .14), lift * .3 * math.sin(pi * (s - .86) / .14)
end

local function animate(rig, motion, u)
    local map = {}
    local phase, idle = tau * u, motion == "IdleLoop"
    local travel = motion == "TravelLoop"
    local beetle, small = rig == scarab, rig == mouse
    local wave = math.sin(phase)
    local pitch, drop
    if idle then
        drop, pitch = -.018 - .012 * (1 - math.cos(phase)), .017 * wave
    elseif travel then
        drop = (if beetle then -.020 elseif small then -.075 else -.124) - .027 * (1 - math.cos(phase * 2))
        pitch = (if small then .075 else .046) * math.sin(phase * 2)
    else
        drop = (if beetle then -.018 elseif small then -.057 else -.117) - .034 * (1 - math.cos(phase * 2))
        pitch = (if beetle then -.09 else -.13) * (.5 - .5 * math.cos(phase * 2))
    end
    map.Body = C(0, drop, 0) * CFrame.Angles(pitch, 0, 0)
    local sniff = if small then math.sin(phase * 3) * .054 else math.sin(phase * 2) * .024
    map.Head = if idle then CFrame.Angles(sniff, .068 * wave, .026 * math.sin(phase * 2))
        elseif travel then CFrame.Angles(-pitch * .52, .044 * wave, 0)
        else CFrame.Angles(-.14 * (.5 - .5 * math.cos(phase * 2)), .072 * wave, 0)

    for i, ear in rig.ears do
        local side = if i == 1 then -1 else 1
        local flick = (.5 + .5 * math.sin(phase + side * 1.22)) ^ 12
        map[ear.part.Name] = CFrame.Angles((if beetle then .13 else .068) * math.sin(phase * (if travel then 2 else 1) + i),
            side * (if beetle then .23 else .10) * wave, side * (.046 * wave + (if idle then .13 * flick else 0)))
    end
    if rig.tail then
        map.Tail = CFrame.Angles((if travel then .086 else .041) * math.sin(phase * 2),
            (if small then .22 else .30) * math.sin(phase), .042 * wave)
        map.TailTip = CFrame.Angles(.052 * math.sin(phase * 2 + .9), .22 * math.sin(phase - .89), 0)
    end

    for _, leg in rig.legs do
        local z, lift = 0, 0
        if travel then
            local offset = if beetle then (if (leg.index + (if leg.side == 1 then 1 else 0)) % 2 == 0 then 0 else .5)
                elseif small then (if leg.front then 0 else .48) + (if leg.side == 1 then .067 else 0)
                else (if leg.front == (leg.side == -1) then 0 else .5)
            z, lift = stroke((u + offset) % 1, if beetle then .30 elseif small then .40 else .68,
                if beetle then .115 elseif small then .118 else .178, .44)
        elseif not idle and (if beetle then leg.index == 1 else leg.front) then
            z, lift = scrape(u, leg.side == 1, if beetle then .17 elseif small then .184 else .248,
                if beetle then .094 elseif small then .116 else .154)
        end
        if beetle then
            local yaw = CFrame.Angles(0, -leg.side * z * 2, 0)
            local flex = CFrame.Angles(0, leg.side * z * .22, leg.side * lift * .83)
            local hip = rig.body.part.CFrame * map.Body * leg.upper.rest
            local swungToe = (yaw * leg.lower.rest * flex):PointToWorldSpace(leg.toeOffset)
            local target = hip:PointToObjectSpace(leg.tip + V(0, lift, z))
            map[leg.upper.part.Name] = C(target - swungToe) * yaw
            map[leg.lower.part.Name] = flex
        else
            solvePaw(rig, map, leg, leg.target + V(0, lift, z), pitch)
        end
    end
    return map
end

local function addClip(rig, name, duration, priority)
    local clip = create("KeyframeSequence", name, rig.clips)
    clip.Loop, clip.Priority = true, priority
    clip:SetAttribute("RigId", rig.model.Name)
    if name == "TravelLoop" then
        clip:SetAttribute("ReferenceSpeedStudsPerSecond", (if rig == scarab then .30 elseif rig == mouse then .40 else .68) / (.56 * duration))
    end
    local count = math.max(20, math.ceil(duration * 20))
    local function addPose(node, parent, map)
        local p = create("Pose", node.part.Name, parent)
        p.CFrame = map[node.part.Name] or C()
        p.Weight = if node == rig.root then 0 else 1
        p.EasingStyle = Enum.PoseEasingStyle.Linear
        for _,child in node.children do addPose(child, p, map) end
    end
    for i = 0, count do
        local k = create("Keyframe", "Keyframe", clip)
        k.Time = duration * i / count
        addPose(rig.root, k, animate(rig, name, if i == count then 0 else i / count))
        if name == "DigLoop" and (i == math.round(count * .22) or i == math.round(count * .72)) then
            local m = create("KeyframeMarker", "DigContact", k)
            m.Value = if i < count / 2 then "Left" else "Right"
        elseif name == "TravelLoop" and (i == math.round(count * .44) or i == math.round(count * .94)) then
            create("KeyframeMarker", "Step", k)
        end
    end
end

for _,item in {{fennec, 2.84, .72, 1.34}, {mouse, 2.18, .55, 1.12}, {scarab, 2.46, .62, 1.02}} do
    local rig = item[1]
    addClip(rig, "IdleLoop", item[2], Enum.AnimationPriority.Idle)
    addClip(rig, "TravelLoop", item[3], Enum.AnimationPriority.Movement)
    addClip(rig, "DigLoop", item[4], Enum.AnimationPriority.Action)
end

if offline then
    local destination = "assets/models/companions_v1/DuneBaron_Companions.rbxm"
    local bytes = roblox.serializeModel({pack})
    local imported = roblox.deserializeModel(bytes)[1]
    local count = 0
    for _,model in imported:GetChildren() do
        assert(model.PrimaryPart.Name == "Root" and #model.Animations:GetChildren() == 3)
        for _,clip in model.Animations:GetChildren() do
            local keys = clip:GetChildren()
            table.sort(keys, function(a, b) return a.Time < b.Time end)
            local start, finish = keys[1]:GetDescendants(), keys[#keys]:GetDescendants()
            assert(clip.Loop and #start == #finish and keys[1].Time == 0)
            for i,p in start do
                assert(p:IsA("Pose") and p.Name == finish[i].Name and p.CFrame == finish[i].CFrame)
            end
            count += 1
        end
    end
    assert(count == 9)
    fs.writeFile(destination, bytes)
    assert(fs.readFile(destination) == bytes, "Export did not round trip")
    print(destination, count, "verified loops")
else
    local run = game:GetService("RunService")
    assert(run:IsStudio() and not run:IsRunning(), "Use Studio Edit mode")
    assert(game.PlaceId == 135831532782380, "Unexpected place")
    local storage = game:GetService("ServerStorage")
    local previous = storage:FindFirstChild(ROOT_NAME)
    assert(not previous or previous:GetAttribute("Owner") == OWNER, "Existing folder belongs to another asset")
    if previous then previous:Destroy() end
    pack.Parent = storage
    return {path = pack:GetFullName(), models = #pack:GetChildren(), clips = 9}
end
