# Innenraum des verschütteten Archivs

[Roblox-Modell](DuneBaron_ArchiveInterior.rbxm) · [Vorschau vor und nach simuliertem Sandabtrag](archiv_innenraum_vorschau.jpg)

Das Archiv bei **X 2090 / Z 931** hat jetzt ein steinernes Lesepult mit geneigter Registerplatte, Siegelstempel und Griffel. Gegenüber steht ein Regal mit 14 Tontafeln, einigen leeren Fächern und einem verschlossenen Tonbehälter. Abgebrochene Mauerstützen verbinden die vier vorhandenen, aus dem Sand ragenden Steine mit dem Mauerwerk unter der Oberfläche.

## Einbau

Nach Gelände und Bauwerken der [Ruinenstadt](../README.md) den Inhalt von [BuildArchiveInterior.editor.luau](BuildArchiveInterior.editor.luau) im Studio-Bearbeitungsmodus von **Every Last Grain** ausführen. Das Werkzeug richtet den Innenraum anhand der mittleren Originalbodenplatte aus. Das Modell landet unter `Workspace.DuneBaronWorld.RuinsArtV1.BuriedStructures["Versandetes Archiv"].ArchiveInteriorV1`. Die RBXM-Datei enthält dieselbe Geometrie auf den lokal berechneten Kartenkoordinaten.

## Lokal geprüft

- Die höchste neue Einrichtung liegt rund 1,6 Studs unter dem unberührten Sand. Die vier zusätzlichen Mauerstützen liegen ebenfalls darunter und treffen die vorhandenen Steine und deren Sockel.
- Zwischen Pult und Regal bleibt ein Mittelgang von mindestens 7,6 Studs. Vom Mittelpunkt des vorhandenen Steinbolzen-Funds bis zur nächsten Kante der Einrichtung sind es knapp drei Studs.
- Die Vorschau zeigt eine lokal simulierte Freilegung bis zum Archivboden. Einbau und Freilegung mit der Grabfunktion in Roblox Studio stehen aus.
