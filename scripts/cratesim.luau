--!strict
-- Quoten-Simulation (Paket 4.7). Öffnet jede Kiste über den echten Kaufweg `CrateOpen.open`,
-- einmal nur mit Einzelöffnungen und einmal nur mit 10 + 1 Paketen, und vergleicht mit den Sollwerten.
-- Aufruf im Projektordner:
--   lune run scripts/cratesim [Öffnungen je Kiste und Lauf] [Startwert] [Berichtsdatei]
-- Standard: 1.000.000, Startwert 470, Bericht docs/balance/crates_sim_4_7.md.
-- Endet mit Code 1, wenn eine Schwelle verletzt ist. Kern und Methode: scripts/lib/cratesim.luau.
-- Gleicher Startwert ergibt denselben Bericht; nur die Zeilen mit "Laufzeit" ändern sich.

local fs = require("@lune/fs")
local process = require("@lune/process")
local Sim = require("./lib/cratesim")
local Crates = require("../src/shared/Data/Crates")

local DEFAULT_OPENINGS = 1_000_000
local DEFAULT_SEED = 470
local DEFAULT_REPORT = "docs/balance/crates_sim_4_7.md"
local BATCHES = 100

local args = process.args
local target = tonumber(args[1]) or DEFAULT_OPENINGS
local seed = tonumber(args[2]) or DEFAULT_SEED
local reportPath = args[3] or DEFAULT_REPORT
assert(target >= 10 * BATCHES, `mindestens {10 * BATCHES} Öffnungen`)

---------------------------------------------------------------------------------------------------
-- Zahlen deutsch formatieren.

local function int(value: number): string
    local text = string.format("%d", value)
    local sign = ""
    if string.sub(text, 1, 1) == "-" then
        sign, text = "-", string.sub(text, 2)
    end
    local out = string.gsub(string.reverse(text), "(%d%d%d)", "%1.")
    out = string.reverse(out)
    if string.sub(out, 1, 1) == "." then
        out = string.sub(out, 2)
    end
    return sign .. out
end

local function num(value: number, decimals: number): string
    if value == math.huge then
        return "unendlich"
    end
    local text = string.format(`%.{decimals}f`, value)
    return (string.gsub(text, "%.", ","))
end

local function signed(value: number, decimals: number): string
    if value == math.huge or value == -math.huge then
        return if value > 0 then "+unendlich" else "-unendlich"
    end
    local text = string.format(`%+.{decimals}f`, value)
    return (string.gsub(text, "%.", ","))
end

local function pct(value: number, decimals: number): string
    return num(value * 100, decimals) .. " %"
end

local function pValue(p: number): string
    if p < 1e-4 then
        return (string.gsub(string.format("%.2e", p), "%.", ","))
    end
    return num(p, 4)
end

---------------------------------------------------------------------------------------------------
-- Lauf

local runtimes: { string } = {}
local startedAll = os.clock()
print(`Quoten-Simulation: {int(target)} Öffnungen je Kiste und Lauf, Startwert {seed}`)
local runs = Sim.runAll(target, seed, BATCHES, nil, function(stats: any, eval: any)
    local status = if #eval.failures == 0 then "ok" else "FEHLER"
    print(
        string.format(
            "  %-6s %-14s %9d Öffnungen  %6.1f s  max |z| %.2f (%s)  %s",
            stats.crateId,
            Sim.MODE_NAMES[stats.mode],
            stats.openings,
            stats.seconds,
            math.abs(eval.worstZ),
            eval.worstZName,
            status
        )
    )
    table.insert(runtimes, `- Laufzeit {stats.crateId}, {Sim.MODE_NAMES[stats.mode]}: {num(stats.seconds, 1)} s`)
end)
local totalSeconds = os.clock() - startedAll

local failures: { string } = {}
for _, run in runs do
    for _, text in run.eval.failures do
        table.insert(failures, text)
    end
end
local passed = #failures == 0
local limits = Sim.DEFAULT_THRESHOLDS

---------------------------------------------------------------------------------------------------
-- Bericht (alles außer der Laufzeit ist deterministisch)

