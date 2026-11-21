--!strict
-- Paket 0.3: RemoteSpec (Schema, Limit, Registrierbarkeit).

local T = require("./lib/expect")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local Validate = require("../src/shared/Logic/Validate")
local RateLimiter = require("../src/shared/Logic/RateLimiter")
local CrateItems = require("../src/shared/Data/CrateItems")

local function validate(name: string, ...: any): boolean
    local def = RemoteSpec.byName[name]
    return (Validate.check(def.schema :: { Validate.Rule }, { ... }, select("#", ...)))
end

T.describe("RemoteSpec", function()
    T.it("alle Client->Server-Remotes haben Schema und Limit und lassen sich registrieren", function()
        local clientRemotes = 0
        for _, def in RemoteSpec.list do
            if def.direction == "ClientToServer" then
                clientRemotes += 1
                T.expect(def.schema ~= nil).toBe(true)
                T.expect(def.limit ~= nil).toBe(true)
                T.expect(select(1, RemoteSpec.canRegister(def.name))).toBe(true)
            end
        end
        T.expect(clientRemotes).toBe(11) -- 6 bis Paket 4.2, dazu EquipItem und MergeItem (4.3), SetAutoDig (4.4), BuyDirectItem (4.6), ClaimDaily (5.1)
        T.expect(RemoteSpec.byName.StateSync.direction).toBe("ServerToClient")
        T.expect(RemoteSpec.byName.Notify.direction).toBe("ServerToClient")
        T.expect(RemoteSpec.byName.StateSync.limit).toBeNil()
    end)

    T.it("Limits entsprechen dem Plan", function()
        local expected: { [string]: { number } } = {
            SetCollecting = { 10, 1 },
            Sell = { 2, 1 },
            TravelZone = { 1, 1 },
            PurchaseNode = { 5, 1 },
            OpenCrate = { 1, 1 },
            EquipItem = { 2, 1 },
            MergeItem = { 2, 1 },
            SetAutoDig = { 2, 1 },
            BuyDirectItem = { 2, 1 },
            ClaimDaily = { 1, 2 },
            Prestige = { 1, 5 },
        }
        for name, values in expected do
            local limit = RemoteSpec.byName[name].limit
            T.expect(limit ~= nil).toBe(true)
            if limit then
                T.expect(limit.calls).toBe(values[1])
                T.expect(limit.per).toBe(values[2])
            end
        end
    end)

    T.it("eine Remote ohne Schema oder ohne Limit lässt sich nicht registrieren", function()
        local specs: { [string]: RemoteSpec.RemoteDef } = {
            NoSchema = {
                name = "NoSchema",
                kind = "Event",
                direction = "ClientToServer",
                limit = { calls = 1, per = 1 },
                description = "",
            },
            NoLimit = {
                name = "NoLimit",
                kind = "Event",
                direction = "ClientToServer",
                schema = {},
                description = "",
            },
            Fine = {
                name = "Fine",
                kind = "Event",
                direction = "ClientToServer",
                schema = {},
                limit = { calls = 1, per = 1 },
                description = "",
            },
        }
        local okSchema, reasonSchema = RemoteSpec.canRegister("NoSchema", specs)
        T.expect(okSchema).toBe(false)
        T.expect(reasonSchema).toContain("Schema")
        local okLimit, reasonLimit = RemoteSpec.canRegister("NoLimit", specs)
        T.expect(okLimit).toBe(false)
        T.expect(reasonLimit).toContain("Rate-Limit")
        T.expect(select(1, RemoteSpec.canRegister("Fine", specs))).toBe(true)
        T.expect(select(1, RemoteSpec.canRegister("Unbekannt", specs))).toBe(false)
        T.expect(function()
            RemoteSpec.assertRegistrable("NoSchema", specs)
        end).toThrow("Schema")
        T.expect(function()
            RemoteSpec.assertRegistrable("NoLimit", specs)
        end).toThrow("Rate-Limit")
        T.expect((pcall(RemoteSpec.assertRegistrable, "Fine", specs))).toBe(true)
    end)

    T.it("Server->Client-Remotes und unbekannte Namen sind nicht registrierbar", function()
        T.expect(select(1, RemoteSpec.canRegister("StateSync"))).toBe(false)
        T.expect(select(1, RemoteSpec.canRegister("GibtEsNicht"))).toBe(false)
        T.expect(function()
            RemoteSpec.assertRegistrable("GibtEsNicht")
        end).toThrow("RemoteSpec")
    end)

    T.it("SetCollecting nimmt genau ein boolean", function()
        T.expect(validate("SetCollecting", true)).toBe(true)
        T.expect(validate("SetCollecting", "yes")).toBe(false)
        T.expect(validate("SetCollecting")).toBe(false)
    end)

    T.it("Sell und Prestige nehmen keine Argumente", function()
        T.expect(validate("Sell")).toBe(true)
        T.expect(validate("Sell", 1000)).toBe(false)
        T.expect(validate("Prestige")).toBe(true)
        T.expect(validate("Prestige", true)).toBe(false)
    end)

    T.it("TravelZone: bekannte Zone, Text höchstens 32 Zeichen", function()
        T.expect(validate("TravelZone", "oasis")).toBe(true)
        T.expect(validate("TravelZone", "mars")).toBe(false)
        T.expect(validate("TravelZone", string.rep("a", 33))).toBe(false)
        T.expect(validate("TravelZone", 5)).toBe(false)
    end)

    T.it("PurchaseNode: nur Knoten aus UpgradeTree", function()
        T.expect(validate("PurchaseNode", "collect_tool_2")).toBe(true)
        T.expect(validate("PurchaseNode", "gibt_es_nicht")).toBe(false)
        T.expect(validate("PurchaseNode", string.rep("a", 65))).toBe(false)
    end)

    T.it("OpenCrate: Kiste aus Crates, Anzahl 1 oder 10", function()
        T.expect(validate("OpenCrate", "gold", 1)).toBe(true)
        T.expect(validate("OpenCrate", "gold", 10)).toBe(true)
        T.expect(validate("OpenCrate", "gold", 5)).toBe(false)
        T.expect(validate("OpenCrate", "gold", 0)).toBe(false)
        T.expect(validate("OpenCrate", "gold", 1.5)).toBe(false)
        T.expect(validate("OpenCrate", "gold", 0 / 0)).toBe(false)
        T.expect(validate("OpenCrate", "diamond", 1)).toBe(false)
        T.expect(validate("OpenCrate", "gold")).toBe(false)
    end)
end)

