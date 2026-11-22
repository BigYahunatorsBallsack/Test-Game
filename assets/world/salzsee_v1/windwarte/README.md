# Windwarte am Salzsee

[Roblox-Modell](DuneBaron_Windwatch.rbxm) · [Vorschau mit Lageplan](windwarte_vorschau.jpg) · [Windsack in Bewegung](windsack.gif)

Die Windwarte steht bei **X 1227 / Z 837** auf der Landzunge zwischen den beiden Uferwegen. Fünf Kalksteinstufen führen auf die hölzerne Aussichtsplattform mit bronzener Peilscheibe und Blick über die Sole. Auf dem Mast hängt ein korallrot und cremefarben gestreifter Windsack. Die maßgeblichen Stufen, Böden und Geländer haben Kollision.

## Einbau und Clip

Nach Gelände und Bauwerken des [Salzsees](../README.md) den Inhalt von [BuildWindwatch.editor.luau](BuildWindwatch.editor.luau) im Studio-Bearbeitungsmodus von **Every Last Grain** ausführen. Das Werkzeug misst die vorhandene Voxeloberfläche und setzt das Modell unter `Workspace.DuneBaronWorld.SaltLakeArtV1.SaltLakeWindwatchV1`. Die RBXM-Datei enthält dieselbe Geometrie auf den lokal berechneten Kartenkoordinaten.

`AnimationClips.LakeWindLoop` ist ein editierbarer 3,2-Sekunden-Loop für die fünf Stoffsegmente. Das Modell enthält die Motoren, den `AnimationController` und den `Animator`. Die Aktivierung des Windsacks im Spiel ist eine getrennte Integrationsaufgabe.

## Lokal geprüft

- Die Modellkanten liegen im Geländeplan mindestens 21,3 Studs von der Mitte beider Fahrwege entfernt. Der Mastkopf ist von einem Prüfpunkt am Canyon-Ausgang über der Geländeoberfläche sichtbar.
- Der Einstieg und die fünf Stufen haben in der Höhenprobe jeweils höchstens 0,36 Studs Höhenunterschied.
- Anfangs- und Endpose stimmen im wieder eingelesenen Clip überein. Alle fünf Motoren sind ihren Posen zugeordnet. Die GIF-Vorschau verwendet 24 aus dem Clip berechnete Bilder.

Einbau, Begehung und Wiedergabe im Studio-Animator stehen aus.
