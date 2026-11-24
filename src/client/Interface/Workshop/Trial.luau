--!strict
local Trial = {}

local START_BUDGET = 100
local TEST_BUDGET = 1000000000
local MAX_SAFE_COINS = 9007199254740991

Trial.presets = {
    {
        id = "hand",
        name = "Mit der Hand starten",
        description = "Startausrüstung und 100 Testmünzen für die ersten Upgrades.",
    },
    {
        id = "snapshot",
        name = "Aktuellen Fortschritt kopieren",
        description = "Übernimmt gelernte Upgrades und das Münzguthaben aus dem aktuellen Lauf.",
    },
    {
        id = "all",
        name = "Alle Geräte testen",
        description = "Alle Geräte, die erste Sturmbelohnung und eine Milliarde Testmünzen.",
    },
}

export type Run = {
    preset: string,
    owned: { [string]: boolean },
    coins: number,
    variants: { [string]: string },
}

function Trial.start(
    preset: string,
    owned: { [string]: boolean },
    coins: number,
    gates: { string }
): Run
    local copy = if preset == "snapshot" then table.clone(owned) else {}
    local budget = START_BUDGET
    if preset == "all" then
        for _, gate in gates do
            if gate ~= "start" then
                copy[gate] = true
            end
        end
        copy.sandstorm_1 = true
        budget = TEST_BUDGET
    elseif preset == "snapshot" then
        budget = math.floor(math.clamp(coins, 0, MAX_SAFE_COINS))
    end
    return { preset = preset, owned = copy, coins = budget, variants = {} }
end

return Trial
