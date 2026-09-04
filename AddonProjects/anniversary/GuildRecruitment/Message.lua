local addonName, ns = ...

ns.Message = ns.Message or {}
local Message = ns.Message

--[[
Turning two teams' worth of needs into ONE line of at most 255 characters.

All pure. The load-bearing property, which has its own case: both team tags
appear in the message whenever the tags plus the template alone fit. One team is
never starved out of a combined message, which is why needs are dropped
round-robin from whichever team currently has the most rather than by truncating
the tail.

The message degrades in named steps rather than being cut off:

    1  T1 Tue/Thu 8-11: 2x Holy Priest, 3x DPS     everything
    2  T1 Tue/Thu 8-11: 2x Healer, 3x DPS          class dropped
    3  T1: 2x Healer, 3x DPS                       days dropped
    4  T1: Healer, DPS                             counts dropped
       T1: Healer                                  lowest priority needs dropped
       T1                                          all of them dropped, tag only

Past level 4 it starts removing needs, lowest priority first. The ladder stops
there on purpose: a level that showed only the first role would make dropping a
need change nothing, and then "3 needs left out" would be a number about text
nobody was going to see anyway.
]]

local MAX_LEN = 255         -- bytes SendChatMessage accepts
local SEP = " | "           -- between teams
local LEVELS = 4

Message.MAX_LEN, Message.LEVELS = MAX_LEN, LEVELS

Message.LEVEL_NAME = {
    [1] = "everything",
    [2] = "without classes",
    [3] = "without days",
    [4] = "without counts",
}

-- gsub treats % in a replacement as an escape, and a raid leader is entitled to
-- write "50% attendance" in their own message.
local function Fill(text, token, value)
    return (text:gsub(token, (tostring(value or ""):gsub("%%", "%%%%"))))
end

-- Pure. Bytes, as SendChatMessage counts them.
function Message.Length(s)
    return #tostring(s or "")
end

Message.DEFAULT_TEAM_TEMPLATE = "{tag} {days}: {needs}"

