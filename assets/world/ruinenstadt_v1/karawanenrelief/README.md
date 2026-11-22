# Versandetes Karawanenrelief

[Roblox-Modell](DuneBaron_CaravanRelief.rbxm) · [Vorschau mit Freilegungsvergleich und Lageplan](karawanenrelief_vorschau.jpg)

Die schräg im schwarzen Sand stehende Stele markiert den Weg vom Salzpass zum Tor der Salzkarawanen. Sie steht bei **X 1806 / Z 841**. Über dem Sand sind ein Dromedar mit Salzladung und ein türkis eingelegtes Sonnensiegel zu sehen. Unter der Oberfläche liegen fünf Frachtzeichen, ein schmales Wellenband und die alte Sockelkante.

## Einbau

Nach Gelände und Bauwerken der [Ruinenstadt](../README.md) den Inhalt von [BuildCaravanRelief.editor.luau](BuildCaravanRelief.editor.luau) im Studio-Bearbeitungsmodus von **Every Last Grain** ausführen. Das Werkzeug misst die vorhandene Voxeloberfläche und setzt das Modell unter `Workspace.DuneBaronWorld.RuinsArtV1.BuriedCaravanReliefV1`. Die RBXM-Datei enthält dieselbe Geometrie auf den lokal berechneten Kartenkoordinaten.

Stele und Sockel haben Kollision. Reliefdetails und Schutt sind dekorativ. Die Attribute `RevealFocusX` und `RevealFocusZ` markieren die Mitte vor der unteren Reliefreihe für eine spätere Grabprobe.

## Lokal geprüft

- Die Stele ragt am höchsten Punkt rund 10,6 Studs aus dem Sand. Ihre Silhouette ist im Geländeplan von der Anfahrt aus sichtbar.
- Die nächste Modellkante liegt 24,8 Studs von der Mitte der Karawanenstraße entfernt.
- Die Frachtzeichen und Rahmen liegen im lokalen Höhenfeld 0,4 bis 2,5 Studs unter dem Sand. Die Vorschau zeigt sie mit einer simulierten Absenkung vor der Stele.

Einbau, Begehung und Freilegung mit der Grabfunktion in Studio stehen aus.
