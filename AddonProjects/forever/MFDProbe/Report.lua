local addonName, ns = ...

--[[
Report: every decision about how a probe result is written down and read back. Pure: each
function takes its tables (and, where a secret has to be recognised, the test for one) as
arguments, so every case runs headless.

A run is one pass of the checks:

    run = { id, phase, trigger, at, ctx = { ... }, rows = { row, ... }, events = { ... } }
    row = { id, outcome, v, combat }

    Report.Describe(value, isSecret, isSecretTable)  -> text, secret
    Report.Outcome(row)                              -> "ok" | "secret" | "none" | "refused" | "error"
                                                        | "blocked" | "absent"
    Report.Shape(t, isSecret, isSecretTable, max)    -> { { key, text, secret }, ... }
    Report.Row(id, try, combat, isSecret)            -> row from an Env.Try result
    Report.ContextLabel(ctx)                         -> "in combat, party of 5, party instance Deadmines, leader"
    Report.Matrix(runs)                              -> { { id, out = "ok", inside = "secret" }, ... }
    Report.MatrixLines(matrix, filter)               -> lines
    Report.RunLines(run)                             -> lines
    Report.Trim(runs, keep)                          -> runs, newest `keep` only
]]

local Report = {}
ns.Report = Report

-- Longest piece of text a described value keeps, in characters. Saved variables stay
-- small and a stray chat line cannot fill the file.
Report.TEXT_LIMIT = 60

local SECRET = "<secret>"
local SECRET_TABLE = "<secret table>"

-- What a value looks like in the report. A secret is recognised before anything else is
-- done with it: comparing, indexing or joining one is what the client forbids, so the
-- only safe question to ask a value of unknown standing is the client's own test.
-- Returns the text and whether the value was secret.
function Report.Describe(value, isSecret, isSecretTable)
    if isSecret then
        local ok, secret = pcall(isSecret, value)
        if ok and secret then return SECRET, true end
    end
    local kind = type(value)
    if kind == "nil" then return "nil", false end
    if kind == "boolean" or kind == "number" then return tostring(value), false end
    if kind == "string" then
        local text = value:gsub("|", "||")
        if #text > Report.TEXT_LIMIT then text = text:sub(1, Report.TEXT_LIMIT) .. "..." end
        return '"' .. text .. '"', false
    end
    if kind == "table" then
        if isSecretTable then
            local ok, secret = pcall(isSecretTable, value)
            if ok and secret then return SECRET_TABLE, true end
        end
        local n = 0
        local ok = pcall(function() for _ in pairs(value) do n = n + 1 end end)
        return ok and string.format("table(%d)", n) or "table(?)", false
    end
    return kind, false
end

-- The one word a row comes to. `none` is a call that ran and returned nothing at all,
-- which for a getter usually means the unit was not there.
function Report.Outcome(row)
    if row.outcome then return row.outcome end
    return "ok"
end

-- A row from what Env.Try brought back. Every value the call returned is described, and
-- the row is secret when any of them was.
function Report.Row(id, try, combat, isSecret, isSecretTable)
    local row = { id = id, combat = combat and true or false }
    if not try.ok then
        if try.err == "not a function" then
            row.outcome, row.v = "absent", "not on this client"
        else
            row.outcome, row.v = "error", tostring(try.err)
        end
        return row
    end
    if (try.n or 0) == 0 then
        row.outcome, row.v = "none", ""
        return row
    end
    local parts, anySecret = {}, false
    for i = 1, try.n do
        local text, secret = Report.Describe(try.values[i], isSecret, isSecretTable)
        parts[i] = text
        if secret then anySecret = true end
    end
    row.v = table.concat(parts, ", ")
    row.outcome = anySecret and "secret" or "ok"
    return row
end

