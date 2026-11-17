# Umsetzungsplan: Schatzsuche-Sim

Nov 17, 2026 · @Waltuh

## Ziel und Arbeitsteilung

Dieser Plan führt das ganze Spiel von der Einrichtung bis zum Launch, in acht Phasen mit drei Prüfstellen. Claude schreibt den Großteil des Codes, ChatGPT liefert Bilder und Texte, und die 3D-Modelle kommen aus Roblox' eigener Mesh-Generierung. Der Skilltree (Upgrades mit verborgenen Ästen und Freischalt-Animationen) ist Phase 2 und steht weiter unten im Detail.

- **Claude Code:** Luau-Code, Architektur, Skilltree-Server und -UI, Animationen, Kisten, Käufe, Tests.
- **ChatGPT:** Stil-Guide, Icons für die Knoten, UI-Rahmen, Konzeptbilder, Texte.
- **Roblox Studio:** Meshes per Mesh Generation, Zusammenbau der Szene, Playtests.
- **Du:** Look-Entscheidungen, Playtests, Abnahme jedes Arbeitspakets.

Eine Korrektur zur Annahme, ChatGPT sei für Modelle am besten: ChatGPT erzeugt nach meinem Wissen Bilder, aber keine fertig texturierten Roblox-Meshes. Dazu mehr unter Modellwahl.

## Gesamt-Roadmap

Der Weg zum Launch hat acht Phasen und drei Prüfstellen: Erst muss die Schleife Spaß machen, dann kommen Käufe, dann der Launch.

_(Diagramm: Gesamt-Roadmap · 8 Phasen, 3 Prüfstellen – nur in der Claude-Version des Dokuments)_

Aufwand: S = 1 bis 2 Tage, M = 3 bis 5 Tage, L = 1 bis 2 Wochen, jeweils Vollzeit mit KI-Hilfe. Zusammengezählt sind das grob 110 bis 150 Arbeitstage bis zum Soft-Launch, also etwa fünf bis sieben Monate Vollzeit, in Teilzeit entsprechend mehr. Das ist eine grobe Schätzung. Der Engpass sind meist Playtests, Assets und Feinschliff, nicht Claudes Codier-Tempo.

**Reihenfolge-Regeln:**

- Phase 1 kommt vor Phase 2, weil der Baum Münzen zum Ausgeben braucht.
- Phase 3 läuft parallel zu den Phasen 2 und 4.
- 4.1 kommt vor 4.2, denn Kisten brauchen Gems. 4.6 muss vor dem ersten echten Robux-Kauf fertig sein.
- 5.4 kommt vor 5.5, damit Events aus Daten laufen.
- Nach der Phase 5 baust du keine neuen Systeme mehr, nur noch Phase 6.

**Schnellster Weg zu einem echten Test:** Phase 0 und 1, dazu 2.1 bis 2.4, die Funde von Zone 1 (30 Stück) aus 3.1 bis 3.3 sowie 4.1, 4.2 und 4.6. Das ergibt ein spielbares Spiel mit Baum und Kisten, aber ohne Events, ohne Zonen 2 bis 5 und ohne Neustart. Damit holst du früh Rückmeldung, bevor du den Rest baust.

## Phase 0 und 1: Fundament und Kernschleife

Zuerst kommt ein Projekt, das Claude sauber bedienen kann, dann eine Schleife, die ohne Grafik schon Spaß macht. Alles Weitere baut darauf auf.

