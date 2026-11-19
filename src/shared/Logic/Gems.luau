--!strict
-- Gems, die Premium-Währung (Paket 4.1). Rein, ohne Roblox-API, Lune-Tests in tests/gems.spec.luau.
--
-- Regeln:
--  * Der Gem-Stand ist eine ganze Zahl ab 0 und höchstens `Economy.purchases.maxGems`.
--  * Alle Buchungen laufen über dieses Modul. `grant` schreibt gut (Kauf, später Daily und Events),
--    `spend` bucht ab (Kisten ab Paket 4.2). Beide nehmen nur ganze Zahlen über 0 an.
--  * `grant` kappt bei `maxGems` und gibt die tatsächlich gebuchte Menge zurück (0 = nichts gebucht).
--  * `spend` bucht nur bei genug Gems ab, sonst bleibt der Stand unverändert.
--  * Jede Buchung nennt ihre Quelle bzw. ihren Grund als Text (zum Beispiel "purchase:gems_550").
--    Ohne Text wird nichts gebucht, damit keine Buchung ohne Herkunft entsteht.
--  * Ein kaputter Stand im Profil (NaN, negativ, gebrochen, kein Wert) zählt beim Rechnen wie der
--    reparierte Wert aus Profile.sanitize.
-- `data` ist für Tests überschreibbar ({ Economy = ... }), wie bei Wind und Sandstorm.

local EconomyData = require("../Data/Economy")

export type SpendReason = "notEnoughGems" | "invalidAmount"

local Gems = {}

local function configOf(data: any?): any
    local economy = if data and data.Economy then data.Economy else EconomyData
    return economy.purchases
end

-- Ganze Zahl über 0 und endlich.
local function isWholePositive(value: any): boolean
    return type(value) == "number" and value == value and value > 0 and value < math.huge and value % 1 == 0
end

local function isLabel(value: any): boolean
    return type(value) == "string" and value ~= ""
end

-- Gem-Stand des Profils. Kaputte Werte zählen als 0, gebrochene werden abgerundet, höchstens maxGems.
function Gems.balance(profile: any, data: any?): number
    local value = profile.gems
    if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
        return 0
    end
    return math.min(math.floor(value), configOf(data).maxGems)
end

-- Schreibt `amount` Gems gut. Gibt die tatsächlich gebuchte Menge zurück: weniger als `amount`, wenn
-- die Obergrenze erreicht ist, 0 bei ungültiger Menge oder fehlender Quelle (dann bleibt das Profil
-- unverändert).
function Gems.grant(profile: any, amount: number, source: string, data: any?): number
    if not isWholePositive(amount) or not isLabel(source) then
        return 0
    end
    local current = Gems.balance(profile, data)
    local added = math.max(math.min(amount, configOf(data).maxGems - current), 0)
    if added > 0 then
        profile.gems = current + added
    end
    return added
end

-- Bucht `amount` Gems ab. Gibt true zurück oder (false, Grund): "invalidAmount" (keine ganze Zahl
-- über 0 oder kein Grund angegeben) oder "notEnoughGems". Bei false bleibt das Profil unverändert.
function Gems.spend(profile: any, amount: number, reason: string, data: any?): (boolean, SpendReason?)
    if not isWholePositive(amount) or not isLabel(reason) then
        return false, "invalidAmount"
    end
    local current = Gems.balance(profile, data)
    if current < amount then
        return false, "notEnoughGems"
    end
    profile.gems = current - amount
    return true, nil
end

-- Reichen die Gems für `amount`? Ungültige Mengen ergeben false (wie bei `spend`).
function Gems.canAfford(profile: any, amount: number, data: any?): boolean
    return isWholePositive(amount) and Gems.balance(profile, data) >= amount
end

return Gems
