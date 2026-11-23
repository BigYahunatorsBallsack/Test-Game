--!strict
-- Reine Prüfung aller Datentabellen. Gibt eine Liste von Fehlertexten zurück (leer = ok).
-- `DataCheck.run()` prüft die echten Tabellen, `DataCheck.run(dataSet)` eine übergebene
-- (z. B. absichtlich kaputte) Fassung. Der Server ruft die Prüfung beim Start auf.

local TreeLayout = require("./TreeLayout")
local Perks = require("./Perks")
local Offers = require("./Offers")
local Equipment = require("./Equipment")
local DirectShop = require("./DirectShop")
local Seasons = require("./Seasons")
local SeasonPass = require("./SeasonPass")

local QUOTA_TOTAL = 10000 -- 100 % in Hundertstel-Prozent
local GEM_BONUS_TOLERANCE = 1 -- Prozentpunkte
local HEX_PATTERN = "^#%x%x%x%x%x%x$"

-- Grenzen für Economy.purchases (Paket 4.1): ganze Zahlen in diesen Bereichen.
--  * receiptCacheSize ab 50: Ein noch nicht bestätigter Beleg darf nicht von wenigen neueren Käufen
--    aus der Liste gedrängt werden (sonst bucht der nächste Versuch doppelt). Außerdem muss die
--    Liste mindestens so lang sein wie das Kaufprotokoll (siehe checkPurchases).
--  * maxGems ab 1_000_000: sanitize kappt Guthaben über maxGems bei jedem Laden und Speichern. Ein zu
--    kleiner Wert würde bezahlte Gems vernichten (siehe Kommentar in Economy.purchases).
local PURCHASE_LIMITS: { { key: string, min: number, max: number } } = {
    { key = "receiptCacheSize", min = 50, max = 1000 },
    { key = "purchaseLogSize", min = 1, max = 500 },
    { key = "saveTimeoutSeconds", min = 1, max = 120 },
    { key = "maxGems", min = 1_000_000, max = 1e9 },
}

local CURRENCIES = { coins = true, gems = true }
-- Kisten (Paket 4.2): Pity-Grenzen der Kisten mit Garantie (Konzept: Episch spätestens bei 15,
-- Legendär spätestens bei 60), erlaubte Item-Arten, Mindestzahl Items je Seltenheit mit Quote > 0
-- im Pool jeder Kiste (Soll sind 3, Pflicht ist 1, sonst kann der Wurf kein Item liefern) und die
-- Kiste, deren Items exklusiv sind.
local CRATE_PITY = { gold = { epic = 15, legendary = 60 }, event = { epic = 15, legendary = 60 } }
local PITY_TIERS = { "epic", "legendary" }
local CRATE_ITEM_KINDS = { skin = true, companion = true, toolVariant = true }
local MIN_POOL_ITEMS = 1
local EXCLUSIVE_CRATE = "event"
local PRODUCT_KINDS = { gamepass = true, developerProduct = true, direct = true }
-- Daily Reward (Paket 5.1): erlaubte Felder je Art der Tage 1 bis 6 (Logic/Daily kennt genau diese).
local DAILY_FIELDS: { [string]: { [string]: boolean } } = {
    coinBoost = { day = true, kind = true, seconds = true },
    luck = { day = true, kind = true, seconds = true },
    gems = { day = true, kind = true, amount = true },
}
local DAILY_DAY7_FIELDS = { day = true, kind = true, crateId = true }
-- Saison-Pass (Paket 5.5b): erlaubte Felder je Belohnungsart (Logic/SeasonPass.claim kennt genau
-- diese). Ein Feld wie `crateId` fällt so auf: nie Kisten, nie Zufall.
local PASS_REWARD_FIELDS: { [string]: { [string]: boolean } } = {
    gems = { kind = true, amount = true },
    coinBoost = { kind = true, seconds = true },
    luck = { kind = true, seconds = true },
    item = { kind = true, itemId = true },
}
local EFFECT_KINDS = {
    setTool = true,
    rateBonus = true,
    setTank = true,
    sellBonus = true,
    luckBonus = true,
    grantedBySandstorm = true,
    zoneKey = true,
}
-- Welche Wirkung in welchen Ast gehört (Konzept: Sammeln = Rate, Tank = Kapazität,
-- Verkauf = Preisfaktor, Glück = Fundchance).
local BRANCH_OF_EFFECT = {
    setTool = "collect",
    rateBonus = "collect",
    setTank = "tank",
    sellBonus = "sell",
    luckBonus = "luck",
    grantedBySandstorm = "sandstorm",
    zoneKey = "sandstorm",
}
local BP_EFFECTS = { rateBonus = true, sellBonus = true, luckBonus = true }
local CONDITION_KINDS = { tankAtLeast = true, sold = true, node = true }
local TUTORIAL_TARGETS = { sand = true, stand = true, tree = true }
local BRANCHES = { collect = true, tank = true, sell = true, luck = true, sandstorm = true }

-- Alle Tabellen, die geprüft werden. Felder sind bewusst `any`, damit auch kaputte
-- Fassungen übergeben werden können.
export type DataSet = {
    Rarities: any,
    Tools: any,
    SandTypes: any,
    Zones: any,
    FindOdds: any,
    Finds: any,
    Crates: any,
    CrateItems: any,
    ItemLooks: any,
    GemPacks: any,
    Products: any,
    Economy: any,
    UpgradeTree: any,
    World: any,
    Terrain: any,
    Tutorial: any,
    TreeLayout: any,
    UnlockAnimation: any,
    TreeSounds: any,
    ToolLooks: any,
    Weather: any,
    Collection: any,
    Screen: any,
    Offers: any,
    Seasons: any,
    SeasonPass: any,
    Koloss: any,
}

local DataCheck = {}

-- Lädt die echten Datenmodule.
function DataCheck.defaults(): DataSet
    return {
        Rarities = require("../Data/Rarities"),
        Tools = require("../Data/Tools"),
        SandTypes = require("../Data/SandTypes"),
        Zones = require("../Data/Zones"),
        FindOdds = require("../Data/FindOdds"),
        Finds = require("../Data/Finds"),
        Crates = require("../Data/Crates"),
        CrateItems = require("../Data/CrateItems"),
        ItemLooks = require("../Data/ItemLooks"),
        GemPacks = require("../Data/GemPacks"),
        Products = require("../Data/Products"),
        Economy = require("../Data/Economy"),
        UpgradeTree = require("../Data/UpgradeTree"),
        World = require("../Data/World"),
        Terrain = require("../Data/Terrain"),
        Tutorial = require("../Data/Tutorial"),
        TreeLayout = require("../Data/TreeLayout"),
        UnlockAnimation = require("../Data/UnlockAnimation"),
        TreeSounds = require("../Data/TreeSounds"),
        ToolLooks = require("../Data/ToolLooks"),
        Weather = require("../Data/Weather"),
        Collection = require("../Data/Collection"),
        Screen = require("../Data/Screen"),
        Offers = require("../Data/Offers"),
        Seasons = require("../Data/Seasons"),
        SeasonPass = require("../Data/SeasonPass"),
        Koloss = require("../Data/Koloss"),
    }
end

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInt(value: any): boolean
    return isFinite(value) and value % 1 == 0
end

local function isList(value: any): boolean
    return type(value) == "table"
end

-- Prüft, dass `list` Einträge mit eindeutiger id hat und `byId` dazu passt.
local function checkIds(errors: { string }, label: string, module: any)
    if type(module) ~= "table" or not isList(module.list) then
        table.insert(errors, `{label}: list fehlt`)
        return
    end
    local seen: { [string]: boolean } = {}
    for index, entry in module.list do
        local id = entry.id
        if type(id) ~= "string" or id == "" then
            table.insert(errors, `{label}: Eintrag {index} hat keine gültige id`)
        elseif seen[id] then
            table.insert(errors, `{label}: id "{id}" ist doppelt`)
        else
            seen[id] = true
            if type(module.byId) ~= "table" or module.byId[id] ~= entry then
                table.insert(errors, `{label}: byId passt nicht zu list bei "{id}"`)
            end
        end
    end
end

local function checkHex(errors: { string }, label: string, id: any, hex: any)
    if type(hex) ~= "string" or not string.match(hex, HEX_PATTERN) then
        table.insert(errors, `{label} "{tostring(id)}": colorHex muss Hex-Text wie #RRGGBB sein`)
    end
end

-- Prüft eine Quotentabelle: nur bekannte Seltenheiten, ganze Zahlen >= 0, Summe 10000.
local function checkOdds(errors: { string }, label: string, odds: any, rarities: any)
    if type(odds) ~= "table" then
        table.insert(errors, `{label}: Quotentabelle fehlt`)
        return
    end
    local sum = 0
    for rarityId, value in odds do
        if type(rarityId) ~= "string" or rarities.byId[rarityId] == nil then
            table.insert(errors, `{label}: unbekannte Seltenheit "{tostring(rarityId)}"`)
        end
        if not isInt(value) or value < 0 then
            table.insert(
                errors,
                `{label}: Quote von "{tostring(rarityId)}" muss eine ganze Zahl ab 0 sein`
            )
        else
            sum += value
        end
    end
    if sum ~= QUOTA_TOTAL then
        table.insert(errors, `{label}: Quoten ergeben {sum} statt {QUOTA_TOTAL}`)
    end
end

local function checkRarities(errors: { string }, data: DataSet)
    local rarities = data.Rarities
    checkIds(errors, "Rarities", rarities)
    if type(rarities) ~= "table" or not isList(rarities.list) then
        return
    end
    local lastFactor = 0
    for index, rarity in rarities.list do
        if rarity.rank ~= index then
            table.insert(errors, `Rarities "{tostring(rarity.id)}": rank muss {index} sein`)
        end
        checkHex(errors, "Rarities", rarity.id, rarity.colorHex)
        if not isFinite(rarity.valueFactor) or rarity.valueFactor <= lastFactor then
            table.insert(errors, `Rarities "{tostring(rarity.id)}": valueFactor muss steigen`)
        else
            lastFactor = rarity.valueFactor
        end
    end
end

local function checkQuotas(errors: { string }, data: DataSet)
    local rarities = data.Rarities
    if type(rarities) ~= "table" or type(rarities.byId) ~= "table" then
        return
    end

    -- Fundquoten: alle Tabellen unter FindOdds.tables.
    if type(data.FindOdds) == "table" and type(data.FindOdds.tables) == "table" then
        for name, odds in data.FindOdds.tables do
            checkOdds(errors, `FindOdds.{tostring(name)}`, odds, rarities)
        end
    else
        table.insert(errors, "FindOdds: tables fehlt")
    end

    -- Kistenquoten: alle Tabellen unter Crates.Odds und die Tabelle jeder Kiste.
    local crates = data.Crates
    if type(crates) ~= "table" then
        table.insert(errors, "Crates: Tabelle fehlt")
        return
    end
    if type(crates.Odds) == "table" then
        for name, odds in crates.Odds do
            checkOdds(errors, `Crates.Odds.{tostring(name)}`, odds, rarities)
        end
    else
        table.insert(errors, "Crates: Odds fehlt")
    end
    if isList(crates.list) then
        for _, crate in crates.list do
            local isShared = false
            if type(crates.Odds) == "table" then
                for _, odds in crates.Odds do
                    if odds == crate.odds then
                        isShared = true
                    end
                end
            end
            if not isShared then
                -- Eigene Tabelle der Kiste, die nicht in Odds steht: trotzdem prüfen.
                checkOdds(errors, `Crates "{tostring(crate.id)}".odds`, crate.odds, rarities)
            end
        end
    end
end

local function checkCrates(errors: { string }, data: DataSet)
    local crates = data.Crates
    checkIds(errors, "Crates", crates)
    if type(crates) ~= "table" or not isList(crates.list) then
        return
    end

    for _, crate in crates.list do
        local label = `Crates "{tostring(crate.id)}"`
        if not isFinite(crate.price) or crate.price <= 0 then
            table.insert(errors, `{label}: price muss größer als 0 sein`)
        end
        if CURRENCIES[crate.currency] == nil then
            table.insert(errors, `{label}: currency muss "coins" oder "gems" sein`)
        elseif crate.currency == "gems" and isFinite(crate.price) and crate.price ~= math.floor(crate.price) then
            table.insert(errors, `{label}: der Gem-Preis muss eine ganze Zahl sein`)
        end
        if crate.eventOnly ~= nil and type(crate.eventOnly) ~= "boolean" then
            table.insert(errors, `{label}: eventOnly muss true oder false sein`)
        end
    end

    -- Jede Kiste liest dieselbe Tabelle wie die Anzeige (Crates.Odds); die Event-Kiste
    -- verweist auf dieselbe Referenz wie die Goldkiste.
    local gold = crates.byId and crates.byId.gold
    local event = crates.byId and crates.byId.event
    if gold == nil then
        table.insert(errors, "Crates: Goldkiste (gold) fehlt")
        return
    end
    for _, key in { "wood", "iron", "gold" } do
        local crate = crates.byId[key]
        if crate == nil then
            table.insert(errors, `Crates: Kiste "{key}" fehlt`)
        elseif type(crates.Odds) ~= "table" or crate.odds ~= crates.Odds[key] then
            table.insert(errors, `Crates "{key}": odds muss auf Crates.Odds.{key} verweisen`)
        end
    end
    if event == nil then
        table.insert(errors, "Crates: Event-Kiste (event) fehlt")
    elseif event.odds ~= gold.odds then
        table.insert(errors, "Crates: Event-Kiste muss dieselbe Quotentabelle wie die Goldkiste nutzen")
    end

    -- Pity der Gold- und der Event-Kiste: Episch spätestens bei 15, Legendär spätestens bei 60
    -- (eigene Tabellen, eigene Zähler im Profil).
    for crateId, expected in CRATE_PITY do
        local crate = crates.byId[crateId]
        local pity = if crate then crate.pity else nil
        if crate ~= nil and (type(pity) ~= "table" or pity.epic ~= expected.epic or pity.legendary ~= expected.legendary) then
            table.insert(errors, `Crates {crateId}: pity muss epic = {expected.epic} und legendary = {expected.legendary} sein`)
        end
    end
    -- Jede Pity (auch künftige Kisten): ganze Grenzen ab 1, Episch nicht nach Legendär, und für
    -- jede Stufe hat mindestens eine Seltenheit dieser Stufe oder besser eine Quote über 0 (sonst
    -- könnte die Garantie nichts würfeln). Die Schlüssel sind Seltenheits-IDs.
    local rarities = data.Rarities
    for _, crate in crates.list do
        local pity = crate.pity
        if pity == nil then
            continue
        end
        local label = `Crates "{tostring(crate.id)}".pity`
        if type(pity) ~= "table" then
            table.insert(errors, `{label} muss eine Tabelle sein`)
            continue
        end
        for _, tier in PITY_TIERS do
            local limit = pity[tier]
            if not isInt(limit) or limit < 1 then
                table.insert(errors, `{label}.{tier} muss eine ganze Zahl ab 1 sein`)
            elseif type(rarities) == "table" and type(rarities.byId) == "table" and rarities.byId[tier] ~= nil and type(crate.odds) == "table" then
                local reachable = 0
                for rarityId, share in crate.odds do
                    local rarity = rarities.byId[rarityId]
                    if rarity ~= nil and rarity.rank >= rarities.byId[tier].rank and isFinite(share) then
                        reachable += share
                    end
                end
                if reachable <= 0 then
                    table.insert(errors, `{label}.{tier}: keine Seltenheit ab "{tier}" hat eine Quote über 0`)
                end
            elseif type(rarities) == "table" and type(rarities.byId) == "table" and rarities.byId[tier] == nil then
                table.insert(errors, `{label}.{tier}: Seltenheit "{tier}" fehlt in Rarities`)
            end
        end
        if isInt(pity.epic) and isInt(pity.legendary) and pity.epic > pity.legendary then
            table.insert(errors, `{label}: epic darf nicht größer als legendary sein`)
        end
    end

    -- 10er-Paket: zehn kaufen, elf bekommen.
    local bundle = crates.bundle
    if type(bundle) ~= "table" or bundle.buy ~= 10 or bundle.get ~= 11 then
        table.insert(errors, "Crates: bundle muss buy = 10 und get = 11 sein")
    end
end

-- Gewinne der Kisten (Paket 4.2): eindeutige IDs, bekannte Art, Seltenheit und Kisten, Event-Items
-- nur in der Event-Kiste, Wirkung (effectBp, Paket 4.3) in den Grenzen der Wirtschaft, und jede Seltenheit mit Quote über 0 hat in
-- jeder Kiste mindestens MIN_POOL_ITEMS Items. Ein Item, das in seiner Kiste nie fallen kann
-- (Quote 0 für seine Seltenheit), ist ebenfalls ein Fehler.
local function checkCrateItems(errors: { string }, data: DataSet)
    local items = data.CrateItems
    checkIds(errors, "CrateItems", items)
    if type(items) ~= "table" or not isList(items.list) then
        return
    end
    local crates = data.Crates
    local rarities = data.Rarities
    if type(crates) ~= "table" or type(crates.byId) ~= "table" or not isList(crates.list) then
        return
    end
    if type(rarities) ~= "table" or type(rarities.byId) ~= "table" then
        return
    end

    -- Kisten-ID -> Seltenheit -> Anzahl Items
    local poolSizes: { [string]: { [string]: number } } = {}
    for index, item in items.list do
        local label = `CrateItems "{tostring(item.id or index)}"`
        if CRATE_ITEM_KINDS[item.kind] == nil then
            table.insert(errors, `{label}: kind muss "skin", "companion" oder "toolVariant" sein`)
        end
        if type(item.name) ~= "string" or item.name == "" then
            table.insert(errors, `{label}: name fehlt`)
        end
        if type(item.rarity) ~= "string" or rarities.byId[item.rarity] == nil then
            table.insert(errors, `{label}: unbekannte Seltenheit "{tostring(item.rarity)}"`)
        end
        local maxEffect = if type(data.Economy) == "table" and type(data.Economy.items) == "table" and isInt(data.Economy.items.maxEffectBp)
            then data.Economy.items.maxEffectBp
            else 0
        if not isInt(item.effectBp) or item.effectBp < 0 or item.effectBp > maxEffect then
            table.insert(errors, `{label}: effectBp muss eine ganze Zahl von 0 bis Economy.items.maxEffectBp ({maxEffect}) sein`)
        end
        if item.passOnly ~= nil and type(item.passOnly) ~= "boolean" then
            table.insert(errors, `{label}: passOnly muss true oder false sein`)
        end
        if item.passOnly == true then
            -- Pass-Items (Paket 5.5) stehen in keiner Kiste und kommen nur über den Saison-Pass.
            if type(item.crates) ~= "table" or #item.crates ~= 0 then
                table.insert(errors, `{label}: ein Pass-Item steht in keiner Kiste (crates = \{\})`)
            end
            continue
        end
        if type(item.crates) ~= "table" or #item.crates == 0 then
            table.insert(errors, `{label}: crates muss mindestens eine Kiste nennen`)
            continue
        end
        local seen: { [string]: boolean } = {}
        local exclusive = false
        for _, crateId in item.crates do
            local crate = if type(crateId) == "string" then crates.byId[crateId] else nil
            if crate == nil then
                table.insert(errors, `{label}: unbekannte Kiste "{tostring(crateId)}"`)
                continue
            end
            if seen[crateId] then
                table.insert(errors, `{label}: Kiste "{crateId}" steht doppelt in crates`)
                continue
            end
            seen[crateId] = true
            if crateId == EXCLUSIVE_CRATE then
                exclusive = true
            end
            local share = if type(crate.odds) == "table" then crate.odds[item.rarity] else nil
            if rarities.byId[item.rarity] ~= nil and (not isFinite(share) or share <= 0) then
                table.insert(errors, `{label}: kann aus Kiste "{crateId}" nie fallen (Quote für "{item.rarity}" ist 0)`)
            end
            local perCrate = poolSizes[crateId]
            if perCrate == nil then
                perCrate = {}
                poolSizes[crateId] = perCrate
            end
            if type(item.rarity) == "string" then
                perCrate[item.rarity] = (perCrate[item.rarity] or 0) + 1
            end
        end
        if exclusive and #item.crates > 1 then
            table.insert(errors, `{label}: Items der Event-Kiste dürfen nur in "{EXCLUSIVE_CRATE}" stehen`)
        end
    end

    for _, crate in crates.list do
        if type(crate.odds) ~= "table" then
            continue
        end
        for rarityId, share in crate.odds do
            if isFinite(share) and share > 0 then
                local size = (poolSizes[crate.id] or {})[rarityId] or 0
                if size < MIN_POOL_ITEMS then
                    table.insert(
                        errors,
                        `CrateItems: Kiste "{tostring(crate.id)}" hat keine Items der Seltenheit "{tostring(rarityId)}" (Quote {share}, mindestens {MIN_POOL_ITEMS})`
                    )
                end
            end
        end
    end
