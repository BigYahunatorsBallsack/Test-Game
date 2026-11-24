--!strict
local Search = {}

type Node = { id: string, name: string, kind: string }
type Page = { id: string, name: string, nodes: { Node } }
type Entry = { id: string, name: string, context: string, order: number }

local aliases = {
    bucket_chain = "Förderband",
    vacuum_robot = "Staubsauger",
    mega_machine = "Großmaschine",
}

local function normalize(value: string): string
    value = string.lower(value)
    value = value:gsub("Ä", "ae"):gsub("ä", "ae")
    value = value:gsub("Ö", "oe"):gsub("ö", "oe")
    value = value:gsub("Ü", "ue"):gsub("ü", "ue")
    value = value:gsub("ẞ", "ss"):gsub("ß", "ss")
    value = value:gsub("[^a-z0-9]+", " "):gsub("^ ", ""):gsub(" $", "")
    return value
end

function Search.build(pages: { Page }, kinds: { [string]: string }): { Entry }
    local index: { Entry } = {}
    for _, page in pages do
        local area = page.name .. " " .. (aliases[page.id] or "")
        for _, node in page.nodes do
            local label = kinds[node.kind] or ""
            table.insert(index, {
                id = node.id,
                name = normalize(node.name),
                context = normalize(area .. " " .. label),
                order = #index + 1,
            })
        end
    end
    return index
end

function Search.find(index: { Entry }, query: string, limit: number): ({ string }, number)
    local normalized = normalize(query)
    if normalized == "" then
        return {}, 0
    end
    local words = string.split(normalized, " ")
    local matches: { { entry: Entry, score: number } } = {}
    for _, entry in index do
        local score = 0
        for _, word in words do
            if string.find(entry.name, word, 1, true) then
                score += 2
            elseif string.find(entry.context, word, 1, true) then
                score += 1
            else
                score = 0
                break
            end
        end
        if score > 0 then
            if entry.name == normalized then
                score += 300
            elseif string.sub(entry.name, 1, #normalized) == normalized then
                score += 200
            elseif string.find(entry.name, normalized, 1, true) then
                score += 100
            end
            table.insert(matches, { entry = entry, score = score })
        end
    end
    table.sort(matches, function(a, b)
        return if a.score == b.score then a.entry.order < b.entry.order else a.score > b.score
    end)
    local result: { string } = {}
    for i = 1, math.min(#matches, limit) do
        result[i] = matches[i].entry.id
    end
    return result, #matches
end

return Search
