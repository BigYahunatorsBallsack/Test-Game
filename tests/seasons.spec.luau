--!strict
-- Paket 5.4: Event-Kalender (Logic/Seasons, Data/Seasons). Zeitpunkte und Wochengrenzen, Pause,
-- Kiste offen, kaputte Zeit, neue Zeile ohne Code, CrateOpen mit der Event-Kiste, DataCheck,
-- Studio-Hilfe, Anzeigeform, keine neue Remote.

local T = require("./lib/expect")
local Seasons = require("../src/shared/Logic/Seasons")
local SeasonData = require("../src/shared/Data/Seasons")
local CrateOpen = require("../src/shared/Logic/CrateOpen")
local CrateItems = require("../src/shared/Data/CrateItems")
local Crates = require("../src/shared/Data/Crates")
local DataCheck = require("../src/shared/Logic/DataCheck")
local Profile = require("../src/shared/Logic/Profile")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")

local DAY = Seasons.SECONDS_PER_DAY
local WEEK = Seasons.WEEK_SECONDS

-- Testtabelle mit den echten Wochen und zwei Saisons mit Pause dazwischen.
local function tableOf(rows: { any }?): any
    return {
        phases = SeasonData.phases,
        list = rows or {
            { id = "a", name = "Saison A", startDate = "2027-01-04", crateId = "event" },
            { id = "b", name = "Saison B", startDate = "2027-03-01", crateId = "event_b" },
        },
    }
end

local DATA = tableOf()
local A_START = Seasons.parseDate("2027-01-04") :: number
local A_END = A_START + 4 * WEEK
local B_START = Seasons.parseDate("2027-03-01") :: number

local function deepCopy(value: any, memo: { [any]: any }?): any
    if type(value) ~= "table" then
        return value
    end
    local seen = memo or {}
    if seen[value] ~= nil then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, inner in value do
        copy[deepCopy(key, seen)] = deepCopy(inner, seen)
    end
    return copy
end

T.describe("Datum", function()
    T.it("parseDate: bekannte Tage und Montag-Prüfung", function()
        T.expect(Seasons.parseDate("1970-01-01")).toBe(0)
        T.expect(Seasons.parseDate("2000-03-01")).toBe(951868800)
        T.expect(Seasons.parseDate("2027-01-04")).toBe(1799020800)
        T.expect(Seasons.isMondayStart(A_START)).toBe(true)
        T.expect(Seasons.isMondayStart(A_START + DAY)).toBe(false)
        T.expect(Seasons.isMondayStart(A_START + 1)).toBe(false)
        T.expect(Seasons.isMondayStart(-1)).toBe(false)
    end)

    T.it("parseDate: falsche Form und Tage, die es nicht gibt", function()
        for _, text in { "2027-02-30", "2027-13-01", "2027-00-10", "2027-01-00", "27-01-04", "2027-1-4", "2027/01/04", "", "heute" } do
            T.expect(Seasons.parseDate(text)).toBeNil()
        end
        T.expect(Seasons.parseDate(5 :: any)).toBeNil()
        T.expect(Seasons.parseDate(nil :: any)).toBeNil()
        T.expect(Seasons.parseDate("2028-02-29")).toBeTruthy() -- Schaltjahr
        T.expect(Seasons.parseDate("2027-02-29")).toBeNil()
    end)
end)

T.describe("Zeitpunkte einer Saison", function()
    T.it("eine Sekunde vor dem Start nichts, erste Sekunde Woche 1", function()
        local before = Seasons.at(A_START - 1, DATA)
        T.expect(before.active).toBeNil()
        T.expect(before.nextSeason.id).toBe("a")
        T.expect(before.secondsToNext).toBe(1)
        local first = Seasons.at(A_START, DATA)
        T.expect(first.active.id).toBe("a")
        T.expect(first.week).toBe(1)
        T.expect(first.phase.id).toBe("start")
        T.expect(first.secondsLeft).toBe(4 * WEEK)
    end)

    T.it("letzte Sekunde Woche 4, die Sekunde nach dem Ende nichts", function()
        local last = Seasons.at(A_END - 1, DATA)
        T.expect(last.active.id).toBe("a")
        T.expect(last.week).toBe(4)
        T.expect(last.phase.id).toBe("finale")
        T.expect(last.secondsLeft).toBe(1)
        T.expect(Seasons.at(A_END, DATA).active).toBeNil()
        T.expect(Seasons.endOf(DATA.list[1], DATA)).toBe(A_END)
    end)

    T.it("Wochengrenzen: Tage 0 bis 6, 7 bis 13, 14 bis 20, 21 bis 27", function()
        local expected = { "start", "koloss", "items", "finale" }
        for week = 1, 4 do
            local first = Seasons.at(A_START + (week - 1) * WEEK, DATA)
            local last = Seasons.at(A_START + week * WEEK - 1, DATA)
            T.expect(first.week).toBe(week)
            T.expect(last.week).toBe(week)
            T.expect(first.phase.id).toBe(expected[week])
            T.expect(last.phase.id).toBe(expected[week])
        end
        for day = 0, 27 do
            T.expect(Seasons.at(A_START + day * DAY + 5, DATA).week).toBe(math.floor(day / 7) + 1)
        end
    end)
end)

