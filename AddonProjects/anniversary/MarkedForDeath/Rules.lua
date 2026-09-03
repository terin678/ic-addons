-- Rule storage, multi-contributor merging and ranked lookup. This file must
-- never call a WoW API.
--
-- Rules carry an explicit rank rather than deriving priority from list
-- position, because two contributors' orderings for one instance have no
-- defined interleaving. Positions cannot merge; ranks sort.
local MFD = _G.MarkedForDeath or {}

MFD.Rules = MFD.Rules or {}
local Rules = MFD.Rules

-- Gap between adjacent ranks, so inserting between two rules rarely needs a
-- full renumber.
Rules.RANK_STEP = 10

-- Takes an array of { owner, rules = { [instanceKey] = array of rule } } and
-- the designated Raid Lead's name. Returns
-- { [instanceKey] = { [npcID] = rule } } where every rule carries an owner
-- field naming the contributor it came from.
--
-- Conflict resolution: the lead's rule wins outright, including its rank.
-- Otherwise the lowest contributor name ascending wins. Both are deterministic,
-- so every client computes the same table from the same inputs regardless of
-- the order contributions arrived in.
function Rules.Merge(contributions, leadName)
    local byOwner = {}
    for _, c in ipairs(contributions) do
        byOwner[c.owner] = c
    end

    local owners = MFD.H.SortedKeys(byOwner)
    local merged = {}

    local function absorb(contribution)
        for _, instanceKey in ipairs(MFD.H.SortedKeys(contribution.rules)) do
            merged[instanceKey] = merged[instanceKey] or {}
            for _, rule in ipairs(contribution.rules[instanceKey]) do
                if merged[instanceKey][rule.npcID] == nil then
                    local copy = MFD.H.DeepCopy(rule)
                    copy.owner = contribution.owner
                    merged[instanceKey][rule.npcID] = copy
                end
            end
        end
    end

    -- The lead goes first, so its rules claim every npcID they cover and later
    -- contributors can only fill gaps.
    if byOwner[leadName] then
        absorb(byOwner[leadName])
    end

    for _, owner in ipairs(owners) do
        if owner ~= leadName then
            absorb(byOwner[owner])
        end
    end

    return merged
end

-- Takes { [npcID] = rule }. Returns an array sorted by rank ascending, then
-- npcID ascending. The npcID tiebreak is what keeps two clients in agreement
-- when two rules share a rank.
function Rules.Ranked(byNpcID)
    local list = {}
    for _, npcID in ipairs(MFD.H.SortedKeys(byNpcID)) do
        list[#list + 1] = byNpcID[npcID]
    end

    table.sort(list, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.npcID < b.npcID
    end)

    return list
end

-- Returns the rank a newly appended rule should take.
function Rules.NextRank(list)
    local highest = 0
    for _, rule in ipairs(list) do
        if rule.rank > highest then
            highest = rule.rank
        end
    end
    return highest + Rules.RANK_STEP
end

-- Moves list[index] by delta places and rewrites every rank to a clean
-- multiple of RANK_STEP. Mutates and returns list. Out-of-range moves are a
-- no-op, so the caller can wire arrow buttons without bounds checks.
function Rules.Reorder(list, index, delta)
    local target = index + delta
    if target < 1 or target > #list or index < 1 or index > #list then
        return list
    end

    local moved = table.remove(list, index)
    table.insert(list, target, moved)

    for i, rule in ipairs(list) do
        rule.rank = i * Rules.RANK_STEP
    end

    return list
end

-- TBC raid instance map ids. Verify each against the live client with
-- /mfd where before trusting it; these were compiled from documentation, not
-- read off this client.
Rules.INSTANCE_KEYS = {
    [532] = "KARAZHAN",
    [565] = "GRUUL",
    [544] = "MAGTHERIDON",
    [548] = "SERPENTSHRINE",
    [550] = "TEMPESTKEEP",
    [534] = "HYJAL",
    [564] = "BLACKTEMPLE",
    [568] = "ZULAMAN",
    [580] = "SUNWELL",
}

-- Display names as GetRealZoneText reports them, so learned mobs (which store
-- a zone name, not a key) can be filtered by instance in search. Verify these
-- against the client the same way as the map ids.
Rules.INSTANCE_ZONE_NAMES = {
    KARAZHAN      = "Karazhan",
    GRUUL         = "Gruul's Lair",
    MAGTHERIDON   = "Magtheridon's Lair",
    SERPENTSHRINE = "Serpentshrine Cavern",
    TEMPESTKEEP   = "Tempest Keep",
    HYJAL         = "Hyjal Summit",
    BLACKTEMPLE   = "Black Temple",
    ZULAMAN       = "Zul'Aman",
    SUNWELL       = "Sunwell Plateau",
}

-- Takes an instance map id. Returns the key rules are filed under.
--
-- TBC raids get stable named keys so rule sets read well and share cleanly
-- between players. Every other zone falls back to its map id, so the addon is
-- usable in heroics and in the open world instead of being inert everywhere
-- but nine raids.
function Rules.InstanceKeyFor(instanceMapID)
    if type(instanceMapID) ~= "number" then
        return nil
    end

    return Rules.INSTANCE_KEYS[instanceMapID] or ("MAP" .. instanceMapID)
end

-- Set by the zone handler in Core. nil before the first zone event.
Rules.currentInstanceKey = nil
Rules.merged = {}

-- Recomputes the merged rule set from every contributor and caches it.
--
-- Never writes to saved variables: merged rules are session state, so a
-- contributor's rules can never alter another player's stored configuration.
function Rules.SetContributions(contributions, leadName)
    Rules.merged = Rules.Merge(contributions, leadName)
end

-- Rebuilds the merged set from just this player's own rules. Task 9 replaces
-- the caller with one that folds in every contributor's rules from the channel.
function Rules.RefreshLocal(db, playerName)
    Rules.SetContributions({ { owner = playerName, rules = db.rules } }, db.designatedLead.name)
end

local EMPTY = {}

-- Returns { [npcID] = rule } for the zone the player is currently in, or an
-- empty table when there are none. The allocator consumes this directly.
function Rules.Active()
    local key = Rules.currentInstanceKey
    if not key then
        return EMPTY
    end
    return Rules.merged[key] or EMPTY
end

-- Wire and export format. One rule per line:
--   instanceKey;npcID;intent;rank;fallback;maxCount;name
-- Fields are positional, name goes last because it is the only one that may
-- contain spaces. Empty means absent. A hand-rolled format is used rather than
-- a serialisation library because rule sets are small enough that compression
-- is not worth a dependency.
local FIELD = ";"
local LINE = "\n"

-- Takes { [instanceKey] = array of rule }. Returns a string. Iteration goes
-- through sorted keys so the same rules always serialise identically, which is
-- what makes the hash usable for version gating.
function Rules.Serialize(rulesByInstance)
    local lines = {}

    for _, instanceKey in ipairs(MFD.H.SortedKeys(rulesByInstance)) do
        for _, rule in ipairs(rulesByInstance[instanceKey]) do
            local safeName = string.gsub(rule.name or "", "[" .. FIELD .. LINE .. "]", " ")
            lines[#lines + 1] = table.concat({
                instanceKey,
                rule.npcID,
                rule.intent,
                rule.rank,
                rule.fallback or "",
                rule.maxCount or "",
                safeName,
            }, FIELD)
        end
    end

    return table.concat(lines, LINE)
