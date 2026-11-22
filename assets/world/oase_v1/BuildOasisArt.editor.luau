--!strict
-- Studio Edit only. The Oase art has no runtime scripts or gameplay tags.
local run = game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Use Studio Edit mode")
assert(game.PlaceId == 135831532782380, "Unexpected place")
local world = workspace:WaitForChild("DuneBaronWorld")
assert(world:GetAttribute("OasisTerrainRevision") == 1, "Build the oasis terrain first")
local storage = game:GetService("ServerStorage")
local geometry = game:GetService("GeometryService")
local terrain = workspace.Terrain
local V,C,rgb = Vector3.new,CFrame.new,Color3.fromRGB
local Y = Vector3.yAxis
local owner = "DuneBaronOasisArt"
local old = world:FindFirstChild("OasisArtV1")
assert(not old or old:GetAttribute("Owner") == owner, "Oasis art name in use")
local art = Instance.new("Folder")
art.Name = "OasisArtV1"
art:SetAttribute("Owner",owner)
art:SetAttribute("ZoneId","oasis")

local mat = Enum.Material
local palette = {
    limestone=rgb(222,173,114), cream=rgb(243,206,147), clay=rgb(176,93,58),
    rock=rgb(157,86,60), ridge=rgb(189,108,69), shadow=rgb(128,75,55),
    wood=rgb(109,69,43), woodLight=rgb(154,99,58), rope=rgb(181,132,79),
    teal=rgb(31,109,112), lightTeal=rgb(68,143,137), leaf=rgb(59,115,73), leafShade=rgb(36,81,63),
    blade=rgb(103,129,66), ochre=rgb(202,149,61), dark=rgb(47,49,42),
}
local function new(class: string,name: string,parent: Instance?): any
    local x=Instance.new(class)
    x.Name=name
    x.Parent=parent
    return x
end

local function piece(parent: Instance,name: string,size: Vector3,cf: CFrame,color: Color3,material: Enum.Material?,solid: boolean?,class: string?): BasePart
    local p = new(class or "Part",name,nil)
    p.Size,p.CFrame,p.Color = size,cf,color
    p.Anchored = true
    p.CanCollide,p.CanQuery,p.CanTouch = solid==true,solid==true,false
    p.Material = material or mat.SmoothPlastic
    p.TopSurface,p.BottomSurface = Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end

local function box(parent: Instance,name: string,frame: CFrame,size: Vector3,localPoint: Vector3,color: Color3,material: Enum.Material?,solid: boolean?)
    return piece(parent,name,size,frame*C(localPoint),color,material,solid)
end

local function shaft(parent: Instance,name: string,a: Vector3,b: Vector3,d: number,color: Color3,material: Enum.Material?,solid: boolean?)
    local axis = (b-a).Unit
    local guide = if math.abs(axis:Dot(Y))<0.87 then Y else Vector3.zAxis
    local up = (guide-axis*guide:Dot(axis)).Unit
    local cf = CFrame.fromMatrix((a+b)/2,axis,up)
    local p = piece(parent,name,V((b-a).Magnitude,d,d),cf,color,material,solid) :: Part
    p.Shape = Enum.PartType.Cylinder
    return p
end

local function pebble(parent: Instance,name: string,cf: CFrame,dim: Vector3,color: Color3)
    local p=piece(parent,name,dim,cf,color,mat.Sandstone,false) :: Part
    p.Shape=Enum.PartType.Ball
    return p
end

local solidRay = RaycastParams.new()
solidRay.FilterType = Enum.RaycastFilterType.Include
solidRay.FilterDescendantsInstances = {terrain}
solidRay.IgnoreWater = true
local wetRay = RaycastParams.new()
wetRay.FilterType = Enum.RaycastFilterType.Include
wetRay.FilterDescendantsInstances = {terrain}
local function surface(x: number,z: number,includeWater: boolean?): RaycastResult
    local hit=workspace:Raycast(V(x,129,z),V(0,-181,0),if includeWater then wetRay else solidRay)
    assert(hit,"Oasis ground not found")
    return hit
end

local function point(x: number,z: number): Vector3
    return surface(x,z).Position
