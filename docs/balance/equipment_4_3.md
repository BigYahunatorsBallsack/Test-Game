# Paket 4.3: Kisten-Items wirken auf die Sammelrate

Stand 19.11.2026, Paket 4.3, `balance-analyst`. Das Skript steht in `docs/balance/equipment_4_3.py` (nur Standardbibliothek, Aufruf `python3 docs/balance/equipment_4_3.py`, Laufzeit etwa 95 s, feste Seeds ab 4300). Es liest Quoten und Pools direkt aus `Crates.luau` und `CrateItems.luau` und nimmt Baum und Schleife aus `skilltree_2_1.py`. Code und Daten wurden nicht geändert.

## Ergebnis

Die Grundwerte (5 bis 25 % je Item) und der Sternschritt (+15 %) passen: Selbst das theoretische Maximum von +120 % (Rate x2,2) verkürzt Lauf 1 nur um 25 %, 2x Münzen (399 Robux) um 46 %. Die Items sind also klar schwächer als der Gamepass und weit unter dem Baum (x12,25). Ein Spieler hat nach 10, 50 und 200 Gold-Öffnungen im Median +38 %, +56 % und +72 % (P90 47 %, 63 %, 76 %), nach 100 Holzkisten +26 % und nach 100 Eisenkisten +45 %. Drei Werte passen nicht. **(1) Die Holzkiste ist ab dem Saugroboter in Lauf 1 (11:52 min) praktisch gratis.** Der Holz-Deckel von +44,8 % (Episch ★5 in Skin und Begleiter, Holz hat keine Werkzeug-Variante) kostet 81 Mio. Münzen, das sind 10 s Ertrag am Baumende oder 7 min Klicken. Weil der Sandsturm die Münzen ohnehin löscht, hat praktisch jeder Spieler nach dem ersten Lauf +44,8 %. Ein mitwachsender Preis hilft kaum, weil die Münzen in einem Lauf um 7 Zehnerpotenzen wachsen. Ein Tageslimit hilft. **(2) Das Maximum ist unerreichbar:** 3 Mythische ★5 kosten im Mittel 7.707 Goldkisten, also 2,8 Mio. Gems oder etwa 1,0 Mio. Robux. Schon ein Mythisch ★2 braucht im Mittel 1.114 Öffnungen. **(3) Die Kopienzahlen 1, 2, 3, 4** sind bei Gewöhnlich egal, weil Gewöhnlich ★5 (8 %) schwächer ist als Selten ★1 (10 %) und das Item ohnehin ersetzt wird. Bei Mythisch sind die Sterne praktisch tot. Ich schlage deshalb eine Kopientabelle je Seltenheit vor (Legendär 1, 2, 2, 3 und Mythisch 1, 1, 2, 2). Als Kaufanreiz ist Gold schwach: Auf dem Holz-Deckel bringen 50 Goldkisten (etwa 6.500 Robux) nur +19 Prozentpunkte, also etwa 5 % kürzere Läufe. Der Kaufanreiz muss also aus Optik und Sammlung kommen, nicht aus der Rate. Das ist für die Policy eher gut.

## Annahmen

- **Formel (Entwurf):** Rate = Werkzeug x (1 + Baum) x (1 + Summe der drei Slot-Boni). Bonus = Grundwert x (1 + 0,15 x (Sterne - 1)). Grundwerte: Gewöhnlich 5, Ungewöhnlich 7, Selten 10, Episch 14, Legendär 19, Mythisch 25 %. Exemplare für ★1 bis ★5: 1, 2, 4, 7, 11.
- **Spieler:** Er verschmilzt sofort und optimal und rüstet je Slot das Item mit dem höchsten Bonus aus. Überzählige Kopien haben keinen Nutzen.
- **Würfeln wie `CrateRoll`:** Erst die Seltenheit, dann gleichverteilt im Pool der Kiste. Gold mit Pity 15/60 ab frischem Zähler (Regeln wie in `crates_4_2.md`). Pools: Holz je 3 Items je Seltenheit (8 Skins, 4 Begleiter, **0 Werkzeug-Varianten**), Eisen je 4, Gold 4/5/4/3/3 (Ungewöhnlich bis Mythisch), Legendär und Mythisch je genau ein Item pro Slot.
- **Kosten:** 10er-Paket, also 363,6 Gems je Gold-Öffnung, 90,9 Gems je Eisen-Öffnung und 22.727 Münzen je Holz-Öffnung. Robux zum besten Gem-Paket: 7.000 Gems für 2.499 Robux, also 0,357 Robux je Gem.
- **Lauf 1:** wie in 2.1 und 2.7 (ohne Tore, Glück-Ast gekauft, 5 s Weg je Richtung, billigster sichtbarer Knoten). Der Item-Faktor wirkt nur auf die Sammelrate.
- Monte Carlo mit 20.000 Versuchen (Holz 3.000: 4.000 Versuche). Die Meilensteine in (b) laufen über Legendär+-Zyklen mit exakter Zykluslängen-Verteilung (Mittel 18,564 wie in 4.2).

