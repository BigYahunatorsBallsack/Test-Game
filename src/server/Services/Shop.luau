--!strict
-- Shop-Service
-- Zuständig: Käufe (ProcessReceipt, idempotent), Gamepasses, Gem-Pakete, Produkte,
-- Policy-Funktionen (ArePaidRandomItemsRestricted). Wird in Paket 4.1, 4.4 und 4.6 gefüllt.

local Shop = {}

function Shop.Init()
    -- Noch leer: Abhängigkeiten anderer Services werden hier nicht benutzt.
end

function Shop.Start()
    -- Noch leer: Verbindungen und Schleifen starten hier, wenn das Paket sie füllt.
end

return Shop
