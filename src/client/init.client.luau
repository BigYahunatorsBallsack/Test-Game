--!strict
-- Client-Bootstrap: lädt die Controller und ruft erst alle Init(), dann alle Start().

local CONTROLLER_NAMES = { "State", "Input", "Hud", "Dig", "ToolVisual", "ItemVisual", "ZoneMenu", "Weather", "Reveal", "CollectionBook", "Sandstorm", "CrateShop", "ProductPrices", "GemShop", "OfferHint", "Daily", "Codes", "OfflineCard", "EquipmentMenu", "SkillTree", "Tutorial" }

type Controller = {
    Init: () -> (),
    Start: () -> (),
}

print("[Client] Dune Baron startet")

local controllersFolder = script:WaitForChild("Controllers")
local controllers: { Controller } = {}
for _, name in CONTROLLER_NAMES do
    local module = controllersFolder:WaitForChild(name) :: ModuleScript
    table.insert(controllers, require(module) :: Controller)
end

-- Ein Fehler in einem Controller darf die folgenden nicht verhindern: Er wird gemeldet, die
-- anderen starten trotzdem (sonst fehlte durch einen Fehler im Baum auch das Tutorial).
for index, controller in controllers do
    local ok, err = pcall(controller.Init)
    if not ok then
        warn(`[Client] Init von {CONTROLLER_NAMES[index]} fehlgeschlagen: {tostring(err)}`)
    end
end
for index, controller in controllers do
    local ok, err = pcall(controller.Start)
    if not ok then
        warn(`[Client] Start von {CONTROLLER_NAMES[index]} fehlgeschlagen: {tostring(err)}`)
    end
end

print("[Client] Dune Baron läuft")
