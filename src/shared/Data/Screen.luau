--!strict
-- Zahlen für den Handy-Durchgang (Paket 3.6): Größenklassen, Plätze der Oberfläche, Fenstergrößen
-- und Grafikstufen. Logic/ScreenLayout und Logic/GraphicsLevel rechnen damit, die Controller
-- zeichnen nur. Alle Maße sind Pixel auf der sicheren Fläche (ScreenGui mit CoreUISafe).
-- Farben und Texte stehen weiter in den Controllern (vorläufig bis Stil-Guide 0.4).

return {
    -- Ist die kürzere Bildschirmseite kleiner als dieser Wert, gilt die Klasse "compact"
    -- (Handy quer oder hoch), sonst "normal".
    compactShortSide = 500,
    -- Kleinste Kantenlänge eines Knopfes, den man mit dem Daumen trifft.
    minTouchPixels = 44,
    -- Abstand eines Fensters zum Bildschirmrand.
    windowMargin = 8,

    -- Bedienelemente in Fenstern (für beide Klassen gleich).
    controls = {
        closeButton = 44, -- Schließen-Knopf
        rowButtonW = 92, -- Knopf in einer Listenzeile (Reisen)
        rowButtonH = 44,
        tabH = 44, -- Reiter
        headerH = 48, -- Kopfzeile eines Fensters
        rowGap = 8,
    },

    -- Fenstergrößen: Anteil des Bildschirms, mit Unter- und Obergrenze.
    windows = {
        narrow = { scaleX = 0.92, scaleY = 0.9, minW = 280, minH = 200, maxW = 480, maxH = 440 },
        wide = { scaleX = 0.92, scaleY = 0.9, minW = 280, minH = 200, maxW = 640, maxH = 520 },
    },

    -- Zone des Roblox-Sprungknopfs unten rechts (nur am Touch-Gerät), damit nichts darauf liegt.
    jumpZone = { w = 120, h = 120 },

    classes = {
        normal = {
            -- Panel mit Münzen und Tank oben links, darunter Textzeilen (Werkzeug, Wind, Debug).
            hud = { x = 16, y = 16, w = 240, h = 84, pad = 12, coinsY = 6, coinsH = 30, barY = 44, barH = 28 },
            lines = { toolY = 104, windY = 126, debugY = 152, h = 22, w = 320 },
            -- Knopf "Baum" oben rechts, daran hängt die Menüleiste.
            treeButton = { w = 124, h = 46, marginX = 16, marginY = 16 },
            menuButton = { w = 140, h = 48, gap = 8 },
            -- PC: Reihe unten links (bricht nach oben um). Touch: Spalte rechts unter dem Baum-Knopf.
            menuRow = { x = 16, bottom = 24 },
            -- Tutorial-Banner im freien Streifen zwischen HUD und Baum-Knopf.
            banner = { maxW = 460, minW = 240, h = 64, y = 16, gap = 8 },
            toast = { w = 400, yScale = 0.75 },
            dig = { size = 96, bottom = 24, gapToJump = 12 },
            smallCard = { w = 264, h = 92, side = "right", yScale = 0.4, yOffset = 0, anchorY = 0.5, margin = 16 },
            bigCard = { w = 340, h = 220 },
            stormBanner = { w = 520, h = 90 },
        },
        compact = {
            hud = { x = 12, y = 8, w = 176, h = 60, pad = 8, coinsY = 4, coinsH = 24, barY = 31, barH = 24 },
            lines = { toolY = 70, windY = 86, debugY = 102, h = 16, w = 230 },
            treeButton = { w = 96, h = 44, marginX = 12, marginY = 8 },
            menuButton = { w = 96, h = 44, gap = 8 },
            menuRow = { x = 12, bottom = 16 },
            banner = { maxW = 460, minW = 240, h = 50, y = 8, gap = 8 },
            toast = { w = 280, yScale = 0.62 },
            dig = { size = 84, bottom = 16, gapToJump = 12 },
            smallCard = { w = 220, h = 72, side = "left", yScale = 0, yOffset = 126, anchorY = 0, margin = 12 },
            bigCard = { w = 340, h = 220 },
            stormBanner = { w = 520, h = 90 },
        },
    },

    -- Grafikstufen. "hoch" ist der Standard am PC, "schlank" gilt am Touch-Gerät und bei niedrigem
    -- Grafikregler, "minimal" ist die Rückfallvariante des Bildraten-Wächters (keine Terrain-
    -- Verformung, keine Effekte). Jede Stufe darf nur abschalten, was die darüber hat.
    graphics = {
        -- Grafikregler von Roblox 1 bis hierhin zählt als schwaches Gerät (Automatik = kein Wert).
        leanMaxQualityLevel = 3,
        order = { "hoch", "schlank", "minimal" },
        levels = {
            hoch = {
                particleFactor = 1, -- Anteil der Partikel (Wetter, Sandfluss)
                motionDistanceFactor = 1, -- Anteil der Entfernung, bis zu der fremde Werkzeuge sich bewegen
                postEffects = true, -- Bloom, Sonnenstrahlen, Tiefenschärfe, Unschärfe
                toolShadows = true, -- Schatten fremder Werkzeuge
                foundLight = true, -- Licht am Fund-Objekt im Sand
                sandFlow = true,
                revealEffects = true, -- Lichtstoß, Blitz, Fund-Objekt
                weatherParticles = true,
            },
            schlank = {
                particleFactor = 0.5,
                motionDistanceFactor = 0.4,
                postEffects = false,
                toolShadows = false,
                foundLight = false,
                sandFlow = true,
                revealEffects = true,
                weatherParticles = true,
            },
            minimal = {
                particleFactor = 0,
                motionDistanceFactor = 0.4,
                postEffects = false,
                toolShadows = false,
                foundLight = false,
                sandFlow = false,
                revealEffects = false,
                weatherParticles = false,
            },
        },
    },
}
