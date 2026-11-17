--!strict
-- Sand-Service
-- Zuständig: Sammeln, Tank und Verkaufen. Der Server berechnet den Sand aus Zeit und
-- Rate, der Client meldet nur "ich halte" (SetCollecting) und "ich verkaufe" (Sell).
-- Wird in Paket 1.2 gefüllt.

local Sand = {}

function Sand.Init()
    -- Noch leer: Abhängigkeiten anderer Services werden hier nicht benutzt.
end

function Sand.Start()
    -- Noch leer: Verbindungen und Schleifen starten hier, wenn das Paket sie füllt.
end

return Sand
