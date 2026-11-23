--!strict
-- Lune-Tests für Soziales (Paket 5.7): Freunde-Faktor, Sammlungswert, Wochenindex, Ranglisten-Einträge,
-- Auszug, Besuchsregel und Ansicht. Die Anbindung der Services kommt weiter unten dazu.
-- Ausführen: lune run tests/social.spec

local T = require("./lib/expect")
local Social = require("../src/shared/Logic/Social")
local DataCheck = require("../src/shared/Logic/DataCheck")
local SocialData = require("../src/shared/Data/Social")
local FindsData = require("../src/shared/Data/Finds")
local RaritiesData = require("../src/shared/Data/Rarities")
local Seasons = require("../src/shared/Logic/Seasons")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local fs = require("@lune/fs")

local FRIENDS_SOURCE: string = fs.readFile("src/server/Services/Friends.luau")
local BOARD_SOURCE: string = fs.readFile("src/server/Services/Leaderboard.luau")
local SAND_SOURCE: string = fs.readFile("src/server/Services/Sand.luau")
local OFFLINE_SOURCE: string = fs.readFile("src/server/Services/Offline.luau")
local OFFLINE_LOGIC_SOURCE: string = fs.readFile("src/shared/Logic/Offline.luau")
local BOOTSTRAP_SOURCE: string = fs.readFile("src/server/init.server.luau")
local MENU_SOURCE: string = fs.readFile("src/client/Controllers/SocialMenu.luau")
local CLIENT_BOOTSTRAP_SOURCE: string = fs.readFile("src/client/init.client.luau")

local WEEK = Seasons.WEEK_SECONDS
local MONDAY = 4 * Seasons.SECONDS_PER_DAY -- 5. Januar 1970, 0 Uhr UTC

local function deepCopy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in value do
        copy[deepCopy(key)] = deepCopy(inner)
    end
    return copy
end

local function profileWith(ids: { string }): any
    local finds: { [string]: number } = {}
    for _, id in ids do
        finds[id] = 1
    end
    return { finds = finds }
end

T.describe("Freunde-Faktor", function()
    T.it("0 Freunde 1, jeder Freund +10 %, höchstens 1,5", function()
        T.expect(Social.bonusFactor(0)).toBe(1)
        T.expect(Social.bonusFactor(1)).toBeCloseTo(1.1, 1e-9)
        T.expect(Social.bonusFactor(3)).toBeCloseTo(1.3, 1e-9)
        T.expect(Social.bonusFactor(5)).toBeCloseTo(1.5, 1e-9)
        T.expect(Social.bonusFactor(9)).toBeCloseTo(1.5, 1e-9)
        T.expect(Social.bonusFactor(1e9)).toBeCloseTo(1.5, 1e-9)
    end)

    T.it("kaputte Zahlen und kaputte Daten ergeben 1", function()
        T.expect(Social.bonusFactor(-2)).toBe(1)
        T.expect(Social.bonusFactor(0 / 0)).toBe(1)
        T.expect(Social.bonusFactor(math.huge)).toBe(1)
        T.expect(Social.bonusFactor("3" :: any)).toBe(1)
        T.expect(Social.bonusFactor(nil)).toBe(1)
        T.expect(Social.bonusFactor(2, { Social = { friends = { perFriendBp = -5, maxBp = 100 } } })).toBe(1)
        T.expect(Social.bonusFactor(2, { Social = { friends = "x" } })).toBe(1)
    end)

    T.it("Werte kommen aus den Daten", function()
        local data = { Social = { friends = { perFriendBp = 500, maxBp = 1500 } } }
        T.expect(Social.bonusFactor(2, data)).toBeCloseTo(1.1, 1e-9)
        T.expect(Social.bonusFactor(10, data)).toBeCloseTo(1.15, 1e-9)
    end)
end)

