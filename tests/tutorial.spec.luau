--!strict
-- Paket 1.6: Tutorial-Fortschritt und Zeit-Simulation der ersten 2 Minuten.

local T = require("./lib/expect")
local Tutorial = require("../src/shared/Logic/Tutorial")
local TreePurchase = require("../src/shared/Logic/TreePurchase")
local Collecting = require("../src/shared/Logic/Collecting")
local Profile = require("../src/shared/Logic/Profile")
local BigNum = require("../src/shared/Logic/BigNum")
local Economy = require("../src/shared/Data/Economy")
local TutorialData = require("../src/shared/Data/Tutorial")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")

local NOW = 1_700_000_000
local DONE = Tutorial.count() + 1

local function fresh(): any
    return Profile.default(NOW)
end

local function setTank(profile: any, amount: number)
    profile.tank = BigNum.serialize(BigNum.new(amount))
end

T.describe("Tutorial-Fortschritt", function()
    T.it("ein neuer Spieler startet bei Schritt 1", function()
        local profile = fresh()
        T.expect(Tutorial.stepOf(profile)).toBe(1)
        T.expect(Tutorial.isDone(profile)).toBe(false)
        T.expect((Tutorial.current(profile) :: any).id).toBe("collect")
        T.expect(Tutorial.evaluate(profile)).toBe(false)
        T.expect(Tutorial.stepOf(profile)).toBe(1)
    end)

    T.it("15 Sand führen zu Schritt 2, der erste Verkauf zu 3, collect_rate_1 zu 4, die Schaufel zum Ende", function()
        local profile = fresh()
        setTank(profile, 14)
        T.expect(Tutorial.evaluate(profile)).toBe(false)
        T.expect(Tutorial.stepOf(profile)).toBe(1)
        setTank(profile, 15)
        T.expect(Tutorial.evaluate(profile)).toBe(true)
        T.expect(Tutorial.stepOf(profile)).toBe(2)
        -- Ohne Verkauf bleibt es bei Schritt 2, auch mit vollem Tank.
        T.expect(Tutorial.evaluate(profile)).toBe(false)
        T.expect(Tutorial.stepOf(profile)).toBe(2)
        setTank(profile, 0)
        T.expect(Tutorial.onSold(profile)).toBe(true)
        T.expect(Tutorial.stepOf(profile)).toBe(3)
        profile.nodes.collect_rate_1 = true
        T.expect(Tutorial.evaluate(profile)).toBe(true)
        T.expect(Tutorial.stepOf(profile)).toBe(4)
        profile.nodes.collect_tool_2 = true
        T.expect(Tutorial.evaluate(profile)).toBe(true)
        T.expect(Tutorial.stepOf(profile)).toBe(DONE)
        T.expect(Tutorial.isDone(profile)).toBe(true)
        T.expect(Tutorial.current(profile)).toBeNil()
    end)

    T.it("15 Sand bei größerem Tank zählen auch (Tank 30)", function()
        local profile = fresh()
        profile.nodes.tank_1 = true
        setTank(profile, 15)
        Tutorial.evaluate(profile)
        T.expect(Tutorial.stepOf(profile)).toBe(2)
    end)

    T.it("ein Verkauf vor dem vollen Tank überspringt Schritt 1", function()
        local profile = fresh()
        setTank(profile, 6)
        T.expect(Tutorial.onSold(profile)).toBe(true)
        T.expect(Tutorial.stepOf(profile)).toBe(3)
    end)

    T.it("ein Verkauf in Schritt 3 oder später ändert nichts", function()
        local profile = fresh()
        profile.tutorial.step = 3
        T.expect(Tutorial.onSold(profile)).toBe(false)
        T.expect(Tutorial.stepOf(profile)).toBe(3)
        profile.tutorial.step = DONE
        T.expect(Tutorial.onSold(profile)).toBe(false)
        T.expect(Tutorial.stepOf(profile)).toBe(DONE)
    end)

    T.it("Schritte gehen nie zurück", function()
        local profile = fresh()
        profile.tutorial.step = 3
        setTank(profile, 0)
        Tutorial.evaluate(profile)
        T.expect(Tutorial.stepOf(profile)).toBe(3)
        profile.tutorial.step = DONE
        profile.nodes = {}
        Tutorial.evaluate(profile)
        T.expect(Tutorial.stepOf(profile)).toBe(DONE)
    end)
end)