end

local function stone(parent: Instance,center: Vector3,dim: Vector3,yaw: number,color: Color3,collide: boolean?)
    local cf=C(center)*CFrame.Angles(0,yaw,0)
    local body=piece(parent,"Weathered Sandstone",dim,cf,color,mat.Sandstone,collide)
    for _, side in {-1,1} do
        piece(parent,"Fractured Corner",V(dim.X*.38,dim.Y*.82,dim.Z*.51),
            cf*C(side*dim.X*.45,-dim.Y*.035,-dim.Z*.17)*CFrame.Angles(0,side*.42,0),
            color:Lerp(palette.ridge,if side==1 then .28 else .04),mat.Sandstone,collide,"WedgePart")
    end
    return body
end

local function triangles(parent: Instance,a: Vector3,b: Vector3,c: Vector3,color: Color3,thickness: number,out: {BasePart})
    local ab,ac,bc = b-a,c-a,c-b
    if ab.Magnitude>ac.Magnitude and ab.Magnitude>bc.Magnitude then
        c,a=a,c
    elseif ac.Magnitude>bc.Magnitude then
        a,b=b,a
    end
    ab,ac,bc=b-a,c-a,c-b
    local x,z=ac:Cross(ab).Unit,bc.Unit
    local up=z:Cross(x)
    local h=math.abs(ab:Dot(up))
    for _,half in {{b,z,x,math.abs(ab:Dot(z))},{c,-z,-x,math.abs(ac:Dot(z))}} do
        if h>.02 and half[4]>.02 then
            table.insert(out,piece(parent,"Leaf Facet",V(thickness,h,half[4]),
                CFrame.fromMatrix((a+half[1])/2,half[3],up,half[2]),color,mat.SmoothPlastic,false,"WedgePart"))
        end
    end
end

local function consolidate(parent: Instance,field: {BasePart},name: string,color: Color3)
    local operands = table.clone(field)
    local first=table.remove(operands,1)
    if not first then return end
    local ok,meshes=pcall(function() return geometry:UnionAsync(first,operands,{SplitApart=false}) end)
    if ok and #meshes>0 then
        for _, facet in field do facet:Destroy() end
        for _, mesh in meshes do
            mesh.Name,mesh.Color,mesh.Material = name,color,mat.SmoothPlastic
            mesh.Anchored,mesh.CanCollide,mesh.CanQuery,mesh.CanTouch = true,false,false,false
            if mesh:IsA("PartOperation") then mesh.UsePartColor=true end
            mesh.Parent=parent
        end
    end
end

local function palmPrototype(seed: number)
    local m=new("Model","Date Palm",nil) :: Model
    local root=piece(m,"GroundPivot",V(.2,.2,.2),C(),palette.wood)
    root.Transparency=1
    m.PrimaryPart=root
    local height=17.2+seed*1.45
    local bend=3.8+seed*.30
    local function center(t: number): Vector3
        return V(bend*t^1.68,height*t,.7*math.sin(t*math.pi)-1.3*t*t)
    end
    for i=1,8 do
        local t=(i-1)/8
        local a,b=center(t),center(i/8)
        local axis=(b-a).Unit
        local width=1.43-.64*t
        shaft(m,"Palm Trunk",a-axis*.09,b+axis*.11,width,palette.woodLight:Lerp(palette.wood,0.28+t*.25),mat.Wood)
        if i>1 then
            shaft(m,"Frond Scar",a-axis*.10,a+axis*.10,width+.08,palette.wood:Lerp(palette.ochre,.18),mat.Wood)
        end
    end
    local crown=center(1)
    local bright,shade={},{}
    local baseC=palette.leaf:Lerp(palette.lightTeal,seed*.08)
    local darkC=palette.leafShade:Lerp(palette.leaf,seed*.07)
    for i=0,8 do
        local angle=i*2.399963+seed*.57
        local d=V(math.cos(angle),0,math.sin(angle))
        local cross=Y:Cross(d)
        local length=7.9+1.55*math.sin(i*2.13+seed)
        local rise=1.45+1.15*math.cos(i*1.6+seed)
        local fall=1.8+1.25*math.sin(i*1.17)
        local first=crown+Y*.31-d*.35
        local shoulder=crown+d*(length*.31)+Y*(rise+.4)
        local elbow=crown+d*(length*.68)+Y*(rise*.59)
        local tip=crown+d*length-Y*fall+cross*.41
        for _, sign in {-1,1} do
            local mid=shoulder+cross*sign*(length*.129)-Y*.52
            local outer=elbow+cross*sign*(length*.09)-Y*.40
            local col=if sign==1 then baseC else darkC
            local out=if sign==1 then bright else shade
            triangles(m,first,shoulder,mid,col,.14,out)
            triangles(m,mid,shoulder,elbow,col,.14,out)
            triangles(m,mid,elbow,outer,col,.14,out)
            triangles(m,outer,elbow,tip,col,.11,out)
        end
    end
    consolidate(m,bright,"Palm Fronds Sun Side",baseC)
    consolidate(m,shade,"Palm Fronds Shade Side",darkC)
    for i=0,2 do
        local a=i*2*math.pi/3
        pebble(m,"Date Cluster",C(crown+V(math.cos(a)*.66,-.32,math.sin(a)*.66)),V(.48,.82,.50),palette.wood)
    end
    return m
