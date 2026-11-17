# Architektur: Dune Baron

Stand Paket 0.3. Grundlage: `docs/konzept.md`, `docs/umsetzungsplan.md`. Testfälle: `docs/testfaelle.md`.

## Ordner und Module

```
default.project.json     Rojo: Shared -> ReplicatedStorage, Server -> ServerScriptService, Client -> StarterPlayerScripts
src/shared/Data/         Datentabellen (Rarities, Tools, SandTypes, Zones, FindOdds, Finds, Crates, GemPacks, Products, Economy, UpgradeTree)
src/shared/Logic/        Reine Logik ohne Roblox-API (DataCheck, Validate, RateLimiter, Profile, Migrations, BigNum, PlayerSession)
src/shared/Net/          RemoteSpec: Liste aller Remotes mit Schema und Rate-Limit
src/server/              init.server.luau (Bootstrap), Services/ (8 Services), Net/Net.luau
src/client/              init.client.luau (Bootstrap), Controllers/ (Input, State)
ServerPackages/          Wally-Pakete für den Server (ProfileStore), eingecheckt
wally.toml               Wally-Abhängigkeiten
tests/                   Lune-Tests (*.spec.luau), run.luau (Testläufer), lib/expect.luau
```

Regeln:

- Datengetrieben: Preise, Quoten, Raten, Zonen, Knoten stehen in `src/shared/Data`, nie im Logik-Code. Quoten sind ganze Zahlen in Hundertstel-Prozent (10000 = 100 %). Farben sind Hex-Text (`#RRGGBB`), Roblox-Typen kommen in `Data` und `Logic` nicht vor.
- Module in `src/shared` laden sich per relativem Pfad-String (`require("../Data/Tools")`), damit Lune und Roblox (Require-by-String) dieselben Dateien laden. Die Module bleiben flach, es gibt keine `init.luau`-Ordner in `src/shared`.
- Server und Client liegen in anderen Services als Shared. Dort laden Skripte Shared-Module per Instanz (`ReplicatedStorage.Shared...`), nicht per Pfad-String.
- Balance-Startwerte (Grundpreis, Tank, Fundchancen, Daily Reward) stammen aus `docs/balance/phase0_startwerte.md`. DataCheck prüft beim Serverstart, dass sie gesetzt und positiv sind.

### Services (Server, feste Reihenfolge)

| Service | Zuständig für | Gefüllt in |
| --- | --- | --- |
| PlayerData | Profil laden, halten, speichern (ProfileStore) | 1.1 |
| Economy | Münzen und Gems buchen, Verkaufspreis, Boni | 1.2, 1.3 |
| Sand | Sammeln, Tank, Verkaufen | 1.2 |
| Finds | Fundstücke, Sammlung, Sets | 2.6 |
| Upgrades | Skilltree-Käufe, Zonen-Freischaltung, Sandsturm | 2.1, 2.5, 2.7 |
| Crates | Kisten öffnen, Quoten, Pity | 4.2, 4.3 |
| Shop | Käufe, Gamepasses, Policy-Funktionen | 4.1, 4.4, 4.6 |
| Events | Event-Kalender, Daily Reward, Koloss | 5.1, 5.4 bis 5.6 |

`init.server.luau` startet so: Daten prüfen (`DataCheck.run`, bei Fehlern Abbruch mit allen Texten), Remotes anlegen, alle 8 Services laden, alle `Init()`, dann alle `Start()`. Jeder Schritt wird im Output gedruckt.

### Controllers (Client)

`State` hält den vom Server gesendeten Zustand (`StateSync`) und die Meldungen (`Notify`). `Input` übersetzt Eingaben in Absichten (`SetCollecting`, `Sell`). `Hud` zeigt Münzen, Tank und Meldungen (schlichte Fassung bis zum UI-Paket).

## Datenfluss

Client -> Server: nur Absichten, nie Mengen oder Preise. Der Server berechnet alles aus Zeit, Stufen und Tabellen. Server -> Client: `StateSync` (Zustand zur Anzeige) und `Notify` (Meldungen).

Jede Client->Server-Remote durchläuft in `Net.on` vor dem Handler:

