local addonName, ns = ...

ns.Comm = ns.Comm or {}
local Comm = ns.Comm

--[[
The wire. Everything above Comm.OnAddonMessage is pure and testable; everything
below it talks to the client.

Written lib-shaped on purpose -- no reads of ns.db in the encoding half, no
GuildRecruitment strings in Escape, Split, Chunk or Bucket -- so that the day a
second addon needs guild comms this half moves into ICLibs as LibICComm-1.0
without being redesigned. It is not there yet because there is one consumer, and
because nothing in this repo has ever sent an addon message: locking a public API
around an unverified client call is the wrong order.

    S   the whole document
    V   "I hold rev N"            an offer, sent at login
    R   "send me yours if it beats this"
    B   "I just barked"

Trust: every one of these arrives from another player and is data, never markup
and never code. What is checked, and in what order, is in Comm.Accept.
]]

local PREFIX = "ICGR"
local PROTO = 1

local WIRE_MAX = 255            -- bytes in one addon message
local CHUNK_BYTES = 200         -- payload per chunk; the rest is envelope and slack
-- Eight chunks is 1600 bytes, which is what the largest document the UI will let
-- anyone build actually encodes to: four teams of eight needs with long names.
-- A transport that cannot carry the biggest legal document is a transport that
-- silently stops syncing for whoever fills the form in.
local MAX_CHUNKS = 8
local CHUNK_GAP = 0.2           -- seconds between chunks; back to back disconnects people
local CHUNK_TIMEOUT = 10        -- seconds before a half-built message is dropped
-- Above CHUNK_BYTES * MAX_CHUNKS, so a legal message can never trip the guard that
-- exists to stop an illegal one.
local MAX_BUFFER_BYTES = 1800   -- per sender, in flight
local MAX_FIELDS = 64           -- fields one payload may split into

local LOGIN_DELAY_MIN = 8       -- seconds; the roster is not loaded before this
local LOGIN_DELAY_MAX = 20
local ANSWER_DELAY_MIN = 2      -- seconds; long enough to hear a better answer first
local ANSWER_DELAY_MAX = 7
local MIN_BROADCAST_GAP = 10    -- seconds between our own full sends
local MIN_REQUEST_GAP = 30      -- seconds between requests, ours and each sender's
local OUT_MAX_PER_10S = 6       -- our own messages
local IN_MAX_PER_10S = 12       -- one sender's messages
local SENDER_MUTE_SEC = 60

Comm.PREFIX, Comm.PROTO = PREFIX, PROTO
Comm.MAX_PAYLOAD = CHUNK_BYTES * MAX_CHUNKS
Comm.CHUNK_TIMEOUT, Comm.MAX_CHUNKS = CHUNK_TIMEOUT, MAX_CHUNKS

--------------------------------------------------------------------------------
-- Pure: escaping and splitting
--------------------------------------------------------------------------------

--[[
Everything outside this class is percent-encoded, which covers ^, ~, |, %, every
control byte and every high byte. Everything a raid leader is likely to type is
inside it and encodes to itself, so the common case costs nothing.

Braces and brackets are in it on purpose. They are not separators, and a template
is mostly {guild}, {teams} and {contacts}: leaving them out tripled the size of
the one field the message is built from and pushed a full document past the wire.
]]
local UNSAFE = "[^%w %-%.,:!%?%(%)'/+#&{}%[%]<>=_*;$@\"]"

