--!strict
-- Ausrüstung und Verschmelzen der Kisten-Items (Paket 4.3). Rein, ohne Roblox-API, Lune-Tests in
-- tests/equipment.spec.luau.
--
-- Drei Slots, je einer pro Art: "skin", "companion" (Begleiter), "toolVariant" (Werkzeug-Variante).
-- Nur ausgerüstete Items wirken, und jedes erhöht die Sammelrate um seinen Bonus. Die Boni der
-- drei Slots werden addiert und wirken als eigener Faktor neben dem Skilltree-Bonus:
--   Rate = Werkzeug x (1 + Baum) x (1 + Summe der drei Item-Boni)   (siehe Collecting.rateOf)
-- Fundchance, Verkaufspreis und Kistenquoten bleiben unberührt (Konzept).
--
-- Spielstand: `profile.equipped = { skin, companion, toolVariant }` (Item-ID oder "" = leer) und
-- `profile.itemStars = { [itemId] = 2..maxStars }` (fehlt = ★1). Besitz steht wie bisher in
-- `profile.inventory` (Anzahl Exemplare je Item). Die Wirkung kommt immer aus den aktuellen Tabellen
-- (Data/CrateItems, Economy.items), gespeichert werden nur IDs und Sterne.
--
-- Bonus eines Items = floor(effectBp x (10000 + (Sterne - 1) x starBonusBp) / 10000).
--
-- Verschmelzen: Ein Item steigt um einen Stern und verbraucht dafür Kopien (Economy.items.
-- copiesToMerge). Ein Exemplar bleibt immer. Kein Zufall, keine Kosten, kein Verkauf, kein Tausch.
--
-- `equip` und `merge` prüfen alles zuerst und schreiben erst danach in einem Zug (ohne Warten):
-- bei jeder Ablehnung bleibt das Profil unverändert. Die Server-Service-Schicht (Services/Equipment)
-- hängt nur Remotes daran. Der optionale Parameter `data` ist für Tests: { CrateItems, Economy }.

local CrateItemsData = require("../Data/CrateItems")
local EconomyData = require("../Data/Economy")

export type Slot = "skin" | "companion" | "toolVariant"

export type Reason = "noProfile" | "badSlot" | "unknownItem" | "wrongSlot" | "notOwned" | "notEnoughCopies" | "maxStars"

export type Result = {
    ok: boolean,
    reason: Reason?,
    bonusBp: number?, -- Gesamtbonus aller ausgerüsteten Items nach der Aktion
    itemId: string?,
    stars: number?,
    copies: number?, -- Exemplare, die nach dem Verschmelzen übrig sind
    consumed: number?, -- Kopien, die das Verschmelzen verbraucht hat
    changed: boolean?, -- equip: Hat sich der Slot geändert? (false = schon so ausgerüstet)
}

local Equipment = {}

Equipment.SLOTS = { "skin", "companion", "toolVariant" } :: { Slot }

-- Inventar-Feld je Art (wie CrateOpen.INVENTORY_FIELDS; ein Test hält beide gleich).
Equipment.INVENTORY_FIELDS = {
    skin = "skins",
    companion = "companions",
    toolVariant = "toolVariants",
} :: { [string]: string }

-- Attribut je Slot, das der Server am Spieler setzt (Paket 4.3), damit alle Clients die Ausrüstung sehen.
Equipment.ATTRIBUTES = {
    skin = "SkinId",
    companion = "CompanionId",
    toolVariant = "ToolVariantId",
} :: { [string]: string }

local function itemsOf(data: any?): any
    return if data ~= nil and data.CrateItems ~= nil then data.CrateItems else CrateItemsData
end

local function configOf(data: any?): any
    local economy = if data ~= nil and data.Economy ~= nil then data.Economy else EconomyData
    return economy.items
end

local function isSlot(slot: any): boolean
    return type(slot) == "string" and Equipment.INVENTORY_FIELDS[slot] ~= nil
end

local function copyTable(value: any): { [any]: any }
    return if type(value) == "table" then table.clone(value) else {}
end

-- Exemplare des Items im Inventar (ganze Zahl ab 0).
function Equipment.copiesOf(profile: any, item: any): number
    local inventory = if type(profile) == "table" then profile.inventory else nil
    local bucket = if type(inventory) == "table" then inventory[Equipment.INVENTORY_FIELDS[item.kind]] else nil
    local count = if type(bucket) == "table" then bucket[item.id] else nil
    if type(count) ~= "number" or count ~= count or count < 0 or count == math.huge then
        return 0
    end
    return math.floor(count)
end

-- Aktueller Stern des Items: ★1, wenn nichts gespeichert ist, sonst 1 bis maxStars.
function Equipment.starsOf(profile: any, itemId: string, data: any?): number
    local maxStars = configOf(data).maxStars
    local stars = if type(profile) == "table" and type(profile.itemStars) == "table" then profile.itemStars[itemId] else nil
    if type(stars) ~= "number" or stars ~= stars then
        return 1
    end
    return math.clamp(math.floor(stars), 1, maxStars)
end

-- Bonus des Items (Hundertstel-Prozent) bei diesem Stern.
function Equipment.itemBonusBp(item: any, stars: number, data: any?): number
    local cfg = configOf(data)
    local clamped = math.clamp(math.floor(stars), 1, cfg.maxStars)
    return math.floor(item.effectBp * (10000 + (clamped - 1) * cfg.starBonusBp) / 10000)
end

