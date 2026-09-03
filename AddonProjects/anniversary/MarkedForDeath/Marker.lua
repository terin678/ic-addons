-- Makes the client's actual raid target icons match the desired map.
--
-- ComputeDiff is pure and carries the defense brake, which is the difference
-- between an addon that restores a mark someone accidentally cleared and one
-- that will not stop fighting a human who is deliberately changing it.
local MFD = _G.MarkedForDeath or {}

MFD.Marker = MFD.Marker or {}
local Marker = MFD.Marker

local SetRaidTarget = SetRaidTarget
local GetRaidTargetIndex = GetRaidTargetIndex
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetCVar = GetCVar

-- maxActions and defenseLimit are counts. defenseWindow and tickInterval are
-- seconds.
Marker.LIMITS = {
    maxActions = 4,
    defenseLimit = 3,
    defenseWindow = 5,
    tickInterval = 0.2,
}

-- Assignments frozen at combat start, { [key] = icon }.
Marker.locked = {}

-- Keys this client has actually applied an icon to. Separating this from the
-- observed icons is what lets the brake tell "we marked it and someone wiped
-- it" apart from "this mob simply has no icon yet"; both read as 0.
Marker.placed = {}

-- Takes the desired map, the observed actual map, the set of keys we have
-- placed, a mutable defense counter table, the current time and the limits.
-- Returns { actions = array of { key, icon, isDefense }, yielded = array of key }.
--
-- Mutates defense: each re-application increments a counter inside a rolling
-- window, and once the limit is hit inside that window the key is yielded
-- rather than fought over. Sorted output keeps the result deterministic.
function Marker.ComputeDiff(desired, actual, placed, defense, now, limits)
    local actions, yielded = {}, {}

    for _, key in ipairs(MFD.H.SortedKeys(desired)) do
        local wanted = desired[key]
        local present = actual[key] or 0

        if present ~= wanted then
            -- Either we put an icon here and it is gone or changed, or someone
            -- else has put a different icon on it. Both mean we are contesting
            -- the mob rather than marking it for the first time.
            local isDefense = placed[key] == true or present ~= 0

            if not isDefense then
                actions[#actions + 1] = { key = key, icon = wanted, isDefense = false }
            else
                local entry = defense[key]
                if not entry or (entry.windowStart + limits.defenseWindow) < now then
                    entry = { count = 0, windowStart = now }
                    defense[key] = entry
                end

                if entry.count < limits.defenseLimit then
                    entry.count = entry.count + 1
                    actions[#actions + 1] = { key = key, icon = wanted, isDefense = true }
                else
                    yielded[#yielded + 1] = key
                end
            end
        end
    end

    while #actions > limits.maxActions do
        table.remove(actions)
    end

    return { actions = actions, yielded = yielded }
end

-- Returns whether the player may place raid icons, and a reason when they may
-- not. Marking needs raid leader or assistant; solo and parties are allowed.
function Marker:CanMark()
    if IsInRaid and IsInRaid() then
        if UnitIsGroupLeader("player") or (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) then
            return true, ""
        end
        return false, "you need raid assist to place icons"
    end

    return true, ""
end

-- Returns whether nameplate settings allow marking mobs the player is not
-- targeting, and a message describing the fix when they do not. Reading a CVar
-- can fail on an unexpected client build, so it is wrapped.
function Marker:CheckCvars()
    if not GetCVar then
        return true, ""
    end

    local ok, showEnemies = pcall(GetCVar, "nameplateShowEnemies")
    if not ok then
        return true, ""
    end

    if showEnemies ~= "1" then
        return false, "enemy nameplates are off, so mobs you are not targeting cannot be marked. Run /mfd fixcvars"
    end

    local okDist, distance = pcall(GetCVar, "nameplateMaxDistance")
    if okDist and tonumber(distance) and tonumber(distance) < 20 then
        return false, "nameplate distance is only " .. distance .. " yards, so packs will be marked late. Run /mfd fixcvars"
    end

    return true, ""
end

-- Temporary until Comms lands in Task 8.
MFD.Comms = MFD.Comms or { IsAuthority = function() return true end }

local defense = {}
local accumulator = 0
local hasReportedTickError = false

-- Builds the roster the seat resolver needs. Returns an array of
-- { name, class }. Reads client state, so it never runs at file scope.
function Marker.CurrentRoster()
    local roster = {}

    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            if name and class then
                roster[#roster + 1] = { name = name, class = class }
            end
        end
        return roster
    end

    local _, playerClass = UnitClass("player")
    roster[#roster + 1] = { name = UnitName("player"), class = playerClass }

    if IsInGroup and IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            local _, class = UnitClass(unit)
            local name = UnitName(unit)
            if name and class then
                roster[#roster + 1] = { name = name, class = class }
            end
        end
    end

    return roster
end

-- Returns { [key] = icon } for the units the client can currently read, plus
-- a { [key] = unitToken } map for applying icons.
local function readActual()
    local actual, units = {}, {}

    for key, entry in pairs(MFD.Candidates.set) do
        if entry.unit then
            units[key] = entry.unit
            actual[key] = GetRaidTargetIndex(entry.unit) or 0
        end
    end

    return actual, units
end

-- Recomputes the desired map from the current candidates, rules and seats.
function Marker:Desired()
    local seats = MFD.Seats.Resolve(MFD.db.seatPlan, Marker.CurrentRoster())
    local rules = MFD.Rules.Active and MFD.Rules.Active() or {}
    return MFD.Allocator.Compute(MFD.Candidates.ToList(MFD.Candidates.set), rules, seats, Marker.locked)
end

function Marker:Tick(elapsed)
    accumulator = accumulator + elapsed
    if accumulator < Marker.LIMITS.tickInterval then
        return
    end
    accumulator = 0

    if not MFD.db or not MFD.db.settings.isMarkingEnabled then
        return
    end

    local now = GetTime()

    for _, key in ipairs(MFD.Candidates.Prune(MFD.Candidates.set, now, MFD.Candidates.GRACE_SECONDS)) do
        Marker.locked[key] = nil
        Marker.placed[key] = nil
        defense[key] = nil
    end

    if not MFD.Comms:IsAuthority() then
        return
    end

    if not Marker:CanMark() then
        return
    end

    local desired = Marker:Desired()
    local actual, units = readActual()
    local diff = Marker.ComputeDiff(desired.byKey, actual, Marker.placed, defense, now, Marker.LIMITS)

    for _, action in ipairs(diff.actions) do
        local unit = units[action.key]
        if unit then
            SetRaidTarget(unit, action.icon)
            Marker.placed[action.key] = true
        end
    end

    for _, key in ipairs(diff.yielded) do
        MFD.Print("giving up on " .. key .. ", something keeps changing that icon")
        defense[key] = nil
        Marker.placed[key] = nil
    end

    Marker.lastDesired = desired
end

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")

    frame:SetScript("OnUpdate", function(_, elapsed)
        local ok, err = pcall(Marker.Tick, Marker, elapsed)
        if not ok and not hasReportedTickError then
            hasReportedTickError = true
            MFD.Error("marking tick failed, marking is now idle: " .. tostring(err))
        end
    end)

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Freeze the current map so nothing shifts under the raid mid-pull.
            local desired = Marker.lastDesired
            if desired then
                for key, icon in pairs(desired.byKey) do
                    Marker.locked[key] = icon
                end
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            wipe(Marker.locked)
            wipe(Marker.placed)
            if MFD.db and MFD.db.settings.isCvarWarnEnabled then
                local ok, message = Marker:CheckCvars()
                if not ok then
                    MFD.Error(message)
                end
            end
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
            if subEvent == "UNIT_DIED" then
                local key = destGUID and MFD.H.KeyFromGUID(destGUID)
                if key then
                    Marker.locked[key] = nil
                    Marker.placed[key] = nil
                    defense[key] = nil
                    MFD.Candidates.set[key] = nil
                end
            end
        end
    end)
end)

_G.MarkedForDeath = MFD