## (a) Gesamtbonus nach N Öffnungen

| Kiste, Öffnungen | Kosten | Median | P10 | P90 | Typisch ausgerüstet |
| --- | --- | --- | --- | --- | --- |
| Gold 10 | 3.636 Gems (etwa 1.300 Robux) | **38,0 %** | 30,0 % | 47,0 % | Selten und Episch, 14 % je Slot Legendär |
| Gold 11 (1 Paket) | 4.000 Gems | 39,0 % | 31,5 % | 48,0 % | wie oben |
| Gold 50 | 18.182 Gems (etwa 6.500 Robux) | **55,6 %** | 49,1 % | 63,0 % | 50 % Legendär, 8 % Mythisch je Slot |
| Gold 200 | 72.727 Gems (etwa 26.000 Robux) | **71,5 %** | 66,8 % | 75,6 % | 52 bis 58 % Legendär, 29 % Mythisch je Slot |
| Holz 100 | 2,5 Mio. Münzen | **26,0 %** | 23,1 % | 28,5 % | Selten oder Episch, Werkzeug-Slot leer |
| Holz 1.000 | 25 Mio. Münzen | 34,3 % | 32,2 % | 36,4 % | Episch ★1 bis ★2 |
| Holz 3.000 | 75 Mio. Münzen | 42,7 % | 40,6 % | 44,8 % | Episch ★4 bis ★5 |
| Eisen 100 | 9.091 Gems | **44,6 %** | 41,5 % | 48,3 % | meist Episch in allen drei Slots |
| Eisen 1.000 | 90.909 Gems | 65,1 % | 63,0 % | 67,2 % | Episch ★4 bis ★5 (Deckel 67,2 %) |
| Gold 10 auf Holz-Deckel | 3.636 Gems | 56,3 % | 51,8 % | 63,8 % | Holz-Epics bleiben, Gold füllt den Werkzeug-Slot |
| Gold 50 auf Holz-Deckel | 18.182 Gems | 63,8 % | 58,8 % | 69,2 % | |
| Gold 200 auf Holz-Deckel | 72.727 Gems | 72,1 % | 68,7 % | 75,8 % | Der Holz-Deckel ist hier fast bedeutungslos |

## (b) Maximum und Verhältnis zu Baum und Gamepässen

| Meilenstein Goldkiste | Öffnungen Mittel (Median, P90) | Gems (Paket) | Robux |
| --- | --- | --- | --- |
| Erstes Mythisch (beliebig) | 188 (133, 427) | 68.213 | 24.352 |
| Alle 3 Legendär ★5 (+91,2 %) | 858 (840, 1.080) | 312.083 | 111.414 |
| Alle 3 Mythisch ★1 (+75 %) | 1.021 (879, 1.873) | 371.397 | 132.589 |
| Ein Mythisch ★5 | 4.623 (4.561, 6.087) | 1.681.151 | 600.171 |
| **Alle 3 Mythisch ★5 (+120 %)** | **7.707 (7.553, 9.842)** | **2.802.690** | **1.000.560** (P90 1,28 Mio.) |

