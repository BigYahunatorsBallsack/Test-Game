--!strict
-- Paket 4.5: Angebote im Shop, zuerst das Starterpaket (Logic/Offers, Data/Offers). Auslöser beim
-- ersten Fund ab "Selten", Zustände mit der Server-Uhr, alte Spielstände, Kauf über ProcessReceipt
-- (Logic/Purchases mit dem Handler aus Logic/Offers, PlayerSession und Fake-Speicher), Spielstand
-- Version 7 (Migration, sanitize, Speichern, Laden, Sandsturm) und Reihenfolge der Hinweise. Die
-- DataCheck-Prüfungen der Angebote stehen in tests/data.spec.luau ("Angebote (4.5)").
--
-- Warten heißt hier wie in tests/purchases.spec.luau: die Fake-Uhr rückt vor und die Koroutine gibt die
-- Kontrolle an den Test zurück (coroutine.yield).

local T = require("./lib/expect")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local FakeStore = require("./lib/fakestore")
local Offers = require("../src/shared/Logic/Offers")
local Profile = require("../src/shared/Logic/Profile")
local Migrations = require("../src/shared/Logic/Migrations")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local PlayerSession = require("../src/shared/Logic/PlayerSession")
local Purchases = require("../src/shared/Logic/Purchases")
local Collection = require("../src/shared/Logic/Collection")
local CrateOpen = require("../src/shared/Logic/CrateOpen")
local Equipment = require("../src/shared/Logic/Equipment")
local BigNum = require("../src/shared/Logic/BigNum")
local OffersData = require("../src/shared/Data/Offers")
local Products = require("../src/shared/Data/Products")
local GemPacks = require("../src/shared/Data/GemPacks")
local CrateItems = require("../src/shared/Data/CrateItems")
local Rarities = require("../src/shared/Data/Rarities")
local Finds = require("../src/shared/Data/Finds")
local Economy = require("../src/shared/Data/Economy")

local NOW = 1_700_000_000
local USER = 42
local KEY = PlayerSession.keyFor(USER)
local STARTER = OffersData.byId.starter
local WINDOW = STARTER.windowHours * Offers.SECONDS_PER_HOUR
local MAX_GEMS = Economy.purchases.maxGems
-- Test-IDs: Die echten Daten haben bis zur Anlage im Creator Dashboard nur Platzhalter (0).
local PACK_PRODUCT_BASE = 9_000_000
local OTHER_PRODUCT_BASE = 9_000_100
local PASS_PRODUCT_BASE = 7_000_000

local function deepCopy(value: any): any
    return FakeStore.deepCopy(value)
end

-- Erstes Fundstück der Liste mit dieser Seltenheit.
local function findOf(rarityId: string): any
    for _, find in Finds.list do
        if find.rarityId == rarityId then
            return find
        end
    end
    error(`kein Fundstück mit Seltenheit {rarityId}`)
end

local function offersTable(list: { any }): any
    local byId = {}
    for _, offer in list do
        byId[offer.id] = offer
    end
    return { list = list, byId = byId }
end

-- Daten mit echten (Test-)IDs für Gem-Pakete und Developer Products (Purchases).
local function testData(): any
    local products = { list = {}, byId = {} } :: any
    for index, product in Products.list do
        local copy = table.clone(product)
        copy.productId = if copy.kind == "gamepass" then PASS_PRODUCT_BASE + index else OTHER_PRODUCT_BASE + index
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
-- Quelltext von Logic/Offers für die Prüfung "kein Zufall". Hier oben gelesen, weil fs.readFile wartet
-- (sonst liefe der automatische Abschluss der Testbibliothek zwischendurch).
local OFFERS_SOURCE = fs.readFile("src/shared/Logic/Offers.luau")
local REAL_DATA = { Products = Products, GemPacks = GemPacks, Economy = Economy }

local function starterEntry(profile: any): any
    return profile.offers[Offers.STARTER_OFFER_ID]
end

local function stateAt(profile: any, t: number): (string, number)
    return Offers.stateOf(profile, Offers.STARTER_OFFER_ID, t)
end

-- Wie der Finds-Service: Fund buchen (Collection.record), dann Offers.onFind mit der Server-Uhr und
-- die neue Tabelle ohne Warten zuweisen. Gibt die gestarteten Angebote zurück.
local function bookFind(profile: any, find: any, t: number): { string }
    local recorded = Collection.record(profile, find.id, BigNum.new(1))
    assert(recorded ~= nil, "Fund nicht gebucht")
    local newOffers, started = Offers.onFind(profile, recorded.rarityId, t)
    if newOffers ~= nil then
        profile.offers = newOffers
    end
    return started
end

T.describe("Auslöser: erster Fund ab Selten (4.5)", function()
    T.it("Data/Offers: Starterpaket wie im Plan (starter_pack, ab Selten, 24 h, 300 Gems, feste Items)", function()
        T.expect(STARTER.productId).toBe("starter_pack")
        T.expect(STARTER.trigger).toBe("firstFindFromRarity")
        T.expect(STARTER.minRarityId).toBe("rare")
        T.expect(STARTER.windowHours).toBe(24)
        T.expect(STARTER.gems).toBe(300)
        T.expect(STARTER.items).toEqual({ "toolVariant_rare_1", "companion_uncommon_1" })
        T.expect(CrateItems.byId.toolVariant_rare_1.kind).toBe("toolVariant")
        T.expect(CrateItems.byId.toolVariant_rare_1.rarity).toBe("rare")
        T.expect(CrateItems.byId.companion_uncommon_1.kind).toBe("companion")
        T.expect(Products.byId.starter_pack.priceRobux).toBe(149)
        T.expect(Products.byId.starter_pack.oneTime).toBe(true)
    end)

    T.it("der erste Fund ab Selten startet das Fenster mit der Server-Uhr", function()
        for _, rarity in Rarities.list do
            local profile: any = Profile.default(NOW)
            local started = bookFind(profile, findOf(rarity.id), NOW + 5)
            local expected = Offers.rankOf(rarity.id) :: number >= (Offers.rankOf("rare") :: number)
            if expected then
                T.expect(started).toEqual({ "starter" })
                T.expect(starterEntry(profile)).toEqual({ since = NOW + 5, bought = false })
                T.expect(stateAt(profile, NOW + 5)).toBe("active")
            else
                T.expect(started).toEqual({})
                T.expect(starterEntry(profile)).toEqual({ since = 0, bought = false })
                T.expect(stateAt(profile, NOW + 5)).toBe("hidden")
            end
        end
    end)

    T.it("weitere Funde (auch höhere Seltenheit, auch Duplikate) verschieben das Fenster nicht", function()
        local profile: any = Profile.default(NOW)
        bookFind(profile, findOf("rare"), NOW)
        for index, rarityId in { "rare", "epic", "legendary", "mythic", "common" } do
            T.expect(bookFind(profile, findOf(rarityId), NOW + index * 1000)).toEqual({})
        end
        T.expect(starterEntry(profile).since).toBe(NOW)
        -- auch nach Ablauf startet nichts neu
        T.expect(bookFind(profile, findOf("epic"), NOW + WINDOW + 10)).toEqual({})
        T.expect(stateAt(profile, NOW + WINDOW + 10)).toBe("expired")
    end)

    T.it("Funde unter Selten starten nichts, auch viele", function()
        local profile: any = Profile.default(NOW)
        for i = 1, 50 do
            bookFind(profile, findOf(if i % 2 == 0 then "common" else "uncommon"), NOW + i)
        end
        T.expect(starterEntry(profile)).toEqual({ since = 0, bought = false })
        T.expect(stateAt(profile, NOW + 100)).toBe("hidden")
    end)

    T.it("Kisten-Items starten nichts (Kisten öffnen ändert offers nie, auch bei Mythisch)", function()
        local profile: any = Profile.default(NOW)
        profile.gems = 100_000
        local before = deepCopy(profile.offers)
        local result = CrateOpen.open(profile, "gold", 10, {
            random = function(): number
                return 0.99999 -- höchste Seltenheit
            end,
            restricted = false,
        })
        T.expect(result.ok).toBe(true)
        T.expect(result.highest).toBe("mythic")
        T.expect(profile.offers).toEqual(before)
        T.expect(stateAt(profile, NOW)).toBe("hidden")
        -- Ein Kisten-Item mit derselben ID wie ein Fund gibt es nicht; Kisten-Items stehen nie in finds.
        T.expect(Offers.highestFoundRarity(profile)).toBeNil()
    end)

    T.it("onFind ändert das Profil nicht, unbekannte Seltenheit und kaputte Uhr starten nichts", function()
        local profile: any = Profile.default(NOW)
        local before = deepCopy(profile)
        local newOffers, started = Offers.onFind(profile, "rare", NOW)
        T.expect(profile).toEqual(before)
        T.expect(newOffers ~= nil and newOffers ~= profile.offers).toBe(true)
        T.expect(started).toEqual({ "starter" })
        for _, bad in { "selten", "", 5, nil } do
            T.expect((Offers.onFind(profile, bad, NOW))).toBeNil()
        end
        for _, badClock in { 0, -5, 0 / 0, math.huge, -math.huge } do
            T.expect((Offers.onFind(profile, "rare", badClock))).toBeNil()
        end
        T.expect((Offers.onFind(nil, "rare", NOW))).toBeNil()
    end)

    T.it("gekauftes Angebot startet nie (keine Meldung offerUnlocked nach dem Kauf)", function()
        local profile: any = Profile.default(NOW)
        profile.offers.starter = { since = 0, bought = true }
        T.expect((Offers.onFind(profile, "mythic", NOW))).toBeNil()
        T.expect(stateAt(profile, NOW)).toBe("bought")
    end)

    T.it("kaputte Startzeit zählt als nicht gestartet: der nächste Selten-Fund startet neu", function()
        for _, bad in { 0 / 0, math.huge, -math.huge, -5, 0, "gestern", true, NOW + 10 * WINDOW } do
            local profile: any = Profile.default(NOW)
            profile.offers.starter = { since = bad, bought = false }
            local newOffers, started = Offers.onFind(profile, "rare", NOW)
            T.expect(started).toEqual({ "starter" })
            T.expect((newOffers :: any).starter).toEqual({ since = NOW, bought = false })
        end
        -- Eintrag fehlt oder offers ist kaputt: auch nicht gestartet
        local missing: any = Profile.default(NOW)
        missing.offers = {}
        T.expect(select(2, Offers.onFind(missing, "epic", NOW))).toEqual({ "starter" })
        local broken: any = Profile.default(NOW)
        broken.offers = "kaputt"
        local fixed = Offers.onFind(broken, "epic", NOW)
        T.expect(fixed).toEqual({ starter = { since = NOW, bought = false } })
    end)

    T.it("andere Angebote und unbekannte Einträge bleiben beim Start erhalten (neue Tabelle)", function()
        local profile: any = Profile.default(NOW)
        profile.offers.zukunft = { since = 123, bought = true } -- Angebot eines neueren Servers
        local newOffers = Offers.onFind(profile, "rare", NOW) :: any
        T.expect(newOffers.zukunft).toEqual({ since = 123, bought = true })
        T.expect(newOffers.starter).toEqual({ since = NOW, bought = false })
    end)

    T.it("Auslöser mit Testdaten: minRarityId aus den Daten, mehrere Angebote starten gemeinsam", function()
        local data = {
            Offers = offersTable({
                { id = "a", productId = "x", trigger = "firstFindFromRarity", minRarityId = "epic", windowHours = 1, gems = 1, items = {}, priority = 1 },
                { id = "b", productId = "y", trigger = "firstFindFromRarity", minRarityId = "uncommon", windowHours = 2, gems = 1, items = {}, priority = 2 },
                { id = "c", productId = "z", trigger = "andererAuslöser", minRarityId = "common", windowHours = 2, gems = 1, items = {}, priority = 3 },
            }),
        }
        local profile: any = { offers = {} }
        local first, startedFirst = Offers.onFind(profile, "rare", NOW, data)
        T.expect(startedFirst).toEqual({ "b" })
        profile.offers = first
        local second, startedSecond = Offers.onFind(profile, "legendary", NOW + 50, data)
        T.expect(startedSecond).toEqual({ "a" })
        profile.offers = second
        T.expect(profile.offers).toEqual({ a = { since = NOW + 50, bought = false }, b = { since = NOW, bought = false } })
        T.expect(Offers.snapshot(profile, NOW + 3600, data)).toEqual({
            a = { state = "active", secondsLeft = 50 },
            b = { state = "active", secondsLeft = 3600 },
            c = { state = "hidden", secondsLeft = 0 },
        })
    end)
end)

