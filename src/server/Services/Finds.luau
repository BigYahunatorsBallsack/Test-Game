--!strict
-- Finds-Service (Paket 2.6)
-- Zuständig: Fundstücke auswürfeln, in die Sammlung buchen, doppelte Funde sofort verkaufen und
-- Meldungen an den Client schicken.
--
-- Die Regeln stehen in den reinen Modulen Logic/FindRoll (Chance, Seltenheit, Auswahl, Wert) und
-- Logic/Collection (Sammlung, Sets, Bonus, Buchung), beide mit Lune-Tests. Hier hängen nur
-- Zeit, Zufall, Profil und Remotes dran.
--
-- Der Client sendet nichts: Funde entstehen allein aus der Sammelzeit, die der Server in
-- Collecting.update misst (Sand floss wirklich in den Tank). Es gibt darum keine Remote vom
-- Client zum Server. Das Wetter liest der Server aus seiner eigenen Zeit (GetServerTimeNow), den
-- Glücks-Boost (Daily Reward Tag 5, Paket 5.1) aus seiner Unix-Uhr (os.time), wie den Münz-Boost.
--
-- Studio-Hilfe (nur in Studio, in der Befehlszeile der Ansicht "Server"): Am Spieler das Attribut "DebugFindSet" auf eine Set-ID setzen
-- (z. B. "dunes_set_1") oder "DebugFindZone" auf eine Zonen-ID (z. B. "oasis"), dann trägt der
-- Server alle Fundstücke dieses Sets oder der Zone in die Sammlung ein.
--
-- Fundstellen (Überarbeitung Ü3): Sand meldet jeden angenommenen Stich (Sand.addStabListener). Logic/
-- FindSpots legt je Spieler Stellen um die Stichstelle an und meldet Treffer; ein Treffer würfelt mit
-- FindRoll.fromSpot (unveränderte Quotentabelle). Der Client bekommt die Lage seiner Stellen über
-- "FindSpots" (nur Lage). Der bisherige Würfel über die Sammelzeit bleibt als Grundchance mit
-- Data/FindSpots.baseChanceFactor und ohne die alte Regel "Erster Fund nach 60 s" (die übernimmt
-- FindSpots nach firstFindStabs Stichen).
--
-- Für andere Services (Paket 4.5): `Finds.addFindListener(fn)` meldet jeden gebuchten Fund mit
-- fn(player, profile, { findId, rarityId, isNew, studio }). Der Offers-Service startet so das
-- Starterpaket-Fenster. Ein Listener darf nicht warten; ein Fehler darin wird gemeldet und ändert
-- nichts am gebuchten Fund. Die Listener laufen nach der Fund-Meldung und vor Sand.refresh, der
-- neue Zustand (auch ein gestartetes Angebot) geht also mit demselben StateSync hinaus. Die
-- Studio-Hilfen DebugFindSet/DebugFindZone melden jedes neu eingetragene Fundstück genauso
-- (studio = true). Kisten-Items laufen nie hier durch (Logic/CrateOpen), sie lösen nichts aus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wie oft der Server die gesammelte Zeit würfelt (s). Gleich wie der Sand-Tick.
local TICK_SECONDS = 0.25
-- Mehr Sammelzeit pro Zone und Tick zählt nie (Schutz gegen Ausreißer, z. B. nach einem Hänger).
local MAX_SECONDS_PER_TICK = 10
local DEBUG_SET_ATTRIBUTE = "DebugFindSet"
local DEBUG_ZONE_ATTRIBUTE = "DebugFindZone"

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local FindRoll = loadShared("Logic", "FindRoll")
local Collection = loadShared("Logic", "Collection")
local BigNum = loadShared("Logic", "BigNum")
local FindsData = loadShared("Data", "Finds")
local ZonesData = loadShared("Data", "Zones")
local ZoneRules = loadShared("Logic", "Zones")
local FindSpots = loadShared("Logic", "FindSpots")
local FindSpotsData = loadShared("Data", "FindSpots")

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local Events: any = nil
local Net: any = nil

local Finds = {}

-- Listener für gebuchte Funde (Finds.addFindListener), in der Reihenfolge der Anmeldung.
export type FindInfo = { findId: string, rarityId: string, isNew: boolean, studio: boolean }
local findListeners: { (Player, any, FindInfo) -> () } = {}

local random = Random.new()
-- Sammelzeit dieser Sitzung je Spieler (für "Erster Fund sicher").
local sessionSeconds: { [Player]: number } = {}
-- Fundstellen je Spieler (Ü3), nur im Speicher.
local spotStates: { [Player]: any } = {}

local function serverTime(): number
    return workspace:GetServerTimeNow()
end

