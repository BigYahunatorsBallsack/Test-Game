# Kisten-Sounds

Vier eigene Klangprofile mit je drei einzelnen WAV-Dateien. Im [Hörvergleich](kisten_soundvergleich.wav) spielt jede Kiste beim Öffnen und Schließen ihre Töne im Abstand der vorhandenen Animationsmarker.

| Kiste | Klang | Start im Hörvergleich |
| --- | --- | ---: |
| Holz | Trockener Riegel, dumpfer Deckel und warmer kurzer Schimmer | 0,10 s |
| Eisen | Tiefer Anschlag, kurzes metallisches Schaben und heller Nachklang | 2,40 s |
| Gold | Feiner Messingriegel und mehrere steigende Münztöne am Lichtblitz | 5,44 s |
| Event | Steinernes Klacken und ein luftiger, gläserner Aufstieg mit längerem Ausklang | 8,07 s |

## Anbindung

Die [Zuordnung](cue_sheet.json) verknüpft `CrateId`, Clip und Marker mit dem jeweiligen WAV. `Open.Unlatch` löst den Riegel aus. `Open.Reveal` spielt den Klang gleichzeitig mit dem vorbereiteten Lichtstoß. `Close.Latch` setzt den Schließton. Nach dem Import verwendet Claude die vergebenen Audio-IDs. Die gemessenen Markerzeiten dienen dem Hörvergleich. Im Spiel soll der jeweilige Marker den Ton auslösen, damit er auch bei anderer Abspielgeschwindigkeit passt.

Das [Importpaket](DuneBaron_Crate_SFX.zip) enthält die zwölf Einzeldateien und die Zuordnung. Die Dateien sind Mono-PCM mit 48 kHz und 16 Bit. [Roblox-Audioimport](https://create.roblox.com/docs/audio/assets) · [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

[build_crate_audio.py](build_crate_audio.py) erzeugt die WAVs mit NumPy. Der Hörvergleich setzt die finalen Einzeldateien an die tatsächlichen Markerpositionen. In Studio lösten alle zwölf Marker beim Abspielen mit normalem Tempo und mit 0,68-fachem Tempo aus. Die Audiodateien sind lokal zum Import vorbereitet.
