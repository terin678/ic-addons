local addonName, ns = ...

ns.Teams = ns.Teams or {}
local Teams = ns.Teams

--[[
A team and the roles it is short of. All pure: these take plain tables and return
plain values, and none of them read the saved document.

A need is { role, class, count, priority }. role and class are free text, because
"Feral Druid" is a thing a raid leader wants to ask for and no dropdown was ever
going to have it.
]]

local MAX_NAME = 24
local MAX_TAG = 8
local MAX_DAYS = 24
local MAX_ROLE = 24
local MAX_CLASS = 24
local MAX_COUNT = 40

Teams.MAX_NAME, Teams.MAX_TAG, Teams.MAX_DAYS = MAX_NAME, MAX_TAG, MAX_DAYS
Teams.MAX_ROLE, Teams.MAX_CLASS = MAX_ROLE, MAX_CLASS

-- Pure. Trims, caps, and fills in a tag from the name when nobody set one, so a
-- team always has something short to put in a 255-character message.
function Teams.Normalize(team)
    team = team or {}
    team.name = ns.Util.Clean(team.name, MAX_NAME)
    if team.name == "" then team.name = "Team " .. tostring(team.id or "?") end

    team.tag = ns.Util.Clean(team.tag, MAX_TAG)
    if team.tag == "" then
        -- Initials, then the first word, then the name. Whichever comes first.
        local initials = ""
        for word in team.name:gmatch("%a+") do initials = initials .. word:sub(1, 1) end
        team.tag = ns.Util.Truncate(initials ~= "" and initials:upper() or team.name, MAX_TAG)
    end

    team.days = ns.Util.Clean(team.days, MAX_DAYS)
    team.active = team.active ~= false
    team.priority = tonumber(team.priority) or 1

    team.needs = team.needs or {}
    for _, need in ipairs(team.needs) do Teams.NormalizeNeed(need) end
    return team
end

-- Pure.
function Teams.NormalizeNeed(need)
    need = need or {}
    need.role = ns.Util.Clean(need.role, MAX_ROLE)
    if need.role == "" then need.role = "DPS" end
    need.class = ns.Util.Clean(need.class, MAX_CLASS)
    need.count = math.max(1, math.min(MAX_COUNT, math.floor(tonumber(need.count) or 1)))
    need.priority = tonumber(need.priority) or 1
    return need
end

--[[
Pure. Priority first, then role, then class. A pairs() walk or an unsorted list
shuffles between refreshes and makes the message change wording without anybody
editing it, which reads as the addon being broken.

Returns a new list; the caller's own is not reordered.
]]
function Teams.Sorted(needs)
    local out = {}
    for _, need in ipairs(needs or {}) do out[#out + 1] = need end
    table.sort(out, function(a, b)
        if (a.priority or 1) ~= (b.priority or 1) then
            return (a.priority or 1) < (b.priority or 1)
        end
        if (a.role or "") ~= (b.role or "") then return (a.role or "") < (b.role or "") end
        return (a.class or "") < (b.class or "")
    end)
    return out
end

-- Pure. "5 needed: 2 Healer, 3 DPS"
function Teams.NeedsSummary(team)
    local needs = Teams.Sorted(team and team.needs)
    if #needs == 0 then return "nothing needed" end
    local total, parts = 0, {}
    for _, need in ipairs(needs) do
        total = total + (need.count or 1)
        local what = need.role or "?"
        if need.class and need.class ~= "" then what = need.class .. " " .. what end
        parts[#parts + 1] = string.format("%d %s", need.count or 1, what)
    end
    return string.format("%d needed: %s", total, table.concat(parts, ", "))
end

-- Pure. How many bodies the whole document is asking for, across active teams.
function Teams.TotalNeeded(doc)
    local total = 0
    for _, team in ipairs((doc or {}).teams or {}) do
        if team.active ~= false then
            for _, need in ipairs(team.needs or {}) do total = total + (need.count or 1) end
        end
    end
    return total
end

--[[
Pure. One past the highest id in use.

Deleting the highest team does hand its id back to the next new one -- this is not a
monotonic counter. That is harmless because a document is never merged team by team:
Doc.Merge takes the whole document from whichever side wins, so two clients can never be
holding different teams that share an id.
]]
function Teams.NextId(doc)
    local highest = 0
    for _, team in ipairs((doc or {}).teams or {}) do
        highest = math.max(highest, tonumber(team.id) or 0)
    end
    return highest + 1
end

-- Pure.
function Teams.ById(doc, id)
    for _, team in ipairs((doc or {}).teams or {}) do
        if team.id == id then return team end
    end
    return nil
end

-- Pure. A new team, normalized, ready to append.
function Teams.New(id, name)
    return Teams.Normalize({
        id = id, name = name, tag = "", days = "",
        active = true, priority = id, needs = {},
    })
end

--[[
Pure. Writes the fields a raid leader can edit and re-normalizes.

A blank tag is not an error: Normalize fills it from the name's initials. That is what makes
renaming work -- the tag generated from the old name would otherwise stick to the new one
forever, so clearing the tag is how you say "follow the name again".

Returns the team.
]]
function Teams.Edit(team, fields)
    if not team then return nil end
    fields = fields or {}
    if fields.name ~= nil then team.name = fields.name end
    if fields.tag ~= nil then team.tag = fields.tag end
    if fields.days ~= nil then team.days = fields.days end
    if fields.active ~= nil then team.active = fields.active and true or false end
    return Teams.Normalize(team)
end

--[[
Pure. Takes a team out of the document by id.

Refuses to remove the last one: a document with no teams has nothing to recruit for, and
every screen that reads doc.teams[1] would then be reading nil. Returns removed, reason.
]]
function Teams.Remove(doc, id)
    local teams = (doc or {}).teams or {}
    if #teams <= 1 then return false, "the guild needs at least one team" end
    for i, team in ipairs(teams) do
        if team.id == id then
            table.remove(teams, i)
            return true
        end
    end
    return false, "no team with that id"
end

--[[
Pure. Moves a need from whichever team holds it to the team with `toId`.

By the need OBJECT, not by an index: the rows are drawn sorted and the stored array is not,
so an index taken off the screen stops meaning anything as soon as a priority changes.

Returns moved, reason. Moving a need to the team it is already on is not a failure, it just
did nothing, so it comes back true.
]]
function Teams.MoveNeed(doc, need, toId)
    local target = Teams.ById(doc, toId)
    if not need then return false, "no need to move" end
    if not target then return false, "no team with that id" end

    for _, team in ipairs((doc or {}).teams or {}) do
        for i, other in ipairs(team.needs or {}) do
            if other == need then
                if team.id == toId then return true end
                if #(target.needs or {}) >= (ns.Doc.MAX_NEEDS or math.huge) then
                    return false, "that team already has as many needs as fit in a message"
                end
                table.remove(team.needs, i)
                target.needs = target.needs or {}
                target.needs[#target.needs + 1] = need
                return true
            end
        end
    end
    return false, "that need is not on any team"
end

--[[
Pure. Moves a team one place earlier in the document.

Array order is what the message uses -- Message.Rotate decides which team leads from it --
so this is not cosmetic. team.priority is not touched: nothing reads it except the wire
format, and having two orderings that can disagree is how a list starts lying.

Returns moved, reason.
]]
function Teams.MoveUp(doc, id)
    local teams = (doc or {}).teams or {}
    for i, team in ipairs(teams) do
        if team.id == id then
            if i == 1 then return false, "already first" end
            teams[i - 1], teams[i] = teams[i], teams[i - 1]
            return true
        end
    end
    return false, "no team with that id"
end
