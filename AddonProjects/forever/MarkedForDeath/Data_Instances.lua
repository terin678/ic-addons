local addonName, ns = ...

--[[
Data_Instances: every Forever dungeon and raid this addon knows, by instance id, with the
encounter ids known for it. Pure: no client call, ever.

Owned by lane E (data and capture).

The instance id is `select(8, GetInstanceInfo())`, the key a plan and the rules are filed
under ("i:<id>"). Everything between the GENERATED markers is rewritten by
scripts/mfd-forever-capture.lua when it merges capture exports, so edit those blocks by
hand only in the same format, one entry per line.

    Instances.list                  [instanceID] = { name, kind, size, forever, src, encounters }
    Instances.pending               { name, kind, size, opens }: known by name, no id yet
    Instances.DIFFICULTIES          [difficultyID] = { name, kind, size }

    Instances.Key(instanceID)       -> "i:<id>", or "open" for the open world (0 or nil)
    Instances.IdFromKey(key)        -> the id in "i:<id>", else nil
    Instances.Get(id, list)         -> the entry, or nil for an id nobody listed
    Instances.Name(id, list)        -> its name, or nil
    Instances.Encounter(encID, list) -> name, instanceID; nil for an unknown encounter
    Instances.FindByName(name, list, pending) -> id or nil, then the pending entry or nil
    Instances.Difficulty(diffID)    -> the DIFFICULTIES row, or nil
    Instances.DifficultyFor(kind, size) -> the difficulty id expected for that kind and size

Every lookup takes the table it reads as its last argument and falls back to the bundled
one, so a case can hand in its own.

Where the ids come from (facts only; no code, file or table layout is copied):
  fdj      ForeverDungeonJournal 1.6.6 (instance-to-dungeon map; no licence stated, so
           treated as all rights reserved: ids and names only)
  questie  QuestieDB 1.0.10 Forever build, instance-to-area table (GPLv3 for new work;
           ids and names only)
  dbcache  the Forever client's own hotfix cache: DungeonEncounter rows (game data)
  capture  /mfd capture in game, merged by scripts/mfd-forever-capture.lua
Barrow Deeps, Hyjal Summit and Onyxia's Lair open on 2026-12-09 and have no id on disk
anywhere; they wait in `pending` until a capture names them. Barrow Deeps' size is the
one the raid was told to expect; the capture's GetInstanceInfo size replaces it.
]]

ns.Instances = ns.Instances or {}
local Instances = ns.Instances

-- What GetInstanceInfo's third return means, for the sizes Forever runs. These are the
-- client family's DifficultyID values; a capture records the id the Forever client
-- actually reports and the merge script says so when one differs.
Instances.DIFFICULTIES = {
    [1] = { name = "Normal", kind = "party", size = 5 },
    [3] = { name = "10 Player", kind = "raid", size = 10 },
    [148] = { name = "20 Player", kind = "raid", size = 20 },
    [9] = { name = "40 Player", kind = "raid", size = 40 },
}

-- BEGIN GENERATED instances
Instances.list = {
    [33] = { name = "Shadowfang Keep", kind = "party", size = 5, src = "fdj" },
    [34] = { name = "The Stockade", kind = "party", size = 5, src = "fdj" },
    [36] = { name = "The Deadmines", kind = "party", size = 5, src = "fdj" },
    [43] = { name = "Wailing Caverns", kind = "party", size = 5, src = "fdj" },
    [47] = { name = "Razorfen Kraul", kind = "party", size = 5, src = "fdj" },
    [48] = { name = "Blackfathom Deeps", kind = "party", size = 5, src = "fdj" },
    [70] = { name = "Uldaman", kind = "party", size = 5, src = "fdj" },
    [90] = { name = "Gnomeregan", kind = "party", size = 5, src = "fdj" },
    [109] = { name = "Sunken Temple", kind = "party", size = 5, src = "fdj" },
    [129] = { name = "Razorfen Downs", kind = "party", size = 5, src = "fdj" },
    [189] = { name = "Scarlet Monastery", kind = "party", size = 5, src = "fdj" },
    [209] = { name = "Zul'Farrak", kind = "party", size = 5, src = "fdj" },
    [229] = { name = "Blackrock Spire", kind = "party", size = 5, src = "questie" },
    [230] = { name = "Blackrock Depths", kind = "party", size = 5, src = "fdj" },
    [289] = { name = "Scholomance", kind = "party", size = 5, src = "fdj" },
    [329] = { name = "Stratholme", kind = "party", size = 5, src = "questie" },
    [349] = { name = "Maraudon", kind = "party", size = 5, src = "fdj" },
    [389] = { name = "Ragefire Chasm", kind = "party", size = 5, src = "fdj" },
    [429] = { name = "Dire Maul", kind = "party", size = 5, src = "questie", encounters = { [349] = "Immol'thar" } },
    [2791] = { name = "Storm Cliffs", kind = "unknown", forever = true, src = "questie" },
    [2804] = { name = "The Crystal Vale", kind = "unknown", forever = true, src = "questie" },
    [2807] = { name = "Burning of Andorhal", kind = "unknown", forever = true, src = "questie" },
    [2817] = { name = "Starfall Barrow Den", kind = "unknown", forever = true, src = "questie" },
    [2902] = { name = "The Scarab Dais", kind = "unknown", forever = true, src = "questie" },
    [2921] = { name = "Naxxramas", kind = "unknown", forever = true, src = "questie" },
    [2959] = { name = "City of Dalaran", kind = "party", size = 5, forever = true, src = "fdj", encounters = { [3303] = "Shade of the Archmage" } },
    [2970] = { kind = "unknown", forever = true, src = "dbcache", encounters = { [3479] = "Min'loth the Serpent" } },
    [2997] = { name = "Darkspear Islands", kind = "unknown", forever = true, src = "questie" },
    [2998] = { name = "Excavation Site: Wetlands", kind = "party", size = 5, forever = true, src = "fdj" },
    [2999] = { name = "Ruins of Lordaeron", kind = "party", size = 5, forever = true, src = "fdj", encounters = { [3354] = "Rath'mael", [3411] = "Viktor the Vile" } },
    [3005] = { name = "Battle for Gilneas", kind = "unknown", forever = true, src = "questie" },
    [3065] = { name = "Hall of Thanes", kind = "party", size = 5, forever = true, src = "fdj" },
    [3109] = { name = "Manor Mistmantle", kind = "unknown", forever = true, src = "questie" },
}
-- END GENERATED instances

