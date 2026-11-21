--!strict
-- Codes-System (Paket 5.2). Rein, ohne Roblox-API, Lune-Tests in tests/codes.spec.luau. Der
-- Codes-Service (Services/Codes) schließt die Remote `RedeemCode`, die Server-Uhren (os.time für
-- Gültigkeit und Boosts, os.clock für die Sperre), die Code-Tabelle, PlayerData und die Studio-Hilfe
-- an. Der Client schickt nur den eingegebenen Text; ob er gilt und was er gibt, entscheidet der Server.
--
-- WICHTIG: Dieses Modul liegt in src/shared und kennt KEINEN Code. Die Codes stehen nur auf dem
-- Server (src/server/Data/Codes) und werden jeder Funktion als Tabelle `{ list = { Zeile, ... } }`
-- übergeben. Ein Lune-Test sucht die Texte der Codes in src/shared und src/client.
--
-- Regeln:
--  * `normalize(text)`: nil bei Nicht-Text. Sonst Leerraum am Rand weg (Leerzeichen, Tab, Zeilenende),
--    Großbuchstaben, danach nur A-Z, 0-9 und Bindestrich, Länge MIN_LENGTH bis MAX_LENGTH, sonst nil.
--    Der Vergleich mit der Tabelle läuft immer über den normalisierten Text.
--  * Ein Code ist je Spieler und Code-ID einmal einlösbar: `profile.codes[id] = true`.
--  * `redeem(profile, tabelle, jetzt, text, ctx)`: Die erste nicht erfüllte Bedingung ist der Grund:
--      "noProfile"        kein Profil
--      "error"            kaputte Uhr, kaputte Tabelle, kaputter Merker profile.codes, kaputte Belohnung
--      "invalid"          Eingabe ungültig, Code unbekannt, noch nicht begonnen (jetzt < startsAt) oder
--                         abgelaufen (jetzt > endsAt). Alle vier geben denselben Grund, damit niemand
--                         erfährt, ob es einen Code gibt.
--      "alreadyRedeemed"  diese Code-ID ist im Profil schon eingelöst
--    Belohnungen (nie Kisten, Items oder Robux):
--      "gems"       `amount` Gems über Gems.grant (Quelle "code:<id>", gekappt bei maxGems; die
--                   Einlösung gilt trotzdem, die Antwort nennt die gutgeschriebene Menge)
--      "coinBoost"  Münz-Boost um `seconds` verlängern (Perks.extendCoinBoost)
--      "luck"       Glücks-Boost um `seconds` verlängern (Perks.extendLuckBoost)
--    Prüfen und Rechnen laufen wie bei Logic/Daily in einer eigenen Koroutine auf Arbeitskopien. Wirft
--    oder wartet sie (yield), wird sie geschlossen und nichts geschrieben ("error"). Danach weist
--    derselbe Thread nur fertige Werte zu (codes und je nach Belohnung gems oder boosts): Belohnung und
--    Merker zusammen oder gar nicht.
--    Ergebnis: `{ ok = true, codeId, reward }` oder `{ ok = false, reason, detail? }` (`detail` nur bei
--    "error", für das Server-Protokoll). `reward`:
--      { kind = "gems", amount, capped? }   amount = tatsächlich gutgeschrieben, capped = true bei maxGems
--      { kind = "coinBoost", seconds }      { kind = "luck", seconds }
--  * `attempt(zustand, jetzt, grenzen, run)`: falsche Versuche und Sperre je Spieler. Zustand
--    `{ failures, lockedUntil }` (nur im Speicher des Servers). Läuft eine Sperre (jetzt < lockedUntil),
--    wird `run` nicht gerufen: `{ ok = false, reason = "locked", secondsLeft }`. Sonst ruft attempt
--    `run()` (die Einlösung) und zählt das Ergebnis:
--      Erfolg                  Zähler zurück auf 0
--      "invalid"               Zähler + 1; erreicht er `maxFailures`, beginnt die Sperre von
--                              `lockSeconds` und schon diese Antwort ist "locked" (secondsLeft = Dauer)
--      jeder andere Grund      Zustand unverändert (alreadyRedeemed, busy, noProfile, error)
--    Eine abgelaufene Sperre verfällt, der Zähler beginnt neu bei 0. Fehlschläge gibt attempt immer nur
--    als `{ ok = false, reason }` zurück (nie `detail`), bei "locked" mit `secondsLeft` (ganz, ab 1).
--  * `check(tabelle, data?)`: Prüfung der Server-Tabelle beim Serverstart (wie DataCheck): eindeutige
--    id, eindeutiger Code, normalize(code) == code, nur bekannte Felder, bekannte Art je Belohnung mit
--    nur ihren Feldern, Gems ganz von 1 bis MAX_GEMS (und höchstens maxGems), Sekunden ganz von 1 bis
--    MAX_SECONDS, Zeiten endlich ab 0 und endsAt > startsAt. Gibt eine Liste von Fehlertexten zurück.
--  * Studio-Hilfe `parseDebug`: "reset" (alle Codes des Spielers wieder einlösbar).
--
-- `ctx.data` bzw. `data` ist für Tests überschreibbar ({ Economy }).

