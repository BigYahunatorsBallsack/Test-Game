# Eimerförderband mit Bodenaufnahme

[Roblox-Modell](DuneBaron_ConveyorRefinement.rbxm) · [Größenvergleich und Details](foerderband_modell.jpg) · [Animierter Arbeitszyklus](foerderband_arbeitszyklus.gif)

Das Gestell ist breiter, die Bodenaufnahme sitzt zwischen zwei seitlichen Führungen und der Antrieb liegt vor der Wand des Sammelbehälters. Die neun Eimer nehmen unten Sand auf, kippen ihn am oberen Kettenrad aus und laufen leer zurück. Im Arbeitszyklus beansprucht das Modell rund 5,72 × 6,28 × 10,03 Studs (Breite × Höhe × Länge). Die Vorschau zeigt daneben einen 5,18 Studs hohen Avatar im selben Maßstab.

## Übergabe an Claude

Das RBXM enthält das Rig `bucket_chain`. Der aktualisierte `Animations/WorkLoop` dauert 2,96 Sekunden. Die neun `Discharge`-Marker behalten ihre Zeitpunkte, und das `Discharge`-Attachment sitzt an der Eimerkante zum Zeitpunkt des Auswurfs. `WorkOrigin` sitzt weiter an der bisherigen Stelle. Die [Sandeffekte](../equipment_sand_fx/README.md) und [Geräusche](../../audio/equipment/README.md) verwenden dieselben Marker. [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

Nach dem Export wurden die neun Auswurfpositionen und der Abstand der Eimer zu beiden Rollen und zum Gestell lokal geprüft. Das GIF verwendet die exportierten Modelle und stellt die Sandpartikel näherungsweise dar. Ein Studio-Wiedergabetest steht noch aus.

```powershell
lune run assets/models/conveyor_refinement/BuildConveyorRefinement.luau
```
