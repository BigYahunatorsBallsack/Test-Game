# Store-Bildentwürfe

## Auswahl für den aktuellen Spielstand

| Platz | Motiv | Export |
| --- | --- | --- |
| Icon | Eine Figur schüttet mit der Schaufel Sand in einen türkisen Eimer. | [Studio-Icon](store_icon_studio.png) · 512 × 512 PNG |
| Thumbnail 1 | Eine Figur legt das türkise Vermessungssiegel frei. Dahinter stehen der Händlerstand und der Maschinenhof. | [Graben in Studio](store_thumbnail_graben_studio.jpg) · 1920 × 1080 JPEG |
| Thumbnail 2 | Der Harvester schneidet mit beiden Walzen in den Sand. Daneben steht der Avatar im Größenvergleich. | [Harvester in Studio](store_thumbnail_harvester_studio.jpg) · 1920 × 1080 JPEG |

Der Abschnitt `preview_listing` in [store_copy_draft.json](store_copy_draft.json) enthält die englische Beschreibung und die Alternativtexte für diese Auswahl. Der Titel ist offen. Bilder und Texte liegen lokal. [Roblox-Vorgaben für Icons](https://create.roblox.com/docs/production/publishing/experience-icons) · [Roblox-Vorgaben für Thumbnails](https://create.roblox.com/docs/production/publishing/thumbnails)

Die drei Motive wurden im lokalen Spieltest inszeniert. Das Icon nutzt die vorhandene Schaufelpose mit einem für die Aufnahme gebauten Eimer. Die Querformate zeigen das Vermessungssiegel am Startlager und das vorhandene 19,5 Studs lange Harvester-Modell im Dünenmeer. Die Studio-Aufnahmen wurden zugeschnitten und für die Ausgabe skaliert. Das Icon ist bei 64 × 64 Pixeln lesbar. Beide Thumbnails wurden bei 256 × 144 Pixeln geprüft.

## Event-Vorschau „Der Koloss“

Das [Studio-Thumbnail](store_thumbnail_koloss_studio.jpg) zeigt den gebauten Koloss mit freiliegender Steinhand. Eine Figur gräbt nach einem Sonnenamulett. Der Mini-Bagger im Hintergrund gibt der Statue einen Größenmaßstab. Das Motiv wurde mit dem vorhandenen Koloss, dem Mini-Bagger und der Schaufelpose im lokalen Spieltest inszeniert.

Die Studio-Aufnahme wurde auf 16:9 zugeschnitten und als 1920 × 1080 JPEG exportiert. Bei 256 × 144 Pixeln bleiben Kopf, Steinhand, Schaufel und Bagger erkennbar. Die Vorschau und ihr englischer Alternativtext stehen unter `event_preview` im [Store-Entwurf](store_copy_draft.json). Das Motiv ist für die Ankündigung des geplanten Events vorgesehen.

## Frühere V2-Bildfassungen

Das [V2-Icon](store_icon_final_v2.png) und das [V2-Harvester-Motiv](store_thumbnail_harvester_final_v2.png) entstanden mit dem eingebauten ImageGen-Werkzeug. Das Harvester-Motiv orientiert sich an [der Maschine aus Studio](../models/equipment_animation/harvester_laufrollen.jpg), [dem Größenvergleich](../models/equipment_animation/equipment_uebersicht.jpg) und [dem Dünenmeer](../world/duenenmeer_v3/duenenmeer_weitblick.jpg). Das Icon wurde aus dem ersten Store-Icon und dem Graben-Motiv weiterentwickelt.

<details>
<summary>Prompts für die V2-Dateien</summary>

**Store-Icon V2**  
Use case: precise-object-edit. Asset type: square Roblox experience icon, readable at 64 pixels. Input 1 is the icon to edit. Input 2 is supporting reference for the same scene and game art. Keep the same orange blocky explorer, teal backpack, bright blue sky, warm dune palette, and recognizable ancient turquoise inset in warm sandstone. Move the camera into a compact waist-up action crop where the explorer, steel scoop, chunky golden stream of sand and entire orange bucket create one clear diagonal composition visible at small size. Make the separation between the dark graphite metal scoop, pale golden sand, and saturated orange bucket especially distinct. The gloved hands should visibly wrap a single continuous shovel handle, and the stream starts on the blade and lands within the mouth of the bucket. Keep a shallow sand hollow so the action clearly reads as digging. The turquoise ruin inset is a small secondary shape against the dunes. Omit the small excavator in the distance and incidental foreground rocks. Fill the frame with the action, leave a narrow safe margin around the scoop and bucket. Authentic stylized Roblox in-engine look with deliberately simple polygon shapes, restrained lighting, matte surfaces, smooth sand and subtle texture. No text, letters, brands, logos, watermark, gradients on the frame or currency graphics. Opaque square image.

**Harvester V2**  
Use case: precise-object-edit. Asset type: landscape 16:9 Roblox store thumbnail. Input 1 is the thumbnail to edit for the core idea of a harvester chewing through a dune. Inputs 2 and 3 are real Studio views of the exact machine to reproduce and its size compared with a Roblox avatar. Input 4 is the real Studio dune setting to match. Use the native proportions and colors of the game model: narrow offset tall turquoise rectangular cab, smaller teal box beside it, rear yellow vent panel, chunky angular bright yellow body, two dark front cutting drums with rows of squared steel tips mounted on gold beds, deep blue charcoal track assembly and separate gold hubs, short ladder on the near side. No long rectangular cockpit across the whole width. Pose the machine at a low three-quarter view with both drums readable in center-right. Show the left-facing drums biting into a sandy ridge with a small fan of real loose sand and a cut through the dune. The reference dunes are long, smooth crests with a fine sand texture. A single original Roblox-style excavator operator with teal pack stands safely to one side of the machine in the middle foreground, visible head to feet for scale, reaching only about to the top of the drums. Place one partially buried turquoise-marked sandstone relic farther back to suggest exploration and balance the left side. The horizon and upper-left have breathing space and layered golden dunes. Give the main machine immediate impact and visual interest across the frame. Use a real Roblox gameplay feeling with matte blocks, a blue sky, subdued midday highlights, clear soft cast shadows and the color saturation of references 2 and 3. No bright plastic toy renders, cubic pixel terrain, glowing chests, floor-shaped sand blocks, second characters, text, logos or watermark. Keep the entire subject and avatar comfortably inside the centered 16:9 safe crop.

</details>

## Erste Bildfassung

- [Store-Icon](store_icon_final.png), 512 × 512. Ein klarer Bildschwerpunkt aus Schaufel, Sand, Eimer und freigelegter Reliquie.
- [Thumbnail Graben](store_thumbnail_graben_final.png), 1920 × 1080. Graben und Freilegen stehen im Vordergrund.
- [Thumbnail Harvester](store_thumbnail_harvester_final.png), 1920 × 1080. Zwei Walzen, Raupenketten und eine Figur vermitteln die Größe der Maschine.
- [Thumbnail Koloss](store_thumbnail_koloss_final.png), 1920 × 1080. Das Konzeptmotiv zeigt die Freilegung der großen Statue.

Die Motive wurden mit dem eingebauten ImageGen-Werkzeug aus den vorhandenen Entwürfen überarbeitet. Stilvorgabe waren matte Blockformen, warmer Sand, Türkis, blauer Himmel und gut lesbare Silhouetten. Das Icon sollte schon bei 64 Pixeln funktionieren. Für Graben blieben eine sichtbare Sandschaufel und die teilweise freigelegte Reliquie im Vordergrund. Beim Harvester waren getrennte schwarze Walzen, Raupenketten und kleine Figuren als Maßstab vorgegeben. Beim Koloss blieb der steinerne Kopf mit türkisfarbener Einlage die Hauptsilhouette. Alle Motive bleiben schrift- und logofrei.

Die Bilder liegen lokal als Entwürfe. Das Koloss-Motiv zeigt die geplante Event-Szene. [Roblox-Bildvorgaben](https://create.roblox.com/docs/production/publishing/thumbnails)

## Prompts

Gemeinsamer Zusatz für alle vier Überarbeitungen. Preserve warm sand, matte blocky Roblox-style original forms, teal accents and bright blue sky. Match a real game-engine frame with clean deliberate composition, unpolished matte surfaces, and modest contrast. No text, logos, decorative burst lines or brands. Keep key objects fully inside a safe area.

- **Icon** — Edit this square game icon so it reads at 64 px. One close view of the orange explorer with teal backpack shoveling an obvious arc of sand into the orange bucket, one excavated turquoise relic edge behind them and a small yellow mini-excavator silhouette behind. Crop in for recognizable shovel, bucket, sand; remove extra scenery clutter and open treasure full of coins. Tangible scoop of sand is the clear focus.
- **Graben** — Refine this existing 16:9 game thumbnail into a readable group of two depth layers. In front explorer with teal backpack operates shovel pouring sand into orange bucket by partially uncovered teal-inlaid sandstone relic. Midground mini-excavator working its steel bucket and simple cloth market stall, dunes behind. Keep top left relatively open for optional title, no title drawn. Less random boulders and no jackpot-looking chest.
- **Harvester** — Refine this 16:9 thumbnail, keep the yellow machine as the strongest feature. Replace large rear tyres with a single pair of dark crawler tracks, front two charcoal cutting drums with separated cutters and squared turquoise cab windows. Small explorer still visible lower right for scale. Sand flowing under the drums as soft chunky granular terrain, preserve clear dune silhouette. Left third of sky and distance stays open.
- **Koloss** — Refine this existing 16:9 thumbnail. The half buried stone colossus is the clear silhouette, recognizable carved sandstone head and turquoise inlay. In the foreground one blocky explorer excavates a small ancient relic next to the gold mini excavator. A hint of caravan ruins and wind ripples, keep empty upper left. Keep relief readable at thumbnail size; remove the second foreground clone and incidental machinery and decorations. This is a concept-based store draft.
