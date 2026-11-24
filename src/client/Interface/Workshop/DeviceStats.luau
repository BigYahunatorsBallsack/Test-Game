--!strict
local DeviceStats = {}

type Effect = { stat: string?, unit: string?, delta: number?, target: string?, cooldown: number? }
type Node = { id: string, name: string, kind: string, effect: Effect? }
type Value = { stat: string, unit: string, total: number }
type Group = { node: Node?, values: { Value }, baseCooldown: number?, cooldown: number? }
type Owned = { [string]: boolean }

local function findValue(group: Group, stat: string, unit: string): Value?
    for _, value in group.values do
        if value.stat == stat and value.unit == unit then
            return value
        end
    end
    return nil
end

function DeviceStats.collect(nodes: { Node }, owned: Owned): ({ Group }, { [string]: Group })
    local passive: Group = { values = {} }
    local groups = { passive }
    local byTarget = { passive = passive }
    for _, node in nodes do
        if node.kind == "ability" or node.kind == "variant" or node.kind == "mastery" then
            local base = node.effect and node.effect.cooldown
            local group: Group = { node = node, values = {}, baseCooldown = base, cooldown = base }
            byTarget[node.id] = group
            table.insert(groups, group)
        end
    end
    for _, node in nodes do
        local effect = node.effect
        if owned[node.id] and effect and effect.stat and effect.unit and effect.delta then
            local group = byTarget[effect.target or "passive"]
            if group then
                local value = findValue(group, effect.stat, effect.unit)
                if not value then
                    value = { stat = effect.stat, unit = effect.unit, total = 0 }
                    table.insert(group.values, value)
                end
                value.total += effect.delta
                if group.cooldown and effect.stat == "Abklingzeit" and effect.unit == "s" then
                    group.cooldown += effect.delta
                end
            end
        end
    end
    return groups, byTarget
end

function DeviceStats.projection(node: Node, groups: { [string]: Group }): (number?, number?)
    local effect = node.effect
    if not effect or not effect.delta or not effect.stat or not effect.unit then
        return nil, nil
    end
    local group = groups[effect.target or "passive"]
    if not group then
        return nil, nil
    end
    if group.cooldown and effect.stat == "Abklingzeit" and effect.unit == "s" then
        return group.cooldown, group.cooldown + effect.delta
    end
    local value = findValue(group, effect.stat, effect.unit)
    local current = if value then value.total else 0
    return current, current + effect.delta
end

function DeviceStats.format(value: number, unit: string, signed: boolean?): string
    local rounded = math.round(value * 1000) / 1000
    local prefix = if rounded < 0 then "−" elseif signed and rounded > 0 then "+" else ""
    return prefix .. (tostring(math.abs(rounded)):gsub("%.", ",")) .. " " .. unit
end

return DeviceStats