Zum Vergleich: Legendär oder besser kommt nach 18,56 Öffnungen (7.426 Gems einzeln, 6.750 Gems im Paket, aus 4.2, unverändert).

**Wirkung auf Lauf 1** (Prüfpunkte: erstes Upgrade, Pausen, Stillstand, Gamepässe):

| Variante | Upgrade 1 | Schaufel | Eimerkette | Mini-Bagger | Großmaschine | Baumende (Stillstand) | Längste Pause | Läufe unter 15 s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Ohne Items | 20 s | 2:00 | 7:08 | 10:08 | 12:31 | 21:36 | 75 s | 44 % |
| +29 % | 17 s | 1:43 | 6:18 | 8:58 | 11:13 | 19:21 (-10 %) | 65 s | 46 % |
| +44,8 % (Holz-Deckel) | 15 s | 1:37 | 5:59 | 8:31 | 10:44 | 18:30 (-14 %) | 61 s | 54 % |
| +67,2 % (Eisen-Deckel) | 14 s | 1:30 | 5:39 | 8:02 | 10:12 | 17:35 (-19 %) | 57 s | 61 % |
| +91,2 % | 13 s | 1:24 | 5:22 | 7:39 | 9:46 | 16:49 (-22 %) | 54 s | 61 % |
| +120 % (Maximum) | 12 s | 1:19 | 5:07 | 7:17 | 9:22 | 16:08 (-25 %) | 50 s | 64 % |
| 2x Münzen, ohne Items | 20 s | 1:10 | 4:07 | 5:43 | 7:00 | 11:46 (-46 %) | 50 s | 42 % |
| 2x Münzen, +120 % | 12 s | 0:45 | 2:55 | 4:06 | 5:13 | 8:45 (-59 %) | 34 s | 63 % |
| Auto-Dig, ohne Items | 20 s | 1:40 | 5:31 | 7:48 | 9:38 | 17:02 (-21 %) | 61 s | 61 % |
| Auto-Dig, +120 % | 12 s | 1:00 | 3:51 | 5:26 | 7:16 | 12:41 (-41 %) | 40 s | **96 %** |

- **Nicht zu stark:** +120 % ist im Fortschritt etwa halb so stark wie 2x Münzen, weil die Rate nur die Sammelzeit kürzt und die 10 s Weg bleiben. Die Sturm-Kristalle ändern sich nicht, weil `runEarned` am Baumende etwa den Baumkosten entspricht (2.7). Items kürzen also nur die Läufe.
- **Als Kaufanreiz schwach:** Über dem Holz-Deckel bringen 10, 50 und 200 Goldkisten +11,5, +19 und +27 Prozentpunkte, das sind nur etwa 3 bis 6 % kürzere Läufe. Das Maximum ist kein Ziel, das ein Spieler erreicht. Der Shop sollte es nicht bewerben.
- **Nebenwirkung Tank:** Jeder Item-Bonus kürzt die Läufe unter das Band von 15 bis 40 s. Mit dem Holz-Deckel liegen 54 % statt 44 % der Läufe unter 15 s, mit Auto-Dig und +120 % sind es 96 %. Paket 6.4 sollte die Tankgrößen mit etwa +45 % Item-Bonus als Normalfall prüfen.
- **Offen:** Ob der Item-Bonus auch auf den Offline-Ertrag des Begleiters wirkt, ist nicht festgelegt. Die Simulation rechnet ohne.

## (c) Sterne-Kosten je Seltenheit

Erwartete Öffnungen, bis ein **bestimmtes** Item ★2, ★3 oder ★5 erreicht (2, 4 oder 11 Exemplare):

| Kiste, Seltenheit | Rate je Item | ★2 | ★3 | ★5 | Bonus ★1 bis ★5 |
| --- | --- | --- | --- | --- | --- |
| Holz Gewöhnlich | 20 % | 10 | 20 | 55 | 5 bis 8 % |
| Holz Selten | 3 % | 67 | 133 | 367 | 10 bis 16 % |
| Holz Episch | 0,33 % | 600 | 1.200 | 3.300 | 14 bis 22,4 % |
| Gold Ungewöhnlich | 9,9 % | 20 | 40 | 111 | 7 bis 11,2 % |
| Gold Episch | 3,9 % | 52 | 103 | 284 | 14 bis 22,4 % |
| Gold Legendär | 1,6 % | 124 | 248 | 681 | 19 bis 30,4 % |
| Gold Mythisch | 0,18 % | 1.114 | 2.228 | 6.126 | 25 bis 40 % |

