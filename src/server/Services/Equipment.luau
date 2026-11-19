--!strict
-- Equipment-Service (Paket 4.3)
-- Zuständig: Kisten-Items ausrüsten (EquipItem) und verschmelzen (MergeItem). Die Regeln stehen im
-- reinen Modul Logic/Equipment (Lune-Tests in tests/equipment.spec.luau); hier hängen nur Remotes,
-- Profil, Anzeige und die Attribute für alle Spieler dran.
--
-- Der Client schickt nur Slot und Item-ID (EquipItem) oder die Item-ID (MergeItem), Schema und
-- Rate-Limit stehen in RemoteSpec. Besitz, Slot, Kopien und Bonus prüft und rechnet allein der Server.
-- Beide Aufrufe laufen ohne Warten in einem Zug (Logic/Equipment prüft zuerst, schreibt dann), ein
-- zweiter schneller Aufruf kann also nichts doppelt verbrauchen. Antwort: `{ ok, reason?, itemId?,
-- stars?, copies?, consumed?, bonusBp? }`, ohne Profil-Interna.
--
-- Vor jeder Änderung wird das offene Sammelfenster mit der alten Rate abgerechnet (`Sand.settle`),
-- sonst gälte die neue Rate rückwirkend. Danach schickt `Sand.refresh` den StateSync und setzt die
-- Spieler-Attribute SkinId, CompanionId und ToolVariantId (Sand.publishLook), damit alle Clients die
-- Ausrüstung sehen. Ausrüsten und Verschmelzen bleiben auch bei gesperrten Zufallsitems erlaubt: Sie
-- kaufen und würfeln nichts.
--
-- Der StateSync bekommt über `Sand.addSnapshotProvider` die Felder `inventory`, `equipped`,
-- `itemStars` und `equipBonusBp` (Kopien, nie das Profil selbst).
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"): Exemplare eines Items ins Inventar legen,
-- damit sich Ausrüsten und Verschmelzen ohne Kistenöffnungen testen lassen:
--   game.Players.Name:SetAttribute("DebugItem", "skin_common_1:5")   -- 5 Exemplare dazu
--   game.Players.Name:SetAttribute("DebugItem", "skin_common_1")     -- 1 Exemplar dazu
-- Das Attribut wird danach zurückgesetzt, derselbe Befehl wirkt also wieder. Außerhalb von Studio wird
-- es nie gelesen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DEBUG_ITEM_ATTRIBUTE = "DebugItem"
local DEBUG_ITEM_MAX_COUNT = 50
local ERROR_REASON = "error"

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local EquipmentLogic = loadShared("Logic", "Equipment")
local CrateItems = loadShared("Data", "CrateItems")

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local Net: any = nil

local Equipment = {}

local function log(text: string)
    warn(`[Equipment] {text}`)
end

-- Kopie nur der Zähler (ID -> Anzahl) je Art, für den StateSync.
local function inventoryCopy(profile: any): { [string]: { [string]: number } }
    local result: { [string]: { [string]: number } } = {}
    for _, field in EquipmentLogic.INVENTORY_FIELDS do
        local bucket: { [string]: number } = {}
        local source = if type(profile.inventory) == "table" then profile.inventory[field] else nil
        if type(source) == "table" then
            for itemId, count in source do
                if type(itemId) == "string" and type(count) == "number" then
                    bucket[itemId] = count
                end
            end
        end
        result[field] = bucket
    end
    return result
end

local function snapshotFor(player: Player): { [string]: any }
    local profile = PlayerData.get(player)
    if profile == nil then
        return {}
    end
    local equipped: { [string]: string } = {}
    for _, slot in EquipmentLogic.SLOTS do
        local item = EquipmentLogic.equippedItem(profile, slot)
        equipped[slot] = if item ~= nil then item.id else ""
    end
    local stars: { [string]: number } = {}
    if type(profile.itemStars) == "table" then
        for itemId, value in profile.itemStars do
            if type(itemId) == "string" and type(value) == "number" then
                stars[itemId] = EquipmentLogic.starsOf(profile, itemId)
            end
        end
    end
    return {
        inventory = inventoryCopy(profile),
        equipped = equipped,
        itemStars = stars,
        equipBonusBp = EquipmentLogic.bonusBp(profile),
    }
end

