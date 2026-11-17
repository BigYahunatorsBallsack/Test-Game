# Umsetzungsplan: Dune Baron

Stand 17.11.2026. Der Plan führt das Spiel von der Einrichtung bis zum Launch, in acht Phasen mit drei Prüfstellen. Grundlage ist `docs/konzept.md`. Aufwand: S = 1 bis 2 Tage, M = 3 bis 5 Tage, L = 1 bis 2 Wochen, jeweils Vollzeit mit KI-Hilfe. Zusammen sind das grob 100 bis 140 Arbeitstage bis zum Soft-Launch, in Teilzeit entsprechend mehr. Der Engpass sind meist Playtests, Assets und Feinschliff, nicht das Codier-Tempo.

## Arbeitsteilung

- **Claude Code:** Luau-Code, Architektur, Skilltree-Server und -UI, Animationen, Terrain-Verformung, Kisten, Käufe, Tests.
- **Subagenten:** `data-worker` für Tabellen und Texte, `payments-builder` für Käufe und Kisten, `security-reviewer` für Prüfungen, `balance-analyst` für Zahlen. Details in `CLAUDE.md`.
- **ChatGPT:** Stil-Guide, Icons, UI-Rahmen, Konzeptbilder, Texte. Nach meinem Wissen liefert es Bilder, aber keine fertig texturierten Roblox-Meshes.
- **Roblox Studio:** Meshes per Mesh Generation, Beleuchtung, Szenenaufbau, Playtests.
- **Du:** Look-Entscheidungen, Playtests, Abnahme jedes Pakets. Playtests macht nur du, weder Claude Code noch die Subagenten können Studio starten.

## Reihenfolge-Regeln

- Phase 1 kommt vor Phase 2, weil der Baum Münzen zum Ausgeben braucht.
- **1.4 (Terrain-Verformung am Handy) ist das erste Risikopaket.** Fällt der Test durch, greift die Rückfallvariante (sinkende Fläche und Partikel), bevor weitere Systeme darauf bauen.
- Phase 3 läuft parallel zu den Phasen 2 und 4.
- 4.1 kommt vor 4.2, denn Kisten brauchen Gems. 4.6 muss vor dem ersten echten Robux-Kauf fertig sein.
- 5.4 kommt vor 5.5, damit Events aus Daten laufen.
- Nach Phase 5 entstehen keine neuen Systeme mehr, nur noch Phase 6.

**Schnellster Weg zu einem echten Test:** Phase 0 und 1, dazu 2.1 bis 2.4, die Optik der ersten Zone aus Phase 3 sowie 4.1, 4.2 und 4.6. Das ergibt ein spielbares Spiel mit Baum und Kisten, aber ohne Events, ohne Zonen 2 bis 5 und ohne Sandsturm.

## Phase 0 und 1: Fundament und Kernschleife

Zuerst ein Projekt, das Claude sauber bedienen kann, dann eine Schleife, die auch ohne Grafik Spaß macht.

| Nr. | Paket | Wer, Modell, Effort | Aufwand | Fertig, wenn |
| --- | --- | --- | --- | --- |
| 0.1 | Umfang einfrieren: Preise, Quoten, Raten, Zonen aus dem Konzept in Datentabellen | Du, `balance-analyst`, Opus 5.5, high | S | Eine Tabelle enthält alle Zahlen, die der Code liest |
| 0.2 | Projekt aufsetzen: Rojo, Studio-Anbindung, Ordnerstruktur, Lune für Tests | Claude Code, Opus 5.5, high | S | Eine Testdatei aus dem Projekt erscheint in Studio, ein Lune-Test läuft in der Shell |
| 0.3 | Architektur: Module für Spielerdaten, Wirtschaft, Sand, Funde, Upgrades, Kisten, Shop, Events; Remotes; Datenversion; Zahlentyp für große Werte | Claude Code, Opus 5.5, high, erst Plan | S bis M | Architektur ist im Projekt beschrieben, leere Module laufen |
| 0.4 | Stil festlegen: Stil-Guide, Farbpalette, Sandsorten, Seltenheitsfarben | ChatGPT, du entscheidest | S | Ein Stil-Guide, an dem sich alle Assets orientieren |
| 1.1 | Spielerdaten laden und speichern (Münzen, Gems, Inventar, Stufen) | Claude Code, Opus 5.5, high | M | Daten überleben Neustart und Server-Wechsel |
| 1.2 | Sammeln, Tank, Verkaufen mit serverseitiger Rate und Münzen | Claude Code, Sonnet 5.5, high | M | Rate und Preis folgen den Tabellen, der Client sendet keine Mengen |
| 1.3 | Zahlentyp (Mantisse und Exponent) mit Anzeige K, M, B, T | Claude Code, Sonnet 5.5, high | S bis M | Rechnen und Anzeige stimmen über 10^15 hinaus, Lune-Tests laufen |
| 1.4 | Terrain-Verformung auf dem Client: Löcher, Nachwachsen, Test am Handy | Claude Code, Opus 5.5, high | M | Löcher erscheinen nur beim eigenen Spieler und das Spiel läuft flüssig auf einem schwachen Handy |
| 1.5 | Zone Dünenmeer mit Platzhalter-Grafik, Händlerstand, Spawn | Du in Studio, Claude Sonnet 5.5, medium | S | Spielbare Zone mit Sand, Stand und Spawnpunkten |
| 1.6 | Die ersten 2 Minuten: Tutorial, erstes Upgrade nach etwa 20 Sekunden, Schaufel nach etwa 2 Minuten | Claude Code, Sonnet 5.5, high | S | Fremde finden die Schleife ohne Erklärung |