- **Gewöhnlich, viele Kopien:** Das ist harmlos. Gewöhnlich ★5 (8 %) liegt unter Selten ★1 (10 %), ein Selten kommt in Holz im Schnitt nach 11 Öffnungen. Die Sterne von Gewöhnlich und Ungewöhnlich wirken also nur in den ersten Minuten, und mehr Kopien würden nichts ändern. Die überzähligen Kopien sind aber nutzlos (eventuell später in eine Verwertung, das ist ein Design-Thema, keine Zahl).
- **Mythisch, kaum Kopien:** Der Engpass ist die Quote (0,54 % auf 3 Items), nicht die Tabelle. Eine Staffelung hilft nur ab ★3, weil ★2 immer eine zweite Kopie braucht:

| Kopientabelle | Ein Item ★5 | Alle 3 ★5 | Robux für alle 3 |
| --- | --- | --- | --- |
| Mythisch 1, 2, 3, 4 (Entwurf, 11 Exemplare) | 4.623 | 7.707 | 1.000.560 |
| **Mythisch 1, 1, 2, 2 (7 Exemplare)** | **2.718** | **5.164** | **670.419** |
| Mythisch 1, 1, 1, 1 (5 Exemplare) | 1.805 | 3.862 | 501.302 |
| Legendär 1, 2, 3, 4 (Entwurf), alle 3 ★5 | - | 858 | 111.414 |
| **Legendär 1, 2, 2, 3 (9 Exemplare), alle 3 ★5** | - | **720** | **93.449** |

Eine Tabelle je Seltenheit lohnt sich, vor allem weil der Testfall "Sterne skalieren nach der Tabelle in `Economy.items`" die Datenform jetzt festlegt. Eine spätere Umstellung auf eine Tabelle je Seltenheit wäre ein neues Datenschema.

## (d) Holzkiste (25.000 Münzen)

| Zeitpunkt Lauf 1 | Ertrag | Eine Holzkiste kostet |
| --- | --- | --- |
| 1 min nach der Eimerkette (8:08) | 80 Münzen/s | 313 s |
| 1 min nach dem Mini-Bagger (11:08) | 2.462 Münzen/s | 10 s |
| **ab 11:52 (Saugroboter-Phase)** | ab 25.000 Münzen/s | **unter 1 s** |
| 1 min nach der Großmaschine (13:31) | 504.000 Münzen/s | 0,05 s |
| Baumende (21:36) | 8,0 Mio. Münzen/s | 0,003 s |

- **Praktisch gratis ab Lauf 1, 11:52 min.** Am Baumende und in den rund 2,5 min bis zum besten Sturmzeitpunkt (2.7) verdient der Spieler etwa 1,2 Mrd. Münzen. Der Sturm löscht sie, also kann er sie ohne Verlust in Holzkisten stecken.
- **Holz-Deckel +44,8 %:** im Mittel 3.552 Öffnungen (P90 4.672), das sind 81 Mio. Münzen (10 s Baumende-Ertrag) und 323 Paket-Aufrufe zu je 1,3 s, also 7 min. Der Deckel aus Seltenheit (höchstens Episch), ★5 und fehlendem Werkzeug-Slot greift. Er liegt aber für alle nach dem ersten Lauf an und macht Gold bis etwa 10 Öffnungen fast wertlos (Gold 10 allein 38 %, also weniger als der Holz-Deckel).
- **BigNum:** `BigNum.sub` verwirft 25.000 erst, wenn der Exponent des Münzstands mehr als 15 über dem des Preises liegt, also ab 10^20 Münzen. Das wird in den Läufen 1 bis 10 nicht erreicht (Endertrag höchstens 229 Mio./s). Die Genauigkeit ist kein Problem, die Wirtschaft schon.
- **Mitwachsender Preis:** Bei 250.000 Münzen kostet der Deckel 0,38 Lauf-1-Verdienste, bei 2,5 Mio. sind es 3,8 und bei 25 Mio. 38. Mit den Windkristallen steigt der Endertrag aber bis Lauf 10 auf das 28-Fache (229 Mio./s), und jeder feste Preis wird wieder gratis. Ein Preis nach Werkzeugstufe müsste deshalb zusätzlich mit den Kristallen wachsen. Ein Tageslimit ist einfacher und hält auch bei 10^20 Münzen:

