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
    CURRENT_VERSION = 2,
    steps = {} :: { [number]: Step },
}

-- Version 1 -> 2 (Paket 2.5, gemischter Tank): Der Tank merkt sich die Sandsorte. Der alte Tank
-- wird zu Sand der Zone, in der der Spieler beim Speichern stand.
Migrations.steps[1] = function(profile: any): any
    if type(profile.tankMix) ~= "table" then
        profile.tankMix = {}
    end
    local tank = profile.tank
    if isValidBigNum(tank) and tank.m > 0 then
        local sandType = LEGACY_SAND_TYPE[profile.currentZone] or LEGACY_FALLBACK_SAND_TYPE
        profile.tankMix[sandType] = { m = tank.m, e = tank.e }
    end
    return profile
end

return Migrations
