# Wrackbucht am Salzsee

[Vorschau am Ufer](wrackbucht_vorschau.jpg) · [Maße und Platzierung](manifest.json)

| Modell | X / Z | Maße in Studs | Dreiecke |
| --- | ---: | ---: | ---: |
| [Versandetes Frachtschiff](salt_lake_wreck.glb) | 1286 / 790 | 11,89 × 8,37 × 28,21 | 4.036 |
| [Alter Anleger](salt_lake_dock.glb) | 1311 / 796 | 6,50 × 7,25 × 16,01 | 3.192 |

Der Bug, der gebrochene Mast und das offene Heck bilden die Silhouette. Eine Salzkruste zieht sich direkt durch die Rumpfplanken. Am Anleger stehen eine Handwinde mit Tau und sechs Pfähle. Die ersten knapp neun Studs bleiben als begehbare Planken erhalten. Dahinter enden die Bretter und nur die beschädigten Träger ragen noch in die Sole.

## Einbau

Beide GLBs in Studio mit `Scale Unit = Studs`, Standardachsen und Vertexfarben importieren. Die Wurzeln unter `ServerStorage.DuneBaronWreckBayV2` ablegen und nach den Dateinamen ohne Endung benennen. [Roblox Importer](https://create.roblox.com/docs/studio/importer)

[PlaceWreckBay.editor.luau](PlaceWreckBay.editor.luau) im Bearbeitungsmodus von **Every Last Grain** ausführen. Das Skript setzt das geneigte Schiff auf das Geländerelief, richtet den Anleger an der Wasserlinie aus und legt die begehbare Fläche auf die intakten Planken. Die ausgebaute Wrackbucht erscheint unter `SaltLakeArtV1.Landmarks.Wrackbucht`. Das bisherige Modell liegt nach der Übernahme unter `ServerStorage.DuneBaronWrackbuchtV1`. Für die Rückkehr zur ersten Fassung kann es wieder als `Wrackbucht` in den Landmarkenordner verschoben werden.

## Prüfung

Die GLBs und ihre eingebetteten Farben wurden erneut eingelesen. Laut Geländeplan beginnt der Anleger rund 0,46 Studs über dem trockenen Ufer, alle sechs Pfahlfüße erreichen den Boden und die äußeren Pfähle stehen in der Sole. Die Bounding Box des Schiffs bleibt mindestens 13,6 Studs von der Fahrwegmitte und 6,1 Studs vom vergrabenen Anker entfernt. Positionierung, begehbare Fläche und Sicherung der alten Fassung wurden lokal nachgestellt. Die Vorschau zeigt beide GLBs auf einem Rendering des Geländebauplans mit einer 5,5-Studs-Figur. Der Einbau und ein Spieltest in Studio stehen aus.

[Modelle neu exportieren](build_wreck_bay.py)
