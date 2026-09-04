local addonName, ns = ...

ns.Bark = ns.Bark or {}
local Bark = ns.Bark

--[[
Sending the line, and not sending it when somebody else already has.

SendChatMessage to a public channel is protected on this client, so the timer can
only ever ARM: it makes a noise and says the line is ready, and a keypress, a
button or a typed command sends it. That split is the whole shape of this file.

The gate is a pure predicate over an injected state plus one function that reads
the world, so every reason an officer can be told has a case. The order of the
reasons is the contract: the UI shows the first one, and a reason that changes
depending on which check ran first is worse than no reason at all.
]]

local POLL_INTERVAL = 5     -- seconds between "is it due yet"
local MIN_INTERVAL = 300    -- seconds; recruiting more often than this is spam
local MAX_INTERVAL = 3600   -- seconds
local MAX_BARKS = 60        -- barks remembered, ours and everyone else's

Bark.MAX_BARKS = MAX_BARKS

-- Pure. One officer, one second, one bark.
function Bark.Key(who, at)
    return string.format("%s@%d", tostring(who or "?"), math.floor(at or 0))
end

--[[
Pure. Places a bark by time, newest first, and returns whether it was new.

Deliberately not the log's blind insert-at-one. Arrival order equals time order
for our own barks, but a remote one can turn up late after a reconnect, and a
bark filed in the wrong place would make the suppression window lie.
]]
function Bark.Insert(log, entry, maxEntries)
    local key = Bark.Key(entry.who, entry.at)
    for _, existing in ipairs(log) do
        if Bark.Key(existing.who, existing.at) == key then return false end
    end

    local at = #log + 1
    for i, existing in ipairs(log) do
        if (entry.at or 0) > (existing.at or 0) then
            at = i
            break
        end
    end
    table.insert(log, at, entry)

    for i = #log, (maxEntries or MAX_BARKS) + 1, -1 do
        table.remove(log, i)
    end
    return true
end

--[[
Pure. Has somebody else already said this recently? Returns who and how many
seconds ago, or nil.

This is the whole anti-spam feature, and it is a dozen lines. Our own barks do not
count -- the interval timer handles those -- and a bark on a different channel is
not the same audience.
]]
function Bark.Suppressed(barks, now, quietSec, channel, selfName)
    if not quietSec or quietSec <= 0 then return nil end
    for _, bark in ipairs(barks or {}) do
        local mine = bark.who == selfName
        local sameRoom = not channel or not bark.channel or bark.channel == channel
        if not mine and sameRoom then
            local ago = now - (bark.at or 0)
            -- Newest first, so the first one inside the window is the closest.
            if ago >= 0 and ago < quietSec then return bark.who, ago end
        end
    end
    return nil
end

-- Pure.
function Bark.ClampInterval(secs)
    secs = math.floor(tonumber(secs) or MIN_INTERVAL)
    return math.max(MIN_INTERVAL, math.min(MAX_INTERVAL, secs))
end

-- Pure.
function Bark.IsDue(lastSentAt, now, intervalSec)
    return (now - (lastSentAt or 0)) >= (intervalSec or MIN_INTERVAL)
end

--[[
Pure. GetChannelList returns a flat list with a stride of THREE on this client:
id, name, disabled, id, name, disabled. Getting that wrong reads every other
channel's name as its id.

`wanted` is a substring, or "auto" to take the first of the usual three that this
character has actually joined. Returns id, name.
]]
local AUTO_ORDER = { "LookingForGroup", "Trade", "General" }

