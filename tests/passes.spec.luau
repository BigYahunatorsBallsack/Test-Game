--!strict
-- Paket 4.4: Gamepass-Besitz (Logic/Passes), Spielstand Version 6 (Migration, sanitize, Speichern,
-- Laden, Sandsturm) und der Kauf des Münz-Boosts über ProcessReceipt (Logic/Purchases mit dem Handler
-- aus Logic/Perks, PlayerSession und Fake-Speicher), dazu die Studio-Hilfe processDebug.
--
-- Warten heißt hier wie in tests/purchases.spec.luau: die Fake-Uhr rückt vor und die Koroutine gibt die
-- Kontrolle an den Test zurück (coroutine.yield).

local T = require("./lib/expect")
local serde = require("@lune/serde")
local FakeStore = require("./lib/fakestore")
local Passes = require("../src/shared/Logic/Passes")
local Perks = require("../src/shared/Logic/Perks")
local Profile = require("../src/shared/Logic/Profile")
local Migrations = require("../src/shared/Logic/Migrations")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local PlayerSession = require("../src/shared/Logic/PlayerSession")
local Purchases = require("../src/shared/Logic/Purchases")
local BigNum = require("../src/shared/Logic/BigNum")
local Products = require("../src/shared/Data/Products")
local GemPacks = require("../src/shared/Data/GemPacks")
local Economy = require("../src/shared/Data/Economy")

local NOW = 1_700_000_000
local USER = 42
local KEY = PlayerSession.keyFor(USER)
local BOOST = Economy.coinBoost.durationSeconds
-- Test-IDs: Die echten Daten haben bis zur Anlage im Creator Dashboard nur Platzhalter (0).
local PASS_IDS = { double_coins = 7_000_001, auto_dig = 7_000_002, big_tank = 7_000_003 }
local PACK_PRODUCT_BASE = 9_000_000
local OTHER_PRODUCT_BASE = 9_000_100

local function deepCopy(value: any): any
    return FakeStore.deepCopy(value)
end

-- Daten mit echten (Test-)IDs für Gamepasses, Gem-Pakete und Developer Products.
local function testData(): any
    local products = { list = {}, byId = {} } :: any
    for index, product in Products.list do
        local copy = table.clone(product)
        if copy.kind == "gamepass" then
            copy.productId = PASS_IDS[copy.id]
        else
            copy.productId = OTHER_PRODUCT_BASE + index
        end
        products.list[index] = copy
        products.byId[copy.id] = copy
    end
    local packs = { list = {}, byId = {} } :: any
    for index, pack in GemPacks.list do
        local copy = table.clone(pack)
        copy.productId = PACK_PRODUCT_BASE + index
        packs.list[index] = copy
        packs.byId[copy.id] = copy
    end
    return { Products = products, GemPacks = packs, Economy = Economy }
end

local DATA = testData()
local REAL_DATA = { Products = Products, GemPacks = GemPacks, Economy = Economy }

