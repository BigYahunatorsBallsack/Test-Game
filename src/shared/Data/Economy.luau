--!strict
-- Wirtschaftswerte, die nicht zu Werkzeugen, Zonen oder Kisten gehören.
-- Quoten und Boni in Hundertstel-Prozent ("Bp"): 10000 = 100 %, 200 = 2 %.
-- Die Balance-Startwerte (Grundpreis, Tank, Daily Reward) stammen aus
-- docs/balance/phase0_startwerte.md.

-- Eine Belohnung der Daily Reward (Paket 5.1, Logic/Daily). Je Art nur diese Felder (DataCheck):
--   "coinBoost" { day, kind, seconds }  2x-Münzen-Boost (Economy.coinBoost.multiplier), verlängert boosts.coinsUntil
--   "luck"      { day, kind, seconds }  Glücks-Boost (Economy.luckBoost.multiplier), verlängert boosts.luckUntil
--   "gems"      { day, kind, amount }   Gems, gekappt bei purchases.maxGems
--   "crate"     { day, kind, crateId }  nur Tag 7: Kiste gratis (bei gesperrten Zufallsitems day7FallbackItemId)
export type DailyReward = {
    day: number,
    kind: "coinBoost" | "luck" | "gems" | "crate",
    amount: number?, -- nur bei "gems": ganze Zahl über 0
    seconds: number?, -- nur bei "coinBoost" und "luck": ganze Sekunden über 0
    crateId: string?, -- nur bei "crate": Kiste aus Data/Crates
}

-- Käufe und Gems (Paket 4.1), siehe Logic/Purchases und Logic/Gems.
export type PurchasesConfig = {
    receiptCacheSize: number, -- so viele PurchaseIds merkt sich das Profil (die neuesten)
    purchaseLogSize: number, -- so viele Einträge hält das Kaufprotokoll im Profil
    saveTimeoutSeconds: number, -- so lange wartet ein Kauf höchstens auf das bestätigte Speichern
    maxGems: number, -- Obergrenze des Gem-Stands (Schutz gegen kaputte Werte und Überlauf)
}

