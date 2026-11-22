local p=game.Players.LocalPlayer
task.wait(1.5)
assert(p:GetAttribute("IsCollecting")==false,"Work still active")
local motor=p.Character.DuneBaronEquipment.WorkPivot_leftDrum.WorkMotor
local minAngle,maxAngle=math.huge,0
for _=1,18 do
    game:GetService("RunService").Heartbeat:Wait()
    local angle=select(2,motor.Transform:ToAxisAngle())
    minAngle=math.min(minAngle,angle)
    maxAngle=math.max(maxAngle,angle)
end
assert(maxAngle-minAngle<0.002,"Idle pose flickers: "..minAngle.." to "..maxAngle)
return {idleMinAngle=minAngle,idleMaxAngle=maxAngle,tank=p.PlayerGui.DuneBaronHud.Panel.TankBar.Tank.Text}
