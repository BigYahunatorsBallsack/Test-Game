--!strict
-- State-Controller
-- Hält den vom Server gesendeten Zustand (StateSync) und die Meldungen (Notify) und gibt
-- sie an die Oberfläche weiter. Der Client rechnet nichts Maßgebliches.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Snapshot = {
    coins: { m: number, e: number },
    gems: number, -- Gems (Paket 4.1)
    tank: { m: number, e: number },
    capacity: number,
    rate: number,
    toolId: string,
    collecting: boolean,
    zoneId: string,
    pricePerSand: number,
    nodes: { [string]: boolean }, -- gekaufte Knoten (nur die, die der Baum kennt)
    zonesUnlocked: { [string]: boolean }, -- freie Zonen (Paket 2.5)
    sellBonusBp: number, -- Summe des Verkauf-Asts (Hundertstel-Prozent, Paket 2.1)
    luckBonusBp: number, -- Summe des Glück-Asts (Hundertstel-Prozent, Paket 2.1)
    collectionBonusBp: number, -- Summe der fertigen Sets (Hundertstel-Prozent, Paket 2.6)
    windCrystals: number, -- Windkristalle (Paket 2.7)
    windBonusBp: number, -- ihr Bonus auf alle Münzen (Hundertstel-Prozent)
    storm: Storm, -- Vorschau des Sandsturms
    pity: { [string]: { sinceEpic: number, sinceLegendary: number } }, -- Kisten-Pity je Kiste (Paket 4.2)
    inventory: { skins: { [string]: number }, companions: { [string]: number }, toolVariants: { [string]: number } }?, -- Kisten-Items (Paket 4.3)
    equipped: { skin: string, companion: string, toolVariant: string }?, -- ausgerüstete Item-IDs, "" = leer (Paket 4.3)
    itemStars: { [string]: number }?, -- Sterne ab ★2, fehlt = ★1 (Paket 4.3)
    equipBonusBp: number?, -- Sammelraten-Bonus aller ausgerüsteten Items (Hundertstel-Prozent, Paket 4.3)
    cratesAllowed: boolean?, -- false/nil: Kisten in dieser Region gesperrt oder Policy unbekannt (Paket 4.2)
    cratePolicy: string?, -- "pending", "allowed", "restricted", "unknown" oder "none" (Paket 4.6): Direktkauf bei restricted/unknown
    offers: { [string]: { state: string, secondsLeft: number } }?, -- Angebote: hidden, active, expired oder bought, Restzeit in Sekunden (Server-Uhr, Paket 4.5)
    passes: { [string]: boolean }?, -- Gamepasses, die der Server als Besitz zählt (Produkt-ID -> true, Paket 4.4)
    autoDig: boolean?, -- Einstellung "Auto-Dig an" (wirkt nur mit Pass)
    autoDigOwned: boolean?, -- Auto-Dig-Pass vorhanden
    coinMultiplier: number?, -- Faktor aus 2x-Pass und Münz-Boost (steckt schon in pricePerSand)
    coinBoostSeconds: number?, -- Restzeit des Münz-Boosts in Sekunden (Server-Uhr zum Zeitpunkt des Snapshots)
    offline: { id: number, ok: boolean, reason: string?, seconds: number, awaySeconds: number, capSeconds: number, capped: boolean, coins: { m: number, e: number }? }?, -- Offline-Bericht (Paket 5.3)
    luckBoostSeconds: number?, -- Restzeit des Glücks-Boosts in Sekunden (Paket 5.1)
    daily: { started: boolean, day: number, canClaim: boolean, secondsLeft: number, streak: number }?, -- Daily Reward (Paket 5.1)
    season: { active: boolean, id: string?, name: string?, week: number?, phaseId: string?, phaseName: string?, hint: string?, secondsLeft: number?, crateId: string?, crateOpen: boolean?, zoneId: string?, zoneOpen: boolean?, next: { id: string, name: string, crateId: string, zoneId: string?, secondsToNext: number }? }?, -- Event-Kalender (Paket 5.4)
    seasonPass: { seasonId: string, points: number, maxPoints: number, tier: number, tiers: number, premium: boolean, claimed: { free: { [string]: boolean }, premium: { [string]: boolean } }?, canBuy: boolean?, ended: boolean?, claimSecondsLeft: number?, seasonSecondsLeft: number?, passId: string? }?, -- Saison-Punkte, Stufen, Abholmerker und Kauf-Zustand (Paket 5.5, 5.5b)
    koloss: { state: string, seasonId: string, progress: number, target: number, completed: boolean, you: number, tierId: string?, claimed: boolean, secondsLeft: number, secondsToStart: number }?, -- Server-Event "Der Koloss" (Paket 5.6)
    tutorialStep: number, -- 1 bis Tutorial.count(), danach fertig
}

