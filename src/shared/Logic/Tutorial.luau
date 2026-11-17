--!strict
-- Tutorial-Fortschritt (Paket 1.6). Rein, ohne Roblox-API, Lune-Tests in tests/tutorial.spec.luau.
--
-- Der Fortschritt ist `profile.tutorial.step`: 1 bis #Schritte = aktueller Schritt,
-- #Schritte + 1 = fertig. Schritte gehen nie zurück. Der Server ruft `evaluate` nach jeder
-- Änderung auf (Tank, Kauf, Laden) und `onSold` nach einem Verkauf. Beim Laden zählen auch
-- erledigte Knoten-Schritte: Wer die Schaufel schon besitzt, bekommt kein Tutorial mehr.

local BigNum = require("./BigNum")
local TutorialData = require("../Data/Tutorial")

local Tutorial = {}

local steps = TutorialData.steps

-- Anzahl der Schritte. Ein Fortschritt von #Schritte + 1 bedeutet "fertig".
function Tutorial.count(): number
    return #steps
end

local function stepOf(profile: any): number
    local value = profile.tutorial and profile.tutorial.step
    if type(value) ~= "number" or value ~= value or value ~= math.floor(value) then
        return 1
    end
    return math.clamp(value, 1, #steps + 1)
end

-- Aktueller Schritt (1 bis #Schritte + 1) nach Bereinigung ungültiger Werte.
function Tutorial.stepOf(profile: any): number
    return stepOf(profile)
end

function Tutorial.isDone(profile: any): boolean
    return stepOf(profile) > #steps
end

-- Daten des aktuellen Schritts, nil wenn fertig.
function Tutorial.current(profile: any): TutorialData.Step?
    return steps[stepOf(profile)]
end

local function set(profile: any, step: number)
    if type(profile.tutorial) ~= "table" then
        profile.tutorial = { step = step }
    else
        profile.tutorial.step = step
    end
end

-- Ist die Bedingung eines Schritts allein aus dem Profil erfüllt? "sold" ist ein Ereignis.
local function met(profile: any, condition: TutorialData.Condition): boolean
    if condition.kind == "tankAtLeast" then
        return BigNum.compare(BigNum.deserialize(profile.tank), BigNum.new(condition.amount or 0)) >= 0
    elseif condition.kind == "node" then
        return profile.nodes[condition.nodeId :: string] == true
    end
    return false
end

-- Rückt weiter, solange die Bedingung des aktuellen Schritts erfüllt ist, und überspringt
-- Knoten-Schritte, die der Spieler schon erledigt hat (auch weiter vorn in der Reihe).
-- Gibt zurück, ob sich der Schritt geändert hat.
function Tutorial.evaluate(profile: any): boolean
    local before = stepOf(profile)
    local step = before
    -- Erledigte Knoten-Schritte: der Fortschritt springt hinter den letzten davon.
    for i, s in steps do
        if s.done.kind == "node" and met(profile, s.done) and i + 1 > step then
            step = i + 1
        end
    end
    while step <= #steps and met(profile, steps[step].done) do
        step += 1
    end
    -- Ein ungültiger gespeicherter Wert wird dabei auf den bereinigten Wert gesetzt.
    set(profile, step)
    return step ~= before
end

-- Ein Verkauf ist passiert: Steht der Spieler vor oder bei dem Verkaufs-Schritt, rückt er
-- dahinter (wer schon vor dem vollen Tank verkauft, braucht den Sammeln-Schritt nicht mehr).
-- Gibt zurück, ob sich der Schritt geändert hat.
function Tutorial.onSold(profile: any): boolean
    local before = stepOf(profile)
    for index, s in steps do
        if s.done.kind == "sold" then
            if before <= index then
                set(profile, index + 1)
                Tutorial.evaluate(profile)
                return true
            end
            break
        end
    end
    return false
end

return Tutorial
