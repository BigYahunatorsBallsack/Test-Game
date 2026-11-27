# Überarbeitung: Every Last Grain

Stand 27.11.2026. Anlass: Waltuh sagt, das Spiel sieht aus und spielt sich wie "AI slop", das ganze Gameplay muss überarbeitet werden. Dieses Dokument ist nur der Plan. Es ändert keinen Spielcode. Jedes Paket unten beginnt wie gewohnt mit einem eigenen Plan und eigenen Testfällen in `docs/testfaelle.md`, Code erst nach Freigabe. Gemergt wird in dieser Überarbeitung nur auf ein ausdrückliches "kannst mergen".

## 1. Kurzfassung

Das Spiel hat sehr viel Technik und sehr wenig Kern. Der Server, die Käufe, die Kisten, der Spielstand und die Datenprüfung sind solide. Aber das, was ein Spieler in der ersten Minute tut, ist: eine Taste halten, eine Zahl steigt, zum Stand laufen. Wo und wie man gräbt, spielt keine Rolle. Darüber liegen über zehn Menüs mit Kisten, Gems, Saison-Pass, Koloss, Codes, Angeboten und Daily Reward. Und was man sieht, sind Blöcke aus Code (Arme, Schaufel, Maschinen), dazu drei verschiedene UI-Stile nebeneinander.

Der Plan in einem Satz: **Erst das Graben selbst gut machen (Ort, Tiefe, Fundstellen, Rhythmus, Gefühl), dann einen einheitlichen Look aus echten Assets einbauen, und alle Zusatzsysteme so lange ausblenden, bis Fremde den Kern freiwillig weiterspielen.**

## 2. Diagnose

### 2.1 Warum es sich generisch spielt

1. **Graben ist nur Deko.** Der Client meldet nur "ich halte" (`SetCollecting`), der Server zählt gehaltene Sekunden mal Rate (`src/server/Services/Sand.luau`). Das Loch im Terrain ist reine Optik und wächst nach 8 Sekunden wieder zu (`Data/Terrain.regrow`). Ob man in eine Düne gräbt, in ein altes Loch oder in die Luft neben dem Feld: Es kommt dasselbe heraus. Es gibt keine Entscheidung, kein Können und nichts zu entdecken.
2. **Funde sind ein Würfel pro Sekunde.** `Finds.tickPlayer` würfelt die gesammelte Zeit (`FindOdds.findChancePerSecond`). Ein Fund liegt nicht im Sand, man findet ihn nicht, er passiert einem. Gerade das Fundstück sollte der eigene Reiz des Spiels sein (Konzept: "Ziel jenseits von mehr Zahlen").
3. **Fortschritt ist nur Multiplikator.** Die Werkzeugstufen ändern Rate und Lochgröße, die Knoten geben "+25 % Sand/s". Kein Upgrade ändert, wie man spielt. Die guten Ideen dafür gibt es schon, aber nur als Entwurf in der Werkstatt-UI ("Gadget-Fähigkeiten" wie Tiefstich und Kornprobe in `Interface/Workshop/Devices.json`). Im Spiel existieren sie nicht.
4. **Der Weg zum Stand ist tote Zeit.** Tank voll, laufen, verkaufen, zurücklaufen. Unterwegs passiert nichts.
5. **Meta vor Kern.** Prüfstelle A ("Fremde spielen die Schleife ohne Hilfe und wollen weiterspielen", `docs/umsetzungsplan.md`) wurde nie gemacht. Danach kamen vier Phasen Systeme obendrauf: Kisten, Gems, drei Gamepasses, Münz-Boost, Starterpaket, Saison-Pass, Event-Zone, Koloss, Daily, Codes, Freunde-Bonus, Rangliste, Offline-Begleiter, Angebote. Das sind die Bausteine jedes Roblox-Simulators. Genau diese Häufung ohne eigenen Kern fühlt sich nach Fließband an.

### 2.2 Warum es generisch aussieht

