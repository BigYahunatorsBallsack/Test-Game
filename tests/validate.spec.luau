--!strict
-- Paket 0.3: Argument-Validierung für Remotes.

local T = require("./lib/expect")
local Validate = require("../src/shared/Logic/Validate")

local ids = { dunes = true, oasis = true }

local function check(schema: { Validate.Rule }, ...: any): (boolean, string?)
    return Validate.check(schema, { ... }, select("#", ...))
end

T.describe("Validate", function()
    T.it("gültige Argumente gehen durch", function()
        T.expect((check({ Validate.boolean() }, true))).toBe(true)
        T.expect((check({ Validate.boolean() }, false))).toBe(true)
        T.expect((check({ Validate.string(5) }, "abcde"))).toBe(true)
        T.expect((check({ Validate.int(1, 10) }, 10))).toBe(true)
        T.expect((check({ Validate.oneOf({ 1, 10 }) }, 10))).toBe(true)
        T.expect((check({ Validate.idIn(ids, 32) }, "oasis"))).toBe(true)
        T.expect((check({}))).toBe(true)
        T.expect((check({ Validate.idIn(ids), Validate.oneOf({ 1, 10 }) }, "dunes", 1))).toBe(true)
    end)

    T.it("falscher Typ wird abgelehnt", function()
        T.expect((check({ Validate.boolean() }, "true"))).toBe(false)
        T.expect((check({ Validate.boolean() }, 1))).toBe(false)
        T.expect((check({ Validate.string(5) }, 5))).toBe(false)
        T.expect((check({ Validate.int(1, 10) }, "5"))).toBe(false)
        T.expect((check({ Validate.int(1, 10) }, {}))).toBe(false)
        T.expect((check({ Validate.idIn(ids) }, 1))).toBe(false)
        T.expect((check({ Validate.idIn(ids) }, { "dunes" }))).toBe(false)
        T.expect((check({ Validate.boolean() }, nil))).toBe(false)
    end)

    T.it("zu wenige oder zu viele Argumente werden abgelehnt", function()
        T.expect((check({ Validate.boolean() }))).toBe(false)
        T.expect((check({ Validate.boolean() }, true, true))).toBe(false)
        T.expect((check({}, true))).toBe(false)
        T.expect((check({ Validate.boolean() }, true, nil))).toBe(false) -- angehängtes nil zählt
        T.expect((check({ Validate.idIn(ids), Validate.oneOf({ 1, 10 }) }, "dunes"))).toBe(false)
        local _, reason = check({ Validate.boolean() })
        T.expect(reason).toContain("Argumentzahl")
    end)

    T.it("NaN und Unendlich werden abgelehnt", function()
        local nan = 0 / 0
        T.expect((check({ Validate.int(0, 10) }, nan))).toBe(false)
        T.expect((check({ Validate.int(-math.huge, math.huge) }, math.huge))).toBe(false)
        T.expect((check({ Validate.int(-math.huge, math.huge) }, -math.huge))).toBe(false)
        T.expect((check({ Validate.oneOf({ 1, 10 }) }, nan))).toBe(false)
        T.expect((check({ Validate.oneOf({ 1, 10 }) }, math.huge))).toBe(false)
    end)

    T.it("Brüche und Werte außerhalb des Bereichs werden abgelehnt", function()
        T.expect((check({ Validate.int(1, 10) }, 1.5))).toBe(false)
        T.expect((check({ Validate.int(1, 10) }, 0))).toBe(false)
        T.expect((check({ Validate.int(1, 10) }, 11))).toBe(false)
        T.expect((check({ Validate.int(1, 10) }, 1))).toBe(true)
        T.expect((check({ Validate.oneOf({ 1, 10 }) }, 5))).toBe(false)
        T.expect((check({ Validate.oneOf({ 1, 10 }) }, "1"))).toBe(false)
    end)

    T.it("zu lange Texte werden abgelehnt", function()
        T.expect((check({ Validate.string(5) }, "abcdef"))).toBe(false)
        T.expect((check({ Validate.idIn(ids, 4) }, "oasis"))).toBe(false)
        T.expect((check({ Validate.idIn(ids, 32) }, string.rep("a", 1000)))).toBe(false)
    end)

    T.it("unbekannte IDs werden abgelehnt", function()
        T.expect((check({ Validate.idIn(ids, 32) }, "mars"))).toBe(false)
        T.expect((check({ Validate.idIn(ids, 32) }, ""))).toBe(false)
        local _, reason = check({ Validate.idIn(ids, 32) }, "mars")
        T.expect(reason).toContain("unbekannte ID")
    end)
end)

T.finish()
