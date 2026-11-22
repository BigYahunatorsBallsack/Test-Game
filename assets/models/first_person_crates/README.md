# Kisten für First Person

[Vorschau aus Augenhöhe](kisten_ego_vorschau.jpg)

Alle vier Varianten haben eine flache Einlage im Innenraum. Die vorhandenen Außenmaße, Scharniere, Riegel und Clips bestimmen weiterhin den Größenvergleich. Jeder Export enthält ein Modell mit `Root`, `Lid`, `Latch`, `AnimationController` und den beiden editierbaren Clips.

| Modell und Ziel-Rig | `CrateId` | Außenmaße in Studs | `Open` | `Close` |
| --- | --- | --- | ---: | ---: |
| [FP_Kiste_Holz](FP_Kiste_Holz.rbxm) | `wood` | 2,74 × 2,11 × 2,87 | 0,81 s | 0,57 s |
| [FP_Kiste_Eisen](FP_Kiste_Eisen.rbxm) | `iron` | 3,09 × 2,13 × 3,11 | 1,16 s | 0,84 s |
| [FP_Kiste_Gold](FP_Kiste_Gold.rbxm) | `gold` | 3,29 × 2,41 × 3,20 | 0,98 s | 0,68 s |
| [FP_Kiste_Event](FP_Kiste_Event.rbxm) | `event` | 3,41 × 2,57 × 3,34 | 1,28 s | 0,78 s |

Maße in Breite, Höhe und Tiefe bei geschlossenem Deckel. Die Vorderseite zeigt nach `−Z`.

`Latch.LatchTouch` liegt unmittelbar vor dem beweglichen Riegel und folgt bei der Öffnung dem Gelenk. `Root.DisplaySurface` sitzt auf der neuen Einlage. `Root.RevealOrigin` und die Marker `Unlatch`, `Reveal` und `Latch` sind für die spätere Anbindung vorhanden. Die enthaltenen Lichteffekte und Partikel liegen als Instanzen mit ihren Ausgangswerten vor.

Die Vorschau zeigt die geschlossene Pose und die Endpose aus `Open`, jeweils vom gleichen Kamerastandpunkt. Die Handsilhouetten dienen als Maßstab. Nach dem Export wurden die Modellstruktur, Clipanschlüsse und der Abstand zwischen der Einlage und den beweglichen Teilen geprüft. Die Prüfung mit Claudes First-Person-Rig und dem aktiven Lichtstoß steht aus.