end

local approach=new("Folder","Approach",art)
local pools=new("Folder","Shoreline",art)
local trees=new("Folder","PalmGroves",art)
local landmarks=new("Folder","Structures",art)
local excavation=new("Folder","BuriedFinds",art)
local weather=new("Folder","WeatherPresets",art)

local facePond = function(x: number,z: number): CFrame
    local p=point(x,z)
    return CFrame.lookAt(p,V(318,p.Y,653))
end

local function pilgrimMarker(x:number,z:number,dx:number,dz:number,index:number)
    local p=point(x,z)
    local cf=CFrame.lookAt(p,V(x+dx,p.Y,z+dz))
    local it=new("Folder",string.format("Route Marker %02d",index),approach)
    box(it,"Marker Foot",cf,V(1.63,.58,1.08),V(0,.10,0),palette.rock,mat.Sandstone)
    box(it,"Sandstone Post",cf,V(.80,2.78,.69),V(0,1.36,0),palette.limestone,mat.Sandstone)
    piece(it,"Turquoise Inlay",V(.48,.48,.105),cf*C(0,2.02,-.377)*CFrame.Angles(0,0,math.pi/4),palette.teal)
    box(it,"Weathered Cap",cf,V(1.03,.3,.89),V(0,2.76,0),palette.cream,mat.Sandstone)
    stone(it,point(x+.96,z-.67)+V(0,.10,0),V(1.15,.40,.81),index*.91,palette.ridge)
end

for i,pos in {
    {120,424},{144,447},{148,480},{177,486},{181,521},{210,540},{209,565},
    {225,591},{243,602},{238,635},{218,665},{244,705},{268,730},
} do
    pilgrimMarker(pos[1],pos[2],25,26,i)
end

do
    local p=point(221,565)
    local frame=CFrame.lookAt(p,V(241,p.Y,601))
    local entrance=new("Folder","CaravanPassGate",landmarks)
    for _,side in {-1,1} do
        local foot=frame:PointToWorldSpace(V(side*7.7,0,0))
        local height=point(foot.X,foot.Z).Y
        local f=CFrame.new(foot.X,height,foot.Z)*frame.Rotation
        box(entrance,"Foundation",f,V(4.2,1.33,3.22),V(0,.07,0),palette.ridge,mat.Sandstone,true)
        for i=0,(if side==1 then 3 else 4) do
            piece(entrance,"Laid Limestone",V(3.17-i*.1,1.43,2.83),
                f*C(.08*math.cos(i*2),1.27+i*1.34,0)*CFrame.Angles(0,.04*math.sin(i*3),0),
                palette.limestone:Lerp(palette.cream,0.15*(i%3)),mat.Sandstone,true)
        end
        box(entrance,"Blue Tile Inlay",f,V(1.06,.38,.12),V(0,4.42,-1.44),palette.teal)
        if side<0 then
            piece(entrance,"Broken Overhang",V(4.37,.85,3.06),f*C(-.32,7.0,0)*CFrame.Angles(0,.071,.055),
                palette.cream,mat.Sandstone)
        end
    end