function Bark.Channel(list, wanted)
    local channels = {}
    for i = 1, #(list or {}), 3 do
        local id, name = list[i], list[i + 1]
        if type(name) == "string" and tonumber(id) then
            channels[#channels + 1] = { id = tonumber(id), name = name }
        end
    end

    local function Match(needle)
        needle = needle:lower()
        for _, channel in ipairs(channels) do
            if channel.name:lower():find(needle, 1, true) then
                return channel.id, channel.name
            end
        end
        return nil
    end

    if wanted and wanted ~= "" and wanted ~= "auto" then return Match(wanted) end
    for _, needle in ipairs(AUTO_ORDER) do
        local id, name = Match(needle)
        if id then return id, name end
    end
    return nil
end

--[[
Pure. Why the message will not go out, or nil. Widest reason first: the addon,
then the guild, then this officer, then the world, then the message, and last the
one that is about other people.
]]
function Bark.BlockReason(state)
    if not state.addonEnabled then return "GuildRecruitment is disabled" end
    if not state.inGuild then return "you are not in a guild" end
    if not state.canBark then return "your guild rank is not allowed to send it" end
    if state.pauseCombat and state.inCombat then return "in combat" end
    if state.pauseInstance and state.inInstance then return "in an instance" end
    if not state.channel then
        return "no channel to send to; join one, or set it on the Settings tab"
    end
    if state.messageReason then return state.messageReason end
    if state.suppressedBy then
        return string.format("%s barked %s ago", state.suppressedBy,
            ns.Util.Duration(state.suppressedAgo))
    end
    return nil
end

-- The only function here that reads the world. Everything above can be handed a
-- table made up in a test.
function Bark.ReadState()
    local s = ns.db.settings.bark
    local now = ns.Now()
    local me = ns.Roster.Short(UnitName and UnitName("player") or "")
    local list = {}
    if type(GetChannelList) == "function" then list = { GetChannelList() } end
    local channelID, channelName = Bark.Channel(list, s.channel)

    local msg, _, _, _, reason = ns.Message.Assemble(ns.db.doc, ns.cdb.bark.cursor)
    if msg then
        local ok, why = ns.Message.Validate(msg)
        if not ok then reason = why end
    end

    local who, ago = Bark.Suppressed(ns.db.barks, now, s.quietSec, channelName, me)

    return {
        addonEnabled = ns.Enabled(),
        inGuild = (IsInGuild and IsInGuild()) and true or false,
        canBark = ns.Roster.ICanBark(),
        pauseCombat = s.pauseCombat and true or false,
        pauseInstance = s.pauseInstance and true or false,
        inCombat = (InCombatLockdown and InCombatLockdown())
            or (UnitAffectingCombat and UnitAffectingCombat("player")) or false,
        inInstance = (IsInInstance and IsInInstance()) and true or false,
        channel = channelID,
        channelName = channelName,
        message = msg,
        messageReason = reason,
        suppressedBy = who,
        suppressedAgo = ago,
    }
end

-- What would go out, with no side effects. The Bark tab shows this next to the
-- button, so nobody sends a line they have not read.
function Bark.Preview()
    local msg, level, dropped = ns.Message.Assemble(ns.db.doc, ns.cdb.bark.cursor)
    return msg, level, dropped
end

function Bark.SecondsUntilDue()
    local s = ns.db.settings.bark
    return math.max(0, (ns.cdb.bark.lastSentAt or 0) + s.intervalSec - ns.Now())
end

--------------------------------------------------------------------------------
-- Arm, then fire
--------------------------------------------------------------------------------

function Bark.Alert()
    local blocked = Bark.BlockReason(Bark.ReadState())
    if blocked then return false, blocked end

    Bark.pending = true
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
    ns.Print("|cffffcc00recruitment message ready|r. Press your GuildRecruitment key, "
        .. "or use /gr send.")
    ns.Log.Add("armed", "Bark", "armed")
    if ns.UI then ns.UI.Refresh() end
    return true
end

--[[
Sends. Only ever reached from a hardware event: the key binding, the Bark button,
the minimap right click, or /gr send.

The first send of a revision an officer has not seen asks once. The Bark tab
already shows the line beside the button, but the keybind and the minimap do not,
and a raid leader's edit going out under somebody else's name without them
reading it is the one mistake this addon must not make.
]]
function Bark.Fire(force)
    local s = ns.db.settings.bark
    local c = ns.cdb.bark
    local state = Bark.ReadState()

    local blocked = Bark.BlockReason(state)
    if blocked then
        ns.Log.Add("skipped", "Bark", "not sent", blocked)
        return false, blocked
    end
    if not force and not Bark.IsDue(c.lastSentAt, ns.Now(), s.intervalSec) then
        return false, "not due yet"
    end

    local rev = ns.db.doc.rev or 0
    if s.confirmNewRev ~= false and c.confirmedRev ~= rev then
        c.confirmedRev = rev
        ns.Printf("|cffffcc00rev %d, which you have not sent before:|r %s", rev, state.message)
        ns.Print("Send it again to put that in " .. (state.channelName or "chat") .. ".")
        if ns.UI then ns.UI.Refresh() end
        return false, "read it first, then send again"
    end

    SendChatMessage(state.message, "CHANNEL", nil, state.channel)

    local now = ns.Now()
    local me = ns.Roster.Short(UnitName and UnitName("player") or "")
    local _, _, _, nextCursor = ns.Message.Assemble(ns.db.doc, c.cursor)
    c.cursor = nextCursor or c.cursor
    c.lastSentAt = now
    Bark.pending = false
    Bark.lastSkipReason = nil

    Bark.Insert(ns.db.barks, {
        who = me, at = now, channel = state.channelName,
        rev = rev, len = #state.message,
    }, MAX_BARKS)

    -- Tell the other officers, so their gate can say "you barked 90s ago" instead
    -- of letting them add a second line to the same channel.
    ns.Comm.AnnounceBark(me, now, state.channelName or "", rev, #state.message)

    ns.Log.Add("sent", "Bark", state.message,
        string.format("%s, rev %d, %d characters", state.channelName or "?", rev,
            #state.message))
    if ns.UI then ns.UI.Refresh() end
    return true, state.message
end

function Bark.Poll()
    local s = ns.db.settings.bark
    if not s.enabled or not ns.Enabled() then return end
    if Bark.pending then return end
    if not Bark.IsDue(ns.cdb.bark.lastSentAt, ns.Now(), s.intervalSec) then return end

    local ok, reason = Bark.Alert()
    if not ok and reason ~= Bark.lastSkipReason then
        -- The same reason every five seconds would be this addon spamming its own
        -- output to complain about spam. Once, and again only when it changes.
        Bark.lastSkipReason = reason
        ns.Log.Capture("skipped", "Bark", "due but skipped: " .. tostring(reason))
    end
end

function Bark.Stop()
    if Bark.ticker then
        Bark.ticker:Cancel()
        Bark.ticker = nil
    end
    Bark.pending = false
end

function Bark.Start()
    Bark.Stop()
    Bark.ticker = C_Timer.NewTicker(POLL_INTERVAL, Bark.Poll)
end

-- Every stuck state needs a way out that is not /reload. This is the bark's.
function Bark.Restart()
    Bark.Stop()
    if ns.db.settings.bark.enabled and ns.Enabled() then Bark.Start() end
end
