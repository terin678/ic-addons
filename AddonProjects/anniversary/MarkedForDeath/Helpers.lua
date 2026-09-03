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

local B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP = {}
for i = 1, #B64_ALPHABET do
    B64_LOOKUP[string.sub(B64_ALPHABET, i, i)] = i - 1
end

-- Standard base64. Hand-rolled rather than pulled from a library so the addon
-- folder stays free of dependencies; rule sets are small enough that the extra
-- string length costs nothing worth a vendored lib.
function H.Base64Encode(str)
    local out = {}

    for i = 1, #str, 3 do
        local a, b, c = string.byte(str, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64

        out[#out + 1] = string.sub(B64_ALPHABET, c1 + 1, c1 + 1)
        out[#out + 1] = string.sub(B64_ALPHABET, c2 + 1, c2 + 1)
        out[#out + 1] = b and string.sub(B64_ALPHABET, c3 + 1, c3 + 1) or "="
        out[#out + 1] = c and string.sub(B64_ALPHABET, c4 + 1, c4 + 1) or "="
    end

    return table.concat(out)
end

-- Returns the decoded string, or nil when the input is not valid base64. A
-- mistyped import string must fail loudly rather than produce a corrupt rule
-- set, so both the length and every character are checked.
function H.Base64Decode(str)
    if type(str) ~= "string" then
        return nil
    end

    if str == "" then
        return ""
    end

    if #str % 4 ~= 0 then
        return nil
    end

    local out = {}

    for i = 1, #str, 4 do
        local values, padding = {}, 0

        for j = 1, 4 do
            local char = string.sub(str, i + j - 1, i + j - 1)
            if char == "=" then
                padding = padding + 1
                values[j] = 0
            else
                local value = B64_LOOKUP[char]
                if not value then
                    return nil
                end
                values[j] = value
            end
        end

        local n = values[1] * 262144 + values[2] * 4096 + values[3] * 64 + values[4]
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if padding < 2 then
            out[#out + 1] = string.char(math.floor(n / 256) % 256)
        end
        if padding < 1 then
            out[#out + 1] = string.char(n % 256)
        end
    end

    return table.concat(out)
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
