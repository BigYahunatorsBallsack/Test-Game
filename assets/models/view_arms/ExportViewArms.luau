--!strict
-- Aus dem Repo-Ordner: lune run assets/models/view_arms/ExportViewArms
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local CFrame, Vector3, Color3, Enum, Instance = roblox.CFrame, roblox.Vector3, roblox.Color3, roblox.Enum, roblox.Instance
local Feel = require("../../../src/shared/Data/StabFeel")
local View = require("../../../src/shared/Data/FirstPerson").viewmodel

local model = Instance.new("Model")
model.Name = "ViewArms"
local canvas = Color3.fromRGB(178, 126, 74)
local seam = Color3.fromRGB(104, 71, 48)
local cuff = Color3.fromRGB(225, 175, 106)
local skin = Color3.fromRGB(218, 164, 119)

local function part(name, size, cf, color, material)
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, cf, color, material
    p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow, p.Massless = false, false, false, false, true
    p.Parent = model
    return p
end

local root = part("CameraRoot", Vector3.new(0.1, 0.1, 0.1), CFrame.identity, canvas, Enum.Material.SmoothPlastic)
root.Transparency, root.Anchored, root.Massless = 1, true, false
model.PrimaryPart = root
local controller = Instance.new("AnimationController")
controller.Parent = model
Instance.new("Animator").Parent = controller

local function motor(name, parent, child, joint)
    local m = Instance.new("Motor6D")
    m.Name, m.Part0, m.Part1 = name, parent, child
    m.C0, m.C1 = parent.CFrame:ToObjectSpace(joint), child.CFrame:ToObjectSpace(joint)
    m.Parent = parent
    return m
end

local function trim(parent, name, size, relative, color, material, shape)
    local p = part(name, size, parent.CFrame * relative, color, material)
    p.Shape = shape or Enum.PartType.Block
    local weld = Instance.new("WeldConstraint")
    weld.Part0, weld.Part1, weld.Parent = parent, p, p
    p.Parent = parent
end

local function frame(spec)
    local o, r = spec.offset, spec.rotation
    return CFrame.new(o.x, o.y, o.z) * CFrame.Angles(math.rad(r.x), math.rad(r.y), math.rad(r.z))
end

local function handFrame(idle, x, y, z, pitch, yaw, roll)
    return CFrame.new(idle.Position + Vector3.new(x, y, z))
        * idle.Rotation * CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
end

local function segment(a, b)
    return CFrame.lookAt((a + b) / 2, b, Vector3.yAxis)
end

local function solve(hand, shoulder, side, upperLength, lowerLength)
    local wrist = (hand * CFrame.new(0, 0, 0.16)).Position
    local span = wrist - shoulder
    local direction = span.Unit
    local distance = span.Magnitude
    assert(distance < upperLength + lowerLength, "Hand außerhalb der Reichweite")
    local along = (upperLength ^ 2 - lowerLength ^ 2 + distance ^ 2) / (2 * distance)
    local bend = Vector3.new(side * 0.75, -1, 0)
    local perpendicular = (bend - direction * bend:Dot(direction)).Unit
    local elbow = shoulder + direction * along + perpendicular * math.sqrt(upperLength ^ 2 - along ^ 2)
    return { segment(shoulder, elbow), segment(elbow, wrist), hand }, { shoulder, elbow, wrist }
end

