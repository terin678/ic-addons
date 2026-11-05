local addonName, ns = ...

--[[
Rules: a mob rule names a job and a rank, never an icon. Pure: no client call, ever; every
function takes its tables as arguments.

Owned by lane A (model).

Keys (spec 7.1). An instance is "i:<instanceID>", the open world is "open", and a rule set
read from an Anniversary file sits under "legacy:<zone>" until the player moves it. Inside
one instance a rule is filed under "n:<name as shown>", or "id:<npcID>" when only the id is
known. A rule:

    { name = "Scarlet Sorcerer", npcID = 4294, intent = "SHEEP", rank = 20,
      fallback = "KILL", maxCount = 2, from = "me", updated = 1793836800 }

Matching works by npc id where the id is readable and by name where the name is readable.
Blind (both secret) matches nothing; the allocator then runs on the rules themselves.

    Rules.InstanceKey(type, id)     "i:33", or "open"
    Rules.CheckName(name)           the trimmed name, or nil and why (quotes, ; refused)
    Rules.Key(rule)                 "n:<name>" | "id:<npc>" | nil
    Rules.New(fields)               a checked rule, or nil and why
    Rules.Ranked(set)               the rules by rank, ties by key
    Rules.Renumber(list)            ranks 10, 20, 30 ... in list order
    Rules.Match(set, mob)           rule, key for { npcID, name }: id first, then name
    Rules.Resolve(set, candidates)  { [candidate.key] = rule }
    Rules.Merge(mine, theirs, from) a new set: mine wins, theirs fills gaps
    Rules.ParseBulk(text)           pasted lines to rules, or nil and why
    Rules.ToJSON(byInstance, meta)  share format v2
    Rules.FromJSON(text)            reads v2 and Anniversary v1; refuses the rest whole
]]

ns.Rules = ns.Rules or {}
local Rules = ns.Rules
local CC = ns.CC
local Util = LibStub("LibICUtil-1.0")
local JSON = LibStub("LibICJSON-1.0")

Rules.RANK_STEP = 10
Rules.SHARE_VERSION = 2
Rules.MAX_NAME = 64       -- bytes; longer than any mob name the game shows

local lower = string.lower

function Rules.InstanceKey(instanceType, instanceID)
    if instanceType == nil or instanceType == "none" or type(instanceID) ~= "number" or instanceID <= 0 then
        return "open"
    end
    return "i:" .. instanceID
end

-- True for a key the reader accepts: "open", "i:<n>", "legacy:<zone>".
function Rules.IsInstanceKey(key)
    if type(key) ~= "string" then return false end
    return key == "open" or key:match("^i:%d+$") ~= nil or key:match("^legacy:.+") ~= nil
end

function Rules.IsLegacy(key)
    return type(key) == "string" and key:match("^legacy:") ~= nil
end

-- A name goes into a macro line as it is, so anything that would change what the line
-- means is refused at entry: a double quote, a semicolon (the macro's "or"), brackets (a
-- conditional), a pipe (an escape), a backslash, a line break. An apostrophe is fine:
-- plenty of mob names hold one.
function Rules.CheckName(name)
    if type(name) ~= "string" then return nil, "a name is text" end
    local trimmed = Util.Trim(name)
    if trimmed == "" then return nil, "the name is empty" end
    if #trimmed > Rules.MAX_NAME then return nil, "the name is longer than " .. Rules.MAX_NAME .. " characters" end
    local bad = trimmed:match("[\";%[%]|\\\r\n]")
    if bad then return nil, "a name cannot hold " .. (bad == "\n" and "a line break" or bad) end
    return trimmed
end

function Rules.Key(rule)
    if type(rule) ~= "table" then return nil end
    if type(rule.name) == "string" and rule.name ~= "" then return "n:" .. rule.name end
    if type(rule.npcID) == "number" then return "id:" .. rule.npcID end
    return nil
end

local function PositiveInt(v)
    return type(v) == "number" and v >= 1 and v % 1 == 0
end

