--!strict
-- Offline authoring for the two SandFX vehicle rigs and their stock R15 drivers.
local rbx = require("@lune/roblox")
local fs = require("@lune/fs")
local C, V = rbx.CFrame.new, rbx.Vector3.new
local I = rbx.CFrame.identity
local Enum = rbx.Enum
local paint = rbx.Color3.fromRGB

local function angles(x: number, y: number, z: number): CFrame
    return rbx.CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function make(class: string, name: string, parent: Instance?): any
    local object = rbx.Instance.new(class)
    object.Name = name
    object.Parent = parent
    return object
end

local function join(class: string, name: string, anchor: BasePart, part: BasePart)
    local link = make(class, name, part)
    link.Part0, link.Part1 = anchor, part
    link.C0, link.C1 = anchor.CFrame:ToObjectSpace(part.CFrame), I
end

local function part(
    parent: Instance,
    anchor: BasePart,
    name: string,
    frame: CFrame,
    size: Vector3,
    color: Color3,
    shape: Enum.PartType?,
    moving: boolean?
): BasePart
    local block = make("Part", name, parent)
    block.CFrame, block.Size, block.Color = frame, size, color
    block.Shape = shape or Enum.PartType.Block
    block.Material = Enum.Material.SmoothPlastic
    block.Massless = true
    block.CanCollide, block.CanTouch, block.CanQuery = false, false, false
    join(if moving then "Motor6D" else "Weld", name, anchor, block)
    return block
end

local function attachment(parent: BasePart, name: string, frame: CFrame): Attachment
    local marker = make("Attachment", name, parent)
    marker.CFrame = frame
    return marker
end

local function strut(
    parent: Instance,
    anchor: BasePart,
    name: string,
    start: Vector3,
    stop: Vector3,
    width: number,
    color: Color3,
    round: boolean?
): BasePart
    local x = (stop - start).Unit
    local up = if math.abs(x.Y) > 0.95 then V(0, 0, 1) else V(0, 1, 0)
    local y = (up - x * up:Dot(x)).Unit
    return part(
        parent,
        anchor,
        name,
        rbx.CFrame.fromMatrix((start + stop) * 0.5, x, y),
        V((stop - start).Magnitude, width, width),
        color,
        if round then Enum.PartType.Cylinder else nil
    )
end

local graphite = paint(37, 46, 49)
local rubber = paint(22, 30, 34)
local darkSteel = paint(66, 83, 86)
local gold = paint(226, 158, 53)
local orange = paint(223, 111, 54)

