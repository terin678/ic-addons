--[[
LibICUtil-1.0
Layer 0 of ICKit: pure helpers. Nothing here calls the game client, so every function has a
headless case and behaves the same on any client the kit is ever loaded on.

    local Util = LibStub("LibICUtil-1.0")

    Util.Trim(s)                    whitespace off both ends
    Util.StripEscapes(s)            colour codes, hyperlinks and inline textures out
    Util.Truncate(s, n)             cut to n bytes, never mid-character or mid-escape
    Util.Clean(s, maxLen)           the choke point for text a person typed or sent
    Util.Plural(n, one, many)       "line" or "lines"
    Util.SortedKeys(t)              a table's keys in a stable order
    Util.DeepCopy(t)                a copy that shares nothing with the original
    Util.Clamp(n, lo, hi)           n held inside lo..hi
    Util.Move(list, from, to)       reorder one element of a list; returns whether it moved

Trim through DeepCopy are lifted from LibICCore-1.0 (the Anniversary set), where they have
run for months; Clamp and Move are new here.
]]

local MAJOR, MINOR = "LibICUtil-1.0", 1
local Util = LibStub:NewLibrary(MAJOR, MINOR)
if not Util then return end

function Util.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Colour codes, hyperlinks and inline textures out. Do this BEFORE storing a string, not
-- when drawing it, so what lands in SavedVariables is readable too.
function Util.StripEscapes(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    return s
end

-- Cuts to n bytes without leaving a half-written escape or a split UTF-8 character
-- behind. A truncation that cuts a |c open eats the rest of the chat row it lands in, and
-- one that cuts a multi-byte character prints a box.
function Util.Truncate(s, n)
    s = tostring(s or "")
    if #s <= n then return s end
    local cut = n
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 128 or b >= 192 then break end
        cut = cut - 1
    end
    local out = s:sub(1, cut)
    local opens = select(2, out:gsub("|c%x%x%x%x%x%x%x%x", ""))
    local closes = select(2, out:gsub("|r", ""))
    if opens > closes then out = out .. "|r" end
    out = out:gsub("|c?%x*$", "")
    return out
end

-- The one choke point every string a person typed, or another player sent, passes through
-- before it is stored or drawn: escapes off, any surviving pipe gone, control characters
-- and runs of whitespace flattened, cut to a length this addon chose.
function Util.Clean(s, maxLen)
    s = Util.StripEscapes(s or "")
    s = s:gsub("|", "")
    s = s:gsub("[%c]", " ")
    return Util.Truncate(Util.Trim(s:gsub("%s+", " ")), maxLen or 255)
end

function Util.Plural(n, one, many)
    return n == 1 and one or (many or (one .. "s"))
end

-- pairs() hands back a different order between two calls on the same table, and a list
-- drawn from it changes under the reader. Anything iterated for display goes through here.
function Util.SortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            if type(a) == "number" then return a < b end
            return tostring(a) < tostring(b)
        end
        return type(a) < type(b)
    end)
    return keys
end

function Util.DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Util.DeepCopy(v) end
    return out
end

-- n held inside lo..hi. Something that is not a number comes back as lo, so a saved value
-- that went missing lands on the safe end rather than raising.
function Util.Clamp(n, lo, hi)
    n = tonumber(n)
    if not n or n < lo then return lo end
    if n > hi then return hi end
    return n
end

-- Moves list[from] to position `to`, shifting what lies between. Returns whether anything
-- moved: an index off either end, or a move to where it already is, changes nothing.
function Util.Move(list, from, to)
    local n = #list
    if type(from) ~= "number" or type(to) ~= "number" then return false end
    if from < 1 or from > n or to < 1 or to > n or from == to then return false end
    table.insert(list, to, table.remove(list, from))
    return true
end
