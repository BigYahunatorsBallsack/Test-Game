# Benannte Roblox-Clips

[Equipment-Clips](DuneBaron_EquipmentClips.rbxm) enthält fünf editierbare, geloopte `KeyframeSequence`-Objekte aus dem Equipment-V3-Paket.

| Clip | Rig | Dauer | Bewegung und Marker |
| --- | --- | ---: | --- |
| `Conveyor_WorkLoop` | `bucket_chain` | 2,96 s | Neun Eimer und zwei Kettenräder. `Discharge` feuert neunmal pro Umlauf. |
| `Excavator_WorkLoop` | `mini_digger` | 3,24 s | Oberwagen, Arm, Tieflöffel und Hydraulik. `BucketCut` bei 0,55 s, `BucketLoaded` bei 1,08 s, `BucketDump` bei 2,16 s. |
| `Excavator_TravelLoop` | `mini_digger` | 0,24 s | Beide Raupenketten. Referenztempo 5,42 Studs/s. |
| `Harvester_WorkLoop` | `mega_machine` | 1,58 s | Zwei versetzt laufende Schneidwalzen. `CutterLoad` bei 0,26 s und 1,05 s. |
| `Harvester_TravelLoop` | `mega_machine` | 0,33 s | Beide Raupenketten. Referenztempo 9,49 Studs/s. |

Die Rigs liegen in [DuneBaron_Equipment_Animations.rbxm](../equipment_animation/DuneBaron_Equipment_Animations.rbxm) und im Studio-Entwurf unter `ServerStorage.DuneBaronEquipmentAnimations`. Der Clip nennt sein Zielrig im Attribut `RigId`. Die Fahrtclips enthalten ihr Referenztempo im Attribut `BeltSpeedStudsPerSecond`.

Beim lokalen Studio-Spieltest liefen alle fünf Clips über den Animator auf Kopien der drei Rigs. Arbeits- und Fahrtclip bewegten beim Bagger und Harvester gleichzeitig ihre jeweiligen Gelenke. Die Marker feuerten und jeder Clip durchlief mindestens einen Umlauf. Im wieder eingelesenen Export stimmen Keyframes, Posen und Marker mit den Clips im Modellpaket überein. Beim Raupenumlauf übernimmt die nächste Platte dieselbe Position und Orientierung. Einzelne Platten im Modell unterscheiden sich in der Dicke um bis zu 0,01 Studs.

[Sandwurm-Clips](DuneBaron_SandwormClips.rbxm) enthält drei nicht geloopte Sequenzen für die Gelenknamen im vorhandenen Sandwurm-Rig. An den Schnittstellen endet und beginnt dieselbe Pose.

| Clip | Dauer | Clip-lokale Marker |
| --- | ---: | --- |
| `Sandworm_Emerge` | 1,29 s | `SandWarning` bei 0,05 s, `Breach` bei 0,70 s |
| `Sandworm_Bite` | 0,74 s | `Bite` bei 0,35 s |
| `Sandworm_Burrow` | 0,67 s | `Burrow` bei 0,23 s |

Die drei Clips bilden in dieser Reihenfolge einen 2,70 Sekunden langen Angriff. Die Clipmarker sind in **Clipzeit** angegeben. Im durchgehenden GLB-Clip liegen `Bite` bei 1,64 s und `Burrow` bei 2,26 s. Für die drei Clips ist das 27-Knochen-Rig aus [DuneBaron_Sandwurm.glb](../sandwurm/DuneBaron_Sandwurm.glb) vorgesehen.

Im Studio-Animator bewegten die drei Abschnitte dieselben Knochen wie der durchgehende Angriff. Stichproben innerhalb aller Abschnitte entsprachen dessen Posen. In der Clipfolge feuerten alle vier Marker einmal und in der vorgesehenen Reihenfolge.

Beide RBXM-Dateien enthalten Clipdaten. Für die Laufzeit exportiert Claude die Sequenzen als Animation-Assets unter dem passenden Roblox-Ersteller und verbindet sie mit den vorhandenen Rigs. Der Export hat die Dateien wieder eingelesen und jede Gelenkpose an beiden Sandwurm-Schnittstellen überprüft.

Die benannten Sequenzen liegen im Studio-Entwurf auch unter `ServerStorage.DuneBaronNamedClips`.
