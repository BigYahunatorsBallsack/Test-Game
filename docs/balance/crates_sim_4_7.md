# Paket 4.7: Quoten-Simulation

Erzeugt von `scripts/cratesim.luau` (Kern `scripts/lib/cratesim.luau`). Nicht von Hand ändern, neu erzeugen mit `lune run scripts/cratesim 10000000 470`.

## Lauf

- Öffnungen je Kiste und Lauf: Ziel 10.000.000. 10 + 1 Pakete runden auf volle Pakete auf.
- Startwert: 470. Jeder Lauf bekommt einen eigenen Startwert daraus.
- Batches für Pity-Kisten: 100.
- Ergebnis: **alle Schwellen eingehalten**.
- Laufzeit: siehe Abschnitt "Laufzeit" am Ende (die einzige Stelle, die sich zwischen gleichen Läufen ändert).

## Methode und Annahmen

- Jede Öffnung läuft über `CrateOpen.open` auf einem Profil aus `Profile.default`. Policy erlaubt (`restricted = false`), Saison an (`inSeason = true`).
- Gems werden vor einem Kauf auf 1.000.000 aufgefüllt, wenn sie nicht reichen. Münzen (Holzkiste) stehen vor jedem Kauf auf 1 Mrd. Pity und Inventar bleiben unberührt. Die Pity läuft wie im Spiel über alle Käufe weiter, auch über Paketgrenzen.
- Einzeln: nur `open(..., 1)`. Pakete: nur `open(..., 10)`, je 11 Öffnungen.
- Zufall: eigener xoshiro128** mit festem Startwert, 53 Bit je Zahl. Unabhängig von `math.random`.
- Sollwerte: Holz und Eisen aus der Tabelle (Quote / 10000). Gold und Event aus `CrateRoll.longRunRates` (Langzeitrate mit Pity). Item = Rate der Seltenheit / Poolgröße in dieser Kiste (Pool direkt aus `CrateItems`).
- Gegenprobe: Das Skript rechnet die Pity-Kette noch einmal nur aus den Daten. Daraus kommen auch die Sollwerte für die Garantie-Raten.
- Sigma ohne Pity: binomial, sqrt(n p (1 - p)). Die Öffnungen sind unabhängig.
- Sigma mit Pity: Batch-Means. Die Pity koppelt benachbarte Öffnungen, das Binomial-Sigma wäre nur eine Näherung. Der Lauf wird in 100 gleich lange Blöcke geteilt. Ein Block ist viel länger als ein Pity-Zyklus (höchstens 60 Öffnungen), die Block-Raten sind also fast unabhängig. Sigma = n x Streuung der Block-Raten / sqrt(100). Die Spalte "Faktor" zeigt Batch-Sigma / Binomial-Sigma.
- Chi-Quadrat ohne Pity: Pearson über alle Items, Freiheitsgrade = Items - 1.
- Chi-Quadrat mit Pity, in zwei Teilen: (a) Items innerhalb ihrer Seltenheit, exakt multinomial, weil der Item-Wurf nicht von der Pity abhängt. (b) Seltenheiten mit Hotelling-T² über die Block-Raten, geprüft mit der F-Verteilung. Das naive Pearson über alle Items steht nur zur Info da.
- Ablauf-Kontrollen je Lauf: Bezahlung je Kauf, Inventar gegen Zählung, `pityTriggered` gegen den mitgezählten Zählerstand, Pity-Zähler in Antwort und Profil.

## Schwellen

| Schwelle | Wert | Grund |
| --- | --- | --- |
| Seltenheit und Item | höchstens 4 Sigma | Bei rund 25 Werten je Lauf schlägt 4 Sigma zufällig nur selten an. |
| Quote 0 | kommt nie vor | Policy: angezeigte 0 % müssen stimmen. |
| Relativ | unter 1 % bei 1.000.000 Öffnungen, skaliert mit sqrt(1.000.000 / n), nur ab 10 % Anteil | Angepasst: Bei 1 % Anteil ist 1 % relativ nur 1 Sigma, bei 4,8 % nur 2,3 Sigma. Ab 10 % sind es mindestens 3,3 Sigma (Gold Episch 15,5 %: 4,3 Sigma). Darunter gilt nur die Sigma-Regel. |
| Chi-Quadrat und Hotelling | p über 0,001 | Plan. |
| Pity | nie mehr als Episch - 1 Öffnungen ohne Episch+, nie mehr als Legendär - 1 ohne Legendär+ | Plan, gezählt über Paketgrenzen. |
| Garantie-Raten | höchstens 4 Sigma (Batch-Means) | Zusätzlich: Die Garantie greift so oft wie die Markov-Kette sagt. |
| Ablauf-Kontrollen | alle 0 | Jede Abweichung wäre ein Fehler im Kaufweg. |

## Übersicht

