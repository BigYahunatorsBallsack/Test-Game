# Paket 2.6: Fundstücke, Sets und Sammlungsbonus

Stand 18.11.2026, Paket 2.6, `balance-analyst`. Die Simulation steht in `docs/balance/collection_2_6.py` (nur Standardbibliothek, feste Seeds, Aufruf `python3 docs/balance/collection_2_6.py`, Laufzeit etwa 90 s). Sie importiert Baum, Schleife und Kaufregel aus `docs/balance/skilltree_2_1.py`. Alle Zahlen sind Startwerte für den Playtest.

## Empfehlung

### Sammlungsbonus `setBonusBp` (in `src/shared/Data/Collection.luau` eingetragen)

| Set | Vorher | Nachher | Begründung |
| --- | --- | --- | --- |
| 1 | 200 | **300** | +2 % sieht man im Preis pro Sand kaum ("die Münzen pro Sand steigen sichtbar"), +3 % bleibt selbst im schlechtesten Fall (Set 1 jeder Zone sofort fertig) bei höchstens 4,4 % kürzeren Zeiten im ersten Lauf. |
| 2 | 200 | **300** | Set 2 kostet 2,4-mal so viele Funde wie Set 1 (150 statt 62) und soll darum nicht weniger bringen als das erste Set. |
| 3 | 300 | **400** | 207 Funde, zusammen mit Set 4 der Mittelteil, der nach dem ersten Sturm in 4 bis 6 Läufen fertig wird und dort spürbar sein soll. |
| 4 | 300 | **400** | 331 Funde, gleicher Bonus wie Set 3, weil der Abstand zwischen den beiden Sets klein ist (x1,6). |
| 5 | 500 | **600** | 673 Funde und der erste Legendär-Slot, etwa 12 Läufe nach dem ersten Sturm. |
| 6 | 1000 | **1000** | Unverändert: 2.154 Funde wegen des Mythisch-Slots (etwa 78 Spieltage), mehr Bonus würde den langen Zufallsschwanz (P90 166 Tage) zu wichtig machen. |
| Summe je Zone | 2500 (+25 %) | **3400 (+34 %)** | Alle fünf Zonenbücher geben +170 % statt +125 %, im Mittel aber erst nach über einem Jahr bei 15 Minuten pro Tag. |

Der Bonus pro erwartetem Fund fällt von Set zu Set (Set 1: 4,8 bp je Fund, Set 6: 0,46 bp je Fund). Das ist gewollt, die frühen Sets sollen sich lohnen, das Buch ist der Titel und der Skin.

### Seltenheitsverteilung der Sets (nur Vorschlag, `Finds.luau` bleibt unverändert)

| Set | Entwurf | Vorschlag V1 | Begründung |
| --- | --- | --- | --- |
| 1 | 3c 2u | **5c** | Ein Ungewöhnlich-Slot hat nur 2,44 % je Fund, mit zwei davon braucht Set 1 im Mittel 62 Funde (52 min im Dünenmeer), mit fünf Gewöhnlichen nur 20 Funde (16 min, P90 28 min). |
| 2 | 2c 2u 1r | **1c 3u 1r** | Nimmt einen Gewöhnlichen aus Set 1 auf. Der Engpass bleibt der Selten-Slot, Set 2 dauert fast gleich lang (155 statt 150 Funde). |
| 3 | 1c 2u 2r | **3u 2r** | Nimmt den zweiten Ungewöhnlichen auf, 209 statt 207 Funde. |
| 4 bis 6 | wie Entwurf | unverändert | Set 6 mit dem Mythisch-Slot bleibt das Langzeitziel, die Abstände Set 3, 4, 5, 6 (x1,6, x2,0, x3,2) passen. |

Zählt man je Zone, bleibt es bei 6c, 9u, 8r, 4e, 2l, 1m. Nur die Zuordnung zu den Sets ändert sich, die Quoten und die Logik bleiben gleich.

**Antwort auf die Frage, ob die Verteilung bleiben kann:** Die Sets 4 bis 6 können so bleiben. Set 1 ist mit zwei Ungewöhnlichen zu langsam für das Ziel "unter 20 Minuten". V1 trifft das Ziel im Mittel, aber nicht in der ersten Sitzung, weil der Spieler im Dünenmeer nur 3:43 min sammelt (siehe Befund 1).

