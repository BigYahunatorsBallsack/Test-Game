-- Run with Lune from the repository root.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local C, Instance, Enum = roblox.CFrame.new, roblox.Instance, roblox.Enum
local output = "assets/models/animation_clips/"

local function create(class, name, parent)
    local node = Instance.new(class)
    node.Name = name
    node.Parent = parent
    return node
end

local function write(root, filename, expected)
    fs.writeFile(output .. filename, roblox.serializeModel({root}))
    local imported = roblox.deserializeModel(fs.readFile(output .. filename))[1]
    assert(#imported:GetChildren() == expected)
    for _, clip in imported:GetChildren() do
        assert(clip:IsA("KeyframeSequence") and #clip:GetChildren() > 1)
        print(clip.Name, #clip:GetChildren())
    end
    return imported
end

local equipment = roblox.deserializeModel(fs.readFile(
    "assets/models/equipment_animation/DuneBaron_Equipment_Animations.rbxm"
))[1]
local equipmentClips = create("Folder", "EquipmentClips")
for _, spec in {
    {"bucket_chain","WorkLoop","Conveyor_WorkLoop"},
    {"mini_digger","WorkLoop","Excavator_WorkLoop"},
    {"mini_digger","TravelLoop","Excavator_TravelLoop"},
    {"mega_machine","WorkLoop","Harvester_WorkLoop"},
    {"mega_machine","TravelLoop","Harvester_TravelLoop"},
} do
    local clip = equipment[spec[1]].Animations[spec[2]]:Clone()
    clip.Name = spec[3]
    clip:SetAttribute("RigId",spec[1])
    assert(clip.Loop)
    clip.Parent = equipmentClips
end
write(equipmentClips,"DuneBaron_EquipmentClips.rbxm",5)

local bytes = buffer.fromstring(fs.readFile("assets/models/sandwurm/DuneBaron_Sandwurm.glb"))
assert(buffer.readstring(bytes,0,4) == "glTF")
local jsonLength = buffer.readu32(bytes,12)
local doc = serde.decode("json",buffer.readstring(bytes,20,jsonLength))
local base = 28 + jsonLength
local function layout(index)
    local accessor = doc.accessors[index+1]
    local view = doc.bufferViews[accessor.bufferView+1]
    assert(accessor.componentType == 5126 and not view.byteStride)
    return base+(view.byteOffset or 0)+(accessor.byteOffset or 0)
end
local animation = doc.animations[1]
assert(animation.name == "BreachSnapBurrow")
local joints = doc.skins[1].joints
local parents, bind, times = {}, {}, {}
for _, index in joints do
    local node = doc.nodes[index+1]
    for _, child in node.children or {} do parents[child] = index end
    local x,y,z = table.unpack(node.translation)
    local qx,qy,qz,qw = table.unpack(node.rotation)
    bind[index] = C(x,y,z,qx,qy,qz,qw)
end
local timeInput = animation.samplers[1].input
for i=1,doc.accessors[timeInput+1].count do
    times[i] = buffer.readf32(bytes,layout(timeInput)+(i-1)*4)
end
local cues = {[2]="SandWarning",[4]="Breach",[8]="Bite",[11]="Burrow"}
local transforms = {}
for i=1,#times do
    local track = {}
    for _, channel in animation.channels do
        local sample = animation.samplers[channel.sampler+1]
        assert(sample.input == timeInput and sample.interpolation == "LINEAR")
        local index, path = channel.target.node, channel.target.path
        local old = bind[index]
        local position = old.Position
        local target
        if path == "translation" then
            local offset = layout(sample.output)+(i-1)*12
            target = C(buffer.readf32(bytes,offset),buffer.readf32(bytes,offset+4),buffer.readf32(bytes,offset+8))*old.Rotation
        else
            assert(path == "rotation")
            local offset = layout(sample.output)+(i-1)*16
            target = C(position.X,position.Y,position.Z,buffer.readf32(bytes,offset),
                buffer.readf32(bytes,offset+4),buffer.readf32(bytes,offset+8),buffer.readf32(bytes,offset+12))
        end
        track[index] = old:ToObjectSpace(target)
    end
    transforms[i] = track
end

local worm = create("Folder","SandwurmClips")
for _, range in {
    {"Sandworm_Emerge",1,6},
    {"Sandworm_Bite",6,10},
    {"Sandworm_Burrow",10,12},
} do
    local clip = create("KeyframeSequence",range[1],worm)
    clip.Loop,clip.Priority = false,Enum.AnimationPriority.Action
    clip:SetAttribute("SourceStart",times[range[2]])
    clip:SetAttribute("SourceEnd",times[range[3]])
    for i=range[2],range[3] do
        local frame = create("Keyframe",cues[i] or "Keyframe",clip)
        frame.Time = times[i]-times[range[2]]
        if cues[i] then create("KeyframeMarker",cues[i],frame) end
        local poses = {}
        for _, j in joints do
            local p = create("Pose",doc.nodes[j+1].name,poses[parents[j]] or frame)
            p.CFrame = transforms[i][j] or roblox.CFrame.identity
            p.Weight,p.EasingStyle = 1,Enum.PoseEasingStyle.Linear
            poses[j] = p
        end
    end
end
local restored = write(worm,"DuneBaron_SandwormClips.rbxm",3)
local names = {"Sandworm_Emerge","Sandworm_Bite","Sandworm_Burrow"}
for i=1,#names-1 do
    local a,b = restored[names[i]],restored[names[i+1]]
    local ending,starting
    for _, k in a:GetChildren() do if not ending or ending.Time<k.Time then ending=k end end
    for _, k in b:GetChildren() do if k.Time==0 then starting=k end end
    assert(starting and ending)
    for _, p in ending:GetDescendants() do
        if p:IsA("Pose") then
            local match = starting:FindFirstChild(p.Name,true)
            assert(match and match.CFrame==p.CFrame,"Mismatched transition "..p.Name)
        end
    end
end
