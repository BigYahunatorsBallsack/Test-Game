--!strict
-- Paket 2.2: Kamera des Baums (Zoom, Verschieben, Tippen oder Ziehen).

local T = require("./lib/expect")
local TreeCamera = require("../src/shared/Logic/TreeCamera")
local TreeLayout = require("../src/shared/Logic/TreeLayout")
local Config = require("../src/shared/Data/TreeLayout")

local layout = TreeLayout.compute()
local area = layout.area
local phone = { width = 800, height = 360 } -- Handy quer
local big = { width = 6000, height = 6000 } -- größer als der ganze Baum

local function fresh(viewport: TreeCamera.Viewport): TreeCamera.Camera
    return TreeCamera.centerOn({ zoom = Config.zoom.start, panX = 0, panY = 0 }, { x = 0, y = 0 }, viewport, area)
end

T.describe("Zoom", function()
    T.it("bleibt zwischen den Grenzen, auch bei extremen Werten", function()
        T.expect(TreeCamera.clampZoom(0)).toBe(Config.zoom.min)
        T.expect(TreeCamera.clampZoom(-5)).toBe(Config.zoom.min)
        T.expect(TreeCamera.clampZoom(1e9)).toBe(Config.zoom.max)
        T.expect(TreeCamera.clampZoom(0 / 0)).toBe(Config.zoom.start)
        local camera = fresh(phone)
        local zoomedOut = TreeCamera.zoomAt(camera, 1e-9, { x = 400, y = 180 }, phone, area)
        T.expect(zoomedOut.zoom).toBe(Config.zoom.min)
        local zoomedIn = TreeCamera.zoomAt(camera, 1e9, { x = 400, y = 180 }, phone, area)
        T.expect(zoomedIn.zoom).toBe(Config.zoom.max)
        local pinched = TreeCamera.pinch(camera, { x = 390, y = 180 }, { x = 410, y = 180 }, { x = 0, y = 180 }, { x = 800, y = 180 }, phone, area)
        T.expect(pinched.zoom).toBe(Config.zoom.max)
        local pinchedIn = TreeCamera.pinch(camera, { x = 0, y = 180 }, { x = 800, y = 180 }, { x = 399, y = 180 }, { x = 401, y = 180 }, phone, area)
        T.expect(pinchedIn.zoom).toBe(Config.zoom.min)
    end)

    T.it("Mausrad und Knöpfe zoomen um den Punkt, der Weltpunkt darunter bleibt stehen", function()
        local camera = fresh(phone)
        local anchor = { x = 600, y = 120 }
        local before = TreeCamera.toWorld(camera, anchor)
        local after = TreeCamera.zoomAt(camera, Config.zoom.wheelStep, anchor, phone, area)
        T.expect(after.zoom).toBeCloseTo(camera.zoom * Config.zoom.wheelStep, 1e-9)
        local now = TreeCamera.toWorld(after, anchor)
        T.expect(now.x).toBeCloseTo(before.x, 1e-6)
        T.expect(now.y).toBeCloseTo(before.y, 1e-6)
    end)

    T.it("Pinch: Der Punkt unter der alten Fingermitte folgt der neuen Fingermitte", function()
        local camera = fresh(phone)
        local a0, b0 = { x = 300, y = 150 }, { x = 500, y = 150 }
        local a1, b1 = { x = 320, y = 160 }, { x = 560, y = 160 } -- Finger weiter auseinander und leicht verschoben
        local worldUnderMid = TreeCamera.toWorld(camera, { x = 400, y = 150 })
        local after = TreeCamera.pinch(camera, a0, b0, a1, b1, phone, area)
        T.expect(after.zoom).toBeCloseTo(camera.zoom * 240 / 200, 1e-9)
        local mid = TreeCamera.toScreen(after, worldUnderMid)
        T.expect(mid.x).toBeCloseTo(440, 1e-6)
        T.expect(mid.y).toBeCloseTo(160, 1e-6)
    end)

    T.it("Pinch mit zwei fast gleichen Fingern teilt nicht durch null", function()
        local camera = fresh(phone)
        local after = TreeCamera.pinch(camera, { x = 400, y = 150 }, { x = 400, y = 150 }, { x = 300, y = 150 }, { x = 500, y = 150 }, phone, area)
        T.expect(after.zoom).toBe(camera.zoom)
    end)
end)

T.describe("Verschieben", function()
    T.it("stoppt am Rand: Man kann den Baum nicht ganz aus dem Bild schieben", function()
        local camera = fresh(phone)
        local far = TreeCamera.drag(camera, -1e7, -1e7, phone, area)
        -- Rechte untere Ecke der Fläche liegt noch am Bildrand.
        local corner = TreeCamera.toScreen(far, { x = area.maxX, y = area.maxY })
        T.expect(corner.x).toBeCloseTo(phone.width, 1e-6)
        T.expect(corner.y).toBeCloseTo(phone.height, 1e-6)
        local other = TreeCamera.drag(camera, 1e7, 1e7, phone, area)
        local origin = TreeCamera.toScreen(other, { x = area.minX, y = area.minY })
        T.expect(origin.x).toBeCloseTo(0, 1e-6)
        T.expect(origin.y).toBeCloseTo(0, 1e-6)
    end)

    T.it("ein Baum, der kleiner ist als das Bild, steht mittig und bewegt sich nicht", function()
        local camera = TreeCamera.centerOn({ zoom = Config.zoom.min, panX = 0, panY = 0 }, { x = 0, y = 0 }, big, area)
        local moved = TreeCamera.drag(camera, 500, -300, big, area)
        T.expect(moved.panX).toBeCloseTo(camera.panX, 1e-9)
        T.expect(moved.panY).toBeCloseTo(camera.panY, 1e-9)
        local middle = TreeCamera.toScreen(moved, { x = (area.minX + area.maxX) / 2, y = (area.minY + area.maxY) / 2 })
        T.expect(middle.x).toBeCloseTo(big.width / 2, 1e-6)
        T.expect(middle.y).toBeCloseTo(big.height / 2, 1e-6)
    end)

    T.it("ein kleiner Zug verschiebt um genau diesen Betrag", function()
        local camera = TreeCamera.centerOn(fresh(phone), { x = 0, y = -600 }, phone, area)
        local moved = TreeCamera.drag(camera, -25, -10, phone, area)
        T.expect(moved.panX).toBeCloseTo(camera.panX - 25, 1e-9)
        T.expect(moved.panY).toBeCloseTo(camera.panY - 10, 1e-9)
    end)
end)

