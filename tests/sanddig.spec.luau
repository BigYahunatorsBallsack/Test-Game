--!strict
-- Paket 1.4: Terrain-Verformung (reine Logik). Eine Fake-Welt ersetzt das Roblox-Terrain:
-- flacher Sand bis SURFACE, darunter voll, darüber Luft. Lesen und Schreiben kopieren Raster
-- wie Terrain:ReadVoxels/WriteVoxels.

local T = require("./lib/expect")
local SandDig = require("../src/shared/Logic/SandDig")
local Terrain = require("../src/shared/Data/Terrain")

local AIR = "Air"
local SAND = "Sand"
local ROCK = "Rock"
local DIGGABLE = { [SAND] = true }
local SURFACE = 8
local VS = Terrain.voxelSize
local CS = Terrain.chunkSize
local N = CS // VS

local function copyGrid(grid: any): any
    local occ, mat = {}, {}
    for x = 1, grid.n do
        occ[x], mat[x] = {}, {}
        for y = 1, grid.n do
            occ[x][y], mat[x][y] = {}, {}
            for z = 1, grid.n do
                occ[x][y][z] = grid.occ[x][y][z]
                mat[x][y][z] = grid.mat[x][y][z]
            end
        end
    end
    return { origin = grid.origin, n = grid.n, voxelSize = grid.voxelSize, occ = occ, mat = mat }
end

-- Raster eines Blocks mit flacher Oberfläche auf Höhe `surface`.
local function pristine(cx: number, cy: number, cz: number, surface: number?): any
    local top = surface or SURFACE
    local origin = { x = cx * CS, y = cy * CS, z = cz * CS }
    local occ, mat = {}, {}
    for x = 1, N do
        occ[x], mat[x] = {}, {}
        for y = 1, N do
            occ[x][y], mat[x][y] = {}, {}
            local y0 = origin.y + (y - 1) * VS
            local fill = math.clamp((top - y0) / VS, 0, 1)
            for z = 1, N do
                occ[x][y][z] = fill
                mat[x][y][z] = if fill > 0 then SAND else AIR
            end
        end
    end
    return { origin = origin, n = N, voxelSize = VS, occ = occ, mat = mat }
end

-- Fake-Welt mit Client-Ablauf wie im Controller Dig.
local function newWorld()
    local world = { chunks = {} :: { [string]: any }, baselines = {} :: { [string]: any } }
    local function chunk(cx: number, cy: number, cz: number): any
        local key = SandDig.chunkKey(cx, cy, cz)
        if world.chunks[key] == nil then
            world.chunks[key] = pristine(cx, cy, cz)
        end
        return world.chunks[key]
    end
    function world.read(cx: number, cy: number, cz: number): any
        return copyGrid(chunk(cx, cy, cz))
    end
    function world.write(cx: number, cy: number, cz: number, grid: any)
        world.chunks[SandDig.chunkKey(cx, cy, cz)] = copyGrid(grid)
    end
    -- Oberfläche (Strahl nach unten) an x, z.
    function world.surfaceAt(x: number, z: number): number
        local cx, cz = math.floor(x / CS), math.floor(z / CS)
        local ix = math.floor((x - cx * CS) / VS) + 1
        local iz = math.floor((z - cz * CS) / VS) + 1
        for cy = 3, -3, -1 do
            local grid = chunk(cx, cy, cz)
            for iy = N, 1, -1 do
                local occ = grid.occ[ix][iy][iz]
                if occ > 0 then
                    return grid.origin.y + (iy - 1) * VS + occ * VS
                end
            end
        end
        return -math.huge
    end
    function world.dig(state: any, now: number, x: number, z: number, toolId: string?): (any, string?)
        local hit = { x = x, y = world.surfaceAt(x, z), z = z }
        local result, reason = SandDig.tryDig(state, now, hit, toolId)
        if result == nil then
            return nil, reason
        end
        for _, ref in result.chunks do
            if ref.isNew then
                world.baselines[ref.key] = world.read(ref.cx, ref.cy, ref.cz)
            end
            local grid = world.read(ref.cx, ref.cy, ref.cz)
            if SandDig.carve(grid, result.center, result.radius, result.floorY, AIR, DIGGABLE) then
                world.write(ref.cx, ref.cy, ref.cz, grid)
            elseif ref.isNew then
                SandDig.forget(state, ref.key)
                world.baselines[ref.key] = nil
            end
        end
        return result, nil
    end
    function world.update(state: any, now: number, playerPos: any?): { any }
        local actions = SandDig.update(state, now, playerPos)
        for _, action in actions do
            local baseline = world.baselines[action.key]
            assert(baseline ~= nil, "Aktion ohne Original")
            local grid = world.read(action.cx, action.cy, action.cz)
            SandDig.blend(grid, baseline, action.t, AIR)
            world.write(action.cx, action.cy, action.cz, grid)
            if action.final then
                world.baselines[action.key] = nil
            end
        end
        return actions
    end
    -- Ist jeder Block wieder im Originalzustand?
    function world.allPristine(): boolean
        for key, grid in world.chunks do
            local cx, cy, cz = string.match(key, "^(-?%d+),(-?%d+),(-?%d+)$")
            local ref = pristine(tonumber(cx) :: number, tonumber(cy) :: number, tonumber(cz) :: number)
            for x = 1, N do
                for y = 1, N do
                    for z = 1, N do
                        if math.abs(grid.occ[x][y][z] - ref.occ[x][y][z]) > 1e-9 or grid.mat[x][y][z] ~= ref.mat[x][y][z] then
                            return false
                        end
                    end
                end
            end
        end
        return true
    end
    return world
