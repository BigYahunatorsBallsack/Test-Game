# Testfälle pro Arbeitspaket

Jedes Arbeitspaket bekommt hier im Plan-Modus seinen Abschnitt, bevor Code entsteht. Ein Paket ist fertig, wenn seine Testfälle laufen und committed sind.

- **[Lune]:** Läuft in der Shell mit Lune, ohne Studio. Gilt für reine Logik ohne Roblox-API.
- **[Studio]:** Muss im Playtest oder mit Studio-Testkäufen geprüft werden.
- **[Shell]:** Läuft in der Shell ohne Studio, aber nicht mit Lune, zum Beispiel `rojo build` oder `git status`.

## 0.1 Datentabellen

- [ ] [Lune] Jede Quotenspalte ergibt genau 10.000 Hundertstel-Prozent (100 %): Fundstücke, Holz-, Eisen- und Goldkiste. Neue Quotentabellen werden automatisch mitgeprüft.
- [ ] [Lune] Jede Quote ist eine ganze Zahl ab 0, und jede Seltenheit in einer Quotentabelle existiert in `Rarities` (keine Tippfehler-IDs).
- [ ] [Lune] Eine absichtlich kaputte Tabelle (Summe 9.999) lässt die Prüfung fehlschlagen.
- [ ] [Lune] Die Event-Kiste verweist auf dieselbe Quotentabelle wie die Goldkiste (gleiche Referenz, keine Kopie).
- [ ] [Lune] Alle IDs sind pro Tabelle eindeutig (Seltenheiten, Werkzeuge, Sandsorten, Zonen, Kisten, Gem-Pakete, Produkte, Knoten).
- [ ] [Lune] Werkzeugstufen: Sand pro Sekunde und Preis steigen streng mit der Stufe, die Hand kostet 0, und jede Stufe verweist auf einen Knoten in `UpgradeTree`.
- [ ] [Lune] Jede Zone verweist auf eine existierende Sandsorte. Ihre Freischaltung ist "Start" oder eine Knoten-ID, die in `UpgradeTree` existiert, nie eine feste Zahl.
- [ ] [Lune] Gem-Pakete: Der aus Gems und Robux berechnete Bonus gegenüber dem kleinsten Paket entspricht der Konzeptspalte auf 1 Prozentpunkt genau. Gems und Robux steigen.
- [ ] [Lune] Jede Kiste hat einen Preis über 0 und die Währung `coins` oder `gems`. Die Pity der Goldkiste liegt bei 15 (Episch oder besser) und 60 (Legendär oder besser), das 10er-Paket gibt 11.
- [ ] [Lune] Alle Datenmodule laden unter Lune ohne Roblox-API. Farben sind Hex-Text.
- [ ] [Studio] Beim Playtest prüft der Server die Tabellen beim Start und meldet keine Fehler im Output.

## 0.2 Projekt-Setup

- [ ] [Lune] `lune run tests/run` findet alle `*.spec.luau`, führt sie aus und endet bei Erfolg mit Code 0, bei einem fehlschlagenden Test mit Code ungleich 0.
- [ ] [Lune] Ein Beispieltest lädt ein Modul aus `src/shared` per Pfad-`require` und läuft.
- [ ] [Shell] `rojo build -o build/test.rbxl` baut ohne Fehler.
- [ ] [Shell] Nach `rojo build` und einem Testlauf zeigt `git status` keine neuen Dateien (die `.gitignore` greift).
- [ ] [Studio] Nach `rojo serve` und Verbinden liegen Shared, Server und Client an den richtigen Orten. Eine gespeicherte Änderung erscheint sofort in Studio.
- [ ] [Studio] Beim Playtest drucken Server und Client je eine Zeile, und der Pfad-`require` funktioniert auch in Studio.

## 0.3 Architektur

- [ ] [Lune] Ein Spieler ohne Daten bekommt ein Standardprofil mit der aktuellen Version.
- [ ] [Lune] Ein Profil der Version 1 wird mit einer Beispielmigration schrittweise auf Version 2 gebracht. Vorhandene Werte bleiben erhalten, fehlende Felder bekommen Standardwerte.
- [ ] [Lune] Eine zweite Migration desselben Profils ändert nichts mehr.
- [ ] [Lune] Ein Profil mit höherer Version, als der Server kennt, wird nicht migriert und als "nicht speichern" markiert.
- [ ] [Lune] Unbekannte Knoten-IDs im Profil bleiben gespeichert und lassen das Laden nicht scheitern.
- [ ] [Lune] Validierung: Falscher Typ, zu wenige oder zu viele Argumente, NaN, Unendlich, zu lange Texte, unbekannte IDs und Werte außerhalb des Bereichs werden abgelehnt. Gültige Argumente gehen durch.
- [ ] [Lune] Rate-Limit mit simulierter Uhr: N Aufrufe pro Sekunde gehen durch, der nächste wird abgelehnt, nach Ablauf geht es wieder. Spieler und Remotes zählen getrennt.
- [ ] [Lune] Eine Remote ohne Schema oder ohne Rate-Limit in `RemoteSpec` lässt sich nicht registrieren.
- [ ] [Studio] Beim Playtest starten alle 8 leeren Services in fester Reihenfolge (erst Init, dann Start), ohne Fehler im Output.
- [ ] [Studio] Die Remotes liegen unter ReplicatedStorage. Ein Aufruf mit falschem Typ aus der Client-Konsole wird abgelehnt und im Server-Output als Verstoß gezählt, ohne Fehler.

