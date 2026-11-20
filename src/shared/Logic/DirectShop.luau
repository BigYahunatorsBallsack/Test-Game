--!strict
-- Direktkauf von Kisten-Items gegen Gems (Paket 4.6). Rein, ohne Roblox-API, Lune-Tests in
-- tests/directshop.spec.luau. Der Crates-Service schließt die Remote `BuyDirectItem` an.
--
-- Warum: Bei `ArePaidRandomItemsRestricted = true` darf ein Spieler keine Kisten öffnen (Zufall mit
-- Gems, die man mit Robux kauft). Roblox erlaubt als Ersatz den festen Kauf, wenn der Preis auf dem
-- Erwartungswert beruht. Darum ist der Direktkauf nur offen, wenn die Policy sperrt oder unbekannt ist
-- (`isOpen`), nie während der ersten Abfrage ("pending") und nie bei erlaubten Kisten.
--
-- Preis (aus den Daten gerechnet, keine eigene Preistabelle; Werte: docs/balance/directshop_4_6.md):
--  1. Für jede Kiste aus `Economy.directShop.crates`, deren Pool das Item enthält:
--     Erwartungswert = Einzelpreis der Kiste / P(genau dieses Item je Öffnung),
--     P = Langzeitrate der Seltenheit (CrateRoll.longRunRates, mit Pity) / Poolgröße.
--     Kisten ohne Pity rechnen exakt in ganzen Zahlen: Preis x Poolgröße x Summe / Quote.
--  2. Die günstigste Kiste zählt.
--  3. Aufrunden auf `roundSignificantDigits` gültige Stellen, nie unter 1 Gem genau (ganze Gems).
--     Kisten mit Pity rechnen in Gleitkomma; ein Wert, der höchstens FLOAT_TOLERANCE (relativ) über
--     einer Stufe liegt, zählt als genau diese Stufe (Rechenfehler, kein echter Aufschlag).
--  4. `monotoneFloor`: Seltenheiten nach Rang, der Preis ist mindestens der Einstiegspreis (das
--     billigste Item) jeder niedrigeren Seltenheit. Hebt nur an, der Preis bleibt über dem
--     Erwartungswert. Ausschaltbar in den Daten.
-- Kein Preis (nil): unbekannte Items, Event-Items (alle ihre Kisten sind `eventOnly`) und Items in
-- keiner Kiste aus der Liste. Münz-Kisten (Holz) und die Event-Kiste zählen nie (DataCheck).
--
-- Kauf (`buy`): Die erste nicht erfüllte Bedingung ist der Grund: "unknownItem", "notOffered" (kein
-- Preis), "cratesAllowed" (Direktkauf nicht offen), "noProfile", "notEnoughGems". Danach ein Block
-- ohne Warten wie bei CrateOpen: Gems.spend genau den Preis (die einzige Gem-Abbuchung, auf einer
-- Kopie) und +1 im Inventar-Feld der Art (Equipment.INVENTORY_FIELDS), alles auf Arbeitskopien in
-- einer eigenen Koroutine. Wirft oder wartet sie, wird nichts geschrieben: Grund "error", Profil
-- unverändert. Danach werden nur fertige Werte zugewiesen (`gems`, `inventory`). Kein Zufall, kein
-- Ausrüsten, die Pity-Zähler bleiben unberührt.
-- Ergebnis: `{ ok = true, itemId, price, gems, copies }` oder `{ ok = false, reason, detail? }`
-- (`detail` nur bei "error", für das Server-Protokoll).
--
-- `data` ist für Tests überschreibbar ({ Crates, CrateItems, Rarities, Economy }).

local CrateRoll = require("./CrateRoll")
local Equipment = require("./Equipment")
local Gems = require("./Gems")
local CratesData = require("../Data/Crates")
local CrateItemsData = require("../Data/CrateItems")
local EconomyData = require("../Data/Economy")
local RaritiesData = require("../Data/Rarities")

