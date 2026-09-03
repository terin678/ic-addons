-- Seat model. An icon binds to a seat, a seat is a durable job in the raid, and
-- a mob rule only names an intent. This file must never call a WoW API.
local MFD = _G.MarkedForDeath or {}

MFD.Seats = MFD.Seats or {}
local Seats = MFD.Seats

-- classes = nil means the intent needs no owner, so its seats are always
-- available. Anything with a class list is skipped entirely when nobody in the
-- raid can perform it, and its mobs resolve through their rule's fallback.
Seats.INTENTS = {
    KILL        = { label = "Kill",          classes = nil },
    SHEEP       = { label = "Sheep",         classes = { "MAGE" } },
    TRAP        = { label = "Trap",          classes = { "HUNTER" } },
    BANISH      = { label = "Banish",        classes = { "WARLOCK" } },
    SEDUCE      = { label = "Seduce",        classes = { "WARLOCK" } },
    ENSLAVE     = { label = "Enslave",       classes = { "WARLOCK" } },
    FEAR        = { label = "Fear",          classes = { "WARLOCK", "PRIEST" } },
    SAP         = { label = "Sap",           classes = { "ROGUE" } },
    SHACKLE     = { label = "Shackle",       classes = { "PRIEST" } },
    MINDCONTROL = { label = "Mind Control",  classes = { "PRIEST" } },
    HIBERNATE   = { label = "Hibernate",     classes = { "DRUID" } },
    ROOTS       = { label = "Roots",         classes = { "DRUID" } },
    REPENTANCE  = { label = "Repentance",    classes = { "PALADIN" } },
    IGNORE      = { label = "Never mark",    classes = nil },
}

-- Raid target icon indices, named so the plan below reads as intended.
local STAR, CIRCLE, DIAMOND, TRIANGLE, MOON, SQUARE, CROSS, SKULL = 1, 2, 3, 4, 5, 6, 7, 8

Seats.DEFAULT_PLAN = {
    [SKULL]    = { intent = "KILL",   ordinal = 1 },
    [CROSS]    = { intent = "KILL",   ordinal = 2 },
    [SQUARE]   = { intent = "KILL",   ordinal = 3 },
    [CIRCLE]   = { intent = "KILL",   ordinal = 4 },
    [MOON]     = { intent = "SHEEP",  ordinal = 1, pin = "Grimmtusk" },
    [STAR]     = { intent = "SHEEP",  ordinal = 2 },
    [TRIANGLE] = { intent = "BANISH", ordinal = 1 },
    [DIAMOND]  = { intent = "BANISH", ordinal = 2 },
}

local function isEligible(intent, class)
    local classes = Seats.INTENTS[intent] and Seats.INTENTS[intent].classes
    if not classes then
        return false
    end
    for _, c in ipairs(classes) do
        if c == class then
            return true
        end
    end
    return false
end

-- Takes a seat plan and a roster array of { name, class }. Returns
-- { byIntent = { [intent] = array of { icon, ordinal, owner } ordered by
-- ordinal }, byIcon = { [icon] = the same record } }.
--
-- owner is true when the intent needs no owner, a player name when a seat has
-- one, and false when the seat exists but nobody can fill it. Ordering is by
-- pin first then player name ascending, which is identical on every client and
-- is why backup markers agree without negotiating.
function Seats.Resolve(seatPlan, roster)
    local byIntent, byIcon = {}, {}

    for _, icon in ipairs(MFD.H.SortedKeys(seatPlan)) do
        local seat = seatPlan[icon]
        local record = { icon = icon, ordinal = seat.ordinal, pin = seat.pin, owner = false }
        byIntent[seat.intent] = byIntent[seat.intent] or {}
        table.insert(byIntent[seat.intent], record)
        byIcon[icon] = record
    end

    for _, records in pairs(byIntent) do
        table.sort(records, function(a, b)
            if a.ordinal ~= b.ordinal then
                return a.ordinal < b.ordinal
            end
            return a.icon < b.icon
        end)
    end

    -- Candidate owners per intent, sorted by name so the result is
    -- deterministic across clients without any coordination.
    local sortedRoster = {}
    for _, member in ipairs(roster) do
        sortedRoster[#sortedRoster + 1] = member
    end
    table.sort(sortedRoster, function(a, b) return a.name < b.name end)

    for intent, records in pairs(byIntent) do
        if not (Seats.INTENTS[intent] and Seats.INTENTS[intent].classes) then
            for _, record in ipairs(records) do
                record.owner = true
            end
        else
            local taken = {}

            -- Pins first, so a pinned player keeps their icon regardless of
            -- where they sort by name.
            for _, record in ipairs(records) do
                if record.pin then
                    for _, member in ipairs(sortedRoster) do
                        if member.name == record.pin and isEligible(intent, member.class) then
                            record.owner = member.name
                            taken[member.name] = true
                            break
                        end
                    end
                end
            end

            for _, record in ipairs(records) do
                if not record.owner then
                    for _, member in ipairs(sortedRoster) do
                        if not taken[member.name] and isEligible(intent, member.class) then
                            record.owner = member.name
                            taken[member.name] = true
                            break
                        end
                    end
                end
            end
        end
    end

    return { byIntent = byIntent, byIcon = byIcon }
end

_G.MarkedForDeath = MFD
