--!strict
-- Crates-Service (Paket 4.2, 4.6)
-- Zuständig: Kisten öffnen (OpenCrate) mit Quoten und Pity auf dem Server, Policy
-- `ArePaidRandomItemsRestricted` je Spieler, Direktkauf (BuyDirectItem, Paket 4.6).
--
-- Die Regeln stehen in reinen Modulen mit Lune-Tests: Logic/CrateRoll (Quoten, Pity, Item),
-- Logic/CrateOpen (Bezahlen, Würfe, Inventar in einem Block, Gründe) und Logic/PolicyCache
-- (Policy holen, fail-closed). Hier werden nur Remote, Zufall, Profil, PolicyService und die
-- Anzeige angeschlossen.
--
-- Der Client schickt nur Kisten-ID und Anzahl (1 oder 10, Schema und Rate-Limit in RemoteSpec). Preis,
-- Würfe und Pity bestimmt der Server. Die Antwort der RemoteFunction ist das Ergebnis von
-- CrateOpen.open (`ok`, Gewinne, neuer Pity-Stand, Gems, Münzen) oder `{ ok = false, reason }`.
--
-- Policy (fail-closed): Beim Beitreten holt der Server einmal die Policy des Spielers (bis zu
-- POLICY_ATTEMPTS Versuche, POLICY_RETRY_SECONDS dazwischen). Bis eine gültige Antwort da ist und
-- für immer, wenn alle Versuche scheitern, gilt der Spieler als gesperrt: jede Öffnung endet mit
-- "restricted", und der StateSync meldet `cratesAllowed = false`. Der Abruf läuft in einem eigenen
-- Thread und nie im Öffnen-Block.
--
-- Direktkauf (Paket 4.6, Logic/DirectShop): Ist die Policy gesperrt oder unbekannt
-- (`Crates.policyState` "restricted" / "unknown"), kauft der Spieler Kisten-Items fest gegen Gems.
-- Der Client schickt nur die Item-ID (Schema und Limit in RemoteSpec), Preis und Policy bestimmt der
-- Server. Er liegt hier, weil dieser Service die Policy hält. Der StateSync meldet `cratePolicy`
-- (Zustand aus `Crates.policyState`) neben `cratesAllowed`.
--
-- Gemeinsame Sperre (Paket 5.1): `Crates.runExclusive(player, label, action)` lässt je Spieler nur einen
-- dieser Aufrufe zur selben Zeit zu: OpenCrate, BuyDirectItem, ClaimDaily (Services/Daily),
-- RedeemCode (Services/Codes, Paket 5.2), ClaimSeasonReward und BuySeasonPass (Services/SeasonPasses,
-- Paket 5.5b); ein zweiter bekommt sofort "busy". Andere Schreiber (MergeItem, Kauf-Handler) nutzen sie nicht. Regel für
-- alle: zwischen Lesen und Schreiben des Profils nie warten.
--
-- Studio-Hilfe (nur in Studio, Befehlszeile Ansicht "Server"):
--   game.Players.Name:SetAttribute("DebugCratesRestricted", true)   -- Kisten gesperrt testen
--   game.Players.Name:SetAttribute("DebugCratesRestricted", false)  -- Kisten erlaubt testen
--   game.Players.Name:SetAttribute("DebugCratesRestricted", nil)    -- wieder die echte Policy
-- Außerhalb von Studio wird das Attribut nie gelesen.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Policy-Abruf: so viele Versuche, so lange Pause dazwischen (Sekunden).
local POLICY_ATTEMPTS = 3
local POLICY_RETRY_SECONDS = 2
-- Studio-Hilfe: Spieler-Attribut, das die Policy überschreibt (true/false, nil = echte Policy).
local DEBUG_RESTRICTED_ATTRIBUTE = "DebugCratesRestricted"
-- Antwort, wenn derselbe Spieler schon eine Öffnung laufen hat (kann heute nicht vorkommen, weil
-- der Block nie wartet; schützt gegen spätere Änderungen).
local BUSY_REASON = "busy"
local ERROR_REASON = "error"

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local CrateOpen = loadShared("Logic", "CrateOpen")
local DirectShop = loadShared("Logic", "DirectShop")
local PolicyCache = loadShared("Logic", "PolicyCache")

