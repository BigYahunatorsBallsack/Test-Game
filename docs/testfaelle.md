# Testfälle pro Arbeitspaket

Jedes Arbeitspaket bekommt hier im Plan-Modus seinen Abschnitt, bevor Code entsteht. Ein Paket ist fertig, wenn seine Testfälle laufen und committed sind.

- **[Lune]:** Läuft in der Shell mit Lune, ohne Studio. Gilt für reine Logik ohne Roblox-API.
- **[Studio]:** Muss im Playtest oder mit Studio-Testkäufen geprüft werden.
- **[Shell]:** Läuft in der Shell ohne Studio, aber nicht mit Lune, zum Beispiel `rojo build` oder `git status`.

## 0.1 Datentabellen

- [x] [Lune] Jede Quotenspalte ergibt genau 10.000 Hundertstel-Prozent (100 %): Fundstücke, Holz-, Eisen- und Goldkiste. Neue Quotentabellen werden automatisch mitgeprüft.
- [x] [Lune] Jede Quote ist eine ganze Zahl ab 0, und jede Seltenheit in einer Quotentabelle existiert in `Rarities` (keine Tippfehler-IDs).
- [x] [Lune] Eine absichtlich kaputte Tabelle (Summe 9.999) lässt die Prüfung fehlschlagen.
- [x] [Lune] Die Event-Kiste verweist auf dieselbe Quotentabelle wie die Goldkiste (gleiche Referenz, keine Kopie).
- [x] [Lune] Alle IDs sind pro Tabelle eindeutig (Seltenheiten, Werkzeuge, Sandsorten, Zonen, Kisten, Gem-Pakete, Produkte, Knoten).
- [x] [Lune] Werkzeugstufen: Sand pro Sekunde und Preis steigen streng mit der Stufe, die Hand kostet 0, und jede Stufe verweist auf einen Knoten in `UpgradeTree`.
- [x] [Lune] Jede Zone verweist auf eine existierende Sandsorte. Ihre Freischaltung ist "Start" oder eine Knoten-ID, die in `UpgradeTree` existiert, nie eine feste Zahl.
- [x] [Lune] Gem-Pakete: Der aus Gems und Robux berechnete Bonus gegenüber dem kleinsten Paket entspricht der Konzeptspalte auf 1 Prozentpunkt genau. Gems und Robux steigen.
- [x] [Lune] Jede Kiste hat einen Preis über 0 und die Währung `coins` oder `gems`. Die Pity der Goldkiste liegt bei 15 (Episch oder besser) und 60 (Legendär oder besser), das 10er-Paket gibt 11.
- [x] [Lune] Alle Datenmodule laden unter Lune ohne Roblox-API. Farben sind Hex-Text.
- [ ] [Studio] Beim Playtest prüft der Server die Tabellen beim Start und meldet keine Fehler im Output.

## 0.2 Projekt-Setup

- [x] [Lune] `lune run tests/run` findet alle `*.spec.luau`, führt sie aus und endet bei Erfolg mit Code 0, bei einem fehlschlagenden Test mit Code ungleich 0.
- [x] [Lune] Ein Beispieltest lädt ein Modul aus `src/shared` per Pfad-`require` und läuft.
- [x] [Shell] `rojo build -o build/test.rbxl` baut ohne Fehler.
- [x] [Shell] Nach `rojo build` und einem Testlauf zeigt `git status` keine neuen Dateien (die `.gitignore` greift).
- [ ] [Studio] Nach `rojo serve` und Verbinden liegen Shared, Server und Client an den richtigen Orten. Eine gespeicherte Änderung erscheint sofort in Studio.
- [ ] [Studio] Beim Playtest drucken Server und Client je eine Zeile, und der Pfad-`require` funktioniert auch in Studio.

## 0.3 Architektur

- [x] [Lune] Ein Spieler ohne Daten bekommt ein Standardprofil mit der aktuellen Version.
- [x] [Lune] Ein Profil der Version 1 wird mit einer Beispielmigration schrittweise auf Version 2 gebracht. Vorhandene Werte bleiben erhalten, fehlende Felder bekommen Standardwerte.
- [x] [Lune] Eine zweite Migration desselben Profils ändert nichts mehr.
- [x] [Lune] Ein Profil mit höherer Version, als der Server kennt, wird nicht migriert und als "nicht speichern" markiert.
- [x] [Lune] Unbekannte Knoten-IDs im Profil bleiben gespeichert und lassen das Laden nicht scheitern.
- [x] [Lune] Validierung: Falscher Typ, zu wenige oder zu viele Argumente, NaN, Unendlich, zu lange Texte, unbekannte IDs und Werte außerhalb des Bereichs werden abgelehnt. Gültige Argumente gehen durch.
- [x] [Lune] Rate-Limit mit simulierter Uhr: N Aufrufe pro Sekunde gehen durch, der nächste wird abgelehnt, nach Ablauf geht es wieder. Spieler und Remotes zählen getrennt.
- [x] [Lune] Eine Remote ohne Schema oder ohne Rate-Limit in `RemoteSpec` lässt sich nicht registrieren.
- [ ] [Studio] Beim Playtest starten alle 8 leeren Services in fester Reihenfolge (erst Init, dann Start), ohne Fehler im Output.
- [ ] [Studio] Die Remotes liegen unter ReplicatedStorage. Ein Aufruf mit falschem Typ aus der Client-Konsole wird abgelehnt und im Server-Output als Verstoß gezählt, ohne Fehler.

## Pflicht für alle Pakete mit Käufen und Kisten (4.1, 4.2, 4.4, 4.5, 5.5)

- [ ] [Lune] Dieselbe PurchaseId zweimal: Die Gutschrift erfolgt nur einmal, der zweite Aufruf liefert PurchaseGranted ohne neue Gutschrift.
- [ ] [Lune] Profil nicht geladen: Ergebnis ist NotProcessedYet, und es gibt keine Gutschrift. Speichern schlägt fehl: NotProcessedYet, Gutschrift und PurchaseId bleiben gemeinsam im Profil, der nächste Versuch bucht nicht erneut.
- [ ] [Lune] Der Pity-Zähler übersteht Speichern und Laden (Neustart) unverändert.
- [ ] [Lune] Quoten-Simulation mit sehr vielen Öffnungen pro Kiste: Die Abweichung von der Quotentabelle bleibt klein. Anzeige und Auswurf lesen dieselbe Tabelle.
- [ ] [Lune] Im 10er-Paket zählt jede der 11 Öffnungen für Pity.
- [ ] [Lune] Bei `ArePaidRandomItemsRestricted = true` lehnt der Server jede Kisten-Interaktion ab.
- [ ] [Studio] Testkauf in Studio: Die Gutschrift erscheint genau einmal und bleibt nach dem Rejoin erhalten.

## 1.1 Spielerdaten laden und speichern

Die Ladelogik steht in einem reinen Modul (`src/shared/Logic/PlayerSession.luau`), das den Speicher über einen Adapter bekommt. Lune testet es mit einem Fake-Speicher, im Spiel steckt ProfileStore dahinter.

- [x] [Lune] Neuer Spieler: Es entsteht ein Standardprofil mit aktueller Version, der Spieler gilt erst danach als geladen.
- [x] [Lune] Vorhandenes Profil: Münzen, Gems, Inventar, Knoten und Zonen kommen nach Speichern und erneutem Laden (Neustart) unverändert zurück, Münzen als Zahlentyp `{m, e}`.
- [x] [Lune] Altes Profil (Version 1) mit Beispielmigration wird beim Laden migriert, und die neue Version wird gespeichert.
- [x] [Lune] Profil mit höherer Version: Der Spieler wird mit einer Meldung entfernt, und der Speicher schreibt keine geänderten Daten zurück.
- [x] [Lune] Laden schlägt fehl oder der Speicher liefert nichts: Der Spieler wird mit einer Meldung entfernt, es entsteht kein leeres Profil, das alte Daten überschreiben könnte.
- [x] [Lune] Der Spieler verlässt das Spiel während des Ladens: Die Sitzung wird beendet, es bleibt kein Profil im Speicher und keine Sitzung offen.
- [x] [Lune] Schneller Rejoin, während das alte Laden noch läuft: Der neue Ladevorgang wartet, bis der alte abgebrochen ist, und lädt dann normal.
- [x] [Lune] Vor jedem Speichern werden NaN, unendlich und nicht speicherbare Werte aus dem Profil entfernt oder auf Standard gesetzt.
- [x] [Lune] Server-Wechsel: Solange Server A die Sitzung hält, wartet Server B. Nach dem Verlassen auf A gibt A die Sitzung frei, und B lädt den zuletzt gespeicherten Stand.
- [x] [Lune] Kaputtes Feld (zum Beispiel Münzen als Text oder Gems als NaN): Nur dieses Feld wird auf den Standardwert gesetzt und eine Warnung ausgegeben, der Rest bleibt.
- [x] [Lune] Beim Speichern und Verlassen wird `lastSeen` auf die aktuelle Zeit gesetzt (Grundlage für den Offline-Ertrag in 5.3).
- [x] [Lune] Vor dem Laden und nach dem Verlassen lehnt die Profil-Prüfung von `Net` jeden Remote-Aufruf ab, danach lässt sie ihn durch.
- [x] [Shell] `rojo build` baut mit ProfileStore aus Wally ohne Fehler.
- [ ] [Studio] Mit API-Zugriff (Studio nutzt den eigenen Store `PlayerData_Studio_v1`): Münzen per Studio-Befehlszeile ändern, Playtest beenden, neu starten: Der Wert ist noch da.
- [ ] [Studio] Ohne API-Zugriff läuft der Playtest mit einem Test-Speicher (Mock) und warnt im Output, dass nichts dauerhaft gespeichert wird.
- [ ] [Studio] Veröffentlichtes Spiel, zwei Server: Wert auf Server A ändern, auf Server B wechseln, der Wert ist da.

## 1.2 Sammeln, Tank, Verkaufen

Die Regeln stehen im reinen Modul `src/shared/Logic/Collecting.luau` (Lune-Tests mit simulierter Uhr), der Service `Sand` schließt nur Remotes, Uhr und Händlerstand an. Werte kommen aus `Tools`, `Zones`, `SandTypes`, `Economy` und `World`.

- [x] [Lune] Der Server berechnet den Sand aus Zeit und Rate: Hand 3 s halten ergibt 3 Sand, mit gekauftem `collect_tool_2` (Schaufel) 5 Sand pro Sekunde.
- [x] [Lune] Ein Client, der große Mengen meldet, hat keine Wirkung: `SetCollecting` nimmt nur einen Wahrheitswert, eine Zahl wie 1e9 oder ein zweites Argument wird abgelehnt, und die Sammel-Logik hat keinen Mengen-Parameter.
- [x] [Lune] Ohne Halten entsteht kein Sand. Nach dem Loslassen zählt die Zeit nicht mehr, nach erneutem Halten zählt sie wieder.
- [x] [Lune] Bruchteile gehen nicht verloren: zweimal 0,5 s mit der Hand ergeben 1 Sand, der Tank enthält immer ganze Körner.
- [x] [Lune] Ein voller Tank stoppt das Sammeln: Bei 15 Sand Kapazität ergeben 100 s Halten genau 15, weitere Zeit fügt nichts hinzu, und das Ergebnis meldet "voll".
- [x] [Lune] Halten ohne Auffrischung: Schickt der Client länger als `holdTimeoutSeconds` kein `SetCollecting(true)`, zählt nur die Zeit bis zur Frist.
- [x] [Lune] Eine Uhr, die rückwärts springt, erzeugt keinen und keinen negativen Sand.
- [x] [Lune] Werkzeug: Es zählt das höchste gekaufte Werkzeug-Knoten-Werkzeug, unbekannte Knoten-IDs im Profil werden ignoriert.
- [x] [Lune] Verkaufen leert den Tank und bucht Münzen nach Sandsorte der Zone: 10 Sand im Dünenmeer geben 10 Münzen, in der Oase 30. Ein leerer Tank bucht nichts.
- [x] [Lune] Verkaufen addiert über den Zahlentyp: 10 Sand auf 1,5e20 Münzen ergibt 1,5e20 + 10 ohne Fehler, auch große Tankwerte.
- [x] [Lune] Verkaufen nur in Reichweite des Händlerstands (`World.sellStand.rangeStuds`), außerhalb wird abgelehnt.
- [x] [Lune] Eine ungültige Zone im Profil fällt auf das Dünenmeer zurück statt einen Fehler zu werfen.
- [x] [Lune] BigNum: `add`, `sub`, `mulNumber`, `compare`, `floor` und `toNumber` stimmen für kleine Werte und für Werte über 10^15.
- [x] [Shell] `rojo build` baut ohne Fehler.
- [ ] [Studio] Halten (linke Maustaste, Gamepad R2 oder Bildschirmknopf "Graben" am Handy) sammelt, Loslassen stoppt, der Tankzähler steigt bis zur Kapazität.
- [ ] [Studio] Am Händlerstand (Prompt "Verkaufen", Taste E) wird der Tank leer und die Münzen steigen um Sand mal Preisfaktor. Weit weg vom Stand passiert nichts.
- [ ] [Studio] Direkt am Händlerstand und mit totem Charakter wird nicht gesammelt.
- [ ] [Studio] Nach Rejoin sind Münzen und Tankinhalt noch da.

## 1.3 Zahlentyp und Anzeige

Rechnen und Vergleichen stehen seit 1.2 in `src/shared/Logic/BigNum.luau`, Paket 1.3 ergänzt `BigNum.format` und die Grenztests in `tests/bignum.spec.luau`. Das HUD ruft nur noch `BigNum.format` auf. Entscheidungen: ein Nachkommastelle als Standard, Nullen am Ende entfallen (`1K`, `1,5K`), deutsches Komma, Suffixe K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc, ab 10^36 wissenschaftlich mit bis zu 2 Nachkommastellen (`1,23e36`).

- [x] [Lune] Addieren, Multiplizieren, Dividieren und Vergleichen stimmen unterhalb und oberhalb von 10^15 gegen feste Referenzwerte (zum Beispiel 9,5e14 + 9,5e14 = 1,9e15, 1e20 * 1e20 = 1e40, 6e30 / 2e10 = 3e20). Ein winziger Summand neben einem riesigen ändert den Wert nicht. Subtrahieren bis genau 0 ergibt die Null.
- [x] [Lune] Vergleichen und Ordnen über große Exponenten: 1e15 < 1,0000001e15, 9,99e308 und mehr bleiben vergleichbar (kein Überlauf), negative Werte ordnen sich richtig.
- [x] [Lune] Anzeige unter 1000: ganze Zahlen ohne Suffix (`0`, `7`, `999`), Brüche mit Komma (`2,5`), Nullen am Ende entfallen.
- [x] [Lune] Anzeige je Suffix: `1K`, `1,5K`, `12,3K`, `999K`, `1M`, `1,2B`, `4,56T`, bis `Dc` (zum Beispiel `1,2Dc` bei 1,2e33, `999Dc` bei 9,99e35 gerundet).
- [x] [Lune] Rundung an den Grenzen springt nicht falsch: 999,9K bleibt `999,9K`, 999.950 wird `1M` (nicht `1000K`), 999,96e6 wird `1B`, 999,96e33 wird `1e36`. Das gilt in jeder Stufe bis `Dc`. Halbe Werte runden auf (1,25K mit 1 Stelle ergibt `1,3K`, 1,15K ergibt `1,2K`).
- [x] [Lune] Wissenschaftlich ab 10^36: `1e36`, `1,23e36`, `9,99e99`, `1,5e308`, und 9,996e40 rundet auf `1e41`.
- [x] [Lune] Negative Werte: `-1,5K`, `-999`. Null und `{m=0, e=0}` ergeben `0`, auch nach Subtraktion gleicher Werte.
- [x] [Lune] Die Stellenzahl lässt sich angeben (`decimals` 0 bis 4, andere Werte werden begrenzt): 1234 mit 0 Stellen ergibt `1K`, mit 2 Stellen `1,23K`.
- [x] [Lune] Ungültige Eingaben stürzen nicht ab: ein Wert mit NaN oder unendlicher Mantisse ergibt `0` bei `deserialize`, und `format` erwartet nur gültige BigNum-Werte.
- [x] [Lune] Speichern und Laden verändert den Wert nicht: `deserialize(serialize(x))` ist für kleine, große (1e15, 1,234e40) und negative Werte identisch, und die Anzeige bleibt gleich. Ungültige gespeicherte Werte (Text, NaN, unendlich, fehlende Felder) werden zur Null.
- [x] [Lune] Eine Zahl wie 1e15 hat durch Rechnen keine Rauschstellen (`0,1 + 0,2` als BigNum ergibt `0,3` mit `format`).
- [x] [Shell] `rojo build` baut ohne Fehler, und `lune run tests/run` läuft komplett durch.
- [ ] [Studio] Im Playtest zeigt das HUD Münzen und Tank mit Suffixen (zum Beispiel `1,5K`), der Verkaufs-Hinweis (`+12,3K Münzen`) stimmt, und per Studio-Befehlszeile gesetzte Münzen von 1e40 erscheinen als `1e40`.
- [ ] [Studio] Der Text des Tankbalkens passt auch bei `999,9K / 1M` ins Feld (kein Abschneiden am Handy-Bildschirm).

