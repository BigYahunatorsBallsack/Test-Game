--!strict
-- Aussehen der sechs Werkzeugstufen (Paket 2.4). Jede Stufe ist deutlich größer als die vorige.
-- Die Modelle bestehen nur aus einfachen Formen, es werden keine fremden Assets geladen.
-- Alle Zahlen sind Startwerte für den Handy-Test. Längen in Studs, Winkel in Grad.
--
-- Koordinaten der Teile: relativ zum Charakter, x nach rechts, y Höhe über dem Boden,
-- z nach vorn ist negativ (hinter dem Charakter ist z positiv). Die Zylinderachse in Roblox
-- ist die x-Achse, die Größe `size.x` ist also die Länge des Zylinders.
-- Die Hand hat kein Modell, nur Körner (Staub).

export type Part = {
    shape: string, -- "Block", "Cylinder" oder "Ball"
    size: { x: number, y: number, z: number },
    offset: { x: number, y: number, z: number },
    rotation: { x: number, y: number, z: number }?,
    colorHex: string,
    material: string, -- Name aus Enum.Material
}

export type Dust = {
    count: number, -- Partikel pro Graben
    size: number, -- Startgröße eines Partikels
}

export type Look = {
    toolId: string, -- Eintrag in Tools
    footprint: number, -- Ausdehnung des Werkzeugs in Studs (steigt streng mit der Stufe)
    parts: { Part },
    dust: Dust,
    cameraBonusStuds: number, -- zusätzlicher Kameraabstand, damit große Maschinen ins Bild passen
}