local lines: { string } = {}
local function add(text: string?)
    table.insert(lines, text or "")
end

add("# Paket 4.7: Quoten-Simulation")
add()
add(
    "Erzeugt von `scripts/cratesim.luau` (Kern `scripts/lib/cratesim.luau`). Nicht von Hand ändern, neu erzeugen mit "
        .. `\`lune run scripts/cratesim {math.floor(target)} {math.floor(seed)}\`.`
)
add()
add("## Lauf")
add()
add(`- Öffnungen je Kiste und Lauf: Ziel {int(target)}. 10 + 1 Pakete runden auf volle Pakete auf.`)
add(`- Startwert: {math.floor(seed)}. Jeder Lauf bekommt einen eigenen Startwert daraus.`)
add(`- Batches für Pity-Kisten: {BATCHES}.`)
add(`- Ergebnis: **{if passed then "alle Schwellen eingehalten" else "Schwellen verletzt"}**.`)
add("- Laufzeit: siehe Abschnitt \"Laufzeit\" am Ende (die einzige Stelle, die sich zwischen gleichen Läufen ändert).")
add()

add("## Methode und Annahmen")
add()
add("- Jede Öffnung läuft über `CrateOpen.open` auf einem Profil aus `Profile.default`. Policy erlaubt (`restricted = false`), Saison an (`inSeason = true`).")
add(`- Gems werden vor einem Kauf auf {int(1_000_000)} aufgefüllt, wenn sie nicht reichen. Münzen (Holzkiste) stehen vor jedem Kauf auf 1 Mrd. Pity und Inventar bleiben unberührt. Die Pity läuft wie im Spiel über alle Käufe weiter, auch über Paketgrenzen.`)
add(`- Einzeln: nur \`open(..., 1)\`. Pakete: nur \`open(..., {Crates.bundle.buy})\`, je {Crates.bundle.get} Öffnungen.`)
add("- Zufall: eigener xoshiro128** mit festem Startwert, 53 Bit je Zahl. Unabhängig von `math.random`.")
add("- Sollwerte: Holz und Eisen aus der Tabelle (Quote / 10000). Gold und Event aus `CrateRoll.longRunRates` (Langzeitrate mit Pity). Item = Rate der Seltenheit / Poolgröße in dieser Kiste (Pool direkt aus `CrateItems`).")
add("- Gegenprobe: Das Skript rechnet die Pity-Kette noch einmal nur aus den Daten. Daraus kommen auch die Sollwerte für die Garantie-Raten.")
add("- Sigma ohne Pity: binomial, sqrt(n p (1 - p)). Die Öffnungen sind unabhängig.")
add(
    `- Sigma mit Pity: Batch-Means. Die Pity koppelt benachbarte Öffnungen, das Binomial-Sigma wäre nur eine Näherung. Der Lauf wird in {BATCHES} gleich lange Blöcke geteilt. Ein Block ist viel länger als ein Pity-Zyklus (höchstens 60 Öffnungen), die Block-Raten sind also fast unabhängig. Sigma = n x Streuung der Block-Raten / sqrt({BATCHES}). Die Spalte "Faktor" zeigt Batch-Sigma / Binomial-Sigma.`
)
add("- Chi-Quadrat ohne Pity: Pearson über alle Items, Freiheitsgrade = Items - 1.")
add(
    "- Chi-Quadrat mit Pity, in zwei Teilen: (a) Items innerhalb ihrer Seltenheit, exakt multinomial, weil der Item-Wurf nicht von der Pity abhängt. (b) Seltenheiten mit Hotelling-T² über die Block-Raten, geprüft mit der F-Verteilung. Das naive Pearson über alle Items steht nur zur Info da."
)
add("- Ablauf-Kontrollen je Lauf: Bezahlung je Kauf, Inventar gegen Zählung, `pityTriggered` gegen den mitgezählten Zählerstand, Pity-Zähler in Antwort und Profil.")
add()

