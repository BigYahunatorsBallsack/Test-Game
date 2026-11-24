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
local CrateItems = require("../Data/CrateItems")
local Equipment = require("../Logic/Equipment")
local Codes = require("../Logic/Codes") -- nur die Längen; die Codes selbst stehen nur auf dem Server
local Social = require("../Data/Social") -- Platzzahl der Freundesliste (Paket 5.7)
local SeasonPass = require("../Logic/SeasonPass") -- Spuren und höchste Stufennummer (Paket 5.5b)

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
        limit = { calls = 5, per = 1 }, -- jede Änderung schaltet ein repliziertes Attribut um (Spam-Schutz, Review 6.1)
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
        name = "EquipItem",
        kind = "Function",
        direction = "ClientToServer",
        schema = {
            Validate.oneOf(Equipment.SLOTS), -- slot: skin, companion oder toolVariant
            Validate.string(ID_MAX_LEN), -- itemId aus CrateItems, oder "" zum Abnehmen (Gründe prüft der Server)
        },
        limit = { calls = 2, per = 1 }, -- jede Änderung baut die Optik aller Clients neu
        description = "Spieler rüstet ein Kisten-Item in einen Slot aus oder nimmt den Slot mit \"\" ab.",
    },
    {
        name = "MergeItem",
        kind = "Function",
        direction = "ClientToServer",
        schema = { Validate.idIn(CrateItems.byId, ID_MAX_LEN) }, -- itemId
        limit = { calls = 2, per = 1 },
        description = "Spieler hebt ein Kisten-Item mit Kopien um einen Stern.",
    },
    {
        name = "BuyDirectItem",
        kind = "Function",
        direction = "ClientToServer",
        schema = { Validate.idIn(CrateItems.byId, ID_MAX_LEN) }, -- itemId; Preis und Policy bestimmt der Server
        limit = { calls = 2, per = 1 },
        description = "Spieler kauft ein Kisten-Item fest gegen Gems (Direktkauf, nur bei gesperrten Zufallsitems, Paket 4.6).",
    },
    {
        name = "SetAutoDig",
        kind = "Event",
        direction = "ClientToServer",
        schema = { Validate.boolean() }, -- enabled
        limit = { calls = 2, per = 1 }, -- Schalter im Menü, jede Änderung rechnet ab und sendet den Zustand
        description = "Spieler schaltet Auto-Dig an oder aus (Einstellung, wirkt nur mit dem Gamepass, Paket 4.4).",
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
        name = "ClaimDaily",
        kind = "Function",
        direction = "ClientToServer",
        schema = {}, -- keine Argumente: Tag, Belohnung und Zeit bestimmt der Server (os.time)
        limit = { calls = 1, per = 2 }, -- ein Knopf im Fenster; die Abholung selbst geht nur einmal am Tag
        description = "Spieler holt die Daily Reward des Tages ab (Paket 5.1). Antwort: ok, Tag, Belohnung, bei Tag 7 die Kiste, oder Grund.",
    },
    {
        name = "RedeemCode",
        kind = "Function",
        direction = "ClientToServer",
        -- Eingegebener Text, 1 bis 24 Bytes. Ob er ein Code ist, was er gibt und ob der Spieler gesperrt
        -- ist, entscheidet nur der Server (Logic/Codes, Tabelle in src/server/Data/Codes).
        schema = { Validate.string(Codes.MAX_LENGTH, Codes.MIN_LENGTH) },
        limit = { calls = 1, per = 3 }, -- ein Knopf im Fenster; dazu die Sperre nach 5 falschen Versuchen
        description = "Spieler löst einen Code ein (Paket 5.2). Antwort: ok und Belohnung, oder Grund (bei locked mit secondsLeft).",
    },
    {
        name = "BuySeasonPass",
        kind = "Function",
        direction = "ClientToServer",
        -- Keine Argumente: Saison, Produkt und Zeit bestimmt der Server (Saison-Uhr). Er öffnet den
        -- Roblox-Kaufdialog nur in einer laufenden Saison mit Pass, die der Spieler noch nicht hat.
        -- Gebucht wird nie hier, sondern in ProcessReceipt (Logic/Purchases, idempotent).
        schema = {},
        limit = { calls = 1, per = 3 }, -- ein Knopf im Pass-Fenster
        description = "Spieler will den Saison-Pass kaufen (Paket 5.5b). Antwort: ok (Dialog geöffnet) oder Grund noSeason, owned, notOffered, busy, error.",
    },
    {
        name = "ClaimSeasonReward",
        kind = "Function",
        direction = "ClientToServer",
        schema = {
            Validate.int(1, SeasonPass.MAX_TIERS), -- Stufe; ob es sie gibt und ob sie erreicht ist, prüft der Server
            Validate.oneOf(SeasonPass.TRACKS), -- Spur: "free" oder "premium"
        },
        limit = { calls = 5, per = 1 }, -- mehrere Stufen kurz nacheinander abholen
        description = "Spieler holt die Belohnung einer Stufe des Saison-Passes ab (Paket 5.5b). Antwort: ok, tier, track, reward oder Grund.",
    },
    {
        name = "GetLeaderboard",
        kind = "Function",
        direction = "ClientToServer",
        schema = {}, -- keine Argumente: der Server antwortet mit seinem Zwischenspeicher (Paket 5.7)
        limit = { calls = 1, per = 5 }, -- Fenster öffnen oder Knopf "Aktualisieren"
        description = "Spieler fragt die Wochen-Rangliste ab (Paket 5.7). Antwort: ok, Woche, Top-Liste mit Rang, Name und Wert, der eigene Wert.",
    },
    {
        name = "GetFriends",
        kind = "Function",
        direction = "ClientToServer",
        schema = {}, -- keine Argumente: der Server nimmt die Roblox-Freundesliste des Spielers selbst
        limit = { calls = 1, per = 5 },
        description = "Spieler fragt seine Freunde zum Besuchen ab (Paket 5.7). Antwort: ok und Liste mit Platz und Name, oder Grund.",
    },
    {
        name = "ViewCollection",
        kind = "Function",
        direction = "ClientToServer",
        -- Der Client nennt nie einen Spieler, sondern nur einen Platz in der Liste von GetFriends, die der
        -- Server für ihn aufgebaut hat. Ohne gültigen Platz gibt es "notFriend".
        schema = { Validate.int(1, Social.leaderboard.maxFriends) },
        limit = { calls = 1, per = 2 },
        description = "Spieler sieht die Sammlung eines Freundes (Paket 5.7, nur lesen). Antwort: ok und Ansicht, oder Grund notFriend, noShowcase, busy, error.",
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
