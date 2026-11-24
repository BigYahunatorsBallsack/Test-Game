--!strict
-- Sammeln, Tank und Verkaufen (Paket 1.2). Rein, ohne Roblox-API, Lune-Tests mit
-- simulierter Uhr (tests/collecting.spec.luau).
--
-- Der Client meldet nur "ich halte" / "ich lasse los" (setHolding) und "ich verkaufe"
-- (sell). Wie viel Sand entsteht, rechnet der Server aus seiner eigenen Uhr, der Rate des
-- Werkzeugs und der Tankgröße. Es gibt bewusst keinen Parameter für eine Menge.
--
-- Zustand pro Spieler (nicht gespeichert, nur im Speicher des Servers):
--   holding   hält der Spieler gerade?
--   lastTick  Server-Zeit, bis zu der schon abgerechnet wurde
--   holdUntil bis wann das letzte SetCollecting(true) gilt (Frist gegen hängende Clients)
--   carry     Bruchteil eines Korns aus der letzten Abrechnung (Tank enthält nur ganze Körner)
--   findSeconds Sekunden, in denen wirklich Sand floss, je Zone (für die Fundchance, Paket 2.6)
-- Gespeichert wird nur profile.tank, profile.tankMix und profile.coins (Zahlentyp BigNum).
--
-- Gemischter Tank (Paket 2.5): `tank` ist die Gesamtmenge, `tankMix` merkt sich je Sandsorte, wie
-- viel davon wo gesammelt wurde. Verkaufen zahlt jede Sorte mit ihrem eigenen Faktor, an
-- jedem Stand, und nie mehr als `tank` hergibt (billigste Sorte zuerst). Was in `tank` steht,
-- aber nicht in `tankMix` (alte Daten, Debug-Werte), zählt zum billigsten Preis.
--
-- Gamepasses und Münz-Boost (Paket 4.4): `Options` trägt den Tank-Faktor ("Großer Tank") und den
-- Münz-Faktor ("2x Münzen" mal Münz-Boost), beide aus Logic/Perks.options. Der Münz-Faktor wirkt
-- auf pricePerSand, priceOf, tankValue (auch auf Sand ohne Mix-Eintrag) und sell, also auf alles,
-- was Wind.credit bucht. Ohne Options (oder mit Faktor 1) rechnet alles genau wie vor Paket 4.4.

local BigNum = require("./BigNum")
local Tools = require("../Data/Tools")
local Zones = require("../Data/Zones")
local SandTypes = require("../Data/SandTypes")
local Economy = require("../Data/Economy")
local UpgradeTree = require("../Data/UpgradeTree")
local TreeEffects = require("./TreeEffects")
local Collection = require("./Collection")
local Wind = require("./Wind")
local Equipment = require("./Equipment")

export type State = {
    holding: boolean,
    lastTick: number,
    holdUntil: number,
    carry: number,
    -- Echte Sammelzeit je Zone, die der Finds-Service noch nicht abgeholt hat (Paket 2.6).
    findSeconds: { [string]: number },
}

export type UpdateResult = {
    added: number, -- ganze Körner, die gerade in den Tank kamen
    full: boolean, -- Tank ist voll (Sammeln wurde gestoppt)
}

export type Options = {
    -- Faktor auf die Tankgröße (z. B. Gamepass "Großer Tank", Paket 4.4). Standard 1; kaputte Werte
    -- (kein number, NaN, unendlich, 0 oder negativ) zählen als 1.
    capacityMultiplier: number?,
    -- Faktor auf alle Münzen aus Verkäufen (Gamepass "2x Münzen" mal Münz-Boost, Paket 4.4).
    -- Standard 1; kaputte Werte (kein number, NaN, unendlich, 0 oder negativ) zählen als 1.
    coinMultiplier: number?,
}

-- Fallback, wenn die Zone im Profil unbekannt ist (sollte nach sanitize nicht vorkommen).
local FALLBACK_ZONE_ID = "dunes"

local Collecting = {}

-- Faktor aus `options` (Paket 4.4). Kaputte Werte (kein number, NaN, unendlich, 0 oder negativ) zählen
-- als 1, damit ein Fehler nie Münzen oder Tankplatz vernichtet oder ins Unendliche treibt.
local function factor(value: any): number
    if type(value) == "number" and value == value and value > 0 and value < math.huge then
        return value
    end
    return 1
end

local function coinFactor(options: Options?): number
    return factor(if options ~= nil then options.coinMultiplier else nil)
end

