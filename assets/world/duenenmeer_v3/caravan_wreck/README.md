# Karawanenwrack im äußeren Dünenmeer

[Roblox-Modell](DuneBaron_CaravanWreck.rbxm) · [Vorschau mit Sandspur und Lageplan](karawanenwrack_vorschau.jpg)

Das Wrack liegt bei **X 246 / Z 548**, östlich der Route vom Signalturm zur Oase. Ockerfarbene [Wegmarken](../oasis_approach/README.md), Holzstücke und Tonscherben führen von der Route zum Frachtenwagen mit zerrissener Plane. Ein abgerissenes Rad, ein zweiter Achsbruch und verstreute Kisten liegen neben dem Wagen. Zwei niedrige Sandrücken ziehen sich vom Wrack in die äußeren Dünen.

## Einbau und Übergabe

Im Studio-Bearbeitungsmodus von **Every Last Grain** den Inhalt von [BuildCaravanWreck.editor.luau](BuildCaravanWreck.editor.luau) nach dem Aufbau der V3-Wegmarken und des Oase-V1-Geländes ausführen. Das Werkzeug misst die vorhandene Voxeloberfläche und setzt `LostCaravanWreck` unter `Workspace.DuneBaronWorld.ArtV3` ein. Die RBXM-Datei hat `ArtVersion = 2` und enthält dieselbe Szene auf den Koordinaten des zusammengesetzten Höhenfelds. Falls Version 1 bereits eingebaut wurde, den bisherigen Modellordner zuerst in `ServerStorage` sichern. [Roblox Terrain-Raycasts](https://create.roblox.com/docs/reference/engine/classes/WorldRoot#Raycast)

Das Modell besteht aus verankerten Bauteilen. Die Referenz `Approach.WreckFocus` speichert den Standort, den Sichtpunkt von der Route und das äußere Ende der Sandspur. Sandwurm-Spawn und Gameplay-Anbindung liegen bei Claude.

Der Geländeübergang zur Oase hebt den Boden am Wrackstandort um etwa 7,3 Studs an. Wagen, Räder und Trümmer wurden für diese Oberfläche neu ausgerichtet. Die äußere Sandspur verläuft fern der Verbindung zur Wasserstation. Die Vorschau wurde aus dem Modell und dem zusammengesetzten Höhenfeld gerendert. Ein Einbau und Laufwegtest in Studio stehen noch aus.

```powershell
lune run assets/world/duenenmeer_v3/caravan_wreck/BuildCaravanWreck.editor.luau
```
