--!strict
-- Paket 1.3: Zahlentyp (Rechnen, Vergleichen, Speichern) und Anzeige (K, M, B, T ...).

local T = require("./lib/expect")
local BigNum = require("../src/shared/Logic/BigNum")

local function n(m: number, e: number?): BigNum.BigNum
    return BigNum.new(m, e)
end

local function fmt(m: number, e: number?, decimals: number?): string
    return BigNum.format(n(m, e), decimals)
end

local function expectNum(actual: BigNum.BigNum, m: number, e: number)
    T.expect(actual.e).toBe(e)
    T.expect(actual.m).toBeCloseTo(m, 1e-9)
end

T.describe("Rechnen gegen Referenzwerte", function()
    T.it("Addieren unter und über 10^15", function()
        expectNum(BigNum.add(n(3), n(4)), 7, 0)
        expectNum(BigNum.add(n(9.5, 14), n(9.5, 14)), 1.9, 15)
        expectNum(BigNum.add(n(1, 15), n(1, 15)), 2, 15)
        expectNum(BigNum.add(n(5, 30), n(5, 30)), 1, 31)
    end)

    T.it("ein winziger Summand neben einem riesigen ändert den Wert nicht", function()
        local big = n(1.5, 30)
        local sum = BigNum.add(big, n(7))
        expectNum(sum, 1.5, 30)
        expectNum(BigNum.add(n(7), big), 1.5, 30)
    end)

    T.it("Subtrahieren bis genau 0 ergibt die Null", function()
        local zero = BigNum.sub(n(2.5, 40), n(2.5, 40))
        T.expect(zero.m).toBe(0)
        T.expect(zero.e).toBe(0)
        T.expect(BigNum.format(zero)).toBe("0")
    end)

    T.it("Subtrahieren über 10^15", function()
        expectNum(BigNum.sub(n(3, 20), n(1, 20)), 2, 20)
        expectNum(BigNum.sub(n(1, 16), n(1, 15)), 9, 15)
    end)

    T.it("Multiplizieren und Dividieren über große Exponenten", function()
        expectNum(BigNum.mul(n(1, 20), n(1, 20)), 1, 40)
        expectNum(BigNum.mul(n(2.5, 10), n(4, 5)), 1, 16)
        expectNum(BigNum.div(n(6, 30), n(2, 10)), 3, 20)
        expectNum(BigNum.mulNumber(n(1.5, 20), 150), 2.25, 22)
        T.expect(BigNum.mul(n(5, 20), BigNum.zero()).m).toBe(0)
        T.expect(function()
            BigNum.div(n(1), BigNum.zero())
        end).toThrow("Division durch 0")
    end)

    T.it("Rauschstellen: 0,1 + 0,2 ergibt 0,3, ganze Zahlen bleiben ganz", function()
        local sum = BigNum.add(n(0.1), n(0.2))
        T.expect(BigNum.format(sum)).toBe("0,3")
        T.expect(BigNum.toNumber(BigNum.add(n(1.4, 1), n(1)))).toBe(15)
        T.expect(BigNum.toNumber(BigNum.mulNumber(n(7), 3))).toBe(21)
    end)
end)

T.describe("Vergleichen", function()
    T.it("kleiner, gleich, größer über 10^15", function()
        T.expect(BigNum.lt(n(1, 15), n(1.0000001, 15))).toBe(true)
        T.expect(BigNum.lt(n(1.0000001, 15), n(1, 15))).toBe(false)
        T.expect(BigNum.eq(n(1, 15), n(10, 14))).toBe(true)
        T.expect(BigNum.compare(n(5, 14), n(1, 15))).toBe(-1)
        T.expect(BigNum.compare(n(1, 15), n(5, 14))).toBe(1)
        T.expect(BigNum.compare(n(2, 40), n(2, 40))).toBe(0)
    end)

    T.it("sehr große Exponenten bleiben vergleichbar", function()
        T.expect(BigNum.compare(n(9.99, 308), n(1, 400))).toBe(-1)
        T.expect(BigNum.compare(n(1, 1000), n(1, 999))).toBe(1)
        T.expect(BigNum.compare(n(1, 1000), BigNum.zero())).toBe(1)
    end)

    T.it("negative Werte ordnen sich richtig", function()
        T.expect(BigNum.compare(n(-5), n(3))).toBe(-1)
        T.expect(BigNum.compare(n(-1, 20), n(-1, 19))).toBe(-1)
        T.expect(BigNum.compare(n(-1, 20), BigNum.zero())).toBe(-1)
    end)

    T.it("max und min", function()
        expectNum(BigNum.max(n(1, 20), n(5, 19)), 1, 20)
        expectNum(BigNum.min(n(1, 20), n(5, 19)), 5, 19)
    end)
end)

