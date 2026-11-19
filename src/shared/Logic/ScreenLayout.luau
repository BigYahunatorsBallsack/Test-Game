--!strict
-- Plätze der Oberfläche am kleinen und am großen Bildschirm (Paket 3.6). Rein, ohne Roblox-API,
-- Lune-Tests in tests/screenlayout.spec.luau. Die Zahlen stehen in Data/Screen, der Controller
-- Screen liest die Bildschirmgröße und zeichnet nur.
--
-- Alle Rechtecke sind Pixel auf der sicheren Fläche: x, y = obere linke Ecke, w, h = Größe.

local DefaultConfig = require("../Data/Screen")

export type Rect = { x: number, y: number, w: number, h: number }
export type Viewport = { width: number, height: number }
export type Layout = {
    class: string,
    touch: boolean,
    menuMode: string, -- "column" (rechts unter dem Baum-Knopf) oder "row" (unten links)
    viewport: Viewport,
    hud: Rect, -- Panel mit Münzen und Tank
    hudStack: Rect, -- Panel samt Textzeilen darunter
    hudBottom: number,
    treeButton: Rect,
    banner: Rect, -- Tutorial-Banner
    menu: { Rect }, -- ein Rechteck je Menü-Knopf, in der übergebenen Reihenfolge
    dig: Rect?, -- Graben-Knopf (nur Touch)
    jump: Rect?, -- Zone des Sprungknopfs (nur Touch)
}

local ScreenLayout = {}

local function finite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Größe bereinigen: kaputte oder negative Werte zählen als 0.
local function sanitize(viewport: any): Viewport
    local width = if type(viewport) == "table" and finite(viewport.width) then math.max(viewport.width, 0) else 0
    local height = if type(viewport) == "table" and finite(viewport.height) then math.max(viewport.height, 0) else 0
    return { width = width, height = height }
end

-- "compact", wenn die kürzere Seite unter der Grenze liegt, sonst "normal".
function ScreenLayout.sizeClass(viewport: Viewport, config: any?): string
    local cfg: any = config or DefaultConfig
    local size = sanitize(viewport)
    if math.min(size.width, size.height) < cfg.compactShortSide then
        return "compact"
    end
    return "normal"
end

function ScreenLayout.classData(class: string, config: any?): any
    local cfg: any = config or DefaultConfig
    return cfg.classes[class] or cfg.classes.normal
end

-- Größe eines Fensters ("narrow" oder "wide"): Anteil des Bildschirms mit Grenzen, nie größer
-- als die sichere Fläche abzüglich Rand.
function ScreenLayout.windowSize(viewport: Viewport, kind: string, config: any?): { width: number, height: number }
    local cfg: any = config or DefaultConfig
    local size = sanitize(viewport)
    local spec = cfg.windows[kind] or cfg.windows.narrow
    local availW = math.max(size.width - 2 * cfg.windowMargin, 0)
    local availH = math.max(size.height - 2 * cfg.windowMargin, 0)
    local width = math.min(math.clamp(size.width * spec.scaleX, spec.minW, spec.maxW), availW)
    local height = math.min(math.clamp(size.height * spec.scaleY, spec.minH, spec.maxH), availH)
    return { width = width, height = height }
end

-- Überlappen sich zwei Rechtecke? Berühren der Kanten zählt nicht.
function ScreenLayout.overlaps(a: Rect, b: Rect): boolean
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Liegt das Rechteck ganz im Bild?
function ScreenLayout.inside(rect: Rect, viewport: Viewport): boolean
    local size = sanitize(viewport)
    return rect.x >= 0 and rect.y >= 0 and rect.x + rect.w <= size.width and rect.y + rect.h <= size.height
end

