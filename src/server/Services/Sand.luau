--!strict
-- Sand-Service (Paket 1.2)
-- Zuständig: Sammeln, Tank und Verkaufen. Der Server berechnet den Sand aus Zeit und
-- Rate, der Client meldet nur "ich halte" (SetCollecting) und "ich verkaufe" (Sell).
-- Die Regeln stehen im reinen Modul Logic/Collecting (Lune-Tests), hier werden nur
-- Remotes, Server-Uhr, Händlerstand und der Zustand für den Client (StateSync) angeschlossen.
--
-- Händlerstand: Teile mit dem Tag World.sellStand.tag. Liegt keiner im Workspace, legt der
-- Server einen Platzhalter an (bis die Welt der ersten Zone steht, Phase 3). Verkaufen geht
-- nur in World.sellStand.rangeStuds um die Mitte eines Stands, das prüft der Server.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wie oft der Server laufendes Sammeln abrechnet und den Tank an den Client schickt (s).
local TICK_SECONDS = 0.25
-- Platzhalter-Stand: Größe und Farbe (nur bis Phase 3).
local PLACEHOLDER_SIZE = Vector3.new(8, 6, 4)
local PLACEHOLDER_COLOR = Color3.fromRGB(176, 120, 64)
local PROMPT_ACTION_TEXT = "Verkaufen"
local PROMPT_OBJECT_TEXT = "Händlerstand"
-- Attribut am ProximityPrompt, an dem der Client den Verkaufs-Prompt erkennt.
local SELL_PROMPT_ATTRIBUTE = "SellPrompt"

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local Collecting = loadShared("Logic", "Collecting")
local TreeEffects = loadShared("Logic", "TreeEffects")
local BigNum = loadShared("Logic", "BigNum")
local World = loadShared("Data", "World")
local Tutorial = loadShared("Logic", "Tutorial")
local TerrainData = loadShared("Data", "Terrain")
local SandTypes = loadShared("Data", "SandTypes")

local servicesFolder = script.Parent
local PlayerData: any = nil
local Net: any = nil

local Sand = {}

local states: { [Player]: any } = {}
-- War der Charakter bei der letzten Positionsprobe (tick) in Reichweite eines Stands?
local wasNearStand: { [Player]: boolean } = {}

local function now(): number
    return os.clock()
end

local function stateOf(player: Player): any
    local state = states[player]
    if state == nil then
        state = Collecting.newState(now())
        states[player] = state
    end
    return state
end

-- Zustand für die Anzeige beim Client. Der Client rechnet damit nichts Maßgebliches.
function Sand.snapshot(player: Player): any?
    local profile = PlayerData.get(player)
    if profile == nil then
        return nil
    end
    local state = stateOf(player)
    local zone = Collecting.zoneOf(profile)
    local effects = TreeEffects.of(profile)
    return {
        coins = BigNum.serialize(BigNum.deserialize(profile.coins)),
        tank = BigNum.serialize(BigNum.deserialize(profile.tank)),
        capacity = Collecting.capacityOf(profile),
        rate = Collecting.rateOf(profile),
        toolId = Collecting.toolOf(profile).id,
        collecting = state.holding,
        zoneId = zone.id,
        pricePerSand = Collecting.pricePerSand(profile),
        nodes = Collecting.ownedNodes(profile),
        sellBonusBp = effects.sellBonusBp,
        luckBonusBp = effects.luckBonusBp,
        tutorialStep = Tutorial.stepOf(profile),
    }
end

local function sync(player: Player)
    local snapshot = Sand.snapshot(player)
    if snapshot ~= nil then
        Net.fire(player, "StateSync", snapshot)
    end
end

-- Tutorial neu bewerten (Tank, Käufe, Laden) und Zustand an den Client schicken. Andere
-- Services rufen das nach Änderungen am Profil auf (zum Beispiel Upgrades nach einem Kauf).
function Sand.refresh(player: Player)
    local profile = PlayerData.get(player)
    if profile ~= nil then
        Tutorial.evaluate(profile)
    end
    sync(player)
end

local function notify(player: Player, payload: any)
    Net.fire(player, "Notify", payload)
end

-- HumanoidRootPart eines lebenden Charakters, sonst nil.
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

-- Mitte des nächsten Händlerstands in Reichweite?
local function nearSellStand(player: Player): boolean
    local root = aliveRoot(player)
    if root == nil then
        return false
    end
    local position = root.Position
    for _, stand in CollectionService:GetTagged(World.sellStand.tag) do
        if stand:IsA("BasePart") and stand:IsDescendantOf(workspace) then
            local d = position - stand.Position
            if Collecting.inRange(d.X, d.Y, d.Z, World.sellStand.rangeStuds) then
                return true
            end
        end
    end
    return false
end

-- Sammeln nur mit lebendem Charakter und nicht direkt am Händlerstand.
local function canCollect(player: Player): boolean
    return aliveRoot(player) ~= nil and not nearSellStand(player)
end

local function onSetCollecting(player: Player, holding: boolean)
    local profile = PlayerData.get(player)
    if profile == nil then
        return
    end
    local state = stateOf(player)
    local wasHolding = state.holding
    local result = Collecting.setHolding(state, profile, holding and canCollect(player), now())
    if result.full and holding then
        notify(player, { kind = "tankFull" })
    end
    local tutorialChanged = result.added > 0 and Tutorial.evaluate(profile)
    if result.added > 0 or tutorialChanged or wasHolding ~= state.holding then
        sync(player)
    end
end

