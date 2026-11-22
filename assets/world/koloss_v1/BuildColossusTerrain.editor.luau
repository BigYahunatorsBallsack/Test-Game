--!strict
-- Studio Edit only. Cut a terraced dig basin and a graded road into the starter dunes.
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Use Studio Edit mode")
assert(game.PlaceId==135831532782380,"Unexpected place")
local world=workspace:WaitForChild("DuneBaronWorld")
assert(world:GetAttribute("DunesTerrainRevision")==3,"Dune sea V3 required")
local terrain=workspace.Terrain
local storage=game:GetService("ServerStorage")
local V=Vector3.new
local MIN,MAX=V(-604,-24,-200),V(-44,92,168)
local GRID,TILE=4,48
local owner="DuneBaronColossusArt"
local anchor=V(-432,0,-24)

local roads={
    {V(-44,4,-10),V(-82,5,-10),V(-124,7,-17),V(-168,9,-30),V(-214,11.5,-43),
        V(-263,14,-44),V(-307,16.5,-24)},
    {V(-307,16.5,-24),V(-332,15,-64),V(-367,14,-88),V(-413,14,-98),V(-461,14,-92),V(-511,16,-66)},
    {V(-307,16.5,-24),V(-330,15.7,15),V(-371,13.7,48),V(-421,12.9,67),V(-473,14.1,57),V(-511,16,-66)},
    {V(-374,13.6,48),V(-387,11.2,30),V(-415,9.5,26),V(-428,9.5,18)},
}

local function smooth(t: number): number
    t=math.clamp(t,0,1)
    return t*t*(3-2*t)
end

local function road(x: number,z: number,track: {Vector3}): (number,number)
    local best,height=math.huge,0
    for i=1,#track-1 do
        local a,b=track[i],track[i+1]
        local dx,dz=b.X-a.X,b.Z-a.Z
        local u=math.clamp(((x-a.X)*dx+(z-a.Z)*dz)/(dx*dx+dz*dz),0,1)
        local px,pz=x-a.X-dx*u,z-a.Z-dz*u
        local d=px*px+pz*pz
        if d<best then best,height=d,a.Y+(b.Y-a.Y)*u end
    end
    return math.sqrt(best),height
end

local function drift(x: number,z: number,cx: number,cz: number,rx: number,rz: number,height: number): number
    return height*math.exp(-(((x-cx)/rx)^2+((z-cz)/rz)^2))
end

local function profile(x: number,z: number,existing: number): number
    local u,v=(x-anchor.X)/124,(z-anchor.Z)/77
    local theta=math.atan2(v,u)
    local radius=math.sqrt(u*u+v*v)/(1+.073*math.sin(3*theta+.24))+.045*math.noise(x/29,z/26,6.7)
    local bed=8.6+1.3*math.noise(x/28,z/27,2.3)
        +5.5*smooth((radius-.49)/.22)+4.4*smooth((radius-.79)/.13)+8.9*smooth((radius-1.02)/.18)
    bed+=drift(x,z,-405,-28,39,29,8.8)+drift(x,z,-407,-62,41,16,7.9)
    bed+=drift(x,z,-472,-37,24,29,4.8)+drift(x,z,-329,-21,39,24,5.8)
    local strength=1-smooth((radius-1.06)/.48)
    local grade=existing+(bed-existing)*strength
    for _,pad in {{-321,47,31,21,14.1},{-446,-96,31,21,14},{-356,15,23,18,13}} do
        local distance=math.sqrt(((x-pad[1])/pad[3])^2+((z-pad[2])/pad[4])^2)
        grade+=(pad[5]-grade)*(1-smooth((distance-.63)/.50))
    end
    for i,track in roads do
        local distance,slope=road(x,z,track)
        local width=if i==4 then 9 else 17
        local fringe=if i==4 then 12 else 27
        local lane=1-smooth((distance-width)/fringe)
        if i==1 then lane*=smooth((-x-44)/29) end
        grade+=(slope-grade)*lane
    end
    local edge=math.min(x-MIN.X,MAX.X-x,z-MIN.Z,MAX.Z-z)
    return existing+(grade-existing)*smooth(edge/28)
end

local function voxel(p: Vector3): Vector3int16
    return Vector3int16.new(p.X/GRID,p.Y/GRID,p.Z/GRID)