1. **Das Erste, was man sieht, sind Blöcke.** Die Ego-Ansicht (Arme, Schaufel, Eimer) baut `Controllers/FirstPerson` aus einfachen Parts (`Data/FirstPerson`). Die Vorschau `ego-vorschau/vorschau_schaufel.png` zeigt es: braune Quader als Arme, ein blauer Zylinder als Eimer, flacher Sand, leerer Himmel. Die Maschinen in `Data/ToolLooks` bestehen laut Kopfkommentar "nur aus einfachen Formen".
2. **Drei UI-Stile nebeneinander.**
   - Das HUD im Spiel ist die "schlichte Fassung bis zum UI-Paket" mit Platzhalterfarben (`Controllers/Hud.luau`, "vorläufig bis zum Stil-Guide").
   - `Interface/Theme.luau` ist ein bunter Cartoon-Stil (FredokaOne, dicke Konturen, Verläufe). Die fertigen Module dazu (`View`, `FindReveal`, `SaleFeedback`, `SandstormResult`, `ColossusStatus`) sind laut `assets/ui/README.md` nicht eingebaut: "Im Git-Stand lädt der vorhandene Bootstrap weiterhin den bisherigen HUD-Controller."
   - Die Werkstatt (`Interface/Workshop`) ist ein dunkler, flacher Dashboard-Stil.
   Elf weitere Menüs (Kisten, Gems, Saison-Pass, Daily, Codes, Social, Ausrüstung, Sammlung, Zonen, Sandsturm, Offline) bauen ihre Frames jeweils selbst im Code, mit eigenen Farben.
3. **Zwei Wahrheiten für den Baum.** Die Werkstatt hat einen eigenen Katalog (`Workshop/Catalog.luau`, "Game purchases still use Shared/Data/UpgradeTree") mit eigenen Preisen. Die Vorschau zeigt Saugroboter 90.000 und Großmaschine 1.100.000, das Spiel verlangt 700.000 und 30 Mio. Das wirkt unfertig, sobald es jemandem auffällt.
4. **Platzhalter im Live-Spiel.** Der Server legt Neon-Tore (`ZoneService`) und graue Händlerstand-Blöcke (`Sand.luau`, "Platzhalter angelegt (bis Phase 3)") an, wenn im Place keine echten liegen. Staub nutzt die Standardtextur `smoke_main.dds`.
5. **Welt-Pakete liegen bereit, sind aber nicht sicher im Place.** Dünenmeer V3, Oase, Canyon, Salzsee, Ruinenstadt, Maschinenhof, Koloss und Sandspuren liegen als Editor-Skripte und `.rbxm` unter `assets/world/`. Ob sie im Place `135831532782380` installiert sind, kann der Code nicht prüfen.
6. **Kein Name.** Repo, Bootstrap-Texte und Konzept sagen "Dune Baron", das Projekt heißt "Every Last Grain".

## 3. Ziel-Kernschleife

Grundidee: **Hand, dann Maschine, dann Landschaft.** Anfangs gräbst du selbst und liest den Sand. In der Mitte stellst du Maschinen auf, die für dich graben. Spät formt der Sandsturm die Karte neu und legt neue Schichten frei.

### 3.1 Die erste Minute (so soll es sich anfühlen)

1. Du stehst vor einer Düne. An einer Stelle glitzert es leicht.
2. Du stichst mit der Schaufel (Klick oder Tippen). Jeder Stich hebt sichtbar Sand ab, klingt satt und füllt den Eimer in deiner linken Hand.
3. Ein Stich im richtigen Moment (kurzes Zeitfenster, wenn die Schaufel unten ist) gibt einen "sauberen Stich": mehr Sand, anderes Geräusch, kleiner Funken. Halten geht weiter, gibt aber nur die Grundrate.
4. Unter der Oberfläche wird der Sand dunkler. Tiefere Schicht, mehr Wert pro Korn.
5. An der Glitzerstelle stößt die Schaufel auf etwas. Das Fundstück kommt sichtbar aus dem Sand, dann erst der Reveal.
6. Eimer voll. Der Stand ist nah, der Verkauf ist ein kurzer, befriedigender Moment (Münzen fliegen in den Zähler).
7. Erstes Upgrade nach etwa 20 Sekunden bleibt das Ziel.

### 3.2 Was das im System bedeutet

