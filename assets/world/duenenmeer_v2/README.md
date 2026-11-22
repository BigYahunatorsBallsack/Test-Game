# Dünenmeer Art V2

Die überarbeitete Dünenmeer-Zone liegt in Studio unter `Workspace.DuneBaronWorld.ArtV2`. Das Händlerlager hat ein zweites Stoffdach, Vorräte, Wasser und einen Vermessungstisch. Die Wege führen vom Lager zum Maschinenhof, zur ausgegrabenen Karawanenstation und zum alten Torbogen. Felswände mit gebrochenen Sedimentschichten, Wegsteine, Keramik und trockene Pflanzen verbinden die Orte.

| Fundstelle | Koordinaten X/Z | Hinweis an der Oberfläche | Freilegbar |
| --- | --- | --- | --- |
| Vermessungssiegel | 31 / 48 | Abgesplitterte Steinkante und zwei Scherben | Türkisfarbenes Siegel auf einer eingelassenen Steinplatte |
| Verschüttete Zisterne | −45 / 92 | Bruchstücke eines Sturzes und farbige Keramik | Oberste Steinlagen, Stufen und der Rest einer Abdeckplatte |
| Karawanentor | 29 / 115 | Erhaltener Torbogen und steinerne Wegmarken | Stufen und Mosaik am verschütteten Durchgang |

Die bestehende Grabfunktion legt die oberen Schichten frei. Im Desktop-Client sank die Sandoberfläche an allen drei Prüfstellen unter die Oberkante der verborgenen Geometrie. Für das Siegel waren es 6,00 → 3,56 Studs, für die Zisterne 6,00 → 3,87 und für das Tor 6,00 → 4,97. Das Gelände wächst wie bisher nach. Beim Siegel blieb der Serverboden auf 6,00 Studs. Die Prüfung der Laufwege vom Spawn zum Händler, zum Sandfeld und zu allen drei Fundstellen war erfolgreich. Handy-Leistung steht noch aus.

## Übergabe an Claude

- `DuneBaron_Duenenmeer_ArtV2.rbxm` ist eine Ergänzung für das vorhandene Dünenmeer-Terrain mit Weltkoordinaten. Den Ordner `ArtV2` unter `Workspace.DuneBaronWorld` einsetzen. Der Export enthält die neue Geometrie, die Maschinen als Schaustücke und die Fundstellen. Terrain, Spawn, Händler und bestehende Spiellogik kommen aus dem Place.
- Im aktuellen Studio-Entwurf sind die ersetzten alten Felsen, Ausgrabungsblöcke und Maschinen unter `ServerStorage.DuneBaron_ArtV2PreviousDecor` abgelegt. Bei Übernahme in einen älteren Place dieselben alten Dekoobjekte ausblenden. Die ursprünglichen Modelle in der Asset-Bibliothek bleiben separat verfügbar.
- Die Modelle in `ArtV2/Ruins` haben `ProbeX`, `ProbeZ`, `SurfaceY` und `HiddenTopY`. Die Bauteile in `BuriedStone` lassen den bestehenden Grabstrahl durch. Fundbelohnungen und bleibender oder gemeinsamer Fortschritt sind separate Spielintegration.
- Das Förderband im Maschinenpaket und im Maschinenhof ist 4,75 Studs hoch. Die Bewegung aller neun Eimer wurde nach dem Skalieren im Studio-Client geprüft.

Der Stand liegt als Studio-Vorschau und als lokales Modellpaket vor. Das Dünenmeer-Paket wurde in Studio erneut eingelesen und überprüft. Es enthält 1.778 Bauteile und keine Laufzeitskripte.

Der [neue Maschinenhof](../machine_yard/README.md) liegt als separates Modellpaket mit vier aktuellen Schaustücken, offenem Besucherweg und Werkstatt vor.
