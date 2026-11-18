--!strict
-- Paket 2.1: Skilltree-Daten und Kauf-Server (ganzer Baum, Wirkungen, Laden, Baum-Updates).

local T = require("./lib/expect")
local FakeStore = require("./lib/fakestore")
local TreePurchase = require("../src/shared/Logic/TreePurchase")
local TreeEffects = require("../src/shared/Logic/TreeEffects")
local Collecting = require("../src/shared/Logic/Collecting")
local Profile = require("../src/shared/Logic/Profile")
local PlayerSession = require("../src/shared/Logic/PlayerSession")
local BigNum = require("../src/shared/Logic/BigNum")
local DataCheck = require("../src/shared/Logic/DataCheck")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local Tools = require("../src/shared/Data/Tools")
local Zones = require("../src/shared/Data/Zones")
local SandTypes = require("../src/shared/Data/SandTypes")
local Economy = require("../src/shared/Data/Economy")

local NOW = 1_700_000_000

-- Zielzeiten aus docs/balance/skilltree_2_1.md, Variante "mit Glück-Knoten" (die Simulation
-- kauft immer den billigsten sichtbaren Knoten, also auch Glück), je ±15 %. Längste Pause
-- zwischen zwei Käufen: Konzept "höchstens etwa 2 Minuten".
local SIM = {
    limitSeconds = 3 * 60 * 60,
    toolSeconds = {
        collect_tool_3 = 7 * 60 + 8, -- Eimerkette, Oase
        collect_tool_4 = 11 * 60 + 21, -- Mini-Bagger, Canyon
        collect_tool_5 = 17 * 60 + 30, -- Saugroboter, Salzsee
        collect_tool_6 = 22 * 60 + 1, -- Großmaschine
    } :: { [string]: number },
    maxGapSeconds = 120,
}

local function withCoins(coins: number): any
    local profile = Profile.default(NOW)
    profile.coins = BigNum.serialize(BigNum.new(coins))
    return profile
end

local function coinsOf(profile: any): number
    return BigNum.toNumber(BigNum.deserialize(profile.coins))
end

local function purchasable(node: UpgradeTree.Node): boolean
    return node.granted ~= true and node.effect.kind ~= "grantedBySandstorm"
end

-- Steht `sandstorm_1` (oder ein anderer vergebener Knoten) in der Kette der Voraussetzungen?
local function behindGranted(nodeId: string, depth: number?): boolean
    local d = depth or 0
    if d > #UpgradeTree.list then
        return true
    end
    local node = UpgradeTree.byId[nodeId]
    for _, required in node.requires do
        local r = UpgradeTree.byId[required]
        if not purchasable(r) or behindGranted(required, d + 1) then
            return true
        end
    end
    return false
end

-- Gibt dem Profil alle Voraussetzungen des Knotens (rekursiv), ohne Münzen abzubuchen.
local function grantRequirements(profile: any, nodeId: string)
    for _, required in UpgradeTree.byId[nodeId].requires do
        grantRequirements(profile, required)
        profile.nodes[required] = true
    end
end

-- Kauft mit unbegrenzt Münzen alles, was geht, immer den billigsten verfügbaren Knoten.
local function buyEverything(profile: any): { string }
    local order = {}
    while true do
        profile.coins = BigNum.serialize(BigNum.new(1e300))
        local nextId = TreePurchase.visible(profile)[1]
        if nextId == nil then
            break
        end
        local ok = TreePurchase.buy(profile, nextId)
        T.expect(ok).toBe(true)
        table.insert(order, nextId)
    end
    return order
end

-- Ändert den Baum für einen Test (wie ein Update) und stellt ihn danach wieder her.
local function withTreeChange(change: () -> (), body: () -> ())
    local savedList = table.clone(UpgradeTree.list)
    local savedById = table.clone(UpgradeTree.byId)
    local savedNodes: { [string]: any } = {}
    for id, node in UpgradeTree.byId do
        savedNodes[id] = { requires = table.clone(node.requires), cost = node.cost, effect = table.clone(node.effect) }
    end
    local function restore()
        table.clear(UpgradeTree.list)
        for i, node in savedList do
            UpgradeTree.list[i] = node
        end
        table.clear(UpgradeTree.byId)
        for id, node in savedById do
            UpgradeTree.byId[id] = node
            node.requires = savedNodes[id].requires
            node.cost = savedNodes[id].cost
            node.effect = savedNodes[id].effect
        end
    end
    change()
    local ok, err = pcall(body)
    restore()
    if not ok then
        error(err, 0)
    end
