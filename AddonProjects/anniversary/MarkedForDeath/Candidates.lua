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

-- Returns { [key] = unitToken } for entries whose stored token STILL refers to
-- that same mob. guidOf(unit) returns a unit's current GUID.
--
-- Unit tokens are aliases, not identities. "mouseover" and "target" point at
-- whatever the player is currently pointing at, and even nameplate tokens are
-- recycled as mobs die and spawn. Acting on a stored token without
-- re-validating it stamps icons onto the wrong creatures, which is precisely
-- what happened before this existed. Nothing may apply an icon except through
-- this function.
function Candidates.ActionableUnits(set, guidOf)
    local units = {}

    for _, key in ipairs(MFD.H.SortedKeys(set)) do
        local entry = set[key]
        if entry.unit then
            local guid = guidOf(entry.unit)
            if guid and MFD.H.KeyFromGUID(guid) == key then
                units[key] = entry.unit
            end
        end
    end

    return units
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

    -- Learn the mob the first time it is seen, so anything the bundled
    -- database missed becomes searchable rather than being unreachable forever.
    -- The creature type is recorded here because it is only readable while the
    -- unit is in front of us, and it is what lets a rule warn that its crowd
    -- control cannot land on this mob.
    if MFD.db and not MFD.db.learnedMobs[npcID] then
        MFD.Learned.Record(MFD.db, npcID, UnitName(unit), GetRealZoneText(), time(),
            UnitCreatureType and UnitCreatureType(unit) or nil)
    end

    return key
end

MFD.Learned = MFD.Learned or {}

-- Records a sighting so the mob becomes searchable even when the bundled
-- database missed it. Mutates db.learnedMobs and nothing else.
-- Incomplete observations are dropped rather than stored half-formed.
function MFD.Learned.Record(db, npcID, name, zone, now, creatureType)
    if type(npcID) ~= "number" or type(name) ~= "string" or name == "" then
        return
    end

    db.learnedMobs[npcID] = {
        name = name,
        zone = zone,
        seenAt = now,
        creatureType = creatureType,
    }
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