T.describe("Pause und Reihenfolge", function()
    T.it("zwischen zwei Saisons ist nichts aktiv, next nennt Saison B und die Sekunden", function()
        local pause = Seasons.at(A_END + DAY, DATA)
        T.expect(pause.active).toBeNil()
        T.expect(pause.week).toBeNil()
        T.expect(pause.nextSeason.id).toBe("b")
        T.expect(pause.secondsToNext).toBe(B_START - (A_END + DAY))
        T.expect(Seasons.at(B_START, DATA).active.id).toBe("b")
    end)

    T.it("nach der letzten Saison gibt es kein next", function()
        local after = Seasons.at(B_START + 4 * WEEK, DATA)
        T.expect(after.active).toBeNil()
        T.expect(after.nextSeason).toBeNil()
        T.expect(after.secondsToNext).toBe(0)
    end)

    T.it("die Reihenfolge der Zeilen spielt keine Rolle", function()
        local swapped = tableOf({ DATA.list[2], DATA.list[1] })
        T.expect(Seasons.at(A_START + 5, swapped).active.id).toBe("a")
        T.expect(Seasons.at(A_END + 5, swapped).nextSeason.id).toBe("b")
    end)
end)

T.describe("Kiste offen", function()
    T.it("nur die Event-Kiste der aktiven Saison", function()
        T.expect(Seasons.inSeason(A_START + 5, "event", DATA)).toBe(true)
        T.expect(Seasons.inSeason(A_START + 5, "event_b", DATA)).toBe(false) -- kommende Saison
        T.expect(Seasons.inSeason(A_START + 5, "gold", DATA)).toBe(false)
        T.expect(Seasons.inSeason(B_START + 5, "event", DATA)).toBe(false) -- vergangene Saison
        T.expect(Seasons.inSeason(B_START + 5, "event_b", DATA)).toBe(true)
        T.expect(Seasons.inSeason(A_END + DAY, "event", DATA)).toBe(false) -- Pause
        T.expect(Seasons.inSeason(A_START - 1, "event", DATA)).toBe(false)
        T.expect(Seasons.inSeason(A_START + 5, 1 :: any, DATA)).toBe(false)
        T.expect(Seasons.inSeason(A_START + 5, nil :: any, DATA)).toBe(false)
    end)

    T.it("nur in Phasen mit crateOpen", function()
        local closed = deepCopy(DATA)
        closed.phases[2].crateOpen = false
        T.expect(Seasons.inSeason(A_START + 1 * WEEK + 5, "event", closed)).toBe(false)
        T.expect(Seasons.inSeason(A_START + 5, "event", closed)).toBe(true)
        T.expect(Seasons.inSeason(A_START + 3 * WEEK + 5, "event", closed)).toBe(true)
    end)

    T.it("die echte Tabelle: Saison 1 öffnet die Event-Kiste in allen vier Wochen", function()
        local start = Seasons.startOf(SeasonData.list[1]) :: number
        for week = 1, 4 do
            T.expect(Seasons.inSeason(start + (week - 1) * WEEK + 5, SeasonData.list[1].crateId)).toBe(true)
        end
        T.expect(Seasons.inSeason(start - 1, SeasonData.list[1].crateId)).toBe(false)
        T.expect(Seasons.inSeason(start + 4 * WEEK, SeasonData.list[1].crateId)).toBe(false)
    end)
end)

