--!strict
-- Fake-Speicher für PlayerSession-Tests. Ahmt die Teile von ProfileStore nach, die das Spiel
-- nutzt: Sitzungssperre pro Schlüssel, Speichern als Kopie, onSave vor jedem Speichern,
-- onSessionEnd beim Ende (auch wenn ein anderer Server die Sitzung beendet).
-- Eine "Welt" ist der gemeinsame DataStore, jeder Server bekommt seinen eigenen Store.
-- Ist ein Schlüssel gesperrt, wartet startSession mit coroutine.yield(). Der Test setzt die
-- Coroutine selbst fort, so bleibt der Ablauf ohne echte Wartezeit und vorhersagbar.
--
-- Paket 4.1 (Käufe): Wie bei ProfileStore gibt es `save` (Speichern anstoßen), `lastSaved` (zuletzt
-- nachweislich gespeicherter Stand, wie profile.LastSavedData), `isActive` und `onAfterSave` (nach
-- jedem erfolgreichen Speichern). Die Welt kann das Speichern steuern:
--  * `failSaves = true`: Speichern schlägt fehl (nichts wird geschrieben, kein onAfterSave).
--  * `delaySaves = true`: `save` wartet in `pendingSaves`, bis der Test `FakeStore.flushSaves` aufruft.
--  * `FakeStore.crash`: Der Server stürzt ab, der ungespeicherte Stand ist verloren.
--  * `FakeStore.endFromOutside`: Ein anderer Server übernimmt die Sitzung (ohne Speichern).
-- Beenden (`endSession`) in der Reihenfolge von ProfileStore: onSave, Sitzung inaktiv und
-- onSessionEnd, danach das letzte Schreiben mit onAfterSave. Mit `delaySaves` wartet auch dieses
-- letzte Schreiben auf `flushSaves` (die Sperre bleibt so lange), `failSaves` gilt auch dort.

local FakeStore = {}

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
FakeStore.deepCopy = deepCopy

export type World = {
    saved: { [string]: any },
    locks: { [string]: string }, -- Schlüssel -> Servername
    sessions: { [string]: any }, -- Schlüssel -> offene Sitzung
    writes: number,
    failNextStart: boolean,
    -- Paket 4.1:
    saveCalls: number, -- wie oft `save` angestoßen wurde
    failSaves: boolean,
    delaySaves: boolean,
    pendingSaves: { { key: string, run: () -> () } },
}

function FakeStore.newWorld(): World
    return {
        saved = {},
        locks = {},
        sessions = {},
        writes = 0,
        failNextStart = false,
        saveCalls = 0,
        failSaves = false,
        delaySaves = false,
        pendingSaves = {},
    }
end

-- Speichert eine offene Sitzung (wie das Autosave von ProfileStore).
function FakeStore.autosave(world: World, key: string)
    local session = world.sessions[key]
    if session ~= nil then
        session.save()
    end
end

-- Ein anderer Server übernimmt die Sitzung (wie ProfileStore "External"). Wie bei
-- ProfileStore speichert die übernommene Sitzung dabei nicht mehr.
function FakeStore.endFromOutside(world: World, key: string)
    local session = world.sessions[key]
    if session ~= nil then
        session.endWithoutSave()
    end
end

-- Führt alle verzögerten Speichervorgänge aus (in der Reihenfolge, in der sie angestoßen wurden).
-- Gibt die Zahl der ausgeführten Vorgänge zurück.
function FakeStore.flushSaves(world: World): number
    local pending = world.pendingSaves
    world.pendingSaves = {}
    for _, job in pending do
        job.run()
    end
    return #pending
end

-- Der Server stürzt ab: Die Sitzung verschwindet ohne Speichern, verzögerte Speichervorgänge für
-- den Schlüssel gehen verloren, die Sperre wird frei (ProfileStore gibt eine verwaiste Sperre nach
-- einer Weile frei). Gespeichert bleibt nur, was vorher geschrieben war.
function FakeStore.crash(world: World, key: string)
    local kept = {}
    for _, job in world.pendingSaves do
        if job.key ~= key then
            table.insert(kept, job)
        end
    end
    world.pendingSaves = kept
    local session = world.sessions[key]
    if session ~= nil then
        session.vanish()
    end
    world.locks[key] = nil -- auch die Sperre einer Sitzung, deren letztes Schreiben noch ausstand