## Annahmen

- **Fundmodell wie `Logic/FindRoll.luau`:** Chance pro Sammelsekunde = 0,02 × Zonenfaktor × Glück-Ast × (1 + 0,15 × Regenstärke in der Oase). Erst die Seltenheit nach `FindOdds.tables.base`, dann gleich verteilt unter den Funden der Zone mit dieser Seltenheit. Gerechnet wird als Poisson-Prozess je Slot. Das ist das Grenzverhalten von 1 − (1 − p)^dt bei Würfen pro Tick (0,25 s). Die Mittelwerte sind exakt, die Monte-Carlo-Gegenprobe (Seed 26, 20.000 Läufe) weicht um weniger als 1 % ab.
- **Regen:** 90 s je 480 s mit 4 s Blende, im Mittel Fundchance x1,027.
- **Erster Fund sicher:** ein Gewöhnlicher nach 60 s Sammelzeit, wenn bis dahin keiner kam.
- **Duplikate:** Sie werden sofort verkauft, Wert = 3 × Sandfaktor × Werkzeug-Grundrate × Wertfaktor. Darauf kommen kein Verkauf-Ast, kein Sammlungsbonus und kein 2x Münzen, so wie `Collection.record` den Wert heute bucht.
- **Sammlungsbonus:** Er wirkt als Faktor auf die Münzen pro Sand beim nächsten Verkauf und zählt für alle Zonen gleich.
- **Erster Lauf:** Schleife und Kaufregel wie in Paket 2.1 (billigster sichtbarer Knoten, Glück-Ast wird mitgekauft, 5 s Weg je Richtung, beste freigeschaltete Zone). Die Referenz sind die Zeiten aus 2.1 mit Toren (7:08 / 11:21 / 17:30 / 22:01), wie im Auftrag verlangt. Die heutige `UpgradeTree.luau` hat keine Tore (Entscheidung vom 18.11.), deshalb ist diese Fassung als zweite Referenz mitgerechnet (7:08 / 10:08 / 11:30 / 12:31). Je Variante gibt es 1.000 Läufe mit den Seeds 1000 bis 1999, die Bonus-Fassungen nutzen dieselben Seeds.
- **Sandsturm-Rhythmus:** Das Konzept nennt nur "ab Zone 3". Angenommen: ein Sturm je Lauf am Baumende, spätere Läufe so lang wie der erste (28:46 min, davon 55 % Sammelzeit), danach wird nur in der Ruinenstadt gesammelt (Sandfaktor 150 schlägt jede andere Zone, sie verlangt nur `sandstorm_1`). Der Glück-Ast wird je Lauf neu gekauft (im Mittel x1,41), und es gibt 15 Minuten Spiel pro Tag (zwei Sitzungen zu 7,5 min).

## 1. Sammelzeit bis ein Set fertig ist (Entwurf)

Echte Sammelzeit, Mittel / 90. Perzentil. Die Anzahl der Funde je Set ist in jeder Zone gleich, Glück und Zone verkürzen nur die Zeit.

**Ohne Glück:**

| Zone | Set 1 | Set 2 | Set 3 | Set 4 | Set 5 | Set 6 | Zonenbuch |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Dünenmeer | 52 min / 1:41 h | 2:04 h / 4:16 h | 2:52 h / 5:30 h | 4:35 h / 8:38 h | 9:20 h / 18:37 h | 29:54 h / 64:02 h | 31:15 h / 64:06 h |
| Oase | 42 min / 1:22 h | 1:41 h / 3:28 h | 2:19 h / 4:27 h | 3:43 h / 7:01 h | 7:34 h / 15:06 h | 24:16 h / 51:58 h | 25:21 h / 52:01 h |
| Canyon | 37 min / 1:12 h | 1:29 h / 3:03 h | 2:03 h / 3:55 h | 3:16 h / 6:10 h | 6:40 h / 13:18 h | 21:22 h / 45:44 h | 22:19 h / 45:47 h |
| Salzsee | 33 min / 1:03 h | 1:18 h / 2:40 h | 1:47 h / 3:26 h | 2:52 h / 5:24 h | 5:50 h / 11:38 h | 18:41 h / 40:01 h | 19:31 h / 40:04 h |
| Ruinenstadt | 26 min / 51 min | 1:02 h / 2:08 h | 1:26 h / 2:45 h | 2:17 h / 4:19 h | 4:40 h / 9:18 h | 14:57 h / 32:01 h | 15:37 h / 32:03 h |

