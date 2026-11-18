--!strict
-- Fundstücke und Sets (Konzept: "Welt und Zonen"). Jede Zone hat 30 Fundstücke in
-- 6 Sets zu je 5. Die 150 Einträge sind Platzhalter (Paket 2.6) mit festen IDs
-- "<Zone>_s<Set>_<Slot>". Paket 3.3 ändert nur Namen und Beschreibungen, die IDs bleiben
-- für immer gleich, sonst gehen gespeicherte Sammlungen verloren. Fundquoten stehen in FindOdds.

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

local list: { Find } = {
    -- Zone: dunes (Dünenmeer)
    -- dunes, Set 1
    { id = "dunes_s1_1", name = "Dünenfund 1-1", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_1", rarityId = "common" },
    { id = "dunes_s1_2", name = "Dünenfund 1-2", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_1", rarityId = "common" },
    { id = "dunes_s1_3", name = "Dünenfund 1-3", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_1", rarityId = "common" },
    { id = "dunes_s1_4", name = "Dünenfund 1-4", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_1", rarityId = "uncommon" },
    { id = "dunes_s1_5", name = "Dünenfund 1-5", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_1", rarityId = "uncommon" },
    -- dunes, Set 2
    { id = "dunes_s2_1", name = "Dünenfund 2-1", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_2", rarityId = "common" },
    { id = "dunes_s2_2", name = "Dünenfund 2-2", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_2", rarityId = "common" },
    { id = "dunes_s2_3", name = "Dünenfund 2-3", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_2", rarityId = "uncommon" },
    { id = "dunes_s2_4", name = "Dünenfund 2-4", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_2", rarityId = "uncommon" },
    { id = "dunes_s2_5", name = "Dünenfund 2-5", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_2", rarityId = "rare" },
    -- dunes, Set 3
    { id = "dunes_s3_1", name = "Dünenfund 3-1", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_3", rarityId = "common" },
    { id = "dunes_s3_2", name = "Dünenfund 3-2", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_3", rarityId = "uncommon" },
    { id = "dunes_s3_3", name = "Dünenfund 3-3", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_3", rarityId = "uncommon" },
    { id = "dunes_s3_4", name = "Dünenfund 3-4", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_3", rarityId = "rare" },
    { id = "dunes_s3_5", name = "Dünenfund 3-5", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_3", rarityId = "rare" },
    -- dunes, Set 4
    { id = "dunes_s4_1", name = "Dünenfund 4-1", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_4", rarityId = "uncommon" },
    { id = "dunes_s4_2", name = "Dünenfund 4-2", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_4", rarityId = "uncommon" },
    { id = "dunes_s4_3", name = "Dünenfund 4-3", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_4", rarityId = "rare" },
    { id = "dunes_s4_4", name = "Dünenfund 4-4", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_4", rarityId = "rare" },
    { id = "dunes_s4_5", name = "Dünenfund 4-5", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_4", rarityId = "epic" },
    -- dunes, Set 5
    { id = "dunes_s5_1", name = "Dünenfund 5-1", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_5", rarityId = "uncommon" },
    { id = "dunes_s5_2", name = "Dünenfund 5-2", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_5", rarityId = "rare" },
    { id = "dunes_s5_3", name = "Dünenfund 5-3", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_5", rarityId = "rare" },
    { id = "dunes_s5_4", name = "Dünenfund 5-4", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_5", rarityId = "epic" },
    { id = "dunes_s5_5", name = "Dünenfund 5-5", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_5", rarityId = "legendary" },
    -- dunes, Set 6
    { id = "dunes_s6_1", name = "Dünenfund 6-1", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_6", rarityId = "rare" },
    { id = "dunes_s6_2", name = "Dünenfund 6-2", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_6", rarityId = "epic" },
    { id = "dunes_s6_3", name = "Dünenfund 6-3", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_6", rarityId = "epic" },
    { id = "dunes_s6_4", name = "Dünenfund 6-4", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_6", rarityId = "legendary" },
    { id = "dunes_s6_5", name = "Dünenfund 6-5", description = "Platzhalter (Paket 3.3)", zoneId = "dunes", setId = "dunes_set_6", rarityId = "mythic" },
    -- Zone: oasis
    -- oasis, Set 1
    { id = "oasis_s1_1", name = "Oasenfund 1-1", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_1", rarityId = "common" },
    { id = "oasis_s1_2", name = "Oasenfund 1-2", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_1", rarityId = "common" },
    { id = "oasis_s1_3", name = "Oasenfund 1-3", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_1", rarityId = "common" },
    { id = "oasis_s1_4", name = "Oasenfund 1-4", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_1", rarityId = "uncommon" },
    { id = "oasis_s1_5", name = "Oasenfund 1-5", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_1", rarityId = "uncommon" },
    -- oasis, Set 2
    { id = "oasis_s2_1", name = "Oasenfund 2-1", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_2", rarityId = "common" },
    { id = "oasis_s2_2", name = "Oasenfund 2-2", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_2", rarityId = "common" },
    { id = "oasis_s2_3", name = "Oasenfund 2-3", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_2", rarityId = "uncommon" },
    { id = "oasis_s2_4", name = "Oasenfund 2-4", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_2", rarityId = "uncommon" },
    { id = "oasis_s2_5", name = "Oasenfund 2-5", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_2", rarityId = "rare" },
    -- oasis, Set 3
    { id = "oasis_s3_1", name = "Oasenfund 3-1", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_3", rarityId = "common" },
    { id = "oasis_s3_2", name = "Oasenfund 3-2", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_3", rarityId = "uncommon" },
    { id = "oasis_s3_3", name = "Oasenfund 3-3", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_3", rarityId = "uncommon" },
    { id = "oasis_s3_4", name = "Oasenfund 3-4", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_3", rarityId = "rare" },
    { id = "oasis_s3_5", name = "Oasenfund 3-5", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_3", rarityId = "rare" },
    -- oasis, Set 4
    { id = "oasis_s4_1", name = "Oasenfund 4-1", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_4", rarityId = "uncommon" },
    { id = "oasis_s4_2", name = "Oasenfund 4-2", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_4", rarityId = "uncommon" },
    { id = "oasis_s4_3", name = "Oasenfund 4-3", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_4", rarityId = "rare" },
    { id = "oasis_s4_4", name = "Oasenfund 4-4", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_4", rarityId = "rare" },
    { id = "oasis_s4_5", name = "Oasenfund 4-5", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_4", rarityId = "epic" },
    -- oasis, Set 5
    { id = "oasis_s5_1", name = "Oasenfund 5-1", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_5", rarityId = "uncommon" },
    { id = "oasis_s5_2", name = "Oasenfund 5-2", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_5", rarityId = "rare" },
    { id = "oasis_s5_3", name = "Oasenfund 5-3", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_5", rarityId = "rare" },
    { id = "oasis_s5_4", name = "Oasenfund 5-4", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_5", rarityId = "epic" },
    { id = "oasis_s5_5", name = "Oasenfund 5-5", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_5", rarityId = "legendary" },
    -- oasis, Set 6
    { id = "oasis_s6_1", name = "Oasenfund 6-1", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_6", rarityId = "rare" },
    { id = "oasis_s6_2", name = "Oasenfund 6-2", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_6", rarityId = "epic" },
    { id = "oasis_s6_3", name = "Oasenfund 6-3", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_6", rarityId = "epic" },
    { id = "oasis_s6_4", name = "Oasenfund 6-4", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_6", rarityId = "legendary" },
    { id = "oasis_s6_5", name = "Oasenfund 6-5", description = "Platzhalter (Paket 3.3)", zoneId = "oasis", setId = "oasis_set_6", rarityId = "mythic" },
    -- Zone: canyon
    -- canyon, Set 1
    { id = "canyon_s1_1", name = "Canyonfund 1-1", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_1", rarityId = "common" },
    { id = "canyon_s1_2", name = "Canyonfund 1-2", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_1", rarityId = "common" },
    { id = "canyon_s1_3", name = "Canyonfund 1-3", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_1", rarityId = "common" },
    { id = "canyon_s1_4", name = "Canyonfund 1-4", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_1", rarityId = "uncommon" },
    { id = "canyon_s1_5", name = "Canyonfund 1-5", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_1", rarityId = "uncommon" },
    -- canyon, Set 2
    { id = "canyon_s2_1", name = "Canyonfund 2-1", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_2", rarityId = "common" },
    { id = "canyon_s2_2", name = "Canyonfund 2-2", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_2", rarityId = "common" },
    { id = "canyon_s2_3", name = "Canyonfund 2-3", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_2", rarityId = "uncommon" },
    { id = "canyon_s2_4", name = "Canyonfund 2-4", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_2", rarityId = "uncommon" },
    { id = "canyon_s2_5", name = "Canyonfund 2-5", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_2", rarityId = "rare" },
    -- canyon, Set 3
    { id = "canyon_s3_1", name = "Canyonfund 3-1", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_3", rarityId = "common" },
    { id = "canyon_s3_2", name = "Canyonfund 3-2", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_3", rarityId = "uncommon" },
    { id = "canyon_s3_3", name = "Canyonfund 3-3", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_3", rarityId = "uncommon" },
    { id = "canyon_s3_4", name = "Canyonfund 3-4", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_3", rarityId = "rare" },
    { id = "canyon_s3_5", name = "Canyonfund 3-5", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_3", rarityId = "rare" },
    -- canyon, Set 4
    { id = "canyon_s4_1", name = "Canyonfund 4-1", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_4", rarityId = "uncommon" },
    { id = "canyon_s4_2", name = "Canyonfund 4-2", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_4", rarityId = "uncommon" },
    { id = "canyon_s4_3", name = "Canyonfund 4-3", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_4", rarityId = "rare" },
    { id = "canyon_s4_4", name = "Canyonfund 4-4", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_4", rarityId = "rare" },
    { id = "canyon_s4_5", name = "Canyonfund 4-5", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_4", rarityId = "epic" },
    -- canyon, Set 5
    { id = "canyon_s5_1", name = "Canyonfund 5-1", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_5", rarityId = "uncommon" },
    { id = "canyon_s5_2", name = "Canyonfund 5-2", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_5", rarityId = "rare" },
    { id = "canyon_s5_3", name = "Canyonfund 5-3", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_5", rarityId = "rare" },
    { id = "canyon_s5_4", name = "Canyonfund 5-4", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_5", rarityId = "epic" },
    { id = "canyon_s5_5", name = "Canyonfund 5-5", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_5", rarityId = "legendary" },
    -- canyon, Set 6
    { id = "canyon_s6_1", name = "Canyonfund 6-1", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_6", rarityId = "rare" },
    { id = "canyon_s6_2", name = "Canyonfund 6-2", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_6", rarityId = "epic" },
    { id = "canyon_s6_3", name = "Canyonfund 6-3", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_6", rarityId = "epic" },
    { id = "canyon_s6_4", name = "Canyonfund 6-4", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_6", rarityId = "legendary" },
    { id = "canyon_s6_5", name = "Canyonfund 6-5", description = "Platzhalter (Paket 3.3)", zoneId = "canyon", setId = "canyon_set_6", rarityId = "mythic" },
    -- Zone: salt_lake
    -- salt_lake, Set 1
    { id = "salt_lake_s1_1", name = "Salzseefund 1-1", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_1", rarityId = "common" },
    { id = "salt_lake_s1_2", name = "Salzseefund 1-2", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_1", rarityId = "common" },
    { id = "salt_lake_s1_3", name = "Salzseefund 1-3", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_1", rarityId = "common" },
    { id = "salt_lake_s1_4", name = "Salzseefund 1-4", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_1", rarityId = "uncommon" },
    { id = "salt_lake_s1_5", name = "Salzseefund 1-5", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_1", rarityId = "uncommon" },
    -- salt_lake, Set 2
    { id = "salt_lake_s2_1", name = "Salzseefund 2-1", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_2", rarityId = "common" },
    { id = "salt_lake_s2_2", name = "Salzseefund 2-2", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_2", rarityId = "common" },
    { id = "salt_lake_s2_3", name = "Salzseefund 2-3", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_2", rarityId = "uncommon" },
    { id = "salt_lake_s2_4", name = "Salzseefund 2-4", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_2", rarityId = "uncommon" },
    { id = "salt_lake_s2_5", name = "Salzseefund 2-5", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_2", rarityId = "rare" },
    -- salt_lake, Set 3
    { id = "salt_lake_s3_1", name = "Salzseefund 3-1", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_3", rarityId = "common" },
    { id = "salt_lake_s3_2", name = "Salzseefund 3-2", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_3", rarityId = "uncommon" },
    { id = "salt_lake_s3_3", name = "Salzseefund 3-3", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_3", rarityId = "uncommon" },
    { id = "salt_lake_s3_4", name = "Salzseefund 3-4", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_3", rarityId = "rare" },
    { id = "salt_lake_s3_5", name = "Salzseefund 3-5", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_3", rarityId = "rare" },
    -- salt_lake, Set 4
    { id = "salt_lake_s4_1", name = "Salzseefund 4-1", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_4", rarityId = "uncommon" },
    { id = "salt_lake_s4_2", name = "Salzseefund 4-2", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_4", rarityId = "uncommon" },
    { id = "salt_lake_s4_3", name = "Salzseefund 4-3", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_4", rarityId = "rare" },
    { id = "salt_lake_s4_4", name = "Salzseefund 4-4", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_4", rarityId = "rare" },
    { id = "salt_lake_s4_5", name = "Salzseefund 4-5", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_4", rarityId = "epic" },
    -- salt_lake, Set 5
    { id = "salt_lake_s5_1", name = "Salzseefund 5-1", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_5", rarityId = "uncommon" },
    { id = "salt_lake_s5_2", name = "Salzseefund 5-2", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_5", rarityId = "rare" },
    { id = "salt_lake_s5_3", name = "Salzseefund 5-3", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_5", rarityId = "rare" },
    { id = "salt_lake_s5_4", name = "Salzseefund 5-4", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_5", rarityId = "epic" },
    { id = "salt_lake_s5_5", name = "Salzseefund 5-5", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_5", rarityId = "legendary" },
    -- salt_lake, Set 6
    { id = "salt_lake_s6_1", name = "Salzseefund 6-1", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_6", rarityId = "rare" },
    { id = "salt_lake_s6_2", name = "Salzseefund 6-2", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_6", rarityId = "epic" },
    { id = "salt_lake_s6_3", name = "Salzseefund 6-3", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_6", rarityId = "epic" },
    { id = "salt_lake_s6_4", name = "Salzseefund 6-4", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_6", rarityId = "legendary" },
    { id = "salt_lake_s6_5", name = "Salzseefund 6-5", description = "Platzhalter (Paket 3.3)", zoneId = "salt_lake", setId = "salt_lake_set_6", rarityId = "mythic" },
    -- Zone: ruins
    -- ruins, Set 1
    { id = "ruins_s1_1", name = "Ruinenfund 1-1", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_1", rarityId = "common" },
    { id = "ruins_s1_2", name = "Ruinenfund 1-2", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_1", rarityId = "common" },
    { id = "ruins_s1_3", name = "Ruinenfund 1-3", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_1", rarityId = "common" },
    { id = "ruins_s1_4", name = "Ruinenfund 1-4", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_1", rarityId = "uncommon" },
    { id = "ruins_s1_5", name = "Ruinenfund 1-5", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_1", rarityId = "uncommon" },
    -- ruins, Set 2
    { id = "ruins_s2_1", name = "Ruinenfund 2-1", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_2", rarityId = "common" },
    { id = "ruins_s2_2", name = "Ruinenfund 2-2", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_2", rarityId = "common" },
    { id = "ruins_s2_3", name = "Ruinenfund 2-3", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_2", rarityId = "uncommon" },
    { id = "ruins_s2_4", name = "Ruinenfund 2-4", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_2", rarityId = "uncommon" },
    { id = "ruins_s2_5", name = "Ruinenfund 2-5", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_2", rarityId = "rare" },
    -- ruins, Set 3
    { id = "ruins_s3_1", name = "Ruinenfund 3-1", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_3", rarityId = "common" },
    { id = "ruins_s3_2", name = "Ruinenfund 3-2", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_3", rarityId = "uncommon" },
    { id = "ruins_s3_3", name = "Ruinenfund 3-3", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_3", rarityId = "uncommon" },
    { id = "ruins_s3_4", name = "Ruinenfund 3-4", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_3", rarityId = "rare" },
    { id = "ruins_s3_5", name = "Ruinenfund 3-5", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_3", rarityId = "rare" },
    -- ruins, Set 4
    { id = "ruins_s4_1", name = "Ruinenfund 4-1", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_4", rarityId = "uncommon" },
    { id = "ruins_s4_2", name = "Ruinenfund 4-2", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_4", rarityId = "uncommon" },
    { id = "ruins_s4_3", name = "Ruinenfund 4-3", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_4", rarityId = "rare" },
    { id = "ruins_s4_4", name = "Ruinenfund 4-4", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_4", rarityId = "rare" },
    { id = "ruins_s4_5", name = "Ruinenfund 4-5", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_4", rarityId = "epic" },
    -- ruins, Set 5
    { id = "ruins_s5_1", name = "Ruinenfund 5-1", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_5", rarityId = "uncommon" },
    { id = "ruins_s5_2", name = "Ruinenfund 5-2", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_5", rarityId = "rare" },
    { id = "ruins_s5_3", name = "Ruinenfund 5-3", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_5", rarityId = "rare" },
    { id = "ruins_s5_4", name = "Ruinenfund 5-4", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_5", rarityId = "epic" },
    { id = "ruins_s5_5", name = "Ruinenfund 5-5", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_5", rarityId = "legendary" },
    -- ruins, Set 6
    { id = "ruins_s6_1", name = "Ruinenfund 6-1", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_6", rarityId = "rare" },
    { id = "ruins_s6_2", name = "Ruinenfund 6-2", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_6", rarityId = "epic" },
    { id = "ruins_s6_3", name = "Ruinenfund 6-3", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_6", rarityId = "epic" },
    { id = "ruins_s6_4", name = "Ruinenfund 6-4", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_6", rarityId = "legendary" },
    { id = "ruins_s6_5", name = "Ruinenfund 6-5", description = "Platzhalter (Paket 3.3)", zoneId = "ruins", setId = "ruins_set_6", rarityId = "mythic" },
}

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
