# Sounds für den Spielstart

[Hörprobe](start_hoerprobe.wav) · [Roblox-Importpaket](DuneBaron_Starter_SFX.zip)

Die Hand streicht leise durch den Sand. Bei der Schaufel kommt der kurze Stahlkontakt dazu. Beide haben eigene Geräusche für Ansetzen, Anheben und Auskippen. Ein heller Doppelton meldet den vollen Tank. Der bestätigte Verkauf bekommt ein kurzes Münzklirren mit aufsteigenden Tönen.

Sechs Einzelgeräusche liegen an den tatsächlichen Markern von `HandScoopLoop` und `ShovelWorkLoop`. Die zwei übrigen WAVs gehören zu den vorhandenen Spielmeldungen `tankFull` und `sold`. Die [Zuordnung](cue_sheet.json) enthält alle Dateien und Zeiten. [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

Die acht eigenständig erzeugten Mono-WAVs verwenden 48 kHz und 16 Bit. Nach dem Audio-Import kann Claude die vergebenen IDs an die Marker und Spielmeldungen binden. Beim Verkauf kann zugleich die [Münzanimation](../../ui/sale_feedback/README.md) gezeigt werden. [Roblox-Audioimport](https://create.roblox.com/docs/audio/assets)

[build_starter_audio.py](../build_starter_audio.py) erstellt alle WAVs und die Hörprobe.
