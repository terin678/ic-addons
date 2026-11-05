local addonName, ns = ...

--[[
Tests_Comms: the comms and lead lane's cases (Lead.lua and the pure half of Comms.lua).
Owned by lane F (comms and lead). Every case builds its own tables; none touches the saved
ones. Registered on ns.Tests; Tests.lua runs them all.

Rule merging between clients was never tried on two clients in the Anniversary addon, so
the merge cases here play several clients receiving the same contributions in different
orders and check they agree.
]]

local T = ns.Tests
local Lead, Comms, Rules = ns.Lead, ns.Comms, ns.Rules
local Util = LibStub("LibICUtil-1.0")
local JSON = LibStub("LibICJSON-1.0")

-- A roster member: name, second name, rank, guid, online.
local function M(name, name2, rank, opts)
    opts = opts or {}
    local m = {
        name = name, name2 = name2, rank = rank, guid = opts.guid or ("G-" .. name .. (name2 or "")),
        online = opts.online, isMe = opts.isMe,
    }
    m.display = name2 and (name .. " " .. name2) or name
    return m
end

local function Set(list)
    local set = {}
    for i, row in ipairs(list) do
        local fields = { intent = row[2] or "KILL", rank = row[3] or i * 10 }
        if type(row[1]) == "number" then fields.npcID = row[1] else fields.name = row[1] end
        for k, v in pairs(row[4] or {}) do fields[k] = v end
        local rule = assert(Rules.New(fields))
        set[Rules.Key(rule)] = rule
    end
    return set
end

local function Users(...)
    local out = {}
    for _, m in ipairs({ ... }) do out[m.guid] = true end
    return out
end

-- The parts of a rule set that decide marking, as one comparable string.
local function Shape(set)
    local parts = {}
    for _, key in ipairs(Util.SortedKeys(set)) do
        local r = set[key]
        parts[#parts + 1] = table.concat({ key, r.intent, tostring(r.rank), tostring(r.fallback),
            tostring(r.maxCount), tostring(r.npcID), tostring(r.from) }, "/")
    end
    return table.concat(parts, ";")
end

--------------------------------------------------------------------------------
-- Lead.Resolve
--------------------------------------------------------------------------------

T.Case("Lead.Resolve: a designated lead who is present wins, by first or full name", function()
    local ann, bo, cy = M("Ann", "Smith", "member"), M("Bo", "Lee", "leader"), M("Cy", "Ray", "assist", { isMe = true })
    local members = { ann, bo, cy }
    local r = Lead.Resolve({ members = members, kind = "raid", designated = "Ann Smith", users = Users(ann, bo), me = "Cy Ray" })
    T.Eq(r.name, "Ann Smith", "designated by full name")
    T.Eq(r.mode, "designated", "mode")
    T.Eq(r.isMe, false, "not me")
    T.Eq(r.reason, "", "no reason")
    T.Eq(Lead.Resolve({ members = members, kind = "raid", designated = "ann", users = {}, me = "Cy Ray" }).name,
        "Ann Smith", "a first name alone, any case, finds the only Ann")
    local mine = Lead.Resolve({ members = members, kind = "raid", designated = "Cy Ray", users = {}, me = "Cy Ray" })
    T.Eq(mine.isMe, true, "designated me is me")
    T.Eq(mine.warning, "", "and I am always heard")
end)

T.Case("Lead.Resolve: a designated lead nobody has heard still wins, with a warning", function()
    local ann, bo = M("Ann", "Smith", "member"), M("Bo", "Lee", "leader", { isMe = true })
    local r = Lead.Resolve({ members = { ann, bo }, kind = "raid", designated = "Ann Smith", users = {}, me = "Bo Lee" })
    T.Eq(r.name, "Ann Smith", "the designation stands without the addon heard")
    T.True(r.warning:find("not been heard", 1, true), "but says so")
    local quiet = Lead.Resolve({ members = { ann, bo }, kind = "raid", designated = "Ann Smith", users = nil, me = "Bo Lee" })
    T.Eq(quiet.warning, "", "no warning when nothing can be heard at all (comms off)")
end)

T.Case("Lead.Resolve: an offline or absent designation falls back to the election, saying why", function()
    local ann = M("Ann", "Smith", "member", { online = false })
    local bo, cy = M("Bo", "Lee", "assist"), M("Cy", "Ray", "leader", { isMe = true })
    local users = Users(bo, cy)
    local off = Lead.Resolve({ members = { ann, bo, cy }, kind = "raid", designated = "Ann Smith", users = users, me = "Cy Ray" })
    T.Eq(off.name, "Cy Ray", "the leader is elected")
    T.Eq(off.mode, "elected", "by election")
    T.True(off.reason:find("offline", 1, true), "an offline designation is named as offline")
    local gone = Lead.Resolve({ members = { bo, cy }, kind = "raid", designated = "Dee Vo", users = users, me = "Cy Ray" })
    T.True(gone.reason:find("not in the group", 1, true), "an absent one as not in the group")
    T.True(gone.reason:find("Dee Vo", 1, true), "by name")
end)

