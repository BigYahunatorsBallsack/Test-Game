--!strict
-- Studio Edit only. Dress the salt basin with native geometry and existing find assets.
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Use Studio Edit mode")
assert(game.PlaceId==135831532782380,"Unexpected place")
local world=workspace:WaitForChild("DuneBaronWorld")
assert(world:GetAttribute("SaltLakeTerrainRevision")==1,"Build Salt Lake terrain first")
local storage=game:GetService("ServerStorage")
local owner="DuneBaronSaltLakeArt"
local prior=world:FindFirstChild("SaltLakeArtV1")
local archive="DuneBaronSaltLakeBeforeDressing"
assert(not prior or prior:GetAttribute("Owner")==owner,"Salt Lake art name occupied")
assert(not prior or not storage:FindFirstChild(archive),"Prior Salt Lake art archive already exists")
local terrain=workspace.Terrain
local geometry=game:GetService("GeometryService")
local sources=storage.DuneBaronAssetLibrary.Finds.salzsee
local V,C,rgb=Vector3.new,CFrame.new,Color3.fromRGB
local Y=Vector3.yAxis
local r=Random.new(30177)
local cx,cz,rx,rz=1381,871,145,99
local level=world:GetAttribute("SaltLakeWaterLine") :: number
local mat=Enum.Material
local cream,ivory,wetSalt=rgb(234,223,198),rgb(244,239,221),rgb(197,206,191)
local weathered,lightWood,woodShade=rgb(122,85,54),rgb(156,113,70),rgb(89,60,43)
local copper,rope,teal=rgb(110,84,63),rgb(181,143,95),rgb(51,119,123)
local fossilsColor=rgb(174,145,110)

local function folder(name: string,parent: Instance?): Folder
    local f=Instance.new("Folder")
    f.Name,f.Parent=name,parent
    return f
end

local pack=folder("SaltLakeArtV1")
pack:SetAttribute("Owner",owner)
pack:SetAttribute("ZoneId","salt_lake")
local landmarks=folder("Landmarks",pack)
local crust=folder("SaltCrust",pack)
local crystals=folder("CrystalBeds",pack)
local deposits=folder("BuriedFinds",pack)
local fog=folder("WaterMist",pack)
local props=folder("ShoreDetails",pack)
local terrainOnly=RaycastParams.new()
terrainOnly.FilterType=Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances={terrain}
terrainOnly.IgnoreWater=true

local function ground(x: number,z: number): RaycastResult
    return assert(workspace:Raycast(V(x,185,z),V(0,-244,0),terrainOnly),"Salt lake ground missing")
end

local function atGround(x: number,z: number,dx: number,dz: number): CFrame
    local g=ground(x,z).Position
    return CFrame.lookAt(g,g+V(dx,0,dz))
end

local function panel(parent: Instance?,name: string,cf: CFrame,size: Vector3,color: Color3,material: Enum.Material,solid: boolean?): Part
    local p=Instance.new("Part")
    p.Name,p.Size,p.CFrame,p.Color,p.Material=name,size,cf,color,material
    p.Anchored,p.CanCollide,p.CanQuery,p.CanTouch=true,solid==true,solid==true,false
    p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    p.Parent=parent
    return p
end

local function spar(parent: Instance,name: string,a: Vector3,b: Vector3,section: Vector2,color: Color3,
        material: Enum.Material,round: boolean?,solid: boolean?): BasePart
    local axis=(b-a).Unit
    local ref=if math.abs(axis.Y)<.91 then Y else Vector3.zAxis
    local up=(ref-axis:Dot(ref)*axis).Unit
    local beam=panel(parent,name,CFrame.fromMatrix((a+b)/2,axis,up),
        V((b-a).Magnitude,section.X,section.Y),color,material,solid)
    if round then beam.Shape=Enum.PartType.Cylinder end
    return beam
end

local function saltPlatePrototype(narrow: number): BasePart
    local main=panel(nil,"Salt Blank",C(),V(8,.56,5.8),cream,mat.Limestone)
    local width=(4+2.9-narrow)*math.sqrt(2)
    local chamfer=panel(nil,"Edge Chamfer",CFrame.Angles(0,math.pi/4,0),V(width,1.9,width),cream,mat.Limestone)
    local okay,result=pcall(function() return geometry:IntersectAsync(main,{chamfer},{SplitApart=false}) end)
    chamfer:Destroy()
    if okay and #result==1 then
        main:Destroy()
        local plate=result[1]
        plate.Anchored,plate.CanCollide,plate.CanQuery,plate.CanTouch=true,false,false,false
        if plate:IsA("PartOperation") then plate.UsePartColor=true end
        return plate
    end
    if okay then for _,shape in result do shape:Destroy() end end
    main.Shape=Enum.PartType.Cylinder
    return main
