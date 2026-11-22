--!strict
-- Die fünf festen Zonen (Konzept: "Welt und Zonen") und die Event-Zonen der Saisons (Paket 5.5).
-- `requires` ist "start" oder die ID eines Knotens aus UpgradeTree, nie eine feste Zahl.
-- Meilenstein Sammeln 1/2/3 = Werkzeugknoten collect_tool_3/4/5.
-- Die Ruinenstadt verlangt den Knoten sandstorm_ruins (Paket 2.7): er setzt den ersten Sandsturm
-- (sandstorm_1) voraus und wird in jedem Lauf neu gekauft. Eine Zone verlangt nie einen vergebenen
-- Knoten, sonst bliebe sie nach dem Reset des Sturms für immer gesperrt (DataCheck).

export type Zone = {
    id: string,
    name: string, -- Anzeigename für Spieler
    sandTypeId: string, -- Eintrag in SandTypes
    requires: string, -- "start" oder Knoten-ID in UpgradeTree
    note: string, -- Besonderheit (Kurzbeschreibung)
    seasonId: string?, -- nur Event-Zonen (Paket 5.5): Saison aus Data/Seasons, in der die Zone offen ist
}

local list: { Zone } = {
    {
        id = "dunes",
        name = "Dünenmeer",
        sandTypeId = "yellow",
        requires = "start",
        note = "Einfache Funde, Tutorial",
    },
    {
        id = "oasis",
        name = "Oase",
        sandTypeId = "red",
        requires = "collect_tool_3",
        note = "Regen erhöht die Fundchance",
    },
    {
        id = "canyon",
        name = "Canyon",
        sandTypeId = "white",
        requires = "collect_tool_4",
        note = "Tiefe Schichten mit seltenen Funden",
    },
    {
        id = "salt_lake",
        name = "Salzsee",
        sandTypeId = "crystal",
        requires = "collect_tool_5",
        note = "Nebel versteckt Fundstellen",
    },
    {
        id = "ruins",
        name = "Ruinenstadt",
        sandTypeId = "black",
        requires = "sandstorm_ruins",
        note = "Mythische Funde",
    },
}

-- Event-Zonen (Paket 5.5): eine je Saison, offen nur während der Saison (Data/Seasons, Phase mit
-- `zoneOpen`). Sie stehen bewusst NICHT in `list`: `list` sind die fünf festen Zonen, auf die sich
-- Fundtabelle, Sammlung, Wetter, Sandsturm und Zonen-Freischaltung stützen. `byId` kennt beide, damit
-- Sammelrate, Reisen und Anzeige jede Zone nachschlagen können. Event-Zonen stehen nie in
-- `profile.zones` (nach der Saison sind sie zu) und haben keine Fundstücke.
-- `requires` ist ein kaufbarer Knoten wie bei den festen Zonen (nie "start": Neulinge sollen erst das
-- Tutorial und die ersten Upgrades erleben).
local events: { Zone } = {
    {
        id = "season_camp",
        name = "Karawanenlager",
        sandTypeId = "season",
        requires = "collect_tool_2",
        note = "Saison 1: Saison-Sand, Saison-Punkte, Koloss",
        seasonId = "season_1",
    },
}

local byId: { [string]: Zone } = {}
local eventById: { [string]: Zone } = {}
for _, zone in list do
    byId[zone.id] = zone
end
for _, zone in events do
    byId[zone.id] = zone
    eventById[zone.id] = zone
end

return {
    list = list,
    events = events,
    byId = byId,
    eventById = eventById,
}
