--!strict
-- Paket 5.2: Codes-System (Logic/Codes, Server-Tabelle src/server/Data/Codes, Services/Codes).
-- Einmal je Spieler und Code, normalize, Belohnungen (Gems mit maxGems, Münz- und Glücks-Boost),
-- gleiche Antwort für unbekannt, abgelaufen, noch nicht begonnen und ungültig, kein halbes Buchen,
-- Sperre nach 5 falschen Versuchen, Codes nur auf dem Server und nie Kisten oder Items, Prüfung der
-- Tabelle (check), Remote RedeemCode, Profil und Sandsturm, Studio-Hilfe.
--
-- Die Logik-Tests nutzen eine eigene Test-Tabelle (FIXTURE). Die echte Server-Tabelle wird nur
-- allgemein geprüft (jede Zeile gültig, einmal einlösbar, nur erlaubte Belohnungen), damit die Tests
-- nicht brechen, wenn die Beispiel-Codes vor dem Start ersetzt werden.

local T = require("./lib/expect")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Codes = require("../src/shared/Logic/Codes")
local Profile = require("../src/shared/Logic/Profile")
local Migrations = require("../src/shared/Logic/Migrations")
local Perks = require("../src/shared/Logic/Perks")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local BigNum = require("../src/shared/Logic/BigNum")
local Validate = require("../src/shared/Logic/Validate")
local RateLimiter = require("../src/shared/Logic/RateLimiter")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local Economy = require("../src/shared/Data/Economy")
local ServerCodes = require("../src/server/Data/Codes")

local NOW = 1_700_000_000
local MAX_GEMS = Economy.purchases.maxGems
local LIMITS = { maxFailures = 5, lockSeconds = 60 }

-- Quelltexte für die Textsuche, hier oben gelesen (Dateizugriff wartet; in einem Test würde das den
-- Abschluss der Testdatei stören).
local function sourcesIn(dir: string, result: { [string]: string })
    for _, name in fs.readDir(dir) do
        local path = `{dir}/{name}`
        if fs.isDir(path) then
            sourcesIn(path, result)
        elseif fs.isFile(path) then
            result[path] = fs.readFile(path)
        end
    end
end
local CLIENT_VISIBLE_SOURCES: { [string]: string } = {}
sourcesIn("src/shared", CLIENT_VISIBLE_SOURCES)
sourcesIn("src/client", CLIENT_VISIBLE_SOURCES)
local LOGIC_SOURCE = fs.readFile("src/shared/Logic/Codes.luau")
local SERVICE_SOURCE = fs.readFile("src/server/Services/Codes.luau")
local BOOTSTRAP_SOURCE = fs.readFile("src/server/init.server.luau")

local function deepCopy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in value do
        copy[key] = deepCopy(inner)
    end
    return copy
end

-- Test-Tabelle (nicht die Server-Tabelle).
local FIXTURE = {
    list = {
        { id = "gems_test", code = "TEST-GEMS", reward = { kind = "gems", amount = 50 } },
        { id = "boost_test", code = "BOOST1", reward = { kind = "coinBoost", seconds = 1200 } },
        { id = "luck_test", code = "LUCKY7", reward = { kind = "luck", seconds = 900 } },
        { id = "window_test", code = "SOMMER", reward = { kind = "gems", amount = 5 }, startsAt = NOW - 100, endsAt = NOW + 100 },
        { id = "future_test", code = "BALD", reward = { kind = "gems", amount = 5 }, startsAt = NOW + 1 },
        { id = "old_test", code = "ALT", reward = { kind = "gems", amount = 5 }, endsAt = NOW - 1 },
    },
}

local function fixture(): any
    return deepCopy(FIXTURE)
end

local function player(): any
    return Profile.default(NOW)
end

-- Felder, die eine Einlösung ändern darf.
local ALLOWED_WRITES = { codes = true, gems = true, boosts = true }

-- Felder, die sich zwischen zwei Profilen unterscheiden (oberste Ebene).
local function changedFields(before: any, after: any): { string }
    local fields: { string } = {}
    local seen: { [string]: boolean } = {}
    for _, source in { before, after } do
        for key in source do
            if not seen[key] then
                seen[key] = true
                if serde.encode("json", { before[key] }) ~= serde.encode("json", { after[key] }) then
                    table.insert(fields, key)
                end
            end
        end
    end
    table.sort(fields)
    return fields
end

-- Wie der DataStore: sanitize, JSON hin und zurück, dann Laden wie PlayerSession.
local function saveAndLoad(profile: any): any
    T.expect(Profile.sanitize(profile, NOW)).toEqual({})
    local stored = serde.decode("json", serde.encode("json", profile))
    local loaded = Profile.migrate(stored, nil, NOW)
    T.expect(Profile.sanitize(loaded, NOW, { trimLists = false })).toEqual({})
    return loaded
end

-- Zeit, zu der eine Zeile der echten Tabelle gilt.
local function activeTimeOf(row: any): number
    if row.startsAt ~= nil then
        return row.startsAt
    elseif row.endsAt ~= nil then
        return row.endsAt
    end
    return NOW
end

-- Einlösung über attempt mit gemeinsamem Zustand (wie der Service je Spieler).
local function makeSession(profile: any, codeTable: any): any
    local session = { state = nil :: any, calls = 0 }
    function session.try(text: any, now: number): any
        local response, state = Codes.attempt(session.state, now, LIMITS, function(): any
            session.calls += 1
            return Codes.redeem(profile, codeTable, NOW, text)
        end)
        session.state = state
        return response
    end
    return session
end