| Kiste | Lauf | Öffnungen | Größte Abw. (Sigma) | Größte rel. Abw. (ab 10 %) | Chi-Quadrat p | Pity-Serien (ohne Episch+ / ohne Legendär+) | Ergebnis |
| --- | --- | --- | --- | --- | --- | --- | --- |
| wood | Einzeln | 10.000.000 | -3,29 (skin_epic_2) | -0,055 % (Ungewöhnlich) | 0,0731 | - | ok |
| wood | 10 + 1 Pakete | 10.000.001 | -1,83 (Ungewöhnlich) | -0,088 % (Ungewöhnlich) | 0,5288 | - | ok |
| iron | Einzeln | 10.000.000 | +1,35 (skin_epic_2) | -0,038 % (Ungewöhnlich) | 0,6528 | - | ok |
| iron | 10 + 1 Pakete | 10.000.001 | +2,09 (skin_uncommon_1) | +0,116 % (Selten) | 0,2371 | - | ok |
| gold | Einzeln | 10.000.000 | +2,27 (toolVariant_mythic_1) | +0,034 % (Episch) | Items 0,2327, Seltenheiten 0,9017 | 14 / 59 (Grenze 14 / 59) | ok |
| gold | 10 + 1 Pakete | 10.000.001 | -2,89 (toolVariant_mythic_1) | -0,024 % (Ungewöhnlich) | Items 0,3841, Seltenheiten 0,1116 | 14 / 59 (Grenze 14 / 59) | ok |
| event | Einzeln | 10.000.000 | +1,63 (skin_legendary_2) | -0,104 % (Episch) | Items 0,6982, Seltenheiten 0,4722 | 14 / 59 (Grenze 14 / 59) | ok |
| event | 10 + 1 Pakete | 10.000.001 | +1,88 (toolVariant_mythic_2) | +0,018 % (Episch) | Items 0,5244, Seltenheiten 0,9125 | 14 / 59 (Grenze 14 / 59) | ok |

## Holzkiste (wood), Einzeln

10.000.000 Öffnungen in 10.000.000 Käufen. Sigma: binomial. Erlaubte relative Abweichung: 0,316 %.

**Seltenheiten**

| Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- |
| Gewöhnlich | 60,0000 % | 60,0206 % | 6.002.059 | +1,33 | +0,034 % (geprüft) |
| Ungewöhnlich | 30,0000 % | 29,9836 % | 2.998.364 | -1,13 | -0,055 % (geprüft) |
| Selten | 9,0000 % | 9,0019 % | 900.186 | +0,21 | +0,021 % |
| Episch | 1,0000 % | 0,9939 % | 99.391 | -1,94 | -0,609 % |
| Legendär | 0,0000 % | 0,0000 % | 0 | - | - |
| Mythisch | 0,0000 % | 0,0000 % | 0 | - | - |

**Items**

| Item | Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- | --- |
| skin_common_1 | common | 20,0000 % | 20,0156 % | 2.001.561 | +1,23 | +0,078 % |
| skin_common_2 | common | 20,0000 % | 19,9980 % | 1.999.800 | -0,16 | -0,010 % |
| companion_common_1 | common | 20,0000 % | 20,0070 % | 2.000.698 | +0,55 | +0,035 % |
| skin_uncommon_1 | uncommon | 10,0000 % | 9,9994 % | 999.936 | -0,07 | -0,006 % |
| skin_uncommon_2 | uncommon | 10,0000 % | 9,9945 % | 999.447 | -0,58 | -0,055 % |
| companion_uncommon_1 | uncommon | 10,0000 % | 9,9898 % | 998.981 | -1,07 | -0,102 % |
| skin_rare_1 | rare | 3,0000 % | 3,0087 % | 300.868 | +1,61 | +0,289 % |
| skin_rare_2 | rare | 3,0000 % | 3,0010 % | 300.095 | +0,18 | +0,032 % |
| companion_rare_1 | rare | 3,0000 % | 2,9922 % | 299.223 | -1,44 | -0,259 % |
| skin_epic_1 | epic | 0,3333 % | 0,3327 % | 33.268 | -0,36 | -0,196 % |
| skin_epic_2 | epic | 0,3333 % | 0,3273 % | 32.734 | -3,29 | -1,798 % |
| companion_epic_1 | epic | 0,3333 % | 0,3339 % | 33.389 | +0,31 | +0,167 % |

**Chi-Quadrat**

- Pearson über alle Items: Chi² = 18,38, Freiheitsgrade 11, p = 0,0731.

Ablauf-Kontrollen: Fehlgeschlagene Käufe 0; Unerwartete Items (nicht im Pool oder falsche Seltenheit) 0; Bezahlung falsch (Gems bzw. Münzen) 0; Inventar weicht von der Zählung ab 0; pityTriggered weicht vom Zählerstand ab 0; Pity-Zähler im Profil weicht ab 0; Öffnungen fehlen 0.

## Holzkiste (wood), 10 + 1 Pakete

10.000.001 Öffnungen in 909.091 Käufen. Sigma: binomial. Erlaubte relative Abweichung: 0,316 %.

