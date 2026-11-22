# Paket 5.5: Saison 1 (Event-Zone, Saison-Punkte, Saison-Pass, Event-Kiste)

Stand 22.11.2026, Paket 5.5, `balance-analyst`. Skript: `docs/balance/season_5_5.py` (nur Standardbibliothek, feste Seeds ab 5500, Aufruf `python3 docs/balance/season_5_5.py`, etwa 10 s, Ausgabe bei zwei Läufen gleich). Es importiert Baum, Schleife, Funde und Kristalle aus `sandstorm_2_7.py`, den Datenabgleich aus `passes_4_4.py` und die Pity-Kette aus `directshop_4_6.py`. Es liest `SandTypes`, `Zones`, `Tools`, `UpgradeTree`, `Economy`, `GemPacks`, `Products`, `Crates` und `CrateItems` direkt. Der Abgleich zeigt keine Abweichung (45 Knoten, Werkzeugraten, Zonenfaktoren). Dateien unter `src/` und `tests/` wurden nicht geändert.

## Ergebnis

| Wert | Platzhalter in den Daten | Vorschlag | Begründung |
| --- | --- | --- | --- |
| `SandTypes "season".priceFactor` | 20 | **5** | Für Schaufel und Eimerkette ist das ein Bonus (x5 statt x1, +67 % gegenüber der Oase). Der Lauf beschleunigt bis zum Mini-Bagger etwa so stark wie der 2x-Pass. Bei 20 wäre die Event-Zone doppelt so ertragreich wie der Canyon, also würde jeder Spieler Oase und Canyon im Lauf auslassen. |
| `Zones "season_camp".requires` | `collect_tool_2` | `collect_tool_2` | Bleibt so: Das Tutorial und die ersten 2 Minuten (Upgrade 1 nach 0:20, Schaufel nach 2:00) laufen damit bei jedem Faktor unverändert. |
| `Economy.seasonPass.secondsPerPoint` | 30 | **10** | Ein Punkt je 10 s Graben ergibt 1 bis 3 Punkte je Gang. Damit sieht der Spieler bei jedem Gang Fortschritt, und die Stufen lassen sich in runden Zahlen schreiben. |
| Stufen (Punkte 1 bis 20) | 10 bis 100 (5 Stufen) | **30 bis 12.000** (Tabelle unten) | Der Gelegenheitsspieler erreicht Stufe 13 an Tag 24,3 (65 %), der Vielspieler Stufe 20 an Tag 16,7, also 4,3 Tage vor dem Ende von Woche 3. |
| Premium-Gems gesamt | 100 | **400** | Das ist eine Event-Kiste. Gemessen an dem, was 399 Robux in Gem-Paketen bringen (höchstens 850 Gems), sind es 47,1 %. |
| Gratis-Gems gesamt | 25 | **75** | Bescheiden: weniger als die Daily-Gems einer Saison (140 Gems und 4 Eisenkisten). |
| Pass-Items | keine | **3** (Selten auf Stufe 1, Episch auf Stufe 10, Legendär auf Stufe 20) | Eine sofortige Belohnung beim Kauf, ein Ziel in der Mitte für Gelegenheitsspieler, ein Hauptpreis für Vielspieler. Die `effectBp` entsprechen dem Event-Pool. |
| `Economy.seasonPass.duplicateGems` | 0 | **850** | Genau so viele Gems, wie 399 Robux in Gem-Paketen höchstens bringen (550 + 3 x 100 für 396 Robux). Der Spieler verliert nichts, und ein absichtlicher Doppelkauf lohnt sich nicht. |
| `Economy.seasonPass.claimGraceDays` | 3 | **3** | Reicht für Spieler, die jeden zweiten oder dritten Tag spielen. Die Frist liegt kurz genug vor einer möglichen nächsten Saison. |
| neu: `premiumGemsMaxPercent` (für DataCheck) | fehlt | **50** | Ermöglicht eine einfache Datenregel: Premium-Gems <= 50 % x Passpreis x Gems je Robux des kleinsten Pakets = 407. 400 besteht die Regel. |

## Annahmen

