--!strict
-- Paket 4.3: Ausrüstung und Verschmelzen der Kisten-Items (Logic/Equipment), dazu Wirkung auf die
-- Sammelrate (Collecting.rateOf), Migration, sanitize, Speichern/Laden und Sandsturm.

local T = require("./lib/expect")
local serde = require("@lune/serde")
local Equipment = require("../src/shared/Logic/Equipment")
local Collecting = require("../src/shared/Logic/Collecting")
local CrateOpen = require("../src/shared/Logic/CrateOpen")
local Profile = require("../src/shared/Logic/Profile")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local BigNum = require("../src/shared/Logic/BigNum")
local CrateItems = require("../src/shared/Data/CrateItems")
local Economy = require("../src/shared/Data/Economy")
local Rarities = require("../src/shared/Data/Rarities")

local NOW = 1_700_000_000

-- Items mit bekannten Werten (Data/CrateItems): common 500, rare 1000, epic 1400, legendary 1900, mythic 2500.
local SKIN = "skin_common_1"
local SKIN_RARE = "skin_rare_1"
local COMPANION = "companion_epic_1"
local VARIANT = "toolVariant_legendary_1"
local MYTHIC_SKIN = "skin_mythic_1"

local function deepCopy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in value do
        copy[key] = deepCopy(inner)
    end
    return copy
end

-- Profil mit Besitz: je Item `count` Exemplare (Standard 1).
local function profileWith(items: { [string]: number }): any
    local profile: any = Profile.default(NOW)
    for itemId, count in items do
        local item = CrateItems.byId[itemId]
        profile.inventory[Equipment.INVENTORY_FIELDS[item.kind]][itemId] = count
    end
    return profile
end

T.describe("Tabellen und Grundwerte", function()
    T.it("die Inventar-Felder sind dieselben wie bei der Kistenöffnung", function()
        T.expect(Equipment.INVENTORY_FIELDS).toEqual(CrateOpen.INVENTORY_FIELDS)
    end)

    T.it("jedes Item hat einen Grundwert in den Grenzen, höhere Seltenheit gibt mehr", function()
        local bestByRank: { [number]: number } = {}
        for _, item in CrateItems.list do
            T.expect(item.effectBp >= 1 and item.effectBp <= Economy.items.maxEffectBp).toBe(true)
            local rank = Rarities.byId[item.rarity].rank
            bestByRank[rank] = item.effectBp
        end
        for rank = 2, 6 do
            T.expect(bestByRank[rank] > bestByRank[rank - 1]).toBe(true)
        end
    end)

    T.it("Sterne: ★1 ist der Grundwert, jeder Stern gibt starBonusBp vom Grundwert dazu, ★5 ist 1,6-fach", function()
        local item = CrateItems.byId[SKIN]
        T.expect(Equipment.itemBonusBp(item, 1)).toBe(500)
        T.expect(Equipment.itemBonusBp(item, 2)).toBe(575)
        T.expect(Equipment.itemBonusBp(item, 5)).toBe(800)
        -- Außerhalb der Grenzen wird gekappt.
        T.expect(Equipment.itemBonusBp(item, 0)).toBe(500)
        T.expect(Equipment.itemBonusBp(item, 99)).toBe(800)
        T.expect(Equipment.itemBonusBp(CrateItems.byId[MYTHIC_SKIN], 5)).toBe(4000)
    end)
end)

