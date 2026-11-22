# Canyon in Roblox Studio

Östlich der Oase beginnt der Canyon am Schichtentor. Der helle Sandweg windet sich zwischen rotbraunen Felswänden bis zum östlichen Ausgang. Der bearbeitete Geländeabschnitt misst **672 × 584 Studs**. In einem gemessenen Querschnitt liegen zwischen Wegsohle und Felskamm rund 90 Studs Höhenunterschied.

[Schichtentor während des Aufbaus](schichtentor.jpg) · [Freigelegte Kristallgeode im Studio-Spieltest](ausgrabungsprobe.jpg) · [Fossilien-Werkbank und Quarzader](expedition_details/README.md) · [Alte Lastenstation](lastenstation/README.md)

| Ort | X / Z | Gestaltung |
| --- | ---: | --- |
| Ostweg der Oase | 376 / 574 | Anschluss an den Weg nahe der Wasserstation |
| Schichtentor | 555 / 607 | Breiter Sandsteinbogen in der ersten Enge |
| Fossilienwand | 664 / 749 | Seitentasche mit Ammonit und Trilobitrelief |
| Vermessungslager | 763 / 635 | Zwei Planenunterstände, Probenkisten und ein Arbeitstisch |
| Versunkener Durchgang | 868 / 753 | Begehbarer Ruinenrest mit türkisen Einlagen und gestürztem Sturzstein |
| Ostausgang | 1053 / 842 | Anschlussfläche am Ende des hellen Sandwegs |

| Fundprobe | ID | X / Z |
| --- | --- | ---: |
| Trilobit | `canyon_04` | 673 / 731 |
| Grubenlampe | `canyon_15` | 755 / 651 |
| Kristallgeode | `canyon_27` | 870 / 758 |

Die drei Modelle liegen rund 1,65 Studs unter der Oberfläche. Kleine Steinsplitter markieren die Fundstellen. Die Modelle liegen in `Workspace.DuneBaronWorld.CanyonArtV1.BuriedFinds` und tragen ihre bisherigen Fund-IDs und Icon-Attribute.

## Studio-Prüfung

- 20 Teilstrecken vom Oasenweg bis zum Ausgang und zu den drei Abzweigen mit Roblox Pathfinding ohne Sprünge geprüft. Im Spieltest lief der Avatar vom Oasenweg durch das Schichtentor bis zum versunkenen Durchgang.
- Passage am Schichtentor mit 13 Studs Pfadradius und 13 Studs Höhe geprüft. Diese Maße decken das vorhandene Harvester-Modell ab.
- Alle drei Fundproben im Studio-Client durch vorübergehendes Abtragen der Voxel freigelegt. Der Serverboden lag währenddessen an allen drei Stellen weiter auf der ursprünglichen Höhe.
- Elf Stichproben auf dem Hauptweg verwenden den hellen Sand-Slot 54. An den Wänden sind die Gesteinsschichten auf unterschiedlichen Höhen sichtbar.

## Aufbau und Übergabe

Der Canyon liegt im geöffneten Entwurf **Every Last Grain**. Für den wiederholbaren Aufbau auf Basis von Oase V1 liegen [Gelände](BuildCanyonTerrain.editor.luau) und [Bauwerke](BuildCanyonArt.editor.luau) im Ordner. Der Geländeaufbau legt vor 71 Schreibabschnitten einen Voxel-Schnappschuss unter `ServerStorage.DuneBaron_PreCanyonTerrainV1` an. Das Art-Paket liegt unter `Workspace.DuneBaronWorld.CanyonArtV1`.

Die Slots 54 und 55 verwenden Sand als Basis und bilden den hellen Weg und seine dunkleren Ränder. Die Slots 56 bis 59 bilden die vier Sandsteinschichten. Für Claude sind Freischaltung, Erkennung von weißem Sand beim Graben und Fundbelohnungen die anschließende Spielintegration. [Roblox Terrain-API](https://create.roblox.com/docs/reference/engine/classes/Terrain#ReadVoxelChannels)
