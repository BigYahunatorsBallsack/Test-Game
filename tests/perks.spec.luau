--!strict
-- Paket 4.4: Wirkungen der Gamepasses und des Münz-Boosts (Logic/Perks) und ihre Wirkung auf Sammeln,
-- Tank, Verkauf und Sandsturm (Collecting, Sandstorm). Dazu die Auto-Dig-Entscheidung und eine
-- Takt-Simulation mit Perks.collectTick, genau dem Schritt, den der Sand-Service alle 0,25 s aufruft.

local T = require("./lib/expect")
local Perks = require("../src/shared/Logic/Perks")
local Collecting = require("../src/shared/Logic/Collecting")
local Sandstorm = require("../src/shared/Logic/Sandstorm")
local Profile = require("../src/shared/Logic/Profile")
local BigNum = require("../src/shared/Logic/BigNum")
local Economy = require("../src/shared/Data/Economy")
local SandTypes = require("../src/shared/Data/SandTypes")

local NOW = 1_700_000_000
local TICK = 0.25 -- Takt des Sand-Service
local BOOST = Economy.coinBoost.durationSeconds
local DOUBLE = Economy.doubleCoinsMultiplier
local BIG_TANK = Economy.bigTankMultiplier

local function deepCopy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in value do
        copy[key] = deepCopy(inner)
    end
    return copy
end

local function tankOf(profile: any): number
    return BigNum.toNumber(BigNum.deserialize(profile.tank))
end

local function num(value: any): number
    return BigNum.toNumber(BigNum.deserialize(value))
end

local function withPasses(passes: { [string]: boolean }): any
    local profile: any = Profile.default(NOW)
    profile.passes = passes
    return profile
end

-- Ein Profil mit allem, was den Preis krumm macht: Verkauf-Ast, Windkristalle, gemischter Tank und
-- Sand ohne Mix-Eintrag.
local function richProfile(): any
    local profile: any = Profile.default(NOW)
    profile.nodes = { sell_1 = true, tank_1 = true, collect_tool_2 = true, collect_tool_3 = true }
    profile.windCrystals = 7
    profile.zones = { dunes = true, oasis = true }
    profile.currentZone = "oasis"
    Collecting.addSand(profile, 9, "yellow")
    Collecting.addSand(profile, 7, "red")
    Collecting.addSand(profile, 3, "black")
    -- 4 Sand ohne Mix-Eintrag (alte Daten): zählt zum billigsten Preis
    profile.tank = BigNum.serialize(BigNum.add(BigNum.deserialize(profile.tank), BigNum.new(4)))
    profile.runEarned = BigNum.serialize(BigNum.new(3, 8))
    return profile
end

T.describe("Faktoren ohne Pässe und Boost (4.4)", function()
    T.it("ohne Pässe und Boost sind Tank-Faktor und Münz-Faktor genau 1", function()
        local profile = Profile.default(NOW)
        T.expect(Perks.options(profile, NOW)).toEqual({ capacityMultiplier = 1, coinMultiplier = 1 })
        T.expect(Perks.coinMultiplier(profile, NOW)).toBe(1)
        T.expect(Perks.capacityMultiplier(profile)).toBe(1)
        T.expect(Perks.coinBoostSeconds(profile, NOW)).toBe(0)
        for _, perk in Perks.PERK_IDS do
            T.expect(Perks.owns(profile, perk)).toBe(false)
        end
    end)

    T.it("Rechnungen mit diesen Options sind genau wie ohne Options (wie vor 4.4)", function()
        local base = richProfile()
        local options = Perks.options(base, NOW)
        T.expect(Collecting.pricePerSand(base, options)).toBe(Collecting.pricePerSand(base))
        for _, sandType in SandTypes.list do
            T.expect(Collecting.priceOf(base, sandType.id, options)).toBe(Collecting.priceOf(base, sandType.id))
        end
        T.expect(Collecting.tankValue(base, options)).toEqual(Collecting.tankValue(base))
        T.expect(Collecting.capacityOf(base, options)).toBe(Collecting.capacityOf(base))
        T.expect(Collecting.isFull(base, options)).toBe(Collecting.isFull(base))
        T.expect(Sandstorm.preview(base, nil, options)).toEqual(Sandstorm.preview(base))
        local a, b = deepCopy(base), deepCopy(base)
        local earnedA = Collecting.sell(Collecting.newState(NOW), a, NOW, options)
        local earnedB = Collecting.sell(Collecting.newState(NOW), b, NOW)
        T.expect(earnedA).toEqual(earnedB)
        T.expect(a).toEqual(b)
    end)

    T.it("kaputte Münz-Faktoren in den Options zählen als 1 (nie 0, negativ oder unendlich)", function()
        local profile = richProfile()
        local plain = Collecting.tankValue(profile)
        for _, bad in { 0 / 0, -2, 0, math.huge, -math.huge } do
            T.expect(Collecting.tankValue(profile, { coinMultiplier = bad })).toEqual(plain)
            T.expect(Collecting.pricePerSand(profile, { coinMultiplier = bad })).toBe(Collecting.pricePerSand(profile))
        end
        local weird: any = { coinMultiplier = "viel" }
        T.expect(Collecting.tankValue(profile, weird)).toEqual(plain)
    end)

    T.it("nur bekannte Pässe mit Wert true zählen", function()
        T.expect(Perks.owns(withPasses({ double_coins = "true" :: any }), "doubleCoins")).toBe(false)
        T.expect(Perks.owns(withPasses({ double_coins = false }), "doubleCoins")).toBe(false)
        T.expect(Perks.owns(withPasses({ gibt_es_nicht = true }), "doubleCoins")).toBe(false)
        T.expect(Perks.owns(withPasses({ starter_pack = true }), "doubleCoins")).toBe(false) -- kein Gamepass
        local broken: any = Profile.default(NOW)
        broken.passes = "kaputt"
        T.expect(Perks.options(broken, NOW)).toEqual({ capacityMultiplier = 1, coinMultiplier = 1 })
        T.expect(Perks.owns(withPasses({ double_coins = true }), "doubleCoins")).toBe(true)
    end)
end)