**Seltenheiten**

| Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- |
| Gewöhnlich | 60,0000 % | 60,0197 % | 6.001.975 | +1,27 | +0,033 % (geprüft) |
| Ungewöhnlich | 30,0000 % | 29,9735 % | 2.997.353 | -1,83 | -0,088 % (geprüft) |
| Selten | 9,0000 % | 9,0049 % | 900.491 | +0,54 | +0,055 % |
| Episch | 1,0000 % | 1,0018 % | 100.182 | +0,58 | +0,182 % |
| Legendär | 0,0000 % | 0,0000 % | 0 | - | - |
| Mythisch | 0,0000 % | 0,0000 % | 0 | - | - |

**Items**

| Item | Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- | --- |
| skin_common_1 | common | 20,0000 % | 20,0143 % | 2.001.429 | +1,13 | +0,071 % |
| skin_common_2 | common | 20,0000 % | 19,9889 % | 1.998.887 | -0,88 | -0,056 % |
| companion_common_1 | common | 20,0000 % | 20,0166 % | 2.001.659 | +1,31 | +0,083 % |
| skin_uncommon_1 | uncommon | 10,0000 % | 9,9967 % | 999.672 | -0,35 | -0,033 % |
| skin_uncommon_2 | uncommon | 10,0000 % | 9,9836 % | 998.361 | -1,73 | -0,164 % |
| companion_uncommon_1 | uncommon | 10,0000 % | 9,9932 % | 999.320 | -0,72 | -0,068 % |
| skin_rare_1 | rare | 3,0000 % | 3,0080 % | 300.798 | +1,48 | +0,266 % |
| skin_rare_2 | rare | 3,0000 % | 2,9954 % | 299.542 | -0,85 | -0,153 % |
| companion_rare_1 | rare | 3,0000 % | 3,0015 % | 300.151 | +0,28 | +0,050 % |
| skin_epic_1 | epic | 0,3333 % | 0,3335 % | 33.354 | +0,11 | +0,062 % |
| skin_epic_2 | epic | 0,3333 % | 0,3350 % | 33.500 | +0,91 | +0,500 % |
| companion_epic_1 | epic | 0,3333 % | 0,3333 % | 33.328 | -0,03 | -0,016 % |

**Chi-Quadrat**

- Pearson über alle Items: Chi² = 10,02, Freiheitsgrade 11, p = 0,5288.

Ablauf-Kontrollen: Fehlgeschlagene Käufe 0; Unerwartete Items (nicht im Pool oder falsche Seltenheit) 0; Bezahlung falsch (Gems bzw. Münzen) 0; Inventar weicht von der Zählung ab 0; pityTriggered weicht vom Zählerstand ab 0; Pity-Zähler im Profil weicht ab 0; Öffnungen fehlen 0.

## Eisenkiste (iron), Einzeln

10.000.000 Öffnungen in 10.000.000 Käufen. Sigma: binomial. Erlaubte relative Abweichung: 0,316 %.

**Seltenheiten**

| Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- |
| Gewöhnlich | 35,0000 % | 35,0096 % | 3.500.959 | +0,64 | +0,027 % (geprüft) |
| Ungewöhnlich | 40,0000 % | 39,9846 % | 3.998.460 | -0,99 | -0,038 % (geprüft) |
| Selten | 20,0000 % | 20,0022 % | 2.000.219 | +0,17 | +0,011 % (geprüft) |
| Episch | 5,0000 % | 5,0036 % | 500.362 | +0,53 | +0,072 % |
| Legendär | 0,0000 % | 0,0000 % | 0 | - | - |
| Mythisch | 0,0000 % | 0,0000 % | 0 | - | - |

**Items**

| Item | Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- | --- |
| skin_common_1 | common | 8,7500 % | 8,7581 % | 875.809 | +0,91 | +0,092 % |
| skin_common_2 | common | 8,7500 % | 8,7585 % | 875.850 | +0,95 | +0,097 % |
| companion_common_1 | common | 8,7500 % | 8,7546 % | 875.455 | +0,51 | +0,052 % |
| toolVariant_common_1 | common | 8,7500 % | 8,7385 % | 873.845 | -1,29 | -0,132 % |
| skin_uncommon_1 | uncommon | 10,0000 % | 9,9875 % | 998.749 | -1,32 | -0,125 % |
| skin_uncommon_2 | uncommon | 10,0000 % | 9,9978 % | 999.785 | -0,23 | -0,021 % |
| companion_uncommon_1 | uncommon | 10,0000 % | 9,9919 % | 999.190 | -0,85 | -0,081 % |
| toolVariant_uncommon_1 | uncommon | 10,0000 % | 10,0074 % | 1.000.736 | +0,78 | +0,074 % |
| skin_rare_1 | rare | 5,0000 % | 4,9993 % | 499.931 | -0,10 | -0,014 % |
| skin_rare_2 | rare | 5,0000 % | 5,0089 % | 500.892 | +1,29 | +0,178 % |
| companion_rare_1 | rare | 5,0000 % | 5,0011 % | 500.111 | +0,16 | +0,022 % |
| toolVariant_rare_1 | rare | 5,0000 % | 4,9928 % | 499.285 | -1,04 | -0,143 % |
| skin_epic_1 | epic | 1,2500 % | 1,2459 % | 124.589 | -1,17 | -0,329 % |
| skin_epic_2 | epic | 1,2500 % | 1,2548 % | 125.476 | +1,35 | +0,381 % |
| companion_epic_1 | epic | 1,2500 % | 1,2510 % | 125.101 | +0,29 | +0,081 % |
| toolVariant_epic_1 | epic | 1,2500 % | 1,2520 % | 125.196 | +0,56 | +0,157 % |

