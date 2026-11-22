--!strict
-- Client, while holding collect with sufficient free tank capacity.
local player=game.Players.LocalPlayer
assert(player:GetAttribute("IsCollecting")==true,"Server has not confirmed collecting")
local model=player.Character:FindFirstChild("DuneBaronEquipment")
assert(model,"Equipment missing")
local samples={}
for _,motor in model:GetDescendants() do
    if motor:IsA("Motor6D") then
        samples[motor]={initial=motor.Transform,part=motor.Part0.CFrame:ToObjectSpace(motor.Part1.CFrame),jointMax=0,partMax=0}
    end
end
assert(next(samples),"No work motors")
for _=1,8 do
    task.wait(0.05)
    for motor,s in samples do
        s.jointMax=math.max(s.jointMax,select(2,(s.initial:Inverse()*motor.Transform):ToAxisAngle()))
        local actual=motor.Part0.CFrame:ToObjectSpace(motor.Part1.CFrame)
        s.partMax=math.max(s.partMax,select(2,(s.part:Inverse()*actual):ToAxisAngle()))
    end
end
local result={}
for motor,s in samples do
    assert(s.jointMax>0.005 and s.partMax>0.005,"Work group did not move: "..motor:GetAttribute("MotionGroup"))
    table.insert(result,{group=motor:GetAttribute("MotionGroup"),jointMax=s.jointMax,actualPartMax=s.partMax})
end
assert(player:GetAttribute("IsCollecting")==true,"Tank filled before movement check completed")
return {tool=model:GetAttribute("ToolId"),groups=result}
