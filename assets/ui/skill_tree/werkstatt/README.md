# Werkstatt · Every Last Grain

Der Knopf **Baum** öffnet die Werkstatt, sobald ihn das Tutorial freigibt. Jeder Gerätereiter enthält 48 Knoten. In der Detailkarte lassen sich benachbarte Ausbaustufen anhand ihrer tatsächlichen Sprites vergleichen und direkt anwählen. Der gemerkte Knoten trägt eine Raute. Auf schmalen Displays öffnet sich die Detailkarte unter der verschiebbaren Karte.

**Übersicht** zeigt den gesamten gewählten Baum und die Zahl der bereits gelernten Knoten. In **Ziele und Voraussetzungen** lassen sich Fähigkeiten, Meilensteine und das gemerkte Upgrade direkt aufrufen, auch wenn es in einem anderen Reiter liegt. Türkise Pfade zeigen nötige Knoten. Bernsteinfarbene Pfade zeigen mögliche Alternativen. Über **Karte** kommst du zum vorherigen Kartenausschnitt zurück. Den bisherigen **Laufbaum** findest du rechts in der Reiterleiste.

**Suche** durchsucht alle 363 Upgrades nach Name, Gerät oder Upgrade-Art. Begriffe lassen sich kombinieren, etwa „Schaufel Meisterschaft“. Auch „Foerderband“ findet die Eimerkette. Ein Treffer öffnet den Knoten in seinem Baum. Enter öffnet den ersten Treffer, solange das Suchfeld fokussiert ist.

[Studio-Modell](ELG_Werkstatt.rbxm) · [Baumübersicht](Werkstatt_Uebersicht.jpg) · [Upgradesuche](Werkstatt_Suche.jpg) · [Stufenvergleich](Werkstatt_Spieltest.jpg) · [Gerätestufen](Werkstatt_Geraetestufen.png) · [Stufen für den Lauf](Werkstatt_Ausbaustufen.png)

## Geräte und Fähigkeiten

| Gerät | Grundfähigkeit | Variante A | Variante B | Meisterschaft |
|---|---|---|---|---|
| Hand | Kornprobe | Schichtleser | Sandsieb | Doppelprobe |
| Schaufel | Tiefstich | Schichtöffner | Grabenzieher | Anschlussstich |
| Eimerkette | Doppeltakt | Doppelschacht | Rücklauf | Vollumlauf |
| Mini-Bagger | Querzug | Räumhub | Feinhub | Zweiter Hub |
| Saugroboter | Wirbelsog | Fächersog | Feinabscheidung | Nachsog |
| Dünen-Harvester | Pufferfahrt | Walzenspur | Umladewerk | Durchlauf |

Jedes Gerät hat 24 passive Knoten in vier verzweigten Reihen, vier große Fähigkeits- und Meisterschaftsknoten, 17 Verstärkungen und drei zusätzliche Spezialisierungen. Beide Varianten sind erlernbar. Im Probelauf kann je Gerät eine davon ausgerüstet sein. Für die Meisterschaft genügt der Abschluss eines der vier Variantenpfade.

Die fünf weiteren Reiter enthalten 17 Werkzeug- und Ratenstufen, 20 Tank-Upgrades, 16 Verkaufs-Upgrades, 14 Glücks-Upgrades und 8 Sandsturm-Knoten. Insgesamt sind es **363 verschiedene IDs**. Werkzeugfreischaltungen des Grundspiels bleiben unabhängig von den neuen Gerätebäumen.

## Spielbetrieb und Probelauf

Die 45 bisherigen Knoten beziehen Beschreibung, Kosten, Wirkung und Voraussetzungen direkt aus dem Spiel. Reguläre Käufe laufen über den vorhandenen servergeprüften Kaufweg. Der erste Sandsturm wird vergeben. **Laufbaum** öffnet die bisherige Ansicht.

Die 318 neuen Knoten sind im **Probelauf** lernbar. Die Werkstatt kopiert beim ersten Start der Probe den Besitz und stellt alle Geräte, den ersten Sturm und eine Milliarde Testmünzen bereit. Das Probeguthaben, Markierungen und die ausgerüstete Probevariante existieren nur in der Sitzung. Beim Verlassen der Probe zeigt die Werkstatt wieder die echten Münzen und den echten Besitz. Die neuen Preise, Zeitfenster und Wirkungswerte sind für den Playtest vorgesehen.

## Übergabe an Claude

Der [Katalog](../../../../src/client/Interface/Workshop/Catalog.luau) baut die Daten aus [Gerätewerten](../../../../src/client/Interface/Workshop/Devices.json), [zusätzlichen Lauf-Upgrades](../../../../src/client/Interface/Workshop/Support.json) und der vorhandenen UpgradeTree-Liste auf. `byId` enthält Namen, Preise, Effekte und Voraussetzungen. Alle Einträge in `requires` müssen erfüllt sein. Bei nichtleerem `requiresAny` muss mindestens ein Eintrag erfüllt sein. `live` bezeichnet die bestehenden Serverknoten. Die IDs aus den ursprünglichen zwölf Fähigkeitsentwürfen bleiben erhalten.

Für die Gameplay-Anbindung liegen Käufe, Speichern, aktiver Variantenslot, Anwendung der Gerätewerte beim Graben und die Behandlung des Sandsturms beim Server. Neue Käufe sind als laufbezogen entworfen. Bereits geltende Dauerfreischaltungen wie der erste Sandsturm folgen der vorhandenen Spiellogik.

Die Ego-Karten verwenden sechs Illustrationen mit 24 animierten Wirkungsverläufen. Die Vorschauen dauern je nach Gerät 2,4 bis 3,6 Sekunden. Bei reduzierter Bewegung erscheint das Endbild. Es handelt sich um UI-Animationen mit dem Ziel **Ego-Vorschaufläche**. Die Spieler-Rigs werden davon nicht bewegt.

## Studio und Bildassets

Das einzelne Modell lässt sich als `ScreenGui` in `StarterGui` einsetzen und im Play-Modus öffnen. Es enthält eine eigenständige Probier-Werkstatt. Im normalen Projekt übernimmt der SkillTree-Controller die Anbindung.

| Roblox-Atlas | Asset-ID | Inhalt |
|---|---:|---|
| Fähigkeitssymbole | 121329522523108 | Vier Leitmotive je Gerät sowie vier Astzeichen |
| Ego-Szenen | 133913310301503 | Sechs Ego-Illustrationen |
| Gerätestufen | 134288678818985 | 24 passive Motive und 120 gerätespezifische Stufensprites |
| Lauf-Upgrades | 71482682642103 | 75 Ausbausprites |

Die [Spritezuordnung](../../../../src/client/Interface/Workshop/TierArt.json) ist nach Knoten-ID indiziert. Die großen Gerätefähigkeiten verwenden weiterhin ihr eigenes Leitmotiv. Die Stufenatlanten lassen sich mit `python assets/ui/skill_tree/werkstatt/build_tiers.py` aus den mitgelieferten Bildquellen erzeugen. Für den Modell-Export dient `rojo build assets/ui/skill_tree/werkstatt/Studio.project.json -o assets/ui/skill_tree/werkstatt/ELG_Werkstatt.rbxm`. `lune run tests/workshop.spec.luau` prüft das exportierte Modell.