T.describe("Remotes der Kisten-Items (4.3)", function()
    T.it("EquipItem: Slot aus der Liste, Item-ID als Text (leer = abnehmen), keine weiteren Argumente", function()
        T.expect(validate("EquipItem", "skin", "skin_common_1")).toBe(true)
        T.expect(validate("EquipItem", "companion", "")).toBe(true)
        T.expect(validate("EquipItem", "toolVariant", "toolVariant_rare_1")).toBe(true)
        T.expect(validate("EquipItem", "hut", "skin_common_1")).toBe(false)
        T.expect(validate("EquipItem", 1, "skin_common_1")).toBe(false)
        T.expect(validate("EquipItem", "skin", 5)).toBe(false)
        T.expect(validate("EquipItem", "skin", string.rep("a", 65))).toBe(false)
        T.expect(validate("EquipItem", "skin")).toBe(false)
        T.expect(validate("EquipItem", "skin", "skin_common_1", 1)).toBe(false)
    end)

    T.it("MergeItem: nur bekannte Item-IDs aus CrateItems", function()
        T.expect(validate("MergeItem", "skin_common_1")).toBe(true)
        T.expect(validate("MergeItem", "")).toBe(false)
        T.expect(validate("MergeItem", "gibt_es_nicht")).toBe(false)
        T.expect(validate("MergeItem", 7)).toBe(false)
        T.expect(validate("MergeItem", "skin_common_1", "skin_common_1")).toBe(false)
        T.expect(validate("MergeItem")).toBe(false)
    end)

    T.it("die Slot-Liste der Remote ist die Liste aus Logic/Equipment (4.3)", function()
        local rule = RemoteSpec.byName.EquipItem.schema[1]
        T.expect(rule.kind).toBe("oneOf")
        T.expect(rule.values).toEqual({ "skin", "companion", "toolVariant" })
    end)
end)