## 1.4 Terrain-Verformung auf dem Client

Die Regeln stehen in zwei reinen Modulen: `src/shared/Logic/SandDig.luau` (welche Terrain-Blöcke ein Loch berührt, Aushöhlen auf Voxel-Rastern, Tiefengrenze, Nachwachsen mit Zeitplan und Budget) und `src/shared/Logic/PerfGuard.luau` (Bildrate beobachten, auf die Rückfallvariante wechseln). Alle Zahlen stehen in `src/shared/Data/Terrain.luau`. Der Client-Controller `Dig` liest und schreibt nur Voxel und zeigt Partikel, der Server zählt Sand wie bisher unabhängig davon. Terrain wird in Blöcken von 16 Studs verwaltet: Vor dem ersten Graben merkt sich der Client den Originalzustand des Blocks, beim Nachwachsen blendet er schrittweise dorthin zurück.

- [x] [Lune] Blöcke eines Lochs: Eine Kugel liefert genau die Blöcke, die sie schneidet, am Raster ausgerichtet, auch über Blockgrenzen und bei negativen Koordinaten.
- [x] [Lune] Aushöhlen: Voxel in der Kugel verlieren Füllung, Voxel außerhalb bleiben unverändert, Füllung wird nie negativ, ein leerer Voxel wird zu Luft.
- [x] [Lune] Tiefengrenze: Wiederholtes Graben an derselben Stelle wird tiefer, aber nie tiefer als `maxDepthStuds` unter der zuerst gemessenen Oberfläche. Liegt der Treffer schon an der Grenze, gibt es kein neues Loch ("zu tief").
- [x] [Lune] Graben-Takt: Ein zweites Loch innerhalb von `digIntervalSeconds` wird abgelehnt, danach geht es wieder.
- [x] [Lune] Lochgröße folgt dem Werkzeug aus den Daten (Hand klein, Großmaschine groß), ein unbekanntes Werkzeug bekommt die Größe der Hand.
- [x] [Lune] Nachwachsen: Vor `regrowDelaySeconds` wächst nichts nach. Danach kehrt der Block in `regrowSteps` Schritten über `regrowSeconds` genau zum Originalzustand zurück (Füllung und Material), dann wird er vergessen.
- [x] [Lune] Erneutes Graben in einem nachwachsenden Block setzt dessen Zeitplan zurück.
- [x] [Lune] Budget: Pro Bildaufruf schreibt der Client höchstens `maxWritesPerUpdate` Blöcke, der Rest folgt in späteren Aufrufen.
- [x] [Lune] Ein Block unter dem eigenen Charakter (Abstand kleiner als `regrowBlockRadiusStuds`) wächst erst nach, wenn der Spieler weggeht.
- [x] [Lune] Lange Sitzung mit simulierter Uhr (2 Stunden Dauergraben an zufälligen Stellen): Es sind nie mehr als `maxDirtyChunks` Blöcke offen, und nach dem Aufhören ist nach Verzögerung plus Nachwachszeit kein Block mehr offen.
- [x] [Lune] Bildraten-Wächter: In der Aufwärmzeit wird nichts entschieden. Ein kurzer Einbruch wechselt nicht. Liegt der Schnitt `downAfterSeconds` lang unter `lowFps`, wird auf "fallback" gewechselt, über `highFps` für `upAfterSeconds` zurück. Nach `maxSwitches` Wechseln bleibt es bei "fallback". Ein erzwungener Modus gilt immer.
- [x] [Lune] `DataCheck` prüft `Terrain`: Blockgröße ein Vielfaches von 4, jede Werkzeugstufe hat eine Lochgröße, Zeiten und Budgets größer als 0, `highFps` über `lowFps`, Material als Text. Eine kaputte Fassung schlägt fehl.
- [x] [Shell] `rojo build` baut ohne Fehler, `lune run tests/run` läuft komplett durch.
- [ ] [Studio] Ohne eigenes Sandterrain legt der Server ein Platzhalter-Sandfeld vor dem Spawn an (Warnung im Output). Halten auf Sand gräbt sichtbare Mulden vor dem Charakter, mit Sandpartikeln.
- [ ] [Studio] Löcher erscheinen nur beim eigenen Spieler. Ein zweiter Spieler im selben Server (Test mit 2 Spielern) sieht sie nicht.
- [ ] [Studio] Der Sand wächst nach etwa `regrowDelaySeconds` sanft nach. Man bleibt nicht im nachwachsenden Sand stecken.
- [ ] [Studio] Lange Sitzung (10 Minuten Dauergraben): Die Fläche bleibt stabil, keine bleibenden Löcher, keine Ruckler.
- [ ] [Studio] Rückfallvariante zum Ausprobieren: In der Client-Befehlszeile `game.Players.LocalPlayer:SetAttribute("DigMode", "fallback")`. Dann sinkt eine Sandscheibe ein, und Partikel fliegen, das Terrain bleibt unverändert. `"full"` schaltet zurück, `nil` gibt die Wahl an den Wächter.
- [ ] [Studio] Auf einem schwachen Handy (veröffentlichtes Spiel, Anzeige oben links mit FPS und Modus) bleibt die Bildrate flüssig. Fällt sie darunter, schaltet der Wächter auf die Rückfallvariante.

## 1.6 Die ersten 2 Minuten

Entscheidung von Waltuh (17.11.2026): 1.6 bringt einen Mini-Kauf mit. Neue Knoten in `UpgradeTree`: `collect_rate_1` (15 Münzen, +50 % Sammelrate), `tank_1` (20, Tank 30), `tank_2` (60, Tank 60), `tank_3` (250, Tank 150), `collect_rate_2` (120, +25 %, nach der Schaufel), dazu die vorhandene Schaufel `collect_tool_2` (50). Werte aus `docs/balance/phase0_startwerte.md`. Der Kauf steht im reinen Modul `src/shared/Logic/TreePurchase.luau`, der Service `Upgrades` schließt `PurchaseNode` an. Paket 2.1 baut darauf auf (ganzer Baum), 2.2 ersetzt die schlichte Upgrade-Liste durch den Baum. Das Tutorial steht in `src/shared/Data/Tutorial.luau` (Schritte und Texte) und `src/shared/Logic/Tutorial.luau` (Fortschritt), der Server entscheidet den Schritt und speichert ihn im Profil (`tutorial.step`).

- [x] [Lune] Kauf ohne Voraussetzung wird abgelehnt (`tank_2` ohne `tank_1`, `collect_rate_2` ohne Schaufel), Münzen bleiben gleich.
- [x] [Lune] Zwei schnelle Käufe desselben Knotens: Nur der erste bucht ab, der zweite meldet "schon gekauft".
- [x] [Lune] Zu wenig Münzen wird abgelehnt, Münzen bleiben gleich. Genau passende Münzen gehen auf 0.
- [x] [Lune] Unbekannte Knoten und vergebene Knoten (`sandstorm_1`) lassen sich nicht kaufen.
- [x] [Lune] Große Münzwerte (1e20) kaufen ohne Fehler über den Zahlentyp.
- [x] [Lune] Wirkung: `collect_rate_1` macht aus 1 Sand/s mit der Hand 1,5, mit Schaufel 7,5. `tank_1` gibt 30, `tank_2` 60, der höchste Tank-Knoten zählt, der Gamepass-Faktor kommt danach. Unbekannte oder entfernte Knoten im Profil ändern nichts.
- [x] [Lune] Tutorial: Ein neuer Spieler startet bei Schritt 1. 15 Sand im Tank (auch bei größerem Tank) führen zu Schritt 2, der erste Verkauf zu Schritt 3, `collect_rate_1` zu Schritt 4, die Schaufel beendet das Tutorial. Schritte gehen nie zurück.
- [x] [Lune] Tutorial beim Laden: Wer schon weiter ist (zum Beispiel die Schaufel besitzt), überspringt die erledigten Schritte. Ein kaputter Schritt im Profil fällt auf einen gültigen Wert zurück.
- [x] [Lune] Zeit-Simulation mit den echten Regeln (Sammeln, 5 s Weg je Richtung, Verkaufen, billigsten verfügbaren Knoten kaufen): Das erste Upgrade ist nach etwa 20 s gekauft, die Schaufel nach etwa 2 Minuten (je ±15 %), wie `Economy.targetSeconds`.
- [x] [Lune] `DataCheck` prüft die neuen Knoten (Name, bekannte Wirkung, Tank-Knoten steigen entlang der Kette) und die Tutorial-Schritte (bekannte Bedingung, existierende Knoten, bekanntes Ziel). Eine kaputte Fassung schlägt fehl.
- [x] [Shell] `rojo build` baut ohne Fehler, `lune run tests/run` läuft komplett durch.
- [ ] [Studio] Neuer Spieler (Profil leeren oder Studio-Speicher neu): Oben steht Schritt 1, ein Strahl und eine Markierung zeigen aufs Sandfeld. Nach dem Füllen zeigt der Strahl zum Händlerstand, nach dem Verkauf leuchtet in der Upgrade-Liste der erste Knoten.
- [ ] [Studio] Upgrade-Liste rechts: Zeigt die kaufbaren Knoten mit Preis. Zu teuer ist ausgegraut, ein Klick darauf meldet "Zu wenig Münzen". Ein Kauf wirkt sofort (Rate oder Tank im HUD).
- [ ] [Studio] Nach der Schaufel verschwindet das Tutorial. Nach einem Rejoin bleibt der Schritt erhalten.
- [ ] [Studio] Fremde Testspieler finden die Schleife ohne Erklärung (Fertig, wenn). Stoppuhr: erstes Upgrade nach etwa 20 s, Schaufel nach etwa 2 Minuten.

## 2.1 Skilltree-Daten und Kauf-Server

Paket 2.1 füllt den ganzen Baum für den ersten Lauf (Hand bis Großmaschine) mit den Ästen Sammeln (Rate), Tank (Kapazität), Verkauf (Preisfaktor) und Glück (Fundchance). Zahlen von `balance-analyst` in `docs/balance/skilltree_2_1.md`. Verkauf und Glück erscheinen erst nach der Schaufel, damit die ersten 2 Minuten gleich bleiben. Neue Wirkungen `sellBonus` und `luckBonus` (Hundertstel-Prozent, Boni addieren sich). Die Wirkung aller Knoten berechnet das reine Modul `src/shared/Logic/TreeEffects.luau` bei jedem Aufruf aus den gekauften IDs und der aktuellen Tabelle, gespeichert werden nur die IDs. `TreePurchase` (aus 1.6) kauft weiter und liefert neu den Zustand jedes Knotens (`owned`, `available`, `fog`) für den Baum in 2.2. Der Fundchancen-Faktor wirkt ab Paket 2.6. Tests in `tests/skilltree.spec.luau`. Ergebnis der Simulation: Eimerkette 7:10, Mini-Bagger 10:10, Saugroboter 11:32, Großmaschine 12:34, längste Pause 75 s. Entscheidung von Waltuh (18.11.2026): keine Sperren über Raten-Knoten vor den späten Werkzeugen, Paket 6.4 hebt stattdessen die Werkzeugpreise an.

- [x] [Lune] Ein Kauf ohne Voraussetzung wird abgelehnt, für jeden Knoten des Baums mit Voraussetzung. Münzen und Knoten bleiben gleich.
- [x] [Lune] Ein Doppelklick (zwei schnelle `PurchaseNode(id)`) kauft nicht zweimal, für jeden kaufbaren Knoten: Der zweite Aufruf meldet "schon gekauft" und bucht nichts ab.
- [x] [Lune] Zu wenig Geld wird abgelehnt (Preis minus 1), für jeden kaufbaren Knoten. Genau der Preis geht auf 0. [Studio] Der Client zeigt den Fehler.
- [x] [Lune] Laden: Knoten kaufen, Sitzung beenden, auf einem neuen Server laden (Fake-Speicher). Knoten, Münzen und alle Wirkungen (Werkzeug, Rate, Tank, Preis, Glück) sind gleich. [Studio] Der Spielstand lädt nach einem Neustart korrekt.
- [x] [Lune] Baum-Update, Knoten entfernt: Das Profil lädt, die ID bleibt gespeichert, wirkt aber nicht, es gibt keine Erstattung, und Folgekäufe gehen weiter.
- [x] [Lune] Baum-Update, Knoten hinzugefügt: Ein altes Profil (nur Knoten aus 1.6) lädt, und der neue Knoten ist kaufbar, sobald seine Voraussetzungen erfüllt sind.
- [x] [Lune] Baum-Update, neue Voraussetzung vor einem gekauften Knoten: Der gekaufte Knoten wirkt weiter, die neue Voraussetzung ist kaufbar.
- [x] [Lune] Baum-Update, geänderte Werte: Die Wirkung folgt der neuen Tabelle, eine Preisänderung bucht nichts nach.
- [x] [Lune] Wirkung: Verkauf-Knoten erhöhen die Münzen pro Sand (Boni addieren sich, Bruchteile beim Verkauf verfallen), Glück-Knoten den Fundchancen-Faktor. Rate und Tank wie in 1.6. Unbekannte Knoten-IDs ändern nichts.
- [x] [Lune] Sichtbarkeit: Am Anfang sind nur Knoten ohne Voraussetzung kaufbar, alle anderen im Nebel. Nach einem Kauf werden die Folgeknoten kaufbar. Der Sandsturm-Knoten ist nie kaufbar.
- [x] [Lune] Jeder kaufbare Knoten ist erreichbar: Ein Käufer mit unbegrenzt Münzen kauft nacheinander den ganzen Baum (ohne Knoten hinter `sandstorm_1`).
- [x] [Lune] Zeit-Simulation des ganzen Laufs mit den echten Regeln (Sammeln, 5 s Weg je Richtung, beste Zone, billigsten sichtbaren Knoten kaufen): erstes Upgrade nach etwa 20 s und Schaufel nach etwa 2 Minuten wie in 1.6, die Werkzeuge kommen zu den Zeiten aus `docs/balance/skilltree_2_1.md` (je ±15 %), und keine Pause zwischen zwei Käufen ist länger als die dort genannte Grenze.
- [x] [Lune] `DataCheck`: Jede Wirkung steht in ihrem Ast, `sellBonus` und `luckBonus` brauchen bp über 0, Meilensteine sind ganze Zahlen. Eine kaputte Fassung schlägt fehl.
- [x] [Shell] `rojo build` baut ohne Fehler, `lune run tests/run` läuft komplett durch.
- [ ] [Studio] Upgrade-Liste nach der Schaufel: Verkauf- und Glück-Knoten erscheinen. Ein Verkauf-Knoten erhöht sofort die Münzen beim nächsten Verkauf.
- [ ] [Studio] Ein Klick auf einen zu teuren Knoten zeigt "Zu wenig Münzen". Nach einem Rejoin sind alle gekauften Knoten und ihre Wirkung noch da.

