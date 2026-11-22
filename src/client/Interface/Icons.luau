--!strict
local Catalog = require(script.Parent.Catalog) :: any
local ids = require(script.Parent.AtlasIds) :: {[string]: string}
local Icons = {}

function Icons.Set(label: ImageLabel, name: string)
    local icon = Catalog.icons[name]
    assert(icon ~= nil, "Icon missing from atlas: " .. name)
    label.ImageRectOffset = Vector2.new(icon.x,icon.y)
    label.ImageRectSize = Vector2.new(Catalog.cell,Catalog.cell)
    label.Image = ids[icon.page]
    label:SetAttribute("AtlasIcon",name)
end

return Icons
