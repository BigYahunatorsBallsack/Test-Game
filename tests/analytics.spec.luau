--!strict
-- Lune-Tests für Analytics (Paket 6.3): Trichter, Käufe, Sitzungslänge, Rückkehr, Zusatzfelder, DataCheck und
-- Anbindung des Service.
-- Ausführen: lune run tests/analytics.spec

local T = require("./lib/expect")
local fs = require("@lune/fs")
local Analytics = require("../src/shared/Logic/Analytics")
local DataCheck = require("../src/shared/Logic/DataCheck")
local TutorialData = require("../src/shared/Data/Tutorial")
local AnalyticsData = require("../src/shared/Data/Analytics")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")

local SERVICE_SOURCE: string = fs.readFile("src/server/Services/Analytics.luau")
local BOOTSTRAP_SOURCE: string = fs.readFile("src/server/init.server.luau")

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

T.describe("Tutorial-Trichter", function()
    T.it("Schritt n mit Nummer und Name aus Data/Tutorial, danach done", function()
        local count = #TutorialData.steps
        for index = 1, count do
            local info = Analytics.tutorialStep(index) :: any
            T.expect(info.step).toBe(index)
            T.expect(info.name).toBe(TutorialData.steps[index].id)
        end
        local done = Analytics.tutorialStep(count + 1) :: any
        T.expect(done.step).toBe(count + 1)
        T.expect(done.name).toBe(AnalyticsData.onboardingDoneName)
    end)

    T.it("kaputte Schritte ergeben nichts", function()
        local count = #TutorialData.steps
        for _, bad in { 0, -1, 1.5, count + 2, 0 / 0, math.huge, "1" :: any, nil } do
            T.expect(Analytics.tutorialStep(bad)).toBeNil()
        end
        T.expect(Analytics.tutorialStep(1, { Tutorial = { steps = { { id = "" } } } })).toBeNil()
        T.expect(Analytics.tutorialStep(1, { Tutorial = { steps = { "x" } } })).toBeNil()
    end)
end)

