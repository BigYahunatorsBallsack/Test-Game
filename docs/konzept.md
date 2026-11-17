# Dune Baron: Konzept und Monetarisierung

Arbeitstitel, Stand 17.11.2026. Die Markenprüfung vor dem Launch steht noch aus. Die Fassung im Claude-Dokument "Sand-Inkremental (Roblox): Konzept & Monetarisierung" ist die Quelle. Diese Datei ist die Arbeitskopie für das Repo.

## Überblick

Ein Roblox-Inkremental-Spiel: Du sammelst Sand in einer endlosen Wüste, verkaufst ihn und rüstest von der bloßen Hand bis zur Riesenmaschine auf. Der Umsatz kommt aus Kisten mit offenen Quoten, Gamepasses, einem Saison-Pass und Zeitersparnis-Produkten. Trading gibt es nicht. Dieses Konzept ersetzt die frühere Schatzsuche.

- **Spielgefühl:** Man sieht sofort, dass jede Stufe größer ist als die vorige. Aus einer Handvoll Körner wird ein Eimer, dann ein Bagger, dann eine Maschine, die ganze Dünen frisst.
- **Zielgruppe:** Casual-Spieler, vor allem auf dem Handy, Sitzungen von 5 bis 10 Minuten, tägliche Rückkehr.
- **Abgrenzung:** Das Prinzip (sammeln, verkaufen, aufrüsten) ist frei, wird aber nicht 1:1 kopiert. Dune Baron bekommt eigene Welt, Namen, Figuren und Look. Es übernimmt weder Titel noch Texte noch den Sandwurm aus dem Teaser, den wir als eigenes Event neu gestalten.
- **Eigener Reiz:** Zusätzlich zum Sand gibt es Fundstücke mit Seltenheit und eine Sammlung. So hat das Spiel ein Ziel jenseits von "mehr Zahlen".

Alle Zahlen sind Startwerte zum Testen, keine Marktdaten.

## Kernschleife und Incremental-Mechanik

Ein Durchlauf dauert 20 bis 40 Sekunden und endet immer mit einer Belohnung: sammeln, verkaufen, aufrüsten.

1. **Sammeln:** Du hältst die Taste (am Handy: Daumen auf die Fläche) und der Sandzähler im Tank steigt. Die Rate hängt vom Werkzeug ab.
2. **Verkaufen:** Am Händlerstand wird der Tank zu Münzen. Die Sandsorte der Zone bestimmt den Preis.
3. **Aufrüsten:** Münzen gehen in den Skilltree (Rate, Tank, Verkaufspreis, Glück). Es sind immer nur die nächsten Knoten sichtbar.
4. **Fundstücke:** Beim Graben tauchen gelegentlich Fundstücke auf, mit Reveal und Seltenheit. Sie füllen die Sammlung.
5. **Sandsturm (Prestige):** Ab Zone 3 setzt du Münzen und Werkzeug zurück und bekommst Windkristalle für einen dauerhaften Bonus.

**Die ersten 2 Minuten:** Das erste Upgrade ist nach etwa 20 Sekunden bezahlbar, die Schaufel nach etwa 2 Minuten. Das zählt mehr als jede Feinheit der Balance.

- **Große Zahlen:** Sand und Münzen wachsen schnell in die Millionen und weiter. Die Anzeige nutzt K, M, B, T. Der Server rechnet mit Mantisse und Exponent, damit Anzeige und Rechnung auch jenseits von 10^15 stimmen.
- **Sandsturm-Bonus (Startwert):** Jeder Windkristall gibt +2 % auf alle Münzen. Der Wert wird im Balancing angepasst.
- **Offline:** Ein Begleiter sammelt weiter, wenn du weg bist (siehe Events und Retention).
- **Der Server entscheidet:** Der Client meldet nur "ich halte", "ich verkaufe" und "ich kaufe Knoten X". Mengen und Preise berechnet der Server aus Zeit und Stufen.

## Werkzeuge und Skilltree

Sechs Werkzeugstufen machen den Fortschritt sichtbar: Jede Stufe ist deutlich größer als die vorige und verändert, wie der Sand aussieht und sich bewegt.