| Tageslimit Holz | 100 Öffnungen (+26 %) | 1.000 Öffnungen (+34 %) | Holz-Deckel (+44,8 %) |
| --- | --- | --- | --- |
| 11 (1 Paket) | Tag 9 | Tag 91 | Tag 323 |
| **33 (3 Pakete)** | **Tag 3** | **Tag 30** | **Tag 108** |
| 110 (10 Pakete) | Tag 1 | Tag 9 | Tag 32 |

## Vorschlag

| Wert | Vorher (Entwurf) | Nachher | Begründung |
| --- | --- | --- | --- |
| Grundwerte ★1 (`effectBp` nach Seltenheit) | 500 / 700 / 1000 / 1400 / 1900 / 2500 | **unverändert**, Event-Items wie Gold derselben Seltenheit | Sie passen zum Konzept (5 bis 25 % je Item), und selbst +120 % kürzt Lauf 1 nur um 25 % gegen 46 % bei 2x Münzen. |
| Sternschritt | +15 % des Grundwerts | **unverändert** | Der Sprung von ★1 auf ★5 (x1,6) bleibt kleiner als ein Seltenheitssprung, eine höhere Seltenheit schlägt also fast immer die Sterne. |
| Kopien Gewöhnlich bis Episch | 1, 2, 3, 4 | **unverändert** | Bei Gewöhnlich und Ungewöhnlich sind die Sterne nach Minuten bedeutungslos, bei Selten und Episch ist ★5 in 139 bis 3.300 Öffnungen ein sinnvolles Mittelziel. |
| Kopien Legendär | 1, 2, 3, 4 (11) | **1, 2, 2, 3 (9)** | Alle 3 Legendär ★5 kosten 720 statt 858 Goldkisten. Das ist ein erreichbares Wal-Ziel bei +91,2 %. |
| Kopien Mythisch | 1, 2, 3, 4 (11) | **1, 1, 2, 2 (7)** | Ein Mythisch ★5 kostet 2.718 statt 4.623 Öffnungen. Die Stufen ab ★3 werden so für Viel-Käufer spürbar, das Maximum bleibt ein Langzeitziel. |
| Datenform Kopien | eine Liste für alle | **Tabelle je Seltenheit** in `Economy.items` | Sie spart später eine Schema-Änderung. DataCheck: jede Liste hat 4 Einträge, jeder Eintrag ist mindestens 1. |
| Holzkiste Preis | 25.000 Münzen | **unverändert** | Bis zum Mini-Bagger ist sie eine echte Ausgabe (10 s bis 313 s Ertrag je Kiste). |
| Holzkiste Tageslimit | keins | **33 Öffnungen je Tag** (neues Datenfeld, braucht Server-Logik mit Tageszähler) | Ohne Limit hat jeder Spieler nach Lauf 1 in 7 min +44,8 %, mit Limit wird daraus ein Ziel für etwa 100 Tage, das gegen Münzinflation und BigNum-Grenzen hält. |
| Konzepttext Kisten | "kleiner Bonus (etwa +5 bis +25 % Sammelrate)" | **"+5 bis +25 % je Item, mit Sternen bis +40 %, drei Slots"** | Die Summe kann 120 % erreichen, das sollte nicht als "klein" im Konzept stehen. |
| Tankgrößen (Paket 6.4) | auf 0 % Item-Bonus abgestimmt | **mit +45 % Item-Bonus prüfen** | Mit dem Holz-Deckel liegen 54 % statt 44 % der Läufe unter 15 s. |
