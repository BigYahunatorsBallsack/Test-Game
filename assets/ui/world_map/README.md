# Weltkarte

Die Karte verfolgt die Karawanenroute vom Dünenmeer über Oase, Canyon und Salzsee bis in die Ruinenstadt. Die Darstellung basiert auf den fünf vorhandenen Geländebauplänen. Die Übergänge sind für die Kartenansicht geglättet. Die markierten Orte sind Karawanentor, Fischersteg, Schichtentor, Solestation und Sonnenplatz.

- [Desktop-Vorschau](weltkarte_desktop.jpg) mit Standortpfeil, offenen Wegen und drei gesperrten Zonen.
- [Handy-Vorschau](weltkarte_mobil.jpg) mit Symbolen auf der Karte und lesbaren Namen samt Freischaltbedingungen in antippbaren Zeilen.
- [Geländerelief](weltkarte_relief.png) mit 1024 × 576 Pixeln und [Symbolatlas](weltkarte_symbole.png) mit 1024 × 512 Pixeln. Beide PNGs sind ohne Beschriftung.
- [Kartenpunkte](kartenpunkte.json) mit Zonen-IDs, Freischaltbedingungen, Ausschnitten des Symbolatlas, Weltkoordinaten der Landmarken und Wegverläufen.

## Einbau

Das Relief deckt X von −700 bis 2500 und Z von −400 bis 1400 ab. Auf der Karte wächst X nach rechts und Z nach unten. Die normalisierte Position eines Markers ist `u = (x + 700) / 3200` und `v = (z + 400) / 1800`. Bei einem Bild mit Seitenrändern beziehen sich die Koordinaten auf die sichtbare Relieffläche. Je Zone ist der Anker schon als `anchorUV` hinterlegt. `routes[].worldXZ` enthält die Pfade zum Zeichnen der Wege. [Roblox ImageLabel](https://create.roblox.com/docs/reference/engine/classes/ImageLabel)

Die Zonenreihenfolge und Freischaltbedingungen stammen aus [Zones.luau](../../../src/shared/Data/Zones.luau). Die Laufzeitanzeige liest den bestätigten Freischaltstatus und verwendet für den Standortpfeil die aktuelle Spielerposition. Die Bildpfade unter `photo` verweisen auf vorhandene Studio-Aufnahmen für die Gestaltung der Detailkarte.

Die Vorschauen sind statische Entwürfe mit Beispielzustand. Atlas, Bildgrößen und Koordinaten wurden lokal geprüft. Roblox-Import und UI-Anbindung stehen aus.
