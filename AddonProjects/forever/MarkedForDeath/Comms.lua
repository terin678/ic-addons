local addonName, ns = ...

--[[
Comms: what Marked For Death clients say to each other, over LibICComm.

Owned by lane F (comms and lead). The top half is pure (no client call, ever; the cases
in Tests_Comms.lua run it headless). The bottom half is the frame module: it calls the
client only inside functions started from the ns.OnReady hook, which returns early on
IC_HEADLESS, and every public function below answers safely before that has run.

What travels (every message is a LibICComm table; LibICComm adds `f`, the sender's guid):

    st  state: { lead = { n, a, b }, k, h, c }   my Raid Lead designation (name, when it was
        set, who set it), and the instance key, digest and count of the rules I hold there.
        Sent on joining a group, on a hello from someone new, and after any change.
    rq  request: { to, k, h }   "send your rules for k". Only the Raid Lead asks everyone,
        and everyone asks only the Raid Lead, so a raid of 25 does not make 600 requests.
    rd  rules: { k, h, doc }    one instance's rules in share format v2 (Rules.ToJSON's
        document). Broadcast, so every client collects the same contributions.
    pl  plan: { k, h, s }       the Raid Lead's assignments, so every assignment panel
        agrees. Taken only from the client every other client also names as Raid Lead.

Merged rules are session state: nothing received is ever written to the saved rules.

Raid behaviour of addon messages is not yet probed (spec P9). Everything here degrades:
with no channel the Raid Lead falls back to the designation, then the group leader, and
each client plans from its own rules. Rules, plans and requests go only out of combat;
what was held is sent when combat ends.

Public, for other lanes:

    ns.Comms.Lead()                 the Lead.Resolve result in force
    ns.Comms.IsLead()               whether this client is the Raid Lead (death calls, announce)
    ns.Comms.Known()                whether IsLead is an answer yet (false before the roster is read)
    ns.Comms.Me()                   the player's full name, as the merge's sources name it
    ns.Comms.ActiveRules(key)       merged rule set for an instance key, and { [ruleKey] = owner }
    ns.Comms.RulesChanged()         call after editing the saved rules; re-advertises them
    ns.Comms.PublishPlan(key, steps)  the Raid Lead sends MarkPlan.Steps; true or false, why
    ns.Comms.Published(key)         { from, at, steps } or nil
    ns.Comms.Versions()             { [name] = { version, at, isMe } }
    ns.Comms.Durability()           { [name] = { percent, broken, at, source } }
    ns.Comms.RequestDurability()    true, or false and why
    ns.Comms.OwnDurability()        percent, broken; nil when nothing worn wears
    ns.Comms.Status()               { channel, why, users }
    ns.Comms.Listen(key, fn)        fn(kind) on "lead", "peers", "rules", "plan", "durability"
    ns.Comms.Unlisten(key)
]]

ns.Comms = ns.Comms or {}
local Comms = ns.Comms
local Lead, Rules, Seats = ns.Lead, ns.Rules, ns.Seats
local Util = LibStub("LibICUtil-1.0")
local JSON = LibStub("LibICJSON-1.0")
local Comm = LibStub("LibICComm-1.0")

Comms.PREFIX = "MarkedForDeath"     -- LibICComm prefix, 16 characters at most
-- LibDurability's prefix ("Durability", in the copy installed on this machine), then the
-- one the Anniversary addon used. Answers are read on both; requests go on the first.
Comms.DURABILITY_PREFIXES = { "Durability", "LibDRBLT" }
Comms.MAX_RULE_BYTES = 3500         -- bytes of compact JSON; about 14 frames, ~20 s of budget
Comms.MAX_STEPS = 8                 -- one step per raid icon
Comms.REQUEST_QUIET = 10            -- seconds before asking for, or answering, the same rules again
Comms.STATE_SETTLE = 2              -- seconds a burst of changes waits before one state message
Comms.ROSTER_SETTLE = 1             -- seconds a burst of roster events waits before one read
Comms.DURABILITY_QUIET = 10         -- seconds between our own durability requests
Comms.DURABILITY_ANSWER_QUIET = 4   -- seconds between our answers, as LibDurability itself
Comms.DURABILITY_WAIT = 3           -- seconds /mfd durability waits for answers
Comms.MAX_TEXT = 48                 -- bytes in a name, a seat label or a version

-- Kinds that wait for the end of combat (spec: rule merge and the published plan OOC only).
Comms.OOC_ONLY = { rq = true, rd = true, pl = true }

local lower, format, byte = string.lower, string.format, string.byte

--------------------------------------------------------------------------------
-- Pure: text checks and digests
--------------------------------------------------------------------------------

-- A short text from another client that may be shown in chat or a list: a string of 1 to
-- MAX_TEXT bytes with no escape (|) and no line break. Returns it, or nil.
function Comms.Text(v)
    if type(v) ~= "string" or v == "" or #v > Comms.MAX_TEXT then return nil end
    if v:find("[|\r\n]") then return nil end
    return v
end

local function Hash(text)
    local h = 5381
    for i = 1, #text do h = (h * 33 + byte(text, i)) % 4294967296 end
    return format("%08x", h)
