# Paket 4.4: Gamepässe und Münz-Boost

Stand 19.11.2026, Paket 4.4, `balance-analyst`. Das Skript liegt in `docs/balance/passes_4_4.py` (nur Standardbibliothek, feste Seeds ab 4400, Aufruf `python3 docs/balance/passes_4_4.py`, Laufzeit etwa 3 s). Es importiert Baum, Schleife, Funde, Kristalle und Ruinenkarte aus `sandstorm_2_7.py` (und damit aus 2.1 und 2.6) und gleicht die Knotenpreise und Raten vorher mit `UpgradeTree.luau` und `Tools.luau` ab (keine Abweichung). Die freigegebenen Regeln werden hier nur bewertet, Code und Daten bleiben unverändert.

## Ergebnis

**Alle vier Regeln können bleiben.** 2x-Pass und Boost machen die Läufe kürzer, bringen aber pro Lauf keine zusätzlichen Kristalle, weil `runEarned` am Baumende ungefähr den Baumkosten entspricht. Der Vorsprung über den Windbonus wächst nicht unbegrenzt: Nach 3 h Spielzeit hat ein x4-Spieler 3,2-mal so viele Kristalle, nach 10 h nur noch 2,2-mal so viele. x4 ist für die Ökonomie unkritisch. Echte Risiken liegen anderswo: (1) **Wegzeit:** Der Server erlaubt Sammeln überall außer im Umkreis von 14 Studs um den Stand. Wer direkt neben dem Stand gräbt, braucht kaum Weg, und der Große Tank verliert dann fast seinen ganzen Wert. (2) **Auto-Dig:** Der Text in `Products.luau` verspricht schon heute 12 h offline, das kommt aber erst mit 5.3. (3) **Boost:** Er läuft offline weiter, bei 15-Minuten-Sitzungen verfällt also die Hälfte.

## Annahmen

- Wie in 2.7: billigster sichtbarer Knoten (Glück-Ast eingeschlossen), Sturm am Baumende (mindestens 20 Kristalle), 5 s Weg je Richtung, beste freie Zone, Funde aus 2.6. Keine Kisten-Items, keine Freunde.
- Der Münzfaktor wirkt auf Sandverkauf **und** verkaufte Duplikate (Regel "aus allen Verkäufen") und damit auf `runEarned`. Der Boost läuft in echter Zeit über eine Spieluhr, die über alle Läufe weiterläuft. "1 Boost" heißt: einmal bei t = 0 gekauft, Dauerspiel. "Dauerhaft x2/x4" heißt: in jeder Sitzung ein Boost (bei Sitzungen bis 30 min also immer aktiv).
- Großer Tank: Der Spieler wählt die schnellere Gewohnheit, also immer voll verkaufen oder schon verkaufen, sobald der nächste Knoten bezahlbar ist (nie unter der normalen Tankgröße).
- Auto-Dig: hält zu 100 % und sammelt auch auf dem Rückweg (Sand.luau `canCollect` prüft nur "lebt und nicht am Stand"). Bei vollem Tank ist Schluss.

## 1. 2x-Pass, Boost und beide zusammen

| Variante | Lauf 1 (Baumende) | Lauf 2 | Lauf 5 | Lauf 10 | 10 Läufe | Kristalle nach 10 | Kristalle/h (10 Läufe) | Kristalle nach 1 h / 3 h / 10 h | Lauf < 2 min ab |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ohne | 21:41 | 13:23 | 6:56 | 4:47 | 1:27 h | 309 | 211 | 118 / 1.354 / 12.546 | Lauf 85 (4:26 h) |
| 2x-Pass | 11:51 (-45 %) | 8:01 | 4:57 | 3:30 | 55:28 (-36 %) | 343 | 371 | 371 / 2.580 / 23.738 | Lauf 55 (2:30 h) |
| 1 Boost ab Start | 11:51 (-45 %) | 8:01 | 7:37 | 5:01 | 1:08 h (-22 %) | 299 | 264 | 232 / 1.605 / 13.196 | Lauf 85 (4:08 h) |
| Pass + 1 Boost | 6:57 (-68 %) | 5:01 | 3:43 | 3:43 | 39:27 (-55 %) | 356 | 541 | 555 / 2.921 / 24.503 | Lauf 55 (2:15 h) |
| dauerhaft x3 (additiv) | 8:40 (-60 %) | 5:48 | 3:55 | 2:36 | 42:18 (-51 %) | 334 | 474 | 569 / 3.583 / 24.324 | Lauf 46 (1:56 h) |
| **dauerhaft x4 (Pass x Boost)** | **6:57 (-68 %)** | **5:01** | **3:43** | **2:23** | **36:21 (-58 %)** | **322** | **532** | **683 / 4.287 / 28.090** | **Lauf 34 (1:24 h)** |

