--!strict
-- ItemVisual-Controller (Paket 4.3)
-- Zeigt Skin (Umhang mit Schärpe) und Begleiter JEDES Spielers. Der Server setzt die Spieler-Attribute
-- `SkinId` und `CompanionId` (Logic/Equipment, nur aus dem Besitz im Profil), der Client liest sie nur
-- und baut einfache Formen aus Data/ItemLooks (Platzhalter bis Paket 3.2, keine fremden Assets).
-- Die Werkzeug-Variante färbt ToolVisual (Attribut `ToolVariantId`).
--
-- Alle Teile sind verankert, nicht kollidierend und nicht abfragbar (CanQuery = false), sie verdecken
-- also weder die Kamera noch Mausklicks. Der Umhang hängt hinter dem Rücken, der Begleiter schwebt
-- neben der Schulter, folgt weich und wippt. Weit entfernte Spieler werden seltener aktualisiert,
-- Begleiter bekommen keine Partikel (auch nicht auf schwachen Geräten).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Umhang (Studs, relativ zum Charakter: x rechts, y hoch, z hinten ist positiv)
local CAPE_SIZE = Vector3.new(1.5, 2.3, 0.12)
local CAPE_OFFSET = Vector3.new(0, 0.2, 0.75)
local CAPE_TILT_DEGREES = 8 -- Umhang weht leicht nach hinten
local SASH_SIZE = Vector3.new(1.75, 0.28, 1.25)
local SASH_OFFSET = Vector3.new(0, 0.35, 0)

-- Begleiter
local COMPANION_OFFSET = Vector3.new(-2.4, 1.6, 1.1) -- links hinter der Schulter
local COMPANION_BOB_STUDS = 0.35
local COMPANION_BOB_SECONDS = 2.2
local COMPANION_FOLLOW_SPEED = 6 -- je Sekunde, größer = straffer
local COMPANION_TELEPORT_STUDS = 30 -- weiter weg: sofort dorthin (Teleport, Respawn)

-- Aktualisierung weit entfernter Spieler
local FAR_DISTANCE_STUDS = 120
local FAR_UPDATE_SECONDS = 0.4

local FOLDER_NAME = "ItemModels"

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local ItemLooks = loadShared("Data", "ItemLooks")

local ItemVisual = {}

type Entry = {
    skinId: string,
    companionId: string,
    model: Model,
    cape: BasePart?,
    sash: BasePart?,
    companion: BasePart?,
    companionPosition: Vector3?,
    nextFarUpdate: number,
    lastUpdate: number, -- Zeit der letzten Aktualisierung (für das weiche Folgen weit entfernter Spieler)
}

local entries: { [Player]: Entry } = {}
local folder: Folder? = nil

local function colorOf(hex: string): Color3
    local r = tonumber(string.sub(hex, 2, 3), 16) or 255
    local g = tonumber(string.sub(hex, 4, 5), 16) or 255
    local b = tonumber(string.sub(hex, 6, 7), 16) or 255
    return Color3.fromRGB(r, g, b)
end

local function materialOf(name: string): Enum.Material
    local ok, value = pcall(function()
        return (Enum.Material :: any)[name]
    end)
    if ok and typeof(value) == "EnumItem" then
        return value :: Enum.Material
    end
    return Enum.Material.SmoothPlastic
end

local function newPart(model: Model, name: string, size: Vector3, look: any, useAccent: boolean): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Size = size
    part.Color = colorOf(if useAccent then look.accentHex else look.colorHex)
    part.Material = materialOf(look.material)
    part.Parent = model
    return part
end

local function rootOf(player: Player): (BasePart?, Humanoid?)
    local character = player.Character
    local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
    local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
    if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
        return nil, nil
    end
    return root, humanoid
end

local function destroyEntry(player: Player)
    local entry = entries[player]
    if entry ~= nil then
        entry.model:Destroy()
        entries[player] = nil
    end
end

