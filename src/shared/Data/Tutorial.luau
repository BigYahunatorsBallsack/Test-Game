--!strict
-- Die ersten 2 Minuten (Paket 1.6, Konzept: "Die ersten 2 Minuten").
-- Vier Schritte führen ohne Erklärtext durch die Schleife: Sand sammeln, verkaufen, erstes
-- Upgrade, Schaufel. Der Server entscheidet den Schritt (Logic/Tutorial), der Client zeigt
-- nur Text, Strahl und Markierung. Bedingungen:
--   tankAtLeast  Der Tank hat mindestens `amount` Sand (höchstens Economy.startTankCapacity, sonst
--                endet der Schritt nicht durch Sammeln).
--   sold         Der Spieler hat verkauft (Ereignis vom Server, nicht ausgewertet beim Laden).
--   node         Der Knoten `nodeId` ist gekauft (zählt auch beim Laden: erledigte Schritte entfallen).
-- Ziel (`target`) bestimmt, wohin der Strahl zeigt: sand, stand oder nichts (list = Upgrade-Liste).
-- Die Zielzeiten stehen in Economy.targetSeconds (erstes Upgrade etwa 20 s, Schaufel etwa 2 Minuten).

export type Condition = {
    kind: "tankAtLeast" | "sold" | "node",
    amount: number?,
    nodeId: string?,
}

export type Step = {
    id: string,
    text: string, -- Hinweis für Spieler (kurz, am Handy lesbar)
    target: "sand" | "stand" | "list",
    done: Condition, -- Der Schritt ist erledigt, sobald das gilt
    highlightNodeId: string?, -- Knoten, der in der Upgrade-Liste leuchtet
}

local steps: { Step } = {
    {
        id = "collect",
        text = "Halte die Taste zum Graben und fülle deinen Tank!",
        target = "sand",
        done = { kind = "tankAtLeast", amount = 15 },
    },
    {
        id = "sell",
        text = "Tank voll! Bring den Sand zum Händlerstand und verkaufe ihn.",
        target = "stand",
        done = { kind = "sold" },
    },
    {
        id = "firstUpgrade",
        text = "Kaufe dein erstes Upgrade: mehr Sand pro Sekunde!",
        target = "list",
        done = { kind = "node", nodeId = "collect_rate_1" },
        highlightNodeId = "collect_rate_1",
    },
    {
        id = "shovel",
        text = "Sammle weiter und spare für die Schaufel!",
        target = "sand",
        done = { kind = "node", nodeId = "collect_tool_2" },
        highlightNodeId = "collect_tool_2",
    },
}

return {
    steps = steps,
    -- Die Upgrade-Liste erscheint ab diesem Schritt (erst nach dem ersten Verkauf), damit Anfänger
    -- nicht von Knöpfen abgelenkt werden. Nach dem Tutorial ist sie immer sichtbar.
    showUpgradesFromStep = 3,
}
