--!strict
-- Testläufer: findet rekursiv alle *.spec.luau unter tests/, startet jede Datei als eigenen
-- Prozess (`lune run <datei>`), gibt eine Zusammenfassung aus und endet mit Code 1, wenn
-- eine Datei fehlschlug. Aufruf im Projektordner: `lune run tests/run`.

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local TESTS_DIR = "tests"
local SPEC_SUFFIX = ".spec.luau"

local function collect(dir: string, found: { string })
    local entries = fs.readDir(dir)
    table.sort(entries)
    for _, name in entries do
        local path = `{dir}/{name}`
        if fs.isDir(path) then
            collect(path, found)
        elseif string.sub(name, -#SPEC_SUFFIX) == SPEC_SUFFIX then
            table.insert(found, path)
        end
    end
end

local specs: { string } = {}
collect(TESTS_DIR, specs)

if #specs == 0 then
    print("Keine *.spec.luau unter tests/ gefunden")
    process.exit(1)
end

-- Lune-Programm: Umgebungsvariable LUNE_BIN oder "lune" aus dem PATH.
local luneBin = process.env.LUNE_BIN or "lune"

-- process.exec (neuere Lune-Versionen) oder process.spawn (ältere).
local proc: any = process
local runProcess: any = proc.exec or proc.spawn

local failedFiles: { string } = {}
for _, spec in specs do
    print(`=== {spec}`)
    local result = runProcess(luneBin, { "run", spec })
    stdio.write(result.stdout)
    stdio.write(result.stderr)
    if not result.ok then
        table.insert(failedFiles, spec)
    end
end

print(`\n{#specs - #failedFiles} von {#specs} Testdateien bestanden`)
if #failedFiles > 0 then
    for _, spec in failedFiles do
        print(`FEHLGESCHLAGEN: {spec}`)
    end
    process.exit(1)
end