T.describe("Tippen oder Ziehen", function()
    T.it("unter 10 px Bewegung ist Tippen, ab 10 px Ziehen", function()
        T.expect(TreeCamera.isTap(0)).toBe(true)
        T.expect(TreeCamera.isTap(9.9)).toBe(true)
        T.expect(TreeCamera.isTap(10)).toBe(false)
        T.expect(TreeCamera.isTap(200)).toBe(false)
    end)

    T.it("der Treffer liegt auf dem Knoten, nicht daneben, und überlappende Knoten werden nach Abstand getrennt", function()
        local positions: { [string]: TreeCamera.Point } = {}
        for id, placement in layout.nodes do
            positions[id] = { x = placement.x, y = placement.y }
        end
        local tank1 = layout.nodes.tank_1
        T.expect(TreeCamera.hitTest(positions, { x = tank1.x, y = tank1.y })).toBe("tank_1")
        T.expect(TreeCamera.hitTest(positions, { x = tank1.x + Config.nodeSize / 2 - 1, y = tank1.y - Config.nodeSize / 2 + 1 })).toBe("tank_1")
        T.expect(TreeCamera.hitTest(positions, { x = tank1.x + Config.nodeSize / 2 + 2, y = tank1.y })).toBeNil()
        T.expect(TreeCamera.hitTest(positions, { x = 99999, y = 99999 })).toBeNil()
        local overlap: { [string]: TreeCamera.Point } = { a = { x = 0, y = 0 }, b = { x = 30, y = 0 } }
        T.expect(TreeCamera.hitTest(overlap, { x = 20, y = 0 })).toBe("b")
        T.expect(TreeCamera.hitTest(overlap, { x = 5, y = 0 })).toBe("a")
    end)

    T.it("Tippen trifft den Knoten auch nach Zoom und Verschieben (Bildschirm -> Welt)", function()
        local camera = TreeCamera.zoomAt(fresh(phone), 1.3, { x = 200, y = 100 }, phone, area)
        camera = TreeCamera.drag(camera, -40, 25, phone, area)
        local target = layout.nodes.collect_tool_2
        local screen = TreeCamera.toScreen(camera, { x = target.x, y = target.y })
        local world = TreeCamera.toWorld(camera, screen)
        T.expect(world.x).toBeCloseTo(target.x, 1e-6)
        T.expect(world.y).toBeCloseTo(target.y, 1e-6)
    end)
end)

T.describe("Zentrieren", function()
    T.it("setzt einen Knoten in die Bildmitte, soweit der Rand es erlaubt", function()
        local narrow = { width = 400, height = 360 } -- schmaler als der Baum: beide Achsen bewegen sich
        local middleNode = layout.nodes.collect_tool_4 -- liegt mitten im Baum
        local centered = TreeCamera.centerOn(fresh(narrow), { x = middleNode.x, y = middleNode.y }, narrow, area)
        local screen = TreeCamera.toScreen(centered, { x = middleNode.x, y = middleNode.y })
        T.expect(screen.x).toBeCloseTo(narrow.width / 2, 1e-6)
        T.expect(screen.y).toBeCloseTo(narrow.height / 2, 1e-6)
        -- Der Start liegt unten am Rand: Die Mitte ist wegen der Begrenzung nicht erreichbar.
        local atStart = TreeCamera.centerOn(fresh(phone), { x = 0, y = 0 }, phone, area)
        local startScreen = TreeCamera.toScreen(atStart, { x = 0, y = 0 })
        T.expect(startScreen.y).toBeGreaterThan(phone.height / 2 - 1)
        T.expect(startScreen.y <= phone.height).toBe(true)
    end)
end)

T.describe("Antippbare Größe", function()
    T.it("Knotengröße mal kleinster Zoom ist mindestens 44 px", function()
        T.expect(TreeCamera.nodePixels(Config.zoom.min) >= Config.minTouchPixels).toBe(true)
        T.expect(TreeCamera.nodePixels(Config.zoom.min) >= 44).toBe(true)
    end)

    T.it("bei kleinstem Zoom sind benachbarte Knoten noch getrennt (Spalten und Reihen)", function()
        T.expect((Config.columnSpacing - Config.nodeSize) * Config.zoom.min > 0).toBe(true)
        T.expect((Config.rowSpacing - Config.nodeSize) * Config.zoom.min > 0).toBe(true)
    end)
end)

T.finish()