| Nr. | Paket | Wer, Modell, Effort | Aufwand | Fertig, wenn |
| --- | --- | --- | --- | --- |
| 0.1 | Umfang einfrieren: Preise, Quoten, Zonen aus dem Konzept in eine Tabelle übernehmen | Du, Claude Sonnet 5.5, medium | S | Eine Tabelle enthält alle Zahlen, die der Code liest |
| 0.2 | Projekt aufsetzen: Git, Rojo, Studio-Anbindung, Ordnerstruktur, CLAUDE.md | Claude Code, Opus 5.5, high | S | Eine Testdatei aus dem Projekt erscheint in Studio |
| 0.3 | Architektur: Module für Spielerdaten, Wirtschaft, Funde, Upgrades, Kisten, Shop, Events; Remotes; Versionierung der Daten | Claude Code, Opus 5.5, high, erst Plan | S bis M | Architektur ist im Projekt beschrieben, leere Module laufen |
| 0.4 | Stil festlegen: Stil-Guide, Farbpalette, Seltenheitsfarben | ChatGPT, GPT-6 und GPT Image 2.5 | S | Ein Stil-Guide, an dem sich alle Assets orientieren |
| 1.1 | Spielerdaten laden und speichern (Münzen, Gems, Inventar) | Claude Code, Opus 5.5, high | M | Daten überleben Neustart und Server-Wechsel |
| 1.2 | Fundsystem: Signale, Piepen nach Nähe, Fundauswahl nach Zone, Tiefe, Wetter | Claude Code, Sonnet 5.5, high | M | Funde entstehen nach den Anteilen der Tabelle |
| 1.3 | Grab-Minispiel und Reveal | Claude Code, Sonnet 5.5, high | M | Timing verändert den Fundwert, Reveal zeigt die Seltenheit |
| 1.4 | Rucksack, Verkauf, Münzen, einfaches HUD | Claude Code, Sonnet 5.5, medium | S bis M | Verkaufen füllt Münzen, voller Rucksack stoppt Funde |
| 1.5 | Zone 1 (Strand) mit Platzhalter-Grafik | Du in Studio, Claude Sonnet 5.5, medium | S | Spielbare Zone mit Boden, Wasser, Spawnpunkten |
| 1.6 | Die ersten 60 Sekunden: Tutorial, garantierter "Selten"-Fund, erstes Upgrade | Claude Code, Sonnet 5.5, high | S | Fremde finden den ersten Fund ohne Erklärung |

**Prüfstelle A (Fun-Test):** Erst wenn Fremde die Schleife ohne Hilfe spielen und weiterspielen wollen, geht es mit Phase 2 weiter. Ein schöner Baum rettet keine langweilige Schleife.

## Phase 2 und 3: Fortschritt und Look

Während Claude den Skilltree und die Zonen baut, entstehen parallel die Assets. So warten weder Code noch Grafik aufeinander.

| Nr. | Paket | Wer, Modell, Effort | Aufwand | Fertig, wenn |
| --- | --- | --- | --- | --- |
| 2.1 | Skilltree-Daten und Kauf-Server | Claude Code, Opus 5.5, high | M | Kauf und Laden funktionieren, die Testfälle bestehen |
| 2.2 | Tree-UI mit Zoom, Zuständen, Linien, Nebel | Claude Code, Plan mit Opus 5.5, Umsetzung mit Sonnet 5.5, high | L | Baum entsteht aus den Daten und ist am Handy bedienbar |
| 2.3 | Freischalt-Animationen und Sound | Claude Code, Sonnet 5.5, high, Feinschliff medium | M | Sequenz läuft flüssig, Meilenstein- und Kurzvariante stehen |
| 2.4 | Ausrüstung wirkt: Detektor, Schaufel, Rucksack | Claude Code, Sonnet 5.5, high | M | Werte aus dem Baum verändern das Spiel spürbar |
| 2.5 | Zonen 2 bis 5: Freischaltung über Meilenstein-Knoten-IDs, Wetter, Tiefenschichten | Claude Code, Sonnet 5.5, high | M | Alle Zonen sind mit Platzhaltern spielbar |
| 2.6 | Museumsbuch mit Sets und Bonus | Claude Code, Sonnet 5.5, medium | M | Neue Funde füllen Slots, der Set-Bonus wirkt |
| 2.7 | Neustart (Rebirth) mit Prestige-Marken | Claude Code, Opus 5.5, high | S bis M | Reset behält Ausrüstung und Museum, Bonus wirkt |
| 3.1 | Icons für Knoten, Kisten, Fundkategorien, UI-Rahmen | ChatGPT, GPT Image 2.5 | M | Alle Icons im einheitlichen Stil im Spiel |
| 3.2 | Meshes: Detektoren, Schaufeln, Begleiter, Kisten, erst 30 Funde, dann der Rest | Roblox Mesh Generation im Studio-Assistenten, Feinschliff in Blender | L | 150 Funde und alle Ausrüstungsmodelle im Spiel |
| 3.3 | Fundtabelle: 150 Funde mit Namen, Beschreibungen, Sets, Werten | Claude Haiku 5.5, low bis medium | S | Tabelle ist vollständig und das Spiel liest sie |
| 3.4 | Umgebung: Zonen-Art, Wetter-Effekte, Beleuchtung | Du in Studio mit den Assets | L | Jede Zone sieht eigenständig aus |
| 3.5 | Audio: Piepen, Graben, Reveal je Seltenheit, Musik | Sounds aus dem Creator Store, Lizenz prüfen | M | Reveal und Piepen klingen nach Belohnung |
| 3.6 | Handy-Durchgang: Layouts, Tippflächen, Lesbarkeit | Claude Code, Sonnet 5.5, high | M | Alle Menüs sind auf kleinem Bildschirm bedienbar |

