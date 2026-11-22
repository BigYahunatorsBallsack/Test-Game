-- Builds the sand merchant stall in Studio Edit or exports its template with Lune.
local offline = game == nil
local roblox = if offline then require("@lune/roblox") else nil
local fs = if offline then require("@lune/fs") else nil
local Instance = if offline then roblox.Instance else Instance
local CFrame = if offline then roblox.CFrame else CFrame
local Vector3 = if offline then roblox.Vector3 else Vector3
local Color3 = if offline then roblox.Color3 else Color3
local Enum = if offline then roblox.Enum else Enum
local C, V, rgb = CFrame.new, Vector3.new, Color3.fromRGB
local M = Enum.Material

local dryWood = rgb(126,77,48)
local endGrain = rgb(158,100,60)
local frameWood = rgb(91,58,42)
local teal = rgb(29,104,107)
local darkTeal = rgb(34,71,71)
local lightTeal = rgb(45,129,130)
local canvas = rgb(232,208,157)
local hem = rgb(173,103,62)
local sand = rgb(219,178,105)
local brass = rgb(202,153,68)
local deepBrass = rgb(135,94,43)
local darkIron = rgb(73,77,74)

local model = Instance.new("Model")
model.Name = "Merchant"
model:SetAttribute("AssetRole","SandMerchantStall")
model:SetAttribute("ArtRevision",1)
model:SetAttribute("FrontAxis","+Z")

local function group(name)
    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = model
    return folder
end

local function block(parent,name,cf,size,color,material,shape)
    local part = Instance.new("Part")
    part.Name = name
    part.CFrame, part.Size, part.Color, part.Material = cf,size,color,material
    part.Anchored = true
    part.CanCollide, part.CanTouch, part.CanQuery = false,false,false
    part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    if shape then part.Shape = shape end
    part.Parent = parent
    return part
end

local function beam(parent,name,from,to,width,height,color,material)
    return block(parent,name,CFrame.lookAt((from+to)/2,to),V(width,height,(to-from).Magnitude),color,material)
end

local function disc(parent,name,at,diameter,depth,color,material,face)
    local tilt = if face then CFrame.Angles(0,math.pi/2,0) else CFrame.Angles(0,0,math.pi/2)
    return block(parent,name,C(at)*tilt,V(depth,diameter,diameter),color,material,Enum.PartType.Cylinder)
end

local stand = group("Stand")
local point = block(stand,"FloorPivot",C(),V(.05,.05,.05),frameWood,M.SmoothPlastic)
point.Transparency, point.CastShadow = 1,false
model.PrimaryPart = point

local counterZ = 2
block(stand,"Counter plinth",C(0,.16,counterZ),V(8.83,.31,2.91),frameWood,M.WoodPlanks)
block(stand,"Counter core",C(0,1.71,counterZ),V(8.68,2.89,2.82),dryWood,M.WoodPlanks)
block(stand,"Counter fascia",C(0,3.18,counterZ),V(9.03,.42,3.02),darkTeal,M.WoodPlanks)
block(stand,"Counter top",C(0,3.46,counterZ),V(9.16,.23,3.22),endGrain,M.WoodPlanks)
block(stand,"Teal frontage",C(0,1.68,3.441),V(7.74,2.54,.12),darkTeal,M.WoodPlanks)
for i=1,9 do
    local color = teal:Lerp(darkTeal,((i*3)%7)*.074)
    block(stand,"Painted front board",C((i-5)*.806,1.68,3.51),V(.779,2.24,.10),color,M.WoodPlanks)
end
for _,x in {-4.08,4.08} do
    block(stand,"Counter end upright",C(x,1.62,3.47),V(.48,2.71,.21),endGrain,M.Wood)
    for _,y in {.62,2.64} do
        disc(stand,"Counter rivet",V(x,y,3.59),.18,.045,deepBrass,M.Metal,true)
    end
end
for _,y in {.57,2.80} do
    block(stand,"Front edging",C(0,y,3.57),V(7.72,.125,.074),brass,M.Wood)
end
local dunes = {
    V(-1.49,1.38,3.58), V(-.58,2.01,3.58),
    V(.24,1.52,3.58), V(.77,1.86,3.58), V(1.53,1.38,3.58),
}
for i=1,#dunes-1 do
    beam(stand,"Dune inlay",dunes[i],dunes[i+1],.142,.109,brass,M.Wood)
end

