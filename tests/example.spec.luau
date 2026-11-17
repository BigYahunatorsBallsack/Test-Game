--!strict
-- Beispieltest: lädt Module aus src/shared per Pfad-require (wie Roblox mit Require-by-String).

local T = require("./lib/expect")
local Validate = require("../src/shared/Logic/Validate")
local Tools = require("../src/shared/Data/Tools")

T.describe("Beispiel", function()
    T.it("lädt ein Modul aus src/shared per Pfad", function()
        T.expect(type(Validate.check)).toBe("function")
        T.expect(#Tools.list).toBe(6)
    end)

    T.it("toThrow und toBeCloseTo funktionieren", function()
        T.expect(function()
            error("kaputt")
        end).toThrow("kaputt")
        T.expect(0.1 + 0.2).toBeCloseTo(0.3, 1e-9)
    end)
end)

T.finish()
