--!strict
-- Aussehen der sechs Werkzeugstufen (Paket 2.4). Jede Stufe ist deutlich größer als die vorige.
-- Die Modelle bestehen nur aus einfachen Formen, es werden keine fremden Assets geladen.
-- Alle Zahlen sind Startwerte für den Handy-Test. Längen in Studs, Winkel in Grad.
--
-- Koordinaten: relativ zum Charakter, x nach rechts, y Höhe über dem Boden, z nach vorn ist
-- negativ (hinter dem Charakter ist z positiv). Die Maschinen stehen VOR und NEBEN dem Charakter,
-- nie hinter ihm, sonst würden sie der Kamera die Sicht auf den Spieler nehmen (Logic/ToolLook
-- prüft das). Die Zylinderachse in Roblox ist die x-Achse, `size.x` ist also die Länge.
-- Die Hand hat kein Modell, nur Körner (Staub).
--
-- `workPoint`: Arbeitsspitze (x und z). Dort entsteht das Loch. Das Loch (Radius aus
-- Terrain.holeByTool) darf den Charakter nicht erreichen.
-- `motions`: Bewegung einzelner Teile, nur solange gesammelt wird.
--   swing  schwingt um die Achse `axis` (x, y oder z), `amplitude` in Grad, `period` in Sekunden
--   spin   dreht um die Achse `axis`, eine Umdrehung pro `period` Sekunden (`amplitude` zählt nicht)
--   bob    wippt entlang der Achse `axis`, `amplitude` in Studs
--   slide  läuft entlang des Vektors `vector` von -amplitude nach +amplitude und springt zurück
-- `sandFlow`: wie der Sand sich bewegt (Partikel an der Maschine, nur beim Sammeln).
--   Von `from` nach `to` (Punkte wie bei den Teilen), `rate` Partikel pro Sekunde (0 = aus,
--   dann gräbt nur der Staub aus `dust`), `speed` in Studs pro Sekunde, `lifetime` in Sekunden.

export type Vec = { x: number, y: number, z: number }

export type Part = {
    shape: string, -- "Block", "Cylinder" oder "Ball"
    size: Vec,
    offset: Vec,
    rotation: Vec?,
    colorHex: string,
    material: string, -- Name aus Enum.Material
}

export type Motion = {
    part: number, -- Nummer des Teils in `parts`
    kind: string, -- swing, spin, bob oder slide
    axis: string?, -- "x", "y" oder "z" (nicht bei slide)
    vector: Vec?, -- nur bei slide
    amplitude: number,
    period: number,
}

export type SandFlow = {
    kind: string, -- spray, conveyor, cloud, suction oder eruption
    from: Vec,
    to: Vec,
    rate: number,
    speed: number,
    lifetime: number,
    spread: number, -- Streuwinkel in Grad
    size: number,
}

export type Dust = {
    count: number, -- Partikel pro Graben
    size: number, -- Startgröße eines Partikels
}

export type Look = {
    toolId: string, -- Eintrag in Tools
    footprint: number, -- Ausdehnung des Werkzeugs in Studs (steigt streng mit der Stufe)
    workPoint: { x: number, z: number },
    parts: { Part },
    motions: { Motion },
    sandFlow: SandFlow,
    dust: Dust,
    cameraBonusStuds: number, -- zusätzlicher Kameraabstand, damit große Maschinen ins Bild passen
    loopSoundId: string, -- Arbeitsgeräusch, leer = Platzhalter bis Paket 3.5
}

