--!strict
-- Paket 4.1: Kaufabwicklung (Logic/Purchases) mit PlayerSession und Fake-Speicher.
--
-- Der Fake-Speicher kann Speichern verzögern (delaySaves + flushSaves), verweigern (failSaves), den
-- ungespeicherten Stand verwerfen (crash) und die Sitzung von außen beenden (endFromOutside).
-- Warten heißt hier: die Fake-Uhr rückt vor und die Koroutine gibt die Kontrolle an den Test zurück
-- (coroutine.yield). So prüft der Test Zwischenstände ohne echte Wartezeit.

local T = require("./lib/expect")
local FakeStore = require("./lib/fakestore")
local PlayerSession = require("../src/shared/Logic/PlayerSession")
local Purchases = require("../src/shared/Logic/Purchases")
local Profile = require("../src/shared/Logic/Profile")
local GemPacks = require("../src/shared/Data/GemPacks")
local Products = require("../src/shared/Data/Products")
local Economy = require("../src/shared/Data/Economy")

local USER = 42
local KEY = PlayerSession.keyFor(USER)
local START = 1_700_000_000
-- Test-ProductIds: Die echten Daten haben bis zur Anlage im Creator Dashboard nur Platzhalter (0).
local PACK_PRODUCT_BASE = 9_000_000
local OTHER_PRODUCT_BASE = 9_000_100

local function testData(purchases: any?): any
    local packs = { list = {}, byId = {} } :: any
    for index, pack in GemPacks.list do
        local copy = table.clone(pack)
        copy.productId = PACK_PRODUCT_BASE + index
        packs.list[index] = copy
        packs.byId[copy.id] = copy
    end
    local products = { list = {}, byId = {} } :: any
    for index, product in Products.list do
        local copy = table.clone(product)
        copy.productId = OTHER_PRODUCT_BASE + index
        products.list[index] = copy
        products.byId[copy.id] = copy
    end
    local economy = table.clone(Economy) :: any
    economy.purchases = purchases or table.clone(Economy.purchases)
    return { GemPacks = packs, Products = products, Economy = economy }
end

local DATA = testData()
local REAL_DATA = { GemPacks = GemPacks, Products = Products, Economy = Economy }

-- Quelltext von PlayerData (Roblox-Service, in Lune nicht ladbar) für den Vergleich der Wartezeiten.
-- Hier oben gelesen: Dateizugriff wartet, und vor dem ersten Test stört das den Abschluss nicht.
local PLAYER_DATA_SOURCE: string = require("@lune/fs").readFile("src/server/Services/PlayerData.luau")

local function productIdOf(id: string, data: any?): number
    local source = data or DATA
    local entry = source.GemPacks.byId[id] or source.Products.byId[id]
    return entry.productId
end

local function present(): boolean
    return true
end

type Note = { userId: number, kind: string, data: { [string]: any } }

type Options = {
    data: any?,
    allowDebug: boolean?,
    handlers: { [string]: any }?,
    noLockWait: boolean?, -- Purchases ohne `wait` (PlayerSession wartet trotzdem)
    isSessionActive: ((number) -> boolean)?,
    isLoading: ((number) -> boolean)?,
    getProfile: ((number) -> any)?,
    saveAndWait: ((number, string, number) -> boolean)?,
    notify: ((number, string, { [string]: any }) -> ())?,
    -- Nur für Purchases (PlayerSession behält die normale Uhr): Uhr und Protokoll, die zum Beispiel warten.
    purchasesNow: (() -> number)?,
    purchasesLog: ((string) -> ())?,
}

type Server = {
    manager: PlayerSession.Manager,
    purchases: Purchases.Purchases,
    logs: { string },
    notes: { Note },
    clock: { time: number },
}

local function newServer(world: FakeStore.World, name: string, options: Options?): Server
    local opts: Options = options or {}
    local clock = { time = START }
    local logs: { string } = {}
    local notes: { Note } = {}
    local function now(): number
        return clock.time
    end
    local function wait(seconds: number)
        clock.time += seconds
        coroutine.yield()
    end
    local function log(message: string)
        table.insert(logs, message)
    end
    local manager = PlayerSession.new({
        store = FakeStore.newServer(world, name),
        now = now,
        clock = now,
        wait = wait,
        kick = function() end,
        log = log,
    })
    local purchases = Purchases.new({
        getProfile = opts.getProfile or manager.get,
        isSessionActive = opts.isSessionActive or manager.isActive,
        isLoading = opts.isLoading,
        saveAndWait = opts.saveAndWait or function(userId: number, purchaseId: string, timeoutSeconds: number): boolean
            return manager.saveAndWait(userId, function(saved: any): boolean
                return Purchases.hasReceipt(saved, purchaseId)
            end, timeoutSeconds)
        end,
        now = opts.purchasesNow or now,
        clock = now,
        wait = if opts.noLockWait then nil else wait,
        log = opts.purchasesLog or log,
        notify = opts.notify or function(userId: number, kind: string, data: { [string]: any })
            table.insert(notes, { userId = userId, kind = kind, data = data })
        end,
        handlers = opts.handlers :: any,
        allowDebug = opts.allowDebug,
        data = if opts.data ~= nil then opts.data else DATA,
    })
    return { manager = manager, purchases = purchases, logs = logs, notes = notes, clock = clock }
end

-- Ein laufender Vorgang (Koroutine). `wait` im Code gibt die Kontrolle an den Test zurück.
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

local function isDone(job: Job): boolean
    return coroutine.status(job.co) == "dead"
end

-- Lässt den Vorgang bis zum Ende laufen (jede Runde ist ein Wartezyklus).
local function finish(job: Job): string?
    for _ = 1, 10_000 do
        if isDone(job) then
            return job.result
        end
        resume(job)
    end
    error("Vorgang wurde nicht fertig")
end

local function receipt(packId: string, purchaseId: string, data: any?): Purchases.Receipt
    return { PlayerId = USER, ProductId = productIdOf(packId, data), PurchaseId = purchaseId }
end

-- Startet einen Kauf als Vorgang.
local function startBuy(server: Server, packId: string, purchaseId: string): Job
    return start(function(): string
        return server.purchases.process(receipt(packId, purchaseId))
    end)
end

-- Kauft und wartet auf das Ergebnis.
local function buy(server: Server, packId: string, purchaseId: string): string?
    return finish(startBuy(server, packId, purchaseId))
end

local function load(server: Server): any
    return server.manager.load(USER, present)
end

local function savedGems(world: FakeStore.World): number
    local saved = world.saved[KEY]
    return if saved ~= nil then saved.gems else 0
end

local function savedHas(world: FakeStore.World, purchaseId: string): boolean
    return Purchases.hasReceipt(world.saved[KEY], purchaseId)
end

-- Gutschrift und PurchaseId stehen im gespeicherten Stand immer gemeinsam (oder beide nicht).
local function expectTogether(world: FakeStore.World, purchaseId: string, gems: number)
    T.expect(savedHas(world, purchaseId)).toBe(savedGems(world) == gems)
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