local servicesFolder = script.Parent
local PlayerData: any = nil
local Sand: any = nil
local Events: any = nil
local Net: any = nil

local Crates = {}

-- Ein Zufallsgeber je Server (nicht je Aufruf neu gesät).
local random = Random.new()
local function nextRandom(): number
    return random:NextNumber()
end

-- Läuft für diesen Spieler gerade eine Öffnung, ein Direktkauf oder eine Daily-Abholung? (Eine
-- Buchung von Gems, Pity oder Inventar je Spieler zur selben Zeit.)
local busy: { [Player]: boolean } = {}
-- Spieler, deren Policy-Abruf und Studio-Hilfe schon angestoßen sind.
local handled: { [Player]: boolean } = {}

local function log(message: string)
    warn(`[Crates] {message}`)
end

-- Anzeige neu senden (Gems, Münzen, Pity, cratesAllowed). Ein Fehler hier ändert nichts am Ergebnis.
local function refresh(player: Player)
    local ok, err = pcall(Sand.refresh, player)
    if not ok then
        log(`Anzeige für {player.Name} fehlgeschlagen: {tostring(err)}`)
    end
end

local policy = PolicyCache.new({
    fetch = function(player: Player): any
        return PolicyService:GetPolicyInfoForPlayerAsync(player)
    end,
    wait = function(seconds: number)
        task.wait(seconds)
    end,
    attempts = POLICY_ATTEMPTS,
    retrySeconds = POLICY_RETRY_SECONDS,
    log = log,
    onResolved = function(userId: number, _restricted: boolean?)
        local player = Players:GetPlayerByUserId(userId)
        if player ~= nil then
            refresh(player)
        end
    end,
})

-- Gesperrt? true/false aus der Policy (in Studio vom Attribut überschrieben), nil = unbekannt.
-- CrateOpen behandelt nil wie true.
local function restrictedOf(player: Player): boolean?
    if RunService:IsStudio() then
        local override = player:GetAttribute(DEBUG_RESTRICTED_ATTRIBUTE)
        if type(override) == "boolean" then
            return override
        end
    end
    return policy.restricted(player.UserId)
end

-- Darf der Spieler Kisten öffnen? Nur, wenn die Policy bekannt ist und nicht sperrt.
function Crates.isAllowed(player: Player): boolean
    return restrictedOf(player) == false
end

-- Zustand der Policy für Anzeige und Direktkauf: "none" | "pending" | "allowed" | "restricted" |
-- "unknown" (Logic/PolicyCache). In Studio überschreibt das Attribut wie bei restrictedOf:
-- true -> "restricted", false -> "allowed".
function Crates.policyState(player: Player): string
    if RunService:IsStudio() then
        local override = player:GetAttribute(DEBUG_RESTRICTED_ATTRIBUTE)
        if type(override) == "boolean" then
            return if override then "restricted" else "allowed"
        end
    end
    return policy.state(player.UserId)
end

-- Öffnet ohne Warten. Der ganze Ablauf (Prüfen, Bezahlen, Würfeln, Pity, Inventar) steckt in
-- CrateOpen.open und schreibt das Profil erst am Ende in einem Zug.
local function openNow(player: Player, crateId: string, count: number): any
    local profile = PlayerData.get(player)
    return CrateOpen.open(profile, crateId, count, {
        random = nextRandom,
        restricted = restrictedOf(player),
        inSeason = Events.inSeason(player, crateId), -- Saison-Kalender (Events nutzt die Saison-Uhr) (Paket 5.4), Server-Uhr
    })
end

-- Gemeinsamer Ablauf für Öffnen und Direktkauf: Sperre je Spieler, pcall, Fehlertext nur ins
-- Protokoll, Anzeige nach Erfolg. Die Antwort an den Client hat nie `detail`.
local function runExclusive(player: Player, label: string, action: () -> any): any
    if busy[player] then
        return { ok = false, reason = BUSY_REASON }
    end
    busy[player] = true
    local ok, result = pcall(action)
    busy[player] = nil
    if not ok then
        log(`{label} für {player.Name} fehlgeschlagen: {tostring(result)}`)
        return { ok = false, reason = ERROR_REASON }
    end
    if result.ok ~= true then
        if result.reason == ERROR_REASON then
            log(`{label} für {player.Name} abgebrochen, nichts gebucht: {tostring(result.detail)}`)
        end
        return { ok = false, reason = result.reason } -- ohne `detail` (nur fürs Protokoll)
    end
    refresh(player)
    return result
