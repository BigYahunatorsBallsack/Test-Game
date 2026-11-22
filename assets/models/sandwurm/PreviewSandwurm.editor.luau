--!strict
-- Studio-only mesh preview for the generated GLB. Pass its zstd/base64 chunks
-- as numbered StringValues in ServerStorage.DuneBaronSandwurmPreviewData.
local storage = game:GetService("ServerStorage")
local assets = game:GetService("AssetService")
local encoding = game:GetService("EncodingService")
local http = game:GetService("HttpService")
local run = game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Studio Edit mode required")

local transport = storage:WaitForChild("DuneBaronSandwurmPreviewData")
local chunks = {}
for _, child in transport:GetChildren() do
    if child:IsA("StringValue") then
        chunks[assert(tonumber(child.Name))] = child.Value
    end
end
local compressed = encoding:Base64Decode(buffer.fromstring(table.concat(chunks)))
local bytes = encoding:DecompressBuffer(compressed, Enum.CompressionAlgorithm.Zstd)
assert(buffer.readstring(bytes, 0, 4) == "glTF", "Expected a binary glTF")
local jsonLength = buffer.readu32(bytes, 12)
local gltf = http:JSONDecode(buffer.readstring(bytes, 20, jsonLength))
local start = 28 + jsonLength
local V, C = Vector3.new, CFrame.new

local function layout(index: number): (number, number)
    local accessor = gltf.accessors[index + 1]
    local view = gltf.bufferViews[accessor.bufferView + 1]
    return start + (view.byteOffset or 0) + (accessor.byteOffset or 0), accessor.count
end

local primitive = gltf.meshes[1].primitives[1]
local posAt, vertexCount = layout(primitive.attributes.POSITION)
local normAt = layout(primitive.attributes.NORMAL)
local colorAt = layout(primitive.attributes.COLOR_0)
local jointsAt = layout(primitive.attributes.JOINTS_0)
local weightsAt = layout(primitive.attributes.WEIGHTS_0)
local indexAt, indexCount = layout(primitive.indices)
assert(vertexCount < 16000 and indexCount / 3 <= 20000)

local data = gltf.accessors[primitive.attributes.POSITION + 1]
local center = (V(table.unpack(data.min)) + V(table.unpack(data.max))) / 2
local editable = assert(assets:CreateEditableMesh(), "Could not allocate editable mesh")
local bindFrames: {CFrame} = {}
local parents: {number} = {}
local ids = {}
local bones = {}
local bindNodes = gltf.skins[1].joints

for _, index in bindNodes do
    local node = gltf.nodes[index + 1]
    for _, child in node.children or {} do
        parents[child + 1] = index + 1
    end
end
for _, index in bindNodes do
    local key = index + 1
    local node = gltf.nodes[key]
    local x, y, z = table.unpack(node.translation)
    local qx, qy, qz, qw = table.unpack(node.rotation)
    local localBind = C(x, y, z, qx, qy, qz, qw)
    local parentKey = parents[key]
    bindFrames[key] = if parentKey then localBind else C(-center) * localBind
    local id = editable:AddBone({Name = node.name, CFrame = bindFrames[key], Virtual = false})
    ids[key] = id
    if parentKey then
        editable:SetBoneParent(id, ids[parentKey])
        editable:SetBoneCFrame(id, localBind)
    end
    local bone = Instance.new("Bone")
    bone.Name = node.name
    bone.CFrame = bindFrames[key]
    if parentKey then bone.Parent = bones[parentKey] end
    bones[key] = bone
end

local function vec(offset: number): Vector3
    return V(buffer.readf32(bytes, offset), buffer.readf32(bytes, offset + 4), buffer.readf32(bytes, offset + 8))
end

local function srgb(value: number): number
    return math.clamp(1.055 * value ^ (1 / 2.4) - 0.055, 0, 1)
end

