--!strict
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Catalog = require(script.Parent.Catalog) :: any
local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)
type Swatch = Theme.Swatch

local rgb, dimensions, offset = Color3.fromRGB, UDim2.new, UDim2.fromOffset
local C = {
    sub=rgb(220,235,233), gold=rgb(255,222,108), tealLight=rgb(146,255,225),
    danger=rgb(250,109,74),
}
local tools = {
    {"hand","Hand","hand"}, {"shovel","Schaufel","shovel"}, {"bucket_chain","Eimerkette","bucket_chain"},
    {"mini_digger","Mini-Bagger","excavator"}, {"vacuum_robot","Saugroboter","suction_robot"},
    {"mega_machine","Harvester","harvester"},
}
local shortToolNames = {"Hand","Schaufel","Kette","Bagger","Sauger","Harvester"}
local zones = {
    {"duenenmeer","Dünenmeer"}, {"oase","Oase"}, {"canyon","Canyon"}, {"salzsee","Salzsee"}, {"ruinenstadt","Ruinenstadt"},
}
local referenceSections = {
    {name="Kisten", color=Theme.gold, items={{"Holzkiste","crates_wood"},{"Eisenkiste","crates_iron"},{"Goldkiste","crates_gold"},{"Event-Kiste","crates_event"}},
        tileColors={Theme.clay,Theme.slate,Theme.gold,Theme.teal}},
    {name="Tank", color=Theme.teal, items={{"Eimer","node_storage_bucket"},{"Tank","node_storage_tank"},{"Rucksack","node_storage_backpack"},{"Fass","node_storage_barrel"}}},
    {name="Verkauf", color=Theme.clay, items={{"Münzen","node_selling_coins"},{"Waage","node_selling_scales"},{"Marktstand","node_selling_stall"},{"Preisschild","node_selling_price_tag"}}},
    {name="Glück", color=Theme.finds.uncommon, items={{"Lupe","node_luck_magnifier"},{"Klee","node_luck_clover"},{"Stern","node_luck_star"},{"Kompass","node_luck_compass"}}},
    {name="Währungen", color=Theme.finds.epic, items={{"Münzen","currency_coin"},{"Edelsteine","currency_gem"},{"Sand","currency_sand"},{"Windkristall","currency_wind_crystal"}}},
}
local rarity: {[string]: string} = {
    common="Gewöhnlich",uncommon="Ungewöhnlich",rare="Selten",epic="Episch",legendary="Legendär",mythic="Mythisch",
}
local barTiming = TweenInfo.new(.15,Enum.EasingStyle.Quad)
local toastTiming = TweenInfo.new(.22,Enum.EasingStyle.Sine)
local View = {}

local function create(class: string,name: string,parent: Instance): any
    local item = Instance.new(class)
    item.Name,item.Parent = name,parent
    return item
end

local function round(item: GuiObject,radius: number)
    create("UICorner","Corners",item).CornerRadius = UDim.new(0,radius)
end

local function frame(parent: Instance,name: string,color: Color3?,size: UDim2,pos: UDim2?): Frame
    local f = create("Frame",name,parent)
    f.Size,f.Position = size,pos or offset(0,0)
    f.BorderSizePixel = 0
    f.BackgroundTransparency = if color then 0 else 1
    if color then f.BackgroundColor3 = color end
    return f
end

local function label(parent: Instance,name: string,value: string,size: UDim2,pos: UDim2,fontSize: number,bold: boolean?,center: boolean?): TextLabel
    local l = create("TextLabel",name,parent)
    l.Size,l.Position = size,pos
    l.BackgroundTransparency = 1
    l.Text,l.TextSize,l.TextColor3 = value,fontSize,Theme.text
    l.Font = Enum.Font.BuilderSansMedium
    if bold then Theme.Lettering(l, math.clamp(fontSize / 10, 1, 3)) end
    l.TextXAlignment = if center then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    return l
end

local function button(parent: Instance,name: string,value: string,size: UDim2,pos: UDim2,swatch: Swatch): TextButton
    local b = create("TextButton",name,parent)
    b.Size,b.Position = size,pos
    b.Text,b.TextTransparency = value,1
    b.AutoButtonColor = true
    b.Selectable = true
    round(b,9)
    Theme.Paint(b,swatch)
    return b