- **Spieler und Schleife** wie in 2.1, 2.7 und 4.4: 5 s Weg je Richtung, der billigste sichtbare Knoten wird gekauft (Glück eingeschlossen), Sturm am Baumende, Funde aus 2.6. Wer nur Münzen will, gräbt in der Zone mit dem höchsten Sandfaktor.
- **Event-Zone:** offen in allen 4 Wochen ab `collect_tool_2`. Sie hat **keine Funde**, denn laut Testfall 5.5a bleibt die Sammlung bei den fünf festen Zonen. Darum hat eine feste Zone mit gleichem Faktor immer noch ihre Funde als Vorteil.
- **Saison-Punkte** = Sekunden, in denen wirklich Sand in den Tank fließt (`Collecting.findSeconds` der Event-Zone), geteilt durch `secondsPerPoint`. Weg und voller Tank zählen nicht. Der Rest unter einem Punkt geht nicht verloren (der Server speichert Sekunden oder Bruchteile und zeigt abgerundet an).
- **Gelegenheitsspieler:** 30 min **Graben** (nicht Aufenthalt) je Tag an 28 Tagen. **Vielspieler:** 120 min Graben je Tag. Die Monte-Carlo-Rechnung zeigt zusätzlich ausgelassene Tage (85 % der Tage gespielt), Streuung der Spielzeit (lognormal, sigma 0,5), späten Einstieg und Aufenthalt statt Grabzeit.
- **Wert in Robux:** Ein 30-min-Münz-Boost entspricht dem Produktpreis von 49 Robux. Gems werden zu vier Bezugsgrößen bewertet (Tabelle in Abschnitt 5).
- **Belohnungen** werden von Hand abgeholt. Ein Boost beginnt beim Abholen (verlängert `boosts.coinsUntil` oder `luckUntil`), der Spieler wählt also selbst den Zeitpunkt.

## 1. Preisfaktor Event-Sand

Lauf 1 und 10 Sturm-Läufe, wenn der Spieler immer in der besten Zone gräbt. Werte in Klammern: Abweichung zu "ohne Saison".

| Faktor | Schaufel | Eimerkette | Mini-Bagger | Saugroboter | Großmaschine | Baumende L1 | 10 Läufe | Kristalle nach 10 | Lauf 10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ohne Saison | 2:00 | 7:08 | 10:08 | 11:30 | 12:31 | 21:36 | 1:27 h | 317 | 4:36 |
| x2 | 2:00 | 4:54 (-31 %) | 7:53 (-22 %) | 9:15 | 10:17 | 19:33 (-9 %) | 1:22 h | 309 | 4:44 |
| x3 (= Oase) | 2:00 | 3:58 (-44 %) | 6:57 (-31 %) | 8:19 | 9:21 | 18:38 (-14 %) | 1:18 h | 310 | 4:29 |
| **x5** | **2:00** | **3:16 (-54 %)** | **5:18 (-48 %)** | **6:39** | **7:40** | **16:45 (-22 %)** | **1:12 h** | **309** | **4:15** |
| x10 (= Canyon) | 2:00 | 2:56 (-59 %) | 3:54 (-62 %) | 5:15 | 6:17 | 15:22 (-29 %) | 1:06 h | 309 | 3:57 |
| x20 (Platzhalter) | 2:00 | 2:41 (-62 %) | 3:22 (-67 %) | 4:05 | 5:06 | 14:11 (-34 %) | 1:00 h | 307 | 3:36 |
| x40 (= Salzsee) | 2:00 | 2:39 (-63 %) | 3:05 (-70 %) | 3:19 | 4:21 | 13:26 (-38 %) | 58:01 | 309 | 3:33 |
| zum Vergleich: 2x-Pass ohne Saison | 1:10 | 4:07 | 5:43 | 6:23 | 7:00 | 11:46 | 55:53 | 344 | |
| 2x-Pass + x5 | 1:10 | 2:06 | 3:04 | 3:43 | 4:20 | 9:06 | 44:59 | 341 | |
| Auto-Dig ohne Saison | 1:40 | 5:31 | 7:48 | 8:48 | 9:38 | 17:02 | 1:09 h | 317 | |
| Auto-Dig + x5 | 1:40 | 2:37 | 4:11 | 5:11 | 6:01 | 13:25 | 58:25 | 309 | |

Ertrag in der Event-Zone im Verhältnis zur besten festen Zone. Verkauf-Ast, Kristalle, 2x-Pass und Boost wirken auf beide Zonen gleich, also zählt nur das Verhältnis der Sandfaktoren:

