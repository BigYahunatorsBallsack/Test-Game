# Paket 4.6: Direktkauf-Preise

Stand 20.11.2026, Paket 4.6, `balance-analyst`. Skript: `docs/balance/directshop_4_6.py` (nur Standardbibliothek, Aufruf `python3 docs/balance/directshop_4_6.py`, unter 1 s, ohne Zufall). Es liest `Crates.luau`, `CrateItems.luau` und `Economy.luau` direkt. Code und Daten wurden nicht geändert.

## Annahmen

- **Zweck:** Der Reiter "Direktkauf" erscheint nur bei gesperrter oder unbekannter Policy. Er verkauft jedes Kisten-Item außer Event-Items gegen Gems.
- **Roblox-Policy:** Ein Direktkauf ist erlaubt, wenn der Preis auf dem Erwartungswert beruht. Beispiel von Roblox: 10 Robux für 5 % Schwert ergibt 200 Robux direkt.
- **Kisten:** Nur Gem-Kisten ohne `eventOnly`, also Eisen (100 Gems) und Gold (400 Gems). Holz kostet Münzen, Event ist Saison.
- **Rate je Öffnung:** Eisen ohne Pity: Quote / 10000. Gold mit Pity 15/60: Langzeitrate aus der exakten Markov-Kette über (sinceEpic, sinceLegendary), Regeln wie `Logic/CrateRoll`. Die Werte stimmen mit `crates_4_2.md` überein (Skript prüft das).
- **Item-Wahrscheinlichkeit:** Rate der Seltenheit / Poolgröße der Kiste. Pools Eisen 4/4/4/4, Gold 4/5/4/3/3.
- **Preisbasis:** Einzelpreis der Kiste, nicht das 10er-Paket. Damit liegt der Preis auch über dem Paket-EV (9,1 % niedriger).

## Gold-Pity: exakte Langzeitraten je Öffnung

| Seltenheit | Tabelle | Mit Pity |
| --- | --- | --- |
| Ungewöhnlich | 0,4000 | 0,3955884537 |
| Selten | 0,4000 | 0,3955884537 |
| Episch | 0,1500 | 0,1549552381 |
| Legendär | 0,0450 | 0,0484810690 |
| Mythisch | 0,0050 | 0,0053867854 |
| Legendär+ | 0,0500 | 0,0538678545 |

Die Werte sind exakte Brüche (Nenner mit 79 Stellen), hier auf 10 Stellen gerundet.

## Regel (Empfehlung)

1. Für jede passende Gem-Kiste: EV = Kistenpreis / P(genau dieses Item je Öffnung).
2. EV(Item) = kleinster Wert über diese Kisten.
3. Aufrunden auf 2 signifikante Stellen: Schritt = 10^(Stellen vor dem Komma - 2), Preis = ceil(EV / Schritt) x Schritt.
4. Monotone Untergrenze: Seltenheiten nach Rang durchgehen. Preis mindestens der Einstiegspreis (billigstes Item) jeder niedrigeren Seltenheit. Die Untergrenze hebt nur an.
5. Event-Items haben keinen Preis.

Jeder Schritt hebt den Preis an oder lässt ihn gleich. Der Preis liegt also nie unter dem EV.

## Preise

| Item | Kiste | P je Öffnung | EV exakt | 2 Stellen | Mit Untergrenze |
| --- | --- | --- | --- | --- | --- |
| 4 x Gewöhnlich | Eisen | 0,0875 | 1.142,86 | 1.200 | **1.200** |
| 4 x Ungewöhnlich | Eisen | 0,1 | 1.000 | 1.000 | **1.200** |
| 4 x Selten (ohne companion_rare_2) | Eisen | 0,05 | 2.000 | 2.000 | **2.000** |
| companion_rare_2 | Gold | 0,0791177 | 5.055,76 | 5.100 | **5.100** |
| 4 x Episch | Eisen | 0,0125 | 8.000 | 8.000 | **8.000** |
| 3 x Legendär | Gold | 0,0161604 | 24.751,93 | 25.000 | **25.000** |
| 3 x Mythisch | Gold | 0,0017956 | 222.767,37 | 230.000 | **230.000** |