T.describe("normalize", function()
    T.it("Leerraum am Rand weg, Großbuchstaben, Ziffern und Bindestrich bleiben", function()
        T.expect(Codes.normalize("test-gems")).toBe("TEST-GEMS")
        T.expect(Codes.normalize("  Test-Gems  ")).toBe("TEST-GEMS")
        T.expect(Codes.normalize("\tlucky7\n")).toBe("LUCKY7")
        T.expect(Codes.normalize("\r\n  1000x \t")).toBe("1000X")
        T.expect(Codes.normalize("A")).toBe("A")
        T.expect(Codes.normalize("-")).toBe("-")
        T.expect(Codes.normalize("0123456789")).toBe("0123456789")
        -- Ein normalisierter Text bleibt beim zweiten Mal gleich.
        T.expect(Codes.normalize(Codes.normalize(" ab-12 "))).toBe("AB-12")
    end)

    T.it("Länge 1 bis 24 nach dem Kürzen; Leerraum zählt am Rand nicht mit", function()
        T.expect(Codes.normalize(string.rep("a", 24))).toBe(string.rep("A", 24))
        T.expect(Codes.normalize(string.rep("a", 25))).toBeNil()
        T.expect(Codes.normalize("   " .. string.rep("b", 24) .. "   ")).toBe(string.rep("B", 24))
        T.expect(Codes.MIN_LENGTH).toBe(1)
        T.expect(Codes.MAX_LENGTH).toBe(24)
    end)

    T.it("leer, nur Leerraum, falsche Zeichen und Leerraum innen ergeben nil", function()
        for _, bad in { "", " ", "\t\n", "TEST GEMS", "TEST_GEMS", "CODE!", "ÄRGER", "über", "CODE.", "CO\0DE", "a+b", "\u{1F381}" } do
            if Codes.normalize(bad) ~= nil then
                error(`normalize({string.format("%q", bad)}) sollte nil sein`)
            end
        end
    end)

    T.it("kein Text ergibt nil", function()
        for _, bad: any in { nil, 5, 0 / 0, true, {}, { "CODE" }, function() end } do
            T.expect(Codes.normalize(bad)).toBeNil()
        end
    end)

    T.it("sehr lange Eingaben werden schnell abgelehnt", function()
        T.expect(Codes.normalize(string.rep(" ", 100_000) .. "A" .. string.rep(" ", 100_000))).toBe("A")
        T.expect(Codes.normalize("A" .. string.rep(" ", 100_000) .. "B")).toBeNil()
    end)
end)

T.describe("Einmal je Spieler und Code", function()
    T.it("der erste Versuch bucht, der zweite gibt alreadyRedeemed und bucht nichts", function()
        local profile = player()
        profile.gems = 7
        local first = Codes.redeem(profile, fixture(), NOW, "test-gems")
        T.expect(first).toEqual({ ok = true, codeId = "gems_test", reward = { kind = "gems", amount = 50 } })
        T.expect(profile.gems).toBe(57)
        T.expect(profile.codes).toEqual({ gems_test = true })
        local before = deepCopy(profile)
        for _, again in { "TEST-GEMS", "  test-gems ", "Test-Gems" } do
            T.expect(Codes.redeem(profile, fixture(), NOW, again)).toEqual({ ok = false, reason = "alreadyRedeemed" })
            T.expect(profile).toEqual(before)
        end
        T.expect(Codes.isRedeemed(profile, "gems_test")).toBe(true)
        T.expect(Codes.isRedeemed(profile, "boost_test")).toBe(false)
    end)

    T.it("jeder Spieler hat seinen eigenen Merker; andere Codes bleiben einlösbar", function()
        local a, b = player(), player()
        T.expect(Codes.redeem(a, fixture(), NOW, "TEST-GEMS").ok).toBe(true)
        T.expect(Codes.redeem(b, fixture(), NOW, "TEST-GEMS").ok).toBe(true)
        T.expect(Codes.redeem(a, fixture(), NOW, "BOOST1").ok).toBe(true)
        T.expect(a.codes).toEqual({ gems_test = true, boost_test = true })
        T.expect(b.codes).toEqual({ gems_test = true })
    end)

    T.it("der Merker hängt an der Code-ID: neuer Text mit derselben ID ist schon eingelöst", function()
        local profile = player()
        T.expect(Codes.redeem(profile, fixture(), NOW, "TEST-GEMS").ok).toBe(true)
        local renamed = fixture()
        renamed.list[1].code = "NEU-GEMS"
        T.expect(Codes.redeem(profile, renamed, NOW, "neu-gems").reason).toBe("alreadyRedeemed")
    end)

    T.it("jeder Wert außer nil und false im Merker zählt als eingelöst (lieber ablehnen als doppelt)", function()
        for _, marker: any in { true, 1, "ja", {} } do
            local profile = player()
            profile.codes = { gems_test = marker }
            T.expect(Codes.redeem(profile, fixture(), NOW, "TEST-GEMS").reason).toBe("alreadyRedeemed")
        end
        local profile = player()
        profile.codes = { gems_test = false }
        T.expect(Codes.redeem(profile, fixture(), NOW, "TEST-GEMS").ok).toBe(true)
        T.expect(profile.codes).toEqual({ gems_test = true })
    end)

    T.it("Merker und Belohnung überstehen Speichern und Laden; danach keine zweite Einlösung", function()
        local profile = player()
        T.expect(Codes.redeem(profile, fixture(), NOW, "TEST-GEMS").ok).toBe(true)
        T.expect(Codes.redeem(profile, fixture(), NOW, "LUCKY7").ok).toBe(true)
        local loaded = saveAndLoad(profile)
        T.expect(loaded.codes).toEqual({ gems_test = true, luck_test = true })
        T.expect(loaded.gems).toBe(50)
        T.expect(loaded.boosts.luckUntil).toBe(NOW + 900)
        T.expect(Codes.redeem(loaded, fixture(), NOW, "test-gems").reason).toBe("alreadyRedeemed")
        T.expect(Codes.redeem(loaded, fixture(), NOW, "lucky7").reason).toBe("alreadyRedeemed")
    end)

    T.it("ohne Feld codes (alter Stand vor dem Laden) zählt nichts als eingelöst, danach steht der Merker", function()
        local profile = player()
        profile.codes = nil
        T.expect(Codes.redeem(profile, fixture(), NOW, "BOOST1").ok).toBe(true)
        T.expect(profile.codes).toEqual({ boost_test = true })
    end)
end)

