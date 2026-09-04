-- The allocator. Given what we can see, what the rules say and who owns which
-- role, decide which icon goes on which mob.
--
-- This function is pure and its result depends only on its arguments, never on
-- table iteration order or on the order mobs were sighted. That property is
-- what removes the nameplate-arrival dependency that scrambles priority in
-- other addons, and it is what lets a backup marker agree with the lead
-- without negotiating. This file must never call a WoW API.
local MFD = _G.MarkedForDeath or {}

MFD.Allocator = MFD.Allocator or {}
local Allocator = MFD.Allocator

-- Returns the icon of the lowest-ordinal role of intent that is both free and
-- owned, or nil. A role whose owner is false exists but nobody in the raid can
-- perform it, so it is not usable.
-- skipLastResort holds back roles flagged as icons of last resort, so that
-- borrowed crowd control icons get spent before them. Only meaningful when
-- reuse is on; with it off there is nothing to come first and the flag is
-- ignored, leaving a last-resort role as an ordinary one.
local function takeRole(roles, intent, usedIcons, skipLastResort)
    local records = roles.byIntent[intent]
    if not records then
        return nil
    end

    for _, record in ipairs(records) do
        if not usedIcons[record.icon] and record.owner
            and not (skipLastResort and record.isLastResort) then
            return record.icon, record.owner
        end
    end

    return nil
end