- **Kristalle pro Lauf:** In Lauf 1 sind es 27, 27, 28 und 29 Kristalle (x1 bis x4). Über 10 Läufe liegen alle Varianten bei 299 bis 356, also innerhalb von ±10 % um 309. Diese Streuung kommt aus dem letzten Gang und den Funden und ist kein Effekt des Passes. Der Faktor kauft also Zeit, keine Kristalle.
- **Sturm nach fester Zeit statt am Baumende** (Kristalle ~ Einnahmen^0,25): Wer immer nach 15 min stürmt, bekommt 13 Kristalle ohne Pass (das liegt unter `minCrystals`, ein Sturm geht also noch nicht), 35 mit dem 2x-Pass, 43 mit x3 und 48 mit x4.
- **Zinseszins:** Der Vorsprung (x4 gegen ohne) wächst schnell und fällt dann wieder: 5,8-mal so viele Kristalle nach 1 h, 3,2-mal nach 3 h, 2,2-mal nach 10 h. Grund: Die Laufzeit stößt an einen Boden von etwa 1 bis 1,5 min (Wege und Anzahl der Gänge), der für alle gleich ist. Der Windbonus allein (x250 nach 10 h) ist dann viel stärker als x4.
- **Ein Boost (49 Robux)** spart über die ersten 10 Läufe 19:55 min. Für Pass-Besitzer spart er 16:00 min bei x4 und nur 9:37 min, wenn additiv x3 gälte.

## 2. Großer Tank (x2, 199 Robux)

g = Tank / Rate (Sammelzeit eines Gangs), Gewinn an Durchsatz = (g + 2w) / (g + w) - 1 bei w Sekunden Weg je Richtung.

| Phase (Lauf 1) | Zone | Tank (Anfang bis Ende) | g in s | Anteil Weg | Gewinn bei 5 s Weg | bei 2 s | bei 0,5 s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Hand | Dünenmeer | 15 bis 30 | 10 bis 20 | 40 % | +25 % | +12 % | +3 % |
| Schaufel | Dünenmeer | 30 bis 150 | 4 bis 15 | 51 % | +34 % | +17 % | +5 % |
| Eimerkette | Oase | 150 bis 1.000 | 3 bis 13 | 55 % | +38 % | +20 % | +6 % |
| Mini-Bagger | Canyon | 1.000 bis 2.000 | 2 bis 4 | 77 % | **+62 %** | +40 % | +14 % |
| Saugroboter | Salzsee | 2.000 bis 15.000 | 1 bis 3 | 84 % | **+72 %** | +51 % | +21 % |
| Großmaschine | Salzsee, Ruinen | 15.000 bis 1,5 Mio. | 0,5 bis 20 | 49 % | +32 % | +16 % | +5 % |
| Baumende | | 1,5 Mio. | 20 (14 mit Holz-Items) | 33 % | +20 % (+26 %) | +9 % | +2 % |

| Weg je Richtung | Lauf 1 ohne / mit Tank | 10 Läufe ohne / mit Tank |
| --- | --- | --- |
| 5 s (Annahme seit Phase 0) | 21:36 / 17:17 (-20 %) | 1:27 h / 1:19 h (-9 %) |
| 2 s | 14:39 / 12:47 (-13 %) | 59:09 / 57:30 (-3 %) |
| 0,5 s (Graben direkt neben dem Stand) | 11:11 / 10:18 (-8 %) | 44:45 / 44:18 (-1 %) |
| 5 s, mit 2x-Pass | 11:46 / 10:09 (-14 %) | 55:28 / 51:21 (-7 %) |

