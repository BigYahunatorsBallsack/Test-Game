# Paket 4.2: Kisten-Quoten mit Pity

Stand 19.11.2026, Paket 4.2, `balance-analyst`. Das Skript steht in `docs/balance/crates_4_2.py` (nur Standardbibliothek, Aufruf `python3 docs/balance/crates_4_2.py`, Laufzeit etwa 1 s, Ausgabe reproduzierbar, Simulations-Seed 4200). Spieldaten wurden nicht geändert.

## Annahmen

- **Quoten:** `src/shared/Data/Crates.luau` von heute, in Hundertstel-Prozent. Gold: Ungewöhnlich 4000, Selten 4000, Episch 1500, Legendär 450, Mythisch 50 (Gewöhnlich 0).
- **Pity (Plan, "Quoten, Pity und Zufall"):** Zähler `sinceEpic` (e) und `sinceLegendary` (l). Bei l = 59 gilt nur Legendär:Mythisch = 450:50. Sonst gilt bei e = 14 nur Episch:Legendär:Mythisch = 1500:450:50. Greifen beide, gewinnt die Legendär-Garantie. Legendär oder Mythisch setzt beide Zähler auf 0, Episch nur e, alles andere zählt beide hoch.
- **Methode:** exakte Markov-Kette über (e, l) mit `fractions.Fraction`. Jeder Legendär-oder-besser-Treffer setzt auf (0, 0) zurück. Ein Zyklus dauert also höchstens 60 Öffnungen, und die stationären Raten sind die Erwartung je Zyklus geteilt durch die mittlere Zykluslänge (Erneuerungstheorie). Die Wartezeiten kommen aus der Rückwärtsrekursion h(e, l). Die Simulation ist nur Gegenprobe.
- **"Stationär"** heißt: ein Spieler, der schon lange Goldkisten öffnet. **"Frisch"** heißt: Zähler auf (0, 0), also ein neues Konto oder direkt nach einem Legendär-Treffer.
- **Preis:** 400 Gems je Goldkiste. Mit dem 10er-Paket (10 kaufen, 11 bekommen) kostet eine Öffnung 363,6 Gems. Jede Öffnung zählt für die Pity.

## (1) Effektive Wahrscheinlichkeit je Öffnung, Goldkiste

| Seltenheit | Tabelle | Mit Pity (exakt) | Faktor |
| --- | --- | --- | --- |
| Gewöhnlich | 0 % | 0 % | - |
| Ungewöhnlich | 40 % | 39,5588 % | 0,989 |
| Selten | 40 % | 39,5588 % | 0,989 |
| Episch | 15 % | 15,4955 % | 1,033 |
| Legendär | 4,5 % | 4,8481 % | 1,077 |
| Mythisch | 0,5 % | 0,5387 % | 1,077 |
| **Episch oder besser** | 20 % | **20,8823 %** | 1,044 |
| **Legendär oder besser** | 5 % | **5,3868 %** | 1,077 |

## (2) Erwartete Öffnungen bis zum Treffer (der Treffer zählt mit)

| Ziel | Ab frischem Zähler | Mittlerer Abstand (stationär) | Restwartezeit zu zufälligem Zeitpunkt | Ohne Pity |
| --- | --- | --- | --- | --- |
| Legendär oder besser | **18,564** | 18,564 | 16,563 | 20 |
| Episch oder besser | **4,824** | 4,789 | 4,426 | 5 |
| Mythisch | 185,64 | 185,64 | - | 200 |

- Bei Legendär+ ist der Wert ab frischem Zähler gleich dem stationären Abstand, weil jeder Treffer die Kette auf (0, 0) zurücksetzt. Bei Episch+ ist der stationäre Abstand etwas kürzer, weil die Legendär-Garantie bei l = 59 auch als Episch+ zählt.
- Mythisch kommt genau 10-mal seltener als Legendär+, weil das Verhältnis Legendär zu Mythisch in jedem Wurf (normal und beide Garantien) 9:1 ist.
- Verteilung der Öffnungen bis Legendär+ ab frischem Zähler: Median 14, 75 % bis 26, 90 % bis 43, 95 % bis 56. 54,6 % treffen innerhalb der ersten 15 Öffnungen, 4,11 % erst mit der harten Pity bei der 60. Öffnung. Standardabweichung 15,9.

## (3) Gems bis Legendär oder besser

