# Altes Schöpfrad an der Oase

[Roblox-Modell](DuneBaron_OasisWaterwheel.rbxm) · [Vorschau mit Lageplan](schoepfrad_vorschau.jpg) · [Eine vollständige Umdrehung](schoepfrad_loop.gif)

Bei **X 388,8 / Z 668,4** steht neben der Quellterrasse ein etwa zehn Studs großes Holzrad. Zwölf offene Tongefäße sitzen zwischen den Holzringen. Sie tauchen auf der Seeseite ein und drehen sich oben zur seitlichen Auffangrinne. Die türkis geflieste Zedernholzrinne führt zu einem kleinen Steinbecken. Zwei gemauerte Pfeiler tragen die Achse, an deren anderer Seite die Handkurbel sitzt.

## Einbau und Clip

Nach Gelände und Bauwerken der [Oase](../README.md) den Inhalt von [BuildOasisWaterwheel.editor.luau](BuildOasisWaterwheel.editor.luau) im Studio-Bearbeitungsmodus von **Every Last Grain** ausführen. Das Werkzeug misst Seegrund, Wasseroberfläche und Ufer. Es setzt das Modell unter `Workspace.DuneBaronWorld.OasisArtV1.Structures.OldOasisWaterwheelV1` ein. Die RBXM-Datei enthält dieselbe Geometrie auf den lokal berechneten Kartenkoordinaten.

`AnimationClips.WaterwheelTurnLoop` ist ein editierbarer 9,6-Sekunden-Loop für eine vollständige Umdrehung. `AnimationController`, `Animator` und Achsgelenk stecken im Modell. Die Aktivierung des Clips im Spiel und ein späterer Wasserfluss gehören zur Integration.

## Lokal geprüft

- Alle zwölf Tongefäße und beide Holzringe gehören zum selben Rotor. Anfang und Ende des Clips ergeben dieselbe Pose.
- Im Geländemodell reicht die tiefste Stelle des Rads 0,48 Studs unter die Wasserlinie. Die rotierende Geometrie hält mindestens 3,1 Studs Abstand zum Seegrund und rund 0,14 Studs zur Auffangrinne.
- Die neue Rinne und ihr Becken stehen mindestens 5,5 Studs von den kollidierenden Steinbauteilen der Quellterrasse entfernt.

Einbau, Wasserhöhenprüfung und Wiedergabe im Studio-Animator stehen aus.
