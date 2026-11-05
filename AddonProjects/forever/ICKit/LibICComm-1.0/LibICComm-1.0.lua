--[[
LibICComm-1.0
Layer 1 of ICKit: addon messages between players running the same addon.

A message is a table. It goes out as compact JSON, cut into frames that fit one addon
message, and comes back whole on every other client in the group. Your own copy, which
the client loops back, is dropped. A frame the client will not take now (locked down,
throttled) waits in a queue with a time to live.

    local Comm = LibStub("LibICComm-1.0")
    local comm = Comm.New("MarkedForDeath", { version = "0.1.0", onDrop = function(entry, reason) end })

    comm:On("plan", function(msg, from, channel) end)
    comm:Send({ t = "plan", rules = { ... } })     -> the plan: { action, channel, reason }
    comm:Hello()                                   -> says this version; peers answer once
    comm:Peers()                                   -> { [guid] = { name, version, at } }

Pure: Comm.Frame, Comm.Assemble, Comm.Channel, Comm.Result, Comm.Newer.
]]

local MAJOR, MINOR = "LibICComm-1.0", 1
local Comm = LibStub:NewLibrary(MAJOR, MINOR)
if not Comm then return end

local JSON = LibStub("LibICJSON-1.0")
local Env = LibStub("LibICEnv-1.0")
local Restrict = LibStub("LibICRestrict-1.0")
local Group = LibStub("LibICGroup-1.0")

local MAX_BYTES = 255       -- the longest addon message the client sends
local HEADER = 3            -- a frame's kind (one byte) and message id (two)
local MAX_PREFIX = 16       -- the longest prefix the client registers
local PARTIAL_TTL = 30      -- seconds a half-received message waits for the rest
local DEFAULT_TTL = 30      -- seconds a queued message waits for the client to take it
local MAX_QUEUE = 50        -- queued messages per sender; past this a new one is refused
local RECHECK = 1           -- seconds between tries while a message waits
local HELLO_QUIET = 60      -- seconds before answering the same peer's hello again
local ID_SPACE = 36 * 36    -- message ids, two base-36 digits

-- Frames per window: { frames, seconds }. Under the client's own throttle, so a burst
-- waits here rather than being refused there.
local DEFAULT_BUDGET = { 8, 10 }

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function Id(n)
    n = n % ID_SPACE
    local hi, lo = math.floor(n / 36), n % 36
    return DIGITS:sub(hi + 1, hi + 1) .. DIGITS:sub(lo + 1, lo + 1)
end

