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
--
-- Gamepasses und Münz-Boost (Paket 4.4): `Sand.optionsFor(player)` liefert die Faktoren aus
-- Logic/Perks.options (Tank: "Großer Tank", Münzen: "2x Münzen" mal Münz-Boost, Unix-Zeit os.time).
-- Jeder Collecting-Aufruf hier bekommt diese Options, ebenso die Sandsturm-Vorschau im Snapshot;
-- Upgrades gibt sie an Sandstorm.apply weiter. Auto-Dig läuft im Takt (tickPlayer): Mit Pass und
-- Einstellung an startet der Server das Halten selbst und erneuert die Frist bei jedem Takt
-- (Entscheidung in Perks.autoDigStep); ein SetCollecting(false) vom Client stoppt es nicht. Ohne Pass
-- oder mit Schalter aus bleibt alles wie vor Paket 4.4.
--
-- Stich (Überarbeitung Ü2): Der Client sendet "Stab" mit dem Zielpunkt und ob der Stich durch Halten
-- kam. Logic/Deposits prüft Takt (Server-Uhr), Reichweite und Zelle und rechnet die Menge; hier kommen
-- Charakterposition, ein Strahl auf das Terrain (liegt unter dem Punkt grabbarer Sand?) und der Tank
-- dazu. Sammeln über die Zeit (SetCollecting, Collecting.update) gibt es nur noch für den Auto-Dig-Pass,
-- mit dem Faktor Deposits.autoDigFactor auf die Rate. Ein SetCollecting(true) ohne aktiven Pass bewirkt
-- nichts.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local IS_STUDIO = RunService:IsStudio() -- Platzhalter-Stände nur in Studio (Überarbeitung Ü1)

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
local Perks = loadShared("Logic", "Perks")
local Passes = loadShared("Logic", "Passes")
local Deposits = loadShared("Logic", "Deposits")
local DepositData = loadShared("Data", "Deposits")
local DigAim = loadShared("Logic", "DigAim")
local TerrainData = loadShared("Data", "Terrain")
local SandTypes = loadShared("Data", "SandTypes")

local servicesFolder = script.Parent
local SeasonClock = require(servicesFolder:WaitForChild("SeasonClock") :: ModuleScript) :: any -- Saison-Uhr für die Event-Zone (Paket 5.5)
local PlayerData: any = nil
local Net: any = nil

local Sand = {}

local states: { [Player]: any } = {}
-- War der Charakter bei der letzten Positionsprobe (tick) in Reichweite eines Stands?
local wasNearStand: { [Player]: boolean } = {}
-- Auto-Dig (Paket 4.4) je Spieler: Merker aus Perks.collectTick (war es im letzten Takt aktiv, ist
-- "Tank voll" für die aktuelle Füllung schon gemeldet?). Nur im Speicher, nicht gespeichert.
local autoDig: { [Player]: any } = {}
-- Münz-Faktor im zuletzt gesendeten Zustand: Läuft der Münz-Boost ab, sendet der Takt neu, damit die
-- Anzeige (pricePerSand, coinMultiplier) nicht veraltet.
local sentCoinMultiplier: { [Player]: number } = {}
-- Lagerstätten je Spieler (Überarbeitung Ü2, Logic/Deposits). Nur im Speicher, nicht gespeichert.
local depositStates: { [Player]: any } = {}
-- Zuletzt gesendetes "sammelt" (Halten des Auto-Dig oder Stich vor kurzem), damit der Takt beim
-- Wechsel neu sendet.
local sentDigging: { [Player]: boolean } = {}
-- Letzte Meldung "Hier ist nichts mehr" (os.clock), höchstens eine je EMPTY_NOTICE_SECONDS.
local emptyNoticeAt: { [Player]: number } = {}
local EMPTY_NOTICE_SECONDS = 2

