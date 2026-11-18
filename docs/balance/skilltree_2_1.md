# Paket 2.1: Skilltree des ersten Durchgangs

Stand 17.11.2026, Paket 2.1, `balance-analyst`. Die Simulation steht in `docs/balance/skilltree_2_1.py` (nur Standardbibliothek, Aufruf `python3 docs/balance/skilltree_2_1.py`, feste Seeds). Der Baum umfasst alles, was ein Spieler vor dem ersten Sandsturm kaufen kann: von der Hand bis etwas hinter die Großmaschine. Alle Zahlen sind Startwerte für den ersten Playtest.

## Vorschlag

Die Reihenfolge entspricht dem Kaufprotokoll der Simulation, die Glück-Knoten stehen dort, wo die Variante mit Glück-Ast sie kauft. "Fest" heißt: Vorgabe aus Paket 1.6 oder `Tools.luau`, unverändert. "Vorher" nennt den Platzhalter aus `phase0_startwerte.md`, sonst ist der Knoten neu. Rate, Verkauf und Glück sind in bp angegeben (10000 = 100 %), Tank als neue Gesamtgröße in Sand.

| Knoten | Spieler-Name | Beschreibung | Ast | requires | Vorher | Preis | Wirkung | Begründung |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `collect_rate_1` | Kräftigere Hände | +50 % Sand pro Sekunde | collect | - | fest | 15 | rateBonus 5000 | Fest, erster Kauf bei 20 s. |
| `tank_1` | Größerer Beutel | Tank 30 | tank | - | fest | 20 | setTank 30 | Fest, Kauf bei 1:00 min. |
| `collect_tool_2` | Schaufel | Werkzeug: Schaufel, gräbt eine Mulde | collect | - | fest | 50 | setTool shovel | Fest, Kauf bei 2:00 min. |
| `luck_1` | Scharfes Auge | +10 % Fundchance | luck | `collect_tool_2` | neu | 30 | luckBonus 1000 | So billig, dass der Glück-Ast sichtbar wird, ohne die Eimerkette mehr als 14 s zu verzögern. |
| `tank_2` | Rucksack | Tank 60 | tank | `tank_1` | fest | 60 | setTank 60 | Fest. |
| `collect_rate_2` | Geübter Griff | +25 % Sand pro Sekunde | collect | `collect_tool_2` | fest | 120 | rateBonus 2500 | Fest. |
| `sell_1` | Feilschen | +20 % Münzen pro Sand | sell | `collect_tool_2` | neu | 150 | sellBonus 2000 | Liegt zwischen den festen Knoten, damit die Lücke vor `tank_3` kürzer wird. |
| `tank_3` | Sandsack | Tank 150 | tank | `tank_2` | fest | 250 | setTank 150 | Fest. |
| `collect_rate_3` | Schneller Spaten | +25 % Sand pro Sekunde | collect | `collect_rate_2` | 300, +25 % | 300 | rateBonus 2500 | Platzhalter bestätigt, letzter Schritt vor der Eimerkette. |
| `collect_tool_3` | Eimerkette | Werkzeug: Eimerkette, Band trägt Sand zum Tank | collect | `collect_tool_2` | fest | 600 | setTool bucket_chain | Preis fest, `requires` unverändert, Kauf bei 6:54 min. |
| `tank_4` | Lederschlauch | Tank 400 | tank | `tank_3`, `collect_tool_3` | 700, 400 | 500 | setTank 400 | Erster Kauf in der Oase, holt die 13-s-Läufe nach dem Werkzeugsprung zurück ins Band. |
| `luck_2` | Wünschelrute | +10 % Fundchance | luck | `luck_1`, `collect_tool_3` | neu | 800 | luckBonus 1000 | Kostet in der Oase etwa 10 s Ertrag, also ein Nebenkauf. |
| `sell_2` | Marktkenntnis | +20 % Münzen pro Sand | sell | `sell_1`, `collect_tool_3` | neu | 1.000 | sellBonus 2000 | Schneller zweiter Kauf in der Oase. |
| `collect_rate_4` | Schnelle Eimer | +50 % Sand pro Sekunde | collect | `collect_rate_3`, `collect_tool_3` | 1.500, +25 % | 1.500 | rateBonus 5000 | +50 % statt +25 %, weil der Bonus sich auf die Grundrate addiert und sonst kaum spürbar wäre. |
| `tank_5` | Wasserfass | Tank 1K | tank | `tank_4` | 1.800, 900 | 2.500 | setTank 1000 | Bringt die Läufe der Eimerkette auf 16 bis 26 s. |
| `collect_rate_5` | Doppelte Kette | +50 % Sand pro Sekunde | collect | `collect_rate_4` | 3.500, +25 % | 4.000 | rateBonus 5000 | Etwa 25 s Ertrag, hält den Takt der Oase. |
| `sell_3` | Oasenmarkt | +30 % Münzen pro Sand | sell | `sell_2` | neu | 6.000 | sellBonus 3000 | Zweiter Verkaufsschritt der Oase. |
| `tank_6` | Karrenladung | Tank 2K | tank | `tank_5` | 4.500, 1.800 | 8.000 | setTank 2000 | 2.000 statt 2.500, damit der längste Lauf vor dem Bagger unter 40 s bleibt. |
| `collect_rate_6` | Lange Kette | +50 % Sand pro Sekunde | collect | `collect_rate_5` | neu | 12.000 | rateBonus 5000 | Tor zum Mini-Bagger, schiebt ihn von 9:52 auf 11:06 min. |
| `collect_tool_4` | Mini-Bagger | Werkzeug: Mini-Bagger, Fahrzeug mit Staubwolke | collect | `collect_tool_3`, `collect_rate_6` | fest, nur `collect_tool_3` | 7.500 | setTool mini_digger | Preis fest, neu ist das Tor `collect_rate_6`. |
| `tank_7` | Kipplader | Tank 6K | tank | `tank_6`, `collect_tool_4` | 11.000, 5.000 | 100.000 | setTank 6000 | Erster Kauf im Canyon, beendet die 14-s-Läufe nach dem Werkzeugsprung. |
| `luck_3` | Spürnase | +15 % Fundchance | luck | `luck_2`, `collect_tool_4` | neu | 50.000 | luckBonus 1500 | Etwa 20 s Ertrag, passt zu "tiefe Schichten mit seltenen Funden". |
| `sell_4` | Canyon-Handel | +30 % Münzen pro Sand | sell | `sell_3`, `collect_tool_4` | neu | 200.000 | sellBonus 3000 | Etwa 40 s Ertrag. |
| `collect_rate_7` | Baggerlöffel | +75 % Sand pro Sekunde | collect | `collect_rate_6`, `collect_tool_4` | neu | 300.000 | rateBonus 7500 | Größerer Schritt, weil die Summe der Boni schon bei +200 % liegt. |
| `tank_8` | Container | Tank 15K | tank | `tank_7` | neu | 400.000 | setTank 15000 | Hält die Bagger-Läufe bei 19 bis 34 s. |
| `sell_5` | Karawanenhandel | +50 % Münzen pro Sand | sell | `sell_4` | neu | 500.000 | sellBonus 5000 | Füllt die Zeit vor dem Tor. |
| `collect_rate_8` | Turbomotor | +100 % Sand pro Sekunde | collect | `collect_rate_7` | neu | 750.000 | rateBonus 10000 | Tor zum Saugroboter, ohne Tor käme er schon bei 10:47 min. |
| `collect_tool_5` | Saugroboter | Werkzeug: Saugroboter, saugt die Fläche leer | collect | `collect_tool_4`, `collect_rate_8` | fest, nur `collect_tool_4` | 90.000 | setTool vacuum_robot | Preis fest, neu ist das Tor `collect_rate_8`. |
| `tank_9` | Silo | Tank 60K | tank | `tank_8`, `collect_tool_5` | neu | 3 Mio. | setTank 60000 | Billigster Knoten im Salzsee, damit nur vier kurze Läufe nach dem Werkzeugsprung bleiben. |
| `collect_rate_9` | Starker Sog | +100 % Sand pro Sekunde | collect | `collect_rate_8`, `collect_tool_5` | neu | 10 Mio. | rateBonus 10000 | Etwa 40 s Ertrag. |
| `sell_6` | Salzhändler | +50 % Münzen pro Sand | sell | `sell_5`, `collect_tool_5` | neu | 15 Mio. | sellBonus 5000 | Etwa 50 s Ertrag. |
| `luck_4` | Salzkompass | +15 % Fundchance | luck | `luck_3`, `collect_tool_5` | neu | 5 Mio. | luckBonus 1500 | Etwa 20 s Ertrag, passt zu "Nebel versteckt Fundstellen". |
| `tank_10` | Speicherturm | Tank 150K | tank | `tank_9` | neu | 20 Mio. | setTank 150000 | Bringt die Läufe vor der Großmaschine auf 37 s. |
| `collect_rate_10` | Doppelrüssel | +150 % Sand pro Sekunde | collect | `collect_rate_9` | neu | 35 Mio. | rateBonus 15000 | Tor zur Großmaschine, ohne Tor käme sie schon bei 11:49 min. |
| `collect_tool_6` | Großmaschine | Werkzeug: Großmaschine, frisst ganze Dünen | collect | `collect_tool_5`, `collect_rate_10` | fest, nur `collect_tool_5` | 1,1 Mio. | setTool mega_machine | Preis fest, neu ist das Tor `collect_rate_10`. |
| `tank_11` | Frachtzug | Tank 800K | tank | `tank_10`, `collect_tool_6` | neu | 60 Mio. | setTank 800000 | Erster Kauf nach der Großmaschine, sonst bleiben die Läufe bei 13 s. |
| `sell_7` | Kristallbörse | +75 % Münzen pro Sand | sell | `sell_6`, `collect_tool_6` | neu | 100 Mio. | sellBonus 7500 | Etwa 30 s Ertrag. |
| `collect_rate_11` | Dünenfresser | +200 % Sand pro Sekunde | collect | `collect_rate_10`, `collect_tool_6` | neu | 200 Mio. | rateBonus 20000 | Etwa 45 s Ertrag. |
| `luck_5` | Sternkarte | +20 % Fundchance | luck | `luck_4`, `collect_tool_6` | neu | 100 Mio. | luckBonus 2000 | Etwa 30 s Ertrag. |
| `luck_6` | Glück der Wüste | +30 % Fundchance | luck | `luck_5` | neu | 150 Mio. | luckBonus 3000 | Letzter Glück-Schritt, Fundchance insgesamt x2. |
| `sell_8` | Wüstenbaron | +100 % Münzen pro Sand | sell | `sell_7` | neu | 300 Mio. | sellBonus 10000 | Verkauf insgesamt +375 %, der Name passt zum Spieltitel. |
| `tank_12` | Dünenspeicher | Tank 1,5M | tank | `tank_11` | neu | 400 Mio. | setTank 1500000 | 1,5M statt 2M, damit der Lauf vor dem letzten Knoten unter 40 s bleibt. |
| `collect_rate_12` | Sturmkraft | +250 % Sand pro Sekunde | collect | `collect_rate_11` | neu | 600 Mio. | rateBonus 25000 | Letzter Knoten vor dem Sandsturm, der Name kündigt ihn an. |