T.describe("Remote SetAutoDig (4.4)", function()
    T.it("nimmt genau ein Boolean, sonst nichts", function()
        T.expect(RemoteSpec.byName.SetAutoDig.kind).toBe("Event")
        T.expect(RemoteSpec.byName.SetAutoDig.direction).toBe("ClientToServer")
        T.expect(validate("SetAutoDig", true)).toBe(true)
        T.expect(validate("SetAutoDig", false)).toBe(true)
        T.expect(validate("SetAutoDig")).toBe(false)
        T.expect(validate("SetAutoDig", "true")).toBe(false)
        T.expect(validate("SetAutoDig", 1)).toBe(false)
        T.expect(validate("SetAutoDig", 0 / 0)).toBe(false)
        T.expect(validate("SetAutoDig", nil)).toBe(false) -- ein angehängtes nil zählt als Argument
        T.expect(validate("SetAutoDig", true, true)).toBe(false)
        T.expect(validate("SetAutoDig", { true })).toBe(false)
    end)

    T.it("Limit 2 pro Sekunde mit simulierter Uhr: der dritte Aufruf in derselben Sekunde wird abgelehnt", function()
        local clock = { t = 100 }
        local limiter = RateLimiter.new(function(): number
            return clock.t
        end)
        local limit = RemoteSpec.byName.SetAutoDig.limit :: RateLimiter.Limit
        T.expect(limiter:allow("42", "SetAutoDig", limit)).toBe(true)
        T.expect(limiter:allow("42", "SetAutoDig", limit)).toBe(true)
        T.expect(limiter:allow("42", "SetAutoDig", limit)).toBe(false)
        -- ein anderer Spieler zählt getrennt
        T.expect(limiter:allow("43", "SetAutoDig", limit)).toBe(true)
        clock.t += 0.5
        T.expect(limiter:allow("42", "SetAutoDig", limit)).toBe(true)
        T.expect(limiter:allow("42", "SetAutoDig", limit)).toBe(false)
        clock.t += 1
        T.expect(limiter:allow("42", "SetAutoDig", limit)).toBe(true)
        T.expect(limiter:allow("42", "SetAutoDig", limit)).toBe(true)
        T.expect(limiter:allow("42", "SetAutoDig", limit)).toBe(false)
    end)
end)