function Comm.Escape(s)
    return (tostring(s or ""):gsub(UNSAFE, function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

function Comm.Unescape(s)
    return (tostring(s or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

--[[
Pure. Splits into at most maxFields, the last of which keeps the rest of the
string separators and all.

Bounded on purpose. Two hundred bytes of "^^^^^^" must not build a two hundred
entry table, and the envelope needs the payload's own separators left alone.
]]
function Comm.Split(s, sep, maxFields)
    s = tostring(s or "")
    local out, start = {}, 1
    while #out < (maxFields or MAX_FIELDS) - 1 do
        local at = s:find(sep, start, true)
        if not at then break end
        out[#out + 1] = s:sub(start, at - 1)
        start = at + #sep
    end
    out[#out + 1] = s:sub(start)
    return out
end

-- Pure.
function Comm.Envelope(op, msgid, seq, total, payload)
    return string.format("%d^%s^%d^%d^%d^%s", PROTO, op, msgid, seq, total, payload or "")
end

-- Pure. Returns op, msgid, seq, total, payload -- or nil and a reason, which is
-- counted so /gr status can say what is being thrown away and why.
function Comm.ParseEnvelope(text)
    local f = Comm.Split(text, "^", 6)
    if #f < 6 then return nil, "short" end

    local proto = tonumber(f[1])
    if not proto or proto < 1 or proto > PROTO then return nil, "proto" end
    if not f[2]:match("^[VSRB]$") then return nil, "op" end

    local msgid, seq, total = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    if not msgid or msgid < 0 then return nil, "msgid" end
    if not total or total < 1 or total > MAX_CHUNKS then return nil, "total" end
    if not seq or seq < 1 or seq > total then return nil, "seq" end

    return f[2], math.floor(msgid), math.floor(seq), math.floor(total), f[6]
end

-- Pure.
function Comm.Chunk(payload, chunkBytes)
    payload = tostring(payload or "")
    chunkBytes = chunkBytes or CHUNK_BYTES
    if payload == "" then return { "" } end
    local out = {}
    for i = 1, #payload, chunkBytes do
        out[#out + 1] = payload:sub(i, i + chunkBytes - 1)
    end
    return out
end

--[[
Pure. Feeds one chunk into a sender's buffer. Returns the whole payload once it
is complete, nil while it is not, and nil plus a reason when the buffer is thrown
away.

A different msgid from the same sender replaces the buffer outright rather than
being merged into it: somebody who reconnects mid-send must not leave a stuck
half-message behind.
]]
function Comm.Reassemble(buf, msgid, seq, total, chunk, now)
    if buf.msgid ~= msgid then
        buf.msgid, buf.total = msgid, total
        buf.parts, buf.count, buf.bytes, buf.startedAt = {}, 0, 0, now
    end
    if buf.total ~= total then
        buf.msgid = nil
        return nil, "total-changed"
    end
    if now - (buf.startedAt or now) > CHUNK_TIMEOUT then
        buf.msgid = nil
        return nil, "timeout"
    end
    if buf.parts[seq] then return nil, "duplicate" end

    buf.parts[seq] = chunk
    buf.count = buf.count + 1
    buf.bytes = buf.bytes + #chunk
    if buf.bytes > MAX_BUFFER_BYTES then
        buf.msgid = nil
        return nil, "too-big"
    end
    if buf.count < total then return nil end

    local payload = table.concat(buf.parts)
    buf.msgid = nil
    return payload
end

-- Pure. A token bucket. Returns whether this message is allowed, and records it
-- when it is.
function Comm.Bucket(bucket, now, maxPer, windowSec)
    local kept = {}
    for _, at in ipairs(bucket.stamps or {}) do
        if now - at < windowSec then kept[#kept + 1] = at end
    end
    bucket.stamps = kept
    if #kept >= maxPer then return false end
    kept[#kept + 1] = now
    return true
end

--------------------------------------------------------------------------------
-- Pure: the document on the wire
--------------------------------------------------------------------------------

local function EscapeList(list)
    local out = {}
    for _, item in ipairs(list or {}) do out[#out + 1] = Comm.Escape(item) end
    return table.concat(out, "~")
end

--[[
Pure. Teams and needs go out FLAT rather than nested, each as its own ^ field,
because that keeps the whole format to two levels of separator and one decoder.
A third level is where a hand-rolled format starts needing a parser.

    rev^author^updatedAt^guild^template^teamTemplate^contacts^T^team..^N^need..
    team = id~name~tag~days~active~priority   need = teamId~role~class~count~priority
]]
function Comm.EncodeState(doc)
    local parts = {
        tostring(math.floor(doc.rev or 0)),
        Comm.Escape(doc.author),
        tostring(math.floor(doc.updatedAt or 0)),
        Comm.Escape(doc.guild),
        Comm.Escape(doc.template),
        Comm.Escape(doc.teamTemplate),
        EscapeList(doc.contacts),
        "T",
    }
    for _, team in ipairs(doc.teams or {}) do
        parts[#parts + 1] = table.concat({
            tostring(math.floor(team.id or 0)),
            Comm.Escape(team.name), Comm.Escape(team.tag), Comm.Escape(team.days),
            team.active ~= false and "1" or "0",
            tostring(math.floor(team.priority or 1)),
        }, "~")
    end
    parts[#parts + 1] = "N"
    for _, team in ipairs(doc.teams or {}) do
        for _, need in ipairs(ns.Teams.Sorted(team.needs)) do
            parts[#parts + 1] = table.concat({
                tostring(math.floor(team.id or 0)),
                Comm.Escape(need.role), Comm.Escape(need.class),
                tostring(math.floor(need.count or 1)),
                tostring(math.floor(need.priority or 1)),
            }, "~")
        end
    end
    return table.concat(parts, "^")
end

-- Pure. Returns a raw document, or nil and a reason. Nothing here trusts a value;
-- Doc.Sanitize does the trimming and the range checks afterwards.
function Comm.DecodeState(payload)
    local f = Comm.Split(payload, "^", MAX_FIELDS)
    if #f < 8 then return nil, "short" end

    local doc = {
        rev = tonumber(f[1]),
        author = Comm.Unescape(f[2]),
        updatedAt = tonumber(f[3]),
        guild = Comm.Unescape(f[4]),
        template = Comm.Unescape(f[5]),
        teamTemplate = Comm.Unescape(f[6]),
        contacts = {},
        teams = {},
    }
    if f[7] ~= "" then
        for _, name in ipairs(Comm.Split(f[7], "~", 8)) do
            doc.contacts[#doc.contacts + 1] = Comm.Unescape(name)
        end
    end

    local byId, section = {}, nil
    for i = 8, #f do
        local field = f[i]
        if field == "T" or field == "N" then
            section = field
        elseif section == "T" then
            local t = Comm.Split(field, "~", 7)
            if #t >= 6 then
                local team = {
                    id = tonumber(t[1]),
                    name = Comm.Unescape(t[2]), tag = Comm.Unescape(t[3]),
                    days = Comm.Unescape(t[4]), active = t[5] == "1",
                    priority = tonumber(t[6]),
                    needs = {},
                }
                doc.teams[#doc.teams + 1] = team
                if team.id then byId[team.id] = team end
            end
        elseif section == "N" then
            local n = Comm.Split(field, "~", 6)
            if #n >= 5 then
                local team = byId[tonumber(n[1])]
                if team then
                    team.needs[#team.needs + 1] = {
                        role = Comm.Unescape(n[2]), class = Comm.Unescape(n[3]),
                        count = tonumber(n[4]), priority = tonumber(n[5]),
                    }
                end
            end
        end
    end

    if not section then return nil, "no sections" end
    return doc
end

-- Pure. "I hold rev N", and the same grammar for a request.
function Comm.EncodeVersion(doc)
    return string.format("%d^%s^%d^%s",
        math.floor(doc.rev or 0), Comm.Escape(doc.author),
        math.floor(doc.updatedAt or 0), Comm.Escape(doc.hash))
end

function Comm.DecodeVersion(payload)
    local f = Comm.Split(payload, "^", 4)
    if #f < 3 then return nil, "short" end
    return {
        rev = tonumber(f[1]), author = Comm.Unescape(f[2]),
        updatedAt = tonumber(f[3]), hash = Comm.Unescape(f[4] or ""),
    }
end

-- Pure. The bark text is deliberately NOT sent: it is derivable from the rev, and
-- everyone is converging on that anyway. len travels so a reader can see the line
-- was cut, rev so they can see it went out on a stale message.
function Comm.EncodeBark(who, at, channel, rev, len)
    return string.format("%s^%d^%s^%d^%d",
        Comm.Escape(who), math.floor(at), Comm.Escape(channel), math.floor(rev),
        math.floor(len))
end

function Comm.DecodeBark(payload)
    local f = Comm.Split(payload, "^", 5)
    if #f < 5 then return nil, "short" end
    return {
        who = Comm.Unescape(f[1]), at = tonumber(f[2]),
        channel = Comm.Unescape(f[3]), rev = tonumber(f[4]), len = tonumber(f[5]),
    }
end

--------------------------------------------------------------------------------
-- The client
--------------------------------------------------------------------------------

--[[
C_ChatInfo is where these moved and where they will stay; the bare globals are the
legacy names 20506 most likely still has. Nothing in this repo has ever called
either, so both are tried and which one answered is reported by /gr probe.
]]
local function Resolve()
    local C = _G.C_ChatInfo
    local send, sendHow, register, registerHow

    if C and type(C.SendAddonMessage) == "function" then
        send = function(prefix, msg, channel) return C.SendAddonMessage(prefix, msg, channel) end
        sendHow = "C_ChatInfo.SendAddonMessage"
    elseif type(_G.SendAddonMessage) == "function" then
        send, sendHow = _G.SendAddonMessage, "SendAddonMessage"
    end

    if C and type(C.RegisterAddonMessagePrefix) == "function" then
        register, registerHow = C.RegisterAddonMessagePrefix, "C_ChatInfo.RegisterAddonMessagePrefix"
    elseif type(_G.RegisterAddonMessagePrefix) == "function" then
        register, registerHow = _G.RegisterAddonMessagePrefix, "RegisterAddonMessagePrefix"
    end

    return send, register, sendHow, registerHow
end

Comm.buffers = {}       -- sender -> reassembly buffer
Comm.out = { stamps = {} }
Comm.inbound = {}       -- sender -> { bucket, mutedUntil, lastRequestAt }
Comm.nextMsgID = 1

function Comm.Init()
    local send, register, sendHow, registerHow = Resolve()
    Comm.send, Comm.register = send, register
    Comm.sendHow, Comm.registerHow = sendHow, registerHow
    Comm.available = send ~= nil

    if register and ns.db.settings.sync.registerPrefix then
        local ok = pcall(register, PREFIX)
        Comm.registered = ok
    else
        Comm.registered = false
    end

    if not Comm.available then
        ns.Print("|cffff4444sync is off|r: this client has no addon message API. "
            .. "Your edits will not reach anyone. /gr probe for detail.")
        ns.Log.Add("err", "Comm", "no addon message API on this client")
    end

    -- A half-built message that never finishes is a wait on the client, so it has
    -- a timeout and something that sweeps it.
    Comm.sweeper = C_Timer.NewTicker(5, Comm.Sweep)
end

function Comm.Sweep()
    local now = ns.Now()
    for sender, buf in pairs(Comm.buffers) do
        if buf.msgid and now - (buf.startedAt or now) > CHUNK_TIMEOUT then
            Comm.buffers[sender] = nil
            ns.Log.Capture("warn", "Comm", sender .. " stopped mid-message", now)
        end
    end
end

local function Count(reason)
    ns.db.stats.rejected[reason] = (ns.db.stats.rejected[reason] or 0) + 1
end

-- Returns ok, reason. Over budget is DROPPED with a line, never queued: a queue
-- that cannot drain is what disconnects people, and the next offer recovers it.
function Comm.Send(op, payload, msgid, seq, total)
    if not Comm.available then return false, "no addon message API on this client" end
    if not ns.db.settings.sync.enabled then return false, "sync is turned off" end
    if not (IsInGuild and IsInGuild()) then return false, "you are not in a guild" end

    if not Comm.Bucket(Comm.out, ns.Now(), OUT_MAX_PER_10S, 10) then
        ns.Log.Add("warn", "Comm", "dropped an outgoing message", "over the send budget")
        return false, "sending too fast; it will go out with the next offer"
    end

    local text = Comm.Envelope(op, msgid or 0, seq or 1, total or 1, payload)
    if #text > WIRE_MAX then
        ns.Log.Add("err", "Comm", "refused to send an oversized message", tostring(#text))
        return false, "message too long for one addon message"
    end

    local ok = pcall(Comm.send, PREFIX, text, "GUILD")
    if not ok then return false, "the client refused the send" end
    ns.db.stats.sent = (ns.db.stats.sent or 0) + 1
    return true
end

function Comm.SendChunked(op, payload)
    local chunks = Comm.Chunk(payload, CHUNK_BYTES)
    if #chunks > MAX_CHUNKS then
        return false, string.format("the message is %d bytes; the limit is %d",
            #payload, Comm.MAX_PAYLOAD)
    end
    local msgid = Comm.nextMsgID
    Comm.nextMsgID = Comm.nextMsgID + 1

    local ok, reason = Comm.Send(op, chunks[1], msgid, 1, #chunks)
    if not ok then return false, reason end
    for i = 2, #chunks do
        -- Spaced out: the client disconnects a client that sends back to back.
        C_Timer.After(CHUNK_GAP * (i - 1), function()
            Comm.Send(op, chunks[i], msgid, i, #chunks)
        end)
    end
    return true
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

--[[
Everything a message must clear before any of it is stored or drawn, in order.
Returns the short sender name and their rankIndex, or nil and a reason.

The second check is the one that matters most: only GUILD. That single line
removes every attack that does not start with being in the guild already.
]]
function Comm.Accept(prefix, text, distribution, sender, now)
    if prefix ~= PREFIX then return nil, "prefix" end
    if distribution ~= "GUILD" then return nil, "distribution" end
    if type(text) ~= "string" or #text > WIRE_MAX then return nil, "size" end
    if not (IsInGuild and IsInGuild()) then return nil, "not in a guild" end

    local short = ns.Roster.Short(sender)
    if short == "" then return nil, "sender" end

    local state = Comm.inbound[short]
    if not state then
        state = { bucket = { stamps = {} }, mutedUntil = 0, lastRequestAt = 0 }
        Comm.inbound[short] = state
    end
    if now < (state.mutedUntil or 0) then return nil, "muted" end
    if not Comm.Bucket(state.bucket, now, IN_MAX_PER_10S, 10) then
        state.mutedUntil = now + SENDER_MUTE_SEC
        ns.Log.Add("warn", "Comm", short .. " is talking too fast",
            string.format("ignored for %ds", SENDER_MUTE_SEC))
        return nil, "flood"
    end

    -- The rank that counts is the one WE read off the roster for them. A rank
    -- claimed inside the message is a claim.
    local rank = ns.Roster.RankOf(ns.Roster.byName, short, ns.Roster.UNKNOWN_RANK)
    return short, rank, state
end

function Comm.OnAddonMessage(prefix, text, distribution, sender)
    local now = ns.Now()
    -- Accept's second return is the rank when it says yes and the reason when it
    -- says no, so the two are unpacked under names that say which.
    local short, rankOrReason, state = Comm.Accept(prefix, text, distribution, sender, now)
    if not short then
        if rankOrReason then Count(rankOrReason) end
        return
    end
    local rank = rankOrReason
    ns.db.stats.received = (ns.db.stats.received or 0) + 1

    local op, msgid, seq, total, payload = Comm.ParseEnvelope(text)
    if not op then
        Count(msgid or "envelope")
        return
    end

    -- Only S is ever chunked; the others are one message each.
    if total > 1 then
        local buf = Comm.buffers[short]
        if not buf then buf = {}; Comm.buffers[short] = buf end
        local whole, why = Comm.Reassemble(buf, msgid, seq, total, payload, now)
        if not whole then
            if why then Count(why) end
            return
        end
        payload = whole
    end

    Comm.Peer(short, rank, now)
    -- /gr probe's loopback is waiting to hear anything at all come back.
    if ns.Probe and ns.Probe.Heard then ns.Probe.Heard(short) end

    if op == "S" then
        Comm.OnState(short, rank, payload, now)
    elseif op == "V" then
        Comm.OnVersion(short, payload, now)
    elseif op == "R" then
        Comm.OnRequest(short, payload, now, state)
    elseif op == "B" then
        Comm.OnBark(short, payload, now)
    end
end

function Comm.Peer(short, rank, now)
    ns.db.peers[short] = ns.db.peers[short] or {}
    local peer = ns.db.peers[short]
    peer.seenAt, peer.rank = now, rank
end

local function RememberRev(rev)
    -- Kept whether or not the document was accepted: an edit made after seeing a
    -- higher rev still has to outrank it.
    if (tonumber(rev) or 0) > (ns.db.highestSeenRev or 0) then
        ns.db.highestSeenRev = math.floor(rev)
    end
end

function Comm.OnState(short, rank, payload, now)
    if not ns.Roster.MayAuthor(rank, ns.db.settings.authorRankIndex) then
        Count("rank")
        ns.Log.Capture("warn", "Comm", short .. " sent a message but is not a raid leader here", now)
        return
    end

    local raw, why = Comm.DecodeState(payload)
    if not raw then
        Count(why or "decode")
        return
    end

    local doc, reason = ns.Doc.Sanitize(raw, short, ns.Roster.GuildName(), now)
    if not doc then
        Count(reason or "sanitize")
        ns.Log.Capture("warn", "Comm", "dropped a message from " .. short, now)
        return
    end

    RememberRev(doc.rev)
    ns.db.peers[short].rev, ns.db.peers[short].hash = doc.rev, doc.hash

    local merged, outcome = ns.Doc.Merge(ns.db.doc, doc)
    ns.db.doc = merged
    if outcome == "took-remote" then
        ns.Log.Add("doc", "Comm", string.format("took %s's rev %d", short, doc.rev),
            ns.Doc.Summary(doc, now))
        Comm.CancelAnswer()
        if ns.UI then ns.UI.Refresh() end
    else
        ns.Log.Capture("info", "Comm",
            string.format("%s sent rev %d; %s", short, doc.rev,
                outcome == "same" and "same as ours" or "ours is newer"), now)
        if outcome == "kept-local" then Comm.ScheduleAnswer(now) end
    end
end

function Comm.OnVersion(short, payload, now)
    local theirs = Comm.DecodeVersion(payload)
    if not theirs then
        Count("version")
        return
    end
    RememberRev(theirs.rev)
    ns.db.peers[short].rev, ns.db.peers[short].hash = theirs.rev, theirs.hash

    -- Only answer if we are actually ahead. In a guild that already agrees, eight
    -- officers logging in produce eight offers and not one full send.
    if ns.Doc.Compare(ns.db.doc, theirs) == "local" and (ns.db.doc.rev or 0) > 0 then
        Comm.ScheduleAnswer(now)
    else
        Comm.CancelAnswer()
    end
end

function Comm.OnRequest(short, payload, now, state)
    if now - (state.lastRequestAt or 0) < MIN_REQUEST_GAP then
        Count("request-flood")
        return
    end
    state.lastRequestAt = now
    Comm.OnVersion(short, payload, now)
end

function Comm.OnBark(short, payload, now)
    local bark = Comm.DecodeBark(payload)
    if not bark then
        Count("bark")
        return
    end
    -- A message claiming somebody else barked is a message lying about it.
    if ns.Roster.Short(bark.who) ~= short then
        Count("bark-spoof")
        return
    end
    if not bark.at or bark.at > now + 300 or bark.at < now - 86400 then
        Count("bark-time")
        return
    end

    local inserted = ns.Bark.Insert(ns.db.barks, {
        who = short, at = math.floor(bark.at),
        channel = ns.Util.Clean(bark.channel, 32),
        rev = math.floor(bark.rev or 0), len = math.floor(bark.len or 0),
    }, ns.Bark.MAX_BARKS)

    if inserted then
        ns.db.peers[short].barkedAt = bark.at
        ns.Log.Add("remote", "Comm", short .. " barked",
            string.format("%s, rev %d, %d characters",
                ns.Util.Clean(bark.channel, 32), bark.rev or 0, bark.len or 0))
        if ns.UI then ns.UI.Refresh() end
    end
end

--------------------------------------------------------------------------------
-- Speaking up
--------------------------------------------------------------------------------

function Comm.Broadcast()
    local doc = ns.db.doc
    if (doc.rev or 0) == 0 then return false, "there is no message to send yet" end

    local now = ns.Now()
    if now - (Comm.lastBroadcastAt or 0) < MIN_BROADCAST_GAP then
        -- Coalesce rather than refuse: somebody mashing Save should end up with
        -- one send, not none.
        Comm.dirty = true
        C_Timer.After(MIN_BROADCAST_GAP, function()
            if Comm.dirty then
                Comm.dirty = false
                Comm.Broadcast()
            end
        end)
        return true, "queued behind the last send"
    end

    local payload = Comm.EncodeState(doc)
    if #payload > Comm.MAX_PAYLOAD then
        return false, string.format("the message is %d bytes and the limit is %d. "
            .. "Shorten the team names, or ask for fewer roles.",
            #payload, Comm.MAX_PAYLOAD)
    end

    local ok, reason = Comm.SendChunked("S", payload)
    if ok then
        Comm.lastBroadcastAt = now
        Comm.dirty = false
        ns.Log.Add("doc", "Comm", "sent rev " .. doc.rev .. " to the guild",
            string.format("%d bytes", #payload))
    end
    return ok, reason
end

function Comm.Offer()
    return Comm.Send("V", Comm.EncodeVersion(ns.db.doc), 0, 1, 1)
end

function Comm.Request()
    local now = ns.Now()
    if now - (Comm.lastRequestAt or 0) < MIN_REQUEST_GAP then
        return false, string.format("already asked; give it %ds",
            MIN_REQUEST_GAP - (now - Comm.lastRequestAt))
    end
    Comm.lastRequestAt = now
    return Comm.Send("R", Comm.EncodeVersion(ns.db.doc), 0, 1, 1)
end

function Comm.AnnounceBark(who, at, channel, rev, len)
    return Comm.Send("B", Comm.EncodeBark(who, at, channel, rev, len), 0, 1, 1)
end

--[[
Jitter, not an elected responder. An elected responder breaks precisely when that
officer is offline, and then a newcomer stays stale forever with nobody noticing.

Everyone who is ahead schedules an answer and cancels it the moment they hear one
that is as good as theirs, so in practice exactly one send happens.
]]
function Comm.ScheduleAnswer(now)
    if Comm.answerAt and now < Comm.answerAt then return end
    local delay = ANSWER_DELAY_MIN + math.random() * (ANSWER_DELAY_MAX - ANSWER_DELAY_MIN)
    Comm.answerAt = now + delay
    C_Timer.After(delay, function()
        if not Comm.answerAt then return end
        Comm.answerAt = nil
        Comm.Broadcast()
    end)
end

function Comm.CancelAnswer()
    Comm.answerAt = nil
end

-- One small offer at login, after a delay long enough for the roster to arrive:
-- GuildRoster() is asynchronous and throttled around ten seconds, and a rank we
-- have not read yet is a rank that can do nothing.
function Comm.ScheduleLogin()
    if not ns.db.settings.sync.onLogin then return end
    local delay = LOGIN_DELAY_MIN + math.random() * (LOGIN_DELAY_MAX - LOGIN_DELAY_MIN)
    C_Timer.After(delay, function()
        ns.Roster.Refresh(true)
        C_Timer.After(2, function()
            ns.Roster.Read()
            Comm.Offer()
        end)
    end)
end

function Comm.Status()
    local sent, received = ns.db.stats.sent or 0, ns.db.stats.received or 0
    local rejected = 0
    for _, n in pairs(ns.db.stats.rejected or {}) do rejected = rejected + n end
    return {
        available = Comm.available,
        how = Comm.sendHow or "nothing",
        registered = Comm.registered,
        sent = sent, received = received, rejected = rejected,
    }
end