**Prüfstelle A (Fun-Test):** Erst wenn Fremde die Schleife ohne Hilfe spielen und weiterspielen wollen und die Terrain-Verformung am Handy läuft, geht es mit Phase 2 weiter. Ein schöner Baum rettet keine langweilige Schleife.

## Phase 2 und 3: Fortschritt und Look

Während Claude den Skilltree, die Werkzeuge und die Zonen baut, entstehen parallel die Assets.

| Nr. | Paket | Wer, Modell, Effort | Aufwand | Fertig, wenn |
| --- | --- | --- | --- | --- |
| 2.1 | Skilltree-Daten und Kauf-Server | Claude Code, Opus 5.5, high | M | Kauf und Laden funktionieren, die Testfälle bestehen |
| 2.2 | Tree-UI mit Zoom, Zuständen, Linien, Nebel | Claude Code, Plan mit Opus 5.5, Umsetzung mit Sonnet 5.5, high | L | Baum entsteht aus den Daten und ist am Handy bedienbar |
| 2.3 | Freischalt-Animationen und Sound | Claude Code, Sonnet 5.5, high, Feinschliff medium | M | Sequenz läuft flüssig, Meilenstein- und Kurzvariante stehen |
| 2.4 | Werkzeugstufen wirken und sind sichtbar (Hand bis Großmaschine) | Claude Code, Sonnet 5.5, high | M | Werte aus dem Baum verändern das Spiel, jede Stufe sieht deutlich anders aus |
| 2.5 | Zonen 2 bis 5: Freischaltung über Knoten-IDs, Sandsorten, Wetter | Claude Code, Sonnet 5.5, high | M | Alle Zonen sind mit Platzhaltern spielbar |
| 2.6 | Fundstücke, Reveal und Sammlung mit Sets und Bonus | Claude Code, Sonnet 5.5, high | M | Funde entstehen nach der Tabelle, Sets füllen sich, der Bonus wirkt |
| 2.7 | Sandsturm (Prestige) mit Windkristallen | Claude Code, Opus 5.5, high | S bis M | Reset behält Sammlung und Ausrüstungs-Skins, Bonus wirkt |
| 3.1 | Icons für Knoten, Kisten, Fundkategorien, UI-Rahmen | ChatGPT | M | Alle Icons im einheitlichen Stil im Spiel |
| 3.2 | Meshes: Werkzeuge, Maschinen, Begleiter, Kisten, erst 30 Fundstücke, dann der Rest | Roblox Mesh Generation im Studio-Assistenten, Feinschliff in Blender | L | 150 Fundstücke und alle Werkzeugmodelle im Spiel |
| 3.3 | Fundtabelle: 150 Fundstücke mit Namen, Beschreibungen, Sets, Werten | `data-worker`, Haiku 5.5, low bis medium | S | Tabelle ist vollständig und das Spiel liest sie |
| 3.4 | Look: Future-Beleuchtung, weiche Schatten, Bloom, Farbkorrektur, Sandmaterial | Du in Studio, Claude Sonnet 5.5, medium | L | Jede Zone sieht weich-realistisch und eigenständig aus |
| 3.5 | Audio: Sammeln, Graben, Reveal je Seltenheit, Musik | Sounds aus dem Creator Store, Lizenz prüfen | M | Reveal und Sammeln klingen nach Belohnung |
| 3.6 | Handy-Durchgang: Layouts, Tippflächen, schlankere Grafikstufe | Claude Code, Sonnet 5.5, high | M | Alle Menüs sind am kleinen Bildschirm bedienbar, das Spiel läuft flüssig |

