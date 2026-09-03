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
    T.Eq(p[2].intent, "KILL", "circle")
    T.Eq(p[2].ordinal, 4, "circle is kill 4")
    T.Eq(p[5].intent, "SHEEP", "moon")
    T.Eq(p[5].pin, "Grimmtusk", "moon is pinned")
    T.Eq(p[5].ordinal, 1, "moon is sheep 1")
    T.Eq(p[1].intent, "SHEEP", "star")
    T.Eq(p[1].ordinal, 2, "star is sheep 2")
    T.Eq(p[4].intent, "BANISH", "triangle")
    T.Eq(p[4].ordinal, 1, "triangle is banish 1")
    T.Eq(p[3].intent, "BANISH", "diamond")
    T.Eq(p[3].ordinal, 2, "diamond is banish 2")
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

T.Case("Candidates: Observe records a unit and clears any prior loss", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 500)
    MFD.Candidates.Lose(set, "100:AAA", 501)
    T.Eq(set["100:AAA"].unit, nil, "losing clears the unit token")
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate2", 502)
    T.Eq(set["100:AAA"].unit, "nameplate2", "reobserving restores it")
    T.Eq(set["100:AAA"].lostAt, nil, "and clears the loss stamp")
end)

T.Case("Candidates: a unit still on screen is never pruned", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 500)
    local removed = MFD.Candidates.Prune(set, 9999, 3)
    T.Eq(#removed, 0, "nothing removed")
    T.Eq(set["100:AAA"].npcID, 100, "entry survives")
end)

T.Case("Candidates: a lost unit survives inside the grace window", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 500)
    MFD.Candidates.Lose(set, "100:AAA", 500)
    local removed = MFD.Candidates.Prune(set, 502, 3)
    T.Eq(#removed, 0, "a flickering nameplate does not churn the pack")
end)

T.Case("Candidates: a lost unit is pruned past the grace window", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 500)
    MFD.Candidates.Lose(set, "100:AAA", 500)
    local removed = MFD.Candidates.Prune(set, 504, 3)
    T.Eq(#removed, 1, "one removed")
    T.Eq(removed[1], "100:AAA", "the right one")
    T.Eq(set["100:AAA"], nil, "and it is gone from the set")
end)

T.Case("Candidates: ToList is sorted by key so the allocator sees a stable order", function()
    local set = {}
    MFD.Candidates.Observe(set, "300:CCC", 300, "nameplate1", 500)
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate2", 500)
    MFD.Candidates.Observe(set, "200:BBB", 200, "nameplate3", 500)
    local list = MFD.Candidates.ToList(set)
    T.Eq(list[1].key, "100:AAA", "first")
    T.Eq(list[2].key, "200:BBB", "second")
    T.Eq(list[3].key, "300:CCC", "third")
    T.Eq(list[1].npcID, 100, "npcID carried through")
end)

local MARKER_LIMITS = { maxActions = 4, defenseLimit = 3, defenseWindow = 5 }