-- Rate, Attribute und Anzeige neu berechnen. Ein Fehler hier darf die schon gebuchte Änderung nicht
-- als Fehlschlag melden.
local function refresh(player: Player)
    local ok, err = pcall(Sand.refresh, player)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
end

-- Gemeinsamer Ablauf: Profil holen, Sammelfenster abrechnen, Aktion ohne Warten, Anzeige.
local function run(player: Player, label: string, action: (profile: any) -> any): any
    local profile = PlayerData.get(player)
    if profile == nil then
        return { ok = false, reason = "noProfile" }
    end
    local settled, settleErr = pcall(Sand.settle, player)
    if not settled then
        -- Ohne Abrechnung würde die neue Rate rückwirkend gelten: lieber abbrechen.
        log(`Abrechnung vor {label} fehlgeschlagen: {tostring(settleErr)}`)
        return { ok = false, reason = ERROR_REASON }
    end
    local ok, result = pcall(action, profile)
    if not ok then
        log(`{label} für {player.Name} fehlgeschlagen: {tostring(result)}`)
        return { ok = false, reason = ERROR_REASON }
    end
    -- Anzeige neu senden (die Abrechnung kann den Tank geändert haben), nur nicht bei einem
    -- Ausrüsten ohne Änderung (schon so ausgerüstet): Das würde die Optik aller Clients neu bauen.
    if not (result.ok == true and result.changed == false) then
        refresh(player)
    end
    return result
end

local function onEquipItem(player: Player, slot: string, itemId: string): any
    return run(player, `Ausrüsten von {itemId}`, function(profile: any): any
        return EquipmentLogic.equip(profile, slot, itemId)
    end)
end

local function onMergeItem(player: Player, itemId: string): any
    return run(player, `Verschmelzen von {itemId}`, function(profile: any): any
        return EquipmentLogic.merge(profile, itemId)
    end)
end

-- Studio-Hilfe: "itemId" oder "itemId:anzahl" legt Exemplare ins Inventar.
local function connectStudioHelper(player: Player)
    player:GetAttributeChangedSignal(DEBUG_ITEM_ATTRIBUTE):Connect(function()
        local value = player:GetAttribute(DEBUG_ITEM_ATTRIBUTE)
        local profile = PlayerData.get(player)
        if type(value) ~= "string" or profile == nil then
            return
        end
        local itemId, countText = string.match(value, "^([%w_]+):?(%d*)$")
        local item = if itemId ~= nil then CrateItems.byId[itemId] else nil
        if item == nil then
            log(`Studio: {tostring(value)}: unbekanntes Item`)
            return
        end
        local count = math.clamp(tonumber(countText) or 1, 1, DEBUG_ITEM_MAX_COUNT)
        local field = EquipmentLogic.INVENTORY_FIELDS[item.kind]
        local inventory = if type(profile.inventory) == "table" then profile.inventory else {}
        local bucket: { [string]: any } = if type(inventory[field]) == "table" then table.clone(inventory[field]) else {}
        local current = if type(bucket[item.id]) == "number" then bucket[item.id] else 0
        bucket[item.id] = current + count
        inventory[field] = bucket
        profile.inventory = inventory
        -- Zurücksetzen, damit derselbe Befehl ein zweites Mal wieder wirkt.
        player:SetAttribute(DEBUG_ITEM_ATTRIBUTE, nil)
        print(`[Equipment] Studio: {player.Name} hat jetzt {bucket[item.id]} x {item.id}`)
        refresh(player)
    end)
end

function Equipment.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Equipment.Start()
    Net.on("EquipItem", onEquipItem)
    Net.on("MergeItem", onMergeItem)

    if type(Sand.addSnapshotProvider) == "function" then
        Sand.addSnapshotProvider(snapshotFor)
    else
        log("Sand.addSnapshotProvider fehlt: der Client bekommt keine Ausrüstung")
    end

    if RunService:IsStudio() then
        local handled: { [Player]: boolean } = {}
        local function onPlayerAdded(player: Player)
            if handled[player] then
                return
            end
            handled[player] = true
            connectStudioHelper(player)
        end
        Players.PlayerAdded:Connect(onPlayerAdded)
        for _, player in Players:GetPlayers() do
            onPlayerAdded(player)
        end
        Players.PlayerRemoving:Connect(function(player: Player)
            handled[player] = nil
        end)
    end
end

return Equipment
