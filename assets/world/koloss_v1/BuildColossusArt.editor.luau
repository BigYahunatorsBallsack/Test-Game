--!strict
-- Studio Edit only. Build the reclining statue, work terraces and excavation camp.
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Use Studio Edit mode")
assert(game.PlaceId==135831532782380,"Unexpected place")
local world=workspace:WaitForChild("DuneBaronWorld")
assert(world:GetAttribute("ColossusTerrainRevision")==1,"Build the dig basin first")
local storage=game:GetService("ServerStorage")
local geometry=game:GetService("GeometryService")
local owner="DuneBaronColossusArt"
local previous=world:FindFirstChild("ColossusArtV1")
local archive="DuneBaronColossusBeforeRimAlignment"
assert(not previous or previous:GetAttribute("Owner")==owner,"Colossus art name occupied")
assert(not previous or not storage:FindFirstChild(archive),"Prior Colossus art archive already exists")
local V,C,rgb=Vector3.new,CFrame.new,Color3.fromRGB
local Y=Vector3.yAxis
local mat=Enum.Material
local random=Random.new(47190)
local stoneGold,ochre,deep=rgb(215,160,97),rgb(191,132,74),rgb(148,100,65)
local sandLight,copper,teal=rgb(231,184,116),rgb(125,94,68),rgb(48,110,113)
local wood,cloth=rgb(128,83,53),rgb(226,199,147)
local anchor=world:GetAttribute("ColossusArtOrigin") :: Vector3
local pose=C(anchor)*CFrame.Angles(0,-math.pi/2,0)

local function folder(name: string,parent: Instance?): Folder
    local f=Instance.new("Folder")
    f.Name,f.Parent=name,parent
    return f
end

local pack=folder("ColossusArtV1")
pack:SetAttribute("Owner",owner)
pack:SetAttribute("EventProp","colossus")
local scene=folder("Grabungsstätte",pack)
local scaleMarkers=folder("Grabungsflächen",pack)
local statue=Instance.new("Model")
statue.Name="Koloss"
statue.WorldPivot=pose
statue.ModelStreamingMode=Enum.ModelStreamingMode.Atomic
statue:SetAttribute("DesignReference","assets/reference/events/ref_colossus_01.png")
statue.Parent=pack
local anatomy={
    head=folder("Kopf und Hals",statue), chest=folder("Brust und Rumpf",statue),
    left=folder("Südarm und Hand",statue), right=folder("Verschütteter Nordarm",statue),
    legs=folder("Verschüttete Beine",statue),
}

local terrainOnly=RaycastParams.new()
terrainOnly.FilterType=Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances={workspace.Terrain}
terrainOnly.IgnoreWater=true
local function ground(x: number,z: number): RaycastResult
    return assert(workspace:Raycast(V(x,160,z),V(0,-260,0),terrainOnly),"Ground missing around dig site")
end

local function panel(parent: Instance?,name: string,cf: CFrame,size: Vector3,color: Color3,
    material: Enum.Material,solid: boolean?): Part
    local p=Instance.new("Part")
    p.Name,p.Size,p.CFrame,p.Color,p.Material=name,size,cf,color,material
    p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery=true,solid==true,false,solid==true
    p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    p.Parent=parent
    return p
end

local function barrel(parent: Instance,name: string,cf: CFrame,d: number,thick: number,color: Color3,
    material: Enum.Material,solid: boolean?): Part
    local p=panel(parent,name,cf*CFrame.Angles(0,0,math.pi/2),V(thick,d,d),color,material,solid)
    p.Shape=Enum.PartType.Cylinder
    return p
end

local function rod(parent: Instance,name: string,a: Vector3,b: Vector3,width: number,color: Color3,
    material: Enum.Material,solid: boolean?)
    local axis=b-a
    local up=if math.abs(axis.Unit.Y)>.94 then Vector3.zAxis else Y
    panel(parent,name,CFrame.lookAt((a+b)/2,b,up),V(width,width,axis.Magnitude),color,material,solid)
end

