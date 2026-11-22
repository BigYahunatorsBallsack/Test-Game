--!strict
-- Studio Edit or Lune. Add art effects to a copy of Equipment V3.
local offline = game == nil
local roblox = if offline then require("@lune/roblox") else nil
local fs = if offline then require("@lune/fs") else nil
local Instance = if roblox then roblox.Instance else Instance
local CFrame = if roblox then roblox.CFrame else CFrame
local Vector3 = if roblox then roblox.Vector3 else Vector3
local Vector2 = if roblox then roblox.Vector2 else Vector2
local Color3 = if roblox then roblox.Color3 else Color3
local ColorSequence = if roblox then roblox.ColorSequence else ColorSequence
local NumberSequence = if roblox then roblox.NumberSequence else NumberSequence
local NumberSequenceKeypoint = if roblox then roblox.NumberSequenceKeypoint else NumberSequenceKeypoint
local NumberRange = if roblox then roblox.NumberRange else NumberRange
local Enum = if roblox then roblox.Enum else Enum

local V, C = Vector3.new, CFrame.new
local sourceName = "DuneBaronEquipmentAnimations"
local packageName = "DuneBaronEquipmentSandFX"
local packageOwner = "DuneBaronEquipmentSandArt"
local storage = if not offline then game:GetService("ServerStorage") else nil
local source = if roblox and fs
    then roblox.deserializeModel(fs.readFile("assets/models/equipment_animation/DuneBaron_Equipment_Animations.rbxm"))[1]
    else assert(storage):FindFirstChild(sourceName) :: Folder

assert(source and source:IsA("Folder"),"Equipment V3 package is missing")
local pack = source:Clone()
pack.Name = packageName
pack:SetAttribute("Owner",packageOwner)
pack:SetAttribute("SandFxRevision",1)

local bindSource = [==[
--!strict
-- Bind once on the client, before playing the WorkLoop.
local function bind(rig: Model, workTrack: AnimationTrack): () -> ()
    local byMarker: {[string]: {ParticleEmitter}} = {}
    local suction: {ParticleEmitter} = {}
    local connections: {RBXScriptConnection} = {}
    local cargo = rig:FindFirstChild("SandFxBucketLoad")
    local generation = 0

    local function on(marker: string, fn: () -> ())
        table.insert(connections, workTrack:GetMarkerReachedSignal(marker):Connect(function()
            if workTrack.IsPlaying and rig:IsDescendantOf(workspace) then fn() end
        end))
    end

    for _, object in rig:GetDescendants() do
        if object:IsA("ParticleEmitter") and object:GetAttribute("SandFx") then
            local marker = object:GetAttribute("Marker") :: string
            if marker == "IntakeEngage" then
                table.insert(suction, object)
            else
                if not byMarker[marker] then byMarker[marker] = {} end
                table.insert(byMarker[marker], object)
            end
        end
    end

    local function setSuction(active: boolean)
        for _, emitter in suction do emitter.Enabled = active end
    end

    local function reset()
        generation += 1
        setSuction(false)
        if cargo and cargo:IsA("BasePart") then cargo.Transparency = 1 end
    end

    if #suction > 0 then
        on("IntakeEngage", function() setSuction(true) end)
        on("IntakeRelease", function() setSuction(false) end)
    end
    if cargo and cargo:IsA("BasePart") then
        local sand = cargo
        on("BucketLoaded", function() sand.Transparency = 0 end)
        on("BucketDump", function() sand.Transparency = 1 end)
    end

    for marker, emitters in byMarker do
        on(marker,function()
            local side = if workTrack.TimePosition < workTrack.Length*.5 then "Left" else "Right"
            local markerGeneration = generation
            for _, emitter in emitters do
                local selectedSide = emitter:GetAttribute("Side")
                if selectedSide and selectedSide ~= side then continue end
                local count = emitter:GetAttribute("BurstCount") :: number
                local delaySeconds = (emitter:GetAttribute("DelaySeconds") :: number?) or 0
                if delaySeconds == 0 then
                    emitter:Emit(count)
                else
                    task.delay(delaySeconds,function()
                        if generation == markerGeneration and workTrack.IsPlaying and emitter:IsDescendantOf(workspace) then
                            emitter:Emit(count)
                        end
                    end)
                end
            end
        end)
    end

    table.insert(connections,workTrack.Stopped:Connect(reset))
    reset()
    return function()
        reset()
        for _, connection in connections do connection:Disconnect() end
        table.clear(connections)
        for _, row in byMarker do
            for _, emitter in row do emitter:Clear() end
        end
        for _, emitter in suction do emitter:Clear() end
    end
end

return table.freeze({Bind = bind})
]==]

