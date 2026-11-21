--!strict
-- Paket 5.3: Offline-Ertrag des Begleiters (Logic/Offline). Grenze (4 und 12 Stunden), feste Rechnung,
-- keine Funde und keine Boosts, Begleiter nötig, kaputte Zeiten, nur einmal je Zeitraum, nichts
-- halb gebucht, keine Remote, Daten.

local T = require("./lib/expect")
local Offline = require("../src/shared/Logic/Offline")
local PlayerSession = require("../src/shared/Logic/PlayerSession")
local Profile = require("../src/shared/Logic/Profile")
local Collecting = require("../src/shared/Logic/Collecting")
local Equipment = require("../src/shared/Logic/Equipment")
local Wind = require("../src/shared/Logic/Wind")
local BigNum = require("../src/shared/Logic/BigNum")
local Perks = require("../src/shared/Logic/Perks")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local Economy = require("../src/shared/Data/Economy")
local Zones = require("../src/shared/Data/Zones")

local NOW = 1_800_000_000
local HOUR = 3600
local CONFIG = Economy.offline

local function withCompanion(away: number): any
    local profile: any = Profile.default(NOW - away)
    profile.lastSeen = NOW - away
    profile.inventory.companions = { companion_uncommon_1 = 1 }
    profile.equipped.companion = "companion_uncommon_1"
    return profile
end

local function expectedCoins(profile: any, seconds: number, pass: number): number
    local base = Collecting.rateOf(profile) / Equipment.multiplier(profile)
    local price = Collecting.priceOf(profile, Collecting.sandTypeOf(profile), { coinMultiplier = pass })
    return base * seconds * CONFIG.rateFactor * price
end

local function coinsOf(profile: any): number
    return BigNum.toNumber(BigNum.deserialize(profile.coins))
end

local function ratio(actual: number, expected: number): number
    return actual / expected
end

T.describe("Grenze", function()
    T.it("ohne Pass 4 Stunden: genau an der Grenze nicht gekappt, eine Sekunde darüber gekappt", function()
        local atLimit = withCompanion(CONFIG.baseHours * HOUR)
        local report = Offline.apply(atLimit, NOW)
        T.expect(report.ok).toBe(true)
        T.expect(report.seconds).toBe(CONFIG.baseHours * HOUR)
        T.expect(report.capped).toBe(false)
        local over = withCompanion(CONFIG.baseHours * HOUR + 1)
        local overReport = Offline.apply(over, NOW)
        T.expect(overReport.seconds).toBe(CONFIG.baseHours * HOUR)
        T.expect(overReport.capped).toBe(true)
        T.expect(overReport.capSeconds).toBe(CONFIG.baseHours * HOUR)
        -- gleicher Ertrag wie genau an der Grenze
        T.expect(coinsOf(over)).toBe(coinsOf(atLimit))
    end)
    T.it("mit Auto-Dig 12 Stunden", function()
        local profile = withCompanion(100 * HOUR)
        profile.passes = { auto_dig = true }
        local report = Offline.apply(profile, NOW)
        T.expect(report.seconds).toBe(CONFIG.autoDigHours * HOUR)
        T.expect(report.capSeconds).toBe(CONFIG.autoDigHours * HOUR)
        T.expect(report.capped).toBe(true)
        local twelve = withCompanion(12 * HOUR)
        twelve.passes = { auto_dig = true }
        T.expect(Offline.apply(twelve, NOW).capped).toBe(false)
        T.expect(coinsOf(twelve)).toBe(coinsOf(profile))
    end)
    T.it("12 Stunden zahlen dreimal so viel wie 4 Stunden", function()
        local short = withCompanion(4 * HOUR)
        Offline.apply(short, NOW)
        local long = withCompanion(12 * HOUR)
        long.passes = { auto_dig = true }
        Offline.apply(long, NOW)
        T.expect(ratio(coinsOf(long), coinsOf(short))).toBeCloseTo(3, 1e-9)
    end)
end)

