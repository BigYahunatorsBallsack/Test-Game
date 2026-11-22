# Koloss-Fortschrittsanzeige

[Desktop-Vorschau](koloss_fortschritt.jpg) · [Handy-Vorschau beim Abschluss](koloss_abschluss_mobil.jpg) · [Roblox-Komponente](../../../src/client/Interface/ColossusStatus.luau)

Die Karte zeigt den gemeinsamen Grabungsfortschritt und den zuletzt freigelegten Abschnitt. Der Balken ist während der Grabung türkis und beim Abschluss goldfarben. Auf breiten Bildschirmen sitzt die Karte oben rechts. Auf schmalen Bildschirmen steht sie mittig unter der HUD-Navigation.

## Übergabe an Claude

Einmal für das HUD mounten. `Update` erhält den bestätigten Fortschritt als Zahl zwischen 0 und 1. `lastSection` kann `northHand` oder `feet` sein. `Update(nil)` blendet die Karte bei inaktivem Event aus. Beim Neubau des HUDs die vorherige Karte mit `Destroy()` entfernen.

```luau
local status = ColossusStatus.Mount(playerGui)
status.Update({progress = confirmedProgress, lastSection = confirmedSection})
```

In der lokalen Prüfung wurden 320, 768, 1024 und 1440 Pixel sowie Öffnen, Aktualisieren, Abschluss und Ausblenden abgedeckt. Bei reduzierter Bewegung springt der Balken direkt auf den aktuellen Wert. Die Layoutbilder verwenden Beispielstände und eine vorhandene Studio-Aufnahme. Der türkise Lichtimpuls in der Handy-Vorschau ist eine Illustration des [Effektpakets](../../world/koloss_fx/README.md). [Roblox GuiService](https://create.roblox.com/docs/reference/engine/classes/GuiService#ReducedMotionEnabled)