end

local palmPlacements = {
    {251,592,1.07},{259,606,1.23},{238,630,.77},{232,657,1.16},
    {253,692,.93},{273,708,1.06},{293,719,1.14},{317,717,.73},
    {339,715,.96},{359,714,1.28},{381,701,1.09},{395,684,.77},
    {410,662,1.16},{405,634,1.17},{392,615,.84},{384,598,1.15},
    {342,588,.89},{310,585,.86},{297,595,1.14},{274,599,.83},{337,668,.71},
}
local prototypes={palmPrototype(1),palmPrototype(2),palmPrototype(3)}
local palmCount=0
for i,row in palmPlacements do
    if surface(row[1],row[2],true).Material~=mat.Water then
        local model=prototypes[(i-1)%3+1]:Clone()
        model.Name=string.format("DatePalm%02d",i)
        model:ScaleTo(row[3])
        model:PivotTo(C(point(row[1],row[2])-Y*.25)*CFrame.Angles(0,i*2.399963,0))
        model.Parent=trees
        palmCount+=1
    end
end
for _,m in prototypes do m:Destroy() end

local shorePlaces = {
    {254,629},{246,642},{250,661},{256,681},{264,689},{281,703},{310,707},
    {328,705},{352,701},{370,686},{383,673},{389,647},{379,623},{368,612},
    {351,608},{330,600},{304,602},{292,602},{276,610},{340,668},
}
local seed = Random.new(733241)
local function reeds(x:number,z:number,scale:number,parent:Instance)
    local p=point(x,z)
    local water=surface(x,z,true)
    if water.Material==mat.Water and water.Position.Y-p.Y>3.3 then return end
    for i=1,5 do
        local angle=i*2.39+seed:NextNumber(-.3,.3)
        local outward=V(math.cos(angle),0,math.sin(angle))
        local a=p+outward*seed:NextNumber(.15,.61)*scale-Y*.15
        local top=a+Y*seed:NextNumber(1.4,3.6)*scale+outward*seed:NextNumber(.45,1.05)*scale
        local dir=(top-a).Unit
        local beam=CFrame.lookAt((a+top)/2,(a+top)/2+dir)
        piece(parent,"Ribbon Leaf",V(seed:NextNumber(.21,.33)*scale,.14*scale,(top-a).Magnitude),beam,
            palette.blade:Lerp(palette.leaf,.15*(i%5)),mat.SmoothPlastic,false,"WedgePart")
    end
end
for i,xy in shorePlaces do
    local x,z=xy[1],xy[2]
    reeds(x,z,seed:NextNumber(.86,1.41),pools)
    if i%3==1 then reeds(x+1.9,z+1.7,.79,pools) end
    local p=point(x+3.8,z-2.2)
    stone(pools,p+Y*.07,V(seed:NextNumber(2.4,5.1),seed:NextNumber(.8,1.65),seed:NextNumber(2.1,4.1)),
        seed:NextNumber(-math.pi,math.pi),palette.ridge:Lerp(palette.cream,.095*(i%4)))
end
for _,xy in {
    {261,634},{261,662},{269,689},{285,701},{336,706},{365,691},{379,662},
    {382,641},{367,617},{351,615},{325,604},{302,609},{284,618}
} do
    local p=point(xy[1],xy[2])
    if p.Y>4.4 then
        pebble(pools,"Submerged Limestone",C(p+Y*.30)*CFrame.Angles(0,seed:NextNumber(-2,2),.06),
            V(seed:NextNumber(2.8,5.5),seed:NextNumber(.7,1.46),seed:NextNumber(2.4,4.7)),palette.cream)
    end
end