end

local function icon(parent: Instance,name: string,key: string?,size: UDim2,pos: UDim2): ImageLabel
    local item = create("ImageLabel",name,parent)
    item.BackgroundTransparency = 1
    item.Size,item.Position,item.ScaleType = size,pos,Enum.ScaleType.Fit
    if key then Icons.Set(item,key) end
    return item
end

local function buttonCaption(button: TextButton, size: number, iconKey: string?): TextLabel
    if iconKey then icon(button,"Icon",iconKey,offset(31,31),dimensions(0,4,.5,-16)) end
    local left = if iconKey then 34 else 3
    return label(button,"Caption",button.Text,dimensions(1,-left-3,1,-3),offset(left,0),size,true,true)
end

local function paintedFrame(parent: Instance,name: string,swatch: Swatch,size: UDim2,pos: UDim2?,radius: number): Frame
    local item = frame(parent,name,Theme.ink,size,pos)
    round(item,radius)
    Theme.Paint(item,swatch)
    return item
end

local function fitText(text: TextLabel, minSize: number, maxSize: number)
    text.TextScaled = true
    local limit = create("UITextSizeConstraint","FontSize",text)
    limit.MinTextSize,limit.MaxTextSize = minSize,maxSize
    return limit :: UITextSizeConstraint
end

local function scroll(parent: Instance,name: string,size: UDim2,pos: UDim2): ScrollingFrame
    local s = create("ScrollingFrame",name,parent)
    s.Size,s.Position = size,pos
    s.BackgroundTransparency,s.BorderSizePixel = 1,0
    s.CanvasSize = offset(0,0)
    s.AutomaticCanvasSize = Enum.AutomaticSize.Y
    s.ScrollingDirection = Enum.ScrollingDirection.Y
    s.ScrollBarThickness,s.ScrollBarImageColor3 = 4,C.gold
    return s
end