T.describe("Remote BuyDirectItem (4.6)", function()
    T.it("RemoteFunction vom Client zum Server, ein Argument: bekannte Item-ID aus CrateItems", function()
        local def = RemoteSpec.byName.BuyDirectItem
        T.expect(def.kind).toBe("Function")
        T.expect(def.direction).toBe("ClientToServer")
        T.expect(select(1, RemoteSpec.canRegister("BuyDirectItem"))).toBe(true)
        local rule: any = (def.schema :: any)[1]
        T.expect(rule.kind).toBe("idIn")
        T.expect(rawequal(rule.ids, CrateItems.byId)).toBe(true)
        T.expect(rule.maxLen).toBe(64)
        T.expect(validate("BuyDirectItem", "skin_rare_1")).toBe(true)
        T.expect(validate("BuyDirectItem", "skin_mythic_2")).toBe(true) -- Event-Item: Schema ok, der Server lehnt ab (notOffered)
    end)

    T.it("falsche Typen, unbekannte IDs, zu lange Texte und falsche Argumentzahl werden abgelehnt", function()
        T.expect(validate("BuyDirectItem", "")).toBe(false)
        T.expect(validate("BuyDirectItem", "gibt_es_nicht")).toBe(false)
        T.expect(validate("BuyDirectItem", string.rep("a", 65))).toBe(false)
        T.expect(validate("BuyDirectItem", 7)).toBe(false)
        T.expect(validate("BuyDirectItem", 0 / 0)).toBe(false)
        T.expect(validate("BuyDirectItem", true)).toBe(false)
        T.expect(validate("BuyDirectItem", { "skin_rare_1" })).toBe(false)
        T.expect(validate("BuyDirectItem")).toBe(false)
        T.expect(validate("BuyDirectItem", nil)).toBe(false)
        T.expect(validate("BuyDirectItem", "skin_rare_1", 2000)).toBe(false) -- kein Preis vom Client
        T.expect(validate("BuyDirectItem", "skin_rare_1", "skin_rare_1")).toBe(false)
    end)

    T.it("Limit 2 pro Sekunde mit simulierter Uhr", function()
        local clock = { t = 50 }
        local limiter = RateLimiter.new(function(): number
            return clock.t
        end)
        local limit = RemoteSpec.byName.BuyDirectItem.limit :: RateLimiter.Limit
        T.expect(limiter:allow("42", "BuyDirectItem", limit)).toBe(true)
        T.expect(limiter:allow("42", "BuyDirectItem", limit)).toBe(true)
        T.expect(limiter:allow("42", "BuyDirectItem", limit)).toBe(false)
        clock.t += 1
        T.expect(limiter:allow("42", "BuyDirectItem", limit)).toBe(true)
    end)
end)

T.describe("Remote ClaimDaily (5.1)", function()
    T.it("RemoteFunction vom Client zum Server ohne Argumente, registrierbar", function()
        local def = RemoteSpec.byName.ClaimDaily
        T.expect(def.kind).toBe("Function")
        T.expect(def.direction).toBe("ClientToServer")
        T.expect(def.schema).toEqual({})
        T.expect(select(1, RemoteSpec.canRegister("ClaimDaily"))).toBe(true)
        T.expect(validate("ClaimDaily")).toBe(true)
    end)

    T.it("jedes Argument wird abgelehnt: kein Tag, keine Zeit, kein Spieler vom Client", function()
        T.expect(validate("ClaimDaily", 7)).toBe(false)
        T.expect(validate("ClaimDaily", 1_700_000_000)).toBe(false) -- keine Client-Zeit
        T.expect(validate("ClaimDaily", "day7")).toBe(false)
        T.expect(validate("ClaimDaily", true)).toBe(false)
        T.expect(validate("ClaimDaily", nil)).toBe(false) -- ein angehängtes nil zählt als Argument
        T.expect(validate("ClaimDaily", { day = 7 })).toBe(false)
        T.expect(validate("ClaimDaily", 0 / 0)).toBe(false)
    end)

    T.it("Limit 1 Aufruf je 2 Sekunden mit simulierter Uhr, Spieler getrennt", function()
        local clock = { t = 10 }
        local limiter = RateLimiter.new(function(): number
            return clock.t
        end)
        local limit = RemoteSpec.byName.ClaimDaily.limit :: RateLimiter.Limit
        T.expect(limit.calls).toBe(1)
        T.expect(limit.per).toBe(2)
        T.expect(limiter:allow("42", "ClaimDaily", limit)).toBe(true)
        T.expect(limiter:allow("42", "ClaimDaily", limit)).toBe(false)
        T.expect(limiter:allow("43", "ClaimDaily", limit)).toBe(true) -- anderer Spieler
        clock.t += 1.9
        T.expect(limiter:allow("42", "ClaimDaily", limit)).toBe(false)
        clock.t += 0.1
        T.expect(limiter:allow("42", "ClaimDaily", limit)).toBe(true)
        T.expect(limiter:allow("42", "ClaimDaily", limit)).toBe(false)
        -- Andere Remotes zählen getrennt.
        T.expect(limiter:allow("42", "OpenCrate", RemoteSpec.byName.OpenCrate.limit :: RateLimiter.Limit)).toBe(true)
    end)
end)

T.finish()