-- Schickt dem Spieler die ganze Sammlung zur Anzeige.
local function syncCollection(player: Player)
    local profile = PlayerData.get(player)
    if profile == nil then
        return
    end
    Net.fire(player, "CollectionSync", Collection.summary(profile))
end

-- Meldet einen gebuchten Fund an alle Listener. Jeder läuft für sich in pcall, ein Fehler wird nur
-- gemeldet (der Fund ist schon gebucht).
local function notifyListeners(player: Player, profile: any, info: FindInfo)
    for _, listener in findListeners do
        -- Ein Listener darf nicht warten (sonst stünden die Funde aller Spieler still): eigene
        -- Koroutine, bei Yield schließen, wie bei den Snapshot-Providern in Sand.
        local co = coroutine.create(listener)
        local ok, err = coroutine.resume(co, player, profile, info)
        if coroutine.status(co) ~= "dead" then
            coroutine.close(co)
            warn(`[Finds] Ein Fund-Listener hat für {player.Name} gewartet und wird abgebrochen`)
        elseif not ok then
            warn(`[Finds] Fund-Listener für {player.Name} fehlgeschlagen: {tostring(err)}`)
        end
    end
end

-- Bucht einen Fund und meldet ihn dem Spieler.
local function award(player: Player, profile: any, roll: any, zoneId: string)
    local recorded = Collection.record(profile, roll.find.id, roll.value)
    if recorded == nil then
        return
    end
    Net.fire(player, "Notify", {
        kind = "find",
        findId = recorded.findId,
        zoneId = zoneId,
        rarityId = recorded.rarityId,
        isNew = recorded.isNew,
        count = recorded.count,
        coins = if recorded.coins ~= nil then BigNum.serialize(recorded.coins) else nil,
        setId = recorded.setId,
        setHave = recorded.setHave,
        setSize = recorded.setSize,
        setCompleted = recorded.setCompleted,
        zoneBookCompleted = recorded.zoneBookCompleted,
        bonusBp = recorded.bonusBpAfter,
    })
    -- Nach der Fund-Meldung (der Client zeigt erst den Reveal, dann ein Angebot), vor dem Refresh.
    notifyListeners(player, profile, { findId = recorded.findId, rarityId = recorded.rarityId, isNew = recorded.isNew, studio = false })
    syncCollection(player)
    Sand.refresh(player) -- Münzen aus einem Duplikat, der neue Preis mit Bonus, gestartete Angebote
end

-- Schickt dem Spieler die Lage seiner Fundstellen.
local function sendSpots(player: Player)
    local state = spotStates[player]
    Net.fire(player, "FindSpots", if state ~= nil then FindSpots.view(state) else {})
end

-- Ein angenommener Stich (Sand.addStabListener, Ü3).
local function onStab(player: Player, profile: any, info: any)
    if ZonesData.eventById[info.zoneId] ~= nil then
        return -- Event-Zonen haben keine Funde
    end
    local state = spotStates[player]
    if state == nil then
        return -- erst nach onLoaded, nach PlayerRemoving nicht mehr
    end
    local rateFactor = FindRoll.chanceFactor(profile, info.zoneId, serverTime(), nil, os.time())
    if rateFactor <= 0 then
        return -- Zone ohne Funde: die Stellen bleiben unberührt
    end
    local outcome = FindSpots.onStab(state, {
        now = os.clock(),
        zoneId = info.zoneId,
        point = info.point,
        root = info.root,
        layer = info.layer,
        seconds = info.seconds,
        rateFactor = rateFactor,
        neverFound = not state.firstSpawned and Collection.distinctFound(profile) == 0,
        random = function(): number
            return random:NextNumber()
        end,
        surfaceAt = function(x: number, z: number): number?
            -- Nur in derselben Zone und in einer noch unberührten Zelle (sonst wäre die Schicht geschenkt).
            if ZoneRules.zoneAt({ x = x, y = info.point.y, z = z }) ~= info.zoneId or Sand.dugAt(player, x, z) > 0 then
                return nil
            end
            return Sand.sandSurface(x, info.point.y, z, FindSpotsData.rayUpStuds, FindSpotsData.rayLengthStuds)
        end,
    })
    if outcome.found ~= nil then
        local roll = if outcome.found.forced
            then FindRoll.build(profile, info.zoneId, "common", random:NextNumber(), true)
            else FindRoll.fromSpot(profile, info.zoneId, function(): number
                return random:NextNumber()
            end)
        if roll ~= nil then
            award(player, profile, roll, info.zoneId)
        end
    end
    if outcome.changed then
        sendSpots(player)
    end
end