-- BEGIN GENERATED pending
Instances.pending = {
    { name = "Barrow Deeps", kind = "raid", size = 10, opens = "2026-12-09" },
    { name = "Hyjal Summit", kind = "raid", size = 20, opens = "2026-12-09" },
    { name = "Onyxia's Lair", kind = "raid", size = 40, opens = "2026-12-09" },
    { name = "Alcaz Prison", kind = "party", size = 5 },
    { name = "Blackmaw Hold", kind = "party", size = 5 },
    { name = "Krol'dok Stronghold", kind = "party", size = 5 },
    { name = "Shaper's Terrace", kind = "party", size = 5 },
    { name = "The Drowned City", kind = "party", size = 5 },
}
-- END GENERATED pending

local OPEN_WORLD = "open"   -- the plan and rules key outside any instance

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------

-- The key a plan and the rules are filed under. 0 is what GetInstanceInfo reports in the
-- open world, so 0 and nil are both "open".
function Instances.Key(instanceID)
    if type(instanceID) ~= "number" or instanceID <= 0 then return OPEN_WORLD end
    return "i:" .. instanceID
end

function Instances.IdFromKey(key)
    if type(key) ~= "string" then return nil end
    local id = tonumber(key:match("^i:(%d+)$"))
    return id
end

--------------------------------------------------------------------------------
-- Lookups
--------------------------------------------------------------------------------

function Instances.Get(id, list)
    list = list or Instances.list
    if type(id) ~= "number" then return nil end
    return list[id]
end

function Instances.Name(id, list)
    local entry = Instances.Get(id, list)
    return entry and entry.name or nil
end

-- name, instanceID for an encounter id; nil when no instance lists it.
function Instances.Encounter(encounterID, list)
    list = list or Instances.list
    if type(encounterID) ~= "number" then return nil end
    for id, entry in pairs(list) do
        local name = entry.encounters and entry.encounters[encounterID]
        if name then return name, id end
    end
    return nil
end

-- Case-insensitive. Returns the id of a listed instance with that name, else nil and the
-- pending entry with that name (or nil).
function Instances.FindByName(name, list, pending)
    if type(name) ~= "string" or name == "" then return nil, nil end
    list = list or Instances.list
    pending = pending or Instances.pending
    local want = name:lower()
    local found
    for id, entry in pairs(list) do
        if entry.name and entry.name:lower() == want and (found == nil or id < found) then
            found = id
        end
    end
    if found then return found, nil end
    for _, entry in ipairs(pending) do
        if entry.name:lower() == want then return nil, entry end
    end
    return nil, nil
end

function Instances.Difficulty(difficultyID)
    if type(difficultyID) ~= "number" then return nil end
    return Instances.DIFFICULTIES[difficultyID]
end

-- The difficulty id expected for a kind ("party" or "raid") and a size, or nil.
function Instances.DifficultyFor(kind, size)
    local best
    for id, row in pairs(Instances.DIFFICULTIES) do
        if row.kind == kind and row.size == size and (best == nil or id < best) then best = id end
    end
    return best
end
