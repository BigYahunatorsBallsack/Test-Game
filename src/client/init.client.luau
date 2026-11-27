--!strict
-- Client-Bootstrap: lädt die Controller und ruft erst alle Init(), dann alle Start().

local CONTROLLER_NAMES = { "State", "Input", "FirstPerson", "Hud", "Dig", "ToolVisual", "ItemVisual", "ZoneMenu", "Weather", "Reveal", "CollectionBook", "Sandstorm", "CrateShop", "ProductPrices", "GemShop", "OfferHint", "Daily", "Codes", "SeasonPassMenu", "KolossBar", "SocialMenu", "OfflineCard", "EquipmentMenu", "SkillTree", "Tutorial" }

type Controller = {
    Init: () -> (),
    Start: () -> (),
}

print("[Client] Every Last Grain startet")

-- Überarbeitung Ü1: Controller ausgeschalteter Systeme (Data/Features) werden gar nicht geladen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("Features") :: ModuleScript) :: any
local ACTIVE_NAMES: { string } = Features.activeControllers(CONTROLLER_NAMES)

local controllersFolder = script:WaitForChild("Controllers")
local controllers: { Controller } = {}
for _, name in ACTIVE_NAMES do
    local module = controllersFolder:WaitForChild(name) :: ModuleScript
    table.insert(controllers, require(module) :: Controller)
end

-- Ein Fehler in einem Controller darf die folgenden nicht verhindern: Er wird gemeldet, die
-- anderen starten trotzdem (sonst fehlte durch einen Fehler im Baum auch das Tutorial).
for index, controller in controllers do
    local ok, err = pcall(controller.Init)
    if not ok then
        warn(`[Client] Init von {ACTIVE_NAMES[index]} fehlgeschlagen: {tostring(err)}`)
    end
end
for index, controller in controllers do
    local ok, err = pcall(controller.Start)
    if not ok then
        warn(`[Client] Start von {ACTIVE_NAMES[index]} fehlgeschlagen: {tostring(err)}`)
    end
end

print("[Client] Every Last Grain läuft")
