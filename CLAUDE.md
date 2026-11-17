# Dune Baron (Arbeitstitel): Roblox-Sand-Inkremental-Spiel

Inkremental-Sim in dritter Person: Sand sammeln, verkaufen, mit immer größeren Werkzeugen aufrüsten, Fundstücke mit Seltenheit sammeln, Sandsturm (Prestige). Weich-realistische Optik, Sand als verformbares Terrain (nur auf dem Client). Monetarisierung über Kisten (Gems, Quoten sichtbar), Gamepasses, Saison-Pass. Kein Trading. Konzept: docs/konzept.md. Plan: docs/umsetzungsplan.md. Testfälle: docs/testfaelle.md.

## Technik-Regeln

- Luau mit `--!strict`. Rojo-Projekt, Code unter `src/` (server, client, shared, shared/Data).
- Der Server entscheidet alles. Der Client sendet nur Absichten, nie Werte. Jede Remote validiert Typ und Bereich und hat ein Rate-Limit.
- Datengetrieben: Preise, Quoten, Raten, Zonen, Fundstücke, Skilltree-Knoten stehen in Datenmodulen, nie im Logik-Code. Zonen verlangen Knoten-IDs, keine festen Zahlen.
- Große Zahlen: Sand und Münzen laufen über den Zahlentyp (Mantisse und Exponent), Anzeige mit K, M, B, T.
- Terrain-Verformung nur auf dem Client. Der Server zählt Sand und Münzen unabhängig davon.
- Spielstand: versioniertes Profil mit Migrationsfunktion, damit Updates alte Spielstände nicht brechen.
- Käufe: ProcessReceipt idempotent (PurchaseId speichern, erst nach dem Speichern PurchaseGranted).
- Kisten: Anzeige und Auswurf lesen dieselbe Quotentabelle. Pity liegt auf dem Server.
- Policy: Quoten vor dem Kauf anzeigen, `ArePaidRandomItemsRestricted` beachten, keine Tausch- oder Verkaufsfunktion für Kisten-Items.
- Konstanten für Animationen (Dauer, Easing, Anzahl) stehen oben im Script.
- Logik ohne Roblox-API (Zahlentyp, Quoten, Pity, Kaufabwicklung, Baum-Kauf, Offline-Ertrag) steht in reinen Modulen und wird mit Lune in der Shell getestet.

## Arbeitsweise und Modelle (bitte selbst einhalten)

- Standardmodell ist `opusplan`: Opus plant im Plan-Modus, Sonnet setzt um. Ein neues Arbeitspaket beginnt immer im Plan-Modus, erst nach meiner Freigabe wird Code geschrieben.
- Delegiere automatisch an die Subagenten:
  - Tabellen füllen, Fundlisten, Texte, Umbenennungen: `data-worker` (Haiku, low).
  - Käufe, ProcessReceipt, Gamepasses, Gems, Kisten-Logik: `payments-builder` (Opus, xhigh).
  - Prüfung von Remotes, Käufen, Speichern, Exploits: `security-reviewer` (Opus, xhigh, nur lesen).
  - Preise, Verdienstkurven, Quoten-Simulation: `balance-analyst` (Opus, high).
- Alles andere (UI, Animationen, Spielschleife, Events) macht die Hauptsitzung.
- Im Plan-Modus schlägst du die Testfälle des Pakets vor und legst sie in docs/testfaelle.md ab. Ein Arbeitspaket gilt als fertig, wenn diese Testfälle laufen und committed ist. Vor Käufen und Kisten läuft immer der `security-reviewer`.
- Beschreibe am Ende kurz, was geändert wurde, und gib eine kurze Studio-Checkliste entlang der Spalte "Fertig, wenn" im Umsetzungsplan.
