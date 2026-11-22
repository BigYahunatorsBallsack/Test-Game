--!strict
-- Studio Edit only. Add landmarks, site dressing, and buried specimen models.
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Use Studio Edit mode")
assert(game.PlaceId==135831532782380, "Unexpected place")
local world=workspace:WaitForChild("DuneBaronWorld")
assert(world:GetAttribute("CanyonTerrainRevision")==1, "Build Canyon terrain first")
local storage=game:GetService("ServerStorage")
local prior=world:FindFirstChild("CanyonArtV1")
local revisionArchive="DuneBaronCanyonArtBeforeDressing"
assert(not prior or prior:GetAttribute("Owner")=="DuneBaronCanyonArt", "Canyon art name occupied")
assert(not prior or not storage:FindFirstChild(revisionArchive), "Prior canyon art archive already exists")
local terrain=workspace.Terrain
local finds=storage.DuneBaronAssetLibrary.Finds.canyon
local V,C,rgb=Vector3.new,CFrame.new,Color3.fromRGB
local Y=Vector3.yAxis
local r=Random.new(20819)
local mat=Enum.Material
local sand, dark, light=rgb(169,116,85),rgb(127,85,66),rgb(203,155,110)
local sandstone, wood=mat.Sandstone,rgb(126,88,56)
local teal,cloth=rgb(59,119,114),rgb(225,196,144)
local rockPalette={sand,dark,light,rgb(184,126,94),rgb(139,93,72)}

local function folder(name: string,parent: Instance?): Folder
    local item=Instance.new("Folder")
    item.Name,item.Parent=name,parent
    return item
end

local art=folder("CanyonArtV1")
art:SetAttribute("Owner","DuneBaronCanyonArt")
art:SetAttribute("ZoneId","canyon")
local structures=folder("Landmarks",art)
local detail=folder("NaturalDetails",art)
local deposits=folder("BuriedFinds",art)
local waypoints=folder("TrailMarkers",art)

local ray=RaycastParams.new()
ray.FilterType=Enum.RaycastFilterType.Include
ray.FilterDescendantsInstances={terrain}
ray.IgnoreWater=true

local function ground(x: number,z: number): RaycastResult
    local hit=workspace:Raycast(V(x,188,z),V(0,-220,0),ray)
    return assert(hit,"Canyon ground missing")
end

local function block(parent: Instance,name: string,cf: CFrame,size: Vector3,color: Color3,
        material: Enum.Material,solid: boolean?,wedge: boolean?): BasePart
    local p=if wedge then Instance.new("WedgePart") else Instance.new("Part")
    p.Name,p.Size,p.CFrame,p.Color,p.Material=name,size,cf,color,material
    p.Anchored=true
    p.CanCollide,p.CanQuery,p.CanTouch=solid==true,solid==true,false
    p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    p.Parent=parent
    return p
end

local function cylinder(parent: Instance,name: string,a: Vector3,b: Vector3,diameter: number,color: Color3,material: Enum.Material)
    local along=(b-a).Unit
    local ref=if math.abs(along.Y)<.9 then Y else Vector3.zAxis
    local normal=(ref-ref:Dot(along)*along).Unit
    local p=block(parent,name,CFrame.fromMatrix((a+b)/2,along,normal),
        V((b-a).Magnitude,diameter,diameter),color,material) :: Part
    p.Shape=Enum.PartType.Cylinder
    return p
end

local function base(x: number,z: number,dx: number,dz: number): CFrame
    local p=ground(x,z).Position
    return CFrame.lookAt(p,p+V(dx,0,dz))
end