end
Comms.Hash = Hash

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- True for an instance key that may travel: "open" or "i:<n>". A "legacy:<zone>" set is
-- an Anniversary file not yet moved to a Forever instance, and stays on its own client.
function Comms.SharedKey(key)
    return Rules.IsInstanceKey(key) and not Rules.IsLegacy(key)
end

--[[
key: an instance key; set: that instance's rules. Returns doc (the share format v2
document as a table, ready to travel), its digest and the rule count; or nil and why when
the key may not travel or the set is too big for addon messages. Two sets that would
export the same file have the same digest, whatever order their keys were added in.
]]
function Comms.PackRules(key, set)
    if not Comms.SharedKey(key) then return nil, "rules under " .. tostring(key) .. " are not shared" end
    local text, err = Rules.ToJSON({ [key] = set or {} })
    if not text then return nil, err end
    local doc = JSON.Decode(text)
    if type(doc) ~= "table" then return nil, "the rules could not be packed" end
    local compact = JSON.Encode(doc, { compact = true })
    if not compact then return nil, "the rules could not be packed" end
    if #compact > Comms.MAX_RULE_BYTES then
        return nil, "too many rules to send in addon messages (" .. #compact .. " bytes); share them as a file"
    end
    return doc, Hash(compact), Count(set)
end

-- The digest and count alone, for the state message. A set too big to send still has a
-- digest, so a change to it is still noticed; it is simply never sent.
function Comms.Digest(key, set)
    local text = Rules.ToJSON({ [key] = set or {} })
    local doc = text and JSON.Decode(text)
    local compact = doc and JSON.Encode(doc, { compact = true }) or ""
    return Hash(compact), Count(set)
end

--[[
doc: what an rd message carried. key: the instance key it claims. Returns that instance's
rule set (possibly empty), or nil and why. Read through Rules.FromJSON, so a rule from
another client passes exactly the checks a pasted file does, and one bad rule refuses the
whole message. Only format 2 travels, and only the one instance the message names.
]]
function Comms.UnpackRules(doc, key)
    if not Comms.SharedKey(key) then return nil, "not an instance key that is shared" end
    if type(doc) ~= "table" then return nil, "no rules in the message" end
    local text = JSON.Encode(doc, { compact = true })
    if not text then return nil, "the rules could not be read" end
    if #text > Comms.MAX_RULE_BYTES * 2 then return nil, "the message is too big" end
    local byInstance, version = Rules.FromJSON(text)
    if not byInstance then return nil, version end
    if version ~= Rules.SHARE_VERSION then return nil, "only format " .. Rules.SHARE_VERSION .. " is taken from other clients" end
    for instanceKey in pairs(byInstance) do
        if instanceKey ~= key then return nil, "the message holds rules for another instance" end
    end
    return byInstance[key] or {}
end

