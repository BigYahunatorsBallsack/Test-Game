--!strict
-- Platzhalter-Optik der Kisten-Items (Paket 4.3). Echte Modelle folgen mit Paket 3.2.
-- Nur einfache Formen und Enum.Material-Namen, keine fremden Assets.
-- Skin = Umhang in der Hauptfarbe (colorHex) mit Schärpe in der Nebenfarbe (accentHex).
-- Begleiter = Figur aus `shape` ("Ball" oder "Block"), Größe in `size` (Studs).
-- Werkzeug-Variante = färbt die Teile des aktuellen Werkzeugs um (colorHex, accentHex).
-- Neon und Glass nur ab Seltenheit epic. Begleiter werden mit der Seltenheit größer.
-- Eine Zeile pro Item aus CrateItems, gleiche id und kind.

export type ItemLook = {
    id: string, -- Item-ID aus CrateItems
    kind: "skin" | "companion" | "toolVariant",
    colorHex: string, -- Hauptfarbe, "#RRGGBB"
    accentHex: string, -- Nebenfarbe
    material: string, -- Name aus Enum.Material (z. B. "Fabric", "Metal", "Glass", "Neon", "SmoothPlastic", "Sand", "Slate")
    shape: string?, -- nur companion: "Ball" oder "Block"
    size: number?, -- nur companion: Kantenlänge/Durchmesser in Studs, zwischen 0.8 und 2.2
}

