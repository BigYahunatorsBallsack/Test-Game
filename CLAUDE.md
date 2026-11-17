# Relic Hunters (Arbeitstitel): Roblox-Schatzsuche-Sim

Casual-Sim: Mit dem Metalldetektor Signale suchen, graben, Relikte mit Seltenheit finden, im Museum sammeln. Monetarisierung über Kisten (Gems, Quoten sichtbar), Gamepasses, Saison-Pass. Kein Trading. Konzept: docs/konzept.md. Plan: docs/umsetzungsplan.md.

## Technik-Regeln

- Luau mit `--!strict`. Rojo-Projekt, Code unter `src/` (server, client, shared, shared/Data).
- Der Server entscheidet alles. Der Client sendet nur Absichten, nie Werte. Jede Remote validiert Typ und Bereich und hat ein Rate-Limit.
- Datengetrieben: Preise, Quoten, Funde, Skilltree-Knoten stehen in Datenmodulen, nie im Logik-Code.
- Spielstand: versioniertes Profil mit Migrationsfunktion, damit Updates alte Spielstände nicht brechen.
- Käufe: ProcessReceipt idempotent (PurchaseId speichern, erst nach dem Speichern PurchaseGranted).
- Kisten: Anzeige und Auswurf lesen dieselbe Quotentabelle. Pity liegt auf dem Server.
- Policy: Quoten vor dem Kauf anzeigen, `ArePaidRandomItemsRestricted` beachten, keine Tausch- oder Verkaufsfunktion für Kisten-Items.
- Konstanten für Animationen (Dauer, Easing, Anzahl) stehen oben im Script.

## Arbeitsweise und Modelle (bitte selbst einhalten)

- Standardmodell ist `opusplan`: Opus plant im Plan-Modus, Sonnet setzt um. Ein neues Arbeitspaket beginnt immer im Plan-Modus, erst nach meiner Freigabe wird Code geschrieben.
- Delegiere automatisch an die Subagenten:
  - Tabellen füllen, Fundlisten, Texte, Umbenennungen: `data-worker` (Haiku, low).
  - Käufe, ProcessReceipt, Gamepasses, Gems, Kisten-Logik: `payments-builder` (Opus, xhigh).
  - Prüfung von Remotes, Käufen, Speichern, Exploits: `security-reviewer` (Opus, xhigh, nur lesen).
  - Preise, Verdienstkurven, Quoten-Simulation: `balance-analyst` (Opus, high).
- Alles andere (UI, Animationen, Spielschleife, Events) macht die Hauptsitzung.
- Ein Arbeitspaket gilt als fertig, wenn die Testfälle aus docs/konzept.md laufen und committed ist. Vor Käufen und Kisten läuft immer der `security-reviewer`.
- Beschreibe am Ende kurz, was geändert wurde und was ich im Studio testen soll.
