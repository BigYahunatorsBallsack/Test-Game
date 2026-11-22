# Salzsee in Roblox Studio

Der Salzsee beginnt am östlichen Ausgang des Canyons. Der Geländeabschnitt misst **672 × 656 Studs**. Zwei trockene Uferwege führen um die Sole und treffen sich am Ostpass. In der Seemitte liegen rund 3,1 Studs Wasser über dem Grund. Auf den vier niedrigen Inseln und am Ufer wachsen Kristalle zwischen gebrochenen Salzplatten.

[Studio-Übersicht](salzsee.jpg) · [Freigelegtes Ankerstück im Spieltest](fundprobe.jpg) · [Neues Frachtschiff und Anleger für die Wrackbucht](wreck_bay/README.md) · [Windwarte und Aussichtsplattform](windwarte/README.md)

| Ort | X / Z | Gestaltung |
| --- | ---: | --- |
| Canyon-Ausgang | 1053 / 842 | Anschluss an den hellen Canyonweg |
| Windwarte | 1227 / 837 | Aussichtsplattform und Windsack zwischen den Uferwegen als lokales Modellpaket |
| Solestation | 1250 / 764 | Gestreifte Plane, Probenbank und Kisten |
| Wrackbucht | 1284 / 786 | Versandete Schiffsrippen und lose Planken |
| Seemitte | 1381 / 871 | Flache Sole, Salzinseln und lokaler Dunst |
| Alte Salzwaage | 1478 / 984 | Kalksteinfundament und verwitterte Balkenwaage |
| Ostpass | 1678 / 837 | Trockener Geländeanschluss östlich der Uferwege |

| Fundprobe | ID | X / Z |
| --- | --- | ---: |
| Ankerstück | `salzsee_15` | 1273 / 792 |
| Salzfächer | `salzsee_09` | 1357 / 757 |
| Muschelanhänger | `salzsee_27` | 1434 / 983 |
| Salzsiegel | `salzsee_29` | 1499 / 993 |

Die vier Fundmodelle stammen aus der bestehenden Bibliothek und liegen rund 1,5 Studs unter der örtlichen Oberfläche in `Workspace.DuneBaronWorld.SaltLakeArtV1.BuriedFinds`.

## Studio-Prüfung

- Der Avatar lief im Spieltest vom Canyon-Ausgang bis zur Wrackbucht. Roblox Pathfinding fand auf allen 22 Teilstrecken der beiden Uferwege einen Pfad ohne Sprünge, sowohl für den Avatar als auch mit 13 Studs Prüfradius und 13 Studs Höhe für den Harvester.
- Im Studio-Client ließ sich jede Fundprobe durch vorübergehendes Abtragen der Voxel vollständig freilegen. Der Serverboden behielt seine Höhe. Nach Ende des Spieltests waren alle vier Fundmodelle im Editor wieder bedeckt.
- Die sechs lokalen Nebelemitter konnten ihre Textur im Studio-Client laden. Die Sole verwendet das türkisfarbene Terrain-Wasser des Places. Die gemeinsamen Wasserwerte und die Wasserhöhe der Oase wurden überprüft.

## Aufbau und Übergabe

Im Studio-Entwurf **Every Last Grain** liegt das Gelände in `Workspace.Terrain` und die Dekoration in `Workspace.DuneBaronWorld.SaltLakeArtV1`. Für den wiederholbaren Aufbau auf Basis von Canyon V1 dienen [Gelände](BuildSaltLakeTerrain.editor.luau) und [Bauwerke](BuildSaltLakeArt.editor.luau). Vor dem Schreiben der 121 Geländeabschnitte legt das Geländeskript eine Voxel-Sicherung in `ServerStorage.DuneBaron_PreSaltLakeTerrainV1` an.

Die Slots 60 und 61 verwenden Sand als Basis für trockenen Kristallsand und feuchten Ufersand. Für die Spielintegration benötigt Claude die Zonen-ID `salt_lake` und kann die beiden Sandvarianten über `SolidMaterialIndex` erkennen. Freischaltung, Abbau im Salzsee und Fundbelohnungen folgen in der Spielintegration. [Roblox Terrain-API](https://create.roblox.com/docs/reference/engine/classes/Terrain#ReadVoxelChannels)
