# Oase in Roblox Studio

Die Oase liegt hinter dem Signalturm an der Karawanenroute. Der Pass führt durch ein altes Tor ans Westufer und verzweigt sich dort zur Wasserstation, zum Fischersteg und zum nördlichen Palmenhain. Am Ostufer steht die ehemalige Quellterrasse. Das Terrainpaket bearbeitet einen Ausschnitt von 448 × 480 Studs einschließlich des Passes. Der See misst in der Draufsicht rund 150 × 105 Studs.

- [Ufer, Steg und Palmenhain](oase_am_ufer.jpg)
- [Wasserstation](oase_wasserstation.jpg)
- [Ankunft in der Oase](oase_karawanenpass.jpg)
- [Rastbank und Abzweig zum Karawanenwrack vor dem Oasentor](../duenenmeer_v3/oasis_approach/README.md)
- [Krug bei der Freilegungsprobe](oase_fundprobe.jpg)
- [Wasserlauf, Uferwellen und Quellplätschern](shore_fx/README.md)
- [Altes Schöpfrad mit Tongefäßen und Sammelbecken](schoepfrad/README.md)

| Landmarke | X / Z |
| --- | ---: |
| Signalturm im Dünenmeer | 107 / 398 |
| Altes Tor am Pass | 221 / 565 |
| Fischersteg | 315 / 604 |
| Wasserstation | 367 / 590 |
| Quellterrasse | 403 / 660 |
| Schöpfrad | 388,8 / 668,4 |

Die beiden Fundstellen liegen unter dem roten Sand. Sichtbare Tonscherben markieren die Position. Die Art-Klone bestehen aus vorhandenen Vorlagen aus der Fundbibliothek.

| Fund | Vorlagen-ID | X / Z |
| --- | --- | ---: |
| Zweihenkelkrug | `oase_09` | 248 / 586 |
| Mosaikstein | `oase_26` | 394 / 624 |

## Aufbau

1. `BuildOasisTerrain.editor.luau` in der Studio-Befehlsleiste von **Every Last Grain** im Bearbeitungsmodus ausführen. Das Werkzeug setzt das Dünenmeer V3 voraus.
2. Auf `BuildStatus = Ready` in `ServerStorage.DuneBaron_PreOasisTerrainV1` warten. Der fertige Lauf hat 56 Terrainabschnitte geschrieben.
3. `BuildOasisArt.editor.luau` ausführen. Das Werkzeug erstellt `Workspace.DuneBaronWorld.OasisArtV1`. Die Regenemitter unter `WeatherPresets` sind für die spätere Anbindung deaktiviert.

Der Sicherungsordner enthält die ursprünglichen Voxel des bearbeiteten Ausschnitts und die vorherigen Wasserparameter. Ein erneuter Terrainaufbau verwendet den ursprünglichen Ausschnitt als Ausgangspunkt.

## Geprüft

- Sieben Teilstrecken mit Roblox-Pathfinding ohne Sprünge geprüft. Im Desktop-Spieltest vom Signalturm durch den Pass zur Wasserstation und bis auf den Fischersteg gelaufen.
- Beide Fundstücke durch ein vorübergehendes Abtragen der roten Voxel im Studio-Client sichtbar gemacht. Der Serverboden blieb unverändert. Die bestehende Grabaktion war an diesem Test nicht beteiligt.
- Alle 21 Palmen verwenden zusammen 42 zusammengefasste Kronenmeshes. Die Textur der Regenemitter wurde im Studio-Client erfolgreich geladen.

## Übergabe für die Spielintegration

Die Terrain-Slots 48 bis 50 verwenden Sand als Basismaterial, mit getrennten Farben für roten Sand, Wege und feuchtes Ufer. In diesem Studio-Build melden Raycasts und `SolidMaterial` für diese Voxel `Grass`. `SolidMaterialIndex` liefert den richtigen Slot. Die Grabverformung muss für diese Zone die Slots 48 bis 50 erkennen und beim Lesen, Abtragen und Nachwachsen `SolidMaterialIndex` sowie `LiquidOccupancy` erhalten. Die Fels-Slots sind 51 bis 53. [Roblox Terrain-API](https://create.roblox.com/docs/reference/engine/classes/Terrain#ReadVoxelChannels)

Die Zone stellt Gelände, Bauwerke und Fundpositionen bereit. Freischaltung, rote Sandsorte, Fundbelohnungen und wetterabhängige Fundchancen bleiben Spielintegration.
