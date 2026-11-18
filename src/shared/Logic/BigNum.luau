--!strict
-- Zahlentyp für große Werte (Mantisse und Exponent): Wert = m * 10^e.
-- Paket 0.3 lieferte die Schnittstelle (new, zero, serialize, deserialize), Paket 1.2 das
-- Rechnen und Vergleichen, das Sammeln und Verkaufen brauchen, Paket 1.3 die Anzeige
-- (format) und die Grenzwert-Tests (tests/bignum.spec.luau).
--
-- Anzeige: deutsches Komma als Dezimaltrenner, ab 1000 mit Suffix
-- K, M, B, T, danach Qa, Qi, Sx, Sp, Oc, No, Dc (bis 10^35), ab 10^36 wissenschaftlich
-- ("1,23e36").

export type BigNum = { m: number, e: number }
export type Serialized = { m: number, e: number }

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
-- Ganze Zahlen bleiben ganz: 1,15 * 10^2 ist intern 114,99999999999999 und soll 115 ergeben
-- (gleiche Toleranz wie toNumber), sonst ginge beim Verkauf eine Münze verloren.
function BigNum.floor(a: BigNum): BigNum
    if a.m == 0 or a.e >= PRECISION_DIGITS then
        return copy(a)
    end
    local value = a.m * 10 ^ a.e
    local rounded = math.round(value)
    if math.abs(value - rounded) <= 1e-9 * math.max(1, math.abs(value)) then
        return BigNum.new(rounded)
    end
    return BigNum.new(math.floor(value))
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

-- Anzeige (Paket 1.3) ------------------------------------------------------------------

-- Nachkommastellen: Standard und erlaubter Bereich. Nullen am Ende entfallen ("1K", "1,5K").
BigNum.DEFAULT_DECIMALS = 1
local MAX_DECIMALS = 4
-- Wissenschaftliche Schreibweise ab 10^36: bis zu 2 Nachkommastellen ("1,23e36").
local SCIENTIFIC_DECIMALS = 2
-- Gleitkomma-Rauschen beim Aufrunden von Hälften (1,15 ist intern 1,1499999...).
local ROUND_EPSILON = 1e-9

-- Rundet x auf `decimals` Stellen (Hälften nach oben) und gibt die Zahl als ganze Zahl
-- mal 10^decimals zurück.
local function roundScaled(x: number, decimals: number): number
    return math.floor(x * 10 ^ decimals + 0.5 + ROUND_EPSILON)
end

-- Baut den Text aus einer ganzen Zahl mal 10^decimals: deutsches Komma, ohne Endnullen.
local function scaledToText(scaled: number, decimals: number): string
    if decimals == 0 then
        return string.format("%d", scaled)
    end
    local unit = 10 ^ decimals
    local whole = math.floor(scaled / unit)
    local fraction = string.format("%0" .. decimals .. "d", scaled - whole * unit)
    fraction = string.gsub(fraction, "0+$", "") :: string
    if fraction == "" then
        return string.format("%d", whole)
    end
    return string.format("%d", whole) .. BigNum.DECIMAL_SEPARATOR .. fraction
end

local function scientificText(m: number, e: number): string
    local scaled = roundScaled(m, SCIENTIFIC_DECIMALS)
    if scaled >= 10 * 10 ^ SCIENTIFIC_DECIMALS then
        -- 9,996e40 rundet auf 10,00 und wird zu 1e41.
        scaled = 10 ^ SCIENTIFIC_DECIMALS
        e += 1
    end
    return scaledToText(scaled, SCIENTIFIC_DECIMALS) .. "e" .. string.format("%d", e)
end

-- Anzeigetext für Spieler (deutsches Komma, Suffixe siehe SUFFIXES, ab 10^36 "1,23e36").
-- `decimals` (0 bis 4, Standard 1) gilt für Zahlen bis 10^36. Rundet Hälften auf und springt
-- an den Grenzen sauber weiter: 999,96K wird "1M", nie "1000K".
function BigNum.format(a: BigNum, decimals: number?): string
    if a.m == 0 or a.m ~= a.m then
        return "0"
    end
    local d = BigNum.DEFAULT_DECIMALS
    if decimals ~= nil and decimals == decimals then
        d = math.clamp(math.floor(decimals), 0, MAX_DECIMALS)
    end

    local negative = a.m < 0
    local m = math.abs(a.m)
    local e = a.e
    local text: string

    if e >= BigNum.SCIENTIFIC_FROM_EXPONENT then
        text = scientificText(m, e)
    else
        -- Stufe 0 = unter 1000 ohne Suffix, Stufe n = SUFFIXES[n].
        local tier = if e >= 3 then e // 3 else 0
        local x = if tier == 0 then m * 10 ^ e else m * 10 ^ (e - 3 * tier)
        local scaled = roundScaled(x, d)
        if scaled >= 1000 * 10 ^ d then
            -- Die Rundung erreicht die nächste Stufe (999,96K wird 1M).
            tier += 1
            scaled = 10 ^ d
        end
        if tier > #BigNum.SUFFIXES then
            text = scientificText(1, 3 * tier)
        elseif scaled == 0 then
            return "0"
        else
            text = scaledToText(scaled, d) .. (if tier == 0 then "" else BigNum.SUFFIXES[tier])
        end
    end

    return if negative then "-" .. text else text
end

return BigNum
