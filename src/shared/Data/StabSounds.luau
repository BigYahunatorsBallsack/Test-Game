--!strict
-- Töne beim Stechen (Überarbeitung Ü4). Die IDs sind leer, bis Waltuh Töne aus dem Creator Store
-- aussucht (Lizenz prüfen). Leere ID = stumm, kein Fehler. Gültig sind "" oder "rbxassetid://" plus
-- Ziffern (DataCheck). Die Tonhöhe schwankt je Ton um ±pitchJitter, damit es nicht nach Maschine klingt.

export type Cue = {
    soundId: string,
    volume: number, -- 0 bis 1
    pitch: number, -- 1 = normal
}

return {
    pitchJitter = 0.05,
    -- Stich je Schicht (Index = Schicht aus Data/Deposits: Oberfläche, feuchter Sand, Kern).
    layers = {
        { soundId = "", volume = 0.5, pitch = 1.05 },
        { soundId = "", volume = 0.55, pitch = 1 },
        { soundId = "", volume = 0.6, pitch = 0.92 },
    } :: { Cue },
    clean = { soundId = "", volume = 0.45, pitch = 1 } :: Cue, -- zusätzlich beim sauberen Stich
    empty = { soundId = "", volume = 0.5, pitch = 1 } :: Cue, -- Zelle leer
    full = { soundId = "", volume = 0.5, pitch = 1 } :: Cue, -- Tank voll
}
