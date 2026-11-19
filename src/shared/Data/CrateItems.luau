--!strict
-- Platzhalter-Gewinne der Kisten (Konzept: "Kisten, Quoten und Monetarisierung").
-- Jede Kiste mit Quote > 0 für eine Seltenheit braucht mindestens 3 Items dieser Seltenheit.
-- Seltenheiten kommen aus `Rarities`, Kisten aus `Crates`. Die Wirkung (`effectBp`) ist
-- vorerst 0 und kommt in Paket 4.3. Die IDs bleiben für immer gleich, sonst gehen
-- gespeicherte Sammlungen verloren. Die Event-Items (Saison) sind exklusiv für die Event-Kiste.

export type CrateItem = {
    id: string, -- "<kind>_<rarity>_<n>", z. B. "skin_common_1"
    kind: "skin" | "companion" | "toolVariant",
    name: string, -- Anzeigename für Spieler
    rarity: string, -- Seltenheits-ID aus Rarities
    crates: { string }, -- Kisten-IDs, in deren Pool das Item vorkommt
    effectBp: number, -- Wirkung in Hundertstel-Prozent, vorerst 0
}

local list: { CrateItem } = {
    -- common (wood, iron)
    { id = "skin_common_1", kind = "skin", name = "Sandläufer-Skin", rarity = "common", crates = { "wood", "iron" }, effectBp = 0 },
    { id = "skin_common_2", kind = "skin", name = "Staubmantel", rarity = "common", crates = { "wood", "iron" }, effectBp = 0 },
    { id = "companion_common_1", kind = "companion", name = "Dünenfuchs", rarity = "common", crates = { "wood", "iron" }, effectBp = 0 },
    { id = "toolVariant_common_1", kind = "toolVariant", name = "Blechschaufel", rarity = "common", crates = { "iron" }, effectBp = 0 },

    -- uncommon (wood, iron, gold)
    { id = "skin_uncommon_1", kind = "skin", name = "Wüstenreiter-Skin", rarity = "uncommon", crates = { "wood", "iron", "gold" }, effectBp = 0 },
    { id = "skin_uncommon_2", kind = "skin", name = "Karawanen-Skin", rarity = "uncommon", crates = { "wood", "iron", "gold" }, effectBp = 0 },
    { id = "companion_uncommon_1", kind = "companion", name = "Wüstengecko", rarity = "uncommon", crates = { "wood", "iron", "gold" }, effectBp = 0 },
    { id = "toolVariant_uncommon_1", kind = "toolVariant", name = "Kupferschaufel", rarity = "uncommon", crates = { "iron", "gold" }, effectBp = 0 },

    -- rare (wood, iron, gold)
    { id = "skin_rare_1", kind = "skin", name = "Oasen-Skin", rarity = "rare", crates = { "wood", "iron", "gold" }, effectBp = 0 },
    { id = "skin_rare_2", kind = "skin", name = "Kristall-Skin", rarity = "rare", crates = { "wood", "iron", "gold" }, effectBp = 0 },
    { id = "companion_rare_1", kind = "companion", name = "Skorpionwächter", rarity = "rare", crates = { "wood", "iron", "gold" }, effectBp = 0 },
    { id = "toolVariant_rare_1", kind = "toolVariant", name = "Glasschaufel", rarity = "rare", crates = { "iron", "gold" }, effectBp = 0 },
    { id = "companion_rare_2", kind = "companion", name = "Sandadler", rarity = "rare", crates = { "gold" }, effectBp = 0 },

    -- epic (wood, iron, gold)
    { id = "skin_epic_1", kind = "skin", name = "Königsdünen-Skin", rarity = "epic", crates = { "wood", "iron", "gold" }, effectBp = 0 },
    { id = "skin_epic_2", kind = "skin", name = "Goldwind-Skin", rarity = "epic", crates = { "wood", "iron", "gold" }, effectBp = 0 },
    { id = "companion_epic_1", kind = "companion", name = "Sandwolf", rarity = "epic", crates = { "wood", "iron", "gold" }, effectBp = 0 },
    { id = "toolVariant_epic_1", kind = "toolVariant", name = "Sichelrechen", rarity = "epic", crates = { "iron", "gold" }, effectBp = 0 },

    -- legendary (gold)
    { id = "skin_legendary_1", kind = "skin", name = "Sturmkönig-Skin", rarity = "legendary", crates = { "gold" }, effectBp = 0 },
    { id = "companion_legendary_1", kind = "companion", name = "Schattenfalke", rarity = "legendary", crates = { "gold" }, effectBp = 0 },
    { id = "toolVariant_legendary_1", kind = "toolVariant", name = "Sternenschaufel", rarity = "legendary", crates = { "gold" }, effectBp = 0 },

    -- mythic (gold)
    { id = "skin_mythic_1", kind = "skin", name = "Sandgott-Skin", rarity = "mythic", crates = { "gold" }, effectBp = 0 },
    { id = "companion_mythic_1", kind = "companion", name = "Sandwurm-Junges", rarity = "mythic", crates = { "gold" }, effectBp = 0 },
    { id = "toolVariant_mythic_1", kind = "toolVariant", name = "Weltenschaufel", rarity = "mythic", crates = { "gold" }, effectBp = 0 },

    -- Event-Pool (exklusiv, nur Event-Kiste)
    -- uncommon
    { id = "skin_uncommon_3", kind = "skin", name = "Saison-Sandläufer", rarity = "uncommon", crates = { "event" }, effectBp = 0 },
    { id = "companion_uncommon_2", kind = "companion", name = "Saison-Dünenfuchs", rarity = "uncommon", crates = { "event" }, effectBp = 0 },
    { id = "toolVariant_uncommon_2", kind = "toolVariant", name = "Saison-Schaufel", rarity = "uncommon", crates = { "event" }, effectBp = 0 },
    -- rare
    { id = "skin_rare_3", kind = "skin", name = "Saison-Karawanenmantel", rarity = "rare", crates = { "event" }, effectBp = 0 },
    { id = "companion_rare_3", kind = "companion", name = "Saison-Wüstenkater", rarity = "rare", crates = { "event" }, effectBp = 0 },
    { id = "toolVariant_rare_2", kind = "toolVariant", name = "Saison-Glasschaufel", rarity = "rare", crates = { "event" }, effectBp = 0 },
    -- epic
    { id = "skin_epic_3", kind = "skin", name = "Saison-Oasen-Skin", rarity = "epic", crates = { "event" }, effectBp = 0 },
    { id = "companion_epic_2", kind = "companion", name = "Saison-Salzgeist", rarity = "epic", crates = { "event" }, effectBp = 0 },
    { id = "toolVariant_epic_2", kind = "toolVariant", name = "Saison-Sichelrechen", rarity = "epic", crates = { "event" }, effectBp = 0 },
    -- legendary
    { id = "skin_legendary_2", kind = "skin", name = "Saison-Königsmantel", rarity = "legendary", crates = { "event" }, effectBp = 0 },
    { id = "companion_legendary_2", kind = "companion", name = "Saison-Sturmvogel", rarity = "legendary", crates = { "event" }, effectBp = 0 },
    { id = "toolVariant_legendary_2", kind = "toolVariant", name = "Saison-Kristallschaufel", rarity = "legendary", crates = { "event" }, effectBp = 0 },
    -- mythic
    { id = "skin_mythic_2", kind = "skin", name = "Saison-Sandgott-Skin", rarity = "mythic", crates = { "event" }, effectBp = 0 },
    { id = "companion_mythic_2", kind = "companion", name = "Saison-Sandwurm", rarity = "mythic", crates = { "event" }, effectBp = 0 },
    { id = "toolVariant_mythic_2", kind = "toolVariant", name = "Saison-Weltenschaufel", rarity = "mythic", crates = { "event" }, effectBp = 0 },
}

local byId: { [string]: CrateItem } = {}
for _, item in list do
    byId[item.id] = item
end

return {
    list = list,
    byId = byId,
}
