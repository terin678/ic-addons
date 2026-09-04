local addonName, ns = ...

ns.Tests = ns.Tests or {}
local T = ns.Tests
T.cases = {}

--[[
The harness came from ICTemplate. What is worth reading here are the cases: two
officers editing in the same minute have to end up agreeing, and they have to
agree on the SAME answer without saying another word to each other. That rule is
Doc.Compare, and it is the reason most of this file exists.

Written in game with /gr test, and the result goes to SavedVariables so it can be
read after a /reload took the chat frame with it.
]]

function T.Case(name, fn)
    T.cases[#T.cases + 1] = { name = name, fn = fn }
end

function T.Eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected [%s], got [%s]",
            tostring(label or "value"), tostring(expected), tostring(actual)), 2)
    end
end

function T.True(value, label)
    if not value then
        error(string.format("%s: expected something true, got [%s]",
            tostring(label or "value"), tostring(value)), 2)
    end
end

-- Runs fn against a made-up saved-variables table and puts the real one back
-- afterwards, whatever fn does.
function T.With(db, cdb, fn)
    local realDB, realCDB = ns.db, ns.cdb
    ns.db, ns.cdb = db, cdb or {}
    local ok, err = pcall(fn)
    ns.db, ns.cdb = realDB, realCDB
    if not ok then error(err, 2) end
end

