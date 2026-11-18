# Paket 2.7: Sandsturm (Prestige) und Windkristalle

Stand 18.11.2026, Paket 2.7, `balance-analyst`. Die Simulation steht in `docs/balance/sandstorm_2_7.py` (nur Standardbibliothek, feste Seeds ab 2700, Aufruf `python3 docs/balance/sandstorm_2_7.py`, Laufzeit etwa 2 s). Sie importiert Baum, Schleife und Kaufregel aus `skilltree_2_1.py` sowie Funde, Duplikate und Sammlung aus `collection_2_6.py`. Alle Zahlen sind Startwerte für den Playtest.

## Vorschlag

| Wert | Vorher (Startvorschlag) | Nachher | Begründung |
| --- | --- | --- | --- |
| `crystalUnit` | 1 Mio. | **1 Mio.** | Bleibt: Unter 1 Mio. Münzen im Lauf gibt es 0 Kristalle, ein Sturm direkt nach dem Mini-Bagger (26.106 Münzen) ist damit `tooFew`. |
| `crystalExponent` | 0,5 | **0,25** | Mit 0,5 lohnt es sich, nach dem Baumende 14 min bei stehendem Einkommen weiterzusammeln, mit 0,25 ist das Baumende der beste Sturmzeitpunkt. |
| `crystalScale` | 1 | **4** | Gleicht den kleineren Exponenten aus: 27 statt 6 Kristalle am Baumende des ersten Laufs, die Einheit bleibt bei 1 Mio. |
| `maxCrystals` | keine | **100.000** je Sturm | Schutz gegen Überlauf, wird erst bei 3,9 × 10^23 Münzen im Lauf erreicht, also nie im normalen Spiel. |
| `minCrystals` | keine (1) | **20** | Der Knopf erscheint erst, wenn ein Sturm höchstens etwa 6 % schlechter ist als der Sturm am Baumende (Befund 2). |
| `sandstorm_ruins` (Münzen) | 500 Mio. (Platzhalter) | **250 Mio.** | Wird nach der Großmaschine und nach `collect_rate_11` gekauft, kostet 32 s Ertrag und macht den Lauf 59 s kürzer. 500 Mio. kommt erst als vorletzter Knoten. |

**Formel:** Kristalle = min(100.000, floor(4 × (runEarned / 1 Mio.)^0,25)). Werte: 1 Mio. ergibt 4, 625 Mio. ergibt 20, 1 Mrd. ergibt 22, 2,14 Mrd. (Baumende Lauf 1) ergibt 27, 10^12 ergibt 126, 10^18 ergibt 4.000.

## Annahmen

- **Baum:** `UpgradeTree.luau` von heute (ohne Tore, Entscheidung vom 18.11.) plus `sandstorm_ruins` (requires `sandstorm_1`, `collect_tool_5`). Die Fassung mit Toren (Ziel von Paket 6.4) ist als Gegenprobe mitgerechnet.
- **Schleife und Kaufregel wie in 2.1 und 2.6:** sammeln bis der Tank voll ist, 5 s Weg je Richtung, billigster sichtbarer Knoten (Glück-Ast eingeschlossen), sonst sparen. Der Spieler sammelt in der Zone mit dem höchsten Sandfaktor, ab der Ruinenkarte also in der Ruinenstadt (x150).
- **Kristalle:** +2 % je Kristall als Faktor auf Sandpreis und Fundwert, multipliziert mit Verkauf-Ast und Sammlungsbonus. `runEarned` zählt Sandverkäufe (mit allen Faktoren, auch 2x Münzen) und verkaufte Duplikate.
- **Sturm:** setzt Münzen, Tank, Knoten, Werkzeug und Zonen zurück. `sandstorm_1`, Funde und Set-Bonus bleiben. Der Sturm selbst kostet keine Zeit, der neue Lauf startet am Feld im Dünenmeer.
- **Funde:** Modell aus 2.6 (Layout V1 wie in `Finds.luau`, Set-Bonus aus `Collection.luau`), ein fester Seed je Lauf (2700 + Laufnummer).
- **Spielzeit:** 15 min pro Tag wie in 2.6. "Tage" ist die Summe der Laufdauern geteilt durch 15 min.
- **Strategien:** Sturm ab einer festen Kristallzahl X (1, 10, 20), Sturm am Baumende (letzter Knoten gekauft) und "kristallraten-optimal": Je Lauf wird der Gang gewählt, an dem Kristalle pro Laufminute am höchsten sind (gierige Obergrenze für Spieler, die nach dem Baumende weiterspielen).

