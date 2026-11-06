local addonName, ns = ...

--[[
Capture: what /mfd capture saw, merged into a capped store, and the JSON export the merge
script reads. Pure: no client call, ever; every function takes its tables as arguments.

Owned by lane E (data and capture). CaptureWatch.lua reads the client and hands each
sighting here as an observation; nothing secret ever reaches this file, because the
watcher turns a secret read into `{ kind = "npc", secret = true }` before it calls Merge.

    Capture.NpcID(guid)                    -> the npc id in a creature or vehicle GUID, else nil
    Capture.InstanceObservation(...)       -> an observation from GetInstanceInfo's returns
    Capture.Merge(store, obs, now)         -> "added" | "updated" | "hidden", or nil and why
    Capture.Clear(store)                   -> empties the store, keeps the table
    Capture.Summary(store, instanceName)   -> the lines /mfd capture show prints
    Capture.Export(store, meta)            -> JSON text, or nil and why
    Capture.Read(text)                     -> an export table, or nil and why

The store is the saved `capture` table: { instances, encounters, npcs, auras, hidden }.
Each kind is capped (CAPS); past the cap the entry seen longest ago is dropped.

Observation shapes (every field but kind and id optional):
    { kind = "instance", id, name, type, difficulty, difficultyName, size }
    { kind = "encounter", id, name, instance, difficulty, size, result = "start"|"kill"|"wipe" }
    { kind = "npc", id, name, instance, creature, classification }   or { kind = "npc", secret = true }
    { kind = "aura", id, name, source = "aura"|"cast" }
]]

ns.Capture = ns.Capture or {}
local Capture = ns.Capture

local JSON = LibStub("LibICJSON-1.0")

Capture.FORMAT = "mfd-capture"   -- the export's own name, so another addon's JSON is refused
Capture.FORMAT_VERSION = 1

-- Entries kept per kind before the one seen longest ago is dropped.
Capture.CAPS = { instances = 200, encounters = 200, npcs = 2000, auras = 500 }

local KINDS = { "instances", "encounters", "npcs", "auras" }
local RESULTS = { start = true, kill = true, wipe = true }
local SOURCES = { aura = true, cast = true }

--------------------------------------------------------------------------------
-- Small pure helpers
--------------------------------------------------------------------------------

-- "Creature-0-1-2999-4-250660-0000ABCDEF" -> 250660. Players, pets and items give nil.
function Capture.NpcID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    return id
end

-- GetInstanceInfo returns name, instanceType, difficultyID, difficultyName, maxPlayers,
-- dynamicDifficulty, isDynamic, instanceID. The caller passes them through Readable first,
-- so a secret one arrives as nil. Returns nil outside an instance (id 0 or unreadable).
function Capture.InstanceObservation(name, instanceType, difficultyID, difficultyName, maxPlayers, _, _, instanceID)
    if type(instanceID) ~= "number" or instanceID <= 0 then return nil end
    return {
        kind = "instance",
        id = instanceID,
        name = type(name) == "string" and name ~= "" and name or nil,
        type = type(instanceType) == "string" and instanceType or nil,
        difficulty = type(difficultyID) == "number" and difficultyID or nil,
        difficultyName = type(difficultyName) == "string" and difficultyName ~= "" and difficultyName or nil,
        size = type(maxPlayers) == "number" and maxPlayers > 0 and maxPlayers or nil,
    }
end

local function Text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function Num(v)
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
    return nil
end

local function Ensure(store)
    for _, kind in ipairs(KINDS) do
        if type(store[kind]) ~= "table" then store[kind] = {} end
    end
    if type(store.hidden) ~= "number" then store.hidden = 0 end
end

-- Drops the entry seen longest ago (ties: the smaller key as text) while past the cap.
local function Trim(list, cap)
    local n = 0
    for _ in pairs(list) do n = n + 1 end
    while n > cap do
        local oldKey, oldSeen
        for key, entry in pairs(list) do
            local seen = entry.seen or 0
            if oldKey == nil or seen < oldSeen
                or (seen == oldSeen and tostring(key) < tostring(oldKey)) then
                oldKey, oldSeen = key, seen
            end
        end
        list[oldKey] = nil
        n = n - 1
    end
end

-- Finds or makes list[key]; returns entry, wasNew.
local function Touch(list, key, now)
    local entry = list[key]
    if entry then
        entry.seen = now
        entry.count = (entry.count or 0) + 1
        return entry, false
    end
    entry = { first = now, seen = now, count = 1 }
    list[key] = entry
    return entry, true
end