T.describe("Großer Tank (4.4)", function()
    T.it("capacityOf verdoppelt die Tankgröße (Economy.bigTankMultiplier), auch mit Tank-Knoten", function()
        local profile = withPasses({ big_tank = true })
        local options = Perks.options(profile, NOW)
        T.expect(options.capacityMultiplier).toBe(BIG_TANK)
        T.expect(Collecting.capacityOf(profile, options)).toBe(Economy.startTankCapacity * BIG_TANK)
        profile.nodes.tank_1 = true
        T.expect(Collecting.capacityOf(profile, options)).toBe(30 * BIG_TANK)
        T.expect(Collecting.capacityOf(profile)).toBe(30)
    end)

    T.it("Sammelstopp und Vollmeldung erst bei der verdoppelten Größe", function()
        local profile = withPasses({ big_tank = true })
        local options = Perks.options(profile, NOW)
        local state = Collecting.newState(NOW)
        local capacity = Economy.startTankCapacity * BIG_TANK
        local t = NOW
        Collecting.setHolding(state, profile, true, t, options)
        local fullAt: number? = nil
        for _ = 1, 200 do
            t += TICK
            local result = Collecting.update(state, profile, t, options)
            Collecting.setHolding(state, profile, true, t, options)
            if result.full then
                fullAt = tankOf(profile)
                break
            end
            -- Ohne Faktor wäre hier schon Schluss: Bei der Startgröße läuft es weiter.
            T.expect(state.holding).toBe(true)
        end
        T.expect(fullAt).toBe(capacity)
        T.expect(Collecting.isFull(profile, options)).toBe(true)
        T.expect(Collecting.isFull(profile)).toBe(true) -- über der Startgröße ist es ohne Faktor erst recht voll
        -- Mit vollem Tank beginnt kein Sammeln, setHolding meldet "voll".
        local again = Collecting.setHolding(state, profile, true, t + 1, options)
        T.expect(again.full).toBe(true)
        T.expect(state.holding).toBe(false)
        T.expect(tankOf(profile)).toBe(capacity)
    end)

    T.it("ohne Pass stoppt dasselbe Sammeln bei der Startgröße", function()
        local profile = Profile.default(NOW)
        local options = Perks.options(profile, NOW)
        local state = Collecting.newState(NOW)
        local t = NOW
        Collecting.setHolding(state, profile, true, t, options)
        for _ = 1, 200 do
            t += TICK
            local result = Collecting.update(state, profile, t, options)
            if result.full then
                break
            end
            Collecting.setHolding(state, profile, true, t, options)
        end
        T.expect(tankOf(profile)).toBe(Economy.startTankCapacity)
        T.expect(Collecting.space(profile, options)).toBe(0)
    end)

    T.it("kaputter Tank-Faktor (NaN, unendlich, 0, negativ, kein number) zählt als 1 (Security-Review 4.4)", function()
        local profile = Profile.default(NOW)
        local base = Collecting.capacityOf(profile)
        T.expect(base).toBe(Economy.startTankCapacity)
        local broken: { any } = { 0 / 0, math.huge, -math.huge, 0, -2, "2", true, {} }
        for _, value in broken do
            local options: any = { capacityMultiplier = value }
            T.expect(Collecting.capacityOf(profile, options)).toBe(base)
            T.expect(Collecting.space(profile, options)).toBe(base)
            T.expect(Collecting.isFull(profile, options)).toBe(false)
        end
        -- Ein voller Tank bleibt mit kaputtem Faktor voll (kein unendlicher Platz durch math.huge).
        Collecting.addSand(profile, base)
        T.expect(Collecting.isFull(profile, { capacityMultiplier = math.huge } :: any)).toBe(true)
        T.expect(Collecting.space(profile, { capacityMultiplier = math.huge } :: any)).toBe(0)
        -- Gültige Faktoren wirken weiter.
        T.expect(Collecting.capacityOf(profile, { capacityMultiplier = BIG_TANK })).toBe(base * BIG_TANK)
    end)
end)