**Mit vollem Glück-Ast (x2):**

| Zone | Set 1 | Set 2 | Set 3 | Set 4 | Set 5 | Set 6 | Zonenbuch |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Dünenmeer | 26 min / 51 min | 1:02 h / 2:08 h | 1:26 h / 2:45 h | 2:17 h / 4:19 h | 4:40 h / 9:18 h | 14:57 h / 32:01 h | 15:37 h / 32:03 h |
| Oase | 21 min / 41 min | 51 min / 1:44 h | 1:09 h / 2:13 h | 1:51 h / 3:30 h | 3:47 h / 7:33 h | 12:08 h / 25:59 h | 12:40 h / 26:00 h |
| Canyon | 19 min / 36 min | 45 min / 1:31 h | 1:01 h / 1:57 h | 1:38 h / 3:05 h | 3:20 h / 6:39 h | 10:41 h / 22:52 h | 11:09 h / 22:53 h |
| Salzsee | 16 min / 32 min | 39 min / 1:20 h | 54 min / 1:43 h | 1:26 h / 2:42 h | 2:55 h / 5:49 h | 9:20 h / 20:00 h | 9:45 h / 20:02 h |
| Ruinenstadt | 13 min / 25 min | 31 min / 1:04 h | 43 min / 1:22 h | 1:08 h / 2:09 h | 2:20 h / 4:39 h | 7:28 h / 16:00 h | 7:48 h / 16:01 h |

**Funde bis zum fertigen Set (Mittel / P90):** Set 1 62 / 121, Set 2 150 / 308, Set 3 207 / 396, Set 4 331 / 623, Set 5 673 / 1.341, Set 6 2.154 / 4.611, Zonenbuch 2.250 / 4.616.

- **Set 1 im Dünenmeer:** im Mittel 52 min Sammelzeit, P90 1:41 h. Nach 20 min Sammeln ist es erst bei 16 % der Spieler fertig. Das Ziel "unter 20 Minuten" verfehlt der Entwurf deutlich. Im ersten Lauf sammelt der Spieler nur 3:43 min im Dünenmeer (danach ist die Oase besser), damit wird Set 1 dort bei 0,1 % der Spieler fertig.
- **Zonenbuch Dünenmeer:** 31 h Sammelzeit ohne Glück, 15,6 h mit vollem Glück-Ast. Es hängt fast nur am Mythisch-Slot (0,05 % je Fund).
- **Set 6 mit Sandsturm-Rhythmus:** Nach dem ersten Sturm wird nur noch in der Ruinenstadt gesammelt. Dort ist Set 6 im Mittel nach 40 Läufen fertig, das sind etwa 78 Spieltage (P90 87 Läufe oder 166 Tage). Set 6 im Dünenmeer, in der Oase, im Canyon oder im Salzsee sieht ein Spieler mit normaler Spielweise nie, weil er diese Zonen nach dem ersten Lauf nicht mehr besucht.

| Ruinenstadt nach dem ersten Sturm (Entwurf) | Sammelzeit | Spielzeit | Läufe | Spieltage (15 min) |
| --- | --- | --- | --- | --- |
| Set 1 | 19 min (P90 36 min) | 34 min | 1,2 (2,3) | 2,2 (4,4) |
| Set 2 | 44 min (1:31 h) | 1:20 h | 2,8 (5,8) | 5,4 (11,1) |
| Set 3 | 1:01 h (1:57 h) | 1:51 h | 3,9 (7,4) | 7,4 (14,3) |
| Set 4 | 1:38 h (3:04 h) | 2:58 h | 6,2 (11,7) | 11,9 (22,4) |
| Set 5 | 3:19 h (6:37 h) | 6:03 h | 12,6 (25,2) | 24,2 (48,3) |
| Set 6 | 10:38 h (22:46 h) | 19:23 h | 40,4 (86,5) | 77,5 (166,0) |
| Zonenbuch | 11:06 h (22:48 h) | 20:15 h | 42,2 (86,7) | 81,0 (166,2) |

