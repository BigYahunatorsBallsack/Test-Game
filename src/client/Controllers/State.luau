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