T.describe("Belohnungen", function()
    T.it("Gems über Gems.grant; bei maxGems gekappt, die Einlösung gilt trotzdem", function()
        local profile = player()
        profile.gems = MAX_GEMS - 10
        local result = Codes.redeem(profile, fixture(), NOW, "TEST-GEMS")
        T.expect(result.reward).toEqual({ kind = "gems", amount = 10, capped = true })
        T.expect(profile.gems).toBe(MAX_GEMS)
        T.expect(profile.codes.gems_test).toBe(true)
        -- Schon voll: 0 gutgeschrieben, trotzdem eingelöst (kein zweiter Versuch später).
        local full = player()
        full.gems = MAX_GEMS
        local fullResult = Codes.redeem(full, fixture(), NOW, "TEST-GEMS")
        T.expect(fullResult.reward).toEqual({ kind = "gems", amount = 0, capped = true })
        T.expect(full.gems).toBe(MAX_GEMS)
        T.expect(Codes.redeem(full, fixture(), NOW, "TEST-GEMS").reason).toBe("alreadyRedeemed")
    end)

    T.it("Gems mit anderer Obergrenze aus den Daten (ctx.data)", function()
        local economy = deepCopy(Economy)
        economy.purchases.maxGems = 30
        local profile = player()
        profile.gems = 25
        local result = Codes.redeem(profile, fixture(), NOW, "TEST-GEMS", { data = { Economy = economy } })
        T.expect(result.reward).toEqual({ kind = "gems", amount = 5, capped = true })
        T.expect(profile.gems).toBe(30)
    end)

    T.it("Münz-Boost: ab jetzt, oder ab der alten Endzeit eines laufenden Boosts; der Glücks-Boost bleibt", function()
        local fresh = player()
        local result = Codes.redeem(fresh, fixture(), NOW, "BOOST1")
        T.expect(result.reward).toEqual({ kind = "coinBoost", seconds = 1200 })
        T.expect(fresh.boosts).toEqual({ coinsUntil = NOW + 1200, luckUntil = 0 })
        T.expect(Perks.coinBoostActive(fresh, NOW + 1199)).toBe(true)
        T.expect(Perks.coinBoostActive(fresh, NOW + 1200)).toBe(false)

        local running = player()
        running.boosts = { coinsUntil = NOW + 500, luckUntil = NOW + 77 }
        Codes.redeem(running, fixture(), NOW, "BOOST1")
        T.expect(running.boosts).toEqual({ coinsUntil = NOW + 1700, luckUntil = NOW + 77 })

        local expired = player()
        expired.boosts = { coinsUntil = NOW - 500, luckUntil = 0 }
        Codes.redeem(expired, fixture(), NOW, "BOOST1")
        T.expect(expired.boosts.coinsUntil).toBe(NOW + 1200)
    end)

    T.it("Glücks-Boost: verlängert luckUntil ab der alten Endzeit; der Münz-Boost bleibt", function()
        local profile = player()
        profile.boosts = { coinsUntil = NOW + 300, luckUntil = NOW + 100 }
        local result = Codes.redeem(profile, fixture(), NOW, "lucky7")
        T.expect(result.reward).toEqual({ kind = "luck", seconds = 900 })
        T.expect(profile.boosts).toEqual({ coinsUntil = NOW + 300, luckUntil = NOW + 1000 })
        T.expect(Perks.luckBoostActive(profile, NOW + 999)).toBe(true)
    end)

    T.it("eine Einlösung ändert nur codes und gems bzw. boosts, nie Inventar, Pity, Käufe oder Münzen", function()
        for _, text in { "TEST-GEMS", "BOOST1", "LUCKY7" } do
            local profile = player()
            profile.inventory.skins.skin_common_1 = 2
            profile.coins = BigNum.serialize(BigNum.new(1, 6))
            local before = deepCopy(profile)
            T.expect(Codes.redeem(profile, fixture(), NOW, text).ok).toBe(true)
            for _, field in changedFields(before, profile) do
                if not ALLOWED_WRITES[field] then
                    error(`{text}: Feld {field} wurde geändert`)
                end
            end
        end
    end)
end)

T.describe("Unbekannt, abgelaufen, noch nicht begonnen und ungültig: dieselbe Antwort", function()
    T.it("alle geben genau { ok = false, reason = \"invalid\" } und buchen nichts", function()
        local texts: { any } = {
            "GIBT-ES-NICHT", -- unbekannt
            "ALT", -- abgelaufen
            "BALD", -- noch nicht begonnen
            "TEST GEMS", -- Leerzeichen innen
            "", -- leer
            string.rep("A", 25), -- zu lang
            "TEST_GEMS", -- falsches Zeichen
            42, -- kein Text
        }
        for _, text in texts do
            local profile = player()
            local before = deepCopy(profile)
            local result = Codes.redeem(profile, fixture(), NOW, text)
            T.expect(result).toEqual({ ok = false, reason = "invalid" })
            T.expect(profile).toEqual(before)
        end
    end)

    T.it("Grenzen des Zeitfensters: startsAt und endsAt zählen noch, eine Sekunde davor bzw. danach nicht", function()
        local window = FIXTURE.list[4]
        local cases = {
            { time = window.startsAt - 1, ok = false },
            { time = window.startsAt, ok = true },
            { time = window.endsAt, ok = true },
            { time = window.endsAt + 1, ok = false },
        }
        for _, case in cases do
            local profile = player()
            local result = Codes.redeem(profile, fixture(), case.time, "sommer")
            T.expect(result.ok == true).toBe(case.ok)
            if not case.ok then
                T.expect(result).toEqual({ ok = false, reason = "invalid" })
            end
        end
    end)

    T.it("kaputte Zeiten in der Tabelle zählen wie abgelaufen (fail-closed)", function()
        for _, bad: any in { 0 / 0, math.huge * 0, "morgen", {} } do
            local codes = fixture()
            codes.list[1].endsAt = bad
            local profile = player()
            T.expect(Codes.redeem(profile, codes, NOW, "TEST-GEMS")).toEqual({ ok = false, reason = "invalid" })
        end
    end)

    T.it("ein schon eingelöster Code nennt alreadyRedeemed (der Spieler kennt ihn ja)", function()
        local profile = player()
        Codes.redeem(profile, fixture(), NOW, "SOMMER")
        T.expect(Codes.redeem(profile, fixture(), NOW + 1000, "SOMMER").reason).toBe("alreadyRedeemed")
    end)
end)

