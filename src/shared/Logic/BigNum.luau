--!strict
-- Zahlentyp für große Werte (Mantisse und Exponent): Wert = m * 10^e.
-- Paket 0.3 lieferte die Schnittstelle (new, zero, serialize, deserialize), Paket 1.2 das
-- Rechnen und Vergleichen, das Sammeln und Verkaufen brauchen. Die Anzeige (format) und
-- die ausführlichen Grenzwert-Tests folgen in Paket 1.3.
--
-- Anzeige (Umsetzung in 1.3): deutsches Komma als Dezimaltrenner, ab 1000 mit Suffix
-- K, M, B, T, danach Qa, Qi, Sx, Sp, Oc, No, Dc (bis 10^35), ab 10^36 wissenschaftlich
-- ("1,23e36").

export type BigNum = { m: number, e: number }
export type Serialized = { m: number, e: number }

local NOT_IMPLEMENTED = "BigNum: in Paket 1.3"

local BigNum = {}

-- Suffixe ab 10^3 in Dreierschritten: SUFFIXES[1] = K (10^3), SUFFIXES[2] = M (10^6) usw.
BigNum.SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
BigNum.DECIMAL_SEPARATOR = ","
-- Ab diesem Exponenten (10^36) wechselt die Anzeige auf die wissenschaftliche Schreibweise.
BigNum.SCIENTIFIC_FROM_EXPONENT = 36

-- Signifikante Stellen der Mantisse (Rest ist Gleitkomma-Rauschen).
local MANTISSA_SCALE = 1e14

-- Erzeugt eine normalisierte Zahl: Mantisse in [1, 10) (oder 0), Exponent ganzzahlig.
function BigNum.new(mantissa: number, exponent: number?): BigNum
    local m = mantissa
    local e = exponent or 0
    if m ~= m or m == math.huge or m == -math.huge then
        error("BigNum: ungültige Mantisse")
    end
    if m == 0 then
        return { m = 0, e = 0 }
    end
    local shift = math.floor(math.log10(math.abs(m)))
    m = m / 10 ^ shift
    e += shift
    -- Rauschen in den letzten Stellen entfernen (z. B. 1,4000000000000004 aus 1,3 + 0,1),
    -- damit ganze Zahlen wie Tankinhalte ganz bleiben.
    m = math.round(m * MANTISSA_SCALE) / MANTISSA_SCALE
    -- Rundungsfehler von log10 und Potenz abfangen.
    if math.abs(m) >= 10 then
        m /= 10
        e += 1
    elseif math.abs(m) < 1 then
        m *= 10
        e -= 1
    end
    return { m = m, e = e }
end

function BigNum.zero(): BigNum
    return { m = 0, e = 0 }
end

function BigNum.serialize(value: BigNum): Serialized
    return { m = value.m, e = value.e }
end

-- Liest einen gespeicherten Wert. Ungültige Eingaben ergeben die Null.
function BigNum.deserialize(data: any): BigNum
    if type(data) ~= "table" then
        return BigNum.zero()
    end
    local m, e = data.m, data.e
    if type(m) ~= "number" or type(e) ~= "number" then
        return BigNum.zero()
    end
    if m ~= m or e ~= e or m == math.huge or m == -math.huge or e == math.huge or e == -math.huge then
        return BigNum.zero()
    end
    return BigNum.new(m, e)
end

-- Ab diesem Abstand der Exponenten ist der kleinere Summand unterhalb der Genauigkeit
-- einer Gleitkommazahl (etwa 15 bis 16 Stellen) und fällt weg.
local PRECISION_DIGITS = 15

local function copy(a: BigNum): BigNum
    return { m = a.m, e = a.e }
end

function BigNum.add(a: BigNum, b: BigNum): BigNum
    if a.m == 0 then
        return copy(b)
    end
    if b.m == 0 then
        return copy(a)
    end
    local diff = a.e - b.e
    if diff > PRECISION_DIGITS then
        return copy(a)
    elseif diff < -PRECISION_DIGITS then
        return copy(b)
    end
    if diff >= 0 then
        return BigNum.new(a.m + b.m / 10 ^ diff, a.e)
    end
    return BigNum.new(a.m / 10 ^ -diff + b.m, b.e)
end

function BigNum.sub(a: BigNum, b: BigNum): BigNum
    return BigNum.add(a, { m = -b.m, e = b.e })
end

function BigNum.mul(a: BigNum, b: BigNum): BigNum
    if a.m == 0 or b.m == 0 then
        return BigNum.zero()
    end
    return BigNum.new(a.m * b.m, a.e + b.e)
end

function BigNum.mulNumber(a: BigNum, factor: number): BigNum
    return BigNum.mul(a, BigNum.new(factor))
end

function BigNum.div(a: BigNum, b: BigNum): BigNum
    if b.m == 0 then
        error("BigNum: Division durch 0")
    end
    if a.m == 0 then
        return BigNum.zero()
    end
    return BigNum.new(a.m / b.m, a.e - b.e)
end

-- -1, 0 oder 1.
function BigNum.compare(a: BigNum, b: BigNum): number
    local d = BigNum.sub(a, b)
    if d.m > 0 then
        return 1
    elseif d.m < 0 then
        return -1
    end
    return 0
end

function BigNum.lt(a: BigNum, b: BigNum): boolean
    return BigNum.compare(a, b) < 0
end

function BigNum.eq(a: BigNum, b: BigNum): boolean
    return BigNum.compare(a, b) == 0
end

function BigNum.max(a: BigNum, b: BigNum): BigNum
    return if BigNum.compare(a, b) >= 0 then copy(a) else copy(b)
end

function BigNum.min(a: BigNum, b: BigNum): BigNum
    return if BigNum.compare(a, b) <= 0 then copy(a) else copy(b)
end

-- Rundet ab. Ab 10^15 hat eine Gleitkommazahl keine Nachkommastellen mehr, der Wert bleibt.
function BigNum.floor(a: BigNum): BigNum
    if a.m == 0 or a.e >= PRECISION_DIGITS then
        return copy(a)
    end
    return BigNum.new(math.floor(a.m * 10 ^ a.e))
end

-- Als gewöhnliche Zahl (verliert ab etwa 10^15 Genauigkeit, ab 10^308 unendlich).
function BigNum.toNumber(a: BigNum): number
    local value = a.m * 10 ^ a.e
    -- Ganze Zahlen exakt zurückgeben (1,4 * 10 soll 14 sein, nicht 14,000000000000002).
    if a.e >= 0 and a.e < PRECISION_DIGITS then
        local rounded = math.round(value)
        if math.abs(value - rounded) <= 1e-9 * math.max(1, math.abs(value)) then
            return rounded
        end
    end
    return value
end

-- Anzeigetext für Spieler (deutsches Komma, Suffixe siehe SUFFIXES).
function BigNum.format(a: BigNum, decimals: number?): string
    error(NOT_IMPLEMENTED)
end

return BigNum