-- Das höchste Werkzeug, dessen Knoten der Spieler besitzt. Unbekannte Knoten zählen nicht.
function Collecting.toolOf(profile: any): Tools.Tool
    return TreeEffects.of(profile).tool
end

-- Sand pro Sekunde: Grundrate des Werkzeugs mal (1 + Summe der Sammelraten-Boni aus dem Baum) mal
-- (1 + Summe der Boni der ausgerüsteten Kisten-Items, Paket 4.3).
function Collecting.rateOf(profile: any): number
    local effects = TreeEffects.of(profile)
    return effects.tool.sandPerSecond * (10000 + effects.rateBonusBp) / 10000 * Equipment.multiplier(profile)
end

-- Tankgröße in Sand: der größte gekaufte Tank-Knoten (sonst die Startgröße), danach der
-- Faktor aus `options` (zum Beispiel Gamepass "Großer Tank", Paket 4.4).
function Collecting.capacityOf(profile: any, options: Options?): number
    local base = TreeEffects.of(profile).tankCapacity
    return math.floor(base * factor(if options ~= nil then options.capacityMultiplier else nil))
end

-- Gekaufte Knoten, die der Baum kennt, als Menge (ID -> true) für die Anzeige beim Client.
function Collecting.ownedNodes(profile: any): { [string]: boolean }
    local result: { [string]: boolean } = {}
    for nodeId, owned in profile.nodes do
        if owned == true and UpgradeTree.byId[nodeId] ~= nil then
            result[nodeId] = true
        end
    end
    return result
end

function Collecting.zoneOf(profile: any): Zones.Zone
    local zone = Zones.byId[profile.currentZone]
    if zone == nil then
        return Zones.byId[FALLBACK_ZONE_ID]
    end
    return zone
end

-- Münzen pro Sand in der aktuellen Zone: Grundpreis mal Sandfaktor mal Verkauf-Ast (Paket 2.1)
-- mal Sammlungsbonus (Paket 2.6) mal Windkristalle (Paket 2.7) mal Münz-Faktor aus `options`
-- (Gamepass "2x Münzen" und Münz-Boost, Paket 4.4). Freunde-Bonus folgt mit seinem Paket.
function Collecting.pricePerSand(profile: any, options: Options?): number
    local sandType = SandTypes.byId[Collecting.zoneOf(profile).sandTypeId]
    return Economy.baseCoinsPerSand
        * sandType.priceFactor
        * TreeEffects.sellMultiplier(profile)
        * Collection.bonusMultiplier(profile)
        * Wind.multiplier(profile)
        * coinFactor(options)
end

-- Alle Schreibzugriffe auf den Tank laufen über addSand und clearTank, damit `tank` und `tankMix`
-- zusammenbleiben (Sandsturm, Offline-Ertrag und Events dürfen die Regel nicht umgehen).

-- Der Preis des billigsten Sands (für Sand ohne bekannte Sorte).
local function cheapestFactor(): number
    local lowest = math.huge
    for _, sandType in SandTypes.list do
        lowest = math.min(lowest, sandType.priceFactor)
    end
    return if lowest == math.huge then 1 else lowest
end

-- Münzen pro Sand einer bestimmten Sandsorte (Grundpreis mal Faktor der Sorte mal Verkauf-Ast mal
-- Sammlungsbonus mal Windkristalle mal Münz-Faktor aus `options`).
function Collecting.priceOf(profile: any, sandTypeId: string, options: Options?): number
    local sandType = SandTypes.byId[sandTypeId]
    if sandType == nil then
        return 0
    end
    return Economy.baseCoinsPerSand
        * sandType.priceFactor
        * TreeEffects.sellMultiplier(profile)
        * Collection.bonusMultiplier(profile)
        * Wind.multiplier(profile)
        * coinFactor(options)
end

-- Die Sandsorte der aktuellen Zone.
function Collecting.sandTypeOf(profile: any): string
    return Collecting.zoneOf(profile).sandTypeId
end

local function mixOf(profile: any): { [string]: any }
    if type(profile.tankMix) ~= "table" then
        profile.tankMix = {}
    end
    return profile.tankMix
end

-- Legt gesammelten Sand in den Tank, in die Sorte `sandTypeId` (Standard: aktuelle Zone).
function Collecting.addSand(profile: any, amount: number, sandTypeId: string?)
    if amount ~= amount or amount <= 0 or amount == math.huge then
        return
    end
    local typeId = sandTypeId or Collecting.sandTypeOf(profile)
    local tank = BigNum.deserialize(profile.tank)
    profile.tank = BigNum.serialize(BigNum.add(tank, BigNum.new(amount)))
    local mix = mixOf(profile)
    mix[typeId] = BigNum.serialize(BigNum.add(BigNum.deserialize(mix[typeId]), BigNum.new(amount)))
