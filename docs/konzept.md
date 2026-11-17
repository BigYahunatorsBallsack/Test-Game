# Schatzsuche-Sim: Konzept & Monetarisierung

Nov 17, 2026 · @Waltuh

## Überblick

Das Spiel ist ein Sammel-Simulator: Man sucht mit dem Metalldetektor, gräbt Relikte aus, jagt Seltenheiten und füllt ein Museum. Der Umsatz kommt aus Kisten, Zeitersparnis und limitierten Event-Items. Trading gibt es nicht.

Arbeitstitel: *Relic Hunters* (Platzhalter, vor dem Launch Namen und Marken prüfen).

- **Spielgefühl:** Ein Signal piept, man läuft hin, gräbt, und ein Reveal zeigt die Seltenheit des Fundes.
- **Zielgruppe:** Casual-Spieler, vor allem auf dem Handy, Sessions von 5 bis 10 Minuten.
- **Abgrenzung:** Angel- und Garten-Sims haben eine Handlung. Hier gibt es zwei (suchen, dann graben), Tiefenschichten und Wetter verändern die Funde, und das Museum gibt Sammlern ein Ziel jenseits des Geldes.
- **Geld verdienen:** Kisten mit Gems (Quoten sichtbar), Gamepasses für Tempo, Battle Pass und limitierte Event-Kisten für die Wiederkehr.

Alle Zahlen im Dokument sind Startwerte zum Testen, keine Marktdaten.

## Kernschleife

Ein Durchlauf dauert etwa 30 bis 45 Sekunden und endet immer mit einem Reveal. Das macht die Schleife kurz genug für das Handy und liefert alle paar Sekunden einen Belohnungsmoment.

1. **Scannen:** Der Detektor piept schneller, je näher ein Fund liegt. Man läuft dem Signal nach (10 bis 20 Sekunden).
2. **Graben:** Ein Timing-Minispiel (3 bis 5 Sekunden). Ein perfekter Treffer erhöht den Fundwert.
3. **Reveal:** Der Fund taucht mit Seltenheitsfarbe, Sound und Kamerawackeln auf. Das ist der Moment, den Spieler weitererzählen.
4. **Entscheiden:** Neue Funde kommen ins Museumsbuch, Doppelte werden verkauft.
5. **Aufrüsten:** Münzen gehen in Detektor-, Schaufel- und Rucksack-Upgrades oder in Kisten.

**Erste 60 Sekunden:** Der erste Fund ist garantiert "Selten" und zeigt das volle Reveal. Danach folgt direkt das erste Upgrade, damit die Spieler sehen, dass Münzen etwas bringen.

**Wiederkehr-Gründe:** tägliche Belohnung, ein unvollständiges Museumsbuch und die aktuelle Event-Zone.

## Zonen und Fundsystem

Zum Launch gibt es 5 Zonen mit je 30 Funden (150 Relikte), die in Sets von je 5 zusammengefasst sind. Jede Zone verändert, was und wo man findet.

| Zone | Freischaltung | Besonderheit |
| --- | --- | --- |
| Strand | Start | Einfache Funde, Ebbe zeigt neue Signale |
| Felder und Hügel | Meilenstein-Knoten `det_milestone_1` | Regen verstärkt Signale |
| Ruinenwald | Meilenstein-Knoten `det_milestone_2` | Nebel erhöht die Chance auf Seltenes |
| Wüstengrabung | Meilenstein-Knoten `det_milestone_3` | Sandsturm versteckt Signale, tiefe Schichten |
| Vulkaninsel | Nach dem ersten Neustart | Hier gibt es die mythischen Relikte |

Es gibt keine eigene Detektor-Stufe. Eine Zone verlangt die ID eines Meilenstein-Knotens im Detektor-Ast (zum Beispiel `requires = "det_milestone_1"`), keine Zahl. So bricht ein Umbau des Baums die Freischaltung nicht.

**Seltenheit beim normalen Graben** (kostenlos, ohne Kisten):

| Stufe | Farbe | Wertfaktor | Anteil |
| --- | --- | --- | --- |
| Gewöhnlich | Grau | x1 | 70 % |
| Ungewöhnlich | Grün | x4 | 22 % |
| Selten | Blau | x15 | 6 % |
| Episch | Lila | x60 | 1,6 % |
| Legendär | Orange | x300 | 0,35 % |
| Mythisch | Rot | x1500 | 0,05 % |

- **Tiefenschichten:** Oberfläche, Mitte, Tief. Seltene Funde liegen eher tief, dafür braucht man eine bessere Schaufel.
- **Wetter:** Pro Zone wechselt es alle paar Minuten und ist im Interface sichtbar, damit Spieler ihren Besuch planen.
- **Museumsbuch:** Jeder neue Fund füllt einen Slot. Ein komplettes Set gibt einen dauerhaften Münzbonus, ein komplettes Zonenbuch einen Titel und einen Detektor-Skin.

