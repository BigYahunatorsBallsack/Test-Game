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

-- Käufe und Gems (Paket 4.1), siehe Logic/Purchases und Logic/Gems.
export type PurchasesConfig = {
    receiptCacheSize: number, -- so viele PurchaseIds merkt sich das Profil (die neuesten)
    purchaseLogSize: number, -- so viele Einträge hält das Kaufprotokoll im Profil
    saveTimeoutSeconds: number, -- so lange wartet ein Kauf höchstens auf das bestätigte Speichern
    maxGems: number, -- Obergrenze des Gem-Stands (Schutz gegen kaputte Werte und Überlauf)
}

-- Kisten-Items (Paket 4.3), siehe Logic/Equipment.
export type ItemsConfig = {
    maxStars: number, -- höchster Stern (★1 = Grundwert, jedes Item startet bei ★1)
    starBonusBp: number, -- je Stern über ★1: so viel vom Grundwert (effectBp) kommt dazu
    copiesToMerge: { number }, -- Kopien, die der Schritt auf ★2, ★3, ... verbraucht (Index = Zielstern - 1)
    maxEffectBp: number, -- Obergrenze für effectBp (★1) je Item, prüft DataCheck
    maxTotalBonusBp: number, -- Deckel für die Summe aller Item-Boni (Equipment.bonusBp), prüft DataCheck
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

    -- Sandsturm (Paket 2.7). Kristalle = floor(crystalScale x (runEarned / crystalUnit) ^ crystalExponent),
    -- runEarned = Münzen aus Verkäufen seit dem letzten Sturm. `requiresNode`: Knoten, ab dem der Sturm
    -- möglich ist (Canyon frei). `minCrystals`: so viele muss der Lauf mindestens bringen.
    -- `maxCrystals`: Obergrenze der gehaltenen Kristalle (Schutz gegen Überlauf), erst bei etwa
    -- 3,9 x 10^23 Münzen im Lauf erreicht.
    -- Werte vom balance-analyst, Begründung und Simulation: docs/balance/sandstorm_2_7.md.
    -- Exponent 0,25 statt 0,5: Bei 0,5 lohnt es sich, nach dem Baumende ohne Kauf weiterzusammeln.
    -- minCrystals 20: erreicht etwa 3,5 min vor dem Baumende von Lauf 1, ein früher Sturm lohnt nie.
    sandstorm = {
        requiresNode = "collect_tool_4",
        crystalUnit = 1_000_000,
        crystalExponent = 0.25,
        crystalScale = 4,
        minCrystals = 20,
        maxCrystals = 100_000,
    },

    -- Käufe (Paket 4.1). PurchaseGranted gibt es erst, wenn die PurchaseId im gespeicherten Stand
    -- steht. Roblox wiederholt unbestätigte Käufe, dafür merkt sich das Profil die letzten
    -- `receiptCacheSize` PurchaseIds (älteste fliegen zuerst raus). Das Kaufprotokoll ist nur für
    -- den Support und hält die letzten `purchaseLogSize` Käufe. `saveTimeoutSeconds`: Wartezeit auf
    -- das Speichern, danach NotProcessedYet. `maxGems`: höchster Gem-Stand, darüber wird gekappt.
    -- maxGems nie senken, sonst kappt sanitize beim nächsten Laden oder Speichern bezahlte Guthaben
    -- (DataCheck verlangt mindestens 1_000_000). receiptCacheSize nie unter 50 und nie unter
    -- purchaseLogSize (DataCheck prüft beides).
    purchases = {
        receiptCacheSize = 100,
        purchaseLogSize = 50,
        saveTimeoutSeconds = 30,
        maxGems = 10_000_000,
    } :: PurchasesConfig,

    -- Kisten-Items (Paket 4.3): Ausgerüstete Items erhöhen die Sammelrate (eigener Faktor neben dem
    -- Baum). Item-Grundwert (`effectBp`) steht in Data/CrateItems. Verschmelzen: Der Schritt auf ★n
    -- verbraucht `copiesToMerge[n - 1]` Kopien, ein Exemplar bleibt immer. ★5 = 1 + 4 x 15 % = 1,6-facher
    -- Grundwert. Startwerte, geprüft vom balance-analyst (docs/balance/equipment_4_3.md).
    items = {
        maxStars = 5,
        starBonusBp = 1500,
        copiesToMerge = { 1, 2, 3, 4 },
        maxEffectBp = 2500,
        -- Drei Mythische ★5 ergeben 12.000 (+120 %). Der Deckel fängt Tippfehler in den Tabellen ab.
        maxTotalBonusBp = 12000,
    } :: ItemsConfig,

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
