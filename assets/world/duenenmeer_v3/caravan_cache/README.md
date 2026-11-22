# Verschüttete Vorratskammer

[Roblox-Modell](DuneBaron_BuriedCaravanCache.rbxm) · [Vorher, nachher und Lage auf der Route](vorratskammer_vorschau.jpg)

Die Kammer liegt bei **X 109 / Z 347**, östlich der Karawanenroute zwischen Unterstand und Signalturm. Zwei niedrige Steinspuren zweigen von der Route ab. Am Ziel ragen ein abgebrochener Türrest mit türkiser Kante, Tonscherben und der Rest eines Seitenpfeilers aus dem Sand.

Unter dem Sand liegt eine etwa 11 × 10 Studs große Kammer mit drei Eingangsstufen, gestaffelten Steinwänden, vier Vorratskrügen, einer zerbrochenen Kiste und einem türkisen Bodensiegel. Das tiefe Fundament hält die sichtbaren Mauern mit dem Boden verbunden, wenn der Sand um sie herum abgetragen wird.

## Einbau und Übergabe

Im Studio-Bearbeitungsmodus von **Every Last Grain** den Inhalt von [BuildCaravanCache.editor.luau](BuildCaravanCache.editor.luau) in der Befehlsleiste ausführen. Das Werkzeug misst das vorhandene V3-Sandgelände und setzt `BuriedCaravanCache` unter `Workspace.DuneBaronWorld.ArtV3` ein. Die RBXM-Datei enthält dieselbe Kammer an den aus dem V3-Höhenfeld berechneten Koordinaten. [Roblox Terrain-Raycasts](https://create.roblox.com/docs/reference/engine/classes/WorldRoot#Raycast)

Die drei Prüfstellen **Schwelle**, **Vorratsnische** und **Vorratssiegel** liegen in `DigProbes` und tragen `ProbeX`, `ProbeZ`, `SurfaceY` und `HiddenTopY`. Die Steine sind verankert und lassen Grabstrahlen durch. Fund-ID und Belohnung folgen in der Spielanbindung durch Claude.

In der lokalen Voxelprobe lagen die geprüften Bodenpunkte 2,28 bis 3,03 Studs unter der ursprünglichen Oberfläche. Mit der bestehenden Grablogik wurden die drei Prüfstellen nach zwei bis drei Schaufelimpulsen sichtbar. Die Vorschau zeigt eine breitere Freilegung nach versetzten Grabungen. Ein Lauf- und Grabtest im Studio-Place steht noch aus.

```powershell
lune run assets/world/duenenmeer_v3/caravan_cache/BuildCaravanCache.editor.luau
```
