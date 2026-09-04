-- Everything this addon says to other people goes through here.
--
-- Before this there was a throttle per feature: one for the pull announcement,
-- one for late crowd control, a budget for raid warnings, a gap for adds, a
-- repeat window for deaths. Each was reasonable and no single place knew the
-- total, so the answer to "how much can this thing say in a bad minute" was
-- nobody's to give. Now it is this file's.
--
-- Two channels with very different costs are treated differently on purpose.
-- A raid message interrupts twenty five people, and a raid warning writes
-- across the middle of their screens; a whisper costs one person who is being
-- told something they have to act on. So whispers are not spent from the raid
-- budget. The rule this encodes is that the addon can go quiet on the raid
-- without ever going quiet on the person who has to sheep something.
local MFD = _G.MarkedForDeath or {}

MFD.Chatter = MFD.Chatter or {}
local Chatter = MFD.Chatter

-- window is seconds; the rest are counts inside that window. minGap is the
-- floor between any two group messages, so a burst reads as speech rather than
-- as three lines arriving on one frame.
Chatter.LIMITS = {
    window = 20,
    perWindow = 5,
    warningsPerWindow = 3,
    minGap = 1.5,
    whispersPerWindow = 12,
}

-- Drops timestamps that have fallen out of the window. Mutates times.
local function prune(times, now, window)
    local kept = 0
    for index = 1, #times do
        local at = times[index]
        if (now - at) < window then
            kept = kept + 1
            times[kept] = at
        end
    end
    for index = #times, kept + 1, -1 do
        times[index] = nil
    end
    return kept
end

-- The state one limiter keeps. Its own function so a test can hold several.
function Chatter.NewState()
    return { group = {}, warnings = {}, whispers = {}, lastAt = nil, droppedAt = nil }
end

-- May a message of this kind go out now? Records it when yes. Mutates state,
-- and is otherwise pure: no clock and no client.
--
-- kind is "RAID_WARNING", "WHISPER", or anything else meaning ordinary group
-- chat. Returns true when sent, or false and a short reason.
--
-- force sends regardless, and still records it. Two things earn it. A line the
-- player deliberately asked for, because swallowing a button press is worse
-- than a crowded chat frame and they can see for themselves how noisy it is.
-- And a death, which is rare, already guarded per name, and the one line
-- nobody can afford to have eaten by an announcement about a trash pack. What
-- the budget is actually for is the two things that can run away on their own:
-- pack announcements and late crowd control.
function Chatter.Allow(state, kind, now, limits, force)
    if force then
        if kind == "WHISPER" then
            state.whispers[#state.whispers + 1] = now
        else
            state.group[#state.group + 1] = now
            if kind == "RAID_WARNING" then
                state.warnings[#state.warnings + 1] = now
            end
            state.lastAt = now
        end
        return true
    end

    if kind == "WHISPER" then
        prune(state.whispers, now, limits.window)
        if #state.whispers >= limits.whispersPerWindow then
            return false, "whisper budget"
        end
        state.whispers[#state.whispers + 1] = now
        return true
    end

    prune(state.group, now, limits.window)
    prune(state.warnings, now, limits.window)

    if state.lastAt and (now - state.lastAt) < limits.minGap then
        return false, "too soon after the last line"
    end

    if #state.group >= limits.perWindow then
        return false, "group budget"
    end

    if kind == "RAID_WARNING" and #state.warnings >= limits.warningsPerWindow then
        return false, "raid warning budget"
    end

    state.group[#state.group + 1] = now
    if kind == "RAID_WARNING" then
        state.warnings[#state.warnings + 1] = now
    end
    state.lastAt = now

    return true
end

-- Whether a dropped message is worth telling the player about. Once per window,
-- because the point is to say "the addon has gone quiet on purpose", not to
-- replace the chat spam with local spam. Mutates state. Pure.
function Chatter.ShouldReportDrop(state, now, window)
    if state.droppedAt and (now - state.droppedAt) < window then
        return false
    end
    state.droppedAt = now
    return true
end

-- ---------------------------------------------------------------- client --

Chatter.state = Chatter.NewState()

-- Sends a message, or does not. Returns true when it went out.
--
-- Every SendChatMessage in this addon comes through here, and anything that
-- must not be dropped says so with force rather than quietly calling the client
-- itself. That is what keeps the answer to "how much can this thing say" in one
-- file instead of spread across six.
function Chatter.Say(message, channel, target, force)
    if not message or message == "" or not channel then
        return false
    end

    local now = GetTime()
    local ok, reason = Chatter.Allow(Chatter.state, channel, now, Chatter.LIMITS, force)

    if not ok then
        MFD.Log.Add(MFD.Log.KINDS.HELD, string.format("%s: %s (%s)", channel, message, reason))
        if Chatter.ShouldReportDrop(Chatter.state, now, Chatter.LIMITS.window) then
            MFD.Print("|cff999999holding back raid chat (" .. reason
                .. "). Nothing is broken; there is just too much to say.|r")
        end
        return false
    end

    MFD.Log.Add(MFD.Log.KINDS.SAY, string.format("%s%s: %s",
        channel, target and (" to " .. target) or "", message))
    pcall(SendChatMessage, message, channel, nil, target)
    return true
end

-- The channel to talk to the group on, or nil when there is no group. warn asks
-- for a raid warning, which needs lead or assist and falls back to raid chat.
function Chatter.GroupChannel(warn)
    if not (IsInRaid and IsInRaid()) then
        return (IsInGroup and IsInGroup()) and "PARTY" or nil
    end

    if warn then
        local canWarn = UnitIsGroupLeader("player")
            or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        if canWarn then
            return "RAID_WARNING"
        end
    end

    return "RAID"
end

_G.MarkedForDeath = MFD
