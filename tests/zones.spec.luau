--!strict
-- Paket 2.5: Zonen (Freischaltung, Position, Reisen) und ihre Daten.

local T = require("./lib/expect")
local Zone = require("../src/shared/Logic/Zones")
local Profile = require("../src/shared/Logic/Profile")
local DataCheck = require("../src/shared/Logic/DataCheck")
local Zones = require("../src/shared/Data/Zones")
local World = require("../src/shared/Data/World")
local SandTypes = require("../src/shared/Data/SandTypes")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local RemoteSpec = require("../src/shared/Net/RemoteSpec")
local Validate = require("../src/shared/Logic/Validate")

local NOW = 1_700_000_000

local function deepCopy(value: any, memo: { [any]: any }?): any
    if type(value) ~= "table" then
        return value
    end
    local seen = memo or {}
    if seen[value] ~= nil then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, inner in value do
        copy[deepCopy(key, seen)] = deepCopy(inner, seen)
    end
    return copy
end

local function profileWith(nodes: { string }): any
    local profile: any = Profile.default(NOW)
    for _, id in nodes do
        profile.nodes[id] = true
    end
    return profile
end

local function at(zoneId: string, dx: number?, dz: number?): any
    local area = World.zonesById[zoneId]
    return { x = area.spawn.x + (dx or 0), y = 6, z = area.spawn.z + (dz or 0) }
end

