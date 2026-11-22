--!strict
-- Studio Edit only. Build a black-sand basin with a graded approach from the salt pass.
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Use Studio Edit mode")
assert(game.PlaceId==135831532782380,"Unexpected place")
local world=workspace:WaitForChild("DuneBaronWorld")
assert(world:GetAttribute("SaltLakeTerrainRevision")==1,"Salt Lake V1 required")
local terrain=workspace.Terrain
local storage=game:GetService("ServerStorage")
local V,rgb=Vector3.new,Color3.fromRGB
local MIN,MAX=V(1672,-24,620),V(2448,160,1324)
local GRID,TILE=4,64
local owner="DuneBaronRuinsArt"
local slots={
    {62,rgb(54,49,57)},
    {63,rgb(39,34,43)},
}

local roads={
    {V(1672,27.2,836),V(1714,29,851),V(1760,30.1,869),V(1810,32.7,874),V(1874,34,866),
        V(1935,34.2,860),V(1993,34.2,856),V(2065,35.5,866),V(2150,39,881),
        V(2215,42,882),V(2290,45.4,881),V(2378,48,900)},
    {V(1935,34.2,860),V(1947,34.7,826),V(1970,35.9,802),V(2017,36,789),
        V(2084,36.9,793),V(2156,40,810),V(2200,41,846),V(2215,42,882)},
    {V(1935,34.2,860),V(1953,34.3,907),V(2002,35,947),V(2062,36,974),
        V(2121,37.1,975),V(2167,38.2,955),V(2204,40.3,920),V(2215,42,882)},
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
            local d=px*px+pz*pz
            if d<best then best,y=d,a.Y+(b.Y-a.Y)*u end
        end
    end
    return math.sqrt(best),y
end

local function mesa(x: number,z: number,cx: number,cz: number,inX: number,inZ: number,h: number,seed: number): number
    local u,v=math.abs((x-cx)/inX),math.abs((z-cz)/inZ)
    local dr=(u^2.4+v^2.4)^(1/2.4)+.13*math.noise(x/32,z/28,seed)
    return h*(.4*smooth((1.36-dr)/.56)+.34*smooth((.92-dr)/.37)+.26*smooth((.60-dr)/.22))
end

local function form(x: number,z: number): (number,number,number)
    local dist,roadY=road(x,z)
    local phase=(z+.29*(x-1900)+33*math.noise(x/117,z/145,4.4))/82
    local u=(phase%1+.61)%1
    local dune=if u<.73 then smooth(u/.73) else smooth((1-u)/.27)
    local amplitude=5+12*smooth((dist-20)/108)+6*math.noise(x/105,z/92,7.2)
    local floor=27+math.clamp((x-1815)*.033,-2,18)+dune*amplitude+4*math.noise(x/44,z/60,13.1)
    local rim=mesa(x,z,1812,743,61,56,55,19)+mesa(x,z,1917,684,128,50,62,21)
        +mesa(x,z,2103,679,94,52,79,29)+mesa(x,z,2285,704,122,59,89,27)
        +mesa(x,z,1821,990,93,79,62,4)+mesa(x,z,1965,1118,152,70,56,9)
        +mesa(x,z,2188,1149,155,100,61,3)+mesa(x,z,2371,1048,89,93,76,11)
    local lane=1-smooth((dist-16)/31)
    local height=floor+rim
    height+=(roadY-height)*lane
    -- Widen the city courtyards independently of the parade road.
    for _,yard in {
        {1993,856,60,43,34.2}, {2021,761,42,28,36},
        {2090,931,49,37,36.3}, {2262,880,52,60,42.7},
    } do
        local d=math.sqrt(((x-yard[1])/yard[3])^2+((z-yard[2])/yard[4])^2)
        local amount=.99*(1-smooth((d-.64)/.59))
        height+=(yard[5]-height)*amount
        rim*=1-amount
    end
    return height,rim*(1-lane),dune
end

local function voxel(p: Vector3): Vector3int16
    return Vector3int16.new(p.X/GRID,p.Y/GRID,p.Z/GRID)
end

for _,slot in slots do
    assert(terrain:GetMaterialSlot(slot[1])==nil,"Ruins material slot occupied")
end
local backup=storage:FindFirstChild("DuneBaron_PreRuinsTerrainV1")
local original: TerrainRegion
if backup then
    assert(backup:GetAttribute("Owner")==owner and backup:GetAttribute("BuildStatus")=="RestoredAfterError","Ruins backup already in use")
    assert(backup:GetAttribute("Min")==MIN and backup:GetAttribute("Max")==MAX,"Ruins bounds differ from snapshot")
    local saved=backup:FindFirstChild("TerrainBeforeRuins")
    assert(saved and saved:IsA("TerrainRegion"))
    original=saved
else
    backup=Instance.new("Folder")
    backup.Name="DuneBaron_PreRuinsTerrainV1"
    backup:SetAttribute("Owner",owner)
    backup:SetAttribute("Min",MIN)
    backup:SetAttribute("Max",MAX)
    original=terrain:CopyRegion(Region3int16.new(voxel(MIN),voxel(MAX-V(4,4,4))))
    original.Name="TerrainBeforeRuins"
    original.Parent=backup
    backup.Parent=storage
end
local state=assert(backup)
state:SetAttribute("BuildStatus","Running")
state:SetAttribute("BuildError",nil)
state:SetAttribute("TilesWritten",0)
local channels={"SolidMaterialIndex","SolidOccupancy","LiquidOccupancy"}

local function build()
    for _,slot in slots do
        terrain:SetMaterialSlot(slot[1],Enum.Material.Sand,"",slot[2])
    end
    local edited=0
    for x0=MIN.X,MAX.X-GRID,TILE do
        for z0=MIN.Z,MAX.Z-GRID,TILE do
            local x1,z1=math.min(x0+TILE,MAX.X),math.min(z0+TILE,MAX.Z)
            local region=Region3.new(V(x0,MIN.Y,z0),V(x1,MAX.Y,z1))
            local patch=terrain:ReadVoxelChannels(region,GRID,channels)
            local solid,materials,liquid=patch.SolidOccupancy,patch.SolidMaterialIndex,patch.LiquidOccupancy
            local ny=(MAX.Y-MIN.Y)/GRID
            for i=1,(x1-x0)/GRID do
                for k=1,(z1-z0)/GRID do
                    local x,z=x0+(i-.5)*GRID,z0+(k-.5)*GRID
                    local target,rim,dune=form(x,z)
                    local mix=smooth((x-MIN.X)/99)
                    local existing,topSlot=MIN.Y,0
                    for j=ny,1,-1 do
                        local occupancy=solid[i][j][k]
                        if occupancy>.001 then
                            existing=MIN.Y+(j-1+occupancy)*GRID
                            topSlot=materials[i][j][k]
                            break
                        end
                    end
                    -- Pull the next plateau under the outside of the salt shelf. Overlap feathered in height and colour.
                    local height=if topSlot==0 then target else existing+(target-existing)*mix
                    if x>1714 and x<1742 and topSlot~=0 then
                        local edge=smooth((x-1714)/26)
                        height+=(target-height)*edge
                    end
                    local black=topSlot==0 or mix>.38+.19*math.noise(x/24,z/41,9.1)
                    for j=1,ny do
                        local bottom=MIN.Y+(j-1)*GRID
                        local frac=math.clamp((height-bottom)/GRID,0,1)
                        solid[i][j][k]=frac
                        liquid[i][j][k]=math.min(liquid[i][j][k],1-frac)
                        if frac==0 then
                            materials[i][j][k]=0
                        elseif black then
                            if rim>17 or bottom<height-18 then
                                local band=(bottom+.018*x+.037*z+5*math.sin(x/90))%29
                                materials[i][j][k]=if band<8 then 56 elseif band<17 then 57 elseif band<23 then 58 else 59
                            else
                                materials[i][j][k]=if dune+.32*math.noise(x/22,z/22,2.6)>.78 then 63 else 62
                            end
                        elseif materials[i][j][k]==0 then
                            materials[i][j][k]=topSlot
                        end
                    end
                end
            end
            terrain:WriteVoxelChannels(region,GRID,{SolidMaterialIndex=materials,SolidOccupancy=solid,LiquidOccupancy=liquid})
            edited+=1
            state:SetAttribute("TilesWritten",edited)
            task.wait()
        end
    end
    world:SetAttribute("RuinsTerrainRevision",1)
    world:SetAttribute("RuinsBoundsMin",MIN)
    world:SetAttribute("RuinsBoundsMax",MAX)
    state:SetAttribute("BuildStatus","Ready")
end

task.spawn(function()
    local ok,reason=pcall(build)
    if not ok then
        state:SetAttribute("BuildError",tostring(reason))
        local restored,rollback=pcall(function()
            terrain:PasteRegion(original,voxel(MIN),true)
            for _,slot in slots do terrain:ResetMaterialSlot(slot[1]) end
        end)
        if not restored then state:SetAttribute("RollbackError",tostring(rollback)) end
        state:SetAttribute("BuildStatus",if restored then "RestoredAfterError" else "Failed")
        warn(reason)
    end
end)
return {zone="Ruinenstadt",status="building",min=MIN,max=MAX}
