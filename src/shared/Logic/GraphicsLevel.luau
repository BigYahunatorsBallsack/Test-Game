--!strict
-- Grafikstufe (Paket 3.6), ohne Roblox-API, Lune-Tests in tests/graphicslevel.spec.luau.
-- Drei Stufen: "hoch" (PC), "schlank" (Touch-Gerät oder niedriger Grafikregler), "minimal"
-- (Rückfallvariante des Bildraten-Wächters, auch am PC). Ein erzwungener Wert (Attribut
-- `GraphicsLevel` am Spieler) gilt immer. Die Einstellungen je Stufe stehen in Data/Screen.

local DefaultConfig = require("../Data/Screen")

export type Input = {
    forced: any?, -- Wert des Attributs `GraphicsLevel` (nur gültige Stufen zählen)
    fallback: boolean?, -- meldet der Bildraten-Wächter den Rückfall?
    touch: boolean?, -- Handy oder Tablet ohne Tastatur
    quality: number?, -- Grafikregler von Roblox 1 bis 10, 0 oder nil = Automatik
}

local GraphicsLevel = {}

function GraphicsLevel.isLevel(value: any, config: any?): boolean
    local cfg: any = config or DefaultConfig
    return type(value) == "string" and cfg.graphics.levels[value] ~= nil
end

-- Wählt die Stufe. Reihenfolge: erzwungen, Rückfall, Touch, niedriger Grafikregler, sonst hoch.
function GraphicsLevel.pick(input: Input, config: any?): string
    local cfg: any = config or DefaultConfig
    if GraphicsLevel.isLevel(input.forced, cfg) then
        return input.forced :: string
    end
    if input.fallback == true then
        return "minimal"
    end
    if input.touch == true then
        return "schlank"
    end
    local quality = input.quality
    if type(quality) == "number" and quality >= 1 and quality <= cfg.graphics.leanMaxQualityLevel then
        return "schlank"
    end
    return "hoch"
end

-- Einstellungen einer Stufe. Eine unbekannte Stufe gibt die von "hoch".
function GraphicsLevel.settings(level: string, config: any?): any
    local cfg: any = config or DefaultConfig
    return cfg.graphics.levels[level] or cfg.graphics.levels.hoch
end

return GraphicsLevel
