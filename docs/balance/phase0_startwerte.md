# Phase 0: Fehlende Startwerte

Stand 17.11.2026, Paket 0.1, `balance-analyst`. Die Simulation steht in `docs/balance/phase0_startwerte.py` (nur Standardbibliothek, Aufruf `python3 docs/balance/phase0_startwerte.py`, feste Seeds). Alle Zahlen sind Startwerte für den ersten Playtest.

## Vorschlag

Vorher war keiner dieser Werte festgelegt, die Spalte "Vorher" entfällt deshalb.

| Wert | Vorschlag | Begründung |
| --- | --- | --- |
| `baseCoinsPerSand` | 1 | Mit 2 Münzen pro Sand käme die Schaufel schon nach 1:10 min statt nach 2:00 min, 1 Münze trifft das Ziel genau. |
| `startTankCapacity` | 15 | Bei 1 Sand/s ist der erste Tank nach 15 s voll, nach 5 s Weg ist der erste Verkauf bei 20 s und deckt genau das erste Upgrade (15 Münzen). |
| `findChancePerSecond` | 0,02 | Bei 20 s Sammeln pro Lauf kommt im Schnitt alle 3 Läufe ein Fund (Monte Carlo: 3,01), und in den ersten 2 Minuten findet man mit 78 % mindestens ein Stück. |
| `bigTankMultiplier` | 2 | Doppelter Tank spart die Hälfte der Wege, verkürzt die Zeit bis zum Mini-Bagger um etwa 15 % und bleibt damit klar schwächer als 2x Münzen (etwa 45 %), passend zum halben Preis. |
| `findBaseValue` | 3 | Wenn ein Gewöhnlicher Fund 3 Sekunden Grundertrag wert ist, bringen Duplikate dauerhaft etwa 15 % des Ertrags, spürbar, aber nicht wichtiger als der Sand. |
| Skalierung des Fundwerts | Wert = `findBaseValue` × Sandfaktor der Zone × Grundrate des Werkzeugs (ohne Knoten-Boni) × Wertfaktor der Seltenheit | Skaliert der Wert nur mit dem Sandfaktor, fällt der Duplikat-Anteil von 17 % (Dünenmeer) auf 0,02 % (Salzsee), und Funde werden wertlos. |
| `zoneFindChanceFactor` Dünenmeer | 1,0 | Bezugswert, ein Fund etwa alle 3 Läufe. |
| `zoneFindChanceFactor` Oase | 1,2 | Leicht mehr als im Dünenmeer, Regen kommt als eigener, zeitweiser Faktor obendrauf. |
| `zoneFindChanceFactor` Canyon | 1,4 | Etwa alle 2,3 Läufe ein Fund passt zum Versprechen "tiefe Schichten mit seltenen Funden". |
| `zoneFindChanceFactor` Salzsee | 1,6 | Der Nebel soll Fundstellen verstecken, nicht die Chance senken, darum steigt der Faktor weiter. |
| `zoneFindChanceFactor` Ruinenstadt | 2,0 | Nach dem Sandsturm soll die Mythisch-Zone sich lohnend anfühlen: ein Fund etwa alle 1,8 Läufe. |
| Daily Tag 1 | 2x Münzen für 10 Minuten | Ein Boost wächst mit dem Spieler mit. Die Serie startet erst nach dem Kauf der Schaufel, sonst kommt die Schaufel schon nach 1:10 min. |
| Daily Tag 2 | 5 Gems | Ein kleiner Gem-Betrag zeigt die Premium-Währung, ohne eine Kiste zu verschenken. |
| Daily Tag 3 | 2x Münzen für 15 Minuten | Statt fester Münzen, weil feste Beträge später nichts wert sind und Beträge in "Minuten Ertrag" ganze Werkzeugstufen überspringen. |
| Daily Tag 4 | 10 Gems | Steigert die Serie und nähert sich den 100 Gems einer Eisenkiste. |
| Daily Tag 5 | Glücks-Boost für 15 Minuten (Fundchance x2) | Glück multipliziert nur die Chance, nicht die Verteilung, und es ist kein Kauf, also verträglich mit "Kein Zufall gegen Geld". |
| Daily Tag 6 | 20 Gems | Größter Gem-Schritt direkt vor der Eisenkiste, zusammen 35 Gems pro Woche. |
| Daily Tag 7 | Eisenkiste (Ersatz: festes Ausrüstungsstück) | Laut Konzept, unverändert. |
| `sammeln_1` | 15 Münzen, Sammelrate +50 % | Der erste Kauf bei 20 s soll sofort spürbar sein, von 1 auf 1,5 Sand/s. |
| `schaufel` | 50 Münzen, 5 Sand/s (Vorgabe) | Mit dem Baum unten fällt der Kauf auf genau 2:00 min. |
| `sammeln_2` | 120 Münzen, Sammelrate +25 % | Zweiter Schritt nach der Schaufel, gekauft bei 3:04 min. |
| `tank_1` | 20 Münzen, Tank 15 auf 30 | Zweiter Kauf bei 1:00 min, macht den Handlauf 30 s lang. |
| `tank_2` | 60 Münzen, Tank 30 auf 60 | Folgt 28 s nach der Schaufel, damit die Läufe nicht bei 14 s hängen bleiben. |
| `tank_3` | 250 Münzen, Tank 60 auf 150 | Bringt den Schaufellauf auf etwa 27 s, kurz vor der Eimerkette. |