T.Case("Marker: an unmarked mob produces a fresh apply", function()
    local out = MFD.Marker.ComputeDiff({ ["100:AAA"] = 8 }, { ["100:AAA"] = 0 }, {}, {}, 100, MARKER_LIMITS)
    T.Eq(#out.actions, 1, "one action")
    T.Eq(out.actions[1].icon, 8, "the desired icon")
    T.Eq(out.actions[1].isDefense, false, "a first placement is not a defense")
end)

T.Case("Marker: an unplaced mob reading zero never burns the defense budget", function()
    -- A mob we have not marked reads 0 exactly like one whose icon was cleared.
    -- Only the placed set separates them, and getting this wrong would make the
    -- addon give up on packs it had never marked in the first place.
    local defense = {}
    for i = 1, 10 do
        local out = MFD.Marker.ComputeDiff({ ["100:AAA"] = 8 }, { ["100:AAA"] = 0 }, {}, defense, 100 + i, MARKER_LIMITS)
        T.Eq(#out.actions, 1, "tick " .. i .. " still tries")
    end
    T.Eq(defense["100:AAA"], nil, "and nothing was ever counted as a defense")
end)

T.Case("Marker: a mob already carrying the desired icon produces nothing", function()
    local out = MFD.Marker.ComputeDiff({ ["100:AAA"] = 8 }, { ["100:AAA"] = 8 }, {}, {}, 100, MARKER_LIMITS)
    T.Eq(#out.actions, 0, "no work to do")
end)

T.Case("Marker: an icon we placed that got cleared is re-applied as a defense", function()
    local defense = {}
    local placed = { ["100:AAA"] = true }
    local out = MFD.Marker.ComputeDiff({ ["100:AAA"] = 8 }, { ["100:AAA"] = 0 }, placed, defense, 100, MARKER_LIMITS)
    T.Eq(out.actions[1].isDefense, true, "counted as a defense")
    T.Eq(defense["100:AAA"].count, 1, "defense counter incremented")
end)

T.Case("Marker: defending stops after the limit inside the window", function()
    local defense = {}
    local placed = { ["100:AAA"] = true }
    local desired, actual = { ["100:AAA"] = 8 }, { ["100:AAA"] = 0 }

    for i = 1, 3 do
        local out = MFD.Marker.ComputeDiff(desired, actual, placed, defense, 100 + i, MARKER_LIMITS)
        T.Eq(#out.actions, 1, "defense " .. i .. " still acts")
    end

    local out = MFD.Marker.ComputeDiff(desired, actual, placed, defense, 104, MARKER_LIMITS)
    T.Eq(#out.actions, 0, "fourth attempt inside the window yields")
    T.Eq(out.yielded[1], "100:AAA", "and reports which key it gave up on")

    -- The brake must hold for the rest of the window. Resetting state on yield
    -- turned it into a loop: fresh apply, cleared, three defenses, yield, again.
    for i = 5, 8 do
        local later = MFD.Marker.ComputeDiff(desired, actual, placed, defense, 100 + i, MARKER_LIMITS)
        T.Eq(#later.actions, 0, "tick " .. i .. " still holds")
        T.Eq(later.yielded[1], "100:AAA", "tick " .. i .. " still yielded")
    end
end)

T.Case("Marker: the defense window resets so a later clear is fought again", function()
    local defense = {}
    local placed = { ["100:AAA"] = true }
    local desired, actual = { ["100:AAA"] = 8 }, { ["100:AAA"] = 0 }

    for i = 1, 3 do
        MFD.Marker.ComputeDiff(desired, actual, placed, defense, 100 + i, MARKER_LIMITS)
    end

    local out = MFD.Marker.ComputeDiff(desired, actual, placed, defense, 200, MARKER_LIMITS)
    T.Eq(#out.actions, 1, "a fresh window means we defend again")
    T.Eq(defense["100:AAA"].count, 1, "counter restarted")
end)

T.Case("Marker: actions are capped so a big pull does not burst", function()
    local desired, actual = {}, {}
    for i = 1, 10 do
        desired["10" .. i .. ":AAA"] = 1
        actual["10" .. i .. ":AAA"] = 0
    end
    local out = MFD.Marker.ComputeDiff(desired, actual, {}, {}, 100, MARKER_LIMITS)
    T.Eq(#out.actions, 4, "capped at maxActions")
end)

T.Case("Marker: actions come out in a deterministic order", function()
    local desired = { ["300:CCC"] = 1, ["100:AAA"] = 2, ["200:BBB"] = 3 }
    local actual = { ["300:CCC"] = 0, ["100:AAA"] = 0, ["200:BBB"] = 0 }
    local out = MFD.Marker.ComputeDiff(desired, actual, {}, {}, 100, MARKER_LIMITS)
    T.Eq(out.actions[1].key, "100:AAA", "sorted by key")
    T.Eq(out.actions[2].key, "200:BBB", "second")
    T.Eq(out.actions[3].key, "300:CCC", "third")
end)

T.Case("Marker: someone else's icon is corrected and counts as a defense", function()
    local defense = {}
    local out = MFD.Marker.ComputeDiff({ ["100:AAA"] = 8 }, { ["100:AAA"] = 5 }, {}, defense, 100, MARKER_LIMITS)
    T.Eq(out.actions[1].icon, 8, "corrected to the desired icon")
    T.Eq(out.actions[1].isDefense, true, "a foreign icon counts as a defense so the brake applies")
end)

T.Case("Seats: EnsurePlan seeds the default plan into an empty database", function()
    local db = { seatPlan = {} }
    MFD.Seats.EnsurePlan(db)
    T.Eq(db.seatPlan[8].intent, "KILL", "skull seeded")
    T.Eq(db.seatPlan[5].pin, "Grimmtusk", "pin seeded")
end)

T.Case("Seats: EnsurePlan never overwrites a plan the user has edited", function()
    local db = { seatPlan = { [8] = { intent = "SHEEP", ordinal = 1 } } }
    MFD.Seats.EnsurePlan(db)
    T.Eq(db.seatPlan[8].intent, "SHEEP", "user's binding survives")
    T.Eq(db.seatPlan[5], nil, "and nothing else is injected")
end)

T.Case("Seats: EnsurePlan deep copies, so editing the db cannot corrupt the default", function()
    local db = { seatPlan = {} }
    MFD.Seats.EnsurePlan(db)
    db.seatPlan[8].intent = "IGNORE"
    T.Eq(MFD.Seats.DEFAULT_PLAN[8].intent, "KILL", "the shared default is untouched")
end)

-- End to end over the pure modules, in the shape the live tick uses them. This
-- is the case that would have caught the empty-seat-plan bug: every unit test
-- passed while the addon marked nothing, because nothing asserted that the
-- default configuration actually produces an icon.
T.Case("Pipeline: default seat plan plus one kill rule puts skull on the mob", function()
    local db = { seatPlan = {} }
    MFD.Seats.EnsurePlan(db)

    local seats = MFD.Seats.Resolve(db.seatPlan, roster("Thok", "WARRIOR"))
    local candidates = MFD.Candidates.ToList({
        ["100:AAA"] = { key = "100:AAA", npcID = 100, unit = "nameplate1" },
    })
    local out = MFD.Allocator.Compute(candidates, { [100] = { npcID = 100, intent = "KILL", rank = 10 } }, seats, nil)

    T.Eq(out.byKey["100:AAA"], 8, "skull, from a default install with one rule")

    local diff = MFD.Marker.ComputeDiff(out.byKey, { ["100:AAA"] = 0 }, {}, {}, 100, MFD.Marker.LIMITS)
    T.Eq(#diff.actions, 1, "and the marker would actually place it")
    T.Eq(diff.actions[1].icon, 8, "with skull")
end)

T.Case("Diagnose: an empty seat plan is reported, not silently ignored", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = true, canMark = true,
        cvarsOk = true, seatCount = 0, candidateCount = 3, ruleCount = 1, desiredCount = 0,
    })
    T.Eq(reasons[1], "no seats are configured, so no icon can be assigned. /mfd config", "names the real cause")
end)

T.Case("Diagnose: marking switched off is reported first", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = false, isAuthority = true, canMark = true,
        cvarsOk = true, seatCount = 8, candidateCount = 3, ruleCount = 1, desiredCount = 1,
    })
    T.Eq(reasons[1], "marking is switched off", "the most basic cause leads")
end)

T.Case("Diagnose: no visible mobs points at nameplates", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = true, canMark = true,
        cvarsOk = true, seatCount = 8, candidateCount = 0, ruleCount = 1, desiredCount = 0,
    })
    T.Eq(reasons[1], "no hostile mobs are visible. Are enemy nameplates on?", "actionable")
end)

T.Case("Diagnose: no rules names the instance", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = true, canMark = true, cvarsOk = true,
        seatCount = 8, candidateCount = 3, ruleCount = 0, desiredCount = 0, instanceKey = "BLACKTEMPLE",
    })
    T.Eq(reasons[1], "no rules are active for BLACKTEMPLE", "says where")
end)

T.Case("Diagnose: rules and mobs but no match is distinguished from having no rules", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = true, canMark = true, cvarsOk = true,
        seatCount = 8, candidateCount = 3, ruleCount = 5, desiredCount = 0,
    })
    T.Eq(reasons[1], "3 mobs visible but none of them match a rule", "the useful distinction")