-- Würfelt die gesammelte Zeit eines Spielers.
local function tickPlayer(player: Player)
    local profile = PlayerData.get(player)
    if profile == nil then
        return
    end
    local taken = Sand.takeFindSeconds(player)
    for zoneId, seconds in taken do
        local clamped = math.min(seconds, MAX_SECONDS_PER_TICK)
        if ZonesData.eventById[zoneId] ~= nil then
            -- Event-Zonen (Paket 5.5) haben keine Fundstücke: ihre Sammelzeit zählt Saison-Punkte.
            local counted, err = pcall(Events.addZoneSeconds, player, zoneId, clamped)
            if not counted then
                warn(`[Finds] Saison-Punkte für {player.Name} fehlgeschlagen: {tostring(err)}`)
            end
            continue
        end
        -- Jede Zone für sich in pcall: ein Fehler in einer Zone darf die Sekunden der nächsten (zum
        -- Beispiel der Event-Zone nach einem Zonenwechsel im selben Takt) nicht verwerfen.
        local rolled, rollErr = pcall(function()
            local total = (sessionSeconds[player] or 0) + clamped
            sessionSeconds[player] = total
            local roll = FindRoll.roll({
                profile = profile,
                zoneId = zoneId,
                seconds = clamped,
                serverTime = serverTime(),
                unixTime = os.time(), -- Glücks-Boost (boosts.luckUntil), Paket 5.1
                sessionSeconds = total,
                chanceFactor = FindSpotsData.baseChanceFactor, -- Ü3: Fundstellen sind der Hauptweg
                noForced = true, -- Ü3: "Erster Fund sicher" kommt über eine Fundstelle
                random = function(): number
                    return random:NextNumber()
                end,
            })
            if roll ~= nil then
                award(player, profile, roll, zoneId)
            end
        end)
        if not rolled then
            warn(`[Finds] Fehler beim Würfeln für {player.Name} in {zoneId}: {tostring(rollErr)}`)
        end
    end
end

local function tick()
    -- Abgelaufene Fundstellen entfernen und melden (Ü3).
    local t = os.clock()
    for player, state in spotStates do
        if FindSpots.expire(state, t) then
            pcall(sendSpots, player)
        end
    end
    for _, player in Players:GetPlayers() do
        local ok, err = pcall(tickPlayer, player)
        if not ok then
            warn(`[Finds] Fehler beim Würfeln für {player.Name}: {tostring(err)}`)
        end
    end
end

-- Studio-Hilfe: füllt ein Set oder eine Zone in der Sammlung.
local function connectStudioHelper(player: Player)
    local function apply(attribute: string)
        local value = player:GetAttribute(attribute)
        local profile = PlayerData.get(player)
        if type(value) ~= "string" or profile == nil then
            return
        end
        local added: { any } = {}
        for _, find in FindsData.list do
            local matches = if attribute == DEBUG_SET_ATTRIBUTE then find.setId == value else find.zoneId == value
            if matches and Collection.countOf(profile, find.id) == 0 then
                profile.finds[find.id] = 1
                table.insert(added, find)
            end
        end
        print(`[Finds] Studio: {player.Name} {attribute} = {value}, {#added} Fundstücke eingetragen`)
        -- Wie echte Funde an die Listener melden (zum Beispiel startet ein Selten-Fund das Starterpaket).
        for _, find in added do
            notifyListeners(player, profile, { findId = find.id, rarityId = find.rarityId, isNew = true, studio = true })
        end
        syncCollection(player)
        Sand.refresh(player)
    end
    for _, attribute in { DEBUG_SET_ATTRIBUTE, DEBUG_ZONE_ATTRIBUTE } do
        player:GetAttributeChangedSignal(attribute):Connect(function()
            apply(attribute)
        end)
    end
end

-- Meldet jeden gebuchten Fund an `listener` (Paket 4.5). Im Init des anderen Services anmelden, dann
-- gilt er vom ersten Takt an (alle Init laufen vor allen Start). Der Listener darf nicht warten.
function Finds.addFindListener(listener: (Player, any, FindInfo) -> ())
    table.insert(findListeners, listener)
end

function Finds.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Events = require(servicesFolder:WaitForChild("Events") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
    Sand.addStabListener(onStab)
end

function Finds.Start()
    PlayerData.onLoaded(function(player: Player, _profile: any)
        sessionSeconds[player] = 0
        spotStates[player] = FindSpots.newState()
        syncCollection(player)
        sendSpots(player)
    end)
    local function onAdded(player: Player)
        if RunService:IsStudio() then
            connectStudioHelper(player)
        end
    end
    for _, player in Players:GetPlayers() do
        onAdded(player)
    end
    Players.PlayerAdded:Connect(onAdded)
    Players.PlayerRemoving:Connect(function(player: Player)
        sessionSeconds[player] = nil
        spotStates[player] = nil
    end)

    task.spawn(function()
        while true do
            task.wait(TICK_SECONDS)
            tick()
        end
    end)
end

return Finds
