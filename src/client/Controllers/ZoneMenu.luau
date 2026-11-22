--!strict
-- ZoneMenu-Controller (Paket 2.5, Handy-Durchgang 3.6)
-- Zonen-Menü (Knopf "Zonen" in der Menüleiste von Controllers/Screen, das Fenster scrollt und passt
-- sich dem Bildschirm an) und die Tor-Anzeigen in der Welt. Alle Werte kommen vom
-- Server (State: zoneId, zonesUnlocked). Der Client sendet nur die Zonen-ID (TravelZone), der
-- Server prüft, ob die Zone frei ist, und setzt den Spieler. Die Tore sind reine Optik: Sie
-- zeigen, ob die Zone dahinter frei ist. Die Sperre selbst setzt der Server durch.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Darstellung
local MENU_ORDER = 1 -- Platz in der Menüleiste (Zonen zuerst)
local ROW_HEIGHT = 64
local FOOTER_HEIGHT = 30
local MESSAGE_SECONDS = 3
local GATE_OPEN_TRANSPARENCY = 1
local GATE_LOCKED_TRANSPARENCY = 0.6
local GATE_SIGN_SIZE = UDim2.new(0, 260, 0, 70)
local GATE_SIGN_OFFSET = Vector3.new(0, 4, 0)
local GATE_SIGN_DISTANCE = 120

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local PANEL_COLOR = Color3.fromRGB(40, 32, 24)
local ROW_COLOR = Color3.fromRGB(64, 52, 40)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local GO_COLOR = Color3.fromRGB(230, 200, 117)
local DISABLED_COLOR = Color3.fromRGB(90, 80, 70)

local REASON_TEXT = {
    locked = "Diese Zone ist noch gesperrt.",
    cooldown = "Kurz warten, dann kannst du wieder reisen.",
    same = "Du bist schon dort.",
    dead = "Als Charakter lebendig sein, um zu reisen.",
    unknown = "Reisen gerade nicht möglich.",
}

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local Zones = loadShared("Data", "Zones")
local SandTypes = loadShared("Data", "SandTypes")
local UpgradeTree = loadShared("Data", "UpgradeTree")
local World = loadShared("Data", "World")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any

local ZoneMenu = {}

local player = Players.LocalPlayer
local gates: { [BasePart]: { sign: BillboardGui, label: TextLabel } } = {}

-- Text zur Voraussetzung einer Zone ("Benötigt: Eimerkette").
local function requirementText(zone: any): string
    if zone.requires == "start" then
        return "Start"
    end
    local node = UpgradeTree.byId[zone.requires]
    return `Benötigt: {if node ~= nil then node.name else zone.requires}`
end

-- Läuft die Saison dieser Event-Zone gerade (Snapshot `season`, Paket 5.5)?
local function seasonRunning(snapshot: any?, zone: any): boolean
    local season = if snapshot ~= nil then snapshot.season else nil
    return type(season) == "table" and season.active == true and season.id == zone.seasonId and season.zoneOpen == true
end

-- Text für eine gesperrte Zone: Knoten, bei einer Event-Zone außerhalb der Saison der Hinweis darauf.
local function lockedText(zone: any, snapshot: any?): string
    if zone.seasonId ~= nil and not seasonRunning(snapshot, zone) then
        return "Nur in der Saison"
    end
    return requirementText(zone)
end

local function isUnlocked(snapshot: any?, zoneId: string): boolean
    return snapshot ~= nil and type(snapshot.zonesUnlocked) == "table" and snapshot.zonesUnlocked[zoneId] == true
end

local function zoneName(zoneId: string): string
    local zone = Zones.byId[zoneId]
    return if zone ~= nil then zone.name else zoneId
end

local function sandText(zone: any): string
    local sandType = SandTypes.byId[zone.sandTypeId]
    if sandType == nil then
        return ""
    end
    return `{sandType.name} x{sandType.priceFactor}`
end

-- Tor-Anzeige: frei = unsichtbar, gesperrt = rot mit Schild.
local function refreshGate(part: BasePart, snapshot: any?)
    local entry = gates[part]
    local zoneId = part:GetAttribute("ZoneId")
    if entry == nil or type(zoneId) ~= "string" then
        return
    end
    local zone = Zones.byId[zoneId]
    if zone == nil then
        return
    end
    local open = isUnlocked(snapshot, zoneId)
    part.Transparency = if open then GATE_OPEN_TRANSPARENCY else GATE_LOCKED_TRANSPARENCY
    entry.sign.Enabled = not open
    entry.label.Text = `{zone.name}\n{lockedText(zone, snapshot)}`
end

local function addGate(part: Instance)
    if not part:IsA("BasePart") or gates[part] ~= nil then
        return
    end
    local sign = Instance.new("BillboardGui")
    sign.Name = "GateSign"
    sign.Size = GATE_SIGN_SIZE
    sign.StudsOffsetWorldSpace = GATE_SIGN_OFFSET
    sign.AlwaysOnTop = false
    sign.MaxDistance = GATE_SIGN_DISTANCE
    sign.Adornee = part
    local text = Instance.new("TextLabel")
    text.BackgroundColor3 = PANEL_COLOR
    text.BackgroundTransparency = 0.25
    text.Size = UDim2.new(1, 0, 1, 0)
    text.Font = Enum.Font.GothamBold
    text.TextColor3 = TEXT_COLOR
    text.TextScaled = true
    text.Parent = sign
    Instance.new("UICorner").Parent = text
    sign.Parent = player:WaitForChild("PlayerGui")
    gates[part] = { sign = sign, label = text }
    refreshGate(part, State.get())