| Faktor | Dünenmeer (x1) | Oase (x3) | Canyon (x10) | Salzsee (x40) | Ruinenstadt (x150) |
| --- | --- | --- | --- | --- | --- |
| x3 | 300 % | 100 % | 30 % | 8 % | 2 % |
| **x5** | **500 %** | **167 %** | **50 %** | **12 %** | **3 %** |
| x10 | 1000 % | 333 % | 100 % | 25 % | 7 % |
| x20 | 2000 % | 667 % | 200 % | 50 % | 13 % |
| x40 | 4000 % | 1333 % | 400 % | 100 % | 27 % |

- **Warum 5:** Mit Schaufel und Eimerkette lohnt die Event-Zone mehr als jede feste Zone. Neue Spieler spüren das in der Saison als Bonus. Der Mini-Bagger kommt bei x5 nach 5:18, beim schon geprüften 2x-Pass nach 5:43. Faktor 5 beschleunigt die frühe Phase also nicht stärker als ein Produkt, das in 4.4 freigegeben wurde. Über den ganzen Lauf 1 wirkt x5 nur halb so stark wie der 2x-Pass (-22 % gegen -45 %).
- **Kristalle unverändert:** Bei jedem Faktor gibt es nach 10 Läufen 303 bis 310 Kristalle, ohne Saison 317. Die Event-Zone kauft Zeit, keine Kristalle. Das ist dasselbe Ergebnis wie beim 2x-Pass in 4.4. Der Sandsturm bleibt unberührt.
- **Warum nicht 20 (Platzhalter):** Die Event-Zone schlägt dann den Canyon (200 %). In jedem Lauf der Saison werden Oase und Canyon beim Geldverdienen übersprungen, und der Mini-Bagger kommt schneller als mit dem 2x-Pass (3:22). Die Ruinenstadt entwertet auch x20 nicht (13 %), das Problem liegt in der Mitte des Baums.
- **Ruinenstadt:** Bei jedem Faktor bis 40 bringt die Event-Zone einem Ruinen-Spieler höchstens 27 % des Ertrags. Die Ruinenstadt behält ihren Wert.
- **Unvermeidbarer Preis:** Weil die Punkte an der Zeit hängen, zahlt jeder Spieler ab dem Canyon für Saison-Punkte mit Ertrag: bei x5 die Hälfte im Canyon, 88 % im Salzsee und 97 % in der Ruinenstadt. Ein fester Faktor kann nicht zugleich frühe Spieler maßvoll belohnen und späte Spieler verschonen. Ändern ließe sich das nur in der Logik, das schlage ich hier nicht vor. Möglich wäre z. B. Event-Sand als Anteil des besten freigeschalteten Faktors oder ein kleiner Punkteanteil aus anderen Zonen. Das ist ein Thema für die Auswertung nach Saison 1 (7.4).

## 2. Saison-Punkte: `secondsPerPoint = 10`

Anteil der echten Grabzeit an der Zeit in der Zone, g = Tank / Rate:

| g | normal | Großer Tank | Auto-Dig | beide | Punkte je Gang |
| --- | --- | --- | --- | --- | --- |
| 3 s | 23 % | 38 % | 30 % | 55 % | 0,3 |
| 5 s | 33 % | 50 % | 50 % | 67 % | 0,5 |
| 10 s | 50 % | 67 % | 67 % | 80 % | 1,0 |
| 20 s | 67 % | 80 % | 80 % | 89 % | 2,0 |
| 30 s | 75 % | 86 % | 86 % | 92 % | 3,0 |

In Lauf 1 liegt der Grabanteil je Werkzeug bei 60 % (Hand), 47 % (Schaufel), 50 % (Eimerkette), 27 % (Mini-Bagger), 19 % (Saugroboter) und 47 % (Großmaschine), im Mittel bei 46 %.

