# Paket 6.4: Balancing (Wirtschaft, Verdienstkurve, Prestige-Formel)

Stand 24.11.2026, `balance-analyst`. Ziel aus dem Umsetzungsplan: "Kein Engpass, an dem Spieler hängen bleiben". Dieses Dokument ändert keine Daten und keinen Code. Alle Zahlenvorschläge entscheidet der Mensch.

Simulation: `tools/balance_sim.luau`, Aufruf im Projektordner `lune run tools/balance_sim [Teil] [Startwert]` (Teil `all` dauert etwa 1 Minute, Startwert 64; die Tabellen unten stammen aus diesem Lauf, die Startwerte 65 und 66 weichen bei Zeiten um weniger als 3 % ab). Teile: `base`, `passes`, `crystals`, `storm`, `casual`, `crates`, `proposals`, `recommended`, `explore`, `explorelong`, `long`.

## Kurzfassung

1. **Kein Engpass in den ersten 34 Stunden aktiver Spielzeit.** Die längste Pause zwischen zwei Käufen ist 1:15 min (vor der Eimerkette). Erstes Upgrade nach 20 s, Schaufel nach 2:00 min, beides genau auf Ziel.
2. **Ein harter Engpass liegt bei etwa 35 Stunden aktiv:** Dann hält der Spieler 99.991 Windkristalle. `maxCrystals = 100.000` begrenzt den Gewinn auf 9, und das ist weniger als `minCrystals = 20`. Ab da ist kein Sturm mehr möglich, und der Baum ist fertig. In der 80-h-Simulation folgen 45 Stunden ohne Fortschritt.
3. **Die Läufe fallen in sich zusammen.** Lauf 1 dauert 21:18 min, Lauf 10 noch 4:48, Lauf 20 noch 2:43, und ab etwa 6 Stunden liegt jeder Lauf bei rund 1 Minute, weil dann nur noch der Weg zum Händler bremst. Nach 8 Stunden hat der Spieler 221 Stürme und +17.298 % Bonus. Der Sturm verliert damit seinen Reiz, und der Inhalt ist schnell verbraucht.
4. **Saugroboter und Großmaschine kommen zu früh**, nur 1:23 und 1:02 min nach dem vorigen Werkzeug. Danach folgen 8:43 min mit der Großmaschine. Das ist der in Paket 2.1 angekündigte Befund (Entscheidung vom 18.11.: keine Tore, 6.4 hebt die Preise an).
5. **Prestige-Formel:** Mit Exponent 0,25 lohnen sich viele kleine Stürme nicht. Wer bei `minCrystals` stürmt, hat nach 8 Stunden 28 % weniger Kristalle als beim Sturm am Baumende, im empfohlenen Paket 48 % weniger. Die Formel kann bleiben. **Windkristalle lassen sich aber kaufen:** Bei gleicher Spielzeit hat ein Spieler mit 2x-Pass oder dauerhaftem Münz-Boost nach 8 Stunden 1,66-mal so viele Kristalle, mit beidem 2,33-mal so viele. Das widerspricht dem Kommentar in `Logic/Wind`.

**Dringendste Vorschläge:** `maxCrystals` von 100.000 auf 5.000.000 setzen (behebt den einzigen echten Engpass). Die Werkzeugpreise anheben: Saugroboter auf 700.000, Großmaschine auf 30 Mio. Einen Ruinen-Ast mit 18 Knoten hinter der Ruinenkarte einbauen, damit die Läufe bis etwa 40 Stunden aktiv bei 6 bis 12 Minuten bleiben. Als Logik-Entscheidung: `runEarned` ohne den Münz-Faktor von Pass und Boost zählen. Details im Abschnitt "Vorschläge".

## Methode

- **Echte Module:** Das Skript lädt die Datentabellen unter `src/shared/Data` und rechnet mit den reinen Modulen `Collecting` (Sammeln, Tank, Verkauf, gemischter Tank), `TreePurchase` (Kaufprüfung und Reihenfolge), `TreeEffects`, `Zones` (Freischaltung), `FindRoll` und `Collection` (Funde, Duplikate, Set-Bonus), `Sandstorm` und `Wind` (Kristalle, Reset), `Perks` (2x-Pass, Münz-Boost, Großer Tank, Auto-Dig), `Offline` (Begleiter-Ertrag), `CrateRoll` (Pity) und `Profile.default`. Nichts davon ist nachgebaut.
- **Vorschläge nur im Speicher:** Varianten setzen Werte in den geladenen Tabellen (`withPatch`) und stellen sie danach wieder her. Das empfohlene Paket besteht `DataCheck.run()` (dieselbe Prüfung wie `tests/data.spec.luau`) ohne Fehler.
- **Engpass-Regel (Auftrag):** Eine Pause zwischen zwei Fortschritten (Kauf oder Sturm) über 10 min, wenn sie in den ersten 2 Stunden aktiver Spielzeit beginnt, sonst über 30 min. Eine offene Pause am Ende der Simulation zählt mit.
- `lune run tests/run`: 53 von 53 Testdateien bestehen, nichts unter `src/` und `tests/` wurde geändert.