| Größe | Wert |
| --- | --- |
| Erwartet, Einzelkauf (18,564 × 400) | **7.426 Gems** |
| Erwartet, nur 10er-Pakete (18,564 × 363,6) | 6.750 Gems |
| Konzept ("etwa 20 Goldkisten, rund 8.000 Gems") | 20 Kisten, 8.000 Gems |
| Abweichung Ist gegen Konzept | -1,44 Kisten, -574 Gems (-7,2 %) |
| Median (14 Öffnungen) | 5.600 Gems |
| Schlimmster Fall Legendär+ (60 Öffnungen) | 24.000 Gems einzeln, 22.000 Gems mit 5 Paketen + 5 einzeln |
| Schlimmster Fall Episch+ (15 Öffnungen) | 6.000 Gems einzeln, 5.600 Gems mit 1 Paket + 4 einzeln |

## (4) Wie oft löst die Pity den Treffer aus (stationär)

| Größe | Wert |
| --- | --- |
| Öffnungen mit aktiver Legendär-Garantie (l = 59) | 0,222 % |
| Öffnungen mit aktiver Episch-Garantie (e = 14, l < 59) | 0,881 % |
| Öffnungen mit irgendeiner Garantie | **1,103 %** |
| Legendär+-Treffer aus der Legendär-Garantie | 4,11 % |
| Legendär+-Treffer aus der Episch-Garantie (dort 25 % statt 5 %) | 4,09 % |
| Legendär+-Treffer aus dem normalen Wurf | 91,80 % |
| Episch+-Treffer aus einer Garantie (Episch 4,22 % + Legendär 1,06 %) | 5,28 % |
| Netto von der Pity erzeugt: Legendär+ (Rate mit Pity minus Tabelle) | 0,387 Prozentpunkte = 7,2 % aller Legendär+ |
| Netto von der Pity erzeugt: Episch+ | 0,882 Prozentpunkte = 4,2 % aller Episch+ |

**Welche Garantie wie viel bewirkt:**

| Variante | P(Episch+) | P(Legendär+) | Öffnungen bis L+ | Gems bis L+ |
| --- | --- | --- | --- | --- |
| Ohne Pity (reine Tabelle) | 20,000 % | 5,000 % | 20,00 | 8.000 |
| Nur Legendär-Pity (60) | 20,203 % | 5,241 % | 19,08 | 7.631 |
| Nur Episch-Pity (15) | 20,729 % | 5,182 % | 19,30 | 7.719 |
| Beide (Ist) | 20,882 % | 5,387 % | 18,56 | 7.426 |

## (5) Holz- und Eisenkiste (ohne Pity, reine Tabelle)

| Kiste | Gew. / Ungew. / Selten / Episch / Leg. / Myth. | Selten oder besser | Episch | Legendär+ |
| --- | --- | --- | --- | --- |
| Holz (25.000 Münzen) | 60 / 30 / 9 / 1 / 0 / 0 % | 10 %: 10 Öffnungen = 250.000 Münzen | 1 %: 100 Öffnungen = 2,5 Mio. Münzen | nicht erreichbar |
| Eisen (100 Gems) | 35 / 40 / 20 / 5 / 0 / 0 % | 25 %: 4 Öffnungen = 400 Gems | 5 %: 20 Öffnungen = 2.000 Gems | nicht erreichbar |

Wahrscheinlichkeit für mindestens ein Episch: Holz 9,6 % in 10, 39,5 % in 50 und 63,4 % in 100 Öffnungen. Eisen 40,1 % in 10, 92,3 % in 50 und 99,4 % in 100 Öffnungen.

## Gegenprobe: Simulation (1.000.000 Öffnungen, Seed 4200)

Die Simulation würfelt wie der Server eine Ganzzahl über die Hundertstel-Prozent-Gewichte (1 bis 10000, bei Garantie 1 bis 500 bzw. 1 bis 2000). Der Standardfehler kommt aus 100 Blöcken zu je 10.000 Öffnungen.

| Größe | Exakt | Simulation | Abweichung | z |
| --- | --- | --- | --- | --- |
| Ungewöhnlich | 39,5588 % | 39,6408 % | +0,082 pp | +1,74 |
| Selten | 39,5588 % | 39,4886 % | -0,070 pp | -1,53 |
| Episch | 15,4955 % | 15,4775 % | -0,018 pp | -0,59 |
| Legendär | 4,8481 % | 4,8469 % | -0,001 pp | -0,07 |
| Mythisch | 0,5387 % | 0,5462 % | +0,008 pp | +1,04 |
| Legendär oder besser | 5,3868 % | 5,3931 % | +0,006 pp | +0,34 |
| Öffnungen bis Legendär+ (53.931 Zyklen) | 18,564 | 18,542 | -0,022 | -0,32 |
| Öffnungen bis Episch+ ab frisch | 4,824 | 4,832 | +0,008 | - |
| Längster Abstand Legendär+ / Episch+ | höchstens 60 / 15 | 60 / 15 | - | - |

