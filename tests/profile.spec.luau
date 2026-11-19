--!strict
-- Paket 0.3: Spielerprofil, Version und Migration.

local T = require("./lib/expect")
local Profile = require("../src/shared/Logic/Profile")
local Migrations = require("../src/shared/Logic/Migrations")
local BigNum = require("../src/shared/Logic/BigNum")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local Economy = require("../src/shared/Data/Economy")

local NOW = 1_700_000_000

-- Beispielmigration von Version 1 auf 2: Gems wandern in ein neues Feld, neues Feld "settings".
local exampleMigrations: { [number]: Migrations.Step } = {
    [1] = function(profile: any)
        profile.settings = { music = true }
        profile.legacyGems = profile.gems
        return profile
    end,
    [2] = function(profile: any) -- Paket 2.7: nur die Version zählt hier
        return profile
    end,
    [3] = function(profile: any) -- Paket 4.1: nur die Version zählt hier
        return profile
    end,
    [4] = function(profile: any) -- Paket 4.3: nur die Version zählt hier
        return profile
    end,
    [5] = function(profile: any) -- Paket 4.4: nur die Version zählt hier
        return profile
    end,
}

local function v1Profile(): any
    local profile: any = Profile.default(NOW)
    profile.coins = { m = 4.5, e = 7 }
    profile.gems = 120
    profile.nodes = { collect_tool_2 = true }
    profile.finds = { dune_find_1 = 3 }
    profile.version = 1 -- ein altes Profil: Standardprofile tragen immer die aktuelle Version
    profile.tankMix = nil
    profile.passes = nil -- gibt es seit Paket 4.4 (Version 6)
    profile.settings = nil
    return profile
end

