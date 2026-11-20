--!strict
-- Texte und Zahlen für die Quoten-Anzeige im Kisten-Fenster (Paket 4.6). Rein, ohne Roblox-API,
-- Lune-Tests in tests/oddsview.spec.luau.
--
-- Roblox verlangt vor dem Kauf alle möglichen Ergebnisse mit echten Prozentzahlen. Gerundete Werte
-- sind erlaubt, wenn der Hinweis `ROUNDING_NOTE` dabeisteht. Die Pity ist selbst ein Quoten-
-- Veränderer: Sie wird mit Zahlen erklärt (`pityRules`), und steht sie bei der nächsten Öffnung an,
-- zeigt das Fenster die dann geltenden Quoten (CrateRoll.effectiveOdds).
--
-- Dieses Modul rechnet keine Quoten selbst. Die Zahlen kommen aus Logic/CrateRoll (dieselben
-- Funktionen, über die der Server würfelt). Hier stehen nur Formatierung, Zähler bis zur Garantie,
-- Kosten bis zur Garantie und die Stelle der Garantie im 10 + 1 Paket.

local OddsView = {}

OddsView.ROUNDING_NOTE = "Quoten sind gerundet. Die Summe der angezeigten Werte kann leicht von 100 % abweichen."

-- Prozente ab dieser Größe mit zwei Nachkommastellen, kleinere mit `SMALL_DIGITS` gültigen Stellen,
-- damit nie "0 %" für ein mögliches Ergebnis dasteht.
local TWO_DECIMALS_FROM = 0.1
local SMALL_DIGITS = 3

local TIER_NAMES: { [string]: string } = {
    epic = "Episch",
    legendary = "Legendär",
}

-- Zahl mit deutschem Komma, Nullen am Ende weg ("22,50" -> "22,5", "75,00" -> "75").
local function trimmed(text: string): string
    if string.find(text, "%.") then
        text = string.gsub(text, "0+$", "")
        text = string.gsub(text, "%.$", "")
    end
    return (string.gsub(text, "%.", ","))
end

-- Anteil (0 bis 1) als Prozenttext: 0.75 -> "75 %", 0.225 -> "22,5 %", 0.0016667 -> "0,17 %",
-- 0.000417 -> "0,0417 %". 0 ergibt "0 %". Kaputte Werte (kein number, NaN, negativ) ergeben "0 %".
function OddsView.percentText(fraction: any): string
    if type(fraction) ~= "number" or fraction ~= fraction or fraction <= 0 or fraction == math.huge then
        return "0 %"
    end
    local percent = fraction * 100
    if percent >= TWO_DECIMALS_FROM then
        return `{trimmed(string.format("%.2f", percent))} %`
    end
    -- gültige Stellen: Exponent der ersten Ziffer bestimmt die Nachkommastellen
    local exponent = math.floor(math.log10(percent))
    local decimals = math.max(SMALL_DIGITS - 1 - exponent, 0)
    return `{trimmed(string.format(`%.{decimals}f`, percent))} %`
end

export type PityInfo = {
    epicLeft: number, -- in so vielen Öffnungen spätestens Episch oder besser (ab 1)
    legendaryLeft: number, -- in so vielen Öffnungen spätestens Legendär oder besser (ab 1)
    epicCost: number?, -- Preis dieser Öffnungen (nil bei Münz-Kisten)
    legendaryCost: number?,
    due: string?, -- "legendary" oder "epic", wenn die nächste Öffnung garantiert ist
}

local function counterValue(value: any): number
    if type(value) ~= "number" or value ~= value or value == math.huge or value < 0 then
        return 0
    end
    return math.floor(value)
end

-- Zähler bis zur Garantie und ihre Kosten. nil bei Kisten ohne Pity. `counters` ist der Pity-Stand
-- dieser Kiste aus dem StateSync (`{ sinceEpic, sinceLegendary }`, fehlt = 0/0). Die Regel ist
-- dieselbe wie in CrateRoll.guarantee (Lune-Test vergleicht beide).
function OddsView.pityInfo(crate: any, counters: any): PityInfo?
    if type(crate) ~= "table" or type(crate.pity) ~= "table" then
        return nil
    end
    local c = if type(counters) == "table" then counters else {}
    local epicLeft = math.max(crate.pity.epic - counterValue(c.sinceEpic), 1)
    local legendaryLeft = math.max(crate.pity.legendary - counterValue(c.sinceLegendary), 1)
    local gems = crate.currency == "gems"
    local due: string? = nil
    if legendaryLeft == 1 then
        due = "legendary"
    elseif epicLeft == 1 then
        due = "epic"
    end
    return {
        epicLeft = epicLeft,
        legendaryLeft = legendaryLeft,
        epicCost = if gems then epicLeft * crate.price else nil,
        legendaryCost = if gems then legendaryLeft * crate.price else nil,
        due = due,
    }
