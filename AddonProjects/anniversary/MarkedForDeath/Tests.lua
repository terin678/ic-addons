-- Test registry and runner. Ships with the addon so correctness is checkable
-- on the live client with /mfd selftest, and runs headlessly under LuaJIT via
-- scripts/run-tests.ps1 because the modules under test call no WoW API.
local MFD = _G.MarkedForDeath or {}

MFD.Tests = MFD.Tests or {}
local T = MFD.Tests
T.cases = T.cases or {}

-- Output goes through MFD.Print in game and plain print headlessly.
local function out(msg)
    if MFD.Print then
        MFD.Print(msg)
    else
        print(msg)
    end
end

function T.Case(name, fn)
    T.cases[#T.cases + 1] = { name = name, fn = fn }
end

function T.Eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected [%s], got [%s]",
            tostring(label or "value"), tostring(expected), tostring(actual)), 2)
    end
end

-- Compares two tables one level deep. Enough for the assignment maps and
-- seat lists the pure modules return; deliberately not a deep compare.
function T.EqShallow(actual, expected, label)
    if type(actual) ~= "table" then
        error(string.format("%s: expected a table, got [%s]", tostring(label), type(actual)), 2)
    end
    for k, v in pairs(expected) do
        if actual[k] ~= v then
            error(string.format("%s[%s]: expected [%s], got [%s]",
                tostring(label), tostring(k), tostring(v), tostring(actual[k])), 2)
        end
    end
    for k in pairs(actual) do
        if expected[k] == nil then
            error(string.format("%s[%s]: unexpected extra key", tostring(label), tostring(k)), 2)
        end
    end
end

