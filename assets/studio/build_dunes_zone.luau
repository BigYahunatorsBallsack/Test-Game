--!strict
-- Edit-time scene builder; run once through Studio execute_luau in Edit mode.
-- Package 1.5: environment only. Uses the existing World.luau tags.
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local terrain = workspace.Terrain
local library = ServerStorage:WaitForChild("DuneBaronAssetLibrary")
local core = library:WaitForChild("Core")
assert(workspace:FindFirstChild("DuneBaronWorld") == nil, "Zone already exists; inspect before rebuilding")

-- Preserve the affected region and global settings before changing the scene.
local backup = Instance.new("Folder")
backup.Name = "DuneBaronWorldBackup"
assert(ServerStorage:FindFirstChild(backup.Name) == nil, "Previous backup exists")
backup.Parent = ServerStorage
local minCell, maxCell = Vector3int16.new(-64,-16,-64), Vector3int16.new(64,24,64)
local terrainBefore = terrain:CopyRegion(Region3int16.new(minCell,maxCell))
terrainBefore.Name = "TerrainBefore"
terrainBefore.Parent = backup
backup:SetAttribute("TerrainMinCell", Vector3.new(-64,-16,-64))
backup:SetAttribute("SandColor", terrain:GetMaterialColor(Enum.Material.Sand))
for _,key in {"ClockTime","Brightness","Ambient","OutdoorAmbient","ExposureCompensation","GlobalShadows"} do
    backup:SetAttribute(key, (Lighting :: any)[key])
end
local gallery = workspace:FindFirstChild("DuneBaron_AssetTests")
if gallery then gallery.Parent = backup end
local oldSpawn = workspace:FindFirstChild("SpawnLocation")
if oldSpawn and oldSpawn:IsA("SpawnLocation") then
    backup:SetAttribute("OriginalSpawnEnabled", oldSpawn.Enabled)
    oldSpawn.Parent = backup
end
local base = workspace:FindFirstChild("Baseplate")
if base and base:IsA("BasePart") then
    backup:SetAttribute("BaseplateTransparency", base.Transparency)
    backup:SetAttribute("BaseplateCanCollide", base.CanCollide)
    base.Transparency = 1
    base.CanCollide = false
end

local world = Instance.new("Folder")
world.Name = "DuneBaronWorld"
world:SetAttribute("Package", "1.5")
world:SetAttribute("EnvironmentOnly", true)
world.Parent = workspace
local environment = Instance.new("Folder")
environment.Name = "Environment"
environment.Parent = world
local props = Instance.new("Folder")
props.Name = "Props"
props.Parent = world
local markers = Instance.new("Folder")
markers.Name = "IntegrationMarkers"
markers.Parent = world

terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(235,195,123))
terrain:FillBlock(CFrame.new(0,-16,0),Vector3.new(512,40,512),Enum.Material.Sand)
-- Smooth shallow dunes framing an open, walkable central basin.
local dunes = {
    {-164,-48,-132,83},{-102,-56,-172,86},{-20,-58,-186,87},
    {88,-44,-168,80},{164,-47,-112,83},{186,-56,-22,82},
    {168,-50,80,83},{120,-57,166,86},{22,-52,184,84},
    {-84,-48,170,82},{-164,-53,106,84},{-190,-57,8,86},
    {-108,-59,74,69},{96,-59,98,70},
}
for i,d in dunes do
    terrain:FillBall(Vector3.new(d[1],d[2],d[3]),d[4],Enum.Material.Sand)
    if i%4==0 then task.wait() end
end

local sand = Color3.fromRGB(210,142,79)
local terracotta = Color3.fromRGB(180,96,58)
local wood = Color3.fromRGB(121,75,43)
local teal = Color3.fromRGB(30,105,112)
local function part(name: string,size: Vector3,cf: CFrame,color: Color3,material: Enum.Material,parent: Instance): Part
    local p = Instance.new("Part")
    p.Name,p.Size,p.CFrame,p.Color,p.Material = name,size,cf,color,material
    p.Anchored = true
    p.TopSurface,p.BottomSurface = Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end

-- Layered angular sandstone on the horizon; low instance count, no imported textures.
local cliffs = {{-166,-138,48,38,24},{-120,-174,50,46,-8},{-66,-190,42,33,12},
    {142,-156,45,39,-22},{183,-106,42,48,12},{-196,76,38,34,-16},
    {166,156,54,36,18},{92,195,40,31,-12}}
for i,c in cliffs do
    for layer=1,3 do
        local width = c[3]*(1-(layer-1)*0.12)
        local height = c[4]/3
        part("Sandstone_"..i.."_"..layer,Vector3.new(width,height,22-layer*2),
            CFrame.new(c[1],4+height*(layer-0.5),c[2])*CFrame.Angles(0,math.rad(c[5]),math.rad((layer-2)*2)),
            if layer==2 then terracotta else sand,Enum.Material.Sandstone,environment)
    end
end

local function placeModel(id: string,name: string,position: Vector3,angle: number,height: number,burial: number?): Model
    local source = core:FindFirstChild(id)
    assert(source and source:IsA("Model"),"Missing core model: "..id)
    local model = source:Clone() :: Model
    model.Name = name
    model:ScaleTo(model:GetScale()*height/model:GetExtentsSize().Y)
    model:PivotTo(CFrame.Angles(0,math.rad(angle),0))
    local box,size = model:GetBoundingBox()
    local bottom = box.Position-Vector3.new(0,size.Y/2,0)
    model:PivotTo(model:GetPivot()+(position-bottom-Vector3.new(0,burial or 0,0)))
    for _,d in model:GetDescendants() do
        if d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
            d.CanTouch = false
        end
    end
    model:SetAttribute("SourceCoreId",id)
    model.Parent = props
    return model