end

local ITEM_LOOK_SHAPES: { [string]: boolean } = { Ball = true, Block = true }
local COMPANION_SIZE_MIN = 0.8
local COMPANION_SIZE_MAX = 2.2

local function isHexColor(value: any): boolean
    return type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

-- Kisten-Items mit Wirkung (Paket 4.3): die Sterne-Regeln in Economy.items und ein Aussehen
-- (Data/ItemLooks) für jedes Item, mit gleicher Art, gültigen Farben und bei Begleitern Form und Größe.
local function checkItems(errors: { string }, data: DataSet)
    local economy = data.Economy
    local cfg = if type(economy) == "table" then economy.items else nil
    if type(cfg) ~= "table" then
        table.insert(errors, "Economy.items: Tabelle fehlt")
    else
        if not isInt(cfg.maxStars) or cfg.maxStars < 2 or cfg.maxStars > 10 then
            table.insert(errors, "Economy.items.maxStars muss eine ganze Zahl von 2 bis 10 sein")
        end
        if not isInt(cfg.starBonusBp) or cfg.starBonusBp < 0 or cfg.starBonusBp > 10000 then
            table.insert(errors, "Economy.items.starBonusBp muss eine ganze Zahl von 0 bis 10000 sein")
        end
        if not isInt(cfg.maxEffectBp) or cfg.maxEffectBp < 1 or cfg.maxEffectBp > 10000 then
            table.insert(errors, "Economy.items.maxEffectBp muss eine ganze Zahl von 1 bis 10000 sein")
        end
        if not isInt(cfg.maxTotalBonusBp) or cfg.maxTotalBonusBp < 1 or cfg.maxTotalBonusBp > 100000 then
            table.insert(errors, "Economy.items.maxTotalBonusBp muss eine ganze Zahl von 1 bis 100000 sein")
        elseif
            isInt(cfg.maxStars)
            and isInt(cfg.starBonusBp)
            and isInt(cfg.maxEffectBp)
            and 3 * math.floor(cfg.maxEffectBp * (10000 + (cfg.maxStars - 1) * cfg.starBonusBp) / 10000) > cfg.maxTotalBonusBp
        then
            table.insert(errors, "Economy.items: drei Items mit höchstem Wert und höchstem Stern überschreiten maxTotalBonusBp")
        end
        if not isList(cfg.copiesToMerge) then
            table.insert(errors, "Economy.items.copiesToMerge muss eine Liste sein")
        else
            if isInt(cfg.maxStars) and #cfg.copiesToMerge ~= cfg.maxStars - 1 then
                table.insert(errors, "Economy.items.copiesToMerge braucht genau maxStars - 1 Einträge")
            end
            for index, copies in cfg.copiesToMerge do
                if not isInt(copies) or copies < 1 then
                    table.insert(errors, `Economy.items.copiesToMerge[{index}] muss eine ganze Zahl ab 1 sein`)
                end
            end
        end
    end

    local items = data.CrateItems
    local looks = data.ItemLooks
    if type(looks) ~= "table" or not isList(looks.list) or type(looks.byId) ~= "table" then
        table.insert(errors, "ItemLooks: list und byId fehlen")
        return
    end
    checkIds(errors, "ItemLooks", looks)
    local itemKinds: { [string]: string } = {}
    if type(items) == "table" and isList(items.list) then
        for _, item in items.list do
            if type(item.id) == "string" then
                itemKinds[item.id] = item.kind
            end
        end
    end
    local seenLooks: { [string]: boolean } = {}
    for index, look in looks.list do
        local label = `ItemLooks "{tostring(look.id or index)}"`
        local kind = if type(look.id) == "string" then itemKinds[look.id] else nil
        if kind == nil then
            table.insert(errors, `{label}: kein Item mit dieser ID in CrateItems`)
        elseif look.kind ~= kind then
            table.insert(errors, `{label}: kind "{tostring(look.kind)}" passt nicht zum Item ("{kind}")`)
        end
        if type(look.id) == "string" then
            seenLooks[look.id] = true
        end
        if not isHexColor(look.colorHex) or not isHexColor(look.accentHex) then
            table.insert(errors, `{label}: colorHex und accentHex müssen "#RRGGBB" sein`)
        end
        if type(look.material) ~= "string" or look.material == "" then
            table.insert(errors, `{label}: material fehlt`)
        end
        if look.kind == "companion" then
            if type(look.shape) ~= "string" or not ITEM_LOOK_SHAPES[look.shape] then
                table.insert(errors, `{label}: shape muss "Ball" oder "Block" sein`)
            end
            if not isFinite(look.size) or look.size < COMPANION_SIZE_MIN or look.size > COMPANION_SIZE_MAX then
                table.insert(errors, `{label}: size muss zwischen {COMPANION_SIZE_MIN} und {COMPANION_SIZE_MAX} liegen`)
            end
        end
    end
    for itemId in itemKinds do
        if not seenLooks[itemId] then
            table.insert(errors, `ItemLooks: Item "{itemId}" hat kein Aussehen`)
        end
    end
end

local function checkTools(errors: { string }, data: DataSet)
    local tools = data.Tools
    checkIds(errors, "Tools", tools)
    if type(tools) ~= "table" or not isList(tools.list) then
        return
    end
    local tree = data.UpgradeTree
    local lastSand, lastCost = 0, -1
    for index, tool in tools.list do
        local label = `Tools "{tostring(tool.id)}"`
        if tool.tier ~= index then
            table.insert(errors, `{label}: tier muss {index} sein`)
        end
        if not isFinite(tool.sandPerSecond) or tool.sandPerSecond <= lastSand then
            table.insert(errors, `{label}: sandPerSecond muss streng steigen`)
        else
            lastSand = tool.sandPerSecond
        end
        if not isFinite(tool.cost) or tool.cost <= lastCost then
            table.insert(errors, `{label}: cost muss streng steigen`)
        else
            lastCost = tool.cost
        end
        if index == 1 and tool.cost ~= 0 then
            table.insert(errors, `{label}: die Hand muss 0 Münzen kosten`)
        end
        if index == 1 then
            -- Die Hand ist die Startausrüstung und hat keinen Knoten.
            if tool.nodeId ~= "start" then
                table.insert(errors, `{label}: nodeId der Hand muss "start" sein`)
            end
        else
            local node = type(tree) == "table" and type(tree.byId) == "table" and tree.byId[tool.nodeId]
            if not node then
                table.insert(errors, `{label}: nodeId "{tostring(tool.nodeId)}" fehlt in UpgradeTree`)
            else
                if node.cost ~= tool.cost then
                    table.insert(errors, `{label}: Knoten-Preis weicht vom Werkzeug-Preis ab`)
                end
                if type(node.effect) ~= "table" or node.effect.toolId ~= tool.id then
                    table.insert(errors, `{label}: Knoten-Effekt verweist nicht auf das Werkzeug`)
                end
            end
        end
    end
end

local function checkSandTypes(errors: { string }, data: DataSet)
    local sandTypes = data.SandTypes
    checkIds(errors, "SandTypes", sandTypes)
    if type(sandTypes) ~= "table" or not isList(sandTypes.list) then
        return
    end
    local last = 0
    for _, sandType in sandTypes.list do
        checkHex(errors, "SandTypes", sandType.id, sandType.colorHex)
        if not isFinite(sandType.priceFactor) or sandType.priceFactor <= last then
            table.insert(errors, `SandTypes "{tostring(sandType.id)}": priceFactor muss steigen`)
        else
            last = sandType.priceFactor
        end
    end
end

local function checkZones(errors: { string }, data: DataSet)
    local zones = data.Zones
    checkIds(errors, "Zones", zones)
    if type(zones) ~= "table" or not isList(zones.list) then
        return
    end
    local tree = data.UpgradeTree
    local sandTypes = data.SandTypes
    local hasStart = false
    for _, zone in zones.list do
        local label = `Zones "{tostring(zone.id)}"`
        if type(sandTypes) ~= "table" or type(sandTypes.byId) ~= "table" or sandTypes.byId[zone.sandTypeId] == nil then
            table.insert(errors, `{label}: unbekannte Sandsorte "{tostring(zone.sandTypeId)}"`)
        end
        if zone.requires == "start" then
            hasStart = true
        elseif type(zone.requires) ~= "string" then
            table.insert(errors, `{label}: requires muss "start" oder eine Knoten-ID sein`)
        elseif type(tree) ~= "table" or type(tree.byId) ~= "table" or tree.byId[zone.requires] == nil then
            table.insert(errors, `{label}: Knoten "{zone.requires}" fehlt in UpgradeTree`)
        else
            -- Der Sandsturm (Paket 2.7) setzt die Zonen zurück und vergibt nur seine eigenen Knoten.
            -- Verlangt eine Zone einen vergebenen Knoten, ist sie nach dem Reset nie mehr zu öffnen,
            -- wenn kein Sturm sie vergibt; sie darf also nur einen kaufbaren Knoten verlangen.
            local required = tree.byId[zone.requires]
            if type(required) == "table" and (required.granted == true or (type(required.effect) == "table" and required.effect.kind == "grantedBySandstorm")) then
                table.insert(errors, `{label}: verlangt den vergebenen Knoten "{zone.requires}", eine Zone braucht einen kaufbaren Knoten`)
            end
        end
    end
    if not hasStart then
        table.insert(errors, "Zones: keine Startzone (requires = \"start\")")
    end
    -- Der Sandsturm und Zones.resolve setzen den Spieler auf die erste Zone der Liste zurück.
    if isList(zones.list) and type(zones.list[1]) == "table" and zones.list[1].requires ~= "start" then
        table.insert(errors, "Zones: die erste Zone der Liste muss die Startzone sein (requires = \"start\")")
    end
    -- Event-Zonen (Paket 5.5): eigene Liste, nicht Teil von `list`. Jede gehört zu genau einer Saison,
    -- hat eine bekannte Sandsorte und verlangt einen kaufbaren Knoten (nie "start", nie einen vergebenen).
    local events = zones.events
    if not isList(events) or type(zones.eventById) ~= "table" then
        table.insert(errors, "Zones: events und eventById fehlen")
        return
    end
    local seasons = data.Seasons
    local seasonRows = if type(seasons) == "table" and isList(seasons.list) then seasons.list else {}
    for index, zone in events do
        local label = `Zones.events[{index}]`
        if type(zone) ~= "table" or type(zone.id) ~= "string" or zone.id == "" then
            table.insert(errors, `{label}: id muss ein nicht leerer Text sein`)
            continue
        end
        label = `Zones.events "{zone.id}"`
        if zones.eventById[zone.id] ~= zone or zones.byId[zone.id] ~= zone then
            table.insert(errors, `{label}: byId oder eventById passt nicht`)
        end
        for _, fixed in zones.list do
            if type(fixed) == "table" and fixed.id == zone.id then
                table.insert(errors, `{label}: id steht auch in Zones.list`)
            end
        end
        if type(zone.name) ~= "string" or zone.name == "" then
            table.insert(errors, `{label}: name muss ein nicht leerer Text sein`)
        end
        if type(sandTypes) ~= "table" or type(sandTypes.byId) ~= "table" or sandTypes.byId[zone.sandTypeId] == nil then
            table.insert(errors, `{label}: unbekannte Sandsorte "{tostring(zone.sandTypeId)}"`)
        end
        if zone.requires == "start" or type(zone.requires) ~= "string" then
            table.insert(errors, `{label}: requires muss eine Knoten-ID sein (nicht "start")`)
        elseif type(tree) ~= "table" or type(tree.byId) ~= "table" or tree.byId[zone.requires] == nil then
            table.insert(errors, `{label}: Knoten "{zone.requires}" fehlt in UpgradeTree`)
        else
            local required = tree.byId[zone.requires]
            if type(required) == "table" and (required.granted == true or (type(required.effect) == "table" and required.effect.kind == "grantedBySandstorm")) then
                table.insert(errors, `{label}: verlangt den vergebenen Knoten "{zone.requires}", eine Zone braucht einen kaufbaren Knoten`)
            end
        end
        local owners = 0
        for _, season in seasonRows do
            if type(season) == "table" and season.zoneId == zone.id then
                owners += 1
                if zone.seasonId ~= season.id then
                    table.insert(errors, `{label}: seasonId "{tostring(zone.seasonId)}" passt nicht zur Saison "{tostring(season.id)}"`)
                end
            end
        end
        if owners ~= 1 then
            table.insert(errors, `{label}: muss die zoneId von genau einer Saison in Seasons sein (gefunden: {owners})`)
        end
    end
end

local function checkUpgradeTree(errors: { string }, data: DataSet)
    local tree = data.UpgradeTree
    checkIds(errors, "UpgradeTree", tree)
    if type(tree) ~= "table" or not isList(tree.list) then
        return
    end
    for _, node in tree.list do
        local label = `UpgradeTree "{tostring(node.id)}"`
        if BRANCHES[node.branch] == nil then
            table.insert(errors, `{label}: unbekannter Ast "{tostring(node.branch)}"`)
        end
        if not isInt(node.cost) or node.cost < 0 then
            table.insert(errors, `{label}: cost muss eine ganze Zahl ab 0 sein`)
        end
        if type(node.effect) == "table" and (node.effect.kind == "grantedBySandstorm") ~= (node.granted == true) then
            table.insert(errors, `{label}: "grantedBySandstorm" und granted = true gehören zusammen`)
        end
        if node.granted ~= true and isFinite(node.cost) and node.cost <= 0 then
            table.insert(errors, `{label}: ein kaufbarer Knoten braucht einen Preis über 0`)
        end
        if type(node.name) ~= "string" or node.name == "" then
            table.insert(errors, `{label}: name fehlt`)
        end
        if type(node.description) ~= "string" or node.description == "" then
            table.insert(errors, `{label}: description fehlt`)
        end
        if type(node.effect) ~= "table" then
            table.insert(errors, `{label}: effect fehlt`)
        elseif EFFECT_KINDS[node.effect.kind] == nil then
            table.insert(errors, `{label}: unbekannte Wirkung "{tostring(node.effect.kind)}"`)
        elseif BP_EFFECTS[node.effect.kind] and (not isInt(node.effect.bp) or node.effect.bp <= 0) then
            table.insert(errors, `{label}: {node.effect.kind} braucht bp als ganze Zahl über 0`)
        elseif node.effect.kind == "setTank" and (not isInt(node.effect.capacity) or node.effect.capacity <= 0) then
            table.insert(errors, `{label}: setTank braucht capacity als ganze Zahl über 0`)
        end
        if type(node.effect) == "table" and BRANCH_OF_EFFECT[node.effect.kind] ~= nil and BRANCH_OF_EFFECT[node.effect.kind] ~= node.branch then
            table.insert(errors, `{label}: Wirkung "{node.effect.kind}" gehört in den Ast "{BRANCH_OF_EFFECT[node.effect.kind]}"`)
        end
        if node.milestone ~= nil and (not isInt(node.milestone) or node.milestone < 1) then
            table.insert(errors, `{label}: milestone muss eine ganze Zahl ab 1 sein`)
        end
        if type(node.requires) ~= "table" then
            table.insert(errors, `{label}: requires fehlt`)
        else
            for _, required in node.requires do
                if required == node.id then
                    table.insert(errors, `{label}: verlangt sich selbst`)
                elseif tree.byId[required] == nil then
                    table.insert(errors, `{label}: verlangt unbekannten Knoten "{tostring(required)}"`)
                end
            end
        end
    end

    -- Zyklen: von jedem Knoten den requires-Pfaden folgen.
    local function reaches(startId: string, currentId: string, depth: number): boolean
        if depth > #tree.list then
            return true
        end
        local node = tree.byId[currentId]
        if node == nil or type(node.requires) ~= "table" then
            return false
        end
        for _, required in node.requires do
            if required == startId or reaches(startId, required, depth + 1) then
                return true
            end
        end
        return false
    end
    for _, node in tree.list do
        if type(node.id) == "string" and reaches(node.id, node.id, 0) then
            table.insert(errors, `UpgradeTree "{node.id}": Zyklus in requires`)
        end
    end
end

local function checkGemPacks(errors: { string }, data: DataSet)
    local packs = data.GemPacks
    checkIds(errors, "GemPacks", packs)
    if type(packs) ~= "table" or not isList(packs.list) then
        return
    end
    local smallest = packs.list[1]
    if smallest == nil then
        table.insert(errors, "GemPacks: keine Pakete")
        return
    end
    local lastGems, lastRobux = 0, 0
    for _, pack in packs.list do
        local label = `GemPacks "{tostring(pack.id)}"`
        if not isInt(pack.gems) or not isInt(pack.robux) or pack.gems <= 0 or pack.robux <= 0 then
            table.insert(errors, `{label}: gems und robux müssen positive ganze Zahlen sein`)
        else
            if pack.gems <= lastGems or pack.robux <= lastRobux then
                table.insert(errors, `{label}: gems und robux müssen steigen`)
            end
            lastGems, lastRobux = pack.gems, pack.robux
            local ratio = (pack.gems / pack.robux) / (smallest.gems / smallest.robux)
            local bonus = (ratio - 1) * 100
            if
                type(pack.bonusPercentConcept) ~= "number"
                or math.abs(bonus - pack.bonusPercentConcept) > GEM_BONUS_TOLERANCE
            then
                table.insert(
                    errors,
                    `{label}: berechneter Bonus {string.format("%.1f", bonus)} % weicht von bonusPercentConcept {tostring(pack.bonusPercentConcept)} ab`
                )
            end
        end
        if not isInt(pack.productId) or pack.productId < 0 then
            table.insert(errors, `{label}: productId muss eine ganze Zahl ab 0 sein`)
        end
    end
