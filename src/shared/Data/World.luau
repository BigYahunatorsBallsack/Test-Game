--!strict
-- Orte in der Welt, die der Server für Regeln braucht. Positionen sind Zahlen in Studs
-- ({ x, y, z }), keine Roblox-Typen. Bis die Welt der ersten Zone steht (Phase 3), legt der
-- Server einen Platzhalter-Stand an dieser Position an, falls im Workspace keiner liegt.

export type Vec3 = { x: number, y: number, z: number }

-- Eine Zone in der Welt (Paket 2.5). Die Zonen liegen nebeneinander entlang der x-Achse, jede
-- ist `zoneWidth` breit. Der Server prüft die Position des Spielers gegen `bounds`.
export type ZoneArea = {
    id: string, -- Eintrag in Zones
    bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
    spawn: Vec3, -- hier landet der Spieler beim Reisen
    stand: Vec3, -- Platzhalter-Händlerstand dieser Zone
    field: { center: Vec3, size: Vec3 }, -- Platzhalter-Sandfeld (Größe am 4-Stud-Raster)
    gate: { x: number, minZ: number, maxZ: number }?, -- Tor zur Zone davor (nur Anzeige, nicht die Sperre)
}

-- Reihenfolge von Westen nach Osten. Jede Zone muss in Zones stehen.
local ZONE_ORDER = { "dunes", "oasis", "canyon", "salt_lake", "ruins" }
local ZONE_WIDTH = 192 -- Breite einer Zone in Studs, ein Vielfaches von 4
local ZONE_MIN_Z = -60 -- südliche Grenze (der Stand liegt bei z = -20)
local ZONE_MAX_Z = 120 -- nördliche Grenze
local FIELD_SIZE = { x = 192, y = 8, z = 96 } :: Vec3 -- so breit wie die Zone, Felder grenzen aneinander
local FIELD_Z = 56 -- Mitte des Sandfelds
local STAND_POSITION_Z = -20
local SPAWN_Z = 0

local zones: { ZoneArea } = {}
for index, id in ZONE_ORDER do
    local cx = (index - 1) * ZONE_WIDTH
    table.insert(zones, {
        id = id,
        bounds = { minX = cx - ZONE_WIDTH / 2, maxX = cx + ZONE_WIDTH / 2, minZ = ZONE_MIN_Z, maxZ = ZONE_MAX_Z },
        spawn = { x = cx, y = 6, z = SPAWN_Z },
        stand = { x = cx, y = 3, z = STAND_POSITION_Z },
        field = { center = { x = cx, y = 0, z = FIELD_Z }, size = FIELD_SIZE },
        gate = if index > 1 then { x = cx - ZONE_WIDTH / 2, minZ = ZONE_MIN_Z, maxZ = ZONE_MAX_Z } else nil,
    })
end

local zonesById: { [string]: ZoneArea } = {}
for _, area in zones do
    zonesById[area.id] = area
end

local World = {
    zones = zones,
    zonesById = zonesById,
    -- Mindestabstand (Studs) von der Zonengrenze, auf den ein Spieler zurückgesetzt wird, der
    -- eine gesperrte Zone betreten hat.
    pushBackMarginStuds = 6,
    -- Abklingzeit zwischen zwei Reisen (Sekunden).
    travelCooldownSeconds = 3,
    -- CollectionService-Tag der Tor-Anzeigen. Das Attribut "ZoneId" nennt die Zone dahinter.
    gateTag = "ZoneGate",
    -- Sandfelder: Der Client zeigt Tutorial-Hinweise zum nächsten Teil mit diesem CollectionService-Tag.
    -- Gibt es keinen, zeigt er auf das Platzhalter-Sandfeld (Data/Terrain).
    sandField = {
        tag = "SandField",
    },
    sellStand = {
        -- CollectionService-Tag, an dem der Server Händlerstände in der Welt erkennt.
        tag = "SellStand",
        -- Platzhalter-Position, falls der Workspace keinen Stand mit diesem Tag enthält.
        placeholderPosition = { x = 0, y = 3, z = -20 } :: Vec3,
        -- Verkaufen ist nur in diesem Abstand (Studs) zur Mitte eines Stands erlaubt.
        rangeStuds = 14,
        -- Sichtweite des Prompts "Verkaufen" (Studs), etwas kleiner als die Reichweite.
        promptDistanceStuds = 10,
    },
}

return World