T.Case("Lead.Resolve: election is leader, then assistant, then name; only addon users vote", function()
    local lead, a1, a2, m1 = M("Zed", "Q", "leader"), M("Yan", "B", "assist"), M("Abe", "C", "assist"), M("Aaa", "A", "member", { isMe = true })
    local members = { m1, a1, lead, a2 }
    local all = Users(lead, a1, a2)
    T.Eq(Lead.Resolve({ members = members, kind = "raid", users = all, me = "Aaa A" }).name, "Zed Q", "leader first")
    T.Eq(Lead.Resolve({ members = members, kind = "raid", users = Users(a1, a2), me = "Aaa A" }).name, "Abe C",
        "leader not running the addon: the assistant whose name sorts first")
    T.Eq(Lead.Resolve({ members = members, kind = "raid", users = {}, me = "Aaa A" }).name, "Aaa A",
        "nobody else heard: me, the only addon user")
    local unknown = M("Ace", "D", nil)
    T.Eq(Lead.Resolve({ members = { unknown, a2 }, kind = "raid", users = Users(unknown, a2), me = "Zzz" }).name, "Abe C",
        "an unreadable rank never outranks an assistant")
    local offline = M("Aab", "E", "leader", { online = false })
    T.Eq(Lead.Resolve({ members = { offline, a1 }, kind = "raid", users = Users(offline, a1), me = "Zzz" }).name, "Yan B",
        "an offline voter is skipped")
end)

T.Case("Lead.Resolve: every client reaches the same answer whatever order its roster is in", function()
    local a, b, c, d = M("Dee", "A", "assist"), M("Bea", "B", "assist"), M("Cal", "C", "member"), M("Ann", "D", "member")
    local users = Users(a, b, c, d)
    local orders = { { a, b, c, d }, { d, c, b, a }, { c, a, d, b }, { b, d, a, c } }
    local first
    for i, members in ipairs(orders) do
        local r = Lead.Resolve({ members = members, kind = "raid", users = users, me = members[1].display })
        first = first or r.name
        T.Eq(r.name, first, "order " .. i)
    end
    T.Eq(first, "Bea B", "two assistants: the name that sorts first")
end)

T.Case("Lead.Resolve: addon messages unavailable falls back to the group leader, alone is me", function()
    local lead, me = M("Zed", "Q", "leader"), M("Ann", "A", "member", { isMe = true })
    local r = Lead.Resolve({ members = { me, lead }, kind = "raid", users = nil, me = "Ann A" })
    T.Eq(r.name, "Zed Q", "the group leader")
    T.Eq(r.mode, "leader", "named as the leader fallback")
    local none = Lead.Resolve({ members = { me, M("Bo", "B", nil) }, kind = "raid", users = nil, me = "Ann A" })
    T.Eq(none.name, nil, "no leader readable: nobody")
    T.Eq(none.mode, "none", "mode none")
    T.True(none.reason ~= "", "with a reason")
    local solo = Lead.Resolve({ members = { me }, kind = "solo", me = "Ann A" })
    T.Eq(solo.name, "Ann A", "alone, me")
    T.Eq(solo.isMe, true, "is me")
    T.Eq(Lead.Resolve(nil).mode, "none", "nothing at all does not raise")
end)

T.Case("Lead.Resolve: two players with one first name are told apart by their full names", function()
    local a, b = M("Sam", "Oak", "assist"), M("Sam", "Ash", "assist")
    local r = Lead.Resolve({ members = { a, b }, kind = "raid", users = Users(a, b), me = "Sam Oak" })
    T.Eq(r.name, "Sam Ash", "full names decide the tie")
    T.Eq(r.isMe, false, "and the other Sam is not me")
    local d = Lead.Resolve({ members = { a, b }, kind = "raid", designated = "Sam", users = Users(a, b), me = "Sam Oak" })
    T.Eq(d.mode, "elected", "an ambiguous first-name designation does not pick one of them")
end)

--------------------------------------------------------------------------------
-- Lead.CanSet, Accept, Parse, Describe
--------------------------------------------------------------------------------

T.Case("Lead.CanSet: alone, leader, assistant or everyone-assist; a member is refused with a reason", function()
    T.Eq(Lead.CanSet({ kind = "solo" }), true, "alone")
    T.Eq(Lead.CanSet({ kind = "raid", me = { rank = "leader" } }), true, "leader")
    T.Eq(Lead.CanSet({ kind = "raid", me = { rank = "assist" } }), true, "assistant")
    T.Eq(Lead.CanSet({ kind = "raid", everyoneAssist = true, me = { rank = "member" } }), true, "everyone is assistant")
    local ok, why = Lead.CanSet({ kind = "raid", me = { rank = "member" } })
    T.Eq(ok, false, "a raid member")
    T.True(why:find("raid leader", 1, true), "is told who can")
    local pok, pwhy = Lead.CanSet({ kind = "party", me = { rank = "member" } })
    T.Eq(pok, false, "a party member")
    T.True(pwhy:find("party leader", 1, true), "is told the party leader can")
    local uok, uwhy = Lead.CanSet({ kind = "raid", me = {} })
    T.Eq(uok, false, "an unreadable rank is refused")
    T.True(uwhy:find("could not be read", 1, true), "and says so")
end)

