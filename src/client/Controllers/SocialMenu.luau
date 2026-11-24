--!strict
-- Freunde-Menü (Paket 5.7): Reiter "Rangliste" (Wochenfortschritt der Sammlung) und "Besuchen"
-- (Sammlung eines Freundes ansehen). Der Server entscheidet alles: GetLeaderboard und GetFriends
-- haben keine Argumente, ViewCollection nennt nur einen Platz aus der Liste, die der Server für den
-- Spieler gebaut hat (nie einen Spieler). Der Client zeigt nur an. Der Freunde-Bonus selbst steckt im
-- Münz-Faktor, den der Server im Zustand mitschickt (Sand.setFriendFactor), hier steht nur ein Hinweis.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Menüleiste und Fenster
local MENU_ORDER = 10 -- nach Zonen, Sammlung, Sandsturm, Kisten, Gems, Ausrüstung, Täglich, Code und Saison
local TAB_STRIP_HEIGHT = 44
local ROW_HEIGHT = 40
local HEADER_HEIGHT = 60
local MESSAGE_HEIGHT = 44
local REQUEST_COOLDOWN_SECONDS = 5.2 -- etwas länger als das Server-Limit (1 Aufruf je 5 s)
local VIEW_COOLDOWN_SECONDS = 2.2 -- Server-Limit 1 Aufruf je 2 s

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local ROW_COLOR = Color3.fromRGB(64, 52, 40)
local YOU_COLOR = Color3.fromRGB(96, 78, 44)
local DONE_COLOR = Color3.fromRGB(48, 70, 48)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local ACCENT_COLOR = Color3.fromRGB(255, 190, 90)
local WARN_COLOR = Color3.fromRGB(235, 150, 90)
local TAB_ON_COLOR = Color3.fromRGB(110, 150, 70)
local TAB_OFF_COLOR = Color3.fromRGB(80, 66, 52)

local REASONS: { [string]: string } = {
    notFriend = "Diese Person ist nicht in deiner Freundesliste. Lade die Liste neu.",
    noShowcase = "Diese Sammlung ist noch nicht freigegeben. Die Person muss erst einmal im Spiel gewesen sein.",
    busy = "Einen Moment, bitte gleich noch einmal versuchen.",
    error = "Das hat nicht geklappt. Bitte versuche es gleich noch einmal.",
    unknown = "Das hat nicht geklappt. Bitte versuche es gleich noch einmal.",
}

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local FindsData = loadShared("Data", "Finds")
local SocialData = loadShared("Data", "Social")
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any

local SocialMenu = {}

local function newLabel(parent: Instance, text: string, font: Enum.Font, color: Color3, order: number, height: number): TextLabel
    local label = Instance.new("TextLabel")
    label.LayoutOrder = order
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 0, height)
    label.Font = font
    label.TextColor3 = color
    label.TextScaled = true
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = text
    label.Parent = parent
    return label
end

local function addRow(parent: Instance, order: number, color: Color3, left: string, right: string, rightColor: Color3?): TextButton
    local row = Instance.new("TextButton")
    row.AutoButtonColor = false
    row.Text = ""
    row.LayoutOrder = order
    row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
    row.BackgroundColor3 = color
    row.BackgroundTransparency = 0.2
    row.Parent = parent
    Instance.new("UICorner").Parent = row
    local leftLabel = newLabel(row, left, Enum.Font.GothamBold, TEXT_COLOR, 1, ROW_HEIGHT)
    leftLabel.Position = UDim2.new(0, 10, 0, 0)
    leftLabel.Size = UDim2.new(0.65, -10, 1, 0)
    local rightLabel = newLabel(row, right, Enum.Font.GothamBold, rightColor or ACCENT_COLOR, 2, ROW_HEIGHT)
    rightLabel.Position = UDim2.new(0.65, 0, 0, 0)
    rightLabel.Size = UDim2.new(0.35, -10, 1, 0)
    rightLabel.TextXAlignment = Enum.TextXAlignment.Right
    return row
end

local function valueText(value: any): string
    if type(value) ~= "number" or value ~= value then
        return "0"
    end
    return tostring(math.floor(value))
end

function SocialMenu.Init() end

