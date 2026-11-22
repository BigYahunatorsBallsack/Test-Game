# Dune Baron Equipment

Das [Roblox-Modellpaket](DuneBaron_Equipment_Animations.rbxm) enthält die vier Maschinen und sieben editierbare Animationsclips. In Studio liegt derselbe Stand unter `ServerStorage.DuneBaronEquipmentAnimations`.

Studio-Aufnahmen. [Bagger-Arbeitszyklus](bagger_arbeitszyklus.gif) · [Equipment im Größenvergleich](equipment_uebersicht.jpg) · [Harvester-Laufwerk](harvester_laufrollen.jpg)

Im Maschinenhof stehen die vier überarbeiteten Modelle als statische Schaustücke. Die früheren Modelle liegen unter `ServerStorage.DuneBaron_PreEquipmentV3Yard`.

| Equipment | Arbeit | Fahrt |
| --- | --- | --- |
| Schaufel | 1,82 s mit Zweihandgriff, Ausholen, Einstechen, Heben und Auskippen | |
| Eimerkette | 2,96 s. Neun Eimer und beide Kettenräder laufen mit. | |
| Mini-Bagger | 3,24 s. Der Tieflöffel zieht den Sand zur Kabine, rollt sich ein und kippt seitlich aus. Beide Hydrauliken folgen den Gelenken. | Zwei laufende Raupenketten |
| Saugroboter | 1,86 s. Der Scanner schwenkt vor, die Düse senkt sich und streicht knapp über dem Sand. | |
| Dünen-Harvester | 1,58 s. Die Schneidwalzen drehen versetzt und variieren ihr Tempo unter Last. | Zwei laufende Raupenketten |

## Maßstab und Form

- Das Förderband misst rund **4,90 × 6,35 × 9,11 Studs**. Es steht rund ein Drittel höher als in V2. `Discharge` liegt etwa 4,59 Studs über dem Boden.
- Beim Mini-Bagger liegt die Zahnleiste des Tieflöffels auf der Kabinenseite. Beim Sandkontakt zieht sie im Arbeitszyklus rund 0,77 Studs Richtung Maschine, bevor der Löffel anhebt.
- Beim Harvester liegen mindestens 0,21 Studs zwischen benachbarten Laufrollen. Die Leiter sitzt außen mit etwa 0,13 Studs Abstand zu den Radnaben.

## Clips für Claude

- Die vier Modelle enthalten `Animations/WorkLoop`. Bagger und Harvester enthalten zusätzlich `Animations/TravelLoop`. Die Clips können gleichzeitig laufen. Das Attribut `BeltSpeedStudsPerSecond` gibt die passende Referenzgeschwindigkeit für den Fahrtclip an.
- `shovel/ShovelWorkLoop` ist für den standardgroßen R15-Avatar. `RightHandToShovelPivot` und `ShovelScale` gelten für das vorhandene Schaufelmodell `DuneBaronAssetLibrary.Core.shovel`. Der Arbeitsclip bewegt den Avatar an Ort und Stelle.
- Marker für optionale Sandeffekte sind `SpadeCut`, `SpadeLoaded`, `SpadeDump`, `Discharge`, `BucketCut`, `BucketLoaded`, `BucketDump`, `IntakeEngage`, `IntakeSweep`, `IntakeRelease` und `CutterLoad`. Die Maschinen behalten ihre `WorkOrigin`- und vorhandenen `DriverMount`-Attachments.
- Die Clips sind lokale `KeyframeSequence`-Objekte. Für veröffentlichte Spielwiedergabe werden die Animationen unter dem passenden Roblox-Ersteller veröffentlicht und mit dem Equipment- und Fahrtzustand verbunden. Das Paket enthält Art-Assets und keine Laufzeitskripte.

Das Modellpaket wurde nach dem Export wieder eingelesen. Die Clips wurden über den Animator im lokalen Studio-Client abgespielt. [Roblox-Animationseditor](https://create.roblox.com/docs/animation/editor)

Das [Sandeffekt-Paket](../equipment_sand_fx/README.md) enthält die vier Rigs mit Partikeln und sichtbarer Baggerladung.

Der [Handgrab-Clip](../hand_scoop/README.md) ergänzt die Werkzeugstufe vor der Schaufel. Das [Start-Soundpaket](../../audio/starter/README.md) enthält Geräusche für beide Einstiegsanimationen.

Das [Sandpaket für Hand und Schaufel](../starter_sand_fx/README.md) ergänzt Bodenkontakt, sichtbare Ladung und Auskippen an den vorhandenen R15-Markern.

Das [Tragepaket der Schaufel](../shovel_carry/README.md) enthält Oberkörperclips für Stand und Lauf sowie Übergänge zwischen Tragen und Arbeiten.

Das [Fahrerkabinen-Paket](../driver_cabs/README.md) enthält den Mini-Bagger und den Dünen-Harvester mit beweglichen Bedienelementen und passenden Sitz- und Bedienclips für R15.
