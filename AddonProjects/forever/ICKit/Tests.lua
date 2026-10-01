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
-- LibICTheme
--------------------------------------------------------------------------------

local Theme = LibStub("LibICTheme-1.0")

T.Case("Theme.Register: a theme inherits every role it does not set", function()
    local base = Theme.Get(Theme.DEFAULT)
    local t = Theme.Register("Case Theme", { colors = { accent = { r = 0, g = 1, b = 0 } } })
    T.Eq(t.colors.accent.g, 1, "its own accent")
    T.Eq(t.colors.accent.a, 1, "with the alpha filled in")
    T.Eq(t.colors.ground.r, base.colors.ground.r, "the ground it did not set is the default's")
    T.Eq(t.fonts.body, "GameFontHighlightSmall", "and so are the fonts")
    T.Eq(t.logo, false, "a theme has no mark unless it names one")
    T.Eq(base.logo, false, "the default carries no guild's mark")
    T.True(Theme.Get("Impulse Control").logo:find("ICKit", 1, true), "the guild theme's mark ships in the kit's own folder")
    t.colors.ground.r = 0.5
    T.True(base.colors.ground.r ~= 0.5, "and the colours are copies, not the default's own tables")
    Theme.themes["Case Theme"] = nil
end)

T.Case("Theme.Select: listeners hear a change once, an unknown name is refused", function()
    local _, before = Theme.Current()
    local other = (before == "Paper") and "Impulse Control" or "Paper"
    local heard = {}
    local stop = Theme.OnChange(function(_, name) heard[#heard + 1] = name end)

    T.Eq(Theme.Select(other), true, "a real theme is selected")
    T.Eq(heard[1], other, "and the listener is told which")
    T.Eq(Theme.Select(other), true, "selecting it again is fine")
    T.Eq(#heard, 1, "and silent: nothing changed")
    T.Eq(Theme.Select("No Such Theme"), false, "an unknown name is refused")
    T.Eq(select(2, Theme.Current()), other, "leaving the selection where it was")

    stop()
    Theme.Select(before)
    T.Eq(#heard, 1, "a listener that stopped hears nothing more")
    T.Eq(select(2, Theme.Current()), before, "and the theme is back as it was found")
end)

T.Case("Theme: the names, a name as typed, and a colour code", function()
    T.Eq(table.concat(Theme.Names(), ","), "Forever,Impulse Control,Paper", "three ship, in order")
    T.Eq(Theme.Find("paper"), "Paper", "case does not matter")
    T.Eq(Theme.Find("  IMPULSE control "), "Impulse Control", "nor do stray spaces")
    T.Eq(Theme.Find("imp"), "Impulse Control", "the start of one name is enough")
    Theme.Register("Forest", {})
    T.Eq(Theme.Find("for"), nil, "the start of two is not")
    T.Eq(Theme.Find("forest"), "Forest", "though the whole of one still is")
    Theme.themes["Forest"] = nil
    T.Eq(Theme.Find(""), nil, "nothing typed is no theme")
    T.Eq(Theme.Find("neon"), nil, "and neither is one that does not exist")
    T.Eq(Theme.Hex({ r = 1, g = 0.82, b = 0 }), "|cffffd100", "the game's gold as a colour code")
    T.Eq(Theme.DEFAULT, "Forever", "the default is the game's own look, not a guild's")
    T.Eq(Theme.Get("Forever").colors.accent.g, 0.82, "with that gold as its accent")
end)

T.Case("Kit: a theme is saved only when it was chosen", function()
    -- Against a table of its own, and the live theme put back before anything is
    -- asserted, so a failure here cannot leave the player's theme changed.
    local _, before = Theme.Current()
    local settings = {}
    local picked = ns.SetTheme("Paper", settings)
    local savedAfterPick = settings.theme
    local refused = ns.SetTheme("Neon", settings)
    local savedAfterRefusal = settings.theme
    local back = ns.SetTheme(nil, settings)
    local savedAfterDefault = settings.theme
    Theme.Select(before)

    T.Eq(picked, "Paper", "a real theme is selected")
    T.Eq(savedAfterPick, "Paper", "and remembered")
    T.Eq(refused, nil, "an unknown one is refused")
    T.Eq(savedAfterRefusal, "Paper", "leaving the choice alone")
    T.Eq(back, Theme.DEFAULT, "no name goes back to the default")
    T.Eq(savedAfterDefault, nil, "and forgets the choice, so a later default is followed")
end)

--------------------------------------------------------------------------------
-- LibICWidgets
--------------------------------------------------------------------------------

local W = LibStub("LibICWidgets-1.0")

T.Case("Widgets: a place is a fraction of the screen, held on it", function()
    local fx, fy = W.ToFraction(480, 270, 1920, 1080)
    T.Near(fx, 0.25, "a quarter in")
    T.Near(fy, 0.25, "a quarter down")
    fx, fy = W.ToFraction(100, 100, 0, 0)
    T.Eq(fx, 0, "a screen with no size gives the corner")
    T.Eq(fy, 0, "rather than a division by zero")

    fx, fy = W.ClampFraction(0.95, -0.2, 0.1, 0.2)
    T.Near(fx, 0.9, "pulled back so the right edge stays on")
    T.Near(fy, 0, "and down from above the top")
    fx, fy = W.ClampFraction(0.5, 0.9, 0.1, 0.2)
    T.Near(fx, 0.5, "inside is left alone")
    T.Near(fy, 0.8, "the bottom edge is held too")
    fx, fy = W.ClampFraction(0.5, 0.5, 1.5, 1.5)
    T.Eq(fx, 0, "a frame bigger than the screen sits at the corner")
    T.Eq(fy, 0, "both ways")
    fx, fy = W.ClampFraction(nil, "x", 0.1, 0.1)
    T.Eq(fx, 0, "a place that was never saved is the corner")
    T.Eq(fy, 0, "not an error")
end)

T.Case("Widgets: each one builds, keeps its state, and repaints", function()
    local p = W.Panel(nil, { width = 120, height = 60, movable = true })
    p:Hide()
    T.Eq(p.icRole, "ground", "a panel is ground unless told otherwise")
    p:SetLocked(true)
    T.Eq(p.icLocked, true, "and can be pinned")

    local label = W.Label(p, "a line")
    label:SetRole("done")
    T.Eq(label.icColor, "done", "a label changes role")

    local b = W.Button(p, "ok", 60, 20, { kind = "accent" })
    b:SetKind("danger")
    T.Eq(b.icKind, "danger", "a button changes kind")

    local clicks = {}
    local box = W.CheckBox(p, { onClick = function(on) clicks[#clicks + 1] = on end })
    T.Eq(box:GetChecked(), false, "a box starts unticked")
    box:SetChecked(true)
    T.Eq(box:GetChecked(), true, "ticks when told")
    T.Eq(#clicks, 0, "without calling the click handler")
    box:GetScript("OnClick")(box)
    T.Eq(box:GetChecked(), false, "a click flips it")
    T.Eq(clicks[1], false, "and says what it became")

    local typed
    local edit = W.EditBox(p, 100, 18, { maxBytes = 40, onEnter = function(text) typed = text end })
    edit:SetText("raid prep")
    edit:GetScript("OnEnterPressed")(edit)
    T.Eq(typed, "raid prep", "Enter hands over what was typed")

    W.Repaint()
    T.Eq(box:GetChecked(), false, "and a repaint changes no state")
end)

T.Case("Widgets: a move starts on the press and ends on the release", function()
    -- Not on the client's drag event, which waits for the pointer to travel and then
    -- makes the frame jump the distance it missed.
    local drops = 0
    local p = W.Panel(nil, { width = 120, height = 60, movable = true, onMoved = function() drops = drops + 1 end })
    p:Hide()
    local down, up = p:GetScript("OnMouseDown"), p:GetScript("OnMouseUp")

    down(p, "RightButton")
    T.Eq(p.icMoving, false, "the right button moves nothing")
    down(p, "LeftButton")
    T.Eq(p.icMoving, true, "the left button starts the move at once")
    up(p, "RightButton")
    T.Eq(p.icMoving, true, "releasing another button does not end it")
    up(p, "LeftButton")
    T.Eq(p.icMoving, false, "releasing the left one does")
    T.Eq(drops, 1, "and the panel says it was dropped, once")
    up(p, "LeftButton")
    T.Eq(drops, 1, "a release with no move in progress says nothing")

    p:SetLocked(true)
    down(p, "LeftButton")
    T.Eq(p.icMoving, false, "a pinned panel does not start")

    -- A title bar drags its panel and passes a right-click on
    p:SetLocked(false)
    local clicked = 0
    local bar = W.Panel(p, { role = "raised", edge = false, height = 20 })
    W.DragHandle(bar, p, { onRightClick = function() clicked = clicked + 1 end })
    bar:GetScript("OnMouseDown")(bar, "LeftButton")
    T.Eq(p.icMoving, true, "pressing the handle moves the panel")
    bar:GetScript("OnMouseUp")(bar, "RightButton")
    T.Eq(clicked, 1, "a right-click on the handle reaches the addon")
    T.Eq(p.icMoving, true, "without ending the move")
    bar:GetScript("OnMouseUp")(bar, "LeftButton")
    T.Eq(drops, 2, "and the release drops it")
end)

T.Case("Widgets: a minimap button's place is an angle round the rim", function()
    local x, y = W.MinimapOffset(0, 100)
    T.Near(x, 100, "due east")
    T.Near(y, 0, "on the centre line")
    x, y = W.MinimapOffset(90, 100)
    T.Near(x, 0, "due north")
    T.Near(y, 100, "is straight up")
    x, y = W.MinimapOffset(180, 50)
    T.Near(x, -50, "and west is negative")

    T.Near(W.MinimapAngle(10, 0, 0, 0), 0, "a pointer east of the centre")
    T.Near(W.MinimapAngle(0, 10, 0, 0), 90, "north")
    T.Near(W.MinimapAngle(-10, 0, 0, 0), 180, "west")
    T.Near(W.MinimapAngle(0, -10, 0, 0), 270, "south is 270, never negative")
    T.Near(W.MinimapAngle(110, 50, 100, 50), 0, "measured from wherever the minimap is")

    x, y = W.MinimapOffset(215, 104)
    T.Near(W.MinimapAngle(x, y, 0, 0), 215, "an angle survives the trip to a place and back")
end)

-- In game these would put a button on the player's minimap every time the cases ran.
if IC_HEADLESS then
    T.Case("Widgets: a minimap button keeps its angle and reports a click and a move", function()
        local clicked, moved
        local b = W.MinimapButton({
            icon = "Interface\\Icons\\INV_Misc_Note_02", angle = 400,
            onClick = function(_, mouseButton) clicked = mouseButton end,
            onMoved = function(angle) moved = angle end,
        })
        T.Eq(b.icAngle, 40, "an angle wraps into one turn")
        b:SetAngle(-90)
        T.Eq(b.icAngle, 270, "and a negative one too")
        b:GetScript("OnClick")(b, "RightButton")
        T.Eq(clicked, "RightButton", "a click says which button")
        b:GetScript("OnDragStop")(b)
        T.Eq(moved, nil, "a drop with no drag in progress says nothing")
        b:GetScript("OnDragStart")(b)
        T.Eq(b.icDragging, true, "dragging starts on the client's drag event, so a press stays a click")
        b:GetScript("OnDragStop")(b)
        T.Eq(b.icDragging, false, "and ends when dropped")
        T.Eq(moved, 270, "reporting where it was left")
        T.Eq(W.Compartment({ text = "Case" }), false, "a client with no addon compartment says so")
    end)
end

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
