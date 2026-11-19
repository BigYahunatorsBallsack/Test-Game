--!strict
-- Kaufabwicklung für Developer Products (Paket 4.1). Rein, ohne Roblox-API, Lune-Tests in
-- tests/purchases.spec.luau. Der Shop-Service schließt MarketplaceService.ProcessReceipt an und gibt
-- Speicher, Uhr, Warten und Meldungen als Adapter hinein (im Spiel PlayerData mit ProfileStore, in
-- Lune ein Fake-Speicher).
--
-- Roblox ruft ProcessReceipt für einen Kauf so lange erneut auf (auch auf anderen Servern), bis
-- "granted" zurückkommt. Darum gilt:
--  1. Das Produkt kommt nur aus den Daten, über die ProductId des Belegs (GemPacks, weitere Produkte
--     über das Handler-Register). ProductId 0 (Platzhalter), doppelt vergeben oder unbekannt:
--     ein Protokolleintrag, "notProcessed".
--  2. Profil nicht geladen, Spieler nicht hier oder Sitzung nicht aktiv: "notProcessed", keine
--     Gutschrift. Ist der Spieler da und sein Profil lädt noch (Roblox schickt offene Belege gleich
--     beim Beitreten), wartet der Kauf höchstens PROFILE_WAIT_SECONDS darauf.
--  3. Je Spieler und PurchaseId läuft höchstens ein Vorgang. Ein zweiter gleichzeitiger Aufruf
--     wartet auf das Ergebnis des ersten und bucht nie selbst. Er wartet mindestens so lange, wie der
--     erste höchstens brauchen kann (Laden plus Speichern), gibt also nie vor ihm auf.
--  4. Steht die PurchaseId schon in `profile.receipts`, gibt es keine Gutschrift mehr; es wird nur
--     noch auf das bestätigte Speichern gewartet.
--  5. Sonst rechnet der Handler die Gutschrift auf Kopien von Profil und Produkt aus. Seine Antwort
--     wird geprüft (Form, speicherbar, Profil-Schema). Dann rechnet Purchases Belege (PurchaseId ans
--     Ende, älteste raus über receiptCacheSize), Kaufprotokoll (höchstens purchaseLogSize) und `spent`
--     aus und prüft direkt vor dem Schreiben noch einmal: dasselbe Profil, Sitzung aktiv, PurchaseId
--     noch nicht da.
--  6. Geschrieben wird alles oder nichts: Purchases weist die Änderungen des Handlers und die eigenen
--     Felder selbst zu (oberste Profilfelder). Wirft eine Zuweisung, werden alle schon geschriebenen
--     Felder zurückgesetzt, es bleibt weder Teilware noch PurchaseId.
--     Kritisches Fenster: Vom Kopieren des Profils über Handler, Uhr (`now`), Protokoll (`log`) und
--     erneute Prüfung bis vor das Schreiben läuft alles in einer eigenen Koroutine, die ohne Warten
--     fertig werden muss. Wartet darin irgendetwas, wird sie geschlossen: nichts geschrieben,
--     "notProcessed". Das Schreiben (writeAll) folgt direkt danach im selben Thread und weist nur zu,
--     es wartet nie. So kann sich das Profil zwischen Kopie und Schreiben nicht ändern (sonst würde
--     eine auf einem alten Stand gerechnete Gutschrift eine neuere überschreiben). Gewartet wird nur
--     vorher (Profil lädt, Sperre) und danach (Speichern).
--  7. "granted" erst, wenn der gespeicherte Stand die PurchaseId nachweislich enthält
--     (`saveAndWait`). Sonst (Fehler, Zeitgrenze, kein letztes Speichern): "notProcessed".
--     Gutschrift und PurchaseId bleiben zusammen im Profil, der nächste Aufruf bucht nicht neu und
--     wartet nur wieder auf das Speichern.
--  8. Die Meldung an den Client (zum Beispiel "gemsBought") kommt erst nach dem bestätigten Speichern
--     und je Kauf höchstens einmal pro Server. Auch sie läuft in einer eigenen Koroutine: Wartet sie,
--     wird sie geschlossen (die Sperre bleibt nie hängen). Gemerkt wird je Kauf nur die Meldefunktion;
--     endet ein Aufruf mit "notProcessed" und der Spieler ist nicht mehr da, wird sie vergessen.
-- Kein Fehler dringt nach außen: Alles läuft in pcall, ein Fehler ergibt "notProcessed" und einen
-- Protokolleintrag. Der Client hat keinen Einfluss: Menge und Preis kommen allein aus den Daten.
--
-- Handler-Register (für Paket 4.4): Ein Handler bekommt Kopien von Profil und Produkt (Änderungen
-- daran wirken nicht) und gibt `{ changes, gems, announce? }` zurück. `changes` sind die neuen Werte
-- für oberste Profilfelder (zum Beispiel `{ gems = 650 }` oder `{ boosts = neueTabelle }`), Purchases
-- schreibt sie selbst. Nicht erlaubt: receipts, purchaseLog, spent, version, nicht speicherbare Werte
-- (Funktionen, NaN, unendlich, gemischte oder lückenhafte Tabellen) und Werte, die nicht zum
-- Profil-Schema passen: `changes.gems` ganze Zahl von 0 bis maxGems, und jedes Feld aus
-- Profile.default muss Profile.sanitize unverändert überstehen (gleicher Typ, gültiger Zahlentyp
-- {m, e} bei coins/tank/runEarned, keine Reparatur nötig). Was das Speichern reparieren würde, wird
-- abgelehnt statt still verändert. `gems` (Antwort) ist eine ganze Zahl ab 0.
-- Ein Handler darf nie warten und nie das echte Profil ändern. Gem-Pakete sind eingebaut, weitere
-- Produkte aus Data/Products kommen über `register(produktId, handler)` dazu.
-- `missingHandlers()` nennt Produkte mit echter ProductId ohne Handler (der Shop meldet sie beim Start).
--
-- Studio-Hilfe: `processPack(userId, packId, purchaseId)` sucht ein Gem-Paket über seine Paket-ID
-- (die ProductIds sind bis zur Anlage im Creator Dashboard 0) und läuft danach durch denselben
-- Ablauf. Das geht nur mit `allowDebug = true` (der Shop setzt das nur in Studio), und die PurchaseId
-- bekommt immer das Präfix DEBUG_PREFIX. Der Echtpfad `process` prüft die ProductId unverändert.

