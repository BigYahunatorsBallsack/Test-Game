# Dune Baron – Maschinen V2

`DuneBaron_Machines_V2.rbxm` enthält vier Studio-Modelle mit Gelenken und je einem lokalen Animationsclip unter `Animations/WorkLoop`. Das Paket lässt sich in Studio über **Insert from File** einfügen. Der Größenvergleich mit dem R15-Avatar ist in `groessenvergleich.jpg` festgehalten. Die Vergleichsszene liegt unter `ServerStorage.DuneBaronMachineScalePreview`. Die Modelle stehen zusätzlich im Maschinenhof des Dünenmeers.

| Modell | Maße X × Y × Z in Studs | Arbeitszyklus |
| --- | --- | --- |
| Eimerkette (`bucket_chain`) | 3,67 × 4,75 × 6,81 | 3,20 s. Neun einzelne Schaufeln umlaufen den Förderweg. |
| Mini-Bagger (`mini_digger`) | 5,91 × 5,85 × 10,64 | 3,00 s. Turm, Ausleger, Stiel und Löffel durchlaufen Graben, Heben und Ausschütten. |
| Saugroboter (`vacuum_robot`) | 2,86 × 2,15 × 3,30 | 1,65 s. Scanner und Saugdüse schwenken. |
| Dünen-Harvester (`mega_machine`) | 16,20 × 12,60 × 19,53 | 1,28 s. Beide Walzen drehen mit ihren Zähnen. |

Der Referenzavatar ist 5,18 Studs hoch. Das Förderband reicht fast auf seine Höhe. Der Bagger ist rund 2,7-mal so hoch wie der Saugroboter. Die Maße gelten in der Ruhepose. Front ist lokales −Z.

## Übergabe an Claude

- Die Modelle samt interner Hierarchie klonen. `Root`, `AnimationController/Animator`, `Motor6D` und Schweißverbindungen bilden das Animationsrig. Der bisherige Equipment-Kloner kopiert nur einzelne Parts und muss für dieses Paket angepasst werden.
- Beim Einbau die Maßstäbe aus dem Paket übernehmen. Falls die Daten für die alten Modelle eine andere Zielhöhe erzwingen, die Zielhöhen angleichen. Der `AnimationController` berücksichtigt bei der Clip-Wiedergabe den kanonischen Modellmaßstab.
- `DriverMount` markiert den Sitz am Baggerturm bzw. in der Harvester-Kabine. `WorkOrigin` markiert den Arbeitsbereich. Bei Bagger und Saugroboter sitzt er am beweglichen Teil. Die Eimerkette hat zusätzlich `Discharge` am Auswurf.
- Die Root-Parts sind für die Vorschau verankert. Fahrzeugphysik, Kollisionen und Sitzsteuerung bleiben Integrationsarbeit. Die Clips liegen als editierbare `KeyframeSequence` vor. Für Wiedergabe in einer veröffentlichten Experience brauchen sie veröffentlichte Animation-IDs des passenden Erstellers.
- Der vorherige Fahr-Prototyp liegt als uncommitteter Stand im Workspace. Das Modellpaket ist der eigenständige Art-Stand.

Studio hat das Paket binär exportiert und wieder eingelesen. Alle 17 Motoren bewegen ihre Teile in der lokalen Vorschau. Die Start- und Endpose der vier geloopten Clips stimmen überein. Die skalierte Gelenkwiedergabe wurde im Client geprüft. Das Modell enthält keine Laufzeitskripte. Der Place wurde für diese Übergabe nicht neu gespeichert.

Stilreferenzen. Das Zusammenspiel einfacher Fahrzeugformen und sichtbarer Förderwege stammt als allgemeine Inspiration aus [Mining INC: Remastered](https://www.roblox.com/games/3168928542/Mining-INC-Remastered) und [Oaklands](https://www.roblox.com/games/9938675423/Oaklands). Die Modelle sind eigene Entwürfe.
