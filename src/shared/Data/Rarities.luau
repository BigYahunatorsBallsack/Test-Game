--!strict
-- Seltenheitsstufen (Konzept: "Welt und Zonen", Tabelle der Fundstück-Stufen).
-- Die Reihenfolge der Liste ist die Rangfolge: Index 1 = niedrigste Stufe.
-- "Oder besser" (z. B. bei der Pity) heißt: Rang >= Rang der genannten Stufe.
-- Farben sind Hex-Text (keine Roblox-Typen), die Umrechnung macht der Client.

export type Rarity = {
    id: string,
    rank: number,
    name: string, -- Anzeigename für Spieler
    colorHex: string,
    valueFactor: number, -- Wertfaktor eines Fundstücks dieser Stufe
}

local list: { Rarity } = {
    { id = "common", rank = 1, name = "Gewöhnlich", colorHex = "#9E9E9E", valueFactor = 1 },
    { id = "uncommon", rank = 2, name = "Ungewöhnlich", colorHex = "#4CAF50", valueFactor = 4 },
    { id = "rare", rank = 3, name = "Selten", colorHex = "#2196F3", valueFactor = 15 },
    { id = "epic", rank = 4, name = "Episch", colorHex = "#9C27B0", valueFactor = 60 },
    { id = "legendary", rank = 5, name = "Legendär", colorHex = "#FF9800", valueFactor = 300 },
    { id = "mythic", rank = 6, name = "Mythisch", colorHex = "#F44336", valueFactor = 1500 },
}

local byId: { [string]: Rarity } = {}
for _, rarity in list do
    byId[rarity.id] = rarity
end

return {
    list = list,
    byId = byId,
}