- **2x Münzen** ändert die Punkte nicht, denn sie zählen Zeit und keine Münzen. Er macht die Event-Zone auch nicht attraktiver, weil er beide Zonen gleich verdoppelt.
- **Auto-Dig und Großer Tank** bringen mehr Punkte je Minute in der Zone, weil weniger Weg anfällt: bei g = 10 s 67 % statt 50 %, mit beiden 80 %. Das ist ein spürbarer, aber begrenzter Vorteil. Es gibt keinen AFK-Missbrauch, solange nur fließender Sand zählt: Mit vollem Tank kommen keine Punkte, wer AFK bleibt, füllt höchstens einen Tank.
- **Wichtig für die Umsetzung:** Zählen die Punkte nur über "Taste gehalten" statt über `findSeconds`, sammelt Auto-Dig rund um die Uhr Punkte (24 h = 8.640 Punkte, also 72 % der Spur an einem Tag). Darum unbedingt `findSeconds` der Event-Zone verwenden.
- **Falls die Ziele für Aufenthalt in der Zone gelten sollen statt für Grabzeit:** Bei 60 bis 67 % Grabanteil erreicht der Gelegenheitsspieler nur Stufe 11, der Vielspieler Stufe 20 erst an Tag 25 bis 28. Dann wäre `secondsPerPoint = 7` richtig, bei sonst gleichen Stufen.

## 3. Saison-Pass: 20 Stufen

Die Kurve folgt etwa 20,5 x n^1,4, gerundet. Der Zuwachs je Stufe sinkt nie. Graben = Grabzeit bis zur Stufe. "Tag" = Tag, an dem die Stufe erreicht ist, beim Gelegenheitsspieler (30 min) und beim Vielspieler (120 min).

| Stufe | Punkte | + | Graben | Tag (30 min) | Tag (120 min) | Gratis | Premium |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 30 | 30 | 0:05 h | 0,2 | 0,0 | 2x Münzen 5 min | **Item: Skin, Selten (1000)** |
| 2 | 90 | 60 | 0:15 h | 0,5 | 0,1 | 5 Gems | 25 Gems |
| 3 | 180 | 90 | 0:30 h | 1,0 | 0,2 | Glück 10 min | 2x Münzen 30 min |
| 4 | 320 | 140 | 0:53 h | 1,8 | 0,4 | 2x Münzen 10 min | 30 Gems |
| 5 | 510 | 190 | 1:25 h | 2,8 | 0,7 | 5 Gems | Glück 30 min |
| 6 | 760 | 250 | 2:06 h | 4,2 | 1,1 | Glück 10 min | 35 Gems |
| 7 | 1.070 | 310 | 2:58 h | 5,9 | 1,5 | 2x Münzen 10 min | 2x Münzen 30 min |
| 8 | 1.440 | 370 | 4:00 h | 8,0 | 2,0 | 10 Gems | 40 Gems |
| 9 | 1.880 | 440 | 5:13 h | 10,4 | 2,6 | Glück 10 min | Glück 30 min |
| 10 | 2.390 | 510 | 6:38 h | 13,3 | 3,3 | 2x Münzen 10 min | **Item: Begleiter, Episch (1400)** |
| 11 | 2.970 | 580 | 8:15 h | 16,5 | 4,1 | 10 Gems | 50 Gems |
| 12 | 3.630 | 660 | 10:05 h | 20,2 | 5,0 | Glück 15 min | 2x Münzen 30 min |
| 13 | 4.370 | 740 | 12:08 h | 24,3 | 6,1 | 2x Münzen 15 min | 70 Gems |
| 14 | 5.200 | 830 | 14:26 h | 28,9 | 7,2 | 10 Gems | Glück 30 min |
| 15 | 6.110 | 910 | 16:58 h | 33,9 | 8,5 | Glück 15 min | 2x Münzen 30 min |
| 16 | 7.110 | 1.000 | 19:45 h | 39,5 | 9,9 | 2x Münzen 15 min | 60 Gems |
| 17 | 8.200 | 1.090 | 22:46 h | 45,6 | 11,4 | 15 Gems | Glück 30 min |
| 18 | 9.390 | 1.190 | 26:05 h | 52,2 | 13,0 | Glück 15 min | 90 Gems |
| 19 | 10.680 | 1.290 | 29:40 h | 59,3 | 14,8 | 2x Münzen 15 min | Glück 60 min |
| 20 | 12.000 | 1.320 | 33:20 h | 66,7 | 16,7 | 20 Gems | **Item: Werkzeug-Variante, Legendär (1900)** |

Summen: Gratis 75 Gems, 80 min 2x Münzen, 75 min Glück. Premium 400 Gems, 120 min 2x Münzen, 180 min Glück, 3 Items. Obergrenze der Punkte (Testfall 5.5a) = 12.000.

**Zum Übertragen in `Data/SeasonPass.luau`** (`bySeason.season_1.tiers`, Format der Hauptsitzung):

