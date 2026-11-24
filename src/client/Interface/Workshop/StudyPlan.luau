--!strict
local StudyPlan = {}

type Node = {
    id: string,
    cost: number,
    requires: { string },
    requiresAny: { string },
}

export type Plan = { steps: { string }, cost: number }

function StudyPlan.find(byId: { [string]: Node }, goal: string, owned: { [string]: boolean }): Plan?
    local choices: { [string]: string } = {}
    local best: Plan? = nil

    -- Restart the topological walk when a new OR choice is found. Evaluating the
    -- complete plan makes shared prerequisites count once even across branches.
    local function try()
        local visiting: { [string]: boolean } = {}
        local added: { [string]: boolean } = {}
        local steps: { string } = {}
        local cost = 0
        local unresolved: Node? = nil

        local function visit(id: string): boolean
            if id == "start" or owned[id] or added[id] then
                return true
            end
            local node = byId[id]
            if not node or visiting[id] then
                return false
            end
            visiting[id] = true
            for _, parent in node.requires do
                if not visit(parent) then
                    return false
                end
            end
            if #node.requiresAny > 0 then
                local fulfilled = false
                for _, parent in node.requiresAny do
                    if parent == "start" or owned[parent] or added[parent] then
                        fulfilled = true
                        break
                    end
                end
                if not fulfilled then
                    local choice = choices[id]
                    if not choice then
                        unresolved = node
                        return false
                    end
                    if not visit(choice) then
                        return false
                    end
                end
            end
            visiting[id] = nil
            added[id] = true
            cost += node.cost
            table.insert(steps, id)
            return true
        end

        if visit(goal) then
            if best == nil or cost < best.cost or (cost == best.cost and #steps < #best.steps) then
                best = { steps = steps, cost = cost }
            end
        elseif unresolved then
            local option = unresolved
            for _, parent in option.requiresAny do
                choices[option.id] = parent
                try()
            end
            choices[option.id] = nil
        end
    end

    try()
    return best
end

return StudyPlan