end

-- Takes a serialised string. Returns { [instanceKey] = array of rule }, or nil
-- and a reason. A malformed line aborts the whole parse rather than silently
-- importing a partial rule set.
function Rules.Deserialize(str)
    if type(str) ~= "string" then
        return nil, "not a string"
    end

    local out = {}
    local lineNumber = 0

    for line in string.gmatch(str, "[^" .. LINE .. "]+") do
        lineNumber = lineNumber + 1

        local instanceKey, npcID, intent, rank, fallback, maxCount, name =
            string.match(line, "^([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);(.*)$")

        if not instanceKey or instanceKey == "" then
            return nil, "line " .. lineNumber .. " is not a rule"
        end

        if not tonumber(npcID) or not tonumber(rank) then
            return nil, "line " .. lineNumber .. " has a bad npc id or rank"
        end

        if not MFD.Seats.INTENTS[intent] then
            return nil, "line " .. lineNumber .. " has unknown intent '" .. tostring(intent) .. "'"
        end

        out[instanceKey] = out[instanceKey] or {}
        table.insert(out[instanceKey], {
            npcID = tonumber(npcID),
            intent = intent,
            rank = tonumber(rank),
            fallback = fallback ~= "" and fallback or nil,
            maxCount = tonumber(maxCount) or nil,
            name = name ~= "" and name or nil,
        })
    end

    return out
end

-- A cheap content hash over the serialised form, used only to decide whether a
-- peer's rules changed. Not a security primitive.
function Rules.Hash(rulesByInstance)
    local payload = Rules.Serialize(rulesByInstance)
    local hash = 5381

    for i = 1, #payload do
        hash = (hash * 33 + string.byte(payload, i)) % 4294967296
    end

    return tostring(hash) .. ":" .. #payload
end

-- Recomputes db.rulesVersion after a local rule edit. The counter rises so a
-- peer can tell newer from merely different, and the hash lets it skip a
-- transfer when nothing actually changed.
function Rules.BumpVersion(db)
    local hash = Rules.Hash(db.rules)
    if db.rulesVersion.hash == hash then
        return
    end
    db.rulesVersion = { counter = (db.rulesVersion.counter or 0) + 1, hash = hash }
end

_G.MarkedForDeath = MFD