T.describe("Rechnung", function()
    T.it("stimmt gegen eine feste Rechnung: Rate, Sekunden, Faktor, Preis", function()
        local profile = withCompanion(2 * HOUR)
        local before = coinsOf(profile)
        local report = Offline.apply(profile, NOW)
        local expected = expectedCoins(profile, 2 * HOUR, 1)
        T.expect(report.ok).toBe(true)
        T.expect(ratio(coinsOf(profile) - before, expected)).toBeCloseTo(1, 1e-9)
        T.expect(ratio(BigNum.toNumber(BigNum.deserialize(report.coins :: any)), expected)).toBeCloseTo(1, 1e-9)
        T.expect(expected > 0).toBe(true)
        -- der Faktor kommt aus den Daten
        T.expect(CONFIG.rateFactor).toBe(0.5)
    end)
    T.it("zwei Zonen: der Preis der Sandsorte der aktuellen Zone gilt", function()
        local results: { number } = {}
        for _, zoneId in { "dunes", "canyon" } do
            local profile = withCompanion(HOUR)
            profile.currentZone = zoneId
            profile.zones = { [zoneId] = true }
            local before = coinsOf(profile)
            Offline.apply(profile, NOW)
            local gained = coinsOf(profile) - before
            T.expect(ratio(gained, expectedCoins(profile, HOUR, 1))).toBeCloseTo(1, 1e-9)
            table.insert(results, gained)
        end
        T.expect(results[2] > results[1]).toBe(true) -- Canyon (roter Sand) zahlt mehr als die Dünen
        T.expect(Zones.byId.canyon ~= nil).toBe(true)
    end)
    T.it("der 2x-Münzen-Pass verdoppelt den Ertrag (dauerhafter Faktor)", function()
        local plain = withCompanion(HOUR)
        Offline.apply(plain, NOW)
        local doubled = withCompanion(HOUR)
        doubled.passes = { double_coins = true }
        Offline.apply(doubled, NOW)
        T.expect(ratio(coinsOf(doubled), coinsOf(plain))).toBeCloseTo(Economy.doubleCoinsMultiplier, 1e-9)
    end)
    T.it("bucht wie Wind.credit: coins und runEarned steigen um denselben Betrag", function()
        local profile = withCompanion(HOUR)
        local mirror: any = table.clone(profile)
        mirror.coins = table.clone(profile.coins)
        mirror.runEarned = table.clone(profile.runEarned)
        local report = Offline.apply(profile, NOW)
        Wind.credit(mirror, BigNum.deserialize(report.coins :: any))
        T.expect(profile.coins).toEqual(mirror.coins)
        T.expect(profile.runEarned).toEqual(mirror.runEarned)
    end)
end)

T.describe("Was nicht zählt", function()
    T.it("die Gutschrift ändert nur coins, runEarned und lastSeen (keine Funde, kein Tank, kein Inventar)", function()
        local profile = withCompanion(3 * HOUR)
        local snapshot: any = {}
        for key, value in profile do
            if key ~= "coins" and key ~= "runEarned" and key ~= "lastSeen" then
                snapshot[key] = if type(value) == "table" then table.clone(value) else value
            end
        end
        Offline.apply(profile, NOW)
        for key, value in snapshot do
            T.expect(profile[key]).toEqual(value)
        end
        T.expect(profile.lastSeen).toBe(NOW)
    end)
    T.it("Münz-Boost, Glücks-Boost und Item-Bonus verändern den Ertrag nicht", function()
        local plain = withCompanion(HOUR)
        Offline.apply(plain, NOW)
        local boosted = withCompanion(HOUR)
        boosted.boosts = { coinsUntil = NOW + 10 * HOUR, luckUntil = NOW + 10 * HOUR }
        boosted.inventory.toolVariants = { toolVariant_uncommon_1 = 1 }
        boosted.equipped.toolVariant = "toolVariant_uncommon_1"
        T.expect(Perks.coinBoostActive(boosted, NOW)).toBe(true)
        T.expect(Equipment.multiplier(boosted) > 1).toBe(true)
        Offline.apply(boosted, NOW)
        T.expect(coinsOf(boosted)).toBe(coinsOf(plain))
    end)
end)

