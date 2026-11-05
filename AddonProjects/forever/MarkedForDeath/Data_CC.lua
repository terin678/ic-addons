local addonName, ns = ...

--[[
Data_CC: the jobs a seat can carry, who can do each one on the vanilla class set, and the
crowd control spell ids behind them. Pure: no client call, ever; every function takes its
tables as arguments.

Owned by lane A (model).

    CC.ORDER                       intent keys in picker order
    CC.INTENTS[intent]             { label, classes, spells, creatureTypes, hidden, note }
    CC.IsKnown(intent)             a job a rule or seat may hold (hidden ones included)
    CC.NeedsOwner(intent)          true when a seat of this job needs a player of a class
    CC.CanClass(intent, class)     whether a class token can do the job
    CC.Pickable(plan)              the jobs a rule editor offers for a seat plan
    CC.CanApply(intent, type)      whether the job works on a creature type (fails open)
    CC.IntentForSpell(spellID)     the job a spell id belongs to, or nil

Spell ids are facts taken from the WhatsTraining Camelot class lists (MIT) on disk; no code
or layout was copied. Ranks run lowest first. Ids the client data on disk does not hold are
left out and marked PENDING-PROBE P14 in the note: Polymorph: Turtle (28271), the Freezing
Trap aura on a mob, the Seduction aura, Repentance (20066, so REPENTANCE is hidden).
Seat ownership only needs the classes; the spell ids feed the creature-type warning and
the raid check's "who can cast it".
]]

ns.CC = ns.CC or {}
local CC = ns.CC

CC.ORDER = {
    "KILL", "SHEEP", "TRAP", "BANISH", "SEDUCE", "ENSLAVE", "FEAR", "SAP",
    "SHACKLE", "MINDCONTROL", "HIBERNATE", "ROOTS", "REPENTANCE", "IGNORE",
}

-- classes = nil: the job needs no owner, so its seats are always usable.
-- creatureTypes = nil: no restriction. hidden: kept readable for old rules, never offered.
CC.INTENTS = {
    KILL = { label = "Kill" },
    SHEEP = {
        label = "Sheep", classes = { "MAGE" },
        spells = { 118, 12824, 12825, 12826, 28272 },   -- Polymorph ranks 1-4, Pig
        creatureTypes = { Humanoid = true, Beast = true, Critter = true },
        note = "Polymorph: Turtle (28271) is not in the client data on disk: P14",
    },
    TRAP = {
        label = "Trap", classes = { "HUNTER" },
        spells = { 1499, 14310, 14311 },                -- Freezing Trap ranks 1-3
        note = "the trap aura on a mob is PENDING-PROBE P14",
    },
    BANISH = {
        label = "Banish", classes = { "WARLOCK" },
        spells = { 710, 18647 },
        creatureTypes = { Demon = true, Elemental = true },
    },
    SEDUCE = {
        label = "Seduce", classes = { "WARLOCK" },
        spells = { 6358 },                              -- the succubus's spell
        creatureTypes = { Humanoid = true },
        note = "the Seduction aura id is PENDING-PROBE P14",
    },
    ENSLAVE = {
        label = "Enslave", classes = { "WARLOCK" },
        spells = { 1098, 11725, 11726 },
        creatureTypes = { Demon = true },
    },
    FEAR = {
        label = "Fear", classes = { "WARLOCK", "PRIEST" },
        -- Fear ranks 1-3 and Howl of Terror (warlock), Psychic Scream (priest)
        spells = { 5782, 6213, 6215, 5484, 17928, 8122, 8124, 10888, 10890 },
    },
    SAP = {
        label = "Sap", classes = { "ROGUE" },
        spells = { 6770, 2070, 11297 },
        creatureTypes = { Humanoid = true },
    },
    SHACKLE = {
        label = "Shackle", classes = { "PRIEST" },
        spells = { 9484, 9485, 10955 },
        creatureTypes = { Undead = true },
    },
    MINDCONTROL = {
        label = "Mind Control", classes = { "PRIEST" },
        spells = { 605, 10911, 10912 },
        creatureTypes = { Humanoid = true },
    },
    HIBERNATE = {
        label = "Hibernate", classes = { "DRUID" },
        spells = { 2637, 18657, 18658 },
        creatureTypes = { Beast = true, Dragonkin = true },
    },
    ROOTS = {
        label = "Roots", classes = { "DRUID" },
        spells = { 339, 1062, 5195, 5196, 9852, 9853 },
    },
    REPENTANCE = {
        label = "Repentance", classes = { "PALADIN" }, hidden = true,
        spells = {},
        creatureTypes = { Humanoid = true },
        note = "no Repentance spell id found on Forever: hidden until P14 finds one",
    },
    IGNORE = { label = "Never mark" },
}

-- Creature types the client reports in English. A type outside this set (a localised
-- client) makes CanApply fail open rather than warn on every rule.
local KNOWN_CREATURE_TYPES = {
    Humanoid = true, Demon = true, Elemental = true, Beast = true, Undead = true,
    Giant = true, Dragonkin = true, Mechanical = true, Critter = true, Totem = true,
    ["Gas Cloud"] = true, ["Not specified"] = true,
}

local spellIntent = {}
for _, intent in ipairs(CC.ORDER) do
    for _, id in ipairs(CC.INTENTS[intent].spells or {}) do spellIntent[id] = intent end
end

function CC.IsKnown(intent)
    return type(intent) == "string" and CC.INTENTS[intent] ~= nil
end

function CC.NeedsOwner(intent)
    local def = CC.INTENTS[intent]
    return def ~= nil and def.classes ~= nil
end

function CC.CanClass(intent, class)
    local def = CC.INTENTS[intent]
    if not def or not def.classes or type(class) ~= "string" then return false end
    for _, c in ipairs(def.classes) do
        if c == class then return true end
    end
    return false
end

-- plan: a seat plan ({ [icon] = { intent, ordinal, ... } }). Returns the jobs a rule may be
-- given there, in CC.ORDER: every job some seat carries, plus IGNORE (a rule's own answer,
-- needing no icon). A hidden job is never offered, even when a seat still holds it.
function CC.Pickable(plan)
    local held = { IGNORE = true }
    for _, seat in pairs(plan or {}) do
        if type(seat) == "table" and seat.intent then held[seat.intent] = true end
    end
    local list = {}
    for _, intent in ipairs(CC.ORDER) do
        if held[intent] and not CC.INTENTS[intent].hidden then list[#list + 1] = intent end
    end
    return list
end

-- Returns true, or false and a reason, for a job on a creature type. Advisory only, so it
-- fails open: an unknown job, a missing or secret type, or a type not in the English set.
function CC.CanApply(intent, creatureType)
    local def = CC.INTENTS[intent]
    local allowed = def and def.creatureTypes
    if not allowed then return true end
    if type(creatureType) ~= "string" or not KNOWN_CREATURE_TYPES[creatureType] then return true end
    if allowed[creatureType] then return true end
    return false, def.label .. " does not work on " .. creatureType .. " targets"
end

function CC.IntentForSpell(spellID)
    return spellIntent[spellID]
end
