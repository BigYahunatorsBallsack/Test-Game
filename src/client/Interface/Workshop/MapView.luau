--!strict
local MapView = {}

function MapView.clampPan(pan: Vector2, content: Vector2, viewport: Vector2): Vector2
    return Vector2.new(
        math.clamp(pan.X, 0, math.max(0, content.X - viewport.X)),
        math.clamp(pan.Y, 0, math.max(0, content.Y - viewport.Y))
    )
end

function MapView.offset(content: Vector2, viewport: Vector2): Vector2
    return Vector2.new(math.max(0, (viewport.X - content.X) / 2), 0)
end

function MapView.worldAt(point: Vector2, pan: Vector2, offset: Vector2, scale: number): Vector2
    return (point + pan - offset) / math.max(0.01, scale)
end

function MapView.panAt(
    world: Vector2,
    anchor: Vector2,
    content: Vector2,
    viewport: Vector2,
    scale: number
): Vector2
    return MapView.clampPan(
        world * scale + MapView.offset(content, viewport) - anchor,
        content,
        viewport
    )
end

type Point = { id: string, x: number, y: number }

function MapView.neighbor(nodes: { Point }, origin: Point, direction: Vector2): string?
    local best: string? = nil
    local bestScore = math.huge
    for _, node in nodes do
        local delta = Vector2.new(node.x - origin.x, node.y - origin.y)
        local forward = delta:Dot(direction)
        if forward > 0 then
            local sideways = math.abs(delta.X * direction.Y - delta.Y * direction.X)
            -- Prefer the current lane before skipping diagonally across the board.
            local score = delta.Magnitude + sideways * 2
            if score < bestScore then
                bestScore = score
                best = node.id
            end
        end
    end
    return best
end

return MapView
