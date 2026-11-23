--!strict
-- Ego-Perspektive: Hände vor der Kamera, Eimer, Maus, Sicht auf die eigene Maschine und Tabellenprüfung.

local T = require("./lib/expect")
local FirstPerson = require("../src/shared/Logic/FirstPerson")
local Data = require("../src/shared/Data/FirstPerson")
local Tools = require("../src/shared/Data/Tools")
local ToolLooks = require("../src/shared/Data/ToolLooks")

local function deepCopy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in value do
        copy[key] = deepCopy(inner)
    end
    return copy
end

local function errorsFor(change: (any) -> ()): string
    local data = deepCopy(Data)
    change(data)
    return table.concat(FirstPerson.check(data), "\n")
end

local still = { t = 0, collecting = false, speed = 0 }

T.describe("Tabelle FirstPerson", function()
    T.it("die mitgelieferte Tabelle ist fehlerfrei", function()
        T.expect(table.concat(FirstPerson.check(), "\n")).toBe("")
    end)

    T.it("jedes Werkzeug hat einen Eintrag, sonst meldet die Prüfung es", function()
        for _, tool in Tools.list do
            T.expect(Data.tools[tool.id] ~= nil).toBeTruthy()
        end
        T.expect(errorsFor(function(d)
            d.tools.shovel = nil
        end)).toContain("shovel")
    end)

    T.it("meldet unbekanntes Teil, Grabstil, falsches Sichtfeld, leere Tasten und fehlenden Standard", function()
        T.expect(errorsFor(function(d)
            d.tools.hand.item = "gibtsnicht"
        end)).toContain("unbekanntes Teil")
        T.expect(errorsFor(function(d)
            d.tools.hand.dig = "gibtsnicht"
        end)).toContain("Grabstil")
        T.expect(errorsFor(function(d)
            d.camera.fieldOfView = 200
        end)).toContain("fieldOfView")
        T.expect(errorsFor(function(d)
            d.cursor.toggleKeys = {}
        end)).toContain("toggleKeys")
        T.expect(errorsFor(function(d)
            d.defaultTool = "weg"
        end)).toContain("defaultTool")
        T.expect(errorsFor(function(d)
            d.digStyles.scoop.period = 0
        end)).toContain("period")
        T.expect(errorsFor(function(d)
            d.toolView.fadeTo = 2
        end)).toContain("fadeTo")
    end)

    T.it("meldet kaputte Teile: Form, Größe, Farbe, Bemalung", function()
        T.expect(errorsFor(function(d)
            d.viewmodel.items.shovel.parts[1].shape = "Kegel"
        end)).toContain("Form")
        T.expect(errorsFor(function(d)
            d.viewmodel.bucket[1].size.x = 0
        end)).toContain("size")
        T.expect(errorsFor(function(d)
            d.viewmodel.rightArm[1].colorHex = "rot"
        end)).toContain("colorHex")
        T.expect(errorsFor(function(d)
            d.viewmodel.leftArm[1].paint = "glitzer"
        end)).toContain("paint")
        T.expect(errorsFor(function(d)
            d.viewmodel.fill.maxHeight = 0.01
        end)).toContain("fill")
    end)

    T.it("die Hände liegen vor der Kamera, rechts die Werkzeughand, links der Eimer", function()
        T.expect(Data.viewmodel.right.offset.z < 0).toBeTruthy()
        T.expect(Data.viewmodel.left.offset.z < 0).toBeTruthy()
        T.expect(Data.viewmodel.right.offset.x > 0).toBeTruthy()
        T.expect(Data.viewmodel.left.offset.x < 0).toBeTruthy()
        T.expect(errorsFor(function(d)
            d.viewmodel.right.offset.z = 1
        end)).toContain("vor der Kamera")
    end)

    T.it("Hand und Schaufel ersetzen das Weltmodell, Maschinen bleiben in der Welt", function()
        T.expect(Data.tools.hand.hideWorldTool).toBe(true)
        T.expect(Data.tools.shovel.hideWorldTool).toBe(true)
        T.expect(Data.tools.shovel.item).toBe("shovel")
        for _, id in { "bucket_chain", "mini_digger", "vacuum_robot", "mega_machine" } do
            T.expect(Data.tools[id].hideWorldTool).toBe(false)
            T.expect(Data.tools[id].item).toBe("remote")
        end
    end)
end)