local list: { Look } = {
    {
        toolId = "hand",
        footprint = 0.5,
        workPoint = { x = 0, z = -4.5 },
        parts = {},
        motions = {},
        sandFlow = { kind = "spray", from = { x = 0, y = 0, z = -4.5 }, to = { x = 0, y = 1, z = -4.5 }, rate = 0, speed = 5, lifetime = 0.5, spread = 40, size = 0.3 },
        dust = { count = 6, size = 0.3 },
        cameraBonusStuds = 0,
        loopSoundId = "",
    },
    {
        toolId = "shovel",
        footprint = 1.6,
        workPoint = { x = 0.6, z = -4.8 },
        parts = {
            {
                shape = "Block",
                size = { x = 0.25, y = 3.4, z = 0.25 },
                offset = { x = 0.6, y = 2.0, z = -2.9 },
                rotation = { x = 60, y = 0, z = 0 },
                colorHex = "#8A5A2B",
                material = "Wood",
            },
            {
                shape = "Block",
                size = { x = 1.1, y = 0.12, z = 1.4 },
                offset = { x = 0.6, y = 0.9, z = -4.3 },
                rotation = { x = 20, y = 0, z = 0 },
                colorHex = "#A8A8A8",
                material = "Metal",
            },
        },
        motions = {
            { part = 1, kind = "swing", axis = "x", amplitude = 8, period = 0.7 },
            { part = 2, kind = "swing", axis = "x", amplitude = 8, period = 0.7 },
        },
        sandFlow = { kind = "spray", from = { x = 0.6, y = 0.9, z = -4.8 }, to = { x = 0.6, y = 2, z = -4.8 }, rate = 0, speed = 8, lifetime = 0.5, spread = 40, size = 0.45 },
        dust = { count = 8, size = 0.45 },
        cameraBonusStuds = 0,
        loopSoundId = "",
    },
    {
        toolId = "bucket_chain",
        footprint = 3.2,
        workPoint = { x = 0, z = -6.5 },
        parts = {
            { -- 1: Förderband, steigt zum Tank
                shape = "Block",
                size = { x = 0.6, y = 0.5, z = 5.5 },
                offset = { x = 0, y = 2.1, z = -4.2 },
                rotation = { x = -32, y = 0, z = 0 },
                colorHex = "#5C6B73",
                material = "Metal",
            },
            { -- 2: Eimer unten
                shape = "Block",
                size = { x = 1, y = 0.9, z = 0.9 },
                offset = { x = 0, y = 0.86, z = -6.18 },
                colorHex = "#C98A2B",
                material = "Metal",
            },
            { -- 3: Eimer Mitte
                shape = "Block",
                size = { x = 1, y = 0.9, z = 0.9 },
                offset = { x = 0, y = 2.1, z = -4.2 },
                colorHex = "#C98A2B",
                material = "Metal",
            },
            { -- 4: Tank
                shape = "Block",
                size = { x = 1.6, y = 1.2, z = 1.6 },
                offset = { x = 0, y = 4.2, z = -2.6 },
                colorHex = "#7A4A1E",
                material = "Wood",
            },
        },
        motions = {
            { part = 2, kind = "slide", vector = { x = 0, y = 0.53, z = 0.85 }, amplitude = 2.2, period = 1.4 },
            { part = 3, kind = "slide", vector = { x = 0, y = 0.53, z = 0.85 }, amplitude = 2.2, period = 1.4 },
        },
        sandFlow = { kind = "conveyor", from = { x = 0, y = 0.9, z = -6.2 }, to = { x = 0, y = 3.6, z = -2.6 }, rate = 10, speed = 6, lifetime = 0.9, spread = 8, size = 0.5 },
        dust = { count = 11, size = 0.65 },
        cameraBonusStuds = 1,
        loopSoundId = "",
    },
    {
        toolId = "mini_digger",
        footprint = 6,
        workPoint = { x = 0, z = -8 },
        parts = {
            { -- 1: Kette links
                shape = "Block",
                size = { x = 1.2, y = 1.3, z = 5 },
                offset = { x = -2, y = 0.65, z = -4.5 },
                colorHex = "#2F2F2F",
                material = "Metal",
            },
            { -- 2: Kette rechts
                shape = "Block",
                size = { x = 1.2, y = 1.3, z = 5 },
                offset = { x = 2, y = 0.65, z = -4.5 },
                colorHex = "#2F2F2F",
                material = "Metal",
            },
            { -- 3: Rumpf
                shape = "Block",
                size = { x = 4, y = 1.6, z = 4.5 },
                offset = { x = 0, y = 2.1, z = -4.5 },
                colorHex = "#E0A21B",
                material = "Metal",
            },
            { -- 4: Kabine
                shape = "Block",
                size = { x = 2.2, y = 1.8, z = 2.2 },
                offset = { x = 0, y = 3.8, z = -3.4 },
                colorHex = "#F2C84B",
                material = "Glass",
            },
            { -- 5: Arm
                shape = "Block",
                size = { x = 0.6, y = 0.6, z = 4.7 },
                offset = { x = 0, y = 2.2, z = -5.5 },
                rotation = { x = -31, y = 0, z = 0 },
                colorHex = "#E0A21B",
                material = "Metal",
            },
            { -- 6: Schaufel
                shape = "Block",
                size = { x = 1.6, y = 1, z = 1.2 },
                offset = { x = 0, y = 1, z = -7.6 },
                colorHex = "#4A4A4A",
                material = "Metal",
            },
        },
        motions = {
            { part = 5, kind = "swing", axis = "x", amplitude = 6, period = 1.2 },
            { part = 6, kind = "bob", axis = "y", amplitude = 0.3, period = 1.2 },
        },
        sandFlow = { kind = "cloud", from = { x = 0, y = 1, z = -8 }, to = { x = 0, y = 2, z = -8 }, rate = 12, speed = 2, lifetime = 1.6, spread = 60, size = 2.2 },
        dust = { count = 15, size = 0.9 },
        cameraBonusStuds = 2.5,
        loopSoundId = "",
    },
    {
        toolId = "vacuum_robot",
        footprint = 9,
        workPoint = { x = 0, z = -10 },
        parts = {
            { -- 1: Rumpf
                shape = "Ball",
                size = { x = 5, y = 5, z = 5 },
                offset = { x = 0, y = 2.8, z = -5.5 },
                colorHex = "#DDE4EA",
                material = "SmoothPlastic",
            },
            { -- 2: Rad links
                shape = "Cylinder",
                size = { x = 0.6, y = 2.4, z = 2.4 },
                offset = { x = -2.8, y = 1.2, z = -5.5 },
                colorHex = "#2D3A45",
                material = "Metal",
            },
            { -- 3: Rad rechts
                shape = "Cylinder",
                size = { x = 0.6, y = 2.4, z = 2.4 },
                offset = { x = 2.8, y = 1.2, z = -5.5 },
                colorHex = "#2D3A45",
                material = "Metal",
            },
            { -- 4: Rüssel
                shape = "Block",
                size = { x = 0.9, y = 0.9, z = 4 },
                offset = { x = 0, y = 1.5, z = -8 },
                rotation = { x = 12, y = 0, z = 0 },
                colorHex = "#3E7CB1",
                material = "SmoothPlastic",
            },
            { -- 5: Düse
                shape = "Block",
                size = { x = 3.5, y = 0.5, z = 2.4 },
                offset = { x = 0, y = 0.3, z = -9.6 },
                colorHex = "#3E7CB1",
                material = "SmoothPlastic",
            },
            { -- 6: Lampe
                shape = "Ball",
                size = { x = 1.2, y = 1.2, z = 1.2 },
                offset = { x = 0, y = 5.5, z = -5.5 },
                colorHex = "#7FD1FF",
                material = "Neon",
            },
        },
        motions = {
            { part = 1, kind = "bob", axis = "y", amplitude = 0.15, period = 1 },
            { part = 2, kind = "spin", axis = "x", amplitude = 0, period = 1.5 },
            { part = 3, kind = "spin", axis = "x", amplitude = 0, period = 1.5 },
            { part = 4, kind = "swing", axis = "x", amplitude = 6, period = 0.9 },
        },
        sandFlow = { kind = "suction", from = { x = 0, y = 0.5, z = -12.8 }, to = { x = 0, y = 1.2, z = -9.8 }, rate = 14, speed = 7, lifetime = 0.45, spread = 20, size = 0.7 },
        dust = { count = 20, size = 1.2 },
        cameraBonusStuds = 4,
        loopSoundId = "",
    },
    {
        toolId = "mega_machine",
        footprint = 16,
        workPoint = { x = 0, z = -16 },
        parts = {
            { -- 1: Kette links
                shape = "Block",
                size = { x = 3, y = 3, z = 14 },
                offset = { x = -6, y = 1.5, z = -9.5 },
                colorHex = "#262626",
                material = "Metal",
            },
            { -- 2: Kette rechts
                shape = "Block",
                size = { x = 3, y = 3, z = 14 },
                offset = { x = 6, y = 1.5, z = -9.5 },
                colorHex = "#262626",
                material = "Metal",
            },
            { -- 3: Rumpf
                shape = "Block",
                size = { x = 11, y = 5, z = 10 },
                offset = { x = 0, y = 5.5, z = -9.5 },
                colorHex = "#B5481C",
                material = "Metal",
            },
            { -- 4: Kabine
                shape = "Block",
                size = { x = 5, y = 3.6, z = 4.4 },
                offset = { x = 0, y = 9.8, z = -6.5 },
                colorHex = "#E8B04A",
                material = "Glass",
            },
            { -- 5: Schornstein
                shape = "Cylinder",
                size = { x = 3, y = 2, z = 2 },
                offset = { x = 3.4, y = 9.5, z = -9 },
                rotation = { x = 0, y = 0, z = 90 },
                colorHex = "#3A3A3A",
                material = "Metal",
            },
            { -- 6: Schaufelrad
                shape = "Cylinder",
                size = { x = 3, y = 9, z = 9 },
                offset = { x = 0, y = 4.5, z = -15 },
                colorHex = "#7C7C7C",
                material = "Metal",
            },
            { -- 7: Arm zum Rad
                shape = "Block",
                size = { x = 1.2, y = 1.2, z = 4 },
                offset = { x = 0, y = 5.5, z = -12.5 },
                colorHex = "#7C7C7C",
                material = "Metal",
            },
        },
        motions = {
            { part = 6, kind = "spin", axis = "x", amplitude = 0, period = 2.5 },
            { part = 5, kind = "bob", axis = "y", amplitude = 0.2, period = 0.6 },
        },
        sandFlow = { kind = "eruption", from = { x = 0, y = 2, z = -16 }, to = { x = 0, y = 12, z = -16 }, rate = 18, speed = 14, lifetime = 1.2, spread = 25, size = 1.6 },
        dust = { count = 28, size = 1.6 },
        cameraBonusStuds = 6,
        loopSoundId = "",
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

    -- Sichtweite: weiter entfernte Spieler sehen die Maschine ohne Bewegung und ohne Sandfluss.
    view = {
        motionDistanceStuds = 150,
        farUpdateSeconds = 0.2, -- so oft folgt ein weit entferntes Modell seinem Spieler
    },

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
        maxParts = 12, -- Teile je Modell
        maxFlowParticles = 80, -- gleichzeitig lebende Sandfluss-Partikel je Modell (rate * lifetime)
        -- Der Charakter als Quader um den Mittelpunkt am Boden (x und z ±halfWidth).
        characterBox = { halfWidth = 1.2, height = 5.5 },
        -- Kamera-Gang hinter dem Charakter: hier darf kein Teil liegen (x ±halfWidth, z nach hinten).
        cameraLane = { halfWidth = 3, length = 20 },
        flowKinds = { "spray", "conveyor", "cloud", "suction", "eruption" },
        motionKinds = { "swing", "spin", "bob", "slide" },
    },
}
