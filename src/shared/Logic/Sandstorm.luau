--!strict
-- Sandsturm (Prestige), Paket 2.7. Rein, ohne Roblox-API, Lune-Tests in tests/sandstorm.spec.luau.
--
-- Der Spieler löst den Sturm aus (Remote `Prestige` ohne Werte). Der Server prüft und rechnet hier:
--  1. Möglich ab dem Knoten `Economy.sandstorm.requiresNode` (Canyon frei) und wenn der Lauf
--     mindestens `minCrystals` bringt.
--  2. Kristalle = floor(crystalScale x (Einnahmen / crystalUnit) ^ crystalExponent). Einnahmen sind
--     `profile.runEarned` plus der Wert des vollen Tanks (er wird mitgezählt, nichts geht verloren).
--  3. Zurück geht alles, was zum Lauf gehört: Münzen, Tank, alle Knoten (also Werkzeug), Zonen
--     und die Einnahmen des Laufs. Es bleiben Sammlung, Skins und Inventar, Gems, Belege,
--     Kaufprotokoll und Ausgaben (Paket 4.1), Pity, Boosts, Gamepasses und Einstellungen (Paket 4.4),
--     Angebote (Paket 4.5), Daily, eingelöste Codes (Paket 5.2) und Tutorial. Vergebene Knoten
--     (`sandstorm_1`) werden neu vergeben.
--  4. Die Zonen starten neu: nur das Dünenmeer ist frei, die Ruinenstadt braucht in jedem Lauf den
--     Knoten `sandstorm_ruins`. So führt jeder Lauf durch alle Zonen und alle Bücher bleiben im Spiel.
--
-- `apply` rechnet zuerst alles aus und schreibt erst dann ins Profil. Es gibt dabei keine Wartezeit,
-- ein zweiter schneller Aufruf trifft schon auf das zurückgesetzte Profil ("requires") und
-- schreibt nie ein zweites Mal Kristalle gut.
--
-- Gamepasses und Münz-Boost (Paket 4.4): `runTotal`, `preview`, `check` und `apply` nehmen optional
-- die Collecting.Options des Spielers (Logic/Perks.options) und geben sie an Collecting.tankValue
-- weiter. So rechnen Vorschau, Sturm und Verkauf den Tank mit demselben Münz-Faktor. Pässe,
-- Einstellungen und Boost bleiben beim Sturm (KEEP_FIELDS).

local BigNum = require("./BigNum")
local Collecting = require("./Collecting")
local TreeEffects = require("./TreeEffects")
local Wind = require("./Wind")
local ZoneLogic = require("./Zones")
local EconomyData = require("../Data/Economy")
local UpgradeTree = require("../Data/UpgradeTree")
local ZonesData = require("../Data/Zones")

export type Reason = "requires" | "tooFew"

export type Preview = {
    unlocked: boolean, -- der Knoten für den Sturm ist da (der Knopf wird sichtbar)
    ready: boolean, -- der Sturm ginge jetzt
    reason: Reason?, -- warum nicht, wenn nicht
    runEarned: BigNum.Serialized, -- Einnahmen des Laufs inklusive Tankwert
    gain: number, -- Kristalle, die der Sturm jetzt gäbe
    needed: BigNum.Serialized, -- Einnahmen, ab denen der Sturm `minCrystals` bringt (für "noch X bis ...")
    minCrystals: number,
    crystalsNow: number,
    crystalsAfter: number,
    bonusBpNow: number,
    bonusBpAfter: number,
    prestiges: number,
    first: boolean, -- es wäre der erste Sturm
}

export type Result = {
    crystals: number, -- gutgeschriebene Kristalle
    total: number, -- Kristalle danach
    bonusBpBefore: number,
    bonusBpAfter: number,
    prestiges: number, -- Zahl der Stürme danach
    first: boolean,
}

local Sandstorm = {}

-- Was beim Sturm mit jedem Profilfeld passiert. Jedes Feld aus `Profile.default` steht in genau
-- einer Liste (Lune-Test), ein neues Feld muss also bewusst eingeordnet werden.
Sandstorm.RESET_FIELDS = { "coins", "tank", "tankMix", "nodes", "zones", "currentZone", "runEarned" }
Sandstorm.UPDATED_FIELDS = { "windCrystals", "prestiges" }
Sandstorm.KEEP_FIELDS = {
    "version",
    "gems",
    "finds",
    "pity",
    "inventory",
    "equipped",
    "itemStars",
    "receipts",
    "purchaseLog",
    "spent",
    "boosts",
    "passes", -- Gamepass-Besitz (Paket 4.4)
    "settings", -- Einstellungen, zum Beispiel Auto-Dig (Paket 4.4)
    "offers", -- Angebote: Fenster und Merker "gekauft" (Paket 4.5)
    "daily",
    "weekly", -- Wochen-Rangliste (Paket 5.7): ein Sturm löscht den Sammlungswert nicht
    "codes", -- eingelöste Codes (Paket 5.2): ein Sturm macht keinen Code wieder einlösbar
    "seasons", -- Saison-Punkte und Abholungen (Paket 5.5): ein Sturm setzt den Pass nie zurück
    "tutorial",
    "lastSeen",
    "createdAt",
}

local function configOf(data: any?): any
    local economy = if data and data.Economy then data.Economy else EconomyData
    return economy.sandstorm
end