-- text cut into frames for message id n (a number). One frame is "S" .. id .. text;
-- more are "F", then "M"s, then "L", each with the id.
function Comm.Frame(text, n)
    local id = Id(n or 0)
    local room = MAX_BYTES - HEADER
    if #text <= room then return { "S" .. id .. text } end
    local frames = {}
    for at = 1, #text, room do
        local kind = (at == 1) and "F" or ((at + room > #text) and "L" or "M")
        frames[#frames + 1] = kind .. id .. text:sub(at, at + room - 1)
    end
    return frames
end

-- Adds one received frame. buffers holds partial messages between calls (the caller
-- keeps it per prefix); from is the sender. Returns the whole text when this frame
-- finishes one, else nil. A frame out of order, or a partial older than PARTIAL_TTL,
-- is dropped.
function Comm.Assemble(buffers, from, frame, now)
    if type(frame) ~= "string" or #frame < HEADER then return nil end
    now = now or 0
    for key, partial in pairs(buffers) do
        if now - partial.at > PARTIAL_TTL then buffers[key] = nil end
    end
    local kind, id, body = frame:sub(1, 1), frame:sub(2, 3), frame:sub(4)
    local key = tostring(from) .. "\0" .. id
    if kind == "S" then return body end
    if kind == "F" then
        buffers[key] = { parts = { body }, at = now }
        return nil
    end
    local partial = buffers[key]
    if not partial or (kind ~= "M" and kind ~= "L") then return nil end
    partial.parts[#partial.parts + 1] = body
    partial.at = now
    if kind == "M" then return nil end
    buffers[key] = nil
    return table.concat(partial.parts)
end

-- The channel a message to the whole group goes on, or nil and why. state: group
-- ("solo", "party", "raid", or "group" for one that may be a raid), instanceGroup, raid
-- ("follow", the default, or "off" to send nothing in a raid).
function Comm.Channel(state)
    state = state or {}
    if state.instanceGroup == true then return "INSTANCE_CHAT" end
    if state.group == "raid" then
        if state.raid == "off" then return nil, "addon messages are off in raids" end
        return "RAID"
    end
    if state.group == "party" then return "PARTY" end
    if state.group == "group" then return nil, "cannot tell whether this is a raid" end
    return nil, "not in a group"
end

-- What a send's result means, by its Enum.SendAddonMessageResult name: "sent", "retry"
-- (throttled: try again shortly), "hold" (locked down: wait for the lock to lift) or
-- "drop", with a reason for the last three.
local RESULTS = {
    Success = { "sent" },
    AddonMessageThrottle = { "retry", "throttled" },
    ChannelThrottle = { "retry", "throttled" },
    AddOnMessageLockdown = { "hold", "addon messages are locked down" },
    NotInGroup = { "drop", "not in a group for that channel" },
    InvalidChatType = { "drop", "the client refuses that channel" },
    InvalidPrefix = { "drop", "the prefix is not registered" },
    InvalidMessage = { "drop", "the client refuses the message" },
}
function Comm.Result(name)
    local r = RESULTS[name]
    if r then return r[1], r[2] end
    return "drop", "the client said " .. tostring(name)
end

-- Whether version a is newer than b, comparing "1.2.10" part by part as numbers. A
-- version that is not text is never newer.
function Comm.Newer(a, b)
    if type(a) ~= "string" then return false end
    if type(b) ~= "string" then return true end
    local pa, pb = {}, {}
    for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

-- The same budget rule as LibICChat: 0 when another frame may go at now, else seconds.
local function Wait(times, now, budget)
    local frames, window = budget[1], budget[2]
    local recent = {}
    for _, at in ipairs(times) do
        if now - at < window then recent[#recent + 1] = at end
    end
    if #recent < frames then return 0 end
    table.sort(recent)
    return recent[#recent - frames + 1] + window - now
end
Comm.Wait = Wait

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

-- The client's result number as its Enum name. The client's own table first; numbers it
-- lacks fall back to the order every client so far has used (5 NotInGroup was seen here).
local FALLBACK_RESULTS = {
    [0] = "Success", "InvalidPrefix", "InvalidMessage", "AddonMessageThrottle", "InvalidChatType",
    "NotInGroup", "TargetRequired", "InvalidChannel", "ChannelThrottle", "GeneralError", "NotInGuild",
    "AddOnMessageLockdown", "TargetOffline",
}
local function ResultName(code)
    if code == true or code == nil then return "Success" end
    if code == false then return "GeneralError" end
    local enum = type(Enum) == "table" and Enum.SendAddonMessageResult
    if type(enum) == "table" then
        for name, value in pairs(enum) do
            if value == code then return name end
        end
    end
    return FALLBACK_RESULTS[code] or tostring(code)
end

local Sender = {}
Sender.__index = Sender

-- One frame to the client. Returns the result's Enum name; a call that raises is
-- "GeneralError", and a client whose call returns nothing is taken as "Success".
function Sender:Post(frame, channel)
    local api = type(C_ChatInfo) == "table" and C_ChatInfo.SendAddonMessage
    if type(api) ~= "function" then return "GeneralError" end
    local ok, code = pcall(api, self.prefix, frame, channel)
    if not ok then return "GeneralError" end
    return ResultName(code)
end

function Sender:State()
    local roster = Group.Now()
    local group = roster.kind
    if roster.kindKnown == false then group = "group" end
    return {
        now = Now(),
        group = group,
        instanceGroup = Restrict.Readable(Ask(IsInGroup, LE_PARTY_CATEGORY_INSTANCE)) == true,
        raid = self.raid,
    }
end

-- Sends what the queue holds, oldest first, frame by frame, until the budget or the
-- client says wait. A message the client refuses is dropped and reported.
function Sender:Pump()
    local now = Now()
    local kept = {}
    local blocked = false
    for _, entry in ipairs(self.queue) do
        if now >= entry.expires then
            if self.onDrop then self.onDrop(entry, entry.why or "expired") end
        elseif blocked then
            kept[#kept + 1] = entry
        else
            while entry.next <= #entry.frames do
                if Wait(self.sent, now, self.budget) > 0 then
                    blocked = true
                    break
                end
                local verdict, reason = Comm.Result(self:Post(entry.frames[entry.next], entry.channel))
                if verdict == "sent" then
                    self.sent[#self.sent + 1] = now
                    while #self.sent > 50 do table.remove(self.sent, 1) end
                    entry.next = entry.next + 1
                elseif verdict == "drop" then
                    if self.onDrop then self.onDrop(entry, reason) end
                    entry.dropped = true
                    break
                else
                    entry.why = reason
                    blocked = true
                    break
                end
            end
            if not entry.dropped and entry.next <= #entry.frames then kept[#kept + 1] = entry end
        end
    end
    self.queue = kept
    if #kept > 0 then self:Wake() end
end

function Sender:Wake()
    if self.waking or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    self.waking = true
    C_Timer.After(RECHECK, function()
        self.waking = false
        self:Pump()
    end)
end

-- msg: a table with `t`, its type; Send adds `f`, the player's guid, which is how the
-- looped-back copy is known. channel: nil for the whole group (Comm.Channel picks).
-- Returns { action = "send" | "queue" | "refuse", channel, reason }: "send" when every
-- frame went at once, "queue" when some wait.
function Sender:Send(msg, channel)
    if type(msg) ~= "table" or type(msg.t) ~= "string" then
        return { action = "refuse", reason = "a message needs a type, msg.t" }
    end
    local why
    if not channel then channel, why = Comm.Channel(self:State()) end
    if not channel then return { action = "refuse", reason = why } end
    if #self.queue >= self.maxQueue then return { action = "refuse", channel = channel, reason = "too many messages waiting" } end
    msg.f = msg.f or self:Me()
    local text, err = JSON.Encode(msg, { compact = true })
    if not text then return { action = "refuse", channel = channel, reason = err } end
    self.counter = self.counter + 1
    local entry = { msg = msg, channel = channel, frames = Comm.Frame(text, self.counter), next = 1,
        expires = Now() + self.ttl }
    self.queue[#self.queue + 1] = entry
    self:Pump()
    for _, waiting in ipairs(self.queue) do
        if waiting == entry then return { action = "queue", channel = channel, reason = entry.why or "waiting its turn" } end
    end
    if entry.dropped then return { action = "refuse", channel = channel, reason = "the client refused it" } end
    return { action = "send", channel = channel }
end

function Sender:Me()
    if not self.me then self.me = Restrict.Readable(Ask(UnitGUID, "player")) end
    return self.me
end

-- fn(msg, from, channel) for each whole message of type t from another player.
function Sender:On(t, fn)
    self.handlers[t] = fn
end

function Sender:Hello(reply)
    return self:Send({ t = "hello", v = self.version, r = reply or nil })
end

function Sender:Peers()
    return self.peers
end

-- One received addon message: framing, then JSON, then the handler for its type.
function Sender:Receive(prefix, text, channel, from)
    if prefix ~= self.prefix then return end
    text, from = Restrict.Readable(text), Restrict.Readable(from)
    if type(text) ~= "string" then return end
    local whole = Comm.Assemble(self.buffers, from, text, Now())
    if not whole then return end
    local msg = JSON.Decode(whole)
    if type(msg) ~= "table" or type(msg.t) ~= "string" then return end
    if msg.f ~= nil and msg.f == self:Me() then return end
    if msg.t == "hello" then
        local now = Now()
        local key = msg.f or from
        local peer = self.peers[key] or {}
        local quiet = peer.answered and now - peer.answered < HELLO_QUIET
        peer.name, peer.version, peer.at = from, msg.v, now
        self.peers[key] = peer
        if not msg.r and not quiet then
            peer.answered = now
            self:Hello(true)
        end
    end
    local handler = self.handlers[msg.t]
    if handler then handler(msg, from, channel) end
end

-- Messages waiting, oldest first: { msg, channel, frames, next, expires, why }.
function Sender:Queue()
    return self.queue
end

-- prefix: the addon's, at most 16 characters. opts: version (for hello), ttl (30),
-- maxQueue (50), budget ({ frames, seconds }), raid ("follow" or "off"), onDrop(entry,
-- reason). Registers the prefix and listens for CHAT_MSG_ADDON at once, and tries the
-- queue again on every restriction change and once a second while it holds a message.
function Comm.New(prefix, opts)
    assert(type(prefix) == "string" and #prefix > 0 and #prefix <= MAX_PREFIX,
        "LibICComm: New needs a prefix of 1 to 16 characters")
    opts = opts or {}
    local sender = setmetatable({
        prefix = prefix,
        version = opts.version,
        ttl = tonumber(opts.ttl) or DEFAULT_TTL,
        maxQueue = tonumber(opts.maxQueue) or MAX_QUEUE,
        budget = opts.budget or DEFAULT_BUDGET,
        raid = opts.raid == "off" and "off" or "follow",
        onDrop = opts.onDrop,
        queue = {}, sent = {}, buffers = {}, handlers = {}, peers = {},
        counter = 0,
    }, Sender)
    if type(C_ChatInfo) == "table" then Ask(C_ChatInfo.RegisterAddonMessagePrefix, prefix) end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", Env.Wrap("ICKit comm " .. prefix, function(_, _, ...) sender:Receive(...) end))
    sender.frame = frame
    sender.stop = Restrict.OnChange(function() sender:Pump() end)
    return sender
end
