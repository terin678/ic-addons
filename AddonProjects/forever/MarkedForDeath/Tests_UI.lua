local addonName, ns = ...

--[[
Tests_UI: the window lane's cases, the pure halves of UI_Main, UI_Roles, UI_Rules,
UI_Assignments, UI_Settings and Launcher.
Owned by lane G (window and config). Every case builds its own tables; none touches the
saved ones, and none adds a tab to the real window.
]]

local T = ns.Tests
local UI, UIRoles, UIRules, UIA, UIS, Launcher = ns.UI, ns.UIRoles, ns.UIRules, ns.UIAssignments, ns.UISettings,
    ns.Launcher
local Schema, Seats, Rules = ns.Schema, ns.Seats, ns.Rules

local function Copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and Copy(v) or v end
    return out
end

local function DefaultPlan()
    return Copy(Schema.DEFAULT_PLAN)
end

local function Keys(list, field)
    local out = {}
    for i, item in ipairs(list) do out[i] = tostring(item[field or 1]) end
    return table.concat(out, ",")
end

local NAMES = {
    [189] = { name = "Scarlet Monastery" },
    [36] = { name = "Deadmines" },
}

--------------------------------------------------------------------------------
-- UI_Main
--------------------------------------------------------------------------------

T.Case("UI.SortTabs: known tabs in their fixed order, others after in the order added", function()
    local sorted = UI.SortTabs({
        { key = "deaths", seq = 1 }, { key = "zeta", seq = 2 }, { key = "roles", seq = 3 },
        { key = "alpha", seq = 4 }, { key = "assign", seq = 5 }, { key = "settings", seq = 6 },
    })
    T.Eq(Keys(sorted, "key"), "assign,roles,deaths,settings,zeta,alpha", "fixed order, then by seq")
end)

T.Case("UI.Size: saved size held between the minimum and the screen", function()
    local w, h = UI.Size(nil, 680, 500)
    T.Eq(w, UI.DEFAULT_W, "default width")
    T.Eq(h, UI.DEFAULT_H, "default height")
    w, h = UI.Size({ w = 100, h = 100 }, 680, 500)
    T.Eq(w .. "x" .. h, "680x500", "never below the minimum")
    w, h = UI.Size({ w = 3000, h = 2000 }, 680, 500, 1920, 1080)
    T.Eq(w .. "x" .. h, "1920x1080", "never past the screen")
    w, h = UI.Size({ w = 900, h = 600 }, 680, 500, 640, 480)
    T.Eq(w .. "x" .. h, "680x500", "a screen smaller than the minimum keeps the minimum")
    local pw, ph = UI.PageSize(720, 540)
    T.Eq(pw .. "x" .. ph, "704x454", "page room: pads, tabs and footer taken off")
end)

T.Case("UI.PickTab: the saved tab when it exists, else the first", function()
    local sorted = { { key = "assign" }, { key = "roles" } }
    T.Eq(UI.PickTab("roles", sorted), "roles", "saved tab kept")
    T.Eq(UI.PickTab("gone", sorted), "assign", "a tab that went away falls back to the first")
    T.Eq(UI.PickTab(nil, {}), nil, "no tabs, no pick")
end)

T.Case("UI.PowerPlan: /mfd on and off say what changed, and nothing when it is already so", function()
    local p = UI.PowerPlan("off", nil)
    T.Eq(p.action, "set", "nil counts as on, so off changes it")
    T.Eq(p.value, false, "to off")
    T.True(p.text:find("/mfd on", 1, true), "and says how to undo it")
    T.Eq(UI.PowerPlan("off", false).action, "same", "off when off does nothing")
    T.Eq(UI.PowerPlan("on", true).action, "same", "on when on does nothing")
    local on = UI.PowerPlan("on", false)
    T.Eq(on.action .. tostring(on.value), "settrue", "on when off turns it on")
end)

T.Case("UI.Age: relative ages for lists and status lines", function()
    T.Eq(UI.Age(12), "12s", "seconds")
    T.Eq(UI.Age(300), "5m", "minutes")
    T.Eq(UI.Age(3 * 3600 + 5), "3h", "hours")
    T.Eq(UI.Age(2 * 86400), "2d", "days")
    T.Eq(UI.Age(-5), "0s", "a clock that went backwards reads as now")
    T.Eq(UI.Age(nil), "0s", "nothing reads as now")
end)