--[[
Pure. One team at one detail level. `team.needs` is taken as given and in order:
Degrade sorts and trims before calling this.

The team template is the raid leader's, so a token can be empty at any level and
the punctuation around it has to survive that. Tidying afterwards is simpler than
a template language: a missing {days} leaves " :" and a team with no needs left
leaves a trailing colon, and both of those are one gsub each.
]]
function Message.TeamFragment(team, level, teamTemplate)
    team = team or {}
    local template = teamTemplate
    if not template or not template:find("{tag}", 1, true) then
        template = Message.DEFAULT_TEAM_TEMPLATE
    end

    local tag = team.tag
    if not tag or tag == "" then tag = team.name or "?" end

    local days = ""
    if level <= 2 and team.days and team.days ~= "" then days = team.days end

    local parts = {}
    for _, need in ipairs(team.needs or {}) do
        local what = need.role or "?"
        if level <= 1 and need.class and need.class ~= "" then
            what = need.class .. " " .. what
        end
        if level <= 3 and (need.count or 1) > 1 then
            what = string.format("%dx %s", need.count, what)
        end
        parts[#parts + 1] = what
    end

    local out = Fill(template, "{tag}", tag)
    out = Fill(out, "{days}", days)
    out = Fill(out, "{needs}", table.concat(parts, ", "))

    out = out:gsub("%s+", " ")
    out = out:gsub("%s+([:,])", "%1")
    out = out:gsub("[%s:,]+$", "")
    return (out:gsub("^%s+", ""))
end

local function Total(fragments)
    local n = 0
    for i, fragment in ipairs(fragments) do
        n = n + #fragment
        if i > 1 then n = n + #SEP end
    end
    return n
end

local function Fragments(teams, level, teamTemplate)
    local out = {}
    for i, team in ipairs(teams) do
        out[i] = Message.TeamFragment(team, level, teamTemplate)
    end
    return out
end

--[[
Pure. Fits the teams into `budget` characters, giving up detail before giving up
a team.

Returns fragments, level, dropped -- or nil, LEVELS, dropped when not even the
tags on their own fit, which is a message nobody should be sending.

Needs are dropped from whichever team currently has the most, alternating, so two
teams shrink together instead of the second one vanishing.
]]
function Message.Degrade(teams, budget, teamTemplate)
    -- Work on copies. Dropping a need to make a message fit must not edit the
    -- document the officers are all trying to agree on.
    local working = {}
    for i, team in ipairs(teams) do
        working[i] = {
            name = team.name, tag = team.tag, days = team.days,
            needs = ns.Teams.Sorted(team.needs),
        }
    end

    for level = 1, LEVELS do
        local fragments = Fragments(working, level, teamTemplate)
        if Total(fragments) <= budget then return fragments, level, 0 end
    end

    local dropped = 0
    while true do
        local biggest, most = nil, 0
        for _, team in ipairs(working) do
            if #team.needs > most then biggest, most = team, #team.needs end
        end
        if not biggest then break end
        -- Sorted puts the lowest priority last, so the last one is the one to lose.
        table.remove(biggest.needs)
        dropped = dropped + 1
        local fragments = Fragments(working, LEVELS, teamTemplate)
        if Total(fragments) <= budget then return fragments, LEVELS, dropped end
    end

    local fragments = Fragments(working, LEVELS, teamTemplate)
    if Total(fragments) <= budget then return fragments, LEVELS, dropped end
    return nil, LEVELS, dropped
end

--[[
Pure. Rotates the list so `cursor` leads, and returns the cursor for next time.

Whichever team is last is the one that loses detail first, so the lead moves each
time a message goes out and neither team is permanently the one that gets cut.
]]
function Message.Rotate(teams, cursor)
    local n = #teams
    if n == 0 then return {}, 1 end
    cursor = tonumber(cursor) or 1
    if cursor < 1 or cursor > n then cursor = 1 end
    local out = {}
    for i = 1, n do
        out[i] = teams[(cursor + i - 2) % n + 1]
    end
    return out, cursor % n + 1
end

--[[
Pure. The whole line.

Returns msg, level, dropped, nextCursor -- or nil, nil, 0, cursor, reason. The
reason is written to be shown to an officer, because a Bark button that does
nothing has to say what it is waiting for.
]]
function Message.Assemble(doc, cursor, maxLen)
    doc = doc or {}
    maxLen = maxLen or MAX_LEN
    cursor = tonumber(cursor) or 1

    local template = doc.template or ""
    if not template:find("{teams}", 1, true) then
        return nil, nil, 0, cursor, "the message has no {teams} in it"
    end

    --[[
    Three different situations used to come back as "nothing to recruit", which is true and
    useless: a new install seeds two teams with no needs, so that is the FIRST thing a raid
    leader sees, with nothing telling them the teams already exist or what to do next.

    They are separated because the fix is different for each one, and this reason is shown
    on the Bark tab's gate as well as under the Message preview.
    ]]
    local recruiting = {}
    local anyActive, anyNeeds = false, false
    for _, team in ipairs(doc.teams or {}) do
        local active = team.active ~= false
        local wants = #(team.needs or {}) > 0
        anyActive = anyActive or active
        anyNeeds = anyNeeds or wants
        if active and wants then recruiting[#recruiting + 1] = team end
    end

    if #recruiting == 0 then
        local why
        if #(doc.teams or {}) == 0 then
            why = "no teams yet: add one on the Teams tab"
        elseif not anyNeeds then
            why = "no roles wanted yet: pick a team on the Teams tab and add a need"
        elseif not anyActive then
            why = "every team is switched off: turn one back on with its On button"
        else
            why = "the only teams asking for anyone are switched off"
        end
        return nil, nil, 0, cursor, why
    end

    local head = Fill(template, "{guild}", (doc.guild ~= "" and doc.guild) or "our guild")
    head = Fill(head, "{contacts}", table.concat(doc.contacts or {}, " or "))

    local shell = Fill(head, "{teams}", "")
    local budget = maxLen - #shell
    if budget <= 0 then
        return nil, nil, 0, cursor,
            string.format("the message is %d characters before any teams go in it", #shell)
    end

    local ordered, nextCursor = Message.Rotate(recruiting, cursor)
    local fragments, level, dropped = Message.Degrade(ordered, budget, doc.teamTemplate)
    if not fragments then
        return nil, nil, dropped, cursor,
            string.format("the team tags alone do not fit in %d characters", maxLen)
    end

    return Fill(head, "{teams}", table.concat(fragments, SEP)), level, dropped, nextCursor
end

--[[
Pure. The last look before it goes out. Returns ok, reason.

The unclosed-colour check matters: a truncation that cut a |c open would colour
everything after it in the chat window, including other people's lines.
]]
function Message.Validate(msg, maxLen)
    maxLen = maxLen or MAX_LEN
    if not msg or msg == "" then return false, "there is nothing to send" end
    if #msg > maxLen then
        return false, string.format("%d characters; the limit is %d", #msg, maxLen)
    end
    if msg:find("\n") or msg:find("\r") then
        return false, "a chat message cannot contain a line break"
    end
    local opens = select(2, msg:gsub("|c%x%x%x%x%x%x%x%x", ""))
    local closes = select(2, msg:gsub("|r", ""))
    if opens ~= closes then
        return false, "a colour code is left open, which would colour the rest of the chat"
    end
    return true
end