local Gems = require("./Gems")
local Perks = require("./Perks")
local EconomyData = require("../Data/Economy")

export type Reason = "noProfile" | "invalid" | "alreadyRedeemed" | "error"
export type RewardKind = "gems" | "coinBoost" | "luck"

export type Reward = {
    kind: RewardKind,
    amount: number?, -- nur bei "gems"
    seconds: number?, -- nur bei "coinBoost" und "luck"
}

export type Row = {
    id: string, -- Schlüssel in profile.codes, nie umbenennen
    code: string, -- normalisierter Text, den der Spieler eingibt
    reward: Reward,
    startsAt: number?, -- Unix-Zeit, ab der der Code gilt
    endsAt: number?, -- Unix-Zeit, bis zu der der Code gilt (einschließlich)
}

export type CodeTable = { list: { Row } }

export type Context = {
    data: any?, -- Tests: { Economy }
}

export type AttemptState = { failures: number, lockedUntil: number }
export type Limits = { maxFailures: number, lockSeconds: number }

local Codes = {}

-- Länge eines normalisierten Codes (gleich im Schema der Remote, Net/RemoteSpec).
Codes.MIN_LENGTH = 1
Codes.MAX_LENGTH = 24
-- Länge einer Code-ID (Schlüssel im Profil).
Codes.MAX_ID_LENGTH = 32
-- Obergrenzen je Belohnung (Prüfung der Tabelle und noch einmal beim Einlösen).
Codes.MAX_GEMS = 1000
Codes.MAX_SECONDS = 86400
-- Erlaubte Felder je Art der Belohnung. Andere Arten (Kisten, Items, Robux) gibt es nicht.
Codes.REWARD_FIELDS = {
    gems = { kind = true, amount = true },
    coinBoost = { kind = true, seconds = true },
    luck = { kind = true, seconds = true },
} :: { [string]: { [string]: boolean } }
-- Gründe.
Codes.INVALID = "invalid"
Codes.LOCKED = "locked"
-- Studio-Hilfe: Befehl des Attributs DebugCodes.
Codes.DEBUG_RESET = "reset"

-- Erlaubte Felder einer Zeile der Tabelle (ein Tippfehler wie `endAt` fällt in `check` auf).
local ROW_FIELDS: { [string]: boolean } = { id = true, code = true, reward = true, startsAt = true, endsAt = true }
-- Normalisierter Code: nur Großbuchstaben, Ziffern und Bindestrich.
local CODE_PATTERN = "^[A-Z0-9%-]+$"
-- Code-ID: Buchstaben, Ziffern, Unterstrich und Bindestrich.
local ID_PATTERN = "^[%w_%-]+$"
-- Herkunftstext der Gem-Gutschrift (Gems.grant verlangt einen), dahinter die Code-ID.
local GEMS_SOURCE_PREFIX = "code:"
local DEBUG_MAX_LENGTH = 16

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isWholePositive(value: any): boolean
    return isFinite(value) and value > 0 and value % 1 == 0
