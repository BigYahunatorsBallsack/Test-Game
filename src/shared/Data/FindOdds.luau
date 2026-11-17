--!strict
-- Fundquoten (Konzept: Tabelle der Fundstück-Stufen) in Hundertstel-Prozent:
-- 10000 = 100 %. Jede Quotentabelle unter `tables` muss 10000 ergeben (DataCheck
-- prüft alle Einträge automatisch). Neue Tabellen einfach unter `tables` ergänzen.
-- Kein Kauf verändert diese Quoten.

export type OddsTable = { [string]: number } -- Seltenheits-ID -> Hundertstel-Prozent

local tables: { [string]: OddsTable } = {
    base = {
        common = 7000, -- 70 %
        uncommon = 2200, -- 22 %
        rare = 600, -- 6 %
        epic = 160, -- 1,6 %
        legendary = 35, -- 0,35 %
        mythic = 5, -- 0,05 %
    },
}

return {
    tables = tables,

    -- Fundchance pro Sekunde Sammeln (Hundertstel-Prozent pro Sekunde) in Zone 1.
    findChancePerSecond = 200,

    -- Faktor auf die Fundchance je Zone (Hundertstel: 10000 = x1).
    zoneFindChanceFactor = {
        dunes = 10000,
        oasis = 12000,
        canyon = 14000,
        salt_lake = 16000,
        ruins = 20000,
    } :: { [string]: number },

    -- Grundwert eines Fundstücks in Münzen. Formel (docs/balance/phase0_startwerte.md):
    -- Wert = findBaseValue × Preisfaktor der Sandsorte × Grundrate des Werkzeugs (ohne Knoten-Boni)
    --        × Wertfaktor der Seltenheit. Der Server schreibt den Wert beim Fund fest.
    findBaseValue = 3,
}
