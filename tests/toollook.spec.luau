--!strict
-- Paket 2.4: Aussehen der Werkzeugstufen (reine Logik und Daten).

local T = require("./lib/expect")
local ToolLook = require("../src/shared/Logic/ToolLook")
local DataCheck = require("../src/shared/Logic/DataCheck")
local Tools = require("../src/shared/Data/Tools")
local ToolLooks = require("../src/shared/Data/ToolLooks")
local Terrain = require("../src/shared/Data/Terrain")
local Profile = require("../src/shared/Logic/Profile")
local BigNum = require("../src/shared/Logic/BigNum")

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

local function errorsFor(change: (any) -> ()): string
    local data: any = deepCopy(DataCheck.defaults())
    change(data)
    return table.concat(DataCheck.run(data), "\n")
end

T.describe("Tabelle ToolLooks", function()
    T.it("jede Werkzeugstufe hat ein Aussehen und es gibt keines ohne Werkzeug", function()
        for _, tool in Tools.list do
            T.expect(ToolLooks.byToolId[tool.id] ~= nil).toBeTruthy()
        end
        T.expect(#ToolLooks.list).toBe(#Tools.list)
        T.expect(errorsFor(function(data: any) end)).toBe("")
    end)

    T.it("Ausdehnung, Staubmenge und Staubgröße steigen je Stufe mindestens um den Faktor 1,25", function()
        local factor = ToolLooks.limits.minStepFactor
        T.expect(factor >= 1.25).toBeTruthy()
        for index = 2, #Tools.list do
            local before = ToolLook.of(Tools.list[index - 1].id)
            local now = ToolLook.of(Tools.list[index].id)
            T.expect(now.footprint >= before.footprint * factor).toBeTruthy()
            T.expect(now.dust.count >= before.dust.count * factor).toBeTruthy()
            T.expect(now.dust.size >= before.dust.size * factor).toBeTruthy()
        end
    end)

    T.it("die Hand hat kein Modell, jede andere Stufe mindestens ein Teil", function()
        T.expect(#ToolLook.of("hand").parts).toBe(0)
        for index = 2, #Tools.list do
            T.expect(#ToolLook.of(Tools.list[index].id).parts > 0).toBeTruthy()
        end
    end)

    T.it("jedes Teil hat gültige Form, Größe über 0 und Hex-Farbe", function()
        for _, look in ToolLooks.list do
            for _, part in look.parts do
                T.expect(part.shape == "Block" or part.shape == "Cylinder" or part.shape == "Ball").toBeTruthy()
                T.expect(part.size.x > 0 and part.size.y > 0 and part.size.z > 0).toBeTruthy()
                T.expect(string.match(part.colorHex, "^#%x%x%x%x%x%x$") ~= nil).toBeTruthy()
            end
        end
    end)

    T.it("Kamera-Bonus steigt nicht ab, ist nie negativ und bleibt unter dem Höchstwert", function()
        local last = 0
        for _, tool in Tools.list do
            local bonus = ToolLook.cameraBonus(tool.id)
            T.expect(bonus >= last).toBeTruthy()
            T.expect(bonus >= 0).toBeTruthy()
            T.expect(bonus <= ToolLooks.limits.maxCameraBonusStuds).toBeTruthy()
            last = bonus
        end
    end)

    T.it("Staub plus Wechsel-Wolke bleibt im Partikelbudget", function()
        for _, tool in Tools.list do
            T.expect(ToolLook.particlePeak(tool.id) <= ToolLooks.limits.maxParticlesPerEmit).toBeTruthy()
        end
    end)
end)

T.describe("ToolLook", function()
    T.it("bekannte ID liefert die Stufe, unbekannte oder leere ID die Hand", function()
        T.expect(ToolLook.of("shovel").toolId).toBe("shovel")
        T.expect(ToolLook.of("gibt_es_nicht").toolId).toBe("hand")
        T.expect(ToolLook.of(nil).toolId).toBe("hand")
        T.expect(ToolLook.of("").toolId).toBe("hand")
    end)

    T.it("Wechsel: gleiche Stufe nichts, höher Animation, niedriger oder erster Zustand still", function()
        T.expect(ToolLook.change("shovel", "shovel")).toBe("none")
        T.expect(ToolLook.change("hand", "shovel")).toBe("upgrade")
        T.expect(ToolLook.change("shovel", "mega_machine")).toBe("upgrade")
        T.expect(ToolLook.change("mega_machine", "hand")).toBe("silent")
        T.expect(ToolLook.change(nil, "mini_digger")).toBe("silent")
        T.expect(ToolLook.change("hand", "unbekannt")).toBe("none")
    end)
end)

T.describe("Geometrie und Bewegung", function()
    T.it("kein Teil schneidet den Charakter-Quader, alle sechs Stufen", function()
        for _, tool in Tools.list do
            local ok, index = ToolLook.clearOfCharacter(ToolLook.of(tool.id))
            T.expect(`{tool.id}: {tostring(index)}`).toBe(`{tool.id}: nil`)
            T.expect(ok).toBe(true)
        end
    end)

    T.it("kein Teil liegt im Kamera-Gang hinter dem Charakter", function()
        for _, tool in Tools.list do
            local ok, index = ToolLook.clearOfCameraLane(ToolLook.of(tool.id))
            T.expect(`{tool.id}: {tostring(index)}`).toBe(`{tool.id}: nil`)
            T.expect(ok).toBe(true)
        end
    end)

    T.it("Hüllquader: Drehung wird eingerechnet", function()
        local flat = ToolLook.bounds({ shape = "Block", size = { x = 2, y = 2, z = 6 }, offset = { x = 0, y = 5, z = 0 }, colorHex = "#FFFFFF", material = "Sand" })
        T.expect(flat.maxZ).toBeCloseTo(3, 0.001)
        local turned = ToolLook.bounds({ shape = "Block", size = { x = 2, y = 2, z = 6 }, offset = { x = 0, y = 5, z = 0 }, rotation = { x = 0, y = 90, z = 0 }, colorHex = "#FFFFFF", material = "Sand" })
        T.expect(turned.maxX).toBeCloseTo(3, 0.001)
        T.expect(turned.maxZ).toBeCloseTo(1, 0.001)
    end)

    T.it("Prüfung findet ein Teil im Charakter und eines im Kamera-Gang", function()
        local look: any = deepCopy(ToolLook.of("shovel"))
        look.parts[1].offset = { x = 0, y = 2, z = 0 }
        T.expect(ToolLook.clearOfCharacter(look)).toBe(false)
        look = deepCopy(ToolLook.of("shovel"))
        look.parts[1].offset = { x = 0, y = 2, z = 5 }
        T.expect(ToolLook.clearOfCameraLane(look)).toBe(false)
    end)

    T.it("Arbeitsspitze liegt vor dem Charakter, das Loch erreicht den Charakter nicht", function()
        for _, tool in Tools.list do
            local look = ToolLook.of(tool.id)
            T.expect(look.workPoint.z < 0).toBe(true)
            local hole = Terrain.holeByTool[tool.id]
            T.expect(`{tool.id}: {tostring(ToolLook.holeClear(look, hole.radius))}`).toBe(`{tool.id}: true`)
        end
        T.expect(ToolLook.workPointOf("gibt_es_nicht")).toEqual(ToolLook.of("hand").workPoint)
        -- Ein zu großes Loch wird erkannt.
        T.expect(ToolLook.holeClear(ToolLook.of("hand"), 50)).toBe(false)
    end)

    T.it("motionAt ist periodisch und bleibt im Ausschlag", function()
        for _, look in ToolLooks.list do
            for _, motion in look.motions do
                for _, t in { 0, 0.13, 0.7, 1.9 } do
                    local a = ToolLook.motionAt(motion, t)
                    local b = ToolLook.motionAt(motion, t + motion.period)
                    if motion.kind == "spin" then
                        T.expect((a - b) % 360 < 1e-6 or (b - a) % 360 < 1e-6).toBe(true)
                        T.expect(a >= 0 and a < 360).toBe(true)
                    else
                        T.expect(a).toBeCloseTo(b, 1e-6)
                        T.expect(math.abs(a) <= motion.amplitude + 1e-9).toBe(true)
                    end
                end
            end
        end
    end)

    T.it("Ausschlag 0 ist still, ungültige Periode auch", function()
        T.expect(ToolLook.motionAt({ part = 1, kind = "swing", axis = "x", amplitude = 0, period = 1 }, 0.3)).toBe(0)
        T.expect(ToolLook.motionAt({ part = 1, kind = "bob", axis = "y", amplitude = 1, period = 0 }, 0.3)).toBe(0)
    end)

    T.it("jede Stufe hat einen erlaubten Sandfluss, ab der Eimerkette nie derselbe wie die Stufe davor", function()
        local allowed: { [string]: boolean } = {}
        for _, kind in ToolLooks.limits.flowKinds do
            allowed[kind] = true
        end
        local previous: string? = nil
        for index, tool in Tools.list do
            local flow = ToolLook.of(tool.id).sandFlow
            T.expect(allowed[flow.kind]).toBe(true)
            if index >= 3 then
                T.expect(flow.kind ~= previous).toBe(true)
                T.expect(flow.rate > 0).toBe(true)
            end
            T.expect(ToolLook.flowLoad(ToolLook.of(tool.id)) <= ToolLooks.limits.maxFlowParticles).toBe(true)
            previous = flow.kind
        end
    end)

    T.it("höchstens 12 Teile je Modell, Bewegungen verweisen auf vorhandene Teile", function()
        for _, look in ToolLooks.list do
            T.expect(#look.parts <= ToolLooks.limits.maxParts).toBe(true)
            for _, motion in look.motions do
                T.expect(look.parts[motion.part] ~= nil).toBe(true)
            end
        end
    end)
end)

T.describe("Attribute für den Server", function()
    local function profileWith(nodes: { string }): any
        local profile = Profile.default(1_700_000_000)
        profile.coins = BigNum.serialize(BigNum.new(0))
        for _, id in nodes do
            profile.nodes[id] = true
        end
        return profile
    end

    T.it("ToolId folgt dem Werkzeug aus dem Baum: Laden, Kauf, Reset", function()
        T.expect(ToolLook.attributesFor(profileWith({}), false)).toEqual({ ToolId = "hand", Collecting = false })
        T.expect(ToolLook.attributesFor(profileWith({ "collect_tool_2" }), true)).toEqual({ ToolId = "shovel", Collecting = true })
        T.expect(ToolLook.attributesFor(profileWith({ "collect_tool_2", "collect_tool_3" }), false).ToolId).toBe("bucket_chain")
        -- Reset (Sandsturm): Knoten weg, Hand.
        T.expect(ToolLook.attributesFor(profileWith({}), false).ToolId).toBe("hand")
        -- Unbekannte Knoten-IDs ändern nichts.
        T.expect(ToolLook.attributesFor(profileWith({ "gibt_es_nicht" }), false).ToolId).toBe("hand")
    end)
end)

T.describe("DataCheck für ToolLooks", function()
    T.it("fehlende Stufe, Größe 0, falsche Farbe und kaputter Staub werden abgelehnt", function()
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.shovel = nil
            table.remove(data.ToolLooks.list, 2)
        end)).toContain("kein Aussehen")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.mini_digger.parts[1].size.y = 0
        end)).toContain("size.y")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.mini_digger.parts[1].colorHex = "rot"
        end)).toContain("colorHex")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.vacuum_robot.dust.count = 5
        end)).toContain("dust.count steigt nicht")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.mega_machine.dust.count = 59
        end)).toContain("Partikelbudget")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.shovel.footprint = 0.4
        end)).toContain("footprint")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.hand.parts = { { shape = "Block", size = { x = 1, y = 1, z = 1 }, offset = { x = 0, y = 0, z = 0 }, colorHex = "#FFFFFF", material = "Sand" } }
        end)).toContain("Hand hat kein Modell")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.mega_machine.cameraBonusStuds = 99
        end)).toContain("Höchstwert")
        T.expect(errorsFor(function(data: any)
            local parts = data.ToolLooks.byToolId.shovel.parts
            for _ = 1, 13 do
                table.insert(parts, parts[1])
            end
        end)).toContain("mehr als 12 Teile")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.mini_digger.sandFlow.kind = "regen"
        end)).toContain("sandFlow.kind ist unbekannt")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.vacuum_robot.sandFlow.kind = "cloud"
        end)).toContain("gleicht der Stufe davor")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.mega_machine.sandFlow.rate = 200
        end)).toContain("Partikelbudget")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.shovel.motions[1].part = 9
        end)).toContain("verweist auf kein Teil")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.shovel.motions[1].kind = "wirbeln"
        end)).toContain("kind ist unbekannt")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.shovel.motions[1].period = 0
        end)).toContain("period")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.shovel.workPoint.z = 2
        end)).toContain("workPoint")
        T.expect(errorsFor(function(data: any)
            data.ToolLooks.byToolId.shovel.loopSoundId = "abc"
        end)).toContain("loopSoundId")
    end)
end)

T.finish()