-- A broad crossing. The stonework leaves a straight passage for machines.
do
    local gate=folder("Schichtentor",structures)
    local at=base(555,607,1,.53)
    for _,side in {-1,1} do
        local x=side*19.2
        for row=0,3 do
            local width=7.4-row*.44
            block(gate,"Buttress Course",at*C(x+side*(1-row*.2),row*3.75+1.3,0),
                V(width,4.0,7.2-row*.53),rockPalette[(row+1)%#rockPalette+1],sandstone,true)
        end
        block(gate,"Teal Stone Band",at*C(x,10,-2.79),V(5.9,1,.22),teal,mat.Slate)
        block(gate,"Shoulder Cap",at*C(x,15.95,0),V(7.1,1.6,6.0),light,sandstone,true)
    end
    for k=0,10 do
        local a=(k+.5)*math.pi/11
        local radius=19.4
        local guide=at*C(math.cos(a)*radius,14.4+math.sin(a)*radius,0)*CFrame.Angles(0,0,a+math.pi/2)
        local size=V(5.7+(if k==5 then .3 else 0),4.65,5.0)
        block(gate,if k==5 then "Keystone" else "Arch Block",guide,size,
            if k==5 then light else rockPalette[k%#rockPalette+1],sandstone,true)
        if k%2==0 then
            block(gate,"Weathered Face",guide*C(0,-.45,-2.55)*CFrame.Angles(0,0,.06),
                V(4.7,.57,.25),sand:Lerp(light,.41),sandstone)
        end
    end
    gate:SetAttribute("PassageWidth",29.5)
end

-- Limestone fossils weathering from the edge of a side recess.
do
    local bed=folder("Fossilienwand",structures)
    local at=base(664,749,-.12,-1)
    for i=0,4 do
        local x=(i-2)*5.25
        local h=11.5+2.8*math.sin(i*.93)
        block(bed,"Exposed Stratum",at*C(x,h*.5-.55,.5)*CFrame.Angles(0,(i-2)*.051,0),
            V(5.9,h,4.8),rockPalette[i%#rockPalette+1],sandstone,true)
        block(bed,"Calcareous Seam",at*C(x,5.1+i*.14,-2.02)*CFrame.Angles(0,0,.047),
            V(5.7,.42,.43),rgb(215,181,137),sandstone)
    end
    local face=at*C(.60,7.0,-2.72)
    local points={}
    for k=0,24 do
        local a=k*.32
        local shell=.22+k*.145
        points[k+1]=face:PointToWorldSpace(V(math.cos(a)*shell,math.sin(a)*shell,0))
    end
    for k=1,#points-1 do
        cylinder(bed,"Ammonite Chamber",points[k],points[k+1],.41+(.65*k/#points),
            rgb(239,214,166):Lerp(rgb(181,146,104),k/49),sandstone)
        if k>6 and k%2==0 then
            local v=face:PointToObjectSpace(points[k])
            local rib=V(v.X,v.Y,0).Unit
            cylinder(bed,"Ammonite Rib",points[k],points[k]+face:VectorToWorldSpace(rib*.53),.22,rgb(228,196,153),sandstone)
        end
    end
    local plate=at*C(-7.0,3.5,-2.54)
    block(bed,"Trilobite Impression",plate*C(0,0,-.16),V(2.4,4.4,.44),rgb(152,110,82),sandstone)
    for row=1,8 do
        local width=.61+.34*math.sin(row*math.pi/9)
        local y=(row-4.1)*.39
        block(bed,"Trilobite Segment",plate*C(0,y,-.43),V(width*2,.20,.16),rgb(203,161,113),sandstone)
    end
    for i=1,5 do
        local x=(i-3)*4.1
        local p=at:PointToWorldSpace(V(x,0,-7-r:NextNumber(0,3)))
        local g=ground(p.X,p.Z).Position
        block(bed,"Broken Excavation Border",C(g+V(0,.17,0))*CFrame.Angles(0,r:NextNumber(-.35,.75),-.12),
            V(r:NextNumber(2.4,4.0),.9,1.7),sand:Lerp(light,.30),sandstone)
    end
end

local function canopy(parent: Instance,at: CFrame,width: number,length: number)
    local front=7.75
    for _,x in {-.46,.46} do
        for _,z in {-.45,.45} do
            local bottom=at:PointToWorldSpace(V(x*width,0,z*length))
            local top=at:PointToWorldSpace(V(x*width,front-1.48*(z+.45),z*length))
            local foot=ground(bottom.X,bottom.Z).Position
            cylinder(parent,"Tent Timber",foot-Y*.28,top,.53,wood,mat.Wood)
            cylinder(parent,"Rope Tie",top-Y*.70,top-Y*.25,.68,rgb(170,129,79),mat.Fabric)
        end
    end
    local fall=math.atan(1.48/length)
    for i=0,5 do
        local color=if i%3==0 then teal else cloth:Lerp(rgb(185,140,92),i*.035)
        block(parent,"Sloped Canvas",at*C((i-2.5)*width/6,front-.6,0)*CFrame.Angles(fall,0,0),
            V(width/6+.10,.15,length),color,mat.Fabric)
        block(parent,"Hanging Canvas Edge",at*C((i-2.5)*width/6,front-.40,-length/2),
            V(width/6+.03,.74,.13),color,mat.Fabric)
    end
    for _,z in {-.45,.45} do
        local h=front-1.48*(z+.45)
        cylinder(parent,"Tent Cross Beam",at:PointToWorldSpace(V(-.50*width,h,z*length)),
            at:PointToWorldSpace(V(.50*width,h,z*length)),.36,wood,mat.Wood)
    end
end

-- Survey tools and two shelters occupy the widened side of the trail.
do
    local camp=folder("Vermessungslager",structures)
    local at=base(763,635,.32,1)
    canopy(camp,at,15,12.5)
    canopy(camp,base(781,643,-.15,1),10,9)
    local bench=at*C(0,2.7,-1.75)
    block(camp,"Survey Bench",bench,V(8.2,.46,3.5),wood,mat.WoodPlanks,true)
    for _,side in {-1,1} do
        block(camp,"Bench Stone Plinth",bench*C(side*2.82,-1.72,0),V(1.7,2.95,2.45),
            sand:Lerp(dark,.35),sandstone,true)
    end
    block(camp,"Survey Plan",bench*C(-.60,.25,-.15)*CFrame.Angles(0,.15,0),V(3.62,.072,1.95),
        rgb(234,208,165),mat.Fabric)
    for i=0,4 do
        local x=-2+i*.65
        block(camp,"Charcoal Grid",bench*C(x,.30,-.15)*CFrame.Angles(0,.15,0),
            V(.026,.015,1.53),rgb(155,123,87),mat.Fabric)
    end
    cylinder(camp,"Straightedge",bench:PointToWorldSpace(V(.3,.34,.55)),bench:PointToWorldSpace(V(2.5,.34,.83)),
        .13,rgb(117,87,54),mat.Wood)
    for i=1,5 do
        local p=at:PointToWorldSpace(V(-5.7+i*1.4,0,4.3+math.sin(i)*1.2))
        local g=ground(p.X,p.Z).Position
        local h=r:NextNumber(1.2,2.25)
        cylinder(camp,"Specimen Barrel",g-Y*.15,g+Y*h,1.75,wood,mat.WoodPlanks)
        for _,frac in {.16,.87} do
            cylinder(camp,"Barrel Hoop",g+Y*(h*frac-.10),g+Y*(h*frac+.10),1.85,rgb(68,71,67),mat.Metal)
        end
    end
    local supply=base(783,644,-.15,1)
    for j=1,3 do
        local shelf=supply*C((j-2)*2.6,.98,-.75+j*.34)
        block(camp,"Sample Crate",shelf,V(2.45,1.9,2.3),wood:Lerp(dark,.15),mat.WoodPlanks)
        for _,x in {-1,1} do
            block(camp,"Crate Frame",shelf*C(x*.91,.06,-1.18),V(.22,1.92,.12),
                rgb(154,114,73),mat.Wood)
        end
        block(camp,"Crate Lid",shelf*C(0,1.0,0),V(2.53,.17,2.38),rgb(149,111,70),mat.WoodPlanks)
    end
    for j=1,2 do
        cylinder(camp,"Rolled Canvas",supply:PointToWorldSpace(V(-.3,.38,2.0+j*.70)),
            supply:PointToWorldSpace(V(2.3,.38,2.15+j*.70)),.62,
            if j==1 then cloth else teal,mat.Fabric)
    end
    local workbench=supply*C(-3.5,.66,2.2)*CFrame.Angles(0,.16,0)
    block(camp,"Stone Cutting Bench",workbench,V(4.3,1.42,2.45),sand:Lerp(light,.40),sandstone)
    block(camp,"Half-Cut Sample",workbench*C(-.59,.92,.31)*CFrame.Angles(0,-.64,0),
        V(1.4,.56,.95),rockPalette[3],sandstone,true,true)
end

-- An older passage with a broken rear wall and a partially buried seal.
do
    local ruins=folder("Versunkener Durchgang",structures)
    local at=base(868,753,-.40,-1)
    for _,x in {-14.0,14.0} do
        for i=0,4 do
            local z=(i-2)*4.7
            local top=if x<0 then 2+(i%3) else 3+((i+1)%3)
            for y=0,top do
                local offsetZ=z+(if y%2==0 then .1 else .48)
                local offsetX=x+r:NextNumber(-.35,.35)
                block(ruins,"Buried Wall Block",at*C(offsetX,y*2.45-.52,offsetZ)*CFrame.Angles(0,r:NextNumber(-.065,.065),0),
                    V(5.4,2.52,4.85),sand:Lerp(light,r:NextNumber(.13,.59)),sandstone,true)
            end
        end
    end
    for x=-12,12,4 do
        local stories=if x>1 then 2 else 1
        for y=0,stories do
            block(ruins,"Fractured Rear Course",at*C(x+(.32*(y%2)),y*2.35-.24,11.3+y*.08),
                V(4.12,2.4,4.1),sand:Lerp(dark,r:NextNumber(.02,.33)),sandstone,true)
        end
    end
    for _,side in {-1,1} do
        block(ruins,"Gate Jamb",at*C(side*5.1,4.3,-8.4),V(3.2,10.9,4.3),light,sandstone,true)
        block(ruins,"Carved Accent",at*C(side*5.1,5.6,-10.6),V(1.55,3.2,.25),teal,mat.Slate)
    end
    block(ruins,"Lintel",at*C(0,10.92,-8.4),V(14.0,2.65,5.25),sand:Lerp(light,.58),sandstone,true)
    block(ruins,"Lintel Inlay",at*C(0,10.98,-11.12),V(6.4,.61,.19),teal,mat.Slate)
    local beam=at*C(-17.0,.37,-12.8)*CFrame.Angles(.095,-.57,.04)
    block(ruins,"Fallen Lintel",beam,V(9.7,1.95,3.1),sand:Lerp(light,.46),sandstone,true)
    for _,u in {-2.7,-.92,.92,2.7} do
        block(ruins,"Fragmented Inlay",beam*C(u,.98,0),V(1.36,.12,.62),teal:Lerp(sand,.15),mat.Slate)
    end
    for _,node in {{-8.7,-4.4},{9.8,1.8},{3.3,8.1},{-9.5,7.2},{2.8,4.9},{2.4,-9.2}} do
        local p=at:PointToWorldSpace(V(node[1],0,node[2]))
        local g=ground(p.X,p.Z).Position
        block(ruins,"Sand-Covered Rubble",C(g+Y*.34)*CFrame.Angles(.08,r:NextNumber(-1.4,1.4),-.18),
            V(2.4,.86,1.6),sand,sandstone)
    end
end

local trail={
    {497,574},{530,575},{570,590},{599,621},{627,635},{655,659},{695,663},{730,659},
    {768,652},{805,651},{831,666},{875,690},{908,725},{938,738},{963,770},{992,787},{1018,809},{1040,823},
    {644,711},{652,723},{671,728},{844,724},{847,740},{854,749},
}
for i,mark in trail do
    local hit=ground(mark[1],mark[2])
    if hit.Normal.Y>.76 then
        local mid=hit.Position
        local turn=r:NextNumber(-.75,.88)
        local h=if i%5==0 then 3.45 else r:NextNumber(1.4,2.15)
        local cf=C(mid+Y*(h*.36))*CFrame.Angles(.08,turn,-.085)
        block(waypoints,"Cairn Foot",cf*C(0,-h*.37,0),
            V(2.75,.72,1.85),sand:Lerp(light,.20),sandstone)
        block(waypoints,"Trail Cairn",cf,V(2.0,h,1.34),sand:Lerp(light,.43),sandstone)
        block(waypoints,"Chipped Cairn Cap",cf*C(.15,h*.47,.08)*CFrame.Angles(0,.28,.17),
            V(1.8,.54,1.12),sand:Lerp(light,.66),sandstone,false,true)
        if i%3==0 then
            block(waypoints,"Trail Inlay",cf*C(0,h*.19,-.74),V(1.25,.41,.09),teal,mat.Slate)
        end
    end
end

-- Rockfall clusters rest on the wall skirts, leaving the pale channel open.
local ledges={
    {575,570},{603,590},{633,610},{663,612},{695,631},{738,620},{781,601},{814,619},{845,622},
    {884,644},{914,671},{955,697},{989,749},{548,640},{573,663},{610,707},{642,757},{685,774},
    {720,746},{759,735},{797,735},{833,756},{865,789},{902,798},{926,816},{957,848},{983,881},{1019,897},
}
local middle={{548,600},{610,646},{680,682},{735,677},{790,669},{845,688},{904,727},{958,778},{1019,827}}
local function channelZ(x: number): number
    for i=2,#middle do
        local a,b=middle[i-1],middle[i]
        if x<=b[1] then
            local fraction=math.clamp((x-a[1])/(b[1]-a[1]),0,1)
            return a[2]+(b[2]-a[2])*fraction
        end
    end
    return middle[#middle][2]
end
for i,entry in ledges do
    for j=1,3 do
        local x=entry[1]+r:NextNumber(-6.5,6.5)
        local z=entry[2]+r:NextNumber(-6.5,6.5)
        local hit=ground(x,z)
        for _=1,6 do
            if hit.Normal.Y>.83 then break end
            z+=(channelZ(x)-z)*.16
            hit=ground(x,z)
        end
        local color=rockPalette[(i+j)%#rockPalette+1]
        local h=r:NextNumber(.65,2.8)
        local w=r:NextNumber(1.6,4.8)
        local anchor=C(hit.Position-Y*h*.18)*CFrame.Angles(r:NextNumber(-.13,.18),r:NextNumber(0,6.28),r:NextNumber(-.15,.17))
        if hit.Normal.Y>.83 then
            block(detail,"Angular Rockfall",anchor,V(w,h,r:NextNumber(1.45,4.0)),color,sandstone,false,true)
        end
        if j==1 then
            local p=anchor:PointToWorldSpace(V(w*.57,0,-.8))
            local foot=ground(p.X,p.Z)
            if foot.Normal.Y>.83 then
                block(detail,"Shale Fragment",C(foot.Position-Y*.09)*anchor.Rotation,V(w*.46,h*.48,1.4),
                    color:Lerp(dark,.25),sandstone,false,true)
            end
        end
    end
end

-- Fine debris and mineral clusters follow the shoulders rather than the lane.
for i=1,72 do
    local x=556+r:NextNumber()*490
    local side=if i%2==0 then -1 else 1
    local z=channelZ(x)+side*r:NextNumber(25,57)
    local hit=ground(x,z)
    if hit.Normal.Y>.88 then
        local p=hit.Position
        local c=rockPalette[r:NextInteger(1,#rockPalette)]:Lerp(rgb(220,207,185),.29)
        local wide=r:NextNumber(.28,1.59)
        local count=if i%9==0 then 5 else 2
        for j=1,count do
            local phi=j*2.399963
            local off=p+V(math.cos(phi)*wide,0,math.sin(phi)*wide)
            local tip=ground(off.X,off.Z)
            if tip.Normal.Y>.83 then
                block(detail,"Talus Flake",C(tip.Position-Y*.035)*CFrame.Angles(.1,phi,-.07),
                    V(wide,.27*wide,.67*wide),c,sandstone,false,true)
            end
        end
    end
end

local function bury(id: string,x: number,z: number,yaw: number,siteName: string)
    local hit=ground(x,z)
    local source=assert(finds:FindFirstChild(id))
    assert(source:IsA("Model") and source:GetAttribute("FindId")==id)
    local model=source:Clone()
    model.Name=siteName
    model:PivotTo(C(x,0,z)*CFrame.Angles(0,yaw,0))
    local box,size=model:GetBoundingBox()
    local burialTop=hit.Position.Y-1.65
    model:PivotTo(model:GetPivot()+V(0,burialTop-(box.Position.Y+size.Y/2),0))
    model:SetAttribute("ArtBurial",true)
    model:SetAttribute("SurfaceY",hit.Position.Y)
    model:SetAttribute("RevealDepthStuds",3.6)
    for _,object in model:GetDescendants() do
        if object:IsA("LuaSourceContainer") then object:Destroy()
        elseif object:IsA("BasePart") then
            object.Anchored,object.CanCollide,object.CanTouch=true,false,false
        end
    end
    model.Parent=deposits
    for i=1,4 do
        local angle=i*2.399963
        local g=ground(x+math.cos(angle)*(1.8+i*.28),z+math.sin(angle)*(1.8+i*.28)).Position
        block(detail,"Specimen Surface Flake",C(g+Y*.02)*CFrame.Angles(.2,angle,.2),
            V(.47+i*.11,.25,.48),light:Lerp(dark,i*.125),sandstone,false,true)
    end
end

bury("canyon_04",673,731,1.1,"Verschütteter Trilobit")
bury("canyon_15",755,651,-.17,"Verschüttete Grubenlampe")
bury("canyon_27",870,758,.59,"Verschüttete Kristallgeode")

if prior then
    prior.Name=revisionArchive
    prior.Parent=storage
end
art.Parent=world
return {path=art:GetFullName(),descendants=#art:GetDescendants(),finds=#deposits:GetChildren()}