T.describe("Anzeige unter 1000", function()
    T.it("ganze Zahlen ohne Suffix", function()
        T.expect(fmt(0)).toBe("0")
        T.expect(fmt(7)).toBe("7")
        T.expect(fmt(42)).toBe("42")
        T.expect(fmt(999)).toBe("999")
        T.expect(BigNum.format(BigNum.zero())).toBe("0")
    end)

    T.it("Brüche mit Komma, Endnullen entfallen", function()
        T.expect(fmt(2.5)).toBe("2,5")
        T.expect(fmt(2.05)).toBe("2,1")
        T.expect(fmt(0.05)).toBe("0,1")
        T.expect(fmt(2, nil, 2)).toBe("2")
        T.expect(fmt(2.25, nil, 2)).toBe("2,25")
    end)

    T.it("winzige Werte werden zu 0", function()
        T.expect(fmt(1, -20)).toBe("0")
        T.expect(fmt(4, -3)).toBe("0")
    end)

    T.it("999,96 springt auf 1K", function()
        T.expect(fmt(9.9996, 2)).toBe("1K")
        T.expect(fmt(9.995, 2)).toBe("999,5")
    end)
end)

T.describe("Anzeige mit Suffixen", function()
    T.it("K, M, B, T", function()
        T.expect(fmt(1, 3)).toBe("1K")
        T.expect(fmt(1.5, 3)).toBe("1,5K")
        T.expect(fmt(1.23, 4)).toBe("12,3K")
        T.expect(fmt(9.99, 5)).toBe("999K")
        T.expect(fmt(1, 6)).toBe("1M")
        T.expect(fmt(1.2, 9)).toBe("1,2B")
        T.expect(fmt(4.56, 12)).toBe("4,6T")
        T.expect(fmt(4.56, 12, 2)).toBe("4,56T")
    end)

    T.it("Qa bis Dc", function()
        T.expect(fmt(1, 15)).toBe("1Qa")
        T.expect(fmt(2.5, 18)).toBe("2,5Qi")
        T.expect(fmt(1, 21)).toBe("1Sx")
        T.expect(fmt(1, 24)).toBe("1Sp")
        T.expect(fmt(1, 27)).toBe("1Oc")
        T.expect(fmt(1, 30)).toBe("1No")
        T.expect(fmt(1.2, 33)).toBe("1,2Dc")
        T.expect(fmt(9.99, 35)).toBe("999Dc")
    end)

    T.it("jeder Suffix entspricht seiner Zehnerpotenz", function()
        for i, suffix in BigNum.SUFFIXES do
            T.expect(BigNum.format(n(1, 3 * i))).toBe("1" .. suffix)
        end
    end)

    T.it("Rundung an den Grenzen: 999,9K bleibt, 999,95K wird 1M", function()
        T.expect(fmt(9.999, 5)).toBe("999,9K")
        T.expect(fmt(9.9995, 5)).toBe("1M")
        T.expect(fmt(9.9996, 5)).toBe("1M")
        T.expect(fmt(9.9996, 8)).toBe("1B")
        T.expect(fmt(9.9996, 11)).toBe("1T")
    end)

    T.it("die Grenze gilt in jeder Stufe bis Dc", function()
        for i, suffix in BigNum.SUFFIXES do
            local top = 3 * i + 2 -- 999,96 der Stufe i (z. B. 999,96K = 9,9996e5)
            local expected = if i == #BigNum.SUFFIXES then "1e36" else "1" .. BigNum.SUFFIXES[i + 1]
            T.expect(fmt(9.9996, top)).toBe(expected)
            T.expect(fmt(9.999, top)).toBe("999,9" .. suffix)
        end
    end)

    T.it("Hälften runden auf", function()
        T.expect(fmt(1.25, 3)).toBe("1,3K")
        T.expect(fmt(1.15, 3)).toBe("1,2K")
        T.expect(fmt(1.05, 3)).toBe("1,1K")
        T.expect(fmt(1.24, 3)).toBe("1,2K")
    end)

    T.it("Stellenzahl wählbar und begrenzt", function()
        T.expect(fmt(1.234, 3, 0)).toBe("1K")
        T.expect(fmt(1.234, 3, 1)).toBe("1,2K")
        T.expect(fmt(1.234, 3, 2)).toBe("1,23K")
        T.expect(fmt(1.2345, 3, 3)).toBe("1,235K")
        T.expect(fmt(1.23456, 3, 4)).toBe("1,2346K")
        T.expect(fmt(1.23456, 3, 9)).toBe("1,2346K")
        T.expect(fmt(1.234, 3, -2)).toBe("1K")
        T.expect(fmt(1.234, 3, 0 / 0)).toBe("1,2K")
        T.expect(fmt(9.996, 5, 0)).toBe("1M")
    end)
end)

