local addonName, ns = ...

--[[
Tests_Model: the model lane's cases (Data_CC, Seats, Rules, Allocator, MarkPlan, Debug,
Log). Owned by lane A (model). Every case builds its own tables; none touches the saved
ones. Registered on ns.Tests; Tests.lua runs them all.

Three Anniversary bugs have cases of their own here, so they cannot come back:
    unit tokens are aliases, not identities     (MarkPlan.Hint, MarkPlan.Actionable)
    an icon belongs to its seat                 (Allocator: icon read off the seat)
    a reserved icon is never lent to a kill     (Allocator: lend)
]]

local T = ns.Tests
local CC, Seats, Rules, Allocator, MarkPlan, Debug, Log =
    ns.CC, ns.Seats, ns.Rules, ns.Allocator, ns.MarkPlan, ns.DebugWhy, ns.Log
local Util = LibStub("LibICUtil-1.0")

local SKULL, CROSS, SQUARE, CIRCLE, MOON, STAR, TRIANGLE, DIAMOND = 8, 7, 6, 2, 5, 1, 4, 3

local function Plan()
    return Util.DeepCopy(ns.Schema.DEFAULT_PLAN)
end

local function Member(name, class, online)
    return { name = name, class = class, online = online }
end

-- A rule set from a list of { name, intent, rank, extra fields }.
local function Set(list)
    local set = {}
    for i, row in ipairs(list) do
        local fields = { name = row[1], intent = row[2] or "KILL", rank = row[3] or i * 10 }
        for k, v in pairs(row[4] or {}) do fields[k] = v end
        local rule = assert(Rules.New(fields))
        set[Rules.Key(rule)] = rule
    end
    return set
end

-- Sighted candidates: { { key, name, npcID }, ... } with a guid per key.
local function Mobs(list)
    local out = {}
    for i, row in ipairs(list) do
        out[i] = { key = row[1], guid = row[1], name = row[2], npcID = row[3], lost = row.lost }
    end
    return out
end

local function Alloc(set, candidates, roster, opts)
    opts = opts or {}
    local seats = Seats.Resolve(opts.plan or Plan(), roster or {})
    return Allocator.Compute({
        candidates = candidates, rules = Rules.Resolve(set, candidates), seats = seats,
        lend = opts.lend, held = opts.held,
    }), seats
end

--------------------------------------------------------------------------------
-- Data_CC
--------------------------------------------------------------------------------

