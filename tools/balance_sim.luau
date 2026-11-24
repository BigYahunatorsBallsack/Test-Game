--!strict
-- Balancing-Simulation (Paket 6.4). Simuliert einen Spieler mit den echten reinen Logikmodulen
-- (Collecting, TreePurchase, Zones, FindRoll, Collection, Sandstorm, Wind, Perks, Offline) und den
-- echten Datentabellen unter src/shared/Data.
--
-- Aufruf im Projektordner:
--   lune run tools/balance_sim [Teil] [Startwert]
-- Teil: "all" (Standard, etwa 1 min), "base", "passes", "crystals", "storm", "casual", "crates",
-- "proposals", "recommended", "explore", "explorelong", "long".
-- Gleicher Startwert ergibt dieselbe Ausgabe. Ausgabe als Markdown-Tabellen auf der Konsole, der
-- Bericht docs/balance-6.4.md übernimmt sie.
--
-- Das Skript ändert keine Datei. Vorschläge werden nur im Speicher dieses Prozesses ausprobiert
-- (`withPatch`): Werte in den geladenen Datentabellen werden gesetzt, die Simulation läuft, danach
-- stellt das Skript die alten Werte wieder her.
--
-- Modell (Annahmen, siehe Bericht):
--  * Schleife: sammeln, bis der Tank voll ist (Server-Takt 0,25 s, der Client frischt das Halten
--    auf), WALK Sekunden zum Händler, verkaufen, kaufen, WALK Sekunden zurück. Mit Auto-Dig sammelt
--    das Werkzeug schon auf dem Rückweg (obere Schranke, wie in Paket 2.1).
--  * Kaufregel: wie der Lune-Test (`TreePurchase.visible(profile)[1]`): immer der billigste sichtbare
--    Knoten, sonst sparen. Glück-Ast und Ruinenkarte werden mitgekauft.
--  * Zone: nach jedem Kauf reist der Spieler in die freie Zone mit dem höchsten Sandfaktor (die
--    Reise kostet keine Zeit, der Rückweg zum Feld zählt wie immer).
--  * Funde: je Füllung holt das Skript die echte Sammelzeit (`Collecting.takeFindSeconds`), würfelt
--    in Fenstern von 0,25 s wie der Server (Chance je Fenster aus `FindRoll.chancePerSecond` und
--    `FindRoll.chanceInWindow`, Wetter zum Beginn der Füllung) und lässt Seltenheit, Fundstück und
--    Wert von `FindRoll.roll` bestimmen. `Collection.record` bucht Duplikate wie im Spiel.
--  * Sandsturm: `Sandstorm.apply` mit den Options des Spielers. Strategien in `wantStorm`: "stall"
--    (Standard: nichts mehr zu kaufen oder der nächste Knoten kostet über 3 min Sparen), "treeEnd",
--    "treeEndPlus", "asap" (sobald minCrystals erreicht), "threshold", "optimal" (Kristalle pro Laufminute).

local process = require("@lune/process")

local BigNum = require("../src/shared/Logic/BigNum")
local Collecting = require("../src/shared/Logic/Collecting")
local Collection = require("../src/shared/Logic/Collection")
local CrateRoll = require("../src/shared/Logic/CrateRoll")
local FindRoll = require("../src/shared/Logic/FindRoll")
local Offline = require("../src/shared/Logic/Offline")
local Perks = require("../src/shared/Logic/Perks")
local Profile = require("../src/shared/Logic/Profile")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local TreeEffects = require("../src/shared/Logic/TreeEffects")
local TreePurchase = require("../src/shared/Logic/TreePurchase")
local Wind = require("../src/shared/Logic/Wind")
local DataCheck = require("../src/shared/Logic/DataCheck")
local ZoneLogic = require("../src/shared/Logic/Zones")

local Crates = require("../src/shared/Data/Crates")
local CrateItems = require("../src/shared/Data/CrateItems")
local Economy = require("../src/shared/Data/Economy")
local FindsData = require("../src/shared/Data/Finds")
local GemPacks = require("../src/shared/Data/GemPacks")
local Products = require("../src/shared/Data/Products")
local Rarities = require("../src/shared/Data/Rarities")
local SandTypes = require("../src/shared/Data/SandTypes")
local Tools = require("../src/shared/Data/Tools")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local Zones = require("../src/shared/Data/Zones")

-- Konstanten des Modells
local TICK = 0.25 -- Server-Takt (Sand und Funde)
local WALK = 5 -- Sekunden je Richtung zum Händler (wie Paket 1.6, 2.1, 2.7)
local UNIX0 = 1_800_000_000 -- Start der Uhr (Unix), nur für Boost und Offline
local EARLY_SECONDS = 2 * 3600 -- "erste 2 Stunden" für die Engpass-Regel
local GAP_EARLY = 10 * 60 -- Engpass: Pause zwischen zwei Fortschritten über 10 min in den ersten 2 h
local GAP_LATE = 30 * 60 -- ... über 30 min danach

local args = process.args
local PART = args[1] or "all"
local SEED = tonumber(args[2]) or 64

---------------------------------------------------------------------------------------------------
-- Hilfen: Formatierung
---------------------------------------------------------------------------------------------------

local function fmtTime(seconds: number?): string
    if seconds == nil then
        return "-"
    end
    local s = math.floor(seconds + 0.5)
    local h = s // 3600
    local m = (s % 3600) // 60
    local r = s % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, r)
    end
    return string.format("%d:%02d", m, r)
end

local function fmtDays(seconds: number?): string
    if seconds == nil then
        return "-"
    end
    return string.format("%.1f d", seconds / 86400)
end

local function fmtNum(value: number?): string
    if value == nil then
        return "-"
    end
    if value ~= value or value == math.huge then
        return tostring(value)
    end
    if math.abs(value) < 1000 then
        return (string.format("%.0f", value))
    end
    return BigNum.format(BigNum.new(value), 1)
end

local function fmtPct(x: number): string
    return string.format("%+.0f %%", x * 100)
end

local function row(cells: { any })
    local out = {}
    for i, cell in cells do
        out[i] = tostring(cell)
    end
    print("| " .. table.concat(out, " | ") .. " |")
end

local function header(cells: { string })
    row(cells)
    local dashes = {}
    for i = 1, #cells do
        dashes[i] = "---"
    end
    row(dashes)
end

local function title(text: string)
    print("")
    print("### " .. text)
    print("")
end

---------------------------------------------------------------------------------------------------
-- Vorschläge nur im Speicher ausprobieren
---------------------------------------------------------------------------------------------------

-- patch = { { tbl, key, value }, ... , addNodes = { node, ... } }
local function withPatch<T>(patch: any, fn: () -> T): T
    local undo = {}
    for _, entry in patch do
        if type(entry) == "table" and entry[1] ~= nil then
            table.insert(undo, { entry[1], entry[2], entry[1][entry[2]] })
            entry[1][entry[2]] = entry[3]
        end
    end
    local added = {}
    if patch.addNodes then
        for _, node in patch.addNodes do
            table.insert(UpgradeTree.list, node)
            UpgradeTree.byId[node.id] = node
            table.insert(added, node.id)
        end
    end
    local ok, result = pcall(fn)
    for i = #undo, 1, -1 do
        local u = undo[i]
        u[1][u[2]] = u[3]
    end
    for _, id in added do
        UpgradeTree.byId[id] = nil
        for i = #UpgradeTree.list, 1, -1 do
            if UpgradeTree.list[i].id == id then
                table.remove(UpgradeTree.list, i)
            end
        end
    end
    if not ok then
        error(result, 0)
    end
    return result
end

local function nodeCost(id: string, cost: number): { any }
    return { UpgradeTree.byId[id], "cost", cost }
end

---------------------------------------------------------------------------------------------------
-- Simulation eines Spielers
---------------------------------------------------------------------------------------------------

export type Config = {
    name: string,
    passes: { string }?, -- Gamepass-IDs aus Data/Products ("double_coins", "auto_dig", "big_tank")
    coinBoost: string?, -- "none" | "always" (immer nachkaufen) | "first" (einmal 30 min am Anfang) | "session"
    storm: string?, -- Sturm-Strategie, siehe STORM_POLICIES
    stormArg: number?,
    activeSeconds: number, -- Spielzeit (aktiv), nach der die Simulation endet
    sessions: { active: number, perDay: number, companion: boolean }?, -- Gelegenheitsspieler mit Offline-Ertrag
    companion: boolean?, -- Begleiter ausgerüstet (Offline-Ertrag, +5 % Sammelrate)
    offlineAtTreeEnd: number?, -- Sekunden offline am Baumende vor dem Sturm (Variante)
    runEarnedWithoutCoinFactor: boolean?, -- Logik-Vorschlag: runEarned ohne 2x-Pass und Münz-Boost
    walk: number?,
    seed: number?,
    maxRuns: number?,
}

type Event = { t: number, real: number, run: number, kind: string, id: string, extra: any? }

local BRANCHES = { "collect", "tank", "sell", "luck" }

