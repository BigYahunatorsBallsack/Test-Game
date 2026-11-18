--!strict
-- Paket 1.1: Spielerdaten laden und speichern (Ablauf mit Fake-Speicher).

local T = require("./lib/expect")
local FakeStore = require("./lib/fakestore")
local PlayerSession = require("../src/shared/Logic/PlayerSession")
local Profile = require("../src/shared/Logic/Profile")
local Migrations = require("../src/shared/Logic/Migrations")

local USER = 42
local KEY = PlayerSession.keyFor(USER)
local START = 1_700_000_000

type Harness = {
    manager: PlayerSession.Manager,
    kicks: { { userId: number, message: string } },
    logs: { string },
    clock: { time: number },
}

local function newHarness(world: FakeStore.World, serverName: string, migrations: any?): Harness
    local kicks = {}
    local logs = {}
    local clock = { time = START }
    local manager = PlayerSession.new({
        store = FakeStore.newServer(world, serverName),
        now = function()
            return clock.time
        end,
        kick = function(userId: number, message: string)
            table.insert(kicks, { userId = userId, message = message })
        end,
        log = function(message: string)
            table.insert(logs, message)
        end,
        migrations = migrations,
    })
    return { manager = manager, kicks = kicks, logs = logs, clock = clock }
end

local function present(): boolean
    return true
end