## Ausrüstung und Fortschritt

Die Ausrüstung bestimmt, wie schnell und wie tief man findet. Alles ist erspielbar, Kisten und Plässe verkürzen nur den Weg. Das hält das Spiel fair und die Kisten attraktiv.

| Slot | Wirkung | Woher |
| --- | --- | --- |
| Detektor | Reichweite, Signalstärke, Fundglück | Upgrades mit Münzen, stärkere Varianten aus Kisten |
| Schaufel | Grabtempo, erreichbare Tiefe | Upgrades mit Münzen, Varianten aus Kisten |
| Rucksack | Platz für Funde vor dem Verkauf | Upgrades mit Münzen, Erweiterung per Gamepass |
| Begleiter (Hund, Maulwurf, Rabe) | Findet Signale, sammelt offline Münzen (siehe Offline-Ertrag) | Kisten und Events |

- **Verschmelzen:** Drei gleiche Ausrüstungsstücke werden zur nächsten Stufe. Doppelte Kisten-Drops sind so nie wertlos.
- **Neustart (Rebirth):** Nach Zone 5 setzt man Münzen und Zonen zurück, behält Ausrüstung und Museum und bekommt einen dauerhaften Münzbonus plus Prestige-Marken für Spezial-Upgrades.
- **Freischaltungen:** Zonen hängen an Meilenstein-Knoten im Detektor-Ast, nicht an Robux-Käufen. So bleibt jeder Fortschritt erspielbar.

## Kisten und Quoten

Drei Dauer-Kisten und eine Event-Kiste liefern Ausrüstung und Skins. Es gibt zwei Währungen: Münzen (nur durch Spielen) und Gems (in kleinen Mengen durch Daily Rewards und Meilensteine, in großen per Robux). Alle Kisten werden wie bezahlte Zufallsitems behandelt, auch die Münz-Kiste, weil Boosts Münzen indirekt beschleunigen.

| Kiste | Preis | Inhalt |
| --- | --- | --- |
| Holzkiste | 2.500 Münzen | Einfache Detektoren, Schaufeln, Begleiter |
| Eisenkiste | 100 Gems | Bessere Ausrüstung und Skins |
| Goldkiste | 400 Gems | Hochwertige Ausrüstung, Legendäres und Mythisches |
| Event-Kiste | 400 Gems | Gleicher Preis und gleiche Quoten wie die Goldkiste, Pool mit exklusiven Event-Items, nur für die Saison. Der Anreiz ist die Exklusivität, nicht der Preis |

**Quoten pro Öffnung** (diese Werte müssen vor dem Kauf im Spiel stehen):

| Seltenheit | Holzkiste | Eisenkiste | Goldkiste |
| --- | --- | --- | --- |
| Gewöhnlich | 60 % | 35 % | 0 % |
| Ungewöhnlich | 30 % | 40 % | 40 % |
| Selten | 9 % | 20 % | 40 % |
| Episch | 1 % | 5 % | 15 % |
| Legendär | 0 % | 0 % | 4,5 % |
| Mythisch | 0 % | 0 % | 0,5 % |

- **Pity-System:** Die Goldkiste garantiert Episch oder besser spätestens bei der 15. Öffnung und Legendär oder besser spätestens bei der 60. Der Zähler ist sichtbar. Das schafft Vertrauen und gibt Spielern ein Ziel.
- **Erwartungswert:** Ein Legendär-oder-besser-Treffer kommt im Schnitt nach etwa 20 Goldkisten, also rund 8.000 Gems.
- **10er-Paket:** Zehn kaufen, elf bekommen, mit denselben Quoten. Die Gratis-Kiste zählt für Pity mit: Jede Öffnung zählt, egal wie sie bezahlt wurde, damit der angezeigte Zähler zu dem passt, was passiert.
- **Doppelte:** Gehen ins Verschmelzen (siehe Ausrüstung), nicht in den Müll.

## Monetarisierung

Der Hauptumsatz kommt aus Gems für Kisten, dazu kommen Gamepasses für Tempo, ein Saison-Pass mit Event-Kisten für die Wiederkehr und günstige Einstiegsprodukte. Alle Preise sind Startwerte und werden nach dem Soft-Launch getestet.

