--!strict
-- Paket 1.1: Spielerdaten laden und speichern (Ablauf mit Fake-Speicher).

local T = require("./lib/expect")
local FakeStore = require("./lib/fakestore")
local PlayerSession = require("../src/shared/Logic/PlayerSession")
local Profile = require("../src/shared/Logic/Profile")
local Migrations = require("../src/shared/Logic/Migrations")
local Economy = require("../src/shared/Data/Economy")

local USER = 42
local KEY = PlayerSession.keyFor(USER)
local START = 1_700_000_000

type Harness = {
    manager: PlayerSession.Manager,
    kicks: { { userId: number, message: string } },
    logs: { string },
    clock: { time: number },
}

local function newHarness(world: FakeStore.World, serverName: string, migrations: any?, wait: ((number) -> ())?): Harness
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
        -- Paket 4.1: Fake-Uhr. Warten rückt die Uhr vor und lässt den Test eingreifen.
        clock = function()
            return clock.time
        end,
        wait = if wait ~= nil
            then function(seconds: number)
                clock.time += seconds
                wait(seconds)
            end
            else nil,
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
            [2] = function(p: any) -- Paket 2.7: nur die Version zählt hier
                return p
            end,
            [3] = function(p: any) -- Paket 4.1: nur die Version zählt hier
                return p
            end,
            [4] = function(p: any) -- Paket 4.3: nur die Version zählt hier
                return p
            end,
            [5] = function(p: any) -- Paket 4.4: nur die Version zählt hier
                return p
            end,
            [6] = function(p: any) -- Paket 4.5: nur die Version zählt hier
                return p
            end,
        }
        local h = newHarness(world, "A", steps)
        local profile: any = h.manager.load(USER, present)
        T.expect(profile.version).toBe(Profile.CURRENT_VERSION)
        T.expect(profile.gems).toBe(77)
        h.manager.release(USER)
        T.expect(world.saved[KEY].version).toBe(Profile.CURRENT_VERSION)
        -- Fehlende Felder werden tief aufgefüllt: settings.autoDig kommt seit Paket 4.4 aus dem Standardprofil.
        T.expect(world.saved[KEY].settings).toEqual({ music = true, autoDig = true })
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

