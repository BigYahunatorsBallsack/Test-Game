--!strict
-- Paket 4.2: Policy-Cache für ArePaidRandomItemsRestricted (Logic/PolicyCache), fail-closed.

local T = require("./lib/expect")
local PolicyCache = require("../src/shared/Logic/PolicyCache")
local CrateOpen = require("../src/shared/Logic/CrateOpen")
local Profile = require("../src/shared/Logic/Profile")
local DirectShop = require("../src/shared/Logic/DirectShop")

local ATTEMPTS = 3
local RETRY = 2

-- Baut einen Cache mit einer Folge von Antworten. Eine Antwort "throw" wirft, eine Funktion wird
-- aufgerufen (zum Beispiel, um mitten im Laden zu vergessen oder zu warten).
local function harness(answers: { any }): any
    local h: any = { fetches = 0, waits = {}, logs = {}, resolved = {} }
    h.cache = PolicyCache.new({
        fetch = function(_subject: any): any
            h.fetches += 1
            local answer = answers[h.fetches]
            if answer == "throw" then
                error("HTTP 500")
            elseif type(answer) == "function" then
                return answer()
            end
            return answer
        end,
        wait = function(seconds: number)
            table.insert(h.waits, seconds)
        end,
        attempts = ATTEMPTS,
        retrySeconds = RETRY,
        log = function(message: string)
            table.insert(h.logs, message)
        end,
        onResolved = function(userId: number, restricted: boolean?)
            table.insert(h.resolved, { userId = userId, restricted = restricted })
        end,
    })
    return h
end

local function policy(restricted: any): any
    return { ArePaidRandomItemsRestricted = restricted, AllowedExternalLinkReferences = {} }
end

