--!strict
-- Studio Edit only. Extend the dunes beyond their eastern rim with a shallow salt basin.
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Use Studio Edit mode")
assert(game.PlaceId==135831532782380,"Unexpected place")
local world=workspace:WaitForChild("DuneBaronWorld")
assert(world:GetAttribute("CanyonTerrainRevision")==1,"Canyon V1 required")
local terrain=workspace.Terrain
local storage=game:GetService("ServerStorage")
local V,rgb=Vector3.new,Color3.fromRGB
local MIN,MAX=V(1056,-24,556),V(1728,140,1212)
local GRID,TILE=4,64
local CX,CZ,RX,RZ,WATER=1381,871,145,99,16.2
local owner="DuneBaronSaltLakeArt"
local slots={
    {60,rgb(235,227,203)}, -- dry crystalline sand
    {61,rgb(194,207,196)}, -- cool, damp margin
}
local roads={
    {V(1056,29,842),V(1103,27,841),V(1154,23.7,826),V(1207,21.5,802),
     V(1249,20.7,772),V(1303,20.1,751),V(1375,20.4,741),V(1442,20.8,750),
     V(1504,21.5,772),V(1560,22.8,805),V(1610,25.0,814),V(1678,27.5,837),V(1727,29.7,853)},
    {V(1193,21.7,809),V(1195,21.2,862),V(1206,21.2,913),V(1246,20.4,970),
     V(1302,20.9,1001),V(1376,20.8,1016),V(1445,21.1,1006),V(1510,22.0,989),
     V(1554,22.8,951),V(1572,23.2,897),V(1593,24.2,850),V(1610,25.0,814)},
}

local function smooth(t: number): number
    t=math.clamp(t,0,1)
    return t*t*(3-2*t)
end

local function road(x: number,z: number): (number,number)
    local best,y=math.huge,0
    for _,track in roads do
        for i=1,#track-1 do
            local a,b=track[i],track[i+1]
            local dx,dz=b.X-a.X,b.Z-a.Z
            local u=math.clamp(((x-a.X)*dx+(z-a.Z)*dz)/(dx*dx+dz*dz),0,1)
            local px,pz=x-a.X-dx*u,z-a.Z-dz*u
            local distance=px*px+pz*pz
            if distance<best then best,y=distance,a.Y+(b.Y-a.Y)*u end
        end
    end
    return math.sqrt(best),y
end

local function shelf(x: number,z: number,tx: number,tz: number,wx: number,wz: number,h: number): number
    return h*math.exp(-(((x-tx)/wx)^2+((z-tz)/wz)^2))
end

local function mesa(x: number,z: number,tx: number,tz: number,wx: number,wz: number,h: number,seed: number): number
    local u,v=math.abs((x-tx)/wx),math.abs((z-tz)/wz)
    local dist=(u^2.3+v^2.3)^(1/2.3)+.10*math.noise(x/39,z/32,seed)+.040*math.noise(x/13,z/18,seed+1)
    return h*(.48*smooth((1.33-dist)/.59)+.34*smooth((.91-dist)/.37)+.18*smooth((.60-dist)/.32))
end

local function form(x: number,z: number)
    local u,v=(x-CX)/RX,(z-CZ)/RZ
    local a=math.atan2(v,u)
    local edge=1+.063*math.sin(a*3-.60)+.047*math.cos(a*7+.30)
    local ring=math.sqrt(u*u+v*v)/edge+.030*math.noise(x/31,z/28,9.2)
    local floor=WATER-5+1.3*math.noise(x/42,z/43,1.7)
    local bank=19.6+2.1*math.noise(x/40,z/43,5.1)+1.7*math.noise(x/25,z/18,2.6)
    local grade=floor+(bank-floor)*smooth((ring-.70)/.43)
    local apparentShelf=shelf(x,z,1309,841,31,17,8.9)+shelf(x,z,1438,846,23,13,8.8)
        +shelf(x,z,1398,918,29,15,8.8)+shelf(x,z,1473,912,22,15,7.5)
    if ring<1.01 then grade+=apparentShelf end
    local mountains=
        mesa(x,z,1172,667,75,73,54,1)+mesa(x,z,1293,641,103,67,62,3)
        +mesa(x,z,1450,655,81,62,51,9)+mesa(x,z,1555,678,80,59,53,12)
        +mesa(x,z,1270,1118,121,71,50,13)+mesa(x,z,1447,1100,109,65,43,17)
        +mesa(x,z,1582,1066,113,75,66,22)+mesa(x,z,1671,941,69,84,61,24)
    mountains*=smooth((ring-1.15)/.56)
    grade+=mountains+2.7*smooth((ring-1.04)/.56)
    local dist,roadY=road(x,z)
    local lane=(1-smooth((dist-12)/21))*smooth((ring-.94)/.18)
    grade+=(roadY-grade)*lane
    mountains*=1-lane
    return grade,ring,mountains,dist
end

local function voxel(p: Vector3): Vector3int16
    return Vector3int16.new(p.X/GRID,p.Y/GRID,p.Z/GRID)
end

for _,definition in slots do
    assert(terrain:GetMaterialSlot(definition[1])==nil,"Salt lake material slot occupied")