**Chi-Quadrat**

- Pearson über alle Items: Chi² = 12,34, Freiheitsgrade 15, p = 0,6528.

Ablauf-Kontrollen: Fehlgeschlagene Käufe 0; Unerwartete Items (nicht im Pool oder falsche Seltenheit) 0; Bezahlung falsch (Gems bzw. Münzen) 0; Inventar weicht von der Zählung ab 0; pityTriggered weicht vom Zählerstand ab 0; Pity-Zähler im Profil weicht ab 0; Öffnungen fehlen 0.

## Eisenkiste (iron), 10 + 1 Pakete

10.000.001 Öffnungen in 909.091 Käufen. Sigma: binomial. Erlaubte relative Abweichung: 0,316 %.

**Seltenheiten**

| Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- |
| Gewöhnlich | 35,0000 % | 34,9979 % | 3.499.792 | -0,14 | -0,006 % (geprüft) |
| Ungewöhnlich | 40,0000 % | 39,9845 % | 3.998.455 | -1,00 | -0,039 % (geprüft) |
| Selten | 20,0000 % | 20,0231 % | 2.002.311 | +1,83 | +0,116 % (geprüft) |
| Episch | 5,0000 % | 4,9944 % | 499.443 | -0,81 | -0,111 % |
| Legendär | 0,0000 % | 0,0000 % | 0 | - | - |
| Mythisch | 0,0000 % | 0,0000 % | 0 | - | - |

**Items**

| Item | Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- | --- |
| skin_common_1 | common | 8,7500 % | 8,7452 % | 874.522 | -0,54 | -0,055 % |
| skin_common_2 | common | 8,7500 % | 8,7396 % | 873.956 | -1,17 | -0,119 % |
| companion_common_1 | common | 8,7500 % | 8,7613 % | 876.126 | +1,26 | +0,129 % |
| toolVariant_common_1 | common | 8,7500 % | 8,7519 % | 875.188 | +0,21 | +0,021 % |
| skin_uncommon_1 | uncommon | 10,0000 % | 10,0198 % | 1.001.979 | +2,09 | +0,198 % |
| skin_uncommon_2 | uncommon | 10,0000 % | 9,9907 % | 999.075 | -0,98 | -0,093 % |
| companion_uncommon_1 | uncommon | 10,0000 % | 9,9832 % | 998.321 | -1,77 | -0,168 % |
| toolVariant_uncommon_1 | uncommon | 10,0000 % | 9,9908 % | 999.080 | -0,97 | -0,092 % |
| skin_rare_1 | rare | 5,0000 % | 5,0015 % | 500.152 | +0,22 | +0,030 % |
| skin_rare_2 | rare | 5,0000 % | 5,0095 % | 500.953 | +1,38 | +0,191 % |
| companion_rare_1 | rare | 5,0000 % | 5,0092 % | 500.917 | +1,33 | +0,183 % |
| toolVariant_rare_1 | rare | 5,0000 % | 5,0029 % | 500.289 | +0,42 | +0,058 % |
| skin_epic_1 | epic | 1,2500 % | 1,2444 % | 124.445 | -1,58 | -0,444 % |
| skin_epic_2 | epic | 1,2500 % | 1,2526 % | 125.265 | +0,75 | +0,212 % |
| companion_epic_1 | epic | 1,2500 % | 1,2481 % | 124.812 | -0,54 | -0,150 % |
| toolVariant_epic_1 | epic | 1,2500 % | 1,2492 % | 124.921 | -0,22 | -0,063 % |

**Chi-Quadrat**

- Pearson über alle Items: Chi² = 18,50, Freiheitsgrade 15, p = 0,2371.

Ablauf-Kontrollen: Fehlgeschlagene Käufe 0; Unerwartete Items (nicht im Pool oder falsche Seltenheit) 0; Bezahlung falsch (Gems bzw. Münzen) 0; Inventar weicht von der Zählung ab 0; pityTriggered weicht vom Zählerstand ab 0; Pity-Zähler im Profil weicht ab 0; Öffnungen fehlen 0.

## Goldkiste (gold), Einzeln

10.000.000 Öffnungen in 10.000.000 Käufen. Sigma: Batch-Means. Erlaubte relative Abweichung: 0,316 %.

