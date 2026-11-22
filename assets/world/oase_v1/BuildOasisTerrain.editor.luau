--!strict
-- Studio Edit only. Sculpt the oasis into the existing Dünenmeer terrain.
local run = game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Use Studio Edit mode")
assert(game.PlaceId == 135831532782380, "Unexpected place")

local terrain = workspace.Terrain
local world = workspace:WaitForChild("DuneBaronWorld")
assert(world:GetAttribute("DunesTerrainRevision") == 3, "Dünenmeer V3 required")
local storage = game:GetService("ServerStorage")
local V, rgb = Vector3.new, Color3.fromRGB
local owner = "DuneBaronOasisArt"
local GRID, TILE, LOW, HIGH = 4, 64, -16, 112
local XMIN, XMAX, ZMIN, ZMAX = 104, 552, 400, 880
local WATER, CX, CZ = 8.5, 318, 653
local air, sand, stone = Enum.Material.Air, Enum.Material.Sand, Enum.Material.Sandstone
local slots = {
    {48, sand, rgb(196, 105, 68)},
    {49, sand, rgb(224, 153, 100)},
    {50, sand, rgb(156, 102, 69)},
    {51, stone, rgb(156, 86, 65)},
    {52, stone, rgb(197, 113, 79)},
    {53, stone, rgb(219, 147, 100)},
}

local function voxel(x: number, y: number, z: number): Vector3int16
    return Vector3int16.new(x / GRID, y / GRID, z / GRID)
end

local prior = storage:FindFirstChild("DuneBaron_PreOasisTerrainV1")
assert(not prior or prior:GetAttribute("Owner") == owner, "Oasis backup name in use")
assert(not prior or prior:GetAttribute("BuildStatus") ~= "Running", "Oasis build still running")
if not prior then
    for _, definition in slots do
        assert(terrain:GetMaterialSlot(definition[1]) == nil, "Oasis material slot already occupied")
    end
    prior = Instance.new("Folder")
    prior.Name = "DuneBaron_PreOasisTerrainV1"
    prior:SetAttribute("Owner", owner)
    prior:SetAttribute("WaterColor", terrain.WaterColor)
    prior:SetAttribute("WaterTransparency", terrain.WaterTransparency)
    prior:SetAttribute("WaterReflectance", terrain.WaterReflectance)
    prior:SetAttribute("WaterWaveSize", terrain.WaterWaveSize)
    prior:SetAttribute("WaterWaveSpeed", terrain.WaterWaveSpeed)
    local snapshot = terrain:CopyRegion(Region3int16.new(voxel(XMIN,LOW,ZMIN),voxel(XMAX-4,HIGH-4,ZMAX-4)))
    snapshot.Name = "TerrainBeforeOasis"
    snapshot.Parent = prior
    prior.Parent = storage
else
    local snapshot = prior:FindFirstChild("TerrainBeforeOasis")
    assert(snapshot and snapshot:IsA("TerrainRegion"), "Oasis snapshot missing")
    terrain:PasteRegion(snapshot, voxel(XMIN,LOW,ZMIN), true)
end
local backup = prior
backup:SetAttribute("BuildStatus", "Running")
backup:SetAttribute("TilesWritten", 0)

local function smooth(t: number): number
    t = math.clamp(t, 0, 1)
    return t*t*(3-2*t)
end

local roads = {
    {V(116,10,420),V(135,12.8,445),V(154,17.2,472),V(176,20.4,502),
        V(198,18.7,529),V(218,13.7,561),V(236,11.7,591),V(247,11.5,614)},
    {V(238,11.7,593),V(272,11.4,582),V(305,11.9,574),
        V(334,12.55,575),V(362,12.9,580),V(389,13.15,594),V(405,13.9,620)},
    {V(247,11.5,614),V(228,12.1,643),V(226,12.45,672),V(237,12.9,699),
        V(254,13.35,717),V(283,14,725),V(313,14.1,728),V(344,15.6,724)},
}

local function nearestRoad(x: number, z: number): (number, number)
    local best, elevation = math.huge, 0
    for _, road in roads do
        for i=1,#road-1 do
            local a,b = road[i],road[i+1]
            local dx,dz = b.X-a.X,b.Z-a.Z
            local t = math.clamp(((x-a.X)*dx+(z-a.Z)*dz)/(dx*dx+dz*dz),0,1)
            local ex,ez = x-a.X-t*dx,z-a.Z-t*dz
            local d = ex*ex+ez*ez
            if d < best then
                best, elevation = d,a.Y+t*(b.Y-a.Y)
            end
        end
    end
    return math.sqrt(best),elevation
end

local function mesa(x: number, z: number, mx: number, mz: number, rx: number, rz: number, height: number, seed: number): number
    local u,v = (x-mx)/rx,(z-mz)/rz
    local rough = 0.086*math.noise(x/31,z/37,seed)+0.033*math.noise(x/11,z/14,seed+1)
    local r = (math.abs(u)^2.65+math.abs(v)^2.65)^(1/2.65)+rough
    local skirt = 0.49*smooth((1.24-r)/0.57)
    local ledge = 0.34*smooth((0.90-r)/0.32)
    local top = 0.17*smooth((0.56-r)/0.35)
    return height*(skirt+ledge+top)
end