-- Terrain-Materialien, in die gestochen werden darf (wie Controllers/Dig: Data/Terrain plus die
-- Materialien aller Sandsorten).
local diggable: { [Enum.Material]: boolean } = {}
do
    local names: { string } = table.clone(TerrainData.diggableMaterials)
    for _, sandType in SandTypes.list do
        table.insert(names, sandType.terrainMaterial)
    end
    for _, name in names do
        local ok, material = pcall(function(): any
            return (Enum.Material :: any)[name]
        end)
        if ok and material ~= nil then
            diggable[material] = true
        end
    end
end

local function now(): number
    return os.clock()
end

-- Unix-Zeit für den Münz-Boost (echte Zeit, auch offline, Paket 4.4). Die Sammel-Uhr bleibt os.clock.
local function unixNow(): number
    return os.time()
end

-- Collecting.Options des Profils (Paket 4.4): Tank- und Münz-Faktor aus Pässen und Boost.
-- Freunde-Bonus (Paket 5.7): Faktor je Spieler, gesetzt vom Service Friends (Sand.setFriendFactor).
-- Er wirkt wie "2x Münzen" im Münz-Faktor (Verkauf, Anzeige, Sandsturm-Münzen über Sand.optionsFor), nicht im
-- Offline-Ertrag.
local friendFactors: { [Player]: number } = {}

local function optionsOf(profile: any, player: Player): any
    local options = Perks.options(profile, unixNow())
    -- Sammeln über die Zeit gibt es nur noch für Auto-Dig (Ü2): so viel wie Halten.
    options.rateMultiplier = DepositData.autoDigFactor
    local friends = friendFactors[player]
    if friends ~= nil and options.coinMultiplier ~= nil then
        options.coinMultiplier *= friends
    end
    return options
end

-- Setzt den Freunde-Faktor (ab 1) und sendet den Zustand neu, wenn er sich ändert.
function Sand.setFriendFactor(player: Player, factor: number)
    if player.Parent == nil then
        return
    end
    local old = friendFactors[player] or 1
    friendFactors[player] = if factor > 1 then factor else nil
    if old ~= factor and PlayerData ~= nil and PlayerData.get(player) ~= nil then
        Sand.refresh(player)
    end
end

-- Faktoren für Sammeln, Tank, Verkauf und Sandsturm des Spielers (Paket 4.4). Ohne Profil: keine
-- Faktoren (leere Options, wie vor 4.4). Andere Services (Upgrades beim Sandsturm) nutzen das.
function Sand.optionsFor(player: Player): any
    local profile = PlayerData.get(player)
    if profile == nil then
        return {}
    end
    return optionsOf(profile, player)
end

local function depositStateOf(player: Player): any
    local state = depositStates[player]
    if state == nil then
        state = Deposits.newState()
        depositStates[player] = state
    end
    return state
end