## Phase 4 und 5: Monetarisierung und Retention

Geld fließt erst, wenn Käufe fehlerfrei laufen und Spieler zurückkommen. Deshalb kommt die Abrechnung vor den Events und wird mit dem höchsten Effort gebaut.

| Nr. | Paket | Wer, Modell, Effort | Aufwand | Fertig, wenn |
| --- | --- | --- | --- | --- |
| 4.1 | Gems und Gem-Pakete als Developer Products mit sicherer Kaufabwicklung | Claude Code, Opus 5.5, xhigh | M | Testkäufe gehen nie doppelt oder verloren |
| 4.2 | Kisten: Quoten, Pity, Öffnen auf dem Server, Reveal-Oberfläche | Claude Code, Opus 5.5, high | M | Simulation mit vielen Öffnungen bestätigt die Quoten |
| 4.3 | Kisten-Inhalte: Ausrüstungs-Drops, Skins, Verschmelzen | Claude Code, Sonnet 5.5, high | M | Drops greifen in die Ausrüstung, Duplikate lassen sich verschmelzen |
| 4.4 | Gamepasses (2x Münzen, Auto-Dig mit Online-Graben und längerer Offline-Grenze, Großer Rucksack) und Boosts | Claude Code, Sonnet 5.5, high | S bis M | Besitz wird auf dem Server geprüft und wirkt nach Neustart |
| 4.5 | Shop-Oberfläche und Angebote (Starterpaket-Auslöser, Reihenfolge) | Claude Code, Sonnet 5.5, high | M | Angebote erscheinen nach dem Reveal und blockieren nichts |
| 4.6 | Policy-Funktionen: Quoten-Anzeige, Regions-Fallback mit Direktkauf-Shop und Ersatz für die Tag-7-Kiste, aktuelle Policy-Seite lesen, Fragebogen | Claude Code, Opus 5.5, high | S bis M | Checkliste aus dem Konzept ist abgehakt |
| 4.7 | Quoten-Simulation mit sehr vielen Öffnungen als Skript | Claude Code, Sonnet 5.5, medium | S | Abweichung von der Tabelle ist klein |
| 5.1 | Daily Reward mit 7-Tage-Serie | Claude Code, Sonnet 5.5, medium | S | Serie zählt richtig, Tag 7 gibt die Gratis-Kiste oder in gesperrten Regionen den festen Ersatz |
| 5.2 | Codes-System | Claude Code, Sonnet 5.5, medium | S | Codes sind einmal pro Spieler einlösbar |
| 5.3 | Begleiter mit Offline-Ertrag (Münzen, etwa 4 Stunden Grenze, mit Auto-Dig länger, keine Funde ab "Selten") | Claude Code, Sonnet 5.5, high | M | Ertrag nach Abwesenheit stimmt und hält die Grenze ein |
| 5.4 | Event-Kalender als Daten: Saisons ohne Code-Änderung | Claude Code, Sonnet 5.5, medium | S | Neue Saison heißt neue Tabellenzeile |
| 5.5 | Saison-Pass, Event-Kiste, Event-Zone | Claude Code, Zahlen mit Opus 5.5 geplant, Umsetzung Sonnet 5.5, high | L | Saison 1 ist komplett spielbar und kaufbar |
| 5.6 | Server-Event "Weltfund" | Claude Code, Sonnet 5.5, high | M | Alle Spieler eines Servers graben gemeinsam ein Boss-Relikt aus |
| 5.7 | Freunde-Bonus, Leaderboard, Museum besuchen | Claude Code, Sonnet 5.5, medium | M | Boni und Rangliste laufen, der Besuch zeigt ein fremdes Museum |

**Prüfstelle B (Policy-Check, nach Phase 4):** Vor dem ersten echten Robux-Kauf sind Quoten-Anzeige, Regions-Fallback und Fragebogen erledigt, und Testkäufe laufen sauber.

## Phase 6 und 7: Härten, Soft-Launch und Launch

Vor dem Launch prüfst du, ob das Spiel sicher, flüssig und balanciert ist. Dann testest du mit kleinem Publikum, bevor du Ads-Budget einsetzt.