-- Paket 4.1: Speichern anstoßen und warten, bis der gespeicherte Stand eine Bedingung erfüllt.
T.describe("PlayerSession: bestätigtes Speichern (Paket 4.1)", function()
    local function hasMarker(saved: any): boolean
        return type(saved) == "table" and saved.marker == "ja"
    end

    T.it("isActive: erst nach dem Laden, nicht mehr nach dem Verlassen oder einer Übernahme", function()
        local world = FakeStore.newWorld()
        local h = newHarness(world, "A")
        T.expect(h.manager.isActive(USER)).toBe(false)
        h.manager.load(USER, present)
        T.expect(h.manager.isActive(USER)).toBe(true)
        h.manager.release(USER)
        T.expect(h.manager.isActive(USER)).toBe(false)
        h.manager.load(USER, present)
        FakeStore.endFromOutside(world, KEY)
        T.expect(h.manager.isActive(USER)).toBe(false)
    end)

    T.it("saveAndWait: true erst, wenn der gespeicherte Stand die Bedingung erfüllt", function()
        local world = FakeStore.newWorld()
        local h = newHarness(world, "A", nil, function() end)
        local profile: any = h.manager.load(USER, present)
        T.expect(h.manager.isSaved(USER, hasMarker)).toBe(false)
        profile.marker = "ja"
        T.expect(h.manager.isSaved(USER, hasMarker)).toBe(false) -- nur im Speicher, nicht gespeichert
        local writes = world.writes
        T.expect(h.manager.saveAndWait(USER, hasMarker, 30)).toBe(true)
        T.expect(world.writes).toBe(writes + 1)
        T.expect(world.saved[KEY].marker).toBe("ja")
        T.expect(h.manager.isSaved(USER, hasMarker)).toBe(true)
        -- Schon gespeichert: kein weiteres Speichern nötig.
        T.expect(h.manager.saveAndWait(USER, hasMarker, 30)).toBe(true)
        T.expect(world.writes).toBe(writes + 1)
    end)

    T.it("saveAndWait wartet auf ein verzögertes Speichern", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local polls = 0
        local h = newHarness(world, "A", nil, function()
            polls += 1
            if polls == 3 then
                FakeStore.flushSaves(world) -- das Speichern kommt nach drei Wartezyklen an
            end
        end)
        local profile: any = h.manager.load(USER, present)
        profile.marker = "ja"
        T.expect(h.manager.saveAndWait(USER, hasMarker, 30)).toBe(true)
        T.expect(polls).toBe(3)
        T.expect(world.saved[KEY].marker).toBe("ja")
    end)

    T.it("Speichern schlägt fehl: false nach der Zeitgrenze, nichts geschrieben", function()
        local world = FakeStore.newWorld()
        world.failSaves = true
        local h = newHarness(world, "A", nil, function() end)
        local profile: any = h.manager.load(USER, present)
        profile.marker = "ja"
        T.expect(h.manager.saveAndWait(USER, hasMarker, 30)).toBe(false)
        T.expect(h.clock.time - START >= 30).toBe(true)
        T.expect(world.saved[KEY]).toBeNil()
        T.expect(profile.marker).toBe("ja") -- der Stand im Speicher bleibt
    end)

    T.it("Sitzung von außen übernommen (ohne letztes Speichern): false erst nach der Zeitgrenze", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local h = newHarness(world, "A", nil, function()
            FakeStore.endFromOutside(world, KEY)
        end)
        local profile: any = h.manager.load(USER, present)
        profile.marker = "ja"
        T.expect(h.manager.saveAndWait(USER, hasMarker, 30)).toBe(false)
        -- Kein Abbruch beim Sitzungsende: bis zur Zeitgrenze könnte noch ein letztes Speichern kommen.
        T.expect(h.clock.time - START >= 30).toBe(true)
        T.expect(FakeStore.flushSaves(world)).toBe(1) -- das verzögerte Speichern schreibt nicht mehr
        T.expect(world.saved[KEY]).toBeNil()
    end)

    T.it("Fake-Speicher beendet wie ProfileStore: erst inaktiv und onSessionEnd, danach schreiben und onAfterSave", function()
        local world = FakeStore.newWorld()
        local store = FakeStore.newServer(world, "A")
        local session = store.startSession(KEY, function(): boolean
            return false
        end)
        session.setData({ marker = "ja" })
        local order: { string } = {}
        session.onSave(function()
            table.insert(order, `onSave aktiv={tostring(session.isActive())}`)
        end)
        session.onSessionEnd(function()
            table.insert(order, `onSessionEnd gespeichert={tostring(world.saved[KEY] ~= nil)}`)
        end)
        session.onAfterSave(function(saved: any)
            table.insert(order, `onAfterSave aktiv={tostring(session.isActive())} marker={tostring(saved.marker)}`)
        end)
        session.endSession()
        T.expect(order).toEqual({
            "onSave aktiv=true",
            "onSessionEnd gespeichert=false",
            "onAfterSave aktiv=false marker=ja",
        })
        T.expect(session.lastSaved().marker).toBe("ja")
        T.expect(world.locks[KEY]).toBeNil()
    end)

    T.it("Spieler verlässt das Spiel während des Wartens: das letzte Speichern nach dem Sitzungsende zählt", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local h: Harness
        local polls = 0
        local sawInactive = false
        h = newHarness(world, "A", nil, function()
            polls += 1
            if polls == 2 then
                h.manager.release(USER) -- letztes Speichern ist angestoßen, aber noch nicht geschrieben
            elseif polls == 3 then
                sawInactive = not h.manager.isActive(USER) and world.saved[KEY] == nil
            elseif polls == 5 then
                FakeStore.flushSaves(world) -- jetzt erst kommt das letzte Schreiben an
            end
        end)
        local profile: any = h.manager.load(USER, present)
        profile.marker = "ja"
        T.expect(h.manager.saveAndWait(USER, hasMarker, 30)).toBe(true)
        T.expect(sawInactive).toBe(true)
        T.expect(polls).toBe(5)
        T.expect(world.saved[KEY].marker).toBe("ja")
    end)

    T.it("Spieler verlässt das Spiel und das letzte Speichern scheitert: false nach der Zeitgrenze", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local h: Harness
        local polls = 0
        h = newHarness(world, "A", nil, function()
            polls += 1
            if polls == 2 then
                h.manager.release(USER)
                world.failSaves = true
                FakeStore.flushSaves(world)
            end
        end)
        local profile: any = h.manager.load(USER, present)
        profile.marker = "ja"
        T.expect(h.manager.saveAndWait(USER, hasMarker, 30)).toBe(false)
        T.expect(h.clock.time - START >= 30).toBe(true)
        T.expect(world.saved[KEY]).toBeNil()
    end)

    T.it("bestätigt auch über den zuletzt gespeicherten Stand, wenn kein onAfterSave mehr kommt", function()
        local world = FakeStore.newWorld()
        world.delaySaves = true
        local h: Harness
        local polls = 0
        h = newHarness(world, "A", nil, function()
            polls += 1
            if polls == 2 then
                h.manager.release(USER)
                FakeStore.flushSaves(world)
            end
        end)
        local profile: any = h.manager.load(USER, present)
        -- Wie ein Speicher, der beim Beenden alle Rückrufe trennt: Der Rückruf kommt nie an, nur
        -- der zuletzt gespeicherte Stand (LastSavedData) ändert sich.
        local session = world.sessions[KEY]
        local realOnAfterSave = session.onAfterSave
        session.onAfterSave = function(_callback: any): () -> ()
            return realOnAfterSave(function() end)
        end
        profile.marker = "ja"
        T.expect(h.manager.saveAndWait(USER, hasMarker, 30)).toBe(true)
        T.expect(h.clock.time - START < 30).toBe(true)
    end)

    T.it("ein altes Profil mit mehr Belegen als receiptCacheSize: beim Laden alle, beim Speichern gekürzt", function()
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
        local h = newHarness(world, "A", nil, function() end)
        local profile: any = h.manager.load(USER, present)
        T.expect(#profile.receipts).toBe(limit + 50) -- keine PurchaseId geht beim Laden verloren
        FakeStore.autosave(world, KEY)
        T.expect(#world.saved[KEY].receipts).toBe(limit)
        T.expect(#profile.receipts).toBe(limit)
    end)

    T.it("nicht geladen, ohne Warten oder mit fehlerhafter Bedingung: false ohne Fehler", function()
        local world = FakeStore.newWorld()
        local noWait = newHarness(world, "A")
        T.expect(noWait.manager.saveAndWait(USER, hasMarker, 30)).toBe(false)
        local profile: any = noWait.manager.load(USER, present)
        profile.marker = "ja"
        T.expect(noWait.manager.saveAndWait(USER, hasMarker, 30)).toBe(false) -- kein Warten eingestellt
        T.expect(noWait.manager.saveAndWait(USER, function(): boolean
            error("kaputt")
        end, 30)).toBe(false)
    end)
end)

T.finish()