local verts, normals, colors = table.create(vertexCount), table.create(vertexCount), table.create(vertexCount)
for i = 0, vertexCount - 1 do
    local j = i + 1
    local id = editable:AddVertex(vec(posAt + 12 * i) - center)
    verts[j] = id
    normals[j] = editable:AddNormal(vec(normAt + 12 * i))
    local tint = vec(colorAt + 12 * i)
    colors[j] = editable:AddColor(Color3.new(srgb(tint.X), srgb(tint.Y), srgb(tint.Z)), 1)
    local influences, amounts = {}, {}
    for k = 0, 1 do
        local weight = buffer.readf32(bytes, weightsAt + 16 * i + 4 * k)
        if weight > 0 then
            table.insert(influences, ids[1 + buffer.readu16(bytes, jointsAt + 8 * i + 2 * k)])
            table.insert(amounts, weight)
        end
    end
    editable:SetVertexBones(id, influences)
    editable:SetVertexBoneWeights(id, amounts)
    if j % 1600 == 0 then task.wait() end
end
for i = 0, indexCount / 3 - 1 do
    local offset = indexAt + 6 * i
    local a, b, c = buffer.readu16(bytes, offset) + 1, buffer.readu16(bytes, offset + 2) + 1, buffer.readu16(bytes, offset + 4) + 1
    local face = editable:AddTriangle(verts[a], verts[b], verts[c])
    editable:SetFaceColors(face, {colors[a], colors[b], colors[c]})
    editable:SetFaceNormals(face, {normals[a], normals[b], normals[c]})
    if i % 3000 == 0 then task.wait() end
end

local mesh = assets:CreateMeshPartAsync(Content.fromObject(editable), {CollisionFidelity = Enum.CollisionFidelity.Box})
mesh.Name = "SandwurmSkin"
mesh.Anchored = true
mesh.CanCollide = false
mesh.CanTouch = false
mesh.CanQuery = false
mesh.Material = Enum.Material.SmoothPlastic
mesh.Color = Color3.new(1, 1, 1)
mesh.CFrame = C(center)
mesh.PivotOffset = C(-center)
for key, bone in bones do
    if not parents[key] then bone.Parent = mesh end
end

local model = Instance.new("Model")
model.Name = "DuneBaronSandwurmSmooth"
model:SetAttribute("Owner", "DuneBaronSandwurmArt")
model:SetAttribute("StudioPreview", true)
model:SetAttribute("Triangles", indexCount / 3)
mesh.Parent = model
model.PrimaryPart = mesh
local controller = Instance.new("AnimationController", model)
Instance.new("Animator", controller)

local clip = gltf.animations[1]
local sequence = Instance.new("KeyframeSequence", model)
sequence.Name = clip.name
sequence.Loop = false
sequence.Priority = Enum.AnimationPriority.Action
local markers = {[2] = "SandWarning", [4] = "Breach", [8] = "Bite", [11] = "Burrow"}
local timeAt, frames = layout(clip.samplers[1].input)
for index = 1, frames do
    local frame = Instance.new("Keyframe")
    frame.Time = buffer.readf32(bytes, timeAt + (index - 1) * 4)
    frame.Name = markers[index] or "Keyframe"
    frame.Parent = sequence
    if markers[index] then
        local marker = Instance.new("KeyframeMarker")
        marker.Name = markers[index]
        marker.Parent = frame
    end
    local poses = {}
    for _, jointIndex in bindNodes do
        local key = jointIndex + 1
        local pose = Instance.new("Pose")
        pose.Name = bones[key].Name
        pose.Weight = 1
        pose.EasingStyle = Enum.PoseEasingStyle.Linear
        pose.Parent = poses[parents[key]] or frame
        poses[key] = pose
    end
    for _, channel in clip.channels do
        local key = channel.target.node + 1
        local base = bindFrames[key]
        local output = layout(clip.samplers[channel.sampler + 1].output)
        local sample = index - 1
        if channel.target.path == "translation" then
            poses[key].CFrame = base:ToObjectSpace(C(vec(output + 12 * sample)) * base.Rotation)
        else
            local offset = output + 16 * sample
            local x, y, z, w = buffer.readf32(bytes, offset), buffer.readf32(bytes, offset + 4),
                buffer.readf32(bytes, offset + 8), buffer.readf32(bytes, offset + 12)
            poses[key].CFrame = base:ToObjectSpace(C(base.Position.X, base.Position.Y, base.Position.Z, x, y, z, w))
        end
    end
end

local old = storage:FindFirstChild(model.Name)
assert(not old or old:GetAttribute("Owner") == "DuneBaronSandwurmArt")
if old then old:Destroy() end
model.Parent = storage
transport:Destroy()
return {model = model:GetFullName(), vertices = vertexCount, triangles = indexCount / 3, bones = #bindNodes, frames = frames}