T.describe("Freunde zählen", function()
    T.it("nie sich selbst, nur Anwesende, jede UserId einmal, nur bekannte Freunde", function()
        local known = { [2] = true, [3] = true, [4] = false, [9] = true }
        T.expect(Social.countFriends(1, { 1, 2, 3, 4 }, known)).toBe(2)
        T.expect(Social.countFriends(2, { 1, 2, 3 }, known)).toBe(1) -- 2 zählt sich nicht
        T.expect(Social.countFriends(1, { 2, 2, 2 }, known)).toBe(1)
        T.expect(Social.countFriends(1, { 1 }, known)).toBe(0)
        T.expect(Social.countFriends(1, { 5, 6 }, known)).toBe(0) -- 9 ist nicht anwesend
        T.expect(Social.countFriends(1, nil, known)).toBe(0)
        T.expect(Social.countFriends(1, { 2 }, nil)).toBe(0)
    end)

    T.it("der Deckel greift auch bei vielen Freunden", function()
        local present: { number } = {}
        local known: { [number]: boolean } = {}
        for index = 2, 40 do
            table.insert(present, index)
            known[index] = true
        end
        T.expect(Social.countFriends(1, present, known)).toBe(39)
        T.expect(Social.bonusFactor(39)).toBeCloseTo(1.5, 1e-9)
    end)
end)

T.describe("Schreibentscheidung der Rangliste", function()
    T.it("schreibt bei erstem Wert, höherem Wert und neuer Woche, sonst nicht", function()
        T.expect(Social.shouldWrite(100, nil, nil, "store_1")).toBe(true)
        T.expect(Social.shouldWrite(100, 100, "store_1", "store_1")).toBe(false)
        T.expect(Social.shouldWrite(90, 100, "store_1", "store_1")).toBe(false) -- nie senken
        T.expect(Social.shouldWrite(120, 100, "store_1", "store_1")).toBe(true)
        T.expect(Social.shouldWrite(100, 100, "store_1", "store_2")).toBe(true) -- neue Woche, gleicher Wert
    end)

    T.it("kein Wert, kaputter Wert oder kein Speichername: nichts schreiben", function()
        T.expect(Social.shouldWrite(0, nil, nil, "store_1")).toBe(false)
        T.expect(Social.shouldWrite(-5, nil, nil, "store_1")).toBe(false)
        T.expect(Social.shouldWrite(0 / 0, nil, nil, "store_1")).toBe(false)
        T.expect(Social.shouldWrite(10, nil, nil, nil)).toBe(false)
    end)
end)

T.describe("Sammlungswert", function()
    T.it("leere und kaputte Sammlungen ergeben 0", function()
        T.expect(Social.collectionValue({ finds = {} })).toBe(0)
        T.expect(Social.collectionValue({})).toBe(0)
        T.expect(Social.collectionValue({ finds = { dunes_s1_1 = 0 / 0 } })).toBe(0)
        T.expect(Social.collectionValue({ finds = { dunes_s1_1 = -3 } })).toBe(0)
    end)

    T.it("Summe der Wertfaktoren aller verschiedenen bekannten Fundstücke, Doppelte zählen einmal", function()
        local first = FindsData.list[1]
        local factor = RaritiesData.byId[first.rarityId].valueFactor
        T.expect(Social.collectionValue({ finds = { [first.id] = 1 } })).toBe(factor)
        T.expect(Social.collectionValue({ finds = { [first.id] = 500 } })).toBe(factor)
        local all: { string } = {}
        local expected = 0
        for _, find in FindsData.list do
            table.insert(all, find.id)
            expected += RaritiesData.byId[find.rarityId].valueFactor
        end
        T.expect(Social.collectionValue(profileWith(all))).toBe(expected)
    end)

    T.it("unbekannte IDs zählen nicht", function()
        T.expect(Social.collectionValue({ finds = { gibtsnicht = 5 } })).toBe(0)
    end)
end)

