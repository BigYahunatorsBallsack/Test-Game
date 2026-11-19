--!strict
-- Gamepass-Besitz (Paket 4.4). Rein, ohne Roblox-API, Lune-Tests in tests/passes.spec.luau.
-- Der Passes-Service (src/server/Services/Passes.luau) gibt MarketplaceService, Uhr und Warten als
-- Funktionen herein und schreibt nur, was die Entscheidungen hier ergeben.
--
-- Spielstand: `profile.passes = { [passId] = true }`. `passId` ist die Produkt-ID eines Gamepasses
-- aus Data/Products (kind "gamepass"), zum Beispiel "double_coins". Nur der Server schreibt das Feld,
-- es ist der gemerkte Besitz. Was ein Pass bewirkt, steht in Logic/Perks (über `perk`).
--
-- Regeln:
--  1. Abfrage beim Laden (runCheck mit UserOwnsGamePassAsync, je Gamepass mit productId > 0): Nur
--     eine Antwort true/false zählt. "Ja" trägt sofort ein. "Nein" entfernt erst, wenn auch die
--     nächste Runde (nach recheckSeconds) "nein" sagt; ein Fehler dazwischen behält den Pass und die
--     Zählung beginnt neu (Security-Review 4.4: ein veraltetes "nein" nach einem Serverwechsel direkt
--     nach dem Kauf nimmt den Pass nicht weg). Ausnahmen, in denen "nein" nie entfernt:
--       * in Studio (Testkäufe zählen bei Roblox nicht als Besitz),
--       * der Pass wurde in dieser Sitzung gekauft UND von Roblox bestätigt (siehe 2).
--     Schlägt die Abfrage fehl (Fehler, keine true/false-Antwort, alle Versuche), bleibt der
--     gemerkte Besitz, die nächste Runde fragt erneut. ProductId 0 (Platzhalter): keine Abfrage.
--  2. Kauf-Ereignis (PromptGamePassPurchaseFinished, newPurchaseConfirmer): Das Ereignis allein trägt
--     nie etwas ein, weil ein Exploit es fälschen kann (Security-Review 4.4). Bei einer Gamepass-ID,
--     die zu genau einem Gamepass gehört (ganze Zahl > 0), startet eine Abfrage bei Roblox (egal, was
--     `wasPurchased` sagt); nur bei der Antwort "ja" wird der Pass eingetragen und als "in dieser
--     Sitzung gekauft" gemerkt. Je Spieler und Pass läuft höchstens eine Prüfung, ein schon
--     eingetragener Pass wird gar nicht erst abgefragt (Schutz des Anfragebudgets), unbekannte IDs
--     starten nichts. Nur in Studio (`trustEvent`) gilt `wasPurchased == true` ohne Abfrage, weil
--     Studio-Testkäufe bei Roblox nie als Besitz zählen.
--  3. Jede Entscheidung gibt eine NEUE Tabelle zurück oder nil (keine Änderung). Die neue Tabelle
--     enthält nur bekannte Pässe mit Wert true (wie Profile.sanitize), das Profil wird hier nie
--     verändert. Der Service rechnet vorher mit Sand.settle ab, schreibt ohne Warten und sendet
--     danach den Zustand.
--
-- Der optionale Parameter `data` ist für Tests: { Products }.

local ProductsData = require("../Data/Products")

-- Gamepass aus den Daten (nur die Felder, die hier zählen).
export type Pass = { id: string, productId: number, perk: string?, name: string }

-- Ergebnis einer Besitzabfrage: ok = eine gültige Antwort kam, owns = die Antwort.
export type CheckResult = { ok: boolean, owns: boolean? }

export type CheckContext = {
    studio: boolean?, -- in Studio entfernt ein "nein" nie einen Pass
    boughtThisSession: boolean?, -- in dieser Sitzung gekauft und von Roblox bestätigt: "nein" entfernt nie
    previousNo: boolean?, -- die Runde davor sagte schon "nein" (erst das zweite "nein" entfernt)
}

-- Was eine Entscheidung ergibt: eingetragen, entfernt oder "erstes Nein, später erneut fragen".
export type Change = "granted" | "revoked" | "confirmNo"

-- Ergebnis eines ganzen Prüf-Ablaufs beim Laden (runCheck).
export type CheckOutcome = "granted" | "revoked" | "unchanged" | "kept" | "gone"