-- Direktkauf (Paket 4.6), siehe Logic/DirectShop.
export type DirectShopConfig = {
    roundSignificantDigits: number, -- Preis auf so viele gültige Stellen aufgerundet (1 bis 4)
    monotoneFloor: boolean, -- Preis mindestens der Einstiegspreis jeder niedrigeren Seltenheit
    crates: { string }, -- Gem-Kisten, aus denen der Preis gerechnet wird (nie Münz- oder Event-Kisten)
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

    -- Faktor auf die Tankgröße durch den Gamepass "Großer Tank" (Wirkung "bigTank", Paket 4.4).
    bigTankMultiplier = 2,

    -- Faktor auf alle Münzen aus Verkäufen durch den Gamepass "2x Münzen" (Wirkung "doubleCoins",
    -- Paket 4.4). Er wirkt auf den Preis pro Sand und damit auf Verkauf, Tankwert und die
    -- Sandsturm-Vorschau. Mit dem Münz-Boost (coinBoost) zusammen wird multipliziert (2 x 2 = 4-fach,
    -- so entschieden). Fundwerte und verkaufte Duplikate bleiben unberührt.
    doubleCoinsMultiplier = 2,

    -- Sandsturm: jeder Windkristall gibt +2 % auf alle Münzen (Startwert, Konzept).
    windCrystalBonusBp = 200,

    -- Sandsturm (Paket 2.7). Kristalle = floor(crystalScale x (runEarned / crystalUnit) ^ crystalExponent),
    -- runEarned = Münzen aus Verkäufen seit dem letzten Sturm. `requiresNode`: Knoten, ab dem der Sturm
    -- möglich ist (Canyon frei). `minCrystals`: so viele muss der Lauf mindestens bringen.
    -- `maxCrystals`: Obergrenze der GEHALTENEN Kristalle (Schutz gegen Überlauf). Bei 100.000 war ab etwa
    -- 35 h aktiv kein Sturm mehr möglich (Gewinn unter minCrystals), darum 5 Mio. (Paket 6.4,
    -- docs/balance-6.4.md). Mehr erlaubt DataCheck bei 200 bp nicht (maxCrystals x bp <= 10^9).
    -- Werte vom balance-analyst, Begründung und Simulation: docs/balance/sandstorm_2_7.md.
    -- Exponent 0,25 statt 0,5: Bei 0,5 lohnt es sich, nach dem Baumende ohne Kauf weiterzusammeln.
    -- minCrystals 20: erreicht etwa 3,5 min vor dem Baumende von Lauf 1, ein früher Sturm lohnt nie.
    sandstorm = {
        requiresNode = "collect_tool_4",
        crystalUnit = 1_000_000,
        crystalExponent = 0.25,
        crystalScale = 4,
        minCrystals = 20,
        maxCrystals = 5_000_000,
        -- Hinweis "Sturm lohnt sich" (Paket 6.4, L2): Der billigste sichtbare Knoten kostet mehr als so
        -- viele Sekunden Verdienst bei der jetzigen Rate.
        worthSeconds = 180,
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

    -- Direktkauf (Paket 4.6): Nur bei gesperrten oder unbekannten Zufallsitems
    -- (ArePaidRandomItemsRestricted) kauft man Kisten-Items fest gegen Gems. Preis = Erwartungswert:
    -- Einzelpreis der Kiste / Wahrscheinlichkeit genau dieses Items je Öffnung (mit Pity), die
    -- günstigste Kiste aus `crates` zählt, aufgerundet auf `roundSignificantDigits` gültige Stellen.
    -- `monotoneFloor`: Seltenheiten nach Rang, der Preis ist mindestens der Einstiegspreis (billigstes
    -- Item) jeder niedrigeren Seltenheit (hebt nur an). Event-Items haben nie einen Preis.
    -- Werte und Begründung: docs/balance/directshop_4_6.md (balance-analyst).
    directShop = {
        roundSignificantDigits = 2,
        monotoneFloor = true,
        crates = { "iron", "gold" },
    } :: DirectShopConfig,

    -- Freunde-Bonus: 10 % mehr Münzen pro Freund im Server, höchstens 50 %.
    friendBonusPerFriendBp = 1000,
    friendBonusMaxBp = 5000,

    -- Offline-Ertrag: der Begleiter sammelt bis zu 4 Stunden, mit Auto-Dig bis zu 12 Stunden.
    offline = {
        baseHours = 4,
        autoDigHours = 12,
        -- Offline-Ertrag (Paket 5.3): Anteil der Online-Sammelrate, den der Begleiter schafft (0 bis 1,
        -- Vorschlag 50 %), und die kürzeste Abwesenheit, ab der es etwas gibt (Sekunden).
        rateFactor = 0.5,
        minSeconds = 300,
        -- Offline-Erträge enthalten keine Fundstücke ab dieser Seltenheit (seit 5.3 gar keine: nur Münzen).
        noFindsFromRarityId = "rare",
    },

    -- Münz-Boost (Verbrauchsprodukt "coin_boost", Paket 4.4): 30 Minuten, doppelte Münzen. Die Zeit
    -- läuft in echter Zeit (Unix, auch offline), jeder Kauf verlängert um durationSeconds ab der
    -- alten Endzeit (oder ab jetzt, wenn abgelaufen). Keine Obergrenze für gestapelte Zeit.
    coinBoost = {
        durationSeconds = 30 * 60,
        multiplier = 2,
    },

    -- Zielzeiten der ersten Minuten (Konzept: "Die ersten 2 Minuten").
    targetSeconds = {
        firstUpgrade = 20,
        shovel = 120,
    },

    -- Glücks-Boost (Daily Reward Tag 5, Paket 5.1): Faktor auf die Fundchance aus dem Sand, solange
    -- boosts.luckUntil nach der Server-Uhr (Unix) liegt. Er ändert nur die Chance, dass ein Fund fällt,
    -- nie die Verteilung der Seltenheiten und nie Kisten (Logic/FindRoll, Logic/Perks).
    luckBoost = {
        multiplier = 2,
    },

    -- Daily Reward (Paket 5.1, Logic/Daily): 7-Tage-Serie nach UTC-Kalendertagen. Tag 7 gibt eine
    -- Eisenkiste gratis. Bei gesperrten oder unbekannten Zufallsitems gibt es stattdessen ein festes
    -- Ausrüstungsstück (day7FallbackItemId). Werte: docs/balance/phase0_startwerte.md.
    daily = {
        -- Die Serie startet erst nach dem Kauf der Schaufel (Knoten aus UpgradeTree, DataCheck prüft
        -- ihn). Nach einem Sandsturm gilt sie immer als gestartet, auch ohne diesen Knoten.
        startNodeId = "collect_tool_2",
        days = {
            { day = 1, kind = "coinBoost", seconds = 10 * 60 },
            { day = 2, kind = "gems", amount = 5 },
            { day = 3, kind = "coinBoost", seconds = 15 * 60 },
            { day = 4, kind = "gems", amount = 10 },
            { day = 5, kind = "luck", seconds = 15 * 60 },
            { day = 6, kind = "gems", amount = 20 },
        } :: { DailyReward },
        day7 = { day = 7, kind = "crate", crateId = "iron" } :: DailyReward,
        -- Festes Ersatz-Item bei gesperrten Zufallsitems: Kupferschaufel, gleichwertig zur Eisenkiste
        -- (docs/balance/directshop_4_6.md, "Tag 7"). DataCheck: bekanntes Item, kein Event-Item.
        day7FallbackItemId = "toolVariant_uncommon_1",
    },

    -- Saison-Pass (Paket 5.5, Logic/SeasonPass, Stufen in Data/SeasonPass). Werte: docs/balance/season_5_5.md.
    seasonPass = {
        -- Je so viele Sekunden Graben in der Event-Zone (vom Server gezählt) gibt es einen Saison-Punkt.
        secondsPerPoint = 10,
        -- So viele Tage nach dem Saisonende lassen sich Belohnungen noch abholen (5.5b).
        claimGraceDays = 3,
        -- Ersatz-Gems, wenn ein zweiter Pass derselben Saison bezahlt wird (5.5b).
        duplicateGems = 850, -- Gem-Gegenwert von 399 Robux (beste Paketkombination), docs/balance/season_5_5.md
        -- Höchstanteil der Premium-Gems am Gem-Gegenwert des Pass-Preises (Kurs des kleinsten Pakets), in
        -- Prozent. DataCheck prüft die Summe aller Premium-Gems dagegen: der Pass ist kein Gem-Rabatt.
        premiumGemsMaxPercent = 50,
    },
}

return Economy