local function isGood(value: any): boolean
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Kristalle für Einnahmen `earned`, ohne Rücksicht auf bisher gehaltene. Rechnet über den
-- Logarithmus, damit auch 10^300 Münzen nichts überlaufen lässt. Ergebnis in [0, maxCrystals].
function Sandstorm.crystalsFor(earned: BigNum.BigNum, data: any?): number
    local cfg = configOf(data)
    if earned.m <= 0 or not isGood(earned.m) or not isGood(earned.e) then
        return 0
    end
    local logRatio = math.log10(earned.m) + earned.e - math.log10(cfg.crystalUnit)
    local logValue = math.log10(cfg.crystalScale) + cfg.crystalExponent * logRatio
    if not isGood(logValue) then
        return 0
    end
    if logValue >= math.log10(cfg.maxCrystals) then
        return cfg.maxCrystals
    end
    -- Toleranz, damit ein exaktes Quadrat (4 Mio. bei Einheit 1 Mio. und Exponent 0,5 ergibt 2)
    -- nicht durch Rundung von log10 und Potenz auf 1 fällt.
    return math.clamp(math.floor(10 ^ logValue + 1e-9), 0, cfg.maxCrystals)
end

-- Einnahmen, bei denen die Formel `crystals` Kristalle ergibt (Umkehrung, nur für die Anzeige).
function Sandstorm.earningsFor(crystals: number, data: any?): BigNum.BigNum
    local cfg = configOf(data)
    local logValue = cfg.crystalUnit > 0 and (math.log10(cfg.crystalUnit) + math.log10(math.max(crystals, 1) / cfg.crystalScale) / cfg.crystalExponent) or 0
    if not isGood(logValue) then
        return BigNum.zero()
    end
    local exponent = math.floor(logValue)
    return BigNum.new(10 ^ (logValue - exponent), exponent)
end

-- Einnahmen des Laufs für die Kristallformel: bisherige Einnahmen plus Wert des Tanks (mit dem
-- Münz-Faktor aus `options`, wie beim Verkauf).
function Sandstorm.runTotal(profile: any, options: Collecting.Options?): BigNum.BigNum
    return BigNum.add(Wind.runEarned(profile), Collecting.tankValue(profile, options))
end

-- Vorschau für die Anzeige, ändert nichts.
function Sandstorm.preview(profile: any, data: any?, options: Collecting.Options?): Preview
    local cfg = configOf(data)
    local total = Sandstorm.runTotal(profile, options)
    local held = Wind.crystalsOf(profile)
    -- Gehaltene Kristalle sind nie über der Obergrenze, auch wenn die Tabelle sie später senkt.
    local gain = math.max(math.min(Sandstorm.crystalsFor(total, data), cfg.maxCrystals - held), 0)
    local unlocked = TreeEffects.owns(profile, cfg.requiresNode)
    local reason: Reason? = nil
    if not unlocked then
        reason = "requires"
    elseif gain < cfg.minCrystals then
        reason = "tooFew"
    end
    local prestiges = if isGood(profile.prestiges) and profile.prestiges >= 0 then math.floor(profile.prestiges) else 0
    return {
        unlocked = unlocked,
        ready = reason == nil,
        reason = reason,
        runEarned = BigNum.serialize(total),
        gain = gain,
        needed = BigNum.serialize(Sandstorm.earningsFor(cfg.minCrystals, data)),
        minCrystals = cfg.minCrystals,
        crystalsNow = held,
        crystalsAfter = held + gain,
        bonusBpNow = held * EconomyData.windCrystalBonusBp,
        bonusBpAfter = (held + gain) * EconomyData.windCrystalBonusBp,
        prestiges = prestiges,
        first = prestiges == 0,
    }
end

-- Kann der Spieler den Sturm jetzt auslösen? nil = ja, sonst der Grund.
function Sandstorm.check(profile: any, data: any?, options: Collecting.Options?): Reason?
    return Sandstorm.preview(profile, data, options).reason
end

-- Löst den Sturm aus. Gibt das Ergebnis zurück oder (nil, Grund). Ändert `profile` nur bei Erfolg.
-- `options` wie bei `preview`, damit der Sturm genau die angezeigten Kristalle gibt.
function Sandstorm.apply(profile: any, data: any?, options: Collecting.Options?): (Result?, Reason?)
    local view = Sandstorm.preview(profile, data, options)
    if view.reason ~= nil then
        return nil, view.reason
    end

    -- Erst alles ausrechnen (auch die Zonen, an einem Schattenprofil) ...
    -- Es bleiben nur vergebene Knoten. Auch unbekannte IDs gehen zurück: Käme ein neuer Knoten
    -- auf einem Server mit neuerem Baum ins Profil und ein älterer Server löste den Sturm aus,
    -- bliebe er sonst stehen und wirkte im nächsten Lauf gratis.
    local nodes: { [string]: boolean } = {}
    for _, node in UpgradeTree.list do
        if node.granted == true or node.effect.kind == "grantedBySandstorm" then
            nodes[node.id] = true
        end
    end
    local shadow: any = { nodes = nodes, zones = {} }
    ZoneLogic.unlockNew(shadow) -- Start-Zonen und Zonen, die ein vergebener Knoten freischaltet
    local prestiges = view.prestiges + 1
    local startZone = ZonesData.list[1].id

    -- ... dann nur noch einfache Zuweisungen, die nichts werfen können (keine Wartezeit dazwischen).
    profile.windCrystals = view.crystalsAfter
    profile.prestiges = prestiges
    profile.coins = BigNum.serialize(BigNum.zero())
    profile.runEarned = BigNum.serialize(BigNum.zero())
    profile.tank = BigNum.serialize(BigNum.zero())
    profile.tankMix = {}
    profile.nodes = nodes
    profile.zones = shadow.zones
    profile.currentZone = startZone

    return {
        crystals = view.gain,
        total = view.crystalsAfter,
        bonusBpBefore = view.bonusBpNow,
        bonusBpAfter = view.bonusBpAfter,
        prestiges = prestiges,
        first = view.first,
    }, nil
end

return Sandstorm