export type CheckRunDeps = {
    passId: string,
    ask: () -> CheckResult, -- eine Runde mit Versuchen (im Spiel Passes.ask mit UserOwnsGamePassAsync), darf warten
    wait: (seconds: number) -> (), -- Pause zwischen Runden
    stillValid: () -> boolean, -- Spieler noch da und dasselbe Profil
    passesOf: () -> any, -- aktueller gemerkter Besitz (lebendes Profil)
    context: () -> CheckContext, -- Studio und "in dieser Sitzung bestätigt gekauft", live gelesen
    write: (newPasses: { [string]: boolean }, change: Change) -> (), -- settle, schreiben, refresh; wartet nie
    rounds: number, -- höchstens so viele Runden
    recheckSeconds: number, -- Pause zwischen Runden (Fehler und erstes "nein")
    log: ((message: string) -> ())?,
    data: any?,
}

export type ConfirmDeps = {
    query: (owner: any, gamePassId: number) -> CheckResult, -- eine Runde mit Versuchen, darf warten
    wait: (seconds: number) -> (),
    spawn: (fn: () -> ()) -> (), -- im Spiel task.spawn
    isPresent: (owner: any) -> boolean, -- Spieler ist noch auf dem Server
    passesOf: (owner: any) -> any?, -- gemerkter Besitz, nil = Profil noch nicht geladen
    grant: (owner: any, passId: string, newPasses: { [string]: boolean }) -> (), -- settle, schreiben, refresh; wartet nie
    remember: (owner: any, passId: string) -> (), -- "in dieser Sitzung gekauft und bestätigt"
    rounds: number, -- Runden, wenn wasPurchased == true (gegen einen veralteten Zwischenspeicher), sonst 1
    retrySeconds: number, -- Pause zwischen diesen Runden
    trustEvent: boolean?, -- NUR Studio: wasPurchased == true ohne Abfrage glauben
    log: ((message: string, owner: any) -> ())?,
    data: any?,
}

-- Was ein Kauf-Ereignis ausgelöst hat (für Tests und das Protokoll).
export type ConfirmStart = "absent" | "unknown" | "owned" | "busy" | "started" | "trusted"

export type Confirmer = {
    onPurchaseFinished: (owner: any, gamePassId: any, wasPurchased: any) -> ConfirmStart,
    isRunning: (owner: any, passId: string) -> boolean,
    forget: (owner: any) -> (),
}

-- Wie das Studio-Attribut "DebugPass" gelesen wird: "big_tank" schaltet an, "-big_tank" aus.
local DEBUG_OFF_PREFIX = "-"
local DEBUG_PATTERN = "^(%-?)([%w_]+)$"
local DEBUG_MAX_LENGTH = 64

local Passes = {}
Passes.DEBUG_OFF_PREFIX = DEBUG_OFF_PREFIX

local function productsOf(data: any?): any
    return if data ~= nil and data.Products ~= nil then data.Products else ProductsData
end

local function isPositiveInteger(value: any): boolean
    return type(value) == "number" and value == value and value > 0 and value < math.huge and value % 1 == 0
end

-- Alle Gamepasses aus Data/Products, in Tabellenreihenfolge.
function Passes.list(data: any?): { Pass }
    local result: { Pass } = {}
    for _, product in productsOf(data).list do
        if product.kind == "gamepass" and type(product.id) == "string" then
            table.insert(result, { id = product.id, productId = product.productId, perk = product.perk, name = product.name })
        end
    end
    return result
end

-- Ist `passId` ein Gamepass aus Data/Products?
function Passes.isKnown(passId: any, data: any?): boolean
    if type(passId) ~= "string" then
        return false
    end
    local product = productsOf(data).byId[passId]
    return product ~= nil and product.kind == "gamepass"
end

-- Gamepasses, deren Besitz bei Roblox abgefragt wird (productId ganze Zahl > 0).
function Passes.toCheck(data: any?): { Pass }
    local result: { Pass } = {}
    for _, pass in Passes.list(data) do
        if isPositiveInteger(pass.productId) then
            table.insert(result, pass)
        end
    end
    return result
end

