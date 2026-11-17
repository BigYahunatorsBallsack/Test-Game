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
-- Gespeichert wird nur profile.tank und profile.coins (Zahlentyp BigNum).

local BigNum = require("./BigNum")
local Tools = require("../Data/Tools")
local Zones = require("../Data/Zones")
local SandTypes = require("../Data/SandTypes")
local Economy = require("../Data/Economy")
local UpgradeTree = require("../Data/UpgradeTree")

export type State = {
    holding: boolean,
    lastTick: number,
    holdUntil: number,
    carry: number,
}

export type UpdateResult = {
    added: number, -- ganze Körner, die gerade in den Tank kamen
    full: boolean, -- Tank ist voll (Sammeln wurde gestoppt)
}

export type Options = {
    -- Faktor auf die Tankgröße (z. B. Gamepass "Großer Tank", Paket 4.4). Standard 1.
    capacityMultiplier: number?,
}

-- Fallback, wenn die Zone im Profil unbekannt ist (sollte nach sanitize nicht vorkommen).
local FALLBACK_ZONE_ID = "dunes"

local Collecting = {}

-- Das höchste Werkzeug, dessen Knoten der Spieler besitzt. Unbekannte Knoten zählen nicht.
function Collecting.toolOf(profile: any): Tools.Tool
    local best = Tools.byId.hand
    for _, tool in Tools.list do
        local owned = tool.nodeId == "start" or (profile.nodes[tool.nodeId] == true and UpgradeTree.byId[tool.nodeId] ~= nil)
        if owned and tool.tier > best.tier then
            best = tool
        end
    end
    return best
end

-- Sand pro Sekunde.
function Collecting.rateOf(profile: any): number
    return Collecting.toolOf(profile).sandPerSecond
end

-- Tankgröße in Sand. Tank-Knoten aus dem Skilltree kommen in Paket 2.1 dazu.
function Collecting.capacityOf(_profile: any, options: Options?): number
    local multiplier = if options and options.capacityMultiplier then options.capacityMultiplier else 1
    return math.floor(Economy.startTankCapacity * multiplier)
end

function Collecting.zoneOf(profile: any): Zones.Zone
    local zone = Zones.byId[profile.currentZone]
    if zone == nil then
        return Zones.byId[FALLBACK_ZONE_ID]
    end
    return zone
end

-- Münzen pro Sand in der aktuellen Zone. Boni (Windkristalle, Freunde, Boosts, Verkauf-Ast)
-- kommen mit ihren Paketen dazu.
function Collecting.pricePerSand(profile: any): number
    local sandType = SandTypes.byId[Collecting.zoneOf(profile).sandTypeId]
    return Economy.baseCoinsPerSand * sandType.priceFactor
end

function Collecting.newState(now: number): State
    return { holding = false, lastTick = now, holdUntil = now, carry = 0 }
end

local function tankOf(profile: any): BigNum.BigNum
    return BigNum.deserialize(profile.tank)
end

function Collecting.isFull(profile: any, options: Options?): boolean
    local capacity = BigNum.new(Collecting.capacityOf(profile, options))
    return BigNum.compare(tankOf(profile), capacity) >= 0
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
    local space = math.max(capacity - BigNum.toNumber(tank), 0)

    local accrued = Collecting.rateOf(profile) * dt + state.carry
    local whole = math.floor(accrued)
    state.carry = accrued - whole
    local added = math.min(whole, math.floor(space))
    if added > 0 then
        profile.tank = BigNum.serialize(BigNum.add(tank, BigNum.new(added)))
    end
    result.added = added
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

-- Verkauft den ganzen Tank zum Preis der aktuellen Zone. Gibt die verdienten Münzen und
-- die verkaufte Menge zurück, oder nil bei leerem Tank. Ändert profile.coins und profile.tank.
function Collecting.sell(state: State, profile: any, now: number, options: Options?): (BigNum.BigNum?, BigNum.BigNum?)
    Collecting.update(state, profile, now, options)
    local tank = tankOf(profile)
    if tank.m <= 0 then
        return nil, nil
    end
    local earned = BigNum.mulNumber(tank, Collecting.pricePerSand(profile))
    profile.coins = BigNum.serialize(BigNum.add(BigNum.deserialize(profile.coins), earned))
    profile.tank = BigNum.serialize(BigNum.zero())
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

return Collecting
