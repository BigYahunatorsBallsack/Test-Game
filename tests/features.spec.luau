--!strict
-- Überarbeitung Ü1: System-Schalter (Data/Features, Logic/Features).

local fs = require("@lune/fs")
local T = require("./lib/expect")
local Features = require("../src/shared/Logic/Features")
local Data = require("../src/shared/Data/Features")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local DataCheck = require("../src/shared/Logic/DataCheck")

local function fileNames(dir: string): { string }
    local names: { string } = {}
    for _, entry in fs.readDir(dir) do
        local name = string.match(entry, "^(.-)%.luau$")
        if name ~= nil then
            table.insert(names, name)
        end
    end
    return names
end

-- Ist im Server-Code ein Kauf-Handler registriert, der in Init oder StartDisabled liegt?
local function registersOutsideStart(source: string): boolean
    local inAllowed = false
    for line in string.gmatch(source, "[^\n]+") do
        if string.match(line, "^function [%w_]+%.Init%(") or string.match(line, "^function [%w_]+%.StartDisabled%(") or string.match(line, "^local function registerHandlers%(") then
            inAllowed = true
        elseif string.match(line, "^function ") or string.match(line, "^local function ") then
            inAllowed = false
        end
        if inAllowed and string.find(line, "registerProduct", 1, true) then
            return true
        end
    end
    return false
end

T.describe("Features: Tabelle", function()
    T.it("jeder Schalter ist ein Wahrheitswert, DataCheck meldet nichts", function()
        for id, value in Data.systems do
            T.expect(type(id)).toBe("string")
            T.expect(type(value)).toBe("boolean")
        end
        T.expect(#Features.check(Data)).toBe(0)
        for _, message in DataCheck.run() do
            T.expect(string.find(message, "Features", 1, true)).toBeNil()
        end
    end)

    T.it("Kern ist an, die Zusatzsysteme sind aus (Plan 5.3)", function()
        for _, id in { "workshop", "collection", "sandstorm", "shop" } do
            T.expect(Features.on(id)).toBe(true)
        end
        for _, id in { "offers", "daily", "codes", "seasonPass", "eventZone", "koloss", "social", "offline" } do
            T.expect(Features.on(id)).toBe(false)
        end
    end)

    T.it("Services, Controller und Remotes in der Tabelle gibt es wirklich", function()
        local errors = Features.check(Data, {
            services = fileNames("src/server/Services"),
            controllers = fileNames("src/client/Controllers"),
            remotes = (function()
                local names = {}
                for _, def in RemoteSpec.list do
                    table.insert(names, def.name)
                end
                return names
            end)(),
        })
        T.expect(#errors).toBe(0)
    end)

    T.it("check meldet kaputte Einträge", function()
        local broken = {
            systems = { a = true, b = "ja" },
            services = { X = "fehlt" },
            remotes = { NichtDa = "a" },
        }
        local errors = Features.check(broken, { remotes = { "Sell" } })
        T.expect(#errors).toBe(3)
        T.expect(#Features.check(nil)).toBe(1)
    end)

    T.it("unbekanntes System gilt als aus", function()
        T.expect(Features.on("gibtsnicht")).toBe(false)
    end)
end)

T.describe("Features: Server", function()
    T.it("Remotes eines ausgeschalteten Systems sind nicht aktiv, Kern-Remotes immer", function()
        for name, systemId in Data.remotes do
            T.expect(Features.remoteActive(name)).toBe(Features.on(systemId))
        end
        for _, name in { "Sell", "SetCollecting", "PurchaseNode", "OpenCrate", "TravelZone", "Prestige", "BuyDirectItem" } do
            T.expect(Features.remoteActive(name)).toBe(true)
        end
        T.expect(Features.remoteActive("ClaimDaily")).toBe(false)
    end)

    T.it("Services ohne Eintrag laufen, ausgeschaltete nicht", function()
        T.expect(Features.serviceActive("Sand")).toBe(true)
        T.expect(Features.serviceActive("Shop")).toBe(true)
        T.expect(Features.serviceActive("Offline")).toBe(false)
        T.expect(Features.serviceActive("Daily")).toBe(false)
    end)

    T.it("jeder ausschaltbare Service mit Kauf-Handlern registriert sie auch ausgeschaltet", function()
        for serviceName in Data.services do
            local source = fs.readFile(`src/server/Services/{serviceName}.luau`)
            if string.find(source, "registerProduct", 1, true) then
                T.expect(registersOutsideStart(source)).toBe(true)
            end
        end
    end)

    T.it("Bootstrap ruft für ausgeschaltete Services StartDisabled statt Start", function()
        local source = fs.readFile("src/server/init.server.luau")
        T.expect(string.find(source, "Features.serviceActive(name)", 1, true) ~= nil).toBe(true)
        T.expect(string.find(source, "StartDisabled", 1, true) ~= nil).toBe(true)
        local net = fs.readFile("src/server/Net/Net.luau")
        T.expect(string.find(net, "Features.remoteActive(name)", 1, true) ~= nil).toBe(true)
    end)
end)

T.describe("Features: Client", function()
    T.it("activeControllers lässt ausgeschaltete weg und behält die Reihenfolge", function()
        local names = { "State", "Daily", "Hud", "OfferHint", "SkillTree", "OfflineCard" }
        local active = Features.activeControllers(names)
        T.expect(#active).toBe(3)
        T.expect(active[1]).toBe("State")
        T.expect(active[2]).toBe("Hud")
        T.expect(active[3]).toBe("SkillTree")
    end)

    T.it("kein aktiver Controller braucht einen ausgeschalteten", function()
        for _, name in fileNames("src/client/Controllers") do
            if not Features.controllerActive(name) then
                continue
            end
            local source = fs.readFile(`src/client/Controllers/{name}.luau`)
            for other in Data.controllers do
                if not Features.controllerActive(other) then
                    T.expect(string.find(source, `WaitForChild("{other}")`, 1, true)).toBeNil()
                end
            end
        end
    end)

    T.it("Kisten, Gems und Ausrüstung stehen im Shop, Sammlung und Zonen nicht", function()
        T.expect(Features.inShop("CratesButton")).toBe(true)
        T.expect(Features.inShop("GemsButton")).toBe(true)
        T.expect(Features.inShop("EquipmentButton")).toBe(true)
        T.expect(Features.inShop("CollectionButton")).toBe(false)
        T.expect(Features.inShop("ZonesButton")).toBe(false)
    end)
end)

T.describe("Features: Event-Zone", function()
    T.it("ausgeschaltet ist die Event-Zone nie offen", function()
        local Zones = require("../src/shared/Data/Zones")
        local ZoneLogic = require("../src/shared/Logic/Zones")
        local event = Zones.events[1]
        if event == nil then
            return
        end
        local profile = { nodes = {}, zones = {} }
        for t = 0, 365 * 86400 * 3, 86400 * 3 do
            T.expect(ZoneLogic.isUnlocked(profile, event.id, 1_700_000_000 + t)).toBe(false)
        end
    end)
end)

T.finish()