--[[
fields: { name, npcID, intent, rank, fallback, maxCount, from, updated }. Returns a fresh
rule or nil and why. intent defaults to KILL; a job and a fallback must be known; a
fallback must be a job that can be marked (not IGNORE) and differ from the job.
]]
function Rules.New(fields)
    if type(fields) ~= "table" then return nil, "nothing to make a rule from" end
    local rule = {}
    if fields.name ~= nil then
        local name, why = Rules.CheckName(fields.name)
        if not name then return nil, why end
        rule.name = name
    end
    if fields.npcID ~= nil then
        if not PositiveInt(fields.npcID) then return nil, "an npc id is a whole number" end
        rule.npcID = fields.npcID
    end
    if not rule.name and not rule.npcID then return nil, "a rule names a mob or an npc id" end

    local intent = fields.intent or "KILL"
    if not CC.IsKnown(intent) then return nil, "unknown job '" .. tostring(intent) .. "'" end
    rule.intent = intent

    if fields.fallback ~= nil then
        if not CC.IsKnown(fields.fallback) or fields.fallback == "IGNORE" then
            return nil, "unknown fallback '" .. tostring(fields.fallback) .. "'"
        end
        if fields.fallback ~= intent then rule.fallback = fields.fallback end
    end
    if fields.maxCount ~= nil then
        if not PositiveInt(fields.maxCount) then return nil, "max count is a whole number from 1" end
        rule.maxCount = fields.maxCount
    end
    rule.rank = type(fields.rank) == "number" and fields.rank or Rules.RANK_STEP
    rule.from = fields.from
    rule.updated = fields.updated
    return rule
end

