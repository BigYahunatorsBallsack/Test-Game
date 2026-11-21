--!strict
-- Wirkungen der Gamepasses und des Münz-Boosts (Paket 4.4). Rein, ohne Roblox-API, Lune-Tests in
-- tests/perks.spec.luau.
--
-- Wirkungen (Data/Products, Feld `perk` je Gamepass; der Code kennt nie feste Produkt-IDs):
--   "bigTank"     Tankgröße mal Economy.bigTankMultiplier (über Collecting.Options.capacityMultiplier)
--   "doubleCoins" Münzen aus Verkäufen mal Economy.doubleCoinsMultiplier (Options.coinMultiplier)
--   "autoDig"     sammelt ohne Taste, solange die Einstellung `profile.settings.autoDig` an ist
-- Münz-Boost (Verbrauchsprodukt "coin_boost"): aktiv, solange die Server-Uhr (Unix) vor
-- `profile.boosts.coinsUntil` liegt; dann Münzen mal Economy.coinBoost.multiplier. Die Zeit läuft in
-- echter Zeit weiter, auch offline (so entschieden).
--
-- Münz-Faktor = (2x Münzen ? doubleCoinsMultiplier : 1) x (Boost aktiv ? coinBoost.multiplier : 1),
-- also multiplikativ (mit beidem 4-fach, so entschieden).
--
-- Glücks-Boost (Daily Reward Tag 5, Paket 5.1): aktiv, solange die Server-Uhr (Unix, os.time) vor
-- `profile.boosts.luckUntil` liegt; dann Fundchance aus dem Sand mal Economy.luckBoost.multiplier
-- (Logic/FindRoll, eigener Faktor neben dem Glück-Ast). Er ändert nie die Verteilung der Seltenheiten
-- und nie Kisten. Verlängern wie beim Münz-Boost: ab der alten Endzeit oder ab jetzt.
--
-- `options(profile, jetzt)` liefert die Collecting.Options für alle Rechnungen von Sammeln, Tank,
-- Verkauf und Sandsturm-Vorschau. Ohne Pass und Boost sind beide Faktoren genau 1, alle Rechnungen
-- bleiben dann wie vor Paket 4.4.
--
-- Auto-Dig im Takt des Sand-Service: `collectTick` rechnet je Takt das Sammeln ab, `autoDigStep`
-- entscheidet darin, ob gesammelt wird (Halten starten oder die Frist erneuern), ob nach dem
-- Abschalten gestoppt wird und ob genau jetzt die Meldung "Tank voll" fällig ist (einmal je Füllung,
-- kein Spam pro Takt). Der Sand-Service ruft collectTick auf und schickt nur noch Meldung und Zustand.
--
-- Der optionale Parameter `data` ist für Tests: { Products, Economy }.

local EconomyData = require("../Data/Economy")
local Passes = require("./Passes")
local Collecting = require("./Collecting")

export type Perk = "doubleCoins" | "autoDig" | "bigTank"

export type Options = Collecting.Options

export type AutoDigInput = {
    active: boolean, -- Pass "autoDig" und Einstellung an (Perks.autoDigActive)
    wasActive: boolean, -- war im letzten Takt aktiv
    canCollect: boolean, -- lebender Charakter, nicht am Händlerstand
    full: boolean, -- kein ganzes Korn passt mehr in den Tank
    fullNoticed: boolean, -- "Tank voll" ist für diese Füllung schon gemeldet
}

export type AutoDigDecision = {
    hold: boolean, -- jetzt Halten starten oder die Frist erneuern (Collecting.setHolding true)
    stop: boolean, -- Auto-Dig wurde gerade abgeschaltet: Halten beenden (Collecting.setHolding false)
    notifyFull: boolean, -- genau jetzt "tankFull" melden
    fullNoticed: boolean, -- Merker für den nächsten Takt
}

-- Merker je Spieler für Auto-Dig (nur im Speicher des Servers). nil = Auto-Dig war nicht aktiv.
export type AutoDigMemory = { wasActive: boolean, fullNoticed: boolean }

-- Ergebnis eines Takts (collectTick).
export type TickResult = {
    added: number, -- ganze Körner, die in diesem Takt in den Tank kamen
    changed: boolean, -- Sand dazu oder Sammeln gestartet/gestoppt: Zustand senden
    notifyFull: boolean, -- genau jetzt "tankFull" melden (höchstens einmal je Takt)
    memory: AutoDigMemory?, -- neuer Merker für den nächsten Takt
}

-- Antwort eines Kauf-Handlers (Form wie Purchases.Prepared, ohne require auf Purchases).
type Prepared = {
    changes: { [string]: any },
    gems: number,
    announce: ((profile: any) -> (string, { [string]: any }))?,
}

