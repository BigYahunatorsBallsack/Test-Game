--!strict
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Art = require(script.Parent.Art)
local C = Art.c

local UnlockFX = {}
local NOTICE_TIME = 3.4
local SHORT = 0.34
local MAJOR = 0.65
local TRACE = 0.42

function UnlockFX.mount(mapWrap, sheet)
    local notice = Art.box(mapWrap, "Freischaltmeldung", C.ink, 126)
    notice.AnchorPoint = Vector2.new(0.5, 1)
    notice.Position = UDim2.new(0.5, 0, 1, -12)
    notice.Size = UDim2.new(1, -24, 0, 66)
    local limit = Instance.new("UISizeConstraint")
    limit.MaxSize = Vector2.new(490, 66)
    limit.Parent = notice
    Art.round(notice, 7)
    local border = Art.edge(notice, C.brass, 2)
    local icon = Art.image(notice, "Motiv")
    Art.rect(icon, 9, 9, 48, 48)
    local title = Art.text(notice, "Upgrade", "", 16, C.bright, true)
    title.Position = UDim2.fromOffset(66, 4)
    title.Size = UDim2.new(1, -74, 0, 28)
    local nextSteps = Art.text(notice, "NaechsteKnoten", "", 12, C.ivory, false)
    nextSteps.Position = UDim2.fromOffset(66, 32)
    nextSteps.Size = UDim2.new(1, -74, 0, 29)
    notice.Visible = false

    local layer: Frame?
    local hideTask: thread?
    local function clear()
        if hideTask then
            task.cancel(hideTask)
            hideTask = nil
        end
        if layer then
            layer:Destroy()
            layer = nil
        end
        notice.Visible = false
    end
    local function tween(object, duration, goal)
        TweenService:Create(
            object,
            TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            goal
        ):Play()
    end
    local function show(node, nextNodes, localNodes, major, equipped)
        clear()
        local accent = if equipped then C.leaf else C.bright
        border.Color = accent
        Art.nodeIcon(icon, node)
        title.Text = node.name
        title.TextColor3 = accent
        local count = #nextNodes
        if equipped then
            nextSteps.Text = "Variante ausgerüstet"
        elseif count == 0 then
            nextSteps.Text = "Gelernt"
        elseif count <= 2 then
            nextSteps.Text = "Jetzt erreichbar · " .. table.concat(nextNodes, " / ")
        else
            nextSteps.Text = "Gelernt · " .. count .. " weitere Knoten erreichbar"
        end
        notice.Visible = true
        hideTask = task.delay(NOTICE_TIME, function()
            hideTask = nil
            clear()
        end)
        if GuiService.ReducedMotionEnabled then
            return
        end
        local drawing = Art.box(sheet, "Freischalteffekt", nil, 116)
        drawing.Size = UDim2.fromScale(1, 1)
        layer = drawing
        local origin = Vector2.new(node.x, node.y)
        local duration = if major then MAJOR else SHORT
        local diameter = if major then 82 else 55
        local function ring(center, initial, finish, color, seconds)
            local rim = Art.box(drawing, "Ring", nil, drawing.ZIndex + 1)
            rim.AnchorPoint = Vector2.new(0.5, 0.5)
            Art.rect(rim, center.X, center.Y, initial, initial)
            Art.round(rim, 100)
            local glow = Art.edge(rim, color, 3.5)
            tween(rim, seconds, { Size = UDim2.fromOffset(finish, finish) })
            tween(glow, seconds, { Transparency = 1 })
        end
        ring(origin, diameter, diameter + 52, accent, duration)
        if major then
            ring(origin, diameter - 14, diameter + 22, C.brass, duration)
        end
        local particles = if major then 18 else 7
        for i = 1, particles do
            local angle = i * math.pi * 2 / particles
            local direction = Vector2.new(math.cos(angle), math.sin(angle))
            local from = origin + direction * diameter * 0.46
            local to = origin + direction * (diameter / 2 + 16 + (i % 3) * 10)
            local grain = Art.box(
                drawing,
                "Sandkorn",
                if i % 3 == 0 then C.brass else accent,
                drawing.ZIndex + 2
            )
            grain.Rotation = math.deg(angle)
            local size = if major and i % 3 == 0 then 7 else 4
            Art.rect(grain, from.X, from.Y, size, size)
            tween(
                grain,
                duration,
                { Position = UDim2.fromOffset(to.X, to.Y), BackgroundTransparency = 1 }
            )
        end
        for _, other in localNodes do
            local target = Vector2.new(other.x, other.y)
            local direction = target - origin
            local line = Art.line(drawing, origin, target, C.leaf, 6, 109, "Lichtspur")
            local length = direction.Magnitude
            line.Position = UDim2.fromOffset(origin.X, origin.Y)
            line.Size = UDim2.fromOffset(0, 5)
            local midpoint = (origin + target) / 2
            tween(line, TRACE, {
                Size = UDim2.fromOffset(length, 5),
                Position = UDim2.fromOffset(midpoint.X, midpoint.Y),
            })
            task.delay(TRACE, function()
                if layer ~= drawing then
                    return
                end
                tween(line, TRACE, { BackgroundTransparency = 1 })
                ring(target, 50, 75, C.leaf, TRACE)
            end)
        end
        task.delay(math.max(duration, TRACE * 2) + 0.05, function()
            if layer == drawing then
                drawing:Destroy()
                layer = nil
            end
        end)
    end
    sheet.Destroying:Connect(clear)
    return { show = show, clear = clear }
end

return UnlockFX
