--!strict
-- Angebote im Shop, zuerst das Starterpaket (Paket 4.5). Rein, ohne Roblox-API, Lune-Tests in
-- tests/offers.spec.luau. Die Angebote stehen in Data/Offers (eine Zeile je Angebot).
--
-- Spielstand (seit Version 7): `profile.offers = { [offerId] = { since, bought } }`.
--   since   Unix-Zeit (Server-Uhr), zu der das Fenster startete; 0 = noch nicht gestartet
--   bought  true, sobald ein Kauf des Angebots gutgeschrieben ist (Einmalkauf)
--
-- Zustand eines Angebots (`stateOf`, Server-Uhr):
--   "bought"   gekauft (gilt immer, auch ohne gültigen Start)
--   "hidden"   noch nicht gestartet; kaputte Startzeiten (kein number, NaN, unendlich, <= 0 oder
--              mehr als FUTURE_TOLERANCE_SECONDS nach der Server-Uhr) zählen als nicht gestartet
--   "active"   von `since` bis ausschließlich `since + windowHours`; secondsLeft >= 1
--   "expired"  danach
-- Ein Start knapp in der Zukunft (Uhren verschiedener Server laufen leicht auseinander) gilt als
-- gerade gestartet: aktiv mit secondsLeft höchstens dem ganzen Fenster.
--
-- Auslöser (`onFind`): Der erste Fund mit Seltenheit mindestens `minRarityId` (Rangfolge aus
-- Data/Rarities) startet jedes noch nicht gestartete, nicht gekaufte Angebot mit
-- trigger "firstFindFromRarity". Spätere Funde verschieben nichts. Kisten-Items zählen nicht: Nur der
-- Finds-Service ruft onFind auf, die Kisten (Logic/CrateOpen) nie.
-- Alte Spielstände (`migrateStart`): Hat ein Profil schon einen Fund ab `minRarityId` in
-- `profile.finds`, aber noch keinen Start, beginnt das Fenster beim ersten Laden nach dem Update
-- (der Server ruft migrateStart beim Laden mit seiner Unix-Uhr auf, die reine Migration kennt keine
-- Uhr).
--
-- Kauf (`offerHandler`, Handler für Logic/Purchases): Das Paket gibt es nur einmal (Exploit-Review
-- 6.1). Ein Beleg bekommt es, wenn das Angebot zur Server-Uhr beim Buchen "active" ist oder seit
-- weniger als `receiptGraceMinutes` abgelaufen und nicht gekauft (`receiptGetsPackage`). Inhalt fest,
-- kein Zufall: Gems (gekappt bei maxGems, über Gems.grant), je ein Exemplar der Items im passenden
-- Inventar-Feld und der Merker `bought`. Jeder andere bezahlte Beleg (schon gekauft, nicht gestartet,
-- abgelaufen; auch über einen selbst aufgerufenen PromptProductPurchase) bekommt nur `duplicateGems`
-- Ersatz-Gems aus Data/Offers (gekappt bei maxGems), keine Items, `offers` bleibt unverändert (ein
-- noch nicht gestartetes Angebot bleibt später kaufbar). Bezahlt ist bezahlt: auch dieser Beleg wird
-- gebucht und bestätigt, nie NotProcessedYet für immer. nil (NotProcessedYet) nur bei kaputter Uhr
-- oder kaputten Daten. Der Handler rechnet auf der Profil-Kopie von Purchases, ändert sie nicht und
-- wartet nie. Meldung nach dem bestätigten Speichern: "offerBought" mit { offerId, gems, items },
-- beim Ersatz zusätzlich `duplicate = true` (items leer).
--
-- Hinweise beim Client (`nextHint`): höchstens ein Angebots-Hinweis zur Zeit, nie während eines
-- Reveals (läuft oder wartet), des Tutorials oder eines offenen Fensters, je Angebot höchstens einmal
-- pro Sitzung, mehrere nach `priority` (kleinere Zahl zuerst). Liegt in shared, damit der Client es
-- nutzen kann; der Client entscheidet damit nur die Anzeige, nie den Kauf.
--
-- Der optionale Parameter `data` ist für Tests: { Offers, Rarities, Finds, CrateItems, Economy }.