Sammelrate-Knoten addieren Prozent auf die Grundrate des aktuellen Werkzeugs, damit sie über alle Werkzeuge hinweg wirken. Tank-Knoten setzen die neue Gesamtkapazität. Der Gamepass multipliziert sie danach.

## Annahmen

- **Laufweg zum Händler:** 5 s je Richtung, also 10 s Weg pro Durchlauf (etwa 80 Studs bei der Standard-WalkSpeed 16). Der Spieler startet am Sandfeld, der erste Hinweg entfällt. Verkaufen und Knotenkauf kosten keine Zeit.
- **Sandpreis:** Es zählt die Zone, in der gesammelt wurde. Der Spieler sammelt immer in der besten freigeschalteten Zone.
- **Spielweise:** Sammeln, bis der Tank voll ist, dann verkaufen. Nach jedem Verkauf kauft der Spieler den billigsten sichtbaren Knoten, solange das Geld reicht. Die Äste Sammeln und Tank sind je eine Kette. Verkauf und Glück sind nicht simuliert.
- **Platzhalter:** Ab `sammeln_3` und `tank_4` nutzt die Simulation eine Platzhalter-Leiter, nur um Eimerkette und Mini-Bagger zu erreichen: `sammeln_3` 300 (+25 %), `sammeln_4` 1.500 (+25 %), `sammeln_5` 3.500 (+25 %), `tank_4` 700 (400), `tank_5` 1.800 (900), `tank_6` 4.500 (1.800), `tank_7` 11.000 (5.000). Diese Werte gehören in Paket 2.1 oder 6.4, nicht in diesen Vorschlag.
- **Funde und Münzen:** In der Zeit-Simulation bringen Funde keine Münzen, weil frühe Funde fast immer neu sind und in die Sammlung gehen.
- **Funde pro Sekunde:** Der Server würfelt pro Sammelsekunde (oder rechnet bei Teilsekunden mit 1 − (1 − p)^dt). Gezählt wird nur echte Sammelzeit, nicht der Weg.
- **Auto-Dig:** Zusätzlich zum Halten nehmen wir an, dass das Werkzeug schon auf dem Weg zum Feld sammelt. Das ist eine obere Schranke. Wirkt Auto-Dig nur als "Taste halten", ändert es die Zeiten aktiver Spieler nicht.

## Simulierte Zeiten

| Variante | Upgrade 1 | Schaufel | Eimerkette (Oase) | Mini-Bagger (Canyon) |
| --- | --- | --- | --- | --- |
| **Basis (Vorschlag)** | **20 s** | **2:00 min** | **6:46 min** | **10:39 min** |
| Gamepass Großer Tank x2 | 35 s | 1:55 min | 5:31 min | 9:05 min |
| Gamepass 2x Münzen | 20 s | 1:10 min | 3:33 min | 5:50 min |
| Auto-Dig (obere Schranke) | 15 s | 1:35 min | 5:13 min | 8:20 min |
| 2x Münzen und Großer Tank | 35 s | 1:25 min | 3:39 min | 6:09 min |
| Daily Tag 1 als 100 Münzen beim Join | 20 s | 20 s | 5:09 min | 9:02 min |

**Kaufprotokoll Basis:** `sammeln_1` 0:20, `tank_1` 1:00, `schaufel` 2:00, `tank_2` 2:28, `sammeln_2` 3:04, `tank_3` 4:11, `sammeln_3` 5:06, `eimerkette` 6:46, danach bis zum Mini-Bagger alle 17 bis 78 s ein Kauf. Die längste Pause liegt mit 100 s vor der Eimerkette. Bis zum Mini-Bagger gibt es keinen Engpass.

**Durchlauflänge (Sammeln plus 10 s Weg):** Im Dünenmeer liegt der Median bei 20 s (14 bis 30 s), in der Oase bei 24 s (13 bis 39 s). Kürzer als 20 s sind die Läufe direkt nach einem neuen Werkzeug, weil die Rate um das Fünffache springt. Ein bis zwei Läufe später holt der nächste Tank-Knoten sie zurück ins Band. Dieser kurze Kraftschub nach dem Kauf ist gewollt.

