-- Role model. An icon binds to a role, a role is a durable job in the raid, and
-- a mob rule only names an intent. This file must never call a WoW API.
local MFD = _G.MarkedForDeath or {}

MFD.Roles = MFD.Roles or {}
local Roles = MFD.Roles

-- classes = nil means the intent needs no owner, so its roles are always
-- available. Anything with a class list is skipped entirely when nobody in the
-- raid can perform it, and its mobs resolve through their rule's fallback.
Roles.INTENTS = {
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

Roles.DEFAULT_PLAN = {
    [SKULL]    = { intent = "KILL",   ordinal = 1 },
    [CROSS]    = { intent = "KILL",   ordinal = 2 },
    [SQUARE]   = { intent = "KILL",   ordinal = 3 },
    -- Last resort: in practice the fourth kill icon is rarely reached, so a
    -- spare sheep or banish icon is better spent on a kill target than this
    -- one is. Only meaningful when icon reuse is on; without it there are no
    -- borrowed icons to come first and Circle is just kill four.
    [CIRCLE]   = { intent = "KILL",   ordinal = 4, isLastResort = true },
    [MOON]     = { intent = "SHEEP",  ordinal = 1, pin = "Grimmtusk" },
    [STAR]     = { intent = "SHEEP",  ordinal = 2 },
    [TRIANGLE] = { intent = "BANISH", ordinal = 1 },
    [DIAMOND]  = { intent = "BANISH", ordinal = 2 },
}

-- Creature types this client can report, in English. Used only to tell an
-- unrecognised string apart from a recognised one, so that a localised client
-- fails open instead of warning about every rule.
local KNOWN_CREATURE_TYPES = {
    Humanoid = true, Demon = true, Elemental = true, Beast = true,
    Undead = true, Giant = true, Dragonkin = true, Mechanical = true,
    Critter = true, Totem = true, ["Gas Cloud"] = true, ["Not specified"] = true,
}

-- Which creature types each crowd control actually works on, as of TBC 2.5.
-- An intent absent from this table has no type restriction.
--
-- Only restrictions that are certain on this expansion are listed. Sap is
-- humanoid-only here because beasts, dragonkin and demons did not become
-- sappable until after TBC, and getting that wrong in the permissive direction
-- costs nothing while getting it wrong in the strict direction cries wolf.
local INTENT_CREATURE_TYPES = {
    SHEEP       = { Humanoid = true, Beast = true, Critter = true },
    BANISH      = { Demon = true, Elemental = true },
    ENSLAVE     = { Demon = true },
    SEDUCE      = { Humanoid = true },
    SAP         = { Humanoid = true },
    SHACKLE     = { Undead = true },
    MINDCONTROL = { Humanoid = true },
    HIBERNATE   = { Beast = true, Dragonkin = true },
    REPENTANCE  = { Humanoid = true },
}

-- Returns whether an intent can actually be used on a creature of this type,
-- and a reason when it cannot. Pure.
--
-- Fails open on purpose: an unknown intent, a missing type, or a type string
-- this build does not recognise all return true. The check is advisory, so a
-- false negative costs nothing and a false positive would train the player to
-- ignore it.
function Roles.CanIntentApply(intent, creatureType)
    local allowed = INTENT_CREATURE_TYPES[intent]
    if not allowed then
        return true
    end

    if type(creatureType) ~= "string" or not KNOWN_CREATURE_TYPES[creatureType] then
        return true
    end

    if allowed[creatureType] then
        return true
    end

    local label = Roles.INTENTS[intent] and Roles.INTENTS[intent].label or intent
    return false, label .. " does not work on " .. creatureType .. " targets"
end

-- Seeds the default plan into db.rolePlan when the player has none. Mutates db.
--
-- An empty role plan is not a neutral starting state: the allocator finds no
-- role for any intent and silently marks nothing, which looks exactly like the
-- addon being broken. Rules deliberately ship empty, because guessing a guild's
-- kill order produces confidently wrong marks, but a role plan must not.
--
-- Deep copied so editing the saved plan cannot mutate the shared default.
function Roles.EnsurePlan(db)
    if next(db.rolePlan) then
        return
    end

    db.rolePlan = MFD.H.DeepCopy(Roles.DEFAULT_PLAN)
end

local function isEligible(intent, class)
    local classes = Roles.INTENTS[intent] and Roles.INTENTS[intent].classes
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

-- Takes a role plan and a roster array of { name, class }. Returns
-- { byIntent = { [intent] = array of { icon, ordinal, owner } ordered by
-- ordinal }, byIcon = { [icon] = the same record } }.
--
-- owner is true when the intent needs no owner, a player name when a role has
-- one, and false when the role exists but nobody can fill it. Ordering is by
-- pin first then player name ascending, which is identical on every client and
-- is why backup markers agree without negotiating.
function Roles.Resolve(rolePlan, roster)
    local byIntent, byIcon = {}, {}

    for _, icon in ipairs(MFD.H.SortedKeys(rolePlan)) do
        local role = rolePlan[icon]
        local record = {
            icon = icon,
            ordinal = role.ordinal,
            pin = role.pin,
            isLastResort = role.isLastResort,
            owner = false,
        }
        byIntent[role.intent] = byIntent[role.intent] or {}
        table.insert(byIntent[role.intent], record)
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
        if not (Roles.INTENTS[intent] and Roles.INTENTS[intent].classes) then
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