local CrateItemsData = require("../Data/CrateItems")
local EconomyData = require("../Data/Economy")
local FindsData = require("../Data/Finds")
local OffersData = require("../Data/Offers")
local RaritiesData = require("../Data/Rarities")
local Equipment = require("./Equipment")
local Gems = require("./Gems")

-- Umrechnung von windowHours und receiptGraceMinutes in Sekunden.
local SECONDS_PER_HOUR = 3600
local SECONDS_PER_MINUTE = 60
-- So weit darf ein Start nach der Server-Uhr liegen und zählt noch (als "gerade gestartet"), weil die
-- Uhren verschiedener Server leicht auseinanderlaufen. Weiter in der Zukunft ist der Wert kaputt und
-- zählt als nicht gestartet (ein Auslöser startet das Fenster dann neu).
local FUTURE_TOLERANCE_SECONDS = 300
-- Studio-Hilfe "DebugOffer": "starter" startet das Fenster jetzt, "-starter" setzt es zurück.
local DEBUG_OFF_PREFIX = "-"
local DEBUG_PATTERN = "^(%-?)([%w_]+)$"
local DEBUG_MAX_LENGTH = 64

export type State = "hidden" | "active" | "expired" | "bought"

-- Eintrag je Angebot im Profil.
export type Entry = { since: number, bought: boolean }

-- Zustand eines Angebots für die Anzeige (Snapshot-Feld `offers` je Angebots-ID).
export type View = { state: State, secondsLeft: number }

-- Lage beim Client für `nextHint`.
export type HintContext = {
    revealBusy: boolean, -- ein Reveal läuft oder wartet in der Warteschlange
    tutorialActive: boolean, -- das Tutorial läuft
    windowOpen: boolean, -- ein Fenster (Shop, Baum, Sammlung, ...) ist offen
    shownThisSession: { [string]: boolean }, -- Angebote, deren Hinweis in dieser Sitzung schon kam
    hintVisible: boolean?, -- gerade ist schon ein Angebots-Hinweis sichtbar (nie zwei zugleich)
}

-- Antwort eines Kauf-Handlers (Form wie Purchases.Prepared, ohne require auf Purchases).
type Prepared = {
    changes: { [string]: any },
    gems: number,
    announce: ((profile: any) -> (string, { [string]: any }))?,
}

local Offers = {}

-- Auslöser, die der Code kennt (DataCheck verlangt einen davon je Angebot).
Offers.TRIGGERS = { firstFindFromRarity = true } :: { [string]: boolean }
-- Meldungen an den Client (Notify-Arten).
Offers.OFFER_UNLOCKED_KIND = "offerUnlocked"
Offers.OFFER_BOUGHT_KIND = "offerBought"
-- Angebots-ID des Starterpakets in Data/Offers.
Offers.STARTER_OFFER_ID = "starter"
Offers.SECONDS_PER_HOUR = SECONDS_PER_HOUR
Offers.SECONDS_PER_MINUTE = SECONDS_PER_MINUTE
Offers.FUTURE_TOLERANCE_SECONDS = FUTURE_TOLERANCE_SECONDS

local function offersOf(data: any?): any
    return if data ~= nil and data.Offers ~= nil then data.Offers else OffersData
end

local function raritiesOf(data: any?): any
    return if data ~= nil and data.Rarities ~= nil then data.Rarities else RaritiesData
end

local function findsOf(data: any?): any
    return if data ~= nil and data.Finds ~= nil then data.Finds else FindsData
end

local function crateItemsOf(data: any?): any
    return if data ~= nil and data.CrateItems ~= nil then data.CrateItems else CrateItemsData
end

local function economyOf(data: any?): any
    return if data ~= nil and data.Economy ~= nil then data.Economy else EconomyData
end

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isWholeAtLeastZero(value: any): boolean
    return isFinite(value) and value >= 0 and value % 1 == 0
end

-- Alle Angebote (Data/Offers).
function Offers.list(data: any?): { any }
    return offersOf(data).list
end

-- Rang einer Seltenheit (Position in Data/Rarities, 1 = niedrigste) oder nil, wenn unbekannt.
function Offers.rankOf(rarityId: any, data: any?): number?
    if type(rarityId) ~= "string" then
        return nil
    end
    for index, rarity in raritiesOf(data).list do
        if rarity.id == rarityId then
            return index
        end
    end
    return nil