1. Profil geladen? (`PlayerData.isLoaded`, gesetzt in `PlayerData.Init`; vorher wird alles abgelehnt)
2. `Validate.check` gegen das Schema aus `RemoteSpec`: genaue Argumentzahl, Typ, NaN und Unendlich abgelehnt, Bereich, Länge, bekannte IDs.
3. `RateLimiter` (Token-Bucket pro Spieler und Remote).

`Net.init` verbindet jede Client->Server-Remote sofort mit dieser Prüfung (`OnServerEvent` bzw. `OnServerInvoke`), `Net.on` trägt nur den Handler ein (Fehler bei fehlendem Schema/Limit oder doppelter Registrierung). Besteht ein Aufruf die Prüfung, es gibt aber noch keinen Handler, wird er ohne Verstoß verworfen; RemoteFunctions antworten `{ ok = false, reason = "nicht verfügbar" }`. Verstöße werden verworfen und pro Spieler gezählt (`warn` mit Name und Grund), es gibt keinen Kick. Eine Remote ohne Schema oder Limit in `RemoteSpec` lässt sich nicht registrieren (`RemoteSpec.assertRegistrable` wirft einen Fehler).

## Remote-Tabelle

| Remote | Art | Richtung | Argumente | Limit |
| --- | --- | --- | --- | --- |
| SetCollecting | Event | Client -> Server | `holding: boolean` | 10 pro s |
| Sell | Event | Client -> Server | keine | 2 pro s |
| TravelZone | Function | Client -> Server | `zoneId: string` (höchstens 32 Zeichen, muss in `Zones` stehen) | 1 pro s |
| PurchaseNode | Function | Client -> Server | `nodeId: string` (höchstens 64 Zeichen, muss in `UpgradeTree` stehen) | 5 pro s |
| OpenCrate | Function | Client -> Server | `crateId` (aus `Crates`), `count` (ganze Zahl 1 oder 10) | 1 pro s |
| Prestige | Function | Client -> Server | keine | 1 pro 5 s |
| StateSync | Event | Server -> Client | Zustand (Paket 1.2) | kein Limit |
| Notify | Event | Server -> Client | Meldung | kein Limit |

Die Remotes liegen zur Laufzeit unter `ReplicatedStorage.Remotes` und werden aus `RemoteSpec.list` angelegt.

## Profil und Migration

Das Profil ist ein versionierter Datensatz (`Profile.luau`, aktuelle Version in `Migrations.CURRENT_VERSION`). Felder: `version`, `coins {m,e}`, `tank {m,e}`, `gems`, `nodes`, `zones`, `currentZone`, `finds`, `windCrystals`, `prestiges`, `pity`, `inventory {skins, companions, toolVariants}`, `receipts`, `boosts {coinsUntil}`, `daily {streak, lastDay}`, `lastSeen`, `createdAt`.

`Profile.migrate(data, migrations?)` gibt `(profile, status)` zurück:

- `"new"`: kein Profil vorhanden, es entsteht ein Standardprofil.
- `"ok"`: Profil ist aktuell oder wurde Schritt für Schritt migriert (`Migrations.steps[n]` hebt von Version n auf n + 1). Danach werden fehlende Felder tief mit Standardwerten gefüllt. Eine zweite Migration ändert nichts mehr.
- `"too_new"`: Das Profil hat eine höhere Version als der Server kennt. Es wird unverändert zurückgegeben und darf nicht gespeichert werden.

Weitere Regeln: Unbekannte Felder und unbekannte Knoten-IDs bleiben gespeichert und werden ignoriert (`Profile.ownedKnownNodes` filtert auf bekannte Knoten). Die Migration arbeitet auf einer Kopie. Fehlt ein Schritt, wirft sie einen Fehler, damit nichts Falsches gespeichert wird. Zu jedem Versionssprung gehört ein Schritt in `Migrations.steps` und ein Lune-Test.

## Laden und Speichern (Paket 1.1)

