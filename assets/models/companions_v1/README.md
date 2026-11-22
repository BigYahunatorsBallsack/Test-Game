# Fennek, Wüstenmaus und Skarabäus

Das [Roblox-Modellpaket](DuneBaron_Companions.rbxm) enthält drei animierbare Begleiter mit Grabtaschen und neun editierbaren Animationsclips. Die Modelle liegen im offenen Studio-Entwurf **Every Last Grain** unter `ServerStorage.DuneBaronCompanionRigs`.

[Größenvergleich mit Avatar](groessenvergleich.jpg) · [Grabbewegungen](grabloops.gif)

| Begleiter | Rig-ID | Breite × Höhe × Länge | Bewegungen |
| --- | --- | --- | --- |
| Fennek | `fennec` | 2,37 × 2,85 × 3,45 Studs | Trab mit diagonalen Pfotenpaaren, wippender Schwanz und bewegliche Ohren |
| Wüstenmaus | `desert_mouse` | 1,67 × 1,77 × 2,33 Studs | Kurze, schnelle Schritte, Schnüffeln und kurze Grabstöße |
| Skarabäus | `scarab` | 1,95 × 1,33 × 1,95 Studs | Sechs Beine in zwei wechselnden Dreiergruppen, bewegliche Fühler und Graben mit den Vorderbeinen |

Der Testavatar war 5,50 Studs hoch. Die Maße der Rigs wurden in ihrer Ruhepose gemessen. Die GIF-Vorschau synchronisiert die drei Grab-Loops für den direkten Vergleich.

## Clips für Claude

| Rig | `IdleLoop` | `TravelLoop` | `DigLoop` | Referenztempo |
| --- | ---: | ---: | ---: | ---: |
| `fennec` | 2,84 s | 0,72 s | 1,34 s | 1,69 Studs/s |
| `desert_mouse` | 2,18 s | 0,55 s | 1,12 s | 1,30 Studs/s |
| `scarab` | 2,46 s | 0,62 s | 1,02 s | 0,86 Studs/s |

Die Bewegungen laufen am Standort des Modells. Jedes Rig hat seine eigene `AnimationController`-Instanz mit `Animator` und eine gemeinsame Vorwärtsrichtung `-Z`. Der `TravelLoop` enthält zwei `Step`-Marker pro Umlauf und trägt `ReferenceSpeedStudsPerSecond`. Der `DigLoop` enthält zwei `DigContact`-Marker mit den Werten `Left` und `Right`. Auswahl, Folgen, Grabverhalten und Sandeffekte bleiben bei Claude.

## Studio-Prüfung

- Alle neun lokalen Clips liefen mindestens einmal vollständig im Animator. Die Schritt- und Grabmarker feuerten. Die tiefste gemessene Abweichung unter der Standfläche lag bei 0,008 Studs.
- Das lokale RBXM enthält alle drei Rigs und neun Sequenzen. Im wieder eingelesenen Paket stimmen Anfangs- und Endpose jedes Loops überein.
- [BuildCompanions.editor.luau](BuildCompanions.editor.luau) erzeugt das Paket aus nativen Roblox-Formen in Studio oder mit Lune. Für den Studio-Test wurden temporäre Clip-IDs verwendet. [Roblox AnimationClipProvider](https://create.roblox.com/docs/reference/engine/classes/AnimationClipProvider)
