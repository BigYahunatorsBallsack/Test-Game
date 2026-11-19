--!strict
-- Passes-Service (Paket 4.4)
-- Zuständig: Gamepass-Besitz ("2x Münzen", "Auto-Dig", "Großer Tank"), die Einstellung Auto-Dig
-- (Remote SetAutoDig) und der Kauf-Handler des Münz-Boosts ("coin_boost", über Shop.registerProduct).
--
-- Die Regeln stehen in reinen Modulen mit Lune-Tests: Logic/Passes (Besitz: Abfrage, Bestätigung des
-- Kauf-Ereignisses, Studio-Regel, Studio-Attribut) und Logic/Perks (Wirkungen, Münz-Boost, Auto-Dig,
-- Handler). Hier werden nur MarketplaceService, PlayerData, Sand, Shop und die Remote angeschlossen.
--
-- Besitz:
--  * Beim Laden des Profils prüft je Gamepass mit productId > 0 ein eigener Thread den Besitz
--    (PassesLogic.runCheck): je Runde UserOwnsGamePassAsync mit CHECK_ATTEMPTS Versuchen und
--    CHECK_PAUSE_SECONDS dazwischen, Runden im Abstand RECHECK_SECONDS, höchstens CHECK_ROUNDS, solange
--    der Spieler da ist. "Ja" trägt sofort ein. "Nein" entfernt erst beim zweiten "nein" in Folge
--    (eine Runde später); ein Fehler dazwischen behält den Pass. In Studio und für einen in dieser
--    Sitzung bestätigt gekauften Pass entfernt "nein" nie. Scheitert die Abfrage, bleibt der gemerkte
--    Besitz (`profile.passes`). ProductId 0 (Platzhalter): keine Abfrage, nur der gemerkte Besitz.
--  * PromptGamePassPurchaseFinished trägt nie selbst etwas ein (ein Exploit kann das Ereignis fälschen).
--    Bei einer Gamepass-ID, die zu genau einem Gamepass gehört, fragt ein eigener Thread bei Roblox nach
--    (PassesLogic.newPurchaseConfirmer, egal was wasPurchased sagt; bei wasPurchased == true bis zu
--    CONFIRM_ROUNDS Runden im Abstand CONFIRM_RETRY_SECONDS, sonst eine; ein Ereignis mit
--    wasPurchased == true während einer kurzen Prüfung verlängert sie). Nur bei "ja" und wenn der
--    Spieler noch da ist, wird der Pass als "in dieser Sitzung gekauft" gemerkt und eingetragen. Je
--    Spieler und Pass läuft höchstens eine Prüfung, ein schon eingetragener Pass wird nicht abgefragt.
--    Ist das Profil noch nicht geladen, trägt onLoaded den bestätigten Kauf ein. Unbekannte IDs starten
--    nichts und werden je Spieler nur einmal gemeldet.
--    Ausnahme NUR in Studio: wasPurchased == true gilt ohne Abfrage (Studio-Testkäufe zählen bei
--    Roblox nie als Besitz, sonst ließe sich der Kauf in Studio nicht testen).
--  * Jede Änderung: zuerst Sand.settle (altes Sammelfenster mit altem Tank abrechnen), dann ohne
--    Warten `profile.passes` als neue Tabelle schreiben, dann Sand.refresh (StateSync).
--
-- Auto-Dig: SetAutoDig(enabled) schreibt nur die Einstellung `profile.settings.autoDig` (neue Tabelle),
-- mit settle davor und refresh danach. Ohne Pass sammelt nichts; das Sammeln selbst steuert der Takt
-- im Sand-Service (Perks.autoDigStep).
--
-- Münz-Boost: Der Handler (Perks.coinBoostHandler, Uhr os.time) verlängert `boosts.coinsUntil` auf der
-- Profil-Kopie von Purchases, gibt keine Gems und meldet nach dem bestätigten Speichern
-- Notify { kind = "boostBought", productId, addedSeconds, coinBoostSeconds }.
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"):
--   game.Players.Name:SetAttribute("DebugPass", "big_tank")       -- Pass "Großer Tank" an
--   game.Players.Name:SetAttribute("DebugPass", "-big_tank")      -- Pass "Großer Tank" aus
--   game.Players.Name:SetAttribute("DebugPass", "double_coins")   -- 2x Münzen an
--   game.Players.Name:SetAttribute("DebugPass", "auto_dig")       -- Auto-Dig an
-- Das Attribut wird danach zurückgesetzt, derselbe Befehl wirkt also wieder. Unbekannte IDs werden
-- im Output gemeldet. Der Münz-Boost geht über die Studio-Hilfe des Shops:
--   game.Players.Name:SetAttribute("DebugPurchase", "coin_boost")        -- neuer Kauf
--   game.Players.Name:SetAttribute("DebugPurchase", "coin_boost:fest1")  -- feste PurchaseId
-- Außerhalb von Studio wird DebugPass nie gelesen.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Besitzabfrage: Versuche je Runde, Pause zwischen Versuchen, Pause zwischen Runden, höchstens so
-- viele Runden (Sekunden). Danach gilt bis zum nächsten Beitreten der gemerkte Besitz.
local CHECK_ATTEMPTS = 3
local CHECK_PAUSE_SECONDS = 2
local RECHECK_SECONDS = 60
local CHECK_ROUNDS = 10
-- Bestätigung eines Kauf-Ereignisses mit wasPurchased == true: so viele Runden (je CHECK_ATTEMPTS
-- Versuche) im Abstand CONFIRM_RETRY_SECONDS, falls Roblox den Kauf noch nicht kennt. Sonst eine Runde.
local CONFIRM_ROUNDS = 3
local CONFIRM_RETRY_SECONDS = 10
-- Studio-Hilfe: Spieler-Attribut "big_tank" (an) oder "-big_tank" (aus).
local DEBUG_PASS_ATTRIBUTE = "DebugPass"