T.describe("Ausrüsten", function()
    T.it("ein besessenes Item lässt sich in den passenden Slot ausrüsten", function()
        local profile = profileWith({ [SKIN] = 1 })
        local result = Equipment.equip(profile, "skin", SKIN)
        T.expect(result.ok).toBe(true)
        T.expect(result.bonusBp).toBe(500)
        T.expect(profile.equipped.skin).toBe(SKIN)
        T.expect(profile.equipped.companion).toBe("")
    end)

    T.it("ohne Besitz, falscher Slot, unbekannte ID und kaputte Argumente werden abgelehnt, Profil unverändert", function()
        local profile = profileWith({ [SKIN] = 1 })
        local before = deepCopy(profile)
        T.expect(Equipment.equip(profile, "skin", SKIN_RARE).reason).toBe("notOwned")
        T.expect(Equipment.equip(profile, "companion", SKIN).reason).toBe("wrongSlot")
        T.expect(Equipment.equip(profile, "skin", "gibt_es_nicht").reason).toBe("unknownItem")
        T.expect(Equipment.equip(profile, "skin", 5).reason).toBe("unknownItem")
        T.expect(Equipment.equip(profile, "hut", SKIN).reason).toBe("badSlot")
        T.expect(Equipment.equip(profile, 3, SKIN).reason).toBe("badSlot")
        T.expect(Equipment.equip(nil, "skin", SKIN).reason).toBe("noProfile")
        T.expect(profile).toEqual(before)
    end)

    T.it("dasselbe Item nochmal ausrüsten oder einen leeren Slot abnehmen meldet changed = false", function()
        local profile = profileWith({ [SKIN] = 1 })
        T.expect(Equipment.equip(profile, "skin", SKIN).changed).toBe(true)
        local again = Equipment.equip(profile, "skin", SKIN)
        T.expect(again.ok).toBe(true)
        T.expect(again.changed).toBe(false)
        T.expect(Equipment.equip(profile, "companion", "").changed).toBe(false)
        T.expect(Equipment.equip(profile, "skin", "").changed).toBe(true)
    end)

    T.it("eine leere ID nimmt den Slot ab, ein zweiter Slot bleibt unberührt", function()
        local profile = profileWith({ [SKIN] = 1, [COMPANION] = 1 })
        Equipment.equip(profile, "skin", SKIN)
        Equipment.equip(profile, "companion", COMPANION)
        local result = Equipment.equip(profile, "skin", "")
        T.expect(result.ok).toBe(true)
        T.expect(profile.equipped.skin).toBe("")
        T.expect(profile.equipped.companion).toBe(COMPANION)
        T.expect(result.bonusBp).toBe(1400)
    end)

    T.it("ein anderes Item im selben Slot ersetzt das alte", function()
        local profile = profileWith({ [SKIN] = 1, [SKIN_RARE] = 1 })
        Equipment.equip(profile, "skin", SKIN)
        Equipment.equip(profile, "skin", SKIN_RARE)
        T.expect(profile.equipped.skin).toBe(SKIN_RARE)
        T.expect(Equipment.bonusBp(profile)).toBe(1000)
    end)

    T.it("ein Profil ohne equipped-Feld (altes Profil) lässt sich trotzdem ausrüsten", function()
        local profile = profileWith({ [SKIN] = 1 })
        profile.equipped = nil
        T.expect(Equipment.equip(profile, "skin", SKIN).ok).toBe(true)
        T.expect(profile.equipped).toEqual({ skin = SKIN, companion = "", toolVariant = "" })
    end)
end)