end
local backup=storage:FindFirstChild("DuneBaron_PreSaltLakeTerrainV1")
local original: TerrainRegion
if backup then
    assert(backup:GetAttribute("Owner")==owner and backup:GetAttribute("BuildStatus")=="RestoredAfterError","Salt lake backup already in use")
    assert(backup:GetAttribute("Min")==MIN and backup:GetAttribute("Max")==MAX,"Salt lake bounds differ from snapshot")
    local saved=backup:FindFirstChild("TerrainBeforeSaltLake")
    assert(saved and saved:IsA("TerrainRegion"))
    original=saved
else
    backup=Instance.new("Folder")
    backup.Name="DuneBaron_PreSaltLakeTerrainV1"
    backup:SetAttribute("Owner",owner)
    backup:SetAttribute("Min",MIN)
    backup:SetAttribute("Max",MAX)
    original=terrain:CopyRegion(Region3int16.new(voxel(MIN),voxel(MAX-V(4,4,4))))
    original.Name="TerrainBeforeSaltLake"
    original.Parent=backup
    backup.Parent=storage
end
local state=assert(backup)
state:SetAttribute("BuildStatus","Running")
state:SetAttribute("BuildError",nil)
state:SetAttribute("TilesWritten",0)
local names={"SolidMaterialIndex","SolidOccupancy","LiquidOccupancy"}

local function build()
    for _,definition in slots do
        terrain:SetMaterialSlot(definition[1],Enum.Material.Sand,"",definition[2])
    end
    local edited,wet=0,0
    for x0=MIN.X,MAX.X-4,TILE do
        for z0=MIN.Z,MAX.Z-4,TILE do
            local x1,z1=math.min(x0+TILE,MAX.X),math.min(z0+TILE,MAX.Z)
            local region=Region3.new(V(x0,MIN.Y,z0),V(x1,MAX.Y,z1))
            local patch=terrain:ReadVoxelChannels(region,GRID,names)
            local solid,materials,liquid=patch.SolidOccupancy,patch.SolidMaterialIndex,patch.LiquidOccupancy
            local ny=(MAX.Y-MIN.Y)/GRID
            local changed=false
            for i=1,(x1-x0)/GRID do
                for k=1,(z1-z0)/GRID do
                    local x,z=x0+(i-.5)*GRID,z0+(k-.5)*GRID
                    local mix=smooth((x-MIN.X)/91)
                    -- Keep the older dunes intact where the new east plateau meets their flank.
                    if x<1152 then mix*=smooth(math.min(z-MIN.Z,MAX.Z-z)/93) end
                    if mix>.003 then
                        local target,ring,stone,distance=form(x,z)
                        local existing,topSlot=MIN.Y,0
                        for j=ny,1,-1 do
                            local occupancy=solid[i][j][k]
                            if occupancy>.001 then
                                existing=MIN.Y+(j-1+occupancy)*GRID
                                topSlot=materials[i][j][k]
                                break
                            end
                        end
                        local height=if topSlot==0 then target else existing+(target-existing)*mix
                        local water=ring<1.045 and height<WATER and mix>.98
                        if water then wet+=1 end
                        local isSalt=mix>.56+.12*math.noise(x/31,z/29,9.1) or topSlot==0
                        for j=1,ny do
                            local bottom=MIN.Y+(j-1)*GRID
                            local fraction=math.clamp((height-bottom)/GRID,0,1)
                            solid[i][j][k]=fraction
                            if fraction<=0 then
                                materials[i][j][k]=0
                            elseif isSalt then
                                if (stone>9 and distance>28) or bottom<height-20 then
                                    local band=(bottom+.022*x+.031*z+3.1*math.sin(z/66))%29
                                    materials[i][j][k]=if band<8 then 56 elseif band<17 then 57 elseif band<23 then 58 else 59
                                else
                                    materials[i][j][k]=if ring<1.04 then 61 else 60
                                end
                            elseif materials[i][j][k]==0 then
                                materials[i][j][k]=topSlot
                            end
                            liquid[i][j][k]=if water then math.clamp((WATER-bottom)/GRID-fraction,0,1-fraction)
                                else math.min(liquid[i][j][k],1-fraction)
                        end
                        changed=true
                    end
                end
            end
            if changed then
                terrain:WriteVoxelChannels(region,GRID,{SolidMaterialIndex=materials,SolidOccupancy=solid,LiquidOccupancy=liquid})
                edited+=1
                state:SetAttribute("TilesWritten",edited)
            end
            task.wait()
        end
    end
    assert(wet>1000,"Salt Lake did not fill")
    world:SetAttribute("SaltLakeTerrainRevision",1)
    world:SetAttribute("SaltLakeBoundsMin",MIN)
    world:SetAttribute("SaltLakeBoundsMax",MAX)
    world:SetAttribute("SaltLakeWaterLine",WATER)
    state:SetAttribute("WetColumns",wet)
    state:SetAttribute("BuildStatus","Ready")
end

task.spawn(function()
    local ok,reason=pcall(build)
    if not ok then
        state:SetAttribute("BuildError",tostring(reason))
        local restored,rollback=pcall(function()
            terrain:PasteRegion(original,voxel(MIN),true)
            for _,definition in slots do terrain:ResetMaterialSlot(definition[1]) end
        end)
        if not restored then state:SetAttribute("RollbackError",tostring(rollback)) end
        state:SetAttribute("BuildStatus",if restored then "RestoredAfterError" else "Failed")
        warn(reason)
    end
end)
return {zone="Salzsee",center=V(CX,WATER,CZ),status="building"}