local function onSell(player: Player)
    local profile = PlayerData.get(player)
    if profile == nil then
        return
    end
    -- Auch bei der letzten Probe in Reichweite: ein Teleport für einen Aufruf reicht nicht.
    if not nearSellStand(player) or not wasNearStand[player] then
        notify(player, { kind = "sellTooFar" })
        return
    end
    local earned, sold = Collecting.sell(stateOf(player), profile, now())
    if earned == nil then
        notify(player, { kind = "tankEmpty" })
    else
        Tutorial.onSold(profile)
        notify(player, {
            kind = "sold",
            earned = BigNum.serialize(earned),
            sold = BigNum.serialize(sold),
        })
    end
    sync(player)
end

local function addPrompt(stand: BasePart)
    if stand:FindFirstChildWhichIsA("ProximityPrompt") ~= nil then
        return
    end
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = PROMPT_ACTION_TEXT
    prompt.ObjectText = PROMPT_OBJECT_TEXT
    prompt.MaxActivationDistance = World.sellStand.promptDistanceStuds
    prompt.RequiresLineOfSight = false
    prompt:SetAttribute(SELL_PROMPT_ATTRIBUTE, true)
    prompt.Parent = stand
end

local function setupSellStands()
    local tag = World.sellStand.tag
    if #CollectionService:GetTagged(tag) == 0 then
        local pos = World.sellStand.placeholderPosition
        local part = Instance.new("Part")
        part.Name = "SellStand_Platzhalter"
        part.Anchored = true
        part.Size = PLACEHOLDER_SIZE
        part.Color = PLACEHOLDER_COLOR
        part.Position = Vector3.new(pos.x, pos.y, pos.z)
        part:AddTag(tag)
        part.Parent = workspace
        warn("[Sand] Kein Händlerstand im Workspace: Platzhalter angelegt (bis Phase 3)")
    end
    for _, stand in CollectionService:GetTagged(tag) do
        if stand:IsA("BasePart") then
            addPrompt(stand)
        end
    end
    CollectionService:GetInstanceAddedSignal(tag):Connect(function(stand: Instance)
        if stand:IsA("BasePart") then
            addPrompt(stand)
        end
    end)
end

-- Platzhalter-Sandfeld (Paket 1.4), bis die Zone Dünenmeer steht (Paket 1.5). Nur wenn es in
-- den Daten eingeschaltet ist und an der Mitte der Oberseite noch kein Terrain liegt. Löcher
-- gräbt später nur der Client, der Server ändert dieses Terrain danach nicht mehr.
local function setupPlaceholderSand()
    local field = TerrainData.placeholderField
    if not field.enabled then
        return
    end
    local terrain = workspace.Terrain
    local voxel = TerrainData.voxelSize
    local center = Vector3.new(field.center.x, field.center.y, field.center.z)
    local size = Vector3.new(field.size.x, field.size.y, field.size.z)
    -- Probe: der Voxel direkt unter der Mitte der Oberseite.
    local probeTop = center + Vector3.new(0, size.Y / 2, 0)
    local probe = Region3.new(probeTop - Vector3.new(voxel, voxel, voxel), probeTop):ExpandToGrid(voxel)
    local _materials, occupancies = terrain:ReadVoxels(probe, voxel)
    local grid = occupancies :: any
    local size3 = grid.Size :: Vector3
    local occupied = false
    for x = 1, size3.X do
        for y = 1, size3.Y do
            for z = 1, size3.Z do
                if grid[x][y][z] > 0 then
                    occupied = true
                end
            end
        end
    end
    if occupied then
        return
    end
    local material = (Enum.Material :: any)[field.material]
    terrain:FillBlock(CFrame.new(center), size, material)
    local sandType = SandTypes.byId[field.sandTypeId]
    if sandType ~= nil then
        terrain:SetMaterialColor(material, Color3.fromHex(sandType.colorHex))
    end
    warn("[Sand] Kein Sandterrain am Platzhalter-Feld: Platzhalter-Sandfeld angelegt (bis Paket 1.5)")
end

-- Ein Spieler pro Tick: Position proben, laufendes Sammeln abrechnen, Änderungen senden.
local function tickPlayer(player: Player, state: any, t: number)
    wasNearStand[player] = nearSellStand(player)
    if not state.holding then
        return
    end
    local profile = PlayerData.get(player)
    if profile == nil then
        state.holding = false
        return
    end
    if not canCollect(player) then
        -- Gestorben oder zum Stand gegangen: bis jetzt abrechnen, dann stoppen.
        Collecting.setHolding(state, profile, false, t)
        sync(player)
        return
    end
    local result = Collecting.update(state, profile, t)
    if result.full then
        notify(player, { kind = "tankFull" })
    end
    local tutorialChanged = result.added > 0 and Tutorial.evaluate(profile)
    if result.added > 0 or tutorialChanged or not state.holding then
        sync(player)
    end
end

local function tick()
    local t = now()
    for player, state in states do
        local ok, err = pcall(tickPlayer, player, state, t)
        if not ok then
            warn(`[Sand] Fehler beim Abrechnen für {player.Name}: {tostring(err)}`)
        end
    end
end

function Sand.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Sand.Start()
    setupSellStands()
    setupPlaceholderSand()
    Net.on("SetCollecting", onSetCollecting)
    Net.on("Sell", onSell)

    PlayerData.onLoaded(function(player: Player, _profile: any)
        states[player] = Collecting.newState(now())
        Sand.refresh(player)
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        states[player] = nil
        wasNearStand[player] = nil
    end)

    task.spawn(function()
        while true do
            task.wait(TICK_SECONDS)
            tick()
        end
    end)
end

return Sand