```lua
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
```

**Pass-Items** (für `Data/CrateItems`, in keiner Kiste, Feld `passOnly = true` wie von der Hauptsitzung geplant; die Namen sind Platzhalter für den `data-worker`, die IDs sind frei, wie das Skript prüft):

```lua
    -- Saison-Pass Saison 1 (nur über den Pass, in keiner Kiste)
    { id = "skin_rare_4", kind = "skin", name = "Dünenpionier-Skin", rarity = "rare", crates = {}, effectBp = 1000, passOnly = true },
    { id = "companion_epic_3", kind = "companion", name = "Wüstenkarakal", rarity = "epic", crates = {}, effectBp = 1400, passOnly = true },
    { id = "toolVariant_epic_3", kind = "toolVariant", name = "Baronsschaufel", rarity = "epic", crates = {}, effectBp = 1400, passOnly = true },
```

- **Stufe 1, Skin Selten:** Der Käufer bekommt nach 5 min Graben sofort etwas Sichtbares.
- **Stufe 10, Begleiter Episch:** Der zahlende Gelegenheitsspieler erreicht sie an Tag 13. Das ist der Grund, über die Mitte hinaus zu spielen.
- **Stufe 20, Werkzeug-Variante Legendär:** Hauptpreis für alle, die die Spur schaffen, ab etwa 71 min Graben je Tag. Die Wirkung (+19 % Sammelrate bei ★1) ist klein im Vergleich zu 2x Münzen. Weil es jedes Pass-Item nur einmal gibt, lässt es sich nie verschmelzen und bleibt auf ★1. Ein Legendär-Item aus der Kiste kann dagegen auf ★5 (+30,4 %) steigen.

## 4. Ziele

| Spieler | Ergebnis | Ziel |
| --- | --- | --- |
| Gelegenheit, 30 min Graben an jedem Tag | 5.040 Punkte, **Stufe 13 (65 %)** an Tag 24,3, Stufe 14 erst an Tag 28,9 | etwa zwei Drittel: erfüllt |
| Vielspieler, 120 min an jedem Tag | **Stufe 20 an Tag 16,7**, Ende Woche 1: Stufe 13, Ende Woche 2: Stufe 18 | vor Ende Woche 3 (Tag 21): erfüllt, 4,3 Tage Puffer |
| ganze Spur in 28 Tagen | ab 71 min Graben je Tag | |

Monte Carlo (20.000 Spieler je Zeile): Stufe am Saisonende als 10 % / Median / 90 %.

| Fall | Stufe | Anteil >= 13 | Stufe 20 bis Tag 21 |
| --- | --- | --- | --- |
| Gelegenheit 30 min, jeden Tag | 13 / 13 / 13 | 100 % | 0 % |
| Gelegenheit 30 min, 85 % der Tage, Streuung | 11 / 12 / 13 | 43 % | 0 % |
| Gelegenheit 30 min, Einstieg Tag 8 | 12 | 0 % | 0 % |
| Gelegenheit 30 min, Einstieg Tag 15 | 10 | 0 % | 0 % |
| Kurzspieler 15 min (Annahme aus 2.6/2.7), 85 %, Streuung | 8 / 9 / 10 | 0 % | 0 % |
| 30 min Aufenthalt (etwa 20 min Graben), 85 %, Streuung | 9 / 10 / 11 | 0 % | 0 % |
| Mittel 60 min, 85 %, Streuung | 15 / 17 / 18 | 100 % | 0 % |
| Vielspieler 120 min, jeden Tag | 20 | 100 % | 100 % (Median Tag 17) |
| Vielspieler 120 min, 85 %, Streuung | 20 / 20 / 20 | 100 % | 65 % (Median Tag 20) |
| Vielspieler 120 min Aufenthalt (etwa 80 min Graben) | 18 / 19 / 20 | 100 % | 1 % |

- Wer an jedem 7. Tag aussetzt, landet eine Stufe tiefer. Das liegt noch im Rahmen von "etwa zwei Drittel" (Stufe 12 = 60 %).
- Wer erst in Woche 2 einsteigt, erreicht trotzdem Stufe 12 und damit den Begleiter auf Stufe 10. Das ist ein gutes Verkaufsargument noch in Woche 2 und 3.