local Perks = {}

-- Alle Wirkungen, die der Code kennt. DataCheck verlangt jede genau einmal bei einem Gamepass.
Perks.PERK_IDS = { "doubleCoins", "autoDig", "bigTank" } :: { Perk }
-- Produkt-ID des Münz-Boosts in Data/Products (Developer Product, Verbrauchsprodukt).
Perks.COIN_BOOST_PRODUCT_ID = "coin_boost"
-- Meldung an den Client nach dem bestätigten Speichern eines Münz-Boost-Kaufs.
Perks.BOOST_BOUGHT_KIND = "boostBought"
-- Standard der Einstellung "Auto-Dig an" (neues Profil, Migration, Reparatur in sanitize).
Perks.AUTO_DIG_DEFAULT = true

local function economyOf(data: any?): any
    return if data ~= nil and data.Economy ~= nil then data.Economy else EconomyData
end

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Faktor aus den Daten, kaputt oder unter 1 zählt als 1 (ein Pass macht nie etwas schlechter).
local function factor(value: any): number
    if isFinite(value) and value >= 1 then
        return value
    end
    return 1
end

-- Felder in `profile.boosts` (Unix-Endzeiten).
local COINS_UNTIL = "coinsUntil"
local LUCK_UNTIL = "luckUntil"

-- Gültige Endzeit eines Boosts (endlich, ab 0), sonst nil. Kaputte Werte zählen als abgelaufen.
local function validUntil(boosts: any, field: string): number?
    local value = if type(boosts) == "table" then boosts[field] else nil
    if isFinite(value) and value >= 0 then
        return value
    end
    return nil
end

-- Besitzt der Spieler einen Gamepass mit dieser Wirkung? Nur bekannte Pässe mit Wert true zählen.
function Perks.owns(profile: any, perk: Perk, data: any?): boolean
    local owned = Passes.owned(profile, data)
    for _, pass in Passes.list(data) do
        if pass.perk == perk and owned[pass.id] == true then
            return true
        end
    end
    return false
end

-- Läuft der Boost mit Endzeit `boosts[field]` zur Unix-Zeit `unixNow`?
local function boostActive(profile: any, field: string, unixNow: number): boolean
    local untilTime = validUntil(if type(profile) == "table" then profile.boosts else nil, field)
    return untilTime ~= nil and isFinite(unixNow) and unixNow < untilTime
end

-- Restsekunden des Boosts (ab 0).
local function boostSeconds(profile: any, field: string, unixNow: number): number
    local untilTime = validUntil(if type(profile) == "table" then profile.boosts else nil, field)
    if untilTime == nil or not isFinite(unixNow) then
        return 0
    end
    return math.max(untilTime - unixNow, 0)
end

-- Läuft der Münz-Boost zur Unix-Zeit `unixNow`?
function Perks.coinBoostActive(profile: any, unixNow: number): boolean
    return boostActive(profile, COINS_UNTIL, unixNow)
end

-- Restsekunden des Münz-Boosts (ab 0) für die Anzeige.
function Perks.coinBoostSeconds(profile: any, unixNow: number): number
    return boostSeconds(profile, COINS_UNTIL, unixNow)
end

-- Läuft der Glücks-Boost zur Unix-Zeit `unixNow`? (Paket 5.1)
function Perks.luckBoostActive(profile: any, unixNow: number): boolean
    return boostActive(profile, LUCK_UNTIL, unixNow)
end

-- Restsekunden des Glücks-Boosts (ab 0) für die Anzeige (StateSync `luckBoostSeconds`).
function Perks.luckBoostSeconds(profile: any, unixNow: number): number
    return boostSeconds(profile, LUCK_UNTIL, unixNow)
end

-- Faktor des Glücks-Boosts auf die Fundchance aus dem Sand: Economy.luckBoost.multiplier, solange er
-- läuft, sonst 1. Kaputt oder unter 1 in den Daten: 1. Logic/FindRoll multipliziert ihn als eigenen
-- Faktor; Kisten lesen ihn nie.
function Perks.luckBoostMultiplier(profile: any, unixNow: number, data: any?): number
    if not Perks.luckBoostActive(profile, unixNow) then
        return 1
    end
    local cfg = economyOf(data).luckBoost
    return factor(if type(cfg) == "table" then cfg.multiplier else nil)
end

-- Faktor auf alle Münzen aus Verkäufen.
function Perks.coinMultiplier(profile: any, unixNow: number, data: any?): number
    local economy = economyOf(data)
    local result = 1
    if Perks.owns(profile, "doubleCoins", data) then
        result *= factor(economy.doubleCoinsMultiplier)
    end
    if Perks.coinBoostActive(profile, unixNow) then
        result *= factor(if type(economy.coinBoost) == "table" then economy.coinBoost.multiplier else nil)
    end
    return result