| Stufe | Werkzeug | Sand pro Sekunde | Preis in Münzen | Sichtbarer Sprung |
| --- | --- | --- | --- | --- |
| 1 | Hand | 1 | 0 | Eine Handvoll Körner |
| 2 | Schaufel | 5 | 50 | Gräbt eine Mulde |
| 3 | Eimerkette | 25 | 600 | Band trägt Sand zum Tank |
| 4 | Mini-Bagger | 150 | 7.500 | Fahrzeug mit Staubwolke |
| 5 | Saugroboter | 900 | 90.000 | Rüssel saugt die Fläche leer |
| 6 | Großmaschine | 6.000 | 1.100.000 | Frisst ganze Dünen |

Alle Werte sind Startwerte für den ersten Test.

Die Werkzeugstufen sind Meilenstein-Knoten im Ast "Sammeln" des Skilltrees. Der Baum folgt diesen Regeln:

- **Sichtbarkeit:** Nur gekaufte und direkt erreichbare Knoten sind sichtbar. Alles dahinter bleibt im Nebel.
- **Äste:** Sammeln (Rate), Tank (Kapazität), Verkauf (Preisfaktor), Glück (Fundchance). Später kommt ein Ast für Begleiter.
- **Freischalt-Animation (etwa 1,2 Sekunden):** Der Knoten drückt sich ein, ein Ring bricht aus, ein Lichtimpuls läuft zu den Folgeknoten, die neuen Knoten blenden aus dem Nebel ein, die Kamera gleitet hin. Bei Meilensteinen kommt ein Aufhell-Puls dazu. Nach etwa zehn Käufen in einer Sitzung läuft eine kürzere Variante.
- **Daten:** Der Baum ist eine Tabelle (`UpgradeTree`). Der Client sendet nur `PurchaseNode(id)`, der Server prüft und bucht.

## Welt und Zonen

Fünf Zonen mit je eigener Sandsorte: Je weiter du kommst, desto mehr bringt jedes Korn. Eine Zone verlangt immer eine Knoten-ID aus dem Skilltree und nie eine feste Zahl, damit Baum-Updates die Freischaltung nicht brechen.

| Zone | Sandsorte (Preisfaktor) | Freischaltung | Besonderheit |
| --- | --- | --- | --- |
| Dünenmeer | Gelber Sand (x1) | Start | Einfache Funde, Tutorial |
| Oase | Roter Sand (x3) | Meilenstein Sammeln 1 | Regen erhöht die Fundchance |
| Canyon | Weißer Sand (x10) | Meilenstein Sammeln 2 | Tiefe Schichten mit seltenen Funden |
| Salzsee | Kristallsand (x40) | Meilenstein Sammeln 3 | Nebel versteckt Fundstellen |
| Ruinenstadt | Schwarzer Sand (x150) | Nach dem ersten Sandsturm | Mythische Funde |

**Fundstücke:** Beim Graben taucht gelegentlich ein Fundstück auf, mit Reveal. Jede Zone hat 30 Fundstücke in Sets zu je 5.

| Stufe | Farbe | Wertfaktor | Anteil |
| --- | --- | --- | --- |
| Gewöhnlich | Grau | x1 | 70 % |
| Ungewöhnlich | Grün | x4 | 22 % |
| Selten | Blau | x15 | 6 % |
| Episch | Lila | x60 | 1,6 % |
| Legendär | Orange | x300 | 0,35 % |
| Mythisch | Rot | x1500 | 0,05 % |

- **Sammlung:** Jedes neue Fundstück füllt einen Slot. Ein komplettes Set gibt einen dauerhaften Münzbonus, ein komplettes Zonenbuch einen Titel und einen Werkzeug-Skin.
- **Doppelte Funde:** Sie werden verkauft oder zum nächsten Set-Fortschritt verschmolzen.
- **Kein Zufall gegen Geld:** Fundstücke kommen nur durchs Spielen. Kein Kauf verändert ihre Quoten.

## Kisten, Quoten und Monetarisierung

Der Hauptumsatz kommt aus Gems für Kisten. Dazu kommen Gamepasses für Tempo, ein Saison-Pass und günstige Einstiegsprodukte. Alle Preise sind Startwerte und werden nach dem Soft-Launch getestet.

Kisten enthalten Skins, Begleiter und Werkzeug-Varianten mit kleinem Bonus (etwa +5 bis +25 % Sammelrate). Sie verändern weder die Quoten der Kisten noch die der Fundstücke. Alle Kisten, auch die Holzkiste für Münzen, gelten als bezahlte Zufallsitems, weil Boosts Münzen indirekt beschleunigen.

