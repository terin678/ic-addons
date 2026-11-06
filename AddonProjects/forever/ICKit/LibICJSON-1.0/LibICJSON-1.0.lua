--[[
LibICJSON-1.0
Layer 0 of ICKit: JSON text to and from Lua tables. Pure; calls nothing in the game client.

For anything a player copies out of the game and back in: a shared rule set, a capture
export, a settings backup. Written for people as much as for parsers, so the output is
indented and its keys are sorted, and two encodes of one table are byte for byte the same.

    local JSON = LibStub("LibICJSON-1.0")

    JSON.Encode(value, opts)        -> text, or nil and a reason
    JSON.Decode(text)               -> value, or nil and a reason

    opts.compact = true             one line, no spaces
    opts.indent = "    "            one level of indent (two spaces by default)

What it maps:
- A table whose keys are exactly 1..n is an array; every other table, the empty one
  included, is an object. Object keys may be text or numbers; a number key is written as
  text and comes back as text.
- Numbers that are whole are written without a fraction (22890, not 22890.0). Infinity and
  NaN have no JSON form and are refused, as are functions, userdata, threads and a table
  that contains itself.
- Decode turns null into nil, so a null inside an array leaves a hole at its index.
  \u escapes come back as UTF-8, surrogate pairs included. The reader is lenient where a
  hand-edited file tends to slip (a raw tab inside a string) and strict about structure.

Lifted from Anniversary MarkedForDeath's JSON.lua, which is ours, with three changes: it
returns a reason instead of writing null for what JSON cannot hold, \u escapes past 255
are decoded rather than replaced with "?", and a null inside an array keeps its index.
]]

local MAJOR, MINOR = "LibICJSON-1.0", 1
local JSON = LibStub:NewLibrary(MAJOR, MINOR)
if not JSON then return end

local type, pairs, ipairs, tostring, tonumber, error, pcall, setmetatable, getmetatable =
    type, pairs, ipairs, tostring, tonumber, error, pcall, setmetatable, getmetatable
local floor, huge = math.floor, math.huge
local byte, char, find, format, gsub, match, rep, sub =
    string.byte, string.char, string.find, string.format, string.gsub, string.match, string.rep, string.sub
local concat, sort = table.concat, table.sort

local MAX_DEPTH = 200          -- nesting levels Decode reads before it gives up
local MAX_EXACT = 2 ^ 53       -- above this a double no longer holds every whole number
local DEFAULT_INDENT = "  "    -- one level, two spaces

-- What Encode raises internally; Encode catches it and returns the reason.
local Refusal = {}
local function Refuse(reason)
    error(setmetatable({ reason = reason }, Refusal), 0)
end

--------------------------------------------------------------------------------
-- Write
--------------------------------------------------------------------------------

local ESCAPES = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b",
    ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function EscapeChar(c)
    return ESCAPES[c] or format("\\u%04x", byte(c))
end

local function EncodeString(s)
    return '"' .. gsub(s, '[%c"\\]', EscapeChar) .. '"'
end

local function EncodeNumber(n)
    if n ~= n or n == huge or n == -huge then
        Refuse("a number JSON cannot hold (" .. tostring(n) .. ")")
    end
    if n == floor(n) and n > -MAX_EXACT and n < MAX_EXACT then
        return format("%d", n)
    end
    -- The shortest form that reads back as the same number.
    local short = format("%.14g", n)
    if tonumber(short) == n then return short end
    return format("%.17g", n)
end