T.describe("2x Münzen (4.4)", function()
    T.it("Preis pro Sand, Preis je Sorte, Tankwert, Verkauf und Sandsturm-Vorschau rechnen mit demselben Faktor", function()
        local plain = richProfile()
        local passed = richProfile()
        passed.passes = { double_coins = true }
        local options = Perks.options(passed, NOW)
        T.expect(options.coinMultiplier).toBe(DOUBLE)
        T.expect(options.capacityMultiplier).toBe(1)

        T.expect(Collecting.pricePerSand(passed, options)).toBeCloseTo(Collecting.pricePerSand(plain) * DOUBLE, 1e-9)
        for _, sandType in SandTypes.list do
            T.expect(Collecting.priceOf(passed, sandType.id, options)).toBeCloseTo(Collecting.priceOf(plain, sandType.id) * DOUBLE, 1e-9)
        end
        -- Tankwert: jede Sorte mit ihrem Preis mal Faktor, Sand ohne Mix zum billigsten Preis mal Faktor,
        -- abgerundet auf ganze Münzen (dieselbe Rechnung wie beim Verkauf).
        local expected = 0
        for typeId, amount in passed.tankMix do
            expected += num(amount) * Collecting.priceOf(passed, typeId, options)
        end
        expected += 4 * Collecting.priceOf(passed, "yellow", options)
        local value = BigNum.toNumber(Collecting.tankValue(passed, options))
        T.expect(value).toBe(math.floor(expected))
        T.expect(value > BigNum.toNumber(Collecting.tankValue(plain))).toBe(true)

        -- Sandsturm-Vorschau (Paket 6.4, L1): Einnahmen = runEarned + Tankwert OHNE Münz-Faktor.
        local plainValue = BigNum.toNumber(Collecting.tankValue(passed))
        local view = Sandstorm.preview(passed, nil, options)
        T.expect(num(view.runEarned)).toBe(3e8 + plainValue)
        T.expect(view.gain).toBe(Sandstorm.crystalsFor(BigNum.add(BigNum.new(3, 8), BigNum.new(plainValue))))

        -- Verkauf bucht den Tankwert mit Faktor auf die Münzen, aber nur den Wert ohne Faktor auf
        -- runEarned. Der Tank ist danach leer.
        local coinsBefore = num(passed.coins)
        local earned = Collecting.sell(Collecting.newState(NOW), passed, NOW, options)
        T.expect(earned ~= nil and BigNum.toNumber(earned)).toBe(value)
        T.expect(num(passed.coins)).toBe(coinsBefore + value)
        T.expect(num(passed.runEarned)).toBe(3e8 + plainValue)
        T.expect(tankOf(passed)).toBe(0)
    end)

    T.it("ein Tank nur aus Sand ohne Mix-Eintrag bekommt den Faktor auch", function()
        local profile = withPasses({ double_coins = true })
        profile.tank = BigNum.serialize(BigNum.new(10))
        local options = Perks.options(profile, NOW)
        T.expect(BigNum.toNumber(Collecting.tankValue(profile, options))).toBe(10 * Economy.baseCoinsPerSand * DOUBLE)
        T.expect(BigNum.toNumber(Collecting.tankValue(profile))).toBe(10 * Economy.baseCoinsPerSand)
    end)

    T.it("der Sandsturm gibt mit Options genau die Kristalle der Vorschau mit denselben Options", function()
        local data = { Economy = { sandstorm = { requiresNode = "collect_tool_2", crystalUnit = 1_000_000, crystalExponent = 0.5, crystalScale = 1, minCrystals = 1, maxCrystals = 100_000 } } }
        local profile = richProfile()
        profile.passes = { double_coins = true }
        profile.boosts = { coinsUntil = NOW + 60 }
        local options = Perks.options(profile, NOW)
        T.expect(options.coinMultiplier).toBe(DOUBLE * Economy.coinBoost.multiplier)
        local view = Sandstorm.preview(profile, data, options)
        local plainView = Sandstorm.preview(profile, data)
        -- L1: Pass und Boost ändern die Vorschau der Kristalle nicht.
        T.expect(view.runEarned).toEqual(plainView.runEarned)
        T.expect(view.gain).toBe(plainView.gain)
        local result = Sandstorm.apply(profile, data, options)
        T.expect(result ~= nil).toBe(true)
        if result then
            T.expect(result.crystals).toBe(view.gain)
        end
        -- Pässe, Einstellung und Boost bleiben beim Sturm.
        T.expect(profile.passes).toEqual({ double_coins = true })
        T.expect(profile.boosts).toEqual({ coinsUntil = NOW + 60 })
        T.expect(profile.settings).toEqual({ autoDig = true })
    end)
end)