T.describe("Bewegung der Hände", function()
    T.it("im Stand ohne Graben bleiben beide Hände am Anker", function()
        local pose = FirstPerson.viewPose("shovel", still)
        T.expect(pose.right.move).toEqual({ x = 0, y = 0, z = 0 })
        T.expect(pose.right.turn).toEqual({ x = 0, y = 0, z = 0 })
        T.expect(pose.left.move).toEqual({ x = 0, y = 0, z = 0 })
    end)

    T.it("unbekanntes oder fehlendes Werkzeug verhält sich wie der Standard", function()
        local state = { t = 0.3, collecting = true, speed = 0 }
        local fallback = FirstPerson.viewPose(Data.defaultTool, state)
        T.expect(FirstPerson.viewPose("gibtsnicht", state)).toEqual(fallback)
        T.expect(FirstPerson.viewPose(nil, state)).toEqual(fallback)
    end)

    T.it("Schaufel: auf dem Höhepunkt des Stichs ganz vorn, der Eimer wippt mit", function()
        local dig = Data.digStyles.stab
        local pose = FirstPerson.viewPose("shovel", { t = dig.period / 4, collecting = true, speed = 0 })
        T.expect(pose.right.move.z).toBeCloseTo(dig.move.z)
        T.expect(pose.right.move.y).toBeCloseTo(dig.move.y)
        T.expect(pose.right.turn.x).toBeCloseTo(dig.turn.x)
        T.expect(pose.left.move.y).toBeCloseTo(dig.move.y * dig.leftFactor)
    end)

    T.it("in der zweiten Hälfte der Periode ist die Hand zurück (kein Rückwärts-Stich)", function()
        local dig = Data.digStyles.stab
        local pose = FirstPerson.viewPose("shovel", { t = dig.period * 3 / 4, collecting = true, speed = 0 })
        T.expect(pose.right.move.z).toBeCloseTo(0)
    end)

    T.it("Hand greift beim Graben nach vorn unten", function()
        local dig = Data.digStyles.scoop
        local pose = FirstPerson.viewPose("hand", { t = dig.period / 4, collecting = true, speed = 0 })
        T.expect(pose.right.move.z < 0).toBeTruthy()
        T.expect(pose.right.move.y < 0).toBeTruthy()
    end)

    T.it("Fernsteuerung zittert nur wenig (unter 0,1 Studs)", function()
        for i = 0, 20 do
            local pose = FirstPerson.viewPose("mega_machine", { t = i * 0.037, collecting = true, speed = 0 })
            T.expect(math.abs(pose.right.move.x) < 0.1).toBeTruthy()
            T.expect(math.abs(pose.right.move.y) < 0.1).toBeTruthy()
        end
    end)

    T.it("Wippen beim Laufen wächst mit der Geschwindigkeit und ist im Stand aus", function()
        local t = 1 / (4 * Data.walk.bobHz)
        local stand = FirstPerson.viewPose("hand", { t = t, collecting = false, speed = 0 })
        local slow = FirstPerson.viewPose("hand", { t = t, collecting = false, speed = Data.walk.fullSpeed / 2 })
        local fast = FirstPerson.viewPose("hand", { t = t, collecting = false, speed = Data.walk.fullSpeed * 3 })
        T.expect(stand.right.move.y).toBeCloseTo(0)
        T.expect(slow.right.move.y).toBeCloseTo(Data.walk.bobStuds / 2)
        T.expect(fast.right.move.y).toBeCloseTo(Data.walk.bobStuds)
        T.expect(fast.left.move.y).toBeCloseTo(-Data.walk.bobStuds)
    end)

    T.it("ungültige Zahlen (NaN, unendlich) ergeben keine Bewegung und keinen Fehler", function()
        local pose = FirstPerson.viewPose("hand", { t = math.huge, collecting = false, speed = 0 / 0 })
        T.expect(pose.right.move).toEqual({ x = 0, y = 0, z = 0 })
    end)

    T.it("Nachziehen: gegen die Drehung, begrenzt, und es klingt ab", function()
        local s = FirstPerson.swayStep({ yaw = 0, pitch = 0 }, 0.05, 0, 1 / 60)
        T.expect(s.yaw < 0).toBeTruthy()
        local big = { yaw = 0, pitch = 0 }
        for _ = 1, 200 do
            big = FirstPerson.swayStep(big, 10, -10, 1 / 60)
        end
        T.expect(big.yaw).toBeCloseTo(-Data.sway.maxDegrees, 1e-3)
        T.expect(big.pitch).toBeCloseTo(Data.sway.maxDegrees, 1e-3)
        local calm = big
        for _ = 1, 600 do
            calm = FirstPerson.swayStep(calm, 0, 0, 1 / 60)
        end
        T.expect(math.abs(calm.yaw) < 0.01).toBeTruthy()
    end)

    T.it("Glättung bleibt zwischen 0 und 1", function()
        local a = FirstPerson.smoothAlpha(1 / 60, 12)
        T.expect(a > 0 and a < 1).toBeTruthy()
        T.expect(FirstPerson.smoothAlpha(10, 12)).toBeCloseTo(1, 1e-3)
        T.expect(FirstPerson.smoothAlpha(0, 12)).toBe(0)
        T.expect(FirstPerson.smoothAlpha(0 / 0, 12)).toBe(0)
    end)
end)

