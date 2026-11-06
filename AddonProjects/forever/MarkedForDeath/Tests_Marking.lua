local addonName, ns = ...

--[[
Tests_Marking: the marking lane's cases (MarkButtons' plan-to-macro half, the press record
ns.Ledger, the "unbound" Debug reason). Owned by lane B (marking runtime). Every case builds
its own tables; none touches the saved ones or a frame. Registered on ns.Tests; Tests.lua
runs them all.

A secret value here is a table whose every comparison, index, concatenation and call
throws, marked secret through Env.SetSecretCheck: if the record ever compared, indexed or
joined one, the case would error rather than pass.
]]

local T = ns.Tests
local MB, Ledger, Rules, Debug, MarkPlan = ns.MarkButtons, ns.Ledger, ns.Rules, ns.DebugWhy, ns.MarkPlan
local Env = LibStub("LibICEnv-1.0")
local Secure = LibStub("LibICSecure-1.0")
local Util = LibStub("LibICUtil-1.0")

local SKULL, CROSS, SQUARE, CIRCLE, MOON = 8, 7, 6, 2, 5
local WORDS = { mark = "/tm", exact = "/targetexact", click = "/click" }

local function Step(icon, name, guid)
    return { icon = icon, name = name, guid = guid }
end

-- A value that throws on anything but being passed along and type().
local function Secret()
    local function Boom() error("a secret value was used", 2) end
    return setmetatable({}, {
        __index = Boom, __newindex = Boom, __lt = Boom, __le = Boom, __eq = Boom,
        __concat = Boom, __call = Boom, __add = Boom, __sub = Boom, __len = Boom,
    })
end

-- Runs fn(asked) with `secrets` (a list) marked secret, and puts the check back after.
-- asked[i] counts how often the check was asked about secrets[i]. On the client a secret
-- number still answers type() with "number", so the check must come first: these counts
-- prove it was asked rather than a type test happening to turn the value away.
local function WithSecrets(secrets, fn)
    local asked = {}
    Env.SetSecretCheck(function(v)
        for i, s in ipairs(secrets) do
            if rawequal(v, s) then
                asked[i] = (asked[i] or 0) + 1
                return true
            end
        end
        return false
    end)
    local ok, err = pcall(fn, asked)
    Env.SetSecretCheck(nil)
    if not ok then error(err, 0) end
end

local function Set(list)
    local set = {}
    for i, row in ipairs(list) do
        local rule = assert(Rules.New({ name = row[1], intent = row[2] or "KILL", rank = i * 10 }))
        set[Rules.Key(rule)] = rule
    end
    return set
end

--------------------------------------------------------------------------------
-- Plan to macro
--------------------------------------------------------------------------------