T.describe("Begleiter nötig", function()
    T.it("ohne ausgestatteten Begleiter nichts, lastSeen wird gesetzt", function()
        local profile = withCompanion(3 * HOUR)
        profile.equipped.companion = ""
        local before = table.clone(profile.coins)
        local report = Offline.apply(profile, NOW)
        T.expect(report.ok).toBe(false)
        T.expect(report.reason).toBe("noCompanion")
        T.expect(profile.coins).toEqual(before)
        T.expect(profile.lastSeen).toBe(NOW)
    end)
    T.it("ein ausgestattetes, aber nicht besessenes Item zählt nicht", function()
        local profile = withCompanion(3 * HOUR)
        profile.inventory.companions = {}
        local report = Offline.apply(profile, NOW)
        T.expect(report.reason).toBe("noCompanion")
    end)
end)

T.describe("Zeit", function()
    T.it("unter minSeconds nichts, lastSeen bleibt; ab minSeconds wird gezahlt", function()
        local short = withCompanion(CONFIG.minSeconds - 1)
        local before = table.clone(short.coins)
        local report = Offline.apply(short, NOW)
        T.expect(report.reason).toBe("tooShort")
        T.expect(short.coins).toEqual(before)
        T.expect(short.lastSeen).toBe(NOW - (CONFIG.minSeconds - 1))
        local enough = withCompanion(CONFIG.minSeconds)
        T.expect(Offline.apply(enough, NOW).ok).toBe(true)
    end)
    T.it("fehlende, kaputte und in der Zukunft liegende lastSeen geben nichts und setzen lastSeen neu", function()
        for _, bad in { "x", -5, 0 / 0, math.huge, NOW + 8 * 86400, 0 } do
            local profile = withCompanion(3 * HOUR)
            profile.lastSeen = bad
            local before = table.clone(profile.coins)
            local report = Offline.apply(profile, NOW)
            T.expect(report.ok).toBe(false)
            T.expect(report.reason).toBe("badTime")
            T.expect(profile.coins).toEqual(before)
            T.expect(profile.lastSeen).toBe(NOW)
        end
        local missing = withCompanion(3 * HOUR)
        missing.lastSeen = nil
        T.expect(Offline.apply(missing, NOW).reason).toBe("badTime")
    end)
    T.it("lastSeen kurz in der Zukunft (Server mit vorgehender Uhr): nichts, und lastSeen geht nie zurück", function()
        local profile = withCompanion(3 * HOUR)
        profile.lastSeen = NOW + 600
        local before = table.clone(profile.coins)
        local report = Offline.apply(profile, NOW)
        T.expect(report.reason).toBe("badTime")
        T.expect(profile.coins).toEqual(before)
        T.expect(profile.lastSeen).toBe(NOW + 600)
    end)
    T.it("Hin und Zurück zwischen zwei Uhren zahlt die Differenz nur einmal", function()
        local skew = 900 -- Server F geht 15 Minuten vor
        local profile = withCompanion(3 * HOUR)
        local function leave(clock: number)
            profile.lastSeen = PlayerSession.laterSeen(profile.lastSeen, clock)
        end
        local t = NOW
        T.expect(Offline.apply(profile, t).ok).toBe(true) -- Server C: normale Zahlung
        leave(t) -- verlassen auf C
        t += 60
        local onF = Offline.apply(profile, t + skew) -- Server F betreten (Uhr + 900)
        T.expect(onF.ok).toBe(true) -- einmal die Differenz (900 - 60 s zählen als Abwesenheit)
        leave(t + skew)
        t += 60
        T.expect(Offline.apply(profile, t).ok).toBe(false) -- zurück auf C: lastSeen liegt in der Zukunft
        leave(t)
        T.expect(profile.lastSeen).toBe(NOW + 60 + skew) -- nicht zurückgesetzt
        local coins = table.clone(profile.coins)
        t += 60
        T.expect(Offline.apply(profile, t + skew).ok).toBe(false) -- wieder auf F: nichts mehr, Differenz ist verbraucht
        T.expect(profile.coins).toEqual(coins)
    end)
    T.it("laterSeen: nie zurück, kaputte Werte zählen als 0", function()
        T.expect(PlayerSession.laterSeen(100, 50)).toBe(100)
        T.expect(PlayerSession.laterSeen(50, 100)).toBe(100)
        for _, bad in { "x", -1, 0 / 0, math.huge, 0 } do
            T.expect(PlayerSession.laterSeen(bad, 100)).toBe(100)
        end
    end)
    T.it("kaputte Uhr gibt nichts", function()
        for _, bad in { "x", -1, 0 / 0, math.huge } do
            local profile = withCompanion(3 * HOUR)
            local before = table.clone(profile.coins)
            T.expect(Offline.apply(profile, bad).reason).toBe("badTime")
            T.expect(profile.coins).toEqual(before)
            T.expect(profile.lastSeen).toBe(NOW - 3 * HOUR)
        end
        T.expect(Offline.apply(nil, NOW).reason).toBe("noProfile")
    end)
    T.it("zweimal hintereinander zahlt nur einmal", function()
        local profile = withCompanion(3 * HOUR)
        T.expect(Offline.apply(profile, NOW).ok).toBe(true)
        local after = table.clone(profile.coins)
        local second = Offline.apply(profile, NOW)
        T.expect(second.ok).toBe(false)
        T.expect(second.reason).toBe("tooShort")
        T.expect(profile.coins).toEqual(after)
        -- auch 10 Sekunden später (noch unter minSeconds)
        T.expect(Offline.apply(profile, NOW + 10).reason).toBe("tooShort")
        T.expect(profile.coins).toEqual(after)
    end)
end)