add("## Schwellen")
add()
add("| Schwelle | Wert | Grund |")
add("| --- | --- | --- |")
add(`| Seltenheit und Item | höchstens {limits.sigma} Sigma | Bei rund 25 Werten je Lauf schlägt 4 Sigma zufällig nur selten an. |`)
add("| Quote 0 | kommt nie vor | Policy: angezeigte 0 % müssen stimmen. |")
add(
    `| Relativ | unter {num(limits.relAt1M * 100, 0)} % bei 1.000.000 Öffnungen, skaliert mit sqrt(1.000.000 / n), nur ab {num(limits.relShareMin * 100, 0)} % Anteil | Angepasst: Bei 1 % Anteil ist 1 % relativ nur 1 Sigma, bei 4,8 % nur 2,3 Sigma. Ab 10 % sind es mindestens 3,3 Sigma (Gold Episch 15,5 %: 4,3 Sigma). Darunter gilt nur die Sigma-Regel. |`
)
add(`| Chi-Quadrat und Hotelling | p über {num(limits.pMin, 3)} | Plan. |`)
add("| Pity | nie mehr als Episch - 1 Öffnungen ohne Episch+, nie mehr als Legendär - 1 ohne Legendär+ | Plan, gezählt über Paketgrenzen. |")
add(`| Garantie-Raten | höchstens {limits.batchSigma} Sigma (Batch-Means) | Zusätzlich: Die Garantie greift so oft wie die Markov-Kette sagt. |`)
add("| Ablauf-Kontrollen | alle 0 | Jede Abweichung wäre ein Fehler im Kaufweg. |")
add()

add("## Übersicht")
add()
add("| Kiste | Lauf | Öffnungen | Größte Abw. (Sigma) | Größte rel. Abw. (ab 10 %) | Chi-Quadrat p | Pity-Serien (ohne Episch+ / ohne Legendär+) | Ergebnis |")
add("| --- | --- | --- | --- | --- | --- | --- | --- |")
for _, run in runs do
    local e = run.eval
    local chiText = if e.hasPity
        then `Items {pValue(e.chi.withinP)}, Seltenheiten {pValue(e.chi.hotellingP)}`
        else pValue(e.chi.pearsonP)
    local pityText = if e.pity
        then `{e.pity.maxNoEpic} / {e.pity.maxNoLegendary} (Grenze {e.pity.limitEpic - 1} / {e.pity.limitLegendary - 1})`
        else "-"
    add(
        `| {e.crateId} | {Sim.MODE_NAMES[e.mode]} | {int(e.openings)} | {signed(e.worstZ, 2)} ({e.worstZName}) | {signed(e.worstRel * 100, 3)} % ({e.worstRelName}) | {chiText} | {pityText} | {if #e.failures == 0
            then "ok"
            else "FEHLER"} |`
    )
end
add()

