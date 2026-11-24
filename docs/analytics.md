# Analytics (Paket 6.3)

Der Service `Analytics` (Server, ganz am Ende von `SERVICE_NAMES`) schickt vier Arten von Ereignissen an `AnalyticsService`. Er liest nur das Profil, ändert nichts und hat keine Remote. Namen und Grenzen stehen in `Data/Analytics`, die Regeln in `Logic/Analytics` (Tests `tests/analytics.spec.luau`). Es werden nie Spielernamen gesendet. In Studio wird nur ins Ausgabefenster geschrieben (`logInStudio = false`).

## Was gemessen wird und wo man es sieht

Creator Dashboard, dein Spiel, Analytics. Neue Ereignisse erscheinen mit einigen Stunden Verzögerung.

| Frage | Ereignis | Wo im Dashboard |
| --- | --- | --- |
| Wo brechen neue Spieler ab? | Trichter "Onboarding": Schritt 1 `collect`, 2 `sell`, 3 `firstUpgrade`, 4 `shovel`, 5 `done` (Namen aus `Data/Tutorial`) | Analytics, Funnels (Onboarding) |
| Was wird gekauft? | Wirtschaft: Quelle "Gems" über IAP, Artikel = Produkt-ID, Menge = Gems | Analytics, Economy |
| Wie lange spielt man? | Custom Event `session_end`, Wert = Sekunden, Feld `bucket` (`lt_1m`, `1_5m`, `5_15m`, `15_30m`, `30_60m`, `gt_60m`) | Analytics, Custom Events |
| Wer kommt zurück? | Custom Event `session_start`, Wert = Tage seit dem letzten Besuch (0 bis 30), Feld `isNew` (`yes` oder `no`); dazu die eingebaute Rückkehr-Kennzahl von Roblox | Analytics, Custom Events und Retention |

## Hinweise

- Der Trichter zählt nur Spieler, die beim Beitritt das Tutorial noch nicht fertig hatten. Ein Schritt wird je Sitzung einmal gemeldet.
- Käufe werden nach der PurchaseId erkannt (je Sitzung einmal). Beim Laden vorhandene Käufe werden nicht noch einmal gemeldet.
- Die Sitzungslänge ist die Zeit im Server (nicht die Zeit ohne Pause).
- Neue Ereignisse brauchen nur eine Zeile in `Data/Analytics` (Namen) und eine Regel in `Logic/Analytics`.
