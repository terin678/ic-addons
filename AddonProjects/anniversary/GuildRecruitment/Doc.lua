local addonName, ns = ...

ns.Doc = ns.Doc or {}
local Doc = ns.Doc

--[[
The shared document, and the rule that decides whose copy the guild converges on.

This is the part that will bite if it is wrong, so all of it is pure and all of it
has cases. Two officers editing in the same minute must end up agreeing, and they
must agree on the SAME answer without talking about it again.

`rev` is a Lamport clock, not a counter. An edit stamps rev above anything this
client has ever seen -- including documents it looked at and rejected -- which is
what makes a stale sender with a fast clock lose. Timestamps are never clamped:
clamping to each client's own idea of now would make Compare answer differently
on different machines, and that is the one thing this cannot afford.
]]

local MAX_TEMPLATE = 255
local MAX_CONTACTS = 6
local MAX_TEAMS = 4
local MAX_NEEDS = 8
local FUTURE_GRACE = 300        -- seconds of clock difference between guildmates
local OLDEST_SANE = 1700000000  -- late 2023; anything before this is a broken clock

Doc.MAX_TEAMS, Doc.MAX_NEEDS, Doc.MAX_TEMPLATE = MAX_TEAMS, MAX_NEEDS, MAX_TEMPLATE

-- Pure. A stable string for everything a reader would call "the message". rev,
-- author and updatedAt are deliberately not in it: two clients can hold the same
-- message under different revisions, and the hash is how they notice.
function Doc.Hash(doc)
    doc = doc or {}
    local teams = {}
    for i, team in ipairs(doc.teams or {}) do
        local needs = {}
        for j, need in ipairs(ns.Teams.Sorted(team.needs)) do
            needs[j] = { role = need.role, class = need.class,
                         count = need.count, priority = need.priority }
        end
        teams[i] = {
            id = team.id, name = team.name, tag = team.tag, days = team.days,
            active = team.active ~= false, priority = team.priority, needs = needs,
        }
    end
    return ns.Util.Serialize({
        template = doc.template or "",
        teamTemplate = doc.teamTemplate or "",
        contacts = doc.contacts or {},
        teams = teams,
    })
end

--[[
Pure. Which copy wins, from this client's point of view. Returns "local",
"remote" or "same".

    1. higher rev wins            -- causality, not clocks
    2. same rev, newer updatedAt  -- two people who both went 6 -> 7
    3. still tied, lower author name wins

Step 3 is an arbitrary coin flip, and that is fine: what matters is that it is
the SAME flip on every client, so nobody oscillates. Lower-cased first so two
spellings of the same name cannot make two clients disagree.

Author RANK is not a tiebreak. Rank decides whether a document is accepted at
all, on receipt, from the sender's rank as this client reads it.
]]
function Doc.Compare(a, b)
    if not b then return "local" end
    if not a then return "remote" end

    local ra, rb = tonumber(a.rev) or 0, tonumber(b.rev) or 0
    if ra ~= rb then return ra > rb and "local" or "remote" end

    local ta, tb = tonumber(a.updatedAt) or 0, tonumber(b.updatedAt) or 0
    if ta ~= tb then return ta > tb and "local" or "remote" end

    -- Lower-cased, and no further. Two spellings of one name are one author, and
    -- swapping the document over a capital letter would be a swap for nothing.
    local la = tostring(a.author or ""):lower()
    local lb = tostring(b.author or ""):lower()
    if la ~= lb then return la < lb and "local" or "remote" end
    return "same"
end

-- Pure. The rev an edit stamps: above everything ever seen, not just above ours.
-- Seeing rev 9 and declining to take it still has to make our next edit outrank it.
function Doc.NextRev(localRev, highestSeen)
    return math.max(tonumber(localRev) or 0, tonumber(highestSeen) or 0) + 1
end

--[[
Pure. Returns the document to store, and what happened: "took-remote",
"kept-local" or "same".

The stored copy is always ours to keep. Returning the caller's remote table would
let a later message from the same sender rewrite what we already committed.
]]
function Doc.Merge(localDoc, remoteDoc)
    local which = Doc.Compare(localDoc, remoteDoc)
    if which == "remote" then return ns.DeepCopy(remoteDoc), "took-remote" end
    if which == "local" then return localDoc, "kept-local" end
    return localDoc, "same"
