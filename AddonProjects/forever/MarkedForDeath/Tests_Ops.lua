local addonName, ns = ...

--[[
Tests_Ops: the ops lane's cases, Conflicts and CombatLog's pure halves.
Owned by lane H (ops). Every case builds its own tables; none touches the saved ones or
the real globals.
]]

local T = ns.Tests
local Conflicts = ns.Conflicts
local CombatLog = ns.CombatLog

local function Has(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local function Addons(found)
    local names = {}
    for i, row in ipairs(found) do names[i] = row.addon .. "/" .. row.topic end
    return table.concat(names, ";")
end

-- MFD's own settings: marking on, logging on with one listed instance.
local function Mine(overrides)
    local s = { enabled = true, logCombat = { enabled = true, instances = { ["i:409"] = true } } }
    for k, v in pairs(overrides or {}) do s[k] = v end
    return s
end

-- An EllesmereUI central table with one child's profile slice.
local function Ellesmere(folder, slice, extra)
    local db = { activeProfile = "Raid", profiles = { Raid = { addons = { [folder] = slice } } } }
    for k, v in pairs(extra or {}) do db[k] = v end
    return db
end

--------------------------------------------------------------------------------
-- Conflicts
--------------------------------------------------------------------------------

T.Case("Conflicts.Find: nothing installed finds nothing", function()
    T.Eq(#Conflicts.Find({}, Mine()), 0, "an empty globals table")
    T.Eq(#Conflicts.Find(nil, Mine()), 0, "no globals at all")
    T.Eq(Conflicts.Headline({}), nil, "no headline")
    T.Eq(#Conflicts.Lines({}), 0, "no lines")
end)

T.Case("Conflicts.Find: EllesmereUI auto logging on and off", function()
    local g = { EllesmereUIQoLDB = {}, EllesmereUIDB = { autoLogging = { enabled = true } } }
    T.Eq(Addons(Conflicts.Find(g, Mine())), "EllesmereUI Quality of Life/combat logging", "on is found")
    g.EllesmereUIDB.autoLogging.enabled = false
    T.Eq(#Conflicts.Find(g, Mine()), 0, "off is not")
    g.EllesmereUIDB.autoLogging = {}
    T.Eq(#Conflicts.Find(g, Mine()), 0, "an unset switch is its default, off")
    g.EllesmereUIDB.autoLogging.enabled = true
    g.EllesmereUIQoLDB = nil
    T.Eq(#Conflicts.Find(g, Mine()), 0, "the QoL module not loaded: its setting is not acting")
end)

T.Case("Conflicts.Find: a logging overlap only counts while MFD has somewhere to log", function()
    local g = { EllesmereUIQoLDB = {}, EllesmereUIDB = { autoLogging = { enabled = true } } }
    T.Eq(#Conflicts.Find(g, Mine({ logCombat = { enabled = true, instances = {} } })), 0,
        "the shipped default, nothing listed, overlaps nothing")
    T.Eq(#Conflicts.Find(g, Mine({ logCombat = { enabled = false, instances = { ["i:409"] = true } } })), 0,
        "logging switched off overlaps nothing")
    T.Eq(#Conflicts.Find(g, nil), 1, "no settings given reports every row")
end)

T.Case("Conflicts.Find: EllesmereUI Raid Tools by mode, in the active profile", function()
    local g = { EllesmereUIQoLDB = {}, EllesmereUIDB = Ellesmere("EllesmereUIQoL", { raidTools = { mode = "raid" } }) }
    local found = Conflicts.Find(g, Mine())
    T.Eq(Addons(found), "EllesmereUI Quality of Life/raid icons", "a mode other than never is found")
    T.Eq(found[1].quiet, true, "as a quiet row")
    T.Eq(#Conflicts.Loud(found), 0, "so login stays silent about it")
    g.EllesmereUIDB.profiles.Raid.addons.EllesmereUIQoL.raidTools.mode = "never"
    T.Eq(#Conflicts.Find(g, Mine()), 0, "never is not")
    g.EllesmereUIDB.profiles.Raid.addons.EllesmereUIQoL.raidTools.mode = "always"
    g.EllesmereUIDB.activeProfile = "Other"
    T.Eq(#Conflicts.Find(g, Mine()), 0, "another profile's setting is not the one acting")
    T.Eq(#Conflicts.Find(g, Mine({ enabled = false })), 0, "MFD off: an icon overlap does not matter")
end)

T.Case("Conflicts.Find: EllesmereUI Quickdraw only with an icon slot and the palette on", function()
    local slice = { enabled = true, palettes = { { slots = { { kind = "spell", id = 1 }, { kind = "raidtarget", id = 8 } } } } }
    local g = { EllesmereUIQuickdrawDB = {}, EllesmereUIDB = Ellesmere("EllesmereUIQuickdraw", slice) }
    T.Eq(Addons(Conflicts.Find(g, Mine())), "EllesmereUI Quickdraw/raid icons", "an icon slot is found")
    slice.palettes[1].slots[2].kind = "worldmarker"
    T.Eq(#Conflicts.Find(g, Mine()), 0, "world markers are not raid icons")
    slice.palettes[2] = { slots = { { kind = "clearmarkers" } } }
    T.Eq(#Conflicts.Find(g, Mine()), 1, "a clear-all slot in any palette is")
    slice.enabled = false
    T.Eq(#Conflicts.Find(g, Mine()), 0, "the palette off is not")
    slice.enabled, slice.palettes = true, "garbage"
    T.Eq(#Conflicts.Find(g, Mine()), 0, "a palettes field of the wrong type is read as none")
end)

T.Case("Conflicts.Find: Forever Dungeon Journal when loaded, MRT rows by switch", function()
    T.Eq(Addons(Conflicts.Find({ ForeverDungeonJournalDB = {} }, Mine())), "Forever Dungeon Journal/raid icons",
        "the journal loaded is listed")
    local g = { VMRT = { MarksSimple = { autoMarkEnabled = true, buffMarkEnabled = false }, Logging = { enabled = true } } }
    local found = Conflicts.Find(g, Mine())
    T.Eq(#found, 2, "automarker and logging")
    T.Eq(#Conflicts.Loud(found), 2, "both loud")
    g.VMRT.MarksSimple.autoMarkEnabled, g.VMRT.Logging.enabled = false, false
    T.Eq(#Conflicts.Find(g, Mine()), 0, "both off")
end)

T.Case("Conflicts.Find: a test that throws, or a garbage table, is not a finding", function()
    local known = {
        { addon = "Boom", topic = Conflicts.TOPIC_ICONS, what = "x", fix = "y", test = function() error("nope") end },
        { addon = "Yes", topic = Conflicts.TOPIC_ICONS, what = "x", fix = "y", test = function() return true end },
        { addon = "Truthy", topic = Conflicts.TOPIC_ICONS, what = "x", fix = "y", test = function() return 1 end },
    }
    T.Eq(Addons(Conflicts.Find({}, Mine(), known)), "Yes/raid icons", "only a plain true counts")
    local g = { EllesmereUIQoLDB = {}, EllesmereUIDB = { profiles = "broken", autoLogging = "broken" },
        VMRT = 7, EllesmereUIQuickdrawDB = {} }
    T.Eq(#Conflicts.Find(g, Mine()), 0, "wrong types everywhere read as nothing")
end)

T.Case("Conflicts.Headline and Lines: topics named once, one line a row", function()
    local found = Conflicts.Find({
        ForeverDungeonJournalDB = {},
        VMRT = { MarksSimple = { autoMarkEnabled = true }, Logging = { enabled = true } },
    }, Mine())
    T.Eq(Conflicts.Headline(found), "another addon is also handling raid icons and combat logging:", "two topics")
    local lines = Conflicts.Lines(found)
    T.Eq(#lines, 3, "a line per row")
    T.True(lines[1]:find("^Forever Dungeon Journal: ") ~= nil, "led by the addon")
    T.True(Has(lines, "Fix: /mrt, Logging"), "with its fix")
    T.True(Conflicts.HasTopic(found, Conflicts.TOPIC_ICONS), "a marker addon is active")
    T.Eq(Conflicts.HasTopic(Conflicts.Find({}, Mine()), Conflicts.TOPIC_ICONS), false, "and none when none is")
    T.Eq(Conflicts.Headline({ found[1] }), "another addon is also handling raid icons:", "one topic")
end)

--------------------------------------------------------------------------------
-- CombatLog
--------------------------------------------------------------------------------

T.Case("CombatLog.InstanceKey: instance, open world, unreadable", function()
    T.Eq(CombatLog.InstanceKey("raid", 409), "i:409", "a raid")
    T.Eq(CombatLog.InstanceKey("party", 36), "i:36", "a dungeon")
    T.Eq(CombatLog.InstanceKey("none", 0), "open", "the open world")
    T.Eq(CombatLog.InstanceKey(nil, 409), nil, "no type is not decided")
    T.Eq(CombatLog.InstanceKey("raid", nil), nil, "no id is not decided")
end)

T.Case("CombatLog.ShouldLog: listed instances only, off by default", function()
    local Schema = ns.Schema
    local db = Schema.Boot({})
    T.Eq(CombatLog.ShouldLog("i:409", db.settings.logCombat), false, "a fresh install logs nowhere")
    T.Eq(CombatLog.HasWork(db.settings.logCombat), false, "and has no work, so nothing listens")

    local s = { enabled = true, instances = { ["i:409"] = true, open = true } }
    T.Eq(CombatLog.ShouldLog("i:409", s), true, "a listed instance")
    T.Eq(CombatLog.ShouldLog("i:249", s), false, "an unlisted one")
    T.Eq(CombatLog.ShouldLog("open", s), false, "the open world never, even listed")
    T.Eq(CombatLog.ShouldLog(nil, s), false, "an unknown place never")
    s.enabled = false
    T.Eq(CombatLog.ShouldLog("i:409", s), false, "the switch off")
    T.Eq(CombatLog.HasWork(s), false, "no work while off")
    T.Eq(CombatLog.ShouldLog("i:409", nil), false, "no settings")
    T.Eq(CombatLog.HasWork({ enabled = true, instances = { open = true } }), false, "open alone is no work")
end)

T.Case("CombatLog.Decide: start, adopt, stop, and leave alone", function()
    T.Eq(CombatLog.Decide(true, false, false), "start", "should and not logging")
    T.Eq(CombatLog.Decide(true, true, false), "adopt", "after a reload inside")
    T.Eq(CombatLog.Decide(true, true, true), nil, "already ours")
    T.Eq(CombatLog.Decide(false, true, true), "stop", "ours, on the way out")
    T.Eq(CombatLog.Decide(false, true, false), nil, "someone else's log is left alone")
    T.Eq(CombatLog.Decide(false, false, false), nil, "nothing to do")
end)

T.Case("CombatLog.WhenToCheck: at the pull, and after combat only while waiting", function()
    local calm, fight = { combat = false }, { combat = true }
    T.Eq(CombatLog.WhenToCheck(calm, fight, false), "pull", "combat begins")
    T.Eq(CombatLog.WhenToCheck(nil, fight, false), "pull", "first state already in combat")
    T.Eq(CombatLog.WhenToCheck(fight, { combat = true, secure = true }, false), nil,
        "the lock arriving seconds later is not a second pull")
    T.Eq(CombatLog.WhenToCheck(fight, calm, true), "after", "combat ends with a check waiting")
    T.Eq(CombatLog.WhenToCheck(fight, calm, false), nil, "and without one, nothing")
    T.Eq(CombatLog.WhenToCheck(calm, { combat = false, chat = true }, true), nil, "other changes are not pulls")
    T.Eq(CombatLog.WhenToCheck(calm, nil, false), nil, "no state")
end)

T.Case("CombatLog.Command: status, on, off, here toggles, refusals", function()
    local s = { enabled = true, instances = { ["i:409"] = true } }
    T.Eq(CombatLog.Command("", { key = "i:409", settings = s }).action, "status", "bare")
    T.Eq(CombatLog.Command("  ON ", {}).action, "enable", "on, any case")
    T.Eq(CombatLog.Command("off", {}).action, "disable", "off")
    local plan = CombatLog.Command("here", { key = "i:409", settings = s })
    T.Eq(plan.action .. " " .. plan.key, "remove i:409", "a listed instance is taken off")
    plan = CombatLog.Command("here", { key = "i:249", settings = s })
    T.Eq(plan.action .. " " .. plan.key, "add i:249", "an unlisted one is added")
    T.Eq(CombatLog.Command("here", { key = "open", settings = s }).action, "refuse", "not the open world")
    T.Eq(CombatLog.Command("here", { settings = s }).action, "refuse", "not an unknown place")
    T.True(CombatLog.Command("sideways", {}).why:find("/mfd combatlog here", 1, true) ~= nil, "unknown word says the usage")
    T.Eq(CombatLog.Command(nil, nil).action, "status", "no text at all")
end)

T.Case("CombatLog.StatusLines: says what is off and how to turn it on", function()
    local off = CombatLog.StatusLines({ settings = { enabled = false, instances = {} }, key = "open", isLogging = false })
    T.True(off[1]:find("/mfd combatlog on", 1, true) ~= nil, "off names the command")
    T.True(off[2]:find("open world, never logged", 1, true) ~= nil, "and where we are")

    local empty = CombatLog.StatusLines({ settings = { enabled = true, instances = {} }, key = "i:409", isLogging = false })
    T.True(empty[1]:find("no instance listed", 1, true) ~= nil, "the shipped default")
    T.True(empty[1]:find("/mfd combatlog here", 1, true) ~= nil, "and how to list one")
    T.Eq(Has(empty, CombatLog.CAVEAT), false, "no caveat with nothing listed")

    local on = CombatLog.StatusLines({ settings = { enabled = true, instances = { ["i:409"] = true } },
        key = "i:409", name = "Molten Core", isLogging = true, isOurs = true, waiting = true })
    T.True(on[1]:find("1 instance listed", 1, true) ~= nil, "a count")
    T.True(on[2]:find("Molten Core, i:409): listed", 1, true) ~= nil, "here, named and listed")
    T.True(on[2]:find("opened by MFD", 1, true) ~= nil, "whose log it is")
    T.True(Has(on, "tried again when combat ends"), "a refused switch is said")
    T.True(Has(on, CombatLog.CAVEAT), "the empty-file caveat while anything is listed")

    local other = CombatLog.StatusLines({ settings = { enabled = true, instances = {} }, key = "i:36", isLogging = true })
    T.True(other[2]:find("someone else", 1, true) ~= nil, "a log nobody here opened is left alone")
    local unknown = CombatLog.StatusLines({ settings = { enabled = true, instances = {} } })
    T.True(unknown[2]:find("not known yet", 1, true) ~= nil, "an unknown place says so")
end)

T.Case("CombatLog.View: the client's answer and the session state, for the settings tab", function()
    local ours, waiting = CombatLog.isOurs, CombatLog.waiting
    CombatLog.isOurs, CombatLog.waiting = true, false
    local v = CombatLog.View(function() return true end)
    T.Eq(v.isLogging, true, "logging")
    T.Eq(v.isOurs, true, "ours")
    T.Eq(v.waiting, false, "not waiting")
    CombatLog.isOurs, CombatLog.waiting = nil, 1
    v = CombatLog.View(function() return false end)
    T.Eq(v.isLogging, false, "not logging")
    T.Eq(v.isOurs, false, "an unset flag reads false")
    T.Eq(v.waiting, false, "only a real true counts")
    T.Eq(CombatLog.View(function() return nil end).isLogging, nil, "unreadable stays nil")
    T.Eq(CombatLog.View(function() return 1 end).isLogging, false, "a non-boolean answer is not logging")
    -- No reader: the client read, which headless has no LoggingCombat for, so it will not say.
    T.Eq(CombatLog.View().isLogging, nil, "no client, not readable")

    -- Merged the way the settings tab does it.
    local view = { settings = { enabled = true, instances = { ["i:409"] = true } }, key = "i:409" }
    for k, val in pairs(CombatLog.View(function() return true end)) do view[k] = val end
    local lines = CombatLog.StatusLines(view)
    CombatLog.isOurs, CombatLog.waiting = ours, waiting
    T.True(lines[2]:find("opened by someone else", 1, true) ~= nil, "a merged view fills the logging line")
    T.True(lines[3]:find("late", 1, true) ~= nil, "the late-file caveat")
end)
