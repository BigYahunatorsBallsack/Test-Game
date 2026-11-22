--!strict
-- Client playtest: set EquipmentTestExpected on LocalPlayer, then run this check.
local player=game.Players.LocalPlayer
local expected=player:GetAttribute("EquipmentTestExpected") or "shovel"
local character=player.Character
assert(character,"Character missing")
local model=character:FindFirstChild("DuneBaronEquipment")
if expected=="hand" then
    assert(model==nil,"Hand must not leave an equipment model")
    return {tool="hand",parts=0}
end
assert(model and model:IsA("Model"),"Equipment model missing")
assert(model:GetAttribute("ToolId")==expected,"Wrong equipment stage")
local parts=0
for _,d in model:GetDescendants() do
    assert(not d:IsA("LuaSourceContainer"),"Executable content copied into equipment")
    if d:IsA("BasePart") then
        parts+=1
        assert(not d.Anchored and d.Massless and not d.CanCollide and not d.CanTouch and not d.CanQuery,
            "Equipment affects physics or digging queries")
        local weld=d:FindFirstChild("EquipmentWeld") or d:FindFirstChild("WorkMotor")
        assert(weld and (weld:IsA("WeldConstraint") or weld:IsA("Motor6D")) and weld.Part0 and weld.Part0:IsDescendantOf(character)
            and weld.Part1==d,"Equipment part not attached to current character")
    end
end
assert(parts>0,"Empty equipment")
local models=0
for _,d in character:GetChildren() do if d.Name=="DuneBaronEquipment" then models+=1 end end
assert(models==1,"Duplicate equipment")
return {tool=expected,parts=parts,health=character:FindFirstChildOfClass("Humanoid").Health}