T.Case("UI.KeyLabel and FooterText: how instance keys read", function()
    T.Eq(UI.KeyLabel("default", NAMES), "Default plan", "default")
    T.Eq(UI.KeyLabel("open", NAMES), "Open world", "open world")
    T.Eq(UI.KeyLabel("i:189", NAMES), "Scarlet Monastery (189)", "a known instance")
    T.Eq(UI.KeyLabel("i:999", NAMES), "Instance 999", "an unknown one")
    T.Eq(UI.KeyLabel("legacy:Karazhan", NAMES), "Karazhan (Anniversary)", "an Anniversary leftover")
    local off = UI.FooterText({ enabled = false, key = "i:189", names = NAMES, rules = 1, lead = "Raid Lead: Ann" })
    T.True(off:find("Off", 1, true) and off:find("1 rule", 1, true) and off:find("Ann", 1, true), "all of it when off")
    T.Eq(UI.FooterText({ key = "open" }):find("Off", 1, true), nil, "no Off when on")
end)

T.Case("UI.AddTab: a tab without a key, label or build is refused before it is kept", function()
    T.Eq((UI.AddTab(nil, "X", function() end)), false, "no key")
    T.Eq((UI.AddTab("x", "", function() end)), false, "no label")
    T.Eq((UI.AddTab("x", "X", nil)), false, "no build")
end)

--------------------------------------------------------------------------------
-- UI_Roles
--------------------------------------------------------------------------------

T.Case("UIRoles.PlanChoices: default, here, then instances with plans or rules, then known ones", function()
    local db = { plans = { default = {}, ["i:36"] = {} }, rules = { ["legacy:Karazhan"] = {}, ["i:777"] = {} } }
    local choices = UIRoles.PlanChoices(db, "i:189", NAMES)
    T.Eq(choices[1][1], "default", "default first")
    T.Eq(choices[2][1], "i:189", "where I am second")
    local seen = {}
    for _, c in ipairs(choices) do
        T.True(not seen[c[1]], c[1] .. " once")
        seen[c[1]] = true
    end
    T.True(seen["i:36"] and seen["i:777"], "instances with a plan or rules")
    T.True(not seen["legacy:Karazhan"], "Anniversary leftovers have no plan to pick")
    T.Eq(UIRoles.PlanChoices(db, "open", NAMES)[2][1] ~= "open", true, "the open world is not a plan")
end)

T.Case("UIRoles.JobChoices: no Never mark and no hidden job for a seat", function()
    local seen = {}
    for _, c in ipairs(UIRoles.JobChoices()) do seen[c[1]] = true end
    T.True(seen.KILL and seen.SHEEP and seen.BANISH, "the usual jobs")
    T.True(not seen.IGNORE, "Never mark is a rule's answer, not a seat's")
    T.True(not seen.REPENTANCE, "a hidden job is not offered")
end)

T.Case("UIRoles.SetJob: a seat moving job goes last there, both jobs renumbered, plan still valid", function()
    local plan = DefaultPlan()
    T.True(UIRoles.SetJob(plan, 2, "SHEEP"), "Circle becomes a Sheep seat")
    T.Eq(plan[2].intent .. plan[2].ordinal, "SHEEP3", "last of the Sheep seats")
    T.Eq(plan[8].ordinal .. plan[7].ordinal .. plan[6].ordinal, "123", "Kill seats unchanged")
    T.True(Seats.Validate(plan), "no two seats share a number")
    T.Eq(UIRoles.SetJob(plan, 8, "IGNORE"), false, "a seat cannot be Never mark")
    T.True(UIRoles.SetJob(plan, 6, "KILL"), "the same job is a no-op")
    T.Eq(plan[6].ordinal, 3, "and keeps its number")
end)

T.Case("UIRoles.MoveSeat: swaps within a job, nothing at the ends", function()
    local plan = DefaultPlan()
    T.True(UIRoles.MoveSeat(plan, 7, -1), "Cross moves up")
    T.Eq(plan[7].ordinal .. plan[8].ordinal, "12", "Cross is Kill 1, Skull Kill 2")
    T.Eq(UIRoles.MoveSeat(plan, 7, -1), false, "Kill 1 cannot go higher")
    T.Eq(UIRoles.MoveSeat(plan, 2, 1), false, "Kill 4 cannot go lower")
    T.Eq(UIRoles.MoveSeat(plan, 5, 1) and plan[5].ordinal, 2, "Moon moves to Sheep 2")
    T.True(Seats.Validate(plan), "still valid")
end)

