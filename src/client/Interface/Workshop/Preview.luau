--!strict
-- Each stroke describes an action in the illustrated first-person view. Coordinates are
-- fractions of the preview. Variants change the shape and timing of the demonstration.
local RunService = game:GetService("RunService")
local Art = require(script.Parent.Art)
local Preview = {}
local tracks = {
    hand = {
        { { 47, 74, 56, 65 } },
        { { 43, 71, 64, 55 }, { 58, 57, 64, 55, 63, 61 } },
        { { 40, 60, 52, 75, 63, 61 }, { 44, 71, 59, 71 } },
        { { 33, 75, 43, 68 }, { 65, 75, 55, 68 }, { 43, 68, 55, 68 } },
    },
    shovel = {
        { { 54, 50, 49, 62, 48, 79 } },
        { { 49, 51, 46, 65, 46, 80 }, { 46, 73, 59, 67 } },
        { { 37, 78, 48, 68, 65, 54 } },
        { { 36, 79, 49, 69 }, { 49, 69, 68, 53 } },
    },
    bucket_chain = {
        { { 28, 74, 42, 55, 67, 40 }, { 36, 73, 50, 54, 73, 40 } },
        { { 24, 64, 40, 71 }, { 63, 62, 40, 71 }, { 40, 71, 67, 42 } },
        { { 29, 72, 69, 40, 74, 52, 42, 76 } },
        { { 30, 71, 64, 44 }, { 43, 63, 70, 43 }, { 70, 43, 75, 62 } },
    },
    mini_digger = {
        { { 35, 70, 47, 74, 63, 66 } },
        { { 25, 68, 38, 74, 56, 74, 71, 64 }, { 26, 71, 40, 78, 57, 77, 71, 68 } },
        { { 45, 58, 48, 67, 52, 70 }, { 50, 72, 56, 72 } },
        { { 32, 63, 52, 68, 66, 61 }, { 33, 74, 52, 79, 67, 72 } },
    },
    vacuum_robot = {
        { { 58, 77, 70, 74, 71, 68, 63, 66, 58, 69, 62, 72, 66, 70 } },
        { { 39, 75, 63, 69 }, { 67, 85, 64, 70 } },
        { { 42, 76, 59, 71, 67, 66 }, { 66, 66, 61, 56 } },
        { { 38, 79, 60, 72, 65, 66 }, { 55, 82, 65, 77, 68, 70 } },
    },
    mega_machine = {
        { { 25, 76, 47, 66, 68, 65, 73, 58 } },
        { { 26, 78, 32, 54 }, { 69, 78, 61, 54 } },
        { { 38, 74, 57, 69, 76, 70, 86, 61 } },
        { { 34, 77, 45, 62, 51, 56 }, { 50, 69, 59, 57, 61, 49 } },
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
                table.insert(parts, { a = a, b = b, obj = v })
            end
        end
        local tip = Art.box(layer, "Kontakt", accent or Art.c.bright, layer.ZIndex + 2)
        tip.AnchorPoint = Vector2.new(0.5, 0.5)
        tip.Size = UDim2.fromOffset(9, 9)
        Art.round(tip, 6)
        Art.edge(tip, Art.c.dark)
        local function draw(t)
            local size = layer.AbsoluteSize
            for j, part in parts do
                local fraction = math.clamp(t * #parts - j + 1, 0, 1)
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