T.describe("Kaputte Zeit", function()
    T.it("kein number, NaN, unendlich, negativ: nichts aktiv, kein Fehler", function()
        for _, bad in { "jetzt" :: any, 0 / 0, math.huge, -math.huge, -5, nil :: any, {} :: any, true :: any } do
            local position = Seasons.at(bad, DATA)
            T.expect(position.active).toBeNil()
            T.expect(position.nextSeason).toBeNil()
            T.expect(Seasons.inSeason(bad, "event", DATA)).toBe(false)
            T.expect(Seasons.state(bad, DATA).active).toBe(false)
        end
    end)

    T.it("eine Zeile mit kaputtem Datum wird übersprungen, die anderen laufen weiter", function()
        local data = tableOf({
            { id = "kaputt", name = "x", startDate = "2027-02-30", crateId = "event" },
            { id = "a", name = "Saison A", startDate = "2027-01-04", crateId = "event" },
        })
        T.expect(Seasons.at(A_START + 5, data).active.id).toBe("a")
        T.expect(Seasons.at(0, data).nextSeason.id).toBe("a")
    end)
end)

T.describe("Neue Saison ohne Code-Änderung", function()
    T.it("eine zusätzliche Tabellenzeile macht die Saison aktiv", function()
        local rows = deepCopy(DATA.list)
        table.insert(rows, { id = "c", name = "Saison C", startDate = "2027-05-03", crateId = "event_c" })
        local data = tableOf(rows)
        local cStart = Seasons.parseDate("2027-05-03") :: number
        T.expect(Seasons.inSeason(cStart + 3 * DAY, "event_c", DATA)).toBe(false) -- ohne die Zeile
        T.expect(Seasons.inSeason(cStart + 3 * DAY, "event_c", data)).toBe(true)
        T.expect(Seasons.state(cStart + 3 * DAY, data).name).toBe("Saison C")
    end)
end)

T.describe("Anzeigeform", function()
    T.it("in der Saison: id, Name, Woche, Phase, Sekunden, Kiste, Hinweis in Woche 4", function()
        local state = Seasons.state(A_START + 2 * WEEK + 100, DATA)
        T.expect(state.active).toBe(true)
        T.expect(state.id).toBe("a")
        T.expect(state.name).toBe("Saison A")
        T.expect(state.week).toBe(3)
        T.expect(state.phaseId).toBe("items")
        T.expect(state.secondsLeft).toBe(2 * WEEK - 100)
        T.expect(state.crateId).toBe("event")
        T.expect(state.crateOpen).toBe(true)
        T.expect(state.hint).toBeNil()
        local finale = Seasons.state(A_START + 3 * WEEK + 100, DATA)
        T.expect(finale.hint).toBe(SeasonData.phases[4].hint)
    end)

    T.it("in der Pause: active false und next mit secondsToNext, nur einfache Werte", function()
        local state = Seasons.state(A_END + 10, DATA)
        T.expect(state.active).toBe(false)
        T.expect(state.next.id).toBe("b")
        T.expect(state.next.name).toBe("Saison B")
        T.expect(state.next.crateId).toBe("event_b")
        T.expect(state.next.secondsToNext).toBe(B_START - A_END - 10)
        for key, value in state do
            T.expect(type(key)).toBe("string")
            T.expect(type(value) == "table" or type(value) == "string" or type(value) == "number" or type(value) == "boolean").toBe(true)
        end
    end)

    T.it("nach der letzten Saison: nur active false", function()
        T.expect(Seasons.state(B_START + 4 * WEEK, DATA)).toEqual({ active = false })
    end)
end)