| Kiste | Preis | Inhalt |
| --- | --- | --- |
| Holzkiste | 25.000 Münzen | Einfache Skins und Begleiter |
| Eisenkiste | 100 Gems | Bessere Skins, Begleiter, Werkzeug-Varianten |
| Goldkiste | 400 Gems | Hochwertige Varianten, Legendäres und Mythisches |
| Event-Kiste | 400 Gems | Gleiche Quoten wie die Goldkiste, exklusiver Pool, nur in der Saison |

**Quoten pro Öffnung** (müssen vor dem Kauf im Spiel stehen):

| Seltenheit | Holzkiste | Eisenkiste | Goldkiste |
| --- | --- | --- | --- |
| Gewöhnlich | 60 % | 35 % | 0 % |
| Ungewöhnlich | 30 % | 40 % | 40 % |
| Selten | 9 % | 20 % | 40 % |
| Episch | 1 % | 5 % | 15 % |
| Legendär | 0 % | 0 % | 4,5 % |
| Mythisch | 0 % | 0 % | 0,5 % |

- **Pity:** Die Goldkiste garantiert Episch oder besser spätestens bei der 15. Öffnung und Legendär oder besser spätestens bei der 60. Der Zähler ist sichtbar und liegt auf dem Server. Jede Öffnung zählt, auch die Gratis-Kiste aus dem 10er-Paket.
- **Erwartungswert:** Ein Legendär-oder-besser-Treffer kommt im Schnitt nach etwa 20 Goldkisten, also rund 8.000 Gems.
- **10er-Paket:** Zehn kaufen, elf bekommen, mit denselben Quoten.

**Gem-Pakete** (Developer Products):

| Paket | Preis | Bonus gegenüber dem kleinsten Paket |
| --- | --- | --- |
| 100 Gems | 49 Robux | 0 % |
| 550 Gems | 249 Robux | 8 % |
| 1.200 Gems | 499 Robux | 18 % |
| 3.200 Gems | 1.199 Robux | 31 % |
| 7.000 Gems | 2.499 Robux | 37 % |

**Weitere Produkte:**

| Produkt | Art | Preis | Wirkung |
| --- | --- | --- | --- |
| Starterpaket | Einmalkauf, 24 Stunden nach dem ersten Selten-Fund | 149 Robux | 300 Gems, eine seltene Werkzeug-Variante, ein Begleiter |
| 2x Münzen | Gamepass | 399 Robux | Doppelte Münzen aus allen Verkäufen |
| Auto-Dig | Gamepass | 499 Robux | Das Werkzeug sammelt automatisch, solange du im Spiel bist. Die Offline-Grenze steigt von 4 auf 12 Stunden |
| Großer Tank | Gamepass | 199 Robux | Mehr Platz, seltener zum Händler laufen |
| Saison-Pass | Developer Product, 4 Wochen | 399 Robux | Premium-Spur mit Gems, Skins und festen Event-Items |
| Münz-Boost | Verbrauchsprodukt | 49 Robux | 30 Minuten doppelte Münzen |
| Skins und Event-Shop | Direktkauf | 99 bis 799 Robux | Reine Optik und limitierte Sammelstücke |

**Regeln für Angebote:** Sie erscheinen nach dem Reveal und nie davor, und sie blockieren das Spiel nicht. Der Shop zeigt immer Quoten und Kosten bis zur Pity-Garantie.

## Events und Retention

Das Spiel läuft in vierwöchigen Saisons mit eigener Event-Zone, Event-Kiste und Pass. Das gibt einen festen Update-Rhythmus und jede Saison einen neuen Kaufanlass.

| Woche | Inhalt | Wirkung |
| --- | --- | --- |
| 1 | Saisonstart: Event-Zone öffnet, Event-Kiste und Saison-Pass starten | Kisten- und Pass-Käufe |
| 2 | Server-Event "Der Koloss" am Wochenende | Spielzeit, Social |
| 3 | Neue Event-Items im Direktshop, Set-Aufgaben | Direktkäufe |
| 4 | Finale: letzte Chance auf die Event-Kiste, Leaderboard-Preise | Dringlichkeit, Rückkehr |

**Server-Event "Der Koloss":** Unter dem Sand liegt ein riesiger Steinkoloss. Alle Spieler eines Servers graben ihn gemeinsam aus, jedes gesammelte Korn in der Event-Zone füllt den Fortschrittsbalken. Bei 100 % bekommen alle im Server eine Belohnung, gestaffelt nach Beitrag. Das ist unser Gegenstück zum Sandwurm im Teaser: eigene Figur, gleicher Wow-Moment, gut für Trailer.

