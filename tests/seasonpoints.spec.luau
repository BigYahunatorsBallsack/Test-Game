--!strict
-- Paket 5.5a: Event-Zone und Saison-Punkte. Zone offen nur in der Saison (Woche, Knoten), nie im
-- Profil, feste Zonen unverändert, Zurücksetzen beim Saisonende, Punkte nur aus Server-Sammelzeit,
-- Profilfeld (Laden, Säubern, Sandsturm), DataCheck, Event-Pool.

local T = require("./lib/expect")
local Zone = require("../src/shared/Logic/Zones")
local Seasons = require("../src/shared/Logic/Seasons")
local SeasonPass = require("../src/shared/Logic/SeasonPass")
local Profile = require("../src/shared/Logic/Profile")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local BigNum = require("../src/shared/Logic/BigNum")
local DataCheck = require("../src/shared/Logic/DataCheck")
local Collecting = require("../src/shared/Logic/Collecting")
local Zones = require("../src/shared/Data/Zones")
local World = require("../src/shared/Data/World")
local SandTypes = require("../src/shared/Data/SandTypes")
local SeasonData = require("../src/shared/Data/Seasons")
local PassData = require("../src/shared/Data/SeasonPass")
local Economy = require("../src/shared/Data/Economy")
local CrateItems = require("../src/shared/Data/CrateItems")
local Crates = require("../src/shared/Data/Crates")
local Rarities = require("../src/shared/Data/Rarities")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local FeatureData = require("../src/shared/Data/Features")

-- Überarbeitung Ü1: Die Event-Zone ist in Data/Features ausgeschaltet. Diese Tests prüfen ihr Verhalten
-- für die Zeit, in der sie wieder an ist (tests/features.spec.luau prüft den ausgeschalteten Fall).
FeatureData.systems.eventZone = true

local ZONE_ID = "season_camp"
local SEASON_ID = "season_1"
local START = Seasons.startOf(SeasonData.list[1]) :: number
local WEEK = Seasons.WEEK_SECONDS
local DAY = Seasons.SECONDS_PER_DAY
local NOW = START + 5 * DAY -- Woche 1
local PER_POINT = Economy.seasonPass.secondsPerPoint
local MAX_POINTS = SeasonPass.maxPoints(SEASON_ID)

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

local function profileWith(nodes: { string }): any
    local profile: any = Profile.default(NOW)
    for _, id in nodes do
        profile.nodes[id] = true
    end
    return profile
end

local function inEventZone(): any
    local area = World.zonesById[ZONE_ID]
    return { x = area.spawn.x, y = 6, z = area.spawn.z }
end

