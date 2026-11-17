--!strict
-- Paket 0.3: Spielerprofil, Version und Migration.

local T = require("./lib/expect")
local Profile = require("../src/shared/Logic/Profile")
local Migrations = require("../src/shared/Logic/Migrations")
local BigNum = require("../src/shared/Logic/BigNum")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")

local NOW = 1_700_000_000

-- Beispielmigration von Version 1 auf 2: Gems wandern in ein neues Feld, neues Feld "settings".
local exampleMigrations: { [number]: Migrations.Step } = {
    [1] = function(profile: any)
        profile.settings = { music = true }
        profile.legacyGems = profile.gems
        return profile
    end,
}

local function v1Profile(): any
    local profile: any = Profile.default(NOW)
    profile.coins = { m = 4.5, e = 7 }
    profile.gems = 120
    profile.nodes = { collect_tool_2 = true }
    profile.finds = { dune_find_1 = 3 }
    return profile
end

T.describe("Profile", function()
    T.it("ein Spieler ohne Daten bekommt ein Standardprofil mit der aktuellen Version", function()
        local profile, status = Profile.migrate(nil, nil, NOW)
        T.expect(status).toBe("new")
        T.expect(profile.version).toBe(Profile.CURRENT_VERSION)
        T.expect(Profile.CURRENT_VERSION).toBe(1)
        T.expect(profile).toEqual(Profile.default(NOW))
    end)

    T.it("das Standardprofil hat alle Felder aus dem Plan", function()
        local profile: any = Profile.default(NOW)
        T.expect(profile.coins).toEqual({ m = 0, e = 0 })
        T.expect(profile.tank).toEqual({ m = 0, e = 0 })
        T.expect(profile.gems).toBe(0)
        T.expect(profile.nodes).toEqual({})
        T.expect(profile.zones).toEqual({ dunes = true })
        T.expect(profile.currentZone).toBe("dunes")
        T.expect(profile.finds).toEqual({})
        T.expect(profile.windCrystals).toBe(0)
        T.expect(profile.prestiges).toBe(0)
        T.expect(profile.pity.gold).toEqual({ sinceEpic = 0, sinceLegendary = 0 })
        T.expect(profile.inventory).toEqual({ skins = {}, companions = {}, toolVariants = {} })
        T.expect(profile.receipts).toEqual({})
        T.expect(profile.boosts).toEqual({ coinsUntil = 0 })
        T.expect(profile.daily).toEqual({ streak = 0, lastDay = 0 })
        T.expect(profile.lastSeen).toBe(NOW)
        T.expect(profile.createdAt).toBe(NOW)
    end)

    T.it("Standardprofile teilen keine Tabellen", function()
        local a: any = Profile.default(NOW)
        local b: any = Profile.default(NOW)
        a.nodes.x = true
        T.expect(b.nodes.x).toBeNil()
    end)

    T.it("ein Profil der Version 1 wird schrittweise auf Version 2 gebracht", function()
        local original = v1Profile()
        local profile, status = Profile.migrate(original, exampleMigrations, NOW)
        local migrated: any = profile
        T.expect(status).toBe("ok")
        T.expect(migrated.version).toBe(2)
        T.expect(migrated.settings).toEqual({ music = true })
        T.expect(migrated.legacyGems).toBe(120)
        -- Vorhandene Werte bleiben erhalten.
        T.expect(migrated.coins).toEqual({ m = 4.5, e = 7 })
        T.expect(migrated.gems).toBe(120)
        T.expect(migrated.nodes).toEqual({ collect_tool_2 = true })
        T.expect(migrated.finds).toEqual({ dune_find_1 = 3 })
        -- Das Original wird nicht verändert.
        T.expect(original.version).toBe(1)
        T.expect(original.settings).toBeNil()
    end)

    T.it("fehlende Felder bekommen Standardwerte (tief)", function()
        local data: any = v1Profile()
        data.boosts = nil
        data.daily = { streak = 3 } -- lastDay fehlt
        data.inventory = { skins = { sand_skin = 1 } } -- companions und toolVariants fehlen
        data.pity = {} -- gold fehlt
        local profile, status = Profile.migrate(data, exampleMigrations, NOW)
        local migrated: any = profile
        T.expect(status).toBe("ok")
        T.expect(migrated.boosts).toEqual({ coinsUntil = 0 })
        T.expect(migrated.daily).toEqual({ streak = 3, lastDay = 0 })
        T.expect(migrated.inventory.skins).toEqual({ sand_skin = 1 })
        T.expect(migrated.inventory.companions).toEqual({})
        T.expect(migrated.inventory.toolVariants).toEqual({})
        T.expect(migrated.pity.gold).toEqual({ sinceEpic = 0, sinceLegendary = 0 })
    end)

    T.it("eine zweite Migration desselben Profils ändert nichts mehr", function()
        local first = Profile.migrate(v1Profile(), exampleMigrations, NOW)
        local second, status = Profile.migrate(first, exampleMigrations, NOW + 999)
        T.expect(status).toBe("ok")
        T.expect(second).toEqual(first)
    end)

    T.it("ein aktuelles Profil bleibt mit den echten Migrationen unverändert", function()
        local current = Profile.default(NOW)
        local profile, status = Profile.migrate(current, nil, NOW + 5)
        T.expect(status).toBe("ok")
        T.expect(profile).toEqual(current)
    end)

    T.it("ein Profil mit höherer Version wird nicht migriert und als nicht speichern markiert", function()
        local future: any = v1Profile()
        future.version = 9
        future.zukunftsfeld = { a = 1 }
        local profile, status = Profile.migrate(future, exampleMigrations, NOW)
        T.expect(status).toBe("too_new")
        T.expect(rawequal(profile, future)).toBe(true)
        T.expect((profile :: any).version).toBe(9)
        T.expect((profile :: any).zukunftsfeld).toEqual({ a = 1 })
        T.expect((profile :: any).boosts).toBe((future :: any).boosts)

        -- Auch mit den echten Migrationen (Version 1) ist Version 2 "zu neu".
        local v2: any = v1Profile()
        v2.version = 2
        local _, status2 = Profile.migrate(v2, nil, NOW)
        T.expect(status2).toBe("too_new")
    end)

    T.it("unbekannte Felder und Knoten-IDs bleiben erhalten und stören das Laden nicht", function()
        local data: any = v1Profile()
        data.nodes = { collect_tool_2 = true, alter_knoten_xyz = true, collect_tool_3 = true }
        data.unbekannt = "bleibt"
        local profile, status = Profile.migrate(data, nil, NOW)
        local migrated: any = profile
        T.expect(status).toBe("ok")
        T.expect(migrated.nodes.alter_knoten_xyz).toBe(true)
        T.expect(migrated.unbekannt).toBe("bleibt")
        T.expect(Profile.ownedKnownNodes(profile, UpgradeTree.byId)).toEqual({
            "collect_tool_2",
            "collect_tool_3",
        })
    end)

    T.it("eine Lücke in den Migrationen ist ein Fehler, das Original bleibt unberührt", function()
        local original = v1Profile()
        local gap: { [number]: Migrations.Step } = {
            [2] = function(p: any)
                return p
            end,
        }
        T.expect(function()
            Profile.migrate(original, gap, NOW)
        end).toThrow("keine Migration")
        T.expect(original.version).toBe(1)
    end)

    T.it("BigNum-Werte im Profil überstehen Speichern und Laden", function()
        local value = BigNum.new(123456, 20)
        local stored = BigNum.serialize(value)
        local loaded = BigNum.deserialize(stored)
        T.expect(loaded).toEqual(value)
        T.expect(value.m).toBeCloseTo(1.23456, 1e-12)
        T.expect(value.e).toBe(25)
        T.expect(BigNum.deserialize(nil)).toEqual({ m = 0, e = 0 })
        T.expect(BigNum.deserialize({ m = "x", e = 1 })).toEqual({ m = 0, e = 0 })
        T.expect(BigNum.new(0, 5)).toEqual({ m = 0, e = 0 })
        -- Rechnen (Paket 1.2) und Anzeige (Paket 1.3) sind fertig, die Details prüft bignum.spec.
        T.expect(BigNum.add(BigNum.zero(), BigNum.zero())).toEqual({ m = 0, e = 0 })
        T.expect(BigNum.format(BigNum.zero())).toBe("0")
    end)
end)

T.finish()