end

-- Leerraum wie %s: Tab, Zeilenvorschub, vertikaler Tab, Seitenvorschub, Wagenrücklauf, Leerzeichen.
local function isSpaceByte(byte: number): boolean
    return byte == 32 or (byte >= 9 and byte <= 13)
end

local function fail(reason: Reason, detail: string?): any
    return { ok = false, reason = reason, detail = detail }
end

-- Normalisiert eine Eingabe (siehe Kopf der Datei). nil, wenn sie kein gültiger Code sein kann.
function Codes.normalize(text: any): string?
    if type(text) ~= "string" then
        return nil
    end
    local first = string.find(text, "%S")
    if first == nil then
        return nil
    end
    local last = #text
    while last > first and isSpaceByte(string.byte(text, last)) do
        last -= 1
    end
    local length = last - first + 1
    if length < Codes.MIN_LENGTH or length > Codes.MAX_LENGTH then
        return nil
    end
    local upper = string.upper(string.sub(text, first, last))
    if string.find(upper, CODE_PATTERN) == nil then
        return nil
    end
    return upper
end

-- Liste der Zeilen. Wirft bei kaputter Tabelle (check verhindert das beim Start).
local function rowsOf(codeTable: any): any
    if type(codeTable) ~= "table" or type(codeTable.list) ~= "table" then
        error("Codes: Code-Tabelle ohne Liste")
    end
    return codeTable.list
end

-- Zeile zum normalisierten Text, sonst nil. Der Code der Zeile wird ebenfalls normalisiert.
local function findRow(codeTable: any, normalized: string): any
    for _, row in rowsOf(codeTable) do
        if type(row) == "table" and Codes.normalize(row.code) == normalized then
            return row
        end
    end
    return nil
end

-- Gilt die Zeile zur Unix-Zeit `unixNow`? Kaputte Zeiten zählen wie "gilt nicht" (fail-closed).
local function inWindow(row: any, unixNow: number): boolean
    local startsAt = row.startsAt
    if startsAt ~= nil and (not isFinite(startsAt) or unixNow < startsAt) then
        return false
    end
    local endsAt = row.endsAt
    if endsAt ~= nil and (not isFinite(endsAt) or unixNow > endsAt) then
        return false
    end
    return true
end

-- Ist die Code-ID im Profil schon eingelöst? Jeder Wert außer nil und false zählt als eingelöst
-- (lieber einmal zu viel ablehnen als doppelt buchen).
local function isMarked(codes: any, codeId: string): boolean
    if type(codes) ~= "table" then
        return false
    end
    local value = codes[codeId]
    return value ~= nil and value ~= false
end

-- Ist die Code-ID im Profil schon eingelöst? (Für Anzeige und Tests.)
function Codes.isRedeemed(profile: any, codeId: string): boolean
    return type(profile) == "table" and isMarked(profile.codes, codeId)
end

