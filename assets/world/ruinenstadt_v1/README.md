# Ruinenstadt in Roblox Studio

Hinter dem Ostpass des Salzsees geht die helle Salzkruste in schwarzen Sand über. Die Ruinenstadt misst **776 × 704 Studs**. Geschichtete Felsen umgeben eine alte Pflasterstraße mit zwei Außenwegen. Heller Sandstein und vereinzelte türkise Einlagen machen die Ruinen auch aus größerer Entfernung erkennbar.

[Überblick über die Ruinenstadt](ruinenstadt.jpg) · [Freigelegtes Archiv im Studio-Spieltest](archiv-freigelegt.jpg) · [Versandetes Karawanenrelief](karawanenrelief/README.md) · [Signalwarte am Wachtgrat](wachtgrat/README.md)

| Ort | X / Z | Gestaltung |
| --- | ---: | --- |
| Karawanenrelief | 1806 / 841 | Geneigte Stele mit Dromedar und vergrabenen Frachtzeichen als lokales Modellpaket |
| Tor der Salzkarawanen | 1874 / 866 | Breite Durchfahrt, Steinpfeiler und Siegelrelief über dem Tor |
| Grabungslager | 1844 / 899 | Plane, Probenkisten und Arbeitstisch |
| Sonnenplatz | 1993 / 856 | Säulenreste und ein halb versunkenes Podest mit Rundrelief |
| Versunkene Stufen | 2021 / 761 | Halbkreis aus gestaffelten Sitzreihen |
| Warenviertel | 2046 / 911 | Drei offene Räume mit Schwellen und alten Ladentischen |
| Zisternenhof | 2102 / 833 | Verlandete Steinzisterne mit niedriger Einfassung und Trennwand |
| Tempel am Ostgrat | 2262 / 849 | Begehbare Stufen, Vorhalle und Opfernischen |
| Wachtgrat | 2365 / 899 | Säulenreste an der östlichen Anhöhe |
| Signalwarte | 2363 / 849 | Runder Sandsteinbau mit Stufen, Kompassrose und Blick zum Osttempel als lokales Modellpaket |

## Vergrabene Bauwerke und Funde

Vom **versandeten Archiv** bei 2090 / 931 und der **überwehten Siegelkammer** bei 2145 / 810 ragen nur einzelne Steinkanten aus dem Sand. Unter der Oberfläche liegen Pflaster, Wände, Schwellen und Reliefs. Das Archiv ist rund 29 Studs breit und sein Fußboden liegt etwa 5,5 Studs unter dem Sand. Die Siegelkammer ist rund 21,5 Studs breit und etwa 4 Studs tief. Beide Bauwerke liegen in `Workspace.DuneBaronWorld.RuinsArtV1.BuriedStructures`.

Das [Innenraumpaket für das Archiv](archiv_innenraum/README.md) ergänzt ein Lesepult, ein Tontafelregister und die verschütteten Stützen der sichtbaren Steinblöcke.

| Fundprobe | ID | X / Z |
| --- | --- | ---: |
| Reliefsplitter | `ruinenstadt_04` | 1857 / 894 |
| Duftlampe | `ruinenstadt_09` | 2027 / 773 |
| Steinbolzen | `ruinenstadt_26` | 2089 / 931 |
| Fingerglied | `ruinenstadt_27` | 2216 / 855 |

Die vier Fundproben behalten die Zuordnung zu ihren Icons in der Bibliothek. Sie liegen rund 1,5 Studs unter der Oberfläche in `RuinsArtV1.BuriedFinds`.

## Wegmarken und Grabungsspuren

Zwei bernsteinfarbene Laternen rahmen das Karawanentor ein. Drei Sandsteinstelen mit türkisem Rundrelief markieren den Nordabzweig, den Weg zum Archiv und den Aufstieg zum Osttempel. Am Archiv und an der Siegelkammer stehen niedrige Vermessungspfähle mit Stoffstreifen und Probenschalen. Die Spuren sitzen einige Studs vor dem Mauerwerk, damit die erste Steinkante im schwarzen Sand der eigentliche Fund bleibt. [Modellvorschau](wegmarken_modelle.jpg) · [Lageplan](wegmarken_lageplan.png)

Das [Roblox-Modellpaket](DuneBaron_Ruins_Wayfinding.rbxm) enthält vier statische Vorlagen für sieben Standorte. Für den Einbau den enthaltenen Ordner in `ServerStorage` einsetzen und [das Platzierungsskript](PlaceRuinsWayfinding.editor.luau) im Studio-Bearbeitungsmodus ausführen. Es setzt die Modelle am jeweiligen Gelände auf und legt sie in `DuneBaronWorld.RuinsArtV1.RuinsWayfindingV1` ab. [Neubau der Vorlagen mit Lune](BuildRuinsWayfinding.luau) · [Roblox PVInstance.PivotTo](https://create.roblox.com/docs/reference/engine/classes/PVInstance#PivotTo) · [Roblox WorldRoot.Raycast](https://create.roblox.com/docs/reference/engine/classes/WorldRoot#Raycast)

Die Modelle sind verankert und lassen sich durchqueren. Die nächstgelegene Modellkante hält nach dem Geländebauplan mindestens 14,8 Studs Abstand zur Mitte einer Fahrroute. Modellpaket und Standorte wurden lokal geprüft. Vorschau und Lageplan sind lokale Renderings. Ein Einbau und Spieltest im Studio-Entwurf stehen aus.

## Studio-Prüfung

- Der Avatar lief im Spieltest vom Ostpass des Salzsees durch das Karawanentor zu einem Laden im Warenviertel. Beim Warenviertel wurde der mittlere Eingang nach der ersten Pfadprüfung verbreitert und erneut geprüft.
- Auf der Hauptstraße und den beiden äußeren Wegen fand Roblox Pathfinding für alle 26 Teilstrecken einen Pfad ohne Sprünge. Die Prüfung mit 13 Studs Radius und 13 Studs Höhe führte den Harvester-Pfad direkt unter dem Tor hindurch. Die Stufen des Osttempels wurden zusätzlich mit Avatar-Maßen geprüft.
- Im Studio-Client wurden in beiden Grabungen Boden und Mauerwerk sowie alle vier Fundmodelle durch vorübergehenden Geländeabtrag freigelegt. Der Serverboden behielt seine ursprüngliche Höhe. Im Entwurf liegen die Bauwerke und Fundmodelle wieder unter Sand.

## Aufbau und Übergabe

Die Ruinenstadt liegt im Studio-Entwurf **Every Last Grain**. [Gelände](BuildRuinsTerrain.editor.luau) und [Bauwerke](BuildRuinsArt.editor.luau) erzeugen die Zone auf Basis von Salzsee V1. Vor dem Schreiben der 143 Geländeabschnitte wird ein Voxel-Schnappschuss in `ServerStorage.DuneBaron_PreRuinsTerrainV1` angelegt.

Beide schwarzen Sandvarianten verwenden Sand als Basis und sind über `SolidMaterialIndex` 62 und 63 erkennbar. Für die Spielintegration bleiben Freischaltung (`ruins`, `sandstorm_1`), Abbau und Fundbelohnungen bei Claude. Die Bauwerke können beim Abtragen umgebender Voxel an ihrem Platz bleiben. [Roblox Terrain-API](https://create.roblox.com/docs/reference/engine/classes/Terrain#ReadVoxelChannels)