local roof = group("Awning")
local profile = {{-4.42,8.03},{-2.28,9.03},{-.52,9.52},{1.13,9.19},{2.86,8.49},{4.39,7.96}}
local stripes = {teal,canvas,teal,canvas,canvas,teal,canvas,teal}
local stripeWidth = 1.405
for i,color in stripes do
    local x = (i-4.5)*stripeWidth
    for section=1,#profile-1 do
        local a,b = profile[section],profile[section+1]
        local dy,dz = b[2]-a[2],b[1]-a[1]
        local center = C(x,(a[2]+b[2])*.5,(a[1]+b[1])*.5)
        block(roof,"Stitched canvas panel",center*CFrame.Angles(-math.atan2(dy,dz),0,0),
            V(stripeWidth+.009,.127,math.sqrt(dy*dy+dz*dz)+.034),color,M.Fabric)
    end
    local depth = if i==1 or i==8 then .52 else .66
    block(roof,"Front valance",C(x,7.96-depth*.5,4.40),V(stripeWidth-.016,depth+.045,.104),color,M.Fabric)
    block(roof,"Valance edging",C(x,7.96-depth,4.405),V(stripeWidth-.012,.105,.128),hem,M.Fabric)
end
for _, x in {-5.57,5.57} do
    for section=1,#profile-1 do
        local a,b = profile[section],profile[section+1]
        beam(roof,"Bound canvas edge",V(x,a[2]+.014,a[1]),V(x,b[2]+.014,b[1]),.16,.124,hem,M.Fabric)
    end
end
for _,z in {-3.44,3.03} do
    local height = if z>0 then 8.28 else 8.46
    local direction = if z>0 then -1 else 1
    block(roof,"Cross beam",C(0,height-.025,z),V(10.21,.27,.32),frameWood,M.Wood)
    for _,x in {-4.76,4.76} do
        block(roof,"Awning support",C(x,height*.5,z),V(.38,height,.41),dryWood,M.Wood)
        block(roof,"Support foot",C(x,.25,z),V(.55,.49,.58),frameWood,M.Wood)
        for _,y in {.54,height-.46} do
            block(roof,"Support binding",C(x,y,z),V(.418,.162,.453),darkIron,M.Metal)
        end
        beam(roof,"Knee brace",V(x,6.99,z),V(x,height-.16,z+.96*direction),.26,.27,endGrain,M.Wood)
    end
end

local sign = group("CoinSign")
for _,x in {-3.28,-1.80} do
    beam(sign,"Sign hanger",V(x,8.06,4.06),V(x,7.13,4.34),.08,.085,deepBrass,M.Metal)
end
block(sign,"Sign backing",C(-2.54,6.68,4.36),V(2.39,1.19,.187),frameWood,M.Wood)
block(sign,"Painted sign face",C(-2.54,6.68,4.47),V(2.20,1.01,.054),teal,M.Wood)
disc(sign,"Coin rim",V(-2.54,6.68,4.54),.878,.094,brass,M.Metal,true)
disc(sign,"Coin inset",V(-2.54,6.68,4.604),.653,.045,deepBrass,M.Metal,true)
block(sign,"Coin stamp",C(-2.54,6.68,4.641)*CFrame.Angles(0,0,math.pi/4),V(.266,.266,.049),brass,M.Metal)

local measure = group("Scales")
local scaleX, scaleZ, surface = 1.60,2.39,3.575
disc(measure,"Scale foot",V(scaleX,surface+.105,scaleZ),.81,.21,deepBrass,M.Metal)
disc(measure,"Scale base ring",V(scaleX,surface+.235,scaleZ),.61,.102,brass,M.Metal)
block(measure,"Balance post",C(scaleX,4.50,scaleZ),V(.184,1.74,.184),deepBrass,M.Metal)
local cross = C(scaleX,5.28,scaleZ)*CFrame.Angles(0,0,math.rad(-8))
block(measure,"Balance beam",cross,V(2.97,.132,.15),brass,M.Metal)
disc(measure,"Balance pin",V(scaleX,5.28,scaleZ+.111),.30,.14,deepBrass,M.Metal,true)
block(measure,"Balance finial",C(scaleX,5.65,scaleZ)*CFrame.Angles(0,0,math.pi/4),V(.227,.227,.189),brass,M.Metal)
for _, side in {-1,1} do
    local top = (cross*C(1.35*side,0,0)).Position
    local base = top-V(0,1.05,0)
    disc(measure,"Weighing pan",base,1.05,.12,deepBrass,M.Metal)
    disc(measure,"Weighing pan rim",base+V(0,.080,0),1.12,.089,brass,M.Metal)
    for angle=0,2 do
        local theta = (angle+.5)*math.pi*2/3
        local foot = base+V(math.cos(theta)*.46,.12,math.sin(theta)*.46)
        beam(measure,"Pan chain",foot,top,.035,.035,deepBrass,M.Metal)
    end
    if side == -1 then
        disc(measure,"Sample sand",base+V(0,.14,0),.79,.12,sand,M.Sand)
    else
        disc(measure,"Iron weight",base+V(0,.212,0),.42,.23,darkIron,M.Metal)
        disc(measure,"Weight knob",base+V(0,.36,0),.174,.104,deepBrass,M.Metal)
    end