## Annahmen

- **Schleife wie in den Paketen 1.6, 2.1 und 2.7:** Der Spieler sammelt, bis der Tank voll ist (Server-Takt 0,25 s, Halten wird aufgefrischt). Dann geht er 5 s zum Händler, verkauft, kauft und geht 5 s zurück. Verkaufen, Kaufen, Reisen und der Sturm selbst kosten keine Zeit.
- **Kaufregel wie im Lune-Test:** Er kauft immer den billigsten sichtbaren Knoten (`TreePurchase.visible(profile)[1]`), sonst spart er. Glück-Ast und Ruinenkarte werden mitgekauft.
- **Zone:** Nach jedem Kauf geht der Spieler in die freie Zone mit dem höchsten Sandfaktor.
- **Sturm "sinnvoll" (Strategie `stall`):** Er stürmt, sobald der Sturm möglich ist und entweder nichts mehr zu kaufen ist oder der nächste Knoten beim jetzigen Ertrag über 3 Minuten Sparen kostet. Mit dem heutigen Baum ist das genau das Baumende. Weitere Strategien stehen in Abschnitt 5.
- **Funde:** Die echte Sammelzeit aus `Collecting.takeFindSeconds` wird in Fenstern von 0,25 s gewürfelt wie auf dem Server. Seltenheit, Fundstück und Wert bestimmt `FindRoll.roll`, Duplikate bucht `Collection.record`. Das Wetter gilt so, wie es zu Beginn jeder Füllung ist.
- **Pässe:** 2x Münzen und Großer Tank wirken über `Perks.options`. "Münz-Boost dauerhaft" heißt, dass der Spieler den Boost vor jedem Verkauf nachkauft, sobald er abgelaufen ist (30 min echte Zeit für 49 Robux). Auto-Dig ist eine obere Schranke: Das Werkzeug sammelt schon auf dem Rückweg vom Händler.
- **Gelegenheitsspieler:** Er spielt 2 Sitzungen zu 10 min am Tag, dazwischen ist er offline (je 11:50 h, gekappt auf 4 h oder mit Auto-Dig auf 12 h). Er hat einen Begleiter (`companion_common_1`, +5 % Sammelrate), weil `Offline.apply` sonst nichts zahlt.
- **Nicht im Modell:** Daily Reward, Codes, Freunde-Bonus, Saison- und Event-Zone, Koloss, Kisten-Items außer dem Begleiter (keine Holzkisten gekauft) und Fehlbedienung. Der Laufweg von 5 s ist der wichtigste unsichere Wert: Bei 8 s dauert Lauf 1 im empfohlenen Paket 36:12 statt 28:21 min.

## 1. Heute: Meilensteine und Verdienstkurve

**Lauf 1 (aktive Spielzeit), Basis ohne Pässe:**

| Meilenstein | Zeit | Zeit seit dem vorigen Werkzeug |
| --- | --- | --- |
| Erstes Upgrade (`collect_rate_1`) | 0:20 | |
| Schaufel | 2:00 | 2:00 |
| Eimerkette, Oase frei | 7:10 | 5:10 |
| Mini-Bagger, Canyon frei, Sturm-Knopf | 10:10 | 3:00 |
| Saugroboter, Salzsee frei | 11:32 | **1:23** |
| Großmaschine | 12:34 | **1:02** |
| Äste fertig: Glück / Verkauf / Tank / Sammeln | 17:40 / 19:19 / 20:06 / 21:18 | |
| Baum fertig = erster Sandsturm (26 Kristalle) | 21:18 | |
| Ruinenstadt (Lauf 2, nach der Ruinenkarte) | 34:41 | |
| Sturm 2 / 3 / 5 / 10 | 35:41 / 46:54 / 1:03:08 / 1:30:26 | |
| Erstes fertiges Set | 18:02 (Startwerte 65 und 66: 34:26 und 5:05) | |
| Erstes bis viertes fertiges Set | 18:02, 1:10 h, 1:37 h, 1:43 h | |
| Erster Fund Selten / Episch / Legendär / Mythisch | 14:25 / 18:50 / 4:15 h / 4:50 h | |

Die Fundzeiten streuen stark mit dem Startwert. Legendär kam bei den Startwerten 64 bis 66 nach 3:19 bis 5:41 h, Mythisch einmal nach 4:50 h und zweimal nicht in 8 h.

**Zeit zwischen Käufen je Werkzeug und Zone, Lauf 1** (die Pause zählt zu der Phase, in der gespart wurde):

