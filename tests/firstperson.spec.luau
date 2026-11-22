--!strict
-- Ego-Perspektive: Armhaltung, Maus, Sicht auf die eigene Maschine und Tabellenprüfung.

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

local still = { pitch = 0, t = 0, collecting = false, speed = 0 }

T.describe("Tabelle FirstPerson", function()
    T.it("die mitgelieferte Tabelle ist fehlerfrei", function()
        T.expect(table.concat(FirstPerson.check(), "\n")).toBe("")
    end)

    T.it("jedes Werkzeug hat eine Armhaltung, sonst meldet die Prüfung es", function()
        for _, tool in Tools.list do
            T.expect(Data.arms[tool.id] ~= nil).toBeTruthy()
        end
        T.expect(errorsFor(function(d)
            d.arms.shovel = nil
        end)).toContain("shovel")
    end)

    T.it("meldet unbekannten Grabstil, falsches Sichtfeld, leere Tasten und fehlenden Standard", function()
        T.expect(errorsFor(function(d)
            d.arms.hand.dig = "gibtsnicht"
        end)).toContain("Grabstil")
        T.expect(errorsFor(function(d)
            d.camera.fieldOfView = 200
        end)).toContain("fieldOfView")
        T.expect(errorsFor(function(d)
            d.cursor.toggleKeys = {}
        end)).toContain("toggleKeys")
        T.expect(errorsFor(function(d)
            d.defaultArms = "weg"
        end)).toContain("defaultArms")
        T.expect(errorsFor(function(d)
            d.digStyles.scoop.period = 0
        end)).toContain("period")
        T.expect(errorsFor(function(d)
            d.toolView.fadeTo = 2
        end)).toContain("fadeTo")
    end)
end)

