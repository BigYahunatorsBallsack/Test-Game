--!strict
-- Ablaufplan der Freischalt-Sequenz (Paket 2.3). Rein, ohne Roblox-API, Lune-Tests in
-- tests/unlocksequence.spec.luau. Der Controller SkillTree spielt den Plan nur ab.
--
-- Ausgelöst wird die Sequenz nicht durch den Klick, sondern durch den Vergleich zweier
-- StateSync-Zustände: Ein Knoten, der neu in `nodes` steht, wurde gekauft. Der erste Zustand
-- nach dem Beitreten hat keinen Vorgänger und zählt nie als Kauf.

local UpgradeTree = require("../Data/UpgradeTree")
local DefaultData = require("../Data/UnlockAnimation")

export type VariantName = "normal" | "short" | "milestone"

export type Step = { name: string, start: number, duration: number }
export type Cue = { name: string, at: number }
export type Edge = { from: string, to: string }

export type Plan = {
    nodeId: string,
    variant: VariantName,
    steps: { Step }, -- nach Start sortiert
    totalSeconds: number,
    revealed: { string }, -- Knoten, die aus dem Nebel auftauchen oder lesbar werden
    pulseEdges: { Edge }, -- Linien, auf denen der Lichtimpuls läuft (nur gleiche Spalte)
    glintTargets: { string }, -- Folgeknoten ohne Linie (andere Spalte): kleiner Glanzring
    cameraPoints: { string }, -- Knoten, die die Kamera zeigen soll
    cues: { Cue },
    ringScale: number,
    flashStrength: number?,
}

local STEP_ORDER = { "press", "ring", "pulse", "reveal", "camera", "flash" }

local UnlockSequence = {}

-- Neu gekaufte Knoten (in der Reihenfolge der Tabelle). Ohne Vorgänger: nichts. Unbekannte IDs
-- (entfernte Knoten) und Knoten, die nur verschwunden sind, zählen nicht.
function UnlockSequence.diff(previous: { [string]: boolean }?, current: { [string]: boolean }?): { string }
    local found: { string } = {}
    if previous == nil or current == nil then
        return found
    end
    for _, node in UpgradeTree.list do
        if current[node.id] == true and previous[node.id] ~= true then
            table.insert(found, node.id)
        end
    end
    return found
end

-- Variante nach den bisher abgespielten Käufen dieser Sitzung.
function UnlockSequence.variantFor(nodeId: string, purchasesBefore: number, data: any?): VariantName
    local cfg: any = data or DefaultData
    local node = UpgradeTree.byId[nodeId]
    if node ~= nil and node.milestone ~= nil then
        return "milestone"
    end
    if purchasesBefore >= cfg.shortAfterPurchases then
        return "short"
    end
    return "normal"
end

-- Plan für den Kauf von `nodeId`. `before` und `after` sind TreeView.View vor und nach dem
-- Kauf, `purchasesBefore` ist die Zahl der schon abgespielten Käufe dieser Sitzung.
function UnlockSequence.plan(before: any, after: any, nodeId: string, purchasesBefore: number, data: any?): Plan?
    local cfg: any = data or DefaultData
    local node = UpgradeTree.byId[nodeId]
    if node == nil or after.nodes[nodeId] == nil then
        return nil
    end
    local variantName = UnlockSequence.variantFor(nodeId, purchasesBefore, cfg)
    local variant: any = cfg.variants[variantName]

    -- Neu sichtbare Knoten: aus dem Nebel aufgetaucht oder von Silhouette zu lesbar.
    local revealed: { string } = {}
    for _, other in UpgradeTree.list do
        if other.id ~= nodeId then
            local was: string? = before.nodes[other.id]
            local now: string? = after.nodes[other.id]
            if now ~= nil and now ~= "hidden" then
                if was == nil or was == "hidden" or (was == "silhouette" and now ~= "silhouette") then
                    table.insert(revealed, other.id)
                end
            end
        end
    end

    local steps: { Step } = {}
    local total = 0
    for _, name in STEP_ORDER do
        local step: any = variant[name]
        if step ~= nil then
            table.insert(steps, { name = name, start = step.start, duration = step.duration })
            total = math.max(total, step.start + step.duration)
        end
    end
    table.sort(steps, function(a: Step, b: Step)
        return a.start < b.start
    end)

    -- Lichtimpuls nur, wenn die Variante ihn hat.
    local edges: { Edge } = {}
    local glints: { string } = {}
    if variant.pulse ~= nil then
        local pulseTargets: { [string]: boolean } = {}
        for _, line in after.lines do
            if line.from == nodeId then
                table.insert(edges, { from = line.from, to = line.to })
                pulseTargets[line.to] = true
            end
        end
        for _, id in revealed do
            if not pulseTargets[id] then
                for _, required in UpgradeTree.byId[id].requires do
                    if required == nodeId then
                        table.insert(glints, id)
                        break
                    end
                end
            end
        end
    end

    local cameraPoints: { string } = { nodeId }
    for _, id in revealed do
        table.insert(cameraPoints, id)
    end

    local cues: { Cue } = {}
    local stepStart: { [string]: number } = {}
    for _, step in steps do
        stepStart[step.name] = step.start
    end
    local cueNames: { string } = {}
    for cueName in variant.cues do
        table.insert(cueNames, cueName)
    end
    table.sort(cueNames)
    for _, cueName in cueNames do
        local at = stepStart[variant.cues[cueName]]
        if at ~= nil then
            table.insert(cues, { name = cueName, at = at })
        end
    end
    table.sort(cues, function(a: Cue, b: Cue)
        if a.at ~= b.at then
            return a.at < b.at
        end
        return a.name < b.name
    end)

    return {
        nodeId = nodeId,
        variant = variantName,
        steps = steps,
        totalSeconds = total,
        revealed = revealed,
        pulseEdges = edges,
        glintTargets = glints,
        cameraPoints = cameraPoints,
        cues = cues,
        ringScale = variant.ring.scale,
        flashStrength = if variant.flash ~= nil then variant.flash.strength else nil,
    }
end

return UnlockSequence