T.describe("Münz-Boost (4.4)", function()
    T.it("wirkt nur vor coinsUntil (Server-Uhr), danach Faktor 1", function()
        local profile: any = Profile.default(NOW)
        profile.boosts = { coinsUntil = NOW + BOOST }
        T.expect(Perks.coinBoostActive(profile, NOW)).toBe(true)
        T.expect(Perks.coinMultiplier(profile, NOW)).toBe(Economy.coinBoost.multiplier)
        T.expect(Perks.coinMultiplier(profile, NOW + BOOST - 1)).toBe(Economy.coinBoost.multiplier)
        T.expect(Perks.coinMultiplier(profile, NOW + BOOST)).toBe(1)
        T.expect(Perks.coinMultiplier(profile, NOW + BOOST + 999)).toBe(1)
        T.expect(Perks.coinBoostSeconds(profile, NOW)).toBe(BOOST)
        T.expect(Perks.coinBoostSeconds(profile, NOW + 100)).toBe(BOOST - 100)
        T.expect(Perks.coinBoostSeconds(profile, NOW + BOOST + 5)).toBe(0)
        -- Der Preis folgt dem Faktor.
        local during = Collecting.pricePerSand(profile, Perks.options(profile, NOW))
        local after = Collecting.pricePerSand(profile, Perks.options(profile, NOW + BOOST))
        T.expect(during).toBe(after * Economy.coinBoost.multiplier)
    end)

    T.it("Pass und Boost zusammen: multiplikativ (2 x 2 = 4-fach, so entschieden)", function()
        local profile = withPasses({ double_coins = true })
        profile.boosts = { coinsUntil = NOW + 10 }
        T.expect(Perks.coinMultiplier(profile, NOW)).toBe(DOUBLE * Economy.coinBoost.multiplier)
        T.expect(Perks.coinMultiplier(profile, NOW)).toBe(4)
        T.expect(Perks.coinMultiplier(profile, NOW + 10)).toBe(DOUBLE)
    end)

    T.it("kaputte Werte (NaN, negativ, unendlich, kein number, keine Tabelle) zählen als abgelaufen", function()
        for _, bad in { 0 / 0, -5, math.huge, -math.huge, "bald", true } do
            local profile: any = Profile.default(NOW)
            profile.boosts = { coinsUntil = bad }
            T.expect(Perks.coinBoostActive(profile, NOW)).toBe(false)
            T.expect(Perks.coinBoostSeconds(profile, NOW)).toBe(0)
            T.expect(Perks.coinMultiplier(profile, NOW)).toBe(1)
        end
        local noTable: any = Profile.default(NOW)
        noTable.boosts = "kaputt"
        T.expect(Perks.coinBoostActive(noTable, NOW)).toBe(false)
        noTable.boosts = nil
        T.expect(Perks.coinBoostSeconds(noTable, NOW)).toBe(0)
        -- Eine kaputte Uhr schaltet den Boost nie ein.
        local running: any = Profile.default(NOW)
        running.boosts = { coinsUntil = NOW + 100 }
        T.expect(Perks.coinBoostActive(running, 0 / 0)).toBe(false)
    end)

    T.it("verlängern: abgelaufen ergibt jetzt + 30 min, laufend ergibt alte Endzeit + 30 min", function()
        T.expect(Perks.extendCoinBoost({ coinsUntil = 0 }, NOW, BOOST)).toEqual({ coinsUntil = NOW + BOOST })
        T.expect(Perks.extendCoinBoost({ coinsUntil = NOW - 50 }, NOW, BOOST)).toEqual({ coinsUntil = NOW + BOOST })
        T.expect(Perks.extendCoinBoost({ coinsUntil = NOW }, NOW, BOOST)).toEqual({ coinsUntil = NOW + BOOST })
        T.expect(Perks.extendCoinBoost({ coinsUntil = NOW + 600 }, NOW, BOOST)).toEqual({ coinsUntil = NOW + 600 + BOOST })
        T.expect(BOOST).toBe(30 * 60)
    end)

    T.it("verlängern: kaputte Werte zählen als abgelaufen, andere Felder bleiben, die alte Tabelle bleibt unverändert", function()
        for _, bad in { 0 / 0, -5, math.huge, -math.huge, "bald" } do
            T.expect(Perks.extendCoinBoost({ coinsUntil = bad }, NOW, BOOST)).toEqual({ coinsUntil = NOW + BOOST })
        end
        T.expect(Perks.extendCoinBoost(nil, NOW, BOOST)).toEqual({ coinsUntil = NOW + BOOST })
        T.expect(Perks.extendCoinBoost("kaputt", NOW, BOOST)).toEqual({ coinsUntil = NOW + BOOST })
        local old = { coinsUntil = NOW + 5, luckUntil = 77 }
        local extended = Perks.extendCoinBoost(old, NOW, BOOST)
        T.expect(extended).toEqual({ coinsUntil = NOW + 5 + BOOST, luckUntil = 77 })
        T.expect(old).toEqual({ coinsUntil = NOW + 5, luckUntil = 77 })
        T.expect(extended ~= old).toBe(true)
    end)

    T.it("verlängern: kaputte Uhr oder Dauer bucht nichts (nil), Stapeln bleibt endlich", function()
        T.expect(Perks.extendCoinBoost({ coinsUntil = 0 }, 0 / 0, BOOST)).toBeNil()
        T.expect(Perks.extendCoinBoost({ coinsUntil = 0 }, -1, BOOST)).toBeNil()
        T.expect(Perks.extendCoinBoost({ coinsUntil = 0 }, NOW, 0)).toBeNil()
        T.expect(Perks.extendCoinBoost({ coinsUntil = 0 }, NOW, -BOOST)).toBeNil()
        T.expect(Perks.extendCoinBoost({ coinsUntil = 0 }, NOW, math.huge)).toBeNil()
        local boosts: any = { coinsUntil = 0 }
        for _ = 1, 1000 do
            boosts = Perks.extendCoinBoost(boosts, NOW, BOOST)
        end
        T.expect(boosts.coinsUntil).toBe(NOW + 1000 * BOOST) -- keine Obergrenze, aber endlich
    end)
end)