local IS_STUDIO = RunService:IsStudio()

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local PassesLogic = loadShared("Logic", "Passes")
local Perks = loadShared("Logic", "Perks")

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local Shop: any = nil
local Net: any = nil

local Passes = {}

-- In dieser Sitzung gekaufte und von Roblox bestätigte Pässe je Spieler (ein "nein" der Abfrage
-- entfernt sie nie). Nur für anwesende Spieler gesetzt, PlayerRemoving räumt auf.
local bought: { [Player]: { [string]: boolean } } = {}
-- Spieler, für die ein Kauf-Ereignis mit unbekannter Gamepass-ID schon gemeldet wurde (Drossel).
local unknownLogged: { [Player]: boolean } = {}
-- Bestätigung der Kauf-Ereignisse (in Start angelegt).
local confirmer: any = nil

local function log(message: string)
    warn(`[Passes] {message}`)
end

-- Anzeige neu senden. Ein Fehler hier ändert nichts an der gebuchten Änderung.
local function refresh(player: Player)
    local ok, err = pcall(Sand.refresh, player)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
end

-- Abrechnen, ohne Warten schreiben, Anzeige senden. `newPasses` ist eine neue Tabelle aus Logic/Passes.
local function writePasses(player: Player, profile: any, newPasses: { [string]: boolean }, label: string)
    -- Altes Sammelfenster mit dem alten Tank abrechnen. Ein Fehler darf die Änderung nicht verhindern
    -- (sonst ginge ein bezahlter Pass für diese Sitzung verloren); offen bleibt höchstens ein Takt.
    local settled, err = pcall(Sand.settle, player)
    if not settled then
        log(`Abrechnung vor der Pass-Änderung ({label}) für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
    profile.passes = newPasses
    print(`[Passes] {player.Name}: {label}`)
    refresh(player)
end

local function isPresent(player: any): boolean
    return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function isCurrent(player: Player, profile: any): boolean
    return isPresent(player) and PlayerData.get(player) == profile
end

local function wait(seconds: number)
    task.wait(seconds)
end

-- Liest, ohne einen Eintrag anzulegen.
local function isBought(player: Player, passId: string): boolean
    local set = bought[player]
    return set ~= nil and set[passId] == true
end

-- Merkt einen bestätigten Kauf, nur für anwesende Spieler (kein Eintrag nach PlayerRemoving).
local function rememberBought(player: Player, passId: string)
    if not isPresent(player) then
        return
    end
    local set = bought[player]
    if set == nil then
        set = {}
        bought[player] = set
    end
    set[passId] = true
end

-- Eine Runde Besitzabfrage bei Roblox (CHECK_ATTEMPTS Versuche). Wartet.
local function askRoblox(player: Player, gamePassId: number, label: string, stillValid: () -> boolean): any
    return PassesLogic.ask(function(): any
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
    end, CHECK_ATTEMPTS, CHECK_PAUSE_SECONDS, wait, function(message: string)
        log(`{player.Name}, {label}: {message}`)
    end, stillValid)
end

-- Eigener Thread je Gamepass beim Laden: Regeln in PassesLogic.runCheck.
local function checkPass(player: Player, profile: any, pass: any)
    local function stillHere(): boolean
        return isCurrent(player, profile)
    end
    PassesLogic.runCheck({
        passId = pass.id,
        ask = function(): any
            return askRoblox(player, pass.productId, pass.id, stillHere)
        end,
        wait = wait,
        stillValid = stillHere,
        passesOf = function(): any
            return profile.passes
        end,
        context = function(): any
            return { studio = IS_STUDIO, boughtThisSession = isBought(player, pass.id) }
        end,
        write = function(newPasses: { [string]: boolean }, change: string)
            local what = if change == "granted" then "eingetragen" else "entfernt (zweimal nein)"
            writePasses(player, profile, newPasses, `{pass.id} {what} (Abfrage bei Roblox)`)
        end,
        rounds = CHECK_ROUNDS,
        recheckSeconds = RECHECK_SECONDS,
        log = function(message: string)
            log(`{player.Name}: {message}`)
        end,
    })
end

local function onLoaded(player: Player, profile: any)
    -- Ein bestätigter Kauf, der vor dem Laden fertig wurde, zählt jetzt.
    local boughtSet = bought[player]
    if boughtSet ~= nil then
        local withBought = PassesLogic.withBought(profile.passes, boughtSet)
        if withBought ~= nil then
            writePasses(player, profile, withBought, "in dieser Sitzung bestätigt gekaufte Pässe eingetragen (Kauf vor dem Laden)")
        end
    end
    for _, pass in PassesLogic.toCheck() do
        task.spawn(checkPass, player, profile, pass)
    end
end

local function newConfirmer(): any
    return PassesLogic.newPurchaseConfirmer({
        query = function(player: Player, gamePassId: number): any
            return askRoblox(player, gamePassId, `Kaufbestätigung {gamePassId}`, function(): boolean
                return isPresent(player)
            end)
        end,
        wait = wait,
        spawn = function(fn: () -> ())
            task.spawn(fn)
        end,
        isPresent = isPresent,
        passesOf = function(player: Player): any
            local profile = PlayerData.get(player)
            if profile == nil then
                return nil
            end
            return profile.passes or {}
        end,
        grant = function(player: Player, passId: string, newPasses: { [string]: boolean })
            local profile = PlayerData.get(player)
            if profile == nil then
                return -- passesOf hat eben ein Profil gesehen, ohne Warten dazwischen
            end
            local how = if IS_STUDIO then "Kauf" else "Kauf, von Roblox bestätigt"
            writePasses(player, profile, newPasses, `{passId} eingetragen ({how})`)
        end,
        remember = rememberBought,
        rounds = CONFIRM_ROUNDS,
        retrySeconds = CONFIRM_RETRY_SECONDS,
        trustEvent = IS_STUDIO,
        log = function(message: string, player: any)
            log(`{if isPresent(player) then player.Name else "Spieler weg"}: {message}`)
        end,
    })
end

local function onPurchaseFinished(player: Player, gamePassId: any, wasPurchased: any)
    local started = confirmer.onPurchaseFinished(player, gamePassId, wasPurchased)
    if started == "unknown" and wasPurchased == true and isPresent(player) and not unknownLogged[player] then
        unknownLogged[player] = true
        log(`{player.Name}: Gamepass-Kauf mit unbekannter oder ungültiger ID {tostring(gamePassId)} ignoriert (weitere werden nicht gemeldet)`)
    end
end

local function onSetAutoDig(player: Player, enabled: boolean)
    local profile = PlayerData.get(player)
    if profile == nil or Perks.autoDigSetting(profile) == enabled then
        return
    end
    local settled, err = pcall(Sand.settle, player)
    if not settled then
        log(`Abrechnung vor SetAutoDig für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
    profile.settings = Perks.withAutoDig(profile.settings, enabled)
    refresh(player)
end

-- Studio-Hilfe: "passId" schaltet an, "-passId" aus. Nur in Studio verbunden.
local function connectStudioHelper(player: Player)
    player:GetAttributeChangedSignal(DEBUG_PASS_ATTRIBUTE):Connect(function()
        local value = player:GetAttribute(DEBUG_PASS_ATTRIBUTE)
        if value == nil then
            return
        end
        player:SetAttribute(DEBUG_PASS_ATTRIBUTE, nil) -- derselbe Befehl soll erneut wirken
        local passId, enable, problem = PassesLogic.parseDebug(value)
        if passId == nil then
            log(`Studio: {DEBUG_PASS_ATTRIBUTE}: {problem}`)
            return
        end
        local profile = PlayerData.get(player)
        if profile == nil then
            log(`Studio: {DEBUG_PASS_ATTRIBUTE}: Profil von {player.Name} ist noch nicht geladen`)
            return
        end
        writePasses(player, profile, PassesLogic.with(profile.passes, passId, enable), `Studio: {passId} {if enable then "an" else "aus"}`)
    end)
end

function Passes.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Shop = require(servicesFolder:WaitForChild("Shop") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Passes.Start()
    -- Shop.Init hat Purchases schon angelegt (alle Init laufen vor allen Start).
    Shop.registerProduct(Perks.COIN_BOOST_PRODUCT_ID, Perks.coinBoostHandler(os.time))
    Net.on("SetAutoDig", onSetAutoDig)
    confirmer = newConfirmer()
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPurchaseFinished)
    PlayerData.onLoaded(onLoaded)
    Players.PlayerRemoving:Connect(function(player: Player)
        bought[player] = nil
        unknownLogged[player] = nil
        confirmer.forget(player)
    end)

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

return Passes