local function attachment(parent: BasePart, name: string, at: Vector3, direction: Vector3): Attachment
    local origin = Instance.new("Attachment")
    origin.Name = name
    origin.CFrame = CFrame.lookAt(at,at+direction)
    origin.Parent = parent
    return origin
end

local function curve(points: {{number}}): NumberSequence
    local keys = {}
    for _, point in points do
        table.insert(keys,NumberSequenceKeypoint.new(point[1],point[2]))
    end
    return NumberSequence.new(keys)
end

local function particles(
    origin: Attachment, dust: boolean, marker: string, count: number, lifetime: NumberRange,
    speed: NumberRange, size: number, spread: Vector2, acceleration: Vector3, drag: number
): ParticleEmitter
    local e = Instance.new("ParticleEmitter")
    e.Name = if dust then "SandFxDust" else "SandFxGrains"
    e.Enabled = false
    e.Rate = if marker == "IntakeEngage" then count else 0
    e.Lifetime, e.Speed, e.SpreadAngle, e.Acceleration, e.Drag = lifetime,speed,spread,acceleration,drag
    e.EmissionDirection = Enum.NormalId.Front
    e.LightInfluence = .68
    e.Rotation = NumberRange.new(0,360)
    e.RotSpeed = NumberRange.new(-110,110)
    e.Texture = "rbxasset://textures/particles/"..(if dust then "smoke_main.dds" else "SquareParticle.png")
    e.Color = if dust then ColorSequence.new(Color3.fromRGB(224,181,120),Color3.fromRGB(241,208,155))
        else ColorSequence.new(Color3.fromRGB(221,164,88),Color3.fromRGB(191,131,67))
    e.Size = if dust then curve({{0,size*.38},{.30,size*.79},{1,size}})
        else curve({{0,size*.76},{.13,size},{.82,size*.86},{1,size*.44}})
    e.Transparency = if dust then curve({{0,.69},{.17,.22},{.49,.42},{1,1}})
        else curve({{0,.07},{.17,0},{.80,.12},{1,1}})
    e:SetAttribute("SandFx",true)
    e:SetAttribute("Marker",marker)
    e:SetAttribute("BurstCount",if marker == "IntakeEngage" then 0 else count)
    e.Parent = origin
    return e
end

local n, s = NumberRange.new, Vector2.new
local belt = pack:FindFirstChild("bucket_chain") :: Model
local beltRoot = assert(belt.PrimaryPart)
local discharge = beltRoot:FindFirstChild("Discharge") :: Attachment
local hopper = belt:FindFirstChild("Sand in Hopper") :: BasePart
for _, side in {-1,1} do
    local stream = attachment(beltRoot,"SandFxConveyorStream",discharge.CFrame.Position+V(side*.26,-.06,.09),V(side*.075,-1,.24))
    for index, delaySeconds in {0,.081,.163} do
        local grains = particles(stream,false,"Discharge",6,n(.34,.46),n(2.4,4.1),.119,s(12,14),V(0,-30,0),.30)
        grains.Name = "SandFxSpill"..index
        grains:SetAttribute("DelaySeconds",delaySeconds)
    end
    local landing = beltRoot.CFrame:PointToObjectSpace(hopper.CFrame.Position)+V(side*.32,hopper.Size.Y*.52,.07)
    local impact = attachment(beltRoot,"SandFxConveyorLanding",landing,V(side*.24,1,.3))
    local plume = particles(impact,true,"Discharge",2,n(.32,.54),n(.28,1.08),.91,s(40,38),V(0,1.3,0),3.4)
    plume:SetAttribute("DelaySeconds",.37)
end

local digger = pack:FindFirstChild("mini_digger") :: Model
local scoop = digger:FindFirstChild("Scoop") :: BasePart
local teeth = scoop:FindFirstChild("WorkOrigin") :: Attachment
for _, side in {-1,1} do
    local cut = attachment(scoop,"SandFxBucketCut",teeth.CFrame.Position+V(side*.61,.10,-.11),V(side*.11,1,.48))
    particles(cut,true,"BucketCut",4,n(.39,.62),n(.55,1.50),1.25,s(38,42),V(0,1.35,0),3.0)
    particles(cut,false,"BucketCut",7,n(.22,.33),n(3.3,6.7),.116,s(34,35),V(0,-31,0),1.0)
end
for i=-1,1 do
    local pour = attachment(scoop,"SandFxBucketPour",V(i*.53,-1.40,.75),V(i*.23,-.31,1))
    for index, delaySeconds in {0,.070,.141,.204} do
        local grains = particles(pour,false,"BucketDump",8,n(.37,.57),n(1.8,4.5),.138,s(23,23),V(0,-35,0),.34)
        grains.Name = "SandFxPour"..index
        grains:SetAttribute("DelaySeconds",delaySeconds)
    end
    particles(pour,true,"BucketDump",1,n(.29,.45),n(.34,1.3),.77,s(19,19),V(0,-9,0),.48)