-- Prüft und rechnet die Einlösung auf Arbeitskopien. Schreibt nichts ins Profil. Gibt entweder ein
-- Fehlschlag-Ergebnis zurück oder `{ write = ..., response = ... }`.
local function prepare(profile: any, codeTable: any, unixNow: any, text: any, ctx: any): any
    local data = ctx.data
    if type(profile) ~= "table" then
        return fail("noProfile")
    end
    if not isFinite(unixNow) or unixNow < 0 then
        error(`Codes: ungültige Uhr {tostring(unixNow)}`)
    end
    local normalized = Codes.normalize(text)
    if normalized == nil then
        return fail("invalid")
    end
    local row = findRow(codeTable, normalized)
    if row == nil then
        return fail("invalid")
    end
    local codeId = row.id
    if type(codeId) ~= "string" or codeId == "" then
        error("Codes: Zeile ohne gültige id")
    end
    local codes = profile.codes
    if codes ~= nil and type(codes) ~= "table" then
        -- Ohne lesbaren Merker ist nicht bekannt, was schon eingelöst ist: nichts buchen.
        error(`Codes: profile.codes ist {type(codes)} statt Tabelle`)
    end
    if isMarked(codes, codeId) then
        return fail("alreadyRedeemed")
    end
    if not inWindow(row, unixNow) then
        return fail("invalid")
    end

    local reward = row.reward
    if type(reward) ~= "table" then
        error(`Codes: Belohnung von "{codeId}" fehlt`)
    end
    local newCodes = if codes ~= nil then table.clone(codes) else {}
    newCodes[codeId] = true
    local write: { [string]: any } = { codes = newCodes }
    local response: { [string]: any } = { ok = true, codeId = codeId }
    local kind = reward.kind
    if kind == "gems" then
        local amount = reward.amount
        if not isWholePositive(amount) or amount > Codes.MAX_GEMS then
            error(`Codes: ungültige Gems {tostring(amount)} bei "{codeId}"`)
        end
        local wallet = { gems = Gems.balance(profile, data) }
        local added = Gems.grant(wallet, amount, GEMS_SOURCE_PREFIX .. codeId, data)
        if added > 0 then
            write.gems = wallet.gems
        end
        response.reward = { kind = "gems", amount = added, capped = if added < amount then true else nil }
    elseif kind == "coinBoost" or kind == "luck" then
        local seconds = reward.seconds
        if not isWholePositive(seconds) or seconds > Codes.MAX_SECONDS then
            error(`Codes: ungültige Dauer {tostring(seconds)} bei "{codeId}"`)
        end
        local extend = if kind == "coinBoost" then Perks.extendCoinBoost else Perks.extendLuckBoost
        local boosts = extend(profile.boosts, unixNow, seconds)
        if boosts == nil then
            error(`Codes: Boost von "{codeId}" ließ sich nicht verlängern`)
        end
        write.boosts = boosts
        response.reward = { kind = kind, seconds = seconds }
    else
        -- Kisten, Items, Robux und alles Unbekannte: nie.
        error(`Codes: unbekannte Art {tostring(kind)} bei "{codeId}"`)
    end
    return { write = write, response = response }
end

-- Führt `prepare` in einer eigenen Koroutine aus. Wartet sie (yield), wird sie geschlossen.
local function prepareWithoutYield(profile: any, codeTable: any, unixNow: any, text: any, ctx: any): (boolean, any)
    local routine = coroutine.create(prepare)
    local resumed, result = coroutine.resume(routine, profile, codeTable, unixNow, text, ctx)
    if coroutine.status(routine) ~= "dead" then
        coroutine.close(routine)
        return false, "Codes: die Einlösung hat gewartet (yield) und wurde abgebrochen"
    end
    return resumed, result
end

-- Löst einen Code ein. Siehe Kopf der Datei.
function Codes.redeem(profile: any, codeTable: any, unixNow: number, text: any, ctx: Context?): any
    local context = if type(ctx) == "table" then ctx else {}
    local ok, prepared = prepareWithoutYield(profile, codeTable, unixNow, text, context)
    if not ok then
        return fail("error", tostring(prepared))
    end
    if prepared.write == nil then
        return prepared -- Ablehnung mit Grund, nichts geschrieben
    end
    -- Ab hier nur Zuweisungen fertiger Werte, im selben Thread direkt nach der Rechnung.
    local write = prepared.write
    if write.gems ~= nil then
        profile.gems = write.gems
    end
    if write.boosts ~= nil then
        profile.boosts = write.boosts
    end
    profile.codes = write.codes
    return prepared.response
end

-- Neuer Zustand ohne Fehlversuche und ohne Sperre.
function Codes.newAttemptState(): AttemptState
    return { failures = 0, lockedUntil = 0 }
end

-- Ist der Zustand leer (keine Fehlversuche, keine Sperre)? Dann muss der Service ihn nicht behalten.
function Codes.isIdle(state: any): boolean
    return type(state) ~= "table" or ((state.failures or 0) == 0 and (state.lockedUntil or 0) == 0)