- Speicher: ProfileStore 1.0.3 (loleris) über Wally, DataStore `PlayerData_v1` (in Studio `PlayerData_Studio_v1`), Schlüssel `Player_<UserId>`. Laden gibt nach 120 s auf. ProfileStore übernimmt Sitzungssperre, Autosave und das Speichern beim Herunterfahren.
- Ablauf in `Logic/PlayerSession.luau` (rein, Lune-Tests mit Fake-Speicher in `tests/lib/fakestore.luau`): Sitzung öffnen, `Profile.migrate`, `Profile.sanitize`, dann gilt der Spieler als geladen.
- Profil zu neu, Öffnen fehlgeschlagen oder Migration mit Fehler: Spieler wird mit Meldung entfernt, die gespeicherten Daten bleiben unverändert.
- `Profile.sanitize` läuft beim Laden und vor jedem Speichern: Ein Feld mit falschem Typ oder einer Zahl NaN/unendlich wird einzeln auf den Standard gesetzt, Münzen/Tank ganz auf 0, ungültige Einträge in ID-Listen werden entfernt. Jede Reparatur erscheint als Warnung im Output.
- Schneller Rejoin auf denselben Server: Der neue Ladevorgang wartet, bis der alte abgebrochen ist (`isBusy`).
- Für Paket 4.1 (Käufe): Der Adapter braucht dann `Save` und `OnAfterSave`, damit `PurchaseGranted` erst nach dem Speichern kommt. Remote-Handler dürfen sich nicht auf Zustand verlassen, den `onLoaded`-Rückrufe erst nach einer Wartezeit setzen.
- Bekannte Grenze: Kommt ein Spieler zurück, während das letzte Speichern nach einem DataStore-Fehler noch wiederholt wird, können Änderungen seit dem letzten Autosave verloren gehen (selten, Prüfung in 6.1).
- Verlässt der Spieler das Spiel während des Ladens, wird die Sitzung sofort beendet. Übernimmt ein anderer Server die Sitzung, wird der Spieler hier entfernt.
- Vor jedem Speichern setzt der Server `lastSeen` (Grundlage für den Offline-Ertrag).
- Andere Services nutzen `PlayerData.get(player)`, `PlayerData.isLoaded(player)` und `PlayerData.onLoaded(fn)`.
- Ohne API-Zugriff in Studio nutzt ProfileStore einen Test-Speicher, der Server warnt dann im Output.
- Studio-Hilfe (nur in Studio): In der Befehlszeile (Ansicht Server) `game.Players.<Name>:SetAttribute("DebugCoins", 12345)` bzw. `"DebugGems"` setzt Münzen oder Gems im Profil.
- Wally-Pakete: `ServerPackages/` ist eingecheckt, damit `rojo serve` ohne Wally läuft. Nach einer Änderung an `wally.toml` einmal `wally install` ausführen.

## Sammeln, Tank, Verkaufen (Paket 1.2)

- Regeln in `Logic/Collecting.luau` (rein, Lune-Tests mit simulierter Uhr), der Service `Sand` schließt Remotes, Server-Uhr (`os.clock`), Händlerstand und `StateSync` an.
- Rate: Sand pro Sekunde des höchsten gekauften Werkzeugs (`Tools`, Knoten aus `UpgradeTree`; die Hand ist Start). Tank: `Economy.startTankCapacity` (Tank-Knoten in 2.1, Gamepass-Faktor in 4.4 über `capacityMultiplier`). Preis: `Economy.baseCoinsPerSand` mal Preisfaktor der Sandsorte der aktuellen Zone (unbekannte Zone: Dünenmeer). Boni folgen mit ihren Paketen.
- Der Client schickt `SetCollecting(true)` beim Drücken und danach alle `Economy.collecting.holdRefreshSeconds`, beim Loslassen `SetCollecting(false)`. Der Server rechnet nur Zeit bis `holdTimeoutSeconds` nach der letzten Auffrischung ab. Spam erzeugt keinen zusätzlichen Sand, weil nur Server-Zeit zählt.
- Der Tank enthält nur ganze Körner, Bruchteile bleiben im Speicher des Servers (`carry`). Ein voller Tank stoppt das Sammeln, `Notify { kind = "tankFull" }`.
- Laufendes Sammeln rechnet der Server alle 0,25 s ab und schickt bei Änderungen `StateSync { coins, tank, capacity, rate, toolId, collecting, zoneId, pricePerSand }`.
- Verkaufen: `Sell` geht nur im Abstand `World.sellStand.rangeStuds` zur Mitte eines Teils mit dem Tag `World.sellStand.tag`. Fehlt ein solcher Stand im Workspace, legt der Server einen Platzhalter mit Prompt "Verkaufen" an (bis Phase 3). Meldungen: `sold`, `tankEmpty`, `sellTooFar`.
- Eingabe: linke Maustaste, Gamepad R2 oder Bildschirmknopf "Graben" (Handy). Die Taste E bleibt für Prompts frei.
- Sammeln nur mit lebendem Charakter und außerhalb der Reichweite eines Händlerstands (kein Sammeln direkt am Stand). Verkaufen verlangt, dass der Charakter auch bei der letzten Positionsprobe des Servers (alle 0,25 s) in Reichweite war, damit ein Teleport zum Stand für einen Aufruf nicht reicht.
- Noch offen: ob der Spieler beim Sammeln auf Sand der Zone steht (mit der Welt, Phase 3). In Paket 2.5 (Reisen) muss der Preis an die Zone gebunden werden, in der der Sand gesammelt wurde (oder an die Zone des Stands), sonst lässt sich billiger Sand in teuren Zonen verkaufen. Beim Verlassen können bis zu `holdTimeoutSeconds` Sand fehlen.

