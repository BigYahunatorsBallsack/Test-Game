--!strict
-- Migrationsschritte für das Spielerprofil.
-- `steps[n]` hebt ein Profil von Version n auf Version n + 1 und gibt das Profil zurück.
-- Beim Erhöhen von CURRENT_VERSION kommt hier der passende Schritt hinzu. Ein Schritt
-- ändert nur, was sich geändert hat; fehlende Felder füllt Profile.migrate danach selbst
-- mit den Standardwerten auf. Alte Spielstände dürfen nie durch ein Update brechen.

export type Step = (profile: any) -> any

-- Sandsorte je Zone, wie sie bei Version 1 galt. Fest eingetragen (nicht aus den Datentabellen),
-- damit ein späteres Update der Tabellen die Migration alter Spielstände nicht verändert.
local LEGACY_SAND_TYPE = {
    dunes = "yellow",
    oasis = "red",
    canyon = "white",
    salt_lake = "crystal",
    ruins = "black",
}
local LEGACY_FALLBACK_SAND_TYPE = "yellow"
-- Werte, die in der alten Beleg-Tabelle (bis Version 3) einen Beleg markieren.
local LEGACY_RECEIPT_MARKER_TYPES: { [string]: boolean } = { boolean = true, number = true, string = true, table = true }

local function isValidBigNum(value: any): boolean
    return type(value) == "table"
        and type(value.m) == "number"
        and type(value.e) == "number"
        and value.m == value.m
        and value.e == value.e
        and value.m ~= math.huge
        and value.m ~= -math.huge
        and value.e ~= math.huge
        and value.e ~= -math.huge
end

local Migrations = {
    CURRENT_VERSION = 7,
    steps = {} :: { [number]: Step },
}

-- Version 1 -> 2 (Paket 2.5, gemischter Tank): Der Tank merkt sich die Sandsorte. Der alte Tank
-- wird zu Sand der Zone, in der der Spieler beim Speichern stand.
Migrations.steps[1] = function(profile: any): any
    -- Version 1 kannte keinen Mix: Ein vorhandener Mix (kaputtes Versionsfeld) wird verworfen.
    profile.tankMix = {}
    local tank = profile.tank
    if isValidBigNum(tank) and tank.m > 0 then
        local sandType = LEGACY_SAND_TYPE[profile.currentZone] or LEGACY_FALLBACK_SAND_TYPE
        profile.tankMix[sandType] = { m = tank.m, e = tank.e }
    end
    return profile
end

-- Version 2 -> 3 (Paket 2.7, Sandsturm): `runEarned` zählt die Verkaufseinnahmen des Laufs. Ältere
-- Spielstände kennen sie nicht. Als Schätzung gelten die aktuellen Münzen (eine untere Grenze, die
-- Ausgaben nicht kennt), so fängt ein bestehender Lauf nicht bei 0 an.
Migrations.steps[2] = function(profile: any): any
    if isValidBigNum(profile.coins) and profile.coins.m > 0 then
        profile.runEarned = { m = profile.coins.m, e = profile.coins.e }
    else
        profile.runEarned = { m = 0, e = 0 }
    end
    return profile
end

-- Version 3 -> 4 (Paket 4.1, sichere Käufe): `receipts` war eine Tabelle { [PurchaseId] = true } und
-- wird eine Liste der PurchaseIds (neueste am Ende, Länge begrenzt in Profile.sanitize). Die alte
-- Tabelle kennt keine Reihenfolge, darum kommen ihre Schlüssel sortiert (gleiches Ergebnis bei jedem
-- Laden). Steht schon ein Listenteil drin (kaputtes Versionsfeld), folgt er danach in seiner
-- Reihenfolge. Jede PurchaseId bleibt erhalten, damit kein bezahlter Kauf zweimal gebucht wird.
-- `purchaseLog` und `spent` füllt Profile.migrate mit den Standardwerten.
Migrations.steps[3] = function(profile: any): any
    local old = profile.receipts
    local ids: { string } = {}
    if type(old) == "table" then
        local seen: { [string]: boolean } = {}
        local keys: { string } = {}
        local positions: { number } = {}
        for key, value in old do
            if type(key) == "string" then
                -- Jeder speicherbare Wert außer false markiert einen Beleg (lieber eine PurchaseId
                -- zu viel behalten als einen Kauf doppelt buchen).
                if key ~= "" and value ~= false and LEGACY_RECEIPT_MARKER_TYPES[type(value)] then
                    table.insert(keys, key)
                end
            elseif type(key) == "number" and type(value) == "string" and value ~= "" then
                table.insert(positions, key)
            end
        end
        table.sort(keys)
        table.sort(positions)
        for _, key in keys do
            if not seen[key] then
                seen[key] = true
                table.insert(ids, key)
            end
        end
        for _, position in positions do
            local id = old[position]
            if not seen[id] then
                seen[id] = true
                table.insert(ids, id)
            end
        end
    end
    profile.receipts = ids
    return profile
end

-- Version 4 -> 5 (Paket 4.3, Kisten-Items): `equipped` (Item-ID je Slot, "" = leer) und `itemStars`
-- (Sterne ab ★2) sind neu. Inventar und Pity bleiben, nichts ist ausgerüstet, alle Items sind ★1.
Migrations.steps[4] = function(profile: any): any
    -- Nur anlegen, was fehlt: Läuft die Kette bei einem kaputten Versionsfeld erneut, bleiben
    -- vorhandene Sterne erhalten (sie stehen für verbrauchte Kopien aus bezahlten Kisten).
    if type(profile.equipped) ~= "table" then
        profile.equipped = { skin = "", companion = "", toolVariant = "" }
    end
    if type(profile.itemStars) ~= "table" then
        profile.itemStars = {}
    end
    return profile
end

-- Version 5 -> 6 (Paket 4.4, Gamepasses und Münz-Boost): `passes` (gemerkter Gamepass-Besitz,
-- { [passId] = true }) und `settings` (Einstellungen, zuerst `autoDig`, Standard an) sind neu. Nur
-- anlegen, was fehlt: Läuft die Kette bei einem kaputten Versionsfeld erneut, bleibt gemerkter
-- Besitz erhalten (er steht für bezahlte Pässe). `boosts.coinsUntil` gab es schon, es bleibt.
-- Der Standardwert steht hier fest (nicht aus Logic/Perks), damit ein späteres Update die Migration
-- alter Spielstände nicht verändert.
Migrations.steps[5] = function(profile: any): any
    if type(profile.passes) ~= "table" then
        profile.passes = {}
    end
    if type(profile.settings) ~= "table" then
        profile.settings = { autoDig = true }
    elseif type(profile.settings.autoDig) ~= "boolean" then
        profile.settings.autoDig = true
    end
    return profile
end

-- Version 6 -> 7 (Paket 4.5, Angebote): `offers` ({ [offerId] = { since, bought } }) ist neu. Nur
-- anlegen, was fehlt: Läuft die Kette bei einem kaputten Versionsfeld erneut, bleibt ein vorhandener
-- Merker "gekauft" erhalten (er steht für einen bezahlten Einmalkauf). Die Einträge je Angebot
-- ({ since = 0, bought = false }) füllt Profile.migrate danach aus dem Standardprofil auf.
-- Das Fenster alter Spielstände, die schon einen Fund ab "Selten" haben, startet nicht hier (die
-- Migration kennt keine Uhr), sondern beim Laden auf dem Server (Logic/Offers.migrateStart).
Migrations.steps[6] = function(profile: any): any
    if type(profile.offers) ~= "table" then
        profile.offers = {}
    end
    return profile
end

return Migrations
