-- Studio command only. Places distant landmarks on the V3 dune surface.
assert(game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
    "Run the Dünenmeer art tool in Studio Edit mode")
assert(game.PlaceId == 135831532782380, "Unexpected place")
local world = workspace.DuneBaronWorld
assert(world:GetAttribute("DunesTerrainRevision") == 3, "V3 terrain must be in place")
local existing = world:FindFirstChild("ArtV3")
assert(not existing or existing:GetAttribute("Owner") == "DuneBaronArtV3", "ArtV3 name collision")

local V, C = Vector3, CFrame
local rgb = Color3.fromRGB
local colors = {
    limestone = rgb(229,182,117), sand = rgb(209,160,99), warm = rgb(190,132,77),
    terracotta = rgb(174,103,68), dark = rgb(137,93,66), wood = rgb(108,74,50),
    teal = rgb(47,110,112), pale = rgb(227,198,133),
}
local rays = RaycastParams.new()
rays.FilterType = Enum.RaycastFilterType.Include
rays.FilterDescendantsInstances = {workspace.Terrain}

local function ground(x, z)
    local h = workspace:Raycast(V.new(x,115,z), V.new(0,-140,0), rays)
    assert(h and h.Material == Enum.Material.Sand, "Expected sand at landmark")
    return h.Position.Y
end

local function make(class, name, parent)
    local child = Instance.new(class)
    child.Name = name
    child.Parent = parent
    return child
end

local root = make("Folder", "ArtV3", nil)
root:SetAttribute("Owner", "DuneBaronArtV3")

local function block(parent, name, size, cf, color, class, surface, solid)
    local p = make(class or "Part", name, parent)
    p.Size = size
    p.CFrame = cf
    p.Color = colors[color]
    p.Material = surface or Enum.Material.Sandstone
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Anchored = true
    p.CanCollide = solid == true
    p.CanQuery = solid == true
    p.CanTouch = false
    return p
end

local function box(parent, name, sx, sy, sz, cf, color, class, surface, solid)
    return block(parent, name, V.new(sx,sy,sz), cf, color, class, surface, solid)
end

local function flags(parent, x, z, h, turn, clay)
    local y = ground(x,z)
    local cf = C.new(x,y,z) * C.Angles(0,math.rad(turn),0)
    box(parent, "Buried Socket", 1,.42,.86, cf*C.new(0,.07,0), "sand")
    box(parent, "Caravan Pole", .17,h,.19, cf*C.new(0,h/2-.07,0), "wood", nil, Enum.Material.Wood)
    box(parent, "Faded Caravan Banner", 1.85,.71,.08, cf*C.new(1.01,h-.62,0)*C.Angles(0,0,math.rad(-6)),
        if clay then "terracotta" else "teal", nil, Enum.Material.Fabric)
    box(parent, "Woven Border", 1.83,.115,.085, cf*C.new(.985,h-.90,-.022)*C.Angles(0,0,math.rad(-6)),
        "pale", nil, Enum.Material.Fabric)
end

local function waystone(parent,x,z,h,turn)
    local cf = C.new(x,ground(x,z),z)*C.Angles(0,math.rad(turn),0)
    box(parent,"Set Foundation",1.63,.36,1.16,cf*C.new(0,.11,0),"sand")
    box(parent,"Waystone",1.05,h,.69,cf*C.new(0,h/2-.05,0),"limestone")
    box(parent,"Split Cap",1.08,.32,.72,cf*C.new(-.14,h-.12,0)*C.Angles(0,0,.15),"warm","WedgePart")
    box(parent,"Glazed Marker",.43,.43,.081,cf*C.new(0,h*.57,-.375)*C.Angles(0,0,math.rad(45)),"teal")
end

local function shale(parent,x,z,width,height,depth,turn)
    local y = ground(x,z)
    local cf = C.new(x,y,z)*C.Angles(0,math.rad(turn),0)
    box(parent,"Buried Bedrock",width*.94,height*.56,depth,cf*C.new(0,height*.02,0),"warm")
    box(parent,"Fractured Face",width,height*.83,depth*.86,cf*C.new(.13,height*.20,.01),"sand","WedgePart")
    box(parent,"Broken Layer",width*.52,height*.62,depth*.63,cf*C.new(-width*.27,.13,-depth*.24)*C.Angles(0,1.01,0),
        "terracotta","CornerWedgePart")
end

local trail = make("Folder","CaravanRoute",root)
for i,p in {{36,147},{41,179},{52,210},{62,242},{71,290},{75,326},{92,360},{104,391}} do
    waystone(trail,p[1],p[2],if i%3==1 then 2.95 else 2.1,(i%5-2)*12)
end
for _,p in {{52,210,4.8,9,false},{80,325,4.3,36,true},{108,397,4.6,17,false}} do
    flags(trail,table.unpack(p))
end