function SocialMenu.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local getLeaderboard = remotes:WaitForChild("GetLeaderboard") :: RemoteFunction
    local getFriends = remotes:WaitForChild("GetFriends") :: RemoteFunction
    local viewCollection = remotes:WaitForChild("ViewCollection") :: RemoteFunction

    local tab = "board" -- "board" oder "visit"
    local busy = false
    local lastRequestAt: { [string]: number } = {} -- je Remote eine Zeitsperre
    local lastReply: { [string]: any } = {} -- letzte Antwort je Remote, wird bei einer Sperre erneut gezeigt
    local friendFactor = 1
    local render: () -> () = function() end

    local window = Screen.createWindow({
        name = "SocialWindow",
        title = "Freunde",
        kind = "narrow",
        subHeight = TAB_STRIP_HEIGHT,
        onOpen = function()
            render()
        end,
    })
    local openButton = Screen.addMenuButton("SocialButton", "Freunde", MENU_ORDER)
    openButton.Activated:Connect(window.toggle)

    local function newTab(text: string, x: number): TextButton
        local button = Instance.new("TextButton")
        button.Position = UDim2.new(x, 0, 0, 4)
        button.Size = UDim2.new(0.5, -4, 1, -8)
        button.Font = Enum.Font.GothamBold
        button.TextColor3 = TEXT_COLOR
        button.TextScaled = true
        button.Text = text
        button.Parent = window.sub
        Instance.new("UICorner").Parent = button
        return button
    end
    local boardTab = newTab("Rangliste", 0)
    local visitTab = newTab("Besuchen", 0.5)

    local body = window.body
    local function clear()
        for _, child in body:GetChildren() do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                child:Destroy()
            end
        end
    end

    local function showMessage(text: string)
        clear()
        newLabel(body, text, Enum.Font.GothamBold, WARN_COLOR, 1, MESSAGE_HEIGHT)
    end

    local function bonusLine(): string
        if friendFactor > 1.0001 then
            return `Freunde-Bonus: x{string.format("%.2f", friendFactor)} Münzen, solange deine Freunde im Server sind.`
        end
        local cfg = SocialData.friends
        return `Freunde-Bonus: {cfg.perFriendBp / 100} % mehr Münzen je Freund im selben Server, höchstens {cfg.maxBp / 100} %.`
    end

    -- Rangliste
    local function showBoard(reply: any)
        clear()
        newLabel(body, bonusLine(), Enum.Font.Gotham, MUTED_COLOR, 1, HEADER_HEIGHT)
        if type(reply) ~= "table" or reply.ok ~= true then
            newLabel(body, REASONS.error, Enum.Font.GothamBold, WARN_COLOR, 2, MESSAGE_HEIGHT)
            return
        end
        local hours = if type(reply.secondsLeft) == "number" then math.floor(reply.secondsLeft / 3600) else 0
        newLabel(body, `Größter Zuwachs der Woche (Wert neuer Funde). Neue Woche in {hours} Std.`, Enum.Font.GothamBold, ACCENT_COLOR, 2, MESSAGE_HEIGHT)
        local order = 3
        if type(reply.entries) == "table" then
            for _, entry in reply.entries do
                if type(entry) == "table" then
                    addRow(body, order, if entry.you == true then YOU_COLOR else ROW_COLOR, `{valueText(entry.rank)}. {tostring(entry.name)}`, valueText(entry.value))
                    order += 1
                end
            end
        end
        local you = if type(reply.you) == "table" then reply.you else {}
        local rank = if type(you.rank) == "number" then `Platz {valueText(you.rank)}` else "nicht in den Top"
        addRow(body, order, YOU_COLOR, `Du: {rank}`, valueText(you.value))
        if order == 3 then
            newLabel(body, "Noch niemand in der Liste. Die Liste füllt sich, sobald Spieler ihre Sammlung gespeichert haben.", Enum.Font.Gotham, MUTED_COLOR, order + 1, MESSAGE_HEIGHT)
        end
    end

    -- Ruft eine Remote auf, höchstens einmal je Sperrzeit. Ist sie noch gesperrt, zeigt das Menü die letzte
    -- Antwort erneut (statt "Lade ..." stehen zu lassen). `cache` = false für Besuche (immer frisch).
    local function request(key: string, call: () -> any, cooldown: number, onReply: (any) -> (), cache: boolean)
        if busy then
            return
        end
        if os.clock() - (lastRequestAt[key] or -math.huge) < cooldown then
            if cache and lastReply[key] ~= nil then
                onReply(lastReply[key])
            end
            return
        end
        busy = true
        lastRequestAt[key] = os.clock()
        task.spawn(function()
            local ok, reply = pcall(call)
            busy = false
            if not ok then
                showMessage(REASONS.error)
                return
            end
            if cache then
                lastReply[key] = reply
            end
            onReply(reply)
        end)
    end

    -- Sammlung eines Freundes
    local function showView(view: any)
        clear()
        if type(view) ~= "table" then
            showMessage(REASONS.error)
            return
        end
        newLabel(body, `{tostring(view.name)}: {valueText(view.found)} von {valueText(view.total)} Fundstücken, Wert {valueText(view.value)}`, Enum.Font.GothamBold, ACCENT_COLOR, 1, HEADER_HEIGHT)
        local order = 2
        if type(view.sets) == "table" then
            for _, set in view.sets do
                if type(set) == "table" then
                    local info = FindsData.setsById[set.setId]
                    local name = if info ~= nil then info.name else "?"
                    addRow(body, order, if set.complete == true then DONE_COLOR else ROW_COLOR, name, `{valueText(set.have)}/{valueText(set.size)}{if set.complete == true then " ✓" else ""}`)
                    order += 1
                end
            end
        end
        local back = addRow(body, order, TAB_OFF_COLOR, "Zurück zur Liste", "")
        back.Activated:Connect(function()
            render()
        end)
    end

    local function showFriends(reply: any)
        clear()
        if type(reply) ~= "table" or reply.ok ~= true then
            local reason = if type(reply) == "table" and type(reply.reason) == "string" then reply.reason else "unknown"
            newLabel(body, REASONS[reason] or REASONS.unknown, Enum.Font.GothamBold, WARN_COLOR, 1, MESSAGE_HEIGHT)
            return
        end
        newLabel(body, "Tippe auf einen Freund, um seine Sammlung zu sehen. Du siehst nur Freunde, und nur ansehen, nichts tauschen.", Enum.Font.Gotham, MUTED_COLOR, 1, HEADER_HEIGHT)
        local order = 2
        if type(reply.friends) == "table" then
            for _, friend in reply.friends do
                if type(friend) == "table" and type(friend.slot) == "number" then
                    local slot = friend.slot
                    local row = addRow(body, order, ROW_COLOR, tostring(friend.name), "ansehen")
                    row.Activated:Connect(function()
                        request("view", function(): any
                            return viewCollection:InvokeServer(slot)
                        end, VIEW_COOLDOWN_SECONDS, function(result: any)
                            if type(result) == "table" and result.ok == true then
                                showView(result.view)
                            else
                                local reason = if type(result) == "table" and type(result.reason) == "string" then result.reason else "unknown"
                                showMessage(REASONS[reason] or REASONS.unknown)
                            end
                        end, false)
                    end)
                    order += 1
                end
            end
        end
        if order == 2 then
            newLabel(body, "Keine Freunde gefunden.", Enum.Font.Gotham, MUTED_COLOR, order, MESSAGE_HEIGHT)
        end
    end

    render = function()
        boardTab.BackgroundColor3 = if tab == "board" then TAB_ON_COLOR else TAB_OFF_COLOR
        visitTab.BackgroundColor3 = if tab == "visit" then TAB_ON_COLOR else TAB_OFF_COLOR
        showMessage("Lade ...")
        if tab == "board" then
            request("board", function(): any
                return getLeaderboard:InvokeServer()
            end, REQUEST_COOLDOWN_SECONDS, showBoard, true)
        else
            request("friends", function(): any
                return getFriends:InvokeServer()
            end, REQUEST_COOLDOWN_SECONDS, showFriends, true)
        end
    end

    boardTab.Activated:Connect(function()
        tab = "board"
        render()
    end)
    visitTab.Activated:Connect(function()
        tab = "visit"
        render()
    end)

    -- Den Freunde-Faktor stecken die Server-Zustände im Münz-Faktor; der Hinweis zeigt ihn nur an.
    State.onChanged(function(snapshot: any)
        local factor = if type(snapshot.friendFactor) == "number" then snapshot.friendFactor else 1
        friendFactor = factor
    end)

end

return SocialMenu
