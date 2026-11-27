--!strict
-- Überarbeitung Ü5: ein Stil für die Oberfläche. Prüft den Code der Menüs (keine eigenen Farben und
-- Schriften), die Fund-Bilder und dass die Werkstatt nur echte Knoten aus UpgradeTree zeigt.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local T = require("./lib/expect")
local Finds = require("../src/shared/Data/Finds")
local UpgradeTree = require("../src/shared/Data/UpgradeTree")
local UiCatalog = require("../src/client/Interface/Catalog")

-- Controller der eingeschalteten Systeme mit Oberfläche. Welt-Effekte (Sand, Wetter, Maschinen,
-- Glitzern, Freischalt-Licht) und die ausgeschalteten Systeme (kommen mit Ü11) zählen nicht.
local UI_CONTROLLERS = {
    "CrateShop", "GemShop", "EquipmentMenu", "ZoneMenu", "Tutorial", "Sandstorm", "CollectionBook",
    "Screen", "Hud", "Reveal", "Input", "SkillTree", "FirstPerson",
}

local function source(path: string): string
    return fs.readFile(path)
end

T.describe("Ein Stil: Menüs", function()
    T.it("kein Menü setzt eigene Farben (Zahlen in Color3) oder eigene Schriften", function()
        for _, name in UI_CONTROLLERS do
            local text = source(`src/client/Controllers/{name}.luau`)
            local color = string.match(text, "Color3%.fromRGB%(%s*%d") or string.match(text, "Color3%.new%(%s*%d")
            if color ~= nil then
                error(`{name}: eigene Farbe gefunden ({color}), bitte Theme.ui nehmen`)
            end
            if string.find(text, "Enum.Font.", 1, true) ~= nil then
                error(`{name}: eigene Schrift gefunden, bitte Theme.font nehmen`)
            end
            T.expect(string.find(text, "Interface\"):WaitForChild(\"Theme\")", 1, true) ~= nil).toBe(true)
        end
    end)

    T.it("die Werkstatt hat keine eigenen Farben oder Schriften mehr", function()
        for _, file in fs.readDir("src/client/Interface/Workshop") do
            if string.sub(file, -5) == ".luau" then
                local text = source(`src/client/Interface/Workshop/{file}`)
                T.expect(string.match(text, "Color3%.fromRGB%(%s*%d")).toBeNil()
                T.expect(string.match(text, "Color3%.new%(%s*%d")).toBeNil()
                T.expect(string.find(text, "Enum.Font.", 1, true)).toBeNil()
                T.expect(string.find(text, "hex(\"", 1, true)).toBeNil()
            end
        end
    end)

    T.it("Theme hat alle Farben und Schriften, die der Baukasten nutzt", function()
        local text = source("src/client/Interface/Theme.luau")
        for _, key in { "backdrop", "panel", "row", "slot", "button", "text", "muted", "accent", "teal", "good", "warn", "danger", "gem", "ink", "white", "black" } do
            T.expect(string.find(text, `    {key} = `, 1, true) ~= nil).toBe(true)
        end
        for _, key in { "title", "bold", "body" } do
            T.expect(string.find(text, `    {key} = Enum.Font.`, 1, true) ~= nil).toBe(true)
        end
    end)
end)

T.describe("Ein Stil: Fund-Bilder", function()
    T.it("jedes Fundstück hat ein eigenes Bild, das im Atlas steht", function()
        local seen: { [string]: boolean } = {}
        for _, find in Finds.list do
            T.expect(type(find.icon)).toBe("string")
            T.expect(UiCatalog.icons[find.icon] ~= nil).toBe(true)
            T.expect(seen[find.icon]).toBeNil()
            seen[find.icon] = true
        end
    end)

    T.it("Bilder bleiben in ihrer Zone (Dünenmeer-Bild nur für Dünenmeer-Funde)", function()
        local prefix = { dunes = "duenenmeer_", oasis = "oase_", canyon = "canyon_", salt_lake = "salzsee_", ruins = "ruinenstadt_" }
        for _, find in Finds.list do
            T.expect(string.sub(find.icon, 1, #prefix[find.zoneId])).toBe(prefix[find.zoneId])
        end
    end)
end)

T.describe("Ein Stil: Werkstatt", function()
    local function loadCatalog(): any
        local function readJson(name: string): any
            return serde.decode("json", fs.readFile(`src/client/Interface/Workshop/{name}.json`))
        end
        local fakeScript = { Parent = { Devices = "Devices", Support = "Support" } }
        return luau.load(fs.readFile("src/client/Interface/Workshop/Catalog.luau"), {
            environment = { script = fakeScript, require = readJson },
        })()
    end

    T.it("zeigt nur Knoten aus UpgradeTree, mit Spielpreis und Voraussetzungen", function()
        local catalog = loadCatalog().build(UpgradeTree.list)
        local count = 0
        for id, node in catalog.byId do
            local real = UpgradeTree.byId[id]
            T.expect(real ~= nil).toBe(true)
            T.expect(node.cost).toBe(real.cost)
            T.expect(node.requires).toEqual(real.requires)
            count += 1
        end
        T.expect(count).toBe(#UpgradeTree.list)
        T.expect(#catalog.devices).toBe(0)
    end)

    T.it("die Entwürfe gibt es nur noch auf Wunsch (für Ü7)", function()
        local catalog = loadCatalog().build(UpgradeTree.list, { drafts = true })
        T.expect(#catalog.devices > 0).toBe(true)
    end)
end)
