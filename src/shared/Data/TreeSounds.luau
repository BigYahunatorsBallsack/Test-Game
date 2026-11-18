--!strict
-- Töne der Freischalt-Sequenz (Paket 2.3). Die Sound-IDs sind leer, bis Paket 3.5 echte Sounds
-- aus dem Creator Store liefert (Lizenz prüfen). Eine leere ID spielt nichts und ist kein Fehler.
-- Gültig sind "" oder "rbxassetid://" plus Ziffern (DataCheck). Welcher Ton wann spielt, steht
-- je Variante in Data/UnlockAnimation (`cues`).

export type Cue = {
    soundId: string,
    volume: number, -- 0 bis 1
    pitch: number, -- Abspielgeschwindigkeit, 1 = normal
}

local cues: { [string]: Cue } = {
    press = { soundId = "", volume = 0.5, pitch = 1 },
    ring = { soundId = "", volume = 0.5, pitch = 1 },
    reveal = { soundId = "", volume = 0.4, pitch = 1 },
    milestone = { soundId = "", volume = 0.7, pitch = 1 },
}

return {
    cues = cues,
}