-- Sammelt der Spieler gerade (Anzeige): Auto-Dig hält oder ein Stich war vor kurzem.
local function isDigging(player: Player, holding: boolean): boolean
    return holding or Deposits.isDigging(depositStates[player], now())
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
        -- Mit den Faktoren VOR der Änderung (alter Tank), der Aufrufer schreibt erst danach.
        Collecting.update(stateOf(player), profile, now(), optionsOf(profile, player))
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
    local unix = unixNow()
    local options = optionsOf(profile, player)
    local snapshot: any = {
        coins = BigNum.serialize(BigNum.deserialize(profile.coins)),
        gems = profile.gems, -- Gems (Paket 4.1)
        tank = BigNum.serialize(BigNum.deserialize(profile.tank)),
        capacity = Collecting.capacityOf(profile, options), -- mit "Großer Tank" (Paket 4.4)
        rate = Collecting.rateOf(profile),
        toolId = Collecting.toolOf(profile).id,
        collecting = isDigging(player, state.holding), -- Auto-Dig oder Stich vor kurzem (Ü2)
        zoneId = zone.id,
        pricePerSand = Collecting.pricePerSand(profile, options), -- mit Münz-Faktor (Paket 4.4)
        nodes = Collecting.ownedNodes(profile),
        zonesUnlocked = Zones.unlockedMap(profile, SeasonClock.timeFor(player)), -- Event-Zone je nach Saison (Paket 5.5)
        sellBonusBp = effects.sellBonusBp,
        luckBonusBp = effects.luckBonusBp,
        collectionBonusBp = Collection.bonusBp(profile), -- Summe der fertigen Sets (Paket 2.6)
        windCrystals = Wind.crystalsOf(profile), -- Sandsturm (Paket 2.7)
        windBonusBp = Wind.bonusBp(profile),
        storm = Sandstorm.preview(profile, nil, options), -- Vorschau für Knopf und Fenster
        tutorialStep = Tutorial.stepOf(profile),
        pity = pityOf(profile), -- Kisten-Pity je Kiste (Paket 4.2)
        -- Gamepasses und Münz-Boost (Paket 4.4), fester Vertrag mit der Client-Oberfläche:
        passes = Passes.owned(profile), -- Kopie { [passId] = true }, nur bekannte Pässe
        autoDig = Perks.autoDigSetting(profile), -- Einstellung (auch ohne Pass)
        autoDigOwned = Perks.owns(profile, "autoDig"), -- Pass "Auto-Dig" vorhanden
        coinMultiplier = options.coinMultiplier, -- Münz-Faktor jetzt (Pass mal Boost mal Freunde-Bonus)
        friendFactor = friendFactors[player] or 1, -- Freunde-Bonus allein (Paket 5.7), nur für den Hinweis im Freunde-Menü
        coinBoostSeconds = Perks.coinBoostSeconds(profile, unix), -- Restsekunden, Server-Uhr
    }
    sentCoinMultiplier[player] = options.coinMultiplier
    sentDigging[player] = snapshot.collecting
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
    for name, value in ToolLook.attributesFor(profile, isDigging(player, stateOf(player).holding)) do
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
    if profile == nil or not Zones.isUnlocked(profile, zoneId, SeasonClock.timeFor(player)) then
        return false
    end
    Collecting.setZone(stateOf(player), profile, zoneId, now(), optionsOf(profile, player))
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
    local options = optionsOf(profile, player)
    -- Überarbeitung Ü2: Sammeln über die Zeit nur noch mit aktivem Auto-Dig. Von Hand wird gestochen
    -- (Remote Stab); ein SetCollecting(true) ohne Pass bewirkt nichts.
    local wanted = Perks.autoDigActive(profile)
    local result = Collecting.setHolding(state, profile, wanted and canCollect(player), now(), options)
    if result.full and holding then
        notify(player, { kind = "tankFull" })
    end
    local tutorialChanged = result.added > 0 and Tutorial.evaluate(profile)
    if result.added > 0 or tutorialChanged or wasHolding ~= state.holding then
        sync(player)
    end
end

-- Liegt unter dem Punkt grabbarer Sand? Strahl von oben nur auf das Terrain (auf dem Server ist es
-- unverformt, Löcher gibt es nur beim Client).
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }
terrainParams.IgnoreWater = true

local function sandUnder(x: number, y: number, z: number): boolean
    local reach = DepositData.reach
    local origin = Vector3.new(x, y + reach.rayUpStuds, z)
    local result = workspace:Raycast(origin, Vector3.new(0, -reach.rayLengthStuds, 0), terrainParams)
    return result ~= nil and result.Instance == workspace.Terrain and diggable[result.Material] == true
end

-- Höhe der Sandoberfläche bei (x, z), gesucht von `yHint` + upStuds nach unten (Überarbeitung Ü3:
-- Fundstellen). nil, wenn dort kein grabbarer Sand liegt.
function Sand.sandSurface(x: number, yHint: number, z: number, upStuds: number, lengthStuds: number): number?
    local origin = Vector3.new(x, yHint + upStuds, z)
    local result = workspace:Raycast(origin, Vector3.new(0, -lengthStuds, 0), terrainParams)
    if result == nil or result.Instance ~= workspace.Terrain or diggable[result.Material] ~= true then
        return nil
    end
    return result.Position.Y
