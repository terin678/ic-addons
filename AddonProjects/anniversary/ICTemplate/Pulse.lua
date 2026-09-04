local addonName, ns = ...

ns.Pulse = ns.Pulse or {}
local Pulse = ns.Pulse

--[[
The arm-and-fire pattern, which any addon that says something on a timer needs.

SendChatMessage to a public channel is protected on this client: it only goes
through from a hardware event. So a timer can never send. What it can do is ARM:
set a flag, make a noise, and say the line is ready. The send itself comes from a
key binding, a button, or a typed slash command -- all of which are hardware
events.

The gate is split in two on purpose. BlockReason takes a state table and is pure,
so every reason it can give has a test; ReadState is the only function here that
looks at the world. TradeMaster's equivalent reads InCombatLockdown() inside the
predicate, and nothing can test it as a result.
]]

local MAX_LEN = 255         -- bytes SendChatMessage accepts
local POLL_INTERVAL = 5     -- seconds between "is it due yet" checks
local MIN_INTERVAL = 15     -- seconds; below this it is a nuisance
local MAX_INTERVAL = 600    -- seconds; above this the timer is not the point

Pulse.MAX_LEN = MAX_LEN

-- What this addon would have to say. Replace it with whatever yours actually has:
-- items on hand, teams recruiting, whatever the message is about.
Pulse.entries = {
    "Adamantite Frame", "Primal Might", "Felsteel Gloves",
    "Netherweave Cloth", "Khorium Scope", "Fel Iron Casing",
}

-- Pure.
function Pulse.ClampInterval(secs)
    secs = math.floor(tonumber(secs) or MIN_INTERVAL)
    return math.max(MIN_INTERVAL, math.min(MAX_INTERVAL, secs))
end

-- Pure.
function Pulse.IsDue(lastSentAt, now, intervalSec)
    return (now - (lastSentAt or 0)) >= (intervalSec or MIN_INTERVAL)
end