T.Case("Lead.Accept: the later setting wins; equal times settle the same way everywhere", function()
    T.Eq(Lead.Accept({ name = "Ann", at = 100 }, { name = "Bo", at = 200 }), true, "later wins")
    T.Eq(Lead.Accept({ name = "Ann", at = 200 }, { name = "Bo", at = 100 }), false, "earlier loses")
    T.Eq(Lead.Accept({ name = "Ann", at = 100 }, { name = nil, at = 200 }), true, "a later clear wins")
    T.Eq(Lead.Accept({ name = "Ann", at = 100 }, { name = "Ann", at = 100 }), false, "the same one changes nothing")
    T.Eq(Lead.Accept({ at = 0 }, { name = "Bo", at = 0 }), true, "a name beats none at the same time")
    T.Eq(Lead.Accept({ name = "Bo", at = 0 }, { at = 0 }), false, "none never beats a name at the same time")
    T.Eq(Lead.Accept({ name = "Bo", at = 0 }, { name = "ann", at = 0 }), true, "then the name that sorts first, any case")
    T.Eq(Lead.Accept(nil, { name = "Bo", at = 5 }), true, "nothing held takes anything")
    T.Eq(Lead.Accept({ name = "Bo", at = 5 }, nil), false, "nothing incoming changes nothing")

    -- Three clients that see the same designations in different orders end on one.
    local seen = { { name = "Cy", at = 0 }, { name = "Bo", at = 0 }, { at = 300, name = "Dee" }, { name = "Al", at = 300 } }
    local orders = { { 1, 2, 3, 4 }, { 4, 3, 2, 1 }, { 2, 4, 1, 3 }, { 3, 1, 4, 2 } }
    for i, order in ipairs(orders) do
        local held = { at = 0 }
        for _, k in ipairs(order) do
            if Lead.Accept(held, seen[k]) then held = seen[k] end
        end
        T.Eq(held.name, "Al", "order " .. i .. " converges on the latest, first by name")
    end
end)

T.Case("Lead.Parse: show, clear, a member's spelling, a new name capitalised, nonsense refused", function()
    local members = { M("Ann", "Smith", "member"), M("Sam", "Oak", "member"), M("Sam", "Ash", "member") }
    T.Eq(Lead.Parse("", members).action, "show", "nothing shows")
    T.Eq(Lead.Parse("   ", members).action, "show", "spaces show")
    for _, word in ipairs({ "clear", "none", "OFF", "-" }) do
        T.Eq(Lead.Parse(word, members).action, "clear", word .. " clears")
    end
    local ann = Lead.Parse("ann", members)
    T.Eq(ann.action, "set", "a first name sets")
    T.Eq(ann.name, "Ann Smith", "spelled as the game does, both names")
    T.Eq(ann.inGroup, true, "and is in the group")
    T.Eq(Lead.Parse("sam ash", members).name, "Sam Ash", "a full name picks one of two Sams")
    local amb = Lead.Parse("Sam", members)
    T.Eq(amb.action, "refuse", "a first name two players share is refused")
    T.True(amb.why:find("both names", 1, true), "asking for both names")
    local new = Lead.Parse("dEE voss", members)
    T.Eq(new.name, "Dee Voss", "a name not in the group is capitalised")
    T.Eq(new.inGroup, false, "and marked as not in the group")
    T.Eq(Lead.Parse("Dee2", members).action, "refuse", "digits refused")
    T.Eq(Lead.Parse("a b c", members).action, "refuse", "three words refused")
    T.Eq(Lead.Parse("|cffff0000Bad", members).action, "refuse", "an escape refused")
    T.Eq(Lead.Parse(string.rep("a", 60), members).action, "refuse", "too long refused")
    T.Eq(Lead.Parse(nil, members).action, "show", "nil shows")
end)

T.Case("Lead.Describe: who, how, and why, in one line", function()
    T.Eq(Lead.Describe({ name = "Ann Smith", mode = "designated", isMe = false, reason = "", warning = "" }),
        "Raid Lead: Ann Smith, designated", "designated")
    local line = Lead.Describe({ name = "Me", mode = "elected", isMe = true, reason = "Raid Lead Bo is offline", warning = "" })
    T.True(line:find("(you)", 1, true), "marks me")
    T.True(line:find("offline", 1, true), "carries the reason")
    T.Eq(Lead.Describe({ mode = "none", reason = "" }), "Raid Lead: nobody", "nobody")
    T.Eq(Lead.Describe(nil), "Raid Lead: nobody", "nil")
end)

--------------------------------------------------------------------------------
-- Rules over the wire
--------------------------------------------------------------------------------

