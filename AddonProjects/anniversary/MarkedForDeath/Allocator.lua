-- The allocator. Given what we can see, what the rules say and who owns which
-- seat, decide which icon goes on which mob.
--
-- This function is pure and its result depends only on its arguments, never on
-- table iteration order or on the order mobs were sighted. That property is
-- what removes the nameplate-arrival dependency that scrambles priority in
-- other addons, and it is what lets a backup marker agree with the lead
-- without negotiating. This file must never call a WoW API.
local MFD = _G.MarkedForDeath or {}

MFD.Allocator = MFD.Allocator or {}
local Allocator = MFD.Allocator

-- Returns the icon of the lowest-ordinal seat of intent that is both free and
-- owned, or nil. A seat whose owner is false exists but nobody in the raid can
-- perform it, so it is not usable.
local function takeSeat(seats, intent, usedIcons)
    local records = seats.byIntent[intent]
    if not records then
        return nil
    end

    for _, record in ipairs(records) do
        if not usedIcons[record.icon] and record.owner then
            return record.icon, record.owner
        end
    end

    return nil
end

-- Takes:
--   candidates    array of { key, npcID }
--   rulesByNpcID  { [npcID] = { intent, rank, fallback, maxCount } }
--   seats         the table returned by MFD.Seats.Resolve
--   locked        { [key] = icon } or nil, assignments frozen at combat start
--
-- Returns { list = array of { key, icon, intent, owner }, byKey = { [key] = icon } }.
-- Has no side effects and does not mutate any argument.
function Allocator.Compute(candidates, rulesByNpcID, seats, locked)
    locked = locked or {}

    local usedIcons, countByNpcID = {}, {}
    local list, byKey = {}, {}

    local byKeyCandidate = {}
    for _, candidate in ipairs(candidates) do
        byKeyCandidate[candidate.key] = candidate
    end

    local function record(key, icon, intent, owner, npcID)
        usedIcons[icon] = true
        countByNpcID[npcID] = (countByNpcID[npcID] or 0) + 1
        byKey[key] = icon
        list[#list + 1] = {
            key = key,
            icon = icon,
            intent = intent,
            owner = type(owner) == "string" and owner or nil,
        }
    end

    -- Locks first, so a frozen assignment keeps its icon and its seat even when
    -- a better mob has since walked into range.
    for _, key in ipairs(MFD.H.SortedKeys(locked)) do
        local candidate = byKeyCandidate[key]
        local icon = locked[key]
        local seat = seats.byIcon[icon]
        if candidate and seat and not usedIcons[icon] then
            local rule = rulesByNpcID[candidate.npcID]
            record(key, icon, rule and rule.intent or seat.intent, seat.owner, candidate.npcID)
        end
    end

    -- Everything else, in priority order. The key tiebreak makes the sort total
    -- so two clients never disagree on a tie.
    local eligible = {}
    for _, candidate in ipairs(candidates) do
        local rule = rulesByNpcID[candidate.npcID]
        if rule and rule.intent ~= "IGNORE" and not byKey[candidate.key] then
            eligible[#eligible + 1] = { candidate = candidate, rule = rule }
        end
    end

    table.sort(eligible, function(a, b)
        if a.rule.rank ~= b.rule.rank then
            return a.rule.rank < b.rule.rank
        end
        return a.candidate.key < b.candidate.key
    end)

    for _, entry in ipairs(eligible) do
        local candidate, rule = entry.candidate, entry.rule
        local used = countByNpcID[candidate.npcID] or 0

        if not rule.maxCount or used < rule.maxCount then
            local icon, owner = takeSeat(seats, rule.intent, usedIcons)
            local intent = rule.intent

            if not icon and rule.fallback then
                icon, owner = takeSeat(seats, rule.fallback, usedIcons)
                intent = rule.fallback
            end

            if icon then
                record(candidate.key, icon, intent, owner, candidate.npcID)
            end
        end
    end

    return { list = list, byKey = byKey }
end

_G.MarkedForDeath = MFD
