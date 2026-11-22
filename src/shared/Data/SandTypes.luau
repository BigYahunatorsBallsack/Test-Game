--!strict
-- Sandsorten je Zone (Konzept: "Welt und Zonen"). Der Preisfaktor ist ein Vielfaches
-- des Grundpreises pro Sand (Economy.baseCoinsPerSand).
-- Die Hex-Farben sind vorläufig, bis der Stil-Guide (Paket 0.4) steht.
-- Roblox kennt nur eine Farbe je Terrain-Material, deshalb hat jede Sorte ihr eigenes Material.

export type SandType = {
    id: string,
    name: string, -- Anzeigename für Spieler
    priceFactor: number,
    colorHex: string,
    terrainMaterial: string, -- Name aus Enum.Material, im Terrain der Zone (Paket 2.5)
}

local list: { SandType } = {
    { id = "yellow", name = "Gelber Sand", priceFactor = 1, colorHex = "#E6C875", terrainMaterial = "Sand" },
    { id = "red", name = "Roter Sand", priceFactor = 3, colorHex = "#C2573B", terrainMaterial = "Sandstone" },
    -- Saison-Sand (Paket 5.5): nur in der Event-Zone der Saison. Faktor 5 liegt zwischen Rot und Weiß
    -- (docs/balance/season_5_5.md: ein Bonus für frühe Spieler, kein Ersatz für Canyon und Salzsee);
    -- die Liste bleibt nach Faktor sortiert.
    { id = "season", name = "Saison-Sand", priceFactor = 5, colorHex = "#D98E4A", terrainMaterial = "Mud" },
    { id = "white", name = "Weißer Sand", priceFactor = 10, colorHex = "#F2EEE3", terrainMaterial = "Salt" },
    { id = "crystal", name = "Kristallsand", priceFactor = 40, colorHex = "#8FD6E8", terrainMaterial = "Glacier" },
    { id = "black", name = "Schwarzer Sand", priceFactor = 150, colorHex = "#2B2B33", terrainMaterial = "Basalt" },
}

local byId: { [string]: SandType } = {}
for _, sandType in list do
    byId[sandType.id] = sandType
end

return {
    list = list,
    byId = byId,
}
