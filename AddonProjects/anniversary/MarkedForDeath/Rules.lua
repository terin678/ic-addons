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

-- Returns the merged rules for the current instance as { [npcID] = rule }.
-- Task 7 replaces this with the real instance-aware, comms-merged lookup.
function Rules.Active()
    return Rules.activeByNpcID or {}
end

_G.MarkedForDeath = MFD
