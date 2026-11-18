--!strict
-- Windkristalle und Lauf-Einnahmen (Paket 2.7). Rein, ohne Roblox-API, Lune-Tests in
-- tests/sandstorm.spec.luau.
--
-- Ein Blatt-Modul ohne Abhängigkeit zu Collecting, Collection oder FindRoll, damit alle drei den
-- Bonus und die Buchung nutzen können, ohne sich im Kreis zu verlinken.
--
--  * `profile.windCrystals`: ganze Kristalle, dauerhaft. Jeder gibt `Economy.windCrystalBonusBp`
--    auf alle Münzen (Preis pro Sand und Fundwert).
--  * `profile.runEarned`: Münzen aus Sandverkäufen und verkauften Duplikaten seit dem letzten
--    Sturm (Zahlentyp). Allein daraus rechnet der Sturm die Kristalle. Münzen aus anderen Quellen
--    (Knotenkäufe sind Ausgaben, spätere gekaufte Münzen) laufen nicht über `credit` und zählen
--    darum nicht, damit sich Kristalle nicht kaufen lassen.

local BigNum = require("./BigNum")
local Economy = require("../Data/Economy")

local Wind = {}

-- Anzahl Kristalle im Profil. Kaputte Werte zählen als 0, gebrochene werden abgerundet.
function Wind.crystalsOf(profile: any): number
    local count = profile.windCrystals
    if type(count) ~= "number" or count ~= count or count < 1 or count == math.huge then
        return 0
    end
    return math.floor(count)
end

-- Bonus aller Kristalle in Hundertstel-Prozent.
function Wind.bonusBp(profile: any): number
    return Wind.crystalsOf(profile) * Economy.windCrystalBonusBp
end

-- Faktor auf alle Münzen (1 = kein Bonus).
function Wind.multiplier(profile: any): number
    return (10000 + Wind.bonusBp(profile)) / 10000
end

-- Münzen aus Verkäufen seit dem letzten Sturm.
function Wind.runEarned(profile: any): BigNum.BigNum
    return BigNum.deserialize(profile.runEarned)
end

-- Bucht verdiente Münzen auf `coins` und auf `runEarned`. Negative oder kaputte Beträge werden
-- ignoriert.
function Wind.credit(profile: any, amount: BigNum.BigNum)
    if amount.m <= 0 then
        return
    end
    profile.coins = BigNum.serialize(BigNum.add(BigNum.deserialize(profile.coins), amount))
    profile.runEarned = BigNum.serialize(BigNum.add(Wind.runEarned(profile), amount))
end

return Wind
