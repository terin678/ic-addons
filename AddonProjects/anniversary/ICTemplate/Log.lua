local addonName, ns = ...

ns.Log = ns.Log or {}
local Log = ns.Log

--[[
Two ring buffers with different budgets, merged at read time.

`log` is what the addon decided and acted on. `capture` is everything it merely
saw. Without the second half an "All" view shows only what the addon acted on,
which is not the same as everything that happened, and the difference is exactly
where "why did it do nothing" lives.
]]

local MAX_ENTRIES = 100     -- decisions kept
local MAX_CAPTURE = 500     -- raw observations kept
local WINDOW = 300          -- how far back any one view reads

Log.MAX_ENTRIES, Log.MAX_CAPTURE, Log.WINDOW = MAX_ENTRIES, MAX_CAPTURE, WINDOW

-- Shared with the UI and with chat, so a kind keeps one colour everywhere.
Log.KIND_COLOR = {
    ok = "|cff44ff44",
    warn = "|cffffcc00",
    err = "|cffff4444",
    info = "|cff888888",
}

-- Pure. Newest first, trimmed from the tail.
function Log.Push(list, entry, max)
    table.insert(list, 1, entry)
    for i = #list, (max or MAX_ENTRIES) + 1, -1 do
        table.remove(list, i)
    end
    return list
end

-- Writes into SavedVariables, so escapes come off before storing: this is what
-- gets read off disk after a /reload, and it has to be readable on its own.
function Log.Add(kind, source, text, detail, now)
    local entry = {
        at = now or ns.Now(),
        kind = kind or "info",
        source = source or "?",
        text = ns.Util.StripEscapes(text or ""),
        detail = detail and ns.Util.StripEscapes(detail) or nil,
    }
    return Log.Push(ns.db.log, entry, MAX_ENTRIES)
end

function Log.Capture(kind, source, text, now)
    ns.db.capture = ns.db.capture or {}
    return Log.Push(ns.db.capture, {
        at = now or ns.Now(),
        kind = kind or "info",
        source = source or "?",
        text = ns.Util.StripEscapes(text or ""),
    }, MAX_CAPTURE)
end

--[[
Pure. The last `window` things that happened, newest first: the decisions and the
raw capture together.

Both lists are already newest-first, so this walks them side by side and stops the
moment the window is full. No sort, and nothing read past what will be shown. An
entry in both is returned once, as the log's copy, which is the one carrying the
detail.
]]
function Log.Window(log, capture, window)
    window = window or WINDOW
    log, capture = log or {}, capture or {}
    local out, seen = {}, {}
    local i, j = 1, 1
    while #out < window do
        local a, b = log[i], capture[j]
        local e
        if a and b then
            if (a.at or 0) >= (b.at or 0) then e = a; i = i + 1 else e = b; j = j + 1 end
        elseif a then
            e = a; i = i + 1
        elseif b then
            e = b; j = j + 1
        else
            break
        end
        local key = string.format("%s|%s|%s", e.source or "", e.at or 0, e.text or "")
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = e
        end
    end
    return out
end

--[[
Pure. Returns at most n entries, and the number the filters held back so a short
list can say why it is short rather than looking like the log was lost.

opts is a table rather than positional filters on purpose. Three axes is where the
positional version stops being readable, and the third one always arrives.
    opts = { kind = "ok", source = "Pulse", since = <timestamp> }
]]
function Log.Filter(entries, n, opts)
    opts = opts or {}
    local out, hidden = {}, 0
    for _, e in ipairs(entries or {}) do
        local keep = true
        if opts.kind and opts.kind ~= "all" and e.kind ~= opts.kind then keep = false end
        if opts.source and opts.source ~= "all" and e.source ~= opts.source then keep = false end
        if opts.since and (e.at or 0) < opts.since then keep = false end
        if keep then
            if #out < n then out[#out + 1] = e end
        else
            hidden = hidden + 1
        end
    end
    return out, hidden
end

-- Newest first, straight off the stored log. For chat, where there is no toolbar.
function Log.Recent(n, kind)
    local out = {}
    for i = 1, #(ns.db.log or {}) do
        if #out >= n then break end
        local e = ns.db.log[i]
        if not kind or kind == "all" or e.kind == kind then out[#out + 1] = e end
    end
    return out
end

-- Pure. Which sources have written anything, in a fixed order, for a filter menu.
function Log.Sources(entries)
    local seen, out = {}, {}
    for _, e in ipairs(entries or {}) do
        if e.source and not seen[e.source] then
            seen[e.source] = true
            out[#out + 1] = e.source
        end
    end
    table.sort(out)
    return out
end

function Log.Describe(entry, now)
    local color = Log.KIND_COLOR[entry.kind] or "|cffffffff"
    local age = ns.Util.Freshness(entry.at, now or ns.Now())
    return string.format("%s%s|r %s |cff888888%s|r %s",
        color, entry.kind, entry.source or "?", age, entry.text or "")
end