-- Vorschau des Sandsturms (Paket 2.7), vom Server berechnet (Logic/Sandstorm.preview).
export type Storm = {
    unlocked: boolean, -- der Knoten für den Sturm ist da: der Knopf wird sichtbar
    ready: boolean, -- der Sturm ginge jetzt
    reason: string?, -- "requires" oder "tooFew", wenn er nicht geht
    runEarned: { m: number, e: number }, -- Einnahmen des Laufs inklusive Tankwert
    gain: number, -- Kristalle, die der Sturm jetzt gäbe
    needed: { m: number, e: number }, -- Einnahmen, ab denen der Sturm sich lohnt (minCrystals)
    minCrystals: number,
    crystalsNow: number,
    crystalsAfter: number,
    bonusBpNow: number,
    bonusBpAfter: number,
    prestiges: number,
    first: boolean,
}

-- Die Sammlung (CollectionSync, Paket 2.6): Zähler je Fund, Bonus und fertige Zonenbücher.
export type Collection = {
    counts: { [string]: number },
    bonusBp: number,
    books: { [string]: boolean },
}

local State = {}

local current: Snapshot? = nil
local currentCollection: Collection? = nil
local changedCallbacks: { (Snapshot) -> () } = {}
local notifyCallbacks: { (any) -> () } = {}
local collectionCallbacks: { (Collection) -> () } = {}

function State.get(): Snapshot?
    return current
end

function State.onChanged(callback: (Snapshot) -> ())
    table.insert(changedCallbacks, callback)
    if current ~= nil then
        task.spawn(callback, current)
    end
end

function State.onNotify(callback: (any) -> ())
    table.insert(notifyCallbacks, callback)
end

function State.getCollection(): Collection?
    return currentCollection
end

function State.onCollectionChanged(callback: (Collection) -> ())
    table.insert(collectionCallbacks, callback)
    if currentCollection ~= nil then
        task.spawn(callback, currentCollection)
    end
end

function State.Init() end

function State.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local stateSync = remotes:WaitForChild("StateSync") :: RemoteEvent
    local notify = remotes:WaitForChild("Notify") :: RemoteEvent
    stateSync.OnClientEvent:Connect(function(snapshot: any)
        if type(snapshot) ~= "table" then
            return
        end
        current = snapshot
        for _, callback in changedCallbacks do
            task.spawn(callback, snapshot)
        end
    end)
    local collectionSync = remotes:WaitForChild("CollectionSync") :: RemoteEvent
    collectionSync.OnClientEvent:Connect(function(summary: any)
        if type(summary) ~= "table" or type(summary.counts) ~= "table" or type(summary.books) ~= "table" then
            return
        end
        local collection: Collection = {
            counts = summary.counts,
            bonusBp = if type(summary.bonusBp) == "number" then summary.bonusBp else 0,
            books = summary.books,
        }
        currentCollection = collection
        for _, callback in collectionCallbacks do
            task.spawn(callback, collection)
        end
    end)
    notify.OnClientEvent:Connect(function(payload: any)
        if type(payload) ~= "table" then
            return
        end
        for _, callback in notifyCallbacks do
            task.spawn(callback, payload)
        end
    end)
end

return State