end)

T.Case("Diagnose: a healthy state reports what it is doing", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = true, canMark = true, cvarsOk = true,
        seatCount = 8, candidateCount = 3, ruleCount = 5, desiredCount = 2,
    })
    T.Eq(reasons[1], "marking 2 of 3 visible mobs", "no problem to report")
end)

T.Case("Diagnose: a backup says who the marker is rather than looking broken", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = false, authority = "Grimmtusk", canMark = true,
        cvarsOk = true, seatCount = 8, candidateCount = 3, ruleCount = 5, desiredCount = 2,
    })
    T.Eq(reasons[1], "Grimmtusk is the marker, you are a backup", "expected, not a fault")
end)

-- Fake UnitGUID: maps a unit token to whatever creature it points at right now.
local function guidLookup(map)
    return function(unit) return map[unit] end
end

local GUID_A = "Creature-0-3299-530-1-100-00000000AA"
local GUID_B = "Creature-0-3299-530-1-200-00000000BB"

T.Case("Candidates: a nameplate token still pointing at its mob is actionable", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:00000000AA", 100, "nameplate1", 500)
    local units = MFD.Candidates.ActionableUnits(set, guidLookup({ nameplate1 = GUID_A }))
    T.Eq(units["100:00000000AA"], "nameplate1", "usable")
end)

