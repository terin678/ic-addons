local addonName, ns = ...

--[[
Allocator: which seat's icon goes on which mob. Pure: no client call, ever; the result
depends only on the arguments, never on table order or on the order mobs were seen, so
every client with the same inputs computes the same plan without talking.

Owned by lane A (model).

    Allocator.Compute(input)        the allocation (below)
    Allocator.Pseudo(set)           blind mode: the rules themselves as candidates
    Allocator.Blind(set, seats, o)  Compute over Pseudo(set)

The icon handed out is always the seat record's own icon (Seats.Resolve keys records by
icon), so a seat can never be carried by another icon. A reserved seat is never lent to a
kill target. A mob with a held icon (placed by hand, read back out of combat) keeps it.

There is no unit token anywhere in here. A candidate is keyed by a durable identity (a GUID
when sighted, the rule key when blind); a unit token is at most a hint MarkPlan passes on
with the GUID it must still point at.
]]

ns.Allocator = ns.Allocator or {}
local Allocator = ns.Allocator
local CC = ns.CC
local Rules = ns.Rules
local Util = LibStub("LibICUtil-1.0")

-- The lowest-ordinal free seat of `intent` that has an owner. skipLastResort holds back
-- seats flagged lastResort so lent icons are spent before them.
local function TakeSeat(seats, intent, used, skipLastResort)
    for _, record in ipairs(seats.byIntent[intent] or {}) do
        if not used[record.icon] and record.owner and not (skipLastResort and record.lastResort) then
            return record
        end
    end
    return nil
end

local function CountKey(rule, candidate)
    return Rules.Key(rule) or candidate.key
end

