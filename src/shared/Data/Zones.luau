--!strict
-- Die fünf Zonen (Konzept: "Welt und Zonen").
-- `requires` ist "start" oder die ID eines Knotens aus UpgradeTree, nie eine feste Zahl.
-- Meilenstein Sammeln 1/2/3 = Werkzeugknoten collect_tool_3/4/5.
-- Die Ruinenstadt verlangt den Knoten sandstorm_1, den der erste Sandsturm vergibt.

export type Zone = {
    id: string,
    name: string, -- Anzeigename für Spieler
    sandTypeId: string, -- Eintrag in SandTypes
    requires: string, -- "start" oder Knoten-ID in UpgradeTree
    note: string, -- Besonderheit (Kurzbeschreibung)
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
        requires = "sandstorm_1",
        note = "Mythische Funde",
    },
}

local byId: { [string]: Zone } = {}
for _, zone in list do
    byId[zone.id] = zone
end

return {
    list = list,
    byId = byId,
}
