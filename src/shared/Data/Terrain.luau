--!strict
-- Terrain-Verformung auf dem Client (Paket 1.4).
-- Alle Zahlen für Löcher, Nachwachsen, Budgets und den Bildraten-Wächter. Die Logik steht in
-- Logic/SandDig und Logic/PerfGuard, der Client-Controller Dig schreibt nur die Voxel.
-- Längen in Studs, Zeiten in Sekunden. Materialien sind Namen von Enum.Material als Text.
-- Startwerte für den Handy-Test, sie werden nach dem Test angepasst.

export type Hole = {
    radius: number, -- Radius der Kugel, die die Mulde formt (Breite der Mulde)
    depth: number, -- so tief schneidet ein einzelnes Graben in die Oberfläche
}

local Terrain = {
    -- Auflösung des Roblox-Terrains (fest 4 Studs). Blöcke müssen ein Vielfaches davon sein.
    voxelSize = 4,
    -- Kantenlänge der Blöcke, in denen der Client Originalzustand und Nachwachsen verwaltet.
    chunkSize = 16,
    -- Nur auf diesen Materialien entstehen Löcher.
    diggableMaterials = { "Sand" },

    dig = {
        -- Abstand zwischen zwei Löchern, solange gegraben wird.
        intervalSeconds = 0.35,
        -- Das Loch entsteht so weit vor dem Charakter.
        forwardStuds = 3.5,
        -- Strahl nach unten: Start über dem Boden und Länge.
        rayUpStuds = 6,
        rayLengthStuds = 24,
        -- Höchstens so tief unter der zuerst gemessenen Oberfläche (ungefähr, auf Voxel genau).
        maxDepthStuds = 4,
        -- Rasterweite, in der sich der Client die ursprüngliche Oberfläche merkt.
        surfaceCellStuds = 4,
    },

    -- Lochgröße je Werkzeug (ID aus Tools). Ein unbekanntes Werkzeug gräbt wie die Hand.
    holeByTool = {
        hand = { radius = 3, depth = 0.6 },
        shovel = { radius = 3.5, depth = 0.9 },
        bucket_chain = { radius = 4.5, depth = 1.1 },
        mini_digger = { radius = 6, depth = 1.4 },
        vacuum_robot = { radius = 7.5, depth = 1.7 },
        mega_machine = { radius = 10, depth = 2.2 },
    } :: { [string]: Hole },
    defaultToolId = "hand",

    regrow = {
        -- So lange nach dem letzten Graben in einem Block bleibt das Loch unverändert.
        delaySeconds = 8,
        -- Danach wächst der Block in so vielen Schritten über diese Zeit zum Original zurück.
        seconds = 4,
        steps = 8,
        -- Ein Block näher als dieser Abstand am eigenen Charakter wächst nicht nach.
        blockRadiusStuds = 4,
        -- Höchstens so viele veränderte Blöcke gleichzeitig. Darüber wird der älteste sofort
        -- zurückgesetzt.
        maxDirtyChunks = 96,
        -- Höchstens so viele Blöcke schreibt der Client pro Bild beim Nachwachsen.
        maxWritesPerUpdate = 4,
    },

    -- Bildraten-Wächter: wechselt bei dauerhaft niedriger Bildrate auf die Rückfallvariante
    -- (sinkende Sandscheibe und Partikel, kein Terrain).
    perf = {
        warmupSeconds = 6,
        windowSeconds = 1,
        lowFps = 40,
        highFps = 52,
        downAfterSeconds = 3,
        upAfterSeconds = 12,
        maxSwitches = 3,
    },

    -- Platzhalter-Sandfeld, bis die Zone Dünenmeer steht (Paket 1.5). Der Server legt es nur an,
    -- wenn `enabled` gilt und an der Mitte der Oberseite noch kein Terrain liegt. Die Werte
    -- sollten am 4-Stud-Raster liegen.
    placeholderField = {
        enabled = true,
        center = { x = 0, y = 0, z = 56 },
        size = { x = 96, y = 8, z = 96 },
        material = "Sand",
        sandTypeId = "yellow",
    },

    debug = {
        -- Anzeige oben links mit FPS, Modus und offenen Blöcken (für den Handy-Test).
        showOverlay = true,
    },
}

return Terrain