--[[
contributions: { [owner] = rule set } for one instance, the player's own included under
their own name. leadName: the Raid Lead's name, or nil. Returns the merged set, sources
({ [ruleKey] = owner }) and the order owners were read in.

The Raid Lead's rules come first and win every mob they name; everyone else fills gaps in
name order. The player's own rules get no special place, which is what lets every client
build the same set from the same contributions, whatever order they arrived in. Nothing
passed in is changed.
]]
function Comms.Merge(contributions, leadName)
    contributions = contributions or {}
    local order = {}
    if leadName and type(contributions[leadName]) == "table" then order[1] = leadName end
    for _, owner in ipairs(Util.SortedKeys(contributions)) do
        if owner ~= leadName and type(contributions[owner]) == "table" then order[#order + 1] = owner end
    end
    local merged, sources = {}, {}
    for _, owner in ipairs(order) do
        merged = Rules.Merge(merged, contributions[owner], owner)
        for key in pairs(merged) do
            if sources[key] == nil then sources[key] = owner end
        end
    end
    return merged, sources, order
end

--------------------------------------------------------------------------------
-- Pure: checking what arrives
--------------------------------------------------------------------------------

local function Whole(v, lo)
    return type(v) == "number" and v % 1 == 0 and v >= (lo or 0)
end

local function Digest(v)
    return type(v) == "string" and v:match("^%x%x%x%x%x%x%x%x$") ~= nil
end

-- A designation as it travels: { n = name or nil, a = time set, b = who set it }.
-- Returns { name, at, by } or nil and why.
function Comms.CheckDesignation(d)
    if type(d) ~= "table" then return nil, "no designation" end
    local name = d.n
    if name ~= nil and not Comms.Text(name) then return nil, "a bad Raid Lead name" end
    if not Whole(d.a) then return nil, "a designation needs the time it was set" end
    return { name = name, at = d.a, by = Comms.Text(d.b) }
end

-- An st message. Returns { lead, key, hash, count } (lead and key optional), or nil and why.
function Comms.CheckState(msg)
    if type(msg) ~= "table" then return nil, "not a message" end
    local out = {}
    if msg.lead ~= nil then
        local lead, why = Comms.CheckDesignation(msg.lead)
        if not lead then return nil, why end
        out.lead = lead
    end
    if msg.k ~= nil then
        if not Comms.SharedKey(msg.k) then return nil, "a bad instance key" end
        if not Digest(msg.h) or not Whole(msg.c) then return nil, "a bad rules digest" end
        out.key, out.hash, out.count = msg.k, msg.h, msg.c
    end
    return out
end

-- An rq message. Returns { to, key, hash } or nil and why.
function Comms.CheckRequest(msg)
    if type(msg) ~= "table" then return nil, "not a message" end
    if type(msg.to) ~= "string" or msg.to == "" or #msg.to > 64 then return nil, "a request names nobody" end
    if not Comms.SharedKey(msg.k) then return nil, "a bad instance key" end
    if msg.h ~= nil and not Digest(msg.h) then return nil, "a bad rules digest" end
    return { to = msg.to, key = msg.k, hash = msg.h }
end

--[[
key: an instance key; steps: MarkPlan.Steps output ({ icon, name, owner, seatLabel,
borrowed, ... }). Returns the pl message ({ t, k, h, s }), or nil and why. Unit tokens and
guids are this client's own and do not travel.
]]
function Comms.PackPlan(key, steps)
    if not Comms.SharedKey(key) then return nil, "not an instance key that is shared" end
    if type(steps) ~= "table" then return nil, "no plan" end
    local s = {}
    for _, step in ipairs(steps) do
        if type(step) == "table" and type(step.icon) == "number" then
            local row = { i = step.icon, n = step.name, l = step.seatLabel, b = step.borrowed and true or nil }
            -- false (nobody can do it) is an answer, so it is kept; `and/or` would drop it.
            if type(step.owner) == "string" or type(step.owner) == "boolean" then row.o = step.owner end
            s[#s + 1] = row
        end
    end
    if #s > Comms.MAX_STEPS then return nil, "more steps than raid icons" end
    local text = JSON.Encode(s, { compact = true })
    if not text then return nil, "the plan could not be packed" end
    return { t = "pl", k = key, h = Hash(key .. text), s = s }
end

--[[
A pl message. Returns { key, hash, steps } with steps in MarkPlan's shape ({ icon,
iconName, name, owner, seatLabel, borrowed }), or nil and why. One bad step refuses the
plan: an assignment panel showing half a plan looks complete and is not.
]]
function Comms.CheckPlan(msg)
    if type(msg) ~= "table" then return nil, "not a message" end
    if not Comms.SharedKey(msg.k) then return nil, "a bad instance key" end
    if not Digest(msg.h) then return nil, "a bad plan digest" end
    if type(msg.s) ~= "table" then return nil, "no steps" end
    if #msg.s > Comms.MAX_STEPS then return nil, "more steps than raid icons" end
    local steps, seen = {}, {}
    for index, row in ipairs(msg.s) do
        if type(row) ~= "table" then return nil, "step " .. index .. " is not a step" end
        local icon = row.i
        if not Whole(icon, 1) or icon > 8 then return nil, "step " .. index .. " has no raid icon" end
        if seen[icon] then return nil, "two steps use " .. Seats.ICON_NAMES[icon] end
        seen[icon] = true
        local name, why = Rules.CheckName(row.n)
        if not name then return nil, "step " .. index .. ": " .. why end
        local owner = row.o
        if owner ~= nil and type(owner) ~= "boolean" and not Comms.Text(owner) then
            return nil, "step " .. index .. " has a bad owner"
        end
        if row.l ~= nil and not Comms.Text(row.l) then return nil, "step " .. index .. " has a bad seat" end
        steps[#steps + 1] = {
            icon = icon, iconName = Seats.ICON_NAMES[icon], name = name, owner = owner,
            seatLabel = row.l, borrowed = row.b == true or nil,
        }
    end
    return { key = msg.k, hash = msg.h, steps = steps }
end

--------------------------------------------------------------------------------
-- Pure: when to ask, answer and send
--------------------------------------------------------------------------------

--[[
Whether to ask a sender for their rules after their state message. ctx:
    count      how many rules they say they hold
    hash       their digest
    have       the digest already held from them for that key, or nil
    iAmLead, senderIsLead
    askedAt    when their rules at this digest were last asked for, or nil
    now
Returns "ask", "empty" (record an empty set, nothing to fetch) or nil (nothing to do).
]]
function Comms.WantRules(ctx)
    if ctx.have == ctx.hash then return nil end
    if ctx.count == 0 then return "empty" end
    if not (ctx.iAmLead or ctx.senderIsLead) then return nil end
    if ctx.askedAt and ctx.now - ctx.askedAt < Comms.REQUEST_QUIET then return nil end
    return "ask"
end

-- Whether to answer a request. ctx: me (my guid), key (my instance key), answeredAt (when
-- I last sent these rules, or nil), now. Asked for an older digest, the current rules go.
function Comms.ShouldAnswer(request, ctx)
    if type(request) ~= "table" or request.to ~= ctx.me or ctx.me == nil then return false end
    if request.key ~= ctx.key then return false end
    if ctx.answeredAt and ctx.now - ctx.answeredAt < Comms.REQUEST_QUIET then return false end
    return true
end

-- kind: a message type. Returns true, or false and why. Rules, requests and plans wait
-- for the end of combat; a state message (the designation, a digest) goes at once.
function Comms.MaySend(kind, inCombat)
    if Comms.OOC_ONLY[kind] and inCombat then return false, "held until combat ends" end
    return true
end

--------------------------------------------------------------------------------
-- Pure: durability and names
--------------------------------------------------------------------------------

-- LibDurability's answer, "<percent>,<broken>". Returns percent (0 to 100), broken; or nil.
function Comms.ParseDurability(text)
    if type(text) ~= "string" then return nil end
    local percent, broken = text:match("^(%d+),(%d+)$")
    percent, broken = tonumber(percent), tonumber(broken)
    if not percent or not broken then return nil end
    return math.min(percent, 100), broken