| Werkzeug (Zone) | Käufe | Mittlere Pause | Längste Pause | vor |
| --- | --- | --- | --- | --- |
| Hand (Dünenmeer) | 4 | 0:30 | 1:00 | `collect_tool_2` |
| Schaufel (Dünenmeer) | 7 | 0:44 | 1:15 | `collect_tool_3` |
| Eimerkette (Oase) | 8 | 0:23 | 0:47 | `sell_3` |
| Mini-Bagger (Canyon) | 4 | 0:21 | 0:42 | `collect_tool_5` |
| Saugroboter (Salzsee) | 7 | **0:09** | 0:14 | `sell_5` |
| Großmaschine (Salzsee) | 14 | 0:37 | 1:12 | `collect_rate_12` |

**Verdienst pro Minute je Phase (Münzen/min):**

| Werkzeug | Lauf 1 | Lauf 2 | Lauf 3 | Läufe 4 bis 10 | ab Lauf 11 |
| --- | --- | --- | --- | --- | --- |
| Hand | 52 | 80 | 103 | 198 | 4,5K |
| Schaufel | 292 | 482 | 693 | 1,3K | 17,9K |
| Eimerkette | 8,2K | 12,8K | 17,5K | 35,1K | 608K |
| Mini-Bagger | 136K | 206K | 277K | 589K | 9,1M |
| Saugroboter | 3,6M | 5,1M | 6,5M | 14,3M | 203M |
| Großmaschine | 230M | 627M | 1B | 1,9B | 27,4B |

Suffixe wie im Spiel: K = Tausend, M = Million, B = Milliarde, T = Billion, Qa = Billiarde.

**Wo das Einkommen stockt:** Innerhalb eines Laufs nie vor dem Baumende. Am Baumende jedes Laufs hört der Fortschritt auf, und dort stürmt der Spieler (heute kommt beides auf dieselbe Minute). Dauerhaft stockt es nur an der Kristall-Obergrenze (Abschnitt 2).

**Läufe (Basis, 8 h aktiv):**

| Lauf | 1 | 2 | 3 | 5 | 10 | 20 | 50 | 100 | 150 | 200 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Dauer | 21:18 | 14:23 | 11:13 | 7:46 | 4:48 | 2:43 | 2:07 | 2:05 | 1:30 | 1:09 |
| Kristalle gesamt | 26 | 56 | 88 | 146 | 308 | 681 | 1.579 | 3.374 | 5.577 | 7.977 |

Die Einnahmen am Baumende liegen meist bei 2 bis 12 Mrd. (gleiche Knotenpreise), darum bringt fast jeder Sturm 26 bis 42 Kristalle. Der Bonus wächst um +60 % je Lauf, die Laufdauer teilt sich etwa durch (1 + Bonus). Das bestätigt Befund 4 aus `docs/balance/sandstorm_2_7.md`. Neu ist die Untergrenze: Etwa 1 Minute je Lauf, weil am Ende nur noch der Weg zählt. Damit wachsen die Kristalle linear um rund 1.900 je Stunde.

## 2. Engpässe

| Stelle | Heute | Bewertung |
| --- | --- | --- |
| Pausen in den ersten 2 h | längste 1:15 (Lauf 1 vor der Eimerkette) | in Ordnung |
| Pausen ab 2 h | längste 0:36 | in Ordnung, eher zu wenig Reibung |
| Kristall-Obergrenze | ab 34:47 h aktiv kein Sturm mehr möglich, danach 45:13 h ohne einen Kauf (80-h-Lauf) | **echter Engpass**, dauerhaft |
| Lauf unter 5 min | ab 1:26 h aktiv | kein Engpass, aber der Sturm wird bedeutungslos |
| Werkzeuge 4 bis 6 | 1:23 und 1:02 min Abstand, dann 8:43 min Großmaschine | Taktproblem |

Die 35 Stunden sind bei 15 min am Tag etwa 140 Tage. Ein Vielspieler mit 2 Stunden am Tag erreicht die Grenze nach 2,5 Wochen und kann dann nie wieder stürmen. Der Kommentar in `Economy.sandstorm` ("erst bei etwa 3,9 × 10^23 Münzen im Lauf erreicht") gilt für einen einzelnen Sturm. Die Grenze kappt aber die **gehaltenen** Kristalle, und die wachsen über viele Stürme.

## 3. 2x Münzen, Münz-Boost, Auto-Dig, Großer Tank

Je 8 h aktiv, Sturm "sinnvoll":

