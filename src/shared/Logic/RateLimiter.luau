--!strict
-- Token-Bucket pro (Spieler-Schlüssel, Remote). Die Uhr wird eingespeist, damit Tests
-- mit simulierter Zeit laufen. In Roblox wird `os.clock` übergeben.
--
-- Ein Limit `{ calls = N, per = S }` heißt: höchstens N Aufrufe je S Sekunden. Der Bucket
-- fasst N Marken und füllt sich mit N/S Marken pro Sekunde. Abgelehnte Aufrufe kosten nichts.

export type Limit = { calls: number, per: number }
export type Clock = () -> number

type Bucket = { tokens: number, last: number }

local EPSILON = 1e-9

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
    {} :: { clock: Clock, buckets: { [string]: { [string]: Bucket } } },
    RateLimiter
))

function RateLimiter.new(clock: Clock): RateLimiter
    return setmetatable({ clock = clock, buckets = {} }, RateLimiter)
end

-- Gibt true zurück, wenn der Aufruf durchgehen darf (und verbraucht eine Marke).
function RateLimiter.allow(self: RateLimiter, key: string, remote: string, limit: Limit): boolean
    local now = self.clock()
    local perPlayer = self.buckets[key]
    if perPlayer == nil then
        perPlayer = {}
        self.buckets[key] = perPlayer
    end

    local capacity = limit.calls
    local bucket = perPlayer[remote]
    if bucket == nil then
        bucket = { tokens = capacity, last = now }
        perPlayer[remote] = bucket
    else
        local elapsed = math.max(0, now - bucket.last)
        bucket.tokens = math.min(capacity, bucket.tokens + elapsed * capacity / limit.per)
        bucket.last = now
    end

    if bucket.tokens >= 1 - EPSILON then
        bucket.tokens = math.max(0, bucket.tokens - 1)
        return true
    end
    return false
end

-- Entfernt alle Bucket eines Spielers (beim Verlassen des Servers).
function RateLimiter.clear(self: RateLimiter, key: string)
    self.buckets[key] = nil
end

return RateLimiter
