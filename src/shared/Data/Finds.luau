--!strict
-- Fundstücke und Sets (Konzept: "Welt und Zonen"). Jede Zone hat 30 Fundstücke in
-- 6 Sets zu je 5. Die Namen und Beschreibungen kommen aus Paket 3.3. Die IDs bleiben
-- für immer gleich ("<Zone>_s<Set>_<Slot>"), sonst gehen gespeicherte Sammlungen verloren.
-- Fundquoten stehen in FindOdds.

local Zones = require("./Zones")

export type FindSet = {
    id: string, -- z. B. "dunes_set_1"
    zoneId: string,
    index: number, -- 1 bis SETS_PER_ZONE
    name: string, -- Anzeigename des Sets
    size: number, -- Slots pro Set
}

export type Find = {
    id: string,
    name: string, -- Anzeigename für Spieler
    description: string,
    zoneId: string,
    setId: string,
    rarityId: string,
    -- Überarbeitung Ü5: Bild aus dem UI-Atlas (Interface/Catalog, assets/ui). Zuordnung je Zone nach
    -- Seltenheit (seltener Fund = Bild eines seltenen Entwurfs). Waltuh prüft im Sammelbuch.
    icon: string,
}

local SETS_PER_ZONE = 6
local FINDS_PER_SET = 5

local SET_NAMES: { [string]: { string } } = {
    dunes = { "Strandgut", "Urlaubsverluste", "Karawanenreste", "Alte Münzen", "Wüstentiere", "Schatz des Dünenpiraten" },
    oasis = { "Gartenkram", "Brunnen und Krüge", "Gewürzhandel", "Teppiche und Lampen", "Karawanenschmuck", "Schatz des Oasenfürsten" },
    canyon = { "Steine", "Goldgräber-Ausrüstung", "Fossilien", "Dino-Knochen", "Edelsteine", "Herz des Canyons" },
    salt_lake = { "Salzkristalle", "Schiffswrack", "Nebelfunde", "Versteinertes Meer", "Kristallgeister", "Krone des Salzkönigs" },
    ruins = { "Tonscherben", "Tempelschmuck", "Statuen", "Königsgrab", "Götterzeichen", "Schatz des letzten Barons" },
}

local sets: { FindSet } = {}
for _, zone in Zones.list do
    for index = 1, SETS_PER_ZONE do
        local setName: string? = SET_NAMES[zone.id][index]
        if setName == nil then
            error(`Finds: Set-Name fehlt für {zone.id} {index}`)
        end
        table.insert(sets, {
            id = `{zone.id}_set_{index}`,
            zoneId = zone.id,
            index = index,
            name = setName,
            size = FINDS_PER_SET,
        })
    end
end

local setsById: { [string]: FindSet } = {}
for _, findSet in sets do
    setsById[findSet.id] = findSet
end