| Szenario | Schaufel | Eimerkette | Mini-Bagger | Großmaschine | Baum fertig / Sturm 1 | Stürme | Kristalle 1 h / 2 h / 8 h | Faktor 8 h |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Basis | 2:00 | 7:10 | 10:10 | 12:34 | 21:18 (26) | 221 | 116 / 563 / 8.649 | x1,00 |
| 2x Münzen | 1:10 | 4:07 | 5:44 | 7:01 | 11:49 (27) | 293 | 376 / 1.175 / 14.237 | x1,65 |
| Münz-Boost dauerhaft (16 Boosts, 784 Robux) | 1:10 | 4:07 | 5:44 | 7:01 | 11:49 (27) | 293 | 376 / 1.175 / 14.237 | x1,65 |
| Münz-Boost einmal (30 min, 49 Robux) | 1:10 | 4:07 | 5:44 | 7:01 | 11:49 (27) | 232 | 232 / 781 / 9.070 | x1,05 |
| 2x Münzen + Boost dauerhaft | 0:50 | 2:09 | 3:06 | 4:09 | 6:54 (29) | 384 | 678 / 2.357 / 20.146 | x2,33 |
| Auto-Dig (obere Schranke) | 1:40 | 5:30 | 7:45 | 9:14 | 15:56 (27) | 365 | 238 / 1.053 / 14.545 | x1,68 |
| Großer Tank | 1:55 | 6:19 | 8:42 | 10:16 | 17:20 (27) | 187 | 189 / 634 / 7.458 | x0,86 |
| Alle Pässe + Boost | 0:35 | 1:46 | 2:39 | 3:01 | 5:37 (32) | 374 | 807 / 2.614 / 22.023 | x2,55 |

- 2x Münzen halbiert den ersten Lauf fast (11:49 statt 21:18 min), wie in Paket 2.1. Das erste Upgrade bleibt bei 20 s, weil der erste Verkauf es bestimmt.
- Großer Tank verlängert die frühen Läufe (erstes Upgrade 35 s statt 20 s, weil der erste Verkauf später kommt) und bringt langfristig sogar weniger Kristalle. Das liegt an der Laufzeit-Untergrenze: Mit doppeltem Tank dauert jeder Gang länger. Ein Problem ist das nicht, der Pass soll Wege sparen. Der Store-Text sollte aber keinen Tempo-Vorteil versprechen.
- Auto-Dig ist online hier eine obere Schranke. Nach Befund M2 aus dem Exploit-Review kann jeder Spieler online dauerhaft halten, der Pass wird nur über die Offline-Grenze verkauft.

## 4. Windkristalle über 2x-Pass und Münz-Boost

`Logic/Wind` sagt: Münzen aus anderen Quellen zählen nicht, "damit sich Kristalle nicht kaufen lassen". `Collecting.sell` bucht aber den Betrag **mit** dem Münz-Faktor über `Wind.credit` auf `runEarned`, und `Offline.apply` bucht mit dem 2x-Faktor (Exploit-Review, Balance-Punkt 2).

**Ein Sturm, gleiche Einnahmen ohne Faktor:**

| Einnahmen | x1 | x2 (Pass oder Boost) | x4 (beides) |
| --- | --- | --- | --- |
| 625M | 20 | 23 | 28 |
| 2,5B | 28 | 33 | 40 |
| 10B | 40 | 47 | 56 |
| 100B | 71 | 84 | 100 |

Der direkte Effekt je Sturm ist 2^0,25 = 1,19 und 4^0,25 = 1,41. Dazu kommt, dass die Läufe schneller gehen.

**Gleiche aktive Spielzeit (8 h), heutige Regel gegen die vorgeschlagene Regel "runEarned ohne Münz-Faktor":**

| Szenario | Regel | Kristalle 2 h | Kristalle 8 h | ggü. Basis |
| --- | --- | --- | --- | --- |
| Basis | - | 563 | 8.649 | x1,00 |
| 2x Münzen oder Boost dauerhaft | heute | 1.175 | 14.333 | x1,66 |
| 2x Münzen oder Boost dauerhaft | ohne Münz-Faktor | 920 | 10.320 | x1,19 |
| 2x + Boost | heute | 2.357 | 20.146 | x2,33 |
| 2x + Boost | ohne Münz-Faktor | 1.194 | 13.460 | x1,56 |

Auch mit der neuen Regel bleibt ein Vorsprung (x1,19 und x1,56), weil die Läufe schneller gehen. Die Kristalle für denselben Lauf sind dann aber gleich. Das Argument aus 2.7 ("Pass-Käufer hätten sonst weniger Kristalle") gilt nur pro Lauf, nicht pro Spielzeit: Bei gleicher Zeit liegen Pass-Käufer mit der neuen Regel immer noch vorn.

**Tank füllen, dann Boost kaufen (Review, Balance-Punkt 1):** Am Baumende von Lauf 1 ist ein voller Tank 342M wert, mit Boost 684M. Das ist etwa eine halbe Minute Ertrag, der Trick ist für Münzen harmlos. Für Kristalle ist er mit der heutigen Regel wirksam, mit der vorgeschlagenen Regel nicht mehr.

## 5. Kristallformel: viele kleine gegen wenige große Stürme

8 h aktiv, ohne Pässe, heutige Formel (Exponent 0,25, Faktor 4, Einheit 1 Mio., `minCrystals` 20):

