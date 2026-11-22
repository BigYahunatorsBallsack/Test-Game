--!strict
-- Studio Edit only. Dress the ruin basin with native masonry and in-place excavation art.
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Use Studio Edit mode")
assert(game.PlaceId==135831532782380,"Unexpected place")
local world=workspace:WaitForChild("DuneBaronWorld")
assert(world:GetAttribute("RuinsTerrainRevision")==1,"Build Ruins terrain first")
local storage=game:GetService("ServerStorage")
local owner="DuneBaronRuinsArt"
local prior=world:FindFirstChild("RuinsArtV1")
local archive="DuneBaronRuinsBeforeDressing"
assert(not prior or prior:GetAttribute("Owner")==owner,"Ruins art name occupied")
assert(not prior or not storage:FindFirstChild(archive),"Prior ruins art archive already exists")
local sources=storage.DuneBaronAssetLibrary.Finds.ruinenstadt
local geometry=game:GetService("GeometryService")
local V,C,rgb=Vector3.new,CFrame.new,Color3.fromRGB
local Y=Vector3.yAxis
local rng=Random.new(38429)
local mat=Enum.Material
local ochre,light,old=rgb(193,137,91),rgb(227,180,124),rgb(154,100,73)
local teal,rust,cloth,timber=rgb(46,111,111),rgb(116,79,58),rgb(203,155,105),rgb(101,66,47)

local function folder(name: string,parent: Instance?): Folder
    local f=Instance.new("Folder")
    f.Name,f.Parent=name,parent
    return f
end

local pack=folder("RuinsArtV1")
pack:SetAttribute("Owner",owner)
pack:SetAttribute("ZoneId","ruins")
local sites=folder("Landmarks",pack)
local paving=folder("Streets",pack)
local buried=folder("BuriedStructures",pack)
local finds=folder("BuriedFinds",pack)
local details=folder("DistrictDetails",pack)
local filter=RaycastParams.new()
filter.FilterType=Enum.RaycastFilterType.Include
filter.FilterDescendantsInstances={workspace.Terrain}
filter.IgnoreWater=true

local function ground(x: number,z: number): RaycastResult
    return assert(workspace:Raycast(V(x,174,z),V(0,-254,0),filter),"Terrain below ruins missing")
end

local function onGround(x: number,z: number,heading: number): CFrame
    return C(ground(x,z).Position)*CFrame.Angles(0,heading,0)
end

local function part(parent: Instance?,name: string,where: CFrame,size: Vector3,color: Color3,
        material: Enum.Material,solid: boolean?): Part
    local p=Instance.new("Part")
    p.Name,p.Size,p.CFrame,p.Color,p.Material=name,size,where,color,material
    p.Anchored,p.CanCollide,p.CanQuery,p.CanTouch=true,solid==true,solid==true,false
    p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    p.Parent=parent
    return p
end

local function cylinder(parent: Instance,name: string,where: CFrame,thick: number,diameter: number,
        c: Color3,material: Enum.Material,solid: boolean?): Part
    local p=part(parent,name,where*CFrame.Angles(0,0,math.pi/2),V(thick,diameter,diameter),c,material,solid)
    p.Shape=Enum.PartType.Cylinder
    return p
end

local function beam(parent: Instance,name: string,a: Vector3,b: Vector3,width: number,depth: number,
        c: Color3,material: Enum.Material,solid: boolean?)
    local span=b-a
    local up=if math.abs(span.Unit.Y)>.97 then Vector3.zAxis else Y
    part(parent,name,CFrame.lookAt((a+b)/2,b,up),V(width,depth,span.Magnitude),c,material,solid)
end

local blank=part(nil,"Masonry blank",C(),V(5,4,4),ochre,mat.Sandstone)
local clip=part(nil,"Corner chamfer",CFrame.Angles(0,math.pi/4,0),V(5.85,6,5.85),ochre,mat.Sandstone)
local ok,result=pcall(function() return geometry:IntersectAsync(blank,{clip},{SplitApart=false}) end)
clip:Destroy()
local blankShape: BasePart=blank
if ok and #result==1 then
    blankShape=result[1]
    blank:Destroy()
    if blankShape:IsA("PartOperation") then blankShape.UsePartColor=true end
elseif ok then
    for _,shape in result do shape:Destroy() end
end