## 2.2 Tree-UI mit Zoom, Zuständen, Linien, Nebel

Paket 2.2 ersetzt die Upgrade-Liste aus 1.6 durch den Skilltree als Vollbild-Ebene (Knopf "Baum" am HUD mit Zähler für bezahlbare Knoten, ab Tutorial-Schritt 3). Die Koordinaten rechnet das reine Modul `src/shared/Logic/TreeLayout.luau` aus `UpgradeTree`: Spalte aus dem Ast (`src/shared/Data/TreeLayout.luau`, Glück, Tank, Werkzeuge in der Mitte, Rate, Verkauf), ein Band pro Werkzeug, Reihe über der Voraussetzung in derselben Spalte, optional festgenagelt per `pos`. `src/shared/Logic/TreeView.luau` liefert den Zustand je Knoten (gekauft, kaufbar, zu teuer, Silhouette, verborgen) und je Linie, den Zähler und den Fokus-Knoten. `src/shared/Logic/TreeCamera.luau` rechnet Zoom, Verschieben, Tippen oder Ziehen. Linien nur senkrecht innerhalb einer Spalte (keine gedrehten Rahmen), Werkzeug-Sperren aus anderen Ästen erscheinen als Bandlinie und "Braucht" auf der Karte. Gekauft wird nur über den Knopf auf der Karte. Keine neue Remote, kein neues Profilfeld. Freischalt-Animation und Sound kommen in 2.3. Entscheidung von Waltuh (18.11.2026): keine Schnellkauf-Leiste neben dem Baum, der Zähler am Knopf genügt. Die Upgrade-Liste aus 1.6 fällt weg, die Studio-Punkte zur Liste in 1.6 gelten damit für den Baum (siehe unten). Das Tutorial-Ziel `list` heißt jetzt `tree`.

- [x] [Lune] Layout: Jeder Knoten bekommt genau eine Position, keine zwei Knoten teilen eine Zelle.
- [x] [Lune] Layout: Ein Knoten liegt immer höher als seine Voraussetzungen in derselben Spalte.
- [x] [Lune] Layout: Werkzeuge stehen in der Mitte, Tank und Glück links, Rate und Verkauf rechts.
- [x] [Lune] Layout: Ein Knoten, der ein Werkzeug verlangt (direkt oder über seine Voraussetzungen), liegt im Band dieses Werkzeugs oder darüber.
- [x] [Lune] Layout: Gleiche Daten ergeben immer dieselben Koordinaten.
- [x] [Lune] Layout bei Baum-Update: Ein neuer Knoten am Ende eines Asts bekommt einen freien Platz, Knoten früherer Bänder verschieben sich nicht. Ein Knoten mit `pos` behält seinen Platz.
- [x] [Lune] Layout: Die Fläche umschließt alle Knoten mit Rand.
- [x] [Lune] Ansicht: Neuer Spieler mit 0 Münzen: `collect_rate_1`, `tank_1` und Schaufel sind "zu teuer", ihre Nachfolger Silhouetten, alles andere verborgen, `sandstorm_1` verborgen.
- [x] [Lune] Ansicht: Mit genug Münzen wird ein Knoten "kaufbar", auch bei sehr großen Werten (1e20) über den Zahlentyp.
- [x] [Lune] Ansicht: Nach einem Kauf ist der Knoten "gekauft", seine Nachfolger werden kaufbar oder zu teuer, die Reihe dahinter wird Silhouette.
- [x] [Lune] Ansicht: Silhouetten liefern keinen Namen und keinen Preis.
- [x] [Lune] Ansicht: Linien gekauft zu gekauft hell, gekauft zu kaufbar gedämpft, zu Silhouetten gestrichelt, zu Verborgenem keine. Werkzeug-Sperren aus anderen Ästen erscheinen als "Braucht", nicht als Linie.
- [x] [Lune] Ansicht: Der Zähler am Knopf ist die Zahl der kaufbaren und bezahlbaren Knoten.
- [x] [Lune] Ansicht: Fokus beim Öffnen ist der Tutorial-Knoten, sonst der billigste bezahlbare, sonst der billigste kaufbare, sonst der Start.
- [x] [Lune] Ansicht: Unbekannte oder entfernte IDs im Profil werden nicht gezeichnet und ändern nichts.
- [x] [Lune] Kamera: Der Zoom bleibt zwischen den Grenzen aus `Data/TreeLayout`, auch bei extremen Pinch-Werten.
- [x] [Lune] Kamera: Pinch und Mausrad zoomen um den Fingermittelpunkt bzw. Mauszeiger, der Punkt darunter bleibt stehen.
- [x] [Lune] Kamera: Verschieben stoppt am Rand, ein Baum kleiner als das Bild steht mittig.
- [x] [Lune] Kamera: Unter 10 px Bewegung ist Tippen, darüber Ziehen, und Ziehen öffnet keine Karte.
- [x] [Lune] Kamera: Zentrieren setzt einen Knoten in die Bildmitte, soweit der Rand es erlaubt.
- [x] [Lune] Kamera: Knotengröße mal kleinster Zoom ist mindestens 44 px (Tippziel am Handy).
- [x] [Lune] `DataCheck` prüft `TreeLayout` (jeder Ast hat eine eindeutige Spalte, gültige Zoomgrenzen) und `pos` (ganze Zahlen, keine Kollision). Eine kaputte Fassung schlägt fehl.
- [x] [Shell] `rojo build` baut ohne Fehler, `lune run tests/run` läuft komplett durch.
- [ ] [Studio] Knopf "Baum" erscheint ab Tutorial-Schritt 3 mit Zähler. Öffnen und Schließen per Knopf, X und Escape.
- [ ] [Studio] Der Baum zeigt alle Zustände, Silhouetten gestrichelt, Nebel über dem sichtbaren Teil.
- [ ] [Studio] Tippen öffnet die Karte, Kaufen wirkt sofort (HUD), Nachfolger tauchen auf. Zu wenig Münzen zeigt die Meldung.
- [ ] [Studio] Tutorial Schritt 3: Der Knopf pulsiert, `collect_rate_1` leuchtet und steht beim Öffnen in der Mitte.
- [ ] [Studio] Geräte-Simulator (kleines Android quer, iPhone SE): Pinch, Ziehen und Tippen gehen, Ziehen kauft nie, nichts liegt unter dem Roblox-Menü oder der Notch.
- [ ] [Studio] Echtes schwaches Handy: Öffnen ohne Ruckler, Ziehen flüssig (Fertig, wenn).
- [ ] [Studio] Nach einem Rejoin zeigt der Baum alle gekauften Knoten.

## 2.3 Freischalt-Animation und Sound

Paket 2.3 spielt die Freischalt-Sequenz im Baum ab (Konzept: etwa 1,2 Sekunden). Ausgelöst wird sie durch den Vergleich zweier `StateSync`-Zustände (neu in `nodes`), der erste Zustand nach dem Beitreten zählt nie als Kauf. Varianten: normal (1,2 s: Eindrücken, Ring, Lichtimpuls über die Linien zu den Folgeknoten, neue Knoten blenden aus dem Nebel ein, Kamera gleitet), Meilenstein (1,6 s, Knoten mit `milestone`, dazu ein Aufhell-Puls) und kurz (0,5 s, ab dem elften Kauf einer Sitzung). Berechnung im reinen Modul `src/shared/Logic/UnlockSequence.luau`, Zahlen in `src/shared/Data/UnlockAnimation.luau`, Töne als Platzhalter in `src/shared/Data/TreeSounds.luau` (leere IDs bis Paket 3.5). Der Controller `SkillTree` spielt den Plan mit Tweens ab. Keine neue Remote, kein neues Profilfeld.

- [x] [Lune] Der Vergleich findet neu gekaufte Knoten, ignoriert den ersten Zustand (kein Vorgänger), unveränderte Zustände und entfernte Knoten.
- [x] [Lune] Variante: Der erste Kauf ist normal, ein Knoten mit `milestone` immer Meilenstein, ab dem elften Kauf einer Sitzung kurz.
- [x] [Lune] Neu sichtbare Knoten stimmen (nach `tank_1` wird `tank_2` kaufbar und `tank_3` Silhouette), ohne Doppelte.
- [x] [Lune] Impulskanten laufen nur vom gekauften Knoten zu Folgeknoten in derselben Spalte, Folgeknoten anderer Spalten bekommen einen Glanzring.
- [x] [Lune] Zeitleiste: Reihenfolge Eindrücken, Ring, Impuls, Einblenden, Kamera. Gesamtdauer normal 1,2 s, kurz höchstens 0,6 s, Meilenstein 1,6 s (je plus/minus 0,05 s).
- [x] [Lune] Kamerapunkte enthalten den gekauften Knoten und alle neu sichtbaren Knoten.
- [x] [Lune] Cues passen zur Variante (Meilenstein spielt `milestone`, die kurze Variante nur `press` und `reveal`).
- [x] [Lune] `DataCheck` lehnt kaputte Zeiten, zu lange Dauern und ungültige Sound-IDs ab, leere IDs sind erlaubt.
- [x] [Shell] `rojo build` baut ohne Fehler, `lune run tests/run` läuft komplett durch.
- [ ] [Studio] Kauf im Baum: Eindrücken, Ring, Impuls zu den Folgeknoten, neue Knoten blenden ein, Kamera gleitet. Die Dauer fühlt sich nach etwa 1,2 s an.
- [ ] [Studio] Eimerkette kaufen: Meilenstein-Variante mit Aufhell-Puls.
- [ ] [Studio] Zehn Käufe hintereinander: danach läuft die kurze Variante. Schnelle Käufe stauen sich nicht.
- [ ] [Studio] Baum während der Sequenz schließen: keine Reste, nichts hängt.
- [ ] [Studio] Schwaches Handy: Sequenz ohne Ruckler. Kein Ton und kein Fehler, solange die Sound-IDs leer sind.

## 2.4 Werkzeugstufen sichtbar (Hand bis Großmaschine)

Die Werte aus dem Baum wirken seit 2.1 (Server: `TreeEffects`, `Collecting`). 2.4 macht die sechs Stufen sichtbar, für alle Spieler im Server. Plan (Opus-Fassung vom 18.11.2026): Der Server setzt die Spieler-Attribute `ToolId` und `Collecting`. `Data/ToolLooks` beschreibt je Stufe Modellteile (vor und neben dem Charakter, nie im Kamera-Gang), Arbeitsspitze (`workPoint`, dort entsteht das Loch), Bewegung beim Sammeln (`motion`), Sandfluss (`sandFlow`: spray, conveyor, cloud, suction, eruption), Staub, Kamera-Bonus und einen leeren Ton-Platzhalter. `Logic/ToolLook` rechnet rein (Auswahl, Wechsel, Hüllquader, Freiraum, Bewegung). `Controllers/ToolVisual` zeigt ein Modell je Spieler, `Dig` gräbt an der Arbeitsspitze.

- [x] [Lune] Jede Werkzeugstufe in `Tools` hat einen Eintrag in `ToolLooks`, und es gibt keinen Eintrag ohne Werkzeug.
- [x] [Lune] Die Stufen unterscheiden sich deutlich: Ausdehnung, Staubmenge und Staubgröße steigen je Stufe mindestens um den Faktor 1,25.
- [x] [Lune] Die Hand hat kein Modell (nur Körner), jede andere Stufe mindestens ein Teil. Jedes Teil hat gültige Form, Größe über 0 und Farbe als Hex-Text.
- [x] [Lune] `ToolLook.of(toolId)`: bekannte ID liefert die Stufe, unbekannte oder leere ID liefert die Hand.
- [x] [Lune] `ToolLook.change(vorher, nachher)`: gleiche Stufe ergibt keine Animation, höhere Stufe die Aufwertungs-Animation, niedrigere (Sandsturm-Reset) und der erste Zustand einen stillen Wechsel.
- [x] [Lune] Kamera: Abstandsbonus je Stufe sinkt nicht, bleibt unter dem Höchstwert und ist nie negativ.
- [x] [Lune] Staub plus Wechsel-Wolke überschreitet das Partikelbudget nicht.
- [x] [Lune] Kein Teil schneidet den Charakter-Quader, kein Teil liegt im Kamera-Gang hinter dem Charakter (alle sechs Stufen, Drehung eingerechnet).
- [x] [Lune] Die Arbeitsspitze jeder Stufe liegt vor dem Charakter, und das Loch dort (Radius aus `Terrain.holeByTool`) erreicht den Charakter-Quader nicht.
- [x] [Lune] `ToolLook.motionAt` ist periodisch, bleibt im Ausschlag und ist bei Ausschlag 0 still.
- [x] [Lune] Jede Stufe hat einen Sandfluss aus der erlaubten Liste, ab der Eimerkette haben zwei aufeinanderfolgende Stufen nie denselben.
- [x] [Lune] Höchstens 12 Teile je Modell. `DataCheck` lehnt eine kaputte `ToolLooks`-Tabelle ab (fehlende Stufe, Größe 0, falsche Farbe, Staub fällt, zu viele Teile, unbekannter Sandfluss, kaputte Bewegung).
- [x] [Lune] Das Werkzeug für das Attribut `ToolId` ist nach Laden, Kauf und Reset das aus `TreeEffects`.
- [x] [Shell] `rojo build` baut ohne Fehler, `lune run tests/run` läuft komplett durch.
- [ ] [Studio] Jede der sechs Stufen sieht im Playtest auf den ersten Blick anders aus.
- [ ] [Studio] Kauf einer neuen Stufe im Baum: das Modell wächst mit kurzer Animation heraus, die Rate steigt im Hud, der Werkzeugname wechselt.
- [ ] [Studio] Zwei Spieler: jeder sieht die Maschine des anderen, inklusive Wechsel.
- [ ] [Studio] Ab dem Mini-Bagger verdeckt keine Maschine den eigenen Charakter, und die Maschine folgt beim Laufen und Springen ohne Ruckeln.
- [ ] [Studio] Das Loch entsteht sichtbar an der Arbeitsspitze.
- [ ] [Studio] Eimerkette, Saugroboter und Großmaschine bewegen den Sand erkennbar anders (Band, Sog, Fontäne).
- [ ] [Studio] Schwaches Handy: Großmaschine mit Staub bleibt über 40 FPS, sonst greift der Wächter.

## 2.5 Zonen 2 bis 5

Plan (Opus-Fassung vom 18.11.2026): Freischaltung über Knoten-IDs (zusätzlich im Profil gespeichert), Bereiche je Zone in `Data/World`, eigenes Terrain-Material je Sandsorte, Wetter je Zone als fester Zyklus aus der Serverzeit (`Data/Weather`, `Logic/Weather`), neues reines Modul `Logic/Zones`, neue Remote `TravelZone`, Tank je Sandsorte (gemischter Tank, Entscheidung von Waltuh am 18.11.2026), Zonen-Menü im Client. Vor dem PR läuft der `security-reviewer` (Remote, Speichern, Preis).

