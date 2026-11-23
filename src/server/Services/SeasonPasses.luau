--!strict
-- SeasonPasses-Service (Paket 5.5b: Saison-Pass, Abholen und Kauf)
-- Zuständig: Remotes ClaimSeasonReward und BuySeasonPass, Kauf-Handler je Pass-Produkt (über
-- Shop.registerProduct, ProcessReceipt in Logic/Purchases), Studio-Hilfe DebugSeasonPass.
--
-- Die Regeln stehen im reinen Modul Logic/SeasonPass (Lune-Tests in tests/seasonpass.spec.luau):
-- Saison des Passes und Abholfrist (`current`), Abholen in einem Block ohne Warten (`claim`), Prüfung
-- vor dem Kaufdialog (`buyCheck`), Kauf-Handler (`passHandler`), Studio-Hilfe (`parseDebug`,
-- `withDebug`). Hier hängen nur Remotes, Saison-Uhr, Profil, gemeinsame Sperre, MarketplaceService und
-- Anzeige dran. Den StateSync (`seasonPass`) baut Services/Events mit SeasonPass.view.
--
-- Zeit: immer die Saison-Uhr des Servers für diesen Spieler (SeasonClock.timeFor, außerhalb von Studio
-- os.time), nie ein Wert vom Client. Boosts aus dem Pass laufen mit der echten Server-Uhr (os.time),
-- damit eine Studio-Verschiebung sie nicht verlängert.
--
-- ClaimSeasonReward(tier, track): RemoteFunction, Schema Stufe 1 bis SeasonPass.MAX_TIERS und Spur
-- "free" | "premium", Limit 5 je s (RemoteSpec). Antwort:
--   { ok = true, tier, track, reward }
--     reward = { kind = "gems", amount, capped? } | { kind = "coinBoost", seconds }
--            | { kind = "luck", seconds } | { kind = "item", itemId, copies }
--   { ok = false, reason }  reason: noSeason, notReached, claimed, needPass, expired, busy, error
-- BuySeasonPass(): RemoteFunction ohne Argumente, Limit 1 je 3 s. Öffnet den Roblox-Kaufdialog
-- (MarketplaceService:PromptProductPurchase) nur in einer laufenden Saison mit `passId`, deren Pass der
-- Spieler noch nicht hat, und nur bei echter ProductId (0 = Platzhalter: "notOffered"). Wartet nie auf
-- die Zahlung. Antwort { ok = true, seasonId } oder { ok = false, reason } mit noSeason, owned,
-- notOffered, busy, error. Gebucht wird nur in ProcessReceipt.
-- Beide laufen unter derselben Sperre je Spieler wie OpenCrate, BuyDirectItem, ClaimDaily und
-- RedeemCode (Crates.runExclusive; gleichzeitig: "busy"); die Antwort hat nie `detail`. Ohne aktive
-- Sitzung (Profil wird nicht mehr gespeichert) gibt es "error". Gespeichert wird das Abholen wie bei
-- Daily über das Autosave von ProfileStore: Belohnung und Merker liegen zusammen im Profil.
--
-- Kauf: Für jede Saison mit `passId` meldet Init einen Handler an (SeasonPass.passHandler mit
-- `timeForUserId`), also vor Shop.Start (ProcessReceipt) und vor Shop.AfterStart (fehlende Handler).
-- Der Handler bekommt von Purchases als 4. Argument `{ userId, purchaseId }` und holt damit die
-- Saison-Uhr des Spielers. Nach dem bestätigten Speichern meldet Purchases
-- Notify { kind = "seasonPassBought", seasonId, duplicate, gems? }, der Shop sendet den Zustand neu.
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"; Saison des Passes = laufende, in der
-- Abholfrist die zuletzt beendete; Zeit wie DebugSeason):
--   game.Players.Name:SetAttribute("DebugSeasonPass", "points:500")  -- genau 500 Punkte (gedeckelt)
--   game.Players.Name:SetAttribute("DebugSeasonPass", "premium")     -- Pass an
--   game.Players.Name:SetAttribute("DebugSeasonPass", "reset")       -- Eintrag der Saison löschen
--   game.Players.Name:SetAttribute("DebugPurchase", "season_pass")   -- Testkauf über den Shop
-- Das Attribut wird nach dem Lesen gelöscht. Außerhalb von Studio gibt es keinen Listener, das
-- Attribut wird nie gelesen.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Studio-Hilfe: Spieler-Attribut ("points:N", "premium", "reset").
local DEBUG_ATTRIBUTE = "DebugSeasonPass"
-- Texte im Protokoll der gemeinsamen Sperre (Crates.runExclusive).
local CLAIM_LOCK_LABEL = "Saison-Pass abholen"
local BUY_LOCK_LABEL = "Saison-Pass kaufen"
local ERROR_REASON = "error"

local IS_STUDIO = RunService:IsStudio()

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local SeasonPassLogic = loadShared("Logic", "SeasonPass")
local SeasonsData = loadShared("Data", "Seasons")

local servicesFolder = script.Parent
local SeasonClock = require(servicesFolder:WaitForChild("SeasonClock") :: ModuleScript) :: any
local PlayerData: any = nil
local Sand: any = nil
local Shop: any = nil
local Crates: any = nil
local Net: any = nil

local SeasonPasses = {}

-- Spieler, deren Studio-Hilfe schon verbunden ist.
local handled: { [Player]: boolean } = {}

local function log(message: string)
    warn(`[SeasonPasses] {message}`)