T.describe("Armhaltung", function()
    T.it("im Stand ohne Blickneigung gilt die Grundhaltung, der linke Arm gespiegelt", function()
        local pose = FirstPerson.armPose("shovel", still)
        local style = Data.arms.shovel
        T.expect(pose.right.x).toBeCloseTo(style.right.x)
        T.expect(pose.right.y).toBeCloseTo(style.right.y)
        T.expect(pose.left.x).toBeCloseTo(style.left.x)
        T.expect(pose.left.y).toBeCloseTo(-style.left.y)
        T.expect(pose.left.z).toBeCloseTo(-style.left.z)
    end)

    T.it("die Arme liegen in der Grundhaltung vorn im Bild (zwischen 45 und 135 Grad gehoben)", function()
        for id, style in Data.arms do
            for _, side in { "right", "left" } do
                local x = style[side].x
                if x < 45 or x > 135 then
                    error(`arms.{id}.{side}.x = {x}`)
                end
            end
        end
    end)

    T.it("unbekanntes oder fehlendes Werkzeug bekommt die Standardhaltung", function()
        local fallback = FirstPerson.armPose(Data.defaultArms, still)
        T.expect(FirstPerson.armPose("gibtsnicht", still)).toEqual(fallback)
        T.expect(FirstPerson.armPose(nil, still)).toEqual(fallback)
    end)

    T.it("Blick nach oben hebt die Arme, nach unten senkt sie, begrenzt durch min/maxPitch", function()
        local base = FirstPerson.armPose("hand", still).right.x
        local up = FirstPerson.armPose("hand", { pitch = 30, t = 0, collecting = false, speed = 0 }).right.x
        local down = FirstPerson.armPose("hand", { pitch = -30, t = 0, collecting = false, speed = 0 }).right.x
        T.expect(up > base).toBeTruthy()
        T.expect(down < base).toBeTruthy()
        local extreme = FirstPerson.armPose("hand", { pitch = 89, t = 0, collecting = false, speed = 0 }).right.x
        T.expect(extreme).toBeCloseTo(base + Data.camera.maxPitch * Data.camera.pitchFollow)
    end)

    T.it("beim Sammeln schwingen die Arme, ohne Sammeln nicht", function()
        local quarter = Data.digStyles.scoop.period / 4
        local idle = FirstPerson.armPose("hand", { pitch = 0, t = quarter, collecting = false, speed = 0 })
        local digging = FirstPerson.armPose("hand", { pitch = 0, t = quarter, collecting = true, speed = 0 })
        T.expect(idle.right.x).toBeCloseTo(Data.arms.hand.right.x)
        T.expect(digging.right.x).toBeCloseTo(Data.arms.hand.right.x + Data.digStyles.scoop.swing.x)
        -- Gegentakt: der linke Arm schwingt zur selben Zeit in die andere Richtung.
        T.expect(digging.left.x).toBeCloseTo(Data.arms.hand.left.x - Data.digStyles.scoop.swing.x)
    end)

    T.it("die Schaufel sticht mit beiden Armen gleichzeitig", function()
        local quarter = Data.digStyles.stab.period / 4
        local pose = FirstPerson.armPose("shovel", { pitch = 0, t = quarter, collecting = true, speed = 0 })
        T.expect(pose.right.x - Data.arms.shovel.right.x).toBeCloseTo(pose.left.x - Data.arms.shovel.left.x)
    end)

    T.it("Wippen beim Laufen wächst mit der Geschwindigkeit und ist bei 0 aus", function()
        local t = 1 / (4 * Data.walk.bobHz)
        local stand = FirstPerson.armPose("hand", { pitch = 0, t = t, collecting = false, speed = 0 })
        local slow = FirstPerson.armPose("hand", { pitch = 0, t = t, collecting = false, speed = Data.walk.fullSpeed / 2 })
        local fast = FirstPerson.armPose("hand", { pitch = 0, t = t, collecting = false, speed = Data.walk.fullSpeed * 3 })
        T.expect(stand.right.x).toBeCloseTo(Data.arms.hand.right.x)
        T.expect(slow.right.x - stand.right.x).toBeCloseTo(Data.walk.bobDegrees / 2)
        T.expect(fast.right.x - stand.right.x).toBeCloseTo(Data.walk.bobDegrees)
    end)

    T.it("ungültige Zahlen (NaN, unendlich) ergeben die Grundhaltung und keinen Fehler", function()
        local pose = FirstPerson.armPose("hand", { pitch = 0 / 0, t = math.huge, collecting = false, speed = 0 / 0 })
        T.expect(pose.right.x).toBeCloseTo(Data.arms.hand.right.x)
    end)

    T.it("pitchFromLook rechnet Grad aus der Blickrichtung", function()
        T.expect(FirstPerson.pitchFromLook(0)).toBeCloseTo(0)
        T.expect(FirstPerson.pitchFromLook(1)).toBeCloseTo(90)
        T.expect(FirstPerson.pitchFromLook(-0.5)).toBeCloseTo(-30)
        T.expect(FirstPerson.pitchFromLook(5)).toBeCloseTo(90)
    end)

    T.it("Glättung geht weich aufs Ziel und bleibt zwischen 0 und 1", function()
        local a = FirstPerson.smoothAlpha(1 / 60, Data.smoothing)
        T.expect(a > 0 and a < 1).toBeTruthy()
        T.expect(FirstPerson.smoothAlpha(10, Data.smoothing)).toBeCloseTo(1, 1e-3)
        T.expect(FirstPerson.smoothAlpha(0, Data.smoothing)).toBe(0)
        local p = FirstPerson.approachPose({ x = 0, y = 0, z = 0 }, { x = 10, y = -10, z = 4 }, 0.5)
        T.expect(p).toEqual({ x = 5, y = -5, z = 2 })
    end)
end)

T.describe("Körperteile", function()
    T.it("nur die Arme von R15 und R6 bleiben sichtbar", function()
        for _, name in { "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand", "Left Arm", "Right Arm" } do
            T.expect(FirstPerson.isArmPart(name)).toBe(true)
        end
        for _, name in { "Head", "UpperTorso", "Torso", "LeftFoot", "HumanoidRootPart", "Handle" } do
            T.expect(FirstPerson.isArmPart(name)).toBe(false)
        end
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