local Gems = require("./Gems")
local Profile = require("./Profile")
local EconomyData = require("../Data/Economy")
local GemPacksData = require("../Data/GemPacks")
local ProductsData = require("../Data/Products")

-- Längste angenommene PurchaseId (Roblox liefert 32 Hex-Zeichen).
local MAX_PURCHASE_ID_LENGTH = 128
-- So lange wartet ein Kauf höchstens auf ein Profil, das gerade lädt (Sekunden), und so oft sieht er
-- nach. Mindestens so lange wie PlayerData beim Laden wartet (LOAD_TIMEOUT_SECONDS = 120) plus Puffer,
-- damit der Kauf nie vor dem Laden aufgibt. Die Schleife endet ohnehin, sobald nicht mehr geladen wird.
local PROFILE_WAIT_SECONDS = 130
local PROFILE_POLL_SECONDS = 0.25
-- Abstand, in dem ein zweiter Aufruf nachsieht, ob der erste fertig ist (Sekunden).
local LOCK_POLL_SECONDS = 0.1
-- Puffer für Abfrageabstände: Ein zweiter Aufruf wartet PROFILE_WAIT_SECONDS + saveTimeoutSeconds +
-- dieser Puffer, also mindestens so lange, wie der erste höchstens braucht.
local LOCK_EXTRA_SECONDS = 5
-- Präfix der PurchaseIds aus der Studio-Hilfe (nie gleich einer echten PurchaseId).
local DEBUG_PREFIX = "studio:"
-- Meldung an den Client nach einem bestätigten Gem-Kauf.
local GEMS_BOUGHT_KIND = "gemsBought"
-- Felder, die nur Purchases selbst schreibt. Ein Handler darf sie nicht in `changes` nennen.
local RESERVED_FIELDS: { [string]: boolean } = { receipts = true, purchaseLog = true, spent = true, version = true }
-- Werte, die ein Handler schreiben darf (alles, was der DataStore speichern kann).
local STORABLE_TYPES: { [string]: boolean } = { number = true, string = true, boolean = true, table = true }

export type Decision = "granted" | "notProcessed"

local GRANTED: Decision = "granted"
local NOT_PROCESSED: Decision = "notProcessed"

-- Beleg, wie ihn ProcessReceipt liefert (nur die Felder, die zählen).
export type Receipt = { PlayerId: number, ProductId: number, PurchaseId: string }

-- Ein Produkt aus den Daten.
export type Product = {
    id: string, -- Produkt-ID aus den Daten, z. B. "gems_550"
    productId: number, -- Developer-Product-ID (0 = Platzhalter)
    robux: number, -- Preis laut Datentabelle (Kaufprotokoll und `spent`)
    gems: number, -- Gems des Pakets (0 bei anderen Produkten)
}

