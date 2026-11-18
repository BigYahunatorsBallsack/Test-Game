--!strict
-- Zahlen für die Baumansicht (Paket 2.2). Die Koordinaten der Knoten rechnet Logic/TreeLayout
-- aus UpgradeTree, hier stehen nur Spalten, Abstände, Zoomgrenzen und vorläufige Farben.
-- Farben und Zeichen sind Platzhalter bis Stil-Guide (0.4) und Icons (3.1).

-- Spalte je Wirkung (Zahl = Spalte, 0 = Mitte). Werkzeuge bilden den Stamm in der Mitte.
-- Ein neuer Ast braucht hier eine Spalte, ein neuer Knoten in einem bekannten Ast nichts.
local columns: { [string]: number } = {
    luckBonus = -2,
    setTank = -1,
    setTool = 0,
    rateBonus = 1,
    sellBonus = 2,
    grantedBySandstorm = 3,
}

-- Platzhalter-Zeichen und -Farbe je Wirkung (Farbe als RGB-Zahlen, damit das Modul rein bleibt).
local looks: { [string]: { glyph: string, color: { number } } } = {
    luckBonus = { glyph = "G", color = { 120, 190, 110 } },
    setTank = { glyph = "T", color = { 110, 160, 215 } },
    setTool = { glyph = "W", color = { 235, 190, 90 } },
    rateBonus = { glyph = "R", color = { 225, 130, 80 } },
    sellBonus = { glyph = "$", color = { 200, 150, 215 } },
    grantedBySandstorm = { glyph = "S", color = { 190, 170, 140 } },
}

return {
    columns = columns,
    looks = looks,

    -- Abstände in Studs der Baumfläche (1 Einheit = 1 Pixel bei Zoom 1).
    columnSpacing = 130,
    rowSpacing = 104,
    nodeSize = 72, -- Kantenlänge eines Knotens
    margin = 90, -- Rand um den äußersten Knoten

    -- Kamera
    zoom = {
        min = 0.62, -- 72 * 0.62 = 44,6 px: Knoten bleiben antippbar (minTouchPixels)
        max = 1.6,
        start = 1,
        buttonStep = 1.25, -- Faktor pro Druck auf Plus/Minus
        wheelStep = 1.1, -- Faktor pro Rastung des Mausrads
    },
    minTouchPixels = 44,
    tapMaxMovePixels = 10, -- bis hierhin gilt eine Berührung als Tippen, ab hier als Ziehen
}