T.describe("Event-Zone offen nur in der Saison", function()
    T.it("mit Knoten und in der Saison offen, sonst nicht", function()
        local profile = profileWith({ "collect_tool_2" })
        T.expect(Zone.isUnlocked(profile, ZONE_ID, NOW)).toBe(true)
        T.expect(Zone.isUnlocked(profile, ZONE_ID, nil)).toBe(false) -- ohne Server-Zeit zu
        T.expect(Zone.isUnlocked(profile, ZONE_ID, START - 1)).toBe(false) -- vor dem Start
        T.expect(Zone.isUnlocked(profile, ZONE_ID, START + 4 * WEEK)).toBe(false) -- nach dem Ende
        T.expect(Zone.isUnlocked(profile, ZONE_ID, START)).toBe(true)
        T.expect(Zone.isUnlocked(profile, ZONE_ID, START + 4 * WEEK - 1)).toBe(true)
        T.expect(Zone.isUnlocked(profileWith({}), ZONE_ID, NOW)).toBe(false) -- ohne Knoten
    end)

    T.it("nur in Wochen mit zoneOpen", function()
        local data = { phases = deepCopy(SeasonData.phases), list = SeasonData.list }
        data.phases[2].zoneOpen = false
        T.expect(Seasons.zoneOpen(START + WEEK + 5, ZONE_ID, data)).toBe(false)
        T.expect(Seasons.zoneOpen(START + 5, ZONE_ID, data)).toBe(true)
        T.expect(Seasons.zoneOpen(START + 2 * WEEK + 5, ZONE_ID, data)).toBe(true)
    end)

    T.it("kaputte Zeit, fremde Zone und kein Text: zu", function()
        for _, bad in { 0 / 0, math.huge, -1, "x" :: any, nil :: any } do
            T.expect(Seasons.zoneOpen(bad, ZONE_ID)).toBe(false)
        end
        T.expect(Seasons.zoneOpen(NOW, "dunes")).toBe(false)
        T.expect(Seasons.zoneOpen(NOW, 5 :: any)).toBe(false)
    end)

    T.it("ein Eintrag in profile.zones öffnet die Event-Zone nie", function()
        local profile = profileWith({})
        profile.zones[ZONE_ID] = true
        T.expect(Zone.isUnlocked(profile, ZONE_ID, NOW)).toBe(false)
        T.expect(Zone.isUnlocked(profile, ZONE_ID, nil)).toBe(false)
    end)

    T.it("Event-Zone steht nie in profile.zones (unlockNew) und nur offen in unlockedMap", function()
        local profile = profileWith({ "collect_tool_2", "collect_tool_3", "collect_tool_4", "collect_tool_5" })
        Zone.unlockNew(profile)
        T.expect(profile.zones[ZONE_ID]).toBeNil()
        T.expect(Zone.unlockedMap(profile, NOW)[ZONE_ID]).toBe(true)
        T.expect(Zone.unlockedMap(profile, START - 1)[ZONE_ID]).toBeNil()
        T.expect(Zone.unlockedMap(profile)[ZONE_ID]).toBeNil()
        T.expect(Zone.unlockedMap(profile, NOW).dunes).toBe(true) -- feste Zonen bleiben
    end)

    T.it("Reisen: nur offen, sonst locked", function()
        local profile = profileWith({ "collect_tool_2" })
        local ok = Zone.canTravel(profile, ZONE_ID, 100, nil, nil, NOW)
        T.expect(ok).toBe(true)
        local closedOk, reason = Zone.canTravel(profile, ZONE_ID, 100, nil, nil, START + 4 * WEEK)
        T.expect(closedOk).toBe(false)
        T.expect(reason).toBe("locked")
        local _, noTime = Zone.canTravel(profile, ZONE_ID, 100, nil, nil, nil)
        T.expect(noTime).toBe("locked")
    end)
end)

T.describe("Saisonende in der Event-Zone", function()
    T.it("beim Ende wird der Spieler an den Spawn der ersten Zone zurückgesetzt", function()
        local profile = profileWith({ "collect_tool_2" })
        profile.currentZone = ZONE_ID
        T.expect(Zone.resolve(profile, inEventZone(), nil, NOW).kind).toBe("none")
        local result = Zone.resolve(profile, inEventZone(), nil, START + 4 * WEEK)
        T.expect(result.kind).toBe("reset")
        T.expect(result.zoneId).toBe(Zones.list[1].id)
        T.expect(result.pushTo).toEqual(World.zonesById[Zones.list[1].id].spawn)
    end)

    T.it("in einer festen Zone vor der gesperrten Event-Zone: blocked", function()
        local profile = profileWith({ "collect_tool_2" })
        local result = Zone.resolve(profile, inEventZone(), nil, START + 4 * WEEK)
        T.expect(result.kind).toBe("blocked")
        local enter = Zone.resolve(profile, inEventZone(), nil, NOW)
        T.expect(enter.kind).toBe("enter")
        T.expect(enter.zoneId).toBe(ZONE_ID)
    end)
end)