T.describe("Fehler im Block: nichts gebucht, codes unverändert", function()
    T.it("kaputte Belohnung (Menge, Dauer, Art, Kiste, Item, fehlt): error, Profil unverändert", function()
        local changes: { (row: any) -> () } = {
            function(row: any) row.reward.amount = -1 end,
            function(row: any) row.reward.amount = 2.5 end,
            function(row: any) row.reward.amount = Codes.MAX_GEMS + 1 end,
            function(row: any) row.reward.amount = 0 / 0 end,
            function(row: any) row.reward = { kind = "coinBoost", seconds = 0 } end,
            function(row: any) row.reward = { kind = "luck", seconds = math.huge } end,
            function(row: any) row.reward = { kind = "coinBoost", seconds = Codes.MAX_SECONDS + 1 } end,
            function(row: any) row.reward = { kind = "crate", crateId = "gold" } end,
            function(row: any) row.reward = { kind = "crate", crateId = "gold", seconds = 60, amount = 5 } end,
            function(row: any) row.reward = { kind = "item", itemId = "skin_rare_1" } end,
            function(row: any) row.reward = { kind = "item", itemId = "skin_rare_1", seconds = 60, amount = 5 } end,
            function(row: any) row.reward = { kind = "robux", amount = 100 } end,
            function(row: any) row.reward = { amount = 50 } end,
            function(row: any) row.reward = nil end,
            function(row: any) row.reward = "50 Gems" end,
            function(row: any) row.id = nil end,
            function(row: any) row.id = "" end,
        }
        for index, change in changes do
            local codes = fixture()
            change(codes.list[1])
            local profile = player()
            profile.gems = 3
            profile.codes = { boost_test = true }
            profile.boosts = { coinsUntil = NOW + 5, luckUntil = NOW + 6 }
            local before = deepCopy(profile)
            local result = Codes.redeem(profile, codes, NOW, "TEST-GEMS")
            if result.reason ~= "error" then
                error(`Fall {index}: erwartet error, erhalten {tostring(result.reason)}`)
            end
            T.expect(type(result.detail)).toBe("string")
            T.expect(profile).toEqual(before)
        end
    end)

    T.it("kaputter Merker profile.codes (kein Tabelle): error statt Raten, nichts gebucht", function()
        for _, bad: any in { "kaputt", 5, true } do
            local profile = player()
            profile.codes = bad
            local before = deepCopy(profile)
            T.expect(Codes.redeem(profile, fixture(), NOW, "TEST-GEMS").reason).toBe("error")
            T.expect(profile).toEqual(before)
        end
    end)

    T.it("kaputte Uhr: error, nichts gebucht; kein Profil: noProfile", function()
        for _, bad: any in { 0 / 0, math.huge, -math.huge, -1, "jetzt" } do
            local profile = player()
            local before = deepCopy(profile)
            T.expect(Codes.redeem(profile, fixture(), bad, "TEST-GEMS").reason).toBe("error")
            T.expect(profile).toEqual(before)
        end
        T.expect(Codes.redeem(nil, fixture(), NOW, "TEST-GEMS")).toEqual({ ok = false, reason = "noProfile" })
        T.expect(Codes.redeem("kaputt", fixture(), NOW, "TEST-GEMS").reason).toBe("noProfile")
    end)

    T.it("kaputte Tabelle: error, nichts gebucht", function()
        for _, bad: any in { nil, {}, { list = "x" }, "Codes" } do
            local profile = player()
            local before = deepCopy(profile)
            T.expect(Codes.redeem(profile, bad, NOW, "TEST-GEMS").reason).toBe("error")
            T.expect(profile).toEqual(before)
        end
    end)

    T.it("Warten im Block (yield beim Lesen der Tabelle): error, nichts gebucht", function()
        -- Eine Liste, deren Iterator wartet (__iter), unterbricht die Einlösung mitten im Block.
        local waiting = {
            list = setmetatable({}, {
                __iter = function(_self: any): any
                    return function(): any
                        coroutine.yield()
                        return nil
                    end
                end,
            }),
        }
        local profile = player()
        local before = deepCopy(profile)
        local result = Codes.redeem(profile, waiting, NOW, "TEST-GEMS")
        T.expect(result.reason).toBe("error")
        T.expect(result.detail).toContain("gewartet")
        T.expect(profile).toEqual(before)
        -- Eine Metamethode, die warten will, wirft in Luau: ebenfalls error, nichts gebucht.
        local codes = fixture()
        codes.list[1].reward = setmetatable({}, {
            __index = function(_self: any, _key: any): any
                coroutine.yield()
                return nil
            end,
        })
        local other = player()
        local otherBefore = deepCopy(other)
        T.expect(Codes.redeem(other, codes, NOW, "TEST-GEMS").reason).toBe("error")
        T.expect(other).toEqual(otherBefore)
    end)

    T.it("jede Ablehnung lässt das Profil unverändert (invalid, alreadyRedeemed)", function()
        local profile = player()
        profile.codes = { gems_test = true }
        local before = deepCopy(profile)
        T.expect(Codes.redeem(profile, fixture(), NOW, "TEST-GEMS")).toEqual({ ok = false, reason = "alreadyRedeemed" })
        T.expect(Codes.redeem(profile, fixture(), NOW, "NIX")).toEqual({ ok = false, reason = "invalid" })
        T.expect(profile).toEqual(before)
    end)
end)