end

local cargo = Instance.new("Part")
cargo.Name = "SandFxBucketLoad"
cargo.Size = V(1.72,.57,1.27)
cargo.CFrame = scoop.CFrame*C(0,-1.267,-.18)
cargo.Material = Enum.Material.Sand
cargo.Color = Color3.fromRGB(218,177,111)
cargo.Transparency = 1
cargo.CanCollide, cargo.CanTouch, cargo.CanQuery, cargo.Massless = false,false,false,true
local heap = Instance.new("SpecialMesh")
heap.MeshType = Enum.MeshType.Sphere
heap.Parent = cargo
local weld = Instance.new("WeldConstraint")
weld.Part0, weld.Part1 = scoop,cargo
weld.Parent = cargo
cargo.Parent = digger

local robot = pack:FindFirstChild("vacuum_robot") :: Model
local intake = robot:FindFirstChild("Intake") :: BasePart
local mouth = intake:FindFirstChild("WorkOrigin") :: Attachment
for _, side in {-1,1} do
    local delta = V(side*.25,.01,-.61)
    local suction = attachment(intake,"SandFxSuction",mouth.CFrame.Position+delta,-delta+V(0,.055,.04))
    particles(suction,true,"IntakeEngage",21,n(.095,.135),n(4.1,5.4),.30,s(10,11),V(0,.22,0),.12)
    particles(suction,false,"IntakeEngage",27,n(.096,.140),n(4.0,5.15),.079,s(11,11),V(0,.21,0),.15)
    local sweep = particles(suction,false,"IntakeSweep",4,n(.096,.133),n(4.35,5.25),.078,s(6,8),V(0,.21,0),.09)
    sweep.Name = "SandFxSweepGrains"
end

local harvester = pack:FindFirstChild("mega_machine") :: Model
local harvesterRoot = assert(harvester.PrimaryPart)
local cutter = harvesterRoot:FindFirstChild("WorkOrigin") :: Attachment
for _, side in {-1,1} do
    local label = if side < 0 then "Left" else "Right"
    for _, x in {2.02,4.66} do
        local drum = attachment(harvesterRoot,"SandFxCutter"..label,
            cutter.CFrame.Position+V(side*x,-.27,.46),V(side*.18,.34,-1))
        local cloud = particles(drum,true,"CutterLoad",5,n(.52,.81),n(2.0,4.0),3.65,s(32,28),V(0,1.75,0),3.8)
        local grains = particles(drum,false,"CutterLoad",15,n(.25,.39),n(5.3,9.4),.172,s(26,33),V(0,-34,0),.85)
        cloud:SetAttribute("Side",label)
        grains:SetAttribute("Side",label)
    end
end

local counts = {}
for _, rig in pack:GetChildren() do
    if not rig:IsA("Model") then continue end
    local module = Instance.new("ModuleScript")
    module.Name, module.Source, module.Parent = "SandEffects",bindSource,rig
    local count = 0
    for _, object in rig:GetDescendants() do
        if object:IsA("ParticleEmitter") and object:GetAttribute("SandFx") then
            assert(not object.Enabled and object.Parent:IsA("Attachment"))
            count += 1
        end
    end
    counts[rig.Name] = count
end

if roblox and fs then
    local output = "assets/models/equipment_sand_fx/DuneBaron_Equipment_SandFX.rbxm"
    local bytes = roblox.serializeModel({pack})
    local restored = roblox.deserializeModel(bytes)[1]
    for name, expected in counts do
        local rig = restored:FindFirstChild(name)
        assert(rig and rig.SandEffects.Source==bindSource and rig.Animations.WorkLoop.Loop)
        local actual = 0
        for _, item in rig:GetDescendants() do
            if item:IsA("ParticleEmitter") and item:GetAttribute("SandFx") then
                assert(not item.Enabled)
                actual += 1
            end
        end
        assert(expected == actual,name)
    end
    fs.writeFile(output,bytes)
    assert(fs.readFile(output)==bytes)
    print(output,"4 machines verified")
else
    local run = game:GetService("RunService")
    assert(run:IsStudio() and not run:IsRunning() and game.PlaceId==135831532782380,"Use Every Last Grain in Studio Edit")
    local target = assert(storage)
    local old = target:FindFirstChild(packageName)
    assert(not old or old:GetAttribute("Owner")==packageOwner)
    if old then old:Destroy() end
    pack.Parent = target
    return {path=pack:GetFullName(),emitters=counts}
end
