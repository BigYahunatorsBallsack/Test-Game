--!strict
-- Ablauf beim Laden und Freigeben von Spielerprofilen. Rein, ohne Roblox-API.
-- Den Speicher (im Spiel: ProfileStore) bekommt das Modul als Adapter, damit Lune den ganzen
-- Ablauf mit einem Fake-Speicher testen kann (Sitzungssperre, Server-Wechsel, Fehlerfälle).
--
-- Regeln:
--  * Ein Spieler gilt erst als geladen, wenn sein Profil migriert und repariert ist.
--  * Profil zu neu, Laden fehlgeschlagen oder Migration mit Fehler: Spieler wird mit Meldung
--    entfernt, die gespeicherten Daten werden nicht verändert (kein leeres Profil).
--  * Verlässt der Spieler das Spiel während des Ladens, wird die Sitzung sofort beendet.
--  * Vor jedem Speichern wird lastSeen auf die aktuelle Zeit gesetzt (Offline-Ertrag, 5.3).
--  * Beendet ein anderer Server die Sitzung (Server-Wechsel), wird der Spieler hier entfernt.

local Profile = require("./Profile")

-- Eine offene Sitzung im Speicher (im Spiel: ein ProfileStore-Profil).
export type StoreSession = {
    getData: () -> any,
    setData: (data: any) -> (),
    onSave: (callback: () -> ()) -> (), -- läuft direkt vor jedem Speichern
    onSessionEnd: (callback: () -> ()) -> (), -- läuft, wenn die Sitzung endet (auch extern)
    endSession: () -> (), -- speichert ein letztes Mal und gibt die Sperre frei
}

export type Store = {
    -- Öffnet eine Sitzung. Darf warten (Sitzungssperre). Gibt nil zurück, wenn es nicht
    -- klappt oder `cancel()` true liefert.
    startSession: (key: string, cancel: () -> boolean) -> StoreSession?,
}

export type Deps = {
    store: Store,
    now: () -> number, -- Unix-Zeit
    kick: (userId: number, message: string) -> (),
    log: (message: string) -> (),
    migrations: { [number]: any }?, -- nur für Tests (Standard: Migrations.steps)
}

type Entry = { session: StoreSession, profile: Profile.Profile }
type LoadJob = { released: boolean }

-- Meldungen an den Spieler. Stehen hier gesammelt, damit sie leicht zu ändern sind.
local MESSAGES = {
    loadFailed = "Dein Spielstand konnte nicht geladen werden. Bitte tritt erneut bei.",
    tooNew = "Dieser Server ist veraltet. Bitte tritt erneut bei, um einen neuen Server zu bekommen.",
    sessionTaken = "Dein Spielstand wurde auf einem anderen Server geöffnet.",
}

local PlayerSession = {}
PlayerSession.MESSAGES = MESSAGES

function PlayerSession.keyFor(userId: number): string
    return `Player_{userId}`
end

export type Manager = {
    load: (userId: number, isPresent: () -> boolean) -> Profile.Profile?,
    release: (userId: number) -> (),
    isBusy: (userId: number) -> boolean,
    get: (userId: number) -> Profile.Profile?,
    isLoaded: (userId: number) -> boolean,
    onLoaded: (callback: (userId: number, profile: Profile.Profile) -> ()) -> (),
}

