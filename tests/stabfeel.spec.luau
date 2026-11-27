--!strict
-- Überarbeitung Ü4: Gefühl beim Stechen (Logic/StabFeel, Data/StabFeel, Data/StabSounds, Arme in
-- Logic/FirstPerson).

local T = require("./lib/expect")
local StabFeel = require("../src/shared/Logic/StabFeel")
local Data = require("../src/shared/Data/StabFeel")
local Sounds = require("../src/shared/Data/StabSounds")
local Deposits = require("../src/shared/Logic/Deposits")
local DepositData = require("../src/shared/Data/Deposits")
local FirstPerson = require("../src/shared/Logic/FirstPerson")
local Tools = require("../src/shared/Data/Tools")
local Screen = require("../src/shared/Data/Screen")
local DataCheck = require("../src/shared/Logic/DataCheck")

local function copy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for k, v in value do
        result[k] = copy(v)
    end
    return result
end

T.describe("StabFeel: Daten", function()
    T.it("DataCheck meldet nichts zu StabFeel", function()
        for _, message in DataCheck.run() do
            T.expect(string.find(message, "StabFeel", 1, true)).toBeNil()
        end
    end)

    T.it("alle Töne sind leer (stumm) oder gültige IDs, je Schicht einer", function()
        T.expect(#Sounds.layers).toBe(#DepositData.layers)
        T.expect(#StabFeel.check(Data, Sounds, Screen.graphics.order, #DepositData.layers)).toBe(0)
    end)

    T.it("check findet kaputte Werte", function()
        local bad = copy(Data)
        bad.arm.strikeEnd = 0.5
        bad.arm.holdEnd = 0.2
        bad.ring.minSize = 50
        bad.camera.downShare = 1
        bad.throw.perStab.hoch = 1.5
        bad.arm.animationId = "123"
        local badSounds = copy(Sounds)
        badSounds.clean.soundId = "http://boese"
        badSounds.layers[1].volume = 2
        local errors = StabFeel.check(bad, badSounds, Screen.graphics.order, #DepositData.layers)
        T.expect(#errors >= 7).toBe(true)
        local fewSounds = copy(Sounds)
        table.remove(fewSounds.layers)
        T.expect(#StabFeel.check(Data, fewSounds, Screen.graphics.order, #DepositData.layers)).toBe(1)
    end)
end)

T.describe("StabFeel: Arme", function()
    T.it("Kurve beginnt und endet in Ruhe, ganz unten nach dem Einstechen", function()
        T.expect(StabFeel.armStroke(0)).toBe(0)
        T.expect(StabFeel.armStroke(1)).toBe(0)
        T.expect(StabFeel.armStroke(Data.arm.strikeEnd)).toBe(1)
        T.expect(StabFeel.armStroke((Data.arm.strikeEnd + Data.arm.holdEnd) / 2)).toBe(1)
        T.expect(StabFeel.armStroke(0.999) < 0.01).toBe(true)
        T.expect(StabFeel.armStroke(0 / 0)).toBe(0)
        -- steigt beim Einstechen, fällt danach
        local last = -1
        for i = 0, 18 do
            local v = StabFeel.armStroke(i / 100)
            T.expect(v >= last).toBe(true)
            last = v
        end
        for i = 30, 99 do
            local v = StabFeel.armStroke(i / 100)
            T.expect(v <= last + 1e-12).toBe(true)
            last = v
        end
    end)

    T.it("ein Stich dauert genau einen Takt, für jedes Werkzeug", function()
        for _, tool in Tools.list do
            local interval = Deposits.stabSeconds(tool.id)
            T.expect(StabFeel.phase(10, 10, interval)).toBe(0)
            T.expect(StabFeel.phase(10 + interval * 0.5, 10, interval)).toBeCloseTo(0.5, 1e-9)
            T.expect(StabFeel.phase(10 + interval + 1e-6, 10, interval)).toBeNil()
            T.expect(StabFeel.phase(9.9, 10, interval)).toBeNil()
        end
        T.expect(StabFeel.phase(10, nil, 0.5)).toBeNil()
        T.expect(StabFeel.phase(10, 10, 0)).toBeNil()
    end)

    T.it("der Stich ersetzt die gleichmäßige Grabbewegung der Hand", function()
        local rest = FirstPerson.viewPose("shovel", { t = 0.2, collecting = false, speed = 0 })
        local down = FirstPerson.viewPose("shovel", { t = 0.2, collecting = false, stab = 1, speed = 0 })
        T.expect(rest.right.move.z).toBe(0)
        T.expect(down.right.move.z < 0).toBe(true)
        -- Stich 0 zwischen zwei Stichen: Hand in Ruhe, auch wenn gesammelt wird
        local between = FirstPerson.viewPose("shovel", { t = 0.2, collecting = true, stab = 0, speed = 0 })
        T.expect(between.right.move.z).toBe(0)
        -- ohne Stich (Auto-Dig) bleibt die alte Bewegung
        local auto = FirstPerson.viewPose("shovel", { t = 0.2, collecting = true, speed = 0 })
        T.expect(auto.right.move.z < 0).toBe(true)
    end)
end)

T.describe("StabFeel: Takt-Ring", function()
    T.it("voll direkt nach dem Stich, klein beim nächsten Takt, nie außerhalb 0 bis 1", function()
        T.expect(StabFeel.ringFraction(10, 10, 10.5)).toBe(1)
        T.expect(StabFeel.ringFraction(10.25, 10, 10.5)).toBeCloseTo(0.5, 1e-9)
        T.expect(StabFeel.ringFraction(10.5, 10, 10.5)).toBe(0)
        T.expect(StabFeel.ringFraction(11, 10, 10.5)).toBe(0)
        T.expect(StabFeel.ringFraction(9, 10, 10.5)).toBe(1)
        T.expect(StabFeel.ringFraction(10, nil, nil)).toBe(0)
        T.expect(StabFeel.ringSize(1)).toBe(Data.ring.maxSize)
        T.expect(StabFeel.ringSize(0)).toBe(Data.ring.minSize)
        T.expect(StabFeel.ringSize(0 / 0)).toBe(Data.ring.minSize)
    end)
end)

T.describe("StabFeel: Kamera-Ruck", function()
    T.it("stärker je Schicht, gedeckelt, auf minimal aus", function()
        local top = StabFeel.cameraKick(1, "hoch")
        local core = StabFeel.cameraKick(3, "hoch")
        T.expect(top.studs).toBeCloseTo(Data.camera.studs, 1e-12)
        T.expect(core.studs > top.studs).toBe(true)
        T.expect(StabFeel.cameraKick(50, "hoch").studs).toBeCloseTo(Data.camera.studs * Data.camera.maxFactor, 1e-12)
        local off = StabFeel.cameraKick(3, "minimal")
        T.expect(off.studs).toBe(0)
        T.expect(off.degrees).toBe(0)
        T.expect(StabFeel.cameraKick(nil, "schlank").studs).toBeCloseTo(Data.camera.studs, 1e-12)
    end)

    T.it("Verlauf: 0 am Anfang und Ende, 1 ganz unten", function()
        T.expect(StabFeel.kickEnvelope(0)).toBe(0)
        T.expect(StabFeel.kickEnvelope(Data.camera.seconds)).toBe(0)
        T.expect(StabFeel.kickEnvelope(Data.camera.seconds * Data.camera.downShare)).toBeCloseTo(1, 1e-9)
        T.expect(StabFeel.kickEnvelope(-1)).toBe(0)
        for i = 1, 99 do
            local v = StabFeel.kickEnvelope(Data.camera.seconds * i / 100)
            T.expect(v >= 0 and v <= 1).toBe(true)
        end
    end)
end)

T.describe("StabFeel: Sandwurf und Eimer", function()
    T.it("Bogen beginnt am Loch, endet am Eimer und steigt dazwischen", function()
        local from = { x = 0, y = 0, z = 0 }
        local to = { x = 4, y = 2, z = -2 }
        T.expect(StabFeel.throwPoint(from, to, 0)).toEqual(from)
        T.expect(StabFeel.throwPoint(from, to, 1)).toEqual(to)
        local mid = StabFeel.throwPoint(from, to, 0.5)
        T.expect(mid.y).toBeCloseTo(1 + Data.throw.arcStuds, 1e-9)
        T.expect(StabFeel.throwPoint(from, to, 5)).toEqual(to)
    end)

    T.it("Farbe wird je Schicht dunkler, gedeckelt", function()
        T.expect(StabFeel.darken(1)).toBe(0)
        T.expect(StabFeel.darken(2)).toBeCloseTo(Data.throw.layerDarken, 1e-12)
        T.expect(StabFeel.darken(3) > StabFeel.darken(2)).toBe(true)
        T.expect(StabFeel.darken(100)).toBe(Data.throw.maxDarken)
        T.expect(StabFeel.darken(nil)).toBe(0)
    end)

    T.it("Anzahl Klumpen je Grafikstufe, nie mehr als maxActive gleichzeitig", function()
        T.expect(StabFeel.throwCount("hoch", 0)).toBe(Data.throw.perStab.hoch)
        T.expect(StabFeel.throwCount("hoch", Data.throw.maxActive.hoch - 1)).toBe(1)
        T.expect(StabFeel.throwCount("hoch", Data.throw.maxActive.hoch)).toBe(0)
        T.expect(StabFeel.throwCount("schlank", 0) < StabFeel.throwCount("hoch", 0)).toBe(true)
        T.expect(StabFeel.throwCount("minimal", 0)).toBe(0)
        T.expect(StabFeel.throwCount("gibt_es_nicht", 0)).toBe(0)
        -- Simulation: Stiche im Takt mit 0,35 s Flugzeit, nie mehr als maxActive
        local active: { number } = {}
        local most = 0
        local t = 0
        for _ = 1, 200 do
            for i = #active, 1, -1 do
                if t - active[i] >= Data.throw.seconds then
                    table.remove(active, i)
                end
            end
            for _ = 1, StabFeel.throwCount("hoch", #active) do
                table.insert(active, t)
            end
            most = math.max(most, #active)
            t += 0.35
        end
        T.expect(most <= Data.throw.maxActive.hoch).toBe(true)
    end)

    T.it("Eimer-Sand hüpft kurz und ist danach wieder in Ruhe", function()
        T.expect(StabFeel.bucketBump(0)).toBe(0)
        T.expect(StabFeel.bucketBump(Data.bucket.bumpSeconds / 2)).toBeCloseTo(Data.bucket.bumpStuds, 1e-9)
        T.expect(StabFeel.bucketBump(Data.bucket.bumpSeconds)).toBe(0)
        T.expect(StabFeel.bucketBump(math.huge)).toBe(0)
    end)
end)

T.describe("StabFeel: Töne", function()
    local filled = copy(Sounds)
    filled.layers[1].soundId = "rbxassetid://1"
    filled.layers[2].soundId = "rbxassetid://2"
    filled.layers[3].soundId = "rbxassetid://3"
    filled.clean.soundId = "rbxassetid://4"

    T.it("richtiger Ton je Schicht, unbekannte Schicht wird begrenzt", function()
        T.expect((StabFeel.pickSound("layer", 1, 0.5, filled) :: any).soundId).toBe("rbxassetid://1")
        T.expect((StabFeel.pickSound("layer", 3, 0.5, filled) :: any).soundId).toBe("rbxassetid://3")
        T.expect((StabFeel.pickSound("layer", 9, 0.5, filled) :: any).soundId).toBe("rbxassetid://3")
        T.expect((StabFeel.pickSound("layer", nil, 0.5, filled) :: any).soundId).toBe("rbxassetid://1")
        T.expect((StabFeel.pickSound("clean", nil, 0.5, filled) :: any).soundId).toBe("rbxassetid://4")
    end)

    T.it("Tonhöhe bleibt in ±pitchJitter", function()
        for i = 0, 100 do
            local pick = StabFeel.pickSound("layer", 2, i / 100, filled) :: any
            local base = filled.layers[2].pitch
            T.expect(math.abs(pick.pitch / base - 1) <= Sounds.pitchJitter + 1e-12).toBe(true)
        end
    end)

    T.it("leere ID spielt nichts, kein Fehler", function()
        T.expect(StabFeel.pickSound("empty", nil, 0.5, filled)).toBeNil()
        T.expect(StabFeel.pickSound("layer", 1, 0.5, Sounds) == nil or Sounds.layers[1].soundId ~= "").toBe(true)
        T.expect(StabFeel.pickSound("gibt_es_nicht", nil, 0.5, filled)).toBeNil()
    end)
end)