local function jar(parent:Instance,origin:CFrame,height:number,color:Color3)
    local p=origin.Position
    local s=height
    local body=piece(parent,"Earthenware Body",V(s*.75,s*.84,s*.75),origin*C(0,s*.44,0),color,mat.SmoothPlastic) :: Part
    body.Shape=Enum.PartType.Ball
    shaft(parent,"Jar Neck",p+Y*(s*.68),p+Y*(s*.96),s*.39,color)
    shaft(parent,"Rolled Rim",p+Y*(s*.92),p+Y*(s*1.02),s*.49,color:Lerp(palette.cream,.19))
    shaft(parent,"Jar Opening",p+Y*(s*1.018),p+Y*(s*1.024),s*.31,palette.dark)
    shaft(parent,"Slip Band",p+Y*(s*.23),p+Y*(s*.285),s*.652,color:Lerp(palette.cream,.45))
end

local function crate(parent:Instance,frame:CFrame,dimension:Vector3)
    local x,y,z=dimension.X,dimension.Y,dimension.Z
    box(parent,"Crate",frame,dimension,V(0,y/2,0),palette.woodLight,mat.WoodPlanks,true)
    for _,sx in {-1,1} do
        for _,sz in {-1,1} do
            box(parent,"Crate Corner",frame,V(.20,y+.05,.22),V(sx*x*.46,y/2,sz*z*.46),palette.wood,mat.Wood)
        end
    end
    piece(parent,"Crate Brace",V(x*.72,.17,.085),frame*C(0,y*.54,-z*.51)*CFrame.Angles(0,0,math.pi/6),palette.wood,mat.Wood)
end

do
    local station=new("Folder","OasisWaterStation",landmarks)
    local frame=facePond(367,590)
    box(station,"Masonry Plinth",frame,V(21.6,1.35,15.25),V(0,.20,0),palette.ridge,mat.Sandstone,true)
    for i=0,6 do
        box(station,"Limestone Deck",frame,V(21.7,.53,2.18),V(0,1.05,-6.57+i*2.19),
            palette.limestone:Lerp(palette.cream,.18*(i%2)),mat.Sandstone,true)
    end
    for _,sx in {-1,1} do for _,sz in {-1,1} do
        local x,z=sx*9.1,sz*5.62
        box(station,"Column Foot",frame,V(1.35,.60,1.35),V(x,1.32,z),palette.cream,mat.Sandstone,true)
        shaft(station,"Cedar Post",frame:PointToWorldSpace(V(x,1.42,z)),frame:PointToWorldSpace(V(x,10.43,z)),.59,palette.woodLight,mat.Wood,true)
        shaft(station,"Rope Wrap",frame:PointToWorldSpace(V(x,9.53,z)),frame:PointToWorldSpace(V(x,9.76,z)),.72,palette.rope,mat.Fabric)
        local endX,endZ=x*1.12,z*1.20
        local endP=frame:PointToWorldSpace(V(endX,1.49,endZ))
        shaft(station,"Guy Rope",frame:PointToWorldSpace(V(x,9.64,z)),endP,.10,palette.rope,mat.Fabric)
    end end
    local stripColors={palette.cream,palette.cream,palette.lightTeal,palette.cream,palette.cream,palette.lightTeal,palette.cream,palette.cream,palette.lightTeal}
    for zi=0,5 do
        local z0,z1=-6.13+zi*2.03,-6.13+(zi+1)*2.03
        local y0,y1=8.72+.024*z0*z0,8.72+.024*z1*z1
        local along=V(0,y1-y0,z1-z0)
        local rot=CFrame.fromMatrix(V(0,(y0+y1)/2,(z0+z1)/2),Vector3.xAxis,along.Unit:Cross(Vector3.xAxis),along.Unit)
        for i,col in stripColors do
            piece(station,"Stitched Shade Canvas",V(2.23,.13,along.Magnitude+.08),
                frame*rot*C((i-5)*2.21,0,0),col,mat.Fabric)
        end
    end
    for _, sign in {-1,1} do
        box(station,"Canvas Hem",frame,V(20.1,.34,.18),V(0,9.58,sign*6.12),palette.limestone,mat.Fabric)
    end
    box(station,"Water Counter",frame,V(7.6,2.15,2.55),V(0,2.42,-2.88),palette.woodLight,mat.WoodPlanks,true)
    box(station,"Counter Cap",frame,V(8.0,.28,2.79),V(0,3.64,-2.89),palette.wood,mat.Wood,true)
    box(station,"Glazed Counter Panel",frame,V(7.21,1.65,.16),V(0,2.51,-4.14),palette.teal)
    jar(station,frame*C(-6.1,1.35,-1.68),2.08,palette.clay)
    jar(station,frame*C(-5.22,1.35,1.56),1.53,palette.teal)
    jar(station,frame*C(1.75,3.8,-2.73),1.04,palette.clay)
    crate(station,frame*C(6.8,1.35,2.8)*CFrame.Angles(0,-.18,0),V(2.4,2.01,1.91))
    crate(station,frame*C(6.6,3.37,2.79)*CFrame.Angles(0,.04,0),V(1.66,1.30,1.31))
    box(station,"Rest Bench",frame,V(5.5,.42,1.23),V(-1.4,2.55,4.6),palette.woodLight,mat.WoodPlanks,true)
    for _, x in {-3.35,.60} do
        box(station,"Bench Pedestal",frame,V(.51,1.12,.71),V(x,1.88,4.6),palette.ridge,mat.Sandstone)
    end
    for i=0,3 do
        local z=-7.5-i*1.58
        local p=frame:PointToWorldSpace(V(-.41,0,z))
        local base=point(p.X,p.Z)
        piece(station,"Shore Step",V(6.55,.64,1.7),C(base+Y*.24)*frame.Rotation,
            palette.cream:Lerp(palette.limestone,.15*(i%2)),mat.Sandstone,true)
    end