| Strategie | Lauf 1 (Kristalle) | Stürme | Kristalle 2 h | Kristalle 8 h | mittlere Laufdauer ab Lauf 5 |
| --- | --- | --- | --- | --- | --- |
| Sofort bei `minCrystals` (20) | 18:07 (20) | 204 | 381 | 6.233 | 2:08 |
| Ab 25 Kristallen | 20:42 (25) | 215 | 522 | 8.158 | 2:01 |
| Ab 30 Kristallen | 23:20 (30) | 229 | 636 | 9.339 | 1:53 |
| **Baumende** | **21:18 (26)** | **221** | **563** | **8.649** | **1:57** |
| Baumende + 2 min | 23:20 (30) | 110 | 679 | 11.017 | 3:57 |
| Baumende + 5 min | 26:23 (33) | 60 | 539 | 6.640 | 7:16 |
| Baumende + 15 min | 36:33 (40) | 24 | 256 | 2.788 | 17:52 |
| Kristallraten-optimal | 24:51 (31) | 128 | 709 | 12.591 | 3:21 |

**Antwort auf den Hinweis aus dem Exploit-Review:** Ein Exponent unter 1 belohnt kleine Stürme hier nicht. Jeder Lauf hat einen festen Sockel (Hand bis Großmaschine, mindestens etwa 1 Minute Weg), und `minCrystals = 20` sperrt die ganz kleinen Stürme. Sofort stürmen bringt nach 8 Stunden 28 % weniger als das Baumende. Am meisten bringt es, 2 bis 3 Minuten nach dem Baumende zu stürmen (+27 % bis +46 %). Das ist ein kleiner Anreiz zum Weitersammeln und kein Zwang. Im empfohlenen Paket ist der Abstand größer: Sofort stürmen bringt 4.363 statt 8.345 Kristalle.

**Andere Exponenten** (Faktor so gewählt, dass Lauf 1 am Baumende gleich viele Kristalle bringt):

| Exponent / Faktor | Baumende, 8 h | Kristallraten-optimal, 8 h | Bewertung |
| --- | --- | --- | --- |
| 0,5 / 0,6 | 15.232 | 100.000 (Obergrenze nach weniger als 8 h) | Weitersammeln nach dem Baumende explodiert, wie in 2.7 |
| 0,4 / 1,25 | 11.066 | 41.951 | dasselbe Problem, etwas schwächer |
| **0,25 / 4 (heute)** | **8.649** | **12.591** | Optimum nahe am Baumende |
| 0,15 / 8,5 | 6.496 | 6.129 | kein Anreiz mehr für einen tieferen Lauf |

Fazit: Exponent 0,25, Faktor 4, Einheit 1 Mio. und `minCrystals` 20 bleiben. Das Problem der zusammenfallenden Läufe kommt nicht von der Formel, sondern von festen Knotenpreisen bei linear wachsendem Bonus.

## 6. Offline-Ertrag und Gelegenheitsspieler

2 Sitzungen zu 10 min am Tag, 14 Tage (Zeit: echte Tage / aktive Spielzeit):

| Szenario | Großmaschine | Sturm 1 (Kristalle) | Stürme in 14 d | Kristalle 14 d | Lauf 10 | Offline-Anteil der Einnahmen |
| --- | --- | --- | --- | --- | --- | --- |
| Ohne Begleiter | 0,5 d / 12:34 | 1,0 d / 21:18 (26) | 88 | 2.907 | 4:48 | 0 % |
| Mit Begleiter (4 h) | 0,5 d / 10:10 | 0,5 d / 17:14 (26) | 110 | 4.917 | 3:05 | 98 % |
| Begleiter + Auto-Dig (12 h) | 0,0 d / 9:01 | 0,5 d / 10:07 (70) | 191 | 8.756 | 2:47 | 98 % |
| Begleiter + 2x Münzen | 0,0 d / 6:54 | 0,5 d / 10:39 (80) | 179 | 8.399 | 2:02 | 96 % |

**Offline am Baumende, dann stürmen** (aktiver Spieler mit Begleiter): sofort 26 Kristalle, nach 4 h offline 72, nach 12 h offline (Auto-Dig) 94. Nach 5 Stürmen sind es 146, 693 und 968.

| `Economy.offline.rateFactor` | Offline-Anteil (14 d) | Kristalle 14 d | Sturm 1 nach 4 h offline am Baumende |
| --- | --- | --- | --- |
| 0,5 (heute) | 98 % | 4.917 | 72 |
| 0,25 | 92 % | 4.930 | 60 |
| 0,1 | 65 % | 4.215 | 49 |

Wer offline ist, verdient bei einem Gelegenheitsspieler fast alle Münzen. Weil die Kristalle aber vom Baumende abhängen, bleiben sie über 14 Tage fast gleich. "Am Baumende abmelden und morgen stürmen" ist eine gute tägliche Schleife und kein Engpass. Gelegenheitsspieler haben heute nach 14 Tagen (4,7 h aktiv) 88 bis 191 Stürme. Lauf 10 dauert nur noch 2 bis 5 Minuten, spätere Läufe 1 bis 2 Minuten. Gegen das Zusammenfallen hilft auch hier der Ruinen-Ast (Abschnitt 7). Eine Holzkiste bringt mit 1/3 Chance einen Begleiter, also im Mittel nach 3 Öffnungen (75K Münzen). Das ist ab dem Mini-Bagger kein Hindernis.