Größe: 12 Sammelrate-Knoten, 12 Tank-Knoten, 8 Verkauf-Knoten, 6 Glück-Knoten, dazu 5 Werkzeug-Knoten. Endwerte: Sammelrate +1.125 %, Verkauf +375 %, Glück +100 %, Tank 1,5M.

**Regeln für die Luau-Daten:**

- Jeder Ast ist eine Kette (jeder Knoten verlangt seinen Vorgänger). Der erste Knoten einer Werkzeugphase verlangt zusätzlich das Werkzeug, damit immer nur die nächsten Schritte sichtbar sind.
- Neue Wirkungen: `sellBonus` (bp, alle gekauften addieren sich, Preis = Grundpreis x Sandfaktor x (1 + Summe / 10000)) und `luckBonus` (bp, alle addieren sich, multipliziert die Fundchance pro Sekunde). `Collecting.pricePerSand` braucht dafür den Verkauf-Faktor.
- Geändert sind an bestehenden Knoten nur die `requires` von `collect_tool_4`, `collect_tool_5` und `collect_tool_6` (je ein Tor-Knoten dazu). Preise und Wirkungen der festen Knoten bleiben gleich.
- Die Beschreibungen der Tanks folgen der Zahlenanzeige im Spiel (K, M mit Komma), also "Tank 1K", "Tank 1,5M".

