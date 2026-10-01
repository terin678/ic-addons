local addonName, ns = ...

-- The kit's own cases: run headless with scripts/run-tests.ps1 -Flavor forever -Addon ICKit
-- and in game with /ickit test. Every function in a pure layer has one here.

local T = ns.Tests
local Util = ns.Util

--------------------------------------------------------------------------------
-- LibICUtil
--------------------------------------------------------------------------------

T.Case("Util.Trim: whitespace off both ends, the middle kept", function()
    T.Eq(Util.Trim("  raid prep \t"), "raid prep", "both ends")
    T.Eq(Util.Trim("a  b"), "a  b", "inner spaces are the text's own")
    T.Eq(Util.Trim(nil), "", "nothing is the empty string")
    T.Eq(Util.Trim(42), "42", "a number is read as its text")
end)

T.Case("Util.StripEscapes: colours, links and textures out, the words kept", function()
    T.Eq(Util.StripEscapes("|cffff0000red|r"), "red", "a colour")
    T.Eq(Util.StripEscapes("buy |Hitem:123|h[Felweed]|h now"), "buy [Felweed] now", "a link keeps its label")
    T.Eq(Util.StripEscapes("x |TInterface\\Icons\\foo:16|t y"), "x  y", "an inline texture")
    T.Eq(Util.StripEscapes("plain"), "plain", "plain text is untouched")
end)

T.Case("Util.Truncate: cut to bytes, never mid-character or mid-escape", function()
    T.Eq(Util.Truncate("checklist", 5), "check", "plain text cuts where asked")
    T.Eq(Util.Truncate("short", 40), "short", "already short enough")
    -- "é" is two bytes; a cut landing between them backs off to the character before
    T.Eq(Util.Truncate("caf\195\169s", 4), "caf", "a split two-byte character is dropped whole")
    T.Eq(Util.Truncate("caf\195\169s", 5), "caf\195\169", "and kept whole when it fits")
    T.Eq(Util.Truncate("|cffff0000danger|r", 14), "|cffff0000dang|r", "an open colour is closed")
end)

T.Case("Util.Clean: what a person typed, made safe to store and draw", function()
    T.Eq(Util.Clean("  buy   20 |cff00ff00herbs|r  "), "buy 20 herbs", "trimmed, squeezed, colour off")
    T.Eq(Util.Clean("a|b"), "ab", "a stray pipe cannot start an escape")
    T.Eq(Util.Clean("line one\nline two"), "line one line two", "a line break becomes a space")
    T.Eq(Util.Clean("abcdefghij", 4), "abcd", "cut to the length asked for")
    T.Eq(Util.Clean(nil), "", "nothing in, nothing out")
end)

T.Case("Util.Plural: one line, two lines", function()
    T.Eq(Util.Plural(1, "line"), "line", "one")
    T.Eq(Util.Plural(0, "line"), "lines", "none takes the plural")
    T.Eq(Util.Plural(2, "entry", "entries"), "entries", "an irregular plural is given")
end)

