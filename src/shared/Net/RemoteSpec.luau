--!strict
-- Vollständige Liste aller Remotes: Art, Richtung, Argument-Schema und Rate-Limit.
-- Der Server legt die Remotes genau aus dieser Liste an (Net.init). Eine Remote vom Client
-- zum Server darf nur registriert werden, wenn sie hier ein Schema UND ein Limit hat.
-- Der Client sendet nur Absichten (nie Mengen oder Preise), der Server prüft alles.

local Validate = require("../Logic/Validate")
local RateLimiter = require("../Logic/RateLimiter")
local Zones = require("../Data/Zones")
local UpgradeTree = require("../Data/UpgradeTree")
local Crates = require("../Data/Crates")

export type Limit = RateLimiter.Limit

export type RemoteDef = {
    name: string,
    kind: "Event" | "Function",
    direction: "ClientToServer" | "ServerToClient",
    schema: { Validate.Rule }?, -- nur Client -> Server
    limit: Limit?, -- nur Client -> Server
    description: string,
}

local ID_MAX_LEN = 64
local ZONE_ID_MAX_LEN = 32
local CRATE_ID_MAX_LEN = 32

local list: { RemoteDef } = {
    {
        name = "SetCollecting",
        kind = "Event",
        direction = "ClientToServer",
        schema = { Validate.boolean() }, -- holding
        limit = { calls = 10, per = 1 },
        description = "Spieler hält oder lässt die Sammeltaste los.",
    },
    {
        name = "Sell",
        kind = "Event",
        direction = "ClientToServer",
        schema = {},
        limit = { calls = 2, per = 1 },
        description = "Spieler will den Tank am Händlerstand verkaufen.",
    },
    {
        name = "TravelZone",
        kind = "Function",
        direction = "ClientToServer",
        schema = { Validate.idIn(Zones.byId, ZONE_ID_MAX_LEN) }, -- zoneId
        limit = { calls = 1, per = 1 },
        description = "Spieler will in eine Zone reisen. Antwort: ok und Grund.",
    },
    {
        name = "PurchaseNode",
        kind = "Function",
        direction = "ClientToServer",
        schema = { Validate.idIn(UpgradeTree.byId, ID_MAX_LEN) }, -- nodeId
        limit = { calls = 5, per = 1 },
        description = "Spieler will einen Skilltree-Knoten kaufen. Antwort: ok und Grund.",
    },
    {
        name = "OpenCrate",
        kind = "Function",
        direction = "ClientToServer",
        schema = {
            Validate.idIn(Crates.byId, CRATE_ID_MAX_LEN), -- crateId
            Validate.oneOf({ 1, Crates.bundle.buy }), -- count: Einzelöffnung oder 10er-Paket (Data/Crates)
        },
        limit = { calls = 1, per = 1 }, -- der Client wartet 1,3 s, damit Netzschwankungen das Limit nicht reißen
        description = "Spieler will eine Kiste (1) oder das 10er-Paket öffnen.",
    },
    {
        name = "Prestige",
        kind = "Function",
        direction = "ClientToServer",
        schema = {},
        limit = { calls = 1, per = 5 },
        description = "Spieler löst den Sandsturm (Prestige) aus.",
    },
    {
        name = "StateSync",
        kind = "Event",
        direction = "ServerToClient",
        description = "Server schickt dem Client den aktuellen Spielzustand zur Anzeige.",
    },
    {
        name = "CollectionSync",
        kind = "Event",
        direction = "ServerToClient",
        description = "Server schickt die Sammlung (Zähler je Fund, Bonus, fertige Zonenbücher) zur Anzeige.",
    },
    {
        name = "Notify",
        kind = "Event",
        direction = "ServerToClient",
        description = "Server schickt eine Meldung für den Spieler (Fehler, Hinweise).",
    },
}

local byName: { [string]: RemoteDef } = {}
for _, def in list do
    byName[def.name] = def
end

local RemoteSpec = {
    list = list,
    byName = byName,
}

-- Reine Prüfung, ob eine Client->Server-Remote registriert werden darf.
-- `specs` ist für Tests überschreibbar (Standard: byName).
function RemoteSpec.canRegister(name: string, specs: { [string]: RemoteDef }?): (boolean, string?)
    local def = (specs or byName)[name]
    if def == nil then
        return false, `Remote "{name}" steht nicht in RemoteSpec`
    end
    if def.direction ~= "ClientToServer" then
        return false, `Remote "{name}" ist keine Client->Server-Remote`
    end
    if def.schema == nil then
        return false, `Remote "{name}" hat kein Schema in RemoteSpec`
    end
    if def.limit == nil then
        return false, `Remote "{name}" hat kein Rate-Limit in RemoteSpec`
    end
    return true, nil
end

-- Wie canRegister, wirft aber einen Fehler (für Net.on).
function RemoteSpec.assertRegistrable(name: string, specs: { [string]: RemoteDef }?)
    local ok, reason = RemoteSpec.canRegister(name, specs)
    if not ok then
        error(reason or "Remote nicht registrierbar", 2)
    end
end

return RemoteSpec
