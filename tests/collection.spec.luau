--!strict
-- Paket 2.6: Sammlung, Sets, Bonus, Zonenbuch, Buchung von Funden und der Preis mit Bonus.

local T = require("./lib/expect")
local Collection = require("../src/shared/Logic/Collection")
local Collecting = require("../src/shared/Logic/Collecting")
local Profile = require("../src/shared/Logic/Profile")
local BigNum = require("../src/shared/Logic/BigNum")
local DataCheck = require("../src/shared/Logic/DataCheck")
local CollectionData = require("../src/shared/Data/Collection")
local Finds = require("../src/shared/Data/Finds")
local Zones = require("../src/shared/Data/Zones")

local NOW = 1_700_000_000

local function deepCopy(value: any, memo: { [any]: any }?): any
    if type(value) ~= "table" then
        return value
    end
    local seen = memo or {}
    if seen[value] ~= nil then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, inner in value do
        copy[deepCopy(key, seen)] = deepCopy(inner, seen)
    end
    return copy
end

local function fresh(): any
    return Profile.default(NOW)
end

local function findId(zoneId: string, setIndex: number, slot: number): string
    return `{zoneId}_s{setIndex}_{slot}`
end

-- Trägt die Slots 1 bis `slots` eines Sets ein.
local function fill(profile: any, zoneId: string, setIndex: number, slots: number?)
    for slot = 1, slots or 5 do
        profile.finds[findId(zoneId, setIndex, slot)] = 1
    end
end

local function setOf(profile: any, setId: string): Collection.SetProgress
    for _, set in Collection.progress(profile) do
        if set.setId == setId then
            return set
        end
    end
    error("Set nicht gefunden: " .. setId)
end

T.describe("Fortschritt und Bonus", function()
    T.it("ohne Funde: alle Sets leer, kein Bonus, kein Buch", function()
        local profile = fresh()
        for _, set in Collection.progress(profile) do
            T.expect(set.have).toBe(0)
            T.expect(set.complete).toBe(false)
            T.expect(set.bonusBp).toBe(0)
        end
        T.expect(Collection.bonusBp(profile)).toBe(0)
        T.expect(Collection.bonusMultiplier(profile)).toBe(1)
        T.expect(next(Collection.completedBooks(profile))).toBeNil()
    end)

    T.it("4 von 5 ist kein fertiges Set, 5 von 5 gibt den Bonus des Sets", function()
        local profile = fresh()
        fill(profile, "dunes", 1, 4)
        T.expect(setOf(profile, "dunes_set_1").have).toBe(4)
        T.expect(setOf(profile, "dunes_set_1").complete).toBe(false)
        T.expect(Collection.bonusBp(profile)).toBe(0)
        profile.finds[findId("dunes", 1, 5)] = 1
        T.expect(setOf(profile, "dunes_set_1").complete).toBe(true)
        T.expect(Collection.bonusBp(profile)).toBe(CollectionData.setBonusBp[1])
        T.expect(Collection.bonusMultiplier(profile)).toBeCloseTo(1 + CollectionData.setBonusBp[1] / 10000, 1e-12)
    end)

    T.it("der Bonus ist die Summe der fertigen Sets, auch aus verschiedenen Zonen", function()
        local profile = fresh()
        fill(profile, "dunes", 1)
        fill(profile, "oasis", 2)
        fill(profile, "ruins", 6)
        local expected = CollectionData.setBonusBp[1] + CollectionData.setBonusBp[2] + CollectionData.setBonusBp[6]
        T.expect(Collection.bonusBp(profile)).toBe(expected)
    end)

    T.it("das Zonenbuch ist erst bei 6 von 6 Sets fertig und nur für diese Zone", function()
        local profile = fresh()
        for index = 1, 5 do
            fill(profile, "canyon", index)
        end
        T.expect(Collection.completedBooks(profile).canyon).toBeNil()
        fill(profile, "canyon", 6)
        local books = Collection.completedBooks(profile)
        T.expect(books.canyon).toBe(true)
        T.expect(books.dunes).toBeNil()
        local total = 0
        for index = 1, 6 do
            total += CollectionData.setBonusBp[index]
        end
        T.expect(Collection.bonusBp(profile)).toBe(total)
    end)

    T.it("kaputte Zähler und unbekannte IDs zählen nicht, bleiben aber im Profil", function()
        local profile = fresh()
        profile.finds[findId("dunes", 1, 1)] = 0
        profile.finds[findId("dunes", 1, 2)] = -3
        profile.finds[findId("dunes", 1, 3)] = 0 / 0
        profile.finds[findId("dunes", 1, 4)] = "viel"
        profile.finds["alter_fund_xyz"] = 7
        T.expect(setOf(profile, "dunes_set_1").have).toBe(0)
        T.expect(Collection.distinctFound(profile)).toBe(0)
        T.expect(profile.finds.alter_fund_xyz).toBe(7)
        profile.finds[findId("dunes", 1, 1)] = 2
        T.expect(Collection.countOf(profile, findId("dunes", 1, 1))).toBe(2)
    end)

    T.it("summary liefert Zähler, Bonus und Bücher für den Client", function()
        local profile = fresh()
        fill(profile, "dunes", 1)
        profile.finds[findId("dunes", 1, 1)] = 3
        local summary = Collection.summary(profile)
        T.expect(summary.counts[findId("dunes", 1, 1)]).toBe(3)
        T.expect(summary.counts[findId("dunes", 2, 1)]).toBeNil()
        T.expect(summary.bonusBp).toBe(CollectionData.setBonusBp[1])
        T.expect(next(summary.books)).toBeNil()
    end)
end)

