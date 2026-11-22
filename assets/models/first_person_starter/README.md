# Schaufel und Eimer für First Person

[Ego-Vorschau](first_person_vorschau.jpg) · [FP_Sandschaufel](FP_Sandschaufel.rbxm) · [FP_Sandeimer](FP_Sandeimer.rbxm)

Die Vorschau zeigt zwei getrennte Posen mit Eimer in der linken Hand und sichtbaren Unterarmen. Beim **Halten** steht die Schaufel rechts nah am Körper, das Blatt zeigt nach oben. Beim **Benutzen** schiebt die rechte Hand die Schaufel nach vorn und das Blatt kippt in Richtung Sand. Der Bereich um die Bildmitte bleibt in beiden Standbildern frei.

Die Standbilder setzen `RightGrip` beim Halten bei `(1,17, −0,83, −1,53)` und beim Benutzen bei `(0,93, −0,89, −1,73)` relativ zur Kamera ein. Die Angaben sind in Studs entlang der Kameraachsen rechts, oben und hinten. Der Stiel neigt sich beim Halten rund 23° aus der Senkrechten. In der Arbeitsansicht liegt er fast waagerecht.

| Modell | Größe im Export | Befestigungspunkte unter `Handle` |
| --- | ---: | --- |
| `FP_Sandschaufel` | ca. 3,46 Studs lang, Blatt 0,82 Studs breit | `RightGrip`, `LeftSupportGrip`, `SandContact` |
| `FP_Sandeimer` | ca. 1,29 Studs hoch mit Griff | `LeftGrip`, `SandFill` |

Beide RBXM-Dateien enthalten je ein Modell. Die sichtbaren Teile sind über `WeldConstraint` mit dem unsichtbaren `Handle` verbunden. `Handle` ist für die Vorschau nach dem Studio-Import verankert. Beim Befestigen am Spieler-Rig muss die Verankerung gelöst werden. In Version 2 sitzt `RightGrip` bei Y = 0,71, also 0,57 Studs näher am Blatt als beim vorherigen Griffpunkt. Für die First-Person-Posen die neuen Attachments verwenden. Die älteren R15-Clips beziehen sich auf das vorige Griffmaß.

Die Vorschau besteht aus zwei lokalen Standbildern mit Referenzarmen. Der Übergang und die Passform stehen zur Probe mit Claudes First-Person-Rig aus.