T.Case("UIRoles.SetPin and SetReserved: trimmed, empty clears, a seat with no job becomes Kill", function()
    local plan = DefaultPlan()
    T.Eq(UIRoles.SetPin(plan, 5, "  Ann Example "), "Ann Example", "trimmed")
    T.Eq(UIRoles.SetPin(plan, 5, "   "), nil, "empty clears")
    T.Eq(plan[5].pin, nil, "and it is gone")
    plan[3] = nil
    UIRoles.SetReserved(plan, 3, true)
    T.Eq(plan[3].intent .. tostring(plan[3].reserved), "KILLtrue", "an empty seat becomes Kill, kept")
    UIRoles.SetReserved(plan, 3, false)
    T.Eq(plan[3].reserved, nil, "unticked is nil, not false")
    T.True(Seats.Validate(plan), "still valid")
end)

T.Case("UIRoles.OwnerText: every owner and pin state has its words and colour", function()
    local function Text(record) return table.concat({ UIRoles.OwnerText(record) }, "|") end
    T.Eq(Text(nil), "no job|textDim", "no seat")
    T.Eq(Text({ owner = true }):match("|(%a+)$"), "good", "a kill seat is anyone's")
    T.Eq(Text({ owner = "Ann", pin = "Ann", pinState = "held" }), "Ann (pinned)|good", "pin held")
    T.Eq(Text({ owner = "Bob", pin = "Ann", pinState = "offline" }), "Bob; Ann is offline|warn", "pin offline, Bob has it")
    T.Eq(Text({ owner = false, pin = "Ann", pinState = "wrong class" }), "nobody: Ann cannot do this job|bad",
        "pin wrong class, nobody else")
    T.Eq(Text({ owner = false }), "nobody in the group can do this|bad", "nobody")
    T.Eq(Text({ owner = "Cy" }), "Cy|good", "by name")
end)

--------------------------------------------------------------------------------
-- UI_Rules
--------------------------------------------------------------------------------

local function Set(list)
    local set = {}
    for i, name in ipairs(list) do
        local rule = Rules.New({ name = name, rank = i * 10 })
        set[Rules.Key(rule)] = rule
    end
    return set
end

local function Order(set)
    local out = {}
    for i, rule in ipairs((Rules.Ranked(set))) do out[i] = rule.name or tostring(rule.npcID) end
    return table.concat(out, ",")
end

T.Case("UIRules.KeyChoices: where I am, the open world, then by name, Anniversary leftovers last", function()
    local choices = UIRules.KeyChoices({ rules = { ["legacy:Karazhan"] = {}, ["i:36"] = {} } }, NAMES)
    T.Eq(Keys(choices), "here,open,i:36,i:189,legacy:Karazhan", "Deadmines before Scarlet Monastery, leftover last")
end)

T.Case("UIRules.Items: rank order, yours apart from the group's", function()
    local mine = Set({ "A", "B" })
    local merged = Copy(mine)
    local theirs = Rules.New({ name = "C", rank = 15 })
    merged["n:C"] = theirs
    local items = UIRules.Items(merged, mine, { ["n:C"] = "Ann Example" })
    T.Eq(Keys(items, "key"), "n:A,n:C,n:B", "by rank")
    T.Eq(tostring(items[2].mine) .. items[2].from, "falseAnn Example", "the group's rule names its owner")
    T.Eq(items[1].from, nil, "yours has no from")
    T.Eq(items[3].pos, 3, "position, not rank")
end)

T.Case("UIRules.Add: by name or npc id, last in the order, duplicates and bad names refused", function()
    local set = Set({ "Scarlet Monk" })
    local key = UIRules.Add(set, "Scarlet Sorcerer", "SHEEP")
    T.Eq(key, "n:Scarlet Sorcerer", "added by name")
    T.Eq(set[key].rank .. set[key].intent, "20SHEEP", "last, with its job")
    T.Eq(UIRules.Add(set, "4294"), "id:4294", "an npc id")
    local none, why = UIRules.Add(set, "scarlet monk")
    T.Eq(none, nil, "the same mob in another case is refused")
    T.True(why:find("already", 1, true), "saying so")
    T.Eq((UIRules.Add(set, "Bad;Name")), nil, "a name a macro cannot hold is refused")
    T.Eq((UIRules.Add(set, "   ")), nil, "nothing typed is refused")
end)