T.describe("Tutorial beim Laden", function()
    T.it("wer die Schaufel besitzt, überspringt alles", function()
        local profile = fresh()
        profile.nodes.collect_tool_2 = true
        T.expect(Tutorial.evaluate(profile)).toBe(true)
        T.expect(Tutorial.stepOf(profile)).toBe(DONE)
    end)

    T.it("wer collect_rate_1 besitzt, steht bei Schritt 4", function()
        local profile = fresh()
        profile.nodes.collect_rate_1 = true
        Tutorial.evaluate(profile)
        T.expect(Tutorial.stepOf(profile)).toBe(4)
    end)

    T.it("ein kaputter Schritt im Profil fällt auf einen gültigen Wert zurück", function()
        for _, broken in { -5, 0, 2.5, 0 / 0, math.huge, "zwei", false } do
            local profile = fresh()
            profile.tutorial.step = broken
            local step = Tutorial.stepOf(profile)
            T.expect(step >= 1 and step <= DONE).toBe(true)
            Tutorial.evaluate(profile)
            local fixed = profile.tutorial.step
            T.expect(type(fixed)).toBe("number")
            T.expect(fixed >= 1 and fixed <= DONE and fixed % 1 == 0).toBe(true)
        end
        local profile = fresh()
        profile.tutorial = nil :: any
        T.expect(Tutorial.stepOf(profile)).toBe(1)
        Tutorial.evaluate(profile)
        T.expect(profile.tutorial.step).toBe(1)
        local huge = fresh()
        huge.tutorial.step = 99
        T.expect(Tutorial.stepOf(huge)).toBe(DONE)
    end)

    T.it("ein alter Spielstand ohne tutorial-Feld bekommt Schritt 1 (Migration füllt Standardwerte)", function()
        local old = Profile.default(NOW) :: any
        old.tutorial = nil
        local migrated = Profile.migrate(old)
        T.expect(migrated.tutorial.step).toBe(1)
    end)

    T.it("Knoten-Schritte nennen existierende Knoten", function()
        for _, step in TutorialData.steps do
            if step.done.kind == "node" then
                T.expect(UpgradeTree.byId[step.done.nodeId :: string] ~= nil).toBe(true)
            end
        end
    end)
end)

-- Simulation: Sammeln (Server-Uhr, Auffrischung jede Sekunde), 5 s Weg je Richtung zum Händler,
-- verkaufen, dann immer den billigsten sichtbaren Knoten kaufen, solange das Geld reicht
-- (wie docs/balance/phase0_startwerte.md). Verkaufen und Kaufen kosten keine Zeit.
local WALK_SECONDS = 5

local function simulate(seconds: number): (any, { [string]: number }, { [number]: number })
    local profile = fresh()
    local state = Collecting.newState(0)
    local t = 0
    local boughtAt: { [string]: number } = {}
    local stepAt: { [number]: number } = {}
    local function track()
        Tutorial.evaluate(profile)
        local step = Tutorial.stepOf(profile)
        if stepAt[step] == nil then
            stepAt[step] = t
        end
    end
    stepAt[1] = 0
    while t < seconds do
        -- Sammeln, bis der Tank voll ist.
        local guard = 0
        Collecting.setHolding(state, profile, true, t)
        while not Collecting.isFull(profile) and guard < 10000 do
            t += 0.25
            local result = Collecting.setHolding(state, profile, true, t)
            guard += 1
            if result.added > 0 then
                track()
            end
        end
        Collecting.setHolding(state, profile, false, t)
        t += WALK_SECONDS
        local earned = Collecting.sell(state, profile, t)
        if earned ~= nil then
            Tutorial.onSold(profile)
            track()
        end
        while true do
            local visible = TreePurchase.visible(profile)
            local nodeId = visible[1]
            if nodeId == nil or TreePurchase.check(profile, nodeId) ~= nil then
                break
            end
            TreePurchase.buy(profile, nodeId)
            boughtAt[nodeId] = t
            track()
        end
        t += WALK_SECONDS -- zurück zum Feld
    end
    return profile, boughtAt, stepAt
end

T.describe("Die ersten 2 Minuten (Simulation)", function()
    T.it("erstes Upgrade nach etwa 20 s, Schaufel nach etwa 2 Minuten", function()
        local _, boughtAt, stepAt = simulate(240)
        local firstUpgrade = boughtAt.collect_rate_1
        local shovel = boughtAt.collect_tool_2
        print(`       erstes Upgrade {firstUpgrade} s, Schaufel {shovel} s, Tutorial-Schritte {stepAt[2]} {stepAt[3]} {stepAt[4]} {stepAt[DONE]}`)
        T.expect(firstUpgrade ~= nil and shovel ~= nil).toBe(true)
        T.expect(math.abs(firstUpgrade - Economy.targetSeconds.firstUpgrade) <= Economy.targetSeconds.firstUpgrade * 0.15).toBe(true)
        T.expect(math.abs(shovel - Economy.targetSeconds.shovel) <= Economy.targetSeconds.shovel * 0.15).toBe(true)
    end)

    T.it("das Tutorial endet mit der Schaufel und durchläuft alle Schritte der Reihe nach", function()
        local profile, boughtAt, stepAt = simulate(240)
        T.expect(Tutorial.isDone(profile)).toBe(true)
        T.expect(stepAt[DONE]).toBe(boughtAt.collect_tool_2)
        local previous = -1
        for step = 1, DONE do
            T.expect(stepAt[step] ~= nil).toBe(true)
            T.expect(stepAt[step] >= previous).toBe(true)
            previous = stepAt[step]
        end
        -- Der erste Verkauf ist nach etwa 20 s (15 Sand plus 5 s Weg).
        T.expect(stepAt[3]).toBeCloseTo(20, 1)
    end)

    T.it("Kaufprotokoll: Tank-Knoten und Schaufel kommen in der Reihenfolge der Balance-Tabelle", function()
        local _, boughtAt = simulate(300)
        T.expect(boughtAt.collect_rate_1 < boughtAt.tank_1).toBe(true)
        T.expect(boughtAt.tank_1 < boughtAt.collect_tool_2).toBe(true)
        T.expect(boughtAt.collect_tool_2 < boughtAt.tank_2).toBe(true)
        T.expect(boughtAt.tank_2 < boughtAt.collect_rate_2).toBe(true)
    end)
end)

T.finish()
