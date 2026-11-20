--!strict
-- Paket 4.6: Robux-Preise für die Anzeige (Logic/PriceView).

local T = require("./lib/expect")
local PriceView = require("../src/shared/Logic/PriceView")
local GemPacks = require("../src/shared/Data/GemPacks")

T.describe("robux und buttonText", function()
    T.it("nimmt den Preis von Roblox, sonst die Tabelle", function()
        T.expect(PriceView.robux({ price = 59, forSale = true }, 49)).toBe(59)
        T.expect(PriceView.robux(nil, 49)).toBe(49)
        T.expect(PriceView.robux({ price = nil }, 49)).toBe(49)
        T.expect(PriceView.robux({ price = 0 / 0 }, 49)).toBe(49)
        T.expect(PriceView.robux({ price = -1 }, 49)).toBe(49)
        T.expect(PriceView.robux({ price = 1.5 }, 49)).toBe(49)
    end)
    T.it("zeigt Bald bei ID 0 und Nicht verfügbar, wenn Roblox nicht verkauft", function()
        T.expect(PriceView.buttonText(0, { price = 59, forSale = true }, 49)).toBe("Bald")
        T.expect(PriceView.buttonText(123, { price = 59, forSale = false }, 49)).toBe("Nicht verfügbar")
        T.expect(PriceView.buttonText(123, { price = 2499, forSale = true }, 49)).toBe("2.499 Robux")
        T.expect(PriceView.buttonText(123, nil, 249)).toBe("249 Robux")
    end)
    T.it("buyable: unbekannt zählt als kaufbar, ID 0 nie", function()
        T.expect(PriceView.buyable(123, nil)).toBe(true)
        T.expect(PriceView.buyable(123, { forSale = false })).toBe(false)
        T.expect(PriceView.buyable(0, nil)).toBe(false)
    end)
end)

T.describe("gemBonusPercent", function()
    T.it("ergibt für die Daten die Konzeptspalte", function()
        local base = GemPacks.list[1]
        for _, pack in GemPacks.list do
            T.expect(PriceView.gemBonusPercent(pack.gems, pack.robux, base.gems, base.robux)).toBe(pack.bonusPercentConcept)
        end
    end)
    T.it("rechnet mit anderen Preisen neu und lehnt kaputte Werte ab", function()
        T.expect(PriceView.gemBonusPercent(550, 275, 100, 50)).toBe(0)
        T.expect(PriceView.gemBonusPercent(100, 0, 100, 49)).toBeNil()
        T.expect(PriceView.gemBonusPercent(0 / 0, 49, 100, 49)).toBeNil()
    end)
end)

T.describe("mismatch", function()
    T.it("meldet abweichenden Preis und nicht zum Verkauf", function()
        T.expect(PriceView.mismatch({ price = 59, forSale = true }, 49)).toBe("Preis im Dashboard 59 Robux, in den Daten 49 Robux")
        T.expect(PriceView.mismatch({ price = 49, forSale = false }, 49)).toBe("nicht zum Verkauf")
        T.expect(PriceView.mismatch({ price = 49, forSale = true }, 49)).toBeNil()
        T.expect(PriceView.mismatch(nil, 49)).toBeNil()
    end)
end)

T.finish()