end

-- Gesäuberte Kopie des Zustands zur Zeit `now`. Eine abgelaufene Sperre verfällt (Zähler neu bei 0).
local function cleanState(state: any, now: number): AttemptState
    if type(state) ~= "table" then
        return Codes.newAttemptState()
    end
    local failures = if isFinite(state.failures) and state.failures >= 0 then math.floor(state.failures) else 0
    local lockedUntil = if isFinite(state.lockedUntil) and state.lockedUntil >= 0 then state.lockedUntil else 0
    if lockedUntil > 0 and now >= lockedUntil then
        return Codes.newAttemptState()
    end
    return { failures = failures, lockedUntil = lockedUntil }
end

-- Restsekunden der Sperre zur Zeit `now` (aufgerundet, 0 = nicht gesperrt).
function Codes.lockSecondsLeft(state: any, now: number): number
    if not isFinite(now) then
        return 0
    end
    local current = cleanState(state, now)
    if current.lockedUntil > now then
        return math.ceil(current.lockedUntil - now)
    end
    return 0
end

local function checkLimits(limits: any)
    if type(limits) ~= "table" or not isWholePositive(limits.maxFailures) or not isFinite(limits.lockSeconds) or limits.lockSeconds <= 0 then
        error("Codes.attempt: Grenzen maxFailures (ganz ab 1) und lockSeconds (über 0) fehlen oder sind ungültig")
    end
end

-- Ein Versuch mit Zähler und Sperre (siehe Kopf der Datei). Gibt (Antwort, neuer Zustand) zurück und
-- ändert `state` nicht. `run` ist die Einlösung und gibt `{ ok, reason? }` zurück.
function Codes.attempt(state: any, now: number, limits: Limits, run: () -> any): (any, AttemptState)
    checkLimits(limits)
    if not isFinite(now) then
        -- Kaputte Uhr: Sperre nicht prüfbar, also nicht einlösen (fail-closed), nichts zählen.
        return { ok = false, reason = "error" }, cleanState(state, -math.huge)
    end
    local current = cleanState(state, now)
    if current.lockedUntil > now then
        return { ok = false, reason = Codes.LOCKED, secondsLeft = math.ceil(current.lockedUntil - now) }, current
    end
    local okRun, result = pcall(run)
    if not okRun or type(result) ~= "table" then
        return { ok = false, reason = "error" }, current
    end
    if result.ok == true then
        return result, Codes.newAttemptState()
    end
    local reason = result.reason
    if reason == Codes.INVALID then
        local failures = current.failures + 1
        if failures >= limits.maxFailures then
            local locked = { failures = 0, lockedUntil = now + limits.lockSeconds }
            return { ok = false, reason = Codes.LOCKED, secondsLeft = math.ceil(limits.lockSeconds) }, locked
        end
        return { ok = false, reason = Codes.INVALID }, { failures = failures, lockedUntil = 0 }
    end
    return { ok = false, reason = if type(reason) == "string" then reason else "error" }, current
end

