# Werkstatt · Every Last Grain

Der Knopf **Baum** öffnet die Werkstatt, sobald ihn das Tutorial freigibt. Jeder Gerätereiter enthält 48 Knoten. In der Detailkarte lassen sich benachbarte Ausbaustufen anhand ihrer tatsächlichen Sprites vergleichen und direkt anwählen. Der gemerkte Knoten trägt eine Raute. Auf schmalen Displays öffnet sich die Detailkarte unter der verschiebbaren Karte.

Eine petrolfarbene Kartentafel mit Höhenlinien, Holz in der Kopfzeile und Messing an den Fassungen prägen die Werkstatt. Die Dialoge und Detailkarten verwenden dieselbe dunkle Stahltextur. [Aktuelle Studio-Ansicht](Werkstatt_Tafel.jpg)

**Übersicht** zeigt den gesamten gewählten Baum und die Zahl der bereits gelernten Knoten. In **Ziele und Voraussetzungen** lassen sich Fähigkeiten, Meilensteine und das gemerkte Upgrade direkt aufrufen, auch wenn es in einem anderen Reiter liegt. Türkise Pfade zeigen nötige Knoten. Bernsteinfarbene Pfade zeigen mögliche Alternativen. Über **Karte** kommst du zum vorherigen Kartenausschnitt zurück. Den bisherigen **Laufbaum** findest du rechts in der Reiterleiste.

**Suche** durchsucht alle 363 Upgrades nach Name, Gerät oder Upgrade-Art. Begriffe lassen sich kombinieren, etwa „Schaufel Meisterschaft“. Auch „Foerderband“ findet die Eimerkette. Ein Treffer öffnet den Knoten in seinem Baum. Enter öffnet den ersten Treffer, solange das Suchfeld fokussiert ist.

**Varianten vergleichen** zeigt die beiden Fähigkeiten eines Geräts mit Wirkung, Lernstatus, Preis und Voraussetzung. Jede Variante hat ihre eigene Ego-Illustration und eine daran ausgerichtete animierte Spur. Die Vorschauen starten gemeinsam und lassen sich wiederholen. In der schmalen Ansicht stehen die Karten untereinander. **Zum Knoten** springt zurück in den Baum.

Beim Lernen zeigt eine Freischaltmeldung das Upgrade und die Knoten, deren Voraussetzungen jetzt erfüllt sind. Eine Lichtspur verbindet direkte Nachfolger auf derselben Karte. Große Fähigkeiten und Meisterschaften erhalten einen kräftigeren Effekt. Beim Ausrüsten einer Variante bestätigt die Meldung den Wechsel. Bei reduzierter Bewegung erscheint nur die Meldung.

Die Werkstatt hat getrennte Audioereignisse für Knotenauswahl, Ausbau, große Fähigkeit und Variantenwechsel. [Werkstatt-Sounds und Hörvergleich](../../../audio/workshop/README.md)

Der **Lernplan** zeigt die noch fehlenden Schritte und deren Gesamtkosten. Bei alternativen Voraussetzungen berechnet er den günstigsten verbleibenden Weg. Bereits gelernte Knoten fallen aus der Rechnung. Ein Klick auf einen Schritt öffnet den Knoten im Baum. In der Übersicht führt der Lernplan direkt zum gemerkten Ziel.

**Gerätewerte** zeigt die addierten Boni pro Gerät und Fähigkeit. Bei einem noch ungelernten Upgrade zeigt die Übersicht außerdem den Wert nach Hinzurechnen seines Bonus. Die Abklingzeit ergibt sich aus der Grundzeit und den gelernten Reduktionen. Gelernte Varianten behalten eigene Werte, und der Status zeigt, welche im Probelauf ausgerüstet ist.

Ziehe die Karte mit der Maus oder mit einem Finger. Das Mausrad zoomt zum Mauszeiger, die Zwei-Finger-Geste zur Mitte der Berührungspunkte. Die Plus- und Minusknöpfe zoomen zur Kartenmitte. Jeder Reiter merkt sich Ausschnitt und Zoom für die laufende Spielsitzung. Die Rückkehr aus der Übersicht stellt den vorherigen Ausschnitt wieder her.

Mit **Pfeiltasten** oder **Steuerkreuz** gehst du zum nächsten Knoten in der gewählten Richtung. Die Karte folgt der Auswahl. **Bild hoch/runter** oder **LB/RB** wechseln den Gerätereiter. **Enter** oder **A** öffnen die Knotendetails. Am Controller führt **B** aus den Details zurück zur Karte.

[Studio-Modell](ELG_Werkstatt.rbxm) · [Baumübersicht](Werkstatt_Uebersicht.jpg) · [Upgradesuche](Werkstatt_Suche.jpg) · [Variantenvergleich](Werkstatt_Varianten.jpg) · [Meisterschaft](Werkstatt_Meisterschaft.jpg) · [Freischalteffekt](Werkstatt_Freischaltung.jpg) · [Lernplan](Werkstatt_Lernplan.jpg) · [Gerätewerte](Werkstatt_Geraetewerte.jpg) · [Probelauf](Werkstatt_Probelauf.jpg) · [Stufenvergleich](Werkstatt_Spieltest.jpg) · [Gerätestufen](Werkstatt_Geraetestufen.png) · [Stufen für den Lauf](Werkstatt_Ausbaustufen.png)

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

