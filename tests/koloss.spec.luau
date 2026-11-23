--!strict
-- Lune-Tests für das Server-Event "Der Koloss" (Paket 5.6): Fenster, Fortschritt, Beitrag, Stufen,
-- Belohnung einmal je Saison, Anzeigeform, Studio-Hilfen und die Anbindung der Services.
-- Ausführen: lune run tests/koloss.spec

local T = require("./lib/expect")
local fs = require("@lune/fs")
local Koloss = require("../src/shared/Logic/Koloss")
local Seasons = require("../src/shared/Logic/Seasons")
local SeasonPass = require("../src/shared/Logic/SeasonPass")
local Profile = require("../src/shared/Logic/Profile")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local BigNum = require("../src/shared/Logic/BigNum")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local DataCheck = require("../src/shared/Logic/DataCheck")
local KolossData = require("../src/shared/Data/Koloss")
local SeasonData = require("../src/shared/Data/Seasons")
local Economy = require("../src/shared/Data/Economy")

local EVENTS_SOURCE: string = fs.readFile("src/server/Services/Events.luau")
local SERVICE_SOURCE: string = fs.readFile("src/server/Services/Koloss.luau")
local BOOTSTRAP_SOURCE: string = fs.readFile("src/server/init.server.luau")
local CLOCK_SOURCE: string = fs.readFile("src/server/Services/SeasonClock.luau")

local SEASON_ID = "season_1"
local DAY = Seasons.SECONDS_PER_DAY
local WEEK = Seasons.WEEK_SECONDS
local START = Seasons.startOf(SeasonData.list[1]) :: number
local WINDOW_START = START + WEEK + KolossData.window.startDay * DAY -- Samstag der Woche 2
local WINDOW_END = WINDOW_START + KolossData.window.days * DAY -- Montag der Woche 3
local OPEN = WINDOW_START + 3600
local TARGET = KolossData.targetSeconds
local MAX_GEMS = Economy.purchases.maxGems
local REAL_NOW = 1_700_000_000
local USER = 42
local OTHER = 43

local function deepCopy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in value do
        copy[deepCopy(key)] = deepCopy(inner)
    end
    return copy
end

local function newProfile(): any
    return Profile.default(REAL_NOW)
end

T.describe("Fenster", function()
    T.it("Samstag 0 Uhr bis Montag 0 Uhr UTC der Koloss-Woche, das Ende ist ausschließend", function()
        T.expect(Koloss.window(WINDOW_START - 1).state).toBe("upcoming")
        T.expect(Koloss.window(WINDOW_START).state).toBe("open")
        T.expect(Koloss.window(WINDOW_END - 1).state).toBe("open")
        T.expect(Koloss.window(WINDOW_END).state).toBe("over")
        local window = Koloss.window(OPEN)
        T.expect(window.seasonId).toBe(SEASON_ID)
        T.expect(window.secondsLeft).toBe(WINDOW_END - OPEN)
        T.expect(window.secondsToStart).toBe(0)
        T.expect(Koloss.window(WINDOW_START - 10).secondsToStart).toBe(10)
    end)

    T.it("Samstag ist Tag 5 ab Montag: das Fenster dauert 48 Stunden", function()
        T.expect(WINDOW_END - WINDOW_START).toBe(2 * DAY)
        T.expect(KolossData.window.startDay).toBe(5)
    end)

    T.it("Woche 1, Woche 3 und 4 gehören zur Saison, aber nicht zum Fenster", function()
        T.expect(Koloss.window(START + 2 * DAY).state).toBe("upcoming")
        T.expect(Koloss.window(START + 3 * WEEK).state).toBe("over")
    end)

    T.it("außerhalb einer Saison und bei kaputter Zeit: none", function()
        T.expect(Koloss.window(0).state).toBe("none")
        T.expect(Koloss.window(START + 4 * WEEK).state).toBe("none")
        for _, bad in { 0 / 0, math.huge, -math.huge, -1, "x" :: any, nil :: any, true :: any } do
            local window = Koloss.window(bad)
            T.expect(window.state).toBe("none")
            T.expect(window.seasonId).toBeNil()
        end
    end)

    T.it("eine zweite Saison nur über Daten", function()
        local calendar = { phases = SeasonData.phases, list = { { id = "s2", name = "S2", startDate = "2027-06-07", crateId = "event" } } }
        local start2 = Seasons.parseDate("2027-06-07") :: number
        local window = Koloss.window(start2 + WEEK + 5 * DAY + 10, { Seasons = calendar })
        T.expect(window.state).toBe("open")
        T.expect(window.seasonId).toBe("s2")
    end)

    T.it("kaputte Daten (Phase gibt es nicht) ergeben none", function()
        local data = { Koloss = { window = { phaseId = "gibtsnicht", startDay = 5, days = 2 }, targetSeconds = TARGET, tiers = KolossData.tiers } }
        T.expect(Koloss.window(OPEN, data).state).toBe("none")
    end)
end)

