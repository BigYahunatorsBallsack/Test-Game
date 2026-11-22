# Abgleich der Fundmodelle mit der Fundkarte

Im Studio-Entwurf **Every Last Grain** stimmen alle **150 Fund-IDs, Modellpfade, Atlas-IDs und Bildausschnitte** überein. Die 150 lokalen Atlaszellen wurden pixelgenau gegen die zugeschnittenen Einzelicons geprüft. Jede Zone hat 30 Modelle und 30 zugehörige Icons.

[Überarbeitete GLBs mit Bildvergleich](../models/fundkorrekturen/README.md) liegen für die 24 unten aufgeführten Abweichungen und die fünf älteren Dünenmeer-Funde vor. Die Tabelle zeigt den Befund an den ursprünglichen Modellen.

| Zone | Zuordnungen geprüft | Modellansichten geprüft | Kollisionsvorschau |
| --- | ---: | ---: | ---: |
| Dünenmeer | 30 | 25 | 5 |
| Oase | 30 | 30 | 0 |
| Canyon | 30 | 30 | 0 |
| Salzsee | 30 | 30 | 0 |
| Ruinenstadt | 30 | 30 | 0 |

## Auffällige Abweichungen

| Fund-ID | Fund | Icon | Modell in der Vergleichsansicht |
| --- | --- | --- | --- |
| `duenenmeer_08` | Tonbecher | Breiter, offener Terrakottabecher | Bauchiges Gefäß mit schmalem Hals |
| `duenenmeer_11` | Kupferstück | Runde Münze ohne Loch | Eckiges Stück mit quadratischem Loch |
| `duenenmeer_13` | Münzbündel | Verschnürter Stapel flacher Münzen | Hoher Körper mit senkrechten Streben |
| `duenenmeer_18` | Nähahle | Ein spitzes Werkzeug mit Schaft | Drei abgerundete Ausläufer |
| `oase_05` | Blattabdruck | Blatt mit Mittelrippe und Adern | In der gezeigten Ansicht ein eingraviertes Herz |
| `oase_06` | Krugboden | Abgebrochener unterer Teil eines Krugs | Weitgehend vollständiger runder Krug mit Hals |
| `oase_11` | Fischernadel | Spitze Nadel mit Öse | Knochenform mit gegabelten Enden |
| `oase_22` | Bewässerungsrinne | Offene, längliche Rinne | Stehende Rohrform mit Abzweig |
| `oase_26` | Mosaikstein | Flache quadratische Fliese | Dicker, vieleckiger Körper mit Relief |
| `canyon_10` | Pyritwürfel | Gruppe aus drei goldenen Würfeln | Gruppe spitzer Kristalle |
| `canyon_12` | Holzkeil | Länglicher brauner Keil | Heller, aufrechter Stift mit rundem Kopf |
| `canyon_17` | Rippenbogen | Langer, schmaler Knochenbogen | Kurzer Knochen mit breitem Gelenk |
| `canyon_23` | Pigmentschale | Terrakottaschale mit Pigmentstücken | Lose rote Stücke ohne sichtbare Schale |
| `canyon_24` | Kletterhaken | Dunkler, spitzer Haken mit Öse | Heller Karabiner |
| `salzsee_04` | Gipsrose | Breite Rosette aus übereinanderliegenden Plättchen | Schmaler, aufrechter Kristallbüschel |
| `salzsee_10` | Salzspirale | Flache, eingerollte Scheibe | Hohe, verdrehte Säule |
| `salzsee_11` | Plankenstück | Flache Bretter mit Nieten | Bootsform mit offenem Innenraum |
| `salzsee_21` | Frachtmarke | Flache Marke mit eckiger Öffnung | Dicker Körper mit rundem Einsatz |
| `salzsee_25` | Perlmuttkasten | Rechteckige Kiste mit Deckel und Beschlag | Niedrige, vieleckige Dose |
| `salzsee_30` | Spiegelplatte | Flache, eingefasste Spiegelfläche | Tiefer, runder Körper mit hellem Einsatz |
| `ruinenstadt_04` | Reliefsplitter | Sandsteinfragment mit eingeritzter Raute | Roter facettierter Edelstein |
| `ruinenstadt_09` | Duftlampe | Niedriges rundes Gefäß mit Deckel | Dreieckige Konstruktion mit Ausschnitt |
| `ruinenstadt_26` | Steinbolzen | Kurzer Bolzen mit verbreiterten Enden | Sanduhrförmiger Körper |
| `ruinenstadt_27` | Fingerglied | Längliches, gegliedertes Steinfragment | Kurzer Hohlzylinder mit seitlichem Ansatz |

Auch bei erkennbaren Paaren variieren Oberfläche und Details. Beim Zweihenkelkrug (`oase_09`) stimmen Gefäßtyp und beide Griffe überein, das Modell zeigt jedoch keinen Terrakottastreifen. Bei der Linsenfassung (`ruinenstadt_24`) stimmen türkisfarbene Linse und eckige Fassung überein. Die Tabelle dokumentiert die deutlichsten Abweichungen und ist keine Art-Freigabe für die übrigen Einträge.

## Grenzen des Vergleichs

Die Mesh-Vorschauen nutzen die Modellgeometrie, vorhandene Farbtexturen und eine einheitliche Dreiviertelansicht. Die Beleuchtung der Spielwelt, Materialeffekte und vollständig verdeckte Rückseiten waren nicht Teil dieser Prüfung.

Für `duenenmeer_02` Schneckenhaus, `duenenmeer_04` Sanddollar, `duenenmeer_05` Perlmuschel, `duenenmeer_06` Tonscherbe und `duenenmeer_07` Krughenkel war nur die Kollisionsgeometrie sichtbar. Die vereinfachten Kollisionsformen geben Gravuren und Rundungen unvollständig wieder. Die optische Abnahme dieser fünf Modelle ist offen.

[Fundmodell- und Icon-Pfade](../ui/collection_assets.json) · [Funddaten mit Namen und Sets](../reference/finds_draft.json)
