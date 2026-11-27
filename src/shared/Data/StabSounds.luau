--!strict
-- Töne beim Stechen (Überarbeitung Ü4). Quellen in docs/testfaelle.md unter „Ü4 Nachtrag“.
-- Leere ID = stumm, kein Fehler. Gültig sind "" oder "rbxassetid://" plus
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
        { soundId = "rbxassetid://139482312225716", volume = 0.5, pitch = 1.05 },
        { soundId = "rbxassetid://111562355410998", volume = 0.55, pitch = 1 },
        { soundId = "rbxassetid://9118598279", volume = 0.6, pitch = 0.92 },
    } :: { Cue },
    clean = { soundId = "rbxassetid://117342687478220", volume = 0.45, pitch = 1 } :: Cue, -- zusätzlich beim sauberen Stich
    empty = { soundId = "rbxassetid://9116190442", volume = 0.5, pitch = 1 } :: Cue, -- Zelle leer
    full = { soundId = "rbxassetid://9119349447", volume = 0.5, pitch = 1 } :: Cue, -- Tank voll
}