-- The bug that shipped. "mouseover" is an alias, not an identity: once the
-- cursor moves it refers to a different creature, so acting on a stored copy
-- stamps an icon onto whatever the player happens to be pointing at.
T.Case("Candidates: a stale mouseover token is never actionable", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:00000000AA", 100, "mouseover", 500)
    local units = MFD.Candidates.ActionableUnits(set, guidLookup({ mouseover = GUID_B }))
    T.Eq(units["100:00000000AA"], nil, "refuses to act through a token that moved")
end)

T.Case("Candidates: a mouseover token still on the same mob is actionable", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:00000000AA", 100, "mouseover", 500)
    local units = MFD.Candidates.ActionableUnits(set, guidLookup({ mouseover = GUID_A }))
    T.Eq(units["100:00000000AA"], "mouseover", "valid right now, so usable")
end)

T.Case("Candidates: a token resolving to nothing is not actionable", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:00000000AA", 100, "target", 500)
    local units = MFD.Candidates.ActionableUnits(set, guidLookup({}))
    T.Eq(units["100:00000000AA"], nil, "no unit, no action")
end)

T.Case("Candidates: an entry known only from a peer sighting has no unit", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:00000000AA", 100, nil, 500)
    local units = MFD.Candidates.ActionableUnits(set, guidLookup({ nameplate1 = GUID_A }))
    T.Eq(units["100:00000000AA"], nil, "nothing to act through")
end)

T.Case("Candidates: a recycled nameplate token is not actionable for the old mob", function()
    -- Nameplate tokens are reused as mobs die and spawn, so they are durable
    -- but not permanent. The same check covers it.
    local set = {}
    MFD.Candidates.Observe(set, "100:00000000AA", 100, "nameplate1", 500)
    MFD.Candidates.Observe(set, "200:00000000BB", 200, "nameplate2", 500)
    local units = MFD.Candidates.ActionableUnits(set, guidLookup({ nameplate1 = GUID_B, nameplate2 = GUID_B }))
    T.Eq(units["100:00000000AA"], nil, "the recycled token no longer means the old mob")
    T.Eq(units["200:00000000BB"], "nameplate2", "and the live one still works")
end)

T.Case("Rules: known TBC raid map ids resolve to stable instance keys", function()
    T.Eq(MFD.Rules.InstanceKeyFor(532), "KARAZHAN", "Karazhan")
    T.Eq(MFD.Rules.InstanceKeyFor(564), "BLACKTEMPLE", "Black Temple")
    T.Eq(MFD.Rules.InstanceKeyFor(534), "HYJAL", "Hyjal Summit")
end)

-- Named keys only exist so raid rule sets share cleanly between players. Every
-- other zone still gets a key, so the addon is usable in heroics and outdoors
-- rather than inert everywhere but nine raids.
T.Case("Rules: any other zone still gets a key derived from its map id", function()
    T.Eq(MFD.Rules.InstanceKeyFor(1), "MAP1", "open world zone")
    T.Eq(MFD.Rules.InstanceKeyFor(nil), nil, "nil is safe")
    T.Eq(MFD.Rules.InstanceKeyFor("nonsense"), nil, "so is rubbish")
end)

T.Case("Rules: Active returns only the current instance's rules", function()
    MFD.Rules.SetContributions({
        { owner = "Dillon", rules = {
            BLACKTEMPLE = { { npcID = 22890, intent = "SHEEP", rank = 10 } },
            HYJAL = { { npcID = 17842, intent = "TRAP", rank = 10 } },
        } },
    }, "Dillon")

    MFD.Rules.currentInstanceKey = "BLACKTEMPLE"
    local active = MFD.Rules.Active()
    T.Eq(active[22890].intent, "SHEEP", "BT rule is active")
    T.Eq(active[17842], nil, "Hyjal rule is not")
end)