Mit V1 ist Set 1 in der Ruinenstadt nach 6 min Sammelzeit fertig (0,4 Läufe), die übrigen Zeilen bleiben gleich. Alle fünf Zonenbücher nacheinander mit vollem Glück brauchen 57 h Sammelzeit, etwa 416 Tage bei 15 min pro Tag.

**Erwarteter Sammlungsbonus nach N Läufen nach dem ersten Sturm** (nur Sets der Ruinenstadt):

| Bonus | N = 1 | 2 | 5 | 10 | 20 | 40 | 80 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Start (2500) | 1,6 % | 3,8 % | 8,5 % | 13,1 % | 17,5 % | 21,3 % | 23,8 % |
| Final (3400) | 2,4 % | 5,5 % | 11,8 % | 17,4 % | 22,3 % | 26,2 % | 28,8 % |

## 2. Seltenheitsverteilung

Funde bis zum fertigen Set, Mittel (P90). "Neu zuerst" ist eine Logik-Option und nicht im Code: Die gewürfelte Seltenheit füllt zuerst den fehlenden Slot dieser Seltenheit im niedrigsten Set, erst danach gibt es Duplikate.

| Variante | Set 1 | Set 2 | Set 3 | Set 4 | Set 5 | Set 6 / Buch |
| --- | --- | --- | --- | --- | --- | --- |
| Entwurf | 62 (121) | 150 (308) | 207 (396) | 331 (623) | 673 (1.341) | 2.154 (4.611) |
| V1 (Set 1 = 5c) | 20 (33) | 155 (309) | 209 (396) | 331 (623) | 673 (1.341) | 2.154 (4.611) |
| Entwurf, neu zuerst | 10 (17) | 25 (40) | 53 (88) | 103 (161) | 326 (658) | 2.124 (4.605) |
| V1, neu zuerst | 7 (9) | 22 (38) | 53 (88) | 103 (161) | 326 (658) | 2.124 (4.605) |

Sammelzeit Set 1 im Dünenmeer ohne Glück: Entwurf 52 min, V1 16 min (P90 28 min), Entwurf mit "neu zuerst" 8 min, V1 mit "neu zuerst" 6 min (P90 9 min).

- **Set 1 ist zu langsam:** Der Engpass sind die beiden Ungewöhnlich-Slots. Neun Ungewöhnliche teilen sich 22 %, also hat jeder nur 2,44 % je Fund. V1 löst das ohne Logikänderung.
- **Set 6 als Langzeitziel passt:** Der Mythisch-Slot macht Set 6 zum Zonenbuch (2.154 von 2.250 Funden). Wer das Buch schneller will, müsste die Mythisch-Quote ändern, die laut Konzept fest ist.
- **"Neu zuerst" ist zu stark für die Mitte:** Die Sets 2 bis 5 würden 3- bis 6-mal schneller, Set 6 nicht. Der Abstand von Set 5 zu Set 6 würde dann x6,5 statt x3,2 betragen. Ich empfehle die Option nur, falls Set 1 im Dünenmeer unbedingt in die erste Sitzung soll (siehe Befund 1), und dann besser nur für Set 1.

## 3. Erster Lauf mit Sammlungsbonus

Zeiten im Mittel mit den Final-Werten. Die Spalten "Max" zeigen die größte Verkürzung durch den Bonus in einem einzelnen der 1.000 Läufe, gemessen am selben Seed ohne Bonus. Im Mittel verkürzt der Final-Bonus die Werkzeugzeiten um 0,0 % und das Baumende um höchstens 1,8 %.