local function excavator(
    rig: Model,
    root: BasePart,
    turret: BasePart
): (CFrame, { BasePart }, { Attachment })
    local function resize(panel: BasePart, size: Vector3, frame: CFrame)
        local found = 0
        for _, connection in rig:GetDescendants() do
            if
                connection:IsA("WeldConstraint")
                and (connection.Part0 == panel or connection.Part1 == panel)
            then
                assert(connection.Part0 == turret or connection.Part1 == turret, panel.Name)
                connection:Destroy()
                found += 1
            end
        end
        assert(found == 1, panel.Name)
        panel.Size, panel.CFrame = size, root.CFrame * frame
        join("Weld", "CabMount", turret, panel)
    end

    resize(rig["Cab Footwell"], V(2.69, 0.25, 3.53), C(-1.22, 2.41, -0.99))
    for _, pillar in rig:GetChildren() do
        if pillar.Name == "ROPS Frame" and pillar:IsA("BasePart") then
            local old = root.CFrame:ToObjectSpace(pillar.CFrame)
            local front = old.Z < 0
            local x = if old.X < -1 then -2.50 else 0.04
            resize(
                pillar,
                V(3.90, 0.15, 0.16),
                C(x, 4.44, if front then -2.51 else 0.51) * angles(0, 0, 90)
            )
        end
    end
    resize(rig["Cab Canopy"], V(2.85, 0.32, 3.36), C(-1.23, 6.50, -1.02))
    resize(rig["Roof Lip"], V(2.87, 0.09, 3.40), C(-1.23, 6.705, -1.02))
    resize(rig["Front Windscreen"], V(2.40, 2.95, 0.10), C(-1.23, 4.77, -2.51))
    resize(rig.Step, V(0.53, 0.16, 1.12), C(-2.67, 2.08, -0.49))
    for _, side in { "Left", "Right" } do
        local x = if side == "Left" then -2.08 else -0.38
        resize(rig[side .. " Work Light Housing"], V(0.54, 0.33, 0.39), C(x, 6.24, -2.58))
        resize(rig[side .. " Work Light"], V(0.37, 0.22, 0.08), C(x, 6.24, -2.81))
    end

    local detail = make("Folder", "DriverControls", rig)
    local world = root.CFrame
    local seat = rig.Seat
    local seatAt = root.CFrame:ToObjectSpace(seat.CFrame)
    local driver = C(seatAt.X, seatAt.Y + seat.Size.Y / 2 + 1.05, -0.68)
    part(
        detail,
        turret,
        "Instrument Rail",
        world * C(-1.23, 3.25, -2.48),
        V(2.36, 0.21, 0.19),
        graphite
    )
    part(
        detail,
        turret,
        "Display",
        world * C(-1.94, 3.44, -2.33) * angles(-27, 0, 0),
        V(0.43, 0.23, 0.095),
        darkSteel
    )
    part(
        detail,
        turret,
        "Instrument Glass",
        world * C(-1.94, 3.47, -2.28) * angles(-27, 0, 0),
        V(0.32, 0.13, 0.03),
        paint(76, 158, 157)
    )
    part(
        detail,
        turret,
        "Floor Tread",
        world * C(-1.13, 2.55, -1.81),
        V(1.70, 0.035, 1.51),
        graphite
    )
    for i = 1, 6 do
        part(
            detail,
            turret,
            "Tread Rib",
            world * C(-1.13, 2.568, -2.42 + i * 0.19),
            V(1.48, 0.018, 0.035),
            darkSteel
        )
    end

    local pivots, grips = {}, {}
    for index, name in { "Left", "Right" } do
        local sign = if index == 1 then -1 else 1
        local x, z = driver.X + sign * 0.78, -1.52
        part(
            detail,
            turret,
            name .. " Control Console",
            world * C(x, 3.12, -1.01),
            V(0.37, 0.22, 1.14),
            graphite
        )
        part(
            detail,
            turret,
            name .. " Console Support",
            world * C(x, 2.84, -1.30),
            V(0.25, 0.6, 0.29),
            darkSteel
        )
        part(
            detail,
            turret,
            name .. " Stick Boot",
            world * C(x, 3.24, z) * angles(0, 0, 90),
            V(0.16, 0.30, 0.30),
            rubber,
            Enum.PartType.Cylinder
        )
        local pivot = part(
            detail,
            turret,
            name .. "Joystick",
            world * C(x, 3.31, z),
            V(0.1, 0.1, 0.1),
            graphite,
            nil,
            true
        )
        pivot.Transparency = 1
        local cap = V(-sign * 0.06, 0.62, -0.08)
        strut(
            detail,
            pivot,
            name .. " Stick Shaft",
            pivot.CFrame.Position,
            pivot.CFrame:PointToWorldSpace(cap),
            0.13,
            darkSteel,
            true
        )
        part(
            detail,
            pivot,
            name .. " Stick Handle",
            pivot.CFrame * C(cap) * angles(0, 7 * sign, 83),
            V(0.32, 0.235, 0.255),
            rubber,
            Enum.PartType.Cylinder
        )
        part(
            detail,
            pivot,
            name .. " Thumb Button",
            pivot.CFrame * C(cap + V(-sign * 0.047, 0.158, -0.034)),
            V(0.091, 0.037, 0.087),
            orange
        )
        pivots[index] = pivot
        grips[index] = attachment(
            pivot,
            "Driver" .. name .. "Grip",
            C(cap + V(sign * 0.087, 0.035, 0.031)) * angles(-17, 0, -sign * 10)
        )
    end
    return driver, pivots, grips
end

