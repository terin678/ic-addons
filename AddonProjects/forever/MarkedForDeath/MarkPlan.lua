local addonName, ns = ...

--[[
MarkPlan: an allocation turned into what a press consumes. Pure: no client call, ever.
This file never places an icon; a secure button (or the Mark guide on the fallback, spec
5.6) consumes what it returns.

Owned by lane A (model).

    MarkPlan.Steps(alloc)                 ordered { icon, name, guid, unit, seat ... } list
    MarkPlan.Build(steps, limit)          macro text and the steps that did not fit
    MarkPlan.Split(steps, limit, names)   the same over chained buttons
    MarkPlan.ClearText()                  the fallback clear line (target only)
    MarkPlan.RemarkText(steps, limit, clearButton)
    MarkPlan.Actionable(step, guidOf)     a unit hint only while it still names that mob
    MarkPlan.IconFor(facts, steps)        the icon the plan wants on one unit (Mark guide)
    MarkPlan.Fingerprint(steps)           a string that changes when the plan changes
    MarkPlan.Pending(written, wanted, locked)   "same" | "write" | "hold"

Limits are constants until the probe answers P7 (longest macrotext) and P17 (/click in
macrotext): LIMIT is what ships, LONG_LIMIT is the client's macro cap if P7 allows it.
]]

ns.MarkPlan = ns.MarkPlan or {}
local MarkPlan = ns.MarkPlan
local Seats = ns.Seats

MarkPlan.LIMIT = 255          -- bytes of macrotext per button, until P7
MarkPlan.LONG_LIMIT = 1023    -- bytes, if P7 says longer macrotext runs
MarkPlan.RESTORE = "/targetlasttarget"

-- The unit hint a step may carry: a nameplate token paired with the GUID it named when
-- seen. Never target, mouseover, focus, partyNtarget or any other token that follows
-- someone's pointer, and never a token without a GUID to check it against.
function MarkPlan.Hint(entry)
    local unit = entry and entry.unit
    if type(unit) ~= "string" or type(entry.guid) ~= "string" then return nil end
    if not unit:match("^nameplate%d+$") then return nil end
    return unit
end

