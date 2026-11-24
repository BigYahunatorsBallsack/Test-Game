--!strict
-- Analytics (Paket 6.3): Regeln für Trichter, Käufe, Sitzungslänge und Rückkehr. Rein, ohne Roblox-API,
-- Lune-Tests in tests/analytics.spec.luau. Der Service Analytics schickt die Ergebnisse an AnalyticsService.

local TutorialData = require("../Data/Tutorial")
local AnalyticsData = require("../Data/Analytics")

export type Data = { Analytics: any?, Tutorial: any? }

local Analytics = {}

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function dataOf(data: Data?): any
    if data ~= nil and data.Analytics ~= nil then
        return data.Analytics
    end
    return AnalyticsData
end

local function stepsOf(data: Data?): any
    if data ~= nil and data.Tutorial ~= nil then
        return data.Tutorial.steps
    end
    return TutorialData.steps
end

-- Trichter-Schritt für den Tutorial-Fortschritt `step` (profile.tutorial.step): 1 bis #Schritte = Schritt mit
-- Namen aus Data/Tutorial, #Schritte + 1 = "done". Ergebnis { step, name } oder nil bei kaputter Zahl.
function Analytics.tutorialStep(step: any, data: Data?): { step: number, name: string }?
    if not isFinite(step) or step < 1 or step % 1 ~= 0 then
        return nil
    end
    local steps = stepsOf(data)
    local count = #steps
    if step <= count then
        local entry = steps[step]
        if type(entry) ~= "table" or type(entry.id) ~= "string" or entry.id == "" then
            return nil
        end
        return { step = step, name = entry.id }
    end
    if step == count + 1 then
        return { step = step, name = dataOf(data).onboardingDoneName }
    end
    return nil
end

-- Neue Einträge des Kaufprotokolls: jeder Eintrag mit neuer `purchaseId` genau einmal (merkt sich die IDs in
-- `seen`). Kaputte Einträge werden übersprungen. Die Liste ist gekürzt (nur die neuesten), darum zählt die
-- ID, nicht die Länge. Mit `markOnly = true` werden vorhandene Einträge nur gemerkt (beim Laden).
function Analytics.newPurchases(log: any, seen: { [string]: boolean }, markOnly: boolean?): { any }
    local fresh: { any } = {}
    if type(log) ~= "table" then
        return fresh
    end
    for _, entry in log do
        if type(entry) == "table" and type(entry.purchaseId) == "string" and entry.purchaseId ~= "" and not seen[entry.purchaseId] then
            seen[entry.purchaseId] = true
            if markOnly ~= true and type(entry.productId) == "string" and isFinite(entry.gems) and entry.gems >= 0 then
                table.insert(fresh, entry)
            end
        end
    end
    return fresh
end

-- Eimer der Sitzungslänge in Sekunden. Kaputte oder negative Zahl: nil.
function Analytics.sessionBucket(seconds: any, data: Data?): string?
    if not isFinite(seconds) or seconds < 0 then
        return nil
    end
    for _, bucket in dataOf(data).sessionBuckets do
        if seconds < bucket.maxSeconds then
            return bucket.name
        end
    end
    return nil
end

-- Rückkehr: { isNew, days }. Neu, wenn das Profil höchstens `newPlayerSeconds` alt ist. Sonst Tage seit dem
-- letzten Besuch (0 bis maxReturnDays). Kaputte Zeiten ergeben nil.
function Analytics.returnInfo(lastSeen: any, createdAt: any, now: any, data: Data?): { isNew: boolean, days: number }?
    if not isFinite(now) or not isFinite(createdAt) or not isFinite(lastSeen) then
        return nil
    end
    local cfg = dataOf(data)
    if now - createdAt <= cfg.newPlayerSeconds then
        return { isNew = true, days = 0 }
    end
    local days = math.floor(math.max(now - lastSeen, 0) / 86400)
    return { isNew = false, days = math.min(days, cfg.maxReturnDays) }
end

-- Zusatzfelder für ein Ereignis: nur Text bis maxFieldLength Zeichen und endliche Zahlen, Schlüssel nur Text.
-- Alles andere (Tabellen, Instanzen, NaN) fällt weg.
function Analytics.cleanFields(fields: any, data: Data?): { [string]: any }
    local clean: { [string]: any } = {}
    if type(fields) ~= "table" then
        return clean
    end
    local limit = dataOf(data).maxFieldLength
    for key, value in fields do
        if type(key) == "string" and key ~= "" then
            if type(value) == "string" then
                clean[key] = string.sub(value, 1, limit)
            elseif isFinite(value) then
                clean[key] = value
            end
        end
    end
    return clean
end

return Analytics
