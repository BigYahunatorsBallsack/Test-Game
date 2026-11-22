# Fundklänge

Sechs unterschiedlich lange Fundklänge für Gewöhnlich, Ungewöhnlich, Selten, Episch, Legendär und Mythisch. Häufige Funde bekommen eine kurze Tonantwort. Seltenere Funde haben einen längeren Tonverlauf mit mehr Obertönen. Der mythische Klang beginnt mit einem tieferen Ton.

[Hörprobe aller sechs Stufen](fundklaenge_hoerprobe.wav) · [Roblox-Importpaket](DuneBaron_Find_SFX.zip)

Die [Zuordnung](cue_sheet.json) nennt die WAV für jede Seltenheits-ID. Nach dem Audio-Import spielt Claude den Ton gleichzeitig mit der [Fundanzeige](../../ui/find_reveal/README.md). Die Einzeldateien sind Mono-PCM mit 48 kHz und 16 Bit. [Roblox Audio-Import](https://create.roblox.com/docs/audio/assets)

[build_discovery_audio.py](../build_discovery_audio.py) erstellt alle Töne mit NumPy. Hörprobe, Einzeldateien und ZIP wurden lokal geprüft.