| Nr. | Paket | Wer, Modell, Effort | Aufwand | Fertig, wenn |
| --- | --- | --- | --- | --- |
| 6.1 | Exploit-Review: Remotes, Duplizieren, Spam, Käufe | Claude Code, Opus 5.5, xhigh, optional einmal Fable 5.2, max | M | Review-Liste ist abgearbeitet |
| 6.2 | Leistung und Handy-Tests: schwache Geräte, Speicher, Ladezeit | Claude Code, Sonnet 5.5, high | M | Das Spiel läuft flüssig auf einem schwachen Handy |
| 6.3 | Analytics: Tutorial-Abbruch, Käufe, Sitzungslänge, Rückkehr | Claude Code, Sonnet 5.5, medium | S | Die wichtigsten Zahlen sind einsehbar |
| 6.4 | Balancing: Wirtschaftstabelle, Preis- und Verdienstkurve | Claude, Opus 5.5, high | M | Kein Engpass, an dem Spieler hängen bleiben |
| 6.5 | Fehlerrunde mit Playtests von Fremden | Claude Code, Sonnet 5.5, medium | M | Keine bekannten Absturz- oder Verlustfehler |
| 6.6 | Soft-Launch mit kleinem Publikum und kleinem Ads-Budget, dann Auswertung | Du, Auswertung mit Claude Sonnet 5.5, medium | M | Rückkehr- und Kaufzahlen liegen vor |
| 7.1 | Store-Seite: Icon, Thumbnails, Titel, Beschreibung | ChatGPT, GPT Image 2.5 und GPT-6, du entscheidest | M | Seite ist fertig und wirkt auch klein auf dem Handy |
| 7.2 | Ads und Creator: Roblox Ads, Codes für YouTuber | Du, Texte mit GPT-6 | laufend | Kampagnen laufen, Codes sind verteilt |
| 7.3 | Saison 1 live, danach Rhythmus: wöchentliche Hotfixes, neue Saison alle vier Wochen | Claude Code, Sonnet 5.5, medium bis high | laufend | Die erste Saison endet ohne Notfall-Fix |
| 7.4 | Auswertung nach zwei Wochen: Preise, Quoten, Rückkehr nachjustieren | Claude, Opus 5.5, high | S | Eine Änderungsliste für die nächste Saison steht |

**Prüfstelle C (Soft-Launch):** Lege vor dem Test fest, welche Rückkehr- und Kaufzahlen dir reichen. Erst wenn sie erreicht sind und kein Verlustfehler offen ist, folgt der Voll-Launch.

## Skilltree-Design

Der Baum kennt für Spieler nur zwei Zustände: gekauft und direkt erreichbar. Alles dahinter bleibt unsichtbar, bis seine Voraussetzung gekauft ist.

- **Gekauft:** Voll sichtbar mit leuchtendem Rand und Effekt-Text.
- **Verfügbar:** Sichtbar mit Preis und pulsierendem Rand. Fehlt Geld, ist er ausgegraut und zeigt den fehlenden Betrag.
- **Verborgen:** Nicht im UI vorhanden. Optional enden Verbindungslinien im Nebel. So spürt man, dass es weitergeht, ohne dass Inhalte verraten werden.

_(Diagramm: Beispiel-Baum · 5 Knoten, 3 Zustände – nur in der Claude-Version des Dokuments)_

Im Beispiel sind Start und Reichweite I gekauft. Reichweite II, Grabtempo I und Platz I sind direkt erreichbar, alles Weitere bleibt verborgen.

**Aufbau:** Drei Äste (Detektor, Schaufel, Rucksack), später ein vierter für Begleiter. Etwa alle fünf Upgrades gibt es einen Meilenstein-Knoten, der eine Zone oder Funktion freischaltet und eine stärkere Animation bekommt. Kosten steigen pro Ebene, die Werte stehen in einer Tabelle und nicht im Code.

**Bedienung:** Ziehen zum Verschieben, Pinch oder Mausrad zum Zoomen. Nach einem Kauf gleitet die Kamera zu den neuen Knoten. Auf dem Handy sind Knoten groß genug zum Antippen.

**Freischalt-Animation** (etwa 1,2 Sekunden):

1. **Druck:** Der Knoten drückt sich ein und federt mit Überschwingen zurück.
2. **Burst:** Ein Ring und 12 bis 20 Partikel strahlen aus, dazu Sound.
3. **Energiefluss:** Ein Lichtimpuls läuft die Linien entlang zu den Folgeknoten.
4. **Auftauchen:** Die neuen Knoten blenden aus dem Nebel ein, von klein und transparent auf volle Größe.
5. **Kamera:** Sie gleitet so, dass die neuen Knoten im Bild sind.

