--!strict
-- Paket 5.1: Daily Reward (Logic/Daily). Serie nach UTC-Tagen, Start nach der Schaufel und nach dem
-- Sandsturm, Belohnungen aus den Daten (Gems mit maxGems, Münz- und Glücks-Boost), Tag 7 mit Policy
-- (Eisenkiste, Ersatzgegenstand, policyPending), kein halbes Buchen, Zukunftstag, Glücks-Boost auf
-- Funde und nie auf Kisten, Speichern und Laden, Studio-Hilfe und die Remote ClaimDaily.

local T = require("./lib/expect")
local serde = require("@lune/serde")
local Daily = require("../src/shared/Logic/Daily")
local Profile = require("../src/shared/Logic/Profile")
local Perks = require("../src/shared/Logic/Perks")
local FindRoll = require("../src/shared/Logic/FindRoll")
local CrateOpen = require("../src/shared/Logic/CrateOpen")
local CrateRoll = require("../src/shared/Logic/CrateRoll")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local BigNum = require("../src/shared/Logic/BigNum")
local Validate = require("../src/shared/Logic/Validate")
local RateLimiter = require("../src/shared/Logic/RateLimiter")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local Economy = require("../src/shared/Data/Economy")
local Crates = require("../src/shared/Data/Crates")
local CrateItems = require("../src/shared/Data/CrateItems")
local Tools = require("../src/shared/Data/Tools")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")

local DAY = 86400
local TODAY = 20_000 -- ein UTC-Tag (Unix-Tag 20000 = 4. Oktober 2024)
local MIDNIGHT = TODAY * DAY -- 0 Uhr UTC an diesem Tag
local NOON = MIDNIGHT + 12 * 3600
local DAYS = Economy.daily.days
local CYCLE = #DAYS + 1
local FALLBACK = Economy.daily.day7FallbackItemId
local MAX_GEMS = Economy.purchases.maxGems

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

local function constant(value: number): () -> number
    return function(): number
        return value
    end
end

-- Zufall, der nie gerufen werden darf (Tag 7 ohne Kiste würfelt nicht).
local function forbiddenRandom(): number
    error("der Zufall darf hier nicht gerufen werden")
end

-- Unix-Zeit: `offset` Tage nach TODAY, `seconds` nach 0 Uhr UTC.
local function at(offset: number, seconds: number?): number
    return (TODAY + offset) * DAY + (seconds or 12 * 3600)
end

local function ctx(policyState: string?, random: (() -> number)?): any
    return { policyState = policyState, random = random or constant(0) }
end

-- Ein Spieler mit Schaufel (Serie gestartet).
local function started(): any
    local profile = Profile.default(NOON)
    profile.nodes[Economy.daily.startNodeId] = true
    return profile
end

-- Ein Spieler, der gestern Tag `streak` abgeholt hat.
local function afterDay(streak: number, offset: number?): any
    local profile = started()
    profile.daily = { streak = streak, lastDay = TODAY + (offset or 0) - 1 }
    return profile
end

local function itemCount(profile: any, itemId: string): number
    local item = CrateItems.byId[itemId]
    local field = CrateOpen.INVENTORY_FIELDS[item.kind]
    local bucket = profile.inventory[field]
    return if type(bucket) == "table" and type(bucket[itemId]) == "number" then bucket[itemId] else 0
end

-- Wie der DataStore: sanitize, JSON hin und zurück, dann Laden wie PlayerSession.
local function saveAndLoad(profile: any): any
    T.expect(Profile.sanitize(profile, NOON)).toEqual({})
    local stored = serde.decode("json", serde.encode("json", profile))
    local loaded = Profile.migrate(stored, nil, NOON)
    T.expect(Profile.sanitize(loaded, NOON, { trimLists = false })).toEqual({})
    return loaded
end

T.describe("Tag und Uhr (UTC)", function()
    T.it("dayOf = floor(t / 86400); kaputte Uhr ergibt nil", function()
        T.expect(Daily.dayOf(0)).toBe(0)
        T.expect(Daily.dayOf(86399)).toBe(0)
        T.expect(Daily.dayOf(86400)).toBe(1)
        T.expect(Daily.dayOf(MIDNIGHT - 1)).toBe(TODAY - 1)
        T.expect(Daily.dayOf(MIDNIGHT)).toBe(TODAY)
        T.expect(Daily.dayOf(MIDNIGHT + 0.5)).toBe(TODAY)
        for _, bad in { 0 / 0, math.huge, -math.huge, -1 } do
            T.expect(Daily.dayOf(bad)).toBeNil()
        end
        T.expect(Daily.dayOf(("morgen" :: any) :: number)).toBeNil()
    end)

    T.it("Tageswechsel genau um 0 Uhr UTC: 23:59:59 ist noch derselbe Tag, 0:00:00 der nächste", function()
        local profile = started()
        local lastSecond = MIDNIGHT + 86399
        T.expect(Daily.claim(profile, lastSecond, ctx("allowed")).day).toBe(1)
        T.expect(profile.daily).toEqual({ streak = 1, lastDay = TODAY })
        T.expect(Daily.claim(profile, lastSecond, ctx("allowed")).reason).toBe("alreadyClaimed")
        local state = Daily.state(profile, lastSecond)
        T.expect(state.canClaim).toBe(false)
        T.expect(state.secondsLeft).toBe(1)
        -- Eine Sekunde später ist der nächste Tag da und die Serie läuft weiter.
        T.expect(Daily.state(profile, lastSecond + 1).canClaim).toBe(true)
        local result = Daily.claim(profile, lastSecond + 1, ctx("allowed"))
        T.expect(result.ok).toBe(true)
        T.expect(result.day).toBe(2)
        T.expect(profile.daily).toEqual({ streak = 2, lastDay = TODAY + 1 })
    end)

    T.it("Kalendertage zählen, nicht 24 Stunden: 0:00 und am Folgetag 23:59 ist eine Serie", function()
        local profile = started()
        T.expect(Daily.claim(profile, at(0, 0), ctx("allowed")).day).toBe(1)
        T.expect(Daily.claim(profile, at(1, 86399), ctx("allowed")).day).toBe(2) -- fast 48 h später
        T.expect(Daily.claim(profile, at(2, 0), ctx("allowed")).day).toBe(3) -- 1 s später, neuer Tag
    end)
end)