function View.Mount(parent: PlayerGui)
    local gui = create("ScreenGui","DuneBaronHud",parent)
    gui.ResetOnSpawn,gui.DisplayOrder = false,9
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local screen = frame(gui,"Layout",nil,dimensions(1,0,1,0))
    local status = paintedFrame(screen,"Status",Theme.panel,offset(318,78),offset(14,12),11)
    local statusScale = create("UIScale","FitWidth",status)
    icon(status,"Coins","icon_currency_coin",offset(43,43),offset(5,7))
    local coins = label(status,"Coins","0",offset(88,28),offset(49,20),22,true)
    coins.TextColor3 = C.gold
    fitText(coins,10,22)
    label(status,"CoinCaption","MÜNZEN",offset(86,14),offset(49,9),10,true).TextColor3 = C.sub
    icon(status,"Sand","icon_currency_sand",offset(40,40),offset(138,7))
    local tank = label(status,"Tank","0 / 0",offset(131,25),offset(178,14),20,true)
    fitText(tank,10,20)
    label(status,"TankCaption","SANDTANK",offset(125,11),offset(178,6),9,true).TextColor3 = C.sub
    local track = frame(status,"TankTrack",Theme.ink,offset(120,6),offset(178,43))
    round(track,4)
    local fill = frame(track,"Fill",C.gold,dimensions(0,0,1,0))
    round(fill,4)
    local currentStatus = label(status,"ZoneAndTool","",offset(292,20),offset(12,52),12)
    currentStatus.TextColor3 = C.sub
    local nav = frame(screen,"Navigation",nil,offset(248,45),offset(14,100))
    local navScale = create("UIScale","FitWidth",nav)
    local menuOpen = button(nav,"OpenMenu","Menü",offset(106,45),offset(0,0),Theme.gold)
    local findOpen = button(nav,"OpenFinds","Fundkarte",offset(134,45),offset(114,0),Theme.teal)
    buttonCaption(menuOpen,18,"icon_node_storage_backpack")
    buttonCaption(findOpen,18,"icon_node_luck_magnifier")

    local bar = paintedFrame(screen,"EquipmentBar",Theme.panel,offset(438,83),dimensions(.5,0,1,-16),12)
    bar.AnchorPoint = Vector2.new(.5,1)
    local toolSlots: {any} = {}

    local toastCard = frame(screen,"ToastCard",Theme.ink,offset(350,40),dimensions(.5,0,1,-111))
    toastCard.AnchorPoint,toastCard.Visible = Vector2.new(.5,1),false
    round(toastCard,9)
    local toast = label(toastCard,"Toast","",dimensions(1,-18,1,0),offset(9,0),14,true,true)
    local toastToken = 0

    local overlay = frame(screen,"MenuOverlay",Theme.ink,dimensions(1,0,1,0))
    overlay.Active = true
    overlay.BackgroundTransparency = .39
    overlay.Visible = false
    local panel = paintedFrame(overlay,"MenuPanel",Theme.panel,offset(980,620),dimensions(.5,0,.5,0),15)
    panel.AnchorPoint = Vector2.new(.5,.5)
    local header = paintedFrame(panel,"Header",Theme.gold,dimensions(1,-16,0,48),offset(8,7),10)
    local headingIcon = icon(header,"Icon","icon_node_storage_backpack",offset(46,46),offset(8,0))
    local heading = label(header,"Heading","Menü",dimensions(1,-116,1,-4),offset(62,0),31,true)
    local close = button(panel,"Close","×",offset(44,48),dimensions(1,-52,0,7),Theme.clay)
    buttonCaption(close,30)
    local sections = frame(panel,"Pages",nil,dimensions(1,-28,0,42),offset(14,64))
    local pageMenu = button(sections,"OverviewTab","Ausrüstung",dimensions(.5,-5,1,0),offset(0,0),Theme.teal)
    local pageFind = button(sections,"CollectionTab","Fundkarte",dimensions(.5,-5,1,0),dimensions(.5,5,0,0),Theme.slate)
    fitText(buttonCaption(pageMenu,19,"icon_node_collect_shovel"),11,19)
    fitText(buttonCaption(pageFind,19,"icon_node_luck_magnifier"),11,19)
    local menuContent = scroll(panel,"EquipmentContents",dimensions(1,-26,1,-124),offset(14,114))
    local menuPadding = create("UIPadding","Margins",menuContent)
    menuPadding.PaddingLeft,menuPadding.PaddingRight,menuPadding.PaddingTop,menuPadding.PaddingBottom = UDim.new(0,4),UDim.new(0,9),UDim.new(0,4),UDim.new(0,4)
    local menuRows = create("UIListLayout","Rows",menuContent)
    menuRows.Padding,menuRows.SortOrder = UDim.new(0,10),Enum.SortOrder.LayoutOrder
    local equipped = paintedFrame(menuContent,"SelectedEquipment",Theme.slate,dimensions(1,0,0,46),nil,9)
    equipped.LayoutOrder = 0
    local selectedToolIcon = icon(equipped,"Icon",nil,offset(39,39),offset(6,1))
    local selectedTool = label(equipped,"SelectedTool","Hand",dimensions(1,-56,1,-4),offset(49,0),19,true)
    fitText(selectedTool,11,19)
    for i, spec in referenceSections do
        local isCrates = spec.tileColors ~= nil
        local section = paintedFrame(menuContent,"Section"..i,Theme.panel,dimensions(1,0,0,if isCrates then 174 else 130),nil,10)
        section.LayoutOrder = i
        label(section,"SectionName",spec.name,dimensions(1,-22,0,28),offset(11,2),22,true).TextColor3 = spec.color.rim
        local tiles = frame(section,"Tiles",nil,dimensions(1,-18,1,-42),offset(9,34))
        for j, entry in spec.items do
            local color = if spec.tileColors then spec.tileColors[j] else spec.color
            local cell = paintedFrame(tiles,entry[2],color,dimensions(.25,-6,1,0),dimensions((j-1)*.25,3,0,0),8)
            icon(cell,"Icon","icon_"..entry[2],dimensions(1,-8,1,-28),offset(4,1))
            local tileName = label(cell,"Name",entry[1],dimensions(1,-6,0,23),dimensions(0,3,1,-26),19,true,true)
            fitText(tileName,9,19)
        end
    end

    local finds = frame(panel,"FindMap",nil,dimensions(1,-28,1,-124),offset(14,114))
    local zoneBar = frame(finds,"Zones",nil,dimensions(1,0,0,36))
    local zoneButtons: {TextButton} = {}
    local list = scroll(finds,"FindCards",dimensions(.69,-8,1,-45),offset(1,43))
    local listPadding = create("UIPadding","Margins",list)
    listPadding.PaddingLeft,listPadding.PaddingTop,listPadding.PaddingBottom = UDim.new(0,4),UDim.new(0,4),UDim.new(0,4)
    local grid = create("UIGridLayout","CardGrid",list)
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.CellPadding = offset(9,9)
    local detail = paintedFrame(finds,"FindDetail",Theme.panel,dimensions(.31,-8,1,-47),dimensions(.69,8,0,43),11)
    local detailGraphic = paintedFrame(detail,"Preview",Theme.slate,offset(115,115),dimensions(.5,-57,0,12),10)
    local detailRing = icon(detailGraphic,"Rarity",nil,dimensions(1,0,1,0),offset(0,0))
    local detailIcon = icon(detailGraphic,"Artifact",nil,dimensions(.76,0,.76,0),dimensions(.12,0,.12,0))
    local detailTitle = label(detail,"FindName","",dimensions(1,-22,0,34),offset(11,135),18,true)
    detailTitle.TextTruncate,detailTitle.TextWrapped = Enum.TextTruncate.None,true
    local detailTitleLimit = fitText(detailTitle,10,21)
    local detailSet = label(detail,"FindSet","",dimensions(1,-22,0,21),offset(11,172),13)
    local detailRarity = label(detail,"RarityText","",dimensions(1,-22,0,24),offset(11,193),13,true)
    detailRarity.TextColor3 = C.gold
    local detailText = scroll(detail,"FindDescription",dimensions(1,-18,1,-225),offset(9,222))
    detailText.ScrollBarThickness = 3
    local description = label(detailText,"Description","",dimensions(1,-6,0,0),offset(0,0),15)
    description.AutomaticSize = Enum.AutomaticSize.Y
    description.TextWrapped,description.TextTruncate = true,Enum.TextTruncate.None
    description.TextYAlignment,description.TextColor3 = Enum.TextYAlignment.Top,C.sub

    local tab, activeZone, currentTool = "equipment",nil,1
    local currentCards: {TextButton} = {}
    local selectedBorder: UIStroke? = nil
    local function selectCard(row: any, border: UIStroke)
        if selectedBorder then selectedBorder.Color = Theme.ink end
        selectedBorder = border
        border.Color = C.tealLight
        Theme.Paint(detailGraphic,Theme.finds[row.rarity],2)
        Icons.Set(detailRing,"frame_rarity_"..row.rarity)
        Icons.Set(detailIcon,row.icon)
        detailTitle.Text,detailSet.Text,description.Text = row.name,row.set,row.description
        detailRarity.Text = rarity[row.rarity] or row.rarity
        detailRarity.TextColor3 = Theme.finds[row.rarity].rim
        detailText.CanvasPosition = Vector2.zero
    end

    local function selectZone(key: string)
        if activeZone == key then return end
        activeZone = key
        selectedBorder = nil
        for _, item in currentCards do item:Destroy() end
        table.clear(currentCards)
        for i, zone in zones do
            Theme.Paint(zoneButtons[i],if zone[1] == key then Theme.gold else Theme.slate,2)
        end
        for i, row in Catalog.finds[key] do
            local card = button(list,row.id,row.name,offset(0,0),offset(0,0),Theme.finds[row.rarity])
            local border = card:FindFirstChild("DarkOutline") :: UIStroke
            card.LayoutOrder = i
            table.insert(currentCards,card)
            icon(card,"Rarity","frame_rarity_"..row.rarity,dimensions(1,-8,0,65),offset(4,3))
            icon(card,"Artifact",row.icon,dimensions(1,-14,0,56),offset(7,7))
            local cardName = label(card,"FindName",row.name,dimensions(1,-8,0,28),dimensions(0,4,1,-31),16,true,true)
            cardName.TextWrapped = true
            fitText(cardName,9,16)
            card.Activated:Connect(function() selectCard(row,border) end)
            if i == 1 then selectCard(row,border) end
        end
        list.CanvasPosition = Vector2.zero
    end
    for i, zone in zones do
        local b = button(zoneBar,zone[1],zone[2],dimensions(.2,-6,1,0),dimensions((i-1)*.2,3,0,0),Theme.slate)
        fitText(buttonCaption(b,17),8,17)
        zoneButtons[i] = b
        b.Activated:Connect(function() selectZone(zone[1]) end)
    end

    local function updatePage(nextPage: string)
        tab = nextPage
        local isFind = tab == "find"
        heading.Text = if isFind then "Fundkarte" else "Menü"
        Icons.Set(headingIcon,if isFind then "icon_node_luck_magnifier" else "icon_node_storage_backpack")
        finds.Visible,menuContent.Visible = isFind,not isFind
        Theme.Paint(pageFind,if isFind then Theme.teal else Theme.slate)
        Theme.Paint(pageMenu,if isFind then Theme.slate else Theme.teal)
        if isFind and not activeZone then selectZone(zones[1][1]) end
    end
    local function open(page: string)
        updatePage(page)
        overlay.Visible = true
    end
    menuOpen.Activated:Connect(function() open("equipment") end)
    findOpen.Activated:Connect(function() open("find") end)
    pageMenu.Activated:Connect(function() updatePage("equipment") end)
    pageFind.Activated:Connect(function() updatePage("find") end)
    close.Activated:Connect(function() overlay.Visible = false end)
    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.M then
            if overlay.Visible then overlay.Visible = false else open(tab) end
        end
    end)

    local function toolSummary(index: number)
        local caption = if index == currentTool then "Ausgerüstet" elseif index < currentTool then "Freigeschaltet"
            elseif index == currentTool+1 then "Nächste Werkzeugstufe" else "Gesperrt"
        selectedTool.Text = tools[index][2] .. "  ·  " .. caption
        Icons.Set(selectedToolIcon,"icon_node_collect_"..tools[index][3])
    end
    for i, tool in tools do
        local b = button(bar,tool[1],tool[2],offset(64,74),offset(7+(i-1)*71,7),Theme.slate)
        local ring = icon(b,"State","frame_state_locked",dimensions(1,-6,0,54),offset(3,1))
        local art = icon(b,"ToolIcon","icon_node_collect_"..tool[3],dimensions(1,-12,0,42),offset(6,7))
        local caption = label(b,"ToolName",tool[2],dimensions(1,-2,0,18),dimensions(0,1,1,-20),11,true,true)
        fitText(caption,8,12)
        toolSlots[i] = {button=b,ring=ring,art=art,caption=caption}
        b.Activated:Connect(function()
            toolSummary(i)
            open("equipment")
            menuContent.CanvasPosition = Vector2.zero
        end)
    end

    local function layout()
        local width,height = screen.AbsoluteSize.X,screen.AbsoluteSize.Y
        if width < 1 or height < 1 then return end
        statusScale.Scale = math.clamp((width-28)/318,.4,1)
        navScale.Scale = math.clamp((width-28)/248,.4,1)
        nav.Position = offset(14,22+78*statusScale.Scale)
        local w,h = math.min(990,width-24),math.min(641,height-24)
        panel.Size = offset(w,h)
        local compact = w<660
        local side = if compact then math.clamp(w*.38,118,205) else math.min(272,w*.31)
        list.Size = dimensions(1,-side-14,1,-45)
        detail.Size,detail.Position = dimensions(0,side,1,-47),dimensions(1,-side,0,43)
        local shortPanel = h<440
        local detailSize = if shortPanel then 55 elseif compact then 82 else 115
        local sideBySide = shortPanel and side >= 174
        detailGraphic.Size = offset(detailSize,detailSize)
        detailGraphic.Position = if sideBySide then offset(9,9)
            else dimensions(.5,-detailSize/2,0,if shortPanel then 6 else 12)
        local titleX = if sideBySide then detailSize+19 else 9
        local titleY = if sideBySide then 7 else detailSize+(if shortPanel then 8 else 18)
        local titleHeight = if sideBySide then 25 else 34
        local setY = titleY+titleHeight+1
        local rarityY = setY+(if sideBySide then 15 else 19)
        local textY = if sideBySide then 73 else rarityY+26
        detailTitle.Size,detailTitle.Position = dimensions(1,-titleX-9,0,titleHeight),offset(titleX,titleY)
        detailSet.Size,detailSet.Position = dimensions(1,-titleX-9,0,if sideBySide then 15 else 21),offset(titleX,setY)
        detailRarity.Size,detailRarity.Position = dimensions(1,-titleX-9,0,if sideBySide then 15 else 24),offset(titleX,rarityY)
        detailTitleLimit.MaxTextSize = if compact or shortPanel then 14 else 21
        detailSet.TextSize = if compact or shortPanel then 11 else 14
        detailRarity.TextSize = if compact or shortPanel then 11 else 16
        detailText.Position = offset(9,textY)
        detailText.Size = dimensions(1,-18,1,-textY-5)
        description.TextSize = if compact or shortPanel then 12 else 15
        local usable = math.max(1,w-28-side-25)
        local columns = math.max(1,math.floor((usable+9)/(if compact then 65 else 124)))
        grid.CellSize = offset(math.floor((usable-(columns-1)*9)/columns),98)

        local pitch = math.clamp(math.floor((width-26)/#tools),42,71)
        bar.Size = offset(pitch*#tools+11,88)
        bar.Position = dimensions(.5,0,1,if UserInputService.TouchEnabled and width<760 then -120 else -16)
        toastCard.Position = bar.Position - offset(0,101)
        toastCard.Size = offset(math.min(width-25,350),40)
        for i, slot in toolSlots do
            slot.button.Size = offset(pitch-8,74)
            slot.button.Position = offset(6+(i-1)*pitch,7)
            slot.caption.Text = if pitch < 62 then shortToolNames[i] else tools[i][2]
        end
    end
    screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
    task.defer(layout)
    updatePage("equipment")

    local function updateEquipment(index: number)
        currentTool = index
        toolSummary(index)
        for i, slot in toolSlots do
            local statusKey = if i <= index then "owned" elseif i == index+1 then "available" else "locked"
            Icons.Set(slot.ring,"frame_state_"..statusKey)
            slot.art.ImageTransparency = if i > index+1 then .32 else 0
            Theme.Paint(slot.button,if i==index then Theme.gold elseif i==index+1 then Theme.teal else Theme.slate,2)
            slot.caption.TextColor3 = if i <= index+1 then Theme.text else C.sub
        end
    end
    updateEquipment(1)

    local api = {}
    function api.Update(coinsText: string,tankText: string,ratio: number,toolId: string,statusText: string)
        coins.Text,tank.Text = coinsText,tankText
        currentStatus.Text = statusText
        fill.BackgroundColor3 = if ratio>=1 then C.danger else C.gold
        TweenService:Create(fill,barTiming,{Size=dimensions(ratio,0,1,0)}):Play()
        for i, tool in tools do if tool[1]==toolId and i~=currentTool then updateEquipment(i) end end
    end
    function api.Notify(message: string)
        toastToken += 1
        local token = toastToken
        toastCard.Visible,toastCard.BackgroundTransparency = true,0
        toast.Text,toast.TextTransparency = message,0
        task.delay(1.6,function()
            if token ~= toastToken then return end
            TweenService:Create(toast,toastTiming,{TextTransparency=1}):Play()
            local fade = TweenService:Create(toastCard,toastTiming,{BackgroundTransparency=1})
            fade.Completed:Once(function() if token==toastToken then toastCard.Visible=false end end)
            fade:Play()
        end)
    end
    function api.ShowFinds(zone: string?)
        open("find")
        if zone and Catalog.finds[zone] then selectZone(zone) end
    end
    return api
end

return View
