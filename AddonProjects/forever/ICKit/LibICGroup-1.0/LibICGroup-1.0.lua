--[[
LibICGroup-1.0
Layer 1 of ICKit: who is in the group, read once and kept as plain values.

On Forever some unit values can come back secret, so a roster is taken out of combat, every
field checked, and kept: a pull then reads the snapshot, not the client.

    local Group = LibStub("LibICGroup-1.0")

    Group.Snapshot(reading)         -> { kind, kindKnown, size, members, byGuid, me, leader, canMark, unknown }
    Group.Read()                    -> the reading Snapshot takes, from the client now
    Group.Now()                     -> Snapshot(Read())

Snapshot is the pure half. Read asks only what the in-game probe saw answer plainly for a
party member out of combat (Docs/client-reference.md); each call is guarded and a secret or
missing answer leaves that field nil. Raid units are read the same way, but how a raid
answers is not yet confirmed, so treat a raid snapshot's gaps as unknown, not as no.
]]

local MAJOR, MINOR = "LibICGroup-1.0", 2
local Group = LibStub:NewLibrary(MAJOR, MINOR)
if not Group then return end

local Restrict = LibStub("LibICRestrict-1.0")

local MAX_PARTY = 5    -- members a party holds, the player included
local MAX_RAID = 40    -- members a raid holds

-- The roles the client assigns; "NONE" and anything else read as no role.
local ROLES = { TANK = true, HEALER = true, DAMAGER = true }

-- The fields of one unit's reading, as Snapshot copies them after checking each.
local FIELDS = { "guid", "name", "name2", "class", "classLocal", "role", "mainTank", "leader", "assist",
    "online", "dead" }

--------------------------------------------------------------------------------
-- Snapshot, pure
--------------------------------------------------------------------------------

local function Text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function Flag(v)
    if v == true then return true end
    if v == false then return false end
    return nil
end

-- One member from one unit's reading. Every field is read through Restrict.Readable; one
-- that is secret, missing or the wrong type is nil, and named in `unknown` when the client
-- did send something. strict: no assist answer at all is not taken as "not assist", which
-- is safe only where there is no assist to be (a party, alone).
local function Member(row, me, strict)
    local plain, unknown = {}, {}
    for _, field in ipairs(FIELDS) do
        local raw = row[field]
        local value = Restrict.Readable(raw)
        if raw ~= nil and value == nil then unknown[field] = true end
        plain[field] = value
    end
    local m = {
        unit = row.unit,
        guid = Text(plain.guid),
        name = Text(plain.name),
        name2 = Text(plain.name2),
        class = Text(plain.class),
        classLocal = Text(plain.classLocal),
        role = ROLES[plain.role] and plain.role or nil,
        mainTank = Flag(plain.mainTank),
        online = Flag(plain.online),
        dead = Flag(plain.dead),
        unknown = unknown,
    }
    local leader, assist = Flag(plain.leader), Flag(plain.assist)
    if leader then
        m.rank = "leader"
    elseif assist then
        m.rank = "assist"
    elseif leader == false and (assist == false or assist == nil and not unknown.assist and not strict) then
        m.rank = "member"
    end
    if m.name then
        m.display = m.name2 and (m.name .. " " .. m.name2) or m.name
    end
    m.isMe = m.guid ~= nil and m.guid == me
    return m
end