end

local tileShapes={saltPlatePrototype(1.10),saltPlatePrototype(1.85)}
local function plate(x: number,z: number,w: number,d: number,t: number,rot: number,c: Color3)
    local sample=ground(x,z)
    if sample.Normal.Y<.86 or sample.Position.Y<level-.60 then return end
    local cap=tileShapes[r:NextInteger(1,2)]:Clone()
    local cf=C(sample.Position-Y*t*.16)*CFrame.Angles(r:NextNumber(-.025,.025),rot,r:NextNumber(-.035,.035))
    cap.Name,cap.Color,cap.Material="Fractured Salt Slab",c,mat.Limestone
    if cap:IsA("Part") and cap.Shape==Enum.PartType.Cylinder then
        cap.Size,cap.CFrame=V(t,w,d),cf*CFrame.Angles(0,0,math.pi/2)
    else
        cap.Size,cap.CFrame=V(w,t,d),cf
    end
    cap.Parent=crust
end

-- Offset shore polygons leave narrow, irregular seams between the slabs.
for i=0,53 do
    local a=i*math.pi*2/54
    local distance=1+.063*math.sin(a*3-.60)+.047*math.cos(a*7+.30)
    for j=1,3 do
        local angle=a+r:NextNumber(-.028,.028)
        local s=distance+r:NextNumber(.033,.155)+j*.022
        local x,z=cx+s*rx*math.cos(angle),cz+s*rz*math.sin(angle)
        plate(x,z,r:NextNumber(3.1,9.4),r:NextNumber(2.25,6.7),r:NextNumber(.30,.69),
            angle+r:NextNumber(-.6,.6),ivory:Lerp(wetSalt,r:NextNumber(.05,.42)))
    end
end
for _,island in {{1309,841},{1438,846},{1398,918},{1473,912}} do
    for i=1,13 do
        local a=i*2.399963
        local reach=math.sqrt(i)*1.8
        plate(island[1]+math.cos(a)*reach*1.6,island[2]+math.sin(a)*reach,
            r:NextNumber(4,10),r:NextNumber(3,7),r:NextNumber(.31,.63),a,ivory:Lerp(cream,r:NextNumber(0,.35)))
    end
end

local function cloneFind(id: string): Model
    local model=sources:FindFirstChild(id)
    assert(model and model:IsA("Model") and model:GetAttribute("FindId")==id)
    return model:Clone()
end

local function settle(model: Model,x: number,z: number,yaw: number,grade: number,placeTop: boolean)
    model:PivotTo(C(x,0,z)*CFrame.Angles(0,yaw,0))
    local bounds,size=model:GetBoundingBox()
    local surface=bounds.Position.Y+size.Y/2*(if placeTop then 1 else -1)
    model:PivotTo(model:GetPivot()+Y*(grade-surface))
end

local function crystalBed(x: number,z: number,multiplier: number,index: number)
    local hit=ground(x,z)
    if hit.Normal.Y<.73 or hit.Position.Y<level-.38 then return end
    local model=cloneFind(if index%3==0 then "salzsee_09" else "salzsee_02")
    model.Name="Milky Salt Crystal Cluster"
    model:ScaleTo(model:GetScale()*multiplier)
    settle(model,x,z,index*2.399963,hit.Position.Y-.48,false)
    for _,d in model:GetDescendants() do
        if d:IsA("LuaSourceContainer") or d:IsA("SurfaceAppearance") or d:IsA("Decal") then
            d:Destroy()
        elseif d:IsA("BasePart") then
            d.Anchored,d.CanCollide,d.CanTouch,d.CanQuery=true,false,false,false
            d.Material=mat.SmoothPlastic
            d.Color=rgb(132,211,208):Lerp(rgb(197,218,202),.11+(index%5)*.115)
            d.Reflectance=.036
            if d:IsA("MeshPart") then d.TextureID="" end
        end
    end
    model.Parent=crystals
end

local locations={
    {1279,798,2.30},{1313,815,3.50},{1363,780,2.85},{1394,771,2.25},{1461,798,2.15},
    {1496,820,3.0},{1531,889,2.67},{1512,929,2.95},{1433,962,2.23},{1392,986,2.72},
    {1343,984,3.18},{1311,971,2.5},{1275,952,3.15},{1257,925,2.48},{1240,875,2.28},
    {1309,841,3.9},{1438,846,3.4},{1398,918,3.8},{1473,912,3.0},
}
for i,v in locations do
    crystalBed(v[1],v[2],v[3],i)
    crystalBed(v[1]+r:NextNumber(-7,-2),v[2]+r:NextNumber(1.2,4.8),.8+v[3]*.22,i+41)