T.describe("Event-Kiste und CrateOpen", function()
    local function rich(): any
        local profile = Profile.default(A_START)
        profile.gems = 100000
        return profile
    end

    local function context(unixNow: number): any
        return {
            random = function(): number
                return 0
            end,
            restricted = false,
            inSeason = Seasons.inSeason(unixNow, "event", SeasonData),
        }
    end

    T.it("außerhalb der Saison: notInSeason, nichts gebucht", function()
        local start = Seasons.startOf(SeasonData.list[1]) :: number
        for _, now in { start - 1, start + 4 * WEEK, 0 } do
            local profile = rich()
            local before = deepCopy(profile)
            T.expect(CrateOpen.open(profile, "event", 1, context(now)).reason).toBe("notInSeason")
            T.expect(profile).toEqual(before)
        end
    end)

    T.it("in der Saison: öffnet mit denselben Quoten wie die Goldkiste, bucht Gems, Pity und Inventar", function()
        local start = Seasons.startOf(SeasonData.list[1]) :: number
        T.expect(Crates.byId.event.odds).toBe(Crates.byId.gold.odds)
        local profile = rich()
        local before = deepCopy(profile)
        local result = CrateOpen.open(profile, "event", 1, context(start + 5))
        T.expect(result.ok).toBe(true)
        T.expect(profile.gems).toBe(100000 - Crates.byId.event.price)
        T.expect(result.pity.sinceEpic).toBe(1)
        T.expect(profile.pity.event.sinceEpic).toBe(1)
        T.expect(profile.pity.gold).toEqual(before.pity.gold)
        local itemId = result.results[1].itemId
        T.expect(table.find(CrateItems.byId[itemId].crates, "event")).toBeTruthy()
    end)

    T.it("Besitz bleibt nach Saisonende, nur das Öffnen ist gesperrt", function()
        local start = Seasons.startOf(SeasonData.list[1]) :: number
        local profile = rich()
        local result = CrateOpen.open(profile, "event", 1, context(start + 5))
        T.expect(result.ok).toBe(true)
        local itemId = result.results[1].itemId
        local field = CrateOpen.INVENTORY_FIELDS[CrateItems.byId[itemId].kind]
        local owned = profile.inventory[field][itemId]
        T.expect(owned >= 1).toBe(true)
        T.expect(CrateOpen.open(profile, "event", 1, context(start + 4 * WEEK)).reason).toBe("notInSeason")
        T.expect(profile.inventory[field][itemId]).toBe(owned)
        T.expect(profile.pity.event ~= nil).toBe(true)
    end)
end)

