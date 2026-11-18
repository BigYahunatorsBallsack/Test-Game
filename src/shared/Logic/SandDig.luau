--!strict
-- Reine Logik der Terrain-Verformung (Paket 1.4), ohne Roblox-API.
--
-- Der Client gräbt Löcher nur bei sich selbst. Terrain wird in würfelförmigen Blöcken
-- (Terrain.chunkSize) verwaltet: Vor dem ersten Graben merkt sich der Client den
-- Originalzustand eines Blocks, beim Nachwachsen blendet er schrittweise dorthin zurück und
-- vergisst den Block danach. Dieses Modul entscheidet, welche Blöcke ein Loch berührt, wie
-- Voxel ausgehöhlt und zurückgeblendet werden, und wann welcher Block nachwächst. Lesen und
-- Schreiben der Voxel macht der Client-Controller Dig.
--
-- Voxel-Raster (wie Terrain:ReadVoxels): occ[x][y][z] Füllung 0..1, mat[x][y][z] Material.
-- Materialien sind hier undurchsichtige Werte, nur der Wert für Luft wird übergeben.

export type Vec3 = { x: number, y: number, z: number }

export type Grid = {
    origin: Vec3, -- Ecke mit den kleinsten Koordinaten (Studs)
    n: number, -- Voxel pro Achse
    voxelSize: number,
    occ: { { { number } } },
    mat: { { { any } } },
}

export type ChunkRef = {
    key: string,
    cx: number,
    cy: number,
    cz: number,
    isNew: boolean, -- Originalzustand muss noch gelesen werden
}

export type Chunk = {
    key: string,
    cx: number,
    cy: number,
    cz: number,
    lastDugAt: number,
    stepsDone: number, -- erledigte Nachwachs-Schritte seit dem letzten Graben
    forced: boolean, -- sofort zurücksetzen (Obergrenze erreicht)
}

export type DigResult = {
    center: Vec3, -- Mitte der Kugel, die die Mulde formt
    radius: number,
    floorY: number, -- unter diese Höhe wird nicht gegraben
    chunks: { ChunkRef },
}

export type RegrowAction = {
    key: string,
    cx: number,
    cy: number,
    cz: number,
    t: number, -- Anteil des Wegs zum Original, der in diesem Schritt zurückgelegt wird (0..1]
    final: boolean, -- letzter Schritt: Original schreiben und Block vergessen
}

export type State = {
    config: any,
    chunks: { [string]: Chunk },
    count: number,
    lastDigAt: number,
    -- Ursprüngliche Oberfläche je Rasterzelle, gruppiert nach Blocksäule (cx, cz).
    surface: { [string]: { [string]: number } },
}

local EMPTY_EPSILON = 0.01 -- Füllung darunter gilt als leer (Luft)
local TIME_EPSILON = 1e-9 -- Rundung bei Zeitvergleichen
local TOO_DEEP_MARGIN = 0.25 -- Treffer so nah an der Grenze graben nicht mehr

local SandDig = {}

function SandDig.new(config: any): State
    return {
        config = config,
        chunks = {},
        count = 0,
        lastDigAt = -math.huge,
        surface = {},
    }
end

function SandDig.chunkKey(cx: number, cy: number, cz: number): string
    return `{cx},{cy},{cz}`
end

local function columnKey(cx: number, cz: number): string
    return `{cx},{cz}`
end

-- Lochgröße für ein Werkzeug, unbekannte Werkzeuge graben wie das Standardwerkzeug.
function SandDig.holeFor(config: any, toolId: string?): { radius: number, depth: number }
    local hole = if toolId ~= nil then config.holeByTool[toolId] else nil
    return hole or config.holeByTool[config.defaultToolId]
end