local function stone(parent: Instance,name: string,cf: CFrame,size: Vector3,c: Color3,solid: boolean?): BasePart
    local p=blankShape:Clone()
    p.Name,p.Size,p.CFrame,p.Color,p.Material=name,size,cf,c,mat.Sandstone
    p.Anchored,p.CanCollide,p.CanQuery,p.CanTouch=true,solid==true,solid==true,false
    p.Parent=parent
    return p
end

local function varied(amount: number): Color3
    return ochre:Lerp(if amount<0 then old else light,math.abs(amount))
end

local function inlay(parent: Instance,name: string,at: CFrame,size: Vector3)
    part(parent,name,at,size,teal:Lerp(rgb(115,145,131),.18),mat.Marble)
end

local function seal(parent: Instance,cf: CFrame,diameter: number)
    cylinder(parent,"Sandstone rim",cf,diameter*.075,diameter,light,mat.Sandstone)
    cylinder(parent,"Aged copper annulus",cf*C(0,diameter*.038,0),diameter*.033,diameter*.82,rust,mat.CorrodedMetal)
    cylinder(parent,"Glazed centre",cf*C(0,diameter*.061,0),diameter*.039,diameter*.64,teal,mat.Marble)
    cylinder(parent,"Relief boss",cf*C(0,diameter*.087,0),diameter*.052,diameter*.22,light,mat.Sandstone)
    for index=0,3 do
        inlay(parent,"Copper key",cf*CFrame.Angles(0,index*math.pi/2,0)*C(0,diameter*.07,diameter*.44),
            V(diameter*.13,diameter*.045,diameter*.135))
    end
end

local function column(parent: Instance,where: CFrame,height: number,width: number,damage: boolean)
    stone(parent,"Foundation dressed block",where*C(0,.38,0),V(width*1.76,1.32,width*1.73),old,true)
    stone(parent,"Plinth",where*C(0,1.02,0),V(width*1.45,.61,width*1.42),light,true)
    cylinder(parent,"Column foot",where*C(0,1.65,0),.71,width*1.1,ochre,mat.Sandstone,true)
    local drums=if damage then 3 else 5
    local length=(height-2.8)/drums
    for i=1,drums do
        local center=where*C(0,1.98+(i-.5)*length,0)
        local scale=1.02-i*.041
        cylinder(parent,"Column drum",center,length+.032,width*scale,varied((i%3-1)*.2),mat.Sandstone,true)
        if i==2 then
            cylinder(parent,"Glazed drum band",center*C(0,length*.28,0),.21,width*(scale+.032),teal,mat.Marble)
        end
    end
    if damage then
        stone(parent,"Broken crown",where*C(.21,height-.65,-.20)*CFrame.Angles(.16,.25,-.17),V(width*.84,.63,width*.77),old,true)
    else
        cylinder(parent,"Capital neck",where*C(0,height-.66,0),.59,width*1.15,light,mat.Sandstone,true)
        stone(parent,"Chamfered capital",where*C(0,height-.21,0),V(width*1.43,.64,width*1.43),light,true)
    end
end

-- A monumental road gate with a wide opening, broken parapets and visible foundations.
do
    local gate=folder("Tor der Salzkarawanen",sites)
    local at=onGround(1874,866,math.pi/2)
    for _,side in {-1,1} do
        local x=side*22.1
        for i=1,6 do
            local w=if i<=2 then 11.18 else 8.85-i*.14
            local shade=varied((i%3-1)*.31)
            stone(gate,"Gate pier course",at*C(x,i*2.92-1.79,0),V(w,2.94,10-i*.35),shade,true)
            if i==3 then
                inlay(gate,"Pier glaze",at*C(x,i*2.92-2.88,-(10-i*.35)/2-.04),V(w*.83,.48,.14))
            end
        end
        stone(gate,"Capital arch spring",at*C(x,17.48,0),V(10.65,2.09,10.1),light,true)
        for j=1,5 do
            local a=at:PointToWorldSpace(V(side*(27+j*4.9),0,side*.55*j))
            local base=ground(a.X,a.Z)
            for course=1,(if j%2==0 then 2 else 3) do
                stone(gate,"Eroded perimeter course",C(base.Position+Y*(course*1.85-1.1))*at.Rotation
                    *CFrame.Angles(0,.067*j*side,0),V(5.22,1.87,5.45-j*.31),varied(rng:NextNumber(-.31,.23)),true)
            end
        end
    end
    for i=-2,2 do
        stone(gate,"Jointed lintel",at*C(i*10.42,20.43,0),V(10.50,4.1,8.52),varied(.38+(i%2)*.20),true)
    end
    stone(gate,"Roof coping",at*C(0,22.89,.1),V(54.6,1.24,9.5),light,true)
    for _,side in {-1,1} do
        inlay(gate,"Lintel stripe",at*C(side*13.8,20.46,-4.30),V(15.2,.79,.15))
    end
    seal(gate,at*C(0,20.48,-4.39)*CFrame.Angles(-math.pi/2,0,0),6.65)