end

-- Wie oft der Spieler die Zelle bei (x, z) schon angestochen hat (0 = unberührt oder wieder voll).
function Sand.dugAt(player: Player, x: number, z: number): number
    local state = depositStates[player]
    return if state ~= nil then Deposits.dugAt(state, x, z, now()) else 0
end

-- Andere Services hören auf angenommene Stiche (Überarbeitung Ü3: Finds für Fundstellen). Ein Listener
-- bekommt (player, profile, { zoneId, point, root, layer, seconds }) und darf nicht warten.
local stabListeners: { (Player, any, any) -> () } = {}

function Sand.addStabListener(listener: (Player, any, any) -> ())
    table.insert(stabListeners, listener)
end

local function notifyStab(player: Player, profile: any, info: any)
    for _, listener in stabListeners do
        local co = coroutine.create(listener)
        local ok, err = coroutine.resume(co, player, profile, info)
        if coroutine.status(co) ~= "dead" then
            coroutine.close(co)
            warn("[Sand] Ein Stich-Listener hat gewartet und wird abgebrochen")
        elseif not ok then
            warn(`[Sand] Stich-Listener fehlgeschlagen: {tostring(err)}`)
        end
    end
end

-- Ein Stich (Überarbeitung Ü2). Ergebnis an den Client (StabResult), Tank neu senden.
local function onStab(player: Player, x: number, y: number, z: number, held: boolean)
    local profile = PlayerData.get(player)
    if profile == nil then
        return
    end
    local root = aliveRoot(player)
    local state = stateOf(player)
    local options = optionsOf(profile, player)
    local toolId = Collecting.toolOf(profile).id
    local result: any
    if root == nil or nearSellStand(player) then
        result = { ok = false, reason = "badInput", added = 0, clean = false, full = false, emptyNow = false, seconds = 0 }
    elseif Deposits.tooSoon(depositStateOf(player), now(), Collecting.toolOf(profile).id) then
        -- Günstige Vorprüfung des Takts vor Strahl und Rechnung (Review Ü2, L1).
        result = { ok = false, reason = "tooSoon", added = 0, clean = false, full = false, emptyNow = false, seconds = 0 }
    else
        local p = root.Position
        local deposit = depositStateOf(player)
        local wasDigging = Deposits.isDigging(deposit, now())
        result = Deposits.stab(deposit, {
            now = now(),
            root = { x = p.X, y = p.Y, z = p.Z },
            point = { x = x, y = y, z = z },
            reachMax = DigAim.reach(toolId).max,
            toolId = toolId,
            held = held,
            isSand = sandUnder(x, y, z),
            space = Collecting.space(profile, options),
            rate = Collecting.rateOf(profile),
        })
        if result.ok then
            -- Stechen und Auto-Dig schließen sich aus (Review Ü2, M1): ein laufendes Halten erst beenden.
            if state.holding then
                Collecting.setHolding(state, profile, false, now(), options)
            end
            if result.added > 0 then
                Collecting.addSand(profile, result.added)
            end
            local zoneId = Collecting.zoneOf(profile).id
            state.findSeconds[zoneId] = (state.findSeconds[zoneId] or 0) + result.seconds
            notifyStab(player, profile, {
                zoneId = zoneId,
                point = { x = x, y = y, z = z },
                root = { x = p.X, z = p.Z },
                layer = result.layer,
                seconds = result.seconds,
            })
            local tutorialChanged = result.added > 0 and Tutorial.evaluate(profile)
            if result.added > 0 or tutorialChanged or not wasDigging then
                sync(player)
            end
        end
    end
    if (result.full or result.reason == "empty") and now() - (emptyNoticeAt[player] or -math.huge) >= EMPTY_NOTICE_SECONDS then
        emptyNoticeAt[player] = now()
        notify(player, { kind = if result.full then "tankFull" else "cellEmpty" })
    end
    Net.fire(player, "StabResult", {
        ok = result.ok,
        reason = result.reason,
        added = result.added,
        layer = result.layer,
        clean = result.clean,
        emptyNow = result.emptyNow,
        x = x,
        z = z,
    })
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
    local earned, sold = Collecting.sell(stateOf(player), profile, now(), optionsOf(profile, player))
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
        if not nearby and not IS_STUDIO then
            -- Überarbeitung Ü1: im veröffentlichten Place kein grauer Block, sondern ein roter Fehler im Log.
            task.spawn(error, `[Welt] FEHLT im Place: Händlerstand der Zone {area.id} (Teil mit Tag "{tag}" nahe x={pos.x}, z={pos.z})`, 0)
        elseif not nearby then
            local part = Instance.new("Part")
            part.Name = `SellStand_Platzhalter_{area.id}`
            part.Anchored = true
            part.Size = PLACEHOLDER_SIZE
            part.Color = PLACEHOLDER_COLOR
            part.Position = Vector3.new(pos.x, pos.y, pos.z)
            part:AddTag(tag)
            part.Parent = workspace
            warn(`[Sand] Kein Händlerstand für Zone {area.id}: Platzhalter angelegt (nur in Studio)`)
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