function T.Run()
    local pass, fail = 0, 0
    ns.db.lastTestRun = { at = ns.Now(), failures = {} }

    for _, case in ipairs(T.cases) do
        local ok, err = pcall(case.fn)
        if ok then
            pass = pass + 1
        else
            fail = fail + 1
            ns.Print("|cffff4444FAIL|r " .. case.name .. " => " .. tostring(err))
            local f = ns.db.lastTestRun.failures
            f[#f + 1] = { name = case.name, err = tostring(err) }
        end
    end

    ns.db.lastTestRun.passed, ns.db.lastTestRun.failed = pass, fail
    ns.Printf("Tests: |cff44ff44%d passed|r, %s%d failed|r",
        pass, fail > 0 and "|cffff4444" or "|cff44ff44", fail)
    if ns.UI then ns.UI.Refresh() end
    return pass, fail
end

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

local function Need(role, class, count, priority)
    return { role = role, class = class or "", count = count or 1, priority = priority or 1 }
end

local function Team(id, name, tag, days, needs)
    return {
        id = id, name = name, tag = tag, days = days or "", active = true,
        priority = id, needs = needs or {},
    }
end

-- The guild's actual shape: two teams, both recruiting, one message between them.
local function TwoTeams()
    return {
        rev = 4, author = "Malexis", updatedAt = 1750000000, guild = "Impulse Control",
        template = "<{guild}> is recruiting: {teams}. Whisper {contacts}!",
        teamTemplate = "{tag} {days}: {needs}",
        contacts = { "Malexis" },
        teams = {
            Team(1, "Tuesday Core", "T1", "Tue/Thu 8-11", {
                Need("Healer", "Priest", 2, 1),
                Need("DPS", "", 3, 2),
            }),
            Team(2, "Sunday Alt", "T2", "Sun 7-10", {
                Need("Tank", "Warrior", 1, 1),
                Need("DPS", "Mage", 2, 2),
            }),
        },
    }
end

local function Version(rev, updatedAt, author)
    return { rev = rev, updatedAt = updatedAt, author = author }
end

--------------------------------------------------------------------------------
-- Doc: the rule two officers have to agree on
--------------------------------------------------------------------------------

T.Case("Doc: a higher revision wins, whatever the clocks say", function()
    T.Eq(ns.Doc.Compare(Version(7, 1000, "Aeryn"), Version(6, 1000, "Zed")), "local",
        "revision is what decides")
    T.Eq(ns.Doc.Compare(Version(6, 1000, "Zed"), Version(7, 1000, "Aeryn")), "remote",
        "and it decides the same way round the other way")

    -- The case the whole design exists for. Somebody's clock is a year fast, and
    -- their revision is still older, so they still lose. Clocks are not causality.
    T.Eq(ns.Doc.Compare(Version(7, 1000, "Aeryn"), Version(6, 1999999999, "Zed")), "local",
        "a stale sender with a fast clock loses")
    T.Eq(ns.Doc.Compare(Version(6, 1999999999, "Zed"), Version(7, 1000, "Aeryn")), "remote",
        "and our own broken clock does not save us either")
end)

T.Case("Doc: the same revision falls back to the newer edit", function()
    T.Eq(ns.Doc.Compare(Version(7, 1050, "Zed"), Version(7, 1000, "Aeryn")), "local", "newer")
    T.Eq(ns.Doc.Compare(Version(7, 1000, "Zed"), Version(7, 1050, "Aeryn")), "remote", "older")
end)

T.Case("Doc: the real race, and both clients pick the same winner", function()
    -- Two raid leaders both went 6 -> 7 in the same second. There is no right
    -- answer; there is only the requirement that both machines choose the same
    -- one, or they hand the document back and forth forever.
    local aeryn, zed = Version(7, 1000, "Aeryn"), Version(7, 1000, "Zed")
    T.Eq(ns.Doc.Compare(aeryn, zed), "local", "on Aeryn's client, Aeryn's wins")
    T.Eq(ns.Doc.Compare(zed, aeryn), "remote", "and on Zed's client, Aeryn's wins too")

    -- The symmetry IS the property, which is why both directions are asserted in
    -- one case rather than two.
    T.Eq(ns.Doc.Compare(aeryn, aeryn), "same", "a self-echo changes nothing")
    T.Eq(ns.Doc.Compare(Version(7, 1000, "aeryn"), Version(7, 1000, "Aeryn")), "same",
        "and casing cannot make two clients disagree")
end)

T.Case("Doc: the edges of comparing at all", function()
    T.Eq(ns.Doc.Compare(Version(0, 0, ""), Version(1, 1000, "Aeryn")), "remote",
        "a fresh install takes whatever the guild has")
    T.Eq(ns.Doc.Compare(Version(7, 1000, "Aeryn"), nil), "local",
        "a dropped message is not a reset")
    T.Eq(ns.Doc.Compare(nil, Version(1, 1000, "Aeryn")), "remote", "and neither is having none")
end)

T.Case("Doc: a revision outranks anything ever seen, not just our own", function()
    T.Eq(ns.Doc.NextRev(5, 5), 6, "the ordinary edit")
    -- Saw rev 9 go past, did not take it, then edited. The edit has to beat 9 or
    -- it loses to a document this client already decided against.
    T.Eq(ns.Doc.NextRev(5, 9), 10, "an edit made after seeing a higher revision")
    T.Eq(ns.Doc.NextRev(9, 3), 10, "a revision never goes backwards")
    T.Eq(ns.Doc.NextRev(nil, nil), 1, "the first edit anyone makes")
end)

T.Case("Doc: merging keeps a copy, never the sender's table", function()
    local mine = TwoTeams()
    local theirs = TwoTeams()
    theirs.rev, theirs.author = 9, "Zed"

    local merged, outcome = ns.Doc.Merge(mine, theirs)
    T.Eq(outcome, "took-remote", "theirs is newer")
    T.Eq(merged.rev, 9, "and it is what we hold now")

    -- A later chunk from the same sender must not reach into what we committed.
    theirs.template = "something else entirely"
    T.True(merged.template ~= "something else entirely", "the stored copy is ours")

    local kept, why = ns.Doc.Merge(theirs, mine)
    T.Eq(why, "kept-local", "and ours wins when ours is newer")
    T.Eq(kept, theirs, "without copying anything")
end)

T.Case("Doc: the hash ignores order and notices content", function()
    local a, b = TwoTeams(), TwoTeams()
    T.Eq(ns.Doc.Hash(a), ns.Doc.Hash(b), "two identical documents hash the same")

    -- Needs are sorted before hashing, so two clients that stored them in a
    -- different order still agree they hold the same message.
    b.teams[1].needs = { b.teams[1].needs[2], b.teams[1].needs[1] }
    T.Eq(ns.Doc.Hash(a), ns.Doc.Hash(b), "the order needs were added in does not count")

    b.teams[1].needs[1].count = 99
    T.True(ns.Doc.Hash(a) ~= ns.Doc.Hash(b), "but a changed value does")

    -- rev, author and updatedAt are deliberately outside the hash: two clients can
    -- hold the same message under different revisions, and the hash is how they
    -- notice they have converged.
    local c = TwoTeams()
    c.rev, c.author, c.updatedAt = 99, "Zed", 1
    T.Eq(ns.Doc.Hash(a), ns.Doc.Hash(c), "the revision is not part of the message")
end)

T.Case("Doc: what arrives from another player is not trusted", function()
    local now = 1750000000
    local raw = TwoTeams()
    raw.author = "Malexis"

    T.True(ns.Doc.Sanitize(raw, "Malexis", "Impulse Control", now) ~= nil, "a good one passes")

    -- A message claiming somebody else wrote it is a message lying about it.
    T.Eq(ns.Doc.Sanitize(raw, "Zed", "Impulse Control", now), nil, "author is not the sender")
    T.Eq(ns.Doc.Sanitize(raw, "Malexis", "Some Other Guild", now), nil, "wrong guild")

    local future = TwoTeams()
    future.updatedAt = now + 3600
    T.Eq(ns.Doc.Sanitize(future, "Malexis", "Impulse Control", now), nil, "an hour ahead")

    local nudged = TwoTeams()
    nudged.updatedAt = now + 120
    T.True(ns.Doc.Sanitize(nudged, "Malexis", "Impulse Control", now) ~= nil,
        "two minutes ahead is two guildmates' clocks disagreeing, not an attack")

    local ancient = TwoTeams()
    ancient.updatedAt = 12345
    T.Eq(ns.Doc.Sanitize(ancient, "Malexis", "Impulse Control", now), nil, "impossibly old")

    -- Markup in a name would colour the rest of whatever row it lands in.
    local nasty = TwoTeams()
    nasty.teams[1].name = "|cffff0000BIG|r |Hplayer:Zed|h[Zed]|h"
    local clean = ns.Doc.Sanitize(nasty, "Malexis", "Impulse Control", now)
    T.Eq(clean.teams[1].name:find("|", 1, true), nil, "not one pipe survives")

    -- Sizes are ours to decide, not the sender's.
    local huge = TwoTeams()
    for i = 1, 20 do huge.teams[#huge.teams + 1] = Team(10 + i, "Spam " .. i, "S") end
    T.Eq(#ns.Doc.Sanitize(huge, "Malexis", "Impulse Control", now).teams, ns.Doc.MAX_TEAMS,
        "a hundred teams becomes as many as fit")
end)

T.Case("Doc: agreement counts who is where", function()
    local doc = TwoTeams()
    doc.hash = ns.Doc.Hash(doc)
    local peers = {
        Aeryn = { rev = 4, hash = ns.Doc.Hash(doc) },
        Zed = { rev = 2 },
        Threnody = { rev = 9 },
    }
    local same, behind, ahead = ns.Doc.Agreement(doc, peers)
    T.Eq(same, 1, "one has it")
    T.Eq(behind, 1, "one is behind")
    T.Eq(ahead, 1, "one is ahead")
end)

--------------------------------------------------------------------------------
-- Message: two teams, one line, 255 characters
--------------------------------------------------------------------------------

T.Case("Message: both teams fit at full detail when there is room", function()
    local doc = TwoTeams()
    local msg, level, dropped = ns.Message.Assemble(doc, 1)
    T.True(msg ~= nil, "there is a message")
    T.Eq(level, 1, "nothing had to be given up")
    T.Eq(dropped, 0, "and nothing was left out")
    T.True(#msg <= ns.Message.MAX_LEN, "inside the limit")
    T.True(msg:find("T1", 1, true) ~= nil, "team one is in it")
    T.True(msg:find("T2", 1, true) ~= nil, "and so is team two")
    T.True(msg:find("Priest", 1, true) ~= nil, "classes survive at level 1")
end)

T.Case("Message: detail is given up in order, a step at a time", function()
    local doc = TwoTeams()
    local full = ns.Message.Assemble(doc, 1)

    -- Squeeze the budget one step at a time and watch what goes first.
    local a = ns.Message.Assemble(doc, 1, #full - 1)
    T.True(a ~= nil, "still a message")
    T.Eq(a:find("Priest", 1, true), nil, "the class is the first thing to go")

    local tight = ns.Message.Assemble(doc, 1, 96)
    T.True(tight ~= nil, "and it keeps going")
    T.Eq(tight:find("Tue/Thu", 1, true), nil, "the days go next")
    T.True(tight:find("2x", 1, true) ~= nil, "counts are still worth keeping at that point")
end)

T.Case("Message: neither team is ever starved out of the message", function()
    -- This is the property the whole degrade ladder exists to hold. Whenever the
    -- tags fit at all, BOTH tags are in the line: an officer must never send a
    -- message that quietly recruits for one team only.
    local doc = TwoTeams()
    for budget = 90, 200, 5 do
        local msg = ns.Message.Assemble(doc, 1, budget)
        if msg then
            T.True(msg:find("T1", 1, true) ~= nil,
                "team one survived a budget of " .. budget)
            T.True(msg:find("T2", 1, true) ~= nil,
                "team two survived a budget of " .. budget)
            T.True(#msg <= budget, "and the line fits in " .. budget)
        end
    end
end)

T.Case("Message: what will not fit is reported, not silently dropped", function()
    local doc = TwoTeams()
    for i = 1, 4 do
        doc.teams[1].needs[#doc.teams[1].needs + 1] = Need("Filler " .. i, "", 1, 5 + i)
    end
    local msg, _, dropped = ns.Message.Assemble(doc, 1, 110)
    T.True(msg ~= nil, "there is still a message")
    T.True(dropped > 0, "and it says how many needs did not make it")
end)

T.Case("Message: a team with nothing to ask for is not in the message", function()
    local doc = TwoTeams()
    doc.teams[2].needs = {}
    local msg = ns.Message.Assemble(doc, 1)
    T.Eq(msg:find("T2", 1, true), nil, "an empty team is left out")

    doc.teams[2].needs = { Need("Tank", "", 1, 1) }
    doc.teams[2].active = false
    msg = ns.Message.Assemble(doc, 1)
    T.Eq(msg:find("T2", 1, true), nil, "and so is one that is switched off")

    doc.teams[1].active = false
    local none, _, _, _, reason = ns.Message.Assemble(doc, 1)
    T.Eq(none, nil, "with both off there is nothing to send")
    T.Eq(reason, "every team is switched off: turn one back on with its On button",
        "and it names the button that fixes it")
end)

T.Case("Message: having nothing to send says WHICH nothing", function()
    -- All four of these used to be the single word "nothing to recruit". A new install
    -- seeds two teams with no needs, so the useless one was the first thing anybody saw.
    local function reasonFor(build)
        local doc = TwoTeams()
        build(doc)
        local msg, _, _, _, why = ns.Message.Assemble(doc, 1)
        T.Eq(msg, nil, "nothing assembles")
        return why
    end

    local noTeams = reasonFor(function(doc) doc.teams = {} end)
    T.Eq(noTeams, "no teams yet: add one on the Teams tab", "no teams at all")

    -- What a fresh install looks like: SeedTeams makes two teams and no needs.
    local noNeeds = reasonFor(function(doc)
        for _, team in ipairs(doc.teams) do team.needs = {} end
    end)
    T.Eq(noNeeds, "no roles wanted yet: pick a team on the Teams tab and add a need",
        "teams exist but want nobody")

    local allOff = reasonFor(function(doc)
        for _, team in ipairs(doc.teams) do team.active = false end
    end)
    T.Eq(allOff, "every team is switched off: turn one back on with its On button",
        "teams want people but are switched off")

    -- The mixed case: one team is on but wants nobody, the other wants people but is off.
    -- Neither "no roles wanted" nor "every team is off" is true, and both would mislead.
    local mixed = reasonFor(function(doc)
        doc.teams[1].needs = {}
        doc.teams[2].active = false
    end)
    T.Eq(mixed, "the only teams asking for anyone are switched off",
        "one team on with no needs, one with needs switched off")
end)

T.Case("Message: a template with nowhere to put the teams is refused", function()
    local doc = TwoTeams()
    doc.template = "we are recruiting, whisper me"
    local msg, _, _, _, reason = ns.Message.Assemble(doc, 1)
    T.Eq(msg, nil, "no message")
    T.True(reason:find("{teams}", 1, true) ~= nil, "and the reason names the token")
end)

T.Case("Message: the lead team rotates so the same one is not always cut", function()
    local teams = { { tag = "A" }, { tag = "B" }, { tag = "C" } }
    local ordered, nextCursor = ns.Message.Rotate(teams, 1)
    T.Eq(ordered[1].tag .. ordered[2].tag .. ordered[3].tag, "ABC", "starting at one")
    T.Eq(nextCursor, 2, "and moving on")

    ordered, nextCursor = ns.Message.Rotate(teams, 3)
    T.Eq(ordered[1].tag .. ordered[2].tag .. ordered[3].tag, "CAB", "wrapping round")
    T.Eq(nextCursor, 1, "back to the start")

    -- A cursor left over from a document that had more teams in it is a stale
    -- saved variable, not a crash.
    ordered = ns.Message.Rotate(teams, 99)
    T.Eq(ordered[1].tag, "A", "a cursor past the end resets")
    T.Eq(#ns.Message.Rotate({}, 1), 0, "and no teams is not an error")
end)

T.Case("Message: a fragment survives an empty token in the middle of it", function()
    local team = Team(1, "Tuesday", "T1", "", { Need("Healer", "Priest", 2, 1) })
    -- No days set, so "{tag} {days}: {needs}" would leave " :" hanging.
    T.Eq(ns.Message.TeamFragment(team, 1), "T1: 2x Priest Healer", "no stray punctuation")

    team.needs = {}
    T.Eq(ns.Message.TeamFragment(team, 1), "T1", "and no trailing colon either")

    team.days = "Tue"
    T.Eq(ns.Message.TeamFragment(team, 1), "T1 Tue", "days with nothing to ask for")
end)

T.Case("Message: the last look before it goes out", function()
    T.Eq(ns.Message.Validate("", 255), false, "nothing to send")
    T.Eq(ns.Message.Validate(string.rep("x", 256), 255), false, "too long")
    T.Eq(ns.Message.Validate("one\ntwo", 255), false, "a chat line has no line breaks")

    -- A cut that opened a colour and never closed it would paint the rest of the
    -- chat window, including other people's lines.
    T.Eq(ns.Message.Validate("|cff44ff44green", 255), false, "an unclosed colour")
    T.Eq(ns.Message.Validate("|cff44ff44green|r", 255), true, "a closed one is fine")
    T.Eq(ns.Message.Validate("LF 2 healers", 255), true, "and an ordinary line passes")
end)

--------------------------------------------------------------------------------
-- Roster: who is allowed to do what
--------------------------------------------------------------------------------

T.Case("Roster: rank 0 is the guild master and lower is a larger number", function()
    T.Eq(ns.Roster.MayAuthor(0, 1), true, "the guild master, under a threshold of 1")
    T.Eq(ns.Roster.MayAuthor(1, 1), true, "and anyone at the threshold")
    T.Eq(ns.Roster.MayAuthor(2, 1), false, "but not below it")

    -- The off-by-one that would otherwise ship: at a threshold of 0, only rank 0.
    T.Eq(ns.Roster.MayAuthor(1, 0), false, "rank 1 cannot author at a threshold of 0")
    T.Eq(ns.Roster.MayAuthor(0, 0), true, "rank 0 can")

    -- A roster that has not loaded is not permission.
    T.Eq(ns.Roster.MayAuthor(nil, 5), false, "an unknown rank may do nothing")
    T.Eq(ns.Roster.MayAuthor("officer", 5), false, "and neither may a rank that is text")
end)

T.Case("Roster: names, indexes and strangers", function()
    T.Eq(ns.Roster.Short("Aeryn-Nightslayer"), "Aeryn", "a realm suffix comes off")
    T.Eq(ns.Roster.Short("Aeryn"), "Aeryn", "and a name without one is left alone")
    T.Eq(ns.Roster.Short(nil), "", "nil is not an error")

    local rows = {
        { name = "Malexis", rank = "Guild Master", rankIndex = 0, online = true },
        { name = "Aeryn-Nightslayer", rank = "Officer", rankIndex = 1, online = false },
        { name = "Zed", rank = "Member", rankIndex = 4, online = true },
    }
    local byName, count, online = ns.Roster.Index(rows)
    T.Eq(count, 3, "everyone counted once")
    T.Eq(online, 2, "and the online ones counted")
    T.Eq(byName["Aeryn"].rankIndex, 1, "indexed by the short name")

    T.Eq(ns.Roster.RankOf(byName, "Zed"), 4, "a known name")
    T.Eq(ns.Roster.RankOf(byName, "Nobody", 99), 99, "and a stranger gets the fallback")
    T.Eq(ns.Roster.RankOf(nil, "Zed", 99), 99, "as does anyone, with no roster at all")

    T.Eq(select(2, ns.Roster.Index({})), 0, "an empty roster is not an error")
    T.Eq(ns.Roster.Sorted(rows)[1].name, "Malexis", "sorted by rank, then name")

    -- The guild window numbers ranks from 1 and the game reports them from 0, so a
    -- bare number on a settings page is read by half its readers as the other one.
    -- Showing the guild's own name for that rank is what stops the guessing.
    T.Eq(ns.Roster.RankName(rows, 0), "Guild Master", "the guild's own word for rank 0")
    T.Eq(ns.Roster.RankName(rows, 1), "Officer", "and for rank 1")
    T.Eq(ns.Roster.RankName(rows, 9), nil, "a rank nobody holds has no name here")
    T.Eq(ns.Roster.RankName({}, 0), nil, "and neither does anything, with no roster")
end)

--------------------------------------------------------------------------------
-- Bark: the gate, and not doubling up
--------------------------------------------------------------------------------

T.Case("Bark: somebody else already said it", function()
    local barks = {
        { who = "Zed", at = 1000, channel = "Trade" },
        { who = "Malexis", at = 990, channel = "Trade" },
    }
    local who, ago = ns.Bark.Suppressed(barks, 1100, 600, "Trade", "Malexis")
    T.Eq(who, "Zed", "Zed did")
    T.Eq(ago, 100, "a hundred seconds ago")

    T.Eq(ns.Bark.Suppressed({ { who = "Malexis", at = 1000, channel = "Trade" } },
        1100, 600, "Trade", "Malexis"), nil,
        "our own barks are the timer's job, not this one's")
    T.Eq(ns.Bark.Suppressed(barks, 1100, 600, "Trade", "Zed"), "Malexis",
        "and skipping our own does not mean skipping everybody")
    T.Eq(ns.Bark.Suppressed(barks, 1100, 600, "General", "Malexis"), nil,
        "a different channel is a different audience")
    T.Eq(ns.Bark.Suppressed(barks, 5000, 600, "Trade", "Malexis"), nil,
        "and past the window it stops mattering")
    T.Eq(ns.Bark.Suppressed(barks, 1100, 0, "Trade", "Malexis"), nil, "zero switches it off")
    T.Eq(ns.Bark.Suppressed({}, 1100, 600, "Trade", "Malexis"), nil, "nobody has said anything")

    -- Newest first, so the closest bark is the one reported.
    table.insert(barks, 1, { who = "Threnody", at = 1090, channel = "Trade" })
    T.Eq(ns.Bark.Suppressed(barks, 1100, 600, "Trade", "Malexis"), "Threnody", "the most recent")
end)

T.Case("Bark: the log is ordered by time, not by arrival", function()
    local log = {}
    T.Eq(ns.Bark.Insert(log, { who = "Zed", at = 100 }, 60), true, "the first one")
    T.Eq(ns.Bark.Insert(log, { who = "Zed", at = 100 }, 60), false, "the same one twice")
    T.Eq(#log, 1, "is one entry")

    ns.Bark.Insert(log, { who = "Aeryn", at = 300 }, 60)
    -- A remote bark can arrive late, after a reconnect. Filed in the wrong place
    -- it would make the suppression window lie about how long ago it was.
    ns.Bark.Insert(log, { who = "Threnody", at = 200 }, 60)
    T.Eq(log[1].at .. "," .. log[2].at .. "," .. log[3].at, "300,200,100", "newest first")

    for i = 1, 70 do ns.Bark.Insert(log, { who = "Filler", at = 1000 + i }, 60) end
    T.Eq(#log, 60, "capped")
    T.Eq(log[1].at, 1070, "keeping the newest")
end)

T.Case("Bark: every reason it will not send, in a fixed order", function()
    local function state(over)
        local s = {
            addonEnabled = true, inGuild = true, canBark = true,
            pauseCombat = true, pauseInstance = true,
            inCombat = false, inInstance = false,
            channel = 3, channelName = "Trade",
        }
        for k, v in pairs(over or {}) do s[k] = v end
        return s
    end

    T.Eq(ns.Bark.BlockReason(state()), nil, "nothing in the way")
    T.Eq(ns.Bark.BlockReason(state({ addonEnabled = false })),
        "GuildRecruitment is disabled", "the addon")
    T.Eq(ns.Bark.BlockReason(state({ inGuild = false })), "you are not in a guild", "the guild")
    T.Eq(ns.Bark.BlockReason(state({ canBark = false })),
        "your guild rank is not allowed to send it", "this officer")
    T.Eq(ns.Bark.BlockReason(state({ inCombat = true })), "in combat", "the world")
    T.Eq(ns.Bark.BlockReason(state({ inCombat = true, pauseCombat = false })), nil,
        "unless you asked it not to care")
    T.Eq(ns.Bark.BlockReason(state({ inInstance = true })), "in an instance", "or an instance")
    -- Cleared after the fact, not passed in: `{ channel = nil }` is an EMPTY table
    -- in Lua, so the override never happens and the field keeps its default. This
    -- shipped green from a Python port of these cases, where a dict really can
    -- hold a None, and failed the first time it ran in the client.
    local noChannel = state()
    noChannel.channel = nil
    T.Eq(ns.Bark.BlockReason(noChannel):find("no channel", 1, true), 1,
        "somewhere to send it")
    T.Eq(ns.Bark.BlockReason(state({ messageReason = "nothing to recruit" })),
        "nothing to recruit", "something to say")
    T.Eq(ns.Bark.BlockReason(state({ suppressedBy = "Zed", suppressedAgo = 240 })),
        "Zed barked 4m ago", "and last, other people")

    -- The order is the contract, not an accident: the UI shows the FIRST reason,
    -- and one that changes with whichever check ran first is worse than none.
    T.Eq(ns.Bark.BlockReason(state({ addonEnabled = false, inCombat = true })),
        "GuildRecruitment is disabled", "widest reason first")
    T.Eq(ns.Bark.BlockReason(state({ inCombat = true, suppressedBy = "Zed",
        suppressedAgo = 10 })), "in combat", "the world before other people")
end)

T.Case("Bark: finding a channel in a list with a stride of three", function()
    -- GetChannelList returns id, name, disabled, id, name, disabled. Reading it
    -- with a stride of two takes every other name as an id.
    local list = { 1, "General - Shattrath", false, 2, "Trade - Shattrath", false,
                   5, "LookingForGroup", false }

    local id, name = ns.Bark.Channel(list, "auto")
    T.Eq(id, 5, "auto prefers LookingForGroup")
    T.Eq(name, "LookingForGroup", "and says which it picked")

    T.Eq(ns.Bark.Channel(list, "Trade"), 2, "a substring finds Trade - Shattrath")
    T.Eq(ns.Bark.Channel(list, "general"), 1, "and it is not case sensitive")
    T.Eq(ns.Bark.Channel(list, "Guild Recruitment"), nil, "a channel nobody joined")
    T.Eq(ns.Bark.Channel({}, "auto"), nil, "an empty list is not an error")

    -- Without LookingForGroup, auto falls through to Trade and then General.
    T.Eq(ns.Bark.Channel({ 1, "General", false, 2, "Trade", false }, "auto"), 2,
        "Trade before General")
end)

T.Case("Bark: interval and due", function()
    T.Eq(ns.Bark.ClampInterval(900), 900, "fifteen minutes passes through")
    T.Eq(ns.Bark.ClampInterval(30), 300, "recruiting every thirty seconds is spam")
    T.Eq(ns.Bark.ClampInterval(99999), 3600, "and an hour is as far apart as it goes")

    T.Eq(ns.Bark.IsDue(1000, 1899, 900), false, "one second early")
    T.Eq(ns.Bark.IsDue(1000, 1900, 900), true, "exactly on the boundary")
    T.Eq(ns.Bark.IsDue(nil, 900, 900), true, "never sent is always due")
end)

--------------------------------------------------------------------------------
-- Comm: the wire
--------------------------------------------------------------------------------

T.Case("Comm: escaping survives anything a raid leader can type", function()
    local nasty = "LF 2 heals ^ ~ |cffff0000 50% off\nnewline"
    T.Eq(ns.Comm.Unescape(ns.Comm.Escape(nasty)), nasty, "it round trips")

    local escaped = ns.Comm.Escape(nasty)
    T.Eq(escaped:find("^", 1, true), nil, "no separator survives")
    T.Eq(escaped:find("~", 1, true), nil, "of either kind")
    T.Eq(escaped:find("|", 1, true), nil, "nor a pipe")

    -- The percent sign has to encode first or the decoder eats the next two
    -- characters of somebody's actual text.
    T.Eq(ns.Comm.Escape("50% off"), "50%25 off", "a percent encodes to %25")

    -- The common case costs nothing: an ordinary line encodes to itself.
    T.Eq(ns.Comm.Escape("LF 2 heals for Kara, whisper Malexis!"),
        "LF 2 heals for Kara, whisper Malexis!", "plain text is untouched")
end)

T.Case("Comm: splitting is bounded and keeps empty fields", function()
    T.Eq(#ns.Comm.Split("a^b^c", "^", 12), 3, "three fields")
    T.Eq(ns.Comm.Split("a^^b", "^", 12)[2], "", "an empty field is a field, not a skip")

    -- Two hundred separators must not build a two hundred entry table.
    T.Eq(#ns.Comm.Split(string.rep("^", 200), "^", 12), 12, "bounded")
end)

T.Case("Comm: the envelope leaves the payload alone", function()
    local text = ns.Comm.Envelope("S", 3, 1, 2, "x^y^z")
    local op, msgid, seq, total, payload = ns.Comm.ParseEnvelope(text)
    T.Eq(op, "S", "the operation")
    T.Eq(msgid, 3, "the message id")
    T.Eq(seq .. "/" .. total, "1/2", "which chunk of how many")
    -- The case a naive whole-string split fails: the payload has its own
    -- separators and they have to come back untouched.
    T.Eq(payload, "x^y^z", "the payload keeps its own separators")

    T.Eq(ns.Comm.ParseEnvelope("1^S^3^1"), nil, "too short")
    T.Eq(select(2, ns.Comm.ParseEnvelope("2^S^3^1^1^x")), "proto", "from the future")
    T.Eq(select(2, ns.Comm.ParseEnvelope("1^Z^3^1^1^x")), "op", "an operation we do not know")
    T.Eq(select(2, ns.Comm.ParseEnvelope("1^S^3^0^1^x")), "seq", "chunk zero")
    T.Eq(select(2, ns.Comm.ParseEnvelope("1^S^3^1^99^x")), "total", "more chunks than we allow")
end)

T.Case("Comm: chunking and putting it back together", function()
    local payload = string.rep("a", 450)
    local chunks = ns.Comm.Chunk(payload, 200)
    T.Eq(#chunks, 3, "three chunks")
    T.Eq(table.concat(chunks), payload, "that concatenate back")
    T.Eq(#ns.Comm.Chunk("", 200), 1, "an empty payload is still one chunk")

    -- Out of order, because nothing guarantees the order they arrive in.
    local buf = {}
    T.Eq(ns.Comm.Reassemble(buf, 7, 2, 2, "second", 100), nil, "waiting")
    T.Eq(ns.Comm.Reassemble(buf, 7, 1, 2, "first", 100), "firstsecond", "and complete")

    buf = {}
    ns.Comm.Reassemble(buf, 8, 1, 2, "a", 100)
    T.Eq(ns.Comm.Reassemble(buf, 8, 1, 2, "a", 100), nil, "a duplicate does not complete it")
    T.Eq(ns.Comm.Reassemble(buf, 8, 2, 2, "b", 100), "ab", "the real second chunk does")

    -- Somebody who reconnects mid-send must not leave a stuck half-message.
    buf = {}
    ns.Comm.Reassemble(buf, 9, 1, 3, "x", 100)
    T.Eq(ns.Comm.Reassemble(buf, 10, 1, 1, "fresh", 100), "fresh",
        "a new message id replaces the buffer outright")

    buf = {}
    ns.Comm.Reassemble(buf, 11, 1, 2, "x", 100)
    T.Eq(select(2, ns.Comm.Reassemble(buf, 11, 2, 2, "y", 100 + ns.Comm.CHUNK_TIMEOUT + 1)),
        "timeout", "and one that never finishes is thrown away")
end)

T.Case("Comm: the send budget", function()
    local bucket = { stamps = {} }
    for i = 1, 6 do
        T.Eq(ns.Comm.Bucket(bucket, 100, 6, 10), true, "message " .. i .. " is allowed")
    end
    T.Eq(ns.Comm.Bucket(bucket, 100, 6, 10), false, "the seventh in one second is not")
    T.Eq(ns.Comm.Bucket(bucket, 111, 6, 10), true, "and the window slides")
end)

T.Case("Comm: a document round trips the wire", function()
    local doc = TwoTeams()
    local payload = ns.Comm.EncodeState(doc)
    T.True(#payload <= ns.Comm.MAX_PAYLOAD, "it fits in what we will send")

    local back = ns.Comm.DecodeState(payload)
    T.True(back ~= nil, "and comes back")
    T.Eq(back.rev, doc.rev, "revision")
    T.Eq(back.author, doc.author, "author")
    T.Eq(back.template, doc.template, "template")
    T.Eq(#back.teams, 2, "both teams")
    T.Eq(back.teams[1].tag, "T1", "with their tags")
    T.Eq(back.teams[2].days, "Sun 7-10", "and their days")
    T.Eq(#back.teams[1].needs, 2, "needs land on the right team")
    T.Eq(back.teams[2].needs[1].role, "Tank", "and keep their fields")
    T.Eq(back.contacts[1], "Malexis", "contacts too")

    -- The hash is what two clients compare, so it has to survive the trip.
    local sanitized = ns.Doc.Sanitize(back, "Malexis", "Impulse Control", 1750000000)
    T.Eq(sanitized.hash, ns.Doc.Hash(doc), "and the message hashes the same at both ends")

    T.Eq(ns.Comm.DecodeState("garbage"), nil, "nonsense decodes to nothing")
    T.Eq(select(2, ns.Comm.DecodeState("1^2^3")), "short", "and says why")
end)

T.Case("Comm: the biggest document the window allows still fits on the wire", function()
    -- A transport that cannot carry the largest legal document is a transport that
    -- silently stops syncing for whoever fills the form in properly. The caps in
    -- Doc and the chunk budget in Comm have to be sized against each other, and
    -- this is where that is checked rather than discovered.
    local doc = {
        rev = 99, author = "Malexis", updatedAt = 1750000000, guild = "Impulse Control",
        template = "<{guild}> is recruiting: {teams}. Whisper {contacts}!",
        teamTemplate = "{tag} {days}: {needs}",
        contacts = { "Malexis", "Dezedin" },
        teams = {},
    }
    for t = 1, ns.Doc.MAX_TEAMS do
        local needs = {}
        for i = 1, ns.Doc.MAX_NEEDS do
            needs[i] = Need("Restoration Shaman", "Shaman", 2, i)
        end
        doc.teams[t] = Team(t, "Wednesday Progress " .. t, "TEAM" .. t,
            "Wed/Sun 8-11:30", needs)
    end

    local payload = ns.Comm.EncodeState(doc)
    T.True(#payload <= ns.Comm.MAX_PAYLOAD, string.format(
        "%d bytes to send, and the wire carries %d", #payload, ns.Comm.MAX_PAYLOAD))

    -- Braces are the most common characters in a template. Escaping them cost
    -- three bytes each and pushed exactly this document over the limit.
    T.Eq(ns.Comm.Escape("{teams}"), "{teams}", "a template token is not worth escaping")

    local back = ns.Comm.DecodeState(payload)
    T.Eq(#back.teams, ns.Doc.MAX_TEAMS, "and all of it comes back")
    T.Eq(#back.teams[1].needs, ns.Doc.MAX_NEEDS, "needs included")
end)

T.Case("Comm: a version offer and a bark round trip", function()
    local doc = TwoTeams()
    doc.hash = ns.Doc.Hash(doc)
    local back = ns.Comm.DecodeVersion(ns.Comm.EncodeVersion(doc))
    T.Eq(back.rev, 4, "revision")
    T.Eq(back.author, "Malexis", "author")
    T.Eq(back.hash, doc.hash, "and the hash to compare against")

    local bark = ns.Comm.DecodeBark(ns.Comm.EncodeBark("Zed", 1750000000, "Trade", 4, 187))
    T.Eq(bark.who, "Zed", "who")
    T.Eq(bark.at, 1750000000, "when")
    T.Eq(bark.channel, "Trade", "where")
    T.Eq(bark.len, 187, "and how long the line was")
end)

--------------------------------------------------------------------------------
-- Teams and Util
--------------------------------------------------------------------------------

T.Case("Teams: a team always has something short to call itself", function()
    local team = ns.Teams.Normalize({ id = 1, name = "  Tuesday Core  " })
    T.Eq(team.name, "Tuesday Core", "trimmed")
    T.Eq(team.tag, "TC", "and a tag made from the initials when nobody set one")

    T.Eq(ns.Teams.Normalize({ id = 2, name = "", tag = "" }).name, "Team 2",
        "a team with no name at all still has one")
    T.Eq(ns.Teams.Normalize({ id = 3, name = "Sunday", tag = "SUN" }).tag, "SUN",
        "and a tag somebody set is left alone")

    local need = ns.Teams.NormalizeNeed({ role = " healer ", count = "3" })
    T.Eq(need.role, "healer", "roles are trimmed")
    T.Eq(need.count, 3, "counts become numbers")
    T.Eq(ns.Teams.NormalizeNeed({ count = 0 }).count, 1, "and zero of something is one")
    T.Eq(ns.Teams.NormalizeNeed({ count = 999 }).count, 40, "and nine hundred is forty")
end)

T.Case("Teams: needs come back in the same order every time", function()
    local needs = {
        Need("Tank", "", 1, 2), Need("Healer", "", 2, 1), Need("DPS", "", 3, 1),
    }
    local a = ns.Teams.Sorted(needs)
    local b = ns.Teams.Sorted(needs)
    T.Eq(a[1].role .. a[2].role .. a[3].role, b[1].role .. b[2].role .. b[3].role,
        "twice in a row is the same order")
    T.Eq(a[1].role, "DPS", "priority first, then role")
    T.Eq(a[3].role, "Tank", "and the lowest priority is last, which is what gets cut")

    -- Sorting must not reorder the caller's own list, which is the document.
    T.Eq(needs[1].role, "Tank", "the original is untouched")
end)

T.Case("Teams: counting and identifying", function()
    local doc = TwoTeams()
    T.Eq(ns.Teams.TotalNeeded(doc), 8, "two plus three plus one plus two")
    doc.teams[2].active = false
    T.Eq(ns.Teams.TotalNeeded(doc), 5, "a team that is off is not recruiting")

    T.Eq(ns.Teams.NextId(doc), 3, "ids never get reused")
    T.Eq(ns.Teams.ById(doc, 2).name, "Sunday Alt", "found by id")
    T.Eq(ns.Teams.ById(doc, 99), nil, "and a missing one is nil")
end)

T.Case("Util: cleaning what another player sent", function()
    T.Eq(ns.Util.Clean("|cffff0000red|r", 255), "red", "colour codes come off")
    T.Eq(ns.Util.Clean("a|b", 255), "ab", "and so does a lone pipe")
    T.Eq(ns.Util.Clean("one\ntwo", 255), "one two", "line breaks become spaces")
    T.Eq(ns.Util.Clean("  spaced   out  ", 255), "spaced out", "runs of space collapse")
    T.Eq(#ns.Util.Clean(string.rep("x", 400), 24), 24, "and the length is ours to decide")
end)

T.Case("Util: how long ago, and how long left", function()
    T.Eq(ns.Util.Duration(0), "0s", "no time at all")
    T.Eq(ns.Util.Duration(240), "4m", "minutes")
    T.Eq(ns.Util.Duration(7200), "2h", "hours")
    T.Eq(ns.Util.Duration(-5), "0s", "and a clock that went backwards is not an error")

    local now = 1750000000
    T.Eq(ns.Util.Freshness(nil, now, 60), "never", "nothing recorded")
    T.Eq(ns.Util.Freshness(now - 90, now, 60), "1m", "and something that was")
end)

T.Case("UI: every page draws without erroring", function()
    -- The Settings page read settings.channel for a field that lives on
    -- settings.bark, and nothing caught it until somebody opened the tab. A page
    -- refresher is not pure, so no other case in this file reaches one; building
    -- the window and calling each one is the cheapest thing that does.
    --
    -- It is a smoke test, not a check of what is drawn. It catches the nil index,
    -- the bad format argument and the renamed field -- which is most of what goes
    -- wrong in a refresher.
    local frame = ns.UI.Create()
    T.Eq(type(frame), "table", "the window builds")
    T.Eq(#ns.UI.Pages > 0, true, "and it has pages")

    for _, page in ipairs(ns.UI.Pages) do
        T.Eq(type(page.refresh), "function", page.name .. " built a refresher")
        local ok, err = pcall(page.refresh)
        T.Eq(ok, true, page.name .. " draws => " .. tostring(err))
    end
end)

--------------------------------------------------------------------------------
-- Editing teams
--------------------------------------------------------------------------------

T.Case("Teams: editing writes the fields a raid leader can change", function()
    local doc = TwoTeams()
    local team = ns.Teams.ById(doc, 1)

    ns.Teams.Edit(team, { name = "Molten Core", days = "Wed 9-12" })
    T.Eq(team.name, "Molten Core", "the name is what was typed")
    T.Eq(team.days, "Wed 9-12", "and so are the days")
    T.Eq(team.tag, "T1", "a tag that was set by hand is left alone")

    -- Clearing the tag is how you say "follow the name again": otherwise a tag built from
    -- the old name sticks to the new one forever.
    ns.Teams.Edit(team, { tag = "" })
    T.Eq(team.tag, "MC", "a blank tag is rebuilt from the name's initials")
end)

T.Case("Teams: a team is never edited into something a message cannot carry", function()
    local doc = TwoTeams()
    local team = ns.Teams.ById(doc, 1)

    ns.Teams.Edit(team, { name = string.rep("x", 200) })
    T.Eq(#team.name, ns.Teams.MAX_NAME, "an over-long name is cut to the cap")

    ns.Teams.Edit(team, { name = "   ", tag = "   " })
    T.Eq(team.name, "Team 1", "a name of nothing but spaces falls back to the id")

    ns.Teams.Edit(team, { days = string.rep("y", 200) })
    T.Eq(#team.days, ns.Teams.MAX_DAYS, "and the days are capped too")
end)

T.Case("Teams: removing takes the right team, and never the last one", function()
    local doc = TwoTeams()

    local gone, why = ns.Teams.Remove(doc, 1)
    T.Eq(gone, true, "the team was removed")
    T.Eq(#doc.teams, 1, "one left")
    T.Eq(doc.teams[1].id, 2, "and it is the OTHER one")

    -- The last team cannot go: every screen reads doc.teams[1], and a document with
    -- nothing to recruit for is not a state this addon has a page for.
    gone, why = ns.Teams.Remove(doc, 2)
    T.Eq(gone, false, "the last team stays")
    T.Eq(#doc.teams, 1, "still one")
    T.Eq(type(why), "string", "and it says why")

    T.Eq(ns.Teams.Remove(TwoTeams(), 99), false, "an id nobody has removes nothing")
end)

T.Case("Teams: moving a team up reorders the document, not just the screen", function()
    local doc = TwoTeams()

    -- Array order is what Message.Rotate reads, so this decides which team leads the line.
    local moved = ns.Teams.MoveUp(doc, 2)
    T.Eq(moved, true, "the second team moved")
    T.Eq(doc.teams[1].id, 2, "and is now first")
    T.Eq(doc.teams[2].id, 1, "with the other one behind it")
    T.Eq(#doc.teams, 2, "nothing was lost on the way")

    local again, why = ns.Teams.MoveUp(doc, 2)
    T.Eq(again, false, "the first team cannot go higher")
    T.Eq(type(why), "string", "and it says so")
    T.Eq(doc.teams[1].id, 2, "and nothing moved")
end)

T.Case("Teams: a new team is complete enough to put in a message", function()
    local doc = TwoTeams()
    local id = ns.Teams.NextId(doc)
    T.Eq(id, 3, "one past the highest in use")

    local team = ns.Teams.New(id, "Team " .. id)
    T.Eq(team.active, true, "a new team is on")
    T.Eq(team.tag ~= "", true, "and has a tag without anybody typing one")
    T.Eq(#team.needs, 0, "and needs nothing yet")

    -- NextId is highest-plus-one, not a counter: removing the highest team hands its id
    -- straight back. Harmless, because Doc.Merge takes a whole document from one side or
    -- the other and never merges teams one at a time -- but worth pinning so nobody
    -- "fixes" it into a counter and breaks the wire format's assumption instead.
    doc.teams[#doc.teams + 1] = team
    T.Eq(ns.Teams.NextId(doc), 4, "with three teams the next id is 4")
    ns.Teams.Remove(doc, 3)
    T.Eq(ns.Teams.NextId(doc), 3, "and removing the highest gives that id back")
end)

T.Case("Message: the raid leader's team template is used, whatever tokens it has", function()
    local team = { tag = "DN", days = "M/W",
        needs = { { role = "DPS", class = "Shaman", count = 1, priority = 1 } } }

    -- The bug this pins: a template with no {tag} was silently swapped for the default, so
    -- "{needs} for our {days}" rendered as "DN M/W: Shaman DPS" and nothing said why.
    T.Eq(ns.Message.TeamFragment(team, 1, "{needs} for our {days}"),
        "Shaman DPS for our M/W", "a template without {tag} is still the author's")
    T.Eq(ns.Message.TeamFragment(team, 1, "{tag} {days}: {needs}"),
        "DN M/W: Shaman DPS", "and the default still reads as it always did")

    -- A template naming no token would repeat one constant string once per team, which is
    -- the only case worth overruling.
    T.Eq(ns.Message.TeamFragment(team, 1, "we want people"),
        "DN M/W: Shaman DPS", "a template with no tokens falls back to the default")
    T.Eq(ns.Message.TeamFragment(team, 1, nil),
        "DN M/W: Shaman DPS", "and so does no template at all")
end)

T.Case("Message: a team never renders to nothing and vanishes", function()
    -- At the bottom of the ladder every need is gone, so "{needs}" on its own empties out.
    -- Without a floor the team would drop out of the message without being counted as
    -- dropped, which is the one failure the degrade ladder must not have.
    local stripped = { tag = "DN", days = "M/W", needs = {} }
    T.Eq(ns.Message.TeamFragment(stripped, ns.Message.LEVELS, "{needs}"), "DN",
        "the tag is the floor")
    -- Level 2 rather than the floor: the ladder drops {days} above level 2, so at the floor
    -- this reads "for our" and the point about keeping the rest would be lost in it.
    T.Eq(ns.Message.TeamFragment(stripped, 2, "{needs} for our {days}"),
        "for our M/W", "anything else it still says is kept")
    T.Eq(ns.Message.TeamFragment(stripped, ns.Message.LEVELS, "{needs} for our {days}"),
        "for our", "and at the floor the days have gone too, but it is still not empty")

    -- A team with no tag of its own falls back to its name, so the floor is never blank.
    local unnamed = { name = "Sunday Alt", tag = "", needs = {} }
    T.Eq(ns.Message.TeamFragment(unnamed, ns.Message.LEVELS, "{needs}"), "Sunday Alt",
        "and the name stands in when there is no tag")
end)

T.Case("Message: a questionable team template is described, not corrected", function()
    local Check = ns.Message.CheckTeamTemplate

    T.Eq(Check("{tag} {days}: {needs}", 2), nil, "the default is fine")
    T.Eq(Check("{needs} for our {days}", 2), nil, "and so is one without a tag")
    T.Eq(Check("{needs}", 1), nil, "with a single team, {needs} alone is enough")

    T.Eq(type(Check("", 1)), "string", "an empty template is called out")
    T.Eq(type(Check("we are recruiting", 1)), "string", "and one with no tokens")
    T.Eq(type(Check("{tag} {days}", 1)), "string",
        "and one that never says who you are looking for")

    -- Two teams run together with nothing to tell them apart reads as one long list.
    T.Eq(type(Check("{needs}", 2)), "string", "two teams need something to tell them apart")
end)

T.Case("Teams: a need can be moved to another team", function()
    local doc = TwoTeams()
    local healer = doc.teams[1].needs[1]

    T.Eq(ns.Teams.MoveNeed(doc, healer, 2), true, "it moved")
    T.Eq(#doc.teams[1].needs, 1, "and left the team it was on")
    T.Eq(#doc.teams[2].needs, 3, "and arrived at the other one")
    T.Eq(doc.teams[2].needs[3], healer, "as the same need, not a copy")

    -- Moving it where it already is did nothing, which is not a failure.
    T.Eq(ns.Teams.MoveNeed(doc, healer, 2), true, "moving it onto its own team is fine")
    T.Eq(#doc.teams[2].needs, 3, "and changes nothing")
end)

T.Case("Teams: a move that cannot happen leaves everything where it was", function()
    local doc = TwoTeams()
    local healer = doc.teams[1].needs[1]

    local ok, why = ns.Teams.MoveNeed(doc, healer, 99)
    T.Eq(ok, false, "there is no team 99")
    T.Eq(type(why), "string", "and it says so")
    T.Eq(#doc.teams[1].needs, 2, "the need stayed where it was")

    T.Eq(ns.Teams.MoveNeed(doc, { role = "Tank" }, 1), false, "a need on no team moves nowhere")
    T.Eq(ns.Teams.MoveNeed(doc, nil, 1), false, "and neither does nothing")

    -- A full team refuses rather than taking one too many: the message has a size, and a
    -- need that left one team without arriving at the other would just be gone.
    local full = TwoTeams()
    local first = full.teams[1].needs[1]
    full.teams[2].needs = {}
    for i = 1, ns.Doc.MAX_NEEDS do
        full.teams[2].needs[i] = { role = "DPS", class = "", count = 1, priority = i }
    end
    local moved, reason = ns.Teams.MoveNeed(full, first, 2)
    T.Eq(moved, false, "the target is full")
    T.Eq(type(reason), "string", "and says which way it is full")
    T.Eq(#full.teams[1].needs, 2, "so the need is still on its own team")
    T.Eq(#full.teams[2].needs, ns.Doc.MAX_NEEDS, "and the full one did not grow")
end)