T.Case("Rules: Active is empty when the zone is unknown", function()
    MFD.Rules.SetContributions({
        { owner = "Dillon", rules = { BLACKTEMPLE = { { npcID = 22890, intent = "SHEEP", rank = 10 } } } },
    }, "Dillon")

    MFD.Rules.currentInstanceKey = nil
    T.Eq(next(MFD.Rules.Active()), nil, "nothing is marked where we have no rules")
end)

T.Case("Learned: recording a mob stores its name and zone", function()
    local db = { learnedMobs = {} }
    MFD.Learned.Record(db, 22890, "Illidari Nightlord", "Black Temple", 1000)
    T.Eq(db.learnedMobs[22890].name, "Illidari Nightlord", "name")
    T.Eq(db.learnedMobs[22890].zone, "Black Temple", "zone")
    T.Eq(db.learnedMobs[22890].seenAt, 1000, "timestamp")
end)

T.Case("Learned: re-recording refreshes the timestamp without duplicating", function()
    local db = { learnedMobs = {} }
    MFD.Learned.Record(db, 22890, "Illidari Nightlord", "Black Temple", 1000)
    MFD.Learned.Record(db, 22890, "Illidari Nightlord", "Black Temple", 2000)
    T.Eq(db.learnedMobs[22890].seenAt, 2000, "refreshed")
    local count = 0
    for _ in pairs(db.learnedMobs) do count = count + 1 end
    T.Eq(count, 1, "still one entry")
end)

T.Case("Learned: a nameless or idless observation is ignored", function()
    local db = { learnedMobs = {} }
    MFD.Learned.Record(db, nil, "Something", "Somewhere", 1000)
    MFD.Learned.Record(db, 22890, nil, "Somewhere", 1000)
    MFD.Learned.Record(db, 22890, "", "Somewhere", 1000)
    T.Eq(next(db.learnedMobs), nil, "nothing stored half-formed")
end)

T.Case("CreatureType: banish only lands on demons and elementals", function()
    T.Eq(MFD.Seats.CanIntentApply("BANISH", "Demon"), true, "demon")
    T.Eq(MFD.Seats.CanIntentApply("BANISH", "Elemental"), true, "elemental")
    T.Eq(MFD.Seats.CanIntentApply("BANISH", "Humanoid"), false, "humanoid cannot be banished")
end)

T.Case("CreatureType: the rejection explains itself", function()
    local _, reason = MFD.Seats.CanIntentApply("BANISH", "Humanoid")
    T.Eq(reason, "Banish does not work on Humanoid targets", "usable in a warning")
end)

T.Case("CreatureType: shackle is undead only, sap is humanoid only on TBC", function()
    T.Eq(MFD.Seats.CanIntentApply("SHACKLE", "Undead"), true, "shackle undead")
    T.Eq(MFD.Seats.CanIntentApply("SHACKLE", "Humanoid"), false, "not humanoids")
    T.Eq(MFD.Seats.CanIntentApply("SAP", "Humanoid"), true, "sap humanoid")
    T.Eq(MFD.Seats.CanIntentApply("SAP", "Beast"), false, "beasts only became sappable after TBC")
end)

T.Case("CreatureType: sheep covers humanoids, beasts and critters", function()
    T.Eq(MFD.Seats.CanIntentApply("SHEEP", "Humanoid"), true, "humanoid")
    T.Eq(MFD.Seats.CanIntentApply("SHEEP", "Beast"), true, "beast")
    T.Eq(MFD.Seats.CanIntentApply("SHEEP", "Undead"), false, "not undead")
end)

T.Case("CreatureType: unrestricted intents accept anything", function()
    T.Eq(MFD.Seats.CanIntentApply("KILL", "Humanoid"), true, "kill")
    T.Eq(MFD.Seats.CanIntentApply("TRAP", "Demon"), true, "trap is not type restricted")
    T.Eq(MFD.Seats.CanIntentApply("IGNORE", "Undead"), true, "ignore")
end)