-- Alle Plätze für eine Bildschirmgröße. `touch`: Handy oder Tablet ohne Tastatur. `menuCount`:
-- wie viele Menü-Knöpfe gerade sichtbar sind.
function ScreenLayout.compute(viewport: Viewport, touch: boolean, menuCount: number, config: any?): Layout
    local cfg: any = config or DefaultConfig
    local size = sanitize(viewport)
    local width, height = size.width, size.height
    local class = ScreenLayout.sizeClass(size, cfg)
    local c = cfg.classes[class]
    local count = if finite(menuCount) then math.max(math.floor(menuCount), 0) else 0

    local hud: Rect = { x = c.hud.x, y = c.hud.y, w = c.hud.w, h = c.hud.h }
    local hudBottom = c.lines.debugY + c.lines.h
    local hudStack: Rect = { x = c.hud.x, y = c.hud.y, w = math.max(c.hud.w, c.lines.w), h = hudBottom - c.hud.y }

    local tree = c.treeButton
    local treeButton: Rect = { x = width - tree.marginX - tree.w, y = tree.marginY, w = tree.w, h = tree.h }

    -- Zone des Sprungknopfs, nur am Touch-Gerät.
    local jump: Rect? = nil
    if touch then
        jump = { x = width - cfg.jumpZone.w, y = height - cfg.jumpZone.h, w = cfg.jumpZone.w, h = cfg.jumpZone.h }
    end

    -- Menü-Knöpfe: am Handy (oder in kleinem Fenster) eine Spalte rechts unter dem Baum-Knopf,
    -- die bei Platzmangel nach links eine weitere Spalte anfängt. Am PC eine Reihe unten links.
    local mb = c.menuButton
    local menuMode = if touch or class == "compact" then "column" else "row"
    local menu: { Rect } = {}
    if menuMode == "column" then
        -- Die Spalte beginnt unter dem Baum-Knopf und unter dem Tutorial-Banner (der bei mehreren
        -- Spalten bis über sie reichen kann).
        local startY = math.max(treeButton.y + treeButton.h, c.banner.y + c.banner.h) + mb.gap
        local bottomLimit = if jump ~= nil then jump.y - mb.gap else height - cfg.windowMargin
        local capacity = math.max(math.floor((bottomLimit - startY + mb.gap) / (mb.h + mb.gap)), 1)
        for index = 0, count - 1 do
            local column = index // capacity
            local row = index % capacity
            table.insert(menu, {
                x = width - tree.marginX - mb.w - column * (mb.w + mb.gap),
                y = startY + row * (mb.h + mb.gap),
                w = mb.w,
                h = mb.h,
            })
        end
    else
        local perRow = math.max(math.floor((width - 2 * c.menuRow.x + mb.gap) / (mb.w + mb.gap)), 1)
        for index = 0, count - 1 do
            local column = index % perRow
            local row = index // perRow
            table.insert(menu, {
                x = c.menuRow.x + column * (mb.w + mb.gap),
                y = height - c.menuRow.bottom - mb.h - row * (mb.h + mb.gap),
                w = mb.w,
                h = mb.h,
            })
        end
    end

    -- Tutorial-Banner: im freien Streifen zwischen HUD und Baum-Knopf. Bleibt dort weniger als
    -- minW übrig (Hochformat), rutscht er unter den HUD-Stapel und endet vor der Menüspalte.
    local bn = c.banner
    local bandLeft = hudStack.x + hudStack.w + bn.gap
    local bandRight = treeButton.x - bn.gap
    local bandW = bandRight - bandLeft
    local banner: Rect
    if bandW >= bn.minW then
        local w = math.min(bn.maxW, bandW)
        banner = { x = bandLeft + (bandW - w) / 2, y = bn.y, w = w, h = bn.h }
    else
        local right = width - hud.x
        if menuMode == "column" and count > 0 then
            for _, rect in menu do
                right = math.min(right, rect.x - bn.gap)
            end
        end
        banner = { x = hud.x, y = hudBottom + bn.gap, w = math.max(right - hud.x, 0), h = bn.h }
    end

    -- Graben-Knopf links neben dem Sprungknopf.
    local dig: Rect? = nil
    if touch then
        local d = c.dig
        dig = { x = width - cfg.jumpZone.w - d.gapToJump - d.size, y = height - d.bottom - d.size, w = d.size, h = d.size }
    end

    return {
        class = class,
        touch = touch,
        menuMode = menuMode,
        viewport = size,
        hud = hud,
        hudStack = hudStack,
        hudBottom = hudBottom,
        treeButton = treeButton,
        banner = banner,
        menu = menu,
        dig = dig,
        jump = jump,
    }
end

return ScreenLayout