function PlayerSession.new(deps: Deps): Manager
    local loaded: { [number]: Entry } = {}
    -- Laufende Ladevorgänge. Jeder Vorgang hat seinen eigenen Datensatz, damit ein schneller
    -- Rejoin den alten Vorgang nicht durcheinanderbringt.
    local loading: { [number]: LoadJob } = {}
    local loadedCallbacks: { (number, Profile.Profile) -> () } = {}

    local manager = {} :: Manager

    local function fail(userId: number, message: string, reason: string)
        deps.log(`Spieler {userId}: {reason}`)
        deps.kick(userId, message)
    end

    local function logWarnings(userId: number, prefix: string, warnings: { string })
        for _, warning in warnings do
            deps.log(`Spieler {userId}: {prefix}: {warning}`)
        end
    end

    function manager.load(userId: number, isPresent: () -> boolean): Profile.Profile?
        if loaded[userId] ~= nil or loading[userId] ~= nil then
            error(`PlayerSession: Spieler {userId} wird schon geladen (vorher isBusy prüfen)`)
        end
        local job: LoadJob = { released = false }
        loading[userId] = job

        local function gone(): boolean
            return job.released or not isPresent()
        end

        local session = deps.store.startSession(PlayerSession.keyFor(userId), gone)
        if loading[userId] == job then
            loading[userId] = nil
        end

        if session == nil then
            if not gone() then
                fail(userId, MESSAGES.loadFailed, "Sitzung konnte nicht geöffnet werden")
            end
            return nil
        end
        if gone() then
            -- Während des Ladens gegangen: Sitzung sofort freigeben, Daten unverändert.
            session.endSession()
            return nil
        end

        local raw = session.getData()
        if type(raw) == "table" and next(raw) == nil then
            raw = nil -- ProfileStore liefert für neue Spieler eine leere Tabelle
        end

        local ok, profileOrError, status = pcall(Profile.migrate, raw, deps.migrations, deps.now())
        if not ok then
            -- Daten nicht anfassen: Sitzung beenden speichert sie unverändert zurück.
            session.endSession()
            fail(userId, MESSAGES.loadFailed, `Migration fehlgeschlagen: {tostring(profileOrError)}`)
            return nil
        end
        if status == "too_new" then
            session.endSession()
            fail(userId, MESSAGES.tooNew, "Profil ist neuer als dieser Server")
            return nil
        end

        local profile: Profile.Profile = profileOrError
        logWarnings(userId, "Profil repariert", Profile.sanitize(profile, deps.now()))

        session.setData(profile)
        local entry: Entry = { session = session, profile = profile }
        session.onSave(function()
            profile.lastSeen = deps.now()
            -- Nichts Ungültiges (NaN, unendlich, Nicht-JSON) darf in den DataStore gelangen,
            -- sonst schlägt das Speichern fehl und Fortschritt geht verloren.
            logWarnings(userId, "Vor dem Speichern repariert", Profile.sanitize(profile, deps.now()))
        end)
        session.onSessionEnd(function()
            if loaded[userId] == entry then
                -- Nicht von uns beendet: ein anderer Server hat die Sitzung übernommen.
                loaded[userId] = nil
                fail(userId, MESSAGES.sessionTaken, "Sitzung von außen beendet")
            end
        end)
        loaded[userId] = entry

        for _, callback in loadedCallbacks do
            callback(userId, profile)
        end
        return profile
    end

    function manager.release(userId: number)
        local job = loading[userId]
        if job ~= nil then
            -- Der Ladevorgang bricht beim nächsten Versuch ab (gone() ist true). Er bleibt
            -- eingetragen, bis startSession zurückkommt, damit isBusy so lange true bleibt.
            job.released = true
            return
        end
        local entry = loaded[userId]
        if entry == nil then
            return
        end
        loaded[userId] = nil
        entry.profile.lastSeen = deps.now()
        entry.session.endSession()
    end

    -- true, solange für den Spieler ein Ladevorgang läuft oder ein Profil geladen ist.
    -- Ein neuer load ist erst erlaubt, wenn das false ist.
    function manager.isBusy(userId: number): boolean
        return loaded[userId] ~= nil or loading[userId] ~= nil
    end

    function manager.get(userId: number): Profile.Profile?
        local entry = loaded[userId]
        return if entry then entry.profile else nil
    end

    function manager.isLoaded(userId: number): boolean
        return loaded[userId] ~= nil
    end

    function manager.onLoaded(callback: (number, Profile.Profile) -> ())
        table.insert(loadedCallbacks, callback)
    end

    return manager
end

return PlayerSession
