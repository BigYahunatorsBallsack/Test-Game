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
    tutorialStep: number, -- 1 bis Tutorial.count(), danach fertig
}

local State = {}

local current: Snapshot? = nil
local changedCallbacks: { (Snapshot) -> () } = {}
local notifyCallbacks: { (any) -> () } = {}

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
