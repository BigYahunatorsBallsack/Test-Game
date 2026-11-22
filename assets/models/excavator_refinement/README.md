# Mini-Bagger mit Löffelhydraulik

[Roblox-Modell](DuneBaron_ExcavatorRefinement.rbxm) · [Detailansichten](bagger_modell.jpg) · [Animierter Grabzyklus](bagger_arbeitszyklus.gif)

Der Tieflöffel hat einen eigenen Kippzylinder mit Kolbenstange, zwei Gelenkbolzen und außen am Arm geführten Hydraulikleitungen. Zwei flexible Schlauchabschnitte folgen dem Knick zwischen Ausleger und Stiel. Die Sandladung setzt sich beim Anheben und rutscht vor dem Auskippen zur Zahnkante.

## Übergabe an Claude

Das Paket enthält das Rig `mini_digger` mit Fahrerkabine. Beide Grabclips enthalten die neue Hydraulik und die Bewegung der Ladung. `Animations/WorkLoop` spielt den 3,24-Sekunden-Zyklus für die Maschine. `DriverAnimations/WorkWithJoysticks` enthält zusätzlich die Joysticks und läuft synchron mit dem R15-Clip `DriverWork`. `TravelLoop`, `DriverIdle` und die vorhandenen Sitz- und Griffpunkte sind ebenfalls enthalten.

Das mitgelieferte `SandEffects`-Modul zeigt alle vier Sandformen ab `BucketLoaded` und blendet sie beim Auswurf oder beim Stoppen aus. Die Auswurfpartikel starten an der Zahnkante. `BucketCut`, `BucketLoaded` und `BucketDump` liegen an den bestehenden Zeitpunkten für die [Arbeitsgeräusche](../../audio/equipment/README.md). [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

Bolzenanschlüsse, Schlauchverlauf und Sichtbarkeit der Ladung sind am Export lokal geprüft. Die animierte Vorschau stellt die Partikel näherungsweise dar. Ein Studio-Wiedergabetest steht noch aus.

```powershell
lune run assets/models/excavator_refinement/BuildExcavatorRefinement.luau
```