end

local backup=storage:FindFirstChild("DuneBaron_PreColossusTerrainV1")
local original: TerrainRegion
if backup then
    assert(backup:GetAttribute("Owner")==owner and backup:GetAttribute("BuildStatus")=="RestoredAfterError","Colossus backup already in use")
    assert(backup:GetAttribute("Min")==MIN and backup:GetAttribute("Max")==MAX,"Colossus bounds differ from snapshot")
    local saved=backup:FindFirstChild("TerrainBeforeColossus")
    assert(saved and saved:IsA("TerrainRegion"))
    original=saved
else
    backup=Instance.new("Folder")
    backup.Name="DuneBaron_PreColossusTerrainV1"
    backup:SetAttribute("Owner",owner)
    backup:SetAttribute("Min",MIN)
    backup:SetAttribute("Max",MAX)
    original=terrain:CopyRegion(Region3int16.new(voxel(MIN),voxel(MAX-V(4,4,4))))
    original.Name="TerrainBeforeColossus"
    original.Parent=backup
    backup.Parent=storage
end
local state=assert(backup)
state:SetAttribute("BuildStatus","Running")
state:SetAttribute("BuildError",nil)
state:SetAttribute("TilesWritten",0)
local channels={"SolidMaterialIndex","SolidOccupancy","LiquidOccupancy"}
local SAND=6 -- the existing dunes use Roblox's native sand voxel index

local function build()
    local edited,changedColumns=0,0
    local layers=(MAX.Y-MIN.Y)/GRID
    for x0=MIN.X,MAX.X-GRID,TILE do
        for z0=MIN.Z,MAX.Z-GRID,TILE do
            local x1,z1=math.min(x0+TILE,MAX.X),math.min(z0+TILE,MAX.Z)
            local region=Region3.new(V(x0,MIN.Y,z0),V(x1,MAX.Y,z1))
            local data=terrain:ReadVoxelChannels(region,GRID,channels)
            local solid,material,liquid=data.SolidOccupancy,data.SolidMaterialIndex,data.LiquidOccupancy
            local modified=false
            for i=1,(x1-x0)/GRID do
                for k=1,(z1-z0)/GRID do
                    local x,z=x0+(i-.5)*GRID,z0+(k-.5)*GRID
                    local existing=MIN.Y
                    for j=layers,1,-1 do
                        local fraction=solid[i][j][k]
                        if fraction>.005 then
                            existing=MIN.Y+(j-1+fraction)*GRID
                            break
                        end
                    end
                    local height=profile(x,z,existing)
                    if math.abs(height-existing)>.11 then
                        for j=1,layers do
                            local bottom=MIN.Y+(j-1)*GRID
                            if bottom+GRID>math.min(height,existing) or bottom>=existing then
                                local occ=math.clamp((height-bottom)/GRID,0,1)
                                solid[i][j][k]=occ
                                material[i][j][k]=if occ>0 then SAND else 0
                                liquid[i][j][k]=math.min(liquid[i][j][k],1-occ)
                            end
                        end
                        modified=true
                        changedColumns+=1
                    end
                end
            end
            if modified then
                terrain:WriteVoxelChannels(region,GRID,{SolidMaterialIndex=material,SolidOccupancy=solid,LiquidOccupancy=liquid})
                edited+=1
                state:SetAttribute("TilesWritten",edited)
            end
            task.wait()
        end
    end
    assert(changedColumns>3500,"Colossus dig terrain did not form")
    world:SetAttribute("ColossusTerrainRevision",1)
    world:SetAttribute("ColossusArtOrigin",anchor)
    state:SetAttribute("ChangedColumns",changedColumns)
    state:SetAttribute("BuildStatus","Ready")
end

task.spawn(function()
    local worked,reason=pcall(build)
    if not worked then
        state:SetAttribute("BuildError",tostring(reason))
        local restored,rollback=pcall(function() terrain:PasteRegion(original,voxel(MIN),true) end)
        if not restored then state:SetAttribute("RollbackError",tostring(rollback)) end
        state:SetAttribute("BuildStatus",if restored then "RestoredAfterError" else "Failed")
        warn(reason)
    end
end)
return {work="Colossus dig site",status="building",origin=anchor}