end

-- Länge des Fensters in Sekunden oder nil bei kaputtem windowHours (DataCheck verhindert das).
function Offers.windowSeconds(offer: any): number?
    local hours = if type(offer) == "table" then offer.windowHours else nil
    if not isFinite(hours) or hours <= 0 then
        return nil
    end
    local seconds = hours * SECONDS_PER_HOUR
    return if isFinite(seconds) then seconds else nil
end

-- Nachfrist nach dem Fensterende in Sekunden (`receiptGraceMinutes`, ganze Zahl ab 0) oder nil bei
-- kaputtem Wert (DataCheck verhindert das).
function Offers.graceSeconds(offer: any): number?
    local minutes = if type(offer) == "table" then offer.receiptGraceMinutes else nil
    if not isWholeAtLeastZero(minutes) then
        return nil
    end
    local seconds = minutes * SECONDS_PER_MINUTE
    return if isFinite(seconds) then seconds else nil
end

-- Roher Eintrag des Angebots im Profil (oder nil).
local function rawEntry(profile: any, offerId: string): any
    local offers = if type(profile) == "table" then profile.offers else nil
    local entry = if type(offers) == "table" then offers[offerId] else nil
    return if type(entry) == "table" then entry else nil
end

-- Gültiger Start (Unix-Zeit) oder nil = nicht gestartet. Siehe Kopf: kaputte Zeiten zählen als nicht
-- gestartet, ebenso ein Start weit nach der Server-Uhr.
local function validStart(entry: any, unixNow: number): number?
    local since = if type(entry) == "table" then entry.since else nil
    if not isFinite(since) or since <= 0 then
        return nil
    end
    if not isFinite(unixNow) or since > unixNow + FUTURE_TOLERANCE_SECONDS then
        return nil
    end
    return since
end

local function isBought(entry: any): boolean
    return type(entry) == "table" and entry.bought == true
end

-- Zustand des Angebots zur Unix-Zeit `unixNow` und Restsekunden (ganze Zahl, ab 1 bei "active",
-- sonst 0). Unbekannte Angebote und eine kaputte Uhr: "hidden" (außer schon gekauft).
function Offers.stateOf(profile: any, offerId: string, unixNow: number, data: any?): (State, number)
    local offer = if type(offerId) == "string" then offersOf(data).byId[offerId] else nil
    if offer == nil then
        return "hidden", 0
    end
    local entry = rawEntry(profile, offerId)
    if isBought(entry) then
        return "bought", 0
    end
    local window = Offers.windowSeconds(offer)
    local since = validStart(entry, unixNow)
    if window == nil or since == nil then
        return "hidden", 0
    end
    local left = since + window - unixNow
    if left <= 0 then
        return "expired", 0
    end
    return "active", math.ceil(math.min(left, window))
end

-- Bekommt ein Beleg, der zur Unix-Zeit `unixNow` (Server-Uhr beim Buchen) gebucht wird, das volle
-- Paket? Ja bei "active" und bei "expired", solange `unixNow` vor Fensterende plus Nachfrist
-- (`receiptGraceMinutes`) liegt. Nein bei "bought" (Einmalkauf), "hidden" (nicht gestartet, auch
-- kaputte Uhr oder unbekanntes Angebot) und nach der Nachfrist. Gibt (ja/nein, Zustand aus stateOf)
-- zurück; der Zustand ist fürs Protokoll.
function Offers.receiptGetsPackage(profile: any, offerId: string, unixNow: number, data: any?): (boolean, State)
    local state = Offers.stateOf(profile, offerId, unixNow, data)
    if state == "active" then
        return true, state
    end
    if state ~= "expired" then
        return false, state
    end
    local offer = offersOf(data).byId[offerId]
    local window = Offers.windowSeconds(offer)
    local grace = Offers.graceSeconds(offer)
    local since = validStart(rawEntry(profile, offerId), unixNow)
    if window == nil or grace == nil or since == nil then
        return false, state
    end
    return unixNow < since + window + grace, state
end