end

-- Für andere Services (Daily, Paket 5.1; Codes, Paket 5.2): dieselbe Sperre je Spieler wie OpenCrate
-- und BuyDirectItem.
-- `action` darf nicht warten und gibt `{ ok, reason?, detail? }` zurück; die Antwort hat nie `detail`.
function Crates.runExclusive(player: Player, label: string, action: () -> any): any
    return runExclusive(player, label, action)
end

local function onOpenCrate(player: Player, crateId: string, count: number): any
    return runExclusive(player, `Öffnen von {tostring(crateId)}`, function(): any
        return openNow(player, crateId, count)
    end)
end

-- Direktkauf ohne Warten (Logic/DirectShop prüft zuerst und schreibt dann in einem Zug).
local function onBuyDirectItem(player: Player, itemId: string): any
    return runExclusive(player, `Direktkauf von {tostring(itemId)}`, function(): any
        local profile = PlayerData.get(player)
        local result = DirectShop.buy(profile, itemId, { policyState = Crates.policyState(player) })
        if result.ok == true then
            return {
                ok = true,
                itemId = result.itemId,
                price = result.price,
                gems = result.gems,
                copies = result.copies,
            }
        end
        return result
    end)
end

local function connectStudioHelper(player: Player)
    player:GetAttributeChangedSignal(DEBUG_RESTRICTED_ATTRIBUTE):Connect(function()
        print(`[Crates] Studio: {player.Name} {DEBUG_RESTRICTED_ATTRIBUTE} = {tostring(player:GetAttribute(DEBUG_RESTRICTED_ATTRIBUTE))}, Kisten erlaubt: {Crates.isAllowed(player)}, Policy: {Crates.policyState(player)}`)
        refresh(player)
    end)
end

local function onPlayerAdded(player: Player)
    -- Ein Spieler, der zwischen Connect und der Schleife über Players:GetPlayers() beitritt, käme
    -- sonst zweimal.
    if handled[player] then
        return
    end
    handled[player] = true
    if RunService:IsStudio() then
        connectStudioHelper(player)
    end
    -- Eigener Thread: der Abruf wartet (Netz), das Öffnen nie.
    task.spawn(policy.load, player.UserId, player)
end

function Crates.Init()
    PlayerData = require(servicesFolder:WaitForChild("PlayerData") :: ModuleScript)
    Sand = require(servicesFolder:WaitForChild("Sand") :: ModuleScript)
    Events = require(servicesFolder:WaitForChild("Events") :: ModuleScript)
    Net = require(servicesFolder.Parent:WaitForChild("Net"):WaitForChild("Net") :: ModuleScript)
end

function Crates.Start()
    Net.on("OpenCrate", onOpenCrate)
    Net.on("BuyDirectItem", onBuyDirectItem)

    -- `cratesAllowed` im StateSync: true nur bei bekannter, nicht sperrender Policy. `cratePolicy`:
    -- Zustand für Kisten-Knopf und Reiter "Direktkauf" (DirectShop.isOpen).
    if type(Sand.addSnapshotProvider) == "function" then
        Sand.addSnapshotProvider(function(player: Player): { [string]: any }
            return { cratesAllowed = Crates.isAllowed(player), cratePolicy = Crates.policyState(player) }
        end)
    else
        log("Sand.addSnapshotProvider fehlt: cratesAllowed wird nicht gesendet (der Client zeigt Kisten dann gesperrt)")
    end

    Players.PlayerAdded:Connect(onPlayerAdded)
    for _, player in Players:GetPlayers() do
        onPlayerAdded(player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        policy.forget(player.UserId)
        busy[player] = nil
        handled[player] = nil
    end)
end

return Crates
