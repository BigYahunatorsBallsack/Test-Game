--!strict
-- Event-Kalender (Paket 5.4): reine Logik ohne Roblox-API, getestet mit Lune (tests/seasons.spec.luau).
--
-- Regeln:
--  * Zeit ist immer die Unix-Zeit des Servers (der Aufrufer übergibt sie). Eine kaputte Zeit (kein
--    number, NaN, unendlich, negativ) ergibt "nichts aktiv", nie einen Fehler.
--  * Eine Saison beginnt am `startDate` um 0 Uhr UTC und dauert #phases Wochen. Das Ende ist
--    ausschließend: die erste Sekunde danach ist keine Saison mehr.
--  * Woche n (1 bis #phases) gehört zur n-ten Phase der Tabelle. Die Event-Kiste ist offen, wenn die
--    Phase `crateOpen = true` hat und die Kiste zur aktiven Saison gehört.
--  * Die Daten kommen als Argument (`data = { phases, list }`), Vorgabe sind die echten Tabellen.
--    So testet Lune neue Zeilen, ohne Code zu ändern.

local Seasons = {}

Seasons.SECONDS_PER_DAY = 86400
Seasons.DAYS_PER_WEEK = 7
Seasons.WEEK_SECONDS = Seasons.SECONDS_PER_DAY * Seasons.DAYS_PER_WEEK

export type Data = { phases: { any }, list: { any } }

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Tage seit 1970-01-01 für ein Kalenderdatum (proleptisch gregorianisch, Howard Hinnant).
local function daysFromCivil(year: number, month: number, day: number): number
    local y = if month <= 2 then year - 1 else year
    local era = math.floor(y / 400)
    local yearOfEra = y - era * 400
    local shifted = if month > 2 then month - 3 else month + 9
    local dayOfYear = math.floor((153 * shifted + 2) / 5) + day - 1
    local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
    return era * 146097 + dayOfEra - 719468
end

-- Kalenderdatum zu Tagen seit 1970 (Gegenstück, für die Prüfung auf echte Tage).
local function civilFromDays(days: number): (number, number, number)
    local z = days + 719468
    local era = math.floor(z / 146097)
    local dayOfEra = z - era * 146097
    local yearOfEra = math.floor((dayOfEra - math.floor(dayOfEra / 1460) + math.floor(dayOfEra / 36524) - math.floor(dayOfEra / 146096)) / 365)
    local year = yearOfEra + era * 400
    local dayOfYear = dayOfEra - (365 * yearOfEra + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100))
    local shifted = math.floor((5 * dayOfYear + 2) / 153)
    local day = dayOfYear - math.floor((153 * shifted + 2) / 5) + 1
    local month = if shifted < 10 then shifted + 3 else shifted - 9
    return (if month <= 2 then year + 1 else year), month, day
end

