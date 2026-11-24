# Werkstatt für Every Last Grain

[Studio-Entwurf](ELG_Werkstatt_UI.rbxm) · [Sammeln](skilltree_desktop.jpg) · [Weitere Äste](skilltree_aeste.jpg) · [Handy-Ansicht](skilltree_handy.jpg)

Die Werkstatt zeigt Sammeln, Tank, Verkauf, Glück und Sandsturm als fünf Reiter. Im Sammelast bilden sechs Werkzeugstufen den Hauptpfad. Direkt unter jedem Werkzeug liegt eine eigene aktive Fähigkeit mit einer Folgeverstärkung. Passive Ratenboni haben einen eigenen Pfad. Die Detailspalte zeigt Wirkung, Voraussetzungen, Preis oder Erwerbsart. Auf dem Handy stehen die Details des ausgewählten Werkzeugs unter der Reihe aus sechs antippbaren Werkzeugplätzen.

Die Vorschau verwendet alle 45 Knoten, Preise und Voraussetzungen aus [UpgradeTree.luau](../../../src/shared/Data/UpgradeTree.luau) und die Startstufe aus [Tools.luau](../../../src/shared/Data/Tools.luau). 740 Münzen und die erworbenen Knoten sind ein Beispielsnapshot. Gelernte, kaufbare, zu teure und wegen einer Voraussetzung gesperrte Knoten haben eigene Zustände. Der erste Sandsturm ist als Belohnung gekennzeichnet.

## Neue Gadget-Fähigkeiten

| Werkzeug | Großer Knoten | Folgeknoten |
|---|---|---|
| Hand | **Kornprobe** macht nahe Fundspuren kurz sichtbar. | **Lesbare Spuren** lassen die Markierungen länger stehen. |
| Schaufel | **Tiefstich** gräbt beim nächsten Einsatz tiefer am Fadenkreuz. | **Tiefenkante** erreicht eine tiefere Sandschicht. |
| Eimerkette | **Doppeltakt** beschleunigt vorübergehend den Transport vom Einlauf zum Tank. | **Nachlauf** verlängert den schnellen Takt. |
| Mini-Bagger | **Querzug** zieht beim nächsten Löffelhub eine breite, flache Rinne. | **Breitlöffel** verbreitert die Rinne. |
| Saugroboter | **Wirbelsog** bündelt losen Sand von beiden Seiten vor der Düse. | **Seitendüsen** vergrößern den seitlichen Einzug. |
| Großmaschine | **Pufferfahrt** lagert bei vollem Tank vorübergehend Sand in der Maschine und überträgt ihn, sobald Platz frei wird. | **Pufferbleche** erhöhen die Zwischenkapazität. |

Der zugehörige Werkzeugknoten ist die Voraussetzung für seine Fähigkeit. Die Hand steht zu Spielbeginn bereit. Der Folgeknoten setzt die Fähigkeit voraus. Preise, Abklingzeiten und Balance der zwölf Entwurfsknoten sind offen.

## Inspiration aus dem lokalen Referenzspiel

Im Unity-Build von *One Million Coins* liegen die gefundenen Skillnamen und Beschreibungstexte in `One Million Coins_Data/Managed/Assembly-CSharp.dll`. Der Baum wird aus mehreren Teilen des kompilierten Katalogs aufgebaut. Die enthaltenen Texte zeigen Muster für Handsammeln und Timing, aufgeladene Schaufelaktionen, Magnetimpulse mit Reichweite und Wiederaufladung, Tank und automatische Entleerung, tragbare Ablage, Sammelhilfe und Rutschen mit zeitlich begrenztem Schub. Ein vollständiger Abgleich aller im Spiel angezeigten Knoten steht aus.

## Studio-Übergabe

Die RBXM-Datei enthält eine Mappe mit sechs `ScreenGui`-Ansichten. Für eine Vorschau lässt sich jeweils eine Ansicht unter `StarterGui` öffnen. Die Knotenrahmen verwenden `nodeId`, `requires`, `branch`, `cost` und `previewState` als Attribute. Die neuen Fähigkeiten und Folgeknoten tragen `designId`, `gadgetNodeId` und `status`. Folgeknoten verweisen zusätzlich über `requiresDesignId` auf ihren Fähigkeitsknoten.

Alle Ansichten verwenden den eigenen bestehenden Core-Atlas. Die Datei wurde lokal erneut eingelesen und auf sechs Ansichten, 45 Upgrade-IDs, die Startstufe, zwölf Fähigkeitsentwürfe, gültige Atlasausschnitte und die Abwesenheit von Skripten geprüft. Die JPEGs zeigen denselben Entwurf. Ein Live-Test der Roblox-Ansichten und die Anbindung von Navigation, Kauf und Fähigkeiten stehen aus.
