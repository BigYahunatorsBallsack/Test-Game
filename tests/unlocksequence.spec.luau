--!strict
-- Paket 2.3: Ablaufplan der Freischalt-Sequenz (reine Logik) und die Daten dazu.

local T = require("./lib/expect")
local UnlockSequence = require("../src/shared/Logic/UnlockSequence")
local TreeView = require("../src/shared/Logic/TreeView")
local TreeLayout = require("../src/shared/Logic/TreeLayout")
local TreePurchase = require("../src/shared/Logic/TreePurchase")
local DataCheck = require("../src/shared/Logic/DataCheck")
local Profile = require("../src/shared/Logic/Profile")
local BigNum = require("../src/shared/Logic/BigNum")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local Anim = require("../src/shared/Data/UnlockAnimation")
local Sounds = require("../src/shared/Data/TreeSounds")

local NOW = 1_700_000_000
local layout = TreeLayout.compute()

-- Tiefe Kopie, die gemeinsame Referenzen (list und byId zeigen auf dieselben Knoten) erhält.
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

local function profileWith(coins: number, owned: { string }): any
    local profile = Profile.default(NOW)
    profile.coins = BigNum.serialize(BigNum.new(coins))
    for _, id in owned do
        profile.nodes[id] = true
    end
    return profile
end

-- Plan für den Kauf von `nodeId` aus einem Zustand heraus (Münzen sinken um den Preis).
local function planFor(owned: { string }, nodeId: string, coins: number?, purchases: number?): UnlockSequence.Plan
    local start = coins or 1_000_000
    local beforeProfile = profileWith(start, owned)
    local after = profileWith(start, owned)
    TreePurchase.buy(after, nodeId)
    local plan = UnlockSequence.plan(TreeView.build(beforeProfile, layout), TreeView.build(after, layout), nodeId, purchases or 0)
    return plan :: UnlockSequence.Plan
end

local function stepOf(plan: UnlockSequence.Plan, name: string): UnlockSequence.Step?
    for _, step in plan.steps do
        if step.name == name then
            return step
        end
    end
    return nil
end

T.describe("Vergleich zweier Zustände", function()
    T.it("findet neu gekaufte Knoten in der Reihenfolge der Tabelle", function()
        T.expect(UnlockSequence.diff({}, { tank_1 = true })).toEqual({ "tank_1" })
        T.expect(UnlockSequence.diff({ tank_1 = true }, { tank_1 = true, tank_2 = true, collect_rate_1 = true })).toEqual({ "collect_rate_1", "tank_2" })
    end)

    T.it("der erste Zustand (kein Vorgänger) und unveränderte Zustände zählen nie", function()
        T.expect(UnlockSequence.diff(nil, { tank_1 = true, collect_tool_2 = true })).toEqual({})
        T.expect(UnlockSequence.diff({ tank_1 = true }, { tank_1 = true })).toEqual({})
        T.expect(UnlockSequence.diff({}, nil)).toEqual({})
    end)

    T.it("entfernte und unbekannte Knoten zählen nicht", function()
        T.expect(UnlockSequence.diff({ tank_1 = true, tank_2 = true }, { tank_1 = true })).toEqual({})
        T.expect(UnlockSequence.diff({}, { gibt_es_nicht = true })).toEqual({})
        T.expect(UnlockSequence.diff({ tank_1 = true }, { tank_1 = false })).toEqual({})
    end)
end)

T.describe("Variante", function()
    T.it("der erste Kauf ist normal, ein Meilenstein-Knoten immer Meilenstein, ab dem elften Kauf kurz", function()
        T.expect(UnlockSequence.variantFor("tank_1", 0)).toBe("normal")
        T.expect(UnlockSequence.variantFor("tank_1", Anim.shortAfterPurchases - 1)).toBe("normal") -- der zehnte Kauf
        T.expect(UnlockSequence.variantFor("tank_1", Anim.shortAfterPurchases)).toBe("short") -- der elfte Kauf
        T.expect(UnlockSequence.variantFor("tank_1", 500)).toBe("short")
        T.expect(UnlockSequence.variantFor("collect_tool_3", 0)).toBe("milestone")
        T.expect(UnlockSequence.variantFor("collect_tool_3", 500)).toBe("milestone")
    end)

    T.it("die Daten legen die Meilensteine fest: Knoten mit milestone", function()
        local count = 0
        for _, node in UpgradeTree.list do
            if node.milestone ~= nil then
                count += 1
                T.expect(UnlockSequence.variantFor(node.id, 0)).toBe("milestone")
            end
        end
        T.expect(count).toBeGreaterThan(0)
    end)
end)

