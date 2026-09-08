local addonName, ns = ...

--[[
The harness -- Case, Eq, True, With, Run -- is LibICCore's. What is worth reading
here are the cases: two officers editing in the same minute have to end up agreeing,
and they have to agree on the SAME answer without saying another word to each other.
That rule is Doc.Compare, and it is the reason most of this file exists.

Written in game with /gr test, and the result goes to SavedVariables so it can be
read after a /reload took the chat frame with it.
]]

local T = ns.Tests

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

local LINE = "<Impulse Control> is recruiting healers and ranged for Kara and Gruul, "
    .. "Tue/Thu 8-11. /w me"

-- The guild's actual shape: one line, one revision.
local function Doc(rev, text)
    return {
        rev = rev or 4, author = "Malexis", updatedAt = 1750000000, guild = "Impulse Control",
        text = text or LINE,
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
    local mine = Doc()
    local theirs = Doc(9, "LF healers for Kara. /w Zed")
    theirs.author = "Zed"

    local merged, outcome = ns.Doc.Merge(mine, theirs)
    T.Eq(outcome, "took-remote", "theirs is newer")
    T.Eq(merged.rev, 9, "and it is what we hold now")
    T.Eq(merged.text, "LF healers for Kara. /w Zed", "text and all")

    -- A later chunk from the same sender must not reach into what we committed.
    theirs.text = "something else entirely"
    T.True(merged.text ~= "something else entirely", "the stored copy is ours")

    local kept, why = ns.Doc.Merge(theirs, mine)
    T.Eq(why, "kept-local", "and ours wins when ours is newer")
    T.Eq(kept, theirs, "without copying anything")
end)

T.Case("Doc: the hash moves with the text and with nothing else", function()
    local a, b = Doc(), Doc()
    T.Eq(ns.Doc.Hash(a), ns.Doc.Hash(b), "two identical documents hash the same")

    b.text = b.text .. "!"
    T.True(ns.Doc.Hash(a) ~= ns.Doc.Hash(b), "one more character is a different message")

    -- rev, author and updatedAt are deliberately outside the hash: two clients can
    -- hold the same message under different revisions, and the hash is how they
    -- notice they have converged.
    local c = Doc()
    c.rev, c.author, c.updatedAt, c.guild = 99, "Zed", 1, "Somewhere Else"
    T.Eq(ns.Doc.Hash(a), ns.Doc.Hash(c), "the revision is not part of the message")

    T.Eq(ns.Doc.Hash({}), ns.Doc.Hash({ text = "" }), "no text and empty text are one message")
    T.Eq(ns.Doc.Hash(nil), ns.Doc.Hash({}), "and no document is not an error")
end)

T.Case("Doc: what arrives from another player is not trusted", function()
    local now = 1750000000
    local raw = Doc()

    T.True(ns.Doc.Sanitize(raw, "Malexis", "Impulse Control", now) ~= nil, "a good one passes")

    -- A message claiming somebody else wrote it is a message lying about it.
    T.Eq(ns.Doc.Sanitize(raw, "Zed", "Impulse Control", now), nil, "author is not the sender")
    T.Eq(ns.Doc.Sanitize(raw, "Malexis", "Some Other Guild", now), nil, "wrong guild")

    local future = Doc()
    future.updatedAt = now + 3600
    T.Eq(ns.Doc.Sanitize(future, "Malexis", "Impulse Control", now), nil, "an hour ahead")

    local nudged = Doc()
    nudged.updatedAt = now + 120
    T.True(ns.Doc.Sanitize(nudged, "Malexis", "Impulse Control", now) ~= nil,
        "two minutes ahead is two guildmates' clocks disagreeing, not an attack")

    local ancient = Doc()
    ancient.updatedAt = 12345
    T.Eq(ns.Doc.Sanitize(ancient, "Malexis", "Impulse Control", now), nil, "impossibly old")

    -- Markup in the line would colour the rest of whatever it lands in, and a chat
    -- channel refuses a pipe outright, so the line would never send.
    local nasty = Doc(5, "|cffff0000BIG|r recruiting, |Hplayer:Zed|h[Zed]|h  knows\nmore")
    local clean = ns.Doc.Sanitize(nasty, "Malexis", "Impulse Control", now)
    T.Eq(clean.text:find("|", 1, true), nil, "not one pipe survives")
    T.Eq(clean.text, "BIG recruiting, [Zed] knows more",
        "the words stay, the markup and the line break do not")
    T.Eq(clean.hash, ns.Doc.Hash(clean), "and the hash is of what was kept")

    -- Sizes are ours to decide, not the sender's.
    local huge = Doc(5, string.rep("x", 1000))
    T.Eq(#ns.Doc.Sanitize(huge, "Malexis", "Impulse Control", now).text, ns.Doc.MAX_TEXT,
        "a thousand characters becomes as many as a chat line takes")

    local empty = Doc(5, nil)
    empty.text = nil
    T.Eq(ns.Doc.Sanitize(empty, "Malexis", "Impulse Control", now).text, "",
        "a document with no text at all is an empty message, not a crash")
end)

