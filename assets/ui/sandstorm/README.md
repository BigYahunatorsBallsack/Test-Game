# Sandsturm-Ergebnis

[Ablaufvorschau](sandsturm_ablauf.gif) · [Handy-Vorschau](sandsturm_ergebnis_mobil.jpg) · [Roblox-Komponente](../../../src/client/Interface/SandstormResult.luau)

Nach dem Sturm erscheint die bestätigte Menge Windkristalle. Wenn die Ruinenstadt gerade neu freigeschaltet wurde, steht das als eigene Zeile dabei. Die Karte lässt sich direkt schließen. Bei reduzierter Bewegung blendet sie sich in fester Größe ein. In den Bildern ist der Kristallbetrag ein Beispiel.

## Übergabe an Claude

Einmal für das vorhandene HUD mounten. Nach dem [Sturmübergang](../../world/sandstorm_fx/README.md) den serverseitig bestätigten Betrag als formatierten Text ohne Pluszeichen und den bestätigten Freischaltstatus übergeben. Beim Neubau des HUDs die vorherige Instanz mit `Destroy()` entfernen. [Roblox GuiService](https://create.roblox.com/docs/reference/engine/classes/GuiService#ReducedMotionEnabled)

```luau
local result = SandstormResult.Mount(playerGui)
result.Show({
    windCrystals = confirmedCrystalText,
    ruinsUnlocked = justUnlockedRuins,
})
```

Die lokale Prüfung deckte 320, 768, 1024 und 1440 Pixel sowie lange Beträge, Schließen, aufeinanderfolgende Einblendungen und den optionalen Freischalthinweis ab.
