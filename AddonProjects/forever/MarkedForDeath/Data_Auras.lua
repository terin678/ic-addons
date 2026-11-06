local addonName, ns = ...

--[[
Data_Auras: the raid buffs and consumables the raid check knows, by aura spell id.
Owned by lane C (raid check). Pure: no client call, ever.

On Forever an aura is matched by its spell id. A name is only a fallback for an aura whose
id is not listed here yet, and a fallback never makes anyone read as missing: it can only
turn a "missing" into a "has it". That is the Gift of Arthas lesson from Anniversary
(2026-09-14): an elixir the table did not know called one raider out at all eleven pulls.

Every id carries where it came from, so a wrong one can be traced:

    eui     EllesmereUI_BuffPresets.lua on the Forever client (FOREVER_BUFF_FAMILIES and the
            Forever consumables list), EllesmereUIAuraBuffReminders.lua (food ids, the Well
            Fed icon). All rights reserved: ids typed in, no code or layout copied.
    vuhdo   VuhDo/Flavors/Forever (Shadow Protection ranks). Ids only.
    dbcache The client's hotfix cache (_forever_\Cache\ADB\enUS\DBCache.bin): the Forever
            "Endless" line, item and buff named alike (recon-data-sources section 2).
    probe   Seen on this client by MFDProbe (MFDProbeDB.capture.auras, 2026-11-05).
    classic The classic-era id, not yet seen on Forever. Forever reuses classic ids for
            vanilla content (recon), but Well Fed (1248688) and Minor Arcane Elixir
            (1245244) proved it does not always. Capture mode replaces these
            (PENDING-PROBE P14); a wrong one only fails to match, and the name
            fallback still catches the aura.

    Auras.BUFFS        the class buff columns, in grid order
    Auras.BLESSINGS    paladin blessings, single and greater as one label
    Auras.CONSUMABLES  [spellId] = { kind = "flask" | "elixir", slot, name, src }
    Auras.FOOD         [spellId] = { name, src }; FOOD_ICON and FOOD_NAMES are fallbacks
    Auras.IGNORED      [spellId] = name: consumables that are not raid preparation
    Auras.FALLBACK     name rules for an aura whose id is not listed
    Auras.Lookup()     spellId -> what it is, built once from the tables above
]]

ns.Auras = ns.Auras or {}
local Auras = ns.Auras

--------------------------------------------------------------------------------
-- Class buffs
--------------------------------------------------------------------------------

--[[
One column each. `classes` are who can cast it: a buff nobody present can cast is never
missing. `required = false` shows the column and never calls anyone out. `proven = true`
means a class is not enough to know the buff can be given (Divine Spirit is a talent, and
on Forever there is no inspect of talents), so it is required only once somebody in the
group is seen wearing it.
]]
Auras.BUFFS = {
    { key = "INT", label = "Int", name = "Arcane Intellect", classes = { "MAGE" }, src = "eui",
      ids = { 1459, 1460, 1461, 10156, 10157, 13326, 16876, 364161, 23028 } },
    { key = "MARK", label = "Mark", name = "Mark of the Wild", classes = { "DRUID" }, src = "eui",
      ids = { 1126, 5232, 5234, 5286, 5287, 6756, 8907, 8908, 9884, 9885, 16878, 24752,
              364163, 1291335, 1310503, 21849, 21850 } },
    { key = "FORT", label = "Fort", name = "Power Word: Fortitude", classes = { "PRIEST" }, src = "eui",
      ids = { 1243, 1244, 1245, 2791, 10937, 10938, 10939, 10940, 13864, 23947, 23948,
              21562, 21564, 450086 } },
    { key = "SPIRIT", label = "Spirit", name = "Divine Spirit", classes = { "PRIEST" }, src = "eui",
      proven = true,
      ids = { 14752, 14818, 14819, 16875, 27841, 27681 } },
    -- Shown, never required: on Anniversary it named about twenty people at every callout
    -- on fights where nobody needed it, and a line the raid learns to skip teaches it to
    -- skip the others too.
    { key = "SHADOW", label = "SProt", name = "Shadow Protection", classes = { "PRIEST" }, src = "vuhdo",
      required = false,
      ids = { 976, 10957, 10958, 27683 } },
}

--------------------------------------------------------------------------------
-- Blessings
--------------------------------------------------------------------------------

