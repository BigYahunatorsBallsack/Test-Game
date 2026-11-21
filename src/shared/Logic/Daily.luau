--!strict
-- Daily Reward (Paket 5.1). Rein, ohne Roblox-API, Lune-Tests in tests/daily.spec.luau. Der
-- Daily-Service (Services/Daily) schließt die Remote `ClaimDaily`, die Server-Uhr (os.time), die
-- Policy (Crates.policyState), den Zufall und den StateSync an. Der Client sendet nur die Absicht
-- "abholen", ohne Argumente; Tag, Belohnung und Zeit bestimmt der Server.
--
-- Regeln (Werte in Economy.daily):
--  * Ein Tag ist ein UTC-Kalendertag: `dayOf(t) = floor(t / 86400)` für die Unix-Zeit t des Servers.
--    Der Wechsel liegt genau auf 0 Uhr UTC (86399 ist noch Tag 0, 86400 schon Tag 1).
--  * Gespeichert wird `profile.daily = { streak, lastDay }`: streak = abgeholte Tage der laufenden
--    Serie (0 bis Länge der Serie), lastDay = dayOf der letzten Abholung (0 = nie).
--  * Länge der Serie = #days + 1 (Tag 1 bis 6 aus `days`, dazu `day7`), heute 7.
--  * Abholbar, wenn gestartet und lastDay < heute. Wer gestern abgeholt hat (lastDay = heute - 1),
--    bekommt den nächsten Serientag (streak + 1); nach dem letzten Tag kommt wieder Tag 1. Ein
--    verpasster Tag (lastDay < heute - 1) setzt die Serie auf Tag 1. Zweimal am selben Tag geht nicht
--    ("alreadyClaimed"). Ein gespeicherter lastDay in der Zukunft (>= heute, zum Beispiel von einem
--    Server mit vorgehender Uhr) zählt wie "heute abgeholt": nie zwei Belohnungen am selben Tag.
--    Kaputte Werte im Profil: streak ganz von 0 bis zur Länge der Serie (sonst 0 bzw. gekappt),
--    lastDay ganz ab 0 (sonst 0).
--  * Gestartet: Knoten `Economy.daily.startNodeId` (die Schaufel) gekauft oder schon ein Sandsturm
--    (prestiges >= 1; der Sturm setzt die Knoten zurück, die Serie läuft weiter).
--  * Belohnungen (Economy.daily.days[1..6] und day7):
--      "coinBoost"  Münz-Boost um `seconds` verlängern (Perks.extendCoinBoost, boosts.coinsUntil)
--      "luck"       Glücks-Boost um `seconds` verlängern (Perks.extendLuckBoost, boosts.luckUntil)
--      "gems"       `amount` Gems gutschreiben (Gems.grant, gekappt bei maxGems; die Abholung gilt auch
--                   dann, die Antwort nennt die tatsächlich gutgeschriebene Menge)
--      "crate"      Tag 7: Policy "allowed" öffnet die Kiste `crateId` gratis (CrateOpen.openFree, eine
--                   Öffnung, zählt für die Pity). Jeder andere Zustand ("restricted", "unknown", auch
--                   "none" und fehlend) gibt ein Exemplar von `day7FallbackItemId` ins Inventar (fester
--                   Gegenstand, kein Zufall). "pending" (die erste Abfrage läuft noch): Grund
--                   "policyPending", nichts gebucht, der Service versucht es nach kurzer Wartezeit neu.
--
-- `claim(profile, jetzt, ctx)`: Die erste nicht erfüllte Bedingung ist der Grund: "noProfile",
-- "error" (kaputte Uhr oder Daten), "notStarted", "alreadyClaimed", "policyPending" (nur Tag 7).
-- Prüfen und Rechnen laufen in einer eigenen Koroutine auf Arbeitskopien (Gems, Boosts, Pity,
-- Inventar, Serie), wie bei CrateOpen und DirectShop. Wirft oder wartet sie (yield), wird sie
-- geschlossen und nichts geschrieben: Grund "error", Profil und Serie unverändert. Danach werden im
-- selben Thread nur fertige Werte zugewiesen (daily und je nach Belohnung gems, boosts, pity,
-- inventory): Belohnung und Serie zusammen oder gar nicht.
-- Ergebnis: `{ ok = true, day, reward, crate?, daily }` oder `{ ok = false, reason, detail? }`
-- (`detail` nur bei "error", für das Server-Protokoll). `reward`:
--   { kind = "coinBoost", seconds }               { kind = "luck", seconds }
--   { kind = "gems", amount, capped? }            amount = tatsächlich gutgeschrieben, capped = true bei maxGems
--   { kind = "crate", crateId, itemId }           itemId = gewonnenes Item; `crate` = Ergebnis von openFree
--   { kind = "fixedItem", itemId, copies }        Ersatzgegenstand, copies = Exemplare danach
--
-- `state(profile, jetzt)` für den StateSync: `{ started, day, canClaim, secondsLeft, streak }`.
--   day         Serientag der nächsten Abholung (jetzt, wenn canClaim, sonst nach secondsLeft)
--   canClaim    jetzt abholbar (gestartet, heute noch nicht abgeholt)
--   secondsLeft 0, wenn abholbar oder nicht gestartet; sonst Sekunden bis 0 Uhr UTC des nächsten
--               abholbaren Tages (aufgerundet)
--   streak      abgeholte Tage der laufenden Serie, die noch zählen (0 nach einem verpassten Tag)
--
-- Studio-Hilfe (`parseDebug`, `withDebug`): "reset" (Serie leer, nie abgeholt), "yesterday" (gestern
-- abgeholt, Serie bleibt), "day:N" (Serie N, gestern abgeholt; die nächste Abholung ist Tag N + 1).
--
-- `data` bzw. `ctx.data` ist für Tests überschreibbar ({ Economy, Crates, CrateItems, Rarities }).