- **Nach dem Tank-Ast nicht bedeutungslos:** Am Baumende bringt der Tank bei 5 s Weg noch +20 %, mit dem Holz-Deckel an Items +26 %. Am stärksten wirkt er in der Phase Mini-Bagger und Saugroboter, weil die Tank-Knoten dort hinter der Rate zurückbleiben (g 1 bis 4 s, 44 % aller Gänge unter 15 s). Hebt Paket 6.4 diese Tanks an, sinkt der Wert dort auf etwa +20 bis +30 %.
- **Das Risiko ist der Weg, nicht der Faktor:** Im Platzhalter-Layout (`World.luau`) liegt der Feldrand nur 14 Studs von der Verkaufsreichweite entfernt, das ist knapp 1 s Laufen. Außerdem darf man überall sammeln, außer im Umkreis von 14 Studs um den Stand. Wer das merkt, gräbt direkt neben dem Stand und braucht etwa 0,25 s Weg (4 Studs bis zur Prompt-Reichweite von 10 Studs). Dann bringt der Pass über 10 Läufe nur noch 1 % und der Tank-Ast insgesamt fast nichts. 2x für 199 Robux passt, aber nur, wenn die Welt etwa 5 s Weg erzwingt.
- Wer immer den vollen Tank verkauft, bekommt Upgrade 1 erst bei 35 s statt 20 s. Der Händler nimmt auch halbe Tanks an. Das Tutorial sollte beim ersten Mal bei 15 Sand zum Verkauf schicken, wie schon in Phase 0 empfohlen.

## 3. Auto-Dig (499 Robux)

| Spielweise ohne Pass (5 s Weg) | Baumende Lauf 1 | 10 Läufe | Mehrertrag pro Stunde durch Auto-Dig |
| --- | --- | --- | --- |
| hält 100 %, auch auf dem Rückweg | 14:40 | 59:27 | 0 % |
| hält 95 %, auch auf dem Rückweg | 15:16 | 1:01 h | **+4 %** |
| hält 90 %, auch auf dem Rückweg | 15:56 | 1:04 h | **+9 %** |
| hält 95 %, nur auf dem Feld | 22:08 | 1:30 h | +52 % |
| hält 80 %, nur auf dem Feld | 24:06 | 1:37 h | +65 % |
| Auto-Dig | 14:40 | 59:27 | (Bezug) |
| Auto-Dig + Großer Tank | 12:56 | 58:03 | 2 % schneller als Auto-Dig allein |

- **Realistisch sind +4 bis +9 %** bei einem Spieler, der ohnehin fast immer hält. Gegen einen Spieler, der nur auf dem Feld hält, sind es bei normalen Gängen (g 15 bis 30 s) +19 bis +33 %. In diesem Baum sind es sogar +52 bis +65 %, weil der Tank in der Mitte des Spiels schon auf dem Rückweg voll wird. Diesen Vorteil hat aber jeder, der auf dem Rückweg die Taste hält.
- **Kein AFK-Missbrauch:** Ohne Verkauf füllt Auto-Dig genau einen Tank. Das sind 20 s Ertrag am Baumende (41 s mit Großem Tank), also 0,6 % (1,1 %) einer aktiven Stunde pro Stunde AFK. Ein Gummiband auf der Maustaste schafft dasselbe auch ohne Pass. Funde gibt es nur, solange Sand fließt (`findSeconds`), mit vollem Tank also keine. Ob der Pass AFK-tauglich wird, entscheidet sich erst mit den 12 h offline in 5.3.
- Für 499 Robux ist das der teuerste Pass mit der schwächsten Wirkung im Spiel. Sein Wert liegt im Komfort (am Handy ist der Daumen frei) und in den 12 h offline.

## 4. x4 (Pass x Boost) gegen additiv x3

| Faktor | Schaufel | Mini-Bagger | Baumende L1 | 25.000 Münzen verdient | `minCrystals` (20) erreicht | Holzkiste = s Ertrag ab Saugroboter | Holz-Deckel (81 Mio.) = s Ertrag am Baumende |
| --- | --- | --- | --- | --- | --- | --- | --- |
| x1 | 2:00 | 10:08 | 21:36 | 10:08 | 18:03 (84 %) | 10,2 | 10,1 |
| x2 | 1:10 | 5:43 | 11:46 | 5:43 | 9:59 (85 %) | 5,1 | 5,1 |
| x3 | 0:50 | 3:59 | 8:35 | 3:59 | 7:12 (84 %) | 3,4 | 3,4 |
| **x4** | **0:50** | **3:06** | **6:52** | **3:06** | **5:53 (86 %)** | **2,5** | **2,5** |
| x4 + Freunde +50 % (x6) | 0:20 | 2:18 | 5:08 | 2:18 | 4:09 (81 %) | 1,8 | 1,7 |

