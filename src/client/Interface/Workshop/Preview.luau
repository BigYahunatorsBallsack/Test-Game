--!strict
-- Each stroke describes an action in the illustrated first-person view. Coordinates are
-- fractions of the preview. Variants change the shape and timing of the demonstration.
local RunService = game:GetService("RunService")
local Art = require(script.Parent.Art)
local Preview = {}
local tracks = {
    hand = {
        { { 47, 74, 56, 65 } },
        { { 61, 43, 72, 34, 88, 23, 97, 15 }, { 34, 76, 47, 73, 64, 71 } },
        { { 48, 59, 49, 71, 50, 89 }, { 43, 58, 50, 61, 55, 56 } },
        { { 24, 61, 30, 55, 40, 54, 45, 61, 39, 67 }, { 56, 64, 65, 59, 74, 61, 78, 67, 69, 70 } },
    },
    shovel = {
        { { 54, 50, 49, 62, 48, 79 } },
        { { 43, 30, 46, 46, 49, 68, 51, 86 }, { 43, 52, 48, 55, 54, 51 } },
        { { 41, 74, 56, 57, 72, 41, 89, 28 } },
        { { 8, 29, 28, 41, 43, 54, 54, 65 }, { 54, 65, 61, 75, 73, 85, 83, 92 } },
    },
    bucket_chain = {
        { { 28, 74, 42, 55, 67, 40 }, { 36, 73, 50, 54, 73, 40 } },
        { { 21, 25, 28, 38, 31, 54 }, { 91, 25, 86, 40, 80, 53 }, { 51, 76, 65, 45, 71, 21 } },
        { { 62, 25, 77, 24, 87, 34, 88, 48, 77, 56, 56, 60, 29, 62 } },
        { { 29, 28, 44, 14, 60, 15, 75, 21 }, { 79, 33, 82, 43, 85, 53, 85, 62 } },
    },
    mini_digger = {
        { { 35, 70, 47, 74, 63, 66 } },
        { { 68, 51, 55, 61, 40, 66, 25, 61, 16, 51 }, { 62, 55, 45, 60, 32, 59 } },
        { { 63, 45, 60, 55, 56, 58 }, { 44, 57, 35, 61, 32, 73, 32, 79 } },
        { { 23, 32, 31, 39, 40, 47, 47, 56 }, { 47, 56, 52, 61, 58, 65, 64, 69 } },
    },
    vacuum_robot = {
        { { 58, 77, 70, 74, 71, 68, 63, 66, 58, 69, 62, 72, 66, 70 } },
        { { 8, 84, 20, 67, 34, 47 }, { 38, 87, 47, 67, 54, 50 } },
        { { 55, 66, 55, 76, 53, 91 }, { 55, 57, 59, 58, 61, 52 } },
        { { 31, 63, 43, 58, 54, 55, 66, 53 }, { 94, 78, 82, 70, 74, 62, 66, 53 } },
    },
    mega_machine = {
        { { 25, 76, 47, 66, 68, 65, 73, 58 } },
        { { 24, 49, 35, 34, 44, 22 }, { 77, 49, 63, 34, 56, 22 } },
        { { 47, 24, 56, 30, 62, 40, 66, 52, 69, 58 } },
        { { 69, 47, 77, 42, 83, 31, 88, 25 }, { 33, 55, 36, 41, 39, 29, 43, 18 } },
    },
}
local durations = {
    hand = 2.4,
    shovel = 2.6,
    bucket_chain = 3.2,
    mini_digger = 3.2,
    vacuum_robot = 2.8,
    mega_machine = 3.6,
}
local masteryCues = {
    hand = { "Erste Probe", "Zweite Probe" },
    shovel = { "Erster Schnitt", "Rinne fortsetzen" },
    bucket_chain = { "Eimer zum Auslauf", "Wartende Eimer entleeren" },
    mini_digger = { "Erster Hub", "Zweiter Hub" },
    vacuum_robot = { "Erster Sog", "Restsand einziehen" },
    mega_machine = { "Sand übergeben", "Walzen laufen weiter" },
}