-- reading: what the client said, every field optional.
--   inRaid, inGroup   IsInRaid(), IsInGroup()
--   me                UnitGUID("player")
--   everyoneAssist    IsEveryoneAssistant()
--   units             one row per unit in the group, in unit order:
--                     { unit, guid, name, name2 (UnitName's two returns), classLocal, class
--                       (UnitClass's first two), role (UnitGroupRolesAssigned), mainTank
--                       (GetPartyAssignment("MAINTANK")), leader, assist
--                       (UnitIsGroupLeader / Assistant), online (UnitIsConnected),
--                       dead (UnitIsDeadOrGhost) }
-- Returns:
--   kind       "solo", "party" or "raid"
--   kindKnown  false when IsInRaid could not be read and nothing else proved a raid: kind
--              then says "party" for a group that may be a raid
--   size       how many members
--   members    one per unit row: { unit, guid, name, name2, display, class, classLocal,
--              role ("TANK", "HEALER", "DAMAGER" or nil), mainTank, rank ("leader",
--              "assist", "member" or nil when unreadable), online, dead, isMe, unknown }
--   byGuid     members by guid, for those with one
--   me         the member who is the player, or nil when no guid matched
--   leader     the member who leads, or nil
--   canMark    whether the player may set raid target icons: always in a party or alone,
--              in a raid only as leader or assist or when everyone is assist; nil when the
--              player's rank, or whether this is a raid, could not be read
--   unknown    how many fields across all members came back unreadable
function Group.Snapshot(reading)
    reading = reading or {}
    local units = reading.units or {}
    local raidAnswer = Restrict.Readable(reading.inRaid)
    local groupAnswer = Restrict.Readable(reading.inGroup)
    -- A raid is known from IsInRaid, or proved by raid unit tokens; alone is known from
    -- IsInGroup. Anything else is a group that may be a raid.
    local isRaid, kindKnown = false, false
    if type(raidAnswer) == "boolean" then
        isRaid, kindKnown = raidAnswer, true
    elseif units[1] and tostring(units[1].unit):match("^raid%d") then
        isRaid, kindKnown = true, true
    end
    if groupAnswer == false and not isRaid then kindKnown = true end
    local me = Text(Restrict.Readable(reading.me))
    local s = { kind = isRaid and "raid" or (groupAnswer == true and "party" or "solo"), kindKnown = kindKnown,
        members = {}, byGuid = {}, unknown = 0 }
    local strict = isRaid or not kindKnown
    for i, row in ipairs(units) do
        local m = Member(row, me, strict)
        s.members[i] = m
        if m.guid then s.byGuid[m.guid] = m end
        if m.isMe then s.me = m end
        if m.rank == "leader" and not s.leader then s.leader = m end
        for _ in pairs(m.unknown) do s.unknown = s.unknown + 1 end
    end
    s.size = #s.members
    s.everyoneAssist = Flag(Restrict.Readable(reading.everyoneAssist))

    local rank = s.me and s.me.rank
    if s.kind ~= "raid" and s.kindKnown then
        s.canMark = true
    elseif s.everyoneAssist or rank == "leader" or rank == "assist" then
        s.canMark = true
    elseif rank == "member" and s.kind == "raid" then
        s.canMark = false
    end
    return s
end

--------------------------------------------------------------------------------
-- The client
--------------------------------------------------------------------------------

local function Answer(ok, ...)
    if not ok then return nil end
    return ...
end

-- fn(...) under pcall: its returns, or nil when it is missing or raises.
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    return Answer(pcall(fn, ...))
end

-- The unit tokens of the group now: the raid's, or the player and the party's.
local function Units(inRaid, inGroup, count)
    local units = {}
    if inRaid then
        for i = 1, math.min(count, MAX_RAID) do units[i] = "raid" .. i end
        return units
    end
    units[1] = "player"
    if inGroup then
        for i = 1, math.min(count, MAX_PARTY) - 1 do units[#units + 1] = "party" .. i end
    end
    return units
end

local function ReadUnit(unit)
    local row = { unit = unit }
    row.guid = Ask(UnitGUID, unit)
    row.name, row.name2 = Ask(UnitName, unit)
    row.classLocal, row.class = Ask(UnitClass, unit)
    row.role = Ask(UnitGroupRolesAssigned, unit)
    row.mainTank = Ask(GetPartyAssignment, "MAINTANK", unit)
    row.leader = Ask(UnitIsGroupLeader, unit)
    row.assist = Ask(UnitIsGroupAssistant, unit)
    row.online = Ask(UnitIsConnected, unit)
    row.dead = Ask(UnitIsDeadOrGhost, unit)
    return row
end

-- What the client says about the group now, in the shape Snapshot takes. Values pass
-- through as the client gave them; Snapshot decides what a secret means. Take it out of
-- combat: the snapshot is what a pull should read.
function Group.Read()
    local inRaid, inGroup = Ask(IsInRaid), Ask(IsInGroup)
    local count = Restrict.Readable(Ask(GetNumGroupMembers))
    if type(count) ~= "number" then count = 0 end
    local units = {}
    -- IsInRaid is not yet proven plain: when it cannot be read, more members than a party
    -- holds is a raid.
    local raidAnswer = Restrict.Readable(inRaid)
    local plainRaid = raidAnswer == true or (raidAnswer == nil and count > MAX_PARTY)
    local plainGroup = Restrict.Readable(inGroup) == true
    for i, unit in ipairs(Units(plainRaid, plainGroup, count)) do units[i] = ReadUnit(unit) end
    return {
        inRaid = inRaid,
        inGroup = inGroup,
        me = Ask(UnitGUID, "player"),
        everyoneAssist = Ask(IsEveryoneAssistant),
        units = units,
    }
end

function Group.Now()
    return Group.Snapshot(Group.Read())
end
