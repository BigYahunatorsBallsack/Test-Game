# Sandwurm-Sounds

Vier eigens erzeugte WAVs begleiten die bestehenden drei Sandwurm-Clips. Im [Hörbeispiel](sandwurm_hoerprobe.wav) liegen die vier Töne an den Zeitpunkten der Animationsmarker.

| Clip | Marker | Zeit im Clip | Klang |
| --- | --- | ---: | --- |
| `Sandworm_Emerge` | `SandWarning` | 0,05 s | Ansteigendes Grollen mit trockenen Sandgeräuschen |
| `Sandworm_Emerge` | `Breach` | 0,70 s | Tiefer Stoß mit auffliegendem und herabrieselndem Sand |
| `Sandworm_Bite` | `Bite` | 0,35 s | Kurzes, trockenes Zuschnappen |
| `Sandworm_Burrow` | `Burrow` | 0,23 s | Abfallender Klang mit nachrutschendem Sand |

Das [Roblox-Importpaket](DuneBaron_Sandworm_SFX.zip) enthält die vier Einzeldateien und die [Zuordnung](cue_sheet.json). Die WAVs verwenden 48 kHz, 16 Bit und einen Monokanal. Die Warnung beginnt 0,65 Sekunden vor dem Ausbruch. Das Grollen enthält auch hörbare Mitten, damit die Warnung auf kleinen Lautsprechern erkennbar bleibt.

Nach dem Audio-Import kann Claude die vergebenen IDs an dieselben Marker wie die [Sandeffekte](../../models/sandwurm_fx/README.md) binden. Das Hörbeispiel kombiniert die Töne in Originalreihenfolge. [Roblox Audio-Import](https://create.roblox.com/docs/audio/assets) · [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

[build_sandworm_audio.py](build_sandworm_audio.py) erzeugt die Töne mit NumPy aus Oszillatoren und gefiltertem Rauschen.
