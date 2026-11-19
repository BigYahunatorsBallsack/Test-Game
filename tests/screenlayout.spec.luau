--!strict
-- Paket 3.6: Plätze der Oberfläche am kleinen und am großen Bildschirm (Logic/ScreenLayout,
-- Data/Screen).

local T = require("./lib/expect")
local ScreenLayout = require("../src/shared/Logic/ScreenLayout")
local DataCheck = require("../src/shared/Logic/DataCheck")
local Config = require("../src/shared/Data/Screen")

local function vp(width: number, height: number): ScreenLayout.Viewport
    return { width = width, height = height }
end

-- Alle Elemente, die sich nicht überlappen dürfen.
local function elements(layout: ScreenLayout.Layout): { { name: string, rect: ScreenLayout.Rect } }
    local list = {
        { name = "hudStack", rect = layout.hudStack },
        { name = "treeButton", rect = layout.treeButton },
        { name = "banner", rect = layout.banner },
    }
    for index, rect in layout.menu do
        table.insert(list, { name = `menu{index}`, rect = rect })
    end
    if layout.dig ~= nil then
        table.insert(list, { name = "dig", rect = layout.dig :: ScreenLayout.Rect })
    end
    if layout.jump ~= nil then
        table.insert(list, { name = "jump", rect = layout.jump :: ScreenLayout.Rect })
    end
    return list
end

local function describe(rect: ScreenLayout.Rect): string
    return `({rect.x},{rect.y} {rect.w}x{rect.h})`
end

local function expectNoOverlap(layout: ScreenLayout.Layout, label: string)
    local list = elements(layout)
    for i = 1, #list do
        for j = i + 1, #list do
            if ScreenLayout.overlaps(list[i].rect, list[j].rect) then
                error(`{label}: {list[i].name} {describe(list[i].rect)} überlappt {list[j].name} {describe(list[j].rect)}`)
            end
        end
    end
end

local function expectInside(layout: ScreenLayout.Layout, label: string)
    for _, entry in elements(layout) do
        if not ScreenLayout.inside(entry.rect, layout.viewport) then
            error(`{label}: {entry.name} {describe(entry.rect)} liegt nicht im Bild`)
        end
    end
end

T.describe("Größenklasse", function()
    T.it("Handys sind kompakt, PC und Tablets normal", function()
        T.expect(ScreenLayout.sizeClass(vp(568, 320))).toBe("compact")
        T.expect(ScreenLayout.sizeClass(vp(667, 375))).toBe("compact")
        T.expect(ScreenLayout.sizeClass(vp(375, 667))).toBe("compact")
        T.expect(ScreenLayout.sizeClass(vp(1024, 768))).toBe("normal")
        T.expect(ScreenLayout.sizeClass(vp(1920, 1080))).toBe("normal")
    end)

    T.it("die Grenze liegt genau bei der kürzeren Seite von 500", function()
        T.expect(ScreenLayout.sizeClass(vp(900, 499))).toBe("compact")
        T.expect(ScreenLayout.sizeClass(vp(900, 500))).toBe("normal")
        T.expect(ScreenLayout.sizeClass(vp(499, 900))).toBe("compact")
        T.expect(ScreenLayout.sizeClass(vp(500, 900))).toBe("normal")
    end)

    T.it("kaputte Größen werfen keinen Fehler", function()
        T.expect(ScreenLayout.sizeClass(vp(0, 0))).toBe("compact")
        T.expect(ScreenLayout.sizeClass(vp(0 / 0, 800))).toBe("compact")
        T.expect(ScreenLayout.sizeClass(vp(-5, -5))).toBe("compact")
    end)
end)

T.describe("Fenstergröße", function()
    local sizes = { vp(568, 320), vp(667, 375), vp(375, 667), vp(360, 640), vp(1024, 768), vp(1920, 1080), vp(2560, 1440) }

    T.it("bleibt in der sicheren Fläche und hält Ober- und Untergrenze ein", function()
        for _, size in sizes do
            for _, kind in { "narrow", "wide" } do
                local spec = Config.windows[kind]
                local window = ScreenLayout.windowSize(size, kind)
                T.expect(window.width <= size.width - 2 * Config.windowMargin).toBe(true)
                T.expect(window.height <= size.height - 2 * Config.windowMargin).toBe(true)
                T.expect(window.width <= spec.maxW).toBe(true)
                T.expect(window.height <= spec.maxH).toBe(true)
                T.expect(window.width >= spec.minW).toBe(true)
                T.expect(window.height >= spec.minH).toBe(true)
            end
        end
    end)

    T.it("am kleinsten Handy bleibt Platz: 568 x 320 gibt mindestens 280 x 200", function()
        local window = ScreenLayout.windowSize(vp(568, 320), "narrow")
        T.expect(window.width >= 280).toBe(true)
        T.expect(window.height >= 200).toBe(true)
    end)

    T.it("kaputte Größen geben 0 und keinen Fehler", function()
        for _, size in { vp(0, 0), vp(-10, 40), vp(0 / 0, 0 / 0), vp(math.huge, 100) } do
            local window = ScreenLayout.windowSize(size, "wide")
            T.expect(window.width >= 0).toBe(true)
            T.expect(window.height >= 0).toBe(true)
            T.expect(window.width == window.width).toBe(true)
        end
        T.expect(ScreenLayout.windowSize(vp(0, 0), "narrow").width).toBe(0)
    end)

    T.it("eine unbekannte Art nimmt die schmale", function()
        T.expect(ScreenLayout.windowSize(vp(1024, 768), "gibtsnicht")).toEqual(ScreenLayout.windowSize(vp(1024, 768), "narrow"))
    end)
end)

