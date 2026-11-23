--!strict
-- Saison-Pass (Paket 5.5): Saison-Punkte, Stufen (5.5a), Abholen und Kauf (5.5b). Reine Logik ohne
-- Roblox-API, getestet mit Lune (tests/seasonpoints.spec.luau, tests/seasonpass.spec.luau).
--
-- Regeln Punkte (5.5a):
--  * Punkte kommen nur aus Sammelzeit in der Event-Zone, die der Server rechnet (`addSeconds`).
--    Der Client sendet nie Punkte oder Zeiten. Je `Economy.seasonPass.secondsPerPoint` Sekunden gibt es
--    einen Punkt.
--  * Gespeichert werden die Sekunden (`profile.seasons[seasonId].seconds`), die Punkte werden daraus
--    gerechnet und sind durch die letzte Stufe gedeckelt. Mehr Sekunden als dafür nötig werden nicht
--    gespeichert (kein Überlauf, kein Dauerzähler).
--  * Die Zählung gilt nur für die laufende Saison, deren Event-Zone offen ist (Logic/Seasons). Der
--    Aufrufer (Services/Events) prüft das; hier wird nur gerechnet.
--  * Profil: `profile.seasons[seasonId] = { seconds, premium, claimed = { free = {}, premium = {} } }`.
--    `claimed` hat die Stufennummer als Textschlüssel ("3" -> true), weil der DataStore keine
--    Zahlenschlüssel in Wörterbüchern speichert.
--
-- Regeln Abholen und Kauf (5.5b). Zeit ist immer die Server-Zeit des Aufrufers (Services/SeasonClock),
-- nie ein Wert vom Client:
--  * Saison des Passes (`current`): die laufende Saison, wenn sie Stufen hat; sonst die zuletzt beendete
--    (Seasons.lastEnded), solange ihre Abholfrist läuft (`Economy.seasonPass.claimGraceDays` Tage nach
--    dem Ende, das Ende der Frist ist ausschließend). Danach "expired", ohne beendete Saison mit Stufen
--    "noSeason". Laufen zwei Saisons ohne Pause hintereinander, gilt ab dem Start der neuen nur sie.
--  * Abholen (`claim`): Stufe n ist erreicht, wenn die Punkte >= ihren Stufenpunkten sind (nie früher,
--    ein Sprung über mehrere Stufen erreicht alle). Je Stufe und Spur genau einmal
--    (`claimed.free|premium["n"] = true`), die Premium-Spur nur mit `premium == true`. Belohnungen sind
--    fest, nie Kisten oder Zufall, darum auch bei gesperrten Zufallsitems (ArePaidRandomItemsRestricted)
--    erlaubt: gems (Gems.grant, gekappt bei maxGems; die Abholung gilt trotzdem), coinBoost und luck
--    (Perks.extendCoinBoost/extendLuckBoost mit der echten Server-Uhr `ctx.boostNow`), item (ein
--    Exemplar eines Pass-Items `passOnly = true` im Inventar-Feld seiner Art, wie Kisten-Items).
--    Gründe in dieser Reihenfolge: "error" (kein Profil, kaputte Uhr, unbekannte Spur), "noSeason" /
--    "expired", "notReached" (auch eine Stufe, die es nicht gibt), "needPass", "claimed".
--    Prüfen und Rechnen laufen in einer eigenen Koroutine auf Arbeitskopien (wie Logic/Daily). Wirft
--    oder wartet sie, wird nichts geschrieben ("error", `detail` nur fürs Protokoll). Danach weist
--    derselbe Thread nur fertige Werte zu (`seasons` und je nach Belohnung `gems`, `boosts`,
--    `inventory`): Belohnung und Merker zusammen oder gar nicht.
--  * Kaufdialog (`buyCheck`): nur in der laufenden Saison mit Stufen ("noSeason"), nur ohne Pass
--    dieser Saison ("owned"), nur wenn die Saison eine `passId` hat, die ein Developer Product mit echter
--    ProductId (> 0) ist ("notOffered"; 0 ist der Platzhalter).
--  * Kauf-Handler (`passHandler`, für Logic/Purchases, ProcessReceipt): Saison der Zahlung = `current`
--    zur Zeit des Spielers (Uhr `clock(userId)` aus dem Kontext). Passt ihre `passId` zum bezahlten
--    Produkt und hat das Profil den Pass noch nicht: `seasons[id].premium = true` (fehlender Eintrag über
--    `newEntry`, bestehende Felder bleiben). Sonst (schon Pass, keine passende Saison, Frist vorbei)
--    gibt es nie einen zweiten Pass, sondern `Economy.seasonPass.duplicateGems` Gems. Bezahlt ist bezahlt:
--    nil (NotProcessedYet) nur bei kaputter Uhr oder kaputten Daten. Meldung nach dem bestätigten
--    Speichern: Notify-Art "seasonPassBought" mit { seasonId, duplicate, gems? }.
--  * Anzeige (`view`): StateSync-Feld `seasonPass` während der laufenden Saison mit Stufen und in der
--    Abholfrist danach (`ended = true`, `canBuy = false`), sonst nil.
--  * Daten kommen als Argument (`data = { Economy, SeasonPass, Seasons, CrateItems, Products }`), Vorgabe
--    sind die echten Tabellen. So läuft eine zweite Saison in Lune nur über Testtabellen.

