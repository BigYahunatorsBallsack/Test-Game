--!strict
-- Server-Bootstrap. Reihenfolge: Daten prüfen, Remotes anlegen, Services laden,
-- alle Init(), dann alle Start(), dann die optionalen AfterStart(). Jeder Schritt wird gedruckt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Reihenfolge der Services (fest). Neue Services hier am Ende ergänzen, außer eine Abhängigkeit
-- verlangt einen anderen Platz: Passes (Paket 4.4) und Offers (Paket 4.5) stehen vor Shop, damit sie
-- ihre Kauf-Handler (Münz-Boost, Starterpaket) in ihrem Start registrieren, bevor Shop.Start
-- ProcessReceipt setzt. Offers steht nach Finds und meldet sich in Init für gebuchte Funde an.
local SERVICE_NAMES = { "PlayerData", "Economy", "Sand", "ZoneService", "Finds", "Upgrades", "Crates", "Equipment", "Passes", "Offers", "Shop", "Events" }

type Service = {
    Init: () -> (),
    Start: () -> (),
    AfterStart: (() -> ())?, -- optional: Prüfungen, wenn alle Services gestartet sind
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

-- 5. Nach allen Start(): Abschlussprüfungen (zum Beispiel Shop: jedes Produkt mit ProductId hat
-- einen Handler). Das ist eine laute Prüfung für Entwickler, keine Sperre: Ein Fehler wird gemeldet,
-- der Server läuft weiter, und die anderen AfterStart() laufen trotzdem. Die eigentliche Absicherung
-- bleibt, eine ProductId erst einzutragen, wenn ihr Handler existiert.
local afterStartFailures: { string } = {}
for _, entry in services do
    local afterStart = entry.service.AfterStart
    if afterStart ~= nil then
        local ok, err = pcall(afterStart)
        if ok then
            print(`[Server] AfterStart: {entry.name}`)
        else
            table.insert(afterStartFailures, `{entry.name}: {tostring(err)}`)
        end
    end
end
for _, failure in afterStartFailures do
    warn(`[Server] AfterStart fehlgeschlagen, bitte beheben: {failure}`)
end

print("[Server] Dune Baron läuft")
