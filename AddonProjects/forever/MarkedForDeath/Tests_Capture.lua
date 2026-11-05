local addonName, ns = ...

--[[
Tests_Capture: the data and capture lane's cases. Owned by lane E (data and capture).
Registered on ns.Tests with T.Case; Tests.lua runs them all. Every case builds its own
tables; none touches the saved ones. The merge script has its own cases:
luajit scripts/mfd-forever-capture.lua --selftest.
]]

local T = ns.Tests
local Instances, Mobs, Capture = ns.Instances, ns.Mobs, ns.Capture

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------------
-- Data_Instances
--------------------------------------------------------------------------------

T.Case("Instances.Key: an instance id is i:<id>, the open world is open", function()
    T.Eq(Instances.Key(2999), "i:2999", "instance")
    T.Eq(Instances.Key(0), "open", "GetInstanceInfo's 0")
    T.Eq(Instances.Key(nil), "open", "nothing")
    T.Eq(Instances.Key("2999"), "open", "text is not an id")
    T.Eq(Instances.IdFromKey("i:2999"), 2999, "back to the id")
    T.Eq(Instances.IdFromKey("open"), nil, "the open world has none")
    T.Eq(Instances.IdFromKey("legacy:Karazhan"), nil, "a legacy key has none")
    T.Eq(Instances.IdFromKey(nil), nil, "nil")
end)

T.Case("Instances.Get and Name: lookups by id; an unknown id is nil, not an error", function()
    T.Eq(Instances.Name(2999), "Ruins of Lordaeron", "a Forever dungeon")
    T.Eq(Instances.Name(36), "The Deadmines", "a classic one")
    T.Eq(Instances.Get(2999).size, 5, "its size")
    T.Eq(Instances.Get(2999).forever, true, "marked Forever")
    T.Eq(Instances.Get(123456), nil, "unknown id")
    T.Eq(Instances.Name(123456), nil, "unknown name")
    T.Eq(Instances.Get("2999"), nil, "text is not an id")
    T.Eq(Instances.Get(nil), nil, "nil")
    T.Eq(Instances.Name(2970), nil, "a map known only by its encounter has no name")
    local own = { [7] = { name = "Mine", kind = "party", size = 5 } }
    T.Eq(Instances.Name(7, own), "Mine", "a case's own table")
    T.Eq(Instances.Name(2999, own), nil, "and only that table")
end)

T.Case("Instances.Encounter: name and instance by encounter id", function()
    local name, instance = Instances.Encounter(3354)
    T.Eq(name, "Rath'mael", "name")
    T.Eq(instance, 2999, "instance")
    T.Eq((Instances.Encounter(3303)), "Shade of the Archmage", "Dalaran")
    T.Eq(select(2, Instances.Encounter(3479)), 2970, "an unnamed map's encounter")
    T.Eq(Instances.Encounter(1), nil, "unknown")
    T.Eq(Instances.Encounter(nil), nil, "nil")
end)

T.Case("Instances.FindByName: listed first, then pending, ignoring case", function()
    T.Eq(Instances.FindByName("ruins of lordaeron"), 2999, "listed")
    local id, pending = Instances.FindByName("ONYXIA'S LAIR")
    T.Eq(id, nil, "Onyxia has no id yet")
    T.Eq(pending and pending.size, 40, "but is pending, 40")
    T.Eq(select(2, Instances.FindByName("Hyjal Summit")).size, 20, "Hyjal 20")
    T.Eq(select(2, Instances.FindByName("Barrow Deeps")).size, 10, "Barrow Deeps 10")
    T.Eq(Instances.FindByName("Nowhere"), nil, "unknown")
    T.Eq(select(2, Instances.FindByName("Nowhere")), nil, "not pending either")
    T.Eq(Instances.FindByName(""), nil, "empty")
end)