end

-- A dry plaza uses low, half-submerged paving so the main equipment lane stays open.
for row=0,32 do
    local x=1887+row*6.48
    local z=861+.027*(x-1930)+2.2*math.sin(row*.21)
    for col=-2,2 do
        if rng:NextNumber()>(if math.abs(col)==2 then .37 else .12) then
            local az=z+col*5.3+rng:NextNumber(-.4,.4)
            local hit=ground(x,az)
            if hit.Normal.Y>.92 then
                stone(paving,"Roadstone",C(hit.Position+Y*rng:NextNumber(-.41,-.22))
                    *CFrame.Angles(.025,rng:NextNumber(-.16,.16),.015),
                    V(rng:NextNumber(5,6.32),.90,rng:NextNumber(4.1,5.15)),varied(rng:NextNumber(-.67,.13)))
            end
        end
    end
end

do
    local court=folder("Sonnenplatz",sites)
    local at=onGround(1993,856,0)
    for i,nameZ in { {-38,13.2}, {-26,17.8}, {26,18.4}, {39,12}, {-37,33.5}, {37,32.2} } do
        local p=at:PointToWorldSpace(V(nameZ[1],0,-nameZ[2]))
        local pose=onGround(p.X,p.Z,-.2+.06*i)
        column(court,pose,if i==2 or i==3 then 13.2 else 5.7+(i%3)*1.4,if i<5 then 3.84 else 3.1,i~=2 and i~=3)
    end
    local g=onGround(1993,831,0)
    cylinder(court,"Buried dais",g*C(0,.02,0),1.58,25.3,old,mat.Sandstone,true)
    cylinder(court,"Terraced dais",g*C(0,.83,0),.84,20.1,ochre,mat.Sandstone,true)
    seal(court,g*C(0,1.22,0),17.3)
    for i=0,6 do
        local a=math.rad(32*i-97)
        local pose=g*CFrame.Angles(0,a,0)*C(0,.39,16.6)
        stone(court,"Low radial seat",pose,V(5.31,1.1,2.45),varied(rng:NextNumber(-.28,.32)),true)
    end
    local fallen=onGround(1962,881,.51)*C(0,.67,0)*CFrame.Angles(0,0,math.rad(82))
    cylinder(court,"Collapsed column shaft",fallen,7,3.52,ochre,mat.Sandstone,true)
    cylinder(court,"Fallen glaze band",fallen*C(0,.9,0),.36,3.66,teal,mat.Marble)
    stone(court,"Fallen capital",fallen*C(0,3.92,0),V(4.71,.9,4.65),light,true)
end

-- Retaining terraces, steps and a small gathering court on the north street.
do
    local steps=folder("Versunkene Stufen",sites)
    local at=onGround(2021,761,0)
    for row=0,3 do
        local radius=13+row*4.8
        for i=-5,5 do
            if row<2 or (i~=4 and (math.abs(i)~=5 or row==2)) then
                local angle=math.rad(i*15+180)
                local cf=at*CFrame.Angles(0,angle,0)*C(0,row*.73+.4,radius)
                stone(steps,"Curved seat terrace",cf,V(radius*.256,1.05,4.87),varied(rng:NextNumber(-.35,.37)),true)
            end
        end
    end
    for i=1,5 do
        stone(steps,"Aisle tread",at*C(10+.50*i,i*.58-.13,1.7-i*1.55),V(3.82,.68,1.64),light,true)
    end
    for _,offset in {-20,19} do
        local p=at:PointToWorldSpace(V(offset,0,-13.3))
        column(steps,onGround(p.X,p.Z,offset*.029),6.7+offset*.062,2.84,true)
    end
    stone(steps,"Old performance plinth",at*C(0,.29,3),V(14.7,.83,7.64),old,true)
end