**Gem-Pakete** (Developer Products, beliebig oft kaufbar):

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
| Starterpaket | Einmalkauf, 24 Stunden nach dem ersten "Selten"-Fund | 149 Robux | 300 Gems, ein fester seltener Detektor, Begleiter Rabe |
| 2x Münzen | Gamepass | 399 Robux | Doppelte Münzen aus allen Verkäufen |
| Auto-Dig | Gamepass | 499 Robux | Graben läuft automatisch, solange man im Spiel ist, mit festem mittlerem Fundwert. Verlängert die Offline-Grenze (zum Beispiel auf 12 Stunden) |
| Großer Rucksack | Gamepass | 199 Robux | Mehr Platz, seltener Verkaufspausen |
| Saison-Pass | Developer Product, 4 Wochen | 399 Robux | Premium-Spur mit Gems, Skins und festen Event-Items |
| Münz-Boost | Verbrauchsprodukt | 49 Robux | 30 Minuten 2x Münzen |
| Wetter rufen | Verbrauchsprodukt | 29 Robux | Gewünschtes Wetter für 10 Minuten |
| Detektor-Skins und Event-Shop | Direktkauf, feste Inhalte | 99 bis 799 Robux | Reine Optik und limitierte Sammelstücke |

**Erwartete Umsatztreiber** (meine Einschätzung, mit echten Zahlen zu prüfen): 1. Gem-Pakete für Kisten, 2. Event-Kisten und Saison-Pass, 3. Starterpaket, 4. Gamepasses, 5. Boosts.

**Reihenfolge der Angebote:**

1. Nach dem ersten "Selten"-Fund: Starterpaket, 24 Stunden gültig.
2. Wenn der Rucksack zum ersten Mal voll ist: Großer Rucksack.
3. Beim ersten Upgrade-Engpass: 2x Münzen.
4. Ab Tag 2: Kisten-Angebote und die laufende Saison.

**Regeln für Angebote:** Sie erscheinen nach dem Reveal, nie davor, und blockieren das Spiel nicht. Der Shop zeigt immer die Quoten und die Kosten bis zur Pity-Garantie. Das hält das Vertrauen hoch, was bei einem jüngeren Publikum wichtig ist.

Zusätzlich kommen Premium-Payouts von Roblox, abhängig von der Spielzeit der Premium-Spieler.

## Events und Retention

Das Spiel läuft in vierwöchigen Saisons, jede mit eigener Event-Zone, Event-Kiste und Pass. Das gibt dir einen festen Update-Rhythmus und jede Saison einen neuen Kaufanlass.

| Woche | Inhalt | Wirkung auf Umsatz und Spielzeit |
| --- | --- | --- |
| 1 | Saisonstart: Event-Zone öffnet, Event-Kiste und Saison-Pass starten | Kisten- und Pass-Käufe |
| 2 | Doppel-Fund-Wochenende und Server-Event "Weltfund": Alle graben gemeinsam ein Boss-Relikt aus | Spielzeit, Social |
| 3 | Neue Event-Items im Direktshop, Set-Aufgaben | Direktkäufe |
| 4 | Finale: letzte Chance auf die Event-Kiste, Leaderboard-Preise | Dringlichkeit, Rückkehrer |

- **Daily Reward:** 7-Tage-Serie, an Tag 7 gibt es eine Eisenkiste gratis. Das erzeugt die tägliche Wiederkehr. In Regionen mit `ArePaidRandomItemsRestricted` gibt es statt der Kiste einen festen Ersatz (zum Beispiel ein bestimmtes Ausrüstungsstück), solange nicht geklärt ist, ob Gratis-Kisten dort erlaubt sind.
- **Codes:** Gems und Boosts bei Meilensteinen wie Likes und Favoriten. Das sind Hebel für YouTuber und Social Media.
- **Freunde-Bonus:** 10 % mehr Münzen pro Freund im Server, bis maximal 50 %. Das bringt Spieler dazu, Freunde einzuladen.
- **Leaderboard:** Wertvollste Sammlung pro Woche. Jeder kann das Museum eines Freundes besuchen.
- **Offline-Ertrag:** Der Begleiter sammelt passiv Münzen, solange man weg ist, begrenzt auf etwa 4 Stunden und ohne Funde ab "Selten". Der Auto-Dig-Pass verlängert die Grenze. Die genauen Zahlen setzt der `balance-analyst`.

## Roblox-Policy

Bezahlte Zufallsitems sind erlaubt, wenn du die Quoten offenlegst und die regionalen Sperren einhaltest. Daraus folgt eine feste Checkliste, die vor dem Launch erfüllt sein muss.

