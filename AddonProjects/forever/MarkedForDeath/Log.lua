local addonName, ns = ...

--[[
Log: what the addon did, kept in the saved table so "it marked the wrong thing" an hour
ago can be read off disk. A ring of LOG_SIZE entries in db.log = { head, entries }; the
head is where the newest entry sits, so a write never shifts the table.

Owned by lane A (model).

Pure half (takes the log table, never touches the saved one on its own):
    Log.Push(log, entry, size)       write one entry, overwriting the oldest when full
    Log.Recent(log, count, kind)     newest first, optionally one kind only
    Log.Age(seconds)                 "12s", "5m", "3h", "2d"
    Log.Describe(entry, now)         one chat line

Runtime half (the saved table and the clock, never at file scope):
    Log.Write(kind, text, where)     appends to ns.db.log; never raises
    /mfd log [count] [kind]          prints the newest entries
Entries hold text, not ids: a log that has to be decoded is a puzzle.
]]

ns.Log = ns.Log or {}
local Log = ns.Log

Log.SIZE = 500    -- entries; a raid night of plans and calls with room to spare

Log.KINDS = {
    plan = "the allocation or the macro changed",
    held = "something was not sent or not written, and why",
    say = "something was sent to the group",
    death = "a tank or healer death was called",
    lead = "who is Raid Lead changed",
    logging = "combat logging turned on or off",
    conflict = "another addon doing one of the same jobs",
    capture = "capture mode",
    error = "something threw",
}

local KIND_COLOR = {
    plan = "|cff88bbff", held = "|cff999999", say = "|cffffffff", death = "|cffff4444",
    lead = "|cff88bbff", logging = "|cff88ff88", conflict = "|cffffcc00", capture = "|cffffcc00",
    error = "|cffff4444",
}

-- log: { head, entries }. entry: { at, kind, text, where }. Mutates and returns log.
function Log.Push(log, entry, size)
    size = size or Log.SIZE
    if type(log.entries) ~= "table" then log.entries = {} end
    local head = tonumber(log.head) or 0
    if head < 0 or head >= size then head = 0 end
    head = head + 1
    log.entries[head] = entry
    log.head = head
    -- A smaller size than the table was written with: drop what lies past it.
    for i = #log.entries, size + 1, -1 do log.entries[i] = nil end
    return log
end

-- Returns up to `count` entries, newest first, of one kind when `kind` is given.
function Log.Recent(log, count, kind)
    local out = {}
    local entries = type(log) == "table" and log.entries or {}
    local n = #entries
    local head = tonumber(log and log.head) or 0
    if n == 0 or head < 1 or head > n then return out end
    count = count or n
    for step = 0, n - 1 do
        local entry = entries[(head - 1 - step) % n + 1]
        if entry and (not kind or entry.kind == kind) then
            out[#out + 1] = entry
            if #out >= count then break end
        end
    end
    return out
end

function Log.Age(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

function Log.Describe(entry, now)
    local age = (now and entry.at) and Log.Age(now - entry.at) or "?"
    local where = entry.where and (" |cff666666" .. entry.where .. "|r") or ""
    return string.format("|cff666666%s|r %s%s|r%s %s", age, KIND_COLOR[entry.kind] or "|cffffffff",
        tostring(entry.kind), where, tostring(entry.text or ""))
end

--------------------------------------------------------------------------------
-- Runtime
--------------------------------------------------------------------------------

-- Appends one entry to the saved log. Called from event handlers, so it never raises.
-- Returns whether it wrote.
function Log.Write(kind, text, where)
    if not ns.db then return false end
    local ok = pcall(function()
        if type(ns.db.log) ~= "table" then ns.db.log = { head = 0, entries = {} } end
        Log.Push(ns.db.log, { at = time(), kind = kind, text = tostring(text), where = where }, Log.SIZE)
    end)
    return ok
end

-- "/mfd log", "/mfd log 40", "/mfd log death", "/mfd log 5 plan".
function Log.ParseArgs(rest)
    local count, kind = 15, nil
    for word in tostring(rest or ""):gmatch("%S+") do
        local n = tonumber(word)
        if n then count = math.max(1, math.min(Log.SIZE, math.floor(n))) else kind = string.lower(word) end
    end
    return count, kind
end

ns.AddCommand("log", "the newest log lines, of one kind if named", function(rest)
    if not ns.db then
        ns.Print("the saved settings are not in hand yet.")
        return
    end
    local count, kind = Log.ParseArgs(rest)
    if kind and not Log.KINDS[kind] then
        local kinds = {}
        for k in pairs(Log.KINDS) do kinds[#kinds + 1] = k end
        table.sort(kinds)
        ns.Printf("no log kind '%s'. Kinds: %s.", kind, table.concat(kinds, ", "))
        return
    end
    local entries = Log.Recent(ns.db.log, count, kind)
    if #entries == 0 then
        ns.Print("nothing logged" .. (kind and (" for " .. kind) or "") .. ".")
        return
    end
    local now = time()
    for i = #entries, 1, -1 do ns.Print(Log.Describe(entries[i], now)) end
end, "log [count] [kind]")
