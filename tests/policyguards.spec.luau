--!strict
-- Paket 4.6: Schutzregeln der Policy (Roblox, bezahlte Zufallsitems), als Lune-Tests.
--
-- 1. Kistenquoten und Wurf hängen nur von Kiste, Pity-Zähler und Zufall ab. Glück-Ast, Glück-Boost,
--    Pässe, Münz-Boost und ausgerüstete Items ändern daran nichts (sonst stimmten die angezeigten
--    Quoten nicht).
-- 2. Remotes: Nur OpenCrate, EquipItem, MergeItem, BuyDirectItem, ClaimDaily (Tag 7: Eisenkiste
--    gratis oder fester Ersatzgegenstand, Paket 5.1) und ClaimSeasonReward (feste Pass-Items, Paket
--    5.5b) dürfen das Inventar ändern, und
--    keine Remote nimmt ein Argument, mit dem man einen anderen Spieler nennen könnte (kein Tausch,
--    kein Verschenken, kein Verkauf von Kisten-Items).
--
-- Was diese Tests NICHT beweisen: Der Inhalt der Handler wird nicht ausgeführt. Geprüft werden die
-- Liste der Remotes und ihre Schemas (RemoteSpec), wo jede Remote registriert wird (Textsuche nach
-- `Net.on("Name"` in src/server) und welche Dateien `.inventory = ...` zuweisen (Textsuche). Ein
-- Handler, der das Inventar auf anderem Weg ändert (zum Beispiel `profile[feld] = ...`), fällt
-- hier nicht auf; dafür gibt es die Prüfung durch den security-reviewer. Neue Remotes oder neue
-- Schreibstellen lassen diese Tests scheitern, damit sie bewusst eingeordnet werden.

local T = require("./lib/expect")
local fs = require("@lune/fs")
local CrateOpen = require("../src/shared/Logic/CrateOpen")
local CrateRoll = require("../src/shared/Logic/CrateRoll")
local Profile = require("../src/shared/Logic/Profile")
local SocialData = require("../src/shared/Data/Social")
local TreeEffects = require("../src/shared/Logic/TreeEffects")
local Perks = require("../src/shared/Logic/Perks")
local SeasonPass = require("../src/shared/Logic/SeasonPass")
local Equipment = require("../src/shared/Logic/Equipment")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local FindRoll = require("../src/shared/Logic/FindRoll")
local Daily = require("../src/shared/Logic/Daily")
local BigNum = require("../src/shared/Logic/BigNum")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local Crates = require("../src/shared/Data/Crates")
local CrateItems = require("../src/shared/Data/CrateItems")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local Products = require("../src/shared/Data/Products")
local Zones = require("../src/shared/Data/Zones")
local Economy = require("../src/shared/Data/Economy")

local NOW = 1_700_000_000
local SEED = 4646

-- Quelltexte für die Textsuche, hier oben gelesen (Dateizugriff wartet; in einem Test würde das den
-- Abschluss der Testdatei stören).
local function sourcesIn(dir: string): { [string]: string }
    local result: { [string]: string } = {}
    for _, name in fs.readDir(dir) do
        local path = `{dir}/{name}`
        if fs.isFile(path) and string.sub(name, -5) == ".luau" then
            result[path] = fs.readFile(path)
        end
    end
    return result
end
local SERVICE_SOURCES = sourcesIn("src/server/Services")
local LOGIC_SOURCES = sourcesIn("src/shared/Logic")
local NET_SOURCES = sourcesIn("src/server/Net")

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

-- Zufallsfolge aus einer Liste (beide Profile bekommen dieselbe).
local function replay(values: { number }): () -> number
    local index = 0
    return function(): number
        index += 1
        return values[index]
    end
end