T.describe("PolicyCache", function()
    T.it("vor dem Laden ist die Policy unbekannt und gilt als gesperrt", function()
        local h = harness({})
        T.expect(h.cache.restricted(1)).toBeNil()
        T.expect(h.cache.isAllowed(1)).toBe(false)
    end)

    T.it("Antwort false erlaubt, Antwort true sperrt; ein Versuch, keine Wartezeit", function()
        local h = harness({ policy(false) })
        T.expect(h.cache.load(1, "spieler")).toBe(false)
        T.expect(h.cache.isAllowed(1)).toBe(true)
        T.expect(h.fetches).toBe(1)
        T.expect(h.waits).toEqual({})
        T.expect(h.resolved).toEqual({ { userId = 1, restricted = false } })

        local h2 = harness({ policy(true) })
        T.expect(h2.cache.load(2, "spieler")).toBe(true)
        T.expect(h2.cache.isAllowed(2)).toBe(false)
        T.expect(h2.cache.restricted(2)).toBe(true)
    end)

    T.it("zwei Fehlschläge, dann Erfolg: drei Versuche, zweimal gewartet", function()
        local h = harness({ "throw", "throw", policy(false) })
        T.expect(h.cache.load(1, "spieler")).toBe(false)
        T.expect(h.fetches).toBe(3)
        T.expect(h.waits).toEqual({ RETRY, RETRY })
        T.expect(h.cache.isAllowed(1)).toBe(true)
    end)

    T.it("alle Versuche scheitern: unbekannt, gesperrt, genau ATTEMPTS Versuche, Meldung im Protokoll", function()
        local h = harness({ "throw", "throw", "throw", policy(false) })
        T.expect(h.cache.load(1, "spieler")).toBeNil()
        T.expect(h.fetches).toBe(ATTEMPTS)
        T.expect(#h.waits).toBe(ATTEMPTS - 1)
        T.expect(h.cache.isAllowed(1)).toBe(false)
        T.expect(h.cache.restricted(1)).toBeNil()
        T.expect(#h.logs).toBe(ATTEMPTS + 1)
        T.expect(h.resolved).toEqual({ { userId = 1 } })
    end)

    T.it("ungültige Antworten zählen als gescheitert (kein Feld, Text, Zahl, nil)", function()
        local h = harness({ {}, policy("false"), 0 })
        T.expect(h.cache.load(1, "spieler")).toBeNil()
        T.expect(h.cache.isAllowed(1)).toBe(false)
        local h2 = harness({ nil :: any, policy(0), policy(true) })
        T.expect(h2.cache.load(1, "spieler")).toBe(true)
        T.expect(h2.cache.isAllowed(1)).toBe(false)
    end)

    T.it("verlässt der Spieler das Spiel während des Ladens, wird nichts gemerkt", function()
        local h: any
        h = harness({
            function(): any
                h.cache.forget(1)
                return policy(false)
            end,
        })
        T.expect(h.cache.load(1, "spieler")).toBeNil()
        T.expect(h.cache.isAllowed(1)).toBe(false)
        T.expect(h.resolved).toEqual({})
    end)

    T.it("schneller Rejoin: ein alter, später fertiger Ladevorgang überschreibt den neuen nicht", function()
        -- Ladevorgang A wartet in fetch (Koroutine), der Spieler geht und kommt wieder, B lädt sofort.
        local resumeA: thread? = nil
        local h: any
        h = harness({
            function(): any
                resumeA = coroutine.running()
                coroutine.yield()
                return policy(false) -- A sagt "erlaubt", ist aber veraltet
            end,
            policy(true), -- B sagt "gesperrt"
        })
        local a = coroutine.create(function()
            return h.cache.load(7, "alt")
        end)
        coroutine.resume(a)
        h.cache.forget(7)
        T.expect(h.cache.load(7, "neu")).toBe(true)
        coroutine.resume(resumeA :: thread)
        T.expect(coroutine.status(a)).toBe("dead")
        T.expect(h.cache.restricted(7)).toBe(true)
        T.expect(h.cache.isAllowed(7)).toBe(false)
    end)

    T.it("Spieler zählen getrennt", function()
        local h = harness({ policy(false), policy(true) })
        h.cache.load(1, "a")
        h.cache.load(2, "b")
        T.expect(h.cache.isAllowed(1)).toBe(true)
        T.expect(h.cache.isAllowed(2)).toBe(false)
        h.cache.forget(1)
        T.expect(h.cache.isAllowed(1)).toBe(false)
        T.expect(h.cache.isAllowed(2)).toBe(false)
    end)

    T.it("der gemerkte Wert geht so in CrateOpen: nur bekanntes false öffnet", function()
        local h = harness({ "throw", "throw", "throw" })
        h.cache.load(1, "spieler")
        local profile = Profile.default(0)
        profile.gems = 10_000
        local ctx = { random = function(): number
            return 0
        end, restricted = h.cache.restricted(1), inSeason = false }
        T.expect(CrateOpen.open(profile, "iron", 1, ctx).reason).toBe("restricted")
        T.expect(profile.gems).toBe(10_000)

        local h2 = harness({ policy(false) })
        h2.cache.load(1, "spieler")
        ctx.restricted = h2.cache.restricted(1)
        T.expect(CrateOpen.open(profile, "iron", 1, ctx).ok).toBe(true)
    end)
end)

T.describe("PolicyCache.state (4.6)", function()
    T.it("none vor dem Laden, pending während des Abrufs, danach allowed oder restricted", function()
        local resume: thread? = nil
        local h: any
        local answer = policy(false)
        h = harness({
            function(): any
                resume = coroutine.running()
                coroutine.yield()
                return answer
            end,
        })
        T.expect(h.cache.state(1)).toBe("none")
        local job = coroutine.create(function()
            return h.cache.load(1, "spieler")
        end)
        coroutine.resume(job)
        T.expect(h.cache.state(1)).toBe("pending")
        T.expect(h.cache.isAllowed(1)).toBe(false) -- pending ist gesperrt
        coroutine.resume(resume :: thread)
        T.expect(coroutine.status(job)).toBe("dead")
        T.expect(h.cache.state(1)).toBe("allowed")
        T.expect(h.cache.isAllowed(1)).toBe(true)

        local h2 = harness({ policy(true) })
        h2.cache.load(2, "spieler")
        T.expect(h2.cache.state(2)).toBe("restricted")
    end)

    T.it("zwischen zwei Versuchen bleibt pending; nach allen Fehlschlägen unknown (gesperrt)", function()
        local states = {}
        local cache: any = nil
        -- Zustand während der Wartezeit zwischen den Versuchen merken.
        cache = PolicyCache.new({
            fetch = function(_subject: any): any
                error("HTTP 500")
            end,
            wait = function(_seconds: number)
                table.insert(states, cache.state(5))
            end,
            attempts = ATTEMPTS,
            retrySeconds = RETRY,
        })
        cache.load(5, "spieler")
        T.expect(states).toEqual({ "pending", "pending" })
        T.expect(cache.state(5)).toBe("unknown")
        T.expect(cache.isAllowed(5)).toBe(false)
        T.expect(cache.restricted(5)).toBeNil()
        local h = harness({ "throw", "throw", "throw" })
        h.cache.load(6, "spieler")
        T.expect(h.cache.state(6)).toBe("unknown")
    end)

    T.it("forget setzt auf none; ein alter Abruf nach dem Verlassen schreibt keinen Zustand", function()
        local h: any
        h = harness({
            function(): any
                h.cache.forget(1)
                return policy(true)
            end,
        })
        h.cache.load(1, "spieler")
        T.expect(h.cache.state(1)).toBe("none")
        local h2 = harness({ policy(false) })
        h2.cache.load(3, "spieler")
        h2.cache.forget(3)
        T.expect(h2.cache.state(3)).toBe("none")
    end)

    T.it("schneller Rejoin: der neue Abruf bestimmt den Zustand, der alte überschreibt ihn nicht", function()
        local resumeA: thread? = nil
        local resumeB: thread? = nil
        local h: any
        h = harness({
            function(): any
                resumeA = coroutine.running()
                coroutine.yield()
                return policy(false) -- veraltet
            end,
            function(): any
                resumeB = coroutine.running()
                coroutine.yield()
                return policy(true)
            end,
        })
        local a = coroutine.create(function()
            return h.cache.load(7, "alt")
        end)
        coroutine.resume(a)
        h.cache.forget(7)
        local b = coroutine.create(function()
            return h.cache.load(7, "neu")
        end)
        coroutine.resume(b)
        T.expect(h.cache.state(7)).toBe("pending")
        coroutine.resume(resumeA :: thread) -- alter Abruf endet zuerst
        T.expect(h.cache.state(7)).toBe("pending")
        coroutine.resume(resumeB :: thread)
        T.expect(h.cache.state(7)).toBe("restricted")
    end)

    T.it("der Zustand passt zum Direktkauf: nur restricted und unknown öffnen ihn", function()
        local h = harness({ policy(true), policy(false), "throw", "throw", "throw" })
        h.cache.load(1, "a")
        h.cache.load(2, "b")
        h.cache.load(3, "c")
        T.expect(DirectShop.isOpen(h.cache.state(1))).toBe(true) -- restricted
        T.expect(DirectShop.isOpen(h.cache.state(2))).toBe(false) -- allowed
        T.expect(DirectShop.isOpen(h.cache.state(3))).toBe(true) -- unknown
        T.expect(DirectShop.isOpen(h.cache.state(4))).toBe(false) -- none
    end)
end)

T.finish()
