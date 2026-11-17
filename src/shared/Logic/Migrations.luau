--!strict
-- Migrationsschritte für das Spielerprofil.
-- `steps[n]` hebt ein Profil von Version n auf Version n + 1 und gibt das Profil zurück.
-- Beim Erhöhen von CURRENT_VERSION kommt hier der passende Schritt hinzu. Ein Schritt
-- ändert nur, was sich geändert hat; fehlende Felder füllt Profile.migrate danach selbst
-- mit den Standardwerten auf. Alte Spielstände dürfen nie durch ein Update brechen.

export type Step = (profile: any) -> any

local Migrations = {
    CURRENT_VERSION = 1,
    steps = {} :: { [number]: Step },
}

return Migrations
