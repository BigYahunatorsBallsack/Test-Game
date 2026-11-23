--!strict
-- Zielen beim Graben in der Ego-Perspektive: Das Loch folgt dem Fadenkreuz, begrenzt auf die Reichweite.

local T = require("./lib/expect")
local DigAim = require("../src/shared/Logic/DigAim")
local Tools = require("../src/shared/Data/Tools")
local ToolLooks = require("../src/shared/Data/ToolLooks")
local TerrainData = require("../src/shared/Data/Terrain")
local SandDig = require("../src/shared/Logic/SandDig")
local FirstPersonData = require("../src/shared/Data/FirstPerson")

local root = { x = 10, z = 20 }
local north = { x = 0, z = -1 }

local function dist(a: any, b: any): number
    return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

T.describe("Reichweite", function()
    T.it("für jedes Werkzeug: min < default < max, und das Loch erreicht den Charakter nie", function()
        local halfWidth = ToolLooks.limits.characterBox.halfWidth
        for _, tool in Tools.list do
            local r = DigAim.reach(tool.id)
            T.expect(r.min <= r.default).toBeTruthy()
            T.expect(r.default < r.max).toBeTruthy()
            local hole = SandDig.holeFor(TerrainData, tool.id)
            -- Ecke des Charakter-Quaders liegt halfWidth * Wurzel 2 vom Mittelpunkt entfernt.
            T.expect(r.min - hole.radius > halfWidth * math.sqrt(2)).toBeTruthy()
        end
    end)
    T.it("max liegt extraReachStuds hinter der Arbeitsspitze", function()
        local r = DigAim.reach("mega_machine")
        T.expect(r.max - r.default).toBeCloseTo(FirstPersonData.aim.extraReachStuds)
    end)
end)

T.describe("Zielpunkt", function()
    local reach = { min = 5, max = 12, default = 7 }
    T.it("Treffer innerhalb der Reichweite: genau dort", function()
        local p = DigAim.target(root, north, { x = 13, z = 12 }, reach) :: any
        T.expect(p.x).toBeCloseTo(13)
        T.expect(p.z).toBeCloseTo(12)
    end)
    T.it("Treffer zu nah (vor den Füßen): auf min hinausgeschoben, gleiche Richtung", function()
        local p = DigAim.target(root, north, { x = 10, z = 18 }, reach) :: any
        T.expect(dist(p, root)).toBeCloseTo(5)
        T.expect(p.x).toBeCloseTo(10)
        T.expect(p.z < root.z).toBeTruthy()
    end)
    T.it("Treffer zu weit: auf max zurückgeholt", function()
        local p = DigAim.target(root, north, { x = 40, z = 20 }, reach) :: any
        T.expect(dist(p, root)).toBeCloseTo(12)
        T.expect(p.z).toBeCloseTo(20)
    end)
    T.it("seitlich oder hinter dem Charakter zielen geht auch (folgt dem Zeiger)", function()
        local p = DigAim.target(root, north, { x = 10, z = 28 }, reach) :: any
        T.expect(p.z).toBeCloseTo(28)
    end)
    T.it("ohne Treffer (Himmel): Arbeitsspitze in Blickrichtung", function()
        local p = DigAim.target(root, { x = 3, z = 0 }, nil, reach) :: any
        T.expect(p.x).toBeCloseTo(17)
        T.expect(p.z).toBeCloseTo(20)
    end)
    T.it("Treffer genau unter dem Charakter: Blickrichtung mit min", function()
        local p = DigAim.target(root, north, { x = 10, z = 20 }, reach) :: any
        T.expect(p.z).toBeCloseTo(15)
    end)
    T.it("ungültige Eingaben ergeben nil statt Fehler", function()
        T.expect(DigAim.target({ x = 0 / 0, z = 0 }, north, nil, reach)).toBeNil()
        T.expect(DigAim.target(root, { x = 0, z = 0 }, nil, reach)).toBeNil()
        T.expect(DigAim.target(root, { x = 0, z = 0 }, { x = 10, z = 20 }, reach)).toBeNil()
        local p = DigAim.target(root, north, { x = math.huge, z = 0 }, reach) :: any
        T.expect(p.z).toBeCloseTo(13) -- ungültiger Treffer zählt wie kein Treffer
    end)
end)

T.describe("Sandfluss der Maschine", function()
    T.it("weit weg: schnell genug, um in der Lebenszeit anzukommen", function()
        T.expect(DigAim.flowSpeed(12, 0.5, 6)).toBeCloseTo(24)
    end)
    T.it("nah: nie langsamer als die Grundgeschwindigkeit", function()
        T.expect(DigAim.flowSpeed(1, 0.5, 6)).toBeCloseTo(6)
    end)
    T.it("ungültige Werte: Grundgeschwindigkeit", function()
        T.expect(DigAim.flowSpeed(0 / 0, 0.5, 6)).toBe(6)
        T.expect(DigAim.flowSpeed(10, 0, 6)).toBe(6)
    end)
end)

T.finish()