T.describe("Feste Zonen unverändert", function()
    T.it("Zones.list hat nur feste Zonen, byId kennt auch die Event-Zone", function()
        for _, zone in Zones.list do
            T.expect(zone.seasonId).toBeNil()
            T.expect(Zones.eventById[zone.id]).toBeNil()
        end
        T.expect(#Zones.list).toBe(5)
        T.expect(Zones.byId[ZONE_ID]).toBe(Zones.events[1])
        T.expect(Zones.events[1].seasonId).toBe(SEASON_ID)
    end)

    T.it("Event-Sand: eigene Sandsorte, Sammelrate und Preis folgen der Zone", function()
        local profile = profileWith({ "collect_tool_2" })
        profile.currentZone = ZONE_ID
        T.expect(Collecting.zoneOf(profile).id).toBe(ZONE_ID)
        T.expect(Collecting.sandTypeOf(profile)).toBe("season")
        T.expect(SandTypes.byId.season ~= nil).toBe(true)
    end)

    T.it("Sandsturm: setzt auf die erste Zone, Saison-Punkte bleiben", function()
        local profile = profileWith({ "collect_tool_2", "collect_tool_3", "collect_tool_4" })
        profile.currentZone = ZONE_ID
        profile.runEarned = BigNum.serialize(BigNum.new(1, 11))
        profile.coins = BigNum.serialize(BigNum.new(3, 7))
        SeasonPass.addSeconds(profile, SEASON_ID, PER_POINT * 3)
        local before = deepCopy(profile.seasons)
        local result, reason = Sandstorm.apply(profile)
        T.expect(reason).toBeNil()
        T.expect(result ~= nil).toBe(true)
        T.expect(profile.currentZone).toBe(Zones.list[1].id)
        T.expect(profile.zones[ZONE_ID]).toBeNil()
        T.expect(profile.seasons).toEqual(before)
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "seasons") ~= nil).toBe(true)
    end)
end)