end

local function removeNode(nodeId: string)
    for i, node in UpgradeTree.list do
        if node.id == nodeId then
            table.remove(UpgradeTree.list, i)
            break
        end
    end
    UpgradeTree.byId[nodeId] = nil
    -- Wer den Knoten verlangte, verlangt jetzt dessen Voraussetzungen (wie ein sauberes Update).
    for _, node in UpgradeTree.list do
        local requires = {}
        for _, required in node.requires do
            if required ~= nodeId then
                table.insert(requires, required)
            end
        end
        node.requires = requires
    end
end

local function addNode(node: any)
    table.insert(UpgradeTree.list, node)
    UpgradeTree.byId[node.id] = node
end

T.describe("Daten des ganzen Baums", function()
    T.it("DataCheck meldet keine Fehler", function()
        local errors = DataCheck.run()
        for _, e in errors do
            print(`       {e}`)
        end
        T.expect(#errors).toBe(0)
    end)

    T.it("alle vier Äste haben Knoten, jede Wirkung steht in ihrem Ast", function()
        local count: { [string]: number } = {}
        for _, node in UpgradeTree.list do
            count[node.branch] = (count[node.branch] or 0) + 1
        end
        for _, branch in { "collect", "tank", "sell", "luck" } do
            T.expect((count[branch] or 0) > 0).toBe(true)
        end
    end)

    T.it("Verkauf und Glück erscheinen erst nach der Schaufel", function()
        local profile = withCoins(0)
        for _, node in UpgradeTree.list do
            if node.branch == "sell" or node.branch == "luck" then
                T.expect(TreePurchase.nodeState(profile, node.id)).toBe("fog")
            end
        end
    end)

    T.it("jeder kaufbare Knoten ist erreichbar (unbegrenzt Münzen kaufen den ganzen Baum)", function()
        local profile = withCoins(0)
        buyEverything(profile)
        for _, node in UpgradeTree.list do
            if purchasable(node) and not behindGranted(node.id) then
                if profile.nodes[node.id] ~= true then
                    print(`       nicht erreichbar: {node.id}`)
                end
                T.expect(profile.nodes[node.id]).toBe(true)
            end
        end
        T.expect(Collecting.toolOf(profile).id).toBe(Tools.list[#Tools.list].id)
    end)

    T.it("eine kaputte Fassung schlägt fehl (Ast, bp, Meilenstein)", function()
        local data: any = DataCheck.defaults()
        local broken = table.clone(data.UpgradeTree.list)
        broken[#broken + 1] = {
            id = "sell_broken",
            name = "Kaputt",
            description = "kaputt",
            branch = "luck", -- falscher Ast für sellBonus
            requires = {},
            cost = 10,
            effect = { kind = "sellBonus", bp = 0 }, -- bp muss über 0 sein
            milestone = 0,
        }
        local byId = table.clone(data.UpgradeTree.byId)
        byId.sell_broken = broken[#broken]
        data.UpgradeTree = { list = broken, byId = byId }
        local errors = DataCheck.run(data)
        local text = table.concat(errors, "\n")
        T.expect(string.find(text, "gehört in den Ast", 1, true) ~= nil).toBe(true)
        T.expect(string.find(text, "sellBonus braucht bp", 1, true) ~= nil).toBe(true)
        T.expect(string.find(text, "milestone", 1, true) ~= nil).toBe(true)
    end)
end)

T.describe("Kauf im ganzen Baum", function()
    T.it("ohne Voraussetzung wird für jeden Knoten abgelehnt", function()
        for _, node in UpgradeTree.list do
            if purchasable(node) and #node.requires > 0 then
                local profile = withCoins(node.cost * 10)
                local ok, reason = TreePurchase.buy(profile, node.id)
                T.expect(ok).toBe(false)
                T.expect(reason).toBe("requires")
                T.expect(coinsOf(profile)).toBe(node.cost * 10)
                T.expect(next(profile.nodes)).toBeNil()
            end
        end
    end)

    T.it("Doppelklick kauft für keinen Knoten zweimal", function()
        for _, node in UpgradeTree.list do
            if purchasable(node) then
                local profile = withCoins(node.cost * 2)
                grantRequirements(profile, node.id)
                local ok1 = TreePurchase.buy(profile, node.id)
                local ok2, reason2 = TreePurchase.buy(profile, node.id)
                T.expect(ok1).toBe(true)
                T.expect(ok2).toBe(false)
                T.expect(reason2).toBe("owned")
                T.expect(coinsOf(profile)).toBe(node.cost)
            end
        end
    end)

    T.it("zu wenig Geld wird für jeden Knoten abgelehnt, genau der Preis geht auf 0", function()
        for _, node in UpgradeTree.list do
            if purchasable(node) then
                local profile = withCoins(node.cost - 1)
                grantRequirements(profile, node.id)
                local ok, reason = TreePurchase.buy(profile, node.id)
                T.expect(ok).toBe(false)
                T.expect(reason).toBe("coins")
                T.expect(coinsOf(profile)).toBe(node.cost - 1)
                T.expect(profile.nodes[node.id]).toBeNil()
                profile.coins = BigNum.serialize(BigNum.new(node.cost))
                T.expect(TreePurchase.buy(profile, node.id)).toBe(true)
                T.expect(coinsOf(profile)).toBe(0)
            end
        end
    end)
end)

T.describe("Kaputte Profile", function()
    T.it("Knoten-Werte außer true zählen nicht als gekauft, ein kaputtes nodes-Feld bucht nichts ab", function()
        local profile = withCoins(1000)
        profile.nodes = { tank_1 = 1, collect_tool_2 = "ja", collect_rate_1 = {} }
        T.expect(TreePurchase.nodeState(profile, "tank_1")).toBe("available")
        T.expect(TreePurchase.nodeState(profile, "tank_2")).toBe("fog")
        T.expect(Collecting.toolOf(profile).id).toBe("hand")
        T.expect(#Profile.ownedKnownNodes(profile, UpgradeTree.byId)).toBe(0)
        local broken = withCoins(1000)
        broken.nodes = "kaputt"
        local ok = TreePurchase.buy(broken, "tank_1")
        T.expect(ok).toBe(false)
        T.expect(coinsOf(broken)).toBe(1000)
    end)

    T.it("DataCheck lehnt einen Preis mit Nachkommastellen ab", function()
        local data: any = DataCheck.defaults()
        local list = table.clone(data.UpgradeTree.list)
        local byId = table.clone(data.UpgradeTree.byId)
        local node = table.clone(byId.tank_1)
        node.cost = 20.5
        byId.tank_1 = node
        for i, n in list do
            if n.id == "tank_1" then
                list[i] = node
            end
        end
        data.UpgradeTree = { list = list, byId = byId }
        local text = table.concat(DataCheck.run(data), "\n")
        T.expect(string.find(text, "cost muss eine ganze Zahl", 1, true) ~= nil).toBe(true)
    end)
end)

T.describe("Sichtbarkeit (Nebel)", function()
    T.it("am Anfang sind nur Knoten ohne Voraussetzung kaufbar, der Rest liegt im Nebel", function()
        local state = TreePurchase.treeState(withCoins(0))
        for _, node in UpgradeTree.list do
            local expected = if purchasable(node) and #node.requires == 0 then "available" else "fog"
            T.expect(state[node.id]).toBe(expected)
        end
    end)

    T.it("nach einem Kauf werden die Folgeknoten kaufbar", function()
        local profile = withCoins(1000)
        T.expect(TreePurchase.nodeState(profile, "tank_2")).toBe("fog")
        TreePurchase.buy(profile, "tank_1")
        T.expect(TreePurchase.nodeState(profile, "tank_1")).toBe("owned")
        T.expect(TreePurchase.nodeState(profile, "tank_2")).toBe("available")
        for _, node in UpgradeTree.list do
            local state = TreePurchase.nodeState(profile, node.id)
            if state == "available" then
                for _, required in node.requires do
                    T.expect(profile.nodes[required]).toBe(true)
                end
            end
        end
    end)

    T.it("der Sandsturm-Knoten ist nie kaufbar, nach dem Sturm gilt er als gekauft", function()
        local profile = withCoins(0)
        buyEverything(profile)
        T.expect(TreePurchase.nodeState(profile, "sandstorm_1")).toBe("fog")
        profile.nodes.sandstorm_1 = true
        T.expect(TreePurchase.nodeState(profile, "sandstorm_1")).toBe("owned")
        T.expect(TreePurchase.nodeState(profile, "gibt_es_nicht")).toBeNil()
    end)
end)

T.describe("Wirkung", function()
    T.it("Verkauf-Knoten erhöhen die Münzen pro Sand, Boni addieren sich", function()
        local profile = withCoins(0)
        local base = Economy.baseCoinsPerSand * SandTypes.byId[Zones.byId.dunes.sandTypeId].priceFactor
        T.expect(Collecting.pricePerSand(profile)).toBe(base)
        local sumBp = 0
        for _, node in UpgradeTree.list do
            if node.effect.kind == "sellBonus" then
                profile.nodes[node.id] = true
                sumBp += node.effect.bp :: number
                T.expect(Collecting.pricePerSand(profile)).toBeCloseTo(base * (10000 + sumBp) / 10000, 1e-9)
            end
        end
        T.expect(sumBp > 0).toBe(true)
        T.expect(TreeEffects.of(profile).sellBonusBp).toBe(sumBp)
    end)

    T.it("Verkaufen mit Bonus bucht ganze Münzen, Bruchteile verfallen", function()
        local profile = withCoins(0)
        local first: UpgradeTree.Node? = nil
        for _, node in UpgradeTree.list do
            if node.effect.kind == "sellBonus" then
                first = node
                break
            end
        end
        assert(first, "kein Verkauf-Knoten")
        profile.nodes[first.id] = true
        profile.tank = BigNum.serialize(BigNum.new(7))
        local earned = Collecting.sell(Collecting.newState(NOW), profile, NOW)
        local expected = math.floor(7 * Collecting.pricePerSand(profile))
        T.expect(BigNum.toNumber(earned :: any)).toBe(expected)
        T.expect(coinsOf(profile)).toBe(expected)
    end)

    T.it("Verkaufen ohne Bonus verliert keine Münze (115, 230, 1150 Sand)", function()
        for _, amount in { 115, 230, 1150, 7, 999_999 } do
            local profile = withCoins(0)
            profile.tank = BigNum.serialize(BigNum.new(amount))
            Collecting.sell(Collecting.newState(NOW), profile, NOW)
            T.expect(coinsOf(profile)).toBe(amount)
        end
        T.expect(BigNum.toNumber(BigNum.floor(BigNum.new(115)))).toBe(115)
        T.expect(BigNum.toNumber(BigNum.floor(BigNum.new(2.3 * 100)))).toBe(230)
        T.expect(BigNum.toNumber(BigNum.floor(BigNum.new(16.5)))).toBe(16)
        T.expect(BigNum.toNumber(BigNum.floor(BigNum.new(-1.5)))).toBe(-2)
    end)

    T.it("Glück-Knoten erhöhen den Fundchancen-Faktor, Boni addieren sich", function()
        local profile = withCoins(0)
        T.expect(TreeEffects.luckMultiplier(profile)).toBe(1)
        local sumBp = 0
        for _, node in UpgradeTree.list do
            if node.effect.kind == "luckBonus" then
                profile.nodes[node.id] = true
                sumBp += node.effect.bp :: number
            end
        end
        T.expect(sumBp > 0).toBe(true)
        T.expect(TreeEffects.luckMultiplier(profile)).toBeCloseTo((10000 + sumBp) / 10000, 1e-9)
    end)

    T.it("Rate und Tank folgen dem ganzen Baum, unbekannte IDs ändern nichts", function()
        local profile = withCoins(0)
        buyEverything(profile)
        local effects = TreeEffects.of(profile)
        local rateBp, tank = 0, Economy.startTankCapacity
        for _, node in UpgradeTree.list do
            if profile.nodes[node.id] then
                if node.effect.kind == "rateBonus" then
                    rateBp += node.effect.bp :: number
                elseif node.effect.kind == "setTank" then
                    tank = math.max(tank, node.effect.capacity :: number)
                end
            end
        end
        T.expect(effects.rateBonusBp).toBe(rateBp)
        T.expect(effects.tankCapacity).toBe(tank)
        T.expect(Collecting.rateOf(profile)).toBeCloseTo(effects.tool.sandPerSecond * (10000 + rateBp) / 10000, 1e-9)
        local before = TreeEffects.of(profile)
        profile.nodes.sell_999 = true
        profile.nodes.luck_alt = true
        profile.nodes.tank_99 = true
        T.expect(TreeEffects.of(profile)).toEqual(before)
    end)
end)

T.describe("Laden", function()
    T.it("gekaufte Knoten und ihre Wirkung überstehen Speichern und Laden auf einem neuen Server", function()
        local world = FakeStore.newWorld()
        local function manager(name: string): PlayerSession.Manager
            return PlayerSession.new({
                store = FakeStore.newServer(world, name),
                now = function()
                    return NOW
                end,
                kick = function() end,
                log = function() end,
            })
        end
        local present = function()
            return true
        end
        local a = manager("A")
        local profile: any = a.load(7, present)
        profile.coins = BigNum.serialize(BigNum.new(5_000_000))
        local bought = 0
        for _ = 1, 25 do
            local nextId = TreePurchase.visible(profile)[1]
            if nextId == nil or not TreePurchase.buy(profile, nextId) then
                break
            end
            bought += 1
        end
        T.expect(bought).toBe(25)
        local nodesBefore = table.clone(profile.nodes)
        local coinsBefore = coinsOf(profile)
        local effectsBefore = TreeEffects.of(profile)
        local priceBefore = Collecting.pricePerSand(profile)
        a.release(7)

        local b = manager("B")
        local again: any = b.load(7, present)
        T.expect(again.nodes).toEqual(nodesBefore)
        T.expect(coinsOf(again)).toBe(coinsBefore)
        T.expect(TreeEffects.of(again)).toEqual(effectsBefore)
        T.expect(Collecting.pricePerSand(again)).toBe(priceBefore)
    end)
end)

T.describe("Baum-Update", function()
    T.it("Knoten entfernt: Profil lädt, ID bleibt, wirkt nicht, keine Erstattung", function()
        local profile = withCoins(1000)
        TreePurchase.buy(profile, "tank_1")
        TreePurchase.buy(profile, "tank_2")
        local saved = FakeStore.deepCopy(profile)
        withTreeChange(function()
            removeNode("tank_2")
        end, function()
            local loaded: any, status = Profile.migrate(FakeStore.deepCopy(saved), nil, NOW)
            T.expect(status).toBe("ok")
            T.expect(#Profile.sanitize(loaded, NOW)).toBe(0)
            T.expect(loaded.nodes.tank_2).toBe(true)
            T.expect(coinsOf(loaded)).toBe(coinsOf(saved))
            T.expect(Collecting.capacityOf(loaded)).toBe(UpgradeTree.byId.tank_1.effect.capacity)
            T.expect(Collecting.ownedNodes(loaded).tank_2).toBeNil()
            -- Folgekäufe gehen weiter (tank_3 verlangt jetzt tank_1).
            loaded.coins = BigNum.serialize(BigNum.new(1000))
            T.expect(TreePurchase.buy(loaded, "tank_3")).toBe(true)
        end)
    end)

    T.it("Knoten hinzugefügt: altes Profil lädt, der neue Knoten wird kaufbar", function()
        local old: any = Profile.default(NOW)
        old.nodes = { collect_rate_1 = true, tank_1 = true, collect_tool_2 = true }
        old.coins = BigNum.serialize(BigNum.new(500))
        withTreeChange(function()
            addNode({
                id = "collect_rate_test",
                name = "Test",
                description = "+10 % Sand pro Sekunde",
                branch = "collect",
                requires = { "collect_tool_2" },
                cost = 100,
                effect = { kind = "rateBonus", bp = 1000 },
            })
        end, function()
            local loaded: any = Profile.migrate(FakeStore.deepCopy(old), nil, NOW)
            T.expect(loaded.nodes).toEqual(old.nodes)
            T.expect(TreePurchase.nodeState(loaded, "collect_rate_test")).toBe("available")
            local rate = Collecting.rateOf(loaded)
            T.expect(TreePurchase.buy(loaded, "collect_rate_test")).toBe(true)
            T.expect(Collecting.rateOf(loaded)).toBeCloseTo(rate + Tools.byId.shovel.sandPerSecond * 0.1, 1e-9)
        end)
    end)

    T.it("neue Voraussetzung vor einem gekauften Knoten: Der gekaufte wirkt weiter", function()
        local profile = withCoins(1000)
        TreePurchase.buy(profile, "tank_1")
        TreePurchase.buy(profile, "tank_2")
        withTreeChange(function()
            addNode({
                id = "tank_1b",
                name = "Test",
                description = "Tank 45",
                branch = "tank",
                requires = { "tank_1" },
                cost = 40,
                effect = { kind = "setTank", capacity = 45 },
            })
            UpgradeTree.byId.tank_2.requires = { "tank_1b" }
        end, function()
            T.expect(#DataCheck.run()).toBe(0)
            T.expect(Collecting.capacityOf(profile)).toBe(UpgradeTree.byId.tank_2.effect.capacity)
            T.expect(TreePurchase.nodeState(profile, "tank_2")).toBe("owned")
            T.expect(TreePurchase.nodeState(profile, "tank_1b")).toBe("available")
            T.expect(TreePurchase.buy(profile, "tank_1b")).toBe(true)
        end)
    end)

    T.it("geänderte Werte: Wirkung folgt der neuen Tabelle, Preisänderung bucht nichts nach", function()
        local profile = withCoins(100)
        TreePurchase.buy(profile, "collect_rate_1")
        local coins = coinsOf(profile)
        withTreeChange(function()
            UpgradeTree.byId.collect_rate_1.effect = { kind = "rateBonus", bp = 10000 }
            UpgradeTree.byId.collect_rate_1.cost = 999
        end, function()
            T.expect(Collecting.rateOf(profile)).toBe(2)
            T.expect(coinsOf(profile)).toBe(coins)
        end)
        T.expect(Collecting.rateOf(profile)).toBe(1.5)
    end)
end)

-- Zeit-Simulation des ganzen ersten Laufs mit den echten Regeln, wie
-- docs/balance/skilltree_2_1.py: Tank füllen (Server-Uhr, Auffrischung alle 0,25 s), 5 s Weg je
-- Richtung, verkaufen, dann den billigsten sichtbaren Knoten kaufen, solange das Geld reicht.
-- Gesammelt wird immer in der besten freigeschalteten Zone (die Reise selbst kommt in 2.5).
local WALK_SECONDS = 5

local function bestZone(profile: any): string
    local best = "dunes"
    local bestFactor = 0
    for _, zone in Zones.list do
        local open = zone.requires == "start" or profile.nodes[zone.requires] == true
        local factor = SandTypes.byId[zone.sandTypeId].priceFactor
        if open and factor > bestFactor then
            best, bestFactor = zone.id, factor
        end
    end
    return best
end

local function simulateRun(limitSeconds: number): ({ [string]: number }, number)
    local profile = withCoins(0)
    local state = Collecting.newState(0)
    local t = 0
    local boughtAt: { [string]: number } = {}
    local lastBuy = 0
    local longestGap = 0
    local finalTool = Tools.list[#Tools.list].nodeId
    while t < limitSeconds and boughtAt[finalTool] == nil do
        -- Sammeln, bis der Tank voll ist. Schritte von 0,25 s wie der Server-Takt.
        Collecting.setHolding(state, profile, true, t)
        local guard = 0
        while not Collecting.isFull(profile) and guard < 100000 do
            t += 0.25
            Collecting.setHolding(state, profile, true, t)
            guard += 1
        end
        Collecting.setHolding(state, profile, false, t)
        t += WALK_SECONDS
        Collecting.sell(state, profile, t)
        while true do
            local nextId = TreePurchase.visible(profile)[1]
            if nextId == nil or TreePurchase.check(profile, nextId) ~= nil then
                break
            end
            TreePurchase.buy(profile, nextId)
            boughtAt[nextId] = t
            longestGap = math.max(longestGap, t - lastBuy)
            lastBuy = t
        end
        profile.currentZone = bestZone(profile)
        t += WALK_SECONDS
    end
    return boughtAt, longestGap
end

T.describe("Ganzer Lauf (Simulation)", function()
    T.it("Werkzeuge kommen zu den Zeiten der Balance-Tabelle, keine zu lange Pause", function()
        local boughtAt, longestGap = simulateRun(SIM.limitSeconds)
        local line = {}
        for _, tool in Tools.list do
            if tool.nodeId ~= "start" then
                table.insert(line, `{tool.id} {boughtAt[tool.nodeId] or "-"} s`)
            end
        end
        print(`       {table.concat(line, ", ")}, längste Pause {longestGap} s`)
        T.expect(math.abs(boughtAt.collect_rate_1 - Economy.targetSeconds.firstUpgrade) <= Economy.targetSeconds.firstUpgrade * 0.15).toBe(true)
        T.expect(math.abs(boughtAt.collect_tool_2 - Economy.targetSeconds.shovel) <= Economy.targetSeconds.shovel * 0.15).toBe(true)
        for nodeId, target in SIM.toolSeconds do
            local at = boughtAt[nodeId]
            T.expect(at ~= nil).toBe(true)
            if at ~= nil and math.abs(at - target) > target * 0.15 then
                print(`       {nodeId}: {at} s statt etwa {target} s`)
                T.expect(false).toBe(true)
            end
        end
        T.expect(longestGap <= SIM.maxGapSeconds).toBe(true)
    end)
end)

T.finish()
