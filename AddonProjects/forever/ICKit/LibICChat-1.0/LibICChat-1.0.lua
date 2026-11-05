--[[
LibICChat-1.0
Layer 1 of ICKit: lines an addon says in chat, sent only when the client will take them.

On Forever chat can be locked (and RAID, RAID_WARNING and INSTANCE_CHAT have their own
rules), so every line is decided before it goes: send it now, hold it in a queue until the
lock lifts or its time runs out, or refuse it with a reason the addon can show.

    local Chat = LibStub("LibICChat-1.0")
    local chat = Chat.New({ ttl = 10, onDrop = function(entry, reason) end })

    chat:Say({ text = "Tank down", channels = { "RAID_WARNING", "RAID" }, whenLocked = "queue" })
        -> the plan: { action = "send" | "queue" | "refuse", channel, text, reason }

    Chat.Decide(line, state)        -> the same plan, pure
    Chat.Flush(queue, state)        -> { send, dropped, keep }, pure
    Chat.Budget(channel, state)     -> 0 when a line may go now, else seconds to wait

A line: `text`, `channels` (a list, the first allowed wins) or `channel`, `whenLocked`
("queue" to hold it, anything else refuses), `ttl` (seconds a held line lives), `pressed`
(true when a key press or click sent it).

Decide, Flush and Budget are the pure half. A sender from Chat.New asks the client with
only what the in-game probe confirmed (Docs/client-reference.md), each call guarded.
]]

local MAJOR, MINOR = "LibICChat-1.0", 1
local Chat = LibStub:NewLibrary(MAJOR, MINOR)
if not Chat then return end

local Util = LibStub("LibICUtil-1.0")
local Env = LibStub("LibICEnv-1.0")
local Restrict = LibStub("LibICRestrict-1.0")
local Group = LibStub("LibICGroup-1.0")

local MAX_BYTES = 255       -- the longest line the client sends
local DEFAULT_TTL = 10      -- seconds a held line waits for the lock to lift
local MAX_QUEUE = 20        -- held lines per sender; past this a new one is refused
local RECHECK = 1           -- seconds between looks while a line is held, in case the lock
                            -- lifts without the restriction event firing

-- Lines per window, per channel: { lines, seconds }. Enough for a burst of calls, few
-- enough that an addon cannot flood a channel.
local DEFAULT_BUDGET = {
    RAID_WARNING = { 2, 10 },
    ["*"] = { 4, 10 },
}

-- What each channel needs from the group. From the probe: RAID, RAID_WARNING and
-- INSTANCE_CHAT in a party answer "You are not in a raid group"; INSTANCE_CHAT outside an
-- instance group is refused; SAY sent from a timer in combat never arrived.
local CHANNELS = {
    PARTY = { group = { party = true, raid = true, group = true } },
    RAID = { group = { raid = true } },
    RAID_WARNING = { group = { raid = true }, lead = true },
    INSTANCE_CHAT = { instanceGroup = true },
    SAY = { pressed = true },
    YELL = { pressed = true },
}

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

-- Line breaks out (the client refuses a line with one), cut to what the client sends.
local function CleanText(text)
    if type(text) ~= "string" then return nil end
    text = Util.Trim((text:gsub("[\r\n]+", " ")))
    if text == "" then return nil end
    return Util.Truncate(text, MAX_BYTES)
end