T.Case("UIRules.Move: chosen rules move together one place, ranks renumbered", function()
    local set = Set({ "A", "B", "C", "D" })
    T.True(UIRules.Move(set, { ["n:C"] = true, ["n:D"] = true }, -1), "C and D up")
    T.Eq(Order(set), "A,C,D,B", "together, order kept")
    T.Eq(set["n:B"].rank, 40, "renumbered in tens")
    T.Eq(UIRules.Move(set, { ["n:A"] = true }, -1), false, "the top cannot go higher")
    T.True(UIRules.Move(set, { ["n:A"] = true, ["n:C"] = true }, 1), "A and C down")
    T.Eq(Order(set), "D,A,C,B", "each one place, the block keeps its order")
end)

T.Case("UIRules.Apply: job, fallback and max count for many; an invalid change is refused", function()
    local set = Set({ "A", "B" })
    local all = { ["n:A"] = true, ["n:B"] = true }
    T.Eq((UIRules.Apply(set, all, "intent", "SHEEP")), 2, "both to Sheep")
    T.Eq((UIRules.Apply(set, all, "fallback", "KILL")), 2, "else Kill")
    T.Eq(set["n:A"].fallback, "KILL", "set")
    local changed, refused = UIRules.Apply(set, all, "fallback", "SHEEP")
    T.Eq(changed .. "/" .. refused, "2/0", "a fallback equal to the job is dropped by Rules.New, not refused")
    T.Eq(set["n:A"].fallback, nil, "so it reads as none")
    T.Eq((UIRules.Apply(set, all, "maxCount", 2)), 2, "max two")
    changed, refused = UIRules.Apply(set, all, "maxCount", 0)
    T.Eq(changed .. "/" .. refused, "0/2", "zero is refused")
    T.Eq(set["n:B"].maxCount, 2, "and left as it was")
    UIRules.Apply(set, all, "maxCount", nil)
    T.Eq(set["n:B"].maxCount, nil, "nil clears it")
    UIRules.Apply(set, all, "fallback", "KILL")
    UIRules.Apply(set, all, "fallback", "none")
    T.Eq(set["n:B"].fallback, nil, "none clears the fallback")
end)

T.Case("UIRules.Delete: gone, and the rest renumbered", function()
    local set = Set({ "A", "B", "C" })
    T.Eq(UIRules.Delete(set, { ["n:B"] = true, ["n:Z"] = true }), 1, "one deleted, a missing key ignored")
    T.Eq(set["n:C"].rank, 20, "C moves up to 20")
end)

T.Case("UIRules.Paste: the pasted order goes on top, matches updated, the rest follow", function()
    local set = Set({ "A", "B", "C" })
    local rules = Rules.ParseBulk("C = sheep\nNew\na")
    local added, updated = UIRules.Paste(set, rules)
    T.Eq(added .. "/" .. updated, "1/2", "New added, C and A updated")
    T.Eq(Order(set), "C,New,A,B", "pasted order, then B")
    T.Eq(set["n:C"].intent, "SHEEP", "C took the pasted job")
    T.Eq(set["n:B"].rank, 40, "renumbered")
end)

T.Case("UIRules.Import: a loaded file updates matches and adds the rest, deleting nothing", function()
    local byKey = { ["i:36"] = Set({ "A", "B" }) }
    local loaded = assert(Rules.FromJSON(assert(Rules.ToJSON({
        ["i:36"] = { ["n:A"] = Rules.New({ name = "A", intent = "SHEEP", rank = 10 }),
                     ["n:N"] = Rules.New({ name = "N", rank = 20 }) },
        ["i:189"] = { ["n:Q"] = Rules.New({ name = "Q", rank = 10 }) },
    }))))
    local zones, added, updated = UIRules.Import(byKey, loaded)
    T.Eq(zones .. "/" .. added .. "/" .. updated, "2/2/1", "two instances, N and Q added, A updated")
    T.Eq(byKey["i:36"]["n:A"].intent, "SHEEP", "A took the file's job")
    T.True(byKey["i:36"]["n:B"] ~= nil, "B, not in the file, is kept")
end)

T.Case("UIRules.MoveLegacy: an Anniversary zone moves under an instance; rules already there win", function()
    local byKey = {
        ["legacy:Karazhan"] = Set({ "A", "B" }),
        ["i:36"] = { ["n:A"] = Rules.New({ name = "A", intent = "SHEEP", rank = 10 }) },
    }
    T.Eq(UIRules.MoveLegacy(byKey, "legacy:Karazhan", "i:36"), 1, "B came across")
    T.Eq(byKey["legacy:Karazhan"], nil, "the leftover is gone")
    T.Eq(byKey["i:36"]["n:A"].intent, "SHEEP", "the rule already there won")
    T.Eq((UIRules.MoveLegacy(byKey, "i:36", "i:189")), nil, "only legacy keys move")
    byKey["legacy:X"] = Set({ "Z" })
    T.Eq((UIRules.MoveLegacy(byKey, "legacy:X", "open")), nil, "not into the open world")
end)