## 5. Wert der Spuren, Ersatz-Gems, Abholfrist

| Bezugsgröße für 399 Robux | Gems | Anteil der 400 Premium-Gems |
| --- | --- | --- |
| beste Kombination aus Paketen (550 + 3 x 100, 396 R) | 850 | **47,1 %** |
| Kurs des 100er-Pakets (49 R) | 814 | 49,1 % |
| Kurs des 1.200er-Pakets (499 R) | 960 | 41,7 % |
| bester Kurs (7.000er-Paket) | 1.118 | 35,8 % |

- **Premium-Spur insgesamt:** 400 Gems (196 R zum Kurs des 100er-Pakets) und 120 min 2x Münzen (196 R zum Preis des Münz-Boosts) ergeben zusammen 392 R zum Listenpreis. Dazu kommen 3 feste Items und 180 min Glück. Ein Gelegenheitsspieler erreicht bis Stufe 13 250 Gems, 90 min 2x Münzen, 60 min Glück und 2 Items.
- **Gratis-Spur:** 75 Gems (bis Stufe 13: 30), 80 min 2x Münzen und 75 min Glück. Zum Vergleich: Der Daily Reward gibt je Saison 140 Gems, 4 Eisenkisten, 100 min 2x Münzen und 60 min Glück. Die Gratis-Spur ist also kleiner als der Daily Reward.
- **Premium-Gems = 1 Event-Kiste:** Sie bringt mit 5,4 % Legendär oder besser und mit 20,9 % Episch oder besser. Die Gems ersetzen keine Kistenkäufe, sie machen Lust auf die Kiste.
- **`duplicateGems = 850`:** Das ist der beste Gem-Gegenwert von 399 Robux in Paketen. 2,13 Gems je Robux sind weniger als bei jedem Paket ab 499 R (2,40 / 2,67 / 2,80), ein absichtlicher Doppelkauf bringt also keinen besseren Kurs. 960 (Kurs des 1.200er-Pakets) wäre großzügiger, gleicht aber nur den Kurs eines Pakets an, das man auch so kaufen kann. Ich empfehle 850.
- **`claimGraceDays = 3`:** Wer in der letzten Woche jeden zweiten oder dritten Tag spielt, kann noch abholen. Wenn Saisons ohne Pause aufeinander folgen, überschneidet sich die Frist mit dem Start der nächsten Saison. Das Pass-Fenster muss dann beide Saisons zeigen können (Anzeige, keine Balance-Frage). 7 Tage wären nur nötig, wenn Saisons mit einer Woche Pause geplant sind und die Pause sowieso leer bleibt.

## 6. Event-Kiste und Pool

- **Quoten:** `event` verweist auf `Odds.gold` (dieselbe Referenz), 400 Gems, Pity 15/60 wie Gold (eigener Zähler), `eventOnly = true`. Stimmt.
- **Pool je Seltenheit:**

| Seltenheit | Quote | Event | Gold | Arten im Event-Pool | effectBp Event (Gold) |
| --- | --- | --- | --- | --- | --- |
| Gewöhnlich | 0 % | 0 | 0 | keine nötig | |
| Ungewöhnlich | 40 % | 3 | 4 | Skin, Begleiter, Werkzeug | 700 (700) |
| Selten | 40 % | 3 | 5 | Skin, Begleiter, Werkzeug | 1000 (1000) |
| Episch | 15 % | 3 | 4 | Skin, Begleiter, Werkzeug | 1400 (1400) |
| Legendär | 4,5 % | 3 | 3 | Skin, Begleiter, Werkzeug | 1900 (1900) |
| Mythisch | 0,5 % | 3 | 3 | Skin, Begleiter, Werkzeug | 2500 (2500) |

