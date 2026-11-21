--!strict
-- Weitere Produkte (Konzept: "Weitere Produkte"). Preise in Robux.
-- productId = 0 ist ein Platzhalter bis zur Anlage im Creator Dashboard
-- (Gamepass-ID bzw. Developer-Product-ID).
--
-- Gamepasses (Paket 4.4): `perk` nennt die Wirkung. Der Code kennt Wirkungen nur über `perk`
-- (Logic/Perks), nie über die Produkt-ID. Jede Wirkung gehört zu genau einem Gamepass (DataCheck).
-- Die Produkt-ID eines Gamepasses ist zugleich der Schlüssel in `profile.passes` und darf darum
-- nie umbenannt werden (sonst braucht es einen Schritt in Logic/Migrations).
--
-- WICHTIG für Gamepasses (Security-Review 4.4), sonst verlieren zahlende Spieler ihren Pass:
--  * Eine eingetragene Roblox-Gamepass-ID (`productId` > 0) nie mehr ändern. Der Server fragt beim
--    Laden UserOwnsGamePassAsync mit genau dieser ID ab; für eine neue ID sagt Roblox bei allen
--    bisherigen Käufern "nein", und nach dem zweiten "nein" wird der Pass aus dem Spielstand entfernt.
--  * Einen Gamepass nicht verkaufen (im Creator Dashboard nicht auf "zum Verkauf"), solange hier
--    noch `productId = 0` steht: Der Server kann den Kauf dann weder bestätigen noch beim Laden
--    finden, der Spieler hätte bezahlt und bekäme nichts.
--  * Einen Gamepass nie aus dieser Liste löschen (auch nicht, wenn er nicht mehr verkauft wird).
--    Profile.sanitize behält in `profile.passes` nur bekannte Gamepass-IDs und würde den Pass bei
--    allen Spielern beim nächsten Laden löschen. Nicht mehr verkaufen geht im Creator Dashboard.

export type Product = {
    id: string,
    kind: "gamepass" | "developerProduct" | "direct",
    name: string, -- Anzeigename für Spieler
    priceRobux: number, -- bei Spannen der kleinste Preis
    priceRobuxMax: number?, -- nur bei Preisspannen (Direktkauf)
    productId: number, -- 0 = Platzhalter
    oneTime: boolean, -- nur einmal kaufbar
    consumable: boolean, -- wird verbraucht
    effect: string, -- Wirkung (Kurzbeschreibung)
    perk: ("doubleCoins" | "autoDig" | "bigTank")?, -- nur Gamepasses: Wirkung im Code (Paket 4.4)
}

local list: { Product } = {
    {
        id = "starter_pack",
        kind = "developerProduct",
        name = "Starterpaket",
        priceRobux = 149,
        priceRobuxMax = nil,
        productId = 0,
        oneTime = true,
        consumable = false,
        -- Angebot "starter" in Data/Offers (Paket 4.5): erscheint direkt nach dem ersten Fund ab
        -- "Selten" und ist ab dann 24 Stunden kaufbar. Inhalt (Gems, feste Items) steht dort.
        effect = "300 Gems, eine seltene Werkzeug-Variante, ein Begleiter",
    },
    {
        id = "double_coins",
        kind = "gamepass",
        name = "2x Münzen",
        priceRobux = 399,
        priceRobuxMax = nil,
        productId = 0,
        oneTime = true,
        consumable = false,
        effect = "Doppelte Münzen aus allen Verkäufen",
        perk = "doubleCoins",
    },
    {
        id = "auto_dig",
        kind = "gamepass",
        name = "Auto-Dig",
        priceRobux = 499,
        priceRobuxMax = nil,
        productId = 0,
        oneTime = true,
        consumable = false,
        -- Seit 5.3 verspricht der Text die Offline-Grenze von 12 statt 4 Stunden (Economy.offline, nur mit
        -- ausgerüstetem Begleiter, docs/balance/passes_4_4.md).
        effect = "Das Werkzeug sammelt automatisch, solange du im Spiel bist. Dein Begleiter sammelt offline bis zu 12 statt 4 Stunden",
        perk = "autoDig",
    },
    {
        id = "big_tank",
        kind = "gamepass",
        name = "Großer Tank",
        priceRobux = 199,
        priceRobuxMax = nil,
        productId = 0,
        oneTime = true,
        consumable = false,
        effect = "Mehr Platz, seltener zum Händler laufen",
        perk = "bigTank",
    },
    {
        id = "season_pass",
        kind = "developerProduct",
        name = "Saison-Pass",
        priceRobux = 399,
        priceRobuxMax = nil,
        productId = 0,
        oneTime = false,
        consumable = false,
        effect = "Premium-Spur mit Gems, Skins und festen Event-Items (4 Wochen)",
    },
    {
        id = "coin_boost",
        kind = "developerProduct",
        name = "Münz-Boost",
        priceRobux = 49,
        priceRobuxMax = nil,
        productId = 0,
        oneTime = false,
        consumable = true,
        effect = "30 Minuten doppelte Münzen, läuft in Echtzeit",
    },
    {
        id = "skins_direct",
        kind = "direct",
        name = "Skins und Event-Shop",
        priceRobux = 99,
        priceRobuxMax = 799,
        productId = 0,
        oneTime = false,
        consumable = false,
        effect = "Reine Optik und limitierte Sammelstücke",
    },
}

local byId: { [string]: Product } = {}
for _, product in list do
    byId[product.id] = product
end

return {
    list = list,
    byId = byId,
}