-- Policy-Zustände (Crates.policyState), bei denen der Direktkauf offen ist.
local OPEN_STATES: { [string]: boolean } = { restricted = true, unknown = true }
-- Herkunftstext der Gem-Abbuchung (Gems.spend verlangt einen).
local SPEND_PREFIX = "direct:"
-- Gleitkomma-Toleranz beim Aufrunden (relativ): 1000,0000000001 bleibt 1000.
local FLOAT_TOLERANCE = 1e-9

export type Reason = "unknownItem" | "notOffered" | "cratesAllowed" | "noProfile" | "notEnoughGems" | "error"

export type Context = {
    policyState: string?, -- Crates.policyState: "pending" | "allowed" | "restricted" | "unknown" | "none"
    data: any?, -- Tests: { Crates, CrateItems, Rarities, Economy }
}

export type Entry = {
    itemId: string,
    kind: string,
    rarityId: string,
    name: string,
    price: number, -- Gems
}

type Priced = { price: number, ev: number }

local DirectShop = {}

DirectShop.FLOAT_TOLERANCE = FLOAT_TOLERANCE

local function cratesOf(data: any?): any
    return if data and data.Crates then data.Crates else CratesData
end

local function itemsOf(data: any?): any
    return if data and data.CrateItems then data.CrateItems else CrateItemsData
end

local function raritiesOf(data: any?): any
    return if data and data.Rarities then data.Rarities else RaritiesData
end

local function configOf(data: any?): any
    local economy = if data and data.Economy then data.Economy else EconomyData
    return economy.directShop
end

local function fail(reason: Reason, detail: string?): any
    return { ok = false, reason = reason, detail = detail }
end

local function isWholePositive(value: any): boolean
    return type(value) == "number" and value == value and value > 0 and value < math.huge and value % 1 == 0
end

-- Zähler im Inventar als ganze Zahl ab 0 (kaputte Werte zählen als 0), wie in CrateOpen.
local function countValue(value: any): number
    if type(value) ~= "number" or value ~= value or value < 1 or value == math.huge then
        return 0
    end
    return math.floor(value)
end

-- Stufe der gültigen Stellen: kleinste Zehnerpotenz `step` ab 1, mit der value / step < 10^digits.
local function stepOf(value: number, digits: number): number
    local limit = 10 ^ digits
    local step = 1
    while value / step >= limit do
        step *= 10
    end
    return step
end

