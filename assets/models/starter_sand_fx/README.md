# Sandeffekte für Hand und Schaufel

[Animierte Vorschau](hand_schaufel_sand.gif) · [Roblox-Effektpaket](DuneBaron_Starter_Sand_FX.rbxm) · [Vorhandene Geräusche zu den Markern](../../audio/starter/README.md)

Beim Sandkontakt lösen sich Staub und einzelne Körner direkt am Boden. Beim Anheben bleibt eine kleine Ladung an der Hand oder auf dem Schaufelblatt. Beim Kippen verschwindet die Ladung und fällt in drei kurzen Portionen nach unten. Die Schaufel hebt sichtbar mehr Sand als die Hand.

| Clip | Bodenkontakt | Ladung sichtbar | Auskippen |
| --- | --- | --- | --- |
| `HandScoopLoop` | `HandSandTouch` bei 0,45 s | `HandLoaded` bei 0,80 s | `HandDeposit` bei 1,16 s |
| `ShovelWorkLoop` | `SpadeCut` bei 0,48 s | `SpadeLoaded` bei 0,89 s | `SpadeDump` bei 1,31 s |

## Einbau

Beide vorhandenen R15-Clips liegen im RBXM. Der Schaufelordner enthält auch die gespeicherten Werte für Maßstab und rechten Griff. Vor dem Abspielen `Bind` auf dem Client mit einem Attachment auf der Handfläche oder in der Schaufelmulde aufrufen. Die Y-Achse des Attachments zeigt aus der Fläche heraus. Der Kurzstrahl fällt nach unten und kann über ein optionales Ziel-Attachment auf die Tanköffnung gerichtet werden. [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

```luau
local stopFX = require(pack.StarterSandFX).Bind("Shovel", workTrack, bladeContact, sandColor, tankMouth)
-- Beim Ablegen des Werkzeugs
stopFX()
```

Für Handgraben `"Hand"` und das Kontakt-Attachment an der rechten Hand verwenden. Das Stopp-Ereignis verbirgt die Ladung und beendet ausstehende Sandportionen. Die bestehenden Geräusche verwenden die gleichen Marker aus [cue_sheet.json](../../audio/starter/cue_sheet.json).

Die 40 Hand- und 50 Schaufel-Keyframes wurden nach dem Export mit den Originalclips verglichen. Markerfolge, Bodenposition, Ladung, Zielrichtung und Abbruch wurden lokal geprüft. Die verlangsamte Vorschau zeigt die exportierten Gelenkstellungen an Blockavataren und verwendet ein vereinfachtes Schaufelmodell. Die Passform am Studio-Modell und der Spieltest stehen aus.

[Effektpaket neu erzeugen](BuildStarterSandFX.luau)