-- Runs every registered case. Returns true when all passed. Failures are also
-- written to saved variables in game so they survive a /reload and can be read
-- off disk instead of retyped out of the chat frame.
function T.Run()
    local pass, failures = 0, {}

    for _, c in ipairs(T.cases) do
        local ok, err = pcall(c.fn)
        if ok then
            pass = pass + 1
        else
            failures[#failures + 1] = c.name .. " => " .. tostring(err)
            out("|cffff4444FAIL|r " .. c.name .. " => " .. tostring(err))
        end
    end

    if MFD.db then
        MFD.db.lastTestRun = { at = time(), passed = pass, failures = failures }
    end

    out(string.format("%d passed, %d failed, %d total", pass, #failures, #T.cases))
    return #failures == 0
end

T.Case("SplitGUID returns npcID and spawnUID from a creature GUID", function()
    local npcID, spawnUID = MFD.H.SplitGUID("Creature-0-3299-530-1-22890-000082EE7C")
    T.Eq(npcID, 22890, "npcID")
    T.Eq(spawnUID, "000082EE7C", "spawnUID")
end)

T.Case("SplitGUID rejects a player GUID", function()
    T.Eq(MFD.H.SplitGUID("Player-970-0002FA7D"), nil, "player GUID")
end)

T.Case("KeyFromGUID builds the compact wire key", function()
    T.Eq(MFD.H.KeyFromGUID("Creature-0-3299-530-1-22890-000082EE7C"), "22890:000082EE7C", "key")
end)

T.Case("ApplyDefaults fills missing keys without overwriting present ones", function()
    local target = { a = 1, nested = { keep = "yes" } }
    MFD.H.ApplyDefaults(target, { a = 99, b = 2, nested = { keep = "no", added = "x" } })
    T.Eq(target.a, 1, "existing scalar preserved")
    T.Eq(target.b, 2, "missing scalar filled")
    T.Eq(target.nested.keep, "yes", "existing nested preserved")
    T.Eq(target.nested.added, "x", "missing nested filled")
end)

local function roster(...)
    local out = {}
    for i = 1, select("#", ...), 2 do
        out[#out + 1] = { name = select(i, ...), class = select(i + 1, ...) }
    end
    return out
end

T.Case("Seats: a pinned player owns their seat when present", function()
    local plan = {
        [5] = { intent = "SHEEP", ordinal = 1, pin = "Grimmtusk" },
        [4] = { intent = "SHEEP", ordinal = 2 },
    }
    local r = MFD.Seats.Resolve(plan, roster("Alfred", "MAGE", "Grimmtusk", "MAGE"))
    T.Eq(r.byIcon[5].owner, "Grimmtusk", "moon owner")
    T.Eq(r.byIcon[4].owner, "Alfred", "triangle owner")
end)

T.Case("Seats: an absent pin falls through to the next eligible mage", function()
    local plan = {
        [5] = { intent = "SHEEP", ordinal = 1, pin = "Grimmtusk" },
        [4] = { intent = "SHEEP", ordinal = 2 },
    }
    local r = MFD.Seats.Resolve(plan, roster("Alfred", "MAGE", "Zed", "MAGE"))
    T.Eq(r.byIcon[5].owner, "Alfred", "moon falls to first mage by name")
    T.Eq(r.byIcon[4].owner, "Zed", "triangle takes the second")
end)

T.Case("Seats: an intent with no capable class is unowned", function()
    local plan = { [5] = { intent = "SHEEP", ordinal = 1 } }
    local r = MFD.Seats.Resolve(plan, roster("Thok", "WARRIOR"))
    T.Eq(r.byIcon[5].owner, false, "no mage means no sheep owner")
end)

T.Case("Seats: KILL needs no owner", function()
    local plan = { [8] = { intent = "KILL", ordinal = 1 } }
    local r = MFD.Seats.Resolve(plan, roster())
    T.Eq(r.byIcon[8].owner, true, "kill seat is always available")
end)

T.Case("Seats: one player holds at most one seat per intent but may span intents", function()
    local plan = {
        [3] = { intent = "BANISH", ordinal = 1 },
        [2] = { intent = "BANISH", ordinal = 2 },
        [7] = { intent = "FEAR", ordinal = 1 },
    }
    local r = MFD.Seats.Resolve(plan, roster("Nyx", "WARLOCK"))
    T.Eq(r.byIcon[3].owner, "Nyx", "banish seat 1")
    T.Eq(r.byIcon[2].owner, false, "only one warlock, so banish seat 2 is unowned")
    T.Eq(r.byIcon[7].owner, "Nyx", "same warlock also holds fear seat 1")
end)

T.Case("Seats: byIntent is ordered by ordinal", function()
    local plan = {
        [1] = { intent = "KILL", ordinal = 4 },
        [8] = { intent = "KILL", ordinal = 1 },
        [6] = { intent = "KILL", ordinal = 3 },
        [7] = { intent = "KILL", ordinal = 2 },
    }
    local r = MFD.Seats.Resolve(plan, roster())
    T.Eq(r.byIntent.KILL[1].icon, 8, "first is skull")
    T.Eq(r.byIntent.KILL[2].icon, 7, "second is cross")
    T.Eq(r.byIntent.KILL[3].icon, 6, "third is square")
    T.Eq(r.byIntent.KILL[4].icon, 1, "fourth is star")
end)

T.Case("Seats: the default plan matches the agreed icon bindings", function()
    local p = MFD.Seats.DEFAULT_PLAN
    T.Eq(p[8].intent, "KILL", "skull")
    T.Eq(p[7].intent, "KILL", "cross")
    T.Eq(p[6].intent, "KILL", "square")
    T.Eq(p[1].intent, "KILL", "star")
    T.Eq(p[1].ordinal, 4, "star is kill 4")
    T.Eq(p[5].intent, "SHEEP", "moon")
    T.Eq(p[5].pin, "Grimmtusk", "moon is pinned")
    T.Eq(p[4].intent, "SHEEP", "triangle")
    T.Eq(p[3].intent, "BANISH", "diamond")
    T.Eq(p[2].intent, "BANISH", "circle")
end)

_G.MarkedForDeath = MFD
