# Schaufel tragen und zum Graben ansetzen

[Animierte Vorschau](schaufel_tragen.gif) · [Roblox-Animationspaket](DuneBaron_Shovel_Carry.rbxm)

Der Avatar trägt die Schaufel einhändig neben dem Körper, mit dem Blatt schräg nach hinten. Beim Ansetzen schwenkt das Blatt seitlich nach vorne und die zweite Hand greift an den Stiel.

| Clip | Dauer | Verwendung |
| --- | ---: | --- |
| `ShovelCarryIdle` | 2,56 s | Oberkörperschleife im Stand |
| `ShovelCarryWalk` | 0,88 s | Oberkörperschleife beim Laufen |
| `ShovelCarryToWork` | 0,52 s | Einmaliger Wechsel in den Zweihandgriff |
| `ShovelWorkLoop` | 1,82 s | Arbeitsfassung mit angepasstem Griff am Anfang und Ende |
| `ShovelWorkToCarry` | 0,46 s | Einmaliger Wechsel zurück zur Tragehaltung |

Die beiden Trageschleifen lassen Armhaltung und Oberkörper über der Beinanimation laufen. Für das vorhandene Modell `DuneBaronAssetLibrary.Core.shovel` liegen `RightHandToShovelPivot` und `ShovelScale` im Paket. Der Übergang beginnt und endet in der passenden Clip-Pose. Beim Rückweg am Ende eines Arbeitsumlaufs in `ShovelWorkToCarry` wechseln. [Roblox AnimationPriority](https://create.roblox.com/docs/reference/engine/enums/AnimationPriority)

Die mitgelieferte Arbeitsfassung zieht beide Hände zum Clipanschluss gemeinsam etwas vor die Brust. `SpadeCut`, `SpadeLoaded` und `SpadeDump` liegen weiterhin bei 0,48, 0,89 und 1,31 Sekunden. Sie passen zum [Sandpaket](../starter_sand_fx/README.md) und zu den [Schaufelgeräuschen](../../audio/starter/README.md).

Nach dem Wiedereinlesen wurden alle Anschlüsse, Schleifen und Marker geprüft. Im geometrischen Test an der Standard-R15-Pose blieb das Schaufelblatt beim Tragen und Schwenken mindestens rund 0,48 Studs über dem Boden. Die Vorschau zeigt nachgestellte Blockgeometrie und Demo-Beinschritte unter dem Oberkörperclip. Passform und Übergänge im Studio-Animator stehen zur Spielprobe aus.

Der [Equipment-Builder](../equipment_animation/BuildEquipment.editor.luau) erzeugt das Paket mit dem Argument `shovel-carry`.