- [x] [Lune] Eine Zone wird frei, sobald ihr `requires`-Knoten (zum Beispiel `collect_tool_3`) gekauft ist, sonst nicht. Das Dünenmeer ist immer frei.
- [x] [Lune] Ein Umbau des Baums, der die Position des Meilensteins ändert, lässt bereits freigeschaltete Zonen frei. Eine im Profil gespeicherte Zone bleibt frei, auch wenn ihr Knoten aus dem Baum verschwindet.
- [x] [Lune] `unlockNew` meldet eine neue Zone genau einmal, auch bei zwei Aufrufen hintereinander.
- [x] [Lune] `zoneAt`: Punkte in jedem Bereich liefern die richtige Zone, Punkte zwischen den Bereichen keine.
- [x] [Lune] Betreten einer gesperrten Zone: Die aktuelle Zone bleibt, der Spieler wird an den Rand der aktuellen Zone zurückgesetzt (nicht zum Spawn). Betreten einer freien Zone macht sie zur aktuellen Zone.
- [x] [Lune] `TravelZone`: unbekannte ID, falscher Typ, gesperrte Zone, Abklingzeit und Rate-Limit werden abgelehnt, eine freie Zone geht durch.
- [x] [Lune] Gemischter Tank: 100 Sand im Dünenmeer, Wechsel zur Oase, 100 Sand dort. Verkaufen zahlt 100 x Faktor 1 plus 100 x Faktor 3, egal an welchem Stand. Die Tankgröße zählt die Summe.
- [x] [Lune] Zonenwechsel während des Sammelns: Das offene Sammelfenster wird mit der alten Sorte abgerechnet, erst danach zählt die neue.
- [x] [Lune] Migration: Ein Profil der alten Version mit Tank 500 in der Oase wird zu 500 rotem Sand. Eine zweite Migration ändert nichts. Speichern und Laden über den Fake-Speicher ergibt denselben Tank.
- [x] [Lune] Wetter: `stateAt` ist für dieselbe Zeit immer gleich, der Regen der Oase dauert 90 s in jedem 8-Minuten-Zyklus, das Dünenmeer hat nie Wetter.
- [x] [Lune] `DataCheck` prüft `World`: jede Zone hat Bereich, Spawn und Stand, Spawn und Stand liegen im Bereich, Bereiche überlappen nicht.
- [x] [Lune] `DataCheck` prüft `SandTypes.terrainMaterial` (verschieden je Sorte) und `Weather` (Zeiten über 0, aktive Zeit kürzer als der Zyklus, bekannte Zonen).
- [x] [Lune] Sicherheit (Review): Ist die aktuelle Zone gesperrt (Sandsturm, Daten-Update), setzt der Server auf das Dünenmeer zurück. Ein zu großer Mix, ein negativer Tank und Sand ohne Mix-Eintrag zahlen nie mehr als der Tank, billigste Sorte zuerst. Die Migration verwirft einen vorhandenen Mix. `sanitize` leert einen Mix ohne Tank. `addSand` und `clearTank` halten Tank und Mix zusammen. Das Limit von `TravelZone` lehnt den zweiten Aufruf ab.
- [x] [Lune] Zeit-Simulation aus 2.1 läuft weiter und wechselt in die beste freie Zone: Die Werkzeugzeiten bleiben in der Spanne aus `docs/balance/skilltree_2_1.md`.
- [x] [Shell] `rojo build` baut ohne Fehler, `lune run tests/run` läuft komplett durch.
- [ ] [Shell] `security-reviewer` findet keine offenen Punkte bei `TravelZone`, Zonenprüfung, Tank und Migration.
- [ ] [Studio] Alle fünf Zonen sind als Platzhalter begehbar, jede mit eigener Sandfarbe, Stand und Spawn.
- [ ] [Studio] Ohne Eimerkette: Das Tor zur Oase ist zu, das Schild nennt den Knoten. Wer trotzdem durchkommt (Fly oder Teleport im Studio-Befehl), landet wieder am Rand der aktuellen Zone mit Meldung.
- [ ] [Studio] Eimerkette kaufen: Meldung "Neue Zone: Oase", das Tor öffnet sich.
- [ ] [Studio] Zonen-Menü: Reisen in eine freie Zone klappt, gesperrte Zonen zeigen den nötigen Knoten.
- [ ] [Studio] Verkaufen in der Oase bringt sichtbar mehr als im Dünenmeer, gemischter Tank wird richtig bezahlt.
- [ ] [Studio] Wetter: Regen in der Oase, Nebel im Salzsee, Dunst in der Ruinenstadt, weiche Übergänge beim Zonenwechsel.
- [ ] [Studio] Graben funktioniert in allen fünf Materialien, im Canyon tiefer.
- [ ] [Studio] Neustart: Zone, freigeschaltete Zonen und Tank bleiben erhalten.

## 2.6 Fundstücke, Reveal und Sammlung

Plan (Opus-Fassung vom 18.11.2026, Doc "Plan Paket 2.6"): Der Server würfelt Funde nur für echte Sammelzeit (`collectSeconds` aus `Collecting.update`), Chance mal Zone, Glück-Ast und Regen, Seltenheit nach der Quotentabelle der Zone (`FindOdds.zoneOddsTable`), Fund gleich verteilt unter den Funden der Zone mit dieser Seltenheit, Wert beim Fund festgeschrieben. 150 Platzhalter mit festen IDs (`dunes_s1_1` bis `ruins_s6_5`, Namen in 3.3). Sammlung, Sets, Bonus und Zonenbuch werden aus `profile.finds` berechnet (`Logic/Collection`, `Data/Collection`), der Sammlungsbonus ist ein eigener Faktor auf die Münzen pro Sand. Doppelte Funde werden sofort zu ihrem festen Wert verkauft (Entscheidung von Waltuh am 18.11.2026). Seltenheiten je Set nach dem Vorschlag des `balance-analyst` (`docs/balance/collection_2_6.md`): Set 1 = 5 Gewöhnliche, Set 2 = 1G 3U 1S, Set 3 = 3U 2S, Sets 4 bis 6 wie im Plan; Set-Boni 3, 3, 4, 4, 6, 10 %. Reveal und Sammlungsbuch im Client, neue Remote `CollectionSync` (nur Server zum Client). Vor dem PR läuft der `security-reviewer` (Münzen, Profil).

- [x] [Lune] Chance: Ohne Sammelzeit kein Fund, negative oder kaputte Zeit zählt als 0. Die Chance im Fenster folgt 1 − (1 − p)^t und bleibt höchstens 100 %. Pro Tick höchstens ein Fund.
- [x] [Lune] Faktoren: Zone, Glück-Ast und Regen multiplizieren die Chance, nicht die Verteilung. Regen zählt nur, solange er aktiv ist (beim Ein- und Ausblenden anteilig).
- [x] [Lune] Verteilung: 200.000 Würfe treffen jede Seltenheit innerhalb der statistischen Toleranz der Tabelle.
- [x] [Lune] Auswahl: Der Fund kommt immer aus der aktuellen Zone und hat die gewürfelte Seltenheit. Fehlt sie in der Zone, kommt die nächst tiefere.
- [x] [Lune] Wert: entspricht `findBaseValue` × Sandfaktor × Werkzeug-Grundrate × Wertfaktor, wird beim Fund festgeschrieben und ändert sich nicht mit dem nächsten Werkzeug.
- [x] [Lune] Neu oder doppelt: Ein neuer Fund setzt den Zähler auf 1 ohne Münzen. Ein doppelter erhöht den Zähler und bucht seinen Wert als BigNum, auch bei großen Münzständen.
- [x] [Lune] Voller Tank: `collectSeconds` endet bei "voll", danach gibt es keine Funde.
- [x] [Lune] Erster Fund sicher: Nach 60 s Sammeln ohne jeden Fund kommt ein Gewöhnlicher Fund, danach greift die Regel nie wieder.
- [x] [Lune] Sammlung: Ein Set mit 5 von 5 ist fertig, mit 4 von 5 nicht. Der Bonus ist die Summe der fertigen Sets. Das Zonenbuch ist nur bei 6 von 6 fertig. Unbekannte IDs zählen nicht und bleiben im Profil.
- [x] [Lune] Preis: Die Münzen pro Sand steigen mit dem Sammlungsbonus, auch beim gemischten Tank. Funde selbst bekommen den Bonus nicht.
- [x] [Lune] `Profile.sanitize` entfernt kaputte Zähler in `finds` (keine ganze Zahl, kleiner 1, NaN), gültige bleiben.
- [x] [Lune] `DataCheck`: 150 Funde, je Set genau 5, jede Zone hat jede Seltenheit, IDs nach Muster, `setBonusBp` und `zoneBooks` gültig, `zoneOddsTable` zeigt auf bekannte Tabellen. Kaputte Daten werden abgelehnt.
- [x] [Lune] Zeit-Simulation aus 2.1 mit Sammlungsbonus: Die Werkzeugzeiten werden im ersten Lauf höchstens 10 % kürzer. Geprüft mit der Python-Simulation `docs/balance/collection_2_6.py` (im Mittel 0,0 %, im schlechtesten Fall 4,8 % kürzer), kein Lune-Test.
- [x] [Lune] Review: Ein Tank mit Bruchteil hält das Sammeln nicht endlos offen. Ein voller Tank mit laufendem Halten gibt keine Sammelzeit. Chance über 100 % durch kaputte Daten gibt höchstens einen Fund je Aufruf.
- [x] [Lune] Review: Die 150 Fund-IDs sind fest (`<Zone>_s<Set>_<Slot>` in Reihenfolge), `DataCheck` lehnt umbenannte IDs, doppelte IDs, falsche Zonen, unbekannte Seltenheiten, Einträge ohne ID und zu hohe Chance, Wetter-Bonus, Wertfaktor oder Sammlungsbonus ab.
- [x] [Lune] Review: Sand ohne Mix-Eintrag bekommt den Sammlungsbonus, Fundwerte mit Bruchteil werden abgerundet, der Zähler eines Fundstücks ist bei 2^31 gedeckelt, ein Profil der Version 1 mit Funden bleibt erhalten.
- [x] [Shell] `rojo build` baut ohne Fehler, `lune run tests/run` läuft komplett durch.
- [x] [Shell] `security-reviewer` findet keine offenen Punkte bei Funden, Münzen aus Duplikaten und Profil (kein kritischer oder hoher Befund, M1 bis M3 und N1, N2, N6, N7, N9 eingearbeitet).
- [ ] [Studio] Sammeln bringt nach etwa einer Minute den ersten Fund mit Reveal, Sammeln und Laufen gehen dabei weiter.
- [ ] [Studio] Ein doppelter Fund zeigt "+X Münzen", die Münzen steigen.
- [ ] [Studio] Ein fertiges Set (im Studio per Befehl gesetzt): Meldung, die Münzen pro Sand steigen sichtbar.
- [ ] [Studio] Das Sammlungsbuch zeigt alle Zonen, Sets und Slots, auch im Handy-Emulator.
- [ ] [Studio] Neustart: Sammlung und Bonus bleiben erhalten.

## 2.7 Sandsturm (Prestige)

Tests: tests/sandstorm.spec.luau. Plan: Claude-Dokument "Paket 2.7: Sandsturm (Prestige), Plan". Waltuh hat Variante A gewählt (Zonen neu, Ruinenstadt am Laufende).

- [x] [Lune] Der Reset setzt Münzen und Werkzeugstufe zurück, behält aber Sammlung und Skins.
- [x] [Lune] Die Windkristalle werden einmal gutgeschrieben, auch bei zwei schnellen Aufrufen.
- [x] [Lune] Ohne `collect_tool_4` gibt der Sturm `requires`, mit dem Knoten aber unter `minCrystals` (20) Kristallen `tooFew`. In beiden Fällen bleibt das Profil unverändert.
- [x] [Lune] Jedes Feld aus `Profile.default` steht genau in einer der Listen "zurücksetzen" oder "behalten".
- [x] [Lune] Gems, Belege, Pity, Boosts, Daily, Tutorial und Inventar sind nach dem Sturm gleich wie vorher.
- [x] [Lune] Die Kristallformel ist monoton, rundet ab, gibt unter einer Einheit 0 und bleibt bei 10^300 Münzen endlich und unter der Obergrenze.
- [x] [Lune] `runEarned` zählt Sandverkäufe und verkaufte Duplikate, nicht Knotenkäufe, und steht nach dem Sturm auf 0.
- [x] [Lune] Der erste Sturm vergibt `sandstorm_1`, ein zweiter behält ihn; `prestiges` zählt hoch.
- [x] [Lune] Mit N Kristallen ist der Preis pro Sand das (1 + N x 2 %)-Fache, zusammen mit Verkauf-Ast und Sammlungsbonus multipliziert; der Fundwert steigt genauso.
- [x] [Lune] Nach dem Sturm ist die Oase gesperrt, bis die Eimerkette gekauft ist; die Ruinenstadt braucht `sandstorm_ruins`; `Zone.resolve` liefert "reset" für einen Spieler, der im Canyon stand.
- [x] [Lune] Ein altes Profil (Version 2) bekommt `runEarned`; ein kaputtes `runEarned` wird 0.
- [x] [Lune] DataCheck meldet einen unbekannten oder vergebenen `requiresNode` und Formelwerte außerhalb der Grenzen.
- [ ] [Studio] Vor dem Canyon (Mini-Bagger) kein Sturm-Knopf, danach erscheint er; das Fenster zeigt "Noch zu früh: ab ... verdienten Münzen gibt es 20 Kristalle", ab 20 Kristallen die Vorschau mit "Du bekommst N Windkristalle" und der Knopf pulsiert.
- [ ] [Studio] Der Sturm braucht zwei Tipps (Nachfrage), danach läuft die Sandwand und das Banner nennt Kristalle und Bonus.
- [ ] [Studio] Nach dem Sturm: Hand, 0 Münzen, Spawn im Dünenmeer, Sammlungsbuch unverändert, Kristalle in der Anzeige, höherer Preis pro Sand.

## 3.6 Handy-Durchgang

Tests: tests/screenlayout.spec.luau, tests/graphicslevel.spec.luau, dazu Erweiterungen in tests/treecamera.spec.luau und tests/treelayout.spec.luau. Plan: Claude-Dokument "Paket 3.6: Handy-Durchgang, Plan". Referenzgrößen im Emulator: iPhone SE quer (568 x 320), iPhone 14 quer, 360er Android, iPad und PC.