-- Abstand eines Punkts zu einem achsparallelen Würfel (0, wenn innen).
local function distanceToBox(p: Vec3, minX: number, minY: number, minZ: number, size: number): number
    local dx = math.max(minX - p.x, 0, p.x - (minX + size))
    local dy = math.max(minY - p.y, 0, p.y - (minY + size))
    local dz = math.max(minZ - p.z, 0, p.z - (minZ + size))
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Alle Blöcke (cx, cy, cz), die eine Kugel schneidet, sortiert.
function SandDig.chunksForSphere(center: Vec3, radius: number, chunkSize: number): { { number } }
    local result: { { number } } = {}
    local x0 = math.floor((center.x - radius) / chunkSize)
    local x1 = math.floor((center.x + radius) / chunkSize)
    local y0 = math.floor((center.y - radius) / chunkSize)
    local y1 = math.floor((center.y + radius) / chunkSize)
    local z0 = math.floor((center.z - radius) / chunkSize)
    local z1 = math.floor((center.z + radius) / chunkSize)
    for cx = x0, x1 do
        for cy = y0, y1 do
            for cz = z0, z1 do
                if distanceToBox(center, cx * chunkSize, cy * chunkSize, cz * chunkSize, chunkSize) < radius then
                    table.insert(result, { cx, cy, cz })
                end
            end
        end
    end
    return result
end

-- Ecke eines Blocks in Studs.
function SandDig.chunkOrigin(config: any, cx: number, cy: number, cz: number): Vec3
    local s = config.chunkSize
    return { x = cx * s, y = cy * s, z = cz * s }
end

-- Darf jetzt gegraben werden (Takt)? Wenn ja, zählt der Aufruf als Graben.
function SandDig.takeDigSlot(state: State, now: number): boolean
    if now - state.lastDigAt < state.config.dig.intervalSeconds - TIME_EPSILON then
        return false
    end
    state.lastDigAt = now
    return true
end

-- Ursprüngliche Oberfläche an einer Stelle: beim ersten Graben gemessen, danach gemerkt.
-- Merkt sich die Höhe auch für alle Zellen im Umkreis, damit Nachbarlöcher die Grenze
-- nicht verschieben.
local function surfaceAt(state: State, hit: Vec3, radius: number): number
    local config = state.config
    local cell = config.dig.surfaceCellStuds
    local cs = config.chunkSize
    local function cellOf(x: number, z: number): (string, string)
        local ix = math.floor(x / cell)
        local iz = math.floor(z / cell)
        local col = columnKey(math.floor(ix * cell / cs), math.floor(iz * cell / cs))
        return col, `{ix},{iz}`
    end
    local col, key = cellOf(hit.x, hit.z)
    local known = state.surface[col] and state.surface[col][key]
    local ref = if known ~= nil then known else hit.y
    local reach = math.ceil(radius / cell)
    local hx = math.floor(hit.x / cell)
    local hz = math.floor(hit.z / cell)
    for ix = hx - reach, hx + reach do
        for iz = hz - reach, hz + reach do
            local cxStuds = (ix + 0.5) * cell
            local czStuds = (iz + 0.5) * cell
            local dx = cxStuds - hit.x
            local dz = czStuds - hit.z
            if dx * dx + dz * dz <= radius * radius or (ix == hx and iz == hz) then
                local c, k = cellOf(cxStuds, czStuds)
                local column = state.surface[c]
                if column == nil then
                    column = {}
                    state.surface[c] = column
                end
                if column[k] == nil then
                    column[k] = ref
                end
            end
        end
    end
    return ref
end

-- Ältesten nicht blockierten Block zum sofortigen Zurücksetzen markieren.
local function forceOldest(state: State, protect: { [string]: boolean })
    local oldest: Chunk? = nil
    for key, chunk in state.chunks do
        if not chunk.forced and not protect[key] and (oldest == nil or chunk.lastDugAt < (oldest :: Chunk).lastDugAt) then
            oldest = chunk
        end
    end
    if oldest ~= nil then
        oldest.forced = true
    end
end

local function forcedCount(state: State): number
    local n = 0
    for _, chunk in state.chunks do
        if chunk.forced then
            n += 1
        end
    end
    return n
end