-- Vorbereitete Gutschrift eines Handlers.
export type Prepared = {
    -- Neue Werte für oberste Profilfelder. Purchases weist sie zu (alles oder nichts).
    changes: { [string]: any },
    gems: number, -- tatsächlich gutgeschriebene Gems (ganze Zahl ab 0, Kaufprotokoll)
    -- Meldung an den Client nach dem bestätigten Speichern: (Art, Daten) aus einer Kopie des Profils.
    announce: ((profile: any) -> (string, { [string]: any }))?,
}

-- Rechnet die Gutschrift auf einer Kopie des Profils aus. Darf nie warten. nil = nicht möglich.
export type Handler = (profile: any, product: Product, data: any?) -> Prepared?

export type Deps = {
    getProfile: (userId: number) -> any?, -- geladenes Profil (lebende Tabelle) oder nil
    isSessionActive: (userId: number) -> boolean, -- Spieler da und Sitzung speichert noch
    -- Spieler ist auf dem Server, sein Profil lädt aber noch. Ohne: kein Warten auf das Laden.
    isLoading: ((userId: number) -> boolean)?,
    -- Speichert und wartet, bis der gespeicherte Stand die PurchaseId enthält. true nur dann.
    saveAndWait: (userId: number, purchaseId: string, timeoutSeconds: number) -> boolean,
    now: () -> number, -- Unix-Zeit (Kaufprotokoll)
    log: (message: string) -> (),
    -- Wartet (im Spiel task.wait). Ohne `wait` wartet ein gleichzeitiger zweiter Aufruf nicht auf den
    -- ersten, sondern gibt sofort "notProcessed" (Roblox wiederholt später).
    wait: ((seconds: number) -> ())?,
    clock: (() -> number)?, -- Uhr für Wartezeiten (im Spiel os.clock, Standard: now)
    notify: ((userId: number, kind: string, data: { [string]: any }) -> ())?,
    handlers: { [string]: Handler }?, -- weitere Produkte: Produkt-ID aus den Daten -> Handler
    allowDebug: boolean?, -- nur in Studio true: erlaubt processPack
    data: any?, -- nur Tests: { GemPacks, Products, Economy }
}

export type Purchases = {
    process: (receipt: any) -> Decision,
    processPack: (userId: number, packId: string, purchaseId: string) -> Decision,
    register: (productId: string, handler: Handler) -> (),
    missingHandlers: () -> { string },
    forget: (userId: number) -> (),
}

type Job = { done: boolean, result: Decision }
type Write = { key: string, value: any }
type Announce = (profile: any) -> (string, { [string]: any })
-- Ergebnis des kritischen Fensters: was geschrieben wird und die Meldefunktion (oder nil).
type Plan = { writes: { Write }, announce: Announce? }

local Purchases = {}
Purchases.DEBUG_PREFIX = DEBUG_PREFIX
Purchases.GEMS_BOUGHT_KIND = GEMS_BOUGHT_KIND
Purchases.PROFILE_WAIT_SECONDS = PROFILE_WAIT_SECONDS

local function configOf(data: any?): any
    local economy = if data and data.Economy then data.Economy else EconomyData
    return economy.purchases
end

local function isInteger(value: any): boolean
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge and value % 1 == 0
end

local function isPurchaseId(value: any): boolean
    return type(value) == "string" and value ~= "" and #value <= MAX_PURCHASE_ID_LENGTH
end

local function wholeAtLeastZero(value: any): number
    if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
        return 0
    end
    return math.floor(value)
end

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

-- Neue Liste mit den Einträgen des Listenteils von `value` (kaputte Werte: leere Liste).
local function listCopy(value: any): { any }
    local copy = {}
    if type(value) == "table" then
        for _, entry in ipairs(value) do
            table.insert(copy, entry)
        end
    end
    return copy
end

