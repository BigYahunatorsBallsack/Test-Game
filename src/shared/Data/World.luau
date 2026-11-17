--!strict
-- Orte in der Welt, die der Server für Regeln braucht. Positionen sind Zahlen in Studs
-- ({ x, y, z }), keine Roblox-Typen. Bis die Welt der ersten Zone steht (Phase 3), legt der
-- Server einen Platzhalter-Stand an dieser Position an, falls im Workspace keiner liegt.

export type Vec3 = { x: number, y: number, z: number }

local World = {
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