T.describe("Fortschritt", function()
    T.it("zählt nur bei offenem Fenster", function()
        local event = Koloss.newEvent()
        T.expect(Koloss.addSeconds(event, WINDOW_START - 1, USER, 10).gained).toBe(0)
        T.expect(Koloss.addSeconds(event, WINDOW_END, USER, 10).gained).toBe(0)
        T.expect(Koloss.addSeconds(event, 0, USER, 10).gained).toBe(0)
        T.expect(event.progress).toBe(0)
        T.expect(Koloss.addSeconds(event, OPEN, USER, 10).gained).toBe(10)
        T.expect(event.progress).toBe(10)
        T.expect(event.contributions[USER]).toBe(10)
    end)

    T.it("kaputte Sekunden und UserIds ändern nichts", function()
        local event = Koloss.newEvent()
        for _, bad in { 0, -5, 0 / 0, math.huge, -math.huge, "10" :: any, nil :: any, true :: any } do
            T.expect(Koloss.addSeconds(event, OPEN, USER, bad).gained).toBe(0)
        end
        for _, bad in { 0, -1, 1.5, 0 / 0, math.huge, "42" :: any, nil :: any } do
            T.expect(Koloss.addSeconds(event, OPEN, bad, 10).gained).toBe(0)
        end
        T.expect(event.progress).toBe(0)
        T.expect(next(event.contributions)).toBeNil()
    end)

    T.it("mehrere Spieler füllen denselben Balken, jeder mit seinem Beitrag", function()
        local event = Koloss.newEvent()
        Koloss.addSeconds(event, OPEN, USER, 100)
        Koloss.addSeconds(event, OPEN, OTHER, 50)
        Koloss.addSeconds(event, OPEN, USER, 25)
        T.expect(event.progress).toBe(175)
        T.expect(event.contributions[USER]).toBe(125)
        T.expect(event.contributions[OTHER]).toBe(50)
    end)

    T.it("bei 100 % gedeckelt: nur der Anteil bis zum Ziel zählt, completed genau einmal", function()
        local event = Koloss.newEvent()
        Koloss.addSeconds(event, OPEN, OTHER, TARGET - 5)
        local done = Koloss.addSeconds(event, OPEN, USER, 1000)
        T.expect(done.gained).toBe(5)
        T.expect(done.completed).toBe(true)
        T.expect(event.progress).toBe(TARGET)
        T.expect(event.completed).toBe(true)
        T.expect(event.contributions[USER]).toBe(5) -- nicht 1000
        local after = Koloss.addSeconds(event, OPEN, USER, 10)
        T.expect(after.gained).toBe(0)
        T.expect(after.completed).toBe(false)
        T.expect(event.progress).toBe(TARGET)
        T.expect(event.contributions[USER]).toBe(5)
    end)

    T.it("ein riesiger Wert füllt nie über das Ziel", function()
        local event = Koloss.newEvent()
        local result = Koloss.addSeconds(event, OPEN, USER, 1e300)
        T.expect(result.gained).toBe(TARGET)
        T.expect(event.progress).toBe(TARGET)
    end)

    T.it("eine neue Saison beginnt bei 0", function()
        local calendar = { phases = SeasonData.phases, list = { SeasonData.list[1], { id = "s2", name = "S2", startDate = "2027-06-07", crateId = "event" } } }
        local data = { Seasons = calendar }
        local event = Koloss.newEvent()
        Koloss.addSeconds(event, OPEN, USER, 100, data)
        T.expect(event.progress).toBe(100)
        local start2 = Seasons.parseDate("2027-06-07") :: number
        Koloss.addSeconds(event, start2 + WEEK + 5 * DAY + 5, USER, 7, data)
        T.expect(event.seasonId).toBe("s2")
        T.expect(event.progress).toBe(7)
        T.expect(event.contributions[USER]).toBe(7)
        T.expect(event.completed).toBe(false)
    end)

    T.it("reset leert alles", function()
        local event = Koloss.newEvent()
        Koloss.addSeconds(event, OPEN, USER, TARGET)
        Koloss.reset(event, SEASON_ID)
        T.expect(event.progress).toBe(0)
        T.expect(event.completed).toBe(false)
        T.expect(next(event.contributions)).toBeNil()
        T.expect(event.seasonId).toBe(SEASON_ID)
    end)
end)

