--!strict
-- Server-Seite der Remotes: legt die Remotes aus RemoteSpec an und verbindet Handler.
-- Vor jedem Handler prüft Net.on: Profil geladen, Argumente (Validate), Rate-Limit
-- (RateLimiter). Verstöße werden verworfen und pro Spieler gezählt, kein Kick.
-- Handler bekommen nur geprüfte Argumente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared-Module per Instanz laden (Server und Shared liegen in verschiedenen Services,
-- ein relativer Pfad-String reicht dort nicht).
local function loadShared(folder: string, name: string): any
    local shared = ReplicatedStorage:WaitForChild("Shared")
    local module = shared:WaitForChild(folder):WaitForChild(name)
    return require(module :: ModuleScript)
end

local RemoteSpec = loadShared("Net", "RemoteSpec")
local Validate = loadShared("Logic", "Validate")
local RateLimiter = loadShared("Logic", "RateLimiter")

local REMOTES_FOLDER_NAME = "Remotes"
local WARN_FIRST_VIOLATIONS = 5 -- die ersten Verstöße eines Spielers werden einzeln gemeldet
local WARN_EVERY = 100 -- danach nur noch jeder 100. Verstoß

local Net = {}

local remotesFolder: Folder? = nil
local remotes: { [string]: Instance } = {}
local violations: { [number]: number } = {}
local handlers: { [string]: (player: Player, ...any) -> any } = {}
local limiter = RateLimiter.new(os.clock)

-- Prüft, ob das Profil des Spielers geladen ist. Paket 1.1 ersetzt das durch die echte Prüfung.
-- TODO(1.1): Net.setProfileCheck mit der PlayerData-Abfrage belegen.
local profileLoaded: (Player) -> boolean = function(_player: Player): boolean
    return true
end

function Net.setProfileCheck(check: (Player) -> boolean)
    profileLoaded = check
end

function Net.violationsOf(player: Player): number
    return violations[player.UserId] or 0
end

local function reject(player: Player, remoteName: string, reason: string)
    local count = (violations[player.UserId] or 0) + 1
    violations[player.UserId] = count
    if count <= WARN_FIRST_VIOLATIONS or count % WARN_EVERY == 0 then
        warn(`[Net] Verstoß #{count} von {player.Name} bei {remoteName}: {reason}`)
    end
end

-- Gemeinsame Prüfung. Gibt true zurück, wenn der Handler laufen darf.
local function admit(player: Player, def: any, args: { any }, argCount: number): boolean
    if not profileLoaded(player) then
        reject(player, def.name, "Profil noch nicht geladen")
        return false
    end
    local ok, reason = Validate.check(def.schema, args, argCount)
    if not ok then
        reject(player, def.name, reason or "ungültige Argumente")
        return false
    end
    if not limiter:allow(tostring(player.UserId), def.name, def.limit) then
        reject(player, def.name, "Rate-Limit überschritten")
        return false
    end
    return true
end

-- Antwort einer RemoteFunction, wenn die Prüfung bestanden ist, aber noch kein Handler da ist.
local UNAVAILABLE_REASON = "nicht verfügbar"

-- Legt alle Remotes aus RemoteSpec unter ReplicatedStorage.Remotes an und verbindet jede
-- Client->Server-Remote sofort mit der Prüfung (admit). So werden Verstöße auch dann
-- gezählt, wenn noch kein Service einen Handler registriert hat, und RemoteFunctions
-- hängen nie. Die Handler selbst trägt Net.on später ein.
function Net.init()
    local folder = Instance.new("Folder")
    folder.Name = REMOTES_FOLDER_NAME
    for _, def in RemoteSpec.list do
        local remote: Instance
        if def.kind == "Function" then
            remote = Instance.new("RemoteFunction")
        else
            remote = Instance.new("RemoteEvent")
        end
        remote.Name = def.name
        remote.Parent = folder
        remotes[def.name] = remote

        if def.direction == "ClientToServer" then
            RemoteSpec.assertRegistrable(def.name)
            if def.kind == "Function" then
                (remote :: RemoteFunction).OnServerInvoke = function(player: Player, ...: any): any
                    if not admit(player, def, { ... }, select("#", ...)) then
                        return nil
                    end
                    local handler = handlers[def.name]
                    if handler == nil then
                        return { ok = false, reason = UNAVAILABLE_REASON }
                    end
                    local ok, result = pcall(handler, player, ...)
                    if not ok then
                        warn(`[Net] Fehler im Handler {def.name}: {tostring(result)}`)
                        return nil
                    end
                    return result
                end
            else
                (remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, ...: any)
                    if not admit(player, def, { ... }, select("#", ...)) then
                        return
                    end
                    local handler = handlers[def.name]
                    if handler == nil then
                        return -- noch kein Handler: verwerfen, kein Verstoß
                    end
                    local ok, result = pcall(handler, player, ...)
                    if not ok then
                        warn(`[Net] Fehler im Handler {def.name}: {tostring(result)}`)
                    end
                end)
            end
        end
    end
    folder.Parent = ReplicatedStorage
    remotesFolder = folder

    Players.PlayerRemoving:Connect(function(player: Player)
        limiter:clear(tostring(player.UserId))
        violations[player.UserId] = nil
    end)
end

-- Trägt den Handler für eine Client->Server-Remote ein. Wirft einen Fehler, wenn die Remote
-- in RemoteSpec kein Schema oder Limit hat oder schon ein Handler registriert ist. Der
-- Handler läuft erst nach Profil-, Argument- und Rate-Limit-Prüfung (siehe Net.init).
-- Bei RemoteFunctions ist der Rückgabewert die Antwort an den Client.
function Net.on(name: string, handler: (player: Player, ...any) -> any)
    RemoteSpec.assertRegistrable(name)
    if handlers[name] ~= nil then
        error(`Net.on: für Remote "{name}" ist schon ein Handler registriert`)
    end
    handlers[name] = handler
end

-- Server -> Client (StateSync, Notify). Kein Limit.
function Net.fire(player: Player, name: string, ...: any)
    local remote = remotes[name]
    if remote == nil or not remote:IsA("RemoteEvent") then
        error(`Net.fire: "{name}" ist kein RemoteEvent`)
    end
    (remote :: RemoteEvent):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
    local remote = remotes[name]
    if remote == nil or not remote:IsA("RemoteEvent") then
        error(`Net.fireAll: "{name}" ist kein RemoteEvent`)
    end
    (remote :: RemoteEvent):FireAllClients(...)
end

return Net