| Baustein | Heute | Ziel |
| --- | --- | --- |
| Graben | Taste halten, Server zählt Sekunden | Stich mit Zielpunkt. Der Client sendet "Stich bei Position X" (eine Absicht, kein Wert). Der Server prüft Reichweite, Takt und Lagerstätte und bucht. |
| Sandmenge | unbegrenzt, überall gleich | **Lagerstätten** je Zone mit Schichten (oben billig, unten wertvoll). Eine Stelle wird leer und füllt sich langsam nach, das bringt Bewegung über die Karte. |
| Funde | Würfel pro gesammelter Sekunde | **Fundstellen** liegen im Sand. Der Server legt sie pro Spieler und Lagerstätte fest, der Client zeigt Hinweise (Glitzern, Spuren). Wer dort gräbt, findet. Die Seltenheitsquoten bleiben dieselbe Tabelle. Eine kleine Grundchance pro Stich bleibt, damit es nie ganz trocken ist. |
| Können | keins | Takt beim Stechen ("sauberer Stich"), Hinweise lesen, tiefe Schichten wählen. |
| Upgrades | nur Prozent | Jede Werkzeugstufe bringt eine **Fähigkeit**, die das Spielen ändert. Die Entwürfe aus der Werkstatt werden echt: Kornprobe (Fundstellen kurz sichtbar), Tiefstich (eine Schicht tiefer), Doppeltakt, Querzug (breiter Stich), Wirbelsog, Pufferfahrt. Prozent-Knoten bleiben als Füllung dazwischen. |
| Maschinen | stehen neben dir und fahren mit | Ab der Eimerkette werden Maschinen zu **Anlagen**, die du auf eine Lagerstätte stellst. Sie graben sie ab, während du woanders stichst. Das ist der Idle-Teil des Spiels. |
| Weg zum Stand | tote Zeit | Stand näher an die Felder. Später bringt eine Anlage (Eimerkette, Förderband) den Sand selbst zum Stand. |
| Sandsturm | Reset, Kristalle | Bleibt. Zusätzlich verschiebt er Dünen und legt neue Lagerstätten und Fundstellen frei. |

Sicherheitsregeln bleiben unverändert: Der Server entscheidet, der Client sendet nur Absichten, jede neue Remote hat Typ-, Bereichs- und Ratenprüfung. Terrain-Verformung bleibt auf dem Client. Neu ist nur, dass der Server zusätzlich einen eigenen, groben Zustand der Lagerstätten führt (Füllstand je Stelle, kein Voxel).

## 4. Was bleibt

- Die ganze Server-Architektur: Services, Remotes mit `RemoteSpec`, Rate-Limits, `DataCheck`.
- Zahlentyp (`BigNum`), versioniertes Profil mit Migrationen, Speichern über ProfileStore.
- Käufe, Kisten, Quoten, Pity, Policy-Abfrage, Gems, Gamepasses. Diese Teile sind geprüft (Exploit-Review 6.1) und werden nicht angefasst, nur vorübergehend ausgeblendet.
- 150 Fundstücke mit Modellen, Icons, Sets und Sammlung.
- Fünf Zonen und Sandsorten, Skilltree-Daten, Sandsturm.
- Terrain-Verformung auf dem Client mit Bildraten-Wächter.
- Alle Welt-, UI- und Audio-Pakete unter `assets/`.

## 5. Was sich ändert

### 5.1 Gameplay

- Stich statt Halten (Halten bleibt als Grundrate, gut fürs Handy und für Barrierefreiheit).
- Lagerstätten mit Schichten und Erschöpfung.
- Fundstellen im Sand statt Sekundenwürfel.
- Fähigkeiten pro Werkzeugstufe statt nur Prozent.
- Maschinen als aufstellbare Anlagen.
- Stand näher am Feld, Transport später als Upgrade.
- Neues Balancing danach, weil sich die Rate grundlegend ändert.

### 5.2 Darstellung

- **Ein Stil.** Eine Theme-Datei für alle Menüs, ein HUD. Welcher Stil, entscheidet Waltuh (siehe Abschnitt 8).
- **Weniger auf dem Bildschirm.** Im Kern zeigt das HUD nur Münzen, Eimer (am Arm, nicht als Balken) und höchstens drei Knöpfe: Werkstatt, Sammlung, Shop.
- **Echte Modelle statt Code-Blöcke.** Arme, Schaufel, Eimer und Maschinen kommen als Modelle aus `ReplicatedStorage.Assets`. Der Code lädt sie, setzt sie an Befestigungspunkte und spielt Animationen ab. Die Blockformen bleiben nur als Rückfall im Studio, mit Warnung.
- **Gefühl (Juice).** Jeder Stich: Geräusch, kleiner Kamera-Ruck, Sandwurf mit eigener Textur, Eimer füllt sich sichtbar. Verkauf: Münzen fliegen in den Zähler. Fund: Objekt steigt aus dem Sand, dann Reveal.
- **Licht je Zone aus Daten.** Atmosphäre, Farbkorrektur, Nebel und Himmel je Zone in einem Datenmodul, der Client blendet beim Zonenwechsel über.
- **Keine Platzhalter im Live-Spiel.** Der Server legt Neon-Tore und graue Stände nur noch im Studio an. Fehlt im Live-Place etwas, bricht er laut ab, statt Platzhalter zu zeigen.
- **Ein Name** in allen Texten.

