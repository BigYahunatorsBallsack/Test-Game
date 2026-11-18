--!strict
-- ZoneMenu-Controller (Paket 2.5)
-- Zonen-Menü (Knopf "Zonen" unten links) und die Tor-Anzeigen in der Welt. Alle Werte kommen vom
-- Server (State: zoneId, zonesUnlocked). Der Client sendet nur die Zonen-ID (TravelZone), der
-- Server prüft, ob die Zone frei ist, und setzt den Spieler. Die Tore sind reine Optik: Sie
-- zeigen, ob die Zone dahinter frei ist. Die Sperre selbst setzt der Server durch.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Darstellung
local BUTTON_POSITION = UDim2.new(0, 16, 1, -72)
local BUTTON_SIZE = UDim2.new(0, 120, 0, 48)
local PANEL_SIZE = UDim2.new(0, 380, 0, 400)
local ROW_HEIGHT = 64
local ROW_GAP = 8
local PANEL_FADE_SECONDS = 0.18
local PANEL_EASING = Enum.EasingStyle.Quad
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
    entry.label.Text = `{zone.name}\n{requirementText(zone)}`
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

    local gui = Instance.new("ScreenGui")
    gui.Name = "DuneBaronZones"
    gui.ResetOnSpawn = false

    local openButton = Instance.new("TextButton")
    openButton.Name = "ZonesButton"
    openButton.Position = BUTTON_POSITION
    openButton.Size = BUTTON_SIZE
    openButton.BackgroundColor3 = PANEL_COLOR
    openButton.BackgroundTransparency = 0.25
    openButton.Font = Enum.Font.GothamBold
    openButton.TextColor3 = TEXT_COLOR
    openButton.TextScaled = true
    openButton.Text = "Zonen"
    openButton.Parent = gui
    Instance.new("UICorner").Parent = openButton

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0, 1)
    panel.Position = UDim2.new(0, 16, 1, -128)
    panel.Size = PANEL_SIZE
    panel.BackgroundColor3 = PANEL_COLOR
    panel.BackgroundTransparency = 1
    panel.Visible = false
    panel.Parent = gui
    Instance.new("UICorner").Parent = panel

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 16, 0, 8)
    title.Size = UDim2.new(1, -32, 0, 30)
    title.Font = Enum.Font.GothamBold
    title.TextColor3 = TEXT_COLOR
    title.TextScaled = true
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Zonen"
    title.Parent = panel

    local message = Instance.new("TextLabel")
    message.Name = "Message"
    message.BackgroundTransparency = 1
    message.AnchorPoint = Vector2.new(0, 1)
    message.Position = UDim2.new(0, 16, 1, -6)
    message.Size = UDim2.new(1, -32, 0, 22)
    message.Font = Enum.Font.Gotham
    message.TextColor3 = MUTED_COLOR
    message.TextScaled = true
    message.TextXAlignment = Enum.TextXAlignment.Left
    message.Text = ""
    message.Parent = panel

    local rows: { [string]: { status: TextLabel, go: TextButton } } = {}
    for index, zone in Zones.list do
        local row = Instance.new("Frame")
        row.Name = zone.id
        row.Position = UDim2.new(0, 12, 0, 46 + (index - 1) * (ROW_HEIGHT + ROW_GAP))
        row.Size = UDim2.new(1, -24, 0, ROW_HEIGHT)
        row.BackgroundColor3 = ROW_COLOR
        row.BackgroundTransparency = 0.2
        row.Parent = panel
        Instance.new("UICorner").Parent = row

        local nameLabel = Instance.new("TextLabel")
        nameLabel.BackgroundTransparency = 1
        nameLabel.Position = UDim2.new(0, 10, 0, 4)
        nameLabel.Size = UDim2.new(1, -120, 0, 26)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextColor3 = TEXT_COLOR
        nameLabel.TextScaled = true
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Text = `{zone.name} · {sandText(zone)}`
        nameLabel.Parent = row

        local status = Instance.new("TextLabel")
        status.BackgroundTransparency = 1
        status.Position = UDim2.new(0, 10, 0, 34)
        status.Size = UDim2.new(1, -120, 0, 22)
        status.Font = Enum.Font.Gotham
        status.TextColor3 = MUTED_COLOR
        status.TextScaled = true
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.Parent = row

        local go = Instance.new("TextButton")
        go.AnchorPoint = Vector2.new(1, 0.5)
        go.Position = UDim2.new(1, -10, 0.5, 0)
        go.Size = UDim2.new(0, 92, 0, 40)
        go.Font = Enum.Font.GothamBold
        go.TextColor3 = PANEL_COLOR
        go.TextScaled = true
        go.Text = "Reisen"
        go.Parent = row
        Instance.new("UICorner").Parent = go

        rows[zone.id] = { status = status, go = go }
        go.Activated:Connect(function()
            local ok, response = pcall(function(): any
                return travel:InvokeServer(zone.id)
            end)
            if not ok or type(response) ~= "table" then
                message.Text = REASON_TEXT.unknown
            elseif response.ok == true then
                message.Text = ""
                panel.Visible = false
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

    local function refresh(snapshot: any?)
        for _, zone in Zones.list do
            local row = rows[zone.id]
            local open = isUnlocked(snapshot, zone.id)
            local current = snapshot ~= nil and snapshot.zoneId == zone.id
            row.status.Text = if current then "Hier bist du" elseif open then "Frei" else requirementText(zone)
            row.go.Visible = open and not current
            row.go.BackgroundColor3 = if open then GO_COLOR else DISABLED_COLOR
        end
        for part in gates do
            refreshGate(part, snapshot)
        end
    end

    local fade = TweenInfo.new(PANEL_FADE_SECONDS, PANEL_EASING)
    openButton.Activated:Connect(function()
        panel.Visible = not panel.Visible
        if panel.Visible then
            panel.BackgroundTransparency = 1
            TweenService:Create(panel, fade, { BackgroundTransparency = 0.15 }):Play()
            message.Text = ""
            refresh(State.get())
        end
    end)

    gui.Parent = player:WaitForChild("PlayerGui")

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