end
local trayHeight = .094
block(measure,"Coin tray",C(-2.17,surface+trayHeight*.5,2.63),V(1.93,trayHeight,.89),frameWood,M.Wood)
for groupIndex, count in {4,3,2} do
    for coin=1,count do
        local x = -2.17+(groupIndex-2)*.52
        local z = 2.62-(groupIndex-2)*.16
        disc(measure,"Coin stack",V(x+.025*(coin%2),surface+trayHeight+(coin-.5)*.074,z),.434,.071,
            if coin%2==0 then brass else rgb(224,174,78),M.Metal)
    end
end

local supplies = group("Supplies")
local function sack(name,at,scale,angle)
    local color = rgb(186,153,104)
    local cf = C(at)*CFrame.Angles(0,angle,0)
    local body=block(supplies,name,cf*C(0,scale*.402,0),V(scale*.91,scale*.81,scale*.74),color,M.Fabric)
    local rounded=Instance.new("SpecialMesh")
    rounded.MeshType = Enum.MeshType.Sphere
    rounded.Parent = body
    block(supplies,"Folded sack opening",cf*C(0,scale*.817,0),V(scale*.25,scale*.18,scale*.22),color,M.Fabric)
    block(supplies,"Sack tie",cf*C(0,scale*.807,0),V(scale*.28,.043,scale*.25),frameWood,M.Fabric)
end
for _,x in {-3.98,3.98} do
    block(supplies,"Shelf upright",C(x,2.51,-3.23),V(.22,4.91,.24),frameWood,M.Wood)
end
for _,y in {1.20,3.14,4.90} do
    block(supplies,"Stock shelf",C(0,y,-3.14),V(8.18,.19,.92),dryWood,M.WoodPlanks)
    block(supplies,"Shelf front",C(0,y,-2.66),V(8.23,.23,.099),endGrain,M.Wood)
end
for _,item in {{-3.04,1.30,.91,.28},{-2.26,1.30,.72,-.22},{2.58,3.24,.90,-.2},{3.33,3.24,.78,.67}} do
    sack("Sample sack",V(item[1],item[2],-3.14),item[3],item[4])
end
sack("Unsorted sand",V(5.66,0,-.98),1.82,.60)
sack("Sorted sand",V(6.72,0,-1.35),1.34,-.52)
for i=1,3 do
    local at = V(-1.65+(i-1)*.72,3.50,-3.06)
    local clay = if i==2 then teal else rgb(169,91,58)
    disc(supplies,"Sample jar base",at,.60,.51,clay,M.SmoothPlastic)
    disc(supplies,"Sample jar rim",at+V(0,.225,0),.646,.12,clay,M.SmoothPlastic)
    disc(supplies,"Sample jar contents",at+V(0,.265,0),.482,.046,sand,M.Sand)
end
for i=1,2 do
    block(supplies,"Folded fabric",C(1.62,5.03+(i-1)*.15,-3.14)*CFrame.Angles(0,.035*i,0),
        V(1.80-i*.2,.143,.63),if i==2 then canvas else lightTeal,M.Fabric)
end

if offline then
    local path = "assets/models/merchant_v1/DuneBaron_Merchant.rbxm"
    local bytes = roblox.serializeModel({model})
    local copy = roblox.deserializeModel(bytes)[1]
    assert(copy.PrimaryPart.Name=="FloorPivot" and copy.PrimaryPart.CFrame==C())
    assert(#copy:GetChildren()==5 and copy.Scales:FindFirstChild("Balance post"))
    for _, item in copy:GetDescendants() do
        if item:IsA("BasePart") then assert(item.Anchored and not item.CanCollide) end
    end
    fs.writeFile(path,bytes)
    assert(fs.readFile(path)==bytes)
    print(path,"verified")
else
    local run = game:GetService("RunService")
    assert(run:IsStudio() and not run:IsRunning(),"Use Studio Edit")
    assert(game.PlaceId==135831532782380,"Unexpected place")
    local world = workspace.DuneBaronWorld
    local deck = world.Environment.MerchantDeck
    local marker = world.IntegrationMarkers.SellStand
    local collision = world.Environment.MerchantCounterCollision
    assert(marker:HasTag("SellStand") and collision.CanCollide)
    local old = world.Props:FindFirstChild("Merchant")
    assert(old and (old:FindFirstChild("canopy") or old:GetAttribute("AssetRole")==model:GetAttribute("AssetRole")),
        "Unexpected existing stall")
    local storage = game:GetService("ServerStorage")
    local backup = storage:FindFirstChild("DuneBaronMerchantBackup")
    if not backup then
        backup = Instance.new("Folder")
        backup.Name = "DuneBaronMerchantBackup"
        backup.Parent = storage
    end
    model:PivotTo(deck.CFrame*C(0,deck.Size.Y*.5,0))
    if backup:FindFirstChild("Merchant") then
        assert(old:GetAttribute("AssetRole")==model:GetAttribute("AssetRole"),"Merchant backup already exists")
        old:Destroy()
    else
        old.Parent = backup
    end
    model.Parent = world.Props
    return {path=model:GetFullName(),parts=#model:GetDescendants(),pivot=tostring(model:GetPivot().Position)}
end
