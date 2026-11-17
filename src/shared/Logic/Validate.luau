--!strict
-- Schema-Prüfung für Remote-Argumente. Rein, ohne Roblox-API.
-- Ein Schema ist eine Liste von Regeln, eine Regel je Argument in fester Reihenfolge.
-- Der Server prüft jedes Argument, bevor ein Handler läuft (Client sendet nur Absichten).

export type Rule =
    { kind: "boolean" }
    | { kind: "string", maxLen: number }
    | { kind: "int", min: number, max: number }
    | { kind: "oneOf", values: { any } }
    | { kind: "idIn", ids: { [string]: any }, maxLen: number }

local Validate = {}

local DEFAULT_ID_MAX_LEN = 64

function Validate.boolean(): Rule
    return { kind = "boolean" }
end

function Validate.string(maxLen: number): Rule
    return { kind = "string", maxLen = maxLen }
end

-- Ganze Zahl im Bereich min bis max (beide eingeschlossen).
function Validate.int(min: number, max: number): Rule
    return { kind = "int", min = min, max = max }
end

-- Genau einer der erlaubten Werte (Zahlen, Texte oder Booleans).
function Validate.oneOf(values: { any }): Rule
    return { kind = "oneOf", values = values }
end

-- Text, der als Schlüssel in der Tabelle `ids` vorkommt (z. B. Zones.byId).
function Validate.idIn(ids: { [string]: any }, maxLen: number?): Rule
    return { kind = "idIn", ids = ids, maxLen = maxLen or DEFAULT_ID_MAX_LEN }
end

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function describe(value: any): string
    if type(value) == "number" then
        if value ~= value then
            return "NaN"
        end
        return tostring(value)
    end
    return type(value)
end

-- Prüft ein einzelnes Argument. Gibt (true, nil) oder (false, Grund) zurück.
local function checkOne(rule: Rule, value: any, index: number): (boolean, string?)
    if rule.kind == "boolean" then
        if type(value) ~= "boolean" then
            return false, `Argument {index}: boolean erwartet, {describe(value)} erhalten`
        end
        return true, nil
    elseif rule.kind == "string" then
        if type(value) ~= "string" then
            return false, `Argument {index}: string erwartet, {describe(value)} erhalten`
        end
        if #value > rule.maxLen then
            return false, `Argument {index}: Text zu lang ({#value} > {rule.maxLen})`
        end
        return true, nil
    elseif rule.kind == "int" then
        if type(value) ~= "number" then
            return false, `Argument {index}: number erwartet, {describe(value)} erhalten`
        end
        if not isFinite(value) then
            return false, `Argument {index}: ungültige Zahl ({describe(value)})`
        end
        if value % 1 ~= 0 then
            return false, `Argument {index}: ganze Zahl erwartet ({value})`
        end
        if value < rule.min or value > rule.max then
            return false, `Argument {index}: außerhalb des Bereichs {rule.min} bis {rule.max} ({value})`
        end
        return true, nil
    elseif rule.kind == "oneOf" then
        if type(value) == "number" and not isFinite(value) then
            return false, `Argument {index}: ungültige Zahl ({describe(value)})`
        end
        for _, allowed in rule.values do
            if allowed == value and type(allowed) == type(value) then
                return true, nil
            end
        end
        return false, `Argument {index}: Wert nicht erlaubt ({describe(value)})`
    else
        if type(value) ~= "string" then
            return false, `Argument {index}: string erwartet, {describe(value)} erhalten`
        end
        if #value > rule.maxLen then
            return false, `Argument {index}: ID zu lang ({#value} > {rule.maxLen})`
        end
        if rule.ids[value] == nil then
            return false, `Argument {index}: unbekannte ID`
        end
        return true, nil
    end
end

-- Prüft alle Argumente gegen das Schema. `argCount` ist die echte Anzahl der übergebenen
-- Argumente (in Roblox `select("#", ...)`), damit auch angehängte nil-Werte auffallen.
function Validate.check(schema: { Rule }, args: { any }, argCount: number): (boolean, string?)
    if argCount ~= #schema then
        return false, `falsche Argumentzahl: erwartet {#schema}, erhalten {argCount}`
    end
    for index, rule in schema do
        local ok, reason = checkOne(rule, args[index], index)
        if not ok then
            return false, reason
        end
    end
    return true, nil
end

return Validate
