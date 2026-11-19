--!strict
-- Sammlung (Paket 2.6): Bonus je fertigem Set und Belohnung je fertigem Zonenbuch.
-- Ein Set ist fertig, wenn alle Slots mindestens einmal gefunden sind (Logic/Collection).
-- Bonus in Hundertstel-Prozent (10000 = 100 %) auf die Münzen pro Sand, alle Boni addieren sich.
-- Die Zahlen sind Startwerte, die Prüfung steht in docs/balance/collection_2_6.md.
-- Titel und Skin des Zonenbuchs werden in 2.6 nur angezeigt. Die Anzeige über dem Kopf und der
-- Skin am Werkzeug kommen mit eigenen Paketen.

export type ZoneBook = {
    zoneId: string,
    title: string, -- Titel für den Spieler
    toolSkinId: string, -- Werkzeug-Skin (Platzhalter-ID)
}

-- Bonus je Set-Nummer (1 bis SETS_PER_ZONE), in jeder Zone gleich.
local setBonusBp: { [number]: number } = {
    [1] = 300,
    [2] = 300,
    [3] = 400,
    [4] = 400,
    [5] = 600,
    [6] = 1000,
}

local zoneBooks: { ZoneBook } = {
    { zoneId = "dunes", title = "Dünenwanderer", toolSkinId = "skin_dunes_book" },
    { zoneId = "oasis", title = "Oasenhüter", toolSkinId = "skin_oasis_book" },
    { zoneId = "canyon", title = "Canyonspäher", toolSkinId = "skin_canyon_book" },
    { zoneId = "salt_lake", title = "Salzsammler", toolSkinId = "skin_salt_lake_book" },
    { zoneId = "ruins", title = "Ruinenforscher", toolSkinId = "skin_ruins_book" },
}

local zoneBooksByZone: { [string]: ZoneBook } = {}
for _, book in zoneBooks do
    zoneBooksByZone[book.zoneId] = book
end

return {
    setBonusBp = setBonusBp,
    zoneBooks = zoneBooks,
    zoneBooksByZone = zoneBooksByZone,
}
