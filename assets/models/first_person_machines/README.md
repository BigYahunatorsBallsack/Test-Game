# Maschinen in First Person

## Mini-Bagger und Saugroboter

[Vergleich aus Augenhöhe](maschinen_ego_vorschau.jpg)

| Roblox-Modell | `EquipmentId` | Breite × Höhe × Tiefe im Export |
| --- | --- | ---: |
| [FP_Mini_Bagger](FP_Mini_Bagger.rbxm) | `mini_digger` | 5,91 × 6,80 × 10,24 Studs |
| [FP_Saugroboter](FP_Saugroboter.rbxm) | `vacuum_robot` | 2,86 × 2,09 × 3,31 Studs |

Der Bagger hat eine klarere Frontscheibe und eine befestigte Warnleuchte am hinteren Dachrand. `Turret.DriverEyeReference` markiert die Augenposition des sitzenden Standard-R15-Referenzavatars. `DriverRoot`, `DriverLeftGrip` und `DriverRightGrip` bleiben die vorhandenen Sitz- und Griffpunkte. Beim Saugroboter markieren zwei gelbe Streifen oben die Kanten der Düse beim Blick von oben.

| Modell | Clip | Dauer | Ziel-Rig |
| --- | --- | ---: | --- |
| Mini-Bagger | `WorkLoop` | 3,24 s | Maschine |
| Mini-Bagger | `WorkWithJoysticks` | 3,24 s | Maschine mit Joysticks |
| Mini-Bagger | `TravelLoop` | 0,24 s | Maschine |
| Mini-Bagger | `DriverIdle` und `DriverWork` | je 3,24 s | Standard-R15-Avatar |
| Saugroboter | `WorkLoop` | 1,86 s | Maschine |

Die Clips stammen aus den bisherigen Rigs. Die Varianten wurden erneut eingelesen. Maßstab und Außenmaße entsprechen den Ausgangsmodellen. Die Vorschau zeigt beide Maschinen aus 5,1 Studs Augenhöhe sowie zwei Blickrichtungen aus der Baggerkabine. Die Passform mit Claudes First-Person-Rig und die Wiedergabe in Studio stehen aus.

## Förderband und Dünen-Harvester

[Größenvergleich und Blick aus der Kabine](schwere_maschinen_ego.jpg)

| Roblox-Modell | `EquipmentId` | Breite × Höhe × Tiefe im Ruhezustand |
| --- | --- | ---: |
| [FP_Foerderband](FP_Foerderband.rbxm) | `bucket_chain` | 5,72 × 6,08 × 10,03 Studs |
| [FP_Duenen_Harvester](FP_Duenen_Harvester.rbxm) | `mega_machine` | 17,05 × 12,43 × 19,26 Studs |

Die beiden Führungen am Förderband markieren mit gelb-schwarzen Streifen den Bodeneinlauf. Der Harvester hat hellere Front- und Seitenscheiben, drei Instrumente und zwei Orientierungsmarken auf der Abdeckung vor der Kabine. `Root.DriverEyeReference` markiert die Augenposition des sitzenden R15-Referenzavatars. Die Griffpunkte sitzen am Lenkrad. Die Abdeckung liegt vor den Walzen und verdeckt sie im direkten Blick aus der Kabine.

| Modell | Clip | Dauer | Ziel-Rig |
| --- | --- | ---: | --- |
| Förderband | `WorkLoop` | 2,96 s | Förderband |
| Dünen-Harvester | `WorkLoop` | 1,58 s | Harvester |
| Dünen-Harvester | `TravelLoop` | 0,33 s | Harvester |
| Dünen-Harvester | `SteeringTurn` | 2,40 s | Lenkrad |
| Dünen-Harvester | `DriverIdle` und `DriverSteer` | je 2,40 s | Standard-R15-Avatar |

Die RBXM-Dateien enthalten Geometrie, Rigs und Keyframe-Sequenzen. Beim erneuten Einlesen wurden Maßstab, Außenmaße, Clips und die Zeitpunkte der Marker geprüft. Die lokale Vorschau nutzt eine Augenhöhe von 5,1 Studs im Größenvergleich und zeigt am Lenkrad die Hände des sitzenden R15-Referenzavatars. Der Test mit der Spielkamera in Studio steht aus.
