--!strict
-- Kamera des Baums (Paket 2.2): Zoom, Verschieben, Tippen oder Ziehen. Rein, ohne Roblox-API,
-- Lune-Tests in tests/treecamera.spec.luau. Der Controller liest die Eingaben und übergibt nur
-- Zahlen.
--
-- Bildschirm = pan + Welt * zoom (je Achse). `area` ist die Baumfläche aus Logic/TreeLayout
-- (Weltkoordinaten), `viewport` die Größe des Fensters in Pixeln.

local DefaultConfig = require("../Data/TreeLayout")

export type Camera = { zoom: number, panX: number, panY: number }
export type Viewport = { width: number, height: number }
export type Area = { minX: number, minY: number, maxX: number, maxY: number }
export type Point = { x: number, y: number }

local TreeCamera = {}

function TreeCamera.clampZoom(zoom: number, config: any?): number
    local cfg: any = config or DefaultConfig
    if zoom ~= zoom then
        return cfg.zoom.start
    end
    return math.clamp(zoom, cfg.zoom.min, cfg.zoom.max)
end

-- Eine Achse: Passt der Baum ins Fenster, steht er mittig, sonst bleibt er so im Fenster, dass
-- man ihn nie ganz aus dem Bild schieben kann.
local function clampAxis(pan: number, zoom: number, size: number, lo: number, hi: number): number
    if (hi - lo) * zoom <= size then
        return size / 2 - (lo + hi) / 2 * zoom
    end
    return math.clamp(pan, size - hi * zoom, -lo * zoom)
end

function TreeCamera.clamp(camera: Camera, viewport: Viewport, area: Area, config: any?): Camera
    local zoom = TreeCamera.clampZoom(camera.zoom, config)
    return {
        zoom = zoom,
        panX = clampAxis(camera.panX, zoom, viewport.width, area.minX, area.maxX),
        panY = clampAxis(camera.panY, zoom, viewport.height, area.minY, area.maxY),
    }
end

-- Bildschirmpunkt -> Weltpunkt und zurück.
function TreeCamera.toWorld(camera: Camera, screen: Point): Point
    return { x = (screen.x - camera.panX) / camera.zoom, y = (screen.y - camera.panY) / camera.zoom }
end

function TreeCamera.toScreen(camera: Camera, world: Point): Point
    return { x = camera.panX + world.x * camera.zoom, y = camera.panY + world.y * camera.zoom }
end

-- Zoom um einen Bildschirmpunkt: Der Weltpunkt darunter bleibt stehen (soweit der Rand es
-- erlaubt).
function TreeCamera.zoomAt(camera: Camera, factor: number, anchor: Point, viewport: Viewport, area: Area, config: any?): Camera
    local zoom = TreeCamera.clampZoom(camera.zoom * factor, config)
    local world = TreeCamera.toWorld(camera, anchor)
    return TreeCamera.clamp({
        zoom = zoom,
        panX = anchor.x - world.x * zoom,
        panY = anchor.y - world.y * zoom,
    }, viewport, area, config)
end

-- Zwei-Finger-Geste: Der Weltpunkt unter der alten Fingermitte folgt der neuen Fingermitte,
-- der Abstand der Finger bestimmt den Zoom.
function TreeCamera.pinch(camera: Camera, oldA: Point, oldB: Point, newA: Point, newB: Point, viewport: Viewport, area: Area, config: any?): Camera
    local oldDistance = math.sqrt((oldA.x - oldB.x) ^ 2 + (oldA.y - oldB.y) ^ 2)
    local newDistance = math.sqrt((newA.x - newB.x) ^ 2 + (newA.y - newB.y) ^ 2)
    if oldDistance < 1 then
        return TreeCamera.clamp(camera, viewport, area, config)
    end
    local oldMid = { x = (oldA.x + oldB.x) / 2, y = (oldA.y + oldB.y) / 2 }
    local newMid = { x = (newA.x + newB.x) / 2, y = (newA.y + newB.y) / 2 }
    local zoom = TreeCamera.clampZoom(camera.zoom * newDistance / oldDistance, config)
    local world = TreeCamera.toWorld(camera, oldMid)
    return TreeCamera.clamp({
        zoom = zoom,
        panX = newMid.x - world.x * zoom,
        panY = newMid.y - world.y * zoom,
    }, viewport, area, config)
end

function TreeCamera.drag(camera: Camera, dx: number, dy: number, viewport: Viewport, area: Area, config: any?): Camera
    return TreeCamera.clamp({ zoom = camera.zoom, panX = camera.panX + dx, panY = camera.panY + dy }, viewport, area, config)
end

-- Setzt einen Weltpunkt in die Bildmitte, soweit der Rand es erlaubt.
function TreeCamera.centerOn(camera: Camera, world: Point, viewport: Viewport, area: Area, config: any?): Camera
    local zoom = TreeCamera.clampZoom(camera.zoom, config)
    return TreeCamera.clamp({
        zoom = zoom,
        panX = viewport.width / 2 - world.x * zoom,
        panY = viewport.height / 2 - world.y * zoom,
    }, viewport, area, config)
end

-- Tippen oder Ziehen: Eine Berührung, die sich höchstens um die Schwelle bewegt hat, ist ein
-- Tippen. Erst bei mehr Bewegung gilt sie als Ziehen (und öffnet keine Karte).
function TreeCamera.isTap(movedPixels: number, config: any?): boolean
    local cfg: any = config or DefaultConfig
    return movedPixels < cfg.tapMaxMovePixels
end

-- Kantenlänge eines Knotens auf dem Bildschirm.
function TreeCamera.nodePixels(zoom: number, config: any?): number
    local cfg: any = config or DefaultConfig
    return cfg.nodeSize * zoom
end

-- Welcher Knoten liegt am Weltpunkt? Nimmt den mit dem kleinsten Abstand zur Mitte, wenn sich
-- Rahmen überlappen. `positions`: ID -> Mittelpunkt in Weltkoordinaten.
function TreeCamera.hitTest(positions: { [string]: Point }, world: Point, config: any?): string?
    local cfg: any = config or DefaultConfig
    local half = cfg.nodeSize / 2
    local best: string? = nil
    local bestDistance = math.huge
    for id, position in positions do
        local dx, dy = math.abs(world.x - position.x), math.abs(world.y - position.y)
        if dx <= half and dy <= half then
            local distance = dx * dx + dy * dy
            if distance < bestDistance or (distance == bestDistance and best ~= nil and id < (best :: string)) then
                best = id
                bestDistance = distance
            end
        end
    end
    return best
end

return TreeCamera