- **Holzkiste:** Sie ist schon bei x1 ab dem Saugroboter praktisch gratis (Befund aus 4.3). x4 holt diesen Punkt von 10:08 auf 3:06 vor, die Bewertung ändert sich aber nicht. Gegenmittel bleibt das Tageslimit aus 4.3. Die Holzkiste gilt laut Konzept ohnehin als bezahltes Zufallsitem.
- **Sturm-Schwelle:** `minCrystals` hängt an den Einnahmen, nicht an der Zeit. Die Schwelle liegt bei jedem Faktor bei 81 bis 86 % des ersten Laufs, kein Faktor öffnet also einen frühen Sturm.
- **Gems:** Münzen lassen sich nicht in Gems tauschen, x4 erreicht die Gem-Kisten also nicht.
- **x4 gegen x3:** Lauf 1 ist um 20 % kürzer, 10 Läufe sind um 14 % kürzer, und nach 3 h (10 h) gibt es 20 % (15 %) mehr Kristalle. Das ist spürbar, aber kein Bruch. Mit x4 bleibt der Boost auch für Pass-Besitzer eine echte Verdopplung, so wie das Etikett "2x" verspricht. Bei x3 bekämen Pass-Besitzer nur noch +50 %, und der Boost wäre gerade für die zahlungsbereitesten Spieler weniger wert.
- **Nebenwirkung:** Mit x4 kommt die Schaufel bei 0:50 statt 2:00, das Tutorial muss also schnelle Meilensteine vertragen. Laufzeiten unter 2 min kommen mit x4 nach 1:24 h Spielzeit statt nach 4:26 h. Das ist Befund 4 aus 2.7 (Baumende braucht Knoten hinter der Ruinenkarte, Paket 6.4), x4 zieht ihn nur nach vorn.

## Empfehlungen

| Punkt | Bewertung | Begründung |
| --- | --- | --- |
| 2x-Pass x2, 399 Robux | behalten | Lauf 1 ist 45 % kürzer, pro Lauf gibt es keine zusätzlichen Kristalle, nach 10 h sind es 1,9-mal so viele. Kein Ausreißer. |
| Münz-Boost 30 min, 49 Robux, stapelbar | behalten | Ein Boost spart in den ersten 10 Läufen 20 min. Dauerhaft x2 über Boosts kostet 98 Robux je Stunde, der Pass lohnt sich also nach 4,1 h Spielzeit, das ist eine saubere Staffel. |
| Boost läuft offline weiter | behalten, aber vor dem Kauf deutlich anzeigen | Bei 15-min-Sitzungen verfällt die Hälfte, bei 10 min zwei Drittel. Gestapelte Boosts in einer kurzen Sitzung sind verlorenes Geld. Shop-Text: "läuft in Echtzeit weiter, auch wenn du offline bist", dazu die gesamte Restzeit. |
| x4 multiplikativ | behalten | Für die Ökonomie unkritisch (siehe Abschnitt 4), und "2x" bleibt für jeden eine Verdopplung. |
| Großer Tank x2, 199 Robux | behalten, **Weg sichern** | Bei 5 s Weg ist Lauf 1 20 % kürzer und am Baumende gibt es noch +20 %. Bei 0,5 s Weg (Graben am Stand) ist es nur noch 1 % über 10 Läufe. Vorschlag für Hauptsitzung oder Welt (3.x/6.4), nicht für 4.4: Sammeln nur auf dem Sandfeld erlauben und den Stand 60 bis 100 Studs vom Feldrand entfernt aufstellen, wie seit Phase 0 angenommen. |
| Auto-Dig 499 Robux | behalten, **Text oder Verkaufsstart anpassen** | Im Spiel bringt er nur +4 bis +9 %, der Wert kommt erst mit 12 h offline. `Products.luau` verspricht die 12 h aber schon. Bis 5.3 die 12 h aus dem Text nehmen oder den Pass erst mit 5.3 verkaufen. |
| Tests | ergänzen | Daily-Boosts (`coins2x`, 10 und 15 min) verlängern dieselbe Endzeit und stapeln nie den Faktor (höchstens x4). In 5.3 klären, ob der Offline-Ertrag den Boost mitnimmt. Empfehlung: nein, oder nur die überlappende Zeit, sonst gibt es mit 12 h Auto-Dig und gestapelten Boosts sehr hohe Offline-Erträge. |
| Fund-Duplikate | festlegen | Die Rechnung oben nimmt an, dass der Münzfaktor auch auf verkaufte Duplikate wirkt ("aus allen Verkäufen"). Wirkt er dort nicht, sinkt der Pass-Effekt um höchstens etwa 1 Prozentpunkt (Duplikate machen in Lauf 1 bis 10 nur 0,4 bis 1,1 % von `runEarned` aus). |