end

local function sortedChunks(list: { { number } }): { string }
    local keys = {}
    for _, c in list do
        table.insert(keys, SandDig.chunkKey(c[1], c[2], c[3]))
    end
    table.sort(keys)
    return keys
end

local delay = Terrain.regrow.delaySeconds
local regrowSeconds = Terrain.regrow.seconds
local interval = Terrain.dig.intervalSeconds

T.describe("Blöcke eines Lochs", function()
    T.it("eine Kugel liefert genau die geschnittenen Blöcke", function()
        T.expect(sortedChunks(SandDig.chunksForSphere({ x = 8, y = 8, z = 8 }, 2, 16))).toEqual({ "0,0,0" })
        T.expect(sortedChunks(SandDig.chunksForSphere({ x = 15, y = 8, z = 8 }, 2, 16))).toEqual({ "0,0,0", "1,0,0" })
        -- Ecke (16,16,16) ist sqrt(12) > 3 entfernt: Block 1,1,1 gehört nicht dazu.
        local corner = SandDig.chunksForSphere({ x = 14, y = 14, z = 14 }, 3, 16)
        T.expect(#corner).toBe(7)
        T.expect(table.find(sortedChunks(corner), "1,1,1")).toBeNil()
    end)

    T.it("negative Koordinaten und Blockgrenzen", function()
        T.expect(sortedChunks(SandDig.chunksForSphere({ x = -1, y = -1, z = -1 }, 0.5, 16))).toEqual({ "-1,-1,-1" })
        T.expect(#SandDig.chunksForSphere({ x = 0, y = 0, z = 0 }, 1, 16)).toBe(8)
        T.expect(sortedChunks(SandDig.chunksForSphere({ x = -16, y = 4, z = 4 }, 1, 16))).toEqual({ "-1,0,0", "-2,0,0" })
    end)
end)

T.describe("Aushöhlen", function()
    T.it("leert Voxel in der Kugel und lässt den Rest unverändert", function()
        local grid = pristine(0, 0, 0, 8)
        local changed = SandDig.carve(grid, { x = 8, y = 10, z = 8 }, 3, -100, AIR, DIGGABLE)
        T.expect(changed).toBe(true)
        -- Säule neben der Mitte (Mitte 6/6 bzw. 10/10) wurde abgesenkt, Ecke (2/2) nicht.
        T.expect(grid.occ[2][2][2] < 1).toBe(true)
        T.expect(grid.occ[3][2][3] < 1).toBe(true)
        T.expect(grid.occ[1][2][1]).toBe(1)
        T.expect(grid.occ[4][2][4]).toBe(1)
        -- Unterste Schicht liegt unter der Kugel.
        T.expect(grid.occ[2][1][2]).toBe(1)
        for x = 1, N do
            for y = 1, N do
                for z = 1, N do
                    T.expect(grid.occ[x][y][z] >= 0).toBe(true)
                end
            end
        end
    end)

    T.it("ein leerer Voxel wird zu Luft, Fels bleibt", function()
        local grid = pristine(0, 0, 0, 8)
        grid.mat[3][1][3] = ROCK
        SandDig.carve(grid, { x = 8, y = 8, z = 8 }, 30, -100, AIR, DIGGABLE)
        T.expect(grid.occ[2][2][2]).toBe(0)
        T.expect(grid.mat[2][2][2]).toBe(AIR)
        T.expect(grid.occ[3][1][3]).toBe(1)
        T.expect(grid.mat[3][1][3]).toBe(ROCK)
    end)

    T.it("Luft bleibt unverändert und meldet keine Änderung", function()
        local grid = pristine(0, 2, 0, 8) -- ganz über der Oberfläche
        T.expect(SandDig.carve(grid, { x = 8, y = 40, z = 8 }, 5, -100, AIR, DIGGABLE)).toBe(false)
    end)
end)

T.describe("Tiefengrenze und Takt", function()
    T.it("wiederholtes Graben wird tiefer, aber nie tiefer als maxDepthStuds", function()
        local world = newWorld()
        local state = SandDig.new(Terrain)
        local floorY = SURFACE - Terrain.dig.maxDepthStuds
        local t = 0
        local first = world.surfaceAt(9, 9)
        local reason: string? = nil
        for _ = 1, 200 do
            t += 1
            local result, why = world.dig(state, t, 9, 9, "hand")
            if result == nil then
                reason = why
                break
            end
            T.expect(result.floorY).toBe(floorY)
        end
        T.expect(reason).toBe("tooDeep")
        local final = world.surfaceAt(9, 9)
        T.expect(final < first - 1).toBe(true)
        -- Keine Säule in der Welt liegt unter der Grenze.
        for x = -12, 28, 4 do
            for z = -12, 28, 4 do
                T.expect(world.surfaceAt(x + 1, z + 1) >= floorY - 1e-9).toBe(true)
            end
        end
    end)

    T.it("ein Treffer an der Grenze gräbt nicht", function()
        local state = SandDig.new(Terrain)
        T.expect(SandDig.tryDig(state, 0, { x = 8, y = 8, z = 8 }, "hand") ~= nil).toBe(true)
        local result, reason = SandDig.tryDig(state, 1, { x = 8, y = 8 - Terrain.dig.maxDepthStuds + 0.1, z = 8 }, "hand")
        T.expect(result).toBeNil()
        T.expect(reason).toBe("tooDeep")
    end)

    T.it("ein zweites Loch innerhalb des Takts wird abgelehnt", function()
        local state = SandDig.new(Terrain)
        local hit = { x = 8, y = 8, z = 8 }
        T.expect(SandDig.tryDig(state, 10, hit, "hand") ~= nil).toBe(true)
        local result, reason = SandDig.tryDig(state, 10 + interval / 2, hit, "hand")
        T.expect(result).toBeNil()
        T.expect(reason).toBe("interval")
        T.expect(SandDig.tryDig(state, 10 + interval, hit, "hand") ~= nil).toBe(true)
        -- Die Rückfallvariante nutzt denselben Takt.
        T.expect(SandDig.takeDigSlot(state, 10 + interval * 1.5)).toBe(false)
        T.expect(SandDig.takeDigSlot(state, 10 + interval * 2)).toBe(true)
    end)

    T.it("Lochgröße folgt dem Werkzeug, unbekannt gräbt wie die Hand", function()
        T.expect(SandDig.holeFor(Terrain, "hand")).toBe(Terrain.holeByTool.hand)
        T.expect(SandDig.holeFor(Terrain, "mega_machine").radius > SandDig.holeFor(Terrain, "hand").radius).toBe(true)
        T.expect(SandDig.holeFor(Terrain, "bagger_9000")).toBe(Terrain.holeByTool.hand)
        T.expect(SandDig.holeFor(Terrain, nil)).toBe(Terrain.holeByTool.hand)
        local state = SandDig.new(Terrain)
        local small = SandDig.tryDig(state, 0, { x = 8, y = 8, z = 8 }, "hand")
        local big = SandDig.tryDig(state, 1, { x = 200, y = 8, z = 200 }, "mega_machine")
        T.expect((big :: any).radius > (small :: any).radius).toBe(true)
        T.expect(#(big :: any).chunks > #(small :: any).chunks).toBe(true)
    end)
end)

T.describe("Nachwachsen", function()
    T.it("wartet die Verzögerung ab und kehrt in regrowSteps Schritten zum Original zurück", function()
        local world = newWorld()
        local state = SandDig.new(Terrain)
        world.dig(state, 0, 9, 9, "shovel")
        world.dig(state, 1, 9, 9, "shovel")
        T.expect(world.allPristine()).toBe(false)
        local open = SandDig.openCount(state)
        T.expect(open > 0).toBe(true)
        T.expect(#world.update(state, 1 + delay - 0.01, nil)).toBe(0)
        T.expect(#world.update(state, 1 + delay, nil)).toBe(0)

        local steps: { [string]: number } = {}
        local finalAt: { [string]: number } = {}
        local t = 1 + delay
        while SandDig.openCount(state) > 0 and t < 1 + delay + regrowSeconds + 5 do
            t += 1 / 60
            for _, action in world.update(state, t, nil) do
                steps[action.key] = (steps[action.key] or 0) + 1
                if action.final then
                    finalAt[action.key] = t
                end
            end
        end
        T.expect(SandDig.openCount(state)).toBe(0)
        T.expect(world.allPristine()).toBe(true)
        for key, count in steps do
            T.expect(count).toBe(Terrain.regrow.steps)
            T.expect(finalAt[key]).toBeCloseTo(1 + delay + regrowSeconds, 0.1)
        end
    end)

    T.it("Zwischenschritte nähern sich dem Original nur an", function()
        local world = newWorld()
        local state = SandDig.new(Terrain)
        world.dig(state, 0, 9, 9, "mini_digger")
        local before = world.surfaceAt(10, 10)
        world.update(state, delay + regrowSeconds / 2, nil)
        local middle = world.surfaceAt(10, 10)
        T.expect(middle > before).toBe(true)
        T.expect(middle < SURFACE).toBe(true)
    end)

    T.it("erneutes Graben setzt den Zeitplan zurück", function()
        local world = newWorld()
        local state = SandDig.new(Terrain)
        world.dig(state, 0, 9, 9, "hand")
        T.expect(#world.update(state, delay + regrowSeconds / 2, nil) > 0).toBe(true)
        local t = delay + regrowSeconds / 2 + 0.01
        world.dig(state, t, 9, 9, "hand")
        -- Bis zur neuen Verzögerung passiert nichts mehr.
        T.expect(#world.update(state, t + delay - 0.1, nil)).toBe(0)
        T.expect(SandDig.openCount(state) > 0).toBe(true)
        world.update(state, t + delay + regrowSeconds, nil)
        local u = t + delay + regrowSeconds
        while SandDig.openCount(state) > 0 do
            u += 0.1
            world.update(state, u, nil)
        end
        T.expect(world.allPristine()).toBe(true)
    end)

    T.it("pro Aufruf höchstens maxWritesPerUpdate Blöcke", function()
        local world = newWorld()
        local state = SandDig.new(Terrain)
        for i = 1, 10 do
            world.dig(state, i, 100 * i + 8, 8, "shovel")
        end
        local open = SandDig.openCount(state)
        T.expect(open > Terrain.regrow.maxWritesPerUpdate).toBe(true)
        local t = 10 + delay + regrowSeconds + 1
        local actions = world.update(state, t, nil)
        T.expect(#actions).toBe(Terrain.regrow.maxWritesPerUpdate)
        local calls = 1
        while SandDig.openCount(state) > 0 do
            T.expect(#world.update(state, t, nil) <= Terrain.regrow.maxWritesPerUpdate).toBe(true)
            calls += 1
        end
        T.expect(calls).toBe(math.ceil(open / Terrain.regrow.maxWritesPerUpdate))
        T.expect(world.allPristine()).toBe(true)
    end)

    T.it("ein Block unter dem eigenen Charakter wächst erst nach, wenn er weggeht", function()
        local world = newWorld()
        local state = SandDig.new(Terrain)
        world.dig(state, 0, 8, 8, "hand")
        local standing = { x = 8, y = SURFACE + 3, z = 8 }
        local t = delay + regrowSeconds + 1
        for _ = 1, 10 do
            local actions = world.update(state, t, standing)
            for _, action in actions do
                -- Nur Blöcke, die weit genug weg sind.
                T.expect(action.cx ~= 0 or action.cz ~= 0 or action.cy ~= 0).toBe(true)
            end
            t += 1
        end
        T.expect(state.chunks[SandDig.chunkKey(0, 0, 0)] ~= nil).toBe(true)
        local away = { x = 500, y = SURFACE + 3, z = 500 }
        while SandDig.openCount(state) > 0 do
            world.update(state, t, away)
            t += 0.1
        end
        T.expect(world.allPristine()).toBe(true)
    end)
end)

-- Simuliert Dauergraben: Der Spieler fährt schnell (30 Studs/s) im Kreis mit Radius 300 und
-- gräbt ständig. Eine Runde dauert länger als Verzögerung plus Nachwachsen.
local function session(config: any, seconds: number): (any, any, number, number, number)
    local world = newWorld()
    local state = SandDig.new(config)
    local seed = 12345
    local function random(): number
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed / 2147483648
    end
    local tools = { "hand", "shovel", "bucket_chain", "mini_digger", "vacuum_robot" }
    local dt = 1 / 30
    local t = 0
    local speed, ringRadius = 30, 300
    local angle = 0
    local x, z = ringRadius, 0
    local maxOpen = 0
    local digs = 0
    while t < seconds do
        t += dt
        angle += speed / ringRadius * dt
        x = ringRadius * math.cos(angle) + (random() - 0.5) * 4
        z = ringRadius * math.sin(angle) + (random() - 0.5) * 4
        world.update(state, t, { x = x, y = SURFACE + 3, z = z })
        if t - state.lastDigAt >= config.dig.intervalSeconds then
            -- Vor jedem Loch: die Obergrenze gilt.
            maxOpen = math.max(maxOpen, SandDig.openCount(state))
            local tool = tools[1 + math.floor(random() * #tools)]
            if world.dig(state, t, x + 3, z, tool) ~= nil then
                digs += 1
            end
        end
    end
    -- Aufhören: nach Verzögerung plus Nachwachszeit ist alles zurück (Spieler weit weg).
    local stopAt = t
    local away = { x = x + 1000, y = SURFACE, z = z + 1000 }
    while t < stopAt + config.regrow.delaySeconds + config.regrow.seconds + 1 do
        t += dt
        world.update(state, t, away)
    end
    return world, state, digs, maxOpen, t
end

local function expectAllBack(world: any, state: any)
    T.expect(SandDig.openCount(state)).toBe(0)
    T.expect(world.allPristine()).toBe(true)
    local remaining = 0
    for _ in world.baselines do
        remaining += 1
    end
    T.expect(remaining).toBe(0)
    local columns = 0
    for _ in state.surface do
        columns += 1
    end
    T.expect(columns).toBe(0)
end

T.describe("Lange Sitzung", function()
    T.it("2 Stunden Dauergraben: nie mehr als maxDirtyChunks offen, danach alles zurück", function()
        local world, state, digs, maxOpen = session(Terrain, 2 * 60 * 60)
        print(`       {digs} Löcher, höchstens {maxOpen} Blöcke offen`)
        T.expect(digs > 10000).toBe(true)
        T.expect(maxOpen <= Terrain.regrow.maxDirtyChunks).toBe(true)
        expectAllBack(world, state)
    end)

    T.it("Obergrenze greift: bei 12 Blöcken werden die ältesten sofort zurückgesetzt", function()
        local config = table.clone(Terrain)
        config.regrow = table.clone(Terrain.regrow)
        config.regrow.maxDirtyChunks = 12
        local world, state, digs, maxOpen = session(config, 10 * 60)
        T.expect(digs > 1000).toBe(true)
        T.expect(maxOpen).toBe(12)
        expectAllBack(world, state)
    end)
end)

T.finish()