-- Ein Loch an der Trefferstelle (Oberfläche) planen. Prüft den Takt und die Tiefengrenze,
-- trägt die berührten Blöcke ein und gibt zurück, was der Client aushöhlen soll.
-- Rückgabe nil plus Grund: "interval" (zu früh) oder "tooDeep" (Grenze erreicht).
-- `zoneId` (optional) wählt die Tiefengrenze der Zone (`dig.maxDepthByZone`, Paket 2.5), sonst gilt
-- `dig.maxDepthStuds`.
function SandDig.tryDig(state: State, now: number, hit: Vec3, toolId: string?, zoneId: string?): (DigResult?, string?)
    local config = state.config
    if now - state.lastDigAt < config.dig.intervalSeconds - TIME_EPSILON then
        return nil, "interval"
    end
    local hole = SandDig.holeFor(config, toolId)
    local ref = surfaceAt(state, hit, hole.radius)
    local byZone = config.dig.maxDepthByZone
    local maxDepth = if zoneId ~= nil and byZone ~= nil and byZone[zoneId] ~= nil then byZone[zoneId] else config.dig.maxDepthStuds
    local floorY = ref - maxDepth
    if hit.y <= floorY + TOO_DEEP_MARGIN then
        return nil, "tooDeep"
    end
    state.lastDigAt = now
    -- Kugel über der Oberfläche, die nur `depth` tief in den Boden schneidet.
    local center = { x = hit.x, y = hit.y + hole.radius - hole.depth, z = hit.z }
    local refs: { ChunkRef } = {}
    local touched: { [string]: boolean } = {}
    for _, c in SandDig.chunksForSphere(center, hole.radius, config.chunkSize) do
        local cx, cy, cz = c[1], c[2], c[3]
        local key = SandDig.chunkKey(cx, cy, cz)
        touched[key] = true
        local chunk = state.chunks[key]
        local isNew = chunk == nil
        if chunk == nil then
            chunk = { key = key, cx = cx, cy = cy, cz = cz, lastDugAt = now, stepsDone = 0, forced = false }
            state.chunks[key] = chunk
            state.count += 1
        else
            -- Erneutes Graben setzt den Zeitplan zurück. Ein schon teilweise nachgewachsener
            -- Block bleibt im Speicher, das Original gilt weiter.
            chunk.lastDugAt = now
            chunk.stepsDone = 0
            chunk.forced = false
        end
        table.insert(refs, { key = key, cx = cx, cy = cy, cz = cz, isNew = isNew })
    end
    -- Obergrenze: älteste Blöcke außerhalb dieses Lochs zum Zurücksetzen markieren.
    while state.count - forcedCount(state) > config.regrow.maxDirtyChunks do
        local before = forcedCount(state)
        forceOldest(state, touched)
        if forcedCount(state) == before then
            break
        end
    end
    return { center = center, radius = hole.radius, floorY = floorY, chunks = refs }, nil
end

-- Block vergessen (nach dem letzten Nachwachs-Schritt oder wenn ein neuer Block durch das
-- Loch gar nicht verändert wurde). Gibt die gemerkte Oberfläche frei, sobald in der
-- Blocksäule kein Block mehr offen ist.
function SandDig.forget(state: State, key: string)
    local chunk = state.chunks[key]
    if chunk == nil then
        return
    end
    state.chunks[key] = nil
    state.count -= 1
    for _, other in state.chunks do
        if other.cx == chunk.cx and other.cz == chunk.cz then
            return
        end
    end
    state.surface[columnKey(chunk.cx, chunk.cz)] = nil
end

function SandDig.openCount(state: State): number
    return state.count
end

