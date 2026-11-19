--!strict
-- Paket 3.3: Namen und Beschreibungen der 150 Fundstücke und Namen der 30 Sets.
-- IDs, Seltenheiten, Sets und Zonen bleiben gegenüber 2.6 unverändert, sonst gehen
-- gespeicherte Sammlungen verloren.

local T = require("./lib/expect")
local Finds = require("../src/shared/Data/Finds")
local Zones = require("../src/shared/Data/Zones")

local MAX_NAME_CHARS = 28
local MAX_DESCRIPTION_CHARS = 80

-- Seltenheit je Set und Slot aus Paket 2.6 (in jeder Zone gleich).
local RARITY_PATTERN: { { string } } = {
    { "common", "common", "common", "common", "common" },
    { "common", "uncommon", "uncommon", "uncommon", "rare" },
    { "uncommon", "uncommon", "uncommon", "rare", "rare" },
    { "uncommon", "uncommon", "rare", "rare", "epic" },
    { "uncommon", "rare", "rare", "epic", "legendary" },
    { "rare", "epic", "epic", "legendary", "mythic" },
}

local function chars(text: string): number
    return utf8.len(text) or #text
end

T.describe("Fundnamen (3.3)", function()
    T.it("IDs, Reihenfolge, Zone, Set und Seltenheit sind wie in 2.6", function()
        T.expect(#Finds.list).toBe(150)
        local index = 0
        for _, zone in Zones.list do
            for setIndex = 1, 6 do
                for slot = 1, 5 do
                    index += 1
                    local find = Finds.list[index]
                    T.expect(find.id).toBe(`{zone.id}_s{setIndex}_{slot}`)
                    T.expect(find.zoneId).toBe(zone.id)
                    T.expect(find.setId).toBe(`{zone.id}_set_{setIndex}`)
                    T.expect(find.rarityId).toBe(RARITY_PATTERN[setIndex][slot])
                end
            end
        end
    end)

    T.it("keine Platzhalter mehr in Namen und Beschreibungen", function()
        for _, find in Finds.list do
            T.expect(string.find(find.description, "Platzhalter", 1, true)).toBeNil()
            T.expect(string.find(find.name, "Platzhalter", 1, true)).toBeNil()
            T.expect(string.find(find.name, "fund %d%-%d")).toBeNil()
        end
    end)

    T.it("Namen sind eindeutig und höchstens 28 Zeichen lang", function()
        local seen: { [string]: string } = {}
        for _, find in Finds.list do
            T.expect(chars(find.name) > 0).toBe(true)
            if chars(find.name) > MAX_NAME_CHARS then
                error(`Name zu lang: {find.id} "{find.name}"`)
            end
            if seen[find.name] ~= nil then
                error(`Name doppelt: "{find.name}" ({seen[find.name]} und {find.id})`)
            end
            seen[find.name] = find.id
        end
    end)

    T.it("Beschreibungen sind nicht leer und höchstens 80 Zeichen lang", function()
        for _, find in Finds.list do
            local length = chars(find.description)
            if length == 0 or length > MAX_DESCRIPTION_CHARS then
                error(`Beschreibung ungültig: {find.id} ({length} Zeichen)`)
            end
        end
    end)

    T.it("jedes Set hat einen eindeutigen Namen", function()
        T.expect(#Finds.sets).toBe(30)
        local seen: { [string]: boolean } = {}
        for _, findSet in Finds.sets do
            T.expect(type(findSet.name)).toBe("string")
            T.expect(chars(findSet.name) > 0).toBe(true)
            T.expect(seen[findSet.name]).toBeNil()
            seen[findSet.name] = true
        end
    end)
end)

T.finish()