end

-- Faktor auf die Tankgröße.
function Perks.capacityMultiplier(profile: any, data: any?): number
    if Perks.owns(profile, "bigTank", data) then
        return factor(economyOf(data).bigTankMultiplier)
    end
    return 1
end

-- Options für Collecting und Sandstorm (Sand-Service: Sand.optionsFor). Ohne Pass und Boost: 1 und 1.
function Perks.options(profile: any, unixNow: number, data: any?): Options
    return {
        capacityMultiplier = Perks.capacityMultiplier(profile, data),
        coinMultiplier = Perks.coinMultiplier(profile, unixNow, data),
    }
end

-- Neue boosts-Tabelle, in der `boosts[field]` = max(jetzt, gültige Endzeit) + seconds ist.
local function extendBoost(boosts: any, field: string, unixNow: number, seconds: number): { [string]: any }?
    if not isFinite(unixNow) or unixNow < 0 or not isFinite(seconds) or seconds <= 0 then
        return nil
    end
    local result: { [string]: any } = if type(boosts) == "table" then table.clone(boosts) else {}
    local current = validUntil(boosts, field)
    local start = if current ~= nil then math.max(current, unixNow) else unixNow
    local untilTime = start + seconds
    if not isFinite(untilTime) then
        return nil
    end
    result[field] = untilTime
    return result
end

-- Neue boosts-Tabelle mit verlängertem Münz-Boost: coinsUntil = max(jetzt, gültige Endzeit) + seconds.
-- Abgelaufen oder kaputt: ab jetzt. Andere Felder der Tabelle bleiben. Keine Obergrenze für die
-- Stapelzeit (bezahlte Belege werden nie abgelehnt). nil nur bei kaputtem `unixNow` oder `seconds`
-- (dann bucht der Kauf nicht, NotProcessedYet).
function Perks.extendCoinBoost(boosts: any, unixNow: number, seconds: number): { [string]: any }?
    return extendBoost(boosts, COINS_UNTIL, unixNow, seconds)
end

-- Wie extendCoinBoost, für den Glücks-Boost (luckUntil, Daily Reward Tag 5, Paket 5.1). Andere Felder
-- (auch coinsUntil) bleiben, die alte Tabelle bleibt unverändert.
function Perks.extendLuckBoost(boosts: any, unixNow: number, seconds: number): { [string]: any }?
    return extendBoost(boosts, LUCK_UNTIL, unixNow, seconds)
end

-- Einstellung "Auto-Dig an" (fehlt oder kaputt: Standard).
function Perks.autoDigSetting(profile: any): boolean
    local settings = if type(profile) == "table" then profile.settings else nil
    local value = if type(settings) == "table" then settings.autoDig else nil
    if type(value) == "boolean" then
        return value
    end
    return Perks.AUTO_DIG_DEFAULT
end

-- Neue settings-Tabelle mit der Einstellung (Remote SetAutoDig). Andere Felder bleiben.
function Perks.withAutoDig(settings: any, enabled: boolean): { [string]: any }
    local result: { [string]: any } = if type(settings) == "table" then table.clone(settings) else {}
    result.autoDig = enabled == true
    return result
end

-- Sammelt Auto-Dig gerade? Pass "autoDig" und Einstellung an.
function Perks.autoDigActive(profile: any, data: any?): boolean
    return Perks.owns(profile, "autoDig", data) and Perks.autoDigSetting(profile) == true
end

-- Will der Spieler sammeln? Taste gehalten oder Auto-Dig aktiv. Ein SetCollecting(false) vom Client
-- stoppt Auto-Dig darum nicht.
function Perks.wantsCollecting(clientHolding: boolean, autoDigActive: boolean): boolean
    return clientHolding == true or autoDigActive == true
end

-- Entscheidung je Takt für Auto-Dig (siehe AutoDigInput/AutoDigDecision).
--  * nicht aktiv: nichts tun; war es im letzten Takt aktiv, Halten beenden (stop). Ohne Pass oder mit
--    Schalter aus ändert sich am Sammeln also nichts.
--  * aktiv, Tank voll: nicht halten; "tankFull" genau einmal je Füllung, und nur, wenn der Spieler
--    sammeln könnte (nicht tot, nicht am Stand).
--  * aktiv, Platz im Tank: halten (oder die Frist erneuern), wenn der Spieler sammeln darf. Nach dem
--    Verkauf ist wieder Platz, das Sammeln läuft von selbst weiter.
function Perks.autoDigStep(input: AutoDigInput): AutoDigDecision
    if not input.active then
        return { hold = false, stop = input.wasActive == true, notifyFull = false, fullNoticed = false }
    end
    if input.full then
        local notify = input.canCollect and not input.fullNoticed
        return { hold = false, stop = false, notifyFull = notify, fullNoticed = input.fullNoticed or input.canCollect }
    end
    return { hold = input.canCollect, stop = false, notifyFull = false, fullNoticed = false }