end

do
    local terrace=new("Folder","OldSpringTerrace",landmarks)
    local frame=facePond(403,660)
    for row=0,3 do
        for i=-2,2 do
            if (i+2+row)%7~=0 then
                local scale=if row%2==0 then 1 else .94
                piece(terrace,"Spring Wall Ashlar",V(2.52*scale,1.35,1.35),
                    frame*C(i*2.28+.20*(row%2),row*1.22+.29,3.42)*CFrame.Angles(0,.06*math.sin(i*row+1),0),
                    palette.ridge:Lerp(palette.limestone,.3+((i+row)%3)*.16),mat.Sandstone,true)
            end
        end
    end
    for _,sign in {-1,1} do
        for i=0,3 do
            local worldPoint=frame:PointToWorldSpace(V(sign*5.9,0,1.83-i*2.29))
            local p=point(worldPoint.X,worldPoint.Z)
            box(terrace,"Broken Retaining Wall",C(p)*frame.Rotation,V(1.35,1.45+.22*(i%2),2.55),
                V(0,.4,0),palette.limestone,mat.Sandstone,true)
        end
    end
    local basin=frame*C(0,.30,-1.18)
    box(terrace,"Spring Catchment",basin,V(6.4,.72,4.08),V(0,.49,0),palette.rock,mat.Sandstone,true)
    box(terrace,"Old Turquoise Tiles",basin,V(5.70,.13,3.36),V(0,.91,0),palette.teal)
    for _,side in {-1,1} do
        box(terrace,"Gutter Lip",basin,V(.70,.62,4.22),V(side*2.97,1.05,0),palette.cream,mat.Sandstone,true)
    end
    box(terrace,"Broken Water Spout",basin,V(1.25,1.08,1.91),V(0,2.14,1.31),palette.limestone,mat.Sandstone)
    jar(terrace,frame*C(7.4,-.09,.83),1.24,palette.clay)
    pilgrimMarker(402,635,-5,24,14)
end

