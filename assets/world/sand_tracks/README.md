# Spuren im Sand

[Vergleich aller fünf Böden](sandspuren_vergleich.jpg) · [Roblox-Effektpaket](DuneBaron_Sand_Tracks.rbxm) · [Hörprobe](../../audio/sand_steps/sandschritte_hoerprobe.wav) · [Audio-Importpaket](../../audio/sand_steps/DuneBaron_SandSteps_SFX.zip)

| Zone | Sandsorte | Abdruck sichtbar | Klang |
| --- | --- | ---: | --- |
| Dünenmeer | `yellow` | 7,0 s | Trockenes Rascheln |
| Oase | `red` | 8,6 s | Satter Auftritt |
| Canyon | `white` | 6,7 s | Feines Schaben |
| Salzsee | `crystal` | 6,1 s | Kurzes Knirschen |
| Ruinenstadt | `black` | 7,2 s | Dumpfer Auftritt |

Die Sohlenabdrücke folgen der Bodenneigung. Staubfarbe, sichtbare Körner und die Dauer bis zum Verblassen hängen vom Sand ab. Für jede Sorte gibt es drei kurze WAV-Varianten. Die [Audio-Zuordnung](../../audio/sand_steps/cue_sheet.json) enthält ihre IDs und Positionen in der Hörprobe.

## Einbau

Das RBXM dem Client bereitstellen. `Stamp` erhält die Sandsorten-ID, einen Kontakt-CFrame am Fuß und die Fußseite. Die lokale Y-Achse des CFrames ist die Bodennormale und −Z zeigt in Laufrichtung entlang der Oberfläche. Den Aufruf an einen bestätigten Bodenkontakt binden und dazu eine der drei passenden WAV-Varianten abspielen. Die visuellen Effekte verwenden native Flächen und Roblox-Standardpartikel. [Roblox SurfaceGui](https://create.roblox.com/docs/reference/engine/classes/SurfaceGui) · [Roblox ParticleEmitter](https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter#Emit)

```luau
local tracks = require(pack.SandTracks).Mount()
tracks.Stamp(sandTypeId, footContactCFrame, isLeft)
-- Beim Abbau der Ansicht
tracks.Destroy()
```

Der Client verwendet bis zu 18 Abdruckplätze. Ausrichtung auf Gefälle, Verblassen, Wiederverwendung und Aufräumen wurden lokal am erneut eingelesenen Modellpaket geprüft. Die Hörprobe ist aus den 15 exportierten Mono-WAVs zusammengesetzt. Die Vergleichsgrafik verwendet die exportierte Sohlengeometrie auf gerenderten Bodenproben. Der Studio-Spieltest steht aus.

[Effektpaket neu erzeugen](BuildSandTracks.luau) · [Schrittgeräusche neu erzeugen](../../audio/build_sand_steps_audio.py)