local list: { ItemLook } = {
    -- common
    { id = "skin_common_1", kind = "skin", colorHex = "#C8A46E", accentHex = "#8B6B3E", material = "Fabric" },
    { id = "skin_common_2", kind = "skin", colorHex = "#9C8F7A", accentHex = "#5E5448", material = "Fabric" },
    { id = "companion_common_1", kind = "companion", colorHex = "#D9893B", accentHex = "#F3E3C3", material = "SmoothPlastic", shape = "Ball", size = 0.8 },
    { id = "toolVariant_common_1", kind = "toolVariant", colorHex = "#A7A9AC", accentHex = "#6D6F72", material = "Metal" },

    -- uncommon
    { id = "skin_uncommon_1", kind = "skin", colorHex = "#B5763A", accentHex = "#E0C080", material = "Fabric" },
    { id = "skin_uncommon_2", kind = "skin", colorHex = "#7A6A4F", accentHex = "#C2A878", material = "Fabric" },
    { id = "companion_uncommon_1", kind = "companion", colorHex = "#8DB35A", accentHex = "#E8D27A", material = "SmoothPlastic", shape = "Block", size = 1.0 },
    { id = "toolVariant_uncommon_1", kind = "toolVariant", colorHex = "#B87333", accentHex = "#E6A46A", material = "Metal" },

    -- rare
    { id = "skin_rare_1", kind = "skin", colorHex = "#2E8B57", accentHex = "#7FD1A0", material = "Fabric" },
    { id = "skin_rare_2", kind = "skin", colorHex = "#7EC8E3", accentHex = "#D6F2FF", material = "SmoothPlastic" },
    { id = "companion_rare_1", kind = "companion", colorHex = "#6B4F2A", accentHex = "#D9A441", material = "Slate", shape = "Block", size = 1.3 },
    { id = "toolVariant_rare_1", kind = "toolVariant", colorHex = "#A8D8EA", accentHex = "#FFFFFF", material = "SmoothPlastic" },
    { id = "companion_rare_2", kind = "companion", colorHex = "#C9B79C", accentHex = "#4A3F35", material = "SmoothPlastic", shape = "Ball", size = 1.4 },

    -- epic
    { id = "skin_epic_1", kind = "skin", colorHex = "#E0B040", accentHex = "#3B2A10", material = "Fabric" },
    { id = "skin_epic_2", kind = "skin", colorHex = "#F2C94C", accentHex = "#FFF4C2", material = "Glass" },
    { id = "companion_epic_1", kind = "companion", colorHex = "#8A8178", accentHex = "#5C554E", material = "SmoothPlastic", shape = "Block", size = 1.6 },
    { id = "toolVariant_epic_1", kind = "toolVariant", colorHex = "#C0C7CF", accentHex = "#E8A33D", material = "Metal" },

    -- legendary
    { id = "skin_legendary_1", kind = "skin", colorHex = "#1A1A22", accentHex = "#D4AF37", material = "Fabric" },
    { id = "companion_legendary_1", kind = "companion", colorHex = "#2B2D42", accentHex = "#8D99AE", material = "Neon", shape = "Ball", size = 1.8 },
    { id = "toolVariant_legendary_1", kind = "toolVariant", colorHex = "#3D2C8D", accentHex = "#FFD700", material = "Neon" },

    -- mythic
    { id = "skin_mythic_1", kind = "skin", colorHex = "#FFF8E1", accentHex = "#FFB300", material = "Neon" },
    { id = "companion_mythic_1", kind = "companion", colorHex = "#7B5E3A", accentHex = "#C68B59", material = "SmoothPlastic", shape = "Block", size = 2.0 },
    { id = "toolVariant_mythic_1", kind = "toolVariant", colorHex = "#00E5FF", accentHex = "#FF4FD8", material = "Neon" },

    -- Event-Pool
    -- uncommon
    { id = "skin_uncommon_3", kind = "skin", colorHex = "#D4B483", accentHex = "#3F7D8C", material = "Fabric" },
    { id = "companion_uncommon_2", kind = "companion", colorHex = "#E07B39", accentHex = "#FFFFFF", material = "SmoothPlastic", shape = "Ball", size = 1.0 },
    { id = "toolVariant_uncommon_2", kind = "toolVariant", colorHex = "#4E9A8F", accentHex = "#F2D16B", material = "Metal" },
    -- rare
    { id = "skin_rare_3", kind = "skin", colorHex = "#5B3E7A", accentHex = "#E8C36A", material = "Fabric" },
    { id = "companion_rare_3", kind = "companion", colorHex = "#C8842E", accentHex = "#2F2A24", material = "SmoothPlastic", shape = "Block", size = 1.3 },
    { id = "toolVariant_rare_2", kind = "toolVariant", colorHex = "#9BE7D6", accentHex = "#FFFFFF", material = "SmoothPlastic" },
    -- epic
    { id = "skin_epic_3", kind = "skin", colorHex = "#1F7A6B", accentHex = "#B6F5E0", material = "Glass" },
    { id = "companion_epic_2", kind = "companion", colorHex = "#EDEFF2", accentHex = "#9FD8FF", material = "Glass", shape = "Ball", size = 1.6 },
    { id = "toolVariant_epic_2", kind = "toolVariant", colorHex = "#7D4E9E", accentHex = "#F4A6E1", material = "Neon" },
    -- legendary
    { id = "skin_legendary_2", kind = "skin", colorHex = "#4B0F2E", accentHex = "#FFD27F", material = "Fabric" },
    { id = "companion_legendary_2", kind = "companion", colorHex = "#2F4F6F", accentHex = "#E0F7FF", material = "Neon", shape = "Block", size = 1.8 },
    { id = "toolVariant_legendary_2", kind = "toolVariant", colorHex = "#8FE3FF", accentHex = "#FFFFFF", material = "Glass" },
    -- mythic
    { id = "skin_mythic_2", kind = "skin", colorHex = "#FFE9A8", accentHex = "#FF6F00", material = "Neon" },
    { id = "companion_mythic_2", kind = "companion", colorHex = "#4A2C17", accentHex = "#FFB84D", material = "SmoothPlastic", shape = "Ball", size = 2.2 },
    { id = "toolVariant_mythic_2", kind = "toolVariant", colorHex = "#FF3D7F", accentHex = "#33FFD1", material = "Neon" },
}

local byId: { [string]: ItemLook } = {}
for _, look in list do
    byId[look.id] = look
end

return {
    list = list,
    byId = byId,
}
