# Saugroboter mit sichtbarem Sandeinlauf

[Roblox-Modell](DuneBaron_VacuumRefinement.rbxm) · [Detailansichten](saugroboter_modell.jpg) · [Animierter Arbeitszyklus](saugroboter_arbeitszyklus.gif)

Die Düse hat einen offenen Ansaugschlitz mit zurückgesetzten Lamellen und zwei Gleitschuhen. Eine Drehkupplung verbindet den schwenkenden Schlauch mit dem Tank, in dem neun animierte Sandkörner aus einem gebogenen Zulauf fallen. Bei laufender Absaugung leuchtet die Anzeige am Tank. Das Modell bleibt rund 2,1 Studs hoch.

## Übergabe an Claude

Das RBXM enthält ein einzelnes Rig namens `vacuum_robot`. Der aktualisierte `Animations/WorkLoop` dauert 1,86 Sekunden und enthält die neuen Bewegungen für Körner, Sandoberfläche und Anzeige. `IntakeEngage`, `IntakeSweep` und `IntakeRelease` liegen an den bestehenden Zeitpunkten. Die [Sandeffekte](../equipment_sand_fx/README.md) und [Geräusche](../../audio/equipment/README.md) verwenden dieselben Marker. Die Sandoberfläche zeigt eine einzelne eintreffende Portion und setzt sich zum Ende des Clips.

Das exportierte Modell wurde erneut eingelesen. Düse, Kupplung und Körnerbahnen wurden lokal über den Arbeitszyklus geprüft. Die animierte Vorschau verwendet die exportierte Geometrie und stellt die Saugeffektpartikel näherungsweise dar. Ein Studio-Wiedergabetest steht noch aus.

```powershell
lune run assets/models/vacuum_refinement/BuildVacuumRefinement.luau
```