T.describe("Falsche Versuche und Sperre (attempt)", function()
    T.it("5 falsche Versuche sperren 60 Sekunden; schon der fünfte antwortet locked", function()
        local profile = player()
        local session = makeSession(profile, fixture())
        for index = 1, 4 do
            T.expect(session.try(`FALSCH{index}`, 100)).toEqual({ ok = false, reason = "invalid" })
        end
        T.expect(session.state).toEqual({ failures = 4, lockedUntil = 0 })
        T.expect(session.try("FALSCH5", 100)).toEqual({ ok = false, reason = "locked", secondsLeft = 60 })
        T.expect(session.state).toEqual({ failures = 0, lockedUntil = 160 })
        T.expect(Codes.lockSecondsLeft(session.state, 100)).toBe(60)
    end)

    T.it("in der Sperre wird auch ein richtiger Code abgelehnt, ohne die Einlösung zu rufen", function()
        local profile = player()
        local session = makeSession(profile, fixture())
        for index = 1, 5 do
            session.try(`FALSCH{index}`, 100)
        end
        local calls = session.calls
        local before = deepCopy(profile)
        T.expect(session.try("TEST-GEMS", 100.5)).toEqual({ ok = false, reason = "locked", secondsLeft = 60 })
        T.expect(session.try("TEST-GEMS", 130)).toEqual({ ok = false, reason = "locked", secondsLeft = 30 })
        T.expect(session.try("TEST-GEMS", 159.2)).toEqual({ ok = false, reason = "locked", secondsLeft = 1 })
        T.expect(session.calls).toBe(calls)
        T.expect(profile).toEqual(before)
        -- Versuche in der Sperre verlängern sie nicht.
        T.expect(session.state.lockedUntil).toBe(160)
    end)

    T.it("nach Ablauf der Sperre geht ein richtiger Code wieder, der Zähler beginnt neu", function()
        local profile = player()
        local session = makeSession(profile, fixture())
        for index = 1, 5 do
            session.try(`FALSCH{index}`, 100)
        end
        T.expect(Codes.lockSecondsLeft(session.state, 160)).toBe(0)
        local result = session.try("TEST-GEMS", 160)
        T.expect(result.ok).toBe(true)
        T.expect(Codes.isIdle(session.state)).toBe(true)
        -- Neu gezählt: wieder vier falsche ohne Sperre.
        local fresh = makeSession(player(), fixture())
        for index = 1, 5 do
            fresh.try(`FALSCH{index}`, 0)
        end
        for index = 1, 4 do
            T.expect(fresh.try(`NOCHMAL{index}`, 61 + index).reason).toBe("invalid")
        end
        T.expect(fresh.try("NOCHMAL5", 70).reason).toBe("locked")
    end)

    T.it("ein Erfolg setzt den Zähler zurück", function()
        local session = makeSession(player(), fixture())
        for index = 1, 4 do
            session.try(`FALSCH{index}`, 10)
        end
        T.expect(session.try("BOOST1", 11).ok).toBe(true)
        T.expect(session.state).toEqual({ failures = 0, lockedUntil = 0 })
        for index = 1, 4 do
            T.expect(session.try(`WIEDER{index}`, 12).reason).toBe("invalid")
        end
        T.expect(session.state.failures).toBe(4)
    end)

    T.it("nur invalid zählt: alreadyRedeemed, busy, noProfile und error nicht", function()
        local profile = player()
        profile.codes = { gems_test = true }
        local session = makeSession(profile, fixture())
        for _ = 1, 10 do
            T.expect(session.try("TEST-GEMS", 5).reason).toBe("alreadyRedeemed")
        end
        T.expect(Codes.isIdle(session.state)).toBe(true)
        for _, reason in { "busy", "noProfile", "error" } do
            local state: any = nil
            for _ = 1, 10 do
                local response, nextState = Codes.attempt(state, 5, LIMITS, function(): any
                    return { ok = false, reason = reason, detail = "nur fürs Protokoll" }
                end)
                T.expect(response).toEqual({ ok = false, reason = reason }) -- nie `detail`
                state = nextState
            end
            T.expect(Codes.isIdle(state)).toBe(true)
        end
    end)

    T.it("je Spieler getrennt; attempt ändert den alten Zustand nicht", function()
        local a = makeSession(player(), fixture())
        local b = makeSession(player(), fixture())
        for index = 1, 5 do
            a.try(`FALSCH{index}`, 0)
        end
        T.expect(a.try("TEST-GEMS", 1).reason).toBe("locked")
        T.expect(b.try("TEST-GEMS", 1).ok).toBe(true)
        local old = { failures = 2, lockedUntil = 0 }
        local _, newState = Codes.attempt(old, 0, LIMITS, function(): any
            return { ok = false, reason = "invalid" }
        end)
        T.expect(old).toEqual({ failures = 2, lockedUntil = 0 })
        T.expect(newState).toEqual({ failures = 3, lockedUntil = 0 })
    end)

    T.it("Einlösung wirft oder antwortet Unsinn: error, nichts gezählt; kaputte Uhr: error, keine Einlösung", function()
        local state = { failures = 3, lockedUntil = 0 }
        local response, nextState = Codes.attempt(state, 0, LIMITS, function(): any
            error("kaputt")
        end)
        T.expect(response).toEqual({ ok = false, reason = "error" })
        T.expect(nextState).toEqual(state)
        local nilResponse = Codes.attempt(state, 0, LIMITS, function(): any
            return nil
        end)
        T.expect(nilResponse).toEqual({ ok = false, reason = "error" })
        for _, badNow in { 0 / 0, math.huge, -math.huge } do
            local called = false
            local badResponse = Codes.attempt(nil, badNow, LIMITS, function(): any
                called = true
                return { ok = true }
            end)
            T.expect(badResponse.reason).toBe("error")
            T.expect(called).toBe(false)
        end
    end)

    T.it("kaputter gespeicherter Zustand zählt wie neu; kaputte Grenzen sind ein Fehler", function()
        for _, bad: any in { nil, "x", { failures = 0 / 0, lockedUntil = -5 }, { failures = "3" } } do
            local response, state = Codes.attempt(bad, 10, LIMITS, function(): any
                return { ok = false, reason = "invalid" }
            end)
            T.expect(response.reason).toBe("invalid")
            T.expect(state).toEqual({ failures = 1, lockedUntil = 0 })
        end
        for _, badLimits: any in { nil, {}, { maxFailures = 0, lockSeconds = 60 }, { maxFailures = 5, lockSeconds = 0 }, { maxFailures = 2.5, lockSeconds = 60 } } do
            T.expect(function()
                Codes.attempt(nil, 0, badLimits, function(): any
                    return { ok = true }
                end)
            end).toThrow("Grenzen")
        end
    end)

    T.it("der Service nutzt 5 Versuche und 60 Sekunden (Konstanten oben im Service) und die Uhr os.clock", function()
        T.expect(string.match(SERVICE_SOURCE, "\nlocal MAX_FAILURES = (%d+)\n")).toBe("5")
        T.expect(string.match(SERVICE_SOURCE, "\nlocal LOCK_SECONDS = (%d+)\n")).toBe("60")
        T.expect(string.find(SERVICE_SOURCE, "maxFailures = MAX_FAILURES, lockSeconds = LOCK_SECONDS", 1, true) ~= nil).toBe(true)
        T.expect(string.find(SERVICE_SOURCE, "return os.clock()", 1, true) ~= nil).toBe(true)
        T.expect(string.find(SERVICE_SOURCE, "return os.time()", 1, true) ~= nil).toBe(true)
    end)
end)