- [ ] [Lune] Größenklasse: 568 x 320, 667 x 375 und 375 x 667 sind kompakt; 1024 x 768 und 1920 x 1080 sind normal; die Grenze liegt genau bei 500 (kürzere Seite).
- [ ] [Lune] Fenstergröße: bleibt bei allen Testgrößen innerhalb der sicheren Fläche, hält Ober- und Untergrenze ein, auch bei 0 x 0, negativen Werten und NaN ohne Fehler.
- [ ] [Lune] Tippflächen: Jeder Knopf aus `Data/Screen` (Baum, Menü, Schließen, Reisen, Reiter, Graben) ist in jeder Klasse mindestens 44 px hoch und breit.
- [ ] [Lune] Menüleiste: Am Handy steht sie als Spalte rechts unter "Baum", ohne Überlappung mit HUD, Tutorial-Banner, Baum-Knopf, Graben-Knopf und Sprungknopf-Zone. Bis 5 Knöpfe liegen bei 568 x 320 vollständig im Bild, mehr als eine Spalte entsteht nur, wenn eine nicht reicht. Am PC steht sie als Reihe unten links und bricht in eine zweite Reihe um.
- [ ] [Lune] Tutorial-Banner: überlappt bei Breiten von 568 bis 2560 (und im Hochformat 375 x 667) weder HUD-Panel, Baum-Knopf noch Menüspalte und ist mindestens 240 px breit.
- [ ] [Lune] Grafikstufe: PC hoch, Touch schlank, Grafikregler 1 bis 3 schlank, Rückfall des Bildraten-Wächters minimal (auch am PC), das Attribut `GraphicsLevel` gewinnt immer, ein ungültiges Attribut wird ignoriert.
- [ ] [Lune] Stufen-Daten: Partikelfaktor hoch = 1, schlank höchstens 0,5, minimal = 0; minimal schaltet alles ab, was schlank abschaltet.
- [ ] [Lune] Baum: Knotengröße mal kleinster Zoom bleibt mindestens 44 px, `zoom.startCompact` liegt zwischen min und max, `tapMaxMovePixelsTouch` ist nicht kleiner als `tapMaxMovePixels`, `TreeCamera.isTap` kennt die Touch-Toleranz.
- [ ] [Lune] `DataCheck` lehnt kaputte Werte in `Data/Screen` und den neuen TreeLayout-Werten ab (Knopf unter 44 px, Faktor außerhalb von 0 bis 1, fehlende Stufe).
- [ ] [Shell] `rojo build` baut ohne Fehler, `lune run tests/run` läuft komplett durch.
- [ ] [Studio] Bei 568 x 320: HUD, Tutorial-Banner, Menüspalte, Graben- und Sprungknopf überlappen nicht, alle Texte sind lesbar.
- [ ] [Studio] Zonen: alle fünf Zonen sind erreichbar (Scrollen), Reisen klappt, das Fenster ragt nicht aus dem Bild.
- [ ] [Studio] Sammlung: alle fünf Reiter sind erreichbar, Sets scrollen, Fundnamen sind lesbar.
- [ ] [Studio] Sandsturm: "Sturm auslösen" verdeckt keinen Text, die Nachfrage mit zwei Tipps klappt.
- [ ] [Studio] Nur ein Fenster zur Zeit: Sammlung öffnen schließt Zonen, den Baum öffnen schließt beide.
- [ ] [Studio] Graben am Handy: Halten sammelt, Loslassen und Abrutschen stoppen, Springen geht gleichzeitig. Im Baum ist der Knopf weg.
- [ ] [Studio] Baum: Er öffnet mit mehr Überblick, Knoten lassen sich gut antippen, die Karte ist lesbar, der Kauf klappt.
- [ ] [Studio] Reveal: Die kleine Karte verdeckt die Menüspalte nicht, die große Karte passt ganz aufs Bild.
- [ ] [Studio] Drehen oder die Emulator-Größe wechseln bei offenem Fenster: Das Layout passt sich an.
- [ ] [Studio] Grafik: Das Handy zeigt "schlank" in der Debug-Anzeige, Bloom und Partikel sind sichtbar reduziert. Der PC zeigt "hoch". Das Attribut `GraphicsLevel` schaltet um.
- [ ] [Studio] PC: Alles sieht aus und bedient sich wie vorher.
- [ ] [Studio] Echtes schwaches Handy: Das Spiel läuft flüssig und alle Menüs sind bedienbar (Fertig, wenn).

## 3.3 Fundtabelle mit Namen

Plan (freigegeben von Waltuh am 19.11.2026): Nur `Data/Finds.luau` ändert sich. Die 150 Funde bekommen Namen und Beschreibungen im Stil bekannter Roblox-Simulatoren (kurz, Alltagskram bei Gewöhnlich, episch bei Legendär und Mythisch), Set 6 jeder Zone ist der Schatz der Zone. Sets bekommen ein Feld `name` (z. B. "Strandgut", "Schatz des letzten Barons"), das Reveal und Sammlungsbuch später lesen können. IDs, Seltenheiten, Sets und Zonen bleiben unverändert.

- [x] [Lune] Alle 150 IDs, ihre Reihenfolge, Zone, Set und Seltenheit sind wie in 2.6.
- [x] [Lune] Kein Name und keine Beschreibung enthält "Platzhalter" oder einen alten Namen wie "Dünenfund 1-1".
- [x] [Lune] Namen sind eindeutig und höchstens 28 Zeichen lang. Beschreibungen sind nicht leer und höchstens 80 Zeichen lang.
- [x] [Lune] Jedes der 30 Sets hat einen eindeutigen Namen.
- [x] [Shell] `rojo build` baut ohne Fehler, `lune run tests/run` läuft komplett durch.
- [ ] [Studio] Ein Fund zeigt beim Reveal und im Sammlungsbuch den neuen Namen und die Beschreibung.

## 4.1 Gems und sichere Käufe

Tests: tests/purchases.spec.luau, tests/gems.spec.luau. Plan: Claude-Dokument "Paket 4.1: Gems und sichere Käufe, Plan".

- [x] [Lune] Ein Kauf von `gems_550` schreibt genau 550 Gems gut und liefert erst nach dem Speichern `PurchaseGranted`.
- [x] [Lune] Dieselbe PurchaseId zweimal nacheinander: eine Gutschrift, beide Aufrufe liefern `PurchaseGranted`.
- [x] [Lune] Dieselbe PurchaseId zweimal gleichzeitig (der erste wartet noch aufs Speichern): eine Gutschrift.
- [x] [Lune] Profil nicht geladen oder Spieler nicht auf dem Server: `NotProcessedYet`, keine Gutschrift.
- [x] [Lune] Speichern schlägt fehl oder läuft in die Zeitgrenze: `NotProcessedYet`; Gems und PurchaseId stehen gemeinsam im Profil, der nächste Versuch bucht nicht erneut und liefert `PurchaseGranted`, sobald gespeichert ist.
- [x] [Lune] Absturz vor dem Speichern (Fake-Speicher verwirft den Stand): Der nächste Versuch auf dem neuen Server bucht genau einmal.
- [x] [Lune] Sitzung endet während des Wartens: `NotProcessedYet`, keine zweite Gutschrift beim nächsten Versuch.
- [x] [Lune] Unbekannte ProductId und `productId = 0`: `NotProcessedYet`, keine Gutschrift, ein Protokolleintrag.
- [x] [Lune] Die Beleg-Liste hält höchstens `receiptCacheSize` Einträge und wirft die ältesten zuerst raus; das Kaufprotokoll hält höchstens `purchaseLogSize`.
- [x] [Lune] `Gems.grant` lehnt 0, negative, gebrochene und NaN-Mengen ab und kappt bei `maxGems`; `Gems.spend` bucht nur bei genug Gems ab.
- [x] [Lune] Migration 3 auf 4 übernimmt alte PurchaseIds; kaputte `gems` (negativ, NaN, gebrochen) werden repariert.
- [x] [Lune] Der Sandsturm behält Gems, Belege, Kaufprotokoll und `spent`.
- [x] [Lune] DataCheck meldet doppelte ProductIds und `purchases`-Werte außerhalb der Grenzen.
- [ ] [Studio] Gem-Zähler im HUD; der Knopf "Gems" öffnet die Liste mit fünf Paketen, Preisen und Bonus.
- [ ] [Studio] Studio-Hilfe `DebugPurchase` mit derselben PurchaseId dreimal: Die Gems steigen genau einmal, das Banner erscheint einmal.
- [ ] [Studio] Testkauf eines echten Developer Products in Studio: Gutschrift genau einmal, nach dem Rejoin noch da.

## 4.2 Kisten: Quoten, Pity, Öffnen auf dem Server, Reveal

Tests: tests/crateroll.spec.luau, tests/crateopen.spec.luau. Plan: Claude-Dokument "Paket 4.2: Kisten mit Quoten und Pity, Plan".

- [x] [Lune] Simulation: 200.000 Öffnungen je Kiste ohne Pity, jede Seltenheit innerhalb von 4 Standardabweichungen der Tabelle; Seltenheiten mit 0 % kommen nie vor.
- [x] [Lune] Pity: In 200.000 Goldkisten vergehen nie mehr als 14 Öffnungen ohne Episch oder besser und nie mehr als 59 ohne Legendär oder besser; die Rate Legendär oder besser liegt beim Wert des balance-analyst.
- [x] [Lune] Pity mit festem Zufall: Die 15. Öffnung ohne Episch ist Episch oder besser, die 60. ohne Legendär ist Legendär oder besser; ein Legendär setzt beide Zähler zurück, ein Episch nur `sinceEpic`.
- [x] [Lune] Im 10er-Paket zählt jede der 11 Öffnungen für die Pity, bezahlt werden 10.
- [x] [Lune] Anzeige und Auswurf lesen dieselbe Tabelle: Die Anzeige-Quoten aus `CrateRoll` sind dieselbe Referenz wie die Tabelle des Wurfs.
- [x] [Lune] Zu wenig Gems oder Münzen: Grund `notEnoughGems` oder `notEnoughCoins`, Profil unverändert.
- [x] [Lune] Bei `ArePaidRandomItemsRestricted = true` oder unbekannter Policy lehnt der Server jede Kisten-Öffnung ab, Profil unverändert.
- [x] [Lune] Event-Kiste außerhalb einer Saison: Grund `notInSeason`, Profil unverändert.
- [x] [Lune] Ein Fehler mitten im Wurf lässt Bezahlung, Inventar und Pity unverändert.
- [x] [Lune] Der Pity-Zähler übersteht Speichern und Laden (Neustart) unverändert.
- [x] [Lune] Jedes gewürfelte Item kommt aus dem Pool der Kiste und hat die gewürfelte Seltenheit; Duplikate erhöhen den Zähler im Inventar.
- [x] [Lune] Die Gratis-Öffnung bucht nichts ab und zählt für die Pity.
- [x] [Lune] DataCheck meldet Quoten, die nicht 10000 ergeben, und eine Seltenheit mit Quote über 0 ohne Items im Pool.
- [ ] [Studio] Das Kisten-Fenster zeigt vor dem Kauf Preis, alle Quoten und den Pity-Zähler der Goldkiste.
- [ ] [Studio] Holzkiste mit Münzen und Goldkiste mit Gems (Studio-Hilfe `DebugGems`) öffnen: Reveal läuft, Guthaben sinkt um den Preis, Pity-Zähler zählt.
- [ ] [Studio] 10 + 1 öffnen: 11 Karten, Preis von 10.
- [ ] [Studio] Sammeln und Laufen gehen während des Reveals weiter.
- [ ] [Studio] Rejoin: Inventar und Pity-Zähler sind noch da.

## 4.3 Kisten-Items: Ausrüstung und Verschmelzen

Tests: tests/equipment.spec.luau, tests/data.spec.luau, tests/remotespec.spec.luau. Plan: Claude-Dokument "Paket 4.3: Kisten-Items, Ausrüstung und Verschmelzen, Plan".

- [x] [Lune] Ausrüsten nur mit Besitz und passendem Slot; `""` nimmt ab; eine Ablehnung lässt das Profil unverändert.
- [x] [Lune] Ohne Ausrüstung ist der Faktor genau 1; ein Item gibt seinen Grundwert; drei Items addieren sich; Sterne skalieren nach der Tabelle in `Economy.items`.
- [x] [Lune] `Collecting.rateOf` multipliziert den Ausrüstungsbonus als eigenen Faktor nach dem Baum-Bonus.
- [x] [Lune] Verschmelzen verbraucht genau die Kopien der Tabelle, der Zähler bleibt mindestens 1, bei ★5 und bei zu wenigen Kopien wird abgelehnt; kein Zufall.
- [x] [Lune] Ein ausgerüstetes Item bleibt nach dem Verschmelzen ausgerüstet und wirkt stärker.
- [x] [Lune] Migration 4 → 5 legt `equipped` und `itemStars` an; `sanitize` nimmt nicht besessene oder falsch eingeordnete Items ab, kappt Sterne auf 1 bis 5, unbekannte Items wirken nicht.
- [x] [Lune] Speichern und Laden sowie der Sandsturm behalten Inventar, Ausrüstung und Sterne.
- [x] [Lune] Remotes `EquipItem` und `MergeItem`: falsche Typen, unbekannte IDs und zu viele Argumente werden abgelehnt, die Limits stimmen.
- [x] [Lune] DataCheck: jedes Item hat `effectBp` im erlaubten Bereich und einen Eintrag in `ItemLooks`; die Stern-Regeln sind gültig.
- [ ] [Studio] Kiste öffnen, Item ausrüsten: Die Sammelrate steigt sichtbar, Umhang, Begleiter oder Werkzeugfarbe erscheinen.
- [ ] [Studio] Ein zweiter Spieler (Studio-Test mit 2 Spielern) sieht die Ausrüstung des ersten.
- [ ] [Studio] Mit Kopien verschmelzen: Sterne steigen, Kopien sinken, der Gesamtbonus im Fuß steigt.
- [ ] [Studio] Rejoin und Sandsturm: Ausrüstung und Sterne bleiben.
- [ ] [Studio] Handy: Das Ausrüstungs-Fenster ist mit dem Daumen bedienbar.

## 4.4 Gamepasses (2x Münzen, Auto-Dig, Großer Tank) und Münz-Boost

Tests: tests/perks.spec.luau, tests/passes.spec.luau, tests/data.spec.luau, tests/remotespec.spec.luau. Plan: Claude-Dokument "Paket 4.4: Gamepasses und Boosts, Plan". Fertig, wenn: Besitz wird auf dem Server geprüft und wirkt nach Neustart.

- [x] [Lune] Ohne Pässe und Boost sind Tank-Faktor und Münz-Faktor genau 1; Rechnungen bleiben wie vor 4.4.
- [x] [Lune] "Großer Tank": `capacityOf` verdoppelt die Tankgröße (`Economy.bigTankMultiplier`), auch für Vollmeldung und Sammelstopp.
- [x] [Lune] "2x Münzen": Preis pro Sand, Tankwert, Verkauf und Sandsturm-Vorschau rechnen alle mit demselben Faktor.
- [x] [Lune] Münz-Boost: wirkt nur vor `coinsUntil` (Server-Uhr), danach Faktor 1; Pass und Boost zusammen nach der freigegebenen Regel.
- [x] [Lune] Boost verlängern: abgelaufen ergibt jetzt + 30 min, laufend ergibt alte Endzeit + 30 min; kaputte Werte (NaN, negativ, unendlich) zählen als abgelaufen.
- [x] [Lune] Kauf "coin_boost" über ProcessReceipt: Gutschrift nur über `boosts`, keine Gems; derselbe Beleg zweimal verlängert nur einmal; ProductId 0 kommt nie durch.
- [x] [Lune] Gamepass-Besitz: "ja" der Roblox-Abfrage trägt sofort ein, erst das zweite "nein" in Folge (nach `RECHECK_SECONDS`) entfernt, ein Fehler dazwischen behält den Pass; schlägt die Abfrage fehl, gilt der gemerkte Besitz; in Studio und nach einem bestätigten Kauf entfernt "nein" nie. (Security-Review 4.4)
- [x] [Lune] Kauf-Ereignis: trägt nur nach einer bestätigten Abfrage ein ("nein", Fehler oder gefälschtes `wasPurchased` ändern nichts); Spam startet je Spieler und Pass keine parallelen Prüfungen; schon eingetragen, unbekannte ID und ID 0 fragen nicht ab; abwesende Spieler werden nicht gemerkt; Profil noch nicht geladen: erst nach der Bestätigung gemerkt, beim Laden eingetragen; ohne Abfrage nur in Studio. (Security-Review 4.4)
- [x] [Lune] Kaputter Tank-Faktor (NaN, unendlich, 0, negativ, kein number) zählt in `capacityOf` als 1. (Security-Review 4.4)
- [x] [Lune] Migration 5 → 6 legt `passes` und `settings.autoDig` an; `sanitize` entfernt unbekannte Pass-IDs und Werte außer `true`; Speichern, Laden und Sandsturm behalten Pässe, Einstellung und Boost.
- [x] [Lune] Auto-Dig: sammelt ohne Taste, wenn der Pass da ist, die Einstellung an ist, der Charakter sammeln darf und der Tank nicht voll ist; stoppt bei vollem Tank, läuft nach dem Verkauf weiter; ohne Pass ändert sich nichts.
- [x] [Lune] Remote `SetAutoDig`: nur ein Boolean, Limit 2 pro Sekunde; ohne Pass wird nur die Einstellung gespeichert, es wird nichts gesammelt.
- [x] [Lune] DataCheck: jeder Gamepass in `Products` hat eine bekannte Wirkung, Faktoren sind größer als 1, `coin_boost` hat einen Handler.
- [ ] [Studio] `DebugPass` "big_tank": Tankgröße verdoppelt sich sofort und nach Rejoin.
- [ ] [Studio] `DebugPass` "double_coins": Verkauf bringt doppelt so viele Münzen, der HUD-Preis zeigt es.
- [ ] [Studio] `DebugPurchase` "coin_boost": Countdown 30:00 erscheint, Verkauf doppelt; derselbe feste Beleg zweimal verlängert nur einmal.
- [ ] [Studio] `DebugPass` "auto_dig": Sammeln läuft ohne Taste, stoppt bei vollem Tank, läuft nach dem Verkauf weiter; Schalter aus stoppt es.
- [ ] [Studio] Mit echten IDs: Testkauf eines Gamepasses wirkt sofort, nach Rejoin und auf einem neuen Server (Live-Test). Im Live-Spiel erscheint im Server-Log "eingetragen (Kauf, von Roblox bestätigt)"; ein Exploit-Aufruf von `SignalPromptGamePassPurchaseFinished` mit einer echten ID ohne Kauf trägt nichts ein.