-- Prüft die Code-Tabelle des Servers (siehe Kopf der Datei). Leere Liste = alles in Ordnung. Die
-- Fehlertexte nennen die Code-ID, nie den Text des Codes.
function Codes.check(codeTable: any, data: any?): { string }
    local errors: { string } = {}
    if type(codeTable) ~= "table" or type(codeTable.list) ~= "table" then
        table.insert(errors, "Codes: Tabelle mit Feld list fehlt")
        return errors
    end
    local list = codeTable.list
    local entries = 0
    for key in list do
        entries += 1
        if type(key) ~= "number" then
            table.insert(errors, `Codes.list: Schlüssel {tostring(key)} gehört nicht in eine Liste`)
        end
    end
    if entries ~= #list then
        table.insert(errors, "Codes.list ist keine lückenlose Liste")
    end
    local economy = if data ~= nil and data.Economy ~= nil then data.Economy else EconomyData
    local purchases = if type(economy) == "table" then economy.purchases else nil
    local maxGems = Codes.MAX_GEMS
    if type(purchases) == "table" and isFinite(purchases.maxGems) then
        maxGems = math.min(maxGems, purchases.maxGems)
    end
    local seenIds: { [string]: number } = {}
    local seenCodes: { [string]: number } = {}
    for index = 1, #list do
        local row = list[index]
        local label = `Codes.list[{index}]`
        if type(row) ~= "table" then
            table.insert(errors, `{label}: keine Tabelle`)
            continue
        end
        for key in row do
            if not ROW_FIELDS[key] then
                table.insert(errors, `{label}: Feld "{tostring(key)}" ist unbekannt`)
            end
        end
        local id = row.id
        if type(id) ~= "string" or #id < 1 or #id > Codes.MAX_ID_LENGTH or string.find(id, ID_PATTERN) == nil then
            table.insert(errors, `{label}: id muss Text aus Buchstaben, Ziffern, _ und - sein (1 bis {Codes.MAX_ID_LENGTH} Zeichen)`)
        else
            label = `{label} ("{id}")`
            if seenIds[id] ~= nil then
                table.insert(errors, `{label}: id doppelt (auch Codes.list[{seenIds[id]}])`)
            else
                seenIds[id] = index
            end
        end
        local code = row.code
        if type(code) ~= "string" or Codes.normalize(code) ~= code then
            table.insert(errors, `{label}: code muss normalisiert sein (A-Z, 0-9 und -, {Codes.MIN_LENGTH} bis {Codes.MAX_LENGTH} Zeichen, ohne Leerraum)`)
        elseif seenCodes[code] ~= nil then
            table.insert(errors, `{label}: code doppelt (auch Codes.list[{seenCodes[code]}])`)
        else
            seenCodes[code] = index
        end
        local reward = row.reward
        local fields = if type(reward) == "table" and type(reward.kind) == "string" then Codes.REWARD_FIELDS[reward.kind] else nil
        if fields == nil then
            table.insert(errors, `{label}: reward.kind muss "gems", "coinBoost" oder "luck" sein (nie Kisten, Items oder Robux)`)
        else
            for key in reward do
                if not fields[key] then
                    table.insert(errors, `{label}: Feld reward.{tostring(key)} gehört nicht zur Art "{reward.kind}"`)
                end
            end
            if reward.kind == "gems" then
                if not isWholePositive(reward.amount) or reward.amount > maxGems then
                    table.insert(errors, `{label}: reward.amount muss eine ganze Zahl von 1 bis {maxGems} sein`)
                end
            elseif not isWholePositive(reward.seconds) or reward.seconds > Codes.MAX_SECONDS then
                table.insert(errors, `{label}: reward.seconds muss eine ganze Zahl von 1 bis {Codes.MAX_SECONDS} sein`)
            end
        end
        local startsAt, endsAt = row.startsAt, row.endsAt
        local timesOk = true
        for _, entry in { { name = "startsAt", value = startsAt }, { name = "endsAt", value = endsAt } } do
            if entry.value ~= nil and (not isFinite(entry.value) or entry.value < 0) then
                table.insert(errors, `{label}: {entry.name} muss eine endliche Unix-Zeit ab 0 sein`)
                timesOk = false
            end
        end
        if timesOk and startsAt ~= nil and endsAt ~= nil and endsAt <= startsAt then
            table.insert(errors, `{label}: endsAt muss nach startsAt liegen`)
        end
    end
    return errors
end

-- Studio-Hilfe: liest den Wert des Attributs DebugCodes. Gibt ("reset", nil) oder (nil, Problem) zurück.
function Codes.parseDebug(value: any): (string?, string?)
    local usage = `erwartet "{Codes.DEBUG_RESET}"`
    if type(value) ~= "string" or value == "" or #value > DEBUG_MAX_LENGTH then
        return nil, usage
    end
    if value == Codes.DEBUG_RESET then
        return value, nil
    end
    return nil, `"{value}": {usage}`
end

return Codes
