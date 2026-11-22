# Der Koloss in Roblox Studio

Die Grabungsstätte liegt westlich des Startlagers im Dünenmeer. Eine breite Sandzufahrt führt vom Lager zu zwei äußeren Terrassenwegen. Unterstände, Probenbänke, Seilmarkierungen und niedrige Sandsteinmauern säumen das Becken. Die sichtbare Hand, der Kopf und das türkise Brustrelief geben der liegenden Figur ihre Silhouette.

[Koloss neben Avatar und Harvester](koloss-massstab.jpg) · [Nordhand im lokalen Grabungstest](nordhand-freigelegt.jpg) · [Vermessungsstand am Nordrand](vermessungsstand/README.md)

| Ort | X / Z |
| --- | ---: |
| Abzweig vom Startlager | −44 / −10 |
| Aussichtspunkt am Ende der Zufahrt | −307 / −24 |
| Vermessungsstand mit Fernrohr | −288 / −78 |
| Südliches Grabungslager | −320 / 47 |
| Nördliche Probenstation | −446 / −108 |
| Brust der Figur | −438 / −25 |
| Vergrabene Nordhand | −386 / −60 |
| Vergrabene Füße | −327 / −42 und −327 / −6 |

Die Figur misst rund **102 Studs Breite, 59 Studs Höhe und 174 Studs Länge**, einschließlich der verschütteten Teile. Im Größenvergleich misst der Avatar 5,5 Studs Höhe und der vorhandene Harvester 19,5 Studs Länge. Kopf, Rumpf, beide Arme und Beine liegen in eigenen Gruppen. Beim Kopf wurden die Augenhöhlen und der Mund direkt in die zusammenhängende Sandsteingeometrie geschnitten. [Roblox GeometryService](https://create.roblox.com/docs/reference/engine/classes/GeometryService)

## Studio-Prüfung

- Der Avatar lief vom Spawn bis zur unteren Südterrasse. Roblox Pathfinding fand ohne Sprünge auf allen 19 Abschnitten von Zufahrt und Außenwegen Platz für 13 Studs Radius und 13 Studs Höhe. Drei weitere Abschnitte auf der unteren Rampe wurden mit Avatar-Maßen geprüft.
- Elf Stichproben auf Nordhand und Füßen lagen zunächst 3,3 bis 7,4 Studs unter der Oberfläche. Durch vorübergehendes Abtragen im Studio-Client wurden alle elf freigelegt. Der Serverboden blieb auf der ursprünglichen Höhe. Im Editor sind Nordhand und Füße wieder bedeckt.
- Das Harvester-Modell in den Vergleichsaufnahmen war eine Kopie im Spieltest. Die Grabungsstätte im Editor enthält die Figur und ihre Umgebung.

## Aufbau und Übergabe

Das Modell liegt im Studio-Entwurf **Every Last Grain** unter `Workspace.DuneBaronWorld.ColossusArtV1.Koloss`. `ColossusArtV1.Grabungsflächen` enthält Mittelpunkt und Ausdehnung der beiden Freilegungsbereiche. Die Sandoberfläche verwendet den nativen Sand des Dünenmeers.

Zum Wiederaufbau auf Basis von Dünenmeer V3 dienen [Gelände](BuildColossusTerrain.editor.luau) und [Modell und Grabungslager](BuildColossusArt.editor.luau). Das Gelände wurde in 52 Abschnitten bearbeitet und vorher unter `ServerStorage.DuneBaron_PreColossusTerrainV1` gesichert. Der frühere Koloss-Prototyp liegt weiter in `ServerStorage.DuneBaronAssetLibrary.Core.colossus`.

Für Claude bleiben Event-Start, gemeinsamer Fortschritt, die Verwaltung der Event-Grabflächen und die Beitragsbelohnungen. Die Testfreilegung zeigt, welche Teile bei Änderungen am Terrain sichtbar werden. [Roblox Terrain-API](https://create.roblox.com/docs/reference/engine/classes/Terrain#ReadVoxelChannels)

Für die Event-Inszenierung liegen [Sand und Abschlusslicht](../koloss_fx/README.md), [Fortschrittsanzeige](../../ui/colossus/README.md) und [drei Eventklänge](../../audio/colossus/README.md) bereit.