## Läufe 1 bis 10 mit dem Vorschlag

**Sturm am Baumende** (Bonus nur aus Kristallen, der Sammlungsbonus steigt zusätzlich von 0 % in Lauf 1 auf 16 % in Lauf 10):

| Lauf | Dauer | Kristalle | Summe | Bonus | Münzen/s Mittel | Münzen/s Ende | Ruinenkarte | Tage gesamt |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 21:41 | 27 | 27 | +54 % | 1,65 Mio. | 8,26 Mio. | - | 1,4 |
| 2 | 13:39 | 30 | 57 | +114 % | 4,21 Mio. | 47,8 Mio. | 12:35 | 2,4 |
| 3 | 10:22 | 32 | 89 | +178 % | 7,08 Mio. | 68 Mio. | 9:17 | 3,0 |
| 4 | 8:12 | 28 | 117 | +234 % | 5,08 Mio. | 56 Mio. | 7:44 | 3,6 |
| 5 | 6:46 | 28 | 145 | +290 % | 6,5 Mio. | 69,2 Mio. | 6:17 | 4,0 |
| 6 | 6:16 | 29 | 174 | +348 % | 8,25 Mio. | 83 Mio. | 5:48 | 4,5 |
| 7 | 5:19 | 32 | 206 | +412 % | 12,95 Mio. | 121 Mio. | 4:50 | 4,8 |
| 8 | 5:12 | 33 | 239 | +478 % | 15,54 Mio. | 144 Mio. | 4:44 | 5,2 |
| 9 | 4:58 | 38 | 277 | +554 % | 29,77 Mio. | 202 Mio. | 4:17 | 5,5 |
| 10 | 4:36 | 40 | 317 | +634 % | 36,22 Mio. | 229 Mio. | 3:56 | 5,8 |

**Alle Strategien, 10 Läufe:**

| Strategie | Lauf 1 | Lauf 2 | Lauf 10 | Kristalle nach 10 Läufen | Spielzeit (Tage) | Kristalle pro Stunde |
| --- | --- | --- | --- | --- | --- | --- |
| Früh: erster Kristall (4 bei 12:09) | 12:09 | 11:39 | 7:27 | 40 (+80 %) | 1:32 h (6,2) | 26 |
| Schwelle 10 | 14:08 | 12:07 | 6:06 | 100 (+200 %) | 1:27 h (5,9) | 68 |
| Schwelle 20 (= `minCrystals`) | 18:08 | 13:53 | 4:46 | 210 (+420 %) | 1:29 h (6,0) | 141 |
| **Baumende** | **21:41** | **13:39** | **4:36** | **317 (+634 %)** | **1:27 h (5,8)** | **219** |
| Kristallraten-optimal | 24:13 | 17:10 | 4:56 | 450 (+900 %) | 1:36 h (6,5) | 279 |
| Startvorschlag, Baumende | 21:41 | 12:38 | 3:44 | 679 (+1.358 %) | 1:16 h (5,1) | 535 |
| Startvorschlag, optimal | 35:53 | 17:15 | 4:08 | 3.494 (+6.988 %) | 1:32 h (6,2) | 2.257 |

**Früher Sturm gegen Baumende im ersten Lauf** (danach Lauf 2 bis zum Baumende):

| Sturm in Lauf 1 bei | Lauf 1 | Kristalle | Lauf 2 | Kristalle nach 2 Läufen | Kristalle pro Minute |
| --- | --- | --- | --- | --- | --- |
| Direkt nach `collect_tool_4` | 10:08 | 0 (`tooFew`) | - | - | - |
| Erster Kristall | 12:09 | 4 | 19:35 | 34 | 1,07 |
| 10 Kristalle | 14:08 | 10 | 17:41 | 40 | 1,26 |
| 20 Kristalle | 18:08 | 20 | 15:39 | 50 | 1,48 |
| **Baumende** | **21:41** | **27** | **14:20** | **57** | **1,58** |
| Baumende + 5 min | 26:45 | 33 | 13:41 | 64 | 1,58 |
| Baumende + 15 min | 36:53 | 40 | 12:29 | 71 | 1,44 |

**Prüfpunkte:**

