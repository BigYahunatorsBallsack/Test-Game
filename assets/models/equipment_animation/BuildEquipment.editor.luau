--!strict
-- Art authoring only. Run in Studio Edit or with Lune from the project root.
local offline = game == nil
local roblox = if offline then require("@lune/roblox") else nil
local fs = if offline then require("@lune/fs") else nil
local Instance = if roblox then roblox.Instance else Instance
local CFrame = if roblox then roblox.CFrame else CFrame
local Vector3 = if roblox then roblox.Vector3 else Vector3
local Enum = if roblox then roblox.Enum else Enum
local Color3 = if roblox then roblox.Color3 else Color3
local C, V = CFrame.new, Vector3.new
local rad = math.rad
local identity = CFrame.identity
local function degrees(x: number, y: number, z: number): CFrame
    return CFrame.Angles(rad(x), rad(y), rad(z))
end

local function create(class: string, name: string, parent: Instance?): any
    local item = Instance.new(class)
    item.Name = name
    item.Parent = parent
    return item
end

local function sortedKeys(sequence: KeyframeSequence): {Keyframe}
    local frames = sequence:GetChildren() :: {Keyframe}
    table.sort(frames, function(a, b) return a.Time < b.Time end)
    return frames
end

local function marker(key: Keyframe, name: string)
    create("KeyframeMarker", name, key)
end

local function sequence(parent: Instance, name: string, priority: Enum.AnimationPriority): KeyframeSequence
    local clip = create("KeyframeSequence", name, parent)
    clip.Loop = true
    clip.Priority = priority
    return clip
end

local function pose(parent: Instance, name: string, transform: CFrame?): Pose
    local p = create("Pose", name, parent)
    p.Weight = 1
    p.CFrame = transform or identity
    p.EasingStyle = Enum.PoseEasingStyle.Linear
    return p
end

local function key(clip: KeyframeSequence, t: number): Keyframe
    local k = create("Keyframe", "Keyframe", clip)
    k.Time = t
    return k
end

local function rootPose(clip: KeyframeSequence, t: number, cue: string?): (Pose, Keyframe)
    local k = key(clip, t)
    if cue then marker(k, cue) end
    local root = pose(k, "Root")
    root.Weight = 0 -- Work and travel animate disjoint branches of the machine.
    return root, k
end

local original: Folder
if offline then
    assert(roblox and fs)
    original = roblox.deserializeModel(fs.readFile("assets/models/machines_v2/DuneBaron_Machines_V2.rbxm"))[1]
else
    local run = game:GetService("RunService")
    assert(run:IsStudio() and not run:IsRunning(), "Use Studio Edit mode")
    original = game:GetService("ServerStorage").DuneBaronMachineScalePreview.DuneBaron_Machines_V2
end
local pack = original:Clone()
pack.Name = "DuneBaronEquipmentAnimations"
pack:SetAttribute("Owner", "DuneBaronEquipmentArt")
for _, model in pack:GetChildren() do
    if model:IsA("Model") then model:SetAttribute("AssetRevision",3) end
end

local function takeOldLoop(model: Model): (Folder, KeyframeSequence)
    local anim = model:FindFirstChild("Animations") :: Folder
    local old = anim:FindFirstChild("WorkLoop") :: KeyframeSequence
    old.Parent = nil
    return anim, old
end

local function modelParts(model: Model, name: string): {BasePart}
    local found = {}
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") and part.Name == name then table.insert(found, part) end
    end
    return found
end

local function replaceWelds(model: Model, parts: {[BasePart]: boolean})
    for _, joint in model:GetDescendants() do
        if joint:IsA("WeldConstraint") and parts[joint.Part1] then joint:Destroy() end
    end
end

local function motor(part: BasePart, root: BasePart, localPose: CFrame?)
    local joint = create("Motor6D", part.Name .. "Joint", root)
    joint.Part0, joint.Part1 = root, part
    joint.C0 = localPose or root.CFrame:ToObjectSpace(part.CFrame)
    joint.C1 = identity
    part.Anchored = false
    return joint
end

local function atScale(delta: CFrame, scale: number): CFrame
    return C(delta.Position / scale) * delta.Rotation
end

local function paintPart(model: Model, root: BasePart, class: string, name: string, size: Vector3, cf: CFrame, color: Color3): BasePart
    local part = create(class, name, model)
    part.Size,part.CFrame,part.Color = size,root.CFrame*cf,color
    part.Material = Enum.Material.SmoothPlastic
    part.CanCollide,part.CanTouch,part.CanQuery = false,false,false
    part.Massless = true
    local weld = create("WeldConstraint","DetailWeld",part)
    weld.Part0,weld.Part1 = root,part
    return part
end

local function widenConveyor(model: Model, root: BasePart, factor: number)
    local frame = root.CFrame
    local hierarchy = model:GetDescendants()
    local welds = {}
    for _, item in hierarchy do
        if item:IsA("WeldConstraint") then
            table.insert(welds,{item.Parent,item.Part0,item.Part1,item.Name,if offline then true else item.Enabled})
            item:Destroy()
        end
    end
    for _, item in hierarchy do
        if item:IsA("BasePart") then
            local relative = frame:ToObjectSpace(item.CFrame)
            item.Size *= factor
            item.CFrame = frame*atScale(relative,1/factor)
        elseif item:IsA("Attachment") or item:IsA("Pose") then
            item.CFrame = atScale(item.CFrame,1/factor)
        elseif item:IsA("Motor6D") then
            item.C0,item.C1 = atScale(item.C0,1/factor),atScale(item.C1,1/factor)
        end
    end
    for _, def in welds do
        local weld = create("WeldConstraint",def[4],def[1])
        weld.Part0,weld.Part1,weld.Enabled = def[2],def[3],def[5]
    end
end

-- Sample the authored beats while preserving direction and avoiding overshoot.
-- The matching end rows make the interpolation periodic.
local function interpolate(rows: {{any}}, fields: number): {{any}}
    local function tangent(a: number, b: number): number
        if a * b <= 0 then return 0 end
        return 2 * a * b / (a + b)
    end
    local sampled = {}
    local final = #rows
    for i = 1, final - 1 do
        local a, b = rows[i], rows[i+1]
        local before = if i > 1 then rows[i-1] else rows[final-1]
        local after = if i+1 < final then rows[i+2] else rows[2]
        local dt = b[1]-a[1]
        local past = if i > 1 then a[1]-before[1] else rows[final][1]-before[1]
        local future = if i+1 < final then after[1]-b[1] else after[1]-rows[1][1]
        local steps = math.max(1, math.round(dt * 26))
        table.insert(sampled, a)
        for f = 1, steps-1 do
            local t = f/steps
            local sample = {a[1] + dt*t}
            local function curve(p: number, x: number, y: number, q: number): number
                local middle = (y-x)/dt
                local m0 = tangent((x-p)/past,middle)*dt
                local m1 = tangent(middle,(q-y)/future)*dt
                return x + (y-x)*t*t*(3-2*t) + m0*t*(1-t)^2 - m1*t*t*(1-t)
            end
            for j=2,fields do
                local p, x, y, q = before[j], a[j], b[j], after[j]
                if typeof(x) == "Vector3" then
                    sample[j] = V(curve(p.X,x.X,y.X,q.X),curve(p.Y,x.Y,y.Y,q.Y),curve(p.Z,x.Z,y.Z,q.Z))
                else
                    sample[j] = curve(p,x,y,q)
                end
            end
            table.insert(sampled, sample)
        end
    end
    table.insert(sampled, rows[final])
    return sampled
