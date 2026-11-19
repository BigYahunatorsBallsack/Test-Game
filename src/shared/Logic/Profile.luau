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
local Economy = require("../Data/Economy")
local CratesData = require("../Data/Crates")

export type Pity = { sinceEpic: number, sinceLegendary: number }

-- Ein Eintrag im Kaufprotokoll (Paket 4.1), nur für Support und Auswertung.
export type PurchaseLogEntry = {
    purchaseId: string,
    productId: string, -- Produkt-ID aus den Daten, z. B. "gems_550" (nicht die Roblox-ProductId)
    gems: number, -- tatsächlich gutgeschriebene Gems
    robux: number, -- Preis laut Datentabelle
    time: number, -- Unix-Zeit der Gutschrift
}

export type Profile = {
    version: number,
    coins: BigNum.Serialized,
    tank: BigNum.Serialized, -- Gesamtmenge Sand im Tank
    tankMix: { [string]: BigNum.Serialized }, -- Sand je Sandsorte (SandTypes-ID), Summe = tank (Paket 2.5)
    gems: number,
    nodes: { [string]: boolean }, -- gekaufte Knoten (ID -> true)
    zones: { [string]: boolean }, -- freigeschaltete Zonen
    currentZone: string,
    finds: { [string]: number }, -- Fundstück-ID -> Anzahl
    windCrystals: number,
    prestiges: number,
    runEarned: BigNum.Serialized, -- Münzen aus Verkäufen seit dem letzten Sandsturm (Paket 2.7)
    pity: { [string]: Pity }, -- Kisten-ID -> Zähler
    inventory: {
        skins: { [string]: number },
        companions: { [string]: number },
        toolVariants: { [string]: number },
    },
    receipts: { string }, -- PurchaseIds der zuletzt gutgeschriebenen Käufe, neueste am Ende (Paket 4.1)
    purchaseLog: { PurchaseLogEntry }, -- die letzten Käufe, neueste am Ende (Paket 4.1)
    spent: { robux: number, count: number }, -- Robux und Zahl aller gutgeschriebenen Käufe (Paket 4.1)
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
        tankMix = {},
        gems = 0,
        nodes = {},
        zones = { dunes = true },
        currentZone = "dunes",
        finds = {},
        windCrystals = 0,
        prestiges = 0,
        runEarned = BigNum.serialize(BigNum.zero()),
        -- Kisten-Pity (Paket 4.2): ein Zähler je Kiste mit Pity. Fehlt einer in einem alten
        -- Spielstand, füllt Profile.migrate ihn mit 0/0 auf (keine Migration nötig).
        pity = {
            gold = { sinceEpic = 0, sinceLegendary = 0 },
            event = { sinceEpic = 0, sinceLegendary = 0 },
        },
        inventory = { skins = {}, companions = {}, toolVariants = {} },
        receipts = {},
        purchaseLog = {},
        spent = { robux = 0, count = 0 },
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
local FREE_KEY_FIELDS: { [string]: boolean } = { pity = true, zones = true, tankMix = true }
-- Felder im Zahlentyp {m, e}: Ist ein Teil kaputt, wird das ganze Feld auf 0 gesetzt.
local BIGNUM_FIELDS: { [string]: boolean } = { coins = true, tank = true, runEarned = true }
-- Echte Listen (Paket 4.1). Sie haben eigene Regeln (repairPurchaseLog, repairReceipts), weil der
-- DataStore nur lückenlose Listen ohne Textschlüssel speichern kann.
local LIST_FIELDS: { [string]: boolean } = { receipts = true, purchaseLog = true }
-- Zähler je Kiste in `pity` (Paket 4.2) und die Pity-Stufe in Data/Crates, auf die sie gekappt werden.
local PITY_COUNTERS: { { field: string, tier: string } } = {
    { field = "sinceEpic", tier = "epic" },
    { field = "sinceLegendary", tier = "legendary" },
}

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
        if path == "" and LIST_FIELDS[key] then
            continue -- eigene Regeln, siehe Profile.sanitize
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

-- Werte, die in der alten Tabellenform { [PurchaseId] = true } einen Beleg markieren: alles
-- Speicherbare außer false. Lieber eine PurchaseId zu viel behalten als einen Kauf doppelt buchen.
local RECEIPT_MARKER_TYPES: { [string]: boolean } = { boolean = true, number = true, string = true, table = true }

-- Liest Belege in jeder Form als Liste von PurchaseIds: die Liste aus Version 4 und die Tabelle
-- { [PurchaseId] = true } älterer Spielstände (Schlüssel sortiert zuerst, dann der Listenteil in
-- seiner Reihenfolge). Nur nicht leere Texte, keine Doppelten. Ändert `value` nicht, gibt immer
-- eine neue Liste zurück (auch für nil oder kaputte Werte: leere Liste).
function Profile.receiptList(value: any): { string }
    local ids: { string } = {}
    if type(value) ~= "table" then
        return ids
    end
    local seen: { [string]: boolean } = {}
    local keys: { string } = {}
    local positions: { number } = {}
    for key, entry in value do
        if type(key) == "string" then
            if key ~= "" and entry ~= false and RECEIPT_MARKER_TYPES[type(entry)] then
                table.insert(keys, key)
            end
        elseif type(key) == "number" and type(entry) == "string" and entry ~= "" then
            table.insert(positions, key)
        end
    end
    table.sort(keys)
    table.sort(positions)
    for _, key in keys do
        if not seen[key] then
            seen[key] = true
            table.insert(ids, key)
        end
    end
    for _, position in positions do
        local id = value[position]
        if not seen[id] then
            seen[id] = true
            table.insert(ids, id)
        end
    end
    return ids
end

-- true, wenn `value` schon genau die Liste `list` ist (lückenlos, keine weiteren Schlüssel).
local function isSameList(value: any, list: { any }, same: (any, any) -> boolean): boolean
    local count = 0
    for _ in value do
        count += 1
    end
    if count ~= #list then
        return false
    end
    for index, entry in list do
        if not same(value[index], entry) then
            return false
        end
    end
    return true
end

local function isFiniteAtLeastZero(value: any): boolean
    return type(value) == "number" and not isBadNumber(value) and value >= 0
end

-- Ein gültiger Eintrag im Kaufprotokoll als saubere Kopie (nur bekannte Felder), sonst nil.
local function cleanLogEntry(entry: any): PurchaseLogEntry?
    if type(entry) ~= "table" then
        return nil
    end
    if type(entry.purchaseId) ~= "string" or entry.purchaseId == "" or type(entry.productId) ~= "string" then
        return nil
    end
    if not isFiniteAtLeastZero(entry.gems) or not isFiniteAtLeastZero(entry.robux) or not isFiniteAtLeastZero(entry.time) then
        return nil
    end
    return {
        purchaseId = entry.purchaseId,
        productId = entry.productId,
        gems = math.floor(entry.gems),
        robux = math.floor(entry.robux),
        time = entry.time,
    }
end

local function sameLogEntry(a: any, b: any): boolean
    if type(a) ~= "table" then
        return false
    end
    local count = 0
    for _ in a do
        count += 1
    end
    return count == 5
        and a.purchaseId == b.purchaseId
        and a.productId == b.productId
        and a.gems == b.gems
        and a.robux == b.robux
        and a.time == b.time
end

local function sameValue(a: any, b: any): boolean
    return a == b
end

-- Kaufprotokoll (Paket 4.1): lückenlose Liste gültiger Einträge, höchstens purchaseLogSize (die
-- neuesten am Ende bleiben, nur mit `trim`). Kaputte Einträge und Textschlüssel werden entfernt.
local function repairPurchaseLog(data: any, warnings: { string }, trim: boolean)
    local current = data.purchaseLog
    if current == nil then
        return -- fehlende Felder füllt Profile.migrate
    end
    if type(current) ~= "table" then
        warn(warnings, "purchaseLog", `{type(current)} statt Liste, geleert`)
        data.purchaseLog = {}
        return
    end
    local positions: { number } = {}
    for key in current do
        if type(key) == "number" then
            table.insert(positions, key)
        end
    end
    table.sort(positions)
    local list: { PurchaseLogEntry } = {}
    for _, position in positions do
        local entry = cleanLogEntry(current[position])
        if entry ~= nil then
            table.insert(list, entry)
        end
    end
    local limit = Economy.purchases.purchaseLogSize
    local trimmed = trim and #list > limit
    if trimmed then
        list = table.move(list, #list - limit + 1, #list, 1, {})
    end
    if not isSameList(current, list, sameLogEntry) then
        local text = if trimmed then `mehr als {limit} Einträge, die ältesten entfernt` else "ungültige Einträge entfernt oder Liste repariert"
        warn(warnings, "purchaseLog", text)
        data.purchaseLog = list
    end
end

-- Belege (Paket 4.1): lückenlose Liste von PurchaseIds, höchstens receiptCacheSize (die neuesten am
-- Ende bleiben, nur mit `trim`). Die alte Tabellenform wird in eine Liste gewandelt
-- (Profile.receiptList). Ist das Feld gar keine Tabelle, kommen die PurchaseIds aus dem
-- Kaufprotokoll zurück, damit ein dort stehender Kauf nicht ein zweites Mal gebucht wird.
local function repairReceipts(data: any, warnings: { string }, trim: boolean)
    local current = data.receipts
    if current == nil then
        return -- fehlende Felder füllt Profile.migrate
    end
    local list: { string }
    if type(current) ~= "table" then
        list = {}
        if type(data.purchaseLog) == "table" then
            for _, entry in data.purchaseLog do
                if type(entry) == "table" and type(entry.purchaseId) == "string" and entry.purchaseId ~= "" then
                    if table.find(list, entry.purchaseId) == nil then
                        table.insert(list, entry.purchaseId)
                    end
                end
            end
        end
        warn(warnings, "receipts", `{type(current)} statt Liste, aus dem Kaufprotokoll neu aufgebaut`)
    else
        list = Profile.receiptList(current)
    end
    local limit = Economy.purchases.receiptCacheSize
    local trimmed = trim and #list > limit
    if trimmed then
        list = table.move(list, #list - limit + 1, #list, 1, {})
    end
    if type(current) ~= "table" then
        data.receipts = list
    elseif not isSameList(current, list, sameValue) then
        local text = if trimmed then `mehr als {limit} Einträge, die ältesten entfernt` else "ungültige Einträge entfernt oder in Listenform gebracht"
        warn(warnings, "receipts", text)
        data.receipts = list
    end
end

-- Repariert kaputte Felder eines migrierten Profils, beim Laden und vor jedem Speichern:
--  * Feld mit falschem Typ oder Zahl NaN/unendlich: nur dieses Feld auf den Standard setzen.
--  * Münzen und Tank ({m, e}): ist ein Teil kaputt, wird das ganze Feld 0.
--  * Listen mit beliebigen IDs (Funde, Inventar, Knoten, Belege, Pity): ungültige Einträge
--    (NaN, unendlich, Nicht-Text-Schlüssel, nicht speicherbare Typen) werden entfernt.
-- Unbekannte Felder oben im Profil bleiben unberührt. Gibt eine Liste mit Warntexten zurück
-- (leer, wenn alles stimmt). Ändert `profile`. Nie auf Profile mit Status "too_new" anwenden.
--
-- `options.trimLists = false` (beim Laden): Belege und Kaufprotokoll werden repariert, aber nicht
-- gekürzt. Grund: Aus der alten Tabellenform { [PurchaseId] = true } ist die Kaufreihenfolge nicht
-- bekannt, Kürzen würde beliebige PurchaseIds entfernen. Roblox schickt offene Belege gleich beim
-- Beitreten erneut; bis dahin muss jede PurchaseId im Profil stehen, sonst würde doppelt gebucht.
-- Gekürzt wird erst beim nächsten Speichern (Standard, trimLists nicht false). Bis dahin steht jede
-- alte PurchaseId auch im zuletzt gespeicherten Stand, ein wiederholter Beleg gilt also sofort.
-- Ehrlich: Der Schutz gilt nur, solange in der Sitzung noch nichts geschrieben wurde. Das erste
-- Speichern und auch die erste neue Gutschrift (Purchases kürzt beim Anhängen) kürzen eine zu lange
-- alte Liste alphabetisch, nicht nach Kaufzeit; ein danach wiederholter alter Beleg gälte als neu.
-- Das reicht hier, weil es vor Paket 4.1 keinen ProcessReceipt gab: Alte Profile enthalten keine
-- echten Belege, die alte Tabellenform ist leer (oder stammt aus Tests und Handarbeit).
export type SanitizeOptions = { trimLists: boolean? }

function Profile.sanitize(profile: Profile, now: number?, options: SanitizeOptions?): { string }
    local trimLists = not (options ~= nil and options.trimLists == false)
    local warnings: { string } = {}
    sanitizeInto(profile, Profile.default(now), "", warnings)
    local data: any = profile
    -- Tank und Sand-Mix (Paket 2.5): negativer Tank wird 0, ein Mix ohne Tank wird geleert,
    -- ungültige oder negative Mix-Einträge werden entfernt.
    if type(data.tank) == "table" and data.tank.m < 0 then
        warn(warnings, "tank", "negativ, auf 0 gesetzt")
        data.tank = BigNum.serialize(BigNum.zero())
    end
    if type(data.tankMix) == "table" then
        if type(data.tank) ~= "table" or data.tank.m <= 0 then
            if next(data.tankMix) ~= nil then
                warn(warnings, "tankMix", "Tank ist leer, Mix geleert")
            end
            data.tankMix = {}
        else
            for typeId, amount in data.tankMix do
                if type(typeId) ~= "string" or not isValidBigNum(amount) or amount.m < 0 then
                    warn(warnings, `tankMix.{tostring(typeId)}`, "ungültiger Eintrag, entfernt")
                    data.tankMix[typeId] = nil
                end
            end
        end
    end
    -- Sandsturm (Paket 2.7): Kristalle sind ganze Zahlen ab 0, Einnahmen des Laufs nie negativ.
    if type(data.windCrystals) == "number" and data.windCrystals ~= math.floor(data.windCrystals) then
        data.windCrystals = math.max(math.floor(data.windCrystals), 0)
    end
    if type(data.windCrystals) == "number" and data.windCrystals < 0 then
        warn(warnings, "windCrystals", "negativ, auf 0 gesetzt")
        data.windCrystals = 0
    end
    if type(data.windCrystals) == "number" and data.windCrystals > Economy.sandstorm.maxCrystals then
        warn(warnings, "windCrystals", "über der Obergrenze, gekappt")
        data.windCrystals = Economy.sandstorm.maxCrystals
    end
    if type(data.prestiges) == "number" and data.prestiges ~= math.floor(data.prestiges) then
        data.prestiges = math.floor(data.prestiges)
    end
    if type(data.prestiges) == "number" and data.prestiges < 0 then
        warn(warnings, "prestiges", "negativ, auf 0 gesetzt")
        data.prestiges = 0
    end
    if type(data.runEarned) == "table" and data.runEarned.m < 0 then
        warn(warnings, "runEarned", "negativ, auf 0 gesetzt")
        data.runEarned = BigNum.serialize(BigNum.zero())
    end
    -- Funde (Paket 2.6): jeder Zähler ist eine ganze Zahl ab 1. Alles andere wird entfernt, ein
    -- Bruch wird abgerundet. Unbekannte IDs bleiben, sie zählen nur nicht.
    if type(data.finds) == "table" then
        for findId, count in data.finds do
            if type(count) ~= "number" or count < 1 then
                warn(warnings, `finds.{tostring(findId)}`, "ungültiger Zähler, entfernt")
                data.finds[findId] = nil
            elseif count ~= math.floor(count) then
                data.finds[findId] = math.floor(count)
            end
        end
    end
    -- Kisten-Pity (Paket 4.2): je Kiste eine Tabelle mit `sinceEpic` und `sinceLegendary`, beide
    -- ganze Zahlen ab 0. Fehlende oder kaputte Zähler werden 0, Brüche abgerundet. Bei Kisten mit
    -- Pity werden sie auf Grenze - 1 gekappt (ab dort greift die Garantie ohnehin, siehe
    -- Logic/CrateRoll). Ein Eintrag, der keine Tabelle ist, wird entfernt. Unbekannte Kisten-IDs
    -- bleiben (wie unbekannte Knoten), ihre Zähler werden nur gesäubert.
    if type(data.pity) == "table" then
        local brokenEntries: { any } = {}
        for crateId, counters in data.pity do
            if type(counters) ~= "table" then
                table.insert(brokenEntries, crateId)
                continue
            end
            local crate = CratesData.byId[crateId]
            local limits = if crate ~= nil and type(crate.pity) == "table" then crate.pity else nil
            for _, entry in PITY_COUNTERS do
                local value = counters[entry.field]
                local repaired = value
                if type(value) ~= "number" or isBadNumber(value) or value < 0 then
                    repaired = 0
                else
                    repaired = math.floor(value)
                    local limit = if limits then limits[entry.tier] else nil
                    if type(limit) == "number" and limit >= 1 and repaired > limit - 1 then
                        repaired = limit - 1
                    end
                end
                if repaired ~= value then
                    warn(warnings, `pity.{tostring(crateId)}.{entry.field}`, `ungültig ({tostring(value)}), auf {repaired} gesetzt`)
                    counters[entry.field] = repaired
                end
            end
        end
        for _, crateId in brokenEntries do
            warn(warnings, `pity.{tostring(crateId)}`, "keine Tabelle, entfernt")
            data.pity[crateId] = nil
        end
    end
    -- Gems (Paket 4.1): ganze Zahl ab 0, höchstens Economy.purchases.maxGems. NaN und unendlich
    -- setzt schon die allgemeine Prüfung oben auf 0.
    if type(data.gems) == "number" then
        local gems = data.gems
        if gems < 0 then
            warn(warnings, "gems", "negativ, auf 0 gesetzt")
            gems = 0
        elseif gems ~= math.floor(gems) then
            warn(warnings, "gems", "keine ganze Zahl, abgerundet")
            gems = math.floor(gems)
        end
        if gems > Economy.purchases.maxGems then
            warn(warnings, "gems", "über der Obergrenze, gekappt")
            gems = Economy.purchases.maxGems
        end
        data.gems = gems
    end
    -- Ausgaben (Paket 4.1): Robux und Zahl der Käufe sind ganze Zahlen ab 0.
    if type(data.spent) == "table" then
        for _, field in { "robux", "count" } do
            local value = data.spent[field]
            if type(value) == "number" and value < 0 then
                warn(warnings, `spent.{field}`, "negativ, auf 0 gesetzt")
                data.spent[field] = 0
            elseif type(value) == "number" and value ~= math.floor(value) then
                warn(warnings, `spent.{field}`, "keine ganze Zahl, abgerundet")
                data.spent[field] = math.floor(value)
            end
        end
    end
    -- Kaufprotokoll zuerst: Ist `receipts` ganz kaputt, kommen die PurchaseIds von dort zurück.
    repairPurchaseLog(data, warnings, trimLists)
    repairReceipts(data, warnings, trimLists)
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
