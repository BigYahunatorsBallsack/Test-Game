--!strict
-- Spielerprofil: Standardwerte, Version und Migration. Rein, ohne Roblox-API.
-- Gespeichert wird später mit ProfileStore (Paket 1.1).
--
-- Regeln beim Laden (Profile.migrate):
--  * Kein Profil (nil) ergibt ein Standardprofil, Status "new".
--  * Höhere Version als dem Server bekannt: unverändert zurück, Status "too_new".
--    Der Aufrufer darf es NICHT speichern (sonst gehen Daten des neueren Servers verloren).
--  * Niedrigere Version: Schritt für Schritt migrieren, dann fehlende Felder (tief) mit
--    Standardwerten füllen, Status "ok". Eine zweite Migration ändert nichts mehr.
--  * Unbekannte Felder und unbekannte Knoten-IDs bleiben erhalten und werden ignoriert.

local BigNum = require("./BigNum")
local Migrations = require("./Migrations")

export type Pity = { sinceEpic: number, sinceLegendary: number }

export type Profile = {
    version: number,
    coins: BigNum.Serialized,
    tank: BigNum.Serialized,
    gems: number,
    nodes: { [string]: boolean }, -- gekaufte Knoten (ID -> true)
    zones: { [string]: boolean }, -- freigeschaltete Zonen
    currentZone: string,
    finds: { [string]: number }, -- Fundstück-ID -> Anzahl
    windCrystals: number,
    prestiges: number,
    pity: { [string]: Pity }, -- Kisten-ID -> Zähler
    inventory: {
        skins: { [string]: number },
        companions: { [string]: number },
        toolVariants: { [string]: number },
    },
    receipts: { [string]: boolean }, -- verarbeitete PurchaseIds
    boosts: { coinsUntil: number }, -- Unix-Zeit, bis wann der Münz-Boost läuft
    daily: { streak: number, lastDay: number },
    tutorial: { step: number }, -- Fortschritt der ersten 2 Minuten (Paket 1.6)
    lastSeen: number, -- Unix-Zeit des letzten Speicherns (Offline-Ertrag)
    createdAt: number,
}

export type Status = "ok" | "new" | "too_new"

local Profile = {}

Profile.CURRENT_VERSION = Migrations.CURRENT_VERSION

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

-- Füllt fehlende Felder von `data` aus `defaults` auf (tief). Vorhandene Werte bleiben.
local function fillDefaults(data: any, defaults: any)
    for key, defaultValue in defaults do
        local current = data[key]
        if current == nil then
            data[key] = deepCopy(defaultValue)
        elseif type(defaultValue) == "table" and type(current) == "table" then
            fillDefaults(current, defaultValue)
        end
    end
end

-- Standardprofil. `now` ist die Unix-Zeit für createdAt und lastSeen (Standard: os.time()).
function Profile.default(now: number?): Profile
    local time = now or os.time()
    return {
        version = Profile.CURRENT_VERSION,
        coins = BigNum.serialize(BigNum.zero()),
        tank = BigNum.serialize(BigNum.zero()),
        gems = 0,
        nodes = {},
        zones = { dunes = true },
        currentZone = "dunes",
        finds = {},
        windCrystals = 0,
        prestiges = 0,
        pity = { gold = { sinceEpic = 0, sinceLegendary = 0 } },
        inventory = { skins = {}, companions = {}, toolVariants = {} },
        receipts = {},
        boosts = { coinsUntil = 0 },
        daily = { streak = 0, lastDay = 0 },
        tutorial = { step = 1 },
        lastSeen = time,
        createdAt = time,
    }
end

-- Zielversion: die höchste bekannte Version der übergebenen Schritte.
local function targetVersion(steps: { [number]: Migrations.Step }): number
    local highest = 0
    for fromVersion in steps do
        if fromVersion > highest then
            highest = fromVersion
        end
    end
    return math.max(Profile.CURRENT_VERSION, highest + 1)
end

-- Lädt ein gespeichertes Profil. Gibt das (migrierte) Profil und den Status zurück.
-- `migrations` (Standard: Migrations.steps) und `now` sind für Tests überschreibbar.
function Profile.migrate(
    data: any,
    migrations: { [number]: Migrations.Step }?,
    now: number?
): (Profile, Status)
    local steps = migrations or Migrations.steps
    local target = targetVersion(steps)

    if type(data) ~= "table" then
        local fresh = Profile.default(now)
        fresh.version = target
        return fresh, "new"
    end

    local version = if type(data.version) == "number" then data.version else 1
    if version > target then
        return data :: any, "too_new"
    end

    -- Auf einer Kopie arbeiten, damit ein Fehler im Schritt das Original nicht beschädigt.
    local profile: any = deepCopy(data)
    while version < target do
        local step = steps[version]
        if step == nil then
            error(`Profile: keine Migration von Version {version} auf {version + 1}`)
        end
        profile = step(profile)
        version += 1
        profile.version = version
    end

    fillDefaults(profile, Profile.default(now))
    profile.version = target
    return profile :: Profile, "ok"
