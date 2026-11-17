--!strict
-- Skilltree-Knoten. Enthalten sind die Werkzeug-Meilensteine (Ast "Sammeln"), der Knoten des
-- ersten Sandsturms und seit Paket 1.6 die ersten Mini-Käufe für die ersten 2 Minuten
-- (collect_rate_1/2 und tank_1 bis tank_3, Werte aus docs/balance/phase0_startwerte.md).
-- Alle anderen Knoten folgen in Paket 2.1.
-- Zonen und Werkzeuge verweisen auf diese IDs, nie auf feste Zahlen.
--
-- Meilensteine: collect_tool_3 (Eimerkette) = Meilenstein 1, schaltet die Oase frei.
--               collect_tool_4 (Mini-Bagger) = Meilenstein 2, schaltet den Canyon frei.
--               collect_tool_5 (Saugroboter) = Meilenstein 3, schaltet den Salzsee frei.
-- sandstorm_1 wird vom ersten Sandsturm vergeben (nicht gekauft) und schaltet die
-- Ruinenstadt frei.

-- Wirkungen: setTool = schaltet ein Werkzeug frei (toolId), rateBonus = addiert bp Hundertstel-
-- Prozent auf die Grundrate des aktuellen Werkzeugs (alle Boni addieren sich), setTank = neue
-- Gesamt-Tankgröße (der höchste gekaufte Wert zählt), grantedBySandstorm = vergeben statt gekauft.
export type Effect = {
    kind: "setTool" | "rateBonus" | "setTank" | "grantedBySandstorm",
    toolId: string?, -- bei "setTool": Eintrag in Tools
    bp: number?, -- bei "rateBonus": Hundertstel-Prozent (5000 = +50 %)
    capacity: number?, -- bei "setTank": Tankgröße in Sand
}

export type Node = {
    id: string,
    name: string, -- Anzeigename für Spieler
    description: string, -- Kurzbeschreibung der Wirkung für die Upgrade-Liste
    branch: "collect" | "tank" | "sell" | "luck" | "sandstorm",
    requires: { string }, -- Knoten, die vorher gekauft sein müssen
    cost: number, -- Münzen (0 bei Knoten, die vergeben statt gekauft werden)
    effect: Effect,
    milestone: number?, -- Meilenstein-Nummer im Ast "Sammeln"
    granted: boolean?, -- true: wird vergeben, nicht gekauft
}

local list: { Node } = {
    {
        id = "collect_rate_1",
        name = "Kräftigere Hände",
        description = "+50 % Sand pro Sekunde",
        branch = "collect",
        requires = {},
        cost = 15,
        effect = { kind = "rateBonus", bp = 5000 },
    },
    {
        id = "tank_1",
        name = "Größerer Beutel",
        description = "Tank 30",
        branch = "tank",
        requires = {},
        cost = 20,
        effect = { kind = "setTank", capacity = 30 },
    },
    {
        id = "collect_tool_2",
        name = "Schaufel",
        description = "Werkzeug: Schaufel, gräbt eine Mulde",
        branch = "collect",
        requires = {},
        cost = 50,
        effect = { kind = "setTool", toolId = "shovel" },
    },
    {
        id = "tank_2",
        name = "Rucksack",
        description = "Tank 60",
        branch = "tank",
        requires = { "tank_1" },
        cost = 60,
        effect = { kind = "setTank", capacity = 60 },
    },
    {
        id = "collect_rate_2",
        name = "Geübter Griff",
        description = "+25 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_tool_2" },
        cost = 120,
        effect = { kind = "rateBonus", bp = 2500 },
    },
    {
        id = "tank_3",
        name = "Sandsack",
        description = "Tank 150",
        branch = "tank",
        requires = { "tank_2" },
        cost = 250,
        effect = { kind = "setTank", capacity = 150 },
    },
    {
        id = "collect_tool_3",
        name = "Eimerkette",
        description = "Werkzeug: Eimerkette, Band trägt Sand zum Tank",
        branch = "collect",
        requires = { "collect_tool_2" },
        cost = 600,
        effect = { kind = "setTool", toolId = "bucket_chain" },
        milestone = 1,
    },
    {
        id = "collect_tool_4",
        name = "Mini-Bagger",
        description = "Werkzeug: Mini-Bagger, Fahrzeug mit Staubwolke",
        branch = "collect",
        requires = { "collect_tool_3" },
        cost = 7500,
        effect = { kind = "setTool", toolId = "mini_digger" },
        milestone = 2,
    },
    {
        id = "collect_tool_5",
        name = "Saugroboter",
        description = "Werkzeug: Saugroboter, saugt die Fläche leer",
        branch = "collect",
        requires = { "collect_tool_4" },
        cost = 90000,
        effect = { kind = "setTool", toolId = "vacuum_robot" },
        milestone = 3,
    },
    {
        id = "collect_tool_6",
        name = "Großmaschine",
        description = "Werkzeug: Großmaschine, frisst ganze Dünen",
        branch = "collect",
        requires = { "collect_tool_5" },
        cost = 1100000,
        effect = { kind = "setTool", toolId = "mega_machine" },
    },
    {
        id = "sandstorm_1",
        name = "Der erste Sturm",
        description = "Wird vom ersten Sandsturm vergeben",
        branch = "sandstorm",
        requires = {},
        cost = 0,
        effect = { kind = "grantedBySandstorm" },
        granted = true,
    },
}

local byId: { [string]: Node } = {}
for _, node in list do
    byId[node.id] = node
end

return {
    list = list,
    byId = byId,
}