-- Zustand aller Angebote aus Data/Offers für den StateSync: { [offerId] = { state, secondsLeft } }.
function Offers.snapshot(profile: any, unixNow: number, data: any?): { [string]: View }
    local result: { [string]: View } = {}
    for _, offer in offersOf(data).list do
        local state, secondsLeft = Offers.stateOf(profile, offer.id, unixNow, data)
        result[offer.id] = { state = state, secondsLeft = secondsLeft }
    end
    return result
end

-- Bereinigte Kopie von `profile.offers` (für Profile.sanitize, onFind und den Kauf-Handler) und die
-- Liste der Reparaturen (leer = die Tabelle war schon sauber und die Kopie ist inhaltsgleich).
-- Regeln: Schlüssel sind nicht leere Texte; jeder Eintrag ist { since, bought } mit `since` endliche
-- Zahl ab 0 (sonst 0) und `bought` Boolean (sonst false), weitere Felder fallen weg. Ein Eintrag, der
-- keine Tabelle ist, wird bei bekannten Angeboten auf { since = 0, bought = false } gesetzt, bei
-- unbekannten entfernt. Unbekannte Angebots-IDs mit gültigem Eintrag bleiben erhalten (ein Angebot,
-- das ein neuerer Server ohne neue Profil-Version eingeführt hat, verliert so seinen Merker
-- "gekauft" nicht und wird nie ein zweites Mal verkauft); sie wirken hier nicht.
function Offers.cleanOffers(value: any, data: any?): ({ [string]: Entry }, { string })
    local result: { [string]: Entry } = {}
    local problems: { string } = {}
    if type(value) ~= "table" then
        if value ~= nil then
            table.insert(problems, `{type(value)} statt Tabelle, geleert`)
        end
        return result, problems
    end
    local known = offersOf(data).byId
    for key, entry in value do
        if type(key) ~= "string" or key == "" then
            table.insert(problems, `[{tostring(key)}]: Schlüssel ist kein Text, entfernt`)
            continue
        end
        if type(entry) ~= "table" then
            if known[key] ~= nil then
                result[key] = { since = 0, bought = false }
                table.insert(problems, `{key}: {type(entry)} statt Tabelle, zurückgesetzt`)
            else
                table.insert(problems, `{key}: {type(entry)} statt Tabelle, entfernt`)
            end
            continue
        end
        local since = entry.since
        local cleanSince = if isFinite(since) and since >= 0 then since else 0
        if cleanSince ~= since then
            table.insert(problems, `{key}.since: ungültig ({tostring(since)}), auf 0 gesetzt`)
        end
        local bought = entry.bought
        local cleanBought = if type(bought) == "boolean" then bought else false
        if cleanBought ~= bought then
            table.insert(problems, `{key}.bought: kein Boolean ({tostring(bought)}), auf false gesetzt`)
        end
        for field in entry do
            if field ~= "since" and field ~= "bought" then
                table.insert(problems, `{key}.{tostring(field)}: unbekanntes Feld, entfernt`)
            end
        end
        result[key] = { since = cleanSince, bought = cleanBought }
    end
    return result, problems
end

-- Darf das Angebot jetzt starten? Bekannter Auslöser, gültiges Fenster, nicht gekauft, noch kein
-- gültiger Start.
local function canStart(profile: any, offer: any, unixNow: number): boolean
    if offer.trigger ~= "firstFindFromRarity" or Offers.windowSeconds(offer) == nil then
        return false
    end
    local entry = rawEntry(profile, offer.id)
    return not isBought(entry) and validStart(entry, unixNow) == nil
end

-- Ein Fund mit Seltenheit `rarityId` wurde gebucht (nur echte Funde, keine Kisten-Items). Startet
-- jedes passende Angebot (siehe Kopf) mit since = unixNow. Gibt die neue offers-Tabelle zurück (der
-- Aufrufer weist sie ohne Warten zu) und die IDs der gestarteten Angebote, oder (nil, {}) ohne
-- Änderung. Ändert `profile` nicht.
function Offers.onFind(profile: any, rarityId: any, unixNow: number, data: any?): ({ [string]: Entry }?, { string })
    local started: { string } = {}
    if type(profile) ~= "table" or not isFinite(unixNow) or unixNow <= 0 then
        return nil, started
    end
    local rank = Offers.rankOf(rarityId, data)
    if rank == nil then
        return nil, started
    end
    local result: { [string]: Entry }? = nil
    for _, offer in offersOf(data).list do
        local minRank = Offers.rankOf(offer.minRarityId, data)
        if minRank ~= nil and rank >= minRank and canStart(profile, offer, unixNow) then
            local offers = result or (Offers.cleanOffers(profile.offers, data))
            offers[offer.id] = { since = unixNow, bought = false }
            result = offers
            table.insert(started, offer.id)
        end
    end
    return result, started