for _, run in runs do
    local e = run.eval
    local crate = Crates.byId[e.crateId]
    add(`## {crate.name} ({e.crateId}), {Sim.MODE_NAMES[e.mode]}`)
    add()
    add(`{int(e.openings)} Öffnungen in {int(e.calls)} Käufen. Sigma: {if e.hasPity then "Batch-Means" else "binomial"}. Erlaubte relative Abweichung: {num(e.relLimit * 100, 3)} %.`)
    add()
    add("**Seltenheiten**")
    add()
    if e.hasPity then
        add("| Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ | Faktor |")
        add("| --- | --- | --- | --- | --- | --- | --- |")
    else
        add("| Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |")
        add("| --- | --- | --- | --- | --- | --- |")
    end
    for _, row in e.rarityRows do
        local z = if row.p > 0 then signed(row.z, 2) else "-"
        local rel = if row.p > 0 then signed(row.rel * 100, 3) .. " %" .. (if row.relChecked then " (geprüft)" else "") else "-"
        local base = `| {row.name} | {pct(row.p, 4)} | {pct(row.actual, 4)} | {int(row.count)} | {z} | {rel} |`
        if e.hasPity then
            base ..= ` {if row.p > 0 then num(row.factor, 3) else "-"} |`
        end
        add(base)
    end
    add()
    add("**Items**")
    add()
    add("| Item | Seltenheit | Soll | Ist | Anzahl | Abw. (Sigma) | Abw. relativ |")
    add("| --- | --- | --- | --- | --- | --- | --- |")
    for _, row in e.itemRows do
        add(`| {row.id} | {row.rarity} | {pct(row.p, 4)} | {pct(row.actual, 4)} | {int(row.count)} | {signed(row.z, 2)} | {signed(row.rel * 100, 3)} % |`)
    end
    add()
    add("**Chi-Quadrat**")
    add()
    if e.hasPity then
        add(`- Items innerhalb der Seltenheit: Chi² = {num(e.chi.within, 2)}, Freiheitsgrade {e.chi.withinDf}, p = {pValue(e.chi.withinP)}.`)
        add(
            `- Seltenheiten (Hotelling-T²): T² = {num(e.chi.hotelling, 2)}, F = {num(e.chi.hotellingF, 3)} bei ({e.chi.hotellingDf1}, {e.chi.hotellingDf2}) Freiheitsgraden, p = {pValue(e.chi.hotellingP)}.`
        )
        add(`- Nur Info, naives Pearson über alle Items: Chi² = {num(e.chi.pearson, 2)}, Freiheitsgrade {e.chi.pearsonDf}, p = {pValue(e.chi.pearsonP)}.`)
    else
        add(`- Pearson über alle Items: Chi² = {num(e.chi.pearson, 2)}, Freiheitsgrade {e.chi.pearsonDf}, p = {pValue(e.chi.pearsonP)}.`)
    end
    add()
    if e.pity then
        add("**Pity**")
        add()
        add(`- Längste Serie ohne Episch oder besser: {e.pity.maxNoEpic} Öffnungen (Grenze {e.pity.limitEpic - 1}).`)
        add(`- Längste Serie ohne Legendär oder besser: {e.pity.maxNoLegendary} Öffnungen (Grenze {e.pity.limitLegendary - 1}).`)
        add()
        add("| Garantie | Soll je Öffnung | Ist je Öffnung | Anzahl | Abw. (Sigma) |")
        add("| --- | --- | --- | --- | --- |")
        for _, row in e.pity.triggers do
            add(`| {row.tier} | {pct(row.p, 4)} | {pct(row.actual, 4)} | {int(row.count)} | {signed(row.z, 2)} |`)
        end
        add()
        add(`- Gegenprobe Sollwerte: größte Differenz \`longRunRates\` zur eigenen Kette {string.format("%.1e", e.crossDiff)}.`)
        add()
    end
    local controlParts = {}
    for _, control in e.controls do
        table.insert(controlParts, `{control.name} {control.value}`)
    end
    add(`Ablauf-Kontrollen: {table.concat(controlParts, "; ")}.`)
    add()
    if #e.failures > 0 then
        add("**Verletzte Schwellen**")
        add()
        for _, text in e.failures do
            add(`- {text}`)
        end
        add()
    end
end

local body = table.concat(lines, "\n")
local check = Sim.checksum(body)

local tail: { string } = {}
table.insert(tail, "## Laufzeit")
table.insert(tail, "")
table.insert(tail, `Prüfsumme des Berichts bis hier (FNV-1a): {check}. Gleicher Startwert und gleiche Öffnungszahl ergeben dieselbe Prüfsumme.`)
table.insert(tail, "")
for _, line in runtimes do
    table.insert(tail, line)
end
table.insert(tail, `- Laufzeit gesamt: {num(totalSeconds, 1)} s`)
table.insert(tail, "")

fs.writeFile(reportPath, body .. "\n" .. table.concat(tail, "\n"))

print(`Bericht: {reportPath} (Prüfsumme {check})`)
print(`Laufzeit gesamt: {string.format("%.1f", totalSeconds)} s`)
if passed then
    print("Ergebnis: alle Schwellen eingehalten")
else
    print(`Ergebnis: {#failures} Schwellen verletzt`)
    for _, text in failures do
        print(`  {text}`)
    end
    process.exit(1)
end
