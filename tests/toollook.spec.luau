--!strict
-- Paket 2.4: Aussehen der Werkzeugstufen (reine Logik und Daten).

local T = require("./lib/expect")
local ToolLook = require("../src/shared/Logic/ToolLook")
local DataCheck = require("../src/shared/Logic/DataCheck")
local Tools = require("../src/shared/Data/Tools")
local ToolLooks = require("../src/shared/Data/ToolLooks")

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
    end)
end)

T.finish()
