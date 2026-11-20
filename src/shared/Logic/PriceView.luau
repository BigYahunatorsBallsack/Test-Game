--!strict
-- Robux-Preise für die Anzeige im Shop (Paket 4.6, Sicherheitsprüfung 4.1 N7). Rein, ohne Roblox-API,
-- Lune-Tests in tests/priceview.spec.luau.
--
-- Der Client fragt Preise bei Roblox ab (Controllers/ProductPrices, GetProductInfo). Der Preis aus dem
-- Creator Dashboard ist maßgeblich, denn ihn zeigt auch der Kaufdialog. Unsere Tabellen
-- (Data/Products, Data/GemPacks) sind nur der Ersatz, solange die Abfrage nicht da ist oder scheitert.
-- Ein Produkt, das Roblox als "nicht zum Verkauf" meldet, wird nicht angeboten.

export type Info = { price: number?, forSale: boolean? }

local PriceView = {}

PriceView.TEXT_SOON = "Bald"
PriceView.TEXT_NOT_FOR_SALE = "Nicht verfügbar"

local function validPrice(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value >= 0 and math.floor(value) == value
end

-- Preis in Robux: der von Roblox, sonst der Tabellenpreis.
function PriceView.robux(info: Info?, fallback: number): number
    if info ~= nil and validPrice(info.price) then
        return info.price :: number
    end
    return fallback
end

-- Kann man das Produkt kaufen? Nein bei ID 0 (noch nicht angelegt) und wenn Roblox "nicht zum Verkauf"
-- meldet. Unbekannt (keine Antwort) zählt als kaufbar: Der Kaufdialog entscheidet dann selbst.
function PriceView.buyable(productId: number, info: Info?): boolean
    if type(productId) ~= "number" or productId <= 0 then
        return false
    end
    return not (info ~= nil and info.forSale == false)
end

-- Ganze Zahl mit Tausenderpunkten (2499 -> "2.499").
local function grouped(value: number): string
    local result = tostring(math.floor(value))
    while true do
        local replaced, count = string.gsub(result, "^(-?%d+)(%d%d%d)", "%1.%2")
        result = replaced
        if count == 0 then
            break
        end
    end
    return result
end

-- Text auf dem Kaufknopf: "Bald" (ID 0), "Nicht verfügbar" oder "249 Robux".
function PriceView.buttonText(productId: number, info: Info?, fallback: number): string
    if type(productId) ~= "number" or productId <= 0 then
        return PriceView.TEXT_SOON
    end
    if not PriceView.buyable(productId, info) then
        return PriceView.TEXT_NOT_FOR_SALE
    end
    return `{grouped(PriceView.robux(info, fallback))} Robux`
end

-- Bonus eines Gem-Pakets gegenüber dem Einstiegspaket in ganzen Prozent (gerundet), aus Gems je Robux.
-- nil bei kaputten Werten. Für die Daten von heute ergibt das die Konzeptspalte (0, 8, 18, 31, 37).
function PriceView.gemBonusPercent(gems: number, robux: number, baseGems: number, baseRobux: number): number?
    for _, value in { gems, robux, baseGems, baseRobux } do
        if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
            return nil
        end
    end
    local ratio = (gems / robux) / (baseGems / baseRobux)
    return math.floor((ratio - 1) * 100 + 0.5)
end

-- Abweichung zwischen Dashboard und Tabelle (für Warnungen). nil = gleich oder unbekannt.
function PriceView.mismatch(info: Info?, tablePrice: number): string?
    if info == nil then
        return nil
    end
    if info.forSale == false then
        return "nicht zum Verkauf"
    end
    if validPrice(info.price) and info.price ~= tablePrice then
        return `Preis im Dashboard {info.price} Robux, in den Daten {tablePrice} Robux`
    end
    return nil
end

return PriceView
