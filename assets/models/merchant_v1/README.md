# Sandhändler im Dünenmeer

Der Verkaufsstand im Startlager hat eine gestreifte Stoffmarkise, ein Münzschild und eine Messingwaage mit Sandprobe und Gegengewicht. Auf der Theke stehen Münzstapel. Am hinteren Regal und neben den Stützen liegen Probengefäße und Sandsäcke. Türkis und Messing verbinden die Markise, das Schild und die Front mit dem restlichen Lager.

[Studio-Aufnahme](sandhaendler.jpg) · [Roblox-Modellpaket](DuneBaron_Merchant.rbxm)

Das Modell steht im Studio-Entwurf **Every Last Grain** unter `Workspace.DuneBaronWorld.Props.Merchant`. Mit den seitlichen Sandsäcken misst es **13,15 × 9,62 × 9,13 Studs**. Der Pivot sitzt mittig auf dem Holzboden bei `(0, 6.6, -30)`. Die Vorderseite zeigt zum Spawn entlang `+Z`. Das lokale Modellpaket verwendet denselben Pivot am Bodenursprung. [Roblox PivotTo](https://create.roblox.com/docs/reference/engine/classes/PVInstance#PivotTo)

## Studio-Prüfung

Der Testavatar lief vom Spawn bis auf das Händlerdeck. Der vorhandene Prompt **Verkaufen** erschien auf dem Weg und löste auf dem Deck mit **E** aus. Thekenkollision und der mit `SellStand` markierte Interaktionspunkt liegen an den bisherigen Positionen.

[BuildMerchant.editor.luau](BuildMerchant.editor.luau) baut das Modell in Studio oder exportiert das RBXM mit Lune. Die vorherige Standversion liegt im Place unter `ServerStorage.DuneBaronMerchantBackup.Merchant`.