-- A line a person can read for where a run took place.
function Report.ContextLabel(ctx)
    ctx = ctx or {}
    local parts = { ctx.combat and "in combat" or "out of combat" }
    if ctx.group == "raid" then
        parts[#parts + 1] = string.format("raid of %d", ctx.size or 0)
    elseif ctx.group == "party" then
        parts[#parts + 1] = string.format("party of %d", ctx.size or 0)
    else
        parts[#parts + 1] = "solo"
    end
    if ctx.instanceType and ctx.instanceType ~= "none" then
        local where = ctx.instanceType .. " instance"
        if ctx.instanceName and ctx.instanceName ~= "" then where = where .. " " .. ctx.instanceName end
        if ctx.instanceId then where = where .. " (" .. tostring(ctx.instanceId) .. ")" end
        parts[#parts + 1] = where
    else
        parts[#parts + 1] = "open world"
    end
    if ctx.leader then
        parts[#parts + 1] = "leader"
    elseif ctx.assist then
        parts[#parts + 1] = "assist"
    elseif ctx.group then
        parts[#parts + 1] = "not leader or assist"
    end
    if ctx.chatLockdown then parts[#parts + 1] = "chat lockdown" end
    if ctx.restricted and #ctx.restricted > 0 then
        parts[#parts + 1] = "restrictions on: " .. table.concat(ctx.restricted, " ")
    end
    return table.concat(parts, ", ")
end

local function AddOutcome(set, outcome)
    for _, seen in ipairs(set) do
        if seen == outcome then return end
    end
    set[#set + 1] = outcome
    table.sort(set)
end

-- Every check id across the runs, with what it came to out of combat and in combat.
-- A check that came out two ways in the same state reads "ok/secret": that is a finding
-- in itself (it depends on the unit, or on the moment in the pull).
function Report.Matrix(runs)
    local byId, ids = {}, {}
    for _, run in ipairs(runs or {}) do
        for _, row in ipairs(run.rows or {}) do
            local entry = byId[row.id]
            if not entry then
                entry = { id = row.id, out = {}, inside = {} }
                byId[row.id] = entry
                ids[#ids + 1] = row.id
            end
            AddOutcome(row.combat and entry.inside or entry.out, Report.Outcome(row))
        end
    end
    table.sort(ids)
    local matrix = {}
    for _, id in ipairs(ids) do
        local entry = byId[id]
        matrix[#matrix + 1] = {
            id = id,
            out = #entry.out > 0 and table.concat(entry.out, "/") or "-",
            inside = #entry.inside > 0 and table.concat(entry.inside, "/") or "-",
        }
    end
    return matrix
end

-- The matrix as chat lines. `filter` keeps only ids containing that text; ids whose
-- outcome is plain ok in every state seen are folded into one count, so what is left on
-- screen is what differs.
function Report.MatrixLines(matrix, filter)
    local lines, plain = {}, 0
    for _, entry in ipairs(matrix or {}) do
        if not filter or filter == "" or entry.id:find(filter, 1, true) then
            local allOk = (entry.out == "ok" or entry.out == "-") and (entry.inside == "ok" or entry.inside == "-")
            if allOk and (not filter or filter == "") then
                plain = plain + 1
            else
                lines[#lines + 1] = string.format("  %s: out of combat %s, in combat %s", entry.id, entry.out, entry.inside)
            end
        end
    end
    if plain > 0 then
        table.insert(lines, 1, string.format("  %d checks were plain ok everywhere they ran.", plain))
    end
    return lines
end

-- One run as a few lines: where, and how its rows came out.
function Report.RunLines(run)
    local counts = {}
    for _, row in ipairs(run.rows or {}) do
        local outcome = Report.Outcome(row)
        counts[outcome] = (counts[outcome] or 0) + 1
    end
    local order = { "ok", "secret", "none", "refused", "error", "blocked", "absent" }
    local parts = {}
    for _, outcome in ipairs(order) do
        if counts[outcome] then parts[#parts + 1] = string.format("%d %s", counts[outcome], outcome) end
    end
    local lines = {
        string.format("run %s, %s (%s): %s", tostring(run.id), tostring(run.phase), tostring(run.trigger),
            Report.ContextLabel(run.ctx)),
        "  " .. (#parts > 0 and table.concat(parts, ", ") or "no rows yet"),
    }
    local seen = {}
    for name in pairs(run.events or {}) do seen[#seen + 1] = name end
    table.sort(seen)
    if #seen > 0 then
        local shown = {}
        for _, name in ipairs(seen) do
            shown[#shown + 1] = string.format("%s %d", name, run.events[name].count or 0)
        end
        lines[#lines + 1] = "  events heard: " .. table.concat(shown, ", ")
    end
    return lines
end

-- The first level of a table the client handed back, for a report on an unknown shape
-- (a damage meter session, an aura). Keys sorted, at most `maxKeys` of them; a secret
-- table gives one entry saying so. Returns { { key, text, secret }, ... }.
function Report.Shape(t, isSecret, isSecretTable, maxKeys)
    local text, secret = Report.Describe(t, isSecret, isSecretTable)
    if secret or type(t) ~= "table" then return { { key = "", text = text, secret = secret } } end
    local keys = {}
    pcall(function() for k in pairs(t) do keys[#keys + 1] = k end end)
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local fields = {}
    for i = 1, math.min(#keys, maxKeys or 12) do
        local k = keys[i]
        local v
        pcall(function() v = t[k] end)
        local vText, vSecret = Report.Describe(v, isSecret, isSecretTable)
        fields[#fields + 1] = { key = tostring(k), text = vText, secret = vSecret }
    end
    return fields
end

-- The npc id inside a creature GUID ("Creature-0-1-2-3-<npc>-<spawn>"), or nil for a
-- player, a pet with no npc, a secret or anything else.
function Report.NpcId(guid, isSecret)
    if isSecret and isSecret(guid) then return nil end
    if type(guid) ~= "string" then return nil end
    local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" and kind ~= "Pet" then return nil end
    return tonumber(npc)
end

-- Files `name` under `id` in capture[kind] when both are plain, and says whether it was
-- new. capture is { instances = {}, encounters = {}, npcs = {}, auras = {} }.
function Report.Collect(capture, kind, id, name, isSecret)
    if isSecret and (isSecret(id) or isSecret(name)) then return false end
    if type(id) ~= "number" or not capture[kind] then return false end
    local text = type(name) == "string" and name or tostring(name)
    if capture[kind][id] == text then return false end
    capture[kind][id] = text
    return true
end

-- "Defias Pillager, Defias Evoker" -> { "Defias Pillager", "Defias Evoker" }.
function Report.ParseNames(text)
    local names = {}
    for piece in tostring(text or ""):gmatch("[^,]+") do
        local name = piece:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then names[#names + 1] = name end
    end
    return names
end

-- The macro MarkedForDeath would write for a pack: target each name, mark it only if it
-- has no mark yet. Icons run down from `firstIcon`, skipping none. `exact` and `mark` are
-- the client's own words for /targetexact and /tm.
function Report.MarkMacro(names, firstIcon, exact, mark)
    exact, mark = exact or "/targetexact", mark or "/tm"
    local lines = {}
    for i, name in ipairs(names or {}) do
        local icon = (firstIcon or 8) - (i - 1)
        if icon < 1 then break end
        lines[#lines + 1] = exact .. " " .. name
        lines[#lines + 1] = mark .. " ~" .. icon
    end
    return table.concat(lines, "\n")
end

-- A macro at least `length` characters long whose last line is `tail`: everything before
-- it clears the player's own mark, which is harmless, so whether the tail ran says whether
-- a macro that long runs to its end.
function Report.LongMacro(length, tail, filler)
    filler = filler or "/tm [@player] 0\n"
    local parts = {}
    local size = #tail
    while size < length do
        parts[#parts + 1] = filler
        size = size + #filler
    end
    parts[#parts + 1] = tail
    return table.concat(parts)
end

-- Keeps the newest `keep` runs, oldest first, in a new list.
function Report.Trim(runs, keep)
    local list = runs or {}
    local first = math.max(1, #list - keep + 1)
    local kept = {}
    for i = first, #list do kept[#kept + 1] = list[i] end
    return kept
end