do
    local shoreWalk = new("Folder","ShorePaths",landmarks)
    local pads = {
        {237,590},{243,594},{249,598},{255,604},{254,613},{250,620},
        {238,638},{237,650},{236,664},{239,674},{245,683},{248,694},
        {266,583},{274,580},{283,578},{291,577},{300,576},{309,578},
        {320,579},{330,578},{342,579},{350,581},{357,584},
        {378,595},{386,598},{392,603},{398,610},{401,621},{406,633},
    }
    for i,p in pads do
        local g=point(p[1],p[2])
        local orient=C(g+Y*.06)*CFrame.Angles(.025*math.sin(i),i*.57,.03*math.cos(i))
        local top = piece(shoreWalk,"Sunken Limestone Slab",V(2.8+i%3*.73,.33,1.8+i%4*.47),orient,
            palette.limestone:Lerp(palette.cream,.26+(i%5)*.075),mat.Sandstone,false)
        if i%4==1 then
            piece(shoreWalk,"Cracked Slab Edge",V(.51,.34,top.Size.Z*.83),orient*C(top.Size.X*.48,0,0)*CFrame.Angles(0,.18,0),
                palette.limestone,mat.Sandstone,false,"WedgePart")
        end
    end
end

do
    local landing=new("Folder","FisherLanding",landmarks)
    local frame=C(315,0,592)
    for i=0,4 do
        local z=-2.4+i*1.72
        local y=13.10-i*.57
        box(landing,"Landing Step",frame,V(5.30,.57,1.79),V(0,y,z),
            palette.limestone:Lerp(palette.cream,.16*(i%2)),mat.Sandstone,true)
    end
    local deckY=10.48
    for i=0,11 do
        local z=5.96+i*.98
        piece(landing,"Boardwalk Plank",V(5.54,.31,.95),
            frame*C(.045*math.sin(i*2),deckY,z)*CFrame.Angles(0,math.sin(i*1.6)*.013,0),
            palette.woodLight:Lerp(palette.wood,.15+.095*(i%5)),mat.WoodPlanks,true)
    end
    for _,s in {-1,1} do
        box(landing,"Boardwalk Beam",frame,V(.30,.68,11.99),V(s*2.34,deckY-.33,11.33),palette.wood,mat.Wood)
        for _,z in {6.13,11.33,16.56} do
            local pos=frame:PointToWorldSpace(V(s*2.43,deckY,z))
            local bottom=point(pos.X,pos.Z)
            shaft(landing,"Pilings",bottom-Y*.48,pos+Y*1.23,.52,palette.wood,mat.Wood)
            shaft(landing,"Mooring Rope Wrap",pos+Y*.69,pos+Y*.92,.65,palette.rope,mat.Fabric)
        end
    end
    crate(landing,frame*C(-1.42,10.65,5.96)*CFrame.Angles(0,.11,0),V(1.31,.74,.90))
    jar(landing,frame*C(2.05,10.68,15.66),.75,palette.clay)
end

do
    local skiff=new("Folder","ReedSkiff",landmarks)
    local x,z=249,646
    local p=surface(x,z,true).Position
    local frame=C(p+Y*.19)*CFrame.Angles(0,math.rad(47),math.rad(-1))
    local planks={.79,1.37,1.75,2.14,2.37,2.46,2.42,2.13,1.69,1.18}
    for i,w in planks do
        box(skiff,"Skiff Bottom Plank",frame,V(w,.24,.82),V(0,0,-3.76+(i-1)*.80),
            palette.woodLight:Lerp(palette.ochre,.12+.09*(i%3)),mat.WoodPlanks)
    end
    local ribs={{0,-4.57},{.94,-2.62},{1.32,-.85},{1.26,1.41},{.92,3.1},{.43,3.69}}
    for _,side in {-1,1} do
        for i=1,#ribs-1 do
            local a,b=ribs[i],ribs[i+1]
            local begin=frame:PointToWorldSpace(V(side*a[1],.66,a[2]))
            local finish=frame:PointToWorldSpace(V(side*b[1],.66,b[2]))
            local d=(finish-begin).Unit
            local sideCF=CFrame.fromMatrix((begin+finish)/2,d:Cross(Y),Y,-d)
            piece(skiff,"Skiff Wale",V(.23,.29,(finish-begin).Magnitude+.16),sideCF,palette.wood,mat.Wood)
            piece(skiff,"Skiff Side Plank",V(.25,.68,(finish-begin).Magnitude+.14),sideCF*C(0,-.31,0),
                palette.woodLight,mat.WoodPlanks)
        end
    end
    for _,zAt in {-1.76,.81,2.72} do
        box(skiff,"Cross Bench",frame,V(2.20,.21,.43),V(0,.47,zAt),palette.ochre,mat.Wood)
    end
    box(skiff,"Glazed Bow Peg",frame,V(.23,.47,.34),V(0,.88,-4.5),palette.teal)
    local tether=point(246.3,643.1)
    local bow=frame:PointToWorldSpace(V(0,.72,-4.47))
    shaft(skiff,"Mooring Rope",bow,tether+Y*.17,.095,palette.rope,mat.Fabric)