| Variante | Eimerkette | Mini-Bagger | Saugroboter | Großmaschine | Baum fertig | Max Start | Max Final | Max Stress x4 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Referenz 2.1 mit Toren | 7:08 | 11:21 | 17:30 | 22:01 | 28:43 | - | - | - |
| Tore, Entwurf | 7:07 | 11:20 | 17:29 | 22:00 | 28:41 | 0,0 % (Baum 1,4 %) | 0,0 % (Baum 1,4 %) | 1,7 % (Baum 3,2 %) |
| Tore, Entwurf, 2x Münzen | 4:05 | 6:18 | 9:30 | 11:47 | 15:22 | 0,0 % | 0,0 % (Baum 2,6 %) | 0,0 % (Baum 3,1 %) |
| Tore, Entwurf, Auto-Dig (obere Schranke) | 5:31 | 8:50 | 13:40 | 17:15 | 22:38 | 0,0 % (Baum 1,4 %) | 0,0 % (Baum 1,4 %) | 2,0 % (Baum 3,3 %) |
| Tore, Entwurf, Großer Tank | 6:10 | 9:38 | 14:31 | 18:04 | 23:43 | - | 0,5 % (Baum 4,2 %) | - |
| Tore, V1 | 7:07 | 11:20 | 17:29 | 22:00 | 28:36 | 0,0 % (Baum 2,2 %) | 0,0 % (Baum 2,2 %) | 2,0 % (Baum 4,6 %) |
| Tore, V1 und neu zuerst | 7:08 | 11:21 | 17:30 | 22:01 | 28:12 | 0,0 % (Baum 2,1 %) | 1,7 % (Baum 4,8 %) | 6,2 % (Baum 10,6 %) |
| Referenz ohne Tore (heutiger Baum) | 7:08 | 10:08 | 11:30 | 12:31 | 21:36 | - | - | - |
| Ohne Tore, Entwurf | 7:07 | 10:07 | 11:29 | 12:30 | 21:35 | 0,0 % | 0,0 % (Baum 1,8 %) | 2,1 % (Baum 4,0 %) |
| Ohne Tore, V1 und neu zuerst | 7:08 | 10:08 | 11:30 | 12:31 | 21:22 | 2,0 % (Baum 3,9 %) | 2,1 % (Baum 4,0 %) | 4,8 % (Baum 7,2 %) |

"Stress x4" bedeutet viermal die Final-Werte (800 bis 4000 bp), nur als Grenzprobe.

**Obere Schranke (deterministisch, Tore):** Wäre Set 1 jeder Zone fertig, sobald der Spieler sie betritt, würden die Werkzeugzeiten mit Final um 0,0 / 0,6 / 1,7 / 2,9 % kürzer, das Baumende um 4,4 %. Ohne Tore sind es 0,0 / 0,0 / 2,1 / 2,0 % und beim Baumende 4,9 %. Mit Set 1 und Set 2 in jeder Zone sind es 0,0 / 0,8 / 3,9 / 4,8 % und 8,0 %. Erst bei viermal so hohen Werten nähert sich die Großmaschine der Grenze (9,0 %).

**Sammlung am Ende des ersten Laufs (Tore, Entwurf):** 37,5 Funde, davon 23,8 neu. Nur 15,6 % der Spieler haben mindestens ein fertiges Set, fast immer Set 1 im Salzsee (13,4 %). Der Bonus liegt am Ende im Mittel bei 0,5 %. Mit V1 haben 68 % ein Set (Salzsee Set 1 64 %), mit V1 und "neu zuerst" 100 % (im Mittel 2,7 Sets, Bonus 8,1 %).

**Ergebnis:** Die Bedingung "höchstens 10 % kürzer" hält mit jeder geprüften Fassung, auch im schlechtesten Fall. Der Sammlungsbonus wirkt im ersten Lauf praktisch nicht, er ist ein Werkzeug für die Läufe nach dem Sturm. Upgrade 1 (20 s) und Schaufel (2:00) ändern sich in keiner Variante, die längsten Pausen und die Ertragskurve aus 2.1 auch nicht. Einen Einbruch beim Einkommen gibt es nicht.

**2x Münzen und Auto-Dig:** 2x Münzen halbiert den ersten Lauf, darum gibt es nur 20 statt 37 Funde und bei 3 % ein fertiges Set. Funde pro Spielstunde bleiben gleich (78). Auto-Dig (obere Schranke) und Großer Tank bringen 99 und 101 statt 78 Funde pro Spielstunde, also 27 bis 29 % mehr, weil ein größerer Teil der Spielzeit Sammelzeit ist (siehe Befund 5).

## 4. Anteil der Münzen aus Funden je Werkzeug

Methode wie in 2.1 (jeder Fund wird verkauft, Knoten zum Phasenbeginn, mit Glück-Ast). Das ist eine obere Schranke.