## Pflicht für alle Pakete mit Käufen und Kisten (4.1, 4.2, 4.4, 4.5, 5.5)

- [ ] [Lune] Dieselbe PurchaseId zweimal: Die Gutschrift erfolgt nur einmal, der zweite Aufruf liefert PurchaseGranted ohne neue Gutschrift.
- [ ] [Lune] Abbruch vor dem Speichern (Speichern schlägt fehl oder Profil nicht geladen): Ergebnis ist NotProcessedYet, und es gibt keine Gutschrift.
- [ ] [Lune] Der Pity-Zähler übersteht Speichern und Laden (Neustart) unverändert.
- [ ] [Lune] Quoten-Simulation mit sehr vielen Öffnungen pro Kiste: Die Abweichung von der Quotentabelle bleibt klein. Anzeige und Auswurf lesen dieselbe Tabelle.
- [ ] [Lune] Im 10er-Paket zählt jede der 11 Öffnungen für Pity.
- [ ] [Lune] Bei `ArePaidRandomItemsRestricted = true` lehnt der Server jede Kisten-Interaktion ab.
- [ ] [Studio] Testkauf in Studio: Die Gutschrift erscheint genau einmal und bleibt nach dem Rejoin erhalten.

## 1.2 Sammeln, Tank, Verkaufen

- [ ] [Lune] Der Server berechnet den Sand aus Zeit und Rate. Ein Client, der große Mengen meldet, hat keine Wirkung.
- [ ] [Lune] Verkaufen leert den Tank und bucht Münzen nach Sandsorte der Zone.
- [ ] [Lune] Ein voller Tank stoppt das Sammeln, mehr Sand entsteht nicht.
- [ ] [Studio] Halten sammelt, Loslassen stoppt, der Händlerstand zeigt die richtigen Münzen.

## 1.3 Zahlentyp und Anzeige

- [ ] [Lune] Addieren, Multiplizieren und Vergleichen stimmen unterhalb und oberhalb von 10^15 und gegen Referenzwerte.
- [ ] [Lune] Die Anzeige rundet sauber (K, M, B, T) und springt an Grenzen wie 999,9K nicht falsch.
- [ ] [Lune] Speichern und Laden verändert den Wert nicht.

## 1.4 Terrain-Verformung auf dem Client

- [ ] [Studio] Löcher erscheinen nur beim eigenen Spieler. Ein zweiter Spieler im selben Server sieht sie nicht.
- [ ] [Studio] Der Sand wächst nach, und die Fläche bleibt über lange Sitzungen stabil.
- [ ] [Studio] Auf einem schwachen Handy bleibt die Bildrate flüssig. Fällt sie darunter, greift die Rückfallvariante (sinkende Fläche, Partikel).

## 2.1 Skilltree-Daten und Kauf-Server

- [ ] [Lune] Ein Kauf ohne Voraussetzung wird abgelehnt.
- [ ] [Lune] Ein Doppelklick (zwei schnelle `PurchaseNode(id)`) kauft nicht zweimal.
- [ ] [Lune] Zu wenig Geld wird abgelehnt. [Studio] Der Client zeigt den Fehler.
- [ ] [Studio] Der Spielstand lädt nach einem Neustart korrekt.
- [ ] [Lune] Ein Baum-Update (Knoten hinzugefügt oder entfernt) zerstört keinen alten Spielstand.

## 2.5 Zonen-Freischaltung

- [ ] [Lune] Eine Zone wird frei, sobald ihr `requires`-Knoten (zum Beispiel `collect_milestone_1`) gekauft ist, sonst nicht.
- [ ] [Lune] Ein Umbau des Baums, der die Position des Meilensteins ändert, lässt bereits freigeschaltete Zonen frei.

## 2.7 Sandsturm (Prestige)

- [ ] [Lune] Der Reset setzt Münzen und Werkzeugstufe zurück, behält aber Sammlung und Skins.
- [ ] [Lune] Die Windkristalle werden einmal gutgeschrieben, auch bei zwei schnellen Aufrufen.

## 5.1 Daily Reward

- [ ] [Lune] Tag 7 gibt die Eisenkiste oder bei `ArePaidRandomItemsRestricted = true` den festen Ersatzgegenstand.

## 5.3 Begleiter, Offline-Ertrag und Auto-Dig

- [ ] [Lune] Der Offline-Ertrag wird bei der Grenze gekappt (ohne Pass 4 Stunden, mit Auto-Dig 12 Stunden).
- [ ] [Lune] Der Offline-Ertrag enthält keine Fundstücke ab "Selten".
- [ ] [Lune] Der Offline-Ertrag wird aus dem Zeitstempel des Servers berechnet, nicht aus einer Angabe des Clients.

## 5.6 Server-Event "Der Koloss"

- [ ] [Lune] Der Fortschritt zählt nur serverseitig gemeldeten Sand aus der Event-Zone.
- [ ] [Lune] Die Belohnung wird pro Spieler einmal vergeben und nach Beitrag gestaffelt.
