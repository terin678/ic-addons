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
local UnitGUID = UnitGUID
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

-- The authority's most recently published map, { [key] = icon }, with the
-- intent and owner alongside and the time each key first appeared. Backups
-- act from this; the assignment panel displays it.
Marker.published = {}
Marker.publishedDetail = {}
Marker.firstPublishedAt = {}

-- Seconds a backup waits for the authority to apply a published icon before
-- placing it. Long enough that the authority normally wins, short enough that
-- a pack is marked before the raid reaches it.
Marker.BACKUP_DELAY_SECONDS = 1.5

-- Parses the authority's published map into the tables above. Pure apart from
-- writing those tables. A key's first-seen stamp is set once and kept, so the
-- backup delay is measured from when the assignment first appeared, not from
-- the latest republish.
function Marker.ApplyPublished(payload, now)
    local published, detail = {}, {}

    for _, a in ipairs(Marker.DecodeAssignments(payload)) do
        published[a.key] = a.icon
        detail[a.key] = { intent = a.intent, owner = a.owner }
        if not Marker.firstPublishedAt[a.key] then
            Marker.firstPublishedAt[a.key] = now
        end
    end

    for key in pairs(Marker.firstPublishedAt) do
        if not published[key] then
            Marker.firstPublishedAt[key] = nil
        end
    end

    Marker.published, Marker.publishedDetail = published, detail
end

