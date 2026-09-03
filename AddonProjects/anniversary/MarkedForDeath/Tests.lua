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

local function contribution(owner, instanceKey, rules)
    return { owner = owner, rules = { [instanceKey] = rules } }
end

T.Case("Rules: a single contributor's rules pass through with owner stamped", function()
    local merged = MFD.Rules.Merge({
        contribution("Dillon", "BT", { { npcID = 22890, intent = "SHEEP", rank = 10 } }),
    }, "Dillon")
    T.Eq(merged.BT[22890].intent, "SHEEP", "intent")
    T.Eq(merged.BT[22890].owner, "Dillon", "owner stamped")
end)

T.Case("Rules: the lead wins a conflict on the same mob", function()
    local merged = MFD.Rules.Merge({
        contribution("Grimmtusk", "BT", { { npcID = 22890, intent = "BANISH", rank = 5 } }),
        contribution("Dillon", "BT", { { npcID = 22890, intent = "SHEEP", rank = 40 } }),
    }, "Dillon")
    T.Eq(merged.BT[22890].intent, "SHEEP", "lead's intent wins")
    T.Eq(merged.BT[22890].rank, 40, "lead's rank wins too")
    T.Eq(merged.BT[22890].owner, "Dillon", "owner is the lead")
end)

T.Case("Rules: a contributor's rule survives when the lead has none for that mob", function()
    local merged = MFD.Rules.Merge({
        contribution("Grimmtusk", "HYJAL", { { npcID = 17842, intent = "TRAP", rank = 20 } }),
        contribution("Dillon", "BT", { { npcID = 22890, intent = "SHEEP", rank = 10 } }),
    }, "Dillon")
    T.Eq(merged.HYJAL[17842].intent, "TRAP", "contributor rule kept")
    T.Eq(merged.HYJAL[17842].owner, "Grimmtusk", "provenance kept")
end)

T.Case("Rules: without the lead, conflicts resolve by contributor name ascending", function()
    local merged = MFD.Rules.Merge({
        contribution("Zed", "BT", { { npcID = 22890, intent = "BANISH", rank = 5 } }),
        contribution("Alfred", "BT", { { npcID = 22890, intent = "SHEEP", rank = 40 } }),
    }, "Nobody")
    T.Eq(merged.BT[22890].owner, "Alfred", "lowest name wins")
    T.Eq(merged.BT[22890].intent, "SHEEP", "and brings its intent")
end)

T.Case("Rules: merging is order independent", function()
    local a = contribution("Zed", "BT", { { npcID = 1, intent = "KILL", rank = 30 } })
    local b = contribution("Alfred", "BT", { { npcID = 1, intent = "SHEEP", rank = 10 } })
    local forward = MFD.Rules.Merge({ a, b }, "Dillon")
    local backward = MFD.Rules.Merge({ b, a }, "Dillon")
    T.Eq(forward.BT[1].owner, backward.BT[1].owner, "same winner either way")
    T.Eq(forward.BT[1].rank, backward.BT[1].rank, "same rank either way")
end)

T.Case("Rules: Ranked sorts by rank then npcID", function()
    local ranked = MFD.Rules.Ranked({
        [30] = { npcID = 30, rank = 20 },
        [10] = { npcID = 10, rank = 10 },
        [20] = { npcID = 20, rank = 20 },
    })
    T.Eq(ranked[1].npcID, 10, "lowest rank first")
    T.Eq(ranked[2].npcID, 20, "tie broken by npcID ascending")
    T.Eq(ranked[3].npcID, 30, "then the higher npcID")
end)

T.Case("Rules: NextRank appends past the highest existing rank", function()
    T.Eq(MFD.Rules.NextRank({}), 10, "first rule")
    T.Eq(MFD.Rules.NextRank({ { rank = 10 }, { rank = 40 } }), 50, "past the highest")
end)

T.Case("Rules: Reorder moves a rule up and respaces ranks", function()
    local list = {
        { npcID = 1, rank = 10 },
        { npcID = 2, rank = 20 },
        { npcID = 3, rank = 30 },
    }
    MFD.Rules.Reorder(list, 3, -1)
    T.Eq(list[2].npcID, 3, "moved up one place")
    T.Eq(list[3].npcID, 2, "displaced one moved down")
    T.Eq(list[1].rank, 10, "ranks respaced from the step")
    T.Eq(list[2].rank, 20, "second rank")
    T.Eq(list[3].rank, 30, "third rank")
end)

T.Case("Rules: Reorder is a no-op at the boundaries", function()
    local list = { { npcID = 1, rank = 10 }, { npcID = 2, rank = 20 } }
    MFD.Rules.Reorder(list, 1, -1)
    T.Eq(list[1].npcID, 1, "cannot move the first up")
    MFD.Rules.Reorder(list, 2, 1)
    T.Eq(list[2].npcID, 2, "cannot move the last down")
end)

-- Builds the resolved-seat table the allocator consumes, from a plan and a
-- roster, so allocator cases read as intent rather than as plumbing.
local function seatsFor(plan, ...)
    return MFD.Seats.Resolve(plan, roster(...))
end

local KILL_AND_SHEEP = {
    [8] = { intent = "KILL",  ordinal = 1 },
    [7] = { intent = "KILL",  ordinal = 2 },
    [5] = { intent = "SHEEP", ordinal = 1 },
    [4] = { intent = "SHEEP", ordinal = 2 },
    [6] = { intent = "SHEEP", ordinal = 3 },
}