**Kisten (zur Vollständigkeit, unverändert):** Bis Legendär oder besser braucht die Goldkiste im Mittel 18,56 Öffnungen (Median 14, P90 43, garantiert bei 60). Die Epic-Pity hebt die Rate leicht an. Das sind 7.426 Gems, also 2.651 Robux mit dem größten Gem-Paket bis 3.639 Robux mit dem kleinsten. Mit 10er-Kistenpaketen sind es 6.750 Gems (2.410 bis 3.308 Robux). Das passt zu `docs/balance/crates_4_2.md`. Das Konzept nennt "etwa 20 Goldkisten, rund 8.000 Gems", die Zahl dort ist leicht zu hoch.

## 7. Vorschläge

### Datenänderungen (Entscheidung Mensch)

| Nr. | Datei | Wert | Alt | Neu | Warum |
| --- | --- | --- | --- | --- | --- |
| D1 | `src/shared/Data/Economy.luau` | `sandstorm.maxCrystals` | 100.000 | **5.000.000** | Heute ist ab etwa 35 h aktiv kein Sturm mehr möglich. 5 Mio. ist der Höchstwert, den DataCheck mit 200 bp erlaubt (`maxCrystals × windCrystalBonusBp ≤ 10^9`). Der Kommentar "erst bei 3,9 × 10^23 Münzen" ist dabei zu korrigieren: Die Grenze gilt für die gehaltenen Kristalle. |
| D2a | `src/shared/Data/Tools.luau` und `src/shared/Data/UpgradeTree.luau` (`collect_tool_5`) | Preis Saugroboter | 90.000 | **700.000** | Er kommt 6:24 statt 1:23 min nach dem Mini-Bagger. DataCheck verlangt in beiden Dateien denselben Preis. |
| D2b | dieselben, `collect_tool_6` | Preis Großmaschine | 1.100.000 | **30.000.000** | Sie kommt 4:46 statt 1:02 min nach dem Saugroboter, Lauf 1 dauert dann 28:21 statt 21:18 min. Die Werte nennt schon `skilltree_2_1.md`. |
| D3 | `src/shared/Data/UpgradeTree.luau` | Ruinen-Ast, 18 neue Knoten | - | siehe Tabelle unten | Der Baum wächst mit dem Bonus mit: Bis etwa 5,5 h aktiv dauert kein Lauf unter 5 min, Lauf 100 noch 8 bis 12 min. Heute ist Lauf 10 bei 4:48 und Lauf 100 bei 2:05. |
| bleibt | `Economy.sandstorm` | `crystalExponent` 0,25, `crystalScale` 4, `crystalUnit` 1 Mio., `minCrystals` 20 | | unverändert | Kleine Stürme lohnen sich nicht (Abschnitt 5). 0,4 oder 0,5 macht Weitersammeln nach dem Baumende übermächtig. |
| bleibt | `Economy.windCrystalBonusBp` | 200 | | unverändert, 100 als Hebel für den Playtest | Mit 100 bp und D1 bis D3 bleiben die Läufe bis 10 h aktiv über 5 min, aber jeder Sturm fühlt sich halb so stark an. Erst entscheiden, wenn Playtests zu kurze Läufe zeigen. |
| bleibt | `Economy.offline.rateFactor` | 0,5 | | unverändert (0,25 als Option) | Der Offline-Anteil ist hoch, die Kristalle ändern sich über 14 Tage aber kaum. 0,25 senkt vor allem den Sturm nach langer Abwesenheit (72 auf 60 Kristalle). |

**Ruinen-Ast (D3):** Alle Knoten nutzen vorhandene Wirkungen (`sellBonus`, `rateBonus`, `setTank`) in ihren Ästen. Sie stehen hinter `sandstorm_ruins` und sind in jedem Lauf neu zu kaufen. Die Preise wachsen je Knoten um den Faktor 2,7. Namen und Beschreibungen sind Platzhalter (für den `data-worker`). Neue IDs dürfen keine früher benutzten sein.