local function harvester(rig: Model, root: BasePart): (CFrame, { BasePart }, { Attachment })
    local detail = make("Folder", "DriverControls", rig)
    local world = root.CFrame
    local seat = rig["Cab Seat"]
    local seatAt = root.CFrame:ToObjectSpace(seat.CFrame)
    local driver = C(seatAt.X, seatAt.Y + seat.Size.Y / 2 + 1.05, -0.88)
    local wheelFrame = world * C(driver.X, 9.02, -1.94) * angles(-15, 0, 0)
    local rimRadius = 0.66
    local pivot =
        part(detail, root, "SteeringWheel", wheelFrame, V(0.1, 0.1, 0.1), graphite, nil, true)
    pivot.Transparency = 1
    strut(
        detail,
        root,
        "Steering Column",
        (world * C(driver.X, 8.19, -2.63)).Position,
        (wheelFrame * C(0, 0, -0.10)).Position,
        0.24,
        graphite,
        true
    )
    local function rimPoint(a: number): Vector3
        return wheelFrame:PointToWorldSpace(V(rimRadius * math.cos(a), rimRadius * math.sin(a), 0))
    end
    for i = 1, 16 do
        local a, b = 2 * math.pi * (i - 1) / 16, 2 * math.pi * i / 16
        strut(
            detail,
            pivot,
            "Steering Rim",
            rimPoint(a - 0.025),
            rimPoint(b + 0.025),
            0.14,
            rubber,
            true
        )
        part(
            detail,
            pivot,
            "Steering Rim Seam",
            C(rimPoint(a)),
            V(0.14, 0.14, 0.14),
            rubber,
            Enum.PartType.Ball
        )
    end
    for _, a in { math.rad(22), math.rad(158), math.rad(270) } do
        strut(detail, pivot, "Steering Spoke", wheelFrame.Position, rimPoint(a), 0.105, darkSteel)
    end
    part(
        detail,
        pivot,
        "Steering Hub",
        wheelFrame * angles(0, 90, 0),
        V(0.16, 0.31, 0.31),
        graphite,
        Enum.PartType.Cylinder
    )
    part(
        detail,
        pivot,
        "Steering Hub Cap",
        wheelFrame * C(0, 0, 0.081) * angles(0, 90, 0),
        V(0.037, 0.11, 0.11),
        gold,
        Enum.PartType.Cylinder
    )
    part(
        detail,
        root,
        "Instrument Console",
        world * C(driver.X, 8.44, -2.79) * angles(32, 0, 0),
        V(1.60, 0.40, 0.18),
        graphite
    )
    for i = 1, 3 do
        part(
            detail,
            root,
            "Instrument Dial",
            world * C(driver.X + (i - 2) * 0.43, 8.50, -2.70) * angles(32, 0, 0) * angles(0, 90, 0),
            V(0.07, 0.23, 0.23),
            if i == 2 then gold else paint(96, 169, 167),
            Enum.PartType.Cylinder
        )
    end
    local grips = {}
    for index, name in { "Left", "Right" } do
        local sign = if index == 1 then -1 else 1
        grips[index] = attachment(
            pivot,
            "Driver" .. name .. "Grip",
            C(sign * rimRadius, 0.055, 0.048) * angles(-32, 0, -sign * 16)
        )
    end
    return driver, { pivot }, grips
end

local function clip(
    parent: Instance,
    name: string,
    priority: Enum.AnimationPriority
): KeyframeSequence
    local motion = make("KeyframeSequence", name, parent)
    motion.Loop, motion.Priority = true, priority
    return motion
end

local function pose(parent: Instance, name: string, offset: CFrame, weight: number?): Pose
    local channel = make("Pose", name, parent)
    channel.CFrame = offset
    channel.Weight = weight or 1
    channel.EasingStyle = Enum.PoseEasingStyle.Linear
    return channel
end

local function key(motion: KeyframeSequence, time: number, rootName: string): Pose
    local frame = make("Keyframe", "Keyframe", motion)
    frame.Time = time
    return pose(frame, rootName, I, 0)
end

local function keyframes(motion: KeyframeSequence): { Keyframe }
    local frames = motion:GetChildren() :: { Keyframe }
    table.sort(frames, function(a, b)
        return a.Time < b.Time
    end)
    return frames
end

-- t, left fore/aft, left sideways, right fore/aft, right sideways.
local joystickBeats = {
    { 0, 0, 0, 0, 0 },
    { 0.28, 12, 0, 7, 0 },
    { 0.55, 9, 0, -6, -3 },
    { 0.76, -10, 0, -10, -5 },
    { 1.08, -12, 0, -5, -2 },
    { 1.34, -8, 8, 3, 0 },
    { 1.71, -3, 10, 1, 0 },
    { 1.93, 0, 5, 3, 0 },
    { 2.16, 2, 0, 10, 7 },
    { 2.36, 1, 0, 7, 4 },
    { 2.53, 6, -9, -4, 1 },
    { 2.76, 8, -8, -5, 0 },
    { 2.99, 4, -4, -6, 0 },
    { 3.24, 0, 0, 0, 0 },
}

local function joystickPose(index: number, t: number): CFrame
    for i = 2, #joystickBeats do
        local a, b = joystickBeats[i - 1], joystickBeats[i]
        if t <= b[1] then
            local f = (t - a[1]) / (b[1] - a[1])
            local eased = f * f * (3 - 2 * f)
            local pitch, roll = index * 2, index * 2 + 1
            return angles(
                a[pitch] + (b[pitch] - a[pitch]) * eased,
                0,
                a[roll] + (b[roll] - a[roll]) * eased
            )
        end
    end
    return I