-- Fail open, deliberately. UnitCreatureType returns a localised string, so on a
-- non-English client nothing would match and a strict check would warn about
-- every single rule. A check that cries wolf gets ignored.
T.Case("CreatureType: an unknown or missing type never warns", function()
    T.Eq(MFD.Seats.CanIntentApply("BANISH", nil), true, "not seen yet")
    T.Eq(MFD.Seats.CanIntentApply("BANISH", "Humanoide"), true, "localised string we do not recognise")
    T.Eq(MFD.Seats.CanIntentApply("BANISH", ""), true, "empty")
end)

T.Case("CreatureType: an unknown intent never warns", function()
    T.Eq(MFD.Seats.CanIntentApply("NONSENSE", "Humanoid"), true, "no opinion")
end)

T.Case("Learned: the creature type is recorded alongside the name", function()
    local db = { learnedMobs = {} }
    MFD.Learned.Record(db, 22880, "Shadowmoon Champion", "Black Temple", 1000, "Humanoid")
    T.Eq(db.learnedMobs[22880].creatureType, "Humanoid", "stored for later rule checks")
end)

T.Case("Learned: a missing creature type is still recorded, just without the type", function()
    local db = { learnedMobs = {} }
    MFD.Learned.Record(db, 22880, "Shadowmoon Champion", "Black Temple", 1000, nil)
    T.Eq(db.learnedMobs[22880].name, "Shadowmoon Champion", "the mob is still learned")
    T.Eq(db.learnedMobs[22880].creatureType, nil, "type simply absent")
end)

local function peer(name, opts)
    opts = opts or {}
    return {
        name = name,
        canMark = opts.canMark ~= false,
        isLeader = opts.isLeader or false,
        isAssist = opts.isAssist or false,
        lastSeen = opts.lastSeen or 100,
        version = opts.version or "0.1.0",
    }
end

T.Case("Comms: encode and decode round-trip", function()
    local encoded = MFD.Comms.Encode("A", { "22890:AAA", 5, "SHEEP", "Grimmtusk" })
    local msgType, fields = MFD.Comms.Decode(encoded)
    T.Eq(msgType, "A", "type")
    T.Eq(fields[1], "22890:AAA", "key")
    T.Eq(fields[2], "5", "icon arrives as a string")
    T.Eq(fields[4], "Grimmtusk", "owner")
end)

T.Case("Comms: decoding rubbish is safe", function()
    T.Eq(MFD.Comms.Decode(""), nil, "empty string")
    T.Eq(MFD.Comms.Decode(nil), nil, "nil")
    T.Eq(MFD.Comms.Decode(12345), nil, "not a string")
end)

T.Case("Comms: the queue drains high priority first", function()
    local queue = {
        { msgType = "RD", body = "rules" },
        { msgType = "B", body = "beat" },
        { msgType = "S", body = "sighting" },
    }
    local sent = MFD.Comms.Drain(queue, 3)
    T.Eq(sent[1].msgType, "B", "heartbeat first")
    T.Eq(sent[2].msgType, "S", "sightings next")
    T.Eq(sent[3].msgType, "RD", "bulk rule data last")
end)