T.describe("Serie", function()
    T.it("Tag 1 bis 7 an aufeinanderfolgenden Tagen, danach wieder Tag 1", function()
        local profile = started()
        for offset = 0, CYCLE + 2 do
            local result = Daily.claim(profile, at(offset), ctx("allowed"))
            local expected = (offset % CYCLE) + 1
            T.expect(result.ok).toBe(true)
            T.expect(result.day).toBe(expected)
            T.expect(profile.daily).toEqual({ streak = expected, lastDay = TODAY + offset })
        end
        T.expect(CYCLE).toBe(7)
    end)

    T.it("ein ausgelassener Tag setzt die Serie auf Tag 1", function()
        local profile = started()
        for offset = 0, 2 do
            Daily.claim(profile, at(offset), ctx("allowed"))
        end
        T.expect(profile.daily.streak).toBe(3)
        local state = Daily.state(profile, at(4))
        T.expect(state.streak).toBe(0)
        T.expect(state.day).toBe(1)
        T.expect(state.canClaim).toBe(true)
        local result = Daily.claim(profile, at(4), ctx("allowed")) -- Tag +3 ausgelassen
        T.expect(result.day).toBe(1)
        T.expect(profile.daily).toEqual({ streak = 1, lastDay = TODAY + 4 })
        -- Auch nach langer Pause und nach Tag 6 (kurz vor der Kiste) beginnt es bei Tag 1.
        local late = afterDay(6, -30)
        T.expect(Daily.claim(late, at(0), ctx("allowed")).day).toBe(1)
    end)

    T.it("zweimal am selben Tag geht nicht: keine zweite Belohnung, Profil unverändert", function()
        local profile = afterDay(1) -- heute ist Tag 2: Gems
        T.expect(DAYS[2].kind).toBe("gems")
        local first = Daily.claim(profile, at(0, 100), ctx("allowed"))
        T.expect(first.ok).toBe(true)
        T.expect(profile.gems).toBe(DAYS[2].amount)
        local before = deepCopy(profile)
        for _, seconds in { 100, 101, 86399 } do
            local again = Daily.claim(profile, at(0, seconds), ctx("allowed"))
            T.expect(again).toEqual({ ok = false, reason = "alreadyClaimed" })
        end
        T.expect(profile).toEqual(before)
        T.expect(profile.gems).toBe(DAYS[2].amount)
    end)

    T.it("nach Tag 7 am selben Tag nichts mehr, am nächsten Tag Tag 1", function()
        local profile = afterDay(CYCLE - 1)
        T.expect(Daily.claim(profile, at(0), ctx("restricted")).day).toBe(CYCLE)
        T.expect(Daily.claim(profile, at(0), ctx("restricted")).reason).toBe("alreadyClaimed")
        T.expect(Daily.claim(profile, at(1), ctx("restricted")).day).toBe(1)
    end)
end)

T.describe("Start nach der Schaufel und nach dem Sandsturm", function()
    T.it("der Startknoten ist die Schaufel aus den Daten", function()
        T.expect(Tools.byId.shovel.nodeId).toBe(Economy.daily.startNodeId)
        T.expect(UpgradeTree.byId[Economy.daily.startNodeId] ~= nil).toBe(true)
    end)

    T.it("vor dem Kauf der Schaufel nichts abholbar, auch mit anderen Knoten; danach Tag 1", function()
        local profile = Profile.default(NOON)
        profile.nodes = { collect_rate_1 = true, tank_1 = true }
        local before = deepCopy(profile)
        T.expect(Daily.claim(profile, NOON, ctx("allowed"))).toEqual({ ok = false, reason = "notStarted" })
        T.expect(profile).toEqual(before)
        T.expect(Daily.state(profile, NOON)).toEqual({ started = false, day = 1, canClaim = false, secondsLeft = 0, streak = 0 })
        T.expect(Daily.isStarted(profile)).toBe(false)
        profile.nodes[Economy.daily.startNodeId] = true -- Schaufel gekauft
        T.expect(Daily.isStarted(profile)).toBe(true)
        T.expect(Daily.state(profile, NOON).canClaim).toBe(true)
        T.expect(Daily.claim(profile, NOON, ctx("allowed")).day).toBe(1)
    end)

    T.it("nach einem echten Sandsturm (Knoten zurückgesetzt) weiter abholbar, die Serie läuft weiter", function()
        local profile = afterDay(2)
        profile.nodes = { collect_tool_2 = true, collect_tool_3 = true, collect_tool_4 = true }
        profile.zones = { dunes = true, oasis = true, canyon = true }
        profile.runEarned = BigNum.serialize(BigNum.new(1, 12))
        local result = Sandstorm.apply(profile)
        T.expect(result ~= nil).toBe(true)
        T.expect(profile.nodes[Economy.daily.startNodeId]).toBeNil() -- Werkzeug zurückgesetzt
        T.expect(profile.prestiges).toBe(1)
        T.expect(profile.daily).toEqual({ streak = 2, lastDay = TODAY - 1 }) -- Sandstorm.KEEP_FIELDS
        T.expect(Daily.state(profile, NOON).started).toBe(true)
        local claim = Daily.claim(profile, NOON, ctx("allowed"))
        T.expect(claim.ok).toBe(true)
        T.expect(claim.day).toBe(3)
    end)

    T.it("prestiges >= 1 gilt als gestartet; kaputte prestiges ohne Knoten nicht", function()
        local profile = Profile.default(NOON)
        profile.prestiges = 1
        T.expect(Daily.isStarted(profile)).toBe(true)
        for _, bad in { 0, 0.5, 0 / 0, math.huge, "3" } do
            profile.prestiges = bad
            T.expect(Daily.isStarted(profile)).toBe(false)
        end
        profile.prestiges = 0
        profile.nodes = { [Economy.daily.startNodeId] = "ja" } -- nur true zählt
        T.expect(Daily.isStarted(profile)).toBe(false)
    end)
end)

