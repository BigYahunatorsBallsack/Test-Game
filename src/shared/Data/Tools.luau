--!strict
-- Die sechs Werkzeugstufen (Konzept: "Werkzeuge und Skilltree").
-- Jede Stufe außer der Hand ist ein Meilenstein-Knoten im Ast "Sammeln" (UpgradeTree).
-- Die Hand ist die Startausrüstung und hat keinen Knoten (nodeId = "start").
-- Alle Werte sind Startwerte für den ersten Test.

export type Tool = {
    id: string,
    tier: number,
    name: string, -- Anzeigename für Spieler
    sandPerSecond: number,
    cost: number, -- Münzen
    nodeId: string, -- Knoten in UpgradeTree, der die Stufe freischaltet ("start" für die Hand)
    visual: string, -- Sichtbarer Sprung (Kurzbeschreibung für Art und Animation)
}

local list: { Tool } = {
    {
        id = "hand",
        tier = 1,
        name = "Hand",
        sandPerSecond = 1,
        cost = 0,
        nodeId = "start",
        visual = "Eine Handvoll Körner",
    },
    {
        id = "shovel",
        tier = 2,
        name = "Schaufel",
        sandPerSecond = 5,
        cost = 50,
        nodeId = "collect_tool_2",
        visual = "Gräbt eine Mulde",
    },
    {
        id = "bucket_chain",
        tier = 3,
        name = "Eimerkette",
        sandPerSecond = 25,
        cost = 600,
        nodeId = "collect_tool_3",
        visual = "Band trägt Sand zum Tank",
    },
    {
        id = "mini_digger",
        tier = 4,
        name = "Mini-Bagger",
        sandPerSecond = 150,
        cost = 7500,
        nodeId = "collect_tool_4",
        visual = "Fahrzeug mit Staubwolke",
    },
    {
        id = "vacuum_robot",
        tier = 5,
        name = "Saugroboter",
        sandPerSecond = 900,
        cost = 90000,
        nodeId = "collect_tool_5",
        visual = "Rüssel saugt die Fläche leer",
    },
    {
        id = "mega_machine",
        tier = 6,
        name = "Großmaschine",
        sandPerSecond = 6000,
        cost = 1100000,
        nodeId = "collect_tool_6",
        visual = "Frisst ganze Dünen",
    },
}

local byId: { [string]: Tool } = {}
for _, tool in list do
    byId[tool.id] = tool
end

return {
    list = list,
    byId = byId,
}
