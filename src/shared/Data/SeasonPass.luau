--!strict
-- Saison-Pass (Paket 5.5): Stufen je Saison. Eine Zeile je Stufe mit dem Punktestand, ab dem sie
-- erreicht ist, und je einer Belohnung für die Gratis- und die Premium-Spur. Die Regeln stehen in
-- Logic/SeasonPass, DataCheck.checkSeasonPass prüft die Tabelle beim Serverstart. Zahlen und
-- Begründung: docs/balance/season_5_5.md (balance-analyst).
--
-- Belohnungen sind immer fest (nie Kisten, nie Zufall), damit der Pass auch bei gesperrten
-- Zufallsitems (ArePaidRandomItemsRestricted) erlaubt ist:
--   { kind = "gems", amount }           Gems (ganze Zahl, höchstens Economy.purchases.maxGems)
--   { kind = "coinBoost", seconds }     Münz-Boost (Economy.coinBoost), verlängert boosts.coinsUntil
--   { kind = "luck", seconds }          Glücks-Boost (Economy.luckBoost), verlängert boosts.luckUntil
--   { kind = "item", itemId }           festes Item aus Data/CrateItems mit `passOnly = true` (5.5b)
-- Eine neue Saison bekommt eine neue Zeile in `bySeason` (Schlüssel = Saison-ID aus Data/Seasons).
-- Nie Stufen einer Saison löschen oder umsortieren, solange Spieler abgeholt haben können (der Merker
-- "abgeholt" hängt an der Stufennummer).

export type Reward = {
    kind: string,
    amount: number?,
    seconds: number?,
    itemId: string?,
}

export type Tier = {
    points: number, -- ab diesem Punktestand ist die Stufe erreicht (aufsteigend, ganze Zahl ab 1)
    free: Reward, -- Gratis-Spur
    premium: Reward, -- Premium-Spur (nur mit Pass)
}

local bySeason: { [string]: { tiers: { Tier } } } = {
    season_1 = {
        -- Zahlen und Begründung: docs/balance/season_5_5.md (balance-analyst). Je Stufe: Punkte,
        -- Gratis-Spur, Premium-Spur.
        tiers = {
            { points = 30, free = { kind = "coinBoost", seconds = 300 }, premium = { kind = "item", itemId = "skin_rare_4" } }, -- 1
            { points = 90, free = { kind = "gems", amount = 5 }, premium = { kind = "gems", amount = 25 } }, -- 2
            { points = 180, free = { kind = "luck", seconds = 600 }, premium = { kind = "coinBoost", seconds = 1800 } }, -- 3
            { points = 320, free = { kind = "coinBoost", seconds = 600 }, premium = { kind = "gems", amount = 30 } }, -- 4
            { points = 510, free = { kind = "gems", amount = 5 }, premium = { kind = "luck", seconds = 1800 } }, -- 5
            { points = 760, free = { kind = "luck", seconds = 600 }, premium = { kind = "gems", amount = 35 } }, -- 6
            { points = 1070, free = { kind = "coinBoost", seconds = 600 }, premium = { kind = "coinBoost", seconds = 1800 } }, -- 7
            { points = 1440, free = { kind = "gems", amount = 10 }, premium = { kind = "gems", amount = 40 } }, -- 8
            { points = 1880, free = { kind = "luck", seconds = 600 }, premium = { kind = "luck", seconds = 1800 } }, -- 9
            { points = 2390, free = { kind = "coinBoost", seconds = 600 }, premium = { kind = "item", itemId = "companion_epic_3" } }, -- 10
            { points = 2970, free = { kind = "gems", amount = 10 }, premium = { kind = "gems", amount = 50 } }, -- 11
            { points = 3630, free = { kind = "luck", seconds = 900 }, premium = { kind = "coinBoost", seconds = 1800 } }, -- 12
            { points = 4370, free = { kind = "coinBoost", seconds = 900 }, premium = { kind = "gems", amount = 70 } }, -- 13
            { points = 5200, free = { kind = "gems", amount = 10 }, premium = { kind = "luck", seconds = 1800 } }, -- 14
            { points = 6110, free = { kind = "luck", seconds = 900 }, premium = { kind = "coinBoost", seconds = 1800 } }, -- 15
            { points = 7110, free = { kind = "coinBoost", seconds = 900 }, premium = { kind = "gems", amount = 60 } }, -- 16
            { points = 8200, free = { kind = "gems", amount = 15 }, premium = { kind = "luck", seconds = 1800 } }, -- 17
            { points = 9390, free = { kind = "luck", seconds = 900 }, premium = { kind = "gems", amount = 90 } }, -- 18
            { points = 10680, free = { kind = "coinBoost", seconds = 900 }, premium = { kind = "luck", seconds = 3600 } }, -- 19
            { points = 12000, free = { kind = "gems", amount = 20 }, premium = { kind = "item", itemId = "toolVariant_epic_3" } }, -- 20
        },
    },
}

return {
    bySeason = bySeason,
}