- **Begleiter und Offline:** Der Begleiter sammelt bis zu 4 Stunden Münzen, wenn du weg bist, aber keine Fundstücke ab Selten. Der Auto-Dig-Pass ergänzt ihn: automatisches Sammeln im Spiel und eine Offline-Grenze von 12 Stunden.
- **Daily Reward:** 7-Tage-Serie, an Tag 7 gibt es eine Eisenkiste gratis. In Regionen mit gesperrten Zufallsitems gibt es stattdessen ein festes Ausrüstungsstück.
- **Codes:** Gems und Boosts bei Meilensteinen wie Likes und Favoriten, als Hebel für YouTuber.
- **Freunde-Bonus:** 10 % mehr Münzen pro Freund im Server, höchstens 50 %.
- **Leaderboard:** Wertvollste Sammlung pro Woche, jeder kann die Sammlung eines Freundes besuchen.

## Policy, Technik, Risiken und Entscheidungen

Bezahlte Zufallsitems sind erlaubt, wenn die Quoten offengelegt und regionale Sperren eingehalten werden. Das gilt auch für Währung, die mit Robux gekauft wird. Die aktuellen Regeln vor dem Launch selbst nachlesen.

**Policy-Checkliste:**

- [ ] Quoten pro Kiste vor dem Kauf im Spiel anzeigen: [Roblox: Virtual Items](https://create.roblox.com/docs/production/monetization/virtual-items)
- [ ] `ArePaidRandomItemsRestricted` abfragen. Ist sie wahr, ohne Kisten spielen und einen Direktkauf-Shop anbieten: [Roblox: Paid Random Items](https://create.roblox.com/docs/en-us/production/monetization/paid-random-items)
- [ ] Keine Boosts, die Kistenquoten verändern
- [ ] Fragebogen zu Reife und Compliance ausfüllen
- [ ] Kein Tauschen oder Verkaufen von Kisten-Items und keine Auszahlung
- [ ] Keine Drittanbieter-Shops, die Items gegen echtes Geld ausliefern

**Technik (Kurzfassung):**

- Server entscheidet alles, der Client sendet nur Absichten. Jede Remote prüft Typ und Bereich und hat ein Rate-Limit.
- Spielstand als versioniertes Profil mit Migration. Käufe über `ProcessReceipt`, idempotent: erst speichern, dann `PurchaseGranted`.
- Offline-Ertrag wird beim Laden aus Zeitstempel und Obergrenze berechnet, nie vom Client gemeldet.
- Sandverformung: Der Sand ist echtes Terrain, und Löcher entstehen mit Terrain-Funktionen wie `FillBall`. Das passiert nur auf dem Client des Spielers, der Server zählt den Sand unabhängig davon. So belastet die Verformung weder Server noch andere Spieler, und der Sand wächst nach. Meines Wissens replizieren Terrain-Änderungen vom Client nicht. Das testen wir als erstes Risikopaket (1.4) am Handy. Das geteilte Event "Der Koloss" bekommt eine eigene, serverseitige Lösung.

**Risiken:**

- **Markt:** Sim-Spiele sind dicht besetzt. Eigener Look und starker erster Eindruck sind Pflicht.
- **Nähe zum Vorbild:** Eigene Namen, Figuren und Texte, kein Nachbau des Teasers.
- **Wirtschaft:** Ein zu schneller oder zu zäher Fortschritt zerstört die Motivation. Balancing ist ein eigenes Paket.
- **Retention:** Ohne Sammlung, Events und Daily Reward bleibt es bei "mehr Zahlen".

**Entscheidungen:**

- [x] Name: Dune Baron (Markenprüfung vor dem Launch noch offen)
- [x] Perspektive: dritte Person, wie in Roblox üblich. Sie zeigt Werkzeug und Größe der Maschinen gut, und Avatar-Skins sind ein Kaufanreiz
- [x] Optik: weich-realistisch wie im Teaser, mit Future-Beleuchtung, weichen Schatten, Bloom und Farbkorrektur. Am Handy läuft eine schlankere Stufe
- [x] Terrain-Verformung: ja, auf dem Client (siehe Technik)
- [x] Ads-Budget: kein Blocker, wird nach dem Soft-Launch festgelegt
- [ ] Prestige-Formel (Windkristalle) nach dem ersten Balancing