**Meilenstein-Variante:** Zusätzlich ein kurzer Aufhell-Puls des ganzen Bildschirms, leichtes Kamerawackeln und ein Banner wie "Neue Zone".

**Gegen Ermüdung:** Nach etwa zehn Käufen in einer Sitzung läuft eine kürzere Variante (rund 0,6 Sekunden), damit schnelles Kaufen nicht nervt.

## Skilltree: technische Umsetzung

Der Baum ist eine Datentabelle, die Server und UI gemeinsam lesen. Ein neues Upgrade ist deshalb eine neue Zeile und kein neuer Code.

- **Daten:** Ein ModuleScript `UpgradeTree` mit id, Name, Beschreibung, Ast, Position im Baum, Voraussetzungen (ids), Kosten (Währung und Betrag), Effekt (Wert und was er ändert), Icon und Meilenstein-Flag.
- **Server entscheidet:** Der Client sendet nur `PurchaseNode(id)`. Der Server prüft Voraussetzungen und Kosten, bucht ab, speichert und berechnet die Werte des Spielers aus den gekauften Knoten neu.
- **Speichern:** Liste der gekauften ids im DataStore, am besten über ein Profil-Modul, das Sperren und Sicherungen übernimmt. Ein Versionsfeld sorgt dafür, dass spätere Baum-Änderungen alte Spielstände nicht brechen.
- **UI:** Eine ScreenGui mit Zeichenfläche. Knoten entstehen aus einer Vorlage, ihr Zustand wird aus den Spielerdaten abgeleitet. Linien sind schmale Frames mit Farbverlauf, der Lichtimpuls ist ein Tween des Verlauf-Versatzes.
- **Animationen:** TweenService für Größe, Transparenz und Kamera. Partikel als kleine Bilder im UI. Dauer, Easing und Anzahl stehen als Konstanten oben im Script, damit du sie schnell einstellen kannst.
- **Performance:** Nur sichtbare Knoten existieren als UI-Objekte. Das hält Handys flüssig und passt zum Verbergen der nächsten Ebenen.

**Testfälle:** stehen in `docs/testfaelle.md` (Abschnitt 2.1).

## Modellwahl

Nimm Sonnet 5.5 für den Großteil des Codes und Opus 5.5 für Architektur, Wirtschaft und Zahlungen. ChatGPT nutzt du nur für Bilder und Texte. Für 3D-Modelle ist Roblox' eigene Mesh-Generierung die bessere Wahl.

**Claude (in Claude Code):**

| Modell | Wofür | Effort |
| --- | --- | --- |
| Haiku 5.5 | Mechanische Fleißarbeit: Tabellen füllen, Umbenennen, Datenzeilen | low bis medium |
| Sonnet 5.5 | UI, Animationen, Spielschleife, Events, der Großteil des Codes | medium für Routine, high für UI und Animationen |
| Opus 5.5 | Architektur, Skilltree-Server, Kisten-Logik, Reviews | high, xhigh für Zahlungen und Exploit-Review |
| Fable 5.2 | Optionaler Einmal-Audit vor dem Launch | xhigh oder max |

