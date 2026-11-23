--!strict
-- Saison-Pass-Fenster (Paket 5.5b)
-- Knopf "Saison" in der Menüleiste und Fenster mit den Stufen der Saison: je Stufe eine Gratis-Zelle
-- und eine Premium-Zelle. Der Server entscheidet alles (Remotes ClaimSeasonReward mit Stufe und Spur,
-- BuySeasonPass ohne Argumente, Snapshot-Feld `seasonPass`). Der Client zeigt an und zählt nur die
-- Abholfrist lokal herunter. Die Belohnungen liest er aus Data/SeasonPass (liegt im geteilten Ordner).
--
-- Der Knopf erscheint, solange der Server einen Pass-Zustand schickt: während der Saison und in der
-- Abholfrist nach dem Ende. Gekauft wird über den Roblox-Kaufdialog, den der Server öffnet; ob und
-- wann der Pass gilt, bestätigt der Server (Notify "seasonPassBought" nach dem Speichern).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Menüleiste und Fenster
local MENU_ORDER = 9 -- nach Zonen, Sammlung, Sandsturm, Kisten, Gems, Ausrüstung, Täglich und Code
local SUB_HEIGHT = 64
local FOOTER_HEIGHT = 118
local TIER_HEIGHT = 104
local TIER_HEAD_HEIGHT = 24
local CELL_GAP = 8
local ROW_GAP = 8
local MESSAGE_SECONDS = 4
local COUNTDOWN_TICK_SECONDS = 0.5
local ACTION_COOLDOWN_SECONDS = 0.4 -- etwas länger als das Server-Limit (5 Aufrufe je Sekunde)
local BUY_COOLDOWN_SECONDS = 3.2 -- etwas länger als das Server-Limit (1 Aufruf je 3 s)
local BAR_HEIGHT = 16

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local ROW_COLOR = Color3.fromRGB(64, 52, 40)
local CELL_COLOR = Color3.fromRGB(80, 66, 52)
local CLAIMABLE_COLOR = Color3.fromRGB(110, 150, 70)
local DONE_COLOR = Color3.fromRGB(48, 70, 48)
local PREMIUM_COLOR = Color3.fromRGB(96, 78, 44)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local ACCENT_COLOR = Color3.fromRGB(255, 190, 90)
local WARN_COLOR = Color3.fromRGB(235, 150, 90)
local BAR_BACK_COLOR = Color3.fromRGB(40, 32, 26)
local BAR_COLOR = Color3.fromRGB(255, 190, 90)
local BUTTON_COLOR = Color3.fromRGB(110, 150, 70)
local BUTTON_OFF_COLOR = Color3.fromRGB(80, 66, 52)

local REASONS: { [string]: string } = {
    noSeason = "Gerade läuft keine Saison.",
    notReached = "Diese Stufe ist noch nicht erreicht.",
    claimed = "Diese Belohnung hast du schon abgeholt.",
    needPass = "Diese Spur gehört zum Saison-Pass.",
    expired = "Die Abholfrist ist vorbei.",
    owned = "Du hast den Saison-Pass schon.",
    notOffered = "Der Saison-Pass ist noch nicht im Shop verfügbar.",
    busy = "Einen Moment, bitte gleich noch einmal versuchen.",
    noProfile = "Dein Spielstand wird noch geladen.",
    error = "Das hat nicht geklappt. Bitte versuche es gleich noch einmal.",
    unknown = "Das hat nicht geklappt. Bitte versuche es gleich noch einmal.",
}

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local SeasonPassData = loadShared("Data", "SeasonPass")
local CrateItems = loadShared("Data", "CrateItems")
local Products = loadShared("Data", "Products")
local PriceView = loadShared("Logic", "PriceView")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any
local ProductPrices = require(script.Parent:WaitForChild("ProductPrices") :: ModuleScript) :: any

local SeasonPassMenu = {}

local function minutesText(seconds: number): string
    return `{math.max(math.floor(seconds / 60 + 0.5), 1)} Min.`
end