end

-- Ganze Zahl mit Tausenderpunkten (2800 -> "2.800").
function OddsView.grouped(value: number): string
    local text = tostring(math.floor(value))
    local result = text
    while true do
        local replaced, count = string.gsub(result, "^(-?%d+)(%d%d%d)", "%1.%2")
        result = replaced
        if count == 0 then
            break
        end
    end
    return result
end

-- Zwei Zeilen für die Kisten-Karte: "Episch oder besser garantiert in 7 Öffnungen (2.800 Gems)."
function OddsView.pityLines(crate: any, counters: any): { string }
    local info = OddsView.pityInfo(crate, counters)
    if info == nil then
        return {}
    end
    local function line(tierName: string, left: number, cost: number?): string
        local openings = if left == 1 then "der nächsten Öffnung" else `{left} Öffnungen`
        local costText = if cost ~= nil then ` ({OddsView.grouped(cost)} Gems)` else ""
        return `{tierName} oder besser garantiert in {openings}{costText}.`
    end
    return {
        line("Episch", info.epicLeft, info.epicCost),
        line("Legendär", info.legendaryLeft, info.legendaryCost),
    }
end

-- Die Pity-Regel in Zahlen (Details-Fenster).
function OddsView.pityRules(crate: any): { string }
    if type(crate) ~= "table" or type(crate.pity) ~= "table" then
        return {}
    end
    local lines = {}
    for _, tier in { "epic", "legendary" } do
        local limit = crate.pity[tier]
        if type(limit) == "number" and limit >= 1 then
            table.insert(lines, `Nach {limit - 1} Öffnungen ohne {TIER_NAMES[tier]} oder besser ist die {limit}. Öffnung sicher {TIER_NAMES[tier]} oder besser.`)
        end
    end
    table.insert(lines, "Legendär oder besser setzt beide Zähler zurück, Episch nur den Episch-Zähler.")
    table.insert(lines, "Steht eine Garantie an, wird nur unter den garantierten Seltenheiten gewürfelt, im Verhältnis der Tabelle.")
    return lines
end

export type BundleNote = { tier: string, at: number }

-- Garantien, die im Paket mit `openings` Öffnungen spätestens greifen, höhere Stufe zuerst:
-- `{ { tier = "legendary", at = 4 }, { tier = "epic", at = 2 } }`. `at` ist die Nummer der Öffnung
-- im Paket (ab 1). Kommt vorher zufällig eine passende Seltenheit, greift sie nicht mehr; darum
-- "spätestens". Leere Liste bei Kisten ohne Pity oder wenn keine Garantie ins Paket fällt.
function OddsView.bundleNotes(crate: any, counters: any, openings: number): { BundleNote }
    local info = OddsView.pityInfo(crate, counters)
    if info == nil or type(openings) ~= "number" or openings < 1 then
        return {}
    end
    local notes: { BundleNote } = {}
    if info.legendaryLeft <= openings then
        table.insert(notes, { tier = "legendary", at = info.legendaryLeft })
    end
    if info.epicLeft <= openings then
        table.insert(notes, { tier = "epic", at = info.epicLeft })
    end
    return notes
end

-- Satz zu den Garantien im Paket, nil wenn keine hineinfällt.
function OddsView.bundleText(crate: any, counters: any, openings: number): string?
    local notes = OddsView.bundleNotes(crate, counters, openings)
    if #notes == 0 then
        return nil
    end
    local parts = {}
    for _, note in notes do
        table.insert(parts, `spätestens die {note.at}. Öffnung {TIER_NAMES[note.tier]} oder besser`)
    end
    return `Im Paket ist {table.concat(parts, ", ")}.`
end

-- Überschrift der Quotentabelle: Steht eine Garantie an, gelten für diesen Spieler andere Quoten.
function OddsView.oddsTitle(due: string?): string
    if due ~= nil and TIER_NAMES[due] ~= nil then
        return `Deine nächste Öffnung (garantiert {TIER_NAMES[due]} oder besser)`
    end
    return "Quoten je Öffnung"
end

return OddsView