Die 318 neuen Knoten sind im **Probelauf** lernbar. **Mit der Hand starten** beginnt mit 100 Testmünzen und ohne gelernte Upgrades. **Aktuellen Fortschritt kopieren** übernimmt Besitz und Münzen aus dem aktuellen Lauf. **Alle Geräte testen** stellt die sechs Geräte, die erste Sturmbelohnung und eine Milliarde Testmünzen bereit.

Über **Testoptionen** kannst du einen neuen Probelauf beginnen oder zum Spielstand zurückkehren. Ein neuer Startpunkt ersetzt die bisherige Probe. **Fortsetzen** lädt den letzten Probelauf der Sitzung mit seinem Guthaben, Besitz und den ausgerüsteten Varianten. Die Preise, Zeitfenster und Wirkungswerte der neuen Knoten sind für den Playtest vorgesehen.

## Übergabe an Claude

Der [Katalog](../../../../src/client/Interface/Workshop/Catalog.luau) baut die Daten aus [Gerätewerten](../../../../src/client/Interface/Workshop/Devices.json), [zusätzlichen Lauf-Upgrades](../../../../src/client/Interface/Workshop/Support.json) und der vorhandenen UpgradeTree-Liste auf. `byId` enthält Namen, Preise, Effekte und Voraussetzungen. Alle Einträge in `requires` müssen erfüllt sein. Bei nichtleerem `requiresAny` muss mindestens ein Eintrag erfüllt sein. `live` bezeichnet die bestehenden Serverknoten. Die IDs aus den ursprünglichen zwölf Fähigkeitsentwürfen bleiben erhalten.

Für die Gameplay-Anbindung liegen Käufe, Speichern, aktiver Variantenslot, Anwendung der Gerätewerte beim Graben und die Behandlung des Sandsturms beim Server. Neue Käufe sind als laufbezogen entworfen. Bereits geltende Dauerfreischaltungen wie der erste Sandsturm folgen der vorhandenen Spiellogik.

Die Ego-Karten verwenden 24 Illustrationen mit 24 animierten Wirkungsverläufen. Jede Meisterschaft zeigt ihren Ablauf in zwei beschrifteten Phasen. Die Vorschauen dauern je nach Gerät 2,4 bis 3,6 Sekunden. Bei reduzierter Bewegung erscheinen beide Schritte zusammen als Standbild. Es handelt sich um UI-Animationen mit dem Ziel **Ego-Vorschaufläche**. Die Spieler-Rigs werden davon nicht bewegt.

## Studio und Bildassets

Das einzelne Modell lässt sich als `ScreenGui` in `StarterGui` einsetzen und im Play-Modus öffnen. Es enthält eine eigenständige Probier-Werkstatt. Im normalen Projekt übernimmt der SkillTree-Controller die Anbindung.

| Roblox-Atlas | Asset-ID | Inhalt |
|---|---:|---|
| Fähigkeitssymbole | 121329522523108 | Vier Leitmotive je Gerät sowie vier Astzeichen |
| Ego-Szenen | 133913310301503 | Sechs Ego-Illustrationen |
| [Ego-Varianten für Hand, Schaufel und Förderband](Werkstatt_Ego_Hand_Schaufel_Foerderband.png) | 127194462292023 | Je zwei Szenen pro Gerät |
| [Ego-Varianten für Bagger, Saugroboter und Harvester](Werkstatt_Ego_Bagger_Roboter_Harvester.png) | 139759034484553 | Je zwei Szenen pro Gerät |
| [Ego-Meisterschaften](Werkstatt_Ego_Meisterschaften.png) | 85422764371102 | Je eine Szene pro Gerät |
| [Werkstattmaterialien](Werkstatt_Materialien.png) | 76841357655479 | Kartentafel, Holz, Stahl und Messing |
| Gerätestufen | 134288678818985 | 24 passive Motive und 120 gerätespezifische Stufensprites |
| Lauf-Upgrades | 71482682642103 | 75 Ausbausprites |

Die [Spritezuordnung](../../../../src/client/Interface/Workshop/TierArt.json) ist nach Knoten-ID indiziert. Die großen Gerätefähigkeiten verwenden weiterhin ihr eigenes Leitmotiv. Die Stufenatlanten lassen sich mit `python assets/ui/skill_tree/werkstatt/build_tiers.py` aus den mitgelieferten Bildquellen erzeugen. Für den Modell-Export dient `rojo build assets/ui/skill_tree/werkstatt/Studio.project.json -o assets/ui/skill_tree/werkstatt/ELG_Werkstatt.rbxm`. `lune run tests/workshop.spec.luau` prüft das exportierte Modell.
