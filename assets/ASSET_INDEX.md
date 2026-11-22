# Dune Baron – lokales Asset-Bildpaket

Aktueller Studio-Place: **Every Last Grain**. Zusätzlich zum Bildpaket sind dort jetzt 164 statische 3D-Prototypen vorhanden: 14 Grundmodelle und 150 Funde.

## Aktuelle Studio-Modelle und UI-Komponenten

| Bereich | Aktuelle Dateien für Studio |
|---|---|
| Schaufel und Eimer | [First-Person-Starterset](models/first_person_starter/README.md) mit Griffpunkten und beiden Schaufelposen |
| Ausrüstung | [Vier First-Person-Maschinen](models/first_person_machines/README.md) mit Maßstab, Rig-IDs und Clips |
| Kisten | [Vier First-Person-Kisten](models/first_person_crates/README.md) mit Öffnungs- und Schließclips |
| Sandwurm | [GLB mit Rig und Angriff](models/sandwurm/README.md) und [Roblox-Clips für Ausbruch, Biss und Abtauchen](models/animation_clips/README.md) |
| UI | [Atlanten, Vorschauen und Übergabe](ui/README.md) für Menü, Werkzeugleiste und Fundkarte |

Die First-Person-Dateien sind die aktuellen Studio-Importe. Für die Maschinen gelten die Clips im jeweiligen RBXM und die dort dokumentierten Rig-IDs. Die Modelle werden in Studio eingesetzt. Anbindung an Kamera, Eingaben, Gameplay und HUD erfolgt im Spielcode.

## Stil

`reference/style_board_01.png` ist die akzeptierte Farbbasis. Für das Endprodukt gilt der anschließend gewünschte Roblox-Look: blockige Low-Poly-Formen, einfache matte Materialien und klare Details. Siehe `reference/STYLE.md`.

## Bestand

| Bereich | Einzeldateien | Ordner |
|---|---:|---|
| Werkzeug-Knoten | 6 | `icons/tools/` |
| Tank, Verkauf, Glück | 12 | `icons/storage/`, `icons/selling/`, `icons/luck/` |
| Währungen | 4 | `icons/currency/` |
| Kisten | 4 | `icons/crates/` |
| Knotenzustände und Seltenheiten | 9 | `icons/frames/` |
| Fundstücke | 150 | `icons/finds/` |
| Modell-/Weltreferenzen | 15 | `reference/tools/`, `reference/props/`, `reference/companions/`, `reference/zones/`, `reference/events/` |

Alle 185 Einzelicons sind quadratische RGBA-PNGs. Rastergrößen sind nativ 362 bis 512 Pixel; Fundicons sind 397 Pixel. Die Einzelicons wurden nicht künstlich auf 1024 Pixel hochskaliert. Für spätere große Darstellungen wären höher aufgelöste Einzelgenerierungen nötig. Quellenblätter liegen unter `icons/sheets/`. Alphakanäle wurden bei Bedarf von generiertem Hintergrundschleier bereinigt; unveränderte Quellen verbleiben im Imagegen-Ausgabeordner, frühe freigegebene Blätter zusätzlich unter `icons/sheets/sources/`.

## Funddaten

`reference/finds_draft.json` enthält 150 eindeutige IDs, deutsche Namen und Beschreibungen, sechs Sets zu fünf Funden pro Zone, Seltenheitsentwürfe und genaue Icon-Pfade. Dies ist ein gekennzeichneter Asset-Entwurf, keine verbindliche Spielkonfiguration. Es sind keine Verkaufspreise oder Dropquoten erfunden oder integriert worden. Vor Codeintegration mit der kanonischen Fundtabelle abgleichen.

## Store-Entwürfe

- [Aktuelle Bildauswahl](store/README-final.md) mit Studio-Icon (512 × 512) und Studio-Thumbnails für Graben und Harvester (je 1920 × 1080). Die Koloss-Vorschau gehört zum geplanten Event.
- [Store-Text](store/store_copy_draft.json) mit einer englischen Beschreibung für den aktuellen Spielstand, Alternativtexten, fünf Taglines und zehn Titelalternativen.
- [Stand der Namensprüfung](store/name_check_2026-11-17.txt). Eine Bestätigung der Namensverfügbarkeit steht aus.

## Studio-Übernahme

