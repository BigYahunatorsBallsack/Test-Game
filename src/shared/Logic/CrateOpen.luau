--!strict
-- Kisten öffnen (Paket 4.2). Rein, ohne Roblox-API, Lune-Tests in tests/crateopen.spec.luau.
-- Der Crates-Service schließt die Remote `OpenCrate` an und gibt Zufall und Policy herein.
--
-- Vom Client kommen nur Kisten-ID und Anzahl (1 oder das 10er-Paket, geprüft per RemoteSpec).
-- Preis, Würfe, Pity und Gewinne bestimmt allein der Server aus den Daten (Crates, CrateItems).
--
-- Ablauf von `open(profile, kistenId, anzahl, ctx)`, die erste nicht erfüllte Bedingung ist der Grund:
--  1. Kiste bekannt ("unknownCrate"); Anzahl 1 oder `Crates.bundle.buy` ("badCount").
--  2. `ctx.restricted ~= false`: gesperrt ("restricted"). Unbekannt (nil) gilt als gesperrt
--     (fail-closed, ArePaidRandomItemsRestricted). Das gilt für ALLE Kisten, auch die Holzkiste.
--  3. Event-Kiste ohne `ctx.inSeason == true`: "notInSeason".
--  4. Kein Profil: "noProfile".
--  5. Preis: Einzelöffnung = price, 10er-Paket = price x bundle.buy. Holzkiste in Münzen (Zahlentyp,
--     "notEnoughCoins"), Eisen, Gold und Event in Gems über `Gems.spend` ("notEnoughGems"), der
--     einzigen Gem-Abbuchung.
--  6. Würfe: eine Öffnung, beim 10er-Paket `bundle.get` (11) nacheinander. Jede zählt für die Pity
--     dieser Kiste (CrateRoll). Gewinne zählen im Inventar hoch (`inventory.skins`, `companions`,
--     `toolVariants` nach `kind`), `isNew` ist false, wenn das Item vorher schon da war.
--  7. Alles bis hier rechnet auf Arbeitskopien (Gems bzw. Münzen, Pity, Inventar) und läuft in einer
--     eigenen Koroutine, die ohne Warten fertig werden muss. Wirft sie (zum Beispiel ein kaputter
--     Zufall) oder wartet sie (yield), wird nichts geschrieben: Grund "error", Profil unverändert.
--     Erst danach werden im selben Thread nur noch fertige Werte zugewiesen (kein halbes Buchen).
-- Ergebnis: `{ ok = true, crateId, count, results, highest, pity, gems, coins, free }` oder
-- `{ ok = false, reason, detail? }` (`detail` nur bei "error", für das Server-Protokoll).
--
-- `openFree(profile, kistenId, ctx)`: Gratis-Einstieg (Daily Reward, Paket 5.1). Eine Öffnung, bucht
-- nichts ab, zählt für die Pity. Policy und Saison gelten genauso (bei gesperrter Policy gibt 5.1
-- den festen Ersatzgegenstand). Aufgerufen von Logic/Daily (Remote ClaimDaily, Tag 7) auf einer
-- Arbeitskopie des Profils.
-- `ctx.data` ist für Tests überschreibbar ({ Crates, CrateItems, Rarities, Economy }).

local BigNum = require("./BigNum")
local CrateRoll = require("./CrateRoll")
local Gems = require("./Gems")
local CratesData = require("../Data/Crates")
local RaritiesData = require("../Data/Rarities")

-- Inventar-Feld je Item-Art (CrateItems.kind).
local INVENTORY_FIELDS: { [string]: string } = {
    skin = "skins",
    companion = "companions",
    toolVariant = "toolVariants",
}
-- Herkunftstext der Gem-Abbuchung (Gems.spend verlangt einen).
local SPEND_PREFIX = "crate:"
local BUNDLE_SUFFIX = ":bundle"

export type Reason =
    "unknownCrate"
    | "badCount"
    | "restricted"
    | "notInSeason"
    | "notEnoughGems"
    | "notEnoughCoins"
    | "noProfile"
    | "error"

