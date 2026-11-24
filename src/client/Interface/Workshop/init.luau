--!strict
-- The host supplies the canonical catalogue, current wallet and its existing purchase action.
-- Trial ownership, variants and money exist only in this UI instance.
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Input = game:GetService("UserInputService")
local Art = require(script.Art)
local Catalog = require(script.Catalog)
local Navigation = require(script.Navigation)
local Preview = require(script.Preview)
local SearchPanel = require(script.SearchPanel)
local VariantPanel = require(script.VariantPanel)
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
local alternative = Color3.fromRGB(216, 159, 89)
local function clampPan(value, content, viewport)
    return Vector2.new(
        math.clamp(value.X, 0, math.max(0, content.X - viewport.X)),
        math.clamp(value.Y, 0, math.max(0, content.Y - viewport.Y))
    )
end
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
    local book = Catalog.build(config.baseNodes)
    local root = Art.box(gui, "Werkstatt", C.ink, 100)
    root.Size = UDim2.fromScale(1, 1)
    root.Visible = false
    root.Active = true
    local header = Art.box(root, "Messingleiste", Color3.new(1, 1, 1), 101)
    Art.gradient(header, C.wood, C.dark)
    local title = Art.text(header, "Title", "WERKSTATT", 30, C.bright, true)
    title.Font = Enum.Font.Antique
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
    local mapBar = Art.box(mapWrap, "Werkzeugleiste", C.panel, 120)
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
    local sheet = Art.box(map, "Diagramm", nil, 103)
    local mapScale = Instance.new("UIScale")
    mapScale.Parent = sheet
    local detail = Art.box(root, "Detail", C.panel, 130)
    Art.edge(detail, C.brass, 2)
    detail.ClipsDescendants = true
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
    local training = config.trialOnly == true
    local trialOwned, variants, trialCoins = nil, {}, 0
    local zoom = 1
    local overview = false
    local detailPan = Vector2.zero
    local compact = false
    local expanded = false
    local activePreview = nil
    local renderedStatus = nil
    local busy = false
    local pin = nil
    local lastSelected = {}
    local pendingFeedback = ""
    local dragUntil = 0
    local renderPage, renderDetail, updateStates, position, changeTab, selectNode, setZoom
    local dialogOpen = false
    local search
    local comparison
    local compareButton: TextButton? = nil
    local api = {}

    local function startTrial()
        if trialOwned then
            return
        end
        trialOwned = table.clone(owned)
        trialCoins = 1000000000
        for _, dev in book.devices do
            if dev.gate ~= "start" then
                trialOwned[dev.gate] = true
            end
        end
        trialOwned.sandstorm_1 = true
    end
    local function learned(id)
        return id == "start" or (if training then trialOwned[id] else owned[id]) == true
    end
    local function status(n)
        if learned(n.id) then
            return if training and variants[n.device or ""] == n.id then "active" else "owned"
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
        return if (if training then trialCoins else coins) >= n.cost then "ready" else "dear"
    end
    local function stopPreview()
        if activePreview then
            activePreview.clear()
            activePreview = nil
        end
    end
    local function focusWorld(n)
        local vp = map.AbsoluteWindowSize
        map.CanvasPosition = clampPan(
            Vector2.new(n.x * mapScale.Scale - vp.X / 2, n.y * mapScale.Scale - vp.Y * 0.42),
            Vector2.new(Catalog.width, page.height) * mapScale.Scale,
            vp
        )
    end
    local function showDetailMap()
        if overview then
            overview = false
            setZoom(zoom, false)
            map.CanvasPosition = detailPan
        end
    end
    local function jumpTo(target)
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
        wallet.Text = if training
            then readable(trialCoins) .. "  Testmünzen"
            else walletText .. "  Münzen"
        mode.Text = if training then "Probelauf beenden" else "Probelauf"
    end
    local function pulse(n)
        local e = entries[n.id]
        if not e then
            return
        end
        scaleIn(e.button, 0.82, if big[n.kind] then 0.55 else 0.25)
        sound(if big[n.kind] then 1.36 else 1.15)
        if reduced() then
            return
        end
        local ring = Art.box(e.button, "Freischaltring", nil, e.button.ZIndex + 5)
        ring.AnchorPoint = Vector2.new(0.5, 0.5)
        ring.Position = UDim2.fromScale(0.5, 0.5)
        ring.Size = UDim2.fromScale(1, 1)
        Art.round(ring, if big[n.kind] then 12 else 100)
        local edge = Art.edge(ring, C.bright, 3)
        local duration = if big[n.kind] then 0.55 else 0.25
        TweenService:Create(ring, TweenInfo.new(duration), { Size = UDim2.fromScale(1.55, 1.55) })
            :Play()
        TweenService:Create(edge, TweenInfo.new(duration), { Transparency = 1 }):Play()
        task.delay(duration, function()
            ring:Destroy()
        end)
    end
    local function toggleTrial()
        if config.trialOnly then
            return
        end
        training = not training
        if training then
            startTrial()
        end
        pendingFeedback = ""
        updateStates()
        renderDetail(false)
    end
    local function act(n)
        if busy then
            return
        end
        if not training and not n.live then
            toggleTrial()
            return
        end
        local state = status(n)
        if training and state == "owned" and n.kind == "variant" then
            variants[n.device] = n.id
            updateStates()
            renderDetail(false)
            pulse(n)
            return
        end
        if state ~= "ready" then
            return
        end
        if training then
            trialCoins -= n.cost
            trialOwned[n.id] = true
            if n.kind == "variant" and not variants[n.device] then
                variants[n.device] = n.id
            end
            updateStates()
            renderDetail(false)
            pulse(n)
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
        handle.Text = (if overview then "Ziele und Voraussetzungen" else n.name)
            .. (if expanded then "   ▾" else "   ▴")
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
        local function addComparison()
            if page.variants then
                compareButton = button("Varianten", "Varianten vergleichen", function()
                    comparison.open(page)
                end)
            end
        end
        local function mapShortcut(target, key, label)
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
            local state =
                Art.text(line, "Status", stateNames[targetState], 11, colors[targetState], false)
            state.Position = UDim2.fromOffset(54, 26)
            state.Size = UDim2.new(1, -62, 0, 20)
            line.Size = UDim2.new(1, -16, 0, 52)
            shortcutStates[target.id] = state
        end
        if overview then
            local heading = caption("Knoten", page.name, 38, 25, C.bright, true)
            heading.Font = Enum.Font.Antique
            addComparison()
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
        addComparison()
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
            local picture = Art.image(detailScroll, "Ego")
            row(detailScroll, picture, if compact then 104 else 142)
            Art.scene(picture, page.row)
            picture.ScaleType = Enum.ScaleType.Stretch
            picture.ClipsDescendants = true
            Art.round(picture, 6)
            Art.edge(picture, C.brass, 1)
            activePreview = Preview.new(picture)
            local variant = if n.sprite and n.sprite < 24 then n.sprite % 4 + 1 else 1
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
            colors[st],
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
            label.TextColor3 = colors[state]
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
        b.Activated:Connect(function()
            if os.clock() < dragUntil then
                return
            end
            sound(1.07)
            selectNode(n, false, true)
        end)
        b.SelectionGained:Connect(function()
            if Input:GetLastInputType().Name:find("Gamepad") then
                focusWorld(n)
            end
        end)
    end
    renderPage = function()
        for _, v in sheet:GetChildren() do
            if v ~= mapScale then
                v:Destroy()
            end
        end
        entries = {}
        edges = {}
        sheet.Size = UDim2.fromOffset(Catalog.width, page.height)
        Art.contours(sheet)
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
        for id, b in tabs do
            b.BackgroundColor3 = if id == page.id then C.brass else C.panel
            b.TextColor3 = if id == page.id then C.dark else C.ivory
        end
        tabTitle.Text = page.name
    end
    setZoom = function(value, center)
        local previous = mapScale.Scale
        local vp = map.AbsoluteSize
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
        local offsetX = sheet.Position.X.Offset
        local point = (map.CanvasPosition + vp / 2 - Vector2.new(offsetX, 0))
            / math.max(0.01, previous)
        zoom = math.clamp(value, 0.86, 1.6)
        local fit = math.min(1.05, math.max(0.86, map.AbsoluteSize.X / Catalog.width))
        mapScale.Scale = math.max(0.86, fit * zoom)
        local canvas = Vector2.new(Catalog.width, page.height) * mapScale.Scale
        map.CanvasSize = UDim2.fromOffset(canvas.X, canvas.Y)
        sheet.Position = UDim2.fromOffset(math.max(0, (map.AbsoluteWindowSize.X - canvas.X) / 2), 0)
        if center then
            map.CanvasPosition = clampPan(
                point * mapScale.Scale + Vector2.new(sheet.Position.X.Offset, 0) - vp / 2,
                canvas,
                vp
            )
        end
    end
    position = function()
        local w, h = root.AbsoluteSize.X, root.AbsoluteSize.Y
        if w < 1 or h < 1 then
            return
        end
        compact = w < 790 or h < 500
        local headerH = if compact then 52 else 66
        local navY = headerH + 6
        local mapY = navY + 55
        Art.rect(header, 0, 0, w, headerH)
        Art.rect(title, if compact then 10 else 20, 0, if w < 490 then 105 else 211, headerH)
        title.TextSize = if w < 490 then 16 elseif compact then 21 else 30
        local trialW = if w < 520 then 87 else 148
        Art.rect(mode, w - trialW - 58, 4, trialW, 44)
        mode.TextSize = if w < 520 then 11 else 14
        mode.Visible = not config.trialOnly
        Art.rect(exit, w - 50, 4, 44, 44)
        local walletEnd = if config.trialOnly then w - 57 else w - trialW - 66
        local walletStart = if w < 490 then 112 else 218
        Art.rect(wallet, walletStart, 0, math.max(0, walletEnd - walletStart), headerH)
        wallet.TextSize = if w < 490 then 11 else 15
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
        map.ScrollingEnabled = not overview
        Art.rect(zoomOut, mapW - 94, 1, 44, 44)
        Art.rect(zoomIn, mapW - 46, 1, 44, 44)
        Art.rect(map, 0, 48, mapW, math.max(1, mapH - 48))
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
        setZoom(zoom, false)
    end
    changeTab = function(id, nodeId, center)
        page = book.byTab[id]
        selected = nodeId or lastSelected[id] or page.nodes[1].id
        pendingFeedback = ""
        renderPage()
        position()
        updateStates()
        renderDetail(true)
        if overview then
            detailPan = Vector2.zero
        elseif (center or lastSelected[id]) and selected then
            focusWorld(book.byId[selected])
        else
            map.CanvasPosition = Vector2.new(
                math.max(0, (Catalog.width * mapScale.Scale - map.AbsoluteWindowSize.X) / 2),
                0
            )
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
                if state == "locked" then C.mute else colors[state]
        end,
        setOpen = function(open)
            setDialogOpen(open, compareButton)
        end,
    })
    searchButton.Activated:Connect(search.open)
    overviewButton.Activated:Connect(function()
        if overview then
            showDetailMap()
            position()
        else
            detailPan = map.CanvasPosition
            overview = true
            expanded = false
            position()
        end
        updateStates()
        renderDetail(false)
    end)
    zoomOut.Activated:Connect(function()
        setZoom(zoom / 1.18, true)
    end)
    zoomIn.Activated:Connect(function()
        setZoom(zoom * 1.18, true)
    end)
    local dragStart, dragOrigin, pinchZoom
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
            if
                not root.Visible
                or dialogOpen
                or not dragStart
                or input.UserInputType ~= Enum.UserInputType.MouseMovement
            then
                return
            end
            local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
            if delta.Magnitude >= 6 then
                dragUntil = os.clock() + 0.16
                map.CanvasPosition = clampPan(
                    dragOrigin - delta,
                    Vector2.new(Catalog.width, page.height) * mapScale.Scale,
                    map.AbsoluteWindowSize
                )
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
                pinchZoom = if points[1] and insideMap(points[1]) then zoom else nil
            elseif
                state == Enum.UserInputState.Change
                and pinchZoom
                and root.Visible
                and not dialogOpen
            then
                setZoom(pinchZoom * scale, true)
                dragUntil = os.clock() + 0.2
            elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
                pinchZoom = nil
            end
        end)
    )
    root.Destroying:Connect(function()
        stopPreview()
        for _, c in connections do
            c:Disconnect()
        end
    end)
    handle.Activated:Connect(function()
        expanded = not expanded
        position()
        renderDetail(false)
    end)
    mode.Activated:Connect(toggleTrial)
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
                if not overview and renderedStatus ~= status(n) then
                    renderDetail(false)
                end
                if owned[n.id] and not before[n.id] then
                    pulse(n)
                end
            end
        end
    end
    function api.open(id)
        if training then
            startTrial()
        end
        root.Visible = true
        gui:SetAttribute("WerkstattOffen", true)
        expanded = false
        local target = book.byId[id or ""]
        changeTab(
            if target then target.page else page.id,
            if target then target.id else nil,
            target ~= nil
        )
        if Input:GetLastInputType().Name:find("Gamepad") then
            GuiService.SelectedObject = tabs[page.id]
        end
        scaleIn(header, 0.987, 0.18)
    end
    function api.close()
        search.dismiss()
        comparison.dismiss()
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
        if search.dismiss() or comparison.dismiss() then
            return
        end
        if compact and expanded then
            expanded = false
            position()
            renderDetail(false)
        elseif overview then
            showDetailMap()
            position()
            updateStates()
            renderDetail(false)
        else
            config.onClose()
        end
    end
    return api
end
return Workshop