end

-- Anzeige neu senden. Ein Fehler hier ändert nichts an der gebuchten Änderung.
local function refresh(player: Player)
    local ok, err = pcall(Sand.refresh, player)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
end

-- Saison-Uhr eines Spielers über die UserId (für den Kauf-Handler): SeasonClock des Spielers, wenn er
-- auf diesem Server ist, sonst die Server-Uhr. Außerhalb von Studio ist beides os.time.
local function timeForUserId(userId: number?): number
    local player = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
    if player ~= nil then
        return SeasonClock.timeFor(player)
    end
    return os.time()
end

-- Profil nur, solange die Sitzung speichert (sonst ginge die Abholung beim Verlassen verloren).
local function activeProfile(player: Player): any
    local profile = PlayerData.get(player)
    if profile == nil or not PlayerData.isActive(player.UserId) then
        return nil
    end
    return profile
end

-- Abholen ohne Warten, unter der gemeinsamen Sperre.
local function onClaimSeasonReward(player: Player, tier: number, track: string): any
    return Crates.runExclusive(player, CLAIM_LOCK_LABEL, function(): any
        local result = SeasonPassLogic.claim(activeProfile(player), tier, track, SeasonClock.timeFor(player), {
            boostNow = os.time(),
        })
        if result.ok == true then
            -- Nur die Felder für das Fenster; den Zustand (Merker, Gems) schickt der StateSync.
            return { ok = true, tier = result.tier, track = result.track, reward = result.reward }
        end
        return result
    end)
end

-- Kaufdialog öffnen, wenn erlaubt. Wartet nicht auf die Zahlung (gebucht wird in ProcessReceipt).
local function onBuySeasonPass(player: Player): any
    return Crates.runExclusive(player, BUY_LOCK_LABEL, function(): any
        local check = SeasonPassLogic.buyCheck(activeProfile(player), SeasonClock.timeFor(player))
        if check.ok ~= true then
            return check
        end
        -- PromptProductPurchase wartet nicht; ein Fehler (zum Beispiel ungültige ID) ergibt "error".
        local ok, err = pcall(function()
            MarketplaceService:PromptProductPurchase(player, check.productId)
        end)
        if not ok then
            return { ok = false, reason = ERROR_REASON, detail = `Kaufdialog nicht geöffnet: {tostring(err)}` }
        end
        return { ok = true, seasonId = check.seasonId }
    end)
end

-- Studio-Hilfe: DebugSeasonPass ändert den Eintrag der Saison des Passes. Nur in Studio verbunden.
local function connectStudioHelper(player: Player)
    player:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
        local value = player:GetAttribute(DEBUG_ATTRIBUTE)
        if value == nil then
            return
        end
        player:SetAttribute(DEBUG_ATTRIBUTE, nil) -- derselbe Befehl soll erneut wirken
        local action, number, problem = SeasonPassLogic.parseDebug(value)
        if action == nil then
            log(`Studio: {DEBUG_ATTRIBUTE}: {problem}`)
            return
        end
        local profile = PlayerData.get(player)
        if profile == nil then
            log(`Studio: {DEBUG_ATTRIBUTE}: Profil von {player.Name} ist noch nicht geladen`)
            return
        end
        local ok, seasons, seasonId, why = pcall(SeasonPassLogic.withDebug, profile, action, number, SeasonClock.timeFor(player))
        if not ok then
            log(`Studio: {DEBUG_ATTRIBUTE}: Fehler {tostring(seasons)}`)
            return
        end
        if seasons == nil then
            log(`Studio: {DEBUG_ATTRIBUTE}: {tostring(why)} (DebugSeason "week:1" oder "ended" setzen)`)
            return
        end
        profile.seasons = seasons
        local state = SeasonPassLogic.state(profile, seasonId)
        print(`[SeasonPasses] Studio: {player.Name} {DEBUG_ATTRIBUTE} = {tostring(value)}: {seasonId} Punkte {state.points}, Stufe {state.tier}, Pass {tostring(state.premium)}`)
        refresh(player)
    end)
end

local function onPlayerAdded(player: Player)
    if handled[player] then
        return
    end
    handled[player] = true
    connectStudioHelper(player)
end

function SeasonPasses.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Shop = require(servicesFolder:WaitForChild("Shop") :: ModuleScript)
    Crates = require(servicesFolder:WaitForChild("Crates") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
    -- Kauf-Handler schon in Init: Shop.Init (steht in SERVICE_NAMES vorher) hat Purchases angelegt, und
    -- alle Init laufen vor Shop.Start (ProcessReceipt) und Shop.AfterStart (Prüfung fehlender Handler).
    -- Je Pass-Produkt genau ein Handler (DataCheck: ein Produkt gehört zu höchstens einer Saison).
    local registered: { [string]: boolean } = {}
    for _, season in SeasonsData.list do
        local passId = season.passId
        if type(passId) == "string" and not registered[passId] then
            registered[passId] = true
            Shop.registerProduct(passId, SeasonPassLogic.passHandler(timeForUserId, log))
        end
    end
end

function SeasonPasses.Start()
    Net.on("ClaimSeasonReward", onClaimSeasonReward)
    Net.on("BuySeasonPass", onBuySeasonPass)
    if IS_STUDIO then
        Players.PlayerAdded:Connect(onPlayerAdded)
        for _, player in Players:GetPlayers() do
            onPlayerAdded(player)
        end
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        handled[player] = nil
    end)
end

return SeasonPasses