-- Sets entry[field] to value when value is known; a later unreadable read never wipes
-- what an earlier one learned.
local function Learn(entry, field, value)
    if value ~= nil then entry[field] = value end
end

--------------------------------------------------------------------------------
-- Merge
--------------------------------------------------------------------------------

local MERGE = {}

function MERGE.instance(store, obs, now)
    local id = Num(obs.id)
    if not id or id <= 0 then return nil, "no instance id" end
    local entry, isNew = Touch(store.instances, id, now)
    entry.id = id
    Learn(entry, "name", Text(obs.name))
    Learn(entry, "type", Text(obs.type))
    Learn(entry, "difficulty", Num(obs.difficulty))
    Learn(entry, "difficultyName", Text(obs.difficultyName))
    Learn(entry, "size", Num(obs.size))
    return isNew, "instances"
end

function MERGE.encounter(store, obs, now)
    local id = Num(obs.id)
    if not id or id <= 0 then return nil, "no encounter id" end
    local result = RESULTS[obs.result] and obs.result or "start"
    local entry, isNew = Touch(store.encounters, id, now)
    entry.id = id
    Learn(entry, "name", Text(obs.name))
    local instance = Num(obs.instance)
    if instance and instance > 0 then entry.instance = instance end
    Learn(entry, "difficulty", Num(obs.difficulty))
    Learn(entry, "size", Num(obs.size))
    entry.pulls = (entry.pulls or 0) + (result == "start" and 1 or 0)
    entry.kills = (entry.kills or 0) + (result == "kill" and 1 or 0)
    entry.wipes = (entry.wipes or 0) + (result == "wipe" and 1 or 0)
    return isNew, "encounters"
end

function MERGE.npc(store, obs, now)
    local id, name = Num(obs.id), Text(obs.name)
    if obs.secret or not id or id <= 0 or not name then
        -- A secret read, or one that came back without an id or a name: counted, never stored.
        store.hidden = store.hidden + 1
        return "hidden"
    end
    local instance = Num(obs.instance)
    if not instance or instance < 0 then instance = 0 end
    local entry, isNew = Touch(store.npcs, instance .. ":" .. id, now)
    entry.id, entry.instance, entry.name = id, instance, name
    Learn(entry, "creature", Text(obs.creature))
    Learn(entry, "classification", Text(obs.classification))
    return isNew, "npcs"
end

function MERGE.aura(store, obs, now)
    local id = Num(obs.id)
    if not id or id <= 0 then return nil, "no spell id" end
    local entry, isNew = Touch(store.auras, id, now)
    entry.id = id
    Learn(entry, "name", Text(obs.name))
    if SOURCES[obs.source] then entry.source = obs.source end
    return isNew, "auras"
end

-- Merges one observation into store at time now (a time() integer). Returns "added" for
-- a new entry, "updated" for one seen before, "hidden" for a secret read (counted in
-- store.hidden only), or nil and a reason for an observation it cannot use.
function Capture.Merge(store, obs, now)
    if type(store) ~= "table" then return nil, "no store" end
    if type(obs) ~= "table" then return nil, "no observation" end
    local merge = MERGE[obs.kind]
    if not merge then return nil, "unknown kind " .. tostring(obs.kind) end
    Ensure(store)
    now = Num(now) or 0
    local isNew, kindOrWhy = merge(store, obs, now)
    if isNew == "hidden" then return "hidden" end
    if isNew == nil then return nil, kindOrWhy end
    if isNew then
        Trim(store[kindOrWhy], Capture.CAPS[kindOrWhy])
        return "added"
    end
    return "updated"
end

function Capture.Clear(store)
    for _, kind in ipairs(KINDS) do store[kind] = {} end
    store.hidden = 0
    return store
end

