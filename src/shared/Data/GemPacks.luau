--!strict
-- Gem-Pakete (Developer Products), Konzept: "Gem-Pakete".
-- `bonusPercentConcept` ist die Konzeptspalte "Bonus gegenüber dem kleinsten Paket" in
-- Prozent. DataCheck rechnet den Bonus aus gems und robux nach (Toleranz 1 Prozentpunkt).
-- productId = 0 ist ein Platzhalter bis zur Anlage im Creator Dashboard.

export type GemPack = {
    id: string,
    name: string, -- Anzeigename für Spieler
    gems: number,
    robux: number,
    bonusPercentConcept: number,
    productId: number, -- Developer-Product-ID (0 = Platzhalter)
}

local list: { GemPack } = {
    { id = "gems_100", name = "100 Gems", gems = 100, robux = 49, bonusPercentConcept = 0, productId = 0 },
    { id = "gems_550", name = "550 Gems", gems = 550, robux = 249, bonusPercentConcept = 8, productId = 0 },
    { id = "gems_1200", name = "1.200 Gems", gems = 1200, robux = 499, bonusPercentConcept = 18, productId = 0 },
    { id = "gems_3200", name = "3.200 Gems", gems = 3200, robux = 1199, bonusPercentConcept = 31, productId = 0 },
    { id = "gems_7000", name = "7.000 Gems", gems = 7000, robux = 2499, bonusPercentConcept = 37, productId = 0 },
}

local byId: { [string]: GemPack } = {}
for _, pack in list do
    byId[pack.id] = pack
end

return {
    list = list,
    byId = byId,
}