-- Which blessings someone carries is shown, never judged: the count expected is one per
-- paladin present. 1213408 (Kings) and 26650 (Light) are the client's other copies.
Auras.BLESSING_CLASSES = { "PALADIN" }
Auras.BLESSINGS = {
    { key = "Kings", src = "eui", ids = { 20217, 1213408, 25898 } },
    { key = "Might", src = "eui", ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 } },
    { key = "Wisdom", src = "eui", ids = { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918 } },
    { key = "Salv", src = "eui", ids = { 1038, 1912, 25895 } },
    { key = "Light", src = "eui", ids = { 19977, 19978, 19979, 26650, 25890 } },
}

--------------------------------------------------------------------------------
-- Flasks and elixirs
--------------------------------------------------------------------------------

--[[
`slot` is the elixir's slot as TBC filed the vanilla elixirs (battle or guardian), or nil
when it is not known. Whether Forever keeps slots at all is not known: vanilla had none.
The model does not need to know: "a flask, or two elixirs" is right either way, because
where slots exist two battle elixirs cannot be worn together. The slot only words a
callout ("Guardian elixir" rather than "Second elixir").
]]
Auras.CONSUMABLES = {
    [17626] = { kind = "flask", name = "Flask of the Titans", src = "eui" },
    [17628] = { kind = "flask", name = "Flask of Supreme Power", src = "eui" },
    [17627] = { kind = "flask", name = "Flask of Distilled Wisdom", src = "eui" },
    [17629] = { kind = "flask", name = "Flask of Chromatic Resistance", src = "eui" },
    -- The same flask's name on the hotfixed SpellName row (recon-data-sources section 2).
    [17638] = { kind = "flask", name = "Flask of Chromatic Resistance", src = "dbcache" },
    [17624] = { kind = "flask", name = "Flask of Petrification", src = "classic" },

    [17538] = { kind = "elixir", slot = "battle", name = "Elixir of the Mongoose", src = "eui" },
    [17539] = { kind = "elixir", slot = "battle", name = "Greater Arcane Elixir", src = "eui" },
    [11474] = { kind = "elixir", slot = "battle", name = "Elixir of Shadow Power", src = "eui" },
    [21920] = { kind = "elixir", slot = "battle", name = "Elixir of Frost Power", src = "eui" },
    [17537] = { kind = "elixir", slot = "guardian", name = "Elixir of Brute Force", src = "eui" },
    [17535] = { kind = "elixir", slot = "guardian", name = "Elixir of the Sages", src = "eui" },
    [673] = { kind = "elixir", slot = "guardian", name = "Elixir of Minor Defense", src = "probe" },
    [1245244] = { kind = "elixir", name = "Minor Arcane Elixir", src = "probe" },

    [1327736] = { kind = "elixir", name = "Elixir of Endless Intellect", src = "dbcache" },
    [1327737] = { kind = "elixir", name = "Elixir of Endless Power", src = "dbcache" },
    [1327738] = { kind = "elixir", name = "Elixir of Endless Healing", src = "dbcache" },
    [1327751] = { kind = "elixir", name = "Elixir of Endless Rapidity", src = "dbcache" },
    [1327753] = { kind = "elixir", name = "Elixir of Endless Opportunity", src = "dbcache" },
    [1328032] = { kind = "elixir", name = "Elixir of Endless Mana", src = "dbcache" },
    [1328118] = { kind = "elixir", name = "Elixir of Endless Growth", src = "dbcache" },

    [11334] = { kind = "elixir", slot = "battle", name = "Greater Agility", src = "classic" },
    [11405] = { kind = "elixir", slot = "battle", name = "Elixir of the Giants", src = "classic" },
    [26276] = { kind = "elixir", slot = "battle", name = "Greater Firepower", src = "classic" },
    [11371] = { kind = "elixir", slot = "guardian", name = "Gift of Arthas", src = "classic" },
    [3593] = { kind = "elixir", slot = "guardian", name = "Elixir of Fortitude", src = "classic" },
    [11348] = { kind = "elixir", slot = "guardian", name = "Elixir of Superior Defense", src = "classic" },
    [11396] = { kind = "elixir", slot = "guardian", name = "Greater Intellect", src = "classic" },
    [24363] = { kind = "elixir", slot = "guardian", name = "Mageblood Potion", src = "classic" },
}

