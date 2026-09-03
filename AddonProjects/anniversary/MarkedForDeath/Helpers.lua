-- Pure helpers. This file must never call a WoW API, so that it loads under the
-- headless test harness. Caching globals into locals is fine; calling is not.
local MFD = _G.MarkedForDeath or {}

MFD.H = MFD.H or {}
local H = MFD.H

-- GUID kinds that can carry a raid target icon. Player GUIDs have a different
-- shape and are rejected by the pattern anyway; this guards the rest.
local MARKABLE_GUID_TYPES = {
    Creature = true,
    Vehicle = true,
    Pet = true,
}

-- Takes a unit GUID string. Returns npcID as a number and spawnUID as a string,
-- or nil when the GUID is not a markable creature-shaped GUID. No side effects.
function H.SplitGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end

    local kind, npcID, spawnUID = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-(%x+)$")
    if not kind or not MARKABLE_GUID_TYPES[kind] then
        return nil
    end

    return tonumber(npcID), spawnUID
end

-- Takes a unit GUID. Returns the compact wire key "npcID:spawnUID" used as the
-- identity for a mob across the addon channel, or nil. Both ends of a message
-- derive this the same way, which is why full GUIDs never go over the wire.
function H.KeyFromGUID(guid)
    local npcID, spawnUID = H.SplitGUID(guid)
    if not npcID then
        return nil
    end
    return npcID .. ":" .. spawnUID
end

-- Takes a compact key. Returns the npcID as a number, or nil.
function H.NpcIDFromKey(key)
    if type(key) ~= "string" then
        return nil
    end
    return tonumber(key:match("^(%d+):"))
end

-- Fills every key of defaults that is missing from target, recursing into
-- tables. Mutates and returns target. Existing values are never overwritten,
-- which is what makes it safe to call on every ADDON_LOADED.
function H.ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            H.ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Returns a deep copy of t. Used when a merged rule is edited into the local
-- set, so the caller never aliases another contributor's table.
function H.DeepCopy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = H.DeepCopy(v)
    end
    return out
end

-- Returns the keys of t as an array sorted ascending by tostring. Table
-- iteration order is undefined in Lua, so anything whose result must match
-- across clients iterates through this instead of pairs().
function H.SortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- Searches the bundled and learned mob tables. Takes a case-insensitive query,
-- an optional instance key filter, the bundled table
-- ({ [npcID] = { name, instanceKey } }) and the learned table
-- ({ [npcID] = { name, zone } }). Returns an array of { npcID, name, source }
-- sorted by name. The tables are arguments rather than globals so this stays
-- pure and testable.
--
-- Learned entries carry the zone name they were seen in rather than an
-- instance key, so the filter matches them through the instance's display
-- name. A learned mob from a zone that cannot be mapped is shown rather than
-- hidden, because losing it is worse than one extra row.
function MFD.Search(query, instanceKey, bundled, learned)
    local needle = string.lower(query or "")
    local results, seen = {}, {}

    local zoneNames = MFD.Rules and MFD.Rules.INSTANCE_ZONE_NAMES or {}
    local targetZone = instanceKey and zoneNames[instanceKey]

    local knownZones = {}
    for _, zoneName in pairs(zoneNames) do
        knownZones[zoneName] = true
    end

    for _, npcID in ipairs(H.SortedKeys(bundled)) do
        local entry = bundled[npcID]
        local matchesInstance = not instanceKey or entry[2] == instanceKey
        if matchesInstance and string.find(string.lower(entry[1]), needle, 1, true) then
            seen[npcID] = true
            results[#results + 1] = { npcID = npcID, name = entry[1], source = "bundled" }
        end
    end

    for _, npcID in ipairs(H.SortedKeys(learned)) do
        local entry = learned[npcID]
        if not seen[npcID] and entry.name and string.find(string.lower(entry.name), needle, 1, true) then
            local isMappable = entry.zone and knownZones[entry.zone]
            local matchesInstance = not targetZone or not isMappable or entry.zone == targetZone
            if matchesInstance then
                results[#results + 1] = { npcID = npcID, name = entry.name, source = "learned" }
            end
        end
    end

    table.sort(results, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.npcID < b.npcID
    end)

    return results
end

_G.MarkedForDeath = MFD
