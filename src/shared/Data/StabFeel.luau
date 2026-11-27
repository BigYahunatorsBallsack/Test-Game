--!strict
-- Gefühl beim Stechen (Überarbeitung Ü4, Plan "Plan Ü4: Gefühl beim Stechen"). Nur Anzeige auf dem
-- Client: Arme, Takt-Ring, Kamera-Ruck, Sandwurf, Eimer. Rechnung in Logic/StabFeel, Umsetzung in
-- Controllers/FirstPerson (Arme, Ring, Kamera, Eimer) und Controllers/Dig (Sandwurf, Töne).
-- Töne stehen in Data/StabSounds. Startwerte, Feinschliff nach Waltuhs Studio-Test.

return {
    -- Ein Stich der Arme dauert einen Takt
    -- des Werkzeugs (Data/Deposits) und beginnt mit dem Klick, damit er sofort sitzt. Anteile am Takt:
    -- Einstechen bis `strikeEnd`, unten halten bis `holdEnd`, danach zurück in die Ruhelage.
    arm = {
        strikeEnd = 0.18,
        holdEnd = 0.3,
        -- Leere ID verwendet die prozedurale Stichkurve.
        animationId = "rbxassetid://138942650732146",
        animationSeconds = 0.5,
    },

    -- Takt-Ring am Fadenkreuz: zieht sich vom Stich bis zum nächsten Takt zusammen.
    ring = {
        maxSize = 34, -- Pixel direkt nach dem Stich
        minSize = 10, -- Pixel beim nächsten Takt
        thickness = 2,
        transparency = 0.35,
        cleanFlashSeconds = 0.25, -- so lange leuchtet er nach einem sauberen Stich grün
        idleAfterTakts = 1.5, -- so lange nach dem letzten Stich ausgeblendet
    },

    -- Kamera-Ruck beim Einstechen (auf Grafikstufe "minimal" aus). Die Kamera sinkt um `studs`, die
    -- Hände kippen zusätzlich um `degrees` nach vorn. Die Kamera selbst wird nicht gedreht, damit sich
    -- die Blickrichtung nicht verschiebt.
    camera = {
        studs = 0.12,
        degrees = 0.6,
        seconds = 0.14,
        downShare = 0.3, -- Anteil der Zeit für den Weg nach unten, der Rest geht zurück
        layerStep = 0.25, -- je Schicht unter der Oberfläche so viel stärker
        maxFactor = 2, -- höchstens so viel mal der Grundwert
    },

    -- Sandklumpen vom Loch in den Eimer.
    throw = {
        seconds = 0.35,
        arcStuds = 1.2, -- so hoch steigt der Bogen über die gerade Linie
        size = 0.35,
        layerDarken = 0.18, -- je Schicht so viel dunkler (Anteil Schwarz)
        maxDarken = 0.6,
        -- Klumpen je Stich und höchstens gleichzeitig, je Grafikstufe (Data/Screen graphics.order).
        perStab = { hoch = 3, schlank = 1, minimal = 0 },
        maxActive = { hoch = 6, schlank = 3, minimal = 0 },
    },

    -- Der Sand im Eimer hüpft bei jedem Stich kurz hoch.
    bucket = {
        bumpStuds = 0.06,
        bumpSeconds = 0.2,
    },
}
