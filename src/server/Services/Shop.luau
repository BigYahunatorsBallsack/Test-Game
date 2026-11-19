--!strict
-- Shop-Service (Paket 4.1)
-- Zuständig: Käufe (ProcessReceipt, idempotent), Gem-Pakete; später Gamepasses und weitere
-- Produkte (4.4) und Policy-Funktionen (ArePaidRandomItemsRestricted, 4.6).
--
-- Die Regeln der Kaufabwicklung stehen im reinen Modul Logic/Purchases (Lune-Tests). Hier wird nur
-- angeschlossen: MarketplaceService.ProcessReceipt (genau einmal gesetzt), PlayerData als Speicher
-- (speichern und warten, bis die PurchaseId in profile.LastSavedData steht), die Uhr, Notify an den
-- Client und die Anzeige (Sand.refresh). PurchaseGranted kommt erst, wenn der Kauf nachweislich
-- gespeichert ist, sonst NotProcessedYet; Roblox ruft dann später erneut auf (auch auf einem
-- anderen Server). Vom Beleg zählen nur PlayerId, ProductId und PurchaseId, Menge und Preis kommen
-- aus den Daten.
--
-- Für andere Services (4.4): Shop.registerProduct(produktId, handler) hängt ein weiteres Developer
-- Product aus Data/Products ein (Handler siehe Logic/Purchases), in Init oder Start. Nach allen
-- Start() prüft Shop.AfterStart, dass jedes Produkt mit echter ProductId (kein Gamepass) einen
-- Handler hat, sonst bricht der Start mit einer Fehlermeldung ab.
--
-- Studio-Hilfe (nur in Studio): In der Befehlszeile (Ansicht "Server")
--   game.Players.Name:SetAttribute("DebugPurchase", "gems_550")        -- neuer Kauf (zufällige PurchaseId)
--   game.Players.Name:SetAttribute("DebugPurchase", "gems_550:fest1")  -- feste PurchaseId (Doppelkauf testen)
-- Der künstliche Beleg läuft über Purchases.processPack (Paket über die Paket-ID, PurchaseId mit
-- Präfix "studio:") durch denselben Ablauf wie ein echter Kauf. Das Attribut wird danach gelöscht,
-- damit derselbe Wert erneut auslöst. Außerhalb von Studio ist der Weg doppelt gesperrt: kein
-- Attribut-Listener und Purchases mit allowDebug = false.

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Studio-Hilfe: Attributname am Spieler und Form des Werts ("paketId" oder "paketId:feste_id").
local DEBUG_PURCHASE_ATTRIBUTE = "DebugPurchase"
local DEBUG_PURCHASE_PATTERN = "^([%w_]+):?([%w_%-]*)$"
local DEBUG_PURCHASE_MAX_LENGTH = 64

local shared = ReplicatedStorage:WaitForChild("Shared")
local Purchases = require(shared:WaitForChild("Logic"):WaitForChild("Purchases") :: ModuleScript) :: any

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local Net: any = nil

local Shop = {}

local purchases: any = nil
local receiptHooked = false

local function log(message: string)
    warn(`[Shop] {message}`)
end

-- Meldung an den Client über den vorhandenen Notify-Weg ({ kind = ..., Daten }).
local function notify(userId: number, kind: string, data: { [string]: any })
    local player = Players:GetPlayerByUserId(userId)
    if player == nil then
        return
    end
    local payload = table.clone(data)
    payload.kind = kind
    Net.fire(player, "Notify", payload)
end

-- Zustand des Spielers neu senden (Gem-Stand im StateSync). Ein Fehler hier ändert nichts am Kauf.
local function refresh(userId: number)
    local player = Players:GetPlayerByUserId(userId)
    if player == nil then
        return
    end
    local ok, err = pcall(Sand.refresh, player)
    if not ok then
        log(`Anzeige nach dem Kauf fehlgeschlagen: {tostring(err)}`)
    end
end

-- ProcessReceipt: nur die drei Felder des Belegs gehen weiter. Jeder Fehler ergibt NotProcessedYet.
local function onProcessReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
    local ok, decision = pcall(function(): string
        return purchases.process({
            PlayerId = receiptInfo.PlayerId,
            ProductId = receiptInfo.ProductId,
            PurchaseId = receiptInfo.PurchaseId,
        })
    end)
    if not ok then
        log(`ProcessReceipt: Fehler {tostring(decision)}`)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    if decision == "granted" then
        refresh(receiptInfo.PlayerId)
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
    return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Studio-Hilfe: künstlicher Beleg über das Attribut DebugPurchase. Nur in Studio verbunden.