T.Case("Instances data: every entry well formed, no encounter in two places", function()
    local kinds = { party = true, raid = true, unknown = true }
    local encounterAt = {}
    for id, entry in pairs(Instances.list) do
        T.True(type(id) == "number" and id > 0, "id " .. tostring(id))
        T.True(kinds[entry.kind], "kind of " .. id)
        if entry.kind ~= "unknown" then
            T.True(type(entry.name) == "string" and entry.name ~= "", "name of " .. id)
            T.True(type(entry.size) == "number", "size of " .. id)
        end
        for encID, name in pairs(entry.encounters or {}) do
            T.Eq(encounterAt[encID], nil, "encounter " .. encID .. " in one instance")
            encounterAt[encID] = id
            T.True(type(name) == "string" and name ~= "", "encounter " .. encID .. " named")
        end
    end
    local raids = {}
    for _, entry in ipairs(Instances.pending) do
        T.Eq(Instances.FindByName(entry.name), nil, entry.name .. " is not listed and pending at once")
        if entry.kind == "raid" then raids[entry.size] = entry.name end
    end
    T.Eq(raids[10], "Barrow Deeps", "the 10")
    T.Eq(raids[20], "Hyjal Summit", "the 20")
    T.Eq(raids[40], "Onyxia's Lair", "the 40")
end)

T.Case("Instances.Difficulty: the ids for 5, 10, 20 and 40", function()
    T.Eq(Instances.DifficultyFor("party", 5), 1, "dungeon")
    T.Eq(Instances.DifficultyFor("raid", 10), 3, "10")
    T.Eq(Instances.DifficultyFor("raid", 20), 148, "20")
    T.Eq(Instances.DifficultyFor("raid", 40), 9, "40")
    T.Eq(Instances.DifficultyFor("raid", 25), nil, "no 25 on Forever")
    T.Eq(Instances.Difficulty(9).size, 40, "row by id")
    T.Eq(Instances.Difficulty(999), nil, "unknown")
    T.Eq(Instances.Difficulty("9"), nil, "text")
end)

--------------------------------------------------------------------------------
-- Data_Mobs
--------------------------------------------------------------------------------

T.Case("Mobs data: parses, every instance listed, every mob named", function()
    local mobs, instances = Mobs.Count()
    T.True(mobs > 500, "hundreds of mobs, got " .. mobs)
    T.True(instances >= 20, "most dungeons, got " .. instances)
    for instanceID, list in pairs(Mobs.byInstance) do
        T.True(Instances.Get(instanceID) ~= nil, "mobs of " .. instanceID .. " belong to a listed instance")
        for id, entry in pairs(list) do
            T.True(type(id) == "number" and id > 0, "npc id in " .. instanceID)
            T.True(type(entry.name) == "string" and entry.name ~= "", "name of " .. id)
        end
    end
end)

T.Case("Mobs.Get and Name: by npc and instance; unknown is nil", function()
    T.Eq(Mobs.Name(250660, 2999), "The Baron", "a Forever boss")
    T.Eq(Mobs.Get(250660, 2999).boss, true, "is a boss")
    T.Eq(Mobs.Name(261319, 3065), "Durgen Dirgehammer", "Hall of Thanes")
    T.Eq(Mobs.Name(9039, 230), "Doom'rel", "the npc's own name, not the journal's label")
    T.Eq(Mobs.Name(250660, 36), nil, "wrong instance")
    T.Eq(Mobs.Name(1, 2999), nil, "unknown npc")
    T.Eq(Mobs.Name(nil, 2999), nil, "nil npc")
    T.Eq(Mobs.Name(250660, nil), nil, "nil instance")
end)

