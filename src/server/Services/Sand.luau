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
-- So nah an der Standposition der Zone zählt ein vorhandener Stand als ihr Stand (Studs).
local PLACEHOLDER_SEARCH_RADIUS = 40
local PROMPT_ACTION_TEXT = "Verkaufen"
local PROMPT_OBJECT_TEXT = "Händlerstand"
-- Attribut am ProximityPrompt, an dem der Client den Verkaufs-Prompt erkennt.
local SELL_PROMPT_ATTRIBUTE = "SellPrompt"

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local Collecting = loadShared("Logic", "Collecting")
local Equipment = loadShared("Logic", "Equipment")
local TreeEffects = loadShared("Logic", "TreeEffects")
local ToolLook = loadShared("Logic", "ToolLook")
local Zones = loadShared("Logic", "Zones")
local BigNum = loadShared("Logic", "BigNum")
local World = loadShared("Data", "World")
local Tutorial = loadShared("Logic", "Tutorial")
local Collection = loadShared("Logic", "Collection")
local Wind = loadShared("Logic", "Wind")
local Sandstorm = loadShared("Logic", "Sandstorm")

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

-- Rechnet das offene Sammelfenster mit der bisherigen Rate ab. Upgrades ruft das vor einem
-- Kauf auf, damit eine neue Rate (oder ein neuer Tank) nicht rückwirkend gilt.
function Sand.settle(player: Player)
    local profile = PlayerData.get(player)
    if profile ~= nil then
        Collecting.update(stateOf(player), profile, now())
    end
end

-- Holt die Sammelzeit je Zone ab, die der Finds-Service noch nicht gewürfelt hat (Paket 2.6).
-- Gibt eine leere Tabelle zurück, wenn der Spieler keinen Zustand hat.
function Sand.takeFindSeconds(player: Player): { [string]: number }
    local state = states[player]
    if state == nil then
        return {}
    end
    return Collecting.takeFindSeconds(state)
end

-- Weitere Services (zum Beispiel Crates, Paket 4.2) hängen eigene Felder an den Snapshot, ohne dass
-- Sand sie kennen oder per require laden muss (sonst entstünde ein Zyklus). Ein Provider gibt eine
-- Tabelle mit Feldern zurück; ein Fehler im Provider lässt die übrigen Felder unberührt. Eigene
-- Felder von Sand werden nie überschrieben.
local snapshotProviders: { (Player) -> { [string]: any } } = {}

function Sand.addSnapshotProvider(provider: (Player) -> { [string]: any })
    table.insert(snapshotProviders, provider)
end

-- Kisten-Pity für die Anzeige (Paket 4.2): Kopie je Kiste, damit der Client nie am Profil hängt.
local function pityOf(profile: any): { [string]: any }
    local result: { [string]: any } = {}
    local pity = profile.pity
    if type(pity) == "table" then
        for crateId, counters in pity do
            if type(crateId) == "string" and type(counters) == "table" then
                result[crateId] = { sinceEpic = counters.sinceEpic, sinceLegendary = counters.sinceLegendary }
            end
        end
    end
    return result
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
    local snapshot: any = {
        coins = BigNum.serialize(BigNum.deserialize(profile.coins)),
        gems = profile.gems, -- Gems (Paket 4.1)
        tank = BigNum.serialize(BigNum.deserialize(profile.tank)),
        capacity = Collecting.capacityOf(profile),
        rate = Collecting.rateOf(profile),
        toolId = Collecting.toolOf(profile).id,
        collecting = state.holding,
        zoneId = zone.id,
        pricePerSand = Collecting.pricePerSand(profile),
        nodes = Collecting.ownedNodes(profile),
        zonesUnlocked = Zones.unlockedMap(profile),
        sellBonusBp = effects.sellBonusBp,
        luckBonusBp = effects.luckBonusBp,
        collectionBonusBp = Collection.bonusBp(profile), -- Summe der fertigen Sets (Paket 2.6)
        windCrystals = Wind.crystalsOf(profile), -- Sandsturm (Paket 2.7)
        windBonusBp = Wind.bonusBp(profile),
        storm = Sandstorm.preview(profile), -- Vorschau für Knopf und Fenster
        tutorialStep = Tutorial.stepOf(profile),
        pity = pityOf(profile), -- Kisten-Pity je Kiste (Paket 4.2)
    }
    for _, provider in snapshotProviders do
        -- Ein Provider darf nicht warten und nicht werfen: Koroutine, bei Yield schließen.
        local co = coroutine.create(provider)
        local ok, extra = coroutine.resume(co, player)
        if coroutine.status(co) ~= "dead" then
            coroutine.close(co)
            warn("Sand.snapshot: ein Snapshot-Provider hat gewartet und wird ignoriert")
        elseif not ok then
            warn(`Sand.snapshot: Snapshot-Provider fehlgeschlagen: {tostring(extra)}`)
        elseif type(extra) == "table" then
            for key, value in extra do
                if snapshot[key] == nil then
                    snapshot[key] = value
                end
            end
        end
    end
    return snapshot