| ID | Ast | verlangt | Preis | Wirkung |
| --- | --- | --- | --- | --- |
| `ruins_sell_1` | sell | `sandstorm_ruins` | 1.000.000.000 | sellBonus 10000 (+100 %) |
| `ruins_collect_1` | collect | `sandstorm_ruins` | 2.700.000.000 | rateBonus 20000 (+200 %) |
| `ruins_tank_1` | tank | `sandstorm_ruins` | 7.300.000.000 | setTank 4.000.000 |
| `ruins_sell_2` | sell | `ruins_sell_1` | 20 Mrd. | sellBonus 10000 |
| `ruins_collect_2` | collect | `ruins_collect_1` | 53 Mrd. | rateBonus 20000 |
| `ruins_tank_2` | tank | `ruins_tank_1` | 140 Mrd. | setTank 10.000.000 |
| `ruins_sell_3` | sell | `ruins_sell_2` | 390 Mrd. | sellBonus 10000 |
| `ruins_collect_3` | collect | `ruins_collect_2` | 1 Bio. | rateBonus 20000 |
| `ruins_tank_3` | tank | `ruins_tank_2` | 2,8 Bio. | setTank 25.000.000 |
| `ruins_sell_4` | sell | `ruins_sell_3` | 7,6 Bio. | sellBonus 10000 |
| `ruins_collect_4` | collect | `ruins_collect_3` | 21 Bio. | rateBonus 20000 |
| `ruins_tank_4` | tank | `ruins_tank_3` | 56 Bio. | setTank 62.500.000 |
| `ruins_sell_5` | sell | `ruins_sell_4` | 150 Bio. | sellBonus 10000 |
| `ruins_collect_5` | collect | `ruins_collect_4` | 410 Bio. | rateBonus 20000 |
| `ruins_tank_5` | tank | `ruins_tank_4` | 1,1 Brd. | setTank 156.250.000 |
| `ruins_sell_6` | sell | `ruins_sell_5` | 3 Brd. | sellBonus 10000 |
| `ruins_collect_6` | collect | `ruins_collect_5` | 8 Brd. | rateBonus 20000 |
| `ruins_tank_6` | tank | `ruins_tank_5` | 22 Brd. | setTank 390.625.000 |

Exakte Preise: 1e9, 2,7e9, 7,3e9, 2,0e10, 5,3e10, 1,4e11, 3,9e11, 1,0e12, 2,8e12, 7,6e12, 2,1e13, 5,6e13, 1,5e14, 4,1e14, 1,1e15, 3,0e15, 8,0e15, 2,2e16. Ab 1e15 Münzen rundet der Zahlentyp kleine Preise (bekannt aus 1.6, harmlos). Die letzten Knoten erreicht in 40 h aktiv niemand, sie sind Reserve.

### Wirkung vorher und nachher

| Kennzahl | Heute | Empfehlung (D1 + D2 + D3) | Warum |
| --- | --- | --- | --- |
| Erstes Upgrade / Schaufel | 0:20 / 2:00 | 0:20 / 2:00 | Die frühen Knoten bleiben unverändert. |
| Eimerkette / Mini-Bagger | 7:10 / 10:10 | 7:10 / 10:10 | Die Preise bis zum Mini-Bagger bleiben gleich. |
| Saugroboter / Großmaschine | 11:32 / 12:34 | 16:33 / 21:19 | Jede Werkzeugphase dauert jetzt 3 bis 6,5 min statt 1 bis 9 min. |
| Lauf 1 (= Sturm 1) | 21:18 (26 Kristalle) | 28:21 (27) | Höhere Werkzeugpreise, die Kristalle bleiben gleich. |
| Längste Pause Lauf 1 | 1:15 | 1:15 | Die Werkzeugpreise erzeugen keine neue lange Pause. |
| Längste Pause bis 8 h | 1:15 | 3:46 (vor Ruinen-Knoten) | Das ist gewollt: Der Sturm lohnt, sobald der nächste Knoten mehr als 3 min Sparen kostet. |
| Lauf 2 / 5 / 10 / 30 / 100 | 14:23 / 7:46 / 4:48 / 2:37 / 2:05 | 20:53 / 12:10 / 7:26 / 7:30 / 12:04 (Startwert 65: 7:57) | Mit dem Ruinen-Ast wandert das Laufende mit dem Bonus mit. |
| Erster Lauf unter 5 min | 1:26 h aktiv | 5:31 h aktiv | wie oben |
| Stürme in 8 h / 40 h | 221 / 1.790 | 59 / 262 | Stürme bleiben ein Ereignis. |
| Kristalle nach 2 h / 8 h / 40 h | 563 / 8.649 / 99.991 | 484 / 8.345 / 81.526 | Ähnliche Menge, aber verteilt auf weniger und größere Stürme (27 bis 200 je Sturm). |
| Kein Sturm mehr möglich ab | 34:47 h aktiv | nicht in 40 h (Grenze 5 Mio.) | D1 |
| Engpässe nach der Regel des Auftrags | 1 (ab 35 h) | 0 | D1 |
| 2x Münzen: Baum fertig Lauf 1 | 11:49 | 15:16 | Der Pass bleibt stark, aber Saugroboter und Großmaschine sind auch mit Pass eigene Phasen. |
| Gelegenheitsspieler mit Begleiter, 14 Tage: Stürme / Lauf 10 | 110 / 3:05 | 45 / 6:13 | Auch bei 20 min am Tag bleibt jeder Lauf eine Sitzung lang. |
| Weg 8 s statt 5 s: Lauf 1 | - | 36:12 | Die Empfindlichkeit für den Laufweg bleibt bestehen und gehört in den Studio-Test. |

