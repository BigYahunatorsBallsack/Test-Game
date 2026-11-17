--!strict
-- Fake-Speicher für PlayerSession-Tests. Ahmt die Teile von ProfileStore nach, die das Spiel
-- nutzt: Sitzungssperre pro Schlüssel, Speichern als Kopie, onSave vor jedem Speichern,
-- onSessionEnd beim Ende (auch wenn ein anderer Server die Sitzung beendet).
-- Eine "Welt" ist der gemeinsame DataStore, jeder Server bekommt seinen eigenen Store.
-- Ist ein Schlüssel gesperrt, wartet startSession mit coroutine.yield(). Der Test setzt die
-- Coroutine selbst fort, so bleibt der Ablauf ohne echte Wartezeit und vorhersagbar.

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
}

function FakeStore.newWorld(): World
    return { saved = {}, locks = {}, sessions = {}, writes = 0, failNextStart = false }
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
        local saveCallbacks: { () -> () } = {}
        local endCallbacks: { () -> () } = {}
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
        function session.save()
            if not active then
                return
            end
            for _, callback in saveCallbacks do
                callback()
            end
            world.saved[key] = deepCopy(data)
            world.writes += 1
        end
        local function finish()
            active = false
            world.locks[key] = nil
            world.sessions[key] = nil
            for _, callback in endCallbacks do
                callback()
            end
        end
        function session.endSession()
            if not active then
                return
            end
            session.save()
            finish()
        end
        function session.endWithoutSave()
            if active then
                finish()
            end
        end
        world.sessions[key] = session
        return session
    end

    return store
end

return FakeStore
