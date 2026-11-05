local addonName, ns = ...

--[[
Lead: who the Raid Lead is. Pure: no client call, ever; every function takes its tables
as arguments.

Owned by lane F (comms and lead).

The Raid Lead is the one client that sends the raid's lines: the pre-pull announce and the
death calls (lane D asks Lead through ns.Comms.IsLead()). Marking is a press anyone with
lead or assist can make, so the Raid Lead no longer has to be able to place icons.

Every client works the answer out on its own from the same inputs, so no client has to
win an argument with another:

    1. A designated Raid Lead (/mfd lead <name>) who is in the group and not offline wins.
       Whether they run the addon is not required: with addon messages off in a raid
       (spec P9) a designation is the only thing that still works.
    2. Otherwise the addon users heard this session (LibICComm hello) elect: the group
       leader, then an assistant, then the name that sorts first.
    3. Heard from nobody (addon messages unavailable): the group leader.
    4. Alone: you.

    Lead.Resolve(input)             { name, mode, reason, warning }
    Lead.CanSet(snapshot)           true, or false and why: who may designate
    Lead.Accept(current, incoming)  whether an incoming designation replaces mine
    Lead.Parse(rest, members)       what /mfd lead was asked: show, clear or set a name
    Lead.Describe(result)           one line for chat
]]

ns.Lead = ns.Lead or {}
local Lead = ns.Lead
local Util = LibStub("LibICUtil-1.0")

Lead.MAX_NAME = 48     -- bytes; a character name, with room for a realm

local lower = string.lower

-- A member is present unless the client said plainly that they are offline.
local function Present(member)
    return type(member) == "table" and type(member.name) == "string" and member.name ~= ""
        and member.online ~= false
end

-- On this client a character has two names ("First Second"); UnitName gives both and
-- LibICGroup joins them as `display`. The full name is what tells two players apart, so it
-- is the name a Raid Lead is stored and compared under.
local function Id(member)
    return member.display or member.name
end
Lead.Id = Id

-- The member called `name`: the full name first, then the first name alone when only one
-- member has it. Returns member, or nil and whether the name was ambiguous.
local function Find(members, name)
    if type(name) ~= "string" or name == "" then return nil end
    local want, byFirst, count = lower(name), nil, 0
    for _, member in ipairs(members or {}) do
        if type(member) == "table" then
            if type(member.display) == "string" and lower(member.display) == want then return member end
            if type(member.name) == "string" and lower(member.name) == want then
                count = count + 1
                byFirst = byFirst or member
            end
        end
    end
    if count > 1 then return nil, true end
    return byFirst
end

local RANK_ORDER = { leader = 1, assist = 2, member = 3 }

-- Election order: group leader, assistant, then name ascending. A rank that could not be
-- read sorts with plain members, never above them.
local function Before(a, b)
    local ra, rb = RANK_ORDER[a.rank] or 3, RANK_ORDER[b.rank] or 3
    if ra ~= rb then return ra < rb end
    return Id(a) < Id(b)
end

