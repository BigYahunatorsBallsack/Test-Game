--!strict
-- Lagerstätten und Stich (Überarbeitung Ü2, Plan "Pläne Ü1 und Ü2"). Die Regeln stehen in
-- Logic/Deposits, der Server-Teil im Sand-Service, der Client-Teil in Controllers/Dig.
--
-- Jedes Sandfeld ist in quadratische Zellen geteilt. Jede Zelle hat Schichten: oben billig, unten
-- ergiebig. Ein Stich trägt Sand aus der obersten noch vollen Schicht ab. Nach der letzten Schicht ist
-- die Zelle leer und füllt sich `refillSeconds` nach dem letzten Stich in ihr wieder ganz auf.
-- Der Faktor einer Schicht wirkt auf die MENGE pro Stich, nicht auf den Preis (der gemischte Tank
-- bleibt, wie er ist, keine Profil-Migration).
--
-- Menge pro Stich = Sammelrate des Werkzeugs (Sand/s, mit Baum und Ausrüstung) mal Takt des Werkzeugs
-- mal Faktor der Schicht mal Stich-Faktor (sauber oder normal). Startwerte, Balancing in Ü10.

export type Layer = {
    name: string, -- Anzeigename (Meldungen, später Hinweise)
    stabs: number, -- so viele Stiche hält die Schicht (ganze Zahl ab 1)
    factor: number, -- Faktor auf die Menge pro Stich (über 0)
}

local Deposits = {
    -- Kantenlänge einer Zelle in Studs (Vielfaches von 4, wie das Terrain-Raster).
    cellStuds = 8,

    layers = {
        { name = "Oberfläche", stabs = 4, factor = 1 },
        { name = "Feuchter Sand", stabs = 6, factor = 1.5 },
        { name = "Kern", stabs = 8, factor = 2.5 },
    } :: { Layer },

    -- So lange nach dem letzten Stich in einer Zelle ist sie wieder ganz voll (Sekunden). Das Terrain
    -- auf dem Client wächst nach derselben Zeit nach (Data/Terrain.regrow.delaySeconds, DataCheck).
    refillSeconds = 60,

    stab = {
        -- Takt je Werkzeug (Sekunden zwischen zwei Stichen). Unbekanntes Werkzeug: defaultSeconds.
        defaultSeconds = 0.5,
        secondsByTool = {
            hand = 0.5,
            shovel = 0.45,
            bucket_chain = 0.4,
            mini_digger = 0.4,
            vacuum_robot = 0.35,
            mega_machine = 0.35,
        } :: { [string]: number },
        -- Spielraum für Netzwerk-Schwankungen: Ein Stich darf so viel früher als der Takt ankommen.
        -- Über viele Stiche bleibt es trotzdem bei höchstens einem Stich je Takt.
        slackSeconds = 0.12,
        -- Sauberer Stich: kommt der nächste Stich höchstens so lange nach dem Takt (und wurde nicht
        -- durch Halten ausgelöst), gilt `cleanFactor`, sonst `plainFactor`.
        cleanWindowSeconds = 0.25,
        cleanFactor = 1,
        plainFactor = 0.6,
    },

    -- Auto-Dig-Pass: sammelt weiter über die Zeit (ohne Zellen) mit diesem Faktor auf die Rate, also
    -- so viel wie Halten.
    autoDigFactor = 0.6,

    -- Prüfung des Zielpunkts auf dem Server.
    reach = {
        -- Zusätzlich zur Reichweite des Werkzeugs (Logic/DigAim.reach max): Bewegung während der
        -- Übertragung.
        toleranceStuds = 4,
        -- Höchster Höhenunterschied zwischen Charakter und Zielpunkt.
        maxHeightStuds = 14,
        -- Strahl nach unten auf dem Server: so weit über dem Zielpunkt beginnen, so lang.
        rayUpStuds = 6,
        rayLengthStuds = 24,
    },

    -- Höchstens so viele Zellen merkt sich der Server je Spieler. Darüber werden aufgefüllte Zellen
    -- vergessen, notfalls die ältesten.
    maxTrackedCells = 400,

    -- Grenze der Koordinaten in der Remote "Stab" (Studs, Schema in RemoteSpec).
    coordinateLimit = 100000,

    -- So lange nach dem letzten Stich zeigt der Zustand "sammelt" (Arme, Maschinen), in Takten.
    diggingHoldTakts = 2.5,
}

return Deposits