## Phase 4 und 5: Monetarisierung und Retention

Geld fließt erst, wenn Käufe fehlerfrei laufen und Spieler zurückkommen. Deshalb kommt die Abrechnung vor den Events. Vor jedem dieser Pakete läuft am Ende der `security-reviewer`.

| Nr. | Paket | Wer, Modell, Effort | Aufwand | Fertig, wenn |
| --- | --- | --- | --- | --- |
| 4.1 | Gems und Gem-Pakete als Developer Products mit sicherer Kaufabwicklung | `payments-builder`, Opus 5.5, xhigh | M | Testkäufe gehen nie doppelt oder verloren |
| 4.2 | Kisten: Quoten, Pity, Öffnen auf dem Server, Reveal-Oberfläche | `payments-builder`, Opus 5.5, xhigh | M | Simulation mit vielen Öffnungen bestätigt die Quoten |
| 4.3 | Kisten-Inhalte: Skins, Begleiter, Werkzeug-Varianten, Verschmelzen | Claude Code, Sonnet 5.5, high | M | Drops greifen in die Ausrüstung, Duplikate lassen sich verschmelzen |
| 4.4 | Gamepasses (2x Münzen, Auto-Dig, Großer Tank) und Boosts | `payments-builder`, Opus 5.5, xhigh | S bis M | Besitz wird auf dem Server geprüft und wirkt nach Neustart |
| 4.5 | Shop-Oberfläche und Angebote (Starterpaket-Auslöser, Reihenfolge) | Claude Code, Sonnet 5.5, high | M | Angebote erscheinen nach dem Reveal und blockieren nichts |
| 4.6 | Policy-Funktionen: Quoten-Anzeige, Regions-Fallback mit Direktkauf-Shop, Fragebogen | Claude Code, Opus 5.5, high | S bis M | Checkliste aus dem Konzept ist abgehakt |
| 4.7 | Quoten-Simulation mit sehr vielen Öffnungen als Skript | `balance-analyst`, Opus 5.5, high | S | Abweichung von der Tabelle ist klein |
| 5.1 | Daily Reward mit 7-Tage-Serie | Claude Code, Sonnet 5.5, medium | S | Serie zählt richtig, Tag 7 gibt die Eisenkiste oder den Ersatz |
| 5.2 | Codes-System | Claude Code, Sonnet 5.5, medium | S | Codes sind einmal pro Spieler einlösbar |
| 5.3 | Begleiter mit Offline-Ertrag, Auto-Dig | Claude Code, Sonnet 5.5, high | M | Ertrag nach Abwesenheit stimmt und ist gekappt |
| 5.4 | Event-Kalender als Daten: Saisons ohne Code-Änderung | Claude Code, Sonnet 5.5, medium | S | Neue Saison heißt neue Tabellenzeile |
| 5.5 | Saison-Pass, Event-Kiste, Event-Zone | Claude Code, Zahlen mit Opus 5.5 geplant, Umsetzung Sonnet 5.5, high | L | Saison 1 ist komplett spielbar und kaufbar |
| 5.6 | Server-Event "Der Koloss" mit serverseitigem Fortschritt | Claude Code, Opus 5.5, high | M | Alle Spieler eines Servers graben gemeinsam, Belohnung nach Beitrag |
| 5.7 | Freunde-Bonus, Leaderboard, Sammlung besuchen | Claude Code, Sonnet 5.5, medium | M | Boni und Rangliste laufen, der Besuch zeigt eine fremde Sammlung |

**Prüfstelle B (Policy-Check, nach Phase 4):** Vor dem ersten echten Robux-Kauf sind Quoten-Anzeige, Regions-Fallback und Fragebogen erledigt, und Testkäufe laufen sauber.

## Phase 6 und 7: Härten, Soft-Launch und Launch

Vor dem Launch prüfst du, ob das Spiel sicher, flüssig und balanciert ist. Dann testest du mit kleinem Publikum.

