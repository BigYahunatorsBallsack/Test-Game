--!strict
local Navigation = {}

type Node = {
    id: string,
    y: number,
    x: number,
    requires: { string },
    requiresAny: { string },
}

local function open(node: Node, owned: { [string]: boolean }): boolean
    for _, parent in node.requires do
        if parent ~= "start" and not owned[parent] then
            return false
        end
    end
    for _, parent in node.requiresAny do
        if parent == "start" or owned[parent] then
            return true
        end
    end
    return #node.requiresAny == 0
end

function Navigation.newlyReachable(
    nodes: { Node },
    before: { [string]: boolean },
    after: { [string]: boolean }
)
    local reached: { string } = {}
    for _, node in nodes do
        if not after[node.id] and open(node, after) and not open(node, before) then
            table.insert(reached, node.id)
        end
    end
    return reached
end

-- When an OR requirement is already fulfilled, trace the learned branches.
-- Otherwise show each option in amber. A shared mandatory edge takes precedence.
function Navigation.route(byId: { [string]: Node }, target: string?, learned: (string) -> boolean)
    local nodes: { [string]: number } = {}
    local edges: { [string]: { [string]: number } } = {}
    local function visit(id: string, weight: number)
        if (nodes[id] or 0) >= weight then
            return
        end
        nodes[id] = weight
        local node = byId[id]
        if not node then
            return
        end
        local parents = edges[id] or {}
        edges[id] = parents
        local function link(parent: string, strength: number)
            parents[parent] = math.max(parents[parent] or 0, strength)
            if learned(parent) then
                nodes[parent] = math.max(nodes[parent] or 0, strength)
            else
                visit(parent, strength)
            end
        end
        for _, parent in node.requires do
            link(parent, weight)
        end
        local fulfilled = false
        for _, parent in node.requiresAny do
            fulfilled = fulfilled or learned(parent)
        end
        for _, parent in node.requiresAny do
            if not fulfilled or learned(parent) then
                link(parent, if fulfilled then weight else 1)
            end
        end
    end
    if target then
        visit(target, 2)
    end
    return nodes, edges
end

return Navigation