T.describe("Belohnungen aus den Daten", function()
    T.it("Tag 1 bis 6 geben genau die Belohnung aus Economy.daily.days", function()
        local profile = started()
        for day = 1, #DAYS do
            local reward = DAYS[day]
            local now = at(day - 1)
            local gemsBefore: number = profile.gems
            local boostsBefore = deepCopy(profile.boosts)
            local result = Daily.claim(profile, now, ctx("allowed"))
            T.expect(result.ok).toBe(true)
            T.expect(result.day).toBe(day)
            T.expect(result.crate).toBeNil()
            if reward.kind == "gems" then
                T.expect(result.reward).toEqual({ kind = "gems", amount = reward.amount })
                T.expect(profile.gems).toBe(gemsBefore + reward.amount)
                T.expect(profile.boosts).toEqual(boostsBefore)
            elseif reward.kind == "coinBoost" then
                T.expect(result.reward).toEqual({ kind = "coinBoost", seconds = reward.seconds })
                T.expect(profile.boosts.coinsUntil).toBe(now + reward.seconds)
                T.expect(profile.boosts.luckUntil).toBe(boostsBefore.luckUntil)
                T.expect(profile.gems).toBe(gemsBefore)
            else
                T.expect(reward.kind).toBe("luck")
                T.expect(result.reward).toEqual({ kind = "luck", seconds = reward.seconds })
                T.expect(profile.boosts.luckUntil).toBe(now + reward.seconds)
                T.expect(profile.boosts.coinsUntil).toBe(boostsBefore.coinsUntil)
                T.expect(profile.gems).toBe(gemsBefore)
            end
        end
        -- Summe der Woche laut Plan: 35 Gems.
        T.expect(profile.gems).toBe(35)
    end)

    T.it("Gems werden bei maxGems gekappt; die Abholung gilt trotzdem und nennt die echte Menge", function()
        local profile = afterDay(1) -- Tag 2: 5 Gems
        profile.gems = MAX_GEMS - 2
        local result = Daily.claim(profile, NOON, ctx("allowed"))
        T.expect(result.ok).toBe(true)
        T.expect(result.reward).toEqual({ kind = "gems", amount = 2, capped = true })
        T.expect(profile.gems).toBe(MAX_GEMS)
        T.expect(profile.daily).toEqual({ streak = 2, lastDay = TODAY })

        local full = afterDay(3) -- Tag 4: 10 Gems
        full.gems = MAX_GEMS
        local capped = Daily.claim(full, NOON, ctx("allowed"))
        T.expect(capped.ok).toBe(true)
        T.expect(capped.reward).toEqual({ kind = "gems", amount = 0, capped = true })
        T.expect(full.gems).toBe(MAX_GEMS)
        T.expect(full.daily).toEqual({ streak = 4, lastDay = TODAY })
    end)

    T.it("Münz-Boost verlängert einen laufenden Boost ab seiner Endzeit, der Glücks-Boost bleibt", function()
        local profile = started() -- Tag 1: Münz-Boost
        profile.boosts = { coinsUntil = NOON + 100, luckUntil = NOON + 7 }
        local result = Daily.claim(profile, NOON, ctx("allowed"))
        T.expect(result.reward).toEqual({ kind = "coinBoost", seconds = DAYS[1].seconds })
        T.expect(profile.boosts).toEqual({ coinsUntil = NOON + 100 + DAYS[1].seconds, luckUntil = NOON + 7 })
        T.expect(Perks.coinBoostSeconds(profile, NOON)).toBe(100 + DAYS[1].seconds)
        T.expect(Perks.coinMultiplier(profile, NOON)).toBe(Economy.coinBoost.multiplier)
    end)

    T.it("Münz-Boost aus der Daily stapelt nie den Faktor: mit Pass und gekauftem Boost höchstens 4-fach", function()
        local profile = started()
        profile.passes = { double_coins = true }
        profile.boosts = Perks.extendCoinBoost(profile.boosts, NOON, Economy.coinBoost.durationSeconds)
        local before = Perks.coinMultiplier(profile, NOON)
        T.expect(before).toBe(Economy.doubleCoinsMultiplier * Economy.coinBoost.multiplier)
        Daily.claim(profile, NOON, ctx("allowed")) -- Tag 1: Münz-Boost
        T.expect(Perks.coinMultiplier(profile, NOON)).toBe(before)
        T.expect(Perks.coinMultiplier(profile, NOON)).toBe(4)
        T.expect(Perks.coinBoostSeconds(profile, NOON)).toBe(Economy.coinBoost.durationSeconds + DAYS[1].seconds)
    end)

    T.it("Glücks-Boost verlängert einen laufenden Boost ab seiner Endzeit, der Münz-Boost bleibt", function()
        local profile = afterDay(4) -- Tag 5: Glücks-Boost
        profile.boosts = { coinsUntil = NOON + 9, luckUntil = NOON + 50 }
        local result = Daily.claim(profile, NOON, ctx("allowed"))
        T.expect(result.reward).toEqual({ kind = "luck", seconds = DAYS[5].seconds })
        T.expect(profile.boosts).toEqual({ coinsUntil = NOON + 9, luckUntil = NOON + 50 + DAYS[5].seconds })
        T.expect(Perks.luckBoostSeconds(profile, NOON)).toBe(50 + DAYS[5].seconds)
        -- Abgelaufen: ab jetzt.
        local expired = afterDay(4)
        expired.boosts = { coinsUntil = 0, luckUntil = NOON - 1 }
        Daily.claim(expired, NOON, ctx("allowed"))
        T.expect(expired.boosts.luckUntil).toBe(NOON + DAYS[5].seconds)
    end)

    T.it("andere Daten, andere Belohnung: nichts ist im Logik-Code fest", function()
        local economy = deepCopy(Economy)
        economy.daily.days[1] = { day = 1, kind = "gems", amount = 7 }
        economy.daily.days[2] = { day = 2, kind = "luck", seconds = 123 }
        local data = { Economy = economy }
        local profile = started()
        T.expect(Daily.claim(profile, at(0), { policyState = "allowed", data = data }).reward).toEqual({ kind = "gems", amount = 7 })
        T.expect(Daily.claim(profile, at(1), { policyState = "allowed", data = data }).reward).toEqual({ kind = "luck", seconds = 123 })
        T.expect(profile.boosts.luckUntil).toBe(at(1) + 123)
        -- Ein anderer Startknoten aus den Daten.
        economy.daily.startNodeId = "tank_1"
        local other = Profile.default(NOON)
        T.expect(Daily.isStarted(other, data)).toBe(false)
        other.nodes.tank_1 = true
        T.expect(Daily.isStarted(other, data)).toBe(true)
    end)
end)

