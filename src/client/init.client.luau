--!strict
-- Client-Bootstrap: lädt die Controller und ruft erst alle Init(), dann alle Start().

local CONTROLLER_NAMES = { "State", "Input", "Hud" }

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

for _, controller in controllers do
    controller.Init()
end
for _, controller in controllers do
    controller.Start()
end

print("[Client] Dune Baron läuft")