| Nr. | Paket | Wer, Modell, Effort | Aufwand | Fertig, wenn |
| --- | --- | --- | --- | --- |
| 6.1 | Exploit-Review: Remotes, Duplizieren, Spam, Käufe, Offline-Ertrag | `security-reviewer`, Opus 5.5, xhigh, optional einmal Fable 5.2, max | M | Review-Liste ist abgearbeitet |
| 6.2 | Leistung und Handy-Tests: schwache Geräte, Speicher, Ladezeit, Terrain | Claude Code, Sonnet 5.5, high | M | Das Spiel läuft flüssig auf einem schwachen Handy |
| 6.3 | Analytics: Tutorial-Abbruch, Käufe, Sitzungslänge, Rückkehr | Claude Code, Sonnet 5.5, medium | S | Die wichtigsten Zahlen sind einsehbar |
| 6.4 | Balancing: Wirtschaftstabelle, Preis- und Verdienstkurve, Prestige-Formel | `balance-analyst`, Opus 5.5, high | M | Kein Engpass, an dem Spieler hängen bleiben |
| 6.5 | Fehlerrunde mit Playtests von Fremden | Claude Code, Sonnet 5.5, medium | M | Keine bekannten Absturz- oder Verlustfehler |
| 6.6 | Soft-Launch mit kleinem Publikum, dann Auswertung | Du, Auswertung mit Claude Sonnet 5.5, medium | M | Rückkehr- und Kaufzahlen liegen vor |
| 7.1 | Store-Seite: Icon, Thumbnails, Titel, Beschreibung, Markenprüfung | ChatGPT, du entscheidest | M | Seite ist fertig und wirkt auch klein auf dem Handy |
| 7.2 | Ads und Creator: Roblox Ads, Codes für YouTuber | Du, Texte mit ChatGPT | laufend | Kampagnen laufen, Codes sind verteilt |
| 7.3 | Saison 1 live, danach Rhythmus: wöchentliche Hotfixes, neue Saison alle vier Wochen | Claude Code, Sonnet 5.5, medium bis high | laufend | Die erste Saison endet ohne Notfall-Fix |
| 7.4 | Auswertung nach zwei Wochen: Preise, Quoten, Rückkehr nachjustieren | `balance-analyst`, Opus 5.5, high | S | Eine Änderungsliste für die nächste Saison steht |

**Prüfstelle C (Soft-Launch):** Lege vor dem Test fest, welche Rückkehr- und Kaufzahlen dir reichen. Erst wenn sie erreicht sind und kein Verlustfehler offen ist, folgt der Voll-Launch.

## Modellwahl

Sonnet 5.5 schreibt den Großteil des Codes, Opus 5.5 übernimmt Architektur, Wirtschaft und Zahlungen. ChatGPT nutzt du nur für Bilder und Texte. Für 3D-Modelle ist die Mesh-Generierung im Roblox-Studio-Assistenten die bessere Wahl. Die Modellnamen folgen der aktuellen Anthropic-Liste, ChatGPT-Namen ändern sich schnell, schau im Modellwähler nach.

| Modell | Wofür | Effort |
| --- | --- | --- |
| Haiku 5.5 | Mechanische Fleißarbeit: Tabellen füllen, Umbenennen, Datenzeilen | low bis medium |
| Sonnet 5.5 | UI, Animationen, Spielschleife, Events, der Großteil des Codes | medium für Routine, high für UI und Animationen |
| Opus 5.5 | Architektur, Terrain-Prototyp, Skilltree-Server, Kisten-Logik, Reviews | high, xhigh für Zahlungen und Exploit-Review |
| Fable 5.2 | Optionaler Einmal-Audit vor dem Launch | xhigh oder max |

Effort hat fünf Stufen (low, medium, high, xhigh, max) und wird in Claude Code mit `/effort` eingestellt. Der Modus `opusplan` lässt Opus planen und Sonnet umsetzen.

## Arbeitsweise

- **Pro Arbeitspaket:** Erst ein Plan mit Testfällen (`docs/testfaelle.md`), dann der Code, dann ein Commit. Kleine Pakete, ein Chat je Paket.
- **Tests:** Reine Logik (Zahlen, Quoten, Pity, Kaufabwicklung, Baum-Kauf, Offline-Ertrag) läuft mit Lune in der Shell. Alles andere prüfst du im Studio-Playtest.
- **Abnahme:** Jedes Paket endet mit deinem Playtest anhand der Spalte "Fertig, wenn", nicht mit der Meldung "fertig".
- **Animationen:** Du beschreibst das gewünschte Gefühl und schickst Screenshots. Rechne mit drei bis fünf Runden. Dauer und Easing stehen als Konstanten oben im Script.
- **Käufe:** Developer Products und Gamepasses zuerst mit den Testkäufen von Studio prüfen, bevor echte Robux im Spiel sind.