-- Exakt: ceil(numerator / denominator) auf `digits` gültige Stellen (ganze Zahlen).
local function roundUpExact(numerator: number, denominator: number, digits: number): number
    local step = stepOf(numerator / denominator, digits)
    local divisor = denominator * step
    return ((numerator + divisor - 1) // divisor) * step
end

-- Gleitkomma: aufrunden auf `digits` gültige Stellen, Rechenfehler bis FLOAT_TOLERANCE zählen nicht.
function DirectShop.roundUp(value: number, digits: number): number
    local step = stepOf(value, digits)
    local units = value / step
    local nearest = math.floor(units + 0.5)
    if math.abs(units - nearest) <= units * FLOAT_TOLERANCE then
        units = nearest
    else
        units = math.ceil(units)
    end
    return units * step
end

-- Ist das Item nur in Event-Kisten? (Alle seine Kisten sind `eventOnly`.)
local function isEventOnly(item: any, crates: any): boolean
    if type(item.crates) ~= "table" or #item.crates == 0 then
        return false
    end
    for _, crateId in item.crates do
        local crate = crates.byId[crateId]
        if crate == nil or crate.eventOnly ~= true then
            return false
        end
    end
    return true
end

-- Darf diese Kiste den Preis bestimmen? Gem-Kiste, nicht Event, ganzer Preis über 0.
local function isPricingCrate(crate: any): boolean
    return crate ~= nil and crate.currency == "gems" and crate.eventOnly ~= true and isWholePositive(crate.price)
end

-- Preis und Erwartungswert eines Items aus einer Kiste (ohne Untergrenze). nil, wenn das Item aus
-- dieser Kiste nicht fallen kann.
local function priceFromCrate(item: any, crate: any, digits: number, data: any?): Priced?
    local poolSize = #CrateRoll.pool(crate.id, item.rarity, data)
    if poolSize == 0 then
        return nil
    end
    if type(crate.pity) ~= "table" then
        -- Ohne Pity exakt: P = Quote / Summe / Poolgröße, also EV = Preis x Poolgröße x Summe / Quote.
        local effective = CrateRoll.effectiveOdds(crate, nil, data)
        local weight = effective.odds[item.rarity]
        if not isWholePositive(weight) or not isWholePositive(effective.total) then
            return nil
        end
        local numerator = crate.price * poolSize * effective.total
        return { price = roundUpExact(numerator, weight, digits), ev = numerator / weight }
    end
    local rate = CrateRoll.longRunRates(crate, data)[item.rarity]
    if type(rate) ~= "number" or not (rate > 0) then
        return nil
    end
    local ev = crate.price * poolSize / rate
    return { price = DirectShop.roundUp(ev, digits), ev = ev }
end

-- Alle Preise: Item-ID -> { price, ev }. Nur Items mit Preis.
local function priceTable(data: any?): { [string]: Priced }
    local cfg = configOf(data)
    local crates = cratesOf(data)
    local digits = cfg.roundSignificantDigits
    local prices: { [string]: Priced } = {}
    for _, item in itemsOf(data).list do
        if isEventOnly(item, crates) then
            continue
        end
        local best: Priced? = nil
        for _, crateId in cfg.crates do
            local crate = crates.byId[crateId]
            if isPricingCrate(crate) and table.find(item.crates, crateId) ~= nil then
                local candidate = priceFromCrate(item, crate, digits, data)
                -- Aufrunden steigt monoton, darum ist der kleinste gerundete Preis der gerundete
                -- kleinste Erwartungswert.
                if candidate ~= nil and (best == nil or candidate.ev < best.ev) then
                    best = candidate
                end
            end
        end
        if best ~= nil then
            prices[item.id] = best
        end
    end
    if cfg.monotoneFloor == true then
        local rarities = raritiesOf(data)
        -- Einstiegspreis je Rang: billigstes Item der Seltenheit.
        local entryByRank: { [number]: number } = {}
        for itemId, priced in prices do
            local rarity = rarities.byId[itemsOf(data).byId[itemId].rarity]
            local rank = if rarity then rarity.rank else 0
            local entry = entryByRank[rank]
            if entry == nil or priced.price < entry then
                entryByRank[rank] = priced.price
            end
        end
        for itemId, priced in prices do
            local rarity = rarities.byId[itemsOf(data).byId[itemId].rarity]
            local rank = if rarity then rarity.rank else 0
            local floor = 0
            for otherRank, entry in entryByRank do
                if otherRank < rank and entry > floor then
                    floor = entry
                end
            end
            if floor > priced.price then
                prices[itemId] = { price = floor, ev = priced.ev }
            end
        end
    end
    return prices
end

-- Ist der Direktkauf bei diesem Policy-Zustand offen? Nur bei "restricted" oder "unknown".
function DirectShop.isOpen(policyState: any): boolean
    return type(policyState) == "string" and OPEN_STATES[policyState] == true
end

-- Preis in Gems oder nil (unbekannt, Event-Item, in keiner Kiste der Liste).
function DirectShop.priceOf(itemId: string, data: any?): number?
    if type(itemId) ~= "string" or itemsOf(data).byId[itemId] == nil then
        return nil
    end
    local priced = priceTable(data)[itemId]
    return if priced then priced.price else nil
end

-- Erwartungswert in Gems (Gleitkomma, ohne Rundung und Untergrenze) oder nil. Für Tests und Anzeige.
function DirectShop.expectedValueOf(itemId: string, data: any?): number?
    if type(itemId) ~= "string" or itemsOf(data).byId[itemId] == nil then
        return nil
    end
    local priced = priceTable(data)[itemId]
    return if priced then priced.ev else nil
end

-- Alle Items mit Preis für den Reiter "Direktkauf": nach Seltenheit (niedrigste zuerst), dann in der
-- Reihenfolge von CrateItems. Dieselbe Rechnung wie beim Kauf.
function DirectShop.catalog(data: any?): { Entry }
    local prices = priceTable(data)
    local rarities = raritiesOf(data)
    local list: { Entry } = {}
    local order: { [string]: number } = {}
    for index, item in itemsOf(data).list do
        local priced = prices[item.id]
        if priced ~= nil and order[item.id] == nil then
            order[item.id] = index
            table.insert(list, { itemId = item.id, kind = item.kind, rarityId = item.rarity, name = item.name, price = priced.price })
        end
    end
    local function rankOf(rarityId: string): number
        local rarity = rarities.byId[rarityId]
        return if rarity then rarity.rank else 0
    end
    table.sort(list, function(a: Entry, b: Entry): boolean
        local ra, rb = rankOf(a.rarityId), rankOf(b.rarityId)
        if ra ~= rb then
            return ra < rb
        end
        return order[a.itemId] < order[b.itemId]
    end)
    return list
end

-- Prüft und rechnet den Kauf auf Arbeitskopien. Schreibt nichts ins Profil.
local function prepare(profile: any, itemId: any, ctx: any): any
    local data = ctx.data
    local item = if type(itemId) == "string" then itemsOf(data).byId[itemId] else nil
    if item == nil then
        return fail("unknownItem")
    end
    local price = DirectShop.priceOf(item.id, data)
    if price == nil then
        return fail("notOffered")
    end
    if not DirectShop.isOpen(ctx.policyState) then
        return fail("cratesAllowed")
    end
    if type(profile) ~= "table" then
        return fail("noProfile")
    end
    if not Gems.canAfford(profile, price, data) then
        return fail("notEnoughGems")
    end
    local field = Equipment.INVENTORY_FIELDS[item.kind]
    if field == nil then
        error(`DirectShop: unbekannte Item-Art {tostring(item.kind)} bei "{item.id}"`)
    end

    local wallet = { gems = profile.gems }
    local spent, reason = Gems.spend(wallet, price, SPEND_PREFIX .. item.id, data)
    if not spent then
        if reason == "notEnoughGems" then
            return fail("notEnoughGems")
        end
        error(`DirectShop: ungültiger Preis {tostring(price)} für "{item.id}"`)
    end
    local inventory = if type(profile.inventory) == "table" then profile.inventory else {}
    local newInventory = table.clone(inventory)
    local bucket = if type(inventory[field]) == "table" then table.clone(inventory[field]) else {}
    local copies = countValue(bucket[item.id]) + 1
    bucket[item.id] = copies
    newInventory[field] = bucket
    return {
        write = { gems = wallet.gems, inventory = newInventory },
        response = { ok = true, itemId = item.id, price = price, gems = wallet.gems, copies = copies },
    }
end

-- Führt `prepare` in einer eigenen Koroutine aus. Wartet sie (yield), wird sie geschlossen.
local function prepareWithoutYield(profile: any, itemId: any, ctx: any): (boolean, any)
    local routine = coroutine.create(prepare)
    local resumed, result = coroutine.resume(routine, profile, itemId, ctx)
    if coroutine.status(routine) ~= "dead" then
        coroutine.close(routine)
        return false, "DirectShop: der Kauf hat gewartet (yield) und wurde abgebrochen"
    end
    return resumed, result
end

-- Kauft ein Item fest gegen Gems. Siehe Kopf der Datei.
function DirectShop.buy(profile: any, itemId: string, ctx: Context?): any
    local context = if type(ctx) == "table" then ctx else {}
    local ok, prepared = prepareWithoutYield(profile, itemId, context)
    if not ok then
        return fail("error", tostring(prepared))
    end
    if prepared.write == nil then
        return prepared -- Ablehnung mit Grund, nichts geschrieben
    end
    -- Ab hier nur Zuweisungen fertiger Werte, im selben Thread direkt nach der Rechnung.
    profile.gems = prepared.write.gems
    profile.inventory = prepared.write.inventory
    return prepared.response
end

return DirectShop