-- Pass-ID zu einer Roblox-Gamepass-ID. nil bei 0, ungültig, unbekannt oder doppelt vergeben
-- (nicht raten, welcher Pass gemeint ist; DataCheck meldet doppelte IDs auch).
function Passes.idForGamePassId(gamePassId: any, data: any?): string?
    if not isPositiveInteger(gamePassId) then
        return nil
    end
    local found: string? = nil
    for _, pass in Passes.list(data) do
        if pass.productId == gamePassId then
            if found ~= nil then
                return nil
            end
            found = pass.id
        end
    end
    return found
end

-- Gemerkter Besitz als neue Tabelle: nur bekannte Pässe mit Wert true.
function Passes.owned(profile: any, data: any?): { [string]: boolean }
    local result: { [string]: boolean } = {}
    local passes = if type(profile) == "table" then profile.passes else nil
    if type(passes) == "table" then
        for passId, value in passes do
            if value == true and Passes.isKnown(passId, data) then
                result[passId] = true
            end
        end
    end
    return result
end

function Passes.owns(profile: any, passId: string, data: any?): boolean
    return Passes.owned(profile, data)[passId] == true
end

-- Neue Besitz-Tabelle mit (owned = true) oder ohne (false) den Pass. Unbekannte Pässe ändern nichts.
function Passes.with(passes: any, passId: string, owned: boolean, data: any?): { [string]: boolean }
    local result = Passes.owned({ passes = passes }, data)
    if Passes.isKnown(passId, data) then
        result[passId] = if owned then true else nil
    end
    return result
end

-- Fragt den Besitz ab: höchstens `attempts` Versuche, dazwischen `wait(pauseSeconds)`. Nur eine
-- Antwort true/false zählt; Fehler (pcall) und alles andere gelten als gescheitert. `stillValid`
-- (optional) beendet die Versuche, wenn der Spieler inzwischen weg ist. Wartet (über `wait`).
function Passes.ask(
    query: () -> any,
    attempts: number,
    pauseSeconds: number,
    wait: (seconds: number) -> (),
    log: ((message: string) -> ())?,
    stillValid: (() -> boolean)?
): CheckResult
    local count = math.max(math.floor(attempts), 1)
    for attempt = 1, count do
        local ok, answer = pcall(query)
        if ok and type(answer) == "boolean" then
            return { ok = true, owns = answer }
        end
        if log ~= nil then
            log(`Versuch {attempt} von {count} gescheitert ({if ok then "keine true/false-Antwort" else tostring(answer)})`)
        end
        if stillValid ~= nil and not stillValid() then
            return { ok = false }
        end
        if attempt < count then
            wait(pauseSeconds)
            if stillValid ~= nil and not stillValid() then
                return { ok = false }
            end
        end
    end
    return { ok = false }
end

-- Wendet das Ergebnis einer Abfrage für `passId` an. Gibt die neue Tabelle und die Art der Änderung
-- zurück, oder nil, wenn sich nichts ändert (Fehler, unbekannter Pass, schon so, Studio-"nein",
-- in dieser Sitzung bestätigt gekauft und "nein"). Ein "nein" für einen eingetragenen Pass ohne
-- `previousNo` gibt (nil, "confirmNo"): nicht entfernen, nach einer Pause erneut fragen.
function Passes.decideCheck(passes: any, passId: string, result: CheckResult, context: CheckContext?, data: any?): ({ [string]: boolean }?, Change?)
    if not Passes.isKnown(passId, data) or type(result) ~= "table" or result.ok ~= true or type(result.owns) ~= "boolean" then
        return nil, nil -- gemerkter Besitz bleibt
    end
    local current = Passes.owned({ passes = passes }, data)
    if result.owns == true then
        if current[passId] == true then
            return nil, nil -- schon eingetragen
        end
        return Passes.with(passes, passId, true, data), "granted"
    end
    local ctx: CheckContext = context or {}
    if ctx.studio == true or ctx.boughtThisSession == true or current[passId] ~= true then
        return nil, nil
    end
    if ctx.previousNo ~= true then
        return nil, "confirmNo"
    end
    return Passes.with(passes, passId, false, data), "revoked"
end