-- Ein Spieler pro Tick: Position proben, laufendes Sammeln abrechnen, Auto-Dig, Änderungen senden.
local function tickPlayer(player: Player, state: any, t: number)
    local near = nearSellStand(player)
    wasNearStand[player] = near
    local profile = PlayerData.get(player)
    if profile == nil then
        state.holding = false
        return
    end
    local options = optionsOf(profile, player)
    -- Abrechnen und Auto-Dig in einem reinen Schritt (Logic/Perks.collectTick, Lune-Tests).
    -- Wie canCollect, mit der Standprobe von eben (lebender Charakter, nicht am Stand).
    -- Während gestochen wird, sammelt Auto-Dig nicht zusätzlich (Review Ü2, M1).
    local collect = aliveRoot(player) ~= nil and not near and not Deposits.isDigging(depositStates[player], t)
    local result = Perks.collectTick(state, profile, t, options, collect, autoDig[player])
    autoDig[player] = result.memory
    if result.notifyFull then
        notify(player, { kind = "tankFull" })
    end
    local tutorialChanged = result.added > 0 and Tutorial.evaluate(profile)
    local changed = result.changed or tutorialChanged
    -- Münz-Boost abgelaufen (oder neu gültig): Zustand neu senden, damit der Preis stimmt.
    local sent = sentCoinMultiplier[player]
    if sent ~= nil and sent ~= options.coinMultiplier then
        changed = true
    end
    -- Stich-Anzeige abgelaufen (Ü2): "sammelt" neu senden.
    if sentDigging[player] ~= nil and sentDigging[player] ~= isDigging(player, state.holding) then
        changed = true
    end
    if changed then
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
    Net.on("Stab", onStab)
    Net.on("Sell", onSell)

    PlayerData.onLoaded(function(player: Player, profile: any)
        states[player] = Collecting.newState(now())
        depositStates[player] = Deposits.newState()
        autoDig[player] = nil
        -- Zonen, deren Knoten schon gekauft sind (alte Spielstände), still freischalten.
        Zones.unlockNew(profile)
        if not Zones.isUnlocked(profile, profile.currentZone, SeasonClock.timeFor(player)) then
            profile.currentZone = "dunes" -- eine gesperrte aktuelle Zone nie übernehmen
        end
        Sand.refresh(player)
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        states[player] = nil
        wasNearStand[player] = nil
        autoDig[player] = nil
        depositStates[player] = nil
        sentDigging[player] = nil
        emptyNoticeAt[player] = nil
        sentCoinMultiplier[player] = nil
        friendFactors[player] = nil
    end)

    task.spawn(function()
        while true do
            task.wait(TICK_SECONDS)
            tick()
        end
    end)
end

return Sand
