local addonName, ns = ...

ns.Util = ns.Util or {}
local Util = ns.Util

--[[
Pure helpers: no frames, no events, no reads of ns.db. Everything here can be
called from a test with made-up arguments, which is the whole reason the file
exists separately from the code that uses it.
]]

function Util.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Colour codes, hyperlinks and inline textures out. Do this BEFORE storing a
-- string, not when drawing it, so what lands in SavedVariables is readable too.
function Util.StripEscapes(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    return s
end

-- Lower case, punctuation flattened to single spaces. For comparing two things a
-- player typed, where the difference is only ever spelling.
function Util.Normalize(s)
    s = Util.StripEscapes(s):lower()
    s = s:gsub("[^%w%s]", " ")
    return Util.Trim(s:gsub("%s+", " "))
end

-- Cuts to n bytes without leaving a half-written escape or a split UTF-8
-- character behind. A truncation that cuts a |c open eats the rest of the chat
-- row it lands in, and one that cuts a multi-byte character prints a box.
function Util.Truncate(s, n)
    s = tostring(s or "")
    if #s <= n then return s end
    local cut = n
    -- Back off a continuation byte at a time until we are on a character boundary.
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 128 or b >= 192 then break end
        cut = cut - 1
    end
    local out = s:sub(1, cut)
    -- An escape opened inside what we kept has to be closed or dropped.
    local opens = select(2, out:gsub("|c%x%x%x%x%x%x%x%x", ""))
    local closes = select(2, out:gsub("|r", ""))
    if opens > closes then out = out .. "|r" end
    -- A trailing partial escape ("|c", "|cff3") is worse than no escape at all.
    out = out:gsub("|c?%x*$", "")
    return out
end

-- pairs() hands back a different order between two calls on the same table, and a
-- list drawn from it changes under the reader. Anything iterated for display or
-- for a hash goes through here first.
function Util.SortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return tostring(a) < tostring(b) end
        return type(a) < type(b)
    end)
    return keys
end

-- A stable string for a table of scalars, arrays and nested tables. Two tables
-- built key-by-key in different orders must serialize identically, or anything
-- comparing them decides they differ forever.
function Util.Serialize(v)
    local t = type(v)
    if t == "table" then
        local parts = {}
        for _, k in ipairs(Util.SortedKeys(v)) do
            parts[#parts + 1] = tostring(k) .. "=" .. Util.Serialize(v[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "number" then
        -- %s on a float is locale- and build-dependent; %.14g is neither.
        return string.format("%.14g", v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "nil" then
        return "nil"
    end
    return string.format("%q", tostring(v))
end

function Util.Plural(n, one, many)
    return n == 1 and one or (many or (one .. "s"))
end

function Util.OnOff(v)
    return v and "|cff44ff44on|r" or "|cffff4444off|r"
end

--[[
Relative age plus the colour it should be drawn in: grey for never, plain for
fresh, amber once it is past staleSec. Lib:Age answers "how long ago"; this
answers "and is that a problem", which is the question a list cell is really
asking. Returns label, color.
]]
function Util.Freshness(at, now, staleSec)
    if not at or at <= 0 then
        return "never", { r = 0.5, g = 0.5, b = 0.5 }
    end
    local age = math.max(0, (now or 0) - at)
    local label
    if age < 60 then label = string.format("%ds", age)
    elseif age < 3600 then label = string.format("%dm", math.floor(age / 60))
    elseif age < 86400 then label = string.format("%dh", math.floor(age / 3600))
    else label = string.format("%dd", math.floor(age / 86400)) end

    if staleSec and staleSec > 0 and age >= staleSec then
        return label, { r = 1, g = 0.8, b = 0.3 }
    end
    return label, { r = 0.9, g = 0.9, b = 0.9 }
end
