--!strict
-- The host supplies the canonical catalogue, current wallet and its existing purchase action.
-- Trial ownership, variants and money exist only in this UI instance.
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Input = game:GetService("UserInputService")
local Art = require(script.Art)
local Catalog = require(script.Catalog)
local Navigation = require(script.Navigation)
local Preview = require(script.Preview)
local SearchPanel = require(script.SearchPanel)
local VariantPanel = require(script.VariantPanel)
local UnlockFX = require(script.UnlockFX)
local StudyPlan = require(script.StudyPlan)
local MapView = require(script.MapView)
local Trial = require(script.Trial)
local TrialPanel = require(script.TrialPanel)
local DeviceStatsView = require(script.DeviceStatsView)
local Workshop = {}
local C = Art.c
local big = { ability = true, variant = true, mastery = true, keystone = true, equipment = true }
local kinds = {
    ability = "Fähigkeit",
    variant = "Ausrüstbare Variante",
    mastery = "Meisterschaft",
    keystone = "Spezialisierung",
    passive = "Werkzeugwert",
    modifier = "Verstärkung",
    equipment = "Werkzeugstufe",
    grant = "Sturmbelohnung",
    upgrade = "Ausbau",
}
local stateNames = {
    owned = "Gelernt",
    active = "Ausgerüstet",
    ready = "Lernbar",
    dear = "Zu wenig Münzen",
    locked = "Voraussetzung fehlt",
    grant = "Sturmbelohnung",
}
local marks =
    { owned = "✓", active = "◆", ready = "+", dear = "₵", locked = "·", grant = "✦" }
local colors = {
    owned = C.brass,
    active = C.leaf,
    ready = C.bright,
    dear = Color3.fromRGB(208, 145, 103),
    locked = C.lock,
    grant = C.leaf,
}
local function stateTextColor(state)
    return if state == "locked" then C.mute else colors[state]
end
local alternative = Color3.fromRGB(216, 159, 89)
local directions = {
    [Enum.KeyCode.Left] = Vector2.new(-1, 0),
    [Enum.KeyCode.Right] = Vector2.new(1, 0),
    [Enum.KeyCode.Up] = Vector2.new(0, -1),
    [Enum.KeyCode.Down] = Vector2.new(0, 1),
    [Enum.KeyCode.DPadLeft] = Vector2.new(-1, 0),
    [Enum.KeyCode.DPadRight] = Vector2.new(1, 0),
    [Enum.KeyCode.DPadUp] = Vector2.new(0, -1),
    [Enum.KeyCode.DPadDown] = Vector2.new(0, 1),
}
local switches = {
    [Enum.KeyCode.PageUp] = -1,
    [Enum.KeyCode.PageDown] = 1,
    [Enum.KeyCode.ButtonL1] = -1,
    [Enum.KeyCode.ButtonR1] = 1,
}
local function gamepad(inputType: Enum.UserInputType): boolean
    return string.find(inputType.Name, "Gamepad", 1, true) ~= nil
end
local nextMount = 0
local function scroll(parent, name)
    local v = Instance.new("ScrollingFrame")
    v.Name = name
    v.BorderSizePixel = 0
    v.BackgroundTransparency = 1
    v.Active = true
    v.ScrollBarImageColor3 = C.brass
    v.ScrollBarThickness = 5
    v.CanvasSize = UDim2.new()
    v.ZIndex = parent.ZIndex + 1
    v.Parent = parent
    return v
end
local function reduced()
    return GuiService.ReducedMotionEnabled
end
local function scaleIn(obj, from, duration)
    if reduced() then
        return
    end
    local v = obj:FindFirstChild("PopScale") or Instance.new("UIScale")
    v.Name = "PopScale"
    v.Parent = obj
    v.Scale = from
    TweenService:Create(
        v,
        TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Scale = 1 }
    ):Play()
end
local function row(parent, obj, height)
    obj.Size = UDim2.new(1, -16, 0, height)
    obj.LayoutOrder = #parent:GetChildren()
    return obj
end
local function readable(value)
    local reversed = string.reverse(tostring(math.floor(value)))
    return (string.reverse((string.gsub(reversed, "(%d%d%d)", "%1."))):gsub("^%.", ""))
end