-- Prüf-Ablauf beim Laden für einen Gamepass (der Service startet ihn je Pass in einem eigenen Thread).
-- Runden im Abstand `recheckSeconds`, höchstens `rounds`: "ja" trägt ein, das zweite "nein" in Folge
-- entfernt, ein Fehler behält den gemerkten Besitz und setzt die Nein-Zählung zurück. Entscheidung und
-- Schreiben folgen ohne Warten aufeinander. Wartet (über deps.ask und deps.wait).
function Passes.runCheck(deps: CheckRunDeps): CheckOutcome
    local function log(message: string)
        if deps.log ~= nil then
            deps.log(message)
        end
    end
    local rounds = math.max(math.floor(deps.rounds), 1)
    local previousNo = false
    for round = 1, rounds do
        if round > 1 then
            deps.wait(deps.recheckSeconds)
        end
        if not deps.stillValid() then
            return "gone"
        end
        local ok, result = pcall(deps.ask)
        if not deps.stillValid() then
            return "gone"
        end
        if ok and type(result) == "table" and result.ok == true then
            local ctx: CheckContext = table.clone(deps.context() or {})
            ctx.previousNo = previousNo
            local newPasses, change = Passes.decideCheck(deps.passesOf(), deps.passId, result, ctx, deps.data)
            if newPasses ~= nil and change ~= nil then
                deps.write(newPasses, change)
                return if change == "granted" then "granted" else "revoked"
            end
            if change ~= "confirmNo" then
                return "unchanged"
            end
            previousNo = true
            log(`{deps.passId}: Roblox sagt "nein", der Pass bleibt bis zum zweiten "nein" (Runde {round} von {rounds})`)
        else
            previousNo = false -- ein Fehler zwischen zwei "nein" behält den Pass, die Zählung beginnt neu
            log(`{deps.passId}: Abfrage gescheitert, gemerkter Besitz bleibt (Runde {round} von {rounds})`)
        end
    end
    return "kept"
end

-- Trägt einen von Roblox bestätigten Kauf ein. Gibt die neue Tabelle zurück oder nil (unbekannt oder
-- schon eingetragen).
function Passes.decideConfirmedPurchase(passes: any, passId: string, data: any?): { [string]: boolean }?
    if not Passes.isKnown(passId, data) or Passes.owned({ passes = passes }, data)[passId] == true then
        return nil
    end
    return Passes.with(passes, passId, true, data)
end