-- Nachwachsen planen: bis zu maxWritesPerUpdate Aktionen, zuerst erzwungene, dann die
-- ältesten fälligen. Blöcke nahe `playerPos` warten (außer erzwungene). Der Aufrufer muss
-- jede Aktion ausführen; bei `final` vergisst dieses Modul den Block schon hier.
function SandDig.update(state: State, now: number, playerPos: Vec3?): { RegrowAction }
    local config = state.config
    local regrow = config.regrow
    local cs = config.chunkSize
    local stepSeconds = regrow.seconds / regrow.steps
    local due: { { chunk: Chunk, target: number } } = {}
    for _, chunk in state.chunks do
        if chunk.forced then
            table.insert(due, { chunk = chunk, target = regrow.steps })
        else
            local start = chunk.lastDugAt + regrow.delaySeconds
            if now > start then
                local target = math.min(regrow.steps, math.floor((now - start) / stepSeconds + 1e-9))
                if target > chunk.stepsDone then
                    local blocked = playerPos ~= nil
                        and distanceToBox(playerPos, chunk.cx * cs, chunk.cy * cs, chunk.cz * cs, cs) < regrow.blockRadiusStuds
                    if not blocked then
                        table.insert(due, { chunk = chunk, target = target })
                    end
                end
            end
        end
    end
    table.sort(due, function(a, b)
        if a.chunk.forced ~= b.chunk.forced then
            return a.chunk.forced
        end
        if a.chunk.lastDugAt ~= b.chunk.lastDugAt then
            return a.chunk.lastDugAt < b.chunk.lastDugAt
        end
        return a.chunk.key < b.chunk.key
    end)
    local actions: { RegrowAction } = {}
    for i = 1, math.min(#due, regrow.maxWritesPerUpdate) do
        local chunk = due[i].chunk
        local target = due[i].target
        local remaining = regrow.steps - chunk.stepsDone
        local t = (target - chunk.stepsDone) / remaining
        local final = target >= regrow.steps
        table.insert(actions, {
            key = chunk.key,
            cx = chunk.cx,
            cy = chunk.cy,
            cz = chunk.cz,
            t = if final then 1 else t,
            final = final,
        })
        if final then
            SandDig.forget(state, chunk.key)
        else
            chunk.stepsDone = target
        end
    end
    return actions
end

-- Mulde in ein Voxel-Raster schneiden. Das Terrain wird als Höhenfeld behandelt: Jeder
-- Voxel ist von unten bis zu seiner Füllung gefüllt. Die Kugel (center, radius) senkt jede
-- Voxelsäule bis zur Unterseite der Kugel, aber nie unter floorY. Weil eine Säule 4 Studs
-- breit ist, zählt der Abstand von der Kugelmitte zum nächsten Rand der Säule (ungefähr:
-- Abstand zur Säulenmitte minus halbe Voxelbreite), sonst würden kleine Löcher zwischen den
-- Säulenmitten verschwinden. Nur grabbare Materialien (`diggable[material] == true`) werden
-- verändert, Fels und Wasser bleiben. Gibt zurück, ob sich etwas geändert hat.
function SandDig.carve(grid: Grid, center: Vec3, radius: number, floorY: number, air: any, diggable: { [any]: boolean }): boolean
    local changed = false
    local vs = grid.voxelSize
    for ix = 1, grid.n do
        local dx = grid.origin.x + (ix - 0.5) * vs - center.x
        for iz = 1, grid.n do
            local dz = grid.origin.z + (iz - 0.5) * vs - center.z
            local h = math.max(0, math.sqrt(dx * dx + dz * dz) - vs / 2)
            if h < radius then
                local half = math.sqrt(radius * radius - h * h)
                local cut = math.max(center.y - half, floorY)
                local top = center.y + half
                for iy = 1, grid.n do
                    local y0 = grid.origin.y + (iy - 1) * vs
                    local old = grid.occ[ix][iy][iz]
                    if y0 < top and old > 0 and diggable[grid.mat[ix][iy][iz]] == true then
                        local fill = math.clamp((cut - y0) / vs, 0, 1)
                        if fill < old then
                            local new = if fill < EMPTY_EPSILON then 0 else fill
                            grid.occ[ix][iy][iz] = new
                            if new == 0 then
                                grid.mat[ix][iy][iz] = air
                            end
                            changed = true
                        end
                    end
                end
            end
        end
    end
    return changed
end

-- Raster um den Anteil t zum Original zurückblenden (t = 1: genau das Original).
-- Ein leerer Voxel, der wieder Füllung bekommt, übernimmt das Material des Originals.
function SandDig.blend(grid: Grid, baseline: Grid, t: number, air: any)
    for ix = 1, grid.n do
        for iy = 1, grid.n do
            for iz = 1, grid.n do
                local base = baseline.occ[ix][iy][iz]
                if t >= 1 then
                    grid.occ[ix][iy][iz] = base
                    grid.mat[ix][iy][iz] = baseline.mat[ix][iy][iz]
                else
                    local cur = grid.occ[ix][iy][iz]
                    local new = cur + (base - cur) * t
                    if new < EMPTY_EPSILON and base > 0 then
                        -- Noch zu wenig, um sichtbar zu sein: im nächsten Schritt weiter.
                        new = math.min(base, EMPTY_EPSILON)
                    end
                    grid.occ[ix][iy][iz] = new
                    if new > 0 and grid.mat[ix][iy][iz] == air then
                        grid.mat[ix][iy][iz] = baseline.mat[ix][iy][iz]
                    elseif new <= 0 then
                        grid.mat[ix][iy][iz] = air
                    end
                end
            end
        end
    end
end

return SandDig