end

local function checkProducts(errors: { string }, data: DataSet)
    local products = data.Products
    checkIds(errors, "Products", products)
    if type(products) ~= "table" or not isList(products.list) then
        return
    end
    for _, product in products.list do
        local label = `Products "{tostring(product.id)}"`
        if PRODUCT_KINDS[product.kind] == nil then
            table.insert(errors, `{label}: unbekannte Art "{tostring(product.kind)}"`)
        end
        if not isInt(product.priceRobux) or product.priceRobux <= 0 then
            table.insert(errors, `{label}: priceRobux muss eine positive ganze Zahl sein`)
        end
        if product.priceRobuxMax ~= nil and (not isInt(product.priceRobuxMax) or product.priceRobuxMax < product.priceRobux) then
            table.insert(errors, `{label}: priceRobuxMax muss >= priceRobux sein`)
        end
        if not isInt(product.productId) or product.productId < 0 then
            table.insert(errors, `{label}: productId muss eine ganze Zahl ab 0 sein`)
        end
    end
end

-- Käufe (Paket 4.1): Grenzen der Kaufabwicklung, Belege mindestens so viele wie Protokolleinträge
-- (jeder protokollierte Kauf steht auch in den Belegen; ist `receipts` kaputt, baut sanitize sie aus
-- dem Protokoll neu auf), und kein Gem-Paket liegt über maxGems.
local function checkPurchases(errors: { string }, data: DataSet)
    local economy = data.Economy
    if type(economy) ~= "table" then
        return -- checkEconomy meldet die fehlende Tabelle
    end
    local cfg = economy.purchases
    if type(cfg) ~= "table" then
        table.insert(errors, "Economy.purchases: Tabelle fehlt")
        return
    end
    for _, limit in PURCHASE_LIMITS do
        local value = cfg[limit.key]
        if not isInt(value) or value < limit.min or value > limit.max then
            table.insert(errors, `Economy.purchases.{limit.key} muss eine ganze Zahl von {limit.min} bis {limit.max} sein`)
        end
    end
    if isInt(cfg.receiptCacheSize) and isInt(cfg.purchaseLogSize) and cfg.receiptCacheSize < cfg.purchaseLogSize then
        table.insert(errors, "Economy.purchases.receiptCacheSize muss mindestens so groß wie purchaseLogSize sein")
    end
    local packs = data.GemPacks
    if isInt(cfg.maxGems) and type(packs) == "table" and isList(packs.list) then
        for _, pack in packs.list do
            if isInt(pack.gems) and pack.gems > cfg.maxGems then
                table.insert(errors, `GemPacks "{tostring(pack.id)}": mehr Gems als Economy.purchases.maxGems`)
            end
        end
    end
end

-- Eine ProductId (außer dem Platzhalter 0) darf nur einmal vorkommen, sonst wüsste ProcessReceipt
-- nicht, welches Produkt gekauft wurde. Developer Products (Gem-Pakete und alle Produkte außer
-- Gamepasses) und Gamepasses haben bei Roblox getrennte Nummernkreise und werden getrennt geprüft.
-- Außerdem darf keine Produkt-ID (`id`) in GemPacks und Products zugleich stehen: Purchases findet
-- Handler und Studio-Käufe über diese ID (doppelte innerhalb einer Tabelle meldet checkIds).
-- Gamepasses und Münz-Boost (Paket 4.4): Jeder Gamepass hat eine bekannte Wirkung (`perk`, siehe
-- Logic/Perks.PERK_IDS), jede Wirkung gehört zu genau einem Gamepass, andere Produkte haben keine.
-- Die Faktoren (2x Münzen, Großer Tank, Münz-Boost) sind endlich und größer als 1. Der Münz-Boost
-- ist ein Developer Product und ein Verbrauchsprodukt (sonst käme er nicht über ProcessReceipt bzw.
-- ließe sich nur einmal kaufen). Ob er einen Handler hat, prüft Shop.AfterStart (missingHandlers).
local function checkPerks(errors: { string }, data: DataSet)
    local products = data.Products
    if type(products) ~= "table" or not isList(products.list) then
        return -- checkProducts meldet die fehlende Tabelle
    end
    local known: { [string]: boolean } = {}
    local count: { [string]: number } = {}
    for _, perk in Perks.PERK_IDS do
        known[perk] = true
        count[perk] = 0
    end
    for _, product in products.list do
        local label = `Products "{tostring(product.id)}"`
        if product.kind == "gamepass" then
            if type(product.perk) ~= "string" or not known[product.perk] then
                table.insert(errors, `{label}: Gamepass ohne bekannte Wirkung (perk "{tostring(product.perk)}")`)
            else
                count[product.perk] += 1
            end
        elseif product.perk ~= nil then
            table.insert(errors, `{label}: perk gibt es nur bei Gamepasses`)
        end
    end
    for _, perk in Perks.PERK_IDS do
        if count[perk] ~= 1 then
            table.insert(errors, `Products: Wirkung "{perk}" muss genau einem Gamepass gehören (gefunden: {count[perk]})`)
        end
    end
    local boost = if type(products.byId) == "table" then products.byId[Perks.COIN_BOOST_PRODUCT_ID] else nil
    if type(boost) ~= "table" then
        table.insert(errors, `Products: "{Perks.COIN_BOOST_PRODUCT_ID}" (Münz-Boost) fehlt`)
    elseif boost.kind ~= "developerProduct" or boost.consumable ~= true then
        table.insert(errors, `Products "{Perks.COIN_BOOST_PRODUCT_ID}": muss ein Developer Product und ein Verbrauchsprodukt sein`)
    end
    local economy = data.Economy
    if type(economy) ~= "table" then
        return -- checkEconomy meldet die fehlende Tabelle
    end
    for _, key in { "doubleCoinsMultiplier", "bigTankMultiplier" } do
        if not isFinite(economy[key]) or economy[key] <= 1 then
            table.insert(errors, `Economy.{key} muss endlich und größer als 1 sein`)
        end
    end
    local coinBoost = economy.coinBoost
    if type(coinBoost) ~= "table" or not isFinite(coinBoost.multiplier) or coinBoost.multiplier <= 1 then
        table.insert(errors, "Economy.coinBoost.multiplier muss endlich und größer als 1 sein")
    end
end

-- Felder einer Angebotszeile (Paket 4.5). Ein weiteres Feld (zum Beispiel eine Kiste oder eine
-- Zufallsliste) ist ein Fehler: Angebote haben nur festen Inhalt, sonst wären sie bezahlte
-- Zufallsitems (Policy ArePaidRandomItemsRestricted, Quotenpflicht).
local OFFER_FIELDS = {
    id = true,
    productId = true,
    trigger = true,
    minRarityId = true,
    windowHours = true,
    gems = true,
    items = true,
    priority = true,
}

-- Angebote (Paket 4.5): eindeutige IDs; jedes Angebot verweist auf ein eigenes bekanntes Produkt
-- (Developer Product, Einmalkauf); bekannter Auslöser und bekannte Seltenheit; Fenster endlich und
-- größer als 0 Stunden; Gems ganze Zahl von 0 bis maxGems; Items sind feste IDs aus CrateItems (keine
-- Kisten-ID, kein Zufall), lückenlose Liste, je Art höchstens eines; das Angebot ist nicht leer;
-- priority ist eine endliche Zahl; keine weiteren Felder.
local function checkOffers(errors: { string }, data: DataSet)
    local offers = data.Offers
    checkIds(errors, "Offers", offers)
    if type(offers) ~= "table" or not isList(offers.list) then
        return
    end
    local products = if type(data.Products) == "table" and type(data.Products.byId) == "table" then data.Products.byId else {}
    local items = if type(data.CrateItems) == "table" and type(data.CrateItems.byId) == "table" then data.CrateItems.byId else {}
    local crates = if type(data.Crates) == "table" and type(data.Crates.byId) == "table" then data.Crates.byId else {}
    local rarities = if type(data.Rarities) == "table" and type(data.Rarities.byId) == "table" then data.Rarities.byId else {}
    local economy = data.Economy
    local maxGems = if type(economy) == "table" and type(economy.purchases) == "table" then economy.purchases.maxGems else nil
    local productUsedBy: { [string]: string } = {}
    for index, offer in offers.list do
        local label = `Offers "{tostring(if type(offer) == "table" then offer.id else index)}"`
        if type(offer) ~= "table" then
            table.insert(errors, `{label}: Eintrag ist keine Tabelle`)
            continue
        end
        for field in offer do
            if not OFFER_FIELDS[field] then
                table.insert(errors, `{label}: unbekanntes Feld "{tostring(field)}" (Angebote haben nur festen Inhalt, kein Zufall)`)
            end
        end
        local product = if type(offer.productId) == "string" then products[offer.productId] else nil
        if type(product) ~= "table" then
            table.insert(errors, `{label}: productId "{tostring(offer.productId)}" steht nicht in Products`)
        else
            if product.kind ~= "developerProduct" or product.oneTime ~= true then
                table.insert(errors, `{label}: Produkt "{offer.productId}" muss ein Developer Product mit oneTime = true sein`)
            end
            local other = productUsedBy[offer.productId]
            if other ~= nil then
                table.insert(errors, `{label}: Produkt "{offer.productId}" gehört schon zum Angebot "{other}"`)
            else
                productUsedBy[offer.productId] = tostring(offer.id)
            end
        end
        if type(offer.trigger) ~= "string" or not Offers.TRIGGERS[offer.trigger] then
            table.insert(errors, `{label}: unbekannter Auslöser "{tostring(offer.trigger)}"`)
        end
        if type(offer.minRarityId) ~= "string" or rarities[offer.minRarityId] == nil then
            table.insert(errors, `{label}: minRarityId "{tostring(offer.minRarityId)}" steht nicht in Rarities`)
        end
        if not isFinite(offer.windowHours) or offer.windowHours <= 0 then
            table.insert(errors, `{label}: windowHours muss endlich und größer als 0 sein`)
        end
        if not isInt(offer.gems) or offer.gems < 0 or (isInt(maxGems) and offer.gems > maxGems) then
            table.insert(errors, `{label}: gems muss eine ganze Zahl von 0 bis Economy.purchases.maxGems sein`)
        end
        if not isFinite(offer.priority) then
            table.insert(errors, `{label}: priority muss eine endliche Zahl sein`)
        end
        local itemList = offer.items
        if type(itemList) ~= "table" then
            table.insert(errors, `{label}: items muss eine Liste sein`)
            continue
        end
        local count = 0
        for _ in itemList do
            count += 1
        end
        if count ~= #itemList then
            table.insert(errors, `{label}: items muss eine lückenlose Liste sein`)
        end
        local kinds: { [string]: string } = {}
        for _, itemId in itemList do
            local item = if type(itemId) == "string" then items[itemId] else nil
            if type(itemId) == "string" and crates[itemId] ~= nil then
                table.insert(errors, `{label}: "{itemId}" ist eine Kiste (Zufall), erlaubt sind nur feste Items aus CrateItems`)
            elseif type(item) ~= "table" then
                table.insert(errors, `{label}: Item "{tostring(itemId)}" steht nicht in CrateItems`)
            elseif type(item.kind) ~= "string" or Equipment.INVENTORY_FIELDS[item.kind] == nil then
                table.insert(errors, `{label}: Item "{itemId}" hat keine bekannte Art`)
            elseif item.passOnly == true then
                table.insert(errors, `{label}: "{itemId}" ist ein Pass-Item und nur über den Saison-Pass erhältlich`)
            elseif kinds[item.kind] ~= nil then
                table.insert(errors, `{label}: höchstens ein Item je Art ("{kinds[item.kind]}" und "{itemId}" sind beide {item.kind})`)
            else
                kinds[item.kind] = itemId
            end
        end
        if count == 0 and offer.gems == 0 then
            table.insert(errors, `{label}: Angebot ohne Inhalt (keine Gems, keine Items)`)
        end
    end
end

local function checkProductIds(errors: { string }, data: DataSet)
    local packIds: { [string]: boolean } = {}
    local packList = data.GemPacks
    local productList = data.Products
    if type(packList) == "table" and isList(packList.list) and type(productList) == "table" and isList(productList.list) then
        for _, pack in packList.list do
            if type(pack.id) == "string" then
                packIds[pack.id] = true
            end
        end
        for _, product in productList.list do
            if type(product.id) == "string" and packIds[product.id] then
                table.insert(errors, `Produkt-ID "{product.id}" steht in GemPacks und in Products`)
            end
        end
    end
    local seen: { [string]: string } = {} -- "Nummernkreis:productId" -> erster Eintrag
    local function add(space: string, productId: any, label: string)
        if not isInt(productId) or productId == 0 then
            return -- Platzhalter oder schon von checkGemPacks/checkProducts gemeldet
        end
        local key = `{space}:{productId}`
        local first = seen[key]
        if first ~= nil then
            table.insert(errors, `productId {productId} ist doppelt: {first} und {label}`)
        else
            seen[key] = label
        end
    end
    local packs = data.GemPacks
    if type(packs) == "table" and isList(packs.list) then
        for _, pack in packs.list do
            add("product", pack.productId, `GemPacks "{tostring(pack.id)}"`)
        end
    end
    local products = data.Products
    if type(products) == "table" and isList(products.list) then
        for _, product in products.list do
            local space = if product.kind == "gamepass" then "gamepass" else "product"
            add(space, product.productId, `Products "{tostring(product.id)}"`)
        end
    end
end

local function checkFinds(errors: { string }, data: DataSet)
    local finds = data.Finds
    local zones = data.Zones
    if type(finds) ~= "table" or not isList(finds.sets) or not isList(finds.list) then
        table.insert(errors, "Finds: sets oder list fehlt")
        return
    end

    -- Sets: eindeutige IDs, bekannte Zone, 6 Sets zu je 5 pro Zone.
    local seen: { [string]: boolean } = {}
    local perZone: { [string]: number } = {}
    for _, findSet in finds.sets do
        if seen[findSet.id] then
            table.insert(errors, `Finds: Set-ID "{tostring(findSet.id)}" ist doppelt`)
        end
        seen[findSet.id] = true
        if type(zones) ~= "table" or zones.byId[findSet.zoneId] == nil then
            table.insert(errors, `Finds: Set "{tostring(findSet.id)}" verweist auf unbekannte Zone`)
        end
        if findSet.size ~= finds.FINDS_PER_SET then
            table.insert(errors, `Finds: Set "{tostring(findSet.id)}" hat nicht {finds.FINDS_PER_SET} Slots`)
        end
        perZone[findSet.zoneId] = (perZone[findSet.zoneId] or 0) + 1
    end
    if type(zones) == "table" and isList(zones.list) then
        for _, zone in zones.list do
            if perZone[zone.id] ~= finds.SETS_PER_ZONE then
                table.insert(errors, `Finds: Zone "{zone.id}" braucht {finds.SETS_PER_ZONE} Sets`)
            end
        end
    end

    -- Fundstücke (sobald vorhanden): eindeutige IDs, bekannte Seltenheit und Sets.
    local ids: { [string]: boolean } = {}
    local perSet: { [string]: number } = {}
    for _, find in finds.list do
        if type(find.id) ~= "string" or type(find.setId) ~= "string" then
            continue -- checkCollection meldet fehlende Felder, hier nur nicht werfen
        end
        if ids[find.id] then
            table.insert(errors, `Finds: id "{tostring(find.id)}" ist doppelt`)
        end
        ids[find.id] = true
        if type(data.Rarities) ~= "table" or data.Rarities.byId[find.rarityId] == nil then
            table.insert(errors, `Finds "{tostring(find.id)}": unbekannte Seltenheit`)
        end
        local findSet = finds.setsById[find.setId]
        if findSet == nil then
            table.insert(errors, `Finds "{tostring(find.id)}": unbekanntes Set`)
        else
            if findSet.zoneId ~= find.zoneId then
                table.insert(errors, `Finds "{tostring(find.id)}": Zone passt nicht zum Set`)
            end
            perSet[find.setId] = (perSet[find.setId] or 0) + 1
            if perSet[find.setId] > findSet.size then
                table.insert(errors, `Finds: Set "{find.setId}" hat zu viele Fundstücke`)
            end
        end
    end
end

-- Sandsturm (Paket 2.7): Economy.sandstorm. Die Grenzen sind Schutz gegen Tippfehler, keine Balance.
local MAX_CRYSTAL_CAP = 10_000_000
local MAX_CRYSTAL_BONUS_BP = 1_000_000_000
local MAX_CRYSTAL_SCALE = 1000

local function checkSandstorm(errors: { string }, data: DataSet)
    local economy = data.Economy
    if type(economy) ~= "table" then
        return -- checkEconomy meldet die fehlende Tabelle
    end
    local cfg = economy.sandstorm
    if type(cfg) ~= "table" then
        table.insert(errors, "Economy.sandstorm: Tabelle fehlt")
        return
    end
    local tree = data.UpgradeTree
    local node = if type(cfg.requiresNode) == "string" and type(tree) == "table" and type(tree.byId) == "table" then tree.byId[cfg.requiresNode] else nil
    if node == nil then
        table.insert(errors, "Economy.sandstorm.requiresNode: Knoten fehlt in UpgradeTree")
    elseif node.granted == true or (type(node.effect) == "table" and node.effect.kind == "grantedBySandstorm") then
        table.insert(errors, "Economy.sandstorm.requiresNode: der Knoten darf nicht vom Sturm vergeben werden")
    end
    if not isFinite(cfg.crystalUnit) or cfg.crystalUnit <= 0 then
        table.insert(errors, "Economy.sandstorm.crystalUnit muss eine Zahl über 0 sein")
    end
    if not isFinite(cfg.crystalExponent) or cfg.crystalExponent <= 0 or cfg.crystalExponent > 1 then
        table.insert(errors, "Economy.sandstorm.crystalExponent muss in (0, 1] liegen")
    end
    if not isFinite(cfg.crystalScale) or cfg.crystalScale <= 0 or cfg.crystalScale > MAX_CRYSTAL_SCALE then
        table.insert(errors, `Economy.sandstorm.crystalScale muss in (0, {MAX_CRYSTAL_SCALE}] liegen`)
    end
    if not isInt(cfg.maxCrystals) or cfg.maxCrystals < 1 or cfg.maxCrystals > MAX_CRYSTAL_CAP then
        table.insert(errors, `Economy.sandstorm.maxCrystals muss eine ganze Zahl von 1 bis {MAX_CRYSTAL_CAP} sein`)
    elseif isInt(economy.windCrystalBonusBp) and cfg.maxCrystals * economy.windCrystalBonusBp > MAX_CRYSTAL_BONUS_BP then
        table.insert(errors, "Economy.sandstorm: maxCrystals mal windCrystalBonusBp ergibt einen unsinnig hohen Bonus")
    end
    if not isInt(cfg.minCrystals) or cfg.minCrystals < 1 or (isInt(cfg.maxCrystals) and cfg.minCrystals > cfg.maxCrystals) then
        table.insert(errors, "Economy.sandstorm.minCrystals muss eine ganze Zahl ab 1 und höchstens maxCrystals sein")
    end
