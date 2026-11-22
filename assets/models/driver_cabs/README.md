# Fahrerkabinen für Mini-Bagger und Dünen-Harvester

Das [Roblox-Modellpaket](DuneBaron_DriverCabs.rbxm) enthält beide Maschinen, bewegliche Bedienelemente und sechs lokale Animationsclips. Die [Vorschau](fahrerkabinen_vorschau.jpg) zeigt beide Maschinen im selben Maßstab sowie die Sitzpositionen bei ausgeblendeten Scheiben. In der [animierten Vorschau](bedienung_vorschau.gif) ist je ein Bedienzyklus pro Maschine zu sehen.

Der Mini-Bagger hat eine höhere, nach vorn verlängerte Kabine mit offenem Einstieg, zwei Joysticks, Instrument und geriffeltem Fußboden. Beim Harvester sitzt der Fahrer in der bestehenden Kabine hinter einem Dreispeichenlenkrad mit seitlichen Griffpunkten. Die Clips sind auf den Standard-R15-Blockavatar zugeschnitten.

| Maschine | Avatar im Stand | Avatar in Aktion | Maschine in Aktion |
|---|---|---|---|
| Mini-Bagger | `DriverIdle` | `DriverWork` | `WorkWithJoysticks` |
| Dünen-Harvester | `DriverIdle` | `DriverSteer` | `SteeringTurn` |

Die drei Clips je Maschine stehen unter `DriverAnimations`. `WorkWithJoysticks` enthält den vollständigen 3,24-Sekunden-Grabzyklus samt Joysticks und vorhandenen Sandmarkern. `DriverWork` verwendet dieselben Zeitpunkte. `DriverSteer` und `SteeringTurn` bilden einen 2,40-Sekunden-Zyklus. Fahrt und Schneidwalzen des Harvesters haben eigene Clips unter `Animations`.

## Übergabe an Claude

Das Paket in Roblox Studio über **Insert from File** einfügen. `DriverRoot.WorldCFrame` gibt die Sitztransformation für den `HumanoidRootPart` vor. Das Attachment sitzt am Bagger auf dem drehbaren `Turret`, beim Harvester auf dem `Root`. Die beweglichen Griffpunkte heißen `DriverLeftGrip` und `DriverRightGrip`. Für die Bedienzyklen jeweils die Avatar- und Maschinenanimation bei gleicher Zeitposition und Geschwindigkeit abspielen. Beim Bagger übernimmt `WorkWithJoysticks` den Grabzyklus einschließlich Sandmarkern. [Roblox-Animationseditor](https://create.roblox.com/docs/animation/editor)

Die Clips sind editierbare `KeyframeSequence`-Objekte. Die Sitzpositionen und Griffpunkte wurden nach dem Export anhand der Gelenkstellungen geprüft. Ein Wiedergabetest in Studio steht noch aus.

Der [überarbeitete Mini-Bagger](../excavator_refinement/README.md) enthält dieselbe Kabine und ergänzt beide Grabclips um Löffelhydraulik und Sandladung.

```powershell
lune run assets/models/equipment_animation/BuildEquipment.editor.luau driver-cabs
```