T.describe("Käufe", function()
    local function entry(id: string): any
        return { purchaseId = id, productId = "gems_100", gems = 100, robux = 49, time = 1 }
    end

    T.it("jeder neue Eintrag genau einmal, nach purchaseId", function()
        local seen: { [string]: boolean } = {}
        local log = { entry("a"), entry("b") }
        T.expect(#Analytics.newPurchases(log, seen)).toBe(2)
        T.expect(#Analytics.newPurchases(log, seen)).toBe(0)
        table.insert(log, entry("c"))
        local fresh = Analytics.newPurchases(log, seen)
        T.expect(#fresh).toBe(1)
        T.expect(fresh[1].purchaseId).toBe("c")
        -- Die Liste wird gekürzt (älteste raus): nichts wird noch einmal gemeldet.
        table.remove(log, 1)
        T.expect(#Analytics.newPurchases(log, seen)).toBe(0)
    end)

    T.it("beim Laden vorhandene Einträge werden nur gemerkt", function()
        local seen: { [string]: boolean } = {}
        local log = { entry("a"), entry("b") }
        T.expect(#Analytics.newPurchases(log, seen, true)).toBe(0)
        T.expect(#Analytics.newPurchases(log, seen)).toBe(0)
    end)

    T.it("kaputte Einträge werden übersprungen", function()
        local seen: { [string]: boolean } = {}
        local log: { any } = {
            "x",
            { purchaseId = "", productId = "p", gems = 1 },
            { purchaseId = 5, productId = "p", gems = 1 },
            { purchaseId = "n1", productId = 7, gems = 1 },
            { purchaseId = "n2", productId = "p", gems = 0 / 0 },
            { purchaseId = "n3", productId = "p", gems = -4 },
            entry("ok"),
        }
        local fresh = Analytics.newPurchases(log, seen)
        T.expect(#fresh).toBe(1)
        T.expect(fresh[1].purchaseId).toBe("ok")
        T.expect(Analytics.newPurchases(nil, seen)).toEqual({})
    end)
end)

T.describe("Sitzungslänge und Rückkehr", function()
    T.it("Eimer an den Grenzen", function()
        T.expect(Analytics.sessionBucket(0)).toBe("lt_1m")
        T.expect(Analytics.sessionBucket(59.9)).toBe("lt_1m")
        T.expect(Analytics.sessionBucket(60)).toBe("1_5m")
        T.expect(Analytics.sessionBucket(900)).toBe("15_30m")
        T.expect(Analytics.sessionBucket(3599)).toBe("30_60m")
        T.expect(Analytics.sessionBucket(3600)).toBe("gt_60m")
        T.expect(Analytics.sessionBucket(1e9)).toBe("gt_60m")
    end)

    T.it("kaputte Längen ergeben nil", function()
        for _, bad in { -1, 0 / 0, math.huge, "5" :: any, nil } do
            T.expect(Analytics.sessionBucket(bad)).toBeNil()
        end
    end)

    T.it("neuer Spieler: Profil höchstens newPlayerSeconds alt", function()
        local info = Analytics.returnInfo(1000, 1000, 1000 + AnalyticsData.newPlayerSeconds) :: any
        T.expect(info.isNew).toBe(true)
        T.expect(info.days).toBe(0)
    end)

    T.it("Rückkehr: Tage seit dem letzten Besuch, gedeckelt, nie negativ", function()
        local created = 0
        local now = 100 * 86400
        local same = Analytics.returnInfo(now - 100, created, now) :: any
        T.expect(same.isNew).toBe(false)
        T.expect(same.days).toBe(0)
        T.expect((Analytics.returnInfo(now - 3 * 86400, created, now) :: any).days).toBe(3)
        T.expect((Analytics.returnInfo(now - 90 * 86400, created, now) :: any).days).toBe(AnalyticsData.maxReturnDays)
        T.expect((Analytics.returnInfo(now + 5000, created, now) :: any).days).toBe(0) -- Zukunft: 0
    end)

    T.it("kaputte Zeiten ergeben nil", function()
        T.expect(Analytics.returnInfo(0 / 0, 0, 5)).toBeNil()
        T.expect(Analytics.returnInfo(0, "x" :: any, 5)).toBeNil()
        T.expect(Analytics.returnInfo(0, 0, nil)).toBeNil()
    end)
end)

T.describe("Zusatzfelder", function()
    T.it("nur Text bis maxFieldLength und endliche Zahlen, nur Textschlüssel", function()
        local clean = Analytics.cleanFields({
            a = string.rep("x", 500),
            b = 5,
            c = 0 / 0,
            d = math.huge,
            e = { 1 },
            f = true,
            [1] = "zahlenschluessel",
            [""] = "leer",
        })
        T.expect(#clean.a).toBe(AnalyticsData.maxFieldLength)
        T.expect(clean.b).toBe(5)
        T.expect(clean.c).toBeNil()
        T.expect(clean.d).toBeNil()
        T.expect(clean.e).toBeNil()
        T.expect(clean.f).toBeNil()
        T.expect(clean[1]).toBeNil()
        T.expect(clean[""]).toBeNil()
        T.expect(Analytics.cleanFields(nil)).toEqual({})
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

    T.it("meldet kaputte Namen, Zahlen und Eimer", function()
        T.expect(broken(function(d)
            d.Analytics.events.sessionEnd = ""
        end)).toContain("sessionEnd")
        T.expect(broken(function(d)
            d.Analytics.events.sessionEnd = d.Analytics.events.sessionStart
        end)).toContain("doppelt")
        T.expect(broken(function(d)
            d.Analytics.tickSeconds = 0
        end)).toContain("tickSeconds")
        T.expect(broken(function(d)
            d.Analytics.logInStudio = "nein"
        end)).toContain("logInStudio")
        T.expect(broken(function(d)
            d.Analytics.sessionBuckets[2].maxSeconds = 10
        end)).toContain("aufsteigend")
        T.expect(broken(function(d)
            d.Analytics.sessionBuckets[#d.Analytics.sessionBuckets].maxSeconds = 99999
        end)).toContain("offen")
        T.expect(broken(function(d)
            d.Analytics.sessionBuckets = {}
        end)).toContain("sessionBuckets")
    end)
end)

T.describe("Anbindung", function()
    T.it("der Service steht am Ende von SERVICE_NAMES und hat keine Remote", function()
        T.expect(string.find(BOOTSTRAP_SOURCE, '"Leaderboard", "Analytics" }', 1, true) ~= nil).toBe(true)
        for _, def in RemoteSpec.list do
            T.expect(string.find(string.lower(def.name), "analytics", 1, true)).toBeNil()
        end
    end)

    T.it("jeder Aufruf von AnalyticsService läuft in pcall (send) und Studio sendet nichts", function()
        local calls = 0
        for position in string.gmatch(SERVICE_SOURCE, "()AnalyticsService:Log") do
            calls += 1
            local head = string.sub(SERVICE_SOURCE, 1, position)
            local lastSend = 0
            for at in string.gmatch(head, "()send%(") do
                lastSend = at
            end
            local lastFunction = 0
            for at in string.gmatch(head, "()\nlocal function ") do
                lastFunction = at
            end
            T.expect(lastSend > lastFunction).toBe(true)
        end
        T.expect(calls).toBe(4) -- Trichter, Kauf, session_start, session_end
        T.expect(string.find(SERVICE_SOURCE, "local ok, err = pcall(call)", 1, true) ~= nil).toBe(true)
        T.expect(string.find(SERVICE_SOURCE, "IS_STUDIO and not AnalyticsData.logInStudio", 1, true) ~= nil).toBe(true)
    end)

    T.it("es werden keine Spielernamen gesendet", function()
        for line in string.gmatch(SERVICE_SOURCE, "[^\n]+") do
            if string.find(line, "AnalyticsService:Log", 1, true) or string.find(line, "LogCustomEvent", 1, true) then
                T.expect(string.find(line, "player.Name", 1, true)).toBeNil()
                T.expect(string.find(line, "DisplayName", 1, true)).toBeNil()
            end
        end
    end)
end)

T.finish()