end

-- Höchste Seltenheit unter den gespeicherten Funden (nur bekannte Fundstücke mit Zähler ab 1).
function Offers.highestFoundRarity(profile: any, data: any?): string?
    local finds = if type(profile) == "table" then profile.finds else nil
    if type(finds) ~= "table" then
        return nil
    end
    local known = findsOf(data).byId
    local bestId: string? = nil
    local bestRank = 0
    for findId, count in finds do
        local find = if type(findId) == "string" then known[findId] else nil
        if find ~= nil and isFinite(count) and count >= 1 then
            local rank = Offers.rankOf(find.rarityId, data)
            if rank ~= nil and rank > bestRank then
                bestId, bestRank = find.rarityId, rank
            end
        end
    end
    return bestId
end

-- Alte Spielstände: beim Laden aufrufen (Server-Uhr). Gibt es schon einen Fund ab `minRarityId`,
-- aber noch keinen Start, beginnt das Fenster jetzt. Rückgabe wie onFind. Läuft bei jedem Laden,
-- ändert aber nur einmal (danach ist der Start gesetzt) und nie ein gekauftes Angebot.
function Offers.migrateStart(profile: any, unixNow: number, data: any?): ({ [string]: Entry }?, { string })
    local rarityId = Offers.highestFoundRarity(profile, data)
    if rarityId == nil then
        return nil, {}
    end
    return Offers.onFind(profile, rarityId, unixNow, data)
end