T.describe("Zustand des Angebots (4.5)", function()
    T.it("verborgen vor dem Auslöser, aktiv bis Start + 24 h, danach abgelaufen", function()
        local profile: any = Profile.default(NOW)
        T.expect({ stateAt(profile, NOW) }).toEqual({ "hidden", 0 })
        profile.offers.starter.since = NOW
        T.expect({ stateAt(profile, NOW) }).toEqual({ "active", WINDOW })
        T.expect({ stateAt(profile, NOW + 1) }).toEqual({ "active", WINDOW - 1 })
        T.expect({ stateAt(profile, NOW + WINDOW - 1) }).toEqual({ "active", 1 })
        T.expect({ stateAt(profile, NOW + WINDOW - 0.25) }).toEqual({ "active", 1 }) -- aktiv heißt mindestens 1 s
        T.expect({ stateAt(profile, NOW + WINDOW) }).toEqual({ "expired", 0 })
        T.expect({ stateAt(profile, NOW + 10 * WINDOW) }).toEqual({ "expired", 0 })
        T.expect(WINDOW).toBe(86400)
    end)

    T.it("nach dem Kauf gekauft, egal wann und auch ohne Start", function()
        local profile: any = Profile.default(NOW)
        profile.offers.starter = { since = NOW, bought = true }
        for _, t in { NOW, NOW + WINDOW, NOW + 100 * WINDOW, 0 / 0 } do
            T.expect({ stateAt(profile, t) }).toEqual({ "bought", 0 })
        end
        profile.offers.starter = { since = 0, bought = true }
        T.expect({ stateAt(profile, NOW) }).toEqual({ "bought", 0 })
    end)

    T.it("kaputte Zeiten zählen als nicht gestartet (verborgen)", function()
        local profile: any = Profile.default(NOW)
        for _, bad in { 0 / 0, math.huge, -math.huge, -1, 0, "x", true, {} :: any, NOW + Offers.FUTURE_TOLERANCE_SECONDS + 1, 1e300 } do
            profile.offers.starter = { since = bad, bought = false }
            T.expect({ stateAt(profile, NOW) }).toEqual({ "hidden", 0 })
        end
        for _, badEntry in { "kaputt", 7, true } do
            profile.offers.starter = badEntry
            T.expect({ stateAt(profile, NOW) }).toEqual({ "hidden", 0 })
        end
        profile.offers = nil
        T.expect({ stateAt(profile, NOW) }).toEqual({ "hidden", 0 })
        T.expect({ Offers.stateOf(nil, "starter", NOW) }).toEqual({ "hidden", 0 })
    end)

    T.it("Start knapp in der Zukunft (andere Server-Uhr) gilt als gerade gestartet, Restzeit höchstens 24 h", function()
        local profile: any = Profile.default(NOW)
        profile.offers.starter = { since = NOW + Offers.FUTURE_TOLERANCE_SECONDS, bought = false }
        T.expect({ stateAt(profile, NOW) }).toEqual({ "active", WINDOW })
        T.expect({ stateAt(profile, NOW + Offers.FUTURE_TOLERANCE_SECONDS + 10) }).toEqual({ "active", WINDOW - 10 })
    end)

    T.it("kaputte Server-Uhr: verborgen; unbekanntes Angebot: verborgen", function()
        local profile: any = Profile.default(NOW)
        profile.offers.starter.since = NOW
        for _, badClock in { 0 / 0, math.huge, -math.huge } do
            T.expect({ stateAt(profile, badClock) }).toEqual({ "hidden", 0 })
        end
        profile.offers.zukunft = { since = NOW, bought = false }
        T.expect({ Offers.stateOf(profile, "zukunft", NOW) }).toEqual({ "hidden", 0 })
    end)

    T.it("snapshot enthält jedes Angebot aus Data/Offers mit Zustand und Restsekunden, keine unbekannten", function()
        local profile: any = Profile.default(NOW)
        profile.offers.zukunft = { since = NOW, bought = false }
        T.expect(Offers.snapshot(profile, NOW)).toEqual({ starter = { state = "hidden", secondsLeft = 0 } })
        profile.offers.starter.since = NOW - 100
        T.expect(Offers.snapshot(profile, NOW)).toEqual({ starter = { state = "active", secondsLeft = WINDOW - 100 } })
        local count = 0
        for _ in Offers.snapshot(profile, NOW) do
            count += 1
        end
        T.expect(count).toBe(#OffersData.list)
    end)

    T.it("die Fensterlänge kommt aus den Daten (windowHours)", function()
        local data = { Offers = offersTable({ { id = "starter", productId = "starter_pack", trigger = "firstFindFromRarity", minRarityId = "rare", windowHours = 0.5, gems = 1, items = {}, priority = 1 } }) }
        local profile: any = { offers = { starter = { since = NOW, bought = false } } }
        T.expect({ Offers.stateOf(profile, "starter", NOW + 1799, data) }).toEqual({ "active", 1 })
        T.expect({ Offers.stateOf(profile, "starter", NOW + 1800, data) }).toEqual({ "expired", 0 })
        T.expect(Offers.windowSeconds({ windowHours = 0 })).toBeNil()
        T.expect(Offers.windowSeconds({ windowHours = 0 / 0 })).toBeNil()
        T.expect(Offers.windowSeconds({ windowHours = math.huge })).toBeNil()
    end)
end)

-- Spielstand der Version 6 (vor Paket 4.5): ohne offers.
local function v6Profile(finds: { [string]: number }?): any
    local profile: any = Profile.default(NOW - 30 * 86400)
    profile.version = 6
    profile.offers = nil
    profile.finds = finds or {}
    return profile
end

T.describe("Alte Spielstände (4.5)", function()
    T.it("vorhandener Selten-Fund: das Fenster startet beim ersten Laden nach dem Update", function()
        local loaded: any = Profile.migrate(v6Profile({ [findOf("common").id] = 4, [findOf("rare").id] = 1 }), nil, NOW)
        T.expect(Profile.sanitize(loaded, NOW, { trimLists = false })).toEqual({})
        T.expect(starterEntry(loaded)).toEqual({ since = 0, bought = false })
        local newOffers, started = Offers.migrateStart(loaded, NOW)
        T.expect(started).toEqual({ "starter" })
        loaded.offers = newOffers
        T.expect({ stateAt(loaded, NOW) }).toEqual({ "active", WINDOW })
        -- zweites Laden (später): nichts verschiebt sich
        T.expect((Offers.migrateStart(loaded, NOW + 3600))).toBeNil()
        T.expect(starterEntry(loaded).since).toBe(NOW)
    end)

    T.it("nur Funde unter Selten, unbekannte Fund-IDs oder kaputte Zähler: kein Start", function()
        local loaded: any = Profile.migrate(v6Profile({ [findOf("common").id] = 9, [findOf("uncommon").id] = 2 }), nil, NOW)
        T.expect((Offers.migrateStart(loaded, NOW))).toBeNil()
        loaded.finds = { gibt_es_nicht_rare = 5, [findOf("epic").id] = 0, [findOf("legendary").id] = 0 / 0 }
        T.expect((Offers.migrateStart(loaded, NOW))).toBeNil()
        loaded.finds = "kaputt"
        T.expect((Offers.migrateStart(loaded, NOW))).toBeNil()
        T.expect(Offers.highestFoundRarity({ finds = { [findOf("rare").id] = 1, [findOf("mythic").id] = 2 } })).toBe("mythic")
    end)

    T.it("schon gekauft oder schon gestartet: migrateStart ändert nichts", function()
        local profile: any = Profile.default(NOW)
        profile.finds = { [findOf("epic").id] = 1 }
        profile.offers.starter = { since = 0, bought = true }
        T.expect((Offers.migrateStart(profile, NOW))).toBeNil()
        profile.offers.starter = { since = NOW - 5, bought = false }
        T.expect((Offers.migrateStart(profile, NOW))).toBeNil()
        profile.offers.starter = { since = NOW - 2 * WINDOW, bought = false } -- abgelaufen bleibt abgelaufen
        T.expect((Offers.migrateStart(profile, NOW))).toBeNil()
        T.expect(stateAt(profile, NOW)).toBe("expired")
    end)

    T.it("über PlayerSession und Fake-Speicher: Fenster ab dem ersten Laden, nach Neustart unverändert, nach 24 h abgelaufen", function()
        local world = FakeStore.newWorld()
        world.saved[KEY] = v6Profile({ [findOf("rare").id] = 1 })
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
        -- So wie der Offers-Service beim Laden (PlayerData.onLoaded).
        local function loadLikeServer(manager: PlayerSession.Manager): any
            local profile: any = manager.load(USER, function(): boolean
                return true
            end)
            local newOffers = Offers.migrateStart(profile, clock.t)
            if newOffers ~= nil then
                profile.offers = newOffers
            end
            return profile
        end
        local a = newManager("A")
        local first = loadLikeServer(a)
        T.expect(first.version).toBe(Migrations.CURRENT_VERSION)
        T.expect({ stateAt(first, clock.t) }).toEqual({ "active", WINDOW })
        a.release(USER)
        T.expect(world.saved[KEY].offers.starter).toEqual({ since = NOW, bought = false })
        clock.t += 3600
        local b = newManager("B")
        local second = loadLikeServer(b)
        T.expect(starterEntry(second).since).toBe(NOW)
        T.expect({ stateAt(second, clock.t) }).toEqual({ "active", WINDOW - 3600 })
        b.release(USER)
        clock.t = NOW + WINDOW
        local c = newManager("C")
        local third = loadLikeServer(c)
        T.expect(stateAt(third, clock.t)).toBe("expired")
        T.expect(starterEntry(third).since).toBe(NOW)
    end)
end)

-- Kaufabwicklung mit PlayerSession und Fake-Speicher (wie tests/passes.spec.luau).
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
    local function log(m: string)
        table.insert(logs, m)
    end
    local manager = PlayerSession.new({
        store = FakeStore.newServer(world, name),
        now = now,
        clock = now,
        wait = wait,
        kick = function() end,
        log = log,
    })
    local handlers = if options.noHandler then nil else { [STARTER.productId] = Offers.offerHandler(STARTER.id, now, log) }
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
        log = log,
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

local function starterReceipt(purchaseId: string, data: any?): any
    return { PlayerId = USER, ProductId = (data or DATA).Products.byId.starter_pack.productId, PurchaseId = purchaseId }
end

local function startBuy(server: Server, purchaseId: string): Job
    return start(function(): string
        return server.purchases.process(starterReceipt(purchaseId))
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

local function copiesOf(profile: any, itemId: string): number
    return Equipment.copiesOf(profile, CrateItems.byId[itemId])
end

T.describe("Kauf starter_pack über ProcessReceipt (4.5)", function()
    T.it("genau 300 Gems, je ein Exemplar der festen Items, Merker gekauft; PurchaseGranted erst nach dem Speichern", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter.since = NOW -- Fenster läuft
        local job = startBuy(a, "starter-1")
        T.expect(coroutine.status(job.co) ~= "dead").toBe(true) -- wartet auf das Speichern
        T.expect(profile.gems).toBe(STARTER.gems)
        T.expect(#a.notes).toBe(0)
        T.expect(FakeStore.flushSaves(world)).toBe(1)
        T.expect(finish(job)).toBe("granted")
        T.expect(profile.gems).toBe(300)
        T.expect(copiesOf(profile, "toolVariant_rare_1")).toBe(1)
        T.expect(copiesOf(profile, "companion_uncommon_1")).toBe(1)
        T.expect(profile.inventory).toEqual({ skins = {}, companions = { companion_uncommon_1 = 1 }, toolVariants = { toolVariant_rare_1 = 1 } })
        T.expect(starterEntry(profile)).toEqual({ since = NOW, bought = true })
        T.expect({ stateAt(profile, NOW) }).toEqual({ "bought", 0 })
        -- gespeichert, gemeinsam mit der PurchaseId
        local saved = world.saved[KEY]
        T.expect(saved.gems).toBe(300)
        T.expect(saved.offers.starter.bought).toBe(true)
        T.expect(saved.inventory.toolVariants.toolVariant_rare_1).toBe(1)
        T.expect(Purchases.hasReceipt(saved, "starter-1")).toBe(true)
        T.expect(profile.purchaseLog[1].productId).toBe("starter_pack")
        T.expect(profile.purchaseLog[1].gems).toBe(300)
        T.expect(profile.spent).toEqual({ robux = 149, count = 1 })
        -- Meldung an den Client nach dem bestätigten Speichern
        T.expect(#a.notes).toBe(1)
        T.expect(a.notes[1].kind).toBe(Offers.OFFER_BOUGHT_KIND)
        T.expect(a.notes[1].data).toEqual({ offerId = "starter", gems = 300, items = { "toolVariant_rare_1", "companion_uncommon_1" } })
        -- nichts ausgerüstet, nichts anderes geändert
        T.expect(profile.equipped).toEqual({ skin = "", companion = "", toolVariant = "" })
        T.expect(countLogs(a, "Profil-Schema")).toBe(0)
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
    end)

    T.it("vorhandene Exemplare zählen hoch, vorhandene Gems bleiben, Ausrüstung bleibt", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.gems = 1234
        profile.inventory = { skins = { skin_common_1 = 3 }, companions = {}, toolVariants = { toolVariant_rare_1 = 2 } }
        profile.equipped = { skin = "skin_common_1", companion = "", toolVariant = "toolVariant_rare_1" }
        profile.itemStars = { toolVariant_rare_1 = 2 }
        profile.offers.starter.since = NOW
        T.expect(buy(a, "starter-2")).toBe("granted")
        T.expect(profile.gems).toBe(1534)
        T.expect(profile.inventory).toEqual({ skins = { skin_common_1 = 3 }, companions = { companion_uncommon_1 = 1 }, toolVariants = { toolVariant_rare_1 = 3 } })
        T.expect(profile.equipped).toEqual({ skin = "skin_common_1", companion = "", toolVariant = "toolVariant_rare_1" })
        T.expect(profile.itemStars).toEqual({ toolVariant_rare_1 = 2 })
    end)

    T.it("derselbe Beleg zweimal (nacheinander und gleichzeitig) bucht nur einmal", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter.since = NOW
        T.expect(buy(a, "starter-dup")).toBe("granted")
        T.expect(buy(a, "starter-dup")).toBe("granted")
        T.expect(profile.gems).toBe(300)
        T.expect(copiesOf(profile, "toolVariant_rare_1")).toBe(1)
        T.expect(#a.notes).toBe(1)
        -- gleichzeitig: der zweite wartet auf den ersten und bucht nie selbst
        world.delaySaves = true
        local first = startBuy(a, "starter-dup2")
        local second = startBuy(a, "starter-dup2")
        resume(second)
        FakeStore.flushSaves(world)
        T.expect(finish(first)).toBe("granted")
        T.expect(finish(second)).toBe("granted")
        -- ein zweiter, anderer Beleg bucht (bezahlt ist bezahlt), aber nur einmal und nur Ersatz-Gems (6.1)
        T.expect(profile.gems).toBe(300 + STARTER.duplicateGems)
        T.expect(copiesOf(profile, "toolVariant_rare_1")).toBe(1)
        T.expect(profile.receipts).toEqual({ "starter-dup", "starter-dup2" })
    end)

    T.it("Gems werden bei maxGems gekappt, Items und Merker kommen trotzdem, Protokoll und Meldung nennen die echte Menge", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.gems = MAX_GEMS - 100
        profile.offers.starter.since = NOW
        T.expect(buy(a, "starter-cap")).toBe("granted")
        T.expect(profile.gems).toBe(MAX_GEMS)
        T.expect(profile.purchaseLog[1].gems).toBe(100)
        T.expect(a.notes[1].data.gems).toBe(100)
        T.expect(countLogs(a, "gekappt")).toBe(1)
        T.expect(copiesOf(profile, "toolVariant_rare_1")).toBe(1)
        T.expect(starterEntry(profile).bought).toBe(true)
        -- schon voll: 0 Gems, der Kauf gilt trotzdem
        local b = newServer(FakeStore.newWorld(), "B")
        local full = load(b)
        full.gems = MAX_GEMS
        full.offers.starter.since = NOW
        T.expect(buy(b, "starter-full")).toBe("granted")
        T.expect(full.gems).toBe(MAX_GEMS)
        T.expect(full.purchaseLog[1].gems).toBe(0)
        T.expect(copiesOf(full, "companion_uncommon_1")).toBe(1)
        T.expect(starterEntry(full).bought).toBe(true)
    end)

    T.it("kein Zufall: der Handler liefert für dasselbe Profil immer dasselbe und ändert die Kopie nicht", function()
        local handler = Offers.offerHandler("starter", function(): number
            return NOW
        end)
        local profile: any = Profile.default(NOW)
        profile.gems = 7
        profile.offers.starter.since = NOW -- Fenster läuft: das Paket
        local before = deepCopy(profile)
        local first = handler(profile, { id = "starter_pack" }) :: any
        T.expect(profile).toEqual(before)
        for _ = 1, 50 do
            local again = handler(deepCopy(profile), { id = "starter_pack" }) :: any
            T.expect(again.changes).toEqual(first.changes)
            T.expect(again.gems).toBe(first.gems)
        end
        T.expect(first.changes.gems).toBe(307)
        T.expect(first.gems).toBe(300)
        T.expect(first.changes.inventory.toolVariants).toEqual({ toolVariant_rare_1 = 1 })
        -- Die Quelle von Logic/Offers enthält keinen Zufall.
        T.expect(string.find(OFFERS_SOURCE, "random", 1, true)).toBeNil()
        T.expect(string.find(OFFERS_SOURCE, "Random", 1, true)).toBeNil()
    end)

    T.it("Handler lehnt nur bei kaputten Daten ab: falsches Produkt, unbekanntes Angebot, unbekanntes Item, kein Profil", function()
        local clock = function(): number
            return NOW
        end
        local logs: { string } = {}
        local handler = Offers.offerHandler("starter", clock, function(m: string)
            table.insert(logs, m)
        end)
        local profile: any = Profile.default(NOW)
        T.expect(handler(profile, { id = "coin_boost" })).toBeNil()
        T.expect(handler(nil, { id = "starter_pack" })).toBeNil()
        T.expect(Offers.offerHandler("gibt_es_nicht", clock)(profile, { id = "starter_pack" })).toBeNil()
        local function row(change: { [string]: any }): any
            local offer: any = { id = "starter", productId = "starter_pack", trigger = "firstFindFromRarity", minRarityId = "rare", windowHours = 24, gems = 300, items = {}, priority = 1, duplicateGems = 300, receiptGraceMinutes = 15 }
            for key, value in change do
                offer[key] = value
            end
            return { Offers = offersTable({ offer }) }
        end
        -- Unbekanntes Item lehnt in jedem Zustand ab, auch wenn der Beleg nur Ersatz-Gems bekäme (verborgen).
        T.expect(handler(profile, { id = "starter_pack" }, row({ items = { "gibt_es_nicht" } }))).toBeNil()
        T.expect(handler(profile, { id = "starter_pack" }, row({ gems = 1.5 }))).toBeNil()
        T.expect(#logs).toBe(3) -- falsches Produkt, unbekanntes Item, ungültige Gems
        -- Ersatzwert, Fenster und Nachfrist kaputt: keine Gutschrift (NotProcessedYet), nie ein Paket.
        for _, bad in { 1.5, -1, 0 / 0, math.huge, "300", false } do
            T.expect(handler(profile, { id = "starter_pack" }, row({ duplicateGems = bad }))).toBeNil()
        end
        local missing = row({})
        missing.Offers.byId.starter.duplicateGems = nil
        T.expect(handler(profile, { id = "starter_pack" }, missing)).toBeNil()
        T.expect(handler(profile, { id = "starter_pack" }, row({ windowHours = 0 }))).toBeNil()
        for _, bad in { -1, 1.5, 0 / 0, math.huge, "15" } do
            T.expect(handler(profile, { id = "starter_pack" }, row({ receiptGraceMinutes = bad }))).toBeNil()
        end
        T.expect(countLogs({ logs = logs } :: any, "duplicateGems ungültig")).toBe(7)
        T.expect(countLogs({ logs = logs } :: any, "receiptGraceMinutes ungültig")).toBe(6)
        -- Kaputte Uhr: keine Gutschrift, Roblox wiederholt den Beleg.
        local active: any = Profile.default(NOW)
        active.offers.starter.since = NOW
        for _, badNow in { 0 / 0, math.huge, -math.huge, 0, -5 } do
            local broken = Offers.offerHandler("starter", function(): number
                return badNow
            end, function(m: string)
                table.insert(logs, m)
            end)
            T.expect(broken(active, { id = "starter_pack" })).toBeNil()
            T.expect(broken(profile, { id = "starter_pack" })).toBeNil()
        end
        T.expect(countLogs({ logs = logs } :: any, "ungültige Uhr")).toBe(10)
        -- Ein Logger, der wirft, stört die Gutschrift nicht.
        local throwing = Offers.offerHandler("starter", clock, function(_m: string)
            error("Logger kaputt")
        end)
        T.expect(throwing(profile, { id = "starter_pack" }) ~= nil).toBe(true)
        T.expect(Offers.starterHandler(clock)(profile, { id = "starter_pack" }) ~= nil).toBe(true)
    end)

    T.it("Speichern schlägt fehl: NotProcessedYet, Gutschrift und PurchaseId bleiben zusammen, der nächste Versuch bucht nicht erneut", function()
        local world = FakeStore.newWorld()
        world.failSaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter.since = NOW
        T.expect(buy(a, "starter-x")).toBe("notProcessed")
        T.expect(profile.gems).toBe(300)
        T.expect(copiesOf(profile, "toolVariant_rare_1")).toBe(1)
        T.expect(starterEntry(profile).bought).toBe(true)
        T.expect(Purchases.hasReceipt(profile, "starter-x")).toBe(true)
        T.expect(#a.notes).toBe(0)
        T.expect(buy(a, "starter-x")).toBe("notProcessed")
        T.expect(profile.gems).toBe(300)
        T.expect(copiesOf(profile, "toolVariant_rare_1")).toBe(1)
        world.failSaves = false
        T.expect(buy(a, "starter-x")).toBe("granted")
        T.expect(profile.gems).toBe(300)
        T.expect(copiesOf(profile, "toolVariant_rare_1")).toBe(1)
        T.expect(world.saved[KEY].gems).toBe(300)
        T.expect(world.saved[KEY].offers.starter.bought).toBe(true)
        T.expect(#a.notes).toBe(1)
    end)

    T.it("Absturz vor dem Speichern: der neue Server bucht genau einmal", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        load(a)
        local job = startBuy(a, "starter-crash")
        FakeStore.crash(world, KEY)
        world.delaySaves = false
        finish(job)
        local b = newServer(world, "B")
        local profile = load(b)
        T.expect(profile.gems).toBe(0)
        T.expect(starterEntry(profile).bought).toBe(false)
        profile.offers.starter.since = NOW -- das Fenster läuft noch (Start war schon gespeichert)
        T.expect(buy(b, "starter-crash")).toBe("granted")
        T.expect(buy(b, "starter-crash")).toBe("granted")
        T.expect(profile.gems).toBe(300)
        T.expect(copiesOf(profile, "toolVariant_rare_1")).toBe(1)
        T.expect(starterEntry(profile).bought).toBe(true)
    end)

    T.it("Profil nicht geladen: NotProcessedYet, keine Gutschrift", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        T.expect(buy(a, "starter-früh")).toBe("notProcessed")
        T.expect(world.saved[KEY]).toBeNil()
    end)

    T.it("gekauft bleibt nach Neustart gekauft (Speichern, Laden auf einem neuen Server, JSON)", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter.since = NOW
        T.expect(buy(a, "starter-rejoin")).toBe("granted")
        a.manager.release(USER)
        local stored = serde.decode("json", serde.encode("json", world.saved[KEY]))
        world.saved[KEY] = stored
        local b = newServer(world, "B")
        local loaded = load(b)
        T.expect({ stateAt(loaded, NOW + 60) }).toEqual({ "bought", 0 })
        T.expect(loaded.gems).toBe(300)
        T.expect(copiesOf(loaded, "toolVariant_rare_1")).toBe(1)
        T.expect((Offers.migrateStart(loaded, NOW + 60))).toBeNil()
    end)

    T.it("ProductId 0 kommt über den Echtpfad nie durch (echte Daten, Platzhalter)", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = REAL_DATA })
        local profile = load(a)
        T.expect(Products.byId.starter_pack.productId).toBe(0)
        local result = finish(start(function(): string
            return a.purchases.process(starterReceipt("starter-0", REAL_DATA))
        end))
        T.expect(result).toBe("notProcessed")
        T.expect(profile.gems).toBe(0)
        T.expect(profile.receipts).toEqual({})
    end)

    T.it("starter_pack hat einen Handler: missingHandlers nennt ihn nicht mehr", function()
        local without = newServer(FakeStore.newWorld(), "A", { noHandler = true })
        T.expect(table.find(without.purchases.missingHandlers(), "starter_pack") ~= nil).toBe(true)
        local with = newServer(FakeStore.newWorld(), "B")
        T.expect(table.find(with.purchases.missingHandlers(), "starter_pack")).toBeNil()
    end)

    T.it("Studio-Hilfe DebugPurchase \"starter_pack\" (processDebug, Weg aus 4.4): feste PurchaseId dreimal bucht einmal", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = REAL_DATA, allowDebug = true })
        local profile = load(a)
        profile.offers.starter.since = NOW -- wie DebugOffer "starter" (ohne Fenster gäbe es nur Ersatz-Gems)
        for _ = 1, 3 do
            T.expect(finish(start(function(): string
                return a.purchases.processDebug(USER, "starter_pack", "fest1")
            end))).toBe("granted")
        end
        T.expect(profile.gems).toBe(300)
        T.expect(copiesOf(profile, "toolVariant_rare_1")).toBe(1)
        T.expect(copiesOf(profile, "companion_uncommon_1")).toBe(1)
        T.expect(starterEntry(profile).bought).toBe(true)
        T.expect(profile.receipts).toEqual({ Purchases.DEBUG_PREFIX .. "fest1" })
        T.expect(#a.notes).toBe(1)
        -- ohne allowDebug gesperrt
        local b = newServer(FakeStore.newWorld(), "B", { data = REAL_DATA })
        local other = load(b)
        T.expect(finish(start(function(): string
            return b.purchases.processDebug(USER, "starter_pack", "fest1")
        end))).toBe("notProcessed")
        T.expect(other.gems).toBe(0)
    end)
end)

-- Exploit-Review 6.1 (mittel): Ein manipulierter Client kann PromptProductPurchase für das Starterpaket
-- selbst aufrufen, beliebig oft und außerhalb des Fensters. Das Paket gibt es nur im Fenster (plus
-- Nachfrist) und nur einmal; jeder andere bezahlte Beleg bekommt nur Ersatz-Gems aus Data/Offers.
local DUPLICATE_GEMS = STARTER.duplicateGems
local GRACE = STARTER.receiptGraceMinutes * Offers.SECONDS_PER_MINUTE

-- Inhalt der Items des Starterpakets im Profil (für "keine Items").
local function starterCopies(profile: any): { number }
    return { copiesOf(profile, "toolVariant_rare_1"), copiesOf(profile, "companion_uncommon_1") }
end

T.describe("Einmalkauf auf dem Server: Ersatz-Gems statt eines zweiten Pakets (6.1)", function()
    T.it("Data/Offers: Ersatz-Gems 300 und Nachfrist 15 min, höchstens der Gem-Gegenwert von 149 Robux", function()
        T.expect(DUPLICATE_GEMS).toBe(300)
        T.expect(STARTER.receiptGraceMinutes).toBe(4320)
        local price = Products.byId.starter_pack.priceRobux
        local bestRate = 0
        for _, pack in GemPacks.list do
            if pack.robux <= price then
                bestRate = math.max(bestRate, pack.gems / pack.robux)
            end
        end
        T.expect(DUPLICATE_GEMS <= price * bestRate).toBe(true) -- 300 <= 304
    end)

    T.it("Erstkauf im Fenster (auch in der letzten Sekunde): volles Paket, Meldung ohne duplicate", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter.since = NOW - WINDOW + 1 -- noch genau 1 s
        T.expect({ stateAt(profile, NOW) }).toEqual({ "active", 1 })
        T.expect(buy(a, "first-in-window")).toBe("granted")
        T.expect(profile.gems).toBe(STARTER.gems)
        T.expect(starterCopies(profile)).toEqual({ 1, 1 })
        T.expect(starterEntry(profile)).toEqual({ since = NOW - WINDOW + 1, bought = true })
        T.expect(a.notes[1].data).toEqual({ offerId = "starter", gems = 300, items = { "toolVariant_rare_1", "companion_uncommon_1" } })
        T.expect(countLogs(a, "Ersatz-Gems")).toBe(0)
        T.expect(countLogs(a, "Nachfrist")).toBe(0)
    end)

    T.it("zweiter Kauf (anderer Beleg): nur Ersatz-Gems, keine Items, Merker bleibt, gespeichert und bestätigt", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter.since = NOW
        T.expect(buy(a, "starter-first")).toBe("granted")
        local inventoryAfterFirst = deepCopy(profile.inventory)
        T.expect(buy(a, "starter-second")).toBe("granted")
        T.expect(profile.gems).toBe(STARTER.gems + DUPLICATE_GEMS)
        T.expect(profile.inventory).toEqual(inventoryAfterFirst)
        T.expect(starterCopies(profile)).toEqual({ 1, 1 })
        T.expect(starterEntry(profile)).toEqual({ since = NOW, bought = true })
        -- Meldung nach dem Speichern: Ersatz, keine Items
        T.expect(#a.notes).toBe(2)
        T.expect(a.notes[2].kind).toBe(Offers.OFFER_BOUGHT_KIND)
        T.expect(a.notes[2].data).toEqual({ offerId = "starter", gems = DUPLICATE_GEMS, items = {}, duplicate = true })
        -- Kaufprotokoll, Ausgaben und Speicher wie bei jedem Kauf
        T.expect(profile.purchaseLog[2].productId).toBe("starter_pack")
        T.expect(profile.purchaseLog[2].gems).toBe(DUPLICATE_GEMS)
        T.expect(profile.spent.count).toBe(2)
        T.expect(Purchases.hasReceipt(world.saved[KEY], "starter-second")).toBe(true)
        T.expect(world.saved[KEY].gems).toBe(STARTER.gems + DUPLICATE_GEMS)
        T.expect(world.saved[KEY].inventory.toolVariants.toolVariant_rare_1).toBe(1)
        T.expect(countLogs(a, "Ersatz-Gems statt des Pakets")).toBe(1)
        T.expect(countLogs(a, "Profil-Schema")).toBe(0)
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
    end)

    T.it("Kauf vor dem Auslöser (verborgen): nur Ersatz-Gems, das Angebot bleibt danach im Fenster kaufbar", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        T.expect(stateAt(profile, NOW)).toBe("hidden")
        T.expect(buy(a, "starter-hidden")).toBe("granted")
        T.expect(profile.gems).toBe(DUPLICATE_GEMS)
        T.expect(starterCopies(profile)).toEqual({ 0, 0 })
        T.expect(starterEntry(profile)).toEqual({ since = 0, bought = false }) -- nicht als gekauft markiert
        T.expect(stateAt(profile, NOW)).toBe("hidden")
        T.expect(a.notes[1].data.duplicate).toBe(true)
        -- Später der echte Auslöser: Fenster startet, der Kauf im Fenster gibt das Paket.
        T.expect(bookFind(profile, findOf("rare"), a.clock.time)).toEqual({ "starter" })
        T.expect(buy(a, "starter-later")).toBe("granted")
        T.expect(profile.gems).toBe(DUPLICATE_GEMS + STARTER.gems)
        T.expect(starterCopies(profile)).toEqual({ 1, 1 })
        T.expect(starterEntry(profile).bought).toBe(true)
    end)

    T.it("Kauf nach Fensterende plus Nachfrist: nur Ersatz-Gems, keine Items, Angebot bleibt abgelaufen", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter.since = NOW - WINDOW - GRACE -- Nachfrist endet genau jetzt
        T.expect(stateAt(profile, NOW)).toBe("expired")
        T.expect(buy(a, "starter-expired")).toBe("granted")
        T.expect(profile.gems).toBe(DUPLICATE_GEMS)
        T.expect(starterCopies(profile)).toEqual({ 0, 0 })
        T.expect(starterEntry(profile)).toEqual({ since = NOW - WINDOW - GRACE, bought = false })
        T.expect(stateAt(profile, NOW)).toBe("expired")
        T.expect(countLogs(a, 'Zustand "expired"')).toBe(1)
        T.expect(Purchases.hasReceipt(world.saved[KEY], "starter-expired")).toBe(true)
    end)

    T.it("Nachfrist: kurz nach Fensterende gibt es noch das Paket (Kaufdialog offen, andere Server-Uhr), danach nicht", function()
        local profile: any = Profile.default(NOW)
        profile.offers.starter.since = NOW
        local function decide(t: number): { any }
            return { Offers.receiptGetsPackage(profile, "starter", t) }
        end
        T.expect(decide(NOW)).toEqual({ true, "active" })
        T.expect(decide(NOW + WINDOW - 1)).toEqual({ true, "active" })
        T.expect(decide(NOW + WINDOW)).toEqual({ true, "expired" })
        T.expect(decide(NOW + WINDOW + GRACE - 1)).toEqual({ true, "expired" })
        T.expect(decide(NOW + WINDOW + GRACE)).toEqual({ false, "expired" })
        T.expect(decide(NOW + 10 * WINDOW)).toEqual({ false, "expired" })
        -- gekauft: nie wieder, auch mitten im Fenster; verborgen und kaputte Uhr: nie
        local bought = deepCopy(profile)
        bought.offers.starter.bought = true
        T.expect({ Offers.receiptGetsPackage(bought, "starter", NOW + 10) }).toEqual({ false, "bought" })
        T.expect({ Offers.receiptGetsPackage(Profile.default(NOW), "starter", NOW) }).toEqual({ false, "hidden" })
        T.expect({ Offers.receiptGetsPackage(profile, "starter", 0 / 0) }).toEqual({ false, "hidden" })
        T.expect({ Offers.receiptGetsPackage(profile, "gibt_es_nicht", NOW) }).toEqual({ false, "hidden" })
        -- Nachfrist 0 aus den Daten: Fensterende ist auch das Ende für Belege
        local noGrace = table.clone(STARTER)
        noGrace.receiptGraceMinutes = 0
        local data = { Offers = offersTable({ noGrace }) }
        T.expect({ Offers.receiptGetsPackage(profile, "starter", NOW + WINDOW - 1, data) }).toEqual({ true, "active" })
        T.expect({ Offers.receiptGetsPackage(profile, "starter", NOW + WINDOW, data) }).toEqual({ false, "expired" })
        -- über ProcessReceipt: eine Minute nach Fensterende, noch nicht gekauft: Paket, Protokoll nennt die Nachfrist
        local a = newServer(FakeStore.newWorld(), "A")
        local late = load(a)
        late.offers.starter.since = NOW - WINDOW - 60
        T.expect(buy(a, "starter-grace")).toBe("granted")
        T.expect(starterCopies(late)).toEqual({ 1, 1 })
        T.expect(late.gems).toBe(STARTER.gems)
        T.expect(starterEntry(late).bought).toBe(true)
        T.expect(countLogs(a, "Nachfrist")).toBe(1)
        T.expect(a.notes[1].data.duplicate).toBeNil()
    end)

    T.it("Kappung bei maxGems: Ersatz-Gems gekappt, bei vollem Stand 0 Gems, der Beleg gilt trotzdem", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter = { since = NOW, bought = true }
        profile.gems = MAX_GEMS - 100
        T.expect(buy(a, "dup-cap")).toBe("granted")
        T.expect(profile.gems).toBe(MAX_GEMS)
        T.expect(profile.purchaseLog[1].gems).toBe(100)
        T.expect(a.notes[1].data).toEqual({ offerId = "starter", gems = 100, items = {}, duplicate = true })
        T.expect(countLogs(a, "gekappt")).toBe(1)
        T.expect(starterCopies(profile)).toEqual({ 0, 0 })
        -- schon voll: 0 Gems, keine Änderung außer Beleg und Protokoll, gespeichert und bestätigt
        T.expect(buy(a, "dup-full")).toBe("granted")
        T.expect(profile.gems).toBe(MAX_GEMS)
        T.expect(profile.purchaseLog[2].gems).toBe(0)
        T.expect(a.notes[2].data).toEqual({ offerId = "starter", gems = 0, items = {}, duplicate = true })
        T.expect(Purchases.hasReceipt(world.saved[KEY], "dup-full")).toBe(true)
        T.expect(starterCopies(profile)).toEqual({ 0, 0 })
        T.expect(starterEntry(profile)).toEqual({ since = NOW, bought = true })
        -- direkt am Handler: kein changes.gems, wenn nichts gutgeschrieben wird
        local handler = Offers.offerHandler("starter", function(): number
            return NOW
        end)
        local prepared = handler(deepCopy(profile), { id = "starter_pack" }) :: any
        T.expect(prepared.changes).toEqual({})
        T.expect(prepared.gems).toBe(0)
    end)

    T.it("derselbe Ersatz-Beleg zweimal (nacheinander und gleichzeitig) bucht nie doppelt", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter = { since = NOW, bought = true }
        T.expect(buy(a, "dup-same")).toBe("granted")
        T.expect(buy(a, "dup-same")).toBe("granted")
        T.expect(profile.gems).toBe(DUPLICATE_GEMS)
        T.expect(#a.notes).toBe(1)
        world.delaySaves = true
        local first = startBuy(a, "dup-same2")
        local second = startBuy(a, "dup-same2")
        resume(second)
        FakeStore.flushSaves(world)
        T.expect(finish(first)).toBe("granted")
        T.expect(finish(second)).toBe("granted")
        T.expect(profile.gems).toBe(2 * DUPLICATE_GEMS)
        T.expect(profile.receipts).toEqual({ "dup-same", "dup-same2" })
        T.expect(starterCopies(profile)).toEqual({ 0, 0 })
        T.expect(#a.notes).toBe(2)
    end)

    T.it("Speichern schlägt beim Ersatz-Beleg fehl: NotProcessedYet, Gems und PurchaseId bleiben zusammen, keine zweite Buchung", function()
        local world = FakeStore.newWorld()
        world.failSaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter = { since = NOW, bought = true }
        T.expect(buy(a, "dup-fail")).toBe("notProcessed")
        T.expect(profile.gems).toBe(DUPLICATE_GEMS)
        T.expect(Purchases.hasReceipt(profile, "dup-fail")).toBe(true)
        T.expect(#a.notes).toBe(0)
        T.expect(buy(a, "dup-fail")).toBe("notProcessed")
        T.expect(profile.gems).toBe(DUPLICATE_GEMS)
        world.failSaves = false
        T.expect(buy(a, "dup-fail")).toBe("granted")
        T.expect(profile.gems).toBe(DUPLICATE_GEMS)
        T.expect(world.saved[KEY].gems).toBe(DUPLICATE_GEMS)
        T.expect(starterCopies(profile)).toEqual({ 0, 0 })
        T.expect(#a.notes).toBe(1)
    end)

    T.it("Profil nicht geladen: NotProcessedYet, kein Ersatz und kein Paket", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        T.expect(buy(a, "dup-noprofile")).toBe("notProcessed")
        T.expect(world.saved[KEY]).toBeNil()
    end)

    T.it("Ausnutzen simuliert: zehn bezahlte Belege im Fenster, gleichzeitig: ein Paket, neunmal Ersatz-Gems", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers.starter.since = NOW
        local jobs: { Job } = {}
        for index = 1, 10 do
            table.insert(jobs, startBuy(a, `exploit-{index}`))
        end
        FakeStore.flushSaves(world)
        for _, job in jobs do
            T.expect(finish(job)).toBe("granted")
        end
        T.expect(starterCopies(profile)).toEqual({ 1, 1 })
        T.expect(profile.gems).toBe(STARTER.gems + 9 * DUPLICATE_GEMS)
        T.expect(#profile.receipts).toBe(10)
        local duplicates = 0
        for _, note in a.notes do
            if note.data.duplicate == true then
                duplicates += 1
            end
        end
        T.expect(duplicates).toBe(9)
        T.expect(world.saved[KEY].inventory.toolVariants.toolVariant_rare_1).toBe(1)
        -- Der Kurs ist nie besser als bei den Gem-Paketen: 9 x 149 Robux für 9 x 300 Gems.
        T.expect(DUPLICATE_GEMS / Products.byId.starter_pack.priceRobux <= GemPacks.byId.gems_100.gems / GemPacks.byId.gems_100.robux).toBe(true)
    end)

    T.it("Absturz vor dem Speichern: der Beleg kommt auf dem neuen Server in der Nachfrist (Paket) oder danach (Ersatz-Gems)", function()
        for _, case in { { delay = GRACE - 60, items = 1, gems = STARTER.gems }, { delay = GRACE + 60, items = 0, gems = DUPLICATE_GEMS } } do
            local world = FakeStore.newWorld()
            world.delaySaves = true
            local a = newServer(world, "A")
            local first = load(a)
            first.offers.starter.since = NOW - WINDOW + 10 -- letzte Sekunden des Fensters
            local job = startBuy(a, "starter-crash-late")
            T.expect(starterCopies(first)).toEqual({ 1, 1 }) -- auf A gebucht, aber nie gespeichert
            FakeStore.crash(world, KEY)
            world.delaySaves = false
            finish(job)
            -- B lädt den alten Stand (Fensterstart war gespeichert) nach dem Fensterende
            local b = newServer(world, "B")
            b.clock.time = NOW + 10 + case.delay
            local profile = load(b)
            profile.offers.starter.since = NOW - WINDOW + 10
            T.expect(buy(b, "starter-crash-late")).toBe("granted")
            T.expect(buy(b, "starter-crash-late")).toBe("granted")
            T.expect(starterCopies(profile)).toEqual({ case.items, case.items })
            T.expect(profile.gems).toBe(case.gems)
        end
    end)

    T.it("Ersatzwert kommt aus den Daten (nicht aus dem Code): Testwert 123, Profil-Kopie unverändert", function()
        local custom = table.clone(STARTER)
        custom.duplicateGems = 123
        local data = { Offers = offersTable({ custom }) }
        local handler = Offers.offerHandler("starter", function(): number
            return NOW
        end)
        local profile: any = Profile.default(NOW)
        profile.gems = 5
        profile.offers.starter = { since = NOW, bought = true }
        local before = deepCopy(profile)
        local prepared = handler(profile, { id = "starter_pack" }, data) :: any
        T.expect(profile).toEqual(before)
        T.expect(prepared.changes).toEqual({ gems = 128 })
        T.expect(prepared.gems).toBe(123)
        local kind, payload = prepared.announce(profile)
        T.expect(kind).toBe(Offers.OFFER_BOUGHT_KIND)
        T.expect(payload).toEqual({ offerId = "starter", gems = 123, items = {}, duplicate = true })
        -- 0 Ersatz-Gems in den Daten: der Beleg gilt, bucht aber nichts
        custom.duplicateGems = 0
        local zero = handler(profile, { id = "starter_pack" }, data) :: any
        T.expect(zero.changes).toEqual({})
        T.expect(zero.gems).toBe(0)
    end)

    T.it("kaputter Eintrag im Profil: der Kauf im Fenster repariert ihn und gilt (Schema-Prüfung von Purchases besteht)", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.offers = { starter = { since = NOW - 5, bought = false }, zukunft = { since = 9, bought = true } }
        T.expect(buy(a, "starter-schema")).toBe("granted")
        T.expect(profile.offers).toEqual({ starter = { since = NOW - 5, bought = true }, zukunft = { since = 9, bought = true } })
        T.expect(countLogs(a, "Profil-Schema")).toBe(0)
    end)
end)

T.describe("Spielstand Version 7 (4.5)", function()
    T.it("Migration 6 auf 7 legt offers mit einem Eintrag je Angebot an", function()
        local migrated, status = Profile.migrate(v6Profile(), nil, NOW)
        local profile: any = migrated
        T.expect(status).toBe("ok")
        T.expect(Migrations.CURRENT_VERSION).toBe(7)
        T.expect(profile.version).toBe(7)
        T.expect(profile.offers).toEqual({ starter = { since = 0, bought = false } })
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        local again = Profile.migrate(deepCopy(profile), nil, NOW)
        T.expect(again).toEqual(profile)
    end)

    T.it("Migration 6 auf 7 legt nur Fehlendes an (Kette läuft erneut: Merker gekauft bleibt)", function()
        local old = v6Profile()
        old.offers = { starter = { since = 55, bought = true } }
        T.expect((Profile.migrate(old, nil, NOW) :: any).offers).toEqual({ starter = { since = 55, bought = true } })
        local partial = v6Profile()
        partial.offers = { starter = { bought = true } }
        T.expect((Profile.migrate(partial, nil, NOW) :: any).offers).toEqual({ starter = { since = 0, bought = true } })
        local broken = v6Profile()
        broken.offers = "kaputt"
        T.expect((Profile.migrate(broken, nil, NOW) :: any).offers).toEqual({ starter = { since = 0, bought = false } })
        -- Version 1 läuft durch alle Schritte bis 7
        local v1: any = v6Profile()
        v1.version = 1
        v1.passes = nil
        v1.settings = nil
        local fromV1: any = Profile.migrate(v1, nil, NOW)
        T.expect(fromV1.version).toBe(7)
        T.expect(fromV1.offers).toEqual({ starter = { since = 0, bought = false } })
    end)

    T.it("sanitize repariert kaputte Werte (since endlich ab 0, bought Boolean, nur Tabellen, keine weiteren Felder)", function()
        local profile: any = Profile.default(NOW)
        for _, bad in { 0 / 0, math.huge, -math.huge, -5, "gestern" } do
            profile.offers = { starter = { since = bad, bought = false } }
            T.expect(#Profile.sanitize(profile, NOW) >= 1).toBe(true)
            T.expect(profile.offers.starter).toEqual({ since = 0, bought = false })
        end
        profile.offers = { starter = { since = NOW, bought = "ja" } }
        Profile.sanitize(profile, NOW)
        T.expect(profile.offers.starter).toEqual({ since = NOW, bought = false })
        profile.offers = { starter = "kaputt" }
        Profile.sanitize(profile, NOW)
        T.expect(profile.offers.starter).toEqual({ since = 0, bought = false })
        profile.offers = "kaputt"
        Profile.sanitize(profile, NOW)
        T.expect(profile.offers).toEqual({ starter = { since = 0, bought = false } })
        profile.offers = { starter = { since = NOW, bought = true, extra = 5 }, [3] = { since = 1, bought = true }, unbekannt = 7 }
        Profile.sanitize(profile, NOW)
        T.expect(profile.offers).toEqual({ starter = { since = NOW, bought = true } })
        -- unbekannte Angebots-ID mit gültigem Eintrag bleibt (Merker eines neueren Servers), wirkt aber nicht
        profile.offers = { starter = { since = 0, bought = false }, zukunft = { since = 4, bought = true } }
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        T.expect(profile.offers.zukunft).toEqual({ since = 4, bought = true })
        -- Startzeit in der Zukunft bleibt stehen (stateOf entscheidet mit der Server-Uhr)
        profile.offers = { starter = { since = NOW + 10 * WINDOW, bought = false } }
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        T.expect(stateAt(profile, NOW)).toBe("hidden")
    end)

    T.it("sauberes Profil: keine Warnung, die Tabelle bleibt dieselbe", function()
        local profile: any = Profile.default(NOW)
        profile.offers.starter = { since = NOW, bought = true }
        local before = profile.offers
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        T.expect(profile.offers == before).toBe(true)
    end)

    T.it("Speichern und Laden (JSON wie im DataStore) behalten offers", function()
        local profile: any = Profile.default(NOW)
        profile.offers.starter = { since = NOW - 77, bought = false }
        local stored = serde.decode("json", serde.encode("json", profile))
        local loaded: any = Profile.migrate(stored, nil, NOW)
        T.expect(Profile.sanitize(loaded, NOW, { trimLists = false })).toEqual({})
        T.expect(loaded.offers).toEqual({ starter = { since = NOW - 77, bought = false } })
        T.expect({ stateAt(loaded, NOW) }).toEqual({ "active", WINDOW - 77 })
    end)

    T.it("der Sandsturm behält offers (Fenster und Merker), auch ein laufendes Fenster", function()
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "offers") ~= nil).toBe(true)
        T.expect(table.find(Sandstorm.RESET_FIELDS, "offers")).toBeNil()
        local profile: any = Profile.default(NOW)
        profile.nodes = { collect_tool_2 = true, collect_tool_3 = true, collect_tool_4 = true }
        profile.runEarned = BigNum.serialize(BigNum.new(1, 9))
        profile.offers.starter = { since = NOW - 10, bought = false }
        T.expect(Sandstorm.apply(profile) ~= nil).toBe(true)
        T.expect(profile.offers).toEqual({ starter = { since = NOW - 10, bought = false } })
        T.expect(profile.nodes.collect_tool_4).toBeNil()
        -- Funde bleiben ebenfalls: ein Selten-Fund nach dem Sturm startet nichts neu
        T.expect((Offers.onFind(profile, "rare", NOW + 5))).toBeNil()
    end)
end)

local function ctx(overrides: { [string]: any }?): Offers.HintContext
    local base: any = { revealBusy = false, tutorialActive = false, windowOpen = false, shownThisSession = {} }
    for key, value in overrides or {} do
        base[key] = value
    end
    return base
end

local ACTIVE = { starter = { state = "active", secondsLeft = 3600 } }

T.describe("Reihenfolge der Hinweise (4.5)", function()
    T.it("aktives Angebot ohne Hindernis: Hinweis für starter", function()
        T.expect(Offers.nextHint(ACTIVE, ctx())).toBe("starter")
    end)

    T.it("wartet, solange ein Reveal läuft oder wartet, das Tutorial läuft, ein Fenster offen ist oder ein Hinweis sichtbar ist", function()
        T.expect(Offers.nextHint(ACTIVE, ctx({ revealBusy = true }))).toBeNil()
        T.expect(Offers.nextHint(ACTIVE, ctx({ tutorialActive = true }))).toBeNil()
        T.expect(Offers.nextHint(ACTIVE, ctx({ windowOpen = true }))).toBeNil()
        T.expect(Offers.nextHint(ACTIVE, ctx({ hintVisible = true }))).toBeNil()
        -- fehlende Pflichtfelder: lieber warten (nie zu früh)
        T.expect(Offers.nextHint(ACTIVE, { shownThisSession = {} } :: any)).toBeNil()
        T.expect(Offers.nextHint(ACTIVE, nil :: any)).toBeNil()
    end)

    T.it("je Angebot höchstens ein Hinweis pro Sitzung", function()
        T.expect(Offers.nextHint(ACTIVE, ctx({ shownThisSession = { starter = true } }))).toBeNil()
    end)

    T.it("nur aktive Angebote mit Restzeit, unbekannte zählen nicht", function()
        for _, view in { { state = "hidden", secondsLeft = 0 }, { state = "expired", secondsLeft = 0 }, { state = "bought", secondsLeft = 0 }, { state = "active", secondsLeft = 0 }, { state = "active" }, "kaputt" } do
            T.expect(Offers.nextHint({ starter = view }, ctx())).toBeNil()
        end
        T.expect(Offers.nextHint({ zukunft = { state = "active", secondsLeft = 10 } }, ctx())).toBeNil()
        T.expect(Offers.nextHint(nil, ctx())).toBeNil()
        T.expect(Offers.nextHint({}, ctx())).toBeNil()
    end)

    T.it("mehrere Angebote: kleinere priority zuerst, bei Gleichstand die kleinere ID, nie zwei gleichzeitig", function()
        local data = {
            Offers = offersTable({
                { id = "a", productId = "x", trigger = "firstFindFromRarity", minRarityId = "rare", windowHours = 1, gems = 1, items = {}, priority = 2 },
                { id = "c", productId = "z", trigger = "firstFindFromRarity", minRarityId = "rare", windowHours = 1, gems = 1, items = {}, priority = 1 },
                { id = "b", productId = "y", trigger = "firstFindFromRarity", minRarityId = "rare", windowHours = 1, gems = 1, items = {}, priority = 1 },
            }),
        }
        local state = {
            a = { state = "active", secondsLeft = 10 },
            b = { state = "active", secondsLeft = 10 },
            c = { state = "active", secondsLeft = 10 },
        }
        local shown: { [string]: boolean } = {}
        local order: { string } = {}
        for _ = 1, 5 do
            local id = Offers.nextHint(state, ctx({ shownThisSession = shown }), data)
            if id == nil then
                break
            end
            -- solange dieser Hinweis sichtbar ist, kommt kein zweiter
            T.expect(Offers.nextHint(state, ctx({ shownThisSession = shown, hintVisible = true }), data)).toBeNil()
            shown[id] = true
            table.insert(order, id)
        end
        T.expect(order).toEqual({ "b", "c", "a" })
    end)

    T.it("Ablauf beim Client: Fund mit Reveal, Angebot wird freigeschaltet, Hinweis erst nach dem letzten Reveal, einmal pro Sitzung", function()
        -- Kleine Client-Simulation: Meldungen kommen in der Reihenfolge des Servers (find, offerUnlocked).
        local revealQueue: { string } = {}
        local revealRunning = false
        local tutorial = false
        local window = false
        local hintVisible = false
        local shown: { [string]: boolean } = {}
        local offersState: any = { starter = { state = "hidden", secondsLeft = 0 } }
        local hints: { string } = {}
        local function poll()
            local id = Offers.nextHint(offersState, {
                revealBusy = revealRunning or #revealQueue > 0,
                tutorialActive = tutorial,
                windowOpen = window,
                shownThisSession = shown,
                hintVisible = hintVisible,
            })
            if id ~= nil then
                shown[id] = true
                hintVisible = true
                table.insert(hints, id)
            end
        end
        -- zwei Funde kurz nacheinander, der zweite ist Selten und startet das Angebot
        table.insert(revealQueue, "dunes_s1_1")
        table.insert(revealQueue, "rare_find")
        offersState = { starter = { state = "active", secondsLeft = WINDOW } } -- offerUnlocked + StateSync
        poll()
        T.expect(#hints).toBe(0)
        revealRunning = true
        table.remove(revealQueue, 1) -- erster Reveal läuft, der zweite wartet
        poll()
        T.expect(#hints).toBe(0)
        table.remove(revealQueue, 1) -- zweiter Reveal läuft
        poll()
        T.expect(#hints).toBe(0)
        revealRunning = false -- alle Reveals fertig
        tutorial = true
        poll()
        T.expect(#hints).toBe(0) -- Tutorial läuft noch
        tutorial = false
        window = true
        poll()
        T.expect(#hints).toBe(0) -- Fenster offen
        window = false
        poll()
        T.expect(hints).toEqual({ "starter" })
        hintVisible = false -- Spieler schließt den Hinweis
        for _ = 1, 10 do
            poll()
        end
        T.expect(hints).toEqual({ "starter" }) -- höchstens einmal pro Sitzung
        -- neue Sitzung: wieder einmal
        shown = {}
        poll()
        T.expect(hints).toEqual({ "starter", "starter" })
    end)
end)

T.describe("Studio-Hilfe DebugOffer (4.5)", function()
    T.it("parseDebug: \"starter\" startet, \"-starter\" setzt zurück, Unbekanntes und Kaputtes abgelehnt", function()
        T.expect({ Offers.parseDebug("starter") }).toEqual({ "starter", true })
        T.expect({ Offers.parseDebug("-starter") }).toEqual({ "starter", false })
        for _, bad in { "", "gibt_es_nicht", "star ter", 5, nil, string.rep("a", 80), "--starter" } do
            local id, _, problem = Offers.parseDebug(bad)
            T.expect(id).toBeNil()
            T.expect(type(problem)).toBe("string")
        end
    end)

    T.it("withDebug: neue Tabelle, Start jetzt bzw. zurückgesetzt, andere Einträge bleiben", function()
        local profile: any = Profile.default(NOW)
        profile.offers = { starter = { since = 5, bought = true }, zukunft = { since = 1, bought = true } }
        local before = deepCopy(profile.offers)
        T.expect(Offers.withDebug(profile, "starter", true, NOW)).toEqual({ starter = { since = NOW, bought = false }, zukunft = { since = 1, bought = true } })
        T.expect(Offers.withDebug(profile, "starter", false, NOW)).toEqual({ starter = { since = 0, bought = false }, zukunft = { since = 1, bought = true } })
        T.expect(profile.offers).toEqual(before)
    end)
end)

T.finish()