**Seltenheiten**

| Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ | Faktor |
| --- | --- | --- | --- | --- | --- | --- |
| Gewöhnlich | 0,0000 % | 0,0000 % | 0 | - | - | - |
| Ungewöhnlich | 39,5588 % | 39,5651 % | 3.956.507 | +0,42 | +0,016 % (geprüft) | 0,950 |
| Selten | 39,5588 % | 39,5516 % | 3.955.156 | -0,54 | -0,018 % (geprüft) | 0,875 |
| Episch | 15,4955 % | 15,5008 % | 1.550.085 | +0,53 | +0,034 % (geprüft) | 0,873 |
| Legendär | 4,8481 % | 4,8431 % | 484.313 | -0,91 | -0,103 % | 0,802 |
| Mythisch | 0,5387 % | 0,5394 % | 53.939 | +0,26 | +0,132 % | 1,177 |

**Items**

| Item | Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- | --- |
| skin_uncommon_1 | uncommon | 9,8897 % | 9,8848 % | 988.481 | -0,52 | -0,050 % |
| skin_uncommon_2 | uncommon | 9,8897 % | 9,8892 % | 988.919 | -0,06 | -0,005 % |
| companion_uncommon_1 | uncommon | 9,8897 % | 9,8833 % | 988.333 | -0,71 | -0,065 % |
| toolVariant_uncommon_1 | uncommon | 9,8897 % | 9,9077 % | 990.774 | +1,92 | +0,182 % |
| skin_rare_1 | rare | 7,9118 % | 7,9040 % | 790.403 | -0,88 | -0,098 % |
| skin_rare_2 | rare | 7,9118 % | 7,9116 % | 791.158 | -0,02 | -0,002 % |
| companion_rare_1 | rare | 7,9118 % | 7,9024 % | 790.236 | -1,08 | -0,119 % |
| toolVariant_rare_1 | rare | 7,9118 % | 7,9231 % | 792.306 | +1,24 | +0,143 % |
| companion_rare_2 | rare | 7,9118 % | 7,9105 % | 791.053 | -0,15 | -0,016 % |
| skin_epic_1 | epic | 3,8739 % | 3,8713 % | 387.131 | -0,44 | -0,066 % |
| skin_epic_2 | epic | 3,8739 % | 3,8768 % | 387.677 | +0,51 | +0,075 % |
| companion_epic_1 | epic | 3,8739 % | 3,8746 % | 387.461 | +0,13 | +0,019 % |
| toolVariant_epic_1 | epic | 3,8739 % | 3,8782 % | 387.816 | +0,69 | +0,110 % |
| skin_legendary_1 | legendary | 1,6160 % | 1,6137 % | 161.373 | -0,65 | -0,143 % |
| companion_legendary_1 | legendary | 1,6160 % | 1,6153 % | 161.530 | -0,20 | -0,046 % |
| toolVariant_legendary_1 | legendary | 1,6160 % | 1,6141 % | 161.410 | -0,48 | -0,120 % |
| skin_mythic_1 | mythic | 0,1796 % | 0,1799 % | 17.992 | +0,27 | +0,201 % |
| companion_mythic_1 | mythic | 0,1796 % | 0,1768 % | 17.682 | -1,91 | -1,526 % |
| toolVariant_mythic_1 | mythic | 0,1796 % | 0,1827 % | 18.265 | +2,27 | +1,721 % |

**Chi-Quadrat**

- Items innerhalb der Seltenheit: Chi² = 17,46, Freiheitsgrade 14, p = 0,2327.
- Seltenheiten (Hotelling-T²): T² = 1,08, F = 0,262 bei (4, 96) Freiheitsgraden, p = 0,9017.
- Nur Info, naives Pearson über alle Items: Chi² = 18,49, Freiheitsgrade 18, p = 0,4239.

**Pity**

- Längste Serie ohne Episch oder besser: 14 Öffnungen (Grenze 14).
- Längste Serie ohne Legendär oder besser: 59 Öffnungen (Grenze 59).

| Garantie | Soll je Öffnung | Ist je Öffnung | Anzahl | Abw. (Sigma) |
| --- | --- | --- | --- | --- |
| epic | 0,8813 % | 0,8825 % | 88.253 | +0,46 |
| legendary | 0,2216 % | 0,2220 % | 22.197 | +0,26 |

- Gegenprobe Sollwerte: größte Differenz `longRunRates` zur eigenen Kette 0.0e+00.

Ablauf-Kontrollen: Fehlgeschlagene Käufe 0; Unerwartete Items (nicht im Pool oder falsche Seltenheit) 0; Bezahlung falsch (Gems bzw. Münzen) 0; Inventar weicht von der Zählung ab 0; pityTriggered weicht vom Zählerstand ab 0; Pity-Zähler im Profil weicht ab 0; Öffnungen fehlen 0.

## Goldkiste (gold), 10 + 1 Pakete