end

-- Leert den Tank und den Mix zusammen.
function Collecting.clearTank(profile: any)
    profile.tank = BigNum.serialize(BigNum.zero())
    profile.tankMix = {}
end

function Collecting.newState(now: number): State
    return { holding = false, lastTick = now, holdUntil = now, carry = 0, findSeconds = {} }
end

local function tankOf(profile: any): BigNum.BigNum
    return BigNum.deserialize(profile.tank)
end

function Collecting.isFull(profile: any, options: Options?): boolean
    local capacity = BigNum.new(Collecting.capacityOf(profile, options))
    return BigNum.compare(tankOf(profile), capacity) >= 0
end

-- Ganze Körner, die noch in den Tank passen (dieselbe Rechnung wie in `update`). 0 heißt: Sammeln
-- würde sofort als "voll" enden, auch wenn der Tank einen Bruchteil unter der Grenze steht. Auto-Dig
-- (Paket 4.4) prüft damit, ob es starten darf, damit ein Bruchteil kein Melden pro Takt auslöst.
function Collecting.space(profile: any, options: Options?): number
    local capacity = Collecting.capacityOf(profile, options)
    return math.max(math.floor(capacity - math.max(BigNum.toNumber(tankOf(profile)), 0)), 0)
end

-- Rechnet die Zeit seit dem letzten Aufruf ab. Ändert `state` und `profile.tank`.
function Collecting.update(state: State, profile: any, now: number, options: Options?): UpdateResult
    local result: UpdateResult = { added = 0, full = false }
    if not state.holding then
        state.lastTick = now
        return result
    end
    local endTime = math.min(now, state.holdUntil)
    local dt = endTime - state.lastTick
    -- Rückwärts springende Uhr oder Frist schon vorbei: nichts gutschreiben.
    if dt ~= dt or dt < 0 then
        dt = 0
    end
    local tank = tankOf(profile)
    local capacity = Collecting.capacityOf(profile, options)
    -- Ganze Körner: ein Tank mit Bruchteil (Altdaten, spätere Pakete) darf das Halten nie ewig offen lassen.
    local space = math.max(math.floor(capacity - math.max(BigNum.toNumber(tank), 0)), 0)

    local carryBefore = state.carry
    local accrued = Collecting.rateOf(profile) * dt + carryBefore
    local whole = math.floor(accrued)
    state.carry = accrued - whole
    local added = math.min(whole, math.floor(space))
    if added > 0 then
        Collecting.addSand(profile, added)
    end
    result.added = added
    -- Echte Sammelzeit für die Fundchance: läuft der Tank in diesem Fenster voll, zählt nur die
    -- Zeit bis "voll".
    local rate = Collecting.rateOf(profile)
    local flowSeconds = dt
    if rate > 0 and whole > space then
        flowSeconds = math.clamp((space - carryBefore) / rate, 0, dt)
    end
    if flowSeconds > 0 then
        local zoneId = Collecting.zoneOf(profile).id
        state.findSeconds[zoneId] = (state.findSeconds[zoneId] or 0) + flowSeconds
    end
    state.lastTick = now

    if added >= space then
        -- Voll: Sammeln stoppt, ein angefangenes Korn verfällt.
        result.full = true
        state.holding = false
        state.carry = 0
    elseif now >= state.holdUntil then
        state.holding = false
    end
    return result
end

-- Der Client hält (true) oder lässt los (false). Erst wird die bisherige Zeit abgerechnet.
-- Mit vollem Tank beginnt kein Sammeln.
function Collecting.setHolding(state: State, profile: any, holding: boolean, now: number, options: Options?): UpdateResult
    local result = Collecting.update(state, profile, now, options)
    if not holding then
        state.holding = false
        return result
    end
    if Collecting.isFull(profile, options) then
        state.holding = false
        result.full = true
        return result
    end
    state.holding = true
    state.holdUntil = now + Economy.collecting.holdTimeoutSeconds
    return result
end

-- Wechselt die aktuelle Zone. Erst wird das offene Sammelfenster mit der alten Sandsorte
-- abgerechnet, danach zählt die neue. Ein angefangenes Korn verfällt.
function Collecting.setZone(state: State, profile: any, zoneId: string, now: number, options: Options?): UpdateResult
    local result = Collecting.update(state, profile, now, options)
    profile.currentZone = zoneId
    state.carry = 0
    return result
