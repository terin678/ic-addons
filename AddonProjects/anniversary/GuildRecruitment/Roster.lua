local addonName, ns = ...

ns.Roster = ns.Roster or {}
local Roster = ns.Roster

--[[
Who is in the guild, and what they are allowed to do.

Authority is a rank threshold. rankIndex 0 is the guild master and a LARGER
number is a LOWER rank, so every test here is `<=`, not `>=`. That is the
off-by-one that would otherwise ship, and it has its own case.

The rank that matters is always the one THIS client reads off the roster for the
sender. A rank claimed inside a message is a claim, not a permission.
]]

local REFRESH_GAP = 15      -- seconds; GuildRoster() is server-throttled around 10
local UNKNOWN_RANK = 99     -- lower than every real rank, so a stranger can do nothing

Roster.UNKNOWN_RANK = UNKNOWN_RANK

-- Pure. "Aeryn-Nightslayer" -> "Aeryn". CHAT_MSG_ADDON may or may not carry a
-- realm on this client, and a realm suffix must not make one person into two.
function Roster.Short(name)
    name = tostring(name or "")
    return (name:match("^([^%-]+)") or name)
end

-- Pure. rankIndex 0 is the guild master. nil is not permission: a roster that has
-- not loaded yet must not let anybody do anything.
function Roster.MayAuthor(rankIndex, threshold)
    if type(rankIndex) ~= "number" then return false end
    return rankIndex <= (threshold or 0)
end

function Roster.MayBark(rankIndex, threshold)
    if type(rankIndex) ~= "number" then return false end
    return rankIndex <= (threshold or 0)
end

--[[
Pure. Builds the lookup from rows shaped
    { name, rank, rankIndex, online, class }
which is exactly what Roster.Read makes from GetGuildRosterInfo. Tests hand it
made-up rows.

Returns byName, count, onlineCount.
]]
function Roster.Index(rows)
    local byName, count, online = {}, 0, 0
    for _, row in ipairs(rows or {}) do
        local short = Roster.Short(row.name)
        if short ~= "" and not byName[short] then
            byName[short] = row
            count = count + 1
            if row.online then online = online + 1 end
        end
    end
    return byName, count, online
end

-- Pure. A name we have never seen gets the fallback, which is a rank that can do
-- nothing at all.
function Roster.RankOf(byName, name, fallback)
    local row = byName and byName[Roster.Short(name)]
    if not row or type(row.rankIndex) ~= "number" then return fallback or UNKNOWN_RANK end
    return row.rankIndex
end

-- Pure. Sorted for display: rank first, then name, so the list does not shuffle
-- between refreshes.
function Roster.Sorted(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do out[#out + 1] = row end
    table.sort(out, function(a, b)
        if (a.rankIndex or UNKNOWN_RANK) ~= (b.rankIndex or UNKNOWN_RANK) then
            return (a.rankIndex or UNKNOWN_RANK) < (b.rankIndex or UNKNOWN_RANK)
        end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

--------------------------------------------------------------------------------
-- Reading the client
--------------------------------------------------------------------------------

Roster.rows, Roster.byName, Roster.readAt = {}, {}, 0

-- The only function here that touches the game. Everything above it can be given
-- a table of rows instead.
function Roster.Read()
    if not IsInGuild or not IsInGuild() then
        Roster.rows, Roster.byName, Roster.readAt = {}, {}, 0
        return Roster.rows, Roster.byName
    end
    if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
        return Roster.rows, Roster.byName
    end

    local rows = {}
    for i = 1, (GetNumGuildMembers() or 0) do
        -- On 20506 the returns are name, rank, rankIndex, level, class, zone,
        -- note, officernote, online. Read defensively: /gr probe reports what this
        -- build actually has, and a nil rankIndex must not become rank 0.
        local name, rank, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name then
            rows[#rows + 1] = {
                name = Roster.Short(name),
                rank = rank or "?",
                rankIndex = type(rankIndex) == "number" and rankIndex or nil,
                online = online and true or false,
            }
        end
    end

    Roster.rows = rows
    Roster.byName = Roster.Index(rows)
    Roster.readAt = ns.Now()
    return Roster.rows, Roster.byName
end

--[[
Asks the server for the roster, at most once every REFRESH_GAP seconds because it
is throttled at about that anyway. The answer arrives on GUILD_ROSTER_UPDATE; this
does not wait for it, and every caller has to cope with an empty roster in the
meantime -- which they do, because an unknown rank can do nothing.
]]
function Roster.Refresh(force)
    local now = ns.Now()
    if not force and (now - (Roster.requestedAt or 0)) < REFRESH_GAP then return false end
    Roster.requestedAt = now
    if type(GuildRoster) == "function" then
        GuildRoster()
        return true
    end
    -- No way to ask: read whatever the client already has rather than nothing.
    Roster.Read()
    return false
end

-- This character's own rank, and what it lets them do.
function Roster.Me()
    local me = Roster.Short(UnitName and UnitName("player") or "")
    return me, Roster.RankOf(Roster.byName, me, UNKNOWN_RANK)
end

function Roster.ICanAuthor()
    local _, rank = Roster.Me()
    return Roster.MayAuthor(rank, ns.db.settings.authorRankIndex)
end

function Roster.ICanBark()
    local _, rank = Roster.Me()
    return Roster.MayBark(rank, ns.db.settings.barkRankIndex)
end

-- The guild's own name, used to drop a document that came from somewhere else.
function Roster.GuildName()
    if type(GetGuildInfo) ~= "function" then return "" end
    local name = GetGuildInfo("player")
    return name or ""
end