T.describe("Kaufabwicklung: Gutschrift erst nach dem Speichern", function()
    T.it("ein Kauf von gems_550 schreibt genau 550 Gems gut und liefert erst nach dem Speichern PurchaseGranted", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        local job = startBuy(a, "gems_550", "kauf-1")
        -- Gutgeschrieben im Speicher, aber noch nicht gespeichert: kein Ergebnis, keine Meldung.
        T.expect(isDone(job)).toBe(false)
        T.expect(profile.gems).toBe(550)
        T.expect(Purchases.hasReceipt(profile, "kauf-1")).toBe(true)
        T.expect(world.saved[KEY]).toBeNil()
        T.expect(#a.notes).toBe(0)
        resume(job)
        resume(job)
        T.expect(isDone(job)).toBe(false)
        -- Das Speichern kommt an: jetzt erst "granted".
        T.expect(FakeStore.flushSaves(world)).toBe(1)
        T.expect(finish(job)).toBe("granted")
        T.expect(world.saved[KEY].gems).toBe(550)
        T.expect(savedHas(world, "kauf-1")).toBe(true)
        T.expect(#a.notes).toBe(1)
        T.expect(a.notes[1].kind).toBe("gemsBought")
        T.expect(a.notes[1].data).toEqual({ gems = 550, total = 550, productId = "gems_550" })
        T.expect(profile.receipts).toEqual({ "kauf-1" })
        T.expect(profile.purchaseLog).toEqual({
            { purchaseId = "kauf-1", productId = "gems_550", gems = 550, robux = 249, time = START },
        })
        T.expect(profile.spent).toEqual({ robux = 249, count = 1 })
    end)

    T.it("jedes Gem-Paket schreibt genau seine Gems aus den Daten gut", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        local total, robux = 0, 0
        for index, pack in GemPacks.list do
            T.expect(buy(a, pack.id, `paket-{index}`)).toBe("granted")
            total += pack.gems
            robux += pack.robux
            T.expect(profile.gems).toBe(total)
        end
        T.expect(world.saved[KEY].gems).toBe(total)
        T.expect(profile.spent).toEqual({ robux = robux, count = #GemPacks.list })
    end)

    T.it("Werte im Beleg außer den drei Feldern zählen nicht (der Server entscheidet)", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        local fake: any = receipt("gems_100", "kauf-extra")
        fake.CurrencySpent = 999_999
        fake.Gems = 999_999
        fake.gems = 999_999
        local result = finish(start(function(): string
            return a.purchases.process(fake)
        end))
        T.expect(result).toBe("granted")
        T.expect(profile.gems).toBe(100)
        T.expect(profile.purchaseLog[1].robux).toBe(49)
    end)
end)

T.describe("Kaufabwicklung: doppelte Belege", function()
    T.it("dieselbe PurchaseId zweimal nacheinander: eine Gutschrift, beide PurchaseGranted", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        T.expect(buy(a, "gems_550", "kauf-2")).toBe("granted")
        local writes = world.writes
        T.expect(buy(a, "gems_550", "kauf-2")).toBe("granted")
        T.expect(buy(a, "gems_550", "kauf-2")).toBe("granted")
        T.expect(profile.gems).toBe(550)
        T.expect(world.saved[KEY].gems).toBe(550)
        T.expect(world.writes).toBe(writes) -- schon gespeichert: kein weiteres Speichern
        T.expect(#profile.purchaseLog).toBe(1)
        T.expect(profile.spent).toEqual({ robux = 249, count = 1 })
        T.expect(#a.notes).toBe(1)
        T.expect(countLogs(a, "schon gutgeschrieben")).toBe(2)
    end)

    T.it("dieselbe PurchaseId zweimal gleichzeitig (der erste wartet noch aufs Speichern): eine Gutschrift", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        local first = startBuy(a, "gems_550", "kauf-3")
        local second = startBuy(a, "gems_550", "kauf-3")
        T.expect(isDone(first)).toBe(false)
        T.expect(isDone(second)).toBe(false)
        T.expect(profile.gems).toBe(550)
        T.expect(world.saveCalls).toBe(1) -- der zweite wartet auf den ersten und speichert nicht selbst
        resume(second)
        resume(first)
        FakeStore.flushSaves(world)
        T.expect(finish(first)).toBe("granted")
        T.expect(finish(second)).toBe("granted")
        T.expect(profile.gems).toBe(550)
        T.expect(world.saved[KEY].gems).toBe(550)
        T.expect(#profile.purchaseLog).toBe(1)
        T.expect(profile.spent.count).toBe(1)
        T.expect(#a.notes).toBe(1)
    end)

    T.it("gleichzeitig, und das Speichern scheitert: beide NotProcessedYet, später genau eine Gutschrift", function()
        local world = FakeStore.newWorld()
        world.failSaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        local first = startBuy(a, "gems_550", "kauf-4")
        local second = startBuy(a, "gems_550", "kauf-4")
        T.expect(finish(first)).toBe("notProcessed")
        T.expect(finish(second)).toBe("notProcessed")
        T.expect(profile.gems).toBe(550)
        world.failSaves = false
        T.expect(buy(a, "gems_550", "kauf-4")).toBe("granted")
        T.expect(profile.gems).toBe(550)
        T.expect(world.saved[KEY].gems).toBe(550)
    end)

    T.it("zwei verschiedene Käufe gleichzeitig: beide gebucht", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        local first = startBuy(a, "gems_100", "kauf-5a")
        local second = startBuy(a, "gems_550", "kauf-5b")
        T.expect(profile.gems).toBe(650)
        FakeStore.flushSaves(world)
        T.expect(finish(first)).toBe("granted")
        T.expect(finish(second)).toBe("granted")
        T.expect(world.saved[KEY].gems).toBe(650)
        T.expect(profile.receipts).toEqual({ "kauf-5a", "kauf-5b" })
        T.expect(#a.notes).toBe(2)
    end)

    T.it("ohne Warten (kein `wait`): ein gleichzeitiger zweiter Aufruf gibt NotProcessedYet und bucht nicht", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A", { noLockWait = true })
        local profile = load(a)
        local first = startBuy(a, "gems_550", "kauf-6")
        local second = startBuy(a, "gems_550", "kauf-6")
        T.expect(isDone(second)).toBe(true)
        T.expect(second.result).toBe("notProcessed")
        FakeStore.flushSaves(world)
        T.expect(finish(first)).toBe("granted")
        T.expect(profile.gems).toBe(550)
    end)

    T.it("eine PurchaseId in der alten Tabellenform des Profils bucht nicht neu", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        profile.receipts = { ["kauf-alt"] = true }
        T.expect(buy(a, "gems_550", "kauf-alt")).toBe("granted")
        T.expect(profile.gems).toBe(0)
        T.expect(world.saved[KEY].receipts).toEqual({ "kauf-alt" }) -- beim Speichern in Listenform
    end)
end)

T.describe("Kaufabwicklung: Profil nicht da", function()
    T.it("Profil nicht geladen: NotProcessedYet, keine Gutschrift, kein Speichern", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        T.expect(buy(a, "gems_550", "kauf-7")).toBe("notProcessed")
        T.expect(world.saveCalls).toBe(0)
        T.expect(world.saved[KEY]).toBeNil()
        T.expect(countLogs(a, "Profil nicht geladen")).toBe(1)
        -- Sobald das Profil da ist, klappt derselbe Beleg genau einmal.
        local profile = load(a)
        T.expect(profile.gems).toBe(0)
        T.expect(buy(a, "gems_550", "kauf-7")).toBe("granted")
        T.expect(profile.gems).toBe(550)
    end)

    T.it("Profil lädt noch, wenn der Beleg kommt: der Kauf wartet und bucht nach dem Laden genau einmal", function()
        local world = FakeStore.newWorld()
        local here = true
        local manager: PlayerSession.Manager
        local a = newServer(world, "A", {
            isLoading = function(userId: number): boolean
                return here and not manager.isLoaded(userId)
            end,
        })
        manager = a.manager
        local job = startBuy(a, "gems_550", "kauf-lade")
        resume(job)
        T.expect(isDone(job)).toBe(false) -- wartet auf das Profil
        local profile = load(a)
        T.expect(finish(job)).toBe("granted")
        T.expect(profile.gems).toBe(550)
        T.expect(world.saved[KEY].gems).toBe(550)

        -- Spieler geht, während sein Profil noch lädt: NotProcessedYet, ohne die volle Wartezeit.
        local world2 = FakeStore.newWorld()
        local b: Server
        b = newServer(world2, "B", {
            isLoading = function(userId: number): boolean
                return here and not b.manager.isLoaded(userId)
            end,
        })
        local leaving = startBuy(b, "gems_550", "kauf-weg")
        here = false
        T.expect(finish(leaving)).toBe("notProcessed")
        T.expect(b.clock.time - START < 5).toBe(true)

        -- Lädt das Profil nie: NotProcessedYet nach der begrenzten Wartezeit.
        local world3 = FakeStore.newWorld()
        local c = newServer(world3, "C", {
            isLoading = function(): boolean
                return true
            end,
        })
        T.expect(buy(c, "gems_550", "kauf-nie")).toBe("notProcessed")
        T.expect(world3.saveCalls).toBe(0)
    end)

    T.it("Spieler nicht auf dem Server oder Sitzung nicht aktiv: NotProcessedYet, keine Gutschrift", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", {
            isSessionActive = function(): boolean
                return false -- zum Beispiel: Spieler hat den Server verlassen
            end,
        })
        local profile = load(a)
        T.expect(buy(a, "gems_550", "kauf-8")).toBe("notProcessed")
        T.expect(profile.gems).toBe(0)
        T.expect(profile.receipts).toEqual({})
        T.expect(world.saveCalls).toBe(0)

        local b = newServer(FakeStore.newWorld(), "B")
        load(b)
        b.manager.release(USER)
        T.expect(buy(b, "gems_550", "kauf-8")).toBe("notProcessed")
    end)
end)

T.describe("Kaufabwicklung: Speicherfehler", function()
    T.it("Speichern schlägt fehl: NotProcessedYet, Gems und PurchaseId bleiben zusammen, der nächste Versuch bucht nicht neu", function()
        local world = FakeStore.newWorld()
        world.failSaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        T.expect(buy(a, "gems_550", "kauf-9")).toBe("notProcessed")
        T.expect(a.clock.time - START >= Economy.purchases.saveTimeoutSeconds).toBe(true)
        T.expect(profile.gems).toBe(550)
        T.expect(Purchases.hasReceipt(profile, "kauf-9")).toBe(true)
        T.expect(world.saved[KEY]).toBeNil()
        T.expect(#a.notes).toBe(0)
        -- Noch ein Versuch, das Speichern geht immer noch nicht: keine neue Gutschrift.
        T.expect(buy(a, "gems_550", "kauf-9")).toBe("notProcessed")
        T.expect(profile.gems).toBe(550)
        -- Speichern geht wieder: "granted" ohne neue Gutschrift, die Meldung kommt jetzt genau einmal.
        world.failSaves = false
        T.expect(buy(a, "gems_550", "kauf-9")).toBe("granted")
        T.expect(profile.gems).toBe(550)
        T.expect(world.saved[KEY].gems).toBe(550)
        T.expect(savedHas(world, "kauf-9")).toBe(true)
        T.expect(#profile.purchaseLog).toBe(1)
        T.expect(profile.spent.count).toBe(1)
        T.expect(#a.notes).toBe(1)
        T.expect(a.notes[1].data.gems).toBe(550)
    end)

    T.it("Speichern läuft in die Zeitgrenze: NotProcessedYet, kommt es später an, gilt der nächste Versuch ohne neue Gutschrift", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        local profile = load(a)
        local job = startBuy(a, "gems_550", "kauf-10")
        T.expect(finish(job)).toBe("notProcessed") -- niemand führt das Speichern aus
        T.expect(a.clock.time - START >= Economy.purchases.saveTimeoutSeconds).toBe(true)
        expectTogether(world, "kauf-10", 550)
        -- Das verspätete Speichern kommt an: beides zusammen.
        FakeStore.flushSaves(world)
        expectTogether(world, "kauf-10", 550)
        T.expect(world.saved[KEY].gems).toBe(550)
        local saves = world.saveCalls
        T.expect(buy(a, "gems_550", "kauf-10")).toBe("granted")
        T.expect(world.saveCalls).toBe(saves) -- schon gespeichert, nur nachgesehen
        T.expect(profile.gems).toBe(550)
    end)

    T.it("Absturz vor dem Speichern (Stand verworfen): der nächste Versuch auf dem neuen Server bucht genau einmal", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        load(a)
        local job = startBuy(a, "gems_550", "kauf-11")
        FakeStore.crash(world, KEY) -- Server A ist weg, der ungespeicherte Stand auch
        T.expect(finish(job)).toBe("notProcessed")
        -- Gewartet wird bis zur Zeitgrenze (ein letztes Speichern könnte noch kommen), dann aufgegeben.
        T.expect(a.clock.time - START >= Economy.purchases.saveTimeoutSeconds).toBe(true)
        T.expect(world.saved[KEY]).toBeNil()

        world.delaySaves = false
        local b = newServer(world, "B")
        local profileB = load(b)
        T.expect(profileB.gems).toBe(0)
        T.expect(buy(b, "gems_550", "kauf-11")).toBe("granted")
        T.expect(buy(b, "gems_550", "kauf-11")).toBe("granted")
        T.expect(profileB.gems).toBe(550)
        T.expect(world.saved[KEY].gems).toBe(550)
        T.expect(#profileB.purchaseLog).toBe(1)
    end)

    T.it("Absturz nach dem Speichern, aber vor PurchaseGranted: der neue Server bucht nicht neu", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        load(a)
        startBuy(a, "gems_550", "kauf-12")
        FakeStore.flushSaves(world) -- gespeichert ...
        FakeStore.crash(world, KEY) -- ... dann stürzt A ab, bevor Roblox die Antwort bekommt
        world.delaySaves = false
        local b = newServer(world, "B")
        local profileB = load(b)
        T.expect(profileB.gems).toBe(550)
        T.expect(buy(b, "gems_550", "kauf-12")).toBe("granted")
        T.expect(profileB.gems).toBe(550)
        T.expect(#profileB.purchaseLog).toBe(1)
    end)

    T.it("Sitzung von außen übernommen während des Wartens: NotProcessedYet, keine zweite Gutschrift beim nächsten Versuch", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        load(a)
        local job = startBuy(a, "gems_550", "kauf-13")
        FakeStore.endFromOutside(world, KEY) -- ein anderer Server übernimmt die Sitzung (ohne Speichern)
        T.expect(finish(job)).toBe("notProcessed")
        -- Erst nach der Zeitgrenze: Bis dahin hätte noch ein letztes Speichern kommen können.
        T.expect(a.clock.time - START >= Economy.purchases.saveTimeoutSeconds).toBe(true)
        FakeStore.flushSaves(world) -- die beendete Sitzung schreibt nicht mehr
        T.expect(world.saved[KEY]).toBeNil()

        world.delaySaves = false
        local b = newServer(world, "B")
        local profileB = load(b)
        T.expect(buy(b, "gems_550", "kauf-13")).toBe("granted")
        T.expect(buy(b, "gems_550", "kauf-13")).toBe("granted")
        T.expect(profileB.gems).toBe(550)
        T.expect(world.saved[KEY].gems).toBe(550)
    end)

    T.it("Spieler verlässt das Spiel während des Wartens, das letzte Speichern enthält den Kauf: PurchaseGranted, kein zweites Buchen", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        load(a)
        local job = startBuy(a, "gems_550", "kauf-14")
        -- Wie ProfileStore: Die Sitzung ist sofort inaktiv, das letzte Schreiben kommt erst danach.
        a.manager.release(USER)
        resume(job)
        resume(job)
        T.expect(isDone(job)).toBe(false) -- wartet trotz Sitzungsende weiter
        T.expect(a.manager.isActive(USER)).toBe(false)
        T.expect(world.saved[KEY]).toBeNil()
        FakeStore.flushSaves(world) -- das letzte Schreiben kommt an
        T.expect(finish(job)).toBe("granted")
        T.expect(a.clock.time - START < Economy.purchases.saveTimeoutSeconds).toBe(true)
        T.expect(savedHas(world, "kauf-14")).toBe(true)
        T.expect(world.saved[KEY].gems).toBe(550)

        world.delaySaves = false
        local b = newServer(world, "B")
        local profileB = load(b)
        T.expect(buy(b, "gems_550", "kauf-14")).toBe("granted")
        T.expect(profileB.gems).toBe(550)
        T.expect(#profileB.purchaseLog).toBe(1)
    end)

    T.it("Spieler verlässt das Spiel während des Wartens, das letzte Speichern scheitert: NotProcessedYet, der nächste Server bucht genau einmal", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a = newServer(world, "A")
        load(a)
        local job = startBuy(a, "gems_550", "kauf-14b")
        a.manager.release(USER)
        world.failSaves = true
        FakeStore.flushSaves(world) -- das letzte Schreiben scheitert, der Stand ist verloren
        T.expect(finish(job)).toBe("notProcessed")
        T.expect(a.clock.time - START >= Economy.purchases.saveTimeoutSeconds).toBe(true)
        T.expect(world.saved[KEY]).toBeNil()
        T.expect(#a.notes).toBe(0)

        world.failSaves = false
        world.delaySaves = false
        local b = newServer(world, "B")
        local profileB = load(b)
        T.expect(profileB.gems).toBe(0)
        T.expect(buy(b, "gems_550", "kauf-14b")).toBe("granted")
        T.expect(buy(b, "gems_550", "kauf-14b")).toBe("granted")
        T.expect(profileB.gems).toBe(550)
        T.expect(world.saved[KEY].gems).toBe(550)
        T.expect(#profileB.purchaseLog).toBe(1)
    end)

    T.it("Fehler im Speicher-Adapter: NotProcessedYet, beim nächsten Versuch ohne neue Gutschrift", function()
        local world = FakeStore.newWorld()
        local broken = true
        local manager: PlayerSession.Manager
        local a = newServer(world, "A", {
            saveAndWait = function(userId: number, purchaseId: string, timeoutSeconds: number): boolean
                if broken then
                    error("DataStore weg")
                end
                return manager.saveAndWait(userId, function(saved: any): boolean
                    return Purchases.hasReceipt(saved, purchaseId)
                end, timeoutSeconds)
            end,
        })
        manager = a.manager
        local profile = load(a)
        T.expect(buy(a, "gems_550", "kauf-15")).toBe("notProcessed")
        T.expect(countLogs(a, "DataStore weg")).toBe(1)
        T.expect(profile.gems).toBe(550)
        broken = false
        T.expect(buy(a, "gems_550", "kauf-15")).toBe("granted")
        T.expect(profile.gems).toBe(550)
    end)
end)

T.describe("Kaufabwicklung: unbekannte Produkte und kaputte Belege", function()
    T.it("unbekannte ProductId und productId = 0: NotProcessedYet, keine Gutschrift, ein Protokolleintrag", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        for _, productId in { 0, 123_456_789 } do
            local before = #a.logs
            local result = finish(start(function(): string
                return a.purchases.process({ PlayerId = USER, ProductId = productId, PurchaseId = `kauf-u{productId}` })
            end))
            T.expect(result).toBe("notProcessed")
            T.expect(#a.logs - before).toBe(1)
        end
        T.expect(profile.gems).toBe(0)
        T.expect(profile.receipts).toEqual({})
        T.expect(world.saveCalls).toBe(0)
    end)

    T.it("mit den echten Daten (ProductId 0 als Platzhalter) wird kein Paket über den Echtpfad gebucht", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = REAL_DATA, allowDebug = true })
        local profile = load(a)
        for _, pack in GemPacks.list do
            local result = finish(start(function(): string
                return a.purchases.process({ PlayerId = USER, ProductId = pack.productId, PurchaseId = `echt-{pack.id}` })
            end))
            T.expect(result).toBe("notProcessed")
        end
        T.expect(profile.gems).toBe(0)
        T.expect(countLogs(a, "Platzhalter")).toBe(#GemPacks.list)
    end)

    T.it("kaputte Belege: NotProcessedYet, keine Gutschrift, je ein Protokolleintrag", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        local pid = productIdOf("gems_550")
        local cases: { any } = {
            "kein Beleg",
            { PlayerId = USER, ProductId = pid, PurchaseId = "" },
            { PlayerId = USER, ProductId = pid, PurchaseId = 12345 },
            { PlayerId = USER, ProductId = pid, PurchaseId = string.rep("x", 200) },
            { PlayerId = USER, ProductId = pid + 0.5, PurchaseId = "kauf-k" },
            { PlayerId = USER, ProductId = tostring(pid), PurchaseId = "kauf-k" },
            { PlayerId = USER, ProductId = -pid, PurchaseId = "kauf-k" },
            { PlayerId = 0 / 0, ProductId = pid, PurchaseId = "kauf-k" },
            { PlayerId = 0, ProductId = pid, PurchaseId = "kauf-k" },
            { ProductId = pid, PurchaseId = "kauf-k" },
        }
        for _, case in cases do
            local before = #a.logs
            local result = finish(start(function(): string
                return a.purchases.process(case)
            end))
            T.expect(result).toBe("notProcessed")
            T.expect(#a.logs - before).toBe(1)
        end
        local result = finish(start(function(): string
            return a.purchases.process(nil)
        end))
        T.expect(result).toBe("notProcessed")
        T.expect(profile.gems).toBe(0)
        T.expect(world.saveCalls).toBe(0)
    end)

    T.it("ein Produkt ohne Handler (zum Beispiel der Münz-Boost vor Paket 4.4): NotProcessedYet", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        T.expect(buy(a, "coin_boost", "kauf-17")).toBe("notProcessed")
        T.expect(countLogs(a, "kein Handler")).toBe(1)
        T.expect(profile.receipts).toEqual({})
        T.expect(profile.spent.count).toBe(0)
    end)

    T.it("doppelt vergebene ProductId: kein Raten, NotProcessedYet", function()
        local data = testData()
        data.GemPacks.byId.gems_100.productId = 777
        data.GemPacks.byId.gems_550.productId = 777
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = data })
        local profile = load(a)
        T.expect(countLogs(a, "doppelt vergeben")).toBe(1)
        local result = finish(start(function(): string
            return a.purchases.process({ PlayerId = USER, ProductId = 777, PurchaseId = "kauf-18" })
        end))
        T.expect(result).toBe("notProcessed")
        T.expect(profile.gems).toBe(0)
    end)
end)

T.describe("Kaufabwicklung: Belege und Kaufprotokoll", function()
    T.it("die Beleg-Liste hält höchstens receiptCacheSize, das Kaufprotokoll höchstens purchaseLogSize, älteste zuerst raus", function()
        local data = testData({ receiptCacheSize = 5, purchaseLogSize = 3, saveTimeoutSeconds = 30, maxGems = 10_000_000 })
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = data })
        local profile = load(a)
        for index = 1, 7 do
            T.expect(buy(a, "gems_100", `k{index}`)).toBe("granted")
        end
        T.expect(profile.receipts).toEqual({ "k3", "k4", "k5", "k6", "k7" })
        local ids = {}
        for _, entry in profile.purchaseLog do
            table.insert(ids, entry.purchaseId)
        end
        T.expect(ids).toEqual({ "k5", "k6", "k7" })
        T.expect(profile.gems).toBe(700)
        T.expect(profile.spent).toEqual({ robux = 7 * 49, count = 7 })
        -- Die noch gemerkten PurchaseIds buchen nicht neu.
        T.expect(buy(a, "gems_100", "k3")).toBe("granted")
        T.expect(profile.gems).toBe(700)
    end)

    T.it("mit den echten Größen: 120 Käufe ergeben 100 Belege und 50 Protokolleinträge", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        for index = 1, 120 do
            T.expect(buy(a, "gems_100", `r{index}`)).toBe("granted")
        end
        T.expect(#profile.receipts).toBe(Economy.purchases.receiptCacheSize)
        T.expect(profile.receipts[1]).toBe("r21")
        T.expect(profile.receipts[100]).toBe("r120")
        T.expect(#profile.purchaseLog).toBe(Economy.purchases.purchaseLogSize)
        T.expect(profile.purchaseLog[1].purchaseId).toBe("r71")
        T.expect(#world.saved[KEY].receipts).toBe(100)
        T.expect(world.saved[KEY].gems).toBe(12_000)
    end)

    T.it("bei maxGems gekappt: der Kauf gilt, das Protokoll nennt die tatsächliche Menge", function()
        local data = testData({ receiptCacheSize = 100, purchaseLogSize = 50, saveTimeoutSeconds = 30, maxGems = 1000 })
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = data })
        local profile = load(a)
        profile.gems = 800
        T.expect(buy(a, "gems_550", "kauf-cap")).toBe("granted")
        T.expect(profile.gems).toBe(1000)
        T.expect(profile.purchaseLog[1].gems).toBe(200)
        T.expect(countLogs(a, "gekappt")).toBe(1)
        T.expect(a.notes[1].data).toEqual({ gems = 200, total = 1000, productId = "gems_550" })
    end)
end)

T.describe("Kaufabwicklung: Handler und Fehler", function()
    -- Beispiel-Handler wie in Paket 4.4: rechnet auf der Kopie und gibt die neuen Felder zurück.
    local function boostHandler(profile: any, product: Purchases.Product): Purchases.Prepared?
        local boosts = table.clone(profile.boosts)
        boosts.coinsUntil = START + Economy.coinBoost.durationSeconds
        return {
            gems = 0,
            changes = { boosts = boosts },
            announce = function(): (string, { [string]: any })
                return "boostBought", { productId = product.id }
            end,
        }
    end

    T.it("ein registrierter Handler bucht ein weiteres Produkt über denselben Ablauf", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { handlers = { coin_boost = boostHandler } })
        local profile = load(a)
        T.expect(buy(a, "coin_boost", "kauf-boost")).toBe("granted")
        T.expect(profile.boosts.coinsUntil).toBe(START + Economy.coinBoost.durationSeconds)
        T.expect(profile.receipts).toEqual({ "kauf-boost" })
        T.expect(profile.purchaseLog[1]).toEqual({ purchaseId = "kauf-boost", productId = "coin_boost", gems = 0, robux = 49, time = START })
        T.expect(profile.spent).toEqual({ robux = 49, count = 1 })
        T.expect(a.notes[1].kind).toBe("boostBought")
        T.expect(profile.gems).toBe(0)
    end)

    T.it("register lehnt unbekannte Produkte, doppelte Handler und Nicht-Funktionen ab", function()
        local a = newServer(FakeStore.newWorld(), "A")
        T.expect(function()
            a.purchases.register("gibt_es_nicht", boostHandler)
        end).toThrow("steht nicht in")
        T.expect(function()
            a.purchases.register("gems_550", boostHandler)
        end).toThrow("schon ein Handler")
        T.expect(function()
            a.purchases.register("coin_boost", "kein Handler" :: any)
        end).toThrow("keine Funktion")
        a.purchases.register("coin_boost", boostHandler)
        T.expect(function()
            a.purchases.register("coin_boost", boostHandler)
        end).toThrow("schon ein Handler")
    end)

    T.it("ein Fehler beim Ausrechnen lässt das Profil unverändert", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", {
            handlers = {
                coin_boost = function(): Purchases.Prepared?
                    error("Handler kaputt")
                end,
                season_pass = function(): Purchases.Prepared?
                    return nil
                end,
            },
        })
        local profile = load(a)
        profile.gems = 40
        local before = FakeStore.deepCopy(profile)
        T.expect(buy(a, "coin_boost", "kauf-err")).toBe("notProcessed")
        T.expect(buy(a, "season_pass", "kauf-nil")).toBe("notProcessed")
        T.expect(profile).toEqual(before)
        T.expect(countLogs(a, "Handler kaputt")).toBe(1)
        T.expect(world.saveCalls).toBe(0)
        -- Danach geht ein normaler Kauf.
        T.expect(buy(a, "gems_100", "kauf-ok")).toBe("granted")
        T.expect(profile.gems).toBe(140)
    end)

    T.it("Fehler beim Profil-Holen: NotProcessedYet ohne Fehler nach außen", function()
        local a = newServer(FakeStore.newWorld(), "A", {
            getProfile = function(): any
                error("kaputt")
            end,
        })
        load(a)
        T.expect(buy(a, "gems_550", "kauf-gp")).toBe("notProcessed")
        T.expect(countLogs(a, "kaputt")).toBe(1)
    end)

    T.it("eine fehlschlagende Meldung ändert nichts am bestätigten Kauf", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", {
            notify = function()
                error("Remote weg")
            end,
        })
        local profile = load(a)
        T.expect(buy(a, "gems_550", "kauf-n")).toBe("granted")
        T.expect(profile.gems).toBe(550)
        T.expect(countLogs(a, "Remote weg")).toBe(1)
    end)

    T.it("forget: ausstehende Meldungen eines gegangenen Spielers verfallen", function()
        local world = FakeStore.newWorld()
        world.failSaves = true
        local a = newServer(world, "A")
        load(a)
        T.expect(buy(a, "gems_550", "kauf-f")).toBe("notProcessed")
        a.purchases.forget(USER)
        world.failSaves = false
        T.expect(buy(a, "gems_550", "kauf-f")).toBe("granted")
        T.expect(#a.notes).toBe(0)
    end)
end)

-- Security-Review 4.1 (M1, M2, N6): Der Handler rechnet nur auf einer Kopie und darf nie warten;
-- Purchases prüft seine Antwort, prüft direkt vor dem Schreiben erneut und schreibt alles oder nichts.
T.describe("Kaufabwicklung: Handler-Vertrag und Schreiben (alles oder nichts)", function()
    -- Ein Handler für coin_boost, dessen Antwort der Test vorgibt.
    local function fixedHandler(answer: () -> any): Purchases.Handler
        return function(): Purchases.Prepared?
            return answer()
        end
    end

    T.it("ein Handler, der wartet (yield), wird abgebrochen: NotProcessedYet sofort, Profil unverändert", function()
        local world = FakeStore.newWorld()
        local resumedAfterYield = false
        local a = newServer(world, "A", {
            handlers = {
                coin_boost = function(): Purchases.Prepared?
                    coroutine.yield() -- wie task.wait im Spiel
                    resumedAfterYield = true
                    return { changes = { gems = 999_999 }, gems = 0 }
                end,
            },
        })
        local profile = load(a)
        local before = FakeStore.deepCopy(profile)
        local job = startBuy(a, "coin_boost", "kauf-yield")
        T.expect(isDone(job)).toBe(true) -- hängt nicht, kein Warten
        T.expect(job.result).toBe("notProcessed")
        T.expect(a.clock.time).toBe(START)
        T.expect(resumedAfterYield).toBe(false)
        T.expect(profile).toEqual(before)
        T.expect(world.saveCalls).toBe(0)
        T.expect(countLogs(a, "gewartet")).toBe(1)
        -- Ein normaler Kauf danach geht.
        T.expect(buy(a, "gems_100", "kauf-danach")).toBe("granted")
        T.expect(profile.gems).toBe(100)
    end)

    T.it("Änderungen des Handlers an seinem Profil-Argument wirken nicht, nur `changes` zählt", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", {
            handlers = {
                coin_boost = function(copy: any, product: any): Purchases.Prepared?
                    copy.gems = 999_999
                    copy.finds.hack = 5
                    table.clear(copy.receipts)
                    copy.spent.robux = 0
                    product.robux = 0 -- auch das Produkt ist nur eine Kopie
                    product.id = "gems_550"
                    local boosts = table.clone(copy.boosts)
                    boosts.coinsUntil = 123
                    return { changes = { boosts = boosts }, gems = 0 }
                end,
            },
        })
        local profile = load(a)
        T.expect(buy(a, "gems_100", "kauf-a")).toBe("granted")
        T.expect(buy(a, "coin_boost", "kauf-b")).toBe("granted")
        T.expect(profile.gems).toBe(100)
        T.expect(profile.finds.hack).toBeNil()
        T.expect(profile.receipts).toEqual({ "kauf-a", "kauf-b" })
        T.expect(profile.spent).toEqual({ robux = 49 + 49, count = 2 })
        T.expect(profile.boosts.coinsUntil).toBe(123)
        T.expect(profile.purchaseLog[2].productId).toBe("coin_boost")
        T.expect(profile.purchaseLog[2].robux).toBe(49)
        T.expect(world.saved[KEY].gems).toBe(100)
        -- Ein zweiter Boost-Kauf hat weiter den Preis aus den Daten.
        T.expect(buy(a, "coin_boost", "kauf-c")).toBe("granted")
        T.expect(profile.spent).toEqual({ robux = 3 * 49, count = 3 })
    end)

    T.it("ungültige Antworten des Handlers: NotProcessedYet, keine Änderung, je ein Protokolleintrag", function()
        local current: any = nil
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { handlers = { coin_boost = fixedHandler(function()
            return current
        end) } })
        local profile = load(a)
        profile.gems = 40
        local before = FakeStore.deepCopy(profile)
        local cases: { any } = {
            5,
            { gems = 0 }, -- changes fehlt
            { changes = "boosts", gems = 0 },
            { changes = {}, gems = -1 },
            { changes = {}, gems = 1.5 },
            { changes = {}, gems = 0 / 0 },
            { changes = {}, gems = math.huge },
            { changes = {}, gems = "5" },
            { changes = { receipts = {} }, gems = 0 },
            { changes = { purchaseLog = {} }, gems = 0 },
            { changes = { spent = { robux = 0, count = 0 } }, gems = 0 },
            { changes = { version = 99 }, gems = 0 },
            { changes = { boosts = function() end }, gems = 0 },
            { changes = { boosts = { coinsUntil = 0 / 0 } }, gems = 0 },
            { changes = { boosts = { fn = function() end } }, gems = 0 },
            { changes = { boosts = { 1, 2, x = 3 } }, gems = 0 }, -- gemischt
            { changes = { boosts = { [1] = 1, [3] = 3 } }, gems = 0 }, -- Lücke
            { changes = { boosts = { [0] = 1 } }, gems = 0 },
            { changes = { boosts = { [1.5] = 1 } }, gems = 0 },
            { changes = { [1] = 5 }, gems = 0 },
            { changes = { [""] = 5 }, gems = 0 },
            { changes = { gems = math.huge }, gems = 0 },
            { changes = {}, gems = 0, announce = "boostBought" },
            -- Profil-Schema (Nach-Prüfung, Punkt 3): was das Speichern reparieren würde, wird abgelehnt.
            { changes = { gems = "550" }, gems = 0 },
            { changes = { gems = -1 }, gems = 0 },
            { changes = { gems = 1.5 }, gems = 0 },
            { changes = { gems = Economy.purchases.maxGems + 1 }, gems = 0 },
            { changes = { coins = { m = 5 } }, gems = 0 },
            { changes = { coins = { m = 5, e = "drei" } }, gems = 0 },
            { changes = { tank = 5 }, gems = 0 },
            { changes = { runEarned = { m = -1, e = 0 } }, gems = 0 },
            { changes = { boosts = { coinsUntil = "bald" } }, gems = 0 },
            { changes = { windCrystals = 2.5 }, gems = 0 }, -- sanitize rundet ohne Warnung ab
            { changes = { daily = "morgen" }, gems = 0 },
            { changes = { finds = { sand_glas = 0 } }, gems = 0 },
        }
        for index, case in cases do
            current = case
            local logsBefore = countLogs(a, "ungültige Antwort")
            T.expect(buy(a, "coin_boost", `kauf-bad-{index}`)).toBe("notProcessed")
            T.expect(countLogs(a, "ungültige Antwort") - logsBefore).toBe(1)
        end
        T.expect(profile).toEqual(before)
        T.expect(world.saveCalls).toBe(0)
        -- Gültige Antworten gehen danach durch (auch ein Feld, das Profile.default nicht kennt).
        current = { changes = { gems = 45, coins = { m = 1.5, e = 3 }, windCrystals = 3, extraFeld = "ok" }, gems = 0 }
        T.expect(buy(a, "coin_boost", "kauf-gut")).toBe("granted")
        T.expect(profile.gems).toBe(45)
        T.expect(profile.coins).toEqual({ m = 1.5, e = 3 })
        T.expect(profile.windCrystals).toBe(3)
        T.expect((profile :: any).extraFeld).toBe("ok")
    end)

    T.it("changes.gems über maxGems aus den Kaufdaten wird abgelehnt, auch wenn sanitize mehr erlaubt", function()
        local data = testData({ receiptCacheSize = 100, purchaseLogSize = 50, saveTimeoutSeconds = 30, maxGems = 1000 })
        local value = 1001
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = data, handlers = { coin_boost = function(): Purchases.Prepared?
            return { changes = { gems = value }, gems = 0 }
        end } })
        local profile = load(a)
        local result = finish(start(function(): string
            return a.purchases.process({ PlayerId = USER, ProductId = productIdOf("coin_boost", data), PurchaseId = "kauf-hoch" })
        end))
        T.expect(result).toBe("notProcessed")
        T.expect(profile.gems).toBe(0)
        T.expect(countLogs(a, "changes.gems ist keine ganze Zahl von 0 bis 1000")).toBe(1)
        value = 1000
        result = finish(start(function(): string
            return a.purchases.process({ PlayerId = USER, ProductId = productIdOf("coin_boost", data), PurchaseId = "kauf-hoch" })
        end))
        T.expect(result).toBe("granted")
        T.expect(profile.gems).toBe(1000)
    end)

    T.it("im kritischen Fenster wartet `now`: NotProcessedYet sofort, nichts geschrieben", function()
        local world = FakeStore.newWorld()
        local yielding = true
        local a = newServer(world, "A", {
            purchasesNow = function(): number
                if yielding then
                    coroutine.yield()
                end
                return START
            end,
        })
        local profile = load(a)
        local before = FakeStore.deepCopy(profile)
        local job = startBuy(a, "gems_550", "kauf-uhr")
        T.expect(isDone(job)).toBe(true)
        T.expect(job.result).toBe("notProcessed")
        T.expect(profile).toEqual(before)
        T.expect(world.saveCalls).toBe(0)
        T.expect(countLogs(a, "nichts geschrieben")).toBe(1)
        -- Ohne Warten geht derselbe Beleg genau einmal durch.
        yielding = false
        T.expect(buy(a, "gems_550", "kauf-uhr")).toBe("granted")
        T.expect(buy(a, "gems_550", "kauf-uhr")).toBe("granted")
        T.expect(profile.gems).toBe(550)
    end)

    T.it("im kritischen Fenster wartet `log` (Kappen-Hinweis): NotProcessedYet sofort, nichts geschrieben", function()
        local data = testData({ receiptCacheSize = 100, purchaseLogSize = 50, saveTimeoutSeconds = 30, maxGems = 1000 })
        local world = FakeStore.newWorld()
        local logs: { string } = {}
        local a = newServer(world, "A", {
            data = data,
            purchasesLog = function(message: string)
                table.insert(logs, message)
                if string.find(message, "gekappt", 1, true) then
                    coroutine.yield()
                end
            end,
        })
        local profile = load(a)
        profile.gems = 800
        local before = FakeStore.deepCopy(profile)
        local job = start(function(): string
            return a.purchases.process({ PlayerId = USER, ProductId = productIdOf("gems_550", data), PurchaseId = "kauf-log" })
        end)
        T.expect(isDone(job)).toBe(true)
        T.expect(job.result).toBe("notProcessed")
        T.expect(profile).toEqual(before)
        T.expect(world.saveCalls).toBe(0)
        local aborted = 0
        for _, line in logs do
            if string.find(line, "nichts geschrieben", 1, true) then
                aborted += 1
            end
        end
        T.expect(aborted).toBe(1)
    end)

    T.it("eine Meldung, die wartet (announce oder notify), wird abgebrochen: PurchaseGranted, die Sperre hängt nicht", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", {
            handlers = {
                coin_boost = function(copy: any): Purchases.Prepared?
                    return {
                        changes = { boosts = { coinsUntil = 99 } },
                        gems = 0,
                        announce = function(): (string, { [string]: any })
                            coroutine.yield() -- wartet zum Beispiel auf ein Ereignis
                            return "boostBought", {}
                        end,
                    }
                end,
            },
        })
        local profile = load(a)
        local job = startBuy(a, "coin_boost", "kauf-meldung")
        T.expect(isDone(job)).toBe(true)
        T.expect(job.result).toBe("granted")
        T.expect(countLogs(a, "Meldung an den Client nicht gesendet")).toBe(1)
        -- Dieselbe PurchaseId noch einmal: keine Sperre mehr, sofort PurchaseGranted ohne neue Buchung.
        local again = startBuy(a, "coin_boost", "kauf-meldung")
        T.expect(isDone(again)).toBe(true)
        T.expect(again.result).toBe("granted")
        T.expect(a.clock.time).toBe(START)
        T.expect(profile.spent.count).toBe(1)

        local world2 = FakeStore.newWorld()
        local b = newServer(world2, "B", {
            notify = function()
                coroutine.yield()
            end,
        })
        local profileB = load(b)
        local jobB = startBuy(b, "gems_550", "kauf-notify")
        T.expect(isDone(jobB)).toBe(true)
        T.expect(jobB.result).toBe("granted")
        T.expect(profileB.gems).toBe(550)
        T.expect(countLogs(b, "Meldung an den Client nicht gesendet")).toBe(1)
    end)

    T.it("NotProcessedYet ohne anwesenden Spieler vergisst die ausstehende Meldung", function()
        local function scenario(leaveInBetween: boolean): number
            local world = FakeStore.newWorld()
            world.failSaves = true
            local here = true
            local manager: PlayerSession.Manager
            local a = newServer(world, "A", {
                isSessionActive = function(userId: number): boolean
                    return here and manager.isActive(userId)
                end,
            })
            manager = a.manager
            local profile = load(a)
            T.expect(buy(a, "gems_550", "kauf-weg")).toBe("notProcessed") -- Meldung steht aus
            if leaveInBetween then
                here = false -- Spieler nicht mehr da: der nächste Aufruf endet mit NotProcessedYet
                T.expect(buy(a, "gems_550", "kauf-weg")).toBe("notProcessed")
                here = true
            end
            world.failSaves = false
            T.expect(buy(a, "gems_550", "kauf-weg")).toBe("granted")
            T.expect(profile.gems).toBe(550)
            return #a.notes
        end
        T.expect(scenario(false)).toBe(1) -- Spieler blieb: die Meldung kommt nach dem Speichern
        T.expect(scenario(true)).toBe(0) -- Spieler war weg: die Meldung ist vergessen
    end)

    T.it("erneute Prüfung direkt vor dem Schreiben: anderes Profil, Sitzung weg oder PurchaseId schon da", function()
        for _, variant in { "anderesProfil", "sitzungWeg", "schonGebucht" } do
            local world = FakeStore.newWorld()
            local calls = 0
            local manager: PlayerSession.Manager
            local live: any
            local a = newServer(world, "A", {
                getProfile = function(userId: number): any
                    calls += 1
                    if variant == "anderesProfil" and calls >= 2 then
                        return FakeStore.deepCopy(manager.get(userId)) -- z. B. neu geladen
                    end
                    return manager.get(userId)
                end,
                isSessionActive = function(userId: number): boolean
                    if variant == "sitzungWeg" and calls >= 2 then
                        return false
                    end
                    if variant == "schonGebucht" and calls >= 2 then
                        -- Simuliert einen anderen Weg, der die PurchaseId inzwischen eingetragen hat.
                        if table.find(live.receipts, "kauf-re") == nil then
                            table.insert(live.receipts, "kauf-re")
                        end
                    end
                    return manager.isActive(userId)
                end,
            })
            manager = a.manager
            live = load(a)
            T.expect(buy(a, "gems_550", "kauf-re")).toBe("notProcessed")
            T.expect(live.gems).toBe(0)
            T.expect(#live.purchaseLog).toBe(0)
            T.expect(live.spent.count).toBe(0)
            T.expect(world.saveCalls).toBe(0)
            T.expect(countLogs(a, "vor dem Schreiben geändert")).toBe(1)
        end
    end)

    -- Profil als Stellvertreter-Tabelle: Jede Zuweisung läuft über __newindex, die n-te wirft.
    type Proxy = { proxy: any, backing: any, writes: { string }, failAt: { n: number? }, logsAtFirstWrite: { n: number? } }
    local function proxyProfile(backing: any, logsOf: () -> number): Proxy
        local writes: { string } = {}
        local failAt: { n: number? } = { n = nil }
        local logsAtFirstWrite: { n: number? } = { n = nil }
        local proxy = setmetatable({}, {
            __index = backing,
            __newindex = function(_, key: any, value: any)
                if logsAtFirstWrite.n == nil then
                    logsAtFirstWrite.n = logsOf()
                end
                table.insert(writes, tostring(key))
                if failAt.n ~= nil and #writes == failAt.n then
                    error(`Schreibfehler bei {tostring(key)}`)
                end
                backing[key] = value
            end,
            __iter = function()
                return next, backing
            end,
        })
        return { proxy = proxy, backing = backing, writes = writes, failAt = failAt, logsAtFirstWrite = logsAtFirstWrite }
    end

    T.it("eine Zuweisung wirft beim dritten Feld: weder Teilware noch PurchaseId, der nächste Versuch bucht genau einmal", function()
        local backing: any = Profile.default(START)
        local logs: { string } = {}
        local p = proxyProfile(backing, function(): number
            return #logs
        end)
        p.failAt.n = 3 -- Reihenfolge: gems, receipts, purchaseLog (wirft), spent
        local saved: any = nil
        local purchases = Purchases.new({
            getProfile = function(): any
                return p.proxy
            end,
            isSessionActive = present,
            saveAndWait = function(_userId: number, purchaseId: string): boolean
                saved = FakeStore.deepCopy(backing)
                return Purchases.hasReceipt(saved, purchaseId)
            end,
            now = function(): number
                return START
            end,
            log = function(message: string)
                table.insert(logs, message)
            end,
            data = DATA,
        })
        local before = FakeStore.deepCopy(backing)
        local function process(): string
            return purchases.process(receipt("gems_550", "kauf-teil"))
        end
        T.expect(process()).toBe("notProcessed")
        T.expect(p.writes[1]).toBe("gems")
        T.expect(p.writes[2]).toBe("receipts")
        T.expect(p.writes[3]).toBe("purchaseLog")
        T.expect(backing).toEqual(before) -- alles zurückgesetzt
        T.expect(Purchases.hasReceipt(backing, "kauf-teil")).toBe(false)
        T.expect(saved).toBeNil() -- ohne Schreiben kein Speichern
        local found = false
        for _, line in logs do
            found = found or string.find(line, "zurückgesetzt", 1, true) ~= nil
        end
        T.expect(found).toBe(true)

        -- Der Speicher geht wieder: genau eine Gutschrift, auch bei Wiederholung.
        p.failAt.n = nil
        T.expect(process()).toBe("granted")
        T.expect(process()).toBe("granted")
        T.expect(backing.gems).toBe(550)
        T.expect(backing.receipts).toEqual({ "kauf-teil" })
        T.expect(#backing.purchaseLog).toBe(1)
        T.expect(backing.spent).toEqual({ robux = 249, count = 1 })
        T.expect(saved.gems).toBe(550)
    end)

    T.it("der Kappen-Eintrag im Protokoll steht vor dem Schreiben", function()
        local data = testData({ receiptCacheSize = 100, purchaseLogSize = 50, saveTimeoutSeconds = 30, maxGems = 1000 })
        local backing: any = Profile.default(START)
        backing.gems = 800
        local logs: { string } = {}
        local p = proxyProfile(backing, function(): number
            local count = 0
            for _, line in logs do
                if string.find(line, "gekappt", 1, true) then
                    count += 1
                end
            end
            return count
        end)
        local purchases = Purchases.new({
            getProfile = function(): any
                return p.proxy
            end,
            isSessionActive = present,
            saveAndWait = function(): boolean
                return true
            end,
            now = function(): number
                return START
            end,
            log = function(message: string)
                table.insert(logs, message)
            end,
            data = data,
        })
        local result = purchases.process({ PlayerId = USER, ProductId = productIdOf("gems_550", data), PurchaseId = "kauf-kappe" })
        T.expect(result).toBe("granted")
        T.expect(backing.gems).toBe(1000)
        T.expect(p.logsAtFirstWrite.n).toBe(1)
    end)
end)

-- Security-Review 4.1 (N1, N8): Wartegrenzen.
T.describe("Kaufabwicklung: Wartegrenzen", function()
    T.it("PROFILE_WAIT_SECONDS ist mindestens so lang wie LOAD_TIMEOUT_SECONDS in PlayerData", function()
        local digits = string.match(PLAYER_DATA_SOURCE, "local LOAD_TIMEOUT_SECONDS%s*=%s*([%d_]+)")
        local loadTimeout = if digits ~= nil then tonumber((string.gsub(digits, "_", ""))) else nil
        T.expect(loadTimeout ~= nil).toBe(true)
        T.expect(Purchases.PROFILE_WAIT_SECONDS >= (loadTimeout :: number)).toBe(true)
    end)

    T.it("ein zweiter gleichzeitiger Aufruf gibt nie vor dem ersten auf (Laden fast bis zur Grenze, dann langsames Speichern)", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local a: Server
        a = newServer(world, "A", {
            isLoading = function(userId: number): boolean
                return not a.manager.isLoaded(userId)
            end,
        })
        local loadAt = START + Purchases.PROFILE_WAIT_SECONDS - 5
        local saveDelay = Economy.purchases.saveTimeoutSeconds - 1
        local first = startBuy(a, "gems_550", "kauf-lang")
        local second = startBuy(a, "gems_550", "kauf-lang")
        local loadedAt: number? = nil
        for _ = 1, 100_000 do
            if isDone(first) and isDone(second) then
                break
            end
            if loadedAt == nil and a.clock.time >= loadAt then
                load(a)
                loadedAt = a.clock.time
            end
            if loadedAt ~= nil and a.clock.time >= (loadedAt :: number) + saveDelay then
                FakeStore.flushSaves(world)
            end
            resume(first)
            resume(second)
        end
        T.expect(first.result).toBe("granted")
        T.expect(second.result).toBe("granted")
        T.expect(a.clock.time - START > Purchases.PROFILE_WAIT_SECONDS).toBe(true) -- wirklich so lange
        T.expect(world.saved[KEY].gems).toBe(550)
        T.expect(#a.manager.get(USER).purchaseLog).toBe(1)
    end)
end)

-- Security-Review 4.1 (N5): Produkte mit echter ProductId brauchen einen Handler.
T.describe("Kaufabwicklung: fehlende Handler", function()
    T.it("missingHandlers nennt Produkte mit ProductId ohne Handler (keine Gamepasses), Registrieren entfernt sie", function()
        local a = newServer(FakeStore.newWorld(), "A")
        local expected: { string } = {}
        for _, product in Products.list do
            if product.kind ~= "gamepass" then
                table.insert(expected, product.id)
            end
        end
        table.sort(expected)
        T.expect(a.purchases.missingHandlers()).toEqual(expected)
        a.purchases.register("coin_boost", function(): Purchases.Prepared?
            return nil
        end)
        T.expect(table.find(a.purchases.missingHandlers(), "coin_boost")).toBeNil()
        T.expect(#a.purchases.missingHandlers()).toBe(#expected - 1)
        -- Gem-Pakete haben ihren eingebauten Handler, Platzhalter (ProductId 0) fehlen nie.
        local real = newServer(FakeStore.newWorld(), "B", { data = REAL_DATA })
        T.expect(real.purchases.missingHandlers()).toEqual({})
    end)
end)

-- Security-Review 4.1 (N9): Alte Beleg-Tabellen werden beim Laden nicht gekürzt.
T.describe("Kaufabwicklung: alte Beleg-Tabellen", function()
    T.it("mehr alte PurchaseIds als receiptCacheSize: ein wiederholter alter Beleg nach dem Laden bucht nicht neu", function()
        local world = FakeStore.newWorld()
        local limit = Economy.purchases.receiptCacheSize
        local old: any = Profile.default(START)
        old.version = 3
        old.purchaseLog = nil
        old.spent = nil
        old.receipts = {}
        for index = 1, limit + 50 do
            old.receipts[`alt_{string.format("%03d", index)}`] = true
        end
        world.saved[KEY] = old
        local a = newServer(world, "A")
        local profile = load(a)
        T.expect(#profile.receipts).toBe(limit + 50)
        -- "alt_001" stünde beim Kürzen ganz vorn (alphabetisch, Reihenfolge unbekannt). Wiederholt
        -- Roblox den Beleg nach dem Beitreten, steht er noch im Profil und im gespeicherten Stand:
        -- PurchaseGranted ohne Gutschrift und ohne neues Speichern.
        local saves = world.saveCalls
        T.expect(buy(a, "gems_550", "alt_001")).toBe("granted")
        T.expect(buy(a, "gems_550", "alt_050")).toBe("granted")
        T.expect(profile.gems).toBe(0)
        T.expect(#profile.purchaseLog).toBe(0)
        T.expect(world.saveCalls).toBe(saves)
        -- Erst das nächste normale Speichern kürzt auf receiptCacheSize.
        FakeStore.autosave(world, KEY)
        T.expect(#world.saved[KEY].receipts).toBe(limit)
        T.expect(#profile.receipts).toBe(limit)
    end)
end)

T.describe("Studio-Hilfe (processPack)", function()
    T.it("ohne allowDebug gesperrt: NotProcessedYet, keine Gutschrift", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A")
        local profile = load(a)
        local result = finish(start(function(): string
            return a.purchases.processPack(USER, "gems_550", "fest1")
        end))
        T.expect(result).toBe("notProcessed")
        T.expect(profile.gems).toBe(0)
        T.expect(countLogs(a, "gesperrt")).toBe(1)
    end)

    T.it("mit allowDebug: Paket über die Paket-ID, feste PurchaseId dreimal ergibt eine Gutschrift und eine Meldung", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = REAL_DATA, allowDebug = true })
        local profile = load(a)
        for _ = 1, 3 do
            local result = finish(start(function(): string
                return a.purchases.processPack(USER, "gems_550", "fest1")
            end))
            T.expect(result).toBe("granted")
        end
        T.expect(profile.gems).toBe(550)
        T.expect(profile.receipts).toEqual({ Purchases.DEBUG_PREFIX .. "fest1" })
        T.expect(world.saved[KEY].gems).toBe(550)
        T.expect(#a.notes).toBe(1)
        -- Eine andere PurchaseId ist ein neuer Kauf.
        finish(start(function(): string
            return a.purchases.processPack(USER, "gems_550", "fest2")
        end))
        T.expect(profile.gems).toBe(1100)
    end)

    T.it("unbekannte Pakete, andere Produkte und kaputte PurchaseIds: NotProcessedYet", function()
        local world = FakeStore.newWorld()
        local a = newServer(world, "A", { data = REAL_DATA, allowDebug = true })
        local profile = load(a)
        for _, args in { { "gems_999", "x" }, { "coin_boost", "x" }, { "gems_550", "" }, { "gems_550", string.rep("y", 200) } } do
            local result = finish(start(function(): string
                return a.purchases.processPack(USER, args[1], args[2])
            end))
            T.expect(result).toBe("notProcessed")
        end
        T.expect(profile.gems).toBe(0)
    end)
end)

T.finish()