--[[
input:
    members     a LibICGroup snapshot's members: { name, display, guid, rank, online, isMe }
    kind        "solo", "party" or "raid" (the snapshot's kind)
    designated  the saved designation's name, or nil
    users       { [guid] = true } for every member heard running the addon this session,
                or nil when addon messages are not available (nothing can be heard)
    me          the player's own full name, as Lead.Id gives it (always an addon user)
Returns {
    name     the Raid Lead's name, or nil when nobody can be named
    mode     "designated", "elected", "leader", "solo" or "none"
    isMe     whether that is the player
    reason   why a designation was passed over, or why nobody was found ("" when neither)
    warning  something to know about a designated lead who still won ("" when nothing)
}
]]
function Lead.Resolve(input)
    input = input or {}
    local members = {}
    for _, member in ipairs(input.members or {}) do
        if Present(member) then members[#members + 1] = member end
    end
    local me = input.me
    local function Result(name, mode, reason, warning)
        return {
            name = name, mode = mode, isMe = name ~= nil and me ~= nil and lower(name) == lower(me),
            reason = reason or "", warning = warning or "",
        }
    end

    if input.kind == "solo" or #members == 0 then
        return Result(me, me and "solo" or "none", me and "" or "nobody is here")
    end

    local reason = ""
    local designated = input.designated
    if type(designated) == "string" and designated ~= "" then
        local found = Find(members, designated)
        if found then
            local warning = ""
            if input.users and not found.isMe and not (found.guid and input.users[found.guid]) then
                warning = Id(found) .. " has not been heard running Marked For Death"
            end
            return Result(Id(found), "designated", "", warning)
        end
        local listed = Find(input.members, designated)
        if listed then
            reason = "Raid Lead " .. Id(listed) .. " is offline"
        else
            reason = "Raid Lead " .. designated .. " is not in the group"
        end
    end

    if input.users then
        local voters = {}
        for _, member in ipairs(members) do
            if member.isMe or (member.guid and input.users[member.guid]) then voters[#voters + 1] = member end
        end
        if #voters > 0 then
            table.sort(voters, Before)
            return Result(Id(voters[1]), "elected", reason)
        end
    end

    for _, member in ipairs(members) do
        if member.rank == "leader" then return Result(Id(member), "leader", reason) end
    end
    if reason == "" then reason = "the group leader could not be read" end
    return Result(nil, "none", reason)
end

-- Whether the player may designate a Raid Lead: alone, as group leader, as an assistant,
-- or when everyone is an assistant. A rank the client did not answer is refused, since
-- the designation travels to the whole group. Returns true, or false and why.
function Lead.CanSet(snapshot)
    snapshot = snapshot or {}
    if snapshot.kind == "solo" then return true end
    if snapshot.everyoneAssist then return true end
    local rank = snapshot.me and snapshot.me.rank
    if rank == "leader" or rank == "assist" then return true end
    if rank == nil then return false, "your group rank could not be read" end
    if snapshot.kind == "raid" then return false, "only the raid leader or an assistant can set the Raid Lead" end
    return false, "only the party leader can set the Raid Lead"
end

local function Named(d)
    return type(d) == "table" and type(d.name) == "string" and d.name ~= ""
end

--[[
current, incoming: { name (nil to clear), at (time() it was set, 0 when unknown), by }.
Returns whether incoming replaces current. The later setting wins. Two with the same time
(two remembered from earlier nights, both 0) settle the same way on every client: a name
beats no name, then the name that sorts first. So any two clients that have seen the same
designations agree, whatever order they arrived in.
]]
function Lead.Accept(current, incoming)
    if type(incoming) ~= "table" then return false end
    current = type(current) == "table" and current or { at = 0 }
    local ca, ia = tonumber(current.at) or 0, tonumber(incoming.at) or 0
    if ia ~= ca then return ia > ca end
    local cn, inn = Named(current), Named(incoming)
    if cn ~= inn then return inn end
    if not inn then return false end
    return lower(incoming.name) < lower(current.name)
end

--[[
rest: what followed /mfd lead. members: the group's members, to spell a name the way the
game does: "Ann" finds "Ann Smith" when only one member's first name is Ann. Returns one of
    { action = "show" }
    { action = "clear" }
    { action = "set", name, inGroup }
    { action = "refuse", why }
A name nobody in the group has is still allowed (the designation is remembered across
nights), capitalised the way the game shows names.
]]
function Lead.Parse(rest, members)
    local text = Util.Trim(type(rest) == "string" and rest or "")
    if text == "" then return { action = "show" } end
    local word = lower(text)
    if word == "clear" or word == "none" or word == "off" or word == "-" then return { action = "clear" } end
    if #text > Lead.MAX_NAME then return { action = "refuse", why = "that name is too long" } end
    local found, ambiguous = Find(members, text)
    if found then return { action = "set", name = Id(found), inGroup = true } end
    if ambiguous then
        return { action = "refuse", why = "two players are called " .. text .. "; give both names" }
    end
    -- One or two words of letters (UTF-8 letters are bytes above 127, which %p and %d
    -- never match), each capitalised the way the game shows them.
    if not text:find("^[^%s%d%p]+$") and not text:find("^[^%s%d%p]+ [^%s%d%p]+$") then
        return { action = "refuse", why = "a character name is one or two words of letters" }
    end
    local name = text:gsub("(%S)(%S*)", function(first, restOf) return string.upper(first) .. lower(restOf) end)
    return { action = "set", name = name, inGroup = false }
end

local MODE_TEXT = {
    designated = "designated",
    elected = "elected among addon users",
    leader = "the group leader",
    solo = "alone",
    none = "nobody",
}

-- result: what Resolve returned. One line for chat, without colour.
function Lead.Describe(result)
    if type(result) ~= "table" or not result.name then
        return "Raid Lead: nobody" .. ((result and result.reason ~= "") and (" (" .. result.reason .. ")") or "")
    end
    local line = "Raid Lead: " .. result.name .. (result.isMe and " (you)" or "")
        .. ", " .. (MODE_TEXT[result.mode] or tostring(result.mode))
    if result.reason ~= "" then line = line .. "; " .. result.reason end
    if result.warning ~= "" then line = line .. "; " .. result.warning end
    return line
end