T.describe("Glücks-Boost (5.1)", function()
    local LUCK = Economy.luckBoost.multiplier
    local SECONDS = 15 * 60

    T.it("wirkt nur vor luckUntil (Server-Uhr), danach Faktor 1; Restsekunden für die Anzeige", function()
        local profile: any = Profile.default(NOW)
        T.expect(Perks.luckBoostActive(profile, NOW)).toBe(false)
        T.expect(Perks.luckBoostMultiplier(profile, NOW)).toBe(1)
        T.expect(Perks.luckBoostSeconds(profile, NOW)).toBe(0)
        profile.boosts = { coinsUntil = 0, luckUntil = NOW + SECONDS }
        T.expect(Perks.luckBoostActive(profile, NOW)).toBe(true)
        T.expect(Perks.luckBoostMultiplier(profile, NOW)).toBe(LUCK)
        T.expect(LUCK).toBe(2)
        T.expect(Perks.luckBoostMultiplier(profile, NOW + SECONDS - 1)).toBe(LUCK)
        T.expect(Perks.luckBoostMultiplier(profile, NOW + SECONDS)).toBe(1)
        T.expect(Perks.luckBoostSeconds(profile, NOW)).toBe(SECONDS)
        T.expect(Perks.luckBoostSeconds(profile, NOW + 100)).toBe(SECONDS - 100)
        T.expect(Perks.luckBoostSeconds(profile, NOW + SECONDS + 5)).toBe(0)
    end)

    T.it("Münz- und Glücks-Boost sind getrennt: keiner schaltet den anderen ein", function()
        local luckOnly: any = Profile.default(NOW)
        luckOnly.boosts = { coinsUntil = 0, luckUntil = NOW + 60 }
        T.expect(Perks.coinBoostActive(luckOnly, NOW)).toBe(false)
        T.expect(Perks.coinMultiplier(luckOnly, NOW)).toBe(1)
        T.expect(Perks.options(luckOnly, NOW)).toEqual({ capacityMultiplier = 1, coinMultiplier = 1 })
        local coinsOnly: any = Profile.default(NOW)
        coinsOnly.boosts = { coinsUntil = NOW + 60, luckUntil = 0 }
        T.expect(Perks.luckBoostActive(coinsOnly, NOW)).toBe(false)
        T.expect(Perks.luckBoostMultiplier(coinsOnly, NOW)).toBe(1)
    end)

    T.it("Faktor aus den Daten; kaputt oder unter 1 zählt als 1", function()
        local profile: any = Profile.default(NOW)
        profile.boosts = { coinsUntil = 0, luckUntil = NOW + 60 }
        T.expect(Perks.luckBoostMultiplier(profile, NOW, { Economy = { luckBoost = { multiplier = 3 } } })).toBe(3)
        for _, bad in { 0.5, 0 / 0, math.huge, "2" } do
            T.expect(Perks.luckBoostMultiplier(profile, NOW, { Economy = { luckBoost = { multiplier = bad } } })).toBe(1)
        end
        T.expect(Perks.luckBoostMultiplier(profile, NOW, { Economy = {} })).toBe(1)
    end)

    T.it("kaputte Endzeit oder Uhr zählt als abgelaufen", function()
        for _, bad in { 0 / 0, -5, math.huge, -math.huge, "bald", true } do
            local profile: any = Profile.default(NOW)
            profile.boosts = { coinsUntil = 0, luckUntil = bad }
            T.expect(Perks.luckBoostActive(profile, NOW)).toBe(false)
            T.expect(Perks.luckBoostSeconds(profile, NOW)).toBe(0)
            T.expect(Perks.luckBoostMultiplier(profile, NOW)).toBe(1)
        end
        local running: any = Profile.default(NOW)
        running.boosts = { coinsUntil = 0, luckUntil = NOW + 100 }
        T.expect(Perks.luckBoostActive(running, 0 / 0)).toBe(false)
        running.boosts = "kaputt"
        T.expect(Perks.luckBoostActive(running, NOW)).toBe(false)
    end)

    T.it("verlängern: ab der alten Endzeit oder ab jetzt, coinsUntil bleibt, die alte Tabelle bleibt unverändert", function()
        T.expect(Perks.extendLuckBoost({ coinsUntil = 5, luckUntil = 0 }, NOW, SECONDS)).toEqual({ coinsUntil = 5, luckUntil = NOW + SECONDS })
        T.expect(Perks.extendLuckBoost({ coinsUntil = 5, luckUntil = NOW - 1 }, NOW, SECONDS)).toEqual({ coinsUntil = 5, luckUntil = NOW + SECONDS })
        T.expect(Perks.extendLuckBoost({ coinsUntil = 5, luckUntil = NOW + 60 }, NOW, SECONDS)).toEqual({ coinsUntil = 5, luckUntil = NOW + 60 + SECONDS })
        T.expect(Perks.extendLuckBoost({ coinsUntil = 5 }, NOW, SECONDS)).toEqual({ coinsUntil = 5, luckUntil = NOW + SECONDS })
        T.expect(Perks.extendLuckBoost(nil, NOW, SECONDS)).toEqual({ luckUntil = NOW + SECONDS })
        local old = { coinsUntil = NOW + 7, luckUntil = 0 / 0 }
        local extended: any = Perks.extendLuckBoost(old, NOW, SECONDS)
        T.expect(extended.luckUntil).toBe(NOW + SECONDS)
        T.expect(extended.coinsUntil).toBe(NOW + 7)
        T.expect(old.luckUntil ~= old.luckUntil).toBe(true) -- alte Tabelle unverändert (NaN)
        -- Der Münz-Boost lässt luckUntil stehen.
        T.expect(Perks.extendCoinBoost({ coinsUntil = 0, luckUntil = NOW + 9 }, NOW, 60)).toEqual({ coinsUntil = NOW + 60, luckUntil = NOW + 9 })
    end)

    T.it("verlängern: kaputte Uhr oder Dauer gibt nil", function()
        T.expect(Perks.extendLuckBoost({ luckUntil = 0 }, 0 / 0, SECONDS)).toBeNil()
        T.expect(Perks.extendLuckBoost({ luckUntil = 0 }, -1, SECONDS)).toBeNil()
        T.expect(Perks.extendLuckBoost({ luckUntil = 0 }, NOW, 0)).toBeNil()
        T.expect(Perks.extendLuckBoost({ luckUntil = 0 }, NOW, -SECONDS)).toBeNil()
        T.expect(Perks.extendLuckBoost({ luckUntil = 0 }, NOW, math.huge)).toBeNil()
    end)
end)