T.describe("Codes nur auf dem Server, nie Kisten oder Items", function()
    T.it("kein Code-Text der Server-Tabelle steht in src/shared oder src/client", function()
        local files = 0
        for _ in CLIENT_VISIBLE_SOURCES do
            files += 1
        end
        T.expect(files > 50).toBe(true) -- die Suche hat wirklich Dateien gelesen
        T.expect(#ServerCodes.list > 0).toBe(true)
        for _, row in ServerCodes.list do
            for path, source in CLIENT_VISIBLE_SOURCES do
                if string.find(string.upper(source), row.code, 1, true) ~= nil then
                    error(`der Code mit der ID "{row.id}" steht in {path}`)
                end
            end
        end
    end)

    T.it("Shared und Client laden die Server-Tabelle nie; der Service lädt sie aus src/server/Data", function()
        -- Code ohne Kommentare: kein Pfad zur Server-Tabelle, kein Zugriff auf ServerScriptService.
        for path, source in CLIENT_VISIBLE_SOURCES do
            for line in string.gmatch(source, "[^\n]+") do
                local code = string.match(line, "^(.-)%-%-") or line
                if string.find(code, "server/Data", 1, true) or string.find(code, "ServerScriptService", 1, true) then
                    error(`{path} greift auf den Server zu: {line}`)
                end
            end
        end
        T.expect(string.find(SERVICE_SOURCE, 'servicesFolder.Parent:WaitForChild("Data"):WaitForChild("Codes")', 1, true) ~= nil).toBe(true)
        T.expect(string.find(BOOTSTRAP_SOURCE, '"Daily", "Codes"', 1, true) ~= nil).toBe(true)
    end)

    T.it("jede Belohnung der Server-Tabelle ist Gems, Münz- oder Glücks-Boost, ohne Kisten- oder Item-Felder", function()
        for _, row in ServerCodes.list do
            local reward: any = row.reward
            T.expect(Codes.REWARD_FIELDS[reward.kind] ~= nil).toBe(true)
            for _, forbidden in { "crateId", "itemId", "items", "crate", "item", "robux", "productId" } do
                T.expect(reward[forbidden]).toBeNil()
            end
        end
        local kinds = {}
        for kind in Codes.REWARD_FIELDS do
            table.insert(kinds, kind)
        end
        table.sort(kinds)
        T.expect(kinds).toEqual({ "coinBoost", "gems", "luck" })
    end)

    T.it("jede Zeile der Server-Tabelle ist einmal einlösbar und ändert nur codes, gems oder boosts", function()
        for _, row in ServerCodes.list do
            local profile = player()
            local before = deepCopy(profile)
            local time = activeTimeOf(row)
            local result = Codes.redeem(profile, ServerCodes, time, `  {string.lower(row.code)} `)
            if result.ok ~= true then
                error(`Code "{row.id}" ließ sich nicht einlösen: {tostring(result.reason)} {tostring(result.detail)}`)
            end
            T.expect(result.reward.kind).toBe(row.reward.kind)
            T.expect(profile.codes).toEqual({ [row.id] = true })
            for _, field in changedFields(before, profile) do
                if not ALLOWED_WRITES[field] then
                    error(`Code "{row.id}" ändert das Feld {field}`)
                end
            end
            T.expect(Codes.redeem(profile, ServerCodes, time, row.code).reason).toBe("alreadyRedeemed")
        end
    end)

    T.it("Logic/Codes lädt keine Kisten-, Item- oder Kauf-Module und schreibt kein Inventar", function()
        for _, module in { "CrateOpen", "CrateRoll", "DirectShop", "Equipment", "Purchases", "Offers", "CrateItems", "Crates", "Products" } do
            if string.find(LOGIC_SOURCE, `require("./{module}")`, 1, true) or string.find(LOGIC_SOURCE, `require("../Data/{module}")`, 1, true) then
                error(`Logic/Codes lädt {module}`)
            end
        end
        for line in string.gmatch(LOGIC_SOURCE, "[^\n]+") do
            local code = string.match(line, "^(.-)%-%-") or line -- Kommentare ignorieren
            T.expect(string.find(code, "inventory", 1, true)).toBeNil()
            T.expect(string.find(code, "pity", 1, true)).toBeNil()
        end
    end)
end)

T.describe("Prüfung der Tabelle (check)", function()
    local function problemsWith(change: (codes: any) -> ()): { string }
        local codes = fixture()
        change(codes)
        return Codes.check(codes)
    end

    local function expectProblem(change: (codes: any) -> (), part: string)
        local problems = problemsWith(change)
        local found = false
        for _, text in problems do
            if string.find(text, part, 1, true) then
                found = true
            end
        end
        if not found then
            error(`erwartet einen Fehler mit "{part}", erhalten: {table.concat(problems, " | ")}`)
        end
    end

    T.it("die Server-Tabelle und die Test-Tabelle sind fehlerfrei", function()
        T.expect(Codes.check(ServerCodes)).toEqual({})
        T.expect(Codes.check(FIXTURE)).toEqual({})
    end)

    T.it("doppelte IDs und doppelte Codes werden abgelehnt", function()
        expectProblem(function(codes: any) codes.list[2].id = "gems_test" end, "id doppelt")
        expectProblem(function(codes: any) codes.list[2].code = "TEST-GEMS" end, "code doppelt")
    end)

    T.it("nicht normalisierte Codes und kaputte IDs werden abgelehnt", function()
        for _, bad: any in { "test-gems2", " TEST2", "TEST 2", string.rep("A", 25), "", "ÄRGER", 5, nil } do
            expectProblem(function(codes: any) codes.list[1].code = bad end, "code muss normalisiert sein")
        end
        for _, bad: any in { "", "mit leer", string.rep("a", 33), 5, nil, "ä" } do
            expectProblem(function(codes: any) codes.list[1].id = bad end, "id muss")
        end
    end)

    T.it("unbekannte Art (Kiste, Item, Robux), fremde Felder und kaputte Mengen werden abgelehnt", function()
        for _, kind: any in { "crate", "item", "robux", "coins", nil, 5 } do
            expectProblem(function(codes: any) codes.list[1].reward = { kind = kind, amount = 5 } end, "reward.kind")
        end
        expectProblem(function(codes: any) codes.list[1].reward = nil end, "reward.kind")
        expectProblem(function(codes: any) codes.list[1].reward.crateId = "gold" end, "reward.crateId")
        expectProblem(function(codes: any) codes.list[2].reward.amount = 5 end, "reward.amount")
        expectProblem(function(codes: any) codes.list[1].endAt = NOW end, "Feld \"endAt\" ist unbekannt")
        for _, bad: any in { 0, -1, 2.5, Codes.MAX_GEMS + 1, 0 / 0, "50" } do
            expectProblem(function(codes: any) codes.list[1].reward.amount = bad end, "reward.amount muss")
        end
        for _, bad: any in { 0, -1, 1.5, Codes.MAX_SECONDS + 1, math.huge, nil } do
            expectProblem(function(codes: any) codes.list[2].reward.seconds = bad end, "reward.seconds muss")
        end
        T.expect(Codes.MAX_GEMS).toBe(1000)
        T.expect(Codes.MAX_SECONDS).toBe(86400)
        -- Die Grenzen selbst sind erlaubt.
        T.expect(problemsWith(function(codes: any)
            codes.list[1].reward.amount = Codes.MAX_GEMS
            codes.list[2].reward.seconds = Codes.MAX_SECONDS
        end)).toEqual({})
    end)

    T.it("kaputte Zeiten werden abgelehnt: nicht endlich, negativ, endsAt nicht nach startsAt", function()
        for _, bad: any in { 0 / 0, math.huge, -1, "morgen" } do
            expectProblem(function(codes: any) codes.list[1].startsAt = bad end, "startsAt muss")
            expectProblem(function(codes: any) codes.list[1].endsAt = bad end, "endsAt muss")
        end
        expectProblem(function(codes: any)
            codes.list[1].startsAt = NOW
            codes.list[1].endsAt = NOW
        end, "endsAt muss nach startsAt")
        expectProblem(function(codes: any)
            codes.list[1].startsAt = NOW
            codes.list[1].endsAt = NOW - 1
        end, "endsAt muss nach startsAt")
    end)

    T.it("kaputte Tabelle: ohne list, Lücken, Textschlüssel, keine Tabelle als Zeile", function()
        T.expect(#Codes.check(nil) > 0).toBe(true)
        T.expect(#Codes.check({}) > 0).toBe(true)
        T.expect(#Codes.check({ list = "x" }) > 0).toBe(true)
        expectProblem(function(codes: any) codes.list.extra = codes.list[1] end, "Schlüssel extra")
        expectProblem(function(codes: any) codes.list[2] = "kaputt" end, "keine Tabelle")
    end)

    T.it("die Fehlertexte nennen nie den Text eines Codes", function()
        local problems = problemsWith(function(codes: any)
            codes.list[2].code = "TEST-GEMS" -- doppelt
            codes.list[3].reward.seconds = 0
        end)
        T.expect(#problems).toBe(2)
        for _, text in problems do
            T.expect(string.find(text, "TEST-GEMS", 1, true)).toBeNil()
            T.expect(string.find(text, "LUCKY7", 1, true)).toBeNil()
        end
    end)
end)

T.describe("Remote RedeemCode", function()
    T.it("ein Text, Länge aus Logic/Codes, Limit 1 je 3 s aus RemoteSpec", function()
        local def = RemoteSpec.byName.RedeemCode
        T.expect(def.kind).toBe("Function")
        T.expect(def.direction).toBe("ClientToServer")
        local schema = def.schema :: { Validate.Rule }
        T.expect(#schema).toBe(1)
        local rule: any = schema[1]
        T.expect(rule.kind).toBe("string")
        T.expect(rule.maxLen).toBe(Codes.MAX_LENGTH)
        T.expect(rule.minLen).toBe(Codes.MIN_LENGTH)
        T.expect((Validate.check(schema, { "abc" }, 1))).toBe(true)
        T.expect((Validate.check(schema, { "" }, 1))).toBe(false)
        T.expect((Validate.check(schema, { string.rep("x", 25) }, 1))).toBe(false)
        T.expect((Validate.check(schema, { 5 }, 1))).toBe(false)
        T.expect((Validate.check(schema, {}, 0))).toBe(false)
        T.expect((Validate.check(schema, { "abc", 50 }, 2))).toBe(false)
        local limit = def.limit :: RateLimiter.Limit
        T.expect(limit).toEqual({ calls = 1, per = 3 })
        local clock = { t = 0 }
        local limiter = RateLimiter.new(function(): number
            return clock.t
        end)
        T.expect(limiter:allow("1", "RedeemCode", limit)).toBe(true)
        T.expect(limiter:allow("1", "RedeemCode", limit)).toBe(false)
        clock.t += 3
        T.expect(limiter:allow("1", "RedeemCode", limit)).toBe(true)
    end)

    T.it("der Service registriert RedeemCode und läuft unter der gemeinsamen Sperre von Crates", function()
        T.expect(string.find(SERVICE_SOURCE, 'Net.on("RedeemCode", onRedeemCode)', 1, true) ~= nil).toBe(true)
        T.expect(string.find(SERVICE_SOURCE, "Crates.runExclusive(player, LOCK_LABEL", 1, true) ~= nil).toBe(true)
        T.expect(string.find(SERVICE_SOURCE, "PlayerData.isActive(player.UserId)", 1, true) ~= nil).toBe(true)
    end)
end)

T.describe("Profil und Sandsturm", function()
    T.it("das Standardprofil hat codes = {}; ein alter Stand ohne codes bekommt es ohne neue Version", function()
        T.expect(player().codes).toEqual({})
        local old: any = Profile.default(NOW)
        old.codes = nil -- Stand vor Paket 5.2
        local versionBefore = old.version
        local migrated, status = Profile.migrate(old, nil, NOW)
        local profile: any = migrated
        T.expect(status).toBe("ok")
        T.expect(profile.version).toBe(versionBefore)
        T.expect(Migrations.CURRENT_VERSION).toBe(versionBefore) -- 5.2 bringt keine neue Profilversion
        T.expect(profile.codes).toEqual({})
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        -- Gesetzte Werte bleiben bei einer zweiten Migration.
        profile.codes = { gems_test = true }
        local again: any = Profile.migrate(profile, nil, NOW)
        T.expect(again.codes).toEqual({ gems_test = true })
    end)

    T.it("sanitize: nur Text-Schlüssel mit Wert true bleiben; falscher Typ wird {}; unbekannte IDs bleiben", function()
        local profile: any = player()
        profile.codes = {
            gems_test = true,
            alter_code = true, -- unbekannte ID (Code gelöscht): bleibt
            nein = false,
            text = "ja",
            zahl = 1,
            kaputt = 0 / 0,
            tabelle = { true },
            [5] = true,
            [""] = true,
        }
        local warnings = Profile.sanitize(profile, NOW)
        T.expect(#warnings > 0).toBe(true)
        T.expect(profile.codes).toEqual({ gems_test = true, alter_code = true })
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        for _, bad: any in { "kaputt", 5, true } do
            profile.codes = bad
            T.expect(#Profile.sanitize(profile, NOW)).toBe(1)
            T.expect(profile.codes).toEqual({})
        end
    end)

    T.it("der Sandsturm behält codes: danach keine zweite Einlösung", function()
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "codes") ~= nil).toBe(true)
        T.expect(table.find(Sandstorm.RESET_FIELDS, "codes")).toBeNil()
        local profile = player()
        T.expect(Codes.redeem(profile, fixture(), NOW, "TEST-GEMS").ok).toBe(true)
        profile.nodes = { collect_tool_2 = true, collect_tool_3 = true, collect_tool_4 = true }
        profile.zones = { dunes = true, oasis = true, canyon = true }
        profile.runEarned = BigNum.serialize(BigNum.new(1, 12))
        local result = Sandstorm.apply(profile)
        T.expect(result ~= nil).toBe(true)
        T.expect(profile.prestiges).toBe(1)
        T.expect(profile.codes).toEqual({ gems_test = true })
        T.expect(Codes.redeem(profile, fixture(), NOW, "TEST-GEMS").reason).toBe("alreadyRedeemed")
    end)
end)

T.describe("Studio-Hilfe DebugCodes", function()
    T.it("parseDebug: nur reset, alles andere mit Hinweis", function()
        T.expect(select(1, Codes.parseDebug("reset"))).toBe("reset")
        for _, bad: any in { "Reset", "", "alles", 5, true, nil, string.rep("a", 40) } do
            local action, problem = Codes.parseDebug(bad)
            T.expect(action).toBeNil()
            T.expect(type(problem)).toBe("string")
        end
    end)

    T.it("nach reset (codes = {}) ist ein Code wieder einlösbar; der Service hängt den Listener nur in Studio an", function()
        local profile = player()
        Codes.redeem(profile, fixture(), NOW, "BOOST1")
        T.expect(Codes.redeem(profile, fixture(), NOW, "BOOST1").reason).toBe("alreadyRedeemed")
        profile.codes = {} -- wie der Service bei "reset"
        T.expect(Codes.redeem(profile, fixture(), NOW, "BOOST1").ok).toBe(true)
        T.expect(string.find(SERVICE_SOURCE, "if IS_STUDIO then\n        Players.PlayerAdded:Connect(onPlayerAdded)", 1, true) ~= nil).toBe(true)
    end)
end)

T.finish()
