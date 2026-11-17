--!strict
-- Paket 1.6: Mini-Kauf im Skilltree (reine Logik) und die Wirkung der ersten Knoten.

local T = require("./lib/expect")
local TreePurchase = require("../src/shared/Logic/TreePurchase")
local Collecting = require("../src/shared/Logic/Collecting")
local Profile = require("../src/shared/Logic/Profile")
local BigNum = require("../src/shared/Logic/BigNum")
local Validate = require("../src/shared/Logic/Validate")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local Economy = require("../src/shared/Data/Economy")

local NOW = 1_700_000_000

local function withCoins(coins: number): any
    local profile = Profile.default(NOW)
    profile.coins = BigNum.serialize(BigNum.new(coins))
    return profile
end

local function coinsOf(profile: any): BigNum.BigNum
    return BigNum.deserialize(profile.coins)
end

T.describe("Kauf eines Knotens", function()
    T.it("ohne Voraussetzung wird abgelehnt, Münzen bleiben gleich", function()
        local profile = withCoins(1000)
        local ok, reason = TreePurchase.buy(profile, "tank_2")
        T.expect(ok).toBe(false)
        T.expect(reason).toBe("requires")
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(1000)
        T.expect(profile.nodes.tank_2).toBeNil()
        local ok2, reason2 = TreePurchase.buy(profile, "collect_rate_2")
        T.expect(ok2).toBe(false)
        T.expect(reason2).toBe("requires")
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(1000)
    end)

    T.it("zwei schnelle Käufe: nur der erste bucht ab", function()
        local profile = withCoins(100)
        local ok1 = TreePurchase.buy(profile, "collect_rate_1")
        local ok2, reason2 = TreePurchase.buy(profile, "collect_rate_1")
        T.expect(ok1).toBe(true)
        T.expect(ok2).toBe(false)
        T.expect(reason2).toBe("owned")
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(85)
        T.expect(profile.nodes.collect_rate_1).toBe(true)
    end)

    T.it("zu wenig Münzen wird abgelehnt, genau passende gehen auf 0", function()
        local profile = withCoins(14)
        local ok, reason = TreePurchase.buy(profile, "collect_rate_1")
        T.expect(ok).toBe(false)
        T.expect(reason).toBe("coins")
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(14)
        T.expect(profile.nodes.collect_rate_1).toBeNil()
        profile.coins = BigNum.serialize(BigNum.new(15))
        T.expect(TreePurchase.buy(profile, "collect_rate_1")).toBe(true)
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(0)
    end)

    T.it("unbekannte und vergebene Knoten lassen sich nicht kaufen", function()
        local profile = withCoins(1000)
        local ok1, reason1 = TreePurchase.buy(profile, "gibt_es_nicht")
        T.expect(ok1).toBe(false)
        T.expect(reason1).toBe("unknown")
        local ok2, reason2 = TreePurchase.buy(profile, "sandstorm_1")
        T.expect(ok2).toBe(false)
        T.expect(reason2).toBe("granted")
        T.expect(profile.nodes.sandstorm_1).toBeNil()
    end)

    T.it("ein Knoten mit Sandsturm-Wirkung lässt sich auch ohne granted-Flag nicht kaufen", function()
        local node = UpgradeTree.byId.sandstorm_1
        local saved = node.granted
        node.granted = nil
        local profile = withCoins(1000)
        local ok, reason = TreePurchase.buy(profile, "sandstorm_1")
        node.granted = saved
        T.expect(ok).toBe(false)
        T.expect(reason).toBe("granted")
    end)

    T.it("große Münzwerte kaufen über den Zahlentyp ohne Fehler", function()
        local profile = Profile.default(NOW)
        profile.coins = BigNum.serialize(BigNum.new(1.5, 20))
        T.expect(TreePurchase.buy(profile, "collect_tool_2")).toBe(true)
        local left = coinsOf(profile)
        T.expect(BigNum.compare(left, BigNum.new(1.5, 20))).toBe(0) -- 50 geht in der Rundung unter
        T.expect(profile.nodes.collect_tool_2).toBe(true)
    end)

    T.it("Kette: tank_1, tank_2, tank_3 nur nacheinander", function()
        local profile = withCoins(10000)
        T.expect(TreePurchase.check(profile, "tank_3")).toBe("requires")
        T.expect(TreePurchase.buy(profile, "tank_1")).toBe(true)
        T.expect(TreePurchase.check(profile, "tank_3")).toBe("requires")
        T.expect(TreePurchase.buy(profile, "tank_2")).toBe(true)
        T.expect(TreePurchase.buy(profile, "tank_3")).toBe(true)
        T.expect(BigNum.toNumber(coinsOf(profile))).toBe(10000 - 20 - 60 - 250)
    end)

    T.it("sichtbare Knoten: aufsteigend nach Preis, ohne gekaufte, vergebene und gesperrte", function()
        local profile = Profile.default(NOW)
        T.expect(TreePurchase.visible(profile)).toEqual({ "collect_rate_1", "tank_1", "collect_tool_2" })
        profile.nodes.collect_rate_1 = true
        profile.nodes.collect_tool_2 = true
        T.expect(TreePurchase.visible(profile)).toEqual({ "tank_1", "collect_rate_2", "collect_tool_3" })
    end)

    T.it("PurchaseNode nimmt nur eine bekannte Knoten-ID, keinen Preis", function()
        local def: any = nil
        for _, candidate in RemoteSpec.list do
            if candidate.name == "PurchaseNode" then
                def = candidate
            end
        end
        T.expect(Validate.check(def.schema, { "collect_rate_1" }, 1)).toBe(true)
        T.expect(Validate.check(def.schema, { "collect_rate_1", 1 }, 2)).toBe(false)
        T.expect(Validate.check(def.schema, { 5 }, 1)).toBe(false)
        T.expect(Validate.check(def.schema, { "gibt_es_nicht" }, 1)).toBe(false)
    end)
end)