T.Case("Doc: an authored edit is stamped, and the guild's copy hashes like ours", function()
    -- What Save and push does, minus the widgets: the same Clean that Sanitize runs
    -- on receipt, so a line with two spaces in it does not hash differently on the
    -- client that typed it.
    local doc = { rev = 3, author = "", updatedAt = 0, guild = "", hash = "", text = "" }
    doc.text = ns.Util.Clean("  LF  healers  /w me ", ns.Doc.MAX_TEXT)
    ns.Doc.Bump(doc, "Malexis-Nightslayer", "Impulse Control", 1750000000, 7)
    T.Eq(doc.rev, 8, "above everything ever seen")
    T.Eq(doc.author, "Malexis", "the short name")
    T.Eq(doc.text, "LF healers /w me", "spaces closed up before it was stamped")

    local wire = ns.Comm.DecodeState(ns.Comm.EncodeState(doc))
    local theirs = ns.Doc.Sanitize(wire, "Malexis", "Impulse Control", 1750000000)
    T.Eq(theirs.hash, doc.hash, "and the receiving client agrees it is the same message")
end)

T.Case("Doc: agreement counts who is where", function()
    local doc = Doc()
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
-- Message: one line, 255 characters
--------------------------------------------------------------------------------

T.Case("Message: there is a line, or there is a reason", function()
    T.Eq(ns.Message.Ready(Doc()), LINE, "the text is the message, exactly")

    local none, why = ns.Message.Ready(Doc(0, ""))
    T.Eq(none, nil, "nothing set")
    T.Eq(why:find("no message set yet", 1, true), 1, "says so")
    T.True(why:find("Message tab", 1, true) ~= nil, "and says where to set one")

    T.Eq(ns.Message.Ready(Doc(1, "   ")), nil, "spaces are not a message")
    T.Eq(ns.Message.Ready({}), nil, "a document with no text field is not an error")
    T.Eq(ns.Message.Ready(nil), nil, "and neither is no document")

    T.Eq(ns.Message.MAX_LEN, ns.Doc.MAX_TEXT, "the chat limit and the document's are one number")
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
    T.Eq(ns.Message.Validate(string.rep("x", 255)), true, "and so does one exactly at the limit")
end)

--------------------------------------------------------------------------------
-- Core: what an update does to what is on disk
--------------------------------------------------------------------------------

T.Case("Core: updating from the team model starts the message empty", function()
    -- A 0.3 document has teams, needs and two templates, none of which is a line
    -- of text. Rather than guess a line out of them, the update forgets them and a
    -- raid leader types the new one once. What it must NOT forget is the highest
    -- revision ever heard, or that first edit would not outrank an old client.
    local db = {
        schema = 1,
        doc = {
            rev = 7, author = "Malexis", updatedAt = 1750000000, guild = "Impulse Control",
            template = "<{guild}> is recruiting: {teams}. Whisper {contacts}!",
            teamTemplate = "{tag} {days}: {needs}", contacts = { "Malexis" },
            teams = { { id = 1, name = "Team One", needs = {} } },
        },
        highestSeenRev = 7,
        peers = { Zed = { rev = 7 } },
    }
    local ran = ns.Migrate(db, ns.Migrations, ns.SCHEMA)
    T.Eq(ran, 1, "one step")
    T.Eq(db.schema, ns.SCHEMA, "and it is current")
    T.Eq(db.doc, nil, "the old document is gone")

    ns.ApplyDefaults(db, ns.Defaults)
    T.Eq(db.doc.rev, 0, "the message starts at rev 0")
    T.Eq(db.doc.text, "", "and empty")
    T.Eq(db.doc.teams, nil, "with no teams in it")
    T.Eq(db.highestSeenRev, 7, "the highest revision seen is kept")
    T.Eq(db.peers.Zed.rev, 7, "and so is what the peers said")
    T.Eq(ns.Doc.NextRev(db.doc.rev, db.highestSeenRev), 8,
        "so the first edit after the update still outranks the old one")

    -- A fresh install has nothing to migrate and lands on the same shape.
    local fresh = {}
    T.Eq(ns.Migrate(fresh, ns.Migrations, ns.SCHEMA), 0, "nothing ran on an empty file")
    ns.ApplyDefaults(fresh, ns.Defaults)
    T.Eq(fresh.doc.text, "", "and it is the same empty message")

    T.Eq(ns.CharDefaults.bark.cursor, nil, "the per-character cursor is gone with the teams")
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
    T.Eq(ns.Bark.BlockReason(state({ messageReason = "no message set yet" })),
        "no message set yet", "something to say")
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
    T.Eq(ns.Comm.Escape(LINE), LINE, "and so is the guild's actual line, slash and all")
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

    local P = ns.Comm.PROTO
    T.Eq(ns.Comm.ParseEnvelope(P .. "^S^3^1"), nil, "too short")
    T.Eq(select(2, ns.Comm.ParseEnvelope((P + 1) .. "^S^3^1^1^x")), "proto", "from the future")
    -- A 0.3 client's document has a template where ours has the text. Reading it
    -- as ours would put "<{guild}> is recruiting: {teams}" in a channel, so an
    -- older protocol is refused whole, not read as far as it goes.
    T.Eq(select(2, ns.Comm.ParseEnvelope("1^S^3^1^1^x")), "proto", "and from the past")
    T.Eq(select(2, ns.Comm.ParseEnvelope("1^V^0^1^1^7^Zed^1750000000^h")), "proto",
        "an old client's offer too, so it never counts as a peer who is ahead")
    T.Eq(select(2, ns.Comm.ParseEnvelope(P .. "^Z^3^1^1^x")), "op", "an operation we do not know")
    T.Eq(select(2, ns.Comm.ParseEnvelope(P .. "^S^3^0^1^x")), "seq", "chunk zero")
    T.Eq(select(2, ns.Comm.ParseEnvelope(P .. "^S^3^1^99^x")), "total", "more chunks than we allow")
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
    local doc = Doc()
    local payload = ns.Comm.EncodeState(doc)
    T.True(#payload <= ns.Comm.MAX_PAYLOAD, "it fits in what we will send")
    T.Eq(#ns.Comm.Chunk(payload), 1, "and the guild's actual line is one addon message")

    local back = ns.Comm.DecodeState(payload)
    T.True(back ~= nil, "and comes back")
    T.Eq(back.rev, doc.rev, "revision")
    T.Eq(back.author, doc.author, "author")
    T.Eq(back.updatedAt, doc.updatedAt, "when")
    T.Eq(back.guild, doc.guild, "guild")
    T.Eq(back.text, doc.text, "and the line, byte for byte")

    -- The hash is what two clients compare, so it has to survive the trip.
    local sanitized = ns.Doc.Sanitize(back, "Malexis", "Impulse Control", 1750000000)
    T.Eq(sanitized.hash, ns.Doc.Hash(doc), "and the message hashes the same at both ends")

    -- A separator in the text is the one thing a hand-rolled format gets wrong.
    local tricky = Doc(5, "a^b~c|d%e")
    T.Eq(ns.Comm.DecodeState(ns.Comm.EncodeState(tricky)).text, "a^b~c|d%e",
        "every separator and escape character in the line comes back")

    T.Eq(ns.Comm.DecodeState("garbage"), nil, "nonsense decodes to nothing")
    T.Eq(select(2, ns.Comm.DecodeState("1^2^3")), "short", "and says why")
    T.Eq(ns.Comm.DecodeState("4^Malexis^1750000000^Impulse Control^").text, "",
        "an empty line is an empty field, not a short message")
end)

T.Case("Comm: the longest line the document allows still fits on the wire", function()
    -- A transport that cannot carry the largest legal document is a transport that
    -- silently stops syncing for whoever wrote it. The caps in Doc and the chunk
    -- budget in Comm have to be sized against each other, and this is where that is
    -- checked rather than discovered: every byte of the line, the author and the
    -- guild name escaping to three.
    local worst = string.rep("\255", ns.Doc.MAX_TEXT)
    local doc = {
        rev = 1000000000, author = string.rep("\255", 24), updatedAt = 1750000000,
        guild = string.rep("\255", 64), text = worst,
    }
    local payload = ns.Comm.EncodeState(doc)
    T.True(#payload <= ns.Comm.MAX_PAYLOAD, string.format(
        "%d bytes to send, and the wire carries %d", #payload, ns.Comm.MAX_PAYLOAD))
    T.True(#ns.Comm.Chunk(payload) <= ns.Comm.MAX_CHUNKS, "in the chunks the envelope allows")
    T.Eq(ns.Comm.DecodeState(payload).text, worst, "and every byte comes back")

    -- And the one that matters in practice: a full line of ordinary text.
    local plain = Doc(1, string.rep("LF heals /w me ", 17))
    T.Eq(#plain.text, 255, "exactly at the limit")
    T.Eq(#ns.Comm.Chunk(ns.Comm.EncodeState(plain)), 2, "goes out in two")
end)

T.Case("Comm: a version offer and a bark round trip", function()
    local doc = Doc()
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
-- Util and UI
--------------------------------------------------------------------------------

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
    -- A page draws with real widgets or not at all; the headless stub has none.
    if IC_HEADLESS then return end
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
    T.Eq(#ns.UI.Pages, 5, "and it has the five pages: Bark, Message, Officers, Log, Settings")

    for _, page in ipairs(ns.UI.Pages) do
        T.Eq(type(page.refresh), "function", page.name .. " built a refresher")
        local ok, err = pcall(page.refresh)
        T.Eq(ok, true, page.name .. " draws => " .. tostring(err))
    end
end)