## 4.5 Shop-Oberfläche und Angebote (Starterpaket)

Tests: tests/offers.spec.luau (Auslöser, Zustände, alte Spielstände, Kauf, Version 7, Hinweise; auch die Pflichtfälle für Käufe mit "starter_pack": doppelter Beleg, Speichern schlägt fehl, Profil nicht geladen, Absturz vor dem Speichern), tests/data.spec.luau ("Angebote (4.5)", DataCheck), tests/profile.spec.luau, tests/playersession.spec.luau. Plan: Claude-Dokument "Paket 4.5: Shop und Angebote, Plan". Fertig, wenn: Angebote erscheinen nach dem Reveal und blockieren nichts.

- [x] [Lune] Der erste Fund ab "Selten" startet das Starterpaket-Fenster (Server-Uhr), weitere Funde verschieben es nicht; Funde darunter und Kisten-Items starten nichts.
- [x] [Lune] Zustand des Angebots: verborgen vor dem Auslöser, aktiv bis Start + 24 h, danach abgelaufen, nach dem Kauf gekauft; kaputte Zeiten zählen als nicht gestartet.
- [x] [Lune] Alte Spielstände mit schon vorhandenem Selten-Fund bekommen das Fenster ab dem ersten Laden nach dem Update.
- [x] [Lune] Kauf "starter_pack" über ProcessReceipt: genau 300 Gems (gekappt bei maxGems), je ein Exemplar der festen Items aus den Daten, Merker "gekauft"; derselbe Beleg zweimal bucht nur einmal; kein Zufall.
- [x] [Lune] Ein bezahlter Beleg außerhalb des Fensters oder nach einem früheren Kauf wird trotzdem gebucht und bestätigt (nie NotProcessedYet für immer), seit 6.1 aber nur mit Ersatz-Gems (siehe 6.1).
- [x] [Lune] Migration 6 → 7 legt `offers` an; `sanitize` repariert kaputte Werte; Sandsturm behält `offers`.
- [x] [Lune] Reihenfolge der Hinweise: ein Angebots-Hinweis wartet, solange ein Reveal läuft oder wartet und solange das Tutorial läuft; je Angebot höchstens ein Hinweis pro Sitzung.
- [x] [Lune] DataCheck: Angebote verweisen auf bekannte Produkte und Items, die Items sind fest (keine Kiste, kein Zufall), Fenster und Gems sind gültig.
- [ ] [Studio] `DebugFindZone` oder ein echter Selten-Fund: Nach dem Reveal erscheint der kleine Angebots-Hinweis, nie davor; Sammeln und Laufen gehen weiter.
- [ ] [Studio] Der Hinweis lässt sich schließen; "Ansehen" öffnet den Shop im Bereich "Angebote" mit Countdown.
- [ ] [Studio] `DebugOffer` "starter", dann `DebugPurchase` "starter_pack": 300 Gems, Glasschaufel und Begleiter im Inventar, das Angebot verschwindet; Rejoin: bleibt gekauft. Ein zweiter `DebugPurchase` "starter_pack" gibt nur 300 Ersatz-Gems, keine Items, Banner "Starterpaket nicht verfügbar: +300 Gems".
- [ ] [Studio] Handy: Shop-Reiter und Hinweis sind mit dem Daumen bedienbar und verdecken weder Graben-Knopf noch Menüspalte.

## 4.6 Policy-Funktionen

Tests: tests/crateroll.spec.luau, tests/directshop.spec.luau, tests/policyguards.spec.luau, tests/oddsview.spec.luau, tests/priceview.spec.luau, tests/policycache.spec.luau, tests/purchases.spec.luau, tests/remotespec.spec.luau, tests/data.spec.luau. Plan: Claude-Dokument "Paket 4.6: Policy-Funktionen, Plan". Fertig, wenn: Die Policy-Checkliste aus dem Konzept ist abgehakt.

- [x] [Lune] `effectiveOdds` ergibt für jede Kiste und jeden Pity-Stand 100 %; bei anstehender Garantie nur Seltenheiten ab der garantierten Stufe.
- [x] [Lune] `roll` würfelt über `effectiveOdds`: für feste Zufallsfolgen dasselbe Ergebnis wie vor 4.6, und die Simulation trifft die angezeigten Quoten.
- [x] [Lune] `itemOdds`: jedes Item jeder Kiste kommt vor, exakte Summe 100 %, Quote je Item = Seltenheits-Quote geteilt durch Poolgröße.
- [x] [Lune] Glück-Ast, Glück-Boost, Pässe, Münz-Boost und Ausrüstung ändern weder Kistenquoten noch Wurf.
- [x] [Lune] Direktpreis: aus den Daten gerechnet, nie unter dem Erwartungswert der günstigsten Gem-Kiste, gerundet; Event-Items haben keinen Preis.
- [x] [Lune] Direktkauf: nur bei gesperrter oder unbekannter Policy, nie während der ersten Abfrage und nie bei erlaubten Kisten; genau der Preis wird abgebucht, Inventar +1; zu wenig Gems, unbekanntes Item, Event-Item, kein Profil: Ablehnung, Profil unverändert; Fehler oder Warten im Block: nichts gebucht.
- [x] [Lune] Remote `BuyDirectItem`: Schema und Limit aus `RemoteSpec`, falsche Typen und zu lange Texte abgelehnt.
- [x] [Lune] Keine Remote außer `OpenCrate`, `EquipItem`, `MergeItem` und `BuyDirectItem` verändert das Inventar, keine überträgt Items oder Gems an andere Spieler.
- [x] [Lune] DataCheck: Ersatzgegenstand Tag 7 ist ein festes Item aus `CrateItems`, kein Event-Item.
- [x] [Lune] ProcessReceipt mit abweichendem `CurrencySpent`: gebucht, Warnung im Protokoll und Vermerk im Kaufprotokoll.
- [ ] [Studio] Kisten-Fenster: "Details" zeigt alle Items mit Quote und Rundungshinweis; Pity-Zeile mit Gems.
- [ ] [Studio] `DebugCratesRestricted = true`: Kisten-Knopf weg, Reiter "Direktkauf" da, Kauf mit Gems landet im Inventar und lässt sich ausrüsten; `false`: Reiter weg, Kisten wieder da.
- [ ] [Studio] Gold-Pity kurz vor der Garantie (14 Öffnungen ohne Episch): Karte zeigt weiter die normale Tabelle und darüber "Deine nächste Öffnung ist garantiert Episch oder besser: Episch 75 %, Legendär 22,5 %, Mythisch 2,5 %"; die 15. Öffnung bringt mindestens Episch, danach ist der Satz sofort weg.
- [ ] [Studio] Details-Fenster der Goldkiste: normale Tabelle mit allen Items, darunter "Garantierte Öffnung" für Episch und Legendär; "Zurück zu den Kisten" führt zurück.
- [ ] [Studio] Direktkauf: erster Tipp zeigt "Wirklich? … Gems", erst der zweite kauft; zu wenig Gems gibt eine Meldung.
- [ ] [Studio, nach dem Anlegen der Produkte] Shop zeigt die Preise aus dem Dashboard; ein absichtlich falscher Tabellenpreis erzeugt eine Warnung im Server-Output.
- [ ] [Dashboard] Fragebogen nach `docs/fragebogen.md` ausgefüllt, Freigabe erteilt.
- [x] [Shell] `security-reviewer` ohne offenen kritischen oder hohen Befund (H1, M1, M2 eingearbeitet, Rest siehe docs/architektur.md).

## 4.7 Quoten-Simulation

Skript: `lune run scripts/cratesim [Öffnungen] [Startwert] [Bericht]`, Bericht docs/balance/crates_sim_4_7.md (Referenzlauf 10 Mio. je Kiste und Lauf), Test tests/cratesim.spec.luau. Plan: Claude-Dokument "Paket 4.7: Quoten-Simulation, Plan". Fertig, wenn: Die Abweichung von der Tabelle ist klein.

- [x] [Shell] Das Skript läuft mit 1.000.000 Öffnungen je Kiste durch und schreibt den Bericht.
- [x] [Shell] Jede Seltenheit und jedes Item jeder Kiste liegt innerhalb der Schwellen, getrennt für Einzelöffnungen und 10 + 1 Pakete.
- [x] [Shell] Die Pity-Grenzen werden nie überschritten, auch über Paketgrenzen hinweg.
- [x] [Shell] Gleicher Startwert ergibt den gleichen Bericht.
- [x] [Lune] Kleiner Lauf über `CrateOpen.open` im normalen Testlauf, unter 3 Sekunden.

## 5.1 Daily Reward

Plan: Claude-Dokument "Paket 5.1: Daily Reward, Plan". Fertig, wenn: Die Serie zählt richtig, und Tag 7 gibt die Eisenkiste oder den Ersatz. Tests: `daily`, `perks`, `findroll`, `profile`, `data`, `remotespec`, `policyguards`, `passes`.

- [x] [Lune] Serie: Tag 1 bis 7 an aufeinanderfolgenden Tagen, danach wieder Tag 1; ein ausgelassener Tag setzt auf Tag 1; zweimal am selben Tag geht nicht; Tagwechsel genau um 0 Uhr UTC.
- [x] [Lune] Vor dem Kauf der Schaufel nichts abholbar; nach einem Sandsturm weiter abholbar.
- [x] [Lune] Belohnungen aus den Daten: Gems (gekappt bei maxGems), Münz-Boost verlängert, Glücks-Boost verlängert.
- [x] [Lune] Tag 7 gibt die Eisenkiste oder bei `ArePaidRandomItemsRestricted = true` (und bei unbekannter Policy) den festen Ersatzgegenstand; während der ersten Abfrage `policyPending`, nichts gebucht.
- [x] [Lune] Fehler oder Warten im Block: nichts gebucht, Serie unverändert.
- [x] [Lune] Glücks-Boost verdoppelt die Fundchance und ändert keine Kistenquote.
- [x] [Lune] Gespeicherter Tag in der Zukunft: keine zweite Belohnung.
- [x] [Lune] Remote `ClaimDaily`: kein Argument, Limit aus `RemoteSpec`.
- [ ] [Studio] Fenster öffnet sich einmal nach dem Tutorial, Abholen zeigt die Belohnung; `DebugDaily` "yesterday" macht den nächsten Tag abholbar.
- [ ] [Studio] Tag 7 mit `DebugCratesRestricted` true und false: Kupferschaufel bzw. Eisenkisten-Reveal.
- [x] [Shell] `security-reviewer` ohne offenen kritischen oder hohen Befund.

## 5.2 Codes-System

Plan: Claude-Dokument "Paket 5.2: Codes-System, Plan". Fertig, wenn: Codes sind einmal pro Spieler einlösbar.

- [x] [Lune] Ein Code ist einmal je Spieler einlösbar; das zweite Mal gibt `alreadyRedeemed`, nichts wird gebucht.
- [x] [Lune] `normalize`: Leerzeichen, Groß- und Kleinschreibung, falsche Zeichen, zu lang, leer, kein String.
- [x] [Lune] Belohnungen: Gems gekappt bei `maxGems`, Münz-Boost und Glücks-Boost verlängern.
- [x] [Lune] Abgelaufen, noch nicht begonnen und unbekannt geben dieselbe Antwort wie ungültig.
- [x] [Lune] Fehler im Block: nichts gebucht, `codes` unverändert.
- [x] [Lune] 5 falsche Versuche führen zur Sperre (60 Sekunden, je Spieler); in der Sperre wird auch ein richtiger Code abgelehnt.
- [x] [Lune] Die Codes stehen nicht im Shared-Ordner, und keine Belohnung ist eine Kiste oder ein Item.
- [x] [Lune] DataCheck lehnt doppelte Codes, unbekannte Art und kaputte Zeiten ab.
- [x] [Lune] Remote `RedeemCode`: ein String-Argument, Länge und Limit aus `RemoteSpec`.
- [x] [Lune] Profil: fehlendes `codes` wird aufgefüllt, der Sandsturm behält es.
- [ ] [Studio] Fenster öffnet, ein Test-Code gibt die Belohnung, derselbe Code noch einmal "schon eingelöst", falscher Code zeigt die Standardmeldung, nach `DebugCodes` "reset" geht er wieder.
- [x] [Shell] `security-reviewer` ohne offenen kritischen oder hohen Befund.

## 5.3 Begleiter, Offline-Ertrag und Auto-Dig

Plan: Claude-Dokument "Paket 5.3: Begleiter, Offline-Ertrag und Auto-Dig, Plan". Fertig, wenn: Der Ertrag nach Abwesenheit stimmt und ist gekappt.

- [x] [Lune] Der Offline-Ertrag wird bei der Grenze gekappt (ohne Pass 4 Stunden, mit Auto-Dig 12 Stunden); genau an der Grenze und eine Sekunde darüber.
- [x] [Lune] Der Ertrag stimmt gegen eine feste Rechnung (Rate, Sekunden, Faktor, Preis) für zwei Zonen und mit 2x-Pass.
- [x] [Lune] Der Offline-Ertrag enthält keine Fundstücke (die Gutschrift ändert nur `coins`, `runEarned` und `lastSeen`).
- [x] [Lune] Der Offline-Ertrag wird aus dem Zeitstempel des Servers berechnet, nicht aus einer Angabe des Clients (kein Argument, keine Remote).
- [x] [Lune] Ohne ausgestatteten oder ohne besessenen Begleiter gibt es nichts.
- [x] [Lune] Unter 5 Minuten sowie fehlende, kaputte oder in der Zukunft liegende `lastSeen` geben nichts.
- [x] [Lune] Münz-Boost, Glücks-Boost und Item-Bonus verändern den Offline-Ertrag nicht.
- [x] [Lune] Zweimal hintereinander laden zahlt nur einmal (`lastSeen` wird im selben Schritt gesetzt); ein Fehler im Block bucht nichts.
- [x] [Lune] Die Münzen laufen wie verdiente Münzen über `Collecting` und `runEarned` (kein Weg über Gems oder `Wind.credit` für gekaufte Münzen).
- [x] [Lune] DataCheck: `Economy.offline` mit `rateFactor` von 0 bis 1 und größerer Auto-Dig-Grenze.
- [ ] [Studio] Mit ausgestattetem Begleiter und `DebugOffline` 30 kommt die Karte mit passender Zahl, ohne Begleiter der Hinweis, mit `DebugOffline` 1000 die Zeile "Grenze erreicht".
- [ ] [Studio] Der Auto-Dig-Text im Shop nennt die 12 Stunden.
- [x] [Shell] `security-reviewer` ohne offenen kritischen oder hohen Befund.

## 5.4 Event-Kalender als Daten

Plan: Claude-Dokument "Paket 5.4: Event-Kalender als Daten, Plan". Fertig, wenn: Neue Saison heißt neue Tabellenzeile.