T.describe("Fund buchen", function()
    T.it("ein neuer Fund setzt den Zähler auf 1 und bringt keine Münzen", function()
        local profile = fresh()
        local result = Collection.record(profile, findId("dunes", 1, 1), BigNum.new(3))
        T.expect(result ~= nil).toBe(true)
        local recorded = result :: Collection.Recorded
        T.expect(recorded.isNew).toBe(true)
        T.expect(recorded.count).toBe(1)
        T.expect(recorded.coins).toBeNil()
        T.expect(profile.finds[findId("dunes", 1, 1)]).toBe(1)
        T.expect(BigNum.toNumber(BigNum.deserialize(profile.coins))).toBe(0)
        T.expect(recorded.setHave).toBe(1)
        T.expect(recorded.setSize).toBe(5)
    end)

    T.it("ein doppelter Fund erhöht den Zähler und wird sofort für seinen Wert verkauft", function()
        local profile = fresh()
        Collection.record(profile, findId("dunes", 1, 1), BigNum.new(3))
        local recorded = Collection.record(profile, findId("dunes", 1, 1), BigNum.new(40)) :: Collection.Recorded
        T.expect(recorded.isNew).toBe(false)
        T.expect(recorded.count).toBe(2)
        T.expect(BigNum.toNumber(recorded.coins :: any)).toBe(40)
        T.expect(BigNum.toNumber(BigNum.deserialize(profile.coins))).toBe(40)
        T.expect(recorded.setHave).toBe(1) -- Duplikat füllt keinen weiteren Slot
    end)

    T.it("Münzen aus Duplikaten laufen über den Zahlentyp, auch bei großen Ständen", function()
        local profile = fresh()
        profile.coins = BigNum.serialize(BigNum.new(1.5, 20))
        Collection.record(profile, findId("ruins", 6, 5), BigNum.new(4.05, 9))
        Collection.record(profile, findId("ruins", 6, 5), BigNum.new(4.05, 9))
        local coins = BigNum.deserialize(profile.coins)
        T.expect(coins.e).toBe(20)
        T.expect(coins.m).toBeCloseTo(1.5 + 4.05e-11, 1e-9)
    end)

    T.it("Set fertig und Zonenbuch fertig werden genau einmal gemeldet", function()
        local profile = fresh()
        for setIndex = 1, 6 do
            for slot = 1, 5 do
                local last = setIndex == 6 and slot == 5
                local recorded = Collection.record(profile, findId("oasis", setIndex, slot), BigNum.new(1)) :: Collection.Recorded
                T.expect(recorded.setCompleted).toBe(slot == 5)
                T.expect(recorded.zoneBookCompleted).toBe(last)
                if slot == 5 then
                    T.expect(recorded.bonusBpAfter - recorded.bonusBpBefore).toBe(CollectionData.setBonusBp[setIndex])
                else
                    T.expect(recorded.bonusBpAfter).toBe(recorded.bonusBpBefore)
                end
            end
        end
        -- Ein Duplikat meldet nichts mehr.
        local again = Collection.record(profile, findId("oasis", 6, 5), BigNum.new(1)) :: Collection.Recorded
        T.expect(again.setCompleted).toBe(false)
        T.expect(again.zoneBookCompleted).toBe(false)
    end)

    T.it("ein unbekannter Fund wird nicht gebucht", function()
        local profile = fresh()
        T.expect(Collection.record(profile, "gibt_es_nicht", BigNum.new(5))).toBeNil()
        T.expect(next(profile.finds)).toBeNil()
        T.expect(BigNum.toNumber(BigNum.deserialize(profile.coins))).toBe(0)
    end)

    T.it("ein kaputtes finds-Feld wird ersetzt, statt zu werfen", function()
        local profile = fresh()
        profile.finds = nil
        local recorded = Collection.record(profile, findId("dunes", 1, 1), BigNum.new(1))
        T.expect(recorded ~= nil).toBe(true)
        T.expect(profile.finds[findId("dunes", 1, 1)]).toBe(1)
    end)
end)

