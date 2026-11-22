# Dune Baron Sandwurm

[`DuneBaron_Sandwurm.glb`](DuneBaron_Sandwurm.glb) enthält das Modell, das Skelett, die Farben und den Angriff `BreachSnapBurrow`. Körper, Hals, Maulrand und Rachen bilden eine durchgehende Oberfläche. Die Falten liegen flach in der Haut. Beim Biss bleibt der Maulrand ein Stück und die 17 Zähne schwenken nach innen.

Der Körper ist bis zu 15,6 Studs breit, das Maul außen rund 17,5 Studs. In der ausgestreckten Pose ragt der Wurm rund 36 Studs aus dem Sand. Der R15-Avatar im [Größenvergleich](sandwurm_groessenvergleich.jpg) ist 5,18 Studs hoch. Die [Bisspose](sandwurm_bisspose.jpg) zeigt die Verformung von der Seite. Die Aufnahmen entstanden in den äußeren Dünen bei X/Z 225 / 576.

## Animation für die Integration

| Cue | Zeit | Pose |
| --- | ---: | --- |
| `SandWarning` | 0,05 s | Der Wurm liegt unter der Oberfläche. |
| `Breach` | 0,70 s | Der Kopf bricht durch den Sand. |
| `Bite` | 1,64 s | Der Wurm schnellt vor und die Zähne klappen ein. |
| `Burrow` | 2,26 s | Der Wurm zieht sich unter den Sand zurück. |

Der Clip endet nach 2,70 Sekunden. `GroundRoot` sitzt auf Sandhöhe, die Blickrichtung des Modells ist entlang der lokalen negativen Z-Achse. Die Farben sind im Mesh eingebettet.

Die lokale GLB ist die dauerhafte Übergabedatei für den Studio-Importer. Das Mesh der `EditableMesh`-Vorschau unter `ServerStorage.DuneBaronSandwurm` muss nach dem Wiederöffnen von Studio erneut erzeugt oder aus der GLB importiert werden. Die [drei Roblox-Clips](../animation_clips/DuneBaron_SandwormClips.rbxm) enthalten die vier Marker in Clipzeit. Spawnregeln, Trefferprüfung und Schaden gehören zur separaten Spielintegration. [Studio-Importer](https://create.roblox.com/docs/studio/importer)

Das [Sandeffekt-Paket](../sandwurm_fx/README.md) ergänzt die Clipmarker um Bodenwarnung, Sandstoß, Partikel am Maul und einwärts fallenden Sand beim Abtauchen.