--------------------------------------------------------------------------------
-- Show
--------------------------------------------------------------------------------

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- The lines /mfd capture show prints. instanceName(id) names an instance the store saw
-- no name for (the bundled data's lookup); optional.
function Capture.Summary(store, instanceName)
    Ensure(store)
    local lines = {
        string.format("%d instances, %d encounters, %d mobs, %d auras and casts.",
            Count(store.instances), Count(store.encounters), Count(store.npcs), Count(store.auras)),
    }
    if store.hidden > 0 then
        lines[#lines + 1] = string.format("%d sightings had their names hidden by the client and were not kept.",
            store.hidden)
    end

    local perInstance = {}
    for _, npc in pairs(store.npcs) do
        perInstance[npc.instance] = (perInstance[npc.instance] or 0) + 1
    end
    local encounters = {}
    for _, enc in pairs(store.encounters) do
        if enc.instance then encounters[enc.instance] = (encounters[enc.instance] or 0) + 1 end
    end
    local ids = {}
    local seen = {}
    for id in pairs(store.instances) do ids[#ids + 1] = id; seen[id] = true end
    for id in pairs(perInstance) do if not seen[id] then ids[#ids + 1] = id; seen[id] = true end end
    for id in pairs(encounters) do if not seen[id] then ids[#ids + 1] = id; seen[id] = true end end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local entry = store.instances[id]
        local name = (entry and entry.name) or (instanceName and instanceName(id))
        if id == 0 then name = "open world" end
        local size = entry and entry.size and string.format(" (%d)", entry.size) or ""
        lines[#lines + 1] = string.format("  %s%s, id %d: %d mobs, %d encounters",
            name or "unnamed", size, id, perInstance[id] or 0, encounters[id] or 0)
    end
    return lines
end

--------------------------------------------------------------------------------
-- Export and read
--------------------------------------------------------------------------------

local FIELDS = {
    instances = { "id", "name", "type", "difficulty", "difficultyName", "size", "first", "seen", "count" },
    encounters = { "id", "name", "instance", "difficulty", "size", "pulls", "kills", "wipes", "first", "seen", "count" },
    npcs = { "id", "name", "instance", "creature", "classification", "first", "seen", "count" },
    auras = { "id", "name", "source", "first", "seen", "count" },
}

local TEXT_FIELDS = { name = true, type = true, difficultyName = true, creature = true,
    classification = true, source = true }

-- Rows sort by instance, then id, so two exports of one store are the same text.
local function RowBefore(a, b)
    if (a.instance or 0) ~= (b.instance or 0) then return (a.instance or 0) < (b.instance or 0) end
    return a.id < b.id
end

local function Rows(list, fields)
    local rows = {}
    for _, entry in pairs(list) do
        local row = {}
        for _, field in ipairs(fields) do row[field] = entry[field] end
        rows[#rows + 1] = row
    end
    table.sort(rows, RowBefore)
    return rows
end

-- The store as JSON, one line. meta = { version, build, now }, all optional.
function Capture.Export(store, meta)
    Ensure(store)
    meta = meta or {}
    local doc = {
        format = Capture.FORMAT,
        formatVersion = Capture.FORMAT_VERSION,
        addon = Text(meta.version),
        build = Text(meta.build),
        exported = Num(meta.now),
        hidden = store.hidden,
    }
    for _, kind in ipairs(KINDS) do doc[kind] = Rows(store[kind], FIELDS[kind]) end
    return JSON.Encode(doc, { compact = true })
end

-- Checks one row and returns a clean copy with only the known fields, or nil.
local function CleanRow(kind, row)
    if type(row) ~= "table" then return nil end
    local id = Num(row.id)
    if not id or id <= 0 or id ~= math.floor(id) then return nil end
    local out = {}
    for _, field in ipairs(FIELDS[kind]) do
        local v = row[field]
        if TEXT_FIELDS[field] then
            out[field] = Text(v)
        else
            out[field] = Num(v)
        end
    end
    if kind == "npcs" then
        if not out.name then return nil end
        out.instance = out.instance or 0
    end
    return out
end

-- Reads an export. Returns { formatVersion, addon, build, exported, hidden, instances,
-- encounters, npcs, auras } with each kind a list of clean rows, or nil and why. Rows it
-- cannot use are skipped and counted in `skipped`. A newer format is refused whole.
function Capture.Read(text)
    if type(text) ~= "string" or text == "" then return nil, "nothing to read" end
    local doc, why = JSON.Decode(text)
    if type(doc) ~= "table" then return nil, "not JSON: " .. tostring(why) end
    if doc.format ~= Capture.FORMAT then return nil, "not a Marked For Death capture" end
    local version = Num(doc.formatVersion)
    if not version then return nil, "the capture has no format version" end
    if version > Capture.FORMAT_VERSION then
        return nil, string.format("capture format %d is newer than this reader (%d)", version, Capture.FORMAT_VERSION)
    end
    local out = {
        formatVersion = version,
        addon = Text(doc.addon),
        build = Text(doc.build),
        exported = Num(doc.exported),
        hidden = Num(doc.hidden) or 0,
        skipped = 0,
    }
    for _, kind in ipairs(KINDS) do
        out[kind] = {}
        if type(doc[kind]) == "table" then
            for _, row in pairs(doc[kind]) do
                local clean = CleanRow(kind, row)
                if clean then
                    out[kind][#out[kind] + 1] = clean
                else
                    out.skipped = out.skipped + 1
                end
            end
        end
        table.sort(out[kind], RowBefore)
    end
    return out
end