T.describe("Glück, Pässe, Boosts und Ausrüstung ändern weder Kistenquoten noch Wurf", function()
    -- Zwei Profile, die sich nur in diesen Feldern unterscheiden. Beide haben dasselbe Inventar,
    -- damit `isNew` vergleichbar bleibt; nur B hat Items ausgerüstet und mit Sternen.
    local function plainProfile(): any
        local profile = Profile.default(NOW)
        profile.gems = 5_000_000
        profile.coins = BigNum.serialize(BigNum.new(1, 12))
        profile.inventory.skins.skin_mythic_1 = 11
        profile.inventory.companions.companion_mythic_1 = 11
        profile.inventory.toolVariants.toolVariant_mythic_1 = 11
        return profile
    end

    local function boostedProfile(): any
        local profile = plainProfile()
        for _, node in UpgradeTree.list do
            if node.effect.kind == "luckBonus" then
                profile.nodes[node.id] = true
            end
        end
        for _, product in Products.list do
            if product.kind == "gamepass" then
                profile.passes[product.id] = true
            end
        end
        profile.boosts = { coinsUntil = NOW + 10 * 3600, luckUntil = NOW + 10 * 3600 } -- luckUntil: Glücks-Boost (Daily Tag 5, Paket 5.1)
        profile.equipped = { skin = "skin_mythic_1", companion = "companion_mythic_1", toolVariant = "toolVariant_mythic_1" }
        profile.itemStars = { skin_mythic_1 = 5, companion_mythic_1 = 5, toolVariant_mythic_1 = 5 }
        profile.luckBonusBp = 50_000 -- kein echtes Feld: auch so ein Wert darf nichts ändern
        profile.windCrystals = 1000
        return profile
    end

    T.it("die Profile unterscheiden sich wirklich in Glück, Pässen, Boost und Ausrüstung", function()
        local plain, boosted = plainProfile(), boostedProfile()
        T.expect(TreeEffects.of(boosted).luckBonusBp > TreeEffects.of(plain).luckBonusBp).toBe(true)
        T.expect(Perks.options(boosted, NOW).coinMultiplier > Perks.options(plain, NOW).coinMultiplier).toBe(true)
        -- Der Glücks-Boost läuft wirklich und verdoppelt die Fundchance (Paket 5.1).
        T.expect(Perks.luckBoostActive(boosted, NOW)).toBe(true)
        T.expect(Perks.luckBoostMultiplier(boosted, NOW)).toBe(Economy.luckBoost.multiplier)
        T.expect(Perks.luckBoostMultiplier(plain, NOW)).toBe(1)
        T.expect(FindRoll.chancePerSecond(boosted, "dunes", 200, nil, NOW) > FindRoll.chancePerSecond(plain, "dunes", 200, nil, NOW)).toBe(true)
        T.expect(Equipment.bonusBp(boosted) > 0).toBe(true)
        T.expect(Equipment.bonusBp(plain)).toBe(0)
    end)

    T.it("CrateOpen: gleiche Zufallsfolge, gleiche Ergebnisse für jede Kiste, einzeln und als Paket", function()
        math.randomseed(SEED)
        local runs = 0
        for _, crate in Crates.list do
            for _, count in { 1, Crates.bundle.buy } do
                for round = 1, 30 do
                    local values: { number } = {}
                    for i = 1, 2 * Crates.bundle.get do
                        values[i] = math.random()
                    end
                    local plain, boosted = plainProfile(), boostedProfile()
                    -- Auch mitten in der Pity: gleicher Zählerstand in beiden Profilen.
                    local counters = { sinceEpic = round % 15, sinceLegendary = (round * 7) % 60 }
                    plain.pity[crate.id] = table.clone(counters)
                    boosted.pity[crate.id] = table.clone(counters)
                    local ctx = { restricted = false, inSeason = true }
                    local a = CrateOpen.open(plain, crate.id, count, { random = replay(values), restricted = ctx.restricted, inSeason = ctx.inSeason })
                    local b = CrateOpen.open(boosted, crate.id, count, { random = replay(values), restricted = ctx.restricted, inSeason = ctx.inSeason })
                    T.expect(a.ok).toBe(true)
                    T.expect(b).toEqual(a)
                    T.expect(boosted.pity).toEqual(plain.pity)
                    T.expect(boosted.inventory).toEqual(plain.inventory)
                    runs += 1
                end
            end
        end
        T.expect(runs).toBe(#Crates.list * 2 * 30)
    end)

    T.it("Daily Tag 7 (Gratis-Eisenkiste, 5.1): gleiche Zufallsfolge, gleiches Ergebnis mit und ohne Glücks-Boost", function()
        math.randomseed(SEED + 7)
        for _ = 1, 30 do
            local values: { number } = {}
            for i = 1, 4 do
                values[i] = math.random()
            end
            local plain, boosted = plainProfile(), boostedProfile()
            for _, profile in { plain, boosted } do
                profile.nodes[Economy.daily.startNodeId] = true
                profile.daily = { streak = #Economy.daily.days, lastDay = math.floor(NOW / 86400) - 1 }
            end
            local a = Daily.claim(plain, NOW, { policyState = "allowed", random = replay(values) })
            local b = Daily.claim(boosted, NOW, { policyState = "allowed", random = replay(values) })
            T.expect(a.ok).toBe(true)
            T.expect(a.day).toBe(#Economy.daily.days + 1)
            T.expect(b).toEqual(a)
            T.expect(boosted.inventory).toEqual(plain.inventory)
            T.expect(boosted.pity).toEqual(plain.pity)
        end
    end)

    T.it("Anzeige: effectiveOdds, itemOdds und longRunRates bekommen kein Profil, nur Kiste und Zähler", function()
        -- Die Schnittstelle selbst schließt das aus: Es gibt keinen Parameter für Profil, Glück oder Boosts.
        -- Gleicher Zählerstand ergibt dieselben Zahlen, egal woher er kommt.
        local plain, boosted = plainProfile(), boostedProfile()
        plain.pity.gold = { sinceEpic = 14, sinceLegendary = 2 }
        boosted.pity.gold = { sinceEpic = 14, sinceLegendary = 2 }
        T.expect(CrateRoll.effectiveOdds(Crates.byId.gold, boosted.pity.gold)).toEqual(CrateRoll.effectiveOdds(Crates.byId.gold, plain.pity.gold))
        T.expect(CrateRoll.itemOdds("gold", boosted.pity.gold)).toEqual(CrateRoll.itemOdds("gold", plain.pity.gold))
        -- Und die Quellen der Logik lesen kein Glück, keine Pässe, keine Boosts.
        for _, name in { "src/shared/Logic/CrateRoll.luau", "src/shared/Logic/CrateOpen.luau" } do
            local source = LOGIC_SOURCES[name]
            for _, word in { "luck", "Luck", "passes", "boosts", "equipped", "itemStars", "TreeEffects", "Perks" } do
                if string.find(source, word, 1, true) then
                    error(`{name} erwähnt "{word}": Kistenquoten dürfen davon nicht abhängen`)
                end
            end
        end
    end)
end)

-- Remotes vom Client zum Server, die das Inventar ändern dürfen (Kisten-Items), mit Grund.
local INVENTORY_REMOTES: { [string]: string } = {
    OpenCrate = "Gewinne aus der Kiste (Crates, Logic/CrateOpen)",
    EquipItem = "nur Ausrüstung, Besitz bleibt (Equipment)",
    MergeItem = "verbraucht Kopien desselben Items (Equipment)",
    BuyDirectItem = "Direktkauf gegen Gems (Crates, Logic/DirectShop)",
    ClaimDaily = "Daily Reward Tag 7: Eisenkiste gratis oder fester Ersatzgegenstand (Daily, Logic/Daily)",
    ClaimSeasonReward = "Saison-Pass: feste Belohnung einer erreichten Stufe, bei Items ein Pass-Item (passOnly), nie Kisten oder Zufall (SeasonPasses, Logic/SeasonPass, Paket 5.5b)",
}
-- Alle anderen Remotes vom Client zum Server, mit dem, was sie tun. Kommt eine neue dazu, muss sie
-- hier oder oben eingeordnet werden (der Test scheitert sonst).
local OTHER_REMOTES: { [string]: string } = {
    SetCollecting = "Sammeltaste",
    Stab = "Stich in den Sand (Überarbeitung Ü2): Zielpunkt und Halten, kein Inventar",
    Sell = "Sand verkaufen (nicht Items)",
    TravelZone = "Zone wechseln",
    PurchaseNode = "Skilltree-Knoten",
    SetAutoDig = "Einstellung",
    Prestige = "Sandsturm (behält das Inventar, siehe Sandstorm.KEEP_FIELDS)",
    RedeemCode = "Code einlösen: nur Gems, Münz- oder Glücks-Boost, nie Kisten oder Items (Codes, Logic/Codes, Paket 5.2)",
    GetLeaderboard = "liest die Wochen-Rangliste aus dem Zwischenspeicher des Servers (Leaderboard, Paket 5.7)",
    GetFriends = "Freundesliste des Spielers zum Besuchen, vom Server geholt (Leaderboard, Paket 5.7)",
    ViewCollection = "nur lesen: Sammlung eines Freundes, gewählt über einen Platz der Server-Liste, nie über eine UserId (Leaderboard, Paket 5.7)",
    BuySeasonPass = "öffnet nur den Roblox-Kaufdialog des Saison-Passes; gebucht wird in ProcessReceipt (Premium-Spur oder Ersatz-Gems, nie Items) (SeasonPasses, Paket 5.5b)",
}
-- Wo die Remotes mit Inventar registriert sein müssen.
local INVENTORY_SERVICES: { [string]: string } = {
    OpenCrate = "src/server/Services/Crates.luau",
    BuyDirectItem = "src/server/Services/Crates.luau",
    EquipItem = "src/server/Services/Equipment.luau",
    MergeItem = "src/server/Services/Equipment.luau",
    ClaimDaily = "src/server/Services/Daily.luau",
    ClaimSeasonReward = "src/server/Services/SeasonPasses.luau",
}
-- Dateien, die `.inventory = ...` zuweisen dürfen (Textsuche). Gutschriften aus Käufen (Starterpaket)
-- laufen über `changes.inventory` in Logic/Purchases (ProcessReceipt, keine Remote).
local INVENTORY_WRITERS: { [string]: string } = {
    ["src/shared/Logic/CrateOpen.luau"] = "OpenCrate",
    ["src/shared/Logic/DirectShop.luau"] = "BuyDirectItem",
    ["src/shared/Logic/Equipment.luau"] = "MergeItem",
    ["src/server/Services/Equipment.luau"] = "Studio-Hilfe DebugItem (nur in Studio)",
    ["src/shared/Logic/Daily.luau"] = "ClaimDaily (Tag 7)",
    ["src/shared/Logic/SeasonPass.luau"] = "ClaimSeasonReward (Pass-Items, Paket 5.5b)",
}
-- Datentabellen, gegen die eine ID-Regel prüfen darf (keine davon enthält Spieler).
local ID_TABLES = { Zones.byId, UpgradeTree.byId, Crates.byId, CrateItems.byId }
-- Freie Text-Argumente (ohne ID-Liste) sind nur hier erlaubt, mit Grund.
local FREE_TEXT_ARGS: { [string]: string } = {
    ["EquipItem#2"] = "Item-ID oder \"\" zum Abnehmen, der Server prüft gegen CrateItems",
    ["RedeemCode#1"] = "eingegebener Code, 1 bis 24 Zeichen; der Server normalisiert ihn und vergleicht nur mit seiner Code-Tabelle (Paket 5.2)",
}
-- Zahlenbereiche als Argument sind nur hier erlaubt, mit Grund, und höchstens bis SMALL_INT_MAX (eine
-- UserId wäre fast immer größer; der Server liest die Zahl ohnehin nie als Spieler).
-- Der Bereich steht genau fest (min und max): ändert er sich, schlägt der Test an und die Bedeutung
-- muss neu begründet werden.
local SMALL_INT_ARGS: { [string]: { min: number, max: number, reason: string } } = {
    ["ClaimSeasonReward#1"] = {
        min = 1,
        max = SeasonPass.MAX_TIERS,
        reason = "Stufennummer des Saison-Passes; der Server prüft sie gegen Data/SeasonPass (Paket 5.5b)",
    },
    ["ViewCollection#1"] = {
        min = 1,
        max = SocialData.leaderboard.maxFriends,
        reason = "Platz in der Freundesliste, die der Server mit GetFriends aufgebaut hat; der Client nennt nie eine UserId (Paket 5.7)",
    },
}
local SMALL_INT_MAX = 1000
-- Kommazahlen sind nur als Weltkoordinate erlaubt: Der Server nutzt sie für Reichweite und Zelle des
-- eigenen Spielers, nie als Verweis auf einen anderen Spieler (Überarbeitung Ü2).
local WORLD_COORD_ARGS: { [string]: boolean } = { ["Stab#1"] = true, ["Stab#2"] = true, ["Stab#3"] = true }
-- Wörter in Remote-Namen, die auf Tausch, Verkauf oder Verschenken hindeuten.
local FORBIDDEN_NAME_PARTS = { "trade", "gift", "send", "transfer", "give", "sellitem", "market" }

local function clientRemotes(): { [string]: any }
    local result: { [string]: any } = {}
    for _, def in RemoteSpec.list do
        if def.direction == "ClientToServer" then
            result[def.name] = def
        end
    end
    return result
end

T.describe("Kein Tausch, kein Verschenken, Inventar nur über bekannte Remotes", function()
    T.it("jede Remote vom Client ist eingeordnet: mit Inventar genau OpenCrate, EquipItem, MergeItem, BuyDirectItem, ClaimDaily, ClaimSeasonReward", function()
        local remotes = clientRemotes()
        for name in remotes do
            if INVENTORY_REMOTES[name] == nil and OTHER_REMOTES[name] == nil then
                error(`Remote "{name}" ist nicht eingeordnet: ändert sie das Inventar? (tests/policyguards.spec.luau)`)
            end
        end
        for name in INVENTORY_REMOTES do
            T.expect(remotes[name] ~= nil).toBe(true)
        end
        for name in OTHER_REMOTES do
            T.expect(remotes[name] ~= nil).toBe(true)
        end
        local names = {}
        for name in INVENTORY_REMOTES do
            table.insert(names, name)
        end
        table.sort(names)
        T.expect(names).toEqual({ "BuyDirectItem", "ClaimDaily", "ClaimSeasonReward", "EquipItem", "MergeItem", "OpenCrate" })
    end)

    T.it("jede Remote vom Client wird genau einmal registriert, die mit Inventar im vorgesehenen Service", function()
        local registeredIn: { [string]: { string } } = {}
        for path, source in SERVICE_SOURCES do
            for name in string.gmatch(source, 'Net%.on%(%s*"([%w_]+)"') do
                registeredIn[name] = registeredIn[name] or {}
                table.insert(registeredIn[name], path)
            end
        end
        local remotes = clientRemotes()
        for name, paths in registeredIn do
            if remotes[name] == nil then
                error(`Net.on("{name}") in {paths[1]}: keine Client->Server-Remote in RemoteSpec`)
            end
        end
        for name in remotes do
            local paths = registeredIn[name]
            if paths == nil or #paths ~= 1 then
                error(`Remote "{name}" ist {if paths then #paths else 0} Mal registriert (erwartet 1)`)
            end
            local expected = INVENTORY_SERVICES[name]
            if expected ~= nil then
                T.expect(paths[1]).toBe(expected)
            end
        end
        -- Net selbst registriert keine Handler.
        for path, source in NET_SOURCES do
            if string.find(source, 'Net%.on%(%s*"') then
                error(`{path} registriert selbst einen Handler`)
            end
        end
    end)

    T.it("nur bekannte Dateien weisen `.inventory = ...` zu (Textsuche)", function()
        local found: { [string]: boolean } = {}
        for _, sources in { SERVICE_SOURCES, LOGIC_SOURCES } do
            for path, source in sources do
                for line in string.gmatch(source, "[^\n]+") do
                    local code = string.match(line, "^(.-)%-%-") or line -- Kommentare ignorieren
                    if string.find(code, "%.inventory%s*=[^=]") then
                        found[path] = true
                    end
                end
            end
        end
        for path in found do
            if INVENTORY_WRITERS[path] == nil then
                error(`{path} weist .inventory zu, steht aber nicht in INVENTORY_WRITERS`)
            end
        end
        for path in INVENTORY_WRITERS do
            T.expect(found[path]).toBe(true)
        end
    end)

    T.it("kein Argument kann einen anderen Spieler nennen: keine Zahlenbereiche, IDs nur aus Datentabellen", function()
        local usedSmallInts: { [string]: boolean } = {}
        for name, def in clientRemotes() do
            local lower = string.lower(name)
            for _, part in FORBIDDEN_NAME_PARTS do
                if string.find(lower, part, 1, true) then
                    error(`Remote "{name}" klingt nach Tausch oder Verschenken ("{part}")`)
                end
            end
            for index, rule in def.schema do
                local label = `{name}#{index}`
                if rule.kind == "int" then
                    -- Eine freie Zahl könnte eine UserId sein: nur eingeordnete, kleine Bereiche.
                    local allowed = SMALL_INT_ARGS[label]
                    if allowed == nil then
                        error(`{label}: Zahlenbereich als Argument (könnte eine UserId sein)`)
                    end
                    if rule.min ~= allowed.min or rule.max ~= allowed.max or rule.max > SMALL_INT_MAX then
                        error(`{label}: Zahlenbereich {rule.min} bis {rule.max} weicht von der Liste ab ({allowed.min} bis {allowed.max}) oder ist zu groß (UserId?)`)
                    end
                    usedSmallInts[label] = true
                elseif rule.kind == "oneOf" then
                    for _, value in rule.values do
                        if type(value) == "number" and value > 1000 then
                            error(`{label}: erlaubte Zahl {value} ist zu groß (UserId?)`)
                        end
                    end
                elseif rule.kind == "idIn" then
                    local known = false
                    for _, ids in ID_TABLES do
                        if rawequal(rule.ids, ids) then
                            known = true
                        end
                    end
                    if not known then
                        error(`{label}: ID-Liste ist keine bekannte Datentabelle`)
                    end
                elseif rule.kind == "string" then
                    if FREE_TEXT_ARGS[label] == nil then
                        error(`{label}: freier Text als Argument (könnte ein Spielername sein)`)
                    end
                elseif rule.kind == "number" then
                    if WORLD_COORD_ARGS[label] == nil then
                        error(`{label}: Kommazahl als Argument ist nur als Weltkoordinate erlaubt`)
                    end
                elseif rule.kind ~= "boolean" then
                    error(`{label}: unbekannte Regel {tostring(rule.kind)}`)
                end
            end
        end
        -- Jeder Eintrag der Liste trifft noch eine echte Regel (keine Leichen).
        for label in SMALL_INT_ARGS do
            T.expect(usedSmallInts[label]).toBe(true)
        end
        -- Ein Player-Objekt oder eine Tabelle besteht keine Regel (Validate nimmt nur Text, Zahl, Boolean).
    end)

    T.it("der Sandsturm (Prestige) behält das Inventar", function()
        T.expect(table.find(Sandstorm.KEEP_FIELDS, "inventory") ~= nil).toBe(true)
        T.expect(table.find(Sandstorm.RESET_FIELDS, "inventory")).toBeNil()
    end)
end)

T.finish()
