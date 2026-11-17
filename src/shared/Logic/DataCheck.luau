--!strict
-- Reine Prüfung aller Datentabellen. Gibt eine Liste von Fehlertexten zurück (leer = ok).
-- `DataCheck.run()` prüft die echten Tabellen, `DataCheck.run(dataSet)` eine übergebene
-- (z. B. absichtlich kaputte) Fassung. Der Server ruft die Prüfung beim Start auf.

local QUOTA_TOTAL = 10000 -- 100 % in Hundertstel-Prozent
local GEM_BONUS_TOLERANCE = 1 -- Prozentpunkte
local HEX_PATTERN = "^#%x%x%x%x%x%x$"

local CURRENCIES = { coins = true, gems = true }
local PRODUCT_KINDS = { gamepass = true, developerProduct = true, direct = true }
local DAILY_KINDS = { coins = true, gems = true, boost = true, crate = true, fixedItem = true }
local EFFECT_KINDS = { setTool = true, rateBonus = true, setTank = true, grantedBySandstorm = true }
local CONDITION_KINDS = { tankAtLeast = true, sold = true, node = true }
local TUTORIAL_TARGETS = { sand = true, stand = true, list = true }
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
    GemPacks: any,
    Products: any,
    Economy: any,
    UpgradeTree: any,
    World: any,
    Terrain: any,
    Tutorial: any,
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
        GemPacks = require("../Data/GemPacks"),
        Products = require("../Data/Products"),
        Economy = require("../Data/Economy"),
        UpgradeTree = require("../Data/UpgradeTree"),
        World = require("../Data/World"),
        Terrain = require("../Data/Terrain"),
        Tutorial = require("../Data/Tutorial"),
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

    -- Pity der Goldkiste: Episch spätestens bei 15, Legendär spätestens bei 60.
    local pity = gold.pity
    if type(pity) ~= "table" or pity.epic ~= 15 or pity.legendary ~= 60 then
        table.insert(errors, "Crates gold: pity muss epic = 15 und legendary = 60 sein")
    end

    -- 10er-Paket: zehn kaufen, elf bekommen.
    local bundle = crates.bundle
    if type(bundle) ~= "table" or bundle.buy ~= 10 or bundle.get ~= 11 then
        table.insert(errors, "Crates: bundle muss buy = 10 und get = 11 sein")
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
        end
    end
    if not hasStart then
        table.insert(errors, "Zones: keine Startzone (requires = \"start\")")
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
        if not isFinite(node.cost) or node.cost < 0 then
            table.insert(errors, `{label}: cost muss eine Zahl ab 0 sein`)
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
        elseif node.effect.kind == "rateBonus" and (not isInt(node.effect.bp) or node.effect.bp <= 0) then
            table.insert(errors, `{label}: rateBonus braucht bp als ganze Zahl über 0`)
        elseif node.effect.kind == "setTank" and (not isInt(node.effect.capacity) or node.effect.capacity <= 0) then
            table.insert(errors, `{label}: setTank braucht capacity als ganze Zahl über 0`)
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
    elseif offline.baseHours <= 0 or offline.autoDigHours <= offline.baseHours then
        table.insert(errors, "Economy.offline: autoDigHours muss größer als baseHours sein")
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
    if not isFinite(economy.bigTankMultiplier) or economy.bigTankMultiplier <= 1 then
        table.insert(errors, "Economy.bigTankMultiplier muss größer als 1 sein")
    end
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
    local daily = economy.daily
    if type(daily) ~= "table" or type(daily.days) ~= "table" or #daily.days ~= 6 then
        table.insert(errors, "Economy.daily: Tag 1 bis 6 fehlen")
    else
        for index, reward in daily.days do
            local label = `Economy.daily.days[{index}]`
            if type(reward) ~= "table" or DAILY_KINDS[reward.kind] == nil then
                table.insert(errors, `{label}: unbekannte Art (kind)`)
            elseif reward.day ~= index then
                table.insert(errors, `{label}: day muss {index} sein`)
            elseif reward.kind == "boost" then
                if type(reward.boostId) ~= "string" or reward.boostId == "" then
                    table.insert(errors, `{label}: boostId fehlt`)
                end
                if not isFinite(reward.durationSeconds) or reward.durationSeconds <= 0 then
                    table.insert(errors, `{label}: durationSeconds muss größer als 0 sein`)
                end
            elseif not isFinite(reward.amount) or reward.amount <= 0 then
                table.insert(errors, `{label}: amount muss größer als 0 sein`)
            end
        end
        if type(daily.day7) ~= "table" or daily.day7.crateId ~= "iron" then
            table.insert(errors, "Economy.daily: Tag 7 muss die Eisenkiste sein")
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

-- Prüft alle Tabellen. Ohne Argument die echten Datenmodule. Leere Liste = alles in Ordnung.
function DataCheck.run(dataSet: DataSet?): { string }
    local data = dataSet or DataCheck.defaults()
    local errors: { string } = {}
    checkRarities(errors, data)
    checkQuotas(errors, data)
    checkCrates(errors, data)
    checkUpgradeTree(errors, data)
    checkTools(errors, data)
    checkSandTypes(errors, data)
    checkZones(errors, data)
    checkGemPacks(errors, data)
    checkProducts(errors, data)
    checkFinds(errors, data)
    checkEconomy(errors, data)
    checkWorld(errors, data)
    checkTerrain(errors, data)
    checkTankChain(errors, data)
    checkTutorial(errors, data)
    return errors
end

return DataCheck
