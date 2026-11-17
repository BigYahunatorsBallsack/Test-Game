--!strict
-- Sandsorten je Zone (Konzept: "Welt und Zonen"). Der Preisfaktor ist ein Vielfaches
-- des Grundpreises pro Sand (Economy.baseCoinsPerSand).
-- Die Hex-Farben sind vorläufig, bis der Stil-Guide (Paket 0.4) steht.

export type SandType = {
    id: string,
    name: string, -- Anzeigename für Spieler
    priceFactor: number,
    colorHex: string,
}

local list: { SandType } = {
    { id = "yellow", name = "Gelber Sand", priceFactor = 1, colorHex = "#E6C875" },
    { id = "red", name = "Roter Sand", priceFactor = 3, colorHex = "#C2573B" },
    { id = "white", name = "Weißer Sand", priceFactor = 10, colorHex = "#F2EEE3" },
    { id = "crystal", name = "Kristallsand", priceFactor = 40, colorHex = "#8FD6E8" },
    { id = "black", name = "Schwarzer Sand", priceFactor = 150, colorHex = "#2B2B33" },
}

local byId: { [string]: SandType } = {}
for _, sandType in list do
    byId[sandType.id] = sandType
end

return {
    list = list,
    byId = byId,
}
