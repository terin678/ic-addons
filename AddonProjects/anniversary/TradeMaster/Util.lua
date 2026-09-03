local addonName, ns = ...

ns.Util = ns.Util or {}
local Util = ns.Util

function Util.Trim(s)
    if not s then return "" end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function Util.StripEscapes(s)
    if not s then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    return s
end

function Util.Normalize(s)
    if not s then return "" end
    s = Util.StripEscapes(s)
    s = s:lower()
    s = s:gsub("[^%w%s]", " ")
    s = s:gsub("%s+", " ")
    return Util.Trim(s)
end

function Util.ExtractItemIDs(raw)
    local ids = {}
    if not raw then return ids end
    for id in raw:gmatch("|Hitem:(%d+)") do
        ids[#ids + 1] = tonumber(id)
    end
    return ids
end

-- Full item links, not just ids, so we can quote back exactly what someone
-- linked at us.
function Util.ExtractItemLinks(raw)
    local out = {}
    if not raw then return out end
    for link in raw:gmatch("|c%x+|Hitem:.-|h.-|h|r") do
        local id = tonumber(link:match("|Hitem:(%d+)"))
        if id then out[#out + 1] = { id = id, link = link } end
    end
    return out
end

-- "Do you have veiled pyrestone cut?" deserves an answer. "why are so many
-- cuts cheaper than [Crimson Spinel]" does not: it is someone thinking out
-- loud, and replying to it is talking over the user. A question mark plus an
-- availability phrase separates the two.
function Util.IsAvailabilityQuestion(raw, norm, phrases)
    if not raw or not raw:find("?", 1, true) then return false end

    -- A shift-clicked gem link with a trailing "?" and no typed words at all
    -- ("[Shifting Shadowsong Amethyst]?") is as direct a question as it gets.
    -- Requiring a phrase from the list would miss it entirely, which is
    -- exactly what happened: the link itself IS the question.
    if raw:find("|Hitem:", 1, true) and raw:match("%?%s*$") then
        return true
    end

    for _, p in ipairs(phrases or {}) do
        if Util.HasPhrase(norm, p) then return true end
    end
    return false
end

function Util.HasPhrase(norm, phrase)
    if not norm or not phrase or phrase == "" then return false end
    return (" " .. norm .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

-- Pure. Reads what a person types for an amount of money: "12g", "12g50s",
-- "1g 2s 3c", "50s". A bare number is gold, which is how people say prices out
-- loud. Returns copper, or nil when there is no number in there at all.
function Util.ParseMoney(text)
    if type(text) ~= "string" then return nil end
    text = text:lower():gsub("%s+", "")
    if text == "" then return nil end

    local copper, found = 0, false
    for amount, unit in text:gmatch("(%d+%.?%d*)([gsc])") do
        local n = tonumber(amount)
        if n then
            found = true
            if unit == "g" then copper = copper + n * 10000
            elseif unit == "s" then copper = copper + n * 100
            else copper = copper + n end
        end
    end
    if found then return math.floor(copper + 0.5) end

    local bare = tonumber(text)
    if bare then return math.floor(bare * 10000 + 0.5) end
    return nil
end

-- Pure. The inverse of ParseMoney, for putting an amount back into a box someone
-- is about to edit. Coin textures are for reading, not for typing into.
function Util.MoneyText(copper)
    copper = math.max(0, math.floor(copper or 0))
    if copper == 0 then return "" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out = ""
    if g > 0 then out = out .. g .. "g" end
    if s > 0 then out = out .. s .. "s" end
    if c > 0 then out = out .. c .. "c" end
    return out
end

function Util.EscapePattern(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

function Util.Tokenize(norm)
    local t = {}
    if not norm then return t end
    for w in norm:gmatch("%S+") do
        t[#t + 1] = w
    end
    return t
end