- [x] [Lune] Zeitpunkte einer Saison (Beispiel-Tabelle im Test): eine Sekunde vor dem Start nichts aktiv, die erste Sekunde ist Woche 1, die letzte Sekunde ist Woche 4, die Sekunde nach dem Ende nichts aktiv (Ende ausschließend, 28 Tage ab 0 Uhr UTC).
- [x] [Lune] Wochengrenzen: Tage 0 bis 6 sind Woche 1, 7 bis 13 Woche 2, 14 bis 20 Woche 3, 21 bis 27 Woche 4, jeweils mit der Phasen-ID aus der Tabelle.
- [x] [Lune] Zwischen zwei Saisons ist nichts aktiv, `next` nennt die nächste Saison und die Sekunden bis zu ihrem Start; nach der letzten Saison gibt es kein `next`.
- [x] [Lune] `inSeason` ist nur für die Kiste der aktiven Saison und nur in Phasen mit `crateOpen` wahr; die Kiste einer anderen oder kommenden Saison bleibt gesperrt.
- [x] [Lune] Ungültige Zeit (nil, NaN, unendlich, negativ, Text) lässt nichts aktiv sein und wirft keinen Fehler.
- [x] [Lune] Eine zusätzliche Zeile in einer Testtabelle macht die Saison aktiv, ohne dass Logik-Code geändert wird (Tabelle wird als Argument übergeben).
- [x] [Lune] Event-Kiste und `CrateOpen`: außerhalb der Saison "notInSeason" und nichts gebucht, in der Saison öffnet sie mit denselben Quoten wie die Goldkiste und bucht Gems, Pity und Inventar wie bisher.
- [x] [Lune] Der Kistenbestand und die Items bleiben nach Saisonende im Profil erhalten (nur das Öffnen der Event-Kiste ist gesperrt).
- [x] [Lune] DataCheck für `Seasons`: doppelte ID, Start kein Montag, ungültiges Datum, Überlappung, unbekannte Kiste, Kiste ohne `eventOnly`, `eventOnly`-Kiste ohne Saison, dieselbe Kiste in zwei Saisons; optionale `zoneId` und `passId` werden nur geprüft, wenn sie gesetzt sind.
- [x] [Lune] `parseDebug`: "off", "clear" und "week:1" bis "week:4" werden erkannt, alles andere ergibt nichts.
- [x] [Lune] Die Snapshot-Form (`state`) enthält in der Saison `id`, `name`, `week`, `phaseId`, `secondsLeft`, `crateId`, `crateOpen` und in der Pause `next` mit `secondsToNext`.
- [x] [Shell] Es gibt keine neue Remote (RemoteSpec unverändert), die Zeit kommt nur von `os.time()` auf dem Server; `DebugSeason` wird außerhalb von Studio nie gelesen.
- [ ] [Studio] `DebugSeason` "week:1": Die Event-Kiste ist kaufbar, die Zeile zeigt "Saison endet in ...", Öffnen zieht die Gems ab.
- [ ] [Studio] `DebugSeason` "off": Die Karte der Event-Kiste zeigt "Nächste Saison in ...", die Knöpfe sind grau (Antippen: Hinweis "nur in der Saison"), die Quoten bleiben sichtbar. Ohne laufende oder kommende Saison ist die Karte ausgeblendet.
- [ ] [Studio] `DebugSeason` "week:4": Die Zeile zeigt "Letzte Woche: letzte Chance auf die Event-Kiste". Ein Wechsel des Attributs aktualisiert die Anzeige ohne Neustart innerhalb weniger Sekunden.
- [x] [Shell] `security-reviewer` ohne offenen kritischen oder hohen Befund.

## 5.5 Saison-Pass, Event-Kiste, Event-Zone

Plan: Claude-Dokument "Paket 5.5: Saison-Pass, Event-Kiste, Event-Zone, Plan". Fertig, wenn: Saison 1 ist komplett spielbar und kaufbar. Zwei Pull Requests: 5.5a (Event-Zone, Saison-Punkte, Event-Kiste) und 5.5b (Saison-Pass).

5.5a Event-Zone, Punkte, Event-Kiste

- [x] [Lune] Die Event-Zone ist nur offen, wenn ihre Saison läuft, die Woche `zoneOpen` hat und der Knoten (Vorgabe `collect_tool_2`) gekauft ist; vor dem Start und nach dem Ende ist sie gesperrt, Besitz und Funde bleiben.
- [x] [Lune] Die Event-Zone steht nie in `profile.zones`; der Sandsturm und die Sammlung (Funde, Sets) bleiben bei den fünf festen Zonen unverändert.
- [x] [Lune] Steht ein Spieler beim Saisonende in der Event-Zone, setzt der Server ihn zurück an den Spawn der ersten Zone.
- [x] [Lune] Saison-Punkte zählen nur aus der vom Server gerechneten Sammelzeit in der Event-Zone, nur in einer laufenden Saison, nie ohne Zone, mit Obergrenze (Summe aller Stufen); der Client sendet keinen Wert.
- [x] [Lune] Der Punktestand liegt in `profile.seasons[seasonId]`, überlebt Laden und Sandsturm und wird beim Laden repariert (kaputte Zahlen, unbekannte Saison).
- [x] [Lune] DataCheck: Event-Zone mit gültiger Sandsorte und Knoten, genau eine Zone je Saison-Zeile, Event-Sand mit Preisfaktor, `Economy.seasonPass` vollständig.
- [x] [Lune] Event-Kiste: Saison-1-Pool vollständig (je Seltenheit gefüllt), Quoten wie die Goldkiste, die Simulation aus 4.7 enthält die Event-Kiste und bleibt innerhalb der Abweichung.
- [x] [Lune] DataCheck verbietet Pass-Items in Angeboten und als Tag-7-Ersatz, meldet eine nicht prüfbare Gem-Obergrenze, eine Saison mit Stufen ohne Zone und zu lange Boost-Belohnungen; unbekannte Felder in `profile.seasons` bleiben beim Säubern erhalten.
- [x] [Shell] `security-reviewer` (Event-Zone, Punkte, Profil, DebugSeason) ohne offenen kritischen, hohen oder mittleren Befund; die niedrigen Befunde sind bis auf die unten genannten behoben.
- [ ] [Studio] `DebugSeason` "week:1": die Event-Zone erscheint im Zonen-Menü, Hinfahren und Graben zählt "Saison-Punkte x von y"; mit "off" in der Zone: Rücksetzen an den Spawn und im Menü "Nur in der Saison".

5.5b Saison-Pass

- [x] [Lune] Punkte zu Stufe: Stufe n ist ab ihrem Punktestand erreicht, nie früher; ein Sprung über mehrere Stufen erreicht alle.
- [x] [Lune] Abholen: nur erreichte Stufen, jede Stufe je Spur genau einmal, die Premium-Spur nur mit Pass; Belohnung und "abgeholt" werden in einem Zug gebucht (Fehler bucht nichts).
- [x] [Lune] Belohnungen sind fest (Gems, Boosts, feste Items), nie Kisten oder Zufall; sie gelten auch bei `ArePaidRandomItemsRestricted`. DataCheck verbietet Kisten und Zufall in den Stufen.
- [x] [Lune] Kauf: Dieselbe PurchaseId zweimal ergibt genau eine Gutschrift (idempotent), `PurchaseGranted` erst nach dem Speichern; unbekanntes Produkt oder kaputte Daten gewähren nichts.
- [x] [Lune] Doppelkauf derselben Saison: `BuySeasonPass` öffnet den Kaufdialog nicht (ein manipulierter Client kann ihn trotzdem selbst aufrufen); trifft ein Kauf ein, gibt es die Ersatz-Gems aus `Economy.seasonPass` statt eines zweiten Passes.
- [x] [Lune] Kauf außerhalb der Saison: `BuySeasonPass` startet den Kaufdialog nicht; trifft eine Zahlung innerhalb der Abholfrist nach dem Ende ein, gilt sie für die zuletzt beendete Saison.
- [x] [Lune] Abholfrist: Belohnungen sind bis zum Ende der Frist (Tage in den Daten) nach dem Saisonende abholbar, danach nicht mehr; Punkte zählen nach dem Ende nicht mehr.
- [x] [Lune] DataCheck: Stufen aufsteigend und lückenlos, Items existieren, Pass-Items stehen in keiner Kiste, Gems höchstens `maxGems`, die Premium-Gems liegen unter dem Anteil des Pass-Preises aus den Daten.
- [x] [Lune] Neue Saison: Eine zweite Saison-Zeile mit eigener Zone, Kiste und Stufen läuft ohne Code-Änderung (Testtabelle).
- [x] [Lune] Die neuen Remotes (`BuySeasonPass`, `ClaimSeasonReward`) haben Schema, Bereichsprüfung und Rate-Limit in `RemoteSpec`.
- [x] [Lune] Eine Zahlung nach dem Saisonende gilt für die zuletzt beendete Saison (innerhalb der Abholfrist), danach gibt es die Ersatz-Gems aus `Economy.seasonPass`; der Pass einer Saison wird nie zweimal vergeben.
- [x] [Lune] Zwei gleichzeitige `ClaimSeasonReward`-Aufrufe buchen eine Stufe nur einmal (Sperre je Spieler); ein Fehler beim Abholen lässt Gems, Boosts und "abgeholt" unverändert.
- [x] [Lune] `premium = true` und die Abholmerker überleben Laden, Speichern und Sandsturm; `Seasons.lastEnded` liefert die zuletzt beendete Saison und die Sekunden seit dem Ende.
- [ ] [Studio] `DebugSeason "ended"` (ein Tag nach dem Saisonende): Abholen geht noch, neue Punkte zählen nicht; `DebugSeasonPass "points:500"` erreicht Stufe 4.
- [ ] [Shell] `balance-analyst`: Simulation der Punkte-Kurve (Gelegenheitsspieler schafft rund zwei Drittel der Spur, Vielspieler die ganze Spur vor Woche 4) und Wert der Premium-Spur in `docs/balance/season_5_5.md`.
- [ ] [Shell] `security-reviewer` (Käufe, Abholen, Remotes) ohne offenen kritischen oder hohen Befund.
- [ ] [Studio] `DebugSeason` "week:1": Event-Zone erscheint im Zonen-Menü, Hinfahren und Graben zählt Punkte im Pass-Fenster, ein Gratis-Preis lässt sich abholen.
- [ ] [Studio] Testkauf des Saison-Passes schaltet die Premium-Spur frei, Abholen gibt Gems und feste Items; ein zweiter Kauf-Knopf ist gesperrt.
- [ ] [Studio] `DebugSeason` "off" während man in der Event-Zone steht: Der Spieler wird zurückgesetzt, die Zone ist gesperrt, das Pass-Fenster zeigt die Abholfrist.
- [ ] [Studio] Das Pass-Fenster ist am Handy-Bildschirm bedienbar.

## 5.6 Server-Event "Der Koloss"

Plan: Claude-Dokument "Paket 5.6: Server-Event Der Koloss, Plan". Fertig, wenn: Alle Spieler eines Servers graben am Wochenende der Koloss-Woche gemeinsam, bei 100 % bekommen alle im Server ihre Belohnung nach Beitrag.

- [x] [Lune] Das Fenster läuft Samstag 0 Uhr bis Montag 0 Uhr UTC der Koloss-Woche (Daten: Phase, Starttag, Tage); davor "upcoming", danach "over", außerhalb einer Saison "none"; kaputte Zeit ergibt nie ein offenes Fenster.
- [x] [Lune] Der Fortschritt zählt nur Grabsekunden, die der Server meldet, nur bei offenem Fenster; NaN, unendlich, 0 und negative Werte ändern nichts; bei 100 % gedeckelt, das Event ist danach fertig und zählt nichts mehr.
- [x] [Lune] Der Beitrag je Spieler wächst nur um den wirklich gezählten Anteil (nichts über den Deckel); ein neues Event beginnt mit einer neuen Saison bei 0.
- [x] [Lune] Die Stufe zum Beitrag stimmt an den Grenzen (0 s, knapp unter und genau auf der Schwelle).
- [x] [Lune] Die Belohnung wird je Spieler und Saison einmal vergeben (Merker im Saison-Eintrag), in einem Zug mit dem Merker; Gems sind bei `maxGems` gekappt; ein Fehler bucht nichts; ein zweiter Aufruf gibt `claimed`.
- [x] [Lune] Die Belohnungen sind fest (Gems, Münz- und Glücks-Boost), nie Kisten oder Zufall.
- [x] [Lune] Die Anzeigeform (`koloss`) nennt Zustand, Fortschritt, Ziel, den eigenen Beitrag, Restzeit und erreichte Stufe und keine fremden Spieler.
- [x] [Lune] Es gibt keine Remote für das Event; Fortschritt entsteht nur über `Events.addZoneSeconds`.
- [x] [Lune] Das Feld `koloss` im Saison-Eintrag überlebt Laden, Speichern und Sandsturm und wird repariert (nur `true` zählt).
- [x] [Lune] DataCheck: Fenster liegt in der Koloss-Woche, Ziel größer 0, Stufen aufsteigend ab 0, nur feste Belohnungen, Gems höchstens `maxGems`, Boosts höchstens 4 Stunden.
- [x] [Lune] Studio-Hilfe: `DebugSeason "koloss"` und `DebugKoloss` ("progress:N", "complete", "reset") werden richtig gelesen und wirken nur in Studio.
- [x] [Shell] `security-reviewer` ohne offenen kritischen oder hohen Befund (Befunde M2, N1, N3, N4, N5 behoben, Balance-Frage M1 offen, siehe architektur.md).
- [ ] [Studio] `DebugSeason "koloss"`, `DebugKoloss "progress:5900"`, in der Event-Zone graben: Der Balken steigt, bei 100 % kommt die Meldung mit der Stufe, `KolossProgress` steht auf 1.
- [ ] [Studio] Test mit 2 Spielern (beide setzen `DebugSeason "koloss"`, die Saison-Uhr gilt je Spieler): beide füllen denselben Balken, beide bekommen ihre Stufe.

## 5.7 Freunde-Bonus, Rangliste, Sammlung besuchen

Plan: Claude-Dokument "Paket 5.7: Freunde-Bonus, Rangliste, Sammlung besuchen, Plan". Fertig, wenn: Boni und Rangliste laufen, der Besuch zeigt eine fremde Sammlung.

