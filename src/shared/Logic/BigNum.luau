--!strict
-- Zahlentyp für große Werte (Mantisse und Exponent): Wert = m * 10^e.
-- Paket 0.3 liefert nur die Schnittstelle und das, was das Profil braucht (new, zero,
-- serialize, deserialize). Rechnen, Vergleichen und die Anzeige folgen in Paket 1.3.
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

function BigNum.add(a: BigNum, b: BigNum): BigNum
    error(NOT_IMPLEMENTED)
end

function BigNum.sub(a: BigNum, b: BigNum): BigNum
    error(NOT_IMPLEMENTED)
end

function BigNum.mul(a: BigNum, b: BigNum): BigNum
    error(NOT_IMPLEMENTED)
end

function BigNum.mulNumber(a: BigNum, factor: number): BigNum
    error(NOT_IMPLEMENTED)
end

function BigNum.div(a: BigNum, b: BigNum): BigNum
    error(NOT_IMPLEMENTED)
end

-- -1, 0 oder 1.
function BigNum.compare(a: BigNum, b: BigNum): number
    error(NOT_IMPLEMENTED)
end

function BigNum.lt(a: BigNum, b: BigNum): boolean
    error(NOT_IMPLEMENTED)
end

function BigNum.eq(a: BigNum, b: BigNum): boolean
    error(NOT_IMPLEMENTED)
end

function BigNum.max(a: BigNum, b: BigNum): BigNum
    error(NOT_IMPLEMENTED)
end

function BigNum.floor(a: BigNum): BigNum
    error(NOT_IMPLEMENTED)
end

function BigNum.toNumber(a: BigNum): number
    error(NOT_IMPLEMENTED)
end

-- Anzeigetext für Spieler (deutsches Komma, Suffixe siehe SUFFIXES).
function BigNum.format(a: BigNum, decimals: number?): string
    error(NOT_IMPLEMENTED)
end

return BigNum