T.describe("Preis mit Sammlungsbonus", function()
    T.it("die Münzen pro Sand steigen mit jedem fertigen Set, in jeder Zone", function()
        local profile = fresh()
        T.expect(Collecting.pricePerSand(profile)).toBe(1)
        fill(profile, "oasis", 1)
        local bonus = 1 + CollectionData.setBonusBp[1] / 10000
        T.expect(Collecting.pricePerSand(profile)).toBeCloseTo(1 * bonus, 1e-12)
        profile.currentZone = "oasis"
        T.expect(Collecting.pricePerSand(profile)).toBeCloseTo(3 * bonus, 1e-12)
        T.expect(Collecting.priceOf(profile, "black")).toBeCloseTo(150 * bonus, 1e-12)
    end)

    T.it("Verkaufen zahlt den Bonus, auch beim gemischten Tank", function()
        local profile = fresh()
        fill(profile, "dunes", 1)
        local state = Collecting.newState(NOW)
        Collecting.addSand(profile, 10, "yellow")
        Collecting.addSand(profile, 10, "red")
        local earned = Collecting.sell(state, profile, NOW) :: BigNum.BigNum
        local bonus = 1 + CollectionData.setBonusBp[1] / 10000
        T.expect(BigNum.toNumber(earned)).toBe(math.floor((10 * 1 + 10 * 3) * bonus))
    end)

    T.it("der Fundwert bekommt den Sammlungsbonus nicht (Wert steht beim Fund fest)", function()
        local profile = fresh()
        for setIndex = 1, 6 do
            fill(profile, "dunes", setIndex)
        end
        local recorded = Collection.record(profile, findId("dunes", 1, 1), BigNum.new(3)) :: Collection.Recorded
        T.expect(BigNum.toNumber(recorded.coins :: any)).toBe(3)
    end)
end)

T.describe("Profil und Daten", function()
    T.it("Profile.sanitize entfernt kaputte Zähler in finds und rundet Brüche ab", function()
        local profile: any = fresh()
        profile.finds = {
            dunes_s1_1 = 2,
            dunes_s1_2 = 0,
            dunes_s1_3 = -1,
            dunes_s1_4 = 2.7,
            dunes_s1_5 = "x",
            alter_fund = 4,
        }
        local warnings = Profile.sanitize(profile, NOW)
        T.expect(#warnings > 0).toBe(true)
        T.expect(profile.finds).toEqual({ dunes_s1_1 = 2, dunes_s1_4 = 2, alter_fund = 4 })
    end)

    T.it("ein gespeichertes Profil mit Funden übersteht Migration und sanitize unverändert", function()
        local profile: any = fresh()
        profile.finds = { dunes_s1_1 = 3, oasis_s2_4 = 1 }
        local migrated = Profile.migrate(deepCopy(profile), nil, NOW)
        Profile.sanitize(migrated, NOW)
        T.expect((migrated :: any).finds).toEqual({ dunes_s1_1 = 3, oasis_s2_4 = 1 })
    end)

    T.it("DataCheck: die echten Daten sind gültig (150 Funde, 5 je Set, jede Seltenheit je Zone)", function()
        T.expect(#Finds.list).toBe(#Zones.list * 30)
        T.expect(DataCheck.run(DataCheck.defaults())).toEqual({})
    end)

    T.it("DataCheck lehnt kaputte Sammlungsdaten ab", function()
        local function broken(change: (data: any) -> ()): string
            local data: any = deepCopy(DataCheck.defaults())
            change(data)
            return table.concat(DataCheck.run(data), " | ")
        end
        local function expectFragment(text: string, fragment: string)
            T.expect(string.find(text, fragment, 1, true) ~= nil).toBe(true)
        end
        expectFragment(
            broken(function(data)
                table.remove(data.Finds.list)
            end),
            "braucht genau 5 Fundstücke"
        )
        expectFragment(
            broken(function(data)
                data.Finds.list[1].id = "falsche_id"
            end),
            "ID muss mit"
        )
        expectFragment(
            broken(function(data)
                for _, find in data.Finds.list do
                    if find.zoneId == "oasis" and find.rarityId == "mythic" then
                        find.rarityId = "epic"
                    end
                end
            end),
            `Zone "oasis" hat kein Fundstück der Seltenheit "mythic"`
        )
        expectFragment(
            broken(function(data)
                data.Collection.setBonusBp[3] = -5
            end),
            "Collection.setBonusBp[3]"
        )
        expectFragment(
            broken(function(data)
                data.Collection.zoneBooks[1].title = ""
            end),
            "Titel und Skin fehlen"
        )
        expectFragment(
            broken(function(data)
                table.remove(data.Collection.zoneBooks)
            end),
            `Zone "ruins" hat kein Zonenbuch`
        )
        expectFragment(
            broken(function(data)
                data.FindOdds.zoneOddsTable.canyon = "gibt_es_nicht"
            end),
            `Zone "canyon" zeigt auf keine bekannte Tabelle`
        )
        expectFragment(
            broken(function(data)
                data.FindOdds.firstFindGuaranteeSeconds = 0
            end),
            "firstFindGuaranteeSeconds"
        )
    end)
end)

T.finish()
