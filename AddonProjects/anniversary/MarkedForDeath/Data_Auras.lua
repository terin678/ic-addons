-- Buff and consumable names as the client reports them in UnitAura. Pure data.
--
-- Everything here is matched by name, never by spell id. Names are stable
-- across ranks and client builds and can be verified by reading a buff bar;
-- ids are neither. /mfd auras prints every name so a mismatch shows up.
local MFD = _G.MarkedForDeath or {}

MFD.Data = MFD.Data or {}
MFD.Data.Auras = MFD.Data.Auras or {}
local A = MFD.Data.Auras

-- The buffs everyone should have, and who can cast them. classes drive the
-- provider check: a buff nobody present can cast is never reported missing.
A.RAID_BUFFS = {
    AI     = { label = "Int",    names = { "Arcane Intellect", "Arcane Brilliance" },            classes = { "MAGE" } },
    MOTW   = { label = "MotW",   names = { "Mark of the Wild", "Gift of the Wild" },             classes = { "DRUID" } },
    FORT   = { label = "Fort",   names = { "Power Word: Fortitude", "Prayer of Fortitude" },     classes = { "PRIEST" } },
    SPIRIT = { label = "Spirit", names = { "Divine Spirit", "Prayer of Spirit" },                classes = { "PRIEST" } },
    SP     = { label = "SProt",  names = { "Shadow Protection", "Prayer of Shadow Protection" }, classes = { "PRIEST" } },
}

-- Column order for every surface. The three priest buffs sit together, and
-- SProt keeps its short label: it is Shadow Protection, not Spirit, and the two
-- being one letter apart is exactly why the longer word is spelled out.
A.RAID_BUFF_ORDER = { "AI", "MOTW", "FORT", "SPIRIT", "SP" }

-- Who can hand out a blessing. Which blessing each class should carry is still
-- the raid leader's call; this only decides whether having none at all is
-- worth mentioning.
A.BLESSING_CLASSES = { "PALADIN" }

-- Which blessings someone holds is shown, never judged. Single and greater
-- collapse to one label.
A.BLESSINGS = {
    ["Blessing of Kings"] = "Kings",         ["Greater Blessing of Kings"] = "Kings",
    ["Blessing of Might"] = "Might",         ["Greater Blessing of Might"] = "Might",
    ["Blessing of Wisdom"] = "Wisdom",       ["Greater Blessing of Wisdom"] = "Wisdom",
    ["Blessing of Salvation"] = "Salv",      ["Greater Blessing of Salvation"] = "Salv",
    ["Blessing of Light"] = "Light",         ["Greater Blessing of Light"] = "Light",
    ["Blessing of Sanctuary"] = "Sanct",     ["Greater Blessing of Sanctuary"] = "Sanct",
}

A.FOOD = { ["Well Fed"] = true }

A.FLASK_PREFIX = "Flask of "

-- TBC elixirs by slot. An elixir in neither table is surfaced as unclassified
-- rather than filed wrong. Verify against the client with /mfd auras; add, do
-- not guess.
A.BATTLE_ELIXIRS = {
    ["Elixir of Major Agility"] = true,
    ["Elixir of Major Strength"] = true,
    ["Elixir of Major Firepower"] = true,
    ["Elixir of Major Frost Power"] = true,
    ["Elixir of Major Shadow Power"] = true,
    ["Elixir of Healing Power"] = true,
    ["Elixir of Mastery"] = true,
    ["Adept's Elixir"] = true,
    ["Onslaught Elixir"] = true,
    ["Fel Strength Elixir"] = true,
    ["Elixir of the Searching Eye"] = true,
}

A.GUARDIAN_ELIXIRS = {
    ["Elixir of Major Mageblood"] = true,
    ["Elixir of Major Fortitude"] = true,
    ["Elixir of Major Defense"] = true,
    ["Elixir of Draenic Wisdom"] = true,
    ["Elixir of Ironskin"] = true,
    ["Earthen Elixir"] = true,
    ["Elixir of Camouflage"] = true,
}

A.ELIXIR_PATTERN = "Elixir"

_G.MarkedForDeath = MFD