T.describe("Auto-Dig: Einstellung und Entscheidung (4.4)", function()
    T.it("aktiv nur mit Pass und Einstellung an; ohne Pass ändert die Einstellung nichts", function()
        T.expect(Perks.autoDigActive(Profile.default(NOW))).toBe(false)
        local owner = withPasses({ auto_dig = true })
        T.expect(Perks.autoDigActive(owner)).toBe(true)
        owner.settings = Perks.withAutoDig(owner.settings, false)
        T.expect(Perks.autoDigActive(owner)).toBe(false)
        T.expect(Perks.autoDigSetting(owner)).toBe(false)
        local other = withPasses({ double_coins = true, big_tank = true })
        T.expect(Perks.autoDigActive(other)).toBe(false)
        -- Kaputte oder fehlende Einstellung: Standard (an).
        local broken = withPasses({ auto_dig = true })
        broken.settings = { autoDig = "ja" }
        T.expect(Perks.autoDigSetting(broken)).toBe(Perks.AUTO_DIG_DEFAULT)
        broken.settings = nil
        T.expect(Perks.autoDigActive(broken)).toBe(Perks.AUTO_DIG_DEFAULT)
    end)

    T.it("withAutoDig gibt eine neue Tabelle, andere Einstellungen bleiben", function()
        local old = { autoDig = true, music = false }
        local new = Perks.withAutoDig(old, false)
        T.expect(new).toEqual({ autoDig = false, music = false })
        T.expect(old.autoDig).toBe(true)
        T.expect(Perks.withAutoDig(nil, true)).toEqual({ autoDig = true })
    end)

    T.it("ein Loslassen der Taste stoppt Auto-Dig nicht", function()
        T.expect(Perks.wantsCollecting(false, true)).toBe(true)
        T.expect(Perks.wantsCollecting(true, false)).toBe(true)
        T.expect(Perks.wantsCollecting(false, false)).toBe(false)
    end)

    T.it("autoDigStep: halten, stoppen und 'voll' nur beim Übergang", function()
        local function step(active: boolean, wasActive: boolean, canCollect: boolean, full: boolean, noticed: boolean): Perks.AutoDigDecision
            return Perks.autoDigStep({ active = active, wasActive = wasActive, canCollect = canCollect, full = full, fullNoticed = noticed })
        end
        T.expect(step(false, false, true, false, false)).toEqual({ hold = false, stop = false, notifyFull = false, fullNoticed = false })
        T.expect(step(false, true, true, false, false)).toEqual({ hold = false, stop = true, notifyFull = false, fullNoticed = false })
        T.expect(step(true, true, true, false, false)).toEqual({ hold = true, stop = false, notifyFull = false, fullNoticed = false })
        T.expect(step(true, true, false, false, false)).toEqual({ hold = false, stop = false, notifyFull = false, fullNoticed = false })
        T.expect(step(true, true, true, true, false)).toEqual({ hold = false, stop = false, notifyFull = true, fullNoticed = true })
        T.expect(step(true, true, true, true, true)).toEqual({ hold = false, stop = false, notifyFull = false, fullNoticed = true })
        -- Voll, aber tot oder am Stand: keine Meldung (sie kommt, sobald er wieder sammeln könnte).
        T.expect(step(true, true, false, true, false)).toEqual({ hold = false, stop = false, notifyFull = false, fullNoticed = false })
        -- Nach dem Verkauf ist wieder Platz: der Merker fällt, es wird wieder gehalten.
        T.expect(step(true, true, true, false, true)).toEqual({ hold = true, stop = false, notifyFull = false, fullNoticed = false })
    end)
end)

