--!strict
-- Schalter für ganze Systeme (Überarbeitung Ü1, docs/overhaul-plan.md Abschnitt 5.3).
-- Ein ausgeschaltetes System bleibt im Code und in den Spielständen. Es wird nur nicht angeboten:
--   * Server: Der Service bekommt Init, aber kein Start (statt Start läuft `StartDisabled`, falls der
--     Service eins hat). Remotes des Systems bekommen keinen Handler (Net.on überspringt sie).
--   * Kauf-Handler bleiben IMMER registriert (Init oder StartDisabled), damit ein offener Kauf auch bei
--     ausgeschaltetem System gutgeschrieben wird.
--   * Client: Die Controller des Systems werden nicht geladen.
-- Die Regeln stehen in Logic/Features, DataCheck prüft diese Tabelle.

local Features = {
    -- System-ID -> an (true) oder aus (false).
    systems = {
        -- Kern, immer an
        workshop = true, -- Werkstatt (Skilltree)
        collection = true, -- Sammlung
        sandstorm = true, -- Sandsturm (Prestige)
        shop = true, -- Kisten, Gems, Gamepasses, Ausrüstung
        -- Bis zum Fun-Test aus (Ü11 schaltet sie einzeln wieder an)
        offers = false, -- Angebote (Starterpaket-Hinweis)
        daily = false, -- Daily Reward
        codes = false, -- Codes
        seasonPass = false, -- Saison-Pass
        eventZone = false, -- Event-Zone der Saison und Saison-Takt
        koloss = false, -- Server-Event "Der Koloss"
        social = false, -- Freunde-Bonus, Rangliste, Sammlung besuchen
        offline = false, -- Offline-Begleiter
    } :: { [string]: boolean },

    -- Server-Service -> System. Services ohne Eintrag laufen immer.
    services = {
        Offers = "offers",
        Daily = "daily",
        Codes = "codes",
        SeasonPasses = "seasonPass",
        Events = "eventZone",
        Koloss = "koloss",
        Friends = "social",
        Leaderboard = "social",
        Offline = "offline",
    } :: { [string]: string },

    -- Client-Controller -> System. Controller ohne Eintrag laufen immer.
    controllers = {
        OfferHint = "offers",
        Daily = "daily",
        Codes = "codes",
        SeasonPassMenu = "seasonPass",
        KolossBar = "koloss",
        SocialMenu = "social",
        OfflineCard = "offline",
    } :: { [string]: string },

    -- Client->Server-Remote -> System. Remotes ohne Eintrag gehören zum Kern.
    remotes = {
        ClaimDaily = "daily",
        RedeemCode = "codes",
        BuySeasonPass = "seasonPass",
        ClaimSeasonReward = "seasonPass",
        GetLeaderboard = "social",
        GetFriends = "social",
        ViewCollection = "social",
    } :: { [string]: string },

    -- Menüknöpfe, die nicht in der Leiste stehen, sondern im Fenster "Shop" (ein Knopf statt drei).
    shop = {
        buttonId = "ShopButton",
        title = "Shop",
        members = { "CratesButton", "GemsButton", "EquipmentButton" },
    },
}

return Features