end

-- Camp: merchant and a clear teal route from spawn toward the sand.
part("MerchantDeck",Vector3.new(20,0.6,13),CFrame.new(0,4.3,-30),wood,Enum.Material.WoodPlanks,environment)
placeModel("merchant_stall","Merchant",Vector3.new(0,4.6,-31),180,10)
placeModel("crate_wood","MerchantCrate",Vector3.new(-9,4,-25),18,2.8)
placeModel("crate_iron","SupplyCrate",Vector3.new(-11,4,-30),-12,2.5)
placeModel("fennec","CampFennec",Vector3.new(10,4,-26),-30,2.6)
-- Solid simple collision proxies keep generated details from trapping players.
part("MerchantCounterCollision",Vector3.new(9,3.5,3),CFrame.new(0,6.35,-28),wood,Enum.Material.Wood,environment).Transparency=1
local stand = part("SellStand",Vector3.new(1,1,1),CFrame.new(0,6,-21),teal,Enum.Material.SmoothPlastic,markers)
stand.Transparency,stand.CanCollide,stand.CanTouch = 1,false,false
stand:AddTag("SellStand")
-- SandField is a non-queryable tutorial target; digging rays must hit actual Terrain.
local field = part("SandField",Vector3.new(1,1,1),CFrame.new(0,4,56),sand,Enum.Material.Sand,markers)
field.Transparency,field.CanCollide,field.CanTouch,field.CanQuery = 1,false,false,false
field:AddTag("SandField")
for i=1,5 do
    part("PathStone_"..i,Vector3.new(3.6,0.2,2),CFrame.new(0,4.12,-10+i*5)*CFrame.Angles(0,math.rad(i%2*10-5),0),
        Color3.fromRGB(216,172,107),Enum.Material.Sandstone,environment)
end

-- Progression silhouettes in a work yard, leaving the first digging field open.
placeModel("shovel","ShovelAtCamp",Vector3.new(9,4,-19),-25,4)
placeModel("bucket_chain","BucketConveyor",Vector3.new(27,4,-22),-75,6)
placeModel("excavator","MiniExcavator",Vector3.new(39,4,4),-40,9)
placeModel("suction_robot","VacuumRobot",Vector3.new(54,4,-15),-80,6)
placeModel("harvester","DuneHarvester",Vector3.new(88,4,-10),-25,24)
-- Treasure partially exposed beside the accessible field.
placeModel("crate_gold","BuriedTreasure",Vector3.new(-23,4,68),25,3.5,1.2)
for i,id in {"duenenmeer_01","duenenmeer_03","duenenmeer_08"} do
    local source = library.Finds.duenenmeer:FindFirstChild(id)
    if source and source:IsA("Model") then
        local model = source:Clone()
        model.Name = "ExposedFind_"..id
        model:ScaleTo(model:GetScale()*1.2/model:GetExtentsSize().Y)
        model:PivotTo(CFrame.new(-30+i*5,4.4,76+i*3))
        for _,d in model:GetDescendants() do if d:IsA("BasePart") then d.CanCollide=false d.CanTouch=false d.Anchored=true end end
        model.Parent=props
    end
end
-- Sparse rocks around the camp and perimeter.
local rng = Random.new(1515)
for i=1,25 do
    local a = rng:NextNumber(0,math.pi*2)
    local radius = rng:NextNumber(105,140)
    local x,z=math.cos(a)*radius,math.sin(a)*radius
    local p=part("DesertRock_"..i,Vector3.new(rng:NextNumber(2,6),rng:NextNumber(1.5,4),rng:NextNumber(2,5)),
        CFrame.new(x,4,z)*CFrame.Angles(rng:NextNumber(-0.2,0.2),a,rng:NextNumber(-0.2,0.2)),
        sand,Enum.Material.Sandstone,environment)
    p.Shape=Enum.PartType.Ball
end
local spawn = Instance.new("SpawnLocation")
spawn.Name="DunesSpawn"
spawn.Size=Vector3.new(6,0.2,6)
spawn.CFrame=CFrame.new(0,4.15,-3)*CFrame.Angles(0,math.pi,0)
spawn.Anchored=true
spawn.Transparency=1
spawn.CanCollide=false
spawn.Neutral=true
spawn.Duration=0
spawn.Parent=world
Lighting.ClockTime=15
Lighting.Brightness=2.3
Lighting.Ambient=Color3.fromRGB(112,96,77)
Lighting.OutdoorAmbient=Color3.fromRGB(145,134,113)
Lighting.ExposureCompensation=0
Lighting.GlobalShadows=true
local atmosphere=Instance.new("Atmosphere")
atmosphere.Name="DuneBaronAtmosphere"
atmosphere.Density=0.2
atmosphere.Offset=0.1
atmosphere.Color=Color3.fromRGB(244,218,177)
atmosphere.Decay=Color3.fromRGB(126,158,184)
atmosphere.Glare=0.05
atmosphere.Haze=1.1
atmosphere.Parent=Lighting
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(-75,48,118),Vector3.new(18,6,8))
world:SetAttribute("BuildComplete",true)
return {world=world:GetFullName(),props=#props:GetChildren(),backup=backup:GetFullName(),environmentOnly=true}