export type Context = {
    random: () -> number, -- Zufall in [0, 1), im Spiel Random des Servers
    restricted: boolean?, -- ArePaidRandomItemsRestricted; nur false erlaubt das Öffnen
    inSeason: boolean?, -- nur true öffnet die Event-Kiste
    data: any?, -- Tests: { Crates, CrateItems, Rarities, Economy }
}

export type Prize = {
    itemId: string,
    kind: string,
    rarityId: string,
    name: string,
    isNew: boolean, -- vorher nicht im Inventar
    pityTriggered: string?, -- "epic" oder "legendary", wenn die Garantie gegriffen hat
}

local CrateOpen = {}

local function fail(reason: Reason, detail: string?): any
    return { ok = false, reason = reason, detail = detail }
end

local function cratesOf(data: any?): any
    return if data and data.Crates then data.Crates else CratesData
end

local function raritiesRank(data: any?, rarityId: string): number
    local rarities = if data and data.Rarities then data.Rarities else RaritiesData
    local rarity = rarities.byId[rarityId]
    return if rarity then rarity.rank else 0
end

-- Zähler im Inventar als ganze Zahl ab 0 (kaputte Werte zählen als 0).
local function countValue(value: any): number
    if type(value) ~= "number" or value ~= value or value < 1 or value == math.huge then
        return 0
    end
    return math.floor(value)
end

local function copyTable(value: any): { [any]: any }
    return if type(value) == "table" then table.clone(value) else {}
end

local function isPositiveFinite(value: any): boolean
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- Rechnet die ganze Öffnung auf Arbeitskopien aus. Schreibt nichts ins Profil. Gibt entweder ein
-- Fehlschlag-Ergebnis zurück oder `{ write = ..., response = ... }`.
local function prepare(profile: any, crateId: any, count: any, ctx: any, free: boolean): any
    local data = ctx.data
    local crates = cratesOf(data)
    local crate = if type(crateId) == "string" then crates.byId[crateId] else nil
    if crate == nil then
        return fail("unknownCrate")
    end
    local bundle = crates.bundle
    local openings: number, priceFactor: number = 0, 0
    if count == 1 then
        openings, priceFactor = 1, 1
    elseif not free and count == bundle.buy then
        openings, priceFactor = bundle.get, bundle.buy
    else
        return fail("badCount")
    end
    if ctx.restricted ~= false then
        return fail("restricted")
    end
    if crate.eventOnly == true and ctx.inSeason ~= true then
        return fail("notInSeason")
    end
    if type(profile) ~= "table" then
        return fail("noProfile")
    end
    if type(ctx.random) ~= "function" then
        error("CrateOpen: ctx.random fehlt")
    end

    -- Bezahlen (auf einer Kopie). Gratis-Öffnungen buchen nichts.
    local gemsAfter: number? = nil
    local coinsAfter: any = nil
    if not free then
        local price = crate.price * priceFactor
        if crate.currency == "gems" then
            local wallet = { gems = profile.gems }
            local label = SPEND_PREFIX .. crate.id .. (if priceFactor > 1 then BUNDLE_SUFFIX else "")
            local spent, reason = Gems.spend(wallet, price, label, data)
            if not spent then
                if reason == "notEnoughGems" then
                    return fail("notEnoughGems")
                end
                error(`CrateOpen: ungültiger Gem-Preis {tostring(price)} für "{crate.id}"`)
            end
            gemsAfter = wallet.gems
        elseif crate.currency == "coins" then
            if not isPositiveFinite(price) then
                error(`CrateOpen: ungültiger Münzpreis {tostring(price)} für "{crate.id}"`)
            end
            local coins = BigNum.deserialize(profile.coins)
            local cost = BigNum.new(price)
            if BigNum.compare(coins, cost) < 0 then
                return fail("notEnoughCoins")
            end
            coinsAfter = BigNum.serialize(BigNum.sub(coins, cost))
        else
            error(`CrateOpen: unbekannte Währung {tostring(crate.currency)} für "{crate.id}"`)
        end
    end

    -- Würfeln (Pity-Zähler und Inventar auf Kopien).
    local hasPity = type(crate.pity) == "table"
    local pityTable = if type(profile.pity) == "table" then profile.pity else nil
    local counters: any = if hasPity then CrateRoll.counters(if pityTable then pityTable[crate.id] else nil) else nil
    local inventory = if type(profile.inventory) == "table" then profile.inventory else {}
    local changed: { [string]: { [any]: any } } = {}
    local results: { Prize } = {}
    local highest: string? = nil
    local highestRank = 0
    for _ = 1, openings do
        local roll = CrateRoll.roll(crate, counters, ctx.random, data)
        if hasPity then
            counters = roll.pity
        end
        local item = roll.item
        local field = INVENTORY_FIELDS[item.kind]
        if field == nil then
            error(`CrateOpen: unbekannte Item-Art {tostring(item.kind)} bei "{tostring(item.id)}"`)
        end
        local bucket = changed[field]
        if bucket == nil then
            bucket = copyTable(inventory[field])
            changed[field] = bucket
        end
        local before = countValue(bucket[item.id])
        bucket[item.id] = before + 1
        table.insert(results, {
            itemId = item.id,
            kind = item.kind,
            rarityId = roll.rarityId,
            name = item.name,
            isNew = before == 0,
            pityTriggered = roll.pityTriggered,
        })
        local rank = raritiesRank(data, roll.rarityId)
        if highest == nil or rank > highestRank then
            highest, highestRank = roll.rarityId, rank
        end
    end

    -- Neue Werte fertig bauen, damit beim Schreiben nur noch Zuweisungen übrig bleiben.
    local newInventory = copyTable(inventory)
    for field, bucket in changed do
        newInventory[field] = bucket
    end
    local newPity: any = nil
    if hasPity then
        newPity = copyTable(pityTable)
        newPity[crate.id] = counters
    end
    local response = {
        ok = true,
        crateId = crate.id,
        count = count,
        results = results,
        highest = highest,
        pity = if hasPity then { sinceEpic = counters.sinceEpic, sinceLegendary = counters.sinceLegendary } else nil,
        gems = if gemsAfter ~= nil then gemsAfter else Gems.balance(profile, data),
        coins = if coinsAfter ~= nil then table.clone(coinsAfter) else BigNum.serialize(BigNum.deserialize(profile.coins)),
        free = free,
    }
    return {
        write = { gems = gemsAfter, coins = coinsAfter, pity = newPity, inventory = newInventory },
        response = response,
    }