T.Case("Mobs.ForInstance: bosses first, then by name", function()
    local own = { [5] = {
        [3] = { name = "Zed" }, [2] = { name = "Adder" }, [9] = { name = "King", boss = true },
        [4] = { name = "Adder" },
    } }
    local list = Mobs.ForInstance(5, own)
    T.Eq(#list, 4, "all four")
    T.Eq(list[1].name, "King", "boss first")
    T.Eq(list[2].id, 2, "then by name, ties by id")
    T.Eq(list[3].id, 4, "the other Adder")
    T.Eq(list[4].name, "Zed", "last")
    T.Eq(#Mobs.ForInstance(6, own), 0, "an instance with none")
    T.Eq(#Mobs.ForInstance(nil, own), 0, "nil")
end)

T.Case("Mobs.Find: every exact match, ignoring case", function()
    local own = { [5] = { [1] = { name = "Ghoul" } }, [6] = { [2] = { name = "ghoul" }, [3] = { name = "Ghoul Lord" } } }
    local hits = Mobs.Find("GHOUL", own)
    T.Eq(#hits, 2, "two ghouls, not the lord")
    T.Eq(hits[1].instance, 5, "by instance")
    T.Eq(hits[2].id, 2, "then id")
    T.Eq(#Mobs.Find("", own), 0, "empty")
    T.Eq(#Mobs.Find(nil, own), 0, "nil")
    T.True(#Mobs.Find("The Baron") >= 1, "the bundled data")
end)

--------------------------------------------------------------------------------
-- Capture: helpers
--------------------------------------------------------------------------------

T.Case("Capture.NpcID: creatures and vehicles only", function()
    T.Eq(Capture.NpcID("Creature-0-4170-2999-12-250660-00007A3B2C"), 250660, "creature")
    T.Eq(Capture.NpcID("Vehicle-0-1-2-3-4567-00000000AA"), 4567, "vehicle")
    T.Eq(Capture.NpcID("Player-4170-0A1B2C3D"), nil, "player")
    T.Eq(Capture.NpcID("Pet-0-1-2-3-416-0100AB"), nil, "pet")
    T.Eq(Capture.NpcID("Creature-0-1-2-3-0-0000AA"), nil, "id 0")
    T.Eq(Capture.NpcID("garbage"), nil, "garbage")
    T.Eq(Capture.NpcID(nil), nil, "nil")
end)

T.Case("Capture.InstanceObservation: from GetInstanceInfo's returns; open world is nil", function()
    local obs = Capture.InstanceObservation("Ruins of Lordaeron", "party", 1, "Normal", 5, false, false, 2999)
    T.Eq(obs.kind, "instance", "kind")
    T.Eq(obs.id, 2999, "id")
    T.Eq(obs.name, "Ruins of Lordaeron", "name")
    T.Eq(obs.type, "party", "type")
    T.Eq(obs.difficulty, 1, "difficulty")
    T.Eq(obs.size, 5, "size")
    T.Eq(Capture.InstanceObservation("Eastern Kingdoms", "none", 0, "", 0, false, false, 0), nil, "open world")
    T.Eq(Capture.InstanceObservation("X", "raid", 9, "40 Player", 40, false, false, nil), nil, "a secret id")
    local hidden = Capture.InstanceObservation(nil, "raid", nil, nil, nil, false, false, 3201)
    T.Eq(hidden.id, 3201, "a secret name still records the id")
    T.Eq(hidden.name, nil, "without the name")
end)

--------------------------------------------------------------------------------
-- Capture: merge
--------------------------------------------------------------------------------

T.Case("Capture.Merge: added, then updated, keeping what an earlier read learned", function()
    local store = {}
    T.Eq(Capture.Merge(store, { kind = "instance", id = 3201, name = "Onyxia's Lair", type = "raid", size = 40 }, 10), "added", "new")
    T.Eq(Capture.Merge(store, { kind = "instance", id = 3201, type = "raid" }, 20), "updated", "again")
    local entry = store.instances[3201]
    T.Eq(entry.name, "Onyxia's Lair", "a nameless read does not wipe the name")
    T.Eq(entry.size, 40, "nor the size")
    T.Eq(entry.first, 10, "first seen")
    T.Eq(entry.seen, 20, "last seen")
    T.Eq(entry.count, 2, "seen twice")
    T.Eq(store.hidden, 0, "the store was given its fields")
    T.Eq(type(store.npcs), "table", "all of them")
end)

T.Case("Capture.Merge: a secret read is counted, never stored", function()
    local store = { instances = {}, encounters = {}, npcs = {}, auras = {}, hidden = 0 }
    T.Eq(Capture.Merge(store, { kind = "npc", secret = true }, 1), "hidden", "secret")
    T.Eq(Capture.Merge(store, { kind = "npc", id = 5, instance = 2999 }, 1), "hidden", "an id without a name")
    T.Eq(Capture.Merge(store, { kind = "npc", name = "Ghoul", instance = 2999 }, 1), "hidden", "a name without an id")
    T.Eq(store.hidden, 3, "three counted")
    T.Eq(Count(store.npcs), 0, "nothing stored")
    T.Eq(Capture.Merge(store, { kind = "npc", id = 250660, name = "The Baron", instance = 2999,
        creature = "Undead", classification = "elite" }, 2), "added", "a readable one is kept")
    local npc = store.npcs["2999:250660"]
    T.Eq(npc.name, "The Baron", "by instance and id")
    T.Eq(npc.creature, "Undead", "creature type")
    T.Eq(Capture.Merge(store, { kind = "npc", id = 250660, name = "The Baron" }, 3), "added",
        "the same npc in the open world is its own entry")
    T.True(store.npcs["0:250660"] ~= nil, "under instance 0")
end)

T.Case("Capture.Merge: encounters count pulls, kills and wipes", function()
    local store = {}
    Capture.Merge(store, { kind = "encounter", id = 3354, name = "Rath'mael", instance = 2999, result = "start" }, 1)
    Capture.Merge(store, { kind = "encounter", id = 3354, instance = 2999, result = "wipe" }, 2)
    Capture.Merge(store, { kind = "encounter", id = 3354, result = "start" }, 3)
    Capture.Merge(store, { kind = "encounter", id = 3354, instance = 0, result = "kill" }, 4)
    local enc = store.encounters[3354]
    T.Eq(enc.pulls, 2, "two pulls")
    T.Eq(enc.wipes, 1, "one wipe")
    T.Eq(enc.kills, 1, "one kill")
    T.Eq(enc.name, "Rath'mael", "the name from the first read")
    T.Eq(enc.instance, 2999, "instance 0 never overwrites a real one")
    T.Eq(Capture.Merge(store, { kind = "encounter", result = "start" }, 5), nil, "no id, refused")
end)

T.Case("Capture.Merge: refuses what it cannot use", function()
    local store = {}
    local ok, why = Capture.Merge(store, { kind = "combatlog", id = 1 }, 1)
    T.Eq(ok, nil, "unknown kind")
    T.True(why:find("unknown kind", 1, true), "with a reason")
    T.Eq(Capture.Merge(store, { kind = "instance", id = 0 }, 1), nil, "instance 0 is the open world")
    T.Eq(Capture.Merge(store, { kind = "aura", id = "x" }, 1), nil, "a spell id is a number")
    T.Eq(Capture.Merge(nil, { kind = "aura", id = 1 }, 1), nil, "no store")
    T.Eq(Capture.Merge(store, nil, 1), nil, "no observation")
    T.Eq(Capture.Merge(store, { kind = "aura", id = 1248688, name = "Well Fed", source = "aura" }, 1), "added", "an aura")
    T.Eq(Capture.Merge(store, { kind = "aura", id = 1288849, source = "cast" }, 1), "added", "a cast")
    T.Eq(store.auras[1288849].source, "cast", "its source")
end)

T.Case("Capture.Merge: past the cap the entry seen longest ago goes", function()
    local saved = Capture.CAPS.npcs
    local ok, err = pcall(function()
        Capture.CAPS.npcs = 3
        local store = {}
        Capture.Merge(store, { kind = "npc", id = 1, name = "A", instance = 9 }, 100)
        Capture.Merge(store, { kind = "npc", id = 2, name = "B", instance = 9 }, 50)
        Capture.Merge(store, { kind = "npc", id = 3, name = "C", instance = 9 }, 200)
        Capture.Merge(store, { kind = "npc", id = 1, name = "A", instance = 9 }, 300)
        T.Eq(Count(store.npcs), 3, "at the cap")
        T.Eq(Capture.Merge(store, { kind = "npc", id = 4, name = "D", instance = 9 }, 400), "added", "one more")
        T.Eq(Count(store.npcs), 3, "still at the cap")
        T.Eq(store.npcs["9:2"], nil, "B, seen at 50, went")
        T.True(store.npcs["9:1"] ~= nil, "A was seen again, so it stayed")
        T.True(store.npcs["9:4"] ~= nil, "the new one is in")
    end)
    Capture.CAPS.npcs = saved
    if not ok then error(err, 0) end
    T.Eq(Capture.CAPS.npcs, 2000, "the spec's caps")
    T.Eq(Capture.CAPS.encounters, 200, "encounters")
    T.Eq(Capture.CAPS.auras, 500, "auras")
end)

T.Case("Capture.Clear: empties every kind and the hidden count", function()
    local store = {}
    Capture.Merge(store, { kind = "npc", secret = true }, 1)
    Capture.Merge(store, { kind = "aura", id = 1, name = "x" }, 1)
    local same = Capture.Clear(store)
    T.Eq(same, store, "the same table")
    T.Eq(store.hidden, 0, "hidden")
    T.Eq(Count(store.auras), 0, "auras")
end)

--------------------------------------------------------------------------------
-- Capture: show, export, read
--------------------------------------------------------------------------------

local function Filled()
    local store = {}
    Capture.Merge(store, { kind = "instance", id = 2999, name = "Ruins of Lordaeron", type = "party",
        difficulty = 1, difficultyName = "Normal", size = 5 }, 10)
    Capture.Merge(store, { kind = "encounter", id = 3354, name = "Rath'mael", instance = 2999, size = 5 }, 11)
    Capture.Merge(store, { kind = "npc", id = 250660, name = "The \"Baron\"", instance = 2999, creature = "Undead" }, 12)
    Capture.Merge(store, { kind = "npc", id = 1, name = "Wolf", instance = 0 }, 13)
    Capture.Merge(store, { kind = "npc", secret = true }, 14)
    Capture.Merge(store, { kind = "aura", id = 1248688, name = "Well Fed", source = "aura" }, 15)
    return store
end

T.Case("Capture.Summary: counts, hidden sightings and a line per instance", function()
    local lines = Capture.Summary(Filled(), function(id) return id == 5 and "Five" or nil end)
    T.True(lines[1]:find("1 instances, 1 encounters, 2 mobs, 1 auras", 1, true), "totals")
    T.True(lines[2]:find("1 sightings had their names hidden", 1, true), "hidden")
    T.True(lines[3]:find("open world", 1, true), "the open world first, by id")
    T.True(lines[4]:find("Ruins of Lordaeron (5), id 2999: 1 mobs, 1 encounters", 1, true), "the dungeon")
    local empty = Capture.Summary({})
    T.Eq(#empty, 1, "an empty store is one line")
end)

T.Case("Capture.Export and Read: round-trips, same text twice", function()
    local store = Filled()
    local text = Capture.Export(store, { version = "0.1.0", build = "70124", now = 99 })
    T.True(type(text) == "string" and not text:find("\n", 1, true), "one line of JSON")
    T.Eq(Capture.Export(store, { version = "0.1.0", build = "70124", now = 99 }), text, "deterministic")
    local doc, why = Capture.Read(text)
    T.True(doc ~= nil, "reads back: " .. tostring(why))
    T.Eq(doc.formatVersion, 1, "format")
    T.Eq(doc.addon, "0.1.0", "addon version")
    T.Eq(doc.build, "70124", "build")
    T.Eq(doc.exported, 99, "time")
    T.Eq(doc.hidden, 1, "hidden count")
    T.Eq(doc.skipped, 0, "nothing skipped")
    T.Eq(#doc.instances, 1, "instances")
    T.Eq(doc.instances[1].difficultyName, "Normal", "difficulty name")
    T.Eq(#doc.npcs, 2, "npcs")
    T.Eq(doc.npcs[1].instance, 0, "open world first")
    T.Eq(doc.npcs[2].name, "The \"Baron\"", "quotes survive")
    T.Eq(doc.npcs[2].count, 1, "counts")
    T.Eq(doc.encounters[1].pulls, 1, "pulls")
    T.Eq(doc.auras[1].id, 1248688, "auras")
    for _, kind in ipairs({ "instances", "encounters", "npcs", "auras" }) do
        for _, row in ipairs(doc[kind]) do
            local key = kind == "npcs" and (row.instance .. ":" .. row.id) or row.id
            local entry = store[kind][key]
            for field, value in pairs(row) do
                T.Eq(value, entry[field], kind .. " " .. tostring(key) .. " " .. field)
            end
        end
    end
end)

T.Case("Capture.Read: refuses other JSON, a newer format and garbage; skips bad rows", function()
    T.Eq(Capture.Read(""), nil, "empty")
    T.Eq(Capture.Read(nil), nil, "nil")
    T.Eq(Capture.Read("{not json"), nil, "garbage")
    local _, why = Capture.Read('{"formatVersion":2,"rules":[]}')
    T.True(why:find("not a Marked For Death capture", 1, true), "another file")
    _, why = Capture.Read('{"format":"mfd-capture","formatVersion":2}')
    T.True(why:find("newer", 1, true), "a newer format")
    T.Eq(Capture.Read('{"format":"mfd-capture"}'), nil, "no version")
    local doc = Capture.Read('{"format":"mfd-capture","formatVersion":1,"npcs":['
        .. '{"id":5,"name":"Ok","instance":9},{"id":"x","name":"Bad"},{"id":6},{"id":7.5,"name":"Half"}],'
        .. '"auras":"not a list"}')
    T.Eq(#doc.npcs, 1, "one good npc")
    T.Eq(doc.skipped, 3, "three skipped")
    T.Eq(#doc.auras, 0, "a kind that is not a list reads as empty")
    T.Eq(#doc.instances, 0, "a missing kind is empty")
end)