end

local function checkEconomy(errors: { string }, data: DataSet)
    local economy = data.Economy
    if type(economy) ~= "table" then
        table.insert(errors, "Economy: Tabelle fehlt")
        return
    end
    for _, key in { "windCrystalBonusBp", "friendBonusPerFriendBp", "friendBonusMaxBp" } do
        if not isInt(economy[key]) or economy[key] < 0 then
            table.insert(errors, `Economy.{key} muss eine ganze Zahl ab 0 sein`)
        end
    end
    if isInt(economy.friendBonusPerFriendBp) and isInt(economy.friendBonusMaxBp) and economy.friendBonusMaxBp < economy.friendBonusPerFriendBp then
        table.insert(errors, "Economy: friendBonusMaxBp muss >= friendBonusPerFriendBp sein")
    end
    local offline = economy.offline
    if type(offline) ~= "table" or not isFinite(offline.baseHours) or not isFinite(offline.autoDigHours) then
        table.insert(errors, "Economy.offline: baseHours und autoDigHours fehlen")
    else
        if offline.baseHours <= 0 or offline.autoDigHours <= offline.baseHours then
            table.insert(errors, "Economy.offline: autoDigHours muss größer als baseHours sein")
        end
        if offline.autoDigHours > 48 then
            table.insert(errors, "Economy.offline: autoDigHours darf höchstens 48 sein (Tippfehler?)")
        end
        if not isFinite(offline.rateFactor) or offline.rateFactor <= 0 or offline.rateFactor > 1 then
            table.insert(errors, "Economy.offline: rateFactor muss größer als 0 und höchstens 1 sein")
        end
        if not isFinite(offline.minSeconds) or offline.minSeconds < 0 or offline.minSeconds >= offline.baseHours * 3600 then
            table.insert(errors, "Economy.offline: minSeconds muss ab 0 und kleiner als die Grundgrenze sein")
        end
    end
    local boost = economy.coinBoost
    if type(boost) ~= "table" or not isFinite(boost.durationSeconds) or boost.durationSeconds <= 0 or not isFinite(boost.multiplier) or boost.multiplier < 1 then
        table.insert(errors, "Economy.coinBoost: durationSeconds und multiplier ungültig")
    end
    local target = economy.targetSeconds
    if type(target) ~= "table" or not isFinite(target.firstUpgrade) or not isFinite(target.shovel) or target.firstUpgrade <= 0 or target.shovel <= target.firstUpgrade then
        table.insert(errors, "Economy.targetSeconds: firstUpgrade und shovel ungültig")
    end
    -- Balance-Werte (docs/balance/phase0_startwerte.md) müssen gesetzt und positiv sein.
    for _, key in { "baseCoinsPerSand", "startTankCapacity" } do
        if not isFinite(economy[key]) or economy[key] <= 0 then
            table.insert(errors, `Economy.{key} muss gesetzt und größer als 0 sein`)
        end
    end
    local collecting = economy.collecting
    if type(collecting) ~= "table" or not isFinite(collecting.holdRefreshSeconds) or not isFinite(collecting.holdTimeoutSeconds) or collecting.holdRefreshSeconds <= 0 or collecting.holdTimeoutSeconds <= collecting.holdRefreshSeconds then
        table.insert(errors, "Economy.collecting: holdTimeoutSeconds muss größer als holdRefreshSeconds (> 0) sein")
    end
    -- bigTankMultiplier und doubleCoinsMultiplier prüft checkPerks (Paket 4.4).
    local findOdds = data.FindOdds
    if type(findOdds) ~= "table" then
        table.insert(errors, "FindOdds: Tabelle fehlt")
    else
        for _, key in { "findChancePerSecond", "findBaseValue" } do
            if not isFinite(findOdds[key]) or findOdds[key] <= 0 then
                table.insert(errors, `FindOdds.{key} muss gesetzt und größer als 0 sein`)
            end
        end
        local zones = data.Zones
        local factors = findOdds.zoneFindChanceFactor
        if type(factors) ~= "table" then
            table.insert(errors, "FindOdds.zoneFindChanceFactor fehlt")
        elseif type(zones) == "table" and isList(zones.list) then
            for _, zone in zones.list do
                local factor = factors[zone.id]
                if not isFinite(factor) or factor <= 0 then
                    table.insert(errors, `FindOdds.zoneFindChanceFactor für Zone "{tostring(zone.id)}" fehlt oder ist nicht positiv`)
                end
            end
        end
    end
end

-- Daily Reward und Glücks-Boost (Paket 5.1, Logic/Daily): Tag 1 bis 6 in Reihenfolge, je Art nur ihre
-- Felder (Tippfehler wie "durationSeconds" fallen auf): Boosts mit ganzen Sekunden über 0, Gems ganze
-- Zahl über 0 und höchstens maxGems; Tag 7 ist die Eisenkiste (bekannte Kiste, keine Event-Kiste); der
-- Startknoten steht in UpgradeTree und wird gekauft, nicht vergeben; der Glücks-Faktor ist endlich und
-- größer als 1. Den Ersatzgegenstand für Tag 7 prüft checkDirectShop.
local function checkDaily(errors: { string }, data: DataSet)
    local economy = data.Economy
    if type(economy) ~= "table" then
        return -- checkEconomy meldet die fehlende Tabelle
    end
    local luckBoost = economy.luckBoost
    if type(luckBoost) ~= "table" or not isFinite(luckBoost.multiplier) or luckBoost.multiplier <= 1 then
        table.insert(errors, "Economy.luckBoost.multiplier muss endlich und größer als 1 sein")
    end
    local daily = economy.daily
    if type(daily) ~= "table" or type(daily.days) ~= "table" or #daily.days ~= 6 then
        table.insert(errors, "Economy.daily: Tag 1 bis 6 fehlen")
        return
    end
    local maxGems = if type(economy.purchases) == "table" and isFinite(economy.purchases.maxGems) then economy.purchases.maxGems else math.huge
    for index, reward in daily.days do
        local label = `Economy.daily.days[{index}]`
        local fields = if type(reward) == "table" then DAILY_FIELDS[reward.kind] else nil
        if fields == nil then
            table.insert(errors, `{label}: unbekannte Art (kind)`)
            continue
        end
        if reward.day ~= index then
            table.insert(errors, `{label}: day muss {index} sein`)
        end
        for key in reward do
            if not fields[key] then
                table.insert(errors, `{label}: Feld "{tostring(key)}" gehört nicht zur Art "{reward.kind}"`)
            end
        end
        if reward.kind == "gems" then
            if not isInt(reward.amount) or reward.amount <= 0 or reward.amount > maxGems then
                table.insert(errors, `{label}: amount muss eine ganze Zahl über 0 und höchstens maxGems sein`)
            end
        elseif not isInt(reward.seconds) or reward.seconds <= 0 then
            table.insert(errors, `{label}: seconds muss eine ganze Zahl über 0 sein`)
        end
    end
    local day7 = daily.day7
    if type(day7) ~= "table" or day7.kind ~= "crate" or day7.day ~= 7 or day7.crateId ~= "iron" then
        table.insert(errors, "Economy.daily: Tag 7 muss die Eisenkiste sein")
    else
        for key in day7 do
            if not DAILY_DAY7_FIELDS[key] then
                table.insert(errors, `Economy.daily.day7: Feld "{tostring(key)}" gehört nicht zu Tag 7`)
            end
        end
        local crates = data.Crates
        local crate = if type(crates) == "table" and type(crates.byId) == "table" then crates.byId[day7.crateId] else nil
        if type(crate) ~= "table" or crate.eventOnly == true then
            table.insert(errors, `Economy.daily.day7: Kiste "{tostring(day7.crateId)}" fehlt in Crates oder ist eine Event-Kiste`)
        end
    end
    local nodeId = daily.startNodeId
    local tree = data.UpgradeTree
    local node = if type(nodeId) == "string" and type(tree) == "table" and type(tree.byId) == "table" then tree.byId[nodeId] else nil
    if type(node) ~= "table" then
        table.insert(errors, `Economy.daily.startNodeId "{tostring(nodeId)}" steht nicht in UpgradeTree`)
    elseif node.granted == true then
        table.insert(errors, `Economy.daily.startNodeId "{nodeId}" wird vergeben, nicht gekauft`)
    end
end

-- Ist das Item nur in Event-Kisten? (Alle seine Kisten sind eventOnly.)
local function isEventOnlyItem(item: any, crates: any): boolean
    if type(item.crates) ~= "table" or #item.crates == 0 or type(crates) ~= "table" or type(crates.byId) ~= "table" then
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

-- Saison-Pass (Paket 5.5): Economy.seasonPass und die Stufen je Saison. Belohnungen sind fest (Gems,
-- Boosts, Pass-Items), nie Kisten oder Zufall.
-- Obergrenze für Boost-Belohnungen im Saison-Pass (Sekunden), gegen Tippfehler: 4 Stunden.
local MAX_BOOST_REWARD_SECONDS = 4 * 3600

local function checkSeasonPass(errors: { string }, data: DataSet)
    local economy = data.Economy
    local config = if type(economy) == "table" then economy.seasonPass else nil
    local maxGems = if type(economy) == "table" and type(economy.purchases) == "table" and isFinite(economy.purchases.maxGems) then economy.purchases.maxGems else math.huge
    if type(config) ~= "table" then
        table.insert(errors, "Economy.seasonPass fehlt")
    else
        if not isFinite(config.secondsPerPoint) or config.secondsPerPoint <= 0 then
            table.insert(errors, "Economy.seasonPass: secondsPerPoint muss endlich und größer als 0 sein")
        end
        if not isInt(config.claimGraceDays) or config.claimGraceDays < 0 or config.claimGraceDays > 30 then
            table.insert(errors, "Economy.seasonPass: claimGraceDays muss eine ganze Zahl von 0 bis 30 sein")
        end
        if not isInt(config.duplicateGems) or config.duplicateGems < 0 or config.duplicateGems > maxGems then
            table.insert(errors, "Economy.seasonPass: duplicateGems muss eine ganze Zahl von 0 bis maxGems sein")
        end
        -- Ersatz-Gems dürfen nie mehr wert sein als der Pass-Preis zum besten Paketkurs bis zu diesem Preis
        -- (sonst wäre ein altes Pass-Produkt ein verstecktes, günstigeres Gem-Paket).
        if isInt(config.duplicateGems) and type(data.Products) == "table" and type(data.GemPacks) == "table" and isList(data.GemPacks.list) then
            local passProduct = data.Products.byId and data.Products.byId.season_pass
            if type(passProduct) == "table" and isFinite(passProduct.priceRobux) then
                local bestRate = 0
                for _, pack in data.GemPacks.list do
                    if type(pack) == "table" and isFinite(pack.gems) and isFinite(pack.robux) and pack.robux > 0 and pack.robux <= passProduct.priceRobux then
                        bestRate = math.max(bestRate, pack.gems / pack.robux)
                    end
                end
                if config.duplicateGems > passProduct.priceRobux * bestRate then
                    table.insert(errors, `Economy.seasonPass: duplicateGems {config.duplicateGems} sind mehr wert als der Pass-Preis ({math.floor(passProduct.priceRobux * bestRate)} Gems zum besten Paketkurs)`)
                end
            end
        end
        if not isFinite(config.premiumGemsMaxPercent) or config.premiumGemsMaxPercent <= 0 or config.premiumGemsMaxPercent > 100 then
            table.insert(errors, "Economy.seasonPass: premiumGemsMaxPercent muss größer als 0 und höchstens 100 sein")
        end
    end
    local passData = data.SeasonPass
    if type(passData) ~= "table" or type(passData.bySeason) ~= "table" then
        table.insert(errors, "SeasonPass: bySeason fehlt")
        return
    end
    local seasons = data.Seasons
    local seasonRows: { [string]: any } = {}
    if type(seasons) == "table" and isList(seasons.list) then
        for _, season in seasons.list do
            if type(season) == "table" and type(season.id) == "string" then
                seasonRows[season.id] = season
            end
        end
    end
    local items = if type(data.CrateItems) == "table" then data.CrateItems.byId else nil
    -- Gem-Gegenwert des Pass-Preises zum schlechtesten Paketkurs (kleinstes Paket), für die Obergrenze
    -- der Premium-Gems.
    local products = if type(data.Products) == "table" then data.Products.byId else nil
    local function passRobuxOf(season: any): number?
        local productId = if type(season) == "table" and type(season.passId) == "string" then season.passId else "season_pass"
        local product = if products ~= nil then products[productId] else nil
        if type(product) == "table" and isFinite(product.priceRobux) then
            return product.priceRobux
        end
        return nil
    end
    local worstRate: number? = nil
    if type(data.GemPacks) == "table" and isList(data.GemPacks.list) then
        for _, pack in data.GemPacks.list do
            if type(pack) == "table" and isFinite(pack.gems) and isFinite(pack.robux) and pack.robux > 0 then
                local rate = pack.gems / pack.robux
                if worstRate == nil or rate < worstRate then
                    worstRate = rate
                end
            end
        end
    end
    -- Jedes Pass-Item kommt in allen Saisons und Spuren höchstens einmal vor (5.5b).
    local passItemUsedAt: { [string]: string } = {}
    for seasonId, row in passData.bySeason do
        local label = `SeasonPass "{tostring(seasonId)}"`
        if type(seasonId) ~= "string" or seasonRows[seasonId] == nil then
            table.insert(errors, `{label}: steht nicht in Seasons`)
            continue
        end
        if type(row) ~= "table" or not isList(row.tiers) or #row.tiers < 1 then
            table.insert(errors, `{label}: tiers braucht mindestens eine Stufe`)
            continue
        end
        -- Lückenlos 1 bis n (5.5b): Bei einer Lücke wären `#tiers`, die letzte Stufe und damit die
        -- Punkte-Obergrenze mehrdeutig, und ClaimSeasonReward fände Stufen hinter der Lücke unzuverlässig.
        local keyCount = 0
        local dense = true
        for key in row.tiers do
            keyCount += 1
            if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
                dense = false
            end
        end
        if not dense or keyCount ~= #row.tiers or row.tiers[keyCount] == nil then
            table.insert(errors, `{label}: tiers muss eine lückenlose Liste sein (Stufe 1 bis n, ohne andere Schlüssel)`)
            continue
        end
        if #row.tiers > SeasonPass.MAX_TIERS then
            -- Die Remote ClaimSeasonReward nimmt nur Stufen 1 bis MAX_TIERS an (RemoteSpec).
            table.insert(errors, `{label}: höchstens {SeasonPass.MAX_TIERS} Stufen (ClaimSeasonReward)`)
        end
        local last = 0
        local premiumGems = 0
        for index, tier in row.tiers do
            local tierLabel = `{label} Stufe {index}`
            if type(tier) ~= "table" then
                table.insert(errors, `{tierLabel}: muss eine Tabelle sein`)
                continue
            end
            if not isInt(tier.points) or tier.points < 1 or tier.points <= last then
                table.insert(errors, `{tierLabel}: points muss eine ganze Zahl ab 1 sein und über der vorigen Stufe liegen`)
            else
                last = tier.points
            end
            for _, track in { "free", "premium" } do
                local reward = tier[track]
                local rewardLabel = `{tierLabel} {track}`
                local allowedFields = if type(reward) == "table" and type(reward.kind) == "string" then PASS_REWARD_FIELDS[reward.kind] else nil
                if allowedFields ~= nil then
                    for field in reward do
                        if not allowedFields[field] then
                            table.insert(errors, `{rewardLabel}: unbekanntes Feld "{tostring(field)}" (nur feste Belohnungen, nie Kisten oder Zufall)`)
                        end
                    end
                end
                if type(reward) ~= "table" then
                    table.insert(errors, `{rewardLabel}: Belohnung fehlt`)
                elseif reward.kind == "gems" then
                    if not isInt(reward.amount) or reward.amount < 1 or reward.amount > maxGems then
                        table.insert(errors, `{rewardLabel}: amount muss eine ganze Zahl von 1 bis maxGems sein`)
                    elseif track == "premium" then
                        premiumGems += reward.amount
                    end
                elseif reward.kind == "coinBoost" or reward.kind == "luck" then
                    if not isInt(reward.seconds) or reward.seconds < 1 or reward.seconds > MAX_BOOST_REWARD_SECONDS then
                        table.insert(errors, `{rewardLabel}: seconds muss eine ganze Zahl von 1 bis {MAX_BOOST_REWARD_SECONDS} sein`)
                    end
                elseif reward.kind == "item" then
                    local item = if items ~= nil and type(reward.itemId) == "string" then items[reward.itemId] else nil
                    if item == nil then
                        table.insert(errors, `{rewardLabel}: unbekanntes Item "{tostring(reward.itemId)}"`)
                    elseif item.passOnly ~= true then
                        table.insert(errors, `{rewardLabel}: Item "{reward.itemId}" ist kein Pass-Item (passOnly)`)
                    elseif passItemUsedAt[reward.itemId] ~= nil then
                        table.insert(errors, `{rewardLabel}: Pass-Item "{reward.itemId}" steht schon bei {passItemUsedAt[reward.itemId]} (jedes Pass-Item nur einmal)`)
                    else
                        passItemUsedAt[reward.itemId] = rewardLabel
                    end
                else
                    table.insert(errors, `{rewardLabel}: unbekannte Art "{tostring(reward.kind)}" (erlaubt: gems, coinBoost, luck, item)`)
                end
            end
        end
        local percent = if type(config) == "table" and isFinite(config.premiumGemsMaxPercent) then config.premiumGemsMaxPercent else nil
        local passRobux = passRobuxOf(seasonRows[seasonId])
        if percent ~= nil then
            if passRobux == nil or worstRate == nil then
                -- Ohne Preis oder Paketkurs wäre die Obergrenze still weggefallen.
                table.insert(errors, `{label}: Obergrenze der Premium-Gems nicht prüfbar (Pass-Produkt mit priceRobux oder GemPacks fehlt)`)
            else
                local limit = percent / 100 * passRobux * worstRate
                if premiumGems > limit then
                    table.insert(errors, `{label}: Premium-Gems {premiumGems} liegen über der Obergrenze {math.floor(limit)} (premiumGemsMaxPercent)`)
                end
            end
        end
        local seasonRow = seasonRows[seasonId]
        if type(seasonRow) == "table" and type(seasonRow.zoneId) ~= "string" then
            table.insert(errors, `{label}: die Saison hat keine zoneId, es gäbe nie Punkte`)
        end
    end
    -- Jede Saison mit passId braucht Stufen.
    for seasonId, season in seasonRows do
        if season.passId ~= nil and passData.bySeason[seasonId] == nil then
            table.insert(errors, `Seasons "{seasonId}": hat eine passId, aber keine Stufen in SeasonPass`)
        end
    end
