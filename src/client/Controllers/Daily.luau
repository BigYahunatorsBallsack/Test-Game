--!strict
-- Daily-Controller (Paket 5.1)
-- Knopf "Täglich" in der Menüleiste und Fenster mit den sieben Tagen der Serie. Der Server
-- entscheidet Tag, Serie und Belohnung (Remote ClaimDaily, ohne Argumente, Snapshot-Feld `daily`).
-- Der Client zeigt nur an und zählt die Zeit bis zum nächsten Tag lokal herunter.
--
-- Von selbst öffnet sich das Fenster einmal je Sitzung, wenn abgeholt werden kann, aber nie während
-- Tutorial, Reveal oder eines anderen offenen Fensters. Tag 7 mit Kiste spielt den Reveal des
-- Kisten-Fensters ab (CrateShop.playReveal), der Ersatzgegenstand zeigt nur eine Meldung.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Menüleiste und Fenster
local MENU_ORDER = 7 -- nach Zonen, Sammlung, Sandsturm, Kisten, Gems und Ausrüstung
local FOOTER_HEIGHT = 110
local ROW_HEIGHT = 44
local ROW_GAP = 6
local INTRO_HEIGHT = 44
local MESSAGE_SECONDS = 4
local AUTO_OPEN_CHECK_SECONDS = 1
local CLAIM_COOLDOWN_SECONDS = 2.2 -- etwas länger als das Server-Limit (1 Aufruf je 2 s)
local COUNTDOWN_TICK_SECONDS = 0.5

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local ROW_COLOR = Color3.fromRGB(64, 52, 40)
local TODAY_COLOR = Color3.fromRGB(96, 78, 44)
local DONE_COLOR = Color3.fromRGB(48, 70, 48)
local TEXT_COLOR = Color3.fromRGB(255, 248, 230)
local MUTED_COLOR = Color3.fromRGB(190, 175, 150)
local ACCENT_COLOR = Color3.fromRGB(255, 190, 90)
local WARN_COLOR = Color3.fromRGB(235, 150, 90)
local BUTTON_COLOR = Color3.fromRGB(110, 150, 70)
local BUTTON_OFF_COLOR = Color3.fromRGB(80, 66, 52)

local REASONS: { [string]: string } = {
    notStarted = "Die tägliche Belohnung startet, sobald du die Schaufel gekauft hast.",
    alreadyClaimed = "Heute schon abgeholt. Komm morgen wieder.",
    policyPending = "Einen Moment, bitte gleich noch einmal versuchen.",
    busy = "Einen Moment, bitte gleich noch einmal versuchen.",
    noProfile = "Dein Spielstand wird noch geladen.",
    error = "Das hat nicht geklappt. Bitte versuche es gleich noch einmal.",
    unknown = "Das hat nicht geklappt. Bitte versuche es gleich noch einmal.",
}

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local EconomyData = loadShared("Data", "Economy")
local Crates = loadShared("Data", "Crates")
local CrateItems = loadShared("Data", "CrateItems")
local TutorialLogic = loadShared("Logic", "Tutorial")
local State = require(script.Parent:WaitForChild("State") :: ModuleScript) :: any
local Screen = require(script.Parent:WaitForChild("Screen") :: ModuleScript) :: any
local Reveal = require(script.Parent:WaitForChild("Reveal") :: ModuleScript) :: any
local CrateShop = require(script.Parent:WaitForChild("CrateShop") :: ModuleScript) :: any

local Daily = {}

local player = Players.LocalPlayer

local function minutesText(seconds: number): string
    return `{math.max(math.floor(seconds / 60 + 0.5), 1)} Minuten`
end

-- Text einer Belohnung aus den Daten (Economy.daily) oder aus der Antwort des Servers.
local function rewardText(reward: any, forDisplay: boolean): string
    local kind = if type(reward) == "table" then reward.kind else nil
    if kind == "coinBoost" then
        return `2x Münzen, {minutesText(reward.seconds)}`
    elseif kind == "luck" then
        return `Glücks-Boost x2, {minutesText(reward.seconds)}`
    elseif kind == "gems" then
        local amount = if type(reward.amount) == "number" then reward.amount else 0
        if not forDisplay and reward.capped == true then
            return "Gems (dein Gem-Konto ist voll)"
        end
        return `{amount} Gems`
    elseif kind == "crate" then
        local crate = Crates.byId[reward.crateId]
        local name = if crate ~= nil then crate.name else "Kiste"
        return `{name} gratis`
    elseif kind == "fixedItem" then
        local item = CrateItems.byId[reward.itemId]
        return if item ~= nil then `{item.name} (Ersatz für die Kiste)` else "Ersatzgegenstand"
    end
    return "?"