end

function ZoneMenu.Init() end

function ZoneMenu.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local travel = remotes:WaitForChild("TravelZone") :: RemoteFunction

    local controls = Screen.controls()
    local ROW_BUTTON_W = controls.rowButtonW

    local refresh: (any?) -> () = function(_snapshot: any?) end
    local message = Instance.new("TextLabel")
    local window = Screen.createWindow({
        name = "ZonesWindow",
        title = "Zonen",
        footerHeight = FOOTER_HEIGHT,
        onOpen = function()
            message.Text = ""
            refresh(State.get())
        end,
    })
    local openButton = Screen.addMenuButton("ZonesButton", "Zonen", MENU_ORDER)

    message.Name = "Message"
    message.BackgroundTransparency = 1
    message.Position = UDim2.fromOffset(16, 4)
    message.Size = UDim2.new(1, -32, 1, -8)
    message.Font = Enum.Font.Gotham
    message.TextColor3 = MUTED_COLOR
    message.TextScaled = true
    message.TextXAlignment = Enum.TextXAlignment.Left
    message.Text = ""
    message.Parent = window.footer

    local busy = false
    local rows: { [string]: { row: Frame, status: TextLabel, go: TextButton } } = {}
    -- Feste Zonen, danach die Event-Zonen der Saisons (Paket 5.5, nur sichtbar, solange ihre Saison läuft).
    local allZones: { any } = {}
    for _, zone in Zones.list do
        table.insert(allZones, zone)
    end
    for _, zone in Zones.events do
        table.insert(allZones, zone)
    end
    for index, zone in allZones do
        local row = Instance.new("Frame")
        row.Name = zone.id
        row.LayoutOrder = index
        row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
        row.BackgroundColor3 = ROW_COLOR
        row.BackgroundTransparency = 0.2
        row.Parent = window.body
        Instance.new("UICorner").Parent = row

        local textWidth = -(ROW_BUTTON_W + 28)
        local nameLabel = Instance.new("TextLabel")
        nameLabel.BackgroundTransparency = 1
        nameLabel.Position = UDim2.new(0, 10, 0, 4)
        nameLabel.Size = UDim2.new(1, textWidth, 0, 28)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextColor3 = TEXT_COLOR
        nameLabel.TextScaled = true
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Text = `{zone.name} · {sandText(zone)}`
        nameLabel.Parent = row

        local status = Instance.new("TextLabel")
        status.BackgroundTransparency = 1
        status.Position = UDim2.new(0, 10, 0, 34)
        status.Size = UDim2.new(1, textWidth, 0, 22)
        status.Font = Enum.Font.Gotham
        status.TextColor3 = MUTED_COLOR
        status.TextScaled = true
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.Parent = row

        local go = Instance.new("TextButton")
        go.AnchorPoint = Vector2.new(1, 0.5)
        go.Position = UDim2.new(1, -10, 0.5, 0)
        go.Size = UDim2.fromOffset(ROW_BUTTON_W, controls.rowButtonH)
        go.Font = Enum.Font.GothamBold
        go.TextColor3 = PANEL_COLOR
        go.TextScaled = true
        go.Text = "Reisen"
        go.Parent = row
        Instance.new("UICorner").Parent = go

        rows[zone.id] = { row = row, status = status, go = go }
        row.Visible = zone.seasonId == nil
        go.Activated:Connect(function()
            if busy then
                return -- ein Aufruf läuft noch (Doppelklick)
            end
            busy = true
            local ok, response = pcall(function(): any
                return travel:InvokeServer(zone.id)
            end)
            busy = false
            if not ok or type(response) ~= "table" then
                message.Text = REASON_TEXT.unknown
            elseif response.ok == true then
                message.Text = ""
                window.close()
                return
            else
                message.Text = REASON_TEXT[response.reason] or REASON_TEXT.unknown
            end
            local text = message.Text
            task.delay(MESSAGE_SECONDS, function()
                if message.Text == text then
                    message.Text = ""
                end
            end)
        end)
    end

    refresh = function(snapshot: any?)
        for _, zone in allZones do
            local row = rows[zone.id]
            local open = isUnlocked(snapshot, zone.id)
            local current = snapshot ~= nil and snapshot.zoneId == zone.id
            if zone.seasonId ~= nil then
                row.row.Visible = open or seasonRunning(snapshot, zone) or current
            end
            local points = ""
            local pass = if snapshot ~= nil then snapshot.seasonPass else nil
            if zone.seasonId ~= nil and type(pass) == "table" and pass.seasonId == zone.seasonId then
                points = ` · Saison-Punkte {pass.points} von {pass.maxPoints}`
            end
            row.status.Text = (if current then "Hier bist du" elseif open then "Frei" else lockedText(zone, snapshot)) .. points
            row.go.Visible = open and not current
            row.go.BackgroundColor3 = if open then GO_COLOR else DISABLED_COLOR
        end
        for part in gates do
            refreshGate(part, snapshot)
        end
    end

    openButton.Activated:Connect(window.toggle)

    for _, part in CollectionService:GetTagged(World.gateTag) do
        addGate(part)
    end
    CollectionService:GetInstanceAddedSignal(World.gateTag):Connect(addGate)
    CollectionService:GetInstanceRemovedSignal(World.gateTag):Connect(function(part: Instance)
        local entry = gates[part :: BasePart]
        if entry ~= nil then
            entry.sign:Destroy()
            gates[part :: BasePart] = nil
        end
    end)

    State.onChanged(refresh)
    refresh(State.get())
end

return ZoneMenu
