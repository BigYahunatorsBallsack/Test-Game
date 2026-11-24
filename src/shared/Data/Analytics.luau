--!strict
-- Analytics (Paket 6.3): Namen der Ereignisse und Grenzen. Die Regeln stehen in Logic/Analytics (Lune-Tests
-- tests/analytics.spec.luau). Gesendet wird über AnalyticsService (Service Analytics), nie vom Client, nie
-- mit Spielernamen. Auswertung im Creator Dashboard (Analytics).

return {
    events = {
        sessionStart = "session_start", -- Custom Event: Rückkehr (neu oder Tage seit dem letzten Besuch)
        sessionEnd = "session_end", -- Custom Event: Sitzungslänge in Eimern
    },
    onboardingDoneName = "done", -- Name des letzten Trichter-Schritts (Tutorial fertig)
    currencyName = "Gems", -- Währung der Wirtschafts-Ereignisse
    newPlayerSeconds = 120, -- so jung (Sekunden seit Anlage des Profils) gilt ein Spieler als neu
    maxReturnDays = 30, -- Tage seit dem letzten Besuch werden hier gedeckelt
    maxFieldLength = 100, -- längster Text in einem Zusatzfeld
    tickSeconds = 5, -- Takt, der Tutorial-Schritt und neue Käufe erkennt
    logInStudio = false, -- in Studio nur ins Ausgabefenster schreiben, nichts senden
    sessionBuckets = {
        { maxSeconds = 60, name = "lt_1m" },
        { maxSeconds = 300, name = "1_5m" },
        { maxSeconds = 900, name = "5_15m" },
        { maxSeconds = 1800, name = "15_30m" },
        { maxSeconds = 3600, name = "30_60m" },
        { maxSeconds = math.huge, name = "gt_60m" },
    },
}