T.describe("Wochenindex", function()
    T.it("Montag 0 Uhr UTC beginnt eine neue Woche, das Ende ist ausschließend", function()
        T.expect(Social.weekIndex(MONDAY)).toBe(0)
        T.expect(Social.weekIndex(MONDAY + WEEK - 1)).toBe(0)
        T.expect(Social.weekIndex(MONDAY + WEEK)).toBe(1)
        T.expect(Social.weekIndex(MONDAY + 52 * WEEK)).toBe(52)
    end)

    T.it("kaputte Zeit ergibt nil", function()
        T.expect(Social.weekIndex(nil)).toBeNil()
        T.expect(Social.weekIndex(0 / 0)).toBeNil()
        T.expect(Social.weekIndex(math.huge)).toBeNil()
        T.expect(Social.weekIndex(-5)).toBeNil()
        T.expect(Social.weekIndex(MONDAY - 1)).toBeNil()
        T.expect(Social.weekIndex("x" :: any)).toBeNil()
    end)

    T.it("Sekunden bis zum Wochenende: ab 1, am Montag 0 Uhr genau eine Woche", function()
        T.expect(Social.secondsLeftInWeek(MONDAY)).toBe(WEEK)
        T.expect(Social.secondsLeftInWeek(MONDAY + WEEK - 1)).toBe(1)
        T.expect(Social.secondsLeftInWeek(MONDAY + WEEK)).toBe(WEEK)
        T.expect(Social.secondsLeftInWeek(nil)).toBe(0)
    end)

    T.it("der Speichername enthält den Index, Studio hat einen eigenen Namen", function()
        local live = Social.weekStoreName(MONDAY + 3 * WEEK, false) :: string
        local studio = Social.weekStoreName(MONDAY + 3 * WEEK, true) :: string
        T.expect(live).toBe(`{SocialData.leaderboard.store}_3`)
        T.expect(studio).toBe(`{SocialData.leaderboard.store}{SocialData.leaderboard.studioSuffix}_3`)
        T.expect(live ~= studio).toBe(true)
        T.expect(Social.weekStoreName(nil, false)).toBeNil()
        T.expect(Social.showcaseStoreName(false) ~= Social.showcaseStoreName(true)).toBe(true)
    end)
end)