T.describe("DataCheck", function()
    local function broken(change: (data: any) -> ()): { string }
        local data = deepCopy(DataCheck.defaults())
        change(data)
        return DataCheck.run(data)
    end

    local function expectError(errors: { string }, fragment: string)
        T.expect(#errors > 0).toBe(true)
        T.expect(table.concat(errors, "\n")).toContain(fragment)
    end

    T.it("die echten Tabellen sind in Ordnung, ein anderer Montag ebenso", function()
        T.expect(DataCheck.run()).toEqual({})
        T.expect(broken(function(d)
            d.Seasons.list[1].startDate = "2027-06-07"
        end)).toEqual({})
    end)

    T.it("doppelte ID, Start kein Montag, ungültiges Datum, Name", function()
        expectError(broken(function(d)
            table.insert(d.Seasons.list, { id = "season_1", name = "x", startDate = "2028-01-03", crateId = "gold" })
        end), 'doppelte id "season_1"')
        expectError(broken(function(d)
            d.Seasons.list[1].startDate = "2027-01-05"
        end), "kein Montag")
        expectError(broken(function(d)
            d.Seasons.list[1].startDate = "2027-02-30"
        end), "gültiges Datum")
        expectError(broken(function(d)
            d.Seasons.list[1].startDate = nil
        end), "gültiges Datum")
        expectError(broken(function(d)
            d.Seasons.list[1].name = ""
        end), "name muss ein nicht leerer Text")
    end)

    T.it("Überlappung", function()
        expectError(broken(function(d)
            table.insert(d.Seasons.list, { id = "zwei", name = "Zwei", startDate = "2027-01-18", crateId = "gold" })
        end), "überlappt")
        -- genau nach dem Ende ist keine Überlappung
        local errors = broken(function(d)
            table.insert(d.Seasons.list, { id = "zwei", name = "Zwei", startDate = "2027-02-01", crateId = "gold" })
        end)
        T.expect(string.find(table.concat(errors, "\n"), "überlappt", 1, true) == nil).toBe(true)
    end)

    T.it("Kisten: unbekannt, keine Event-Kiste, Event-Kiste ohne Saison, dieselbe Kiste zweimal", function()
        expectError(broken(function(d)
            d.Seasons.list[1].crateId = "silber"
        end), 'crateId "silber" steht nicht in Crates')
        expectError(broken(function(d)
            d.Seasons.list[1].crateId = "gold"
        end), "keine Event-Kiste")
        expectError(broken(function(d)
            d.Seasons.list = {}
        end), 'Kiste "event" ist eine Event-Kiste ohne Saison')
        expectError(broken(function(d)
            table.insert(d.Seasons.list, { id = "zwei", name = "Zwei", startDate = "2027-03-01", crateId = "event" })
        end), 'Kiste "event" gehört schon zu Saison "season_1"')
    end)

    T.it("zoneId und passId werden nur geprüft, wenn sie gesetzt sind", function()
        T.expect(broken(function(d)
            d.Seasons.list[1].passId = nil
        end)).toEqual({})
        expectError(broken(function(d)
            d.Seasons.list[1].zoneId = "nirgends"
        end), 'zoneId "nirgends" steht nicht in Zones.events')
        expectError(broken(function(d)
            d.Seasons.list[1].passId = "nirgends"
        end), 'passId "nirgends" steht nicht in Products')
        T.expect(broken(function(d)
            d.Seasons.list[1].passId = "season_pass"
        end)).toEqual({})
    end)

    T.it("Phasen: leer, doppelte ID, crateOpen kein Wahrheitswert; fehlende Tabelle", function()
        expectError(broken(function(d)
            d.Seasons.phases = {}
        end), "mindestens eine Woche")
        expectError(broken(function(d)
            d.Seasons.phases[2].id = "start"
        end), 'doppelte id "start"')
        expectError(broken(function(d)
            d.Seasons.phases[1].crateOpen = 1
        end), "crateOpen muss true oder false")
        expectError(broken(function(d)
            d.Seasons = nil
        end), "Seasons: phases und list fehlen")
    end)
end)

T.describe("Studio-Hilfe", function()
    T.it("parseDebug: off, clear, ended und week:1 bis week:4, alles andere nichts", function()
        local action, week = Seasons.parseDebug("off")
        T.expect(action).toBe("off")
        T.expect(week).toBeNil()
        T.expect((Seasons.parseDebug("clear"))).toBe("clear")
        local ended, endedWeek = Seasons.parseDebug("ended")
        T.expect(ended).toBe("ended")
        T.expect(endedWeek).toBeNil()
        for _, bad in { "Ended", "ended:1", "end", " ended" } do
            T.expect((Seasons.parseDebug(bad))).toBeNil()
        end
        for number = 1, 4 do
            local a, w = Seasons.parseDebug(`week:{number}`)
            T.expect(a).toBe("week")
            T.expect(w).toBe(number)
        end
        for _, bad in { "week:0", "week:5", "week:", "week:-1", "week:1.5", "Week:1", "an", "", 3 :: any, nil :: any, true :: any } do
            local a, w = Seasons.parseDebug(bad)
            T.expect(a).toBeNil()
            T.expect(w).toBeNil()
        end
    end)

    T.it("debugTime: week:N liegt in Woche N der nächsten Saison, off davor, clear echte Zeit", function()
        for week = 1, 4 do
            local time = Seasons.debugTime("week", week, 0, DATA) :: number
            local position = Seasons.at(time, DATA)
            T.expect(position.week).toBe(week)
            T.expect(position.active.id).toBe("a")
        end
        -- läuft Saison B gerade, gilt Saison B
        local inB = Seasons.debugTime("week", 2, B_START + 5, DATA) :: number
        T.expect(Seasons.at(inB, DATA).active.id).toBe("b")
        T.expect(Seasons.at(Seasons.debugTime("off", nil, A_START + 5, DATA) :: number, DATA).active).toBeNil()
        T.expect(Seasons.debugTime("clear", nil, A_START + 5, DATA)).toBeNil()
        T.expect(Seasons.debugTime("week", 1, 0, tableOf({}))).toBeNil()
    end)

    T.it("debugTime: ended liegt einen Tag nach dem Ende der Saison, auf die week:N zielt", function()
        -- vor allen Saisons: die nächste (A)
        local beforeAll = Seasons.debugTime("ended", nil, 0, DATA) :: number
        T.expect(beforeAll).toBe(A_END + DAY)
        T.expect(Seasons.at(beforeAll, DATA).active).toBeNil()
        local last, since = Seasons.lastEnded(beforeAll, DATA)
        T.expect(last.id).toBe("a")
        T.expect(since).toBe(DAY)
        -- während A: A; während B: B; nach allen: die erste (A)
        T.expect(Seasons.debugTime("ended", nil, A_START + 5, DATA)).toBe(A_END + DAY)
        T.expect(Seasons.debugTime("ended", nil, B_START + 5, DATA)).toBe(B_START + 4 * WEEK + DAY)
        T.expect(Seasons.debugTime("ended", nil, B_START + 10 * WEEK, DATA)).toBe(A_END + DAY)
        -- ohne Saison mit gültigem Datum: nil (echte Zeit)
        T.expect(Seasons.debugTime("ended", nil, 0, tableOf({}))).toBeNil()
        -- unbekannte Befehle und week ohne Zahl: nil
        T.expect(Seasons.debugTime("week", nil, 0, DATA)).toBeNil()
        T.expect(Seasons.debugTime("irgendwas", nil, 0, DATA)).toBeNil()
    end)
end)

T.describe("Keine Remote für Zeit", function()
    -- Seit 5.5b gibt es genau zwei Remotes mit "Season" im Namen (Saison-Pass). Keine nimmt eine Zeit,
    -- eine Saison-ID oder eine Woche: die Saison bestimmt allein der Server mit seiner Uhr.
    local PASS_REMOTES = { BuySeasonPass = true, ClaimSeasonReward = true }

    T.it("RemoteSpec kennt keine Remote für Saisons oder Zeit außer den zwei Pass-Remotes (5.5b)", function()
        for name in RemoteSpec.byName do
            local lower = string.lower(tostring(name))
            local mentions = string.find(lower, "season") ~= nil or string.find(lower, "saison") ~= nil or string.find(lower, "event") ~= nil
            T.expect(mentions == (PASS_REMOTES[name] == true)).toBe(true)
            T.expect(string.find(lower, "time") == nil and string.find(lower, "week") == nil and string.find(lower, "clock") == nil).toBe(true)
        end
    end)

    T.it("die Pass-Remotes nehmen keine Zeit und keine Saison: kein Text, nur Stufe 1 bis 50 und Spur", function()
        T.expect(RemoteSpec.byName.BuySeasonPass.schema).toEqual({})
        local schema = RemoteSpec.byName.ClaimSeasonReward.schema :: { any }
        T.expect(#schema).toBe(2)
        T.expect(schema[1]).toEqual({ kind = "int", min = 1, max = 50 })
        T.expect(schema[2]).toEqual({ kind = "oneOf", values = { "free", "premium" } })
    end)
end)

T.describe("Zuletzt beendete Saison (lastEnded, Paket 5.5b)", function()
    T.it("vor dem ersten Ende nichts, ab der Sekunde des Endes die Saison und die Sekunden seit dem Ende", function()
        local none, noSeconds = Seasons.lastEnded(A_END - 1, DATA)
        T.expect(none).toBeNil()
        T.expect(noSeconds).toBeNil()
        local season, since = Seasons.lastEnded(A_END, DATA)
        T.expect(season.id).toBe("a")
        T.expect(since).toBe(0)
        local later, laterSince = Seasons.lastEnded(A_END + 3 * DAY + 7, DATA)
        T.expect(later.id).toBe("a")
        T.expect(laterSince).toBe(3 * DAY + 7)
    end)

    T.it("während Saison B gilt A als zuletzt beendet, nach B dann B; Reihenfolge der Zeilen egal", function()
        local during = Seasons.lastEnded(B_START + 5, DATA)
        T.expect(during.id).toBe("a")
        local after, since = Seasons.lastEnded(B_START + 4 * WEEK + 10, DATA)
        T.expect(after.id).toBe("b")
        T.expect(since).toBe(10)
        local swapped = tableOf({ DATA.list[2], DATA.list[1] })
        T.expect((Seasons.lastEnded(B_START + 4 * WEEK + 10, swapped)).id).toBe("b")
        T.expect((Seasons.lastEnded(A_END + 10, swapped)).id).toBe("a")
    end)

    T.it("kaputte Zeit, leere Tabelle und kaputtes Datum: nichts bzw. übersprungen", function()
        for _, bad in { 0 / 0, math.huge, -1, "x" :: any, nil :: any } do
            T.expect((Seasons.lastEnded(bad, DATA))).toBeNil()
        end
        T.expect((Seasons.lastEnded(A_END + 10, tableOf({})))).toBeNil()
        local rows = { { id = "kaputt", name = "K", startDate = "2027-02-30", crateId = "x" }, DATA.list[1] }
        T.expect((Seasons.lastEnded(A_END + 10, tableOf(rows))).id).toBe("a")
    end)

    T.it("die echte Tabelle: Saison 1 ist einen Tag nach ihrem Ende die zuletzt beendete", function()
        local start = Seasons.startOf(SeasonData.list[1]) :: number
        local season, since = Seasons.lastEnded(start + 4 * WEEK + DAY)
        T.expect(season.id).toBe("season_1")
        T.expect(since).toBe(DAY)
    end)
end)

T.finish()
