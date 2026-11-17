# Testfälle pro Arbeitspaket

Jedes Arbeitspaket bekommt hier im Plan-Modus seinen Abschnitt, bevor Code entsteht. Ein Paket ist fertig, wenn seine Testfälle laufen und committed sind.

- **[Lune]:** Läuft in der Shell mit Lune, ohne Studio. Gilt für reine Logik ohne Roblox-API.
- **[Studio]:** Muss im Playtest oder mit Studio-Testkäufen geprüft werden.

## Pflicht für alle Pakete mit Käufen und Kisten (4.1, 4.2, 4.4, 4.5, 5.5)

- [ ] [Lune] Dieselbe PurchaseId zweimal: Die Gutschrift erfolgt nur einmal, der zweite Aufruf liefert PurchaseGranted ohne neue Gutschrift.
- [ ] [Lune] Abbruch vor dem Speichern (Speichern schlägt fehl oder Profil nicht geladen): Ergebnis ist NotProcessedYet, und es gibt keine Gutschrift.
- [ ] [Lune] Der Pity-Zähler übersteht Speichern und Laden (Neustart) unverändert.
- [ ] [Lune] Quoten-Simulation mit sehr vielen Öffnungen pro Kiste: Die Abweichung von der Quotentabelle bleibt klein. Anzeige und Auswurf lesen dieselbe Tabelle.
- [ ] [Lune] Im 10er-Paket zählt jede der 11 Öffnungen für Pity.
- [ ] [Lune] Bei `ArePaidRandomItemsRestricted = true` lehnt der Server jede Kisten-Interaktion ab.
- [ ] [Studio] Testkauf in Studio: Die Gutschrift erscheint genau einmal und bleibt nach dem Rejoin erhalten.

## 2.1 Skilltree-Daten und Kauf-Server

- [ ] [Lune] Ein Kauf ohne Voraussetzung wird abgelehnt.
- [ ] [Lune] Ein Doppelklick (zwei schnelle `PurchaseNode(id)`) kauft nicht zweimal.
- [ ] [Lune] Zu wenig Geld wird abgelehnt. [Studio] Der Client zeigt den Fehler.
- [ ] [Studio] Der Spielstand lädt nach einem Neustart korrekt.
- [ ] [Lune] Ein Baum-Update (Knoten hinzugefügt oder entfernt) zerstört keinen alten Spielstand.

## 2.5 Zonen-Freischaltung

- [ ] [Lune] Eine Zone wird frei, sobald ihr `requires`-Knoten (zum Beispiel `det_milestone_1`) gekauft ist, sonst nicht.
- [ ] [Lune] Ein Umbau des Baums, der die Position des Meilensteins ändert, lässt bereits freigeschaltete Zonen frei.

## 5.1 Daily Reward

- [ ] [Lune] Tag 7 gibt die Eisenkiste oder bei `ArePaidRandomItemsRestricted = true` den festen Ersatzgegenstand.

## 5.3 Begleiter und Offline-Ertrag

- [ ] [Lune] Der Offline-Ertrag wird bei der Grenze gekappt (ohne Pass etwa 4 Stunden, mit Auto-Dig länger).
- [ ] [Lune] Der Offline-Ertrag enthält keine Funde ab "Selten".
