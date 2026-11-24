# Werkstatt-Sounds für Every Last Grain

[Hörvergleich](Werkstatt_Hoervergleich.wav) · [Quellskript](../build_workshop_audio.py)

| Klang | Einsatz | Dauer | Beginn im Hörvergleich |
| --- | --- | ---: | ---: |
| [Knotenauswahl](Werkstatt_Knoten.wav) | Kurzer, heller Klick beim Wechsel auf einen Knoten | 0,105 s | 0,120 s |
| [Upgrade](Werkstatt_Upgrade.wav) | Messingklack mit kurzem Sandscharren beim Lernen eines kleinen Upgrades | 0,306 s | 0,525 s |
| [Fähigkeit](Werkstatt_Faehigkeit.wav) | Aufsteigende Messingtöne und Sandstaub bei einer Fähigkeit oder Meisterschaft | 0,690 s | 1,131 s |
| [Variante](Werkstatt_Variante.wav) | Zwei kurze Rastungen und ein dumpfer Anschlag beim Wechsel der ausgerüsteten Variante | 0,279 s | 2,121 s |

Alle Dateien sind originale Mono-WAVs mit 48 kHz und 16 Bit. Die vier Einzeldateien sind die Importassets. [Roblox-Audioimport](https://create.roblox.com/docs/audio/assets)

Die Werkstatt spielt den Kaufklang nach einem bestätigten Kauf oder einem abgeschlossenen Testkauf. Der Variantenklang läuft beim separaten Ausrüsten. Auswahltöne sind begrenzt und unterbrechen keine laufende Bestätigung.

Die vier Audio-IDs gehören in die `asset`-Felder von [Audio.luau](../../../src/client/Interface/Workshop/Audio.luau). Bis zum Import oder solange Roblox ein Audioasset lädt, spielt die Werkstatt leise Ersatzklänge aus Studio. Die WAV-Dateien lassen sich mit `python -B assets/audio/build_workshop_audio.py` erneut erzeugen.