Startwerte 65 und 66: Lauf 1 27:37 bis 28:21 min, Kristalle nach 8 h 8.464 bis 8.672, nach 40 h 81.218 bis 81.608. Ein Engpass trat in keinem Lauf auf.

### Logik-Vorschläge (kein Datenwert, eigenes Paket, Entscheidung Mensch)

| Nr. | Stelle | Vorschlag | Warum |
| --- | --- | --- | --- |
| L1 | `Logic/Collecting.sell` (Buchung über `Wind.credit`), `Logic/Offline.apply` | `runEarned` zählt den Verkauf ohne Münz-Faktor (2x-Pass und Münz-Boost), `coins` weiter mit Faktor | Kristalle lassen sich sonst kaufen (x1,66 bei gleicher Spielzeit, x2,33 mit beidem). Mit L1 sind es x1,19 und x1,56, nur noch über schnellere Läufe. Es entspricht dem Kommentar in `Logic/Wind` und schließt Balance-Punkt 2 des Exploit-Reviews. Sturm-Vorschau (`Sandstorm.runTotal`, Tankwert) muss dieselbe Regel nutzen. |
| L2 | Sturm-Fenster (Client) und `Sandstorm.preview` | Hinweis "Sturm lohnt sich jetzt", wenn der nächste Knoten mehr als etwa 3 Minuten Ertrag kostet | Mit dem Ruinen-Ast gibt es praktisch kein Baumende mehr. Ein Spieler, der auf das Baumende wartet, stürmt in 8 Stunden genau einmal (Simulation "Baumende" im Paket: 1 Sturm, 27 Kristalle). |
| L3 | Langfristig: Knotenpreise des Ruinen-Asts mit der Zahl der Stürme skalieren, oder Kristalle nur für Einnahmen über dem bisher besten Lauf | Der Ruinen-Ast verschiebt das Zusammenfallen der Läufe nur nach hinten (ab etwa 40 h aktiv). Eine Dauerlösung braucht eine Regel, nicht nur Zahlen. |
| L4 | `Sandstorm.preview` an der Obergrenze | Bei gehaltenen Kristallen nahe `maxCrystals` den Sturm ohne Kristalle erlauben oder "Maximum erreicht" zeigen | Mit D1 nicht mehr dringend, aber die Sperre wäre bei einer späteren Absenkung wieder da (`tests/sandstorm.spec.luau` prüft heute "tooFew" an der Grenze). |

### Folgen für Tests und Dokumente, falls D1 bis D3 übernommen werden

- `tests/skilltree.spec.luau`, `SIM.toolSeconds`: `collect_tool_5` von 10:47 auf etwa 16:33 (993 s) und `collect_tool_6` von 11:49 auf etwa 21:19 (1.279 s). `maxGapSeconds` 120 hält weiter (längste Pause 1:15).
- `docs/konzept.md`: In der Werkzeugtabelle stehen die Preise 90.000 und 1.100.000. In der Kistenrechnung steht "etwa 20 Goldkisten, rund 8.000 Gems", richtig sind 18,6 Goldkisten und 7.426 Gems.
- `docs/architektur.md` (Sandsturm, Werte): `maxCrystals` und die Bedeutung "gehaltene Kristalle".
- Neue Ruinen-Knoten: Testfälle in `docs/testfaelle.md` (sichtbar erst nach `sandstorm_ruins`, Sturm setzt sie zurück, DataCheck grün).

## Studio-Checkliste (für den Playtest nach einer Entscheidung)

- Laufweg zum Händler im echten Level messen, das Skript mit dem gemessenen Wert laufen lassen (`WALK` oben im Skript).
- Lauf 1 ohne Pass: Saugroboter nach etwa 16 bis 17 min, Großmaschine nach etwa 21 min, erster Sturm nach etwa 28 min.
- Lauf 2: Ruinenkarte, danach die Ruinen-Knoten sichtbar. Der Sturm fühlt sich nach etwa 20 min sinnvoll an.
- Sturm-Fenster: Ist klar, wann ein Sturm sich lohnt (L2)?


## Entscheidung und Stand

Umgesetzt: D1 (`maxCrystals` 5.000.000) und D2 (Saugroboter 700.000, Großmaschine 30.000.000, in `Tools.luau` und `UpgradeTree.luau`), dazu die Zielzeiten in `tests/skilltree.spec.luau` (Saugroboter 16:33, Großmaschine 21:19) sowie `konzept.md` und `architektur.md`. Alle 53 Testdateien bestehen.

Nicht umgesetzt: D3 (Ruinen-Ast, 18 neue Knoten mit Namen und Texten) und L1 bis L4. Sie ändern das Spielgefühl nach etwa 5 Stunden aktiv und brauchen zuerst den Studio-Test des Laufwegs (`WALK`) und Waltuhs Entscheidung.