T.Case("Comms: the queue respects the per-tick budget", function()
    local queue = {}
    for i = 1, 20 do
        queue[i] = { msgType = "S", body = "s" .. i }
    end
    local sent = MFD.Comms.Drain(queue, 8)
    T.Eq(#sent, 8, "only the budget goes out")
    T.Eq(#queue, 12, "the rest stays queued")
end)

T.Case("Comms: equal priority keeps insertion order", function()
    local queue = {
        { msgType = "S", body = "first" },
        { msgType = "S", body = "second" },
    }
    local sent = MFD.Comms.Drain(queue, 2)
    T.Eq(sent[1].body, "first", "observed order preserved")
    T.Eq(sent[2].body, "second", "second")
end)

T.Case("Comms: a valid designation beats the election", function()
    local name, mode = MFD.Comms.ResolveAuthority(
        { peer("Dillon", { isAssist = true }), peer("Grimmtusk", { isLeader = true }) },
        { name = "Dillon", setAt = 50 }, 100)
    T.Eq(name, "Dillon", "the designated lead wins over the raid leader")
    T.Eq(mode, "designated", "and says so")
end)

T.Case("Comms: an absent designated lead falls back to the election", function()
    local name, mode, reason = MFD.Comms.ResolveAuthority(
        { peer("Grimmtusk", { isLeader = true }) },
        { name = "Dillon", setAt = 50 }, 100)
    T.Eq(name, "Grimmtusk", "elected instead")
    T.Eq(mode, "elected", "mode reports the fallback")
    T.Eq(reason, "designated lead Dillon is not in the group", "and says why")
end)

T.Case("Comms: a designated lead without assist falls back", function()
    local name, _, reason = MFD.Comms.ResolveAuthority(
        { peer("Dillon", { canMark = false }), peer("Grimmtusk", { isLeader = true }) },
        { name = "Dillon", setAt = 50 }, 100)
    T.Eq(name, "Grimmtusk", "elected instead")
    T.Eq(reason, "designated lead Dillon cannot place icons", "names the real problem")
end)

T.Case("Comms: the election prefers leader, then assist, then name", function()
    T.Eq(MFD.Comms.ResolveAuthority(
        { peer("Zed", { isAssist = true }), peer("Alfred"), peer("Mira", { isLeader = true }) },
        { name = "", setAt = 0 }, 100), "Mira", "raid leader outranks assist")

    T.Eq(MFD.Comms.ResolveAuthority(
        { peer("Zed", { isAssist = true }), peer("Alfred") },
        { name = "", setAt = 0 }, 100), "Zed", "assist outranks nobody")

    T.Eq(MFD.Comms.ResolveAuthority(
        { peer("Zed"), peer("Alfred") },
        { name = "", setAt = 0 }, 100), "Alfred", "tie broken by name ascending")
end)

T.Case("Comms: peers that have gone silent are ignored", function()
    local name = MFD.Comms.ResolveAuthority(
        { peer("Mira", { isLeader = true, lastSeen = 10 }), peer("Alfred", { lastSeen = 99 }) },
        { name = "", setAt = 0 }, 100)
    T.Eq(name, "Alfred", "a disconnected raid leader cannot hold the authority hostage")
end)

T.Case("Comms: nobody eligible means no authority, with a reason", function()
    local name, mode, reason = MFD.Comms.ResolveAuthority({}, { name = "", setAt = 0 }, 100)
    T.Eq(name, nil, "no authority")
    T.Eq(mode, "none", "and it says so")
    T.Eq(reason, "nobody in the group can place icons", "rather than failing silently")
end)

T.Case("Comms: resolution does not depend on peer ordering", function()
    local a, b = peer("Zed", { isAssist = true }), peer("Alfred", { isAssist = true })
    T.Eq(MFD.Comms.ResolveAuthority({ a, b }, { name = "", setAt = 0 }, 100),
         MFD.Comms.ResolveAuthority({ b, a }, { name = "", setAt = 0 }, 100),
         "same answer either way, so every client agrees")
end)

-- The bug that spammed "giving up". actual only holds mobs with a currently
-- valid unit, so a marked mob whose nameplate dropped inside the grace window
-- read as icon 0 with placed = true and burned the whole brake budget five
-- times a second, despite there being nothing to act through.
T.Case("Marker: a placed mob we cannot currently address is skipped, not defended", function()
    local defense = {}
    local placed = { ["100:AAA"] = true }
    for i = 1, 10 do
        local out = MFD.Marker.ComputeDiff({ ["100:AAA"] = 8 }, {}, placed, defense, 100 + i, MARKER_LIMITS)
        T.Eq(#out.actions, 0, "tick " .. i .. ": nothing to act through")
        T.Eq(#out.yielded, 0, "tick " .. i .. ": and nothing to give up on")
    end
    T.Eq(defense["100:AAA"], nil, "the brake was never touched")
end)

T.Case("Candidates: a transient token never overwrites a nameplate token", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate3", 500)
    MFD.Candidates.Observe(set, "100:AAA", 100, "target", 501)
    T.Eq(set["100:AAA"].unit, "nameplate3", "nameplate kept, it is the durable handle")
    T.Eq(set["100:AAA"].seenAt, 501, "but the sighting is still refreshed")
end)

T.Case("Candidates: a transient token fills in when there is no unit", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate3", 500)
    MFD.Candidates.Lose(set, "100:AAA", 501)
    MFD.Candidates.Observe(set, "100:AAA", 100, "target", 502)
    T.Eq(set["100:AAA"].unit, "target", "better than nothing")
end)

T.Case("Candidates: a nameplate token replaces a transient one", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "mouseover", 500)
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 501)
    T.Eq(set["100:AAA"].unit, "nameplate1", "upgraded to the durable handle")
end)

_G.MarkedForDeath = MFD
