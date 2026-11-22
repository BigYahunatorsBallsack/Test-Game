# Grabungsdetails für den Canyon

[Modellvorschau](canyon_grabungsdetails.jpg) · [Maße und Platzierung](manifest.json)

| Modell | Ort | X / Z | Maße in Studs | Dreiecke |
| --- | --- | ---: | --- | ---: |
| [Fossilien-Werkbank](canyon_fossil_workbench.glb) | Vor der Fossilienwand | 649 / 733 | 7,14 × 4,08 × 3,12 | 2.773 |
| [Quarzader](canyon_quartz_seam.glb) | Neben dem versunkenen Durchgang | 895 / 767 | 8,58 × 4,10 × 4,15 | 630 |

Auf der Werkbank stehen ein Ammonitenabdruck, eine Probenschale und eine Bürste. Die Quarzader zieht sich als helles Band durch orangefarbene Gesteinsschichten. An der Oberfläche ragen kleine Kristallspitzen aus dem Gestein. Die Modelle dienen als Umgebungsausstattung.

## Einbau

Beide GLBs mit `Scale Unit = Studs` und Vertexfarben importieren. Die beiden importierten Wurzeln unter `ServerStorage.DuneBaronCanyonDetails` ablegen und nach den Dateinamen ohne Endung benennen. [Roblox Importer](https://create.roblox.com/docs/studio/importer)

[PlaceCanyonDetails.editor.luau](PlaceCanyonDetails.editor.luau) im Studio-Bearbeitungsmodus von **Every Last Grain** ausführen. Es setzt die Modelle am Gelände auf und legt sie in `Workspace.DuneBaronWorld.CanyonArtV1.CanyonExpeditionDetailsV1` ab. Beide Modelle sind verankerte, durchquerbare Dekoration.

Die GLBs wurden mit ihren eingebetteten Farben erneut eingelesen und in derselben Skalierung gerendert. Laut Geländebauplan liegen die Modellkanten 54,1 und 32,2 Studs von der Mitte des Hauptwegs entfernt. Die Platzierung wurde lokal mit importiertem Modell und Einzelteil nachgestellt. Studio-Import und Spieltest stehen aus.

[Modelle neu exportieren](build_canyon_details.py)
