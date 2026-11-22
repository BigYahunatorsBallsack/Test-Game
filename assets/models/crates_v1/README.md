# Holz-, Eisen-, Gold- und Event-Kiste

Das [Roblox-Modellpaket](DuneBaron_Crates.rbxm) enthält vier Rigs mit Scharnierdeckel, beweglichem Riegel, ausgearbeitetem Innenraum und Lichtstoß beim Öffnen. Die Modelle liegen im Studio-Entwurf **Every Last Grain** unter `ServerStorage.DuneBaronCrateRigs`.

[Geschlossene Kisten](kisten_uebersicht.jpg) · [Deckelbewegung](kisten_oeffnen.gif) · [Lichtstoß in Studio](kisten_glow.jpg)

| Kiste | `CrateId` | Breite × Höhe × Tiefe im geschlossenen Zustand | `Open` | `Close` |
| --- | --- | --- | ---: | ---: |
| Holz | `wood` | 2,74 × 2,11 × 2,87 Studs | 0,81 s | 0,57 s |
| Eisen | `iron` | 3,09 × 2,13 × 3,11 Studs | 1,16 s | 0,84 s |
| Gold | `gold` | 3,29 × 2,41 × 3,20 Studs | 0,98 s | 0,68 s |
| Event | `event` | 3,41 × 2,57 × 3,34 Studs | 1,28 s | 0,78 s |

Die Kisten werden von Holz bis Event größer. Dunkle Beschläge, Nieten, goldene Rauten und eine türkisfarbene Fuge greifen die Merkmale der jeweiligen UI-Icons auf.

Beim Öffnen wirft Holz einen bernsteinfarbenen Schimmer und Eisen sprüht hellblaue Funken. Gold bekommt einen größeren goldenen Sternblitz. Bei der Event-Kiste kommen zum türkisen Licht violette Partikel. Die Farben und die Stärke hängen am jeweiligen Rig.

## Übergabe an Claude

Jedes Rig hat einen `AnimationController` mit `Animator`. `Root` sitzt auf der Standfläche und die Vorderseite zeigt nach `-Z`. Die Clips laufen einmal pro Aufruf. `Open` enthält die Marker `Unlatch` und `Reveal`. `Close` enthält `Latch`.

Der Effekt verwendet das Attachment `Root.RevealOrigin`. Auf dem Client einmal pro geladenem `Open`-Track binden und anschließend wie gewohnt abspielen. Die Bindung gilt auch für Wiederholungen desselben Tracks. Beim Entladen den Track zerstören oder die Verbindung trennen. Kauf, Inventar und Belohnungen bleiben bei Claude. [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

Das [Kisten-Soundpaket](../../audio/crates/README.md) enthält separate WAVs für `Unlatch`, `Reveal` und `Latch` sowie einen Hörvergleich für alle vier Kisten.

```luau
local revealConnection = require(crate.RevealEffects).Bind(crate, openTrack)
openTrack:Play()
```

## Studio-Prüfung

Alle acht Clips liefen im Studio-Animator. Die Marker feuerten in der vorgesehenen Reihenfolge. Der Geometrietest fand nach der Korrektur der Riegelhalterungen keine unbeabsichtigten Überschneidungen an den Öffnungs-Keyframes. Im erneut eingelesenen RBXM schließen die Endposen von `Open` und `Close` an die jeweilige Anfangspose des Gegenclips an.

Jede Kiste wurde zweimal geöffnet und geschlossen. Das Licht startete jeweils am `Reveal`-Marker und klang vollständig ab. Die Partikeltexturen wurden im Playtest geladen. Für die Aufnahme wurden die vier Lichtstöße auf denselben Moment nach `Reveal` synchronisiert.

[BuildCrates.editor.luau](BuildCrates.editor.luau) erzeugt die Modelle aus nativen Roblox-Bauteilen in Studio oder mit Lune. Der Studio-Test verwendete temporäre Clip-IDs. [Roblox AnimationClipProvider](https://create.roblox.com/docs/reference/engine/classes/AnimationClipProvider)
