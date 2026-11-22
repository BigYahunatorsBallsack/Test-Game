# Münzanimation beim Verkauf

[Vorschau am Händlerstand](verkauf_vorschau.jpg) · [Roblox-Komponente](../../../src/client/Interface/SaleFeedback.luau)

Nach einem bestätigten Verkauf erscheint der ausgezahlte Betrag in einer kompakten Karte. Fünf Münzikonen fächern kurz auf und fliegen anschließend zum übergebenen Münzzähler. Bei reduzierter Bewegung bleibt die Rückmeldung eine kurze Einblendung.

## Übergabe an Claude

Einmal für das vorhandene HUD mounten. Bei `sold` den formatierten Betrag ohne Pluszeichen und das sichtbare Münzicon des HUDs übergeben. Der Aufrufer kann gleichzeitig den [Verkaufsklang](../../audio/starter/README.md) abspielen. Beim Neubau des HUDs die vorherige Instanz mit `Destroy()` entfernen. [Roblox GuiService](https://create.roblox.com/docs/reference/engine/classes/GuiService#ReducedMotionEnabled)

```luau
local sale = SaleFeedback.Mount(playerGui)
sale.Show(formattedEarnedCoins, coinIcon)
```

Münzflugziele, kleine Bildschirmbreiten, große Beträge, aufeinanderfolgende Verkäufe und reduzierte Bewegung wurden lokal geprüft. Das Bild ist eine Vorschau aus dem aktuellen Händlerbild und dem vorhandenen Münzicon. Der Studio-Spieltest steht aus.
