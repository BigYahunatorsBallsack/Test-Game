--!strict
-- Graphics (Paket 3.6): Hilfsmodul der Client-Controller, kein eigener Controller. Es hält die
-- aktuelle Grafikstufe ("hoch", "schlank", "minimal") und schaltet bei "schlank" und "minimal" die
-- Nachbearbeitung (Bloom, Sonnenstrahlen, Tiefenschärfe, Unschärfe) nur auf diesem Client ab.
-- Die Wahl rechnet Logic/GraphicsLevel, die Zahlen je Stufe stehen in Data/Screen. Wer Effekte
-- zeichnet (Wetter, Reveal, Werkzeuge), fragt `Graphics.settings()`.
--
-- Quellen der Stufe: erzwungen über das Spieler-Attribut `GraphicsLevel` (zum Testen in der
-- Client-Befehlszeile: game.Players.LocalPlayer:SetAttribute("GraphicsLevel", "schlank"), nil =
-- automatisch), der Rückfall des Bildraten-Wächters (Dig meldet ihn mit `setFallbackProvider`),
-- ein Touch-Gerät und der Grafikregler von Roblox.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LEVEL_ATTRIBUTE = "GraphicsLevel"
local REFRESH_SECONDS = 0.5
local EFFECT_CLASSES = { "BloomEffect", "SunRaysEffect", "DepthOfFieldEffect", "BlurEffect" }

local shared = ReplicatedStorage:WaitForChild("Shared")
local GraphicsLevel = require(shared:WaitForChild("Logic"):WaitForChild("GraphicsLevel") :: ModuleScript) :: any

local Graphics = {}

local player = Players.LocalPlayer
local fallbackProvider: () -> boolean = function()
    return false
end
local currentLevel = "hoch"
local evaluatedAt = -math.huge
local started = false
local listeners: { (string) -> () } = {}
-- Ursprünglicher Zustand der Effekte (Enabled), damit "hoch" sie wieder genau so einschaltet.
local savedEnabled: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function isEffect(instance: Instance): boolean
    for _, className in EFFECT_CLASSES do
        if instance:IsA(className) then
            return true
        end
    end
    return false
end

local function applyToEffect(instance: Instance, allowed: boolean)
    local effect = instance :: any
    if savedEnabled[instance] == nil then
        savedEnabled[instance] = effect.Enabled
    end
    effect.Enabled = if allowed then savedEnabled[instance] else false
end

local function applyPostEffects()
    local allowed = GraphicsLevel.settings(currentLevel).postEffects == true
    for _, child in Lighting:GetChildren() do
        if isEffect(child) then
            applyToEffect(child, allowed)
        end
    end
end

-- Grafikregler von Roblox (1 bis 10, 0 = Automatik oder unbekannt).
local function qualityLevel(): number
    local ok, value = pcall(function(): number
        return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
    end)
    if ok and type(value) == "number" then
        return value
    end
    return 0
end

local function evaluate()
    evaluatedAt = os.clock()
    local level = GraphicsLevel.pick({
        forced = player:GetAttribute(LEVEL_ATTRIBUTE),
        fallback = fallbackProvider(),
        touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
        quality = qualityLevel(),
    })
    if level ~= currentLevel then
        currentLevel = level
        print(`[Graphics] Stufe: {level}`)
        applyPostEffects()
        for _, listener in table.clone(listeners) do
            task.spawn(listener, level)
        end
    end
end

-- Aktuelle Stufe. Wertet höchstens alle REFRESH_SECONDS neu aus, ist also auch pro Bild billig.
function Graphics.level(): string
    if os.clock() - evaluatedAt >= REFRESH_SECONDS then
        evaluate()
    end
    return currentLevel
end

-- Einstellungen der aktuellen Stufe (Data/Screen: graphics.levels).
function Graphics.settings(): any
    return GraphicsLevel.settings(Graphics.level())
end

-- Meldet sich ab, wenn die zurückgegebene Funktion aufgerufen wird.
function Graphics.onChanged(listener: (string) -> ()): () -> ()
    table.insert(listeners, listener)
    return function()
        local index = table.find(listeners, listener)
        if index ~= nil then
            table.remove(listeners, index)
        end
    end
end

-- Dig meldet hier den Rückfall des Bildraten-Wächters (Modul Graphics kennt Dig nicht, damit sich
-- die beiden nicht gegenseitig laden).
function Graphics.setFallbackProvider(provider: () -> boolean)
    fallbackProvider = provider
    evaluatedAt = -math.huge
end

-- Startet die regelmäßige Auswertung und das Abschalten der Effekte. Mehrfach aufrufen ist harmlos.
function Graphics.start()
    if started then
        return
    end
    started = true
    evaluate()
    applyPostEffects()
    local accumulated = 0
    RunService.Heartbeat:Connect(function(dt: number)
        accumulated += dt
        if accumulated >= REFRESH_SECONDS then
            accumulated = 0
            evaluate()
        end
    end)
    -- Effekte, die später im Lighting auftauchen (zum Beispiel der Look aus Paket 3.4).
    Lighting.ChildAdded:Connect(function(child: Instance)
        if isEffect(child) then
            applyToEffect(child, GraphicsLevel.settings(currentLevel).postEffects == true)
        end
    end)
end

return Graphics