Gold wäre teurer für Ungewöhnlich (4.044,6), Selten (5.055,8) und Episch (10.325,6). Darum gewinnt dort Eisen.

## Bewertung

- **2 Stellen aufrunden ist sinnvoll.** Die Preise wirken rund. Der Aufschlag liegt hier bei 0 bis 5 %, höchstens 10 % (z. B. 1.001 wird 1.100). Mythisch: +3,2 % (7.233 Gems). 3 Stellen (1.150, 24.800, 223.000) wären genauer, aber unruhiger. Kein Grund zum Wechsel.
- **Gewöhnlich teurer als Ungewöhnlich ist ein Problem für die Anzeige.** Ehrlich gerechnet stimmt es: Eisen würfelt Gewöhnlich seltener (35 %) als Ungewöhnlich (40 %). Im Shop sieht es aber wie ein Fehler aus. Außerdem wäre jedes gewöhnliche Item sinnlos, weil ein ungewöhnliches mehr bringt (7 % statt 5 %) und weniger kostet.
- **Empfehlung: monotone Untergrenze.** Sie ändert nur die vier ungewöhnlichen Items (1.000 auf 1.200, 20 % über EV). Sie hebt nur an, die Policy bleibt erfüllt. Sie bleibt datengetrieben, eine eigene Preistabelle ist nicht nötig.

## Arbitrage

Kein Gewinn möglich, auch nicht bei unbekannter Policy in einer erlaubten Region. Jeder Direktpreis liegt auf oder über den Kistenkosten je erwartetem Exemplar (Einzelkauf und 10er-Paket). Eine Kistenöffnung bringt zusätzlich andere Items, ist also im Mittel immer gleich gut oder besser. Items lassen sich weder verkaufen noch tauschen noch in Gems zurückwandeln. Der einzige Unterschied: Der Direktkauf hat keine Streuung. Das ist eine Wahl, kein Vorteil. Wichtig für die Logik: Ein Direktkauf darf den Pity-Zähler nicht verändern.

## Tag 7: Ersatzgegenstand

Die Eisenkiste kostet 100 Gems. Ihr Inhalt ist zu Direkt-EV bewertet 1.600 Gems wert (zu Shoppreisen 1.700), weil sie eines von 16 Items liefert. Der erwartete Bonus je Eisenkiste ist 725 Bp, fast genau ein ungewöhnliches Item (700 Bp). Die Kupferschaufel (`toolVariant_uncommon_1`, Shoppreis 1.200) ist also gleichwertig, nicht zu großzügig. Ein gewöhnliches Item wäre schwächer als der Schnitt der Kiste, ein seltenes stärker. Die Werkzeug-Variante füllt einen Slot, den Holz nie füllt, und ist kein Event-Item. Wöchentliche Kopien bringen sie nach 11 Wochen auf ★5 (11,2 %). Das ist knapp über Selten ★1 (10 %) und unter Episch ★1 (14 %), also harmlos. **Empfehlung: `day7FallbackItemId = "toolVariant_uncommon_1"`.**

## maxGems

`Economy.purchases.maxGems` = 10.000.000. Das teuerste Item kostet 230.000 Gems, also 2,3 % des Deckels. Es passt. Zum besten Gem-Paket (0,357 Robux je Gem) sind das etwa 82.000 Robux.

## Hinweise für die Umsetzung (Lune)

- Für Kisten ohne Pity in ganzen Zahlen rechnen: EV = Preis x Poolgröße x 10000 / Quote. Sonst kann 1000,0000000001 auf 1.100 springen.
- Gold in Gleitkomma ist unkritisch. Alle Gold-EVs liegen weit von einer Rundungsgrenze (4.044,6, 5.055,8, 10.325,6, 24.751,9, 222.767,4).
- Sollwerte: die Spalte "Mit Untergrenze". Dazu prüfen: Preis >= EV für jedes Item, Preis ganzzahlig, Preis <= maxGems, Event-Items ohne Preis.