T.describe("Wirkung der ersten Knoten", function()
    T.it("Sammelrate: Hand 1 auf 1,5, mit Schaufel 7,5 (+25 % danach 8,75)", function()
        local profile = Profile.default(NOW)
        T.expect(Collecting.rateOf(profile)).toBe(1)
        profile.nodes.collect_rate_1 = true
        T.expect(Collecting.rateOf(profile)).toBe(1.5)
        profile.nodes.collect_tool_2 = true
        T.expect(Collecting.rateOf(profile)).toBe(7.5)
        profile.nodes.collect_rate_2 = true
        T.expect(Collecting.rateOf(profile)).toBe(8.75)
    end)

    T.it("Tank: Start, tank_1 30, tank_2 60, tank_3 150, der höchste zählt", function()
        local profile = Profile.default(NOW)
        T.expect(Collecting.capacityOf(profile)).toBe(Economy.startTankCapacity)
        profile.nodes.tank_1 = true
        T.expect(Collecting.capacityOf(profile)).toBe(30)
        profile.nodes.tank_2 = true
        T.expect(Collecting.capacityOf(profile)).toBe(60)
        profile.nodes.tank_3 = true
        T.expect(Collecting.capacityOf(profile)).toBe(150)
        -- Reihenfolge im Profil ist egal: nur tank_1 und tank_3.
        local other = Profile.default(NOW)
        other.nodes.tank_3 = true
        other.nodes.tank_1 = true
        T.expect(Collecting.capacityOf(other)).toBe(150)
    end)

    T.it("der Gamepass-Faktor kommt nach dem Tank-Knoten", function()
        local profile = Profile.default(NOW)
        profile.nodes.tank_2 = true
        T.expect(Collecting.capacityOf(profile, { capacityMultiplier = Economy.bigTankMultiplier })).toBe(60 * Economy.bigTankMultiplier)
    end)

    T.it("unbekannte und entfernte Knoten im Profil ändern nichts", function()
        local profile = Profile.default(NOW)
        profile.nodes.tank_99 = true
        profile.nodes.alter_knoten = true
        T.expect(Collecting.capacityOf(profile)).toBe(Economy.startTankCapacity)
        T.expect(Collecting.rateOf(profile)).toBe(1)
        profile.nodes.tank_1 = false
        T.expect(Collecting.capacityOf(profile)).toBe(Economy.startTankCapacity)
    end)

    T.it("ownedNodes liefert nur bekannte, gekaufte Knoten", function()
        local profile = Profile.default(NOW)
        profile.nodes.tank_1 = true
        profile.nodes.collect_rate_1 = false
        profile.nodes.alter_knoten = true
        T.expect(Collecting.ownedNodes(profile)).toEqual({ tank_1 = true })
    end)

    T.it("jeder Knoten hat Name und Beschreibung, die Wirkung ist bekannt", function()
        for _, node in UpgradeTree.list do
            T.expect(type(node.name)).toBe("string")
            T.expect(type(node.description)).toBe("string")
        end
        T.expect(UpgradeTree.byId.collect_rate_1.effect.bp).toBe(5000)
        T.expect(UpgradeTree.byId.tank_3.effect.capacity).toBe(150)
    end)
end)

T.finish()