-- The former merchant district frames a side street between the plaza and archive.
do
    local district=folder("Warenviertel",sites)
    local at=onGround(2046,911,-.12)
    for room=-1,1 do
        local cx=room*15.03
        local center=at:PointToWorldSpace(V(cx,0,.42))
        local floor=C(ground(center.X,center.Z).Position)*at.Rotation
        stone(district,"Half-buried shop pavement",floor*C(0,-.05,0),V(14.98,1.18,19.3),old,true)
        for course=1,4 do
            for col=-1,1 do
                if not (course==4 and (room==1 or col==1)) and not (course==3 and room==-1 and col==-1) then
                    stone(district,"Shop rear-wall course",floor*C(col*4.94+(course%2)*.27,course*2.02-.8,8.74),
                        V(5.13,2.05,2.49),varied(rng:NextNumber(-.35,.32)),true)
                end
            end
            if course<=3 then
                for _,side in {-1,1} do
                    if course<=2 or room~=side then
                        stone(district,"Roofless shop frontage",floor*C(side*6.10,course*1.88-.69,-8.12),
                            V(3.43,1.92,2.48),varied(.20-course*.07),true)
                    end
                end
            end
        end
        for j=-1,1 do
            for course=1,(if room==-1 then 3 else 2) do
                if course<3 or j~=0 then
                    stone(district,"Shop dividing wall",floor*C(-7.35,course*1.96-.72,j*5.68),
                        V(2.28,1.99,5.78),varied(rng:NextNumber(-.27,.32)),true)
                end
            end
        end
        stone(district,"Street threshold",floor*C(0,.16,-8.28),V(5.38,.71,3.68),light)
        inlay(district,"Trade counter glaze",floor*C(-6.17,2.21,-9.40),V(2.54,.32,.10))
        stone(district,"Abandoned storage bench",floor*C(3.0,1.01,4.8),V(5.77,1.38,3.27),varied(-.27),true)
    end
    local lie=onGround(2016,908,.59)*C(0,1.06,0)*CFrame.Angles(0,0,1.44)
    cylinder(district,"Fallen street column",lie,8.7,3.1,ochre,mat.Sandstone,true)
    cylinder(district,"Fallen inlaid collar",lie*C(0,-1.65,0),.42,3.25,teal,mat.Marble)
    stone(district,"Fragment of street capital",lie*C(0,4.64,0),V(4.06,.83,4.12),light,true)
end

do
    local court=folder("Zisternenhof",sites)
    local at=onGround(2102,833,.20)
    stone(court,"Cistern apron",at*C(0,-.25,0),V(25.1,1.32,17.93),old,true)
    for i=0,11 do
        if i~=5 then
            local pose=at*CFrame.Angles(0,i*math.pi/6,0)*C(0,.82,5.93)
            stone(court,"Cistern coping",pose,V(3.3,1.21,1.57),varied(rng:NextNumber(-.2,.4)),true)
        end
    end
    cylinder(court,"Silted cistern floor",at*C(0,.43,0),.38,10.76,varied(-.53),mat.Sandstone,true)
    for j=1,4 do
        for col=-2,2 do
            if j<=2 or math.abs(col)<3-j*.26 then
                stone(court,"Cistern dividing wall",at*C(4.93*col+(j%2)*.32,j*1.58-.53,-8.3),
                    V(5,1.61,2.42),varied(rng:NextNumber(-.32,.42)),true)
            end
        end
    end
    column(court,at*C(10.1,-.25,5.65),8.49,2.81,false)
    column(court,at*C(-10.45,-.20,5.65),5.09,2.78,true)
    seal(court,at*C(0,3.87,-7.02)*CFrame.Angles(math.pi/2,0,0),3.09)
end