local function singleShape(parts: {BasePart}): BasePart
    assert(#parts==1,"Expected a single piece of connected stone")
    return parts[1]
end

-- Build one chamfered block to reuse on the statue and excavation walls.
local chamfer: BasePart=panel(nil,"Stone blank",C(),V(10,10,10),stoneGold,mat.Sandstone)
for _,rot in {CFrame.Angles(0,math.pi/4,0),CFrame.Angles(0,0,math.pi/4),CFrame.Angles(math.pi/4,0,0)} do
    local tool=panel(nil,"Chipping plane",rot,V(12.83,12.83,12.83),stoneGold,mat.Sandstone)
    local shape=singleShape(geometry:IntersectAsync(chamfer,{tool},{SplitApart=false}))
    chamfer:Destroy()
    tool:Destroy()
    chamfer=shape
end

local function finishStone(p: BasePart,parent: Instance?,name: string,color: Color3,solid: boolean?): BasePart
    p.Name,p.Color,p.Material=name,color,mat.Sandstone
    p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery=true,solid==true,false,solid==true
    if p:IsA("PartOperation") then p.UsePartColor=true end
    p.Parent=parent
    return p
end

local function stone(parent: Instance?,name: string,where: CFrame,size: Vector3,color: Color3,solid: boolean?): BasePart
    local p=chamfer:Clone()
    p.Size,p.CFrame=size,where
    return finishStone(p,parent,name,color,solid)
end

local function span(a: Vector3,b: Vector3): CFrame
    return CFrame.lookAt((a+b)/2,b)
end

local function member(parent: Instance,name: string,a: Vector3,b: Vector3,w: number,h: number,color: Color3)
    return stone(parent,name,pose*span(a,b),V(w,h,(a-b).Magnitude+.55),color,true)
end

-- Face and nose are fused before cutting the eye sockets and weathered notches.
do
    local cf=pose*C(0,35.35,40.9)*CFrame.Angles(.49,-.06,.083)
    local skull=stone(nil,"Crown blank",C(),V(30.6,24,24.3),stoneGold,true)
    local jaw=stone(nil,"Jaw blank",C(0,-9.75,-.22),V(25.4,13.95,23.75),stoneGold,true)
    local nose=stone(nil,"Nose blank",C(0,-.10,-12.15)*CFrame.Angles(-.13,0,-.04),V(4.55,8.5,5.75),stoneGold,true)
    local head=singleShape(geometry:UnionAsync(skull,{jaw,nose},{SplitApart=false}))
    skull:Destroy()
    jaw:Destroy()
    nose:Destroy()
    local inserts={
        panel(nil,"Left eye cut",C(-7.45,2.62,-12.65)*CFrame.Angles(.03,0,.04),V(9.4,4.01,9.8),deep,mat.Sandstone),
        panel(nil,"Right eye cut",C(7.45,2.62,-12.65)*CFrame.Angles(-.02,0,-.04),V(9.4,4.01,9.8),deep,mat.Sandstone),
        panel(nil,"Mouth cut",C(.12,-8.8,-11.49)*CFrame.Angles(0,0,-.017),V(10.5,1.42,3.6),deep,mat.Sandstone),
        panel(nil,"Crown break",C(-11,11.78,-10.5)*CFrame.Angles(0,-.26,-.59),V(8.2,2.9,9.0),deep,mat.Sandstone),
        panel(nil,"Crown weathering",C(10.38,9.12,-11.23)*CFrame.Angles(0,.28,-.72),V(5.5,.48,3.1),deep,mat.Sandstone),
    }
    local carved=singleShape(geometry:SubtractAsync(head,inserts,{SplitApart=false}))
    for _,p in inserts do p:Destroy() end
    carved.CFrame=cf*carved.CFrame
    finishStone(carved,anatomy.head,"Carved sandstone head",stoneGold,true)
    head:Destroy()
    stone(anatomy.head,"Neck into the shoulder block",pose*C(0,21.8,29.4)*CFrame.Angles(-.45,0,.08),
        V(23.1,16.7,20.4),ochre,true)
end

do
    stone(anatomy.chest,"Continuous upper torso",pose*C(0,16.45,4.2)*CFrame.Angles(-.23,0,.024),
        V(58.3,23.6,54),ochre,true)
    stone(anatomy.chest,"Sloping breastplate",pose*C(0,25.55,5.7)*CFrame.Angles(-.235,0,.015),
        V(56.2,7.0,37.6),stoneGold,true)
    stone(anatomy.chest,"Ribs under the dunes",pose*C(0,10.0,-26.3)*CFrame.Angles(-.16,0,-.037),
        V(42.9,15.3,30.9),ochre,true)
    stone(anatomy.chest,"Lower girdle",pose*C(0,7.4,-47.7)*CFrame.Angles(-.12,.09,0),
        V(40.5,12.1,18.6),deep,true)
    local medallion=pose*C(-.7,29.44,6.2)*CFrame.Angles(-.235,0,.015)
    barrel(anatomy.chest,"Cut sandstone setting",medallion,19.5,1.42,sandLight,mat.Sandstone,true)
    barrel(anatomy.chest,"Oxidised metal rim",medallion*C(0,.70,0),16.75,.60,copper,mat.CorrodedMetal)
    barrel(anatomy.chest,"Dark teal stone inlay",medallion*C(0,1.14,0),14.12,.80,teal,mat.SmoothPlastic)
    for _,side in {-1,1} do
        local stripe=medallion*C(side*15.95,-.21,-1.5)*CFrame.Angles(0,side*.18,0)
        stone(anatomy.chest,"Carved breastplate ridge",stripe,V(11.2,1.07,2.82),sandLight)
    end
end

for _,side in {-1,1} do
    local south=side==1
    local limb=if south then anatomy.left else anatomy.right
    local offset=if south then 0 else -5.1
    local f=if south then -3 else 2
    local shoulder=pose*C(side*33,23.0+offset,20+f)*CFrame.Angles(-.22,side*.27,side*.11)
    stone(limb,"One-piece shoulder block",shoulder,V(27.4,20.7,28.1),stoneGold,true)
    stone(limb,"Shoulder rim",shoulder*C(0,7.95,-1.6),V(25.9,5.97,24.2),sandLight,true)
    member(limb,"Upper arm",V(side*33,20+offset,16+f),V(side*38,13.1+offset,-9+f),19.7,17.35,ochre)
    member(limb,"Elbow",V(side*38,13.9+offset,-6+f),V(side*40,11.9+offset,-17+f),19.9,16.9,stoneGold)
    member(limb,"Forearm stone",V(side*39.25,12.35+offset,-14+f),V(side*36,11.2+offset,-34+f),17.45,14.8,ochre)
    member(limb,"Carved wrist cuff",V(side*36.3,11.9+offset,-31.5+f),V(side*35.5,11.85+offset,-38.6+f),19.2,15.36,stoneGold)
    local wrist=pose*C(side*35.6,15.10+offset,-41.3+f)*CFrame.Angles(-.06,side*.07,side*.036)
    stone(limb,"Carved palm",wrist,V(22.4,9.21,12.4),stoneGold,true)
    for i,entry in {{-7.3,11.6},{-2.42,14.0},{2.6,13.1},{7.43,10.15}} do
        local x=entry[1]
        local length=entry[2]
        local axis=wrist*C(x,.45,-5.20)*CFrame.Angles(.045,x*.013,0)
        stone(limb,"Finger proximal stone",axis*C(0,-.17,-length*.30),V(4.38,7.61,length*.63),sandLight,true)
        stone(limb,"Finger tip buried in the drift",axis*C(0,-1.9,-length*.82)*CFrame.Angles(-.19,0,0),
            V(4.19,6.45,length*.54),stoneGold,true)
    end
    stone(limb,"Sculpted thumb",wrist*C(-side*10.53,-.98,-2.41)*CFrame.Angles(-.17,side*.56,side*.21),
        V(6.6,7.73,11.45),stoneGold,true)
end

for _,side in {-1,1} do
    member(anatomy.legs,"Thigh under the sand",V(side*11.2,5.8,-49),V(side*14,3.2,-75),20.8,12.1,ochre)
    member(anatomy.legs,"Shin under the sand",V(side*14,3,-73),V(side*17,2.3,-100),17.7,11.6,ochre)
    stone(anatomy.legs,"Sandstone sandal",pose*C(side*17.7,3.73,-104.6)*CFrame.Angles(.08,-side*.11,0),
        V(17.25,15.2,17.8),stoneGold,true)
end

local function marker(name: string,center: Vector3,extents: Vector3,body: string)
    local spot=folder(name,scaleMarkers)
    spot:SetAttribute("Center",center)
    spot:SetAttribute("Footprint",extents)
    spot:SetAttribute("Reveals",body)
end
marker("Nordhand",pose:PointToWorldSpace(V(-35.7,0,-46)),V(40,0,40),anatomy.right.Name)
marker("Beine",pose:PointToWorldSpace(V(0,0,-81)),V(58,0,59),anatomy.legs.Name)

local function sampleCamp(name: string,x: number,z: number,yaw: number,big: boolean)
    local site=folder(name,scene)
    local base=C(ground(x,z).Position)*CFrame.Angles(0,yaw,0)
    local w,d=if big then 18 else 12,if big then 10 else 8.3
    for i=1,7 do
        local width=w/7
        panel(site,"Weathered floorboard",base*C((i-4)*width,.29,0),V(width-.03,.64,d+.14*(i%3)),
            wood:Lerp(ochre,.14+.09*(i%3)),mat.WoodPlanks,true)
    end
    for _,side in {-1,1} do
        for _,endZ in {-1,1} do
            local col=base:PointToWorldSpace(V(side*(w*.44),0,endZ*(d*.44)))
            local footing=ground(col.X,col.Z).Position
            local top=col+Y*(5.95-endZ*.68)
            rod(site,"Canopy timber",footing-Y*.38,top,.68,wood,mat.Wood,true)
            rod(site,"Wrapped lashing",top-Y*.55,top-Y*.24,.79,copper,mat.Fabric)
        end
        local a=base:PointToWorldSpace(V(-w*.475,5.95-side*.68,side*d*.44))
        local b=base:PointToWorldSpace(V(w*.475,5.95-side*.68,side*d*.44))
        rod(site,"Canopy crosspiece",a,b,.44,wood,mat.Wood)
    end
    -- Two curved-looking runs of canvas meet below the tops of the posts.
    for i=0,5 do
        local k=(i+.5)/6
        local y=5.95+(1-2*k)*.68-.58*math.sin(k*math.pi)
        local pitch=math.atan((1.36+.58*math.pi*math.cos(k*math.pi))/(d*.94))
        panel(site,"Draped canvas panel",base*C(0,y,(k-.5)*d*.94)*CFrame.Angles(pitch,0,0),
            V(w*.94,.13,d*.166),cloth:Lerp(ochre,if i==0 or i==5 then .24 else .025*(i%3)),mat.Fabric)
    end
    panel(site,"Sorting bench top",base*C(-w*.19,2.02,-1.95),V(w*.45,.33,2.2),wood,mat.WoodPlanks,true)
    for _,side in {-1,1} do
        panel(site,"Sorting table leg",base*C(-w*.19+side*w*.16,1.20,-1.95),V(.37,1.68,1.75),wood,mat.Wood,true)
    end
    for i=1,3 do
        local a=base*C(w*.10+i*.70,.62+i*.35,2.25-(i%2)*1.59)*CFrame.Angles(0,i*.11,0)
        panel(site,"Sample case",a,V(1.83,1.56,1.67),if i==2 then teal else wood:Lerp(ochre,.28),mat.WoodPlanks,true)
        for _,side in {-1,1} do
            panel(site,"Case edge",a*C(side*.64,0,-.84),V(.19,1.58,.13),copper,mat.Wood)
        end
    end
    for i=1,3 do
        stone(site,"Sandstone specimen",base*C(-w*.38+i*.89,2.33,-1.65+(i%2)*.35)*CFrame.Angles(0,.25*i,.08),
            V(.70,.36,.62),stoneGold)
    end
end
sampleCamp("Grabungslager Süd",-320,47,.15,true)
sampleCamp("Probenstation Nord",-446,-108,-.16,false)

local function railing(label: string,stations: {{number}})
    local segment=folder(label,scene)
    local last: Vector3?=nil
    for _,spot in stations do
        local at=ground(spot[1],spot[2]).Position
        local top=at+Y*2.5
        rod(segment,"Route marker timber",at-Y*.4,top,.48,wood,mat.Wood)
        if last then
            local a,b=last-Y*.45,top-Y*.45
            local mid=(a+b)/2-Y*.45
            rod(segment,"Braided rope",a,mid,.115,copper,mat.Fabric)
            rod(segment,"Braided rope",mid,b,.115,copper,mat.Fabric)
        end
        last=top
    end
end
railing("Böschung am Aussichtspunkt",{{-319,-48},{-326,-44},{-331,-36},{-333,-25},{-334,-14},{-338,-3}})
railing("Südliche Arbeitsterrasse",{{-378,35},{-393,40},{-403,43},{-413,45},{-427,45},{-444,46},{-460,40}})
railing("Nördliche Arbeitsterrasse",{{-356,-78},{-371,-83},{-388,-86},{-403,-87},{-420,-85},{-435,-83},{-450,-80}})

for _,array in {
    {-355,-76,-3.0,-.40,8}, {-455,41,-4.8,-.12,8}, {-399,43,-3.95,.44,6},
    {-489,-78,-3.39,1.76,5}, {-427,-78,-4.1,-.16,6},
} do
    for i=0,array[5] do
        local x,z=array[1]+i*array[3],array[2]+i*array[4]
        local g=ground(x,z)
        local h=random:NextNumber(1.1,2.21)
        stone(scene,"Exposed terrace facing",C(g.Position+Y*(h*.13))*CFrame.Angles(.065,-.15+.055*i,.045),
            V(math.abs(array[3])+.29,h,random:NextNumber(1.92,3.04)),ochre:Lerp(stoneGold,random:NextNumber(.05,.60)))
    end
end

-- Old sandstone retaining courses make the two lower working benches visible from the road.
for _,line in {
    {-374,-83,-4.45,-.12,9}, {-423,45,-4.33,-.17,8}, {-458,-76,-4.62,1.10,5},
} do
    for i=0,line[5] do
        local x,z=line[1]+i*line[3],line[2]+i*line[4]
        local g=ground(x,z)
        local yaw=math.atan(-line[4]/line[3])
        local cf=C(g.Position)*CFrame.Angles(0,yaw,0)
        stone(scene,"Terrace foundation course",cf*C(0,.25,0),V(math.abs(line[3])+.20,2.27,3.56),ochre)
        if i~=4 and i~=line[5] then
            stone(scene,"Broken upper retaining course",cf*C(.22,1.71,-.27)*CFrame.Angles(.02,0,.045*(i%3-1)),
                V(math.abs(line[3])-.06,1.32,2.72),stoneGold:Lerp(ochre,.085*(i%3)))
        end
    end
end

for i,point in {{-83,3},{-121,1},{-157,-11},{-194,-24},{-226,-26},{-263,-27},{-293,-11},
    {-344,36},{-368,64},{-404,81},{-461,63},{-366,-108},{-412,-120},{-477,-109}} do
    local g=ground(point[1],point[2])
    if g.Normal.Y>.69 then
        local cf=C(g.Position)*CFrame.Angles(.07,i*.64,-.065)
        stone(scene,"Route cairn foot",cf*C(0,.43,0),V(2.51,1.2,2.09),ochre)
        stone(scene,"Route cairn upper stone",cf*C(.19,1.36,0),V(1.87,1.03,1.64),stoneGold)
        panel(scene,"Teal wayfinder mark",cf*C(.22,1.44,-.84),V(.68,.25,.11),teal,mat.Marble)
    end
end

for _,coord in {{-342,3},{-353,-48},{-373,26},{-426,-65},{-453,25},{-500,-52},{-480,42},{-477,-49}} do
    for i=1,5 do
        local x,z=coord[1]+random:NextNumber(-8,8),coord[2]+random:NextNumber(-5,5)
        local g=ground(x,z)
        local h=random:NextNumber(.38,1.44)
        stone(scene,"Loose stone fragment",C(g.Position+Y*(.11*h))*CFrame.Angles(
            random:NextNumber(-.19,.19),random:NextNumber(-3.1,3.1),random:NextNumber(-.17,.17)),
            V(random:NextNumber(1.1,3.7),h,random:NextNumber(.9,2.6)),ochre:Lerp(deep,random:NextNumber(.12,.56)))
    end
end

chamfer:Destroy()
if previous then
    previous.Name=archive
    previous.Parent=storage
end
pack.Parent=world
local _,size=statue:GetBoundingBox()
return {path=pack:GetFullName(),figure=tostring(size),parts=#statue:GetDescendants(),scene=#scene:GetDescendants()}
