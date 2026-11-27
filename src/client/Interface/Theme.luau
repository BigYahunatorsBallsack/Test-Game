--!strict
export type Swatch = { fill: ColorSequence, rim: Color3 }
local rgb = Color3.fromRGB
local Theme = {}

local function swatch(top: Color3, base: Color3, shade: Color3, rim: Color3): Swatch
    local fill = ColorSequence.new({
        ColorSequenceKeypoint.new(0, top),
        ColorSequenceKeypoint.new(.67, base),
        ColorSequenceKeypoint.new(.87, base),
        ColorSequenceKeypoint.new(.93, shade),
        ColorSequenceKeypoint.new(1, shade),
    })
    return {fill = fill, rim = rim}
end

Theme.ink = rgb(19,25,32)
Theme.text = rgb(255,251,235)
Theme.panel = swatch(rgb(48,81,85),rgb(28,50,61),rgb(23,36,47),rgb(108,171,170))
Theme.slate = swatch(rgb(101,129,140),rgb(60,88,103),rgb(36,54,74),rgb(170,205,216))
Theme.teal = swatch(rgb(125,246,219),rgb(25,166,157),rgb(18,103,111),rgb(168,255,230))
Theme.gold = swatch(rgb(255,241,156),rgb(246,171,49),rgb(170,82,21),rgb(255,236,145))
Theme.clay = swatch(rgb(255,161,121),rgb(216,83,61),rgb(139,36,44),rgb(255,175,142))
Theme.finds = {
    common=swatch(rgb(116,161,166),rgb(63,103,116),rgb(39,61,85),rgb(165,209,208)),
    uncommon=swatch(rgb(153,224,104),rgb(62,153,88),rgb(22,76,66),rgb(195,251,123)),
    rare=swatch(rgb(130,214,255),rgb(54,127,209),rgb(30,57,130),rgb(170,226,255)),
    epic=swatch(rgb(231,157,255),rgb(143,78,203),rgb(79,40,132),rgb(239,182,255)),
    legendary=Theme.gold,
    mythic=Theme.clay,
} :: {[string]: Swatch}

-- Flache Farben für alle Menüs (Überarbeitung Ü5: ein Stil). Controller setzen keine eigenen Farben,
-- sie nehmen diese hier (Prüfung in tests/uitheme.spec.luau).
Theme.ui = {
    backdrop = rgb(14,22,29), -- abgedunkelter Hintergrund hinter Fenstern
    panel = rgb(28,50,61), -- Fenster und Karten
    row = rgb(45,74,88), -- Zeilen in einem Fenster
    slot = rgb(23,36,47), -- leere Plätze, Spuren
    button = rgb(60,88,103), -- normaler Knopf
    text = Theme.text,
    muted = rgb(190,212,212), -- Nebentext
    accent = rgb(255,222,108), -- Gold: Hauptaktion, Münzen, aktiver Reiter
    accentText = Theme.ink, -- Text auf Gold
    teal = rgb(25,166,157), -- Navigation, Auswahl
    good = rgb(153,224,104), -- fertig, Bonus, sauber
    warn = rgb(250,150,90), -- Hinweis, Kosten
    danger = rgb(250,109,74), -- voll, Fehler, Schließen
    gem = rgb(130,214,255), -- Edelsteine
    ink = Theme.ink, -- Konturen, Schatten
    white = rgb(255,255,255),
    black = rgb(0,0,0),
}

-- Schriften: Überschriften und Knöpfe rund und kräftig, Fließtext gut lesbar.
Theme.font = {
    title = Enum.Font.FredokaOne,
    bold = Enum.Font.FredokaOne, -- Knöpfe, Namen, Zahlen
    body = Enum.Font.Gotham, -- längerer Text (Beschreibungen, Quoten)
}

function Theme.Paint(item: GuiObject, color: Swatch, thickness: number?): UIStroke
    item.BackgroundColor3 = Color3.new(1, 1, 1)
    item.BorderSizePixel = 0
    local tint = item:FindFirstChild("ColorWash") :: UIGradient?
    if not tint then
        tint = Instance.new("UIGradient")
        tint.Name, tint.Rotation, tint.Parent = "ColorWash", 90, item
    end
    tint.Color = color.fill
    local outline = item:FindFirstChild("DarkOutline") :: UIStroke?
    if not outline then
        outline = Instance.new("UIStroke")
        outline.Name = "DarkOutline"
        outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        outline.Parent = item
    end
    outline.Color, outline.Thickness = Theme.ink, thickness or 3
    local rim = item:FindFirstChild("ColorRim") :: UIStroke?
    if not rim then
        rim = Instance.new("UIStroke")
        rim.Name = "ColorRim"
        rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        rim.BorderStrokePosition = Enum.BorderStrokePosition.Inner
        rim.Thickness = 1.5
        rim.Transparency = .2
        rim.Parent = item
    end
    rim.Color = color.rim
    return outline
end

function Theme.Lettering(item: TextLabel | TextButton, weight: number)
    item.Font = Enum.Font.FredokaOne
    item.TextColor3 = Theme.text
    local edge = Instance.new("UIStroke")
    edge.Name,edge.Color,edge.Thickness = "LetterOutline",Theme.ink,weight
    edge.ApplyStrokeMode,edge.LineJoinMode = Enum.ApplyStrokeMode.Contextual,Enum.LineJoinMode.Round
    edge.Parent = item
end

return Theme
