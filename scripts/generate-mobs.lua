-- Generates MarkedForDeath's bundled raid creature table.
--
-- Usage:
--   luajit scripts/generate-mobs.lua <path to Questie tbcNpcDB.lua> <outfile>
--
-- Source of names and ids: Questie's TBC creature database, which ships with
-- the same client this addon targets, so every name is the name the game
-- reports. Membership of a raid is established three ways, in order of trust:
--
--   1. Spawn data. Most raids' creatures carry a zone id, and the zone id is
--      itself discovered from where that raid's bosses spawn rather than from
--      a remembered list.
--   2. A roster from another addon. Hyjal's waves are summoned by script and
--      carry no zone, so the roster comes from DBM-Raids-BC's WaveTimers
--      localization (Ghouls, Abominations, Necromancers, Banshees, Crypt
--      Fiends, Gargoyles, Frost Wyrm, Fel Stalkers, Infernals) and each name is
--      resolved to an id here.
--   3. An id block. Tempest Keep has no spawn data at all and its creature
--      families are shared with the four five-man wings, so The Eye's own
--      trash is taken from the contiguous id block those creatures occupy.
--
-- Anything that cannot be established by one of those is left out. A missing
-- entry only means the search box will not suggest that mob; rules can always
-- be typed by name, so a gap is an inconvenience and a wrong entry is a lie.
local dbPath, outPath = ...
assert(dbPath and outPath, "usage: luajit generate-mobs.lua <tbcNpcDB.lua> <outfile>")

local f = assert(io.open(dbPath, "r"))
local text = f:read("*a")
f:close()

local body = assert(text:match("QuestieDB%.npcData = %[%[(.-)%]%]"),
    "could not find QuestieDB.npcData; has Questie's format changed?")

-- Field positions, from QuestieDB.npcKeys at the top of the source file.
local NAME, MINLEVEL, MAXLEVEL, RANK, SPAWNS, ZONE, FRIENDLY = 1, 4, 5, 6, 7, 9, 13

-- The table is far past Lua's 65536 constants per chunk, so each entry is
-- compiled on its own.
local npcs = {}
for line in string.gmatch(body, "[^\n]+") do
    local id = line:match("^%[(%d+)%]")
    local tbl = line:match("=%s*(%b{})")
    if id and tbl then
        local chunk = loadstring("return " .. tbl)
        if chunk then
            local ok, value = pcall(chunk)
            if ok then npcs[tonumber(id)] = value end
        end
    end
end

local RAIDS = {
    { key = "KARAZHAN", label = "Karazhan",
      bosses = { 15550, 15691, 16457, 15687, 15688, 15689, 16524, 15690, 17225 } },
    { key = "GRUUL", label = "Gruul's Lair", bosses = { 18831, 19044 } },
    { key = "MAGTHERIDON", label = "Magtheridon's Lair", bosses = { 17257 } },
    { key = "SERPENTSHRINE", label = "Serpentshrine Cavern",
      bosses = { 21212, 21214, 21215, 21217, 21216, 21213 } },
    { key = "TEMPESTKEEP", label = "Tempest Keep",
      bosses = { 19514, 19516, 18805, 19622 },
      -- The Eye's trash occupies this block; the surrounding ids belong to the
      -- five-man wings and to outdoor Netherstorm.
      idBlock = { 20031, 20090 } },
    { key = "HYJAL", label = "Hyjal Summit",
      bosses = { 17767, 17808, 17888, 17842, 17968 },
      -- Wave roster per DBM-Raids-BC, resolved to ids by exact name.
      roster = {
          "Ghoul", "Abomination", "Shadowy Necromancer", "Banshee", "Crypt Fiend",
          "Crypt Scarab", "Gargoyle", "Frost Wyrm", "Fel Stalker", "Giant Infernal",
          "Towering Infernal", "Lesser Doomguard", "Skeleton Invader", "Skeleton Mage",
      } },
    { key = "BLACKTEMPLE", label = "Black Temple",
      bosses = { 22887, 22898, 22841, 22871, 22948, 23420, 22947, 22949, 22917 } },
    { key = "ZULAMAN", label = "Zul'Aman",
      bosses = { 23574, 23576, 23578, 23577, 24239, 23863 } },
    { key = "SUNWELL", label = "Sunwell Plateau",
      bosses = { 24850, 24882, 25038, 25166, 25741, 25315 } },
}

-- Script helpers and art assets that are never worth marking.
local function isNoise(name)
    return name:find("Image$") or name:find("Visual") or name:find("Trigger")
        or name:find("Relay") or name:find("Target %(") or name:find("Dummy")
        or name:find("Bunny") or name:find("^Waypoint")
end

-- isTrusted is set for the explicit boss lists below, which may override the
-- hostile-only test. Some bosses are flagged friendly in the source because
-- they start non-hostile, Brutallus being the one that actually bites.
local function isMarkable(n, isTrusted)
    return type(n[NAME]) == "string" and n[NAME] ~= ""
        and (isTrusted or n[FRIENDLY] == nil) and not isNoise(n[NAME])
end

local function zonesOf(n)
    local zones = {}
    if type(n[SPAWNS]) == "table" then
        for z in pairs(n[SPAWNS]) do zones[z] = true end
    end
    if type(n[ZONE]) == "number" and n[ZONE] ~= 0 then zones[n[ZONE]] = true end
    return zones