## Annahmen

- **Schleife wie in Paket 0.1 und im Lune-Test:** Start am Feld, sammeln, bis der Tank voll ist, 5 s zum Händler, verkaufen, kaufen, 5 s zurück. Verkaufen und Kaufen kosten keine Zeit.
- **Kaufregel:** Nach jedem Verkauf kauft der Spieler den billigsten sichtbaren Knoten, solange das Geld reicht. Ist der billigste zu teuer, spart er (wie `TreePurchase.visible()[1]` im Lune-Test). Die Regel aus Paket 0.1 (billigster bezahlbarer Knoten) ergibt mit diesem Baum dieselben Zeiten.
- **Basis ohne Glück:** In der Basis kauft der Spieler Sammeln, Tank, Verkauf und Werkzeuge. Die Glück-Knoten kommen als eigene Variante dazu.
- **Funde:** Wie in Paket 0.1 bringen Funde in der Basis keine Münzen, weil frühe Funde neu sind und in die Sammlung gehen. Die Variante "Fundverkauf" ist eine obere Schranke: Ab der Schaufel wird jeder Fund verkauft, Wert = 3 x Sandfaktor x Werkzeug-Grundrate x Wertfaktor (Erwartungswert x5,24).
- **Zone:** Der Spieler sammelt immer in der besten freigeschalteten Zone.
- **Tore:** Ein Tor ist der teuerste Sammelrate-Knoten einer Phase, den das nächste Werkzeug zusätzlich verlangt. Weil der Spieler billig zuerst kauft, ist bei Erreichen des Tors der Rest der Phase gekauft, und das Werkzeug folgt im selben Moment.
- **Auto-Dig:** Obere Schranke wie in Paket 0.1 (das Werkzeug sammelt schon auf dem Hinweg).