T.Case("Comms.PackRules/UnpackRules: a rule set round-trips through the wire unchanged", function()
    local set = Set({
        { "Scarlet Sorcerer", "SHEEP", 20, { fallback = "KILL", maxCount = 2, npcID = 4294 } },
        { "Scarlet Monk", "KILL", 10 },
        { 6000, "BANISH", 30 },
        { "C'Thun's Eye", "KILL", 40 },
    })
    local doc, hash, count = Comms.PackRules("i:33", set)
    T.True(type(doc) == "table", "packed")
    T.True(hash:match("^%x+$") ~= nil and #hash == 8, "an 8-digit digest")
    T.Eq(count, 4, "four rules")
    T.Eq(doc.formatVersion, 2, "share format v2")
    -- What travels is compact JSON text; decode it the way the other client does.
    local wire = JSON.Decode(JSON.Encode({ t = "rd", k = "i:33", h = hash, doc = doc }, { compact = true }))
    local back, why = Comms.UnpackRules(wire.doc, wire.k)
    T.True(back ~= nil, "unpacked: " .. tostring(why))
    T.Eq(Shape(back), Shape(set), "every rule, job, rank, fallback, max count and npc id intact")
    T.Eq(Comms.Digest("i:33", back), hash, "the receiver's digest of it matches the sender's")
end)

T.Case("Comms.Digest: the same rules give the same digest whatever order they were added", function()
    local a = Set({ { "One", "KILL", 10 }, { "Two", "SHEEP", 20 }, { "Three", "KILL", 30 } })
    local b = {}
    for _, key in ipairs({ "n:Three", "n:One", "n:Two" }) do b[key] = Util.DeepCopy(a[key]) end
    T.Eq(Comms.Digest("open", a), Comms.Digest("open", b), "insertion order does not matter")
    local changed = Util.DeepCopy(a)
    changed["n:Two"].intent = "KILL"
    T.True(Comms.Digest("open", changed) ~= Comms.Digest("open", a), "a changed job changes it")
    local reranked = Util.DeepCopy(a)
    reranked["n:One"].rank = 35
    T.True(Comms.Digest("open", reranked) ~= Comms.Digest("open", a), "a changed rank changes it")
    local h, n = Comms.Digest("open", {})
    T.Eq(n, 0, "an empty set counts 0")
    T.True(#h == 8, "and still has a digest")
    local from = Util.DeepCopy(a)
    from["n:One"].from = "Somebody"
    T.Eq(Comms.Digest("open", from), Comms.Digest("open", a), "who a rule came from is not part of it")
end)

T.Case("Comms.UnpackRules: anything wrong refuses the whole message", function()
    local good = Comms.PackRules("i:33", Set({ { "Mob", "KILL", 10 } }))
    local function Doc(edit)
        local d = Util.DeepCopy(good)
        edit(d)
        return d
    end
    local cases = {
        { "not ours", Doc(function(d) d.addon = "Other" end) },
        { "newer", Doc(function(d) d.formatVersion = 3 end) },
        { "Anniversary v1", Doc(function(d) d.formatVersion = 1 end) },
        { "unknown job", Doc(function(d) d.rules["i:33"][1].job = "DANCE" end) },
        { "a quote in a name", Doc(function(d) d.rules["i:33"][1].name = 'Bad"Name' end) },
        { "a semicolon in a name", Doc(function(d) d.rules["i:33"][1].name = "Bad;Name" end) },
        { "another instance", Doc(function(d) d.rules["i:34"] = d.rules["i:33"] end) },
        { "two rules for one mob", Doc(function(d) d.rules["i:33"][2] = Util.DeepCopy(d.rules["i:33"][1]) end) },
        { "a rule that is not a table", Doc(function(d) d.rules["i:33"][1] = "x" end) },
    }
    for _, c in ipairs(cases) do
        local set, why = Comms.UnpackRules(c[2], "i:33")
        T.Eq(set, nil, c[1] .. " is refused")
        T.True(type(why) == "string" and why ~= "", c[1] .. " says why")
    end
    T.Eq(Comms.UnpackRules("text", "i:33"), nil, "a doc that is not a table")
    T.Eq(Comms.UnpackRules(good, "legacy:Karazhan"), nil, "legacy keys never travel")
    T.Eq(Comms.UnpackRules(good, "nonsense"), nil, "nor a key that is not one")
    local empty = Comms.PackRules("i:33", {})
    local set = Comms.UnpackRules(empty, "i:33")
    T.Eq(next(set), nil, "an empty set comes back empty, not refused")
end)

T.Case("Comms.PackRules: too big for addon messages, or a legacy key, is refused with a reason", function()
    local list = {}
    for i = 1, 80 do list[i] = { "A Rather Long Mob Name Number " .. i, "KILL", i * 10, { fallback = "SHEEP" } } end
    local doc, why = Comms.PackRules("i:33", Set(list))
    T.Eq(doc, nil, "eighty long rules are too many")
    T.True(why:find("as a file", 1, true), "and the player is told to share a file")
    local h, n = Comms.Digest("i:33", Set(list))
    T.Eq(n, 80, "a set too big to send still has a digest and a count")
    T.True(#h == 8, "so a change to it is still seen")
    T.Eq(Comms.PackRules("legacy:Karazhan", Set({ { "Mob" } })), nil, "a legacy set stays home")
end)

T.Case("Comms.UnpackRules: an Anniversary v1 file still reads through Rules, but never off the wire", function()
    local v1 = '{"addon":"MarkedForDeath","formatVersion":1,"rules":{"Karazhan":[{"name":"Phantom Valet","job":"kill","priority":10}]}}'
    local byInstance, version = Rules.FromJSON(v1)
    T.Eq(version, 1, "the file reader takes v1")
    T.True(byInstance["legacy:Karazhan"] ~= nil, "under a legacy key")
    local set, why = Comms.UnpackRules(JSON.Decode(v1), "i:33")
    T.Eq(set, nil, "the same document from another client is refused")
    T.True(why ~= nil, "with a reason")
end)

--------------------------------------------------------------------------------
-- Merging contributions
--------------------------------------------------------------------------------

T.Case("Comms.Merge: the Raid Lead's rule wins a mob, everyone else fills gaps", function()
    local leadSet = Set({ { "Mob A", "SHEEP", 10 }, { "Mob B", "KILL", 20 } })
    local bo = Set({ { "Mob A", "KILL", 5 }, { "Mob C", "BANISH", 30 } })
    local merged, sources = Comms.Merge({ ["Ann Smith"] = leadSet, ["Bo Lee"] = bo }, "Ann Smith")
    T.Eq(merged["n:Mob A"].intent, "SHEEP", "the lead's job for Mob A")
    T.Eq(merged["n:Mob A"].rank, 10, "with the lead's rank")
    T.Eq(sources["n:Mob A"], "Ann Smith", "sourced to the lead")
    T.Eq(merged["n:Mob C"].intent, "BANISH", "a mob only Bo rules comes in")
    T.Eq(sources["n:Mob C"], "Bo Lee", "sourced to Bo")
    T.Eq(merged["n:Mob C"].from, "Bo Lee", "and the rule says where it came from")
    T.Eq(Util.SortedKeys(merged)[3], "n:Mob C", "three rules in all")
end)

T.Case("Comms.Merge: a rule by npc id and a rule by name for the same mob do not both land", function()
    local leadSet = Set({ { "Scarlet Monk", "SHEEP", 10, { npcID = 4540 } } })
    local other = Set({ { 4540, "KILL", 10 } })
    local merged = Comms.Merge({ Lead = leadSet, Other = other }, "Lead")
    T.Eq(merged["id:4540"], nil, "the id rule for the lead's mob is dropped")
    T.Eq(merged["n:Scarlet Monk"].intent, "SHEEP", "the lead's stands")
    local byName = Set({ { "scarlet monk", "KILL", 10 } })
    local merged2 = Comms.Merge({ Lead = leadSet, Other = byName }, "Lead")
    T.Eq(merged2["n:scarlet monk"], nil, "a name in another case is the same mob")
end)

T.Case("Comms.Merge: two clients with the same contributions build the same set", function()
    -- Three players each with their own rules; the lead is Bea. Each client holds its own
    -- set under its own name and everyone else's as received: the inputs are the same, so
    -- the merged sets must be too, whichever client builds it and whatever order.
    local ann = Set({ { "Mob A", "KILL", 10 }, { "Mob X", "SHEEP", 20 } })
    local bea = Set({ { "Mob A", "SHEEP", 30 }, { "Mob B", "KILL", 10 } })
    local cal = Set({ { "Mob X", "BANISH", 5 }, { "Mob C", "KILL", 15 }, { "Mob B", "BANISH", 99 } })
    local onAnn = Comms.Merge({ ["Ann A"] = ann, ["Bea B"] = bea, ["Cal C"] = cal }, "Bea B")
    local reversed = {}
    reversed["Cal C"] = Util.DeepCopy(cal)
    reversed["Bea B"] = Util.DeepCopy(bea)
    reversed["Ann A"] = Util.DeepCopy(ann)
    local onCal = Comms.Merge(reversed, "Bea B")
    T.Eq(Shape(onAnn), Shape(onCal), "same set on both clients")
    T.Eq(onAnn["n:Mob A"].intent, "SHEEP", "lead wins Mob A over Ann's own rule")
    T.Eq(onAnn["n:Mob B"].intent, "KILL", "lead wins Mob B over Cal")
    T.Eq(onAnn["n:Mob X"].intent, "SHEEP", "no lead rule: Ann sorts before Cal, so Ann's Mob X")
    T.Eq(onAnn["n:Mob C"].from, "Cal C", "Cal's only rule fills the gap")
end)

T.Case("Comms.Merge: with no lead, or a lead with no rules, names in order decide", function()
    local ann = Set({ { "Mob A", "KILL", 10 } })
    local bo = Set({ { "Mob A", "SHEEP", 10 } })
    T.Eq(Comms.Merge({ ["Bo"] = bo, ["Ann"] = ann }, nil)["n:Mob A"].intent, "KILL", "Ann sorts first")
    T.Eq(Comms.Merge({ ["Bo"] = bo, ["Ann"] = ann }, "Zed")["n:Mob A"].intent, "KILL", "an absent lead changes nothing")
    local _, _, order = Comms.Merge({ ["Bo"] = bo, ["Ann"] = ann, ["Zed"] = {} }, "Zed")
    T.Eq(table.concat(order, ","), "Zed,Ann,Bo", "the lead is read first even with no rules")
    local merged = Comms.Merge({}, "Ann")
    T.Eq(next(merged), nil, "nothing merges to nothing")
end)

T.Case("Comms.Merge: never changes the sets it was given (saved rules stay as written)", function()
    local mine = Set({ { "Mob A", "KILL", 10 } })
    local theirs = Set({ { "Mob B", "SHEEP", 20 } })
    local before, beforeTheirs = Shape(mine), Shape(theirs)
    local merged = Comms.Merge({ Me = mine, Them = theirs }, "Them")
    merged["n:Mob A"].intent = "IGNORE"
    T.Eq(Shape(mine), before, "my set is untouched, even after editing the merged copy")
    T.Eq(Shape(theirs), beforeTheirs, "theirs too")
    T.Eq(mine["n:Mob A"].from, nil, "no from was stamped on my saved rule")
end)

--------------------------------------------------------------------------------
-- Messages arriving
--------------------------------------------------------------------------------

T.Case("Comms.CheckState: a state message is checked field by field", function()
    local ok = Comms.CheckState({ t = "st", k = "i:33", h = "0123abcd", c = 4, lead = { n = "Ann Smith", a = 100, b = "Bo Lee" } })
    T.Eq(ok.key, "i:33", "key")
    T.Eq(ok.count, 4, "count")
    T.Eq(ok.lead.name, "Ann Smith", "lead name")
    T.Eq(ok.lead.at, 100, "lead time")
    T.Eq(Comms.CheckState({ t = "st", lead = { a = 5 } }).lead.name, nil, "a cleared lead is no name")
    T.True(Comms.CheckState({ t = "st" }) ~= nil, "a state with nothing is still a state")
    local bad = {
        { "legacy key", { k = "legacy:Kara", h = "0123abcd", c = 1 } },
        { "short digest", { k = "open", h = "abc", c = 1 } },
        { "negative count", { k = "open", h = "0123abcd", c = -1 } },
        { "fractional count", { k = "open", h = "0123abcd", c = 1.5 } },
        { "lead with no time", { lead = { n = "Ann" } } },
        { "lead name with an escape", { lead = { n = "|cffAnn", a = 1 } } },
        { "lead name too long", { lead = { n = string.rep("x", 60), a = 1 } } },
    }
    for _, c in ipairs(bad) do T.Eq(Comms.CheckState(c[2]), nil, c[1] .. " refused") end
    T.Eq(Comms.CheckState("x"), nil, "not a table")
end)

T.Case("Comms.CheckRequest: names someone, a shared key, and maybe a digest", function()
    local r = Comms.CheckRequest({ to = "Player-1-0001", k = "open", h = "deadbeef" })
    T.Eq(r.to, "Player-1-0001", "to")
    T.Eq(r.hash, "deadbeef", "hash")
    T.Eq(Comms.CheckRequest({ k = "open" }), nil, "nobody named")
    T.Eq(Comms.CheckRequest({ to = "x", k = "legacy:Z" }), nil, "legacy key")
    T.Eq(Comms.CheckRequest({ to = "x", k = "open", h = "zz" }), nil, "bad digest")
end)

T.Case("Comms.PackPlan/CheckPlan: the Raid Lead's steps arrive as MarkPlan steps", function()
    local steps = {
        { icon = 8, iconName = "Skull", name = "Mob A", guid = "Creature-1", unit = "nameplate3", seatLabel = "Kill 1", owner = true },
        { icon = 5, iconName = "Moon", name = "Mob B", seatLabel = "Sheep 1", owner = "Ann Smith" },
        { icon = 4, iconName = "Triangle", name = "Mob C", seatLabel = "Banish 1", owner = false, borrowed = true },
    }
    local msg = assert(Comms.PackPlan("i:33", steps))
    T.Eq(msg.t, "pl", "a pl message")
    T.Eq(msg.s[1].unit, nil, "no unit token travels")
    T.Eq(msg.s[1].guid, nil, "no guid travels")
    local wire = JSON.Decode(JSON.Encode(msg, { compact = true }))
    local plan = assert(Comms.CheckPlan(wire))
    T.Eq(#plan.steps, 3, "three steps")
    T.Eq(plan.steps[1].iconName, "Skull", "icon name filled from the icon")
    T.Eq(plan.steps[1].owner, true, "a kill seat's owner")
    T.Eq(plan.steps[2].owner, "Ann Smith", "a named owner")
    T.Eq(plan.steps[3].owner, false, "nobody can do it")
    T.Eq(plan.steps[3].borrowed, true, "borrowed kept")
    T.Eq(plan.hash, msg.h, "digest kept")
    local again = Comms.PackPlan("i:33", Util.DeepCopy(steps))
    T.Eq(again.h, msg.h, "the same plan has the same digest, so it is not sent twice")
    local other = Util.DeepCopy(steps)
    other[1].name = "Mob Z"
    T.True(Comms.PackPlan("i:33", other).h ~= msg.h, "a changed plan changes the digest")
    T.True(Comms.PackPlan("i:34", steps).h ~= msg.h, "and so does another instance")
end)

T.Case("Comms.CheckPlan: one bad step refuses the plan", function()
    local base = { t = "pl", k = "open", h = "0123abcd", s = { { i = 8, n = "Mob", o = true, l = "Kill 1" } } }
    T.True(Comms.CheckPlan(base) ~= nil, "the base plan is fine")
    local function With(edit)
        local m = Util.DeepCopy(base)
        edit(m)
        return m
    end
    local bad = {
        { "icon 9", With(function(m) m.s[1].i = 9 end) },
        { "icon 0", With(function(m) m.s[1].i = 0 end) },
        { "two Skulls", With(function(m) m.s[2] = { i = 8, n = "Other" } end) },
        { "a quote in a name", With(function(m) m.s[1].n = 'A"B' end) },
        { "no name", With(function(m) m.s[1].n = nil end) },
        { "an escape in an owner", With(function(m) m.s[1].o = "|cffAnn" end) },
        { "a number for an owner", With(function(m) m.s[1].o = 5 end) },
        { "an escape in a seat", With(function(m) m.s[1].l = "Kill|r" end) },
        { "nine steps", With(function(m) for i = 1, 9 do m.s[i] = { i = (i % 8) + 1, n = "M" .. i } end end) },
        { "legacy key", With(function(m) m.k = "legacy:Z" end) },
        { "bad digest", With(function(m) m.h = "x" end) },
        { "steps not a list", With(function(m) m.s = "x" end) },
    }
    for _, c in ipairs(bad) do T.Eq(Comms.CheckPlan(c[2]), nil, c[1] .. " refused") end
    T.Eq(#Comms.CheckPlan(With(function(m) m.s = {} end)).steps, 0, "an empty plan is a plan (nothing to mark)")
end)

--------------------------------------------------------------------------------
-- When to ask, answer and send
--------------------------------------------------------------------------------

T.Case("Comms.WantRules: the lead asks everyone, everyone asks the lead, nobody asks twice", function()
    local base = { count = 3, hash = "aaaaaaaa", have = nil, iAmLead = false, senderIsLead = false, now = 100 }
    local function With(t)
        local c = Util.DeepCopy(base)
        for k, v in pairs(t) do c[k] = v end
        return c
    end
    T.Eq(Comms.WantRules(base), nil, "two non-leads do not ask each other")
    T.Eq(Comms.WantRules(With({ iAmLead = true })), "ask", "the lead asks")
    T.Eq(Comms.WantRules(With({ senderIsLead = true })), "ask", "the lead's rules are asked for")
    T.Eq(Comms.WantRules(With({ iAmLead = true, have = "aaaaaaaa" })), nil, "already held at that digest")
    T.Eq(Comms.WantRules(With({ iAmLead = true, have = "bbbbbbbb" })), "ask", "a changed digest is asked again")
    T.Eq(Comms.WantRules(With({ iAmLead = true, askedAt = 95 })), nil, "asked 5 s ago: wait")
    T.Eq(Comms.WantRules(With({ iAmLead = true, askedAt = 85 })), "ask", "asked 15 s ago: ask again")
    T.Eq(Comms.WantRules(With({ count = 0 })), "empty", "no rules: recorded empty without a message")
    T.Eq(Comms.WantRules(With({ count = 0, have = "aaaaaaaa" })), nil, "an empty set already held")
end)

T.Case("Comms.ShouldAnswer: only requests for me, for this instance, not twice in 10 s", function()
    local ctx = { me = "G-me", key = "i:33", answeredAt = nil, now = 100 }
    T.Eq(Comms.ShouldAnswer({ to = "G-me", key = "i:33" }, ctx), true, "mine, this instance")
    T.Eq(Comms.ShouldAnswer({ to = "G-other", key = "i:33" }, ctx), false, "someone else's request")
    T.Eq(Comms.ShouldAnswer({ to = "G-me", key = "i:34" }, ctx), false, "another instance")
    ctx.answeredAt = 95
    T.Eq(Comms.ShouldAnswer({ to = "G-me", key = "i:33" }, ctx), false, "answered 5 s ago")
    ctx.answeredAt = 80
    T.Eq(Comms.ShouldAnswer({ to = "G-me", key = "i:33" }, ctx), true, "answered 20 s ago")
    T.Eq(Comms.ShouldAnswer({ to = nil, key = "i:33" }, { me = nil, key = "i:33", now = 1 }), false,
        "my guid unknown answers nothing")
end)

T.Case("Comms.MaySend: rules, requests and plans wait for the end of combat; state goes at once", function()
    for _, kind in ipairs({ "rq", "rd", "pl" }) do
        local ok, why = Comms.MaySend(kind, true)
        T.Eq(ok, false, kind .. " held in combat")
        T.True(why:find("combat", 1, true), kind .. " says why")
        T.Eq(Comms.MaySend(kind, false), true, kind .. " goes out of combat")
    end
    T.Eq(Comms.MaySend("st", true), true, "a state message goes in combat")
    T.Eq(Comms.MaySend("hello", true), true, "so does a hello")
end)

--------------------------------------------------------------------------------
-- Durability, names, the report
--------------------------------------------------------------------------------

T.Case("Comms.ParseDurability and DurabilityOf: LibDurability's wire format and its sums", function()
    local p, b = Comms.ParseDurability("87,1")
    T.Eq(p, 87, "percent")
    T.Eq(b, 1, "broken")
    T.Eq(Comms.ParseDurability("120,0"), 100, "capped at 100")
    T.Eq(Comms.ParseDurability("R"), nil, "a request is not an answer")
    T.Eq(Comms.ParseDurability("87"), nil, "half an answer")
    T.Eq(Comms.ParseDurability("-5,0"), nil, "a negative")
    T.Eq(Comms.ParseDurability(nil), nil, "nothing")
    local pct, broken = Comms.DurabilityOf({ [1] = { 50, 100 }, [5] = { 0, 100 }, [7] = { nil, nil } })
    T.Near(pct, 25, 0.001, "150 of 200 ... 50 of 200 is 25%")
    T.Eq(broken, 1, "one broken item")
    T.Eq(Comms.DurabilityOf({}), nil, "nothing worn that wears")
    T.Eq(Comms.DurabilityOf({ { 0, 0 } }), nil, "a zero-max item does not count")
end)

T.Case("Comms.MatchSender: full names, a lone first name, and Name-Realm land on the member", function()
    local members = { M("Ann", "Smith", "member"), M("Sam", "Oak", "member"), M("Sam", "Ash", "member") }
    T.Eq(Comms.MatchSender("Ann Smith", members), "Ann Smith", "full name")
    T.Eq(Comms.MatchSender("ann", members), "Ann Smith", "the only Ann")
    T.Eq(Comms.MatchSender("Ann-SomeRealm", members), "Ann Smith", "Name-Realm")
    T.Eq(Comms.MatchSender("Sam", members), "Sam", "two Sams: left as given")
    T.Eq(Comms.MatchSender("Sam Ash", members), "Sam Ash", "but a full Sam matches")
    T.Eq(Comms.MatchSender("Zed", members), "Zed", "a stranger as given")
    T.Eq(Comms.MatchSender(nil, members), nil, "nothing")
end)

T.Case("Comms.Text: names from other clients cannot carry escapes or line breaks", function()
    T.Eq(Comms.Text("Ann Smith"), "Ann Smith", "plain")
    T.Eq(Comms.Text("|cffff0000x"), nil, "escape")
    T.Eq(Comms.Text("a\nb"), nil, "line break")
    T.Eq(Comms.Text(""), nil, "empty")
    T.Eq(Comms.Text(5), nil, "not text")
    T.Eq(Comms.Text(string.rep("a", 49)), nil, "too long")
end)

T.Case("Comms.PeerLines: channel, lead, users with versions, merged counts", function()
    local lines = Comms.PeerLines({
        users = { { name = "Bo Lee", version = "0.2.0" }, { name = "Ann Smith", version = "0.1.0", isMe = true }, { name = "Cy" } },
        version = "0.1.0",
        status = { channel = "RAID" },
        counts = { ["Bo Lee"] = 4 },
        lead = { name = "Bo Lee", mode = "elected", isMe = false, reason = "", warning = "" },
        key = "i:33",
    })
    T.Eq(lines[1], "Addon messages go on RAID.", "the channel")
    T.True(lines[2]:find("Raid Lead: Bo Lee", 1, true), "the lead")
    T.True(lines[3]:find("^3 running"), "three users")
    T.True(lines[3]:find("Ann Smith (you) v0.1.0", 1, true), "me, sorted first")
    T.True(lines[3]:find("v0.2.0 (newer)", 1, true), "a newer version is flagged")
    T.True(lines[3]:find("Cy version unknown", 1, true), "a user with no version")
    T.True(lines[4]:find("4 rules merged from Bo Lee", 1, true), "merged counts")
    local off = Comms.PeerLines({ status = { why = "addon messages are off in raids" }, lead = { mode = "none", reason = "" } })
    T.True(off[1]:find("not going out", 1, true), "comms down is said first")
    T.True(off[1]:find("own rules", 1, true), "with what that means")
    T.True(off[3]:find("none heard", 1, true), "and nobody heard")
end)

T.Case("Comms: the public functions answer safely before comms start (headless)", function()
    T.Eq(Comms.IsLead(), false, "not the lead before anything is known")
    T.Eq(Comms.Known(), false, "and says it does not know yet")
    T.Eq(Lead.IsMe(), nil, "so Lead.IsMe is nil, and DeathWatch's own fallback decides")
    T.True(type(Comms.Lead()) == "table", "a lead result exists")
    local rules = Comms.ActiveRules("i:999999")
    T.True(type(rules) == "table", "active rules is a table")
    T.Eq(Comms.Published("i:999999"), nil, "no published plan")
    T.True(type(Comms.Versions()) == "table", "versions")
    T.True(type(Comms.Durability()) == "table", "durability")
    T.Eq(Comms.Status().channel, nil, "no channel")
    local ok, why = Comms.PublishPlan("open", {})
    T.Eq(ok, false, "publishing refused")
    T.True(why ~= nil, "with a reason")
    local fired
    Comms.Listen("test", function(kind) fired = kind end)
    Comms.Unlisten("test")
    T.Eq(fired, nil, "listen and unlisten do not raise")
end)