end

local function clockText(seconds: number): string
    local total = math.max(math.ceil(seconds), 0)
    return string.format("%d:%02d:%02d", total // 3600, (total % 3600) // 60, total % 60)
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

function Daily.Init() end

function Daily.Start()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local claimDaily = remotes:WaitForChild("ClaimDaily") :: RemoteFunction

    local window = Screen.createWindow({
        name = "DailyWindow",
        title = "Tägliche Belohnung",
        kind = "narrow",
        footerHeight = FOOTER_HEIGHT,
    })
    local openButton = Screen.addMenuButton("DailyButton", "Täglich", MENU_ORDER)
    openButton.Visible = false -- erst, wenn die Serie gestartet ist
    openButton.Activated:Connect(window.toggle)

    -- Fuß: Zeit oder Meldung und der Knopf "Abholen"
    local statusLabel = newLabel(window.footer, "Status", UDim2.new(0, 12, 0, 4), UDim2.new(1, -24, 0, 44), Enum.Font.GothamBold, MUTED_COLOR, "")
    local claimButton = Instance.new("TextButton")
    claimButton.Name = "Claim"
    claimButton.Position = UDim2.new(0, 12, 0, 54)
    claimButton.Size = UDim2.new(1, -24, 0, 46)
    claimButton.Font = Enum.Font.GothamBold
    claimButton.TextColor3 = TEXT_COLOR
    claimButton.TextScaled = true
    claimButton.Text = "Abholen"
    claimButton.BackgroundColor3 = BUTTON_OFF_COLOR
    claimButton.Parent = window.footer
    Instance.new("UICorner").Parent = claimButton

    newLabel(window.body, "Intro", UDim2.new(), UDim2.new(1, 0, 0, INTRO_HEIGHT), Enum.Font.Gotham, MUTED_COLOR, "Hol jeden Tag deine Belohnung ab. Ein ausgelassener Tag setzt die Serie auf Tag 1 zurück. Der Tag wechselt um 0 Uhr Weltzeit (UTC).").LayoutOrder = 0

    -- Zeilen: je Tag eine
    local rows: { { frame: Frame, mark: TextLabel } } = {}
    local days: { any } = {}
    for index, reward in EconomyData.daily.days do
        days[index] = reward
    end
    days[7] = EconomyData.daily.day7
    for day = 1, 7 do
        local frame = Instance.new("Frame")
        frame.Name = `Day{day}`
        frame.LayoutOrder = day
        frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
        frame.BackgroundColor3 = ROW_COLOR
        frame.BackgroundTransparency = 0.2
        frame.Parent = window.body
        Instance.new("UICorner").Parent = frame
        newLabel(frame, "Day", UDim2.new(0, 10, 0.15, 0), UDim2.new(0, 56, 0.7, 0), Enum.Font.GothamBold, ACCENT_COLOR, `Tag {day}`)
        local text = rewardText(days[day], true)
        if day == 7 then
            local fallback = CrateItems.byId[EconomyData.daily.day7FallbackItemId]
            if fallback ~= nil then
                text = `{text} (wo Kisten gesperrt sind: {fallback.name})`
            end
        end
        newLabel(frame, "Reward", UDim2.new(0, 72, 0.08, 0), UDim2.new(1, -120, 0.84, 0), Enum.Font.Gotham, TEXT_COLOR, text)
        local mark = newLabel(frame, "Mark", UDim2.new(1, -40, 0.1, 0), UDim2.new(0, 32, 0.8, 0), Enum.Font.GothamBold, ACCENT_COLOR, "")
        mark.TextXAlignment = Enum.TextXAlignment.Center
        rows[day] = { frame = frame, mark = mark }
    end
    -- Platz im Rhythmus der Liste: die Zeilen stehen in `window.body` unter dem Intro.
    local listPadding = window.body:FindFirstChildOfClass("UIListLayout")
    if listPadding ~= nil then
        listPadding.Padding = UDim.new(0, ROW_GAP)
    end

    -- Zustand vom Server mit lokalem Ende der Wartezeit
    local daily: any = nil
    local endsAt = 0 -- os.clock, wann der nächste Tag beginnt (nur wenn nicht abholbar)
    local busy = false
    local lastClaimAt = -math.huge
    local autoOpened = false
    local tutorialStep = 1
    local messageUntil = 0 -- bis dahin bleibt eine Meldung im Fuß stehen

    local function showMessage(text: string)
        messageUntil = os.clock() + MESSAGE_SECONDS
        statusLabel.Text = text
        statusLabel.TextColor3 = WARN_COLOR
    end

    local function canClaimNow(): boolean
        if daily == nil or daily.started ~= true then
            return false
        end
        return daily.canClaim == true or (endsAt > 0 and os.clock() >= endsAt)
    end

    local function render()
        local started = daily ~= nil and daily.started == true
        local claimable = canClaimNow()
        openButton.Visible = started
        openButton.Text = if claimable then "Täglich •" else "Täglich"
        if daily == nil then
            return
        end
        local day = if type(daily.day) == "number" then daily.day else 1
        local streak = if type(daily.streak) == "number" then daily.streak else 0
        for index = 1, 7 do
            local done = if daily.canClaim == true then index < day else index <= streak
            local today = claimable and index == day
            local row = rows[index]
            row.frame.BackgroundColor3 = if today then TODAY_COLOR elseif done then DONE_COLOR else ROW_COLOR
            row.mark.Text = if done then "✓" elseif today then "▶" else ""
        end
        claimButton.BackgroundColor3 = if claimable then BUTTON_COLOR else BUTTON_OFF_COLOR
        claimButton.Text = if claimable then "Abholen" else "Heute abgeholt"
        if os.clock() >= messageUntil then
            statusLabel.TextColor3 = MUTED_COLOR
            if claimable then
                statusLabel.Text = `Tag {day} wartet auf dich.`
            elseif started then
                statusLabel.Text = `Nächste Belohnung in {clockText(endsAt - os.clock())}.`
            else
                statusLabel.Text = REASONS.notStarted
            end
        end
    end

    State.onChanged(function(snapshot: any)
        tutorialStep = if type(snapshot.tutorialStep) == "number" then snapshot.tutorialStep else 1
        local entry = snapshot.daily
        if type(entry) ~= "table" then
            return
        end
        daily = entry
        local seconds = if type(entry.secondsLeft) == "number" and entry.secondsLeft == entry.secondsLeft then math.max(entry.secondsLeft, 0) else 0
        endsAt = if entry.canClaim == true or seconds <= 0 then 0 else os.clock() + seconds
        render()
    end)

    task.spawn(function()
        while true do
            task.wait(COUNTDOWN_TICK_SECONDS)
            if daily ~= nil and window.isOpen() then
                render()
            end
        end
    end)

    -- Abholen
    claimButton.Activated:Connect(function()
        if busy or os.clock() - lastClaimAt < CLAIM_COOLDOWN_SECONDS then
            return
        end
        if not canClaimNow() then
            showMessage(if daily ~= nil and daily.started == true then REASONS.alreadyClaimed else REASONS.notStarted)
            return
        end
        busy = true
        lastClaimAt = os.clock()
        local ok, reply = pcall(function(): any
            return claimDaily:InvokeServer()
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
        -- Der Snapshot des Servers folgt; bis dahin zeigt der Knopf schon "abgeholt".
        if daily ~= nil then
            daily = table.clone(daily)
            daily.canClaim = false
            daily.secondsLeft = 0
            endsAt = os.clock() + (86400 - os.time() % 86400) -- nur Anzeige bis zum Snapshot (0 Uhr UTC)
            daily.streak = if type(reply.day) == "number" then reply.day else daily.streak
        end
        local reward = reply.reward
        if type(reward) == "table" and reward.kind == "crate" and type(reply.crate) == "table" then
            window.close()
            if not CrateShop.playReveal(reply.crate) then
                showMessage("Abgeholt: Eisenkiste. Du findest den Gewinn in deinen Items.")
            end
        else
            showMessage(`Abgeholt: {rewardText(reward, false)}`)
            statusLabel.TextColor3 = ACCENT_COLOR
        end
        render()
    end)

    -- Von selbst öffnen: einmal je Sitzung, nie bei Tutorial, Reveal oder offenem Fenster.
    task.spawn(function()
        while not autoOpened do
            task.wait(AUTO_OPEN_CHECK_SECONDS)
            if daily ~= nil and daily.started == true and daily.canClaim == true
                and tutorialStep > TutorialLogic.count()
                and not Reveal.isBusy() and not CrateShop.isRevealing()
                and not Screen.isAnyWindowOpen() then
                autoOpened = true
                window.open()
            end
        end
    end)

    -- Der Spieler kann das Fenster schon vorher selbst geöffnet haben: dann zählt es als gesehen.
    openButton.Activated:Connect(function()
        autoOpened = true
    end)
end

return Daily