T.Case("Util.SortedKeys: the same order every time, numbers by value", function()
    local keys = Util.SortedKeys({ b = 1, a = 2, [10] = 3, [2] = 4 })
    T.Eq(#keys, 4, "every key")
    T.Eq(keys[1], 2, "numbers first, by value not by text")
    T.Eq(keys[2], 10, "so 2 comes before 10")
    T.Eq(keys[3], "a", "then strings")
    T.Eq(keys[4], "b", "in order")
    T.Eq(#Util.SortedKeys(nil), 0, "no table, no keys")
end)

T.Case("Util.DeepCopy: a copy that shares nothing", function()
    local original = { title = "todo", lines = { { text = "one", done = false } } }
    local copy = Util.DeepCopy(original)
    copy.lines[1].done = true
    copy.title = "changed"
    T.Eq(original.lines[1].done, false, "the nested table is its own")
    T.Eq(original.title, "todo", "and so is the top")
    T.Eq(Util.DeepCopy(7), 7, "a plain value is itself")
end)

T.Case("Util.Clamp: held inside the bounds, and safe on a missing value", function()
    T.Eq(Util.Clamp(5, 1, 10), 5, "inside")
    T.Eq(Util.Clamp(-3, 1, 10), 1, "below")
    T.Eq(Util.Clamp(99, 1, 10), 10, "above")
    T.Eq(Util.Clamp(nil, 1, 10), 1, "nothing lands on the low end")
    T.Eq(Util.Clamp("7", 1, 10), 7, "a number in text is read")
end)

T.Case("Util.Move: one element reordered, the rest shifted", function()
    local list = { "a", "b", "c", "d" }
    T.Eq(Util.Move(list, 1, 3), true, "first to third")
    T.Eq(table.concat(list), "bcad", "the two between shift up")
    T.Eq(Util.Move(list, 4, 1), true, "last to first")
    T.Eq(table.concat(list), "dbca", "the rest shift down")
    T.Eq(Util.Move(list, 2, 2), false, "a move to where it is does nothing")
    T.Eq(Util.Move(list, 0, 2), false, "an index off the front is refused")
    T.Eq(Util.Move(list, 2, 5), false, "and off the end")
    T.Eq(Util.Move(list, "1", 2), false, "and one that is not a number")
    T.Eq(table.concat(list), "dbca", "none of which changed the list")
end)

--------------------------------------------------------------------------------
-- LibICTest, run against a registry of its own
--------------------------------------------------------------------------------

T.Case("Test: a failing case is counted and named, a passing one is not", function()
    local Test = LibStub("LibICTest-1.0")
    local lines, done = {}, nil
    local inner = Test.New({
        print = function(line) lines[#lines + 1] = line end,
        onDone = function(result) done = result end,
    })
    inner.Case("fine", function() inner.Eq(1, 1, "one") end)
    inner.Case("broken", function() inner.Eq(1, 2, "one") end)
    inner.Case("near", function() inner.Near(0.3, 0.1 + 0.2, "a float sum") end)

    local pass, fail = inner.Run()
    T.Eq(pass, 2, "two passed")
    T.Eq(fail, 1, "one failed")
    T.Eq(#lines, 2, "one line for the failure and one for the summary")
    T.Eq(done.passed, 2, "the result carries the counts")
    T.Eq(done.failures[1].name, "broken", "and names what failed")
    T.True(done.failures[1].err:find("one: expected [2], got [1]", 1, true), "with what was expected")
end)

T.Case("Test: True and Near say what they wanted", function()
    local inner = LibStub("LibICTest-1.0").New({ print = function() end })
    local ok, err = pcall(inner.True, false, "the flag")
    T.Eq(ok, false, "a false value raises")
    T.True(err:find("the flag: expected true", 1, true), "naming the label")
    ok, err = pcall(inner.Near, 1.5, 1, 0.1, "the ratio")
    T.Eq(ok, false, "outside the tolerance raises")
    T.True(err:find("give or take 0.1", 1, true), "naming the tolerance")
    T.Eq(pcall(inner.Near, 1.05, 1, 0.1, "the ratio"), true, "inside it passes")
end)

--------------------------------------------------------------------------------
-- LibICEnv
--------------------------------------------------------------------------------

local Env = LibStub("LibICEnv-1.0")

T.Case("Env.Resolve and Has: a dotted path under a root, or missing", function()
    local root = { C_Timer = { After = function() end }, GameFontNormal = {}, count = 3 }
    T.Eq(type(Env.Resolve("C_Timer.After", root)), "function", "two steps down")
    T.Eq(Env.Resolve("C_Timer.NewTicker", root), nil, "the last step missing")
    T.Eq(Env.Resolve("Nope.At.All", root), nil, "the first step missing")
    T.Eq(Env.Resolve("count.more", root), nil, "a path through a number stops")
    T.Eq(Env.Resolve("", root), nil, "no path is no value")
    local present, kind = Env.Has("GameFontNormal", root)
    T.Eq(present, true, "present")
    T.Eq(kind, "table", "and what it is")
    present, kind = Env.Has("EasyMenu", root)
    T.Eq(present, false, "absent")
    T.Eq(kind, "missing", "said plainly")
end)

T.Case("Env.Probe: one row per check, plain or with a reason", function()
    local root = { C_Timer = { After = function() end }, count = 3 }
    local rows = Env.Probe({ "count", { "C_Timer.After", "delays" }, { "EasyMenu", "menus" } }, root)
    T.Eq(#rows, 3, "a row each")
    T.Eq(rows[1].path, "count", "a bare path")
    T.Eq(rows[1].kind, "number", "with its kind")
    T.Eq(rows[2].present, true, "a function two steps down")
    T.Eq(rows[2].why, "delays", "carrying why the addon cares")
    T.Eq(rows[3].present, false, "and one that is not there")
    T.Eq(#Env.Probe(nil, root), 0, "no checks, no rows")
end)

T.Case("Env.Build: the client's answers as a table, and a client that gives none", function()
    local b = Env.Build(function() return "1.60.1", "70124", "Sep 30 2026", 16001 end)
    T.Eq(b.version, "1.60.1", "version")
    T.Eq(b.build, "70124", "build")
    T.Eq(b.interface, 16001, "the interface as a number")
    b = Env.Build(function() end)
    T.Eq(b.version, "?", "nothing answered")
    T.Eq(b.interface, 0, "is zero, not an error")
    T.Eq(Env.Build().interface, 16001, "and the client this is running on is the Forever one")
end)

T.Case("Env.Try: an answer, several answers, or the error", function()
    local t = Env.Try("sum", function(a, b) return a + b end, 2, 3)
    T.Eq(t.ok, true, "it ran")
    T.Eq(t.values[1], 5, "with its return")
    T.Eq(t.text, "5", "and that as text")
    t = Env.Try("several", function() return "a", nil, 3 end)
    T.Eq(t.n, 3, "a nil in the middle is still counted")
    T.Eq(t.text, "a, nil, 3", "and shown")
    t = Env.Try("boom", function() error("no such thing") end)
    T.Eq(t.ok, false, "an error is caught")
    T.True(t.err:find("no such thing", 1, true), "and kept")
    T.Eq(Env.Try("nothing", nil).err, "not a function", "asking nothing is said to be so")
end)

T.Case("Env.Wrap: calls and time are counted, the function behaves as before", function()
    local now, step = 0, 5
    Env.SetClock(function() return now end)
    local add = Env.Wrap("case: adder", function(a, b)
        now = now + step
        return a + b, "extra"
    end)
    local sum, extra = add(1, 2)
    step = 7
    add(3, 4)
    local thrower = Env.Wrap("case: thrower", function() error("bang") end)
    local ok = pcall(thrower)
    Env.SetClock(nil)

    T.Eq(sum, 3, "the first return")
    T.Eq(extra, "extra", "and the second")
    T.Eq(ok, false, "an error still reaches the caller")
    local byLabel = {}
    for _, row in ipairs(Env.Counters()) do byLabel[row.label] = row end
    T.Eq(byLabel["case: adder"].calls, 2, "two calls")
    T.Near(byLabel["case: adder"].total, 12, "five and seven milliseconds")
    T.Near(byLabel["case: adder"].max, 7, "the slower of the two")
    T.Eq(byLabel["case: thrower"].calls, 1, "the call that raised is counted")
end)

--------------------------------------------------------------------------------
-- LibICStore
--------------------------------------------------------------------------------

local Store = LibStub("LibICStore-1.0")

T.Case("Store.ApplyDefaults: fills what is missing, keeps what is there, false included", function()
    local saved = { settings = { debug = true, locked = false }, title = "mine" }
    Store.ApplyDefaults(saved, { settings = { debug = false, locked = true, scale = 1 }, title = "default", notes = {} })
    T.Eq(saved.settings.debug, true, "a stored true is kept")
    T.Eq(saved.settings.locked, false, "and so is a stored false")
    T.Eq(saved.settings.scale, 1, "a missing field appears")
    T.Eq(saved.title, "mine", "a stored string is kept")
    T.Eq(type(saved.notes), "table", "a missing table appears")
end)

T.Case("Store.Migrate: steps run in order from the saved schema, a fresh table runs none", function()
    local order = {}
    local steps = {
        [1] = function(db) order[#order + 1] = 1; db.renamed, db.old = db.old, nil end,
        [2] = function() order[#order + 1] = 2 end,
    }
    local db = { schema = 1, old = "kept" }
    T.Eq(Store.Migrate(db, steps, 3), 2, "two steps from schema 1 to 3")
    T.Eq(table.concat(order), "12", "in order")
    T.Eq(db.schema, 3, "ending at the head")
    T.Eq(db.renamed, "kept", "the step read the old shape")

    local fresh = {}
    T.Eq(Store.Migrate(fresh, steps, 3), 0, "an empty table is a fresh install")
    T.Eq(fresh.schema, 3, "and starts at the head")

    local unstamped = { old = "x" }
    T.Eq(Store.Migrate(unstamped, steps, 3), 2, "data with no stamp is schema 1")
    T.Eq(Store.Migrate({ schema = 3 }, steps, 3), 0, "already at the head runs nothing")
end)

T.Case("Store.Boot: a fresh install, a returning one, and a file that did not load", function()
    local spec = {
        account = "XDB", character = "XCharDB", schema = 2,
        defaults = { settings = { debug = false }, loads = 0 },
        charDefaults = { loads = 0 },
        migrations = { [1] = function(db) db.renamed, db.old = db.old, nil end },
    }

    local globals = {}
    local db, cdb, info = Store.Boot(spec, globals)
    T.Eq(info.sawFile, false, "nothing came back")
    T.Eq(info.firstRun, true, "and this character never ran it: a first run")
    T.Eq(info.lost, false, "not a lost file")
    T.Eq(db.schema, 2, "a fresh table starts at the head")
    T.Eq(db.settings.debug, false, "with its defaults")
    T.Eq(globals.XDB, db, "published where the client will save it")
    T.Eq(cdb.everRan, true, "and the character remembers")

    globals = {
        XDB = { schema = 1, old = "kept", settings = { debug = true } },
        XCharDB = { everRan = true, loads = 4 },
    }
    db, cdb, info = Store.Boot(spec, globals)
    T.Eq(info.sawFile, true, "the file was there")
    T.Eq(info.firstRun, false, "so not a first run")
    T.Eq(info.migrated, 1, "one step ran")
    T.Eq(db.renamed, "kept", "before the defaults, on the old shape")
    T.Eq(db.settings.debug, true, "a saved setting survives")
    T.Eq(db.loads, 0, "a field added since appears")
    T.Eq(cdb.loads, 4, "the character's own data is untouched")

    globals = { XCharDB = { everRan = true } }
    db, cdb, info = Store.Boot(spec, globals)
    T.Eq(info.lost, true, "an empty account beside a character that has run: the file did not load")
    T.Eq(info.firstRun, false, "which is not a first run")

    db, cdb, info = Store.Boot({ account = "YDB" }, {})
    T.Eq(cdb, nil, "an addon with no character table gets none")
    T.Eq(info.firstRun, true, "and an empty account is all it can go on")
end)

T.Case("Store.Register: the kit's own tables arrived through it", function()
    T.True(ns.db ~= nil, "the account table")
    T.True(ns.cdb ~= nil, "the character table")
    T.Eq(ns.db.schema, 1, "stamped")
    T.True(ns.db.loads >= 1, "this load was counted")
    T.Eq(ns.cdb.everRan, true, "and the character remembers running it")
    T.Eq(ns.events[1], "ADDON_LOADED", "with the saved tables in hand at the first event")
end)

--------------------------------------------------------------------------------
-- LibICConsole
--------------------------------------------------------------------------------

local Console = LibStub("LibICConsole-1.0")

T.Case("Console.Parse: the first word lower-cased, the rest trimmed", function()
    local cmd, rest = Console.Parse("  New   Raid prep  ")
    T.Eq(cmd, "new", "the command, whatever its case")
    T.Eq(rest, "Raid prep", "the rest as typed, ends trimmed")
    cmd, rest = Console.Parse("PROBE")
    T.Eq(cmd, "probe", "a lone word")
    T.Eq(rest, "", "has no rest")
    cmd, rest = Console.Parse(nil)
    T.Eq(cmd, "", "nothing typed is the bare command")
    T.Eq(rest, "", "with no rest")
end)

T.Case("Console.New: every line carries the prefix, debug lines only when asked", function()
    local lines, debugOn = {}, false
    local chat = { AddMessage = function(_, msg) lines[#lines + 1] = msg end }
    local o = Console.New("Kit", {
        color = "ffffff",
        frame = function() return chat end,
        debug = function() return debugOn end,
    })
    o.Print("hello")
    o.Printf("%d notes", 3)
    o.Debug("quiet %s", "line")
    T.Eq(#lines, 2, "the debug line stayed quiet")
    T.Eq(lines[1], "|cffffffffKit|r: hello", "prefixed and coloured")
    T.Eq(lines[2], "|cffffffffKit|r: 3 notes", "formatted")
    debugOn = true
    o.Debug("loud %s", "line")
    T.True(lines[3]:find("loud line", 1, true), "and prints once debug is on")
end)

T.Case("Console.Dispatcher: a known word runs its command, anything else prints help", function()
    local said, got = {}, nil
    local handle = Console.Dispatcher({
        slash = { "/kit" },
        out = { Print = function(msg) said[#said + 1] = msg end },
        help = { { "", "the status" }, { "new [title]", "start a note" } },
        commands = {
            [""] = function() got = "bare" end,
            new = function(rest, cmd) got = cmd .. ":" .. rest end,
        },
    })
    handle("")
    T.Eq(got, "bare", "nothing typed runs the bare command")
    handle("NEW Raid prep")
    T.Eq(got, "new:Raid prep", "a command gets its word and the rest")
    handle("nonsense")
    T.Eq(said[1], "commands:", "an unknown word prints the help")
    T.Eq(#said, 3, "one line per row under the heading")
    T.True(said[2]:find("/kit|r", 1, true), "the bare command shown without a trailing space")
    T.True(said[3]:find("/kit new [title]", 1, true), "and a sub-command with its arguments")
    T.Eq(#Console.HelpLines("/kit", nil), 0, "no rows, no lines")
end)

--------------------------------------------------------------------------------
-- The addon itself
--------------------------------------------------------------------------------

T.Case("Kit: the build and the login lines", function()
    local build = { version = "1.60.1", build = "70124", interface = 16001 }
    T.Eq(ns.DescribeBuild(build), "1.60.1 (70124), interface 16001", "version, build and interface")
    T.Eq(ns.DescribeBuild(nil), "? (?), interface ?", "a client that answers nothing is still described")

    local lines = ns.LoadLines("0.2.0", build, { sawFile = true })
    T.Eq(#lines, 1, "an ordinary load is one line")
    T.Eq(lines[1], "v0.2.0 on 1.60.1 (70124), interface 16001. /ickit help lists commands.", "saying what loaded")
    lines = ns.LoadLines("0.2.0", build, { firstRun = true })
    T.Eq(lines[2], "first run on this account.", "a first run says so")
    lines = ns.LoadLines("0.2.0", build, { lost = true })
    T.Eq(#lines, 3, "a lost file is said twice over")
    T.True(lines[2]:find("did not load", 1, true), "what happened")
    T.True(lines[3]:find("Restart the client", 1, true), "and what to do before logging out")
    lines = ns.LoadLines("0.2.0", build, nil)
    T.True(lines[2]:find("never arrived", 1, true), "and tables that never came are not passed over")
end)

T.Case("Kit: the profile report", function()
    local lines = ns.ProfileLines({}, nil, nil, "unavailable")
    T.Eq(lines[2], "  nothing has run yet.", "no handlers yet")
    T.Eq(lines[3], "memory: this client does not say.", "no memory figure")
    T.Eq(lines[4], "client CPU figure: unavailable.", "no CPU figure")

    lines = ns.ProfileLines({
        { label = "ICKit events", calls = 2, total = 1.5, max = 1 },
        { label = "ICKit saved variables", calls = 1, total = 0.25, max = 0.25 },
    }, 123.4, 12.34, "scriptProfile")
    T.Eq(lines[2], "  ICKit events: 2 calls, 1.50 ms in total, 1.00 ms at worst", "calls, total and worst")
    T.Eq(lines[3], "  ICKit saved variables: 1 call, 0.25 ms in total, 0.25 ms at worst", "one call is singular")
    T.Eq(lines[4], "memory: 123 KB", "memory rounded")
    T.True(lines[5]:find("12.3 ms (scriptProfile", 1, true), "and the client's CPU figure with its source")
end)

T.Case("Probe.Summary: counts, and names what is missing", function()
    local lines = ns.Probe.Summary({
        build = { version = "1.60.1", build = "70124", interface = 16001 },
        has = { CreateFrame = "function", EasyMenu = false, ["C_Timer.After"] = "function" },
        templates = { BackdropTemplate = true, NopeTemplate = "Couldn't find inherited node" },
        methods = { ["Texture.SetColorTexture"] = true },
        scripts = { ["EditBox.OnEnterPressed"] = false },
        events = { "ADDON_LOADED", "PLAYER_LOGIN" },
    })
    T.Eq(lines[1], "client probe on 1.60.1 (70124), interface 16001:", "which client")
    T.Eq(lines[2], "  2 of 3 globals present.", "the globals")
    T.True(lines[3]:find("EasyMenu", 1, true), "naming the missing one")
    T.Eq(lines[4], "  1 of 2 templates usable.", "the templates")
    T.True(lines[5]:find("NopeTemplate", 1, true), "naming the refused one")
    T.Eq(lines[6], "  1 of 1 methods usable.", "the methods, with nothing to name")
    T.Eq(lines[7], "  0 of 1 script handlers usable.", "the script handlers")
    T.True(lines[8]:find("EditBox.OnEnterPressed", 1, true), "naming the missing one")
    T.True(lines[9]:find("ADDON_LOADED, PLAYER_LOGIN", 1, true), "and the load order")
    T.Eq(#ns.Probe.Summary({}), 5, "an empty report is five quiet lines")
end)

T.Case("Probe.Run: every question is asked and the report holds together", function()
    local report = ns.Probe.Run()
    T.Eq(report.build.interface, 16001, "the build")
    T.True(report.has.CreateFrame, "a global that must exist")
    local asked = 0
    for _ in pairs(report.has) do asked = asked + 1 end
    T.Eq(asked, #ns.Probe.CHECKS, "one answer per check")
    T.True(report.values["GetBuildInfo"] ~= nil, "the values were asked")
    T.Eq(type(report.templates.BackdropTemplate) ~= "nil", true, "the templates were tried")
    T.Eq(type(report.methods["Texture.SetColorTexture"]), "boolean", "the methods were looked for")
    T.Eq(type(ns.Probe.Summary(report)[1]), "string", "and it summarises")
end)