T.describe("Stufen", function()
    local tiers = KolossData.tiers
    T.it("die Schwellen folgen der Zahl der Gräber: wenige Gräber gelten die festen Sekunden, viele den fairen Anteil", function()
        local dug, strong = tiers[2], tiers[3]
        -- 1 bis 6 Gräber: Stark bleibt bei 900 s (6000 / 6 = 1000 > 900).
        for diggers = 1, 6 do
            T.expect(Koloss.thresholdOf(strong, diggers)).toBe(strong.minSeconds)
        end
        -- 20 Gräber: fairer Anteil 300 s, Mitgegraben halb davon: 150 s.
        T.expect(Koloss.thresholdOf(strong, 20)).toBe(300)
        T.expect(Koloss.thresholdOf(dug, 20)).toBe(150)
        T.expect(Koloss.thresholdOf(dug, 1)).toBe(dug.minSeconds)
        -- Die erste Stufe bleibt bei 0, auch mit vielen Gräbern.
        T.expect(Koloss.thresholdOf(tiers[1], 100)).toBe(0)
        -- Wer bei 20 Gräbern seinen fairen Anteil gräbt, ist "Stark", wer 150 s gräbt "Mitgegraben".
        T.expect((Koloss.tierOf(300, nil, 20) :: any).id).toBe(strong.id)
        T.expect((Koloss.tierOf(150, nil, 20) :: any).id).toBe(dug.id)
        T.expect((Koloss.tierOf(149, nil, 20) :: any).id).toBe(tiers[1].id)
        -- Ohne Angabe oder mit kaputter Zahl gelten die festen Sekunden.
        T.expect((Koloss.tierOf(300, nil, nil) :: any).id).toBe(dug.id)
        T.expect((Koloss.tierOf(300, nil, 0 / 0) :: any).id).toBe(dug.id)
        T.expect((Koloss.tierOf(300, nil, 0) :: any).id).toBe(dug.id)
    end)

    T.it("die Zahl der Gräber zählt nur Beiträge über 0", function()
        local event = Koloss.newEvent()
        event.contributions = { [1] = 10, [2] = 0, [3] = 5, [4] = 0 / 0 }
        T.expect(Koloss.diggerCount(event)).toBe(2)
    end)

    T.it("die Belohnung nimmt die Zahl der Gräber mit (viele Gräber, fairer Anteil gibt Stark)", function()
        local profile = newProfile()
        local result = Koloss.claim(profile, SEASON_ID, 300, { boostNow = REAL_NOW, diggers = 20 })
        T.expect(result.ok).toBe(true)
        T.expect(result.tierId).toBe(tiers[3].id)
        local solo = Koloss.claim(newProfile(), SEASON_ID, 300, { boostNow = REAL_NOW, diggers = 1 })
        T.expect(solo.tierId).toBe(tiers[2].id)
    end)

    T.it("die Stufe zum Beitrag stimmt an den Grenzen", function()
        T.expect((Koloss.tierOf(0) :: any).id).toBe(tiers[1].id)
        for index = 2, #tiers do
            local edge = tiers[index].minSeconds
            T.expect((Koloss.tierOf(edge - 0.001) :: any).id).toBe(tiers[index - 1].id)
            T.expect((Koloss.tierOf(edge) :: any).id).toBe(tiers[index].id)
            T.expect((Koloss.tierOf(edge + 1e6) :: any).id).toBe(tiers[#tiers].id)
        end
    end)

    T.it("kaputte Beiträge ergeben keine Stufe", function()
        for _, bad in { -1, 0 / 0, math.huge, "5" :: any, nil :: any } do
            T.expect(Koloss.tierOf(bad)).toBeNil()
        end
    end)

    T.it("die erste Stufe gilt ab 0 Sekunden (alle im Server bei 100 %)", function()
        T.expect(tiers[1].minSeconds).toBe(0)
    end)
end)

T.describe("Belohnung", function()
    local function claim(profile: any, contribution: any, data: any?): any
        return Koloss.claim(profile, SEASON_ID, contribution, { boostNow = REAL_NOW, data = { Koloss = data } :: any })
    end

    T.it("gibt die Stufe zum Beitrag und den Merker, einmal je Saison", function()
        local profile = newProfile()
        local top = KolossData.tiers[#KolossData.tiers]
        local result = claim(profile, top.minSeconds)
        T.expect(result.ok).toBe(true)
        T.expect(result.tierId).toBe(top.id)
        T.expect(Koloss.isClaimed(profile, SEASON_ID)).toBe(true)
        T.expect(profile.seasons[SEASON_ID].koloss).toBe(true)
        local again = claim(profile, top.minSeconds)
        T.expect(again.ok).toBe(false)
        T.expect(again.reason).toBe("claimed")
    end)

    T.it("Gems und Boosts werden genau nach der Stufe gebucht", function()
        local profile = newProfile()
        local gemsBefore = profile.gems
        local tier = KolossData.tiers[2]
        local expectedGems = 0
        for _, reward in tier.rewards do
            if reward.kind == "gems" then
                expectedGems += reward.amount
            end
        end
        local result = claim(profile, tier.minSeconds)
        T.expect(result.ok).toBe(true)
        T.expect(profile.gems).toBe(gemsBefore + expectedGems)
        T.expect(#result.rewards).toBe(#tier.rewards)
        for _, reward in tier.rewards do
            if reward.kind == "luck" then
                T.expect(profile.boosts.luckUntil).toBe(REAL_NOW + reward.seconds)
            end
        end
    end)

    T.it("die erste Stufe (kein Beitrag) bekommt nur ihre eigene Belohnung", function()
        local profile = newProfile()
        local gemsBefore = profile.gems
        local result = claim(profile, 0)
        T.expect(result.ok).toBe(true)
        T.expect(result.tierId).toBe(KolossData.tiers[1].id)
        T.expect(profile.gems).toBe(gemsBefore)
    end)

    T.it("Gems sind bei maxGems gekappt, die Abholung gilt trotzdem", function()
        local profile = newProfile()
        profile.gems = MAX_GEMS - 5
        local top = KolossData.tiers[#KolossData.tiers]
        local result = claim(profile, top.minSeconds)
        T.expect(result.ok).toBe(true)
        T.expect(profile.gems).toBe(MAX_GEMS)
        local gemReward: any = nil
        for _, reward in result.rewards do
            if reward.kind == "gems" then
                gemReward = reward
            end
        end
        T.expect(gemReward.amount).toBe(5)
        T.expect(gemReward.capped).toBe(true)
    end)

    T.it("legt einen fehlenden Saison-Eintrag an und lässt andere Felder des Eintrags in Ruhe", function()
        local profile = newProfile()
        profile.seasons[SEASON_ID] = { seconds = 90, premium = true, claimed = { free = { ["1"] = true }, premium = {} } }
        claim(profile, 0)
        local entry = profile.seasons[SEASON_ID]
        T.expect(entry.seconds).toBe(90)
        T.expect(entry.premium).toBe(true)
        T.expect(entry.claimed.free["1"]).toBe(true)
        T.expect(entry.koloss).toBe(true)
        local other = newProfile()
        claim(other, 0)
        T.expect(other.seasons[SEASON_ID].seconds).toBe(0)
    end)

    T.it("ein Fehler bucht nichts: kaputte Belohnung, Kiste als Belohnung, kaputte Uhr", function()
        local function brokenData(reward: any): any
            local data = deepCopy(KolossData)
            data.tiers[1].rewards = { reward }
            return { Koloss = data }
        end
        for _, reward in { { kind = "crate", crateId = "gold" }, { kind = "coinBoost", seconds = 0 / 0 }, { kind = "unbekannt" } } do
            local profile = newProfile()
            local before = deepCopy(profile)
            local result = claim(profile, 0, brokenData(reward))
            T.expect(result.ok).toBe(false)
            T.expect(result.reason).toBe("error")
            T.expect(profile).toEqual(before)
        end
        local profile = newProfile()
        local before = deepCopy(profile)
        T.expect(Koloss.claim(profile, SEASON_ID, 0, { boostNow = 0 / 0 }).ok).toBe(false)
        T.expect(Koloss.claim(profile, SEASON_ID, 0, nil).ok).toBe(false)
        T.expect(Koloss.claim(profile, SEASON_ID, -1, { boostNow = REAL_NOW }).ok).toBe(false)
        T.expect(Koloss.claim(profile, 5 :: any, 0, { boostNow = REAL_NOW }).ok).toBe(false)
        T.expect(Koloss.claim(nil, SEASON_ID, 0, { boostNow = REAL_NOW }).ok).toBe(false)
        T.expect(profile).toEqual(before)
    end)

    T.it("Warten im Block bucht nichts", function()
        local profile = newProfile()
        local before = deepCopy(profile)
        local data = deepCopy(KolossData)
        -- Belohnungsliste, deren Durchlauf wartet: die Rechnung darf dann nichts buchen.
        data.tiers[1].rewards = setmetatable({}, {
            __iter = function()
                coroutine.yield()
                return next, {}, nil
            end,
        })
        local result = Koloss.claim(profile, SEASON_ID, 0, { boostNow = REAL_NOW, data = { Koloss = data } :: any })
        T.expect(result.ok).toBe(false)
        T.expect(profile).toEqual(before)
    end)

    T.it("eine ungültige Gems-Menge bucht nichts und setzt keinen Merker", function()
        for _, bad in { 0, -5, 2.5, 0 / 0, math.huge } do
            local profile = newProfile()
            local before = deepCopy(profile)
            local data = deepCopy(KolossData)
            data.tiers[1].rewards = { { kind = "gems", amount = bad } }
            local result = Koloss.claim(profile, SEASON_ID, 0, { boostNow = REAL_NOW, data = { Koloss = data } :: any })
            T.expect(result.ok).toBe(false)
            T.expect(profile).toEqual(before)
        end
    end)

    T.it("Belohnungen sind fest: nur Gems, Münz- und Glücks-Boost", function()
        for _, tier in KolossData.tiers do
            for _, reward in tier.rewards do
                T.expect(table.find(Koloss.REWARD_KINDS, reward.kind) ~= nil).toBe(true)
            end
        end
    end)
end)

T.describe("Anzeigeform (view)", function()
    T.it("während des Fensters: genau die vereinbarten Felder, nur der eigene Beitrag", function()
        local event = Koloss.newEvent()
        Koloss.addSeconds(event, OPEN, USER, 100)
        Koloss.addSeconds(event, OPEN, OTHER, 400)
        local view = Koloss.view(event, newProfile(), USER, OPEN) :: any
        local keys = {}
        for key in view do
            table.insert(keys, key)
        end
        table.sort(keys)
        T.expect(keys).toEqual({ "claimed", "completed", "diggers", "progress", "seasonId", "secondsLeft", "secondsToStart", "state", "target", "tierId", "you" })
        T.expect(view.state).toBe("open")
        T.expect(view.progress).toBe(500)
        T.expect(view.target).toBe(TARGET)
        T.expect(view.you).toBe(100)
        T.expect(view.completed).toBe(false)
        T.expect(view.claimed).toBe(false)
        T.expect(view.secondsLeft).toBe(WINDOW_END - OPEN)
        local viewOther = Koloss.view(event, newProfile(), OTHER, OPEN) :: any
        T.expect(viewOther.you).toBe(400)
    end)

    T.it("fertig und abgeholt: completed, claimed, Stufe", function()
        local event = Koloss.newEvent()
        Koloss.addSeconds(event, OPEN, USER, TARGET)
        local profile = newProfile()
        Koloss.claim(profile, SEASON_ID, TARGET, { boostNow = REAL_NOW })
        local view = Koloss.view(event, profile, USER, OPEN) :: any
        T.expect(view.completed).toBe(true)
        T.expect(view.claimed).toBe(true)
        T.expect(view.tierId).toBe(KolossData.tiers[#KolossData.tiers].id)
        T.expect(view.progress).toBe(TARGET)
    end)

    T.it("vor dem Fenster und danach: Zustand, Restzeit, kein fremder Fortschritt", function()
        local event = Koloss.newEvent()
        Koloss.addSeconds(event, OPEN, USER, 100)
        local before = Koloss.view(event, newProfile(), USER, WINDOW_START - 60) :: any
        T.expect(before.state).toBe("upcoming")
        T.expect(before.secondsToStart).toBe(60)
        local afterWindow = Koloss.view(event, newProfile(), USER, WINDOW_END + 1) :: any
        T.expect(afterWindow.state).toBe("over")
        T.expect(afterWindow.secondsLeft).toBe(0)
    end)

    T.it("ohne Saison: nil; die Werte enthalten nur Texte, Zahlen und Wahrheitswerte", function()
        T.expect(Koloss.view(Koloss.newEvent(), newProfile(), USER, 0)).toBeNil()
        local view = Koloss.view(Koloss.newEvent(), newProfile(), USER, OPEN) :: any
        for _, value in view do
            T.expect(type(value) == "string" or type(value) == "number" or type(value) == "boolean").toBe(true)
        end
    end)
end)

T.describe("Profil: Merker überlebt Laden, Speichern und Sandsturm", function()
    T.it("Säubern: nur true zählt, andere Felder des Eintrags bleiben", function()
        local profile: any = Profile.default(REAL_NOW)
        profile.seasons = {
            season_1 = { seconds = 10, premium = false, claimed = { free = {}, premium = {} }, koloss = true },
            season_2 = { seconds = 0, premium = false, claimed = { free = {}, premium = {} }, koloss = "ja" },
            season_3 = { seconds = 0, premium = false, claimed = { free = {}, premium = {} }, koloss = false },
        }
        Profile.sanitize(profile, REAL_NOW)
        T.expect(profile.seasons.season_1.koloss).toBe(true)
        T.expect(profile.seasons.season_1.seconds).toBe(10)
        T.expect(profile.seasons.season_2.koloss).toBeNil()
        T.expect(profile.seasons.season_3.koloss).toBeNil()
    end)

    T.it("Kopie des Profils nach Speichern und Laden behält den Merker", function()
        local profile = newProfile()
        Koloss.claim(profile, SEASON_ID, 0, { boostNow = REAL_NOW })
        local loaded = deepCopy(profile)
        Profile.sanitize(loaded, REAL_NOW)
        T.expect(Koloss.isClaimed(loaded, SEASON_ID)).toBe(true)
    end)

    T.it("der Sandsturm behält profile.seasons (und damit den Merker)", function()
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "seasons") ~= nil).toBe(true)
        local profile = newProfile()
        Koloss.claim(profile, SEASON_ID, 0, { boostNow = REAL_NOW })
        local storm: any = deepCopy(profile)
        storm.runEarned = BigNum.serialize(BigNum.new(1e30))
        T.expect(Koloss.isClaimed(storm, SEASON_ID)).toBe(true)
    end)
end)

T.describe("DataCheck", function()
    local function broken(change: (data: any) -> ()): string
        local data = deepCopy(DataCheck.defaults())
        change(data)
        return table.concat(DataCheck.run(data), "\n")
    end

    T.it("die echten Tabellen bestehen", function()
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("meldet kaputte Fenster, Ziele, Stufen und Belohnungen", function()
        T.expect(broken(function(d)
            d.Koloss.window.phaseId = "gibtsnicht"
        end)).toContain("phaseId")
        T.expect(broken(function(d)
            d.Koloss.window.startDay = 6
            d.Koloss.window.days = 2
        end)).toContain("Woche")
        T.expect(broken(function(d)
            d.Koloss.window.days = 0
        end)).toContain("days")
        T.expect(broken(function(d)
            d.Koloss.targetSeconds = 0
        end)).toContain("targetSeconds")
        T.expect(broken(function(d)
            d.Koloss.tiers = {}
        end)).toContain("tiers")
        T.expect(broken(function(d)
            d.Koloss.tiers[1].minSeconds = 5
        end)).toContain("minSeconds")
        T.expect(broken(function(d)
            d.Koloss.tiers[2].minSeconds = d.Koloss.tiers[3].minSeconds
        end)).toContain("aufsteigend")
        T.expect(broken(function(d)
            d.Koloss.tiers[2].id = d.Koloss.tiers[1].id
        end)).toContain("doppelt")
        T.expect(broken(function(d)
            d.Koloss.tiers[2].rewards = { { kind = "crate", crateId = "gold" } }
        end)).toContain("unbekannte Art")
        T.expect(broken(function(d)
            d.Koloss.tiers[2].rewards = { { kind = "gems", amount = MAX_GEMS + 1 } }
        end)).toContain("amount")
        T.expect(broken(function(d)
            d.Koloss.tiers[2].rewards = { { kind = "luck", seconds = 99 * 3600 } }
        end)).toContain("seconds")
        T.expect(broken(function(d)
            d.Koloss.tiers[2].rewards = {}
        end)).toContain("rewards")
        T.expect(broken(function(d)
            d.Koloss.tiers[2].fairShare = 0
        end)).toContain("fairShare")
        T.expect(broken(function(d)
            d.Koloss.tiers[1].fairShare = 0.5
        end)).toContain("fairShare")
        T.expect(broken(function(d)
            d.Koloss.tiers[#d.Koloss.tiers].minSeconds = d.Koloss.targetSeconds + 1
        end)).toContain("unerreichbar")
        T.expect(broken(function(d)
            for _, phase in d.Seasons.phases do
                if phase.id == d.Koloss.window.phaseId then
                    phase.zoneOpen = false
                end
            end
        end)).toContain("zoneOpen")
        T.expect(broken(function(d)
            d.Seasons.list[1].zoneId = nil
        end)).toContain("zoneId")
    end)
end)

T.describe("Studio-Hilfen", function()
    T.it("DebugKoloss: progress:N, complete, reset; alles andere mit Hinweis", function()
        local action, number = Koloss.parseDebug("progress:5900")
        T.expect(action).toBe("progress")
        T.expect(number).toBe(5900)
        T.expect((Koloss.parseDebug("complete"))).toBe("complete")
        T.expect((Koloss.parseDebug("reset"))).toBe("reset")
        for _, bad in { "progress:", "progress:-1", "progress:1.5", "progress:1000001", "Complete", "", 5 :: any, nil :: any } do
            local a, n, problem = Koloss.parseDebug(bad)
            T.expect(a).toBeNil()
            T.expect(n).toBeNil()
            T.expect(type(problem)).toBe("string")
        end
    end)

    T.it("debugTime liegt eine Stunde nach dem Start des Fensters (laufende, nächste oder erste Saison)", function()
        T.expect(Koloss.debugTime(0)).toBe(WINDOW_START + 3600)
        T.expect(Koloss.debugTime(START + 100)).toBe(WINDOW_START + 3600)
        T.expect(Koloss.window(Koloss.debugTime(0) :: number).state).toBe("open")
    end)

    T.it("DebugSeason koloss wirkt nur über SeasonClock und nur in Studio", function()
        T.expect(CLOCK_SOURCE).toContain("koloss")
        T.expect(CLOCK_SOURCE).toContain("IS_STUDIO")
        T.expect(SERVICE_SOURCE).toContain("IsStudio()")
        T.expect(SERVICE_SOURCE).toContain("DebugKoloss")
    end)
end)

T.describe("Anbindung: keine Remote, nur Events.addZoneSeconds", function()
    T.it("es gibt keine Remote für das Event", function()
        for _, def in RemoteSpec.list do
            T.expect(string.find(string.lower(def.name), "koloss", 1, true)).toBeNil()
        end
    end)

    T.it("Fortschritt entsteht nur über Events.addZoneSeconds (vom Server gezählte Sammelzeit)", function()
        T.expect(EVENTS_SOURCE).toContain("Koloss.addZoneSeconds")
        -- Zwei Stellen buchen Fortschritt: addZoneSeconds (Spiel) und die Studio-Hilfe DebugKoloss.
        local studioStart = string.find(SERVICE_SOURCE, "local function connectStudioHelper", 1, true) :: number
        local count = 0
        for position in string.gmatch(SERVICE_SOURCE, "()KolossLogic%.addSeconds") do
            count += 1
            if count == 1 then
                T.expect(position < studioStart).toBe(true)
            else
                T.expect(position > studioStart).toBe(true) -- nur in der Studio-Hilfe
            end
        end
        T.expect(count).toBe(2)
    end)

    T.it("der Service steht nach Events in SERVICE_NAMES und schickt den Stand über den StateSync", function()
        local events = string.find(BOOTSTRAP_SOURCE, '"Events"', 1, true) :: number
        local koloss = string.find(BOOTSTRAP_SOURCE, '"Koloss"', 1, true) :: number
        T.expect(koloss > events).toBe(true)
        T.expect(SERVICE_SOURCE).toContain("Sand.addSnapshotProvider")
        T.expect(SERVICE_SOURCE).toContain("KolossProgress")
        T.expect(SERVICE_SOURCE).toContain("KolossState")
    end)

    T.it("die Belohnung geht nur an aktive Spieler mit geladenem Profil", function()
        T.expect(SERVICE_SOURCE).toContain("PlayerData.isActive")
    end)

    T.it("bei 100 % wird zuerst verteilt, dann veröffentlicht (ein Fehler beim Attribut kostet keine Belohnung)", function()
        local distribute = string.find(SERVICE_SOURCE, "        distribute()\n        pcall(publishAttributes)", 1, true)
        T.expect(distribute ~= nil).toBe(true)
    end)

    T.it("die Attribute zeigen nach dem Fenster oder in einer anderen Saison geschlossen und 0", function()
        T.expect(SERVICE_SOURCE).toContain("w.seasonId ~= event.seasonId")
        T.expect(SERVICE_SOURCE).toContain('return "closed", 0')
    end)
end)

T.finish()