-- Returns { key, icon } pairs a backup should place: published icons that are
-- still not on the mob, that have been outstanding longer than delay, and that
-- this client has a valid unit for (nil in actual means it does not). Sorted
-- by key so two backups act in the same order.
function Marker.BackupActions(published, actual, firstSeenAt, now, delay)
    local actions = {}

    for _, key in ipairs(MFD.H.SortedKeys(published)) do
        local since = firstSeenAt[key]
        local present = actual[key]
        if since and present ~= nil and (since + delay) <= now and present ~= published[key] then
            actions[#actions + 1] = { key = key, icon = published[key] }
        end
    end

    return actions
end

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
        local present = actual[key]

        -- nil means there is no valid unit to read or write through right now:
        -- the nameplate dropped inside the grace window, or the stored token
        -- went stale. That is neither an action nor a defense. Counting it
        -- burned the entire brake budget in under a second on a mob we could
        -- not even touch.
        if present ~= nil and present ~= wanted then
            -- Either we put an icon here and it is gone or changed, or someone
            -- else has put a different icon on it. Both mean we are contesting
            -- the mob rather than marking it for the first time.
            local isDefense = placed[key] == true or present ~= 0

            if not isDefense then
                actions[#actions + 1] = { key = key, icon = wanted, isDefense = false }
            else
                local entry = defense[key]
                -- The back-off is measured from the moment of giving up, not
                -- from the first defense, so yielding buys a full quiet window.
                local expiresAt = entry and ((entry.yieldedAt or entry.windowStart) + limits.defenseWindow)
                if not entry or expiresAt < now then
                    entry = { count = 0, windowStart = now }
                    defense[key] = entry
                end

                if entry.count < limits.defenseLimit then
                    entry.count = entry.count + 1
                    actions[#actions + 1] = { key = key, icon = wanted, isDefense = true }
                else
                    entry.yieldedAt = entry.yieldedAt or now
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

-- Takes a snapshot of the marking pipeline and returns an ordered array of
-- human-readable reasons, most fundamental first. Pure.
--
-- This exists because the tick runs five times a second and cannot print, so
-- without it the addon can do nothing at all and give the player no clue why.
-- An empty role plan silently marking nothing is exactly the failure this
-- catches, and it is the one that shipped.
function Marker.DiagnoseState(state)
    local reasons = {}

    if not state.isMarkingEnabled then
        reasons[#reasons + 1] = "marking is switched off"
        return reasons
    end

    if not state.isAuthority then
        reasons[#reasons + 1] = (state.authority or "someone else")
            .. " is the marker, you are a backup"
        return reasons
    end

    if not state.canMark then
        reasons[#reasons + 1] = state.canMarkReason or "you cannot place icons"
        return reasons
    end

    if state.roleCount == 0 then
        reasons[#reasons + 1] = "no roles are configured, so no icon can be assigned. /mfd config"
        return reasons
    end

    if not state.cvarsOk then
        reasons[#reasons + 1] = state.cvarMessage or "nameplate settings prevent marking"
    end

    if state.candidateCount == 0 then
        reasons[#reasons + 1] = "no hostile mobs are visible. Are enemy nameplates on?"
        return reasons
    end

    if state.ruleCount == 0 then
        reasons[#reasons + 1] = "no rules are active for " .. tostring(state.instanceKey or "this zone")
        return reasons
    end

    if state.desiredCount == 0 then
        reasons[#reasons + 1] = state.candidateCount .. " mobs visible but none of them match a rule"
        return reasons
    end

    reasons[#reasons + 1] = "marking " .. state.desiredCount .. " of " .. state.candidateCount .. " visible mobs"
    return reasons
end

-- Assignment payload: "key=icon=INTENT=owner" entries joined by commas, with
-- an empty owner for intents that need none. Pure.
--
-- Kept as one string rather than one message per assignment because the whole
-- map has to arrive together: a half-applied map marks some mobs and not
-- others, which is worse than marking none.
function Marker.EncodeAssignments(list)
    local parts = {}
    for _, a in ipairs(list) do
        parts[#parts + 1] = string.format("%s=%d=%s=%s", a.key, a.icon, a.intent, a.owner or "")
    end
    return table.concat(parts, ",")
end

-- Takes an assignment payload. Returns an array of { key, icon, intent, owner }.
-- Entries that do not match in full are dropped rather than half-read, because
-- a truncated transfer must not produce an assignment with a missing icon. Pure.
function Marker.DecodeAssignments(payload)
    local list = {}
    if type(payload) ~= "string" then
        return list
    end

    for key, icon, intent, owner in string.gmatch(payload, "([%d]+:%x+)=(%d+)=(%u+)=([^,]*)") do
        list[#list + 1] = {
            key = key,
            icon = tonumber(icon),
            intent = intent,
            owner = owner ~= "" and owner or nil,
        }
    end

    return list
end

-- Chooses which borrowed locks to give up so that crowd control can have its
-- icons back. Returns the keys to release, lowest first, at most as many as
-- are actually needed. Pure.
--
-- Only borrowed locks are eligible. A real assignment is never disturbed
-- mid-fight, because moving somebody's actual kill target under them is worse
-- than one mob going unmarked.
function Marker.ReleaseBorrowed(locked, borrowed, neededCount)
    if neededCount <= 0 then
        return {}
    end

    local candidates = {}
    for _, key in ipairs(MFD.H.SortedKeys(locked)) do
        if borrowed[key] then
            candidates[#candidates + 1] = key
        end
    end

    local released = {}
    for i = 1, math.min(neededCount, #candidates) do
        released[i] = candidates[i]
    end
    return released
end

-- Clears every icon this client can reach and forgets what it placed. Returns
-- how many were cleared.
--
-- Routed through ActionableUnits for the same reason marking is: clearing
-- through a stale token wipes the icon off whatever the player happens to be
-- pointing at rather than off the mob it was meant for.
function Marker:ClearAll()
    local cleared = 0
    for _, unit in pairs(MFD.Candidates.ActionableUnits(MFD.Candidates.set, UnitGUID)) do
        SetRaidTarget(unit, 0)
        cleared = cleared + 1
    end

    wipe(Marker.locked)
    wipe(Marker.placed)
    wipe(Marker.borrowed)
    return cleared
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

local defense = {}
local accumulator = 0
local sightingAccumulator = 0
local hasReportedTickError = false

-- Builds the roster the role resolver needs. Returns an array of
-- { name, class }. Reads client state, so it never runs at file scope.
function Marker.BuildRoster()
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

local rosterCache, rolesCache, rolesCachePlan

-- Drops the cached roster and the roles resolved from it. Called whenever the
-- group changes or the role plan is edited.
function Marker.InvalidateRoster()
    rosterCache, rolesCache, rolesCachePlan = nil, nil, nil
end

-- Returns the group roster, built once and reused until invalidated.
--
-- The tick runs five times a second and the roster only changes when somebody
-- joins or leaves, so rebuilding it every tick is 125 roster API calls a
-- second in a full raid for an answer that did not change.
function Marker.CurrentRoster()
    if not rosterCache then
        rosterCache = Marker.BuildRoster()
    end
    return rosterCache
end

-- Returns the resolved roles for a plan, cached against the roster. Re-resolves
-- when the roster is invalidated or a different plan table is passed, which is
-- what the role editor does after an edit.
function Marker.ResolvedRoles(plan)
    if not rolesCache or rolesCachePlan ~= plan then
        rolesCache = MFD.Roles.Resolve(plan, Marker.CurrentRoster())
        rolesCachePlan = plan
    end
    return rolesCache
end

-- Returns { [key] = icon } for the units the client can currently read, plus
-- a { [key] = unitToken } map for applying icons.
local function readActual()
    -- Every token is re-validated against the mob it is supposed to refer to.
    -- Reading or writing an icon through a stale alias touches whatever the
    -- player is pointing at instead of the intended mob.
    local units = MFD.Candidates.ActionableUnits(MFD.Candidates.set, UnitGUID)
    local actual = {}

    for key, unit in pairs(units) do
        actual[key] = GetRaidTargetIndex(unit) or 0
    end

    return actual, units
end

-- Recomputes the desired map from the current candidates, rules and roles.
function Marker:Desired()
    local roles = Marker.ResolvedRoles(MFD.db.rolePlan)
    local candidates = MFD.Candidates.ToList(MFD.Candidates.set)
    -- Rules may be filed by npcID or by name; the allocator only thinks in
    -- ids, so name rules are matched onto the mobs actually on screen first.
    local rules = MFD.Rules.ResolveForCandidates(MFD.Rules.Active(), candidates)
    local allowReuse = MFD.db.settings.isIconReuseEnabled
    local desired = MFD.Allocator.Compute(candidates, rules, roles, Marker.locked, allowReuse)

    -- Which mobs wanted crowd control and got nothing. The tick uses this to
    -- take a borrowed icon back and shout about it.
    desired.unmetCrowdControl = MFD.Allocator.UnmetCrowdControl(candidates, rules, desired.byKey)
    desired.candidates = candidates
    return desired
end

-- Icons currently on loan to a kill target, { [key] = true }.
Marker.borrowed = {}

-- Crowd control assignments already shouted about this pull.
Marker.alertedCrowdControl = {}

-- Set at the pull: the crowd control the raid knew about going in. Anything
-- that appears afterwards is by definition a surprise and worth a warning.
Marker.pullCrowdControl = nil

local lastAlertAt = 0

-- Shouts about a crowd control assignment that appeared after the pull.
--
-- Silent before combat, because the allocator is still settling and the pull
-- announcement covers it. Silent for anything present at the pull. Authority
-- only, and once per mob.
function Marker:AlertLateCrowdControl(desired, now)
    if not MFD.IsEnabled() or not MFD.db.settings.isLateCCAlertEnabled then
        return
    end
    if not Marker.pullCrowdControl or not MFD.Comms:IsAuthority() then
        return
    end
    if (now - lastAlertAt) < MFD.Announce.LATE_ALERT_THROTTLE_SECONDS then
        return
    end

    for _, assignment in ipairs(desired.list) do
        local def = MFD.Roles.INTENTS[assignment.intent]
        local isCrowdControl = def and def.classes
        if isCrowdControl and not Marker.pullCrowdControl[assignment.key]
            and not Marker.alertedCrowdControl[assignment.key] then

            Marker.alertedCrowdControl[assignment.key] = true
            lastAlertAt = now

            local learned = MFD.db.learnedMobs[MFD.H.NpcIDFromKey(assignment.key)]
            local mobName = learned and learned.name or nil

            local channel = (IsInRaid and IsInRaid() and "RAID_WARNING")
                or (IsInGroup and IsInGroup() and "PARTY") or nil
            if channel then
                pcall(SendChatMessage, "[MFD] " .. MFD.Announce.FormatLateAlert(assignment, mobName), channel)
            end

            if assignment.owner and assignment.owner ~= UnitName("player") then
                pcall(SendChatMessage, "[MFD] " .. MFD.Announce.FormatLateWhisper(assignment, mobName),
                    "WHISPER", nil, assignment.owner)
            end

            MFD.Print("|cffff4444late " .. tostring(assignment.intent)
                .. ": " .. (mobName or assignment.key) .. "|r")
            return
        end
    end
end

-- Gathers the live pipeline state and runs it through DiagnoseState. Returns
-- the reason array plus the snapshot, so /mfd debug can show both.
function Marker:Diagnose()
    local canMark, canMarkReason = Marker:CanMark()
    local cvarsOk, cvarMessage = Marker:CheckCvars()

    local candidateCount = 0
    for _ in pairs(MFD.Candidates.set) do
        candidateCount = candidateCount + 1
    end

    local ruleCount = 0
    for _ in pairs(MFD.Rules.Active()) do
        ruleCount = ruleCount + 1
    end

    local roleCount = 0
    for _ in pairs(MFD.db.rolePlan) do
        roleCount = roleCount + 1
    end

    local desiredCount = 0
    local ok, desired = pcall(Marker.Desired, Marker)
    if ok and desired then
        desiredCount = #desired.list
    end

    local state = {
        isMarkingEnabled = MFD.db.settings.isMarkingEnabled,
        isAuthority = MFD.Comms:IsAuthority(),
        authority = MFD.Comms.authority,
        canMark = canMark,
        canMarkReason = canMarkReason,
        cvarsOk = cvarsOk,
        cvarMessage = cvarMessage,
        roleCount = roleCount,
        candidateCount = candidateCount,
        ruleCount = ruleCount,
        desiredCount = desiredCount,
        instanceKey = MFD.Rules.currentInstanceKey,
    }

    return Marker.DiagnoseState(state), state
end

function Marker:Tick(elapsed)
    accumulator = accumulator + elapsed
    if accumulator < Marker.LIMITS.tickInterval then
        return
    end
    accumulator = 0

    if not MFD.IsEnabled() or not MFD.db.settings.isMarkingEnabled then
        return
    end

    local now = GetTime()

    for _, key in ipairs(MFD.Candidates.Prune(MFD.Candidates.set, now, MFD.Candidates.GRACE_SECONDS)) do
        Marker.locked[key] = nil
        Marker.placed[key] = nil
        defense[key] = nil
        MFD.Comms.reportedSightings[key] = nil
    end

    if not MFD.Comms:IsAuthority() then
        -- Backup: report what we can see, then place anything the authority
        -- published but could not reach itself.
        sightingAccumulator = sightingAccumulator + Marker.LIMITS.tickInterval
        if sightingAccumulator >= MFD.Comms.SIGHTING_INTERVAL_SECONDS then
            sightingAccumulator = 0
            local pending = MFD.Comms.PendingSightings(
                MFD.Candidates.set, MFD.Comms.reportedSightings,
                function(npcID) return MFD.Comms:IsRuled(npcID) end,
                MFD.Comms.SIGHTINGS_PER_MESSAGE, now, MFD.Comms.SIGHTING_REFRESH_SECONDS)
            if #pending > 0 then
                MFD.Comms:Send("S", { MFD.Comms.EncodeSightings(pending) })
            end
        end

        if Marker:CanMark() then
            local actual, units = readActual()
            for _, action in ipairs(Marker.BackupActions(
                Marker.published, actual, Marker.firstPublishedAt, now, Marker.BACKUP_DELAY_SECONDS)) do
                local unit = units[action.key]
                if unit then
                    SetRaidTarget(unit, action.icon)
                    Marker.placed[action.key] = true
                    MFD.Comms:Send("C", { action.key })
                end
            end
        end

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

    -- Report a yield once per back-off. Clearing state here was the loop:
    -- fresh apply, cleared again, three defenses, yield, print, repeat. The
    -- defense entry now holds until its window expires on its own.
    for _, key in ipairs(diff.yielded) do
        local entry = defense[key]
        if entry and not entry.hasReported then
            entry.hasReported = true
            local culprits = MFD.Conflicts and MFD.Conflicts.Format(MFD.Conflicts.Detect()) or {}
            MFD.Print("backing off " .. key .. " for " .. Marker.LIMITS.defenseWindow
                .. "s, something keeps changing that icon"
                .. (#culprits > 0 and (" -- likely " .. culprits[1]) or ""))
        end
    end

    -- A crowd control mob nobody planned for has turned up and has no icon.
    -- Give back a borrowed one so it can have its role on the next tick. Only
    -- borrowed locks are eligible, so a real assignment is never moved.
    if #desired.unmetCrowdControl > 0 then
        local released = Marker.ReleaseBorrowed(Marker.locked, Marker.borrowed, #desired.unmetCrowdControl)
        for _, key in ipairs(released) do
            Marker.locked[key] = nil
            Marker.borrowed[key] = nil
        end
    end

    -- Remember which icons are on loan, so the release above knows what it may
    -- take back.
    wipe(Marker.borrowed)
    for _, assignment in ipairs(desired.list) do
        if assignment.isBorrowed then
            Marker.borrowed[assignment.key] = true
        end
    end

    Marker:AlertLateCrowdControl(desired, now)
    Marker.lastDesired = desired

    -- Publish only when the map actually changed. The tick runs five times a
    -- second; publishing every time would consume the entire channel budget.
    local payload = Marker.EncodeAssignments(desired.list)

    if payload ~= Marker.lastPublishedPayload then
        Marker.lastPublishedPayload = payload
        Marker.ApplyPublished(payload, now)

        local chunks = MFD.Comms.Chunk(payload, MFD.Comms.CHUNK_BYTES)
        for i, chunkText in ipairs(chunks) do
            MFD.Comms:Send("A", { i, #chunks, chunkText })
        end
    end
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
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")

    frame:SetScript("OnEvent", function(_, event)
        if event == "GROUP_ROSTER_UPDATE" then
            Marker.InvalidateRoster()
        end

        if event == "PLAYER_REGEN_DISABLED" then
            -- Freeze the current map so nothing shifts under the raid mid-pull.
            local desired = Marker.lastDesired
            Marker.pullCrowdControl = {}
            wipe(Marker.alertedCrowdControl)

            if desired then
                for key, icon in pairs(desired.byKey) do
                    Marker.locked[key] = icon
                end
                -- What the raid knew about going in. Anything crowd control
                -- that appears after this is a surprise worth warning about.
                for _, assignment in ipairs(desired.list) do
                    local def = MFD.Roles.INTENTS[assignment.intent]
                    if def and def.classes then
                        Marker.pullCrowdControl[assignment.key] = true
                    end
                end
            end
            MFD.Announce.Post(desired, GetTime())
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Out of combat the allocator is free to re-optimise again, and
            -- late-arrival warnings go quiet: between pulls there is no such
            -- thing as a surprise.
            wipe(Marker.locked)
            wipe(Marker.alertedCrowdControl)
            Marker.pullCrowdControl = nil
        elseif event == "PLAYER_ENTERING_WORLD" then
            wipe(Marker.locked)
            wipe(Marker.placed)
            wipe(Marker.alertedCrowdControl)
            Marker.pullCrowdControl = nil
            Marker.InvalidateRoster()
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

-- Raid chat announcement of the pack, for the benefit of people not running
-- the addon. Lives here rather than in the UI file so it stays testable.
MFD.Announce = MFD.Announce or {}
local Announce = MFD.Announce

Announce.THROTTLE_SECONDS = 5   -- minimum gap between announcements

-- Display order and names for the eight icons, kill icons first so the line
-- always opens with what dies first.
local ICON_NAMES = {
    [8] = "Skull", [7] = "Cross", [6] = "Square", [2] = "Circle",
    [5] = "Moon", [1] = "Star", [4] = "Triangle", [3] = "Diamond",
}
local ANNOUNCE_ORDER = { 8, 7, 6, 2, 5, 1, 4, 3 }

-- Takes the allocator's assignment list. Returns one compact line ordered by
-- the display order above, so it reads identically every pull. Pure.
function Announce.Format(assignments)
    local byIcon = {}
    for _, a in ipairs(assignments) do
        byIcon[a.icon] = a
    end

    local parts = {}
    for _, icon in ipairs(ANNOUNCE_ORDER) do
        local a = byIcon[icon]
        if a then
            local label = MFD.Roles.INTENTS[a.intent] and MFD.Roles.INTENTS[a.intent].label or a.intent
            parts[#parts + 1] = ICON_NAMES[icon] .. ">" .. label .. (a.owner and (" " .. a.owner) or "")
        end
    end

    return table.concat(parts, " | ")
end

Announce.LATE_ALERT_THROTTLE_SECONDS = 3   -- minimum gap between late alerts

-- The raid warning for a crowd control target nobody planned for. Names the
-- job first because that is the word the reader is scanning for. Pure.
function Announce.FormatLateAlert(assignment, mobName)
    local def = MFD.Roles.INTENTS[assignment.intent]
    local label = def and def.label:upper() or assignment.intent
    return string.format("%s %s: %s - %s", label, ICON_NAMES[assignment.icon] or "?",
        mobName or "unknown", assignment.owner or "unassigned")
end

-- The whisper to the one person who has to act on it. Pure.
function Announce.FormatLateWhisper(assignment, mobName)
    local def = MFD.Roles.INTENTS[assignment.intent]
    local label = def and def.label or assignment.intent
    return string.format("%s the %s now: %s", label,
        ICON_NAMES[assignment.icon] or "?", mobName or "unknown")
end

-- Posts the current pack to the group once per pull, authority only, throttled
-- so two quick pulls do not produce two lines.
function Announce.Post(desired, now)
    if not MFD.IsEnabled() or not MFD.db.settings.isAnnounceEnabled
        or not MFD.Comms:IsAuthority() or not desired then
        return
    end

    if (now - (Announce.lastAt or 0)) <= Announce.THROTTLE_SECONDS then
        return
    end

    local line = Announce.Format(desired.list)
    if line == "" then
        return
    end

    local target = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and IsInGroup() and "PARTY") or nil
    if not target then
        return
    end

    Announce.lastAt = now
    pcall(SendChatMessage, "[MFD] " .. line, target)
end

_G.MarkedForDeath = MFD