10.000.001 Öffnungen in 909.091 Käufen. Sigma: Batch-Means. Erlaubte relative Abweichung: 0,316 %.

**Seltenheiten**

| Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ | Faktor |
| --- | --- | --- | --- | --- | --- | --- |
| Gewöhnlich | 0,0000 % | 0,0000 % | 0 | - | - | - |
| Ungewöhnlich | 39,5588 % | 39,5495 % | 3.954.947 | -0,63 | -0,024 % (geprüft) | 0,961 |
| Selten | 39,5588 % | 39,5595 % | 3.955.946 | +0,04 | +0,002 % (geprüft) | 0,966 |
| Episch | 15,4955 % | 15,4970 % | 1.549.701 | +0,13 | +0,010 % (geprüft) | 1,002 |
| Legendär | 4,8481 % | 4,8607 % | 486.074 | +1,95 | +0,261 % | 0,955 |
| Mythisch | 0,5387 % | 0,5333 % | 53.333 | -2,20 | -0,993 % | 1,051 |

**Items**

| Item | Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- | --- |
| skin_uncommon_1 | uncommon | 9,8897 % | 9,8834 % | 988.341 | -0,63 | -0,064 % |
| skin_uncommon_2 | uncommon | 9,8897 % | 9,8904 % | 989.036 | +0,07 | +0,007 % |
| companion_uncommon_1 | uncommon | 9,8897 % | 9,8889 % | 988.892 | -0,09 | -0,008 % |
| toolVariant_uncommon_1 | uncommon | 9,8897 % | 9,8868 % | 988.678 | -0,31 | -0,030 % |
| skin_rare_1 | rare | 7,9118 % | 7,9052 % | 790.521 | -0,70 | -0,083 % |
| skin_rare_2 | rare | 7,9118 % | 7,9003 % | 790.032 | -1,35 | -0,145 % |
| companion_rare_1 | rare | 7,9118 % | 7,9218 % | 792.180 | +1,16 | +0,127 % |
| toolVariant_rare_1 | rare | 7,9118 % | 7,9022 % | 790.220 | -1,07 | -0,121 % |
| companion_rare_2 | rare | 7,9118 % | 7,9299 % | 792.993 | +2,03 | +0,230 % |
| skin_epic_1 | epic | 3,8739 % | 3,8745 % | 387.452 | +0,11 | +0,016 % |
| skin_epic_2 | epic | 3,8739 % | 3,8715 % | 387.153 | -0,42 | -0,061 % |
| companion_epic_1 | epic | 3,8739 % | 3,8805 % | 388.047 | +1,11 | +0,170 % |
| toolVariant_epic_1 | epic | 3,8739 % | 3,8705 % | 387.049 | -0,54 | -0,088 % |
| skin_legendary_1 | legendary | 1,6160 % | 1,6220 % | 162.204 | +1,60 | +0,372 % |
| companion_legendary_1 | legendary | 1,6160 % | 1,6223 % | 162.226 | +1,69 | +0,385 % |
| toolVariant_legendary_1 | legendary | 1,6160 % | 1,6164 % | 161.644 | +0,10 | +0,025 % |
| skin_mythic_1 | mythic | 0,1796 % | 0,1792 % | 17.922 | -0,23 | -0,189 % |
| companion_mythic_1 | mythic | 0,1796 % | 0,1781 % | 17.808 | -1,05 | -0,824 % |
| toolVariant_mythic_1 | mythic | 0,1796 % | 0,1760 % | 17.603 | -2,89 | -1,966 % |

**Chi-Quadrat**

- Items innerhalb der Seltenheit: Chi² = 14,91, Freiheitsgrade 14, p = 0,3841.
- Seltenheiten (Hotelling-T²): T² = 7,96, F = 1,930 bei (4, 96) Freiheitsgraden, p = 0,1116.
- Nur Info, naives Pearson über alle Items: Chi² = 23,73, Freiheitsgrade 18, p = 0,1642.

**Pity**

- Längste Serie ohne Episch oder besser: 14 Öffnungen (Grenze 14).
- Längste Serie ohne Legendär oder besser: 59 Öffnungen (Grenze 59).

| Garantie | Soll je Öffnung | Ist je Öffnung | Anzahl | Abw. (Sigma) |
| --- | --- | --- | --- | --- |
| epic | 0,8813 % | 0,8800 % | 87.998 | -0,50 |
| legendary | 0,2216 % | 0,2217 % | 22.166 | +0,04 |

- Gegenprobe Sollwerte: größte Differenz `longRunRates` zur eigenen Kette 0.0e+00.

Ablauf-Kontrollen: Fehlgeschlagene Käufe 0; Unerwartete Items (nicht im Pool oder falsche Seltenheit) 0; Bezahlung falsch (Gems bzw. Münzen) 0; Inventar weicht von der Zählung ab 0; pityTriggered weicht vom Zählerstand ab 0; Pity-Zähler im Profil weicht ab 0; Öffnungen fehlen 0.