local Equipment = require("./Equipment")
local Gems = require("./Gems")
local Perks = require("./Perks")
local Seasons = require("./Seasons")

local SeasonPass = {}

export type Entry = {
    seconds: number,
    premium: boolean,
    claimed: { free: { [string]: boolean }, premium: { [string]: boolean } },
}

export type Data = { Economy: any?, SeasonPass: any?, Seasons: any?, CrateItems: any?, Products: any? }

-- Saison des Passes zu einer Zeit (`current`).
export type Current = {
    season: any, -- Zeile aus Data/Seasons
    ended: boolean, -- true: Saison vorbei, nur noch Abholfrist
    claimSecondsLeft: number, -- Sekunden bis zum Ende der Abholfrist (laufend: Saisonrest plus Frist)
}

-- Kontext für `claim`.
export type ClaimContext = {
    boostNow: number?, -- echte Server-Uhr für Boosts (in Studio kann die Saison-Uhr verschoben sein)
    data: Data?, -- Tests
}

-- Antwort eines Kauf-Handlers (Form wie Purchases.Prepared, ohne require auf Purchases).
type Prepared = {
    changes: { [string]: any },
    gems: number,
    announce: ((profile: any) -> (string, { [string]: any }))?,
}

SeasonPass.TRACKS = { "free", "premium" }
-- Höchste Stufennummer, die die Remote ClaimSeasonReward annimmt (RemoteSpec); DataCheck verlangt
-- höchstens so viele Stufen je Saison.
SeasonPass.MAX_TIERS = 50
-- Meldung an den Client nach einem bestätigten Kauf (Notify-Art).
SeasonPass.PASS_BOUGHT_KIND = "seasonPassBought"
-- Studio-Hilfe DebugSeasonPass: "points:N", "premium", "reset".
SeasonPass.DEBUG_POINTS_PREFIX = "points:"
SeasonPass.DEBUG_PREMIUM = "premium"
SeasonPass.DEBUG_RESET = "reset"

local DEBUG_MAX_LENGTH = 24
local DEVELOPER_PRODUCT = "developerProduct"
local TRACK_SET: { [string]: boolean } = { free = true, premium = true }

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isWholePositive(value: any): boolean
    return isFinite(value) and value > 0 and value % 1 == 0
end

local function isWholeAtLeastZero(value: any): boolean
    return isFinite(value) and value >= 0 and value % 1 == 0
end

local function fail(reason: string, detail: string?): any
    return { ok = false, reason = reason, detail = detail }
end

local function economyOf(data: Data?): any
    if data ~= nil and data.Economy ~= nil then
        return data.Economy
    end
    return require("../Data/Economy")
end

local function tablesOf(data: Data?): any
    if data ~= nil and data.SeasonPass ~= nil then
        return data.SeasonPass
    end
    return require("../Data/SeasonPass")
end

local function calendarOf(data: Data?): any
    if data ~= nil and data.Seasons ~= nil then
        return data.Seasons
    end
    return require("../Data/Seasons")
end

local function itemsOf(data: Data?): any
    if data ~= nil and data.CrateItems ~= nil then
        return data.CrateItems
    end
    return require("../Data/CrateItems")
end

local function productsOf(data: Data?): any
    if data ~= nil and data.Products ~= nil then
        return data.Products
    end
    return require("../Data/Products")
end

-- Sekunden je Punkt (endlich und größer 0). Wirft bei kaputten Daten (DataCheck prüft beim Start).
function SeasonPass.secondsPerPoint(data: Data?): number
    local config = economyOf(data).seasonPass
    if type(config) ~= "table" or not isFinite(config.secondsPerPoint) or config.secondsPerPoint <= 0 then
        error("SeasonPass: Economy.seasonPass.secondsPerPoint fehlt")
    end
    return config.secondsPerPoint
end

-- Stufen einer Saison oder nil.
function SeasonPass.tiersOf(seasonId: any, data: Data?): { any }?
    if type(seasonId) ~= "string" then
        return nil
    end
    local row = tablesOf(data).bySeason[seasonId]
    if type(row) ~= "table" or type(row.tiers) ~= "table" then
        return nil
    end
    return row.tiers
