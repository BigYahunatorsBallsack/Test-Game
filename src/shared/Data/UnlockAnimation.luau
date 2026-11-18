--!strict
-- Zahlen der Freischalt-Sequenz im Skilltree (Paket 2.3, Konzept: "Freischalt-Animation").
-- Die Berechnung steht in Logic/UnlockSequence, abgespielt wird sie vom Controller SkillTree.
--
-- Drei Varianten:
--   normal     etwa 1,2 s: Knoten drückt sich ein, Ring bricht aus, Lichtimpuls läuft über die
--              Linien zu den Folgeknoten, neue Knoten blenden aus dem Nebel ein, Kamera gleitet.
--   milestone  etwa 1,6 s für Knoten mit `milestone`: wie normal, dazu größerer Ring und ein
--              Aufhell-Puls über den ganzen Baum. Gilt immer, auch nach vielen Käufen.
--   short      etwa 0,5 s ab dem Kauf nach `shortAfterPurchases` Käufen in einer Sitzung: nur
--              Eindrücken, kleiner Ring, Einblenden und kurze Kamerafahrt.
--
-- Jeder Schritt hat `start` und `duration` in Sekunden ab dem Kauf. Die Starts steigen in der
-- Reihenfolge press, ring, pulse, reveal, camera (DataCheck prüft das). Ein fehlender Schritt
-- (pulse, flash) entfällt in dieser Variante.
-- `cues` ordnet einen Ton (siehe Data/TreeSounds) dem Start eines Schritts zu.

export type Step = { start: number, duration: number }

export type Variant = {
    press: Step,
    ring: Step & { scale: number }, -- Ring wächst bis zum x-fachen der Knotengröße
    pulse: Step?,
    reveal: Step,
    camera: Step,
    flash: (Step & { strength: number })?, -- Aufhell-Puls, strength = Deckkraft am Höhepunkt (0 bis 1)
    cues: { [string]: string }, -- Ton -> Schritt, bei dessen Start er spielt
}

return {
    -- Ab dem Kauf nach so vielen Käufen läuft die kurze Variante (also ab dem elften Kauf).
    shortAfterPurchases = 10,
    -- Längste erlaubte Gesamtdauer einer Variante (DataCheck).
    maxTotalSeconds = 2,

    pressScale = 0.88, -- der Knoten drückt sich bis auf diese Größe ein
    revealStartScale = 0.8, -- neue Knoten wachsen aus dieser Größe auf

    variants = {
        normal = {
            press = { start = 0, duration = 0.15 },
            ring = { start = 0.1, duration = 0.35, scale = 2.4 },
            pulse = { start = 0.2, duration = 0.5 },
            reveal = { start = 0.4, duration = 0.5 },
            camera = { start = 0.5, duration = 0.7 },
            cues = { press = "press", ring = "ring", reveal = "reveal" },
        },
        milestone = {
            press = { start = 0, duration = 0.15 },
            ring = { start = 0.1, duration = 0.45, scale = 3.6 },
            pulse = { start = 0.2, duration = 0.6 },
            reveal = { start = 0.5, duration = 0.6 },
            camera = { start = 0.7, duration = 0.9 },
            flash = { start = 0.2, duration = 0.5, strength = 0.55 },
            cues = { press = "press", ring = "ring", reveal = "reveal", milestone = "flash" },
        },
        short = {
            press = { start = 0, duration = 0.1 },
            ring = { start = 0.05, duration = 0.25, scale = 1.7 },
            reveal = { start = 0.15, duration = 0.3 },
            camera = { start = 0.2, duration = 0.3 },
            cues = { press = "press", reveal = "reveal" },
        },
    },
}
