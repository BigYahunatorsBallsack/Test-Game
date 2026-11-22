# Koloss-Sand und Abschlusslicht

[Roblox-Effektpaket](DuneBaron_Colossus_FX.rbxm) · [Fortschritt und Abschluss in der Vorschau](../../ui/colossus/README.md)

Beim Freilegen eines Abschnitts wirbeln Staub und gröbere Körner an acht Punkten seiner Oberfläche auf. Die Quellen werden an den aktuellen Sandboden angepasst. Beim Abschluss sendet der türkise Brusteinsatz einen kurzen Lichtimpuls und kleine Funken aus. Das Licht klingt in gut einer Sekunde ab.

## Übergabe an Claude

Das Paket in Studio importieren und dem Client bereitstellen. `Section` nimmt den vorhandenen `Center` der Grabungsfläche `Nordhand` oder `Beine` entgegen. `Complete` erhält den Einsatz `Dark teal stone inlay` aus `Koloss.Brust und Rumpf`. Die Effekte können nach den bestätigten Eventmeldungen zusammen mit den [Klängen](../../audio/colossus/README.md) ausgelöst werden. Die Instanz am Eventende mit `Destroy()` entfernen.

```luau
local effects = require(pack.Effects).Mount(workspace)
effects.Section(sectionCenter)
effects.Complete(reliefPart)
```

[BuildColossusEffects.editor.luau](BuildColossusEffects.editor.luau) baut das Paket in Studio Edit oder mit Lune. Der Export wurde erneut eingelesen. In der lokalen Prüfung saßen alle acht Quellen auf geneigtem Boden. Position und Abklingen des Abschlusslichts wurden ebenfalls geprüft. Der gemeinsame Studio-Spieltest mit der Koloss-Szene steht aus. [Roblox ParticleEmitter](https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter#Emit) · [Roblox PointLight](https://create.roblox.com/docs/reference/engine/classes/PointLight)
