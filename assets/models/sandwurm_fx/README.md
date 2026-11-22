# Sandwurm-Effekte

[Roblox-Paket](DuneBaron_Sandworm_SandFX.rbxm) · [Warnung im Spieltest](sandwarnung.jpg) · [Sandstoß im Spieltest](sandstoss.jpg)

Der Sandwurm kündigt sich mit zwei niedrigen Staubwellen an. Beim Ausbruch spritzt der Sand nach außen und die gröberen Körner fallen in Bögen zurück. Beim Biss lösen sich einzelne Sandkörner vom Maulrand. Beim Abtauchen zieht die Wolke von den Rändern zur Mitte und setzt sich dort ab.

| Clip | Marker | Zeit im Clip | Bezugspunkt |
| --- | --- | ---: | --- |
| `Sandworm_Emerge` | `SandWarning` | 0,05 s | Zwei versetzte Ringe auf der Sandoberfläche |
| `Sandworm_Emerge` | `Breach` | 0,70 s | Sandfächer am Austrittspunkt |
| `Sandworm_Bite` | `Bite` | 0,35 s | Beiderseits des animierten `Head`-Knochens |
| `Sandworm_Burrow` | `Burrow` | 0,23 s | Nach innen gerichtete Partikel am Boden |

## Übergabe an Claude

Im Studio-Entwurf **Every Last Grain** liegt das Paket unter `ServerStorage.DuneBaronSandwormSandFX`. Für die clientseitige Einbindung braucht der Client das Paket, beispielsweise in `ReplicatedStorage`. Das Modul erwartet das platzierte [Sandwurm-Rig](../sandwurm/README.md) mit Bodenausrichtung am Pivot und drei bereits geladenen [Animationsclips](../animation_clips/README.md).

```luau
local unbind = require(pack.SandEffects).Bind(worm, {
    Emerge = emergeTrack,
    Bite = biteTrack,
    Burrow = burrowTrack,
})
-- Beim Entfernen des Rigs unbind() aufrufen.
```

Spawn, Treffer und Schaden bleiben bei Claude. Die Bodeneffekte folgen der Höhe und Neigung des vorhandenen Terrains. [Roblox Raycasting](https://create.roblox.com/docs/workspace/raycasting) · [Roblox-Animationsmarker](https://create.roblox.com/docs/animation/events)

Das [Soundpaket](../../audio/sandwurm/README.md) ordnet den vier Markern eigene WAV-Dateien zu.

## Studio-Prüfung

Alle vier Marker lösten in der Reihenfolge Warnung, Ausbruch, Biss und Abtauchen aus. Die Partikelquellen am Boden wurden auf Terrain mit bis zu 17,26 Studs Höhenunterschied geprüft. Beide Bissquellen lagen am animierten Kopf. Beim Abbrechen einer laufenden Warnung wurde ihr Effektanker entfernt.

Die Aufnahmen zeigen die Partikel im lokalen Spieltest mit dem animierten Knochenrig. Das Wurm-Mesh wurde separat im Editor geladen und geprüft. Für die gemeinsame Spielvorschau muss die vorhandene GLB als Mesh importiert sein, da die temporäre Editor-Geometrie im Spieltest nicht gerendert wird. [Roblox Studio-Importer](https://create.roblox.com/docs/studio/importer)

[BuildSandwormEffects.editor.luau](BuildSandwormEffects.editor.luau) baut das Effektpaket in Studio oder mit Lune. Das RBXM wurde nach dem Export erneut eingelesen.