T.describe("Zone", function()
    T.it("eine gesperrte aktuelle Zone zahlt den Preis der Startzone", function()
        local locked = withCompanion(HOUR)
        locked.currentZone = "ruins" -- nicht freigeschaltet
        local home = withCompanion(HOUR)
        Offline.apply(locked, NOW)
        Offline.apply(home, NOW)
        T.expect(coinsOf(locked)).toBe(coinsOf(home))
    end)
    T.it("Münzen sind ganze Zahlen wie beim Verkauf", function()
        local profile = withCompanion(HOUR + 7)
        local report = Offline.apply(profile, NOW)
        local coins = BigNum.deserialize(report.coins :: any)
        T.expect(BigNum.toNumber(coins) % 1).toBe(0)
    end)
end)

T.describe("Fehler im Block", function()
    T.it("ein Fehler beim Rechnen von runEarned bucht nichts und lässt lastSeen stehen", function()
        local profile = withCompanion(3 * HOUR)
        local coins = table.clone(profile.coins)
        profile.runEarned = setmetatable({}, { __index = function() error("kaputt") end }) :: any
        local report = Offline.apply(profile, NOW)
        T.expect(report.ok).toBe(false)
        T.expect(report.reason).toBe("error")
        T.expect(profile.coins).toEqual(coins)
        T.expect(getmetatable(profile.runEarned) ~= nil).toBe(true) -- unverändert
        T.expect(profile.lastSeen).toBe(NOW - 3 * HOUR)
    end)
end)

T.describe("Kein Weg für den Client", function()
    T.it("es gibt keine Remote für den Offline-Ertrag", function()
        for _, def in RemoteSpec.list do
            T.expect(string.find(string.lower(def.name), "offline", 1, true)).toBeNil()
        end
    end)
    T.it("snapshotOf gibt dem Client nur den Bericht", function()
        local profile = withCompanion(HOUR)
        local report = Offline.apply(profile, NOW)
        local snapshot: any = Offline.snapshotOf(report, 3)
        T.expect(snapshot.id).toBe(3)
        T.expect(snapshot.ok).toBe(true)
        T.expect(snapshot.coins).toEqual(report.coins)
        T.expect(Offline.snapshotOf(nil, 1)).toBeNil()
    end)
end)

T.finish()