- **Erstes Upgrade:** in jedem Lauf nach 20 s (erster Verkauf), die Schaufel nach 2:00 (Lauf 1), 1:10 (Lauf 2 und 3), 0:50 (ab Lauf 4).
- **Pausen zwischen Käufen:** längste Pause 75 s in Lauf 1 (vor der Eimerkette, wie in 2.1), 50 s in Lauf 2, 36 s in Lauf 3, 30 s in Lauf 4.
- **Einkommen stockt:** am Baumende, weil kein Knoten mehr übrig ist (Lauf 1 bei 21:36 mit 8,26 Mio. Münzen/s). Mit dem Vorschlag ist das genau der Sturmzeitpunkt. Mit dem Startvorschlag sammelt der beste Spieler danach noch 14 min ohne einen Kauf weiter.
- **2x Münzen:** 10 Läufe in 3,7 statt 5,8 Tagen (36 % weniger), 344 statt 317 Kristalle. Am Baumende bringt der Pass fast keine zusätzlichen Kristalle (27 gegen 27), weil `runEarned` dort etwa den Baumkosten entspricht. Zählte `runEarned` die Münzen ohne den Pass-Faktor, hätten Pass-Käufer nach 10 Läufen weniger Kristalle als Spieler ohne Pass (276 gegen 317).
- **Auto-Dig (obere Schranke):** 10 Läufe in 4,6 statt 5,8 Tagen (21 % weniger), gleich viele Kristalle.
- **Goldkiste:** unverändert, Legendär oder besser im Mittel nach 19,1 Öffnungen, also 7.631 Gems.
- **Gegenprobe mit Toren:** Lauf 1 28:24 mit 26 Kristallen, Lauf 2 18:57, Lauf 10 6:25, 10 Läufe in 7,9 Tagen. Die Ruinenkarte zu 250 Mio. kommt auch dort nach der Großmaschine (18:04 gegen 15:25) und kürzt den Lauf um 59 s.

## Preis der Ruinenkarte (Lauf 2 mit 27 Kristallen, Sturm am Baumende)

| Preis | Gekauft | Nach Knoten | Kostet Ertrag | Baumende | Ohne Karte | Differenz |
| --- | --- | --- | --- | --- | --- | --- |
| 2 Mio. | 8:49 | `collect_tool_6` | 9 s | 11:03 | 15:03 | -240 s |
| 100 Mio. | 11:47 | `sell_7` | 18 s | 13:13 | 15:03 | -110 s |
| **250 Mio.** | **13:05** | **`collect_rate_11`** | **32 s** | **14:04** | **15:03** | **-59 s** |
| 500 Mio. | 14:28 | `tank_12` | 41 s | 15:03 | 15:03 | 0 s |
| 1 Mrd. | 16:04 | `collect_rate_12` | 67 s | 16:04 | 15:03 | +61 s |

Die Großmaschine kommt in Lauf 2 bei 8:38, jeder Preis ab 2 Mio. liegt also danach. Ab 100 Mio. fällt der Kauf in die letzten 90 s des Laufs. 250 und 300 Mio. kürzen den Lauf gleich stark (-59 s), ab 500 Mio. kürzt die Karte nichts mehr. 250 Mio. hält Abstand zu dieser Grenze und liegt mit 32 s Ertrag mitten in der Spanne aus 2.1 (12 bis 75 s je Knoten).

## Befunde