end

type Joint = { base: CFrame, tip: CFrame }
type JointMaker = (number, number, number, number) -> Joint
type LimbSolver = (CFrame, Joint, Joint, Joint, CFrame, Vector3) -> (CFrame, CFrame, CFrame, number)

local function advance(frame: CFrame, joint: Joint, transform: CFrame): CFrame
    return frame * joint.base * transform * joint.tip:Inverse()
end

local function driverClips(
    rig: Model,
    root: BasePart,
    anchor: BasePart,
    driver: CFrame,
    pivots: { BasePart },
    grips: { Attachment },
    joint: JointMaker,
    solve: LimbSolver,
    isExcavator: boolean
)
    local driverWorld = root.CFrame * driver
    attachment(anchor, "DriverRoot", anchor.CFrame:ToObjectSpace(driverWorld))
    local group = make("Folder", "DriverAnimations", rig)
    local hold = clip(group, "DriverIdle", Enum.AnimationPriority.Action)
    local act = clip(
        group,
        if isExcavator then "DriverWork" else "DriverSteer",
        Enum.AnimationPriority.Action
    )
    local controls: KeyframeSequence
    local workKeys: { Keyframe } = {}
    if isExcavator then
        -- Keep the turret, arm and sand cues on one track with the joysticks.
        controls = rig.Animations.WorkLoop:Clone()
        controls.Name, controls.Parent = "WorkWithJoysticks", group
        workKeys = keyframes(controls)
    else
        controls = clip(group, "SteeringTurn", Enum.AnimationPriority.Action)
    end
    local pelvis, waist = joint(0, -1, 0, -0.20025), joint(0, 0.20030, 0, -0.84900)
    local neck = joint(0, 0.63, 0, -0.52)
    local maxGripError, maxFootError, maxHead = 0, 0, 0
    local duration = if isExcavator then workKeys[#workKeys].Time else 2.4

    local function animate(motion: KeyframeSequence, operating: boolean)
        local adoptsWorkKeys = isExcavator and operating
        local frameCount = if adoptsWorkKeys then #workKeys - 1 else math.round(duration * 30)
        for i = 0, frameCount do
            local time = if adoptsWorkKeys then workKeys[i + 1].Time else duration * i / frameCount
            local phase = if i == frameCount then 0 else 2 * math.pi * time / duration
            local sway = math.sin(phase)
            local smaller = math.sin(2 * phase)
            local rotation = {}
            for index in pivots do
                rotation[index] = if not operating
                    then I
                    elseif not isExcavator then angles(0, 0, -16 * sway)
                    elseif i == frameCount then I
                    else joystickPose(index, time)
            end
            if operating then
                local mountChannel = if adoptsWorkKeys
                    then workKeys[i + 1].Root.Turret
                    else key(controls, time, "Root")
                for index, pivot in pivots do
                    pose(mountChannel, pivot.Name, rotation[index])
                end
            end
            local rootChannel = key(motion, time, "HumanoidRootPart")
            local hipMotion = angles(-8, 0, 0)
            local torsoMotion = angles(
                -5 - (if operating then 1.1 else 0.8) * smaller,
                (if operating then 3.5 else 1.2) * sway,
                (if operating then -2 else 1) * sway
            )
            local headMotion =
                angles(8 + 1.55 * smaller, (if operating then -7 else 5) * sway, sway)
            local hips = advance(driverWorld, pelvis, hipMotion)
            local chest = advance(hips, waist, torsoMotion)
            local head = advance(chest, neck, headMotion)
            local localHead = root.CFrame:ToObjectSpace(head)
            local top = localHead.Y
                + 0.5 * math.abs(localHead.UpVector.Y)
                + 0.5 * math.abs(localHead.RightVector.Y)
                + 0.5 * math.abs(localHead.LookVector.Y)
            maxHead = math.max(maxHead, top)
            local lowerPose = pose(rootChannel, "LowerTorso", hipMotion)
            local chestPose = pose(lowerPose, "UpperTorso", torsoMotion)
            pose(chestPose, "Head", headMotion)
            for index, side in { "Left", "Right" } do
                local sign = if index == 1 then -1 else 1
                local grip = grips[index]
                local pivotIndex = if isExcavator then index else 1
                local target = pivots[pivotIndex].CFrame * rotation[pivotIndex] * grip.CFrame
                local a, b, c, gripError = solve(
                    chest,
                    joint(0.97160 * sign, 0.59751, -0.50053 * sign, 0.41892),
                    joint(0, -0.35501, 0, 0.27471),
                    joint(0, -0.53217, 0, 0.13157),
                    target,
                    V(0.35 * sign, -1, 0.45)
                )
                maxGripError = math.max(maxGripError, gripError)
                pose(
                    pose(pose(chestPose, side .. "UpperArm", a), side .. "LowerArm", b),
                    side .. "Hand",
                    c
                )

                local foot = root.CFrame
                    * C(
                        driver.X + 0.48 * sign,
                        if isExcavator then 2.725 else 7.285,
                        if isExcavator then -2.12 else -2.11 + 0.045 * sign
                    )
                local d, e, f, footError = solve(
                    hips,
                    joint(0.49785 * sign, -0.20025, 0, 0.47139),
                    joint(0, -0.44926, 0, 0.41327),
                    joint(0, -0.59649, 0, 0.10602),
                    foot,
                    V(0.12 * sign, 0.95, -0.4)
                )
                maxFootError = math.max(maxFootError, footError)
                pose(
                    pose(pose(lowerPose, side .. "UpperLeg", d), side .. "LowerLeg", e),
                    side .. "Foot",
                    f
                )
            end
        end
    end
    animate(hold, false)
    animate(act, true)
    local roof = if isExcavator then rig["Cab Canopy"] else rig["Raised Cab Roof"]
    local clearance = root.CFrame:ToObjectSpace(roof.CFrame).Y - roof.Size.Y / 2 - maxHead
    print(
        rig.Name,
        "grip error",
        maxGripError,
        "foot error",
        maxFootError,
        "roof clearance",
        clearance
    )
    assert(
        maxGripError < 0.01 and maxFootError < 0.01 and clearance > 0.07,
        rig.Name .. " driver fit"
    )
    group:SetAttribute("DurationSeconds", duration)
    group:SetAttribute("RoofClearanceStuds", clearance)
end

return function(joint: JointMaker, solve: LimbSolver)
    local base = rbx.deserializeModel(
        fs.readFile("assets/models/equipment_sand_fx/DuneBaron_Equipment_SandFX.rbxm")
    )[1]
    local bundle = make("Folder", "DuneBaron_DriverCabs")
    for _, name in { "mini_digger", "mega_machine" } do
        local rig = base[name]:Clone()
        rig.Parent = bundle
        local root = rig.Root
        local isExcavator = name == "mini_digger"
        local anchor = if isExcavator then rig.Turret else root
        local driver, pivots, grips
        if isExcavator then
            driver, pivots, grips = excavator(rig, root, anchor)
        else
            driver, pivots, grips = harvester(rig, root)
        end
        driverClips(rig, root, anchor, driver, pivots, grips, joint, solve, isExcavator)
    end
    local bytes = rbx.serializeModel({ bundle })
    local restored = rbx.deserializeModel(bytes)[1]
    for _, rig in restored:GetChildren() do
        local isExcavator = rig.Name == "mini_digger"
        local original = base[rig.Name]
        assert(rig.PrimaryPart == rig.Root and rig.Root.Anchored)
        assert(rig.SandEffects.Source == original.SandEffects.Source)
        assert(#rig.Animations:GetChildren() == #original.Animations:GetChildren())
        assert(#rig.DriverAnimations:GetChildren() == 3)
        assert(rig:FindFirstChild("DriverMount", true) and rig:FindFirstChild("DriverRoot", true))
        assert(
            rig:FindFirstChild("DriverLeftGrip", true)
                and rig:FindFirstChild("DriverRightGrip", true)
        )
        for _, motion in rig.DriverAnimations:GetChildren() do
            local frames = keyframes(motion)
            local first, last = frames[1], frames[#frames]
            assert(motion.Loop and first.Time == 0)
            assert(
                math.abs(last.Time - rig.DriverAnimations:GetAttribute("DurationSeconds")) < 0.001
            )
            for _, channel in first:GetDescendants() do
                assert(
                    channel:IsA("Pose")
                        and channel.CFrame == last:FindFirstChild(channel.Name, true).CFrame
                )
            end
        end
        local controlParts = 0
        for _, instance in rig.DriverControls:GetDescendants() do
            if instance:IsA("Motor6D") then
                assert(instance.Part0 == (if isExcavator then rig.Turret else rig.Root))
                assert(instance.Part1 and instance.Part1:IsDescendantOf(rig.DriverControls))
                controlParts += 1
            end
        end
        assert(controlParts == (if isExcavator then 2 else 1))
    end
    local path = "assets/models/driver_cabs/DuneBaron_DriverCabs.rbxm"
    fs.writeFile(path, bytes)
    print(path, "2 rigs and 6 looping clips")
end