T.describe("Wirkung", function()
    T.it("ohne Ausrüstung ist der Faktor genau 1", function()
        local profile = profileWith({ [SKIN] = 3 })
        T.expect(Equipment.bonusBp(profile)).toBe(0)
        T.expect(Equipment.multiplier(profile)).toBe(1)
    end)

    T.it("nur ausgerüstete Items wirken, drei Slots addieren sich", function()
        local profile = profileWith({ [SKIN] = 1, [COMPANION] = 1, [VARIANT] = 1 })
        Equipment.equip(profile, "skin", SKIN)
        T.expect(Equipment.bonusBp(profile)).toBe(500)
        Equipment.equip(profile, "companion", COMPANION)
        Equipment.equip(profile, "toolVariant", VARIANT)
        T.expect(Equipment.bonusBp(profile)).toBe(500 + 1400 + 1900)
        T.expect(Equipment.multiplier(profile)).toBeCloseTo(1.38, 0.0001)
    end)

    T.it("der Gesamtbonus ist gedeckelt: drei Mythische ★5 ergeben genau den Deckel, auch bei absurden Sternen", function()
        local profile = profileWith({ skin_mythic_1 = 1, companion_mythic_1 = 1, toolVariant_mythic_1 = 1 })
        Equipment.equip(profile, "skin", "skin_mythic_1")
        Equipment.equip(profile, "companion", "companion_mythic_1")
        Equipment.equip(profile, "toolVariant", "toolVariant_mythic_1")
        profile.itemStars = { skin_mythic_1 = 5, companion_mythic_1 = 5, toolVariant_mythic_1 = 5 }
        T.expect(Equipment.bonusBp(profile)).toBe(12000)
        T.expect(Economy.items.maxTotalBonusBp).toBe(12000)
        profile.itemStars = { skin_mythic_1 = 1e9, companion_mythic_1 = 1e9, toolVariant_mythic_1 = 1e9 }
        T.expect(Equipment.bonusBp(profile)).toBe(12000)
        -- ein zu niedriger Deckel in den Daten gilt
        local data = { CrateItems = CrateItems, Economy = { items = { maxStars = 5, starBonusBp = 1500, copiesToMerge = { 1, 2, 3, 4 }, maxEffectBp = 2500, maxTotalBonusBp = 5000 } } }
        T.expect(Equipment.bonusBp(profile, data)).toBe(5000)
    end)

    T.it("ein veralteter oder kaputter Eintrag wirkt nicht (unbekannt, falsche Art, nicht besessen)", function()
        local profile = profileWith({ [SKIN] = 1 })
        profile.equipped = { skin = "weg_aus_den_daten", companion = SKIN, toolVariant = VARIANT }
        T.expect(Equipment.bonusBp(profile)).toBe(0)
        profile.equipped = { skin = SKIN, companion = "", toolVariant = "" }
        T.expect(Equipment.bonusBp(profile)).toBe(500)
        profile.inventory.skins[SKIN] = 0
        T.expect(Equipment.bonusBp(profile)).toBe(0)
    end)

    T.it("Collecting.rateOf multipliziert den Ausrüstungsbonus nach dem Baum-Bonus", function()
        local profile = profileWith({ [SKIN] = 1, [COMPANION] = 1 })
        local base = Collecting.rateOf(profile)
        T.expect(base > 0).toBe(true)
        Equipment.equip(profile, "skin", SKIN)
        Equipment.equip(profile, "companion", COMPANION)
        T.expect(Collecting.rateOf(profile)).toBeCloseTo(base * 1.19, 1e-9)
        -- mit einem Baum-Knoten: Faktoren multiplizieren sich, sie werden nicht addiert
        local tree = profileWith({ [SKIN] = 1 })
        tree.nodes = { collect_rate_1 = true }
        local treeBase = Collecting.rateOf(tree)
        Equipment.equip(tree, "skin", SKIN)
        T.expect(Collecting.rateOf(tree)).toBeCloseTo(treeBase * 1.05, 1e-9)
    end)

    T.it("die Sammelrate ändert weder Fundchance noch Verkaufspreis", function()
        local profile = profileWith({ [MYTHIC_SKIN] = 1 })
        local priceBefore = Collecting.pricePerSand(profile)
        Equipment.equip(profile, "skin", MYTHIC_SKIN)
        T.expect(Collecting.pricePerSand(profile)).toBe(priceBefore)
    end)

    T.it("die Attribute für alle Clients nennen je Slot die ID oder leer", function()
        local profile = profileWith({ [SKIN] = 1 })
        Equipment.equip(profile, "skin", SKIN)
        T.expect(Equipment.attributesFor(profile)).toEqual({ SkinId = SKIN, CompanionId = "", ToolVariantId = "" })
        profile.equipped.skin = "unbekannt"
        T.expect(Equipment.attributesFor(profile).SkinId).toBe("")
    end)
end)