T.describe("Wissenschaftliche Anzeige ab 10^36", function()
    T.it("Beispiele", function()
        T.expect(fmt(1, 36)).toBe("1e36")
        T.expect(fmt(1.23, 36)).toBe("1,23e36")
        T.expect(fmt(1.234, 36)).toBe("1,23e36")
        T.expect(fmt(9.99, 99)).toBe("9,99e99")
        T.expect(fmt(1.5, 308)).toBe("1,5e308")
        T.expect(fmt(1.5, 1000)).toBe("1,5e1000")
    end)

    T.it("Rundung über die Zehnerstelle: 9,996e40 wird 1e41", function()
        T.expect(fmt(9.996, 40)).toBe("1e41")
        T.expect(fmt(9.994, 40)).toBe("9,99e40")
    end)

    T.it("die Stellenzahl ändert die wissenschaftliche Form nicht", function()
        T.expect(fmt(1.2345, 50, 0)).toBe("1,23e50")
        T.expect(fmt(1.2345, 50, 4)).toBe("1,23e50")
    end)
end)

T.describe("Negative Werte und Null", function()
    T.it("Vorzeichen davor", function()
        T.expect(fmt(-1.5, 3)).toBe("-1,5K")
        T.expect(fmt(-999)).toBe("-999")
        T.expect(fmt(-1.23, 40)).toBe("-1,23e40")
        T.expect(fmt(-9.9996, 5)).toBe("-1M")
    end)

    T.it("negative Rundung auf 0 zeigt kein Minus", function()
        T.expect(fmt(-4, -3)).toBe("0")
    end)
end)

T.describe("Speichern und Laden", function()
    local samples = {
        n(0),
        n(7),
        n(999.5),
        n(1.5, 3),
        n(1, 15),
        n(9.5, 14),
        n(1.234, 40),
        n(-3.21, 22),
        n(1.2345678901234, 100),
    }

    T.it("serialize und deserialize verändern den Wert nicht", function()
        for _, value in samples do
            local loaded = BigNum.deserialize(BigNum.serialize(value))
            T.expect(loaded.m).toBe(value.m)
            T.expect(loaded.e).toBe(value.e)
            T.expect(BigNum.format(loaded)).toBe(BigNum.format(value))
        end
    end)

    T.it("serialize liefert eine Kopie", function()
        local value = n(1, 20)
        local data = BigNum.serialize(value)
        data.m = 5
        T.expect(value.m).toBe(1)
    end)

    T.it("ungültige gespeicherte Werte werden zur Null", function()
        local bad: { any } = {
            "text",
            42,
            {},
            { m = "1", e = 3 },
            { m = 1, e = "3" },
            { m = 0 / 0, e = 3 },
            { m = 1, e = 0 / 0 },
            { m = math.huge, e = 3 },
            { m = 1, e = -math.huge },
        }
        for _, data in bad do
            local value = BigNum.deserialize(data)
            T.expect(value.m).toBe(0)
            T.expect(BigNum.format(value)).toBe("0")
        end
        T.expect(BigNum.deserialize(nil).m).toBe(0)
    end)

    T.it("nicht normalisierte gespeicherte Werte werden normalisiert", function()
        local value = BigNum.deserialize({ m = 15, e = 2 })
        T.expect(value.e).toBe(3)
        T.expect(value.m).toBeCloseTo(1.5, 1e-12)
        T.expect(BigNum.format(value)).toBe("1,5K")
    end)

    T.it("BigNum.new lehnt NaN und unendlich ab", function()
        T.expect(function()
            BigNum.new(0 / 0)
        end).toThrow("ungültige Mantisse")
        T.expect(function()
            BigNum.new(math.huge)
        end).toThrow("ungültige Mantisse")
    end)
end)

T.finish()
