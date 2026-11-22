--!strict
-- Saison-Pass (Paket 5.5): Saison-Punkte und Stufen. Reine Logik ohne Roblox-API, getestet mit Lune
-- (tests/seasonpoints.spec.luau). Abholen und Kauf folgen in Paket 5.5b in demselben Modul.
--
-- Regeln:
--  * Punkte kommen nur aus Sammelzeit in der Event-Zone, die der Server rechnet (`addSeconds`).
--    Der Client sendet nie Punkte oder Zeiten. Je `Economy.seasonPass.secondsPerPoint` Sekunden gibt es
--    einen Punkt.
--  * Gespeichert werden die Sekunden (`profile.seasons[seasonId].seconds`), die Punkte werden daraus
--    gerechnet und sind durch die letzte Stufe gedeckelt. Mehr Sekunden als dafür nötig werden nicht
--    gespeichert (kein Überlauf, kein Dauerzähler).
--  * Die Zählung gilt nur für die laufende Saison, deren Event-Zone offen ist (Logic/Seasons). Der
--    Aufrufer (Services/Events) prüft das; hier wird nur gerechnet.
--  * Profil: `profile.seasons[seasonId] = { seconds, premium, claimed = { free = {}, premium = {} } }`.
--    `claimed` hat die Stufennummer als Textschlüssel ("3" -> true), weil der DataStore keine
--    Zahlenschlüssel in Wörterbüchern speichert.
--  * Daten kommen als Argument (`data = { Economy, SeasonPass }`), Vorgabe sind die echten Tabellen.

local SeasonPass = {}

export type Entry = {
    seconds: number,
    premium: boolean,
    claimed: { free: { [string]: boolean }, premium: { [string]: boolean } },
}

export type Data = { Economy: any?, SeasonPass: any? }

SeasonPass.TRACKS = { "free", "premium" }

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function economyOf(data: Data?): any
    if data ~= nil and data.Economy ~= nil then
        return data.Economy
    end
    return require("../Data/Economy")
end

local function tablesOf(data: Data?): any
    if data ~= nil and data.SeasonPass ~= nil then
        return data.SeasonPass
    end
    return require("../Data/SeasonPass")
end

-- Sekunden je Punkt (endlich und größer 0). Wirft bei kaputten Daten (DataCheck prüft beim Start).
function SeasonPass.secondsPerPoint(data: Data?): number
    local config = economyOf(data).seasonPass
    if type(config) ~= "table" or not isFinite(config.secondsPerPoint) or config.secondsPerPoint <= 0 then
        error("SeasonPass: Economy.seasonPass.secondsPerPoint fehlt")
    end
    return config.secondsPerPoint
end

-- Stufen einer Saison oder nil.
function SeasonPass.tiersOf(seasonId: any, data: Data?): { any }?
    if type(seasonId) ~= "string" then
        return nil
    end
    local row = tablesOf(data).bySeason[seasonId]
    if type(row) ~= "table" or type(row.tiers) ~= "table" then
        return nil
    end
    return row.tiers
end

