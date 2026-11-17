--!strict
-- Wirtschaftswerte, die nicht zu Werkzeugen, Zonen oder Kisten gehören.
-- Quoten und Boni in Hundertstel-Prozent ("Bp"): 10000 = 100 %, 200 = 2 %.
-- Die Balance-Startwerte (Grundpreis, Tank, Daily Reward) stammen aus
-- docs/balance/phase0_startwerte.md.

export type DailyReward = {
    day: number,
    kind: "coins" | "gems" | "boost" | "crate" | "fixedItem",
    amount: number,
    crateId: string?,
    itemId: string?,
    boostId: ("coins2x" | "luck2x")?, -- nur bei kind = "boost"
    durationSeconds: number?, -- nur bei kind = "boost"
}

local Economy = {
    -- Grundpreis pro Sand in Münzen; der Preisfaktor der Sandsorte (SandTypes) multipliziert ihn.
    baseCoinsPerSand = 1,

    -- Tankgröße am Anfang (Sand).
    startTankCapacity = 15,

    -- Sammeln (Paket 1.2): Der Client schickt SetCollecting(true) alle `holdRefreshSeconds`,
    -- solange die Taste gehalten wird. Kommt länger als `holdTimeoutSeconds` nichts, zählt
    -- der Server nur die Zeit bis zur Frist (verlorene Verbindung, hängender Client).
    collecting = {
        holdRefreshSeconds = 1,
        holdTimeoutSeconds = 2.5,
    },

    -- Faktor auf die Tankgröße durch den Gamepass "Großer Tank".
    bigTankMultiplier = 2,

    -- Sandsturm: jeder Windkristall gibt +2 % auf alle Münzen (Startwert, Konzept).
    windCrystalBonusBp = 200,

    -- Freunde-Bonus: 10 % mehr Münzen pro Freund im Server, höchstens 50 %.
    friendBonusPerFriendBp = 1000,
    friendBonusMaxBp = 5000,

    -- Offline-Ertrag: der Begleiter sammelt bis zu 4 Stunden, mit Auto-Dig bis zu 12 Stunden.
    offline = {
        baseHours = 4,
        autoDigHours = 12,
        -- Offline-Erträge enthalten keine Fundstücke ab dieser Seltenheit.
        noFindsFromRarityId = "rare",
    },

    -- Münz-Boost (Verbrauchsprodukt): 30 Minuten, doppelte Münzen.
    coinBoost = {
        durationSeconds = 30 * 60,
        multiplier = 2,
    },

    -- Zielzeiten der ersten Minuten (Konzept: "Die ersten 2 Minuten").
    targetSeconds = {
        firstUpgrade = 20,
        shovel = 120,
    },

    -- Daily Reward: 7-Tage-Serie. Tag 7 gibt eine Eisenkiste gratis. In Regionen mit
    -- gesperrten Zufallsitems gibt es stattdessen ein festes Ausrüstungsstück.
    daily = {
        -- Die Serie startet erst nach dem Kauf der Schaufel (docs/balance/phase0_startwerte.md).
        days = {
            { day = 1, kind = "boost", boostId = "coins2x", durationSeconds = 600, amount = 1 },
            { day = 2, kind = "gems", amount = 5 },
            { day = 3, kind = "boost", boostId = "coins2x", durationSeconds = 900, amount = 1 },
            { day = 4, kind = "gems", amount = 10 },
            { day = 5, kind = "boost", boostId = "luck2x", durationSeconds = 900, amount = 1 },
            { day = 6, kind = "gems", amount = 20 },
        } :: { DailyReward },
        day7 = { day = 7, kind = "crate", amount = 1, crateId = "iron" } :: DailyReward,
        -- TODO(content): festes Ersatz-Ausrüstungsstück festlegen (ID aus den Kisten-Inhalten, Paket 4.3).
        day7FallbackItemId = "daily_fallback_item",
    },
}

return Economy