local function profile(x: number,z: number)
    local dx,dz = x-CX,z-CZ
    local u,v = dx / 82,dz / 58
    local theta = math.atan2(v,u)
    local shape = 1 + 0.070*math.sin(theta*3+0.43) + 0.049*math.cos(theta*5-0.7)
    local ring = math.sqrt(u*u+v*v) / shape + 0.039 * math.noise(x/23,z/26,8.4)

    local h = WATER + (ring-1)*24
    local bank = 13.9 + 2.3*math.noise(x/38,z/48,4.7) + 1.3*math.noise(x/21,z/17,11.7)
    if ring > 1.15 then
        h += (bank-h)*smooth((ring-1.15)/0.22)
    elseif ring < 0.46 then
        h = WATER-14 + 1.4*math.noise(x/20,z/27,8.1)
    end
    local islet = math.exp(-(((x-337)/13.3)^2+((z-668)/10.8)^2)/1.12)
    h += 16.1*islet

    local ledges = mesa(x,z,329,774,107,47,42,2.2)
        +mesa(x,z,459,695,51,105,55,7.4)
        +mesa(x,z,439,758,73,45,26,13.3)
        +mesa(x,z,222,745,37,53,25,3.2)
    ledges *= smooth((ring-1.09)/0.55)
    local d,pathY = nearestRoad(x,z)
    local roadBlend = (1-smooth((d-7)/23))
    if ring<1.04 and z>540 then roadBlend *= smooth((ring-.94)/.1) end
    h += ledges
    h += (pathY-h)*roadBlend
    ledges *= 1-roadBlend

    local outerRadius = math.sqrt(((x-322)/198)^2+((z-654)/178)^2)
    local plaza = 1-smooth((outerRadius-.79)/.41)
    local approach = (1-smooth((d-8)/25))*smooth((z-415)/29)*(1-smooth((z-604)/38))
    local edge = math.min(x-XMIN,XMAX-x,z-ZMIN,ZMAX-z)
    local influence = math.max(plaza,approach)*smooth(edge/18)
    return h,influence,ring,ledges,d
end

local function build()
    for _, definition in slots do
        terrain:SetMaterialSlot(definition[1], definition[2], "", definition[3])
    end
    terrain.WaterColor = rgb(41, 151, 143)
    terrain.WaterTransparency = 0.36
    terrain.WaterReflectance = 0.21
    terrain.WaterWaveSize = 0.17
    terrain.WaterWaveSpeed = 11

    local count, ny = 0, (HIGH-LOW)/GRID
    local channelNames = {"SolidMaterialIndex","SolidOccupancy","LiquidOccupancy"}
    for x0=XMIN,XMAX-GRID,TILE do
        for z0=ZMIN,ZMAX-GRID,TILE do
            local x1,z1 = math.min(x0+TILE,XMAX),math.min(z0+TILE,ZMAX)
            local patch = Region3.new(V(x0,LOW,z0),V(x1,HIGH,z1))
            local current = terrain:ReadVoxelChannels(patch,GRID,channelNames)
            local indexes, solids, liquid = current.SolidMaterialIndex,current.SolidOccupancy,current.LiquidOccupancy
            for ix=1,(x1-x0)/GRID do
                local x = x0+(ix-.5)*GRID
                for iz=1,(z1-z0)/GRID do
                    local z = z0+(iz-.5)*GRID
                    local target,alpha,ring,ledge,road = profile(x,z)
                    if alpha>.001 then
                        local oldHeight = LOW
                        local oldSlot = 0
                        for iy=ny,1,-1 do
                            if solids[ix][iy][iz]>.001 then
                                oldHeight = LOW+(iy-1+solids[ix][iy][iz])*GRID
                                oldSlot = indexes[ix][iy][iz]
                                break
                            end
                        end
                        local height = oldHeight+(target-oldHeight)*alpha
                        local reddish = alpha > .58 + math.noise(x/20,z/24,1.6)*.20
                        for iy=1,ny do
                            local bottom = LOW+(iy-1)*GRID
                            local fill = math.clamp((height-bottom)/GRID,0,1)
                            solids[ix][iy][iz] = fill
                            local slot = oldSlot
                            if fill<=0 then
                                slot = 0
                            elseif reddish or oldSlot==0 then
                                if ledge>7 and road>16 and bottom>WATER+4 then
                                    local band = (bottom+x*.027+z*.013)%24
                                    slot = if band<7 then 51 elseif band<17 then 52 else 53
                                elseif ring>.91 and ring<1.12 then
                                    slot = if bottom<=WATER then 50 else 49
                                elseif road<7.4 and ring>1.02 then
                                    slot = 49
                                else
                                    slot = 48
                                end
                            end
                            indexes[ix][iy][iz] = slot
                            if ring<1.02 and alpha>.95 and height<WATER then
                                liquid[ix][iy][iz] = math.clamp((WATER-bottom)/GRID,0,1-fill)
                            else
                                liquid[ix][iy][iz] = 0
                            end
                        end
                    end
                end
            end
            terrain:WriteVoxelChannels(patch,GRID,{
                SolidMaterialIndex=indexes,SolidOccupancy=solids,LiquidOccupancy=liquid,
            })
            count += 1
            if count%3==0 then
                backup:SetAttribute("TilesWritten",count)
                task.wait()
            end
        end
    end
    backup:SetAttribute("TilesWritten",count)
    world:SetAttribute("OasisTerrainRevision",1)
    world:SetAttribute("OasisBoundsMin",V(XMIN,LOW,ZMIN))
    world:SetAttribute("OasisBoundsMax",V(XMAX,HIGH,ZMAX))
    backup:SetAttribute("BuildStatus","Ready")
end

task.spawn(function()
    local ok, reason = pcall(build)
    if not ok then
        backup:SetAttribute("BuildStatus","Failed")
        backup:SetAttribute("BuildError",tostring(reason))
        warn(reason)
    end
end)
return {zone="Oase",waterCenter=V(CX,WATER,CZ),bounds=V(XMAX-XMIN,HIGH-LOW,ZMAX-ZMIN),status="building"}
