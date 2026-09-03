-- Bundled TBC raid NPC table. Pure data, no logic.
--
-- Bosses only. Creature ids were read off the DBM-Raids-BC modules installed
-- on the maintainer's client, which are what DBM itself uses to detect each
-- fight, and the names were cross-checked against BigWigs_BurningCrusade.
-- Where one encounter spans several creatures (councils, twins, mounts) every
-- id carries the encounter's name rather than a guessed member name.
--
-- Trash is deliberately absent: neither boss mod carries it and no second
-- source was available to verify a scraped list against. The learning layer
-- records every mob the raid sees, so trash becomes searchable the first time
-- the raid walks past it. A wrong id here would silently mark the wrong mob;
-- a missing one costs nothing.
local MFD = _G.MarkedForDeath or {}

MFD.Data = MFD.Data or {}

-- [npcID] = { name, instanceKey }
MFD.Data.Mobs = {
    -- Karazhan
    [16151] = { "Attumen the Huntsman", "KARAZHAN" },
    [16152] = { "Attumen the Huntsman", "KARAZHAN" },
    [15687] = { "Moroes", "KARAZHAN" },
    [16457] = { "Maiden of Virtue", "KARAZHAN" },
    [17521] = { "The Big Bad Wolf", "KARAZHAN" },
    [17534] = { "Romulo and Julianne", "KARAZHAN" },
    [17533] = { "Romulo and Julianne", "KARAZHAN" },
    [15691] = { "The Curator", "KARAZHAN" },
    [16524] = { "Shade of Aran", "KARAZHAN" },
    [15689] = { "Netherspite", "KARAZHAN" },
    [21752] = { "Chess Event", "KARAZHAN" },
    [21684] = { "Chess Event", "KARAZHAN" },
    [15690] = { "Prince Malchezaar", "KARAZHAN" },
    [17225] = { "Nightbane", "KARAZHAN" },
    [16180] = { "Shadikith the Glider", "KARAZHAN" },
    [16179] = { "Hyakiss the Lurker", "KARAZHAN" },
    [16181] = { "Rokad the Ravager", "KARAZHAN" },

    -- Gruul's Lair
    [19044] = { "Gruul the Dragonkiller", "GRUUL" },
    [18831] = { "High King Maulgar", "GRUUL" },
    [18832] = { "High King Maulgar", "GRUUL" },
    [18834] = { "High King Maulgar", "GRUUL" },
    [18835] = { "High King Maulgar", "GRUUL" },
    [18836] = { "High King Maulgar", "GRUUL" },

    -- Magtheridon's Lair
    [17257] = { "Magtheridon", "MAGTHERIDON" },

    -- Serpentshrine Cavern
    [21216] = { "Hydross the Unstable", "SERPENTSHRINE" },
    [21217] = { "The Lurker Below", "SERPENTSHRINE" },
    [21215] = { "Leotheras the Blind", "SERPENTSHRINE" },
    [21214] = { "Fathom-Lord Karathress", "SERPENTSHRINE" },
    [21213] = { "Morogrim Tidewalker", "SERPENTSHRINE" },
    [21212] = { "Lady Vashj", "SERPENTSHRINE" },

    -- Tempest Keep
    [19514] = { "Al'ar", "TEMPESTKEEP" },
    [19516] = { "Void Reaver", "TEMPESTKEEP" },
    [18805] = { "High Astromancer Solarian", "TEMPESTKEEP" },
    [19622] = { "Kael'thas Sunstrider", "TEMPESTKEEP" },

    -- Hyjal Summit
    [17767] = { "Rage Winterchill", "HYJAL" },
    [17808] = { "Anetheron", "HYJAL" },
    [17888] = { "Kaz'rogal", "HYJAL" },
    [17842] = { "Azgalor", "HYJAL" },
    [17968] = { "Archimonde", "HYJAL" },

    -- Black Temple
    [22887] = { "High Warlord Naj'entus", "BLACKTEMPLE" },
    [22898] = { "Supremus", "BLACKTEMPLE" },
    [22841] = { "Shade of Akama", "BLACKTEMPLE" },
    [22871] = { "Teron Gorefiend", "BLACKTEMPLE" },
    [22948] = { "Gurtogg Bloodboil", "BLACKTEMPLE" },
    [23420] = { "Reliquary of Souls", "BLACKTEMPLE" },
    [22947] = { "Mother Shahraz", "BLACKTEMPLE" },
    [22949] = { "Illidari Council", "BLACKTEMPLE" },
    [22950] = { "Illidari Council", "BLACKTEMPLE" },
    [22951] = { "Illidari Council", "BLACKTEMPLE" },
    [22952] = { "Illidari Council", "BLACKTEMPLE" },
    [22917] = { "Illidan Stormrage", "BLACKTEMPLE" },

    -- Zul'Aman
    [23574] = { "Akil'zon", "ZULAMAN" },
    [23576] = { "Nalorakk", "ZULAMAN" },
    [23578] = { "Jan'alai", "ZULAMAN" },
    [23577] = { "Halazzi", "ZULAMAN" },
    [24239] = { "Hex Lord Malacrass", "ZULAMAN" },
    [23863] = { "Zul'jin", "ZULAMAN" },

    -- Sunwell Plateau
    [24850] = { "Kalecgos", "SUNWELL" },
    [24882] = { "Brutallus", "SUNWELL" },
    [25038] = { "Felmyst", "SUNWELL" },
    [25165] = { "The Eredar Twins", "SUNWELL" },
    [25166] = { "The Eredar Twins", "SUNWELL" },
    [25741] = { "M'uru", "SUNWELL" },
    [25315] = { "Kil'jaeden", "SUNWELL" },
}

_G.MarkedForDeath = MFD