Effort hat fünf Stufen: low, medium, high, xhigh, max. Du stellst ihn in Claude Code mit `/effort` ein. [Low bis xhigh bleiben über Sitzungen erhalten, max gilt nur für die aktuelle Sitzung](https://mcp.directory/blog/claude-code-effort-levels-explained-2026). Modell und Effort sind zwei getrennte Stellschrauben. Ein Praxismuster: [Sonnet mit mittlerem Effort für Routine, Opus mit hohem Effort bei Schwierigem, max nur selten](https://hackernoon.com/navigating-claude-code-models-tiers-and-effort). Ein praktischer Trick ist der Modus `opusplan`, bei dem Opus plant und Sonnet umsetzt.

Die Modellnamen folgen der aktuellen Anthropic-Liste. Drittseiten nennen teils ältere Versionen.

**ChatGPT und Roblox-Tools:**

| Aufgabe | Werkzeug | Hinweis |
| --- | --- | --- |
| Stil-Guide, Konzeptbilder, Knoten-Icons, UI-Rahmen | GPT Image 2.5 in ChatGPT | Das Modell ist laut [Modellübersicht](https://www.datalearner.com/en/ai-organizations/open-ai) seit September 2026 draußen. Transparenten Hintergrund anfragen und Ergebnis prüfen, alle Icons in einem Stil und einer Größe erzeugen |
| Texte: Item-Namen, Beschreibungen, Lore | GPT-6, Hauptmodell in ChatGPT | Laut [OpenAI-Release-Notes](https://help.openai.com/en/articles/9624314-model-release-notes) ist GPT-6 das aktuelle Hauptmodell. Claude kann das auch, dann brauchst du nur ein Tool |
| 3D-Meshes: Detektoren, Schaufeln, Funde | Mesh Generation im Roblox-Studio-Assistenten (Cube) | [Erzeugt voll texturierte 3D-Objekte aus einem Prompt](https://thenextweb.com/news/roblox-ai-assistant-agentic-tools-planning-procedural-models?type=Games). Es sind einzelne Meshes, Feinschliff geht in Blender oder Studio |

ChatGPT-Modellnamen ändern sich schnell, schau im Modellwähler nach, was dein Plan bietet.

## Arbeitsweise

Claude Code arbeitet in Dateien auf deinem Rechner, und Rojo synchronisiert sie live nach Studio. Beides läuft parallel. [Ohne Rojo liegt der Code nur auf der Festplatte](https://dev.to/juanzab/how-to-use-claude-code-with-roblox-studio-complete-guide-3n0a).

- **Studio-Anbindung:** Ein MCP-Server verbindet Claude mit Studio, sodass es Objekte anlegen, Code ausführen und je nach Server auch playtesten und Screenshots machen kann. Studio hat dafür eine [Quick-Connect-Funktion im Assistenten](https://skillselion.com/skills/nonlooped/roblox-suite/roblox-mcp).
- **Projektdatei (CLAUDE.md):** Kurzfassung des Spielkonzepts, Ordnerstruktur, Regeln (Server entscheidet alles, dem Client wird nie vertraut, Daten kommen aus Tabellen, Luau mit strikter Typprüfung) und die Befehle zum Testen. Claude liest sie in jeder Sitzung.
- **Pro Arbeitspaket:** Erst ein Plan mit Testfällen (abgelegt in `docs/testfaelle.md`), dann der Code, dann ein Commit. Kleine Pakete, ein Chat je Paket, damit der Kontext schlank bleibt.
- **Animationen abstimmen:** Du beschreibst das gewünschte Gefühl und schickst Screenshots oder einen Bildschirmmitschnitt. Rechne mit drei bis fünf Runden, und halte Dauer und Easing als Konstanten.
- **Käufe testen:** Developer Products und Gamepasses mit den Testkäufen von Studio prüfen, bevor echte Robux im Spiel sind.
- **Tests ohne Studio:** Logik ohne Roblox-API (Quoten, Pity, Kaufabwicklung, Baum-Kauf) läuft mit dem Luau-Runner Lune auch in der Shell. Dafür bleibt diese Logik in reinen Modulen ohne Roblox-Services.
- **Abnahme:** Jedes Arbeitspaket endet mit deinem Playtest, nicht mit Claudes Meldung "fertig". Claude liefert dafür eine kurze Studio-Checkliste entlang der Spalte "Fertig, wenn".

## Quellen

Aus Suchergebnissen, die Seiten selbst wurden nicht vollständig gelesen. Stand: 17.11.2026.

- [Claude Code Effort Levels Explained, mcp.directory](https://mcp.directory/blog/claude-code-effort-levels-explained-2026)
- [Navigating Claude Code models, tiers and effort, HackerNoon](https://hackernoon.com/navigating-claude-code-models-tiers-and-effort)
- [Model Release Notes, OpenAI](https://help.openai.com/en/articles/9624314-model-release-notes)
- [OpenAI models overview, DataLearner](https://www.datalearner.com/en/ai-organizations/open-ai)
- [Roblox gives its AI assistant the ability to plan, build and test, The Next Web](https://thenextweb.com/news/roblox-ai-assistant-agentic-tools-planning-procedural-models?type=Games)
- [Cube 3D Generation Tools and APIs, Roblox DevForum](https://devforum.roblox.com/t/beta-cube-3d-generation-tools-and-apis-for-creators/3558947)
- [How to Use Claude Code with Roblox Studio, DEV Community](https://dev.to/juanzab/how-to-use-claude-code-with-roblox-studio-complete-guide-3n0a)
- [Roblox MCP, Skillselion](https://skillselion.com/skills/nonlooped/roblox-suite/roblox-mcp)