-- Takes:
--   candidates    array of { key, npcID }
--   rulesByNpcID  { [npcID] = { intent, rank, fallback, maxCount } }
--   roles         the table returned by MFD.Roles.Resolve
--   locked        { [key] = icon } or nil, assignments frozen at combat start
--   manualKeys    { [key] = true } or nil, locks a person placed by hand
--
-- Returns { list = array of { key, icon, intent, owner }, byKey = { [key] = icon } }.
-- Has no side effects and does not mutate any argument.
function Allocator.Compute(candidates, rulesByNpcID, roles, locked, allowIconReuse, manualKeys)
    locked = locked or {}
    manualKeys = manualKeys or {}

    local usedIcons, countByNpcID = {}, {}
    local list, byKey = {}, {}

    local byKeyCandidate = {}
    for _, candidate in ipairs(candidates) do
        byKeyCandidate[candidate.key] = candidate
    end

    local function record(key, icon, intent, owner, npcID, isBorrowed)
        usedIcons[icon] = true
        countByNpcID[npcID] = (countByNpcID[npcID] or 0) + 1
        byKey[key] = icon
        list[#list + 1] = {
            key = key,
            icon = icon,
            intent = intent,
            owner = type(owner) == "string" and owner or nil,
            isBorrowed = isBorrowed or nil,
        }
    end

    -- Locks first, so a frozen assignment keeps its icon and its role even when
    -- a better mob has since walked into range.
    for _, key in ipairs(MFD.H.SortedKeys(locked)) do
        local candidate = byKeyCandidate[key]
        local icon = locked[key]
        local role = roles.byIcon[icon]
        local isManual = manualKeys[key] == true

        -- A hand-placed icon holds its mob whether or not the plan has a role
        -- for that icon. Dropping it here would leave the mob eligible, the
        -- allocator would want a different icon on it, and the addon would
        -- spend the pull arguing with the tank who marked it.
        if candidate and (role or isManual) and not usedIcons[icon] then
            local rule = rulesByNpcID[candidate.npcID]
            local intent, owner

            if isManual then
                -- Whoever placed it meant the icon, not the mob's rule. Moon on
                -- something the rules call a kill is a sheep call, and reading
                -- it as a kill would announce the wrong job to the wrong person.
                intent = role and role.intent or "MANUAL"
                owner = role and role.owner
            else
                intent = rule and rule.intent or role.intent
                owner = role.owner
            end

            record(key, icon, intent, owner, candidate.npcID)
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

    -- A mob you can actually see outranks one that has walked off, whatever
    -- the rules say. A patrol pacing the edge of nameplate range would
    -- otherwise hold Skull hostage from the pack you are about to pull, while
    -- being untouchable itself. It keeps its icon only when nothing else
    -- wants it, so a nameplate that merely flickered causes no churn.
    table.sort(eligible, function(a, b)
        local aLost = a.candidate.isLost and 1 or 0
        local bLost = b.candidate.isLost and 1 or 0
        if aLost ~= bLost then
            return aLost < bLost
        end
        if a.rule.rank ~= b.rule.rank then
            return a.rule.rank < b.rule.rank
        end
        return a.candidate.key < b.candidate.key
    end)

    for _, entry in ipairs(eligible) do
        local candidate, rule = entry.candidate, entry.rule
        local used = countByNpcID[candidate.npcID] or 0

        if not rule.maxCount or used < rule.maxCount then
            local icon, owner = takeRole(roles, rule.intent, usedIcons, allowIconReuse)
            local intent = rule.intent

            if not icon and rule.fallback then
                icon, owner = takeRole(roles, rule.fallback, usedIcons, allowIconReuse)
                intent = rule.fallback
            end

            if icon then
                record(candidate.key, icon, intent, owner, candidate.npcID)
            end
        end
    end

    -- Second pass: hand any icon still unused to a mob that got nothing.
    --
    -- This runs only after every mob has been offered its proper role, which
    -- is what makes it safe: an icon is only spare here because nothing in
    -- this pack needs it. A crowd control target always wins its own icon in
    -- the pass above, however low its priority, so borrowing can never take
    -- Moon away from a mob somebody is about to sheep.
    if allowIconReuse then
        -- Ordered so the best-placed spare goes first: sheep role one before
        -- sheep role two, and anything flagged last resort after everything
        -- else. That is what puts Circle behind a spare Moon.
        local spare = {}
        for icon, role in pairs(roles.byIcon) do
            if not usedIcons[icon] then
                spare[#spare + 1] = { icon = icon, role = role }
            end
        end

        table.sort(spare, function(a, b)
            local aLast = a.role.isLastResort and 1 or 0
            local bLast = b.role.isLastResort and 1 or 0
            if aLast ~= bLast then
                return aLast < bLast
            end
            if (a.role.ordinal or 0) ~= (b.role.ordinal or 0) then
                return (a.role.ordinal or 0) < (b.role.ordinal or 0)
            end
            -- Descending icon index is the traditional marking order: skull,
            -- cross, square, moon, triangle, diamond, circle, star. Following
            -- it means the borrowed icons come out in the order a raid leader
            -- would reach for them anyway.
            return a.icon > b.icon
        end)

        local nextSpare = 1
        for _, entry in ipairs(eligible) do
            if nextSpare > #spare then
                break
            end
            local candidate, rule = entry.candidate, entry.rule
            local used = countByNpcID[candidate.npcID] or 0
            if not byKey[candidate.key] and (not rule.maxCount or used < rule.maxCount) then
                -- Reported as a kill: the icon carries no crowd control
                -- meaning here, and saying otherwise would be a lie to whoever
                -- reads the assignment panel.
                record(candidate.key, spare[nextSpare].icon, "KILL", nil, candidate.npcID, true)
                nextSpare = nextSpare + 1
            end
        end
    end

    return { list = list, byKey = byKey }
end

-- Returns the candidates whose rule asks for crowd control but which got no
-- icon, as an array of { key, npcID, intent } sorted by key. Pure.
--
-- These are the "we did not know we needed a sheep" cases: a mob that walked
-- in late, or one that was outranked while every role was taken. The marker
-- uses this to reclaim a borrowed icon and shout about it.
function Allocator.UnmetCrowdControl(candidates, rulesByNpcID, byKey)
    local unmet = {}

    for _, candidate in ipairs(candidates) do
        if not byKey[candidate.key] then
            local rule = rulesByNpcID[candidate.npcID]
            local intent = rule and rule.intent
            local def = intent and MFD.Roles.INTENTS[intent]
            if def and def.classes then
                unmet[#unmet + 1] = { key = candidate.key, npcID = candidate.npcID, intent = intent }
            end
        end
    end

    table.sort(unmet, function(a, b) return a.key < b.key end)
    return unmet
end

_G.MarkedForDeath = MFD
