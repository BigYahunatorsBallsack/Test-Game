--!strict
-- Paket 3.6: Wahl der Grafikstufe und ihre Einstellungen (Logic/GraphicsLevel, Data/Screen).

local T = require("./lib/expect")
local GraphicsLevel = require("../src/shared/Logic/GraphicsLevel")
local Config = require("../src/shared/Data/Screen")

T.describe("Wahl der Stufe", function()
    T.it("PC mit guter Bildrate: hoch", function()
        T.expect(GraphicsLevel.pick({ touch = false, fallback = false })).toBe("hoch")
        T.expect(GraphicsLevel.pick({})).toBe("hoch")
        T.expect(GraphicsLevel.pick({ touch = false, quality = 0 })).toBe("hoch")
        T.expect(GraphicsLevel.pick({ touch = false, quality = 10 })).toBe("hoch")
    end)

    T.it("Touch-Gerät: schlank", function()
        T.expect(GraphicsLevel.pick({ touch = true })).toBe("schlank")
    end)

    T.it("Grafikregler 1 bis 3: schlank, ab 4 und in Automatik nicht", function()
        T.expect(GraphicsLevel.pick({ quality = 1 })).toBe("schlank")
        T.expect(GraphicsLevel.pick({ quality = 3 })).toBe("schlank")
        T.expect(GraphicsLevel.pick({ quality = 4 })).toBe("hoch")
        T.expect(GraphicsLevel.pick({ quality = 0 })).toBe("hoch")
        T.expect(GraphicsLevel.pick({ quality = -2 })).toBe("hoch")
    end)

    T.it("Rückfall des Bildraten-Wächters: minimal, auch am PC", function()
        T.expect(GraphicsLevel.pick({ fallback = true, touch = false })).toBe("minimal")
        T.expect(GraphicsLevel.pick({ fallback = true, touch = true })).toBe("minimal")
    end)

    T.it("das Attribut gewinnt immer", function()
        T.expect(GraphicsLevel.pick({ forced = "hoch", touch = true, fallback = true })).toBe("hoch")
        T.expect(GraphicsLevel.pick({ forced = "minimal", touch = false })).toBe("minimal")
        T.expect(GraphicsLevel.pick({ forced = "schlank", touch = false })).toBe("schlank")
    end)

    T.it("ein ungültiges Attribut wird ignoriert", function()
        T.expect(GraphicsLevel.pick({ forced = "ultra", touch = true })).toBe("schlank")
        T.expect(GraphicsLevel.pick({ forced = 5, touch = false })).toBe("hoch")
        T.expect(GraphicsLevel.pick({ forced = "", fallback = true })).toBe("minimal")
        T.expect(GraphicsLevel.isLevel("hoch")).toBe(true)
        T.expect(GraphicsLevel.isLevel("Hoch")).toBe(false)
        T.expect(GraphicsLevel.isLevel(nil)).toBe(false)
    end)
end)

T.describe("Einstellungen je Stufe", function()
    local flags = { "postEffects", "toolShadows", "foundLight", "sandFlow", "revealEffects", "weatherParticles" }

    T.it("Partikelfaktor: hoch 1, schlank höchstens 0,5, minimal 0", function()
        T.expect(GraphicsLevel.settings("hoch").particleFactor).toBe(1)
        T.expect(GraphicsLevel.settings("schlank").particleFactor <= 0.5).toBe(true)
        T.expect(GraphicsLevel.settings("minimal").particleFactor).toBe(0)
    end)

    T.it("minimal schaltet alles ab, was schlank abschaltet, und schlank, was hoch abschaltet", function()
        local hoch = GraphicsLevel.settings("hoch")
        local schlank = GraphicsLevel.settings("schlank")
        local minimal = GraphicsLevel.settings("minimal")
        for _, flag in flags do
            if hoch[flag] == false then
                T.expect(schlank[flag]).toBe(false)
            end
            if schlank[flag] == false then
                T.expect(minimal[flag]).toBe(false)
            end
        end
        T.expect(schlank.motionDistanceFactor <= hoch.motionDistanceFactor).toBe(true)
        T.expect(minimal.motionDistanceFactor <= schlank.motionDistanceFactor).toBe(true)
    end)

    T.it("schlank spart Nachbearbeitung und Schatten, behält aber Sandfluss und Reveal", function()
        local schlank = GraphicsLevel.settings("schlank")
        T.expect(schlank.postEffects).toBe(false)
        T.expect(schlank.toolShadows).toBe(false)
        T.expect(schlank.sandFlow).toBe(true)
        T.expect(schlank.revealEffects).toBe(true)
    end)

    T.it("minimal schaltet Sandfluss, Reveal-Effekte und Wetter-Partikel ab", function()
        local minimal = GraphicsLevel.settings("minimal")
        T.expect(minimal.sandFlow).toBe(false)
        T.expect(minimal.revealEffects).toBe(false)
        T.expect(minimal.weatherParticles).toBe(false)
    end)

    T.it("eine unbekannte Stufe gibt die Einstellungen von hoch", function()
        T.expect(GraphicsLevel.settings("ultra")).toEqual(GraphicsLevel.settings("hoch"))
    end)

    T.it("die Reihenfolge in den Daten nennt alle drei Stufen", function()
        T.expect(Config.graphics.order).toEqual({ "hoch", "schlank", "minimal" })
    end)
end)

T.finish()