T.describe("Saison-Punkte", function()
    T.it("secondsPerPoint Sekunden ergeben einen Punkt, dazwischen nichts", function()
        local profile = profileWith({})
        T.expect(SeasonPass.addSeconds(profile, SEASON_ID, PER_POINT - 1)).toBe(0)
        T.expect(SeasonPass.pointsOf(profile, SEASON_ID)).toBe(0)
        T.expect(SeasonPass.addSeconds(profile, SEASON_ID, 1)).toBe(1)
        T.expect(SeasonPass.pointsOf(profile, SEASON_ID)).toBe(1)
        T.expect(SeasonPass.addSeconds(profile, SEASON_ID, PER_POINT * 2.5)).toBe(2)
        T.expect(SeasonPass.pointsOf(profile, SEASON_ID)).toBe(3)
    end)

    T.it("Obergrenze: höchstens die Punkte der letzten Stufe, Sekunden laufen nicht weiter", function()
        local profile = profileWith({})
        T.expect(SeasonPass.addSeconds(profile, SEASON_ID, 1e12)).toBe(MAX_POINTS)
        T.expect(SeasonPass.pointsOf(profile, SEASON_ID)).toBe(MAX_POINTS)
        T.expect(profile.seasons[SEASON_ID].seconds).toBe(MAX_POINTS * PER_POINT)
        T.expect(SeasonPass.addSeconds(profile, SEASON_ID, 100)).toBe(0)
        T.expect(profile.seasons[SEASON_ID].seconds).toBe(MAX_POINTS * PER_POINT)
        T.expect(SeasonPass.tierOf(SeasonPass.pointsOf(profile, SEASON_ID), SEASON_ID)).toBe(#PassData.bySeason[SEASON_ID].tiers)
    end)

    T.it("kaputte Eingaben ändern nichts", function()
        local profile = profileWith({})
        local before = deepCopy(profile)
        for _, bad in { 0, -5, 0 / 0, math.huge, -math.huge, "10" :: any, nil :: any, true :: any } do
            T.expect(SeasonPass.addSeconds(profile, SEASON_ID, bad)).toBe(0)
        end
        T.expect(SeasonPass.addSeconds(profile, "unbekannt", 100)).toBe(0) -- Saison ohne Stufen
        T.expect(SeasonPass.addSeconds(profile, 7 :: any, 100)).toBe(0)
        T.expect(SeasonPass.addSeconds(nil, SEASON_ID, 100)).toBe(0)
        T.expect(SeasonPass.addSeconds({} :: any, SEASON_ID, 100)).toBe(0) -- Profil ohne seasons
        T.expect(profile).toEqual(before)
    end)

    T.it("Stufe aus Punkten: nie früher, Sprünge erreichen alle Stufen", function()
        local tiers = PassData.bySeason[SEASON_ID].tiers
        T.expect(SeasonPass.tierOf(0, SEASON_ID)).toBe(0)
        for index, tier in tiers do
            T.expect(SeasonPass.tierOf(tier.points - 1, SEASON_ID)).toBe(index - 1)
            T.expect(SeasonPass.tierOf(tier.points, SEASON_ID)).toBe(index)
        end
        T.expect(SeasonPass.tierOf(1e9, SEASON_ID)).toBe(#tiers)
        T.expect(SeasonPass.tierOf(0 / 0, SEASON_ID)).toBe(0)
    end)

    T.it("state: Punkte, Obergrenze, Stufe, Stufenzahl", function()
        local profile = profileWith({})
        SeasonPass.addSeconds(profile, SEASON_ID, PER_POINT * PassData.bySeason[SEASON_ID].tiers[1].points)
        local state = SeasonPass.state(profile, SEASON_ID)
        T.expect(state.points).toBe(PassData.bySeason[SEASON_ID].tiers[1].points)
        T.expect(state.maxPoints).toBe(MAX_POINTS)
        T.expect(state.tier).toBe(1)
        T.expect(state.tiers).toBe(#PassData.bySeason[SEASON_ID].tiers)
        T.expect(state.premium).toBe(false)
    end)

    T.it("es gibt keine Remote und keine Client-Eingabe für Punkte (nur addSeconds auf dem Server)", function()
        for name in RemoteSpec.byName do
            local lower = string.lower(tostring(name))
            T.expect(string.find(lower, "point") == nil and string.find(lower, "punkt") == nil).toBe(true)
        end
    end)
end)

T.describe("Profil", function()
    T.it("neues Profil hat seasons = {}, Standardprofile teilen keine Tabellen", function()
        local a: any = Profile.default(NOW)
        local b: any = Profile.default(NOW)
        T.expect(a.seasons).toEqual({})
        a.seasons.x = SeasonPass.newEntry()
        T.expect(b.seasons).toEqual({})
    end)

    T.it("alter Spielstand ohne seasons wird aufgefüllt (keine neue Version)", function()
        local old: any = Profile.default(NOW)
        old.seasons = nil
        local migrated, status = Profile.migrate(old, {}, NOW)
        T.expect(status).toBe("ok")
        T.expect((migrated :: any).seasons).toEqual({})
        T.expect((migrated :: any).version).toBe(Profile.default(NOW).version)
    end)

    T.it("Säubern: kaputte Zahlen, Typen und Abholmerker, unbekannte Saisons bleiben", function()
        local profile: any = Profile.default(NOW)
        profile.seasons = {
            season_1 = { seconds = 0 / 0, premium = "ja", claimed = { free = { ["3"] = true, ["x"] = true, ["0"] = true, ["2"] = false }, premium = "kaputt" } },
            future_season = { seconds = 90, premium = true, claimed = { free = { ["1"] = true }, premium = {} } },
            [5] = { seconds = 1 },
            broken = 12,
        }
        Profile.sanitize(profile, NOW)
        local seasons = profile.seasons
        T.expect(seasons.season_1.seconds).toBe(0)
        T.expect(seasons.season_1.premium).toBe(false)
        T.expect(seasons.season_1.claimed).toEqual({ free = { ["3"] = true }, premium = {} })
        T.expect(seasons.future_season).toEqual({ seconds = 90, premium = true, claimed = { free = { ["1"] = true }, premium = {} } })
        T.expect(seasons[5]).toBeNil()
        T.expect(seasons.broken).toBeNil()
    end)

    T.it("Säubern: unbekannte Felder eines Eintrags bleiben erhalten", function()
        local profile: any = Profile.default(NOW)
        profile.seasons = {
            season_1 = { seconds = 10, premium = true, claimed = { free = {}, premium = {} }, purchaseId = "abc", [3] = "x" },
        }
        Profile.sanitize(profile, NOW)
        T.expect(profile.seasons.season_1.purchaseId).toBe("abc")
        T.expect(profile.seasons.season_1[3]).toBeNil()
        T.expect(profile.seasons.season_1.seconds).toBe(10)
    end)

    T.it("Punkte überleben Speichern und Laden (Kopie des Profils)", function()
        local profile = profileWith({})
        SeasonPass.addSeconds(profile, SEASON_ID, PER_POINT * 7)
        local loaded = deepCopy(profile)
        Profile.sanitize(loaded, NOW)
        T.expect(SeasonPass.pointsOf(loaded, SEASON_ID)).toBe(7)
    end)
end)

T.describe("DataCheck", function()
    local function broken(change: (data: any) -> ()): { string }
        local data = deepCopy(DataCheck.defaults())
        change(data)
        return DataCheck.run(data)
    end
    local function expectError(errors: { string }, fragment: string)
        T.expect(#errors > 0).toBe(true)
        T.expect(table.concat(errors, "\n")).toContain(fragment)
    end

    T.it("die echten Tabellen bestehen", function()
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("Event-Zone: Sandsorte, Knoten, Saison, Doppelte", function()
        expectError(broken(function(d)
            d.Zones.events[1].sandTypeId = "nirgends"
        end), "unbekannte Sandsorte")
        expectError(broken(function(d)
            d.Zones.events[1].requires = "start"
        end), 'nicht "start"')
        expectError(broken(function(d)
            d.Zones.events[1].requires = "nirgends"
        end), 'Knoten "nirgends" fehlt')
        expectError(broken(function(d)
            d.Zones.events[1].requires = "sandstorm_1"
        end), "vergebenen Knoten")
        expectError(broken(function(d)
            d.Zones.events[1].seasonId = "season_9"
        end), "passt nicht zur Saison")
        expectError(broken(function(d)
            d.Seasons.list[1].zoneId = nil
        end), "genau einer Saison")
        expectError(broken(function(d)
            d.Zones.events[1].id = "dunes"
            d.Zones.eventById = { dunes = d.Zones.events[1] }
        end), "steht auch in Zones.list")
    end)

    T.it("Event-Zone braucht einen Bereich in der Welt, Bereiche kennen nur bekannte Zonen", function()
        expectError(broken(function(d)
            local area = d.World.zonesById[ZONE_ID]
            table.remove(d.World.zones, table.find(d.World.zones, area))
            d.World.zonesById[ZONE_ID] = nil
        end), `Zone "{ZONE_ID}" hat keinen Bereich`)
        expectError(broken(function(d)
            d.World.zonesById[ZONE_ID].id = "mars"
            d.World.zonesById.mars = d.World.zonesById[ZONE_ID]
            d.World.zonesById[ZONE_ID] = nil
        end), "Zone fehlt in Zones")
    end)

    T.it("Wirtschaft des Passes: secondsPerPoint, Abholfrist, Ersatz-Gems", function()
        expectError(broken(function(d)
            d.Economy.seasonPass.secondsPerPoint = 0
        end), "secondsPerPoint")
        expectError(broken(function(d)
            d.Economy.seasonPass.claimGraceDays = -1
        end), "claimGraceDays")
        expectError(broken(function(d)
            d.Economy.seasonPass.duplicateGems = 1.5
        end), "duplicateGems")
        expectError(broken(function(d)
            d.Economy.seasonPass = nil
        end), "Economy.seasonPass fehlt")
    end)

    T.it("Stufen: aufsteigend, feste Belohnungen, bekannte Items, keine Kisten", function()
        expectError(broken(function(d)
            d.SeasonPass.bySeason.season_1.tiers[2].points = d.SeasonPass.bySeason.season_1.tiers[1].points
        end), "über der vorigen Stufe")
        expectError(broken(function(d)
            d.SeasonPass.bySeason.season_1.tiers[1].free = { kind = "crate", crateId = "gold" }
        end), 'unbekannte Art "crate"')
        expectError(broken(function(d)
            d.SeasonPass.bySeason.season_1.tiers[1].free = { kind = "gems", amount = 0 }
        end), "amount muss")
        expectError(broken(function(d)
            d.SeasonPass.bySeason.season_1.tiers[1].premium = { kind = "item", itemId = "nirgends" }
        end), "unbekanntes Item")
        expectError(broken(function(d)
            d.SeasonPass.bySeason.season_1.tiers[1].premium = { kind = "item", itemId = "skin_common_1" }
        end), "kein Pass-Item")
        expectError(broken(function(d)
            d.SeasonPass.bySeason.season_1.tiers[1].premium = { kind = "gems", amount = 5000 }
        end), "liegen über der Obergrenze")
        expectError(broken(function(d)
            d.Economy.seasonPass.premiumGemsMaxPercent = 0
        end), "premiumGemsMaxPercent")
        expectError(broken(function(d)
            d.CrateItems.byId.skin_rare_4.crates = { "gold" }
        end), "steht in keiner Kiste")
        expectError(broken(function(d)
            d.CrateItems.byId.skin_rare_4.passOnly = "ja"
        end), "passOnly muss true oder false")
        expectError(broken(function(d)
            d.CrateItems.byId.skin_rare_3.passOnly = true
        end), "steht in keiner Kiste")
        expectError(broken(function(d)
            d.SeasonPass.bySeason.season_9 = { tiers = {} }
        end), "steht nicht in Seasons")
        expectError(broken(function(d)
            d.SeasonPass.bySeason.season_1.tiers = {}
        end), "mindestens eine Stufe")
    end)

    T.it("Pass-Items sind in Angeboten und als Ersatz an Tag 7 verboten", function()
        expectError(broken(function(d)
            d.Offers.byId.starter.items = { "skin_rare_4" }
        end), "Pass-Item")
        expectError(broken(function(d)
            d.Economy.daily.day7FallbackItemId = "skin_rare_4"
        end), "Pass-Item")
    end)

    T.it("Obergrenze der Premium-Gems fällt nie still weg, Zone und Boost-Sekunden sind geprüft", function()
        expectError(broken(function(d)
            d.Products.byId.season_pass = nil
        end), "nicht prüfbar")
        expectError(broken(function(d)
            d.GemPacks.list = {}
        end), "nicht prüfbar")
        expectError(broken(function(d)
            d.Seasons.list[1].zoneId = nil
        end), "keine zoneId")
        expectError(broken(function(d)
            d.SeasonPass.bySeason.season_1.tiers[2].free = { kind = "coinBoost", seconds = 99 * 3600 }
        end), "seconds muss eine ganze Zahl von 1 bis")
    end)
end)

T.describe("Pass-Items", function()
    T.it("kommen in keiner Kiste vor und haben nie einen Direktkauf-Preis", function()
        local DirectShop = require("../src/shared/Logic/DirectShop")
        for _, item in CrateItems.list do
            if item.passOnly == true then
                T.expect(#item.crates).toBe(0)
                for _, crate in Crates.list do
                    T.expect(table.find(item.crates, crate.id)).toBeNil()
                end
                T.expect(DirectShop.priceOf(item.id)).toBeNil()
            end
        end
    end)

    T.it("alle Item-Belohnungen der Stufen sind Pass-Items, jedes höchstens einmal", function()
        local seen: { [string]: boolean } = {}
        for _, tier in PassData.bySeason[SEASON_ID].tiers do
            for _, reward in { tier.free, tier.premium } do
                if reward.kind == "item" then
                    T.expect(CrateItems.byId[reward.itemId].passOnly).toBe(true)
                    T.expect(seen[reward.itemId]).toBeNil()
                    seen[reward.itemId] = true
                end
            end
        end
    end)
end)

T.describe("Event-Kiste: Pool vollständig", function()
    T.it("Saison-Pool hat in jeder Seltenheit mit Quote Items und Quoten wie die Goldkiste", function()
        local crate = Crates.byId[Seasons.at(NOW).active.crateId]
        T.expect(crate.eventOnly).toBe(true)
        T.expect(crate.odds).toBe(Crates.byId.gold.odds)
        for _, rarity in Rarities.list do
            if (crate.odds[rarity.id] or 0) <= 0 then
                continue -- Seltenheiten ohne Quote (Gold: keine gewöhnlichen) brauchen keine Items
            end
            local count = 0
            for _, item in CrateItems.list do
                if item.rarity == rarity.id and table.find(item.crates, crate.id) ~= nil then
                    count += 1
                end
            end
            T.expect(count >= 1).toBe(true)
        end
    end)
end)

T.finish()
