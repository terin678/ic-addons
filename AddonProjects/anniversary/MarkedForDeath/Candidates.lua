-- The live set of observable hostile units.
--
-- The set-manipulation functions are pure so they can be tested headlessly.
-- Only Init and the event handler touch the client, and neither runs at file
-- scope.
local MFD = _G.MarkedForDeath or {}

MFD.Candidates = MFD.Candidates or {}
local Candidates = MFD.Candidates

-- Seconds a unit stays in the set after its nameplate disappears. A nameplate
-- that flickers as the camera turns would otherwise churn the pack and cause
-- the allocator to reshuffle icons for no reason.
Candidates.GRACE_SECONDS = 3

local UnitGUID = UnitGUID
local UnitIsEnemy = UnitIsEnemy
local UnitIsDead = UnitIsDead

Candidates.set = {}

-- Records or refreshes a unit in set. Mutates set. Reobserving a unit that had
-- been lost restores its unit token and clears the loss stamp, so it will not
-- be pruned.
function Candidates.Observe(set, key, npcID, unit, now)
    local entry = set[key]
    if not entry then
        entry = { key = key, npcID = npcID }
        set[key] = entry
    end

    entry.unit = unit
    entry.seenAt = now
    entry.lostAt = nil
end

-- Marks a unit as no longer visible. Mutates set. The entry is kept until
-- Prune decides the grace window has passed.
function Candidates.Lose(set, key, now)
    local entry = set[key]
    if not entry then
        return
    end

    entry.unit = nil
    entry.lostAt = now
end

-- Removes entries lost longer than grace seconds ago. Mutates set. Returns an
-- array of the removed keys so the caller can release their seats.
function Candidates.Prune(set, now, grace)
    local removed = {}

    for _, key in ipairs(MFD.H.SortedKeys(set)) do
        local entry = set[key]
        if entry.lostAt and (entry.lostAt + grace) < now then
            removed[#removed + 1] = key
            set[key] = nil
        end
    end

    return removed
end

-- Returns the set as an array of { key, npcID } sorted by key ascending. The
-- allocator sorts again by rank, but starting from a deterministic order means
-- two clients with the same set always produce the same result.
function Candidates.ToList(set)
    local list = {}

    for _, key in ipairs(MFD.H.SortedKeys(set)) do
        list[#list + 1] = { key = key, npcID = set[key].npcID }
    end

    return list
end

-- Reads a unit token and records it if it is a live hostile creature. Returns
-- the key it recorded, or nil. Touches the client, so it is never called at
-- file scope.
function Candidates.ObserveUnit(unit, now)
    if not unit or not UnitGUID then
        return nil
    end

    local guid = UnitGUID(unit)
    if not guid then
        return nil
    end

    local key = MFD.H.KeyFromGUID(guid)
    if not key then
        return nil
    end

    if UnitIsDead and UnitIsDead(unit) then
        return nil
    end

    if UnitIsEnemy and not UnitIsEnemy("player", unit) then
        return nil
    end

    local npcID = MFD.H.NpcIDFromKey(key)
    Candidates.Observe(Candidates.set, key, npcID, unit, now)
    return key
end

local frame

MFD.RegisterInit(function()
    frame = CreateFrame("Frame")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:RegisterEvent("UNIT_TARGET")
    frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")

    frame:SetScript("OnEvent", function(_, event, unit)
        local now = GetTime()

        if event == "NAME_PLATE_UNIT_ADDED" then
            Candidates.ObserveUnit(unit, now)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            local guid = UnitGUID(unit)
            local key = guid and MFD.H.KeyFromGUID(guid)
            if key then
                Candidates.Lose(Candidates.set, key, now)
            end
        elseif event == "UNIT_TARGET" then
            Candidates.ObserveUnit(unit .. "target", now)
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            Candidates.ObserveUnit("mouseover", now)
        elseif event == "PLAYER_TARGET_CHANGED" then
            Candidates.ObserveUnit("target", now)
        end
    end)
end)

_G.MarkedForDeath = MFD
