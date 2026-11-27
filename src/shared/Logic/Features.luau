--!strict
-- Regeln zu den System-Schaltern (Überarbeitung Ü1). Rein, ohne Roblox-API, Lune-Tests in
-- tests/features.spec.luau. Die Tabelle steht in Data/Features; jede Funktion nimmt optional eine
-- andere Tabelle (für Tests).

local Data = require("../Data/Features")

local Features = {}

-- Ist das System an? Unbekannte Systeme gelten als aus (sicherer Standard).
function Features.on(systemId: string, data: any?): boolean
    local source = data or Data
    local systems = source.systems
    return type(systems) == "table" and systems[systemId] == true
end

-- Gehört der Eintrag (Service, Controller, Remote) zu keinem System oder zu einem eingeschalteten?
local function active(map: any, name: string, data: any?): boolean
    if type(map) ~= "table" then
        return true
    end
    local systemId = map[name]
    if systemId == nil then
        return true
    end
    return Features.on(systemId, data)
end

function Features.serviceActive(name: string, data: any?): boolean
    return active((data or Data).services, name, data)
end

function Features.controllerActive(name: string, data: any?): boolean
    return active((data or Data).controllers, name, data)
end

function Features.remoteActive(name: string, data: any?): boolean
    return active((data or Data).remotes, name, data)
end

-- Die Namen aus `names`, deren Controller laufen sollen (Reihenfolge bleibt).
function Features.activeControllers(names: { string }, data: any?): { string }
    local result: { string } = {}
    for _, name in names do
        if Features.controllerActive(name, data) then
            table.insert(result, name)
        end
    end
    return result
end

-- Steht der Menüknopf im Fenster "Shop" statt in der Leiste?
function Features.inShop(buttonId: string, data: any?): boolean
    local shop = (data or Data).shop
    if type(shop) ~= "table" or type(shop.members) ~= "table" then
        return false
    end
    return table.find(shop.members, buttonId) ~= nil
end

-- Prüft die Tabelle. `known` sind die bekannten Namen je Art (Services, Controller, Remotes); fehlt
-- eine Art, wird sie nicht gegen Namen geprüft. Gibt eine Liste von Fehlertexten zurück.
function Features.check(data: any, known: { services: { string }?, controllers: { string }?, remotes: { string }? }?): { string }
    local errors: { string } = {}
    if type(data) ~= "table" or type(data.systems) ~= "table" then
        table.insert(errors, "Features: systems fehlt")
        return errors
    end
    for id, value in data.systems do
        if type(id) ~= "string" or type(value) ~= "boolean" then
            table.insert(errors, `Features: systems.{tostring(id)} muss true oder false sein`)
        end
    end
    local function checkMap(kind: string, names: { string }?)
        local map = data[kind]
        if map == nil then
            return
        end
        if type(map) ~= "table" then
            table.insert(errors, `Features: {kind} muss eine Tabelle sein`)
            return
        end
        for name, systemId in map do
            if type(name) ~= "string" then
                table.insert(errors, `Features: {kind} hat einen Schlüssel, der kein Text ist`)
                continue
            end
            if type(systemId) ~= "string" or type(data.systems[systemId]) ~= "boolean" then
                table.insert(errors, `Features: {kind}.{name} nennt das unbekannte System {tostring(systemId)}`)
            end
            if names ~= nil and table.find(names, name) == nil then
                table.insert(errors, `Features: {kind}.{name} gibt es nicht`)
            end
        end
    end
    local k = known or {}
    checkMap("services", k.services)
    checkMap("controllers", k.controllers)
    checkMap("remotes", k.remotes)
    local shop = data.shop
    if shop ~= nil then
        if type(shop) ~= "table" or type(shop.buttonId) ~= "string" or type(shop.title) ~= "string" or type(shop.members) ~= "table" then
            table.insert(errors, "Features: shop braucht buttonId, title und members")
        end
    end
    return errors
end

return Features