-- Part of the archive wall intentionally sits below the visible grade. The adjoining hall
-- and threshold remain intact below native terrain for the dig interaction to uncover.
local function buriedHall(name: string,x: number,z: number,yaw: number,scale: number)
    local site=folder(name,buried)
    local at=onGround(x,z,yaw)
    site:SetAttribute("ArtBurial",true)
    site:SetAttribute("Center",at.Position)
    site:SetAttribute("FloorY",at.Y-5.45*scale)
    site:SetAttribute("PlanStuds",V(29*scale,0,21*scale))
    local function pose(a: number,b: number,c: number): CFrame
        return at*C(a*scale,b*scale,c*scale)
    end
    for i=-2,2 do
        for j=-1,1 do
            stone(site,"Buried floor slab",pose(i*5.72,-5.91,j*6.71),V(5.76,.89,6.68)*scale,varied((i+j)%3*.12),true)
        end
    end
    for i=-3,3 do
        for j=1,3 do
            if j<3 or math.abs(i)>1 then
                local crown=if j==3 then .37 else 0
                stone(site,"Buried archive wall",pose(i*4.19+(j%2)*.56,j*1.37-6.05+crown,-8.3),
                    V(4.23,1.40,3.4)*scale,varied((j%3-1)*.27),true)
            end
        end
    end
    for _,side in {-1,1} do
        for j=1,4 do
            for i=1,(if j%3==1 then 3 else 2) do
                stone(site,"Buried side niche",pose(side*12.1,i*1.38-5.91,j*3.86-8.61),
                    V(3.31,1.42,3.91)*scale,varied((i%3-1)*.29),true)
            end
        end
        stone(site,"Visible foundation crown",pose(side*12.1,.13,-5.1)*CFrame.Angles(0,.09*side,.13),
            V(3.47,1.12,4.02)*scale,varied(.38))
    end
    seal(site,pose(0,-3.53,-6.35)*CFrame.Angles(math.pi/2,0,0),5.5*scale)
    stone(site,"Archive door threshold",pose(0,-4.7,7.6),V(9.58,1.0,3.57)*scale,light,true)
    for _,corner in {-1,1} do
        stone(site,"Exposed lintel tip",pose(corner*3.37,-.08,6.3)*CFrame.Angles(0,corner*.22,corner*.12),
            V(4.86,1.13,2.87)*scale,ochre)
    end
end
buriedHall("Versandetes Archiv",2090,931,-.32,1)
buriedHall("Überwehte Siegelkammer",2145,810,.49,.74)

-- An offset sanctuary keeps the harvester route south of the archaeological steps.
do
    local temple=folder("Tempel am Ostgrat",sites)
    local at=onGround(2262,849,math.pi/2)
    for i=1,5 do
        stone(temple,"Sanctuary stair",at*C(0,i*.66-.27,-23.3+i*1.82),V(21.6,.76,1.92),light,true)
    end
    stone(temple,"Sanctuary raft",at*C(0,1.35,1.22),V(38,2.82,32.3),old,true)
    stone(temple,"Sanctuary pavement",at*C(0,2.62,.46),V(34.1,.74,31.5),ochre,true)
    for i=-1,1,2 do
        column(temple,at*C(i*12.4,2.93,-9.8),15.3,4.6,false)
        column(temple,at*C(i*12.4,2.93,3.46),if i<0 then 15.3 else 8.1,4.6,i>0)
    end
    stone(temple,"Carved architrave",at*C(0,18.8,-9.8),V(32.9,2.17,5.45),light,true)
    stone(temple,"Roof lip",at*C(0,20.1,-9.85),V(34.3,.59,6.14),ochre,true)
    for i=-1,1 do
        inlay(temple,"Roof frieze inset",at*C(i*8.95,18.81,-12.63),V(if i==0 then 5.3 else 7.09,.64,.16))
    end
    for row=1,5 do
        for i=-3,3 do
            if row<=3 or math.abs(i)<3 then
                stone(temple,"Sanctuary rear course",at*C(i*4.8+(row%2)*.34,row*1.99+1.92,11.9),
                    V(4.83,2.02,4.49),varied(rng:NextNumber(-.23,.32)),true)
            end
        end
    end
    seal(temple,at*C(0,8.87,9.52)*CFrame.Angles(-math.pi/2,0,0),8.45)
    for i=-1,1,2 do
        stone(temple,"Weathered offering plinth",at*C(i*7,3.48,6.76),V(5.4,1.15,4.8),old,true)
        stone(temple,"Offering casket",at*C(i*7,4.55,6.62),V(3.42,1.03,2.5),ochre,true)
    end
end

-- Outer columns on raised ground break up the skyline behind the city.
do
    local ridge=folder("Wachtgrat",sites)
    local at=onGround(2365,899,math.pi/2)
    for _,side in {-1,1} do
        for i=1,3 do
            local xy=at:PointToWorldSpace(V(side*(22+4.2*i),0,(i-2)*6.77))
            column(ridge,onGround(xy.X,xy.Z,-.23*side),6.7+i*1.54,2.98,i%2==0)
        end
    end
    for i=0,4 do
        local hit=ground(2317+i*7,798+i*4)
        if hit.Normal.Y>.66 then
            column(ridge,onGround(hit.Position.X,hit.Position.Z,.04*i),11.2-(i%2)*2.25,2.92,i%2==1)
        end
    end
end

