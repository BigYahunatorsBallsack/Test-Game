# Dünenmeer in Roblox Studio

Das Sandgelände misst 2.304 × 2.304 Studs. Die langen, leicht versetzten Dünenkämme haben flache Windseiten und steilere Leeseiten. Mehrere Dünenreihen und Dunst verdecken den Kartenrand vom erschlossenen Gebiet aus.

Hinter dem Karawanentor bei X/Z **29 / 115** führen Wegsteine zum verlassenen Unterstand bei **67 / 263** und zum Signalturm bei **107 / 398**. Im alten Kernbereich liegt die Sandoberfläche weiterhin auf der bisherigen Höhe. Die neuen Bauwerke liegen unter `Workspace.DuneBaronWorld.ArtV3`.

- [Dünenmeer im Überblick](duenenmeer_weitblick.jpg)
- [Weg vom Karawanentor in die Dünen](karawanentor.jpg)
- [Verlassener Unterstand zwischen den Dünen](karawanenroute.jpg)

Zwischen Unterstand und Signalturm lässt sich die [verschüttete Vorratskammer](caravan_cache/README.md) mit Türrest, Krügen und Bodensiegel ausgraben. Sie liegt als separates Modellpaket vor.

Hinter dem Signalturm führen eine [Rastbank und zweifarbige Wegmarken](oasis_approach/README.md) zum Oasentor und zum [Karawanenwrack](caravan_wreck/README.md). Beide Modellpakete sind auf den Geländeübergang von Dünenmeer V3 zu Oase V1 abgestimmt.

## V3 im bestehenden Place aufbauen

1. In **Every Last Grain** (Place-ID `135831532782380`) mit vorhandenem `Workspace.DuneBaronWorld.ArtV2` den Inhalt von `BuildDunes.editor.luau` in der Studio-Befehlsleiste im Bearbeitungsmodus ausführen.
2. Auf `BuildStatus = Ready` im Ordner `ServerStorage.DuneBaron_PreDuneTerrainV3` warten. Der fertige Stand hat `TilesWritten = 324`.
3. `BuildWaystations.editor.luau` ebenfalls in der Studio-Befehlsleiste ausführen. Das Werkzeug setzt die Wegmarken, Bauwerke und Felsen auf das fertige Gelände.

`ServerStorage.DuneBaron_PreDuneTerrainV3` enthält die ursprünglichen Terrain-Voxel des Kernbereichs, die vorige Atmosphäre, die vorherige Sandfarbe und die alten Felswände für eine Rücksicherung. Die beiden Werkzeuge laufen ausschließlich beim Bearbeiten in Studio.

## Geprüft

- Sand an 529 Stichproben über die Karte und begehbare Wege vom Start zum Karawanentor sowie vom Tor über den Unterstand bis in die äußeren Dünen.
- Im Desktop-Spieltest den Unterstand und den Signalturm zu Fuß erreicht und das verschüttete Vermessungssiegel mit der vorhandenen Grabfunktion freigelegt.