## Simulierte Zeiten

| Variante | Upgrade 1 | Schaufel | Eimerkette (Oase) | Mini-Bagger (Canyon) | Saugroboter (Salzsee) | Großmaschine | Baum fertig | Spielzeit im Band 15 bis 40 s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Basis (Vorschlag)** | **20 s** | **2:00** | **6:54** | **11:06** | **16:46** | **21:16** | **26:50** | **91 %** |
| Mit Glück-Ast (ohne Fundwert) | 20 s | 2:00 | 7:08 | 11:21 | 17:30 | 22:01 | 28:43 | 88 % |
| Mit Glück-Ast und Fundverkauf | 20 s | 2:00 | 6:38 | 10:28 | 16:23 | 20:54 | 27:35 | 90 % |
| Ohne Glück, mit Fundverkauf | 20 s | 2:00 | 6:38 | 10:28 | 16:09 | 20:18 | 25:42 | 90 % |
| Gamepass Großer Tank x2 | 35 s | 1:55 | 5:54 | 9:21 | 13:58 | 17:27 | 22:22 | 61 % |
| Gamepass 2x Münzen | 20 s | 1:10 | 3:50 | 6:03 | 9:01 | 11:16 | 14:24 | 89 % |
| 2x Münzen und Großer Tank | 35 s | 1:25 | 3:39 | 5:24 | 8:41 | 11:08 | 14:24 | 52 % |
| Auto-Dig (obere Schranke) | 20 s | 1:40 | 5:21 | 8:40 | 13:09 | 16:42 | 21:12 | 77 % |
| Ohne Tore an den Werkzeugen | 20 s | 2:00 | 6:54 | 9:52 | 10:47 | 11:49 | 19:46 | 71 % |