end

-- Event-Kalender (Paket 5.4): Phasen, Saisonzeilen, Montag-Start, keine Überlappung, Kisten.
local function checkSeasons(errors: { string }, data: DataSet)
    local seasons = data.Seasons
    if type(seasons) ~= "table" or type(seasons.phases) ~= "table" or type(seasons.list) ~= "table" then
        table.insert(errors, "Seasons: phases und list fehlen")
        return
    end
    if #seasons.phases < 1 then
        table.insert(errors, "Seasons.phases: mindestens eine Woche nötig")
    end
    local phaseIds: { [string]: boolean } = {}
    for index, phase in seasons.phases do
        local label = `Seasons.phases[{index}]`
        if type(phase) ~= "table" or type(phase.id) ~= "string" or phase.id == "" then
            table.insert(errors, `{label}: id muss ein nicht leerer Text sein`)
            continue
        end
        if phaseIds[phase.id] then
            table.insert(errors, `{label}: doppelte id "{phase.id}"`)
        end
        phaseIds[phase.id] = true
        if type(phase.name) ~= "string" or phase.name == "" then
            table.insert(errors, `{label}: name muss ein nicht leerer Text sein`)
        end
        if type(phase.crateOpen) ~= "boolean" then
            table.insert(errors, `{label}: crateOpen muss true oder false sein`)
        end
        if type(phase.zoneOpen) ~= "boolean" then
            table.insert(errors, `{label}: zoneOpen muss true oder false sein`)
        end
        if phase.hint ~= nil and (type(phase.hint) ~= "string" or phase.hint == "") then
            table.insert(errors, `{label}: hint muss ein nicht leerer Text sein`)
        end
    end
    local crates = if type(data.Crates) == "table" then data.Crates.byId else nil
    local products = if type(data.Products) == "table" then data.Products.byId else nil
    local length = #seasons.phases * Seasons.WEEK_SECONDS
    local ids: { [string]: boolean } = {}
    local crateUsers: { [string]: string } = {}
    local zoneUsers: { [string]: string } = {}
    local passUsers: { [string]: string } = {}
    local ranges: { { id: string, startAt: number, hasPass: boolean } } = {}
    for index, season in seasons.list do
        local label = `Seasons.list[{index}]`
        if type(season) ~= "table" then
            table.insert(errors, `{label}: muss eine Tabelle sein`)
            continue
        end
        local id = season.id
        if type(id) ~= "string" or id == "" then
            table.insert(errors, `{label}: id muss ein nicht leerer Text sein`)
            id = `#{index}`
        elseif ids[id] then
            table.insert(errors, `{label}: doppelte id "{id}"`)
        end
        ids[id] = true
        label = `Seasons "{id}"`
        if type(season.name) ~= "string" or season.name == "" then
            table.insert(errors, `{label}: name muss ein nicht leerer Text sein`)
        end
        local start = Seasons.parseDate(season.startDate)
        if start == nil then
            table.insert(errors, `{label}: startDate muss ein gültiges Datum JJJJ-MM-TT sein`)
        elseif not Seasons.isMondayStart(start) then
            table.insert(errors, `{label}: startDate {season.startDate} ist kein Montag`)
        else
            table.insert(ranges, { id = id, startAt = start, hasPass = season.passId ~= nil })
        end
        local crate = if type(season.crateId) == "string" and crates ~= nil then crates[season.crateId] else nil
        if crate == nil then
            table.insert(errors, `{label}: crateId "{tostring(season.crateId)}" steht nicht in Crates`)
        else
            if crate.eventOnly ~= true then
                table.insert(errors, `{label}: Kiste "{season.crateId}" ist keine Event-Kiste (eventOnly)`)
            end
            if crateUsers[season.crateId] ~= nil then
                table.insert(errors, `{label}: Kiste "{season.crateId}" gehört schon zu Saison "{crateUsers[season.crateId]}"`)
            end
            crateUsers[season.crateId] = id
        end
        if season.zoneId ~= nil then
            local eventZones = if type(data.Zones) == "table" then data.Zones.eventById else nil
            if type(season.zoneId) ~= "string" or type(eventZones) ~= "table" or eventZones[season.zoneId] == nil then
                table.insert(errors, `{label}: zoneId "{tostring(season.zoneId)}" steht nicht in Zones.events`)
            elseif zoneUsers[season.zoneId] ~= nil then
                table.insert(errors, `{label}: Zone "{season.zoneId}" gehört schon zu Saison "{zoneUsers[season.zoneId]}"`)
            else
                zoneUsers[season.zoneId] = id
            end
        end
        if season.passId ~= nil then
            local product = if type(season.passId) == "string" and products ~= nil then products[season.passId] else nil
            if type(product) ~= "table" then
                table.insert(errors, `{label}: passId "{tostring(season.passId)}" steht nicht in Products`)
            else
                -- Paket 5.5b: Der Pass läuft über ProcessReceipt (Developer Product) und ist je Saison
                -- kaufbar, darum oneTime = false (ein zweiter Kauf derselben Saison gibt Ersatz-Gems).
                if product.kind ~= "developerProduct" or product.oneTime ~= false then
                    table.insert(errors, `{label}: Pass-Produkt "{season.passId}" muss ein Developer Product mit oneTime = false sein`)
                end
                -- Ein Produkt gehört zu höchstens einer Saison, sonst wüsste der Kauf-Handler nicht,
                -- welche Saison bezahlt ist.
                if passUsers[season.passId] ~= nil then
                    table.insert(errors, `{label}: Pass-Produkt "{season.passId}" gehört schon zu Saison "{passUsers[season.passId]}"`)
                else
                    passUsers[season.passId] = id
                end
            end
        end
    end
    table.sort(ranges, function(a, b)
        return a.startAt < b.startAt
    end)
    local passConfig = if type(data.Economy) == "table" then data.Economy.seasonPass else nil
    local graceDays = if type(passConfig) == "table" and isFinite(passConfig.claimGraceDays) then passConfig.claimGraceDays else 0
    local graceSeconds = graceDays * 86400
    for index = 2, #ranges do
        if ranges[index].startAt < ranges[index - 1].startAt + length then
            table.insert(errors, `Seasons "{ranges[index].id}" überlappt "{ranges[index - 1].id}"`)
        elseif ranges[index - 1].hasPass and ranges[index].startAt < ranges[index - 1].startAt + length + graceSeconds then
            -- Paket 5.5b: Die Abholfrist einer Saison mit Pass (und eine späte Zahlung) braucht Platz,
            -- sonst verfielen Belohnungen und Zahlungen mit dem Start der nächsten Saison.
            table.insert(errors, `Seasons "{ranges[index].id}" beginnt vor dem Ende der Abholfrist von "{ranges[index - 1].id}" (claimGraceDays)`)
        end
    end
    -- Jede Event-Kiste braucht eine Saison, sonst ist sie nie öffnbar.
    if crates ~= nil then
        for crateId, crate in crates do
            if type(crate) == "table" and crate.eventOnly == true and crateUsers[crateId] == nil then
                table.insert(errors, `Kiste "{crateId}" ist eine Event-Kiste ohne Saison in Seasons`)
            end
        end
    end
end

-- Direktkauf (Paket 4.6): Kisten für den Preis sind bekannte Gem-Kisten ohne eventOnly (nie Münz-
-- oder Event-Kisten), keine doppelt; gültige Stellen ganze Zahl von 1 bis 4; monotoneFloor Boolean.
-- Jeder Preis lässt sich rechnen und liegt nicht über maxGems (sonst wäre das Item nie kaufbar).
-- Tag 7 der Daily Reward (Paket 5.1): Der Ersatzgegenstand ist ein festes Item aus CrateItems, kein
-- Event-Item.
local function checkDirectShop(errors: { string }, data: DataSet)
    local economy = data.Economy
    if type(economy) ~= "table" then
        return -- checkEconomy meldet die fehlende Tabelle
    end
    local crates = data.Crates
    local items = data.CrateItems
    local daily = economy.daily
    if type(daily) == "table" then
        local itemId = daily.day7FallbackItemId
        local item = if type(itemId) == "string" and type(items) == "table" and type(items.byId) == "table" then items.byId[itemId] else nil
        if item == nil then
            table.insert(errors, `Economy.daily.day7FallbackItemId "{tostring(itemId)}" steht nicht in CrateItems`)
        elseif isEventOnlyItem(item, crates) or item.passOnly == true then
            table.insert(errors, `Economy.daily.day7FallbackItemId "{itemId}" ist ein Event-Item oder Pass-Item`)
        end
    end

    local cfg = economy.directShop
    if type(cfg) ~= "table" then
        table.insert(errors, "Economy.directShop: Tabelle fehlt")
        return
    end
    local valid = true
    local digits = cfg.roundSignificantDigits
    if not isInt(digits) or digits < 1 or digits > 4 then
        table.insert(errors, "Economy.directShop.roundSignificantDigits muss eine ganze Zahl von 1 bis 4 sein")
        valid = false
    end
    if type(cfg.monotoneFloor) ~= "boolean" then
        table.insert(errors, "Economy.directShop.monotoneFloor muss true oder false sein")
        valid = false
    end
    local list = cfg.crates
    if type(list) ~= "table" or #list == 0 then
        table.insert(errors, "Economy.directShop.crates muss mindestens eine Kiste nennen")
        return
    end
    local seen: { [string]: boolean } = {}
    for index, crateId in list do
        local label = `Economy.directShop.crates[{tostring(index)}]`
        local crate = if type(crateId) == "string" and type(crates) == "table" and type(crates.byId) == "table" then crates.byId[crateId] else nil
        if crate == nil then
            table.insert(errors, `{label}: unbekannte Kiste "{tostring(crateId)}"`)
            valid = false
        elseif seen[crateId] then
            table.insert(errors, `{label}: Kiste "{crateId}" steht doppelt`)
            valid = false
        else
            seen[crateId] = true
            if crate.currency ~= "gems" then
                table.insert(errors, `{label}: Kiste "{crateId}" muss in Gems kosten (currency = "gems")`)
                valid = false
            end
            if crate.eventOnly == true then
                table.insert(errors, `{label}: Kiste "{crateId}" ist eine Event-Kiste`)
                valid = false
            end
        end
    end
    if not valid or #errors > 0 then
        return -- Preise nur mit sonst gültigen Daten rechnen
    end
    local maxGems = if type(economy.purchases) == "table" then economy.purchases.maxGems else nil
    local ok, catalog = pcall(DirectShop.catalog, data)
    if not ok then
        table.insert(errors, `Economy.directShop: Preise lassen sich nicht rechnen ({tostring(catalog)})`)
        return
    end
    for _, entry in catalog do
        if not isInt(entry.price) or entry.price <= 0 or (isInt(maxGems) and entry.price > maxGems) then
            table.insert(errors, `Direktkauf "{entry.itemId}": Preis {tostring(entry.price)} ist keine ganze Zahl von 1 bis Economy.purchases.maxGems`)
        end
    end
end

local function checkWorld(errors: { string }, data: DataSet)
    local world = data.World
    local stand = if type(world) == "table" then world.sellStand else nil
    if type(stand) ~= "table" then
        table.insert(errors, "World.sellStand fehlt")
        return
    end
    if type(stand.tag) ~= "string" or stand.tag == "" then
        table.insert(errors, "World.sellStand.tag fehlt")
    end
    local pos = stand.placeholderPosition
    if type(pos) ~= "table" or not isFinite(pos.x) or not isFinite(pos.y) or not isFinite(pos.z) then
        table.insert(errors, "World.sellStand.placeholderPosition braucht x, y und z")
    end
    if not isFinite(stand.rangeStuds) or stand.rangeStuds <= 0 then
        table.insert(errors, "World.sellStand.rangeStuds muss größer als 0 sein")
    end
    local field = world.sandField
    if type(field) ~= "table" or type(field.tag) ~= "string" or field.tag == "" then
        table.insert(errors, "World.sandField.tag fehlt")
    end
    if not isFinite(stand.promptDistanceStuds) or stand.promptDistanceStuds <= 0 or (isFinite(stand.rangeStuds) and stand.promptDistanceStuds > stand.rangeStuds) then
        table.insert(errors, "World.sellStand.promptDistanceStuds muss größer als 0 und höchstens rangeStuds sein")
    end
end

local function positive(errors: { string }, label: string, value: any)
    if not isFinite(value) or value <= 0 then
        table.insert(errors, `{label} muss eine Zahl größer als 0 sein`)
    end
end

local function checkTerrain(errors: { string }, data: DataSet)
    local terrain = data.Terrain
    if type(terrain) ~= "table" then
        table.insert(errors, "Terrain fehlt")
        return
    end
    if terrain.voxelSize ~= 4 then
        table.insert(errors, "Terrain.voxelSize muss 4 sein (Auflösung des Roblox-Terrains)")
    end
    if not isInt(terrain.chunkSize) or terrain.chunkSize <= 0 or terrain.chunkSize % 4 ~= 0 then
        table.insert(errors, "Terrain.chunkSize muss ein Vielfaches von 4 sein")
    end
    if not isList(terrain.diggableMaterials) or #terrain.diggableMaterials == 0 then
        table.insert(errors, "Terrain.diggableMaterials braucht mindestens ein Material")
    else
        for i, name in terrain.diggableMaterials do
            if type(name) ~= "string" or name == "" or name == "Air" then
                table.insert(errors, `Terrain.diggableMaterials[{i}] muss ein Materialname sein (nicht Air)`)
            end
        end
    end
    local dig = terrain.dig
    if type(dig) ~= "table" then
        table.insert(errors, "Terrain.dig fehlt")
    else
        for _, field in { "intervalSeconds", "forwardStuds", "rayUpStuds", "rayLengthStuds", "maxDepthStuds", "surfaceCellStuds" } do
            positive(errors, `Terrain.dig.{field}`, dig[field])
        end
        if type(dig.maxDepthByZone) ~= "table" then
            table.insert(errors, "Terrain.dig.maxDepthByZone fehlt")
        else
            local zoneIds = if type(data.Zones) == "table" and type(data.Zones.byId) == "table" then data.Zones.byId else {}
            for zoneId, depth in dig.maxDepthByZone do
                if zoneIds[zoneId] == nil then
                    table.insert(errors, `Terrain.dig.maxDepthByZone.{tostring(zoneId)}: unbekannte Zone`)
                end
                positive(errors, `Terrain.dig.maxDepthByZone.{tostring(zoneId)}`, depth)
            end
        end
    end
    local holes = terrain.holeByTool
    if type(holes) ~= "table" then
        table.insert(errors, "Terrain.holeByTool fehlt")
    else
        local tools = if type(data.Tools) == "table" and type(data.Tools.list) == "table" then data.Tools.list else {}
        for _, tool in tools do
            if type(tool) == "table" and type(tool.id) == "string" and holes[tool.id] == nil then
                table.insert(errors, `Terrain.holeByTool: Werkzeug {tool.id} hat keine Lochgröße`)
            end
        end
        for toolId, hole in holes do
            local label = `Terrain.holeByTool.{tostring(toolId)}`
            if type(hole) ~= "table" then
                table.insert(errors, `{label} muss eine Tabelle sein`)
            else
                positive(errors, `{label}.radius`, hole.radius)
                positive(errors, `{label}.depth`, hole.depth)
                if isFinite(hole.radius) and isFinite(hole.depth) and hole.depth > hole.radius then
                    table.insert(errors, `{label}.depth darf nicht größer als radius sein`)
                end
            end
        end
        if type(terrain.defaultToolId) ~= "string" or holes[terrain.defaultToolId] == nil then
            table.insert(errors, "Terrain.defaultToolId muss in holeByTool stehen")
        end
    end
    local regrow = terrain.regrow
    if type(regrow) ~= "table" then
        table.insert(errors, "Terrain.regrow fehlt")
    else
        for _, field in { "delaySeconds", "seconds", "blockRadiusStuds" } do
            positive(errors, `Terrain.regrow.{field}`, regrow[field])
        end
        for _, field in { "steps", "maxDirtyChunks", "maxWritesPerUpdate" } do
            if not isInt(regrow[field]) or regrow[field] <= 0 then
                table.insert(errors, `Terrain.regrow.{field} muss eine ganze Zahl größer als 0 sein`)
            end
        end
    end
    local perf = terrain.perf
    if type(perf) ~= "table" then
        table.insert(errors, "Terrain.perf fehlt")
    else
        for _, field in { "warmupSeconds", "windowSeconds", "lowFps", "highFps", "downAfterSeconds", "upAfterSeconds" } do
            positive(errors, `Terrain.perf.{field}`, perf[field])
        end
        if isFinite(perf.lowFps) and isFinite(perf.highFps) and perf.highFps <= perf.lowFps then
            table.insert(errors, "Terrain.perf.highFps muss über lowFps liegen")
        end
        if not isInt(perf.maxSwitches) or perf.maxSwitches < 0 then
            table.insert(errors, "Terrain.perf.maxSwitches muss eine ganze Zahl ab 0 sein")
        end
    end
    local field = terrain.placeholderField
    if type(field) ~= "table" then
        table.insert(errors, "Terrain.placeholderField fehlt")
    else
        if type(field.enabled) ~= "boolean" then
            table.insert(errors, "Terrain.placeholderField.enabled muss true oder false sein")
        end
        local c, sz = field.center, field.size
        if type(c) ~= "table" or not isFinite(c.x) or not isFinite(c.y) or not isFinite(c.z) then
            table.insert(errors, "Terrain.placeholderField.center braucht x, y und z")
        end
        if type(sz) ~= "table" or not isFinite(sz.x) or not isFinite(sz.y) or not isFinite(sz.z) or sz.x <= 0 or sz.y <= 0 or sz.z <= 0 then
            table.insert(errors, "Terrain.placeholderField.size braucht x, y und z größer als 0")
        end
        if type(field.material) ~= "string" or field.material == "" then
            table.insert(errors, "Terrain.placeholderField.material muss ein Materialname sein")
        end
        local sandTypes = if type(data.SandTypes) == "table" then data.SandTypes.byId else nil
        if type(sandTypes) == "table" and sandTypes[field.sandTypeId] == nil then
            table.insert(errors, "Terrain.placeholderField.sandTypeId muss in SandTypes stehen")
        end
    end
end