local CrateOpen = require("./CrateOpen")
local Equipment = require("./Equipment")
local Gems = require("./Gems")
local Perks = require("./Perks")
local CrateItemsData = require("../Data/CrateItems")
local EconomyData = require("../Data/Economy")

export type Reason = "noProfile" | "notStarted" | "alreadyClaimed" | "policyPending" | "error"

export type Context = {
    policyState: string?, -- Crates.policyState: "pending" | "allowed" | "restricted" | "unknown" | "none"
    random: (() -> number)?, -- Zufall in [0, 1) für die Kiste an Tag 7 (nur bei "allowed")
    inSeason: boolean?, -- an CrateOpen weitergereicht (Tag 7 ist die Eisenkiste, keine Event-Kiste)
    data: any?, -- Tests: { Economy, Crates, CrateItems, Rarities }
}

export type State = {
    started: boolean,
    day: number,
    canClaim: boolean,
    secondsLeft: number,
    streak: number,
}

local Daily = {}

-- Länge eines Tages in Sekunden (UTC-Kalendertag, Unix-Zeit kennt keine Schaltsekunden).
Daily.SECONDS_PER_DAY = 86400
-- Policy-Zustand, bei dem Tag 7 wartet (erste Abfrage läuft), und der einzige, der die Kiste öffnet.
Daily.POLICY_PENDING = "pending"
Daily.POLICY_ALLOWED = "allowed"
-- Studio-Hilfe: Befehle des Attributs DebugDaily.
Daily.DEBUG_RESET = "reset"
Daily.DEBUG_YESTERDAY = "yesterday"
Daily.DEBUG_DAY_PREFIX = "day:"

-- Herkunftstext der Gem-Gutschrift (Gems.grant verlangt einen), dahinter der Serientag.
local GEMS_SOURCE_PREFIX = "daily:day"
local DEBUG_MAX_LENGTH = 16

local function economyOf(data: any?): any
    return if data ~= nil and data.Economy ~= nil then data.Economy else EconomyData
end

local function configOf(data: any?): any
    return economyOf(data).daily
end

local function itemsOf(data: any?): any
    return if data ~= nil and data.CrateItems ~= nil then data.CrateItems else CrateItemsData
end

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isWholePositive(value: any): boolean
    return isFinite(value) and value > 0 and value % 1 == 0