end

-- Pure. Stamps an authored edit. `highestSeen` is the largest rev this client has
-- heard from anyone, kept whether or not the document it came in was accepted.
function Doc.Bump(doc, author, guild, now, highestSeen)
    doc.rev = Doc.NextRev(doc.rev, highestSeen)
    doc.author = ns.Roster.Short(author)
    doc.guild = guild or doc.guild or ""
    doc.updatedAt = now
    doc.hash = Doc.Hash(doc)
    return doc
end

--[[
Pure. Everything that arrived from another player, checked and cut down before it
is stored or drawn. Returns doc, reason -- nil and a reason when it must be
dropped outright, and a trimmed copy otherwise.

`now` is passed in rather than read, so the clock-skew window is testable.
]]
function Doc.Sanitize(incoming, sender, guild, now)
    if type(incoming) ~= "table" then return nil, "not a document" end

    local author = ns.Roster.Short(incoming.author)
    if author == "" then return nil, "no author" end
    if sender and author ~= ns.Roster.Short(sender) then
        -- A message claiming somebody else wrote this is a message lying about it.
        return nil, "author is not the sender"
    end

    if guild and guild ~= "" and ns.Util.Clean(incoming.guild, 64) ~= guild then
        return nil, "wrong guild"
    end

    local rev = tonumber(incoming.rev)
    if not rev or rev < 0 or rev > 1e9 then return nil, "rev out of range" end

    local at = tonumber(incoming.updatedAt)
    if not at or at < OLDEST_SANE then return nil, "timestamp is impossible" end
    if at > now + FUTURE_GRACE then return nil, "timestamp is in the future" end

    local doc = {
        rev = math.floor(rev),
        author = ns.Util.Clean(author, 24),
        updatedAt = math.floor(at),
        guild = ns.Util.Clean(incoming.guild, 64),
        template = ns.Util.Clean(incoming.template, MAX_TEMPLATE),
        teamTemplate = ns.Util.Clean(incoming.teamTemplate, MAX_TEMPLATE),
        contacts = {},
        teams = {},
    }

    for _, name in ipairs(incoming.contacts or {}) do
        if #doc.contacts >= MAX_CONTACTS then break end
        local clean = ns.Util.Clean(name, 24)
        if clean ~= "" then doc.contacts[#doc.contacts + 1] = clean end
    end

    for _, team in ipairs(incoming.teams or {}) do
        if #doc.teams >= MAX_TEAMS then break end
        local copy = ns.Teams.Normalize({
            id = tonumber(team.id) or (#doc.teams + 1),
            name = team.name, tag = team.tag, days = team.days,
            active = team.active, priority = team.priority, needs = {},
        })
        for _, need in ipairs(team.needs or {}) do
            if #copy.needs >= MAX_NEEDS then break end
            copy.needs[#copy.needs + 1] = ns.Teams.NormalizeNeed({
                role = need.role, class = need.class,
                count = need.count, priority = need.priority,
            })
        end
        doc.teams[#doc.teams + 1] = copy
    end

    doc.hash = Doc.Hash(doc)
    return doc
end

-- Pure. "rev 14 - Malexis - 3h ago"
function Doc.Summary(doc, now)
    doc = doc or {}
    if (doc.rev or 0) == 0 then return "no message set yet" end
    local age = ns.Util.Freshness(doc.updatedAt, now, 0)
    return string.format("rev %d  \194\183  %s  \194\183  %s ago",
        doc.rev, doc.author ~= "" and doc.author or "?", age)
end

-- Pure. How many peers hold what we hold. The Officers tab's whole point.
function Doc.Agreement(doc, peers)
    local same, behind, ahead = 0, 0, 0
    for _, peer in pairs(peers or {}) do
        local which = Doc.Compare(doc, peer)
        if which == "same" or (peer.hash and peer.hash == doc.hash) then
            same = same + 1
        elseif which == "local" then
            behind = behind + 1
        else
            ahead = ahead + 1
        end
    end
    return same, behind, ahead
end