`reference/mesh_prompts_draft.json` enthält 14 Objektprompts und 150 Fundprompts mit Referenzpfaden. Die zugehörigen 3D-Prototypen liegen im Studio-Place unter `ServerStorage.DuneBaronAssetLibrary.Core` (14 Grundmodelle) und `ServerStorage.DuneBaronAssetLibrary.Finds` (fünf Zonen mit je 30 Funden). Die frühere Modellübersicht liegt gesichert unter `ServerStorage.DuneBaronWorldBackup.DuneBaron_AssetTests`. Frühere Varianten sind separat in `ServerStorage.DuneBaronAssetLibrary.EarlierCandidates` erhalten.

Die Modelle sind als Asset-Basis verankert. Finale Art-Abnahme, Rigging, Animationen und Spielintegration folgen als eigene Schritte. Einige bildgestützte Varianten bestehen aus nativen Roblox-Bauteilen statt aus einem einzelnen Mesh. Kanonische Place-Modelle beim Einbau klonen; ursprüngliche Asset-IDs allein enthalten lokale Farb-, Maßstabs- und Pivot-Anpassungen nicht immer.

`studio/find_model_map.json` ordnet alle 150 Funde ihren kanonischen Modellpfaden und Icons zu. `studio/generated_models.json` und `studio/additional_find_models.json` enthalten die Generierungsprotokolle. Zurückgewiesene Einzelfälle wurden mit präzisierten, sachlichen Objektbeschreibungen erfolgreich neu erzeugt.

Das [Begleiterpaket](models/companions_v1/README.md) enthält animierbare Rigs für Fennek, Wüstenmaus und Skarabäus mit je einer Ruhe-, Lauf- und Grabschleife.

Das [Kistenpaket](models/crates_v1/README.md) enthält vier Kisten mit Innenraum, Lichtstoß und je einem Öffnungs- und Schließclip.

Die [First-Person-Kisten](models/first_person_crates/README.md) enthalten dieselben vier Größen mit Einlagen, Griffpunkten am Riegel und je einem Roblox-Modell pro Kiste.

Der [Sandhändler](models/merchant_v1/README.md) steht mit Stoffmarkise, Münzschild und Waage am Verkaufsplatz des Startlagers.

Die [Koloss-Grabungsstätte](world/koloss_v1/README.md) verlinkt auf Sand- und Lichteffekte, Fortschrittsanzeige und Eventklänge.

Der [Vermessungsstand am Koloss](world/koloss_v1/vermessungsstand/README.md) ergänzt am Nordrand eine hölzerne Aussichtsplattform mit Treppe, Schattendach und Fernrohr.

Der [Prestige-Sandsturm](world/sandstorm_fx/README.md) hat einen kurzen Übergang mit Sandpartikeln, Windstoß und Windkristall-Anzeige.