function Rules.Ranked(set)
    local list = {}
    for _, key in ipairs(Util.SortedKeys(set or {})) do
        local rule = set[key]
        if type(rule) == "table" then list[#list + 1] = { key = key, rule = rule } end
    end
    table.sort(list, function(a, b)
        local ar, br = a.rule.rank or 0, b.rule.rank or 0
        if ar ~= br then return ar < br end
        return a.key < b.key
    end)
    local rules = {}
    for i, entry in ipairs(list) do rules[i] = entry.rule end
    return rules, list
end

-- list: rules in the order wanted. Mutates their ranks; returns list.
function Rules.Renumber(list)
    for i, rule in ipairs(list) do rule.rank = i * Rules.RANK_STEP end
    return list
end

-- An index built once per set: by npc id, and by lower-cased name.
local function Index(set)
    local byID, byName = {}, {}
    for _, entry in ipairs(select(2, Rules.Ranked(set))) do
        local rule = entry.rule
        if rule.npcID and not byID[rule.npcID] then byID[rule.npcID] = entry end
        if type(rule.name) == "string" then
            local k = lower(rule.name)
            if not byName[k] then byName[k] = entry end
        end
    end
    return { byID = byID, byName = byName }
end

local function MatchIn(index, mob)
    if type(mob) ~= "table" then return nil end
    local entry = type(mob.npcID) == "number" and index.byID[mob.npcID]
    if not entry and type(mob.name) == "string" then entry = index.byName[lower(mob.name)] end
    if entry then return entry.rule, entry.key end
    return nil
end

-- mob: { npcID, name }, either nil when unreadable (the caller passes nothing secret).
-- The id is the more specific statement, so it wins over a name rule for the same mob.
-- Returns rule, key or nil.
function Rules.Match(set, mob)
    return MatchIn(Index(set), mob)
end

-- candidates: { { key, npcID, name }, ... }. Returns { [candidate.key] = rule }.
function Rules.Resolve(set, candidates)
    local index, out = Index(set), {}
    for _, candidate in ipairs(candidates or {}) do
        local rule = MatchIn(index, candidate)
        if rule and candidate.key ~= nil then out[candidate.key] = rule end
    end
    return out
end

--[[
mine, theirs: rule sets for one instance. Returns a new set and how many rules came in.
Mine wins: a key I hold, or a rule of theirs naming a mob I already rule (same npc id or
same name), is skipped. What comes in is a copy with from = `from`.
]]
function Rules.Merge(mine, theirs, from)
    local out = Util.DeepCopy(mine or {})
    local index = Index(out)
    local added = 0
    for _, key in ipairs(Util.SortedKeys(theirs or {})) do
        local rule = theirs[key]
        if type(rule) == "table" and out[key] == nil and not MatchIn(index, rule) then
            local copy = Util.DeepCopy(rule)
            copy.from = from or copy.from
            out[key] = copy
            added = added + 1
            index = Index(out)
        end
    end
    return out, added
end

--[[
A pasted kill order, highest priority first, one mob per line, an optional job after "=":

    Scarlet Sorcerer = sheep
    Scarlet Monk
    4294 = banish

Blank lines and lines starting with -- or # are skipped. Returns an array of rules ranked
10, 20 ... or nil and the first bad line. One bad line refuses the whole paste: half a
kill order looks complete and is not.
]]
function Rules.ParseBulk(text)
    if type(text) ~= "string" then return nil, "nothing to read" end
    local rules, seen, n = {}, {}, 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local trimmed = Util.Trim((line:gsub("\r", "")))
        if trimmed ~= "" and trimmed:sub(1, 2) ~= "--" and trimmed:sub(1, 1) ~= "#" then
            local subject, job = trimmed:match("^(.-)%s*=%s*(.-)$")
            if not subject then subject = trimmed end
            local intent = (job and job ~= "") and string.upper(job) or "KILL"
            if not CC.IsKnown(intent) then return nil, "line " .. n .. ": unknown job '" .. job .. "'" end
            local id = subject:match("^%d+$") and tonumber(subject)
            local rule, why = Rules.New({
                npcID = id or nil, name = (not id) and subject or nil,
                intent = intent, rank = (#rules + 1) * Rules.RANK_STEP,
            })
            if not rule then return nil, "line " .. n .. ": " .. why end
            local key = lower(Rules.Key(rule))
            if seen[key] then return nil, "line " .. n .. ": '" .. subject .. "' is already in this list" end
            seen[key] = true
            rules[#rules + 1] = rule
        end
    end
    if #rules == 0 then return nil, "no mob names found" end
    return rules
end

--------------------------------------------------------------------------------
-- Share format
--------------------------------------------------------------------------------

--[[
byInstance: { [instanceKey] = rule set }. Returns JSON text (sorted, indented) or nil and
why. Plain words for a person reading it: job, priority, npc, name.
]]
function Rules.ToJSON(byInstance, meta)
    local doc = {
        addon = "MarkedForDeath",
        formatVersion = Rules.SHARE_VERSION,
        note = meta and meta.note or nil,
        rules = {},
    }
    for _, instanceKey in ipairs(Util.SortedKeys(byInstance or {})) do
        local out = {}
        for _, rule in ipairs((Rules.Ranked(byInstance[instanceKey]))) do
            out[#out + 1] = {
                name = rule.name, npc = rule.npcID, job = rule.intent, priority = rule.rank,
                fallback = rule.fallback, maxCount = rule.maxCount,
            }
        end
        if #out > 0 then doc.rules[instanceKey] = out end
    end
    return JSON.Encode(doc)
end

local function ReadEntry(instanceKey, index, entry)
    if type(entry) ~= "table" then return nil, instanceKey .. ": rule " .. index .. " is not a rule" end
    local job = type(entry.job) == "string" and string.upper(entry.job) or nil
    if not job or not CC.IsKnown(job) then
        return nil, instanceKey .. ": unknown job '" .. tostring(entry.job) .. "'"
    end
    local fallback = type(entry.fallback) == "string" and string.upper(entry.fallback) or nil
    local rule, why = Rules.New({
        name = type(entry.name) == "string" and entry.name ~= "" and entry.name or nil,
        npcID = tonumber(entry.npc),
        intent = job,
        rank = tonumber(entry.priority) or index * Rules.RANK_STEP,
        fallback = fallback,
        maxCount = tonumber(entry.maxCount),
    })
    if not rule then return nil, instanceKey .. ": rule " .. index .. ": " .. why end
    return rule
end

--[[
Returns { [instanceKey] = rule set }, the format version read, or nil and why. Version 1
(Anniversary) keys were zone names; each becomes "legacy:<zone>". Version 2 keys must be
instance keys. A file that is not ours, a newer version, an unknown job, a bad name or two
rules for one mob refuses the whole file.
]]
function Rules.FromJSON(text)
    local doc, err = JSON.Decode(text)
    if not doc then return nil, err end
    if type(doc) ~= "table" or doc.addon ~= "MarkedForDeath" then
        return nil, "that is not a Marked For Death file"
    end
    local version = doc.formatVersion
    if type(version) ~= "number" or version < 1 then return nil, "that file has no format version" end
    if version > Rules.SHARE_VERSION then return nil, "that file was made by a newer version of the addon" end
    if type(doc.rules) ~= "table" then return nil, "that file has no rules in it" end

    local out = {}
    for _, fileKey in ipairs(Util.SortedKeys(doc.rules)) do
        local instanceKey = fileKey
        if version == 1 then
            instanceKey = "legacy:" .. tostring(fileKey)
        elseif not Rules.IsInstanceKey(fileKey) then
            return nil, "'" .. tostring(fileKey) .. "' is not an instance key"
        end
        local list = doc.rules[fileKey]
        if type(list) ~= "table" then return nil, instanceKey .. ": rules should be a list" end
        local set = {}
        for index, entry in ipairs(list) do
            local rule, why = ReadEntry(instanceKey, index, entry)
            if not rule then return nil, why end
            local key = Rules.Key(rule)
            if set[key] then return nil, instanceKey .. ": two rules for " .. key:sub(3) end
            set[key] = rule
        end
        out[instanceKey] = set
    end
    return out, version
end