T.describe("Verschmelzen", function()
    T.it("★1 auf ★2 verbraucht eine Kopie, ein Exemplar bleibt immer", function()
        local profile = profileWith({ [SKIN] = 2 })
        local result = Equipment.merge(profile, SKIN)
        T.expect(result.ok).toBe(true)
        T.expect(result.stars).toBe(2)
        T.expect(result.copies).toBe(1)
        T.expect(result.consumed).toBe(1)
        T.expect(profile.inventory.skins[SKIN]).toBe(1)
        T.expect(profile.itemStars[SKIN]).toBe(2)
        T.expect(Equipment.starsOf(profile, SKIN)).toBe(2)
    end)

    T.it("mit nur einem Exemplar geht es nicht, Profil unverändert", function()
        local profile = profileWith({ [SKIN] = 1 })
        local before = deepCopy(profile)
        T.expect(Equipment.merge(profile, SKIN).reason).toBe("notEnoughCopies")
        T.expect(profile).toEqual(before)
    end)

    T.it("die Kopien je Schritt stammen aus der Tabelle (1, 2, 3, 4), insgesamt 11 Exemplare bis ★5", function()
        local profile = profileWith({ [SKIN] = 11 })
        local expected = Economy.items.copiesToMerge
        for step = 1, Economy.items.maxStars - 1 do
            local result = Equipment.merge(profile, SKIN)
            T.expect(result.ok).toBe(true)
            T.expect(result.consumed).toBe(expected[step])
            T.expect(result.stars).toBe(step + 1)
        end
        T.expect(profile.inventory.skins[SKIN]).toBe(1)
        T.expect(Equipment.starsOf(profile, SKIN)).toBe(Economy.items.maxStars)
    end)

    T.it("zu wenige Kopien für den nächsten Stern: abgelehnt, auch mit Rest vom vorigen Schritt", function()
        local profile = profileWith({ [SKIN] = 3 })
        T.expect(Equipment.merge(profile, SKIN).ok).toBe(true) -- 3 -> 2 Exemplare, ★2
        local before = deepCopy(profile)
        T.expect(Equipment.merge(profile, SKIN).reason).toBe("notEnoughCopies") -- ★3 braucht 2 Kopien, nur 1 übrig
        T.expect(profile).toEqual(before)
    end)

    T.it("bei ★5 wird abgelehnt, weitere Kopien bleiben liegen", function()
        local profile = profileWith({ [SKIN] = 20 })
        for _ = 1, Economy.items.maxStars - 1 do
            T.expect(Equipment.merge(profile, SKIN).ok).toBe(true)
        end
        local before = deepCopy(profile)
        T.expect(Equipment.merge(profile, SKIN).reason).toBe("maxStars")
        T.expect(profile).toEqual(before)
        T.expect(Equipment.mergeCost(profile, SKIN)).toBeNil()
    end)

    T.it("ohne Besitz, unbekannte ID und kaputte Argumente werden abgelehnt", function()
        local profile = profileWith({})
        local before = deepCopy(profile)
        T.expect(Equipment.merge(profile, SKIN).reason).toBe("notOwned")
        T.expect(Equipment.merge(profile, "gibt_es_nicht").reason).toBe("unknownItem")
        T.expect(Equipment.merge(profile, 7).reason).toBe("unknownItem")
        T.expect(Equipment.merge(nil, SKIN).reason).toBe("noProfile")
        T.expect(profile).toEqual(before)
    end)

    T.it("ein ausgerüstetes Item bleibt ausgerüstet und wirkt danach stärker", function()
        local profile = profileWith({ [SKIN] = 2 })
        Equipment.equip(profile, "skin", SKIN)
        T.expect(Equipment.bonusBp(profile)).toBe(500)
        local result = Equipment.merge(profile, SKIN)
        T.expect(profile.equipped.skin).toBe(SKIN)
        T.expect(result.bonusBp).toBe(575)
        T.expect(Equipment.bonusBp(profile)).toBe(575)
    end)

    T.it("es gibt keinen Zufall: gleiche Eingabe, gleiches Ergebnis", function()
        local a = profileWith({ [SKIN_RARE] = 5 })
        local b = profileWith({ [SKIN_RARE] = 5 })
        Equipment.merge(a, SKIN_RARE)
        Equipment.merge(b, SKIN_RARE)
        T.expect(a).toEqual(b)
    end)

    T.it("kaputte Zähler im Inventar zählen als 0 Exemplare", function()
        local profile = profileWith({})
        profile.inventory.skins[SKIN] = 0 / 0
        T.expect(Equipment.merge(profile, SKIN).reason).toBe("notOwned")
        profile.inventory.skins[SKIN] = -3
        T.expect(Equipment.merge(profile, SKIN).reason).toBe("notOwned")
    end)
end)