-- Takt-Simulation: genau der Schritt des Sand-Service (Perks.collectTick) alle 0,25 s, ohne Eingabe vom
-- Client. `world` steuert, ob der Spieler sammeln darf (lebt, nicht am Stand).
type Sim = { profile: any, state: Collecting.State, memory: Perks.AutoDigMemory?, t: number, notices: number, canCollect: boolean }

local function newSim(profile: any): Sim
    return { profile = profile, state = Collecting.newState(NOW), memory = nil, t = NOW, notices = 0, canCollect = true }
end

local function run(sim: Sim, seconds: number)
    local steps = math.floor(seconds / TICK + 0.5)
    for _ = 1, steps do
        sim.t += TICK
        local options = Perks.options(sim.profile, NOW)
        local result = Perks.collectTick(sim.state, sim.profile, sim.t, options, sim.canCollect, sim.memory)
        sim.memory = result.memory
        if result.notifyFull then
            sim.notices += 1
        end
    end
end

T.describe("Auto-Dig: Takt-Simulation mit collectTick (4.4)", function()
    T.it("sammelt ohne Taste, stoppt bei vollem Tank mit genau einer Meldung, läuft nach dem Verkauf weiter", function()
        local sim = newSim(withPasses({ auto_dig = true }))
        local capacity = Collecting.capacityOf(sim.profile)
        run(sim, 3)
        T.expect(tankOf(sim.profile) > 0).toBe(true)
        T.expect(sim.state.holding).toBe(true)
        -- Weit über die Frist holdTimeoutSeconds hinaus: Auto-Dig erneuert sie jeden Takt.
        run(sim, 60)
        T.expect(tankOf(sim.profile)).toBe(capacity)
        T.expect(sim.state.holding).toBe(false)
        T.expect(sim.notices).toBe(1)
        -- Voll bleibt voll: keine weitere Meldung pro Takt.
        run(sim, 30)
        T.expect(sim.notices).toBe(1)
        T.expect(tankOf(sim.profile)).toBe(capacity)
        -- Verkaufen (am Stand: sammeln geht dort nicht), danach weg vom Stand: es läuft von selbst weiter.
        sim.canCollect = false
        run(sim, 1)
        T.expect(Collecting.sell(sim.state, sim.profile, sim.t, Perks.options(sim.profile, NOW)) ~= nil).toBe(true)
        run(sim, 1)
        T.expect(tankOf(sim.profile)).toBe(0)
        T.expect(sim.state.holding).toBe(false)
        sim.canCollect = true
        run(sim, 3)
        T.expect(tankOf(sim.profile) > 0).toBe(true)
        T.expect(sim.state.holding).toBe(true)
        -- Die nächste Füllung meldet wieder genau einmal.
        run(sim, 60)
        T.expect(sim.notices).toBe(2)
    end)

    T.it("mit 'Großer Tank' füllt Auto-Dig bis zur verdoppelten Größe", function()
        local sim = newSim(withPasses({ auto_dig = true, big_tank = true }))
        run(sim, 120)
        T.expect(tankOf(sim.profile)).toBe(Economy.startTankCapacity * BIG_TANK)
        T.expect(sim.notices).toBe(1)
    end)

    T.it("ohne Pass oder mit Schalter aus wird ohne Taste nichts gesammelt", function()
        local noPass = newSim(Profile.default(NOW))
        run(noPass, 30)
        T.expect(tankOf(noPass.profile)).toBe(0)
        T.expect(noPass.memory).toBeNil()
        T.expect(noPass.notices).toBe(0)
        local off = newSim(withPasses({ auto_dig = true }))
        off.profile.settings = Perks.withAutoDig(off.profile.settings, false)
        run(off, 30)
        T.expect(tankOf(off.profile)).toBe(0)
        T.expect(off.state.holding).toBe(false)
        -- Nur die Einstellung ohne Pass (Remote SetAutoDig): weiterhin nichts.
        local settingOnly = newSim(Profile.default(NOW))
        settingOnly.profile.settings = Perks.withAutoDig(settingOnly.profile.settings, true)
        run(settingOnly, 30)
        T.expect(tankOf(settingOnly.profile)).toBe(0)
    end)

    T.it("ohne Pass verhält sich der Takt wie vor 4.4: Halten endet nach der Frist", function()
        local sim = newSim(Profile.default(NOW))
        Collecting.setHolding(sim.state, sim.profile, true, sim.t)
        run(sim, 10)
        -- Die Hand sammelt 1 Sand/s, die Frist ist holdTimeoutSeconds: danach kommt nichts mehr dazu.
        T.expect(tankOf(sim.profile)).toBe(math.floor(Economy.collecting.holdTimeoutSeconds * Collecting.rateOf(sim.profile)))
        T.expect(sim.state.holding).toBe(false)
    end)

    T.it("tot oder am Stand: kein Sammeln; danach geht es weiter", function()
        local sim = newSim(withPasses({ auto_dig = true }))
        sim.canCollect = false
        run(sim, 5)
        T.expect(tankOf(sim.profile)).toBe(0)
        T.expect(sim.state.holding).toBe(false)
        sim.canCollect = true
        run(sim, 2)
        T.expect(tankOf(sim.profile) > 0).toBe(true)
    end)

    T.it("Schalter aus mitten im Sammeln: sofort Schluss, kein weiterer Sand", function()
        local sim = newSim(withPasses({ auto_dig = true }))
        run(sim, 3)
        T.expect(sim.state.holding).toBe(true)
        sim.profile.settings = Perks.withAutoDig(sim.profile.settings, false)
        run(sim, TICK)
        T.expect(sim.state.holding).toBe(false)
        T.expect(sim.memory).toBeNil()
        local tank = tankOf(sim.profile)
        run(sim, 10)
        T.expect(tankOf(sim.profile)).toBe(tank)
        -- Auch wenn der Pass wegfällt (Rückerstattung), endet das Sammeln sofort.
        local refunded = newSim(withPasses({ auto_dig = true }))
        run(refunded, 3)
        refunded.profile.passes = {}
        run(refunded, TICK)
        T.expect(refunded.state.holding).toBe(false)
    end)

    T.it("ein Bruchteil im Tank knapp unter der Grenze löst keine Meldung pro Takt aus", function()
        local sim = newSim(withPasses({ auto_dig = true }))
        sim.profile.tank = BigNum.serialize(BigNum.new(Economy.startTankCapacity - 0.5))
        run(sim, 10)
        T.expect(sim.notices).toBe(1)
        T.expect(sim.state.holding).toBe(false)
    end)

    T.it("der Tank füllt sich als Ganzes: kein Sand über der Tankgröße, nur ganze Körner", function()
        local sim = newSim(withPasses({ auto_dig = true }))
        sim.profile.nodes.collect_tool_2 = true -- 5 Sand/s
        run(sim, 100)
        T.expect(tankOf(sim.profile)).toBe(Collecting.capacityOf(sim.profile))
        T.expect(tankOf(sim.profile) % 1).toBe(0)
    end)
end)

T.finish()
