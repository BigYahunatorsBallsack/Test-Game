--!strict
-- Saison-Uhr (Paket 5.5): die Zeit, nach der der Server den Saison-Kalender für einen Spieler rechnet.
-- Das ist die Server-Uhr (os.time, nie eine Zeit vom Client). Nur in Studio kann die Hilfe DebugSeason
-- (Services/Events) sie für einen Spieler in eine Woche der Saison ("week:N") oder einen Tag nach ihr
-- Ende ("ended", Abholfrist des Saison-Passes, Paket 5.5b) verschieben, damit sich Event-Zone,
-- Event-Kiste, Punkte, Abholen und der Kauf-Handler des Passes ohne Warten testen lassen. In einem
-- Live-Server gibt es nie eine Verschiebung: `set` tut dort nichts und `timeFor` liest keine.
-- Kein Service (kein Init, kein Start), nur ein gemeinsames Modul für Events, Crates, Sand, Zonen und
-- SeasonPasses.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local SeasonsLogic = require(shared:WaitForChild("Logic"):WaitForChild("Seasons") :: ModuleScript) :: any

local IS_STUDIO = RunService:IsStudio()

local SeasonClock = {}

-- Studio-Hilfe je Spieler: { action = "off" | "week" | "ended", week = number? }. Leer = echte Zeit.
local overrides: { [Player]: { action: string, week: number? } } = {}

-- Zeit für den Kalender dieses Spielers (Unix-Sekunden).
function SeasonClock.timeFor(player: Player?): number
    local now = os.time()
    if IS_STUDIO and player ~= nil then
        local override = overrides[player]
        if override ~= nil then
            local shifted = SeasonsLogic.debugTime(override.action, override.week, now)
            if shifted ~= nil then
                return shifted
            end
        end
    end
    return now
end

-- Setzt oder löscht (action nil) die Verschiebung. Nur in Studio.
function SeasonClock.set(player: Player, action: string?, week: number?)
    if not IS_STUDIO then
        return
    end
    if action == nil then
        overrides[player] = nil
    else
        overrides[player] = { action = action, week = week }
    end
end

function SeasonClock.forget(player: Player)
    overrides[player] = nil
end

Players.PlayerRemoving:Connect(SeasonClock.forget)

return SeasonClock