end

-- rows: { { current, max }, ... } for each worn slot (nil rows skipped). Returns the
-- whole set's percent and how many items are broken, as LibDurability counts them; nil
-- when nothing worn has durability.
function Comms.DurabilityOf(rows)
    local cur, max, broken = 0, 0, 0
    for _, row in pairs(rows or {}) do
        local c, m = row[1], row[2]
        if type(c) == "number" and type(m) == "number" and m > 0 then
            cur, max = cur + c, max + m
            if c == 0 then broken = broken + 1 end
        end
    end
    if max == 0 then return nil end
    return cur / max * 100, broken
end

--[[
sender: the name CHAT_MSG_ADDON gave. members: a LibICGroup snapshot's members. Returns
the member's full name (Lead.Id) when one matches, else the sender as given. Matches the
full name, then the first name when only one member has it, then the part before a
"-Realm" (other clients' style), so an answer from anywhere lands on one row.
]]
function Comms.MatchSender(sender, members)
    if type(sender) ~= "string" or sender == "" then return nil end
    local want = lower(sender)
    local plain = lower(sender:match("^([^%-]+)%-") or sender)
    local first, count = nil, 0
    for _, member in ipairs(members or {}) do
        if type(member) == "table" then
            if type(member.display) == "string" and lower(member.display) == want then return Lead.Id(member) end
            if type(member.name) == "string" and (lower(member.name) == want or lower(member.name) == plain) then
                count = count + 1
                first = first or member
            end
        end
    end
    if count == 1 then return Lead.Id(first) end
    return sender
end

--[[
The /mfd peers report. input:
    users     { { name, version, isMe }, ... }
    version   this client's version
    status    { channel, why }
    counts    { [owner] = rules merged from them } (the player excluded)
    lead      the Lead.Resolve result
    key       the instance key in force
Returns lines, without colour codes except where a line says so.
]]
function Comms.PeerLines(input)
    local lines = {}
    local status = input.status or {}
    if status.channel then
        lines[#lines + 1] = "Addon messages go on " .. status.channel .. "."
    else
        lines[#lines + 1] = "|cffff9900Addon messages are not going out:|r " .. tostring(status.why or "not started")
            .. ". Each client plans from its own rules."
    end
    lines[#lines + 1] = Lead.Describe(input.lead)
    local users = {}
    for _, u in ipairs(input.users or {}) do users[#users + 1] = u end
    table.sort(users, function(a, b) return tostring(a.name) < tostring(b.name) end)
    local parts = {}
    for _, u in ipairs(users) do
        local version = u.version and ("v" .. u.version) or "version unknown"
        if u.version and input.version and Comm.Newer(u.version, input.version) then
            version = "|cff66ff66" .. version .. " (newer)|r"
        end
        parts[#parts + 1] = tostring(u.name) .. (u.isMe and " (you)" or "") .. " " .. version
    end
    lines[#lines + 1] = #users .. " running Marked For Death: " .. (#parts > 0 and table.concat(parts, ", ") or "none heard")
    local owners = Util.SortedKeys(input.counts or {})
    for _, owner in ipairs(owners) do
        lines[#lines + 1] = "|cffffcc66" .. input.counts[owner] .. " rules merged from " .. owner
            .. " for " .. tostring(input.key) .. "|r"
    end
    return lines
end

--------------------------------------------------------------------------------
-- The client
--------------------------------------------------------------------------------

local Group = LibStub("LibICGroup-1.0")
local Restrict = LibStub("LibICRestrict-1.0")

local RED, AMBER, CLOSE = "|cffff4444", "|cffff9900", "|r"

local comm                  -- the LibICComm sender, once started
local snapshot = { kind = "solo", members = {} }
local lead = Lead.Resolve({ kind = "solo" })
local designation = { at = 0 }   -- { name, at, by }; at is session-only, 0 for one loaded from disk
local users = {}            -- [guid] = true: heard running MFD this group session
local heard = {}            -- [guid] = { name, key, hash, count }: their last state
local contributions = {}    -- [guid] = { name, key, hash, set }
local askedAt = {}          -- [guid .. hash] = time
local answeredAt = nil      -- when our rules last went out
local answeredHash = nil
local published = {}        -- [key] = { from, at, hash, steps }
local sentPlan = {}         -- [key] = hash we last published
local durability = {}       -- [name] = { percent, broken, at, source }
local listeners = {}
local held = {}             -- [kind] = true: wanted to go, waited for combat to end
local myKey = "open"
local wasGrouped = false
local warnedNewer = false
local status = { why = "not started" }
local ConsiderAll           -- defined below; Recompute needs it
local known = false         -- whether lead was worked out from a real roster yet

local function Now()
    local ok, t = pcall(GetTime)
    t = ok and Restrict.Readable(t) or nil
    return type(t) == "number" and t or 0
end

local function Wall()
    local ok, t = pcall(time)
    return ok and type(t) == "number" and t or 0
end

local function InCombat()
    local ok, yes = pcall(Restrict.InCombat)
    return ok and yes == true
end

local function Notify(kind)
    for _, key in ipairs(Util.SortedKeys(listeners)) do
        local ok, err = pcall(listeners[key], kind)
        if not ok then ns.Debug("comms listener " .. key .. " failed: " .. tostring(err)) end
    end
end

local function Write(kind, text)
    if ns.Log and ns.Log.Write then ns.Log.Write(kind, text, "comms") end
end

local function MyId()
    return snapshot.me and Lead.Id(snapshot.me) or nil
end

local function MyRules(key)
    local rules = ns.db and ns.db.rules
    return type(rules) == "table" and type(rules[key]) == "table" and rules[key] or {}
end

local function NameOf(guid, from)
    local member = guid and snapshot.byGuid and snapshot.byGuid[guid]
    if member then return Lead.Id(member) end
    return Comms.MatchSender(from, snapshot.members)
end

local function Send(msg)
    if not comm then return { action = "refuse", reason = "comms not started" } end
    if not Comms.MaySend(msg.t, InCombat()) then
        held[msg.t] = true
        ns.Events.On("PLAYER_REGEN_ENABLED", "comms", Comms.AfterCombat)
        return { action = "refuse", reason = "held until combat ends" }
    end
    local result = comm:Send(msg)
    if result.action == "refuse" then
        status = { why = result.reason }
        ns.Debug("comms: " .. msg.t .. " not sent: " .. tostring(result.reason))
    else
        status = { channel = result.channel }
    end
    return result
end

-- Works the Raid Lead out again. Out of combat only: a lead that changed mid-pull would
-- have two clients calling the same death.
local function Recompute()
    if InCombat() then
        held.lead = true
        ns.Events.On("PLAYER_REGEN_ENABLED", "comms", Comms.AfterCombat)
        return
    end
    local canHear = status.channel ~= nil or next(users) ~= nil
    local result = Lead.Resolve({
        members = snapshot.members, kind = snapshot.kind, designated = designation.name,
        users = canHear and users or nil, me = MyId(),
    })
    local changed = result.name ~= lead.name or result.mode ~= lead.mode
    lead = result
    known = true
    if changed then
        Write("lead", Lead.Describe(result))
        if result.reason ~= "" and snapshot.kind ~= "solo" then ns.Print(AMBER .. result.reason .. "." .. CLOSE) end
        for key, plan in pairs(published) do
            if plan.from ~= result.name then published[key] = nil end
        end
        Notify("lead")
        -- Who asks whom depends on who leads.
        if ConsiderAll then ConsiderAll() end
    end
end

local function StateMessage()
    local hash, count = Comms.Digest(myKey, MyRules(myKey))
    local msg = { t = "st", k = myKey, h = hash, c = count }
    if designation.name or designation.at > 0 then
        msg.lead = { n = designation.name, a = designation.at, b = designation.by }
    end
    return msg
end

local stateSoon = false
-- One state message for a burst of changes.
function Comms.SendStateSoon()
    if stateSoon or not comm then return end
    stateSoon = true
    C_Timer.After(Comms.STATE_SETTLE, function()
        stateSoon = false
        if snapshot.kind ~= "solo" then Send(StateMessage()) end
    end)
end

local function SendRules()
    local doc, hash = Comms.PackRules(myKey, MyRules(myKey))
    if not doc then
        ns.Print(AMBER .. "your rules were not shared:" .. CLOSE .. " " .. tostring(hash) .. ".")
        Write("held", "rules not shared: " .. tostring(hash))
        return
    end
    local result = Send({ t = "rd", k = myKey, h = hash, doc = doc })
    if result.action ~= "refuse" then answeredAt, answeredHash = Now(), hash end
end

local function Ask(guid, key, hash)
    askedAt[guid .. hash] = Now()
    Send({ t = "rq", to = guid, k = key, h = hash })
end

-- After a state message, or after the Raid Lead changed: fetch what is missing.
local function Consider(guid)
    local state = heard[guid]
    if not state or not state.key then return end
    local have = contributions[guid]
    local want = Comms.WantRules({
        count = state.count, hash = state.hash,
        have = have and have.key == state.key and have.hash or nil,
        iAmLead = lead.isMe, senderIsLead = lead.name ~= nil and state.name == lead.name,
        askedAt = askedAt[guid .. state.hash], now = Now(),
    })
    if want == "empty" then
        contributions[guid] = { name = state.name, key = state.key, hash = state.hash, set = {} }
        Notify("rules")
    elseif want == "ask" then
        Ask(guid, state.key, state.hash)
    end
end

ConsiderAll = function()
    for _, guid in ipairs(Util.SortedKeys(heard)) do Consider(guid) end
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

local function OnHello(msg, from)
    local guid = msg.f
    if type(guid) ~= "string" then return end
    local isNew = not users[guid]
    users[guid] = true
    if isNew or not msg.r then Comms.SendStateSoon() end
    Recompute()
    Notify("peers")
    local peer = comm and comm:Peers()[guid]
    if not warnedNewer and peer and Comm.Newer(peer.version, ns.VERSION) then
        warnedNewer = true
        ns.Printf("%s runs a newer Marked For Death (v%s; you have v%s).", NameOf(guid, from) or "someone",
            tostring(peer.version), ns.VERSION)
    end
end

local function OnState(msg, from)
    local state, why = Comms.CheckState(msg)
    local guid = msg.f
    if not state or type(guid) ~= "string" then
        ns.Debug("comms: a state message from " .. tostring(from) .. " was refused: " .. tostring(why))
        return
    end
    users[guid] = true
    local name = NameOf(guid, from)
    if state.lead and Lead.Accept(designation, state.lead) then
        designation = state.lead
        if ns.db then ns.db.settings.raidLead = designation.name end
        local line = "Raid Lead set to " .. tostring(designation.name or "nobody (automatic)")
            .. " by " .. tostring(designation.by or name or "someone")
        Write("lead", line)
        -- One remembered from an earlier night (time 0) is taken quietly.
        if designation.at > 0 then ns.Print(line .. ".") else ns.Debug(line) end
    end
    heard[guid] = { name = name, key = state.key, hash = state.hash, count = state.count }
    Recompute()
    Consider(guid)
    Notify("peers")
end

local function OnRequest(msg)
    local request = Comms.CheckRequest(msg)
    if not request then return end
    local hash = Comms.Digest(myKey, MyRules(myKey))
    if Comms.ShouldAnswer(request, {
        me = snapshot.me and snapshot.me.guid, key = myKey,
        answeredAt = answeredHash == hash and answeredAt or nil, now = Now(),
    }) then
        SendRules()
    end
end

local function OnRules(msg, from)
    local guid = msg.f
    if type(guid) ~= "string" or not Digest(msg.h) then return end
    local set, why = Comms.UnpackRules(msg.doc, msg.k)
    local name = NameOf(guid, from)
    if not set then
        Write("held", "rules from " .. tostring(name) .. " refused: " .. tostring(why))
        ns.Print(AMBER .. "rules from " .. tostring(name) .. " were not taken:" .. CLOSE .. " " .. tostring(why) .. ".")
        return
    end
    users[guid] = true
    contributions[guid] = { name = name, key = msg.k, hash = msg.h, set = set }
    Write("plan", Count(set) .. " rules from " .. tostring(name) .. " for " .. msg.k)
    Notify("rules")
end

local function OnPlan(msg, from)
    local plan, why = Comms.CheckPlan(msg)
    local name = NameOf(msg.f, from)
    if not plan then
        ns.Debug("comms: a plan from " .. tostring(name) .. " was refused: " .. tostring(why))
        return
    end
    if not lead.name or name ~= lead.name then
        ns.Debug("comms: a plan from " .. tostring(name) .. " ignored; the Raid Lead is " .. tostring(lead.name))
        return
    end
    published[plan.key] = { from = name, at = Now(), hash = plan.hash, steps = plan.steps }
    Notify("plan")
end

--------------------------------------------------------------------------------
-- Durability
--------------------------------------------------------------------------------

local durabilityAskedAt, durabilityAnsweredAt = nil, {}
local durabilityListening = false

local function LibDurability()
    if type(LibStub) ~= "table" or type(LibStub.GetLibrary) ~= "function" then return nil end
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibDurability", true)
    if ok and type(lib) == "table" and type(lib.RequestDurability) == "function" then return lib end
    return nil
end

function Comms.OwnDurability()
    if type(GetInventoryItemDurability) ~= "function" then return nil end
    local rows = {}
    for slot = 1, 18 do
        local ok, current, max = pcall(GetInventoryItemDurability, slot)
        if ok then rows[slot] = { Restrict.Readable(current), Restrict.Readable(max) } end
    end
    return Comms.DurabilityOf(rows)
end

local function Record(name, percent, broken, source)
    if not name then return end
    durability[name] = { percent = percent, broken = broken, at = Now(), source = source }
    Notify("durability")
end

local function RawSend(prefix, text, channel)
    local api = type(C_ChatInfo) == "table" and C_ChatInfo.SendAddonMessage
    if type(api) ~= "function" then return false end
    return (pcall(api, prefix, text, channel))
end

local function GroupChannel()
    if not comm then return nil, "comms not started" end
    return Comm.Channel(comm:State())
end

local function OnAddonMessage(_, prefix, text, channel, sender)
    prefix, text = Restrict.Readable(prefix), Restrict.Readable(text)
    local isDurability = false
    for _, p in ipairs(Comms.DURABILITY_PREFIXES) do
        if prefix == p then isDurability = true end
    end
    if not isDurability or type(text) ~= "string" then return end
    channel, sender = Restrict.Readable(channel), Restrict.Readable(sender)
    if text == "R" then
        -- With LibDurability loaded it answers for us; answering too would double every row.
        if LibDurability() or type(channel) ~= "string" then return end
        local now = Now()
        local last = durabilityAnsweredAt[channel]
        if last and now - last < Comms.DURABILITY_ANSWER_QUIET then return end
        durabilityAnsweredAt[channel] = now
        local percent, broken = Comms.OwnDurability()
        if percent then RawSend(prefix, format("%d,%d", math.floor(percent), broken), channel) end
        return
    end
    local percent, broken = Comms.ParseDurability(text)
    if percent then Record(Comms.MatchSender(sender, snapshot.members), percent, broken, "lib") end
end

-- Listens on the durability prefixes only while in a group; alone there is nobody to ask.
local function ListenDurability(want)
    if want == durabilityListening then return end
    durabilityListening = want
    if want then
        if type(C_ChatInfo) == "table" and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
            for _, p in ipairs(Comms.DURABILITY_PREFIXES) do pcall(C_ChatInfo.RegisterAddonMessagePrefix, p) end
        end
        ns.Events.On("CHAT_MSG_ADDON", "comms.durability", OnAddonMessage)
    else
        ns.Events.Off("CHAT_MSG_ADDON", "comms.durability")
    end
end

function Comms.RequestDurability()
    local percent, broken = Comms.OwnDurability()
    if percent then Record(Comms.Me(), percent, broken, "me") end
    if snapshot.kind == "solo" then return false, "not in a group" end
    local now = Now()
    if durabilityAskedAt and now - durabilityAskedAt < Comms.DURABILITY_QUIET then
        return false, "asked less than " .. Comms.DURABILITY_QUIET .. " seconds ago"
    end
    local channel, why = GroupChannel()
    if not channel then return false, why end
    durabilityAskedAt = now
    local lib = LibDurability()
    if lib then
        local ok = pcall(lib.RequestDurability, lib, channel)
        if ok then return true end
    end
    if not RawSend(Comms.DURABILITY_PREFIXES[1], "R", channel) then return false, "the client refused the request" end
    return true
end

--------------------------------------------------------------------------------
-- The group
--------------------------------------------------------------------------------

local function InstanceKey()
    local ok, _, instanceType, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
    if not ok then return "open" end
    return Rules.InstanceKey(Restrict.Readable(instanceType), Restrict.Readable(instanceID))
end

-- Reads the roster, forgets whoever left, and says hello on joining a group.
local function Refresh()
    if InCombat() then
        held.roster = true
        ns.Events.On("PLAYER_REGEN_ENABLED", "comms", Comms.AfterCombat)
        return
    end
    snapshot = Group.Now()
    local grouped = snapshot.kind ~= "solo"
    local left = false
    for guid in pairs(users) do
        if not snapshot.byGuid[guid] then
            left = left or contributions[guid] ~= nil
            users[guid], heard[guid], contributions[guid] = nil, nil, nil
        end
    end
    if left then Notify("rules") end
    ListenDurability(grouped)
    if grouped and not wasGrouped then
        local result = comm:Hello()
        if result.action == "refuse" then status = { why = result.reason } else status = { channel = result.channel } end
        Comms.SendStateSoon()
    elseif not grouped then
        users, heard, contributions, published, durability = {}, {}, {}, {}, {}
        status = { why = "not in a group" }
    end
    wasGrouped = grouped
    Recompute()
    ConsiderAll()
    Notify("peers")
end

local rosterSoon = false
local function RefreshSoon()
    if rosterSoon then return end
    rosterSoon = true
    C_Timer.After(Comms.ROSTER_SETTLE, function()
        rosterSoon = false
        local ok, err = pcall(Refresh)
        if not ok then ns.Print(RED .. "comms could not read the group:" .. CLOSE .. " " .. tostring(err)) end
    end)
end

local function OnZone()
    local key = InstanceKey()
    if key ~= myKey then
        myKey = key
        Comms.SendStateSoon()
        Notify("rules")
    end
end

-- Sends whatever combat held back, then stops listening for the end of combat.
function Comms.AfterCombat()
    ns.Events.Off("PLAYER_REGEN_ENABLED", "comms")
    local was = held
    held = {}
    if was.roster then RefreshSoon() end
    if was.lead then Recompute() end
    if was.rq or was.rd or was.st then ConsiderAll() end
    if was.rd then SendRules() end
    if was.pl then
        sentPlan = {}
        Notify("plan")
    end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function Comms.Lead() return lead end
function Comms.IsLead() return lead.isMe == true end
-- Whether IsLead is an answer yet: false until the roster has been read once.
function Comms.Known() return known end
-- The player's full name as the merge and the sources map name them.
function Comms.Me() return MyId() or "you" end

function Comms.ActiveRules(key)
    local mine = MyRules(key)
    local byOwner = { [Comms.Me()] = mine }
    local any = false
    for _, c in pairs(contributions) do
        if c.key == key and c.name then
            byOwner[c.name] = c.set
            any = true
        end
    end
    if not any then return mine, {} end
    local merged, sources = Comms.Merge(byOwner, lead.name)
    return merged, sources
end

function Comms.RulesChanged()
    Comms.SendStateSoon()
    Notify("rules")
end

function Comms.PublishPlan(key, steps)
    if not lead.isMe then return false, "not the Raid Lead" end
    local msg, why = Comms.PackPlan(key, steps)
    if not msg then return false, why end
    published[key] = { from = lead.name, at = Now(), hash = msg.h, steps = (Comms.CheckPlan(msg) or {}).steps }
    if sentPlan[key] == msg.h then return false, "unchanged" end
    if snapshot.kind == "solo" then return false, "not in a group" end
    local result = Send(msg)
    if result.action == "refuse" then return false, result.reason end
    sentPlan[key] = msg.h
    return true
end

function Comms.Published(key)
    return published[key]
end

function Comms.Versions()
    local out = {}
    local me = MyId()
    if me then out[me] = { version = ns.VERSION, isMe = true } end
    if comm then
        for guid, peer in pairs(comm:Peers()) do
            local name = snapshot.byGuid and snapshot.byGuid[guid] and NameOf(guid, peer.name)
            if name then out[name] = { version = Comms.Text(peer.version), at = peer.at } end
        end
    end
    return out
end

function Comms.Durability()
    return durability
end

function Comms.Status()
    return { channel = status.channel, why = status.why, users = Count(users) }
end

function Comms.Listen(key, fn)
    assert(type(key) == "string" and type(fn) == "function", "Comms.Listen needs a key and a function")
    listeners[key] = fn
end

function Comms.Unlisten(key)
    listeners[key] = nil
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function SetDesignation(name)
    designation = { name = name, at = Wall(), by = MyId() }
    ns.db.settings.raidLead = name
    Write("lead", "Raid Lead " .. (name and ("set to " .. name) or "cleared") .. " by you")
    if snapshot.kind ~= "solo" then Send(StateMessage()) end
    Recompute()
end

ns.AddCommand("lead", "show the Raid Lead, set one by name, or clear it (leader or assistant)", function(rest)
    if not ns.db then
        ns.Print("the saved settings are not in hand yet.")
        return
    end
    local plan = Lead.Parse(rest, snapshot.members)
    if plan.action == "refuse" then
        ns.Print(RED .. plan.why .. "." .. CLOSE)
        return
    end
    if plan.action == "show" then
        ns.Print(Lead.Describe(lead) .. ".")
        ns.Print("Designated: " .. (designation.name or "|cff999999nobody (automatic)|r") .. ".")
        return
    end
    local ok, why = Lead.CanSet(snapshot)
    if not ok then
        ns.Print(RED .. why .. "." .. CLOSE)
        return
    end
    if plan.action == "clear" then
        SetDesignation(nil)
        ns.Print("Raid Lead cleared; the addon users elect one: group leader, then assistant, then name.")
    else
        SetDesignation(plan.name)
        ns.Printf("Raid Lead set to %s.%s", plan.name,
            plan.inGroup and "" or (AMBER .. " Nobody of that name is in the group now." .. CLOSE))
    end
    ns.Print(Lead.Describe(lead) .. ".")
end, "lead [name|clear]")

ns.AddCommand("peers", "who runs Marked For Death here, their versions, and the Raid Lead", function()
    local list = {}
    for name, v in pairs(Comms.Versions()) do list[#list + 1] = { name = name, version = v.version, isMe = v.isMe } end
    local counts = {}
    for _, c in pairs(contributions) do
        if c.key == myKey and c.name and Count(c.set) > 0 then counts[c.name] = Count(c.set) end
    end
    for _, line in ipairs(Comms.PeerLines({
        users = list, version = ns.VERSION, status = status, counts = counts, lead = lead, key = myKey,
    })) do
        ns.Print(line)
    end
end)

ns.AddCommand("sync", "say hello and share rules with the group again now", function()
    if not comm then
        ns.Print("comms have not started.")
        return
    end
    if snapshot.kind == "solo" then
        ns.Print("not in a group; there is nobody to share with.")
        return
    end
    askedAt, answeredAt, sentPlan = {}, nil, {}
    local result = comm:Hello()
    if result.action == "refuse" then
        ns.Print(AMBER .. "addon messages are not going out:" .. CLOSE .. " " .. tostring(result.reason) .. ".")
        return
    end
    Send(StateMessage())
    ns.Print("said hello on " .. tostring(result.channel) .. "; rules are asked for as answers arrive.")
end)

ns.AddCommand("durability", "ask the group for durability and list the answers", function()
    local ok, why = Comms.RequestDurability()
    if not ok and snapshot.kind ~= "solo" then ns.Print(AMBER .. "not asked:" .. CLOSE .. " " .. tostring(why) .. ".") end
    local function Show()
        local names = Util.SortedKeys(durability)
        if #names == 0 then
            ns.Print("no durability answers; nobody in the group runs an addon that answers them.")
            return
        end
        for _, name in ipairs(names) do
            local d = durability[name]
            local colour = d.percent < ((ns.db and ns.db.check.minDurability) or 50) and RED or "|cff66ff66"
            ns.Printf("%s: %s%d%%%s%s", name, colour, math.floor(d.percent), CLOSE,
                d.broken > 0 and (RED .. ", " .. d.broken .. " broken" .. CLOSE) or "")
        end
    end
    if ok then C_Timer.After(Comms.DURABILITY_WAIT, Show) else Show() end
end)

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

ns.OnReady("comms", function()
    if IC_HEADLESS then return end
    local saved = ns.db and ns.db.settings.raidLead
    designation = { name = type(saved) == "string" and saved ~= "" and saved or nil, at = 0 }
    comm = Comm.New(Comms.PREFIX, {
        version = ns.VERSION,
        onDrop = function(entry, reason)
            local t = entry and entry.msg and entry.msg.t or "?"
            Write("held", "addon message " .. t .. " dropped: " .. tostring(reason))
            ns.Debug("comms: " .. t .. " dropped: " .. tostring(reason))
        end,
    })
    comm:On("hello", OnHello)
    comm:On("st", OnState)
    comm:On("rq", OnRequest)
    comm:On("rd", OnRules)
    comm:On("pl", OnPlan)
    ns.Events.On("GROUP_ROSTER_UPDATE", "comms", RefreshSoon)
    ns.Events.On("PLAYER_ENTERING_WORLD", "comms", function() OnZone() RefreshSoon() end)
    ns.Events.On("ZONE_CHANGED_NEW_AREA", "comms", OnZone)
    myKey = InstanceKey()
    Refresh()
end)
