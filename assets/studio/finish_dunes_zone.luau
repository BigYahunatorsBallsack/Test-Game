--!strict
local world=workspace.DuneBaronWorld
assert(not world:GetAttribute("FinishingCompleted"), "Finishing already applied")
local terrain=workspace.Terrain
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Include
params.FilterDescendantsInstances={terrain}
local function ground(x:number,z:number): number
    local hit=workspace:Raycast(Vector3.new(x,100,z),Vector3.new(0,-180,0),params)
    assert(hit,"No terrain under prop")
    return hit.Position.Y
end
for _,m in world.Props:GetChildren() do
    if m:IsA("Model") then m:PivotTo(m:GetPivot()+Vector3.new(0,2,0)) end
end
for _,p in world.Environment:GetChildren() do
    if p:IsA("BasePart") then
        if p.Name:match("^Sandstone_") then
            local index=p.Name:match("^Sandstone_(%d+)_")
            if index then
                p.CFrame+=Vector3.new(0,ground(p.Position.X,p.Position.Z)-6,0)
            end
        elseif p.Name:match("^DesertRock_") then
            p.CFrame=CFrame.new(p.Position.X,ground(p.Position.X,p.Position.Z)+p.Size.Y*0.2,p.Position.Z)*p.CFrame.Rotation
        else p.CFrame+=Vector3.new(0,2,0) end
    end
end
world.DunesSpawn.CFrame+=Vector3.new(0,2,0)
world.IntegrationMarkers.SellStand.CFrame+=Vector3.new(0,2,0)
world.IntegrationMarkers.SandField.CFrame+=Vector3.new(0,2,0)
world.IntegrationMarkers.SellStand.CanQuery=false
local function part(name:string,size:Vector3,cf:CFrame,color:Color3,mat:Enum.Material):Part
    local p=Instance.new("Part")
    p.Name,p.Size,p.CFrame,p.Color,p.Material=name,size,cf,color,mat
    p.Anchored=true
    p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    p.Parent=world.Environment
    return p
end
local wood=Color3.fromRGB(112,70,42)
local teal=Color3.fromRGB(31,111,120)
local stone=Color3.fromRGB(202,147,82)
-- Twin flags and barrels frame the camp entrance, with a distinct work-yard silhouette.
for side=-1,1,2 do
    local x=side*13
    part("CampFlagPole",Vector3.new(0.35,12,0.35),CFrame.new(x,12,-15),wood,Enum.Material.Wood)
    local flag=part("CampFlag",Vector3.new(3.5,2.4,0.12),CFrame.new(x+1.65,16,-15)*CFrame.Angles(0,math.rad(side*12),0),teal,Enum.Material.Fabric)
    flag.CanCollide=false
end
for i=1,4 do
    local x,z=-15-(i%2)*2.4,-28+math.floor(i/2)*2.5
    local barrel=part("SupplyBarrel",Vector3.new(2.8,2,2),CFrame.new(x,7.4,z)*CFrame.Angles(0,0,math.pi/2),wood,Enum.Material.Wood)
    barrel.Shape=Enum.PartType.Cylinder
    for _,dy in {-0.9,0.9} do
        local band=part("BarrelBand",Vector3.new(0.22,2.1,2.1),CFrame.new(x,7.4+dy,z)*CFrame.Angles(0,0,math.pi/2),Color3.fromRGB(63,70,69),Enum.Material.Metal)
        band.Shape=Enum.PartType.Cylinder
    end
end
-- A low ruin and excavation posts make the first digging destination readable.
for i=1,6 do
    local x,z=-38+(i-1)*4,83
    local h=if i==1 or i==6 then 8 else 3
    part("ExcavationRuin",Vector3.new(3.8,h,3),CFrame.new(x,6+h/2-0.3,z)*CFrame.Angles(0,math.rad(i%2*3),0),stone,Enum.Material.Sandstone)
    if i==1 or i==6 then
        part("RuinCap",Vector3.new(5,1.2,4),CFrame.new(x,13.6,z),Color3.fromRGB(224,173,100),Enum.Material.Sandstone)
    end
end
for i=1,8 do
    local a=math.pi*2*i/8
    local x,z=-24+math.cos(a)*17,64+math.sin(a)*14
    part("DigSitePost",Vector3.new(0.4,2,0.4),CFrame.new(x,7,z),wood,Enum.Material.Wood)
end
for i=1,6 do
    local x,z=-8-i*2.2,24+i*4.6
    local p=part("DigTrailStone",Vector3.new(1.8,0.25,1.2),CFrame.new(x,6.1,z)*CFrame.Angles(0,i*0.4,0),stone,Enum.Material.Sandstone)
    p.CanCollide=false
end
-- Keep the generated merchant details non-colliding; deck/counter provide simple collision.
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(-40,24,47),Vector3.new(16,9,-17))
world:SetAttribute("FinishingCompleted",true)
return {ground=ground(0,56),environmentParts=#world.Environment:GetChildren()}
