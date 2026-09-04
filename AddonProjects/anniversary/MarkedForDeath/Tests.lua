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
-- role lists the pure modules return; deliberately not a deep compare.
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

T.Case("Roles: a pinned player owns their role when present", function()
    local plan = {
        [5] = { intent = "SHEEP", ordinal = 1, pin = "Grimmtusk" },
        [4] = { intent = "SHEEP", ordinal = 2 },
    }
    local r = MFD.Roles.Resolve(plan, roster("Alfred", "MAGE", "Grimmtusk", "MAGE"))
    T.Eq(r.byIcon[5].owner, "Grimmtusk", "moon owner")
    T.Eq(r.byIcon[4].owner, "Alfred", "triangle owner")
end)

T.Case("Roles: an absent pin falls through to the next eligible mage", function()
    local plan = {
        [5] = { intent = "SHEEP", ordinal = 1, pin = "Grimmtusk" },
        [4] = { intent = "SHEEP", ordinal = 2 },
    }
    local r = MFD.Roles.Resolve(plan, roster("Alfred", "MAGE", "Zed", "MAGE"))
    T.Eq(r.byIcon[5].owner, "Alfred", "moon falls to first mage by name")
    T.Eq(r.byIcon[4].owner, "Zed", "triangle takes the second")
end)

T.Case("Roles: an intent with no capable class is unowned", function()
    local plan = { [5] = { intent = "SHEEP", ordinal = 1 } }
    local r = MFD.Roles.Resolve(plan, roster("Thok", "WARRIOR"))
    T.Eq(r.byIcon[5].owner, false, "no mage means no sheep owner")
end)

T.Case("Roles: KILL needs no owner", function()
    local plan = { [8] = { intent = "KILL", ordinal = 1 } }
    local r = MFD.Roles.Resolve(plan, roster())
    T.Eq(r.byIcon[8].owner, true, "kill role is always available")
end)

T.Case("Roles: one player holds at most one role per intent but may span intents", function()
    local plan = {
        [3] = { intent = "BANISH", ordinal = 1 },
        [2] = { intent = "BANISH", ordinal = 2 },
        [7] = { intent = "FEAR", ordinal = 1 },
    }
    local r = MFD.Roles.Resolve(plan, roster("Nyx", "WARLOCK"))
    T.Eq(r.byIcon[3].owner, "Nyx", "banish role 1")
    T.Eq(r.byIcon[2].owner, false, "only one warlock, so banish role 2 is unowned")
    T.Eq(r.byIcon[7].owner, "Nyx", "same warlock also holds fear role 1")
end)

T.Case("Roles: byIntent is ordered by ordinal", function()
    local plan = {
        [1] = { intent = "KILL", ordinal = 4 },
        [8] = { intent = "KILL", ordinal = 1 },
        [6] = { intent = "KILL", ordinal = 3 },
        [7] = { intent = "KILL", ordinal = 2 },
    }
    local r = MFD.Roles.Resolve(plan, roster())
    T.Eq(r.byIntent.KILL[1].icon, 8, "first is skull")
    T.Eq(r.byIntent.KILL[2].icon, 7, "second is cross")
    T.Eq(r.byIntent.KILL[3].icon, 6, "third is square")
    T.Eq(r.byIntent.KILL[4].icon, 1, "fourth is star")
end)

T.Case("Roles: the default plan matches the agreed icon bindings", function()
    local p = MFD.Roles.DEFAULT_PLAN
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

-- Builds the resolved-role table the allocator consumes, from a plan and a
-- roster, so allocator cases read as intent rather than as plumbing.
local function rolesFor(plan, ...)
    return MFD.Roles.Resolve(plan, roster(...))
end

local KILL_AND_SHEEP = {
    [8] = { intent = "KILL",  ordinal = 1 },
    [7] = { intent = "KILL",  ordinal = 2 },
    [5] = { intent = "SHEEP", ordinal = 1 },
    [4] = { intent = "SHEEP", ordinal = 2 },
    [6] = { intent = "SHEEP", ordinal = 3 },
}

T.Case("Allocator: duplicates of one mob take successive roles of their intent", function()
    local roles = rolesFor(KILL_AND_SHEEP, "Alfred", "MAGE", "Grimmtusk", "MAGE", "Zed", "MAGE")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 }, { key = "100:BBB", npcID = 100 }, { key = "100:CCC", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10 } },
        roles, nil)
    T.Eq(out.byKey["100:AAA"], 5, "first sheep role")
    T.Eq(out.byKey["100:BBB"], 4, "second sheep role")
    T.Eq(out.byKey["100:CCC"], 6, "third sheep role")
end)

T.Case("Allocator: rank decides which mob gets skull, not sighting order", function()
    local roles = rolesFor(KILL_AND_SHEEP)
    local low = { key = "200:AAA", npcID = 200 }
    local high = { key = "100:BBB", npcID = 100 }
    local rules = { [100] = { intent = "KILL", rank = 10 }, [200] = { intent = "KILL", rank = 90 } }

    local seenLast = MFD.Allocator.Compute({ low, high }, rules, roles, nil)
    local seenFirst = MFD.Allocator.Compute({ high, low }, rules, roles, nil)

    T.Eq(seenLast.byKey["100:BBB"], 8, "rank 10 takes skull however late it was seen")
    T.Eq(seenFirst.byKey["100:BBB"], 8, "and the same when seen first")
    T.Eq(seenLast.byKey["200:AAA"], 7, "rank 90 takes cross")
end)

T.Case("Allocator: an unowned intent falls through to the rule's fallback", function()
    local roles = rolesFor(KILL_AND_SHEEP, "Thok", "WARRIOR")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10, fallback = "KILL" } },
        roles, nil)
    T.Eq(out.byKey["100:AAA"], 8, "no mage in raid, so the sheep rule becomes a kill")
    T.Eq(out.list[1].intent, "KILL", "and the assignment reports the fallback intent")
end)

T.Case("Allocator: an unowned intent with no fallback leaves the mob unmarked", function()
    local roles = rolesFor(KILL_AND_SHEEP, "Thok", "WARRIOR")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10 } },
        roles, nil)
    T.Eq(out.byKey["100:AAA"], nil, "unmarked rather than guessed")
end)

T.Case("Allocator: mobs with no rule are never marked", function()
    local roles = rolesFor(KILL_AND_SHEEP)
    local out = MFD.Allocator.Compute({ { key = "999:AAA", npcID = 999 } }, {}, roles, nil)
    T.Eq(out.byKey["999:AAA"], nil, "no rule means no icon")
    T.Eq(#out.list, 0, "and nothing in the list")
end)

T.Case("Allocator: IGNORE is never marked even with roles free", function()
    local roles = rolesFor(KILL_AND_SHEEP)
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 } },
        { [100] = { intent = "IGNORE", rank = 10 } },
        roles, nil)
    T.Eq(out.byKey["100:AAA"], nil, "IGNORE means never")
end)

T.Case("Allocator: running out of icons leaves the lowest priority mobs unmarked", function()
    local roles = rolesFor({ [8] = { intent = "KILL", ordinal = 1 } })
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 }, { key = "200:BBB", npcID = 200 } },
        { [100] = { intent = "KILL", rank = 10 }, [200] = { intent = "KILL", rank = 20 } },
        roles, nil)
    T.Eq(out.byKey["100:AAA"], 8, "highest priority gets the only icon")
    T.Eq(out.byKey["200:BBB"], nil, "the rest go unmarked")
end)

T.Case("Allocator: maxCount caps how many of one npcID get marked", function()
    local roles = rolesFor(KILL_AND_SHEEP, "Alfred", "MAGE", "Grimmtusk", "MAGE", "Zed", "MAGE")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 }, { key = "100:BBB", npcID = 100 }, { key = "100:CCC", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10, maxCount = 2 } },
        roles, nil)
    T.Eq(out.byKey["100:AAA"], 5, "first allowed")
    T.Eq(out.byKey["100:BBB"], 4, "second allowed")
    T.Eq(out.byKey["100:CCC"], nil, "third capped")
end)

T.Case("Allocator: a locked assignment keeps its icon and consumes that role", function()
    local roles = rolesFor(KILL_AND_SHEEP)
    local out = MFD.Allocator.Compute(
        { { key = "200:OLD", npcID = 200 }, { key = "100:NEW", npcID = 100 } },
        { [100] = { intent = "KILL", rank = 10 }, [200] = { intent = "KILL", rank = 90 } },
        roles, { ["200:OLD"] = 8 })
    T.Eq(out.byKey["200:OLD"], 8, "locked mob keeps skull despite its worse rank")
    T.Eq(out.byKey["100:NEW"], 7, "the better mob takes the next free role instead")
end)

T.Case("Allocator: a lock counts toward maxCount", function()
    local roles = rolesFor(KILL_AND_SHEEP, "Alfred", "MAGE", "Grimmtusk", "MAGE")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 }, { key = "100:BBB", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10, maxCount = 1 } },
        roles, { ["100:AAA"] = 5 })
    T.Eq(out.byKey["100:AAA"], 5, "locked one holds the single allowed slot")
    T.Eq(out.byKey["100:BBB"], nil, "the other is capped out")
end)

T.Case("Allocator: assignments carry the role owner", function()
    local roles = rolesFor(KILL_AND_SHEEP, "Grimmtusk", "MAGE")
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 } },
        { [100] = { intent = "SHEEP", rank = 10 } },
        roles, nil)
    T.Eq(out.list[1].owner, "Grimmtusk", "owner comes from the role")
end)

T.Case("Allocator: kill assignments have no owner", function()
    local roles = rolesFor(KILL_AND_SHEEP)
    local out = MFD.Allocator.Compute(
        { { key = "100:AAA", npcID = 100 } },
        { [100] = { intent = "KILL", rank = 10 } },
        roles, nil)
    T.Eq(out.list[1].owner, nil, "kill roles need no owner")
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

T.Case("Roles: EnsurePlan seeds the default plan into an empty database", function()
    local db = { rolePlan = {} }
    MFD.Roles.EnsurePlan(db)
    T.Eq(db.rolePlan[8].intent, "KILL", "skull seeded")
    T.Eq(db.rolePlan[5].pin, "Grimmtusk", "pin seeded")
end)

T.Case("Roles: EnsurePlan never overwrites a plan the user has edited", function()
    local db = { rolePlan = { [8] = { intent = "SHEEP", ordinal = 1 } } }
    MFD.Roles.EnsurePlan(db)
    T.Eq(db.rolePlan[8].intent, "SHEEP", "user's binding survives")
    T.Eq(db.rolePlan[5], nil, "and nothing else is injected")
end)

T.Case("Roles: EnsurePlan deep copies, so editing the db cannot corrupt the default", function()
    local db = { rolePlan = {} }
    MFD.Roles.EnsurePlan(db)
    db.rolePlan[8].intent = "IGNORE"
    T.Eq(MFD.Roles.DEFAULT_PLAN[8].intent, "KILL", "the shared default is untouched")
end)

-- End to end over the pure modules, in the shape the live tick uses them. This
-- is the case that would have caught the empty-role-plan bug: every unit test
-- passed while the addon marked nothing, because nothing asserted that the
-- default configuration actually produces an icon.
T.Case("Pipeline: default role plan plus one kill rule puts skull on the mob", function()
    local db = { rolePlan = {} }
    MFD.Roles.EnsurePlan(db)

    local roles = MFD.Roles.Resolve(db.rolePlan, roster("Thok", "WARRIOR"))
    local candidates = MFD.Candidates.ToList({
        ["100:AAA"] = { key = "100:AAA", npcID = 100, unit = "nameplate1" },
    })
    local out = MFD.Allocator.Compute(candidates, { [100] = { npcID = 100, intent = "KILL", rank = 10 } }, roles, nil)

    T.Eq(out.byKey["100:AAA"], 8, "skull, from a default install with one rule")

    local diff = MFD.Marker.ComputeDiff(out.byKey, { ["100:AAA"] = 0 }, {}, {}, 100, MFD.Marker.LIMITS)
    T.Eq(#diff.actions, 1, "and the marker would actually place it")
    T.Eq(diff.actions[1].icon, 8, "with skull")
end)

T.Case("Diagnose: an empty role plan is reported, not silently ignored", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = true, canMark = true,
        cvarsOk = true, roleCount = 0, candidateCount = 3, ruleCount = 1, desiredCount = 0,
    })
    T.Eq(reasons[1], "no roles are configured, so no icon can be assigned. /mfd config", "names the real cause")
end)

T.Case("Diagnose: marking switched off is reported first", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = false, isAuthority = true, canMark = true,
        cvarsOk = true, roleCount = 8, candidateCount = 3, ruleCount = 1, desiredCount = 1,
    })
    T.Eq(reasons[1], "marking is switched off", "the most basic cause leads")
end)

T.Case("Diagnose: no visible mobs points at nameplates", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = true, canMark = true,
        cvarsOk = true, roleCount = 8, candidateCount = 0, ruleCount = 1, desiredCount = 0,
    })
    T.Eq(reasons[1], "no hostile mobs are visible. Are enemy nameplates on?", "actionable")
end)

T.Case("Diagnose: no rules names the instance", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = true, canMark = true, cvarsOk = true,
        roleCount = 8, candidateCount = 3, ruleCount = 0, desiredCount = 0, instanceKey = "BLACKTEMPLE",
    })
    T.Eq(reasons[1], "no rules are active for BLACKTEMPLE", "says where")
end)

T.Case("Diagnose: rules and mobs but no match is distinguished from having no rules", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = true, canMark = true, cvarsOk = true,
        roleCount = 8, candidateCount = 3, ruleCount = 5, desiredCount = 0,
    })
    T.Eq(reasons[1], "3 mobs visible but none of them match a rule", "the useful distinction")
end)

T.Case("Diagnose: a healthy state reports what it is doing", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = true, canMark = true, cvarsOk = true,
        roleCount = 8, candidateCount = 3, ruleCount = 5, desiredCount = 2,
    })
    T.Eq(reasons[1], "marking 2 of 3 visible mobs", "no problem to report")
end)