-- Das ausgerüstete Item des Slots, nur wenn es gültig ist: bekannt, richtige Art, mindestens ein
-- Exemplar im Inventar. Sonst nil (kaputte oder veraltete Einträge wirken einfach nicht).
function Equipment.equippedItem(profile: any, slot: string, data: any?): any?
    if type(profile) ~= "table" or type(profile.equipped) ~= "table" or not isSlot(slot) then
        return nil
    end
    local itemId = profile.equipped[slot]
    if type(itemId) ~= "string" or itemId == "" then
        return nil
    end
    local item = itemsOf(data).byId[itemId]
    if item == nil or item.kind ~= slot or Equipment.copiesOf(profile, item) < 1 then
        return nil
    end
    return item
end

-- Summe der Boni aller gültig ausgerüsteten Items (Hundertstel-Prozent), höchstens
-- Economy.items.maxTotalBonusBp (DataCheck stellt sicher, dass die Tabellen den Deckel nicht überschreiten;
-- er schützt zusätzlich gegen einen Fehler in den Daten).
function Equipment.bonusBp(profile: any, data: any?): number
    local total = 0
    for _, slot in Equipment.SLOTS do
        local item = Equipment.equippedItem(profile, slot, data)
        if item ~= nil then
            total += Equipment.itemBonusBp(item, Equipment.starsOf(profile, item.id, data), data)
        end
    end
    return math.min(total, configOf(data).maxTotalBonusBp)
end

-- Faktor auf die Sammelrate: 1 ohne Ausrüstung.
function Equipment.multiplier(profile: any, data: any?): number
    return (10000 + Equipment.bonusBp(profile, data)) / 10000
end

-- Kopien, die der nächste Stern verbraucht, oder nil bei maximalem Stern.
function Equipment.mergeCost(profile: any, itemId: string, data: any?): number?
    local cfg = configOf(data)
    local stars = Equipment.starsOf(profile, itemId, data)
    if stars >= cfg.maxStars then
        return nil
    end
    return cfg.copiesToMerge[stars]
end

-- Attribute für alle Clients: Item-ID je Slot, "" wenn leer oder ungültig.
function Equipment.attributesFor(profile: any, data: any?): { [string]: string }
    local result: { [string]: string } = {}
    for _, slot in Equipment.SLOTS do
        local item = Equipment.equippedItem(profile, slot, data)
        result[Equipment.ATTRIBUTES[slot]] = if item ~= nil then item.id else ""
    end
    return result
end

local function fail(reason: Reason): Result
    return { ok = false, reason = reason }
end

-- Rüstet ein Item aus oder (itemId = "") nimmt den Slot ab. Der Slot muss zur Art des Items passen,
-- und das Item muss im Inventar liegen.
function Equipment.equip(profile: any, slot: any, itemId: any, data: any?): Result
    if type(profile) ~= "table" then
        return fail("noProfile")
    end
    if not isSlot(slot) then
        return fail("badSlot")
    end
    local item: any = nil
    if itemId ~= "" then
        item = if type(itemId) == "string" then itemsOf(data).byId[itemId] else nil
        if item == nil then
            return fail("unknownItem")
        end
        if item.kind ~= slot then
            return fail("wrongSlot")
        end
        if Equipment.copiesOf(profile, item) < 1 then
            return fail("notOwned")
        end
    end
    local equipped: { [any]: any } = {}
    for _, name in Equipment.SLOTS do
        local current = if type(profile.equipped) == "table" then profile.equipped[name] else nil
        equipped[name] = if type(current) == "string" then current else ""
    end
    local newId = if item ~= nil then item.id else ""
    local changed = equipped[slot] ~= newId
    equipped[slot] = newId
    if changed or type(profile.equipped) ~= "table" then
        profile.equipped = equipped
    end
    return { ok = true, itemId = newId, changed = changed, bonusBp = Equipment.bonusBp(profile, data) }
end

-- Hebt das Item um einen Stern. Verbraucht die Kopien aus Economy.items.copiesToMerge, ein Exemplar
-- bleibt. Ein ausgerüstetes Item bleibt ausgerüstet (der höhere Bonus gilt sofort).
function Equipment.merge(profile: any, itemId: any, data: any?): Result
    if type(profile) ~= "table" then
        return fail("noProfile")
    end
    local item = if type(itemId) == "string" then itemsOf(data).byId[itemId] else nil
    if item == nil then
        return fail("unknownItem")
    end
    local copies = Equipment.copiesOf(profile, item)
    if copies < 1 then
        return fail("notOwned")
    end
    local stars = Equipment.starsOf(profile, item.id, data)
    local cost = Equipment.mergeCost(profile, item.id, data)
    if cost == nil then
        return fail("maxStars")
    end
    if copies - cost < 1 then
        return fail("notEnoughCopies")
    end
    -- Alles geprüft: erst die neuen Tabellen bauen, dann in einem Zug zuweisen.
    local field = Equipment.INVENTORY_FIELDS[item.kind]
    local inventory = copyTable(profile.inventory)
    local bucket = copyTable(inventory[field])
    bucket[item.id] = copies - cost
    inventory[field] = bucket
    local itemStars = copyTable(profile.itemStars)
    itemStars[item.id] = stars + 1
    profile.inventory = inventory
    profile.itemStars = itemStars
    return {
        ok = true,
        itemId = item.id,
        stars = stars + 1,
        copies = copies - cost,
        consumed = cost,
        bonusBp = Equipment.bonusBp(profile, data),
    }
end

return Equipment
