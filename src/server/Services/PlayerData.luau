--!strict
-- PlayerData-Service
-- Zuständig: Profil laden, im Speicher halten und speichern (ProfileStore), Migration über
-- Profile.migrate, Sitzungssperre, Speichern beim Verlassen. Wird in Paket 1.1 gefüllt.

local PlayerData = {}

function PlayerData.Init()
    -- Noch leer: Abhängigkeiten anderer Services werden hier nicht benutzt.
end

function PlayerData.Start()
    -- Noch leer: Verbindungen und Schleifen starten hier, wenn das Paket sie füllt.
end

return PlayerData