-- Tank-Knoten sollen entlang der Voraussetzungen steigen: ein Knoten, der einen anderen
-- verlangt, muss einen größeren Tank geben (sonst wäre der Kauf wertlos).
local function checkTankChain(errors: { string }, data: DataSet)
    local tree = data.UpgradeTree
    if type(tree) ~= "table" or type(tree.byId) ~= "table" then
        return
    end
    for _, node in tree.list do
        if type(node.effect) == "table" and node.effect.kind == "setTank" and type(node.requires) == "table" then
            for _, requiredId in node.requires do
                local required = tree.byId[requiredId]
                if
                    required ~= nil
                    and type(required.effect) == "table"
                    and required.effect.kind == "setTank"
                    and isFinite(required.effect.capacity)
                    and isFinite(node.effect.capacity)
                    and node.effect.capacity <= required.effect.capacity
                then
                    table.insert(errors, `UpgradeTree "{node.id}": Tank muss größer sein als bei "{requiredId}"`)
                end
            end
        end
    end
end

-- Zahlen der Baumansicht (Paket 2.2): Spalten, Abstände, Zoomgrenzen, Platzhalter-Looks und die
-- festgenagelten Plätze (`pos`) der Knoten.
local function checkTreeLayout(errors: { string }, data: DataSet)
    local config = data.TreeLayout
    if type(config) ~= "table" then
        table.insert(errors, "TreeLayout fehlt")
        return
    end
    local before = #errors

    local columnValues: { [number]: string } = {}
    if type(config.columns) ~= "table" then
        table.insert(errors, "TreeLayout.columns fehlt")
    else
        for kind, column in config.columns do
            if EFFECT_KINDS[kind] == nil then
                table.insert(errors, `TreeLayout.columns: unbekannte Wirkung "{tostring(kind)}"`)
            elseif not isInt(column) then
                table.insert(errors, `TreeLayout.columns.{kind} muss eine ganze Zahl sein`)
            elseif columnValues[column] ~= nil then
                table.insert(errors, `TreeLayout.columns: {kind} und {columnValues[column]} teilen sich die Spalte {column}`)
            else
                columnValues[column] = kind
            end
        end
        for kind in EFFECT_KINDS do
            if config.columns[kind] == nil then
                table.insert(errors, `TreeLayout.columns: Wirkung "{kind}" hat keine Spalte`)
            end
        end
    end

    if type(config.looks) ~= "table" then
        table.insert(errors, "TreeLayout.looks fehlt")
    else
        for kind in EFFECT_KINDS do
            local look = config.looks[kind]
            local label = `TreeLayout.looks.{kind}`
            if type(look) ~= "table" then
                table.insert(errors, `{label} fehlt`)
            else
                if type(look.glyph) ~= "string" or look.glyph == "" then
                    table.insert(errors, `{label}.glyph muss ein Zeichen sein`)
                end
                local ok = type(look.color) == "table" and #look.color == 3
                if ok then
                    for _, channel in look.color do
                        if not isInt(channel) or channel < 0 or channel > 255 then
                            ok = false
                        end
                    end
                end
                if not ok then
                    table.insert(errors, `{label}.color braucht drei ganze Zahlen von 0 bis 255`)
                end
            end
        end
    end

    for _, field in { "columnSpacing", "rowSpacing", "nodeSize", "minTouchPixels", "tapMaxMovePixels", "tapMaxMovePixelsTouch" } do
        positive(errors, `TreeLayout.{field}`, config[field])
    end
    if not isFinite(config.margin) or config.margin < 0 then
        table.insert(errors, "TreeLayout.margin muss eine Zahl ab 0 sein")
    end
    if isFinite(config.nodeSize) then
        if isFinite(config.columnSpacing) and config.columnSpacing <= config.nodeSize then
            table.insert(errors, "TreeLayout.columnSpacing muss größer als nodeSize sein (Knoten dürfen sich nicht berühren)")
        end
        if isFinite(config.rowSpacing) and config.rowSpacing <= config.nodeSize then
            table.insert(errors, "TreeLayout.rowSpacing muss größer als nodeSize sein (Knoten dürfen sich nicht berühren)")
        end
    end

    if isFinite(config.tapMaxMovePixels) and isFinite(config.tapMaxMovePixelsTouch) and config.tapMaxMovePixelsTouch < config.tapMaxMovePixels then
        table.insert(errors, "TreeLayout.tapMaxMovePixelsTouch darf nicht unter tapMaxMovePixels liegen")
    end

    local zoom = config.zoom
    if type(zoom) ~= "table" then
        table.insert(errors, "TreeLayout.zoom fehlt")
    else
        for _, field in { "min", "max", "start" } do
            positive(errors, `TreeLayout.zoom.{field}`, zoom[field])
        end
        if isFinite(zoom.min) and isFinite(zoom.max) and zoom.max <= zoom.min then
            table.insert(errors, "TreeLayout.zoom.max muss über zoom.min liegen")
        end
        if isFinite(zoom.min) and isFinite(zoom.max) and isFinite(zoom.start) and (zoom.start < zoom.min or zoom.start > zoom.max) then
            table.insert(errors, "TreeLayout.zoom.start muss zwischen min und max liegen")
        end
        positive(errors, "TreeLayout.zoom.startCompact", zoom.startCompact)
        if isFinite(zoom.min) and isFinite(zoom.max) and isFinite(zoom.startCompact) and (zoom.startCompact < zoom.min or zoom.startCompact > zoom.max) then
            table.insert(errors, "TreeLayout.zoom.startCompact muss zwischen min und max liegen")
        end
        for _, field in { "buttonStep", "wheelStep" } do
            if not isFinite(zoom[field]) or zoom[field] <= 1 then
                table.insert(errors, `TreeLayout.zoom.{field} muss über 1 liegen`)
            end
        end
        if isFinite(zoom.min) and isFinite(config.nodeSize) and isFinite(config.minTouchPixels) and config.nodeSize * zoom.min < config.minTouchPixels then
            table.insert(errors, "TreeLayout: nodeSize mal zoom.min liegt unter minTouchPixels (Knoten am Handy zu klein zum Antippen)")
        end
    end

    -- Festgenagelte Plätze und Kollisionen (nur wenn die Zahlen oben stimmen).
    local tree = data.UpgradeTree
    if type(tree) ~= "table" or not isList(tree.list) or type(tree.byId) ~= "table" then
        return
    end
    for _, node in tree.list do
        if node.pos ~= nil then
            local label = `UpgradeTree "{tostring(node.id)}"`
            if type(node.pos) ~= "table" or not isInt(node.pos.column) or not isInt(node.pos.row) or node.pos.row < 1 then
                table.insert(errors, `{label}: pos braucht column (ganze Zahl) und row (ganze Zahl ab 1)`)
            elseif type(config.columns) == "table" and columnValues[node.pos.column] == nil then
                table.insert(errors, `{label}: pos.column {node.pos.column} ist keine Spalte aus TreeLayout.columns`)
            end
        end
    end
    if #errors ~= before then
        return
    end
    local ok, layout = pcall(function()
        return TreeLayout.compute(tree, config)
    end)
    if not ok then
        table.insert(errors, `TreeLayout: Berechnung schlägt fehl ({tostring(layout)})`)
        return
    end
    local taken: { [string]: string } = {}
    for _, node in tree.list do
        local placement = layout.nodes[node.id]
        if placement == nil then
            table.insert(errors, `UpgradeTree "{tostring(node.id)}": kein Platz im Baum`)
        else
            local key = `{placement.column}:{placement.row}`
            if taken[key] ~= nil then
                table.insert(errors, `UpgradeTree "{node.id}": liegt auf demselben Platz wie "{taken[key]}" (Spalte {placement.column}, Reihe {placement.row})`)
            else
                taken[key] = node.id
            end
        end
    end
end

-- Freischalt-Sequenz und ihre Töne (Paket 2.3).
local UNLOCK_VARIANTS = { "normal", "short", "milestone" }
local UNLOCK_REQUIRED_STEPS = { "press", "ring", "reveal", "camera" }
-- Reihenfolge der Schritte: Die Starts dürfen nicht fallen (Eindrücken, Ring, Impuls, Einblenden, Kamera).
local UNLOCK_STEP_ORDER = { "press", "ring", "pulse", "reveal", "camera" }
local SOUND_ID_PATTERN = "^rbxassetid://%d+$"

local function checkUnlockAnimation(errors: { string }, data: DataSet)
    local anim = data.UnlockAnimation
    local sounds = data.TreeSounds
    if type(anim) ~= "table" then
        table.insert(errors, "UnlockAnimation fehlt")
        return
    end
    if not isInt(anim.shortAfterPurchases) or anim.shortAfterPurchases < 1 then
        table.insert(errors, "UnlockAnimation.shortAfterPurchases muss eine ganze Zahl ab 1 sein")
    end
    if not isFinite(anim.maxTotalSeconds) or anim.maxTotalSeconds <= 0 then
        table.insert(errors, "UnlockAnimation.maxTotalSeconds muss eine Zahl größer als 0 sein")
    end
    for _, field in { "pressScale", "revealStartScale" } do
        if not isFinite(anim[field]) or anim[field] <= 0 or anim[field] > 1 then
            table.insert(errors, `UnlockAnimation.{field} muss größer als 0 und höchstens 1 sein`)
        end
    end

    local cueTable = if type(sounds) == "table" and type(sounds.cues) == "table" then sounds.cues else nil
    if cueTable == nil then
        table.insert(errors, "TreeSounds.cues fehlt")
    else
        for cueName, cue in cueTable do
            local label = `TreeSounds.cues.{tostring(cueName)}`
            if type(cue) ~= "table" then
                table.insert(errors, `{label} muss eine Tabelle sein`)
            else
                if type(cue.soundId) ~= "string" or (cue.soundId ~= "" and string.match(cue.soundId, SOUND_ID_PATTERN) == nil) then
                    table.insert(errors, `{label}.soundId muss leer oder "rbxassetid://" plus Ziffern sein`)
                end
                if not isFinite(cue.volume) or cue.volume < 0 or cue.volume > 1 then
                    table.insert(errors, `{label}.volume muss zwischen 0 und 1 liegen`)
                end
                if not isFinite(cue.pitch) or cue.pitch < 0.5 or cue.pitch > 2 then
                    table.insert(errors, `{label}.pitch muss zwischen 0,5 und 2 liegen`)
                end
            end
        end
    end

    if type(anim.variants) ~= "table" then
        table.insert(errors, "UnlockAnimation.variants fehlt")
        return
    end
    local totals: { [string]: number } = {}
    for _, name in UNLOCK_VARIANTS do
        local variant = anim.variants[name]
        local label = `UnlockAnimation.variants.{name}`
        if type(variant) ~= "table" then
            table.insert(errors, `{label} fehlt`)
            continue
        end
        local total = 0
        local lastStart = -1
        for _, stepName in UNLOCK_STEP_ORDER do
            local step = variant[stepName]
            if step == nil then
                if table.find(UNLOCK_REQUIRED_STEPS, stepName) ~= nil then
                    table.insert(errors, `{label}.{stepName} fehlt`)
                end
                continue
            end
            if type(step) ~= "table" or not isFinite(step.start) or step.start < 0 or not isFinite(step.duration) or step.duration <= 0 then
                table.insert(errors, `{label}.{stepName} braucht start ab 0 und duration über 0`)
                continue
            end
            if step.start < lastStart then
                table.insert(errors, `{label}.{stepName} startet vor dem Schritt davor (Reihenfolge: press, ring, pulse, reveal, camera)`)
            end
            lastStart = math.max(lastStart, step.start)
            total = math.max(total, step.start + step.duration)
        end
        if type(variant.ring) == "table" and (not isFinite(variant.ring.scale) or variant.ring.scale <= 1) then
            table.insert(errors, `{label}.ring.scale muss größer als 1 sein`)
        end
        local flash = variant.flash
        if flash ~= nil then
            if type(flash) ~= "table" or not isFinite(flash.start) or flash.start < 0 or not isFinite(flash.duration) or flash.duration <= 0 then
                table.insert(errors, `{label}.flash braucht start ab 0 und duration über 0`)
            else
                total = math.max(total, flash.start + flash.duration)
                if not isFinite(flash.strength) or flash.strength <= 0 or flash.strength > 1 then
                    table.insert(errors, `{label}.flash.strength muss größer als 0 und höchstens 1 sein`)
                end
            end
        end
        if isFinite(anim.maxTotalSeconds) and total > anim.maxTotalSeconds then
            table.insert(errors, `{label} dauert {total} s, erlaubt sind höchstens {anim.maxTotalSeconds} s`)
        end
        totals[name] = total

        if type(variant.cues) ~= "table" then
            table.insert(errors, `{label}.cues fehlt`)
        else
            for cueName, stepName in variant.cues do
                if cueTable ~= nil and cueTable[cueName] == nil then
                    table.insert(errors, `{label}.cues: Ton "{tostring(cueName)}" fehlt in TreeSounds`)
                end
                if type(stepName) ~= "string" or variant[stepName] == nil then
                    table.insert(errors, `{label}.cues.{tostring(cueName)}: Schritt "{tostring(stepName)}" gibt es in dieser Variante nicht`)
                end
            end
        end
    end
    if totals.short ~= nil and totals.normal ~= nil and totals.short >= totals.normal then
        table.insert(errors, "UnlockAnimation: die kurze Variante muss kürzer sein als die normale")
    end
    if totals.milestone ~= nil and totals.normal ~= nil and totals.milestone <= totals.normal then
        table.insert(errors, "UnlockAnimation: die Meilenstein-Variante muss länger sein als die normale")
    end
end

local function checkTutorial(errors: { string }, data: DataSet)
    local tutorial = data.Tutorial
    if type(tutorial) ~= "table" or type(tutorial.steps) ~= "table" or #tutorial.steps == 0 then
        table.insert(errors, "Tutorial.steps fehlt oder ist leer")
        return
    end
    if not isInt(tutorial.showUpgradesFromStep) or tutorial.showUpgradesFromStep < 1 or tutorial.showUpgradesFromStep > #tutorial.steps then
        table.insert(errors, "Tutorial.showUpgradesFromStep muss ein Schritt der Liste sein")
    end
    local tree = if type(data.UpgradeTree) == "table" then data.UpgradeTree.byId else nil
    local seen: { [string]: boolean } = {}
    for index, step in tutorial.steps do
        local label = `Tutorial Schritt {index}`
        if type(step) ~= "table" then
            table.insert(errors, `{label}: muss eine Tabelle sein`)
            continue
        end
        if type(step.id) ~= "string" or step.id == "" or seen[step.id] then
            table.insert(errors, `{label}: id fehlt oder ist doppelt`)
        else
            seen[step.id] = true
        end
        if type(step.text) ~= "string" or step.text == "" then
            table.insert(errors, `{label}: text fehlt`)
        end
        if TUTORIAL_TARGETS[step.target] == nil then
            table.insert(errors, `{label}: unbekanntes Ziel "{tostring(step.target)}"`)
        end
        local done = step.done
        if type(done) ~= "table" or CONDITION_KINDS[done.kind] == nil then
            table.insert(errors, `{label}: unbekannte Bedingung`)
        elseif done.kind == "tankAtLeast" and (not isFinite(done.amount) or done.amount <= 0) then
            table.insert(errors, `{label}: tankAtLeast braucht amount über 0`)
        elseif
            done.kind == "tankAtLeast"
            and type(data.Economy) == "table"
            and isFinite(data.Economy.startTankCapacity)
            and done.amount > data.Economy.startTankCapacity
        then
            table.insert(errors, `{label}: amount darf nicht größer als Economy.startTankCapacity sein`)
        elseif done.kind == "node" and (type(tree) ~= "table" or tree[done.nodeId] == nil) then
            table.insert(errors, `{label}: Knoten "{tostring(done.nodeId)}" fehlt in UpgradeTree`)
        end
        if step.highlightNodeId ~= nil and (type(tree) ~= "table" or tree[step.highlightNodeId] == nil) then
            table.insert(errors, `{label}: highlightNodeId "{tostring(step.highlightNodeId)}" fehlt in UpgradeTree`)
        end
    end
end

local SHAPES = { Block = true, Cylinder = true, Ball = true }

