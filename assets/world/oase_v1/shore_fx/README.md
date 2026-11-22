# Oase am Wasser

[Animierte Vorschau](oase_wasser_vorschau.gif) · [Roblox-Effektpaket](DuneBaron_Oasis_Shore_FX.rbxm) · [Quellplätschern](../../../audio/oasis_spring/quelle_plaetschern.wav)

An der Quellterrasse fällt ein schmaler Wasserstrahl aus einer türkisen Fassung ins vorhandene Steinbecken. Kleine Spritzer und ein Wasserring machen den Auftreffpunkt sichtbar. Am Fischersteg ziehen zwei Gruppen versetzter Ringe über die Wasserfläche. Dort ermitteln Terrain-Strahlen die Wasserhöhe. Der Wasserlauf und die Ringe blenden ab 72 Studs Kameradistanz aus.

## Einbau

Den Ordner `DuneBaronOasisShoreFX` ins Projekt importieren und dem Client bereitstellen. Sobald Quellterrasse und Stegufer in `Workspace.DuneBaronWorld.OasisArtV1` geladen sind, kann die Darstellung gebunden werden. Beim Verlassen der Oase die zurückgegebene Funktion aufrufen. Nach einem erneuten Laden kann dieselbe Szene wieder gebunden werden. [Roblox Beam](https://create.roblox.com/docs/reference/engine/classes/Beam) · [Roblox SurfaceGui](https://create.roblox.com/docs/reference/engine/classes/SurfaceGui)

```luau
local stopShoreFX = require(pack.ShoreMotion).Mount(oasisArt, springSoundId)
-- Beim Verlassen der Oase
stopShoreFX()
```

Die optionale `springSoundId` ist die Roblox-Asset-ID des [12-Sekunden-Loops](../../../audio/oasis_spring/quelle_plaetschern.wav). Sie wird am Auftreffpunkt abgespielt und klingt zwischen 4 und 26 Studs ab. Die bestehende Umgebungsgeräusch-Schleife der Oase kann parallel laufen. [Räumlicher Roblox-Sound](https://create.roblox.com/docs/sound/objects)

## Prüfung

Das Modellpaket wurde erneut eingelesen. Lokal geprüft wurden der Ansatz des Wasserlaufs, beide Wasserpositionen im Geländeplan, das Ausblenden auf Distanz, das erneute Binden und das Aufräumen beim Entladen der Terrasse. Die WAV-Datei ist Mono-PCM mit 48 kHz und 16 Bit. Die Vorschau kombiniert ein Detailrendering der Quelle mit einer vorhandenen Studio-Aufnahme des Stegs. Der gemeinsame Spieltest in Studio steht aus.

[Paketerzeugung mit Lune](BuildOasisShoreMotion.luau) · [Audioerzeugung](../../../audio/build_oasis_spring_audio.py)
