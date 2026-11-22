# Sandeffekte für die vier Maschinen

[Roblox-Modellpaket](DuneBaron_Equipment_SandFX.rbxm) · [Maschinen in der Übersicht](maschinen_sand.jpg) · [Förderband](foerderband_sand.jpg) · [Bagger](bagger_sand.jpg) · [Saugroboter](saugroboter_sand.jpg)

Die Arbeitsclips der vier Equipment-V3-Rigs lösen Sandkörner und Staub direkt an den bewegten Teilen aus. Die Spieltest-Aufnahmen zeigen unterschiedliche Zeitpunkte aus den vier Schleifen.

| Rig | Effekt | Auslöser |
| --- | --- | --- |
| `bucket_chain` | Jeder Eimer gibt eine kurze Portion Sand ab. Der Strahl fällt in den Behälter und wirbelt dort Staub auf. | `Discharge` |
| `mini_digger` | Staub an den Zähnen beim Einstechen, sichtbare Ladung im Tieflöffel und ein gekörnter Sandstrom beim Kippen. | `BucketCut`, `BucketLoaded`, `BucketDump` |
| `vacuum_robot` | Zwei kleine Sandströme folgen der Düse und laufen in ihre Öffnung. | `IntakeEngage`, `IntakeSweep`, `IntakeRelease` |
| `mega_machine` | Die beiden Walzen werfen abwechselnd Sand auf. Die Staubwolken bleiben auf Höhe der Schneidzähne. | `CutterLoad` |

## Übergabe an Claude

Im Studio-Entwurf **Every Last Grain** liegen die vier animierten Rigs unter `ServerStorage.DuneBaronEquipmentSandFX`. Auf dem Client das Modul `SandEffects` einmal an den geladenen Arbeitsclip des geklonten Rigs binden. In der Integration entscheidet weiterhin der Arbeitszustand über Start und Stopp des Clips. Die zurückgegebene Funktion beim Entfernen des Rigs aufrufen. [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

Das [Equipment-Soundpaket](../../audio/equipment/README.md) ergänzt die vier Rigs um Arbeitsloops und acht Geräusche für dieselben Arbeitsmarker.

Das [überarbeitete Saugroboter-Modell](../vacuum_refinement/README.md) ergänzt die bewegliche Düse um einen offenen Ansaugschlitz und einen sichtbaren Sandeinlauf im Tank.

Das [überarbeitete Eimerförderband](../conveyor_refinement/README.md) ergänzt die Bodenaufnahme und sichtbare Sandladungen in den Eimern. Der Auswurf folgt der jeweiligen Eimerkante.

Der [überarbeitete Dünen-Harvester](../harvester_refinement/README.md) erhält neue Keilzähne und ein Steigband mit Sandlade- und Auswurfanimation.

```luau
local releaseSandEffects = require(rig.SandEffects).Bind(rig, workTrack)
workTrack:Play()
-- Beim Entfernen des Rigs releaseSandEffects() aufrufen.
```

## Prüfung

Alle vier Arbeitsclips liefen im Studio-Client einen vollständigen Umlauf. Neun Eimerentleerungen, drei Bagger-Marker, drei Sauger-Marker und zwei Walzenimpulse wurden erfasst. Beim Stoppen mitten im Arbeitszyklus schaltete der Sauger seinen Partikelstrom ab und der Bagger verbarg die Ladung. Die Partikel verwenden zwei in Studio geladene Roblox-Texturen. Das RBXM wurde erneut eingelesen und auf Arbeitsclips, Modul und Partikel geprüft.

[BuildSandEffects.editor.luau](BuildSandEffects.editor.luau) erzeugt das Paket aus den Equipment-V3-Rigs. [Roblox ParticleEmitter](https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter)