end

-- Conveyor. Keep the calibrated bucket path and tie its drive wheels to it.
do
    local model = pack:FindFirstChild("bucket_chain") :: Model
    local body = assert(model.PrimaryPart)
    widenConveyor(model,body,6.35/4.75)
    model:SetAttribute("RestHeightStuds",6.35)
    local anim, old = takeOldLoop(model)
    local sprockets, caps = modelParts(model, "Sprocket"), modelParts(model, "Drive Cap")
    table.sort(sprockets, function(a,b) return a.CFrame.Position.Y < b.CFrame.Position.Y end)
    local retarget = {}
    for _, p in sprockets do retarget[p] = true end
    for _, p in caps do retarget[p] = true end
    replaceWelds(model, retarget)
    for idx, sprocket in sprockets do
        sprocket.Name = "Sprocket" .. idx
        motor(sprocket, body)
        for _, cap in caps do
            if (cap.CFrame.Position - sprocket.CFrame.Position).Magnitude < sprocket.Size.X * 0.85 then
                local coupling = create("WeldConstraint", "DriveCapWeld", cap)
                coupling.Part0, coupling.Part1 = sprocket, cap
            end
        end
        for _, side in {-1, 1} do
            for n = 0, 2 do
                local bolt = create("Part", "Drive Face Bolt", model)
                local r = sprocket.Size.Y * 0.23
                local a = n * 2 * math.pi / 3
                bolt.Size = V(0.062, r * 0.6, r * 0.6)
                bolt.CFrame = sprocket.CFrame * C(side * (sprocket.Size.X * 0.64 + 0.03), r * math.cos(a), r * math.sin(a))
                bolt.Color = body.Color:Lerp(sprocket.Color, 0.35)
                bolt.Material = Enum.Material.Metal
                bolt.CanCollide, bolt.CanTouch, bolt.CanQuery = false, false, false
                bolt.Massless = true
                local weld = create("WeldConstraint", "DriveBoltWeld", bolt)
                weld.Part0, weld.Part1 = sprocket, bolt
            end
        end
    end

    local work = old
    work.Name = "WorkLoop"
    work.Parent = anim
    local frames = sortedKeys(work)
    local duration = 2.96
    for idx, frame in frames do
        local phase = (idx - 1) / (#frames - 1)
        frame.Time = phase * duration
        local root = frame:FindFirstChild("Root") :: Pose
        for n = 1, #sprockets do
            pose(root, "Sprocket" .. n, CFrame.Angles(phase * math.pi * 12, 0, 0))
        end
        -- All buckets visit the same upper sprocket, 1/9 of a loop apart.
        local countBefore = math.floor((idx - 2) * 9 / (#frames - 1) + 0.43)
        local countNow = math.floor((idx - 1) * 9 / (#frames - 1) + 0.43)
        if idx > 1 and countNow ~= countBefore then marker(frame, "Discharge") end
    end
end

local function carveExcavatorBucket(model: Model, bucket: BasePart)
    local oldParts = {}
    for _, name in {"Bucket Floor","Bucket Cheek","Bucket Back","Cutting Tooth"} do
        for _, p in modelParts(model,name) do oldParts[p] = true end
    end
    replaceWelds(model,oldParts)
    for p in oldParts do p:Destroy() end
    local steel = Color3.fromRGB(65,79,85)
    local plates = Color3.fromRGB(54,66,72)
    local edge = Color3.fromRGB(138,151,150)
    -- X is the bucket width. Its opening faces +Z, toward the machine.
    local profile = {V(0,-.30,-.05),V(0,-.45,-.78),V(0,-.84,-1.03),
        V(0,-1.27,-.89),V(0,-1.51,-.55),V(0,-1.59,-.07),V(0,-1.50,.80)}
    for i=1,#profile-1 do
        local a,b = profile[i],profile[i+1]
        local axis = (b-a).Unit
        local cf = CFrame.fromMatrix((a+b)/2,Vector3.xAxis,axis:Cross(Vector3.xAxis),axis)
        paintPart(model,bucket,"Part","Bucket Shell",V(2.04,.145,(b-a).Magnitude+.092),cf,steel)
    end
    local function triangle(a: Vector3,b: Vector3,c: Vector3)
        local ab,ac,bc = b-a,c-a,c-b
        if ab.Magnitude>ac.Magnitude and ab.Magnitude>bc.Magnitude then
            c,a = a,c
        elseif ac.Magnitude>bc.Magnitude then
            a,b = b,a
        end
        ab,ac,bc = b-a,c-a,c-b
        local x,z = ac:Cross(ab).Unit,bc.Unit
        local y = z:Cross(x)
        local height = math.abs(ab:Dot(y))
        for _, half in {{b,z,x,math.abs(ab:Dot(z))},{c,-z,-x,math.abs(ac:Dot(z))}} do
            if half[4]>.002 and height>.002 then
                paintPart(model,bucket,"WedgePart","Bucket Side Plate",V(.16,height,half[4]),
                    CFrame.fromMatrix((a+half[1])/2,half[3],y,half[2]),plates)
            end
        end
    end
    for _, side in {-1,1} do
        local x = V(side*1.0,0,0)
        local middle = x+V(0,-1.04,-.24)
        for i=1,#profile do
            triangle(middle,profile[i]+x,profile[i%#profile+1]+x)
        end
    end
    paintPart(model,bucket,"Part","Hitch Saddle",V(1.08,.46,.45),C(0,-.16,-.19)*degrees(-16,0,0),steel)
    paintPart(model,bucket,"Part","Replaceable Cutting Edge",V(2.13,.17,.32),C(0,-1.51,.79),edge)
    for j=-2,2 do
        paintPart(model,bucket,"WedgePart","Bucket Tooth",V(.24,.22,.55),
            C(j*.43,-1.46,.98)*degrees(0,180,0),edge)
    end
    local work = bucket:FindFirstChild("WorkOrigin") :: Attachment
    work.CFrame = C(0,-1.57,1.24)
end

local function clearHarvesterWheels(model: Model, root: BasePart)
    local wheels, hubs, steps = modelParts(model,"Bogie Wheel"),modelParts(model,"Hub"),modelParts(model,"Access Step")
    local detach = {}
    for _, group in {wheels,hubs,steps} do for _, part in group do detach[part] = true end end
    replaceWelds(model,detach)
    local function place(part: BasePart, position: Vector3)
        local rotation = root.CFrame:ToObjectSpace(part.CFrame).Rotation
        part.CFrame = root.CFrame*C(position)*rotation
        local weld = create("WeldConstraint","ChassisWeld",part)
        weld.Part0,weld.Part1 = root,part
    end
    for _, group in {wheels,hubs} do
        local isWheel = group==wheels
        for _, part in group do
            local rest = root.CFrame:PointToObjectSpace(part.CFrame.Position)
            local endWheel = rest.Z < -2 or rest.Z > 5
            local diameter = if isWheel then (if endWheel then 2.19 else 2.02) else (if endWheel then 1.19 else 1.03)
            local x = if isWheel then 7.893 else 8.037
            part.Size = V(if isWheel then .19 else .16,diameter,diameter)
            place(part,V(math.sign(rest.X)*x,rest.Y,rest.Z))
        end
    end
    for _, step in steps do
        local rest = root.CFrame:PointToObjectSpace(step.CFrame.Position)
        step.Size = V(.69,step.Size.Y,1.34)
        place(step,V(-8.59,rest.Y,rest.Z))
    end
    local support = Color3.fromRGB(67,86,91)
    for _,z in {1.95,3.18} do
        paintPart(model,root,"Part","Ladder Upright",V(.14,3.47,.12),C(-8.60,2.61,z),support)
        paintPart(model,root,"Part","Ladder Mount",V(1.15,.16,.15),C(-8.11,4.31,z),support)
    end
end

-- The crawler loop advances three identical pads per loop. The pad lattice is
-- identical across the boundary, and the hull remains a fixed reference.
local function makeTracks(model: Model, anim: Folder, scale: number, duration: number)
    local root = assert(model.PrimaryPart)
    local cleats, belts = modelParts(model, "Tread Cleat"), modelParts(model, "Track Belt")
    local detach = {}
    for _, cleat in cleats do detach[cleat] = true end
    replaceWelds(model, detach)
    table.sort(belts, function(a,b)
        return root.CFrame:PointToObjectSpace(a.CFrame.Position).X < root.CFrame:PointToObjectSpace(b.CFrame.Position).X
    end)
    local clip = sequence(anim, "TravelLoop", Enum.AnimationPriority.Movement)
    local samples = {}
    for f = 0, 12 do
        samples[f + 1] = rootPose(clip, duration * f / 12)
    end
    for side, belt in belts do
        local center = root.CFrame:PointToObjectSpace(belt.CFrame.Position)
        local row = {}
        local radius = 0
        for _, p in cleats do
            local offset = root.CFrame:PointToObjectSpace(p.CFrame.Position)
            if offset.X * center.X > 0 then
                table.insert(row, p)
                radius = math.max(radius, math.abs(offset.Y - center.Y))
            end
        end
        local count = #row
        assert(count == 30 and radius > 0, "Expected 30 crawler pads on each side")
        local straight = belt.Size.Z
        local endTurn = math.pi * radius
        local perimeter = 2 * (straight + endTurn)
        local stride = perimeter / count
        if side == 1 then clip:SetAttribute("BeltSpeedStudsPerSecond", 3 * stride / duration) end
        local function treadAt(d: number): CFrame
            d %= perimeter
            local angle, y, z
            if d < straight then
                angle, y, z = 0, -radius, -straight / 2 + d
            elseif d < straight + endTurn then
                angle = (d - straight) / radius
                y, z = -radius * math.cos(angle), straight / 2 + radius * math.sin(angle)
            elseif d < 2 * straight + endTurn then
                angle, y, z = math.pi, radius, straight / 2 - (d - straight - endTurn)
            else
                angle = math.pi + (d - 2 * straight - endTurn) / radius
                y, z = -radius * math.cos(angle), -straight / 2 + radius * math.sin(angle)
            end
            return C(center + V(0, y, z)) * CFrame.Angles(-angle, 0, 0)
        end
        for i, pad in row do
            local distance = (i - 1) * stride
            local rest = treadAt(distance)
            pad.Name = string.format("Tread%d_%02d", side, i)
            pad.CFrame = root.CFrame * rest
            motor(pad, root, rest)
            for frame, p in samples do
                local moving = treadAt(distance + 3 * stride * (frame - 1) / 12)
                pose(p, pad.Name, atScale(rest:ToObjectSpace(moving), scale))
            end
        end
    end
end

-- Excavator. An explicit cutting, curling, slewing and tipping cycle.
do
    local m = pack:FindFirstChild("mini_digger") :: Model
    local anim, old = takeOldLoop(m)
    old:Destroy()
    local scale = 1.4698492288589478
    local work = sequence(anim, "WorkLoop", Enum.AnimationPriority.Action)
    local root = assert(m.PrimaryPart)
    carveExcavatorBucket(m,m:FindFirstChild("Scoop",true) :: BasePart)
    local joints = {}
    for _, j in m:GetDescendants() do
        if j:IsA("Motor6D") and j.Part1 then joints[j.Part1.Name] = j end
    end
    local rams = {}
    local detach = {}
    for index, spec in {
        {"Boom Cylinder","Boom Ram","Turret","Boom"},
        {"Stick Piston","Stick Ram","Boom","Stick"},
    } do
        local barrel, rod = modelParts(m,spec[1])[1], modelParts(m,spec[2])[1]
        local a, b = assert(joints[spec[3]].Part1), assert(joints[spec[4]].Part1)
        local firstPin = barrel.CFrame.Position-barrel.CFrame.RightVector*barrel.Size.X/2
        local lastPin = rod.CFrame.Position+rod.CFrame.RightVector*rod.Size.X/2
        rams[index] = {
            barrel = barrel, rod = rod, a = spec[3], b = spec[4],
            aPin = a.CFrame:PointToObjectSpace(firstPin),
            bPin = b.CFrame:PointToObjectSpace(lastPin),
        }
        detach[barrel],detach[rod] = true,true
    end
    replaceWelds(m,detach)
    local ramMid = {}
    for _, parts in rams do
        for _, part in {parts.barrel,parts.rod} do
            motor(part,root)
            ramMid[part] = root.CFrame:ToObjectSpace(part.CFrame)
        end
    end
    local cutTable = {
        {0.00,  0, 12.5,-7.5, -1.0},
        {0.28,  0,  4.5, 7.0, 25.5},
        {0.55,  0, -4.0, 9.5, 22.5, "BucketCut"},
        {0.76,  0, -1.5, 0.0, 19.5},
        {1.08,  0, -4.0,10.5,-27.5, "BucketLoaded"},
        {1.34,  8, 13.0, 5.5,-53.5},
        {1.71, 29, 29.0,15.0,-62.0},
        {1.93, 41, 32.0,12.0,-56.0},
        {2.16, 43, 29.0, 9.0,  8.0, "BucketDump"},
        {2.36, 43, 28.0, 8.0, 22.0},
        {2.53, 37, 28.0,10.0,-43.0},
        {2.76, 18, 21.0, 4.0,-27.0},
        {2.99,  4, 15.0,-4.0, -7.0},
        {3.24,  0, 12.5,-7.5, -1.0},
    }
    for _, f in interpolate(cutTable,5) do
        local origin = rootPose(work, f[1], f[6])
        local frames = {}
        local p, reference = origin, identity
        for _, spec in {
            {"Turret",degrees(0,f[2],0)},
            {"Boom",degrees(f[3],0,0)},
            {"Stick",degrees(f[4],0,0)},
            {"Scoop",degrees(f[5],0,0)},
        } do
            local j = joints[spec[1]]
            p = pose(p,spec[1],spec[2])
            reference = reference*j.C0*spec[2]*j.C1:Inverse()
            frames[spec[1]] = reference
        end
        for _, parts in rams do
            local a = frames[parts.a]:PointToWorldSpace(parts.aPin)
            local b = frames[parts.b]:PointToWorldSpace(parts.bPin)
            local axis = (b-a).Unit
            local z = frames.Turret.RightVector
            z = (z-axis*axis:Dot(z)).Unit
            local y = z:Cross(axis)
            local barrel,rod = parts.barrel,parts.rod
            local pump = CFrame.fromMatrix(a+axis*barrel.Size.X/2,axis,y,z)
            local piston = CFrame.fromMatrix(b-axis*rod.Size.X/2,axis,y,z)
            pose(origin,barrel.Name,atScale(ramMid[barrel]:ToObjectSpace(pump),scale))
            pose(origin,rod.Name,atScale(ramMid[rod]:ToObjectSpace(piston),scale))
        end
    end
    makeTracks(m, anim, scale, 0.24)
end

-- The scanner sees the target before the suction shoe lowers onto it.
do
    local model = pack:FindFirstChild("vacuum_robot") :: Model
    local anim, old = takeOldLoop(model)
    old:Destroy()
    local work = sequence(anim, "WorkLoop", Enum.AnimationPriority.Action)
    for _, f in interpolate({
        {0.00, 0,    0,   0},
        {0.20, 26,   1,   2},
        {0.42, 22,  -2,   8, "IntakeEngage"},
        {0.73, 3, -3.4,   5},
        {1.05, -17, -3.5, 0, "IntakeSweep"},
        {1.38, -24, -2,  -8},
        {1.59, -9,   1,  -5, "IntakeRelease"},
        {1.86, 0,    0,   0},
    },4) do
        local p = rootPose(work, f[1], f[5])
        pose(p, "Scanner", degrees(0, f[2], 0))
        pose(p, "Intake", degrees(f[3], f[4], 0))
    end
end

-- Drums keep turning under load. Their speed dips occur at staggered phases.
do
    local model = pack:FindFirstChild("mega_machine") :: Model
    clearHarvesterWheels(model,assert(model.PrimaryPart))
    local anim, old = takeOldLoop(model)
    old:Destroy()
    local work = sequence(anim, "WorkLoop", Enum.AnimationPriority.Action)
    for index = 0, 30 do
        local phase = index / 30
        local cue = if index == 5 or index == 20 then "CutterLoad" else nil
        local p = rootPose(work, phase * 1.58, cue)
        local a = -720 * phase
        pose(p, "Drum_L", degrees(a + 8 * math.sin(phase * 4 * math.pi), 0, 0))
        pose(p, "Drum_R", degrees(a + 22 + 8 * (math.sin(phase * 4 * math.pi + 1.2) - math.sin(1.2)), 0, 0))
    end
    makeTracks(model, anim, 1.9134396314620972, 0.33)
end

-- R15 shovel. The two grips are solved against a single tool transform.
local shovel = create("Folder", "shovel", pack)
local toolGrip = C(0, 1.28, 0)
local handRotation = degrees(0, 0, -90)
local grip = toolGrip * handRotation
local storedGrip = create("CFrameValue", "RightHandToShovelPivot", shovel)
storedGrip.Value = grip:Inverse()
local toolScale = create("NumberValue", "ShovelScale", shovel)
toolScale.Value = 0.8
local offGrip = C(-0.025, 0.43, 0) * degrees(0, 0, 90)

type Joint = {base: CFrame, tip: CFrame}
local function joint(x0: number, y0: number, x1: number, y1: number): Joint
    return {base = C(x0,y0,0), tip = C(x1,y1,0)}
end
local pelvis = joint(0,-1,0,-0.20025)
local waist = joint(0,0.20030,0,-0.84900)

local function solveLimb(base: CFrame, upper: Joint, lower: Joint, endJoint: Joint, target: CFrame, hint: Vector3): (CFrame,CFrame,CFrame,number)
    local start = (base * upper.base).Position
    local desired = (target * endJoint.tip).Position
    local reach = desired - start
    local axis = reach.Unit
    local a0 = lower.base.Position - upper.tip.Position
    local b0 = endJoint.base.Position - lower.tip.Position
    local lengthA, lengthB = a0.Magnitude, b0.Magnitude
    local d = math.clamp(reach.Magnitude, math.abs(lengthA - lengthB) + .001, lengthA + lengthB - .001)
    local forward = (lengthA^2 - lengthB^2 + d^2) / (2*d)
    local bend = math.sqrt(math.max(lengthA^2 - forward^2, 0))
    local pole = (hint - axis * hint:Dot(axis)).Unit
    local mid, stop = start + axis * forward + pole * bend, start + axis * d
    local function orient(from: Vector3, to: Vector3, xHint: Vector3): CFrame
        local srcY, dstY = -from.Unit,-to.Unit
        local srcX = (Vector3.xAxis - srcY * srcY.X).Unit
        local dstX = (xHint - dstY * xHint:Dot(dstY)).Unit
        return CFrame.fromMatrix(Vector3.zero,dstX,dstY) * CFrame.fromMatrix(Vector3.zero,srcX,srcY):Inverse()
    end
    local rA = orient(a0, mid-start, base.RightVector)
    local rB = orient(b0, stop-mid, rA.RightVector)
    local a = C(start) * rA * C(-upper.tip.Position)
    local b = C(mid) * rB * C(-lower.tip.Position)
    local c = C(stop) * target.Rotation * C(-endJoint.tip.Position)
    local e = (stop - desired).Magnitude
    return (base*upper.base):ToObjectSpace(a*upper.tip),
        (a*lower.base):ToObjectSpace(b*lower.tip),
        (b*endJoint.base):ToObjectSpace(c*endJoint.tip), e
end

if offline and require("@lune/process").args[1] == "driver-cabs" then
    require("../driver_cabs/BuildDriverCabs")(joint, solveLimb)
    return
end

local function shovelAt(low: Vector3, shaft: Vector3, roll: number): CFrame
    local up = shaft.Unit
    local right = (Vector3.xAxis - up * up.X).Unit
    return CFrame.fromMatrix(low, right, up) * degrees(0,roll,0) * C(0,1.60,0)
end

local scoop = sequence(shovel, "ShovelWorkLoop", Enum.AnimationPriority.Action)
local maxGripError = 0
for _, f in interpolate({
    -- t, stance height and lean, blade tip, handle direction, shaft roll, cue
    {0.00, -.18, 9,  V(.20, 1.18,-2.10), V(.24,.76,.60), 8},
    {0.22, -.26, 13, V(.26, 1.05,-2.24), V(.26,.77,.58), 7},
    {0.48, -.74, 22, V(-.08,0.17,-2.57), V(.27,.80,.56), 5, "SpadeCut"},
    {0.66, -.64, 24, V(.10, 0.11,-2.22), V(.29,.78,.61), 12},
    {0.89, -.55, 18, V(.16, 0.52,-2.04), V(.27,.72,.65), 24, "SpadeLoaded"},
    {1.11, -.30,  9, V(.08, 1.46,-2.18), V(.26,.61,.75), 28},
    {1.31, -.23,  6, V(-.05,1.66,-2.20), V(.37,.46,.80), 57, "SpadeDump"},
    {1.53, -.15,  6, V(-.01,1.40,-2.18), V(.34,.58,.74), 25},
    {1.82, -.18,  9, V(.20, 1.18,-2.10), V(.24,.76,.60), 8},
},6) do
    local k = key(scoop, f[1])
    if f[7] then marker(k, f[7]) end
    local root = pose(k, "HumanoidRootPart")
    root.Weight = 0
    local rootFrame = C(0,3.006,0)
    local hipPose = C(0,f[2],0.08) * degrees(5,0,0)
    local torsoPose = degrees(-f[3],-6,0)
    local hipFrame = rootFrame * pelvis.base * hipPose * pelvis.tip:Inverse()
    local torsoFrame = hipFrame * waist.base * torsoPose * waist.tip:Inverse()
    local lower = pose(root, "LowerTorso", hipPose)
    local chest = pose(lower, "UpperTorso", torsoPose)
    pose(chest, "Head", degrees(f[3] * .65, 4, 0))
    local tool = shovelAt(f[4]-V(.70,0,0), f[5], f[6])
    for _, side in {"Right","Left"} do
        local s = if side == "Right" then 1 else -1
        local hand = tool * (if s == 1 then grip else offGrip)
        local a,b,c,errorDistance = solveLimb(torsoFrame,
            joint(.97160*s,.59751,-.50053*s,.41892), joint(0,-.35501,0,.27471),
            joint(0,-.53217,0,.13157), hand, V(s*.85,-.8,.25))
        maxGripError = math.max(maxGripError,errorDistance)
        pose(pose(pose(chest,side.."UpperArm",a),side.."LowerArm",b),side.."Hand",c)
        local hip, knee, ankle = solveLimb(hipFrame,
            joint(.49785*s,-.20025,0,.47139), joint(0,-.44926,0,.41327),
            joint(0,-.59649,0,.10602), C(.52*s,.156,if s == 1 then .20 else -.28), V(0,0,-1))
        pose(pose(pose(lower,side.."UpperLeg",hip),side.."LowerLeg",knee),side.."Foot",ankle)
    end
end
shovel:SetAttribute("MaxGripErrorStuds", maxGripError)

-- Export carry and transition clips with a matching copy of the R15 WorkLoop.
if offline and require("@lune/process").args[1] == "shovel-carry" then
    assert(roblox and fs)
    local originalPackage = roblox.deserializeModel(
        fs.readFile("assets/models/equipment_animation/DuneBaron_Equipment_Animations.rbxm")
    )[1]
    local originalShovel = originalPackage.shovel
    local work = originalShovel.ShovelWorkLoop:Clone() :: KeyframeSequence
    local savedGrip = originalShovel.RightHandToShovelPivot :: CFrameValue
    local rootFrame = C(0, 3.006, 0)
    local wristTip = joint(0, -0.53217, 0, 0.13157)
    local elbow = joint(0, -0.35501, 0, 0.27471)
    local knee = joint(0, -0.44926, 0, 0.41327)
    local ankle = joint(0, -0.59649, 0, 0.10602)

    local function shoulder(sign: number): Joint
        return joint(0.97160 * sign, 0.59751, -0.50053 * sign, 0.41892)
    end
    local function chestFrame(hipPose: CFrame, torsoPose: CFrame): (CFrame, CFrame)
        local hipFrame = rootFrame * pelvis.base * hipPose * pelvis.tip:Inverse()
        return hipFrame, hipFrame * waist.base * torsoPose * waist.tip:Inverse()
    end
    local function palmFrame(
        upperBody: CFrame,
        sign: number,
        a: CFrame,
        b: CFrame,
        c: CFrame
    ): CFrame
        local first = shoulder(sign)
        local upper = upperBody * first.base * a * first.tip:Inverse()
        local forearm = upper * elbow.base * b * elbow.tip:Inverse()
        return forearm * wristTip.base * c * wristTip.tip:Inverse()
    end
    local function armPoses(torso: Pose, side: string): (Pose, Pose, Pose)
        local upper = torso:FindFirstChild(side .. "UpperArm") :: Pose
        local forearm = upper:FindFirstChild(side .. "LowerArm") :: Pose
        local hand = forearm:FindFirstChild(side .. "Hand") :: Pose
        return upper, forearm, hand
    end
    local function workingHand(torso: Pose, body: CFrame, side: string, sign: number): CFrame
        local upper, forearm, hand = armPoses(torso, side)
        return palmFrame(body, sign, upper.CFrame, forearm.CFrame, hand.CFrame)
    end

    -- Give the start and return poses room for the hilt while retaining the timed digging beats.
    local maxWorkShift, maxWorkReach = 0, 0
    for _, frame in sortedKeys(work) do
        local hips = frame.HumanoidRootPart.LowerTorso :: Pose
        local torso = hips.UpperTorso :: Pose
        local _, body = chestFrame(hips.CFrame, torso.CFrame)
        local tool = workingHand(torso, body, "Right", 1) * savedGrip.Value
        local shift = 0
        for i = 0, 32 do
            local p =
                body:PointToObjectSpace(tool:PointToWorldSpace(V(0, -1.60 + i * (3.22 / 32), 0)))
            if math.abs(p.X) < 0.91 and math.abs(p.Y) < 0.71 and p.Z > -0.49 and p.Z < 0.24 then
                shift = math.max(shift, p.Z + 0.492)
            end
        end
        if frame.Time > 0.40 then
            local amount = math.clamp((frame.Time - 1.55) / 0.19, 0, 1)
            shift *= amount * amount * (3 - 2 * amount)
        end
        if shift > 0 then
            maxWorkShift = math.max(maxWorkShift, shift)
            for _, side in { "Right", "Left" } do
                local sign = if side == "Right" then 1 else -1
                local desired = workingHand(torso, body, side, sign) + body.LookVector * shift
                local a, b, d, handError = solveLimb(
                    body,
                    shoulder(sign),
                    elbow,
                    wristTip,
                    desired,
                    V(sign * 0.85, -0.8, 0.25)
                )
                local upper, forearm, hand = armPoses(torso, side)
                upper.CFrame, forearm.CFrame, hand.CFrame = a, b, d
                maxWorkReach = math.max(maxWorkReach, handError)
            end
        end
    end
    print("Work hilt clearance shift and hand error", maxWorkShift, maxWorkReach)
    assert(maxWorkReach < 0.075, "Adjusted work grips exceed rig reach")
    local workStart = sortedKeys(work)[1]
    local workHip = workStart.HumanoidRootPart.LowerTorso :: Pose
    local workTorso = workHip.UpperTorso :: Pose
    local workHead = workTorso.Head :: Pose
    local _, workingBody = chestFrame(workHip.CFrame, workTorso.CFrame)
    local workRight = workingHand(workTorso, workingBody, "Right", 1)
    local workLeft = workingHand(workTorso, workingBody, "Left", -1)

    local function carryGrip(center: Vector3, shaft: Vector3, roll: number): CFrame
        local axis = shaft.Unit
        local across = (Vector3.xAxis - axis * axis.X).Unit
        local aligned = CFrame.fromMatrix(center, across, axis)
        return aligned * degrees(0, roll, 0) * handRotation
    end
    local restingChest, restingHead = degrees(-3.2, 2.8, -1.65), degrees(2.4, -2.2, 1)
    local restingRight = carryGrip(V(1.29, 2.36, -0.22), V(-0.17, 0.56, -0.81), 13)
    local restingLeft = C(-1.06, 2.09, -0.12) * degrees(9, -7, -9)

    local bundle = create("Folder", "DuneBaronShovelCarry", nil)
    originalShovel.RightHandToShovelPivot:Clone().Parent = bundle
    originalShovel.ShovelScale:Clone().Parent = bundle
    work.Parent = bundle
    local idle = sequence(bundle, "ShovelCarryIdle", Enum.AnimationPriority.Movement)
    local walk = sequence(bundle, "ShovelCarryWalk", Enum.AnimationPriority.Movement)
    idle:SetAttribute("UpperBodyOnly", true)
    walk:SetAttribute("UpperBodyOnly", true)
    walk:SetAttribute("ReferenceSpeedStudsPerSecond", 12)
    local ready = sequence(bundle, "ShovelCarryToWork", Enum.AnimationPriority.Action)
    local lowerTool = sequence(bundle, "ShovelWorkToCarry", Enum.AnimationPriority.Action)
    ready.Loop, lowerTool.Loop = false, false

    local smallestBladeY, maxHandError = math.huge, 0
    local function stance(
        clip: KeyframeSequence,
        t: number,
        hips: CFrame,
        torso: CFrame,
        head: CFrame,
        rightHand: CFrame,
        leftHand: CFrame,
        armsOnly: boolean
    )
        local k = key(clip, t)
        local root = pose(k, "HumanoidRootPart")
        root.Weight = 0
        local pa = pose(root, "LowerTorso", hips)
        pa.Weight = if armsOnly then 0 else 1
        local upper = pose(pa, "UpperTorso", torso)
        pose(upper, "Head", head)
        local hipFrame, upperBody = chestFrame(hips, torso)
        for _, name in { "Right", "Left" } do
            local sign = if name == "Right" then 1 else -1
            local goal = if sign == 1 then rightHand else leftHand
            local a, b, d, error = solveLimb(
                upperBody,
                shoulder(sign),
                elbow,
                wristTip,
                goal,
                V(sign * 0.9, -0.68, 0.21)
            )
            maxHandError = math.max(maxHandError, error)
            pose(pose(pose(upper, name .. "UpperArm", a), name .. "LowerArm", b), name .. "Hand", d)
            if sign == 1 then
                local tool = palmFrame(upperBody, sign, a, b, d) * savedGrip.Value
                for _, x in { -0.38, 0.38 } do
                    for _, z in { -0.12, 0.12 } do
                        smallestBladeY =
                            math.min(smallestBladeY, tool:PointToWorldSpace(V(x, -1.66, z)).Y)
                    end
                end
            end
            if not armsOnly then
                local fixedFoot = C(0.52 * sign, 0.156, if sign == 1 then 0.20 else -0.28)
                local a1, b1, d1 = solveLimb(
                    hipFrame,
                    joint(0.49785 * sign, -0.20025, 0, 0.47139),
                    knee,
                    ankle,
                    fixedFoot,
                    V(0, 0, -1)
                )
                pose(
                    pose(pose(pa, name .. "UpperLeg", a1), name .. "LowerLeg", b1),
                    name .. "Foot",
                    d1
                )
            end
        end
    end

    local function restFrame(clip: KeyframeSequence, time: number, armsOnly: boolean)
        stance(clip, time, identity, restingChest, restingHead, restingRight, restingLeft, armsOnly)
    end

    for i = 0, 24 do
        if i % 24 == 0 then
            restFrame(idle, i / 24 * 2.56, true)
            continue
        end
        local angle = (i % 24) / 24 * math.pi * 2
        local wave, lift = math.sin(angle), 1 - math.cos(angle)
        stance(
            idle,
            i / 24 * 2.56,
            identity,
            restingChest * degrees(0.8 * lift, 0.65 * wave, 0),
            restingHead,
            restingRight + V(0.012 * wave, 0.020 * lift, 0.018 * wave),
            restingLeft + V(0, 0.018 * lift, 0.028 * wave),
            true
        )
    end

    for i = 0, 24 do
        if i % 24 == 0 then
            restFrame(walk, i / 24 * 0.88, true)
            continue
        end
        local angle = (i % 24) / 24 * math.pi * 2
        local wave, lift = math.sin(angle), math.sin(angle) ^ 2
        local walkingChest = restingChest * degrees(-3.25 * lift, -4.6 * wave, 2.8 * wave)
        local hand = carryGrip(
            V(1.29 + 0.052 * wave, 2.36 + 0.039 * lift, -0.22 - 0.16 * wave),
            V(-0.17 + 0.031 * wave, 0.56 + 0.022 * wave, -0.81),
            13 + 5.2 * wave
        )
        local opposite = C(-1.06, 2.09 + 0.078 * lift, -0.12 + 0.45 * wave)
            * degrees(9 - 18 * wave, -7, -9 + 3.25 * wave)
        stance(
            walk,
            i / 24 * 0.88,
            identity,
            walkingChest,
            restingHead * degrees(-2 * lift, 1.65 * wave, 0),
            hand,
            opposite,
            true
        )
    end

    local function smooth(t: number): number
        local x = math.clamp(t, 0, 1)
        return x * x * (3 - 2 * x)
    end
    local gripPath = {
        { 0, restingRight },
        { 0.26, carryGrip(V(1.38, 2.48, -0.35), V(-0.39, 0.51, -0.76), 17) },
        { 0.48, carryGrip(V(1.34, 2.56, -0.54), V(-0.82, 0.53, -0.13), 22) },
        { 0.66, carryGrip(V(1.05, 2.59, -0.80), V(-0.77, 0.54, 0.35), 24) },
        { 0.84, carryGrip(V(0.38, 2.66, -0.75), V(-0.36, 0.63, 0.68), 13) },
        { 1, workRight },
    }

    local function rightHandAt(t: number): CFrame
        for i = 2, #gripPath do
            local a, b = gripPath[i - 1], gripPath[i]
            if t <= b[1] then
                return a[2]:Lerp(b[2], smooth((t - a[1]) / (b[1] - a[1])))
            end
        end
        return workRight
    end

    local function transition(clip: KeyframeSequence, duration: number, back: boolean)
        for i = 0, 20 do
            local phase = if back then 1 - i / 20 else i / 20
            local time = i / 20 * duration
            if phase == 1 then
                local frame = workStart:Clone()
                frame.Time, frame.Parent = time, clip
            elseif phase == 0 then
                restFrame(clip, time, false)
            else
                local weight = smooth(phase)
                local hand = rightHandAt(phase)
                local left = restingLeft
                    :Lerp(C(-0.89, 2.41, -0.68) * degrees(2, 15, -12), smooth(phase / 0.64))
                    :Lerp(workLeft, smooth((phase - 0.62) / 0.38))
                stance(
                    clip,
                    time,
                    identity:Lerp(workHip.CFrame, weight),
                    restingChest:Lerp(workTorso.CFrame, weight),
                    restingHead:Lerp(workHead.CFrame, weight),
                    hand,
                    left,
                    false
                )
            end
        end
    end
    transition(ready, 0.52, false)
    transition(lowerTool, 0.46, true)
    print("Carry blade clearance and hand target error", smallestBladeY, maxHandError)
    assert(smallestBladeY > 0.30 and maxHandError < 0.075, "Carry stance exceeds pose tolerance")
    bundle:SetAttribute("RigType", "R15")
    bundle:SetAttribute("MinimumBladeHeightStuds", smallestBladeY)
    bundle:SetAttribute("MaxHandTargetErrorStuds", maxHandError)
    local destination = "assets/models/shovel_carry/DuneBaron_Shovel_Carry.rbxm"
    local bytes = roblox.serializeModel({ bundle })
    local reloaded = roblox.deserializeModel(bytes)[1]
    local function sameBody(a: Keyframe, b: Keyframe)
        for _, p in a:GetDescendants() do
            if p:IsA("Pose") then
                local twin = b:FindFirstChild(p.Name, true) :: Pose
                assert(twin.CFrame == p.CFrame, p.Name)
            end
        end
    end
    for _, name in { "ShovelCarryIdle", "ShovelCarryWalk" } do
        local clip = reloaded:FindFirstChild(name) :: KeyframeSequence
        local keys = sortedKeys(clip)
        assert(clip.Loop and #keys == 25 and clip:GetAttribute("UpperBodyOnly"))
        assert(not keys[1]:FindFirstChild("LeftUpperLeg", true))
        sameBody(keys[1], keys[#keys])
    end
    local toWork, toCarry =
        sortedKeys(reloaded.ShovelCarryToWork), sortedKeys(reloaded.ShovelWorkToCarry)
    sameBody(toWork[#toWork], workStart)
    sameBody(toCarry[1], workStart)
    sameBody(toWork[1], toCarry[#toCarry])
    fs.writeFile(destination, bytes)
    print(destination, "five clips verified")
    return
end

-- A separate export lets the starter animation ship without altering the equipment bundle.
if offline and require("@lune/process").args[1] == "hand-scoop" then
    assert(roblox and fs)
    local export = create("Folder","DuneBaronHandScoop",nil)
    local hand = sequence(export,"HandScoopLoop",Enum.AnimationPriority.Action)
    hand:SetAttribute("RigType","R15")
    local wristTip = joint(0,-.53217,0,.13157)
    local restRight,restLeft = V(.81,2.19,-.60),V(-.88,2.04,-.23)
    local beats = {
        -- Seconds, crouch, hips back, lean, turn, right palm, wrist pitch, left palm, wrist pitch, cue.
        {0.00,-.12,.05,12, -6,restRight,26,restLeft,9},
        {0.17,-.59,.14,30, -8,V(.77,1.56,-1.03),40,V(-.87,1.48,-.42),19},
        {0.34,-1.24,.22,61, -8,V(.69,.50,-1.63),63,V(-.91,.99,-.75),17},
        {0.45,-1.49,.26,73,-10,V(.61,.15,-1.88),75,V(-.90,.85,-.83),24,"HandSandTouch"},
        {0.61,-1.47,.24,61, -8,V(.65,.16,-1.41),21,V(-.92,.86,-.77),21},
        {0.80,-1.16,.22,39, -5,V(.68,.95,-1.31),-14,V(-.92,1.13,-.62),17,"HandLoaded"},
        {1.01,-.53,.13,22, -9,V(.69,1.80,-1.07),-32,V(-.79,1.54,-.58),23},
        {1.16,-.37,.08,17,-15,V(.37,2.05,-.86),46,V(-.57,1.68,-.70),23,"HandDeposit"},
        {1.34,-.25,.04,13, -8,V(.78,2.15,-.58),38,V(-.83,1.85,-.46),18},
        {1.54,-.12,.05,12, -6,restRight,26,restLeft,9},
    }
    local render = {}
    local maxReachError = 0
    local footError = 0
    local lowestPalm = math.huge
    local contactTravel = 0
    local contactStart: Vector3? = nil
    local frames = interpolate(beats,9)
    local function partsForPreview(row: {[string]: {number}}, name: string, cf: CFrame)
        row[name] = {cf:GetComponents()}
    end
    for _, f in frames do
        local k = key(hand,f[1])
        if f[10] then marker(k,f[10]) end
        local rootPoseFrame = pose(k,"HumanoidRootPart")
        rootPoseFrame.Weight = 0
        local hipPose = C(0,f[2],f[3])*degrees(4,0,0)
        local torsoPose = degrees(-f[4],f[5],-4)
        local hipFrame = C(0,3.006,0)*pelvis.base*hipPose*pelvis.tip:Inverse()
        local torsoFrame = hipFrame*waist.base*torsoPose*waist.tip:Inverse()
        local lower = pose(rootPoseFrame,"LowerTorso",hipPose)
        local chest = pose(lower,"UpperTorso",torsoPose)
        local headPose = degrees(f[4]*.48,4,0)
        pose(chest,"Head",headPose)
        local world: {[string]: {number}} = {}
        partsForPreview(world,"LowerTorso",hipFrame)
        partsForPreview(world,"UpperTorso",torsoFrame)
        partsForPreview(world,"Head",torsoFrame*C(0,.63,0)*headPose*C(0,.52,0))
        for _, name in {"Right","Left"} do
            local sign = if name=="Right" then 1 else -1
            local target = if sign==1 then C(f[6])*degrees(f[7],-17,12) else C(f[8])*degrees(f[9],10,-16)
            local shoulder = joint(.97160*sign,.59751,-.50053*sign,.41892)
            local elbow = joint(0,-.35501,0,.27471)
            local a,b,c,errorDistance = solveLimb(torsoFrame,shoulder,elbow,wristTip,target,V(sign*.88,-.75,.26))
            maxReachError = math.max(maxReachError,errorDistance)
            pose(pose(pose(chest,name.."UpperArm",a),name.."LowerArm",b),name.."Hand",c)
            local upper = torsoFrame*shoulder.base*a*shoulder.tip:Inverse()
            local arm = upper*elbow.base*b*elbow.tip:Inverse()
            local palm = arm*wristTip.base*c*wristTip.tip:Inverse()
            partsForPreview(world,name.."UpperArm",upper)
            partsForPreview(world,name.."LowerArm",arm)
            partsForPreview(world,name.."Hand",palm)
            if sign==1 then
                lowestPalm = math.min(lowestPalm,palm.Position.Y)
                if f[10]=="HandSandTouch" then contactStart=palm.Position end
                if f[1]>=.6099 and f[1]<=.6101 and contactStart then
                    contactTravel = math.abs(palm.Position.Z-contactStart.Z)
                end
            end

            local thigh = joint(.49785*sign,-.20025,0,.47139)
            local shin = joint(0,-.44926,0,.41327)
            local sole = joint(0,-.59649,0,.10602)
            local footTarget = C(.55*sign,.156,if sign==1 then .23 else -.33)
            local h,n,d,footGap = solveLimb(hipFrame,thigh,shin,sole,footTarget,V(0,0,-1))
            footError = math.max(footError,footGap)
            pose(pose(pose(lower,name.."UpperLeg",h),name.."LowerLeg",n),name.."Foot",d)
            local leg = hipFrame*thigh.base*h*thigh.tip:Inverse()
            local calf = leg*shin.base*n*shin.tip:Inverse()
            local foot = calf*sole.base*d*sole.tip:Inverse()
            partsForPreview(world,name.."UpperLeg",leg)
            partsForPreview(world,name.."LowerLeg",calf)
            partsForPreview(world,name.."Foot",foot)
        end
        table.insert(render,{t=f[1],parts=world,cue=f[10]})
    end
    assert(lowestPalm>=.085 and lowestPalm<=.22 and contactTravel>=.40,"Hand did not travel through the pickup")
    assert(maxReachError<.075 and footError<.035,"R15 reach exceeds the supported pose tolerance")
    hand:SetAttribute("GreatestHandTargetError",maxReachError)
    hand:SetAttribute("GreatestFootTargetError",footError)
    local destination = "assets/models/hand_scoop/DuneBaron_HandScoop.rbxm"
    local bytes = roblox.serializeModel({export})
    local restored = roblox.deserializeModel(bytes)[1].HandScoopLoop
    local keys = sortedKeys(restored)
    assert(restored.Loop and #keys==#frames and math.abs(keys[#keys].Time-1.54)<.00001)
    local names = {"HandSandTouch","HandLoaded","HandDeposit"}
    local cueIndex = 0
    for _, k in keys do
        for _, item in k:GetChildren() do
            if item:IsA("KeyframeMarker") then
                cueIndex+=1
                assert(item.Name==names[cueIndex])
            end
        end
    end
    assert(cueIndex==#names)
    for _, item in keys[1]:GetDescendants() do
        if item:IsA("Pose") then
            assert((keys[#keys]:FindFirstChild(item.Name,true) :: Pose).CFrame==item.CFrame)
        end
    end
    fs.writeFile(destination,bytes)
    local renderOut = require("@lune/process").args[2]
    if renderOut then
        fs.writeFile(renderOut,require("@lune/serde").encode("json",render))
    end
    print(destination,#keys,lowestPalm,contactTravel,maxReachError,footError)
    return
end

if offline then
    assert(roblox and fs)
    local destination = "assets/models/equipment_animation/DuneBaron_Equipment_Animations.rbxm"
    fs.writeFile(destination, roblox.serializeModel({pack}))
    local restored = roblox.deserializeModel(fs.readFile(destination))[1]
    local count = 0
    for _, item in restored:GetDescendants() do
        if item:IsA("KeyframeSequence") then count += 1 end
    end
    assert(count == 7, "Incomplete animation package")
    print(destination, count, maxGripError)
else
    local storage = game:GetService("ServerStorage")
    local previous = storage:FindFirstChild(pack.Name)
    assert(not previous or previous:GetAttribute("Owner") == "DuneBaronEquipmentArt", "Name already in use")
    if previous then previous:Destroy() end
    pack.Parent = storage
    return {asset = pack:GetFullName(), gripError = maxGripError}
end
