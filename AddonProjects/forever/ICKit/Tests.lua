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
-- LibICJSON
--------------------------------------------------------------------------------

local JSON = LibStub("LibICJSON-1.0")

T.Case("JSON.Encode: plain values", function()
    T.Eq(JSON.Encode(nil), "null", "nothing is null")
    T.Eq(JSON.Encode(true), "true", "true")
    T.Eq(JSON.Encode(false), "false", "false")
    T.Eq(JSON.Encode(22890.0), "22890", "a whole number has no fraction")
    T.Eq(JSON.Encode(-3), "-3", "a negative one")
    T.Eq(JSON.Encode(1.5), "1.5", "a fraction keeps it")
    T.Eq(JSON.Encode(0.1), "0.1", "in its shortest form")
    T.Eq(JSON.Decode(JSON.Encode(1 / 3)), 1 / 3, "and reads back as the same number")
    T.Eq(JSON.Encode('say "hi"\\now\n'), '"say \\"hi\\"\\\\now\\n"', "quotes, backslashes and line breaks escaped")
    T.Eq(JSON.Encode("a\1b"), '"a\\u0001b"', "another control character as \\u")
    T.Eq(JSON.Encode("caf\195\169"), '"caf\195\169"', "UTF-8 is written as it is")
end)

T.Case("JSON.Encode: tables, sorted and indented, or compact", function()
    local t = { name = "Hyjal", ids = { 3, 1 }, boss = { hp = 10, alive = true }, empty = {} }
    T.Eq(JSON.Encode(t), '{\n'
        .. '  "boss": {\n'
        .. '    "alive": true,\n'
        .. '    "hp": 10\n'
        .. '  },\n'
        .. '  "empty": {},\n'
        .. '  "ids": [\n'
        .. '    3,\n'
        .. '    1\n'
        .. '  ],\n'
        .. '  "name": "Hyjal"\n'
        .. '}', "keys in order, two spaces a level, a list keeps its own order")
    T.Eq(JSON.Encode(t, { compact = true }),
        '{"boss":{"alive":true,"hp":10},"empty":{},"ids":[3,1],"name":"Hyjal"}', "compact is one line")
    T.Eq(JSON.Encode({ a = 1 }, { indent = "\t" }), '{\n\t"a": 1\n}', "the indent is the caller's to pick")
    T.Eq(JSON.Encode({ [10] = "x", [2] = "y", b = "z" }, { compact = true }), '{"2":"y","10":"x","b":"z"}',
        "number keys by value, before text keys, and written as text")
    T.Eq(JSON.Encode({ [1] = "a", [3] = "c" }, { compact = true }), '{"1":"a","3":"c"}', "a list with a hole is an object")
    local one, two = {}, {}
    for i = 1, 30 do one["k" .. i] = i end
    for i = 30, 1, -1 do two["k" .. i] = i end
    T.Eq(JSON.Encode(one), JSON.Encode(two), "the order a table was filled in never shows")
end)

T.Case("JSON.Encode: what JSON cannot hold is refused with a reason", function()
    local text, why = JSON.Encode({ fn = print })
    T.Eq(text, nil, "a function")
    T.True(why:find("function", 1, true), "is named")
    local loop = {}
    loop.self = loop
    text, why = JSON.Encode(loop)
    T.Eq(text, nil, "a table inside itself")
    T.True(why:find("itself", 1, true), "is named")
    T.Eq(JSON.Encode({ 1 / 0 }), nil, "infinity")
    T.Eq(JSON.Encode({ 0 / 0 }), nil, "NaN")
    text, why = JSON.Encode({ [true] = 1 })
    T.Eq(text, nil, "a key that is not text or a number")
    T.True(why:find("key", 1, true), "is named")
    local shared = { 1 }
    T.Eq(JSON.Encode({ shared, shared }, { compact = true }), "[[1],[1]]", "one table used twice is not a loop")
end)

T.Case("JSON.Decode: objects, lists, numbers and words", function()
    local t = JSON.Decode(' { "a" : [ 1, -2.5, 3e2, 1E-1 ], "b": { "c": true, "d": false }, "e": "x" } ')
    T.Eq(t.a[1], 1, "a whole number")
    T.Eq(t.a[2], -2.5, "a negative fraction")
    T.Eq(t.a[3], 300, "an exponent")
    T.Near(t.a[4], 0.1, 1e-12, "a capital E and a negative exponent")
    T.Eq(t.b.c, true, "true")
    T.Eq(t.b.d, false, "false")
    T.Eq(t.e, "x", "text")
    T.Eq(JSON.Decode("42"), 42, "a bare number")
    T.Eq(next(JSON.Decode("{}")), nil, "an empty object")
    T.Eq(next(JSON.Decode("[]")), nil, "an empty list")
    t = JSON.Decode("[1, null, 3]")
    T.Eq(t[2], nil, "a null in a list is a hole")
    T.Eq(t[3], 3, "and what follows keeps its index")
    T.Eq(JSON.Decode('{"a": null}').a, nil, "a null value is no value")
end)

T.Case("JSON.Decode: escapes, UTF-8 included", function()
    T.Eq(JSON.Decode('"a\\"b\\\\c\\/d\\n\\t\\r\\b\\f"'), 'a"b\\c/d\n\t\r\b\f', "every short escape")
    T.Eq(JSON.Decode('"\\u0041"'), "A", "a \\u escape")
    T.Eq(JSON.Decode('"caf\\u00e9"'), "caf\195\169", "past 127 as UTF-8")
    T.Eq(JSON.Decode('"\\u20AC"'), "\226\130\172", "three bytes, either case of hex")
    T.Eq(JSON.Decode('"\\ud83d\\ude00"'), "\240\159\152\128", "a surrogate pair is one character")
    T.Eq(JSON.Decode('"x\\ud83dy"'), "x\239\191\189y", "a lone surrogate is the replacement character")
    T.Eq(JSON.Decode('"tab\there"'), "tab\there", "a raw tab a text editor left is kept")
    T.Eq(JSON.Decode('"caf\195\169"'), "caf\195\169", "raw UTF-8 passes through")
end)

T.Case("JSON.Decode: text that is not JSON gets a reason, never an error", function()
    local cases = {
        { nil, "nothing to read" }, { "", "nothing to read" }, { "  \n ", "nothing to read" },
        { "{", "ends where a key" }, { "[", "ends where a value" }, { "[1,]", "unexpected ]" }, { "[1 2]", "expected , or ]" },
        { '{"a" 1}', "expected :" }, { "{a: 1}", "quoted key" }, { '{"a": 1,}', "quoted key" },
        { '"open', "never ends" }, { '"\\q"', "unknown escape" }, { '"\\u12"', "four hex" },
        { "1 2", "more text after" }, { "null", "only null" }, { "nope", "unexpected n" },
        { string.rep("[", 300), "nested more than" },
    }
    for _, case in ipairs(cases) do
        local value, why = JSON.Decode(case[1])
        T.Eq(value, nil, tostring(case[1]) .. " reads as nothing")
        T.True(type(why) == "string" and why:find(case[2], 1, true), tostring(case[1]) .. " says " .. case[2]
            .. " (said " .. tostring(why) .. ")")
    end
    local _, why = JSON.Decode("[1, 2, x]")
    T.True(why:find("character 8", 1, true), "the reason says where (" .. tostring(why) .. ")")
end)