-- Kauf-Handler für ein Angebot (Shop.registerProduct(angebot.productId, ...)). `clock` ist die
-- Unix-Uhr des Servers (im Spiel os.time): Sie entscheidet, ob der Beleg das Paket bekommt
-- (`receiptGetsPackage`) oder nur Ersatz-Gems (`duplicateGems`, keine Items, `offers` unverändert).
-- `log` (optional) meldet Ersatz-Gems, Belege in der Nachfrist und Kappen. Gibt nil nur bei kaputter
-- Uhr, kaputten Daten oder ohne Profil zurück (dann NotProcessedYet, Roblox wiederholt): unbekanntes
-- Angebot, falsches Produkt, unbekanntes Item, ungültige gems, duplicateGems, windowHours oder
-- receiptGraceMinutes, Uhr nicht endlich oder nicht über 0.
function Offers.offerHandler(offerId: string, clock: () -> number, log: ((message: string) -> ())?): (profile: any, product: any, data: any?) -> Prepared?
    local function report(message: string)
        if log ~= nil then
            pcall(log, message)
        end
    end
    return function(profile: any, product: any, data: any?): Prepared?
        if type(profile) ~= "table" then
            return nil
        end
        local offer = offersOf(data).byId[offerId]
        if offer == nil then
            report(`Angebot "{offerId}" ist unbekannt, keine Gutschrift`)
            return nil
        end
        local productId = if type(product) == "table" then product.id else nil
        if productId ~= offer.productId then
            report(`Angebot "{offerId}" gehört zu "{tostring(offer.productId)}", nicht zu "{tostring(productId)}", keine Gutschrift`)
            return nil
        end
        if not isWholeAtLeastZero(offer.gems) or type(offer.items) ~= "table" then
            report(`Angebot "{offerId}": gems oder items ungültig, keine Gutschrift`)
            return nil
        end
        if not isWholeAtLeastZero(offer.duplicateGems) then
            report(`Angebot "{offerId}": duplicateGems ungültig ({tostring(offer.duplicateGems)}), keine Gutschrift`)
            return nil
        end
        if Offers.windowSeconds(offer) == nil or Offers.graceSeconds(offer) == nil then
            report(`Angebot "{offerId}": windowHours oder receiptGraceMinutes ungültig, keine Gutschrift`)
            return nil
        end

        -- Items prüfen (auch wenn der Beleg nur Ersatz-Gems bekommt: kaputte Daten buchen nie).
        local itemData = crateItemsOf(data)
        local items: { any } = {}
        for _, itemId in offer.items do
            local item = if type(itemId) == "string" then itemData.byId[itemId] else nil
            local field = if item ~= nil then Equipment.INVENTORY_FIELDS[item.kind] else nil
            if item == nil or field == nil then
                report(`Angebot "{offerId}": Item "{tostring(itemId)}" ist unbekannt, keine Gutschrift`)
                return nil
            end
            table.insert(items, item)
        end

        local now = clock()
        if not isFinite(now) or now <= 0 then
            report(`Angebot "{offerId}": ungültige Uhr {tostring(now)}, keine Gutschrift`)
            return nil
        end
        local maxGems = economyOf(data).purchases.maxGems
        local resultOfferId: string = offer.id
        local getsPackage, state = Offers.receiptGetsPackage(profile, offer.id, now, data)

        if not getsPackage then
            -- Kein Paket (schon gekauft, nicht gestartet, abgelaufen): nur Ersatz-Gems über Gems.grant
            -- (gekappt bei maxGems) auf einer Hilfstabelle, keine Items, offers bleibt unverändert.
            local duplicateGems: number = offer.duplicateGems
            local scratch = { gems = Gems.balance(profile, data) }
            local replaced = 0
            if duplicateGems > 0 then
                replaced = Gems.grant(scratch, duplicateGems, `purchase:{offer.productId}:duplicate`, data)
            end
            report(`Angebot "{offerId}": Beleg im Zustand "{state}" (schon gekauft oder Fenster nicht offen), {replaced} Ersatz-Gems statt des Pakets, keine Items`)
            if replaced < duplicateGems then
                report(`Angebot "{offerId}": bei maxGems ({maxGems}) gekappt, {replaced} statt {duplicateGems} Ersatz-Gems gutgeschrieben`)
            end
            local replacement: { [string]: any } = {}
            if replaced > 0 then
                replacement.gems = scratch.gems
            end
            return {
                changes = replacement,
                gems = replaced,
                announce = function(_current: any): (string, { [string]: any })
                    return Offers.OFFER_BOUGHT_KIND, { offerId = resultOfferId, gems = replaced, items = {}, duplicate = true }
                end,
            }
        end

        -- Paket. Items: je ein Exemplar im Feld der Art (Equipment.INVENTORY_FIELDS), neue Tabellen.
        local inventory: { [string]: any } = if type(profile.inventory) == "table" then table.clone(profile.inventory) else {}
        local given: { string } = {}
        for _, item in items do
            local field = Equipment.INVENTORY_FIELDS[item.kind]
            local bucket: { [string]: any } = if type(inventory[field]) == "table" then table.clone(inventory[field]) else {}
            local current = bucket[item.id]
            local count = if isFinite(current) and current >= 0 then math.floor(current) else 0
            bucket[item.id] = count + 1
            inventory[field] = bucket
            table.insert(given, item.id)
        end

        -- Gems über Gems.grant (ganze Zahl, gekappt bei maxGems) auf einer Hilfstabelle, damit die
        -- Profil-Kopie unverändert bleibt.
        local changes: { [string]: any } = { inventory = inventory }
        local added = 0
        if offer.gems > 0 then
            local scratch = { gems = Gems.balance(profile, data) }
            added = Gems.grant(scratch, offer.gems, `purchase:{offer.productId}`, data)
            changes.gems = scratch.gems
            if added < offer.gems then
                report(`Angebot "{offerId}": bei maxGems ({maxGems}) gekappt, {added} statt {offer.gems} Gems gutgeschrieben`)
            end
        end

        -- Merker "gekauft" (Einmalkauf). Ein Beleg in der Nachfrist bekommt das Paket, das Protokoll
        -- nennt es.
        if state ~= "active" then
            report(`Angebot "{offerId}": Beleg im Zustand "{state}" in der Nachfrist nach dem Fensterende, Paket gutgeschrieben`)
        end
        local offers = Offers.cleanOffers(profile.offers, data)
        local before = offers[offer.id]
        offers[offer.id] = { since = if before ~= nil then before.since else 0, bought = true }
        changes.offers = offers

        return {
            changes = changes,
            gems = added,
            announce = function(_current: any): (string, { [string]: any })
                return Offers.OFFER_BOUGHT_KIND, { offerId = resultOfferId, gems = added, items = table.clone(given) }
            end,
        }
    end