- **Quoten anzeigen:** Wer zufällige virtuelle Items gegen Robux oder Ingame-Währung verkauft, muss [die tatsächlichen Zahlenwerte angeben](https://create.roblox.com/docs/production/monetization/virtual-items), was man bekommen kann. Das gilt auch für Gems.
- **Regionale Sperre:** Die Eigenschaft `ArePaidRandomItemsRestricted` abfragen. Ist sie wahr, dürfen Spieler nicht mit den Kisten interagieren, und die Gratis-Kiste von Tag 7 wird durch einen festen Gegenstand ersetzt. Statt der Kisten braucht es dann einen [Shop mit Direktkäufen](https://create.roblox.com/docs/en-us/production/monetization/paid-random-items).
- **Boosts, die Quoten verändern:** Wer die Quoten beeinflusst, muss das vor dem Kauf erklären, und die angezeigten Quoten müssen live den echten Stand zeigen. Deshalb gibt es in diesem Konzept keine Glücks-Boosts für Kisten.
- **Fragebogen:** Paid Random Items müssen im [Maturity-&-Compliance-Fragebogen](https://devforum.roblox.com/t/question-about-the-paid-random-items-policy/3495508) angegeben werden.
- **Kein Trading:** Items aus Kisten lassen sich weder tauschen noch verkaufen, und es gibt keine Auszahlung. Laut zitierten Nutzungsbedingungen dürfen Items aus bezahlten Zufallsboxen nicht gegen Robux oder etwas von Wert getauscht werden ([Forum-Zitat](https://devforum.roblox.com/t/dices-integration-does-this-infringe-the-gambling-tos/2980663)). Die aktuellen Terms of Use solltest du vor dem Launch selbst gegenlesen.
- **Keine Drittanbieter-Verkäufe:** Webshops, die Spielitems für echtes Geld ausliefern, sind verboten und kein Vorbild.

## Roadmap und Aufwand

_(Diagramm: Roadmap · 4 Phasen, 3 Prüfstellen – nur in der Claude-Version des Dokuments)_

Grobe Schätzung bei einem Einzelentwickler mit KI-Unterstützung: Phase 1 braucht 3 bis 4 Wochen, Phase 2 und 3 je etwa 2. Danach folgt der Soft-Launch. Das hängt stark von deinem Zeitbudget ab. Der Mindestumfang (MVP) ist Phase 1 plus eine Kiste mit sichtbaren Quoten.

## Risiken und offene Entscheidungen

Das größte Risiko ist nicht die Technik, sondern dass das Spiel in einem vollen Markt nicht gefunden wird oder in den ersten Minuten nicht trägt.

| Risiko | Warum | Gegenmaßnahme |
| --- | --- | --- |
| Policy-Auslegung bei Kisten und Robux | Regeln ändern sich, Regionen sperren Kisten | Quoten live anzeigen, Direktkauf-Shop als Fallback, Terms vor dem Launch lesen |
| Gesättigter Sim-Markt | Im vierten Quartal 2025 kamen 189 neue Simulatoren, die durchschnittliche CCU pro Spiel sank Anfang 2026 um 20 % | Eigener Dreh (zwei Handlungen, Wetter, Museum) und starke erste 60 Sekunden |
| Schwache Retention | Ohne Wiederkehr-Gründe läuft der Kistenumsatz nicht | Daily Rewards, Museum, Soft-Launch-Zahlen auswerten |
| Wirtschaft kippt | Zu viele Münzen oder zu seltene Drops zerstören die Motivation | Wirtschaftstabelle in einem Spreadsheet, Preise nach dem Soft-Launch anpassen |
| Zu wenig Reichweite | Ohne Ads und Creator findet niemand das Spiel | Roblox-Ads-Budget einplanen, Codes für YouTuber |

**Offene Entscheidungen:**

- [ ] Optik: Cartoon, Low-Poly oder realistisch?
- [ ] Name und Markenprüfung statt "Relic Hunters"
- [ ] Budget für Roblox Ads vor und nach dem Launch
- [ ] Handy-Steuerung: Was erreicht man mit einer Hand?
- [ ] Trading später nachrüsten? Nur nach Klärung der Policy

## Quellen

Aus Suchergebnissen, die Seiten selbst wurden nicht vollständig gelesen. Stand: 17.11.2026.

- [Virtual items, Roblox](https://create.roblox.com/docs/production/monetization/virtual-items)
- [Paid random items policy guidelines, Roblox](https://create.roblox.com/docs/en-us/production/monetization/paid-random-items)
- [Question about the Paid Random Items policy, Roblox DevForum](https://devforum.roblox.com/t/question-about-the-paid-random-items-policy/3495508)
- [Dices integration, Roblox DevForum](https://devforum.roblox.com/t/dices-integration-does-this-infringe-the-gambling-tos/2980663)
- [Genre shift 2026 predictions, rolearn.dev](https://rolearn.dev/trend-reports/genre-shift-2026-predictions)
- [The Simulation Takeover, RoWatcher](https://rowatcher.com/news/the-simulation-takeover-why-casual-sims-rule-roblox-in-2026)