T.describe("Gamepass-Besitz: Abfrage bei Roblox (4.4)", function()
    local function fakeQuery(answers: { any }): (() -> any, { calls: number, waits: { number } })
        local log = { calls = 0, waits = {} :: { number } }
        local function query(): any
            log.calls += 1
            local answer = answers[log.calls]
            if answer == "error" then
                error("HTTP 503 (Service Unavailable)")
            end
            return answer
        end
        return query, log
    end

    T.it("eine true/false-Antwort zählt sofort", function()
        local query, log = fakeQuery({ true })
        local waits: { number } = {}
        local result = Passes.ask(query, 3, 2, function(s: number)
            table.insert(waits, s)
        end)
        T.expect(result).toEqual({ ok = true, owns = true })
        T.expect(log.calls).toBe(1)
        T.expect(#waits).toBe(0)
        local queryNo = fakeQuery({ false })
        T.expect(Passes.ask(queryNo, 3, 2, function() end)).toEqual({ ok = true, owns = false })
    end)

    T.it("Fehler und Antworten ohne true/false zählen als gescheitert, bis zu 3 Versuche mit Pause", function()
        local query, log = fakeQuery({ "error", "ja", true })
        local waits: { number } = {}
        local messages: { string } = {}
        local result = Passes.ask(query, 3, 2, function(s: number)
            table.insert(waits, s)
        end, function(m: string)
            table.insert(messages, m)
        end)
        T.expect(result).toEqual({ ok = true, owns = true })
        T.expect(log.calls).toBe(3)
        T.expect(waits).toEqual({ 2, 2 })
        T.expect(#messages).toBe(2)
        T.expect(messages[1]).toContain("503")
    end)

    T.it("alle Versuche gescheitert: ok = false (der gemerkte Besitz bleibt)", function()
        local query, log = fakeQuery({ "error", "error", "error", true })
        local result = Passes.ask(query, 3, 2, function() end)
        T.expect(result.ok).toBe(false)
        T.expect(log.calls).toBe(3)
        local nilQuery = fakeQuery({})
        T.expect(Passes.ask(nilQuery, 3, 2, function() end).ok).toBe(false)
    end)

    T.it("Spieler weg: keine weiteren Versuche", function()
        local query, log = fakeQuery({ "error", true })
        local here = true
        local result = Passes.ask(query, 3, 2, function()
            here = false
        end, nil, function(): boolean
            return here
        end)
        T.expect(result.ok).toBe(false)
        T.expect(log.calls).toBe(1)
    end)
end)

T.describe("Gamepass-Besitz: Entscheidungen (4.4)", function()
    T.it("'ja' trägt sofort ein, erst das zweite 'nein' in Folge entfernt (Security-Review 4.4)", function()
        local granted, change = Passes.decideCheck({}, "big_tank", { ok = true, owns = true })
        T.expect(granted).toEqual({ big_tank = true })
        T.expect(change).toBe("granted")
        -- Erstes "nein": nichts entfernen, später erneut fragen.
        local first, firstChange = Passes.decideCheck({ big_tank = true, auto_dig = true }, "big_tank", { ok = true, owns = false })
        T.expect(first).toBeNil()
        T.expect(firstChange).toBe("confirmNo")
        -- Zweites "nein" in Folge: entfernen.
        local revoked, change2 = Passes.decideCheck({ big_tank = true, auto_dig = true }, "big_tank", { ok = true, owns = false }, { previousNo = true })
        T.expect(revoked).toEqual({ auto_dig = true })
        T.expect(change2).toBe("revoked")
        -- Schon so: keine Änderung (kein Abrechnen, kein Schreiben), auch keine Nachfrage.
        T.expect((Passes.decideCheck({ big_tank = true }, "big_tank", { ok = true, owns = true }))).toBeNil()
        local none, noneChange = Passes.decideCheck({}, "big_tank", { ok = true, owns = false })
        T.expect(none).toBeNil()
        T.expect(noneChange).toBeNil()
    end)

    T.it("schlägt die Abfrage fehl, gilt der gemerkte Besitz", function()
        T.expect((Passes.decideCheck({ big_tank = true }, "big_tank", { ok = false }))).toBeNil()
        T.expect((Passes.decideCheck({}, "big_tank", { ok = false }))).toBeNil()
        local broken: any = { ok = true, owns = "ja" }
        T.expect((Passes.decideCheck({ big_tank = true }, "big_tank", broken))).toBeNil()
        local notTable: any = "kaputt"
        T.expect((Passes.decideCheck({ big_tank = true }, "big_tank", notTable))).toBeNil()
    end)

    T.it("in Studio und nach einem bestätigten Kauf in dieser Sitzung entfernt ein 'nein' nie", function()
        for _, ctx in { { studio = true }, { boughtThisSession = true } } :: { any } do
            for _, previousNo in { false, true } do
                local c = table.clone(ctx)
                c.previousNo = previousNo
                local result, change = Passes.decideCheck({ big_tank = true }, "big_tank", { ok = true, owns = false }, c)
                T.expect(result).toBeNil()
                T.expect(change).toBeNil()
            end
        end
        -- Ein "ja" trägt auch in Studio ein.
        T.expect((Passes.decideCheck({}, "big_tank", { ok = true, owns = true }, { studio = true }))).toEqual({ big_tank = true })
    end)

    T.it("Entscheidungen geben neue Tabellen zurück und lassen das Profil unverändert; unbekannte Pässe ändern nichts", function()
        local passes = { auto_dig = true, alt_aus_der_zukunft = true, double_coins = false :: any }
        local before = deepCopy(passes)
        local granted = Passes.decideCheck(passes, "big_tank", { ok = true, owns = true })
        T.expect(granted).toEqual({ auto_dig = true, big_tank = true }) -- nur bekannte Pässe mit true
        T.expect(passes).toEqual(before)
        T.expect((Passes.decideCheck(passes, "gibt_es_nicht", { ok = true, owns = true }))).toBeNil()
        T.expect((Passes.decideCheck(passes, "starter_pack", { ok = true, owns = true }))).toBeNil()
    end)

    T.it("bestätigter Kauf: decideConfirmedPurchase trägt bekannte Pässe ein, schon eingetragen ändert nichts", function()
        local before = { auto_dig = true }
        T.expect(Passes.decideConfirmedPurchase(before, "double_coins")).toEqual({ auto_dig = true, double_coins = true })
        T.expect(before).toEqual({ auto_dig = true })
        T.expect(Passes.decideConfirmedPurchase({ double_coins = true }, "double_coins")).toBeNil()
        T.expect(Passes.decideConfirmedPurchase({}, "gibt_es_nicht")).toBeNil()
        T.expect(Passes.decideConfirmedPurchase({}, "coin_boost")).toBeNil()
    end)

    T.it("Gamepass-IDs: echte Daten (alle 0), ungültige und doppelt vergebene IDs finden keinen Pass", function()
        T.expect(Passes.idForGamePassId(0)).toBeNil()
        T.expect(#Passes.toCheck()).toBe(0) -- ProductId 0: keine Abfrage, nur der gemerkte Besitz
        for _, gamePassId in { 0, -PASS_IDS.big_tank, 123, 1.5, 0 / 0, math.huge, "7000003", nil :: any } do
            T.expect(Passes.idForGamePassId(gamePassId, DATA)).toBeNil()
        end
        T.expect(Passes.idForGamePassId(PASS_IDS.double_coins, DATA)).toBe("double_coins")
        local dup = testData()
        dup.Products.byId.auto_dig.productId = PASS_IDS.double_coins
        T.expect(Passes.idForGamePassId(PASS_IDS.double_coins, dup)).toBeNil()
        -- Developer Products zählen nie als Gamepass, auch mit gleicher Nummer.
        local devId = DATA.Products.byId.coin_boost.productId
        T.expect(Passes.idForGamePassId(devId, DATA)).toBeNil()
    end)

    T.it("abgefragt werden nur Gamepasses mit echter ID, die Pass-ID kommt über die productId", function()
        local list = Passes.toCheck(DATA)
        T.expect(#list).toBe(3)
        for _, pass in list do
            T.expect(pass.productId).toBe(PASS_IDS[pass.id])
            T.expect(Passes.idForGamePassId(pass.productId, DATA)).toBe(pass.id)
        end
        local partial = testData()
        partial.Products.byId.auto_dig.productId = 0
        T.expect(#Passes.toCheck(partial)).toBe(2)
    end)

    T.it("Kauf vor dem Laden: withBought trägt die gekauften Pässe ein", function()
        T.expect(Passes.withBought({ auto_dig = true }, { big_tank = true })).toEqual({ auto_dig = true, big_tank = true })
        T.expect(Passes.withBought({ big_tank = true }, { big_tank = true })).toBeNil()
        T.expect(Passes.withBought({}, { gibt_es_nicht = true })).toBeNil()
        T.expect(Passes.withBought({}, {})).toBeNil()
    end)

    T.it("Studio-Attribut DebugPass: 'big_tank' an, '-big_tank' aus, unbekannte IDs mit Grund", function()
        local id, on = Passes.parseDebug("big_tank")
        T.expect(id).toBe("big_tank")
        T.expect(on).toBe(true)
        local id2, on2 = Passes.parseDebug("-big_tank")
        T.expect(id2).toBe("big_tank")
        T.expect(on2).toBe(false)
        for _, bad in { "gibt_es_nicht", "starter_pack", "coin_boost" } do
            local none, _, problem = Passes.parseDebug(bad)
            T.expect(none).toBeNil()
            T.expect(problem).toContain("unbekannter Gamepass")
        end
        for _, bad in { "", "big tank", "--big_tank", 5, string.rep("a", 65), nil :: any } do
            local none, _, problem = Passes.parseDebug(bad)
            T.expect(none).toBeNil()
            T.expect(problem ~= nil).toBe(true)
        end
        T.expect(Passes.with({}, "big_tank", true)).toEqual({ big_tank = true })
        T.expect(Passes.with({ big_tank = true, auto_dig = true }, "big_tank", false)).toEqual({ auto_dig = true })
    end)
end)

T.describe("Gamepass-Besitz: Prüf-Ablauf beim Laden, runCheck (4.4)", function()
    -- Fake-Abhängigkeiten: `answers` je Runde ("error" = Fehler, sonst das Ergebnis von ask).
    local function setup(answers: { any }, passes: any, context: any?): (any, any)
        local state = {
            passes = passes,
            asks = 0,
            waits = {} :: { number },
            writes = {} :: { any },
            here = true,
            context = context or {},
        }
        local deps = {
            passId = "big_tank",
            ask = function(): any
                state.asks += 1
                local answer = answers[state.asks]
                if answer == "error" then
                    error("HTTP 503 (Service Unavailable)")
                end
                return answer
            end,
            wait = function(seconds: number)
                table.insert(state.waits, seconds)
            end,
            stillValid = function(): boolean
                return state.here
            end,
            passesOf = function(): any
                return state.passes
            end,
            context = function(): any
                return state.context
            end,
            write = function(newPasses: any, change: string)
                table.insert(state.writes, { passes = newPasses, change = change })
                state.passes = newPasses
            end,
            rounds = 10,
            recheckSeconds = 60,
            data = DATA,
        }
        return deps, state
    end
    local YES = { ok = true, owns = true }
    local NO = { ok = true, owns = false }
    local FAILED = { ok = false }

    T.it("ein einzelnes 'nein' entfernt nicht, das zweite 'nein' nach RECHECK_SECONDS schon", function()
        local deps, state = setup({ NO, NO }, { big_tank = true, auto_dig = true })
        T.expect(Passes.runCheck(deps)).toBe("revoked")
        T.expect(state.asks).toBe(2)
        T.expect(state.waits).toEqual({ 60 })
        T.expect(#state.writes).toBe(1)
        T.expect(state.writes[1].change).toBe("revoked")
        T.expect(state.passes).toEqual({ auto_dig = true })
    end)

    T.it("'nein', dann Fehler, dann 'nein': der Pass bleibt, die Zählung beginnt neu", function()
        local deps, state = setup({ NO, FAILED, NO, "error", NO, YES }, { big_tank = true })
        T.expect(Passes.runCheck(deps)).toBe("unchanged") -- am Ende "ja": schon eingetragen
        T.expect(state.asks).toBe(6)
        T.expect(#state.writes).toBe(0)
        T.expect(state.passes).toEqual({ big_tank = true })
        -- Ohne das "ja" am Ende: nach dem Fehler wieder zwei "nein" in Folge nötig.
        local deps2, state2 = setup({ NO, "error", NO, NO }, { big_tank = true })
        T.expect(Passes.runCheck(deps2)).toBe("revoked")
        T.expect(state2.asks).toBe(4)
        T.expect(state2.passes).toEqual({})
    end)

    T.it("'nein' und dann nur noch Fehler bis zum Rundenende: Pass bleibt ('kept')", function()
        local answers: { any } = { NO }
        for _ = 2, 10 do
            table.insert(answers, FAILED)
        end
        local deps, state = setup(answers, { big_tank = true })
        T.expect(Passes.runCheck(deps)).toBe("kept")
        T.expect(state.asks).toBe(10)
        T.expect(#state.waits).toBe(9)
        T.expect(#state.writes).toBe(0)
    end)

    T.it("'ja' trägt in der ersten Runde ein; ein Fehler vorher verzögert nur", function()
        local deps, state = setup({ YES }, {})
        T.expect(Passes.runCheck(deps)).toBe("granted")
        T.expect(state.writes[1].change).toBe("granted")
        T.expect(state.passes).toEqual({ big_tank = true })
        local deps2, state2 = setup({ "error", YES }, {})
        T.expect(Passes.runCheck(deps2)).toBe("granted")
        T.expect(state2.waits).toEqual({ 60 })
    end)

    T.it("in Studio und nach einem bestätigten Kauf entfernt auch 'nein, nein' nichts", function()
        for _, ctx in { { studio = true }, { boughtThisSession = true } } :: { any } do
            local deps, state = setup({ NO, NO, NO }, { big_tank = true }, ctx)
            T.expect(Passes.runCheck(deps)).toBe("unchanged")
            T.expect(#state.writes).toBe(0)
        end
    end)

    T.it("der Kontext wird live gelesen: ein Kauf zwischen den beiden 'nein' schützt den Pass", function()
        local deps, state = setup({ NO, NO }, { big_tank = true })
        local baseWait = deps.wait
        deps.wait = function(seconds: number)
            baseWait(seconds)
            state.context = { boughtThisSession = true }
        end
        T.expect(Passes.runCheck(deps)).toBe("unchanged")
        T.expect(state.passes).toEqual({ big_tank = true })
    end)

    T.it("Spieler weg (vor oder während der Abfrage): nichts schreiben", function()
        local deps, state = setup({ NO, NO }, { big_tank = true })
        deps.wait = function()
            state.here = false
        end
        T.expect(Passes.runCheck(deps)).toBe("gone")
        T.expect(#state.writes).toBe(0)
        local deps2, state2 = setup({ YES }, {})
        deps2.ask = function(): any
            state2.here = false
            return YES
        end
        T.expect(Passes.runCheck(deps2)).toBe("gone")
        T.expect(#state2.writes).toBe(0)
    end)
end)

T.describe("Gamepass-Kauf-Ereignis: Bestätigung bei Roblox (Security-Review 4.4)", function()
    -- Fake-Spieler und Fake-Abhängigkeiten. `spawn` merkt sich die Threads, der Test startet sie
    -- selbst (so lässt sich "läuft gerade" prüfen); `answers[gamePassId]` = Liste von Antworten.
    local function setup(options: any?): (any, any, any)
        local opts = options or {}
        local owner = { name = "Spieler" }
        local state = {
            present = { [owner] = true } :: { [any]: boolean },
            profiles = { [owner] = if opts.notLoaded then nil else { passes = opts.passes or {} } } :: { [any]: any },
            queries = {} :: { any },
            answers = opts.answers or {},
            threads = {} :: { () -> () },
            grants = {} :: { any },
            remembered = {} :: { [any]: { [string]: boolean } },
            waits = {} :: { number },
            logs = {} :: { string },
        }
        local deps = {
            query = function(who: any, gamePassId: number): any
                table.insert(state.queries, gamePassId)
                if opts.onQuery then
                    opts.onQuery(state, who)
                end
                local list = state.answers[gamePassId] or {}
                local answer = table.remove(list, 1)
                if answer == "error" then
                    error("HTTP 503")
                end
                return answer or { ok = false }
            end,
            wait = function(seconds: number)
                table.insert(state.waits, seconds)
            end,
            spawn = function(fn: () -> ())
                table.insert(state.threads, fn)
            end,
            isPresent = function(who: any): boolean
                return state.present[who] == true
            end,
            passesOf = function(who: any): any
                local profile = state.profiles[who]
                return if profile then profile.passes else nil
            end,
            grant = function(who: any, passId: string, newPasses: any)
                table.insert(state.grants, passId)
                state.profiles[who].passes = newPasses
            end,
            remember = function(who: any, passId: string)
                local set = state.remembered[who] or {}
                set[passId] = true
                state.remembered[who] = set
            end,
            rounds = 3,
            retrySeconds = 10,
            trustEvent = opts.trustEvent,
            log = function(message: string)
                table.insert(state.logs, message)
            end,
            data = DATA,
        }
        return Passes.newPurchaseConfirmer(deps), state, owner
    end
    local function runThreads(state: any)
        while #state.threads > 0 do
            local fn = table.remove(state.threads, 1)
            fn()
        end
    end
    local YES = { ok = true, owns = true }
    local NO = { ok = true, owns = false }
    local DC = PASS_IDS.double_coins

    T.it("ohne bestätigte Abfrage kein Eintrag: 'nein', Fehler und kaputte Antworten", function()
        for _, answers in { { NO, NO, NO }, { "error", "error", "error" }, { { ok = true, owns = "ja" }, { ok = false }, "kaputt" } } :: { any } do
            local confirmer, state, owner = setup({ answers = { [DC] = answers } })
            T.expect(confirmer.onPurchaseFinished(owner, DC, true)).toBe("started")
            runThreads(state)
            T.expect(#state.queries).toBe(3) -- wasPurchased == true: bis zu 3 Runden
            T.expect(state.waits).toEqual({ 10, 10 })
            T.expect(#state.grants).toBe(0)
            T.expect(state.remembered[owner]).toBeNil()
            T.expect(state.profiles[owner].passes).toEqual({})
            T.expect(confirmer.isRunning(owner, "double_coins")).toBe(false)
        end
    end)

    T.it("gefälschtes Ereignis mit wasPurchased == false: eine Abfrage, kein Eintrag", function()
        local confirmer, state, owner = setup({ answers = { [DC] = { NO, YES } } })
        T.expect(confirmer.onPurchaseFinished(owner, DC, false)).toBe("started")
        runThreads(state)
        T.expect(#state.queries).toBe(1)
        T.expect(#state.grants).toBe(0)
    end)

    T.it("mit Bestätigung: merken und eintragen; auch nach einem 'nein' in der ersten Runde", function()
        local confirmer, state, owner = setup({ answers = { [DC] = { YES } }, passes = { auto_dig = true } })
        T.expect(confirmer.onPurchaseFinished(owner, DC, true)).toBe("started")
        T.expect(confirmer.isRunning(owner, "double_coins")).toBe(true)
        runThreads(state)
        T.expect(state.grants).toEqual({ "double_coins" })
        T.expect(state.remembered[owner]).toEqual({ double_coins = true })
        T.expect(state.profiles[owner].passes).toEqual({ auto_dig = true, double_coins = true })
        T.expect(confirmer.isRunning(owner, "double_coins")).toBe(false)
        -- Roblox kennt den Kauf erst in der zweiten Runde (veralteter Zwischenspeicher).
        local c2, s2, o2 = setup({ answers = { [DC] = { NO, YES } } })
        c2.onPurchaseFinished(o2, DC, true)
        runThreads(s2)
        T.expect(#s2.queries).toBe(2)
        T.expect(s2.grants).toEqual({ "double_coins" })
        -- Auch ein Ereignis mit wasPurchased == false trägt ein, wenn Roblox "ja" sagt.
        local c3, s3, o3 = setup({ answers = { [DC] = { YES } } })
        c3.onPurchaseFinished(o3, DC, false)
        runThreads(s3)
        T.expect(s3.grants).toEqual({ "double_coins" })
    end)

    T.it("Spam: je Spieler und Pass höchstens eine Prüfung gleichzeitig", function()
        local confirmer, state, owner = setup({ answers = { [DC] = { NO, NO, NO } } })
        T.expect(confirmer.onPurchaseFinished(owner, DC, true)).toBe("started")
        for _ = 1, 50 do
            T.expect(confirmer.onPurchaseFinished(owner, DC, true)).toBe("busy")
            T.expect(confirmer.onPurchaseFinished(owner, DC, false)).toBe("busy")
        end
        T.expect(#state.threads).toBe(1)
        -- Ein anderer Pass hat seine eigene Prüfung.
        T.expect(confirmer.onPurchaseFinished(owner, PASS_IDS.big_tank, true)).toBe("started")
        T.expect(#state.threads).toBe(2)
        runThreads(state)
        T.expect(#state.queries).toBe(6) -- 3 Runden je Pass, keine weiteren
        -- Nach dem Ende darf eine neue Prüfung starten.
        T.expect(confirmer.onPurchaseFinished(owner, DC, true)).toBe("started")
    end)

    T.it("Kauf während einer kurzen Prüfung (abgebrochenes Fenster davor): die Prüfung verlängert sich, der Kauf geht nicht verloren", function()
        local confirmer, state, owner = setup({ answers = { [DC] = { NO, NO, YES } } })
        T.expect(confirmer.onPurchaseFinished(owner, DC, false)).toBe("started") -- 1 Runde
        T.expect(confirmer.onPurchaseFinished(owner, DC, true)).toBe("busy") -- verlängert auf 3
        T.expect(#state.threads).toBe(1)
        runThreads(state)
        T.expect(#state.queries).toBe(3)
        T.expect(state.grants).toEqual({ "double_coins" })
        -- Ein späteres Ereignis mit wasPurchased == false verkürzt nie.
        local c2, s2, o2 = setup({ answers = { [DC] = { NO, NO, NO } } })
        c2.onPurchaseFinished(o2, DC, true)
        c2.onPurchaseFinished(o2, DC, false)
        runThreads(s2)
        T.expect(#s2.queries).toBe(3)
    end)

    T.it("schon eingetragen: keine Abfrage; unbekannte IDs und 0: nichts", function()
        local confirmer, state, owner = setup({ passes = { double_coins = true } })
        T.expect(confirmer.onPurchaseFinished(owner, DC, true)).toBe("owned")
        for _, bad in { 0, 123, -DC, 1.5, 0 / 0, math.huge, "7000001", nil :: any, DATA.Products.byId.coin_boost.productId } do
            T.expect(confirmer.onPurchaseFinished(owner, bad, true)).toBe("unknown")
        end
        T.expect(#state.threads).toBe(0)
        T.expect(#state.queries).toBe(0)
        T.expect(#state.logs).toBe(0) -- keine Protokollflut bei Spam mit unbekannten IDs
    end)

    T.it("Spieler nicht (mehr) da: nichts starten, nichts merken (kein Speicherleck)", function()
        local confirmer, state, owner = setup({ answers = { [DC] = { YES } } })
        state.present[owner] = nil
        T.expect(confirmer.onPurchaseFinished(owner, DC, true)).toBe("absent")
        T.expect(#state.threads).toBe(0)
        -- Spieler geht, während die Abfrage läuft.
        local c2, s2, o2 = setup({
            answers = { [DC] = { YES } },
            onQuery = function(st: any, who: any)
                st.present[who] = nil
            end,
        })
        T.expect(c2.onPurchaseFinished(o2, DC, true)).toBe("started")
        c2.forget(o2)
        runThreads(s2)
        T.expect(#s2.grants).toBe(0)
        T.expect(s2.remembered[o2]).toBeNil()
        T.expect(c2.isRunning(o2, "double_coins")).toBe(false)
    end)

    T.it("Profil noch nicht geladen: erst nach der Bestätigung merken, beim Laden trägt withBought ein", function()
        local confirmer, state, owner = setup({ notLoaded = true, answers = { [DC] = { NO, NO, NO } } })
        T.expect(confirmer.onPurchaseFinished(owner, DC, true)).toBe("started")
        T.expect(state.remembered[owner]).toBeNil() -- vor der Bestätigung nichts gemerkt
        runThreads(state)
        T.expect(state.remembered[owner]).toBeNil() -- ohne Bestätigung auch danach nicht
        local c2, s2, o2 = setup({ notLoaded = true, answers = { [DC] = { YES } } })
        c2.onPurchaseFinished(o2, DC, true)
        T.expect(s2.remembered[o2]).toBeNil()
        runThreads(s2)
        T.expect(s2.remembered[o2]).toEqual({ double_coins = true })
        T.expect(#s2.grants).toBe(0)
        T.expect(Passes.withBought({}, s2.remembered[o2], DATA)).toEqual({ double_coins = true })
    end)

    T.it("Fehler in einer Abhängigkeit beendet die Prüfung sauber (kein dauerhaftes 'busy')", function()
        local confirmer, state, owner = setup({ answers = { [DC] = { NO, NO, NO } } })
        local spawnFailed = Passes.newPurchaseConfirmer({
            query = function(): any
                return YES
            end,
            wait = function() end,
            spawn = function()
                error("kaputt")
            end,
            isPresent = function(): boolean
                return true
            end,
            passesOf = function(): any
                return {}
            end,
            grant = function() end,
            remember = function() end,
            rounds = 3,
            retrySeconds = 10,
            data = DATA,
        })
        T.expect(spawnFailed.onPurchaseFinished(owner, DC, true)).toBe("started")
        T.expect(spawnFailed.isRunning(owner, "double_coins")).toBe(false)
        -- Fehler beim Warten zwischen den Runden.
        confirmer.onPurchaseFinished(owner, DC, true)
        local fn = table.remove(state.threads, 1)
        state.waits = nil :: any -- table.insert auf nil wirft
        fn()
        T.expect(confirmer.isRunning(owner, "double_coins")).toBe(false)
        T.expect(state.profiles[owner].passes).toEqual({})
    end)

    T.it("nur mit trustEvent (Studio) gilt wasPurchased == true ohne Abfrage", function()
        local confirmer, state, owner = setup({ trustEvent = true })
        T.expect(confirmer.onPurchaseFinished(owner, DC, true)).toBe("trusted")
        T.expect(#state.queries).toBe(0)
        T.expect(state.grants).toEqual({ "double_coins" })
        T.expect(state.remembered[owner]).toEqual({ double_coins = true })
        -- wasPurchased ~= true wird auch in Studio abgefragt.
        local c2, s2, o2 = setup({ trustEvent = true, answers = { [PASS_IDS.big_tank] = { NO } } })
        T.expect(c2.onPurchaseFinished(o2, PASS_IDS.big_tank, false)).toBe("started")
        runThreads(s2)
        T.expect(#s2.grants).toBe(0)
    end)
end)

T.describe("Spielstand Version 6 (4.4)", function()
    local function v5Profile(): any
        local profile: any = Profile.default(NOW)
        profile.version = 5
        profile.passes = nil
        profile.settings = nil
        profile.boosts = { coinsUntil = NOW + 77 }
        return profile
    end

    T.it("Migration 5 auf 6 legt passes und settings.autoDig an; der Boost bleibt", function()
        local migrated, status = Profile.migrate(v5Profile(), nil, NOW)
        local profile: any = migrated
        T.expect(status).toBe("ok")
        T.expect(profile.version).toBe(Migrations.CURRENT_VERSION) -- 6 in Paket 4.4, seit Paket 4.5 weiter auf 7
        T.expect(Migrations.CURRENT_VERSION >= 6).toBe(true)
        T.expect(profile.passes).toEqual({})
        T.expect(profile.settings).toEqual({ autoDig = true })
        -- Der Boost bleibt; luckUntil (Glücks-Boost, Paket 5.1) füllt Profile.migrate mit 0 auf.
        T.expect(profile.boosts).toEqual({ coinsUntil = NOW + 77, luckUntil = 0 })
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        local again = Profile.migrate(deepCopy(profile), nil, NOW)
        T.expect(again).toEqual(profile)
    end)

    T.it("Migration 5 auf 6 legt nur Fehlendes an (Kette läuft erneut: gemerkter Besitz bleibt)", function()
        local old = v5Profile()
        old.passes = { big_tank = true }
        old.settings = { autoDig = false, music = true }
        local migrated: any = Profile.migrate(old, nil, NOW)
        T.expect(migrated.passes).toEqual({ big_tank = true })
        T.expect(migrated.settings).toEqual({ autoDig = false, music = true })
        local broken = v5Profile()
        broken.settings = { autoDig = "ja" }
        T.expect((Profile.migrate(broken, nil, NOW) :: any).settings).toEqual({ autoDig = true })
        local notTable = v5Profile()
        notTable.passes = "kaputt"
        notTable.settings = 7
        local fixed: any = Profile.migrate(notTable, nil, NOW)
        T.expect(fixed.passes).toEqual({})
        T.expect(fixed.settings).toEqual({ autoDig = true })
    end)

    T.it("sanitize entfernt unbekannte Pass-IDs und Werte außer true", function()
        local profile: any = Profile.default(NOW)
        profile.passes = {
            big_tank = true,
            double_coins = false,
            auto_dig = "true",
            starter_pack = true, -- Developer Product, kein Gamepass
            gibt_es_nicht = true,
            [5] = true,
        }
        local warnings = Profile.sanitize(profile, NOW)
        T.expect(profile.passes).toEqual({ big_tank = true })
        T.expect(#warnings >= 5).toBe(true)
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        local broken: any = Profile.default(NOW)
        broken.passes = "kaputt"
        Profile.sanitize(broken, NOW)
        T.expect(broken.passes).toEqual({})
    end)

    T.it("sanitize repariert settings.autoDig (Boolean, sonst an) und eine kaputte Boost-Endzeit (0)", function()
        local profile: any = Profile.default(NOW)
        profile.settings = { autoDig = "aus", music = true }
        Profile.sanitize(profile, NOW)
        T.expect(profile.settings).toEqual({ autoDig = true, music = true })
        profile.settings = "kaputt"
        Profile.sanitize(profile, NOW)
        T.expect(profile.settings).toEqual({ autoDig = true })
        profile.settings = { autoDig = false }
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        T.expect(profile.settings.autoDig).toBe(false)
        for _, bad in { -5, 0 / 0, math.huge, "bald" } do
            profile.boosts = { coinsUntil = bad }
            Profile.sanitize(profile, NOW)
            T.expect(profile.boosts.coinsUntil).toBe(0)
        end
        profile.boosts = { coinsUntil = NOW + 1800 }
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        T.expect(profile.boosts.coinsUntil).toBe(NOW + 1800)
    end)

    T.it("Pässe, Einstellung und Boost überstehen Speichern und Laden (JSON wie im DataStore)", function()
        local profile: any = Profile.default(NOW)
        profile.passes = { big_tank = true, double_coins = true }
        profile.settings = { autoDig = false }
        profile.boosts = { coinsUntil = NOW + 1234, luckUntil = NOW + 99 } -- luckUntil: Paket 5.1
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        local stored = serde.decode("json", serde.encode("json", profile))
        local loaded: any = Profile.migrate(stored, nil, NOW)
        T.expect(Profile.sanitize(loaded, NOW, { trimLists = false })).toEqual({})
        T.expect(loaded.passes).toEqual({ big_tank = true, double_coins = true })
        T.expect(loaded.settings).toEqual({ autoDig = false })
        T.expect(loaded.boosts).toEqual({ coinsUntil = NOW + 1234, luckUntil = NOW + 99 })
        T.expect(Perks.options(loaded, NOW)).toEqual(Perks.options(profile, NOW))
    end)

    T.it("Neustart über PlayerSession und Fake-Speicher: Besitz wirkt nach dem Laden auf einem neuen Server", function()
        local world = FakeStore.newWorld()
        local clock = { t = NOW }
        local function newManager(name: string): PlayerSession.Manager
            return PlayerSession.new({
                store = FakeStore.newServer(world, name),
                now = function(): number
                    return clock.t
                end,
                kick = function() end,
                log = function() end,
            })
        end
        local a = newManager("A")
        local profile: any = a.load(USER, function(): boolean
            return true
        end)
        profile.passes = Passes.with(profile.passes, "big_tank", true)
        profile.settings = Perks.withAutoDig(profile.settings, false)
        profile.boosts = Perks.extendCoinBoost(profile.boosts, clock.t, BOOST)
        a.release(USER)
        clock.t += 60
        local b = newManager("B")
        local loaded: any = b.load(USER, function(): boolean
            return true
        end)
        T.expect(loaded.passes).toEqual({ big_tank = true })
        T.expect(loaded.settings).toEqual({ autoDig = false })
        T.expect(Perks.capacityMultiplier(loaded)).toBe(Economy.bigTankMultiplier)
        -- Der Boost lief offline weiter (echte Zeit).
        T.expect(Perks.coinBoostSeconds(loaded, clock.t)).toBe(BOOST - 60)
    end)

    T.it("der Sandsturm behält Pässe, Einstellung und Boost", function()
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "passes") ~= nil).toBe(true)
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "settings") ~= nil).toBe(true)
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "boosts") ~= nil).toBe(true)
        local profile: any = Profile.default(NOW)
        profile.nodes = { collect_tool_2 = true, collect_tool_3 = true, collect_tool_4 = true }
        profile.runEarned = BigNum.serialize(BigNum.new(1, 9))
        profile.passes = { auto_dig = true, double_coins = true }
        profile.settings = { autoDig = false }
        profile.boosts = { coinsUntil = NOW + 999 }
        T.expect(Sandstorm.apply(profile, nil, Perks.options(profile, NOW)) ~= nil).toBe(true)
        T.expect(profile.passes).toEqual({ auto_dig = true, double_coins = true })
        T.expect(profile.settings).toEqual({ autoDig = false })
        T.expect(profile.boosts).toEqual({ coinsUntil = NOW + 999 })
        T.expect(profile.nodes.collect_tool_4).toBeNil()
    end)
end)

-- Kaufabwicklung mit PlayerSession und Fake-Speicher (wie tests/purchases.spec.luau, gekürzt).
type Note = { userId: number, kind: string, data: { [string]: any } }
type Server = { manager: PlayerSession.Manager, purchases: Purchases.Purchases, logs: { string }, notes: { Note }, clock: { time: number } }

local function newServer(world: FakeStore.World, name: string, opts: { data: any?, allowDebug: boolean?, noHandler: boolean? }?): Server
    local options = opts or {}
    local clock = { time = NOW }
    local logs: { string } = {}
    local notes: { Note } = {}
    local function now(): number
        return clock.time
    end
    local function wait(seconds: number)
        clock.time += seconds
        coroutine.yield()
    end
    local manager = PlayerSession.new({
        store = FakeStore.newServer(world, name),
        now = now,
        clock = now,
        wait = wait,
        kick = function() end,
        log = function(m: string)
            table.insert(logs, m)
        end,
    })
    local handlers = if options.noHandler then nil else { [Perks.COIN_BOOST_PRODUCT_ID] = Perks.coinBoostHandler(now) }
    local purchases = Purchases.new({
        getProfile = manager.get,
        isSessionActive = manager.isActive,
        saveAndWait = function(userId: number, purchaseId: string, timeoutSeconds: number): boolean
            return manager.saveAndWait(userId, function(saved: any): boolean
                return Purchases.hasReceipt(saved, purchaseId)
            end, timeoutSeconds)
        end,
        now = now,
        clock = now,
        wait = wait,
        log = function(m: string)
            table.insert(logs, m)
        end,
        notify = function(userId: number, kind: string, data: { [string]: any })
            table.insert(notes, { userId = userId, kind = kind, data = data })
        end,
        handlers = handlers :: any,
        allowDebug = options.allowDebug,
        data = if options.data ~= nil then options.data else DATA,
    })
    return { manager = manager, purchases = purchases, logs = logs, notes = notes, clock = clock }
end

type Job = { co: thread, result: string? }

local function resume(job: Job)
    if coroutine.status(job.co) == "dead" then
        return
    end
    local ok, err = coroutine.resume(job.co)
    if not ok then
        error(err, 0)
    end
end

local function start(fn: () -> string): Job
    local job = {} :: Job
    job.co = coroutine.create(function()
        job.result = fn()
    end)
    resume(job)
    return job
end

local function finish(job: Job): string?
    for _ = 1, 10_000 do
        if coroutine.status(job.co) == "dead" then
            return job.result
        end
        resume(job)
    end
    error("Vorgang wurde nicht fertig")
end

local function boostReceipt(purchaseId: string, data: any?): any
    return { PlayerId = USER, ProductId = (data or DATA).Products.byId.coin_boost.productId, PurchaseId = purchaseId }
end

local function startBuy(server: Server, purchaseId: string): Job
    return start(function(): string
        return server.purchases.process(boostReceipt(purchaseId))
    end)
end

local function buy(server: Server, purchaseId: string): string?
    return finish(startBuy(server, purchaseId))
end

local function load(server: Server): any
    return server.manager.load(USER, function(): boolean
        return true
    end)
end

local function countLogs(server: Server, fragment: string): number
    local count = 0
    for _, line in server.logs do
        if string.find(line, fragment, 1, true) then
            count += 1
        end
    end
    return count
end

T.describe("Münz-Boost über ProcessReceipt (4.4)", function()
    T.it("Gutschrift nur über boosts, keine Gems, erst nach dem Speichern PurchaseGranted, Meldung mit Restsekunden", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        local job = startBuy(a, "boost-1")
        T.expect(coroutine.status(job.co) ~= "dead").toBe(true)
        T.expect(profile.boosts.coinsUntil).toBe(NOW + BOOST)
        T.expect(#a.notes).toBe(0)
        T.expect(FakeStore.flushSaves(world)).toBe(1)
        T.expect(finish(job)).toBe("granted")
        T.expect(world.saved[KEY].boosts.coinsUntil).toBe(NOW + BOOST)
        T.expect(profile.gems).toBe(0)
        T.expect(world.saved[KEY].gems).toBe(0)
        T.expect(profile.receipts).toEqual({ "boost-1" })
        T.expect(profile.purchaseLog[1].gems).toBe(0)
        T.expect(profile.purchaseLog[1].productId).toBe("coin_boost")
        T.expect(profile.spent).toEqual({ robux = Products.byId.coin_boost.priceRobux, count = 1 })
        T.expect(#a.notes).toBe(1)
        T.expect(a.notes[1].kind).toBe(Perks.BOOST_BOUGHT_KIND)
        T.expect(a.notes[1].data.productId).toBe("coin_boost")
        T.expect(a.notes[1].data.addedSeconds).toBe(BOOST)
        T.expect(a.notes[1].data.coinBoostSeconds <= BOOST).toBe(true) -- Restzeit zur Zeit der Meldung
        T.expect(a.notes[1].data.coinBoostSeconds > 0).toBe(true)
        -- Nur boosts ändert sich: Pässe und Einstellung bleiben.
        T.expect(profile.passes).toEqual({})
        T.expect(profile.settings).toEqual({ autoDig = true })
    end)

    T.it("derselbe Beleg zweimal (nacheinander und gleichzeitig) verlängert nur einmal", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        T.expect(buy(a, "boost-1")).toBe("granted")
        T.expect(buy(a, "boost-1")).toBe("granted")
        T.expect(profile.boosts.coinsUntil).toBe(NOW + BOOST)
        T.expect(#a.notes).toBe(1)
        -- gleichzeitig: der zweite wartet auf den ersten und bucht nie selbst
        world.delaySaves = true
        local first = startBuy(a, "boost-2")
        local second = startBuy(a, "boost-2")
        resume(second)
        FakeStore.flushSaves(world)
        T.expect(finish(first)).toBe("granted")
        T.expect(finish(second)).toBe("granted")
        T.expect(profile.boosts.coinsUntil).toBe(NOW + 2 * BOOST)
        T.expect(profile.receipts).toEqual({ "boost-1", "boost-2" })
    end)

    T.it("zwei verschiedene Käufe stapeln: alte Endzeit + 30 min; nach Ablauf zählt wieder jetzt + 30 min", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        T.expect(buy(a, "boost-a")).toBe("granted")
        a.clock.time = NOW + 100
        T.expect(buy(a, "boost-b")).toBe("granted")
        T.expect(profile.boosts.coinsUntil).toBe(NOW + 2 * BOOST)
        a.clock.time = NOW + 10 * BOOST
        T.expect(buy(a, "boost-c")).toBe("granted")
        T.expect(profile.boosts.coinsUntil).toBe(a.clock.time + BOOST)
    end)

    T.it("Speichern schlägt fehl: NotProcessedYet, Boost und PurchaseId bleiben zusammen, der nächste Versuch verlängert nicht erneut", function()
        local world = FakeStore.newWorld()
        world.failSaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        T.expect(buy(a, "boost-x")).toBe("notProcessed")
        T.expect(profile.boosts.coinsUntil).toBe(NOW + BOOST)
        T.expect(Purchases.hasReceipt(profile, "boost-x")).toBe(true)
        T.expect(#a.notes).toBe(0)
        T.expect(buy(a, "boost-x")).toBe("notProcessed")
        T.expect(profile.boosts.coinsUntil).toBe(NOW + BOOST)
        world.failSaves = false
        T.expect(buy(a, "boost-x")).toBe("granted")
        T.expect(profile.boosts.coinsUntil).toBe(NOW + BOOST)
        T.expect(world.saved[KEY].boosts.coinsUntil).toBe(NOW + BOOST)
        T.expect(#a.notes).toBe(1)
    end)

    T.it("Absturz vor dem Speichern: der neue Server verlängert genau einmal", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        load(a)
        local job = startBuy(a, "boost-crash")
        FakeStore.crash(world, KEY)
        world.delaySaves = false
        finish(job)
        local b = newServer(world, "B")
        local profile = load(b)
        T.expect(profile.boosts.coinsUntil).toBe(0)
        T.expect(buy(b, "boost-crash")).toBe("granted")
        T.expect(buy(b, "boost-crash")).toBe("granted")
        T.expect(profile.boosts.coinsUntil).toBe(NOW + BOOST)
    end)

    T.it("Profil nicht geladen: NotProcessedYet, keine Gutschrift", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        T.expect(buy(a, "boost-früh")).toBe("notProcessed")
        T.expect(world.saved[KEY]).toBeNil()
    end)

    T.it("ProductId 0 kommt über den Echtpfad nie durch (echte Daten, Platzhalter)", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = REAL_DATA })
        local profile = load(a)
        T.expect(Products.byId.coin_boost.productId).toBe(0)
        local result = finish(start(function(): string
            return a.purchases.process(boostReceipt("boost-0", REAL_DATA))
        end))
        T.expect(result).toBe("notProcessed")
        T.expect(profile.boosts.coinsUntil).toBe(0)
        T.expect(profile.receipts).toEqual({})
        T.expect(countLogs(a, "Platzhalter")).toBe(1)
    end)

    T.it("die neue boosts-Tabelle besteht die Schema-Prüfung unverändert, auch mit weiteren Feldern", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.boosts = { coinsUntil = NOW + 10, luckUntil = 55 }
        T.expect(buy(a, "boost-felder")).toBe("granted")
        T.expect(profile.boosts).toEqual({ coinsUntil = NOW + 10 + BOOST, luckUntil = 55 })
        T.expect(countLogs(a, "Profil-Schema")).toBe(0)
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
    end)

    T.it("coin_boost hat einen Handler: missingHandlers nennt ihn nicht mehr", function()
        local world = FakeStore.newWorld()
        local without = newServer(world, "A", { noHandler = true })
        T.expect(table.find(without.purchases.missingHandlers(), "coin_boost") ~= nil).toBe(true)
        local with = newServer(FakeStore.newWorld(), "B")
        T.expect(table.find(with.purchases.missingHandlers(), "coin_boost")).toBeNil()
        -- Gamepasses brauchen nie einen Handler (sie laufen nicht über ProcessReceipt).
        for _, pass in Passes.list(DATA) do
            T.expect(table.find(with.purchases.missingHandlers(), pass.id)).toBeNil()
        end
    end)

    T.it("ein Gamepass-Beleg über ProcessReceipt wird nie gebucht", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        local result = finish(start(function(): string
            return a.purchases.process({ PlayerId = USER, ProductId = PASS_IDS.big_tank, PurchaseId = "pass-1" })
        end))
        T.expect(result).toBe("notProcessed")
        T.expect(profile.passes).toEqual({})
    end)
end)

T.describe("Studio-Hilfe processDebug (4.4)", function()
    local function debugBuy(server: Server, dataId: string, purchaseId: string): string?
        return finish(start(function(): string
            return server.purchases.processDebug(USER, dataId, purchaseId)
        end))
    end

    T.it("ohne allowDebug gesperrt", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = REAL_DATA })
        local profile = load(a)
        T.expect(debugBuy(a, "coin_boost", "fest1")).toBe("notProcessed")
        T.expect(profile.boosts.coinsUntil).toBe(0)
        T.expect(countLogs(a, "gesperrt")).toBe(1)
    end)

    T.it("coin_boost über die Daten-ID: feste PurchaseId dreimal verlängert einmal, PurchaseId mit Präfix", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = REAL_DATA, allowDebug = true })
        local profile = load(a)
        for _ = 1, 3 do
            T.expect(debugBuy(a, "coin_boost", "fest1")).toBe("granted")
        end
        T.expect(profile.boosts.coinsUntil).toBe(NOW + BOOST)
        T.expect(profile.receipts).toEqual({ Purchases.DEBUG_PREFIX .. "fest1" })
        T.expect(#a.notes).toBe(1)
        T.expect(debugBuy(a, "coin_boost", "fest2")).toBe("granted")
        T.expect(profile.boosts.coinsUntil).toBe(NOW + 2 * BOOST)
        -- Gem-Pakete gehen auch über diesen Weg.
        T.expect(debugBuy(a, "gems_550", "fest3")).toBe("granted")
        T.expect(profile.gems).toBe(550)
    end)

    T.it("Gamepasses, Produkte ohne Handler, Unbekanntes und kaputte PurchaseIds: NotProcessedYet", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = REAL_DATA, allowDebug = true })
        local profile = load(a)
        for _, args in { { "double_coins", "x" }, { "big_tank", "x" }, { "auto_dig", "x" }, { "season_pass", "x" }, { "gibt_es_nicht", "x" }, { "coin_boost", "" }, { "coin_boost", string.rep("y", 200) } } do
            T.expect(debugBuy(a, args[1], args[2])).toBe("notProcessed")
        end
        T.expect(profile.passes).toEqual({})
        T.expect(profile.boosts.coinsUntil).toBe(0)
        T.expect(profile.receipts).toEqual({})
        T.expect(countLogs(a, "unbekanntes Produkt (oder Gamepass)")).toBe(4)
        T.expect(countLogs(a, "kein Handler")).toBe(1)
    end)
end)

T.finish()