T.describe("Profile", function()
    T.it("ein Spieler ohne Daten bekommt ein Standardprofil mit der aktuellen Version", function()
        local profile, status = Profile.migrate(nil, nil, NOW)
        T.expect(status).toBe("new")
        T.expect(profile.version).toBe(Profile.CURRENT_VERSION)
        -- 2 seit Paket 2.5 (gemischter Tank), 3 seit Paket 2.7 (runEarned), 4 seit Paket 4.1 (Belege als Liste),
        -- 5 seit Paket 4.3 (Ausrüstung und Sterne der Kisten-Items), 6 seit Paket 4.4 (Gamepasses, Einstellungen)
        T.expect(Profile.CURRENT_VERSION).toBe(6)
        T.expect(profile).toEqual(Profile.default(NOW))
    end)

    T.it("das Standardprofil hat alle Felder aus dem Plan", function()
        local profile: any = Profile.default(NOW)
        T.expect(profile.coins).toEqual({ m = 0, e = 0 })
        T.expect(profile.tank).toEqual({ m = 0, e = 0 })
        T.expect(profile.tankMix).toEqual({})
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
        T.expect(profile.purchaseLog).toEqual({})
        T.expect(profile.spent).toEqual({ robux = 0, count = 0 })
        T.expect(profile.boosts).toEqual({ coinsUntil = 0 })
        T.expect(profile.passes).toEqual({}) -- Paket 4.4
        T.expect(profile.settings).toEqual({ autoDig = true }) -- Paket 4.4
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

    T.it("ein Profil der Version 1 wird schrittweise auf die aktuelle Version gebracht", function()
        local original = v1Profile()
        local profile, status = Profile.migrate(original, exampleMigrations, NOW)
        local migrated: any = profile
        T.expect(status).toBe("ok")
        T.expect(migrated.version).toBe(6)
        -- Fehlende Felder werden tief aufgefüllt: settings.autoDig kommt seit Paket 4.4 aus dem Standardprofil.
        T.expect(migrated.settings).toEqual({ music = true, autoDig = true })
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

        -- Auch mit den echten Migrationen ist die nächste Version nach der aktuellen "zu neu".
        local next: any = v1Profile()
        next.version = Profile.CURRENT_VERSION + 1
        local _, status2 = Profile.migrate(next, nil, NOW)
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

T.describe("Profil Version 4 (Paket 4.1)", function()
    local function v3Profile(): any
        local profile: any = Profile.default(NOW)
        profile.version = 3
        profile.purchaseLog = nil
        profile.spent = nil
        return profile
    end

    T.it("Migration 3 auf 4 übernimmt alte PurchaseIds sortiert als Liste", function()
        local old = v3Profile()
        old.receipts = { zz_kauf = true, aa_kauf = true, mm_kauf = true, nein = false }
        old.gems = 1200
        local migrated, status = Profile.migrate(old, nil, NOW)
        local profile: any = migrated
        T.expect(status).toBe("ok")
        T.expect(profile.version).toBe(Profile.CURRENT_VERSION)
        T.expect(profile.receipts).toEqual({ "aa_kauf", "mm_kauf", "zz_kauf" })
        T.expect(profile.purchaseLog).toEqual({})
        T.expect(profile.spent).toEqual({ robux = 0, count = 0 })
        T.expect(profile.gems).toBe(1200)
        -- Das Original bleibt unverändert, eine zweite Migration ändert nichts.
        T.expect(old.receipts.zz_kauf).toBe(true)
        local again = Profile.migrate(migrated, nil, NOW + 5)
        T.expect(again).toEqual(migrated)
        T.expect(#Profile.sanitize(again, NOW)).toBe(0)
    end)

    T.it("Migration 3 auf 4 verkraftet leere, kaputte und gemischte Beleg-Tabellen", function()
        local empty = v3Profile()
        empty.receipts = {}
        T.expect((Profile.migrate(empty, nil, NOW) :: any).receipts).toEqual({})

        local missing = v3Profile()
        missing.receipts = nil
        T.expect((Profile.migrate(missing, nil, NOW) :: any).receipts).toEqual({})

        local text = v3Profile()
        text.receipts = "kaputt"
        T.expect((Profile.migrate(text, nil, NOW) :: any).receipts).toEqual({})

        -- Alte Schlüssel zuerst (sortiert), dann ein schon vorhandener Listenteil, ohne Doppelte.
        local mixed = v3Profile()
        mixed.receipts = { "liste_1", "b_kauf", b_kauf = true, a_kauf = 1700000000, [""] = true }
        T.expect((Profile.migrate(mixed, nil, NOW) :: any).receipts).toEqual({ "a_kauf", "b_kauf", "liste_1" })
    end)

    T.it("Migration 3 auf 4 ist bei gleichem Inhalt immer gleich (deterministisch)", function()
        local ids = {}
        for index = 1, 30 do
            ids[`kauf_{string.format("%02d", 31 - index)}`] = true
        end
        local first = v3Profile()
        first.receipts = table.clone(ids)
        local second = v3Profile()
        second.receipts = table.clone(ids)
        local a: any = Profile.migrate(first, nil, NOW)
        local b: any = Profile.migrate(second, nil, NOW)
        T.expect(a.receipts).toEqual(b.receipts)
        T.expect(a.receipts[1]).toBe("kauf_01")
        T.expect(a.receipts[30]).toBe("kauf_30")
    end)

    T.it("kaputte Gems werden repariert: NaN, unendlich, negativ, gebrochen, über maxGems", function()
        local cases = {
            { value = 0 / 0, expected = 0 },
            { value = math.huge, expected = 0 },
            { value = -50, expected = 0 },
            { value = 12.9, expected = 12 },
            { value = "viel", expected = 0 },
            { value = Economy.purchases.maxGems + 1, expected = Economy.purchases.maxGems },
            { value = 550, expected = 550 },
        }
        for _, case in cases do
            local profile: any = Profile.default(NOW)
            profile.gems = case.value
            local warnings = Profile.sanitize(profile, NOW)
            T.expect(profile.gems).toBe(case.expected)
            T.expect(#warnings).toBe(if case.value == 550 then 0 else 1)
        end
        -- Auch über die Migration eines alten Profils.
        local old = v3Profile()
        old.gems = -3.5
        local migrated: any = Profile.migrate(old, nil, NOW)
        Profile.sanitize(migrated, NOW)
        T.expect(migrated.gems).toBe(0)
    end)

    T.it("sanitize bringt Belege in Listenform, entfernt Ungültiges und kürzt auf receiptCacheSize", function()
        local profile: any = Profile.default(NOW)
        profile.receipts = { alt_1 = true, [1] = "neu_1", [2] = 5, [3] = "neu_1", [4] = "neu_2" }
        local warnings = Profile.sanitize(profile, NOW)
        T.expect(#warnings).toBe(1)
        T.expect(profile.receipts).toEqual({ "alt_1", "neu_1", "neu_2" })

        local long: any = Profile.default(NOW)
        local limit = Economy.purchases.receiptCacheSize
        for index = 1, limit + 7 do
            table.insert(long.receipts, `kauf_{index}`)
        end
        Profile.sanitize(long, NOW)
        T.expect(#long.receipts).toBe(limit)
        T.expect(long.receipts[1]).toBe("kauf_8") -- die ältesten sind raus
        T.expect(long.receipts[limit]).toBe(`kauf_{limit + 7}`)
    end)

    T.it("mit trimLists = false (beim Laden) werden Belege und Protokoll repariert, aber nicht gekürzt", function()
        local limit = Economy.purchases.receiptCacheSize
        local logLimit = Economy.purchases.purchaseLogSize
        -- Alte Tabellenform mit mehr PurchaseIds als receiptCacheSize: keine Reihenfolge bekannt.
        local old = v3Profile()
        old.receipts = {}
        for index = 1, limit + 50 do
            old.receipts[`alt_{string.format("%03d", index)}`] = true
        end
        local migrated: any = Profile.migrate(old, nil, NOW)
        T.expect(#migrated.receipts).toBe(limit + 50) -- die Migration kürzt nie
        for index = 1, logLimit + 5 do
            table.insert(migrated.purchaseLog, { purchaseId = `alt_{string.format("%03d", index)}`, productId = "gems_100", gems = 100, robux = 49, time = NOW })
        end
        migrated.receipts[limit + 51] = 5 -- ungültig: wird trotzdem entfernt
        local warnings = Profile.sanitize(migrated, NOW, { trimLists = false })
        T.expect(#warnings).toBe(1)
        T.expect(#migrated.receipts).toBe(limit + 50)
        T.expect(#migrated.purchaseLog).toBe(logLimit + 5)
        T.expect(migrated.receipts[1]).toBe("alt_001")
        -- Das nächste normale Speichern (ohne Option) kürzt.
        Profile.sanitize(migrated, NOW)
        T.expect(#migrated.receipts).toBe(limit)
        T.expect(migrated.receipts[1]).toBe("alt_051")
        T.expect(#migrated.purchaseLog).toBe(logLimit)
        -- trimLists = true und eine leere Option verhalten sich wie der Standard.
        local long: any = Profile.default(NOW)
        for index = 1, limit + 2 do
            table.insert(long.receipts, `kauf_{index}`)
        end
        local copy = table.clone(long)
        copy.receipts = table.clone(long.receipts)
        Profile.sanitize(long, NOW, { trimLists = true })
        Profile.sanitize(copy, NOW, {})
        T.expect(#long.receipts).toBe(limit)
        T.expect(copy.receipts).toEqual(long.receipts)
    end)

    T.it("sanitize: Belege ganz kaputt, die PurchaseIds kommen aus dem Kaufprotokoll zurück", function()
        local profile: any = Profile.default(NOW)
        profile.purchaseLog = {
            { purchaseId = "p1", productId = "gems_100", gems = 100, robux = 49, time = NOW },
            { purchaseId = "p2", productId = "gems_550", gems = 550, robux = 249, time = NOW + 1 },
        }
        profile.receipts = "kaputt"
        Profile.sanitize(profile, NOW)
        T.expect(profile.receipts).toEqual({ "p1", "p2" })
    end)

    T.it("sanitize repariert das Kaufprotokoll und kürzt es auf purchaseLogSize", function()
        local good = { purchaseId = "p1", productId = "gems_100", gems = 100, robux = 49, time = NOW }
        local profile: any = Profile.default(NOW)
        profile.purchaseLog = {
            good,
            { purchaseId = "", productId = "gems_100", gems = 100, robux = 49, time = NOW },
            { purchaseId = "p3", productId = "gems_100", gems = 0 / 0, robux = 49, time = NOW },
            "kein Eintrag",
            { purchaseId = "p5", productId = "gems_550", gems = 550, robux = 249, time = NOW, fn = function() end },
        }
        profile.purchaseLog.textschluessel = good
        local warnings = Profile.sanitize(profile, NOW)
        T.expect(#warnings).toBe(1)
        T.expect(profile.purchaseLog).toEqual({
            good,
            { purchaseId = "p5", productId = "gems_550", gems = 550, robux = 249, time = NOW },
        })

        local long: any = Profile.default(NOW)
        local limit = Economy.purchases.purchaseLogSize
        for index = 1, limit + 3 do
            table.insert(long.purchaseLog, { purchaseId = `p{index}`, productId = "gems_100", gems = 100, robux = 49, time = NOW + index })
        end
        Profile.sanitize(long, NOW)
        T.expect(#long.purchaseLog).toBe(limit)
        T.expect(long.purchaseLog[1].purchaseId).toBe("p4")

        local text: any = Profile.default(NOW)
        text.purchaseLog = 7
        Profile.sanitize(text, NOW)
        T.expect(text.purchaseLog).toEqual({})
    end)

    T.it("sanitize: spent wird ganz und nie negativ, kaputte Typen auf den Standard", function()
        local profile: any = Profile.default(NOW)
        profile.spent = { robux = -10, count = 2.5 }
        Profile.sanitize(profile, NOW)
        T.expect(profile.spent).toEqual({ robux = 0, count = 2 })
        profile.spent = { robux = 0 / 0, count = "x" }
        Profile.sanitize(profile, NOW)
        T.expect(profile.spent).toEqual({ robux = 0, count = 0 })
        profile.spent = "kaputt"
        Profile.sanitize(profile, NOW)
        T.expect(profile.spent).toEqual({ robux = 0, count = 0 })
    end)

    T.it("ein gültiges Profil mit Käufen bleibt unverändert und ohne Warnung", function()
        local profile: any = Profile.default(NOW)
        profile.gems = 650
        profile.receipts = { "p1", "p2" }
        profile.purchaseLog = {
            { purchaseId = "p1", productId = "gems_100", gems = 100, robux = 49, time = NOW },
            { purchaseId = "p2", productId = "gems_550", gems = 550, robux = 249, time = NOW },
        }
        profile.spent = { robux = 298, count = 2 }
        local before = table.clone(profile)
        T.expect(#Profile.sanitize(profile, NOW)).toBe(0)
        T.expect(profile).toEqual(before)
        T.expect(rawequal(profile.receipts, before.receipts)).toBe(true)
    end)
end)

T.finish()