end

function FakeStore.newServer(world: World, serverName: string): any
    local store = {}

    function store.startSession(key: string, cancel: () -> boolean): any
        if world.failNextStart then
            world.failNextStart = false
            return nil
        end
        -- Sitzungssperre: warten, bis der andere Server freigibt oder abgebrochen wird.
        while world.locks[key] ~= nil do
            if cancel() then
                return nil
            end
            coroutine.yield()
        end
        if cancel() then
            return nil
        end
        world.locks[key] = serverName

        local data: any = deepCopy(world.saved[key]) or {}
        local lastSavedData: any = deepCopy(data)
        local saveCallbacks: { () -> () } = {}
        local endCallbacks: { () -> () } = {}
        local afterSaveCallbacks: { (any) -> () } = {}
        local active = true

        local session = {}
        function session.getData(): any
            return data
        end
        function session.setData(newData: any)
            data = newData
        end
        function session.onSave(callback: () -> ())
            table.insert(saveCallbacks, callback)
        end
        function session.onSessionEnd(callback: () -> ())
            table.insert(endCallbacks, callback)
        end
        function session.onAfterSave(callback: (any) -> ()): () -> ()
            table.insert(afterSaveCallbacks, callback)
            return function()
                local index = table.find(afterSaveCallbacks, callback)
                if index ~= nil then
                    table.remove(afterSaveCallbacks, index)
                end
            end
        end
        function session.lastSaved(): any
            return lastSavedData
        end
        function session.isActive(): boolean
            return active
        end

        local function runSaveCallbacks()
            for _, callback in saveCallbacks do
                callback()
            end
        end
        -- Schreibt den Stand (außer bei failSaves) und ruft danach onAfterSave mit dem gespeicherten
        -- Stand auf. Gibt true zurück, wenn geschrieben wurde.
        local function writeData(): boolean
            if world.failSaves then
                return false
            end
            world.saved[key] = deepCopy(data)
            world.writes += 1
            lastSavedData = deepCopy(data)
            for _, callback in table.clone(afterSaveCallbacks) do
                callback(lastSavedData)
            end
            return true
        end
        -- Ein normaler Schreibvorgang: onSave, dann schreiben, dann onAfterSave.
        local function write()
            runSaveCallbacks()
            writeData()
        end

        function session.save()
            if not active then
                return
            end
            world.saveCalls += 1
            if world.delaySaves then
                table.insert(world.pendingSaves, {
                    key = key,
                    run = function()
                        -- Eine beendete Sitzung schreibt nicht mehr (wie ProfileStore).
                        if active then
                            write()
                        end
                    end,
                })
                return
            end
            write()
        end
        local function releaseLock()
            if world.locks[key] == serverName then
                world.locks[key] = nil
            end
        end
        local function finish()
            active = false
            world.sessions[key] = nil
            for _, callback in endCallbacks do
                callback()
            end
        end
        -- Reihenfolge wie ProfileStore beim Beenden: onSave, dann Sitzung inaktiv (IsActive false) und
        -- onSessionEnd, erst danach das letzte Schreiben mit onAfterSave. Wer auf ein bestätigtes
        -- Speichern wartet, sieht also zuerst "inaktiv" und erst danach den gespeicherten Stand.
        -- Die Sperre bleibt bis nach dem letzten Schreiben (ein neuer Server lädt erst danach).
        function session.endSession()
            if not active then
                return
            end
            world.saveCalls += 1
            runSaveCallbacks()
            finish()
            if world.delaySaves then
                -- Das letzte Schreiben ist verzögert (es läuft auch für die beendete Sitzung).
                table.insert(world.pendingSaves, {
                    key = key,
                    run = function()
                        writeData()
                        releaseLock()
                    end,
                })
                return
            end
            writeData()
            releaseLock()
        end
        function session.endWithoutSave()
            if active then
                finish()
                releaseLock()
            end
        end
        -- Absturz: kein Speichern, keine Rückrufe (der Server ist weg).
        function session.vanish()
            active = false
            world.locks[key] = nil
            world.sessions[key] = nil
        end
        world.sessions[key] = session
        return session
    end

    return store
end

return FakeStore
