--!strict
-- Paket 0.3: Rate-Limit (Token-Bucket) mit simulierter Uhr.

local T = require("./lib/expect")
local RateLimiter = require("../src/shared/Logic/RateLimiter")

local function newLimiter(): (RateLimiter.RateLimiter, { advance: (seconds: number) -> () })
    local now = 100
    local limiter = RateLimiter.new(function()
        return now
    end)
    return limiter, {
        advance = function(seconds: number)
            now += seconds
        end,
    }
end

T.describe("RateLimiter", function()
    T.it("N Aufrufe pro Sekunde gehen durch, der nächste wird abgelehnt", function()
        local limiter = newLimiter()
        local limit = { calls = 10, per = 1 }
        for _ = 1, 10 do
            T.expect(limiter:allow("1", "SetCollecting", limit)).toBe(true)
        end
        T.expect(limiter:allow("1", "SetCollecting", limit)).toBe(false)
        T.expect(limiter:allow("1", "SetCollecting", limit)).toBe(false)
    end)

    T.it("nach Ablauf der Zeit geht es wieder", function()
        local limiter, clock = newLimiter()
        local limit = { calls = 2, per = 1 }
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(false)
        clock.advance(0.4)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(false)
        clock.advance(0.1) -- 0,5 s = eine Marke
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(false)
        clock.advance(1)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(false)
    end)

    T.it("Bucket füllt sich nie über die Kapazität", function()
        local limiter, clock = newLimiter()
        local limit = { calls = 2, per = 1 }
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
        clock.advance(1000)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(false)
    end)

    T.it("Prestige: 1 pro 5 Sekunden", function()
        local limiter, clock = newLimiter()
        local limit = { calls = 1, per = 5 }
        T.expect(limiter:allow("1", "Prestige", limit)).toBe(true)
        clock.advance(4.9)
        T.expect(limiter:allow("1", "Prestige", limit)).toBe(false)
        clock.advance(0.1)
        T.expect(limiter:allow("1", "Prestige", limit)).toBe(true)
        T.expect(limiter:allow("1", "Prestige", limit)).toBe(false)
    end)

    T.it("Spieler zählen getrennt", function()
        local limiter = newLimiter()
        local limit = { calls = 1, per = 1 }
        T.expect(limiter:allow("1", "TravelZone", limit)).toBe(true)
        T.expect(limiter:allow("1", "TravelZone", limit)).toBe(false)
        T.expect(limiter:allow("2", "TravelZone", limit)).toBe(true)
        T.expect(limiter:allow("2", "TravelZone", limit)).toBe(false)
    end)

    T.it("Remotes zählen getrennt", function()
        local limiter = newLimiter()
        local limit = { calls = 1, per = 1 }
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(false)
        T.expect(limiter:allow("1", "PurchaseNode", limit)).toBe(true)
    end)

    T.it("clear entfernt die Bucket eines Spielers", function()
        local limiter = newLimiter()
        local limit = { calls = 1, per = 1 }
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
        T.expect(limiter:allow("1", "Sell", limit)).toBe(false)
        limiter:clear("1")
        T.expect(limiter:allow("1", "Sell", limit)).toBe(true)
    end)
end)

T.finish()