T.describe("Neu sichtbare Knoten", function()
    T.it("nach tank_1 wird tank_2 lesbar und tank_3 taucht als Silhouette auf", function()
        local plan = planFor({}, "tank_1")
        T.expect(plan.revealed).toEqual({ "tank_2", "tank_3" })
        local seen: { [string]: boolean } = {}
        for _, id in plan.revealed do
            T.expect(seen[id]).toBeNil()
            seen[id] = true
        end
    end)

    T.it("die Schaufel macht ihre Folgeknoten sichtbar, der gekaufte Knoten ist nicht dabei", function()
        local plan = planFor({}, "collect_tool_2")
        for _, id in { "luck_1", "collect_rate_2", "sell_1", "collect_tool_3" } do
            T.expect(plan.revealed).toContain(id)
        end
        for _, id in plan.revealed do
            T.expect(id == "collect_tool_2").toBe(false)
        end
    end)

    T.it("ein Kauf ohne neue Knoten hat eine leere Liste (collect_rate_1 öffnet nichts)", function()
        T.expect(planFor({}, "collect_rate_1").revealed).toEqual({})
    end)
end)

T.describe("Impuls und Glanz", function()
    T.it("Impulskanten laufen nur vom gekauften Knoten zu Folgeknoten in derselben Spalte", function()
        local plan = planFor({ "tank_1" }, "tank_2")
        T.expect(plan.pulseEdges).toEqual({ { from = "tank_2", to = "tank_3" } })
        for _, edge in planFor({}, "collect_tool_2").pulseEdges do
            T.expect(edge.from).toBe("collect_tool_2")
            T.expect(layout.nodes[edge.from].column).toBe(layout.nodes[edge.to].column)
        end
    end)

    T.it("Folgeknoten anderer Spalten bekommen einen Glanzring statt einer Linie", function()
        local plan = planFor({}, "collect_tool_2")
        T.expect(plan.pulseEdges).toEqual({ { from = "collect_tool_2", to = "collect_tool_3" } })
        T.expect(plan.glintTargets).toEqual({ "luck_1", "collect_rate_2", "sell_1" })
        for _, id in plan.glintTargets do
            T.expect(layout.nodes[id].column == layout.nodes.collect_tool_2.column).toBe(false)
            T.expect(plan.revealed).toContain(id)
        end
    end)

    T.it("die kurze Variante hat weder Impuls noch Glanz", function()
        local plan = planFor({}, "collect_tool_2", nil, Anim.shortAfterPurchases)
        T.expect(plan.variant).toBe("short")
        T.expect(plan.pulseEdges).toEqual({})
        T.expect(plan.glintTargets).toEqual({})
        T.expect(stepOf(plan, "pulse")).toBeNil()
    end)

    T.it("ein Kauf ohne Folgeknoten (Ende eines Asts) hat keinen Impuls und keinen Glanz", function()
        local owned: { string } = {}
        for _, node in UpgradeTree.list do
            if not node.granted and node.id ~= "tank_12" then
                table.insert(owned, node.id)
            end
        end
        local plan = planFor(owned, "tank_12", 0)
        T.expect(plan.pulseEdges).toEqual({})
        T.expect(plan.glintTargets).toEqual({})
        T.expect(plan.revealed).toEqual({})
    end)
end)

T.describe("Zeitleiste", function()
    T.it("Reihenfolge: Eindrücken, Ring, Impuls, Einblenden, Kamera", function()
        for _, plan in { planFor({}, "tank_1"), planFor({ "collect_tool_2" }, "collect_tool_3") } do
            local last = -1
            for _, name in { "press", "ring", "pulse", "reveal", "camera" } do
                local step = stepOf(plan, name)
                T.expect(step == nil).toBe(false)
                T.expect((step :: UnlockSequence.Step).start >= last).toBe(true)
                last = (step :: UnlockSequence.Step).start
            end
        end
    end)

    T.it("Gesamtdauer: normal 1,2 s, kurz höchstens 0,6 s, Meilenstein 1,6 s", function()
        T.expect(planFor({}, "tank_1").totalSeconds).toBeCloseTo(1.2, 0.05)
        T.expect(planFor({}, "tank_1", nil, 99).totalSeconds <= 0.6).toBe(true)
        T.expect(planFor({ "collect_tool_2" }, "collect_tool_3").totalSeconds).toBeCloseTo(1.6, 0.05)
    end)

    T.it("die Schritte sind nach Start sortiert und liegen innerhalb der Gesamtdauer", function()
        for _, plan in { planFor({}, "tank_1"), planFor({}, "tank_1", nil, 99), planFor({ "collect_tool_2" }, "collect_tool_3") } do
            local last = -1
            for _, step in plan.steps do
                T.expect(step.start >= last).toBe(true)
                last = step.start
                T.expect(step.start + step.duration <= plan.totalSeconds + 1e-9).toBe(true)
            end
        end
    end)

    T.it("nur die Meilenstein-Variante hat den Aufhell-Puls und den größeren Ring", function()
        local normal = planFor({}, "tank_1")
        local milestone = planFor({ "collect_tool_2" }, "collect_tool_3")
        T.expect(stepOf(normal, "flash")).toBeNil()
        T.expect(normal.flashStrength).toBeNil()
        T.expect(stepOf(milestone, "flash") == nil).toBe(false)
        T.expect((milestone.flashStrength :: number) > 0).toBe(true)
        T.expect(milestone.ringScale).toBeGreaterThan(normal.ringScale)
    end)
end)