-- Whether t's keys are exactly 1..n with n at least 1.
local function IsArray(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    if count == 0 then return false end
    for i = 1, count do
        if t[i] == nil then return false end
    end
    return true
end

-- Numbers by value first, then text, so an export never depends on the order a table
-- was filled in.
local function KeyBefore(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == "number" end
    return a < b
end

local EncodeValue

local function EncodeTable(t, depth, style, open)
    if open[t] then Refuse("a table that contains itself") end
    open[t] = true

    local items = {}
    local isArray = IsArray(t)
    if isArray then
        for i, v in ipairs(t) do items[i] = EncodeValue(v, depth + 1, style, open) end
    else
        local keys = {}
        for k in pairs(t) do
            local kind = type(k)
            if kind ~= "string" and kind ~= "number" then
                Refuse("a key that is neither text nor a number (" .. kind .. ")")
            end
            keys[#keys + 1] = k
        end
        sort(keys, KeyBefore)
        for i, k in ipairs(keys) do
            local name = type(k) == "number" and EncodeNumber(k) or k
            items[i] = EncodeString(name) .. style.colon .. EncodeValue(t[k], depth + 1, style, open)
        end
    end
    open[t] = nil

    local first, last = "{", "}"
    if isArray then first, last = "[", "]" end
    if #items == 0 then return first .. last end
    if not style.indent then
        return first .. concat(items, ",") .. last
    end
    local pad = "\n" .. rep(style.indent, depth + 1)
    return first .. pad .. concat(items, "," .. pad) .. "\n" .. rep(style.indent, depth) .. last
end

EncodeValue = function(value, depth, style, open)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then return EncodeNumber(value) end
    if kind == "string" then return EncodeString(value) end
    if kind == "table" then return EncodeTable(value, depth, style, open) end
    Refuse("a " .. kind .. ", which JSON cannot hold")
end

-- value: a table, text, number, boolean or nil. Returns the JSON text, or nil and a
-- reason when something in it has no JSON form. Never raises.
function JSON.Encode(value, opts)
    opts = opts or {}
    local style
    if opts.compact then
        style = { colon = ":" }
    else
        style = { indent = type(opts.indent) == "string" and opts.indent or DEFAULT_INDENT, colon = ": " }
    end
    local ok, text = pcall(EncodeValue, value, 0, style, {})
    if ok then return text end
    if getmetatable(text) == Refusal then return nil, text.reason end
    return nil, "could not write that as JSON: " .. tostring(text)
end

--------------------------------------------------------------------------------
-- Read
--------------------------------------------------------------------------------

local UNESCAPES = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b",
    f = "\f", n = "\n", r = "\r", t = "\t",
}

local REPLACEMENT = "\239\191\189"  -- U+FFFD, for a surrogate that has no partner

-- A code point as UTF-8.
local function Utf8(code)
    if code < 0x80 then return char(code) end
    if code < 0x800 then
        return char(0xC0 + floor(code / 0x40), 0x80 + code % 0x40)
    end
    if code < 0x10000 then
        return char(0xE0 + floor(code / 0x1000), 0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return char(0xF0 + floor(code / 0x40000), 0x80 + floor(code / 0x1000) % 0x40,
        0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local function SkipSpace(text, pos)
    local _, stop = find(text, "^[ \t\r\n]*", pos)
    return stop + 1
end

-- Every parser takes the text and a position and returns value, next position, or nil,
-- the position it stopped at, and a reason.
local ParseValue

-- pos is at the opening quote. Runs of plain characters are copied whole, so a long
-- export reads in a few steps rather than one per character.
local function ParseString(text, pos)
    local parts, i = {}, pos + 1
    while true do
        local at = find(text, '["\\]', i)
        if not at then return nil, pos, "a string that never ends" end
        if at > i then parts[#parts + 1] = sub(text, i, at - 1) end
        if sub(text, at, at) == '"' then return concat(parts), at + 1 end

        local escape = sub(text, at + 1, at + 1)
        if escape == "u" then
            local hex = match(text, "^%x%x%x%x", at + 2)
            if not hex then return nil, at, "a \\u escape without four hex digits" end
            local code = tonumber(hex, 16)
            i = at + 6
            if code >= 0xD800 and code <= 0xDBFF then
                local low = match(text, "^\\u([dD][c-fC-F]%x%x)", i)
                if low then
                    code = 0x10000 + (code - 0xD800) * 0x400 + (tonumber(low, 16) - 0xDC00)
                    i = i + 6
                else
                    code = nil
                end
            elseif code >= 0xDC00 and code <= 0xDFFF then
                code = nil
            end
            parts[#parts + 1] = code and Utf8(code) or REPLACEMENT
        elseif UNESCAPES[escape] then
            parts[#parts + 1] = UNESCAPES[escape]
            i = at + 2
        else
            return nil, at, "an unknown escape \\" .. escape
        end
    end
end

local function ParseArray(text, pos, depth)
    local out, n = {}, 0
    pos = SkipSpace(text, pos + 1)
    if sub(text, pos, pos) == "]" then return out, pos + 1 end
    while true do
        local value, err
        value, pos, err = ParseValue(text, pos, depth)
        if err then return nil, pos, err end
        n = n + 1
        out[n] = value
        pos = SkipSpace(text, pos)
        local c = sub(text, pos, pos)
        if c == "]" then return out, pos + 1 end
        if c ~= "," then return nil, pos, "expected , or ] in a list" end
        pos = SkipSpace(text, pos + 1)
    end
end

local function ParseObject(text, pos, depth)
    local out = {}
    pos = SkipSpace(text, pos + 1)
    if sub(text, pos, pos) == "}" then return out, pos + 1 end
    while true do
        local c = sub(text, pos, pos)
        if c == "" then return nil, pos, "the text ends where a key should be" end
        if c ~= '"' then return nil, pos, "expected a quoted key" end
        local key, value, err
        key, pos, err = ParseString(text, pos)
        if err then return nil, pos, err end
        pos = SkipSpace(text, pos)
        if sub(text, pos, pos) ~= ":" then return nil, pos, "expected : after a key" end
        value, pos, err = ParseValue(text, SkipSpace(text, pos + 1), depth)
        if err then return nil, pos, err end
        out[key] = value
        pos = SkipSpace(text, pos)
        c = sub(text, pos, pos)
        if c == "}" then return out, pos + 1 end
        if c ~= "," then return nil, pos, "expected , or } in an object" end
        pos = SkipSpace(text, pos + 1)
    end
end

ParseValue = function(text, pos, depth)
    pos = SkipSpace(text, pos)
    local c = sub(text, pos, pos)
    if c == "{" or c == "[" then
        if depth >= MAX_DEPTH then return nil, pos, "nested more than " .. MAX_DEPTH .. " deep" end
        if c == "{" then return ParseObject(text, pos, depth + 1) end
        return ParseArray(text, pos, depth + 1)
    end
    if c == '"' then return ParseString(text, pos) end
    if sub(text, pos, pos + 3) == "true" then return true, pos + 4 end
    if sub(text, pos, pos + 4) == "false" then return false, pos + 5 end
    if sub(text, pos, pos + 3) == "null" then return nil, pos + 4 end

    local number = match(text, "^-?%d+%.?%d*[eE][%+%-]?%d+", pos) or match(text, "^-?%d+%.?%d*", pos)
    local value = number and tonumber(number)
    if value then return value, pos + #number end
    if c == "" then return nil, pos, "the text ends where a value should be" end
    return nil, pos, "unexpected " .. c
end

-- text: JSON. Returns the value, or nil and a reason that says where reading stopped.
-- Never raises, so pasted text that is not JSON gets a message rather than a Lua error.
function JSON.Decode(text)
    if type(text) ~= "string" or not find(text, "%S") then
        return nil, "nothing to read"
    end
    local ok, value, pos, err = pcall(ParseValue, text, 1, 0)
    if not ok then return nil, "could not read that as JSON" end
    if err then return nil, err .. " at character " .. pos end
    local rest = SkipSpace(text, pos)
    if rest <= #text then return nil, "more text after the end, at character " .. rest end
    if value == nil then return nil, "only null" end
    return value
end
