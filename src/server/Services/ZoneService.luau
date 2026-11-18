--!strict
-- Zonen-Service (Paket 2.5)
-- Zuständig: Platzhalter-Welt der fünf Zonen (Sandfelder in eigenem Terrain-Material, Tor-Anzeigen),
-- Zonenwechsel nach Position, Reisen (TravelZone) und die Meldung neuer Zonen.
--
-- Die Position des Charakters gehört dem Client, deshalb entscheidet der Server selbst: Alle
-- TICK_SECONDS prüft er mit Logic/Zones.resolve, in welcher Zone jeder Spieler steht. Eine freie
-- Zone wird zur aktuellen Zone (das Sammelfenster wird erst mit der alten Sandsorte abgerechnet,
-- Sand.setZone), eine gesperrte wird nie übernommen: Der Spieler wird in die aktuelle Zone
-- zurückgesetzt. Die Tor-Anzeigen sind nur Optik (kein Kollisionsschutz), die Sperre ist die
-- Prüfung des Servers. Die Regeln stehen im reinen Modul Logic/Zones (Lune-Tests).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wie oft der Server die Zone jedes Spielers prüft (Sekunden).
local TICK_SECONDS = 0.25
-- Meldung "Zone gesperrt" und "Zone betreten" höchstens so oft pro Spieler (Sekunden).
local LOCKED_NOTICE_SECONDS = 2
local ENTERED_NOTICE_SECONDS = 1
-- Nach einem Teleport des Servers wird die Position so lange nicht geprüft (Sekunden), weil der
-- Client noch die alte Position melden kann.
local TELEPORT_GRACE_SECONDS = 0.5
-- Tor-Anzeige: Größe in Studs (Dicke, Höhe, Länge folgt der Zone) und Farbe.
local GATE_THICKNESS = 2
local GATE_HEIGHT = 24
local GATE_TRANSPARENCY = 0.6
local GATE_COLOR = Color3.fromRGB(220, 90, 70)
-- Der Teleport beim Reisen setzt den Spieler diese Studs über den Spawn-Punkt (fällt auf den Boden).
local TRAVEL_LIFT_STUDS = 0

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local Zone = loadShared("Logic", "Zones")
local World = loadShared("Data", "World")
local Zones = loadShared("Data", "Zones")
local SandTypes = loadShared("Data", "SandTypes")
local TerrainData = loadShared("Data", "Terrain")

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local Net: any = nil

local ZoneService = {}

local lastTravelAt: { [Player]: number } = {}
local lastLockedNoticeAt: { [Player]: number } = {}
local lastEnteredNoticeAt: { [Player]: number } = {}
local graceUntil: { [Player]: number } = {}

local function now(): number
    return os.clock()
end

local function notify(player: Player, payload: any)
    Net.fire(player, "Notify", payload)
end

local function aliveRoot(player: Player): BasePart?
    local character = player.Character
    if character == nil then
        return nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
        return nil
    end
    return root
end

-- Terrain-Material (Enum) zum Namen aus SandTypes, oder nil bei einem Tippfehler.
local function materialOf(name: string): Enum.Material?
    local ok, value = pcall(function(): any
        return (Enum.Material :: any)[name]
    end)
    if ok and typeof(value) == "EnumItem" then
        return value :: Enum.Material
    end
    return nil
end

-- Liegt an der Mitte der Oberseite schon Terrain? (Studio-Terrain nicht überschreiben)
local function fieldOccupied(center: Vector3, size: Vector3): boolean
    local terrain = workspace.Terrain
    local voxel = TerrainData.voxelSize
    local probeTop = center + Vector3.new(0, size.Y / 2, 0)
    local probe = Region3.new(probeTop - Vector3.new(voxel, voxel, voxel), probeTop):ExpandToGrid(voxel)
    local _materials, occupancies = terrain:ReadVoxels(probe, voxel)
    local grid = occupancies :: any
    local size3 = grid.Size :: Vector3
    for x = 1, size3.X do
        for y = 1, size3.Y do
            for z = 1, size3.Z do
                if grid[x][y][z] > 0 then
                    return true
                end
            end
        end
    end
    return false
end

-- Platzhalter-Sandfelder (Paket 1.4 und 2.5): je Zone ein Feld im Terrain-Material ihrer Sandsorte.
-- Nur wenn es in den Daten eingeschaltet ist und an der Mitte der Oberseite noch kein Terrain liegt.
-- Löcher gräbt später nur der Client, der Server ändert dieses Terrain danach nicht mehr.
local function setupFields()
    if not TerrainData.placeholderField.enabled then
        return
    end
    local terrain = workspace.Terrain
    for _, area in World.zones do
        local zone = Zones.byId[area.id]
        local sandType = if zone ~= nil then SandTypes.byId[zone.sandTypeId] else nil
        local material = if sandType ~= nil then materialOf(sandType.terrainMaterial) else nil
        if sandType == nil or material == nil then
            warn(`[Zonen] Zone {area.id}: Sandsorte oder Terrain-Material unbekannt, kein Feld`)
            continue
        end
        local c, sz = area.field.center, area.field.size
        local center = Vector3.new(c.x, c.y, c.z)
        local size = Vector3.new(sz.x, sz.y, sz.z)
        if fieldOccupied(center, size) then
            continue
        end
        terrain:FillBlock(CFrame.new(center), size, material)
        terrain:SetMaterialColor(material, Color3.fromHex(sandType.colorHex))
        warn(`[Zonen] Kein Terrain am Platzhalter-Feld von {area.id}: Feld angelegt (bis Phase 3)`)
    end
