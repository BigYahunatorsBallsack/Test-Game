--!strict
-- Skilltree-Knoten. In Paket 0.1 sind nur die Werkzeug-Meilensteine (Ast "Sammeln") und
-- der Knoten des ersten Sandsturms enthalten, alle anderen Knoten folgen in Paket 2.1.
-- Zonen und Werkzeuge verweisen auf diese IDs, nie auf feste Zahlen.
--
-- Meilensteine: collect_tool_3 (Eimerkette) = Meilenstein 1, schaltet die Oase frei.
--               collect_tool_4 (Mini-Bagger) = Meilenstein 2, schaltet den Canyon frei.
--               collect_tool_5 (Saugroboter) = Meilenstein 3, schaltet den Salzsee frei.
-- sandstorm_1 wird vom ersten Sandsturm vergeben (nicht gekauft) und schaltet die
-- Ruinenstadt frei.

export type Effect = {
    kind: "setTool" | "grantedBySandstorm",
    toolId: string?, -- bei "setTool": Eintrag in Tools
}

export type Node = {
    id: string,
    branch: "collect" | "tank" | "sell" | "luck" | "sandstorm",
    requires: { string }, -- Knoten, die vorher gekauft sein müssen
    cost: number, -- Münzen (0 bei Knoten, die vergeben statt gekauft werden)
    effect: Effect,
    milestone: number?, -- Meilenstein-Nummer im Ast "Sammeln"
    granted: boolean?, -- true: wird vergeben, nicht gekauft
}

local list: { Node } = {
    {
        id = "collect_tool_2",
        branch = "collect",
        requires = {},
        cost = 50,
        effect = { kind = "setTool", toolId = "shovel" },
    },
    {
        id = "collect_tool_3",
        branch = "collect",
        requires = { "collect_tool_2" },
        cost = 600,
        effect = { kind = "setTool", toolId = "bucket_chain" },
        milestone = 1,
    },
    {
        id = "collect_tool_4",
        branch = "collect",
        requires = { "collect_tool_3" },
        cost = 7500,
        effect = { kind = "setTool", toolId = "mini_digger" },
        milestone = 2,
    },
    {
        id = "collect_tool_5",
        branch = "collect",
        requires = { "collect_tool_4" },
        cost = 90000,
        effect = { kind = "setTool", toolId = "vacuum_robot" },
        milestone = 3,
    },
    {
        id = "collect_tool_6",
        branch = "collect",
        requires = { "collect_tool_5" },
        cost = 1100000,
        effect = { kind = "setTool", toolId = "mega_machine" },
    },
    {
        id = "sandstorm_1",
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
