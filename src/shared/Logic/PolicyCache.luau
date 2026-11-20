--!strict
-- Policy-Cache für `ArePaidRandomItemsRestricted` (Paket 4.2). Rein, ohne Roblox-API, Lune-Tests in
-- tests/policycache.spec.luau. Der Crates-Service gibt PolicyService und `task.wait` als Adapter
-- herein.
--
-- Regeln (fail-closed):
--  * Je Spieler (UserId) wird die Policy einmal beim Beitreten geholt, höchstens `attempts` Versuche,
--    dazwischen `retrySeconds` Wartezeit. Ein Versuch gilt nur, wenn die Antwort eine Tabelle mit
--    `ArePaidRandomItemsRestricted` als true/false ist. Fehler (pcall) und alles andere zählen als
--    gescheitert.
--  * Solange keine gültige Antwort da ist, und für immer, wenn alle Versuche scheitern, ist der Wert
--    unbekannt (nil). Unbekannt gilt als gesperrt: `isAllowed` ist nur bei bekanntem `false` wahr.
--  * `forget` (Spieler verlässt das Spiel) löscht den Wert. Ein Ladevorgang, der danach noch fertig
--    wird (oder von einem neueren Ladevorgang desselben Spielers überholt wurde, schneller Rejoin),
--    schreibt nichts mehr.
--  * `onResolved(userId, restricted)` meldet das Endergebnis eines Ladevorgangs, der noch gilt
--    (auch nil nach lauter Fehlschlägen), damit der Service die Anzeige neu senden kann.
--  * `state(userId)` (Paket 4.6) nennt den Zustand für Anzeige und Direktkauf: "none" (nie geladen
--    oder vergessen), "pending" (Abruf läuft), "allowed" / "restricted" (Antwort false / true),
--    "unknown" (alle Versuche gescheitert). Gesperrt für Kisten ist alles außer "allowed".

export type Deps = {
    fetch: (subject: any) -> any, -- holt die Policy-Tabelle; darf warten und werfen
    wait: (seconds: number) -> (), -- Wartezeit zwischen Versuchen
    attempts: number, -- höchstens so viele Versuche
    retrySeconds: number, -- Wartezeit zwischen zwei Versuchen
    log: ((message: string) -> ())?,
    onResolved: ((userId: number, restricted: boolean?) -> ())?,
}

export type State = "none" | "pending" | "allowed" | "restricted" | "unknown"

export type Cache = {
    load: (userId: number, subject: any) -> boolean?,
    restricted: (userId: number) -> boolean?,
    isAllowed: (userId: number) -> boolean,
    state: (userId: number) -> State,
    forget: (userId: number) -> (),
}

-- Feld der Policy-Antwort, das zählt.
local FIELD = "ArePaidRandomItemsRestricted"

local PolicyCache = {}

function PolicyCache.new(deps: Deps): Cache
    local values: { [number]: boolean } = {}
    local states: { [number]: State } = {}
    local tokens: { [number]: number } = {}
    local nextToken = 0

    local function log(message: string)
        if deps.log then
            deps.log(message)
        end
    end

    local function isCurrent(userId: number, token: number): boolean
        return tokens[userId] == token
    end

    -- Holt die Policy (wartet!). Gibt den gemerkten Wert zurück (nil = unbekannt, also gesperrt).
    local function load(userId: number, subject: any): boolean?
        nextToken += 1
        local token = nextToken
        tokens[userId] = token
        values[userId] = nil
        states[userId] = "pending"
        for attempt = 1, deps.attempts do
            local ok, info = pcall(deps.fetch, subject)
            if not isCurrent(userId, token) then
                return nil -- inzwischen vergessen oder neu geladen: nichts schreiben
            end
            if ok and type(info) == "table" and type(info[FIELD]) == "boolean" then
                values[userId] = info[FIELD]
                states[userId] = if info[FIELD] then "restricted" else "allowed"
                if deps.onResolved then
                    deps.onResolved(userId, info[FIELD])
                end
                return info[FIELD]
            end
            log(`Policy für {userId}: Versuch {attempt} von {deps.attempts} gescheitert ({if ok then "ungültige Antwort" else tostring(info)})`)
            if attempt < deps.attempts then
                deps.wait(deps.retrySeconds)
                if not isCurrent(userId, token) then
                    return nil
                end
            end
        end
        log(`Policy für {userId}: unbekannt, Kisten bleiben gesperrt`)
        states[userId] = "unknown"
        if deps.onResolved then
            deps.onResolved(userId, nil)
        end
        return nil
    end

    local function restricted(userId: number): boolean?
        return values[userId]
    end

    local function isAllowed(userId: number): boolean
        return values[userId] == false
    end

    -- Zustand für Anzeige und Direktkauf (siehe Kopf der Datei).
    local function state(userId: number): State
        return states[userId] or "none"
    end

    local function forget(userId: number)
        values[userId] = nil
        tokens[userId] = nil
        states[userId] = nil
    end

    return {
        load = load,
        restricted = restricted,
        isAllowed = isAllowed,
        state = state,
        forget = forget,
    }
end

return PolicyCache