T.Case("UIRules.NpcFromGuid: creatures only", function()
    T.Eq(UIRules.NpcFromGuid("Creature-0-4372-189-12-4294-0000ABCDEF"), 4294, "a creature")
    T.Eq(UIRules.NpcFromGuid("Vehicle-0-4372-189-12-1234-0000ABCDEF"), 1234, "a vehicle")
    T.Eq(UIRules.NpcFromGuid("Player-4372-0ABCDEF1"), nil, "a player")
    T.Eq(UIRules.NpcFromGuid("Pet-0-4372-189-12-416-0100ABCDEF"), nil, "a pet")
    T.Eq(UIRules.NpcFromGuid(nil), nil, "nothing")
end)

T.Case("UIRules.Note: counts, the group's share, the choice, and the leftover warning", function()
    local items = { { mine = true }, { mine = false }, { mine = true } }
    local note = UIRules.Note({ label = "X", items = items, selected = 2 })
    T.True(note:find("3 rules", 1, true) and note:find("1 from the group", 1, true) and note:find("2 chosen", 1, true),
        "all three counts")
    T.True(UIRules.Note({ label = "Deadmines", items = {} }):find("No rules for Deadmines", 1, true), "empty")
    T.True(UIRules.Note({ legacy = true }):find("Move here", 1, true), "a leftover says how to move it")
end)

--------------------------------------------------------------------------------
-- UI_Assignments
--------------------------------------------------------------------------------

T.Case("UIAssignments.IconText: an inline icon for 1 to 8 only", function()
    local skull = UIA.IconText(8, 14)
    T.True(skull:find("UI-RaidTargetingIcons", 1, true), "the kit's icon sheet")
    T.True(skull:find(":192:256:64:128|t", 1, true), "skull is the last cell of the second row")
    T.Eq(UIA.IconText(9), "", "nine is nothing")
    T.Eq(UIA.IconText(nil), "", "nil is nothing")
end)

