local addonName, ns = ...

ns.Tests = ns.Tests or {}
local T = ns.Tests
T.cases = {}

--[[
The whole harness. There is no Lua interpreter on the maintainer's machine and no
CI, so this runs in game with /ictpl test and writes its result to SavedVariables,
where it can still be read after a /reload took the chat frame with it.

The house rule: any decision worth arguing about lives in a pure function, and
every pure function has a case here.
]]

function T.Case(name, fn)
    T.cases[#T.cases + 1] = { name = name, fn = fn }
end

function T.Eq(actual, expected, label)
    if actual ~= expected then
        -- Level 2 so the reported line is the assertion's, not this function's.
        error(string.format("%s: expected [%s], got [%s]",
            tostring(label or "value"), tostring(expected), tostring(actual)), 2)
    end
end

function T.Near(actual, expected, tolerance, label)
    if math.abs((actual or 0) - expected) > (tolerance or 0) then
        error(string.format("%s: expected [%s] give or take %s, got [%s]",
            tostring(label or "value"), tostring(expected), tostring(tolerance),
            tostring(actual)), 2)
    end
end

--[[
Runs fn against a made-up saved-variables table and puts the real one back
afterwards, whatever fn does.

Without this, only the pure half of an addon can be tested, and the impure half is
where the interesting bugs live. The restore is unconditional: a case that errors
must not leave the player's own settings swapped out.
]]
function T.With(db, cdb, fn)
    local realDB, realCDB = ns.db, ns.cdb
    ns.db, ns.cdb = db, cdb or {}
    local ok, err = pcall(fn)
    ns.db, ns.cdb = realDB, realCDB
    if not ok then error(err, 2) end
end

function T.Run()
    local pass, fail = 0, 0
    ns.db.lastTestRun = { at = ns.Now(), failures = {} }

    for _, case in ipairs(T.cases) do
        local ok, err = pcall(case.fn)
        if ok then
            pass = pass + 1
        else
            fail = fail + 1
            ns.Print("|cffff4444FAIL|r " .. case.name .. " => " .. tostring(err))
            local f = ns.db.lastTestRun.failures
            f[#f + 1] = { name = case.name, err = tostring(err) }
        end
    end

    ns.db.lastTestRun.passed, ns.db.lastTestRun.failed = pass, fail
    ns.Printf("Tests: |cff44ff44%d passed|r, %s%d failed|r",
        pass, fail > 0 and "|cffff4444" or "|cff44ff44", fail)
    if ns.UI then ns.UI.Refresh() end
    return pass, fail
end

--------------------------------------------------------------------------------
-- Util
--------------------------------------------------------------------------------

T.Case("Util: trimming and stripping", function()
    T.Eq(ns.Util.Trim("  hello  "), "hello", "both ends")
    T.Eq(ns.Util.Trim(""), "", "nothing to trim")
    T.Eq(ns.Util.Trim(nil), "", "nil is not an error")

    T.Eq(ns.Util.StripEscapes("|cff44ff44green|r"), "green", "colour codes")
    -- The brackets are part of what the player saw, so they stay; only the link
    -- machinery around them goes.
    T.Eq(ns.Util.StripEscapes("|cffa335ee|Hitem:29434:0:0:0|h[Badge]|h|r"), "[Badge]",
        "a link keeps only its display name")
    T.Eq(ns.Util.StripEscapes("a|TInterface\\Icons\\x:12|tb"), "ab", "inline textures")
end)

T.Case("Util: normalizing is for comparing, not for showing", function()
    T.Eq(ns.Util.Normalize("Fel Leather Gloves"), "fel leather gloves", "case")
    T.Eq(ns.Util.Normalize("LF  LW,  please!"), "lf lw please", "punctuation and runs of space")
    T.Eq(ns.Util.Normalize("|cff44ff44Primal Might|r"), "primal might", "escapes go first")
end)

T.Case("Util: truncating never leaves a broken escape behind", function()
    T.Eq(ns.Util.Truncate("short", 20), "short", "nothing to do")
    T.Eq(ns.Util.Truncate("abcdefgh", 4), "abcd", "plain")

    -- A cut that opens a colour and never closes it eats the rest of the chat row
    -- it lands in, which is somebody else's text.
    local opened = ns.Util.Truncate("|cff44ff44hello world|r", 16)
    T.Eq(opened:sub(-2), "|r", "an opened colour is closed")

    -- Half an escape is worse than none.
    T.Eq(ns.Util.Truncate("ab|cff44", 6), "ab", "a partial escape is dropped")

    -- Two bytes into a three-byte character is a box on screen.
    local dot = "a\194\183b"
    T.Eq(#ns.Util.Truncate(dot, 2), 1, "cuts back to a character boundary")
end)

T.Case("Util: serializing is stable or it is useless", function()
    -- Built in different key orders, and they must still hash the same. Anything
    -- comparing two of these otherwise decides they differ forever.
    local a = { name = "Malexis", rank = 1, teams = { "one", "two" } }
    local b = {}
    b.teams = { "one", "two" }
    b.rank = 1
    b.name = "Malexis"
    T.Eq(ns.Util.Serialize(a), ns.Util.Serialize(b), "order does not matter")

    b.rank = 2
    if ns.Util.Serialize(a) == ns.Util.Serialize(b) then
        error("a changed field must change the serialization", 2)
    end

    T.Eq(ns.Util.Serialize(1.5), "1.5", "numbers do not pick up a locale")
    T.Eq(ns.Util.Serialize(true), "true", "booleans")
    T.Eq(ns.Util.Serialize({}), "{}", "empty")
end)

T.Case("Util: sorted keys, plurals and switches", function()
    local keys = ns.Util.SortedKeys({ zebra = 1, apple = 1, mango = 1 })
    T.Eq(table.concat(keys, ","), "apple,mango,zebra", "alphabetical")
    T.Eq(#ns.Util.SortedKeys(nil), 0, "nil is an empty table")

    T.Eq(ns.Util.Plural(1, "line"), "line", "one")
    T.Eq(ns.Util.Plural(2, "line"), "lines", "many")
    T.Eq(ns.Util.Plural(0, "entry", "entries"), "entries", "an irregular one")
end)

T.Case("Util: freshness says how old and whether that is a problem", function()
    local now = 1000000
    T.Eq(ns.Util.Freshness(nil, now, 60), "never", "nothing stored")
    T.Eq(ns.Util.Freshness(0, now, 60), "never", "and zero means the same")
    T.Eq(ns.Util.Freshness(now - 42, now, 3600), "42s", "seconds")
    T.Eq(ns.Util.Freshness(now - 400, now, 3600), "6m", "minutes")
    T.Eq(ns.Util.Freshness(now - 9000, now, 86400), "2h", "hours")
    T.Eq(ns.Util.Freshness(now - 200000, now, 0), "2d", "days")

    -- The second return is the point of having this at all.
    local _, fresh = ns.Util.Freshness(now - 10, now, 60)
    local _, stale = ns.Util.Freshness(now - 600, now, 60)
    T.Eq(fresh.g > 0.85 and stale.g < 0.85, true, "past staleSec it goes amber")

    -- A clock that jumped backwards must not produce a negative age.
    T.Eq(ns.Util.Freshness(now + 500, now, 60), "0s", "the future reads as now")
end)

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

T.Case("Defaults: filling gaps without trampling anything", function()
    local target = { a = 1, nested = { keep = "mine" } }
    ns.ApplyDefaults(target, { a = 9, b = 2, nested = { keep = "theirs", add = 3 } })
    T.Eq(target.a, 1, "an existing value is left alone")
    T.Eq(target.b, 2, "a missing one is filled in")
    T.Eq(target.nested.keep, "mine", "and nested is the same rule")
    T.Eq(target.nested.add, 3, "new nested keys arrive")

    -- The classic one: `false` is a value the player chose, not a missing key.
    local off = { enabled = false }
    ns.ApplyDefaults(off, { enabled = true })
    T.Eq(off.enabled, false, "a stored false survives its own default")

    -- A scalar where a table belongs is corrupt; the table wins.
    local wrong = { settings = 5 }
    ns.ApplyDefaults(wrong, { settings = { x = 1 } })
    T.Eq(type(wrong.settings), "table", "a table default replaces a scalar")
    T.Eq(wrong.settings.x, 1, "and is then filled")
end)

T.Case("Defaults: a deep copy shares nothing", function()
    local source = { list = { 1, 2 }, deep = { inner = { "x" } } }
    local copy = ns.DeepCopy(source)
    copy.list[1] = 99
    copy.deep.inner[1] = "y"
    T.Eq(source.list[1], 1, "the original list is untouched")
    T.Eq(source.deep.inner[1], "x", "however deep it goes")
end)

T.Case("Migrations: run in order, once, and never on a fresh install", function()
    local ran = {}
    local steps = {
        [1] = function(db) ran[#ran + 1] = 1; db.one = true end,
        [2] = function(db) ran[#ran + 1] = 2; db.two = true end,
    }

    -- An empty table is somebody's first login, not an ancient save.
    local fresh = {}
    T.Eq(ns.Migrate(fresh, steps, 3), 0, "nothing runs on a fresh table")
    T.Eq(fresh.schema, 3, "and it is stamped at the head")

    local old = { settings = {} }
    T.Eq(ns.Migrate(old, steps, 3), 2, "an unstamped table with data is schema 1")
    T.Eq(table.concat(ran, ","), "1,2", "in order")
    T.Eq(old.schema, 3, "and lands on the head")

    T.Eq(ns.Migrate(old, steps, 3), 0, "running again does nothing")
    T.Eq(table.concat(ran, ","), "1,2", "and does not repeat a step")

    -- A gap in the table is not an error: a schema can bump without a step.
    local gap = { schema = 1 }
    T.Eq(ns.Migrate(gap, { [2] = steps[2] }, 3), 2, "missing steps are skipped")
end)

T.Case("Migrations: the shipped example reads the old shape", function()
    local db = { schema = 1, settings = { pulse = { every = 45 } } }
    ns.Migrate(db, ns.Migrations, 2)
    T.Eq(db.settings.pulse.intervalSec, 45, "every became intervalSec")
    T.Eq(db.settings.pulse.every, nil, "and the old field is gone")

    -- It has to run BEFORE ApplyDefaults. Afterwards it cannot tell a field the
    -- player never had from one the defaults have just invented.
    local defaulted = { schema = 1, settings = { pulse = { every = 45, intervalSec = 60 } } }
    ns.Migrate(defaulted, ns.Migrations, 2)
    T.Eq(defaulted.settings.pulse.intervalSec, 60, "an explicit new value wins")
end)

--------------------------------------------------------------------------------
-- Log
--------------------------------------------------------------------------------

local function entry(at, kind, source, text)
    return { at = at, kind = kind, source = source, text = text }
end

T.Case("Log: the ring buffer keeps the newest and drops the oldest", function()
    local list = {}
    for i = 1, 12 do ns.Log.Push(list, entry(i, "info", "T", "line " .. i), 10) end
    T.Eq(#list, 10, "capped")
    T.Eq(list[1].text, "line 12", "newest first")
    T.Eq(list[10].text, "line 3", "and the two oldest are gone")
end)

T.Case("Log: the window merges both streams without sorting either", function()
    local log = { entry(90, "ok", "Pulse", "sent"), entry(50, "ok", "Pulse", "sent") }
    local capture = { entry(80, "info", "Pulse", "skipped"), entry(60, "info", "Pulse", "skipped") }

    local out = ns.Log.Window(log, capture, 10)
    T.Eq(#out, 4, "everything, once")
    T.Eq(out[1].at .. "," .. out[2].at .. "," .. out[3].at .. "," .. out[4].at,
        "90,80,60,50", "in time order")

    -- The same thing recorded in both halves is one line, and it is the log's
    -- copy, which is the one carrying the detail.
    local both = entry(70, "ok", "Pulse", "sent")
    local rich = { at = 70, kind = "ok", source = "Pulse", text = "sent", detail = "3 entries" }
    out = ns.Log.Window({ rich }, { both }, 10)
    T.Eq(#out, 1, "deduped")
    T.Eq(out[1].detail, "3 entries", "and the richer copy survives")

    -- The window is a budget, not a suggestion.
    local many = {}
    for i = 1, 50 do many[i] = entry(100 - i, "info", "T", "x") end
    T.Eq(#ns.Log.Window(many, {}, 5), 5, "stops at the window")
    T.Eq(#ns.Log.Window(nil, nil, 5), 0, "and two empty lists are not an error")
end)

T.Case("Log: a filtered list says what it is holding back", function()
    local entries = {
        entry(5, "ok", "Pulse", "sent"),
        entry(4, "warn", "Pulse", "skipped"),
        entry(3, "ok", "Demos", "compiled"),
        entry(2, "err", "Demos", "broken"),
    }

    local out, hidden = ns.Log.Filter(entries, 10, {})
    T.Eq(#out, 4, "no filter keeps everything")
    T.Eq(hidden, 0, "and hides nothing")

    out, hidden = ns.Log.Filter(entries, 10, { kind = "ok" })
    T.Eq(#out, 2, "by kind")
    T.Eq(hidden, 2, "the rest are counted, not forgotten")

    out, hidden = ns.Log.Filter(entries, 10, { source = "Demos" })
    T.Eq(#out, 2, "by source")

    out, hidden = ns.Log.Filter(entries, 10, { kind = "ok", source = "Demos" })
    T.Eq(#out, 1, "both axes at once")
    T.Eq(out[1].text, "compiled", "and the right one")

    -- "all" is the word the toolbar stores for no filter at all.
    out = ns.Log.Filter(entries, 10, { kind = "all", source = "all" })
    T.Eq(#out, 4, "all means all")

    -- n caps what is drawn; hidden counts only what the FILTER removed, so the
    -- count line reads "2 of 4" rather than claiming two were filtered out.
    out, hidden = ns.Log.Filter(entries, 2, {})
    T.Eq(#out, 2, "n caps the list")
    T.Eq(hidden, 0, "a cap is not a filter")
end)

T.Case("Log: sources come back in a fixed order", function()
    local entries = {
        entry(3, "ok", "Pulse", "x"), entry(2, "ok", "Demos", "y"),
        entry(1, "ok", "Pulse", "z"),
    }
    T.Eq(table.concat(ns.Log.Sources(entries), ","), "Demos,Pulse", "deduped and sorted")
end)

T.Case("Log: writing goes through a made-up database", function()
    -- The point of T.With: Log.Add is not pure, and it is still testable.
    T.With({ log = {}, capture = {}, settings = { outputFrame = 1 } }, {}, function()
        ns.Log.Add("ok", "Test", "|cff44ff44coloured|r", "and a detail", 500)
        T.Eq(#ns.db.log, 1, "written")
        T.Eq(ns.db.log[1].text, "coloured", "escapes come off BEFORE storing")
        T.Eq(ns.db.log[1].at, 500, "the caller's clock, not the real one")

        ns.Log.Capture("info", "Test", "seen", 501)
        T.Eq(#ns.db.capture, 1, "capture is its own stream")
        T.Eq(#ns.db.log, 1, "and does not touch the other one")
    end)
    T.Eq(type(ns.db.settings), "table", "the real database came back")
end)

--------------------------------------------------------------------------------
-- Pulse
--------------------------------------------------------------------------------

T.Case("Pulse: the interval is held to something sensible", function()
    T.Eq(ns.Pulse.ClampInterval(60), 60, "a reasonable number passes through")
    T.Eq(ns.Pulse.ClampInterval(1), 15, "too fast is a nuisance")
    T.Eq(ns.Pulse.ClampInterval(99999), 600, "too slow is not a timer")
    T.Eq(ns.Pulse.ClampInterval("abc"), 15, "and nonsense is not an error")
end)

T.Case("Pulse: due is measured from the last send", function()
    T.Eq(ns.Pulse.IsDue(1000, 1059, 60), false, "one second early")
    T.Eq(ns.Pulse.IsDue(1000, 1060, 60), true, "exactly on the boundary")
    T.Eq(ns.Pulse.IsDue(nil, 60, 60), true, "never sent is always due")
end)

T.Case("Pulse: fitting entries into a byte budget", function()
    local entries = { "Alpha", "Bravo", "Charlie", "Delta" }
    local template = "LFW: {items} -- whisper me"

    local msg, cursor, used = ns.Pulse.Fit(entries, 1, template, 255, 3)
    T.Eq(used, 3, "three of them")
    T.Eq(msg, "LFW: Alpha, Bravo, Charlie -- whisper me", "in the template")
    T.Eq(cursor, 4, "and the cursor moved on")

    -- The cursor wraps, so the next message shows different entries rather than
    -- the same three forever.
    msg, cursor, used = ns.Pulse.Fit(entries, 4, template, 255, 3)
    T.Eq(msg, "LFW: Delta, Alpha, Bravo -- whisper me", "wrapping round the end")
    T.Eq(cursor, 3, "and the cursor wrapped with it")

    -- The budget is what is left after the template's own text: 255 fits four,
    -- 32 fits two, and the separator counts.
    msg, _, used = ns.Pulse.Fit(entries, 1, template, 32, 3)
    T.Eq(used, 2, "only two fit in 32 bytes")
    T.Eq(#msg <= 32, true, "and the result really is inside the budget")

    T.Eq(ns.Pulse.Fit({}, 1, template, 255, 3), nil, "nothing to say")
    T.Eq(ns.Pulse.Fit(entries, 1, "no token here", 255, 3), nil,
        "a template with no {items} has nowhere to put them")
    T.Eq(ns.Pulse.Fit(entries, 1, template, 10, 3), nil, "a budget too small for one entry")

    -- A cursor pointing past the end is a stale saved variable, not a crash.
    T.Eq(ns.Pulse.Fit(entries, 99, template, 255, 1) ~= nil, true, "a bad cursor resets")

    -- A percent sign in an entry must survive gsub's replacement rules.
    msg = ns.Pulse.Fit({ "50% off" }, 1, template, 255, 1)
    T.Eq(msg, "LFW: 50% off -- whisper me", "a percent is text, not a format token")
end)

T.Case("Pulse: every reason it will not send, in a fixed order", function()
    local function state(over)
        local s = {
            addonEnabled = true, pulseEnabled = true, pauseCombat = true,
            inCombat = false, hasTemplate = true, hasEntries = true,
        }
        for k, v in pairs(over or {}) do s[k] = v end
        return s
    end

    T.Eq(ns.Pulse.BlockReason(state()), nil, "nothing in the way")
    T.Eq(ns.Pulse.BlockReason(state({ addonEnabled = false })), "ICTemplate is disabled", "off")
    T.Eq(ns.Pulse.BlockReason(state({ pulseEnabled = false })), "the pulse timer is off", "timer")
    T.Eq(ns.Pulse.BlockReason(state({ inCombat = true })), "in combat", "combat")
    T.Eq(ns.Pulse.BlockReason(state({ inCombat = true, pauseCombat = false })), nil,
        "unless you asked it not to care")
    T.Eq(ns.Pulse.BlockReason(state({ hasTemplate = false })),
        "the template has no {items} in it", "template")
    T.Eq(ns.Pulse.BlockReason(state({ hasEntries = false })), "nothing to send", "entries")

    -- The order is the contract, not an accident. The UI shows the FIRST reason,
    -- and one that changes with whichever check ran first is worse than none.
    T.Eq(ns.Pulse.BlockReason(state({ addonEnabled = false, inCombat = true })),
        "ICTemplate is disabled", "widest reason first")
    T.Eq(ns.Pulse.BlockReason(state({ inCombat = true, hasEntries = false })),
        "in combat", "the world before the contents")
end)

--------------------------------------------------------------------------------
-- Probe
--------------------------------------------------------------------------------

T.Case("Probe: a dotted path never indexes a nil", function()
    local root = { C_Thing = { Method = function() end }, plain = 1 }
    T.Eq(type(ns.Probe.Resolve(root, "C_Thing.Method")), "function", "two levels")
    T.Eq(ns.Probe.Resolve(root, "plain"), 1, "one level")
    T.Eq(ns.Probe.Resolve(root, "C_Missing.Method"), nil, "a missing namespace is nil, not an error")
    T.Eq(ns.Probe.Resolve(root, "plain.deeper"), nil, "and neither is walking into a number")

    local present, kind = ns.Probe.Describe(nil)
    T.Eq(present, false, "missing")
    T.Eq(kind, "missing", "and says so")
    T.Eq(select(2, ns.Probe.Describe(print)), "function", "present things report their type")
end)

--------------------------------------------------------------------------------
-- Snippet
--------------------------------------------------------------------------------

T.Case("Snippet: dedent keeps the shape and loses the margin", function()
    local src = "\n    local a = 1\n        local b = 2\n    local c = 3\n"
    T.Eq(ns.Snippet.Dedent(src), "local a = 1\n    local b = 2\nlocal c = 3",
        "the common indent goes, the relative one stays")
    T.Eq(ns.Snippet.Dedent("already flat"), "already flat", "nothing to remove")
    T.Eq(ns.Snippet.Dedent(""), "", "empty")
    T.Eq(ns.Snippet.Dedent(nil), "", "nil is not an error")

    -- A blank line has no indentation to measure and must not set the margin to
    -- zero for everybody else.
    T.Eq(ns.Snippet.Dedent("\n    local a = 1\n\n    local b = 2"),
        "local a = 1\n\nlocal b = 2", "blank lines do not count")
end)

T.Case("Snippet: an error names the demo's own line", function()
    T.Eq(ns.Snippet.CleanError("button:3: unexpected symbol"), "line 3: unexpected symbol",
        "the chunk name is ours, not the reader's problem")
    T.Eq(ns.Snippet.CleanError('[string "@button"]:7: bad thing'), "line 7: bad thing",
        "and the other shape of it")
    T.Eq(ns.Snippet.CleanError(nil), "", "nil is not an error")
end)

T.Case("Snippet: compiling", function()
    if type(loadstring) ~= "function" then
        -- Not a failure. This client cannot do it, and the gallery says so.
        T.Eq(ns.Snippet.Compile("local a = 1"), nil, "no loadstring, no compile")
        return
    end
    T.Eq(type(ns.Snippet.Compile("local a = 1")), "function", "valid source")
    T.Eq(ns.Snippet.Compile("local = = ="), nil, "a syntax error returns nil")
    T.Eq(type(select(2, ns.Snippet.Compile("local = = ="))), "string", "with a message")

    -- The compiled chunk is handed the three names a demo is allowed to use.
    local fn = ns.Snippet.Compile("return page + 1")
    T.Eq(fn(41), 42, "page is the first argument")
end)

-- >>> gallery tests
-- Deleted by scripts/new-addon.ps1 -Minimal, along with Demos.lua, Snippet.lua
-- and the two gallery pages.

T.Case("Demos: the catalogue is well formed", function()
    local seen = {}
    for _, demo in ipairs(ns.Demos.list) do
        T.Eq(seen[demo.id], nil, "duplicate demo id: " .. tostring(demo.id))
        seen[demo.id] = true
        T.Eq(type(demo.id) == "string" and demo.id ~= "", true, "every demo has an id")
        T.Eq(type(demo.group) == "string" and demo.group ~= "", true,
            demo.id .. " has a group")
        T.Eq(type(demo.blurb) == "string" and #demo.blurb > 20, true,
            demo.id .. " explains itself")
        T.Eq(ns.Demos.ById(demo.id), demo, demo.id .. " can be looked up")
    end
    T.Eq(ns.Demos.ById("no such demo"), nil, "and an unknown id is nil")
end)

T.Case("Demos: every demo still compiles", function()
    -- This is the ICLibs smoke test. Change the library, /reload, run this: a
    -- demo that no longer builds is the library telling you what you broke.
    if type(loadstring) ~= "function" then return end
    for _, demo in ipairs(ns.Demos.list) do
        local fn, err = ns.Snippet.Compile(demo.source, demo.id)
        T.Eq(type(fn), "function", demo.id .. " does not compile: " .. tostring(err))
    end
end)

T.Case("Demos: groups come back in the order they first appear", function()
    local groups = ns.Demos.Groups()
    T.Eq(#groups > 0, true, "there are groups")
    T.Eq(groups[1].name, ns.Demos.list[1].group, "the first demo's group leads")

    local total = 0
    for _, group in ipairs(groups) do total = total + #group.demos end
    T.Eq(total, #ns.Demos.list, "and every demo is in exactly one of them")
end)
-- <<< gallery tests