function Preview.new(container)
    local layer = Art.box(container, "Ablauf", nil, container.ZIndex + 2)
    layer.Size = UDim2.fromScale(1, 1)
    local connection
    local redraw: (() -> ())? = nil
    local function clear()
        redraw = nil
        if connection then
            connection:Disconnect()
            connection = nil
        end
        layer:ClearAllChildren()
    end
    layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if redraw then
            redraw()
        end
    end)
    layer.Destroying:Connect(clear)
    local function show(device, variant, reduced, accent: Color3?)
        clear()
        if not tracks[device] then
            return
        end
        local strokes = tracks[device][variant]
        local cues = if variant == 4 then masteryCues[device] else nil
        local parts = {}
        for i, points in strokes do
            for p = 1, #points - 2, 2 do
                local a = Vector2.new(points[p] / 100, points[p + 1] / 100)
                local b = Vector2.new(points[p + 2] / 100, points[p + 3] / 100)
                local v = Art.box(
                    layer,
                    "Spur",
                    if i % 2 == 1 then accent or Art.c.bright else Art.c.leaf,
                    layer.ZIndex + 1
                )
                v.AnchorPoint = Vector2.new(0, 0.5)
                Art.round(v, 2)
                table.insert(parts, {
                    a = a,
                    b = b,
                    obj = v,
                    stroke = i,
                    rank = (p + 1) / 2,
                    size = (#points - 2) / 2,
                })
            end
        end
        local tip = Art.box(layer, "Kontakt", accent or Art.c.bright, layer.ZIndex + 2)
        tip.AnchorPoint = Vector2.new(0.5, 0.5)
        tip.Size = UDim2.fromOffset(9, 9)
        Art.round(tip, 6)
        Art.edge(tip, Art.c.dark)
        local stepLabel: TextLabel? = nil
        local currentStep = 0
        if cues then
            local badge = Art.box(layer, "Meisterschaftsschritt", Art.c.ink, layer.ZIndex + 3)
            badge.Position = UDim2.fromOffset(6, 6)
            local badgeHeight = if reduced then 34 else 23
            badge.Size = UDim2.new(1, -12, 0, badgeHeight)
            local badgeSize = Instance.new("UISizeConstraint")
            badgeSize.MaxSize = Vector2.new(229, badgeHeight)
            badgeSize.Parent = badge
            badge.BackgroundTransparency = 0.18
            Art.round(badge, 4)
            stepLabel = Art.text(badge, "Phase", "", 11, Art.c.ivory, true)
            stepLabel.Position = UDim2.fromOffset(7, 0)
            stepLabel.Size = UDim2.new(1, -14, 1, 0)
            if reduced then
                stepLabel.Text = cues[1] .. " → " .. cues[2]
            end
        end
        local function draw(t)
            local size = layer.AbsoluteSize
            for j, part in parts do
                local phase = if cues then math.clamp(t * 2 - part.stroke + 1, 0, 1) else nil
                local fraction = math.clamp(
                    if phase then phase * part.size - part.rank + 1 else t * #parts - j + 1,
                    0,
                    1
                )
                local a = part.a * size
                local v = (part.b - part.a) * size
                local center = a + v * fraction * 0.5
                part.obj.AnchorPoint = Vector2.new(0.5, 0.5)
                part.obj.Position = UDim2.fromOffset(center.X, center.Y)
                part.obj.Rotation = math.deg(math.atan2(v.Y, v.X))
                part.obj.Size = UDim2.fromOffset(v.Magnitude * fraction, 3)
                part.obj.Visible = fraction > 0
                if fraction > 0 then
                    local endPt = a + v * fraction
                    tip.Position = UDim2.fromOffset(endPt.X, endPt.Y)
                end
            end
            tip.Visible = t > 0
            if stepLabel and cues and not reduced then
                local step = if t < 0.5 then 1 else 2
                if step ~= currentStep then
                    currentStep = step
                    stepLabel.Text = step .. " / 2   ·   " .. cues[step]
                    stepLabel.TextColor3 = if step == 1 then Art.c.bright else Art.c.leaf
                end
            end
        end
        local progress = if reduced then 1 else 0
        redraw = function()
            draw(progress)
        end
        draw(progress)
        if reduced then
            return
        end
        local t0 = os.clock()
        connection = RunService.Heartbeat:Connect(function()
            local t = math.min(1, (os.clock() - t0) / durations[device])
            progress = t * t * (3 - 2 * t)
            draw(progress)
            if t >= 1 then
                connection:Disconnect()
                connection = nil
            end
        end)
    end
    return { show = show, clear = clear }
end
return Preview
