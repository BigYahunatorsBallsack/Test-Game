--!strict
-- Paket 5.5b: Saison-Pass, Abholen und Kauf (Logic/SeasonPass, Logic/Purchases, Logic/Seasons).
-- Stufen nie früher, Sprünge, je Stufe und Spur einmal, Premium nur mit Pass, feste Belohnungen ohne
-- Zufall, ein Fehler bucht nichts, Abholfrist, Kaufdialog, Kauf-Handler über die echte Kaufabwicklung
-- (idempotent, Doppelkauf, Zahlung nach dem Ende, Speichern schlägt fehl), zweite Saison nur über Daten,
-- Remote-Schema und Rate-Limit, gleichzeitiges Abholen, Laden/Speichern/Sandsturm, StateSync-Form,
-- Studio-Hilfe, Service-Verdrahtung (Textsuche).

local T = require("./lib/expect")
local FakeStore = require("./lib/fakestore")
local fs = require("@lune/fs")
local SeasonPass = require("../src/shared/Logic/SeasonPass")
local Seasons = require("../src/shared/Logic/Seasons")
local Purchases = require("../src/shared/Logic/Purchases")
local PlayerSession = require("../src/shared/Logic/PlayerSession")
local Profile = require("../src/shared/Logic/Profile")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local BigNum = require("../src/shared/Logic/BigNum")
local Validate = require("../src/shared/Logic/Validate")
local RateLimiter = require("../src/shared/Logic/RateLimiter")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local Economy = require("../src/shared/Data/Economy")
local PassData = require("../src/shared/Data/SeasonPass")
local SeasonData = require("../src/shared/Data/Seasons")
local CrateItems = require("../src/shared/Data/CrateItems")
local Products = require("../src/shared/Data/Products")
local GemPacks = require("../src/shared/Data/GemPacks")

-- Quelltexte für die Textsuche, hier oben gelesen (Dateizugriff wartet).
local LOGIC_SOURCE: string = fs.readFile("src/shared/Logic/SeasonPass.luau")
local SERVICE_SOURCE: string = fs.readFile("src/server/Services/SeasonPasses.luau")
local EVENTS_SOURCE: string = fs.readFile("src/server/Services/Events.luau")
local BOOTSTRAP_SOURCE: string = fs.readFile("src/server/init.server.luau")

local SEASON_ID = "season_1"
local DAY = Seasons.SECONDS_PER_DAY
local WEEK = Seasons.WEEK_SECONDS
local START = Seasons.startOf(SeasonData.list[1]) :: number
local END = START + 4 * WEEK
local GRACE = Economy.seasonPass.claimGraceDays * DAY
local NOW = START + 5 * DAY -- Woche 1
local PER_POINT = Economy.seasonPass.secondsPerPoint
local TIERS = PassData.bySeason[SEASON_ID].tiers
local MAX_GEMS = Economy.purchases.maxGems
local DUPLICATE_GEMS = Economy.seasonPass.duplicateGems
-- Echte Server-Uhr für Boosts (in Studio kann die Saison-Uhr verschoben sein).
local REAL_NOW = 1_700_000_000

local USER = 42
local KEY = PlayerSession.keyFor(USER)
-- Test-ProductIds: Die echten Daten haben bis zur Anlage im Creator Dashboard nur Platzhalter (0).
local PASS_PRODUCT_ID = 9_100_001
local PASS2_PRODUCT_ID = 9_100_002

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

-- Products mit echten ProductIds für die genannten Produkte (Kopien, die echten Daten bleiben).
local function productsWith(ids: { [string]: number }, extra: { any }?): any
    local list, byId = {}, {}
    for index, product in Products.list do
        local copy = table.clone(product)
        if ids[copy.id] ~= nil then
            copy.productId = ids[copy.id]
        end
        list[index] = copy
        byId[copy.id] = copy
    end
    for _, product in extra or {} do
        table.insert(list, product)
        byId[product.id] = product
    end
    return { list = list, byId = byId }
end

local DATA = {
    Economy = Economy,
    SeasonPass = PassData,
    Seasons = SeasonData,
    CrateItems = CrateItems,
    Products = productsWith({ season_pass = PASS_PRODUCT_ID }),
}

-- Erste Stufe, deren Belohnung auf `track` die Art `kind` hat (unabhängig von den Zahlen der Daten).
local function tierWith(track: string, kind: string): number
    for index, tier in TIERS do
        if tier[track].kind == kind then
            return index
        end
    end
    error(`keine Stufe mit {track} {kind}`)
end

local function profileWithPoints(points: number, premium: boolean?, data: any?): any
    local profile: any = Profile.default(NOW)
    if points > 0 then
        SeasonPass.addSeconds(profile, SEASON_ID, points * PER_POINT, data)
    end
    if premium then
        local entry = profile.seasons[SEASON_ID] or SeasonPass.newEntry()
        entry.premium = true
        profile.seasons[SEASON_ID] = entry
    end
    return profile
end

local function claim(profile: any, tier: any, track: any, now: number?, ctx: any?): any
    return SeasonPass.claim(profile, tier, track, now or NOW, ctx)
end

