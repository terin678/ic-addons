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
    -- Shown on the grid, never required. It named about twenty people at every
    -- callout in Black Temple on 2026-09-14, on fights where nobody needed it,
    -- and a line the raid learns to skip teaches it to skip the others too.
    SP     = { label = "SProt",  names = { "Shadow Protection", "Prayer of Shadow Protection" }, classes = { "PRIEST" },
               isRequired = false },
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

-- Shattrath Flasks name their buff the other way round: the item "Shattrath Flask
-- of Fortification" puts "Fortification of Shattrath" on the player, so the prefix
-- test above never saw one and everybody on a Shattrath flask read as unflasked.
-- Seen on a raid's own buffs on 2026-09-14: Fortification, Pure Death, Relentless
-- Assault and Blinding Light, each "of Shattrath".
A.FLASK_SUFFIX = " of Shattrath"

-- TBC elixirs by slot. An elixir in neither table is surfaced as unclassified
-- rather than filed wrong. Verify against the client with /mfd auras; add, do
-- not guess.
--
-- Listed by item name. The buff a player carries often drops the "Elixir of":
-- Major Agility, Major Strength, Major Shadow Power and Healing Power were all
-- seen that way on 2026-09-14, while Elixir of Major Fortitude and Elixir of
-- Draenic Wisdom kept it. RC.Classify accepts both forms against these entries.
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
    -- Both seen on raid members on 2026-09-14 and surfacing as unclassified.
    -- Both raise damage, which is what makes a TBC elixir a battle one.
    ["Greater Arcane Elixir"] = true,
    ["Elixir of Demonslaying"] = true,
}

A.GUARDIAN_ELIXIRS = {
    ["Elixir of Major Mageblood"] = true,
    ["Elixir of Major Fortitude"] = true,
    ["Elixir of Major Defense"] = true,
    ["Elixir of Draenic Wisdom"] = true,
    ["Elixir of Ironskin"] = true,
    ["Earthen Elixir"] = true,
    ["Elixir of Camouflage"] = true,
    -- A Classic elixir TBC files as a guardian one. Confirmed an elixir in game
    -- on 2026-09-14, and the slot follows from the log: Moophie wore it beside
    -- Major Agility at every pull, and nobody holds two battle elixirs at once.
    -- Missing it called him out at all eleven pulls of the night.
    ["Gift of Arthas"] = true,
}

A.ELIXIR_PATTERN = "Elixir"

_G.MarkedForDeath = MFD