- **Lücken in den Zahlen: keine.** Jede Seltenheit mit Quote hat 3 Items (das DataCheck-Minimum) und alle drei Arten. Die `effectBp` entsprechen der Goldkiste, kein Event-Item liegt in einer anderen Kiste, und es gibt kein Item ohne Quote.
- **Hinweise:**
  1. Weil der Event-Pool kleiner ist als der Gold-Pool, ist ein bestimmtes Ungewöhnlich-, Selten- oder Episch-Item in der Event-Kiste 1,3- bis 1,7-mal so wahrscheinlich wie in Gold (z. B. Selten 13,19 % statt 7,91 %). Bei Legendär und Mythisch ist es gleich. Das ist gewollt und unkritisch.
  2. Der Name `companion_mythic_2` "Saison-Sandwurm" widerspricht dem Konzept, das den Sandwurm aus dem Teaser ausdrücklich nicht übernimmt. Das gilt auch für "Sandwurm-Junges" in Gold. Nur Text, für den `data-worker`.
  3. Das Konzept nennt für Woche 3 "Neue Event-Items im Direktshop", `Economy.directShop` sagt dagegen "Event-Items haben nie einen Preis". Das muss vor 5.7 oder der Woche-3-Planung entschieden werden.
  4. Bei gesperrten Zufallsitems ist der Event-Pool nicht erreichbar. Die festen Pass-Items sind für diese Spieler die einzigen Saison-Items. Das ist zulässig, weil der Pass keine Zufallsitems enthält.
- **Kosten** (Pity exakt aus der Markov-Kette, dazu Monte Carlo mit 4.000 Spielern ab Zähler 0):

| Ziel | Öffnungen Mittel / Median / 90 % | Gems einzeln (Mittel) |
| --- | --- | --- |
| erstes Legendär+ | 18,56 exakt (MC 18,7 / 14 / 44) | **7.426** (10er-Paket 6.751) |
| bestimmtes Legendär | 62,0 / 46 / 142 | 24.817 (EV je Öffnung 24.752) |
| alle 3 Legendär | 113,3 / 100 / 202 | 45.315 |
| erstes Mythisch | 185,8 / 132 / 421 | 74.331 |
| ganzer Pool (15 Items) | 1.026 / 896 / 1.896 | 410.554 |

Das Konzept nennt "etwa 20 Goldkisten, rund 8.000 Gems". Das stimmt: exakt sind es 18,56 Kisten oder 7.426 Gems.

## Unsicherheiten

- **Grabzeit oder Aufenthalt:** Alle Ziele gelten für Grabzeit, wie im Auftrag. Misst das Team später Aufenthalt in der Zone, liegt der Gelegenheitsspieler 2 bis 3 Stufen tiefer, dann `secondsPerPoint = 7` (Abschnitt 2).
- **Event-Zone ohne Funde:** Gibt es dort doch Funde, steigt der Ertrag um bis zu etwa 15 % (Duplikat-Anteil aus Phase 0). Die Empfehlung x5 bleibt gleich.
- **Opportunitätskosten ab dem Canyon** lassen sich mit einem festen Faktor nicht lösen (Abschnitt 1). Nach Saison 1 sollte man messen, wie viel Zeit Spieler in Salzsee und Ruinenstadt in der Event-Zone verbringen (Analytics 6.3).
- **Legendär im Pass:** Ein Vielspieler bekommt für 399 Robux und 33 h Graben ein festes Legendär-Item. Aus der Kiste kostet ein bestimmtes Legendär-Item im Mittel 24.800 Gems. Die Leistung ist dank ★1-Deckel begrenzt, aber das Pass-Item kann Kistenkäufe in diesem einen Slot ersetzen. Die vorsichtigere Variante wäre Episch auf Stufe 20 und Selten auf Stufe 10. Ich empfehle trotzdem Legendär, weil es der Kaufgrund für den Pass ist.
- **Boost-Zeit im Pass** (Premium 120 min 2x Münzen) kann den Münz-Boost für 49 Robux etwas verdrängen. Sie fällt über 4 Wochen verteilt an und wird von Hand abgeholt.
- **Spielzeiten** (30 min und 120 min Graben) sind Vorgaben, keine Messwerte. Nach dem Soft-Launch mit echten `findSeconds` der Event-Zone nachrechnen (Skript: nur `CASUAL_MIN`, `HEAVY_MIN` und die Fälle in `section_pass` anpassen).
- **Koloss (5.6)** zählt Sand, nicht Zeit, und ist hier nicht modelliert. Er lockt in Woche 2 auch späte Spieler in die Event-Zone und verstärkt die Opportunitätskosten dort für ein Wochenende.


**Entscheidung (Waltuh überlässt sie der Hauptsitzung, 22.11.2026):** Stufe 20 gibt eine Werkzeug-Variante **Episch** (1400) statt Legendär, damit der Pass keine Kistenkäufe für diesen Slot ersetzt. `secondsPerPoint` bleibt 10 (echte Grabzeit).
