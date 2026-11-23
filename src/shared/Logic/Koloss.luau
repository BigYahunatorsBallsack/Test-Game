--!strict
-- Server-Event "Der Koloss" (Paket 5.6): reine Logik ohne Roblox-API, getestet mit Lune
-- (tests/koloss.spec.luau). Der Service (Services/Koloss) hängt Uhr, Spieler, StateSync und
-- Workspace-Attribute daran.
--
-- Regeln:
--  * Das Fenster liegt in der Woche der Saison-Phase `Data/Koloss.window.phaseId`, ab `startDay`
--    (0 = Montag) 0 Uhr UTC für `days` Tage, das Ende ist ausschließend. Zeit ist immer die Unix-Zeit
--    des Servers (der Aufrufer übergibt sie). Eine kaputte Zeit ergibt "none", nie ein offenes Fenster.
--  * Fortschritt zählt nur Grabsekunden, die der Server meldet (`addSeconds`), nur bei offenem Fenster,
--    gedeckelt bei `targetSeconds`. Danach ist das Event fertig und zählt nichts mehr. Der Zustand
--    (`Event`) lebt nur im Speicher eines Servers; mit einer neuen Saison beginnt er bei 0.
--  * Der Beitrag je Spieler (`contributions[userId]`) wächst nur um den wirklich gezählten Anteil.
--  * Die Belohnung (`claim`) richtet sich nach dem eigenen Beitrag (höchste erreichte Stufe), ist fest
--    (Gems, Münz-Boost, Glücks-Boost) und wird je Spieler und Saison einmal vergeben: Merker
--    `profile.seasons[saisonId].koloss = true`, gebucht in einem Zug mit der Belohnung.
--  * Daten kommen als Argument (`data = { Koloss, Seasons, Economy }`), Vorgabe sind die echten Tabellen.

local Seasons = require("./Seasons")
local SeasonPass = require("./SeasonPass")
local Gems = require("./Gems")
local Perks = require("./Perks")

local Koloss = {}

Koloss.STATES = { "none", "upcoming", "open", "over" }
Koloss.REWARD_KINDS = { "gems", "coinBoost", "luck" }
Koloss.DEBUG_PROGRESS_PREFIX = "progress:"
Koloss.DEBUG_COMPLETE = "complete"
Koloss.DEBUG_RESET = "reset"
Koloss.DEBUG_MAX = 1000000
Koloss.NOTIFY_KIND = "kolossDone"

export type Data = { Koloss: any?, Seasons: any?, Economy: any? }

export type Event = {
    seasonId: string?,
    progress: number,
    completed: boolean,
    contributions: { [number]: number },
}

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function kolossOf(data: Data?): any
    if data ~= nil and data.Koloss ~= nil then
        return data.Koloss
    end
    return require("../Data/Koloss")
end

local function calendarOf(data: Data?): any
    if data ~= nil and data.Seasons ~= nil then
        return data.Seasons
    end
    return require("../Data/Seasons")
end

-- Ziel in Sekunden (endlich, größer 0). Wirft bei kaputten Daten (DataCheck prüft beim Start).
function Koloss.targetSeconds(data: Data?): number
    local target = kolossOf(data).targetSeconds
    if not isFinite(target) or target <= 0 then
        error("Koloss: targetSeconds fehlt")
    end
    return target
end