end

local function isBadNumber(value: number): boolean
    return value ~= value or value == math.huge or value == -math.huge
end

-- Felder, deren Standardtabelle zwar Einträge hat, deren Schlüssel aber beliebige IDs sind.
-- Sie werden wie Listen behandelt (nur Einträge säubern, siehe scrubFree).
local FREE_KEY_FIELDS: { [string]: boolean } = { pity = true, zones = true }
-- Felder im Zahlentyp {m, e}: Ist ein Teil kaputt, wird das ganze Feld auf 0 gesetzt.
local BIGNUM_FIELDS: { [string]: boolean } = { coins = true, tank = true }

local function warn(warnings: { string }, path: string, text: string)
    warnings[#warnings + 1] = `{path}: {text}`
end

-- Säubert eine Tabelle mit beliebigen Schlüsseln (Funde, Inventar, Knoten, Belege, Pity):
-- Schlüssel müssen Text sein, Werte Zahl (endlich), Text, Wahrheitswert oder Tabelle.
-- Alles andere wird entfernt, damit es den DataStore nicht stört.
local function scrubFree(data: any, path: string, warnings: { string })
    local toRemove = {}
    for key, value in data do
        local valueType = type(value)
        if type(key) ~= "string" then
            table.insert(toRemove, key)
            warn(warnings, `{path}[{tostring(key)}]`, "Schlüssel ist kein Text, entfernt")
        elseif valueType == "number" then
            if isBadNumber(value) then
                table.insert(toRemove, key)
                warn(warnings, `{path}.{key}`, "Zahl ist NaN oder unendlich, entfernt")
            end
        elseif valueType == "table" then
            scrubFree(value, `{path}.{key}`, warnings)
        elseif valueType ~= "string" and valueType ~= "boolean" then
            table.insert(toRemove, key)
            warn(warnings, `{path}.{key}`, `{valueType} kann nicht gespeichert werden, entfernt`)
        end
    end
    for _, key in toRemove do
        data[key] = nil
    end
end

local function isValidBigNum(value: any): boolean
    return type(value) == "table"
        and type(value.m) == "number"
        and type(value.e) == "number"
        and not isBadNumber(value.m)
        and not isBadNumber(value.e)
end

local function sanitizeInto(data: any, defaults: any, path: string, warnings: { string })
    for key, defaultValue in defaults do
        local current = data[key]
        local fieldPath = if path == "" then tostring(key) else `{path}.{key}`
        if current == nil then
            continue -- fehlende Felder füllt Profile.migrate
        end
        if path == "" and BIGNUM_FIELDS[key] then
            if not isValidBigNum(current) then
                warn(warnings, fieldPath, "ungültiger Zahlentyp, auf 0 gesetzt")
                data[key] = deepCopy(defaultValue)
            end
            continue
        end
        local broken = type(current) ~= type(defaultValue)
            or (type(current) == "number" and isBadNumber(current))
        if broken then
            warn(warnings, fieldPath, `{type(current)} statt {type(defaultValue)}, auf Standard gesetzt`)
            data[key] = deepCopy(defaultValue)
        elseif type(defaultValue) == "table" then
            if next(defaultValue) == nil or (path == "" and FREE_KEY_FIELDS[key]) then
                scrubFree(current, fieldPath, warnings) -- Liste beliebiger IDs
            else
                sanitizeInto(current, defaultValue, fieldPath, warnings) -- feste Struktur
            end
        end
    end
end

-- Repariert kaputte Felder eines migrierten Profils, beim Laden und vor jedem Speichern:
--  * Feld mit falschem Typ oder Zahl NaN/unendlich: nur dieses Feld auf den Standard setzen.
--  * Münzen und Tank ({m, e}): ist ein Teil kaputt, wird das ganze Feld 0.
--  * Listen mit beliebigen IDs (Funde, Inventar, Knoten, Belege, Pity): ungültige Einträge
--    (NaN, unendlich, Nicht-Text-Schlüssel, nicht speicherbare Typen) werden entfernt.
-- Unbekannte Felder oben im Profil bleiben unberührt. Gibt eine Liste mit Warntexten zurück
-- (leer, wenn alles stimmt). Ändert `profile`. Nie auf Profile mit Status "too_new" anwenden.
function Profile.sanitize(profile: Profile, now: number?): { string }
    local warnings: { string } = {}
    sanitizeInto(profile, Profile.default(now), "", warnings)
    return warnings
end

-- Gibt die gekauften Knoten zurück, die der Baum kennt (sortiert). Unbekannte Knoten-IDs
-- im Profil bleiben gespeichert, werden hier aber ignoriert. `known` ist z. B. UpgradeTree.byId.
function Profile.ownedKnownNodes(profile: Profile, known: { [string]: any }): { string }
    local result = {}
    for nodeId, owned in profile.nodes do
        if owned == true and known[nodeId] ~= nil then
            table.insert(result, nodeId)
        end
    end
    table.sort(result)
    return result
end

return Profile
