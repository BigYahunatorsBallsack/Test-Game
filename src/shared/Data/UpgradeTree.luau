--!strict
-- Skilltree-Knoten: der ganze Baum des ersten Laufs (Paket 2.1), von der Hand bis zur
-- Großmaschine, mit den Ästen Sammeln (Rate und Werkzeuge), Tank, Verkauf und Glück.
-- Zahlen und Simulation: docs/balance/skilltree_2_1.md und .py (Startwerte für den Playtest).
-- Die ersten Knoten (collect_rate_1/2, tank_1 bis tank_3, Schaufel) stammen aus Paket 1.6.
-- Verkauf und Glück beginnen nach der Schaufel, damit die ersten 2 Minuten gleich bleiben.
-- Die Liste steht in der Reihenfolge, in der ein Spieler die Knoten etwa trifft.
-- Zonen und Werkzeuge verweisen auf diese IDs, nie auf feste Zahlen.
--
-- Meilensteine: collect_tool_3 (Eimerkette) = Meilenstein 1, schaltet die Oase frei.
--               collect_tool_4 (Mini-Bagger) = Meilenstein 2, schaltet den Canyon frei.
--               collect_tool_5 (Saugroboter) = Meilenstein 3, schaltet den Salzsee frei.
-- Werkzeuge verlangen nur das vorige Werkzeug. Die späten Werkzeuge sind im Verhältnis zu
-- günstig und kommen darum früh (Saugroboter und Großmaschine kurz nach dem Mini-Bagger).
-- Entscheidung von Waltuh (18.11.2026): keine Sperren über Raten-Knoten, stattdessen hebt
-- Paket 6.4 die Werkzeugpreise an (docs/balance/skilltree_2_1.md, Befunde).
-- sandstorm_1 wird vom ersten Sandsturm vergeben (nicht gekauft) und bleibt über alle Stürme.
-- sandstorm_ruins (Paket 2.7) schaltet die Ruinenstadt frei, verlangt sandstorm_1 und den
-- Saugroboter und wird in jedem Lauf neu gekauft: der Sandsturm setzt alle gekauften Knoten zurück.
--
-- Gespeichert werden nur die gekauften IDs. Knoten dürfen hinzukommen, wegfallen oder neue
-- Werte bekommen, ohne Migration (siehe Logic/TreeEffects). Nur eine umbenannte ID braucht
-- einen Schritt in Logic/Migrations. Eine entfernte ID nie für einen anderen Knoten
-- wiederverwenden: Alte Profile tragen sie noch und bekämen den neuen Knoten geschenkt.

-- Wirkungen (berechnet in Logic/TreeEffects, nie im Profil gespeichert):
--   setTool            schaltet ein Werkzeug frei (toolId), das höchste zählt
--   rateBonus          bp Hundertstel-Prozent auf die Grundrate des aktuellen Werkzeugs
--   setTank            neue Gesamt-Tankgröße (der höchste gekaufte Wert zählt)
--   sellBonus          bp Hundertstel-Prozent auf den Münzpreis pro Sand
--   luckBonus          bp Hundertstel-Prozent auf die Fundchance (Wirkung ab Paket 2.6)
--   grantedBySandstorm vergeben statt gekauft
--   zoneKey            keine eigene Wirkung: schaltet Zonen frei, die diesen Knoten verlangen (Data/Zones)
-- Boni (bp) eines Typs addieren sich. Jeder Knoten gehört zum Ast seiner Wirkung (DataCheck).
export type Effect = {
    kind: "setTool" | "rateBonus" | "setTank" | "sellBonus" | "luckBonus" | "grantedBySandstorm" | "zoneKey",
    toolId: string?, -- bei "setTool": Eintrag in Tools
    bp: number?, -- bei "rateBonus", "sellBonus", "luckBonus": Hundertstel-Prozent (5000 = +50 %)
    capacity: number?, -- bei "setTank": Tankgröße in Sand
}

