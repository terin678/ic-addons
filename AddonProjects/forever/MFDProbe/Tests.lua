local addonName, ns = ...

-- The cases: headless with scripts/run-tests.ps1 -Flavor forever -Addon MFDProbe, and in
-- game with /mfdp test. Every one builds its own tables and its own secret test; none
-- asks the client anything.

local T = ns.Tests
local Report = ns.Report

-- A stand-in for the client's secret test: a value is secret when it is this table.
local SECRET = setmetatable({}, { __tostring = function() error("a secret was turned into text") end })
local function IsSecret(v) return v == SECRET end
local SECRET_TABLE = {}
local function IsSecretTable(t) return t == SECRET_TABLE end

T.Case("Describe: plain values, cut text, and a secret recognised before it is touched", function()
    T.Eq((Report.Describe(nil, IsSecret)), "nil", "nil")
    T.Eq((Report.Describe(true, IsSecret)), "true", "boolean")
    T.Eq((Report.Describe(42, IsSecret)), "42", "number")
    T.Eq((Report.Describe("Defias Pillager", IsSecret)), '"Defias Pillager"', "string quoted")
    T.Eq((Report.Describe("a|cffb", IsSecret)), '"a||cffb"', "a pipe cannot start an escape in chat")
    local long = Report.Describe(string.rep("x", 80), IsSecret)
    T.Eq(#long, Report.TEXT_LIMIT + 5, "cut to the limit, plus quotes and dots")
    local text, secret = Report.Describe(SECRET, IsSecret)
    T.Eq(text, "<secret>", "a secret says so")
    T.Eq(secret, true, "and is flagged")
    T.Eq((Report.Describe({ 1, 2, 3 }, IsSecret, IsSecretTable)), "table(3)", "a table counts its keys")
    T.Eq((Report.Describe(SECRET_TABLE, IsSecret, IsSecretTable)), "<secret table>", "a secret table says so")
    T.Eq((Report.Describe("x", nil)), '"x"', "no secret test on a client without one")
end)

T.Case("Describe: a secret test that throws is treated as not secret", function()
    local text, secret = Report.Describe(5, function() error("boom") end)
    T.Eq(text, "5", "the value is still described")
    T.Eq(secret, false, "and not called secret")
end)

T.Case("Row: each way a call can come out", function()
    local row = Report.Row("unit.plate.UnitHealth", { ok = true, n = 1, values = { 1200 } }, false, IsSecret)
    T.Eq(row.outcome, "ok", "a plain value")
    T.Eq(row.v, "1200", "described")
    T.Eq(row.combat, false, "out of combat")

    row = Report.Row("x", { ok = true, n = 2, values = { "Hogger", SECRET } }, true, IsSecret)
    T.Eq(row.outcome, "secret", "one secret return makes the row secret")
    T.Eq(row.v, '"Hogger", <secret>', "every return described")
    T.Eq(row.combat, true, "in combat")

    T.Eq(Report.Row("x", { ok = true, n = 0, values = {} }, false).outcome, "none", "nothing returned")
    T.Eq(Report.Row("x", { ok = true, n = 1, values = {} }, false).v, "nil", "a nil return is still a return")
    row = Report.Row("x", { ok = false, err = "not a function" }, false)
    T.Eq(row.outcome, "absent", "a missing function")
    row = Report.Row("x", { ok = false, err = "blocked" }, false)
    T.Eq(row.outcome, "error", "a throw")
    T.Eq(row.v, "blocked", "keeps the message")
end)

T.Case("ContextLabel: solo, party leader, raid assist, restrictions", function()
    T.Eq(Report.ContextLabel({}), "out of combat, solo, open world", "the empty case")
    T.Eq(Report.ContextLabel({ combat = true, group = "party", size = 5, instanceType = "party",
        instanceName = "Deadmines", leader = true }),
        "in combat, party of 5, party instance Deadmines, leader", "a dungeon pull")
    T.Eq(Report.ContextLabel({ group = "raid", size = 20, instanceType = "raid", assist = true,
        restricted = { "Combat", "Encounter" } }),
        "out of combat, raid of 20, raid instance, assist, restrictions on: Combat Encounter", "a raid")
    T.Eq(Report.ContextLabel({ group = "party", size = 3, instanceType = "none" }),
        "out of combat, party of 3, open world, not leader or assist", "a plain member")
end)

T.Case("Matrix: outcomes split by combat, merged across runs, ids sorted", function()
    local runs = {
        { rows = {
            { id = "unit.plate.UnitHealth", outcome = "ok", combat = false },
            { id = "mark.target.readback", outcome = "ok", combat = false },
        } },
        { rows = {
            { id = "unit.plate.UnitHealth", outcome = "secret", combat = true },
            { id = "unit.plate.UnitHealth", outcome = "ok", combat = true },
            { id = "mark.target.readback", outcome = "refused", combat = true },
            { id = "forbidden.SetRaidTarget", outcome = "blocked", combat = true },
        } },
    }
    local m = Report.Matrix(runs)
    T.Eq(#m, 3, "three ids")
    T.Eq(m[1].id, "forbidden.SetRaidTarget", "sorted")
    T.Eq(m[1].out, "-", "never seen out of combat")
    T.Eq(m[1].inside, "blocked", "blocked in combat")
    T.Eq(m[2].id, "mark.target.readback", "second")
    T.Eq(m[2].out .. "|" .. m[2].inside, "ok|refused", "took out of combat, refused in it")
    T.Eq(m[3].inside, "ok/secret", "two outcomes in one state are both kept, sorted")
end)

T.Case("MatrixLines: plain rows fold into a count, a filter shows everything that matches", function()
    local m = {
        { id = "a.one", out = "ok", inside = "ok" },
        { id = "a.two", out = "ok", inside = "-" },
        { id = "b.three", out = "ok", inside = "secret" },
    }
    local lines = Report.MatrixLines(m)
    T.Eq(#lines, 2, "a count line and the one that differs")
    T.True(lines[1]:find("2 checks", 1, true), "the count")
    T.True(lines[2]:find("b.three: out of combat ok, in combat secret", 1, true), "the difference")
    lines = Report.MatrixLines(m, "a.")
    T.Eq(#lines, 2, "the filter shows plain rows too")
    T.True(lines[1]:find("a.one", 1, true), "first match")
end)

T.Case("RunLines: header, counts in a fixed order, events heard", function()
    local run = {
        id = 7, phase = "pull +3s", trigger = "auto", ctx = { combat = true },
        rows = { { outcome = "secret" }, { outcome = "ok" }, { outcome = "ok" }, { outcome = "blocked" } },
        events = { UNIT_FLAGS = { count = 4 }, ["CLEU:UNIT_DIED"] = { count = 1 } },
    }
    local lines = Report.RunLines(run)
    T.True(lines[1]:find("run 7, pull +3s (auto): in combat, solo", 1, true), "header")
    T.Eq(lines[2], "  2 ok, 1 secret, 1 blocked", "counts")
    T.Eq(lines[3], "  events heard: CLEU:UNIT_DIED 1, UNIT_FLAGS 4", "events sorted")
    T.Eq(Report.RunLines({ id = 1, rows = {} })[2], "  no rows yet", "an empty run")
end)

T.Case("Shape: sorted keys, capped, secrets inside named", function()
    local fields = Report.Shape({ b = 2, a = "x", c = SECRET }, IsSecret, IsSecretTable, 2)
    T.Eq(#fields, 2, "capped")
    T.Eq(fields[1].key .. "=" .. fields[1].text, 'a="x"', "sorted first")
    T.Eq(fields[2].key, "b", "then b")
    fields = Report.Shape({ c = SECRET }, IsSecret, IsSecretTable)
    T.Eq(fields[1].secret, true, "a secret field")
    fields = Report.Shape(SECRET_TABLE, IsSecret, IsSecretTable)
    T.Eq(#fields, 1, "a secret table is one entry")
    T.Eq(fields[1].text, "<secret table>", "and says so")
    T.Eq(Report.Shape(nil, IsSecret)[1].text, "nil", "not a table")
end)

T.Case("Trim: newest kept, oldest first", function()
    local kept = Report.Trim({ 1, 2, 3, 4, 5 }, 3)
    T.Eq(table.concat(kept, ","), "3,4,5", "the last three")
    T.Eq(#Report.Trim({ 1 }, 3), 1, "short lists untouched")
    T.Eq(#Report.Trim(nil, 3), 0, "nothing")
end)

-- Headless only: in game this would set marks and send chat. Every check runs against
-- the stub client, where most functions are missing, and none may throw.
T.Case("Checks.Run: every check runs on a client that has almost nothing", function()
    if not IC_HEADLESS or not ns.db then return end
    local hadTime = GetTime
    if not hadTime then _G.GetTime = function() return 0 end end
    local before = #ns.db.runs
    local run = ns.Checks.Run("smoke", "test", true)
    if not hadTime then _G.GetTime = nil end
    for _, row in ipairs(run.rows) do
        T.True(row.id ~= "probe.fault", "no check threw: " .. tostring(row.v))
    end
    T.True(#run.rows > 20, "rows were written")
    ns.Listen.Stop()
    ns.db.runs[#ns.db.runs] = nil
    T.Eq(#ns.db.runs, before, "the run is taken back out")
end)