--[[
alloc: Allocator.Compute's answer. Returns steps in seat order (Kill 1 = Skull first, then
the other jobs; a lent icon after the seats of its job) and the keys left out because the
mob has no name a macro can target (an id-only rule, or a name that was secret).
step = { icon, iconName, name, guid, unit, key, intent, seatLabel, owner, borrowed }
]]
function MarkPlan.Steps(alloc)
    local steps, nameless = {}, {}
    for _, entry in ipairs(alloc and alloc.list or {}) do
        if type(entry.name) == "string" and entry.name ~= "" then
            steps[#steps + 1] = {
                icon = entry.icon, iconName = Seats.ICON_NAMES[entry.icon],
                name = entry.name, guid = entry.guid, unit = MarkPlan.Hint(entry),
                key = entry.key, intent = entry.intent, owner = entry.owner, borrowed = entry.borrowed,
                seatLabel = entry.seat and Seats.Label(entry.seat) or nil,
                ordinal = entry.seat and entry.seat.ordinal or 99,
                rank = entry.rank or 0,
            }
        else
            nameless[#nameless + 1] = entry.key
        end
    end
    table.sort(steps, function(a, b)
        local sa = { intent = a.borrowed and "KILL" or a.intent, ordinal = a.ordinal, icon = a.icon }
        local sb = { intent = b.borrowed and "KILL" or b.intent, ordinal = b.ordinal, icon = b.icon }
        if sa.intent ~= sb.intent or sa.ordinal ~= sb.ordinal then return Seats.Before(sa, sb) end
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.icon > b.icon
    end)
    table.sort(nameless, function(a, b) return tostring(a) < tostring(b) end)
    return steps, nameless
end

local function Pair(step)
    return "/targetexact " .. step.name .. "\n/tm ~" .. step.icon
end

-- Fits as many whole pairs as `limit` bytes allow, with `tail` (a closing line) kept room
-- for. Returns the lines used and the steps that did not fit.
local function Fit(steps, first, limit, tail)
    local lines, size, last = {}, #tail, first - 1
    for i = first, #steps do
        local pair = Pair(steps[i])
        local add = #pair + 1     -- the line break joining it on
        if size + add > limit then break end
        lines[#lines + 1] = pair
        size = size + add
        last = i
    end
    return lines, last
end

--[[
steps: from Steps. limit: bytes (default LIMIT). Returns the macro text, and the steps that
did not fit, in order. Cut on a whole pair, never mid-pair, so a press never targets a mob
it then cannot mark. The text ends by putting the player's target back. An empty plan is
empty text.
]]
function MarkPlan.Build(steps, limit)
    limit = limit or MarkPlan.LIMIT
    if not steps or #steps == 0 then return "", {} end
    local lines, last = Fit(steps, 1, limit, MarkPlan.RESTORE)
    local dropped = {}
    for i = last + 1, #steps do dropped[#dropped + 1] = steps[i] end
    if #lines == 0 then return "", dropped end
    lines[#lines + 1] = MarkPlan.RESTORE
    return table.concat(lines, "\n"), dropped
end

--[[
The plan over chained buttons (P17): every page but the last ends "/click <next name>"; the
last ends by restoring the target. names: the button names in order; the first is the one
pressed. Returns pages (texts, one per button used) and the steps no page could hold.
]]
function MarkPlan.Split(steps, limit, names)
    limit = limit or MarkPlan.LIMIT
    names = names or {}
    local pages, first = {}, 1
    if not steps or #steps == 0 then return pages, {} end
    for page = 1, math.max(#names, 1) do
        -- A page that can hold everything left closes with the restore line and ends the
        -- chain. Otherwise it closes with a click on the next button, if there is one.
        local lines, last = Fit(steps, first, limit, MarkPlan.RESTORE)
        local tail = MarkPlan.RESTORE
        if last < #steps and names[page + 1] then
            tail = "/click " .. names[page + 1]
            lines, last = Fit(steps, first, limit, tail)
        end
        if #lines == 0 then break end
        lines[#lines + 1] = tail
        pages[#pages + 1] = table.concat(lines, "\n")
        first = last + 1
        if tail == MarkPlan.RESTORE then break end
    end
    local dropped = {}
    for i = first, #steps do dropped[#dropped + 1] = steps[i] end
    return pages, dropped
end

-- The clear line a fallback button uses when clear-all is refused (P6): target only.
function MarkPlan.ClearText()
    return "/tm 0"
end

-- One press that clears every icon then marks the pack: "/click <clearButton>" then the
-- Mark pack lines, fit to limit with the click counted. Returns text, dropped.
function MarkPlan.RemarkText(steps, limit, clearButton)
    limit = limit or MarkPlan.LIMIT
    local click = "/click " .. tostring(clearButton or "MFDClear")
    local text, dropped = MarkPlan.Build(steps, limit - #click - 1)
    if text == "" then return click, dropped end
    return click .. "\n" .. text, dropped
end

--[[
step: from Steps. guidOf(unit): the unit's GUID now, or nil (the caller wraps UnitGUID and
returns nil for a secret answer). Returns the unit only if it still points at the mob the
step was planned for; else nil. A unit token is an alias, not an identity: "mouseover" and
"target" follow the player's pointer, and nameplate tokens are recycled as mobs die and
spawn. Acting through a stale one puts the icon on whatever the player points at now.
]]
function MarkPlan.Actionable(step, guidOf)
    if type(step) ~= "table" or type(step.unit) ~= "string" or type(step.guid) ~= "string" then return nil end
    if type(guidOf) ~= "function" then return nil end
    local ok, now = pcall(guidOf, step.unit)
    if ok and type(now) == "string" and now == step.guid then return step.unit end
    return nil
end

--[[
facts: what can be read of one unit right now, nothing secret: { guid, name }. steps: from
Steps. Returns the icon the plan wants there and its step, or nil and why. A GUID match is
exact; a name match takes the first step of that name not already marked (marked:
{ [icon] = true }, the icons seen on mobs), the order a press would mark them in.
]]
function MarkPlan.IconFor(facts, steps, marked)
    if type(facts) ~= "table" then return nil, "nothing readable on that unit" end
    marked = marked or {}
    if type(facts.guid) == "string" then
        for _, step in ipairs(steps or {}) do
            if step.guid == facts.guid then return step.icon, step end
        end
    end
    if type(facts.name) ~= "string" or facts.name == "" then
        return nil, "its name is hidden here"
    end
    local lowered = string.lower(facts.name)
    for _, step in ipairs(steps or {}) do
        if string.lower(step.name) == lowered and not marked[step.icon] then return step.icon, step end
    end
    return nil, "the plan has no icon for " .. facts.name
end

-- A string that changes whenever what a press would do changes.
function MarkPlan.Fingerprint(steps)
    local parts = {}
    for i, step in ipairs(steps or {}) do parts[i] = step.icon .. "=" .. step.name end
    return table.concat(parts, ";")
end

--[[
written: the fingerprint last written to the button (nil before the first write). wanted:
the fingerprint of the plan now. locked: InCombatLockdown() (never the regen event: the
lock starts about 3 s after it). Returns:
    "same"   nothing to do
    "write"  write it now
    "hold"   the plan changed while locked: keep the old one, tint the bar stale, write
             at PLAYER_REGEN_ENABLED
]]
function MarkPlan.Pending(written, wanted, locked)
    if written == wanted then return "same" end
    if locked then return "hold" end
    return "write"
end