T.Case("Allocator: duplicates of one mob take successive seats of their intent", function()
    local seats = seatsFor(KILL_AND_SHEEP, "Alfred", "MAGE", "Grimmtusk", "MAGE", "Zed", "MAGE")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 }, { key = "100:BBB", npcID = 100 }, { key = "100:CCC", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10 } },
        seats, nil)
    T.Eq(out.byKey["100:AAA"], 5, "first sheep seat")
    T.Eq(out.byKey["100:BBB"], 4, "second sheep seat")
    T.Eq(out.byKey["100:CCC"], 6, "third sheep seat")
end)

T.Case("Allocator: rank decides which mob gets skull, not sighting order", function()
    local seats = seatsFor(KILL_AND_SHEEP)
    local low = { key = "200:AAA", npcID = 200 }
    local high = { key = "100:BBB", npcID = 100 }
    local rules = { [100] = { intent = "KILL", rank = 10 }, [200] = { intent = "KILL", rank = 90 } }

    local seenLast = MFD.Allocator.Compute({ low, high }, rules, seats, nil)
    local seenFirst = MFD.Allocator.Compute({ high, low }, rules, seats, nil)

    T.Eq(seenLast.byKey["100:BBB"], 8, "rank 10 takes skull however late it was seen")
    T.Eq(seenFirst.byKey["100:BBB"], 8, "and the same when seen first")
    T.Eq(seenLast.byKey["200:AAA"], 7, "rank 90 takes cross")
end)

T.Case("Allocator: an unowned intent falls through to the rule's fallback", function()
    local seats = seatsFor(KILL_AND_SHEEP, "Thok", "WARRIOR")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10, fallback = "KILL" } },
        seats, nil)
    T.Eq(out.byKey["100:AAA"], 8, "no mage in raid, so the sheep rule becomes a kill")
    T.Eq(out.list[1].intent, "KILL", "and the assignment reports the fallback intent")
end)

T.Case("Allocator: an unowned intent with no fallback leaves the mob unmarked", function()
    local seats = seatsFor(KILL_AND_SHEEP, "Thok", "WARRIOR")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10 } },
        seats, nil)
    T.Eq(out.byKey["100:AAA"], nil, "unmarked rather than guessed")
end)

T.Case("Allocator: mobs with no rule are never marked", function()
    local seats = seatsFor(KILL_AND_SHEEP)
    local out = MFD.Allocator.Compute({ { key = "999:AAA", npcID = 999 } }, {}, seats, nil)
    T.Eq(out.byKey["999:AAA"], nil, "no rule means no icon")
    T.Eq(#out.list, 0, "and nothing in the list")
end)

T.Case("Allocator: IGNORE is never marked even with seats free", function()
    local seats = seatsFor(KILL_AND_SHEEP)
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 } },
        { [100] = { intent = "IGNORE", rank = 10 } },
        seats, nil)
    T.Eq(out.byKey["100:AAA"], nil, "IGNORE means never")
end)

T.Case("Allocator: running out of icons leaves the lowest priority mobs unmarked", function()
    local seats = seatsFor({ [8] = { intent = "KILL", ordinal = 1 } })
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 }, { key = "200:BBB", npcID = 200 } },
        { [100] = { intent = "KILL", rank = 10 }, [200] = { intent = "KILL", rank = 20 } },
        seats, nil)
    T.Eq(out.byKey["100:AAA"], 8, "highest priority gets the only icon")
    T.Eq(out.byKey["200:BBB"], nil, "the rest go unmarked")
end)

T.Case("Allocator: maxCount caps how many of one npcID get marked", function()
    local seats = seatsFor(KILL_AND_SHEEP, "Alfred", "MAGE", "Grimmtusk", "MAGE", "Zed", "MAGE")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 }, { key = "100:BBB", npcID = 100 }, { key = "100:CCC", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10, maxCount = 2 } },
        seats, nil)
    T.Eq(out.byKey["100:AAA"], 5, "first allowed")
    T.Eq(out.byKey["100:BBB"], 4, "second allowed")
    T.Eq(out.byKey["100:CCC"], nil, "third capped")
end)

T.Case("Allocator: a locked assignment keeps its icon and consumes that seat", function()
    local seats = seatsFor(KILL_AND_SHEEP)
    local out = MFD.Allocator.Compute(
        { { key = "200:OLD", npcID = 200 }, { key = "100:NEW", npcID = 100 } },
        { [100] = { intent = "KILL", rank = 10 }, [200] = { intent = "KILL", rank = 90 } },
        seats, { ["200:OLD"] = 8 })
    T.Eq(out.byKey["200:OLD"], 8, "locked mob keeps skull despite its worse rank")
    T.Eq(out.byKey["100:NEW"], 7, "the better mob takes the next free seat instead")
end)

T.Case("Allocator: a lock counts toward maxCount", function()
    local seats = seatsFor(KILL_AND_SHEEP, "Alfred", "MAGE", "Grimmtusk", "MAGE")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 }, { key = "100:BBB", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10, maxCount = 1 } },
        seats, { ["100:AAA"] = 5 })
    T.Eq(out.byKey["100:AAA"], 5, "locked one holds the single allowed slot")
    T.Eq(out.byKey["100:BBB"], nil, "the other is capped out")
end)

T.Case("Allocator: assignments carry the seat owner", function()
    local seats = seatsFor(KILL_AND_SHEEP, "Grimmtusk", "MAGE")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10 } },
        seats, nil)
    T.Eq(out.list[1].owner, "Grimmtusk", "owner comes from the seat")
end)

T.Case("Allocator: kill assignments have no owner", function()
    local seats = seatsFor(KILL_AND_SHEEP)
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 } },
        { [100] = { intent = "KILL", rank = 10 } },
        seats, nil)
    T.Eq(out.list[1].owner, nil, "kill seats need no owner")
end)

_G.MarkedForDeath = MFD