end

-- Ein Takt des Sand-Service für einen Spieler (alle Economy-Werte aus den Tabellen, Uhr von außen):
--  1. Laufendes Sammeln abrechnen wie vor Paket 4.4: Darf der Spieler nicht sammeln (tot, am Stand),
--     bis jetzt abrechnen und stoppen; sonst Collecting.update, "tankFull", wenn der Tank dabei voll
--     wird.
--  2. Auto-Dig (autoDigStep): starten oder die Frist erneuern, nach dem Abschalten stoppen, "Tank voll"
--     nur beim Übergang. War Auto-Dig nie aktiv (memory nil) und ist es nicht, passiert hier nichts,
--     das Verhalten ist dann genau wie vor Paket 4.4.
-- Ändert `state` und `profile` (Tank) wie Collecting. Wartet nie.
function Perks.collectTick(state: Collecting.State, profile: any, t: number, options: Options?, canCollect: boolean, memory: AutoDigMemory?, data: any?): TickResult
    local added = 0
    local changed = false
    local notifyFull = false
    if state.holding then
        if not canCollect then
            Collecting.setHolding(state, profile, false, t, options)
            changed = true
        else
            local result = Collecting.update(state, profile, t, options)
            added = result.added
            notifyFull = result.full
            changed = result.added > 0 or not state.holding
        end
    end

    local active = Perks.autoDigActive(profile, data)
    if not active and memory == nil then
        return { added = added, changed = changed, notifyFull = notifyFull, memory = nil }
    end
    local before: AutoDigMemory = memory or { wasActive = false, fullNoticed = false }
    local decision = Perks.autoDigStep({
        active = active,
        wasActive = before.wasActive,
        canCollect = canCollect,
        -- Kein ganzes Korn passt mehr (wie in Collecting.update), damit ein Bruchteil im Tank nicht
        -- jeden Takt neu startet und "voll" meldet.
        full = Collecting.space(profile, options) <= 0,
        fullNoticed = before.fullNoticed or notifyFull,
    })
    if decision.notifyFull then
        notifyFull = true
    end
    local wasHolding = state.holding
    if decision.stop then
        -- Gerade abgeschaltet (Schalter aus oder Pass weg): Halten beenden. Hält der Spieler die Taste
        -- selbst, startet seine nächste Auffrischung (alle holdRefreshSeconds) das Sammeln neu.
        Collecting.setHolding(state, profile, false, t, options)
    elseif decision.hold then
        Collecting.setHolding(state, profile, true, t, options)
    end
    if wasHolding ~= state.holding then
        changed = true
    end
    local nextMemory: AutoDigMemory? = if active then { wasActive = true, fullNoticed = decision.fullNoticed } else nil
    return { added = added, changed = changed, notifyFull = notifyFull, memory = nextMemory }
end

-- Kauf-Handler für den Münz-Boost (Shop.registerProduct(Perks.COIN_BOOST_PRODUCT_ID, ...)). Rechnet
-- auf der Profil-Kopie von Purchases, wartet nie und gibt nur `boosts` als Änderung zurück, keine
-- Gems. `clock` ist die Unix-Uhr (im Spiel os.time), per Closure. Die Meldung nach dem bestätigten
-- Speichern nennt die Restsekunden zu diesem Zeitpunkt.
function Perks.coinBoostHandler(clock: () -> number): (profile: any, product: any, data: any?) -> Prepared?
    return function(profile: any, product: any, data: any?): Prepared?
        local cfg = economyOf(data).coinBoost
        local seconds = if type(cfg) == "table" then cfg.durationSeconds else nil
        local boosts = Perks.extendCoinBoost(if type(profile) == "table" then profile.boosts else nil, clock(), seconds)
        if boosts == nil then
            return nil
        end
        local productId = if type(product) == "table" then product.id else Perks.COIN_BOOST_PRODUCT_ID
        return {
            changes = { boosts = boosts },
            gems = 0,
            announce = function(current: any): (string, { [string]: any })
                return Perks.BOOST_BOUGHT_KIND,
                    {
                        productId = productId,
                        addedSeconds = seconds,
                        coinBoostSeconds = Perks.coinBoostSeconds(current, clock()),
                    }
            end,
        }
    end
end

return Perks
