-- A small JSON reader and writer, so rule sets can be shared as a file anyone
-- can read, edit in a text editor and post on the internet.
--
-- Hand-rolled because the addon folder carries no dependency it does not need,
-- and because only a restricted subset is required: objects, arrays, strings,
-- numbers and booleans. This file must never call a WoW API.
local MFD = _G.MarkedForDeath or {}

MFD.JSON = MFD.JSON or {}
local JSON = MFD.JSON

local ESCAPES = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b",
    ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encodeString(value)
    local out = value:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", string.byte(c))
    end)
    return '"' .. out .. '"'
end

-- Returns true when t is a proper 1..n array, which decides whether it is
-- written as [] or {}.
local function isArray(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    for i = 1, count do
        if t[i] == nil then
            return false
        end
    end
    return count > 0
end

local encodeValue

-- indent is the current depth; the output is pretty printed because a shared
-- file is read and edited by people, not just parsed.
local function encodeTable(t, indent)
    local pad = string.rep("  ", indent + 1)
    local closePad = string.rep("  ", indent)

    if isArray(t) then
        local parts = {}
        for _, v in ipairs(t) do
            parts[#parts + 1] = pad .. encodeValue(v, indent + 1)
        end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. closePad .. "]"
    end

    -- Keys are sorted so two exports of one configuration are byte identical,
    -- which makes them diffable and makes a changed file mean something.
    local keys = MFD.H.SortedKeys(t)
    if #keys == 0 then
        return "{}"
    end

    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = pad .. encodeString(tostring(k)) .. ": " .. encodeValue(t[k], indent + 1)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. closePad .. "}"
end

encodeValue = function(value, indent)
    local kind = type(value)
    if kind == "nil" then
        return "null"
    elseif kind == "boolean" then
        return value and "true" or "false"
    elseif kind == "number" then
        -- Whole numbers must not come out as "22890.0"; npc ids are integers.
        if value == math.floor(value) then
            return string.format("%d", value)
        end
        return tostring(value)
    elseif kind == "string" then
        return encodeString(value)
    elseif kind == "table" then
        return encodeTable(value, indent)
    end
    return "null"
end

-- Takes any supported value. Returns pretty printed JSON.
function JSON.Encode(value)
    return encodeValue(value, 0)
end

-- ------------------------------------------------------------------ read --

local UNESCAPES = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b",
    f = "\f", n = "\n", r = "\r", t = "\t",
}

local parseValue

local function skipSpace(text, pos)
    local _, stop = text:find("^[ \t\r\n]*", pos)
    return stop + 1
end

local function parseString(text, pos)
    if text:sub(pos, pos) ~= '"' then
        return nil, pos, "expected a string"
    end

    local out = {}
    local i = pos + 1
    while i <= #text do
        local c = text:sub(i, i)
        if c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local escape = text:sub(i + 1, i + 1)
            if escape == "u" then
                local hex = text:sub(i + 2, i + 5)
                if not hex:match("^%x%x%x%x$") then
                    return nil, i, "bad unicode escape"
                end
                local code = tonumber(hex, 16)
                -- Only the range string.char can represent; anything above is
                -- replaced rather than silently mangled.
                out[#out + 1] = code < 256 and string.char(code) or "?"
                i = i + 6
            elseif UNESCAPES[escape] then
                out[#out + 1] = UNESCAPES[escape]
                i = i + 2
            else
                return nil, i, "bad escape \\" .. tostring(escape)
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end

    return nil, i, "unterminated string"
end

local function parseArray(text, pos)
    local out = {}
    pos = skipSpace(text, pos + 1)

    if text:sub(pos, pos) == "]" then
        return out, pos + 1
    end

    while true do
        local value, err
        value, pos, err = parseValue(text, pos)
        if err then
            return nil, pos, err
        end
        out[#out + 1] = value

        pos = skipSpace(text, pos)
        local c = text:sub(pos, pos)
        if c == "]" then
            return out, pos + 1
        elseif c ~= "," then
            return nil, pos, "expected , or ] in an array"
        end
        pos = skipSpace(text, pos + 1)
    end
end

local function parseObject(text, pos)
    local out = {}
    pos = skipSpace(text, pos + 1)

    if text:sub(pos, pos) == "}" then
        return out, pos + 1
    end

    while true do
        local key, value, err
        key, pos, err = parseString(text, pos)
        if err then
            return nil, pos, err
        end

        pos = skipSpace(text, pos)
        if text:sub(pos, pos) ~= ":" then
            return nil, pos, "expected : after an object key"
        end

        pos = skipSpace(text, pos + 1)
        value, pos, err = parseValue(text, pos)
        if err then
            return nil, pos, err
        end
        out[key] = value

        pos = skipSpace(text, pos)
        local c = text:sub(pos, pos)
        if c == "}" then
            return out, pos + 1
        elseif c ~= "," then
            return nil, pos, "expected , or } in an object"
        end
        pos = skipSpace(text, pos + 1)
    end
end

parseValue = function(text, pos)
    pos = skipSpace(text, pos)
    local c = text:sub(pos, pos)

    if c == "{" then
        return parseObject(text, pos)
    elseif c == "[" then
        return parseArray(text, pos)
    elseif c == '"' then
        return parseString(text, pos)
    elseif text:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif text:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif text:sub(pos, pos + 3) == "null" then
        return nil, pos + 4
    end

    local number = text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
    if number and number ~= "" and tonumber(number) then
        return tonumber(number), pos + #number
    end

    return nil, pos, "unexpected character at position " .. pos
end

-- Takes JSON text. Returns the value, or nil and a reason. Never throws, so a
-- pasted file that is not JSON produces a message rather than a Lua error.
function JSON.Decode(text)
    if type(text) ~= "string" or text:match("^%s*$") then
        return nil, "nothing to read"
    end

    local ok, value, pos, err = pcall(parseValue, text, 1)
    if not ok then
        return nil, "could not read that as JSON"
    end
    if err then
        return nil, err
    end
    if value == nil then
        return nil, "could not read that as JSON"
    end

    local rest = skipSpace(text, pos)
    if rest <= #text then
        return nil, "unexpected text after position " .. rest
    end

    return value
end

_G.MarkedForDeath = MFD