-- "JJJJ-MM-TT" -> Unix-Sekunden 0 Uhr UTC. nil bei falscher Form oder einem Datum, das es nicht gibt
-- (z. B. 2027-02-30).
function Seasons.parseDate(text: any): number?
    if type(text) ~= "string" then
        return nil
    end
    local yearText, monthText, dayText = string.match(text, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if yearText == nil then
        return nil
    end
    local year, month, day = tonumber(yearText) :: number, tonumber(monthText) :: number, tonumber(dayText) :: number
    if year < 1970 or month < 1 or month > 12 or day < 1 or day > 31 then
        return nil
    end
    local days = daysFromCivil(year, month, day)
    local checkYear, checkMonth, checkDay = civilFromDays(days)
    if checkYear ~= year or checkMonth ~= month or checkDay ~= day then
        return nil
    end
    return days * Seasons.SECONDS_PER_DAY
end

-- Ist die Unix-Zeit ein Montag um 0 Uhr UTC? (1970-01-01 war ein Donnerstag.)
function Seasons.isMondayStart(unixTime: number): boolean
    if not isFinite(unixTime) or unixTime < 0 or unixTime % Seasons.SECONDS_PER_DAY ~= 0 then
        return false
    end
    return (unixTime / Seasons.SECONDS_PER_DAY + 3) % 7 == 0
end

local function dataOf(data: Data?): Data
    if data ~= nil then
        return data
    end
    return require("../Data/Seasons") :: any
end

local function lengthOf(data: Data): number
    return #data.phases * Seasons.WEEK_SECONDS
end

-- Start einer Saison (Unix-Sekunden). nil bei kaputtem Datum.
function Seasons.startOf(season: any): number?
    if type(season) ~= "table" then
        return nil
    end
    return Seasons.parseDate(season.startDate)
end

-- Ende der Saison (ausschließend). nil bei kaputtem Datum.
function Seasons.endOf(season: any, data: Data?): number?
    local start = Seasons.startOf(season)
    if start == nil then
        return nil
    end
    return start + lengthOf(dataOf(data))
end

export type Position = {
    active: any?, -- Zeile der laufenden Saison oder nil
    week: number?, -- 1 bis #phases
    phase: any?, -- Phase der Woche
    secondsLeft: number, -- Sekunden bis zum Saisonende (0 ohne Saison)
    nextSeason: any?, -- die nächste Saison, die noch beginnt
    secondsToNext: number, -- Sekunden bis zu ihrem Start (0 ohne)
}

local NOTHING: Position = { active = nil, week = nil, phase = nil, secondsLeft = 0, nextSeason = nil, secondsToNext = 0 }

table.freeze(NOTHING) -- wird von `at` gemeinsam zurückgegeben, darf nie verändert werden

-- Wo steht die Zeit im Kalender? Zeilen mit kaputtem Datum werden übersprungen (DataCheck meldet sie
-- beim Start).
function Seasons.at(unixNow: any, data: Data?): Position
    if not isFinite(unixNow) or unixNow < 0 then
        return NOTHING
    end
    local set = dataOf(data)
    local length = lengthOf(set)
    local nextSeason: any = nil
    local nextStart = math.huge
    for _, season in set.list do
        local start = Seasons.startOf(season)
        if start ~= nil then
            if unixNow >= start and unixNow < start + length then
                local week = math.min(math.floor((unixNow - start) / Seasons.WEEK_SECONDS) + 1, #set.phases)
                return {
                    active = season,
                    week = week,
                    phase = set.phases[week],
                    secondsLeft = start + length - unixNow,
                    nextSeason = nil,
                    secondsToNext = 0,
                }
            end
            if start > unixNow and start < nextStart then
                nextSeason, nextStart = season, start
            end
        end
    end
    if nextSeason == nil then
        return NOTHING
    end
    return {
        active = nil,
        week = nil,
        phase = nil,
        secondsLeft = 0,
        nextSeason = nextSeason,
        secondsToNext = nextStart - unixNow,
    }
end

-- Darf die Kiste jetzt geöffnet werden? Nur die Event-Kiste der aktiven Saison, nur in einer Phase mit
-- `crateOpen`. Alles andere (andere Saison, Pause, kaputte Zeit, kein Text) ist false.
function Seasons.inSeason(unixNow: any, crateId: any, data: Data?): boolean
    if type(crateId) ~= "string" then
        return false
    end
    local position = Seasons.at(unixNow, data)
    if position.active == nil or position.phase == nil then
        return false
    end
    return position.active.crateId == crateId and position.phase.crateOpen == true
end

-- Ist die Event-Zone jetzt offen? Nur die Zone der aktiven Saison, nur in einer Phase mit `zoneOpen`.
-- Kaputte Zeit, andere Saison, Pause oder kein Text ergeben false (Paket 5.5).
function Seasons.zoneOpen(unixNow: any, zoneId: any, data: Data?): boolean
    if type(zoneId) ~= "string" then
        return false
    end
    local position = Seasons.at(unixNow, data)
    if position.active == nil or position.phase == nil then
        return false
    end
    return position.active.zoneId == zoneId and position.phase.zoneOpen == true
end

-- Die laufende Saison, wenn `zoneId` ihre Event-Zone ist und die Zone offen ist, sonst nil.
function Seasons.activeForZone(unixNow: any, zoneId: any, data: Data?): any?
    if not Seasons.zoneOpen(unixNow, zoneId, data) then
        return nil
    end
    return Seasons.at(unixNow, data).active
end

-- Anzeigeform für den StateSync (`season`). Nur Texte, Zahlen und Wahrheitswerte.
function Seasons.state(unixNow: any, data: Data?): { [string]: any }
    local position = Seasons.at(unixNow, data)
    if position.active ~= nil and position.phase ~= nil then
        return {
            active = true,
            id = position.active.id,
            name = position.active.name,
            week = position.week,
            phaseId = position.phase.id,
            phaseName = position.phase.name,
            hint = position.phase.hint,
            secondsLeft = position.secondsLeft,
            crateId = position.active.crateId,
            crateOpen = position.phase.crateOpen == true,
            zoneId = position.active.zoneId,
            zoneOpen = position.phase.zoneOpen == true,
        }
    end
    local result: { [string]: any } = { active = false }
    if position.nextSeason ~= nil then
        result.next = {
            id = position.nextSeason.id,
            name = position.nextSeason.name,
            crateId = position.nextSeason.crateId,
            zoneId = position.nextSeason.zoneId,
            secondsToNext = position.secondsToNext,
        }
    end
    return result
end

-- Die zuletzt beendete Saison (größtes Ende, das nicht nach `unixNow` liegt; das Ende ist
-- ausschließend, in der Sekunde des Endes ist sie also schon beendet) und die Sekunden seit ihrem Ende
-- (ab 0). (nil, nil), wenn noch keine Saison beendet ist oder die Zeit kaputt ist. Zeilen mit kaputtem
-- Datum werden übersprungen (Paket 5.5b, Abholfrist des Saison-Passes).
function Seasons.lastEnded(unixNow: any, data: Data?): (any?, number?)
    if not isFinite(unixNow) or unixNow < 0 then
        return nil, nil
    end
    local set = dataOf(data)
    local length = lengthOf(set)
    local found: any = nil
    local foundEnd = -math.huge
    for _, season in set.list do
        local start = Seasons.startOf(season)
        if start ~= nil then
            local finish = start + length
            if finish <= unixNow and finish > foundEnd then
                found, foundEnd = season, finish
            end
        end
    end
    if found == nil then
        return nil, nil
    end
    return found, unixNow - foundEnd
end

-- Studio-Hilfe: "off", "clear", "ended", "koloss" (Paket 5.6, die Zeit rechnet Logic/Koloss) oder "week:N" (N = 1 bis Anzahl Wochen). Alles andere ergibt nil.
function Seasons.parseDebug(value: any, data: Data?): (string?, number?)
    if type(value) ~= "string" then
        return nil, nil
    end
    if value == "off" or value == "clear" or value == "ended" or value == "koloss" then
        return value, nil
    end
    local text = string.match(value, "^week:(%d+)$")
    if text == nil then
        return nil, nil
    end
    local week = tonumber(text) :: number
    if week < 1 or week > #dataOf(data).phases then
        return nil, nil
    end
    return "week", week
end

-- Saison, auf die die Studio-Hilfe zielt: die laufende, sonst die nächste, sonst die erste der Tabelle
-- (frühester Start). Gemessen an der echten Zeit `unixNow`, damit das Ziel fest bleibt.
local function debugTarget(unixNow: number, set: Data): any?
    local position = Seasons.at(unixNow, set)
    local target: any = position.active or position.nextSeason
    if target == nil then
        local earliest = math.huge
        for _, season in set.list do
            local start = Seasons.startOf(season)
            if start ~= nil and start < earliest then
                target, earliest = season, start
            end
        end
    end
    return target
end

-- Zeit, die die Studio-Hilfe an Stelle der Server-Uhr benutzt. "clear" ergibt nil (echte Zeit),
-- "off" eine Zeit vor allen Saisons, "week" die Mitte der Woche N der laufenden oder sonst der
-- nächsten oder sonst der ersten Saison, "ended" einen Tag nach dem Ende derselben Saison (für die
-- Abholfrist des Saison-Passes, Paket 5.5b). nil, wenn es keine Saison mit gültigem Datum gibt.
function Seasons.debugTime(action: string, week: number?, unixNow: number, data: Data?): number?
    if action == "clear" then
        return nil
    end
    if action == "off" then
        return 0
    end
    if action ~= "week" and action ~= "ended" then
        return nil
    end
    if action == "week" and week == nil then
        return nil
    end
    local set = dataOf(data)
    local start = Seasons.startOf(debugTarget(unixNow, set))
    if start == nil then
        return nil
    end
    if action == "ended" then
        return start + lengthOf(set) + Seasons.SECONDS_PER_DAY
    end
    return start + ((week :: number) - 1) * Seasons.WEEK_SECONDS + Seasons.WEEK_SECONDS / 2
end

return Seasons