local function connectStudioHelper(player: Player)
    player:GetAttributeChangedSignal(DEBUG_PURCHASE_ATTRIBUTE):Connect(function()
        local value = player:GetAttribute(DEBUG_PURCHASE_ATTRIBUTE)
        if value == nil then
            return
        end
        player:SetAttribute(DEBUG_PURCHASE_ATTRIBUTE, nil) -- derselbe Wert soll erneut auslösen
        if type(value) ~= "string" or #value > DEBUG_PURCHASE_MAX_LENGTH then
            log(`Studio: {DEBUG_PURCHASE_ATTRIBUTE} erwartet Text wie "gems_550" oder "gems_550:fest1"`)
            return
        end
        local packId, fixedId = string.match(value, DEBUG_PURCHASE_PATTERN)
        if packId == nil then
            log(`Studio: "{value}" hat nicht die Form "gems_550" oder "gems_550:fest1"`)
            return
        end
        local purchaseId = if fixedId ~= nil and fixedId ~= "" then fixedId else HttpService:GenerateGUID(false)
        local decision = purchases.processPack(player.UserId, packId, purchaseId)
        print(`[Shop] Studio: Kauf {packId} ({Purchases.DEBUG_PREFIX}{purchaseId}) für {player.Name}: {decision}`)
        if decision == "granted" then
            refresh(player.UserId)
        end
    end)
end

-- Hängt ein weiteres Developer Product ein (Paket 4.4). `productId` ist die ID aus Data/Products.
function Shop.registerProduct(productId: string, handler: any)
    purchases.register(productId, handler)
end

function Shop.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)

    purchases = Purchases.new({
        getProfile = function(userId: number): any
            return PlayerData.getByUserId(userId)
        end,
        isSessionActive = function(userId: number): boolean
            return Players:GetPlayerByUserId(userId) ~= nil and PlayerData.isActive(userId)
        end,
        -- Offene Belege kommen oft gleich beim Beitreten: solange der Spieler da ist und sein
        -- Profil noch lädt, wartet der Kauf (begrenzt) statt sofort NotProcessedYet zu geben.
        isLoading = function(userId: number): boolean
            return Players:GetPlayerByUserId(userId) ~= nil and not PlayerData.isActive(userId)
        end,
        saveAndWait = function(userId: number, purchaseId: string, timeoutSeconds: number): boolean
            return PlayerData.saveAndWait(userId, function(savedData: any): boolean
                return Purchases.hasReceipt(savedData, purchaseId)
            end, timeoutSeconds)
        end,
        now = os.time,
        clock = os.clock,
        wait = function(seconds: number)
            task.wait(seconds)
        end,
        log = log,
        notify = notify,
        allowDebug = RunService:IsStudio(),
    })
end

function Shop.Start()
    -- Roblox kennt nur einen Rückruf je Spiel: genau einmal setzen.
    if receiptHooked then
        error("[Shop] ProcessReceipt ist schon gesetzt")
    end
    receiptHooked = true
    MarketplaceService.ProcessReceipt = onProcessReceipt

    Players.PlayerRemoving:Connect(function(player: Player)
        purchases.forget(player.UserId)
    end)
    if RunService:IsStudio() then
        Players.PlayerAdded:Connect(connectStudioHelper)
        for _, player in Players:GetPlayers() do
            connectStudioHelper(player)
        end
    end
end

-- Läuft nach allen Start() (Server-Bootstrap), wenn alle Handler registriert sind. Ein Fehler wird laut gemeldet, stoppt aber den Server nicht. Ein Produkt mit
-- echter ProductId ohne Handler würde bezahlt, aber nie gutgeschrieben (NotProcessedYet für immer).
function Shop.AfterStart()
    local missing: { string } = purchases.missingHandlers()
    if #missing > 0 then
        error(`[Shop] Produkte mit ProductId ohne Handler (Shop.registerProduct fehlt): {table.concat(missing, ", ")}`)
    end
end

return Shop