T.Case("UIAssignments.Preview: rules and seats give the plan a press would mark, blind", function()
    local set = {
        ["n:Monk"] = Rules.New({ name = "Monk", rank = 10 }),
        ["n:Sorcerer"] = Rules.New({ name = "Sorcerer", intent = "SHEEP", rank = 20 }),
        ["id:99"] = Rules.New({ npcID = 99, rank = 30 }),
    }
    local members = { { name = "Mage", class = "MAGE" }, { name = "Lock", class = "WARLOCK" } }
    local steps, alloc = UIA.Preview(DefaultPlan(), set, members)
    T.Eq(#steps, 2, "two names; the id-only rule cannot be targeted")
    T.Eq(steps[1].iconName .. ":" .. steps[1].name, "Skull:Monk", "Skull first")
    T.Eq(steps[2].owner, "Mage", "the sheep seat's owner")
    T.Eq(#alloc.skipped, 1, "the id-only rule is reported")
    local none = UIA.Preview(DefaultPlan(), set, {})
    T.Eq(#none, 1, "no mage: the sheep rule has no seat (no fallback)")
end)

T.Case("UIAssignments.Source: lane B first, then someone else's published plan, then the preview", function()
    local preview = { { icon = 8 } }
    local _, _, role = UIA.Source({ preview = preview })
    T.Eq(role, "warn", "the preview is amber")
    local steps, text = UIA.Source({ preview = preview, unmet = 2 })
    T.Eq(steps, preview, "preview steps")
    T.True(text:find("2 crowd control rules", 1, true), "unmet counted")
    local pub = { from = "Ann", at = 100, steps = { { icon = 7 } } }
    steps, text = UIA.Source({ preview = preview, published = pub, me = "Bob", now = 220 })
    T.Eq(steps, pub.steps, "the Raid Lead's plan")
    T.True(text:find("Ann, 2m ago", 1, true), "who and how long ago")
    steps = UIA.Source({ preview = preview, published = pub, me = "Ann" })
    T.Eq(steps, preview, "my own published plan is not shown back to me")
    local provided = { { icon = 1 } }
    steps = UIA.Source({ provided = provided, published = pub, me = "Bob", preview = preview })
    T.Eq(steps, provided, "lane B's provider wins")
end)

T.Case("UIAssignments.Rows: seat, mob and holder with their colours", function()
    local rows = UIA.Rows({
        { icon = 8, seatLabel = "Kill 1", name = "Monk", owner = true },
        { icon = 5, seatLabel = "Sheep 1", name = "Sorcerer", owner = "Mage" },
        { icon = 1, seatLabel = "Sheep 2", name = "Adept", owner = false },
        { icon = 4, name = "Guard", borrowed = true },
    })
    T.Eq(rows[1].iconName .. "|" .. rows[1].who .. "|" .. rows[1].whoRole, "Skull|anyone|textDim", "kill")
    T.Eq(rows[2].who .. "|" .. rows[2].whoRole, "Mage|good", "owner")
    T.Eq(rows[3].whoRole, "bad", "nobody can")
    T.Eq(rows[4].seat .. "|" .. rows[4].seatRole, "lent: Kill|warn", "a lent icon")
end)

--------------------------------------------------------------------------------
-- UI_Settings
--------------------------------------------------------------------------------

T.Case("UISettings.DeathsSummary: each kind and the chat cue in a line", function()
    local db = { deaths = {
        tank = { on = true, trash = true, override = "auto" },
        healer = { on = false, override = "auto" },
    }, settings = { cue = { enabled = true, word = "", sound = "" } } }
    local line = UIS.DeathsSummary(db)
    T.True(line:find("Tank deaths on, bosses and trash", 1, true), "tank")
    T.True(line:find("Healer deaths off", 1, true), "healer")
    T.True(line:find("no word or sound", 1, true), "a cue switched on with nothing set says so")
    db.deaths.healer.override = "on"
    T.True(UIS.DeathsSummary(db):find("Healer deaths on everywhere", 1, true), "override")
end)

T.Case("UISettings.WhyState and WhyLines: what this tab knows, lane B's extra, colours by level", function()
    local state = UIS.WhyState({
        enabled = true, ruleCount = 3,
        roster = { kind = "raid", canMark = false },
        conflicts = { { addon = "Quickdraw", topic = ns.Conflicts.TOPIC_ICONS }, { addon = "X", topic = "combat logging" } },
        extra = { blind = true },
    })
    T.Eq(tostring(state.inGroup) .. tostring(state.inRaid) .. tostring(state.canMark), "truetruefalse", "group")
    T.Eq(#state.conflicts .. state.conflicts[1], "1Quickdraw", "only marker addons count")
    T.Eq(state.blind, true, "lane B's field kept")
    local lines = UIS.WhyLines(ns.DebugWhy.WhyNot(state))
    T.Eq(lines[1][2], "bad", "no rights blocks: red")
    T.Eq(UIS.WhyLines({})[1][2], "good", "nothing in the way: green")
    T.Eq(UIS.WhyState({}).inGroup, nil, "no roster: not known, not solo")
end)

T.Case("UISettings.ConflictLines and ListedText", function()
    T.Eq(UIS.ConflictLines({ "a", "b" })[2][2], "warn", "findings amber")
    T.Eq(UIS.ConflictLines({})[1][2], "good", "none green")
    T.True(UIS.ListedText({ instances = {} }, NAMES):find("none", 1, true), "nothing listed")
    T.Eq(UIS.ListedText({ instances = { ["i:189"] = true, ["i:36"] = true } }, NAMES),
        "Listed: Deadmines (36), Scarlet Monastery (189).", "both, by name")
end)

--------------------------------------------------------------------------------
-- Launcher
--------------------------------------------------------------------------------

T.Case("Launcher.MenuItems: every entry reaches its action; ticks follow the state", function()
    local did = {}
    local items = Launcher.MenuItems({
        enabled = false, minimap = true,
        act = {
            open = function(key) did[#did + 1] = "open:" .. key end,
            check = function() did[#did + 1] = "check" end,
            float = function() did[#did + 1] = "float" end,
            toggleEnabled = function() did[#did + 1] = "toggle" end,
            minimap = function(on) did[#did + 1] = "minimap:" .. tostring(on) end,
        },
    })
    for _, item in ipairs(items) do
        if item.onClick then item.onClick() end
    end
    T.Eq(table.concat(did, ","), "open:assign,open:roles,open:rules,check,open:settings,float,toggle,minimap:false",
        "each entry once, in order")
    local ticks = {}
    for _, item in ipairs(items) do
        if item.checked then ticks[#ticks + 1] = tostring(item.checked()) end
    end
    T.Eq(table.concat(ticks, ","), "false,true", "off shows unticked, the button shown ticked")
end)
