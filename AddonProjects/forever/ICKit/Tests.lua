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
-- The addon itself
--------------------------------------------------------------------------------

T.Case("Build: the client's answer reads as one phrase", function()
    T.Eq(ns.DescribeBuild("1.60.1", "70124", "Sep 30 2026", 16001), "1.60.1 (70124), interface 16001",
        "version, build and interface")
    T.Eq(ns.DescribeBuild(), "? (?), interface ?", "a client that answers nothing is still described")
    T.Eq(select(4, GetBuildInfo()), 16001, "and this addon's .toc targets the Forever client")
end)