- [x] [Lune] Freunde-Faktor: 0 Freunde = 1, 1 = 1,1, 5 = 1,5, mehr bleibt bei 1,5; kaputte Zahl, negativ oder NaN = 1; Werte kommen aus `Data/Social`; DataCheck meldet kaputte Werte (`perFriendBp` und `maxBp` ganze Zahlen ab 1, `maxBp` mindestens `perFriendBp`).
- [x] [Lune] Wochenfortschritt (`Social.rollWeek`): neue Woche setzt die Basis, gleiche Woche Fortschritt = Wert minus Basis, nie negativ, kaputte Profildaten ergeben eine saubere Basis; Kontoalter der Freunde (`accountOldEnough`); Koloss: Schwellen mit `fairShare` folgen der Zahl der Gräber.
- [x] [Lune] Sammlungswert: Summe der Wertfaktoren aller verschiedenen bekannten Fundstücke; doppelte zählen einmal, unbekannte IDs und kaputte Werte zählen 0; leere Sammlung = 0.
- [x] [Lune] Wochenindex: Montag 0 Uhr UTC beginnt eine neue Woche, Ende ausschließend; kaputte Zeit ergibt nil; der Speichername enthält den Index.
- [x] [Lune] Ranglisten-Einträge werden bereinigt: nur ganze UserIds über 0, endliche Werte über 0, absteigend sortiert, höchstens 10, doppelte UserIds nur einmal.
- [x] [Lune] Auszug (Showcase): enthält nur bekannte Fundstück-IDs, nie mehr Einträge als der Katalog; ein kaputter oder fremder Auszug wird beim Lesen bereinigt; die Ansicht rechnet Wert und Set-Fortschritt mit `Logic/Collection`.
- [x] [Lune] Besuch: Der Client nennt nie einen Spieler, nur einen Platz (1 bis maxFriends) in der Freundesliste, die der Server selbst gebaut hat; ungültiger Platz, Text, NaN oder zu groß ergibt nil (notFriend); die Freundesliste wird bereinigt (ganze UserIds, einmal, Namen gekürzt, höchstens maxFriends); nichts Schreibendes in der Ansicht.
- [x] [Lune] RemoteSpec: `GetLeaderboard` und `GetFriends` (keine Argumente) und `ViewCollection` (Platz 1 bis maxFriends, keine UserId) mit Rate-Limit; der Wächtertest (policyguards) lässt die Zahl nur mit Begründung zu.
- [x] [Lune] Anbindung: `Friends` und `Leaderboard` stehen in `SERVICE_NAMES`, `Sand.optionsFor` multipliziert den Freunde-Faktor in den Münz-Faktor, Offline-Ertrag nutzt ihn nicht, DataStore-Aufrufe laufen in pcall, Studio nutzt einen eigenen Speichernamen.
- [x] [Shell] `security-reviewer` ohne offenen kritischen oder hohen Befund (mittlere Befunde behoben, Alt-Accounts und Wochenwertung als Designfragen offen, siehe architektur.md).
- [ ] [Studio] (nur mit echten Konten, negative Studio-UserIds gehen nicht) Zwei befreundete Spieler im Server: beide sehen +10 % Münzfaktor, beim Verlassen fällt er zurück.
- [ ] [Studio] Menü "Freunde": die Rangliste zeigt den eigenen Wert nach dem Fund eines neuen Stücks (nach höchstens 2 Minuten), der Reiter "Besuchen" zeigt die Sammlung eines Freundes, nicht befreundete Spieler lassen sich nicht ansehen.

## 6.1 Exploit-Review

Plan: Claude-Dokument "Paket 6.1: Exploit-Review, Plan". Fertig, wenn: Die Review-Liste ist abgearbeitet.

- [x] [Shell] `security-reviewer` prüft alle Client-zu-Server-Remotes, Käufe, Speichern, Offline-Ertrag, Zeit, Sammeln und Verkaufen, Soziales; Bericht liegt in `docs/exploit-review.md`.
- [ ] [Lune] Für jeden bestätigten kritischen oder hohen Befund gibt es einen Test, der den Fehler vorher gezeigt hat und jetzt besteht.
- [x] [Shell] Kein offener kritischer oder hoher Befund; mittlere Befunde sind behoben oder mit Begründung als Entscheidung für Waltuh vermerkt.
- [ ] [Studio] Stichprobe: schnelles Mehrfachklicken auf Kaufen, Abholen und Öffnen bucht nie doppelt.
- [x] [Lune] Starterpaket (Befund 6.1, mittel): Erstkauf im Fenster gibt das volle Paket; ein zweiter Beleg, ein Beleg vor dem Auslöser und einer nach Fensterende plus Nachfrist (`receiptGraceMinutes`) geben nur `duplicateGems` Ersatz-Gems, keine Items, ohne den Merker "gekauft" zu ändern; Nachfrist-Grenzen; Kappung bei maxGems (auch 0 Gems); derselbe Beleg zweimal (nacheinander, gleichzeitig) und Speicherfehler buchen nie doppelt; zehn gleichzeitige Belege geben genau ein Paket; kaputte Uhr oder Daten: NotProcessedYet (tests/offers.spec.luau, "Einmalkauf auf dem Server").
- [x] [Lune] DataCheck: `duplicateGems` ganze Zahl von 0 bis maxGems und höchstens der Gem-Gegenwert des Produktpreises zum besten Paketkurs; `receiptGraceMinutes` ganze Zahl von 0 bis 60 (tests/data.spec.luau, "Angebote (4.5)").

## 6.3 Analytics

Plan: kurz in docs/analytics.md. Fertig, wenn: Die wichtigsten Zahlen sind einsehbar (Tutorial-Abbruch, Käufe, Sitzungslänge, Rückkehr im Creator Dashboard).

- [x] [Lune] Tutorial-Trichter: Schritt n wird mit Nummer und Name aus `Data/Tutorial` gemeldet, "fertig" als letzter Schritt; ein Schritt wird je Sitzung nur einmal gemeldet; kaputte Schritte ergeben nichts.
- [x] [Lune] Käufe: Neue Einträge im Kaufprotokoll werden genau einmal gemeldet (nach `purchaseId`), beim Laden bereits vorhandene nicht; kaputte Einträge werden übersprungen.
- [x] [Lune] Sitzungslänge in Eimern (unter 1 Min., 1 bis 5, 5 bis 15, 15 bis 30, 30 bis 60, über 60), kaputte Zahl ergibt nil; Rückkehr: neuer Spieler, Tage seit dem letzten Besuch (0 bis 30, gedeckelt).
- [x] [Lune] Zusatzfelder werden bereinigt: nur Text bis 100 Zeichen und endliche Zahlen, nie Spielernamen; Event-Namen kommen aus `Data/Analytics`, DataCheck prüft sie.
- [x] [Lune] Anbindung: Service `Analytics` steht in `SERVICE_NAMES`, jeder Aufruf von `AnalyticsService` läuft in pcall, in Studio wird nur geloggt, es gibt keine Remote.
- [ ] [Studio] Im Ausgabefenster erscheinen `[Analytics]`-Zeilen für Tutorial-Schritte, Testkauf (`DebugPurchase`), Sitzungsende.
- [ ] [Studio/Live] Im Creator Dashboard unter Analytics: Onboarding-Trichter, Wirtschaft (Gems) und Custom Events `session_start` und `session_end` sind sichtbar (erscheint mit Verzögerung).

## 6.4 Balancing

Plan: Simulation durch den `balance-analyst`, Bericht in docs/balance-6.4.md. Fertig, wenn: Kein Engpass, an dem Spieler hängen bleiben.

- [x] [Shell] Simulationsskript `tools/balance_sim.luau` läuft und nutzt die echten Module und Tabellen.
- [x] [Shell] Bericht mit Meilensteinen, Engpässen und Zahlenvorschlägen liegt vor; Waltuh entscheidet über die Zahlen.
- [x] [Lune] Angenommene Änderungen der Zahlen bestehen DataCheck und alle Tests. Angenommen (nach Waltuhs "was du am besten hältst"): D1 `maxCrystals` 5 Mio., D2 Saugroboter 700.000 und Großmaschine 30 Mio. (in `Tools` und `UpgradeTree`), Zielzeiten in `tests/skilltree.spec.luau` auf 16:33 und 21:19.
- [ ] [Offen, Entscheidung] D3 (Ruinen-Ast mit 18 Knoten) und die Logik-Vorschläge L1 bis L4 sind nicht umgesetzt, siehe docs/balance-6.4.md.
- [ ] [Studio] Laufweg zum Händler messen und im Skript `WALK` setzen; Lauf 1 soll mit den neuen Preisen etwa 28 bis 36 min dauern.

## Ego-Perspektive (Umstellung von dritter Person)

Fertig, wenn: Das Spiel läuft in der Ego-Perspektive, rechts unten ist die Hand mit dem Werkzeug (Schaufel), links unten die Hand mit dem Eimer, beide bewegen sich beim Graben und Laufen, und alle Menüs bleiben bedienbar. Vorbild: Waltuhs Referenzbilder vom 22.11.2026.

- [x] [Lune] Die Tabelle `Data/FirstPerson` ist fehlerfrei, jedes Werkzeug aus `Data/Tools` hat einen Eintrag, und `check` meldet fehlenden Eintrag, unbekanntes Teil, unbekannten Grabstil, falsches Sichtfeld, leere Tasten, fehlenden Standard, Periode 0, `fadeTo` außerhalb 0 bis 1, kaputte Teile (Form, Größe, Farbe, Bemalung), falschen Füllstand und Hände hinter der Kamera.
- [x] [Lune] Rechte Hand vorn rechts, Eimer vorn links. Hand und Schaufel ersetzen das Weltmodell, Maschinen bleiben in der Welt und die Hand hält die Fernsteuerung.
- [x] [Lune] Bewegung: im Stand ohne Graben am Anker, Schaufel sticht nach vorn unten und kommt zurück (kein Rückwärts-Stich), der Eimer wippt mit, Hand greift nach vorn unten, Fernsteuerung zittert unter 0,1 Studs, Wippen beim Laufen wächst mit der Geschwindigkeit, NaN und unendlich ergeben keine Bewegung.
- [x] [Lune] Nachziehen beim Umsehen: gegen die Drehung, begrenzt auf `maxDegrees`, klingt ab.
- [x] [Lune] Eimer: leer dünne Schicht, voll knapp unter dem Rand, halb voll in der Mitte, Werte außerhalb begrenzt, Kapazität 0 oder NaN ergibt leer.
- [x] [Lune] Maus: gesperrt ohne Fenster, Baum, Karte und Taste, jeder einzelne Grund gibt sie frei, nur Alt schaltet um.
- [x] [Lune] Eigene Maschine: Hand und Schaufel verdecken nichts, der Körper von Saugroboter und Mega-Maschine wird durchscheinend, Ketten neben dem Charakter bleiben sichtbar, Teile hinter oder hoch über dem Charakter zählen nicht, Drehungen werden mitgerechnet.
- [ ] [Studio] Spawn: Die Kamera sitzt im Kopf, Mausrad zoomt nicht heraus. Rechts unten Hand (Hautfarbe des Avatars), links unten Hand mit Eimer, wie auf den Referenzbildern.
- [ ] [Studio] Schaufel kaufen: Die Schaufel liegt in der rechten Hand, der Stiel zeigt zur Bildmitte, das Blatt nach vorn unten. Die Schaufel vor dem Charakter in der Welt ist für einen selbst weg.
- [ ] [Studio] Linke Maustaste halten (und Graben-Knopf am Handy): Hand greift, Schaufel sticht, Fernsteuerung zittert. Der Sand im Eimer steigt mit dem Tank und ist nach dem Verkaufen wieder unten.
- [ ] [Studio] Laufen, Springen, schnelles Umsehen: Hände wippen leicht und ziehen nach, nichts flackert. Umhang und Schärpe des eigenen Skins sind nicht im Bild.
- [ ] [Studio] Werkzeug-Wechsel bis zur Mega-Maschine: Die Kamera bleibt im Kopf, der Teil der Maschine direkt vor den Augen ist durchscheinend, das Loch vorn ist zu sehen.
- [ ] [Studio] PC: Fadenkreuz in der Mitte, Hinweis "Alt: Maus frei" für 10 Sekunden. Alt gibt die Maus frei, Menüleiste anklickbar, Alt sperrt wieder. Fenster (Zonen, Shop, Sammlung ...), Baum, Offline-Karte und Kisten-Reveal geben die Maus von selbst frei und sperren sie beim Schließen wieder. Fund-Karten beim Graben lassen die Maus gesperrt.
- [ ] [Studio] Handy (Emulator): Wischen dreht die Kamera, Steuerknüppel, Sprung- und Graben-Knopf und Menüleiste funktionieren wie vorher, die Hände verdecken keine Knöpfe.
- [ ] [Studio] Händlerstand: Der Prompt "Verkaufen" erscheint in der Ego-Perspektive und E verkauft.
- [ ] [Studio] Zweiter Spieler (Test mit 2 Spielern): Der andere sieht den ganzen Avatar mit Skin und Werkzeug, keine schwebenden Hände.
- [x] [Lune] Zielen beim Graben (`Logic/DigAim`): Für jedes Werkzeug gilt min < Arbeitsspitze < max, und das Loch erreicht den Charakter-Quader in keiner Richtung. Treffer in Reichweite: genau dort. Zu nah: auf min hinausgeschoben. Zu weit: auf max zurückgeholt. Seitlich oder hinter dem Charakter geht. Kein Treffer (Himmel): Arbeitsspitze in Blickrichtung. Ungültige Eingaben ergeben nil. `flowSpeed`: schnell genug für die Strecke, nie unter der Grundgeschwindigkeit.
- [ ] [Studio] Graben folgt dem Fadenkreuz: Nach links, rechts, nah und weit zielen, das Loch und der Staub entstehen dort. Vor die Füße zielen: Das Loch bleibt so weit weg, dass man nicht hineinfällt. In den Himmel zielen: Es wird vor einem gegraben. Mit Alt (freie Maus) folgt das Loch dem Mauszeiger. Ab der Eimerkette beginnt der Sandfluss der Maschine am Grabpunkt und fliegt zur Maschine.


## 6.4 L1: Münz-Faktor zählt nicht für Kristalle

Entscheidung (Waltuh: "was du am besten hältst", Empfehlung Koordinator): `runEarned` zählt den Münz-Faktor aus 2x-Pass und Münz-Boost nicht, damit sich Windkristalle nicht kaufen lassen (docs/balance-6.4.md, L1). Geändert: `Wind.credit` (optionaler `runAmount`), `Collecting.sell`, `Offline.apply`, `Sandstorm.runTotal`.

- [x] [Lune] Verkauf mit Münz-Faktor 3: Münzen mal 3, `runEarned` ohne Faktor (`tests/sandstorm.spec.luau`, `tests/perks.spec.luau`).
- [x] [Lune] Sandsturm-Vorschau mit und ohne Faktor zeigt dieselben Einnahmen und dieselben Kristalle.
- [x] [Lune] Offline mit 2x-Pass: Münzen höher, `runEarned` gleich wie ohne Pass (`tests/offline.spec.luau`).
- [x] [Lune] `Wind.credit` mit `runAmount`: höchstens der Betrag, 0 oder negativ zählt nichts, Münzen bleiben voll.
- [ ] [Studio] Mit 2x-Pass einen Sturm vorbereiten: Die Kristallvorschau ist gleich hoch wie ohne Pass, nur die Münzanzeige wächst schneller.

## 6.4 L2 und L4: Hinweis "Sturm lohnt sich" und Obergrenze

Entscheidung (Waltuh: "was du am besten hältst", Koordinator-Empfehlung): L2 und L4 aus docs/balance-6.4.md umsetzen. D3 (Ruinen-Ast) wartet auf den Studio-Test der Werkzeugpreise.

- L2: `Sandstorm.worthIt(profile, data, options)` ist wahr, wenn der billigste sichtbare Knoten mehr als `Economy.sandstorm.worthSeconds` (180) Verdienst bei jetziger Rate kostet, oder kein Knoten mehr sichtbar ist. `preview.worth` ist nur bei möglichem Sturm wahr. Das Sturm-Fenster zeigt dann "Jetzt lohnt sich ein Sturm."
- L4: Neuer Grund `maxReached`, wenn die Obergrenze den Sturm verhindert (gehaltene Kristalle am Maximum, oder der Gewinn läge nur wegen der Kappung unter `minCrystals`). Der Sturm bleibt gesperrt, das Fenster sagt "Maximum an Windkristallen erreicht".

- [x] [Lune] Obergrenze: knapp darunter und am Maximum ergibt `maxReached`, `requires` hat Vorrang, `apply` ändert nichts (`tests/sandstorm.spec.luau`).
- [x] [Lune] `worth`: kleine Schwelle wahr, große falsch, nur bei möglichem Sturm, ohne sichtbaren Knoten wahr, kaputte Schwelle nutzt 180 s, Lauf-Anfang ohne Hinweis.
- [x] [Lune] DataCheck meldet fehlendes oder falsches `worthSeconds` (0, negativ, über 3600, NaN, unendlich).
- [ ] [Studio] Sturm-Fenster: Hinweis "Jetzt lohnt sich ein Sturm." erscheint, wenn der nächste Knoten weit weg ist, und nicht zu Beginn eines Laufs.