T.describe("Ranglisten-Einträge", function()
    T.it("nur ganze UserIds, endliche Werte über 0, jede UserId einmal, absteigend, höchstens topCount", function()
        local raw: { any } = {
            { userId = 5, value = 100 },
            { userId = 6, value = 300 },
            { userId = 7, value = 300 },
            { userId = 6, value = 999 }, -- doppelt: zählt nur der erste
            { userId = 0, value = 50 },
            { userId = -3, value = 50 },
            { userId = 2.5, value = 50 },
            { userId = 8, value = 0 },
            { userId = 9, value = -1 },
            { userId = 10, value = 0 / 0 },
            { userId = 11, value = math.huge },
            { userId = "x", value = 10 },
            "kaputt",
            { key = "12", value = 40 },
        }
        local clean = Social.cleanEntries(raw)
        local ids = {}
        for _, entry in clean do
            table.insert(ids, entry.userId)
        end
        T.expect(ids).toEqual({ 6, 7, 5, 12 })
        T.expect(clean[1].rank).toBe(1)
        T.expect(clean[4].rank).toBe(4)
        T.expect(clean[1].value).toBe(300)
    end)

    T.it("höchstens topCount Plätze und kaputte Eingaben ergeben eine leere Liste", function()
        local raw: { any } = {}
        for index = 1, 40 do
            table.insert(raw, { userId = index, value = index })
        end
        local clean = Social.cleanEntries(raw)
        T.expect(#clean).toBe(SocialData.leaderboard.topCount)
        T.expect(clean[1].userId).toBe(40)
        T.expect(Social.cleanEntries(nil)).toEqual({})
        T.expect(Social.cleanEntries("x")).toEqual({})
    end)
end)

T.describe("Auszug (Showcase)", function()
    T.it("enthält nur bekannte besessene IDs in der Reihenfolge der Tabelle, sonst nichts", function()
        local profile = { finds = { [FindsData.list[3].id] = 2, [FindsData.list[1].id] = 1, gibtsnicht = 4 }, coins = "123", gems = 9 }
        local showcase = Social.buildShowcase(profile, 1_700_000_000)
        T.expect(showcase.owned).toEqual({ FindsData.list[1].id, FindsData.list[3].id })
        T.expect(showcase.v).toBe(Social.SHOWCASE_VERSION)
        local keys = {}
        for key in showcase do
            table.insert(keys, key)
        end
        table.sort(keys)
        T.expect(keys).toEqual({ "owned", "t", "v" })
    end)

    T.it("nie mehr Einträge als der Katalog", function()
        local all: { string } = {}
        for _, find in FindsData.list do
            table.insert(all, find.id)
        end
        T.expect(#Social.buildShowcase(profileWith(all), 1).owned).toBe(#FindsData.list)
    end)

    T.it("ein kaputter oder fremder Auszug wird beim Lesen bereinigt", function()
        T.expect(Social.cleanShowcase(nil)).toBeNil()
        T.expect(Social.cleanShowcase("x")).toBeNil()
        T.expect(Social.cleanShowcase({ v = 99, owned = {} })).toBeNil()
        T.expect(Social.cleanShowcase({ v = Social.SHOWCASE_VERSION, owned = "x" })).toBeNil()
        local first = FindsData.list[1].id
        local owned = Social.cleanShowcase({ v = Social.SHOWCASE_VERSION, owned = { first, first, "gibtsnicht", 5, {} } }) :: any
        T.expect(owned).toEqual({ [first] = true })
    end)
end)

T.describe("Freundesliste und Besuch", function()
    T.it("säubert die Liste: ganze UserIds, jede einmal, Namen gekürzt, höchstens maxFriends", function()
        local raw: { any } = {
            { Id = 5, Username = "eins", DisplayName = "Eins" },
            { Id = 5, Username = "doppelt" },
            { Id = 6, Username = "zwei", DisplayName = "" },
            { Id = 0, Username = "null" },
            { Id = -2, Username = "minus" },
            { Id = 2.5, Username = "halb" },
            { Id = "x", Username = "text" },
            "kaputt",
            { Id = 7, Username = string.rep("n", 500) },
        }
        local list = Social.cleanFriends(raw)
        T.expect(#list).toBe(3)
        T.expect(list[1]).toEqual({ userId = 5, name = "Eins" })
        T.expect(list[2]).toEqual({ userId = 6, name = "zwei" })
        T.expect(#list[3].name).toBe(Social.MAX_NAME_LENGTH)
        local many: { any } = {}
        for index = 1, 500 do
            table.insert(many, { Id = index, Username = "u" })
        end
        T.expect(#Social.cleanFriends(many)).toBe(SocialData.leaderboard.maxFriends)
        T.expect(Social.cleanFriends(nil)).toEqual({})
    end)

    T.it("der Besuch wählt nur einen Platz der Server-Liste, alles andere ergibt nil", function()
        local list = Social.cleanFriends({ { Id = 5, Username = "a" }, { Id = 6, Username = "b" } })
        T.expect((Social.friendAt(list, 1) :: any).userId).toBe(5)
        T.expect((Social.friendAt(list, 2) :: any).userId).toBe(6)
        T.expect(Social.friendAt(list, 3)).toBeNil()
        for _, bad in { 0, -1, 1.5, 0 / 0, math.huge, SocialData.leaderboard.maxFriends + 1 } do
            T.expect(Social.friendAt(list, bad :: any)).toBeNil()
        end
        T.expect(Social.friendAt(list, "1" :: any)).toBeNil()
        T.expect(Social.friendAt(nil, 1)).toBeNil()
        T.expect(Social.friendAt({ "kaputt" }, 1)).toBeNil()
    end)
end)

T.describe("Ansicht", function()
    T.it("Name, Wert, Anzahl, besessene IDs und Set-Fortschritt, nur einfache Werte", function()
        local first = FindsData.list[1]
        local owned: { [string]: boolean } = { [first.id] = true, gibtsnicht = true }
        local view = Social.view(owned, "Freund")
        T.expect(view.userId).toBeNil() -- der Client braucht keine UserId
        T.expect(view.name).toBe("Freund")
        T.expect(view.value).toBe(RaritiesData.byId[first.rarityId].valueFactor)
        T.expect(view.found).toBe(1)
        T.expect(view.total).toBe(#FindsData.list)
        T.expect(view.owned).toEqual({ first.id })
        T.expect(#view.sets).toBe(#FindsData.sets)
        T.expect(view.sets[1].have).toBe(1)
        T.expect(view.sets[1].complete).toBe(false)
    end)

    T.it("ein langer oder kaputter Name wird gekürzt", function()
        T.expect(#Social.view({}, string.rep("a", 500)).name).toBe(Social.MAX_NAME_LENGTH)
        T.expect(Social.view({}, 5 :: any).name).toBe("?")
    end)
end)

T.describe("DataCheck", function()
    local function broken(change: (data: any) -> ()): string
        local data = deepCopy(DataCheck.defaults())
        change(data)
        return table.concat(DataCheck.run(data), "\n")
    end

    T.it("die echten Tabellen bestehen", function()
        T.expect(DataCheck.run()).toEqual({})
    end)

    T.it("meldet kaputte Werte", function()
        T.expect(broken(function(d)
            d.Social.friends.perFriendBp = 0
        end)).toContain("perFriendBp")
        T.expect(broken(function(d)
            d.Social.friends.maxBp = 1.5
        end)).toContain("maxBp")
        T.expect(broken(function(d)
            d.Social.friends.maxBp = d.Social.friends.perFriendBp - 1
        end)).toContain("mindestens")
        T.expect(broken(function(d)
            d.Social.friends.maxBp = 50000
        end)).toContain("maxBp")
        T.expect(broken(function(d)
            d.Social.leaderboard.writeSeconds = 1
        end)).toContain("writeSeconds")
        T.expect(broken(function(d)
            d.Rarities.list[2].valueFactor = 2.5
        end)).toContain("ganzzahlig")
        T.expect(broken(function(d)
            d.Social.leaderboard.topCount = 0
        end)).toContain("topCount")
        T.expect(broken(function(d)
            d.Social.leaderboard.maxFriends = 0
        end)).toContain("maxFriends")
        T.expect(broken(function(d)
            d.Social.leaderboard.readSeconds = 0 / 0
        end)).toContain("readSeconds")
        T.expect(broken(function(d)
            d.Social.leaderboard.store = ""
        end)).toContain("store")
        T.expect(broken(function(d)
            d.Social.leaderboard.showcaseStore = d.Social.leaderboard.store
        end)).toContain("verschieden")
        T.expect(broken(function(d)
            d.Social.friends = nil
        end)).toContain("Social.friends")
    end)
end)

-- Der Service ohne Kommentarzeilen (die Kopfzeilen nennen die Aufrufe auch).
local codeLines: { string } = {}
for line in string.gmatch(BOARD_SOURCE, "[^\n]*") do
    if string.match(line, "^%s*%-%-") == nil then
        table.insert(codeLines, line)
    end
end
local CODE_ONLY = "\n" .. table.concat(codeLines, "\n")

T.describe("Anbindung der Services", function()
    T.it("Friends und Leaderboard stehen am Ende von SERVICE_NAMES, die Remotes gibt es genau einmal", function()
        T.expect(string.find(BOOTSTRAP_SOURCE, '"Codes", "Friends", "Leaderboard" }', 1, true) ~= nil).toBe(true)
        for _, name in { "GetLeaderboard", "GetFriends", "ViewCollection" } do
            T.expect(RemoteSpec.byName[name].direction).toBe("ClientToServer")
            T.expect(string.find(BOARD_SOURCE, `Net.on("{name}"`, 1, true) ~= nil).toBe(true)
        end
    end)

    T.it("der Freunde-Faktor geht über Sand in den Münz-Faktor, der Offline-Ertrag kennt ihn nicht", function()
        T.expect(string.find(SAND_SOURCE, "options.coinMultiplier *= friends", 1, true) ~= nil).toBe(true)
        T.expect(string.find(SAND_SOURCE, "function Sand.setFriendFactor", 1, true) ~= nil).toBe(true)
        T.expect(string.find(FRIENDS_SOURCE, "Sand.setFriendFactor", 1, true) ~= nil).toBe(true)
        T.expect(string.find(FRIENDS_SOURCE, "bonusFactor", 1, true) ~= nil).toBe(true)
        T.expect(string.find(OFFLINE_SOURCE, "Friend", 1, true)).toBeNil()
        T.expect(string.find(OFFLINE_LOGIC_SOURCE, "Friend", 1, true)).toBeNil()
        for _, source in { OFFLINE_SOURCE, OFFLINE_LOGIC_SOURCE } do
            T.expect(string.find(source, "optionsFor", 1, true)).toBeNil() -- das wäre der Weg zum Freunde-Faktor
            T.expect(string.find(source, "optionsOf", 1, true)).toBeNil()
        end
    end)

    T.it("Roblox-Aufrufe laufen in pcall, der Client nennt nie einen Spieler", function()
        for _, call in { "UpdateAsync", "SetAsync", "GetSortedAsync", "GetAsync", "GetFriendsAsync", "GetNameFromUserIdAsync" } do
            local at = string.find(CODE_ONLY, `:{call}(`, 1, true)
            T.expect(at ~= nil).toBe(true)
            -- Der letzte pcall davor muss näher liegen als der letzte Funktionsanfang `local function`.
            local head = string.sub(CODE_ONLY, 1, at :: number)
            local lastPcall = 0
            for position in string.gmatch(head, "()pcall%(") do
                lastPcall = position
            end
            local lastFunction = 0
            for position in string.gmatch(head, "()\nlocal function ") do
                lastFunction = position
            end
            T.expect(lastPcall > lastFunction).toBe(true)
        end
        T.expect(string.find(FRIENDS_SOURCE, "pcall(function(): boolean", 1, true) ~= nil).toBe(true)
        -- ViewCollection nimmt nur einen Platz (Zahl bis maxFriends), keine UserId.
        local rule = RemoteSpec.byName.ViewCollection.schema[1]
        T.expect(rule.kind).toBe("int")
        T.expect(rule.max).toBe(SocialData.leaderboard.maxFriends)
    end)

    T.it("das Menü ruft nur die drei Remotes auf und schickt höchstens einen Platz", function()
        T.expect(string.find(CLIENT_BOOTSTRAP_SOURCE, '"SocialMenu"', 1, true) ~= nil).toBe(true)
        T.expect(string.find(MENU_SOURCE, "getLeaderboard:InvokeServer()", 1, true) ~= nil).toBe(true)
        T.expect(string.find(MENU_SOURCE, "getFriends:InvokeServer()", 1, true) ~= nil).toBe(true)
        T.expect(string.find(MENU_SOURCE, "viewCollection:InvokeServer(slot)", 1, true) ~= nil).toBe(true)
        T.expect(string.find(MENU_SOURCE, "UserId", 1, true)).toBeNil()
    end)

    T.it("Studio nutzt eigene Speicher, die Werte kommen aus Data/Social", function()
        T.expect(string.find(BOARD_SOURCE, "IS_STUDIO", 1, true) ~= nil).toBe(true)
        T.expect(string.find(BOARD_SOURCE, "SocialData.leaderboard", 1, true) ~= nil).toBe(true)
        T.expect(string.find(BOARD_SOURCE, '"CollectionWeekly', 1, true)).toBeNil()
    end)

    T.it("geschrieben wird nur ein steigender Wert (UpdateAsync mit Maximum) und der Auszug nur mit bekannten IDs", function()
        T.expect(string.find(BOARD_SOURCE, "old >= value", 1, true) ~= nil).toBe(true)
        T.expect(string.find(BOARD_SOURCE, "SocialLogic.buildShowcase", 1, true) ~= nil).toBe(true)
        T.expect(string.find(BOARD_SOURCE, "SocialLogic.cleanShowcase", 1, true) ~= nil).toBe(true)
    end)
end)

T.finish()
