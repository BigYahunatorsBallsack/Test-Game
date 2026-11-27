--!strict
-- Offers-Service (Paket 4.5)
-- Zuständig: Angebote im Shop, zuerst das Starterpaket. Fenster starten (erster Fund ab "Selten",
-- alte Spielstände beim Laden), Zustand im StateSync und der Kauf-Handler je Angebot über
-- Shop.registerProduct.
--
-- Die Regeln stehen im reinen Modul Logic/Offers (Lune-Tests in tests/offers.spec.luau), die
-- Angebote in Data/Offers. Hier werden nur Finds, PlayerData, Sand, Shop und Notify angeschlossen.
-- Der Client sendet zu Angeboten nichts: Es gibt keine neue Remote. Gekauft wird über
-- MarketplaceService:PromptProductPurchase und ProcessReceipt (Shop, Logic/Purchases).
--
-- Ablauf:
--  * Fund gebucht (Finds.addFindListener, auch Studio-Funde aus DebugFindSet/DebugFindZone):
--    OffersLogic.onFind mit der Server-Uhr (os.time). Startet ein Angebot, wird `profile.offers` ohne
--    Warten als neue Tabelle zugewiesen und Notify { kind = "offerUnlocked", offerId, secondsLeft }
--    gesendet. Danach schickt Finds den neuen Zustand (Sand.refresh). Kisten-Items lösen nichts aus.
--  * Profil geladen: OffersLogic.migrateStart (alte Spielstände mit schon vorhandenem Selten-Fund
--    bekommen das Fenster ab jetzt), bei einer Änderung Sand.refresh. Keine Meldung: Der Client sieht
--    das aktive Angebot im StateSync und zeigt den Hinweis höchstens einmal pro Sitzung.
--  * StateSync (Sand.addSnapshotProvider): `offers = { [offerId] = { state, secondsLeft } }` mit der
--    Server-Uhr beim Snapshot. Läuft ein Angebot ab, zeigt der nächste Snapshot "expired" (der Client
--    zählt selbst herunter).
--  * Kauf: OffersLogic.offerHandler(angebot.id, os.time, log) je Angebot. Das Paket gibt es nur im
--    Fenster (plus Nachfrist receiptGraceMinutes) und nur einmal; jeder andere bezahlte Beleg bekommt
--    nur duplicateGems Ersatz-Gems (Exploit-Review 6.1). Nach dem bestätigten Speichern meldet
--    Purchases Notify { kind = "offerBought", offerId, gems, items } (beim Ersatz mit duplicate = true
--    und leeren items), der Shop sendet danach den Zustand neu (das Angebot steht dann auf "bought").
--    Studio: Für das Paket über DebugPurchase erst DebugOffer "starter" setzen, sonst Ersatz-Gems.
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"):
--   game.Players.Name:SetAttribute("DebugOffer", "starter")    -- Fenster jetzt starten (nicht gekauft)
--   game.Players.Name:SetAttribute("DebugOffer", "-starter")   -- zurücksetzen (nicht gestartet, nicht gekauft)
--   game.Players.Name:SetAttribute("DebugPurchase", "starter_pack")        -- Kauf über den Shop (Paket 4.4-Weg)
--   game.Players.Name:SetAttribute("DebugPurchase", "starter_pack:fest1")  -- feste PurchaseId (Doppelkauf)
-- Das Attribut wird danach zurückgesetzt, derselbe Befehl wirkt also wieder. Außerhalb von Studio
-- wird DebugOffer nie gelesen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Studio-Hilfe: Spieler-Attribut "starter" (starten) oder "-starter" (zurücksetzen).
local DEBUG_OFFER_ATTRIBUTE = "DebugOffer"

local IS_STUDIO = RunService:IsStudio()

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local OffersLogic = loadShared("Logic", "Offers")
local OffersData = loadShared("Data", "Offers")
local FeatureRules = loadShared("Logic", "Features")

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local Shop: any = nil
local Finds: any = nil
local Net: any = nil

local Offers = {}

local function log(message: string)
    warn(`[Offers] {message}`)
end

-- Server-Uhr in Unix-Sekunden (dieselbe wie Kaufprotokoll und Münz-Boost).
local function unixNow(): number
    return os.time()
end

-- Anzeige neu senden. Ein Fehler hier ändert nichts an der gebuchten Änderung.
local function refresh(player: Player)
    local ok, err = pcall(Sand.refresh, player)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
end

-- Meldet gerade gestartete Angebote an den Client: { kind = "offerUnlocked", offerId, secondsLeft }.
local function announceUnlocked(player: Player, profile: any, started: { string }, now: number)
    for _, offerId in started do
        local state, secondsLeft = OffersLogic.stateOf(profile, offerId, now)
        if state == "active" then
            local ok, err = pcall(Net.fire, player, "Notify", {
                kind = OffersLogic.OFFER_UNLOCKED_KIND,
                offerId = offerId,
                secondsLeft = secondsLeft,
            })
            if not ok then
                log(`Meldung "{OffersLogic.OFFER_UNLOCKED_KIND}" an {player.Name} fehlgeschlagen: {tostring(err)}`)
            end
        end
    end