-- Work camp on the windward side of the gate. Accent against the black ground and pale city.
do
    local camp=folder("Grabungslager",sites)
    local at=onGround(1844,899,.54)
    for _,side in {-1,1} do
        for _,z in {-4.2,4.2} do
            local tip=at:PointToWorldSpace(V(side*6.2,if z<0 then 5.92 else 4.29,z))
            local g=ground(tip.X,tip.Z).Position
            beam(camp,"Camp timber",g-Y*.35,tip,.49,.49,timber,mat.Wood,true)
        end
    end
    for i=-2,2 do
        part(camp,"Canvas awning",at*C(i*2.55,5.03,0)*CFrame.Angles(.191,0,0),V(2.59,.15,9.02),
            if i==1 or i==-1 then teal:Lerp(cloth,.32) else cloth:Lerp(light,.54),mat.Fabric)
    end
    for i,coord in {{-3.9,2.02},{-2.38,2.82},{3.5,.42},{4.97,1.43}} do
        local p=at:PointToWorldSpace(V(coord[1],0,coord[2]))
        local cf=onGround(p.X,p.Z,rng:NextNumber(-.42,.51))*C(0,1,0)
        part(camp,"Canvas-wrapped specimen box",cf,V(1.93,2.05,1.99),varied(-.32+i*.08),mat.WoodPlanks,true)
        for _,side in {-1,1} do
            part(camp,"Crate edge",cf*C(side*.65,0,-1.01),V(.19,2.07,.11),timber,mat.Wood)
        end
    end
    part(camp,"Sample table",at*C(-2.6,1.69,-1.74),V(4.78,.29,2.1),timber,mat.WoodPlanks,true)
    for _,side in {-1,1} do
        part(camp,"Table leg",at*C(-2.6+side*1.83,.76,-1.74),V(.34,1.64,1.69),timber,mat.Wood,true)
    end
    stone(camp,"Relief rubbing stone",at*C(-2.8,1.9,-1.84)*CFrame.Angles(0,.42,0),V(2.08,.35,1.33),light)
    inlay(camp,"Relief on bench",at*C(-2.8,2.06,-1.84)*CFrame.Angles(0,.42,0),V(.66,.07,.59))
end

for _,node in {{1851,834},{1896,836},{1905,898},{1939,887},{2007,819},{2033,886},{2073,841},
    {2099,899},{2135,922},{2171,846},{2222,901},{2255,917},{2309,918},{2319,851},{2350,874}} do
    for i=1,rng:NextInteger(3,6) do
        local x,z=node[1]+rng:NextNumber(-7,7),node[2]+rng:NextNumber(-5.75,5.75)
        local hit=ground(x,z)
        if hit.Normal.Y>.71 then
            local height=rng:NextNumber(.55,1.75)
            stone(details,"Half-buried masonry",C(hit.Position+Y*(height*.18))*CFrame.Angles(
                rng:NextNumber(-.23,.23),rng:NextNumber(0,6.283),rng:NextNumber(-.18,.18)),
                V(rng:NextNumber(1.3,4.6),height,rng:NextNumber(.98,2.85)),varied(rng:NextNumber(-.48,.30)))
        end
    end
end

local function entomb(id: string,name: string,x: number,z: number,yaw: number)
    local source=sources:FindFirstChild(id)
    assert(source and source:IsA("Model"),"Missing canonical ruin find "..id)
    local model=source:Clone()
    model.Name=name
    local y=ground(x,z).Position.Y
    model:PivotTo(C(x,0,z)*CFrame.Angles(0,yaw,0))
    local box,size=model:GetBoundingBox()
    model:PivotTo(model:GetPivot()+Y*(y-1.5-(box.Y+size.Y/2)))
    model:SetAttribute("ArtBurial",true)
    model:SetAttribute("SurfaceY",y)
    for _,p in model:GetDescendants() do
        if p:IsA("LuaSourceContainer") then p:Destroy()
        elseif p:IsA("BasePart") then p.Anchored,p.CanCollide,p.CanTouch=true,false,false end
    end
    model.Parent=finds
end
entomb("ruinenstadt_04","Versandeter Reliefsplitter",1857,894,.37)
entomb("ruinenstadt_09","Versandete Duftlampe",2027,773,-.56)
entomb("ruinenstadt_26","Versandeter Steinbolzen",2089,931,.26)
entomb("ruinenstadt_27","Versandetes Fingerglied",2216,855,1.15)

blankShape:Destroy()
if prior then
    prior.Name=archive
    prior.Parent=storage
end
pack.Parent=world
return {path=pack:GetFullName(),landmarks=#sites:GetChildren(),finds=#finds:GetChildren(),buried=#buried:GetChildren()}
