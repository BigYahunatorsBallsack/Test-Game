--!strict
-- Standalone Studio exhibit. The project uses Controllers/SkillTree instead.
local gui = script.Parent
local art = require(gui.Workshop.Art)
local launch = art.button(gui, "Oeffnen", "Werkstatt")
launch.Position = UDim2.fromOffset(16, 16)
launch.Size = UDim2.fromOffset(130, 46)
local session
session = require(gui.Workshop).mount(gui, {
    baseNodes = require(gui.BaseTree).list,
    trialOnly = true,
    onClose = function()
        session.close()
        launch.Visible = true
    end,
})
local function open()
    launch.Visible = false
    session.open("tiefstich")
end
launch.Activated:Connect(open)
game:GetService("UserInputService").InputBegan:Connect(function(input)
    if
        session.visible()
        and (input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape)
    then
        session.back()
    end
end)
open()