1. **Startvorschlag (0,5) hat eine Falle: Weitersammeln bei stehendem Einkommen schlägt alles.** Am Baumende hat der Lauf erst 2,14 Mrd. verdient, das sind nur 260 s des Endertrags. Mit Exponent 0,5 wachsen die Kristalle danach schneller als die Zeit, der kristallraten-optimale Spieler stürmt in Lauf 1 erst bei 35:53 (14 min ohne einen Kauf). Nach 3 Stunden Spiel hat er 13.871 Kristalle gegen 2.672 beim Sturm am Baumende (Formel-Suche, Abschnitt 1 der Simulation), also fünfmal so viele. Mit 0,25 liegt das Optimum 2,5 min hinter dem Baumende, und nach 3 Stunden sind beide gleich auf (1.253 gegen 1.273). Der Spieler muss also nicht mehr grinden, um gut zu spielen.
2. **Früh stürmen lohnt sich nie, und direkt nach dem Mini-Bagger geht es gar nicht.** Ein Sturm direkt nach `collect_tool_4` bringt 0 Kristalle (`tooFew`). Der erste mögliche Sturm (4 Kristalle bei 12:09) bringt über zwei Läufe 32 % weniger Kristalle pro Minute als der Sturm am Baumende, über 10 Läufe nur 40 statt 317 Kristalle. Wer immer beim ersten Kristall stürmt, kommt nie zur Ruinenkarte. Der Knopf darf deshalb nicht schon ab dem Canyon aktiv sein.
3. **`minCrystals = 20`:** Die Schwelle wird im ersten Lauf bei 18:03 erreicht (625 Mio. Münzen, kurz nach `luck_6`), also etwa 3,5 min vor dem Baumende. Ein Sturm dort ist über zwei Läufe 6 % schlechter als am Baumende, bei 10 Kristallen wären es 20 %. Weil `runEarned` am Baumende in jedem Lauf etwa den Baumkosten entspricht, liegt die Schwelle in jedem Lauf an derselben Stelle im Baum. Am Baumende bringt jeder Lauf 27 bis 40 Kristalle, also immer mehr als 20.
4. **Die Läufe werden mit jedem Sturm kürzer, das liegt am Baum und nicht an der Formel.** Die Knotenpreise sind fest, der Bonus wächst linear, also teilt sich die Laufdauer etwa durch (1 + Bonus). Lauf 2 dauert 63 % von Lauf 1, ab Lauf 9 (ab Tag 5,2) dauert ein Lauf unter 5 min. Die Formel bestimmt nur das Tempo: Mit dem Startvorschlag ist das schon ab Lauf 6 (ab Tag 3,7) so, mit Toren bleiben alle 10 Läufe über 5 min (Lauf 10: 6:25). Für Paket 6.4 empfehle ich Knoten hinter der Ruinenkarte (Ruinen-Ast mit Preisen von 1 Mrd. bis in die Billionen), damit das Baumende mit dem Bonus mitwandert, oder Sturm-Knoten, die Kristalle kosten.
5. **Ruinenkarte zu 500 Mio. ist zu spät.** Sie wird als vorletzter Knoten gekauft, die Ruinenstadt gilt dann nur für einen Kauf, und der Lauf wird nicht kürzer. Mit 250 Mio. kommt sie nach `collect_rate_11`, gilt für die letzten drei Knoten und kürzt den Lauf um 59 s.
6. **Der erste Sturm gibt `sandstorm_1` unabhängig von der Kristallzahl.** Ohne `minCrystals` könnte ein Spieler mit 4 Kristallen stürmen, nur um die Ruinenkarte freizuschalten. Das lohnt sich nicht (34 gegen 57 Kristalle nach zwei Läufen), `minCrystals = 20` schließt es trotzdem aus.
7. **`runEarned` muss die Münzen mit dem 2x-Faktor zählen**, wie in der Formel festgelegt ("Münzen aus Sandverkäufen"). Ohne den Faktor stünden Pass-Käufer bei den Kristallen schlechter da als Spieler ohne Pass. Mit dem Faktor bringt der Pass bei Exponent 0,25 höchstens 2^0,25 = 1,19-mal so viele Kristalle bei gleicher Laufzeit, bei 0,5 wären es 1,41-mal so viele.
8. **Testfall anpassen:** Der Studio-Test "Vor dem Canyon kein Sturm-Knopf, danach erscheint er" passt nicht zu `minCrystals = 20`. Vorschlag: Ab `collect_tool_4` zeigt das Sturm-Fenster die Vorschau ("noch X Münzen bis 20 Kristalle"), aktiv wird der Knopf erst ab 20. Das entscheidet die Hauptsitzung.
9. **Überlauf:** Bei 10^300 Münzen ist 4 × (10^294)^0,25 = 4 × 10^73,5. Das ist als Gleitkommazahl noch endlich, `runEarned` selbst ist es aber nicht mehr. Rechnet die Logik über den Zehnerlogarithmus des Zahlentyps (log10 C = log10 Skala + Exponent × (log10 runEarned - log10 Einheit)) und kappt vor dem Potenzieren, bleibt alles endlich. Grenzen für DataCheck: 0 < Exponent ≤ 1, Skala > 0, Einheit ≥ 1, 1 ≤ `minCrystals` ≤ `maxCrystals`.

## Finale Werte

```lua
sandstorm = {
    requiresNode = "collect_tool_4",
    crystalUnit = 1_000_000,
    crystalExponent = 0.25,
    crystalScale = 4,
    maxCrystals = 100_000, -- je Sturm
    minCrystals = 20,
}
```

Knotenpreis `sandstorm_ruins`: **250.000.000 Münzen** (bisher 500 Mio. in `UpgradeTree.luau`). `Economy.windCrystalBonusBp = 200` bleibt.