T.Case("MarkButtons.PackText: Skull first, one targetexact and tm pair per step, target put back", function()
    local steps = { Step(SKULL, "Scarlet Sorcerer"), Step(CROSS, "Scarlet Monk") }
    local text, kept, dropped = MB.PackText(steps, WORDS)
    T.Eq(text, "/targetexact Scarlet Sorcerer\n/tm ~8\n/targetexact Scarlet Monk\n/tm ~7\n/targetlasttarget", "the macro")
    T.Eq(#kept, 2, "both held")
    T.Eq(#dropped, 0, "nothing dropped")
    T.Eq(MB.PackText({}, WORDS), "", "an empty plan is empty text")
end)

T.Case("MarkButtons.PackText: the client's own slash words, English when missing", function()
    local text = MB.PackText({ Step(SKULL, "Ogre") }, { mark = "/zm", exact = "/zx" })
    T.Eq(text, "/zx Ogre\n/zm ~8\n/targetlasttarget", "the words handed in")
    T.Eq((MB.PackText({ Step(SKULL, "Ogre") }, nil)), "/targetexact Ogre\n/tm ~8\n/targetlasttarget", "English")
    T.Eq(MB.ClearTargetText({ mark = "/zm" }), "/zm 0", "clear target uses the mark word")
    T.Eq(MB.ClearTargetText(), "/tm 0", "and /tm by default")
end)

T.Case("MarkButtons.PackText: cut on a whole pair inside the limit, the rest dropped in order", function()
    local steps = {}
    for i, icon in ipairs({ SKULL, CROSS, SQUARE, CIRCLE, MOON }) do
        steps[i] = Step(icon, "Very Long Mob Name Number " .. i .. " Of The Scarlet Crusade")
    end
    local text, kept, dropped = MB.PackText(steps, WORDS, Secure.MACRO_LIMIT)
    T.True(#text <= Secure.MACRO_LIMIT, "fits in 255 bytes")
    T.True(#kept >= 1 and #kept < 5, "some kept, some cut")
    T.Eq(#kept + #dropped, 5, "every step is either kept or dropped")
    T.Eq(kept[1].icon, SKULL, "Skull is kept first")
    T.Eq(dropped[1].icon, steps[#kept + 1].icon, "the first dropped is the next seat down")
    T.True(text:sub(-#"/targetlasttarget") == "/targetlasttarget", "still ends by putting the target back")
    local lines = {}
    for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
    T.Eq(#lines, #kept * 2 + 1, "whole pairs only")

    local tiny, k2, d2 = MB.PackText(steps, WORDS, 20)
    T.Eq(tiny, "", "nothing fits: no text")
    T.Eq(#k2, 0, "nothing kept")
    T.Eq(#d2, 5, "all dropped")
end)

T.Case("MarkButtons.RemarkText: clicks Clear all first, then the pack; dropped counted without the click", function()
    local steps = { Step(SKULL, "Ogre"), Step(CROSS, "Gnoll") }
    local text, kept, dropped = MB.RemarkText(steps, WORDS, nil, "MFDClear")
    T.Eq(text, "/click MFDClear\n/targetexact Ogre\n/tm ~8\n/targetexact Gnoll\n/tm ~7\n/targetlasttarget", "the macro")
    T.Eq(#kept, 2, "both kept")
    T.Eq(#dropped, 0, "none dropped")
    T.Eq((MB.RemarkText({}, WORDS)), "/click MFDClear", "an empty plan is the click alone")
    local long = {}
    for i = 1, 8 do long[i] = Step(9 - i, "A Rather Long Name For Mob " .. i) end
    local t2, k2, d2 = MB.RemarkText(long, WORDS, 255)
    T.True(#t2 <= 255, "fits")
    T.Eq(#k2 + #d2, 8, "every step accounted for")
    T.True(t2:find("^/click MFDClear\n") ~= nil, "the click stays first")
end)

T.Case("MarkButtons.Plan: blind from the rules, Skull to the first kill rule; off writes nothing", function()
    local rules = Set({ { "Scarlet Sorcerer" }, { "Scarlet Monk" }, { "Scarlet Adept", "SHEEP" } })
    local members = { { name = "Ann", class = "MAGE", online = true } }
    local plan = MB.Plan({ rules = rules, plan = Util.DeepCopy(ns.Schema.DEFAULT_PLAN), members = members, words = WORDS })
    T.Eq(plan.steps[1].icon, SKULL, "Skull first")
    T.Eq(plan.steps[1].name, "Scarlet Sorcerer", "on the best kill rule")
    T.Eq(plan.steps[2].icon, CROSS, "Cross next")
    local moon
    for _, step in ipairs(plan.steps) do if step.name == "Scarlet Adept" then moon = step.icon end end
    T.Eq(moon, MOON, "the sheep rule gets Moon with a mage present")
    T.True(plan.pack:find("/targetexact Scarlet Sorcerer\n/tm ~8", 1, true) == 1, "the pack text starts with Skull")
    T.Eq(plan.cleartarget, "/tm 0", "clear target")
    T.True(plan.remark:find("^/click MFDClear") ~= nil, "re-mark clicks Clear all")
    T.Eq(plan.fingerprint, MarkPlan.Fingerprint(plan.steps), "the fingerprint is of what the button holds")

    local off = MB.Plan({ enabled = false, rules = rules, words = WORDS })
    T.Eq(off.pack, "", "off: Mark pack is empty")
    T.Eq(off.remark, "", "and Re-mark")
    T.Eq(#off.steps, 0, "no steps")
    T.Eq(#MB.Plan({ rules = {}, words = WORDS }).steps, 0, "no rules, no steps")
end)

T.Case("MarkButtons.Plan: a rule with only an npc id is nameless, not in the macro", function()
    local rules = Set({ { "Ogre" } })
    local idOnly = assert(Rules.New({ npcID = 1234, intent = "KILL", rank = 5 }))
    rules[Rules.Key(idOnly)] = idOnly
    local plan = MB.Plan({ rules = rules, plan = Util.DeepCopy(ns.Schema.DEFAULT_PLAN), words = WORDS })
    T.Eq(#plan.steps, 1, "only the named rule is pressed")
    T.Eq(#plan.nameless, 1, "the id-only rule is listed as nameless")
end)

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------

T.Case("MarkButtons keys: on, off, one button, a key moved, bad input refused", function()
    T.Eq(MB.ParseKeys("").action, "show", "nothing shows")
    local on = MB.ParseKeys("on")
    T.Eq(on.keys.pack, "CTRL-1", "on binds the probe's keys")
    T.Eq(MB.KeySet(on.keys)["CTRL-1"], "MFDMarkPack", "as an override set")
    T.Eq(MB.KeySet(on.keys)["CTRL-4"], "MFDClearTarget", "all four")
    T.Eq(MB.ParseKeys("off").keys, nil, "off drops them")

    local one = MB.ParseKeys("pack alt-q", nil)
    T.Eq(one.action, "set", "one button")
    T.Eq(one.keys.pack, "ALT-Q", "upper-cased")
    local moved = MB.ParseKeys("clear ALT-Q", one.keys)
    T.Eq(moved.keys.clear, "ALT-Q", "a key given to another button")
    T.Eq(moved.keys.pack, nil, "leaves the first")
    T.Eq(MB.ParseKeys("pack none", { pack = "CTRL-1" }).keys, nil, "none drops the last key")
    T.Eq(MB.ParseKeys("sing loud").action, "refuse", "an unknown button")
    T.Eq(MB.ParseKeys("pack CTRL-").action, "refuse", "a broken key")
    T.Eq(MB.ParseKeys("pack ctrl;1").action, "refuse", "a key with odd characters")
    T.Eq(MB.KeyText("CTRL-SHIFT-1"), "Ctrl-Shift-1", "a key as a label")
    T.Eq(MB.KeyText(nil), nil, "no key, no label")
    T.Eq(next(MB.KeySet(nil)), nil, "no keys, an empty set")
end)

--------------------------------------------------------------------------------
-- The press record
--------------------------------------------------------------------------------

T.Case("Ledger: a Mark pack press records each step as planned, never placed", function()
    local led = Ledger.New()
    Ledger.Pressed(led, "pack", { Step(SKULL, "Ogre"), Step(CROSS, "Gnoll") }, 100)
    local view = Ledger.View(led)
    T.Eq(view[SKULL].name, "Ogre", "Skull on the ogre")
    T.Eq(view[SKULL].state, "planned", "as planned")
    T.Eq(view[CROSS].state, "planned", "Cross too")
    T.Eq(led.press.kind, "pack", "the press kept")
    T.Eq(next(Ledger.Held(led)), nil, "planned icons are never held")
end)

T.Case("Ledger: Clear empties the record; Re-mark is clear then pack", function()
    local led = Ledger.New()
    Ledger.Pressed(led, "pack", { Step(SKULL, "Ogre"), Step(CROSS, "Gnoll") }, 100)
    Ledger.Pressed(led, "clear", nil, 110)
    T.Eq(next(Ledger.View(led)), nil, "clear empties it")
    Ledger.Pressed(led, "pack", { Step(SKULL, "Ogre"), Step(CROSS, "Gnoll") }, 120)
    Ledger.Pressed(led, "remark", { Step(SKULL, "Imp") }, 130)
    local view = Ledger.View(led)
    T.Eq(view[SKULL].name, "Imp", "re-mark plans its own steps")
    T.Eq(view[CROSS], nil, "and drops the rest")
    Ledger.Pressed(led, "cleartarget", nil, 140)
    T.Eq(Ledger.View(led)[SKULL].name, "Imp", "clear target cannot know which icon went: the record stays")
end)

T.Case("Ledger: Seen only counts, and starts again at each press", function()
    local led = Ledger.New()
    Ledger.Pressed(led, "pack", { Step(SKULL, "Ogre") }, 100)
    Ledger.Seen(led, 101)
    Ledger.Seen(led, 102)
    Ledger.Seen(led, 103)
    T.Eq(led.seen, 3, "three marks changed")
    T.Eq(Ledger.View(led)[SKULL].state, "planned", "seeing a change confirms nothing")
    T.Eq(Ledger.Summary(led, 112), "Mark pack pressed 12s ago, 3 mark changes seen", "the summary")
    Ledger.Pressed(led, "pack", { Step(SKULL, "Ogre") }, 120)
    T.Eq(led.seen, 0, "a new press starts the count again")
    T.Eq(Ledger.Summary(Ledger.New(), 1), nil, "no press, no summary")
end)

T.Case("Ledger: Settle replaces planned with what was read; unconfirmed stays planned", function()
    local led = Ledger.New()
    Ledger.Pressed(led, "pack", { Step(SKULL, "Ogre"), Step(CROSS, "Gnoll"), Step(SQUARE, "Imp") }, 100)
    Ledger.Settle(led, {
        { guid = "Creature-1", name = "Ogre", icon = SKULL },
        { guid = "Creature-9", name = "Kobold", icon = CROSS },
    }, 200)
    local view = Ledger.View(led)
    T.Eq(view[SKULL].state, "placed", "Skull confirmed")
    T.Eq(view[SKULL].guid, "Creature-1", "on that mob")
    T.Eq(view[CROSS].name, "Kobold", "a read replaces the plan: Cross is on the kobold")
    T.Eq(view[CROSS].state, "placed", "as placed")
    T.Eq(view[SQUARE].state, "planned", "no read for Square: still planned")
    T.Eq(Ledger.RowState(view, Step(SKULL, "Ogre")), "placed", "the Skull row is placed")
    T.Eq(Ledger.RowState(view, Step(CROSS, "Gnoll")), "other", "the Cross row is on another mob")
    T.Eq(Ledger.RowState(view, Step(SQUARE, "Imp")), "planned", "the Square row is planned")
    T.Eq(Ledger.RowState(view, Step(MOON, "Adept")), nil, "the record says nothing of Moon")
    local held = Ledger.Held(led)
    T.Eq(held["n:Ogre"], SKULL, "placed icons are held for the allocator")
    T.Eq(held["n:Imp"], nil, "planned ones are not")

    Ledger.Settle(led, { { guid = "Creature-1", name = "Ogre", icon = MOON } }, 300)
    view = Ledger.View(led)
    T.Eq(view[MOON].guid, "Creature-1", "the ogre now reads Moon")
    T.Eq(view[SKULL], nil, "so its old Skull entry goes")
end)

T.Case("Ledger: a secret icon, name or GUID never reaches a comparison, and the row is dropped", function()
    local icon, name, guid = Secret(), Secret(), Secret()
    WithSecrets({ icon, name, guid }, function(asked)
        local led = Ledger.New()
        Ledger.Pressed(led, "pack", { Step(SKULL, "Ogre") }, 100)
        Ledger.Settle(led, {
            { guid = "Creature-1", name = "Ogre", icon = icon },     -- secret icon: dropped whole
            { guid = guid, name = name, icon = CROSS },              -- nothing readable to name it
            { guid = guid, name = "Gnoll", icon = SQUARE },          -- secret GUID, plain name: kept by name
            { name = "Imp", icon = 9 },                              -- not an icon
            { name = "Imp", icon = 1.5 },
            { name = "Imp", icon = "8" },
            "junk",
        }, 200)
        local view = Ledger.View(led)
        T.Eq(view[SKULL].state, "planned", "the secret read confirmed nothing")
        T.Eq(view[CROSS], nil, "a row with no readable name or GUID is dropped")
        T.Eq(view[SQUARE].name, "Gnoll", "a plain name is enough")
        T.Eq(view[SQUARE].guid, nil, "and the secret GUID is not kept")
        local n = 0
        for _ in pairs(view) do n = n + 1 end
        T.Eq(n, 2, "nothing else got in")
        T.True((asked[1] or 0) >= 1, "the secret icon was asked about")
        T.True((asked[2] or 0) >= 1, "the secret name was asked about")
        T.True((asked[3] or 0) >= 1, "the secret GUID was asked about")
    end)
end)

T.Case("Ledger.Describe: the Mark guide, out of combat and in", function()
    local steps = { Step(SKULL, "Ogre"), Step(CROSS, "Gnoll") }
    local led = Ledger.New()
    T.Eq(select(2, Ledger.Describe(nil, steps, {}, false)), "textDim", "no target")
    local text, role = Ledger.Describe({ name = "Ogre" }, steps, Ledger.View(led), false)
    T.True(text:find("Skull is planned for Ogre", 1, true) ~= nil, "unmarked: what a press gives it")
    T.Eq(role, "good", "in green")

    text = Ledger.Describe({ name = "Ogre" }, steps, Ledger.View(led), true, SKULL)
    T.True(text:find("as planned", 1, true) ~= nil, "out of combat a plain read is compared")
    text, role = Ledger.Describe({ name = "Ogre" }, steps, Ledger.View(led), true, CROSS)
    T.Eq(role, "warn", "the wrong icon warns")

    Ledger.Pressed(led, "pack", steps, 100)
    text = Ledger.Describe({ name = "Ogre" }, steps, Ledger.View(led), true)
    T.True(text:find("Skull planned", 1, true) ~= nil, "in combat: the record's icon, as planned")
    text, role = Ledger.Describe({ name = "Kobold" }, steps, Ledger.View(led), true)
    T.True(text:find("marked by someone", 1, true) ~= nil, "a mark the plan did not press")
    T.Eq(role, "warn", "in amber")
    text = Ledger.Describe({ name = "Murloc" }, steps, Ledger.View(led), false)
    T.True(text:find("No icon for Murloc", 1, true) ~= nil, "no rule for it")
end)

--------------------------------------------------------------------------------
-- Debug: the unbound key
--------------------------------------------------------------------------------

T.Case("DebugWhy: Mark pack with no key bound is a reason, after not built and before conflicts", function()
    local reasons = Debug.WhyNot({ ruleCount = 3, unbound = true })
    T.Eq(#reasons, 1, "one reason")
    T.Eq(reasons[1].code, "unbound", "the unbound key")
    T.Eq(reasons[1].level, "warn", "a press by mouse is unproven, so it warns")
    local order = Debug.WhyNot({ ruleCount = 3, built = false, unbound = true, conflicts = { "X" } })
    T.Eq(order[1].code, "notbuilt", "not built first")
    T.Eq(order[2].code, "unbound", "then unbound")
    T.Eq(order[3].code, "conflict", "then conflicts")
    T.Eq(#Debug.WhyNot({ ruleCount = 3, unbound = false }), 0, "a bound key says nothing")
end)

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------

T.Case("UIBar: shown in a group, alone only with solo on, never when hidden", function()
    local Bar = ns.UIBar
    T.Eq(Bar.Shows({}, "raid"), true, "a raid")
    T.Eq(Bar.Shows({}, "party"), true, "a party")
    T.Eq(Bar.Shows({}, "solo"), false, "alone: hidden by default")
    T.Eq(Bar.Shows({ outsideRaid = true }, "solo"), true, "solo on shows it alone")
    T.Eq(Bar.Shows({ shown = false, outsideRaid = true }, "raid"), false, "hidden wins")
    T.Eq(Bar.Shows(nil, nil), false, "nothing known: hidden")
end)

T.Case("UIBar: colour roles, the /mfd bar words and the status line", function()
    local Bar = ns.UIBar
    T.Eq(Bar.Role({ stale = true }), "warn", "stale is amber")
    T.Eq(Bar.Role({ stale = true, enabled = false }), "bad", "off is red, stale or not")
    T.Eq(Bar.Role({ canMark = false }), "bad", "no right to mark is red")
    T.Eq(Bar.Role({}), nil, "otherwise the button's own colour")

    T.Eq(Bar.Parse("").action, "toggle", "nothing toggles")
    T.Eq(Bar.Parse(" Hide ").action, "hide", "hide, any case")
    T.Eq(Bar.Parse("solo on").arg, true, "solo on")
    T.Eq(Bar.Parse("solo off").arg, false, "solo off")
    T.Eq(Bar.Parse("solo").arg, nil, "solo alone flips")
    T.Eq(Bar.Parse("dance").action, "refuse", "an unknown word")

    local text, role = Bar.Status({ built = true, count = 3, key = "Ctrl-1" })
    T.Eq(text, "Mark pack: 3 names, key Ctrl-1.", "the normal line")
    T.Eq(role, "good", "in green")
    T.Eq(select(2, Bar.Status({ built = true, count = 3 })), "warn", "no key is amber")
    T.True(Bar.Status({ built = true, count = 1, key = "Ctrl-1", stale = true }):find("Stale", 1, true) ~= nil, "stale says so")
    T.True(Bar.Status({ built = true, count = 9, dropped = 2, key = "K" }):find("2 did not fit", 1, true) ~= nil, "dropped")
    T.Eq(select(2, Bar.Status({ built = false })), "warn", "not built yet")
    T.Eq(select(2, Bar.Status({ enabled = false, built = true })), "bad", "off is red")
end)
