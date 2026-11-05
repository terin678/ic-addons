local addonName, ns = ...

--[[
Seats: the eight raid icons belong to seats, and a seat belongs to a player. Pure: no
client call, ever; every function takes its tables as arguments.

Owned by lane A (model).

A seat plan is { [icon] = { intent, ordinal, pin, reserved, lastResort } }, icon 1 to 8
(1 Star, 2 Circle, 3 Diamond, 4 Triangle, 5 Moon, 6 Square, 7 Cross, 8 Skull). The icon is
the key, so a seat can never carry another icon: whatever the allocator hands out is read
straight off this table.

    Seats.ICON_NAMES[icon]          "Skull"
    Seats.Label(seat)               "Kill 1"
    Seats.Validate(plan)            true, or nil and the first problem
    Seats.PlanFor(db, key)          the plan an instance follows, and whether it is its own
    Seats.Detach(db, key)           give an instance its own copy to edit
    Seats.Reattach(db, key)         drop it, so it follows the default again
    Seats.Before(a, b)              seat order: Kill seats first, Skull before Cross ...
    Seats.Resolve(plan, roster)     who owns which seat (see below)
]]

ns.Seats = ns.Seats or {}
local Seats = ns.Seats
local CC = ns.CC
local Util = LibStub("LibICUtil-1.0")

Seats.ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

local INTENT_INDEX = {}
for i, intent in ipairs(CC.ORDER) do INTENT_INDEX[intent] = i end

function Seats.Label(seat)
    local def = seat and CC.INTENTS[seat.intent]
    local label = def and def.label or tostring(seat and seat.intent)
    return label .. " " .. tostring(seat and seat.ordinal or "?")
end

-- Returns true, or nil and the first problem found, read in icon order.
function Seats.Validate(plan)
    if type(plan) ~= "table" then return nil, "a seat plan is a table" end
    local seen = {}
    for _, icon in ipairs(Util.SortedKeys(plan)) do
        local seat = plan[icon]
        if type(icon) ~= "number" or icon < 1 or icon > 8 or icon % 1 ~= 0 then
            return nil, "icon " .. tostring(icon) .. " is not 1 to 8"
        end
        local name = Seats.ICON_NAMES[icon]
        if type(seat) ~= "table" or not CC.IsKnown(seat.intent) or seat.intent == "IGNORE" then
            return nil, name .. " has no job a seat can carry"
        end
        if type(seat.ordinal) ~= "number" or seat.ordinal < 1 or seat.ordinal % 1 ~= 0 then
            return nil, name .. " needs a seat number from 1"
        end
        local key = seat.intent .. seat.ordinal
        if seen[key] then
            return nil, name .. " and " .. seen[key] .. " are both " .. Seats.Label(seat)
        end
        seen[key] = name
    end
    return true
end

-- db.plans.default always exists (Schema.Prepare seeds it); db.plans[key] only once that
-- instance was edited. Returns the plan and whether it is the instance's own.
function Seats.PlanFor(db, instanceKey)
    local plans = db and db.plans or {}
    local own = instanceKey and instanceKey ~= "default" and plans[instanceKey]
    if own then return own, true end
    return plans.default or {}, false
end

-- Copies what the instance was following, so editing starts from what was there. Mutates
-- db. Returns the plan to edit.
function Seats.Detach(db, instanceKey)
    db.plans = db.plans or {}
    if not instanceKey or instanceKey == "default" then
        db.plans.default = db.plans.default or {}
        return db.plans.default
    end
    if not db.plans[instanceKey] then
        db.plans[instanceKey] = Util.DeepCopy((Seats.PlanFor(db, instanceKey)))
    end
    return db.plans[instanceKey]
end

-- Mutates db. The default plan itself is never dropped.
function Seats.Reattach(db, instanceKey)
    if instanceKey and instanceKey ~= "default" and db.plans then db.plans[instanceKey] = nil end
end

