--!strict
-- Weitere Produkte (Konzept: "Weitere Produkte"). Preise in Robux.
-- productId = 0 ist ein Platzhalter bis zur Anlage im Creator Dashboard
-- (Gamepass-ID bzw. Developer-Product-ID).

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
        -- Erscheint 24 Stunden nach dem ersten Selten-Fund.
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
        effect = "Das Werkzeug sammelt automatisch, solange du im Spiel bist. "
            .. "Die Offline-Grenze steigt von 4 auf 12 Stunden",
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
        effect = "30 Minuten doppelte Münzen",
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