end

-- Fund-Listener (Finds.addFindListener): startet passende Angebote. Wartet nie; Finds sendet danach
-- den Zustand neu.
local function onFind(player: Player, profile: any, info: any)
    if not FeatureRules.on("offers") then
        return -- Angebote sind ausgeschaltet (Data/Features): kein Fenster starten
    end
    if PlayerData.get(player) ~= profile then
        return -- Profil gewechselt (Rejoin), nichts schreiben
    end
    local now = unixNow()
    local newOffers, started = OffersLogic.onFind(profile, info.rarityId, now)
    if newOffers == nil then
        return
    end
    profile.offers = newOffers
    local source = if info.studio then "Studio-Fund" else "Fund"
    print(`[Offers] {player.Name}: Angebot {table.concat(started, ", ")} gestartet ({source} {tostring(info.findId)}, {tostring(info.rarityId)})`)
    announceUnlocked(player, profile, started, now)
end

-- Profil geladen: alte Spielstände mit schon vorhandenem Fund ab "Selten" bekommen das Fenster jetzt.
local function onLoaded(player: Player, profile: any)
    if PlayerData.get(player) ~= profile then
        return
    end
    local newOffers, started = OffersLogic.migrateStart(profile, unixNow())
    if newOffers == nil then
        return
    end
    profile.offers = newOffers
    print(`[Offers] {player.Name}: Angebot {table.concat(started, ", ")} gestartet (Spielstand hatte schon einen passenden Fund)`)
    refresh(player)
end

-- Snapshot-Feld `offers` für den StateSync (Server-Uhr beim Snapshot).
local function snapshotFor(player: Player): { [string]: any }
    local profile = PlayerData.get(player)
    if profile == nil then
        return {}
    end
    return { offers = OffersLogic.snapshot(profile, unixNow()) }
end

-- Studio-Hilfe: "starter" startet das Fenster jetzt, "-starter" setzt es zurück. Nur in Studio verbunden.
local function connectStudioHelper(player: Player)
    player:GetAttributeChangedSignal(DEBUG_OFFER_ATTRIBUTE):Connect(function()
        local value = player:GetAttribute(DEBUG_OFFER_ATTRIBUTE)
        if value == nil then
            return
        end
        player:SetAttribute(DEBUG_OFFER_ATTRIBUTE, nil) -- derselbe Befehl soll erneut wirken
        local offerId, start, problem = OffersLogic.parseDebug(value)
        if offerId == nil then
            log(`Studio: {DEBUG_OFFER_ATTRIBUTE}: {problem}`)
            return
        end
        local profile = PlayerData.get(player)
        if profile == nil then
            log(`Studio: {DEBUG_OFFER_ATTRIBUTE}: Profil von {player.Name} ist noch nicht geladen`)
            return
        end
        local now = unixNow()
        profile.offers = OffersLogic.withDebug(profile, offerId, start, now)
        print(`[Offers] Studio: {player.Name} Angebot {offerId} {if start then "gestartet" else "zurückgesetzt"}`)
        if start then
            announceUnlocked(player, profile, { offerId }, now)
        end
        refresh(player)
    end)
end

function Offers.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Shop = require(servicesFolder:WaitForChild("Shop") :: ModuleScript)
    Finds = require(servicesFolder:WaitForChild("Finds") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
    -- Schon in Init, damit der Listener vor dem ersten Takt von Finds steht.
    Finds.addFindListener(onFind)
end

-- Je Angebot ein Handler für sein Produkt (DataCheck: eigenes Developer Product mit oneTime = true).
-- Shop.Init hat Purchases schon angelegt (alle Init laufen vor allen Start).
local function registerHandlers()
    for _, offer in OffersData.list do
        Shop.registerProduct(offer.productId, OffersLogic.offerHandler(offer.id, os.time, log))
    end
end

-- Angebote ausgeschaltet (Data/Features, Ü1): nur die Kauf-Handler, damit ein offener Kauf trotzdem
-- gutgeschrieben wird. Kein Fenster, kein Snapshot, keine Studio-Hilfe.
function Offers.StartDisabled()
    registerHandlers()
end

function Offers.Start()
    registerHandlers()
    if type(Sand.addSnapshotProvider) == "function" then
        Sand.addSnapshotProvider(snapshotFor)
    else
        log("Sand.addSnapshotProvider fehlt: der Client bekommt keine Angebote")
    end
    PlayerData.onLoaded(onLoaded)

    if IS_STUDIO then
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

return Offers