T.describe("Eimer zeigt den Tank", function()
    local fill = Data.viewmodel.fill
    T.it("leer: dünne Schicht am Boden, voll: bis knapp unter den Rand", function()
        local empty = FirstPerson.bucketFill(0)
        T.expect(empty.height).toBeCloseTo(fill.minHeight)
        T.expect(empty.centerY - empty.height / 2).toBeCloseTo(fill.bottomY)
        local full = FirstPerson.bucketFill(1)
        T.expect(full.height).toBeCloseTo(fill.maxHeight)
        T.expect(full.centerY - full.height / 2).toBeCloseTo(fill.bottomY)
    end)
    T.it("halb voll liegt in der Mitte, Werte außerhalb werden begrenzt", function()
        T.expect(FirstPerson.bucketFill(0.5).height).toBeCloseTo((fill.minHeight + fill.maxHeight) / 2)
        T.expect(FirstPerson.bucketFill(7).height).toBeCloseTo(fill.maxHeight)
        T.expect(FirstPerson.bucketFill(-1).height).toBeCloseTo(fill.minHeight)
        T.expect(FirstPerson.bucketFill(0 / 0).height).toBeCloseTo(fill.minHeight)
    end)
    T.it("tankRatio: Anteil, begrenzt, Kapazität 0 oder NaN ergibt leer", function()
        T.expect(FirstPerson.tankRatio(25, 100)).toBeCloseTo(0.25)
        T.expect(FirstPerson.tankRatio(500, 100)).toBe(1)
        T.expect(FirstPerson.tankRatio(5, 0)).toBe(0)
        T.expect(FirstPerson.tankRatio(0 / 0, 100)).toBe(0)
        T.expect(FirstPerson.tankRatio(math.huge, 100)).toBe(0)
    end)
end)

T.describe("Maus", function()
    local closed = { windowOpen = false, treeOpen = false, toggled = false, guiNeedsCursor = false }
    T.it("ohne Fenster, Baum, Karte und Taste bleibt die Maus gesperrt", function()
        T.expect(FirstPerson.cursorFree(closed)).toBe(false)
    end)
    T.it("jeder einzelne Grund gibt sie frei", function()
        for _, key in { "windowOpen", "treeOpen", "toggled", "guiNeedsCursor" } do
            local state: any = table.clone(closed)
            state[key] = true
            T.expect(FirstPerson.cursorFree(state)).toBe(true)
        end
    end)
    T.it("Alt schaltet um, andere Tasten (E, linke Maustaste) nicht", function()
        T.expect(FirstPerson.isToggleKey("LeftAlt")).toBe(true)
        T.expect(FirstPerson.isToggleKey("E")).toBe(false)
        T.expect(FirstPerson.isToggleKey("Space")).toBe(false)
    end)
end)

T.describe("Eigene Maschine vor den Augen", function()
    local eye = Data.toolView.defaultEyeHeight
    T.it("Hand und Schaufel verdecken nichts", function()
        T.expect(#FirstPerson.blockingParts(ToolLooks.byToolId.hand, eye)).toBe(0)
        T.expect(#FirstPerson.blockingParts(ToolLooks.byToolId.shovel, eye)).toBe(0)
    end)
    T.it("Saugroboter und Mega-Maschine: der große Körper vor den Augen wird durchscheinend", function()
        T.expect(FirstPerson.blockingParts(ToolLooks.byToolId.vacuum_robot, eye)).toContain(1)
        T.expect(FirstPerson.blockingParts(ToolLooks.byToolId.mega_machine, eye)).toContain(3)
    end)
    T.it("Ketten, die tief neben dem Charakter liegen, bleiben sichtbar", function()
        local blocked = FirstPerson.blockingParts(ToolLooks.byToolId.mini_digger, eye)
        T.expect(table.find(blocked, 1)).toBeNil()
        T.expect(table.find(blocked, 2)).toBeNil()
    end)
    T.it("ein Teil hinter dem Charakter oder weit oben zählt nicht", function()
        local look = { parts = {
            { size = { x = 2, y = 2, z = 2 }, offset = { x = 0, y = eye, z = 5 } },
            { size = { x = 2, y = 2, z = 2 }, offset = { x = 0, y = eye + 10, z = -5 } },
            { size = { x = 2, y = 2, z = 2 }, offset = { x = 0, y = eye, z = -5 } },
        } }
        T.expect(FirstPerson.blockingParts(look, eye)).toEqual({ 3 })
    end)
    T.it("eine Drehung um 90 Grad zählt die gedrehte Ausdehnung", function()
        -- 10 lang entlang x, 6 Studs seitlich: ohne Drehung im Gang, um y gedreht (dann entlang z) nicht.
        local flat = { parts = { { size = { x = 10, y = 1, z = 1 }, offset = { x = 6, y = eye, z = -5 } } } }
        local turned = { parts = { { size = { x = 10, y = 1, z = 1 }, offset = { x = 6, y = eye, z = -5 }, rotation = { x = 0, y = 90, z = 0 } } } }
        T.expect(#FirstPerson.blockingParts(flat, eye)).toBe(1)
        T.expect(#FirstPerson.blockingParts(turned, eye)).toBe(0)
    end)
end)

T.finish()