end

-- Old mooring ribs and a broken hull form the focus of the western bay.
do
    local wreck=folder("Wrackbucht",landmarks)
    local at=atGround(1284,786,-.60,-1)
    local function point(v: Vector3): Vector3 return at:PointToWorldSpace(v) end
    panel(wreck,"Partially Buried Keel",at*C(0,-.42,.1)*CFrame.Angles(.02,.03,.07),
        V(1.31,1.85,25.1),woodShade,mat.WoodPlanks,true)
    for rib=1,5 do
        local z=(rib-3)*5
        local width=4.00+(if rib==2 or rib==3 then 1.10 else 0)
        local endAngle=if rib==1 then .93 elseif rib==5 then 1.16 else 1.36
        local curve={}
        for j=0,10 do
            local t=(j/10-.5)*2*endAngle
            curve[j+1]=V(math.sin(t)*width,-.64+(1-math.cos(t))*6.90,z+.22*math.sin(t*1.8))
        end
        local wood=weathered:Lerp(lightWood,rib*.064)
        for j=1,#curve-1 do
            local a,b=point(curve[j]),point(curve[j+1])
            local u=(b-a).Unit
            spar(wreck,"Broken Oak Rib",a-u*.085,b+u*.085,Vector2.new(.76,1.13),wood,mat.Wood)
            if j%3==1 then
                local spot=(a+b)/2+at.LookVector*.62
                spar(wreck,"Iron Rivet",spot-at.LookVector*.09,spot+at.LookVector*.10,Vector2.new(.24,.24),copper,mat.CorrodedMetal,true)
            end
        end
    end
    for _,sign in {-1,1} do
        for j=1,4 do
            local length=(17.4-j)*(.93+sign*.07)
            local baseX=sign*(2.64+j*.44)
            local plank=at*C(baseX,.14+j*.52,-.98+math.sin(j)*1.1)*CFrame.Angles(.055*sign,sign*.04,sign*.16)
            panel(wreck,"Split Hull Strake",plank,V(.47,.68,length),weathered:Lerp(woodShade,j*.103),mat.WoodPlanks)
        end
    end
    for i=1,7 do
        local anchor=point(V(r:NextNumber(-8.6,8.4),0,r:NextNumber(-14.5,14.1)))
        local g=ground(anchor.X,anchor.Z).Position
        panel(wreck,"Loose Weathered Board",C(g-Y*.016)*CFrame.Angles(.08,r:NextNumber(-1.7,2.4),.08),
            V(.62+r:NextNumber(0,.7),.27,2.5+r:NextNumber(.4,2.8)),weathered:Lerp(cream,.12),mat.WoodPlanks)
    end
end

local function tiedPosts(parent: Instance,cf: CFrame,points: {Vector3})
    local tops: {Vector3}={}
    for _,loc in points do
        local v=cf:PointToWorldSpace(loc)
        local foot=ground(v.X,v.Z).Position
        local top=foot+Y*(2.05+loc.Y)
        spar(parent,"Old Rope Post",foot-Y*.23,top,Vector2.new(.65,.65),weathered,mat.Wood,true)
        table.insert(tops,top-Y*.39)
    end
    for i=1,#tops-1 do
        local a,b=tops[i],tops[i+1]
        local last=a
        for k=1,5 do
            local t=k/5
            local nextPoint=a:Lerp(b,t)-Y*(.34*math.sin(math.pi*t))
            spar(parent,"Salt-Stained Rope",last,nextPoint,Vector2.new(.116,.116),rope,mat.Fabric,true)
            last=nextPoint
        end
    end
end

