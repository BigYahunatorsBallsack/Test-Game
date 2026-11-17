--!strict
-- Server-Bootstrap. Reihenfolge: Daten prüfen, Remotes anlegen, Services laden,
-- alle Init(), dann alle Start(). Jeder Schritt wird gedruckt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Reihenfolge der Services (fest). Neue Services hier am Ende ergänzen.
local SERVICE_NAMES = { "PlayerData", "Economy", "Sand", "Finds", "Upgrades", "Crates", "Shop", "Events" }

type Service = {
    Init: () -> (),
    Start: () -> (),
}

print("[Server] Dune Baron startet")

local shared = ReplicatedStorage:WaitForChild("Shared")
local DataCheck: any = require(shared:WaitForChild("Logic"):WaitForChild("DataCheck") :: ModuleScript)

-- 1. Daten prüfen: bei Fehlern abbrechen und alle Texte ausgeben.
local dataErrors: { string } = DataCheck.run()
if #dataErrors > 0 then
    error("[Server] Datenprüfung fehlgeschlagen:\n" .. table.concat(dataErrors, "\n"))
end
print("[Server] Daten geprüft")

-- 2. Remotes anlegen.
local Net: any = require((script:WaitForChild("Net"):WaitForChild("Net")) :: ModuleScript)
Net.init()
print("[Server] Remotes angelegt")

-- 3. Services laden.
local servicesFolder = script:WaitForChild("Services")
local services: { { name: string, service: Service } } = {}
for _, name in SERVICE_NAMES do
    local module = servicesFolder:WaitForChild(name) :: ModuleScript
    table.insert(services, { name = name, service = require(module) :: Service })
    print(`[Server] Service geladen: {name}`)
end

-- 4. Alle Init(), danach alle Start().
for _, entry in services do
    entry.service.Init()
    print(`[Server] Init: {entry.name}`)
end
for _, entry in services do
    entry.service.Start()
    print(`[Server] Start: {entry.name}`)
end

print("[Server] Dune Baron läuft")
