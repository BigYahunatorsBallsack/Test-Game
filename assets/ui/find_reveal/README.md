# Fundanzeige

[Desktop-Vorschau](fundanzeige_desktop.jpg) · [Handy-Vorschau](fundanzeige_mobil.jpg) · [Roblox-Komponente](../../../src/client/Interface/FindReveal.luau)

Nach einem Fund erscheint eine kompakte Karte oben im Spielfeld. Sie zeigt das vorhandene Fundicon, den Seltenheitsrahmen, den Namen und die Zone. Beim ersten Exemplar steht dort **Neuer Fund!**. Bei Folgefunden steht **Fund geborgen**. Seltene Funde und höhere Stufen bekommen einen kurzen Glanz auf der Iconfläche. Die Roblox-Einstellung für reduzierte Bewegung lässt die Karte ohne Größenbewegung und Glanz erscheinen.

Die Karte blendet sich nach 2,45 bis 3,75 Sekunden aus, lässt sich direkt schließen und zeigt bei schnellen Folgefunden jeweils den neuesten Fund. Auf einem 320 Pixel breiten Display bleiben 12 Pixel Rand auf beiden Seiten.

## Übergabe an Claude

Die Komponente einmal im vorhandenen HUD mounten. Beim bestätigten Fund `Show` mit der ID aus dem aktuellen UI-Katalog und dem vom Spiel ermittelten Sammlungsstatus aufrufen. Der Aufrufer kann den [Fundklang](../../audio/finds/README.md) anhand der bestätigten Seltenheit auslösen. Bei einer erneuten HUD-Initialisierung zuerst `Destroy()` auf der vorherigen Instanz aufrufen.

```luau
local reveal = FindReveal.Mount(playerGui)
reveal.Show(findId, isNew)
```

Wiederholte Einblendungen, schließbare und ablaufende Karten, reduzierte Bewegung sowie alle 150 Katalog-IDs wurden lokal geprüft. Die Layoutprüfung deckte 320, 768, 1024 und 1440 Pixel ab. Die Bilder sind Layoutvorschauen aus den vorhandenen Roblox-Weltaufnahmen und Atlanten. Der Studio-Spieltest steht aus. [Roblox GuiService](https://create.roblox.com/docs/reference/engine/classes/GuiService#ReducedMotionEnabled)
