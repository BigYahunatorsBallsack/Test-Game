--!strict
local Art = require(script.Parent.Art)
local DeviceStats = require(script.Parent.DeviceStats)
local C = Art.c

local DeviceStatsView = {}

function DeviceStatsView.render(page, selected, owned, options)
    local caption = options.caption
    local groups, byTarget = DeviceStats.collect(page.nodes, owned)
    options.button("WerteZurueck", "Zurück zu den Details", options.back)
    caption("Wertetitel", "GERÄTEWERTE  ·  " .. page.name, 40, 18, C.bright, true)
    caption(
        "Wertequelle",
        if options.training
            then "Boni aus den gelernten Geräte-Upgrades im Probelauf."
            else "Die Geräteboni lassen sich im Probelauf testen.",
        42,
        12,
        C.mute,
        false
    )
    if not owned[selected.id] and selected.effect then
        local before, after = DeviceStats.projection(selected, byTarget)
        if before and after then
            local effect = selected.effect
            local absolute = effect.stat == "Abklingzeit" and effect.unit == "s"
            caption("Wertevorschau", "Mit " .. selected.name, 22, 12, C.leaf, true)
            caption(
                "Werteaenderung",
                effect.stat
                    .. "   "
                    .. DeviceStats.format(before, effect.unit, not absolute)
                    .. " → "
                    .. DeviceStats.format(after, effect.unit, not absolute),
                48,
                15,
                C.bright,
                true
            )
        end
    end
    for _, group in groups do
        local node = group.node
        if node then
            local state = options.status(node)
            if group.cooldown and owned[node.id] then
                state ..= "  ·  " .. DeviceStats.format(group.cooldown, "s") .. " Abklingzeit"
            end
            options.shortcut(node, "ZumWert_" .. node.id, node.name, state)
        else
            caption("PassiveWerte", "PASSIVE WERTE", 22, 12, C.leaf, true)
            if #group.values == 0 then
                caption(
                    "KeinePassivenWerte",
                    "Noch keine passiven Geräteknoten gelernt.",
                    40,
                    12,
                    C.mute,
                    false
                )
            end
        end
        for index, value in group.values do
            if not group.cooldown or value.stat ~= "Abklingzeit" or value.unit ~= "s" then
                caption(
                    "Bonus_" .. (if node then node.id else "passive") .. "_" .. index,
                    value.stat .. "   " .. DeviceStats.format(value.total, value.unit, true),
                    30,
                    13,
                    C.ivory,
                    false
                )
            end
        end
    end
end

return DeviceStatsView
