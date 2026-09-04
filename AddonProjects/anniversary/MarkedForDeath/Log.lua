-- What the addon did, kept where it can be read after the fact.
--
-- Same manner as CutMaster's Log: a capped ring buffer, newest first, written
-- to SavedVariables so it survives a reload and can be read off disk. That last
-- part is the point. "It marked the wrong thing" an hour ago is unanswerable
-- from memory and obvious from a log, and this addon has already cost a day of
-- guessing at a bug that a line in a file would have named immediately.
--
-- Entries store text, not ids. A log you have to decode against the addon's own
-- tables is not a log, it is a puzzle.
local MFD = _G.MarkedForDeath or {}

MFD.Log = MFD.Log or {}
local Log = MFD.Log

-- A raid night of marking is a few hundred lines. Enough to cover last night,
-- not enough to bloat the saved variables into something that slows a reload.
Log.MAX_ENTRIES = 400

-- The kinds, so a reader can filter and a writer cannot invent a new one by
-- typo. Ordered roughly by how often they appear.
Log.KINDS = {
    MARK = "mark",          -- the assignment map changed
    YIELD = "yield",        -- backed off a mob something else keeps changing
    MANUAL = "manual",      -- a person's mark was taken as theirs
    SAY = "say",            -- something was sent to the group
    HELD = "held",          -- something was not sent, and why
    DEATH = "death",        -- a tank or healer death was called
    CC = "cc",              -- late crowd control alert
    LEAD = "lead",          -- who is marking changed
    LOGGING = "logging",    -- combat logging turned on or off
    ERROR = "error",        -- something threw
}

-- Adds an entry, newest first, and trims. Mutates and returns log. Pure.
function Log.Push(log, entry, maxEntries)
    table.insert(log, 1, entry)
    for index = #log, maxEntries + 1, -1 do
        table.remove(log, index)
    end
    return log
end

-- Builds one entry. at is epoch seconds, so the file makes sense on its own
-- rather than only relative to a session that has since ended. when is the same
-- moment already formatted, for the same reason: a reader should not have to
-- convert timestamps to know when something happened. Pure.
function Log.NewEntry(kind, text, at, zone)
    return {
        at = at,
        when = date("%m/%d %H:%M:%S", at),
        kind = kind,
        zone = zone,
        text = text,
    }
end

local KIND_COLOR = {
    mark = "|cff88bbff",
    yield = "|cffffcc66",
    manual = "|cff88ff88",
    say = "|cffffffff",
    held = "|cff999999",
    death = "|cffff4444",
    cc = "|cffffcc66",
    lead = "|cff88bbff",
    logging = "|cff88ff88",
    error = "|cffff4444",
}

-- One line for chat. Pure.
function Log.Describe(entry)
    local color = KIND_COLOR[entry.kind] or "|cffffffff"
    return string.format("|cff666666%s|r %s%s|r %s",
        entry.when or "?", color, entry.kind or "?", entry.text or "")
end

-- The most recent count entries, newest first. Pure.
function Log.Recent(log, count)
    local out = {}
    for index = 1, math.min(count, #log) do
        out[index] = log[index]
    end
    return out
end

-- Entries of one kind, newest first. For "show me every time it backed off".
-- Pure.
function Log.OfKind(log, kind, count)
    local out = {}
    for _, entry in ipairs(log) do
        if entry.kind == kind then
            out[#out + 1] = entry
            if #out >= count then
                break
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------- client --

-- Writes one line. Never throws: a logger that can take the addon down with it
-- is worse than no logger, and this is called from inside event handlers.
function Log.Add(kind, text)
    if not MFD.db or not MFD.db.settings.isLogEnabled then
        return
    end

    local ok = pcall(function()
        MFD.db.log = MFD.db.log or {}
        Log.Push(MFD.db.log, Log.NewEntry(kind, text, time(),
            MFD.Rules and MFD.Rules.currentInstanceKey or nil), Log.MAX_ENTRIES)
    end)

    return ok
end

-- Prints the tail to chat.
function Log.Print(count, kind)
    local log = MFD.db.log or {}
    local entries = kind and Log.OfKind(log, kind, count) or Log.Recent(log, count)

    if #entries == 0 then
        MFD.Print("nothing logged" .. (kind and (" for " .. kind) or ""))
        return
    end

    -- Oldest of the slice first, so chat reads downward the way time runs.
    for index = #entries, 1, -1 do
        MFD.Print(Log.Describe(entries[index]))
    end
    MFD.Print(string.format("|cff666666%d of %d entries. The full log is in "
        .. "SavedVariables\\MarkedForDeath.lua after a reload or logout.|r", #entries, #log))
end

_G.MarkedForDeath = MFD