end

-- Kauf-Handler des Starterpakets (Kurzform von offerHandler).
function Offers.starterHandler(clock: () -> number, log: ((message: string) -> ())?): (profile: any, product: any, data: any?) -> Prepared?
    return Offers.offerHandler(Offers.STARTER_OFFER_ID, clock, log)
end

-- Welches Angebot soll der Client jetzt als Hinweis zeigen? `offersState` ist das Snapshot-Feld
-- `offers` ({ [offerId] = { state, secondsLeft } }, secondsLeft darf der Client herunterzählen).
-- Gibt eine Angebots-ID oder nil zurück. Regeln: nur Angebote mit state "active" und secondsLeft > 0;
-- nichts, solange ein Reveal läuft oder wartet, das Tutorial läuft, ein Fenster offen ist oder schon
-- ein Hinweis sichtbar ist (die drei Pflichtfelder müssen genau false sein, sonst wartet der
-- Hinweis); je Angebot höchstens einmal pro Sitzung (`shownThisSession`, der Client trägt das
-- gezeigte Angebot sofort ein); bei mehreren das mit der kleinsten `priority`, bei Gleichstand die
-- kleinere ID. Unbekannte Angebote zählen nicht.
function Offers.nextHint(offersState: any, ctx: HintContext, data: any?): string?
    if type(ctx) ~= "table" then
        return nil
    end
    if ctx.revealBusy ~= false or ctx.tutorialActive ~= false or ctx.windowOpen ~= false or ctx.hintVisible == true then
        return nil
    end
    if type(offersState) ~= "table" then
        return nil
    end
    local shown = if type(ctx.shownThisSession) == "table" then ctx.shownThisSession else {}
    local bestId: string? = nil
    local bestPriority = math.huge
    for _, offer in offersOf(data).list do
        local view = offersState[offer.id]
        local active = type(view) == "table"
            and view.state == "active"
            and type(view.secondsLeft) == "number"
            and view.secondsLeft > 0
        if active and shown[offer.id] ~= true then
            local priority = if isFinite(offer.priority) then offer.priority else math.huge
            if bestId == nil or priority < bestPriority or (priority == bestPriority and offer.id < (bestId :: string)) then
                bestId = offer.id
                bestPriority = priority
            end
        end
    end
    return bestId
end

-- Studio-Hilfe: liest den Wert des Attributs "DebugOffer". "starter" = Fenster jetzt starten,
-- "-starter" = zurücksetzen (nicht gestartet, nicht gekauft). Gibt (offerId, starten) zurück oder
-- (nil, false, Grund).
function Offers.parseDebug(value: any, data: any?): (string?, boolean, string?)
    if type(value) ~= "string" or value == "" or #value > DEBUG_MAX_LENGTH then
        return nil, false, `erwartet Text wie "starter" oder "{DEBUG_OFF_PREFIX}starter"`
    end
    local prefix, offerId = string.match(value, DEBUG_PATTERN)
    if offerId == nil then
        return nil, false, `"{value}" hat nicht die Form "starter" oder "{DEBUG_OFF_PREFIX}starter"`
    end
    if offersOf(data).byId[offerId] == nil then
        return nil, false, `unbekanntes Angebot "{offerId}"`
    end
    return offerId, prefix ~= DEBUG_OFF_PREFIX, nil
end

-- Studio-Hilfe: neue offers-Tabelle, in der das Angebot jetzt startet (since = unixNow, nicht gekauft)
-- oder zurückgesetzt ist (since = 0, nicht gekauft). Ändert `profile` nicht.
function Offers.withDebug(profile: any, offerId: string, start: boolean, unixNow: number, data: any?): { [string]: Entry }
    local offers = Offers.cleanOffers(if type(profile) == "table" then profile.offers else nil, data)
    local since = if start and isFinite(unixNow) and unixNow > 0 then unixNow else 0
    offers[offerId] = { since = since, bought = false }
    return offers
end

return Offers