### 5.3 Vorübergehend ausblenden (Code bleibt)

Ein neues Datenmodul `Data/Features` schaltet ganze Systeme an und aus. Der Server registriert ausgeschaltete Remotes nicht, der Client zeigt die Menüs nicht. Vorschlag für den Neustart:

| System | Neustart | Wann wieder an |
| --- | --- | --- |
| Werkstatt (Skilltree), Sammlung, Sandsturm | an | – |
| Shop mit Kisten, Gems, Gamepasses | an, aber nur ein Knopf, keine Pop-ups | – |
| Angebote (Starterpaket-Hinweis) | aus | nach dem Fun-Test |
| Daily Reward, Codes | aus | nach dem Fun-Test |
| Saison-Pass, Event-Zone, Koloss | aus | erste echte Saison |
| Freunde-Bonus, Rangliste, Besuch | aus | Soft-Launch |
| Offline-Begleiter | aus | nach den Anlagen (Ü7), dann als Teil davon |

## 6. Pakete in Reihenfolge

Aufwand wie im Umsetzungsplan: S = 1 bis 2 Tage, M = 3 bis 5, L = 1 bis 2 Wochen. Spalte "Braucht" nennt, was nicht aus Code kommt.

| Nr. | Paket | Inhalt | Aufwand | Braucht | Fertig, wenn |
| --- | --- | --- | --- | --- | --- |
| Ü0 | Plan | Dieses Dokument | S | Waltuhs Entscheidungen (Abschnitt 8) | Entscheidungen stehen |
| Ü1 | Aufräumen und Schalter | `Data/Features`, Menüs und Remotes nach Schalter, HUD auf Münzen und drei Knöpfe, keine Platzhalter im Live-Server, ein Name | S | nichts | Spiel startet mit nur dem Kern sichtbar, Lune-Tests für die Schalter laufen |
| Ü2 | Lagerstätten und Stich (Server) | Neue Remote "Stich" mit Position, reines Modul für Lagerstätten, Schichten, Erschöpfung und Nachfüllen, Halten als Grundrate, Profil-Migration falls nötig | M bis L | nichts (security-reviewer vor Abschluss) | Lune-Tests: Reichweite, Takt, leere Stelle, Schichtwert, kein Wert vom Client |
| Ü3 | Fundstellen | Server legt Fundstellen je Spieler und Lagerstätte fest, Hinweise auf dem Client, Fund beim Graben an der Stelle, Grundchance bleibt, Quotentabelle unverändert | M | nichts (security-reviewer) | Lune-Tests: Stelle nur für den eigenen Spieler, Quoten gleich, kein Fund ohne Stich in Reichweite |
| Ü4 | Stich-Gefühl | Takt-Fenster "sauberer Stich", Sound, Kamera-Ruck, Sandwurf, Eimer-Füllung, Münzflug beim Verkauf, Fund steigt aus dem Sand | M | Stich-Animation der Arme (ChatGPT), Sounds (Waltuh oder Creator Store), Partikeltextur | Waltuh spielt 2 Minuten im Studio und es fühlt sich satt an |
| **A1** | **Mini-Fun-Test** | 3 bis 5 Fremde spielen 5 Minuten, nur Dünenmeer mit Hand und Schaufel | – | **Waltuh** | Mindestens die Hälfte spielt ohne Aufforderung weiter |
| Ü5 | Ein Look für die Oberfläche | Eine Theme-Datei, `Interface/View`, `FindReveal`, `SaleFeedback` einbauen, alte HUD-Farben weg, alle Menüs auf das Theme, Werkstatt liest `UpgradeTree` statt eigenem Katalog | M bis L | UI-Stilentscheid, Atlas-IDs hochgeladen | Kein Menü hat eigene Farben, Werkstatt zeigt Spielpreise |
| Ü6 | Modelle statt Blöcke | Lader für Arme, Werkzeuge und Maschinen aus `ReplicatedStorage.Assets` mit Befestigungspunkten (Grip, WorkPoint), Animationen über IDs in Daten, Blöcke nur als Studio-Rückfall | M | Modelle und Animationen (ChatGPT), Import in Studio (Waltuh) | Im Live-Place keine Code-Blöcke mehr sichtbar |
| Ü7 | Fähigkeiten pro Werkzeug | Kornprobe, Tiefstich, Doppeltakt, Querzug, Wirbelsog, Pufferfahrt als echte Knoten mit Wirkung, Abklingzeit auf dem Server | M | Icons sind da (Werkstatt), Effekt-Animationen (ChatGPT) | Jede Stufe ändert, wie man spielt, Lune-Tests je Fähigkeit |
| Ü8 | Maschinen als Anlagen | Eimerkette bis Großmaschine aufstellen, sie graben eine Lagerstätte ab, Förderung zum Stand, Offline-Ertrag hängt an Anlagen | L | Modelle (ChatGPT), Platzierung im Place prüfen (Waltuh) | Spieler kann weggehen und die Anlage arbeitet, Server zählt |
| Ü9 | Zonen-Look | Datenmodul für Licht und Atmosphäre je Zone, Überblendung beim Wechsel, Welt-Pakete V3 und folgende im Place installieren | M | **Waltuh in Studio** (Installation, Licht abnehmen) | Jede Zone sieht eigenständig aus, keine Neon-Tore |
| Ü10 | Balancing neu | Raten, Schichtwerte, Preise, Anlagen-Ertrag, Sandsturm neu rechnen | M | balance-analyst | Erstes Upgrade etwa 20 s, Schaufel etwa 2 min, kein Engpass |
| **A2** | **Prüfstelle A nachholen** | Fremde spielen 15 Minuten, auch am Handy | – | **Waltuh** | Wie im Umsetzungsplan |
| Ü11 | Systeme wieder anschalten | Je System ein kleiner PR: Angebote, Daily, Codes, dann Saison, Koloss, Social | je S | Studio-Check je System | Nach A2, eins nach dem anderen |