-- Text einer Belohnung aus den Daten (Data/SeasonPass) oder aus der Antwort des Servers.
local function rewardText(reward: any): string
    local kind = if type(reward) == "table" then reward.kind else nil
    if kind == "gems" then
        return `{if type(reward.amount) == "number" then reward.amount else 0} Gems`
    elseif kind == "coinBoost" then
        return `2x Münzen, {minutesText(reward.seconds)}`
    elseif kind == "luck" then
        return `Glück x2, {minutesText(reward.seconds)}`
    elseif kind == "item" then
        local item = CrateItems.byId[reward.itemId]
        return if item ~= nil then item.name else "Pass-Item"
    end
    return "?"
end

local function dayText(seconds: number): string
    local total = math.max(math.ceil(seconds), 0)
    local days = total // 86400
    local hours = (total % 86400) // 3600
    local minutes = (total % 3600) // 60
    if days > 0 then
        return `{days} T {hours} Std.`
    end
    return `{hours} Std. {minutes} Min.`
end

local function newLabel(parent: Instance, name: string, position: UDim2, size: UDim2, font: Enum.Font, color: Color3, text: string): TextLabel
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Position = position
    l.Size = size
    l.Font = font
    l.TextColor3 = color
    l.TextScaled = true
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = parent
    return l
end

local function newCell(parent: Instance, name: string, position: UDim2, size: UDim2): TextButton
    local b = Instance.new("TextButton")
    b.Name = name
    b.Position = position
    b.Size = size
    b.BackgroundColor3 = CELL_COLOR
    b.AutoButtonColor = false
    b.Font = Enum.Font.Gotham
    b.TextColor3 = TEXT_COLOR
    b.TextScaled = true
    b.TextWrapped = true
    b.Text = ""
    b.Parent = parent
    Instance.new("UICorner").Parent = b
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 6)
    padding.PaddingRight = UDim.new(0, 6)
    padding.PaddingTop = UDim.new(0, 4)
    padding.PaddingBottom = UDim.new(0, 4)
    padding.Parent = b
    return b
end

function SeasonPassMenu.Init() end