| Sammlungsbonus | Schaufel | Eimerkette | Mini-Bagger | Saugroboter | Großmaschine |
| --- | --- | --- | --- | --- | --- |
| ohne (2.1) | 17,3 % | 14,7 % | 8,2 % | 4,9 % | 3,1 % |
| +34 % (ein Buch, Final) | 13,5 % | 11,4 % | 6,2 % | 3,7 % | 2,4 % |
| +170 % (fünf Bücher, Final) | 7,2 % | 6,0 % | 3,2 % | 1,9 % | 1,2 % |
| **echt im ersten Lauf** (nur Duplikate, Final) | 1,1 % | 0,4 % | 0,5 % | 0,3 % | 0,5 % |

Ruinenstadt mit der Hand nach dem Sturm (obere Schranke): ohne Bonus 38,6 %, mit +34 % noch 31,9 %, mit +170 % noch 18,9 %.

- **Die Spanne "17 % bis 2 %" gilt nur als obere Schranke:** Mit Glück-Ast sind es 17 bis 3 %, ohne Glück wie in 2.1 17 bis 2 %. Im ersten Lauf sind fast zwei Drittel der Funde neu, deshalb bringen Duplikate dort nur 0,3 bis 1,1 % des Ertrags.
- **Der Sammlungsbonus senkt den Anteil weiter**, weil er nur den Sand verteuert und nicht die Funde: mit einem fertigen Buch auf etwa drei Viertel, mit allen fünf auf etwa die Hälfte.
- **Später steigt der echte Anteil gegen die obere Schranke:** Sobald Gewöhnliche und Ungewöhnliche einer Zone vollständig sind, ist fast jeder Fund ein Duplikat. In der Ruinenstadt geht der Anteil in der Handphase direkt nach dem Sturm damit gegen 32 % (mit einem Buch) bis 39 % (ohne Bonus). Das gehört zur Prestige-Formel (2.7, 6.4).

## 5. Befunde

