--!strict
-- Kleine Assert-Bibliothek für die Lune-Tests.
-- Benutzung:
--   local T = require("./lib/expect")
--   T.describe("Name", function() T.it("tut etwas", function() T.expect(1).toBe(1) end) end)
--   T.finish()  -- am Ende der Datei: Zusammenfassung, Exit-Code 1 bei Fehlern
-- Tests laufen sofort beim Aufruf von it/test. `finish` ist idempotent und wird zusätzlich
-- automatisch nach dem Hauptteil der Datei aufgerufen.

local process = require("@lune/process")
local task = require("@lune/task")

export type Expectation = {
    toBe: (expected: any) -> (),
    toEqual: (expected: any) -> (),
    toBeCloseTo: (expected: number, tolerance: number?) -> (),
    toBeTruthy: () -> (),
    toBeFalsy: () -> (),
    toBeNil: () -> (),
    toContain: (item: any) -> (),
    toBeGreaterThan: (other: number) -> (),
    toBeLessThan: (other: number) -> (),
    toThrow: (substring: string?) -> (),
}

local T = {}

local passed = 0
local failed = 0
local failures: { string } = {}
local depth: { string } = {}
local finished = false
local scheduled = false

local function repr(value: any, seen: { [any]: boolean }?): string
    if type(value) == "string" then
        return string.format("%q", value)
    elseif type(value) ~= "table" then
        return tostring(value)
    end
    local visited = seen or {}
    if visited[value] then
        return "<zyklisch>"
    end
    visited[value] = true
    local keys = {}
    for key in value do
        table.insert(keys, key)
    end
    table.sort(keys, function(a: any, b: any)
        return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, key in keys do
        table.insert(parts, `{tostring(key)} = {repr(value[key], visited)}`)
    end
    visited[value] = nil
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function deepEqual(a: any, b: any): boolean
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        -- NaN ist gleich NaN
        return a ~= a and b ~= b
    end
    for key, value in a do
        if not deepEqual(value, b[key]) then
            return false
        end
    end
    for key in b do
        if a[key] == nil then
            return false
        end
    end
    return true
end

local function fail(message: string)
    error(message, 0)
end

function T.expect(actual: any): Expectation
    local expectation: Expectation = {
        toBe = function(expected: any)
            if actual ~= expected and not (actual ~= actual and expected ~= expected) then
                fail(`erwartet {repr(expected)}, erhalten {repr(actual)}`)
            end
        end,
        toEqual = function(expected: any)
            if not deepEqual(actual, expected) then
                fail(`erwartet gleich {repr(expected)}, erhalten {repr(actual)}`)
            end
        end,
        toBeCloseTo = function(expected: number, tolerance: number?)
            local tol = tolerance or 1e-9
            if type(actual) ~= "number" or math.abs(actual - expected) > tol then
                fail(`erwartet ca. {repr(expected)} (±{tol}), erhalten {repr(actual)}`)
            end
        end,
        toBeTruthy = function()
            if not actual then
                fail(`erwartet wahr, erhalten {repr(actual)}`)
            end
        end,
        toBeFalsy = function()
            if actual then
                fail(`erwartet falsch, erhalten {repr(actual)}`)
            end
        end,
        toBeNil = function()
            if actual ~= nil then
                fail(`erwartet nil, erhalten {repr(actual)}`)
            end
        end,
        toContain = function(item: any)
            if type(actual) == "string" and type(item) == "string" then
                if not string.find(actual, item, 1, true) then
                    fail(`Text {repr(actual)} enthält {repr(item)} nicht`)
                end
                return
            end
            if type(actual) == "table" then
                for _, value in actual do
                    if deepEqual(value, item) then
                        return
                    end
                end
            end
            fail(`{repr(actual)} enthält {repr(item)} nicht`)
        end,
        toBeGreaterThan = function(other: number)
            if type(actual) ~= "number" or not (actual > other) then
                fail(`erwartet > {other}, erhalten {repr(actual)}`)
            end
        end,
        toBeLessThan = function(other: number)
            if type(actual) ~= "number" or not (actual < other) then
                fail(`erwartet < {other}, erhalten {repr(actual)}`)
            end
        end,
        toThrow = function(substring: string?)
            if type(actual) ~= "function" then
                fail("toThrow erwartet eine Funktion")
            end
            local ok, err = pcall(actual :: any)
            if ok then
                fail("erwartet einen Fehler, es gab keinen")
            end
            if substring ~= nil and not string.find(tostring(err), substring, 1, true) then
                fail(`Fehler {repr(tostring(err))} enthält {repr(substring)} nicht`)
            end
        end,
    }
    return expectation
end

function T.finish()
    if finished then
        return
    end
    finished = true
    print(`\n{passed} bestanden, {failed} fehlgeschlagen`)
    if failed > 0 then
        for _, line in failures do
            print(line)
        end
        process.exit(1)
    end
end

local function schedule()
    if not scheduled then
        scheduled = true
        task.defer(T.finish)
    end
end

function T.describe(name: string, body: () -> ())
    table.insert(depth, name)
    print(`{string.rep("  ", #depth - 1)}{name}`)
    body()
    table.remove(depth)
end

function T.it(name: string, body: () -> ())
    schedule()
    local indent = string.rep("  ", #depth)
    local ok, err = pcall(body)
    if ok then
        passed += 1
        print(`{indent}ok   {name}`)
    else
        failed += 1
        print(`{indent}FAIL {name}\n{indent}     {tostring(err)}`)
        table.insert(failures, `FAIL {table.concat(depth, " > ")} > {name}: {tostring(err)}`)
    end
end

T.test = T.it

return T