-- Aussehen der Werkzeugstufen (Paket 2.4): jede Stufe vorhanden, deutlich größer als die vorige.
local function checkToolLooks(errors: { string }, data: DataSet)
    local looks = data.ToolLooks
    if type(looks) ~= "table" or type(looks.list) ~= "table" or type(looks.byToolId) ~= "table" then
        table.insert(errors, "ToolLooks: list und byToolId fehlen")
        return
    end
    local limits = looks.limits
    if type(limits) ~= "table" then
        table.insert(errors, "ToolLooks.limits fehlt")
        return
    end
    for _, field in { "maxCameraBonusStuds", "maxParticlesPerEmit", "minStepFactor", "maxParts", "maxFlowParticles" } do
        positive(errors, `ToolLooks.limits.{field}`, limits[field])
    end
    local function nameSet(label: string, names: any): { [string]: boolean }
        local set: { [string]: boolean } = {}
        if type(names) ~= "table" or #names == 0 then
            table.insert(errors, `ToolLooks.limits.{label} fehlt`)
            return set
        end
        for _, name in names do
            if type(name) == "string" then
                set[name] = true
            end
        end
        return set
    end
    local flowKinds = nameSet("flowKinds", limits.flowKinds)
    local motionKinds = nameSet("motionKinds", limits.motionKinds)
    local view = looks.view
    if type(view) ~= "table" then
        table.insert(errors, "ToolLooks.view fehlt")
    else
        positive(errors, "ToolLooks.view.motionDistanceStuds", view.motionDistanceStuds)
        positive(errors, "ToolLooks.view.farUpdateSeconds", view.farUpdateSeconds)
    end
    local change = looks.change
    if type(change) ~= "table" then
        table.insert(errors, "ToolLooks.change fehlt")
    else
        for _, field in { "popSeconds", "popStartScale", "cameraSeconds" } do
            positive(errors, `ToolLooks.change.{field}`, change[field])
        end
        if isFinite(change.popStartScale) and change.popStartScale >= 1 then
            table.insert(errors, "ToolLooks.change.popStartScale muss unter 1 liegen")
        end
        if not isInt(change.burstCount) or change.burstCount < 0 then
            table.insert(errors, "ToolLooks.change.burstCount muss eine ganze Zahl ab 0 sein")
        end
    end
    local tools = if type(data.Tools) == "table" and type(data.Tools.list) == "table" then data.Tools.list else {}
    local known: { [string]: boolean } = {}
    local previous: any = nil
    for _, tool in tools do
        if type(tool) ~= "table" or type(tool.id) ~= "string" then
            continue
        end
        known[tool.id] = true
        local look = looks.byToolId[tool.id]
        local label = `ToolLooks "{tool.id}"`
        if type(look) ~= "table" then
            table.insert(errors, `{label}: Werkzeug hat kein Aussehen`)
            previous = nil
            continue
        end
        positive(errors, `{label}.footprint`, look.footprint)
        if type(look.parts) ~= "table" then
            table.insert(errors, `{label}.parts fehlt`)
        else
            if isFinite(limits.maxParts) and #look.parts > limits.maxParts then
                table.insert(errors, `{label}: mehr als {limits.maxParts} Teile`)
            end
            if tool.tier > 1 and #look.parts == 0 then
                table.insert(errors, `{label}: braucht mindestens ein Teil`)
            end
            if tool.tier == 1 and #look.parts > 0 then
                table.insert(errors, `{label}: die Hand hat kein Modell`)
            end
            for index, part in look.parts do
                local partLabel = `{label}.parts[{index}]`
                if type(part) ~= "table" then
                    table.insert(errors, `{partLabel} muss eine Tabelle sein`)
                    continue
                end
                if type(part.shape) ~= "string" or not SHAPES[part.shape] then
                    table.insert(errors, `{partLabel}.shape muss Block, Cylinder oder Ball sein`)
                end
                if type(part.size) ~= "table" then
                    table.insert(errors, `{partLabel}.size fehlt`)
                else
                    for _, axis in { "x", "y", "z" } do
                        positive(errors, `{partLabel}.size.{axis}`, part.size[axis])
                    end
                end
                if type(part.offset) ~= "table" then
                    table.insert(errors, `{partLabel}.offset fehlt`)
                else
                    for _, axis in { "x", "y", "z" } do
                        if not isFinite(part.offset[axis]) then
                            table.insert(errors, `{partLabel}.offset.{axis} muss eine Zahl sein`)
                        end
                    end
                end
                if type(part.colorHex) ~= "string" or not string.match(part.colorHex, HEX_PATTERN) then
                    table.insert(errors, `{partLabel}.colorHex muss Hex-Text wie #RRGGBB sein`)
                end
                if type(part.material) ~= "string" or part.material == "" then
                    table.insert(errors, `{partLabel}.material fehlt`)
                end
            end
        end
        local dust = look.dust
        if type(dust) ~= "table" then
            table.insert(errors, `{label}.dust fehlt`)
        else
            positive(errors, `{label}.dust.count`, dust.count)
            positive(errors, `{label}.dust.size`, dust.size)
            local burst = if type(change) == "table" and isFinite(change.burstCount) then change.burstCount else 0
            if isFinite(dust.count) and isFinite(limits.maxParticlesPerEmit) and dust.count + burst > limits.maxParticlesPerEmit then
                table.insert(errors, `{label}: Staub plus Wechsel-Wolke übersteigt das Partikelbudget`)
            end
        end
        if type(look.workPoint) ~= "table" or not isFinite(look.workPoint.x) or not isFinite(look.workPoint.z) then
            table.insert(errors, `{label}.workPoint braucht x und z`)
        elseif look.workPoint.z >= 0 then
            table.insert(errors, `{label}.workPoint muss vor dem Charakter liegen (z unter 0)`)
        end
        if type(look.loopSoundId) ~= "string" or (look.loopSoundId ~= "" and not string.match(look.loopSoundId, "^rbxassetid://%d+$")) then
            table.insert(errors, `{label}.loopSoundId muss leer oder rbxassetid:// plus Ziffern sein`)
        end
        local partCount = if type(look.parts) == "table" then #look.parts else 0
        if type(look.motions) ~= "table" then
            table.insert(errors, `{label}.motions fehlt`)
        else
            for index, motion in look.motions do
                local mLabel = `{label}.motions[{index}]`
                if type(motion) ~= "table" then
                    table.insert(errors, `{mLabel} muss eine Tabelle sein`)
                    continue
                end
                if not isInt(motion.part) or motion.part < 1 or motion.part > partCount then
                    table.insert(errors, `{mLabel}.part verweist auf kein Teil`)
                end
                if type(motion.kind) ~= "string" or not motionKinds[motion.kind] then
                    table.insert(errors, `{mLabel}.kind ist unbekannt`)
                end
                positive(errors, `{mLabel}.period`, motion.period)
                if not isFinite(motion.amplitude) or motion.amplitude < 0 then
                    table.insert(errors, `{mLabel}.amplitude muss eine Zahl ab 0 sein`)
                end
                if motion.kind == "slide" then
                    local v = motion.vector
                    if type(v) ~= "table" or not isFinite(v.x) or not isFinite(v.y) or not isFinite(v.z) then
                        table.insert(errors, `{mLabel}.vector fehlt`)
                    end
                elseif motion.axis ~= "x" and motion.axis ~= "y" and motion.axis ~= "z" then
                    table.insert(errors, `{mLabel}.axis muss x, y oder z sein`)
                end
            end
        end
        local flow = look.sandFlow
        if type(flow) ~= "table" then
            table.insert(errors, `{label}.sandFlow fehlt`)
        else
            if type(flow.kind) ~= "string" or not flowKinds[flow.kind] then
                table.insert(errors, `{label}.sandFlow.kind ist unbekannt`)
            end
            for _, point in { "from", "to" } do
                local v = flow[point]
                if type(v) ~= "table" or not isFinite(v.x) or not isFinite(v.y) or not isFinite(v.z) then
                    table.insert(errors, `{label}.sandFlow.{point} braucht x, y und z`)
                end
            end
            positive(errors, `{label}.sandFlow.speed`, flow.speed)
            positive(errors, `{label}.sandFlow.lifetime`, flow.lifetime)
            positive(errors, `{label}.sandFlow.size`, flow.size)
            if not isFinite(flow.rate) or flow.rate < 0 then
                table.insert(errors, `{label}.sandFlow.rate muss eine Zahl ab 0 sein`)
            elseif isFinite(flow.lifetime) and isFinite(limits.maxFlowParticles) and flow.rate * flow.lifetime > limits.maxFlowParticles then
                table.insert(errors, `{label}.sandFlow übersteigt das Partikelbudget`)
            end
            if not isFinite(flow.spread) or flow.spread < 0 or flow.spread > 180 then
                table.insert(errors, `{label}.sandFlow.spread muss zwischen 0 und 180 liegen`)
            end
            if tool.tier >= 3 and isFinite(flow.rate) and flow.rate <= 0 then
                table.insert(errors, `{label}.sandFlow: ab der Eimerkette muss der Sand sichtbar fließen (rate über 0)`)
            end
            if type(previous) == "table" and type(previous.sandFlow) == "table" and tool.tier >= 3 and previous.sandFlow.kind == flow.kind then
                table.insert(errors, `{label}.sandFlow.kind gleicht der Stufe davor`)
            end
        end
        local bonus = look.cameraBonusStuds
        if not isFinite(bonus) or bonus < 0 then
            table.insert(errors, `{label}.cameraBonusStuds muss eine Zahl ab 0 sein`)
        elseif isFinite(limits.maxCameraBonusStuds) and bonus > limits.maxCameraBonusStuds then
            table.insert(errors, `{label}.cameraBonusStuds liegt über dem Höchstwert`)
        end
        if type(previous) == "table" and type(look.dust) == "table" and type(previous.dust) == "table" then
            local factor = if isFinite(limits.minStepFactor) then limits.minStepFactor else 1
            if isFinite(look.footprint) and isFinite(previous.footprint) and look.footprint < previous.footprint * factor then
                table.insert(errors, `{label}: footprint steigt nicht um den Faktor {factor}`)
            end
            if isFinite(dust.count) and isFinite(previous.dust.count) and dust.count < previous.dust.count * factor then
                table.insert(errors, `{label}: dust.count steigt nicht um den Faktor {factor}`)
            end
            if isFinite(dust.size) and isFinite(previous.dust.size) and dust.size < previous.dust.size * factor then
                table.insert(errors, `{label}: dust.size steigt nicht um den Faktor {factor}`)
            end
            if isFinite(bonus) and isFinite(previous.cameraBonusStuds) and bonus < previous.cameraBonusStuds then
                table.insert(errors, `{label}: cameraBonusStuds darf nicht sinken`)
            end
        end
        previous = look
    end
    for toolId in looks.byToolId do
        if not known[toolId] then
            table.insert(errors, `ToolLooks "{tostring(toolId)}": kein Werkzeug mit dieser ID`)
        end
    end
end

-- Zonen in der Welt (Paket 2.5): Bereich, Spawn, Stand und Feld je Zone, Bereiche überlappen nicht.
local function checkWorldZones(errors: { string }, data: DataSet)
    local world = data.World
    if type(world) ~= "table" or type(world.zones) ~= "table" or type(world.zonesById) ~= "table" then
        table.insert(errors, "World.zones und World.zonesById fehlen")
        return
    end
    if not isFinite(world.pushBackMarginStuds) or world.pushBackMarginStuds < 0 then
        table.insert(errors, "World.pushBackMarginStuds muss eine Zahl ab 0 sein")
    end
    positive(errors, "World.travelCooldownSeconds", world.travelCooldownSeconds)
    if type(world.gateTag) ~= "string" or world.gateTag == "" then
        table.insert(errors, "World.gateTag fehlt")
    end
    local zones: { any } = {}
    local knownZones = if type(data.Zones) == "table" and type(data.Zones.byId) == "table" then data.Zones.byId else {}
    if type(data.Zones) == "table" then
        for _, group in { data.Zones.list, data.Zones.events } do
            if type(group) == "table" then
                for _, zone in group do
                    table.insert(zones, zone)
                end
            end
        end
    end
    local present: { [string]: boolean } = {}
    for index, area in world.zones do
        local label = `World.zones[{index}]`
        if type(area) ~= "table" or type(area.id) ~= "string" then
            table.insert(errors, `{label} braucht eine id`)
            continue
        end
        label = `World.zones "{area.id}"`
        if knownZones[area.id] == nil then
            table.insert(errors, `{label}: Zone fehlt in Zones (list oder events)`)
        end
        if present[area.id] then
            table.insert(errors, `{label} ist doppelt`)
        end
        present[area.id] = true
        if world.zonesById[area.id] ~= area then
            table.insert(errors, `{label}: zonesById passt nicht`)
        end
        local b = area.bounds
        if type(b) ~= "table" or not isFinite(b.minX) or not isFinite(b.maxX) or not isFinite(b.minZ) or not isFinite(b.maxZ) or b.minX >= b.maxX or b.minZ >= b.maxZ then
            table.insert(errors, `{label}.bounds braucht minX < maxX und minZ < maxZ`)
            continue
        end
        for _, point in { "spawn", "stand" } do
            local p = area[point]
            if type(p) ~= "table" or not isFinite(p.x) or not isFinite(p.y) or not isFinite(p.z) then
                table.insert(errors, `{label}.{point} braucht x, y und z`)
            elseif p.x < b.minX or p.x >= b.maxX or p.z < b.minZ or p.z > b.maxZ then
                table.insert(errors, `{label}.{point} liegt nicht im Bereich der Zone`)
            end
        end
        local field = area.field
        if type(field) ~= "table" or type(field.center) ~= "table" or type(field.size) ~= "table" then
            table.insert(errors, `{label}.field braucht center und size`)
        else
            for _, axis in { "x", "y", "z" } do
                if not isFinite(field.size[axis]) or field.size[axis] <= 0 then
                    table.insert(errors, `{label}.field.size.{axis} muss größer als 0 sein`)
                elseif field.size[axis] % 4 ~= 0 then
                    table.insert(errors, `{label}.field.size.{axis} muss ein Vielfaches von 4 sein`)
                end
                if not isFinite(field.center[axis]) then
                    table.insert(errors, `{label}.field.center.{axis} muss eine Zahl sein`)
                end
            end
        end
    end
    for _, zone in zones do
        if type(zone) == "table" and type(zone.id) == "string" and not present[zone.id] then
            table.insert(errors, `World.zones: Zone "{zone.id}" hat keinen Bereich`)
        end
    end
    -- Keine Überlappung (in x und z).
    local areas = world.zones
    for i = 1, #areas do
        for j = i + 1, #areas do
            local a, c = areas[i].bounds, areas[j].bounds
            if type(a) == "table" and type(c) == "table" and isFinite(a.minX) and isFinite(c.minX) then
                if a.minX < c.maxX and c.minX < a.maxX and a.minZ < c.maxZ and c.minZ < a.maxZ then
                    table.insert(errors, `World.zones: "{areas[i].id}" und "{areas[j].id}" überlappen`)
                end
            end
        end
    end
end

-- Sandsorten brauchen ein eigenes Terrain-Material (Paket 2.5), und alle Zonen-Sorten sind verschieden.
local function checkSandMaterials(errors: { string }, data: DataSet)
    local sandTypes = data.SandTypes
    if type(sandTypes) ~= "table" or type(sandTypes.list) ~= "table" then
        return
    end
    local seen: { [string]: string } = {}
    for _, sandType in sandTypes.list do
        local material = sandType.terrainMaterial
        if type(material) ~= "string" or material == "" or material == "Air" then
            table.insert(errors, `SandTypes "{tostring(sandType.id)}": terrainMaterial muss ein Materialname sein`)
        elseif seen[material] ~= nil then
            table.insert(errors, `SandTypes "{tostring(sandType.id)}": terrainMaterial "{material}" nutzt auch "{seen[material]}"`)
        else
            seen[material] = sandType.id
        end
    end
end

-- Obergrenzen für Fundchance, Wetter-Bonus, Wert und Sammlungsbonus (gegen Tippfehler in den Daten).
local MAX_FIND_CHANCE_PER_SECOND_BP = 1000 -- 10 % pro Sekunde (heute 2 %)
local MAX_ZONE_FIND_FACTOR_BP = 50000 -- x5 (heute bis x2)
local MAX_FIND_BASE_VALUE = 100
local MAX_WEATHER_FIND_BONUS_BP = 20000 -- +200 % (heute +15 %)
local MAX_RARITY_VALUE_FACTOR = 100000 -- heute bis 1500
local MAX_COLLECTION_BONUS_BP = 50000 -- +500 % über alle Zonen (heute +125 % bis +160 %)

-- Fundliste und Sammlung (Paket 2.6): ID-Muster, vollständige Sets, jede Seltenheit in jeder Zone,
-- Set-Boni, Zonenbücher und die Quotentabelle je Zone.
local function checkCollection(errors: { string }, data: DataSet)
    local finds, zones, rarities, odds, collection = data.Finds, data.Zones, data.Rarities, data.FindOdds, data.Collection
    if type(finds) ~= "table" or not isList(finds.list) or not isList(finds.sets) then
        return -- checkFinds meldet das
    end
    if type(zones) ~= "table" or not isList(zones.list) or type(rarities) ~= "table" or not isList(rarities.list) then
        return
    end

    -- Jedes Set hat genau `size` Fundstücke, die IDs folgen dem Muster "<Zone>_s<Set>_<Slot>".
    local perSet: { [string]: number } = {}
    local perZoneRarity: { [string]: { [string]: boolean } } = {}
    for _, find in finds.list do
        if type(find.id) ~= "string" or type(find.setId) ~= "string" or type(find.zoneId) ~= "string" or type(find.rarityId) ~= "string" then
            table.insert(errors, "Finds: ein Eintrag braucht id, setId, zoneId und rarityId als Text")
            continue
        end
        perSet[find.setId] = (perSet[find.setId] or 0) + 1
        local findSet = finds.setsById[find.setId]
        if findSet ~= nil then
            -- Feste IDs "<Zone>_s<Set>_<Slot>" (Slot = Reihenfolge im Set): Eine Umbenennung ließe
            -- gespeicherte Sammlungen still ihren Slot verlieren.
            local expected = `{findSet.zoneId}_s{findSet.index}_{perSet[find.setId]}`
            if find.id ~= expected then
                table.insert(errors, `Finds "{tostring(find.id)}": ID muss "{expected}" lauten`)
            end
        end
        perZoneRarity[find.zoneId] = perZoneRarity[find.zoneId] or {}
        perZoneRarity[find.zoneId][find.rarityId] = true
        if type(find.name) ~= "string" or find.name == "" then
            table.insert(errors, `Finds "{tostring(find.id)}": Name fehlt`)
        end
    end
    for _, findSet in finds.sets do
        if perSet[findSet.id] ~= findSet.size then
            table.insert(errors, `Finds: Set "{tostring(findSet.id)}" braucht genau {findSet.size} Fundstücke`)
        end
    end
    -- Jede Zone hat jede Seltenheit (sonst fiele ein Fund auf eine tiefere Stufe zurück).
    for _, zone in zones.list do
        for _, rarity in rarities.list do
            if not (perZoneRarity[zone.id] and perZoneRarity[zone.id][rarity.id]) then
                table.insert(errors, `Finds: Zone "{zone.id}" hat kein Fundstück der Seltenheit "{rarity.id}"`)
            end
        end
    end

    -- Quotentabelle je Zone und der sichere erste Fund.
    if type(odds) == "table" then
        local names = odds.zoneOddsTable
        if type(names) ~= "table" then
            table.insert(errors, "FindOdds.zoneOddsTable fehlt")
        else
            for _, zone in zones.list do
                local name = names[zone.id]
                if type(name) ~= "string" or type(odds.tables) ~= "table" or odds.tables[name] == nil then
                    table.insert(errors, `FindOdds.zoneOddsTable für Zone "{zone.id}" zeigt auf keine bekannte Tabelle`)
                end
            end
        end
        positive(errors, "FindOdds.firstFindGuaranteeSeconds", odds.firstFindGuaranteeSeconds)
        -- Obergrenzen gegen Tippfehler (zum Beispiel 20000 statt 200 ergäbe vier Funde pro Sekunde).
        if isFinite(odds.findChancePerSecond) and odds.findChancePerSecond > MAX_FIND_CHANCE_PER_SECOND_BP then
            table.insert(errors, `FindOdds.findChancePerSecond darf höchstens {MAX_FIND_CHANCE_PER_SECOND_BP} sein`)
        end
        if type(odds.zoneFindChanceFactor) == "table" then
            for zoneId, factor in odds.zoneFindChanceFactor do
                if isFinite(factor) and factor > MAX_ZONE_FIND_FACTOR_BP then
                    table.insert(errors, `FindOdds.zoneFindChanceFactor "{tostring(zoneId)}" darf höchstens {MAX_ZONE_FIND_FACTOR_BP} sein`)
                end
            end
        end
        if isFinite(odds.findBaseValue) and odds.findBaseValue > MAX_FIND_BASE_VALUE then
            table.insert(errors, `FindOdds.findBaseValue darf höchstens {MAX_FIND_BASE_VALUE} sein`)
        end
    end
    if type(data.Weather) == "table" and type(data.Weather.zones) == "table" then
        for zoneId, schedule in data.Weather.zones do
            if type(schedule) == "table" and isFinite(schedule.findChanceBonusBp) and schedule.findChanceBonusBp > MAX_WEATHER_FIND_BONUS_BP then
                table.insert(errors, `Weather.zones "{tostring(zoneId)}".findChanceBonusBp darf höchstens {MAX_WEATHER_FIND_BONUS_BP} sein`)
            end
        end
    end
    for _, rarity in rarities.list do
        if isFinite(rarity.valueFactor) and rarity.valueFactor > MAX_RARITY_VALUE_FACTOR then
            table.insert(errors, `Rarities "{tostring(rarity.id)}".valueFactor darf höchstens {MAX_RARITY_VALUE_FACTOR} sein`)
        end
    end

    -- Set-Boni je Set-Nummer und ein Zonenbuch je Zone.
    if type(collection) ~= "table" or type(collection.setBonusBp) ~= "table" or not isList(collection.zoneBooks) then
        table.insert(errors, "Collection: setBonusBp und zoneBooks fehlen")
        return
    end
    local bonusTotal = 0
    for index = 1, finds.SETS_PER_ZONE do
        local bonus = collection.setBonusBp[index]
        if not isInt(bonus) or bonus < 0 then
            table.insert(errors, `Collection.setBonusBp[{index}] muss eine ganze Zahl ab 0 sein`)
        else
            bonusTotal += bonus
        end
    end
    -- Alle Zonen zusammen dürfen den Gesamtbonus nicht über die Grenze heben.
    if bonusTotal * #zones.list > MAX_COLLECTION_BONUS_BP then
        table.insert(errors, `Collection.setBonusBp: der Gesamtbonus aller Zonen darf höchstens {MAX_COLLECTION_BONUS_BP} sein`)
    end
    local booked: { [string]: boolean } = {}
    for _, book in collection.zoneBooks do
        if type(zones.byId) == "table" and zones.byId[book.zoneId] == nil then
            table.insert(errors, `Collection.zoneBooks: unbekannte Zone "{tostring(book.zoneId)}"`)
        end
        if type(book.title) ~= "string" or book.title == "" or type(book.toolSkinId) ~= "string" or book.toolSkinId == "" then
            table.insert(errors, `Collection.zoneBooks "{tostring(book.zoneId)}": Titel und Skin fehlen`)
        end
        booked[book.zoneId] = true
    end
    for _, zone in zones.list do
        if not booked[zone.id] then
            table.insert(errors, `Collection.zoneBooks: Zone "{zone.id}" hat kein Zonenbuch`)
        end
    end