"Baum fertig" ist der letzte Kauf außerhalb des Glück-Asts. Mit Glück-Ast ist der ganze Baum bei 28:43 min gekauft, die Glück-Knoten kosten zusammen 255 Mio. Münzen.

**Gamepass-Wirkung gegenüber der Basis:** Großer Tank x2 spart 14 bis 18 %, 2x Münzen 45 bis 47 %, beide zusammen 46 bis 51 %, Auto-Dig als obere Schranke 21 bis 22 %. Das Verhältnis entspricht Paket 0.1, der Baum verschiebt es nicht.

**Empfindlichkeit Laufweg:** Bei 3 s je Richtung kommen Eimerkette 5:36, Mini-Bagger 9:04, Saugroboter 13:44, Großmaschine 17:26 und das Baumende 22:04 min. Bei 8 s je Richtung sind es 8:51, 14:09, 21:19, 27:01 und 33:59 min.

## Kaufprotokoll (Basis)

`collect_rate_1` 0:20, `tank_1` 1:00, `collect_tool_2` 2:00, `tank_2` 2:28, `collect_rate_2` 3:04, `sell_1` 3:55, `tank_3` 4:45, `collect_rate_3` 5:39, `collect_tool_3` 6:54. In der Oase folgen 8 Käufe bis `collect_rate_6` und Mini-Bagger bei 11:06. Im Canyon kommen 6 Käufe bis `collect_rate_8` und Saugroboter bei 16:46, im Salzsee 5 Käufe bis `collect_rate_10` und Großmaschine bei 21:16, danach 6 Käufe bis `collect_rate_12` bei 26:50.

| Phase | Käufe | Mittlere Pause | Längste Pause | Lauflänge Median (Min bis Max) | Läufe im Band 15 bis 40 s |
| --- | --- | --- | --- | --- | --- |
| Hand | 3 | 40 s | 60 s vor der Schaufel | 25 s (20 bis 30 s) | 100 % |
| Schaufel | 6 | 49 s | 75 s vor der Eimerkette | 17 s (14 bis 27 s) | 87 % |
| Eimerkette | 8 | 31 s | 73 s vor `collect_rate_6` | 23 s (13 bis 37 s) | 91 % |
| Mini-Bagger | 7 | 49 s | 67 s vor `sell_5` | 21 s (14 bis 34 s) | 80 % |
| Saugroboter | 6 | 45 s | 73 s vor `collect_rate_10` | 21 s (13 bis 37 s) | 83 % |
| Großmaschine | 7 | 48 s | 71 s vor `collect_rate_12` | 24 s (13 bis 36 s) | 79 % |

Über alle Varianten (Basis, Glück, 2x Münzen, Großer Tank) ist die längste Pause zwischen zwei Käufen 80 s. Der Ertrag pro Minute steigt ohne eine einzige Minute mit Rückgang von 1 Münze/s auf etwa 8 Mio. Münzen/s. Läufe unter 15 s (13 bis 14 s) gibt es nur in den ersten ein bis drei Läufen nach einem neuen Werkzeug, weil die Rate um das Fünf- bis Sechsfache springt. Der erste Kauf jeder Phase ist in der Basis deshalb immer ein Tank-Knoten.

Jeder Knoten außerhalb der Werkzeuge kostet beim Kauf 12 bis 75 s des aktuellen Ertrags. Früh in einer Phase sind es 12 bis 40 s (schnelle Käufe direkt nach dem Werkzeugsprung), gegen Ende 55 bis 75 s, das Tor ist jeweils der teuerste Schritt. Die Eimerkette kostet wie in Paket 0.1 83 s, die späteren Werkzeuge nur 2 bis 27 s, weil sie im selben Moment wie ihr Tor gekauft werden.

