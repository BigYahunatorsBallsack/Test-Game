--!strict
-- Offline-Ertrag des Begleiters (Paket 5.3). Rein, ohne Roblox-API, Lune-Tests in tests/offline.spec.luau.
-- Der Offline-Service (Services/Offline) ruft `apply` einmal beim Laden des Profils auf. Der Client
-- meldet nie etwas: Die Zeit kommt aus `profile.lastSeen` (setzt der Server beim Speichern und
-- Verlassen) und der Uhr des Servers.
--
-- Regeln (Werte in Economy.offline):
--  * Abwesenheit = jetzt minus lastSeen. Unter `minSeconds` (300) gibt es nichts und lastSeen bleibt.
--  * Obergrenze: `baseHours` (4) oder mit dem Pass "autoDig" `autoDigHours` (12). Wer länger weg war,
--    bekommt genau die Grenze (`capped`).
--  * Ohne besessenen, ausgestatteten Begleiter (Slot companion) gibt es nichts ("noCompanion").
--  * Ertrag = Sammelrate (Collecting.rateOf ohne den Ausrüstungsbonus) mal Sekunden mal `rateFactor` (0.5) als Sand der aktuellen
--    Zone, zum normalen Verkaufspreis (Collecting.priceOf: Sorte, Verkauf-Ast, Sammlung, Windkristalle)
--    mal dem dauerhaften Faktor des 2x-Münzen-Passes. Der Münz-Boost, der Glücks-Boost und Fundstücke
--    zählen nicht (Balance 4.4 und 2.6): es gibt nur Münzen, nie Funde. Die Münzen gehen wie verdiente
--    Münzen über Wind.credit auf `coins` und `runEarned` (nicht in den Tank).
--  * Kaputte Zeit (lastSeen fehlt oder ist keine Zahl, kaputte Uhr): nichts. lastSeen in der Zukunft
--    (Server mit vorgehender Uhr): nichts, lastSeen bleibt (geht nie zurück); über 7 Tage in der Zukunft
--    gilt es als kaputt und wird auf jetzt gesetzt.
--  * In jedem Fall außer "tooShort" setzt `apply` lastSeen im selben Schritt auf jetzt: derselbe
--    Zeitraum wird nie zweimal bezahlt.
-- `apply` rechnet zuerst alles aus und schreibt danach nur fertige Werte (ohne Warten).

local BigNum = require("./BigNum")
local Collecting = require("./Collecting")
local Equipment = require("./Equipment")
local Perks = require("./Perks")
local Wind = require("./Wind")
local EconomyData = require("../Data/Economy")
local ZoneData = require("../Data/Zones")
local ZoneLogic = require("./Zones")

local Offline = {}

-- Eine lastSeen weiter als so viele Sekunden in der Zukunft gilt als kaputt (7 Tage) und wird neu gesetzt.
Offline.MAX_FUTURE_SECONDS = 7 * 86400

export type Report = {
    ok: boolean,
    reason: string?, -- "noCompanion", "tooShort", "noProfile", "badTime", "noGain", "error"
    seconds: number, -- bezahlte Sekunden (nach der Grenze)
    awaySeconds: number, -- tatsächliche Abwesenheit
    capSeconds: number, -- die Grenze, die galt
    capped: boolean,
    coins: BigNum.Serialized?, -- gutgeschriebene Münzen
}

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function configOf(data: any?): (any, any)
    local economy = if data ~= nil and data.Economy ~= nil then data.Economy else EconomyData
    return economy.offline, economy
end

-- Grenze in Sekunden: mit dem Pass "autoDig" autoDigHours, sonst baseHours.
function Offline.capSeconds(profile: any, data: any?): number
    local config = configOf(data)
    local hours = if Perks.owns(profile, "autoDig", if data ~= nil then data else nil) then config.autoDigHours else config.baseHours
    return hours * 3600
end

local function fail(reason: string, away: number, cap: number): Report
    return { ok = false, reason = reason, seconds = 0, awaySeconds = away, capSeconds = cap, capped = false }
end

