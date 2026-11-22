# Dünen-Harvester mit Steigband

[Roblox-Modell](DuneBaron_HarvesterRefinement.rbxm) · [Größenvergleich und Details](harvester_modell.jpg) · [Animierter Arbeitszyklus](harvester_arbeitszyklus.gif)

Die beiden Schneidwalzen tragen je 24 versetzte Keilzähne. Frontblende und Arbeitsleuchten sitzen höher, und die Seitenpanzer haben Verschleißleisten. Rechts von der Fahrerkabine fördert ein offenes Steigband Sand in den Sammelbehälter. Die Vorschau zeigt den rund 12,5 Studs hohen Harvester im selben Maßstab wie einen Standardavatar.

## Übergabe an Claude

Das RBXM enthält das Rig `mega_machine`. Der aktualisierte `Animations/WorkLoop` dauert 1,58 Sekunden. Die beiden `CutterLoad`-Marker behalten ihre Zeitpunkte. Sechs neue `HopperDrop`-Marker lösen über das vorhandene Modul `SandEffects` den Partikelauswurf am `HopperDischarge`-Attachment aus. `TravelLoop`, die drei Clips unter `DriverAnimations` und die Attachments `WorkOrigin`, `DriverMount` und `DriverRoot` bleiben im Rig verfügbar. [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

Lokal am Export geprüft wurden der Abstand der Zahnspitzen zu Blende und Leuchten sowie alle sechs Auswurfpositionen. Die Vorschau stellt die Partikel näherungsweise dar. Ein Studio-Wiedergabetest steht noch aus.

```powershell
lune run assets/models/harvester_refinement/BuildHarvesterRefinement.luau
```
