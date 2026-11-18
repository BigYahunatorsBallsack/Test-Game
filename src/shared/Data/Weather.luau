--!strict
-- Wetter je Zone (Paket 2.5). Das Wetter läuft als fester Zyklus aus der Serverzeit
-- (workspace:GetServerTimeNow()), alle Clients sehen deshalb dasselbe Wetter, ohne dass der
-- Server etwas senden muss. Logic/Weather rechnet es aus, Controllers/Weather zeigt es.
-- Alle Zahlen sind Startwerte für den Handy-Test. Zeiten in Sekunden.
--
-- Wirkung auf das Spiel: In Paket 2.5 ist das Wetter nur Optik. `findChanceBonusBp` (Hundertstel-
-- Prozent) liest Paket 2.6 für die Fundchance (Oase: Regen erhöht die Fundchance).

export type Schedule = {
    kind: string, -- Eintrag in `looks`
    cycleSeconds: number, -- Länge eines Zyklus
    activeSeconds: number, -- so lange ist das Wetter in jedem Zyklus aktiv (höchstens cycleSeconds)
    offsetSeconds: number, -- Versatz des Zyklusbeginns
    findChanceBonusBp: number, -- Fundchance-Bonus während des Wetters (Paket 2.6)
}

export type Look = {
    atmosphereDensity: number, -- 0 bis 1
    atmosphereHaze: number, -- 0 bis 10
    atmosphereColorHex: string,
    brightness: number, -- Änderung der Helligkeit, -1 bis 1
    saturation: number, -- Änderung der Sättigung, -1 bis 1
    tintHex: string,
    particleRate: number, -- Partikel pro Sekunde um die Kamera (0 = keine)
    particleSpeed: number, -- Fallgeschwindigkeit in Studs pro Sekunde
    particleSize: number,
    particleColorHex: string,
    particleWindStuds: number, -- seitliche Geschwindigkeit
}

local Weather = {
    -- Ein- und Ausblenden: Dauer in Sekunden. Die Stärke läuft in dieser Zeit von 0 auf 1.
    fadeSeconds = 4,

    -- Zone-ID -> Zeitplan. Zonen ohne Eintrag haben nie Wetter (Dünenmeer).
    zones = {
        oasis = { kind = "rain", cycleSeconds = 480, activeSeconds = 90, offsetSeconds = 0, findChanceBonusBp = 1500 },
        canyon = { kind = "dustwind", cycleSeconds = 420, activeSeconds = 100, offsetSeconds = 120, findChanceBonusBp = 0 },
        salt_lake = { kind = "fog", cycleSeconds = 600, activeSeconds = 180, offsetSeconds = 60, findChanceBonusBp = 0 },
        -- Dunst ist dauerhaft aktiv (activeSeconds gleich cycleSeconds).
        ruins = { kind = "haze", cycleSeconds = 600, activeSeconds = 600, offsetSeconds = 0, findChanceBonusBp = 0 },
    } :: { [string]: Schedule },

    looks = {
        rain = {
            atmosphereDensity = 0.45, atmosphereHaze = 3, atmosphereColorHex = "#8A9BA8",
            brightness = -0.08, saturation = -0.15, tintHex = "#B8C8D8",
            particleRate = 90, particleSpeed = 55, particleSize = 0.25, particleColorHex = "#C8D8E8", particleWindStuds = 4,
        },
        dustwind = {
            atmosphereDensity = 0.5, atmosphereHaze = 4, atmosphereColorHex = "#C9A06A",
            brightness = -0.05, saturation = -0.05, tintHex = "#E8C890",
            particleRate = 70, particleSpeed = 6, particleSize = 0.6, particleColorHex = "#D8B078", particleWindStuds = 40,
        },
        fog = {
            atmosphereDensity = 0.65, atmosphereHaze = 6, atmosphereColorHex = "#DCE8F0",
            brightness = 0.02, saturation = -0.2, tintHex = "#E0ECF4",
            particleRate = 0, particleSpeed = 0, particleSize = 0, particleColorHex = "#FFFFFF", particleWindStuds = 0,
        },
        haze = {
            atmosphereDensity = 0.4, atmosphereHaze = 5, atmosphereColorHex = "#3A3340",
            brightness = -0.12, saturation = -0.1, tintHex = "#C8B8D8",
            particleRate = 0, particleSpeed = 0, particleSize = 0, particleColorHex = "#FFFFFF", particleWindStuds = 0,
        },
    } :: { [string]: Look },

    -- Aussehen ohne Wetter (Standardwerte der Zone, die Controllers/Weather zurückblendet).
    clear = {
        atmosphereDensity = 0.3,
        atmosphereHaze = 0,
        atmosphereColorHex = "#C7D3E0",
        brightness = 0,
        saturation = 0,
        tintHex = "#FFFFFF",
    },
}

return Weather