-- Open shoreline workshop. The trail runs behind it.
do
    local station=folder("Solemessstation",landmarks)
    local at=atGround(1250,764,1,.33)
    for i=0,8 do
        panel(station,"Deck Board",at*C(0,.53,(i-4)*1.19),V(14.8,.57,1.16),
            weathered:Lerp(lightWood,.13+(i%3)*.12),mat.WoodPlanks,true)
    end
    for _,x in {-6.3,6.3} do
        for _,z in {-4.5,4.5} do
            local h=if z<0 then 8.1 else 6.55
            local p=at:PointToWorldSpace(V(x,0,z))
            local g=ground(p.X,p.Z).Position
            local roof=at:PointToWorldSpace(V(x,h,z))
            spar(station,"Canopy Timber",g-Y*.33,roof,Vector2.new(.60,.60),woodShade,mat.Wood,true)
            spar(station,"Lashing",roof-Y*.85,roof-Y*.4,Vector2.new(.72,.72),rope,mat.Fabric,true)
        end
    end
    for i=0,6 do
        local x=(i-3)*2.12
        local color=if i==1 or i==5 then teal else cream:Lerp(lightWood,(i%3)*.022)
        panel(station,"Salt Canvas",at*C(x,7.45,0)*CFrame.Angles(.17,0,0),V(2.17,.16,10.2),color,mat.Fabric)
        panel(station,"Hem",at*C(x,8.08,-5.08),V(2.15,.66,.13),color,mat.Fabric)
    end
    local desk=at*C(-3.48,2.09,-.36)
    panel(station,"Sample Bench",desk,V(4.6,.34,2.2),lightWood,mat.WoodPlanks,true)
    for _,x in {-1.58,1.58} do
        panel(station,"Desk Supports",desk*C(x,-.73,0),V(.5,1.4,1.5),woodShade,mat.Wood,true)
    end
    for i=1,3 do
        local a=desk:PointToWorldSpace(V(-1.5+i*.70,.18,.20))
        spar(station,"Brine Sample Cup",a,a+Y*.68,Vector2.new(.46,.46),
            if i==2 then teal else copper,mat.SmoothPlastic,true)
    end
    for i,v in {{2.4,1.77,2.7},{4.6,1.75,2.8},{2.72,1.64,.55},{4.7,2.85,2.5}} do
        local box=at*C(table.unpack(v))*CFrame.Angles(0,.14*i,0)
        panel(station,"Salt Sample Crate",box,V(1.84,1.48,1.53),weathered:Lerp(lightWood,.31),mat.WoodPlanks)
        for _,side in {-1,1} do
            panel(station,"Crate Strapping",box*C(side*.61,0,-.79),V(.19,1.50,.11),woodShade,mat.Wood)
        end
    end
    tiedPosts(station,at,{V(7.7,0,-5.3),V(10.2,.03,-1.5),V(14.3,0,.68),V(18.9,.24,1.2)})
end

-- Low saltworks buttresses and old docking stakes give the far shore landmarks.
do
    local works=folder("Alte Salzwaage",landmarks)
    local at=atGround(1478,984,.08,-1)
    local stone=cream:Lerp(copper,.32)
    for i=1,6 do
        local x=(i-3.5)*3.54
        local p=at:PointToWorldSpace(V(x,0,2.8))
        local g=ground(p.X,p.Z).Position
        panel(works,"Exposed Saltworks Foundation",C(g+Y*.34)*at.Rotation,V(3.63,1.54,3.37),
            cream:Lerp(fossilsColor,.37+i*.048),mat.Limestone,true)
        if i%3~=0 then
            panel(works,"Upper Saltworks Stone",C(g+Y*1.43)*at.Rotation,V(3.44,.91,3.02),
                cream:Lerp(wetSalt,.24),mat.Limestone,true)
        end
    end
    for _,side in {-1,1} do
        local x=side*6.25
        for i=1,if side<0 then 4 else 3 do
            local size=V(3.38-.18*i,1.24,3.18-.17*i)
            panel(works,"Saltworks Pier Course",at*C(x+side*.11*i,i*1.13-.46,2.8)
                *CFrame.Angles(0,side*.035*i,0),size,stone:Lerp(cream,i*.085),mat.Limestone,true)
        end
    end
    panel(works,"Scale Plinth",at*C(-.4,.52,.62),V(4.6,1.65,3.26),stone,mat.Limestone,true)
    panel(works,"Scale Timber",at*C(-.4,3.32,.62),V(.72,4.57,.88),woodShade,mat.Wood,true)
    local lever=at*C(-.4,5.36,.62)*CFrame.Angles(0,0,-.20)
    panel(works,"Uneven Weighing Beam",lever,V(6.66,.47,.48),lightWood,mat.Wood,true)
    for _,side in {-1,1} do
        local hook=lever:PointToWorldSpace(V(side*2.92,-.23,0))
        local pan=hook-Y*2.25
        for _,z in {-.74,.74} do
            spar(works,"Scale Rope",hook,pan+Vector3.zAxis*z,Vector2.new(.075,.075),rope,mat.Fabric,true)
        end
        spar(works,"Weathered Copper Pan",pan-Y*.13,pan+Y*.13,Vector2.new(2.16,2.16),
            if side<0 then teal:Lerp(copper,.46) else copper,mat.CorrodedMetal,true)
    end
    panel(works,"Broken Pier Coping",at*C(7.66,.74,-.05)*CFrame.Angles(.09,.37,.18),
        V(3.6,1.13,2.44),stone,mat.Limestone,true)
    tiedPosts(works,at,{V(-12,0,-1.9),V(-6,.12,-2.75),V(.64,.2,-3.65),V(7.95,0,-2.9)})