-- Punktestand der letzten Stufe (0 ohne Stufen).
function SeasonPass.maxPoints(seasonId: any, data: Data?): number
    local tiers = SeasonPass.tiersOf(seasonId, data)
    if tiers == nil or #tiers == 0 then
        return 0
    end
    return tiers[#tiers].points
end

function SeasonPass.newEntry(): Entry
    return { seconds = 0, premium = false, claimed = { free = {}, premium = {} } }
end

-- Eintrag der Saison im Profil oder nil. Ändert nichts.
function SeasonPass.entryOf(profile: any, seasonId: any): Entry?
    if type(profile) ~= "table" or type(profile.seasons) ~= "table" or type(seasonId) ~= "string" then
        return nil
    end
    local entry = profile.seasons[seasonId]
    if type(entry) ~= "table" then
        return nil
    end
    return entry
end

-- Punkte aus Sekunden (ganze Zahl, durch die letzte Stufe gedeckelt).
function SeasonPass.pointsFromSeconds(seconds: any, seasonId: any, data: Data?): number
    if not isFinite(seconds) or seconds <= 0 then
        return 0
    end
    local points = math.floor(seconds / SeasonPass.secondsPerPoint(data))
    return math.min(points, SeasonPass.maxPoints(seasonId, data))
end

function SeasonPass.pointsOf(profile: any, seasonId: any, data: Data?): number
    local entry = SeasonPass.entryOf(profile, seasonId)
    if entry == nil then
        return 0
    end
    return SeasonPass.pointsFromSeconds(entry.seconds, seasonId, data)
end

-- Anzahl erreichter Stufen bei `points` Punkten (0 bis #Stufen).
function SeasonPass.tierOf(points: any, seasonId: any, data: Data?): number
    local tiers = SeasonPass.tiersOf(seasonId, data)
    if tiers == nil or not isFinite(points) then
        return 0
    end
    local reached = 0
    for index, tier in tiers do
        if points >= tier.points then
            reached = index
        else
            break
        end
    end
    return reached
end

-- Schreibt Sammelzeit in der Event-Zone gut. Gibt die neu gewonnenen Punkte zurück (0 oder mehr).
-- Kaputte Eingaben (kein number, NaN, unendlich, 0 oder negativ), eine Saison ohne Stufen und ein
-- Profil ohne `seasons` ändern nichts. Rechnet erst alles und schreibt dann in einem Zug.
function SeasonPass.addSeconds(profile: any, seasonId: any, seconds: any, data: Data?): number
    if type(profile) ~= "table" or type(profile.seasons) ~= "table" or not isFinite(seconds) or seconds <= 0 then
        return 0
    end
    local maxPoints = SeasonPass.maxPoints(seasonId, data)
    if maxPoints <= 0 then
        return 0
    end
    local perPoint = SeasonPass.secondsPerPoint(data)
    local cap = maxPoints * perPoint
    local entry = SeasonPass.entryOf(profile, seasonId)
    local before = if entry ~= nil and isFinite(entry.seconds) then math.max(entry.seconds, 0) else 0
    local after = math.min(before + seconds, cap)
    if after <= before then
        return 0
    end
    local gained = math.floor(after / perPoint) - math.floor(before / perPoint)
    -- Schreiben, ohne dass etwas dazwischen wirft.
    if entry == nil then
        entry = SeasonPass.newEntry()
        profile.seasons[seasonId :: string] = entry
    end
    (entry :: Entry).seconds = after
    return gained
end

-- Anzeigeform für den StateSync (`seasonPass`): Punkte, Obergrenze, erreichte Stufen, Stufenzahl.
function SeasonPass.state(profile: any, seasonId: any, data: Data?): { [string]: any }
    local tiers = SeasonPass.tiersOf(seasonId, data)
    local points = SeasonPass.pointsOf(profile, seasonId, data)
    local entry = SeasonPass.entryOf(profile, seasonId)
    return {
        seasonId = seasonId,
        points = points,
        maxPoints = SeasonPass.maxPoints(seasonId, data),
        tier = SeasonPass.tierOf(points, seasonId, data),
        tiers = if tiers ~= nil then #tiers else 0,
        premium = entry ~= nil and entry.premium == true,
    }
end

-- Säubert `profile.seasons` beim Laden: Textschlüssel (Saison-ID), je Eintrag `seconds` endlich ab 0
-- (sonst 0), `premium` Boolean (sonst false), `claimed.free` und `claimed.premium` nur mit Textschlüsseln
-- aus Ziffern (Stufennummer ab 1) und Wert true. Unbekannte Saison-IDs und unbekannte Felder in einem
-- Eintrag bleiben erhalten (ein neuerer Server darf nichts verlieren). Gibt (sauberes Feld, Liste der Probleme) zurück.
function SeasonPass.cleanSeasons(value: any): ({ [string]: Entry }, { string })
    local problems: { string } = {}
    local clean: { [string]: Entry } = {}
    if type(value) ~= "table" then
        return clean, { "seasons keine Tabelle, auf {} gesetzt" }
    end
    for seasonId, raw in value do
        if type(seasonId) ~= "string" or seasonId == "" or type(raw) ~= "table" then
            table.insert(problems, `seasons.{tostring(seasonId)}: Schlüssel kein Text oder Eintrag keine Tabelle, entfernt`)
            continue
        end
        local entry = SeasonPass.newEntry()
        if isFinite(raw.seconds) and raw.seconds >= 0 then
            entry.seconds = raw.seconds
        elseif raw.seconds ~= nil then
            table.insert(problems, `seasons.{seasonId}.seconds ungültig, auf 0 gesetzt`)
        end
        if raw.premium == true then
            entry.premium = true
        elseif raw.premium ~= nil and raw.premium ~= false then
            table.insert(problems, `seasons.{seasonId}.premium kein Wahrheitswert, auf false gesetzt`)
        end
        if type(raw.claimed) == "table" then
            for _, track in SeasonPass.TRACKS do
                local source = raw.claimed[track]
                if type(source) == "table" then
                    for key, flag in source do
                        if type(key) == "string" and string.match(key, "^[1-9]%d*$") ~= nil and flag == true then
                            (entry.claimed :: any)[track][key] = true
                        else
                            table.insert(problems, `seasons.{seasonId}.claimed.{track}.{tostring(key)} ungültig, entfernt`)
                        end
                    end
                end
            end
        end
        -- Unbekannte Felder bleiben erhalten (ein neuerer Server, zum Beispiel 5.5b, darf nichts verlieren).
        for key, extra in raw do
            if type(key) == "string" and key ~= "seconds" and key ~= "premium" and key ~= "claimed" then
                (entry :: any)[key] = extra
            end
        end
        clean[seasonId] = entry
    end
    return clean, problems
end

return SeasonPass