T.describe("Stufen erreichen", function()
    T.it("Stufe n ist genau ab ihrem Punktestand abholbar, nie früher", function()
        for index, tier in TIERS do
            local before = profileWithPoints(tier.points - 1)
            T.expect(claim(before, index, "free").reason).toBe("notReached")
            local reached = profileWithPoints(tier.points)
            local result = claim(reached, index, "free")
            T.expect(result.ok).toBe(true)
            T.expect(result.tier).toBe(index)
        end
    end)

    T.it("ein Sprung über mehrere Stufen erreicht alle, die nächste nicht", function()
        local profile = profileWithPoints(TIERS[4].points)
        for index = 1, 4 do
            T.expect(claim(profile, index, "free").ok).toBe(true)
        end
        T.expect(claim(profile, 5, "free").reason).toBe("notReached")
    end)

    T.it("eine Stufe, die es in den Daten nicht gibt, ist nie erreicht (auch mit allen Punkten)", function()
        local profile = profileWithPoints(1e9)
        local before = deepCopy(profile)
        for _, tier in { #TIERS + 1, SeasonPass.MAX_TIERS, 0, -1, 1.5 } do
            T.expect(claim(profile, tier, "free").reason).toBe("notReached")
        end
        T.expect(profile).toEqual(before)
    end)

    T.it("ohne Eintrag und ohne Punkte: notReached, nichts angelegt", function()
        local profile: any = Profile.default(NOW)
        T.expect(claim(profile, 1, "free").reason).toBe("notReached")
        T.expect(profile.seasons).toEqual({})
    end)
end)

T.describe("Abholen: einmal je Stufe und Spur, Premium nur mit Pass", function()
    T.it("jede Stufe je Spur genau einmal, Merker mit Textschlüssel", function()
        local profile = profileWithPoints(TIERS[2].points, true)
        T.expect(claim(profile, 1, "free").ok).toBe(true)
        T.expect(claim(profile, 1, "free").reason).toBe("claimed")
        T.expect(claim(profile, 1, "premium").ok).toBe(true)
        T.expect(claim(profile, 1, "premium").reason).toBe("claimed")
        T.expect(claim(profile, 2, "free").ok).toBe(true)
        T.expect(profile.seasons[SEASON_ID].claimed).toEqual({ free = { ["1"] = true, ["2"] = true }, premium = { ["1"] = true } })
    end)

    T.it("Premium-Spur ohne Pass: needPass, nichts gebucht; danach mit Pass abholbar", function()
        local profile = profileWithPoints(TIERS[3].points)
        local before = deepCopy(profile)
        T.expect(claim(profile, 1, "premium").reason).toBe("needPass")
        T.expect(profile).toEqual(before)
        profile.seasons[SEASON_ID].premium = true
        T.expect(claim(profile, 1, "premium").ok).toBe(true)
    end)

    T.it("Reihenfolge der Gründe: notReached vor needPass vor claimed", function()
        local profile = profileWithPoints(TIERS[1].points)
        T.expect(claim(profile, 2, "premium").reason).toBe("notReached")
        T.expect(claim(profile, 1, "premium").reason).toBe("needPass")
        claim(profile, 1, "free")
        T.expect(claim(profile, 1, "free").reason).toBe("claimed")
    end)

    T.it("Antwort: ok, seasonId, tier, track, reward; nie detail", function()
        local profile = profileWithPoints(TIERS[1].points)
        local result = claim(profile, 1, "free")
        T.expect(result.ok).toBe(true)
        T.expect(result.seasonId).toBe(SEASON_ID)
        T.expect(result.tier).toBe(1)
        T.expect(result.track).toBe("free")
        T.expect(type(result.reward)).toBe("table")
        T.expect(result.detail).toBeNil()
    end)

    T.it("unbekannte Felder des Eintrags und von claimed bleiben beim Abholen erhalten", function()
        local profile = profileWithPoints(TIERS[1].points, true)
        profile.seasons[SEASON_ID].future = "bleibt"
        profile.seasons[SEASON_ID].claimed.extra = { x = 1 }
        profile.seasons.other_season = { seconds = 5, premium = true, claimed = { free = {}, premium = {} } }
        T.expect(claim(profile, 1, "free").ok).toBe(true)
        T.expect(profile.seasons[SEASON_ID].future).toBe("bleibt")
        T.expect(profile.seasons[SEASON_ID].claimed.extra).toEqual({ x = 1 })
        T.expect(profile.seasons.other_season.premium).toBe(true)
        T.expect(profile.seasons[SEASON_ID].premium).toBe(true)
    end)
end)

T.describe("Belohnungen: fest, nie Kisten oder Zufall", function()
    T.it("Gems über Gems.grant", function()
        local index = tierWith("free", "gems")
        local profile = profileWithPoints(TIERS[index].points)
        profile.gems = 10
        local result = claim(profile, index, "free")
        T.expect(result.reward).toEqual({ kind = "gems", amount = TIERS[index].free.amount })
        T.expect(profile.gems).toBe(10 + TIERS[index].free.amount)
    end)

    T.it("Gems bei maxGems gekappt: die Abholung gilt trotzdem, amount ist die gutgeschriebene Menge", function()
        local index = tierWith("free", "gems")
        local profile = profileWithPoints(TIERS[index].points)
        profile.gems = MAX_GEMS - 2
        local result = claim(profile, index, "free")
        T.expect(result.reward).toEqual({ kind = "gems", amount = 2, capped = true })
        T.expect(profile.gems).toBe(MAX_GEMS)
        T.expect(claim(profile, index, "free").reason).toBe("claimed")
        local full = profileWithPoints(TIERS[index].points)
        full.gems = MAX_GEMS
        T.expect(claim(full, index, "free").reward).toEqual({ kind = "gems", amount = 0, capped = true })
        T.expect(full.gems).toBe(MAX_GEMS)
    end)

    T.it("Münz-Boost und Glücks-Boost laufen mit der echten Server-Uhr (boostNow), sonst mit der Saison-Uhr", function()
        local coinIndex = tierWith("free", "coinBoost")
        local profile = profileWithPoints(TIERS[coinIndex].points)
        local result = claim(profile, coinIndex, "free", NOW, { boostNow = REAL_NOW })
        T.expect(result.reward).toEqual({ kind = "coinBoost", seconds = TIERS[coinIndex].free.seconds })
        T.expect(profile.boosts.coinsUntil).toBe(REAL_NOW + TIERS[coinIndex].free.seconds)
        local luckIndex = tierWith("free", "luck")
        local lucky = profileWithPoints(TIERS[luckIndex].points)
        T.expect(claim(lucky, luckIndex, "free").reward).toEqual({ kind = "luck", seconds = TIERS[luckIndex].free.seconds })
        T.expect(lucky.boosts.luckUntil).toBe(NOW + TIERS[luckIndex].free.seconds)
        T.expect(lucky.boosts.coinsUntil).toBe(profileWithPoints(0).boosts.coinsUntil) -- andere Felder bleiben
    end)

    T.it("Pass-Item: ein Exemplar im Inventar-Feld seiner Art, weitere Exemplare zählen hoch", function()
        local index = tierWith("premium", "item")
        local itemId = TIERS[index].premium.itemId
        local item = CrateItems.byId[itemId]
        T.expect(item.passOnly).toBe(true)
        local field = ({ skin = "skins", companion = "companions", toolVariant = "toolVariants" } :: any)[item.kind]
        local profile = profileWithPoints(TIERS[index].points, true)
        local result = claim(profile, index, "premium")
        T.expect(result.reward).toEqual({ kind = "item", itemId = itemId, copies = 1 })
        T.expect(profile.inventory[field][itemId]).toBe(1)
        local again = profileWithPoints(TIERS[index].points, true)
        again.inventory[field][itemId] = 2
        T.expect(claim(again, index, "premium").reward.copies).toBe(3)
    end)

    T.it("gleiches Profil, gleiches Ergebnis: kein Zufall, keine Policy (gilt auch bei gesperrten Zufallsitems)", function()
        local a = profileWithPoints(TIERS[#TIERS].points, true)
        local b = deepCopy(a)
        for index = 1, #TIERS do
            for _, track in SeasonPass.TRACKS do
                T.expect(claim(b, index, track)).toEqual(claim(a, index, track))
            end
        end
        T.expect(b).toEqual(a)
        -- Der Code (ohne Kommentare) kennt weder Zufall noch Kisten noch Policy.
        for line in string.gmatch(LOGIC_SOURCE, "[^\n]+") do
            local code = string.lower(string.match(line, "^(.-)%-%-") or line)
            for _, word in { "random", "crateopen", "crateroll", "policy", "restricted" } do
                if string.find(code, word, 1, true) then
                    error(`Logic/SeasonPass nennt "{word}": {line}`)
                end
            end
        end
    end)

    T.it("die echten Stufen enthalten nur gems, coinBoost, luck und Pass-Items", function()
        for _, tier in TIERS do
            for _, track in SeasonPass.TRACKS do
                local reward = tier[track]
                T.expect(reward.kind == "gems" or reward.kind == "coinBoost" or reward.kind == "luck" or reward.kind == "item").toBe(true)
                if reward.kind == "item" then
                    T.expect(CrateItems.byId[reward.itemId].passOnly).toBe(true)
                end
            end
        end
    end)
end)

T.describe("Ein Fehler bucht nichts", function()
    local function passData(free: any, premium: any): any
        return { bySeason = { [SEASON_ID] = { tiers = { { points = 1, free = free, premium = premium } } } } }
    end

    T.it("kaputte Belohnung (Kiste, kein Pass-Item, unbekannt, kaputte Zahlen, fehlt): error, Profil unverändert", function()
        local broken: { any } = {
            { kind = "crate", crateId = "gold" },
            { kind = "item", itemId = "skin_common_1" }, -- Kisten-Item, kein Pass-Item
            { kind = "item", itemId = "gibt_es_nicht" },
            { kind = "gems", amount = 0 },
            { kind = "gems", amount = 1.5 },
            { kind = "coinBoost", seconds = -5 },
            { kind = "luck" },
            "kaputt",
        }
        for _, reward in broken do
            local data = { SeasonPass = passData(reward, reward) }
            local profile = profileWithPoints(1, true, data)
            profile.gems = 33
            local before = deepCopy(profile)
            local result = claim(profile, 1, "free", NOW, { data = data })
            T.expect(result.ok).toBe(false)
            T.expect(result.reason).toBe("error")
            T.expect(type(result.detail)).toBe("string")
            T.expect(profile).toEqual(before)
        end
        -- fehlende Belohnung
        local data = { SeasonPass = passData(nil, { kind = "gems", amount = 1 }) }
        local profile = profileWithPoints(1, true, data)
        local before = deepCopy(profile)
        T.expect(claim(profile, 1, "free", NOW, { data = data }).reason).toBe("error")
        T.expect(profile).toEqual(before)
    end)

    T.it("Warten im Block (yield beim Lesen der Daten): error, nichts gebucht, danach geht es normal", function()
        local yielding = setmetatable({}, {
            __index = function(): any
                coroutine.yield()
                return nil
            end,
        })
        local data = { SeasonPass = passData({ kind = "item", itemId = "skin_rare_4" }, { kind = "gems", amount = 1 }), CrateItems = yielding }
        local profile = profileWithPoints(1, true, data)
        local before = deepCopy(profile)
        local result = claim(profile, 1, "free", NOW, { data = data })
        T.expect(result.reason).toBe("error")
        T.expect(profile).toEqual(before)
        local okData = { SeasonPass = data.SeasonPass }
        T.expect(claim(profile, 1, "free", NOW, { data = okData }).ok).toBe(true)
    end)

    T.it("kein Profil, kaputte Uhr, unbekannte Spur: error ohne Änderung", function()
        T.expect(claim(nil, 1, "free").reason).toBe("error")
        local profile = profileWithPoints(TIERS[1].points)
        local before = deepCopy(profile)
        for _, bad in { 0 / 0, math.huge, -1, "jetzt" :: any } do
            T.expect(claim(profile, 1, "free", bad).reason).toBe("error")
        end
        for _, track in { "gold", "Free", 1 :: any, nil :: any } do
            T.expect(claim(profile, 1, track).reason).toBe("error")
        end
        T.expect(profile).toEqual(before)
    end)
end)

T.describe("Abholfrist", function()
    T.it("während der Saison und bis zum Ende der Frist abholbar (Tag 3 ja), danach expired", function()
        local profile = profileWithPoints(TIERS[3].points)
        local lastSecond = claim(profile, 1, "free", END + GRACE - 1)
        T.expect(lastSecond.ok).toBe(true)
        T.expect(lastSecond.seasonId).toBe(SEASON_ID)
        T.expect(claim(profile, 2, "free", END).ok).toBe(true) -- erste Sekunde nach dem Ende
        local before = deepCopy(profile)
        T.expect(claim(profile, 3, "free", END + GRACE).reason).toBe("expired")
        T.expect(claim(profile, 3, "free", END + 30 * DAY).reason).toBe("expired")
        T.expect(profile).toEqual(before)
        T.expect(claim(profile, 3, "free", START - 1).reason).toBe("noSeason")
        T.expect(Economy.seasonPass.claimGraceDays).toBe(3)
    end)

    T.it("current: laufend (Saisonrest plus Frist), beendet (Rest der Frist), danach nichts", function()
        local running = SeasonPass.current(NOW) :: any
        T.expect(running.season.id).toBe(SEASON_ID)
        T.expect(running.ended).toBe(false)
        T.expect(running.claimSecondsLeft).toBe(END - NOW + GRACE)
        local ended = SeasonPass.current(END + DAY) :: any
        T.expect(ended.ended).toBe(true)
        T.expect(ended.claimSecondsLeft).toBe(GRACE - DAY)
        local none, reason = SeasonPass.current(END + GRACE)
        T.expect(none).toBeNil()
        T.expect(reason).toBe("expired")
        local before, beforeReason = SeasonPass.current(START - 1)
        T.expect(before).toBeNil()
        T.expect(beforeReason).toBe("noSeason")
        T.expect((SeasonPass.current(0 / 0))).toBeNil()
    end)

    T.it("Punkte zählen nach dem Ende nicht mehr (die Event-Zone gehört keiner Saison mehr)", function()
        local zoneId = SeasonData.list[1].zoneId
        T.expect(Seasons.activeForZone(NOW, zoneId) ~= nil).toBe(true)
        T.expect(Seasons.activeForZone(END, zoneId)).toBeNil()
        T.expect(Seasons.activeForZone(END + DAY, zoneId)).toBeNil()
    end)

    T.it("Abholen nach dem Ende gibt Belohnungen der beendeten Saison, Boosts mit der echten Uhr", function()
        local index = tierWith("free", "coinBoost")
        local profile = profileWithPoints(TIERS[index].points)
        local result = claim(profile, index, "free", END + DAY, { boostNow = REAL_NOW })
        T.expect(result.ok).toBe(true)
        T.expect(profile.boosts.coinsUntil).toBe(REAL_NOW + TIERS[index].free.seconds)
    end)
end)

T.describe("Kaufdialog (buyCheck)", function()
    T.it("nur in der laufenden Saison, ohne Pass, mit echter ProductId", function()
        local profile = profileWithPoints(0)
        local ok = SeasonPass.buyCheck(profile, NOW, DATA)
        T.expect(ok).toEqual({ ok = true, seasonId = SEASON_ID, passId = "season_pass", productId = PASS_PRODUCT_ID })
        T.expect(SeasonPass.buyCheck(profile, START - 1, DATA).reason).toBe("noSeason")
        T.expect(SeasonPass.buyCheck(profile, END + DAY, DATA).reason).toBe("noSeason") -- Abholfrist: kein Kauf
        T.expect(SeasonPass.buyCheck(profile, END + GRACE, DATA).reason).toBe("noSeason")
        T.expect(SeasonPass.buyCheck(profileWithPoints(0, true), NOW, DATA).reason).toBe("owned")
    end)

    T.it("ProductId 0 (Platzhalter, echte Daten), fehlende passId, falsche Produktart: notOffered", function()
        T.expect(Products.byId.season_pass.productId).toBe(0)
        T.expect(SeasonPass.buyCheck(profileWithPoints(0), NOW).reason).toBe("notOffered")
        local noPass = table.clone(DATA) :: any
        noPass.Seasons = { phases = SeasonData.phases, list = { (table.clone(SeasonData.list[1]) :: any) } }
        noPass.Seasons.list[1].passId = nil
        T.expect(SeasonPass.buyCheck(profileWithPoints(0), NOW, noPass).reason).toBe("notOffered")
        local wrongKind = table.clone(DATA) :: any
        wrongKind.Products = productsWith({ season_pass = PASS_PRODUCT_ID })
        wrongKind.Products.byId.season_pass.kind = "gamepass"
        T.expect(SeasonPass.buyCheck(profileWithPoints(0), NOW, wrongKind).reason).toBe("notOffered")
    end)

    T.it("kein Profil oder kaputte Uhr: error; buyCheck ändert nichts", function()
        T.expect(SeasonPass.buyCheck(nil, NOW, DATA).reason).toBe("error")
        local profile = profileWithPoints(5)
        local before = deepCopy(profile)
        T.expect(SeasonPass.buyCheck(profile, 0 / 0, DATA).reason).toBe("error")
        SeasonPass.buyCheck(profile, NOW, DATA)
        T.expect(profile).toEqual(before)
    end)
end)

-- Kaufabwicklung wie im Spiel: PlayerSession mit Fake-Speicher, Purchases, Handler des Passes.
type Note = { userId: number, kind: string, data: { [string]: any } }
type Server = { manager: any, purchases: any, logs: { string }, notes: { Note }, clockCalls: { any } }

-- Saison-Uhr, die der Handler über `clock(userId)` liest (je Test gesetzt, wie SeasonClock in Studio).
local seasonClock = { time = NOW }

local PURCHASE_DATA = { GemPacks = GemPacks, Products = DATA.Products, Economy = Economy }

local function newServer(world: FakeStore.World, name: string?, handlerData: any?): Server
    local clock = { time = REAL_NOW }
    local logs: { string } = {}
    local notes: { Note } = {}
    local clockCalls: { any } = {}
    local function now(): number
        return clock.time
    end
    local function wait(seconds: number)
        clock.time += seconds
        coroutine.yield()
    end
    local function log(message: string)
        table.insert(logs, message)
    end
    local manager = PlayerSession.new({
        store = FakeStore.newServer(world, name or "A"),
        now = now,
        clock = now,
        wait = wait,
        kick = function() end,
        log = log,
    })
    local handler = SeasonPass.passHandler(function(userId: number?): number
        table.insert(clockCalls, userId)
        return seasonClock.time
    end, log, handlerData)
    local purchases = Purchases.new({
        getProfile = manager.get,
        isSessionActive = manager.isActive,
        saveAndWait = function(userId: number, purchaseId: string, timeoutSeconds: number): boolean
            return manager.saveAndWait(userId, function(saved: any): boolean
                return Purchases.hasReceipt(saved, purchaseId)
            end, timeoutSeconds)
        end,
        now = now,
        clock = now,
        wait = wait,
        log = log,
        notify = function(userId: number, kind: string, data: { [string]: any })
            table.insert(notes, { userId = userId, kind = kind, data = data })
        end,
        handlers = { season_pass = handler },
        allowDebug = true,
        data = PURCHASE_DATA,
    })
    return { manager = manager, purchases = purchases, logs = logs, notes = notes, clockCalls = clockCalls }
end

-- Lässt einen Vorgang bis zum Ende laufen (`wait` gibt die Kontrolle an den Test zurück).
local function run(fn: () -> any): any
    local result: any = nil
    local co = coroutine.create(function()
        result = fn()
    end)
    for _ = 1, 10_000 do
        if coroutine.status(co) == "dead" then
            return result
        end
        local ok, err = coroutine.resume(co)
        if not ok then
            error(err, 0)
        end
    end
    error("Vorgang wurde nicht fertig")
end

local function buy(server: Server, purchaseId: string, productId: number?): string
    return run(function(): any
        return server.purchases.process({ PlayerId = USER, ProductId = productId or PASS_PRODUCT_ID, PurchaseId = purchaseId })
    end)
end

local function load(server: Server): any
    return run(function(): any
        return server.manager.load(USER, function(): boolean
            return true
        end)
    end)
end

local function countLogs(server: Server, fragment: string): number
    local count = 0
    for _, line in server.logs do
        if string.find(line, fragment, 1, true) then
            count += 1
        end
    end
    return count
end

T.describe("Kauf über ProcessReceipt (Logic/Purchases)", function()
    T.it("Kauf in der Saison: Premium-Spur, erst nach dem Speichern granted, Meldung seasonPassBought", function()
        seasonClock.time = NOW
        local world = FakeStore.newWorld()
        local a = newServer(world)
        local profile = load(a)
        T.expect(buy(a, "pass-1")).toBe("granted")
        T.expect(profile.seasons[SEASON_ID].premium).toBe(true)
        T.expect(profile.gems).toBe(0)
        T.expect(world.saved[KEY].seasons[SEASON_ID].premium).toBe(true)
        T.expect(Purchases.hasReceipt(world.saved[KEY], "pass-1")).toBe(true)
        T.expect(#a.notes).toBe(1)
        T.expect(a.notes[1].kind).toBe("seasonPassBought")
        T.expect(a.notes[1].data).toEqual({ seasonId = SEASON_ID, duplicate = false })
        T.expect(profile.purchaseLog[1].productId).toBe("season_pass")
        T.expect(profile.purchaseLog[1].robux).toBe(Products.byId.season_pass.priceRobux)
        -- Der Handler hat die Uhr des kaufenden Spielers gefragt (4. Argument von Purchases).
        T.expect(a.clockCalls).toEqual({ USER })
    end)

    T.it("dieselbe PurchaseId zweimal: genau eine Gutschrift, keine Ersatz-Gems, granted ohne neue Buchung", function()
        seasonClock.time = NOW
        local world = FakeStore.newWorld()
        local a = newServer(world)
        local profile = load(a)
        T.expect(buy(a, "pass-same")).toBe("granted")
        local after = deepCopy(profile)
        T.expect(buy(a, "pass-same")).toBe("granted")
        T.expect(profile.gems).toBe(0)
        T.expect(profile.receipts).toEqual({ "pass-same" })
        T.expect(#profile.purchaseLog).toBe(1)
        T.expect(profile.seasons).toEqual(after.seasons)
        T.expect(#a.notes).toBe(1)
        T.expect(#a.clockCalls).toBe(1) -- der Handler lief nur einmal
    end)

    T.it("Doppelkauf derselben Saison (neue PurchaseId): kein zweiter Pass, Ersatz-Gems aus Economy.seasonPass", function()
        seasonClock.time = NOW
        local world = FakeStore.newWorld()
        local a = newServer(world)
        local profile = load(a)
        profile.gems = 100
        T.expect(buy(a, "pass-a")).toBe("granted")
        T.expect(buy(a, "pass-b")).toBe("granted")
        T.expect(profile.seasons[SEASON_ID].premium).toBe(true)
        T.expect(profile.gems).toBe(100 + DUPLICATE_GEMS)
        T.expect(DUPLICATE_GEMS).toBe(850)
        T.expect(a.notes[2].data).toEqual({ seasonId = SEASON_ID, duplicate = true, gems = DUPLICATE_GEMS })
        T.expect(profile.purchaseLog[2].gems).toBe(DUPLICATE_GEMS)
        T.expect(world.saved[KEY].gems).toBe(100 + DUPLICATE_GEMS)
    end)

    T.it("Speichern schlägt fehl: NotProcessedYet, Pass und PurchaseId bleiben zusammen, der nächste Versuch bucht nicht neu", function()
        seasonClock.time = NOW
        local world = FakeStore.newWorld()
        world.failSaves = true
        local a = newServer(world)
        local profile = load(a)
        T.expect(buy(a, "pass-fail")).toBe("notProcessed")
        T.expect(profile.seasons[SEASON_ID].premium).toBe(true)
        T.expect(Purchases.hasReceipt(profile, "pass-fail")).toBe(true)
        T.expect(#a.notes).toBe(0) -- keine Meldung vor dem bestätigten Speichern
        world.failSaves = false
        T.expect(buy(a, "pass-fail")).toBe("granted")
        T.expect(profile.gems).toBe(0) -- keine Ersatz-Gems beim Wiederholen
        T.expect(world.saved[KEY].seasons[SEASON_ID].premium).toBe(true)
        T.expect(#a.notes).toBe(1)
        T.expect(a.notes[1].data.duplicate).toBe(false)
    end)

    T.it("Profil nicht geladen: NotProcessedYet ohne Gutschrift", function()
        seasonClock.time = NOW
        local world = FakeStore.newWorld()
        local a = newServer(world)
        T.expect(buy(a, "pass-noload")).toBe("notProcessed")
        T.expect(world.saved[KEY]).toBeNil()
        T.expect(#a.clockCalls).toBe(0)
    end)

    T.it("Zahlung nach dem Saisonende gilt innerhalb der Abholfrist für die zuletzt beendete Saison", function()
        seasonClock.time = END + DAY
        local world = FakeStore.newWorld()
        local a = newServer(world)
        local profile = load(a)
        T.expect(buy(a, "pass-late")).toBe("granted")
        T.expect(profile.seasons[SEASON_ID].premium).toBe(true)
        T.expect(profile.gems).toBe(0)
        T.expect(a.notes[1].data).toEqual({ seasonId = SEASON_ID, duplicate = false })
    end)

    T.it("Zahlung nach der Frist oder vor der Saison: Ersatz-Gems, nie ein Pass", function()
        for _, time in { END + GRACE, END + 40 * DAY, START - 1 } do
            seasonClock.time = time
            local world = FakeStore.newWorld()
            local a = newServer(world)
            local profile = load(a)
            T.expect(buy(a, `pass-{time}`)).toBe("granted")
            T.expect(profile.seasons[SEASON_ID]).toBeNil()
            T.expect(profile.gems).toBe(DUPLICATE_GEMS)
            T.expect(a.notes[1].data).toEqual({ seasonId = SEASON_ID, duplicate = true, gems = DUPLICATE_GEMS })
            T.expect(countLogs(a, "Ersatz-Gems")).toBe(1)
        end
    end)

    T.it("bestehende Felder des Eintrags (Punkte, Abholmerker, unbekannte Felder) bleiben beim Kauf erhalten", function()
        seasonClock.time = NOW
        local world = FakeStore.newWorld()
        local a = newServer(world)
        local profile = load(a)
        SeasonPass.addSeconds(profile, SEASON_ID, TIERS[2].points * PER_POINT)
        claim(profile, 1, "free")
        profile.seasons[SEASON_ID].future = "bleibt"
        profile.seasons.other = { seconds = 3, premium = false, claimed = { free = { ["1"] = true }, premium = {} } }
        T.expect(buy(a, "pass-keep")).toBe("granted")
        local entry = profile.seasons[SEASON_ID]
        T.expect(entry.premium).toBe(true)
        T.expect(entry.seconds).toBe(TIERS[2].points * PER_POINT)
        T.expect(entry.claimed.free).toEqual({ ["1"] = true })
        T.expect(entry.future).toBe("bleibt")
        T.expect(profile.seasons.other.claimed.free).toEqual({ ["1"] = true })
    end)

    T.it("bei maxGems werden die Ersatz-Gems gekappt, der Kauf gilt trotzdem", function()
        seasonClock.time = NOW
        local world = FakeStore.newWorld()
        local a = newServer(world)
        local profile = load(a)
        profile.seasons[SEASON_ID] = { seconds = 0, premium = true, claimed = { free = {}, premium = {} } }
        profile.gems = MAX_GEMS - 10
        T.expect(buy(a, "pass-cap")).toBe("granted")
        T.expect(profile.gems).toBe(MAX_GEMS)
        T.expect(a.notes[1].data.gems).toBe(10)
        T.expect(countLogs(a, "gekappt")).toBe(1)
    end)

    T.it("kaputte Uhr oder kaputte Daten: NotProcessedYet, nichts gebucht (Roblox wiederholt später)", function()
        seasonClock.time = 0 / 0
        local world = FakeStore.newWorld()
        local a = newServer(world)
        local profile = load(a)
        local before = deepCopy(profile)
        T.expect(buy(a, "pass-clock")).toBe("notProcessed")
        T.expect(profile).toEqual(before)
        seasonClock.time = NOW
        local brokenEconomy = table.clone(Economy) :: any
        brokenEconomy.seasonPass = table.clone(Economy.seasonPass)
        brokenEconomy.seasonPass.duplicateGems = 1.5
        local b = newServer(FakeStore.newWorld(), "B", { Economy = brokenEconomy })
        local other = load(b)
        local otherBefore = deepCopy(other)
        T.expect(buy(b, "pass-data")).toBe("notProcessed")
        T.expect(other).toEqual(otherBefore)
        -- ein unbekanntes Produkt erreicht den Handler nie
        T.expect(buy(a, "pass-unknown", 123)).toBe("notProcessed")
        T.expect(#a.clockCalls).toBe(1)
    end)

    T.it("Studio-Testkauf (processDebug) läuft denselben Weg mit der Saison-Uhr des Spielers", function()
        seasonClock.time = END + DAY -- wie DebugSeason "ended"
        local world = FakeStore.newWorld()
        local a = newServer(world)
        local profile = load(a)
        local decision = run(function(): any
            return a.purchases.processDebug(USER, "season_pass", "fest1")
        end)
        T.expect(decision).toBe("granted")
        T.expect(profile.seasons[SEASON_ID].premium).toBe(true)
        T.expect(profile.receipts).toEqual({ Purchases.DEBUG_PREFIX .. "fest1" })
        T.expect(a.clockCalls).toEqual({ USER })
    end)

    T.it("premium und Abholmerker überleben Speichern und erneutes Laden auf einem anderen Server", function()
        seasonClock.time = NOW
        local world = FakeStore.newWorld()
        local a = newServer(world)
        local profile = load(a)
        SeasonPass.addSeconds(profile, SEASON_ID, TIERS[2].points * PER_POINT)
        T.expect(buy(a, "pass-reload")).toBe("granted")
        T.expect(claim(profile, 1, "premium").ok).toBe(true)
        T.expect(claim(profile, 2, "free").ok).toBe(true)
        local expected = deepCopy(profile.seasons)
        run(function(): any
            a.manager.release(USER)
            return nil
        end)
        local b = newServer(world, "B")
        local reloaded = load(b)
        T.expect(reloaded ~= nil).toBe(true)
        T.expect(reloaded.seasons).toEqual(expected)
        T.expect(claim(reloaded, 1, "premium").reason).toBe("claimed")
        T.expect(claim(reloaded, 2, "premium").ok).toBe(true)
    end)
end)

T.describe("Laden, Speichern und Sandsturm", function()
    T.it("premium und claimed überstehen sanitize, migrate und den Sandsturm unverändert", function()
        local profile = profileWithPoints(TIERS[3].points, true)
        claim(profile, 1, "free")
        claim(profile, 1, "premium")
        claim(profile, 3, "free")
        local expected = deepCopy(profile.seasons)
        local saved = deepCopy(profile)
        Profile.sanitize(saved, NOW)
        T.expect(saved.seasons).toEqual(expected)
        local migrated = Profile.migrate(deepCopy(saved), {}, NOW)
        T.expect((migrated :: any).seasons).toEqual(expected)
        profile.nodes.collect_tool_2 = true
        profile.nodes.collect_tool_3 = true
        profile.nodes.collect_tool_4 = true
        profile.runEarned = BigNum.serialize(BigNum.new(1, 11))
        profile.coins = BigNum.serialize(BigNum.new(3, 7))
        local result, reason = Sandstorm.apply(profile)
        T.expect(reason).toBeNil()
        T.expect(result ~= nil).toBe(true)
        T.expect(profile.seasons).toEqual(expected)
        T.expect(claim(profile, 1, "premium").reason).toBe("claimed")
    end)
end)

T.describe("StateSync-Form (view)", function()
    T.it("während der Saison: genau die vereinbarten Felder, Kopien der Merker", function()
        local profile = profileWithPoints(TIERS[2].points)
        claim(profile, 1, "free")
        local view = SeasonPass.view(profile, NOW, DATA) :: any
        local keys = {}
        for key in view do
            table.insert(keys, key)
        end
        table.sort(keys)
        T.expect(keys).toEqual({ "canBuy", "claimSecondsLeft", "claimed", "ended", "maxPoints", "passId", "points", "premium", "seasonId", "seasonSecondsLeft", "tier", "tiers" })
        T.expect(view.seasonId).toBe(SEASON_ID)
        T.expect(view.points).toBe(TIERS[2].points)
        T.expect(view.maxPoints).toBe(TIERS[#TIERS].points)
        T.expect(view.tier).toBe(2)
        T.expect(view.tiers).toBe(#TIERS)
        T.expect(view.premium).toBe(false)
        T.expect(view.claimed).toEqual({ free = { ["1"] = true }, premium = {} })
        T.expect(view.canBuy).toBe(true)
        T.expect(view.ended).toBe(false)
        T.expect(view.claimSecondsLeft).toBe(END - NOW + GRACE)
        -- Kopien: eine Änderung an der Anzeige ändert das Profil nicht
        view.claimed.free["2"] = true
        T.expect(profile.seasons[SEASON_ID].claimed.free["2"]).toBeNil()
    end)

    T.it("mit Pass oder Platzhalter-ProductId: canBuy false", function()
        T.expect((SeasonPass.view(profileWithPoints(0, true), NOW, DATA) :: any).canBuy).toBe(false)
        T.expect((SeasonPass.view(profileWithPoints(0), NOW) :: any).canBuy).toBe(false) -- echte Daten: productId 0
    end)

    T.it("in der Abholfrist: ended, canBuy false, Rest der Frist; danach und vorher kein Feld", function()
        local profile = profileWithPoints(TIERS[1].points)
        local view = SeasonPass.view(profile, END + DAY, DATA) :: any
        T.expect(view.ended).toBe(true)
        T.expect(view.canBuy).toBe(false)
        T.expect(view.claimSecondsLeft).toBe(GRACE - DAY)
        T.expect(view.points).toBe(TIERS[1].points)
        T.expect(SeasonPass.view(profile, END + GRACE, DATA)).toBeNil()
        T.expect(SeasonPass.view(profile, START - 1, DATA)).toBeNil()
        T.expect(SeasonPass.view(nil, NOW, DATA)).toBeNil()
    end)

    T.it("Events baut das Feld aus SeasonPass.view und sendet beim Wechsel in die und aus der Frist neu", function()
        T.expect(string.find(EVENTS_SOURCE, "pcall(SeasonPassLogic.view, profile, time)", 1, true) ~= nil).toBe(true)
        T.expect(string.find(EVENTS_SOURCE, "SeasonPassLogic.current", 1, true) ~= nil).toBe(true)
        T.expect(string.find(EVENTS_SOURCE, "keyOf(state, time)", 1, true) ~= nil).toBe(true)
    end)
end)

T.describe("Zweite Saison nur über Daten", function()
    local S2_START = Seasons.parseDate("2027-03-01") :: number
    local S2_NOW = S2_START + 2 * DAY
    local season2 = {
        id = "season_2",
        name = "Saison 2",
        startDate = "2027-03-01",
        crateId = "event_2",
        zoneId = "season_camp_2",
        passId = "season_pass_2",
    }
    local data2 = {
        Economy = Economy,
        CrateItems = CrateItems,
        Seasons = { phases = SeasonData.phases, list = { SeasonData.list[1], season2 } },
        SeasonPass = {
            bySeason = {
                season_1 = PassData.bySeason.season_1,
                season_2 = {
                    tiers = {
                        { points = 10, free = { kind = "gems", amount = 7 }, premium = { kind = "luck", seconds = 120 } },
                        { points = 20, free = { kind = "coinBoost", seconds = 60 }, premium = { kind = "gems", amount = 9 } },
                    },
                },
            },
        },
        Products = productsWith({ season_pass = PASS_PRODUCT_ID }, {
            {
                id = "season_pass_2",
                kind = "developerProduct",
                name = "Saison-Pass 2",
                priceRobux = 399,
                productId = PASS2_PRODUCT_ID,
                oneTime = false,
                consumable = false,
                effect = "Premium-Spur der Saison 2",
            },
        }),
    }

    T.it("Punkte, Abholen, Anzeige und Kaufdialog laufen für Saison 2 ohne Code-Änderung", function()
        T.expect(Seasons.activeForZone(S2_NOW, "season_camp_2", data2.Seasons).id).toBe("season_2")
        local profile: any = Profile.default(S2_NOW)
        T.expect(SeasonPass.addSeconds(profile, "season_2", 15 * PER_POINT, data2)).toBe(15)
        local result = SeasonPass.claim(profile, 1, "free", S2_NOW, { data = data2 })
        T.expect(result.ok).toBe(true)
        T.expect(result.seasonId).toBe("season_2")
        T.expect(result.reward).toEqual({ kind = "gems", amount = 7 })
        T.expect(SeasonPass.claim(profile, 2, "free", S2_NOW, { data = data2 }).reason).toBe("notReached")
        local view = SeasonPass.view(profile, S2_NOW, data2) :: any
        T.expect(view.seasonId).toBe("season_2")
        T.expect(view.tiers).toBe(2)
        T.expect(view.canBuy).toBe(true)
        T.expect(SeasonPass.buyCheck(profile, S2_NOW, data2).productId).toBe(PASS2_PRODUCT_ID)
        -- Saison 1 ist dann lange vorbei: ihre Merker bleiben, abholen geht nicht mehr
        T.expect(profile.seasons.season_2.claimed.free).toEqual({ ["1"] = true })
    end)

    T.it("Handler: das Produkt der Saison 2 gibt ihren Pass, das alte Produkt der Saison 1 nur Ersatz-Gems", function()
        local profile: any = Profile.default(S2_NOW)
        local handler = SeasonPass.passHandler(function(): number
            return S2_NOW
        end, nil, data2)
        local answer = handler(deepCopy(profile), { id = "season_pass_2" }, nil, { userId = USER, purchaseId = "p2" }) :: any
        T.expect(answer.gems).toBe(0)
        T.expect(answer.changes.seasons.season_2.premium).toBe(true)
        T.expect(select(2, answer.announce(profile))).toEqual({ seasonId = "season_2", duplicate = false })
        local old = handler(deepCopy(profile), { id = "season_pass" }, nil, { userId = USER, purchaseId = "p1" }) :: any
        T.expect(old.gems).toBe(DUPLICATE_GEMS)
        T.expect(old.changes.seasons).toBeNil()
        T.expect(select(2, old.announce(profile))).toEqual({ seasonId = SEASON_ID, duplicate = true, gems = DUPLICATE_GEMS })
    end)

    T.it("die Abholfrist der Saison 1 läuft auch mit der zweiten Zeile in der Tabelle", function()
        local profile = profileWithPoints(TIERS[1].points, false, data2)
        local result = SeasonPass.claim(profile, 1, "free", END + DAY, { data = data2 })
        T.expect(result.ok).toBe(true)
        T.expect(result.seasonId).toBe(SEASON_ID)
    end)
end)

T.describe("Remotes: Schema und Rate-Limit", function()
    local function validate(name: string, ...: any): boolean
        local def = RemoteSpec.byName[name]
        return (Validate.check(def.schema :: { Validate.Rule }, { ... }, select("#", ...)))
    end

    T.it("ClaimSeasonReward: Function vom Client, Stufe 1 bis 50 und Spur free oder premium", function()
        local def = RemoteSpec.byName.ClaimSeasonReward
        T.expect(def.kind).toBe("Function")
        T.expect(def.direction).toBe("ClientToServer")
        T.expect(select(1, RemoteSpec.canRegister("ClaimSeasonReward"))).toBe(true)
        T.expect(validate("ClaimSeasonReward", 1, "free")).toBe(true)
        T.expect(validate("ClaimSeasonReward", 50, "premium")).toBe(true)
        T.expect(SeasonPass.MAX_TIERS).toBe(50)
        T.expect(#TIERS <= SeasonPass.MAX_TIERS).toBe(true)
    end)

    T.it("ClaimSeasonReward lehnt falschen Typ, Stufe 0, unbekannte Spur und falsche Argumentzahl ab", function()
        for _, args in {
            { 0, "free" },
            { 51, "free" },
            { -1, "free" },
            { 1.5, "free" },
            { 0 / 0, "free" },
            { math.huge, "free" },
            { "1", "free" },
            { true, "free" },
            { { 1 }, "free" },
            { 1, "gold" },
            { 1, "Free" },
            { 1, "" },
            { 1, 1 },
            { 1, true },
        } do
            T.expect(validate("ClaimSeasonReward", args[1], args[2])).toBe(false)
        end
        T.expect(validate("ClaimSeasonReward")).toBe(false)
        T.expect(validate("ClaimSeasonReward", 1)).toBe(false)
        T.expect(validate("ClaimSeasonReward", 1, nil)).toBe(false)
        T.expect(validate("ClaimSeasonReward", 1, "free", NOW)).toBe(false) -- keine Zeit vom Client
        T.expect(validate("ClaimSeasonReward", 1, "free", "season_1")).toBe(false) -- keine Saison vom Client
    end)

    T.it("BuySeasonPass: Function ohne Argumente; jedes Argument wird abgelehnt", function()
        local def = RemoteSpec.byName.BuySeasonPass
        T.expect(def.kind).toBe("Function")
        T.expect(def.direction).toBe("ClientToServer")
        T.expect(def.schema).toEqual({})
        T.expect(select(1, RemoteSpec.canRegister("BuySeasonPass"))).toBe(true)
        T.expect(validate("BuySeasonPass")).toBe(true)
        for _, value in { "season_1", PASS_PRODUCT_ID, 399, true, nil :: any } do
            T.expect(validate("BuySeasonPass", value)).toBe(false)
        end
    end)

    T.it("Rate-Limit: ClaimSeasonReward 5 je s, BuySeasonPass 1 je 3 s, Spieler und Remotes getrennt", function()
        local clock = { t = 100 }
        local limiter = RateLimiter.new(function(): number
            return clock.t
        end)
        local claimLimit = RemoteSpec.byName.ClaimSeasonReward.limit :: RateLimiter.Limit
        local buyLimit = RemoteSpec.byName.BuySeasonPass.limit :: RateLimiter.Limit
        T.expect(claimLimit).toEqual({ calls = 5, per = 1 })
        T.expect(buyLimit).toEqual({ calls = 1, per = 3 })
        for _ = 1, 5 do
            T.expect(limiter:allow("42", "ClaimSeasonReward", claimLimit)).toBe(true)
        end
        T.expect(limiter:allow("42", "ClaimSeasonReward", claimLimit)).toBe(false)
        T.expect(limiter:allow("43", "ClaimSeasonReward", claimLimit)).toBe(true) -- anderer Spieler
        T.expect(limiter:allow("42", "BuySeasonPass", buyLimit)).toBe(true) -- andere Remote
        T.expect(limiter:allow("42", "BuySeasonPass", buyLimit)).toBe(false)
        clock.t += 1
        T.expect(limiter:allow("42", "ClaimSeasonReward", claimLimit)).toBe(true)
        T.expect(limiter:allow("42", "BuySeasonPass", buyLimit)).toBe(false)
        clock.t += 2
        T.expect(limiter:allow("42", "BuySeasonPass", buyLimit)).toBe(true)
    end)
end)

T.describe("Gleichzeitiges Abholen und Sperre", function()
    T.it("zwei Aufrufe für dieselbe Stufe, ineinander verschränkt: eine Buchung, einmal claimed", function()
        local index = tierWith("free", "gems")
        local profile = profileWithPoints(TIERS[index].points)
        local results: { any } = {}
        -- Beide Aufrufe kommen an, bevor einer fertig ist (Netz), danach laufen sie in beliebiger Reihenfolge.
        local first = coroutine.create(function()
            coroutine.yield()
            table.insert(results, claim(profile, index, "free"))
        end)
        local second = coroutine.create(function()
            coroutine.yield()
            table.insert(results, claim(profile, index, "free"))
        end)
        coroutine.resume(first)
        coroutine.resume(second)
        coroutine.resume(second)
        coroutine.resume(first)
        T.expect(#results).toBe(2)
        T.expect(results[1].ok).toBe(true)
        T.expect(results[2].reason).toBe("claimed")
        T.expect(profile.gems).toBe(TIERS[index].free.amount)
    end)

    T.it("der Service führt beide Remotes unter der gemeinsamen Sperre von Crates aus (ein zweiter: busy)", function()
        T.expect(string.find(SERVICE_SOURCE, "Crates.runExclusive(player, CLAIM_LOCK_LABEL", 1, true) ~= nil).toBe(true)
        T.expect(string.find(SERVICE_SOURCE, "Crates.runExclusive(player, BUY_LOCK_LABEL", 1, true) ~= nil).toBe(true)
        T.expect(string.find(SERVICE_SOURCE, 'Net.on("ClaimSeasonReward", onClaimSeasonReward)', 1, true) ~= nil).toBe(true)
        T.expect(string.find(SERVICE_SOURCE, 'Net.on("BuySeasonPass", onBuySeasonPass)', 1, true) ~= nil).toBe(true)
        -- Zeit nur vom Server: Saison-Uhr und echte Uhr für Boosts, nie ein Argument.
        T.expect(string.find(SERVICE_SOURCE, "SeasonPassLogic.claim(activeProfile(player), tier, track, SeasonClock.timeFor(player)", 1, true) ~= nil).toBe(true)
        T.expect(string.find(SERVICE_SOURCE, "boostNow = os.time()", 1, true) ~= nil).toBe(true)
    end)
end)

T.describe("Service: Reihenfolge, Handler vor Shop.Start, Studio-Hilfe", function()
    T.it("SeasonPasses steht nach Shop und Events und registriert die Handler in Init", function()
        T.expect(string.find(BOOTSTRAP_SOURCE, '"Shop", "Events", "SeasonPasses", "Koloss", "Daily", "Codes", "Friends", "Leaderboard", "Analytics" }', 1, true) ~= nil).toBe(true)
        local initStart = string.find(SERVICE_SOURCE, "function SeasonPasses.Init()", 1, true) :: number
        local startStart = string.find(SERVICE_SOURCE, "function SeasonPasses.Start()", 1, true) :: number
        local register = string.find(SERVICE_SOURCE, "Shop.registerProduct(passId, SeasonPassLogic.passHandler(timeForUserId, log))", 1, true) :: number
        T.expect(initStart ~= nil and startStart ~= nil and register ~= nil).toBe(true)
        T.expect(register > initStart and register < startStart).toBe(true)
        T.expect(SeasonData.list[1].passId).toBe("season_pass")
    end)

    T.it("DebugSeasonPass hat nur in Studio einen Listener, das Attribut wird nach dem Lesen gelöscht", function()
        T.expect(string.find(SERVICE_SOURCE, "local IS_STUDIO = RunService:IsStudio()", 1, true) ~= nil).toBe(true)
        local guarded = string.find(SERVICE_SOURCE, "if IS_STUDIO then\n        Players.PlayerAdded:Connect(onPlayerAdded)", 1, true)
        T.expect(guarded ~= nil).toBe(true)
        local connects = 0
        for _ in string.gmatch(SERVICE_SOURCE, "connectStudioHelper%(") do
            connects += 1
        end
        T.expect(connects).toBe(2) -- Definition und genau ein Aufruf (in onPlayerAdded)
        T.expect(string.find(SERVICE_SOURCE, "player:SetAttribute(DEBUG_ATTRIBUTE, nil)", 1, true) ~= nil).toBe(true)
    end)

    T.it("parseDebug: points:N, premium, reset; alles andere mit Hinweis", function()
        local action, number, problem = SeasonPass.parseDebug("points:500")
        T.expect(action).toBe("points")
        T.expect(number).toBe(500)
        T.expect(problem).toBeNil()
        T.expect((SeasonPass.parseDebug("premium"))).toBe("premium")
        T.expect((SeasonPass.parseDebug("reset"))).toBe("reset")
        for _, bad in { "points:", "points:-1", "points:1.5", "Premium", "", string.rep("9", 40), 5 :: any, nil :: any, true :: any } do
            local a, n, p = SeasonPass.parseDebug(bad)
            T.expect(a).toBeNil()
            T.expect(n).toBeNil()
            T.expect(type(p)).toBe("string")
        end
    end)

    T.it("withDebug: points:500 erreicht Stufe 4, gedeckelt bei der letzten Stufe; premium; reset; Profil unverändert", function()
        local profile = profileWithPoints(0)
        local before = deepCopy(profile)
        local seasons, seasonId = SeasonPass.withDebug(profile, "points", 500, NOW)
        T.expect(profile).toEqual(before)
        T.expect(seasonId).toBe(SEASON_ID)
        profile.seasons = seasons
        T.expect(SeasonPass.pointsOf(profile, SEASON_ID)).toBe(500)
        T.expect(SeasonPass.tierOf(500, SEASON_ID)).toBe(4)
        profile.seasons = SeasonPass.withDebug(profile, "points", 1e9, NOW)
        T.expect(SeasonPass.pointsOf(profile, SEASON_ID)).toBe(TIERS[#TIERS].points)
        profile.seasons = SeasonPass.withDebug(profile, "premium", nil, NOW)
        T.expect(profile.seasons[SEASON_ID].premium).toBe(true)
        -- in der Abholfrist wirkt die Hilfe auf die beendete Saison
        local grace = SeasonPass.withDebug(profile, "reset", nil, END + DAY) :: any
        T.expect(grace[SEASON_ID]).toBeNil()
        local none, noneId, problem = SeasonPass.withDebug(profile, "premium", nil, START - 1)
        T.expect(none).toBeNil()
        T.expect(noneId).toBeNil()
        T.expect(type(problem)).toBe("string")
    end)
end)

T.describe("Nachbesserungen aus dem Security-Review", function()
    local DataCheck = require("../src/shared/Logic/DataCheck")
    local function copyOf(value: any): any
        if type(value) ~= "table" then
            return value
        end
        local copy = {}
        for key, inner in value do
            copy[copyOf(key)] = copyOf(inner)
        end
        return copy
    end
    local function broken(change: (data: any) -> ()): string
        local data = copyOf(DataCheck.defaults())
        change(data)
        return table.concat(DataCheck.run(data), "\n")
    end

    T.it("Saisons mit Pass brauchen Platz für die Abholfrist: direkt aufeinander folgende Saisons sind verboten", function()
        local text = broken(function(d)
            local first = d.Seasons.list[1]
            local start = Seasons.parseDate(first.startDate) :: number
            local length = #d.Seasons.phases * 7 * 86400
            local nextStart = start + length -- sofort nach dem Ende
            local second = copyOf(first)
            second.id = "season_2"
            second.passId = nil
            second.crateId = "event"
            second.zoneId = nil
            second.startDate = os.date("!%Y-%m-%d", nextStart)
            table.insert(d.Seasons.list, second)
        end)
        T.expect(text).toContain("Abholfrist")
    end)

    T.it("Ersatz-Gems dürfen nicht mehr wert sein als der Pass-Preis zum besten Paketkurs", function()
        local text = broken(function(d)
            d.Economy.seasonPass.duplicateGems = 5000
        end)
        T.expect(text).toContain("duplicateGems")
        T.expect(table.concat(DataCheck.run(), "\n")).toBe("")
    end)

    T.it("Säubern: weitere Spuren in claimed bleiben erhalten, ungültige Merker darin fallen weg", function()
        local profile: any = Profile.default(NOW)
        profile.seasons = {
            season_1 = { seconds = 10, premium = false, claimed = { free = {}, premium = {}, elite = { ["2"] = true, ["x"] = true } } },
        }
        Profile.sanitize(profile, NOW)
        T.expect(profile.seasons.season_1.claimed.elite).toEqual({ ["2"] = true })
    end)

    T.it("view nennt das Produkt des Passes und die Restzeit der Saison ohne Frist", function()
        local view = SeasonPass.view(profileWithPoints(0), NOW, DATA) :: any
        T.expect(view.passId).toBe("season_pass")
        T.expect(view.claimSecondsLeft - view.seasonSecondsLeft).toBe(Economy.seasonPass.claimGraceDays * 86400)
    end)
end)

T.finish()