-- An abandoned caravan shelter sits at the first saddle beyond the old gate.
local shelter = make("Model","ForgottenCaravanShelter",root)
local sx,sz = 67,263
local y = ground(sx,sz)
local cf = C.new(sx,y,sz)*C.Angles(0,math.rad(-14),0)
shelter:SetAttribute("ProbeX", sx)
shelter:SetAttribute("ProbeZ", sz)
shelter:SetAttribute("SurfaceY", y)
shelter:SetAttribute("HiddenTopY", y-.92)
local buried = make("Folder","BuriedStone",shelter)
box(buried,"Caravan Inlay Floor",7.5,.44,5.2,cf*C.new(0,-1.33,0),"limestone")
for i=-2,2 do
    box(buried,"Diamond Tile",.86,.083,.86,cf*C.new(i*1.18,-.967,0)*C.Angles(0,math.rad(45),0),
        if i==0 then "pale" else "teal")
end
for side=-1,1,2 do
    local x = side*6.3
    box(shelter,"Outer Pier Pad",3.09,.68,2.90,cf*C.new(x,.12,1.75),"warm")
    for row=1,5 do
        local cx=x+.11*math.sin(row*2)
        box(shelter,"Weathered Pier Course",1.95,.79,2.15,
            cf*C.new(cx,.35+.76*row,1.74)*C.Angles(0,0,.016*(row-2)),
            if row%3==0 then "warm" else "limestone")
    end
    box(shelter,"Burnished Band",1.98,.19,2.22,cf*C.new(x,3.2,1.70),"terracotta")
    box(shelter,"Glazed Cap Tile",.69,.30,.115,cf*C.new(x,3.52,.623),"teal")
    box(shelter,"Pier Cornice",2.72,.48,2.62,cf*C.new(x,4.49,1.75),"sand")
end
for tier=1,3 do
    for i=0,6 do
        if (tier==1 or i<5) and not (tier==3 and i==3) then
            box(shelter,"Crumbled Windbreak",1.68,.57,1.18,
                cf*C.new(-5.39+i*1.68-(tier%2)*.22,.62*tier,3.25)*C.Angles(0,.019*math.sin(i+tier),.036*math.sin(tier*i)),
                if (tier+i)%4==0 then "warm" else "sand")
        end
    end
end
box(shelter,"Broken Lintel",3.9,.62,2.3,cf*C.new(-5.42,4.91,1.74)*C.Angles(0,0,-.18),"limestone")
box(shelter,"Fallen Roof Panel",4.1,1.1,1.72,cf*C.new(3.65,.38,-3.2)*C.Angles(0,.6,.12),"warm","WedgePart")
for _,q in {{58,259,2.9,1.3,2.2,-36},{64,269,1.7,.73,1.4,23},{74,260,2.2,.85,1.5,18},{73,273,2.8,1.22,1.91,46}} do
    shale(shelter,table.unpack(q))
end
flags(shelter,60,255,4.6,-18,true)

-- A low signal tower marks the deeper route without filling the horizon.
local tower = make("Model","DesertSignalTower",root)
local tx,tz = 107,398
local ty = ground(tx,tz)
local tc = C.new(tx,ty,tz)*C.Angles(0,math.rad(15),0)
box(tower,"Buried Watchtower Footing",9.34,.88,8.83,tc*C.new(0,.15,0),"warm")
for row=1,8 do
    local hh=.48+row*.96
    local w=8.6-row*.31
    for _,side in {-1,1} do
        box(tower,"Load Bearing Course",.76,.92,w,
            tc*C.new(side*w/2,hh,.07*math.sin(row)),"sand",nil,nil,true)
        if side==1 or row<=5 then
            for col=1,4 do
                -- A gap survives in the front of the tower.
                if side==1 or row<3 or (col~=2 and col~=3) then
                    box(tower,"Broken Tower Masonry",w/4+.015,.93,.80,
                        tc*C.new((col-2.5)*w/4,hh,side*w/2)*C.Angles(0,.018*math.sin(row*col),0),
                        if (row+col)%3==0 then "warm" else "limestone")
                end
            end
        end
    end
end
box(tower,"Staggered Crown",6.76,.57,2.22,tc*C.new(0,8.53,1.96),"warm")
box(tower,"Teal Signal Band",5.78,.28,.13,tc*C.new(0,8.61,.786),"teal")
for _,q in {{101,402,3.8,1.23,2.8,-22},{112,393,2.2,.94,2,12},{116,398,2.6,1.2,1.9,51}} do
    shale(tower,table.unpack(q))
end

-- Low, sparse rock ribs and isolated wind markers give scale to an open landscape.
local rocks = make("Folder","DuneOutcrops",root)
for _,v in {{-71,129,11,4.4,7.1,17},{92,127,9.8,3.7,6.9,-24},{137,223,12,4.5,6.6,42},
    {-122,175,14,4.9,9.1,-15},{-191,216,11,3.24,8.6,35},{241,58,12,4.7,6.2,25},
    {258,73,7.2,3.2,5.1,39},{271,91,4.7,2.38,3.6,74},{147,470,7.9,3.63,7.5,81}} do
    shale(rocks,table.unpack(v))
end
for _,q in {{241,51,2.10,-19},{275,96,2.28,45},{154,465,2.55,10}} do
    waystone(rocks,table.unpack(q))
end

if existing then existing:Destroy() end
root.Parent=world
local count=0
for _,p in root:GetDescendants() do if p:IsA("BasePart") then count+=1 end end
return {world=root:GetFullName(),parts=count,sites={shelter:GetFullName(),tower:GetFullName()},shelterSurface=y}