## Befunde

- **Die frühen Zeiten bleiben:** Upgrade 1 bei 20 s und Schaufel bei 2:00 min sind unverändert, weil Verkauf und Glück erst nach der Schaufel erscheinen. Eimerkette (6:54) und Mini-Bagger (11:06) liegen nahe an Paket 0.1 (6:46 und 10:39).
- **Tore sind nötig:** Ohne Tore kommt der Saugroboter 55 s nach dem Mini-Bagger (10:47 min) und die Großmaschine eine Minute danach (11:49 min). Mit Toren dauert jede Werkzeugphase 4,5 bis 6 Minuten. Der Preis bleibt dabei fest, aber das Tor kostet ein Vielfaches des Werkzeugs: 750.000 vor dem Saugroboter (90.000) und 35 Mio. vor der Großmaschine (1,1 Mio.). Im Baum wirkt das Werkzeug dadurch wie eine Belohnung für das Tor. Wer das stört, hebt in Paket 6.4 die Werkzeugpreise auf etwa 60 s Ertrag am Tor an, also Saugroboter etwa 700.000 und Großmaschine etwa 30 Mio., dann können die Tore entfallen.
- **Werkzeugsprünge:** Jedes neue Werkzeug macht den möglichen Ertrag 6- bis 24-mal größer (Rate x5 oder x6, dazu der Sandfaktor der neuen Zone). Darum steigen die Knotenpreise an jedem Werkzeug sprunghaft (12.000 auf 100.000, 750.000 auf 3 Mio., 35 Mio. auf 60 Mio.). Das ist gewollt, der Spieler sieht den Sprung auch im Preis.
- **Glück ist ein Nebenkauf:** Wer alle Glück-Knoten sofort kauft, verliert 14 bis 45 s je Meilenstein (2 bis 4 %) und 113 s bis zum Baumende (7 %). Dafür findet er bis zum Sandsturm im Mittel 37 statt 24 Fundstücke und 3,0 statt 1,9 Seltene oder bessere (Monte Carlo, Seeds 21 und 22). Selbst wenn jeder Fund verkauft wird, zahlt sich Glück in Münzen kaum aus: Funde bringen nur 17 % (Schaufel) bis 2 % (Großmaschine) des Ertrags, weil ihr Wert die Knoten-Boni nicht mitnimmt. Glück lohnt sich also für die Sammlung, nicht für Münzen.
- **Lune-Test:** Der Lune-Test kauft wie `TreePurchase.visible` den billigsten sichtbaren Knoten, also auch Glück. Seine Zeiten entsprechen darum der Zeile "Mit Glück-Ast": Eimerkette etwa 7:08, Mini-Bagger etwa 11:21. Die Reihenfolge Schaufel, `tank_2`, `collect_rate_2` bleibt erhalten, `luck_1` (30) kommt direkt nach der Schaufel bei 2:14.
- **Großer Tank:** Mit dem Pass sind die Läufe länger (Median 33 s, bis 63 s), nur 61 % der Spielzeit liegen im Band. Das ist der Sinn des Passes (weniger Wege), er bleibt mit 14 bis 18 % klar schwächer als 2x Münzen.
- **2x Münzen ist sehr stark:** Der Baum ist mit dem Pass nach 14:24 statt 26:50 min fertig. Für 399 Robux ist das wie in Paket 0.1 gewollt, gehört aber in den Playtest.
- **Erster Durchgang dauert etwa 27 Minuten:** Der Sandsturm ist laut Konzept ab Zone 3 möglich, also ab dem Mini-Bagger bei 11 Minuten. Die Prestige-Formel (2.7, 6.4) sollte so liegen, dass ein Sturm vor dem Baumende möglich, aber nach dem Baumende deutlich besser ist.
- **Laufweg:** Wie in Paket 0.1 hängen alle Zeiten stark am Weg zum Händler. 8 s statt 5 s verlängern den ganzen Durchgang um etwa 7 Minuten.