-- 0 when a line may go on channel now, else the seconds until one may. state.sent is
-- { [channel] = { times } } and state.budget overrides DEFAULT_BUDGET by channel.
function Chat.Budget(channel, state)
    state = state or {}
    local budgets = state.budget or DEFAULT_BUDGET
    local rule = budgets[channel] or budgets["*"] or DEFAULT_BUDGET[channel] or DEFAULT_BUDGET["*"]
    local lines, window = rule[1], rule[2]
    local now = state.now or 0
    local recent = {}
    for _, at in ipairs((state.sent or {})[channel] or {}) do
        if now - at < window then recent[#recent + 1] = at end
    end
    if #recent < lines then return 0 end
    table.sort(recent)
    return recent[#recent - lines + 1] + window - now
end

-- Why channel cannot take a line in this group, or nil when it can.
local function Unfit(channel, state, line)
    local rule = CHANNELS[channel]
    if not rule then return "no such channel: " .. tostring(channel) end
    if rule.group and not rule.group[state.group or "solo"] then
        if channel == "PARTY" then return "not in a group" end
        if state.group == "group" then return "cannot tell whether this is a raid" end
        return "not in a raid"
    end
    if rule.lead and state.lead ~= true then
        return state.lead == nil and "cannot tell whether you lead or assist" or "needs raid lead or assist"
    end
    if rule.instanceGroup and state.instanceGroup ~= true then return "not in an instance group" end
    if rule.pressed and line.pressed ~= true then return channel .. " needs a key press" end
    return nil
end

local function Locked(state)
    if state.chat == true then return true end
    return state.instance == "locked" and state.inInstance == true
end

-- line: see the header. state: what the client said now, every field optional:
--   now            seconds (GetTime)
--   chat           chat is locked (Restrict's State.chat)
--   inInstance     inside an instance
--   instance       "follow" (trust the client's lock, the default) or "locked" (treat
--                  every instance as locked: the policy for a client that locks without
--                  saying so)
--   group          "solo", "party", "raid", or "group" for one that may be a raid
--   lead           leader or assist in a raid (nil when unreadable)
--   instanceGroup  in an instance group
--   sent, budget   for Chat.Budget
-- Returns { action = "send" | "queue" | "refuse", channel, text, reason, wait }. A queued
-- plan says why (locked, or `wait` seconds of budget) and carries the channel it would use.
function Chat.Decide(line, state)
    line, state = line or {}, state or {}
    local text = CleanText(line.text)
    if not text then return { action = "refuse", reason = "nothing to say" } end

    local channels = line.channels or { line.channel }
    local channel, why
    for _, candidate in ipairs(channels) do
        local unfit = Unfit(candidate, state, line)
        if not unfit then
            channel = candidate
            break
        end
        why = why or unfit
    end
    if not channel then
        return { action = "refuse", text = text, reason = why or "no channel given" }
    end

    local plan = { channel = channel, text = text }
    local wait = Chat.Budget(channel, state)
    if Locked(state) then
        plan.reason = "chat is locked here"
    elseif wait > 0 then
        plan.reason, plan.wait = "too many lines on " .. channel, wait
    else
        plan.action = "send"
        return plan
    end
    plan.action = line.whenLocked == "queue" and "queue" or "refuse"
    return plan
end

-- queue: held entries { line, expires } in the order they were said. Each is decided again
-- against state, in order, counting what this round sends against the budget. Returns
-- { send = { plans }, dropped = { { entry, reason } }, keep = { entries } }. An entry
-- past its time is dropped as "expired"; one that is now refused is dropped with why.
function Chat.Flush(queue, state)
    state = state or {}
    local now = state.now or 0
    local sent = {}
    for channel, times in pairs(state.sent or {}) do
        sent[channel] = {}
        for i, at in ipairs(times) do sent[channel][i] = at end
    end
    local round = setmetatable({ sent = sent }, { __index = state })
    local out = { send = {}, dropped = {}, keep = {} }
    for _, entry in ipairs(queue or {}) do
        if now >= (entry.expires or 0) then
            out.dropped[#out.dropped + 1] = { entry = entry, reason = "expired" }
        else
            local plan = Chat.Decide(entry.line, round)
            if plan.action == "send" then
                out.send[#out.send + 1] = plan
                sent[plan.channel] = sent[plan.channel] or {}
                table.insert(sent[plan.channel], now)
            elseif plan.action == "queue" then
                out.keep[#out.keep + 1] = entry
            else
                out.dropped[#out.dropped + 1] = { entry = entry, reason = plan.reason }
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- The client
--------------------------------------------------------------------------------

local function Answer(ok, ...)
    if not ok then return nil end
    return ...
end

local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    return Answer(pcall(fn, ...))
end

local function Now()
    local t = Restrict.Readable(Ask(GetTime))
    return type(t) == "number" and t or 0
end

local Sender = {}
Sender.__index = Sender

-- The state Decide takes, from the client now.
function Sender:State()
    local restrict = Restrict.Now()
    local roster = Group.Now()
    local instanceType = Restrict.Readable(select(2, Ask(GetInstanceInfo)))
    local lead
    if roster.kind == "raid" then
        lead = roster.canMark
    end
    local group = roster.kind
    if roster.kindKnown == false then group = "group" end
    return {
        now = Now(),
        chat = restrict.chat,
        inInstance = type(instanceType) == "string" and instanceType ~= "none" or nil,
        instance = self.instance,
        group = group,
        lead = lead,
        instanceGroup = Restrict.Readable(Ask(IsInGroup, LE_PARTY_CATEGORY_INSTANCE)) == true,
        sent = self.sent,
        budget = self.budget,
    }
end

local function Record(sender, plan, now)
    local times = sender.sent[plan.channel] or {}
    sender.sent[plan.channel] = times
    times[#times + 1] = now
    while #times > 20 do table.remove(times, 1) end
end

-- Sends one plan. Returns whether the client took it.
function Sender:Send(plan, now)
    if type(SendChatMessage) ~= "function" then return false end
    local ok = pcall(SendChatMessage, plan.text, plan.channel)
    if ok then
        Record(self, plan, now)
        if self.onSend then self.onSend(plan) end
    end
    return ok
end

-- Wakes the sender after seconds to flush, once per pending wake.
function Sender:Wake(seconds)
    if self.waking or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    self.waking = true
    C_Timer.After(math.max(seconds, 0.1), function()
        self.waking = false
        self:Flush()
    end)
end

-- Next moment to look again, as seconds from now: a held line expiring, the budget
-- freeing, or RECHECK, whichever is first. Only runs while a line is held.
local function NextWake(queue, now, fallback)
    local soonest = RECHECK
    for _, entry in ipairs(queue) do
        local left = entry.expires - now
        if left < soonest then soonest = left end
    end
    if fallback and fallback < soonest then soonest = fallback end
    return soonest
end

-- Decides line now and acts on the plan: sends it, holds it, or refuses it. Returns the plan.
function Sender:Say(line)
    local state = self:State()
    local plan = Chat.Decide(line, state)
    if plan.action == "send" then
        if not self:Send(plan, state.now) then
            plan.action, plan.reason = "refuse", "the client did not take it"
        end
    elseif plan.action == "queue" then
        if #self.queue >= self.maxQueue then
            plan.action, plan.reason = "refuse", "too many lines waiting"
        else
            local ttl = tonumber(line.ttl) or self.ttl
            self.queue[#self.queue + 1] = { line = line, expires = state.now + ttl, plan = plan }
            self:Wake(NextWake(self.queue, state.now, plan.wait))
        end
    end
    return plan
end

-- Sends what may go now and drops what has expired; held lines stay held.
function Sender:Flush()
    if #self.queue == 0 then return end
    local state = self:State()
    local out = Chat.Flush(self.queue, state)
    for _, plan in ipairs(out.send) do self:Send(plan, state.now) end
    for _, drop in ipairs(out.dropped) do
        if self.onDrop then self.onDrop(drop.entry, drop.reason) end
    end
    self.queue = out.keep
    if #self.queue > 0 then self:Wake(NextWake(self.queue, state.now, nil)) end
end

-- Held lines, oldest first: { line, expires, plan }.
function Sender:Queue()
    return self.queue
end

-- opts: ttl (seconds, 10), maxQueue (20), budget ({ [channel] = { lines, seconds } },
-- "*" for the rest), instance ("follow" or "locked"), onSend(plan), onDrop(entry, reason).
-- The sender flushes whenever the restriction state changes, and on a timer while it holds
-- a line.
function Chat.New(opts)
    opts = opts or {}
    local sender = setmetatable({
        ttl = tonumber(opts.ttl) or DEFAULT_TTL,
        maxQueue = tonumber(opts.maxQueue) or MAX_QUEUE,
        budget = opts.budget,
        instance = opts.instance == "locked" and "locked" or "follow",
        onSend = opts.onSend,
        onDrop = opts.onDrop,
        queue = {},
        sent = {},
    }, Sender)
    sender.stop = Restrict.OnChange(Env.Wrap("ICKit chat flush", function() sender:Flush() end))
    return sender
end