1. **Set 1 im Dünenmeer kommt nicht in die erste Sitzung, egal mit welcher Verteilung.** Mit der Kaufregel aus 2.1 sammelt der Spieler nur 3:43 min im Dünenmeer (4 bis 5 Funde plus der sichere erste), danach wechselt er in die Oase. Die Wahrscheinlichkeit, dass Set 1 im Dünenmeer im ersten Lauf fertig wird, liegt beim Entwurf bei 0,1 %, mit V1 bei 1,9 %, mit V1 und "neu zuerst" bei 27 % und mit V1, "neu zuerst" und Fundfaktor x1,5 im Dünenmeer bei 60 %. Das erste fertige Set eines Spielers liegt fast immer im Salzsee. Soll es das Dünenmeer sein, braucht es eine Tutorial-Regel ("die ersten fünf Funde füllen Set 1"). Mit Daten allein geht das nicht. Empfehlung: V1 übernehmen und das Ziel auf "erstes fertiges Set im ersten Lauf" ändern (mit V1 bei 68 % der Spieler).
2. **Vier von fünf Zonenbüchern bleiben nach dem ersten Sturm liegen.** Die Ruinenstadt verlangt nur `sandstorm_1` und zahlt das 150-Fache des Dünenmeers. Danach sammelt kein rational spielender Spieler mehr in den Zonen 1 bis 4. Ihre 24 Sets (80 % der Sammlung) füllen sich nur noch durch gezieltes Sammeln zu einem Bruchteil des Ertrags. Weil der Set-Bonus überall gleich ist, sind die Sets der Ruinenstadt sogar doppelt so schnell (Fundfaktor 2,0). Das gehört in Paket 2.7: Entweder führt der Lauf nach dem Sturm wieder durch die Zonen (Ruinenstadt erst ab einem späteren Knoten), oder es gibt einen eigenen Anreiz für alte Zonen (Aufgaben, Event-Set).
3. **Offline-Funde füllen Set 1 von selbst (Ausnutzungsweg).** `Economy.offline.noFindsFromRarityId = "rare"` schließt nur Funde ab Selten aus. Set 1 besteht aber nur aus Gewöhnlichen und Ungewöhnlichen. Würfelt der Begleiter mit der normalen Chance, bringen 4 Stunden offline 288 Funde, und Set 1 ist mit 99,8 % fertig (mit Auto-Dig nach 12 Stunden sicher). Das wäre Sammlung ohne Spielen. Empfehlung für 5.3: Offline-Funde zählen nicht für die Sammlung (nur Münzen für Duplikate) oder laufen mit stark reduzierter Chance.
4. **Ein Wurf pro Verkauf statt pro Tick kostet bis zu 62 % der Funde.** `FindRoll.roll` gibt höchstens einen Fund pro Aufruf. Ruft der Finds-Service das einmal pro Lauf oder pro `SetCollecting` auf, statt in jedem 0,25-s-Tick von `Collecting.update`, fehlen bei 20 bis 30 s Sammelzeit 17 bis 24 % (Dünenmeer) bis 49 bis 62 % (Ruinenstadt mit Glück x2) der Funde. Außerdem gilt dann das Wetter zum Zeitpunkt des Wurfs für das ganze Fenster, und ein Client mit vielen `SetCollecting`-Aufrufen würfelt öfter. Der Testfall "pro Tick höchstens ein Fund" muss also wirklich pro Tick laufen.
5. **Großer Tank und Auto-Dig beschleunigen die Sammlung um 27 bis 29 % pro Spielstunde.** Die Quoten bleiben unberührt ("kein Kauf verändert ihre Quoten" stimmt), aber längere Läufe und Sammeln auf dem Weg erhöhen den Anteil der Sammelzeit. Das ist vertretbar, weil Funde nicht handelbar sind, sollte aber bewusst entschieden und im Shop nicht als "mehr Funde" beworben werden. Wenn Auto-Dig in 5.3 auch automatisch verkauft, wird daraus AFK-Farmen der ganzen Sammlung. Auto-Dig muss deshalb beim vollen Tank stoppen, wie `Collecting.update` es heute tut.
6. **Kein Ausnutzungsweg über Regen oder Zonenwechsel.** Die Oase im Regen (0,0552 Funde/s mit Glück x2) bleibt unter Canyon (0,056) und Salzsee (0,064). Wer das Oasenbuch nur im Regen sammelt, spart 10,7 % Sammelzeit, braucht aber 5,3-mal so viel Spielzeit. Funde ohne Münzen gibt es nicht, weil ohne Sandfluss (voller Tank, am Händlerstand) keine Sammelzeit zählt. Der Fundwert hängt nicht an den Knoten, Horten lohnt sich also nicht.
7. **2x Münzen und Duplikate:** `Collection.record` bucht den Duplikatwert ohne den 2x-Faktor. Das Konzept verspricht "doppelte Münzen aus allen Verkäufen". Bei 0,3 bis 1,1 % Anteil im ersten Lauf ist das für die Kurve egal, für die Erwartung des Käufers aber nicht. Entweder nimmt der Pass Duplikate mit, oder der Shoptext sagt "aus allen Sandverkäufen". Das entscheidet Waltuh.
8. **Erster Fund:** Mit der 60-s-Regel kommt der erste Fund im Mittel nach 0:55 min Spielzeit, spätestens nach 1:40 min (ohne Regel waren es in Paket 0.1 78 % in den ersten 2 Minuten). Der Studio-Test "nach etwa einer Minute" passt.
9. **Seltene Funde und Kisten (Kontrolle):** Der erste Legendär-oder-besser-Fund kommt im Dünenmeer nach 3:28 h Sammelzeit ohne Glück (1:44 h mit Glück), in der Ruinenstadt mit Glück nach 52 min. Die Goldkiste ist unverändert: Legendär oder besser im Mittel nach 19,1 Öffnungen, das sind 7.631 Gems einzeln oder 6.938 Gems im 10er-Paket.

## Finale Werte

- `Collection.setBonusBp = { 300, 300, 400, 400, 600, 1000 }` (eingetragen), +34 % je Zone, +170 % für alle fünf Bücher.
- `Finds.luau` (nur Vorschlag, gehört zum Worker der Fundliste): Set 1 = 5c, Set 2 = 1c 3u 1r, Set 3 = 3u 2r, Sets 4 bis 6 unverändert.
- Offen für andere Pakete: Offline-Funde und Sammlung (5.3), Zonenbesuch nach dem Sturm (2.7), Würfe pro Tick im Finds-Service (2.6, Hauptsitzung), 2x Münzen und Duplikate (Waltuh).