-- Festgenagelter Platz: Spalte (siehe Data/TreeLayout) und absolute Reihe (1 = unterste Reihe
-- über dem Start, größere Zahlen liegen weiter oben).
export type Pos = { column: number, row: number }

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
    pos: Pos?, -- optional: Platz im Baum festnageln (sonst rechnet Logic/TreeLayout ihn aus)
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
        id = "luck_1",
        name = "Scharfes Auge",
        description = "+10 % Fundchance",
        branch = "luck",
        requires = { "collect_tool_2" },
        cost = 30,
        effect = { kind = "luckBonus", bp = 1000 },
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
        id = "sell_1",
        name = "Feilschen",
        description = "+20 % Münzen pro Sand",
        branch = "sell",
        requires = { "collect_tool_2" },
        cost = 150,
        effect = { kind = "sellBonus", bp = 2000 },
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
        id = "collect_rate_3",
        name = "Schneller Spaten",
        description = "+25 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_rate_2" },
        cost = 300,
        effect = { kind = "rateBonus", bp = 2500 },
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
        id = "tank_4",
        name = "Lederschlauch",
        description = "Tank 400",
        branch = "tank",
        requires = { "tank_3", "collect_tool_3" },
        cost = 500,
        effect = { kind = "setTank", capacity = 400 },
    },
    {
        id = "luck_2",
        name = "Wünschelrute",
        description = "+10 % Fundchance",
        branch = "luck",
        requires = { "luck_1", "collect_tool_3" },
        cost = 800,
        effect = { kind = "luckBonus", bp = 1000 },
    },
    {
        id = "sell_2",
        name = "Marktkenntnis",
        description = "+20 % Münzen pro Sand",
        branch = "sell",
        requires = { "sell_1", "collect_tool_3" },
        cost = 1000,
        effect = { kind = "sellBonus", bp = 2000 },
    },
    {
        id = "collect_rate_4",
        name = "Schnelle Eimer",
        description = "+50 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_rate_3", "collect_tool_3" },
        cost = 1500,
        effect = { kind = "rateBonus", bp = 5000 },
    },
    {
        id = "tank_5",
        name = "Wasserfass",
        description = "Tank 1K",
        branch = "tank",
        requires = { "tank_4" },
        cost = 2500,
        effect = { kind = "setTank", capacity = 1000 },
    },
    {
        id = "collect_rate_5",
        name = "Doppelte Kette",
        description = "+50 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_rate_4" },
        cost = 4000,
        effect = { kind = "rateBonus", bp = 5000 },
    },
    {
        id = "sell_3",
        name = "Oasenmarkt",
        description = "+30 % Münzen pro Sand",
        branch = "sell",
        requires = { "sell_2" },
        cost = 6000,
        effect = { kind = "sellBonus", bp = 3000 },
    },
    {
        id = "tank_6",
        name = "Karrenladung",
        description = "Tank 2K",
        branch = "tank",
        requires = { "tank_5" },
        cost = 8000,
        effect = { kind = "setTank", capacity = 2000 },
    },
    {
        id = "collect_rate_6",
        name = "Lange Kette",
        description = "+50 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_rate_5" },
        cost = 12_000,
        effect = { kind = "rateBonus", bp = 5000 },
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
        id = "tank_7",
        name = "Kipplader",
        description = "Tank 6K",
        branch = "tank",
        requires = { "tank_6", "collect_tool_4" },
        cost = 100_000,
        effect = { kind = "setTank", capacity = 6000 },
    },
    {
        id = "luck_3",
        name = "Spürnase",
        description = "+15 % Fundchance",
        branch = "luck",
        requires = { "luck_2", "collect_tool_4" },
        cost = 50_000,
        effect = { kind = "luckBonus", bp = 1500 },
    },
    {
        id = "sell_4",
        name = "Canyon-Handel",
        description = "+30 % Münzen pro Sand",
        branch = "sell",
        requires = { "sell_3", "collect_tool_4" },
        cost = 200_000,
        effect = { kind = "sellBonus", bp = 3000 },
    },
    {
        id = "collect_rate_7",
        name = "Baggerlöffel",
        description = "+75 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_rate_6", "collect_tool_4" },
        cost = 300_000,
        effect = { kind = "rateBonus", bp = 7500 },
    },
    {
        id = "tank_8",
        name = "Container",
        description = "Tank 15K",
        branch = "tank",
        requires = { "tank_7" },
        cost = 400_000,
        effect = { kind = "setTank", capacity = 15_000 },
    },
    {
        id = "sell_5",
        name = "Karawanenhandel",
        description = "+50 % Münzen pro Sand",
        branch = "sell",
        requires = { "sell_4" },
        cost = 500_000,
        effect = { kind = "sellBonus", bp = 5000 },
    },
    {
        id = "collect_rate_8",
        name = "Turbomotor",
        description = "+100 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_rate_7" },
        cost = 750_000,
        effect = { kind = "rateBonus", bp = 10000 },
    },
    {
        id = "collect_tool_5",
        name = "Saugroboter",
        description = "Werkzeug: Saugroboter, saugt die Fläche leer",
        branch = "collect",
        requires = { "collect_tool_4" },
        cost = 90_000,
        effect = { kind = "setTool", toolId = "vacuum_robot" },
        milestone = 3,
    },
    {
        id = "tank_9",
        name = "Silo",
        description = "Tank 60K",
        branch = "tank",
        requires = { "tank_8", "collect_tool_5" },
        cost = 3_000_000,
        effect = { kind = "setTank", capacity = 60_000 },
    },
    {
        id = "luck_4",
        name = "Salzkompass",
        description = "+15 % Fundchance",
        branch = "luck",
        requires = { "luck_3", "collect_tool_5" },
        cost = 5_000_000,
        effect = { kind = "luckBonus", bp = 1500 },
    },
    {
        id = "collect_rate_9",
        name = "Starker Sog",
        description = "+100 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_rate_8", "collect_tool_5" },
        cost = 10_000_000,
        effect = { kind = "rateBonus", bp = 10000 },
    },
    {
        id = "sell_6",
        name = "Salzhändler",
        description = "+50 % Münzen pro Sand",
        branch = "sell",
        requires = { "sell_5", "collect_tool_5" },
        cost = 15_000_000,
        effect = { kind = "sellBonus", bp = 5000 },
    },
    {
        id = "tank_10",
        name = "Speicherturm",
        description = "Tank 150K",
        branch = "tank",
        requires = { "tank_9" },
        cost = 20_000_000,
        effect = { kind = "setTank", capacity = 150_000 },
    },
    {
        id = "collect_rate_10",
        name = "Doppelrüssel",
        description = "+150 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_rate_9" },
        cost = 35_000_000,
        effect = { kind = "rateBonus", bp = 15000 },
    },
    {
        id = "collect_tool_6",
        name = "Großmaschine",
        description = "Werkzeug: Großmaschine, frisst ganze Dünen",
        branch = "collect",
        requires = { "collect_tool_5" },
        cost = 1_100_000,
        effect = { kind = "setTool", toolId = "mega_machine" },
    },
    {
        id = "tank_11",
        name = "Frachtzug",
        description = "Tank 800K",
        branch = "tank",
        requires = { "tank_10", "collect_tool_6" },
        cost = 60_000_000,
        effect = { kind = "setTank", capacity = 800_000 },
    },
    {
        id = "sell_7",
        name = "Kristallbörse",
        description = "+75 % Münzen pro Sand",
        branch = "sell",
        requires = { "sell_6", "collect_tool_6" },
        cost = 100_000_000,
        effect = { kind = "sellBonus", bp = 7500 },
    },
    {
        id = "luck_5",
        name = "Sternkarte",
        description = "+20 % Fundchance",
        branch = "luck",
        requires = { "luck_4", "collect_tool_6" },
        cost = 100_000_000,
        effect = { kind = "luckBonus", bp = 2000 },
    },
    {
        id = "collect_rate_11",
        name = "Dünenfresser",
        description = "+200 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_rate_10", "collect_tool_6" },
        cost = 200_000_000,
        effect = { kind = "rateBonus", bp = 20000 },
    },
    {
        id = "luck_6",
        name = "Glück der Wüste",
        description = "+30 % Fundchance",
        branch = "luck",
        requires = { "luck_5" },
        cost = 150_000_000,
        effect = { kind = "luckBonus", bp = 3000 },
    },
    {
        id = "sell_8",
        name = "Wüstenbaron",
        description = "+100 % Münzen pro Sand",
        branch = "sell",
        requires = { "sell_7" },
        cost = 300_000_000,
        effect = { kind = "sellBonus", bp = 10000 },
    },
    {
        id = "tank_12",
        name = "Dünenspeicher",
        description = "Tank 1,5M",
        branch = "tank",
        requires = { "tank_11" },
        cost = 400_000_000,
        effect = { kind = "setTank", capacity = 1_500_000 },
    },
    {
        id = "collect_rate_12",
        name = "Sturmkraft",
        description = "+250 % Sand pro Sekunde",
        branch = "collect",
        requires = { "collect_rate_11" },
        cost = 600_000_000,
        effect = { kind = "rateBonus", bp = 25000 },
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
    {
        id = "sandstorm_ruins",
        name = "Ruinenkarte",
        description = "Öffnet die Ruinenstadt für diesen Lauf",
        branch = "sandstorm",
        requires = { "sandstorm_1", "collect_tool_5" },
        cost = 250_000_000, -- docs/balance/sandstorm_2_7.md: kostet etwa 32 s Ertrag und verkürzt den Lauf
        effect = { kind = "zoneKey" },
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
