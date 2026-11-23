--!strict
-- UI catalogue. Game purchases still use Shared/Data/UpgradeTree.
local devices = require(script.Parent.Devices)
local support = require(script.Parent.Support)
local Catalog = {}

Catalog.width = 1050
Catalog.lanes = { "Tempo", "Reichweite", "Aushub", "Präzision" }
Catalog.supportNames = {
    collect = "Werkzeugstufen",
    tank = "Tank",
    sell = "Verkauf",
    luck = "Glück",
    sandstorm = "Sandsturm",
}
local core = {
    collect = "icon_currency_sand",
    tank = "icon_node_storage_tank",
    sell = "icon_node_selling_scales",
    luck = "icon_node_luck_compass",
    sandstorm = "icon_currency_wind_crystal",
}
local roman = { "I", "II", "III" }

local function deltaText(effect)
    local number = string.gsub(tostring(math.abs(effect.delta)), "%.", ",")
    return effect.stat
        .. " "
        .. (if effect.delta < 0 then "−" else "+")
        .. number
        .. " "
        .. effect.unit
end

function Catalog.build(baseNodes)
    local catalog = { tabs = {}, byId = {}, byTab = {}, families = {}, devices = devices }
    local function tier(id, family)
        local nodes = catalog.families[family] or {}
        catalog.families[family] = nodes
        table.insert(nodes, id)
        catalog.byId[id].family = family
    end
    local function tab(id, name, icon, row)
        local entry = { id = id, name = name, icon = icon, row = row, height = 1300, nodes = {} }
        table.insert(catalog.tabs, entry)
        catalog.byTab[id] = entry
        return entry
    end
    local function add(page, node)
        assert(not catalog.byId[node.id], "Duplicate workshop node " .. node.id)
        node.page = page.id
        node.requiresAny = node.requiresAny or {}
        catalog.byId[node.id] = node
        table.insert(page.nodes, node)
        return node.id
    end
    for _, device in devices do
        local page =
            tab(device.id, device.name, "icon_node_collect_" .. device.core, device.atlasRow)
        page.gate = device.gate
        local function create(key, name, kind, description, x, y, sprite, requires, factor, effect)
            return add(page, {
                id = key,
                name = name,
                kind = kind,
                description = description,
                x = x,
                y = y,
                sprite = sprite,
                requires = requires,
                cost = math.max(1, math.round(device.price * factor)),
                effect = effect,
                device = device.id,
            })
        end
        local function portrait(index)
            return device.atlasRow * 4 + index - 1
        end
        local gate = if device.gate == "start" then {} else { device.gate }
        local main = device.abilities[1]
        local base = create(
            device.abilityId,
            main.name,
            "ability",
            main.description .. " Abklingzeit " .. main.cooldown .. " s.",
            525,
            195,
            portrait(1),
            gate,
            1,
            { mechanic = device.abilityId, cooldown = main.cooldown }
        )
        local ends = {}
        local rails = { 100, 278, 772, 950 }
        local forkX = { 0, -39, 39, 0, -39, 39 }
        local forkY = { 180, 266, 266, 392, 475, 475 }
        for laneNo, lane in device.lanes do
            local learned = {}
            for rank, name in lane.names do
                local effect = lane.effects[1 + (rank - 1) % 2]
                local needs = gate
                if rank == 2 or rank == 3 then
                    needs = { learned[1] }
                elseif rank == 4 then
                    needs = { learned[2], learned[3] }
                elseif rank >= 5 then
                    needs = { learned[4] }
                end
                learned[rank] = create(
                    device.id .. "_p" .. laneNo .. "_" .. rank,
                    name,
                    "passive",
                    deltaText(effect) .. " mit " .. device.name .. ".",
                    rails[laneNo] + forkX[rank],
                    forkY[rank],
                    23 + laneNo,
                    needs,
                    0.30 + rank ^ 1.65 * 0.24,
                    effect
                )
                tier(learned[rank], device.id .. "_p" .. laneNo)
            end
            ends[laneNo] = { learned[5], learned[6] }
        end
        local function mod(spec, rank, levels, key, x, y, sprite, requires, price, target)
            local effect =
                { stat = spec.stat, delta = spec.delta, unit = spec.unit, target = target }
            local id = create(
                key,
                spec.name .. (if levels > 1 then " " .. roman[rank] else ""),
                "modifier",
                deltaText(effect) .. " für " .. catalog.byId[target].name .. ".",
                x,
                y,
                sprite,
                requires,
                price,
                effect
            )
            tier(id, target .. "_" .. spec.stat)
            return id
        end
        local primaryEnds = {}
        for path = 1, 2 do
            local prev = base
            for rank = 1, 3 do
                local key = if path == 1 and rank == 1
                    then base .. "_upgrade"
                    else base .. "_m" .. path .. "_" .. rank
                prev = mod(
                    device.mods[path],
                    rank,
                    3,
                    key,
                    if path == 1 then 405 else 645,
                    267 + (rank - 1) * 78,
                    portrait(1),
                    { prev },
                    1 + rank * 0.65,
                    base
                )
            end
            primaryEnds[path] = prev
        end
        local variantEnds = {}
        for side = 1, 2 do
            local ability = device.abilities[side + 1]
            local id = base .. (if side == 1 then "_a" else "_b")
            local variant = create(
                id,
                ability.name,
                "variant",
                ability.description,
                if side == 1 then 401 else 649,
                532,
                portrait(side + 1),
                { primaryEnds[side] },
                4.4,
                { mode = id, slot = device.id }
            )
            for j = 1, 2 do
                local prev = variant
                for rank = 1, 2 do
                    local x = (if side == 1 then 408 else 642) + (if j == 1 then -48 else 48)
                    prev = mod(
                        device.mods[2 + 2 * (side - 1) + j],
                        rank,
                        2,
                        id .. "_m" .. j .. "_" .. rank,
                        x,
                        654 + (rank - 1) * 100,
                        portrait(side + 1),
                        { prev },
                        4.6 + rank,
                        variant
                    )
                end
                table.insert(variantEnds, prev)
            end
        end
        local ability = device.abilities[4]
        local master = create(
            base .. "_master",
            ability.name,
            "mastery",
            ability.description,
            525,
            864,
            portrait(4),
            {},
            9.5,
            { extends = base }
        )
        catalog.byId[master].requiresAny = variantEnds
        for side = 1, 2 do
            local effect = device.lanes[side * 2 - 1].effects[1]
            create(
                device.id .. "_bridge" .. side,
                device.bridges[side],
                "keystone",
                deltaText(effect) .. " zusätzlich. Gilt für " .. device.name .. ".",
                if side == 1 then 175 else 875,
                595,
                23 + side * 2 - 1,
                {
                    ends[side * 2 - 1][1],
                    ends[side * 2 - 1][2],
                    ends[side * 2][1],
                    ends[side * 2][2],
                },
                7,
                effect
            )
        end
        local last = {}
        for j = 1, 3 do
            local spec = device.mods[if j == 2 then 8 else 7]
            local id = mod(
                spec,
                if j == 3 then 2 else 1,
                if j == 2 then 1 else 2,
                base .. "_master_" .. j,
                ({ 350, 525, 700 })[j],
                if j == 3 then 1090 else 982,
                portrait(4),
                { if j == 3 then last[1] else master },
                9 + j,
                master
            )
            table.insert(last, id)
        end
        create(
            device.id .. "_crown",
            device.bridges[3],
            "keystone",
            "Nach der Meisterschaft verkürzt sich die Abklingzeit von "
                .. main.name
                .. " um weitere 2 s.",
            525,
            1200,
            portrait(4),
            { last[2], last[3] },
            15,
            { stat = "Abklingzeit", delta = -2, unit = "s", target = base }
        )
    end
    for _, key in { "collect", "tank", "sell", "luck", "sandstorm" } do
        local page = tab(key, Catalog.supportNames[key], core[key])
        local lanes = { 0, 0 }
        for _, n in baseNodes do
            if n.branch ~= key then
                continue
            end
            local col = if key == "collect" and n.effect.kind == "setTool" then 2 else 1
            lanes[col] += 1
            local icon = core[key]
            if n.effect.kind == "setTool" and catalog.byTab[n.effect.toolId] then
                icon = catalog.byTab[n.effect.toolId].icon
            end
            add(page, {
                id = n.id,
                name = n.name,
                description = n.description,
                requires = n.requires,
                cost = n.cost,
                kind = if n.granted
                    then "grant"
                    elseif n.effect.kind == "setTool" then "equipment"
                    else "upgrade",
                granted = n.granted,
                live = true,
                core = icon,
                effect = n.effect,
                x = if col == 1 then 245 else 737,
                y = 100 + (lanes[col] - 1) * 115,
            })
            tier(n.id, key .. "_lauf_" .. col)
        end
        local extras = support[key] or {}
        local span = if #extras == 6 then 3 else 4
        for i, n in extras do
            local isLeft = i <= span
            local row = if isLeft then i else i - span
            local center = i == #extras
            add(page, {
                id = n.id,
                name = n.name,
                description = n.description,
                requires = n.requires,
                cost = n.cost,
                kind = if center then "keystone" elseif row == 1 then "ability" else "modifier",
                core = core[key],
                x = if center then 660 elseif isLeft then 530 else 810,
                y = if center then 850 else 210 + (row - 1) * 150,
            })
            tier(n.id, key .. (if isLeft then "_links" else "_rechts"))
        end
        page.height = math.max(1010, lanes[1] * 115 + 100)
    end
    return catalog
end
return Catalog
