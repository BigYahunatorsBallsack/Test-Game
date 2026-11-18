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

export type Vec3 = { x: number, y: number, z: number }

export type Resolution = {
    kind: string, -- "none", "enter" oder "blocked"
    zoneId: string?, -- Zone an der Position (bei enter und blocked)
    pushTo: Vec3?, -- Zielposition bei blocked (innerhalb der aktuellen Zone)
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

function Zone.isUnlocked(profile: any, zoneId: string): boolean
    if Zones.byId[zoneId] == nil then
        return false
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
function Zone.unlockedMap(profile: any): { [string]: boolean }
    local result: { [string]: boolean } = {}
    for _, zone in Zones.list do
        if Zone.isUnlocked(profile, zone.id) then
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
function Zone.resolve(profile: any, position: Vec3, world: any?): Resolution
    local zoneId = Zone.zoneAt(position, world)
    local current = profile.currentZone
    if zoneId == nil or zoneId == current then
        return { kind = "none" }
    end
    if Zone.isUnlocked(profile, zoneId) then
        return { kind = "enter", zoneId = zoneId }
    end
    local anchor = if Zones.byId[current] ~= nil and (world or WorldData).zonesById[current] ~= nil then current else Zones.list[1].id
    return { kind = "blocked", zoneId = zoneId, pushTo = Zone.clampInto(position, anchor, world) }
end

-- Darf der Spieler jetzt in die Zone reisen? Gibt true oder false plus Grund zurück:
-- "unknown", "same", "locked", "cooldown". `lastTravelAt` ist die Zeit der letzten Reise (oder nil).
function Zone.canTravel(profile: any, zoneId: string, now: number, lastTravelAt: number?, world: any?): (boolean, string?)
    local source = world or WorldData
    if Zones.byId[zoneId] == nil or source.zonesById[zoneId] == nil then
        return false, "unknown"
    end
    if profile.currentZone == zoneId then
        return false, "same"
    end
    if not Zone.isUnlocked(profile, zoneId) then
        return false, "locked"
    end
    if lastTravelAt ~= nil and now - lastTravelAt < source.travelCooldownSeconds then
        return false, "cooldown"
    end
    return true, nil
end

return Zone