T.Case("JSON: a table survives the trip out and back", function()
    local rules = { version = 2, name = "Barrow \"Deeps\"", mobs = {}, flags = { true, false, true } }
    for i = 1, 500 do
        rules.mobs[i] = { id = 200000 + i, name = "Mob " .. i, weight = i / 8, marks = { i % 8 + 1 } }
    end
    local text = assert(JSON.Encode(rules))
    local back = assert(JSON.Decode(text))
    T.Eq(JSON.Encode(back), text, "encoding what was read gives the same text")
    T.Eq(back.mobs[500].id, 200500, "deep values come back")
    T.Eq(back.mobs[3].weight, 0.375, "fractions too")
    T.Eq(back.name, rules.name, "and text with quotes in it")
    T.Eq(JSON.Decode(JSON.Encode(rules, { compact = true })).mobs[250].name, "Mob 250", "compact reads back the same")
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

-- A stand-in for a secret value: like the client's, it refuses to become text.
local function FakeSecret()
    return setmetatable({}, {
        __tostring = function() error("attempt to read a secret value") end,
        __concat = function() error("attempt to concatenate a secret value") end,
    })
end

T.Case("Env.IsSecret: the client's check, guarded, or false where there is none", function()
    local mark = FakeSecret()
    Env.SetSecretCheck(nil)
    if type(issecretvalue) ~= "function" then
        T.Eq(Env.IsSecret(mark), false, "a client without the check has no secrets")
    end
    Env.SetSecretCheck(function(v) return v == mark end)
    T.Eq(Env.IsSecret(mark), true, "the check says so")
    T.Eq(Env.IsSecret("plain"), false, "a plain value is not")
    Env.SetSecretCheck(function() error("check broke") end)
    T.Eq(Env.IsSecret(mark), false, "a check that fails is read as not secret, not raised")
    Env.SetSecretCheck(function() return 1 end)
    T.Eq(Env.IsSecret(mark), false, "only a true answer counts")
    Env.SetSecretCheck(nil)
end)

T.Case("Env.Try: a secret return is marked, never joined into the text", function()
    local mark = FakeSecret()
    Env.SetSecretCheck(function(v) return v == mark end)
    local t = Env.Try("unit", function() return "a", mark, 3 end)
    T.Eq(t.ok, true, "the call answered")
    T.Eq(t.n, 3, "all three returns counted")
    T.Eq(t.text, "a, <secret>, 3", "the secret one is named, not read")
    T.True(t.secret[2], "and its place is marked")
    T.Eq(t.secret[1], nil, "a plain one is not")
    T.True(t.values[2] == mark, "the value itself is handed back untouched")
    t = Env.Try("secret error", function() error(mark) end)
    T.Eq(t.ok, false, "an error raised with a secret is caught")
    T.Eq(t.err, "<secret>", "and named, not read")
    Env.SetSecretCheck(nil)
end)

T.Case("Env.Try: a return that will not become text leaves the answer intact", function()
    local odd = FakeSecret()
    Env.SetSecretCheck(function() return false end)
    local t = Env.Try("odd", function() return 1, odd end)
    T.Eq(t.ok, true, "the call still answered")
    T.Eq(t.unreadable, true, "the text is said to be unreadable")
    T.Eq(t.text, "<unreadable>", "rather than raising")
    T.True(t.values[2] == odd, "and the values are all there")
    t = Env.Try("odd error", function() error(odd) end)
    T.Eq(t.err, "<unreadable>", "an error that will not become text is named too")
    t = Env.Try("plain", function() return true end)
    T.Eq(t.unreadable, nil, "a plain answer is readable")
    T.Eq(next(t.secret), nil, "with nothing secret")
    Env.SetSecretCheck(nil)
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
-- LibICRestrict
--------------------------------------------------------------------------------

local Restrict = LibStub("LibICRestrict-1.0")

T.Case("Restrict.IsSecret and Readable: a secret is withheld, a plain value passes", function()
    local mark = FakeSecret()
    Env.SetSecretCheck(function(v) return v == mark end)
    T.Eq(Restrict.IsSecret(mark), true, "the secret is one")
    T.Eq(Restrict.IsSecret(12), false, "a number is not")
    T.Eq(Restrict.Readable(mark), nil, "a secret reads as nothing")
    T.Eq(Restrict.Readable(mark, 0), 0, "or as the fallback")
    T.Eq(Restrict.Readable(12, 0), 12, "a plain value is itself")
    T.Eq(Restrict.Readable(false, true), false, "false is a plain value, not a missing one")
    Env.SetSecretCheck(nil)
end)

T.Case("Restrict.State: out of combat in the open world, nothing is on", function()
    local s = Restrict.State({
        states = { Combat = 0, Chat = 0, Encounter = 0, Map = 0, ChallengeMode = 0, PvPMatch = 0 },
        lockdown = false, chatLockdown = false,
    })
    T.Eq(s.combat, false, "not in combat")
    T.Eq(s.chat, false, "chat open")
    T.Eq(s.secure, false, "secure frames can change")
    T.Eq(s.restricted, false, "nothing restricted")
    T.Eq(s.reason, nil, "and no reason")
    T.Eq(next(s.active), nil, "no restriction on")
    T.Eq(Restrict.State(nil).restricted, false, "nothing said is nothing on")
end)

T.Case("Restrict.State: combat by any of its three signs", function()
    local s = Restrict.State({ regenDisabled = true, lockdown = false, states = { Combat = 0 } })
    T.Eq(s.combat, true, "the regen event comes first, seconds before the rest")
    T.Eq(s.secure, true, "so secure changes stop at once")
    T.Eq(s.reason, "in combat", "and that is the reason")
    s = Restrict.State({ lockdown = true })
    T.Eq(s.combat and s.secure, true, "lockdown alone")
    s = Restrict.State({ states = { Combat = 2 } })
    T.Eq(s.combat, true, "the Combat restriction alone")
    T.Eq(s.secure, false, "which alone does not say secure frames are locked")
    T.True(s.active.Combat, "and is listed as on")
    T.Eq(Restrict.State({ states = { Combat = 1 } }).combat, true, "1, the state the change event reports, counts as on")
end)

T.Case("Restrict.State: chat, encounter and other kinds, with the reason most fundamental first", function()
    local s = Restrict.State({ chatLockdown = true })
    T.Eq(s.chat, true, "chat lockdown")
    T.Eq(s.combat, false, "is not combat")
    T.Eq(s.reason, "chat is locked", "and says so")
    T.Eq(Restrict.State({ states = { Chat = 2 } }).chat, true, "the Chat restriction locks chat too")
    s = Restrict.State({ states = { Encounter = 2, Chat = 2 } })
    T.Eq(s.encounter, true, "an encounter")
    T.Eq(s.reason, "in an encounter", "comes before chat")
    s = Restrict.State({ states = { Encounter = 2, Combat = 2 } })
    T.Eq(s.reason, "in combat", "and combat before both")
    s = Restrict.State({ states = { PvPMatch = 2, Map = 2 } })
    T.Eq(s.restricted, true, "another kind still restricts")
    T.Eq(s.combat or s.chat or s.encounter, false, "without claiming to be one of the three")
    T.Eq(s.reason, "restricted (Map, PvPMatch)", "and names itself")
end)

T.Case("Restrict.State: a state that cannot be read is unknown, not on", function()
    local mark = FakeSecret()
    Env.SetSecretCheck(function(v) return v == mark end)
    local s = Restrict.State({ states = { Combat = mark, Chat = "2" }, lockdown = mark })
    T.True(s.unknown.Combat, "a secret state is unknown")
    T.True(s.unknown.Chat, "so is one that is not a number")
    T.Eq(s.combat, false, "an unreadable lockdown is not taken as combat")
    T.Eq(s.restricted, false, "nothing is claimed")
    Env.SetSecretCheck(nil)
end)

T.Case("Restrict.Changed: only what an addon acts on counts", function()
    local calm = Restrict.State({ states = { Combat = 0 } })
    local fight = Restrict.State({ states = { Combat = 2 }, lockdown = true })
    T.Eq(Restrict.Changed(nil, calm), true, "the first reading is a change")
    T.Eq(Restrict.Changed(calm, Restrict.State({ states = { Combat = 0, Map = 0 } })), false,
        "a new kind reading off is not")
    T.Eq(Restrict.Changed(calm, fight), true, "combat starting is")
    T.Eq(Restrict.Changed(fight, Restrict.State({ states = { Combat = 1 }, lockdown = true })), false,
        "1 and 2 are both on")
    T.Eq(Restrict.Changed(Restrict.State({ states = { Map = 2 } }), Restrict.State({ states = { PvPMatch = 2 } })),
        true, "a different kind on is")
end)

-- Stands a fake client in for the calls Restrict.Read makes; returns the knobs and a
-- function that puts the real globals back.
local function FakeRestrictClient()
    local saved = { Enum = Enum, C_RestrictedActions = C_RestrictedActions, C_ChatInfo = C_ChatInfo,
        InCombatLockdown = InCombatLockdown }
    local client = { states = { [0] = 0, [1] = 0, [2] = 0 }, lockdown = false, chat = false }
    _G.Enum = { AddOnRestrictionType = { Combat = 0, Chat = 1, Encounter = 2 } }
    _G.C_RestrictedActions = {
        GetAddOnRestrictionState = function(kind) return client.states[kind] end,
    }
    _G.C_ChatInfo = { InChatMessagingLockdown = function() return client.chat end }
    _G.InCombatLockdown = function() return client.lockdown end
    return client, function()
        for k, v in pairs(saved) do _G[k] = v end
    end
end

T.Case("Restrict.Read: the client's answers, in the shape State takes", function()
    -- Headless only: in game, writing Enum and the C_ tables would taint them.
    if not IC_HEADLESS then return end
    local client, restore = FakeRestrictClient()
    local r = Restrict.Read()
    T.Eq(r.states.Combat, 0, "each kind by its name")
    T.Eq(r.lockdown, false, "lockdown")
    T.Eq(r.chatLockdown, false, "chat lockdown")
    T.Eq(Restrict.InCombat(), false, "not in combat")
    client.states[0], client.lockdown, client.chat = 2, true, true
    T.Eq(Restrict.InCombat(), true, "in combat")
    T.Eq(Restrict.ChatLocked(), true, "chat locked")
    T.Eq(Restrict.Active("Combat"), true, "Combat on")
    T.Eq(Restrict.Active("Encounter"), false, "Encounter off")
    _G.C_RestrictedActions = { IsAddOnRestrictionActive = function(kind) return kind == 2 end }
    T.Eq(Restrict.Read().states.Encounter, 2, "a client with only the yes-or-no call still answers")
    T.Eq(Restrict.Read().states.Combat, 0, "and off reads as 0")
    _G.C_RestrictedActions = { GetAddOnRestrictionState = function() error("nope") end }
    T.Eq(Restrict.Read().states.Combat, nil, "a call that fails is no answer")
    _G.C_RestrictedActions, _G.Enum, _G.C_ChatInfo, _G.InCombatLockdown = nil, nil, nil, nil
    r = Restrict.Read()
    T.Eq(next(r.states), nil, "a client without restrictions has none")
    T.Eq(Restrict.State(r).restricted, false, "and nothing is restricted")
    restore()
end)

T.Case("Restrict.OnChange: told at each change, with the regen event first", function()
    -- Headless only: in game, writing Enum and the C_ tables would taint them.
    if not IC_HEADLESS then return end
    local client, restore = FakeRestrictClient()
    local seen = {}
    local stop = Restrict.OnChange(function(s, previous) seen[#seen + 1] = { s = s, previous = previous } end)
    local frame = Restrict.frame
    T.True(frame and frame:IsEventRegistered("ADDON_RESTRICTION_STATE_CHANGED"), "listens for the restriction event")
    T.True(frame:IsEventRegistered("PLAYER_REGEN_DISABLED") and frame:IsEventRegistered("PLAYER_REGEN_ENABLED"),
        "and the regen pair")
    local fire = frame:GetScript("OnEvent")
    T.Eq(#seen, 0, "nothing is said at the start")

    fire(frame, "PLAYER_REGEN_DISABLED")
    T.Eq(#seen, 1, "combat starts at the regen event")
    T.Eq(seen[1].s.combat and seen[1].s.secure, true, "secure frames lock at once")
    T.Eq(seen[1].previous.combat, false, "and the State before is handed in")

    client.states[0], client.lockdown = 1, true
    fire(frame, "ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
    T.Eq(#seen, 2, "the Combat restriction arriving is a change")
    T.True(seen[2].s.active.Combat, "it is listed")
    client.states[0] = 2
    fire(frame, "ADDON_RESTRICTION_STATE_CHANGED", 0, 2)
    T.Eq(#seen, 2, "1 to 2 is not")

    client.states[0], client.lockdown = 0, false
    fire(frame, "ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
    T.Eq(#seen, 3, "the restriction ending is a change")
    T.Eq(seen[3].s.active.Combat, nil, "it is no longer listed")
    T.Eq(seen[3].s.combat and seen[3].s.secure, true, "but combat holds while the regen window is open")
    fire(frame, "PLAYER_REGEN_ENABLED")
    T.Eq(#seen, 4, "the regen end is a change")
    T.Eq(seen[4].s.combat or seen[4].s.secure, false, "and everything opens")

    stop()
    fire(frame, "PLAYER_REGEN_DISABLED")
    T.Eq(#seen, 4, "a stopped listener hears nothing")
    fire(frame, "PLAYER_REGEN_ENABLED")
    restore()
end)

--------------------------------------------------------------------------------
-- LibICGroup
--------------------------------------------------------------------------------

local Group = LibStub("LibICGroup-1.0")

-- A party of two as the probe saw one: the player leads, the other is a mage.
local function PartyReading()
    return {
        inGroup = true, inRaid = false, me = "Player-1-A",
        units = {
            { unit = "player", guid = "Player-1-A", name = "Mal", name2 = "Exis", classLocal = "Hunter",
                class = "HUNTER", role = "TANK", mainTank = false, leader = true, assist = false, online = true,
                dead = false },
            { unit = "party1", guid = "Player-1-B", name = "Solo", name2 = "Siphyr", classLocal = "Mage",
                class = "MAGE", role = "DAMAGER", mainTank = false, leader = false, online = true, dead = false },
        },
    }
end

T.Case("Group.Snapshot: a party, every field plain", function()
    local s = Group.Snapshot(PartyReading())
    T.Eq(s.kind, "party", "a party")
    T.Eq(s.size, 2, "of two")
    T.Eq(s.me.unit, "player", "the player is found by guid")
    T.Eq(s.leader.unit, "player", "and leads")
    T.Eq(s.me.rank, "leader", "rank leader")
    local mage = s.byGuid["Player-1-B"]
    T.Eq(mage.display, "Solo Siphyr", "both names, for showing")
    T.Eq(mage.name, "Solo", "the first name on its own")
    T.Eq(mage.class, "MAGE", "the class token")
    T.Eq(mage.classLocal, "Mage", "and the class as the client shows it")
    T.Eq(mage.role, "DAMAGER", "the role")
    T.Eq(mage.rank, "member", "no assist answer in a party is a plain member")
    T.Eq(mage.isMe, false, "not the player")
    T.Eq(s.canMark, true, "anyone in a party may mark")
    T.Eq(s.unknown, 0, "nothing unreadable")
end)

T.Case("Group.Snapshot: alone, and nothing said", function()
    local s = Group.Snapshot({ inGroup = false, me = "Player-1-A", units = { { unit = "player", guid = "Player-1-A", name = "Mal",
        role = "NONE" } } })
    T.Eq(s.kind, "solo", "alone")
    T.Eq(s.me.display, "Mal", "one name is the whole name")
    T.Eq(s.me.role, nil, "NONE is no role")
    T.Eq(s.canMark, true, "marks work solo")
    s = Group.Snapshot(nil)
    T.Eq(s.size, 0, "nothing said is nobody")
    T.Eq(s.me, nil, "with no player found")
end)

T.Case("Group.Snapshot: in a raid, marking needs leader, assist or everyone assist", function()
    local reading = PartyReading()
    reading.inRaid = true
    reading.units[1].unit, reading.units[2].unit = "raid1", "raid2"
    reading.units[1].leader = false
    T.Eq(Group.Snapshot(reading).canMark, false, "a plain member may not")
    reading.units[1].assist = true
    local s = Group.Snapshot(reading)
    T.Eq(s.me.rank, "assist", "an assist")
    T.Eq(s.canMark, true, "may")
    reading.units[1].assist = false
    reading.everyoneAssist = true
    T.Eq(Group.Snapshot(reading).canMark, true, "everyone assist lets anyone")
    reading.everyoneAssist = nil
    reading.units[1].mainTank = true
    T.Eq(Group.Snapshot(reading).me.mainTank, true, "Main Tank is kept")
    T.Eq(Group.Snapshot(reading).leader, nil, "a raid with no readable leader has none")
end)

T.Case("Group.Snapshot: a secret field is unknown, never guessed", function()
    local mark = FakeSecret()
    Env.SetSecretCheck(function(v) return v == mark end)
    local reading = PartyReading()
    reading.inRaid = true
    reading.units[1].leader, reading.units[1].assist = mark, mark
    reading.units[2].name, reading.units[2].role, reading.units[2].class = mark, mark, 7
    local s = Group.Snapshot(reading)
    T.Eq(s.me.rank, nil, "an unreadable rank is no rank")
    T.Eq(s.canMark, nil, "so whether the player may mark in a raid is not known")
    local mage = s.byGuid["Player-1-B"]
    T.Eq(mage.name, nil, "a secret name is nil")
    T.Eq(mage.display, nil, "and so is the shown name")
    T.True(mage.unknown.name and mage.unknown.role, "both are named as unknown")
    T.Eq(mage.class, nil, "a class that is not text is dropped")
    T.Eq(s.unknown, 4, "four unreadable fields in all")
    reading.me = mark
    T.Eq(Group.Snapshot(reading).me, nil, "a secret player guid finds nobody")
    Env.SetSecretCheck(nil)
end)

T.Case("Group.Snapshot: whether this is a raid, and assist, are never guessed", function()
    local mark = FakeSecret()
    Env.SetSecretCheck(function(v) return v == mark end)
    local reading = PartyReading()
    reading.inRaid = mark
    reading.units[1].leader, reading.units[1].assist = false, nil
    local s = Group.Snapshot(reading)
    T.Eq(s.kindKnown, false, "a secret IsInRaid leaves the kind unknown")
    T.Eq(s.kind, "party", "the kind says group")
    T.Eq(s.me.rank, nil, "with no assist answer, a non-leader's rank is unknown")
    T.Eq(s.canMark, nil, "so whether the player may mark is unknown, not yes")
    reading.units[1].assist = true
    T.Eq(Group.Snapshot(reading).canMark, true, "an assist may mark either way")
    reading.units[1].assist = nil
    reading.units[1].unit, reading.units[2].unit = "raid1", "raid2"
    s = Group.Snapshot(reading)
    T.Eq(s.kind, "raid", "raid unit tokens prove a raid")
    T.Eq(s.kindKnown, true, "and the kind is known")
    T.Eq(s.me.rank, nil, "a raid member with no assist answer has no rank")
    reading.units[1].assist = mark
    T.Eq(Group.Snapshot(reading).me.unknown.assist, true, "a secret assist is named unknown")
    reading.everyoneAssist = mark
    T.Eq(Group.Snapshot(reading).everyoneAssist, nil, "a secret everyone-assist is nil, not false")
    reading = PartyReading()
    reading.inRaid, reading.units[2].assist = false, nil
    s = Group.Snapshot(reading)
    T.Eq(s.kindKnown and s.byGuid["Player-1-B"].rank, "member", "a known party member with no assist answer is a member")
    reading = { inRaid = mark, inGroup = false, units = { { unit = "player" } } }
    T.Eq(Group.Snapshot(reading).kindKnown, true, "not in a group is known alone")
    Env.SetSecretCheck(nil)
end)

T.Case("Group.Read: the units of a party or a raid, every call guarded", function()
    -- Headless only: in game, writing these globals would taint them.
    if not IC_HEADLESS then return end
    local names = { "IsInRaid", "IsInGroup", "GetNumGroupMembers", "UnitGUID", "UnitName", "UnitClass",
        "UnitGroupRolesAssigned", "GetPartyAssignment", "UnitIsGroupLeader", "UnitIsGroupAssistant",
        "UnitIsConnected", "UnitIsDeadOrGhost", "IsEveryoneAssistant" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = _G[n] end
    local raid, count = false, 3
    _G.IsInRaid = function() return raid end
    _G.IsInGroup = function() return true end
    _G.GetNumGroupMembers = function() return count end
    _G.UnitGUID = function(unit) return unit == "player" and "G-player" or ("G-" .. unit) end
    _G.UnitName = function(unit) return "N-" .. unit, "Two" end
    _G.UnitClass = function() return "Priest", "PRIEST", 5 end
    _G.UnitGroupRolesAssigned = function(unit) return unit == "party1" and "HEALER" or "NONE" end
    _G.GetPartyAssignment = function(kind, unit) return kind == "MAINTANK" and unit == "party2" end
    _G.UnitIsGroupLeader = function(unit) return unit == "player" end
    _G.UnitIsGroupAssistant = function() error("not here") end
    _G.UnitIsConnected = function() return true end
    _G.UnitIsDeadOrGhost = function() return false end
    _G.IsEveryoneAssistant = nil

    local r = Group.Read()
    T.Eq(#r.units, 3, "the player and two party units")
    T.Eq(r.units[1].unit, "player", "the player first")
    T.Eq(r.units[3].unit, "party2", "then party1 and party2")
    T.Eq(r.units[2].name2, "Two", "both name returns")
    T.Eq(r.units[2].class, "PRIEST", "the class token")
    T.Eq(r.units[1].assist, nil, "a call that raises is no answer")
    T.Eq(r.everyoneAssist, nil, "nor is one that is missing")
    local s = Group.Snapshot(r)
    T.Eq(s.me.rank, "leader", "and the snapshot reads it")
    T.Eq(s.byGuid["G-party1"].role, "HEALER", "the healer")
    T.Eq(s.byGuid["G-party2"].mainTank, true, "the Main Tank")
    T.Eq(Group.Now().size, 3, "Now is the same snapshot")
    raid, count = true, 4
    r = Group.Read()
    T.Eq(#r.units, 4, "a raid reads its count")
    T.Eq(r.units[4].unit, "raid4", "as raid units")
    count = 99
    T.Eq(#Group.Read().units, 40, "never more than a raid holds")
    _G.IsInGroup = function() return false end
    raid = false
    T.Eq(#Group.Read().units, 1, "alone is the player only")
    local mark = FakeSecret()
    Env.SetSecretCheck(function(v) return v == mark end)
    _G.IsInGroup = function() return true end
    _G.IsInRaid = function() return mark end
    count = 8
    T.Eq(Group.Read().units[1].unit, "raid1", "an unreadable IsInRaid with eight members reads raid units")
    count = 3
    T.Eq(Group.Read().units[1].unit, "player", "and with three, party units")
    T.Eq(Group.Now().kindKnown, false, "leaving the kind unknown")
    Env.SetSecretCheck(nil)

    for _, n in ipairs(names) do _G[n] = saved[n] end
end)

--------------------------------------------------------------------------------
-- LibICChat
--------------------------------------------------------------------------------

local Chat = LibStub("LibICChat-1.0")

local function RaidLead(extra)
    local s = { now = 100, group = "raid", lead = true, chat = false, sent = {} }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

T.Case("Chat.Decide: the first channel the group allows, cleaned and cut", function()
    local plan = Chat.Decide({ text = "Tank\ndown ", channels = { "RAID_WARNING", "RAID" } }, RaidLead())
    T.Eq(plan.action, "send", "a raid lead sends")
    T.Eq(plan.channel, "RAID_WARNING", "as a raid warning")
    T.Eq(plan.text, "Tank down", "with the line break and the trailing space gone")
    plan = Chat.Decide({ text = "x", channels = { "RAID_WARNING", "RAID" } }, RaidLead({ lead = false }))
    T.Eq(plan.channel, "RAID", "a plain member falls back to RAID")
    plan = Chat.Decide({ text = "x", channel = "RAID_WARNING" }, RaidLead({ lead = false }))
    T.Eq(plan.action, "refuse", "with no fallback it is refused")
    T.Eq(plan.reason, "needs raid lead or assist", "and says why")
    local unread = RaidLead()
    unread.lead = nil
    T.Eq(Chat.Decide({ text = "x", channel = "RAID_WARNING" }, unread).reason,
        "cannot tell whether you lead or assist", "an unreadable rank is said as such")
    T.Eq(#Chat.Decide({ text = string.rep("a", 300), channel = "RAID" }, RaidLead()).text, 255,
        "a long line is cut to what the client sends")
    T.Eq(Chat.Decide({ text = "  \n", channel = "RAID" }, RaidLead()).reason, "nothing to say", "an empty line")
end)

T.Case("Chat.Decide: what each channel needs from the group", function()
    local party = { group = "party", sent = {} }
    T.Eq(Chat.Decide({ text = "x", channel = "PARTY" }, party).action, "send", "PARTY in a party")
    T.Eq(Chat.Decide({ text = "x", channel = "PARTY" }, RaidLead()).action, "send", "and in a raid")
    T.Eq(Chat.Decide({ text = "x", channel = "PARTY" }, { group = "solo" }).reason, "not in a group", "not alone")
    T.Eq(Chat.Decide({ text = "x", channel = "RAID" }, party).reason, "not in a raid", "RAID needs a raid")
    T.Eq(Chat.Decide({ text = "x", channel = "INSTANCE_CHAT" }, party).reason, "not in an instance group",
        "INSTANCE_CHAT needs an instance group")
    T.Eq(Chat.Decide({ text = "x", channel = "INSTANCE_CHAT" }, { instanceGroup = true }).action, "send", "and goes in one")
    T.Eq(Chat.Decide({ text = "x", channel = "SAY" }, party).reason, "SAY needs a key press", "SAY from a timer")
    T.Eq(Chat.Decide({ text = "x", channel = "SAY", pressed = true }, party).action, "send", "SAY from a press")
    T.Eq(Chat.Decide({ text = "x", channel = "GUILD" }, party).reason, "no such channel: GUILD", "an unknown channel")
    local maybe = { group = "group" }
    T.Eq(Chat.Decide({ text = "x", channel = "RAID" }, maybe).reason, "cannot tell whether this is a raid",
        "a group that may be a raid does not guess")
    T.Eq(Chat.Decide({ text = "x", channels = { "RAID", "PARTY" } }, maybe).channel, "PARTY", "PARTY works either way")
end)

T.Case("Chat.Decide: locked chat queues or refuses, as the line asks", function()
    local plan = Chat.Decide({ text = "x", channel = "RAID", whenLocked = "queue" }, RaidLead({ chat = true }))
    T.Eq(plan.action, "queue", "a death call waits")
    T.Eq(plan.channel, "RAID", "knowing where it will go")
    T.Eq(plan.reason, "chat is locked here", "and why")
    plan = Chat.Decide({ text = "x", channel = "RAID" }, RaidLead({ chat = true }))
    T.Eq(plan.action, "refuse", "a pre-pull line is refused")
    T.Eq(plan.reason, "chat is locked here", "with the same reason")
    local inside = RaidLead({ inInstance = true })
    T.Eq(Chat.Decide({ text = "x", channel = "RAID" }, inside).action, "send", "following the client, an open instance sends")
    inside.instance = "locked"
    T.Eq(Chat.Decide({ text = "x", channel = "RAID" }, inside).reason, "chat is locked here",
        "the locked policy treats every instance as locked")
    inside.inInstance = false
    T.Eq(Chat.Decide({ text = "x", channel = "RAID" }, inside).action, "send", "and nowhere else")
end)

T.Case("Chat.Budget: lines per window, per channel", function()
    local s = RaidLead({ sent = { RAID_WARNING = { 95, 99 }, RAID = { 91, 92, 93, 99 } } })
    T.Eq(Chat.Budget("RAID_WARNING", s), 5, "two warnings in ten seconds: wait for the older to age out")
    T.Eq(Chat.Budget("RAID", s), 1, "four raid lines: one second to go")
    T.Eq(Chat.Budget("PARTY", s), 0, "an unused channel is free")
    s.now = 106
    T.Eq(Chat.Budget("RAID_WARNING", s), 0, "after the window it is free again")
    s.budget = { RAID = { 10, 10 } }
    s.now = 100
    T.Eq(Chat.Budget("RAID", s), 0, "a sender's own budget is used")
    local plan = Chat.Decide({ text = "x", channel = "RAID_WARNING", whenLocked = "queue" },
        RaidLead({ sent = { RAID_WARNING = { 95, 99 } } }))
    T.Eq(plan.action, "queue", "over budget, a queueable line waits")
    T.Eq(plan.wait, 5, "saying how long")
end)

T.Case("Chat.Flush: sends what may go, drops what expired, keeps the rest", function()
    local queue = {
        { line = { text = "old", channel = "RAID", whenLocked = "queue" }, expires = 99 },
        { line = { text = "a", channel = "RAID", whenLocked = "queue" }, expires = 110 },
        { line = { text = "b", channel = "RAID_WARNING", whenLocked = "queue" }, expires = 110 },
        { line = { text = "c", channel = "RAID_WARNING", whenLocked = "queue" }, expires = 110 },
        { line = { text = "d", channel = "RAID_WARNING", whenLocked = "queue" }, expires = 110 },
    }
    local state = RaidLead({ sent = {} })
    local out = Chat.Flush(queue, state)
    T.Eq(#out.dropped, 1, "one expired")
    T.Eq(out.dropped[1].reason, "expired", "said so")
    T.Eq(#out.send, 3, "three go")
    T.Eq(out.send[3].text, "c", "in the order they were said")
    T.Eq(#out.keep, 1, "the third warning waits for the budget")
    T.Eq(out.keep[1].line.text, "d", "and it is the last one")
    T.Eq(next(state.sent), nil, "the caller's record is not touched")
    out = Chat.Flush(queue, RaidLead({ chat = true }))
    T.Eq(#out.keep, 4, "while chat is locked everything unexpired waits")
    out = Chat.Flush(queue, RaidLead({ group = "party" }))
    T.Eq(out.dropped[2].reason, "not in a raid", "a line the group no longer allows is dropped with why")
end)

T.Case("Chat.New: a sender holds a locked line and sends it when the lock lifts", function()
    -- Headless only: in game, writing these globals would taint them.
    if not IC_HEADLESS then return end
    local saved = { SendChatMessage = SendChatMessage, GetTime = GetTime, C_Timer = C_Timer }
    local savedNow, savedGroup = Restrict.Now, Group.Now
    local clock, said, timers = 100, {}, {}
    local locked = true
    _G.GetTime = function() return clock end
    _G.SendChatMessage = function(text, channel) said[#said + 1] = channel .. ": " .. text end
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    Restrict.Now = function() return Restrict.State({ chatLockdown = locked }) end
    Group.Now = function() return { kind = "raid", canMark = true } end

    local frame = Restrict.frame
    frame:GetScript("OnEvent")(frame, "ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
    local drops = {}
    local chat = Chat.New({ ttl = 5, onDrop = function(entry, reason) drops[#drops + 1] = reason end })
    local plan = chat:Say({ text = "Healer down", channels = { "RAID_WARNING", "RAID" }, whenLocked = "queue" })
    T.Eq(plan.action, "queue", "held while chat is locked")
    T.Eq(#chat:Queue(), 1, "one line waiting")
    T.Eq(timers[1].seconds, 1, "and a look again in a second")
    T.Eq(chat:Say({ text = "Pull in 10", channel = "RAID" }).action, "refuse", "a pre-pull line is refused")

    locked = false
    frame:GetScript("OnEvent")(frame, "ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
    T.Eq(said[1], "RAID_WARNING: Healer down", "the lock lifting sends it")
    T.Eq(#chat:Queue(), 0, "and the queue is empty")

    locked = true
    frame:GetScript("OnEvent")(frame, "ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
    chat:Say({ text = "Tank down", channel = "RAID", whenLocked = "queue" })
    clock = 101
    timers[#timers].fn()
    T.Eq(#chat:Queue(), 1, "still locked a second later, it still waits")
    locked = false
    clock = 102
    timers[#timers].fn()
    T.Eq(said[2], "RAID: Tank down", "a lock that lifts without the event is caught by the next look")
    locked = true
    chat:Say({ text = "Mage down", channel = "RAID", whenLocked = "queue" })
    clock = 108
    timers[#timers].fn()
    T.Eq(drops[1], "expired", "a line the lock outlasts is dropped and reported")
    T.Eq(#said, 2, "never sent")

    locked = false
    frame:GetScript("OnEvent")(frame, "ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
    T.Eq(chat:Say({ text = "Ready", channel = "RAID" }).action, "send", "open chat sends at once")
    T.Eq(said[3], "RAID: Ready", "and is said")
    chat.stop()

    Restrict.Now, Group.Now = savedNow, savedGroup
    for k, v in pairs(saved) do _G[k] = v end
end)

--------------------------------------------------------------------------------
-- LibICComm
--------------------------------------------------------------------------------

local Comm = LibStub("LibICComm-1.0")

T.Case("Comm.Frame and Assemble: a message of any length comes back whole", function()
    local frames = Comm.Frame("short", 5)
    T.Eq(#frames, 1, "a short message is one frame")
    T.Eq(frames[1], "S05short", "kind, two-digit id, then the text")
    T.Eq(Comm.Assemble({}, "A", frames[1], 0), "short", "and reads back at once")
    local long = string.rep("abcdefghij", 60)
    frames = Comm.Frame(long, 37)
    T.Eq(#frames, 3, "600 bytes is three frames")
    T.Eq(frames[1]:sub(1, 3), "F11", "first, id 37 in base 36")
    T.Eq(frames[2]:sub(1, 1), "M", "middle")
    T.Eq(frames[3]:sub(1, 1), "L", "last")
    for _, f in ipairs(frames) do T.True(#f <= 255, "every frame fits one message") end
    local buffers = {}
    local other = Comm.Frame(string.rep("z", 300), 1)
    T.Eq(Comm.Assemble(buffers, "A", frames[1], 0), nil, "a first frame waits")
    T.Eq(Comm.Assemble(buffers, "B", other[1], 0), nil, "another sender's first frame waits beside it")
    T.Eq(Comm.Assemble(buffers, "A", frames[2], 1), nil, "a middle frame waits")
    T.Eq(Comm.Assemble(buffers, "B", other[2], 1), string.rep("z", 300), "B's finishes")
    T.Eq(Comm.Assemble(buffers, "A", frames[3], 2), long, "and so does A's, unmixed")
    T.Eq(next(buffers), nil, "nothing left over")
    T.Eq(Comm.Assemble(buffers, "A", frames[3], 3), nil, "a last frame with no first is dropped")
    Comm.Assemble(buffers, "A", frames[1], 10)
    T.Eq(Comm.Assemble(buffers, "A", frames[2], 50), nil, "a partial older than thirty seconds is dropped")
    T.Eq(next(buffers), nil, "and forgotten")
    T.Eq(Comm.Assemble({}, "A", "S0", 0), nil, "a frame too short to have a header is ignored")
end)

T.Case("Comm.Channel, Result and Newer", function()
    T.Eq(Comm.Channel({ group = "party" }), "PARTY", "a party")
    T.Eq(Comm.Channel({ group = "raid" }), "RAID", "a raid")
    T.Eq(Comm.Channel({ group = "party", instanceGroup = true }), "INSTANCE_CHAT", "an instance group first")
    local ch, why = Comm.Channel({ group = "raid", raid = "off" })
    T.Eq(ch, nil, "raids can be switched off")
    T.Eq(why, "addon messages are off in raids", "and say so")
    T.Eq(select(2, Comm.Channel({ group = "group" })), "cannot tell whether this is a raid", "a maybe-raid")
    T.Eq(select(2, Comm.Channel({ group = "solo" })), "not in a group", "alone")
    T.Eq(Comm.Result("Success"), "sent", "success")
    T.Eq(Comm.Result("AddOnMessageLockdown"), "hold", "lockdown holds")
    T.Eq(Comm.Result("ChannelThrottle"), "retry", "throttle retries")
    local verdict, reason = Comm.Result("NotInGroup")
    T.Eq(verdict, "drop", "not in a group drops")
    T.Eq(reason, "not in a group for that channel", "with why")
    T.Eq(select(2, Comm.Result("Mystery")), "the client said Mystery", "an unknown result is dropped by name")
    T.Eq(Comm.Newer("1.2.10", "1.2.9"), true, "parts compare as numbers")
    T.Eq(Comm.Newer("1.2.0", "1.2"), false, "a missing part is zero")
    T.Eq(Comm.Newer("0.2.0", "0.10.0"), false, "older is not newer")
    T.Eq(Comm.Newer("1.0.0", nil), true, "anything beats no version")
    T.Eq(Comm.Newer(nil, "1.0.0"), false, "and no version beats nothing")
end)

T.Case("Comm.New: send, loop back, receive, hold through a lockdown", function()
    -- Headless only: in game, writing these globals would taint them.
    if not IC_HEADLESS then return end
    local saved = { C_ChatInfo = C_ChatInfo, GetTime = GetTime, C_Timer = C_Timer, UnitGUID = UnitGUID }
    local savedGroup = Group.Now
    local clock, wire, timers, result = 100, {}, {}, 0
    _G.GetTime = function() return clock end
    _G.UnitGUID = function() return "G-me" end
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, text, channel)
            if result == 0 then wire[#wire + 1] = { prefix, text, channel } end
            return result
        end,
    }
    Group.Now = function() return { kind = "party", kindKnown = true } end

    local drops = {}
    local mine = Comm.New("ICKitCase", { version = "1.0.0", onDrop = function(_, reason) drops[#drops + 1] = reason end })
    local theirs = Comm.New("ICKitCase", { version = "1.1.0" })
    theirs.me = "G-them"
    local got = {}
    theirs:On("plan", function(msg, from) got[#got + 1] = { msg = msg, from = from } end)
    mine:On("plan", function() got[#got + 1] = "echo" end)
    T.Eq(mine.frame:IsEventRegistered("CHAT_MSG_ADDON"), true, "listens for addon messages")

    local plan = mine:Send({ t = "plan", note = string.rep("x", 400) })
    T.Eq(plan.action, "send", "sent at once")
    T.Eq(plan.channel, "PARTY", "to the party")
    T.Eq(#wire, 2, "as two frames")
    for _, w in ipairs(wire) do
        mine:Receive(w[1], w[2], w[3], "Mal Exis")
        theirs:Receive(w[1], w[2], w[3], "Mal Exis")
    end
    T.Eq(#got, 1, "the looped-back copy is dropped")
    T.Eq(got[1].msg.note, string.rep("x", 400), "the other client gets it whole")
    T.Eq(got[1].from, "Mal Exis", "from the sender")
    theirs:Receive("SomeoneElse", wire[1][2], "PARTY", "Mal Exis")
    T.Eq(#got, 1, "another prefix is ignored")

    wire = {}
    mine:Hello()
    theirs:Receive(wire[1][1], wire[1][2], wire[1][3], "Mal Exis")
    T.Eq(theirs:Peers()["G-me"].version, "1.0.0", "a hello is recorded with its version")
    T.Eq(#wire, 2, "and answered once")
    mine:Receive(wire[2][1], wire[2][2], wire[2][3], "Solo Siphyr")
    T.Eq(mine:Peers()["G-them"].version, "1.1.0", "the answer is recorded too")
    T.Eq(#wire, 2, "and not answered back")
    theirs:Receive(wire[1][1], wire[1][2], wire[1][3], "Mal Exis")
    T.Eq(#wire, 2, "a second hello within a minute is not answered again")

    result = 11
    plan = mine:Send({ t = "plan" })
    T.Eq(plan.action, "queue", "a lockdown holds the message")
    T.Eq(plan.reason, "addon messages are locked down", "and says why")
    result = 0
    timers[#timers]()
    T.Eq(#mine:Queue(), 0, "the next try sends it")
    T.Eq(#wire, 3, "on the wire")
    result = 5
    T.Eq(mine:Send({ t = "plan" }).action, "refuse", "a refusal from the client")
    T.Eq(drops[1], "not in a group for that channel", "is reported")
    result = 11
    mine:Send({ t = "plan" })
    clock = 140
    timers[#timers]()
    T.Eq(drops[2], "addon messages are locked down", "a lockdown that outlasts the ttl drops with its reason")
    T.Eq(mine:Send({ x = 1 }).reason, "a message needs a type, msg.t", "a message without a type is refused")

    mine.stop()
    theirs.stop()
    Group.Now = savedGroup
    for k, v in pairs(saved) do _G[k] = v end
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

T.Case("Widgets: a slider reports whole steps, and both of its ends", function()
    T.Near(W.SliderValue(0.674, 0.3334, 2, 0.01), 0.67, "snapped to the step")
    T.Near(W.SliderValue(0.35, 0.3334, 2, 0.01), 0.35, "a whole step inside the range")
    T.Eq(W.SliderValue(0.34, 0.3334, 2, 0.01), 0.3334, "the first whole step is the floor itself, off the step or not")
    T.Eq(W.SliderValue(0.1, 0.3334, 2, 0.01), 0.3334, "and so is anything under it")
    T.Eq(W.SliderValue(2, 0.3334, 2, 0.01), 2, "the ceiling")
    T.Eq(W.SliderValue(5.4, 0, 9, 1), 5, "whole numbers")
    T.Eq(W.SliderValue(nil, 0, 9, 1), 0, "no position is the floor")
end)

T.Case("Widgets: a slider and a choice keep their value and report a change, not a SetValue", function()
    local p = W.Panel(nil, { width = 240, height = 60 })
    p:Hide()

    local got = {}
    local s = W.Slider(p, {
        min = 0, max = 10, step = 1, value = 4,
        format = function(v) return v .. " fps" end,
        onChange = function(v) got[#got + 1] = v end,
    })
    T.Eq(s:GetValue(), 4, "a slider starts where it is told")
    T.Eq(s.text:GetText(), "4 fps", "and writes its value beside it")
    s:SetValue(7)
    T.Eq(s:GetValue(), 7, "it moves when told")
    T.Eq(s.text:GetText(), "7 fps", "the text follows")
    T.Eq(#got, 0, "without calling the handler")
    s.inner:GetScript("OnValueChanged")(s.inner, 8.2)
    T.Eq(s:GetValue(), 8, "a drag is snapped to the step")
    T.Eq(got[1], 8, "and reported")
    s:SetValue(99)
    T.Eq(s:GetValue(), 10, "a value past the end sits on the end")

    -- One that waits for the thumb to be let go: for a change too heavy to make per step.
    local late = {}
    local w = W.Slider(p, { min = 0, max = 10, step = 1, value = 0, live = false,
        onChange = function(v) late[#late + 1] = v end })
    w.inner:GetScript("OnMouseDown")(w.inner)
    w.inner:GetScript("OnValueChanged")(w.inner, 3)
    w.inner:GetScript("OnValueChanged")(w.inner, 5)
    T.Eq(w:GetValue(), 5, "it follows the drag")
    T.Eq(#late, 0, "and says nothing while held")
    w.inner:GetScript("OnMouseUp")(w.inner)
    T.Eq(#late, 1, "one report on release")
    T.Eq(late[1], 5, "of where it ended")
    w.inner:GetScript("OnValueChanged")(w.inner, 6)
    T.Eq(late[2], 6, "a stepper click, with nothing held, reports at once")

    local picked
    local c = W.Choice(p, 100, 20, {
        choices = { { 0, "None" }, { 4, "CMAA2" } }, value = 4,
        onChange = function(v) picked = v end,
    })
    T.Eq(c.label:GetText(), "CMAA2", "a choice shows the label of its value")
    c:SetValue(0)
    T.Eq(c:GetValue(), 0, "it changes when told")
    T.Eq(c.label:GetText(), "None", "and the label follows")
    T.Eq(picked, nil, "without calling the handler")
    c:SetValue(9)
    T.Eq(c.label:GetText(), "9", "a value with no label shows itself")
end)

T.Case("Widgets: a scroll view stays inside its content, and its bar shows only when needed", function()
    local offset, range = W.ScrollClamp(50, 300, 100)
    T.Eq(offset, 50, "an offset inside the range is kept")
    T.Eq(range, 200, "the range is the content less the view")
    T.Eq(W.ScrollClamp(-10, 300, 100), 0, "not above the top")
    T.Eq(W.ScrollClamp(999, 300, 100), 200, "not past the bottom")
    T.Eq(W.ScrollClamp(40, 80, 100), 0, "content that fits does not scroll")

    local p = W.Panel(nil, { width = 240, height = 120 })
    p:Hide()
    local s = W.Scroll(p, 200, 100, { step = 24 })
    s:SetContentHeight(300)
    T.Eq(s.bar:IsShown(), true, "taller content shows the bar")
    s:GetScript("OnMouseWheel")(s, -1)
    T.Eq(s:GetOffset(), 24, "one notch down moves one step")
    s:GetScript("OnMouseWheel")(s, 1)
    s:GetScript("OnMouseWheel")(s, 1)
    T.Eq(s:GetOffset(), 0, "and it stops at the top")
    s:ScrollTo(999)
    T.Eq(s:GetOffset(), 200, "and at the bottom")
    s.bar:GetScript("OnValueChanged")(s.bar, 120)
    T.Eq(s:GetOffset(), 120, "dragging the bar scrolls")
    s:SetContentHeight(150)
    T.Eq(s:GetOffset(), 50, "shorter content pulls the view back inside it")
    s:SetContentHeight(60)
    T.Eq(s.bar:IsShown(), false, "content that fits hides the bar")
    T.Eq(s:GetOffset(), 0, "at the top")
    s:SetViewHeight(40)
    T.Eq(s.bar:IsShown(), true, "a window made shorter than its content shows the bar")
    s:SetViewHeight(100)
    T.Eq(s.bar:IsShown(), false, "and made taller hides it again")

    -- A slider's value can be typed over, and says when its thumb is picked up and put down.
    local typedValue, holds = nil, {}
    local slider = W.Slider(p, {
        min = 0, max = 10, step = 1, value = 3, width = 200,
        onType = function(text) typedValue = text end,
        onHold = function(held) holds[#holds + 1] = held end,
    })
    slider.entry:SetText("7")
    slider.entry:GetScript("OnEnterPressed")(slider.entry)
    T.Eq(typedValue, "7", "Enter sends what was typed")
    slider.inner:GetScript("OnMouseDown")(slider.inner)
    slider.inner:GetScript("OnMouseUp")(slider.inner)
    T.Eq(table.concat({ tostring(holds[1]), tostring(holds[2]) }, ","), "true,false", "held, then let go")
    T.Eq(rawget(W.Slider(p, { min = 0, max = 1, step = 0.1 }), "entry"), nil, "no typing unless asked for")

    local typed = {}
    local edit = W.EditBox(p, 100, 18, { onChange = function(text) typed[#typed + 1] = text end })
    edit:SetText("sha")
    edit:GetScript("OnTextChanged")(edit, true)
    T.Eq(typed[1], "sha", "an edit box reports what the player types")
    edit:GetScript("OnTextChanged")(edit, false)
    T.Eq(#typed, 1, "and not a change made for it")
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

T.Case("Widgets: Tab in an edit box and a drag on a button reach the addon", function()
    local p = W.Panel(nil, { width = 120, height = 60 })
    p:Hide()
    local tabs = {}
    local edit = W.EditBox(p, 100, 18, { onTab = function(_, backwards) tabs[#tabs + 1] = backwards end })
    edit:GetScript("OnTabPressed")(edit)
    T.Eq(#tabs, 1, "Tab is passed on")
    T.Eq(type(tabs[1]), "boolean", "with whether Shift was held")

    local events = {}
    local row = W.Button(p, "a row", 80, 18, {
        onDragStart = function() events[#events + 1] = "up" end,
        onDragStop = function() events[#events + 1] = "down" end,
    })
    row:GetScript("OnDragStart")(row)
    row:GetScript("OnDragStop")(row)
    T.Eq(table.concat(events, ","), "up,down", "a button that asked hears a drag start and stop")
    T.Eq(W.Button(p, "plain", 80, 18):GetScript("OnDragStart"), nil, "one that did not is not draggable")
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

T.Case("Widgets: tabs lay out, shrinking alike when they would not fit", function()
    local l = W.TabLayout(3, 400, 96)
    T.Eq(l[1].x, 0, "the first at the left")
    T.Eq(l[2].x, 98, "the next a tab and a gap along")
    T.Eq(l[3].w, 96, "full width when there is room")
    l = W.TabLayout(4, 200, 96)
    T.Eq(l[1].w, 48, "four in 200 shrink to 48 each")
    T.True(l[4].x + l[4].w <= 200, "and fit")
    T.Eq(#W.TabLayout(0, 100), 0, "no tabs, no layout")
    T.Eq(W.TabLayout(2, nil, 50)[2].x, 52, "no width means room for all")
end)

T.Case("Widgets: tabs select one, show its page, and refuse a disabled one", function()
    local host = W.Panel(nil, { width = 300, height = 200 })
    host:Hide()
    local pageA, pageB = CreateFrame("Frame", nil, host), CreateFrame("Frame", nil, host)
    local picked = {}
    local strip = W.Tabs(host, {
        { key = "a", label = "Roles", page = pageA },
        { key = "b", label = "Rules", page = pageB },
        { key = "c", label = "Deaths" },
    }, { width = 300, onSelect = function(key) picked[#picked + 1] = key end })
    T.Eq(strip:GetSelected(), "a", "the first tab is selected to start")
    T.Eq(pageA:IsShown() and not pageB:IsShown(), true, "its page shows, the other hides")
    strip.buttons.b:GetScript("OnClick")(strip.buttons.b)
    T.Eq(strip:GetSelected(), "b", "a click selects")
    T.Eq(picked[1], "b", "and is reported")
    T.Eq(pageB:IsShown() and not pageA:IsShown(), true, "and swaps the pages")
    strip.buttons.b:GetScript("OnClick")(strip.buttons.b)
    T.Eq(#picked, 1, "clicking the selected tab again says nothing")
    T.Eq(strip:Select("c"), true, "Select works on a tab with no page")
    T.Eq(#picked, 1, "and does not report")
    T.Eq(pageA:IsShown() or pageB:IsShown(), false, "every page hides")
    T.Eq(strip:Select("nope"), false, "an unknown key is refused")
    T.Eq(strip:GetSelected(), "c", "and changes nothing")
    strip:SetDisabled("a", "Needs a raid")
    strip.buttons.a:GetScript("OnClick")(strip.buttons.a)
    T.Eq(strip:GetSelected(), "c", "a disabled tab cannot be picked")
    T.Eq(strip.buttons.a.icDisabled, "Needs a raid", "and keeps its reason for the tooltip")
    strip:SetDisabled("a", nil)
    strip.buttons.a:GetScript("OnClick")(strip.buttons.a)
    T.Eq(strip:GetSelected(), "a", "enabled again, it can")
    strip:SetLabel("b", "Rules (3)")
    T.Eq(strip.buttons.b.label:GetText(), "Rules (3)", "a label can change")
    local other = W.Tabs(host, { { key = "x" }, { key = "y" } }, { selected = "y" })
    T.Eq(other:GetSelected(), "y", "a starting tab can be named")
    T.Eq(W.Tabs(host, { { key = "x" } }, { selected = "zz" }):GetSelected(), "x",
        "an unknown starting tab falls back to the first")
end)

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