T.Case("Diagnose: a backup says who the marker is rather than looking broken", function()
    local reasons = MFD.Marker.DiagnoseState({
        isMarkingEnabled = true, isAuthority = false, authority = "Grimmtusk", canMark = true,
        cvarsOk = true, roleCount = 8, candidateCount = 3, ruleCount = 5, desiredCount = 2,
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
    T.Eq(MFD.Roles.CanIntentApply("BANISH", "Demon"), true, "demon")
    T.Eq(MFD.Roles.CanIntentApply("BANISH", "Elemental"), true, "elemental")
    T.Eq(MFD.Roles.CanIntentApply("BANISH", "Humanoid"), false, "humanoid cannot be banished")
end)

T.Case("CreatureType: the rejection explains itself", function()
    local _, reason = MFD.Roles.CanIntentApply("BANISH", "Humanoid")
    T.Eq(reason, "Banish does not work on Humanoid targets", "usable in a warning")
end)

T.Case("CreatureType: shackle is undead only, sap is humanoid only on TBC", function()
    T.Eq(MFD.Roles.CanIntentApply("SHACKLE", "Undead"), true, "shackle undead")
    T.Eq(MFD.Roles.CanIntentApply("SHACKLE", "Humanoid"), false, "not humanoids")
    T.Eq(MFD.Roles.CanIntentApply("SAP", "Humanoid"), true, "sap humanoid")
    T.Eq(MFD.Roles.CanIntentApply("SAP", "Beast"), false, "beasts only became sappable after TBC")
end)

T.Case("CreatureType: sheep covers humanoids, beasts and critters", function()
    T.Eq(MFD.Roles.CanIntentApply("SHEEP", "Humanoid"), true, "humanoid")
    T.Eq(MFD.Roles.CanIntentApply("SHEEP", "Beast"), true, "beast")
    T.Eq(MFD.Roles.CanIntentApply("SHEEP", "Undead"), false, "not undead")
end)

T.Case("CreatureType: unrestricted intents accept anything", function()
    T.Eq(MFD.Roles.CanIntentApply("KILL", "Humanoid"), true, "kill")
    T.Eq(MFD.Roles.CanIntentApply("TRAP", "Demon"), true, "trap is not type restricted")
    T.Eq(MFD.Roles.CanIntentApply("IGNORE", "Undead"), true, "ignore")
end)

-- Fail open, deliberately. UnitCreatureType returns a localised string, so on a
-- non-English client nothing would match and a strict check would warn about
-- every single rule. A check that cries wolf gets ignored.
T.Case("CreatureType: an unknown or missing type never warns", function()
    T.Eq(MFD.Roles.CanIntentApply("BANISH", nil), true, "not seen yet")
    T.Eq(MFD.Roles.CanIntentApply("BANISH", "Humanoide"), true, "localised string we do not recognise")
    T.Eq(MFD.Roles.CanIntentApply("BANISH", ""), true, "empty")
end)

T.Case("CreatureType: an unknown intent never warns", function()
    T.Eq(MFD.Roles.CanIntentApply("NONSENSE", "Humanoid"), true, "no opinion")
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

T.Case("Rules: serialise and deserialise round-trip", function()
    local original = {
        BLACKTEMPLE = {
            { npcID = 22890, name = "Illidari Nightlord", intent = "SHEEP", rank = 10, fallback = "KILL", maxCount = 2 },
            { npcID = 22861, name = "Illidari Fearbringer", intent = "KILL", rank = 20 },
        },
    }
    local restored = MFD.Rules.Deserialize(MFD.Rules.Serialize(original))
    T.Eq(restored.BLACKTEMPLE[1].npcID, 22890, "npcID")
    T.Eq(restored.BLACKTEMPLE[1].name, "Illidari Nightlord", "name with a space")
    T.Eq(restored.BLACKTEMPLE[1].intent, "SHEEP", "intent")
    T.Eq(restored.BLACKTEMPLE[1].rank, 10, "rank comes back as a number")
    T.Eq(restored.BLACKTEMPLE[1].fallback, "KILL", "fallback")
    T.Eq(restored.BLACKTEMPLE[1].maxCount, 2, "maxCount")
    T.Eq(restored.BLACKTEMPLE[2].fallback, nil, "an absent optional stays absent")
end)

T.Case("Rules: deserialising rubbish returns nil and a reason", function()
    local restored, err = MFD.Rules.Deserialize("not a rule set")
    T.Eq(restored, nil, "no table")
    T.Eq(type(err), "string", "and an explanation")
end)

T.Case("Rules: an unknown intent is rejected rather than imported blind", function()
    local restored, err = MFD.Rules.Deserialize("BT;1;EXPLODE;10;;;Thing")
    T.Eq(restored, nil, "refused")
    T.Eq(err, "line 1 has unknown intent 'EXPLODE'", "and says which line")
end)

T.Case("Rules: the hash is stable and change sensitive", function()
    local a = { BT = { { npcID = 1, intent = "KILL", rank = 10 } } }
    local b = { BT = { { npcID = 1, intent = "KILL", rank = 10 } } }
    local c = { BT = { { npcID = 1, intent = "SHEEP", rank = 10 } } }
    T.Eq(MFD.Rules.Hash(a), MFD.Rules.Hash(b), "same content, same hash")
    if MFD.Rules.Hash(a) == MFD.Rules.Hash(c) then
        error("changing an intent must change the hash")
    end
end)

T.Case("Rules: BumpVersion only advances when content actually changed", function()
    local db = { rules = { BT = { { npcID = 1, intent = "KILL", rank = 10 } } }, rulesVersion = { counter = 0, hash = "" } }
    MFD.Rules.BumpVersion(db)
    T.Eq(db.rulesVersion.counter, 1, "first bump")
    MFD.Rules.BumpVersion(db)
    T.Eq(db.rulesVersion.counter, 1, "unchanged rules do not bump, so peers skip the transfer")
    db.rules.BT[1].intent = "SHEEP"
    MFD.Rules.BumpVersion(db)
    T.Eq(db.rulesVersion.counter, 2, "a real change bumps")
end)

T.Case("Comms: chunking splits and preserves the payload", function()
    local payload = string.rep("x", 450)
    local chunks = MFD.Comms.Chunk(payload, 200)
    T.Eq(#chunks, 3, "three chunks")
    T.Eq(#chunks[1], 200, "full first chunk")
    T.Eq(#chunks[3], 50, "remainder in the last")
    T.Eq(table.concat(chunks), payload, "concatenation restores it")
end)

T.Case("Comms: a short or empty payload is a single chunk", function()
    T.Eq(#MFD.Comms.Chunk("short", 200), 1, "one chunk")
    T.Eq(#MFD.Comms.Chunk("", 200), 1, "even empty, so a receiver always sees a terminator")
end)

T.Case("Comms: reassembly returns the payload only when complete", function()
    local state = {}
    T.Eq(MFD.Comms.Reassemble(state, "Zed", 1, 2, "hello "), nil, "incomplete")
    T.Eq(MFD.Comms.Reassemble(state, "Zed", 2, 2, "world"), "hello world", "complete")
    T.Eq(state.Zed, nil, "state cleaned up after completion")
end)

T.Case("Comms: chunks arriving out of order still reassemble correctly", function()
    local state = {}
    MFD.Comms.Reassemble(state, "Zed", 2, 2, "world")
    T.Eq(MFD.Comms.Reassemble(state, "Zed", 1, 2, "hello "), "hello world", "order restored by index")
end)

T.Case("Comms: two senders reassemble independently", function()
    local state = {}
    MFD.Comms.Reassemble(state, "Zed", 1, 2, "A")
    MFD.Comms.Reassemble(state, "Mira", 1, 2, "B")
    T.Eq(MFD.Comms.Reassemble(state, "Zed", 2, 2, "1"), "A1", "Zed's payload")
    T.Eq(MFD.Comms.Reassemble(state, "Mira", 2, 2, "2"), "B2", "Mira's payload")
end)

T.Case("Comms: an abandoned transfer times out instead of hanging", function()
    local state = {}
    MFD.Comms.Reassemble(state, "Zed", 1, 3, "partial")
    state.Zed.startedAt = 100
    local abandoned = MFD.Comms.SweepTransfers(state, 200, 20)
    T.Eq(abandoned[1], "Zed", "reported")
    T.Eq(state.Zed, nil, "and dropped so a retry can start clean")
end)

local ALWAYS = function() return true end

T.Case("Comms: only ruled mobs are reported as sightings", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 10)
    MFD.Candidates.Observe(set, "999:BBB", 999, "nameplate2", 10)
    local isRuled = function(npcID) return npcID == 100 end
    local pending = MFD.Comms.PendingSightings(set, {}, isRuled, 10, 10, 2)
    T.Eq(#pending, 1, "the unruled mob is not worth channel bandwidth")
    T.Eq(pending[1], "100:AAA:100", "key and npc id")
end)

-- Re-reported on an interval rather than once, because the authority expires
-- peer-only entries it can no longer vouch for. A backup that went quiet after
-- one report would let the mob fall out of the merged set while still visible.
T.Case("Comms: a sighting repeats only after the refresh interval", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 10)
    local reported = {}
    T.Eq(#MFD.Comms.PendingSightings(set, reported, ALWAYS, 10, 10, 2), 1, "first report")
    T.Eq(#MFD.Comms.PendingSightings(set, reported, ALWAYS, 10, 11, 2), 0, "quiet inside the interval")
    T.Eq(#MFD.Comms.PendingSightings(set, reported, ALWAYS, 10, 12, 2), 1, "refreshed once it elapses")
end)

T.Case("Comms: a mob with no unit is not reported, there is nothing to vouch for", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, nil, 10)
    T.Eq(#MFD.Comms.PendingSightings(set, {}, ALWAYS, 10, 10, 2), 0, "peer-only entries stay quiet")
end)

T.Case("Comms: sightings are batched to a message budget", function()
    local set = {}
    for i = 1, 25 do
        MFD.Candidates.Observe(set, "10" .. i .. ":AAA", 100 + i, "nameplate1", 10)
    end
    local pending = MFD.Comms.PendingSightings(set, {}, ALWAYS, 10, 10, 2)
    T.Eq(#pending, 10, "capped at the per-message budget")
end)

T.Case("Marker: ApplyPublished parses the authority's map and stamps first-seen once", function()
    MFD.Marker.firstPublishedAt = {}
    MFD.Marker.ApplyPublished("100:AAA=8=KILL=,200:BBB=5=SHEEP=Grimmtusk", 50)
    T.Eq(MFD.Marker.published["100:AAA"], 8, "kill icon")
    T.Eq(MFD.Marker.publishedDetail["200:BBB"].owner, "Grimmtusk", "owner carried")
    T.Eq(MFD.Marker.publishedDetail["100:AAA"].owner, nil, "empty owner is nil")
    T.Eq(MFD.Marker.firstPublishedAt["100:AAA"], 50, "stamped on first sight")

    MFD.Marker.ApplyPublished("100:AAA=8=KILL=", 60)
    T.Eq(MFD.Marker.firstPublishedAt["100:AAA"], 50, "not re-stamped, so the backup delay is honest")
    T.Eq(MFD.Marker.published["200:BBB"], nil, "dropped from the map")
    T.Eq(MFD.Marker.firstPublishedAt["200:BBB"], nil, "and its stamp cleared")
end)

T.Case("Marker: a backup waits before placing an icon the authority published", function()
    local firstSeen = { ["100:AAA"] = 100 }
    local actions = MFD.Marker.BackupActions({ ["100:AAA"] = 8 }, {}, firstSeen, 101, 1.5)
    T.Eq(#actions, 0, "still inside the grace delay")
end)

T.Case("Marker: a backup places an icon the authority never managed to apply", function()
    local firstSeen = { ["100:AAA"] = 100 }
    local actions = MFD.Marker.BackupActions({ ["100:AAA"] = 8 }, { ["100:AAA"] = 0 }, firstSeen, 102, 1.5)
    T.Eq(#actions, 1, "past the delay, the backup steps in")
    T.Eq(actions[1].icon, 8, "with the published icon")
end)

T.Case("Marker: a backup does nothing once the icon is already on the mob", function()
    local firstSeen = { ["100:AAA"] = 100 }
    local actions = MFD.Marker.BackupActions({ ["100:AAA"] = 8 }, { ["100:AAA"] = 8 }, firstSeen, 102, 1.5)
    T.Eq(#actions, 0, "the authority got there")
end)

T.Case("Marker: a backup cannot act on a mob it has no unit for", function()
    -- Same rule as the authority: nil in actual means nothing to act through.
    local firstSeen = { ["100:AAA"] = 100 }
    local actions = MFD.Marker.BackupActions({ ["100:AAA"] = 8 }, {}, firstSeen, 102, 1.5)
    T.Eq(#actions, 0, "no unit, no action")
end)

T.Case("Marker: backup actions are deterministic in order", function()
    local firstSeen = { ["300:C"] = 100, ["100:A"] = 100, ["200:B"] = 100 }
    local actual = { ["300:C"] = 0, ["100:A"] = 0, ["200:B"] = 0 }
    local actions = MFD.Marker.BackupActions(
        { ["300:C"] = 1, ["100:A"] = 2, ["200:B"] = 3 }, actual, firstSeen, 102, 1.5)
    T.Eq(actions[1].key, "100:A", "sorted by key")
    T.Eq(actions[3].key, "300:C", "third")
end)

-- A peer sighting carries no unit token. Merging it into the set must not
-- throw away a nameplate handle this client already holds for the same mob.
T.Case("Candidates: observing with no unit keeps an existing handle", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 500)
    MFD.Candidates.Observe(set, "100:AAA", 100, nil, 501)
    T.Eq(set["100:AAA"].unit, "nameplate1", "handle preserved")
    T.Eq(set["100:AAA"].seenAt, 501, "sighting still refreshed")
end)

T.Case("Search: matches on a case-insensitive substring", function()
    local bundled = { [100] = { "Illidari Nightlord", "BLACKTEMPLE" } }
    local results = MFD.Search("nightlord", nil, bundled, {})
    T.Eq(#results, 1, "one hit")
    T.Eq(results[1].npcID, 100, "the right mob")
    T.Eq(results[1].source, "bundled", "provenance")
end)

T.Case("Search: an instance filter excludes other raids", function()
    local bundled = {
        [100] = { "Illidari Nightlord", "BLACKTEMPLE" },
        [200] = { "Illidari Watcher", "HYJAL" },
    }
    local results = MFD.Search("illidari", "BLACKTEMPLE", bundled, {})
    T.Eq(#results, 1, "filtered")
    T.Eq(results[1].npcID, 100, "the BT one")
end)

T.Case("Search: learned mobs appear alongside bundled ones", function()
    local learned = { [300] = { name = "Unlisted Trash", zone = "Sunwell Plateau" } }
    local results = MFD.Search("unlisted", nil, {}, learned)
    T.Eq(#results, 1, "found")
    T.Eq(results[1].source, "learned", "marked as derived so the UI can amber it")
end)

T.Case("Search: a bundled entry wins over a learned duplicate", function()
    local bundled = { [100] = { "Illidari Nightlord", "BLACKTEMPLE" } }
    local learned = { [100] = { name = "Illidari Nightlord", zone = "Black Temple" } }
    local results = MFD.Search("illidari", nil, bundled, learned)
    T.Eq(#results, 1, "not listed twice")
    T.Eq(results[1].source, "bundled", "the curated entry wins")
end)

T.Case("Search: results are sorted by name for a stable list", function()
    local bundled = { [1] = { "Zealot", "BT" }, [2] = { "Acolyte", "BT" } }
    local results = MFD.Search("", nil, bundled, {})
    T.Eq(results[1].name, "Acolyte", "alphabetical")
    T.Eq(results[2].name, "Zealot", "second")
end)

T.Case("Search: a learned mob is filtered by the zone it was seen in", function()
    -- Learned entries carry a zone name, not an instance key, so the filter
    -- matches through the instance's display name. A learned mob seen in a
    -- zone we cannot map is shown rather than hidden: losing it is worse.
    local learned = {
        [300] = { name = "Some Trash", zone = "Black Temple" },
        [400] = { name = "Other Trash", zone = "Hyjal Summit" },
        [500] = { name = "Odd Trash", zone = "Somewhere Unmapped" },
    }
    local results = MFD.Search("trash", "BLACKTEMPLE", {}, learned)
    T.Eq(#results, 2, "the BT one and the unmappable one")
    T.Eq(results[1].npcID, 500, "Odd sorts before Some")
    T.Eq(results[2].npcID, 300, "then the BT mob")
end)

T.Case("Announce: formats icon, intent and owner compactly", function()
    local line = MFD.Announce.Format({
        { key = "1:A", icon = 8, intent = "KILL" },
        { key = "2:B", icon = 5, intent = "SHEEP", owner = "Grimmtusk" },
    })
    T.Eq(line, "Skull>Kill | Moon>Sheep Grimmtusk", "compact single line")
end)

T.Case("Announce: orders by icon so the line reads the same every pull", function()
    local line = MFD.Announce.Format({
        { key = "2:B", icon = 5, intent = "SHEEP" },
        { key = "3:C", icon = 2, intent = "KILL" },
        { key = "1:A", icon = 8, intent = "KILL" },
    })
    T.Eq(line, "Skull>Kill | Circle>Kill | Moon>Sheep", "kill icons lead, in role order")
end)

T.Case("Announce: an empty assignment list produces nothing", function()
    T.Eq(MFD.Announce.Format({}), "", "nothing to say")
end)

T.Case("Base64: round-trips arbitrary bytes", function()
    for _, sample in ipairs({ "", "a", "ab", "abc", "Illidari Nightlord;22890;SHEEP;10", "BT;1;KILL;10;;;A\nBT;2;SHEEP;20;KILL;3;B" }) do
        T.Eq(MFD.H.Base64Decode(MFD.H.Base64Encode(sample)), sample, "round trip of [" .. sample .. "]")
    end
end)

T.Case("Base64: matches the standard encoding", function()
    T.Eq(MFD.H.Base64Encode("a"), "YQ==", "one byte")
    T.Eq(MFD.H.Base64Encode("ab"), "YWI=", "two bytes")
    T.Eq(MFD.H.Base64Encode("abc"), "YWJj", "three bytes")
end)

T.Case("Base64: decoding rubbish returns nil rather than garbage", function()
    T.Eq(MFD.H.Base64Decode("not base64!!"), nil, "bad characters")
    T.Eq(MFD.H.Base64Decode("YQ="), nil, "bad length")
    T.Eq(MFD.H.Base64Decode(42), nil, "not a string")
end)

T.Case("Rules: a full export round-trips through base64", function()
    local rules = { BT = { { npcID = 1, name = "A", intent = "KILL", rank = 10 } } }
    local encoded = MFD.H.Base64Encode(MFD.Rules.Serialize(rules))
    local restored = MFD.Rules.Deserialize(MFD.H.Base64Decode(encoded))
    T.Eq(restored.BT[1].npcID, 1, "survived the trip")
end)

T.Case("Rules: MergeImport updates an existing rule in place and keeps its rank", function()
    local db = { rules = { BT = { { npcID = 1, name = "A", intent = "KILL", rank = 30 } } } }
    local added, updated = MFD.Rules.MergeImport(db, { BT = { { npcID = 1, name = "A", intent = "SHEEP", rank = 10, maxCount = 2 } } })
    T.Eq(updated, 1, "one updated")
    T.Eq(added, 0, "none added")
    T.Eq(db.rules.BT[1].intent, "SHEEP", "intent taken from the import")
    T.Eq(db.rules.BT[1].maxCount, 2, "cap taken from the import")
    T.Eq(db.rules.BT[1].rank, 30, "the local priority is the local player's decision")
end)

T.Case("Rules: MergeImport appends new rules after existing ones", function()
    local db = { rules = { BT = { { npcID = 1, name = "A", intent = "KILL", rank = 10 } } } }
    local added = MFD.Rules.MergeImport(db, { BT = { { npcID = 2, name = "B", intent = "KILL", rank = 5 } } })
    T.Eq(added, 1, "one added")
    T.Eq(#db.rules.BT, 2, "existing rule untouched")
    T.Eq(db.rules.BT[2].npcID, 2, "appended")
    T.Eq(db.rules.BT[2].rank, 20, "ranked after what was already there, not at its imported rank")
end)

T.Case("Rules: MergeImport creates an instance the player had no rules for", function()
    local db = { rules = {} }
    MFD.Rules.MergeImport(db, { HYJAL = { { npcID = 9, name = "H", intent = "TRAP", rank = 10 } } })
    T.Eq(db.rules.HYJAL[1].npcID, 9, "new instance list created")
    T.Eq(db.rules.HYJAL[1].rank, 10, "first rule takes the first rank")
end)

T.Case("Rules: MergeImport never deletes", function()
    local db = { rules = { BT = { { npcID = 1, name = "A", intent = "KILL", rank = 10 }, { npcID = 2, name = "B", intent = "KILL", rank = 20 } } } }
    MFD.Rules.MergeImport(db, { BT = { { npcID = 1, name = "A", intent = "SHEEP", rank = 10 } } })
    T.Eq(#db.rules.BT, 2, "the rule absent from the import survives")
end)

T.Case("Data: every bundled mob names a real instance and carries a name", function()
    local validKeys = {}
    for _, key in pairs(MFD.Rules.INSTANCE_KEYS) do
        validKeys[key] = true
    end

    local count = 0
    for npcID, entry in pairs(MFD.Data.Mobs) do
        count = count + 1
        T.Eq(type(npcID), "number", "npc id " .. tostring(npcID) .. " is a number")
        T.Eq(type(entry[1]), "string", "npc " .. npcID .. " has a name")
        if entry[1] == "" then
            error("npc " .. npcID .. " has an empty name")
        end
        if not validKeys[entry[2]] then
            error("npc " .. npcID .. " names unknown instance '" .. tostring(entry[2]) .. "'")
        end
    end

    if count < 50 then
        error("expected at least the TBC raid bosses, got " .. count)
    end
end)

T.Case("Data: bundled mobs are searchable by name and by instance", function()
    local results = MFD.Search("illidan", "BLACKTEMPLE", MFD.Data.Mobs, {})
    T.Eq(#results, 1, "one Illidan in BT")
    T.Eq(results[1].npcID, 22917, "and it is him")

    local wrongZone = MFD.Search("illidan", "KARAZHAN", MFD.Data.Mobs, {})
    T.Eq(#wrongZone, 0, "not in Karazhan")
end)

T.Case("Classify: raid buffs are detected by name, single or greater", function()
    local s = MFD.RaidCheck.Classify({ "Arcane Brilliance", "Mark of the Wild", "Prayer of Fortitude", "Shadow Protection" })
    T.Eq(s.AI, true, "brilliance counts as intellect")
    T.Eq(s.MOTW, true, "mark")
    T.Eq(s.FORT, true, "prayer counts as fortitude")
    T.Eq(s.SP, true, "shadow protection")
end)

T.Case("Classify: absent buffs are false, not nil", function()
    local s = MFD.RaidCheck.Classify({})
    T.Eq(s.AI, false, "explicit false so a cell can be painted red rather than grey")
    T.Eq(#s.blessings, 0, "no blessings")
end)

T.Case("Classify: food, flask and elixirs land in their own slots", function()
    local s = MFD.RaidCheck.Classify({ "Well Fed", "Flask of Relentless Assault", "Elixir of Major Agility", "Elixir of Major Fortitude" })
    T.Eq(s.food, "Well Fed", "food")
    T.Eq(s.flask, "Flask of Relentless Assault", "flask by prefix")
    T.Eq(s.battle, "Elixir of Major Agility", "battle elixir")
    T.Eq(s.guardian, "Elixir of Major Fortitude", "guardian elixir")
end)

T.Case("Classify: an elixir not in either table is reported as unclassified, never dropped", function()
    local s = MFD.RaidCheck.Classify({ "Elixir of Something New" })
    T.Eq(s.battle, nil, "not filed as battle")
    T.Eq(s.guardian, nil, "not filed as guardian")
    T.Eq(s.unclassifiedElixir, "Elixir of Something New", "surfaced so the table can be fixed")
end)

T.Case("Classify: blessings are listed by short label and sorted, never judged", function()
    local s = MFD.RaidCheck.Classify({ "Greater Blessing of Salvation", "Blessing of Kings" })
    T.Eq(s.blessings[1], "Kings", "sorted")
    T.Eq(s.blessings[2], "Salv", "greater and single collapse to the same label")
end)

T.Case("Classify: unknown auras are ignored without error", function()
    local s = MFD.RaidCheck.Classify({ "Some Trinket Proc", "Bloodlust", "" })
    T.Eq(s.food, nil, "nothing misfiled")
    T.Eq(s.AI, false, "nothing misfiled")
end)

T.Case("Providers: a buff is providable only if someone present can cast it", function()
    local p = MFD.RaidCheck.Providers(roster("Alfred", "MAGE", "Thok", "WARRIOR"))
    T.Eq(p.AI, true, "a mage is here")
    T.Eq(p.MOTW, false, "no druid")
    T.Eq(p.FORT, false, "no priest")
end)

T.Case("Missing: a raid buff nobody can cast is not reported", function()
    local state = MFD.RaidCheck.Classify({})
    local missing = MFD.RaidCheck.Missing(state, { AI = false, MOTW = false, FORT = false, SP = false }, {})
    for _, m in ipairs(missing) do
        if m.column == "AI" or m.column == "MOTW" then
            error("reported " .. m.column .. " with no provider present")
        end
    end
end)

T.Case("Missing: a raid buff someone can cast and the player lacks is reported", function()
    local state = MFD.RaidCheck.Classify({ "Mark of the Wild" })
    local missing = MFD.RaidCheck.Missing(state, { AI = true, MOTW = true, FORT = false, SP = false }, {})
    T.Eq(#missing, 1, "only intellect")
    T.Eq(missing[1].column, "AI", "the one a mage could fix")
    T.Eq(missing[1].label, "Int", "with its short label")
end)

T.Case("Missing: consumables are reported only when flagged as expected", function()
    local state = MFD.RaidCheck.Classify({})
    local none = MFD.RaidCheck.Missing(state, {}, {})
    T.Eq(#none, 0, "nothing expected, nothing missing")

    local some = MFD.RaidCheck.Missing(state, {}, { FOOD = true, ELIXIRS = true })
    T.Eq(#some, 2, "two expected, both absent")
    T.Eq(some[1].column, "FOOD", "fixed order")
    T.Eq(some[2].column, "ELIXIRS", "fixed order")
end)

T.Case("Missing: a present consumable is not reported even when expected", function()
    local state = MFD.RaidCheck.Classify({ "Well Fed" })
    local missing = MFD.RaidCheck.Missing(state, {}, { FOOD = true })
    T.Eq(#missing, 0, "fed")
end)

T.Case("Report: encode and decode round-trip the self-reported state", function()
    local state = {
        version = "0.9.0", durability = 87, spec = "Fire",
        AI = true, MOTW = false, FORT = true, SP = false,
        food = true, flask = false, battle = true, guardian = false,
    }
    local decoded = MFD.RaidCheck.DecodeReport(MFD.RaidCheck.EncodeReport(state))
    T.Eq(decoded.version, "0.9.0", "version")
    T.Eq(decoded.durability, 87, "durability as a number")
    T.Eq(decoded.spec, "Fire", "spec")
    T.Eq(decoded.AI, true, "AI")
    T.Eq(decoded.MOTW, false, "MOTW false, not nil")
    T.Eq(decoded.battle, true, "battle")
    T.Eq(decoded.guardian, false, "guardian")
end)

T.Case("Report: unknown fields encode as unknown and decode as nil", function()
    local decoded = MFD.RaidCheck.DecodeReport(MFD.RaidCheck.EncodeReport({ version = "x" }))
    T.Eq(decoded.durability, nil, "no durability is nil")
    T.Eq(decoded.spec, nil, "no spec is nil")
    T.Eq(decoded.AI, nil, "unknown buff is nil")
end)

T.Case("Report: the encoded form fits one addon message with room to spare", function()
    local fields = MFD.RaidCheck.EncodeReport({
        version = "10.10.10", durability = 100, spec = "Restoration",
        AI = true, MOTW = true, FORT = true, SP = true, food = true, flask = true, battle = true, guardian = true,
    })
    local wire = MFD.Comms.Encode("PC", fields)
    if #wire > 120 then
        error("report is " .. #wire .. " bytes; must stay well under the 255 byte cap")
    end
end)

T.Case("Report: decoding rubbish returns nil", function()
    T.Eq(MFD.RaidCheck.DecodeReport({}), nil, "empty")
    T.Eq(MFD.RaidCheck.DecodeReport({ "not", "a", "report" }), nil, "wrong shape")
end)

T.Case("MergeRow: a report overrides a scanned flag but never a scanned name", function()
    local scanned = MFD.RaidCheck.Classify({ "Flask of Relentless Assault" })
    local reported = { flask = false, AI = true, durability = 90, spec = "Fire", version = "1.0.0" }
    local row = MFD.RaidCheck.MergeRow(scanned, reported)
    T.Eq(row.isReported, true, "marked as reported")
    T.Eq(row.state.AI, true, "report supplies a flag the scan could not see")
    T.Eq(row.state.flask, "Flask of Relentless Assault", "the scanned name is kept for display")
    T.Eq(row.state.durability, 90, "durability from the report")
    T.Eq(row.state.spec, "Fire", "spec from the report")
end)

T.Case("MergeRow: no report leaves the row scan-only with unknowns nil", function()
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({ "Well Fed" }), nil)
    T.Eq(row.isReported, false, "scan only")
    T.Eq(row.state.food, "Well Fed", "scanned name")
    T.Eq(row.state.durability, nil, "unknown")
end)

T.Case("MergeRow: a reported false does not erase a scanned present name", function()
    -- The report is a flag snapshot that can lag the scan by a debounce.
    -- The scan just saw the flask. Keep the name; the flag is informational.
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({ "Flask of Blinding Light" }), { flask = false })
    T.Eq(row.state.flask, "Flask of Blinding Light", "present in the scan wins for names")
end)

T.Case("Missing: a flask satisfies the elixir requirement on its own", function()
    local state = MFD.RaidCheck.Classify({ "Flask of Relentless Assault" })
    local missing = MFD.RaidCheck.Missing(state, {}, { ELIXIRS = true })
    T.Eq(#missing, 0, "a flask is both elixirs")
end)

local function entryWith(name, ...)
    local missing = {}
    for _, label in ipairs({ ... }) do
        missing[#missing + 1] = { column = label, label = label }
    end
    return { name = name, missing = missing }
end

T.Case("Callout: groups players by what they are missing", function()
    local lines = MFD.RaidCheck.FormatCallout({
        entryWith("Bob", "Int", "Flask"),
        entryWith("Sue", "Int"),
        entryWith("Dave", "Flask"),
    })
    T.Eq(lines[1], "Int: Bob, Sue", "first fix, sorted names")
    T.Eq(lines[2], "Flask: Bob, Dave", "second fix")
end)

T.Case("Callout: nothing missing produces no lines", function()
    T.Eq(#MFD.RaidCheck.FormatCallout({ entryWith("Bob") }), 0, "silence")
end)

T.Case("Callout: lines are capped and the overflow is counted", function()
    local entries = {}
    for i = 1, 8 do
        entries[i] = entryWith("P" .. i, "Fix" .. i)
    end
    local lines = MFD.RaidCheck.FormatCallout(entries)
    T.Eq(#lines, MFD.RaidCheck.CALLOUT_MAX_LINES, "capped")
    if not string.find(lines[#lines], "and %d+ more") then
        error("last line should say how many fixes were left out, got: " .. lines[#lines])
    end
end)

T.Case("Callout: a very long name list is cut to the byte limit", function()
    local entries = {}
    for i = 1, 60 do
        entries[i] = entryWith("Longishplayername" .. i, "Int")
    end
    local lines = MFD.RaidCheck.FormatCallout(entries)
    if #lines[1] > MFD.RaidCheck.CALLOUT_LINE_BYTES then
        error("line is " .. #lines[1] .. " bytes")
    end
end)

T.Case("Whisper: names exactly what one player is missing", function()
    T.Eq(MFD.RaidCheck.FormatWhisper(entryWith("Bob", "Int", "Flask")), "You are missing: Int, Flask", "template")
    T.Eq(MFD.RaidCheck.FormatWhisper(entryWith("Bob")), nil, "nothing to say")
end)

-- Durability from the shared LibDurability protocol, which most raiders answer
-- through BigWigs, DBM or MRT whether or not they run this addon.
T.Case("MergeRow: LibDurability fills durability when there is no self-report", function()
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({}), nil, 73)
    T.Eq(row.state.durability, 73, "taken from the shared protocol")
    T.Eq(row.isReported, false, "but the row is still not an MFD-reported row")
end)

T.Case("MergeRow: a self-report wins over LibDurability for durability", function()
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({}), { durability = 90 }, 73)
    T.Eq(row.state.durability, 90, "the owning client's own report is authoritative")
end)

T.Case("MergeRow: a self-report without durability still falls back to LibDurability", function()
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({}), { spec = "Fire" }, 73)
    T.Eq(row.state.durability, 73, "report present but silent on durability, so the lib fills it")
    T.Eq(row.state.spec, "Fire", "and the rest of the report still applies")
end)

T.Case("Durability: the shared protocol's response parses to percent and broken count", function()
    local percent, broken = MFD.RaidCheck.ParseDurabilityMessage("85,1")
    T.Eq(percent, 85, "percent")
    T.Eq(broken, 1, "broken item count")
end)

T.Case("Durability: a request or rubbish does not parse as a response", function()
    T.Eq(MFD.RaidCheck.ParseDurabilityMessage("R"), nil, "a request")
    T.Eq(MFD.RaidCheck.ParseDurabilityMessage("lots,of,commas"), nil, "wrong shape")
    T.Eq(MFD.RaidCheck.ParseDurabilityMessage(nil), nil, "nil")
end)

-- Spec from inspected talent tabs. Works on anyone in inspect range running
-- nothing at all, which beats every addon-to-addon protocol available here.
T.Case("Spec: the tab with the most points names the spec", function()
    T.Eq(MFD.RaidCheck.SpecFromTabs({ { name = "Arcane", points = 0 }, { name = "Fire", points = 41 }, { name = "Frost", points = 20 } }), "Fire", "fire")
end)

T.Case("Spec: no points spent means no spec, not the first tab", function()
    T.Eq(MFD.RaidCheck.SpecFromTabs({ { name = "Arcane", points = 0 }, { name = "Fire", points = 0 }, { name = "Frost", points = 0 } }), nil, "unspecced")
    T.Eq(MFD.RaidCheck.SpecFromTabs({}), nil, "no tabs")
end)

T.Case("Spec: a tie goes to the first tab so the answer is stable", function()
    T.Eq(MFD.RaidCheck.SpecFromTabs({ { name = "Holy", points = 30 }, { name = "Disc", points = 30 }, { name = "Shadow", points = 1 } }), "Holy", "first wins")
end)

-- A self-reported spec is what makes a player "known"; an inspected one is
-- refreshed on its own ttl, so the helper marks the row reported only when a
-- spec is given.
local function rowEntry(name, spec)
    return { name = name, row = { state = { spec = spec }, isReported = spec ~= nil } }
end

T.Case("Inspect: the next target is the first player with no fresh spec from any source", function()
    local entries = { rowEntry("Zed", nil), rowEntry("Alfred", nil), rowEntry("Mira", "Fire") }
    local inspected = { Alfred = { spec = "Frost", at = 100 } }
    T.Eq(MFD.RaidCheck.NextInspectTarget(entries, inspected, 120, 60), "Zed",
        "Alfred is fresh, Mira self-reported, Zed is the one left")
end)

T.Case("Inspect: a stale inspection is re-done after the ttl", function()
    local entries = { rowEntry("Alfred", nil) }
    local inspected = { Alfred = { spec = "Frost", at = 100 } }
    T.Eq(MFD.RaidCheck.NextInspectTarget(entries, inspected, 161, 60), "Alfred", "older than ttl")
    T.Eq(MFD.RaidCheck.NextInspectTarget(entries, inspected, 159, 60), nil, "still fresh")
end)

T.Case("Inspect: nobody needs inspecting returns nil", function()
    local entries = { rowEntry("Mira", "Fire") }
    T.Eq(MFD.RaidCheck.NextInspectTarget(entries, {}, 100, 60), nil, "everyone known")
    T.Eq(MFD.RaidCheck.NextInspectTarget({}, {}, 100, 60), nil, "empty group")
end)

T.Case("MergeRow: an inspected spec fills in when there is no self-reported one", function()
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({}), nil, nil, "Frost")
    T.Eq(row.state.spec, "Frost", "from inspect")
    T.Eq(row.isReported, false, "still not an MFD-reported row")
end)

T.Case("MergeRow: a self-reported spec wins over an inspected one", function()
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({}), { spec = "Fire" }, nil, "Frost")
    T.Eq(row.state.spec, "Fire", "the owning client is authoritative")
end)

-- An empty field must survive the round trip. Dropping it shifts every field
-- after it, which silently changes what a message means.
T.Case("Comms: an empty field keeps its position", function()
    local msgType, fields = MFD.Comms.Decode(MFD.Comms.Encode("L", { "", "Dillon", 123 }))
    T.Eq(msgType, "L", "type")
    T.Eq(fields[1], "", "the empty name is still field one")
    T.Eq(fields[2], "Dillon", "not shifted down")
    T.Eq(fields[3], "123", "nor this")
end)

-- The bug this pins down: clearing the Raid Lead sends an empty name, and the
-- old split turned "L~~Dillon~123" into fields {Dillon, 123}, so every client
-- read the clearer's own name as the new lead instead of clearing it.
T.Case("Comms: clearing the Raid Lead decodes as a clear, not as a name", function()
    local _, fields = MFD.Comms.Decode(MFD.Comms.Encode("L", { "", "Dezedin", 1788480000 }))
    T.Eq(fields[1], "", "no lead")
    T.Eq(fields[2], "Dezedin", "set by")
    T.Eq(tonumber(fields[3]), 1788480000, "timestamp intact")
end)

T.Case("Comms: trailing and consecutive empty fields survive", function()
    local _, fields = MFD.Comms.Decode(MFD.Comms.Encode("X", { "a", "", "", "b", "" }))
    T.Eq(#fields, 5, "all five fields")
    T.Eq(fields[2], "", "second empty")
    T.Eq(fields[3], "", "third empty")
    T.Eq(fields[4], "b", "not shifted")
    T.Eq(fields[5], "", "trailing empty kept")
end)

T.Case("Comms: a type with no fields still decodes", function()
    local msgType, fields = MFD.Comms.Decode(MFD.Comms.Encode("B", {}))
    T.Eq(msgType, "B", "type")
    T.Eq(#fields, 0, "no fields")
end)

-- The assignment and sighting payloads are the two messages that have never
-- been exercised with a second client, and they carry the coverage feature.
T.Case("Assignments: encode and decode round-trip", function()
    local list = {
        { key = "22890:1A2B", icon = 8, intent = "KILL" },
        { key = "22880:3C4D", icon = 5, intent = "SHEEP", owner = "Grimmtusk" },
    }
    local decoded = MFD.Marker.DecodeAssignments(MFD.Marker.EncodeAssignments(list))
    T.Eq(#decoded, 2, "both")
    T.Eq(decoded[1].key, "22890:1A2B", "key")
    T.Eq(decoded[1].icon, 8, "icon as a number")
    T.Eq(decoded[1].intent, "KILL", "intent")
    T.Eq(decoded[1].owner, nil, "no owner stays nil, not empty string")
    T.Eq(decoded[2].owner, "Grimmtusk", "owner")
end)

T.Case("Assignments: an empty list round-trips to nothing", function()
    T.Eq(MFD.Marker.EncodeAssignments({}), "", "empty payload")
    T.Eq(#MFD.Marker.DecodeAssignments(""), 0, "decodes to no assignments")
end)

T.Case("Assignments: a truncated or corrupt payload yields only whole entries", function()
    local decoded = MFD.Marker.DecodeAssignments("22890:1A2B=8=KILL=,22880:3C")
    T.Eq(#decoded, 1, "the complete one survives, the fragment is dropped")
    T.Eq(decoded[1].key, "22890:1A2B", "the whole entry")
end)

T.Case("Assignments: encoding is stable so an unchanged map is not republished", function()
    local list = {
        { key = "22880:3C4D", icon = 5, intent = "SHEEP", owner = "Grimmtusk" },
        { key = "22890:1A2B", icon = 8, intent = "KILL" },
    }
    T.Eq(MFD.Marker.EncodeAssignments(list), MFD.Marker.EncodeAssignments(list), "same input, same bytes")
end)

T.Case("Sightings: encode and decode round-trip", function()
    local decoded = MFD.Comms.DecodeSightings(MFD.Comms.EncodeSightings({ "100:AAA:100", "200:BBB:200" }))
    T.Eq(#decoded, 2, "both")
    T.Eq(decoded[1].key, "100:AAA", "key")
    T.Eq(decoded[1].npcID, 100, "npcID as a number")
    T.Eq(decoded[2].key, "200:BBB", "second")
end)

T.Case("Sightings: rubbish yields nothing rather than a bad candidate", function()
    T.Eq(#MFD.Comms.DecodeSightings(""), 0, "empty")
    T.Eq(#MFD.Comms.DecodeSightings("not a sighting"), 0, "rubbish")
    T.Eq(#MFD.Comms.DecodeSightings(nil), 0, "nil")
end)

-- The tick runs five times a second. Rebuilding the roster and re-resolving
-- every role on each one is 125 roster API calls a second in a full raid, for
-- an answer that only changes when somebody joins or leaves.
T.Case("Roster: the roster is built once and reused until invalidated", function()
    local builds = 0
    local realBuild = MFD.Marker.BuildRoster
    MFD.Marker.BuildRoster = function()
        builds = builds + 1
        return { { name = "Alfred", class = "MAGE" } }
    end

    MFD.Marker.InvalidateRoster()
    MFD.Marker.CurrentRoster()
    MFD.Marker.CurrentRoster()
    MFD.Marker.CurrentRoster()
    T.Eq(builds, 1, "three calls, one build")

    MFD.Marker.InvalidateRoster()
    MFD.Marker.CurrentRoster()
    T.Eq(builds, 2, "invalidating forces a rebuild")

    MFD.Marker.BuildRoster = realBuild
    MFD.Marker.InvalidateRoster()
end)

T.Case("Roster: the cached roster still has the right contents", function()
    local realBuild = MFD.Marker.BuildRoster
    MFD.Marker.BuildRoster = function()
        return { { name = "Grimmtusk", class = "MAGE" } }
    end

    MFD.Marker.InvalidateRoster()
    T.Eq(MFD.Marker.CurrentRoster()[1].name, "Grimmtusk", "first call")
    T.Eq(MFD.Marker.CurrentRoster()[1].class, "MAGE", "and the cached one")

    MFD.Marker.BuildRoster = realBuild
    MFD.Marker.InvalidateRoster()
end)

T.Case("Roles: resolution is cached against the roster and the plan", function()
    local realBuild = MFD.Marker.BuildRoster
    MFD.Marker.BuildRoster = function()
        return { { name = "Grimmtusk", class = "MAGE" } }
    end
    MFD.Marker.InvalidateRoster()

    local plan = { [5] = { intent = "SHEEP", ordinal = 1 } }
    local first = MFD.Marker.ResolvedRoles(plan)
    T.Eq(first == MFD.Marker.ResolvedRoles(plan), true, "same table returned, not re-resolved")
    T.Eq(first.byIcon[5].owner, "Grimmtusk", "and it is correct")

    MFD.Marker.InvalidateRoster()
    T.Eq(first == MFD.Marker.ResolvedRoles(plan), false, "invalidating re-resolves")

    MFD.Marker.BuildRoster = realBuild
    MFD.Marker.InvalidateRoster()
end)

-- Broken gear is the thing a durability column exists to catch: 40% overall
-- with a broken weapon is a different problem from 40% spread evenly.
T.Case("Durability: a broken item count rides along with the percent", function()
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({}), nil, 42, nil, 2)
    T.Eq(row.state.durability, 42, "percent")
    T.Eq(row.state.brokenItems, 2, "broken count")
end)

T.Case("Durability: no broken data is nil rather than zero", function()
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({}), nil, 42, nil, nil)
    T.Eq(row.state.brokenItems, nil, "unknown, not none")
end)

T.Case("Durability: zero broken is reported as zero, not dropped", function()
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({}), nil, 95, nil, 0)
    T.Eq(row.state.brokenItems, 0, "known to be none")
end)

-- Rules typed by name, for planning a raid you have not walked yet. A rule
-- with no npcID matches any mob whose name matches, so a whole instance can be
-- written out from a guide before the addon has ever seen the place.
T.Case("Rules: a name-only rule gets a stable merge key", function()
    T.Eq(MFD.Rules.MergeKey({ npcID = 22890, name = "Illidari Nightlord" }), 22890, "id wins when present")
    T.Eq(MFD.Rules.MergeKey({ name = "Illidari Nightlord" }), "name:illidari nightlord", "else the lowercased name")
    T.Eq(MFD.Rules.MergeKey({ name = "ILLIDARI NIGHTLORD" }), "name:illidari nightlord", "case does not fork the key")
    T.Eq(MFD.Rules.MergeKey({}), nil, "a rule with neither is not a rule")
end)

T.Case("Rules: name-only rules from two contributors still resolve lead-first", function()
    local merged = MFD.Rules.Merge({
        { owner = "Grimmtusk", rules = { BT = { { name = "Illidari Nightlord", intent = "BANISH", rank = 5 } } } },
        { owner = "Dillon", rules = { BT = { { name = "Illidari Nightlord", intent = "SHEEP", rank = 40 } } } },
    }, "Dillon")
    T.Eq(merged.BT["name:illidari nightlord"].intent, "SHEEP", "the lead's version wins")
    T.Eq(merged.BT["name:illidari nightlord"].owner, "Dillon", "and carries their name")
end)

T.Case("Resolve: an id rule matches the candidate carrying that id", function()
    local active = { [22890] = { npcID = 22890, intent = "SHEEP", rank = 10 } }
    local resolved = MFD.Rules.ResolveForCandidates(active, {
        { key = "22890:A", npcID = 22890, name = "Illidari Nightlord" },
    })
    T.Eq(resolved[22890].intent, "SHEEP", "matched by id")
end)

T.Case("Resolve: a name-only rule matches by name, case insensitively", function()
    local active = { ["name:illidari nightlord"] = { name = "Illidari Nightlord", intent = "SHEEP", rank = 10 } }
    local resolved = MFD.Rules.ResolveForCandidates(active, {
        { key = "22890:A", npcID = 22890, name = "illidari nightlord" },
    })
    T.Eq(resolved[22890].intent, "SHEEP", "matched by name onto the live id")
end)

T.Case("Resolve: one name rule covers every id sharing that name", function()
    local active = { ["name:shadowmoon champion"] = { name = "Shadowmoon Champion", intent = "KILL", rank = 10 } }
    local resolved = MFD.Rules.ResolveForCandidates(active, {
        { key = "100:A", npcID = 100, name = "Shadowmoon Champion" },
        { key = "200:B", npcID = 200, name = "Shadowmoon Champion" },
    })
    T.Eq(resolved[100].intent, "KILL", "first id")
    T.Eq(resolved[200].intent, "KILL", "second id, same rule")
end)

T.Case("Resolve: an id rule beats a name rule for the same mob", function()
    local active = {
        [22890] = { npcID = 22890, intent = "BANISH", rank = 5 },
        ["name:illidari nightlord"] = { name = "Illidari Nightlord", intent = "SHEEP", rank = 10 },
    }
    local resolved = MFD.Rules.ResolveForCandidates(active, {
        { key = "22890:A", npcID = 22890, name = "Illidari Nightlord" },
    })
    T.Eq(resolved[22890].intent, "BANISH", "the more specific rule wins")
end)

T.Case("Resolve: a name rule with nothing on screen matching it is simply absent", function()
    local active = { ["name:illidari nightlord"] = { name = "Illidari Nightlord", intent = "SHEEP", rank = 10 } }
    T.Eq(next(MFD.Rules.ResolveForCandidates(active, {})), nil, "no candidates")
    T.Eq(next(MFD.Rules.ResolveForCandidates(active, { { key = "1:A", npcID = 1, name = "Something Else" } })), nil, "no match")
end)

T.Case("Resolve: a candidate with no name still matches its id rule", function()
    local active = { [22890] = { npcID = 22890, intent = "KILL", rank = 10 } }
    local resolved = MFD.Rules.ResolveForCandidates(active, { { key = "22890:A", npcID = 22890 } })
    T.Eq(resolved[22890].intent, "KILL", "a peer sighting carries no name and must still work")
end)

T.Case("Ranked: name-only and id rules sort together by rank", function()
    local ranked = MFD.Rules.Ranked({
        ["name:b mob"] = { name = "B Mob", rank = 20 },
        [100] = { npcID = 100, name = "A Mob", rank = 10 },
    })
    T.Eq(ranked[1].name, "A Mob", "lowest rank first regardless of key shape")
    T.Eq(ranked[2].name, "B Mob", "second")
end)

-- Bulk entry: paste a kill order straight out of a guide, one mob per line,
-- top line highest priority.
T.Case("Bulk: one name per line becomes rules in the order given", function()
    local rules = MFD.Rules.ParseBulk("Illidari Nightlord\nShadowmoon Champion\nIllidari Fearbringer")
    T.Eq(#rules, 3, "three rules")
    T.Eq(rules[1].name, "Illidari Nightlord", "first line")
    T.Eq(rules[1].rank, 10, "highest priority")
    T.Eq(rules[2].rank, 20, "then the next")
    T.Eq(rules[3].rank, 30, "spaced by the rank step")
    T.Eq(rules[1].intent, "KILL", "kill unless told otherwise")
end)

T.Case("Bulk: an intent can follow the name after an equals sign", function()
    local rules = MFD.Rules.ParseBulk("Illidari Nightlord = sheep\nSummoner = banish")
    T.Eq(rules[1].intent, "SHEEP", "case insensitive")
    T.Eq(rules[1].name, "Illidari Nightlord", "name is trimmed")
    T.Eq(rules[2].intent, "BANISH", "second")
end)

T.Case("Bulk: blank lines and comments are skipped without shifting priority", function()
    local rules = MFD.Rules.ParseBulk("-- first pack\nIllidari Nightlord\n\n   \n# second pack\nShadowmoon Champion")
    T.Eq(#rules, 2, "only the two mobs")
    T.Eq(rules[1].rank, 10, "priority counts mobs, not lines")
    T.Eq(rules[2].rank, 20, "second mob")
end)

T.Case("Bulk: an unknown intent fails the whole paste rather than importing half", function()
    local rules, err = MFD.Rules.ParseBulk("Good Mob = sheep\nBad Mob = frobnicate")
    T.Eq(rules, nil, "nothing imported")
    T.Eq(err, "line 2: unknown job 'frobnicate'", "and it says which line")
end)

T.Case("Bulk: an empty paste is an error, not an empty rule set", function()
    local rules, err = MFD.Rules.ParseBulk("\n\n  \n")
    T.Eq(rules, nil, "nothing to import")
    T.Eq(type(err), "string", "with a reason")
end)

T.Case("Bulk: a duplicate name is rejected so the paste cannot fight itself", function()
    local rules, err = MFD.Rules.ParseBulk("Illidari Nightlord\nillidari nightlord = sheep")
    T.Eq(rules, nil, "rejected")
    T.Eq(err, "line 2: 'illidari nightlord' is already in this list", "naming the collision")
end)

T.Case("Bulk: an npcID can be given instead of a name", function()
    local rules = MFD.Rules.ParseBulk("22890 = sheep\nIllidari Fearbringer")
    T.Eq(rules[1].npcID, 22890, "numeric lines are ids")
    T.Eq(rules[1].name, nil, "and carry no name")
    T.Eq(rules[2].npcID, nil, "the other stays a name rule")
end)

-- Guards against the bundled table silently regressing to bosses only, which
-- is what it was before and which looks fine until someone searches for trash.
T.Case("Data: the bundled table carries real trash, not just bosses", function()
    local mobs = MFD.Data.Mobs
    local function nameOf(id) return mobs[id] and mobs[id][1] end

    T.Eq(nameOf(22855), "Illidari Nightlord", "Black Temple trash")
    T.Eq(nameOf(22844), "Ashtongue Battlelord", "Black Temple trash")
    T.Eq(nameOf(22880), "Shadowmoon Champion", "the mob Dillon ruled first")
    T.Eq(nameOf(17897), "Crypt Fiend", "Hyjal wave trash")
    T.Eq(nameOf(17907), "Frost Wyrm", "Hyjal wave trash")
    T.Eq(nameOf(20040), "Crystalcore Devastator", "Tempest Keep trash")
end)

T.Case("Data: every raid has more creatures than it has bosses", function()
    local counts = {}
    for _, entry in pairs(MFD.Data.Mobs) do
        counts[entry[2]] = (counts[entry[2]] or 0) + 1
    end
    -- Every TBC raid has more than a dozen distinct creatures. A key well
    -- under that means its extraction fell back to bosses.
    for _, key in ipairs({ "BLACKTEMPLE", "HYJAL", "KARAZHAN", "SERPENTSHRINE",
                           "TEMPESTKEEP", "ZULAMAN", "SUNWELL" }) do
        if (counts[key] or 0) < 15 then
            error(key .. " has only " .. (counts[key] or 0) .. " creatures; extraction regressed")
        end
    end
end)

T.Case("Data: every entry is a name and a known instance key", function()
    local known = {}
    for _, key in pairs(MFD.Rules.INSTANCE_KEYS) do known[key] = true end

    for id, entry in pairs(MFD.Data.Mobs) do
        if type(id) ~= "number" then
            error("non numeric npc id: " .. tostring(id))
        end
        if type(entry[1]) ~= "string" or entry[1] == "" then
            error("id " .. id .. " has no name")
        end
        if not known[entry[2]] then
            error("id " .. id .. " has unknown instance key " .. tostring(entry[2]))
        end
    end
end)

T.Case("Search: bundled trash is findable by a partial name", function()
    local results = MFD.Search("nightlord", nil, MFD.Data.Mobs, {})
    T.Eq(#results, 1, "one hit")
    T.Eq(results[1].name, "Illidari Nightlord", "the right one")
    T.Eq(results[1].source, "bundled", "from the bundled table")
end)

T.Case("Search: filtering to an instance narrows bundled results", function()
    local all = MFD.Search("ashtongue", nil, MFD.Data.Mobs, {})
    local bt = MFD.Search("ashtongue", "BLACKTEMPLE", MFD.Data.Mobs, {})
    if #all == 0 then
        error("expected Ashtongue mobs in the bundled table")
    end
    T.Eq(#bt, #all, "all of them are Black Temple")
    T.Eq(#MFD.Search("ashtongue", "HYJAL", MFD.Data.Mobs, {}), 0, "and none are Hyjal")
end)

-- The exact pack Dillon asked about: two Coilskar Wranglers and one Leviathan,
-- all ruled Kill, against the shipped default role plan.
local function killPack(wranglerRank, leviathanRank)
    local db = { rolePlan = {} }
    MFD.Roles.EnsurePlan(db)
    local roles = MFD.Roles.Resolve(db.rolePlan, roster("Thok", "WARRIOR"))

    local candidates = {
        { key = "22877:AAA", npcID = 22877, name = "Coilskar Wrangler" },
        { key = "22877:BBB", npcID = 22877, name = "Coilskar Wrangler" },
        { key = "22884:CCC", npcID = 22884, name = "Leviathan" },
    }
    local rules = {
        [22877] = { npcID = 22877, intent = "KILL", rank = wranglerRank },
        [22884] = { npcID = 22884, intent = "KILL", rank = leviathanRank },
    }
    return MFD.Allocator.Compute(candidates, rules, roles, nil).byKey
end

T.Case("Pack: wranglers above leviathan take skull and cross, leviathan takes square", function()
    local icons = killPack(10, 20)
    T.Eq(icons["22877:AAA"], 8, "first wrangler skull")
    T.Eq(icons["22877:BBB"], 7, "second wrangler cross")
    T.Eq(icons["22884:CCC"], 6, "leviathan square")
end)

T.Case("Pack: put leviathan above and it takes skull instead", function()
    local icons = killPack(20, 10)
    T.Eq(icons["22884:CCC"], 8, "leviathan skull")
    T.Eq(icons["22877:AAA"], 7, "wranglers follow")
    T.Eq(icons["22877:BBB"], 6, "in cross then square")
end)

T.Case("Pack: two copies of one mob get different icons, never the same one", function()
    local icons = killPack(10, 20)
    if icons["22877:AAA"] == icons["22877:BBB"] then
        error("both wranglers got icon " .. tostring(icons["22877:AAA"]))
    end
end)

T.Case("Pack: a fourth kill target takes circle, a fifth goes unmarked", function()
    local db = { rolePlan = {} }
    MFD.Roles.EnsurePlan(db)
    local roles = MFD.Roles.Resolve(db.rolePlan, roster("Thok", "WARRIOR"))

    local candidates, rules = {}, { [22877] = { npcID = 22877, intent = "KILL", rank = 10 } }
    for i = 1, 5 do
        candidates[i] = { key = "22877:" .. string.char(64 + i), npcID = 22877, name = "Coilskar Wrangler" }
    end

    local icons = MFD.Allocator.Compute(candidates, rules, roles, nil).byKey
    local placed = 0
    for _ in pairs(icons) do placed = placed + 1 end
    T.Eq(placed, 4, "four kill roles exist, so the fifth is left alone")
    T.Eq(icons["22877:D"], 2, "fourth takes circle")
    T.Eq(icons["22877:E"], nil, "fifth unmarked rather than stealing a cc icon")
end)

-- Spare icon reuse: when no mob needs Moon or Triangle, let kill targets have
-- them rather than leaving four icons idle on a big pull.
local function defaultRoles(...)
    local db = { rolePlan = {} }
    MFD.Roles.EnsurePlan(db)
    return MFD.Roles.Resolve(db.rolePlan, roster(...))
end

local function killCandidates(count)
    local list = {}
    for i = 1, count do
        list[i] = { key = "100:" .. string.char(64 + i), npcID = 100, name = "Trash" }
    end
    return list
end

T.Case("Reuse: off by default, a fifth kill target stays unmarked", function()
    local out = MFD.Allocator.Compute(killCandidates(5),
        { [100] = { npcID = 100, intent = "KILL", rank = 10 } },
        defaultRoles("Thok", "WARRIOR"), nil, false)
    T.Eq(out.byKey["100:E"], nil, "no spare icons handed out")
end)

T.Case("Reuse: on, spare crowd control icons go to kill overflow", function()
    local out = MFD.Allocator.Compute(killCandidates(8),
        { [100] = { npcID = 100, intent = "KILL", rank = 10 } },
        defaultRoles("Thok", "WARRIOR"), nil, true)
    local placed = 0
    for _ in pairs(out.byKey) do placed = placed + 1 end
    T.Eq(placed, 8, "all eight icons used when nothing needs the cc ones")
end)

-- The property that matters. Reuse must never take an icon a crowd control
-- mob is going to need, however low that mob's priority is.
T.Case("Reuse: a sheep mob still gets Moon even when kill targets outrank it", function()
    local roles = defaultRoles("Grimmtusk", "MAGE")
    local candidates = killCandidates(6)
    candidates[7] = { key = "200:Z", npcID = 200, name = "Sheepable" }

    local out = MFD.Allocator.Compute(candidates, {
        [100] = { npcID = 100, intent = "KILL", rank = 10 },
        [200] = { npcID = 200, intent = "SHEEP", rank = 99 },
    }, roles, nil, true)

    T.Eq(out.byKey["200:Z"], 5, "the sheep target holds Moon despite the worst rank")
end)

T.Case("Reuse: with no mage present the sheep icons are free for kills", function()
    local roles = defaultRoles("Thok", "WARRIOR")
    local candidates = killCandidates(5)
    candidates[6] = { key = "200:Z", npcID = 200, name = "Sheepable" }

    local out = MFD.Allocator.Compute(candidates, {
        [100] = { npcID = 100, intent = "KILL", rank = 10 },
        [200] = { npcID = 200, intent = "SHEEP", rank = 20 },
    }, roles, nil, true)

    local placed = 0
    for _ in pairs(out.byKey) do placed = placed + 1 end
    T.Eq(placed, 6, "nobody can sheep, so every mob gets an icon")
end)

T.Case("Reuse: reused assignments are reported as kills with no owner", function()
    local out = MFD.Allocator.Compute(killCandidates(5),
        { [100] = { npcID = 100, intent = "KILL", rank = 10 } },
        defaultRoles("Grimmtusk", "MAGE"), nil, true)

    for _, a in ipairs(out.list) do
        if a.key == "100:E" then
            T.Eq(a.intent, "KILL", "a borrowed icon still means kill this")
            T.Eq(a.owner, nil, "and carries no crowd control owner")
        end
    end
end)

T.Case("Reuse: maxCount is still respected", function()
    local out = MFD.Allocator.Compute(killCandidates(8),
        { [100] = { npcID = 100, intent = "KILL", rank = 10, maxCount = 2 } },
        defaultRoles("Thok", "WARRIOR"), nil, true)
    local placed = 0
    for _ in pairs(out.byKey) do placed = placed + 1 end
    T.Eq(placed, 2, "the cap wins over filling icons")
end)

T.Case("Reuse: is deterministic, so two clients agree", function()
    local a = MFD.Allocator.Compute(killCandidates(8),
        { [100] = { npcID = 100, intent = "KILL", rank = 10 } },
        defaultRoles("Thok", "WARRIOR"), nil, true).byKey
    local b = MFD.Allocator.Compute(killCandidates(8),
        { [100] = { npcID = 100, intent = "KILL", rank = 10 } },
        defaultRoles("Thok", "WARRIOR"), nil, true).byKey
    for key, icon in pairs(a) do
        T.Eq(b[key], icon, "same icon for " .. key)
    end
end)

-- A crowd control mob nobody saw before the pull. The icon it needs may
-- already be lent out to a kill target, so it has to be taken back and
-- shouted about.
T.Case("Unmet: a sheep mob with no icon is reported, a kill mob is not", function()
    local candidates = {
        { key = "100:A", npcID = 100, name = "Trash" },
        { key = "200:B", npcID = 200, name = "Sheepable" },
    }
    local rules = {
        [100] = { npcID = 100, intent = "KILL", rank = 10 },
        [200] = { npcID = 200, intent = "SHEEP", rank = 20 },
    }
    local unmet = MFD.Allocator.UnmetCrowdControl(candidates, rules, {})
    T.Eq(#unmet, 1, "only the crowd control one")
    T.Eq(unmet[1].key, "200:B", "the sheep target")
    T.Eq(unmet[1].intent, "SHEEP", "carrying its job")
end)

T.Case("Unmet: a mob that already has its icon is not reported", function()
    local candidates = { { key = "200:B", npcID = 200, name = "Sheepable" } }
    local rules = { [200] = { npcID = 200, intent = "SHEEP", rank = 20 } }
    T.Eq(#MFD.Allocator.UnmetCrowdControl(candidates, rules, { ["200:B"] = 5 }), 0, "satisfied")
end)

T.Case("Unmet: a mob with no rule at all is not reported", function()
    local candidates = { { key = "999:C", npcID = 999, name = "Unruled" } }
    T.Eq(#MFD.Allocator.UnmetCrowdControl(candidates, {}, {}), 0, "nothing was asked for")
end)

T.Case("Release: borrowed locks are given up only when crowd control needs them", function()
    local locked = { ["100:A"] = 8, ["100:E"] = 5 }
    local borrowed = { ["100:E"] = true }

    T.Eq(#MFD.Marker.ReleaseBorrowed(locked, borrowed, 0), 0, "nothing unmet, nothing released")

    local released = MFD.Marker.ReleaseBorrowed(locked, borrowed, 1)
    T.Eq(#released, 1, "one released")
    T.Eq(released[1], "100:E", "the borrowed one, not the real assignment")
end)

T.Case("Release: never gives up more locks than crowd control actually needs", function()
    local locked = { ["1:A"] = 1, ["2:B"] = 3, ["3:C"] = 4 }
    local borrowed = { ["1:A"] = true, ["2:B"] = true, ["3:C"] = true }
    T.Eq(#MFD.Marker.ReleaseBorrowed(locked, borrowed, 2), 2, "two needed, two released")
end)

T.Case("Release: is deterministic in which borrowed lock goes first", function()
    local locked = { ["3:C"] = 1, ["1:A"] = 3, ["2:B"] = 4 }
    local borrowed = { ["3:C"] = true, ["1:A"] = true, ["2:B"] = true }
    T.Eq(MFD.Marker.ReleaseBorrowed(locked, borrowed, 1)[1], "1:A", "lowest key first")
end)

T.Case("Alert: the raid warning names the job, the icon, the mob and the owner", function()
    T.Eq(MFD.Announce.FormatLateAlert(
        { icon = 5, intent = "SHEEP", owner = "Grimmtusk" }, "Illidari Nightlord"),
        "SHEEP Moon: Illidari Nightlord - Grimmtusk", "raid warning text")
end)

T.Case("Alert: an unowned job still warns, naming nobody rather than nil", function()
    T.Eq(MFD.Announce.FormatLateAlert({ icon = 4, intent = "BANISH" }, "Illidari Defiler"),
        "BANISH Triangle: Illidari Defiler - unassigned", "still worth shouting")
end)

T.Case("Alert: the whisper tells one person exactly what to do", function()
    T.Eq(MFD.Announce.FormatLateWhisper(
        { icon = 5, intent = "SHEEP", owner = "Grimmtusk" }, "Illidari Nightlord"),
        "Sheep the Moon now: Illidari Nightlord", "whisper text")
end)

T.Case("Tanks: a typed list accepts commas, newlines and stray spaces", function()
    local names = MFD.Tanks.ParseList("Dezedin, Moophie\n  Grimmtusk ,,\nThok")
    T.Eq(#names, 4, "four names")
    T.Eq(names[1], "Dezedin", "trimmed")
    T.Eq(names[2], "Moophie", "comma separated")
    T.Eq(names[3], "Grimmtusk", "newline separated, empty entries skipped")
    T.Eq(names[4], "Thok", "last")
end)

T.Case("Tanks: an empty list is empty, not a list containing nothing", function()
    T.Eq(#MFD.Tanks.ParseList(""), 0, "empty string")
    T.Eq(#MFD.Tanks.ParseList("  ,\n , "), 0, "only separators")
    T.Eq(#MFD.Tanks.ParseList(nil), 0, "nil")
end)

T.Case("Tanks: the raid's own main tank assignment counts", function()
    T.Eq(MFD.Tanks.IsTank("Dezedin", { Dezedin = true }, {}), true, "assigned in the raid frame")
    T.Eq(MFD.Tanks.IsTank("Someone", { Dezedin = true }, {}), false, "not a tank")
end)

T.Case("Tanks: a manually typed name counts even with no raid assignment", function()
    T.Eq(MFD.Tanks.IsTank("Moophie", {}, { "Moophie" }), true, "typed list")
    T.Eq(MFD.Tanks.IsTank("moophie", {}, { "Moophie" }), true, "case insensitive")
end)

T.Case("Tanks: with no tanks known at all, nobody is a tank", function()
    T.Eq(MFD.Tanks.IsTank("Dezedin", {}, {}), false, "silence rather than announcing everyone")
end)

T.Case("Death: the same death is announced once, not once per combat log line", function()
    local announced = {}
    T.Eq(MFD.Tanks.ShouldAnnounce("Dezedin", announced, 100, 10), true, "first")
    T.Eq(MFD.Tanks.ShouldAnnounce("Dezedin", announced, 101, 10), false, "duplicate suppressed")
end)

T.Case("Death: a later death of the same tank announces again", function()
    local announced = {}
    MFD.Tanks.ShouldAnnounce("Dezedin", announced, 100, 10)
    T.Eq(MFD.Tanks.ShouldAnnounce("Dezedin", announced, 111, 10), true, "died again after a rez")
end)

T.Case("Death: two different tanks each get announced", function()
    local announced = {}
    T.Eq(MFD.Tanks.ShouldAnnounce("Dezedin", announced, 100, 10), true, "first tank")
    T.Eq(MFD.Tanks.ShouldAnnounce("Moophie", announced, 100, 10), true, "second tank, same instant")
end)

T.Case("Death: the message is exactly what a raid leader would type", function()
    T.Eq(MFD.Tanks.FormatDeath("Dezedin"), "Dezedin has died", "wording")
end)

-- Circle is the icon of last resort: spare sheep and banish icons should be
-- spent on kill targets before it, not after.
T.Case("LastResort: the default plan marks Circle as last resort", function()
    T.Eq(MFD.Roles.DEFAULT_PLAN[2].isLastResort, true, "circle")
    T.Eq(MFD.Roles.DEFAULT_PLAN[8].isLastResort, nil, "skull is not")
end)

T.Case("LastResort: with reuse on, spare cc icons are spent before Circle", function()
    local out = MFD.Allocator.Compute(killCandidates(4),
        { [100] = { npcID = 100, intent = "KILL", rank = 10 } },
        defaultRoles("Thok", "WARRIOR"), nil, true)

    T.Eq(out.byKey["100:A"], 8, "skull")
    T.Eq(out.byKey["100:B"], 7, "cross")
    T.Eq(out.byKey["100:C"], 6, "square")
    T.Eq(out.byKey["100:D"], 5, "then Moon, the first spare, not Circle")
end)

T.Case("LastResort: Circle is still used, just last of everything", function()
    local out = MFD.Allocator.Compute(killCandidates(8),
        { [100] = { npcID = 100, intent = "KILL", rank = 10 } },
        defaultRoles("Thok", "WARRIOR"), nil, true)
    T.Eq(out.byKey["100:H"], 2, "the eighth and final kill target gets Circle")
end)

T.Case("LastResort: spare icons come out in role order, best job first", function()
    local out = MFD.Allocator.Compute(killCandidates(7),
        { [100] = { npcID = 100, intent = "KILL", rank = 10 } },
        defaultRoles("Thok", "WARRIOR"), nil, true)
    -- Role one before role two, then the traditional marking order within a
    -- rank: moon, triangle, diamond, star.
    T.Eq(out.byKey["100:D"], 5, "Moon, sheep role one")
    T.Eq(out.byKey["100:E"], 4, "Triangle, banish role one")
    T.Eq(out.byKey["100:F"], 3, "Diamond, banish role two")
    T.Eq(out.byKey["100:G"], 1, "Star, sheep role two")
end)

-- With reuse off there are no borrowed icons to come first, so the flag has
-- nothing to mean and Circle goes back to being the fourth kill icon.
T.Case("LastResort: with reuse off Circle is simply kill four again", function()
    local out = MFD.Allocator.Compute(killCandidates(4),
        { [100] = { npcID = 100, intent = "KILL", rank = 10 } },
        defaultRoles("Thok", "WARRIOR"), nil, false)
    T.Eq(out.byKey["100:D"], 2, "circle, as the plan says")
end)

T.Case("LastResort: a sheep mob still beats a kill target to Moon", function()
    local roles = defaultRoles("Grimmtusk", "MAGE")
    local candidates = killCandidates(3)
    candidates[4] = { key = "200:Z", npcID = 200, name = "Sheepable" }

    local out = MFD.Allocator.Compute(candidates, {
        [100] = { npcID = 100, intent = "KILL", rank = 10 },
        [200] = { npcID = 200, intent = "SHEEP", rank = 99 },
    }, roles, nil, true)

    T.Eq(out.byKey["200:Z"], 5, "Moon belongs to the sheep target")
    T.Eq(out.byKey["100:C"], 6, "and the third kill still has Square")
end)

-- Dragging a rule to an arbitrary position, for when the arrows would take ten
-- clicks. Same renumbering as Reorder, different way of naming the target.
T.Case("MoveTo: dragging a rule down lands it at the target position", function()
    local list = { { npcID = 1, rank = 10 }, { npcID = 2, rank = 20 }, { npcID = 3, rank = 30 }, { npcID = 4, rank = 40 } }
    MFD.Rules.MoveTo(list, 1, 3)
    T.Eq(list[1].npcID, 2, "the rest shuffle up")
    T.Eq(list[2].npcID, 3, "second")
    T.Eq(list[3].npcID, 1, "the dragged rule is third now")
    T.Eq(list[4].npcID, 4, "and the tail is undisturbed")
end)

T.Case("MoveTo: dragging a rule up lands it at the target position", function()
    local list = { { npcID = 1, rank = 10 }, { npcID = 2, rank = 20 }, { npcID = 3, rank = 30 }, { npcID = 4, rank = 40 } }
    MFD.Rules.MoveTo(list, 4, 1)
    T.Eq(list[1].npcID, 4, "dragged to the top")
    T.Eq(list[2].npcID, 1, "everything else moves down one")
    T.Eq(list[4].npcID, 3, "last")
end)

T.Case("MoveTo: ranks are respaced so priority still reads cleanly", function()
    local list = { { npcID = 1, rank = 10 }, { npcID = 2, rank = 20 }, { npcID = 3, rank = 30 } }
    MFD.Rules.MoveTo(list, 3, 1)
    T.Eq(list[1].rank, 10, "first")
    T.Eq(list[2].rank, 20, "second")
    T.Eq(list[3].rank, 30, "third")
end)

T.Case("MoveTo: dropping a rule on itself changes nothing", function()
    local list = { { npcID = 1, rank = 10 }, { npcID = 2, rank = 20 } }
    MFD.Rules.MoveTo(list, 2, 2)
    T.Eq(list[1].npcID, 1, "unchanged")
    T.Eq(list[2].npcID, 2, "unchanged")
end)

T.Case("MoveTo: an out of range drop is ignored rather than corrupting the list", function()
    local list = { { npcID = 1, rank = 10 }, { npcID = 2, rank = 20 } }
    MFD.Rules.MoveTo(list, 1, 99)
    MFD.Rules.MoveTo(list, 0, 1)
    MFD.Rules.MoveTo(list, 1, 0)
    T.Eq(#list, 2, "still two rules")
    T.Eq(list[1].npcID, 1, "in the original order")
end)

T.Case("JSON: encodes the scalar types", function()
    T.Eq(MFD.JSON.Encode(42), "42", "number")
    T.Eq(MFD.JSON.Encode(true), "true", "true")
    T.Eq(MFD.JSON.Encode(false), "false", "false")
    T.Eq(MFD.JSON.Encode("hi"), '"hi"', "string")
end)

T.Case("JSON: escapes what would otherwise break the string", function()
    T.Eq(MFD.JSON.Encode('a"b'), '"a\\"b"', "quote")
    T.Eq(MFD.JSON.Encode("a\\b"), '"a\\\\b"', "backslash")
    T.Eq(MFD.JSON.Encode("a\nb"), '"a\\nb"', "newline")
end)

T.Case("JSON: an empty table encodes as an object, not an array", function()
    T.Eq(MFD.JSON.Encode({}), "{}", "ambiguous, and object is the safer read")
end)

T.Case("JSON: arrays and objects round-trip", function()
    local original = {
        addon = "MarkedForDeath",
        formatVersion = 1,
        rules = { BLACKTEMPLE = { { npc = 22890, job = "SHEEP", priority = 10 } } },
    }
    local back = MFD.JSON.Decode(MFD.JSON.Encode(original))
    T.Eq(back.addon, "MarkedForDeath", "string field")
    T.Eq(back.formatVersion, 1, "number field")
    T.Eq(back.rules.BLACKTEMPLE[1].npc, 22890, "nested array of objects")
    T.Eq(back.rules.BLACKTEMPLE[1].job, "SHEEP", "job")
end)

T.Case("JSON: object keys come out in a stable order", function()
    local text = MFD.JSON.Encode({ zebra = 1, apple = 2, mango = 3 })
    T.Eq(text:find("apple") < text:find("mango"), true, "alphabetical")
    T.Eq(text:find("mango") < text:find("zebra"), true, "so two exports of one config are identical")
end)

T.Case("JSON: decoding rubbish returns nil and a reason", function()
    for _, bad in ipairs({ "", "{", "{\"a\":}", "[1,]", "nonsense", "{\"a\" 1}" }) do
        local value, err = MFD.JSON.Decode(bad)
        T.Eq(value, nil, "rejected: " .. bad)
        T.Eq(type(err), "string", "with a reason: " .. bad)
    end
end)

T.Case("JSON: whitespace between tokens is fine", function()
    local v = MFD.JSON.Decode('  {  "a" : [ 1 , 2 ]  ,  "b" : "x"  }  ')
    T.Eq(v.a[2], 2, "array element")
    T.Eq(v.b, "x", "string value")
end)

T.Case("Share: exporting produces a document with the addon and format stamped", function()
    local doc = MFD.JSON.Decode(MFD.Rules.ToJSON(
        { BLACKTEMPLE = { { npcID = 22890, name = "Illidari Nightlord", intent = "SHEEP", rank = 10 } } },
        { note = "BT trash" }))
    T.Eq(doc.addon, "MarkedForDeath", "so an import can refuse someone else's file")
    T.Eq(doc.formatVersion, 1, "version")
    T.Eq(doc.note, "BT trash", "the note travels with it")
    T.Eq(doc.rules.BLACKTEMPLE[1].name, "Illidari Nightlord", "name")
    T.Eq(doc.rules.BLACKTEMPLE[1].job, "SHEEP", "intent is called job in the file")
    T.Eq(doc.rules.BLACKTEMPLE[1].priority, 10, "rank is called priority in the file")
end)

T.Case("Share: a document round-trips back into rules", function()
    local original = { HYJAL = { { npcID = 17907, name = "Frost Wyrm", intent = "KILL", rank = 20, fallback = "KILL" } } }
    local back = MFD.Rules.FromJSON(MFD.Rules.ToJSON(original, {}))
    T.Eq(back.HYJAL[1].npcID, 17907, "npc id")
    T.Eq(back.HYJAL[1].name, "Frost Wyrm", "name")
    T.Eq(back.HYJAL[1].intent, "KILL", "intent")
    T.Eq(back.HYJAL[1].rank, 20, "rank")
end)

T.Case("Share: importing someone else's file is refused, not half applied", function()
    local rules, err = MFD.Rules.FromJSON('{"addon":"SomethingElse","formatVersion":1,"rules":{}}')
    T.Eq(rules, nil, "refused")
    T.Eq(err, "that file is not a Marked For Death export", "and says why")
end)

T.Case("Share: a newer format version is refused rather than guessed at", function()
    local rules, err = MFD.Rules.FromJSON('{"addon":"MarkedForDeath","formatVersion":99,"rules":{}}')
    T.Eq(rules, nil, "refused")
    T.Eq(err, "that file was made by a newer version of the addon", "and says why")
end)

T.Case("Share: an unknown job fails the whole import", function()
    local rules, err = MFD.Rules.FromJSON(
        '{"addon":"MarkedForDeath","formatVersion":1,"rules":{"BT":[{"name":"A","job":"FROBNICATE","priority":10}]}}')
    T.Eq(rules, nil, "nothing imported")
    T.Eq(err, "BT: unknown job 'FROBNICATE'", "naming the zone and the job")
end)

T.Case("Share: a rule with neither a name nor an npc id is rejected", function()
    local rules, err = MFD.Rules.FromJSON(
        '{"addon":"MarkedForDeath","formatVersion":1,"rules":{"BT":[{"job":"KILL","priority":10}]}}')
    T.Eq(rules, nil, "rejected")
    T.Eq(type(err), "string", "with a reason")
end)

-- A patrol wandering off must not keep Skull away from the pack you are about
-- to pull. Present mobs outrank departed ones whatever the rules say.
T.Case("Patrol: a mob you can see beats a departed one to the icon", function()
    local roles = defaultRoles("Thok", "WARRIOR")
    local out = MFD.Allocator.Compute({
        { key = "100:PATROL", npcID = 100, name = "Patrol", isLost = true },
        { key = "200:STATIC", npcID = 200, name = "Static" },
    }, {
        -- The patrol even has the better rule; being gone still loses.
        [100] = { npcID = 100, intent = "KILL", rank = 10 },
        [200] = { npcID = 200, intent = "KILL", rank = 90 },
    }, roles, nil, false)

    T.Eq(out.byKey["200:STATIC"], 8, "the mob in front of you takes skull")
    T.Eq(out.byKey["100:PATROL"], 7, "the patrol drops to the next icon")
end)

T.Case("Patrol: a departed mob keeps its icon when nothing else wants it", function()
    local roles = defaultRoles("Thok", "WARRIOR")
    local out = MFD.Allocator.Compute({
        { key = "100:PATROL", npcID = 100, name = "Patrol", isLost = true },
    }, { [100] = { npcID = 100, intent = "KILL", rank = 10 } }, roles, nil, false)

    T.Eq(out.byKey["100:PATROL"], 8, "no churn from a nameplate that merely flickered")
end)

T.Case("Patrol: coming back into view puts it back in the running", function()
    local roles = defaultRoles("Thok", "WARRIOR")
    local out = MFD.Allocator.Compute({
        { key = "100:PATROL", npcID = 100, name = "Patrol" },
        { key = "200:STATIC", npcID = 200, name = "Static" },
    }, {
        [100] = { npcID = 100, intent = "KILL", rank = 10 },
        [200] = { npcID = 200, intent = "KILL", rank = 90 },
    }, roles, nil, false)

    T.Eq(out.byKey["100:PATROL"], 8, "present again, so its better rule wins again")
    T.Eq(out.byKey["200:STATIC"], 7, "and the static mob steps down")
end)

T.Case("Patrol: among departed mobs the usual priority still applies", function()
    local roles = defaultRoles("Thok", "WARRIOR")
    local out = MFD.Allocator.Compute({
        { key = "100:A", npcID = 100, name = "A", isLost = true },
        { key = "200:B", npcID = 200, name = "B", isLost = true },
    }, {
        [100] = { npcID = 100, intent = "KILL", rank = 90 },
        [200] = { npcID = 200, intent = "KILL", rank = 10 },
    }, roles, nil, false)

    T.Eq(out.byKey["200:B"], 8, "better rule first")
    T.Eq(out.byKey["100:A"], 7, "then the other")
end)

T.Case("Candidates: ToList reports whether a mob has gone out of view", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 500)
    MFD.Candidates.Observe(set, "200:BBB", 200, "nameplate2", 500)
    MFD.Candidates.Lose(set, "200:BBB", 501)

    local byKey = {}
    for _, c in ipairs(MFD.Candidates.ToList(set)) do
        byKey[c.key] = c
    end

    T.Eq(byKey["100:AAA"].isLost, nil, "still visible")
    T.Eq(byKey["200:BBB"].isLost, true, "nameplate gone")
end)

T.Case("Conflicts: a detected automarker is named with the exact fix", function()
    local lines = MFD.Conflicts.Format({
        { label = "Method Raid Tools", what = "its automarker is on", fix = "/mrt, Marks tab, untick Enable" },
    })
    T.Eq(#lines, 1, "one conflict")
    T.Eq(lines[1], "Method Raid Tools: its automarker is on. Fix: /mrt, Marks tab, untick Enable",
        "names the addon, the problem and the fix")
end)

T.Case("Conflicts: nothing detected produces no lines at all", function()
    T.Eq(#MFD.Conflicts.Format({}), 0, "silence when there is nothing to say")
end)

T.Case("Conflicts: several are listed in the order given", function()
    local lines = MFD.Conflicts.Format({
        { label = "A", what = "x", fix = "do y" },
        { label = "B", what = "p", fix = "do q" },
    })
    T.Eq(#lines, 2, "both")
    T.Eq(lines[1], "A: x. Fix: do y", "first")
    T.Eq(lines[2], "B: p. Fix: do q", "second")
end)

T.Case("Conflicts: Evaluate only reports the ones whose test says so", function()
    local found = MFD.Conflicts.Evaluate({
        { label = "On", what = "w", fix = "f", isActive = function() return true end },
        { label = "Off", what = "w", fix = "f", isActive = function() return false end },
        { label = "Broken", what = "w", fix = "f", isActive = function() error("boom") end },
    })
    T.Eq(#found, 1, "only the active one")
    T.Eq(found[1].label, "On", "and it is the right one")
end)

-- Having no blessing at all is worth calling out. Which blessing each class
-- should carry is still the raid leader's business, so only the absence of
-- every one of them counts.
T.Case("Blessing: someone with none is reported when a paladin is present", function()
    local state = MFD.RaidCheck.Classify({})
    local missing = MFD.RaidCheck.Missing(state, { BLESSING = true, BLESSING_COUNT = 1 }, {})
    T.Eq(#missing, 1, "one thing missing")
    T.Eq(missing[1].column, "BLESSING", "the blessing")
    T.Eq(missing[1].label, "Blessing", "labelled plainly")
end)

T.Case("Blessing: any blessing at all satisfies it, and none is judged", function()
    T.Eq(#MFD.RaidCheck.Missing(MFD.RaidCheck.Classify({ "Blessing of Salvation" }),
        { BLESSING = true, BLESSING_COUNT = 1 }, {}), 0, "salvation counts")
    T.Eq(#MFD.RaidCheck.Missing(MFD.RaidCheck.Classify({ "Greater Blessing of Kings" }),
        { BLESSING = true, BLESSING_COUNT = 1 }, {}), 0,
        "so does kings, and the addon does not say which they should have")
end)

T.Case("Blessing: with no paladin present it is never reported", function()
    local state = MFD.RaidCheck.Classify({})
    T.Eq(#MFD.RaidCheck.Missing(state, { BLESSING = false, BLESSING_COUNT = 0 }, {}), 0,
        "nobody can cast it, so it is an absence rather than a failure")
end)

T.Case("Blessing: a paladin in the group makes it providable", function()
    local withPaladin = MFD.RaidCheck.Providers(roster("Dezedin", "PALADIN", "Thok", "WARRIOR"))
    T.Eq(withPaladin.BLESSING, true, "paladin present")
    T.Eq(withPaladin.BLESSING_COUNT, 1, "and one blessing expected")

    local without = MFD.RaidCheck.Providers(roster("Thok", "WARRIOR"))
    T.Eq(without.BLESSING, false, "no paladin")
end)

T.Case("Blessing: it is listed with the raid buffs, before consumables", function()
    local state = MFD.RaidCheck.Classify({})
    local missing = MFD.RaidCheck.Missing(state, { AI = true, BLESSING = true, BLESSING_COUNT = 1 }, { FOOD = true })
    T.Eq(missing[1].column, "AI", "raid buffs first")
    T.Eq(missing[2].column, "BLESSING", "then the blessing")
    T.Eq(missing[3].column, "FOOD", "then consumables")
end)

-- GetTalentTabInfo has two shapes across client builds. Reading the wrong one
-- put a description string where the points number belonged, and comparing it
-- threw inside GatherSelf, which aborted the entire raid check scan and left
-- the grid reading "nobody in the group".
T.Case("TalentTab: reads the five-return shape, id first", function()
    local name, points = MFD.RaidCheck.ParseTalentTab(382, "Holy", "", "icon", 41)
    T.Eq(name, "Holy", "name is the second return")
    T.Eq(points, 41, "points are the fifth")
end)

T.Case("TalentTab: reads the three-return shape, name first", function()
    local name, points = MFD.RaidCheck.ParseTalentTab("Fire", "icon", 41)
    T.Eq(name, "Fire", "name is the first return")
    T.Eq(points, 41, "points are the third")
end)

T.Case("TalentTab: a missing points value reads as zero, never as a string", function()
    local _, points = MFD.RaidCheck.ParseTalentTab(382, "Holy", "", "icon", "")
    T.Eq(points, 0, "the description string must never reach a comparison")
end)

T.Case("TalentTab: an unrecognisable shape yields nothing rather than throwing", function()
    T.Eq(MFD.RaidCheck.ParseTalentTab(nil), nil, "nil")
    T.Eq(MFD.RaidCheck.ParseTalentTab(1, 2, 3), nil, "no name anywhere")
    T.Eq(MFD.RaidCheck.ParseTalentTab(382, "", "", "", 0), nil, "empty name")
end)

T.Case("TalentTab: SpecFromTabs still picks the tab with the most points", function()
    local tabs = {}
    for _, raw in ipairs({ { 381, "Arcane", "", "i", 0 }, { 382, "Fire", "", "i", 41 }, { 383, "Frost", "", "i", 20 } }) do
        local name, points = MFD.RaidCheck.ParseTalentTab(raw[1], raw[2], raw[3], raw[4], raw[5])
        tabs[#tabs + 1] = { name = name, points = points }
    end
    T.Eq(MFD.RaidCheck.SpecFromTabs(tabs), "Fire", "fire")
end)

-- How many blessings somebody should have is not fixed: it is however many
-- paladins are in the raid, one each.
T.Case("Blessings: the expected count is the number of paladins present", function()
    T.Eq(MFD.RaidCheck.Providers(roster("Thok", "WARRIOR")).BLESSING_COUNT, 0, "none")
    T.Eq(MFD.RaidCheck.Providers(roster("A", "PALADIN")).BLESSING_COUNT, 1, "one paladin")
    T.Eq(MFD.RaidCheck.Providers(roster("A", "PALADIN", "B", "PALADIN", "C", "PALADIN")).BLESSING_COUNT, 3, "three")
end)

T.Case("Blessings: holding fewer than the paladin count is reported", function()
    local state = MFD.RaidCheck.Classify({ "Blessing of Kings" })
    local missing = MFD.RaidCheck.Missing(state, { BLESSING = true, BLESSING_COUNT = 3 }, {})
    T.Eq(#missing, 1, "short two")
    T.Eq(missing[1].column, "BLESSING", "the blessing")
    T.Eq(missing[1].have, 1, "carrying one")
    T.Eq(missing[1].expected, 3, "out of three")
end)

T.Case("Blessings: holding one from each paladin is enough", function()
    local state = MFD.RaidCheck.Classify({ "Blessing of Kings", "Greater Blessing of Salvation" })
    T.Eq(#MFD.RaidCheck.Missing(state, { BLESSING = true, BLESSING_COUNT = 2 }, {}), 0, "two of two")
end)

T.Case("Blessings: more than expected is never a complaint", function()
    local state = MFD.RaidCheck.Classify({ "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom" })
    T.Eq(#MFD.RaidCheck.Missing(state, { BLESSING = true, BLESSING_COUNT = 1 }, {}), 0, "three when one was expected")
end)

T.Case("Blessings: the callout label stays groupable, the count rides alongside", function()
    local state = MFD.RaidCheck.Classify({})
    local missing = MFD.RaidCheck.Missing(state, { BLESSING = true, BLESSING_COUNT = 2 }, {})
    T.Eq(missing[1].label, "Blessing", "so everyone short one groups onto a single callout line")
end)

T.Case("Blessings: no paladin means it is never mentioned", function()
    local state = MFD.RaidCheck.Classify({})
    T.Eq(#MFD.RaidCheck.Missing(state, { BLESSING = false, BLESSING_COUNT = 0 }, {}), 0, "nobody can cast one")
end)

T.Case("Blessings: which ones somebody holds is still listed, sorted", function()
    local state = MFD.RaidCheck.Classify({ "Greater Blessing of Salvation", "Blessing of Kings" })
    T.Eq(state.blessings[1], "Kings", "first")
    T.Eq(state.blessings[2], "Salv", "second, so the grid can show exactly which")
end)

-- Weapon enchant is gone: it could only ever be read from the player's own
-- client, so it was the one column that needed the addon on both ends.
T.Case("Weapon: is no longer a consumable the check knows about", function()
    for _, column in ipairs(MFD.RaidCheck.CONSUMABLE_ORDER) do
        if column == "WEAPON" then
            error("WEAPON is still in the consumable order")
        end
    end
    T.Eq(MFD.RaidCheck.CONSUMABLE_LABELS.WEAPON, nil, "and has no label")
end)

T.Case("Weapon: asking for it explicitly no longer reports anything", function()
    local state = MFD.RaidCheck.Classify({})
    T.Eq(#MFD.RaidCheck.Missing(state, {}, { WEAPON = true }), 0, "a stale setting cannot resurrect it")
end)

-- A flask fills both elixir slots, so it is one requirement with two ways to
-- meet it: a flask, or a battle elixir and a guardian elixir together.
local function elixirState(...)
    return MFD.RaidCheck.Classify({ ... })
end

T.Case("Elixirs: a flask on its own satisfies it", function()
    T.Eq(#MFD.RaidCheck.Missing(elixirState("Flask of Relentless Assault"), {}, { ELIXIRS = true }), 0, "flask")
end)

T.Case("Elixirs: both elixirs together satisfy it", function()
    T.Eq(#MFD.RaidCheck.Missing(
        elixirState("Elixir of Major Agility", "Elixir of Major Fortitude"), {}, { ELIXIRS = true }), 0, "one of each")
end)

T.Case("Elixirs: only one of the two is not enough", function()
    T.Eq(#MFD.RaidCheck.Missing(elixirState("Elixir of Major Agility"), {}, { ELIXIRS = true }), 1, "battle only")
    T.Eq(#MFD.RaidCheck.Missing(elixirState("Elixir of Major Fortitude"), {}, { ELIXIRS = true }), 1, "guardian only")
end)

T.Case("Elixirs: nothing at all is reported", function()
    local missing = MFD.RaidCheck.Missing(elixirState(), {}, { ELIXIRS = true })
    T.Eq(#missing, 1, "one thing missing")
    T.Eq(missing[1].column, "ELIXIRS", "the combined requirement")
    T.Eq(missing[1].label, "Flask or elixirs", "named so the callout reads plainly")
end)

T.Case("Elixirs: the three old separate checks are gone", function()
    for _, column in ipairs(MFD.RaidCheck.CONSUMABLE_ORDER) do
        if column == "FLASK" or column == "BATTLE" or column == "GUARDIAN" then
            error(column .. " is still checked on its own")
        end
    end
end)

T.Case("Elixirs: not expected means never reported", function()
    T.Eq(#MFD.RaidCheck.Missing(elixirState(), {}, {}), 0, "the raid does not ask for them")
end)

-- A person who marks a mob has already decided that mob. The addon's job from
-- there is to work around them, not to win an argument with a tank.
local function detect(actual, placed, manual, wroteAt, now)
    return MFD.Marker.DetectManualMarks(actual, placed or {}, manual or {}, wroteAt or {}, now or 100, 1.0)
end

T.Case("Manual: an icon we never placed belongs to whoever placed it", function()
    local result = detect({ ["1-A"] = 8 })
    T.Eq(result.added["1-A"], 8, "their skull is now a lock")
end)

T.Case("Manual: the icon we placed ourselves is not somebody else's", function()
    local result = detect({ ["1-A"] = 8 }, { ["1-A"] = 8 })
    T.Eq(result.added["1-A"], nil, "our own work")
end)

T.Case("Manual: a mob changed out from under us is theirs now", function()
    local result = detect({ ["1-A"] = 7 }, { ["1-A"] = 8 })
    T.Eq(result.added["1-A"], 7, "we wrote skull, cross is on it, somebody moved it")
end)

T.Case("Manual: an unmarked mob is nobody's doing", function()
    local result = detect({ ["1-A"] = 0 }, { ["1-A"] = 8 })
    T.Eq(result.added["1-A"], nil, "cleared, not claimed")
    T.Eq(#result.removed, 0, "and it was never a manual lock to release")
end)

T.Case("Manual: our own write is not read back as theirs while it settles", function()
    -- SetRaidTarget is not instant. Reading the previous icon back a tick later
    -- and calling it a person's doing would lock mobs to icons nobody chose.
    local result = detect({ ["1-A"] = 7 }, { ["1-A"] = 8 }, {}, { ["1-A"] = 99.5 }, 100)
    T.Eq(result.added["1-A"], nil, "inside the settle window")

    local later = detect({ ["1-A"] = 7 }, { ["1-A"] = 8 }, {}, { ["1-A"] = 98 }, 100)
    T.Eq(later.added["1-A"], 7, "once it has had time to land")
end)

T.Case("Manual: a lock already held is not re-reported every tick", function()
    local result = detect({ ["1-A"] = 8 }, {}, { ["1-A"] = 8 })
    T.Eq(result.added["1-A"], nil, "already ours to respect")
end)

T.Case("Manual: taking the mark off hands the mob back", function()
    local result = detect({ ["1-A"] = 0 }, {}, { ["1-A"] = 8 })
    T.Eq(result.removed[1], "1-A", "released")
end)

local function manualRoles()
    return MFD.Roles.Resolve({
        [8] = { intent = "KILL", ordinal = 1 },
        [7] = { intent = "KILL", ordinal = 2 },
        [5] = { intent = "SHEEP", ordinal = 1, pin = "Grimmtusk" },
    }, { { name = "Grimmtusk", class = "MAGE" } })
end

T.Case("Manual: a hand-placed icon takes the mob out of the running", function()
    local result = MFD.Allocator.Compute(
        { { key = "1-A", npcID = 1 }, { key = "1-B", npcID = 1 } },
        { [1] = { intent = "KILL", rank = 1 } },
        manualRoles(), { ["1-B"] = 8 }, false, { ["1-B"] = true })

    T.Eq(result.byKey["1-B"], 8, "their skull stays where they put it")
    T.Eq(result.byKey["1-A"], 7, "and the mob that would have had skull moves down")
end)

T.Case("Manual: an icon with no role in the plan still holds its mob", function()
    -- Circle is not in this plan at all. Dropping the lock would leave the mob
    -- eligible, the allocator would want cross on it, and the addon would spend
    -- the pull overwriting the icon somebody deliberately placed.
    local result = MFD.Allocator.Compute(
        { { key = "1-A", npcID = 1 } },
        { [1] = { intent = "KILL", rank = 1 } },
        manualRoles(), { ["1-A"] = 2 }, false, { ["1-A"] = true })

    T.Eq(result.byKey["1-A"], 2, "circle held")
    T.Eq(result.list[1].intent, "MANUAL", "named for what it is")
    T.Eq(MFD.Announce.Format(result.list), "Circle>manual", "and read plainly at the raid")
end)

T.Case("Manual: the icon's role decides the job, not the mob's rule", function()
    -- Moon on something the rules call a kill is a sheep call. Announcing it as
    -- a kill would send the wrong job to the wrong person.
    local result = MFD.Allocator.Compute(
        { { key = "1-A", npcID = 1 } },
        { [1] = { intent = "KILL", rank = 1 } },
        manualRoles(), { ["1-A"] = 5 }, false, { ["1-A"] = true })

    T.Eq(result.list[1].intent, "SHEEP", "the icon they reached for says sheep")
    T.Eq(result.list[1].owner, "Grimmtusk", "and it is his job")
end)

T.Case("Manual: a combat lock still reads the job from the mob's rule", function()
    -- Unchanged behaviour for locks the addon froze itself at the pull.
    local result = MFD.Allocator.Compute(
        { { key = "1-A", npcID = 1 } },
        { [1] = { intent = "KILL", rank = 1 } },
        manualRoles(), { ["1-A"] = 5 }, false, nil)

    T.Eq(result.list[1].intent, "KILL", "frozen as what it was allocated for")
end)

T.Case("Defense: a mark we placed and lost is still defended", function()
    -- The manual override is about foreign icons. An icon of ours wiped to
    -- nothing is the case the brake was written for, and it keeps that job.
    local defense = {}
    local diff = MFD.Marker.ComputeDiff(
        { ["1-A"] = 8 }, { ["1-A"] = 0 }, { ["1-A"] = 8 }, defense, 100, MFD.Marker.LIMITS)

    T.Eq(#diff.actions, 1, "re-applied")
    T.Eq(diff.actions[1].isDefense, true, "as a defense, so the brake counts it")
end)

-- Death announcements: which fight you are in, and whether it counts.
local E = MFD.Encounters

T.Case("Bosses: every encounter has a name, an instance and at least one id", function()
    T.Eq(#MFD.Data.Bosses > 0, true, "the table is not empty")
    for _, boss in ipairs(MFD.Data.Bosses) do
        T.Eq(type(boss.name), "string", "named")
        T.Eq(type(boss.instance), "string", "filed under a raid")
        T.Eq(#boss.ids > 0, true, boss.name .. " has no ids, so it could never be detected")
    end
end)

T.Case("Bosses: no npcID belongs to two encounters", function()
    local seen = {}
    for _, boss in ipairs(MFD.Data.Bosses) do
        for _, id in ipairs(boss.ids) do
            T.Eq(seen[id], nil, "id " .. id .. " is in both " .. tostring(seen[id]) .. " and " .. boss.name)
            seen[id] = boss.name
        end
    end
end)

T.Case("Bosses: every id is a mob the bundled table knows", function()
    -- The ids were resolved by name against Data_Mobs. If one drifts, this is
    -- the test that catches it rather than a boss silently never detecting.
    for _, boss in ipairs(MFD.Data.Bosses) do
        for _, id in ipairs(boss.ids) do
            local mob = MFD.Data.Mobs[id]
            T.Eq(mob ~= nil, true, boss.name .. " id " .. id .. " is not in the mob table")
            T.Eq(mob[2], boss.instance, boss.name .. " id " .. id .. " is filed under " .. tostring(mob[2]))
        end
    end
end)

T.Case("Encounters: a boss on screen is the fight you are in", function()
    local index = E.IndexByNpcID({ { name = "Supremus", instance = "BT", ids = { 22898 } } })
    T.Eq(E.Detect({ { key = "1-A", npcID = 22898 } }, index), "Supremus", "detected")
    T.Eq(E.Detect({ { key = "1-A", npcID = 99999 } }, index), nil, "trash is not a boss")
    T.Eq(E.Detect({}, index), nil, "nothing on screen")
end)

T.Case("Encounters: a boss whose nameplate is gone is not the fight you are in", function()
    local index = E.IndexByNpcID({ { name = "Supremus", instance = "BT", ids = { 22898 } } })
    T.Eq(E.Detect({ { key = "1-A", npcID = 22898, isLost = true } }, index), nil, "walked off")
end)

T.Case("Encounters: bosses group by raid in the order written", function()
    local groups = E.GroupByInstance(MFD.Data.Bosses)
    T.Eq(groups[1].instance, "KARAZHAN", "first raid first")
    T.Eq(groups[1].bosses[1].name, "Attumen the Huntsman", "and its first boss")
end)

local function gate(override, selected, encounter)
    return E.PassesBossGate(override, selected, encounter)
end

T.Case("Gate: trash never passes, whatever the override says", function()
    T.Eq(gate("AUTO", {}, nil), false, "auto")
    T.Eq(gate("ON", {}, nil), false, "even forced on")
    T.Eq(gate("OFF", {}, nil), false, "off")
end)

T.Case("Gate: on a boss, auto follows the ticks", function()
    T.Eq(gate("AUTO", { Supremus = true }, "Supremus"), true, "ticked")
    T.Eq(gate("AUTO", { Supremus = true }, "Mother Shahraz"), false, "not ticked")
end)

T.Case("Gate: the override ignores the ticks in both directions", function()
    T.Eq(gate("ON", {}, "Supremus"), true, "nothing ticked, still on")
    T.Eq(gate("OFF", { Supremus = true }, "Supremus"), false, "ticked, still off")
end)

T.Case("Gate: the override cycles through all three and back", function()
    T.Eq(E.NextOverride("AUTO"), "ON", "first press")
    T.Eq(E.NextOverride("ON"), "OFF", "second")
    T.Eq(E.NextOverride("OFF"), "AUTO", "third comes home")
end)

T.Case("Deaths: healer alerts are boss gated, tank alerts are not by default", function()
    local onTrash = nil

    T.Eq(E.ShouldAnnounce({ isEnabled = true, bossOnly = true, override = "AUTO", selected = {} }, onTrash),
        false, "healers say nothing on trash")
    T.Eq(E.ShouldAnnounce({ isEnabled = true, bossOnly = false, override = "AUTO", selected = {} }, onTrash),
        true, "tanks announce on trash, which is what they have always done")
end)

T.Case("Deaths: a tank alert held to the boss list obeys it", function()
    T.Eq(E.ShouldAnnounce({ isEnabled = true, bossOnly = true, override = "AUTO", selected = {} }, "Supremus"),
        false, "not ticked")
    T.Eq(E.ShouldAnnounce(
        { isEnabled = true, bossOnly = true, override = "AUTO", selected = { Supremus = true } }, "Supremus"),
        true, "ticked")
end)

T.Case("Deaths: switched off says nothing however the gate reads", function()
    T.Eq(E.ShouldAnnounce({ isEnabled = false, bossOnly = false, override = "ON", selected = {} }, "Supremus"),
        false, "off is off")
end)

local H = MFD.Healers

T.Case("Healers: a healing spec counts and a damage spec does not", function()
    local specs = { Kaylia = "Holy", Grimmtusk = "Frost", Thok = "Restoration", Vex = "Shadow" }
    T.Eq(H.IsHealer("Kaylia", specs, {}), true, "holy")
    T.Eq(H.IsHealer("Thok", specs, {}), true, "resto")
    T.Eq(H.IsHealer("Vex", specs, {}), false, "a shadow priest is not a healer")
    T.Eq(H.IsHealer("Grimmtusk", specs, {}), false, "nor is a mage")
end)

T.Case("Healers: an unknown spec is not guessed at", function()
    T.Eq(H.IsHealer("Nobody", {}, {}), false, "no spec, no claim")
end)

T.Case("Healers: a typed name counts without a spec, case insensitively", function()
    T.Eq(H.IsHealer("Kaylia", {}, { "kaylia" }), true, "typed")
end)

T.Case("Healers: the known list merges both sources and sorts, without duplicates", function()
    local known = H.Known({ Kaylia = "Holy", Vex = "Shadow", Thok = "Restoration" }, { "Kaylia", "Amara" })
    T.Eq(table.concat(known, ","), "Amara,Kaylia,Thok", "sorted, deduplicated, no shadow priest")
end)

-- The defense brake exists for one thing: an icon of ours being wiped by
-- something that will not stop. Everything else that moves an icon is either
-- our own decision or a person's, and counting those burns the budget on
-- fights that are not happening.
local function diffOne(desired, actual, placed)
    local defense = {}
    local result = MFD.Marker.ComputeDiff(desired, actual, placed, defense, 100, MFD.Marker.LIMITS)
    return result, defense
end

T.Case("Brake: changing our own mind is not a fight", function()
    -- The board holds exactly what we wrote. We simply want something else on
    -- it now, because a higher priority mob turned up.
    local result = diffOne({ ["1-A"] = 7 }, { ["1-A"] = 8 }, { ["1-A"] = 8 })
    T.Eq(#result.actions, 1, "re-marked")
    T.Eq(result.actions[1].isDefense, false, "not a defense")
end)

T.Case("Brake: an icon taken by the mob we now want to have it is not a fight", function()
    -- A tank marks B with Skull. The game strips Skull from A, and the
    -- allocator has already moved A down to Cross and given B the Skull. Both
    -- mobs are doing what we want; nobody is fighting us.
    local result = diffOne(
        { ["1-A"] = 7, ["1-B"] = 8 },
        { ["1-A"] = 0, ["1-B"] = 8 },
        { ["1-A"] = 8 })

    T.Eq(#result.actions, 1, "only A needs writing")
    T.Eq(result.actions[1].key, "1-A", "A")
    T.Eq(result.actions[1].isDefense, false, "its icon was taken, not wiped")
end)

T.Case("Brake: an icon wiped to nothing is still defended", function()
    local result = diffOne({ ["1-A"] = 8 }, { ["1-A"] = 0 }, { ["1-A"] = 8 })
    T.Eq(result.actions[1].isDefense, true, "nobody has our skull, so it was wiped")
end)

T.Case("Brake: an icon taken by a mob we do not want to have it is still a fight", function()
    -- Another addon has moved our Skull onto a mob our rules say should be
    -- Cross. That is the case the brake was written for and it must survive.
    local result = diffOne(
        { ["1-A"] = 8, ["1-B"] = 7 },
        { ["1-A"] = 0, ["1-B"] = 8 },
        { ["1-A"] = 8, ["1-B"] = 7 })

    local byKey = {}
    for _, action in ipairs(result.actions) do
        byKey[action.key] = action
    end
    T.Eq(byKey["1-A"].isDefense, true, "A lost skull to a mob that should not have it")
    T.Eq(byKey["1-B"].isDefense, true, "and B is wearing an icon we did not put there")
end)

T.Case("Brake: our icon swapped for a different one is still a fight", function()
    local result = diffOne({ ["1-A"] = 8 }, { ["1-A"] = 3 }, { ["1-A"] = 8 })
    T.Eq(result.actions[1].isDefense, true, "somebody replaced it")
end)

T.Case("Brake: a mob we never marked wearing an icon is contested", function()
    local result = diffOne({ ["1-A"] = 8 }, { ["1-A"] = 3 }, {})
    T.Eq(result.actions[1].isDefense, true, "not ours, so not a free first mark")
end)

T.Case("Brake: a bare unmarked mob is a first mark, not a defense", function()
    local result = diffOne({ ["1-A"] = 8 }, { ["1-A"] = 0 }, {})
    T.Eq(result.actions[1].isDefense, false, "nothing to defend")
end)

T.Case("Brake: three hand-placed marks no longer trip it", function()
    -- The regression this was written for. A tank marks three mobs in a pack of
    -- four; each steal cascades every lower mob down a slot. Before, every one
    -- of those shifts counted as a defense and the pack was yielded.
    local defense = {}
    local placed = { ["1-A"] = 8, ["1-B"] = 7, ["1-C"] = 6, ["1-D"] = 2 }

    for _, step in ipairs({
        { desired = { ["1-D"] = 8, ["1-A"] = 7, ["1-B"] = 6, ["1-C"] = 2 },
          actual  = { ["1-D"] = 8, ["1-A"] = 0, ["1-B"] = 7, ["1-C"] = 6 } },
        { desired = { ["1-D"] = 8, ["1-C"] = 7, ["1-A"] = 6, ["1-B"] = 2 },
          actual  = { ["1-D"] = 8, ["1-C"] = 7, ["1-A"] = 0, ["1-B"] = 6 } },
        { desired = { ["1-D"] = 8, ["1-C"] = 7, ["1-B"] = 6, ["1-A"] = 2 },
          actual  = { ["1-D"] = 8, ["1-C"] = 7, ["1-B"] = 6, ["1-A"] = 0 } },
    }) do
        local result = MFD.Marker.ComputeDiff(step.desired, step.actual, placed, defense, 100, MFD.Marker.LIMITS)
        T.Eq(#result.yielded, 0, "nothing yielded")
        for _, action in ipairs(result.actions) do
            T.Eq(action.isDefense, false, action.key .. " should not count as a fight")
            placed[action.key] = action.icon
        end
    end
end)

T.Case("Remark: resetting the marking state clears the hand-placed holds too", function()
    -- The bug this replaces: /mfd mark wiped locked and placed but left manual
    -- behind, so on the next tick every icon the addon had placed read as
    -- somebody else's and the whole pack was locked permanently.
    MFD.Marker.locked["1-A"] = 8
    MFD.Marker.placed["1-A"] = 8
    MFD.Marker.manual["1-A"] = 8
    MFD.Marker.wroteAt["1-A"] = 100
    MFD.Marker.borrowed["1-A"] = true

    MFD.Marker.ResetMarkState()

    T.Eq(next(MFD.Marker.locked), nil, "locked")
    T.Eq(next(MFD.Marker.placed), nil, "placed")
    T.Eq(next(MFD.Marker.manual), nil, "manual, which is the one that was missed")
    T.Eq(next(MFD.Marker.wroteAt), nil, "wroteAt")
    T.Eq(next(MFD.Marker.borrowed), nil, "borrowed")
end)

T.Case("Encounters: a boss stays the active fight while its nameplate is gone", function()
    -- The raid lead is a ranged healer at the edge of nameplate range. Losing
    -- the nameplate mid fight must not silently stop death announcements.
    T.Eq(MFD.Encounters.Resolve("Illidan Stormrage", nil, true), "Illidan Stormrage", "seen")
    T.Eq(MFD.Encounters.Resolve(nil, "Illidan Stormrage", true), "Illidan Stormrage", "still in combat")
    T.Eq(MFD.Encounters.Resolve(nil, "Illidan Stormrage", false), nil, "combat over, forget it")
    T.Eq(MFD.Encounters.Resolve(nil, nil, true), nil, "never seen one")
end)

T.Case("Encounters: a boss id in the combat log identifies the fight", function()
    local index = MFD.Encounters.IndexByNpcID({ { name = "Supremus", instance = "BT", ids = { 22898 } } })
    T.Eq(MFD.Encounters.FromGUID("Creature-0-1-565-0-22898-000123ABCD", index), "Supremus", "boss")
    T.Eq(MFD.Encounters.FromGUID("Creature-0-1-565-0-99999-000123ABCD", index), nil, "trash")
    T.Eq(MFD.Encounters.FromGUID("Player-4321-0000AAAA", index), nil, "a player is not a boss")
    T.Eq(MFD.Encounters.FromGUID(nil, index), nil, "nothing at all")
end)

T.Case("Deaths: both announcers share one suppression table", function()
    -- A resto druid left flagged Main Tank from last night matches both, and
    -- without a shared table the raid gets the same warning twice.
    T.Eq(MFD.Healers.announced == MFD.Tanks.announced, true, "the same table, not a copy")

    local shared = MFD.Tanks.announced
    for key in pairs(shared) do
        shared[key] = nil
    end

    T.Eq(MFD.Tanks.ShouldAnnounce("Kaylia", shared, 100, 10), true, "the tank announcer gets there first")
    T.Eq(MFD.Tanks.ShouldAnnounce("Kaylia", shared, 100, 10), false, "the healer announcer is suppressed")
end)

_G.MarkedForDeath = MFD
