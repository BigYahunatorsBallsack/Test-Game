--!strict
-- Studio Edit only. Create the Canyon east of the oasis and keep a terrain snapshot.
local run = game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Use Studio Edit mode")
assert(game.PlaceId == 135831532782380, "Unexpected place")

local terrain = workspace.Terrain
local world = workspace:WaitForChild("DuneBaronWorld")
assert(world:GetAttribute("OasisTerrainRevision") == 1, "Oasis V1 required")
local storage = game:GetService("ServerStorage")
local V, rgb = Vector3.new, Color3.fromRGB
local owner = "DuneBaronCanyonArt"
local MIN, MAX = V(416,-24,476), V(1088,164,1060)
local VOXEL, PATCH = 4, 64
local sand, rock = Enum.Material.Sand, Enum.Material.Sandstone
local slots = {
    {54,sand,rgb(235,226,204)}, {55,sand,rgb(200,181,155)},
    {56,rock,rgb(141,90,73)}, {57,rock,rgb(177,119,94)},
    {58,rock,rgb(210,161,120)}, {59,rock,rgb(157,103,82)},
}
local canal = {
    -- X, centre Z, bed Y, half width
    {416,578,16,15},{448,578,16.5,17},{487,582,18.5,23},{526,593,16.5,32},
    {572,617,14.2,36},{620,653,12.0,38},{678,682,11.8,47},{732,679,12.7,36},
    {784,668,14.0,44},{833,681,15.9,45},{887,714,17.0,38},{944,763,20.1,53},
    {994,810,24.0,49},{1054,842,29.0,45},{1088,845,29.5,39},
}
local function smooth(t: number): number
    t=math.clamp(t,0,1)
    return t*t*(3-2*t)
end

