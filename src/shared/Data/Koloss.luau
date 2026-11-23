--!strict
-- Server-Event "Der Koloss" (Paket 5.6). Die Regeln stehen in Logic/Koloss (Lune-Tests in
-- tests/koloss.spec.luau), DataCheck.checkKoloss prüft die Tabelle beim Serverstart.
--
--  * `window`: wann das Event läuft. Es liegt in der Woche der Saison-Phase `phaseId`, ab `startDay`
--    (0 = Montag, 5 = Samstag) 0 Uhr UTC für `days` Tage. Saison 1: Samstag und Sonntag der Woche 2.
--  * `targetSeconds`: Grabsekunden aller Spieler eines Servers in der Event-Zone bis 100 %.
--    6.000 Sekunden sind 100 Spielerminuten: allein 100 Minuten, zehn Spieler je 10 Minuten.
--  * `tiers`: Belohnung nach eigenem Beitrag (Sekunden), aufsteigend nach `minSeconds`. Es gilt je
--    Spieler die höchste erreichte Stufe. `fairShare` (optional, 0 bis 1) macht die Schwelle relativ zur
--    Zahl der Gräber: Die Schwelle ist höchstens `fairShare` mal dem gleichen Anteil am Ziel
--    (targetSeconds / Zahl der Gräber). So bleibt "Stark" (1,0) mit vielen Gräbern erreichbar, wer
--    überdurchschnittlich gräbt, und allein oder zu zweit gilt nur `minSeconds`. Feste Belohnungen, nie Kisten oder Zufall: "gems" (amount),
--    "coinBoost" und "luck" (seconds). Zum Vergleich: Saison-Pass und Event-Kiste kosten je 400 Gems.

return {
    window = { phaseId = "koloss", startDay = 5, days = 2 },
    targetSeconds = 6000,
    tiers = {
        { id = "joined", name = "Dabei", minSeconds = 0, rewards = { { kind = "coinBoost", seconds = 900 } } },
        { id = "dug", name = "Mitgegraben", minSeconds = 300, fairShare = 0.5, rewards = { { kind = "gems", amount = 20 }, { kind = "luck", seconds = 900 } } },
        {
            id = "strong",
            name = "Stark beteiligt",
            minSeconds = 900,
            fairShare = 1,
            rewards = { { kind = "gems", amount = 50 }, { kind = "coinBoost", seconds = 1800 }, { kind = "luck", seconds = 1800 } },
        },
    },
}
