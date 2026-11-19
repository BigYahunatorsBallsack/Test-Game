--!strict
-- Paket 4.1: Gems gutschreiben und abbuchen (Logic/Gems).

local T = require("./lib/expect")
local Gems = require("../src/shared/Logic/Gems")
local Profile = require("../src/shared/Logic/Profile")
local Economy = require("../src/shared/Data/Economy")

local NOW = 1_700_000_000
local SOURCE = "purchase:gems_550"

-- Kleine Obergrenze, damit das Kappen ohne riesige Zahlen testbar ist.
local SMALL_CAP = {
    Economy = {
        purchases = { receiptCacheSize = 100, purchaseLogSize = 50, saveTimeoutSeconds = 30, maxGems = 1000 },
    },
}

local function fresh(): any
    return Profile.default(NOW)
end

local INVALID_AMOUNTS: { any } = { 0, -5, 1.5, 0 / 0, math.huge, -math.huge, "550", true }

T.describe("Gems.grant", function()
    T.it("schreibt genau die Menge gut und gibt sie zurück", function()
        local profile = fresh()
        T.expect(Gems.grant(profile, 550, SOURCE)).toBe(550)
        T.expect(profile.gems).toBe(550)
        T.expect(Gems.grant(profile, 100, "purchase:gems_100")).toBe(100)
        T.expect(profile.gems).toBe(650)
    end)

    T.it("lehnt 0, negative, gebrochene, NaN, unendliche und Nicht-Zahl-Mengen ab", function()
        for _, amount in INVALID_AMOUNTS do
            local profile = fresh()
            profile.gems = 40
            T.expect(Gems.grant(profile, amount, SOURCE)).toBe(0)
            T.expect(profile.gems).toBe(40)
        end
    end)

    T.it("bucht nichts ohne Quelle", function()
        local profile = fresh()
        T.expect(Gems.grant(profile, 550, "")).toBe(0)
        T.expect(Gems.grant(profile, 550, nil :: any)).toBe(0)
        T.expect(profile.gems).toBe(0)
    end)

    T.it("kappt bei maxGems und gibt die tatsächlich gebuchte Menge zurück", function()
        local profile = fresh()
        profile.gems = 900
        T.expect(Gems.grant(profile, 550, SOURCE, SMALL_CAP)).toBe(100)
        T.expect(profile.gems).toBe(1000)
        T.expect(Gems.grant(profile, 1, SOURCE, SMALL_CAP)).toBe(0)
        T.expect(profile.gems).toBe(1000)
        -- Mit den echten Daten liegt die Grenze bei Economy.purchases.maxGems.
        local rich = fresh()
        rich.gems = Economy.purchases.maxGems - 10
        T.expect(Gems.grant(rich, 7000, SOURCE)).toBe(10)
        T.expect(rich.gems).toBe(Economy.purchases.maxGems)
    end)

    T.it("ein kaputter Stand zählt wie der reparierte Wert", function()
        local cases: { { value: any, expected: number } } = {
            { value = 0 / 0, expected = 550 },
            { value = -20, expected = 550 },
            { value = 10.9, expected = 560 },
            { value = "viel", expected = 550 },
            { value = math.huge, expected = 550 },
        }
        for _, case in cases do
            local profile = fresh()
            profile.gems = case.value
            Gems.grant(profile, 550, SOURCE)
            T.expect(profile.gems).toBe(case.expected)
        end
    end)
end)

T.describe("Gems.spend und Gems.canAfford", function()
    T.it("bucht nur bei genug Gems ab, genau passend geht auf 0", function()
        local profile = fresh()
        profile.gems = 300
        T.expect(Gems.canAfford(profile, 300)).toBe(true)
        T.expect(Gems.canAfford(profile, 301)).toBe(false)
        local ok, reason = Gems.spend(profile, 301, "crate:gold")
        T.expect(ok).toBe(false)
        T.expect(reason).toBe("notEnoughGems")
        T.expect(profile.gems).toBe(300)
        ok, reason = Gems.spend(profile, 120, "crate:gold")
        T.expect(ok).toBe(true)
        T.expect(reason).toBeNil()
        T.expect(profile.gems).toBe(180)
        T.expect((Gems.spend(profile, 180, "crate:gold"))).toBe(true)
        T.expect(profile.gems).toBe(0)
    end)

    T.it("ungültige Mengen und fehlender Grund: invalidAmount, nichts abgebucht", function()
        for _, amount in INVALID_AMOUNTS do
            local profile = fresh()
            profile.gems = 1000
            local ok, reason = Gems.spend(profile, amount, "crate:gold")
            T.expect(ok).toBe(false)
            T.expect(reason).toBe("invalidAmount")
            T.expect(profile.gems).toBe(1000)
            T.expect(Gems.canAfford(profile, amount)).toBe(false)
        end
        local profile = fresh()
        profile.gems = 1000
        local ok, reason = Gems.spend(profile, 10, "")
        T.expect(ok).toBe(false)
        T.expect(reason).toBe("invalidAmount")
        T.expect(profile.gems).toBe(1000)
    end)

    T.it("ein kaputter Stand (NaN, negativ) hat keine Gems zum Ausgeben", function()
        for _, value in { 0 / 0, -50, "x" } do
            local profile = fresh()
            profile.gems = value
            T.expect(Gems.balance(profile)).toBe(0)
            T.expect(Gems.canAfford(profile, 1)).toBe(false)
            local ok, reason = Gems.spend(profile, 1, "crate:gold")
            T.expect(ok).toBe(false)
            T.expect(reason).toBe("notEnoughGems")
        end
    end)
end)

T.finish()
