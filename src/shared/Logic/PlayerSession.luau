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
--  * Käufe (Paket 4.1): `saveAndWait` stößt ein Speichern an und wartet, bis der gespeicherte Stand
--    eine Bedingung erfüllt (die PurchaseId steht drin). Nur das zählt als "gespeichert"; ein
--    Fehler oder die Zeitgrenze ergeben false. Endet die Sitzung während des Wartens, wird bis zur
--    Zeitgrenze weiter gewartet: ProfileStore setzt beim Beenden zuerst IsActive auf false und
--    schreibt erst danach ein letztes Mal (OnAfterSave mit LastSavedData). Enthält dieser letzte
--    Stand die PurchaseId, ist der Kauf gespeichert. Gewartet wird über die eingespeiste Funktion
--    `wait` (im Spiel task.wait, in Lune eine Fake-Uhr).

local Profile = require("./Profile")

-- Eine offene Sitzung im Speicher (im Spiel: ein ProfileStore-Profil).
export type StoreSession = {
    getData: () -> any,
    setData: (data: any) -> (),
    onSave: (callback: () -> ()) -> (), -- läuft direkt vor jedem Speichern
    onSessionEnd: (callback: () -> ()) -> (), -- läuft, wenn die Sitzung endet (auch extern)
    endSession: () -> (), -- speichert ein letztes Mal und gibt die Sperre frei
    -- Paket 4.1 (Käufe):
    save: () -> (), -- stößt ein Speichern an, wartet nicht (im Spiel profile:Save())
    lastSaved: () -> any?, -- zuletzt nachweislich gespeicherter Stand oder nil (profile.LastSavedData)
    isActive: () -> boolean, -- true, solange Änderungen an den Daten gespeichert werden
    -- läuft nach jedem erfolgreichen Speichern mit dem gespeicherten Stand; gibt "Trennen" zurück
    onAfterSave: (callback: (savedData: any) -> ()) -> () -> (),
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
    -- Paket 4.1: Warten auf das Speichern. Ohne `wait` gibt saveAndWait false zurück, wenn der
    -- gespeicherte Stand die Bedingung nicht schon erfüllt.
    wait: ((seconds: number) -> ())?, -- im Spiel task.wait
    clock: (() -> number)?, -- Uhr für Zeitgrenzen (im Spiel os.clock, Standard: now)
}

type Entry = { session: StoreSession, profile: Profile.Profile }
type LoadJob = { released: boolean }

-- Meldungen an den Spieler. Stehen hier gesammelt, damit sie leicht zu ändern sind.
-- Abstand, in dem saveAndWait nachsieht, ob das Speichern bestätigt ist (Sekunden).
local SAVE_POLL_SECONDS = 0.1

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
    -- Paket 4.1 (Käufe):
    isActive: (userId: number) -> boolean,
    isSaved: (userId: number, predicate: (savedData: any) -> boolean) -> boolean,
    saveAndWait: (userId: number, predicate: (savedData: any) -> boolean, timeoutSeconds: number) -> boolean,
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
        -- Beim Laden Belege und Kaufprotokoll nicht kürzen (keine PurchaseId verlieren, offene Belege
        -- kommen gleich nach dem Beitreten). Gekürzt wird erst beim nächsten Speichern (onSave unten).
        logWarnings(userId, "Profil repariert", Profile.sanitize(profile, deps.now(), { trimLists = false }))

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

    -- Erfüllt `savedData` die Bedingung? Fehler in der Bedingung zählen als nein.
    local function matches(predicate: (any) -> boolean, savedData: any): boolean
        if savedData == nil then
            return false
        end
        local ok, result = pcall(predicate, savedData)
        return ok and result == true
    end

    -- true, solange das Profil geladen ist und die Sitzung noch speichert.
    function manager.isActive(userId: number): boolean
        local entry = loaded[userId]
        return entry ~= nil and entry.session.isActive() == true
    end

    -- Erfüllt der zuletzt nachweislich gespeicherte Stand die Bedingung?
    function manager.isSaved(userId: number, predicate: (savedData: any) -> boolean): boolean
        local entry = loaded[userId]
        return entry ~= nil and matches(predicate, entry.session.lastSaved())
    end

    -- Speichert und wartet höchstens `timeoutSeconds`, bis ein gespeicherter Stand die Bedingung
    -- erfüllt. Erfüllt der zuletzt gespeicherte Stand sie schon, wird nicht erneut gespeichert.
    -- false bei: beim Aufruf nicht geladen oder Sitzung nicht aktiv, Fehler, Zeitgrenze. Endet die
    -- Sitzung erst während des Wartens, zählt bis zur Zeitgrenze noch ihr letztes Speichern.
    function manager.saveAndWait(userId: number, predicate: (savedData: any) -> boolean, timeoutSeconds: number): boolean
        local entry = loaded[userId]
        if entry == nil or entry.session.isActive() ~= true then
            return false
        end
        local session = entry.session
        if matches(predicate, session.lastSaved()) then
            return true
        end
        local wait = deps.wait
        if wait == nil then
            deps.log(`Spieler {userId}: Speichern bestätigen geht hier nicht (kein Warten eingestellt)`)
            return false
        end
        local clock: () -> number = deps.clock or deps.now

        local confirmed = false
        local disconnect = session.onAfterSave(function(savedData: any)
            if not confirmed and matches(predicate, savedData) then
                confirmed = true
            end
        end)
        local ok, err = pcall(session.save)
        if not ok then
            deps.log(`Spieler {userId}: Speichern fehlgeschlagen: {tostring(err)}`)
        end
        local deadline = clock() + timeoutSeconds
        while ok and not confirmed do
            -- Kein Abbruch beim Ende der Sitzung: Ihr letztes Speichern kommt erst danach (siehe Kopf).
            -- Zusätzlich zum Rückruf zählt der zuletzt gespeicherte Stand, falls der Speicher die
            -- Rückrufe beim Beenden trennt.
            if matches(predicate, session.lastSaved()) then
                confirmed = true
                break
            end
            if clock() >= deadline then
                deps.log(`Spieler {userId}: Speichern nach {timeoutSeconds} s nicht bestätigt`)
                break
            end
            local waited, waitError = pcall(wait, SAVE_POLL_SECONDS)
            if not waited then
                deps.log(`Spieler {userId}: Warten auf das Speichern fehlgeschlagen: {tostring(waitError)}`)
                break
            end
        end
        pcall(disconnect)
        return confirmed
    end

    return manager
end

return PlayerSession
