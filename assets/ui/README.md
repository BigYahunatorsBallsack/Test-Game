# Dune Baron UI

Das Roblox-HUD liest weiterhin den vorhandenen Serverzustand. Das Menü zeigt Ausrüstung, Tank-, Verkaufs- und Glücksicons sowie Währungen und Kisten. Die Werkzeugleiste zeigt die aktive Stufe. Die Fundkarte bietet fünf Regionen, 30 Karten pro Region und eine Detailansicht mit Set, Beschreibung und Seltenheit. Menü und Fundkarte lassen sich über die HUD-Schaltflächen öffnen. Auf der Tastatur öffnet oder schließt **M** die zuletzt geöffnete Seite.

[Fundkarte](fundkarte.jpg) · [Menü](menue.jpg) · [Werkzeugleiste](werkzeugleiste.jpg)

Die Oberfläche verwendet Sandgold und Türkis für die Navigation, Terrakotta zum Schließen und unterschiedliche Farben für die sechs Seltenheiten. `src/client/Interface/Theme.luau` bündelt Farbverläufe, Rahmenfarben und Schriftkonturen. Auf schmalen Bildschirmen verwendet die Werkzeugleiste kürzere Beschriftungen. Die vollständigen Werkzeugnamen stehen im Ausrüstungsmenü.

Alle 185 Einzelbilder liegen in sechs transparenten PNG-Atlanten. `src/client/Interface/AtlasIds.luau` enthält ihre Roblox-Bild-IDs. Icons und Rahmen werden im HUD und in der Sammlung separat zusammengesetzt. Karte und Detailansicht verwenden denselben Bildausschnitt und Seltenheitsrahmen in der jeweils passenden Größe.

[Zuordnung aller 150 Fundmodelle und Icons](collection_assets.json). Die Fundkarte zeigt den vorhandenen Asset-Katalog mit Entwurfsnamen, Sets und Seltenheiten. Besitz, Belohnungen und die verbindliche Fundtabelle bleiben bei der Spielintegration. Der Atlas-Build prüft eindeutige Fund-IDs und eindeutige Bild- und Modellpfade. Er lässt sich mit `python assets/ui/build_atlases.py` neu erzeugen.

Im Studio-Spieltest wurden alle sechs Roblox-Bildassets erfolgreich geladen. Auf den fünf geöffneten Fundseiten luden jeweils alle 30 Fundbilder. In der Studio-Bibliothek haben alle 150 Modelle die Attribute `CollectionIcon`, `CollectionIconOffset` und `CollectionIconSize`.

Der [Modellvergleich](../studio/find_visual_review.md) bestätigt alle 150 Zuordnungen und dokumentiert sichtbare Abweichungen zwischen Fundmodell und Icon.

Die [Fundanzeige](find_reveal/README.md) zeigt nach einem Fund Icon, Seltenheit, Name und Zone. Desktop- und Handy-Vorschauen liegen im selben Paket.

Die [Münzanimation](sale_feedback/README.md) zeigt nach einem bestätigten Verkauf den ausgezahlten Betrag und kann die Münzen zum HUD-Zähler fliegen lassen.

Die [Weltkarte](world_map/README.md) verbindet die fünf Zonen entlang der Karawanenroute. Relief, Symbole, Kartenpunkte und Layoutentwürfe für Desktop und Handy liegen im Paket.


## Einbau

Die UI-Komponenten liegen in src/client/Interface. Die Menüs aus den Vorschauen wurden im Studio-Entwurf mit einem HUD-Adapter getestet. Im Git-Stand lädt der vorhandene Bootstrap weiterhin den bisherigen HUD-Controller. Menü, Werkzeugleiste und Fundkarte können zusammen über das Modul View eingebunden werden. Für die Fundanzeige, den Verkaufseffekt und die Eventanzeigen liegen eigene Komponenten in demselben Ordner.