T.Case("CC: every job is defined, has a class list where it needs one, and an id once", function()
    local seenSpell = {}
    for _, intent in ipairs(CC.ORDER) do
        local def = CC.INTENTS[intent]
        T.True(def and def.label, intent .. " is defined with a label")
        if def.classes then
            T.True(#def.classes > 0, intent .. " names at least one class")
        end
        for _, id in ipairs(def.spells or {}) do
            T.Eq(seenSpell[id], nil, "spell " .. id .. " belongs to one job")
            seenSpell[id] = intent
            T.Eq(CC.IntentForSpell(id), intent, "spell " .. id .. " reads back as " .. intent)
        end
    end
    T.Eq(CC.NeedsOwner("KILL"), false, "kill needs no owner")
    T.Eq(CC.NeedsOwner("IGNORE"), false, "never mark needs no owner")
    T.Eq(CC.NeedsOwner("SHEEP"), true, "sheep needs a mage")
    T.Eq(CC.IntentForSpell(118), "SHEEP", "Polymorph rank 1")
    T.Eq(CC.IntentForSpell(9484), "SHACKLE", "Shackle Undead rank 1")
    T.Eq(CC.IntentForSpell(1), nil, "an unknown id is nil")
end)

T.Case("CC: REPENTANCE is hidden from the picker even when a seat holds it", function()
    T.Eq(CC.INTENTS.REPENTANCE.hidden, true, "flagged hidden")
    T.Eq(CC.IsKnown("REPENTANCE"), true, "but still known, so an old rule still reads")
    local plan = Plan()
    plan[DIAMOND] = { intent = "REPENTANCE", ordinal = 1 }
    local picks = table.concat(CC.Pickable(plan), ",")
    T.Eq(picks, "KILL,SHEEP,BANISH,IGNORE", "seated jobs in order, IGNORE always, no REPENTANCE")
    T.Eq(table.concat(CC.Pickable({}), ","), "IGNORE", "an empty plan still offers never mark")
end)

T.Case("CC: classes and creature types", function()
    T.True(CC.CanClass("FEAR", "WARLOCK"), "warlock fears")
    T.True(CC.CanClass("FEAR", "PRIEST"), "priest fears")
    T.Eq(CC.CanClass("SHEEP", "PRIEST"), false, "priest cannot sheep")
    T.Eq(CC.CanClass("KILL", "MAGE"), false, "kill has no class list")
    T.Eq(CC.CanClass("SHEEP", nil), false, "an unknown class can do nothing")
    T.Eq(CC.CanClass("NOPE", "MAGE"), false, "an unknown job")

    T.Eq(CC.CanApply("SHACKLE", "Undead"), true, "shackle undead")
    local ok, why = CC.CanApply("SHACKLE", "Humanoid")
    T.Eq(ok, false, "not a humanoid")
    T.True(why:find("Shackle", 1, true), "the reason names the job")
    T.Eq(CC.CanApply("SHEEP", "Elementar"), true, "a localised type fails open")
    T.Eq(CC.CanApply("SHEEP", nil), true, "a hidden type fails open")
    T.Eq(CC.CanApply("KILL", "Demon"), true, "kill works on anything")
end)

--------------------------------------------------------------------------------
-- Seats
--------------------------------------------------------------------------------

T.Case("Seats.Resolve: kill seats always owned, CC seats need a capable player", function()
    local seats = Seats.Resolve(Plan(), {})
    T.Eq(seats.byIcon[SKULL].owner, true, "Skull needs nobody")
    T.Eq(seats.byIcon[MOON].owner, false, "no mage: Moon exists but cannot be used")
    T.Eq(seats.seats[1].icon, SKULL, "Skull is the first seat")
    T.Eq(seats.seats[2].icon, CROSS, "then Cross")
    T.Eq(seats.seats[4].icon, CIRCLE, "Circle is Kill 4")
    T.Eq(#seats.seats, 8, "eight seats")
    T.Eq(Seats.Label(seats.byIcon[MOON]), "Sheep 1", "label")
end)

T.Case("Seats.Resolve: name-ascending owners, pins honoured first", function()
    local roster = { Member("Zed", "MAGE"), Member("Abe", "MAGE"), Member("Mia", "MAGE") }
    local seats = Seats.Resolve(Plan(), roster)
    T.Eq(seats.byIcon[MOON].owner, "Abe", "Sheep 1 to the first mage by name")
    T.Eq(seats.byIcon[STAR].owner, "Mia", "Sheep 2 to the next")

    local plan = Plan()
    plan[STAR].pin = "Zed"
    seats = Seats.Resolve(plan, roster)
    T.Eq(seats.byIcon[STAR].owner, "Zed", "the pinned seat goes to its pin")
    T.Eq(seats.byIcon[STAR].pinState, "held", "pin held")
    T.Eq(seats.byIcon[MOON].owner, "Abe", "the rest fill by name")

    plan[MOON].pin = "Zed"
    seats = Seats.Resolve(plan, roster)
    T.Eq(seats.byIcon[MOON].owner, "Zed", "Sheep 1 comes first, so its pin wins")
    T.Eq(seats.byIcon[STAR].pinState, "taken", "the same player cannot hold Sheep 2 too")
    T.Eq(seats.byIcon[STAR].owner, "Abe", "Sheep 2 fills from the roster")
end)

T.Case("Seats.Resolve: pin offline, absent or the wrong class falls back to the roster", function()
    local plan = Plan()
    plan[MOON].pin = "Gone"
    local seats = Seats.Resolve(plan, { Member("Gone", "MAGE", false), Member("Bea", "MAGE") })
    T.Eq(seats.byIcon[MOON].pinState, "offline", "pin offline")
    T.Eq(seats.byIcon[MOON].owner, "Bea", "the seat goes to someone present")
    T.Eq(seats.byIcon[STAR].owner, false, "and the offline mage owns nothing")

    seats = Seats.Resolve(plan, { Member("Bea", "MAGE") })
    T.Eq(seats.byIcon[MOON].pinState, "absent", "pin not in the group")
    T.Eq(seats.byIcon[MOON].owner, "Bea", "filled")

    seats = Seats.Resolve(plan, { Member("Gone", "PRIEST"), Member("Bea", "MAGE") })
    T.Eq(seats.byIcon[MOON].pinState, "wrong class", "a priest cannot hold a sheep seat")
    T.Eq(seats.byIcon[MOON].owner, "Bea", "filled")

    seats = Seats.Resolve(Plan(), { Member("Who", "MAGE", nil) })
    T.Eq(seats.byIcon[MOON].owner, "Who", "online unknown counts as present")
    seats = Seats.Resolve(Plan(), { { name = "Hid", class = nil } })
    T.Eq(seats.byIcon[MOON].owner, false, "a class that came back secret can do nothing")
end)

T.Case("Seats.Resolve: one warlock holds banish and fear; zero capable class", function()
    local plan = Plan()
    plan[DIAMOND] = { intent = "FEAR", ordinal = 1 }
    local seats = Seats.Resolve(plan, { Member("Lock", "WARLOCK"), Member("Rog", "ROGUE") })
    T.Eq(seats.byIcon[TRIANGLE].owner, "Lock", "Banish 1")
    T.Eq(seats.byIcon[DIAMOND].owner, "Lock", "and Fear 1, a different job")
    T.Eq(seats.byIcon[MOON].owner, false, "no mage at all")
end)

T.Case("Seats.Validate: icons 1 to 8, a job a seat can carry, each seat once", function()
    T.Eq(Seats.Validate(Plan()), true, "the default plan")
    local plan = Plan()
    plan[9] = { intent = "KILL", ordinal = 5 }
    T.Eq(Seats.Validate(plan), nil, "icon 9")
    plan = Plan()
    plan[STAR] = { intent = "KILL", ordinal = 1 }
    local ok, why = Seats.Validate(plan)
    T.Eq(ok, nil, "two Kill 1 seats")
    T.True(why:find("Kill 1", 1, true), "named")
    plan = Plan()
    plan[STAR] = { intent = "IGNORE", ordinal = 1 }
    T.Eq(Seats.Validate(plan), nil, "never mark is not a seat")
end)

T.Case("Seats.PlanFor/Detach/Reattach: an instance follows default until its first edit", function()
    local db = { plans = { default = Plan() } }
    local plan, own = Seats.PlanFor(db, "i:33")
    T.Eq(plan, db.plans.default, "follows default")
    T.Eq(own, false, "not its own")
    local mine = Seats.Detach(db, "i:33")
    T.True(mine ~= db.plans.default, "a copy")
    mine[MOON].pin = "Me"
    T.Eq(db.plans.default[MOON].pin, nil, "editing the copy leaves default alone")
    T.Eq(select(2, Seats.PlanFor(db, "i:33")), true, "now its own")
    T.Eq(Seats.Detach(db, "i:33"), mine, "a second detach keeps the edit")
    Seats.Reattach(db, "i:33")
    T.Eq(Seats.PlanFor(db, "i:33"), db.plans.default, "back on default")
    Seats.Reattach(db, "default")
    T.True(db.plans.default ~= nil, "default is never dropped")
end)

--------------------------------------------------------------------------------
-- Rules
--------------------------------------------------------------------------------

T.Case("Rules: instance keys and rule keys, by name and by id", function()
    T.Eq(Rules.InstanceKey("raid", 409), "i:409", "an instance")
    T.Eq(Rules.InstanceKey("none", 0), "open", "the open world")
    T.Eq(Rules.InstanceKey(nil, nil), "open", "nothing known")
    T.Eq(Rules.IsInstanceKey("legacy:Karazhan"), true, "legacy")
    T.Eq(Rules.IsInstanceKey("Karazhan"), false, "a bare zone name")
    T.Eq(Rules.Key({ name = "Scarlet Monk", npcID = 4540 }), "n:Scarlet Monk", "name first")
    T.Eq(Rules.Key({ npcID = 4540 }), "id:4540", "id when no name")
    T.Eq(Rules.Key({}), nil, "neither")
end)

T.Case("Rules.CheckName: quotes, semicolons and brackets refused; apostrophes fine", function()
    T.Eq(Rules.CheckName("  Kel'Thuzad  "), "Kel'Thuzad", "trimmed, apostrophe kept")
    T.Eq(Rules.CheckName('Bad "Name"'), nil, "a double quote")
    T.Eq(Rules.CheckName("A; /tm 8"), nil, "a semicolon")
    T.Eq(Rules.CheckName("[@player] x"), nil, "a bracket")
    T.Eq(Rules.CheckName("a|cffname"), nil, "a pipe")
    T.Eq(Rules.CheckName("two\nlines"), nil, "a line break")
    T.Eq(Rules.CheckName("   "), nil, "empty")
    T.Eq(Rules.CheckName(string.rep("x", 65)), nil, "too long")
end)

T.Case("Rules.New: jobs and fallbacks checked", function()
    local rule = Rules.New({ name = "Mob" })
    T.Eq(rule.intent, "KILL", "kill by default")
    T.Eq(rule.rank, 10, "first rank")
    T.Eq(Rules.New({ name = "Mob", intent = "DANCE" }), nil, "unknown job")
    T.Eq(Rules.New({ name = "Mob", fallback = "IGNORE" }), nil, "never mark is no fallback")
    T.Eq(Rules.New({ name = "Mob", intent = "SHEEP", fallback = "SHEEP" }).fallback, nil,
        "a fallback equal to the job is dropped")
    T.Eq(Rules.New({ name = "Mob", maxCount = 0 }), nil, "max count from 1")
    T.Eq(Rules.New({ npcID = 1.5 }), nil, "a whole npc id")
    T.Eq(Rules.New({}), nil, "names nothing")
end)

T.Case("Rules.Match: id before name, names case-blind, blind matches nothing", function()
    local set = Set({ { "Scarlet Monk", "KILL", 30 }, { "Other", "SHEEP", 10, { npcID = 4540 } } })
    local rule, key = Rules.Match(set, { npcID = 4540, name = "Scarlet Monk" })
    T.Eq(rule.intent, "SHEEP", "the id rule wins for that mob")
    T.Eq(key, "n:Other", "its key")
    T.Eq(Rules.Match(set, { name = "scarlet monk" }).intent, "KILL", "a name rule, case-blind")
    T.Eq(Rules.Match(set, { npcID = 1 }), nil, "no rule")
    T.Eq(Rules.Match(set, {}), nil, "names hidden, id hidden: nothing")
    local resolved = Rules.Resolve(set, { { key = "g1", name = "Scarlet Monk" }, { key = "g2", name = "Nope" } })
    T.Eq(resolved.g1.intent, "KILL", "resolved by candidate key")
    T.Eq(resolved.g2, nil, "unruled mob left out")
end)

T.Case("Rules.Ranked: rank, then key, so a tie is the same everywhere", function()
    local set = Set({ { "Bee", "KILL", 20 }, { "Ant", "KILL", 20 }, { "Cat", "KILL", 10 } })
    local list = Rules.Ranked(set)
    T.Eq(list[1].name .. list[2].name .. list[3].name, "CatAntBee", "rank then key")
    Rules.Renumber(list)
    T.Eq(list[3].rank, 30, "renumbered by tens")
end)

T.Case("Rules.Merge: mine wins, theirs fills gaps", function()
    local mine = Set({ { "Monk", "KILL", 10 }, { "Mage", "SHEEP", 20, { npcID = 99 } } })
    local theirs = Set({ { "Monk", "SHEEP", 5 }, { "monk", "SHEEP", 5 }, { "Caster", "KILL", 30, { npcID = 99 } },
        { "Priest", "SHACKLE", 40 } })
    local merged, added = Rules.Merge(mine, theirs, "Ally")
    T.Eq(added, 1, "only Priest is new")
    T.Eq(merged["n:Monk"].intent, "KILL", "my Monk kept")
    T.Eq(merged["n:monk"], nil, "their monk is the same mob by name")
    T.Eq(merged["n:Caster"], nil, "their Caster is my npc 99")
    T.Eq(merged["n:Priest"].from, "Ally", "what came in says who from")
    T.Eq(mine["n:Priest"], nil, "mine is not changed")
end)

T.Case("Rules.ParseBulk: names, ids, jobs; one bad line refuses all", function()
    local rules = Rules.ParseBulk("-- pack 1\nScarlet Sorcerer = sheep\n\nScarlet Monk\n4294 = banish\n# done\n")
    T.Eq(#rules, 3, "three rules")
    T.Eq(rules[1].intent, "SHEEP", "job read")
    T.Eq(rules[2].rank, 20, "ranked by line")
    T.Eq(rules[3].npcID, 4294, "an id line")
    T.Eq(rules[3].name, nil, "with no name")
    local _, why = Rules.ParseBulk("Monk\nMage = dance")
    T.True(why:find("line 2", 1, true), "unknown job names its line")
    T.Eq(Rules.ParseBulk("Monk\nmonk"), nil, "a duplicate")
    T.Eq(Rules.ParseBulk('Bad "quote"'), nil, "a quote in a name")
    T.Eq(Rules.ParseBulk("\n-- only a comment\n"), nil, "nothing to import")
end)

T.Case("Rules share v2: round trip keeps keys and fields", function()
    local byInstance = {
        ["i:409"] = Set({ { "Flamewaker", "KILL", 10, { maxCount = 2 } }, { "Lava Surger", "BANISH", 20, { fallback = "KILL" } } }),
        open = Set({ { "Wolf", "KILL", 10, { npcID = 525 } } }),
    }
    local text = assert(Rules.ToJSON(byInstance, { note = "test" }))
    T.True(text:find('"formatVersion": 2', 1, true), "version 2")
    local back, version = Rules.FromJSON(text)
    T.Eq(version, 2, "read as v2")
    T.Eq(back["i:409"]["n:Flamewaker"].maxCount, 2, "max count")
    T.Eq(back["i:409"]["n:Lava Surger"].fallback, "KILL", "fallback")
    T.Eq(back["i:409"]["n:Lava Surger"].rank, 20, "priority")
    T.Eq(back.open["n:Wolf"].npcID, 525, "npc id")
end)

T.Case("Rules share: an Anniversary v1 file imports under legacy keys", function()
    local v1 = '{"addon":"MarkedForDeath","formatVersion":1,"rules":{"Karazhan":['
        .. '{"npc":15547,"job":"sheep","priority":10},{"name":"Phantom Guest","job":"KILL"}]}}'
    local back, version = Rules.FromJSON(v1)
    T.Eq(version, 1, "read as v1")
    local set = back["legacy:Karazhan"]
    T.True(set ~= nil, "the zone name becomes a legacy key")
    T.Eq(set["id:15547"].intent, "SHEEP", "by id")
    T.Eq(set["n:Phantom Guest"].rank, 20, "a missing priority is its place")
end)

T.Case("Rules share: newer, unknown job, not ours, bad key and bad name refused whole", function()
    local function Doc(version, key, entry)
        return '{"addon":"MarkedForDeath","formatVersion":' .. version .. ',"rules":{"' .. key .. '":[' .. entry .. ']}}'
    end
    local _, why = Rules.FromJSON(Doc(3, "open", '{"name":"A","job":"KILL"}'))
    T.True(why:find("newer", 1, true), "a newer file")
    _, why = Rules.FromJSON(Doc(2, "open", '{"name":"A","job":"KILL"},{"name":"B","job":"DANCE"}'))
    T.True(why:find("unknown job", 1, true), "one unknown job refuses the file")
    T.Eq(Rules.FromJSON('{"addon":"Other","formatVersion":1,"rules":{}}'), nil, "another addon's file")
    T.Eq(Rules.FromJSON("not json"), nil, "not JSON")
    T.Eq(Rules.FromJSON(Doc(2, "Karazhan", '{"name":"A","job":"KILL"}')), nil, "a v2 key that is no instance key")
    T.Eq(Rules.FromJSON(Doc(2, "open", '{"name":"A;B","job":"KILL"}')), nil, "a name a macro cannot hold")
    T.Eq(Rules.FromJSON(Doc(2, "open", '{"name":"A","job":"KILL"},{"name":"A","job":"SHEEP"}')), nil, "two rules for one mob")
end)

--------------------------------------------------------------------------------
-- Allocator
--------------------------------------------------------------------------------

T.Case("Allocator: three copies of one mob take three kill seats in order", function()
    local alloc = Alloc(Set({ { "Monk" } }), Mobs({ { "g3", "Monk" }, { "g1", "Monk" }, { "g2", "Monk" } }))
    T.Eq(alloc.byKey.g1.icon, SKULL, "first key Skull")
    T.Eq(alloc.byKey.g2.icon, CROSS, "then Cross")
    T.Eq(alloc.byKey.g3.icon, SQUARE, "then Square")
end)

T.Case("Allocator: more mobs than kill seats; maxCount; rank tie by key", function()
    local mobs = Mobs({ { "a", "Monk" }, { "b", "Monk" }, { "c", "Monk" }, { "d", "Monk" }, { "e", "Monk" } })
    local alloc = Alloc(Set({ { "Monk" } }), mobs)
    T.Eq(#alloc.list, 4, "four kill seats, the fifth mob waits")
    T.Eq(alloc.byKey.e, nil, "the last key gets nothing")

    alloc = Alloc(Set({ { "Monk", "KILL", 10, { maxCount = 2 } } }), mobs)
    T.Eq(#alloc.list, 2, "max count 2")

    alloc = Alloc(Set({ { "Bee", "KILL", 10 }, { "Ant", "KILL", 10 } }), Mobs({ { "g2", "Bee" }, { "g1", "Ant" } }))
    T.Eq(alloc.byKey.g1.icon, SKULL, "same rank: lower key first")
end)

T.Case("Allocator: an icon belongs to its seat, whatever the plan binds it to", function()
    local plan = Plan()
    plan[MOON], plan[SKULL] = { intent = "KILL", ordinal = 1 }, { intent = "SHEEP", ordinal = 1 }
    local set = Set({ { "Monk", "KILL", 10 }, { "Mage", "SHEEP", 20 } })
    local alloc, seats = Alloc(set, Mobs({ { "g1", "Monk" }, { "g2", "Mage" } }), { Member("Ice", "MAGE") }, { plan = plan })
    T.Eq(alloc.byKey.g1.icon, MOON, "Kill 1 is Moon in this plan")
    T.Eq(alloc.byKey.g2.icon, SKULL, "Sheep 1 is Skull")
    T.Eq(alloc.byKey.g2.owner, "Ice", "owned by the mage")
    for _, entry in ipairs(alloc.list) do
        T.Eq(seats.byIcon[entry.icon], entry.seat, "the icon is the seat's own")
        T.Eq(plan[entry.icon].intent, entry.intent, "and the seat's job")
    end
end)

T.Case("Allocator: fallback when nobody can do the job; unmet reported", function()
    local set = Set({ { "Mage", "SHEEP", 10, { fallback = "KILL" } }, { "Priest", "SHEEP", 20 } })
    local alloc = Alloc(set, Mobs({ { "g1", "Mage" }, { "g2", "Priest" } }), {})
    T.Eq(alloc.byKey.g1.icon, SKULL, "no mage: falls back to Kill 1")
    T.Eq(alloc.byKey.g1.intent, "KILL", "reported as kill")
    T.Eq(alloc.byKey.g2, nil, "no fallback: nothing")
    T.Eq(#alloc.unmet, 2, "both sheep calls unmet")
    T.Eq(alloc.unmet[1].key, "g1", "by key")
end)

T.Case("Allocator: spare icons lent to kills, but a reserved icon never", function()
    local mobs = Mobs({ { "a", "Monk" }, { "b", "Monk" }, { "c", "Monk" }, { "d", "Monk" }, { "e", "Monk" }, { "f", "Monk" } })
    local set = Set({ { "Monk" } })
    local alloc = Alloc(set, mobs, {}, { lend = true })
    T.Eq(#alloc.list, 6, "four kill seats and two lent")
    T.Eq(alloc.byKey.e.borrowed, true, "lent")
    T.Eq(alloc.byKey.e.intent, "KILL", "lent icons carry no crowd control meaning")
    T.Eq(alloc.byKey.e.icon, MOON, "Sheep 1 is lent first (lowest seat number, then higher icon)")

    local plan = Plan()
    for _, icon in ipairs({ MOON, STAR, TRIANGLE, DIAMOND }) do plan[icon].reserved = true end
    alloc = Alloc(set, mobs, {}, { lend = true, plan = plan })
    T.Eq(#alloc.list, 4, "nothing reserved is lent")
    for _, entry in ipairs(alloc.list) do
        T.True(entry.icon ~= MOON and entry.icon ~= STAR and entry.icon ~= TRIANGLE and entry.icon ~= DIAMOND,
            "a reserved icon stays off kill targets")
    end

    plan = Plan()
    plan[MOON].reserved = true
    alloc = Alloc(Set({ { "Monk", "KILL", 10 }, { "Mage", "SHEEP", 20 } }),
        Mobs({ { "a", "Monk" }, { "m", "Mage" } }), { Member("Ice", "MAGE") }, { lend = true, plan = plan })
    T.Eq(alloc.byKey.m.icon, MOON, "a reserved seat still serves its own job")
end)

T.Case("Allocator: a lent icon never takes Moon from a mob about to be sheeped", function()
    local set = Set({ { "Monk", "KILL", 10 }, { "Mage", "SHEEP", 90 } })
    local mobs = Mobs({ { "a", "Monk" }, { "b", "Monk" }, { "c", "Monk" }, { "d", "Monk" }, { "e", "Monk" }, { "m", "Mage" } })
    local alloc = Alloc(set, mobs, { Member("Ice", "MAGE") }, { lend = true })
    T.Eq(alloc.byKey.m.icon, MOON, "the sheep keeps Moon though it ranks last")
    T.Eq(alloc.byKey.e.icon, TRIANGLE, "a spare seat 1 (Triangle) is lent instead")
end)

T.Case("Allocator: held icons stay; a lost mob ranks after the pack; order-free", function()
    local set = Set({ { "Monk" } })
    local alloc = Alloc(set, Mobs({ { "a", "Monk" }, { "b", "Monk" } }), {}, { held = { b = SKULL } })
    T.Eq(alloc.byKey.b.icon, SKULL, "the hand mark is kept")
    T.Eq(alloc.byKey.b.held, true, "and says so")
    T.Eq(alloc.byKey.a.icon, CROSS, "the next mob gets the next seat")

    alloc = Alloc(set, Mobs({ { "a", "Monk", lost = true }, { "b", "Monk" } }))
    T.Eq(alloc.byKey.b.icon, SKULL, "the mob in sight takes Skull")

    local mobs = Mobs({ { "c", "Monk" }, { "a", "Monk" }, { "b", "Monk" } })
    local one = Alloc(set, mobs)
    local reversed = { mobs[3], mobs[2], mobs[1] }
    local two = Alloc(set, reversed)
    for _, key in ipairs({ "a", "b", "c" }) do
        T.Eq(one.byKey[key].icon, two.byKey[key].icon, key .. " gets the same icon whatever the order")
    end
end)

T.Case("Allocator: IGNORE never marked; unruled mobs left alone", function()
    local alloc = Alloc(Set({ { "Critter", "IGNORE" }, { "Monk" } }), Mobs({ { "a", "Critter" }, { "b", "Monk" }, { "c", "Nobody" } }), {}, { lend = true })
    T.Eq(alloc.byKey.a, nil, "never mark")
    T.Eq(alloc.byKey.c, nil, "no rule")
    T.Eq(alloc.byKey.b.icon, SKULL, "the ruled one")
end)

T.Case("Allocator.Blind: the rules stand in for the pack, id-only rules skipped", function()
    local set = Set({ { "Monk", "KILL", 20, { maxCount = 3 } }, { "Mage", "SHEEP", 10 }, { "Boss", "KILL", 5 } })
    set["id:77"] = assert(Rules.New({ npcID = 77, rank = 1 }))
    local seats = Seats.Resolve(Plan(), { Member("Ice", "MAGE") })
    local alloc = Allocator.Blind(set, seats)
    T.Eq(#alloc.list, 3, "one mob per named rule, max count moot")
    T.Eq(alloc.byKey["n:Boss"].icon, SKULL, "best rank Skull")
    T.Eq(alloc.byKey["n:Monk"].icon, CROSS, "then Cross")
    T.Eq(alloc.byKey["n:Mage"].icon, MOON, "the sheep on Moon")
    T.Eq(alloc.skipped[1], "id:77", "the id-only rule has no name to target")
end)

--------------------------------------------------------------------------------
-- MarkPlan
--------------------------------------------------------------------------------

local function StepsFor(names, roster)
    local list = {}
    for i, name in ipairs(names) do list[i] = { name, "KILL", i * 10 } end
    local set = Set(list)
    return MarkPlan.Steps(Allocator.Blind(set, Seats.Resolve(Plan(), roster or {}), { lend = true }))
end

T.Case("MarkPlan.Steps: Skull first, then the kill seats, then crowd control", function()
    local set = Set({ { "Mage", "SHEEP", 5 }, { "Monk", "KILL", 10 }, { "Guard", "KILL", 20 } })
    local steps = MarkPlan.Steps(Allocator.Blind(set, Seats.Resolve(Plan(), { Member("Ice", "MAGE") })))
    T.Eq(steps[1].icon, SKULL, "Skull first though the sheep ranks higher")
    T.Eq(steps[1].name, "Monk", "on the best kill")
    T.Eq(steps[2].icon, CROSS, "Cross next")
    T.Eq(steps[3].icon, MOON, "then Moon")
    T.Eq(steps[3].seatLabel, "Sheep 1", "with its seat")
    T.Eq(steps[3].owner, "Ice", "and its owner")
end)

T.Case("MarkPlan.Build: exact text, cut on a whole pair, dropped listed", function()
    local steps = StepsFor({ "Scarlet Monk", "Scarlet Sorcerer" })
    local text, dropped = MarkPlan.Build(steps)
    T.Eq(text, "/targetexact Scarlet Monk\n/tm ~8\n/targetexact Scarlet Sorcerer\n/tm ~7\n/targetlasttarget", "the macro")
    T.Eq(#dropped, 0, "all fit")

    steps = StepsFor({ "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1", "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2", "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa3",
        "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa4", "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa5", "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa6" })
    text, dropped = MarkPlan.Build(steps, 255)
    T.True(#text <= 255, "within 255 bytes: " .. #text)
    T.Eq(#dropped, 2, "four pairs fit, two dropped")
    T.Eq(dropped[1].name, "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa5", "the dropped ones in order")
    T.True(text:sub(-17) == "/targetlasttarget", "still restores the target")
    T.Eq(select(2, text:gsub("/targetexact", "")), select(2, text:gsub("/tm ~", "")), "never half a pair")

    text, dropped = MarkPlan.Build(steps, 1023)
    T.Eq(#dropped, 0, "all six fit in 1023")
    T.Eq(MarkPlan.Build({}), "", "an empty plan is empty text")
    T.Eq(MarkPlan.Build(steps, 10), "", "nothing fits: empty, not a bare restore")
end)

T.Case("MarkPlan.Split: chained buttons, the click counted, restore at the end", function()
    local steps = StepsFor({ "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1", "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2", "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa3",
        "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa4", "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa5", "Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa6" })
    local pages, dropped = MarkPlan.Split(steps, 255, { "MFDMarkPack", "MFDMarkPack2" })
    T.Eq(#pages, 2, "two pages")
    T.Eq(#dropped, 0, "nothing dropped")
    T.True(pages[1]:sub(-19) == "/click MFDMarkPack2", "the first chains to the second")
    T.True(pages[2]:sub(-17) == "/targetlasttarget", "the last restores")
    T.True(#pages[1] <= 255 and #pages[2] <= 255, "each fits")

    pages = MarkPlan.Split(StepsFor({ "Monk" }), 255, { "MFDMarkPack", "MFDMarkPack2" })
    T.Eq(#pages, 1, "one page when it all fits")
    T.True(pages[1]:find("/click", 1, true) == nil, "no click to an empty page")

    pages, dropped = MarkPlan.Split(steps, 255, { "MFDMarkPack" })
    T.Eq(#pages, 1, "one button")
    T.Eq(#dropped, 2, "the rest dropped")
    T.Eq(#MarkPlan.Split({}, 255, { "A" }), 0, "an empty plan has no pages")
end)

T.Case("MarkPlan: clear and re-mark text", function()
    T.Eq(MarkPlan.ClearText(), "/tm 0", "clear the target")
    local text = MarkPlan.RemarkText(StepsFor({ "Monk" }), 255, "MFDClear")
    T.Eq(text, "/click MFDClear\n/targetexact Monk\n/tm ~8\n/targetlasttarget", "clear then mark")
    T.Eq(MarkPlan.RemarkText({}, 255, "MFDClear"), "/click MFDClear", "nothing to mark: just the clear")
end)

T.Case("MarkPlan: unit tokens are aliases, never identities", function()
    T.Eq(MarkPlan.Hint({ unit = "mouseover", guid = "G1" }), nil, "mouseover is never a hint")
    T.Eq(MarkPlan.Hint({ unit = "target", guid = "G1" }), nil, "nor target")
    T.Eq(MarkPlan.Hint({ unit = "party1target", guid = "G1" }), nil, "nor someone's target")
    T.Eq(MarkPlan.Hint({ unit = "nameplate3" }), nil, "a nameplate without a GUID to check")
    T.Eq(MarkPlan.Hint({ unit = "nameplate3", guid = "G1" }), "nameplate3", "a nameplate with its GUID")

    local alloc = Allocator.Compute({
        candidates = { { key = "G1", guid = "G1", name = "Monk", unit = "mouseover" },
                       { key = "G2", guid = "G2", name = "Monk", unit = "nameplate2" } },
        rules = { G1 = Rules.New({ name = "Monk" }), G2 = Rules.New({ name = "Monk" }) },
        seats = Seats.Resolve(Plan(), {}),
    })
    local steps = MarkPlan.Steps(alloc)
    T.Eq(steps[1].unit, nil, "the mouseover sighting carries no unit")
    T.Eq(steps[2].unit, "nameplate2", "the nameplate one does")

    local now = { nameplate2 = "G2" }
    local function guidOf(unit) return now[unit] end
    T.Eq(MarkPlan.Actionable(steps[2], guidOf), "nameplate2", "still that mob")
    now.nameplate2 = "G9"
    T.Eq(MarkPlan.Actionable(steps[2], guidOf), nil, "the plate was recycled: refused")
    T.Eq(MarkPlan.Actionable(steps[2], function() error("secret") end), nil, "a throwing read refused")
    T.Eq(MarkPlan.Actionable(steps[1], guidOf), nil, "no unit at all")
end)

T.Case("MarkPlan.IconFor: the Mark guide's answer for one unit", function()
    local steps = MarkPlan.Steps(Allocator.Compute({
        candidates = Mobs({ { "G1", "Monk" }, { "G2", "Monk" } }),
        rules = { G1 = Rules.New({ name = "Monk" }), G2 = Rules.New({ name = "Monk" }) },
        seats = Seats.Resolve(Plan(), {}),
    }))
    T.Eq(MarkPlan.IconFor({ guid = "G2", name = "Monk" }, steps), CROSS, "by GUID, exact")
    T.Eq(MarkPlan.IconFor({ name = "monk" }, steps), SKULL, "by name, the first not yet placed")
    T.Eq(MarkPlan.IconFor({ name = "Monk" }, steps, { [SKULL] = true }), CROSS, "Skull already out: Cross")
    local icon, why = MarkPlan.IconFor({}, steps)
    T.Eq(icon, nil, "nothing readable")
    T.True(why:find("hidden", 1, true), "says the name is hidden")
    T.Eq(MarkPlan.IconFor({ name = "Rat" }, steps), nil, "no plan for it")
end)

T.Case("MarkPlan.Pending: write out of combat, hold while locked", function()
    local a = MarkPlan.Fingerprint(StepsFor({ "Monk" }))
    local b = MarkPlan.Fingerprint(StepsFor({ "Monk", "Mage" }))
    T.True(a ~= b, "the fingerprint follows the plan")
    T.Eq(MarkPlan.Pending(nil, a, false), "write", "first write")
    T.Eq(MarkPlan.Pending(a, a, true), "same", "nothing changed")
    T.Eq(MarkPlan.Pending(a, b, true), "hold", "changed in combat: stale until it ends")
    T.Eq(MarkPlan.Pending(a, b, false), "write", "changed out of combat")
end)

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

local function Clear()
    return { enabled = true, inGroup = true, inRaid = true, canMark = true, stale = false, ruleCount = 3,
        blind = false, dropped = 0, nameless = 0, built = true, conflicts = {} }
end

T.Case("Debug.WhyNot: all clear, and each reason alone", function()
    T.Eq(#Debug.WhyNot(Clear()), 0, "nothing to say")
    local cases = {
        { "enabled", false, "off" }, { "inGroup", false, "solo" }, { "canMark", false, "rights" },
        { "stale", true, "stale" }, { "ruleCount", 0, "norules" }, { "blind", true, "blind" },
        { "dropped", { {}, {} }, "toolong" }, { "nameless", 1, "noname" }, { "built", false, "notbuilt" },
        { "conflicts", { "OtherMarker" }, "conflict" },
    }
    for _, c in ipairs(cases) do
        local state = Clear()
        state[c[1]] = c[2]
        local reasons = Debug.WhyNot(state)
        T.Eq(#reasons, 1, c[1] .. " gives one reason")
        T.Eq(reasons[1].code, c[3], c[1] .. " is " .. c[3])
    end
    local state = Clear()
    state.inRaid, state.canMark = false, false
    T.Eq(#Debug.WhyNot(state), 0, "no rights matter only in a raid")
    state = Clear()
    state.dropped = 2
    T.True(Debug.WhyNot(state)[1].text:find("2 seats", 1, true), "the count is named")
end)

T.Case("Debug.WhyNot: most fundamental first when several hold", function()
    local state = { enabled = false, inGroup = true, inRaid = true, canMark = false, stale = true, ruleCount = 0,
        blind = true, dropped = 1, nameless = 2, built = false, conflicts = { "X" } }
    local codes = {}
    for i, r in ipairs(Debug.WhyNot(state)) do codes[i] = r.code end
    T.Eq(table.concat(codes, ","), "off,rights,stale,norules,blind,toolong,noname,notbuilt,conflict", "the order")
end)

T.Case("Debug.PlanLines: one line per step in press order", function()
    local lines = Debug.PlanLines(StepsFor({ "Monk", "Guard" }))
    T.Eq(lines[1], "Skull (Kill 1): Monk", "first")
    T.Eq(lines[2], "Cross (Kill 2): Guard", "second")
end)

--------------------------------------------------------------------------------
-- Log
--------------------------------------------------------------------------------

T.Case("Log: a ring that wraps at its size, newest first", function()
    local log = { head = 0, entries = {} }
    for i = 1, 505 do Log.Push(log, { at = i, kind = (i % 2 == 0) and "plan" or "say", text = "e" .. i }) end
    T.Eq(#log.entries, 500, "capped at 500")
    T.Eq(log.head, 5, "wrapped round")
    local recent = Log.Recent(log, 3)
    T.Eq(recent[1].text, "e505", "newest first")
    T.Eq(recent[3].text, "e503", "then older")
    local all = Log.Recent(log)
    T.Eq(#all, 500, "everything")
    T.Eq(all[500].text, "e6", "the oldest left is e6")
    local plans = Log.Recent(log, 2, "plan")
    T.Eq(plans[1].text, "e504", "filter by kind")
    T.Eq(plans[2].text, "e502", "only that kind")
    T.Eq(#Log.Recent({ head = 0, entries = {} }, 5), 0, "an empty log")
    T.Eq(#Log.Recent(nil, 5), 0, "no log at all")
end)

T.Case("Log: small ring, ages, describe, args", function()
    local log = { head = 0, entries = {} }
    for i = 1, 4 do Log.Push(log, { at = i, kind = "plan", text = "e" .. i }, 3) end
    T.Eq(#log.entries, 3, "size 3")
    T.Eq(Log.Recent(log, 1)[1].text, "e4", "newest")
    T.Eq(Log.Age(12), "12s", "seconds")
    T.Eq(Log.Age(300), "5m", "minutes")
    T.Eq(Log.Age(3 * 3600), "3h", "hours")
    T.Eq(Log.Age(2 * 86400), "2d", "days")
    T.True(Log.Describe({ at = 100, kind = "death", text = "Tank died" }, 112):find("12s", 1, true), "relative age")
    local count, kind = Log.ParseArgs("5 death")
    T.Eq(count, 5, "count")
    T.Eq(kind, "death", "kind")
    T.Eq((Log.ParseArgs("")), 15, "default count")
end)