## Zahlentyp

`BigNum = { m: number, e: number }` (Wert = m * 10^e, Mantisse in [1, 10)). Paket 0.3 lieferte `new`, `zero`, `serialize` und `deserialize`, Paket 1.2 `add`, `sub`, `mul`, `mulNumber`, `div`, `compare`, `lt`, `eq`, `max`, `min`, `floor` und `toNumber`. Die Mantisse wird auf 14 Nachkommastellen gerundet, damit ganze Zahlen ganz bleiben; `toNumber` gibt ganze Zahlen unter 10^15 exakt zurück. Paket 1.3 lieferte `format(zahl, stellen?)` und die Tests in `tests/bignum.spec.luau`. Anzeige: deutsches Komma, Suffixe K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc (Konstante `BigNum.SUFFIXES`), ab 10^36 wissenschaftlich (`1,23e36`). Standard ist eine Nachkommastelle (`BigNum.DEFAULT_DECIMALS`, wählbar 0 bis 4), Endnullen entfallen (`1K`, `1,5K`), Hälften runden auf, und an den Stufengrenzen springt die Anzeige weiter (999,96K wird `1M`, nie `1000K`). Das HUD zeigt alle Münz- und Sandwerte über `BigNum.format`.

## Entscheidungen

- Meilensteine: `collect_tool_3` (Eimerkette) = Meilenstein 1 schaltet die Oase frei, `collect_tool_4` (Mini-Bagger) den Canyon, `collect_tool_5` (Saugroboter) den Salzsee. Werkzeugknoten heißen `collect_tool_2` bis `collect_tool_6`. Die Ruinenstadt verlangt `sandstorm_1`, den der erste Sandsturm vergibt. Zonen verweisen direkt auf diese IDs.
- Die Hand (Stufe 1) ist Startausrüstung ohne Knoten (`nodeId = "start"`).
- Spielstand mit ProfileStore (Paket 1.1), siehe oben.
- Remote-Verstöße: verwerfen und zählen, kein Kick.
- Unbekannte Knoten-IDs im Profil bleiben gespeichert und werden ignoriert.

## Testen

- `lune run tests/run` (im Projektordner): findet alle `*.spec.luau` unter `tests/`, startet jede Datei als eigenen Prozess und endet mit Code 1, wenn eine fehlschlug. Mit `LUNE_BIN` lässt sich ein anderes Lune-Programm wählen.
- Einzelne Datei: `lune run tests/data.spec.luau`.
- Tests schreiben: `local T = require("./lib/expect")`, dann `T.describe`, `T.it`, `T.expect(x).toBe/toEqual/toThrow/toBeCloseTo`, am Ende `T.finish()`.
- `mkdir -p build` und dann `rojo build -o build/test.rbxl` baut die Platzdatei (Rojo legt den Ordner nicht selbst an; `build/` wird nicht eingecheckt).
- `rojo serve` startet den Sync mit Studio (Rojo-Plugin verbinden). Playtest: Server und Client drucken je eine Startzeile.
- Format und Stil: `stylua src tests`, `selene src tests` (für selene einmal `selene generate-roblox-std` ausführen).