end

local function fail(reason: Reason, detail: string?): any
    return { ok = false, reason = reason, detail = detail }
end

-- UTC-Kalendertag der Unix-Zeit: floor(t / 86400). nil bei kaputter Uhr (kein number, NaN,
-- unendlich, negativ).
function Daily.dayOf(unixTime: number): number?
    if not isFinite(unixTime) or unixTime < 0 then
        return nil
    end
    return math.floor(unixTime / Daily.SECONDS_PER_DAY)
end

-- Länge der Serie (#days + 1). Wirft bei kaputten Daten (DataCheck verhindert das beim Start).
local function cycleOf(config: any): number
    if type(config) ~= "table" or type(config.days) ~= "table" or #config.days < 1 then
        error("Daily: Economy.daily.days fehlt")
    end
    return #config.days + 1
end

-- Gespeicherte Serie, repariert: streak ganz von 0 bis `cycle`, lastDay ganz ab 0.
local function readDaily(profile: any, cycle: number): (number, number)
    local daily = if type(profile.daily) == "table" then profile.daily else nil
    local streak = if daily ~= nil then daily.streak else nil
    local lastDay = if daily ~= nil then daily.lastDay else nil
    local cleanStreak = if isFinite(streak) then math.clamp(math.floor(streak), 0, cycle) else 0
    local cleanLast = if isFinite(lastDay) and lastDay >= 0 then math.floor(lastDay) else 0
    return cleanStreak, cleanLast
end

-- Gestartet: Startknoten gekauft oder schon ein Sandsturm.
local function isStarted(profile: any, config: any): boolean
    local prestiges = profile.prestiges
    if isFinite(prestiges) and prestiges >= 1 then
        return true
    end
    local nodeId = if type(config) == "table" then config.startNodeId else nil
    return type(nodeId) == "string" and type(profile.nodes) == "table" and profile.nodes[nodeId] == true
end

-- Serientag, der auf eine Abholung mit `streak` folgt (nach dem letzten Tag wieder Tag 1).
local function followingDay(streak: number, cycle: number): number
    if streak >= 1 and streak < cycle then
        return streak + 1
    end
    return 1
end

-- Belohnung eines Serientags aus den Daten.
local function rewardOf(config: any, day: number, cycle: number): any
    if day == cycle then
        return config.day7
    end
    return config.days[day]
end

-- Ist die Serie gestartet? (Für Anzeige und Prüfung.)
function Daily.isStarted(profile: any, data: any?): boolean
    return type(profile) == "table" and isStarted(profile, configOf(data))
end

-- Zustand für den StateSync (siehe Kopf der Datei). Ändert nichts.
function Daily.state(profile: any, unixNow: number, data: any?): State
    local result: State = { started = false, day = 1, canClaim = false, secondsLeft = 0, streak = 0 }
    if type(profile) ~= "table" then
        return result
    end
    local config = configOf(data)
    local okCycle, cycle = pcall(cycleOf, config)
    if not okCycle then
        return result
    end
    result.started = isStarted(profile, config)
    local today = Daily.dayOf(unixNow)
    if today == nil then
        return result
    end
    local streak, lastDay = readDaily(profile, cycle)
    if lastDay >= today then
        -- Heute (oder laut Speicher später) schon abgeholt: der nächste Tag kommt nach lastDay.
        result.streak = streak
        result.day = followingDay(streak, cycle)
        result.secondsLeft = math.max(math.ceil((lastDay + 1) * Daily.SECONDS_PER_DAY - unixNow), 0)
    elseif lastDay == today - 1 then
        result.streak = streak
        result.day = followingDay(streak, cycle)
        result.canClaim = result.started
    else
        result.streak = 0
        result.day = 1
        result.canClaim = result.started
    end
    return result
end

-- Ein Exemplar des Ersatzgegenstands auf einer Kopie des Inventars. Gibt (neues Inventar, Item, Exemplare).
local function addFallbackItem(profile: any, config: any, data: any?): (any, any, number)
    local itemId = config.day7FallbackItemId
    local item = if type(itemId) == "string" then itemsOf(data).byId[itemId] else nil
    if item == nil then
        error(`Daily: Ersatzgegenstand "{tostring(itemId)}" steht nicht in CrateItems`)
    end
    local field = Equipment.INVENTORY_FIELDS[item.kind]
    if field == nil then
        error(`Daily: unbekannte Item-Art {tostring(item.kind)} bei "{item.id}"`)
    end
    local inventory = if type(profile.inventory) == "table" then profile.inventory else {}
    local newInventory = table.clone(inventory)
    local bucket = if type(inventory[field]) == "table" then table.clone(inventory[field]) else {}
    local copies = Equipment.copiesOf(profile, item) + 1
    bucket[item.id] = copies
    newInventory[field] = bucket
    return newInventory, item, copies
end

-- Prüft und rechnet die Abholung auf Arbeitskopien. Schreibt nichts ins Profil. Gibt entweder ein
-- Fehlschlag-Ergebnis zurück oder `{ write = ..., response = ... }`.
local function prepare(profile: any, unixNow: any, ctx: any): any
    local data = ctx.data
    if type(profile) ~= "table" then
        return fail("noProfile")
    end
    local today = Daily.dayOf(unixNow)
    if today == nil then
        error(`Daily: ungültige Uhr {tostring(unixNow)}`)
    end
    local config = configOf(data)
    local cycle = cycleOf(config)
    if not isStarted(profile, config) then
        return fail("notStarted")
    end
    local streak, lastDay = readDaily(profile, cycle)
    if lastDay >= today then
        return fail("alreadyClaimed")
    end
    local day = if lastDay == today - 1 then followingDay(streak, cycle) else 1
    local reward = rewardOf(config, day, cycle)
    if type(reward) ~= "table" then
        error(`Daily: Belohnung für Tag {day} fehlt`)
    end

    local newDaily = { streak = day, lastDay = today }
    local write: { [string]: any } = { daily = newDaily }
    local response: { [string]: any } = { ok = true, day = day, daily = table.clone(newDaily) }
    local kind = reward.kind
    if kind == "crate" then
        local policyState = ctx.policyState
        if policyState == Daily.POLICY_PENDING then
            return fail("policyPending")
        end
        if policyState == Daily.POLICY_ALLOWED then
            -- Gratis-Öffnung auf einer flachen Kopie: openFree weist pity und inventory als neue Tabellen
            -- zu und ändert die alten nie, das echte Profil bleibt also unberührt.
            local work = table.clone(profile)
            local opened = CrateOpen.openFree(work, reward.crateId, {
                random = ctx.random :: any,
                restricted = policyState ~= Daily.POLICY_ALLOWED,
                inSeason = ctx.inSeason,
                data = data,
            })
            if opened.ok ~= true then
                error(`Daily: Kiste "{tostring(reward.crateId)}" nicht geöffnet ({tostring(opened.reason)}: {tostring(opened.detail)})`)
            end
            write.pity = work.pity
            write.inventory = work.inventory
            response.reward = { kind = "crate", crateId = opened.crateId, itemId = opened.results[1].itemId }
            response.crate = opened
        else
            local newInventory, item, copies = addFallbackItem(profile, config, data)
            write.inventory = newInventory
            response.reward = { kind = "fixedItem", itemId = item.id, copies = copies }
        end
    elseif kind == "gems" then
        local amount = reward.amount
        if not isWholePositive(amount) then
            error(`Daily: ungültige Gems {tostring(amount)} für Tag {day}`)
        end
        local wallet = { gems = Gems.balance(profile, data) }
        local added = Gems.grant(wallet, amount, GEMS_SOURCE_PREFIX .. tostring(day), data)
        if added > 0 then
            write.gems = wallet.gems
        end
        response.reward = { kind = "gems", amount = added, capped = if added < amount then true else nil }
    elseif kind == "coinBoost" or kind == "luck" then
        local seconds = reward.seconds
        if not isWholePositive(seconds) then
            error(`Daily: ungültige Dauer {tostring(seconds)} für Tag {day}`)
        end
        local extend = if kind == "coinBoost" then Perks.extendCoinBoost else Perks.extendLuckBoost
        local boosts = extend(profile.boosts, unixNow, seconds)
        if boosts == nil then
            error(`Daily: Boost für Tag {day} ließ sich nicht verlängern`)
        end
        write.boosts = boosts
        response.reward = { kind = kind, seconds = seconds }
    else
        error(`Daily: unbekannte Art {tostring(kind)} für Tag {day}`)
    end
    return { write = write, response = response }
end

-- Führt `prepare` in einer eigenen Koroutine aus. Wartet sie (yield), wird sie geschlossen.
local function prepareWithoutYield(profile: any, unixNow: any, ctx: any): (boolean, any)
    local routine = coroutine.create(prepare)
    local resumed, result = coroutine.resume(routine, profile, unixNow, ctx)
    if coroutine.status(routine) ~= "dead" then
        coroutine.close(routine)
        return false, "Daily: die Abholung hat gewartet (yield) und wurde abgebrochen"
    end
    return resumed, result
end

-- Holt die Belohnung des Tages ab. Siehe Kopf der Datei.
function Daily.claim(profile: any, unixNow: number, ctx: Context?): any
    local context = if type(ctx) == "table" then ctx else {}
    local ok, prepared = prepareWithoutYield(profile, unixNow, context)
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
    if write.pity ~= nil then
        profile.pity = write.pity
    end
    if write.inventory ~= nil then
        profile.inventory = write.inventory
    end
    profile.daily = write.daily
    return prepared.response
end

-- Studio-Hilfe: liest den Wert des Attributs DebugDaily. Gibt (Befehl, Serie, Problem) zurück:
-- ("reset", nil), ("yesterday", nil), ("day", N) mit N ganz von 0 bis zur Länge der Serie, sonst
-- (nil, nil, Text).
function Daily.parseDebug(value: any, data: any?): (string?, number?, string?)
    local usage = `erwartet "{Daily.DEBUG_RESET}", "{Daily.DEBUG_YESTERDAY}" oder "{Daily.DEBUG_DAY_PREFIX}6"`
    if type(value) ~= "string" or value == "" or #value > DEBUG_MAX_LENGTH then
        return nil, nil, usage
    end
    if value == Daily.DEBUG_RESET or value == Daily.DEBUG_YESTERDAY then
        return value, nil, nil
    end
    local digits = string.match(value, "^" .. Daily.DEBUG_DAY_PREFIX .. "(%d+)$")
    local number = if digits ~= nil then tonumber(digits) else nil
    if number == nil then
        return nil, nil, `"{value}": {usage}`
    end
    local okCycle, cycle = pcall(cycleOf, configOf(data))
    if not okCycle or number > cycle then
        return nil, nil, `"{value}": Serie höchstens {if okCycle then cycle else "?"}`
    end
    return "day", number, nil
end

-- Studio-Hilfe: neue daily-Tabelle für den Befehl. Ändert `profile` nicht.
--   "reset"      { streak = 0, lastDay = 0 }: nie abgeholt, die nächste Abholung ist Tag 1
--   "yesterday"  Serie bleibt, lastDay = gestern: der nächste Serientag ist sofort abholbar
--   "day"        Serie = streak, lastDay = gestern: die nächste Abholung ist Tag streak + 1
function Daily.withDebug(profile: any, action: string, streak: number?, unixNow: number, data: any?): { streak: number, lastDay: number }
    local today = Daily.dayOf(unixNow) or 0
    local yesterday = math.max(today - 1, 0)
    if action == Daily.DEBUG_RESET then
        return { streak = 0, lastDay = 0 }
    end
    local okCycle, cycle = pcall(cycleOf, configOf(data))
    local maxStreak = if okCycle then cycle else 0
    if action == "day" then
        local value = if isFinite(streak) then math.clamp(math.floor(streak :: number), 0, maxStreak) else 0
        return { streak = value, lastDay = yesterday }
    end
    local current = if type(profile) == "table" then readDaily(profile, maxStreak) else 0
    return { streak = current, lastDay = yesterday }
end

return Daily