local list: { Look } = {
    {
        toolId = "hand",
        footprint = 0.5,
        parts = {},
        dust = { count = 6, size = 0.3 },
        cameraBonusStuds = 0,
    },
    {
        toolId = "shovel",
        footprint = 1.6,
        parts = {
            {
                shape = "Block",
                size = { x = 0.25, y = 3.2, z = 0.25 },
                offset = { x = 1.5, y = 2.2, z = -0.8 },
                rotation = { x = -25, y = 0, z = 0 },
                colorHex = "#8A5A2B",
                material = "Wood",
            },
            {
                shape = "Block",
                size = { x = 1, y = 0.12, z = 1.3 },
                offset = { x = 1.5, y = 0.6, z = -1.6 },
                rotation = { x = -25, y = 0, z = 0 },
                colorHex = "#A8A8A8",
                material = "Metal",
            },
        },
        dust = { count = 8, size = 0.45 },
        cameraBonusStuds = 0,
    },
    {
        toolId = "bucket_chain",
        footprint = 3.2,
        parts = {
            {
                shape = "Block",
                size = { x = 0.5, y = 0.5, z = 4.5 },
                offset = { x = 2.4, y = 2.4, z = -2.2 },
                rotation = { x = 25, y = 0, z = 0 },
                colorHex = "#5C6B73",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 1, y = 0.9, z = 0.9 },
                offset = { x = 2.4, y = 0.9, z = -3.9 },
                colorHex = "#C98A2B",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 1, y = 0.9, z = 0.9 },
                offset = { x = 2.4, y = 2.3, z = -2.1 },
                colorHex = "#C98A2B",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 1.6, y = 1.2, z = 1.6 },
                offset = { x = 2.4, y = 3.6, z = -0.3 },
                colorHex = "#7A4A1E",
                material = "Wood",
            },
        },
        dust = { count = 11, size = 0.65 },
        cameraBonusStuds = 1,
    },
    {
        toolId = "mini_digger",
        footprint = 6,
        parts = {
            {
                shape = "Block",
                size = { x = 1.2, y = 1.3, z = 5 },
                offset = { x = -2, y = 0.65, z = 5 },
                colorHex = "#2F2F2F",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 1.2, y = 1.3, z = 5 },
                offset = { x = 2, y = 0.65, z = 5 },
                colorHex = "#2F2F2F",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 4, y = 1.6, z = 4.5 },
                offset = { x = 0, y = 2.1, z = 5 },
                colorHex = "#E0A21B",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 2.2, y = 1.8, z = 2.2 },
                offset = { x = 0, y = 3.8, z = 5.6 },
                colorHex = "#F2C84B",
                material = "Glass",
            },
            {
                shape = "Block",
                size = { x = 0.6, y = 0.6, z = 4.5 },
                offset = { x = 0, y = 3, z = 1.6 },
                rotation = { x = -20, y = 0, z = 0 },
                colorHex = "#E0A21B",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 1.8, y = 1.1, z = 1.4 },
                offset = { x = 0, y = 1.2, z = -0.3 },
                colorHex = "#4A4A4A",
                material = "Metal",
            },
        },
        dust = { count = 15, size = 0.9 },
        cameraBonusStuds = 2.5,
    },
    {
        toolId = "vacuum_robot",
        footprint = 9,
        parts = {
            {
                shape = "Ball",
                size = { x = 6, y = 6, z = 6 },
                offset = { x = 0, y = 3.4, z = 7 },
                colorHex = "#DDE4EA",
                material = "SmoothPlastic",
            },
            {
                shape = "Cylinder",
                size = { x = 0.5, y = 7, z = 7 },
                offset = { x = 0, y = 0.6, z = 7 },
                rotation = { x = 0, y = 0, z = 90 },
                colorHex = "#2D3A45",
                material = "Metal",
            },
            {
                shape = "Cylinder",
                size = { x = 6.5, y = 1.2, z = 1.2 },
                offset = { x = 0, y = 2.2, z = 2.6 },
                rotation = { x = 20, y = 90, z = 0 },
                colorHex = "#3E7CB1",
                material = "SmoothPlastic",
            },
            {
                shape = "Block",
                size = { x = 4.5, y = 0.5, z = 2.4 },
                offset = { x = 0, y = 0.3, z = -1.6 },
                colorHex = "#3E7CB1",
                material = "SmoothPlastic",
            },
            {
                shape = "Ball",
                size = { x = 1.4, y = 1.4, z = 1.4 },
                offset = { x = 0, y = 4.4, z = 4.6 },
                colorHex = "#7FD1FF",
                material = "Neon",
            },
        },
        dust = { count = 20, size = 1.2 },
        cameraBonusStuds = 4,
    },
    {
        toolId = "mega_machine",
        footprint = 16,
        parts = {
            {
                shape = "Block",
                size = { x = 3, y = 3, z = 14 },
                offset = { x = -6, y = 1.5, z = 10 },
                colorHex = "#262626",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 3, y = 3, z = 14 },
                offset = { x = 6, y = 1.5, z = 10 },
                colorHex = "#262626",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 11, y = 5, z = 12 },
                offset = { x = 0, y = 5.5, z = 10 },
                colorHex = "#B5481C",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 5, y = 3.6, z = 4.4 },
                offset = { x = 0, y = 10.8, z = 12 },
                colorHex = "#E8B04A",
                material = "Glass",
            },
            {
                shape = "Cylinder",
                size = { x = 2, y = 2.2, z = 2.2 },
                offset = { x = 3.4, y = 12, z = 7 },
                rotation = { x = 0, y = 0, z = 90 },
                colorHex = "#3A3A3A",
                material = "Metal",
            },
            {
                shape = "Cylinder",
                size = { x = 3, y = 9, z = 9 },
                offset = { x = 0, y = 5, z = 0.2 },
                colorHex = "#7C7C7C",
                material = "Metal",
            },
            {
                shape = "Block",
                size = { x = 1.2, y = 1.2, z = 5 },
                offset = { x = 0, y = 6, z = 4 },
                colorHex = "#7C7C7C",
                material = "Metal",
            },
        },
        dust = { count = 28, size = 1.6 },
        cameraBonusStuds = 6,
    },
}

local byToolId: { [string]: Look } = {}
for _, look in list do
    byToolId[look.toolId] = look
end

return {
    list = list,
    byToolId = byToolId,
    defaultToolId = "hand",

    -- Wechsel-Animation bei einer neuen, höheren Stufe.
    change = {
        popSeconds = 0.45, -- Dauer des Einblendens (Größe von popStartScale auf 1)
        popStartScale = 0.2,
        popEasing = "Back", -- Name aus Enum.EasingStyle
        burstCount = 20, -- Staubwolke beim Wechsel
        cameraSeconds = 0.8, -- so lange gleitet der Kameraabstand zum neuen Wert
    },

    limits = {
        maxCameraBonusStuds = 12,
        -- Höchstens so viele Partikel auf einmal (Staub beim Graben plus Wechsel-Wolke).
        maxParticlesPerEmit = 60,
        minStepFactor = 1.25, -- jede Stufe mindestens so viel größer wie die vorige
    },
}
