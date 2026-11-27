--!strict
-- Baukasten für alle Menüs (Überarbeitung Ü5: ein Stil). Färbt vorhandene Teile im Stil aus
-- Interface/Theme: Fenster, Kopfzeile, Knöpfe, Texte, Zeilen. Controller rufen nur diese Funktionen
-- und nehmen Farben aus Theme.ui, Schriften aus Theme.font. So hat kein Menü eigene Farben.

local Theme = require(script.Parent.Theme)

local Kit = {}

Kit.ui = Theme.ui
Kit.font = Theme.font

-- Knopfarten: "primary" (Gold, Hauptaktion), "normal" (Schiefer), "nav" (Türkis, Reiter aktiv),
-- "close" (Terrakotta), "good" (grün, z. B. Zusammenlegen).
local SWATCH: { [string]: Theme.Swatch } = {
    primary = Theme.gold,
    normal = Theme.slate,
    nav = Theme.teal,
    close = Theme.clay,
    good = Theme.finds.uncommon,
    panel = Theme.panel,
}

local function corner(item: GuiObject, radius: number)
    local c = item:FindFirstChildOfClass("UICorner")
    if c == nil then
        c = Instance.new("UICorner")
        c.Parent = item
    end
    (c :: UICorner).CornerRadius = UDim.new(0, radius)
end

-- Fenster oder große Karte: Verlauf, dunkle Kontur, heller Rand.
function Kit.window(frame: GuiObject)
    Theme.Paint(frame, Theme.panel, 3)
    frame.BackgroundTransparency = 0
    corner(frame, 14)
end

-- Zeile oder kleine Karte in einem Fenster (flach, ohne Verlauf).
function Kit.row(frame: GuiObject, color: Color3?)
    frame.BackgroundColor3 = color or Theme.ui.row
    frame.BackgroundTransparency = 0
    frame.BorderSizePixel = 0
    corner(frame, 10)
end

-- Knopf in einer der Arten oben. Nochmal aufrufen wechselt die Art (z. B. Reiter aktiv/inaktiv).
function Kit.button(button: TextButton, kind: string?)
    local key = kind or "normal"
    Theme.Paint(button, SWATCH[key] or Theme.slate, 2)
    button.BackgroundTransparency = 0
    button.AutoButtonColor = true
    button.Font = Theme.font.title
    button.TextColor3 = Theme.text
    corner(button, 10)
    if button:FindFirstChild("LetterOutline") == nil then
        local edge = Instance.new("UIStroke")
        edge.Name = "LetterOutline"
        edge.Color = Theme.ink
        edge.Thickness = 1.5
        edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
        edge.LineJoinMode = Enum.LineJoinMode.Round
        edge.Parent = button
    end
end

-- Flacher Knopf für Menüs, deren Farbe sich je Zustand ändert (kaufbar, gesperrt): runde Ecken und
-- dunkle Kontur, die Farbe setzt der Controller aus Theme.ui.
function Kit.flat(button: GuiButton)
    corner(button, 10)
    if button:FindFirstChild("DarkOutline") == nil then
        local outline = Instance.new("UIStroke")
        outline.Name = "DarkOutline"
        outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        outline.Color = Theme.ink
        outline.Thickness = 2
        outline.Parent = button
    end
end

-- Überschrift (Fenstertitel, Abschnitt): runde Schrift mit Kontur.
function Kit.title(label: TextLabel)
    label.Font = Theme.font.title
    label.TextColor3 = Theme.text
    if label:FindFirstChild("LetterOutline") == nil then
        local edge = Instance.new("UIStroke")
        edge.Name = "LetterOutline"
        edge.Color = Theme.ink
        edge.Thickness = 2
        edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
        edge.LineJoinMode = Enum.LineJoinMode.Round
        edge.Parent = label
    end
end

-- Farbe einer Seltenheit (Rand der Swatch aus Theme.finds), Rückfall: Nebentext.
function Kit.rarityColor(rarityId: string?): Color3
    local swatch = if rarityId ~= nil then Theme.finds[rarityId] else nil
    return if swatch ~= nil then swatch.rim else Theme.ui.muted
end

return Kit
