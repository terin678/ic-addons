local addonName, ns = ...

--[[
Debug: why a press of Mark pack would not do what the player expects, most fundamental
reason first (spec 5.7). Pure: no client call, ever; the runtime lane gathers the state.

Owned by lane A (model). The table is ns.DebugWhy, not ns.Debug: Core.lua already gives
ns.Debug to the debug chat line.

    DebugWhy.WhyNot(state)       ordered { { code, level, text }, ... }; empty means all clear
    DebugWhy.PlanLines(steps)    the plan as chat lines: "Skull (Kill 1): Scarlet Monk"

state = {
    enabled     false when the addon is switched off
    inGroup     false when solo (fine: marks work solo)
    inRaid      true in a raid group
    canMark     false when the raid denies this player icons (not leader or assist)
    stale       true when the plan changed while locked (MarkPlan.Pending said "hold")
    ruleCount   rules for this instance
    blind       true when mob names are hidden here
    dropped     steps that did not fit in the macro (a count or a list)
    nameless    rules or mobs with no name a macro can target (a count or a list)
    built       false until the secure button has been written once
    conflicts   names of marker addons found active
}
level: "block" (nothing will be marked), "warn" (some of it will not), "info".
]]

ns.DebugWhy = ns.DebugWhy or {}
local Debug = ns.DebugWhy
local Seats = ns.Seats

local function Count(v)
    if type(v) == "number" then return v end
    if type(v) == "table" then return #v end
    return 0
end

local function Plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

function Debug.WhyNot(state)
    state = state or {}
    local reasons = {}
    local function Add(code, level, text)
        reasons[#reasons + 1] = { code = code, level = level, text = text }
    end

    if state.enabled == false then
        Add("off", "block", "the addon is off: /mfd on")
    end
    if state.inGroup == false then
        Add("solo", "info", "not in a group: marks still work solo")
    end
    if state.inRaid and state.canMark == false then
        Add("rights", "block", "you are not raid leader or assist, so the raid will not take your marks")
    end
    if state.stale then
        Add("stale", "warn", "the plan changed in combat: the button keeps the old plan until combat ends")
    end
    if (tonumber(state.ruleCount) or 0) == 0 then
        Add("norules", "block", "no rules for this instance")
    end
    if state.blind then
        Add("blind", "info", "mob names are hidden here: the plan runs from the rules, by name only")
    end
    local dropped = Count(state.dropped)
    if dropped > 0 then
        Add("toolong", "warn", "the macro is too long: " .. Plural(dropped, "seat", "seats") .. " dropped")
    end
    local nameless = Count(state.nameless)
    if nameless > 0 then
        Add("noname", "warn", Plural(nameless, "rule has", "rules have") .. " no name yet, so the macro skips them")
    end
    if state.built == false then
        Add("notbuilt", "block", "the Mark pack button is not built yet: it is written at the first moment out of combat")
    end
    local conflicts = type(state.conflicts) == "table" and state.conflicts or {}
    if #conflicts > 0 then
        Add("conflict", "warn", "another marker addon is active: " .. table.concat(conflicts, ", "))
    end
    return reasons
end

-- steps: MarkPlan.Steps. Returns one line per step, in press order.
function Debug.PlanLines(steps)
    local lines = {}
    for i, step in ipairs(steps or {}) do
        local seat = step.seatLabel or (step.borrowed and "lent" or "held")
        local owner = step.owner and (" -> " .. step.owner) or ""
        lines[i] = string.format("%s (%s): %s%s", Seats.ICON_NAMES[step.icon] or tostring(step.icon),
            seat, tostring(step.name), owner)
    end
    return lines
end
