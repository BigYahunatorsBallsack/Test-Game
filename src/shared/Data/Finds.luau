--!strict
-- Fundstücke und Sets (Konzept: "Welt und Zonen"). Jede Zone hat 30 Fundstücke in
-- 6 Sets zu je 5. Die Fundliste selbst ist noch leer, sie wird in Paket 3.3
-- (data-worker) mit 150 Einträgen gefüllt. Fundquoten stehen in FindOdds.

local Zones = require("./Zones")

export type FindSet = {
    id: string, -- z. B. "dunes_set_1"
    zoneId: string,
    index: number, -- 1 bis SETS_PER_ZONE
    size: number, -- Slots pro Set
}

export type Find = {
    id: string,
    name: string, -- Anzeigename für Spieler
    description: string,
    zoneId: string,
    setId: string,
    rarityId: string,
}

local SETS_PER_ZONE = 6
local FINDS_PER_SET = 5

local sets: { FindSet } = {}
for _, zone in Zones.list do
    for index = 1, SETS_PER_ZONE do
        table.insert(sets, {
            id = `{zone.id}_set_{index}`,
            zoneId = zone.id,
            index = index,
            size = FINDS_PER_SET,
        })
    end
end

local setsById: { [string]: FindSet } = {}
for _, findSet in sets do
    setsById[findSet.id] = findSet
end

-- TODO(3.3): 150 Fundstücke eintragen (30 je Zone, je Set 5).
local list: { Find } = {}

local byId: { [string]: Find } = {}
for _, find in list do
    byId[find.id] = find
end

return {
    SETS_PER_ZONE = SETS_PER_ZONE,
    FINDS_PER_SET = FINDS_PER_SET,
    sets = sets,
    setsById = setsById,
    list = list,
    byId = byId,
}