end

-- Wetter (Paket 2.5): bekannte Zonen und Arten, gültige Zeiten.
local function checkWeather(errors: { string }, data: DataSet)
    local weather = data.Weather
    if type(weather) ~= "table" or type(weather.zones) ~= "table" or type(weather.looks) ~= "table" then
        table.insert(errors, "Weather.zones und Weather.looks fehlen")
        return
    end
    positive(errors, "Weather.fadeSeconds", weather.fadeSeconds)
    local zoneIds = if type(data.Zones) == "table" and type(data.Zones.byId) == "table" then data.Zones.byId else {}
    for zoneId, schedule in weather.zones do
        local label = `Weather.zones.{tostring(zoneId)}`
        if zoneIds[zoneId] == nil then
            table.insert(errors, `{label}: unbekannte Zone`)
        end
        if type(schedule) ~= "table" then
            table.insert(errors, `{label} muss eine Tabelle sein`)
            continue
        end
        if type(schedule.kind) ~= "string" or weather.looks[schedule.kind] == nil then
            table.insert(errors, `{label}.kind steht nicht in Weather.looks`)
        end
        positive(errors, `{label}.cycleSeconds`, schedule.cycleSeconds)
        positive(errors, `{label}.activeSeconds`, schedule.activeSeconds)
        if isFinite(schedule.cycleSeconds) and isFinite(schedule.activeSeconds) and schedule.activeSeconds > schedule.cycleSeconds then
            table.insert(errors, `{label}: activeSeconds darf nicht länger als cycleSeconds sein`)
        end
        if not isFinite(schedule.offsetSeconds) or schedule.offsetSeconds < 0 then
            table.insert(errors, `{label}.offsetSeconds muss eine Zahl ab 0 sein`)
        end
        if not isInt(schedule.findChanceBonusBp) or schedule.findChanceBonusBp < 0 then
            table.insert(errors, `{label}.findChanceBonusBp muss eine ganze Zahl ab 0 sein`)
        end
    end
    for kind, look in weather.looks do
        local label = `Weather.looks.{tostring(kind)}`
        if type(look) ~= "table" then
            table.insert(errors, `{label} muss eine Tabelle sein`)
            continue
        end
        for _, field in { "atmosphereColorHex", "tintHex", "particleColorHex" } do
            if type(look[field]) ~= "string" or not string.match(look[field], HEX_PATTERN) then
                table.insert(errors, `{label}.{field} muss Hex-Text wie #RRGGBB sein`)
            end
        end
        if not isFinite(look.atmosphereDensity) or look.atmosphereDensity < 0 or look.atmosphereDensity > 1 then
            table.insert(errors, `{label}.atmosphereDensity muss zwischen 0 und 1 liegen`)
        end
        if not isFinite(look.atmosphereHaze) or look.atmosphereHaze < 0 or look.atmosphereHaze > 10 then
            table.insert(errors, `{label}.atmosphereHaze muss zwischen 0 und 10 liegen`)
        end
        for _, field in { "brightness", "saturation" } do
            if not isFinite(look[field]) or look[field] < -1 or look[field] > 1 then
                table.insert(errors, `{label}.{field} muss zwischen -1 und 1 liegen`)
            end
        end
        for _, field in { "particleRate", "particleSpeed", "particleSize", "particleWindStuds" } do
            if not isFinite(look[field]) or look[field] < 0 then
                table.insert(errors, `{label}.{field} muss eine Zahl ab 0 sein`)
            end
        end
    end
end

-- Data/Screen (Paket 3.6): Größenklassen, Tippflächen, Fenster und Grafikstufen.
local function checkScreen(errors: { string }, data: DataSet)
    local screen = data.Screen
    if type(screen) ~= "table" then
        table.insert(errors, "Screen fehlt")
        return
    end
    positive(errors, "Screen.compactShortSide", screen.compactShortSide)
    positive(errors, "Screen.minTouchPixels", screen.minTouchPixels)
    if not isFinite(screen.windowMargin) or screen.windowMargin < 0 then
        table.insert(errors, "Screen.windowMargin muss eine Zahl ab 0 sein")
    end
    local minTouch = if isFinite(screen.minTouchPixels) then screen.minTouchPixels else 44

    local function touchSize(label: string, value: any)
        if not isFinite(value) or value < minTouch then
            table.insert(errors, `{label} muss mindestens {minTouch} px sein (Tippfläche am Handy)`)
        end
    end

    local controls = screen.controls
    if type(controls) ~= "table" then
        table.insert(errors, "Screen.controls fehlt")
    else
        for _, field in { "closeButton", "rowButtonW", "rowButtonH", "tabH" } do
            touchSize(`Screen.controls.{field}`, controls[field])
        end
        positive(errors, "Screen.controls.headerH", controls.headerH)
        if not isFinite(controls.rowGap) or controls.rowGap < 0 then
            table.insert(errors, "Screen.controls.rowGap muss eine Zahl ab 0 sein")
        end
    end

    local windows = screen.windows
    if type(windows) ~= "table" then
        table.insert(errors, "Screen.windows fehlt")
    else
        for _, kind in { "narrow", "wide" } do
            local w = windows[kind]
            if type(w) ~= "table" then
                table.insert(errors, `Screen.windows.{kind} fehlt`)
                continue
            end
            for _, field in { "scaleX", "scaleY" } do
                if not isFinite(w[field]) or w[field] <= 0 or w[field] > 1 then
                    table.insert(errors, `Screen.windows.{kind}.{field} muss über 0 und höchstens 1 liegen`)
                end
            end
            for _, field in { "minW", "minH", "maxW", "maxH" } do
                positive(errors, `Screen.windows.{kind}.{field}`, w[field])
            end
            if isFinite(w.minW) and isFinite(w.maxW) and w.maxW < w.minW then
                table.insert(errors, `Screen.windows.{kind}: maxW liegt unter minW`)
            end
            if isFinite(w.minH) and isFinite(w.maxH) and w.maxH < w.minH then
                table.insert(errors, `Screen.windows.{kind}: maxH liegt unter minH`)
            end
        end
    end

    if type(screen.jumpZone) ~= "table" then
        table.insert(errors, "Screen.jumpZone fehlt")
    else
        positive(errors, "Screen.jumpZone.w", screen.jumpZone.w)
        positive(errors, "Screen.jumpZone.h", screen.jumpZone.h)
    end

    if type(screen.classes) ~= "table" then
        table.insert(errors, "Screen.classes fehlt")
    else
        for _, class in { "normal", "compact" } do
            local c = screen.classes[class]
            local label = `Screen.classes.{class}`
            if type(c) ~= "table" then
                table.insert(errors, `{label} fehlt`)
                continue
            end
            for _, group in { "hud", "lines", "treeButton", "menuButton", "menuRow", "banner", "toast", "dig", "smallCard", "bigCard", "stormBanner" } do
                if type(c[group]) ~= "table" then
                    table.insert(errors, `{label}.{group} fehlt`)
                end
            end
            if type(c.treeButton) == "table" then
                touchSize(`{label}.treeButton.w`, c.treeButton.w)
                touchSize(`{label}.treeButton.h`, c.treeButton.h)
            end
            if type(c.menuButton) == "table" then
                touchSize(`{label}.menuButton.w`, c.menuButton.w)
                touchSize(`{label}.menuButton.h`, c.menuButton.h)
            end
            if type(c.dig) == "table" then
                touchSize(`{label}.dig.size`, c.dig.size)
            end
            if type(c.banner) == "table" and isFinite(c.banner.minW) and isFinite(c.banner.maxW) and c.banner.maxW < c.banner.minW then
                table.insert(errors, `{label}.banner: maxW liegt unter minW`)
            end
            if type(c.smallCard) == "table" and c.smallCard.side ~= "left" and c.smallCard.side ~= "right" then
                table.insert(errors, `{label}.smallCard.side muss "left" oder "right" sein`)
            end
        end
    end

    local graphics = screen.graphics
    if type(graphics) ~= "table" or type(graphics.levels) ~= "table" or type(graphics.order) ~= "table" then
        table.insert(errors, "Screen.graphics fehlt oder ist unvollständig")
        return
    end
    if not isInt(graphics.leanMaxQualityLevel) or graphics.leanMaxQualityLevel < 1 or graphics.leanMaxQualityLevel > 10 then
        table.insert(errors, "Screen.graphics.leanMaxQualityLevel muss eine ganze Zahl von 1 bis 10 sein")
    end
    local numbers = { "particleFactor", "motionDistanceFactor" }
    local flags = { "postEffects", "toolShadows", "foundLight", "sandFlow", "revealEffects", "weatherParticles" }
    local previous: any = nil
    for _, name in { "hoch", "schlank", "minimal" } do
        local level = graphics.levels[name]
        local label = `Screen.graphics.levels.{name}`
        if table.find(graphics.order, name) == nil then
            table.insert(errors, `Screen.graphics.order enthält "{name}" nicht`)
        end
        if type(level) ~= "table" then
            table.insert(errors, `{label} fehlt`)
            previous = nil
            continue
        end
        for _, field in numbers do
            if not isFinite(level[field]) or level[field] < 0 or level[field] > 1 then
                table.insert(errors, `{label}.{field} muss eine Zahl von 0 bis 1 sein`)
            end
        end
        if isFinite(level.motionDistanceFactor) and level.motionDistanceFactor <= 0 then
            table.insert(errors, `{label}.motionDistanceFactor muss über 0 liegen`)
        end
        for _, field in flags do
            if type(level[field]) ~= "boolean" then
                table.insert(errors, `{label}.{field} muss true oder false sein`)
            end
        end
        if previous ~= nil then
            for _, field in numbers do
                if isFinite(level[field]) and isFinite(previous[field]) and level[field] > previous[field] then
                    table.insert(errors, `{label}.{field} darf nicht über dem der höheren Stufe liegen`)
                end
            end
            for _, field in flags do
                if level[field] == true and previous[field] == false then
                    table.insert(errors, `{label}.{field} darf nichts einschalten, was die höhere Stufe abschaltet`)
                end
            end
        end
        previous = level
    end
end

-- Server-Event "Der Koloss" (Paket 5.6): Das Fenster liegt in einer bekannten Phase und passt in die
-- Woche, das Ziel ist endlich und größer 0, die Stufen steigen ab 0 Sekunden, die Belohnungen sind fest
-- (Gems, Münz- und Glücks-Boost), nie Kisten oder Zufall.
local function checkKoloss(errors: { string }, data: DataSet)
    local koloss = data.Koloss
    if type(koloss) ~= "table" then
        table.insert(errors, "Koloss: Tabelle fehlt")
        return
    end
    local window = koloss.window
    if type(window) ~= "table" then
        table.insert(errors, "Koloss.window fehlt")
    else
        local seasons = data.Seasons
        local known = false
        if type(seasons) == "table" and isList(seasons.phases) then
            for _, phase in seasons.phases do
                if type(phase) == "table" and phase.id == window.phaseId then
                    known = true
                end
            end
        end
        if not known then
            table.insert(errors, `Koloss.window.phaseId "{tostring(window.phaseId)}" steht nicht in Seasons.phases`)
        end
        local seasons2 = data.Seasons
        if type(seasons2) == "table" and isList(seasons2.phases) then
            for _, phase in seasons2.phases do
                if type(phase) == "table" and phase.id == window.phaseId and phase.zoneOpen ~= true then
                    table.insert(errors, `Koloss.window: die Phase "{tostring(phase.id)}" braucht zoneOpen = true, sonst zählt nichts`)
                end
            end
        end
        if type(seasons2) == "table" and isList(seasons2.list) then
            for _, season in seasons2.list do
                if type(season) == "table" and (type(season.zoneId) ~= "string" or season.zoneId == "") then
                    table.insert(errors, `Koloss: Saison "{tostring(season.id)}" braucht eine zoneId (dort wird gegraben)`)
                end
            end
        end
        if not isInt(window.startDay) or window.startDay < 0 or window.startDay > 6 then
            table.insert(errors, "Koloss.window.startDay muss eine ganze Zahl von 0 (Montag) bis 6 sein")
        end
        if not isInt(window.days) or window.days < 1 then
            table.insert(errors, "Koloss.window.days muss eine ganze Zahl ab 1 sein")
        elseif isInt(window.startDay) and window.startDay + window.days > 7 then
            table.insert(errors, "Koloss.window: startDay + days muss in die Woche der Phase passen (höchstens 7)")
        end
    end
    if not isFinite(koloss.targetSeconds) or koloss.targetSeconds <= 0 then
        table.insert(errors, "Koloss.targetSeconds muss endlich und größer 0 sein")
    end
    local maxGems = math.huge
    if type(data.Economy) == "table" and type(data.Economy.purchases) == "table" and isFinite(data.Economy.purchases.maxGems) then
        maxGems = data.Economy.purchases.maxGems
    end
    if not isList(koloss.tiers) or #koloss.tiers < 1 then
        table.insert(errors, "Koloss.tiers braucht mindestens eine Stufe")
        return
    end
    local seen: { [string]: boolean } = {}
    local last = -1
    for index, tier in koloss.tiers do
        local label = `Koloss Stufe {index}`
        if type(tier) ~= "table" then
            table.insert(errors, `{label}: muss eine Tabelle sein`)
            continue
        end
        if type(tier.id) ~= "string" or tier.id == "" or type(tier.name) ~= "string" or tier.name == "" then
            table.insert(errors, `{label}: id und name müssen Text sein`)
        elseif seen[tier.id] then
            table.insert(errors, `{label}: id "{tier.id}" ist doppelt`)
        else
            seen[tier.id] = true
        end
        if not isFinite(tier.minSeconds) or tier.minSeconds < 0 then
            table.insert(errors, `{label}: minSeconds muss endlich und ab 0 sein`)
        elseif index == 1 and tier.minSeconds ~= 0 then
            table.insert(errors, `{label}: die erste Stufe braucht minSeconds 0 (alle im Server bei 100 % bekommen etwas)`)
        elseif tier.minSeconds <= last then
            table.insert(errors, `{label}: minSeconds muss aufsteigend über der vorigen Stufe liegen`)
        else
            last = tier.minSeconds
        end
        if isFinite(tier.minSeconds) and isFinite(koloss.targetSeconds) and tier.minSeconds > koloss.targetSeconds then
            table.insert(errors, `{label}: minSeconds liegt über targetSeconds, die Stufe wäre unerreichbar`)
        end
        if not isList(tier.rewards) or #tier.rewards < 1 then
            table.insert(errors, `{label}: rewards braucht mindestens eine Belohnung`)
            continue
        end
        for rewardIndex, reward in tier.rewards do
            local rewardLabel = `{label} Belohnung {rewardIndex}`
            if type(reward) ~= "table" then
                table.insert(errors, `{rewardLabel}: muss eine Tabelle sein`)
            elseif reward.kind == "gems" then
                if not isInt(reward.amount) or reward.amount < 1 or reward.amount > maxGems then
                    table.insert(errors, `{rewardLabel}: amount muss eine ganze Zahl von 1 bis maxGems sein`)
                end
            elseif reward.kind == "coinBoost" or reward.kind == "luck" then
                if not isInt(reward.seconds) or reward.seconds < 1 or reward.seconds > MAX_BOOST_REWARD_SECONDS then
                    table.insert(errors, `{rewardLabel}: seconds muss eine ganze Zahl von 1 bis {MAX_BOOST_REWARD_SECONDS} sein`)
                end
            else
                table.insert(errors, `{rewardLabel}: unbekannte Art "{tostring(if type(reward) == "table" then reward.kind else reward)}" (erlaubt: gems, coinBoost, luck)`)
            end
        end
    end
end

-- Prüft alle Tabellen. Ohne Argument die echten Datenmodule. Leere Liste = alles in Ordnung.
function DataCheck.run(dataSet: DataSet?): { string }
    local data = dataSet or DataCheck.defaults()
    local errors: { string } = {}
    checkRarities(errors, data)
    checkQuotas(errors, data)
    checkCrates(errors, data)
    checkCrateItems(errors, data)
    checkItems(errors, data)
    checkUpgradeTree(errors, data)
    checkTreeLayout(errors, data)
    checkScreen(errors, data)
    checkUnlockAnimation(errors, data)
    checkToolLooks(errors, data)
    checkTools(errors, data)
    checkSandTypes(errors, data)
    checkZones(errors, data)
    checkGemPacks(errors, data)
    checkProducts(errors, data)
    checkPerks(errors, data)
    checkOffers(errors, data)
    checkProductIds(errors, data)
    checkFinds(errors, data)
    checkCollection(errors, data)
    checkEconomy(errors, data)
    checkDaily(errors, data)
    checkSandstorm(errors, data)
    checkPurchases(errors, data)
    checkDirectShop(errors, data)
    checkSeasons(errors, data)
    checkSeasonPass(errors, data)
    checkKoloss(errors, data)
    checkWorld(errors, data)
    checkWorldZones(errors, data)
    checkSandMaterials(errors, data)
    checkWeather(errors, data)
    checkTerrain(errors, data)
    checkTankChain(errors, data)
    checkTutorial(errors, data)
    return errors
end

return DataCheck
