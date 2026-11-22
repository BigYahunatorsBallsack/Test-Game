# Handgraben für R15

[Animationspaket](DuneBaron_HandScoop.rbxm) · [Bewegungsvorschau](handgraben.gif)

Der Avatar geht in die Hocke, zieht die rechte Hand durch den Sand, hebt sie an und kippt die Hand am Körper aus. Die Arbeitsbewegung dauert **1,54 Sekunden**. Beide Füße behalten ihren Standpunkt. Die Bewegung passt zum Standard-R15-Rig und lässt sich als Schleife abspielen.

| Marker | Zeit | Moment |
| --- | ---: | --- |
| `HandSandTouch` | 0,45 s | Die rechte Hand setzt im Sand an. |
| `HandLoaded` | 0,80 s | Die Hand hebt den Sand an. |
| `HandDeposit` | 1,16 s | Das Handgelenk kippt zum Einfüllen. |

Der Export enthält eine editierbare `KeyframeSequence` mit 40 Posen. Anfangs- und Endpose stimmen im wieder eingelesenen Paket überein. Im geometrischen Test zog sich die Hand nach dem Sandkontakt 0,47 Studs zum Körper zurück. Die größte Abweichung vom berechneten Handziel betrug 0,01 Studs. Die GIF-Vorschau zeigt die exportierten Gelenkstellungen an einem vereinfachten Blockavatar. Der Studio-Spieltest steht aus. [Roblox Pose](https://create.roblox.com/docs/reference/engine/classes/Pose)

Für Claude liegen die [Geräusche für die drei Marker](../../audio/starter/README.md) bereit. [BuildEquipment.editor.luau](../equipment_animation/BuildEquipment.editor.luau) exportiert den Handclip mit dem Lune-Argument `hand-scoop`.