end

-- Führt `prepare` in einer eigenen Koroutine aus. Wartet sie (yield), wird sie geschlossen.
local function prepareWithoutYield(profile: any, crateId: any, count: any, ctx: any, free: boolean): (boolean, any)
    local routine = coroutine.create(prepare)
    local resumed, result = coroutine.resume(routine, profile, crateId, count, ctx, free)
    if coroutine.status(routine) ~= "dead" then
        coroutine.close(routine)
        return false, "CrateOpen: die Öffnung hat gewartet (yield) und wurde abgebrochen"
    end
    return resumed, result
end

local function execute(profile: any, crateId: any, count: any, ctx: any, free: boolean): any
    local context = if type(ctx) == "table" then ctx else {}
    local ok, prepared = prepareWithoutYield(profile, crateId, count, context, free)
    if not ok then
        return fail("error", tostring(prepared))
    end
    if prepared.write == nil then
        return prepared -- Fehlschlag mit Grund, nichts geschrieben
    end
    -- Ab hier nur Zuweisungen fertiger Werte, im selben Thread direkt nach der Rechnung.
    local write = prepared.write
    if write.gems ~= nil then
        profile.gems = write.gems
    end
    if write.coins ~= nil then
        profile.coins = write.coins
    end
    if write.pity ~= nil then
        profile.pity = write.pity
    end
    profile.inventory = write.inventory
    return prepared.response
end

-- Öffnet eine Kiste (1) oder das 10er-Paket. Siehe Kopf der Datei.
function CrateOpen.open(profile: any, crateId: string, count: number, ctx: Context): any
    -- Gratis geht nur über `openFree`: ein `ctx.free` von außen zählt hier nicht.
    return execute(profile, crateId, count, ctx, false)
end

-- Gratis-Öffnung (eine), bucht nichts ab und zählt für die Pity.
function CrateOpen.openFree(profile: any, crateId: string, ctx: Context): any
    return execute(profile, crateId, 1, ctx, true)
end

CrateOpen.INVENTORY_FIELDS = INVENTORY_FIELDS

return CrateOpen