**Empfindlichkeit Laufweg:** Bei 3 s je Richtung kommt die Schaufel nach 1:42 min, bei 8 s nach 2:27 min. Der Abstand vom Feld zum Händler in Paket 1.5 sollte also bei etwa 5 s Laufzeit liegen (60 bis 100 Studs).

## Befunde und Hinweise

- **Großer Tank verzögert den ersten Kauf:** Mit dem Pass ist der erste Tank erst nach 30 s voll. Der Händler sollte darum auch einen halbvollen Tank annehmen, und das Tutorial schickt beim ersten Mal schon bei 15 Sand zum Verkauf.
- **2x Münzen ist sehr stark:** Die Zeit bis zum Mini-Bagger halbiert sich fast (10:39 auf 5:50 min). Für 399 Robux ist das gewollt, sollte aber im Playtest gegen das Gefühl "ohne Pass zäh" geprüft werden.
- **Daily Reward:** Feste Münzen oder Münzen in "Minuten Grundertrag" brechen die Kurve, deshalb nur Boosts und Gems. 100 Münzen am ersten Tag beim Join überspringen die Schaufel-Phase komplett. Pro Woche gibt es 35 Gems plus eine Eisenkiste (100 Gems), also etwa 135 Gems Gegenwert. Belohnungen später zu erhöhen ist leichter, als sie zu kürzen.
- **Fundwert sichern:** Weil der Wert mit dem Werkzeug wächst, muss der Server ihn beim Fund festschreiben (oder das Duplikat sofort verkaufen). Sonst lohnt es sich, Duplikate zu horten und erst nach dem nächsten Werkzeug zu verkaufen.
- **Ruinenstadt nach dem Sandsturm:** Mit der Hand und ohne Knoten bringen Duplikate dort rechnerisch 39 % des Ertrags. Das ist nach einem Reset als Anschub in Ordnung, gehört aber in die Prüfung der Prestige-Formel (2.7, 6.4).
- **Erste Funde:** Ein Gewöhnlicher kommt im Schnitt nach 1,2 min Sammeln, ein Seltener nach 14 min, ein Epischer nach 52 min, ein Legendärer nach 4 h, ein Mythischer nach 28 h (Dünenmeer, ohne Glück). Der Starterpaket-Auslöser "erster Selten-Fund" fällt damit meist in die erste oder zweite Sitzung. Wer den ersten Fund sicher in den ersten 2 Minuten will, setzt ihn im Tutorial fest (heute 78 %).
- **Ausblick auf späte Stufen (für 6.4):** Gemessen am Grundertrag des Vorgängers in seiner besten Zone kosten die Werkzeuge 50 s (Schaufel), 120 s (Eimerkette), 100 s (Mini-Bagger), 60 s (Saugroboter) und nur 31 s (Großmaschine). Weil der Sandfaktor der Zonen mitwächst, wird der Fortschritt nach dem Mini-Bagger immer schneller. Entweder steigen die späten Werkzeugpreise (etwa Saugroboter 150.000, Großmaschine 3.500.000) oder die Zonen-Knoten im Baum werden teurer. Die Vorgaben bleiben hier unverändert.
- **Kontrolle Goldkiste:** Mit 5 % Legendär-oder-besser und Pity bei 60 braucht es im Schnitt 19,1 Kisten, also 7.631 Gems einzeln oder 6.938 Gems im 10er-Paket. Das passt zu den "etwa 20 Kisten, rund 8.000 Gems" im Konzept.

## Finale Werte

- `baseCoinsPerSand = 1`
- `startTankCapacity = 15`
- `findChancePerSecond = 0.02`
- `bigTankMultiplier = 2`
- `findBaseValue = 3`, Fundwert = `findBaseValue` × Sandfaktor der Zone × Werkzeug-Grundrate × Wertfaktor der Seltenheit, festgeschrieben beim Fund
- `zoneFindChanceFactor`: Dünenmeer 1,0, Oase 1,2, Canyon 1,4, Salzsee 1,6, Ruinenstadt 2,0
- Daily Reward: Tag 1 2x Münzen 10 min (Serie startet nach der Schaufel), Tag 2 5 Gems, Tag 3 2x Münzen 15 min, Tag 4 10 Gems, Tag 5 Glücks-Boost x2 15 min, Tag 6 20 Gems, Tag 7 Eisenkiste
- Skilltree: `sammeln_1` 15 Münzen (+50 % Rate), `schaufel` 50, `sammeln_2` 120 (+25 % Rate), `tank_1` 20 (Tank 30), `tank_2` 60 (Tank 60), `tank_3` 250 (Tank 150)