end

-- Nach einem Sandsturm (Paket 2.7): Der Sammelzustand beginnt neu. Der Tank ist schon leer, der
-- Rest eines Korns und nicht gewürfelte Sammelzeit gehören zum alten Lauf. Ob der Spieler die
-- Taste hält, bleibt (der Client meldet das ohnehin jede Sekunde neu). Der Aufrufer ruft danach
-- `Sand.setZone` und `Sand.refresh`.
function Sand.resetAfterStorm(player: Player)
    local state = states[player]
    if state ~= nil then
        state.carry = 0
        state.findSeconds = {}
        state.lastTick = now()
    end
end

-- Werkzeug und Sammeln als Spieler-Attribute (Paket 2.4), damit alle Clients die Maschine eines
-- Spielers sehen. Nur der Server setzt sie, der Client sendet dazu nichts.
local function publishLook(player: Player)
    local profile = PlayerData.get(player)
    if profile == nil then
        return
    end
    local attributes: { [string]: any } = {}
    for name, value in ToolLook.attributesFor(profile, stateOf(player).holding) do
        attributes[name] = value
    end
    -- Ausrüstung der Kisten-Items (Paket 4.3): SkinId, CompanionId, ToolVariantId.
    for name, value in Equipment.attributesFor(profile) do
        attributes[name] = value
    end
    for name, value in attributes do
        if player:GetAttribute(name) ~= value then
            player:SetAttribute(name, value)
        end
    end
end

local function sync(player: Player)
    publishLook(player)
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

-- Wechselt die aktuelle Zone des Spielers (Paket 2.5). Das offene Sammelfenster wird mit der
-- alten Sandsorte abgerechnet, danach zählt die neue. Eine gesperrte Zone wird nie übernommen
-- (zweite Sicherung neben ZoneService). Gibt false zurück, wenn kein Profil da ist oder die Zone
-- gesperrt ist.
function Sand.setZone(player: Player, zoneId: string): boolean
    local profile = PlayerData.get(player)
    if profile == nil or not Zones.isUnlocked(profile, zoneId) then
        return false
    end
    Collecting.setZone(stateOf(player), profile, zoneId, now())
    sync(player)
    return true
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
    -- Je Zone ein Platzhalter-Stand, falls im Workspace noch keiner in der Nähe liegt (bis Phase 3).
    for _, area in World.zones do
        local pos = area.stand
        local nearby = false
        for _, stand in CollectionService:GetTagged(tag) do
            if stand:IsA("BasePart") then
                local d = stand.Position - Vector3.new(pos.x, pos.y, pos.z)
                if d.Magnitude <= PLACEHOLDER_SEARCH_RADIUS then
                    nearby = true
                    break
                end
            end
        end
        if not nearby then
            local part = Instance.new("Part")
            part.Name = `SellStand_Platzhalter_{area.id}`
            part.Anchored = true
            part.Size = PLACEHOLDER_SIZE
            part.Color = PLACEHOLDER_COLOR
            part.Position = Vector3.new(pos.x, pos.y, pos.z)
            part:AddTag(tag)
            part.Parent = workspace
            warn(`[Sand] Kein Händlerstand für Zone {area.id}: Platzhalter angelegt (bis Phase 3)`)
        end
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
    Net.on("SetCollecting", onSetCollecting)
    Net.on("Sell", onSell)

    PlayerData.onLoaded(function(player: Player, profile: any)
        states[player] = Collecting.newState(now())
        -- Zonen, deren Knoten schon gekauft sind (alte Spielstände), still freischalten.
        Zones.unlockNew(profile)
        if not Zones.isUnlocked(profile, profile.currentZone) then
            profile.currentZone = "dunes" -- eine gesperrte aktuelle Zone nie übernehmen
        end
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