end

-- Münzen, die der Tank jetzt beim Verkauf brächte (ganze Münzen). Jede Sandsorte im Tank wird mit
-- ihrem eigenen Faktor bezahlt. Ändert nichts. Auch der Sandsturm (Paket 2.7) nutzt das für seine
-- Vorschau, damit Anzeige und Verkauf dieselbe Rechnung haben (mit denselben `options`, Paket 4.4).
function Collecting.tankValue(profile: any, options: Options?): BigNum.BigNum
    local tank = tankOf(profile)
    if tank.m <= 0 then
        return BigNum.zero()
    end
    local mix = mixOf(profile)
    -- Billigste Sorte zuerst und nie mehr als der Tank: Ein zu großer Mix (kaputte oder
    -- fremd geschriebene Daten) kann so nie mehr bringen als der Tank hergibt.
    local typeIds: { string } = {}
    for typeId in mix do
        if SandTypes.byId[typeId] ~= nil then
            table.insert(typeIds, typeId)
        end
    end
    table.sort(typeIds, function(a: string, b: string): boolean
        local pa, pb = SandTypes.byId[a].priceFactor, SandTypes.byId[b].priceFactor
        if pa ~= pb then
            return pa < pb
        end
        return a < b
    end)
    local earned = BigNum.zero()
    local remaining = tank
    for _, typeId in typeIds do
        local amount = BigNum.deserialize(mix[typeId])
        if amount.m > 0 and remaining.m > 0 then
            local take = BigNum.min(amount, remaining)
            earned = BigNum.add(earned, BigNum.mulNumber(take, Collecting.priceOf(profile, typeId, options)))
            remaining = BigNum.sub(remaining, take)
        end
    end
    -- Sand ohne Eintrag im Mix (alte Daten, Debug-Werte) zählt zum billigsten Preis, mit denselben
    -- Faktoren wie priceOf (auch dem Münz-Faktor).
    if remaining.m > 0 then
        local price = Economy.baseCoinsPerSand
            * cheapestFactor()
            * TreeEffects.sellMultiplier(profile)
            * Collection.bonusMultiplier(profile)
            * Wind.multiplier(profile)
            * coinFactor(options)
        earned = BigNum.add(earned, BigNum.mulNumber(remaining, price))
    end
    -- Ganze Münzen: Ein Bruchteil aus dem Verkauf-Ast (zum Beispiel 15 Sand mal 1,1) verfällt.
    return BigNum.floor(earned)
end

-- Verkauft den ganzen Tank. Jede Sandsorte im Tank wird mit ihrem eigenen Faktor bezahlt, egal an
-- welchem Stand. Gibt die verdienten Münzen und die verkaufte Menge zurück, oder nil bei leerem
-- Tank. Ändert profile.coins, profile.runEarned, profile.tank und profile.tankMix. Der Münz-Faktor aus
-- `options` (Paket 4.4) steckt im gebuchten Betrag, `runEarned` (Sandsturm) zählt ihn nicht mit
-- (Paket 6.4, L1): Dafür wird der Tank noch einmal ohne Münz-Faktor bewertet.
function Collecting.sell(state: State, profile: any, now: number, options: Options?): (BigNum.BigNum?, BigNum.BigNum?)
    Collecting.update(state, profile, now, options)
    local tank = tankOf(profile)
    if tank.m <= 0 then
        Collecting.clearTank(profile) -- ein Mix ohne Tank verfällt
        return nil, nil
    end
    local earned = Collecting.tankValue(profile, options)
    Wind.credit(profile, earned, Collecting.tankValue(profile, nil))
    Collecting.clearTank(profile)
    return earned, tank
end

-- Liegt ein Punkt im Abstand `range` um die Mitte? (Abstand als dx, dy, dz)
function Collecting.inRange(dx: number, dy: number, dz: number, range: number): boolean
    local squared = dx * dx + dy * dy + dz * dz
    if squared ~= squared then
        return false
    end
    return squared <= range * range
end

-- Holt die gesammelte Sammelzeit je Zone ab (und setzt sie zurück). Der Finds-Service ruft das in
-- jedem Tick auf. Zeit aus allen Aufrufen von `update` (Sammeln, Verkaufen, Kaufen, Zonenwechsel)
-- landet hier, nichts geht verloren.
function Collecting.takeFindSeconds(state: State): { [string]: number }
    local taken = state.findSeconds
    state.findSeconds = {}
    return taken
end

return Collecting