T.describe("Spielstand: Migration, sanitize, Speichern, Sandsturm", function()
    local function v4Profile(): any
        local profile: any = Profile.default(NOW)
        profile.version = 4
        profile.equipped = nil
        profile.itemStars = nil
        profile.inventory.skins[SKIN] = 3
        return profile
    end

    T.it("Migration 4 auf 5 legt equipped und itemStars an und behält das Inventar", function()
        local migrated, status = Profile.migrate(v4Profile(), nil, NOW)
        local profile: any = migrated
        T.expect(status).toBe("ok")
        T.expect(profile.version).toBe(5)
        T.expect(profile.equipped).toEqual({ skin = "", companion = "", toolVariant = "" })
        T.expect(profile.itemStars).toEqual({})
        T.expect(profile.inventory.skins[SKIN]).toBe(3)
        -- eine zweite Migration ändert nichts mehr
        local again = Profile.migrate(deepCopy(profile), nil, NOW)
        T.expect(again).toEqual(profile)
    end)

    T.it("Migration 4 auf 5 behält schon vorhandene Sterne und Ausrüstung (Kette läuft erneut)", function()
        local old = v4Profile()
        old.equipped = { skin = SKIN, companion = "", toolVariant = "" }
        old.itemStars = { [SKIN] = 3 }
        local migrated: any = Profile.migrate(old, nil, NOW)
        T.expect(migrated.equipped.skin).toBe(SKIN)
        T.expect(migrated.itemStars[SKIN]).toBe(3)
    end)

    T.it("sanitize leert nicht ausrüstbare Slots (unbekannt, falsche Art, nicht besessen)", function()
        local profile = profileWith({ [SKIN] = 1 })
        profile.equipped = { skin = "weg_aus_den_daten", companion = SKIN, toolVariant = VARIANT }
        local warnings = Profile.sanitize(profile, NOW)
        T.expect(#warnings).toBe(3)
        T.expect(profile.equipped).toEqual({ skin = "", companion = "", toolVariant = "" })
        -- ein gültiger Eintrag bleibt
        profile.equipped.skin = SKIN
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        T.expect(profile.equipped.skin).toBe(SKIN)
    end)

    T.it("sanitize repariert kaputte Typen in equipped und itemStars", function()
        local profile = profileWith({ [SKIN] = 1 })
        profile.equipped = { skin = 5, companion = true, toolVariant = {} }
        Profile.sanitize(profile, NOW)
        T.expect(profile.equipped).toEqual({ skin = "", companion = "", toolVariant = "" })
        profile.equipped = "kaputt"
        Profile.sanitize(profile, NOW)
        T.expect(profile.equipped).toEqual({ skin = "", companion = "", toolVariant = "" })
        profile.itemStars = "kaputt"
        Profile.sanitize(profile, NOW)
        T.expect(profile.itemStars).toEqual({})
    end)

    T.it("sanitize hält Sterne bei 2 bis maxStars, rundet Brüche ab und entfernt Ungültiges", function()
        local profile = profileWith({})
        profile.itemStars = {
            [SKIN] = 9,
            [SKIN_RARE] = 3.7,
            [COMPANION] = 1,
            [VARIANT] = 0 / 0,
            [MYTHIC_SKIN] = -2,
            weg_aus_den_daten = 4,
        }
        Profile.sanitize(profile, NOW)
        T.expect(profile.itemStars).toEqual({
            [SKIN] = Economy.items.maxStars,
            [SKIN_RARE] = 3,
            weg_aus_den_daten = 4, -- unbekannte IDs bleiben, sie wirken nur nicht
        })
    end)

    T.it("Ausrüstung und Sterne überstehen Speichern und Laden", function()
        local profile = profileWith({ [SKIN] = 5, [COMPANION] = 1 })
        Equipment.equip(profile, "skin", SKIN)
        Equipment.equip(profile, "companion", COMPANION)
        Equipment.merge(profile, SKIN)
        T.expect(Profile.sanitize(profile, NOW)).toEqual({})
        local stored = serde.decode("json", serde.encode("json", profile))
        local loaded: any = Profile.migrate(stored, nil, NOW)
        T.expect(Profile.sanitize(loaded, NOW, { trimLists = false })).toEqual({})
        T.expect(loaded.equipped).toEqual(profile.equipped)
        T.expect(loaded.itemStars).toEqual(profile.itemStars)
        T.expect(Equipment.bonusBp(loaded)).toBe(Equipment.bonusBp(profile))
        T.expect(Equipment.starsOf(loaded, SKIN)).toBe(2)
    end)

    T.it("der Sandsturm behält Ausrüstung und Sterne", function()
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "equipped") ~= nil).toBe(true)
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "itemStars") ~= nil).toBe(true)
        T.expect(table.find(Sandstorm.RESET_FIELDS, "equipped")).toBeNil()
        local profile = profileWith({ [SKIN] = 3 })
        Equipment.equip(profile, "skin", SKIN)
        Equipment.merge(profile, SKIN)
        profile.nodes = { collect_tool_2 = true, collect_tool_3 = true, collect_tool_4 = true }
        profile.runEarned = BigNum.serialize(BigNum.new(1, 8))
        local equippedBefore = deepCopy(profile.equipped)
        local starsBefore = deepCopy(profile.itemStars)
        local data = { Economy = { sandstorm = { requiresNode = "collect_tool_4", crystalUnit = 1_000_000, crystalExponent = 0.5, crystalScale = 1, minCrystals = 1, maxCrystals = 100_000 } } }
        T.expect(Sandstorm.apply(profile, data) ~= nil).toBe(true)
        T.expect(profile.equipped).toEqual(equippedBefore)
        T.expect(profile.itemStars).toEqual(starsBefore)
    end)
end)

T.finish()