end

-- Tor-Anzeigen an der Grenze zu jeder Zone außer der ersten (nur Optik, siehe Kopfkommentar).
-- Der Client färbt sie je nach Freischaltung und blendet das Schild ein.
local function setupGates()
    for _, area in World.zones do
        local gate = area.gate
        if gate == nil then
            continue
        end
        local length = gate.maxZ - gate.minZ
        local part = Instance.new("Part")
        part.Name = `Tor_{area.id}`
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Color = GATE_COLOR
        part.Transparency = GATE_TRANSPARENCY
        part.Size = Vector3.new(GATE_THICKNESS, GATE_HEIGHT, length)
        part.Position = Vector3.new(gate.x, GATE_HEIGHT / 2, (gate.minZ + gate.maxZ) / 2)
        part:SetAttribute("ZoneId", area.id)
        part:AddTag(World.gateTag)
        part.Parent = workspace
    end
end

local function teleport(player: Player, root: BasePart, position: { x: number, y: number, z: number })
    local target = CFrame.new(position.x, position.y + TRAVEL_LIFT_STUDS, position.z)
    local character = player.Character
    if character ~= nil then
        character:PivotTo(target)
    else
        root.CFrame = target
    end
    root.AssemblyLinearVelocity = Vector3.zero
    graceUntil[player] = now() + TELEPORT_GRACE_SECONDS
end

local function notifyEntered(player: Player, zoneId: string, t: number)
    local last = lastEnteredNoticeAt[player]
    if last == nil or t - last >= ENTERED_NOTICE_SECONDS then
        lastEnteredNoticeAt[player] = t
        notify(player, { kind = "zoneEntered", zoneId = zoneId })
    end
end

-- Ein Spieler pro Tick: Position proben und die Zone danach setzen.
local function tickPlayer(player: Player, t: number)
    local profile = PlayerData.get(player)
    local root = aliveRoot(player)
    if profile == nil or root == nil then
        return
    end
    local grace = graceUntil[player]
    if grace ~= nil and t < grace then
        return
    end
    local p = root.Position
    local result = Zone.resolve(profile, { x = p.X, y = p.Y, z = p.Z })
    if result.kind == "enter" and result.zoneId ~= nil then
        if Sand.setZone(player, result.zoneId) then
            notifyEntered(player, result.zoneId, t)
        end
    elseif result.kind == "reset" and result.zoneId ~= nil and result.pushTo ~= nil then
        -- Die aktuelle Zone ist gesperrt (zum Beispiel nach einem Sandsturm): zurück zum Anfang.
        if Sand.setZone(player, result.zoneId) then
            teleport(player, root, result.pushTo)
            notifyEntered(player, result.zoneId, t)
        end
    elseif result.kind == "blocked" and result.pushTo ~= nil then
        teleport(player, root, result.pushTo)
        local last = lastLockedNoticeAt[player]
        if last == nil or t - last >= LOCKED_NOTICE_SECONDS then
            lastLockedNoticeAt[player] = t
            notify(player, { kind = "zoneLocked", zoneId = result.zoneId })
        end
    end
end

local function tick()
    local t = now()
    for _, player in Players:GetPlayers() do
        local ok, err = pcall(tickPlayer, player, t)
        if not ok then
            warn(`[Zonen] Fehler beim Prüfen von {player.Name}: {tostring(err)}`)
        end
    end
end

-- Reisen: Antwort ist { ok, reason }. Der Client schickt nur die Zonen-ID.
local function onTravelZone(player: Player, zoneId: string): any
    local profile = PlayerData.get(player)
    if profile == nil then
        return { ok = false, reason = "unknown" }
    end
    local root = aliveRoot(player)
    if root == nil then
        return { ok = false, reason = "dead" }
    end
    local t = now()
    local ok, reason = Zone.canTravel(profile, zoneId, t, lastTravelAt[player])
    if not ok then
        return { ok = false, reason = reason }
    end
    local area = World.zonesById[zoneId]
    if not Sand.setZone(player, zoneId) then
        return { ok = false, reason = "unknown" }
    end
    lastTravelAt[player] = t
    teleport(player, root, area.spawn)
    notifyEntered(player, zoneId, t)
    return { ok = true }
end

-- Neu freigeschaltete Zonen nach einem Kauf melden. Andere Services rufen das nach Käufen auf.
function ZoneService.unlockNew(player: Player)
    local profile = PlayerData.get(player)
    if profile == nil then
        return
    end
    for _, zoneId in Zone.unlockNew(profile) do
        notify(player, { kind = "zoneUnlocked", zoneId = zoneId })
    end
end

function ZoneService.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function ZoneService.Start()
    setupFields()
    setupGates()
    Net.on("TravelZone", onTravelZone)
    Players.PlayerRemoving:Connect(function(player: Player)
        lastTravelAt[player] = nil
        lastLockedNoticeAt[player] = nil
        lastEnteredNoticeAt[player] = nil
        graceUntil[player] = nil
    end)
    task.spawn(function()
        while true do
            task.wait(TICK_SECONDS)
            tick()
        end
    end)
end

return ZoneService