local function buildEntry(player: Player, skinId: string, companionId: string): Entry
    local model = Instance.new("Model")
    model.Name = player.Name
    local entry: Entry = {
        skinId = skinId,
        companionId = companionId,
        model = model,
        cape = nil,
        sash = nil,
        companion = nil,
        companionPosition = nil,
        nextFarUpdate = 0,
        lastUpdate = os.clock(),
    }
    local skin = ItemLooks.byId[skinId]
    if skin ~= nil and skin.kind == "skin" then
        entry.cape = newPart(model, "Cape", CAPE_SIZE, skin, false)
        entry.sash = newPart(model, "Sash", SASH_SIZE, skin, true)
    end
    local companion = ItemLooks.byId[companionId]
    if companion ~= nil and companion.kind == "companion" then
        local size = companion.size or 1
        local part = newPart(model, "Companion", Vector3.new(size, size, size), companion, false)
        part.Shape = if companion.shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Block
        entry.companion = part
    end
    model.Parent = folder
    return entry
end

local function updateEntry(entry: Entry, root: BasePart, now: number)
    local camera = workspace.CurrentCamera
    local far = camera ~= nil and (camera.CFrame.Position - root.Position).Magnitude > FAR_DISTANCE_STUDS
    if far and now < entry.nextFarUpdate then
        return
    end
    entry.nextFarUpdate = now + FAR_UPDATE_SECONDS
    local dt = now - entry.lastUpdate
    entry.lastUpdate = now

    local list: { BasePart } = {}
    local cframes: { CFrame } = {}
    local base = root.CFrame
    if entry.cape ~= nil and entry.sash ~= nil then
        table.insert(list, entry.cape)
        table.insert(cframes, base * CFrame.new(CAPE_OFFSET) * CFrame.Angles(math.rad(CAPE_TILT_DEGREES), 0, 0))
        table.insert(list, entry.sash)
        table.insert(cframes, base * CFrame.new(SASH_OFFSET))
    end
    local companion = entry.companion
    if companion ~= nil then
        local bob = math.sin(now * 2 * math.pi / COMPANION_BOB_SECONDS) * COMPANION_BOB_STUDS
        local target = (base * CFrame.new(COMPANION_OFFSET + Vector3.new(0, bob, 0))).Position
        local current = entry.companionPosition
        if current == nil or (current - target).Magnitude > COMPANION_TELEPORT_STUDS then
            current = target
        else
            current = current:Lerp(target, 1 - math.exp(-COMPANION_FOLLOW_SPEED * math.max(dt, 1 / 120)))
        end
        entry.companionPosition = current
        table.insert(list, companion)
        table.insert(cframes, CFrame.new(current :: Vector3) * (base - base.Position))
    end
    if #list > 0 then
        workspace:BulkMoveTo(list, cframes, Enum.BulkMoveMode.FireCFrameChanged)
    end
end

local function onFrame()
    local now = os.clock()
    for _, player in Players:GetPlayers() do
        local skinId = player:GetAttribute("SkinId")
        local companionId = player:GetAttribute("CompanionId")
        local root = select(1, rootOf(player))
        if type(skinId) ~= "string" then
            skinId = ""
        end
        if type(companionId) ~= "string" then
            companionId = ""
        end
        if root == nil or (skinId == "" and companionId == "") then
            -- Nichts ausgerüstet, tot oder noch nicht bereit: Modell entfernen.
            destroyEntry(player)
            continue
        end
        local entry = entries[player]
        if entry == nil or entry.skinId ~= skinId or entry.companionId ~= companionId then
            destroyEntry(player)
            entry = buildEntry(player, skinId, companionId)
            entries[player] = entry
        end
        updateEntry(entry :: Entry, root, now)
    end
end

function ItemVisual.Init() end

function ItemVisual.Start()
    local existing = workspace:FindFirstChild(FOLDER_NAME)
    if existing ~= nil then
        existing:Destroy()
    end
    local f = Instance.new("Folder")
    f.Name = FOLDER_NAME
    f.Parent = workspace
    folder = f
    Players.PlayerRemoving:Connect(destroyEntry)
    RunService.Heartbeat:Connect(function()
        local ok, err = pcall(onFrame)
        if not ok then
            warn("[ItemVisual] " .. tostring(err))
        end
    end)
end

return ItemVisual