T.describe("Tag 7 und Policy", function()
    T.it("erlaubt: Eisenkiste gratis über CrateOpen.openFree, Antwort im Format von OpenCrate", function()
        local profile = afterDay(CYCLE - 1)
        profile.gems = 40
        local pityBefore = deepCopy(profile.pity)
        local result = Daily.claim(profile, NOON, ctx("allowed", constant(0.3)))
        T.expect(result.ok).toBe(true)
        T.expect(result.day).toBe(CYCLE)
        local crate = result.crate
        T.expect(crate.ok).toBe(true)
        T.expect(crate.crateId).toBe(Economy.daily.day7.crateId)
        T.expect(crate.crateId).toBe("iron")
        T.expect(crate.count).toBe(1)
        T.expect(crate.free).toBe(true)
        T.expect(#crate.results).toBe(1)
        local prize = crate.results[1]
        for _, key in { "itemId", "kind", "rarityId", "name" } do
            T.expect(type(prize[key])).toBe("string")
        end
        T.expect(prize.isNew).toBe(true)
        T.expect(crate.highest).toBe(prize.rarityId)
        T.expect(result.reward).toEqual({ kind = "crate", crateId = "iron", itemId = prize.itemId })
        T.expect(table.find(CrateItems.byId[prize.itemId].crates, "iron") ~= nil).toBe(true)
        T.expect(itemCount(profile, prize.itemId)).toBe(1)
        T.expect(profile.gems).toBe(40) -- gratis
        T.expect(profile.pity).toEqual(pityBefore) -- Eisenkiste ohne Pity
        T.expect(profile.daily).toEqual({ streak = CYCLE, lastDay = TODAY })
    end)

    T.it("erlaubt: derselbe Wurf wie CrateOpen.openFree mit demselben Zufall", function()
        math.randomseed(71)
        for _ = 1, 40 do
            local values = { math.random(), math.random() }
            local function replay(): () -> number
                local index = 0
                return function(): number
                    index += 1
                    return values[index]
                end
            end
            local reference = afterDay(CYCLE - 1)
            local expected = CrateOpen.openFree(reference, "iron", { random = replay(), restricted = false })
            local profile = afterDay(CYCLE - 1)
            local result = Daily.claim(profile, NOON, ctx("allowed", replay()))
            T.expect(result.crate).toEqual(expected)
            T.expect(profile.inventory).toEqual(reference.inventory)
            T.expect(profile.pity).toEqual(reference.pity)
        end
    end)

    T.it("gesperrt oder unbekannt: ein Exemplar des Ersatzgegenstands, kein Zufall, keine Kiste", function()
        for _, policyState in { "restricted", "unknown" } do
            local profile = afterDay(CYCLE - 1)
            local pityBefore = deepCopy(profile.pity)
            local result = Daily.claim(profile, NOON, ctx(policyState, forbiddenRandom))
            T.expect(result.ok).toBe(true)
            T.expect(result.day).toBe(CYCLE)
            T.expect(result.reward).toEqual({ kind = "fixedItem", itemId = FALLBACK, copies = 1 })
            T.expect(result.crate).toBeNil()
            T.expect(itemCount(profile, FALLBACK)).toBe(1)
            T.expect(profile.pity).toEqual(pityBefore)
            T.expect(profile.daily).toEqual({ streak = CYCLE, lastDay = TODAY })
        end
        -- Ein schon vorhandenes Exemplar zählt hoch, andere Items bleiben.
        local owner = afterDay(CYCLE - 1)
        owner.inventory.toolVariants[FALLBACK] = 2
        owner.inventory.skins.skin_common_1 = 1
        local result = Daily.claim(owner, NOON, ctx("restricted", forbiddenRandom))
        T.expect(result.reward.copies).toBe(3)
        T.expect(itemCount(owner, FALLBACK)).toBe(3)
        T.expect(owner.inventory.skins).toEqual({ skin_common_1 = 1 })
        T.expect(FALLBACK).toBe("toolVariant_uncommon_1")
    end)

    T.it("jeder andere Zustand außer pending (none, fehlend, unbekannter Text) gibt den Ersatz (fail-closed)", function()
        for _, policyState in { "none", "irgendwas", "fehlt" } do
            local profile = afterDay(CYCLE - 1)
            local claimCtx: any = { random = forbiddenRandom }
            if policyState ~= "fehlt" then
                claimCtx.policyState = policyState
            end
            local result = Daily.claim(profile, NOON, claimCtx)
            T.expect(result.reward).toEqual({ kind = "fixedItem", itemId = FALLBACK, copies = 1 })
        end
        local noCtx = afterDay(CYCLE - 1)
        T.expect(Daily.claim(noCtx, NOON).reward.kind).toBe("fixedItem")
    end)

    T.it("während der ersten Abfrage (pending): policyPending, nichts gebucht, danach normal", function()
        local profile = afterDay(CYCLE - 1)
        local before = deepCopy(profile)
        T.expect(Daily.claim(profile, NOON, ctx("pending", forbiddenRandom))).toEqual({ ok = false, reason = "policyPending" })
        T.expect(profile).toEqual(before)
        T.expect(Daily.state(profile, NOON).canClaim).toBe(true)
        -- Die Abfrage ist fertig: die Kiste kommt.
        local result = Daily.claim(profile, NOON + 5, ctx("allowed", constant(0)))
        T.expect(result.ok).toBe(true)
        T.expect(result.reward.kind).toBe("crate")
        -- pending stört an den Tagen 1 bis 6 nicht.
        local early = afterDay(1)
        T.expect(Daily.claim(early, NOON, ctx("pending", forbiddenRandom)).ok).toBe(true)
    end)
end)

T.describe("Kein halbes Buchen", function()
    T.it("Fehler im Wurf der Kiste (Zufall wirft, außerhalb [0, 1), fehlt): error, Profil und Serie unverändert", function()
        local calls = 0
        local failing = function(): number
            calls += 1
            if calls == 2 then
                error("Zufall kaputt") -- erst beim Item, nach der Seltenheit
            end
            return 0.1
        end
        -- Ohne Zufall (Feld fehlt) ist es ebenfalls ein Fehler, kein stiller Wurf.
        local randoms: { any } = { failing, constant(1.5), constant(0 / 0), "fehlt" }
        for _, random in randoms do
            local profile = afterDay(CYCLE - 1)
            profile.gems = 12
            local before = deepCopy(profile)
            local claimCtx: any = { policyState = "allowed" }
            if random ~= "fehlt" then
                claimCtx.random = random
            end
            local result = Daily.claim(profile, NOON, claimCtx)
            T.expect(result.ok).toBe(false)
            T.expect(result.reason).toBe("error")
            T.expect(type(result.detail)).toBe("string")
            T.expect(profile).toEqual(before)
        end
    end)

    T.it("Warten im Block (yield im Wurf der Kiste): error, Profil und Serie unverändert", function()
        local yielding = function(): number
            coroutine.yield()
            return 0
        end
        local profile = afterDay(CYCLE - 1)
        local before = deepCopy(profile)
        local result = Daily.claim(profile, NOON, ctx("allowed", yielding))
        T.expect(result.reason).toBe("error")
        T.expect(result.detail).toContain("gewartet")
        T.expect(profile).toEqual(before)
    end)

    T.it("ein Fehler beim Lesen der Daten mitten im Block bucht nichts", function()
        -- Eine Metamethode, die warten will, wirft in Luau ("yield across metamethod"): Fehler, kein Buchen.
        local slowData = setmetatable({}, {
            __index = function(_self: any, _key: any): any
                coroutine.yield()
                return nil
            end,
        })
        local other = afterDay(1)
        local otherBefore = deepCopy(other)
        local slow = Daily.claim(other, NOON, { policyState = "allowed", data = slowData })
        T.expect(slow.reason).toBe("error")
        T.expect(type(slow.detail)).toBe("string")
        T.expect(other).toEqual(otherBefore)
    end)

    T.it("kaputte Daten im Block (Gems, Dauer, Art, Ersatz, Kiste): error, nichts gebucht", function()
        local cases: { { offset: number, policy: string, change: (economy: any) -> () } } = {
            { offset = 1, policy = "allowed", change = function(e: any) e.daily.days[2].amount = -1 end },
            { offset = 1, policy = "allowed", change = function(e: any) e.daily.days[2].amount = 2.5 end },
            { offset = 0, policy = "allowed", change = function(e: any) e.daily.days[1].seconds = 0 end },
            { offset = 0, policy = "allowed", change = function(e: any) e.daily.days[1].seconds = math.huge end },
            { offset = 0, policy = "allowed", change = function(e: any) e.daily.days[1].kind = "coins" end },
            { offset = 0, policy = "allowed", change = function(e: any) e.daily.days[1] = nil end },
            { offset = CYCLE - 1, policy = "restricted", change = function(e: any) e.daily.day7FallbackItemId = "gibt_es_nicht" end },
            { offset = CYCLE - 1, policy = "allowed", change = function(e: any) e.daily.day7.crateId = "diamant" end },
            { offset = 0, policy = "allowed", change = function(e: any) e.daily.days = nil end },
        }
        for index, case in cases do
            local economy = deepCopy(Economy)
            case.change(economy)
            local profile = if case.offset == 0 then started() else afterDay(case.offset)
            profile.boosts = { coinsUntil = NOON + 5, luckUntil = NOON + 6 }
            local before = deepCopy(profile)
            local result = Daily.claim(profile, NOON, { policyState = case.policy, random = constant(0), data = { Economy = economy } })
            if result.reason ~= "error" then
                error(`Fall {index}: erwartet error, erhalten {tostring(result.reason)}`)
            end
            T.expect(profile).toEqual(before)
        end
    end)

    T.it("kaputte Uhr: error, nichts gebucht; kein Profil: noProfile", function()
        for _, bad in { 0 / 0, math.huge, -math.huge, -1 } do
            local profile = started()
            local before = deepCopy(profile)
            T.expect(Daily.claim(profile, bad, ctx("allowed")).reason).toBe("error")
            T.expect(profile).toEqual(before)
            T.expect(Daily.state(profile, bad).canClaim).toBe(false)
        end
        T.expect(Daily.claim(nil, NOON, ctx("allowed"))).toEqual({ ok = false, reason = "noProfile" })
        T.expect(Daily.claim("kaputt", NOON, ctx("allowed")).reason).toBe("noProfile")
    end)

    T.it("jede Ablehnung lässt das Profil unverändert (notStarted, alreadyClaimed, policyPending)", function()
        local cases = {
            { profile = Profile.default(NOON), policy = "allowed", reason = "notStarted" },
            { profile = (function(): any
                local p = started()
                p.daily = { streak = 3, lastDay = TODAY }
                return p
            end)(), policy = "allowed", reason = "alreadyClaimed" },
            { profile = afterDay(CYCLE - 1), policy = "pending", reason = "policyPending" },
        }
        for _, case in cases do
            local before = deepCopy(case.profile)
            local result = Daily.claim(case.profile, NOON, ctx(case.policy, forbiddenRandom))
            T.expect(result).toEqual({ ok = false, reason = case.reason })
            T.expect(case.profile).toEqual(before)
        end
    end)
end)

T.describe("Gespeicherter Tag in der Zukunft", function()
    T.it("lastDay heute oder später zählt wie heute abgeholt: keine zweite Belohnung", function()
        for _, ahead in { 0, 1, 3 } do
            local profile = started()
            profile.daily = { streak = 2, lastDay = TODAY + ahead }
            local before = deepCopy(profile)
            T.expect(Daily.claim(profile, NOON, ctx("allowed")).reason).toBe("alreadyClaimed")
            T.expect(profile).toEqual(before)
            local state = Daily.state(profile, NOON)
            T.expect(state.canClaim).toBe(false)
            T.expect(state.secondsLeft).toBe((TODAY + ahead + 1) * DAY - NOON)
            T.expect(state.day).toBe(3)
        end
    end)

    T.it("geht die Uhr eines Servers nach, gibt es am selben (oder früheren) Tag nichts zweimal", function()
        local profile = started()
        T.expect(Daily.claim(profile, at(0), ctx("allowed")).ok).toBe(true)
        T.expect(Daily.claim(profile, at(-1), ctx("allowed")).reason).toBe("alreadyClaimed")
        T.expect(Daily.claim(profile, at(0, 0), ctx("allowed")).reason).toBe("alreadyClaimed")
        -- Danach geht es am Tag nach dem gespeicherten Tag normal weiter.
        T.expect(Daily.claim(profile, at(1), ctx("allowed")).day).toBe(2)
    end)

    T.it("nach dem Zukunftstag läuft die Serie weiter (lastDay + 1 gilt als Folgetag)", function()
        local profile = started()
        profile.daily = { streak = 2, lastDay = TODAY + 3 }
        local result = Daily.claim(profile, at(4), ctx("allowed"))
        T.expect(result.day).toBe(3)
    end)
end)

T.describe("Glücks-Boost: Fundchance x2, nie Kistenquoten", function()
    T.it("Tag 5 verdoppelt die Fundchance für die Dauer aus den Daten, danach wieder einfach", function()
        T.expect(DAYS[5].kind).toBe("luck")
        local profile = afterDay(4)
        profile.finds = {}
        local base = FindRoll.chancePerSecond(profile, "dunes", NOON, nil, NOON)
        T.expect(Daily.claim(profile, NOON, ctx("allowed")).reward.kind).toBe("luck")
        local seconds = DAYS[5].seconds
        T.expect(FindRoll.chancePerSecond(profile, "dunes", NOON, nil, NOON)).toBeCloseTo(base * 2, 1e-12)
        T.expect(FindRoll.chancePerSecond(profile, "dunes", NOON, nil, NOON + seconds - 1)).toBeCloseTo(base * 2, 1e-12)
        T.expect(FindRoll.chancePerSecond(profile, "dunes", NOON, nil, NOON + seconds)).toBeCloseTo(base, 1e-12)
        T.expect(Economy.luckBoost.multiplier).toBe(2)
    end)

    T.it("Kisten: gleiche Zufallsfolge, gleiche Gewinne und Pity mit und ohne Glücks-Boost", function()
        math.randomseed(505)
        for _, crate in Crates.list do
            for round = 1, 20 do
                local values: { number } = {}
                for i = 1, 2 * Crates.bundle.get do
                    values[i] = math.random()
                end
                local function replay(): () -> number
                    local index = 0
                    return function(): number
                        index += 1
                        return values[index]
                    end
                end
                local plain = started()
                plain.gems = 1_000_000
                plain.coins = BigNum.serialize(BigNum.new(1, 12))
                plain.pity.gold = { sinceEpic = round % 15, sinceLegendary = (round * 7) % 60 }
                local lucky = deepCopy(plain)
                lucky.daily = { streak = 4, lastDay = TODAY - 1 }
                T.expect(Daily.claim(lucky, NOON, ctx("allowed")).reward.kind).toBe("luck")
                T.expect(Perks.luckBoostActive(lucky, NOON)).toBe(true)
                local count = if round % 2 == 0 then Crates.bundle.buy else 1
                local opts = { restricted = false, inSeason = true }
                local a = CrateOpen.open(plain, crate.id, count, { random = replay(), restricted = opts.restricted, inSeason = opts.inSeason })
                local b = CrateOpen.open(lucky, crate.id, count, { random = replay(), restricted = opts.restricted, inSeason = opts.inSeason })
                T.expect(a.ok).toBe(true)
                T.expect(b).toEqual(a)
                T.expect(lucky.pity).toEqual(plain.pity)
                T.expect(lucky.inventory).toEqual(plain.inventory)
            end
        end
        -- Die angezeigten Quoten hängen nur von Kiste und Zähler ab.
        T.expect(CrateRoll.effectiveOdds(Crates.byId.gold, { sinceEpic = 0, sinceLegendary = 0 }).odds).toEqual(Crates.byId.gold.odds)
    end)
end)

T.describe("Zustand für den StateSync", function()
    T.it("Felder je Lage: nicht gestartet, abholbar, abgeholt, verpasst, nach Tag 7", function()
        T.expect(Daily.state(Profile.default(NOON), NOON)).toEqual({ started = false, day = 1, canClaim = false, secondsLeft = 0, streak = 0 })
        local profile = started()
        T.expect(Daily.state(profile, NOON)).toEqual({ started = true, day = 1, canClaim = true, secondsLeft = 0, streak = 0 })
        Daily.claim(profile, NOON, ctx("allowed"))
        T.expect(Daily.state(profile, NOON)).toEqual({ started = true, day = 2, canClaim = false, secondsLeft = 12 * 3600, streak = 1 })
        T.expect(Daily.state(profile, at(1))).toEqual({ started = true, day = 2, canClaim = true, secondsLeft = 0, streak = 1 })
        T.expect(Daily.state(profile, at(2))).toEqual({ started = true, day = 1, canClaim = true, secondsLeft = 0, streak = 0 })
        local week = afterDay(CYCLE - 1)
        Daily.claim(week, NOON, ctx("restricted"))
        T.expect(Daily.state(week, NOON)).toEqual({ started = true, day = 1, canClaim = false, secondsLeft = 12 * 3600, streak = CYCLE })
        T.expect(Daily.state(week, at(1))).toEqual({ started = true, day = 1, canClaim = true, secondsLeft = 0, streak = CYCLE })
    end)

    T.it("secondsLeft zählt bis 0 Uhr UTC, aufgerundet, nie negativ", function()
        local profile = started()
        profile.daily = { streak = 1, lastDay = TODAY }
        T.expect(Daily.state(profile, MIDNIGHT).secondsLeft).toBe(DAY)
        T.expect(Daily.state(profile, MIDNIGHT + 0.25).secondsLeft).toBe(DAY) -- aufgerundet
        T.expect(Daily.state(profile, MIDNIGHT + DAY - 1).secondsLeft).toBe(1)
        T.expect(Daily.state(profile, MIDNIGHT + DAY).secondsLeft).toBe(0)
    end)

    T.it("kaputte Werte im Profil zählen wie nie abgeholt bzw. werden gekappt", function()
        local profile = started()
        for _, daily: any in { "kaputt", { streak = 0 / 0, lastDay = -5 }, { streak = "3", lastDay = "gestern" }, {} } do
            profile.daily = daily
            T.expect(Daily.state(profile, NOON)).toEqual({ started = true, day = 1, canClaim = true, secondsLeft = 0, streak = 0 })
        end
        profile.daily = { streak = 99, lastDay = TODAY - 1 } -- über der Länge: gekappt auf 7, also Tag 1
        T.expect(Daily.state(profile, NOON).day).toBe(1)
        profile.daily = { streak = 2.7, lastDay = TODAY - 0.5 } -- gebrochen: abgerundet
        T.expect(Daily.state(profile, NOON).day).toBe(3)
        local result = Daily.claim(profile, NOON, ctx("allowed"))
        T.expect(result.day).toBe(3)
        T.expect(profile.daily).toEqual({ streak = 3, lastDay = TODAY })
        T.expect(Daily.state(nil, NOON).started).toBe(false)
    end)
end)

T.describe("Speichern und Laden", function()
    T.it("Serie und Boosts überstehen Speichern und Laden; nach dem Neustart keine zweite Abholung", function()
        local profile = afterDay(4) -- Tag 5: Glücks-Boost
        T.expect(Daily.claim(profile, NOON, ctx("allowed")).ok).toBe(true)
        local loaded = saveAndLoad(profile)
        T.expect(loaded.daily).toEqual({ streak = 5, lastDay = TODAY })
        T.expect(loaded.boosts).toEqual(profile.boosts)
        T.expect(Perks.luckBoostSeconds(loaded, NOON)).toBe(DAYS[5].seconds)
        T.expect(Daily.claim(loaded, NOON + 60, ctx("allowed")).reason).toBe("alreadyClaimed")
        T.expect(Daily.claim(loaded, at(1), ctx("allowed")).day).toBe(6)
    end)

    T.it("Tag 7 mit Kiste: Inventar und Serie zusammen gespeichert", function()
        local profile = afterDay(CYCLE - 1)
        local result = Daily.claim(profile, NOON, ctx("allowed", constant(0.5)))
        local loaded = saveAndLoad(profile)
        T.expect(itemCount(loaded, result.reward.itemId)).toBe(1)
        T.expect(loaded.daily).toEqual({ streak = CYCLE, lastDay = TODAY })
    end)
end)

T.describe("Studio-Hilfe DebugDaily", function()
    T.it("parseDebug: reset, yesterday, day:N (0 bis 7); alles andere mit Hinweis", function()
        T.expect(select(1, Daily.parseDebug("reset"))).toBe("reset")
        T.expect(select(1, Daily.parseDebug("yesterday"))).toBe("yesterday")
        local action, streak = Daily.parseDebug("day:6")
        T.expect(action).toBe("day")
        T.expect(streak).toBe(6)
        T.expect(select(2, Daily.parseDebug("day:0"))).toBe(0)
        T.expect(select(2, Daily.parseDebug("day:7"))).toBe(7)
        for _, bad: any in { "day:8", "day:-1", "day:x", "day:", "Reset", "", "bla", 5, true, string.rep("a", 40) } do
            local badAction, _, problem = Daily.parseDebug(bad)
            T.expect(badAction).toBeNil()
            T.expect(type(problem)).toBe("string")
        end
    end)

    T.it("reset: nie abgeholt; yesterday: nächster Tag sofort abholbar, Serie bleibt; withDebug ändert das Profil nicht", function()
        local profile = afterDay(2)
        Daily.claim(profile, NOON, ctx("allowed")) -- Tag 3 heute
        local before = deepCopy(profile)
        local yesterday = Daily.withDebug(profile, "yesterday", nil, NOON)
        T.expect(yesterday).toEqual({ streak = 3, lastDay = TODAY - 1 })
        T.expect(profile).toEqual(before)
        profile.daily = yesterday
        T.expect(Daily.claim(profile, NOON, ctx("allowed")).day).toBe(4)
        profile.daily = Daily.withDebug(profile, "reset", nil, NOON)
        T.expect(profile.daily).toEqual({ streak = 0, lastDay = 0 })
        T.expect(Daily.claim(profile, NOON, ctx("allowed")).day).toBe(1)
    end)

    T.it("day:6 macht Tag 7 sofort abholbar (Kiste oder Ersatz)", function()
        local profile = started()
        local action, streak = Daily.parseDebug("day:6")
        profile.daily = Daily.withDebug(profile, action :: string, streak, NOON)
        T.expect(profile.daily).toEqual({ streak = 6, lastDay = TODAY - 1 })
        local result = Daily.claim(profile, NOON, ctx("restricted", forbiddenRandom))
        T.expect(result.day).toBe(CYCLE)
        T.expect(result.reward.kind).toBe("fixedItem")
    end)
end)

T.describe("Remote ClaimDaily", function()
    T.it("kein Argument, Limit aus RemoteSpec (1 je 2 s)", function()
        local def = RemoteSpec.byName.ClaimDaily
        T.expect(def.kind).toBe("Function")
        T.expect(def.direction).toBe("ClientToServer")
        local schema = def.schema :: { Validate.Rule }
        T.expect(#schema).toBe(0)
        T.expect((Validate.check(schema, {}, 0))).toBe(true)
        T.expect((Validate.check(schema, { 7 }, 1))).toBe(false)
        T.expect((Validate.check(schema, { NOON }, 1))).toBe(false)
        local limit = def.limit :: RateLimiter.Limit
        T.expect(limit).toEqual({ calls = 1, per = 2 })
        local clock = { t = 0 }
        local limiter = RateLimiter.new(function(): number
            return clock.t
        end)
        T.expect(limiter:allow("1", "ClaimDaily", limit)).toBe(true)
        T.expect(limiter:allow("1", "ClaimDaily", limit)).toBe(false)
        clock.t += 2
        T.expect(limiter:allow("1", "ClaimDaily", limit)).toBe(true)
    end)
end)

T.finish()
