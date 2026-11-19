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
local Migrations = require("../src/shared/Logic/Migrations")

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
            "ID muss"
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

T.describe("Sicherheits-Review 2.6", function()
    local function broken(change: (data: any) -> ()): string
        local data: any = deepCopy(DataCheck.defaults())
        change(data)
        return table.concat(DataCheck.run(data), " | ")
    end
    local function expectFragment(text: string, fragment: string)
        T.expect(string.find(text, fragment, 1, true) ~= nil).toBe(true)
    end

    T.it("die 150 Fund-IDs sind fest: <Zone>_s<Set>_<Slot>, in Reihenfolge", function()
        local expected: { string } = {}
        for _, zone in Zones.list do
            for setIndex = 1, 6 do
                for slot = 1, 5 do
                    table.insert(expected, `{zone.id}_s{setIndex}_{slot}`)
                end
            end
        end
        T.expect(#Finds.list).toBe(#expected)
        for index, find in Finds.list do
            T.expect(find.id).toBe(expected[index])
        end
    end)

    T.it("DataCheck lehnt eine umbenannte Fund-ID mit gültigem Präfix ab", function()
        expectFragment(
            broken(function(data)
                data.Finds.list[1].id = "dunes_s1_skarabaeus"
            end),
            `ID muss "dunes_s1_1" lauten`
        )
        expectFragment(
            broken(function(data)
                data.Finds.list[2].id = data.Finds.list[1].id -- doppelte ID
            end),
            "doppelt"
        )
        expectFragment(
            broken(function(data)
                data.Finds.list[3].setId = "oasis_set_1" -- Zone passt nicht zum Set
            end),
            "Zone passt nicht zum Set"
        )
        expectFragment(
            broken(function(data)
                data.Finds.list[4].rarityId = "gibt_es_nicht"
            end),
            "unbekannte Seltenheit"
        )
    end)

    T.it("DataCheck wirft bei einem Eintrag ohne ID nicht, sondern meldet ihn", function()
        local text = broken(function(data)
            data.Finds.list[5].id = nil
        end)
        expectFragment(text, "braucht id, setId, zoneId und rarityId als Text")
    end)

    T.it("DataCheck begrenzt Fundchance, Wetter-Bonus, Wert und Sammlungsbonus gegen Tippfehler", function()
        expectFragment(
            broken(function(data)
                data.FindOdds.findChancePerSecond = 20000
            end),
            "findChancePerSecond darf höchstens"
        )
        expectFragment(
            broken(function(data)
                data.FindOdds.zoneFindChanceFactor.oasis = 900000
            end),
            "zoneFindChanceFactor"
        )
        expectFragment(
            broken(function(data)
                data.Weather.zones.oasis.findChanceBonusBp = 5000000
            end),
            "findChanceBonusBp darf höchstens"
        )
        expectFragment(
            broken(function(data)
                data.Rarities.byId.mythic.valueFactor = 1e9
            end),
            "valueFactor darf höchstens"
        )
        expectFragment(
            broken(function(data)
                data.Collection.setBonusBp[6] = 90000
            end),
            "Gesamtbonus aller Zonen"
        )
    end)

    T.it("die Seltenheiten je Zone: 6 Gewöhnlich, 9 Ungewöhnlich, 8 Selten, 4 Episch, 2 Legendär, 1 Mythisch", function()
        for _, zone in Zones.list do
            local counts: { [string]: number } = {}
            for _, find in Finds.list do
                if find.zoneId == zone.id then
                    counts[find.rarityId] = (counts[find.rarityId] or 0) + 1
                end
            end
            T.expect(counts).toEqual({ common = 6, uncommon = 9, rare = 8, epic = 4, legendary = 2, mythic = 1 })
        end
    end)

    T.it("Migration: ein Profil der Version 1 mit Funden behält sie, ein kaputtes finds-Feld wird ersetzt", function()
        local old: any = fresh()
        old.version = 1
        old.tankMix = nil
        old.finds = { dunes_s1_1 = 2 }
        local migrated, status = Profile.migrate(old, nil, NOW)
        T.expect(status).toBe("ok")
        T.expect((migrated :: any).finds).toEqual({ dunes_s1_1 = 2 })

        local broken1: any = fresh()
        broken1.finds = "kaputt"
        local fixed = Profile.migrate(broken1, nil, NOW)
        Profile.sanitize(fixed, NOW)
        T.expect((fixed :: any).finds).toEqual({})
        T.expect(Migrations.CURRENT_VERSION).toBe(5) -- 3 seit Paket 2.7 (runEarned), 4 seit Paket 4.1 (Belege), 5 seit Paket 4.3 (Ausrüstung)
    end)

    T.it("der Zähler eines Fundstücks ist bei 2^31 gedeckelt", function()
        local profile = fresh()
        profile.finds[findId("dunes", 1, 1)] = 2 ^ 31
        local recorded = Collection.record(profile, findId("dunes", 1, 1), BigNum.new(1)) :: Collection.Recorded
        T.expect(recorded.count).toBe(2 ^ 31)
        T.expect(profile.finds[findId("dunes", 1, 1)]).toBe(2 ^ 31)
    end)

    T.it("Sand ohne Mix-Eintrag bekommt den Sammlungsbonus wie der übrige Sand", function()
        local profile = fresh()
        fill(profile, "dunes", 1)
        profile.tank = BigNum.serialize(BigNum.new(100)) -- Debug-Wert ohne Mix
        local state = Collecting.newState(NOW)
        local earned = Collecting.sell(state, profile, NOW) :: BigNum.BigNum
        local bonus = 1 + CollectionData.setBonusBp[1] / 10000
        T.expect(BigNum.toNumber(earned)).toBe(math.floor(100 * bonus))
    end)

    T.it("Fundwert mit Bruchteil wird zu ganzen Münzen abgerundet", function()
        local FindRoll = require("../src/shared/Logic/FindRoll")
        local value = FindRoll.valueOf("dunes", "common", 1.5) -- 3 x 1 x 1,5 x 1 = 4,5
        T.expect(BigNum.toNumber(value)).toBe(4)
    end)
end)

T.finish()