local function section(x: number): (number,number,number)
    for i=1,#canal-1 do
        local a,b=canal[i],canal[i+1]
        if x<=b[1] then
            local prev,next=canal[math.max(1,i-1)],canal[math.min(#canal,i+2)]
            local w=b[1]-a[1]
            local s=(x-a[1])/w
            local da=(b[2]-prev[2])/(b[1]-prev[1])*w
            local db=(next[2]-a[2])/(next[1]-a[1])*w
            local z = (2*s^3-3*s*s+1)*a[2]+(s^3-2*s*s+s)*da+(-2*s^3+3*s*s)*b[2]+(s^3-s*s)*db
            local mix=smooth(s)
            return z,a[3]+(b[3]-a[3])*mix,a[4]+(b[4]-a[4])*mix
        end
    end
    error("Canyon x out of bounds")
end

local function swell(x: number, mid: number, width: number): number
    return math.exp(-((x-mid)/width)^2)
end

local function profile(x: number,z: number,axis: number,base: number,width: number)
    local delta=z-axis
    local distance=math.abs(delta)
    local farSide=if delta>0 then 1 else -1
    local recess=(if farSide==1 then 33*swell(x,666,41)+32*swell(x,867,37)
        else 25*swell(x,782,42)+14*swell(x,565,26))
    local irregular=5.7*math.noise(x/49,z/43,7.1)+3*math.noise(x/18,z/23,2.7)
    local wallDistance=distance-width-recess+irregular

    -- Low talus fans, steep visible faces, and broader cap rock behind the rim.
    local cliff = 13*smooth(wallDistance/16)
        + 24*smooth((wallDistance-12)/16)
        + 28*smooth((wallDistance-27)/17)
        + 18*smooth((wallDistance-45)/19)
    local shoulder=smooth((wallDistance-17)/30)*(11*math.noise(x/29,z/35,1.9)+5*math.noise(x/14,z/13,6.7))
    local weight=smooth((x-498)/80)*(1-smooth((x-1000)/80))
    local erosion=1+.16*math.sin(x/75+farSide*.94)+.09*math.noise(x/33,z/30,5.8)
    local bluff=(cliff*erosion+shoulder)*weight*(1-smooth((wallDistance-80)/68))
    local floorNoise=1.4*math.noise(x/34,z/23,2.2)+.65*math.noise(x/12,z/11,4.8)
    local ripple=if distance<14 then floorNoise*.37 else floorNoise
    local pavement = base + ripple + bluff
    local channel=(1-smooth((distance-width-2)/22))*smooth((x-MIN.X)/37)
    local slopes=(1-smooth((distance-width-recess-93)/46))*smooth((x-484)/90)
    local edge=math.min(x-MIN.X,MAX.X-x,z-MIN.Z,MAX.Z-z)
    local influence=math.max(channel,slopes)*smooth(edge/30)
    return pavement,influence,bluff,wallDistance
end

local function vox(p: Vector3): Vector3int16
    return Vector3int16.new(p.X/VOXEL,p.Y/VOXEL,p.Z/VOXEL)
end

for _,definition in slots do
    assert(terrain:GetMaterialSlot(definition[1])==nil, "Canyon material slot occupied")
end
local prior=storage:FindFirstChild("DuneBaron_PreCanyonTerrainV1")
local backup: Instance
local snapshot: TerrainRegion
if prior then
    assert(prior:GetAttribute("Owner")==owner and prior:GetAttribute("BuildStatus")=="RestoredAfterError", "Canyon snapshot already in use")
    assert(prior:GetAttribute("Min")==MIN and prior:GetAttribute("Max")==MAX, "Canyon bounds differ from snapshot")
    local region=prior:FindFirstChild("TerrainBeforeCanyon")
    assert(region and region:IsA("TerrainRegion"), "Canyon snapshot missing")
    backup,snapshot=prior,region
else
    backup=Instance.new("Folder")
    backup.Name="DuneBaron_PreCanyonTerrainV1"
    backup:SetAttribute("Owner",owner)
    backup:SetAttribute("Min",MIN)
    backup:SetAttribute("Max",MAX)
    snapshot=terrain:CopyRegion(Region3int16.new(vox(MIN),vox(MAX-V(4,4,4))))
    snapshot.Name="TerrainBeforeCanyon"
    snapshot.Parent=backup
    backup.Parent=storage
end
backup:SetAttribute("BuildError",nil)
backup:SetAttribute("BuildStatus","Running")
backup:SetAttribute("TilesWritten",0)

local channelNames={"SolidMaterialIndex","SolidOccupancy","LiquidOccupancy"}
local function build()
    for _,setting in slots do
        terrain:SetMaterialSlot(setting[1],setting[2],"",setting[3])
    end
    local ny,touched=(MAX.Y-MIN.Y)/VOXEL,0
    for x0=MIN.X,MAX.X-VOXEL,PATCH do
        for z0=MIN.Z,MAX.Z-VOXEL,PATCH do
            local x1,z1=math.min(x0+PATCH,MAX.X),math.min(z0+PATCH,MAX.Z)
            local region=Region3.new(V(x0,MIN.Y,z0),V(x1,MAX.Y,z1))
            local patch=terrain:ReadVoxelChannels(region,VOXEL,channelNames)
            local indexes,solid,liquid=patch.SolidMaterialIndex,patch.SolidOccupancy,patch.LiquidOccupancy
            local edited=false
            for a=1,(x1-x0)/VOXEL do
                local x=x0+(a-.5)*VOXEL
                local axis,base,width=section(x)
                for c=1,(z1-z0)/VOXEL do
                    local z=z0+(c-.5)*VOXEL
                    local target,mix,bluff,edge=profile(x,z,axis,base,width)
                    if mix>.002 then
                        local original,oldTop=MIN.Y,0
                        for b=ny,1,-1 do
                            local occupancy=solid[a][b][c]
                            if occupancy>.001 then
                                original=MIN.Y+(b-1+occupancy)*VOXEL
                                oldTop=indexes[a][b][c]
                                break
                            end
                        end
                        local height=original+(target-original)*mix
                        local colored=mix>(.54+.14*math.noise(x/19,z/22,5.1))
                        local face=bluff>8 and edge>7
                        local sandTint=if math.abs(z-axis)<width-4 then 54 else 55
                        for b=1,ny do
                            local bottom=MIN.Y+(b-1)*VOXEL
                            local fill=math.clamp((height-bottom)/VOXEL,0,1)
                            solid[a][b][c]=fill
                            if fill<=0 then
                                indexes[a][b][c]=0
                            elseif colored or oldTop==0 then
                                if face or bottom<height-17 then
                                    local stratum=(bottom + 5.8*math.sin((x-489)/83)+z*.036)%33
                                    indexes[a][b][c]=if stratum<8 then 56 elseif stratum<20 then 57 elseif stratum<26 then 58 else 59
                                else
                                    indexes[a][b][c]=sandTint
                                end
                            elseif indexes[a][b][c]==0 then
                                indexes[a][b][c]=oldTop
                            end
                            liquid[a][b][c]=math.min(liquid[a][b][c],1-fill)
                        end
                        edited=true
                    end
                end
            end
            if edited then
                terrain:WriteVoxelChannels(region,VOXEL,{
                    SolidMaterialIndex=indexes,SolidOccupancy=solid,LiquidOccupancy=liquid,
                })
                touched+=1
                backup:SetAttribute("TilesWritten",touched)
            end
            task.wait()
        end
    end
    world:SetAttribute("CanyonTerrainRevision",1)
    world:SetAttribute("CanyonBoundsMin",MIN)
    world:SetAttribute("CanyonBoundsMax",MAX)
    backup:SetAttribute("BuildStatus","Ready")
end

task.spawn(function()
    local ok,problem=pcall(build)
    if not ok then
        backup:SetAttribute("BuildError",tostring(problem))
        local restored,rollback=pcall(function()
            terrain:PasteRegion(snapshot,vox(MIN),true)
            for _,definition in slots do terrain:ResetMaterialSlot(definition[1]) end
        end)
        if not restored then backup:SetAttribute("RollbackError",tostring(rollback)) end
        backup:SetAttribute("BuildStatus",if restored then "RestoredAfterError" else "Failed")
        warn(problem)
    end
end)
return {zone="Canyon",minimum=MIN,maximum=MAX,status="building"}