-- Consumables that are not raid preparation: worn, they count for nothing and are never
-- reported as unlisted.
Auras.IGNORED = {
    [1328127] = "Elixir of Endless Experience",   -- dbcache: experience, not combat
}

--------------------------------------------------------------------------------
-- Food
--------------------------------------------------------------------------------

-- Food buffs not named Well Fed (Grilled Squid, Nightfin Soup and the rest) share names
-- with other buffs, so they are matched by id only. Well Fed on Forever is 1248688
-- (probe), not the classic 19705, which is kept in case both exist.
Auras.FOOD = {
    [1248688] = { name = "Well Fed", src = "probe" },
    [19705] = { name = "Well Fed", src = "eui" },
    [18192] = { name = "Grilled Squid", src = "eui" },
    [18194] = { name = "Nightfin Soup", src = "eui" },
    [22730] = { name = "Runn Tum Tuber Surprise", src = "eui" },
    [25661] = { name = "Dirge's Kickin' Chimaerok Chops", src = "eui" },
    [18125] = { name = "Blessed Sunfruit", src = "eui" },
    [18141] = { name = "Blessed Sunfruit Juice", src = "eui" },
}

-- Every food buff wears this icon (EllesmereUIAuraBuffReminders reads food by it).
Auras.FOOD_ICON = 136000
Auras.FOOD_NAMES = { ["Well Fed"] = true }

--------------------------------------------------------------------------------
-- Name fallbacks for unlisted ids
--------------------------------------------------------------------------------

--[[
Only for an aura whose id is in no table above. A match counts the aura as held and puts
its name on the unlisted list (/mfd auras), so the id can be added here.
`names` are elixir buffs whose name does not say "Elixir" (Gift of Arthas). A buff name
shared with something else (Mana Regeneration is Mageblood's and Nightfin Soup's) is
never listed: that one is matched by id or not at all.
]]
Auras.FALLBACK = {
    flaskPrefix = "Flask of ",
    elixirWord = "Elixir",
    names = {
        ["Gift of Arthas"] = "guardian",
        ["Greater Agility"] = "battle",
        ["Greater Intellect"] = "guardian",
        ["Greater Firepower"] = "battle",
        ["Greater Armor"] = "guardian",
    },
}

--------------------------------------------------------------------------------
-- Lookup
--------------------------------------------------------------------------------

--[[
Returns ids, problems. `ids` maps every listed spell id to what it is:
    { what = "buff", key }  { what = "blessing", key }  { what = "flask" | "elixir", slot, name }
    { what = "food", name }  { what = "ignored", name }
`problems` lists every id claimed twice, as text. Built from `data` (Auras by default),
so a case hands in its own tables.
]]
function Auras.Index(data)
    data = data or Auras
    local ids, problems = {}, {}
    local function Claim(id, entry, owner)
        if ids[id] then
            problems[#problems + 1] = string.format("%d is in %s and %s", id, ids[id].owner, owner)
            return
        end
        entry.owner = owner
        ids[id] = entry
    end
    for _, buff in ipairs(data.BUFFS or {}) do
        for _, id in ipairs(buff.ids) do Claim(id, { what = "buff", key = buff.key }, "buff " .. buff.key) end
    end
    for _, blessing in ipairs(data.BLESSINGS or {}) do
        for _, id in ipairs(blessing.ids) do
            Claim(id, { what = "blessing", key = blessing.key }, "blessing " .. blessing.key)
        end
    end
    for id, c in pairs(data.CONSUMABLES or {}) do
        Claim(id, { what = c.kind, slot = c.slot, name = c.name }, c.kind .. " " .. c.name)
    end
    for id, f in pairs(data.FOOD or {}) do
        Claim(id, { what = "food", name = f.name }, "food " .. f.name)
    end
    for id, name in pairs(data.IGNORED or {}) do
        Claim(id, { what = "ignored", name = name }, "ignored " .. name)
    end
    table.sort(problems)
    return ids, problems
end

local index

-- The index of the shipped tables, built on first use.
function Auras.Lookup()
    if not index then index = Auras.Index(Auras) end
    return index
end

-- The buff column definition for `key`, or nil.
function Auras.Buff(key)
    for _, buff in ipairs(Auras.BUFFS) do
        if buff.key == key then return buff end
    end
    return nil
end