Warum diese Reihenfolge: Ü1 bis Ü4 machen den Kern spielbar und brauchen fast keine Assets, also kann ich sofort anfangen. A1 sagt früh, ob die Richtung stimmt, bevor Look-Arbeit darauf aufbaut. Ü5, Ü6 und Ü9 laufen parallel, sobald Assets da sind. Kisten und Pass kommen erst zurück, wenn der Kern trägt.

## 7. Risiken

- **Mehr Server-Arbeit pro Stich.** Ein Stich alle 0,3 bis 0,5 Sekunden pro Spieler ist für den Server kein Problem, wenn das Modul nur Füllstände rechnet. Ratenprüfung wie bei allen Remotes.
- **Takt am Handy.** Wenn das Zeitfenster am Handy frustriert, wird es breiter oder Halten gibt mehr. Das entscheidet A1.
- **Bestehende Spielstände.** Es gibt noch keine echten Spieler. Trotzdem jede Profiländerung mit Migration, wie bisher.
- **Assets kommen später als Code.** Deshalb lädt jedes Code-Paket Modelle über Namen und hat einen Studio-Rückfall. Kein Paket wartet auf ein Asset, um gemergt zu werden, nur um im Live-Place sichtbar zu sein.

## 8. Entscheidungen für Waltuh

1. **Kern:** Aktives Graben mit Stich, Schichten und Fundstellen (Empfehlung). Oder: Halten bleibt, nur Look und Gefühl werden besser.
2. **Bildstil:** Weich-realistisch wie im Konzept, oder kräftig stilisiert mit klaren Formen und warmen Farben (Empfehlung, weil das mit ChatGPT-Modellen und am Handy sicher sauber aussieht).
3. **UI-Stil:** Der dunkle, flache Werkstatt-Stil für alles (Empfehlung, er ist am weitesten fertig), oder der bunte Cartoon-Stil aus `Theme.luau`.
4. **Ausblenden:** Tabelle in 5.3 so übernehmen (Empfehlung), oder einzelne Systeme anlassen.
5. **Name:** "Every Last Grain" (Empfehlung, das Projekt heißt schon so) oder "Dune Baron".

Testfälle je Paket kommen wie gewohnt beim Plan des jeweiligen Pakets in `docs/testfaelle.md`.
