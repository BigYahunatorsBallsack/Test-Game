--!strict
-- UnlockPlayer (Paket 2.3): spielt die Freischalt-Sequenz im Skilltree ab. Hilfsmodul des
-- Controllers SkillTree, kein eigener Controller. Den Plan (Variante, neu sichtbare Knoten,
-- Impulskanten, Zeitleiste, Töne) rechnet Logic/UnlockSequence, die Zahlen stehen in
-- Data/UnlockAnimation und Data/TreeSounds. Dieses Modul zeichnet nur mit Tweens und räumt alles
-- wieder ab. Der Server und der Kauf sind nicht beteiligt.
--
-- Ablauf (normal, etwa 1,2 s): Der Knoten drückt sich ein, ein Ring bricht aus, ein Lichtpunkt
-- läuft über die Linien zu den Folgeknoten (Folgeknoten ohne Linie bekommen einen Glanzring), neue
-- Knoten und Linien blenden aus dem Nebel ein, der Nebel weicht, die Kamera gleitet hin. Meilenstein:
-- dazu ein Aufhell-Puls über den ganzen Baum. Kurz: nur Eindrücken, Ring, Einblenden, Kamera.
-- `stop()` springt sofort ans Ende (alles steht dann im Endzustand, nichts bleibt hängen).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Gestaltung der kurzen Effekte (die Zeiten selbst stehen in Data/UnlockAnimation)
local RING_THICKNESS = 4
local RING_START_TRANSPARENCY = 0.05
local RING_CORNER = 20
local GLINT_THICKNESS = 3
local GLINT_SCALE = 1.9 -- Glanzring wächst bis zum x-fachen der Knotengröße
local GLINT_SECONDS = 0.3
local GLINT_AT_FRACTION = 0.6 -- Der Glanzring erscheint, wenn der Lichtpunkt zu 60 % unterwegs ist
local DOT_SIZE = 14
local DOT_FADE_FRACTION = 0.3 -- Der Lichtpunkt blendet im letzten Drittel aus
local FLASH_UP_FRACTION = 0.3 -- Der Aufhell-Puls steigt in 30 % der Zeit und fällt in 70 %
local SOUND_LIFETIME_SECONDS = 5

-- Easing
local PRESS_EASING = Enum.EasingStyle.Quad
local RING_EASING = Enum.EasingStyle.Quad
local DOT_EASING = Enum.EasingStyle.Sine
local REVEAL_EASING = Enum.EasingStyle.Sine
local FLASH_EASING = Enum.EasingStyle.Sine
local CAMERA_EASING = Enum.EasingStyle.Sine

-- Farben (vorläufig bis zum Stil-Guide, Paket 0.4)
local LIGHT_COLOR = Color3.fromRGB(255, 226, 140)
local FLASH_COLOR = Color3.fromRGB(255, 244, 214)

-- ZIndex (der ScreenGui läuft im Modus Global, siehe SkillTree)
local Z_EFFECT = 15
local Z_FLASH = 18

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local Anim = loadShared("Data", "UnlockAnimation")
local Sounds = loadShared("Data", "TreeSounds")
local LayoutConfig = loadShared("Data", "TreeLayout")
local TreeCamera = loadShared("Logic", "TreeCamera")

local UnlockPlayer = {}