-- Rechnet den Ertrag für die Zeit seit lastSeen und bucht ihn. `unixNow` ist die Unix-Zeit des Servers.
-- Gibt immer einen Bericht zurück; `ok` ist nur bei einer Gutschrift true.
function Offline.apply(profile: any, unixNow: any, data: any?): Report
    if type(profile) ~= "table" then
        return fail("noProfile", 0, 0)
    end
    local config, economy = configOf(data)
    local cap = Offline.capSeconds(profile, data)
    if not isFinite(unixNow) or unixNow < 0 then
        return fail("badTime", 0, cap)
    end
    local lastSeen = profile.lastSeen
    if not isFinite(lastSeen) or lastSeen <= 0 or lastSeen > unixNow + Offline.MAX_FUTURE_SECONDS then
        profile.lastSeen = unixNow -- kaputt oder weit in der Zukunft: neu anfangen
        return fail("badTime", 0, cap)
    end
    if lastSeen > unixNow then
        -- Ein Server mit vorgehender Uhr hat lastSeen geschrieben: nichts zahlen, aber nie zurücksetzen
        -- (sonst ließe sich die Uhrdifferenz durch Serverwechsel immer wieder bezahlen, Review 5.3, M1).
        return fail("badTime", 0, cap)
    end
    local away = unixNow - lastSeen
    if away < config.minSeconds then
        return fail("tooShort", away, cap)
    end
    -- Ab hier gilt der Zeitraum als abgerechnet, auch wenn es nichts zu zahlen gibt.
    local seconds = math.min(away, cap)
    local capped = away > cap
    if Equipment.equippedItem(profile, "companion", data) == nil then
        profile.lastSeen = unixNow
        local report = fail("noCompanion", away, cap)
        report.capped = capped
        return report
    end

    -- Alles rechnen, bevor etwas geschrieben wird (auch die neuen Münzstände). Wirft etwas, bleibt das
    -- Profil unverändert und lastSeen stehen (bis zum nächsten Speichern; ein Fehler kostet den Zeitraum).
    local ok, result = pcall(function(): { coins: BigNum.BigNum, newCoins: BigNum.Serialized, newRunEarned: BigNum.Serialized }?
        -- Sammelrate ohne den Ausrüstungsbonus (Kisten-Items zählen offline nicht).
        local equipment = Equipment.multiplier(profile, data)
        if not isFinite(equipment) or equipment <= 0 then
            equipment = 1
        end
        local rate = Collecting.rateOf(profile) / equipment
        local pass = if Perks.owns(profile, "doubleCoins", data) then economy.doubleCoinsMultiplier else 1
        if not isFinite(rate) or rate <= 0 or not isFinite(pass) or pass <= 0 then
            return nil
        end
        -- Die Event-Zone gilt hier immer als gesperrt (isUnlocked ohne Zeit): wer dort abmeldet, bekommt offline den
        -- Preis der ersten Zone (nie zu viel, bewusst).
        -- Eine gesperrte aktuelle Zone zahlt nie (der Sand-Service setzt sie beim Laden zurück, hier zur Sicherheit).
        local sandTypeId = if ZoneLogic.isUnlocked(profile, profile.currentZone) then Collecting.sandTypeOf(profile) else ZoneData.list[1].sandTypeId
        local price = Collecting.priceOf(profile, sandTypeId, { coinMultiplier = pass })
        local amount = rate * seconds * config.rateFactor * price
        if not isFinite(amount) or amount <= 0 then
            return nil
        end
        local earned = BigNum.floor(BigNum.new(amount)) -- ganze Münzen wie beim Verkauf
        if earned.m <= 0 then
            return nil
        end
        return {
            coins = earned,
            newCoins = BigNum.serialize(BigNum.add(BigNum.deserialize(profile.coins), earned)),
            newRunEarned = BigNum.serialize(BigNum.add(Wind.runEarned(profile), earned)),
        }
    end)
    if not ok then
        return fail("error", away, cap)
    end
    if result == nil then
        profile.lastSeen = unixNow
        local report = fail("noGain", away, cap)
        report.capped = capped
        return report
    end

    -- Dieselbe Buchung wie Wind.credit (coins und runEarned), nur mit fertigen Werten.
    profile.coins = result.newCoins
    profile.runEarned = result.newRunEarned
    profile.lastSeen = unixNow
    return {
        ok = true,
        seconds = seconds,
        awaySeconds = away,
        capSeconds = cap,
        capped = capped,
        coins = BigNum.serialize(result.coins),
    }
end

-- Für den Client: Bericht ohne interne Felder, nur was die Karte zeigt.
function Offline.snapshotOf(report: Report?, id: number): { [string]: any }?
    if report == nil then
        return nil
    end
    return {
        id = id,
        ok = report.ok,
        reason = report.reason,
        seconds = report.seconds,
        awaySeconds = report.awaySeconds,
        capSeconds = report.capSeconds,
        capped = report.capped,
        coins = report.coins,
    }
end

return Offline