Für die [Ruinenstadt](world/ruinenstadt_v1/README.md#wegmarken-und-grabungsspuren) gibt es Laternen, Siegelstelen und zwei Grabungsspuren als Roblox-Modellpaket mit Lageplan.

Das [Karawanenrelief vor der Ruinenstadt](world/ruinenstadt_v1/karawanenrelief/README.md) ergänzt die Anfahrt um eine geneigte Sandsteinstele mit Sonnensiegel und vergrabener Frachtzeichenreihe.

Die [Signalwarte am Wachtgrat](world/ruinenstadt_v1/wachtgrat/README.md) ergänzt am anderen Ende der Stadt ein rundes Aussichtsplateau mit Stufen, Kompassrose und alter Feuerschale.

Der [Innenraum des verschütteten Archivs](world/ruinenstadt_v1/archiv_innenraum/README.md) ergänzt ein Lesepult, ein Register aus 14 Tontafeln und Stützen unter den sichtbaren Ruinensteinen.

Das [Uferpaket der Oase](world/oase_v1/shore_fx/README.md) ergänzt einen Wasserlauf an der Quellterrasse, Wasserringe am Fischersteg und räumliches Quellplätschern.

Das [Schöpfrad am Ostufer der Oase](world/oase_v1/schoepfrad/README.md) ergänzt zwölf Tongefäße, eine Auffangrinne, ein Steinbecken und eine editierbare Drehschleife.

Die [Grabungsdetails im Canyon](world/canyon_v1/expedition_details/README.md) enthalten eine Fossilien-Werkbank und eine aufgebrochene Quarzader als GLB-Modelle.

Die [alte Lastenstation im Canyon](world/canyon_v1/lastenstation/README.md) ergänzt hinter dem Schichtentor eine Winde, einen beladenen Förderwagen und eine versandete Wartungsöffnung.

Die [Wrackbucht am Salzsee](world/salzsee_v1/wreck_bay/README.md) hat ein neues Frachtschiff und einen gebrochenen Anleger als GLB-Modelle.

Die [Windwarte am Salzsee](world/salzsee_v1/windwarte/README.md) ergänzt eine Aussichtsplattform, Kalksteinstufen und einen Windsack mit editierbarer Animationsschleife.

Das [Schritt-Effektpaket](world/sand_tracks/README.md) enthält Sohlenabdrücke, Staub und drei Schrittgeräusche je Sandsorte.

Das [Sandpaket für Hand und Schaufel](models/starter_sand_fx/README.md) verbindet beide R15-Einstiegsclips mit Staub, Sandladung und einem kurzen Auskippstrahl.

Das [Tragepaket der Schaufel](models/shovel_carry/README.md) bringt Trageanimationen für Stand und Lauf sowie passende Übergänge in den Zweihandgriff und zurück.

Das [First-Person-Starterset](models/first_person_starter/README.md) enthält Schaufel und Eimer als zwei Roblox-Modelle mit Griffpunkten und einer Ego-Vorschau.

Das [Fahrerkabinen-Paket](models/driver_cabs/README.md) enthält die Baggerkabine mit zwei Joysticks, den Harvester mit Lenkrad und sechs auf R15 abgestimmte Clips.

Die [First-Person-Maschinen](models/first_person_machines/README.md) enthalten Studio-Modelle und Ego-Vorschauen für Mini-Bagger, Saugroboter, Förderband und Dünen-Harvester.

Der [überarbeitete Saugroboter](models/vacuum_refinement/README.md) hat eine offene Düse, eine Drehkupplung und einen animierten Sandeinlauf hinter dem Tankglas.

Das [überarbeitete Eimerförderband](models/conveyor_refinement/README.md) hat eine Bodenaufnahme, ein breiteres Gestell und neun Eimer mit sichtbarer Sandladung.

Der [überarbeitete Dünen-Harvester](models/harvester_refinement/README.md) verbindet zwei Schneidwalzen mit einem sichtbaren Steigband und enthält die Fahr- und Fahrerclips.

Der [überarbeitete Mini-Bagger](models/excavator_refinement/README.md) hat einen Kippzylinder, flexible Leitungen am Armknick und eine Sandladung, die vor dem Auswurf zur Zahnkante rutscht.

Der [neue Maschinenhof](world/machine_yard/README.md) stellt alle vier Maschinen im selben Maßstab aus und ergänzt den Besucherweg um einen offenen Werkstattunterstand.

Die [verschüttete Vorratskammer](world/duenenmeer_v3/caravan_cache/README.md) ergänzt die Karawanenroute im Dünenmeer um eine ausgrabbare Ruine mit Vorratsnischen und Bodensiegel.

Das [Karawanenwrack](world/duenenmeer_v3/caravan_wreck/README.md) ergänzt die Strecke zwischen Signalturm und Oase um einen zerstörten Frachtenwagen, verstreute Ladung und eine Sandspur.

Das [Wegpaket am Oasenpass](world/duenenmeer_v3/oasis_approach/README.md) ergänzt die Rastbank und unterscheidet den Weg zum Oasentor vom Abzweig zum Wrack durch türkise und ockerfarbene Wegmarken.

Icons und Rahmen getrennt hochladen; Seltenheit ausschließlich über den Rahmen zeigen. Der Puls verfügbarer Knoten und andere UI-Animationen entstehen später in Roblox. Vor Veröffentlichung Store-Bilder und Beschreibung gegen den tatsächlichen Spielumfang abgleichen.

## Prüfung und Herkunft

Erzeugt mit dem eingebauten Imagegen-Werkzeug. Die vollständigen Prompts liegen jeweils in benachbarten `.prompt.txt`-Dateien. `asset_manifest.json` erfasst alle PNG-Pfade, Maße und Farbmodi. Geprüft wurden Bildlesbarkeit, 185 quadratische Einzelicons mit transparenten Ecken, 150 eindeutige Fund-IDs und alle 164 Modellprompt-Referenzen. `previews/finds_64px_dark.png` zeigt sämtliche Fundicons bei 64 Pixeln auf dunklem Grund.

Die Strukturprüfung bestätigt 150 eindeutige Fund-IDs, genau 30 Modelle je Zone und durchgehend verankerte Fundgeometrie. Der Desktop-Client-Ladetest für Grundmodelle und Dünenmeer-Vorschau hat 162 Asset-Ladevorgänge ohne Fehler abgeschlossen. Die kontrollierte Einzelansicht lag bei 87.650 Dreiecken und 95 Draw Calls; das ist kein Test auf einem echten Handy. Rohdaten: `studio/render_check_verified.json`.

Bilddateien und Metadaten liegen lokal; es wurde kein GitHub-Push durchgeführt. Die Mesh-Generierung hat einzelne Roblox-Modellassets erzeugt. Der Place wird als unveröffentlichte Entwurfsversion gespeichert; den letzten Save-Status dokumentiert `studio/generated_models.json`.

## Dünenmeer-Umgebung (18.11.2026)

`Workspace.DuneBaronWorld` enthält die begehbare erste Zone: Sandterrain, Spawn, Händlerlager, statische Maschinen und eine kleine Ausgrabung. `SellStand` und `SandField` sind als BaseParts passend zu den Datenmodulen des GitHub-Projekts markiert. Die Spielskripte wurden in diesem Schritt noch nicht nach Studio übernommen. Sammeln, Verkaufen und Upgrades sind daher noch nicht benutzbar.

Desktop geprüft: Spawn auf Boden, beide Laufwege erfolgreich, Grabstrahl trifft Sand, 64 Szenenasset-Ladevorgänge ohne Fehler, Bibliothek unverändert vollständig. Bericht: `assets/studio/dunes_zone_check.json`. Gespeichert als unveröffentlichte Place-Version 28.

Aufbau: `build_dunes_zone.luau`, anschließend einmalig `finish_dunes_zone.luau` im Edit-Modus ausführen. Nicht erneut auf die bereits gebaute Szene anwenden. `rollback_dunes_zone.luau` stellt Objekte, Lichtparameter und die gesicherte Terrainregion aus `ServerStorage.DuneBaronWorldBackup` wieder her. Deren Grenzen und die verbleibenden äußeren Dünenvolumen sind in `studio/README.md` dokumentiert. Für die vollständige Rückkehr steht Roblox-Version 26 zur Verfügung. Die Wiederherstellung wurde nicht ausgeführt.

## Sammelschleife integriert (18.11.2026)

Aktueller Stand: unveröffentlichte Studio-Version 30. Der GitHub-Code aus Commit `368d170dd6315fe2f0875f3bd5d4665c02f16adb` liegt jetzt lokal und mit 47 Skripten/Modulen im Place. Sammeln per linker Maustaste, Tank, Verkaufen per E, HUD, Tutorial und erste Upgrade-Käufe funktionieren im Desktop-Test. Die Fundmodelle und übrigen Assets bleiben erhalten; ihre Sammelmechanik ist noch nicht umgesetzt.

Lokaler Fix in `src/client/Controllers/Dig.luau`: sichtbaren Sandtreffer ins Voxel-Füllhöhenraster umrechnen, damit die Hand tatsächlich Mulden gräbt. Client-Verformung, unverändertes Serverterrain und vollständiges Nachwachsen wurden geprüft. Alle 14 Lune-Testdateien bestehen. Selene meldet 0 Fehler und 20 bestehende Stilwarnungen mit dem vorhandenen API-Cache. Details: `assets/studio/core_loop_check.json`.

Studio-API-Zugriff ist deaktiviert. ProfileStore verwendet seinen vorhandenen temporären Test-Speicher; Sitzungsfortschritt wird derzeit nicht dauerhaft gespeichert. Für einen späteren Persistenztest Studio-Zugriff auf API-Dienste in den Spieleinstellungen aktivieren. Es wurden keine Sicherheits- oder API-Einstellungen verändert und kein GitHub-Push ausgeführt.

Aktuell ergänzt (Place-Version 32): Sichtbare Werkzeugstufen folgen den gekauften Knoten; Schaufel und vier Maschinenmodelle erscheinen am Charakter. Noch keine Fahrsteuerung oder Maschinenanimation. Bericht: studio/equipment_check.json.

Aktuell ergänzt (Version 35): Arbeitsbewegungen für Schaufel und Maschinen mit weichem Start/Stopp. Bericht: studio/work_motion_check.json. Fahrsteuerung und Avatar-Armhaltung stehen noch aus.
