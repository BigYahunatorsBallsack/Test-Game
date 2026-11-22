# Arbeitsgeräusche für das Equipment

Der [Hörvergleich](maschinen_hoervergleich.wav) spielt jede Maschine zwei Arbeitszyklen lang. Die Einzelgeräusche setzen an den tatsächlichen Animationsmarkern ein.

| Maschine | Schleife | Einzelgeräusche | Start im Hörvergleich |
| --- | ---: | --- | ---: |
| Förderband | 2,96 s | Kettenlauf und Sandportionen am Auswurf | 0,10 s |
| Mini-Bagger | 3,24 s | Dieselmotor und Hydraulik, Zahnkontakt, Anheben und Auskippen | 6,67 s |
| Saugroboter | 1,86 s | Kleiner Elektromotor, Luftstrom an der Düse und Schließgeräusch am Ventil | 13,80 s |
| Harvester | 1,58 s | Tiefes Motorgeräusch und abwechselnde Lastimpulse der beiden Walzen | 18,17 s |

Das [Importpaket](DuneBaron_Equipment_SFX.zip) enthält vier Arbeitsloops und acht Einzelgeräusche als 48-kHz-Mono-PCM-WAVs mit 16 Bit. Die zwölf Dateien sind eigens erzeugt. [Roblox-Audioimport](https://create.roblox.com/docs/audio/assets)

## Übergabe an Claude

Die [Marker-Zuordnung](cue_sheet.json) nennt für jedes Rig den `WorkLoop`, die passende WAV und alle Tonmarker. Nach dem Import den Arbeitsloop am Maschinenmodell während des Arbeitszustands abspielen. Die acht Einzelgeräusche an die Clipmarker binden. Bei geändertem Arbeitstempo folgen Loop und Arbeitsanimation demselben Abspieltempo. Eine kurze Lautstärkeblende beim Anfahren und Abschalten gehört zur Spielanbindung. [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

Die Schleifenlängen entsprechen auf das Sample genau den Arbeitsclips im [Equipment-Paket](../../models/equipment_sand_fx/README.md). Die vier Loopübergänge und der zusammengesetzte Hörvergleich wurden lokal auf Pegelsprünge und Übersteuerung geprüft. [build_equipment_audio.py](build_equipment_audio.py) baut alle WAVs mit NumPy erneut.
