# Sandsturm-Übergang

[Roblox-Effektpaket](DuneBaron_Sandstorm_FX.rbxm) · [Ablaufvorschau](../../ui/sandstorm/sandsturm_ablauf.gif) · [Hörprobe](../../audio/sandstorm/sandsturm_hoerprobe.wav)

Der Übergang dauert **2,40 Sekunden**. Eine seitliche Böe zieht mit Staub und einzelnen Körnern durch das Bild. Die Welt wird kurz sandfarben. Ab 0,91 Sekunden flaut der Sturm ab und gibt den Blick wieder frei. Das HUD bleibt über dem Schleier. Bei reduzierter Bewegung verwendet der Übergang einen helleren, ruhigen Schleier.

## Übergabe an Claude

Das Paket in Studio importieren und dem Client bereitstellen. `Play` nach einer bestätigten Sandsturm-Meldung aufrufen und gleichzeitig den [Windstoß](../../audio/sandstorm/README.md) starten. Der Abschluss-Callback ist für [Ergebnisanzeige und Windkristallton](../../ui/sandstorm/README.md) vorgesehen. Beim Überspringen oder Entfernen der Ansicht stehen `Stop()` und `Destroy()` bereit.

```luau
local storm = require(pack.Transition).Mount(playerGui)
storm.Play(function()
    resultView.Show(confirmedResult)
end)
```

Kamerafolge, Zeitpunkte, Abbruch, reduzierte Bewegung und das Entfernen der temporären Effekte wurden lokal am erneut eingelesenen Paket geprüft. Die Ablaufvorschau ist eine Animation auf Basis einer vorhandenen Studio-Aufnahme. Der gemeinsame Studio-Spieltest steht aus. [Roblox ColorCorrectionEffect](https://create.roblox.com/docs/reference/engine/classes/ColorCorrectionEffect) · [Roblox ParticleEmitter](https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter)

[BuildSandstormEffects.editor.luau](BuildSandstormEffects.editor.luau) baut das Paket in Studio Edit oder mit Lune.
