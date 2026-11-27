--!strict
-- Zonen (Paket 2.5): Freischaltung, Position, Reisen. Rein, ohne Roblox-API, Lune-Tests in
-- tests/zones.spec.luau.
--
-- Freischaltung: Eine Zone ist frei, wenn ihr `requires`-Knoten (Data/Zones) gekauft ist ODER
-- die Zone schon im Profil (`profile.zones`) steht. So bleibt eine einmal frei gewordene Zone frei,
-- auch wenn ein Baum-Update den Knoten verschiebt oder entfernt.
--
-- Die Position des Charakters gehört dem Client. Darum entscheidet der Server mit `resolve`
-- selbst, in welcher Zone ein Spieler steht, und setzt ihn bei einer gesperrten Zone zurück.

local Zones = require("../Data/Zones")
local WorldData = require("../Data/World")
local TreeEffects = require("./TreeEffects")
local Seasons = require("./Seasons")
local Features = require("./Features")

export type Vec3 = { x: number, y: number, z: number }

export type Resolution = {
    kind: string, -- "none", "enter" oder "blocked"
    zoneId: string?, -- Zone an der Position (enter, blocked) oder die Zone, auf die zurückgesetzt wird (reset)
    pushTo: Vec3?, -- Zielposition bei blocked (innerhalb der aktuellen Zone) und reset (Spawn)
}

local Zone = {}

-- Ist die Voraussetzung (Start oder gekaufter Knoten) erfüllt? Unabhängig vom Profil-Eintrag.
function Zone.requirementMet(profile: any, zoneId: string): boolean
    local zone = Zones.byId[zoneId]
    if zone == nil then
        return false
    end
    return zone.requires == "start" or TreeEffects.owns(profile, zone.requires)
end

-- `unixNow` (Server-Uhr) braucht nur die Event-Zone (Paket 5.5): Sie ist offen, solange ihre Saison
-- läuft, die Woche `zoneOpen` hat und der Knoten gekauft ist. Ohne `unixNow` ist sie zu (sicherer
-- Standard). Sie steht nie in `profile.zones`, ein Eintrag dort zählt nicht.
function Zone.isUnlocked(profile: any, zoneId: string, unixNow: number?): boolean
    if Zones.byId[zoneId] == nil then
        return false
    end
    if Zones.eventById[zoneId] ~= nil then
        -- Überarbeitung Ü1: Ist die Event-Zone in Data/Features aus, ist sie immer zu.
        if not Features.on("eventZone") then
            return false
        end
        return unixNow ~= nil and Zone.requirementMet(profile, zoneId) and Seasons.zoneOpen(unixNow, zoneId)
    end
    local stored = profile.zones
    if type(stored) == "table" and stored[zoneId] == true then
        return true
    end
    return Zone.requirementMet(profile, zoneId)
end

-- Schreibt neu erfüllte Zonen ins Profil. Gibt die neu freigeschalteten Zonen zurück
-- (Reihenfolge der Tabelle), jede nur einmal.
function Zone.unlockNew(profile: any): { string }
    if type(profile.zones) ~= "table" then
        profile.zones = {}
    end
    local fresh: { string } = {}
    for _, zone in Zones.list do
        if profile.zones[zone.id] ~= true and Zone.requirementMet(profile, zone.id) then
            profile.zones[zone.id] = true
            table.insert(fresh, zone.id)
        end
    end
    return fresh
end

-- Alle freien Zonen als Menge (ID -> true) für die Anzeige beim Client.
function Zone.unlockedMap(profile: any, unixNow: number?): { [string]: boolean }
    local result: { [string]: boolean } = {}
    for _, zone in Zones.list do
        if Zone.isUnlocked(profile, zone.id) then
            result[zone.id] = true
        end
    end
    for _, zone in Zones.events do
        if Zone.isUnlocked(profile, zone.id, unixNow) then
            result[zone.id] = true
        end
    end
    return result
end

local function isNumber(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- In welcher Zone liegt die Position? nil außerhalb aller Zonen oder bei kaputten Zahlen.
function Zone.zoneAt(position: Vec3, world: any?): string?
    if type(position) ~= "table" or not isNumber(position.x) or not isNumber(position.z) then
        return nil
    end
    local source = world or WorldData
    for _, area in source.zones do
        local b = area.bounds
        if position.x >= b.minX and position.x < b.maxX and position.z >= b.minZ and position.z <= b.maxZ then
            return area.id
        end
    end
    return nil
end

-- Position innerhalb der Grenzen der Zone, mit Abstand `margin` zum Rand.
function Zone.clampInto(position: Vec3, zoneId: string, world: any?): Vec3
    local source = world or WorldData
    local area = source.zonesById[zoneId]
    if area == nil then
        return { x = position.x, y = position.y, z = position.z }
    end
    local b = area.bounds
    local margin = source.pushBackMarginStuds
    return {
        x = math.clamp(position.x, b.minX + margin, b.maxX - margin),
        y = position.y,
        z = math.clamp(position.z, b.minZ + margin, b.maxZ - margin),
    }
end

-- Was soll der Server tun, wenn der Spieler an `position` steht?
--   none     nichts (außerhalb aller Zonen oder in der aktuellen Zone)
--   enter    freie andere Zone betreten: sie wird zur aktuellen Zone
--   blocked  gesperrte Zone betreten: zurück in die aktuelle Zone (`pushTo`), sie bleibt aktuell
--   reset    die aktuelle Zone selbst ist gesperrt oder unbekannt (zum Beispiel nach einem
--            Sandsturm oder einem Daten-Update): zurück auf die erste Zone am Spawn
function Zone.resolve(profile: any, position: Vec3, world: any?, unixNow: number?): Resolution
    local current = profile.currentZone
    if type(current) ~= "string" or not Zone.isUnlocked(profile, current, unixNow) then
        local first = Zones.list[1].id
        local area = (world or WorldData).zonesById[first]
        return { kind = "reset", zoneId = first, pushTo = if area ~= nil then area.spawn else nil }
    end
    local zoneId = Zone.zoneAt(position, world)
    if zoneId == nil or zoneId == current then
        return { kind = "none" }
    end
    if Zone.isUnlocked(profile, zoneId, unixNow) then
        return { kind = "enter", zoneId = zoneId }
    end
    return { kind = "blocked", zoneId = zoneId, pushTo = Zone.clampInto(position, current, world) }
end

-- Darf der Spieler jetzt in die Zone reisen? Gibt true oder false plus Grund zurück:
-- "unknown", "same", "locked", "cooldown". `lastTravelAt` ist die Zeit der letzten Reise (oder nil).
function Zone.canTravel(profile: any, zoneId: string, now: number, lastTravelAt: number?, world: any?, unixNow: number?): (boolean, string?)
    local source = world or WorldData
    if Zones.byId[zoneId] == nil or source.zonesById[zoneId] == nil then
        return false, "unknown"
    end
    if profile.currentZone == zoneId then
        return false, "same"
    end
    if not Zone.isUnlocked(profile, zoneId, unixNow) then
        return false, "locked"
    end
    if lastTravelAt ~= nil and now - lastTravelAt < source.travelCooldownSeconds then
        return false, "cooldown"
    end
    return true, nil
end

return Zone