function SeasonPassMenu.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local claimReward = remotes:WaitForChild("ClaimSeasonReward") :: RemoteFunction
    local buyPass = remotes:WaitForChild("BuySeasonPass") :: RemoteFunction

    local window = Screen.createWindow({
        name = "SeasonPassWindow",
        title = "Saison-Pass",
        kind = "narrow",
        subHeight = SUB_HEIGHT,
        footerHeight = FOOTER_HEIGHT,
    })
    local openButton = Screen.addMenuButton("SeasonPassButton", "Saison", MENU_ORDER)
    openButton.Visible = false -- erst, wenn der Server einen Pass-Zustand schickt
    openButton.Activated:Connect(window.toggle)

    -- Streifen unter der Kopfzeile: Punkte, Balken, Restzeit
    local pointsLabel = newLabel(window.sub, "Points", UDim2.new(0, 0, 0, 2), UDim2.new(0.55, 0, 0, 26), Enum.Font.GothamBold, TEXT_COLOR, "")
    local timeLabel = newLabel(window.sub, "Time", UDim2.new(0.55, 0, 0, 2), UDim2.new(0.45, 0, 0, 26), Enum.Font.Gotham, MUTED_COLOR, "")
    timeLabel.TextXAlignment = Enum.TextXAlignment.Right
    local barBack = Instance.new("Frame")
    barBack.Name = "BarBack"
    barBack.Position = UDim2.new(0, 0, 0, 36)
    barBack.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
    barBack.BackgroundColor3 = BAR_BACK_COLOR
    barBack.Parent = window.sub
    Instance.new("UICorner").Parent = barBack
    local barFill = Instance.new("Frame")
    barFill.Name = "Fill"
    barFill.Size = UDim2.fromScale(0, 1)
    barFill.BackgroundColor3 = BAR_COLOR
    barFill.Parent = barBack
    Instance.new("UICorner").Parent = barFill

    -- Fuß: Meldung und Kauf-Knopf
    local statusLabel = newLabel(window.footer, "Status", UDim2.new(0, 12, 0, 4), UDim2.new(1, -24, 0, 50), Enum.Font.GothamBold, MUTED_COLOR, "")
    local buyButton = Instance.new("TextButton")
    buyButton.Name = "Buy"
    buyButton.Position = UDim2.new(0, 12, 0, 60)
    buyButton.Size = UDim2.new(1, -24, 0, 48)
    buyButton.Font = Enum.Font.GothamBold
    buyButton.TextColor3 = TEXT_COLOR
    buyButton.TextScaled = true
    buyButton.Text = "Premium freischalten"
    buyButton.BackgroundColor3 = BUTTON_OFF_COLOR
    buyButton.Parent = window.footer
    Instance.new("UICorner").Parent = buyButton

    -- Zeilen: je Stufe eine mit Gratis- und Premium-Zelle (die Stufen kommen aus den Daten der Saison,
    -- gebaut wird beim ersten Snapshot mit einer Saison, bei einem Saisonwechsel neu)
    type Row = { tier: number, points: number, free: TextButton, premium: TextButton, head: TextLabel, frame: Frame }
    local rows: { Row } = {}
    local builtFor: string? = nil
    local claim: (track: string, tier: number, points: number) -> () = function() end -- unten gesetzt

    local function clearRows()
        for _, row in rows do
            row.frame:Destroy()
        end
        table.clear(rows)
    end

    local function buildRows(seasonId: string)
        clearRows()
        builtFor = seasonId
        local config = SeasonPassData.bySeason[seasonId]
        if type(config) ~= "table" or type(config.tiers) ~= "table" then
            return
        end
        for index, tier in config.tiers do
            local frame = Instance.new("Frame")
            frame.Name = `Tier{index}`
            frame.LayoutOrder = index
            frame.Size = UDim2.new(1, 0, 0, TIER_HEIGHT)
            frame.BackgroundColor3 = ROW_COLOR
            frame.BackgroundTransparency = 0.2
            frame.Parent = window.body
            Instance.new("UICorner").Parent = frame
            local head = newLabel(frame, "Head", UDim2.new(0, 8, 0, 4), UDim2.new(1, -16, 0, TIER_HEAD_HEIGHT), Enum.Font.GothamBold, ACCENT_COLOR, `Stufe {index} · {tier.points} Punkte`)
            local cellSize = UDim2.new(0.5, -(CELL_GAP + 4), 1, -(TIER_HEAD_HEIGHT + 12))
            local free = newCell(frame, "Free", UDim2.new(0, 6, 0, TIER_HEAD_HEIGHT + 6), cellSize)
            local premium = newCell(frame, "Premium", UDim2.new(0.5, CELL_GAP / 2 - 2, 0, TIER_HEAD_HEIGHT + 6), cellSize)
            rows[index] = { tier = index, points = tier.points, free = free, premium = premium, head = head, frame = frame }
            free.Activated:Connect(function()
                claim("free", index, tier.points)
            end)
            premium.Activated:Connect(function()
                claim("premium", index, tier.points)
            end)
        end
        local listLayout = window.body:FindFirstChildOfClass("UIListLayout")
        if listLayout ~= nil then
            listLayout.Padding = UDim.new(0, ROW_GAP)
        end
    end

    -- Zustand vom Server mit lokalem Ende der Abholfrist
    local pass: any = nil
    local claimEndsAt = 0 -- os.clock, wann die Abholfrist endet
    local seasonEndsAt = 0 -- os.clock, wann die Saison endet (Punkte und Kauf enden dort, die Frist später)
    local busy = false
    local lastActionAt = -math.huge
    local lastBuyAt = -math.huge
    local messageUntil = 0 -- bis dahin bleibt eine Meldung im Fuß stehen

    -- Produkt des Passes der gezeigten Saison (kommt mit dem Snapshot, ab Saison 2 ein anderes)
    local function productOfPass(): any
        return if pass ~= nil and type(pass.passId) == "string" then Products.byId[pass.passId] else nil
    end

    local function showMessage(text: string, color: Color3?)
        messageUntil = os.clock() + MESSAGE_SECONDS
        statusLabel.Text = text
        statusLabel.TextColor3 = color or WARN_COLOR
    end

    local function expired(): boolean
        return pass ~= nil and claimEndsAt > 0 and os.clock() >= claimEndsAt
    end

    local function isClaimed(track: string, tier: number): boolean
        local claimed = if pass ~= nil and type(pass.claimed) == "table" then pass.claimed[track] else nil
        return type(claimed) == "table" and claimed[tostring(tier)] == true
    end

    local function canClaimCell(track: string, tier: number, points: number): boolean
        if pass == nil or expired() or isClaimed(track, tier) then
            return false
        end
        if (pass.points or 0) < points then
            return false
        end
        return track == "free" or pass.premium == true
    end

    local function renderCell(cell: TextButton, track: string, tier: number, points: number, reward: any)
        local text = rewardText(reward)
        local color = CELL_COLOR
        if isClaimed(track, tier) then
            text = `✓ {text}`
            color = DONE_COLOR
        elseif canClaimCell(track, tier, points) then
            text = `{text}\nAbholen`
            color = CLAIMABLE_COLOR
        elseif track == "premium" and pass ~= nil and pass.premium ~= true then
            text = `{text}\nmit Pass`
            color = PREMIUM_COLOR
        end
        cell.Text = text
        cell.BackgroundColor3 = color
    end

    local function renderBuy()
        if pass == nil then
            return
        end
        if pass.premium == true then
            buyButton.Text = "Premium aktiv"
            buyButton.BackgroundColor3 = DONE_COLOR
        elseif pass.canBuy == true then
            local product = productOfPass()
            local info = if product ~= nil and product.productId > 0 then ProductPrices.info(false, product.productId) else nil
            local price = if product ~= nil then PriceView.buttonText(product.productId, info, product.priceRobux) else nil
            buyButton.Text = if price ~= nil then `Premium freischalten · {price}` else "Premium freischalten"
            buyButton.BackgroundColor3 = BUTTON_COLOR
        else
            buyButton.Text = "Premium nur in der Saison"
            buyButton.BackgroundColor3 = BUTTON_OFF_COLOR
        end
    end

    local function render()
        if pass == nil then
            return
        end
        local points = if type(pass.points) == "number" then pass.points else 0
        local maxPoints = if type(pass.maxPoints) == "number" and pass.maxPoints > 0 then pass.maxPoints else 1
        pointsLabel.Text = `{points} von {maxPoints} Punkten`
        barFill.Size = UDim2.fromScale(math.clamp(points / maxPoints, 0, 1), 1)
        local left = math.max(claimEndsAt - os.clock(), 0)
        if pass.ended == true then
            timeLabel.Text = if left > 0 then `Abholen noch {dayText(left)}` else "Abholfrist vorbei"
            timeLabel.TextColor3 = if left > 0 then WARN_COLOR else MUTED_COLOR
        else
            timeLabel.Text = `Saison-Ende in {dayText(math.max(seasonEndsAt - os.clock(), 0))}`
            timeLabel.TextColor3 = MUTED_COLOR
        end
        local config = SeasonPassData.bySeason[pass.seasonId]
        if config ~= nil then
            for _, row in rows do
                local tier = config.tiers[row.tier]
                renderCell(row.free, "free", row.tier, row.points, tier.free)
                renderCell(row.premium, "premium", row.tier, row.points, tier.premium)
            end
        end
        renderBuy()
        if os.clock() >= messageUntil then
            statusLabel.TextColor3 = MUTED_COLOR
            if pass.ended == true then
                statusLabel.Text = if left > 0 then "Die Saison ist vorbei. Hol deine Belohnungen noch ab." else "Die Abholfrist ist vorbei."
            elseif pass.premium == true then
                statusLabel.Text = "Tippe auf eine erreichte Stufe, um sie abzuholen."
            else
                statusLabel.Text = "Gratis-Spur für alle. Die Premium-Spur schaltet der Saison-Pass frei."
            end
        end
    end

    State.onChanged(function(snapshot: any)
        local entry = snapshot.seasonPass
        if type(entry) ~= "table" or type(entry.seasonId) ~= "string" then
            pass = nil
            openButton.Visible = false
            if window.isOpen() then
                window.close()
            end
            return
        end
        if builtFor ~= entry.seasonId then
            buildRows(entry.seasonId)
        end
        pass = entry
        local seconds = if type(entry.claimSecondsLeft) == "number" and entry.claimSecondsLeft == entry.claimSecondsLeft then math.max(entry.claimSecondsLeft, 0) else 0
        claimEndsAt = os.clock() + seconds
        local seasonSeconds = if type(entry.seasonSecondsLeft) == "number" and entry.seasonSecondsLeft == entry.seasonSecondsLeft then math.max(entry.seasonSecondsLeft, 0) else 0
        seasonEndsAt = os.clock() + seasonSeconds
        openButton.Visible = true
        render()
    end)

    task.spawn(function()
        while true do
            task.wait(COUNTDOWN_TICK_SECONDS)
            if pass ~= nil and window.isOpen() then
                render()
            end
        end
    end)

    -- Abholen: Tipp auf eine Zelle
    claim = function(track: string, tier: number, points: number)
        if busy or os.clock() - lastActionAt < ACTION_COOLDOWN_SECONDS then
            return
        end
        if pass == nil then
            return
        end
        if isClaimed(track, tier) then
            showMessage(REASONS.claimed)
            return
        end
        if expired() then
            showMessage(REASONS.expired)
            return
        end
        if (pass.points or 0) < points then
            showMessage(REASONS.notReached)
            return
        end
        if track == "premium" and pass.premium ~= true then
            showMessage(REASONS.needPass)
            return
        end
        busy = true
        lastActionAt = os.clock()
        local ok, reply = pcall(function(): any
            return claimReward:InvokeServer(tier, track)
        end)
        busy = false
        if not ok or type(reply) ~= "table" then
            showMessage(REASONS.error)
            return
        end
        if reply.ok ~= true then
            showMessage(REASONS[tostring(reply.reason)] or REASONS.unknown)
            return
        end
        -- Der Snapshot des Servers folgt; bis dahin zeigt die Zelle schon "abgeholt".
        pass = table.clone(pass)
        local claimed = table.clone(if type(pass.claimed) == "table" then pass.claimed else {})
        local trackClaimed = table.clone(if type(claimed[track]) == "table" then claimed[track] else {})
        trackClaimed[tostring(tier)] = true
        claimed[track] = trackClaimed
        pass.claimed = claimed
        showMessage(`Abgeholt: {rewardText(reply.reward)}`, ACCENT_COLOR)
        render()
    end

    -- Kaufen: der Server prüft Saison und Besitz und öffnet den Dialog; gebucht wird in ProcessReceipt.
    buyButton.Activated:Connect(function()
        if busy or os.clock() - lastBuyAt < BUY_COOLDOWN_SECONDS then
            return
        end
        if pass == nil then
            return
        end
        if pass.premium == true then
            showMessage(REASONS.owned, MUTED_COLOR)
            return
        end
        if pass.canBuy ~= true then
            showMessage(REASONS.noSeason)
            return
        end
        busy = true
        lastBuyAt = os.clock()
        local ok, reply = pcall(function(): any
            return buyPass:InvokeServer()
        end)
        busy = false
        if not ok or type(reply) ~= "table" then
            showMessage(REASONS.error)
            return
        end
        if reply.ok ~= true then
            showMessage(REASONS[tostring(reply.reason)] or REASONS.unknown)
        end
    end)

    -- Rückmeldung nach dem bestätigten Speichern des Kaufs
    State.onNotify(function(payload: any)
        if type(payload) ~= "table" or payload.kind ~= "seasonPassBought" then
            return
        end
        if payload.duplicate == true then
            local gems = if type(payload.gems) == "number" then payload.gems else 0
            showMessage(`Du hattest den Pass schon: {gems} Gems gutgeschrieben.`, ACCENT_COLOR)
        else
            showMessage("Premium-Spur freigeschaltet!", ACCENT_COLOR)
        end
    end)

    ProductPrices.onChanged(function()
        if pass ~= nil then
            renderBuy()
        end
    end)
end

return SeasonPassMenu