-- Index der Phase mit dieser ID (Woche 1 bis #phases) oder nil.
local function phaseIndex(calendar: any, phaseId: any): number?
    for index, phase in calendar.phases do
        if type(phase) == "table" and phase.id == phaseId then
            return index
        end
    end
    return nil
end

-- Fenster (Start, Ende in Unix-Sekunden) für eine Saison-Zeile oder nil bei kaputten Daten.
local function windowOf(season: any, calendar: any, data: Data?): (number?, number?)
    local config = kolossOf(data).window
    local start = Seasons.startOf(season)
    if start == nil or type(config) ~= "table" then
        return nil, nil
    end
    local index = phaseIndex(calendar, config.phaseId)
    if index == nil or not isFinite(config.startDay) or not isFinite(config.days) then
        return nil, nil
    end
    local from = start + (index - 1) * Seasons.WEEK_SECONDS + config.startDay * Seasons.SECONDS_PER_DAY
    return from, from + config.days * Seasons.SECONDS_PER_DAY
end

export type Window = {
    state: string, -- "none" (keine Saison), "upcoming", "open", "over"
    seasonId: string?,
    startsAt: number?,
    endsAt: number?,
    secondsLeft: number, -- bis zum Ende (nur "open")
    secondsToStart: number, -- bis zum Start (nur "upcoming")
}

local function none(): Window
    return { state = "none", seasonId = nil, startsAt = nil, endsAt = nil, secondsLeft = 0, secondsToStart = 0 }
end

-- Wo steht die Zeit im Fenster der laufenden Saison? Außerhalb einer Saison (und bei kaputter Zeit
-- oder kaputten Daten) "none".
function Koloss.window(unixNow: any, data: Data?): Window
    if not isFinite(unixNow) or unixNow < 0 then
        return none()
    end
    local calendar = calendarOf(data)
    local position = Seasons.at(unixNow, calendar)
    local season = position.active
    if season == nil then
        return none()
    end
    local from, to = windowOf(season, calendar, data)
    if from == nil or to == nil then
        return none()
    end
    local state = if unixNow < from then "upcoming" elseif unixNow < to then "open" else "over"
    return {
        state = state,
        seasonId = season.id,
        startsAt = from,
        endsAt = to,
        secondsLeft = if state == "open" then to - unixNow else 0,
        secondsToStart = if state == "upcoming" then from - unixNow else 0,
    }
end

function Koloss.newEvent(): Event
    return { seasonId = nil, progress = 0, completed = false, contributions = {} }
end

-- Setzt den Zustand zurück (neue Saison oder Studio-Hilfe).
function Koloss.reset(event: Event, seasonId: string?)
    event.seasonId = seasonId
    event.progress = 0
    event.completed = false
    table.clear(event.contributions)
end

export type Added = { gained: number, completed: boolean }

-- Bucht Grabsekunden eines Spielers. `completed` ist nur in dem Aufruf true, der 100 % erreicht.
-- Kaputte Eingaben (kein number, NaN, unendlich, 0, negativ, UserId keine ganze Zahl über 0), ein
-- geschlossenes Fenster und ein fertiges Event ändern nichts. Rechnet erst alles, schreibt dann.
function Koloss.addSeconds(event: Event, unixNow: any, userId: any, seconds: any, data: Data?): Added
    local nothing: Added = { gained = 0, completed = false }
    if not isFinite(seconds) or seconds <= 0 or not isFinite(userId) or userId <= 0 or userId ~= math.floor(userId) then
        return nothing
    end
    local window = Koloss.window(unixNow, data)
    if window.state ~= "open" or window.seasonId == nil then
        return nothing
    end
    if event.seasonId ~= window.seasonId then
        Koloss.reset(event, window.seasonId)
    end
    if event.completed then
        return nothing
    end
    local target = Koloss.targetSeconds(data)
    local gained = math.min(seconds, target - event.progress)
    if gained <= 0 then
        return nothing
    end
    local newProgress = event.progress + gained
    local done = newProgress >= target
    local newShare = (event.contributions[userId] or 0) + gained
    event.progress = if done then target else newProgress
    event.contributions[userId] = newShare
    event.completed = done
    return { gained = gained, completed = done }
end

-- Höchste erreichte Stufe zum Beitrag: (Stufe, Index) oder nil bei kaputter Eingabe.
function Koloss.tierOf(seconds: any, data: Data?): (any?, number?)
    local tiers = kolossOf(data).tiers
    if type(tiers) ~= "table" or not isFinite(seconds) or seconds < 0 then
        return nil, nil
    end
    local found: any = nil
    local foundIndex: number? = nil
    for index, tier in tiers do
        if seconds >= tier.minSeconds then
            found, foundIndex = tier, index
        else
            break
        end
    end
    return found, foundIndex
end

-- Hat der Spieler die Belohnung dieser Saison schon?
function Koloss.isClaimed(profile: any, seasonId: any): boolean
    local entry = SeasonPass.entryOf(profile, seasonId)
    return entry ~= nil and (entry :: any).koloss == true
end

export type ClaimContext = { data: Data?, boostNow: number? }

local function fail(reason: string, detail: string?): any
    return { ok = false, reason = reason, detail = detail }
end

-- Rechnet die Belohnung auf Kopien. Gibt entweder ein Fehlschlag-Ergebnis oder
-- `{ write = { gems?, boosts?, seasons }, response }` zurück.
local function prepareClaim(profile: any, seasonId: any, contribution: any, ctx: ClaimContext): any
    local data = ctx.data
    if type(profile) ~= "table" or type(profile.seasons) ~= "table" or type(seasonId) ~= "string" then
        return fail("error", "kein Profil oder keine Saison")
    end
    if Koloss.isClaimed(profile, seasonId) then
        return fail("claimed")
    end
    local tier = Koloss.tierOf(contribution, data)
    if tier == nil then
        return fail("error", "kein Beitrag")
    end
    local boostNow = ctx.boostNow
    if not isFinite(boostNow) then
        return fail("error", "keine Uhr")
    end
    local wallet = { gems = Gems.balance(profile, data) }
    local boosts: any = profile.boosts
    local changedGems = false
    local changedBoosts = false
    local rewards: { any } = {}
    for _, reward in tier.rewards do
        if reward.kind == "gems" then
            local added = Gems.grant(wallet, reward.amount, `koloss:{seasonId}:{tier.id}`, data)
            changedGems = true
            table.insert(rewards, { kind = "gems", amount = added, capped = if added < reward.amount then true else nil })
        elseif reward.kind == "coinBoost" or reward.kind == "luck" then
            local extend = if reward.kind == "coinBoost" then Perks.extendCoinBoost else Perks.extendLuckBoost
            local extended = extend(boosts, boostNow :: number, reward.seconds)
            if extended == nil then
                return fail("error", `Boost für Stufe {tier.id} ließ sich nicht verlängern`)
            end
            boosts = extended
            changedBoosts = true
            table.insert(rewards, { kind = reward.kind, seconds = reward.seconds })
        else
            -- Nie Kisten, nie Zufall: jede andere Art ist ein Datenfehler und bucht nichts.
            return fail("error", `unbekannte Art {tostring(reward.kind)} in Stufe {tier.id}`)
        end
    end
    local existing = SeasonPass.entryOf(profile, seasonId)
    local newEntry: any = if existing ~= nil then table.clone(existing) else SeasonPass.newEntry()
    newEntry.koloss = true
    local newSeasons = table.clone(profile.seasons)
    newSeasons[seasonId] = newEntry
    return {
        write = {
            gems = if changedGems then wallet.gems else nil,
            boosts = if changedBoosts then boosts else nil,
            seasons = newSeasons,
        },
        response = { ok = true, seasonId = seasonId, tierId = tier.id, tierName = tier.name, rewards = rewards },
    }
end

-- Führt `prepareClaim` in einer eigenen Koroutine aus. Wartet sie (yield), wird sie geschlossen.
local function prepareWithoutYield(profile: any, seasonId: any, contribution: any, ctx: ClaimContext): (boolean, any)
    local routine = coroutine.create(prepareClaim)
    local resumed, result = coroutine.resume(routine, profile, seasonId, contribution, ctx)
    if coroutine.status(routine) ~= "dead" then
        coroutine.close(routine)
        return false, "Koloss: die Belohnung hat gewartet (yield) und wurde abgebrochen"
    end
    return resumed, result
end

-- Vergibt die Belohnung der Stufe zum Beitrag, einmal je Spieler und Saison. Ergebnis
-- `{ ok = true, seasonId, tierId, tierName, rewards }` mit rewards `{ kind = "gems", amount, capped? }`
-- oder `{ kind = "coinBoost" | "luck", seconds }`; sonst `{ ok = false, reason, detail? }` mit reason
-- "claimed" oder "error". Schreibt in einem Zug, ein Fehler oder Warten bucht nichts.
function Koloss.claim(profile: any, seasonId: any, contribution: any, ctx: ClaimContext?): any
    local context: ClaimContext = if type(ctx) == "table" then ctx else { data = nil, boostNow = nil }
    local ok, prepared = prepareWithoutYield(profile, seasonId, contribution, context)
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
    profile.seasons = write.seasons
    return prepared.response
end

-- Anzeigeform für den StateSync (`koloss`): Zustand, Fortschritt, Ziel, eigener Beitrag, Restzeiten,
-- erreichte Stufe und ob die Belohnung schon da ist. Nur Texte, Zahlen und Wahrheitswerte, nie Daten
-- anderer Spieler. nil ohne Saison (Zustand "none").
function Koloss.view(event: Event, profile: any, userId: any, unixNow: any, data: Data?): { [string]: any }?
    local window = Koloss.window(unixNow, data)
    if window.state == "none" then
        return nil
    end
    local sameSeason = event.seasonId == window.seasonId
    local progress = if sameSeason then event.progress else 0
    local you = if sameSeason and type(userId) == "number" then (event.contributions[userId] or 0) else 0
    local tier = Koloss.tierOf(you, data)
    return {
        state = window.state,
        seasonId = window.seasonId,
        progress = progress,
        target = Koloss.targetSeconds(data),
        completed = sameSeason and event.completed,
        you = you,
        tierId = if tier ~= nil then tier.id else nil,
        claimed = Koloss.isClaimed(profile, window.seasonId),
        secondsLeft = window.secondsLeft,
        secondsToStart = window.secondsToStart,
    }
end

-- Studio-Hilfe: Zeit eine Stunde nach dem Start des Fensters der laufenden, sonst der nächsten, sonst
-- der ersten Saison (gemessen an der echten Zeit `unixNow`). nil ohne Saison mit gültigem Datum.
function Koloss.debugTime(unixNow: number, data: Data?): number?
    local calendar = calendarOf(data)
    local position = Seasons.at(unixNow, calendar)
    local target: any = position.active or position.nextSeason
    if target == nil then
        local earliest = math.huge
        for _, season in calendar.list do
            local start = Seasons.startOf(season)
            if start ~= nil and start < earliest then
                target, earliest = season, start
            end
        end
    end
    local from = windowOf(target, calendar, data)
    if from == nil then
        return nil
    end
    return from + 3600
end

-- Studio-Hilfe DebugKoloss: "progress:N" (N ganz von 0 bis DEBUG_MAX), "complete" oder "reset".
-- Gibt (Befehl, Zahl, Problem) zurück: ("progress", N), ("complete", nil), ("reset", nil) oder
-- (nil, nil, Text).
function Koloss.parseDebug(value: any): (string?, number?, string?)
    if type(value) ~= "string" then
        return nil, nil, "DebugKoloss erwartet Text"
    end
    if value == Koloss.DEBUG_COMPLETE then
        return "complete", nil, nil
    end
    if value == Koloss.DEBUG_RESET then
        return "reset", nil, nil
    end
    local text = string.match(value, "^" .. Koloss.DEBUG_PROGRESS_PREFIX .. "(%d+)$")
    if text ~= nil then
        local number = tonumber(text) :: number
        if number <= Koloss.DEBUG_MAX then
            return "progress", number, nil
        end
    end
    return nil, nil, `DebugKoloss erwartet "progress:N" (N bis {Koloss.DEBUG_MAX}), "complete" oder "reset"`
end

return Koloss