local list: { Find } = {
    -- Zone: dunes (Dünenmeer)
    -- dunes, Set 1
    { id = "dunes_s1_1", name = "Einzelner Flip-Flop", description = "Der andere ist irgendwo da draußen.", zoneId = "dunes", setId = "dunes_set_1", rarityId = "common", icon = "duenenmeer_01" },
    { id = "dunes_s1_2", name = "Sonnenbrille ohne Bügel", description = "Sieht trotzdem cool aus, sagt der Besitzer.", zoneId = "dunes", setId = "dunes_set_1", rarityId = "common", icon = "duenenmeer_02" },
    { id = "dunes_s1_3", name = "Verbeulte Wasserflasche", description = "Leer, aber mit einem Zettel darin, den niemand entziffern kann.", zoneId = "dunes", setId = "dunes_set_1", rarityId = "common", icon = "duenenmeer_03" },
    { id = "dunes_s1_4", name = "Halber Badeball", description = "Die andere Hälfte hat vermutlich ein Krebs geklaut.", zoneId = "dunes", setId = "dunes_set_1", rarityId = "common", icon = "duenenmeer_06" },
    { id = "dunes_s1_5", name = "Rote Plastikschaufel", description = "Hier hat schon ein Kind gebuddelt, vor ein paar Jahrzehnten.", zoneId = "dunes", setId = "dunes_set_1", rarityId = "common", icon = "duenenmeer_07" },
    -- dunes, Set 2
    { id = "dunes_s2_1", name = "Halbe Sonnencreme", description = "Der Rest der Tube ist jetzt Teil der Düne.", zoneId = "dunes", setId = "dunes_set_2", rarityId = "common", icon = "duenenmeer_11" },
    { id = "dunes_s2_2", name = "Autoschlüssel ohne Auto", description = "Passt zu einem Wagen, der seit Jahren im Sand parkt.", zoneId = "dunes", setId = "dunes_set_2", rarityId = "uncommon", icon = "duenenmeer_12" },
    { id = "dunes_s2_3", name = "Goldener Ehering", description = "Den Besitzer suchen wir noch. Vielleicht sucht er uns.", zoneId = "dunes", setId = "dunes_set_2", rarityId = "uncommon", icon = "duenenmeer_16" },
    { id = "dunes_s2_4", name = "Handyhülle mit Foto", description = "Das Foto zeigt einen Strand, den es hier nie gab.", zoneId = "dunes", setId = "dunes_set_2", rarityId = "uncommon", icon = "duenenmeer_21" },
    { id = "dunes_s2_5", name = "Reisepass ohne Namen", description = "Kein Name, kein Foto, aber vierzig Stempel aus Wüstenländern.", zoneId = "dunes", setId = "dunes_set_2", rarityId = "rare", icon = "duenenmeer_14" },
    -- dunes, Set 3
    { id = "dunes_s3_1", name = "Zerrissenes Kamelhalfter", description = "Das Kamel ist längst weitergezogen, ohne Halfter.", zoneId = "dunes", setId = "dunes_set_3", rarityId = "uncommon", icon = "duenenmeer_26" },
    { id = "dunes_s3_2", name = "Kupferne Feldflasche", description = "Noch dicht, sagt die Karawane. Alle anderen zweifeln.", zoneId = "dunes", setId = "dunes_set_3", rarityId = "uncommon", icon = "duenenmeer_04" },
    { id = "dunes_s3_3", name = "Gewebte Satteldecke", description = "Das Kamel fand sie bequem. Das Kamel hatte recht.", zoneId = "dunes", setId = "dunes_set_3", rarityId = "uncommon", icon = "duenenmeer_05" },
    { id = "dunes_s3_4", name = "Karawanen-Notizbuch", description = "Der letzte Eintrag lautet: Bitte nicht nach Süden gehen.", zoneId = "dunes", setId = "dunes_set_3", rarityId = "rare", icon = "duenenmeer_17" },
    { id = "dunes_s3_5", name = "Silberne Wegkarte", description = "Führt zu einer Düne, auf der bereits jemand gräbt.", zoneId = "dunes", setId = "dunes_set_3", rarityId = "rare", icon = "duenenmeer_18" },
    -- dunes, Set 4
    { id = "dunes_s4_1", name = "Abgegriffene Kupfermünze", description = "Der Kopf ist abgerieben, aber das Gesicht war sicher wichtig.", zoneId = "dunes", setId = "dunes_set_4", rarityId = "uncommon", icon = "duenenmeer_08" },
    { id = "dunes_s4_2", name = "Bronzemünze mit Loch", description = "Die Gelehrten streiten, ob es eine Münze oder ein Knopf war.", zoneId = "dunes", setId = "dunes_set_4", rarityId = "uncommon", icon = "duenenmeer_09" },
    { id = "dunes_s4_3", name = "Dünenthaler aus Silber", description = "Geprägt in einer Stadt, die zuletzt unter Sand verschwand.", zoneId = "dunes", setId = "dunes_set_4", rarityId = "rare", icon = "duenenmeer_22" },
    { id = "dunes_s4_4", name = "Goldstater des Heerführers", description = "Die Inschrift lobt einen Mann, der den Sand besiegen wollte.", zoneId = "dunes", setId = "dunes_set_4", rarityId = "rare", icon = "duenenmeer_27" },
    { id = "dunes_s4_5", name = "Münzkette der Sandkönige", description = "Jede Münze erzählt eine Geschichte, und keine endet gut.", zoneId = "dunes", setId = "dunes_set_4", rarityId = "epic", icon = "duenenmeer_23" },
    -- dunes, Set 5
    { id = "dunes_s5_1", name = "Kleiner Skorpionpanzer", description = "Leer, sagt die Forschung. Die Forschung hat nicht nachgeschaut.", zoneId = "dunes", setId = "dunes_set_5", rarityId = "uncommon", icon = "duenenmeer_13" },
    { id = "dunes_s5_2", name = "Fossiler Wüstenfuchs", description = "Sieht aus, als wäre er gerade noch weggerannt.", zoneId = "dunes", setId = "dunes_set_5", rarityId = "rare", icon = "duenenmeer_10" },
    { id = "dunes_s5_3", name = "Gecko-Haut im Glas", description = "Der Gecko hat sie abgestreift und ist vermutlich gut angekommen.", zoneId = "dunes", setId = "dunes_set_5", rarityId = "rare", icon = "duenenmeer_15" },
    { id = "dunes_s5_4", name = "Riesige Adlerschwinge", description = "So groß, dass sie als Sonnenschirm für zwei reicht.", zoneId = "dunes", setId = "dunes_set_5", rarityId = "epic", icon = "duenenmeer_28" },
    { id = "dunes_s5_5", name = "Zahn des Sandwurms", description = "Er gehörte zu einem Wesen, das noch niemand gesehen hat.", zoneId = "dunes", setId = "dunes_set_5", rarityId = "legendary", icon = "duenenmeer_29" },
    -- dunes, Set 6
    { id = "dunes_s6_1", name = "Piratenkompass ohne Nadel", description = "Zeigt immer dorthin, wo der nächste Schatz liegen soll.", zoneId = "dunes", setId = "dunes_set_6", rarityId = "rare", icon = "duenenmeer_19" },
    { id = "dunes_s6_2", name = "Kapitänshut aus Leder", description = "Der Hut ist noch da, der Kapitän nicht. Verständlich.", zoneId = "dunes", setId = "dunes_set_6", rarityId = "epic", icon = "duenenmeer_20" },
    { id = "dunes_s6_3", name = "Goldenes Piratenfernrohr", description = "Durch dieses Glas wurde der Schatz angeblich zuerst gesehen.", zoneId = "dunes", setId = "dunes_set_6", rarityId = "epic", icon = "duenenmeer_24" },
    { id = "dunes_s6_4", name = "Gold der Dünenkapitäne", description = "Über Jahrzehnte gesammelt, in einer einzigen Nacht verloren.", zoneId = "dunes", setId = "dunes_set_6", rarityId = "legendary", icon = "duenenmeer_30" },
    { id = "dunes_s6_5", name = "Säbel des Dünenpiraten", description = "Er hat drei Sandstürme besiegt. Behauptet jedenfalls der Säbel.", zoneId = "dunes", setId = "dunes_set_6", rarityId = "mythic", icon = "duenenmeer_25" },
    -- Zone: oasis
    -- oasis, Set 1
    { id = "oasis_s1_1", name = "Rostige Gießkanne", description = "Hat ein Loch im Boden und gießt deshalb vor allem Füße.", zoneId = "oasis", setId = "oasis_set_1", rarityId = "common", icon = "oase_01" },
    { id = "oasis_s1_2", name = "Schrumpeliger Gartenzwerg", description = "Er schaut uns an, als wüsste er, wo der Rasen geblieben ist.", zoneId = "oasis", setId = "oasis_set_1", rarityId = "common", icon = "oase_02" },
    { id = "oasis_s1_3", name = "Linker Gummistiefel", description = "Der rechte liegt vermutlich noch im Teich.", zoneId = "oasis", setId = "oasis_set_1", rarityId = "common", icon = "oase_03" },
    { id = "oasis_s1_4", name = "Vogelhaus ohne Dach", description = "Ein Vogel hat trotzdem hier gewohnt. Mit Regenschirm.", zoneId = "oasis", setId = "oasis_set_1", rarityId = "common", icon = "oase_06" },
    { id = "oasis_s1_5", name = "Plastikpalme mit Staub", description = "Die einzige Palme, die hier nie Durst hatte.", zoneId = "oasis", setId = "oasis_set_1", rarityId = "common", icon = "oase_07" },
    -- oasis, Set 2
    { id = "oasis_s2_1", name = "Angeschlagener Tonkrug", description = "Füllt sich nicht mehr, hat aber noch viel Charakter.", zoneId = "oasis", setId = "oasis_set_2", rarityId = "common", icon = "oase_11" },
    { id = "oasis_s2_2", name = "Kupferschöpfkelle", description = "Hat Generationen Wasser geschöpft und wurde nie gespült.", zoneId = "oasis", setId = "oasis_set_2", rarityId = "uncommon", icon = "oase_12" },
    { id = "oasis_s2_3", name = "Lederner Wasserschlauch", description = "Noch dicht. Fast. Bitte nicht drücken.", zoneId = "oasis", setId = "oasis_set_2", rarityId = "uncommon", icon = "oase_16" },
    { id = "oasis_s2_4", name = "Bemalter Wasserkrug", description = "Die Muster zeigen einen Brunnen, den nie jemand fand.", zoneId = "oasis", setId = "oasis_set_2", rarityId = "uncommon", icon = "oase_21" },
    { id = "oasis_s2_5", name = "Brunnenstein mit Gravur", description = "Die Gravur verspricht ewiges Wasser. Eine Lüge, aber eine schöne.", zoneId = "oasis", setId = "oasis_set_2", rarityId = "rare", icon = "oase_14" },
    -- oasis, Set 3
    { id = "oasis_s3_1", name = "Gewürzbeutel mit Zimt", description = "Der Zimt hat den Beutel überlebt, der Händler nicht.", zoneId = "oasis", setId = "oasis_set_3", rarityId = "uncommon", icon = "oase_26" },
    { id = "oasis_s3_2", name = "Versiegelte Pfefferdose", description = "Die Dose ist zu, aber der Duft hat sich schon verbreitet.", zoneId = "oasis", setId = "oasis_set_3", rarityId = "uncommon", icon = "oase_04" },
    { id = "oasis_s3_3", name = "Safranfaden im Glas", description = "Teurer als alles, was wir je in einem Laden gesehen haben.", zoneId = "oasis", setId = "oasis_set_3", rarityId = "uncommon", icon = "oase_05" },
    { id = "oasis_s3_4", name = "Händlerwaage aus Messing", description = "Wiegt sehr genau, solange der Händler kauft.", zoneId = "oasis", setId = "oasis_set_3", rarityId = "rare", icon = "oase_17" },
    { id = "oasis_s3_5", name = "Gewürzkiste des Kaufmanns", description = "Leer, aber der Duft verspricht noch Verhandlungsspielraum.", zoneId = "oasis", setId = "oasis_set_3", rarityId = "rare", icon = "oase_18" },
    -- oasis, Set 4
    { id = "oasis_s4_1", name = "Zerschlissener Teppichrand", description = "Der Teppich fehlt, aber der Rand hat Geschichte.", zoneId = "oasis", setId = "oasis_set_4", rarityId = "uncommon", icon = "oase_08" },
    { id = "oasis_s4_2", name = "Öllampe ohne Docht", description = "Brennt nicht mehr, riecht aber nach langen Nächten.", zoneId = "oasis", setId = "oasis_set_4", rarityId = "uncommon", icon = "oase_09" },
    { id = "oasis_s4_3", name = "Verziertes Lampenglas", description = "Die Muster wandern, wenn niemand hinsieht.", zoneId = "oasis", setId = "oasis_set_4", rarityId = "rare", icon = "oase_22" },
    { id = "oasis_s4_4", name = "Knüpfteppich aus Seide", description = "Über tausend Knoten, und jeder einzelne wurde gezählt.", zoneId = "oasis", setId = "oasis_set_4", rarityId = "rare", icon = "oase_27" },
    { id = "oasis_s4_5", name = "Lampe des Nachtwächters", description = "Sie leuchtet nur für Leute, die sich verlaufen haben.", zoneId = "oasis", setId = "oasis_set_4", rarityId = "epic", icon = "oase_23" },
    -- oasis, Set 5
    { id = "oasis_s5_1", name = "Silberarmreif", description = "Klimpert bei jedem Schritt. Kamele lieben das.", zoneId = "oasis", setId = "oasis_set_5", rarityId = "uncommon", icon = "oase_13" },
    { id = "oasis_s5_2", name = "Perlenkette der Händlerin", description = "Jede Perle hat einen Preis, nur diese hier nicht.", zoneId = "oasis", setId = "oasis_set_5", rarityId = "rare", icon = "oase_10" },
    { id = "oasis_s5_3", name = "Kupferohrring mit Glöckchen", description = "Das Glöckchen klingelt nur, wenn jemand lügt.", zoneId = "oasis", setId = "oasis_set_5", rarityId = "rare", icon = "oase_15" },
    { id = "oasis_s5_4", name = "Halskette der Karawane", description = "Sie wurde bei jedem Handel getragen, und bei jedem gewonnen.", zoneId = "oasis", setId = "oasis_set_5", rarityId = "epic", icon = "oase_28" },
    { id = "oasis_s5_5", name = "Diadem der Wüstenkönigin", description = "Man sagt, sie hat es nie abgelegt, nicht mal im Schlaf.", zoneId = "oasis", setId = "oasis_set_5", rarityId = "legendary", icon = "oase_29" },
    -- oasis, Set 6
    { id = "oasis_s6_1", name = "Goldene Dattelschale", description = "Nur für Datteln, die niemand sonst bekommen durfte.", zoneId = "oasis", setId = "oasis_set_6", rarityId = "rare", icon = "oase_19" },
    { id = "oasis_s6_2", name = "Juwelenkompass des Fürsten", description = "Er zeigt immer zum nächsten Vorrat, sagen die Diener.", zoneId = "oasis", setId = "oasis_set_6", rarityId = "epic", icon = "oase_20" },
    { id = "oasis_s6_3", name = "Fürstlicher Wasserbeutel", description = "Er war voll, auch in den schlimmsten Dürren.", zoneId = "oasis", setId = "oasis_set_6", rarityId = "epic", icon = "oase_24" },
    { id = "oasis_s6_4", name = "Thron des Oasenfürsten", description = "Aus Palmholz und Gold. Der Fürst saß trotzdem nie lange still.", zoneId = "oasis", setId = "oasis_set_6", rarityId = "legendary", icon = "oase_30" },
    { id = "oasis_s6_5", name = "Ewige Quelle", description = "Eine Quelle in einer Flasche. Sie wird nie leer, egal wie groß der Durst.", zoneId = "oasis", setId = "oasis_set_6", rarityId = "mythic", icon = "oase_25" },
    -- Zone: canyon
    -- canyon, Set 1
    { id = "canyon_s1_1", name = "Normaler Stein", description = "Ein Stein. Mehr sagen wir dazu nicht.", zoneId = "canyon", setId = "canyon_set_1", rarityId = "common", icon = "canyon_01" },
    { id = "canyon_s1_2", name = "Brauner Kieselstein", description = "Sieht aus wie der letzte, nur dunkler.", zoneId = "canyon", setId = "canyon_set_1", rarityId = "common", icon = "canyon_02" },
    { id = "canyon_s1_3", name = "Runder Flusskiesel", description = "Seit tausend Jahren rund, und trotzdem noch nicht fertig.", zoneId = "canyon", setId = "canyon_set_1", rarityId = "common", icon = "canyon_03" },
    { id = "canyon_s1_4", name = "Gespaltener Schiefer", description = "Hat sich ein Jahr lang gespalten, dann war Schluss.", zoneId = "canyon", setId = "canyon_set_1", rarityId = "common", icon = "canyon_06" },
    { id = "canyon_s1_5", name = "Ockerfarbener Brocken", description = "Riesig für einen Stein, winzig für einen Berg.", zoneId = "canyon", setId = "canyon_set_1", rarityId = "common", icon = "canyon_07" },
    -- canyon, Set 2
    { id = "canyon_s2_1", name = "Verbeulte Schaufel", description = "Schaufelt noch, aber nur in eine Richtung.", zoneId = "canyon", setId = "canyon_set_2", rarityId = "common", icon = "canyon_11" },
    { id = "canyon_s2_2", name = "Goldwaschpfanne", description = "Eine Pfanne voller Hoffnung und fast ohne Gold.", zoneId = "canyon", setId = "canyon_set_2", rarityId = "uncommon", icon = "canyon_12" },
    { id = "canyon_s2_3", name = "Rostige Spitzhacke", description = "Der Stiel hält, der Rost ist ehrlich.", zoneId = "canyon", setId = "canyon_set_2", rarityId = "uncommon", icon = "canyon_16" },
    { id = "canyon_s2_4", name = "Lederbeutel mit Staub", description = "Mehr Staub als Gold, aber der Beutel war einmal voll.", zoneId = "canyon", setId = "canyon_set_2", rarityId = "uncommon", icon = "canyon_21" },
    { id = "canyon_s2_5", name = "Goldgräberlaterne", description = "Brennt noch, obwohl niemand mehr Gold erwartet.", zoneId = "canyon", setId = "canyon_set_2", rarityId = "rare", icon = "canyon_14" },
    -- canyon, Set 3
    { id = "canyon_s3_1", name = "Muschelabdruck", description = "Vor Millionen Jahren war hier Wasser. Beweise folgen.", zoneId = "canyon", setId = "canyon_set_3", rarityId = "uncommon", icon = "canyon_26" },
    { id = "canyon_s3_2", name = "Farnblatt im Stein", description = "Sieht aus, als wäre es gestern erst gefallen.", zoneId = "canyon", setId = "canyon_set_3", rarityId = "uncommon", icon = "canyon_04" },
    { id = "canyon_s3_3", name = "Trilobit im Kalk", description = "Ein kleines Krabbeltier, das schon lange nicht mehr krabbelt.", zoneId = "canyon", setId = "canyon_set_3", rarityId = "uncommon", icon = "canyon_05" },
    { id = "canyon_s3_4", name = "Ammonit mit Spirale", description = "Die Spirale führt nach innen, zu den besten Funden.", zoneId = "canyon", setId = "canyon_set_3", rarityId = "rare", icon = "canyon_17" },
    { id = "canyon_s3_5", name = "Versteinerter Fischkopf", description = "Schaut traurig, weil er sich seit Ewigkeiten nicht bewegt.", zoneId = "canyon", setId = "canyon_set_3", rarityId = "rare", icon = "canyon_18" },
    -- canyon, Set 4
    { id = "canyon_s4_1", name = "Kleiner Rippenknochen", description = "Gehörte zu einem Tier, das niemand gern gestreichelt hätte.", zoneId = "canyon", setId = "canyon_set_4", rarityId = "uncommon", icon = "canyon_08" },
    { id = "canyon_s4_2", name = "Zahn eines Raubsauriers", description = "Scharf genug, um alles Mögliche anzuknabbern.", zoneId = "canyon", setId = "canyon_set_4", rarityId = "uncommon", icon = "canyon_09" },
    { id = "canyon_s4_3", name = "Schädelbruchstück", description = "Gehörte wohl zu jemandem, der sehr laut war.", zoneId = "canyon", setId = "canyon_set_4", rarityId = "rare", icon = "canyon_22" },
    { id = "canyon_s4_4", name = "Oberschenkelknochen", description = "Der Rest des Beins ist vermutlich schon weitergelaufen.", zoneId = "canyon", setId = "canyon_set_4", rarityId = "rare", icon = "canyon_27" },
    { id = "canyon_s4_5", name = "Halswirbel des Titanen", description = "So lang, dass man darauf sitzen könnte, wenn man mutig ist.", zoneId = "canyon", setId = "canyon_set_4", rarityId = "epic", icon = "canyon_23" },
    -- canyon, Set 5
    { id = "canyon_s5_1", name = "Blauer Quarzsplitter", description = "Glitzert nur, wenn man zweimal hinsieht.", zoneId = "canyon", setId = "canyon_set_5", rarityId = "uncommon", icon = "canyon_13" },
    { id = "canyon_s5_2", name = "Rauchquarz", description = "Verhandelt mit dem Licht, bleibt aber dunkel.", zoneId = "canyon", setId = "canyon_set_5", rarityId = "rare", icon = "canyon_10" },
    { id = "canyon_s5_3", name = "Grüner Turmalin", description = "So grün, dass die Kakteen neidisch werden.", zoneId = "canyon", setId = "canyon_set_5", rarityId = "rare", icon = "canyon_15" },
    { id = "canyon_s5_4", name = "Feuerachat", description = "Fühlt sich warm an, auch im kältesten Schatten.", zoneId = "canyon", setId = "canyon_set_5", rarityId = "epic", icon = "canyon_28" },
    { id = "canyon_s5_5", name = "Kristall der Tiefe", description = "Er hat den Canyon geformt, nicht umgekehrt.", zoneId = "canyon", setId = "canyon_set_5", rarityId = "legendary", icon = "canyon_29" },
    -- canyon, Set 6
    { id = "canyon_s6_1", name = "Glimmerader", description = "Eine Ader aus Glimmer, die durch den ganzen Fels läuft.", zoneId = "canyon", setId = "canyon_set_6", rarityId = "rare", icon = "canyon_19" },
    { id = "canyon_s6_2", name = "Bernsteinklinge", description = "Die Händler schwören, sie schneidet sogar Schatten.", zoneId = "canyon", setId = "canyon_set_6", rarityId = "epic", icon = "canyon_20" },
    { id = "canyon_s6_3", name = "Schlafender Geodenkern", description = "Im Inneren schläft ein Kristall, der noch nicht bereit ist.", zoneId = "canyon", setId = "canyon_set_6", rarityId = "epic", icon = "canyon_24" },
    { id = "canyon_s6_4", name = "Schluchtenherz", description = "Pulsiert leise, wenn man den Canyon zu laut anschreit.", zoneId = "canyon", setId = "canyon_set_6", rarityId = "legendary", icon = "canyon_30" },
    { id = "canyon_s6_5", name = "Donnerei", description = "Ein Ei aus Stein, in dem es grollt. Was schlüpft, weiß niemand.", zoneId = "canyon", setId = "canyon_set_6", rarityId = "mythic", icon = "canyon_25" },
    -- Zone: salt_lake
    -- salt_lake, Set 1
    { id = "salt_lake_s1_1", name = "Salzbrocken", description = "Schmeckt salzig, was niemanden wirklich überrascht.", zoneId = "salt_lake", setId = "salt_lake_set_1", rarityId = "common", icon = "salzsee_01" },
    { id = "salt_lake_s1_2", name = "Verklumpte Salzkörner", description = "Zusammen halten sie mehr als jedes Korn für sich.", zoneId = "salt_lake", setId = "salt_lake_set_1", rarityId = "common", icon = "salzsee_02" },
    { id = "salt_lake_s1_3", name = "Salzige Muschel", description = "Die Muschel vermisst vermutlich den Ozean.", zoneId = "salt_lake", setId = "salt_lake_set_1", rarityId = "common", icon = "salzsee_03" },
    { id = "salt_lake_s1_4", name = "Salzstreuer ohne Deckel", description = "Hier gibt es wirklich genug Nachschub.", zoneId = "salt_lake", setId = "salt_lake_set_1", rarityId = "common", icon = "salzsee_06" },
    { id = "salt_lake_s1_5", name = "Weiße Salzkruste", description = "Knirscht beim Drauftreten, als würde sie sich beschweren.", zoneId = "salt_lake", setId = "salt_lake_set_1", rarityId = "common", icon = "salzsee_07" },
    -- salt_lake, Set 2
    { id = "salt_lake_s2_1", name = "Verrostete Schiffsschraube", description = "Dreht sich nur noch im Kopf des Kapitäns.", zoneId = "salt_lake", setId = "salt_lake_set_2", rarityId = "common", icon = "salzsee_11" },
    { id = "salt_lake_s2_2", name = "Morsche Schiffsplanke", description = "Hat mehr Stürme überstanden als seine Besatzung.", zoneId = "salt_lake", setId = "salt_lake_set_2", rarityId = "uncommon", icon = "salzsee_12" },
    { id = "salt_lake_s2_3", name = "Kaputtes Bullauge", description = "Das Glas ist gesprungen, der Blick aber immer noch weit.", zoneId = "salt_lake", setId = "salt_lake_set_2", rarityId = "uncommon", icon = "salzsee_16" },
    { id = "salt_lake_s2_4", name = "Salzverkrustete Kiste", description = "Der Inhalt ist Salz, die Kiste war mal Gold wert.", zoneId = "salt_lake", setId = "salt_lake_set_2", rarityId = "uncommon", icon = "salzsee_21" },
    { id = "salt_lake_s2_5", name = "Schiffsglocke aus Bronze", description = "Läutet nur noch im Wind, und der Wind liebt Dramen.", zoneId = "salt_lake", setId = "salt_lake_set_2", rarityId = "rare", icon = "salzsee_14" },
    -- salt_lake, Set 3
    { id = "salt_lake_s3_1", name = "Feuchter Nebelstein", description = "Immer feucht, egal wie lange er in der Sonne liegt.", zoneId = "salt_lake", setId = "salt_lake_set_3", rarityId = "uncommon", icon = "salzsee_26" },
    { id = "salt_lake_s3_2", name = "Tropfenglas", description = "Sammelt Nebel, aber nur an Tagen, die keiner mag.", zoneId = "salt_lake", setId = "salt_lake_set_3", rarityId = "uncommon", icon = "salzsee_04" },
    { id = "salt_lake_s3_3", name = "Zerbrochene Nebellaterne", description = "Ihr Licht reicht genau bis zum nächsten Nebel.", zoneId = "salt_lake", setId = "salt_lake_set_3", rarityId = "uncommon", icon = "salzsee_05" },
    { id = "salt_lake_s3_4", name = "Nebelkompass", description = "Zeigt immer dorthin, wo man gerade nichts sieht.", zoneId = "salt_lake", setId = "salt_lake_set_3", rarityId = "rare", icon = "salzsee_17" },
    { id = "salt_lake_s3_5", name = "Kalter Nebelschlüssel", description = "Passt in jedes Schloss, das man noch nicht gesehen hat.", zoneId = "salt_lake", setId = "salt_lake_set_3", rarityId = "rare", icon = "salzsee_18" },
    -- salt_lake, Set 4
    { id = "salt_lake_s4_1", name = "Versteinerter Seestern", description = "Hat das Austrocknen des Sees offenbar verschlafen.", zoneId = "salt_lake", setId = "salt_lake_set_4", rarityId = "uncommon", icon = "salzsee_08" },
    { id = "salt_lake_s4_2", name = "Stein-Seeigel", description = "Stachlig, hart und ein echter Schreck für Badegäste.", zoneId = "salt_lake", setId = "salt_lake_set_4", rarityId = "uncommon", icon = "salzsee_09" },
    { id = "salt_lake_s4_3", name = "Perlmuttschnecke", description = "Innen schimmert noch das Meer, außen nur Sand.", zoneId = "salt_lake", setId = "salt_lake_set_4", rarityId = "rare", icon = "salzsee_22" },
    { id = "salt_lake_s4_4", name = "Korallenstein", description = "Ein Riff, das den Weg zurück zum Meer nicht findet.", zoneId = "salt_lake", setId = "salt_lake_set_4", rarityId = "rare", icon = "salzsee_27" },
    { id = "salt_lake_s4_5", name = "Panzer des Meerkönigs", description = "Der König ist gegangen, sein Panzer wartet noch auf ihn.", zoneId = "salt_lake", setId = "salt_lake_set_4", rarityId = "epic", icon = "salzsee_23" },
    -- salt_lake, Set 5
    { id = "salt_lake_s5_1", name = "Glasiger Geistersplitter", description = "Flüstert nur, wenn es sehr still ist.", zoneId = "salt_lake", setId = "salt_lake_set_5", rarityId = "uncommon", icon = "salzsee_13" },
    { id = "salt_lake_s5_2", name = "Kristallschlange", description = "Eine Schlange aus Kristall. Sie ruht sich nur kurz aus.", zoneId = "salt_lake", setId = "salt_lake_set_5", rarityId = "rare", icon = "salzsee_10" },
    { id = "salt_lake_s5_3", name = "Schimmernder Kristallfalter", description = "Flattert nicht mehr, glitzert aber, als würde er es versuchen.", zoneId = "salt_lake", setId = "salt_lake_set_5", rarityId = "rare", icon = "salzsee_15" },
    { id = "salt_lake_s5_4", name = "Geisterlaterne aus Salz", description = "Zeigt den Weg zu Orten, die niemand suchen wollte.", zoneId = "salt_lake", setId = "salt_lake_set_5", rarityId = "epic", icon = "salzsee_28" },
    { id = "salt_lake_s5_5", name = "Kern des Kristallgeists", description = "Er schläft im Salz und wacht nur auf, wenn Gold klingelt.", zoneId = "salt_lake", setId = "salt_lake_set_5", rarityId = "legendary", icon = "salzsee_29" },
    -- salt_lake, Set 6
    { id = "salt_lake_s6_1", name = "Salzgekrönter Rubin", description = "Lag so lange im Salz, dass er Ehrgeiz entwickelt hat.", zoneId = "salt_lake", setId = "salt_lake_set_6", rarityId = "rare", icon = "salzsee_19" },
    { id = "salt_lake_s6_2", name = "Salzsiegel des Königs", description = "Mit diesem Siegel wurde jeder Vertrag am See gültig.", zoneId = "salt_lake", setId = "salt_lake_set_6", rarityId = "epic", icon = "salzsee_20" },
    { id = "salt_lake_s6_3", name = "Königliches Salzzepter", description = "Mehr Stab als Macht, aber es glänzt wunderbar.", zoneId = "salt_lake", setId = "salt_lake_set_6", rarityId = "epic", icon = "salzsee_24" },
    { id = "salt_lake_s6_4", name = "Thronfolgerring", description = "Wartete auf einen Nachfolger, der nie kam.", zoneId = "salt_lake", setId = "salt_lake_set_6", rarityId = "legendary", icon = "salzsee_30" },
    { id = "salt_lake_s6_5", name = "Salzkönigskrone", description = "Wer sie trägt, herrscht über jedes Salzkorn. Und das sind viele.", zoneId = "salt_lake", setId = "salt_lake_set_6", rarityId = "mythic", icon = "salzsee_25" },
    -- Zone: ruins
    -- ruins, Set 1
    { id = "ruins_s1_1", name = "Kleine Tonscherbe", description = "Ein Teil eines Topfes, der wohl erst wieder heil werden muss.", zoneId = "ruins", setId = "ruins_set_1", rarityId = "common", icon = "ruinenstadt_01" },
    { id = "ruins_s1_2", name = "Scherbe mit Henkel", description = "Der Henkel hat den Rest der Schüssel überlebt.", zoneId = "ruins", setId = "ruins_set_1", rarityId = "common", icon = "ruinenstadt_02" },
    { id = "ruins_s1_3", name = "Bemalte Tonscherbe", description = "Ein Punkt, eine Linie, und die Gelehrten streiten schon.", zoneId = "ruins", setId = "ruins_set_1", rarityId = "common", icon = "ruinenstadt_03" },
    { id = "ruins_s1_4", name = "Gesprungener Krugboden", description = "Der Boden ist noch da, der Krug hat sich verabschiedet.", zoneId = "ruins", setId = "ruins_set_1", rarityId = "common", icon = "ruinenstadt_06" },
    { id = "ruins_s1_5", name = "Verschmierte Tonplatte", description = "Die Schrift ist verschmiert, vermutlich von Nachbarn.", zoneId = "ruins", setId = "ruins_set_1", rarityId = "common", icon = "ruinenstadt_07" },
    -- ruins, Set 2
    { id = "ruins_s2_1", name = "Bunter Tempelkiesel", description = "Laut Priester heilig. Die Priester sind leider nicht mehr da.", zoneId = "ruins", setId = "ruins_set_2", rarityId = "common", icon = "ruinenstadt_11" },
    { id = "ruins_s2_2", name = "Goldener Ohrring", description = "Der Tempel hat ihn verloren und nie danach gesucht.", zoneId = "ruins", setId = "ruins_set_2", rarityId = "uncommon", icon = "ruinenstadt_12" },
    { id = "ruins_s2_3", name = "Bronzener Armreif", description = "Schwer, glänzend und leider nicht mehr am Arm.", zoneId = "ruins", setId = "ruins_set_2", rarityId = "uncommon", icon = "ruinenstadt_16" },
    { id = "ruins_s2_4", name = "Kettenanhänger aus Ton", description = "Der Gott auf dem Anhänger wirkt sehr entspannt.", zoneId = "ruins", setId = "ruins_set_2", rarityId = "uncommon", icon = "ruinenstadt_21" },
    { id = "ruins_s2_5", name = "Tempelmedaillon", description = "Das Medaillon zeigt einen Gott, der gern zusah.", zoneId = "ruins", setId = "ruins_set_2", rarityId = "rare", icon = "ruinenstadt_14" },
    -- ruins, Set 3
    { id = "ruins_s3_1", name = "Abgebrochener Statuenfinger", description = "Der Finger zeigt noch auf etwas, das niemand mehr sieht.", zoneId = "ruins", setId = "ruins_set_3", rarityId = "uncommon", icon = "ruinenstadt_26" },
    { id = "ruins_s3_2", name = "Steinerne Katzenfigur", description = "Schaut verächtlich, wie alle Katzen dieser Stadt.", zoneId = "ruins", setId = "ruins_set_3", rarityId = "uncommon", icon = "ruinenstadt_04" },
    { id = "ruins_s3_3", name = "Kopf eines Wächters", description = "Der Blick ist streng, der Nacken fehlt.", zoneId = "ruins", setId = "ruins_set_3", rarityId = "uncommon", icon = "ruinenstadt_05" },
    { id = "ruins_s3_4", name = "Schreiberstatue aus Bronze", description = "Er schreibt noch immer, in einer Sprache, die niemand kennt.", zoneId = "ruins", setId = "ruins_set_3", rarityId = "rare", icon = "ruinenstadt_17" },
    { id = "ruins_s3_5", name = "Thronwächter aus Stein", description = "Bewacht einen Thron, der längst im Sand versunken ist.", zoneId = "ruins", setId = "ruins_set_3", rarityId = "rare", icon = "ruinenstadt_18" },
    -- ruins, Set 4
    { id = "ruins_s4_1", name = "Grabbeigabe aus Ton", description = "Sollte den König begleiten, ist aber hier geblieben.", zoneId = "ruins", setId = "ruins_set_4", rarityId = "uncommon", icon = "ruinenstadt_08" },
    { id = "ruins_s4_2", name = "Schmuckdose des Königs", description = "Leer, aber verziert, wie es sich für einen König gehört.", zoneId = "ruins", setId = "ruins_set_4", rarityId = "uncommon", icon = "ruinenstadt_09" },
    { id = "ruins_s4_3", name = "Goldene Totenmaske", description = "Der König trägt sie nicht mehr, er hat sich verändert.", zoneId = "ruins", setId = "ruins_set_4", rarityId = "rare", icon = "ruinenstadt_22" },
    { id = "ruins_s4_4", name = "Kanopenkrug", description = "Angeblich enthält er Eingeweide. Wir fragen nicht nach.", zoneId = "ruins", setId = "ruins_set_4", rarityId = "rare", icon = "ruinenstadt_27" },
    { id = "ruins_s4_5", name = "Sarkophagdeckel", description = "So schwer, dass man ihn nur mit Geduld und Flüchen hob.", zoneId = "ruins", setId = "ruins_set_4", rarityId = "epic", icon = "ruinenstadt_23" },
    -- ruins, Set 5
    { id = "ruins_s5_1", name = "Winziges Sonnensymbol", description = "Ein Gott, der nie an Sonnencreme gedacht hat.", zoneId = "ruins", setId = "ruins_set_5", rarityId = "uncommon", icon = "ruinenstadt_13" },
    { id = "ruins_s5_2", name = "Mondsichel aus Kupfer", description = "Die Priester beteten nachts zu ihr. Tagsüber schliefen sie.", zoneId = "ruins", setId = "ruins_set_5", rarityId = "rare", icon = "ruinenstadt_10" },
    { id = "ruins_s5_3", name = "Sternenzeichen aus Lehm", description = "Die Sterne haben sich verschoben, das Zeichen nicht.", zoneId = "ruins", setId = "ruins_set_5", rarityId = "rare", icon = "ruinenstadt_15" },
    { id = "ruins_s5_4", name = "Amulett des Sonnengottes", description = "Wer es trägt, fühlt sich im Tageslicht sicher.", zoneId = "ruins", setId = "ruins_set_5", rarityId = "epic", icon = "ruinenstadt_28" },
    { id = "ruins_s5_5", name = "Auge des Sandgottes", description = "Ein Edelstein, der dir mit dem Blick folgt, wohin du auch gehst.", zoneId = "ruins", setId = "ruins_set_5", rarityId = "legendary", icon = "ruinenstadt_29" },
    -- ruins, Set 6
    { id = "ruins_s6_1", name = "Siegelring des Barons", description = "Der Baron hat ihn beim Abstieg verloren, sagt man.", zoneId = "ruins", setId = "ruins_set_6", rarityId = "rare", icon = "ruinenstadt_19" },
    { id = "ruins_s6_2", name = "Goldene Schatulle", description = "Verschlossen. Der Schlüssel liegt irgendwo in den Ruinen, viel Glück.", zoneId = "ruins", setId = "ruins_set_6", rarityId = "epic", icon = "ruinenstadt_20" },
    { id = "ruins_s6_3", name = "Kristallschwert des Barons", description = "Zu scharf für Gegner, zu schön für den Kampf.", zoneId = "ruins", setId = "ruins_set_6", rarityId = "epic", icon = "ruinenstadt_24" },
    { id = "ruins_s6_4", name = "Kette des letzten Barons", description = "Er trug sie bis zum letzten Tag, dann verschwand er spurlos.", zoneId = "ruins", setId = "ruins_set_6", rarityId = "legendary", icon = "ruinenstadt_25" },
    { id = "ruins_s6_5", name = "Das erste Sandkorn", description = "Jedes Sandkorn der Welt begann als dieses hier, behauptet die Legende.", zoneId = "ruins", setId = "ruins_set_6", rarityId = "mythic", icon = "ruinenstadt_30" },
}

local byId: { [string]: Find } = {}
for _, find in list do
    byId[find.id] = find
end

return {
    SETS_PER_ZONE = SETS_PER_ZONE,
    FINDS_PER_SET = FINDS_PER_SET,
    sets = sets,
    setsById = setsById,
    list = list,
    byId = byId,
}