-- Behält die neuesten `limit` Einträge (am Ende der Liste).
local function keepNewest<T>(list: { T }, limit: number): { T }
    local size = math.max(math.floor(limit), 1)
    if #list <= size then
        return list
    end
    return table.move(list, #list - size + 1, #list, 1, {})
end

-- Ein Wert, den der DataStore speichern kann: Zahlen endlich, Tabellen tief geprüft und entweder
-- lückenlose Listen (Schlüssel 1 bis n) oder nur Textschlüssel (nicht gemischt).
local function isStorable(value: any, depth: number): boolean
    if not STORABLE_TYPES[type(value)] or depth > 20 then
        return false
    end
    if type(value) == "number" then
        return value == value and value > -math.huge and value < math.huge
    end
    if type(value) == "table" then
        local count, textKeys = 0, 0
        for key, inner in value do
            if type(key) == "string" then
                textKeys += 1
            elseif type(key) ~= "number" then
                return false
            end
            count += 1
            if not isStorable(inner, depth + 1) then
                return false
            end
        end
        if textKeys > 0 then
            return textKeys == count -- gemischte Tabellen speichert der DataStore nicht
        end
        for index = 1, count do
            if value[index] == nil then
                return false -- Lücke oder Schlüssel außerhalb von 1 bis n
            end
        end
    end
    return true
end

-- Prüft die Antwort eines Handlers. Gibt nil zurück, wenn sie stimmt, sonst den Grund.
local function problemOf(prepared: any): string?
    if type(prepared) ~= "table" then
        return "Antwort ist keine Tabelle"
    end
    if type(prepared.changes) ~= "table" then
        return "changes fehlt"
    end
    if not isInteger(prepared.gems) or prepared.gems < 0 then
        return `gems ist keine ganze Zahl ab 0 ({tostring(prepared.gems)})`
    end
    if prepared.announce ~= nil and type(prepared.announce) ~= "function" then
        return "announce ist keine Funktion"
    end
    for key, value in prepared.changes do
        if type(key) ~= "string" or key == "" then
            return "changes enthält einen Schlüssel, der kein Text ist"
        end
        if RESERVED_FIELDS[key] then
            return `changes darf "{key}" nicht ändern (schreibt nur Purchases)`
        end
        if not isStorable(value, 0) then
            return `changes.{key} kann nicht gespeichert werden`
        end
    end
    return nil
end

-- Gleicher Inhalt (Tabellen tief verglichen)?
local function deepEqual(a: any, b: any): boolean
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in a do
        if not deepEqual(value, b[key]) then
            return false
        end
    end
    for key in b do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Passen die Änderungen zum Profil-Schema? `changes.gems` muss eine ganze Zahl von 0 bis maxGems sein
-- (maxGems aus `cfg`). Danach werden die Änderungen auf eine Kopie des Profils gelegt und
-- Profile.sanitize läuft darüber, mit denselben Regeln wie vor jedem Speichern (falscher Typ, kaputter
-- Zahlentyp {m, e} bei coins/tank/runEarned, negative oder gebrochene Werte, Obergrenzen). Ändert
-- sanitize ein geändertes Feld, passt es nicht: abgelehnt statt beim Speichern still repariert.
-- Gibt nil zurück, wenn alles passt, sonst den Grund.
local function schemaProblemOf(profile: any, changes: { [string]: any }, cfg: any, now: number): string?
    local gems = changes.gems
    if gems ~= nil and (not isInteger(gems) or gems < 0 or gems > cfg.maxGems) then
        return `changes.gems ist keine ganze Zahl von 0 bis {cfg.maxGems} ({tostring(gems)})`
    end
    local copy = deepCopy(profile)
    for key, value in changes do
        copy[key] = deepCopy(value)
    end
    local ok, err = pcall(Profile.sanitize, copy, now, { trimLists = false })
    if not ok then
        return `Schema-Prüfung fehlgeschlagen: {tostring(err)}`
    end
    local keys: { string } = {}
    for key in changes do
        table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in keys do
        if not deepEqual(copy[key], changes[key]) then
            return `changes.{key} passt nicht zum Profil-Schema (würde beim Speichern repariert)`
        end
    end
    return nil
end

-- Führt `fn()` in einer eigenen Koroutine aus und verlangt, dass sie ohne Warten fertig wird.
-- Gibt (true, Ergebnis) zurück, sonst (false, Grund): bei einem Fehler oder wenn sie gewartet hat
-- (dann wird sie geschlossen und läuft nie weiter).
local function runAtOnce(fn: () -> any): (boolean, any)
    local thread = coroutine.create(fn)
    local ok, result = coroutine.resume(thread)
    if not ok then
        return false, `Fehler: {tostring(result)}`
    end
    if coroutine.status(thread) ~= "dead" then
        pcall(coroutine.close, thread)
        return false, "hat gewartet (in diesem Abschnitt darf nichts warten)"
    end
    return true, result
end

-- Schreibt alles oder nichts: Wirft eine Zuweisung, werden alle Felder auf den Stand davor gesetzt.
local function writeAll(profile: any, writes: { Write }): (boolean, any)
    local backup: { [number]: any } = {}
    for index, write in writes do
        backup[index] = profile[write.key]
    end
    local ok, err = pcall(function()
        for _, write in writes do
            profile[write.key] = write.value
        end
    end)
    if ok then
        return true, nil
    end
    for index, write in writes do
        pcall(function()
            profile[write.key] = backup[index]
        end)
    end
    return false, err
end

-- Enthält `data.receipts` die PurchaseId? Versteht die Liste und die alte Tabellenform.
-- Für das lebende Profil und für den zuletzt gespeicherten Stand.
function Purchases.hasReceipt(data: any, purchaseId: string): boolean
    if type(data) ~= "table" or type(purchaseId) ~= "string" or purchaseId == "" then
        return false
    end
    return table.find(Profile.receiptList(data.receipts), purchaseId) ~= nil
end

-- Eingebauter Handler für Gem-Pakete: Gems über Gems.grant (ganze Zahl, gekappt bei maxGems).
local function gemPackHandler(profile: any, product: Product, data: any?): Prepared?
    local added = Gems.grant(profile, product.gems, `purchase:{product.id}`, data) -- auf der Kopie
    return {
        changes = { gems = Gems.balance(profile, data) },
        gems = added,
        announce = function(current: any): (string, { [string]: any })
            return GEMS_BOUGHT_KIND, { gems = added, total = Gems.balance(current, data), productId = product.id }
        end,
    }
end

function Purchases.new(deps: Deps): Purchases
    local data = deps.data
    local gemPacks = if data and data.GemPacks then data.GemPacks else GemPacksData
    local products = if data and data.Products then data.Products else ProductsData
    local clock: () -> number = deps.clock or deps.now

    local byId: { [string]: Product } = {}
    local byProductId: { [number]: Product } = {}
    local duplicateProductIds: { [number]: boolean } = {}
    local packIds: { [string]: boolean } = {}
    local handlers: { [string]: Handler } = {}
    -- Laufende Vorgänge je Spieler und PurchaseId (Sperre).
    local inFlight: { [string]: Job } = {}
    -- Meldefunktionen der Gutschriften dieses Servers, deren Speichern noch nicht bestätigt ist (nur
    -- `announce`, nicht die ganze Antwort des Handlers).
    local unannounced: { [string]: Announce } = {}

    local function log(message: string)
        pcall(deps.log, message)
    end

    local function keyOf(userId: number, purchaseId: string): string
        return `{userId}:{purchaseId}`
    end

    local function addProduct(product: Product)
        if byId[product.id] ~= nil then
            log(`Produkt-ID "{product.id}" ist doppelt, der zweite Eintrag zählt nicht`)
            return
        end
        byId[product.id] = product
        local productId = product.productId
        if not isInteger(productId) or productId <= 0 then
            return -- Platzhalter: über den Echtpfad nie erreichbar
        end
        if duplicateProductIds[productId] or byProductId[productId] ~= nil then
            -- Doppelt vergeben: nicht raten, welches Produkt gemeint ist (DataCheck meldet es auch).
            duplicateProductIds[productId] = true
            byProductId[productId] = nil
            log(`ProductId {productId} ist doppelt vergeben, Käufe damit werden nicht verarbeitet`)
            return
        end
        byProductId[productId] = product
    end

    for _, pack in gemPacks.list do
        addProduct({ id = pack.id, productId = pack.productId, robux = pack.robux, gems = pack.gems })
        packIds[pack.id] = true
        handlers[pack.id] = gemPackHandler
    end
    for _, product in products.list do
        if product.kind ~= "gamepass" then -- Gamepasses laufen nicht über ProcessReceipt (Paket 4.4)
            addProduct({ id = product.id, productId = product.productId, robux = product.priceRobux, gems = 0 })
        end
    end

    local purchases = {} :: Purchases

    -- Hängt einen Handler für ein Produkt aus den Daten ein (Paket 4.4). Fehler beim Start sind
    -- gewollt: unbekannte Produkte und doppelte Handler sind Programmierfehler.
    function purchases.register(productId: string, handler: Handler)
        if type(productId) ~= "string" or byId[productId] == nil then
            error(`Purchases.register: Produkt "{tostring(productId)}" steht nicht in GemPacks oder Products`)
        end
        if type(handler) ~= "function" then
            error(`Purchases.register: Handler für "{productId}" ist keine Funktion`)
        end
        if handlers[productId] ~= nil then
            error(`Purchases.register: für "{productId}" ist schon ein Handler registriert`)
        end
        handlers[productId] = handler
    end

    -- Produkte mit echter ProductId (über 0, kein Gamepass) ohne Handler, sortiert. Käufe davon kämen
    -- nie durch; der Shop meldet sie darum schon beim Start.
    function purchases.missingHandlers(): { string }
        local missing: { string } = {}
        for productId, product in byId do
            if isInteger(product.productId) and product.productId > 0 and handlers[productId] == nil then
                table.insert(missing, productId)
            end
        end
        table.sort(missing)
        return missing
    end

    local extraHandlers = deps.handlers
    if extraHandlers ~= nil then
        for productId, handler in extraHandlers do
            purchases.register(productId, handler)
        end
    end

    -- Profil des Spielers. Lädt es gerade noch (Spieler ist da), wird begrenzt darauf gewartet.
    local function profileOf(userId: number): any?
        local profile = deps.getProfile(userId)
        local isLoading = deps.isLoading
        local wait = deps.wait
        if profile ~= nil or isLoading == nil or wait == nil then
            return profile
        end
        local deadline = clock() + PROFILE_WAIT_SECONDS
        while profile == nil and isLoading(userId) == true and clock() < deadline do
            wait(PROFILE_POLL_SECONDS)
            profile = deps.getProfile(userId)
        end
        return profile
    end

    -- Kritisches Fenster, Teil 1. Läuft über runAtOnce in einer eigenen Koroutine und darf nie warten:
    -- Kopie und Handler, Prüfung der Antwort, Uhr, Belege, Kaufprotokoll, `spent`, Kappen-Hinweis und
    -- erneute Prüfung. Ändert das Profil nicht. Gibt den Plan zurück oder nil (Grund protokolliert).
    local function planWrites(userId: number, purchaseId: string, product: Product, profile: any, handler: Handler, label: string): Plan?
        local cfg = configOf(data)
        -- 1. Handler auf Kopien von Profil und Produkt.
        local handled, answer = pcall(handler, deepCopy(profile), table.clone(product), data)
        if not handled then
            log(`{label}: Fehler im Handler: {tostring(answer)}, NotProcessedYet`)
            return nil
        end
        if answer == nil then
            log(`{label}: Handler lehnt die Gutschrift ab, NotProcessedYet`)
            return nil
        end
        local now = deps.now()
        local problem = problemOf(answer)
        if problem == nil then
            problem = schemaProblemOf(profile, answer.changes, cfg, now)
        end
        if problem ~= nil then
            log(`{label}: ungültige Antwort des Handlers ({problem}), NotProcessedYet`)
            return nil
        end
        local prepared: Prepared = answer

        -- 2. Belege, Kaufprotokoll und Ausgaben ausrechnen, alle Zuweisungen sammeln.
        local receipts = Profile.receiptList(profile.receipts)
        table.insert(receipts, purchaseId)
        receipts = keepNewest(receipts, cfg.receiptCacheSize)
        local purchaseLog = listCopy(profile.purchaseLog)
        table.insert(purchaseLog, {
            purchaseId = purchaseId,
            productId = product.id,
            gems = prepared.gems,
            robux = product.robux,
            time = now,
        })
        purchaseLog = keepNewest(purchaseLog, cfg.purchaseLogSize)
        local spent: { [string]: any } = if type(profile.spent) == "table" then table.clone(profile.spent) else {}
        spent.robux = wholeAtLeastZero(spent.robux) + product.robux
        spent.count = wholeAtLeastZero(spent.count) + 1

        local fields: { string } = {}
        for field in prepared.changes do
            table.insert(fields, field)
        end
        table.sort(fields)
        local writes: { Write } = {}
        for _, field in fields do
            table.insert(writes, { key = field, value = prepared.changes[field] })
        end
        table.insert(writes, { key = "receipts", value = receipts })
        table.insert(writes, { key = "purchaseLog", value = purchaseLog })
        table.insert(writes, { key = "spent", value = spent })

        if prepared.gems < product.gems then
            log(`{label}: bei maxGems gekappt, {prepared.gems} statt {product.gems} Gems gutgeschrieben`)
        end

        -- 3. Direkt vor dem Schreiben erneut prüfen: dasselbe Profil, Sitzung aktiv, noch nicht gebucht.
        if
            deps.getProfile(userId) ~= profile
            or deps.isSessionActive(userId) ~= true
            or Purchases.hasReceipt(profile, purchaseId)
        then
            log(`{label}: Profil oder Sitzung hat sich vor dem Schreiben geändert, NotProcessedYet`)
            return nil
        end
        return { writes = writes, announce = prepared.announce }
    end

    -- Gutschrift und Speichern für einen Kauf. Läuft nur unter der Sperre (runLocked) und in pcall.
    local function grantAndSave(userId: number, purchaseId: string, product: Product): Decision
        local label = `Kauf {purchaseId} ({product.id}) von Spieler {userId}`
        local profile = profileOf(userId)
        if profile == nil or deps.isSessionActive(userId) ~= true then
            log(`{label}: Profil nicht geladen oder Sitzung nicht aktiv, NotProcessedYet`)
            return NOT_PROCESSED
        end
        local cfg = configOf(data)
        local key = keyOf(userId, purchaseId)

        if Purchases.hasReceipt(profile, purchaseId) then
            log(`{label}: schon gutgeschrieben, keine neue Gutschrift, warte auf das Speichern`)
        else
            local handler = handlers[product.id]
            if handler == nil then
                log(`{label}: kein Handler für das Produkt, NotProcessedYet`)
                return NOT_PROCESSED
            end
            -- Kritisches Fenster: alles bis vor das Schreiben in einer Koroutine, die nie warten darf.
            local ran, plan = runAtOnce(function(): any
                return planWrites(userId, purchaseId, product, profile, handler, label)
            end)
            if not ran then
                log(`{label}: Abschnitt vor dem Schreiben {tostring(plan)}, nichts geschrieben, NotProcessedYet`)
                return NOT_PROCESSED
            end
            if plan == nil then
                return NOT_PROCESSED -- Grund schon protokolliert
            end
            local ready: Plan = plan

            -- Kritisches Fenster, Teil 2: direkt danach im selben Thread schreiben (nur Zuweisungen, kein
            -- Warten), alles oder nichts. Gutschrift und PurchaseId landen nur zusammen im Profil.
            local written, writeError = writeAll(profile, ready.writes)
            if not written then
                log(`{label}: Schreiben fehlgeschlagen und zurückgesetzt: {tostring(writeError)}, NotProcessedYet`)
                return NOT_PROCESSED
            end
            if ready.announce ~= nil then
                unannounced[key] = ready.announce
            end
        end

        if deps.saveAndWait(userId, purchaseId, cfg.saveTimeoutSeconds) ~= true then
            log(`{label}: Speichern nicht bestätigt, NotProcessedYet (Gutschrift und PurchaseId bleiben im Profil)`)
            return NOT_PROCESSED
        end

        -- Gespeichert. Die Meldung ist Nebensache: Ein Fehler dabei ändert das Ergebnis nicht. Sie läuft
        -- in einer eigenen Koroutine; wartet sie, wird sie geschlossen, damit die Sperre nie hängt.
        local announce = unannounced[key]
        unannounced[key] = nil
        local notify = deps.notify
        if announce ~= nil and notify ~= nil then
            local announceNow: Announce = announce
            local notifyNow: (number, string, { [string]: any }) -> () = notify
            local sent, err = runAtOnce(function(): any
                local kind, payload = announceNow(deepCopy(deps.getProfile(userId) or profile))
                notifyNow(userId, kind, payload)
                return nil
            end)
            if not sent then
                log(`{label}: Meldung an den Client nicht gesendet: {tostring(err)}`)
            end
        end
        return GRANTED
    end

    -- Wartet, bis ein laufender Vorgang fertig ist, und gibt dessen Ergebnis zurück. Die Grenze deckt
    -- alles ab, was der erste höchstens braucht (Warten aufs Profil plus Speichern), damit der zweite
    -- nie vor ihm aufgibt.
    local function waitFor(job: Job, label: string): Decision
        local wait = deps.wait
        if wait == nil then
            log(`{label}: läuft schon, ohne Warten NotProcessedYet`)
            return NOT_PROCESSED
        end
        local limit = PROFILE_WAIT_SECONDS + configOf(data).saveTimeoutSeconds + LOCK_EXTRA_SECONDS
        local deadline = clock() + limit
        while not job.done do
            if clock() >= deadline then
                log(`{label}: der erste Aufruf wurde nicht rechtzeitig fertig, NotProcessedYet`)
                return NOT_PROCESSED
            end
            wait(LOCK_POLL_SECONDS)
        end
        return job.result
    end

    -- Sperre je Spieler und PurchaseId: Ein zweiter Aufruf wartet auf das Ergebnis des ersten.
    local function runLocked(userId: number, purchaseId: string, product: Product): Decision
        local key = keyOf(userId, purchaseId)
        local running = inFlight[key]
        if running ~= nil then
            return waitFor(running, `Kauf {purchaseId} ({product.id}) von Spieler {userId}`)
        end
        local job: Job = { done = false, result = NOT_PROCESSED }
        inFlight[key] = job
        local ok, result = pcall(grantAndSave, userId, purchaseId, product)
        if not ok then
            log(`Kauf {purchaseId} ({product.id}) von Spieler {userId}: Fehler {tostring(result)}, NotProcessedYet`)
        end
        job.result = if ok and result == GRANTED then GRANTED else NOT_PROCESSED
        if job.result ~= GRANTED then
            -- Spieler nicht mehr da (oder Sitzung zu Ende): Die Meldung dieses Kaufs wird vergessen, damit
            -- nichts liegen bleibt, auch wenn `forget` schon vorher lief.
            local checked, active = pcall(deps.isSessionActive, userId)
            if not checked or active ~= true then
                unannounced[key] = nil
            end
        end
        job.done = true
        if inFlight[key] == job then
            inFlight[key] = nil
        end
        return job.result
    end

    -- Echtpfad: Beleg aus ProcessReceipt. Nur PlayerId, ProductId und PurchaseId zählen.
    function purchases.process(receipt: any): Decision
        local ok, result = pcall(function(): Decision
            if type(receipt) ~= "table" then
                log(`Beleg ist keine Tabelle ({type(receipt)}), NotProcessedYet`)
                return NOT_PROCESSED
            end
            local userId = receipt.PlayerId
            local productId = receipt.ProductId
            local purchaseId = receipt.PurchaseId
            if not isInteger(userId) or userId == 0 or not isPurchaseId(purchaseId) then
                log(`Beleg mit ungültiger PlayerId oder PurchaseId ({tostring(userId)}, {tostring(purchaseId)}), NotProcessedYet`)
                return NOT_PROCESSED
            end
            if not isInteger(productId) or productId <= 0 then
                log(`Kauf {purchaseId} von Spieler {userId}: ProductId {tostring(productId)} ist ein Platzhalter oder ungültig, NotProcessedYet`)
                return NOT_PROCESSED
            end
            local product = byProductId[productId]
            if product == nil then
                local why = if duplicateProductIds[productId] then "doppelt vergeben" else "unbekannt"
                log(`Kauf {purchaseId} von Spieler {userId}: ProductId {productId} ist {why}, NotProcessedYet`)
                return NOT_PROCESSED
            end
            if handlers[product.id] == nil then
                log(`Kauf {purchaseId} von Spieler {userId}: kein Handler für "{product.id}", NotProcessedYet`)
                return NOT_PROCESSED
            end
            return runLocked(userId, purchaseId, product)
        end)
        if not ok then
            log(`Beleg konnte nicht verarbeitet werden: {tostring(result)}, NotProcessedYet`)
            return NOT_PROCESSED
        end
        return if result == GRANTED then GRANTED else NOT_PROCESSED
    end

    -- Studio-Hilfe: Gem-Paket über die Paket-ID, PurchaseId mit DEBUG_PREFIX. Nur mit allowDebug.
    function purchases.processPack(userId: number, packId: string, purchaseId: string): Decision
        if deps.allowDebug ~= true then
            log("Studio-Kauf abgelehnt: die Studio-Hilfe ist auf diesem Server gesperrt")
            return NOT_PROCESSED
        end
        local ok, result = pcall(function(): Decision
            local fullId = if type(purchaseId) == "string" then DEBUG_PREFIX .. purchaseId else nil
            if not isInteger(userId) or userId == 0 or purchaseId == "" or not isPurchaseId(fullId) then
                log(`Studio-Kauf mit ungültiger PlayerId oder PurchaseId ({tostring(userId)}, {tostring(purchaseId)})`)
                return NOT_PROCESSED
            end
            local product = if type(packId) == "string" and packIds[packId] then byId[packId] else nil
            if product == nil then
                log(`Studio-Kauf von Spieler {userId}: unbekanntes Gem-Paket "{tostring(packId)}"`)
                return NOT_PROCESSED
            end
            return runLocked(userId, fullId :: string, product)
        end)
        if not ok then
            log(`Studio-Kauf konnte nicht verarbeitet werden: {tostring(result)}`)
            return NOT_PROCESSED
        end
        return if result == GRANTED then GRANTED else NOT_PROCESSED
    end

    -- Vergisst ausstehende Meldungen eines Spielers (beim Verlassen des Servers).
    function purchases.forget(userId: number)
        local prefix = `{userId}:`
        for key in unannounced do
            if string.sub(key, 1, #prefix) == prefix then
                unannounced[key] = nil
            end
        end
    end

    return purchases
end

return Purchases