-- Kill seats first so Skull is always first; then jobs in CC.ORDER; then seat number;
-- then the higher icon (the traditional Skull, Cross, Square ... reach order).
function Seats.Before(a, b)
    local ai, bi = INTENT_INDEX[a.intent] or 99, INTENT_INDEX[b.intent] or 99
    if ai ~= bi then return ai < bi end
    if a.ordinal ~= b.ordinal then return (a.ordinal or 0) < (b.ordinal or 0) end
    return a.icon > b.icon
end

local function Present(member)
    return type(member) == "table" and type(member.name) == "string" and member.name ~= ""
        and member.online ~= false
end

local function PinMatches(member, pin)
    return member.name == pin or member.display == pin
end

--[[
plan: a seat plan. roster: an array of members { name, class, online, display } (a
LibICGroup snapshot's members fit). A member whose name is missing or who is offline
(online == false) owns nothing; online == nil is unknown and counts as present.

Returns {
    seats    = every seat record in Seats.Before order,
    byIcon   = { [icon] = record },
    byIntent = { [intent] = records by ordinal },
}
record = { icon, intent, ordinal, pin, reserved, lastResort, owner, pinState }
    owner     true for a job with no class (KILL), a player name, or false when nobody
              present can do it (the seat exists but cannot be used)
    pinState  nil (no pin), "held", "absent", "offline", "wrong class", or "taken" (the
              same player is pinned to an earlier seat of this job)

Pins are honoured first; every other seat goes to the next capable player by name
ascending, so every client builds the same table from the same roster. A player holds at
most one seat per job, but may hold seats of different jobs (one warlock can be Banish 1
and Fear 1).
]]
function Seats.Resolve(plan, roster)
    local seats, byIcon, byIntent = {}, {}, {}
    for _, icon in ipairs(Util.SortedKeys(plan or {})) do
        local seat = plan[icon]
        if type(icon) == "number" and type(seat) == "table" and CC.IsKnown(seat.intent) then
            local record = {
                icon = icon, intent = seat.intent, ordinal = seat.ordinal or 1, pin = seat.pin,
                reserved = seat.reserved and true or nil, lastResort = seat.lastResort and true or nil,
                owner = false,
            }
            seats[#seats + 1] = record
            byIcon[icon] = record
            byIntent[seat.intent] = byIntent[seat.intent] or {}
            table.insert(byIntent[seat.intent], record)
        end
    end
    table.sort(seats, Seats.Before)
    for _, records in pairs(byIntent) do table.sort(records, Seats.Before) end

    local members = {}
    for _, member in ipairs(roster or {}) do
        if type(member) == "table" and type(member.name) == "string" then members[#members + 1] = member end
    end
    table.sort(members, function(a, b) return a.name < b.name end)

    for _, intent in ipairs(Util.SortedKeys(byIntent)) do
        local records = byIntent[intent]
        if not CC.NeedsOwner(intent) then
            for _, record in ipairs(records) do record.owner = true end
        else
            local taken = {}
            for _, record in ipairs(records) do
                if record.pin then
                    record.pinState = "absent"
                    for _, member in ipairs(members) do
                        if PinMatches(member, record.pin) then
                            if member.online == false then
                                record.pinState = "offline"
                            elseif not CC.CanClass(intent, member.class) then
                                record.pinState = "wrong class"
                            elseif taken[member.name] then
                                record.pinState = "taken"
                            else
                                record.pinState = "held"
                                record.owner = member.name
                                taken[member.name] = true
                            end
                            break
                        end
                    end
                end
            end
            for _, record in ipairs(records) do
                if not record.owner then
                    for _, member in ipairs(members) do
                        if Present(member) and not taken[member.name] and CC.CanClass(intent, member.class) then
                            record.owner = member.name
                            taken[member.name] = true
                            break
                        end
                    end
                end
            end
        end
    end

    return { seats = seats, byIcon = byIcon, byIntent = byIntent }
end
