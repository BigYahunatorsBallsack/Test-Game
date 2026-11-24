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
        { { 33, 75, 43, 68 }, { 65, 75, 55, 68 }, { 43, 68, 55, 68 } },
    },
    shovel = {
        { { 54, 50, 49, 62, 48, 79 } },
        { { 43, 30, 46, 46, 49, 68, 51, 86 }, { 43, 52, 48, 55, 54, 51 } },
        { { 41, 74, 56, 57, 72, 41, 89, 28 } },
        { { 36, 79, 49, 69 }, { 49, 69, 68, 53 } },
    },
    bucket_chain = {
        { { 28, 74, 42, 55, 67, 40 }, { 36, 73, 50, 54, 73, 40 } },
        { { 21, 25, 28, 38, 31, 54 }, { 91, 25, 86, 40, 80, 53 }, { 51, 76, 65, 45, 71, 21 } },
        { { 62, 25, 77, 24, 87, 34, 88, 48, 77, 56, 56, 60, 29, 62 } },
        { { 30, 71, 64, 44 }, { 43, 63, 70, 43 }, { 70, 43, 75, 62 } },
    },
    mini_digger = {
        { { 35, 70, 47, 74, 63, 66 } },
        { { 68, 51, 55, 61, 40, 66, 25, 61, 16, 51 }, { 62, 55, 45, 60, 32, 59 } },
        { { 63, 45, 60, 55, 56, 58 }, { 44, 57, 35, 61, 32, 73, 32, 79 } },
        { { 32, 63, 52, 68, 66, 61 }, { 33, 74, 52, 79, 67, 72 } },
    },
    vacuum_robot = {
        { { 58, 77, 70, 74, 71, 68, 63, 66, 58, 69, 62, 72, 66, 70 } },
        { { 8, 84, 20, 67, 34, 47 }, { 38, 87, 47, 67, 54, 50 } },
        { { 55, 66, 55, 76, 53, 91 }, { 55, 57, 59, 58, 61, 52 } },
        { { 38, 79, 60, 72, 65, 66 }, { 55, 82, 65, 77, 68, 70 } },
    },
    mega_machine = {
        { { 25, 76, 47, 66, 68, 65, 73, 58 } },
        { { 24, 49, 35, 34, 44, 22 }, { 77, 49, 63, 34, 56, 22 } },
        { { 47, 24, 56, 30, 62, 40, 66, 52, 69, 58 } },
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
