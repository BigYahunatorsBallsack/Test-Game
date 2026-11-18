--!strict
-- Aussehen eines Werkzeugs (Paket 2.4). Rein, ohne Roblox-API, Lune-Tests in
-- tests/toollook.spec.luau. Die Zahlen stehen in Data/ToolLooks.

local Tools = require("../Data/Tools")
local ToolLooks = require("../Data/ToolLooks")

export type Change = "none" | "upgrade" | "silent"

local ToolLook = {}

-- Aussehen zur Werkzeug-ID. Unbekannte oder leere IDs bekommen das Aussehen der Hand.
function ToolLook.of(toolId: string?): ToolLooks.Look
    local look = if type(toolId) == "string" then ToolLooks.byToolId[toolId] else nil
    return look or ToolLooks.byToolId[ToolLooks.defaultToolId]
end

local function tierOf(toolId: string?): number
    local tool = if type(toolId) == "string" then Tools.byId[toolId] else nil
    if tool == nil then
        tool = Tools.byId[ToolLooks.defaultToolId]
    end
    return if tool ~= nil then tool.tier else 1
end

-- Was passiert beim Wechsel von `before` zu `after`?
--   none     gleiche Stufe, nichts tun
--   upgrade  höhere Stufe: Modell wechseln mit Animation
--   silent   erster Zustand oder niedrigere Stufe (Sandsturm-Reset): Modell wechseln ohne Animation
function ToolLook.change(before: string?, after: string?): Change
    if before == nil then
        return "silent"
    end
    local a = tierOf(before)
    local b = tierOf(after)
    if b == a then
        return "none"
    elseif b > a then
        return "upgrade"
    end
    return "silent"
end

-- Partikel pro Graben.
function ToolLook.dustCount(toolId: string?): number
    return ToolLook.of(toolId).dust.count
end

-- Höchste Partikelzahl auf einmal: Staub beim Graben plus Wechsel-Wolke.
function ToolLook.particlePeak(toolId: string?): number
    return ToolLook.of(toolId).dust.count + ToolLooks.change.burstCount
end

function ToolLook.cameraBonus(toolId: string?): number
    return ToolLook.of(toolId).cameraBonusStuds
end

return ToolLook