T.describe("Freischaltung über Knoten-IDs", function()
    T.it("das Dünenmeer ist immer frei, andere Zonen erst mit ihrem Knoten", function()
        local profile = profileWith({})
        T.expect(Zone.isUnlocked(profile, "dunes")).toBe(true)
        for _, zone in Zones.list do
            if zone.requires ~= "start" then
                T.expect(Zone.isUnlocked(profile, zone.id)).toBe(false)
                profile.nodes[zone.requires] = true
                T.expect(Zone.isUnlocked(profile, zone.id)).toBe(true)
            end
        end
    end)

    T.it("jede Zone verlangt eine Knoten-ID, die im Baum existiert (nie eine feste Zahl)", function()
        for _, zone in Zones.list do
            T.expect(zone.requires == "start" or UpgradeTree.byId[zone.requires] ~= nil).toBe(true)
        end
    end)

    T.it("eine im Profil gespeicherte Zone bleibt frei, auch wenn der Knoten fehlt oder umgebaut wird", function()
        local profile = profileWith({ "collect_tool_3" })
        T.expect(#Zone.unlockNew(profile) > 0).toBe(true)
        -- Der Baum ändert sich: der Knoten ist nicht mehr gekauft (oder gar nicht mehr da).
        profile.nodes = {}
        T.expect(Zone.isUnlocked(profile, "oasis")).toBe(true)
        T.expect(Zone.isUnlocked(profile, "canyon")).toBe(false)
        -- Auch ein Knoten, der aus dem Baum verschwindet, ändert die gespeicherte Zone nicht.
        local moved: any = profileWith({ "gibt_es_nicht_mehr" })
        moved.zones.oasis = true
        T.expect(Zone.isUnlocked(moved, "oasis")).toBe(true)
    end)

    T.it("unlockNew meldet eine neue Zone genau einmal", function()
        local profile = profileWith({})
        T.expect(Zone.unlockNew(profile)).toEqual({})
        profile.nodes.collect_tool_3 = true
        T.expect(Zone.unlockNew(profile)).toEqual({ "oasis" })
        T.expect(Zone.unlockNew(profile)).toEqual({})
        profile.nodes.collect_tool_4 = true
        profile.nodes.collect_tool_5 = true
        T.expect(Zone.unlockNew(profile)).toEqual({ "canyon", "salt_lake" })
        T.expect(profile.zones.canyon).toBe(true)
    end)

    T.it("unlockedMap zeigt freie Zonen, unbekannte Knoten im Profil ändern nichts", function()
        local profile = profileWith({ "gibt_es_nicht", "collect_tool_3" })
        T.expect(Zone.unlockedMap(profile)).toEqual({ dunes = true, oasis = true })
    end)
end)

T.describe("Position und Zonenwechsel", function()
    T.it("zoneAt: Punkte in jedem Bereich liefern die richtige Zone, Punkte außerhalb keine", function()
        for _, area in World.zones do
            T.expect(Zone.zoneAt(area.spawn)).toBe(area.id)
            T.expect(Zone.zoneAt(area.stand)).toBe(area.id)
            local c = area.field.center
            T.expect(Zone.zoneAt({ x = c.x, y = c.y, z = c.z })).toBe(area.id)
        end
        T.expect(Zone.zoneAt({ x = -500, y = 0, z = 0 })).toBeNil()
        T.expect(Zone.zoneAt({ x = 0, y = 0, z = 500 })).toBeNil()
        T.expect(Zone.zoneAt({ x = 0 / 0, y = 0, z = 0 })).toBeNil()
        T.expect(Zone.zoneAt({ x = math.huge, y = 0, z = 0 })).toBeNil()
    end)

    T.it("an der Grenze zwischen zwei Zonen gehört der Punkt genau einer Zone", function()
        local border = World.zonesById.oasis.bounds.minX
        T.expect(Zone.zoneAt({ x = border, y = 0, z = 0 })).toBe("oasis")
        T.expect(Zone.zoneAt({ x = border - 0.01, y = 0, z = 0 })).toBe("dunes")
    end)

    T.it("freie Zone betreten: sie wird zur aktuellen Zone", function()
        local profile = profileWith({ "collect_tool_3" })
        Zone.unlockNew(profile)
        local result = Zone.resolve(profile, at("oasis"))
        T.expect(result.kind).toBe("enter")
        T.expect(result.zoneId).toBe("oasis")
        profile.currentZone = "oasis"
        T.expect(Zone.resolve(profile, at("oasis")).kind).toBe("none")
        T.expect(Zone.resolve(profile, at("dunes")).kind).toBe("enter") -- zurück ins Dünenmeer
    end)

    T.it("gesperrte Zone betreten: aktuelle Zone bleibt, Spieler wird in die aktuelle Zone zurückgesetzt", function()
        local profile = profileWith({})
        local deep = at("canyon", 20, 30)
        local result = Zone.resolve(profile, deep)
        T.expect(result.kind).toBe("blocked")
        T.expect(result.zoneId).toBe("canyon")
        local push: any = result.pushTo
        T.expect(Zone.zoneAt(push)).toBe("dunes")
        T.expect(push.z).toBe(deep.z)
        T.expect(push.y).toBe(deep.y)
        T.expect(profile.currentZone).toBe("dunes") -- unverändert
        local bounds = World.zonesById.dunes.bounds
        T.expect(push.x <= bounds.maxX - World.pushBackMarginStuds + 1e-9).toBe(true)
    end)

    T.it("gesperrte aktuelle Zone (zum Beispiel nach einem Sandsturm): zurück zum Dünenmeer-Spawn", function()
        local profile = profileWith({})
        profile.currentZone = "ruins" -- Knoten fehlt, Zone steht nicht im Profil
        local result = Zone.resolve(profile, at("ruins"))
        T.expect(result.kind).toBe("reset")
        T.expect(result.zoneId).toBe("dunes")
        T.expect(result.pushTo).toEqual(World.zonesById.dunes.spawn)
        -- Auch außerhalb aller Zonen und bei unbekannter Zone im Profil.
        T.expect(Zone.resolve(profile, { x = -999, y = 0, z = 0 }).kind).toBe("reset")
        profile.currentZone = "gibt_es_nicht"
        T.expect(Zone.resolve(profile, at("dunes")).kind).toBe("reset")
        -- Steht die Zone im Profil, bleibt sie frei und es passiert nichts.
        local kept = profileWith({})
        kept.zones.ruins = true
        kept.currentZone = "ruins"
        T.expect(Zone.resolve(kept, at("ruins")).kind).toBe("none")
    end)

    T.it("außerhalb aller Zonen passiert nichts", function()
        T.expect(Zone.resolve(profileWith({}), { x = -999, y = 5, z = 0 }).kind).toBe("none")
    end)
end)

T.describe("Reisen", function()
    T.it("freie, bekannte Zone geht durch", function()
        local profile = profileWith({ "collect_tool_3" })
        local ok, reason = Zone.canTravel(profile, "oasis", NOW, nil)
        T.expect(ok).toBe(true)
        T.expect(reason).toBeNil()
    end)

    T.it("unbekannte, gleiche und gesperrte Zone werden abgelehnt", function()
        local profile = profileWith({})
        local _, unknown = Zone.canTravel(profile, "mars", NOW, nil)
        T.expect(unknown).toBe("unknown")
        local _, same = Zone.canTravel(profile, "dunes", NOW, nil)
        T.expect(same).toBe("same")
        local _, locked = Zone.canTravel(profile, "oasis", NOW, nil)
        T.expect(locked).toBe("locked")
    end)

    T.it("Abklingzeit: zu früh abgelehnt, danach wieder erlaubt", function()
        local profile = profileWith({ "collect_tool_3" })
        local cooldown = World.travelCooldownSeconds
        local ok1, reason1 = Zone.canTravel(profile, "oasis", NOW + cooldown - 0.1, NOW)
        T.expect(ok1).toBe(false)
        T.expect(reason1).toBe("cooldown")
        local ok2 = Zone.canTravel(profile, "oasis", NOW + cooldown, NOW)
        T.expect(ok2).toBe(true)
    end)

    T.it("Remote TravelZone: bekannte Zone ja, falscher Typ, Text und mehrere Argumente nein", function()
        local def: any
        for _, entry in RemoteSpec.list do
            if entry.name == "TravelZone" then
                def = entry
            end
        end
        T.expect(def ~= nil).toBe(true)
        T.expect(def.limit.calls).toBe(1)
        T.expect((Validate.check(def.schema, { "oasis" }, 1))).toBe(true)
        T.expect((Validate.check(def.schema, { "mars" }, 1))).toBe(false)
        T.expect((Validate.check(def.schema, { 5 }, 1))).toBe(false)
        T.expect((Validate.check(def.schema, { "oasis", "x" }, 2))).toBe(false)
        T.expect((Validate.check(def.schema, {}, 0))).toBe(false)
    end)

    T.it("Remote TravelZone: Limit lehnt den zweiten Aufruf in einer Sekunde ab", function()
        local RateLimiter = require("../src/shared/Logic/RateLimiter")
        local def: any
        for _, entry in RemoteSpec.list do
            if entry.name == "TravelZone" then
                def = entry
            end
        end
        local clock = 0
        local limiter = RateLimiter.new(function()
            return clock
        end)
        T.expect(limiter:allow("1", "TravelZone", def.limit)).toBe(true)
        T.expect(limiter:allow("1", "TravelZone", def.limit)).toBe(false)
        clock += def.limit.per
        T.expect(limiter:allow("1", "TravelZone", def.limit)).toBe(true)
    end)
end)

T.describe("Daten der Welt und der Sandsorten", function()
    local function errorsFor(change: (any) -> ()): string
        local data: any = deepCopy(DataCheck.defaults())
        change(data)
        return table.concat(DataCheck.run(data), "\n")
    end

    T.it("jede Zone hat Bereich, Spawn, Stand und Feld im Bereich, Bereiche überlappen nicht", function()
        T.expect(errorsFor(function(data: any) end)).toBe("")
        T.expect(#World.zones).toBe(#Zones.list + #Zones.events) -- feste Zonen und Event-Zonen (5.5)
        for _, zone in Zones.list do
            T.expect(World.zonesById[zone.id] ~= nil).toBe(true)
        end
        for _, zone in Zones.events do
            T.expect(World.zonesById[zone.id] ~= nil).toBe(true)
        end
    end)

    T.it("kaputte Bereiche werden abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.World.zonesById.oasis.bounds.minX = data.World.zonesById.dunes.bounds.minX
        end)).toContain("überlappen")
        T.expect(errorsFor(function(data: any)
            data.World.zonesById.canyon.spawn.x = 99999
        end)).toContain("spawn liegt nicht im Bereich")
        T.expect(errorsFor(function(data: any)
            data.World.zonesById.canyon.stand.x = 99999
        end)).toContain("stand liegt nicht im Bereich")
        T.expect(errorsFor(function(data: any)
            data.World.zonesById.canyon.field.size.x = 10
        end)).toContain("Vielfaches von 4")
        T.expect(errorsFor(function(data: any)
            table.remove(data.World.zones, 5)
        end)).toContain("hat keinen Bereich")
    end)

    T.it("jede Sandsorte hat ein eigenes Terrain-Material", function()
        local seen: { [string]: boolean } = {}
        for _, sandType in SandTypes.list do
            T.expect(type(sandType.terrainMaterial)).toBe("string")
            T.expect(seen[sandType.terrainMaterial]).toBeNil()
            seen[sandType.terrainMaterial] = true
        end
        T.expect(errorsFor(function(data: any)
            data.SandTypes.byId.red.terrainMaterial = "Sand"
        end)).toContain("nutzt auch")
        T.expect(errorsFor(function(data: any)
            data.SandTypes.byId.red.terrainMaterial = nil
        end)).toContain("terrainMaterial")
    end)
end)

T.finish()
