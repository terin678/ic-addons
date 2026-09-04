-- TBC raid boss encounters. Pure data, no logic.
--
-- Every id here was resolved by looking the encounter's mobs up by name in
-- Data_Mobs, which comes from Questie's client-matched database, so these are
-- the ids the client actually reports. Nothing is guessed.
--
-- Two Karazhan encounters are deliberately absent: the Opera Event and the
-- Chess Event. None of their mobs appear in the bundled table, and inventing
-- ids for them would produce a boss toggle that silently never fires, which is
-- worse than not offering it. Everything else in TBC is here.
--
-- ids are for recognising the fight, not for listing every mob in it: one mob
-- that is present when the encounter starts is enough, and adds are left out.
local MFD = _G.MarkedForDeath or {}

MFD.Data = MFD.Data or {}

-- Ordered, because this list is drawn as it stands. Raids in progression order,
-- bosses in the order a raid meets them.
MFD.Data.Bosses = {
    { name = "Attumen the Huntsman",     instance = "KARAZHAN",      ids = { 15550 } },
    { name = "Moroes",                   instance = "KARAZHAN",      ids = { 15687 } },
    { name = "Maiden of Virtue",         instance = "KARAZHAN",      ids = { 16457 } },
    { name = "The Curator",              instance = "KARAZHAN",      ids = { 15691 } },
    { name = "Terestian Illhoof",        instance = "KARAZHAN",      ids = { 15688 } },
    { name = "Shade of Aran",            instance = "KARAZHAN",      ids = { 16524 } },
    { name = "Netherspite",              instance = "KARAZHAN",      ids = { 15689 } },
    { name = "Prince Malchezaar",        instance = "KARAZHAN",      ids = { 15690 } },
    { name = "Nightbane",                instance = "KARAZHAN",      ids = { 17225 } },

    { name = "High King Maulgar",        instance = "GRUUL",         ids = { 18831, 18832, 18834, 18835, 18836 } },
    { name = "Gruul the Dragonkiller",   instance = "GRUUL",         ids = { 19044 } },

    { name = "Magtheridon",              instance = "MAGTHERIDON",   ids = { 17257 } },

    { name = "Hydross the Unstable",     instance = "SERPENTSHRINE", ids = { 21216 } },
    { name = "The Lurker Below",         instance = "SERPENTSHRINE", ids = { 21217 } },
    { name = "Leotheras the Blind",      instance = "SERPENTSHRINE", ids = { 21215 } },
    { name = "Fathom-Lord Karathress",   instance = "SERPENTSHRINE", ids = { 21214 } },
    { name = "Morogrim Tidewalker",      instance = "SERPENTSHRINE", ids = { 21213 } },
    { name = "Lady Vashj",               instance = "SERPENTSHRINE", ids = { 21212 } },

    { name = "Al'ar",                    instance = "TEMPESTKEEP",   ids = { 19514 } },
    { name = "Void Reaver",              instance = "TEMPESTKEEP",   ids = { 19516 } },
    { name = "High Astromancer Solarian", instance = "TEMPESTKEEP",  ids = { 18805 } },
    { name = "Kael'thas Sunstrider",     instance = "TEMPESTKEEP",   ids = { 19622 } },

    { name = "Rage Winterchill",         instance = "HYJAL",         ids = { 17767 } },
    { name = "Anetheron",                instance = "HYJAL",         ids = { 17808 } },
    { name = "Kaz'rogal",                instance = "HYJAL",         ids = { 17888 } },
    { name = "Azgalor",                  instance = "HYJAL",         ids = { 17842 } },
    { name = "Archimonde",               instance = "HYJAL",         ids = { 17968 } },

    { name = "High Warlord Naj'entus",   instance = "BLACKTEMPLE",   ids = { 22887 } },
    { name = "Supremus",                 instance = "BLACKTEMPLE",   ids = { 22898 } },
    { name = "Shade of Akama",           instance = "BLACKTEMPLE",   ids = { 22841 } },
    { name = "Teron Gorefiend",          instance = "BLACKTEMPLE",   ids = { 22871 } },
    { name = "Gurtogg Bloodboil",        instance = "BLACKTEMPLE",   ids = { 22948 } },
    -- Reliquary of the Lost is the mob that is up when the fight starts;
    -- Essence of Anger is the last phase. Either identifies the encounter.
    { name = "Reliquary of Souls",       instance = "BLACKTEMPLE",   ids = { 22856, 23420 } },
    { name = "Mother Shahraz",           instance = "BLACKTEMPLE",   ids = { 22947 } },
    { name = "Illidari Council",         instance = "BLACKTEMPLE",   ids = { 22949, 22950, 22951, 22952 } },
    { name = "Illidan Stormrage",        instance = "BLACKTEMPLE",   ids = { 22917 } },

    { name = "Nalorakk",                 instance = "ZULAMAN",       ids = { 23576 } },
    { name = "Akil'zon",                 instance = "ZULAMAN",       ids = { 23574 } },
    { name = "Jan'alai",                 instance = "ZULAMAN",       ids = { 23578 } },
    { name = "Halazzi",                  instance = "ZULAMAN",       ids = { 23577 } },
    { name = "Hex Lord Malacrass",       instance = "ZULAMAN",       ids = { 24239 } },
    { name = "Zul'jin",                  instance = "ZULAMAN",       ids = { 23863 } },

    { name = "Kalecgos",                 instance = "SUNWELL",       ids = { 24850 } },
    { name = "Brutallus",                instance = "SUNWELL",       ids = { 24882 } },
    { name = "Felmyst",                  instance = "SUNWELL",       ids = { 25038 } },
    { name = "Eredar Twins",             instance = "SUNWELL",       ids = { 25165, 25166 } },
    { name = "M'uru",                    instance = "SUNWELL",       ids = { 25741 } },
    { name = "Kil'jaeden",               instance = "SUNWELL",       ids = { 25315 } },
}

_G.MarkedForDeath = MFD