end

local waymarkers={
    {1154,813},{1181,802},{1214,789},{1231,777},{1300,764},{1330,749},{1402,747},{1456,763},
    {1492,784},{1546,786},{1574,805},{1615,799},{1654,815},{1680,820},
    {1185,852},{1195,897},{1220,945},{1262,974},{1323,993},{1403,1004},{1518,984},{1573,941},
}
for i,v in waymarkers do
    local g=ground(v[1],v[2])
    if g.Normal.Y>.82 then
        local tall=if i%5==1 then 3.95 else 2.25
        local cf=C(g.Position+Y*(tall*.37))*CFrame.Angles(.02,r:NextNumber(-1.65,.71),-.055)
        panel(props,"Salt-Worn Trail Cairn",cf,V(1.75,tall,1.76),cream:Lerp(fossilsColor,.35),mat.Limestone)
        panel(props,"Cairn Coral Inlay",cf*C(0,tall*.26,-.92),V(.84,.37,.12),teal:Lerp(wetSalt,(i%4)*.09),mat.Slate)
    end
end

local function bury(id: string,site: string,x: number,z: number,yaw: number)
    local height=ground(x,z).Position.Y
    local model=cloneFind(id)
    model.Name=site
    settle(model,x,z,yaw,height-1.5,true)
    model:SetAttribute("ArtBurial",true)
    model:SetAttribute("SurfaceY",height)
    for _,d in model:GetDescendants() do
        if d:IsA("LuaSourceContainer") then d:Destroy()
        elseif d:IsA("BasePart") then d.Anchored,d.CanCollide,d.CanTouch=true,false,false end
    end
    model.Parent=deposits
    for i=1,3 do
        local t=i*2.399963
        plate(x+math.cos(t)*2.0,z+math.sin(t)*2.4,1.22+i*.16,1.39,.275,t,cream:Lerp(wetSalt,.22))
    end
end

-- Choose dry marginals with enough cover to expose the art from the shore.
bury("salzsee_15","Verschüttetes Ankerstück",1273,792,-.32)
bury("salzsee_09","Verschütteter Salzfächer",1357,757,.45)
bury("salzsee_27","Verschütteter Muschelanhänger",1434,983,1.12)
bury("salzsee_29","Verschüttetes Salzsiegel",1499,993,-.30)
for _,p in tileShapes do p:Destroy() end

-- A light local mist layer. The dune lighting and Oasis water stay shared.
for i,entry in {
    {1340,858,36,15},{1371,825,40,11},{1404,875,52,24},
    {1445,884,43,24},{1433,939,44,11},{1476,858,34,19},
} do
    local plate=panel(fog,"Mist Volume",C(entry[1],level+.34,entry[2]),
        V(entry[3],.35,entry[4]),ivory,mat.SmoothPlastic)
    plate.Transparency=1
    local emitter=Instance.new("ParticleEmitter")
    emitter.Name="Low Brine Haze"
    emitter.Texture="rbxasset://textures/particles/smoke_main.dds"
    emitter.Shape=Enum.ParticleEmitterShape.Box
    emitter.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume
    emitter.Orientation=Enum.ParticleOrientation.FacingCameraWorldUp
    emitter.EmissionDirection=Enum.NormalId.Right
    emitter.Lifetime=NumberRange.new(7,13)
    emitter.Rate=1.05+(i%3)*.18
    emitter.Speed=NumberRange.new(.22,.66)
    emitter.LightInfluence=.24
    emitter.Color=ColorSequence.new(rgb(225,237,234))
    emitter.SpreadAngle=Vector2.new(4,12)
    emitter.Size=NumberSequence.new({
        NumberSequenceKeypoint.new(0,8),NumberSequenceKeypoint.new(.54,13),
        NumberSequenceKeypoint.new(1,17),
    })
    emitter.Transparency=NumberSequence.new({
        NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.29,.867),
        NumberSequenceKeypoint.new(.77,.908),NumberSequenceKeypoint.new(1,1),
    })
    emitter.Parent=plate
end

if prior then
    prior.Name=archive
    prior.Parent=storage
end
pack.Parent=world
return {path=pack:GetFullName(),landmarks=#landmarks:GetChildren(),slabs=#crust:GetChildren(),
    finds=#deposits:GetChildren(),crystals=#crystals:GetChildren()}