end

print("=== zone id, discovered from where each raid's bosses spawn ===")
for _, raid in ipairs(RAIDS) do
    local votes = {}
    for _, id in ipairs(raid.bosses) do
        local n = npcs[id]
        if n then
            for z in pairs(zonesOf(n)) do votes[z] = (votes[z] or 0) + 1 end
        end
    end
    local best, bestCount = nil, 0
    for z, count in pairs(votes) do
        if count > bestCount then best, bestCount = z, count end
    end
    raid.zone = best
    print(string.format("%-14s %s", raid.key,
        best and ("zone " .. best .. ", agreed by " .. bestCount .. "/" .. #raid.bosses .. " bosses")
             or "no spawn data, using a roster or id block"))
end

local assigned = {}
local byRaid = {}
for _, raid in ipairs(RAIDS) do byRaid[raid.key] = {} end

local function claim(raidKey, id, how)
    if assigned[id] or not npcs[id] or not isMarkable(npcs[id], how == "boss") then
        return false
    end
    assigned[id] = raidKey
    table.insert(byRaid[raidKey], { id = id, how = how })
    return true
end

-- 1. Spawn data.
for _, raid in ipairs(RAIDS) do
    if raid.zone then
        local ids = {}
        for id, n in pairs(npcs) do
            if isMarkable(n) and zonesOf(n)[raid.zone] then
                ids[#ids + 1] = id
            end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do claim(raid.key, id, "zone") end
    end
end

-- 2. Named rosters, for raids whose creatures are summoned.
for _, raid in ipairs(RAIDS) do
    for _, wanted in ipairs(raid.roster or {}) do
        local hits = {}
        for id, n in pairs(npcs) do
            if n[NAME] == wanted and isMarkable(n) and (n[MAXLEVEL] or 0) >= 63 then
                hits[#hits + 1] = id
            end
        end
        if #hits == 1 then
            claim(raid.key, hits[1], "roster")
        else
            print(string.format("  SKIPPED %-22s %d matches, cannot tell which", wanted, #hits))
        end
    end
end

-- 3. Id blocks, for raids with neither.
for _, raid in ipairs(RAIDS) do
    if raid.idBlock then
        for id = raid.idBlock[1], raid.idBlock[2] do
            local n = npcs[id]
            if n and isMarkable(n) and (n[MAXLEVEL] or 0) >= 68 then
                claim(raid.key, id, "block")
            end
        end
    end
end

-- Bosses last, so a boss that fell outside every rule is still present.
for _, raid in ipairs(RAIDS) do
    for _, id in ipairs(raid.bosses) do claim(raid.key, id, "boss") end
end

print()
print("=== result, and proof every boss survived ===")
local total = 0
for _, raid in ipairs(RAIDS) do
    local list = byRaid[raid.key]
    table.sort(list, function(a, b) return a.id < b.id end)
    total = total + #list

    local missing = {}
    for _, id in ipairs(raid.bosses) do
        if assigned[id] ~= raid.key then
            missing[#missing + 1] = (npcs[id] and npcs[id][NAME]) or ("id " .. id)
        end
    end

    local counts = {}
    for _, entry in ipairs(list) do counts[entry.how] = (counts[entry.how] or 0) + 1 end
    local parts = {}
    for _, how in ipairs({ "zone", "roster", "block", "boss" }) do
        if counts[how] then parts[#parts + 1] = counts[how] .. " by " .. how end
    end

    print(string.format("%-14s %3d  (%s)%s", raid.key, #list, table.concat(parts, ", "),
        #missing > 0 and ("   MISSING: " .. table.concat(missing, ", ")) or ""))
end
print("total: " .. total)

-- Binary mode: text mode on Windows would write CRLF, and the repo requires
-- Unix line endings for Lua.
local out = assert(io.open(outPath, "wb"))
out:write([[
-- Bundled TBC raid creature table. Pure data, no logic.
--
-- AUTO GENERATED. Regenerate with:
--   luajit scripts/generate-mobs.lua <Questie tbcNpcDB.lua> <this file>
--
-- Names and ids come from Questie's TBC creature database, which ships for the
-- same client this addon targets, so every name is the name the game reports.
-- Raid membership is established from spawn data where it exists, from another
-- addon's roster where a raid summons its creatures, and from a contiguous id
-- block where neither is available. See the generator for which applies where.
--
-- This table only feeds the search box. A mob missing from it can still be
-- ruled by typing its name, so a gap costs a suggestion and nothing more.
local MFD = _G.MarkedForDeath or {}

MFD.Data = MFD.Data or {}

-- [npcID] = { name, instanceKey }
MFD.Data.Mobs = {
]])

for _, raid in ipairs(RAIDS) do
    local list = byRaid[raid.key]
    if #list > 0 then
        out:write(string.format("\n    -- %s (%d)\n", raid.label, #list))
        for _, entry in ipairs(list) do
            local name = npcs[entry.id][NAME]:gsub("\\", "\\\\"):gsub('"', '\\"')
            out:write(string.format('    [%d] = { "%s", "%s" },\n', entry.id, name, raid.key))
        end
    end
end

out:write("}\n\n_G.MarkedForDeath = MFD\n")
out:close()

print()
print("wrote " .. outPath)