function Workshop.mount(gui, config)
    nextMount += 1
    local actionName = "ELGWorkshopNavigation" .. nextMount
    local book = Catalog.build(config.baseNodes)
    local root = Art.box(gui, "Werkstatt", C.ink, 100)
    root.Size = UDim2.fromScale(1, 1)
    root.Visible = false
    root.Active = true
    local header = Art.box(root, "Messingleiste", Color3.new(1, 1, 1), 101)
    Art.gradient(header, C.wood, C.dark)
    Art.surface(header, "wood", 0.27)
    local headerEdge = Art.box(header, "Fassung", C.wood, 102)
    headerEdge.Position = UDim2.new(0, 0, 1, -4)
    headerEdge.Size = UDim2.new(1, 0, 0, 4)
    Art.surface(headerEdge, "brass", 0.13)
    local titlePlate = Art.box(header, "Titelplatte", C.ink, 102)
    Art.round(titlePlate, 6)
    Art.edge(titlePlate, C.brass, 1.5)
    Art.round(Art.surface(titlePlate, "steel", 0.39), 6)
    for _, side in { 0, 1 } do
        local rivet = Art.box(titlePlate, "Niete", C.brass, 103)
        rivet.AnchorPoint = Vector2.new(0.5, 0.5)
        rivet.Position = UDim2.new(side, if side == 0 then 6 else -6, 0.5, 0)
        rivet.Size = UDim2.fromOffset(5, 5)
        Art.round(rivet, 3)
        Art.gradient(rivet, C.bright, C.wood)
    end
    local title = Art.text(header, "Title", "WERKSTATT", 30, C.bright, true)
    title.ZIndex = 103
    title.Font = Enum.Font.Antique
    local controlsHint = Art.text(header, "Tasten", "", 12, C.mute, false)
    controlsHint.TextXAlignment = Enum.TextXAlignment.Center
    local wallet = Art.text(header, "Wallet", "", 15, C.ivory, true)
    wallet.TextXAlignment = Enum.TextXAlignment.Right
    local mode = Art.button(header, "Mode", "Probelauf")
    local exit = Art.button(header, "Close", "×")
    exit.Modal = true
    exit.TextSize = 26
    local nav = scroll(root, "Werkzeuge")
    nav.ScrollingDirection = Enum.ScrollingDirection.X
    nav.ScrollBarThickness = 3
    local mapWrap = Art.box(root, "Tafel", C.board, 101)
    mapWrap.ClipsDescendants = true
    Art.edge(mapWrap, C.brass, 2)
    Art.surface(mapWrap, "chart", 0.13)
    local mapBar = Art.box(mapWrap, "Werkzeugleiste", C.panel, 120)
    Art.surface(mapBar, "steel", 0.28)
    local divider = Art.box(mapBar, "Kante", C.brass, 121)
    divider.Position = UDim2.new(0, 0, 1, -1)
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.BackgroundTransparency = 0.3
    local tabTitle = Art.text(mapBar, "Gerät", "", 18, C.ivory, true)
    local progress = Art.text(mapBar, "Fortschritt", "", 11, C.mute, true)
    local overviewButton = Art.button(mapBar, "Uebersicht", "Übersicht")
    local searchButton = Art.button(mapBar, "Suche", "Suche")
    local zoomOut = Art.button(mapBar, "ZoomOut", "−")
    local zoomIn = Art.button(mapBar, "ZoomIn", "+")
    local legacy = Art.button(nav, "Laufbaum", "Laufbaum")
    legacy.Visible = config.onLegacy ~= nil
    local map = scroll(mapWrap, "Karte")
    map.ScrollingDirection = Enum.ScrollingDirection.XY
    map.ElasticBehavior = Enum.ElasticBehavior.Never
    local sheet = Art.box(map, "Diagramm", nil, 103)
    local unlockFX = UnlockFX.mount(mapWrap, sheet)
    local mapScale = Instance.new("UIScale")
    mapScale.Parent = sheet
    local detail = Art.box(root, "Detail", C.panel, 130)
    Art.edge(detail, C.brass, 2)
    detail.ClipsDescendants = true
    Art.surface(detail, "steel", 0.35)
    local detailScroll = scroll(detail, "Inhalt")
    detailScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    detailScroll.ScrollBarThickness = 4
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 9)
    layout.Parent = detailScroll
    local inset = Instance.new("UIPadding")
    inset.PaddingTop = UDim.new(0, 8)
    inset.PaddingLeft = UDim.new(0, 8)
    inset.PaddingBottom = UDim.new(0, 14)
    inset.Parent = detailScroll
    local handle = Art.button(detail, "DetailToggle", "")
    handle.TextXAlignment = Enum.TextXAlignment.Center
    local tone = Instance.new("Sound")
    tone.SoundId = "rbxasset://sounds/volume_slider.ogg"
    tone.Volume = 0.16
    tone.Parent = root
    local function sound(pitch)
        tone:Stop()
        tone.PlaybackSpeed = pitch
        tone:Play()
    end
    local tabs, entries, edges, shortcutStates = {}, {}, {}, {}
    local selected, page = nil, book.byTab.hand
    local owned, coins, walletText = {}, 0, "0"
    local gates = {}
    for _, device in book.devices do
        table.insert(gates, device.gate)
    end
    local training = config.trialOnly == true
    local trial: Trial.Run? = if training then Trial.start("all", owned, coins, gates) else nil
    local zoom = 1
    local overview = false
    local mapViewport = Vector2.zero
    local savedViews: { [string]: { zoom: number, center: Vector2 } } = {}
    local dragStart: Vector2?
    local dragOrigin = Vector2.zero
    local pinch: { zoom: number, world: Vector2 }?
    local compact = false
    local expanded = false
    local activePreview = nil
    local renderedStatus = nil
    local busy = false
    local pin = nil
    local planTarget: string? = nil
    local statsOpen = false
    local lastSelected = {}
    local pendingFeedback = ""
    local dragUntil = 0
    local renderPage, renderDetail, updateStates, position, changeTab, selectNode, setZoom
    local dialogOpen = false
    local search
    local comparison
    local trialMenu
    local compareButton: TextButton? = nil
    local api = {}

    local function learned(id)
        return id == "start" or (if training and trial then trial.owned[id] else owned[id]) == true
    end
    local function status(n)
        if learned(n.id) then
            return if training
                    and trial
                    and trial.variants[n.device or ""] == n.id
                then "active"
                else "owned"
        end
        if n.granted then
            return "grant"
        end
        for _, id in n.requires do
            if not learned(id) then
                return "locked"
            end
        end
        if #n.requiresAny > 0 then
            local one = false
            for _, id in n.requiresAny do
                if learned(id) then
                    one = true
                    break
                end
            end
            if not one then
                return "locked"
            end
        end
        return if (if training and trial then trial.coins else coins) >= n.cost
            then "ready"
            else "dear"
    end
    local function stopPreview()
        if activePreview then
            activePreview.clear()
            activePreview = nil
        end
    end
    local function mapContent()
        return Vector2.new(Catalog.width, page.height) * mapScale.Scale
    end
    local function worldAt(point: Vector2)
        return MapView.worldAt(
            point,
            map.CanvasPosition,
            Vector2.new(sheet.Position.X.Offset, sheet.Position.Y.Offset),
            mapScale.Scale
        )
    end
    local function placeWorld(world: Vector2, anchor: Vector2)
        map.CanvasPosition = MapView.panAt(world, anchor, mapContent(), mapViewport, mapScale.Scale)
    end
    local function focusWorld(n)
        if not overview then
            placeWorld(Vector2.new(n.x, n.y), Vector2.new(mapViewport.X / 2, mapViewport.Y * 0.42))
        end
    end
    local function focusSelected()
        local entry = entries[selected]
        GuiService.SelectedObject = if overview
            then overviewButton
            elseif entry then entry.button
            else tabs[page.id]
    end
    local function focusDetail()
        local first: GuiButton? = nil
        for _, control in detailScroll:GetChildren() do
            if
                control:IsA("GuiButton")
                and control.Selectable
                and (not first or control.LayoutOrder < first.LayoutOrder)
            then
                first = control
            end
        end
        GuiService.SelectedObject = first or handle
    end
    local function updateHint()
        local inputType = Input:GetLastInputType()
        controlsHint.Visible = root.AbsoluteSize.X >= 1260
            and (inputType == Enum.UserInputType.Keyboard or gamepad(inputType))
        controlsHint.Text = if gamepad(inputType)
            then "Steuerkreuz · Knoten     LB / RB · Reiter     A · Details"
            else "Pfeile · Knoten     Bild ↑ / ↓ · Reiter     Enter · Details"
    end
    local function rememberView()
        if not overview and mapViewport.X > 0 then
            savedViews[page.id] = { zoom = zoom, center = worldAt(mapViewport / 2) }
        end
    end
    local function updateScrolling()
        map.ScrollingEnabled = not overview
            and not dialogOpen
            and not pinch
            and Input:GetLastInputType() == Enum.UserInputType.Touch
    end
    local function showDetailMap()
        if overview then
            overview = false
            local view = savedViews[page.id]
            setZoom(if view then view.zoom else 1)
            if view then
                placeWorld(view.center, mapViewport / 2)
            else
                placeWorld(Vector2.new(Catalog.width / 2, 0), Vector2.new(mapViewport.X / 2, 0))
            end
        end
    end
    local function jumpTo(target)
        planTarget = nil
        statsOpen = false
        showDetailMap()
        if target.page == page.id then
            selectNode(target, true, true)
        else
            expanded = true
            changeTab(target.page, target.id, true)
        end
    end
    local function tabFocus()
        local button = tabs[page.id]
        if button then
            nav.CanvasPosition = Vector2.new(
                math.max(
                    0,
                    button.Position.X.Offset - (nav.AbsoluteWindowSize.X - button.Size.X.Offset) / 2
                ),
                0
            )
        end
    end
    local function updateWallet()
        wallet.Text = if training and trial
            then readable(trial.coins) .. "  Testmünzen"
            else walletText .. "  Münzen"
        mode.Text = if training then "Testoptionen" else "Probelauf"
    end
    local function presentUnlock(n, before, after, equipped)
        local e = entries[n.id]
        if not e or dialogOpen then
            return
        end
        local nextNames, linked = {}, {}
        if not equipped then
            for _, section in book.tabs do
                for _, id in Navigation.newlyReachable(section.nodes, before, after) do
                    local node = book.byId[id]
                    if (training or node.live) and not node.granted then
                        table.insert(nextNames, node.name)
                        if
                            node.page == n.page
                            and (
                                table.find(node.requires, n.id)
                                or table.find(node.requiresAny, n.id)
                            )
                        then
                            table.insert(linked, node)
                        end
                    end
                end
            end
        end
        local major = big[n.kind] == true
        scaleIn(e.button, if major then 0.78 else 0.88, if major then 0.5 else 0.24)
        sound(if equipped then 1.23 elseif major then 1.36 else 1.15)
        unlockFX.show(n, nextNames, linked, major, equipped)
    end
    local function setTraining(active: boolean)
        unlockFX.clear()
        training = active
        pendingFeedback = ""
        updateStates()
        renderDetail(false)
    end
    local function openTrialMenu()
        trialMenu.open(if trial then trial.preset else nil, training)
    end
    local function act(n)
        if busy then
            return
        end
        if not training and not n.live then
            openTrialMenu()
            return
        end
        local state = status(n)
        if training and trial and state == "owned" and n.kind == "variant" then
            trial.variants[n.device] = n.id
            updateStates()
            renderDetail(false)
            presentUnlock(n, trial.owned, trial.owned, true)
            return
        end
        if state ~= "ready" then
            return
        end
        if training and trial then
            local before = table.clone(trial.owned)
            trial.coins -= n.cost
            trial.owned[n.id] = true
            if n.kind == "variant" and not trial.variants[n.device] then
                trial.variants[n.device] = n.id
            end
            updateStates()
            renderDetail(false)
            presentUnlock(n, before, trial.owned, false)
        elseif config.purchase then
            busy = true
            pendingFeedback = "Wird geprüft …"
            renderDetail(false)
            task.spawn(function()
                local ok, response = pcall(config.purchase, n.id)
                busy = false
                if selected == n.id then
                    pendingFeedback = if ok
                            and type(response) == "table"
                            and response.ok
                        then ""
                        else "Kauf nicht bestätigt. Prüfe Guthaben und Voraussetzungen."
                    if root.Visible then
                        renderDetail(false)
                    end
                end
            end)
        end
    end
    selectNode = function(n, center, openSheet)
        unlockFX.clear()
        planTarget = nil
        statsOpen = false
        showDetailMap()
        selected = n.id
        lastSelected[page.id] = n.id
        pendingFeedback = ""
        if compact and openSheet then
            expanded = true
        end
        position()
        updateStates()
        renderDetail(true)
        if center then
            focusWorld(n)
        end
        local entry = entries[n.id]
        if entry then
            scaleIn(entry.button, 0.93, 0.12)
        end
    end
    renderDetail = function(animate)
        stopPreview()
        compareButton = nil
        table.clear(shortcutStates)
        for _, obj in detailScroll:GetChildren() do
            if obj:IsA("GuiObject") then
                obj:Destroy()
            end
        end
        detailScroll.CanvasPosition = Vector2.zero
        local n = book.byId[selected]
        if not n then
            return
        end
        local st = status(n)
        renderedStatus = st
        handle.Text = (
            if statsOpen
                then "Gerätewerte"
                elseif planTarget then "Lernplan"
                elseif overview then "Ziele und Voraussetzungen"
                else n.name
        ) .. (if expanded then "   ▾" else "   ▴")
        if compact and not expanded then
            return
        end
        local function caption(key, str, h, size, color, bold)
            local l = Art.text(detailScroll, key, str, size, color, bold)
            row(detailScroll, l, h)
            return l
        end
        local function button(key, str, callback)
            local b = Art.button(detailScroll, key, str)
            row(detailScroll, b, 44)
            b.Activated:Connect(callback)
            return b
        end
        local function addDeviceActions()
            if page.variants then
                compareButton = button("Varianten", "Varianten vergleichen", function()
                    comparison.open(page)
                end)
                button("Geraetewerte", "Gerätewerte", function()
                    statsOpen = true
                    renderDetail(false)
                end)
            end
        end
        local function mapShortcut(target, key, label, context: string?)
            local line = button(key, "", function()
                jumpTo(target)
            end)
            local icon = Art.image(line, "Motiv")
            Art.rect(icon, 6, 5, 42, 42)
            Art.nodeIcon(icon, target)
            local text = Art.text(line, "Name", label, 13, C.ivory, true)
            text.Position = UDim2.fromOffset(54, 3)
            text.Size = UDim2.new(1, -62, 0, 24)
            local targetState = status(target)
            local state = Art.text(
                line,
                "Status",
                context or stateNames[targetState],
                11,
                if context then C.mute else stateTextColor(targetState),
                false
            )
            state.Position = UDim2.fromOffset(54, 26)
            state.Size = UDim2.new(1, -62, 0, 20)
            line.Size = UDim2.new(1, -16, 0, 52)
            if not context then
                shortcutStates[target.id] = state
            end
        end
        local function openPlan(id: string)
            planTarget = id
            renderDetail(false)
        end
        if statsOpen then
            DeviceStatsView.render(page, n, if training and trial then trial.owned else owned, {
                button = button,
                caption = caption,
                shortcut = mapShortcut,
                training = training,
                status = function(node)
                    return stateNames[status(node)]
                end,
                back = function()
                    statsOpen = false
                    renderDetail(false)
                end,
            })
            return
        end
        if planTarget then
            local goal = book.byId[planTarget]
            local plan = StudyPlan.find(
                book.byId,
                goal.id,
                if training and trial then trial.owned else owned
            )
            button("PlanZurueck", "Zurück zu den Details", function()
                planTarget = nil
                renderDetail(false)
            end)
            caption(
                "PlanTitel",
                "LERNPLAN  ·  " .. book.byTab[goal.page].name,
                24,
                12,
                C.leaf,
                true
            )
            local heading = caption("Knoten", goal.name, 40, 24, C.bright, true)
            heading.Font = Enum.Font.Antique
            if not plan or #plan.steps == 0 then
                caption(
                    "PlanStatus",
                    if plan
                        then "Ziel bereits gelernt."
                        else "Für dieses Ziel ist kein Lernweg verfügbar.",
                    50,
                    14,
                    C.ivory,
                    false
                )
                return
            end
            caption(
                "PlanKosten",
                readable(plan.cost)
                    .. (if training then " Testmünzen" else " Münzen")
                    .. "  ·  "
                    .. #plan.steps
                    .. (if #plan.steps == 1 then " Schritt" else " Schritte"),
                35,
                14,
                C.bright,
                true
            )
            if not training then
                for _, id in plan.steps do
                    if not book.byId[id].live then
                        caption(
                            "PlanModus",
                            "Neue Upgrades in diesem Lernplan sind im Probelauf verfügbar.",
                            43,
                            12,
                            C.mute,
                            false
                        )
                        break
                    end
                end
            end
            for _, id in plan.steps do
                local step = book.byId[id]
                local fee = if step.granted
                    then "Sturmbelohnung"
                    else readable(step.cost) .. (if training
                        then " Testmünzen"
                        else " Münzen")
                mapShortcut(
                    step,
                    "Schritt_" .. id,
                    step.name,
                    book.byTab[step.page].name .. "  ·  " .. fee
                )
            end
            return
        end
        if overview then
            local heading = caption("Knoten", page.name, 38, 25, C.bright, true)
            heading.Font = Enum.Font.Antique
            addDeviceActions()
            button(
                "Lernplan",
                if pin then "Lernplan zum gemerkten Ziel" else "Lernplan zur Auswahl",
                function()
                    openPlan(pin or n.id)
                end
            )
            if pin and pin ~= selected then
                local target = book.byId[pin]
                caption(
                    "Gemerkt",
                    "GEMERKT  ·  " .. book.byTab[target.page].name,
                    18,
                    12,
                    C.leaf,
                    true
                )
                mapShortcut(target, "ZumGemerkt", target.name)
            end
            caption(
                "Auswahl",
                if selected == pin then "GEMERKT" else "AUSGEWÄHLTES UPGRADE",
                18,
                12,
                C.leaf,
                true
            )
            mapShortcut(n, "ZurAuswahl", n.name)
            caption(
                "Pfad",
                "Türkis zeigt nötige Knoten. Bernstein markiert alternative Wege.",
                44,
                12,
                C.mute,
                false
            )
            local goals = {}
            for _, candidate in page.nodes do
                if (big[candidate.kind] or candidate.granted) and candidate.id ~= selected then
                    table.insert(goals, candidate)
                end
            end
            if #goals > 0 then
                table.sort(goals, function(a, b)
                    return if a.y == b.y then a.x < b.x else a.y < b.y
                end)
                caption("Ziele", "FÄHIGKEITEN UND MEILENSTEINE", 18, 12, C.leaf, true)
                for _, goal in goals do
                    mapShortcut(goal, "Ziel_" .. goal.id, goal.name)
                end
            end
            return
        end
        caption(
            "Kategorie",
            string.upper(kinds[n.kind]) .. "   /   " .. string.upper(page.name),
            24,
            12,
            C.leaf,
            true
        )
        local name = caption("Knoten", n.name, 48, 25, C.bright, true)
        name.Font = Enum.Font.Antique
        addDeviceActions()
        local siblings = book.families[n.family]
        if siblings and #siblings > 1 then
            local tierNo = table.find(siblings, n.id) or 1
            caption(
                "Stufentitel",
                "AUSBAUSTUFE   " .. tierNo .. " / " .. #siblings,
                18,
                12,
                C.leaf,
                true
            )
            local strip = scroll(detailScroll, "Stufenvergleich")
            row(detailScroll, strip, 56)
            strip.ScrollingDirection = Enum.ScrollingDirection.X
            strip.ScrollBarThickness = 3
            strip.CanvasSize = UDim2.fromOffset(#siblings * 54, 0)
            for i, id in siblings do
                local other = book.byId[id]
                local b = Art.button(strip, "Stufe_" .. i, "")
                Art.rect(b, (i - 1) * 54 + 2, 2, 46, 46)
                b.UIStroke.Color = if id == n.id then C.bright else C.edge
                b.UIStroke.Thickness = if id == n.id then 2.5 else 1
                local icon = Art.image(b, "Fassung")
                Art.nodeIcon(icon, other)
                Art.rect(icon, 2, 2, 42, 42)
                Art.round(icon, 22)
                b.Activated:Connect(function()
                    selectNode(other, true, true)
                end)
            end
            strip.CanvasPosition = Vector2.new(math.max(0, (tierNo - 2) * 54), 0)
        end
        if page.row ~= nil then
            local variant = if n.sprite and n.sprite < 24 then n.sprite % 4 + 1 else 1
            local picture = Art.image(detailScroll, "Ego")
            local sceneHeight = math.clamp(
                math.floor((detail.AbsoluteSize.X - 16) * 2 / 3),
                125,
                if compact then 163 else 216
            )
            row(detailScroll, picture, sceneHeight)
            Art.scene(picture, page.row, variant)
            picture.ScaleType = Enum.ScaleType.Stretch
            picture.ClipsDescendants = true
            Art.round(picture, 6)
            Art.edge(picture, C.brass, 1)
            activePreview = Preview.new(picture)
            activePreview.show(page.id, variant, reduced() or not animate)
            local play = Art.button(picture, "Wiederholen", "Start")
            play.Size = UDim2.fromOffset(44, 44)
            play.AnchorPoint = Vector2.new(1, 1)
            play.Position = UDim2.new(1, -5, 1, -5)
            play.ZIndex = picture.ZIndex + 6
            play.Activated:Connect(function()
                if activePreview then
                    activePreview.show(page.id, variant, reduced())
                end
            end)
        end
        local desc = caption("Wirkung", n.description, 0, 16, C.ivory, false)
        desc.AutomaticSize = Enum.AutomaticSize.Y
        caption(
            "Preis",
            stateNames[st]
                .. (if n.granted then "" else "   ·   " .. readable(n.cost) .. " Münzen"),
            36,
            14,
            stateTextColor(st),
            true
        )
        local showTrial = not training and not n.live
        local label = if showTrial
            then "Im Probelauf testen"
            elseif training and n.kind == "variant" and st == "owned" then "Variante ausrüsten"
            elseif st == "ready" then (if training then "Im Probelauf lernen" else "Lernen")
            else stateNames[st]
        local action = button("Lernen", label, function()
            act(n)
        end)
        local enabled = showTrial
            or st == "ready"
            or (training and n.kind == "variant" and st == "owned")
        action.Active = enabled
        action.AutoButtonColor = enabled
        action.Selectable = enabled
        action.BackgroundColor3 = if enabled then C.brass else C.board
        action.TextColor3 = if enabled then C.dark else C.mute
        if pendingFeedback ~= "" then
            caption("Feedback", pendingFeedback, 45, 13, C.bright, false)
        end
        button("Merken", if pin == n.id then "◆  Gemerkt" else "◇  Knoten merken", function()
            pin = if pin == n.id then nil else n.id
            updateStates()
            renderDetail(false)
        end)
        button("Lernplan", "Lernplan für dieses Upgrade", function()
            openPlan(n.id)
        end)
        local function requirements(ids, titleText)
            if #ids == 0 then
                return
            end
            caption("Bedingung", titleText, 24, 12, C.mute, true)
            for _, id in ids do
                local req = book.byId[id]
                if not req then
                    continue
                end
                button(
                    "Zu_" .. id,
                    (if learned(id) then "✓  " else "→  ") .. req.name,
                    function()
                        changeTab(req.page, req.id, true)
                    end
                )
            end
        end
        requirements(n.requires, "VORAUSSETZUNG")
        requirements(n.requiresAny, "EINE DIESER VERSTÄRKUNGEN")
    end
    updateStates = function()
        updateWallet()
        local target = if pin and book.byId[pin].page == page.id then pin else selected
        local routeNodes, routeEdges = Navigation.route(book.byId, target, learned)
        local completed = 0
        for id, e in entries do
            local n = book.byId[id]
            local state = status(n)
            local chosen = id == selected
            local route = routeNodes[id]
            e.outline.Color = if chosen or route == 2
                then C.leaf
                elseif route == 1 then alternative
                else colors[state]
            e.outline.Thickness = if chosen then 4 elseif big[n.kind] then 3 else 2
            e.button.BackgroundColor3 = if chosen then C.panel else C.dark
            e.mark.Text = if id == pin then "◆" else marks[state]
            e.mark.TextColor3 = colors[state]
            e.icon.ImageColor3 = if state == "locked"
                then Color3.fromRGB(150, 164, 156)
                else Color3.new(1, 1, 1)
            e.button.Interactable = not overview
            e.button.Selectable = not overview
            if state == "owned" or state == "active" then
                completed += 1
            end
        end
        progress.Text = completed .. " / " .. #page.nodes .. " gelernt"
        if dialogOpen then
            search.refresh()
            comparison.refresh()
        end
        for id, label in shortcutStates do
            local state = status(book.byId[id])
            label.Text = stateNames[state]
            label.TextColor3 = stateTextColor(state)
        end
        for _, edge in edges do
            local lit = learned(edge.from)
            local parents = routeEdges[edge.to]
            local path = if parents then parents[edge.from] else nil
            edge.line.BackgroundColor3 = if path == 2
                then C.leaf
                elseif path == 1 then alternative
                elseif lit then C.brass
                else C.edge
            edge.line.Size = UDim2.fromOffset(edge.line.Size.X.Offset, if path then 5 else 3)
            edge.line.ZIndex = if path then 106 else 105
        end
    end
    local function badge(n)
        local large = big[n.kind]
        local size = if large then 78 else 52
        local b = Art.button(sheet, n.id, "")
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        Art.rect(b, n.x, n.y, size, size)
        b.ZIndex = 110
        b:SetAttribute("NodeId", n.id)
        b.UICorner.CornerRadius = UDim.new(0, if large then 13 else size)
        local im = Art.image(b, "Gravur")
        Art.nodeIcon(im, n)
        im.AnchorPoint = Vector2.new(0.5, 0.5)
        im.Position = UDim2.fromScale(0.5, 0.5)
        im.Size = if large then UDim2.fromScale(0.88, 0.88) else UDim2.fromScale(0.98, 0.98)
        if large then
            Art.bezel(b, 13)
        end
        Art.round(im, if large then 9 else size)
        local mark = Art.text(b, "Status", "", 14, C.bright, true, 114)
        Art.rect(mark, size - 11, -6, 20, 20)
        mark.TextXAlignment = Enum.TextXAlignment.Center
        mark.BackgroundTransparency = 0
        mark.BackgroundColor3 = C.ink
        Art.round(mark, 10)
        if large or page.row == nil then
            local l = Art.text(b, "Name", n.name, 13, C.ivory, true, 112)
            l.AnchorPoint = Vector2.new(0.5, 0)
            l.Position = UDim2.new(0.5, 0, 1, 5)
            l.Size = UDim2.fromOffset(if large then 147 else 130, 27)
            l.TextXAlignment = Enum.TextXAlignment.Center
            l.BackgroundColor3 = C.dark
            l.BackgroundTransparency = 0.10
            Art.round(l, 4)
            if large then
                Art.edge(l, C.brass, 1.3)
            end
        end
        entries[n.id] = { button = b, icon = im, outline = b.UIStroke, mark = mark }
        b.Activated:Connect(function(input)
            if os.clock() < dragUntil then
                return
            end
            sound(1.07)
            selectNode(n, false, true)
            if input and gamepad(input.UserInputType) then
                focusDetail()
            end
        end)
        b.SelectionGained:Connect(function()
            if root.Visible and not overview and not dialogOpen then
                if selected ~= n.id then
                    selectNode(n, true, false)
                else
                    focusWorld(n)
                end
            end
        end)
    end
    renderPage = function()
        unlockFX.clear()
        for _, v in sheet:GetChildren() do
            if v ~= mapScale then
                v:Destroy()
            end
        end
        entries = {}
        edges = {}
        sheet.Size = UDim2.fromOffset(Catalog.width, page.height)
        local gatePos = Vector2.new(525, 62)
        for _, n in page.nodes do
            local hasLocal = false
            for _, ids in { n.requires, n.requiresAny } do
                for _, id in ids do
                    local prev = book.byId[id]
                    if prev and prev.page == page.id then
                        hasLocal = true
                        local l = Art.line(
                            sheet,
                            Vector2.new(prev.x, prev.y),
                            Vector2.new(n.x, n.y),
                            C.edge,
                            3,
                            105,
                            "Pfad"
                        )
                        table.insert(edges, { from = id, to = n.id, line = l })
                    end
                end
            end
            if not hasLocal and page.row ~= nil then
                for _, pair in
                    {
                        { gatePos, Vector2.new(525, 100) },
                        { Vector2.new(525, 100), Vector2.new(n.x, 100) },
                        { Vector2.new(n.x, 100), Vector2.new(n.x, n.y) },
                    }
                do
                    if (pair[2] - pair[1]).Magnitude > 1 then
                        local l = Art.line(sheet, pair[1], pair[2], C.edge, 3, 105, "Wurzel")
                        table.insert(edges, { from = page.gate, line = l })
                    end
                end
            end
        end
        if page.row ~= nil then
            local socket = Art.box(sheet, "Werkzeugfassung", C.wood, 108)
            Art.rect(socket, 484, 5, 82, 82)
            Art.round(socket, 41)
            Art.edge(socket, C.brass, 3)
            Art.bezel(socket, 41)
            local rootIcon = Art.image(socket, "Stamm")
            Art.icon(rootIcon, nil, page.icon)
            Art.rect(rootIcon, 6, 6, 70, 70)
            rootIcon.BackgroundColor3 = C.board
            rootIcon.BackgroundTransparency = 0
            Art.round(rootIcon, 35)
            rootIcon.ZIndex = 109
            for i, x in { 100, 278, 772, 950 } do
                local h = Art.text(sheet, "Ast_" .. i, Catalog.lanes[i], 14, C.bright, true, 108)
                Art.rect(h, x - 65, 103, 130, 28)
                h.TextXAlignment = Enum.TextXAlignment.Center
                h.BackgroundTransparency = 0
                h.BackgroundColor3 = C.wood
                Art.round(h, 4)
                Art.edge(h, C.brass)
            end
        end
        for _, n in page.nodes do
            badge(n)
        end
        for _, n in page.nodes do
            local button = entries[n.id].button
            local left = MapView.neighbor(page.nodes, n, directions[Enum.KeyCode.Left])
            local right = MapView.neighbor(page.nodes, n, directions[Enum.KeyCode.Right])
            local up = MapView.neighbor(page.nodes, n, directions[Enum.KeyCode.Up])
            local down = MapView.neighbor(page.nodes, n, directions[Enum.KeyCode.Down])
            button.NextSelectionLeft = if left then entries[left].button else button
            button.NextSelectionRight = if right then entries[right].button else button
            button.NextSelectionUp = if up then entries[up].button else tabs[page.id]
            button.NextSelectionDown = if down then entries[down].button else button
        end
        local first = entries[selected]
        tabs[page.id].NextSelectionDown = if first then first.button else nil
        for id, b in tabs do
            b.BackgroundColor3 = if id == page.id then C.brass else C.panel
            b.TextColor3 = if id == page.id then C.dark else C.ivory
        end
        tabTitle.Text = page.name
    end
    setZoom = function(value, anchor: Vector2?, target: Vector2?)
        local vp = mapViewport
        if vp.X <= 0 or vp.Y <= 0 then
            return
        end
        if overview then
            local fit =
                math.max(0.01, math.min((vp.X - 12) / Catalog.width, (vp.Y - 12) / page.height))
            mapScale.Scale = fit
            local canvas = Vector2.new(Catalog.width, page.height) * fit
            sheet.Position = UDim2.fromOffset((vp.X - canvas.X) / 2, (vp.Y - canvas.Y) / 2)
            map.CanvasSize = UDim2.fromOffset(vp.X, vp.Y)
            map.CanvasPosition = Vector2.zero
            return
        end
        local point = if anchor then target or worldAt(anchor) else nil
        local fit = math.clamp(vp.X / Catalog.width, 0.86, 1.05)
        zoom = math.clamp(value, 0.86 / fit, 1.6)
        mapScale.Scale = fit * zoom
        local canvas = mapContent()
        map.CanvasSize = UDim2.fromOffset(canvas.X, canvas.Y)
        local origin = MapView.offset(canvas, vp)
        sheet.Position = UDim2.fromOffset(origin.X, origin.Y)
        if anchor and point then
            placeWorld(point, anchor)
        end
    end
    position = function(changingPage: boolean?)
        local w, h = root.AbsoluteSize.X, root.AbsoluteSize.Y
        if w < 1 or h < 1 then
            return
        end
        local center = if not changingPage
                and not overview
                and mapViewport.X > 0
            then worldAt(mapViewport / 2)
            else nil
        compact = w < 790 or h < 500
        local headerH = if compact then 52 else 66
        local navY = headerH + 6
        local mapY = navY + 55
        Art.rect(header, 0, 0, w, headerH)
        titlePlate.Visible = not compact
        Art.rect(titlePlate, 9, 8, 211, headerH - 20)
        Art.rect(
            title,
            if compact then 10 else 20,
            if compact then 0 else -1,
            if w < 490 then 105 else 211,
            headerH
        )
        title.TextSize = if w < 490 then 16 elseif compact then 21 else 30
        local trialW = if w < 520 then 87 else 148
        Art.rect(mode, w - trialW - 58, 4, trialW, 44)
        mode.TextSize = if w < 520 then 11 else 14
        Art.rect(exit, w - 50, 4, 44, 44)
        local walletEnd = w - trialW - 66
        local walletStart = if w < 490 then 112 else 218
        if w >= 1260 then
            Art.rect(
                controlsHint,
                walletStart,
                0,
                math.max(0, walletEnd - walletStart - 230),
                headerH
            )
            Art.rect(wallet, walletEnd - 218, 0, 218, headerH)
        else
            Art.rect(wallet, walletStart, 0, math.max(0, walletEnd - walletStart), headerH)
        end
        wallet.TextSize = if w < 490 then 11 else 15
        updateHint()
        Art.rect(nav, 8, navY, w - 16, 49)
        local margin = if compact then 5 else 14
        local side = if compact then 0 else math.clamp(math.floor(w * 0.26), 243, 350)
        local mapW = w - margin * 2 - side - (if compact then 0 else 12)
        local usable = h - mapY - margin
        local cardH = if compact
            then (if expanded then math.max(110, math.floor(usable * 0.57)) else 46)
            else usable
        local mapH = if compact then usable - cardH - 5 else usable
        Art.rect(mapWrap, margin, mapY, mapW, math.max(44, mapH))
        Art.rect(mapBar, 0, 0, mapW, 47)
        local controls = if overview then 6 else 98
        local controlStart = mapW - controls
        local titleWidth = math.max(38, controlStart - 166)
        Art.rect(tabTitle, 10, 1, titleWidth, 26)
        tabTitle.TextSize = if titleWidth < 153 then 13 else 18
        tabTitle.TextTruncate = Enum.TextTruncate.AtEnd
        tabTitle.TextWrapped = false
        Art.rect(progress, 10, 28, titleWidth, 14)
        Art.rect(overviewButton, controlStart - 88, 1, 84, 44)
        Art.rect(searchButton, controlStart - 150, 1, 58, 44)
        overviewButton.Text = if overview then "Karte" else "Übersicht"
        zoomOut.Visible = not overview
        zoomIn.Visible = not overview
        updateScrolling()
        Art.rect(zoomOut, mapW - 94, 1, 44, 44)
        Art.rect(zoomIn, mapW - 46, 1, 44, 44)
        mapViewport = Vector2.new(mapW, math.max(1, mapH - 48))
        Art.rect(map, 0, 48, mapViewport.X, mapViewport.Y)
        Art.rect(
            detail,
            if compact then margin else mapW + margin + 12,
            if compact then h - margin - cardH else mapY,
            if compact then mapW else side,
            cardH
        )
        handle.Visible = compact
        handle.Size = UDim2.new(1, 0, 0, 44)
        detailScroll.Position = UDim2.fromOffset(0, if compact then 44 else 0)
        detailScroll.Size = UDim2.new(1, 0, 1, if compact then -44 else 0)
        setZoom(zoom, if center then mapViewport / 2 else nil, center)
    end
    changeTab = function(id, nodeId, center)
        rememberView()
        pinch, dragStart = nil, nil
        planTarget = nil
        statsOpen = false
        page = book.byTab[id]
        local view = savedViews[id]
        zoom = if view then view.zoom else 1
        selected = nodeId or lastSelected[id] or page.nodes[1].id
        pendingFeedback = ""
        renderPage()
        position(true)
        updateStates()
        renderDetail(true)
        if not overview then
            if center and selected then
                focusWorld(book.byId[selected])
            elseif view then
                placeWorld(view.center, mapViewport / 2)
            else
                placeWorld(Vector2.new(Catalog.width / 2, 0), Vector2.new(mapViewport.X / 2, 0))
            end
        end
        tabFocus()
    end
    local x = 0
    for _, t in book.tabs do
        local b = Art.button(nav, "Tab_" .. t.id, t.name)
        local w = math.max(110, 56 + #t.name * 8)
        Art.rect(b, x, 0, w, 44)
        b.TextXAlignment = Enum.TextXAlignment.Center
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 26)
        pad.Parent = b
        local icon = Art.image(b, "Icon")
        Art.icon(icon, nil, t.icon)
        Art.rect(icon, -22, 6, 32, 32)
        tabs[t.id] = b
        x += w + 7
        b.Activated:Connect(function()
            expanded = false
            changeTab(t.id)
        end)
    end
    if config.onLegacy then
        Art.rect(legacy, x, 0, 103, 44)
        x += 110
    end
    nav.CanvasSize = UDim2.fromOffset(x, 0)
    local function setDialogOpen(open: boolean, returnTo: GuiObject?)
        dialogOpen = open
        if open then
            unlockFX.clear()
            pinch, dragStart = nil, nil
        end
        updateScrolling()
        for _, panel in { header, nav, mapWrap, detail } do
            panel.Interactable = not open
        end
        if not open and Input:GetLastInputType().Name:find("Gamepad") then
            GuiService.SelectedObject = returnTo or searchButton
        end
    end
    search = SearchPanel.mount(root, {
        book = book,
        kinds = kinds,
        choose = jumpTo,
        statusText = function(node)
            return stateNames[status(node)]
        end,
        setOpen = function(open)
            setDialogOpen(open, searchButton)
        end,
    })
    comparison = VariantPanel.mount(root, {
        book = book,
        choose = jumpTo,
        statusText = function(node)
            local state = status(node)
            return stateNames[state] .. "  ·  " .. readable(node.cost) .. " Münzen",
                stateTextColor(state)
        end,
        setOpen = function(open)
            setDialogOpen(open, compareButton)
        end,
    })
    trialMenu = TrialPanel.mount(root, {
        trialOnly = config.trialOnly,
        start = function(preset)
            trial = Trial.start(preset, owned, coins, gates)
            setTraining(true)
            if preset == "hand" then
                changeTab("hand")
            end
        end,
        resume = function()
            if trial then
                setTraining(true)
            end
        end,
        leave = function()
            setTraining(false)
        end,
        setOpen = function(open)
            setDialogOpen(open, mode)
        end,
    })
    searchButton.Activated:Connect(search.open)
    overviewButton.Activated:Connect(function()
        planTarget = nil
        statsOpen = false
        if overview then
            showDetailMap()
        else
            rememberView()
            pinch, dragStart = nil, nil
            overview = true
            expanded = false
        end
        position()
        updateStates()
        renderDetail(false)
    end)
    zoomOut.Activated:Connect(function()
        setZoom(zoom / 1.18, mapViewport / 2)
    end)
    zoomIn.Activated:Connect(function()
        setZoom(zoom * 1.18, mapViewport / 2)
    end)
    local function insideMap(point)
        local offset = point - map.AbsolutePosition
        local s = map.AbsoluteWindowSize
        return root.Visible
            and not overview
            and not dialogOpen
            and offset.X >= 0
            and offset.X <= s.X
            and offset.Y >= 0
            and offset.Y <= s.Y
    end
    local connections = {}
    table.insert(
        connections,
        Input.LastInputTypeChanged:Connect(function(inputType)
            updateScrolling()
            updateHint()
            local focus = GuiService.SelectedObject
            if
                inputType == Enum.UserInputType.Keyboard
                and focus
                and focus:IsDescendantOf(sheet)
            then
                GuiService.SelectedObject = nil
            end
        end)
    )
    table.insert(
        connections,
        Input.InputBegan:Connect(function(input)
            local p = Vector2.new(input.Position.X, input.Position.Y)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and insideMap(p) then
                dragStart = p
                dragOrigin = map.CanvasPosition
            end
        end)
    )
    table.insert(
        connections,
        Input.InputChanged:Connect(function(input)
            if not root.Visible or dialogOpen or overview then
                return
            end
            local point = Vector2.new(input.Position.X, input.Position.Y)
            if input.UserInputType == Enum.UserInputType.MouseWheel and insideMap(point) then
                setZoom(zoom * 1.12 ^ input.Position.Z, point - map.AbsolutePosition)
            elseif input.UserInputType == Enum.UserInputType.MouseMovement and dragStart then
                local delta = point - dragStart
                if delta.Magnitude >= 6 then
                    dragUntil = os.clock() + 0.16
                    map.CanvasPosition =
                        MapView.clampPan(dragOrigin - delta, mapContent(), mapViewport)
                end
            end
        end)
    )
    table.insert(
        connections,
        Input.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragStart = nil
            end
        end)
    )
    table.insert(
        connections,
        Input.TouchPinch:Connect(function(points, scale, _velocity, state)
            if state == Enum.UserInputState.Begin then
                if #points == 2 and insideMap(points[1]) and insideMap(points[2]) then
                    local anchor = (points[1] + points[2]) / 2 - map.AbsolutePosition
                    pinch = { zoom = zoom, world = worldAt(anchor) }
                    updateScrolling()
                end
            elseif state == Enum.UserInputState.Change and pinch and #points == 2 then
                local anchor = (points[1] + points[2]) / 2 - map.AbsolutePosition
                setZoom(pinch.zoom * scale, anchor, pinch.world)
                dragUntil = os.clock() + 0.2
            elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
                pinch = nil
                updateScrolling()
            end
        end)
    )
    root.Destroying:Connect(function()
        ContextActionService:UnbindAction(actionName)
        stopPreview()
        for _, c in connections do
            c:Disconnect()
        end
    end)
    local function navigate(_name: string, state: Enum.UserInputState, input: InputObject)
        if not root.Visible or dialogOpen or Input:GetFocusedTextBox() then
            return Enum.ContextActionResult.Pass
        end
        local key = input.KeyCode
        local step = switches[key]
        local direction = directions[key]
        local focused = GuiService.SelectedObject
        local controller = gamepad(input.UserInputType)
        if direction and controller and focused then
            return Enum.ContextActionResult.Pass
        end
        if
            not step
            and (
                overview
                or (
                    controller
                    and focused
                    and not focused:IsDescendantOf(sheet)
                    and not focused:IsDescendantOf(nav)
                )
            )
        then
            return Enum.ContextActionResult.Pass
        end
        if state == Enum.UserInputState.Begin then
            if step then
                local current = table.find(book.tabs, page) or 1
                local target = math.clamp(current + step, 1, #book.tabs)
                if target ~= current then
                    expanded = false
                    changeTab(book.tabs[target].id)
                end
                if controller then
                    focusSelected()
                end
            elseif direction and selected then
                local nextId = MapView.neighbor(page.nodes, book.byId[selected], direction)
                if nextId then
                    selectNode(book.byId[nextId], true, false)
                    if controller then
                        focusSelected()
                    end
                end
            elseif key == Enum.KeyCode.Return and selected then
                selectNode(book.byId[selected], true, true)
            end
        end
        return Enum.ContextActionResult.Sink
    end
    handle.Activated:Connect(function()
        expanded = not expanded
        position()
        renderDetail(false)
    end)
    mode.Activated:Connect(openTrialMenu)
    exit.Activated:Connect(config.onClose)
    if config.onLegacy then
        legacy.Activated:Connect(config.onLegacy)
    end
    local oldCompact
    root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if not root.Visible then
            return
        end
        oldCompact = compact
        position()
        if oldCompact ~= compact then
            renderDetail(false)
        end
    end)
    function api.sync(snapshot, amount, formatted)
        local before = owned
        owned = snapshot.nodes or {}
        coins = amount
        walletText = formatted
        if root.Visible and not training then
            updateStates()
            local n = book.byId[selected]
            if n then
                local planChanged = false
                if planTarget or statsOpen then
                    for id, candidate in book.byId do
                        if candidate.live and before[id] ~= owned[id] then
                            planChanged = true
                            break
                        end
                    end
                end
                if
                    planChanged
                    or (
                        not overview
                        and not planTarget
                        and not statsOpen
                        and renderedStatus ~= status(n)
                    )
                then
                    renderDetail(false)
                end
                if owned[n.id] and not before[n.id] then
                    presentUnlock(n, before, owned, false)
                end
            end
        end
    end
    function api.open(id)
        root.Visible = true
        gui:SetAttribute("WerkstattOffen", true)
        expanded = false
        local target = book.byId[id or ""]
        changeTab(
            if target then target.page else page.id,
            if target then target.id else nil,
            target ~= nil
        )
        ContextActionService:BindActionAtPriority(
            actionName,
            navigate,
            false,
            Enum.ContextActionPriority.High.Value + 1,
            Enum.KeyCode.Left,
            Enum.KeyCode.Right,
            Enum.KeyCode.Up,
            Enum.KeyCode.Down,
            Enum.KeyCode.DPadLeft,
            Enum.KeyCode.DPadRight,
            Enum.KeyCode.DPadUp,
            Enum.KeyCode.DPadDown,
            Enum.KeyCode.PageUp,
            Enum.KeyCode.PageDown,
            Enum.KeyCode.ButtonL1,
            Enum.KeyCode.ButtonR1,
            Enum.KeyCode.Return
        )
        if gamepad(Input:GetLastInputType()) then
            focusSelected()
        end
        scaleIn(header, 0.987, 0.18)
    end
    function api.close()
        ContextActionService:UnbindAction(actionName)
        rememberView()
        pinch, dragStart = nil, nil
        search.dismiss()
        comparison.dismiss()
        trialMenu.dismiss()
        unlockFX.clear()
        stopPreview()
        root.Visible = false
        gui:SetAttribute("WerkstattOffen", false)
        if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
            GuiService.SelectedObject = nil
        end
    end
    function api.visible()
        return root.Visible
    end
    function api.back()
        if search.dismiss() or comparison.dismiss() or trialMenu.dismiss() then
            return
        end
        local focused = GuiService.SelectedObject
        if statsOpen then
            statsOpen = false
            renderDetail(false)
        elseif planTarget then
            planTarget = nil
            renderDetail(false)
        elseif compact and expanded then
            expanded = false
            position()
            renderDetail(false)
            if gamepad(Input:GetLastInputType()) then
                focusSelected()
            end
        elseif focused and focused:IsDescendantOf(detail) and gamepad(Input:GetLastInputType()) then
            focusSelected()
        elseif overview then
            showDetailMap()
            position()
            updateStates()
            renderDetail(false)
            if gamepad(Input:GetLastInputType()) then
                focusSelected()
            end
        else
            config.onClose()
        end
    end
    return api
end
return Workshop