T.describe("Tippflächen", function()
    T.it("jeder Knopf aus Data/Screen ist in jeder Klasse mindestens 44 px", function()
        for class, c in Config.classes do
            T.expect(c.treeButton.w >= 44).toBe(true)
            T.expect(c.treeButton.h >= 44).toBe(true)
            T.expect(c.menuButton.w >= 44).toBe(true)
            T.expect(c.menuButton.h >= 44).toBe(true)
            T.expect(c.dig.size >= 44).toBe(true)
            if c.treeButton.w < 44 then
                error(`{class}: Baum-Knopf zu klein`)
            end
        end
        for _, field in { "closeButton", "rowButtonW", "rowButtonH", "tabH" } do
            T.expect(Config.controls[field] >= 44).toBe(true)
        end
    end)
end)

T.describe("Menüleiste und Plätze", function()
    local cases = {
        { name = "iPhone SE quer", size = vp(568, 320), touch = true },
        { name = "iPhone 14 quer", size = vp(844, 390), touch = true },
        { name = "Android 360 quer", size = vp(640, 360), touch = true },
        { name = "iPhone 8 quer", size = vp(667, 375), touch = true },
        { name = "iPhone hoch", size = vp(375, 667), touch = true },
        { name = "iPad quer", size = vp(1024, 768), touch = true },
        { name = "kleines Fenster am PC", size = vp(568, 320), touch = false },
        { name = "PC 800", size = vp(800, 600), touch = false },
        { name = "PC 1080", size = vp(1920, 1080), touch = false },
        { name = "PC 1440", size = vp(2560, 1440), touch = false },
    }

    T.it("nichts überlappt und alles liegt im Bild, bei 0, 3 und 5 Menü-Knöpfen", function()
        for _, case in cases do
            for _, count in { 0, 3, 5 } do
                local layout = ScreenLayout.compute(case.size, case.touch, count)
                local label = `{case.name} mit {count} Knöpfen`
                expectNoOverlap(layout, label)
                expectInside(layout, label)
                T.expect(#layout.menu).toBe(count)
            end
        end
    end)

    T.it("am Handy steht die Menüspalte rechts unter dem Baum-Knopf", function()
        local layout = ScreenLayout.compute(vp(568, 320), true, 3)
        T.expect(layout.menuMode).toBe("column")
        local tree = layout.treeButton
        for _, rect in layout.menu do
            T.expect(rect.y >= tree.y + tree.h).toBe(true)
            T.expect(rect.x + rect.w <= tree.x + tree.w).toBe(true)
        end
        T.expect((layout.menu[1] :: ScreenLayout.Rect).x).toBe(tree.x + tree.w - Config.classes.compact.menuButton.w)
    end)

    T.it("eine zweite Spalte entsteht nur, wenn eine nicht reicht", function()
        local small = ScreenLayout.compute(vp(568, 320), true, 5)
        local columns: { [number]: boolean } = {}
        for _, rect in small.menu do
            columns[rect.x] = true
        end
        local count = 0
        for _ in columns do
            count += 1
        end
        T.expect(count > 1).toBe(true)
        -- Im Hochformat ist genug Höhe da: eine Spalte.
        local tall = ScreenLayout.compute(vp(375, 667), true, 5)
        local tallColumns: { [number]: boolean } = {}
        for _, rect in tall.menu do
            tallColumns[rect.x] = true
        end
        local tallCount = 0
        for _ in tallColumns do
            tallCount += 1
        end
        T.expect(tallCount).toBe(1)
    end)

    T.it("am PC steht die Menüleiste als Reihe unten links und bricht um", function()
        local wide = ScreenLayout.compute(vp(1920, 1080), false, 3)
        T.expect(wide.menuMode).toBe("row")
        local first = wide.menu[1] :: ScreenLayout.Rect
        local second = wide.menu[2] :: ScreenLayout.Rect
        T.expect(first.y).toBe(second.y)
        T.expect(second.x > first.x).toBe(true)
        T.expect(first.y > 1080 / 2).toBe(true)
        -- 600 breit: nur 3 Knöpfe in eine Reihe (16 + 3 * 148), der vierte steht darüber.
        local narrow = ScreenLayout.compute(vp(600, 600), false, 5)
        local fourth = narrow.menu[4] :: ScreenLayout.Rect
        local firstNarrow = narrow.menu[1] :: ScreenLayout.Rect
        T.expect(fourth.y < firstNarrow.y).toBe(true)
        T.expect(fourth.x).toBe(firstNarrow.x)
    end)

    T.it("Graben-Knopf und Sprungknopf-Zone gibt es nur am Touch-Gerät, der Graben-Knopf liegt links vom Sprung", function()
        local touch = ScreenLayout.compute(vp(568, 320), true, 3)
        local pc = ScreenLayout.compute(vp(1920, 1080), false, 3)
        T.expect(pc.dig).toBeNil()
        T.expect(pc.jump).toBeNil()
        local dig = touch.dig :: ScreenLayout.Rect
        local jump = touch.jump :: ScreenLayout.Rect
        T.expect(dig.x + dig.w <= jump.x).toBe(true)
    end)

    T.it("die Anzahl der Knöpfe ist robust gegen kaputte Werte", function()
        T.expect(#ScreenLayout.compute(vp(568, 320), true, -3).menu).toBe(0)
        T.expect(#ScreenLayout.compute(vp(568, 320), true, 0 / 0).menu).toBe(0)
        T.expect(#ScreenLayout.compute(vp(0, 0), true, 2).menu).toBe(2)
    end)
end)

T.describe("Tutorial-Banner", function()
    T.it("ist bei 568 bis 2560 Breite mindestens 240 px breit und überlappt nichts", function()
        for _, width in { 568, 640, 667, 800, 844, 1024, 1280, 1920, 2560 } do
            for _, touch in { true, false } do
                local height = if width < 700 then 320 else 600
                local layout = ScreenLayout.compute(vp(width, height), touch, 4)
                T.expect(layout.banner.w >= Config.classes[layout.class].banner.minW).toBe(true)
                expectNoOverlap(layout, `Banner bei {width} x {height}, Touch {tostring(touch)}`)
            end
        end
    end)

    T.it("im Hochformat (375 x 667) rutscht er unter den HUD-Stapel und ist mindestens 240 px breit", function()
        local layout = ScreenLayout.compute(vp(375, 667), true, 4)
        T.expect(layout.banner.y >= layout.hudBottom).toBe(true)
        T.expect(layout.banner.w >= 240).toBe(true)
        expectNoOverlap(layout, "Hochformat")
    end)

    T.it("er ist nie breiter als sein Höchstwert", function()
        local layout = ScreenLayout.compute(vp(2560, 1440), false, 3)
        T.expect(layout.banner.w).toBe(Config.classes.normal.banner.maxW)
    end)
end)

T.describe("DataCheck", function()
    local function fresh(): any
        return table.clone(DataCheck.defaults())
    end
    local function deep(value: any): any
        if type(value) ~= "table" then
            return value
        end
        local copy = {}
        for key, inner in value do
            copy[key] = deep(inner)
        end
        return copy
    end
    local function expectError(errors: { string }, part: string)
        for _, message in errors do
            if string.find(message, part, 1, true) ~= nil then
                return
            end
        end
        error(`Fehler "{part}" erwartet, bekommen: {table.concat(errors, " | ")}`)
    end

    T.it("die echten Daten bestehen die Prüfung", function()
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("ein Knopf unter 44 px wird abgelehnt", function()
        local data = fresh()
        data.Screen = deep(data.Screen)
        data.Screen.classes.compact.menuButton.h = 40
        expectError(DataCheck.run(data), "compact.menuButton.h muss mindestens 44")
        local data2 = fresh()
        data2.Screen = deep(data2.Screen)
        data2.Screen.controls.closeButton = 30
        expectError(DataCheck.run(data2), "closeButton muss mindestens 44")
    end)

    T.it("ein Grafikfaktor außerhalb von 0 bis 1 wird abgelehnt", function()
        local data = fresh()
        data.Screen = deep(data.Screen)
        data.Screen.graphics.levels.schlank.particleFactor = 1.5
        expectError(DataCheck.run(data), "particleFactor muss eine Zahl von 0 bis 1")
    end)

    T.it("eine fehlende Stufe wird abgelehnt", function()
        local data = fresh()
        data.Screen = deep(data.Screen)
        data.Screen.graphics.levels.minimal = nil
        expectError(DataCheck.run(data), "levels.minimal fehlt")
    end)

    T.it("eine untere Stufe, die mehr kann als die obere, wird abgelehnt", function()
        local data = fresh()
        data.Screen = deep(data.Screen)
        data.Screen.graphics.levels.minimal.postEffects = true
        expectError(DataCheck.run(data), "postEffects darf nichts einschalten")
        local data2 = fresh()
        data2.Screen = deep(data2.Screen)
        data2.Screen.graphics.levels.minimal.particleFactor = 0.9
        expectError(DataCheck.run(data2), "particleFactor darf nicht über dem der höheren Stufe liegen")
    end)

    T.it("ein Fenster mit Obergrenze unter der Untergrenze wird abgelehnt", function()
        local data = fresh()
        data.Screen = deep(data.Screen)
        data.Screen.windows.wide.maxW = 100
        expectError(DataCheck.run(data), "maxW liegt unter minW")
    end)

    T.it("ein fehlendes Screen-Modul wird gemeldet", function()
        local data = fresh()
        data.Screen = nil
        expectError(DataCheck.run(data), "Screen fehlt")
    end)
end)

T.finish()