-- Knoten je Ast (ohne vergebene), für "Ast fertig".
local function branchNodes(): { [string]: { string } }
    local result: { [string]: { string } } = {}
    for _, node in UpgradeTree.list do
        if node.granted ~= true and node.branch ~= "sandstorm" then
            result[node.branch] = result[node.branch] or {}
            table.insert(result[node.branch], node.id)
        end
    end
    return result
end

local function bestZone(profile: any): string
    local best, bestFactor = Zones.list[1].id, -1
    for _, zone in Zones.list do
        if ZoneLogic.isUnlocked(profile, zone.id) then
            local f = SandTypes.byId[zone.sandTypeId].priceFactor
            if f > bestFactor then
                best, bestFactor = zone.id, f
            end
        end
    end
    return best
end

local function toolTier(profile: any): number
    return TreeEffects.of(profile).tool.tier
end

-- Stetige Kristallzahl (ohne Abrunden), nur für die Entscheidung "optimal".
local function crystalsContinuous(earned: number): number
    local cfg = Economy.sandstorm
    if earned <= 0 then
        return 0
    end
    return cfg.crystalScale * (earned / cfg.crystalUnit) ^ cfg.crystalExponent
end

local function simulate(cfg: Config): any
    math.randomseed(cfg.seed or SEED)
    local walk = cfg.walk or WALK
    local profile: any = Profile.default(UNIX0)
    for _, passId in cfg.passes or {} do
        profile.passes[passId] = true
    end
    local autoDig = Perks.owns(profile, "autoDig")
    if cfg.companion or (cfg.sessions and cfg.sessions.companion) then
        profile.inventory.companions.companion_common_1 = 1
        profile.equipped.companion = "companion_common_1"
    end
    local state = Collecting.newState(0)
    local sim = {
        cfg = cfg,
        profile = profile,
        t = 0, -- aktive Spielzeit
        real = 0, -- echte Zeit (mit Offline)
        run = 1,
        runStart = 0,
        runStartReal = 0,
        events = {} :: { Event },
        firstBuy = {} :: { [string]: number }, -- nur Lauf 1
        runs = {} :: { any },
        earnedTotal = 0,
        boostsBought = 0,
        sessionCollect = 0,
        phase = {} :: { [string]: { seconds: number, earned: number } },
        sets = {} :: { [string]: { t: number, real: number, run: number } },
        rarityFirst = {} :: { [string]: { t: number, real: number } },
        findsCount = 0,
        lastTreeEnd = nil :: number?,
        stormCrystals = {} :: { number },
        bestRatio = 0,
        declines = 0,
        offlineCoins = 0,
        incomeRate = 0,
        boughtThisRun = {} :: { [string]: boolean },
        branchDone = {} :: { [string]: number }, -- Lauf 1
    }
    local branches = branchNodes()

    local function unix(): number
        return UNIX0 + sim.real
    end
    local function opts(): any
        return Perks.options(profile, unix())
    end
    local function log(kind: string, id: string, extra: any?)
        table.insert(sim.events, { t = sim.t, real = sim.real, run = sim.run, kind = kind, id = id, extra = extra, tool = TreeEffects.of(profile).tool.id })
    end
    local function phaseKey(): string
        local run = if sim.run <= 3 then tostring(sim.run) else (if sim.run <= 10 then "4-10" else "11+")
        return run .. ":" .. TreeEffects.of(profile).tool.id
    end
    local function addEarned(amount: number, dtActive: number?)
        sim.earnedTotal += amount
        local key = phaseKey()
        local p = sim.phase[key]
        if p == nil then
            p = { seconds = 0, earned = 0 }
            sim.phase[key] = p
        end
        p.earned += amount
    end
    local function addPhaseTime(dt: number)
        local key = phaseKey()
        local p = sim.phase[key]
        if p == nil then
            p = { seconds = 0, earned = 0 }
            sim.phase[key] = p
        end
        p.seconds += dt
    end
    local function advance(dt: number)
        addPhaseTime(dt)
        sim.t += dt
        sim.real += dt
    end

    local function ensureBoost()
        local mode = cfg.coinBoost or "none"
        if mode == "always" then
            if not Perks.coinBoostActive(profile, unix()) then
                profile.boosts = Perks.extendCoinBoost(profile.boosts, unix(), Economy.coinBoost.durationSeconds)
                sim.boostsBought += 1
            end
        end
    end

    -- Würfelt Funde für die echte Sammelzeit je Zone.
    local function rollFinds(secondsByZone: { [string]: number })
        for zoneId, secs in secondsByZone do
            sim.sessionCollect += secs
            local windows = math.floor(secs / TICK + 0.5)
            if windows <= 0 then
                continue
            end
            local function record(roll: any)
                if roll == nil then
                    return
                end
                local rec = Collection.record(profile, roll.find.id, roll.value)
                if rec == nil then
                    return
                end
                sim.findsCount += 1
                if rec.coins then
                    addEarned(BigNum.toNumber(rec.coins))
                end
                if rec.isNew and sim.rarityFirst[rec.rarityId] == nil then
                    sim.rarityFirst[rec.rarityId] = { t = sim.t, real = sim.real }
                end
                if rec.setCompleted and sim.sets[rec.setId] == nil then
                    sim.sets[rec.setId] = { t = sim.t, real = sim.real, run = sim.run }
                    log("set", rec.setId)
                end
            end
            -- Erster Fund sicher (FindRoll entscheidet selbst, ob er greift).
            if Collection.distinctFound(profile) == 0 then
                local roll = FindRoll.roll({
                    profile = profile,
                    zoneId = zoneId,
                    seconds = TICK,
                    serverTime = unix(),
                    unixTime = unix(),
                    sessionSeconds = sim.sessionCollect,
                    random = math.random,
                })
                record(roll)
            end
            local p = FindRoll.chancePerSecond(profile, zoneId, unix(), nil, unix())
            local q = FindRoll.chanceInWindow(p, TICK)
            if q <= 0 then
                continue
            end
            local k = 0
            while true do
                local u = math.random()
                local skip = if q >= 1 then 0 else math.floor(math.log(1 - u) / math.log(1 - q))
                k += skip + 1
                if k > windows then
                    break
                end
                local seq = { 0, math.random(), math.random() }
                local i = 0
                local roll = FindRoll.roll({
                    profile = profile,
                    zoneId = zoneId,
                    seconds = TICK,
                    serverTime = unix(),
                    unixTime = unix(),
                    sessionSeconds = math.max(sim.sessionCollect, 1e9),
                    random = function(): number
                        i += 1
                        return seq[i] or math.random()
                    end,
                })
                record(roll)
            end
        end
    end

    -- Sammeln bis voll (oder bis `limit` Sekunden).
    local function fill(limit: number?)
        local o = opts()
        Collecting.setHolding(state, profile, true, sim.t, o)
        local space = Collecting.space(profile, o)
        if space <= 0 then
            Collecting.setHolding(state, profile, false, sim.t, o)
            return
        end
        local rate = Collecting.rateOf(profile)
        local need = (space - state.carry) / rate
        local dt = math.max(math.ceil(need / TICK - 1e-9) * TICK, TICK)
        if limit ~= nil then
            dt = math.min(dt, limit)
        end
        state.holdUntil = sim.t + dt + 1 -- der Client frischt das Halten auf
        local tEnd = sim.t + dt
        Collecting.update(state, profile, tEnd, o)
        Collecting.setHolding(state, profile, false, tEnd, o)
        advance(dt)
        rollFinds(Collecting.takeFindSeconds(state))
    end

    local function sell()
        ensureBoost()
        local o = opts()
        local before = BigNum.toNumber(Wind.runEarned(profile))
        local earned = Collecting.sell(state, profile, sim.t, o)
        if earned ~= nil then
            local amount = BigNum.toNumber(earned)
            addEarned(amount)
            if cfg.runEarnedWithoutCoinFactor and (o.coinMultiplier or 1) > 1 then
                -- Logik-Vorschlag (nicht im Spiel): runEarned zählt den Verkauf ohne Münz-Faktor.
                local without = before + amount / o.coinMultiplier
                profile.runEarned = BigNum.serialize(BigNum.new(without))
            end
        end
    end

    local function treeComplete(): boolean
        return TreePurchase.visible(profile)[1] == nil
    end

    local function buyAll()
        while true do
            local nextId = TreePurchase.visible(profile)[1]
            if nextId == nil or TreePurchase.check(profile, nextId) ~= nil then
                break
            end
            local toolBefore = TreeEffects.of(profile).tool.id
            TreePurchase.buy(profile, nextId)
            sim.boughtThisRun[nextId] = true
            log("buy", nextId)
            sim.events[#sim.events].tool = toolBefore -- Phase, in der gespart wurde
            if sim.run == 1 and sim.firstBuy[nextId] == nil then
                sim.firstBuy[nextId] = sim.t
            end
            if sim.run == 1 then
                for branch, ids in branches do
                    if sim.branchDone[branch] == nil then
                        local all = true
                        for _, id in ids do
                            if not sim.boughtThisRun[id] then
                                all = false
                                break
                            end
                        end
                        if all then
                            sim.branchDone[branch] = sim.t
                        end
                    end
                end
            end
        end
        for _, zoneId in ZoneLogic.unlockNew(profile) do
            log("zone", zoneId)
        end
        local zone = bestZone(profile)
        if zone ~= profile.currentZone then
            Collecting.setZone(state, profile, zone, sim.t, opts())
        end
        if treeComplete() and sim.lastTreeEnd == nil then
            sim.lastTreeEnd = sim.t
            log("treeEnd", tostring(sim.run))
        end
    end

    local function doStorm(): boolean
        local o = opts()
        local runTotal = BigNum.toNumber(Sandstorm.runTotal(profile, o))
        local result = Sandstorm.apply(profile, nil, o)
        if result == nil then
            return false
        end
        table.insert(sim.runs, {
            run = sim.run,
            duration = sim.t - sim.runStart,
            durationReal = sim.real - sim.runStartReal,
            treeEnd = if sim.lastTreeEnd then sim.lastTreeEnd - sim.runStart else nil,
            crystals = result.crystals,
            total = result.total,
            earned = runTotal,
            at = sim.t,
            atReal = sim.real,
            setBonusBp = Collection.bonusBp(profile),
        })
        log("storm", tostring(sim.run), result.crystals)
        sim.run += 1
        sim.runStart = sim.t
        sim.runStartReal = sim.real
        sim.lastTreeEnd = nil
        sim.bestRatio = 0
        sim.declines = 0
        sim.boughtThisRun = {}
        state = Collecting.newState(sim.t)
        return true
    end

    local function wantStorm(): boolean
        local o = opts()
        local view = Sandstorm.preview(profile, nil, o)
        if not view.ready then
            return false
        end
        local policy = cfg.storm or "stall"
        if policy == "asap" then
            return true
        elseif policy == "threshold" then
            return view.gain >= (cfg.stormArg or 20)
        elseif policy == "treeEnd" then
            return treeComplete()
        elseif policy == "stall" then
            -- "Sinnvoll": stürmen, wenn nichts mehr zu kaufen ist oder der nächste Knoten beim jetzigen
            -- Ertrag länger als `stormArg` Sekunden (Standard 180) Sparen kostet.
            local nextId = TreePurchase.visible(profile)[1]
            if nextId == nil then
                return true
            end
            local missing = UpgradeTree.byId[nextId].cost - BigNum.toNumber(BigNum.deserialize(profile.coins))
            return sim.incomeRate > 0 and missing / sim.incomeRate > (cfg.stormArg or 180)
        elseif policy == "treeEndPlus" then
            return sim.lastTreeEnd ~= nil and sim.t - sim.lastTreeEnd >= (cfg.stormArg or 0)
        elseif policy == "optimal" then
            -- Kristalle pro Laufminute: stürmen, sobald die stetige Rate zweimal hintereinander fällt.
            local earned = BigNum.toNumber(Sandstorm.runTotal(profile, o))
            local ratio = crystalsContinuous(earned) / math.max(sim.t - sim.runStart + walk, 1)
            if ratio < sim.bestRatio then
                sim.declines += 1
            else
                sim.declines = 0
                sim.bestRatio = ratio
            end
            return sim.declines >= 2
        end
        return false
    end

    local function goOffline(seconds: number)
        profile.lastSeen = unix()
        sim.real += seconds
        local report = Offline.apply(profile, unix())
        if report.ok and report.coins then
            local c = BigNum.toNumber(BigNum.deserialize(report.coins))
            sim.offlineCoins += c
            addEarned(c)
        end
        sim.sessionCollect = 0
    end

    -- Sitzungen (Gelegenheitsspieler)
    local sessionLeft = if cfg.sessions then cfg.sessions.active else math.huge
    local offlineGap = if cfg.sessions then (86400 - cfg.sessions.perDay * cfg.sessions.active) / cfg.sessions.perDay else 0
    if cfg.coinBoost == "first" or cfg.coinBoost == "session" then
        profile.boosts = Perks.extendCoinBoost(profile.boosts, unix(), Economy.coinBoost.durationSeconds)
        sim.boostsBought += 1
    end

    local maxRuns = cfg.maxRuns or math.huge
    -- Hauptschleife: ein Durchgang = Tank füllen, zum Stand, verkaufen, kaufen, Sturm?, zurück.
    while sim.t < cfg.activeSeconds and sim.run <= maxRuns do
        local tBefore = sim.t
        local earnedBefore = sim.earnedTotal
        fill()
        advance(walk)
        sell()
        sim.incomeRate = (sim.earnedTotal - earnedBefore) / math.max(sim.t - tBefore + walk, 1)
        buyAll()
        if cfg.offlineAtTreeEnd and treeComplete() and not sim.offlineDone then
            sim.offlineDone = true
            goOffline(cfg.offlineAtTreeEnd)
            sell()
        end
        if wantStorm() then
            doStorm()
            sim.offlineDone = false
        end
        if autoDig then
            -- Auto-Dig: der Rückweg ist Sammelzeit (obere Schranke)
            fill(walk)
        else
            advance(walk)
        end
        if cfg.sessions then
            sessionLeft -= sim.t - tBefore
            if sessionLeft <= 0 then
                goOffline(offlineGap)
                sessionLeft = cfg.sessions.active
                if cfg.coinBoost == "session" then
                    profile.boosts = Perks.extendCoinBoost(profile.boosts, unix(), Economy.coinBoost.durationSeconds)
                    sim.boostsBought += 1
                end
            end
        end
        if sim.t == tBefore then
            break -- Schutz gegen Endlosschleife
        end
    end
    sim.crystals = Wind.crystalsOf(profile)
    sim.finalProfile = profile
    return sim
end

---------------------------------------------------------------------------------------------------
-- Auswertung
---------------------------------------------------------------------------------------------------

local TOOL_NODES = {}
for _, tool in Tools.list do
    if tool.nodeId ~= "start" then
        table.insert(TOOL_NODES, tool)
    end
end

-- Fortschritts-Ereignisse (Kauf oder Sturm) und Lücken dazwischen.
local function gaps(sim: any): { { from: number, to: number, gap: number, before: string, after: string, run: number } }
    local result = {}
    local lastT, lastId = 0, "Start"
    for _, e in sim.events do
        if e.kind == "buy" or e.kind == "storm" then
            local label = if e.kind == "storm" then "Sturm " .. e.id else e.id
            table.insert(result, { from = lastT, to = e.t, gap = e.t - lastT, before = lastId, after = label, run = e.run })
            lastT, lastId = e.t, label
        end
    end
    -- offene Lücke bis zum Ende
    if sim.t - lastT > 0 then
        table.insert(result, { from = lastT, to = sim.t, gap = sim.t - lastT, before = lastId, after = "(Ende der Simulation)", run = sim.run })
    end
    return result
end

local function bottlenecks(sim: any): { any }
    local found = {}
    for _, g in gaps(sim) do
        local limit = if g.from < EARLY_SECONDS then GAP_EARLY else GAP_LATE
        if g.gap > limit then
            table.insert(found, g)
        end
    end
    return found
end

local function longestGap(sim: any, fromT: number, toT: number): any
    local best = nil
    for _, g in gaps(sim) do
        if g.from >= fromT and g.from < toT and g.after ~= "(Ende der Simulation)" then
            if best == nil or g.gap > best.gap then
                best = g
            end
        end
    end
    return best
end

local function zoneTime(sim: any, zoneId: string, run: number?): number?
    for _, e in sim.events do
        if e.kind == "zone" and e.id == zoneId and (run == nil or e.run == run) then
            return e.t
        end
    end
    return nil
end

local function stormTimes(sim: any): { number }
    local out = {}
    for _, r in sim.runs do
        table.insert(out, r.at)
    end
    return out
end

local function reportMilestones(sim: any)
    title(`Meilensteine Lauf 1: {sim.cfg.name}`)
    header({ "Meilenstein", "Zeit (aktiv)" })
    row({ "Erstes Upgrade (`collect_rate_1`)", fmtTime(sim.firstBuy.collect_rate_1) })
    for _, tool in TOOL_NODES do
        row({ `Werkzeug {tool.name} (`.. "`" .. tool.nodeId .. "`)", fmtTime(sim.firstBuy[tool.nodeId]) })
    end
    for _, zone in Zones.list do
        if zone.requires ~= "start" then
            row({ `Zone {zone.name}`, fmtTime(zoneTime(sim, zone.id)) })
        end
    end
    for _, branch in BRANCHES do
        row({ `Ast {branch} fertig`, fmtTime(sim.branchDone[branch]) })
    end
    local r1 = sim.runs[1]
    row({ "Baum fertig (Lauf 1)", fmtTime(r1 and r1.treeEnd) })
    row({ "Erster Sandsturm", if r1 then `{fmtTime(r1.at)} ({r1.crystals} Kristalle)` else "-" })
    local storms = stormTimes(sim)
    for i = 2, math.min(#storms, 5) do
        row({ `Sturm {i}`, `{fmtTime(storms[i])} ({sim.runs[i].crystals} Kristalle, Summe {sim.runs[i].total})` })
    end
    if #storms > 5 then
        row({ `Sturm {#storms} (letzter)`, `{fmtTime(storms[#storms])} (Summe {sim.runs[#storms].total})` })
    end
    -- Sets
    local setList = {}
    for setId, info in sim.sets do
        table.insert(setList, { id = setId, t = info.t, run = info.run })
    end
    table.sort(setList, function(a, b)
        return a.t < b.t
    end)
    for i = 1, math.min(#setList, 4) do
        row({ `{i}. fertiges Set ({setList[i].id})`, `{fmtTime(setList[i].t)} (Lauf {setList[i].run})` })
    end
    row({ "Fertige Sets am Ende", tostring(#setList) })
    for _, rarity in Rarities.list do
        if rarity.rank >= 3 then
            local first = sim.rarityFirst[rarity.id]
            row({ `Erster Fund {rarity.name}`, fmtTime(first and first.t) })
        end
    end
end

local function reportGaps(sim: any)
    title(`Längste Pausen und Engpässe: {sim.cfg.name}`)
    header({ "Abschnitt", "Längste Pause", "zwischen", "Lauf" })
    local windows = { { 0, 1800, "0 bis 30 min" }, { 1800, 3600, "30 bis 60 min" }, { 3600, 7200, "1 bis 2 h" }, { 7200, 4 * 3600, "2 bis 4 h" }, { 4 * 3600, math.huge, "ab 4 h" } }
    for _, w in windows do
        local g = longestGap(sim, w[1], w[2])
        if g then
            row({ w[3], fmtTime(g.gap), "`" .. g.before .. "` bis `" .. g.after .. "`", g.run })
        end
    end
    local found = bottlenecks(sim)
    print("")
    if #found == 0 then
        print(`Engpässe (über 10 min in den ersten 2 h, über 30 min danach): keine.`)
    else
        print(`Engpässe (über 10 min in den ersten 2 h, über 30 min danach): {#found}`)
        for _, g in found do
            print(`- {fmtTime(g.from)}: {fmtTime(g.gap)} zwischen {g.before} und {g.after} (Lauf {g.run})`)
        end
    end
end

-- Käufe je Werkzeugphase in einem Lauf: Anzahl, mittlere und längste Pause.
local function reportPhaseGaps(sim: any, run: number)
    title(`Zeit zwischen Käufen je Werkzeug und Zone, Lauf {run}: {sim.cfg.name}`)
    header({ "Werkzeug (Zone)", "Käufe", "Mittlere Pause", "Längste Pause", "vor" })
    local lastT = nil
    local stats: { [string]: any } = {}
    local order = {}
    for _, e in sim.events do
        if e.run == run and (e.kind == "buy" or e.kind == "storm") then
            local key = e.tool
            if lastT == nil then
                lastT = if run == 1 then 0 else e.t
            end
            local gap = e.t - lastT
            local st = stats[key]
            if st == nil then
                st = { n = 0, sum = 0, max = 0, maxId = "" }
                stats[key] = st
                table.insert(order, key)
            end
            st.n += 1
            st.sum += gap
            if gap > st.max then
                st.max, st.maxId = gap, e.id
            end
            lastT = e.t
        end
    end
    local zoneOfTool = { hand = "Dünenmeer", shovel = "Dünenmeer", bucket_chain = "Oase", mini_digger = "Canyon", vacuum_robot = "Salzsee", mega_machine = "Salzsee/Ruinen" }
    for _, key in order do
        local st = stats[key]
        row({ `{Tools.byId[key].name} ({zoneOfTool[key] or "?"})`, st.n, fmtTime(st.sum / st.n), fmtTime(st.max), "`" .. st.maxId .. "`" })
    end
end

local function reportRuns(sim: any, limit: number?)
    title(`Läufe: {sim.cfg.name}`)
    header({ "Lauf", "Dauer", "davon bis Baumende", "Einnahmen", "Kristalle", "Summe", "Bonus Kristalle", "Sammlung", "Ende bei" })
    local n = #sim.runs
    for i, r in sim.runs do
        if limit == nil or i <= limit or i == n or i % 10 == 0 then
            row({
                r.run,
                fmtTime(r.duration),
                fmtTime(r.treeEnd),
                fmtNum(r.earned),
                r.crystals,
                r.total,
                fmtPct(r.total * Economy.windCrystalBonusBp / 10000),
                fmtPct(r.setBonusBp / 10000),
                fmtTime(r.at),
            })
        end
    end
end

local PHASE_ORDER = { "1", "2", "3", "4-10", "11+" }
local function reportPhases(sim: any)
    title(`Verdienst pro Minute je Phase: {sim.cfg.name}`)
    header({ "Lauf", "Werkzeug", "Spielzeit", "Münzen/min" })
    for _, run in PHASE_ORDER do
        for _, tool in Tools.list do
            local p = sim.phase[run .. ":" .. tool.id]
            if p and p.seconds > 0 then
                row({ run, tool.name, fmtTime(p.seconds), fmtNum(p.earned / p.seconds * 60) })
            end
        end
    end
end

local function summaryLine(sim: any): { any }
    local r1 = sim.runs[1]
    local b = bottlenecks(sim)
    return {
        sim.cfg.name,
        fmtTime(sim.firstBuy.collect_rate_1),
        fmtTime(sim.firstBuy.collect_tool_2),
        fmtTime(sim.firstBuy.collect_tool_3),
        fmtTime(sim.firstBuy.collect_tool_4),
        fmtTime(sim.firstBuy.collect_tool_5),
        fmtTime(sim.firstBuy.collect_tool_6),
        fmtTime(r1 and r1.treeEnd),
        if r1 then `{fmtTime(r1.at)} ({r1.crystals})` else "-",
        #sim.runs,
        sim.crystals,
        #b,
    }
end

local SUMMARY_HEADER = { "Szenario", "Upgrade 1", "Schaufel", "Eimerkette", "Mini-Bagger", "Saugroboter", "Großmaschine", "Baum fertig", "Sturm 1 (Kristalle)", "Stürme", "Kristalle am Ende", "Engpässe" }

---------------------------------------------------------------------------------------------------
-- Teile
---------------------------------------------------------------------------------------------------

local HOURS = 3600
local BASE_HOURS = 8

local function partBase()
    print("## Basis: aktiver Spieler ohne Pässe, Sturm-Strategie stall (heute gleich Baumende), " .. BASE_HOURS .. " h")
    local sim = simulate({ name = "Basis", activeSeconds = BASE_HOURS * HOURS })
    reportMilestones(sim)
    reportPhases(sim)
    reportPhaseGaps(sim, 1)
    reportPhaseGaps(sim, 2)
    reportRuns(sim, 12)
    reportGaps(sim)
    -- Kaufprotokoll Lauf 1
    title("Kaufprotokoll Lauf 1 (Basis)")
    local line = {}
    for _, e in sim.events do
        if e.run == 1 and (e.kind == "buy" or e.kind == "storm" or e.kind == "zone") then
            table.insert(line, `{e.kind == "zone" and "Zone " or ""}{e.id} {fmtTime(e.t)}`)
        end
    end
    print(table.concat(line, ", "))
    return sim
end

local function partPasses()
    print("")
    print("## Pässe und Münz-Boost (je " .. BASE_HOURS .. " h aktiv, Sturm-Strategie stall (heute gleich Baumende))")
    local variants: { Config } = {
        { name = "Basis", activeSeconds = BASE_HOURS * HOURS },
        { name = "2x Münzen", passes = { "double_coins" }, activeSeconds = BASE_HOURS * HOURS },
        { name = "Münz-Boost dauerhaft", coinBoost = "always", activeSeconds = BASE_HOURS * HOURS },
        { name = "Münz-Boost einmal (30 min)", coinBoost = "first", activeSeconds = BASE_HOURS * HOURS },
        { name = "2x Münzen + Boost dauerhaft", passes = { "double_coins" }, coinBoost = "always", activeSeconds = BASE_HOURS * HOURS },
        { name = "Auto-Dig (obere Schranke)", passes = { "auto_dig" }, activeSeconds = BASE_HOURS * HOURS },
        { name = "Großer Tank", passes = { "big_tank" }, activeSeconds = BASE_HOURS * HOURS },
        { name = "Alle Pässe + Boost dauerhaft", passes = { "double_coins", "auto_dig", "big_tank" }, coinBoost = "always", activeSeconds = BASE_HOURS * HOURS },
    }
    local sims = {}
    title("Meilensteine Lauf 1 und Ergebnis nach " .. BASE_HOURS .. " h")
    header(SUMMARY_HEADER)
    for _, v in variants do
        local sim = simulate(v)
        table.insert(sims, sim)
        row(summaryLine(sim))
    end
    title("Kristalle über die Zeit (Summe nach 1 h, 2 h, 4 h, 8 h aktiv)")
    header({ "Szenario", "1 h", "2 h", "4 h", "8 h", "Faktor 8 h ggü. Basis", "Münz-Boosts gekauft", "Robux für Boosts" })
    local baseAt8 = nil
    for _, sim in sims do
        local function at(hours: number): number
            local total = 0
            for _, r in sim.runs do
                if r.at <= hours * HOURS then
                    total = r.total
                end
            end
            return total
        end
        baseAt8 = baseAt8 or at(8)
        local boostPrice = Products.byId and Products.byId.coin_boost and Products.byId.coin_boost.priceRobux or 49
        row({ sim.cfg.name, at(1), at(2), at(4), at(8), string.format("x%.2f", at(8) / math.max(baseAt8, 1)), sim.boostsBought, sim.boostsBought * boostPrice })
    end
    -- Erste Läufe im Detail für 2x
    reportRuns(sims[2], 5)
    reportRuns(sims[5], 5)
    return sims
end

local function partCrystalsBuyable()
    print("")
    print("## Windkristalle über 2x-Pass und Münz-Boost (Hinweis aus Logic/Wind und Exploit-Review 2)")
    title("Gleiche aktive Spielzeit, Sturm-Strategie stall (heute gleich Baumende): Kristalle nach 2 h und 8 h")
    header({ "Szenario", "runEarned-Regel", "Kristalle 2 h", "Kristalle 8 h", "Stürme 8 h", "Kristalle je Sturm (Mittel)", "ggü. Basis 8 h" })
    local base8 = nil
    for _, v in {
        { name = "Basis", passes = {}, coinBoost = "none" },
        { name = "2x Münzen", passes = { "double_coins" }, coinBoost = "none" },
        { name = "Boost dauerhaft", passes = {}, coinBoost = "always" },
        { name = "2x + Boost", passes = { "double_coins" }, coinBoost = "always" },
    } do
        for _, without in { false, true } do
            if v.name == "Basis" and without then
                continue
            end
            local sim = simulate({
                name = v.name,
                passes = v.passes,
                coinBoost = v.coinBoost,
                activeSeconds = 8 * HOURS,
                runEarnedWithoutCoinFactor = without,
            })
            local c2 = 0
            for _, r in sim.runs do
                if r.at <= 2 * HOURS then
                    c2 = r.total
                end
            end
            base8 = base8 or sim.crystals
            row({
                v.name,
                if without then "ohne Münz-Faktor (Vorschlag)" else "heute (mit Münz-Faktor)",
                c2,
                sim.crystals,
                #sim.runs,
                string.format("%.1f", sim.crystals / math.max(#sim.runs, 1)),
                string.format("x%.2f", sim.crystals / math.max(base8, 1)),
            })
        end
    end

    title("Ein Sturm, gleicher Lauf: Kristalle für dieselben Einnahmen mit Münz-Faktor 1, 2, 4")
    header({ "Einnahmen ohne Faktor", "x1", "x2 (Pass oder Boost)", "x4 (Pass und Boost)" })
    for _, earned in { 625e6, 2.5e9, 1e10, 1e11 } do
        row({
            fmtNum(earned),
            Sandstorm.crystalsFor(BigNum.new(earned)),
            Sandstorm.crystalsFor(BigNum.new(earned * 2)),
            Sandstorm.crystalsFor(BigNum.new(earned * 4)),
        })
    end

    -- Tank füllen, dann Boost kaufen und verkaufen (Exploit-Review 1): Wert eines vollen Tanks
    title("Tank voll, dann Boost kaufen und verkaufen: Mehrertrag eines Tanks am Baumende von Lauf 1")
    local probe = simulate({ name = "Probe", activeSeconds = 6 * HOURS, maxRuns = 1, storm = "never" })
    local p = probe.finalProfile
    local cap = Collecting.capacityOf(p)
    local price = Collecting.priceOf(p, Collecting.sandTypeOf(p))
    local rate = Collecting.rateOf(p)
    header({ "Tank", "Wert ohne Boost", "mit Boost", "Sammelzeit für einen Tank", "Einnahmen je Minute (Baumende)" })
    row({ fmtNum(cap), fmtNum(cap * price), fmtNum(cap * price * 2), fmtTime(cap / rate), fmtNum(cap * price / (cap / rate + 2 * WALK) * 60) })
end

local function partStorm()
    print("")
    print("## Sturm-Strategien: viele kleine gegen wenige große Stürme (8 h aktiv, ohne Pässe)")
    local strategies = {
        { name = "Sofort bei minCrystals (20)", storm = "asap" },
        { name = "Ab 25 Kristallen", storm = "threshold", stormArg = 25 },
        { name = "Ab 30 Kristallen", storm = "threshold", stormArg = 30 },
        { name = "Baumende", storm = "treeEnd" },
        { name = "Baumende + 2 min", storm = "treeEndPlus", stormArg = 120 },
        { name = "Baumende + 5 min", storm = "treeEndPlus", stormArg = 300 },
        { name = "Baumende + 15 min", storm = "treeEndPlus", stormArg = 900 },
        { name = "Kristallraten-optimal", storm = "optimal" },
    }
    local function table8(exponentLabel: string)
        header({ "Strategie (" .. exponentLabel .. ")", "Lauf 1", "Kristalle Lauf 1", "Stürme", "Kristalle 2 h", "Kristalle 8 h", "Mittlere Laufdauer ab Lauf 5", "kürzester Lauf" })
        for _, s in strategies do
            local sim = simulate({ name = s.name, storm = s.storm, stormArg = s.stormArg, activeSeconds = 8 * HOURS })
            local c2 = 0
            for _, r in sim.runs do
                if r.at <= 2 * HOURS then
                    c2 = r.total
                end
            end
            local sum, n, shortest = 0, 0, math.huge
            for i, r in sim.runs do
                if i >= 5 then
                    sum += r.duration
                    n += 1
                end
                shortest = math.min(shortest, r.duration)
            end
            local r1 = sim.runs[1]
            row({ s.name, fmtTime(r1 and r1.duration), r1 and r1.crystals or "-", #sim.runs, c2, sim.crystals, fmtTime(if n > 0 then sum / n else nil), fmtTime(if shortest < math.huge then shortest else nil) })
        end
    end
    title("Heutige Formel: Exponent 0,25, Faktor 4, Einheit 1 Mio., minCrystals 20")
    table8("0,25")
    -- Varianten der Formel: Faktor so gewählt, dass das Baumende von Lauf 1 (etwa 2,1 Mrd.) gleich viele Kristalle gibt.
    for _, variant in { { exp = 0.5, scale = 0.6, min = 20 }, { exp = 0.4, scale = 1.25, min = 20 }, { exp = 0.15, scale = 8.5, min = 20 } } do
        title(`Variante: Exponent {variant.exp}, Faktor {variant.scale}, minCrystals {variant.min}`)
        withPatch({
            { Economy.sandstorm, "crystalExponent", variant.exp },
            { Economy.sandstorm, "crystalScale", variant.scale },
            { Economy.sandstorm, "minCrystals", variant.min },
        }, function()
            table8(tostring(variant.exp))
            return nil
        end)
    end
end

local function partCasual()
    print("")
    print("## Gelegenheitsspieler: 2 Sitzungen zu 10 min am Tag, Begleiter für den Offline-Ertrag, 14 Tage")
    local variants: { Config } = {
        { name = "Ohne Begleiter", sessions = { active = 600, perDay = 2, companion = false }, activeSeconds = 14 * 1200 },
        { name = "Mit Begleiter (4 h offline)", sessions = { active = 600, perDay = 2, companion = true }, activeSeconds = 14 * 1200 },
        { name = "Mit Begleiter + Auto-Dig (12 h offline)", passes = { "auto_dig" }, sessions = { active = 600, perDay = 2, companion = true }, activeSeconds = 14 * 1200 },
        { name = "Mit Begleiter + 2x Münzen", passes = { "double_coins" }, sessions = { active = 600, perDay = 2, companion = true }, activeSeconds = 14 * 1200 },
    }
    title("Echte Tage bis zum Meilenstein")
    header({ "Szenario", "Eimerkette", "Mini-Bagger", "Großmaschine", "Sturm 1 (Kristalle)", "Sturm 2", "Stürme in 14 d", "Kristalle 14 d", "Lauf 10 Dauer", "Offline-Anteil der Einnahmen", "Fertige Sets" })
    for _, v in variants do
        local sim = simulate(v)
        local function realOf(nodeId: string): string
            for _, e in sim.events do
                if e.kind == "buy" and e.id == nodeId and e.run == 1 then
                    return fmtDays(e.real) .. " / " .. fmtTime(e.t)
                end
            end
            return "-"
        end
        local r1, r2 = sim.runs[1], sim.runs[2]
        local sets = 0
        for _ in sim.sets do
            sets += 1
        end
        row({
            v.name,
            realOf("collect_tool_3"),
            realOf("collect_tool_4"),
            realOf("collect_tool_6"),
            if r1 then `{fmtDays(r1.atReal)} / {fmtTime(r1.at)} ({r1.crystals})` else "-",
            if r2 then `{fmtDays(r2.atReal)} ({r2.crystals})` else "-",
            #sim.runs,
            sim.crystals,
            if sim.runs[10] then fmtTime(sim.runs[10].duration) else "-",
            string.format("%.0f %%", sim.offlineCoins / math.max(sim.earnedTotal, 1) * 100),
            sets,
        })
    end
    print("")
    print("Zeitangabe: echte Tage / aktive Spielzeit.")

    title("Offline am Baumende vor dem Sturm (aktiver Spieler, Begleiter, 8 h aktiv)")
    header({ "Variante", "Kristalle Sturm 1", "Kristalle Sturm 2", "Kristalle nach 5 Stürmen" })
    for _, v in { { "Sofort stürmen", nil, false }, { "4 h offline, dann stürmen", 4 * 3600, false }, { "12 h offline (Auto-Dig), dann stürmen", 12 * 3600, true } } do
        local sim = simulate({
            name = v[1],
            activeSeconds = 8 * HOURS,
            maxRuns = 5,
            offlineAtTreeEnd = v[2],
            passes = if v[3] then { "auto_dig" } else nil,
            companion = true,
        })
        row({ v[1], sim.runs[1] and sim.runs[1].crystals or "-", sim.runs[2] and sim.runs[2].crystals or "-", sim.runs[5] and sim.runs[5].total or sim.crystals })
    end

    title("Offline-Faktor (Economy.offline.rateFactor): Gelegenheitsspieler mit Begleiter, 14 Tage, und 4 h offline am Baumende")
    header({ "rateFactor", "Offline-Anteil der Einnahmen (14 d)", "Stürme 14 d", "Kristalle 14 d", "Sturm 1 mit 4 h offline am Baumende", "ohne Offline" })
    for _, factor in { 0.5, 0.25, 0.1 } do
        withPatch({ { Economy.offline, "rateFactor", factor } }, function()
            local casual = simulate({ name = "c", sessions = { active = 600, perDay = 2, companion = true }, activeSeconds = 14 * 1200 })
            local idle = simulate({ name = "i", activeSeconds = 8 * HOURS, maxRuns = 1, offlineAtTreeEnd = 4 * 3600, companion = true })
            local plain = simulate({ name = "p", activeSeconds = 8 * HOURS, maxRuns = 1, companion = true })
            row({
                tostring(factor),
                string.format("%.0f %%", casual.offlineCoins / math.max(casual.earnedTotal, 1) * 100),
                #casual.runs,
                casual.crystals,
                idle.runs[1] and idle.runs[1].crystals or "-",
                plain.runs[1] and plain.runs[1].crystals or "-",
            })
            return nil
        end)
    end
end

local function partCrates()
    print("")
    print("## Kisten: erwartete Kosten bis Legendär oder besser (Goldkiste, mit Pity)")
    local crate = Crates.byId.gold
    -- Exakte Verteilung über die Zählerstände mit CrateRoll.effectiveOdds und CrateRoll.advance.
    local dist: { [string]: number } = { ["0:0"] = 1 }
    local expected, cumulative = 0, 0
    local legendaryRank = Rarities.byId.legendary.rank
    local p50, p90 = nil, nil
    for opening = 1, 200 do
        local nextDist: { [string]: number } = {}
        local hit = 0
        local mass = 0
        for key, prob in dist do
            mass += prob
            local e, l = string.match(key, "(%d+):(%d+)")
            local counters = { sinceEpic = tonumber(e), sinceLegendary = tonumber(l) }
            local eff = CrateRoll.effectiveOdds(crate, counters)
            for _, rarity in Rarities.list do
                local w = eff.odds[rarity.id] or 0
                if w > 0 and rarity.rank >= 1 then
                    local share = prob * w / eff.total
                    if rarity.rank >= legendaryRank then
                        hit += share
                    else
                        local adv = CrateRoll.advance(crate, counters, rarity.id)
                        local k = `{adv.sinceEpic}:{adv.sinceLegendary}`
                        nextDist[k] = (nextDist[k] or 0) + share
                    end
                end
            end
        end
        expected += mass -- P(noch kein Treffer vor dieser Öffnung)
        cumulative += hit
        if p50 == nil and cumulative >= 0.5 then
            p50 = opening
        end
        if p90 == nil and cumulative >= 0.9 then
            p90 = opening
        end
        dist = nextDist
        local left = 0
        for _, v in dist do
            left += v
        end
        if left < 1e-12 then
            break
        end
    end
    local gems = expected * crate.price
    local best, smallest = math.huge, 0
    for _, pack in GemPacks.list do
        best = math.min(best, pack.robux / pack.gems)
        if pack.gems == 100 then
            smallest = pack.robux / pack.gems
        end
    end
    header({ "Kiste", "Erwartete Öffnungen", "Median", "P90", "Garantie spätestens", "Gems", "Robux (größtes Paket)", "Robux (kleinstes Paket)" })
    row({ crate.name, string.format("%.2f", expected), p50 or "-", p90 or "-", crate.pity and crate.pity.legendary or "-", fmtNum(gems), string.format("%.0f", gems * best), string.format("%.0f", gems * smallest) })
    local packGems = expected * crate.price * 10 / 11
    row({ crate.name .. " (nur 10er-Pakete, 11 für 10)", string.format("%.2f", expected), p50 or "-", p90 or "-", crate.pity and crate.pity.legendary or "-", fmtNum(packGems), string.format("%.0f", packGems * best), string.format("%.0f", packGems * smallest) })
    -- Holzkiste: erste Begleiter-Chance (für den Offline-Ertrag)
    local wood = Crates.byId.wood
    local companionShare = 0
    for _, rarity in Rarities.list do
        local w = wood.odds[rarity.id] or 0
        if w > 0 then
            local total, comps = 0, 0
            for _, item in CrateItems.list do
                if item.rarity == rarity.id and table.find(item.crates, "wood") then
                    total += 1
                    if item.kind == "companion" then
                        comps += 1
                    end
                end
            end
            if total > 0 then
                companionShare += w / 10000 * comps / total
            end
        end
    end
    print("")
    print(string.format("Holzkiste (%s Münzen): Chance auf einen Begleiter je Öffnung %.1f %%, im Mittel %.1f Öffnungen = %s Münzen bis zum ersten Begleiter.", fmtNum(wood.price), companionShare * 100, 1 / companionShare, fmtNum(wood.price / companionShare)))
end

-- Vorschläge (nur im Speicher)
local PROPOSALS = {}

-- V1: Werkzeugpreise anheben (Entscheidung 18.11.2026: keine Tore, 6.4 hebt die Preise an).
PROPOSALS.tools = {
    label = "V1 Werkzeugpreise",
    patch = function(): any
        return {
            nodeCost("collect_tool_4", 7_500),
            nodeCost("collect_tool_5", 700_000),
            nodeCost("collect_tool_6", 30_000_000),
        }
    end,
}

-- V2: Ruinen-Ast hinter der Ruinenkarte (neue Knoten mit vorhandenen Wirkungen, nur Daten).
local function ruinsNodes(): { any }
    local nodes = {}
    local specs = {
        { "ruins_sell_1", "sell", "sellBonus", 10000, 1e9, { "sandstorm_ruins" } },
        { "ruins_rate_1", "collect", "rateBonus", 20000, 3e9, { "sandstorm_ruins" } },
        { "ruins_tank_1", "tank", "setTank", 4_000_000, 6e9, { "sandstorm_ruins" } },
        { "ruins_sell_2", "sell", "sellBonus", 15000, 15e9, { "ruins_sell_1" } },
        { "ruins_rate_2", "collect", "rateBonus", 30000, 40e9, { "ruins_rate_1" } },
        { "ruins_tank_2", "tank", "setTank", 10_000_000, 100e9, { "ruins_tank_1" } },
        { "ruins_sell_3", "sell", "sellBonus", 20000, 250e9, { "ruins_sell_2" } },
        { "ruins_rate_3", "collect", "rateBonus", 40000, 600e9, { "ruins_rate_2" } },
        { "ruins_tank_3", "tank", "setTank", 25_000_000, 1.5e12, { "ruins_tank_2" } },
        { "ruins_sell_4", "sell", "sellBonus", 30000, 4e12, { "ruins_sell_3" } },
        { "ruins_rate_4", "collect", "rateBonus", 50000, 10e12, { "ruins_rate_3" } },
    }
    for _, s in specs do
        local effect: any = { kind = s[3] }
        if s[3] == "setTank" then
            effect.capacity = s[4]
        else
            effect.bp = s[4]
        end
        table.insert(nodes, { id = s[1], name = s[1], description = "", branch = s[2], requires = s[6], cost = s[5], effect = effect })
    end
    return nodes
end
-- Längerer Ruinen-Ast: `count` Knoten im Wechsel Verkauf, Rate, Tank, Preise geometrisch ab `startCost`
-- mit Faktor `ratio`. Verkauf +100 %, Rate +200 %, Tank x2,5 je Stufe (Startwert 4M).
local function ruinsChain(count: number, startCost: number, ratio: number): { any }
    local nodes = {}
    local last: { [string]: string } = { sell = "sandstorm_ruins", collect = "sandstorm_ruins", tank = "sandstorm_ruins" }
    local kinds = { { "sell", "sellBonus" }, { "collect", "rateBonus" }, { "tank", "setTank" } }
    local cost = startCost
    local tank = 4_000_000
    for i = 1, count do
        local k = kinds[(i - 1) % 3 + 1]
        local id = `ruins_{k[1]}_{(i - 1) // 3 + 1}`
        local effect: any = { kind = k[2] }
        if k[2] == "setTank" then
            effect.capacity = tank
            tank = math.floor(tank * 2.5)
        elseif k[2] == "sellBonus" then
            effect.bp = 10000
        else
            effect.bp = 20000
        end
        -- runde Preise (2 gültige Stellen)
        local digits = math.floor(math.log10(cost))
        local rounded = math.floor(cost / 10 ^ (digits - 1) + 0.5) * 10 ^ (digits - 1)
        local description = if k[2] == "setTank" then `Tank {fmtNum(effect.capacity)}` elseif k[2] == "sellBonus" then "+100 % Münzen pro Sand" else "+200 % Sand pro Sekunde"
        table.insert(nodes, { id = id, name = `Ruinen {i}`, description = description, branch = k[1], requires = { last[k[1]] }, cost = rounded, effect = effect })
        last[k[1]] = id
        cost *= ratio
    end
    return nodes
end

PROPOSALS.ruins = {
    label = "V2 Ruinen-Ast",
    patch = function(): any
        return { addNodes = ruinsNodes() }
    end,
}
PROPOSALS.both = {
    label = "V1 + V2",
    patch = function(): any
        local p = PROPOSALS.tools.patch()
        p.addNodes = ruinsNodes()
        return p
    end,
}

local function partProposals()
    print("")
    print("## Vorschläge im Vergleich (nur im Speicher, 8 h aktiv)")
    local list = {
        { "Heute", nil },
        { PROPOSALS.tools.label, PROPOSALS.tools },
        { PROPOSALS.ruins.label, PROPOSALS.ruins },
        { PROPOSALS.both.label, PROPOSALS.both },
    }
    title("Meilensteine Lauf 1 und Ergebnis nach 8 h")
    header(SUMMARY_HEADER)
    local sims = {}
    for _, entry in list do
        for _, extra in { { "", {} }, { ", 2x Münzen", { "double_coins" } } } do
            local cfg: Config = { name = entry[1] .. extra[1], passes = extra[2], activeSeconds = 8 * HOURS }
            local sim = if entry[2] then withPatch(entry[2].patch(), function()
                return simulate(cfg)
            end) else simulate(cfg)
            sims[cfg.name] = sim
            row(summaryLine(sim))
        end
    end
    for _, name in { "Heute", "V1 Werkzeugpreise", "V1 + V2" } do
        reportRuns(sims[name], 10)
        local sim = sims[name]
        title(`Längste Pause Lauf 1 und Phasen ({name})`)
        header({ "Werkzeug", "Zeit seit dem vorigen Werkzeug (Lauf 1)" })
        local prev = 0
        for _, tool in TOOL_NODES do
            local at = sim.firstBuy[tool.nodeId]
            row({ tool.name, if at then fmtTime(at - prev) else "-" })
            prev = at or prev
        end
        reportGaps(sim)
    end
end

-- Kennzahlen einer Simulation in einer Zeile (für Suchläufe).
local COMPACT_HEADER = { "Variante", "Eimerk.", "Bagger", "Saugr.", "Großm.", "Lauf 1", "Lauf 5", "Lauf 10", "Lauf 20", "erster Lauf < 5 min bei", "Stürme", "Kristalle 2 h", "Kristalle 8 h", "längste Pause", "Engpässe" }
local function compactLine(label: string, sim: any): { any }
    local function dur(i: number): string
        local r = sim.runs[i]
        return if r then fmtTime(r.duration) else "-"
    end
    local below = nil
    for _, r in sim.runs do
        if r.duration < 300 then
            below = r.at - r.duration
            break
        end
    end
    local c2 = 0
    for _, r in sim.runs do
        if r.at <= 2 * 3600 then
            c2 = r.total
        end
    end
    local longest = longestGap(sim, 0, math.huge)
    return {
        label,
        fmtTime(sim.firstBuy.collect_tool_3),
        fmtTime(sim.firstBuy.collect_tool_4),
        fmtTime(sim.firstBuy.collect_tool_5),
        fmtTime(sim.firstBuy.collect_tool_6),
        dur(1),
        dur(5),
        dur(10),
        dur(20),
        fmtTime(below),
        #sim.runs,
        c2,
        sim.crystals,
        if longest then `{fmtTime(longest.gap)} (L{longest.run} vor {longest.after})` else "-",
        #bottlenecks(sim),
    }
end

local function toolPatch(t5: number, t6: number): any
    return {
        nodeCost("collect_tool_5", t5),
        nodeCost("collect_tool_6", t6),
        { Tools.byId.vacuum_robot, "cost", t5 },
        { Tools.byId.mega_machine, "cost", t6 },
    }
end

local function merge(...: any): any
    local out: any = {}
    for _, p in { ... } do
        for _, e in p do
            table.insert(out, e)
        end
        if p.addNodes then
            out.addNodes = out.addNodes or {}
            for _, n in p.addNodes do
                table.insert(out.addNodes, n)
            end
        end
    end
    return out
end

local function partExplore()
    print("")
    print("## Suchläufe (nur im Speicher, 8 h aktiv, Sturm-Strategie \"stall\": nichts mehr zu kaufen oder nächster Knoten über 3 min entfernt)")
    title("Werkzeugpreise Saugroboter / Großmaschine")
    header(COMPACT_HEADER)
    for _, pair in { { 90_000, 1_100_000 }, { 300_000, 5_000_000 }, { 500_000, 15_000_000 }, { 700_000, 30_000_000 }, { 1_000_000, 50_000_000 } } do
        local sim = withPatch(toolPatch(pair[1], pair[2]), function()
            return simulate({ name = "x", storm = "stall", activeSeconds = 8 * HOURS })
        end)
        row(compactLine(`{fmtNum(pair[1])} / {fmtNum(pair[2])}`, sim))
    end
    title("Bonus je Kristall (windCrystalBonusBp), heutiger Baum")
    header(COMPACT_HEADER)
    for _, bp in { 200, 100, 50 } do
        local sim = withPatch({ { Economy, "windCrystalBonusBp", bp } }, function()
            return simulate({ name = "x", storm = "stall", activeSeconds = 8 * HOURS })
        end)
        row(compactLine(`{bp} bp`, sim))
    end
    title("Ruinen-Ast (V2), kombiniert mit Werkzeugpreisen und Bonus je Kristall")
    header(COMPACT_HEADER)
    for _, v in {
        { "V2", { addNodes = ruinsNodes() } },
        { "V1 + V2", merge(toolPatch(700_000, 30_000_000), { addNodes = ruinsNodes() }) },
        { "V1 + V2 + 100 bp", merge(toolPatch(700_000, 30_000_000), { addNodes = ruinsNodes() }, { { Economy, "windCrystalBonusBp", 100 } }) },
        { "V1 + 100 bp", merge(toolPatch(700_000, 30_000_000), { { Economy, "windCrystalBonusBp", 100 } }) },
    } do
        local sim = withPatch(v[2], function()
            return simulate({ name = "x", storm = "stall", activeSeconds = 8 * HOURS })
        end)
        row(compactLine(v[1], sim))
    end
end

-- Langzeit-Suchlauf: wann fallen Läufe unter 5 min, wann blockiert maxCrystals den Sturm?
local LONG_HEADER = { "Variante", "Lauf 1", "Lauf 10", "Lauf 30", "Lauf 100", "erster Lauf < 5 min bei", "Kristalle 2 h", "8 h", "20 h", "40 h", "Sturm blockiert ab", "Stürme 40 h", "längste Pause", "Engpässe" }
local function longLine(label: string, sim: any): { any }
    local function dur(i: number): string
        local r = sim.runs[i]
        return if r then fmtTime(r.duration) else "-"
    end
    local function at(h: number): number
        local total = 0
        for _, r in sim.runs do
            if r.at <= h * 3600 then
                total = r.total
            end
        end
        return total
    end
    local below, blocked = nil, nil
    for _, r in sim.runs do
        if below == nil and r.duration < 300 and r.run > 1 then
            below = r.at - r.duration
        end
        if blocked == nil and r.total > Economy.sandstorm.maxCrystals - Economy.sandstorm.minCrystals then
            blocked = r.at
        end
    end
    local longest = longestGap(sim, 0, math.huge)
    return {
        label,
        dur(1),
        dur(10),
        dur(30),
        dur(100),
        fmtTime(below),
        at(2),
        at(8),
        at(20),
        at(40),
        fmtTime(blocked),
        #sim.runs,
        if longest then `{fmtTime(longest.gap)} (L{longest.run})` else "-",
        #bottlenecks(sim),
    }
end

local function partExploreLong()
    print("")
    print("## Langzeit-Suchlauf (nur im Speicher, 40 h aktiv, Sturm-Strategie \"stall\")")
    title("Ruinen-Ast-Länge, Bonus je Kristall und maxCrystals")
    header(LONG_HEADER)
    local v1 = function()
        return toolPatch(700_000, 30_000_000)
    end
    for _, v in {
        { "Heute", function()
            return {}
        end },
        { "V1", v1 },
        { "V1 + V2 (11 Knoten bis 10 Bio.)", function()
            return merge(v1(), { addNodes = ruinsNodes() })
        end },
        { "V1 + Ruinen-Ast 18 Knoten (x2,7, bis 22 Brd.)", function()
            return merge(v1(), { addNodes = ruinsChain(18, 1e9, 2.7) })
        end },
        { "V1 + 18 Knoten + 100 bp", function()
            return merge(v1(), { addNodes = ruinsChain(18, 1e9, 2.7) }, { { Economy, "windCrystalBonusBp", 100 } })
        end },
        { "V1 + 18 Knoten + 100 bp + maxCrystals 10 Mio.", function()
            return merge(v1(), { addNodes = ruinsChain(18, 1e9, 2.7) }, { { Economy, "windCrystalBonusBp", 100 }, { Economy.sandstorm, "maxCrystals", 10_000_000 } })
        end },
        { "Heute + maxCrystals 5 Mio.", function()
            return { { Economy.sandstorm, "maxCrystals", 5_000_000 } }
        end },
    } do
        withPatch(v[2](), function()
            row(longLine(v[1], simulate({ name = "x", storm = "stall", activeSeconds = 40 * HOURS })))
            return nil
        end)
    end
end

local function partLong()
    print("")
    print("## Langzeit: 80 h aktiv, heutige Werte, Sturm-Strategie stall (heute gleich Baumende)")
    local sim = simulate({ name = "Langzeit", activeSeconds = 80 * HOURS })
    local capAt, blockedAt = nil, nil
    for _, r in sim.runs do
        if capAt == nil and r.total > Economy.sandstorm.maxCrystals - Economy.sandstorm.minCrystals then
            capAt = r.at
        end
    end
    local last = sim.runs[#sim.runs]
    header({ "Kennzahl", "Wert" })
    row({ "Stürme", #sim.runs })
    row({ "Kristalle am Ende", sim.crystals })
    row({ "Obergrenze maxCrystals", Economy.sandstorm.maxCrystals })
    row({ "Kein Sturm mehr möglich ab (gehaltene Kristalle über maxCrystals - minCrystals)", fmtTime(capAt) })
    row({ "Letzter Sturm bei", fmtTime(last and last.at) })
    row({ "Aktive Zeit ohne Sturm am Ende", fmtTime(sim.t - (last and last.at or 0)) })
    for _, h in { 10, 20, 40, 60 } do
        local total = 0
        for _, r in sim.runs do
            if r.at <= h * HOURS then
                total = r.total
            end
        end
        row({ `Kristalle nach {h} h`, total })
    end
    reportGaps(sim)
end

-- Empfohlenes Paket (nur im Speicher): V1 Werkzeugpreise, V2 Ruinen-Ast (18 Knoten), maxCrystals 5 Mio.
local function recommendedPatch(bonusBp: number?): any
    local p = merge(toolPatch(700_000, 30_000_000), { addNodes = ruinsChain(18, 1e9, 2.7) }, { { Economy.sandstorm, "maxCrystals", 5_000_000 } })
    if bonusBp then
        table.insert(p, { Economy, "windCrystalBonusBp", bonusBp })
    end
    return p
end

local function partRecommended()
    print("")
    print("## Empfohlenes Paket (V1 + V2 mit 18 Ruinen-Knoten + maxCrystals 5 Mio.), nur im Speicher")
    title("Ruinen-Ast (Vorschlag V2): Knoten")
    header({ "ID", "Ast", "verlangt", "Preis", "Wirkung" })
    for _, node in ruinsChain(18, 1e9, 2.7) do
        local effect = if node.effect.kind == "setTank" then `setTank {fmtNum(node.effect.capacity)}` else `{node.effect.kind} {node.effect.bp}`
        row({ "`" .. node.id .. "`", node.branch, "`" .. node.requires[1] .. "`", fmtNum(node.cost), effect })
    end
    withPatch(recommendedPatch(), function()
        -- Prüfung: bestehen die vorgeschlagenen Tabellen DataCheck (dieselbe Prüfung wie tests/data.spec)?
        local errors = DataCheck.run()
        print("")
        if #errors == 0 then
            print("DataCheck mit dem Paket im Speicher: keine Fehler.")
        else
            print(`DataCheck mit dem Paket im Speicher: {#errors} Fehler`)
            for _, e in errors do
                print("- " .. e)
            end
        end
        local sim = simulate({ name = "Empfehlung", activeSeconds = 8 * HOURS })
        reportMilestones(sim)
        reportPhaseGaps(sim, 1)
        reportPhaseGaps(sim, 2)
        reportPhases(sim)
        reportRuns(sim, 12)
        reportGaps(sim)
        title("Empfehlung mit Pässen und Boost (8 h aktiv)")
        header(SUMMARY_HEADER)
        for _, v in {
            { name = "Empfehlung", activeSeconds = 8 * HOURS },
            { name = "Empfehlung, 2x Münzen", passes = { "double_coins" }, activeSeconds = 8 * HOURS },
            { name = "Empfehlung, Boost dauerhaft", coinBoost = "always", activeSeconds = 8 * HOURS },
            { name = "Empfehlung, Auto-Dig", passes = { "auto_dig" }, activeSeconds = 8 * HOURS },
            { name = "Empfehlung, Weg 8 s", walk = 8, activeSeconds = 8 * HOURS },
        } do
            row(summaryLine(simulate(v :: any)))
        end
        title("Empfehlung: Gelegenheitsspieler (2 x 10 min am Tag, Begleiter, 14 Tage)")
        header({ "Szenario", "Großmaschine", "Sturm 1 (Kristalle)", "Stürme 14 d", "Kristalle 14 d", "Lauf 10 Dauer", "Offline-Anteil" })
        for _, v in {
            { name = "Empfehlung", sessions = { active = 600, perDay = 2, companion = true }, activeSeconds = 14 * 1200 },
            { name = "Empfehlung + rateFactor 0,25", sessions = { active = 600, perDay = 2, companion = true }, activeSeconds = 14 * 1200, rf = 0.25 },
        } do
            local run = function()
                local sim = simulate(v :: any)
                local tool6 = nil
                for _, e in sim.events do
                    if e.kind == "buy" and e.id == "collect_tool_6" then
                        tool6 = e
                        break
                    end
                end
                row({
                    v.name,
                    if tool6 then `{fmtDays(tool6.real)} / {fmtTime(tool6.t)}` else "-",
                    if sim.runs[1] then `{fmtDays(sim.runs[1].atReal)} ({sim.runs[1].crystals})` else "-",
                    #sim.runs,
                    sim.crystals,
                    if sim.runs[10] then fmtTime(sim.runs[10].duration) else "-",
                    string.format("%.0f %%", sim.offlineCoins / math.max(sim.earnedTotal, 1) * 100),
                })
                return nil
            end
            if v.rf then
                withPatch({ { Economy.offline, "rateFactor", v.rf } }, run)
            else
                run()
            end
        end
        title("Empfehlung: Sturm-Strategien (8 h aktiv)")
        header({ "Strategie", "Stürme", "Kristalle 2 h", "Kristalle 8 h" })
        for _, st in { { "Sofort bei minCrystals", "asap" }, { "Baumende", "treeEnd" }, { "stall (3 min)", "stall" }, { "Kristallraten-optimal", "optimal" } } do
            local sim = simulate({ name = st[1], storm = st[2], activeSeconds = 8 * HOURS })
            local c2 = 0
            for _, r in sim.runs do
                if r.at <= 2 * HOURS then
                    c2 = r.total
                end
            end
            row({ st[1], #sim.runs, c2, sim.crystals })
        end
        return nil
    end)
    title("Langzeit (40 h aktiv): Empfehlung mit 200 bp und mit 100 bp je Kristall")
    header(LONG_HEADER)
    for _, bp in { 200, 100 } do
        withPatch(recommendedPatch(if bp == 100 then 100 else nil), function()
            row(longLine(`Empfehlung, {bp} bp`, simulate({ name = "x", activeSeconds = 40 * HOURS })))
            return nil
        end)
    end
end

-- Kurz-Check: Laufzeit
local started = os.clock()
print(`# Balance-Simulation 6.4 (Startwert {SEED}, Teil "{PART}")`)
print("")
print(`Weg je Richtung {WALK} s, Server-Takt {TICK} s, Kaufregel "billigster sichtbarer Knoten".`)
print("")

if PART == "all" or PART == "base" then
    partBase()
end
if PART == "all" or PART == "passes" then
    partPasses()
end
if PART == "all" or PART == "crystals" then
    partCrystalsBuyable()
end
if PART == "all" or PART == "storm" then
    partStorm()
end
if PART == "all" or PART == "casual" then
    partCasual()
end
if PART == "all" or PART == "crates" then
    partCrates()
end
if PART == "all" or PART == "proposals" then
    partProposals()
end
if PART == "all" or PART == "explore" then
    partExplore()
end
if PART == "all" or PART == "recommended" then
    partRecommended()
end
if PART == "all" or PART == "explorelong" then
    partExploreLong()
end
if PART == "all" or PART == "long" then
    partLong()
end
print("")
print(string.format("Laufzeit %.1f s", os.clock() - started))
