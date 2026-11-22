# Umgebungsgeräusche der fünf Zonen

[Hörvergleich](zonen_hoervergleich.wav) · [Roblox-Importpaket](DuneBaron_Zone_Ambience.zip)

| Zone | Klang | Schleife | Start der Hörprobe |
| --- | --- | ---: | ---: |
| Dünenmeer | Breiter Wind und einzelne Sandböen | 20 s | 0,10 s |
| Oase | Leises Wasser, Tropfen und helleres Rascheln | 22 s | 4,75 s |
| Canyon | Tiefer, zwischen Felswänden widerhallender Wind | 21 s | 9,40 s |
| Salzsee | Offener Wind mit vereinzeltem Kristallknistern | 24 s | 14,05 s |
| Ruinenstadt | Gedämpfter Wind mit trockenen Steingeräuschen | 23 s | 18,70 s |

Die [Zuordnung](cue_sheet.json) verwendet die IDs aus `src/shared/Data/Zones.luau`. Nach dem Audio-Import kann Claude beim Zonenwechsel lokal zwischen den beiden Schleifen überblenden. Die WAVs sind Mono-PCM mit 48 kHz und 16 Bit. Die Übergänge aller fünf Schleifen wurden lokal gegen den übrigen Signalverlauf geprüft. [Roblox Audio-Import](https://create.roblox.com/docs/audio/assets)

[build_discovery_audio.py](../build_discovery_audio.py) erzeugt die Schleifen und den Hörvergleich mit NumPy.
