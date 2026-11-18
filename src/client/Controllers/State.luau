--!strict
-- State-Controller
-- Hält den vom Server gesendeten Zustand (StateSync) und die Meldungen (Notify) und gibt
-- sie an die Oberfläche weiter. Der Client rechnet nichts Maßgebliches.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Snapshot = {
    coins: { m: number, e: number },
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
    tutorialStep: number, -- 1 bis Tutorial.count(), danach fertig
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