--[[
input = {
    candidates = { { key, npcID, name, guid, unit, lost }, ... }   key is required and unique
    rules      = { [candidate.key] = rule }                        Rules.Resolve's answer
    seats      = Seats.Resolve's answer
    held       = { [candidate.key] = icon } or nil                  icons already on mobs
    lend       = true to lend spare unreserved icons to kill targets
}
Returns {
    list   = { entry, ... } in the order assigned (held, then rank order, then lent)
    byKey  = { [key] = entry },  byIcon = { [icon] = entry },
    unmet  = { { key, intent }, ... } crowd control that got no seat of its own, by key
}
entry = { key, icon, intent, owner, seat, name, npcID, guid, unit, rank, borrowed, held }
    owner     the player name for a job with an owner, else nil
    seat      the seat record (nil for a held icon the plan has no seat for)
    borrowed  the icon was lent: reported as KILL, it carries no crowd control meaning
Does not change any argument.
]]
function Allocator.Compute(input)
    local candidates = input.candidates or {}
    local rules = input.rules or {}
    local seats = input.seats or { byIcon = {}, byIntent = {}, seats = {} }
    local held = input.held or {}

    local used, counts = {}, {}
    local list, byKey, byIcon, unmet = {}, {}, {}, {}

    local byCandidateKey = {}
    for _, candidate in ipairs(candidates) do
        if candidate.key ~= nil and byCandidateKey[candidate.key] == nil then
            byCandidateKey[candidate.key] = candidate
        end
    end

    local function Record(candidate, icon, intent, seat, rule, extra)
        used[icon] = true
        if rule then
            local k = CountKey(rule, candidate)
            counts[k] = (counts[k] or 0) + 1
        end
        local entry = {
            key = candidate.key, icon = icon, intent = intent, seat = seat,
            owner = seat and type(seat.owner) == "string" and seat.owner or nil,
            name = candidate.name, npcID = candidate.npcID, guid = candidate.guid, unit = candidate.unit,
            rank = rule and rule.rank or nil,
        }
        for k, v in pairs(extra or {}) do entry[k] = v end
        list[#list + 1] = entry
        byKey[candidate.key] = entry
        byIcon[icon] = entry
    end

    -- Held icons first: whoever put it there meant that icon on that mob.
    for _, key in ipairs(Util.SortedKeys(held)) do
        local candidate, icon = byCandidateKey[key], held[key]
        if candidate and type(icon) == "number" and icon >= 1 and icon <= 8 and not used[icon] then
            local seat = seats.byIcon[icon]
            Record(candidate, icon, seat and seat.intent or "MANUAL", seat, rules[key], { held = true })
        end
    end

    local eligible = {}
    for _, candidate in ipairs(candidates) do
        local rule = rules[candidate.key]
        if rule and rule.intent ~= "IGNORE" and byCandidateKey[candidate.key] == candidate
            and not byKey[candidate.key] then
            eligible[#eligible + 1] = { candidate = candidate, rule = rule }
        end
    end
    -- A mob in sight outranks one that walked off; then rank; then key, so a tie is total.
    table.sort(eligible, function(a, b)
        local al, bl = a.candidate.lost and 1 or 0, b.candidate.lost and 1 or 0
        if al ~= bl then return al < bl end
        local ar, br = a.rule.rank or 0, b.rule.rank or 0
        if ar ~= br then return ar < br end
        return tostring(a.candidate.key) < tostring(b.candidate.key)
    end)

    local function UnderMax(entry)
        local max = entry.rule.maxCount
        return not max or (counts[CountKey(entry.rule, entry.candidate)] or 0) < max
    end

    for _, entry in ipairs(eligible) do
        local candidate, rule = entry.candidate, entry.rule
        if UnderMax(entry) then
            local intent = rule.intent
            local seat = TakeSeat(seats, intent, used, input.lend)
            if not seat and CC.NeedsOwner(intent) then
                unmet[#unmet + 1] = { key = candidate.key, intent = intent }
            end
            if not seat and rule.fallback then
                intent = rule.fallback
                seat = TakeSeat(seats, intent, used, input.lend)
            end
            if seat then Record(candidate, seat.icon, intent, seat, rule) end
        end
    end

    -- Lend what is still spare to mobs that got nothing. Only now is an icon known to be
    -- spare, so a crowd control target always won its own seat above. A reserved seat is
    -- never spare: the icon the raid reads as "do not hit this" stays off kill targets.
    if input.lend then
        local spare = {}
        for _, seat in ipairs(seats.seats or {}) do
            if not used[seat.icon] and not seat.reserved then spare[#spare + 1] = seat end
        end
        table.sort(spare, function(a, b)
            local al, bl = a.lastResort and 1 or 0, b.lastResort and 1 or 0
            if al ~= bl then return al < bl end
            if a.ordinal ~= b.ordinal then return a.ordinal < b.ordinal end
            return a.icon > b.icon
        end)
        local nextSpare = 1
        for _, entry in ipairs(eligible) do
            if nextSpare > #spare then break end
            if not byKey[entry.candidate.key] and UnderMax(entry) then
                local seat = spare[nextSpare]
                nextSpare = nextSpare + 1
                if seat.intent == "KILL" then
                    -- A last-resort kill seat reached at the end is its own job, not a loan.
                    Record(entry.candidate, seat.icon, "KILL", seat, entry.rule)
                else
                    Record(entry.candidate, seat.icon, "KILL", nil, entry.rule, { borrowed = true })
                end
            end
        end
    end

    table.sort(unmet, function(a, b) return tostring(a.key) < tostring(b.key) end)
    return { list = list, byKey = byKey, byIcon = byIcon, unmet = unmet }
end

--[[
Blind mode: no pack to see, so each rule that has a name stands for one mob. maxCount is
moot (one name marks one mob per press). Returns candidates, rules (by candidate key) and
the keys skipped because the rule has only an npc id, which the macro cannot target.
]]
function Allocator.Pseudo(set)
    local candidates, rules, skipped = {}, {}, {}
    for _, entry in ipairs(select(2, Rules.Ranked(set or {}))) do
        local rule = entry.rule
        if type(rule.name) == "string" and rule.name ~= "" then
            candidates[#candidates + 1] = { key = entry.key, name = rule.name, npcID = rule.npcID, blind = true }
            rules[entry.key] = rule
        else
            skipped[#skipped + 1] = entry.key
        end
    end
    return candidates, rules, skipped
end

-- opts: { lend, held }. Returns Compute's answer, plus .skipped from Pseudo.
function Allocator.Blind(set, seats, opts)
    local candidates, rules, skipped = Allocator.Pseudo(set)
    local result = Allocator.Compute({
        candidates = candidates, rules = rules, seats = seats,
        lend = opts and opts.lend, held = opts and opts.held,
    })
    result.skipped = skipped
    return result
end