--[[
Pure. Packs entries into the template's {items} slot until either the byte budget
or perLine runs out, starting at `cursor` and wrapping.

Returns msg, nextCursor, used -- or nil, cursor, 0 when nothing fits. The cursor
moves on so the next message shows different entries rather than the same three
forever.
]]
function Pulse.Fit(entries, cursor, template, maxLen, perLine)
    entries = entries or {}
    maxLen = maxLen or MAX_LEN
    perLine = math.max(1, perLine or 1)
    cursor = cursor or 1
    if #entries == 0 then return nil, cursor, 0 end
    if not template or not template:find("{items}", 1, true) then return nil, cursor, 0 end
    if cursor < 1 or cursor > #entries then cursor = 1 end

    -- The shell is everything but the items, so the budget is what is left.
    local shell = template:gsub("{items}", "")
    local budget = maxLen - #shell
    if budget <= 0 then return nil, cursor, 0 end

    local picked, i = {}, cursor
    for _ = 1, math.min(perLine, #entries) do
        local entry = entries[i]
        local candidate = table.concat(picked, ", ")
        if #picked > 0 then candidate = candidate .. ", " end
        candidate = candidate .. entry
        if #candidate > budget then break end
        picked[#picked + 1] = entry
        i = i % #entries + 1
    end

    if #picked == 0 then return nil, cursor, 0 end
    local msg = template:gsub("{items}", (table.concat(picked, ", "):gsub("%%", "%%%%")))
    return msg, i, #picked
end

--[[
Pure. Why the pulse cannot go out, or nil.

The order is fixed and documented, because the UI shows the first reason it gets
and a reason that changes with whichever check happened to run first is worse than
no reason at all. Widest first: the addon, then this feature, then the world.
]]
function Pulse.BlockReason(state)
    if not state.addonEnabled then return "ICTemplate is disabled" end
    if not state.pulseEnabled then return "the pulse timer is off" end
    if state.pauseCombat and state.inCombat then return "in combat" end
    if not state.hasTemplate then return "the template has no {items} in it" end
    if not state.hasEntries then return "nothing to send" end
    return nil
end

-- The only function in this file that reads the world. Everything above it can be
-- handed a made-up table.
function Pulse.ReadState()
    local s = ns.db.settings.pulse
    return {
        addonEnabled = ns.Enabled(),
        pulseEnabled = s.enabled and true or false,
        pauseCombat = s.pauseCombat and true or false,
        inCombat = (InCombatLockdown and InCombatLockdown())
            or (UnitAffectingCombat and UnitAffectingCombat("player")) or false,
        hasTemplate = (s.template or ""):find("{items}", 1, true) ~= nil,
        hasEntries = #Pulse.entries > 0,
    }
end

-- What the next pulse would say, without sending it.
function Pulse.Preview()
    local s = ns.db.settings.pulse
    local msg = Pulse.Fit(Pulse.entries, ns.cdb.pulse.cursor, s.template, MAX_LEN, s.perLine)
    return msg
end

-- Arms. The timer gets this far and no further.
function Pulse.Alert()
    local blocked = Pulse.BlockReason(Pulse.ReadState())
    if blocked then return false, blocked end

    Pulse.pending = true
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
    ns.Print("|cffffcc00pulse ready|r. Press your ICTemplate key, or use /ictpl send.")
    ns.Log.Add("info", "Pulse", "armed")
    if ns.UI then ns.UI.Refresh() end
    return true
end

--[[
Sends. Only ever reached from a hardware event: the key binding in Bindings.xml,
the button on the Pulse page, the minimap right-click, or /ictpl send.

`force` skips the interval check, not the gate. Someone pressing the button early
still may not send in combat.
]]
function Pulse.Fire(force)
    local s = ns.db.settings.pulse
    local c = ns.cdb.pulse

    local blocked = Pulse.BlockReason(Pulse.ReadState())
    if blocked then
        ns.Log.Add("warn", "Pulse", "not sent", blocked)
        return false, blocked
    end
    if not force and not Pulse.IsDue(c.lastSentAt, ns.Now(), s.intervalSec) then
        return false, "not due yet"
    end

    local msg, nextCursor, used = Pulse.Fit(Pulse.entries, c.cursor, s.template,
        MAX_LEN, s.perLine)
    if not msg then
        ns.Log.Add("warn", "Pulse", "not sent", "nothing fits in " .. MAX_LEN .. " bytes")
        return false, "nothing fits"
    end

    -- EMOTE rather than a public channel, so running the template cannot spam
    -- anyone. It is still a protected send, so this line proves the hardware-event
    -- path works before a real addon points it at Trade.
    SendChatMessage(msg, s.channel or "EMOTE")

    c.cursor = nextCursor
    c.lastSentAt = ns.Now()
    Pulse.pending = false
    Pulse.lastSkipReason = nil
    ns.Log.Add("ok", "Pulse", msg, string.format("%d entries, %d bytes, %s",
        used, #msg, s.channel or "EMOTE"))
    if ns.UI then ns.UI.Refresh() end
    return true, msg
end

function Pulse.Poll()
    local s = ns.db.settings.pulse
    if not s.enabled or not ns.Enabled() then return end
    if Pulse.pending then return end
    if not Pulse.IsDue(ns.cdb.pulse.lastSentAt, ns.Now(), s.intervalSec) then return end

    local ok, reason = Pulse.Alert()
    if not ok then
        -- The same reason every five seconds is the addon spamming its own output
        -- to complain about spam. Say it once, and again only when it changes.
        if reason ~= Pulse.lastSkipReason then
            Pulse.lastSkipReason = reason
            ns.Log.Capture("info", "Pulse", "due but skipped: " .. tostring(reason))
        end
    end
end

function Pulse.Stop()
    if Pulse.ticker then
        Pulse.ticker:Cancel()
        Pulse.ticker = nil
    end
    Pulse.pending = false
end

function Pulse.Start(immediate)
    Pulse.Stop()
    if immediate then Pulse.Alert() end
    Pulse.ticker = C_Timer.NewTicker(POLL_INTERVAL, Pulse.Poll)
end

-- Every stuck state needs a way out that is not /reload; this is the pulse's.
function Pulse.Restart()
    Pulse.Stop()
    if ns.db.settings.pulse.enabled and ns.Enabled() then Pulse.Start() end
end