local function arm(sideName, side, idle, shoulder, upperLength, lowerLength, gripName, gripOffset)
    local poses, joints = solve(idle, shoulder, side, upperLength, lowerLength)
    local upper = part(sideName .. "UpperArm", Vector3.new(0.43, 0.43, upperLength + 0.11), poses[1], canvas, Enum.Material.Fabric)
    local lower = part(sideName .. "LowerArm", Vector3.new(0.34, 0.34, lowerLength + 0.06), poses[2], canvas, Enum.Material.Fabric)
    local hand = part(sideName .. "Hand", Vector3.new(0.30, 0.28, 0.36), poses[3], skin, Enum.Material.SmoothPlastic)
    local motors = {
        motor(sideName .. "Shoulder", root, upper, CFrame.new(joints[1])),
        motor(sideName .. "Elbow", upper, lower, CFrame.new(joints[2])),
        motor(sideName .. "Wrist", lower, hand, CFrame.new(joints[3])),
    }
    trim(upper, "ElbowPatch", Vector3.new(0.32, 0.06, 0.28), CFrame.new(0, 0.23, -upperLength * 0.29), seam, Enum.Material.Fabric)
    trim(lower, "Cuff", Vector3.new(0.41, 0.41, 0.18), CFrame.new(0, 0, -lowerLength / 2 + 0.08), cuff, Enum.Material.Fabric)
    trim(lower, "CuffEdge", Vector3.new(0.42, 0.42, 0.045), CFrame.new(0, 0, -lowerLength / 2 + 0.005), seam, Enum.Material.Fabric)
    trim(hand, "Knuckles", Vector3.new(0.29, 0.24, 0.19), CFrame.new(0, 0.015, -0.13), skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
    trim(hand, "Thumb", Vector3.new(0.14, 0.17, 0.24), CFrame.new(-side * 0.145, 0.023, -0.012)
        * CFrame.Angles(0, side * math.rad(22), 0), skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
    local grip = Instance.new("Attachment")
    grip.Name, grip.CFrame, grip.Parent = gripName, gripOffset, hand
    return { motors = motors, side = side, shoulder = shoulder, upperLength = upperLength, lowerLength = lowerLength }
end

local rightIdle = frame(View.right)
local leftIdle = frame(View.left) * CFrame.new(0, 0.62, 0)
local right = arm("Right", 1, rightIdle, Vector3.new(1.40, -1.32, -0.14), 0.88, 0.85, "Grip", CFrame.identity)
local left = arm("Left", -1, leftIdle, Vector3.new(-1.36, -0.95, -0.15), 0.85, 0.83, "BucketGrip", CFrame.new(0, -0.62, 0))

local clip = Instance.new("KeyframeSequence")
clip.Name, clip.Loop, clip.Priority = "ViewArmsStab", false, Enum.AnimationPriority.Action
local function pose(parent, name, cf)
    local p = Instance.new("Pose")
    p.Name, p.CFrame, p.Weight = name, cf, 1
    p.Parent = parent
    return p
end

local function armPoses(parent, spec, hand, shoulderOffset, rest)
    local poses = solve(hand, spec.shoulder + shoulderOffset, spec.side, spec.upperLength, spec.lowerLength)
    local from = CFrame.identity
    for i, joint in spec.motors do
        local to = poses[i]
        local transform = if rest then CFrame.identity else joint.C0:Inverse() * from:ToObjectSpace(to) * joint.C1
        parent = pose(parent, joint.Part1.Name, transform)
        from = to
    end
end

local strike = handFrame(rightIdle, -0.13, -0.52, -0.37, -24, 5, -4)
local lever = handFrame(rightIdle, -0.33, -0.04, -0.29, 19, 16, -7)
local toss = handFrame(rightIdle, -0.84, 0.26, -0.35, 10, 43, 24)
local bucketDip = handFrame(leftIdle, -0.025, -0.09, -0.035, -4, 0, -4)
local shoulderStrike = Vector3.new(-0.02, -0.11, -0.19)
local shoulderToss = Vector3.new(-0.42, 0.05, -0.25)

local function key(time, hand, shoulderOffset, bucket, rest)
    local frame = Instance.new("Keyframe")
    frame.Time, frame.Parent = time * Feel.arm.animationSeconds, clip
    local base = pose(frame, root.Name, CFrame.identity)
    armPoses(base, right, hand, shoulderOffset, rest)
    armPoses(base, left, bucket, Vector3.zero, rest)
end

key(0, rightIdle, Vector3.zero, leftIdle, true)
-- Mehrere lineare Schlüssel bilden die Beschleunigung beim Einstechen ab.
for _, t in { 0.25, 0.5, 0.75, 1 } do
    key(Feel.arm.strikeEnd * t, rightIdle:Lerp(strike, t ^ 2), shoulderStrike * t ^ 2, leftIdle, false)
end
key(Feel.arm.holdEnd, strike, shoulderStrike, leftIdle, false)
key(0.385, strike:Lerp(lever, 0.68), shoulderStrike:Lerp(Vector3.zero, 0.68), leftIdle, false)
key(0.48, lever, Vector3.zero, leftIdle, false)
key(0.58, lever:Lerp(toss, 0.67), shoulderToss * 0.67, leftIdle, false)
key(0.68, toss, shoulderToss, leftIdle:Lerp(bucketDip, 0.55), false)
key(0.74, toss:Lerp(rightIdle, 0.25), shoulderToss * 0.75, bucketDip, false)
key(0.82, toss:Lerp(rightIdle, 0.64), shoulderToss * 0.36, bucketDip:Lerp(leftIdle, 0.52), false)
key(0.91, toss:Lerp(rightIdle, 0.91), shoulderToss * 0.09, bucketDip:Lerp(leftIdle, 0.93), false)
key(1, rightIdle, Vector3.zero, leftIdle, true)

local output = "assets/models/view_arms/"
fs.writeFile(output .. "ViewArms.rbxm", roblox.serializeModel({ model }))
fs.writeFile(output .. "ViewArmsStab.rbxm", roblox.serializeModel({ clip }))
