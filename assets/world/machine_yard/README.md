# Maschinenhof im Dünenmeer

[Roblox-Modellpaket](DuneBaron_MachineYard.rbxm) · [Vorschau mit Werkstatt und Lageplan](maschinenhof_vorschau.jpg)

Vier Buchten zeigen die aktuellen Maschinen in ihren Originalgrößen. Eine niedrige Steinreihe markiert den Besucherweg. Hinter den Buchten steht eine offene Werkstatt mit beleuchteter Werkbank, Schraubstock, Werkzeugkiste und einem Regal für Raupenplatten, Laufrollen und Hydraulikschläuche.

| Schaustück | Höhe in der ausgestellten Pose | Position X / Z |
|---|---:|---:|
| Eimerförderband | 6,27 Studs | 22,50 / −27,85 |
| Mini-Bagger | 6,80 Studs | 37,60 / −27,05 |
| Saugroboter | 2,09 Studs | 51,05 / −24,25 |
| Dünen-Harvester | 12,43 Studs | 68,23 / −28,45 |

## Übernahme in Roblox Studio

1. Das Modellpaket als Ordner `MachineYard` unter `Workspace.DuneBaronWorld.ArtV2` einsetzen. Den bisherigen Hofordner vorab in `ServerStorage` ablegen.
2. Die vier alten `Display_…_Collision`-Bauteile der Maschinen aus `ArtV2.SolidPlacements` zusammen mit dem alten Hof sichern. Die neuen Kollisionskörper liegen gesammelt unter `MachineYard.Collision`.

Die Modelle unter `MachineYard.Displays` sind verankerte Schaustücke. Für Animationen und Spielanbindung die Einzelrigs aus den Modellpaketen verwenden. Die überarbeiteten Exporte für [Förderband](../../models/conveyor_refinement/README.md), [Saugroboter](../../models/vacuum_refinement/README.md) und [Harvester](../../models/harvester_refinement/README.md) berücksichtigen den gespeicherten Modellmaßstab bei Positions-Keyframes. Der Roblox-Animator wendet den Maßstab beim Abspielen an. [Roblox Model:GetScale](https://create.roblox.com/docs/reference/engine/classes/Model#GetScale)

Lokal am Export geprüft wurden der Sitz auf den Stellflächen und die Erreichbarkeit aller Buchten sowie des Werkstatteingangs. Die Vorschau zeigt die Weltgeometrie mit einer aus dem Dünenmeer-Höhenfeld gerenderten Umgebung. Der Hof liegt lokal als RBXM vor. Die Übernahme und der Laufwegtest im Studio-Place stehen noch aus.

```powershell
lune run assets/world/machine_yard/BuildMachineYard.luau
```
