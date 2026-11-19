--!strict
-- Kisten, Quoten und Pity (Konzept: "Kisten, Quoten und Monetarisierung").
-- Quoten in Hundertstel-Prozent (10000 = 100 %). Anzeige und Auswurf lesen dieselben
-- Tabellen aus `Odds` (Logic/CrateRoll: `displayOdds` und `roll` über `oddsOf`). Die Event-Kiste
-- verweist auf dieselbe Tabelle wie die Goldkiste (gleiche Referenz, keine Kopie), damit die
-- Quoten nie auseinanderlaufen. Pity: Gold- und Event-Kiste haben dieselben Grenzen, aber jede
-- ihren eigenen Zähler im Profil (`pity.gold`, `pity.event`). Kisten ohne `pity` zählen nichts.

export type OddsTable = { [string]: number } -- Seltenheits-ID -> Hundertstel-Prozent

export type Pity = {
    epic: number, -- Episch oder besser spätestens bei dieser Öffnung
    legendary: number, -- Legendär oder besser spätestens bei dieser Öffnung
}

export type Crate = {
    id: string,
    name: string, -- Anzeigename für Spieler
    currency: "coins" | "gems",
    price: number,
    odds: OddsTable,
    pity: Pity?, -- nur Gold- und Event-Kiste garantieren etwas (je eigener Zähler)
    eventOnly: boolean, -- nur in der Saison kaufbar
}

local Odds: { wood: OddsTable, iron: OddsTable, gold: OddsTable } = {
    wood = {
        common = 6000,
        uncommon = 3000,
        rare = 900,
        epic = 100,
        legendary = 0,
        mythic = 0,
    },
    iron = {
        common = 3500,
        uncommon = 4000,
        rare = 2000,
        epic = 500,
        legendary = 0,
        mythic = 0,
    },
    gold = {
        common = 0,
        uncommon = 4000,
        rare = 4000,
        epic = 1500,
        legendary = 450,
        mythic = 50,
    },
}

local list: { Crate } = {
    {
        id = "wood",
        name = "Holzkiste",
        currency = "coins",
        price = 25000,
        odds = Odds.wood,
        pity = nil,
        eventOnly = false,
    },
    {
        id = "iron",
        name = "Eisenkiste",
        currency = "gems",
        price = 100,
        odds = Odds.iron,
        pity = nil,
        eventOnly = false,
    },
    {
        id = "gold",
        name = "Goldkiste",
        currency = "gems",
        price = 400,
        odds = Odds.gold,
        pity = { epic = 15, legendary = 60 },
        eventOnly = false,
    },
    {
        id = "event",
        name = "Event-Kiste",
        currency = "gems",
        price = 400,
        odds = Odds.gold, -- dieselbe Referenz wie die Goldkiste
        -- Eigene Pity mit denselben Grenzen wie die Goldkiste (entschieden in Paket 4.2), eigener
        -- Zähler `pity.event` im Profil: Öffnungen der Goldkiste zählen hier nicht und umgekehrt.
        pity = { epic = 15, legendary = 60 },
        eventOnly = true,
    },
}

local byId: { [string]: Crate } = {}
for _, crate in list do
    byId[crate.id] = crate
end

return {
    Odds = Odds,
    list = list,
    byId = byId,

    -- 10er-Paket: zehn kaufen, elf bekommen, mit denselben Quoten.
    -- Jede der 11 Öffnungen zählt für die Pity.
    bundle = { buy = 10, get = 11 },
}
