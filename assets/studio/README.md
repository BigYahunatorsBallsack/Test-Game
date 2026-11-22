# 3D-Asset-Basis

Place: **Every Last Grain**, ID `135831532782380`.

- `ServerStorage.DuneBaronAssetLibrary.Core`: 14 Grundmodelle für Werkzeuge, Händlerstand, Kisten, Begleiter und Koloss.
- `ServerStorage.DuneBaronAssetLibrary.Finds`: fünf Zonenordner mit je 30 Fundmodellen. Modellnamen entsprechen den IDs in `assets/reference/finds_draft.json`.
- `ServerStorage.DuneBaronWorldBackup.DuneBaron_AssetTests`: sichtbare Vorschau der Grundmodelle und Dünenmeer-Funde.
- `ServerStorage.DuneBaronAssetLibrary.EarlierCandidates`: aufbewahrte frühere Varianten, keine kanonischen Modelle.

Beim Einbau die kanonischen Modelle aus der Bibliothek klonen. `find_model_map.json` ist die Zuordnung von Fund-IDs, Modellpfaden und Icon-Dateien. `generated_models.json` und `additional_find_models.json` sind Protokolle, keine verbindliche Spielkonfiguration.

Alle Modelle sind statische Prototypen. Die Bibliothek enthält auch prozedurale Roblox-Modelle mit ihren Generator-Modulen. Finaler Art-Feinschliff, bewegliche Teile, Rigging, Animationen, Kollisionen und Anbindung an die Spiellogik sind noch gesondert umzusetzen. Es wurden keine Sammel-, Wirtschafts-, Kauf- oder Speichermechaniken ergänzt.

Der kontrollierte Desktop-Ladetest steht in `render_check_verified.json`. Er prüft eine Vorschauansicht und ersetzt keinen echten Handy- oder vollständigen Spieltest.

## Dünenmeer-Umgebung (18.11.2026)

`Workspace.DuneBaronWorld` enthält die begehbare erste Zone: Sandterrain, Spawn, Händlerlager, statische Maschinen und eine kleine Ausgrabung. `SellStand` und `SandField` sind als BaseParts passend zu den Datenmodulen des GitHub-Projekts markiert. Die Spielskripte wurden in diesem Schritt noch nicht nach Studio übernommen. Sammeln, Verkaufen und Upgrades sind daher noch nicht benutzbar.

Desktop geprüft: Spawn auf Boden, beide Laufwege erfolgreich, Grabstrahl trifft Sand, 64 Szenenasset-Ladevorgänge ohne Fehler, Bibliothek unverändert vollständig. Bericht: `assets/studio/dunes_zone_check.json`. Gespeichert als unveröffentlichte Place-Version 28.

Aufbau: `build_dunes_zone.luau`, anschließend einmalig `finish_dunes_zone.luau` im Edit-Modus ausführen. Nicht erneut auf die bereits gebaute Szene anwenden. `rollback_dunes_zone.luau` stellt Baseplate, ursprünglichen Spawn, Modellübersicht und Lichtparameter aus `ServerStorage.DuneBaronWorldBackup` wieder her; die Sicherung bleibt erhalten. Der Terrain-Snapshot umfasst x/z −256 bis 256 und y −64 bis 96. Außenliegende und tiefe Ausläufer der Dünen bleiben beim Skript-Rollback erhalten. Für eine vollständige Rückkehr zum vorherigen Place die Roblox-Version 26 verwenden. Die Wiederherstellung wurde nicht ausgeführt.

## Sammelschleife integriert (18.11.2026)

Aktueller Stand: unveröffentlichte Studio-Version 30. Der GitHub-Code aus Commit `368d170dd6315fe2f0875f3bd5d4665c02f16adb` liegt jetzt lokal und mit 47 Skripten/Modulen im Place. Sammeln per linker Maustaste, Tank, Verkaufen per E, HUD, Tutorial und erste Upgrade-Käufe funktionieren im Desktop-Test. Die Fundmodelle und übrigen Assets bleiben erhalten; ihre Sammelmechanik ist noch nicht umgesetzt.

Lokaler Fix in `src/client/Controllers/Dig.luau`: sichtbaren Sandtreffer ins Voxel-Füllhöhenraster umrechnen, damit die Hand tatsächlich Mulden gräbt. Client-Verformung, unverändertes Serverterrain und vollständiges Nachwachsen wurden geprüft. Alle 14 Lune-Testdateien bestehen. Selene meldet 0 Fehler und 20 bestehende Stilwarnungen mit dem vorhandenen API-Cache. Details: `assets/studio/core_loop_check.json`.

Studio-API-Zugriff ist deaktiviert. ProfileStore verwendet seinen vorhandenen temporären Test-Speicher; Sitzungsfortschritt wird derzeit nicht dauerhaft gespeichert. Für einen späteren Persistenztest Studio-Zugriff auf API-Dienste in den Spieleinstellungen aktivieren. Es wurden keine Sicherheits- oder API-Einstellungen verändert und kein GitHub-Push ausgeführt.

## Sichtbare Werkzeugstufen (18.11.2026)

Aktueller Stand ist unveröffentlichte Place-Version 32 mit 50 Skripten/Modulen. Alle sechs Stufen sind an die vorhandenen Käufe angebunden: Hand ohne Modell, Schaufel an der Hand und vier größere Arbeitsgeräte neben dem Charakter. Es sind visuelle Anbauten, noch keine fahrbaren oder animierten Maschinen. Kameraabstand, Bewegung, Graben und Respawn wurden im R15-Desktop-Test geprüft. Quellen bleiben in der Bibliothek unverändert; Bericht: equipment_check.json.

## Arbeitsbewegungen (18.11.2026)

Aktueller Stand: unveröffentlichte Version 35, 53 Skripte/Module. Schaufel, Eimer-Mesh, Baggerarm, Saugkopf und beide Walzen erhalten clientseitige Arbeitsbewegungen auf Grundlage von IsCollecting. Sie stoppen beim Loslassen oder vollen Tank. Vor jedem Simulationsschritt angewandte Posen verhindern das im Test gefundene Flackern. Bericht: work_motion_check.json; alle 15 Lune-Testdateien bestehen.

Grenzen: keine Fahrsteuerung oder Avatar-Armhaltung; die Eimerkette bewegt ein einzelnes Mesh. Quellenbibliothek und Sammelwerte bleiben erhalten. Die Tests ersetzen keinen echten Handy-, R6- oder Mehrspieler-Durchgang.