T.describe("PlayerSession", function()
    T.it("neuer Spieler: Standardprofil mit aktueller Version, erst danach geladen", function()
        local world = FakeStore.newWorld()
        local h = newHarness(world, "A")
        T.expect(h.manager.isLoaded(USER)).toBe(false)
        local loadedEvents = 0
        h.manager.onLoaded(function(userId: number)
            T.expect(userId).toBe(USER)
            loadedEvents += 1
        end)
        local profile = h.manager.load(USER, present)
        T.expect(profile).toEqual(Profile.default(START))
        T.expect((profile :: any).version).toBe(Profile.CURRENT_VERSION)
        T.expect(h.manager.isLoaded(USER)).toBe(true)
        T.expect(loadedEvents).toBe(1)
        T.expect(#h.kicks).toBe(0)
    end)

    T.it("Münzen, Gems, Inventar, Knoten und Zonen überleben einen Neustart", function()
        local world = FakeStore.newWorld()
        local a = newHarness(world, "A")
        local profile: any = a.manager.load(USER, present)
        profile.coins = { m = 1.5, e = 18 }
        profile.gems = 250
        profile.inventory.skins.desert_hat = 1
        profile.nodes.collect_tool_2 = true
        profile.zones.oasis = true
        a.manager.release(USER)

        -- "Neustart": neuer Server, gleiche Welt
        local b = newHarness(world, "B")
        local again: any = b.manager.load(USER, present)
        T.expect(again.coins).toEqual({ m = 1.5, e = 18 })
        T.expect(again.gems).toBe(250)
        T.expect(again.inventory.skins).toEqual({ desert_hat = 1 })
        T.expect(again.nodes).toEqual({ collect_tool_2 = true })
        T.expect(again.zones).toEqual({ dunes = true, oasis = true })
    end)

    T.it("altes Profil wird beim Laden migriert und in neuer Version gespeichert", function()
        local world = FakeStore.newWorld()
        local old: any = Profile.default(START)
        old.gems = 77
        old.version = 1
        world.saved[KEY] = old
        local steps: { [number]: Migrations.Step } = {
            [1] = function(p: any)
                p.settings = { music = true }
                return p
            end,
        }
        local h = newHarness(world, "A", steps)
        local profile: any = h.manager.load(USER, present)
        T.expect(profile.version).toBe(2)
        T.expect(profile.gems).toBe(77)
        h.manager.release(USER)
        T.expect(world.saved[KEY].version).toBe(2)
        T.expect(world.saved[KEY].settings).toEqual({ music = true })
    end)

    T.it("zu neues Profil: Spieler wird entfernt, gespeicherte Daten bleiben unverändert", function()
        local world = FakeStore.newWorld()
        local future: any = Profile.default(START)
        future.version = Profile.CURRENT_VERSION + 1
        future.newFeature = { level = 3 }
        world.saved[KEY] = FakeStore.deepCopy(future)
        local h = newHarness(world, "A")
        h.clock.time = START + 999
        T.expect(h.manager.load(USER, present)).toBeNil()
        T.expect(h.manager.isLoaded(USER)).toBe(false)
        T.expect(#h.kicks).toBe(1)
        T.expect(h.kicks[1].message).toBe(PlayerSession.MESSAGES.tooNew)
        T.expect(world.saved[KEY]).toEqual(future) -- auch lastSeen unverändert
        T.expect(world.locks[KEY]).toBeNil()
    end)

    T.it("Laden schlägt fehl: Spieler wird entfernt, kein leeres Profil wird gespeichert", function()
        local world = FakeStore.newWorld()
        local existing: any = Profile.default(START)
        existing.gems = 500
        world.saved[KEY] = FakeStore.deepCopy(existing)
        world.failNextStart = true
        local h = newHarness(world, "A")
        T.expect(h.manager.load(USER, present)).toBeNil()
        T.expect(h.manager.isLoaded(USER)).toBe(false)
        T.expect(#h.kicks).toBe(1)
        T.expect(h.kicks[1].message).toBe(PlayerSession.MESSAGES.loadFailed)
        T.expect(world.writes).toBe(0)
        T.expect(world.saved[KEY]).toEqual(existing)
    end)

    T.it("Migration mit Fehler: Spieler wird entfernt, Daten bleiben unverändert", function()
        local world = FakeStore.newWorld()
        local old: any = Profile.default(START)
        old.version = 1
        world.saved[KEY] = FakeStore.deepCopy(old)
        local steps: { [number]: Migrations.Step } = {
            [1] = function(_p: any): any
                error("kaputter Schritt")
            end,
        }
        local h = newHarness(world, "A", steps)
        T.expect(h.manager.load(USER, present)).toBeNil()
        T.expect(h.kicks[1].message).toBe(PlayerSession.MESSAGES.loadFailed)
        T.expect(world.saved[KEY]).toEqual(old)
        T.expect(world.locks[KEY]).toBeNil()
    end)

    T.it("Spieler geht während des Ladens: Sitzung wird beendet, nichts bleibt offen", function()
        local world = FakeStore.newWorld()
        world.locks[KEY] = "anderer Server" -- Laden muss warten
        local h = newHarness(world, "A")
        local isHere = true
        local result: any = "läuft"
        local co = coroutine.create(function()
            result = h.manager.load(USER, function()
                return isHere
            end)
        end)
        coroutine.resume(co)
        T.expect(coroutine.status(co)).toBe("suspended")
        -- Spieler geht, dann gibt der andere Server frei
        isHere = false
        h.manager.release(USER)
        world.locks[KEY] = nil
        coroutine.resume(co)
        T.expect(coroutine.status(co)).toBe("dead")
        T.expect(result).toBeNil()
        T.expect(h.manager.isLoaded(USER)).toBe(false)
        T.expect(world.locks[KEY]).toBeNil()
        T.expect(#h.kicks).toBe(0)
    end)

    T.it("Spieler geht, nachdem die Sitzung offen ist, aber vor dem Melden: Sitzung wird freigegeben", function()
        local world = FakeStore.newWorld()
        local h = newHarness(world, "A")
        local checks = 0
        -- Erste Abfrage (beim Öffnen): noch da. Danach: weg.
        local profile = h.manager.load(USER, function()
            checks += 1
            return checks <= 1
        end)
        T.expect(profile).toBeNil()
        T.expect(h.manager.isLoaded(USER)).toBe(false)
        T.expect(world.locks[KEY]).toBeNil()
        T.expect(#h.kicks).toBe(0)
    end)

    T.it("Server-Wechsel: B wartet, bis A freigibt, und lädt dann den Stand von A", function()
        local world = FakeStore.newWorld()
        local a = newHarness(world, "A")
        local b = newHarness(world, "B")
        local onA: any = a.manager.load(USER, present)
        onA.gems = 1234

        local result: any = nil
        local co = coroutine.create(function()
            result = b.manager.load(USER, present)
        end)
        coroutine.resume(co)
        T.expect(coroutine.status(co)).toBe("suspended")
        T.expect(b.manager.isLoaded(USER)).toBe(false)

        a.manager.release(USER)
        coroutine.resume(co)
        T.expect(coroutine.status(co)).toBe("dead")
        T.expect(b.manager.isLoaded(USER)).toBe(true)
        T.expect(result.gems).toBe(1234)
        T.expect(world.locks[KEY]).toBe("B")
    end)

    T.it("anderer Server übernimmt die Sitzung: Spieler wird hier entfernt", function()
        local world = FakeStore.newWorld()
        local a = newHarness(world, "A")
        local profile: any = a.manager.load(USER, present)
        local writesBefore = world.writes
        profile.gems = 999
        FakeStore.endFromOutside(world, KEY)
        T.expect(world.writes).toBe(writesBefore)
        T.expect(a.manager.isLoaded(USER)).toBe(false)
        T.expect(#a.kicks).toBe(1)
        T.expect(a.kicks[1].message).toBe(PlayerSession.MESSAGES.sessionTaken)
    end)

    T.it("lastSeen wird beim Autosave und beim Verlassen auf die aktuelle Zeit gesetzt", function()
        local world = FakeStore.newWorld()
        local h = newHarness(world, "A")
        h.manager.load(USER, present)
        h.clock.time = START + 300
        FakeStore.autosave(world, KEY)
        T.expect(world.saved[KEY].lastSeen).toBe(START + 300)
        h.clock.time = START + 450
        h.manager.release(USER)
        T.expect(world.saved[KEY].lastSeen).toBe(START + 450)
        T.expect(world.saved[KEY].createdAt).toBe(START)
    end)

    T.it("Profil-Prüfung für Remotes: vor dem Laden nein, danach ja, nach dem Verlassen nein", function()
        local world = FakeStore.newWorld()
        local h = newHarness(world, "A")
        T.expect(h.manager.isLoaded(USER)).toBe(false)
        T.expect(h.manager.get(USER)).toBeNil()
        h.manager.load(USER, present)
        T.expect(h.manager.isLoaded(USER)).toBe(true)
        T.expect(h.manager.get(USER)).toBeTruthy()
        h.manager.release(USER)
        T.expect(h.manager.isLoaded(USER)).toBe(false)
        T.expect(h.manager.get(USER)).toBeNil()
        T.expect(h.manager.isLoaded(USER + 1)).toBe(false)
    end)

    T.it("kaputte Felder werden beim Laden einzeln repariert und gemeldet", function()
        local world = FakeStore.newWorld()
        local broken: any = Profile.default(START)
        broken.coins = "abc"
        broken.gems = 0 / 0
        broken.tank = { m = "x", e = 2 }
        broken.windCrystals = 9
        broken.nodes = { collect_tool_2 = true }
        world.saved[KEY] = broken
        local h = newHarness(world, "A")
        local profile: any = h.manager.load(USER, present)
        T.expect(profile.coins).toEqual({ m = 0, e = 0 })
        T.expect(profile.gems).toBe(0)
        T.expect(profile.tank).toEqual({ m = 0, e = 0 })
        T.expect(profile.windCrystals).toBe(9)
        T.expect(profile.nodes).toEqual({ collect_tool_2 = true })
        T.expect(#h.logs).toBe(3)
        T.expect(#h.kicks).toBe(0)
    end)
end)

T.describe("PlayerSession: schneller Rejoin und Speichern", function()
    T.it("Rejoin während das alte Laden noch läuft: busy bis es fertig ist, dann lädt der neue Spieler", function()
        local world = FakeStore.newWorld()
        world.locks[KEY] = "anderer Server"
        local h = newHarness(world, "A")
        local firstHere = true
        local first = coroutine.create(function()
            h.manager.load(USER, function()
                return firstHere
            end)
        end)
        coroutine.resume(first)
        -- Spieler geht und kommt sofort wieder
        firstHere = false
        h.manager.release(USER)
        T.expect(h.manager.isBusy(USER)).toBe(true)
        T.expect(function()
            h.manager.load(USER, present)
        end).toThrow("schon geladen")
        -- Das alte Laden bricht beim nächsten Versuch ab
        coroutine.resume(first)
        T.expect(coroutine.status(first)).toBe("dead")
        T.expect(h.manager.isBusy(USER)).toBe(false)
        world.locks[KEY] = nil
        local profile = h.manager.load(USER, present)
        T.expect(profile).toBeTruthy()
        T.expect(h.manager.isLoaded(USER)).toBe(true)
        T.expect(#h.kicks).toBe(0)
    end)

    T.it("vor dem Speichern werden NaN, unendlich und Nicht-JSON-Werte entfernt", function()
        local world = FakeStore.newWorld()
        local h = newHarness(world, "A")
        local profile: any = h.manager.load(USER, present)
        profile.gems = 0 / 0
        profile.coins = { m = 5, e = math.huge }
        profile.finds.good = 3
        profile.finds.bad = math.huge
        profile.inventory.skins[7] = 1
        profile.receipts.fn = function() end
        FakeStore.autosave(world, KEY)
        local saved = world.saved[KEY]
        T.expect(saved.gems).toBe(0)
        T.expect(saved.coins).toEqual({ m = 0, e = 0 })
        T.expect(saved.finds).toEqual({ good = 3 })
        T.expect(saved.inventory.skins).toEqual({})
        T.expect(saved.receipts).toEqual({})
        T.expect(#h.logs).toBe(5)
    end)
end)

T.describe("Profile.sanitize", function()
    T.it("ein gültiges Profil bleibt unverändert und ohne Warnung", function()
        local profile: any = Profile.default(START)
        profile.coins = { m = 3, e = 40 }
        profile.pity.event = { sinceEpic = 2, sinceLegendary = 9 }
        profile.unknownField = "bleibt"
        local before = FakeStore.deepCopy(profile)
        T.expect(#Profile.sanitize(profile, START)).toBe(0)
        T.expect(profile).toEqual(before)
    end)

    T.it("falscher Typ einer ganzen Gruppe setzt nur diese Gruppe zurück", function()
        local profile: any = Profile.default(START)
        profile.gems = 5
        profile.daily = "kaputt"
        profile.boosts.coinsUntil = math.huge
        local warnings = Profile.sanitize(profile, START)
        T.expect(#warnings).toBe(2)
        T.expect(profile.daily).toEqual({ streak = 0, lastDay = 0 })
        T.expect(profile.boosts.coinsUntil).toBe(0)
        T.expect(profile.gems).toBe(5)
    end)
end)

T.finish()