-- Bestätigung von Kauf-Ereignissen (PromptGamePassPurchaseFinished) über eine Abfrage bei Roblox.
-- `onPurchaseFinished` läuft ohne Warten und startet höchstens einen Thread je Spieler und Pass
-- (deps.spawn). Darin: bis zu `rounds` Runden (bei wasPurchased == true, sonst eine; ein späteres
-- Ereignis mit wasPurchased == true verlängert eine laufende Prüfung), bei "ja" sofort weiter. Danach wird der Pass nur gemerkt (deps.remember) und eingetragen (deps.grant), wenn Roblox
-- "ja" sagte und der Spieler noch da ist. Ist das Profil noch nicht geladen, trägt der Service ihn
-- beim Laden über withBought ein.
function Passes.newPurchaseConfirmer(deps: ConfirmDeps): Confirmer
    local data = deps.data
    -- Laufende Prüfungen je Spieler und Pass mit der Zahl der Runden, die sie machen sollen.
    local running: { [any]: { [string]: { rounds: number } } } = {}
    local fullRounds = math.max(math.floor(deps.rounds), 1)

    local function log(message: string, owner: any)
        if deps.log ~= nil then
            pcall(deps.log, message, owner)
        end
    end

    local function finish(owner: any, passId: string)
        local set = running[owner]
        if set ~= nil then
            set[passId] = nil
            if next(set) == nil then
                running[owner] = nil
            end
        end
    end

    -- Bestätigt: merken und eintragen (ohne Warten zwischen Lesen und Schreiben).
    local function apply(owner: any, passId: string)
        deps.remember(owner, passId)
        local passes = deps.passesOf(owner)
        if passes == nil then
            log(`{passId}: Kauf bestätigt, Profil noch nicht geladen, wird beim Laden eingetragen`, owner)
            return
        end
        local newPasses = Passes.decideConfirmedPurchase(passes, passId, data)
        if newPasses ~= nil then
            deps.grant(owner, passId, newPasses)
        end
    end

    -- `entry.rounds` wird je Runde neu gelesen: Ein Kauf-Ereignis mit wasPurchased == true, das
    -- kommt, während eine kurze Prüfung läuft (zum Beispiel nach einem abgebrochenen Kauffenster),
    -- verlängert sie auf alle Runden, statt verloren zu gehen.
    local function confirm(owner: any, gamePassId: number, passId: string, entry: { rounds: number })
        local confirmed = false
        local worked, err = pcall(function()
            local round = 0
            while round < entry.rounds do
                round += 1
                if round > 1 then
                    deps.wait(deps.retrySeconds)
                end
                if not deps.isPresent(owner) then
                    return
                end
                local ok, result = pcall(deps.query, owner, gamePassId)
                if ok and type(result) == "table" and result.ok == true and result.owns == true then
                    confirmed = true
                    return
                end
            end
        end)
        finish(owner, passId)
        if not worked then
            log(`{passId}: Bestätigung fehlgeschlagen: {tostring(err)}`, owner)
            return
        end
        if not confirmed then
            log(`{passId}: Kauf-Ereignis ohne Bestätigung durch Roblox, nichts eingetragen`, owner)
            return
        end
        if not deps.isPresent(owner) then
            return -- Spieler weg: nichts merken (kein Speicherleck), die Abfrage beim nächsten Laden zählt
        end
        apply(owner, passId)
    end

    local confirmer = {} :: Confirmer

    function confirmer.onPurchaseFinished(owner: any, gamePassId: any, wasPurchased: any): ConfirmStart
        if not deps.isPresent(owner) then
            return "absent"
        end
        local passId = Passes.idForGamePassId(gamePassId, data)
        if passId == nil then
            return "unknown"
        end
        local passes = deps.passesOf(owner)
        if passes ~= nil and Passes.owned({ passes = passes }, data)[passId] == true then
            return "owned"
        end
        if deps.trustEvent == true and wasPurchased == true then
            apply(owner, passId)
            return "trusted"
        end
        local rounds = if wasPurchased == true then fullRounds else 1
        local set = running[owner]
        local current = if set ~= nil then set[passId] else nil
        if current ~= nil then
            current.rounds = math.max(current.rounds, rounds)
            return "busy"
        end
        if set == nil then
            set = {}
            running[owner] = set
        end
        local entry = { rounds = rounds }
        set[passId] = entry
        local passIdNow: string = passId
        local spawned, err = pcall(deps.spawn, function()
            confirm(owner, gamePassId, passIdNow, entry)
        end)
        if not spawned then
            finish(owner, passIdNow)
            log(`{passIdNow}: Bestätigung konnte nicht gestartet werden: {tostring(err)}`, owner)
        end
        return "started"
    end

    function confirmer.isRunning(owner: any, passId: string): boolean
        local set = running[owner]
        return set ~= nil and set[passId] ~= nil
    end

    function confirmer.forget(owner: any)
        running[owner] = nil
    end

    return confirmer
end

-- Trägt Pässe ein, die in dieser Sitzung gekauft wurden, bevor das Profil geladen war (das
-- Kauf-Ereignis kam zu früh). `boughtSet` = { [passId] = true }. Gibt die neue Tabelle zurück oder
-- nil, wenn alle schon eingetragen sind. Unbekannte IDs zählen nicht.
function Passes.withBought(passes: any, boughtSet: { [string]: boolean }, data: any?): { [string]: boolean }?
    local result = Passes.owned({ passes = passes }, data)
    local changed = false
    for passId, value in boughtSet do
        if value == true and Passes.isKnown(passId, data) and result[passId] ~= true then
            result[passId] = true
            changed = true
        end
    end
    return if changed then result else nil
end

-- Studio-Hilfe: liest den Wert des Attributs "DebugPass". "big_tank" = anschalten, "-big_tank" =
-- ausschalten. Gibt (passId, an) zurück oder (nil, false, Grund).
function Passes.parseDebug(value: any, data: any?): (string?, boolean, string?)
    if type(value) ~= "string" or value == "" or #value > DEBUG_MAX_LENGTH then
        return nil, false, `erwartet Text wie "big_tank" oder "{DEBUG_OFF_PREFIX}big_tank"`
    end
    local prefix, passId = string.match(value, DEBUG_PATTERN)
    if passId == nil then
        return nil, false, `"{value}" hat nicht die Form "big_tank" oder "{DEBUG_OFF_PREFIX}big_tank"`
    end
    if not Passes.isKnown(passId, data) then
        return nil, false, `unbekannter Gamepass "{passId}"`
    end
    return passId, prefix ~= DEBUG_OFF_PREFIX, nil
end

return Passes
