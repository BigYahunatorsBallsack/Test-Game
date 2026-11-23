--!strict
-- Angebote im Shop (Paket 4.5, Konzept: "Starterpaket, Einmalkauf, 24 Stunden nach dem ersten
-- Selten-Fund, 149 Robux: 300 Gems, eine seltene Werkzeug-Variante, ein Begleiter").
-- Eine Zeile je Angebot. Die Regeln stehen in Logic/Offers (Zustand, Auslöser, Kauf-Handler,
-- Reihenfolge der Hinweise), DataCheck.checkOffers prüft die Tabelle beim Serverstart.
--
-- Entscheidung (Plan 4.5): Das Angebot erscheint direkt nach dem ersten Fund ab `minRarityId` und
-- ist ab dann `windowHours` Stunden kaufbar (Server-Uhr, Unix-Zeit, läuft auch offline weiter).
-- Der Inhalt ist fest (`gems`, `items`), es gibt keinen Zufall: Ein Angebot mit Zufallsinhalt wäre
-- ein bezahltes Zufallsitem (Policy ArePaidRandomItemsRestricted, Quotenpflicht). DataCheck lässt
-- darum nur feste Item-IDs aus Data/CrateItems zu (keine Kisten-IDs) und keine weiteren Felder.
--
-- WICHTIG:
--  * Die Angebots-ID (`id`) ist der Schlüssel in `profile.offers` und darf nie umbenannt werden
--    (sonst ginge der Merker "gekauft" verloren, und ein Einmalkauf erschiene erneut).
--  * Ein Angebot nie aus der Liste löschen, solange Spieler es gekauft haben können; nicht mehr
--    anbieten geht über das Produkt im Creator Dashboard.
--  * Jedes Angebot braucht ein eigenes Developer Product mit `oneTime = true` in Data/Products.
--    Der Kauf-Handler wird für jedes Angebot über dessen `productId` registriert.
--
-- Einmalkauf auf dem Server (Exploit-Review 6.1): Roblox kennt keine Einmal-Developer-Products, ein
-- manipulierter Client kann PromptProductPurchase selbst aufrufen. Nur ein Beleg, der im Fenster
-- (plus `receiptGraceMinutes`) und vor einem früheren Kauf ankommt, bekommt das Paket. Jeder andere
-- bezahlte Beleg bekommt nur `duplicateGems` Ersatz-Gems, keine Items (bezahlt ist bezahlt, aber
-- nie ein zweites Paket). DataCheck: `duplicateGems` höchstens der Gem-Gegenwert des Produktpreises
-- zum besten Paketkurs bis zu diesem Preis (sonst wäre das Angebot ein verstecktes, günstigeres
-- Gem-Paket).

export type Trigger = "firstFindFromRarity"

export type Offer = {
    id: string, -- Angebots-ID, Schlüssel in profile.offers (nie umbenennen)
    productId: string, -- Produkt-ID aus Data/Products (Developer Product, oneTime = true)
    -- Auslöser des Fensters. "firstFindFromRarity": der erste Fund (nicht Kisten-Item) mit
    -- Seltenheit mindestens `minRarityId` startet das Fenster.
    trigger: Trigger,
    minRarityId: string, -- Seltenheits-ID aus Data/Rarities (Rangfolge der Liste)
    windowHours: number, -- so viele Stunden ab dem Start ist das Angebot kaufbar (endlich, > 0)
    gems: number, -- Gems im Angebot (ganze Zahl ab 0, höchstens Economy.purchases.maxGems)
    items: { string }, -- feste Item-IDs aus Data/CrateItems, je ein Exemplar, höchstens eines je Art
    priority: number, -- Reihenfolge der Hinweise beim Client: kleinere Zahl zuerst
    -- Ersatz-Gems für einen bezahlten Beleg, der das Paket nicht bekommt (schon gekauft, Fenster nicht
    -- gestartet oder vorbei): ganze Zahl ab 0, höchstens maxGems und höchstens der Gem-Gegenwert des
    -- Produktpreises zum besten Paketkurs (DataCheck). Keine Items.
    duplicateGems: number,
    -- Nachfrist in Minuten nach dem Fensterende: Ein Beleg in dieser Zeit bekommt noch das Paket
    -- (Kaufdialog über das Fensterende offen, Uhren verschiedener Server). Ganze Zahl von 0 bis 60.
    receiptGraceMinutes: number,
}

local list: { Offer } = {
    {
        id = "starter",
        productId = "starter_pack",
        trigger = "firstFindFromRarity",
        minRarityId = "rare",
        windowHours = 24,
        gems = 300,
        -- Glasschaufel (Werkzeug-Variante, Selten) und Wüstengecko (Begleiter, Ungewöhnlich).
        items = { "toolVariant_rare_1", "companion_uncommon_1" },
        priority = 1,
        -- Gem-Gegenwert von 149 Robux in Paketen: 3 x 100 Gems für 147 Robux. Obergrenze laut DataCheck:
        -- 149 x 100 / 49 = 304 (bester Kurs bis 149 Robux ist das 100er-Paket). Wie beim Saison-Pass
        -- (Economy.seasonPass.duplicateGems): Der Spieler verliert nichts, ein absichtlicher Zweitkauf
        -- bringt keinen besseren Kurs als die Gem-Pakete.
        duplicateGems = 300,
        receiptGraceMinutes = 15,
    },
}

local byId: { [string]: Offer } = {}
for _, offer in list do
    byId[offer.id] = offer
end

return {
    list = list,
    byId = byId,
}