end

local function buried(id:string,name:string,x:number,z:number,size:number)
    local g=point(x,z)
    assert(surface(x,z,true).Material~=mat.Water,"Buried spot underwater")
    local location=new("Folder",name,excavation)
    local asset=storage.DuneBaronAssetLibrary.Finds.oase[id]:Clone() :: Model
    asset.Name="BuriedArt"
    for _, part in asset:GetDescendants() do
        if part:IsA("BasePart") then
            part.Anchored,part.CanCollide,part.CanQuery,part.CanTouch=true,false,false,false
        end
    end
    local boxAt,extent=asset:GetBoundingBox()
    asset:ScaleTo(asset:GetScale()*size/extent.Y)
    boxAt,extent=asset:GetBoundingBox()
    local unitTop=boxAt.Y+extent.Y/2
    local delta=V(x-boxAt.X,g.Y-1.28-unitTop,z-boxAt.Z)
    asset:PivotTo(asset:GetPivot()+delta)
    asset.Parent=location
    location:SetAttribute("ProbeX",x)
    location:SetAttribute("ProbeZ",z)
    location:SetAttribute("SurfaceY",g.Y)
    location:SetAttribute("HiddenTopY",g.Y-1.28)
    location:SetAttribute("PrototypeFindId",id)
    for i=1,3 do
        local a=i*2.2+.52
        local dx,dz=math.cos(a)*1.8,math.sin(a)*1.6
        local p=point(x+dx,z+dz)
        piece(location,"Exposed Pottery Shard",V(.49+i*.17,.24,.65),
            C(p+Y*.09)*CFrame.Angles(.10,a,.15),if i==2 then palette.lightTeal else palette.clay,
            mat.SmoothPlastic,false,"WedgePart")
    end
end
buried("oase_09","BuriedTwoHandledJar",248,586,2.32)
buried("oase_26","BuriedSpringMosaic",394,624,1.62)

for i,row in {{266,618},{326,640},{368,629},{379,681}} do
    local anchor=piece(weather,string.format("DrizzleVolume%02d",i),V(45,.25,40),C(row[1],48,row[2]),palette.cream)
    anchor.Transparency,anchor.CastShadow=1,false
    local e=new("ParticleEmitter","LightOasisRain",anchor) :: ParticleEmitter
    e.Enabled=false
    e.Rate=56
    e.Shape=Enum.ParticleEmitterShape.Box
    e.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume
    e.EmissionDirection=Enum.NormalId.Bottom
    e.Orientation=Enum.ParticleOrientation.VelocityParallel
    e.Texture="rbxasset://textures/particles/sparkles_main.dds"
    e.Speed=NumberRange.new(36,42)
    e.Lifetime=NumberRange.new(.75,.92)
    e.Acceleration=V(2,-16,-3)
    e.Color=ColorSequence.new(rgb(200,233,234))
    e.Squash=NumberSequence.new(-.78)
    e.Size=NumberSequence.new(.22)
    e.Transparency=NumberSequence.new(.46,.76)
end

terrain.WaterColor=rgb(41,151,143)
terrain.WaterTransparency=.36
terrain.WaterReflectance=.21
terrain.WaterWaveSize=.17

local parts=0
for _,x in art:GetDescendants() do if x:IsA("BasePart") then parts+=1 end end
art:SetAttribute("PalmCount",palmCount)
art:SetAttribute("PartCount",parts)
if old then old:Destroy() end
art.Parent=world
return {model=art:GetFullName(),palms=palmCount,parts=parts,buried=#excavation:GetChildren()}