end

-- Punktestand der letzten Stufe (0 ohne Stufen).
function SeasonPass.maxPoints(seasonId: any, data: Data?): number
    local tiers = SeasonPass.tiersOf(seasonId, data)
    if tiers == nil or #tiers == 0 then
        return 0
    end
    return tiers[#tiers].points
end

function SeasonPass.newEntry(): Entry
    return { seconds = 0, premium = false, claimed = { free = {}, premium = {} } }
end

-- Eintrag der Saison im Profil oder nil. Ändert nichts.
function SeasonPass.entryOf(profile: any, seasonId: any): Entry?
    if type(profile) ~= "table" or type(profile.seasons) ~= "table" or type(seasonId) ~= "string" then
        return nil
    end
    local entry = profile.seasons[seasonId]
    if type(entry) ~= "table" then
        return nil
    end
    return entry
end

-- Punkte aus Sekunden (ganze Zahl, durch die letzte Stufe gedeckelt).
function SeasonPass.pointsFromSeconds(seconds: any, seasonId: any, data: Data?): number
    if not isFinite(seconds) or seconds <= 0 then
        return 0
    end
    local points = math.floor(seconds / SeasonPass.secondsPerPoint(data))
    return math.min(points, SeasonPass.maxPoints(seasonId, data))
end

function SeasonPass.pointsOf(profile: any, seasonId: any, data: Data?): number
    local entry = SeasonPass.entryOf(profile, seasonId)
    if entry == nil then
        return 0
    end
    return SeasonPass.pointsFromSeconds(entry.seconds, seasonId, data)
end

-- Anzahl erreichter Stufen bei `points` Punkten (0 bis #Stufen).
function SeasonPass.tierOf(points: any, seasonId: any, data: Data?): number
    local tiers = SeasonPass.tiersOf(seasonId, data)
    if tiers == nil or not isFinite(points) then
        return 0
    end
    local reached = 0
    for index, tier in tiers do
        if points >= tier.points then
            reached = index
        else
            break
        end
    end
    return reached
end

-- Schreibt Sammelzeit in der Event-Zone gut. Gibt die neu gewonnenen Punkte zurück (0 oder mehr).
-- Kaputte Eingaben (kein number, NaN, unendlich, 0 oder negativ), eine Saison ohne Stufen und ein
-- Profil ohne `seasons` ändern nichts. Rechnet erst alles und schreibt dann in einem Zug.
function SeasonPass.addSeconds(profile: any, seasonId: any, seconds: any, data: Data?): number
    if type(profile) ~= "table" or type(profile.seasons) ~= "table" or not isFinite(seconds) or seconds <= 0 then
        return 0
    end
    local maxPoints = SeasonPass.maxPoints(seasonId, data)
    if maxPoints <= 0 then
        return 0
    end
    local perPoint = SeasonPass.secondsPerPoint(data)
    local cap = maxPoints * perPoint
    local entry = SeasonPass.entryOf(profile, seasonId)
    local before = if entry ~= nil and isFinite(entry.seconds) then math.max(entry.seconds, 0) else 0
    local after = math.min(before + seconds, cap)
    if after <= before then
        return 0
    end
    local gained = math.floor(after / perPoint) - math.floor(before / perPoint)
    -- Schreiben, ohne dass etwas dazwischen wirft.
    if entry == nil then
        entry = SeasonPass.newEntry()
        profile.seasons[seasonId :: string] = entry
    end
    (entry :: Entry).seconds = after
    return gained
end

-- Anzeigeform für den StateSync (`seasonPass`): Punkte, Obergrenze, erreichte Stufen, Stufenzahl.
function SeasonPass.state(profile: any, seasonId: any, data: Data?): { [string]: any }
    local tiers = SeasonPass.tiersOf(seasonId, data)
    local points = SeasonPass.pointsOf(profile, seasonId, data)
    local entry = SeasonPass.entryOf(profile, seasonId)
    return {
        seasonId = seasonId,
        points = points,
        maxPoints = SeasonPass.maxPoints(seasonId, data),
        tier = SeasonPass.tierOf(points, seasonId, data),
        tiers = if tiers ~= nil then #tiers else 0,
        premium = entry ~= nil and entry.premium == true,
    }
end

-- Säubert `profile.seasons` beim Laden: Textschlüssel (Saison-ID), je Eintrag `seconds` endlich ab 0
-- (sonst 0), `premium` Boolean (sonst false), `claimed.free` und `claimed.premium` nur mit Textschlüsseln
-- aus Ziffern (Stufennummer ab 1) und Wert true. Unbekannte Saison-IDs und unbekannte Felder in einem
-- Eintrag bleiben erhalten (ein neuerer Server darf nichts verlieren). Gibt (sauberes Feld, Liste der Probleme) zurück.
function SeasonPass.cleanSeasons(value: any): ({ [string]: Entry }, { string })
    local problems: { string } = {}
    local clean: { [string]: Entry } = {}
    if type(value) ~= "table" then
        return clean, { "seasons keine Tabelle, auf {} gesetzt" }
    end
    for seasonId, raw in value do
        if type(seasonId) ~= "string" or seasonId == "" or type(raw) ~= "table" then
            table.insert(problems, `seasons.{tostring(seasonId)}: Schlüssel kein Text oder Eintrag keine Tabelle, entfernt`)
            continue
        end
        local entry = SeasonPass.newEntry()
        if isFinite(raw.seconds) and raw.seconds >= 0 then
            entry.seconds = raw.seconds
        elseif raw.seconds ~= nil then
            table.insert(problems, `seasons.{seasonId}.seconds ungültig, auf 0 gesetzt`)
        end
        if raw.premium == true then
            entry.premium = true
        elseif raw.premium ~= nil and raw.premium ~= false then
            table.insert(problems, `seasons.{seasonId}.premium kein Wahrheitswert, auf false gesetzt`)
        end
        if type(raw.claimed) == "table" then
            for _, track in SeasonPass.TRACKS do
                local source = raw.claimed[track]
                if type(source) == "table" then
                    for key, flag in source do
                        if type(key) == "string" and string.match(key, "^[1-9]%d*$") ~= nil and flag == true then
                            (entry.claimed :: any)[track][key] = true
                        else
                            table.insert(problems, `seasons.{seasonId}.claimed.{track}.{tostring(key)} ungültig, entfernt`)
                        end
                    end
                end
            end
            -- Weitere Spuren (ein neuerer Server) bleiben erhalten, nach denselben Regeln gesäubert: sonst
            -- löschte ein alter Server ihre Abholmerker und der neue gäbe die Stufen erneut aus.
            for name, source in raw.claimed do
                if type(name) == "string" and (entry.claimed :: any)[name] == nil and type(source) == "table" then
                    local kept: { [string]: boolean } = {}
                    for key, flag in source do
                        if type(key) == "string" and string.match(key, "^[1-9]%d*$") ~= nil and flag == true then
                            kept[key] = true
                        end
                    end
                    (entry.claimed :: any)[name] = kept
                end
            end
        end
        -- Unbekannte Felder bleiben erhalten (ein neuerer Server, zum Beispiel 5.5b, darf nichts verlieren).
        for key, extra in raw do
            if type(key) == "string" and key ~= "seconds" and key ~= "premium" and key ~= "claimed" then
                (entry :: any)[key] = extra
            end
        end
        clean[seasonId] = entry
    end
    return clean, problems
end

-- ---------------------------------------------------------------------------------------------
-- Paket 5.5b: Abholen und Kauf
-- ---------------------------------------------------------------------------------------------

-- Hat die Saison mindestens eine Stufe?
local function hasTiers(seasonId: any, data: Data?): boolean
    local tiers = SeasonPass.tiersOf(seasonId, data)
    return tiers ~= nil and #tiers > 0
end

-- Abholfrist in Sekunden aus Economy.seasonPass.claimGraceDays. Wirft bei kaputten Daten (DataCheck
-- prüft beim Start).
local function graceSecondsOf(data: Data?): number
    local config = economyOf(data).seasonPass
    local days = if type(config) == "table" then config.claimGraceDays else nil
    if not isWholeAtLeastZero(days) then
        error("SeasonPass: Economy.seasonPass.claimGraceDays fehlt oder ist keine ganze Zahl ab 0")
    end
    return days * Seasons.SECONDS_PER_DAY
end

-- Kopie der Abholmerker einer Spur: nur Textschlüssel aus Ziffern (ab 1) mit Wert true.
local function copyFlags(value: any): { [string]: boolean }
    local result: { [string]: boolean } = {}
    if type(value) == "table" then
        for key, flag in value do
            if type(key) == "string" and string.match(key, "^[1-9]%d*$") ~= nil and flag == true then
                result[key] = true
            end
        end
    end
    return result
end

-- Saison-ID, deren `passId` das Produkt ist (DataCheck: höchstens eine), oder nil.
local function seasonIdForPass(productId: string, data: Data?): string?
    for _, season in calendarOf(data).list do
        if type(season) == "table" and season.passId == productId and type(season.id) == "string" then
            return season.id
        end
    end
    return nil
end

-- Für welche Saison gilt der Pass zur Zeit `unixNow` (Server-Zeit)? Gibt (Current, nil) zurück oder
-- (nil, Grund) mit "noSeason" (keine Saison, kaputte Zeit) oder "expired" (Abholfrist der zuletzt
-- beendeten Saison vorbei). Wirft nur bei kaputten Daten (claimGraceDays).
function SeasonPass.current(unixNow: any, data: Data?): (Current?, string?)
    if not isFinite(unixNow) or unixNow < 0 then
        return nil, "noSeason"
    end
    local calendar = calendarOf(data)
    local grace = graceSecondsOf(data)
    local position = Seasons.at(unixNow, calendar)
    local active = position.active
    if active ~= nil and hasTiers(active.id, data) then
        return { season = active, ended = false, claimSecondsLeft = position.secondsLeft + grace }, nil
    end
    local last, since = Seasons.lastEnded(unixNow, calendar)
    if last ~= nil and since ~= nil and hasTiers(last.id, data) then
        if since < grace then
            return { season = last, ended = true, claimSecondsLeft = grace - since }, nil
        end
        return nil, "expired"
    end
    return nil, "noSeason"
end

-- Darf der Server jetzt den Roblox-Kaufdialog für den Pass öffnen? Ändert nichts.
-- `{ ok = true, seasonId, passId, productId }` oder `{ ok = false, reason, detail? }` mit reason
-- "error" (kein Profil, kaputte Uhr), "noSeason", "owned" oder "notOffered" (siehe Kopf).
function SeasonPass.buyCheck(profile: any, unixNow: any, data: Data?): { [string]: any }
    if type(profile) ~= "table" then
        return fail("error", "kein Profil")
    end
    if not isFinite(unixNow) or unixNow < 0 then
        return fail("error", `ungültige Uhr {tostring(unixNow)}`)
    end
    local season = Seasons.at(unixNow, calendarOf(data)).active
    if season == nil or not hasTiers(season.id, data) then
        return fail("noSeason")
    end
    local entry = SeasonPass.entryOf(profile, season.id)
    if entry ~= nil and entry.premium == true then
        return fail("owned")
    end
    local passId = season.passId
    local product = if type(passId) == "string" then productsOf(data).byId[passId] else nil
    if type(product) ~= "table" or product.kind ~= DEVELOPER_PRODUCT or not isWholePositive(product.productId) then
        return fail("notOffered")
    end
    return { ok = true, seasonId = season.id, passId = passId, productId = product.productId }
end

-- Anzeigeform für den StateSync (`seasonPass`) oder nil (keine Saison mit Pass, Frist vorbei):
-- { seasonId, points, maxPoints, tier, tiers, premium, claimed = { free, premium }, canBuy, ended,
--   claimSecondsLeft, seasonSecondsLeft, passId }. Nur Texte, Zahlen, Wahrheitswerte und Kopien. Ändert nichts.
function SeasonPass.view(profile: any, unixNow: any, data: Data?): { [string]: any }?
    if type(profile) ~= "table" then
        return nil
    end
    local current = SeasonPass.current(unixNow, data)
    if current == nil then
        return nil
    end
    local seasonId = current.season.id
    local result = SeasonPass.state(profile, seasonId, data)
    local entry = SeasonPass.entryOf(profile, seasonId)
    local claimed: any = if entry ~= nil and type(entry.claimed) == "table" then entry.claimed else {}
    result.claimed = { free = copyFlags(claimed.free), premium = copyFlags(claimed.premium) }
    result.canBuy = not current.ended and SeasonPass.buyCheck(profile, unixNow, data).ok == true
    result.ended = current.ended
    result.claimSecondsLeft = current.claimSecondsLeft
    result.passId = current.season.passId -- Produkt der Saison (Preisanzeige im Client)
    result.seasonSecondsLeft = if current.ended then 0 else math.max(current.claimSecondsLeft - graceSecondsOf(data), 0) -- Restzeit der Saison ohne Frist
    return result
end

-- Ein Exemplar eines Pass-Items auf einer Kopie des Inventars. Gibt (neues Inventar, Item, Exemplare).
local function addPassItem(profile: any, itemId: any, data: Data?): (any, any, number)
    local item = if type(itemId) == "string" then itemsOf(data).byId[itemId] else nil
    if type(item) ~= "table" then
        error(`SeasonPass: Item "{tostring(itemId)}" steht nicht in CrateItems`)
    end
    if item.passOnly ~= true then
        error(`SeasonPass: Item "{item.id}" ist kein Pass-Item (passOnly)`)
    end
    local field = Equipment.INVENTORY_FIELDS[item.kind]
    if field == nil then
        error(`SeasonPass: unbekannte Item-Art {tostring(item.kind)} bei "{item.id}"`)
    end
    local inventory = if type(profile.inventory) == "table" then profile.inventory else {}
    local newInventory = table.clone(inventory)
    local bucket = if type(inventory[field]) == "table" then table.clone(inventory[field]) else {}
    local copies = Equipment.copiesOf(profile, item) + 1
    bucket[item.id] = copies
    newInventory[field] = bucket
    return newInventory, item, copies
end

-- Prüft und rechnet die Abholung auf Arbeitskopien. Schreibt nichts ins Profil. Gibt entweder ein
-- Fehlschlag-Ergebnis zurück oder `{ write = ..., response = ... }`.
local function prepareClaim(profile: any, tier: any, track: any, unixNow: any, ctx: ClaimContext): any
    local data = ctx.data
    if type(profile) ~= "table" then
        return fail("error", "kein Profil")
    end
    if not isFinite(unixNow) or unixNow < 0 then
        error(`SeasonPass: ungültige Uhr {tostring(unixNow)}`)
    end
    if type(track) ~= "string" or not TRACK_SET[track] then
        error(`SeasonPass: unbekannte Spur {tostring(track)}`)
    end
    local current, reason = SeasonPass.current(unixNow, data)
    if current == nil then
        return fail(reason or "noSeason")
    end
    local seasonId: string = current.season.id
    local tiers = SeasonPass.tiersOf(seasonId, data) :: { any }
    local row = if isWholePositive(tier) then tiers[tier] else nil
    if type(row) ~= "table" then
        return fail("notReached") -- eine Stufe, die es in den Daten nicht gibt, ist nie erreicht
    end
    if not isWholePositive(row.points) then
        error(`SeasonPass: Stufe {tier} von "{seasonId}" hat keine gültigen Punkte`)
    end
    if SeasonPass.pointsOf(profile, seasonId, data) < row.points then
        return fail("notReached")
    end
    local entry = SeasonPass.entryOf(profile, seasonId)
    if track == "premium" and (entry == nil or entry.premium ~= true) then
        return fail("needPass")
    end
    local key = tostring(tier)
    local claimed: any = if entry ~= nil and type(entry.claimed) == "table" then entry.claimed else nil
    local trackClaimed = if claimed ~= nil and type(claimed[track]) == "table" then claimed[track] else nil
    if trackClaimed ~= nil and trackClaimed[key] == true then
        return fail("claimed")
    end
    if type(profile.seasons) ~= "table" then
        error("SeasonPass: profile.seasons fehlt")
    end
    local reward = row[track]
    if type(reward) ~= "table" then
        error(`SeasonPass: Belohnung für Stufe {tier} ({track}) fehlt`)
    end

    local write: { [string]: any } = {}
    local response: { [string]: any } = { ok = true, seasonId = seasonId, tier = tier, track = track }
    local kind = reward.kind
    if kind == "gems" then
        local amount = reward.amount
        if not isWholePositive(amount) then
            error(`SeasonPass: ungültige Gems {tostring(amount)} für Stufe {tier} ({track})`)
        end
        local wallet = { gems = Gems.balance(profile, data) }
        local added = Gems.grant(wallet, amount, `seasonPass:{seasonId}:{track}:{key}`, data)
        if added > 0 then
            write.gems = wallet.gems
        end
        response.reward = { kind = "gems", amount = added, capped = if added < amount then true else nil }
    elseif kind == "coinBoost" or kind == "luck" then
        local seconds = reward.seconds
        if not isWholePositive(seconds) then
            error(`SeasonPass: ungültige Dauer {tostring(seconds)} für Stufe {tier} ({track})`)
        end
        local boostNow = if ctx.boostNow ~= nil then ctx.boostNow else unixNow
        local extend = if kind == "coinBoost" then Perks.extendCoinBoost else Perks.extendLuckBoost
        local boosts = extend(profile.boosts, boostNow, seconds)
        if boosts == nil then
            error(`SeasonPass: Boost für Stufe {tier} ({track}) ließ sich nicht verlängern`)
        end
        write.boosts = boosts
        response.reward = { kind = kind, seconds = seconds }
    elseif kind == "item" then
        local newInventory, item, copies = addPassItem(profile, reward.itemId, data)
        write.inventory = newInventory
        response.reward = { kind = "item", itemId = item.id, copies = copies }
    else
        -- Nie Kisten, nie Zufall: jede andere Art ist ein Datenfehler und bucht nichts.
        error(`SeasonPass: unbekannte Art {tostring(kind)} für Stufe {tier} ({track})`)
    end

    -- Merker "abgeholt" auf neuen Tabellen; unbekannte Felder von Eintrag und `claimed` bleiben.
    local newEntry: any = if entry ~= nil then table.clone(entry) else SeasonPass.newEntry()
    local newClaimed: any = if claimed ~= nil then table.clone(claimed) else {}
    for _, name in SeasonPass.TRACKS do
        newClaimed[name] = copyFlags(newClaimed[name])
    end
    newClaimed[track][key] = true
    newEntry.claimed = newClaimed
    local newSeasons = table.clone(profile.seasons)
    newSeasons[seasonId] = newEntry
    write.seasons = newSeasons
    return { write = write, response = response }
end

-- Führt `prepareClaim` in einer eigenen Koroutine aus. Wartet sie (yield), wird sie geschlossen.
local function prepareWithoutYield(profile: any, tier: any, track: any, unixNow: any, ctx: ClaimContext): (boolean, any)
    local routine = coroutine.create(prepareClaim)
    local resumed, result = coroutine.resume(routine, profile, tier, track, unixNow, ctx)
    if coroutine.status(routine) ~= "dead" then
        coroutine.close(routine)
        return false, "SeasonPass: die Abholung hat gewartet (yield) und wurde abgebrochen"
    end
    return resumed, result
end

-- Holt die Belohnung einer Stufe auf einer Spur ab (siehe Kopf). `unixNow` ist die Saison-Uhr des
-- Servers für diesen Spieler. Ergebnis: `{ ok = true, seasonId, tier, track, reward }` mit reward
-- `{ kind = "gems", amount, capped? }`, `{ kind = "coinBoost" | "luck", seconds }` oder
-- `{ kind = "item", itemId, copies }`; sonst `{ ok = false, reason, detail? }`.
function SeasonPass.claim(profile: any, tier: any, track: any, unixNow: any, ctx: ClaimContext?): any
    local context: ClaimContext = if type(ctx) == "table" then ctx else {}
    local ok, prepared = prepareWithoutYield(profile, tier, track, unixNow, context)
    if not ok then
        return fail("error", tostring(prepared))
    end
    if prepared.write == nil then
        return prepared -- Ablehnung mit Grund, nichts geschrieben
    end
    -- Ab hier nur Zuweisungen fertiger Werte, im selben Thread direkt nach der Rechnung.
    local write = prepared.write
    if write.gems ~= nil then
        profile.gems = write.gems
    end
    if write.boosts ~= nil then
        profile.boosts = write.boosts
    end
    if write.inventory ~= nil then
        profile.inventory = write.inventory
    end
    profile.seasons = write.seasons
    return prepared.response
end

-- Kauf-Handler für das Pass-Produkt einer Saison (Shop.registerProduct(passId, ...)). `clock(userId)`
-- liefert die Saison-Uhr des Spielers (im Spiel SeasonClock, ohne Spieler os.time). Rechnet auf der
-- Profil-Kopie von Purchases, wartet nie. `log` (optional) bekommt Hinweise fürs Protokoll, `ownData`
-- (Tests) ersetzt die Daten von Purchases. Regeln im Kopf der Datei.
function SeasonPass.passHandler(
    clock: (userId: number?) -> number,
    log: ((message: string) -> ())?,
    ownData: Data?
): (profile: any, product: any, data: any?, context: any?) -> Prepared?
    local function report(message: string)
        if log ~= nil then
            pcall(log, message)
        end
    end
    return function(profile: any, product: any, purchasesData: any?, context: any?): Prepared?
        local data: any = if ownData ~= nil then ownData else purchasesData
        if type(profile) ~= "table" then
            return nil
        end
        local productId = if type(product) == "table" then product.id else nil
        if type(productId) ~= "string" then
            report("Saison-Pass: Produkt ohne ID, keine Gutschrift")
            return nil
        end
        local userId = if type(context) == "table" and type(context.userId) == "number" then context.userId else nil
        local now = clock(userId)
        if not isFinite(now) or now < 0 then
            report(`Saison-Pass "{productId}": ungültige Uhr {tostring(now)}, keine Gutschrift`)
            return nil
        end
        local config = economyOf(data).seasonPass
        local duplicateGems = if type(config) == "table" then config.duplicateGems else nil
        if not isWholeAtLeastZero(duplicateGems) then
            report(`Saison-Pass "{productId}": Economy.seasonPass.duplicateGems ungültig, keine Gutschrift`)
            return nil
        end

        local current = SeasonPass.current(now, data)
        local season = if current ~= nil and current.season.passId == productId then current.season else nil
        local entry = if season ~= nil then SeasonPass.entryOf(profile, season.id) else nil
        if season ~= nil and (entry == nil or entry.premium ~= true) then
            -- Pass vergeben: gesäuberte Kopie aller Einträge (übersteht Profile.sanitize unverändert),
            -- bestehende Felder bleiben, fehlender Eintrag über newEntry.
            local seasonId: string = season.id
            local seasons = SeasonPass.cleanSeasons(profile.seasons)
            local newEntry: any = seasons[seasonId] or SeasonPass.newEntry()
            newEntry.premium = true
            seasons[seasonId] = newEntry
            return {
                changes = { seasons = seasons },
                gems = 0,
                announce = function(_current: any): (string, { [string]: any })
                    return SeasonPass.PASS_BOUGHT_KIND, { seasonId = seasonId, duplicate = false }
                end,
            }
        end

        -- Kein zweiter Pass: Ersatz-Gems (gekappt bei maxGems, über Gems.grant auf einer Hilfstabelle).
        local why = if season ~= nil
            then "Pass dieser Saison schon vorhanden"
            elseif current ~= nil then `laufende Saison "{tostring(current.season.id)}" gehört nicht zu diesem Produkt`
            else "keine Saison und keine Abholfrist"
        local scratch = { gems = Gems.balance(profile, data) }
        local added = 0
        if duplicateGems > 0 then
            added = Gems.grant(scratch, duplicateGems, `purchase:{productId}:duplicate`, data)
        end
        report(`Saison-Pass "{productId}": {why}, {added} Ersatz-Gems statt eines zweiten Passes`)
        if added < duplicateGems then
            report(`Saison-Pass "{productId}": bei maxGems gekappt, {added} statt {duplicateGems} Gems`)
        end
        local changes: { [string]: any } = {}
        if added > 0 then
            changes.gems = scratch.gems
        end
        local seasonId = if season ~= nil then season.id else seasonIdForPass(productId, data)
        return {
            changes = changes,
            gems = added,
            announce = function(_current: any): (string, { [string]: any })
                return SeasonPass.PASS_BOUGHT_KIND, { seasonId = seasonId, duplicate = true, gems = added }
            end,
        }
    end
end

-- Studio-Hilfe: liest den Wert des Attributs DebugSeasonPass. Gibt (Befehl, Zahl, Problem) zurück:
-- ("points", N), ("premium", nil), ("reset", nil), sonst (nil, nil, Text).
function SeasonPass.parseDebug(value: any): (string?, number?, string?)
    local usage = `erwartet "{SeasonPass.DEBUG_POINTS_PREFIX}500", "{SeasonPass.DEBUG_PREMIUM}" oder "{SeasonPass.DEBUG_RESET}"`
    if type(value) ~= "string" or value == "" or #value > DEBUG_MAX_LENGTH then
        return nil, nil, usage
    end
    if value == SeasonPass.DEBUG_PREMIUM or value == SeasonPass.DEBUG_RESET then
        return value, nil, nil
    end
    local digits = string.match(value, "^" .. SeasonPass.DEBUG_POINTS_PREFIX .. "(%d+)$")
    local number = if digits ~= nil then tonumber(digits) else nil
    if number == nil then
        return nil, nil, `"{value}": {usage}`
    end
    return "points", number, nil
end

-- Studio-Hilfe: neue seasons-Tabelle für den Befehl, angewandt auf die Saison des Passes (`current`:
-- die laufende, in der Abholfrist die zuletzt beendete). Ändert `profile` nicht. Gibt (neue Tabelle,
-- Saison-ID) zurück oder (nil, nil, Problem).
--   "points"   Sekunden so, dass genau N Punkte da sind (gedeckelt bei der letzten Stufe)
--   "premium"  Pass an
--   "reset"    Eintrag der Saison löschen (Punkte, Pass, Abholmerker)
function SeasonPass.withDebug(profile: any, action: string, points: number?, unixNow: number, data: Data?): ({ [string]: any }?, string?, string?)
    local current = SeasonPass.current(unixNow, data)
    if current == nil then
        return nil, nil, "keine Saison mit Pass und keine Abholfrist"
    end
    local seasonId: string = current.season.id
    local seasons: { [string]: any } = if type(profile) == "table" and type(profile.seasons) == "table" then table.clone(profile.seasons) else {}
    if action == SeasonPass.DEBUG_RESET then
        seasons[seasonId] = nil
        return seasons, seasonId, nil
    end
    local entry: any = if type(seasons[seasonId]) == "table" then table.clone(seasons[seasonId]) else SeasonPass.newEntry()
    if action == SeasonPass.DEBUG_PREMIUM then
        entry.premium = true
    elseif action == "points" then
        local wanted = if isFinite(points) then math.floor(points :: number) else 0
        local value = math.clamp(wanted, 0, SeasonPass.maxPoints(seasonId, data))
        entry.seconds = value * SeasonPass.secondsPerPoint(data)
    else
        return nil, nil, `unbekannter Befehl "{tostring(action)}"`
    end
    seasons[seasonId] = entry
    return seasons, seasonId, nil
end

return SeasonPass