Alle Abweichungen liegen unter 2 Standardfehlern. Die Simulation bestätigt die exakte Rechnung.

## Erwartete Raten mit Pity (Sollwerte für Lune)

Goldkiste und Event-Kiste mit Pity 15/60. Die Werte gelten für viele Öffnungen am Stück ab frischem Zähler (der Einschwingfehler ab (0, 0) ist nach wenigen Zyklen vernachlässigbar). Die Toleranz entspricht etwa 5 Standardfehlern bei 1.000.000 Öffnungen. Lune nutzt einen anderen Zufallsgenerator, deshalb mit Toleranz prüfen, nicht auf Gleichheit.

| Größe | Sollwert | Toleranz bei 1 Mio. Öffnungen |
| --- | --- | --- |
| P(Gewöhnlich) | 0 | genau 0 |
| P(Ungewöhnlich) | 0,395588 | ± 0,0025 |
| P(Selten) | 0,395588 | ± 0,0025 |
| P(Episch) | 0,154955 | ± 0,0016 |
| P(Legendär) | 0,048481 | ± 0,0009 |
| P(Mythisch) | 0,005387 | ± 0,0004 |
| P(Episch oder besser) | 0,208823 | ± 0,0016 |
| P(Legendär oder besser) | 0,053868 | ± 0,0010 |
| Öffnungen bis Legendär+ (Mittel) | 18,5639 | ± 0,35 |
| Öffnungen bis Episch+ ab frisch (Mittel) | 4,8241 | ± 0,09 |
| Längster Abstand ohne Legendär+ / ohne Episch+ | 60 / 15 | darf nie überschritten werden |

Bei 100.000 Öffnungen sind die Toleranzen etwa 3,2-mal so groß. Die Standardabweichung der Legendär+-Rate ist dann 0,063 statt 0,020 Prozentpunkte.

## Fazit

- **Konzeptaussage passt nicht ganz.** "Etwa 20 Goldkisten, rund 8.000 Gems" ist genau der Wert der reinen Tabelle ohne Pity (1 / 5 %). Mit beiden Garantien sind es 18,56 Kisten und 7.426 Gems, also 7,2 % weniger. Als Rundung ("etwa 20") ist das vertretbar. Für den Shop-Text ("Kosten bis zur Pity-Garantie", Erwartungswert) wäre "im Schnitt nach etwa 19 Goldkisten, rund 7.400 Gems" genauer. Die Tabelle muss dafür nicht geändert werden, nur die Aussage im Konzept (Entscheidung beim Nutzer).
- **Die Pity hebt die Rate nur mäßig.** Legendär+ steigt von 5,00 % auf 5,39 % (Faktor 1,077), Episch+ von 20,0 % auf 20,9 % (Faktor 1,044). Nur 1,1 % aller Öffnungen laufen unter einer Garantie. Die Pity begrenzt also vor allem das Pech (höchstens 60 bzw. 15 Öffnungen) und verändert kaum den Schnitt.
- **Auffällig: Die Episch-Garantie trägt etwa die Hälfte zum Legendär-Plus bei.** Eine Garantie-Öffnung bei e = 14 ergibt in 25 % der Fälle Legendär+ statt in 5 %. Dadurch kommen 4,09 % aller Legendär+-Treffer aus der Episch-Garantie, fast so viele wie aus der harten Legendär-Garantie (4,11 %). Das ist regelkonform, sollte aber bewusst so gewollt sein. Wer die Episch-Garantie auf "nur Episch" beschränken wollte, müsste die Regel im Plan ändern, nicht die Tabelle.
- **Die harte Pity greift selten, aber spürbar.** 4,1 % der Zyklen enden erst bei der 60. Öffnung (24.000 Gems einzeln). Das 95-%-Quantil liegt bei 56 Öffnungen. Diese Spanne sollte der Shop neben dem Erwartungswert ehrlich zeigen.
- **Event-Kiste:** Sie hat dieselbe Pity wie die Goldkiste (15/60, eigener Zähler `pity.event`); `Crates.luau` ist angeglichen. Für sie gelten die Gold-Werte oben.
- **Holz und Eisen** sind ohne Pity unauffällig. Episch kostet im Schnitt 2,5 Mio. Münzen (Holz) bzw. 2.000 Gems (Eisen). Legendär+ gibt es dort nicht, das passt zum Konzept ("Legendäres und Mythisches" nur in Gold und Event).