-- ctx:
--   overlay, world: Frames (Aufheller liegt im Overlay, Effekte in der Baumfläche)
--   fog: Frame, lineFolder: Folder, entries: { [id] = { scale: UIScale, veil: Frame } }
--   layout, area: aus Logic/TreeLayout
--   framePosition(x, y): UDim2, viewport(): { width, height }, getCamera(), setCamera(camera)
function UnlockPlayer.new(ctx: any)
    local half = LayoutConfig.nodeSize / 2
    local player = {}

    local token = 0
    local tweens: { Tween } = {}
    local temps: { Instance } = {}
    local snaps: { () -> () } = {}
    local glide: RBXScriptConnection? = nil

    local flash = Instance.new("Frame")
    flash.Name = "Flash"
    flash.Size = UDim2.fromScale(1, 1)
    flash.BackgroundColor3 = FLASH_COLOR
    flash.BackgroundTransparency = 1
    flash.BorderSizePixel = 0
    flash.Active = false
    flash.ZIndex = Z_FLASH
    flash.Parent = ctx.overlay

    local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
        local t = TweenService:Create(instance, info, goal)
        table.insert(tweens, t)
        t:Play()
        return t
    end

    local function temp(instance: Instance): Instance
        table.insert(temps, instance)
        return instance
    end

    local function at(seconds: number, fn: () -> ())
        local mine = token
        task.delay(seconds, function()
            if mine == token then
                fn()
            end
        end)
    end

    local function stopGlide()
        if glide ~= nil then
            (glide :: RBXScriptConnection):Disconnect()
            glide = nil
        end
    end

    local function playCue(name: string)
        local cue = Sounds.cues[name]
        if cue == nil or cue.soundId == "" then
            return -- Platzhalter: kein Ton, kein Fehler
        end
        local sound = Instance.new("Sound")
        sound.SoundId = cue.soundId
        sound.Volume = cue.volume
        sound.PlaybackSpeed = cue.pitch
        sound.Parent = SoundService
        sound:Play()
        Debris:AddItem(sound, SOUND_LIFETIME_SECONDS)
    end

    -- Ring, der um einen Knoten herum ausbricht und ausblendet.
    local function spawnRing(x: number, y: number, scale: number, seconds: number, thickness: number)
        local ring = Instance.new("Frame")
        ring.Name = "UnlockRing"
        ring.AnchorPoint = Vector2.new(0.5, 0.5)
        ring.Position = ctx.framePosition(x, y)
        ring.Size = UDim2.fromOffset(LayoutConfig.nodeSize, LayoutConfig.nodeSize)
        ring.BackgroundTransparency = 1
        ring.ZIndex = Z_EFFECT
        ring.Parent = ctx.world
        temp(ring)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, RING_CORNER)
        corner.Parent = ring
        local stroke = Instance.new("UIStroke")
        stroke.Color = LIGHT_COLOR
        stroke.Thickness = thickness
        stroke.Transparency = RING_START_TRANSPARENCY
        stroke.Parent = ring
        local info = TweenInfo.new(seconds, RING_EASING, Enum.EasingDirection.Out)
        local size = LayoutConfig.nodeSize * scale
        tween(ring, info, { Size = UDim2.fromOffset(size, size) })
        tween(stroke, info, { Transparency = 1 })
    end

    -- Lichtpunkt, der von einem Knoten zum Folgeknoten läuft (y wächst nach unten: `to` liegt oben).
    local function spawnDot(from: any, to: any, seconds: number)
        local dot = Instance.new("Frame")
        dot.Name = "UnlockDot"
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
        dot.Position = ctx.framePosition(from.x, from.y - half)
        dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
        dot.BackgroundColor3 = LIGHT_COLOR
        dot.BorderSizePixel = 0
        dot.ZIndex = Z_EFFECT
        dot.Parent = ctx.world
        temp(dot)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = dot
        tween(dot, TweenInfo.new(seconds, DOT_EASING, Enum.EasingDirection.InOut), { Position = ctx.framePosition(to.x, to.y + half) })
        tween(dot, TweenInfo.new(seconds * DOT_FADE_FRACTION, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, seconds * (1 - DOT_FADE_FRACTION)), { BackgroundTransparency = 1 })
    end

    -- Beendet alles sofort: Tweens abbrechen, Zwischenstände auf den Endzustand setzen,
    -- kurzlebige Instanzen löschen.
    function player.stop()
        token += 1
        stopGlide()
        for _, t in tweens do
            t:Cancel()
        end
        table.clear(tweens)
        for _, instance in temps do
            instance:Destroy()
        end
        table.clear(temps)
        for _, snap in snaps do
            snap()
        end
        table.clear(snaps)
        flash.BackgroundTransparency = 1
    end

    -- Bricht nur die Kamerafahrt ab (zum Beispiel wenn der Spieler selbst zieht oder zoomt).
    function player.stopGlide()
        stopGlide()
    end

    -- Spielt den Plan ab. `fogBefore` ist die Größe des Nebels vor dem Kauf (der Nebel weicht
    -- von dort zur neuen Größe).
    function player.play(plan: any, fogBefore: UDim2)
        player.stop()
        token += 1

        local steps: { [string]: any } = {}
        for _, step in plan.steps do
            steps[step.name] = step
        end
        local nodePlace = ctx.layout.nodes[plan.nodeId]
        local entry = ctx.entries[plan.nodeId]

        -- Töne
        for _, cue in plan.cues do
            at(cue.at, function()
                playCue(cue.name)
            end)
        end

        -- Eindrücken: runter und wieder hoch in einem Tween (reverses).
        local press = steps.press
        if press ~= nil and entry ~= nil and nodePlace ~= nil then
            table.insert(snaps, function()
                entry.scale.Scale = 1
            end)
            at(press.start, function()
                tween(entry.scale, TweenInfo.new(press.duration / 2, PRESS_EASING, Enum.EasingDirection.Out, 0, true), { Scale = Anim.pressScale })
            end)
        end

        -- Ring
        local ring = steps.ring
        if ring ~= nil and nodePlace ~= nil then
            at(ring.start, function()
                spawnRing(nodePlace.x, nodePlace.y, plan.ringScale, ring.duration, RING_THICKNESS)
            end)
        end

        -- Lichtimpuls und Glanzringe
        local pulse = steps.pulse
        if pulse ~= nil then
            at(pulse.start, function()
                for _, edge in plan.pulseEdges do
                    local from, to = ctx.layout.nodes[edge.from], ctx.layout.nodes[edge.to]
                    if from ~= nil and to ~= nil then
                        spawnDot(from, to, pulse.duration)
                    end
                end
            end)
            at(pulse.start + pulse.duration * GLINT_AT_FRACTION, function()
                for _, id in plan.glintTargets do
                    local target = ctx.layout.nodes[id]
                    if target ~= nil then
                        spawnRing(target.x, target.y, GLINT_SCALE, GLINT_SECONDS, GLINT_THICKNESS)
                    end
                end
            end)
        end

        -- Einblenden: Neue Knoten und Linien starten unsichtbar und kommen aus dem Nebel.
        local reveal = steps.reveal
        if reveal ~= nil then
            local revealInfo = TweenInfo.new(reveal.duration, REVEAL_EASING, Enum.EasingDirection.Out)
            local revealed: { [string]: boolean } = {}
            for _, id in plan.revealed do
                revealed[id] = true
                local target = ctx.entries[id]
                if target ~= nil then
                    target.veil.BackgroundTransparency = 0
                    target.scale.Scale = Anim.revealStartScale
                    table.insert(snaps, function()
                        target.veil.BackgroundTransparency = 1
                        target.scale.Scale = 1
                    end)
                    at(reveal.start, function()
                        tween(target.veil, revealInfo, { BackgroundTransparency = 1 })
                        tween(target.scale, revealInfo, { Scale = 1 })
                    end)
                end
            end
            local pieces: { Frame } = {}
            for _, piece in ctx.lineFolder:GetChildren() do
                if piece:IsA("Frame") and revealed[piece:GetAttribute("To") :: string] then
                    piece.BackgroundTransparency = 1
                    table.insert(pieces, piece)
                end
            end
            if #pieces > 0 then
                table.insert(snaps, function()
                    for _, piece in pieces do
                        if piece.Parent ~= nil then
                            piece.BackgroundTransparency = 0
                        end
                    end
                end)
                at(reveal.start, function()
                    for _, piece in pieces do
                        if piece.Parent ~= nil then
                            tween(piece, revealInfo, { BackgroundTransparency = 0 })
                        end
                    end
                end)
            end

            -- Nebel weicht von der alten zur neuen Größe.
            local fogAfter = ctx.fog.Size
            local fogVisibleAfter = ctx.fog.Visible
            if fogBefore ~= fogAfter then
                ctx.fog.Size = fogBefore
                ctx.fog.Visible = true
                table.insert(snaps, function()
                    ctx.fog.Size = fogAfter
                    ctx.fog.Visible = fogVisibleAfter
                end)
                at(reveal.start, function()
                    tween(ctx.fog, revealInfo, { Size = fogAfter })
                end)
            end
        end

        -- Aufhell-Puls (nur Meilenstein)
        local flashStep = steps.flash
        if flashStep ~= nil and plan.flashStrength ~= nil then
            local peak = 1 - plan.flashStrength
            at(flashStep.start, function()
                local up = flashStep.duration * FLASH_UP_FRACTION
                local upTween = tween(flash, TweenInfo.new(up, FLASH_EASING, Enum.EasingDirection.Out), { BackgroundTransparency = peak })
                upTween.Completed:Connect(function(state: Enum.PlaybackState)
                    if state == Enum.PlaybackState.Completed then
                        tween(flash, TweenInfo.new(flashStep.duration - up, FLASH_EASING, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
                    end
                end)
            end)
        end

        -- Kamera gleitet zum gekauften Knoten und den neu sichtbaren Knoten.
        local cameraStep = steps.camera
        if cameraStep ~= nil then
            local sum = { x = 0, y = 0 }
            local count = 0
            for _, id in plan.cameraPoints do
                local place = ctx.layout.nodes[id]
                if place ~= nil then
                    sum.x += place.x
                    sum.y += place.y
                    count += 1
                end
            end
            if count > 0 then
                local startCamera = ctx.getCamera()
                local endCamera = TreeCamera.centerOn(startCamera, { x = sum.x / count, y = sum.y / count }, ctx.viewport(), ctx.area)
                at(cameraStep.start, function()
                    local elapsed = 0
                    glide = RunService.Heartbeat:Connect(function(dt: number)
                        elapsed += dt
                        local alpha = math.min(elapsed / cameraStep.duration, 1)
                        local eased = TweenService:GetValue(alpha, CAMERA_EASING, Enum.EasingDirection.Out)
                        ctx.setCamera({
                            zoom = startCamera.zoom,
                            panX = startCamera.panX + (endCamera.panX - startCamera.panX) * eased,
                            panY = startCamera.panY + (endCamera.panY - startCamera.panY) * eased,
                        })
                        if alpha >= 1 then
                            stopGlide()
                        end
                    end)
                end)
            end
        end

        -- Am Ende der Zeitleiste aufräumen (Ringe und Punkte sind dann schon unsichtbar).
        at(plan.totalSeconds + 0.1, function()
            player.stop()
        end)
    end

    return player
end

return UnlockPlayer