T.describe("Kamera und Töne", function()
    T.it("die Kamerapunkte enthalten den gekauften Knoten und alle neu sichtbaren Knoten", function()
        for _, case in { { {}, "tank_1" }, { {}, "collect_tool_2" }, { { "collect_tool_2" }, "collect_tool_3" } } do
            local plan = planFor(case[1] :: { string }, case[2] :: string)
            T.expect(plan.cameraPoints[1]).toBe(case[2])
            for _, id in plan.revealed do
                T.expect(plan.cameraPoints).toContain(id)
            end
            T.expect(#plan.cameraPoints).toBe(#plan.revealed + 1)
        end
    end)

    T.it("die Töne passen zur Variante", function()
        local function names(plan: UnlockSequence.Plan): { string }
            local result: { string } = {}
            for _, cue in plan.cues do
                table.insert(result, cue.name)
            end
            return result
        end
        T.expect(names(planFor({}, "tank_1"))).toEqual({ "press", "ring", "reveal" })
        T.expect(names(planFor({ "collect_tool_2" }, "collect_tool_3"))).toEqual({ "press", "ring", "milestone", "reveal" })
        T.expect(names(planFor({}, "tank_1", nil, 99))).toEqual({ "press", "reveal" })
        for _, cue in planFor({ "collect_tool_2" }, "collect_tool_3").cues do
            T.expect(Sounds.cues[cue.name] == nil).toBe(false)
        end
    end)

    T.it("ein Kauf, den es nicht gibt, ergibt keinen Plan", function()
        local view = TreeView.build(profileWith(100, {}), layout)
        T.expect(UnlockSequence.plan(view, view, "gibt_es_nicht", 0)).toBeNil()
    end)
end)

T.describe("Daten der Sequenz", function()
    T.it("DataCheck meldet für die echten Daten keine Fehler, die Sound-IDs sind noch leer", function()
        T.expect(DataCheck.run()).toEqual({})
        for _, cue in Sounds.cues do
            T.expect(cue.soundId).toBe("")
        end
    end)

    local function errorsFor(change: (any) -> ()): string
        local data: any = deepCopy(DataCheck.defaults())
        change(data)
        return table.concat(DataCheck.run(data), "\n")
    end

    T.it("Schritte in falscher Reihenfolge werden abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.normal.ring.start = 0.45 -- nach dem Impuls
        end)).toContain("startet vor dem Schritt davor")
    end)

    T.it("zu lange oder kaputte Dauern werden abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.normal.camera.duration = 5
        end)).toContain("erlaubt sind höchstens")
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.short.reveal.duration = 0
        end)).toContain("duration über 0")
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.short.press.start = -1
        end)).toContain("start ab 0")
    end)

    T.it("die kurze Variante muss kürzer, die Meilenstein-Variante länger sein als die normale", function()
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.short.camera.duration = 1
        end)).toContain("kürzer")
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.milestone.camera.duration = 0.2
        end)).toContain("länger")
    end)

    T.it("fehlende Schritte, Töne und falsche Grenzen werden abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.normal.camera = nil
        end)).toContain("normal.camera fehlt")
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.normal.cues.pling = "press"
        end)).toContain("Ton \"pling\" fehlt in TreeSounds")
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.short.cues.press = "pulse" -- die kurze Variante hat keinen Impuls
        end)).toContain("gibt es in dieser Variante nicht")
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.shortAfterPurchases = 0
        end)).toContain("shortAfterPurchases")
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.milestone.flash.strength = 2
        end)).toContain("flash.strength")
        T.expect(errorsFor(function(data: any)
            data.UnlockAnimation.variants.normal.ring.scale = 1
        end)).toContain("ring.scale")
    end)

    T.it("Sound-IDs: leer und rbxassetid:// plus Ziffern gelten, alles andere nicht", function()
        T.expect(errorsFor(function(data: any)
            data.TreeSounds.cues.press.soundId = "rbxassetid://12345"
        end)).toBe("")
        for _, bad in { "12345", "rbxassetid://", "rbxassetid://abc", "https://example.com/a.mp3", " " } do
            T.expect(errorsFor(function(data: any)
                data.TreeSounds.cues.press.soundId = bad
            end)).toContain("soundId")
        end
        T.expect(errorsFor(function(data: any)
            data.TreeSounds.cues.reveal.volume = 3
        end)).toContain("volume")
        T.expect(errorsFor(function(data: any)
            data.TreeSounds.cues.ring.pitch = 0
        end)).toContain("pitch")
    end)
end)

T.finish()