## Event-Kiste (event), Einzeln

10.000.000 Öffnungen in 10.000.000 Käufen. Sigma: Batch-Means. Erlaubte relative Abweichung: 0,316 %.

**Seltenheiten**

| Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ | Faktor |
| --- | --- | --- | --- | --- | --- | --- |
| Gewöhnlich | 0,0000 % | 0,0000 % | 0 | - | - | - |
| Ungewöhnlich | 39,5588 % | 39,5526 % | 3.955.258 | -0,37 | -0,016 % (geprüft) | 1,108 |
| Selten | 39,5588 % | 39,5735 % | 3.957.352 | +0,88 | +0,037 % (geprüft) | 1,074 |
| Episch | 15,4955 % | 15,4794 % | 1.547.938 | -1,55 | -0,104 % (geprüft) | 0,913 |
| Legendär | 4,8481 % | 4,8557 % | 485.569 | +1,13 | +0,156 % | 0,987 |
| Mythisch | 0,5387 % | 0,5388 % | 53.883 | +0,07 | +0,028 % | 0,883 |

**Items**

| Item | Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- | --- |
| skin_uncommon_3 | uncommon | 13,1863 % | 13,1734 % | 1.317.341 | -1,19 | -0,098 % |
| companion_uncommon_2 | uncommon | 13,1863 % | 13,1883 % | 1.318.828 | +0,19 | +0,015 % |
| toolVariant_uncommon_2 | uncommon | 13,1863 % | 13,1909 % | 1.319.089 | +0,45 | +0,035 % |
| skin_rare_3 | rare | 13,1863 % | 13,2017 % | 1.320.168 | +1,42 | +0,117 % |
| companion_rare_3 | rare | 13,1863 % | 13,1842 % | 1.318.422 | -0,20 | -0,016 % |
| toolVariant_rare_2 | rare | 13,1863 % | 13,1876 % | 1.318.762 | +0,12 | +0,010 % |
| skin_epic_3 | epic | 5,1652 % | 5,1579 % | 515.795 | -1,02 | -0,140 % |
| companion_epic_2 | epic | 5,1652 % | 5,1651 % | 516.511 | -0,01 | -0,001 % |
| toolVariant_epic_2 | epic | 5,1652 % | 5,1563 % | 515.632 | -1,31 | -0,171 % |
| skin_legendary_2 | legendary | 1,6160 % | 1,6230 % | 162.295 | +1,63 | +0,428 % |
| companion_legendary_2 | legendary | 1,6160 % | 1,6142 % | 161.419 | -0,46 | -0,114 % |
| toolVariant_legendary_2 | legendary | 1,6160 % | 1,6185 % | 161.855 | +0,66 | +0,156 % |
| skin_mythic_2 | mythic | 0,1796 % | 0,1783 % | 17.832 | -0,95 | -0,690 % |
| companion_mythic_2 | mythic | 0,1796 % | 0,1801 % | 18.009 | +0,38 | +0,295 % |
| toolVariant_mythic_2 | mythic | 0,1796 % | 0,1804 % | 18.042 | +0,64 | +0,479 % |

**Chi-Quadrat**

- Items innerhalb der Seltenheit: Chi² = 7,29, Freiheitsgrade 10, p = 0,6982.
- Seltenheiten (Hotelling-T²): T² = 3,68, F = 0,892 bei (4, 96) Freiheitsgraden, p = 0,4722.
- Nur Info, naives Pearson über alle Items: Chi² = 10,81, Freiheitsgrade 14, p = 0,7013.

**Pity**

- Längste Serie ohne Episch oder besser: 14 Öffnungen (Grenze 14).
- Längste Serie ohne Legendär oder besser: 59 Öffnungen (Grenze 59).

| Garantie | Soll je Öffnung | Ist je Öffnung | Anzahl | Abw. (Sigma) |
| --- | --- | --- | --- | --- |
| epic | 0,8813 % | 0,8861 % | 88.615 | +1,87 |
| legendary | 0,2216 % | 0,2191 % | 21.912 | -1,89 |

- Gegenprobe Sollwerte: größte Differenz `longRunRates` zur eigenen Kette 0.0e+00.

Ablauf-Kontrollen: Fehlgeschlagene Käufe 0; Unerwartete Items (nicht im Pool oder falsche Seltenheit) 0; Bezahlung falsch (Gems bzw. Münzen) 0; Inventar weicht von der Zählung ab 0; pityTriggered weicht vom Zählerstand ab 0; Pity-Zähler im Profil weicht ab 0; Öffnungen fehlen 0.

## Event-Kiste (event), 10 + 1 Pakete

10.000.001 Öffnungen in 909.091 Käufen. Sigma: Batch-Means. Erlaubte relative Abweichung: 0,316 %.

**Seltenheiten**

| Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ | Faktor |
| --- | --- | --- | --- | --- | --- | --- |
| Gewöhnlich | 0,0000 % | 0,0000 % | 0 | - | - | - |
| Ungewöhnlich | 39,5588 % | 39,5570 % | 3.955.704 | -0,12 | -0,005 % (geprüft) | 0,987 |
| Selten | 39,5588 % | 39,5547 % | 3.955.468 | -0,28 | -0,011 % (geprüft) | 0,952 |
| Episch | 15,4955 % | 15,4983 % | 1.549.828 | +0,25 | +0,018 % (geprüft) | 0,962 |
| Legendär | 4,8481 % | 4,8492 % | 484.919 | +0,16 | +0,022 % | 0,980 |
| Mythisch | 0,5387 % | 0,5408 % | 54.082 | +0,91 | +0,398 % | 1,022 |

**Items**

| Item | Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |
| --- | --- | --- | --- | --- | --- | --- |
| skin_uncommon_3 | uncommon | 13,1863 % | 13,1841 % | 1.318.412 | -0,22 | -0,016 % |
| companion_uncommon_2 | uncommon | 13,1863 % | 13,1865 % | 1.318.652 | +0,02 | +0,002 % |
| toolVariant_uncommon_2 | uncommon | 13,1863 % | 13,1864 % | 1.318.640 | +0,01 | +0,001 % |
| skin_rare_3 | rare | 13,1863 % | 13,1966 % | 1.319.660 | +0,93 | +0,078 % |
| companion_rare_3 | rare | 13,1863 % | 13,1838 % | 1.318.377 | -0,27 | -0,019 % |
| toolVariant_rare_2 | rare | 13,1863 % | 13,1743 % | 1.317.431 | -0,95 | -0,091 % |
| skin_epic_3 | epic | 5,1652 % | 5,1678 % | 516.777 | +0,35 | +0,050 % |
| companion_epic_2 | epic | 5,1652 % | 5,1590 % | 515.902 | -0,93 | -0,119 % |
| toolVariant_epic_2 | epic | 5,1652 % | 5,1715 % | 517.149 | +0,97 | +0,122 % |
| skin_legendary_2 | legendary | 1,6160 % | 1,6214 % | 162.139 | +1,29 | +0,331 % |
| companion_legendary_2 | legendary | 1,6160 % | 1,6127 % | 161.268 | -0,84 | -0,208 % |
| toolVariant_legendary_2 | legendary | 1,6160 % | 1,6151 % | 161.512 | -0,24 | -0,057 % |
| skin_mythic_2 | mythic | 0,1796 % | 0,1805 % | 18.052 | +0,73 | +0,535 % |
| companion_mythic_2 | mythic | 0,1796 % | 0,1785 % | 17.850 | -0,80 | -0,590 % |
| toolVariant_mythic_2 | mythic | 0,1796 % | 0,1818 % | 18.180 | +1,88 | +1,248 % |

**Chi-Quadrat**

- Items innerhalb der Seltenheit: Chi² = 9,08, Freiheitsgrade 10, p = 0,5244.
- Seltenheiten (Hotelling-T²): T² = 1,01, F = 0,244 bei (4, 96) Freiheitsgraden, p = 0,9125.
- Nur Info, naives Pearson über alle Items: Chi² = 10,07, Freiheitsgrade 14, p = 0,7569.

**Pity**

- Längste Serie ohne Episch oder besser: 14 Öffnungen (Grenze 14).
- Längste Serie ohne Legendär oder besser: 59 Öffnungen (Grenze 59).

| Garantie | Soll je Öffnung | Ist je Öffnung | Anzahl | Abw. (Sigma) |
| --- | --- | --- | --- | --- |
| epic | 0,8813 % | 0,8797 % | 87.966 | -0,59 |
| legendary | 0,2216 % | 0,2224 % | 22.245 | +0,62 |

- Gegenprobe Sollwerte: größte Differenz `longRunRates` zur eigenen Kette 0.0e+00.

Ablauf-Kontrollen: Fehlgeschlagene Käufe 0; Unerwartete Items (nicht im Pool oder falsche Seltenheit) 0; Bezahlung falsch (Gems bzw. Münzen) 0; Inventar weicht von der Zählung ab 0; pityTriggered weicht vom Zählerstand ab 0; Pity-Zähler im Profil weicht ab 0; Öffnungen fehlen 0.

## Laufzeit

Prüfsumme des Berichts bis hier (FNV-1a): affcd945. Gleicher Startwert und gleiche Öffnungszahl ergeben dieselbe Prüfsumme.

- Laufzeit wood, Einzeln: 51,2 s
- Laufzeit wood, 10 + 1 Pakete: 17,8 s
- Laufzeit iron, Einzeln: 43,8 s
- Laufzeit iron, 10 + 1 Pakete: 18,0 s
- Laufzeit gold, Einzeln: 55,6 s
- Laufzeit gold, 10 + 1 Pakete: 25,1 s
- Laufzeit event, Einzeln: 59,6 s
- Laufzeit event, 10 + 1 Pakete: 24,9 s
- Laufzeit gesamt: 296,1 s
