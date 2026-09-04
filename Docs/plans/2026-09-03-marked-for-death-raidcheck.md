# Marked For Death: Raid Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the raid buff and consumable check to Marked For Death: a full grid on ready check, a quick missing-only buff board on demand, and targeted callouts, so the raid leader can see who is short what and tell a specific person to fix it.

**Architecture:** Two data paths feed one table of per-player state. A local `UnitAura` sweep covers anyone, and every client running the addon self-reports its own state over the existing comms channel, which is the only way to learn weapon enchants, durability and spec. Classification, provider awareness, missing-buff logic and callout formatting are pure functions with tests; the scan, the reports and the three surfaces are thin impure shells over them.

**Tech Stack:** Lua 5.1 (WoW client), LuaJIT 2.1 for headless tests, the addon's existing `Comms`, `UI.AcquireRow` pool and test harness. No new libraries.

**Spec:** `Docs/specs/2026-09-03-marked-for-death-design.md`, section 12 (raid check), section 9 (the `PC` message), section 13 (saved variables).

**Scope:** This plan completes the second half of the spec. The marking engine shipped in `Docs/plans/2026-09-03-marked-for-death-marking.md` at 0.9.0. This plan ends at 1.0.0.

## Global Constraints

Copied from the spec and `CODING_STANDARDS.md`. Every task's requirements implicitly include this section. The marking plan's constraints all still apply; the ones that bite here are repeated.

- **Interface version is `20506`.** Already in the `.toc`.
- **One global only: `MarkedForDeath`.** Every file opens with `local MFD = _G.MarkedForDeath or {}` and closes with `_G.MarkedForDeath = MFD`.
- **No WoW API calls at file scope.** Caching a global into a local is fine. Frames and client reads happen inside `MFD.RegisterInit` or a function called later. This is what lets the harness load `RaidCheck.lua`.
- **`Data_Auras.lua` and every function marked pure in `RaidCheck.lua` call no WoW API.** They go on the harness list and get tests.
- **Match auras by name, never by spell id.** `UnitAura`'s first return is the name on every client build; ids differ per rank and per build. The one exception is nothing: even the diagnostic prints names.
- **Fail open on anything unrecognised.** An aura name not in the tables is not a failure, an unknown creature or class is not a failure, a missing self-report is "unknown", never "missing".
- **Colors follow the repo standard:** green good, red missing, amber external or derived (a scanned cell, as opposed to a self-reported one), grey unknown.
- **The channel is throttled and shared.** Self-reports go through `Comms:Send` and its existing priority queue at priority 3. Reports fire on change but are debounced, and the periodic report is once per 60 seconds, never faster.
- **Every wait has a timeout and a visible failure message.** A ready check that gets no report from a player shows grey "no report" for that cell, not a hang.
- **Every new command appears in `/mfd help` and in `Docs/MarkedForDeath.md`.** Task 8 diffs the two.
- Four-space indentation, Unix line endings, `local` everything, colon syntax on the addon table, booleans as questions, constants in `UPPER_SNAKE` with a unit comment.
- **Use the Write and Edit tools for Lua.** Bash heredocs fail on some content on this machine.
- **`git -C /c/code/ic-addons` with repo-relative paths for every git command.** The Bash and PowerShell tools share a working directory that drifts.
- Deploy is already a live junction; `/reload` picks up edits. Package with `scripts/package.ps1 -Flavor anniversary -Addon MarkedForDeath`.
- **Version must match** in the `.toc`, `MFD.VERSION` in `Core.lua`, and the zip name. This plan bumps 0.9.0 to 1.0.0 in its last task, not before.

## Decisions made while planning

- **Auto-open on ready check is leader and assist only.** Everyone else gets the data (so their buff board works) but no window. A setting turns auto-open off entirely.
- **Blessings are shown, not judged**, per the spec: the grid lists which blessings a player holds and never asserts which they should have.
- **Elixir classification fails open.** Battle and guardian elixir lists are name tables. An elixir name not in either list shows as "elixir (unclassified)" in its own cell rather than being filed wrong or dropped.
- **Self-reported cells win over scanned cells** for the same player, because the owning client is the authority on its own state and is never out of range of itself.
- **The quick buff board needs no comms at all.** It uses only scanned buff columns, so it works in a pug where nobody else has the addon. That property is a deliberate design goal and Task 7 tests it by not touching `Comms`.

## File Structure

```
AddonProjects/anniversary/MarkedForDeath/
    Data_Auras.lua        Pure data: buff, food, flask and elixir name tables, provider classes
    RaidCheck.lua         Pure: classify, providers, missing, callout format, report encode/decode
                          Impure: scan, self-state, report send/receive, state table, refresh policy
    UI_RaidCheck.lua      Full grid, quick buff board, callout buttons
    Comms.lua             Modify: route PC to RaidCheck
    Core.lua              Modify: settings defaults, commands check/buffs/callout, ready-check event
    Tests.lua             Modify: append cases
    Bindings.xml          Modify: buff board keybind

scripts/test-harness.lua  Modify: add Data_Auras.lua and RaidCheck.lua to the load list
Docs/MarkedForDeath.md    Modify: raid check section, new commands
```

**Responsibility boundaries.** `Data_Auras` knows what things are called. `RaidCheck.Classify` turns a list of aura names into one player's buff state. `RaidCheck.Providers` turns a roster into "which buffs can anyone here even cast". `RaidCheck.Missing` combines a state with providers and says what is worth mentioning. `RaidCheck.Format*` turn missing lists into chat text. Everything impure in `RaidCheck` just feeds those. `UI_RaidCheck` paints. Each can be understood alone.

---

### Task 1: Aura tables and classification

Pure. Turns the aura names on one unit into a buff state. This is the foundation every column stands on.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/Data_Auras.lua`
- Create: `AddonProjects/anniversary/MarkedForDeath/RaidCheck.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` (add `Data_Auras.lua` after `Data_Mobs.lua`, `RaidCheck.lua` after `Comms.lua`)
- Modify: `scripts/test-harness.lua` (add both to the load list, in that order, before `Tests.lua`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `MFD.Data.Auras.RAID_BUFFS` -> `{ [column] = { names = { ... }, classes = { CLASSTOKEN, ... } } }` for columns `AI`, `MOTW`, `FORT`, `SP`
  - `MFD.Data.Auras.BLESSINGS` -> `{ [name] = shortLabel }` covering both single and greater versions
  - `MFD.Data.Auras.FOOD` -> `{ [name] = true }`
  - `MFD.Data.Auras.BATTLE_ELIXIRS`, `MFD.Data.Auras.GUARDIAN_ELIXIRS` -> `{ [name] = true }`
  - `MFD.Data.Auras.FLASK_PREFIX` -> `"Flask of "`
  - `MFD.RaidCheck.Classify(auraNames) -> state` where `auraNames` is an array of strings and `state` is
    `{ food = name|nil, flask = name|nil, battle = name|nil, guardian = name|nil, unclassifiedElixir = name|nil, AI = bool, MOTW = bool, FORT = bool, SP = bool, blessings = array of shortLabel sorted }`

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua` before the final `_G.MarkedForDeath = MFD` line:

```lua
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the six new cases fail with `attempt to index field 'RaidCheck' (a nil value)`.

- [ ] **Step 3: Write Data_Auras.lua**

```lua
-- Buff and consumable names as the client reports them in UnitAura. Pure data.
--
-- Everything here is matched by name, never by spell id. Names are stable
-- across ranks and client builds and can be verified by reading a buff bar;
-- ids are neither. /mfd auras prints every name so a mismatch shows up.
local MFD = _G.MarkedForDeath or {}

MFD.Data = MFD.Data or {}
MFD.Data.Auras = MFD.Data.Auras or {}
local A = MFD.Data.Auras

-- The buffs everyone should have, and who can cast them. classes drive the
-- provider check: a buff nobody present can cast is never reported missing.
A.RAID_BUFFS = {
    AI   = { label = "Int",   names = { "Arcane Intellect", "Arcane Brilliance" },          classes = { "MAGE" } },
    MOTW = { label = "MotW",  names = { "Mark of the Wild", "Gift of the Wild" },           classes = { "DRUID" } },
    FORT = { label = "Fort",  names = { "Power Word: Fortitude", "Prayer of Fortitude" },   classes = { "PRIEST" } },
    SP   = { label = "SProt", names = { "Shadow Protection", "Prayer of Shadow Protection" }, classes = { "PRIEST" } },
}

-- Column order for every surface.
A.RAID_BUFF_ORDER = { "AI", "MOTW", "FORT", "SP" }

-- Shown, never judged. Single and greater collapse to one label.
A.BLESSINGS = {
    ["Blessing of Kings"] = "Kings",             ["Greater Blessing of Kings"] = "Kings",
    ["Blessing of Might"] = "Might",             ["Greater Blessing of Might"] = "Might",
    ["Blessing of Wisdom"] = "Wisdom",           ["Greater Blessing of Wisdom"] = "Wisdom",
    ["Blessing of Salvation"] = "Salv",          ["Greater Blessing of Salvation"] = "Salv",
    ["Blessing of Light"] = "Light",             ["Greater Blessing of Light"] = "Light",
    ["Blessing of Sanctuary"] = "Sanct",         ["Greater Blessing of Sanctuary"] = "Sanct",
}

A.FOOD = { ["Well Fed"] = true }

A.FLASK_PREFIX = "Flask of "

-- TBC elixirs by slot. An elixir in neither table is surfaced as unclassified
-- rather than filed wrong. Verify against the client; add, do not guess.
A.BATTLE_ELIXIRS = {
    ["Elixir of Major Agility"] = true,
    ["Elixir of Major Strength"] = true,
    ["Elixir of Major Firepower"] = true,
    ["Elixir of Major Frost Power"] = true,
    ["Elixir of Major Shadow Power"] = true,
    ["Elixir of Healing Power"] = true,
    ["Elixir of Mastery"] = true,
    ["Adept's Elixir"] = true,
    ["Onslaught Elixir"] = true,
    ["Fel Strength Elixir"] = true,
    ["Elixir of the Searching Eye"] = true,
}

A.GUARDIAN_ELIXIRS = {
    ["Elixir of Major Mageblood"] = true,
    ["Elixir of Major Fortitude"] = true,
    ["Elixir of Major Defense"] = true,
    ["Elixir of Draenic Wisdom"] = true,
    ["Elixir of Ironskin"] = true,
    ["Earthen Elixir"] = true,
    ["Elixir of Camouflage"] = true,
}

A.ELIXIR_PATTERN = "Elixir"

_G.MarkedForDeath = MFD
```

- [ ] **Step 4: Write the pure half of RaidCheck.lua**

```lua
-- Raid buff and consumable check.
--
-- The functions above the "client" marker are pure and tested. Everything
-- below it touches the client and runs from RegisterInit or a command.
local MFD = _G.MarkedForDeath or {}

MFD.RaidCheck = MFD.RaidCheck or {}
local RC = MFD.RaidCheck

-- Takes an array of aura names on one unit. Returns that unit's buff state.
-- Unknown names are ignored. Booleans are explicit false when absent so a
-- cell can be painted red rather than grey.
function RC.Classify(auraNames)
    local A = MFD.Data.Auras
    local state = {
        food = nil, flask = nil, battle = nil, guardian = nil, unclassifiedElixir = nil,
        blessings = {},
    }
    for column in pairs(A.RAID_BUFFS) do
        state[column] = false
    end

    local nameSet = {}
    for _, name in ipairs(auraNames) do
        if type(name) == "string" and name ~= "" then
            nameSet[name] = true
        end
    end

    for column, def in pairs(A.RAID_BUFFS) do
        for _, name in ipairs(def.names) do
            if nameSet[name] then
                state[column] = true
            end
        end
    end

    local blessingSeen = {}
    for name in pairs(nameSet) do
        if A.FOOD[name] then
            state.food = name
        elseif string.sub(name, 1, #A.FLASK_PREFIX) == A.FLASK_PREFIX then
            state.flask = name
        elseif A.BATTLE_ELIXIRS[name] then
            state.battle = name
        elseif A.GUARDIAN_ELIXIRS[name] then
            state.guardian = name
        elseif string.find(name, A.ELIXIR_PATTERN, 1, true) then
            state.unclassifiedElixir = name
        elseif A.BLESSINGS[name] then
            blessingSeen[A.BLESSINGS[name]] = true
        end
    end

    for label in pairs(blessingSeen) do
        state.blessings[#state.blessings + 1] = label
    end
    table.sort(state.blessings)

    return state
end

_G.MarkedForDeath = MFD
```

- [ ] **Step 5: TOC and harness**

TOC: add `Data_Auras.lua` immediately after `Data_Mobs.lua`, and `RaidCheck.lua` immediately after `Comms.lua`.

Harness `files` list: add `"Data_Auras.lua"` after `"Data_Mobs.lua"` and `"RaidCheck.lua"` after `"Comms.lua"`.

- [ ] **Step 6: Run the tests to verify they pass**

Expected: `142 passed, 0 failed, 142 total`.

- [ ] **Step 7: Commit**

```bash
git -C /c/code/ic-addons add AddonProjects/anniversary/MarkedForDeath/Data_Auras.lua AddonProjects/anniversary/MarkedForDeath/RaidCheck.lua AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc AddonProjects/anniversary/MarkedForDeath/Tests.lua scripts/test-harness.lua
git -C /c/code/ic-addons commit -m "Add aura tables and buff classification for the raid check"
```

---

### Task 2: Providers and the missing list

Pure. "Who here can even cast this" and "what is worth mentioning for this player". This is the roster-aware principle from the seat model applied to buffs: a buff nobody present can cast is an absence, not a failure.

**Files:**
- Modify: `AddonProjects/anniversary/MarkedForDeath/RaidCheck.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append)

**Interfaces:**
- Consumes: `RC.Classify` state shape from Task 1, `MFD.Data.Auras.RAID_BUFFS`.
- Produces:
  - `RC.Providers(roster) -> { [column] = true|false }` for each column in `RAID_BUFFS`. `roster` is the array of `{ name, class }` that `MFD.Marker.CurrentRoster()` returns.
  - `RC.Missing(state, providers, expected) -> array of { column, label }` where `expected` is `{ [consumable] = true }` for the consumables the raid cares about. Raid buffs come first in `RAID_BUFF_ORDER`, listed only when absent and someone present can provide them; then consumables in a fixed order `FOOD`, `FLASK`, `BATTLE`, `GUARDIAN`, `WEAPON`, listed only when expected and known to be absent. Unknown (nil) is never listed.
  - `RC.CONSUMABLE_ORDER` -> `{ "FOOD", "FLASK", "BATTLE", "GUARDIAN", "WEAPON" }`
  - `RC.CONSUMABLE_LABELS` -> `{ FOOD = "Food", FLASK = "Flask", BATTLE = "Battle elixir", GUARDIAN = "Guardian elixir", WEAPON = "Weapon enchant" }`

- [ ] **Step 1: Write the failing tests**

```lua
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

    local some = MFD.RaidCheck.Missing(state, {}, { FOOD = true, FLASK = true })
    T.Eq(#some, 2, "two expected, both absent")
    T.Eq(some[1].column, "FOOD", "fixed order")
    T.Eq(some[2].column, "FLASK", "fixed order")
end)

T.Case("Missing: a present consumable is not reported even when expected", function()
    local state = MFD.RaidCheck.Classify({ "Well Fed" })
    local missing = MFD.RaidCheck.Missing(state, {}, { FOOD = true })
    T.Eq(#missing, 0, "fed")
end)

T.Case("Missing: weapon enchant comes from the reported flag, not auras", function()
    local state = MFD.RaidCheck.Classify({})
    state.weapon = false
    T.Eq(#MFD.RaidCheck.Missing(state, {}, { WEAPON = true }), 1, "reported absent")
    state.weapon = true
    T.Eq(#MFD.RaidCheck.Missing(state, {}, { WEAPON = true }), 0, "reported present")
    state.weapon = nil
    T.Eq(#MFD.RaidCheck.Missing(state, {}, { WEAPON = true }), 0, "unknown is never reported missing")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: six failures on `MFD.RaidCheck.Providers` being nil.

- [ ] **Step 3: Implement**

Insert into `RaidCheck.lua` after `RC.Classify`, before the final line:

```lua
RC.CONSUMABLE_ORDER = { "FOOD", "FLASK", "BATTLE", "GUARDIAN", "WEAPON" }
RC.CONSUMABLE_LABELS = {
    FOOD = "Food", FLASK = "Flask", BATTLE = "Battle elixir",
    GUARDIAN = "Guardian elixir", WEAPON = "Weapon enchant",
}

-- Takes the roster ({ name, class } array). Returns { [column] = bool } saying
-- whether anyone present can cast each raid buff. Pure.
function RC.Providers(roster)
    local classesPresent = {}
    for _, member in ipairs(roster or {}) do
        classesPresent[member.class] = true
    end

    local providers = {}
    for column, def in pairs(MFD.Data.Auras.RAID_BUFFS) do
        providers[column] = false
        for _, class in ipairs(def.classes) do
            if classesPresent[class] then
                providers[column] = true
            end
        end
    end
    return providers
end

-- Takes a player's state, the providers table and { [consumable] = true } for
-- the consumables the raid expects. Returns an array of { column, label } in a
-- fixed order: raid buffs first, then consumables. Pure.
--
-- A raid buff is missing only when absent AND someone present can cast it.
-- A consumable is missing only when expected AND known to be absent; unknown
-- (no self-report yet) is never reported, because "no data" is not "no flask".
function RC.Missing(state, providers, expected)
    local A = MFD.Data.Auras
    local missing = {}

    for _, column in ipairs(A.RAID_BUFF_ORDER) do
        if providers[column] and state[column] == false then
            missing[#missing + 1] = { column = column, label = A.RAID_BUFFS[column].label }
        end
    end

    local present = {
        FOOD = state.food ~= nil,
        FLASK = state.flask ~= nil,
        BATTLE = state.battle ~= nil,
        GUARDIAN = state.guardian ~= nil,
        WEAPON = state.weapon,
    }

    for _, column in ipairs(RC.CONSUMABLE_ORDER) do
        if expected[column] and present[column] == false then
            missing[#missing + 1] = { column = column, label = RC.CONSUMABLE_LABELS[column] }
        end
    end

    return missing
end
```

Note `present.WEAPON = state.weapon` is deliberately not coerced: `nil` (no report) stays nil and is skipped by the `== false` check.

- [ ] **Step 4: Run the tests to verify they pass**

Expected: `148 passed`.

- [ ] **Step 5: Commit**

```bash
git -C /c/code/ic-addons add AddonProjects/anniversary/MarkedForDeath/RaidCheck.lua AddonProjects/anniversary/MarkedForDeath/Tests.lua
git -C /c/code/ic-addons commit -m "Add provider awareness and the missing-buff list"
```

---

### Task 3: Self-reports over the channel

Each client reports its own state: what it cannot be scanned for (weapon enchant, durability, spec, addon version) plus its buff flags as an authoritative overlay. Encode and decode are pure and tested; the gather and the send are not.

**Files:**
- Modify: `AddonProjects/anniversary/MarkedForDeath/RaidCheck.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/Comms.lua` (route `PC`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append)

**Interfaces:**
- Consumes: `MFD.Comms:Send`, `Comms.HandleRuleMessage` dispatch pattern, `Comms.PRIORITY.PC = 3` (already present).
- Produces:
  - `RC.REPORT_HEARTBEAT_SECONDS` -> `60`, `RC.REPORT_DEBOUNCE_SECONDS` -> `2`
  - `RC.EncodeReport(state) -> array of fields` and `RC.DecodeReport(fields) -> state|nil`. The state carries `version, weapon (bool|nil), durability (0..100|nil), spec (string|nil), AI, MOTW, FORT, SP (bool), food, flask, battle, guardian (bool)`. Names are not sent; the receiver already has them from its scan, and names do not fit in 240 bytes for 25 people.
  - `RC.reports` -> `{ [playerName] = { state, at } }` populated by received `PC` messages
  - `RC:GatherSelf() -> state` (impure)
  - `RC:SendReport()` (impure, debounced)

- [ ] **Step 1: Write the failing tests**

```lua
T.Case("Report: encode and decode round-trip the self-reported state", function()
    local state = {
        version = "0.9.0", weapon = true, durability = 87, spec = "Fire",
        AI = true, MOTW = false, FORT = true, SP = false,
        food = true, flask = false, battle = true, guardian = false,
    }
    local decoded = MFD.RaidCheck.DecodeReport(MFD.RaidCheck.EncodeReport(state))
    T.Eq(decoded.version, "0.9.0", "version")
    T.Eq(decoded.weapon, true, "weapon")
    T.Eq(decoded.durability, 87, "durability as a number")
    T.Eq(decoded.spec, "Fire", "spec")
    T.Eq(decoded.AI, true, "AI")
    T.Eq(decoded.MOTW, false, "MOTW false, not nil")
    T.Eq(decoded.battle, true, "battle")
    T.Eq(decoded.guardian, false, "guardian")
end)

T.Case("Report: unknown fields encode as unknown and decode as nil", function()
    local decoded = MFD.RaidCheck.DecodeReport(MFD.RaidCheck.EncodeReport({ version = "x" }))
    T.Eq(decoded.weapon, nil, "no weapon data is nil, never false")
    T.Eq(decoded.durability, nil, "no durability is nil")
    T.Eq(decoded.spec, nil, "no spec is nil")
    T.Eq(decoded.AI, nil, "unknown buff is nil")
end)

T.Case("Report: the encoded form fits one addon message with room to spare", function()
    local fields = MFD.RaidCheck.EncodeReport({
        version = "10.10.10", weapon = true, durability = 100, spec = "Restoration",
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: four failures on `MFD.RaidCheck.EncodeReport` being nil.

- [ ] **Step 3: Implement the pure encode and decode**

Insert into `RaidCheck.lua` before the final line:

```lua
RC.REPORT_HEARTBEAT_SECONDS = 60   -- periodic self-report while in a group
RC.REPORT_DEBOUNCE_SECONDS = 2     -- coalesce bursts of change into one report

-- Tri-state flags on the wire: 1 true, 0 false, ? unknown. Unknown must stay
-- distinct from false, because "no data" is not "no flask".
local FLAG_ORDER = { "weapon", "AI", "MOTW", "FORT", "SP", "food", "flask", "battle", "guardian" }

local function flagChar(v)
    if v == true then return "1" end
    if v == false then return "0" end
    return "?"
end

local function charFlag(c)
    if c == "1" then return true end
    if c == "0" then return false end
    return nil
end

-- Takes a state. Returns the fields array for a PC message:
-- { version, flags, durability, spec }. Pure.
function RC.EncodeReport(state)
    local flags = {}
    for i, key in ipairs(FLAG_ORDER) do
        flags[i] = flagChar(state[key])
    end
    return {
        state.version or "?",
        table.concat(flags),
        state.durability and tostring(math.floor(state.durability)) or "?",
        state.spec or "?",
    }
end

-- Takes the fields array from a PC message. Returns a state, or nil when the
-- fields are not a report. Pure.
function RC.DecodeReport(fields)
    if type(fields) ~= "table" or #fields < 4 then
        return nil
    end
    local flags = fields[2]
    if type(flags) ~= "string" or #flags ~= #FLAG_ORDER then
        return nil
    end

    local state = { version = fields[1] ~= "?" and fields[1] or nil }
    for i, key in ipairs(FLAG_ORDER) do
        state[key] = charFlag(string.sub(flags, i, i))
    end
    state.durability = tonumber(fields[3])
    state.spec = fields[4] ~= "?" and fields[4] or nil
    return state
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected: `152 passed`.

- [ ] **Step 5: Implement the client half**

Append to `RaidCheck.lua` before the final line:

```lua
-- ---------------------------------------------------------------- client --

local UnitAura = UnitAura
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetInventoryItemDurability = GetInventoryItemDurability
local GetTalentTabInfo = GetTalentTabInfo

RC.reports = {}

-- Returns an array of aura names on unit. Reads only the first return of
-- UnitAura, which is the name on every client build. Wrapped because the
-- return signature differs across the flavors this repo targets.
function RC.AuraNames(unit)
    local names = {}
    if not UnitAura then
        return names
    end
    for i = 1, 40 do
        local ok, name = pcall(UnitAura, unit, i, "HELPFUL")
        if not ok or not name then
            break
        end
        names[#names + 1] = name
    end
    return names
end

-- Equipped item slots that have durability. Head through hands, legs, feet,
-- weapons and ranged. Same slots the repair vendor totals.
local DURABILITY_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

local function durabilityPercent()
    if not GetInventoryItemDurability then
        return nil
    end
    local current, maximum = 0, 0
    for _, slot in ipairs(DURABILITY_SLOTS) do
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        if ok and cur and max and max > 0 then
            current = current + cur
            maximum = maximum + max
        end
    end
    if maximum == 0 then
        return nil
    end
    return math.floor(current / maximum * 100)
end

local function specName()
    if not GetTalentTabInfo then
        return nil
    end
    local bestName, bestPoints = nil, -1
    for tab = 1, 3 do
        local ok, name, _, points = pcall(GetTalentTabInfo, tab)
        if ok and name and points and points > bestPoints then
            bestName, bestPoints = name, points
        end
    end
    return bestName
end

-- Reads this client's own state. The only place weapon enchant, durability
-- and spec can ever be learned from, which is why they are self-reported.
function RC:GatherSelf()
    local state = RC.Classify(RC.AuraNames("player"))
    state.version = MFD.VERSION
    state.durability = durabilityPercent()
    state.spec = specName()

    if GetWeaponEnchantInfo then
        local ok, hasMainHand = pcall(GetWeaponEnchantInfo)
        state.weapon = ok and (hasMainHand and true or false) or nil
    end

    -- Flatten names to flags for the wire; the receiver has names from its
    -- own scan when in range.
    state.food = state.food ~= nil
    state.flask = state.flask ~= nil
    state.battle = state.battle ~= nil
    state.guardian = state.guardian ~= nil
    return state
end

local reportTimer
local lastReportAt = 0

-- Sends a self-report, debounced so a mass rebuff produces one message per
-- client rather than one per buff. Nothing is sent when solo.
function RC:SendReport()
    if reportTimer then
        return
    end
    reportTimer = true
    C_Timer.After(RC.REPORT_DEBOUNCE_SECONDS, function()
        reportTimer = nil
        if not ((IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())) then
            return
        end
        lastReportAt = GetTime()
        MFD.Comms:Send("PC", RC.EncodeReport(RC:GatherSelf()))
    end)
end

-- Called by Comms when a PC message arrives.
function RC:ReceiveReport(sender, fields)
    local state = RC.DecodeReport(fields)
    if not state then
        return
    end
    RC.reports[sender] = { state = state, at = GetTime() }
    if RC.OnDataChanged then
        RC.OnDataChanged()
    end
end

local heartbeat = 0

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterUnitEvent("UNIT_AURA", "player")

    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then
            return
        end
        RC:SendReport()
    end)

    frame:SetScript("OnUpdate", function(_, elapsed)
        heartbeat = heartbeat + elapsed
        if heartbeat >= RC.REPORT_HEARTBEAT_SECONDS then
            heartbeat = 0
            RC:SendReport()
        end
    end)
end)
```

- [ ] **Step 6: Route PC in Comms.lua**

In `Comms:HandleRuleMessage`, before the final `return false`:

```lua
    if msgType == "PC" then
        if MFD.RaidCheck then
            MFD.RaidCheck:ReceiveReport(sender, fields)
        end
        return true
    end
```

- [ ] **Step 7: Verify in game, two clients**

1. Both `/reload` in a group.
2. On one, `/run for n, r in pairs(MarkedForDeath.RaidCheck.reports) do print(n, r.state.spec, r.state.durability, r.state.weapon) end` after a few seconds. The other player's spec, durability percent and weapon flag print.
3. Have the other player apply an oil. Within about two seconds the flag flips.
4. Solo, confirm nothing is sent: the queue stays empty (`/mfd status` still works, no errors).
5. BugSack empty on both.

- [ ] **Step 8: Commit**

```bash
git -C /c/code/ic-addons add AddonProjects/anniversary/MarkedForDeath/RaidCheck.lua AddonProjects/anniversary/MarkedForDeath/Comms.lua AddonProjects/anniversary/MarkedForDeath/Tests.lua
git -C /c/code/ic-addons commit -m "Self-report weapon enchant, durability, spec and buff flags over the channel"
```

---

### Task 4: The scan, the merged row table, and a text summary

Reads every group member, merges what was scanned with what they reported, and prints a text summary. After this task the raid check is usable from chat before any window exists. The merge is pure and tested.

**Files:**
- Modify: `AddonProjects/anniversary/MarkedForDeath/RaidCheck.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/Core.lua` (settings, `/mfd missing`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append)

**Interfaces:**
- Consumes: `RC.Classify`, `RC.Providers`, `RC.Missing`, `RC.reports`, `RC.AuraNames`, `MFD.Marker.CurrentRoster()`.
- Produces:
  - `RC.MergeRow(scanned, reported) -> row` where `row = { state, isReported }`. `state` has the union of fields; for the boolean buff and consumable flags a non-nil reported value overrides the scanned one; names (`food`, `flask`, `battle`, `guardian`, `unclassifiedElixir`, `blessings`) come only from the scan; `weapon`, `durability`, `spec`, `version` come only from the report.
  - `RC.rows` -> `{ [playerName] = { name, class, unit, row, missing } }`
  - `RC.providers` -> the current providers table
  - `RC:Scan()` rebuilds `rows` and `providers` from the live group
  - `RC:ScanUnit(unit)` rebuilds one entry
  - `RC.OnDataChanged` -> optional callback the UI sets; called after any scan or report
  - `MFD.db.settings.raidCheck` -> `{ isAutoOpenEnabled = true, expected = { FOOD = true, FLASK = true, BATTLE = false, GUARDIAN = false, WEAPON = true } }`

- [ ] **Step 1: Write the failing tests**

```lua
T.Case("MergeRow: a report overrides a scanned flag but never a scanned name", function()
    local scanned = MFD.RaidCheck.Classify({ "Flask of Relentless Assault" })
    local reported = { flask = false, AI = true, weapon = true, durability = 90, spec = "Fire", version = "1.0.0" }
    local row = MFD.RaidCheck.MergeRow(scanned, reported)
    T.Eq(row.isReported, true, "marked as reported")
    T.Eq(row.state.AI, true, "report supplies a flag the scan could not see")
    T.Eq(row.state.flask, "Flask of Relentless Assault", "the scanned name is kept for display")
    T.Eq(row.state.weapon, true, "weapon only ever comes from the report")
    T.Eq(row.state.durability, 90, "durability from the report")
    T.Eq(row.state.spec, "Fire", "spec from the report")
end)

T.Case("MergeRow: no report leaves the row scan-only with unknowns nil", function()
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({ "Well Fed" }), nil)
    T.Eq(row.isReported, false, "scan only")
    T.Eq(row.state.food, "Well Fed", "scanned name")
    T.Eq(row.state.weapon, nil, "unknown, never false")
    T.Eq(row.state.durability, nil, "unknown")
end)

T.Case("MergeRow: a reported false does not erase a scanned present name", function()
    -- The report is a flag snapshot that can lag the scan by a debounce.
    -- The scan just saw the flask. Keep the name; the flag is informational.
    local row = MFD.RaidCheck.MergeRow(MFD.RaidCheck.Classify({ "Flask of Blinding Light" }), { flask = false })
    T.Eq(row.state.flask, "Flask of Blinding Light", "present in the scan wins for names")
end)

T.Case("Missing: a flask satisfies both elixir slots", function()
    local state = MFD.RaidCheck.Classify({ "Flask of Relentless Assault" })
    local missing = MFD.RaidCheck.Missing(state, {}, { BATTLE = true, GUARDIAN = true })
    T.Eq(#missing, 0, "a flask is both elixirs")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: three failures on `MFD.RaidCheck.MergeRow` being nil and one on the flask case (two missing reported).

- [ ] **Step 3: Implement MergeRow and the flask rule**

In `RC.Missing`, change the `present` table so a flask covers the elixir slots:

```lua
    local hasFlask = state.flask ~= nil
    local present = {
        FOOD = state.food ~= nil,
        FLASK = hasFlask,
        BATTLE = hasFlask or state.battle ~= nil,
        GUARDIAN = hasFlask or state.guardian ~= nil,
        WEAPON = state.weapon,
    }
```

Insert `MergeRow` after `RC.Missing`:

```lua
local REPORT_ONLY = { "weapon", "durability", "spec", "version" }
local FLAG_ONLY = { "AI", "MOTW", "FORT", "SP" }

-- Takes a scanned state and a reported state (or nil). Returns
-- { state, isReported }. Pure.
--
-- The owning client is the authority on its own flags, so a non-nil reported
-- flag overrides the scan. Names come only from the scan because the wire
-- carries flags, not names. Weapon, durability, spec and version come only
-- from the report because nothing else can see them.
function RC.MergeRow(scanned, reported)
    local state = {}
    for k, v in pairs(scanned) do
        state[k] = v
    end

    if not reported then
        return { state = state, isReported = false }
    end

    for _, key in ipairs(FLAG_ONLY) do
        if reported[key] ~= nil then
            state[key] = reported[key]
        end
    end

    for _, key in ipairs(REPORT_ONLY) do
        state[key] = reported[key]
    end

    return { state = state, isReported = true }
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected: `156 passed`.

- [ ] **Step 5: Implement the scan**

Append to `RaidCheck.lua` before the final line:

```lua
RC.rows = {}
RC.providers = {}

-- Returns the unit tokens and names for everyone in the group, self included.
local function groupUnits()
    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
        end
        return units
    end
    units[1] = "player"
    if IsInGroup and IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
        end
    end
    return units
end

local function expected()
    return MFD.db.settings.raidCheck.expected
end

-- Rebuilds one player's row from a live unit token.
function RC:ScanUnit(unit)
    local name = UnitName(unit)
    if not name or name == "" then
        return
    end
    local _, class = UnitClass(unit)
    local scanned = RC.Classify(RC.AuraNames(unit))
    local reported = RC.reports[name] and RC.reports[name].state or nil
    local row = RC.MergeRow(scanned, reported)
    RC.rows[name] = {
        name = name,
        class = class,
        unit = unit,
        row = row,
        missing = RC.Missing(row.state, RC.providers, expected()),
        scannedAt = GetTime(),
    }
end

-- Rebuilds every row. Providers first, because Missing depends on them.
function RC:Scan()
    RC.providers = RC.Providers(MFD.Marker.CurrentRoster())
    wipe(RC.rows)
    for _, unit in ipairs(groupUnits()) do
        RC:ScanUnit(unit)
    end
    if RC.OnDataChanged then
        RC.OnDataChanged()
    end
end

-- Returns the rows as an array sorted by raid group then name, so the grid
-- reads like the raid frame.
function RC:SortedRows()
    local list = {}
    for _, entry in pairs(RC.rows) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end
```

- [ ] **Step 6: Settings and the text command**

In `Core.lua` `DB_DEFAULTS.settings`, add:

```lua
        raidCheck = {
            isAutoOpenEnabled = true,
            expected = { FOOD = true, FLASK = true, BATTLE = false, GUARDIAN = false, WEAPON = true },
        },
```

Add the command:

```lua
commands.missing = {
    desc = "text summary of who is missing what buff or consumable",
    run = function()
        MFD.RaidCheck:Scan()
        local anyone = false
        for _, entry in ipairs(MFD.RaidCheck:SortedRows()) do
            if #entry.missing > 0 then
                anyone = true
                local labels = {}
                for _, m in ipairs(entry.missing) do
                    labels[#labels + 1] = m.label
                end
                MFD.Print(string.format("%s%s|r: %s",
                    entry.row.isReported and "" or "|cffffcc66",
                    entry.name, table.concat(labels, ", ")))
            end
        end
        if not anyone then
            MFD.Print("everyone has everything the group can provide")
        end
    end,
}
```

- [ ] **Step 7: Verify in game**

1. Solo, unbuffed: `/mfd missing` lists you with Food, Flask, Weapon enchant (the expected defaults), and no raid buffs (nobody can cast them).
2. Eat food: rerun, Food is gone from the list.
3. In a group with a mage who has not buffed you: Int appears; after they buff, it disappears.
4. Your own name prints white (reported); a group member not running the addon prints amber (scan only).
5. BugSack empty.

- [ ] **Step 8: Commit**

```bash
git -C /c/code/ic-addons add AddonProjects/anniversary/MarkedForDeath/RaidCheck.lua AddonProjects/anniversary/MarkedForDeath/Core.lua AddonProjects/anniversary/MarkedForDeath/Tests.lua
git -C /c/code/ic-addons commit -m "Scan the group, merge with self-reports, and summarise what is missing"
```

---

### Task 5: Callouts

Formatting is pure and tested. Posting is throttled and goes to raid or party chat, or a whisper.

**Files:**
- Modify: `AddonProjects/anniversary/MarkedForDeath/RaidCheck.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/Core.lua` (`/mfd callout`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append)

**Interfaces:**
- Consumes: `RC.rows` entries with `missing` arrays.
- Produces:
  - `RC.CALLOUT_THROTTLE_SECONDS` -> `10`, `RC.CALLOUT_MAX_LINES` -> `4`, `RC.CALLOUT_LINE_BYTES` -> `200`
  - `RC.FormatCallout(entries) -> array of lines` grouped by fix, each line at most `CALLOUT_LINE_BYTES`, at most `CALLOUT_MAX_LINES` lines, with a final "and N more" if truncated
  - `RC.FormatWhisper(entry) -> string|nil`
  - `RC:PostCallout()` and `RC:Whisper(name)` (impure)

- [ ] **Step 1: Write the failing tests**

```lua
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: five failures on `MFD.RaidCheck.FormatCallout` being nil.

- [ ] **Step 3: Implement**

Insert after `RC.MergeRow`:

```lua
RC.CALLOUT_THROTTLE_SECONDS = 10  -- minimum gap between raid-chat callouts
RC.CALLOUT_MAX_LINES = 4          -- lines per callout
RC.CALLOUT_LINE_BYTES = 200       -- bytes per line, under the chat cap

-- Takes row entries ({ name, missing }). Returns chat lines grouped by fix,
-- in the order fixes first appear, names sorted, capped and truncated. Pure.
-- Grouping by fix rather than by player is what makes it actionable: the
-- paladin reads the Kings line, the mage reads the Int line.
function RC.FormatCallout(entries)
    local byFix, order = {}, {}
    for _, entry in ipairs(entries) do
        for _, m in ipairs(entry.missing or {}) do
            if not byFix[m.label] then
                byFix[m.label] = {}
                order[#order + 1] = m.label
            end
            table.insert(byFix[m.label], entry.name)
        end
    end

    local lines = {}
    for i, label in ipairs(order) do
        if i > RC.CALLOUT_MAX_LINES then
            lines[#lines] = lines[#lines] .. " (and " .. (#order - RC.CALLOUT_MAX_LINES + 1) .. " more)"
            break
        end
        local names = byFix[label]
        table.sort(names)
        local line = label .. ": " .. table.concat(names, ", ")
        if #line > RC.CALLOUT_LINE_BYTES then
            line = string.sub(line, 1, RC.CALLOUT_LINE_BYTES - 3) .. "..."
        end
        lines[#lines + 1] = line
    end

    return lines
end

-- Takes one row entry. Returns a whisper line, or nil when there is nothing
-- to say. Pure.
function RC.FormatWhisper(entry)
    if not entry.missing or #entry.missing == 0 then
        return nil
    end
    local labels = {}
    for _, m in ipairs(entry.missing) do
        labels[#labels + 1] = m.label
    end
    return "You are missing: " .. table.concat(labels, ", ")
end
```

Note the overflow branch: when there are more fixes than lines, the last kept line gets the count appended so the limit is never silently exceeded. With eight fixes and four lines, the fourth line ends with "(and 5 more)".

Append to the client half:

```lua
local lastCalloutAt = 0

-- Posts the callout to raid or party chat, throttled.
function RC:PostCallout()
    local now = GetTime()
    if (now - lastCalloutAt) < RC.CALLOUT_THROTTLE_SECONDS then
        MFD.Print("callout throttled, try again in a few seconds")
        return
    end

    local target = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and IsInGroup() and "PARTY") or nil
    if not target then
        MFD.Error("not in a group")
        return
    end

    RC:Scan()
    local lines = RC.FormatCallout(RC:SortedRows())
    if #lines == 0 then
        MFD.Print("nothing to call out")
        return
    end

    lastCalloutAt = now
    for _, line in ipairs(lines) do
        pcall(SendChatMessage, "[MFD] " .. line, target)
    end
end

-- Whispers one player what they are missing.
function RC:Whisper(name)
    local entry = RC.rows[name]
    local text = entry and RC.FormatWhisper(entry)
    if not text then
        MFD.Print(name .. " is not missing anything")
        return
    end
    pcall(SendChatMessage, "[MFD] " .. text, "WHISPER", nil, name)
end
```

Add the command:

```lua
commands.callout = {
    desc = "post who is missing what to raid chat, grouped by fix",
    run = function()
        MFD.RaidCheck:PostCallout()
    end,
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected: `161 passed`.

- [ ] **Step 5: Verify in game**

1. In a group with someone missing a buff: `/mfd callout` posts grouped lines to party chat.
2. Immediately again: prints the throttle message, posts nothing.
3. With nothing missing: prints "nothing to call out".

- [ ] **Step 6: Commit**

```bash
git -C /c/code/ic-addons add AddonProjects/anniversary/MarkedForDeath/RaidCheck.lua AddonProjects/anniversary/MarkedForDeath/Core.lua AddonProjects/anniversary/MarkedForDeath/Tests.lua
git -C /c/code/ic-addons commit -m "Add grouped raid-chat callouts and per-player whispers"
```

---

### Task 6: The full grid

Opens on ready check for leader and assist, or on `/mfd check`. Live while shown. This task is UI; the specification below is binding and the row pool is reused.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/UI_RaidCheck.lua`
- Modify: `MarkedForDeath.toc` (add after `UI_Assignments.lua`)
- Modify: `Core.lua` (`/mfd check`, ready-check event)

**Interfaces:**
- Consumes: `RC.rows`, `RC:SortedRows()`, `RC:Scan()`, `RC:ScanUnit(unit)`, `RC.OnDataChanged`, `RC:Whisper`, `RC:PostCallout`, `MFD.UI.AcquireRow`, `MFD.UI.ReleaseRows`, `MFD.Data.Auras.RAID_BUFF_ORDER`, `RC.CONSUMABLE_ORDER`.
- Produces: `MFD.UI.RaidCheck:Toggle()`, `:Show()`, `:Refresh()`

- [ ] **Step 1: Write UI_RaidCheck.lua**

A `BasicFrameTemplateWithInset` frame named `MarkedForDeathRaidCheckFrame`, in `UISpecialFrames`, movable, position saved to `MFD.charDb.windows.raidCheck` exactly the way `UI_Assignments.lua` does it, 860 wide, height for 26 rows of 18 pixels plus a header and a button bar.

Columns, left to right, with fixed widths: Name (110), Food (44), Flask (44), Battle (44), Guardian (44), Weapon (44), Int (40), MotW (40), Fort (40), SProt (40), Blessings (120), Dur (40), Spec (80), Ver (50). A header row of `GameFontDisableSmall` labels.

One pooled row per player from `RC:SortedRows()`. Each cell is a `FontString`. Cell text and color:

- Consumable and raid buff cells: `|cff66ff66yes|r` when present, `|cffff4444no|r` when absent and in that player's `missing` list, `|cff999999no|r` when absent but not worth mentioning (nobody can cast it, or not expected), `|cff999999?|r` when unknown (nil).
- Blessings: the sorted labels joined by space, or `|cff999999none|r`.
- Dur: the number with `%`, red under 30, amber under 60, else white; `?` when unknown.
- Spec and Ver: the string or `?`. Ver in red when it differs from `MFD.VERSION`.
- Name: white when `row.isReported`, amber when scan-only. Name is a `Button`; clicking it calls `RC:Whisper(name)`.

Button bar at the bottom: **Refresh** (`RC:Scan()`), **Call out** (`RC:PostCallout()`), and a checkbox **Open on ready check** bound to `MFD.db.settings.raidCheck.isAutoOpenEnabled`.

Live policy: on `Show`, register `UNIT_AURA` on the frame and, in its handler, if the unit is a group unit, call `RC:ScanUnit(unit)` and repaint that one row. On `Hide`, unregister it. Set `RC.OnDataChanged` to a function that repaints if the frame is shown, so incoming reports repaint too.

`Toggle()` builds lazily, then shows or hides. `Show()` scans and shows.

- [ ] **Step 2: Wire the ready check**

In `Core.lua`, inside `onAddonLoaded` after the zone frame, add:

```lua
    local readyFrame = CreateFrame("Frame")
    readyFrame:RegisterEvent("READY_CHECK")
    readyFrame:SetScript("OnEvent", function()
        if not MFD.db.settings.raidCheck.isAutoOpenEnabled then
            return
        end
        -- Leader and assist only. A window on twenty four screens every ready
        -- check is how an addon gets uninstalled.
        local isLeadOrAssist = UnitIsGroupLeader("player")
            or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        if isLeadOrAssist then
            MFD.UI.RaidCheck:Show()
        else
            MFD.RaidCheck:Scan()
        end
    end)
```

Add the command:

```lua
commands.check = {
    desc = "open the full raid buff and consumable grid",
    run = function()
        MFD.UI.RaidCheck:Toggle()
    end,
}
```

- [ ] **Step 3: Run the tests**

Expected: `161 passed`, unchanged; the UI file is not on the harness list.

- [ ] **Step 4: Verify in game**

1. `/mfd check` opens the grid with one row per group member, columns as listed.
2. Your own row is white; a member without the addon is amber and shows `?` for Weapon, Dur, Spec and Ver.
3. Eat food and watch your Food cell go green without touching anything.
4. Click a name; that player receives the whisper.
5. As leader, start a ready check: the grid opens by itself. Untick the checkbox, start another: it does not.
6. Move the window, `/reload`, it comes back where it was.
7. BugSack empty.

- [ ] **Step 5: Commit**

```bash
git -C /c/code/ic-addons add AddonProjects/anniversary/MarkedForDeath/UI_RaidCheck.lua AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc AddonProjects/anniversary/MarkedForDeath/Core.lua
git -C /c/code/ic-addons commit -m "Add the full raid check grid, live while shown, auto-open on ready check"
```

---

### Task 7: The quick buff board

Missing-only by default, buff columns only, works in a pug with nobody else running the addon. The test for that last property is structural: this task must not add any call into `Comms`.

**Files:**
- Modify: `AddonProjects/anniversary/MarkedForDeath/UI_RaidCheck.lua`
- Modify: `Core.lua` (`/mfd buffs`, `MFD.Bindings.ToggleBuffs`)
- Modify: `Bindings.xml` (`MARKEDFORDEATH_BUFFS`)

**Interfaces:**
- Consumes: everything Task 6 does.
- Produces: `MFD.UI.BuffBoard:Toggle()`, `:Refresh()`

- [ ] **Step 1: Write the board**

A second, smaller frame in `UI_RaidCheck.lua` named `MarkedForDeathBuffBoardFrame`, 360 wide, in `UISpecialFrames`, position saved to `MFD.charDb.windows.buffBoard`, strata `MEDIUM` so it can sit over the raid frames.

Content: one pooled row per player who has anything in `entry.missing`, showing the name (a button, click to whisper) and the missing labels joined by ", " in red. When nobody is missing anything, a single line `|cff66ff66everyone is buffed|r`. A **Show all** checkbox lists every player instead, with `|cff66ff66ok|r` for the complete ones. A **Call out** button calls `RC:PostCallout()`.

Live policy identical to the grid: `UNIT_AURA` registered while shown, unregistered on hide, `RC.OnDataChanged` repaints. Since the grid and the board can both be open, `RC.OnDataChanged` is set once to a function that repaints whichever of the two is shown.

`Toggle()` scans on show.

- [ ] **Step 2: Command and keybind**

```lua
commands.buffs = {
    desc = "quick board of who is missing buffs, no ready check needed",
    run = function()
        MFD.UI.BuffBoard:Toggle()
    end,
}
```

In `MFD.Bindings`:

```lua
function MFD.Bindings.ToggleBuffs()
    MFD.UI.BuffBoard:Toggle()
end
```

`BINDING_NAME_MARKEDFORDEATH_BUFFS = "Toggle the buff board"`, and in `Bindings.xml`:

```xml
    <Binding name="MARKEDFORDEATH_BUFFS" category="ADDONS">
        MarkedForDeath.Bindings.ToggleBuffs()
    </Binding>
```

- [ ] **Step 3: Confirm the board does not depend on comms**

Run: `grep -n "Comms" AddonProjects/anniversary/MarkedForDeath/UI_RaidCheck.lua`

Expected: no output. The board reads `RC.rows`, which the scan fills without any report. Reports only add columns the board does not show.

- [ ] **Step 4: Verify in game**

1. In a pug where nobody else has the addon: `/mfd buffs` lists who is missing Int, MotW, Fort, SProt (whichever have providers) and expected consumables, correctly.
2. Get someone buffed and watch them drop off the list.
3. Show all lists everyone with `ok` for the complete ones.
4. Bind the key and confirm it toggles.
5. BugSack empty.

- [ ] **Step 5: Commit**

```bash
git -C /c/code/ic-addons add AddonProjects/anniversary/MarkedForDeath/UI_RaidCheck.lua AddonProjects/anniversary/MarkedForDeath/Core.lua AddonProjects/anniversary/MarkedForDeath/Bindings.xml
git -C /c/code/ic-addons commit -m "Add the quick buff board"
```

---

### Task 8: Diagnostic, documentation, and release 1.0.0

**Files:**
- Modify: `Core.lua` (`/mfd auras`, version)
- Modify: `MarkedForDeath.toc` (version)
- Modify: `Docs/MarkedForDeath.md`
- Modify: `AddonProjects/anniversary/README.md`

- [ ] **Step 1: Add the aura diagnostic**

The name tables were written from knowledge of the client, not read off it. This command lets a mismatch be seen instead of silently never matching:

```lua
commands.auras = {
    desc = "list the buff names on you and how the addon classified them",
    run = function()
        local names = MFD.RaidCheck.AuraNames("player")
        local state = MFD.RaidCheck.Classify(names)
        MFD.Print(#names .. " buffs on you: " .. table.concat(names, ", "))
        MFD.Print(string.format("food=%s flask=%s battle=%s guardian=%s unclassified=%s",
            tostring(state.food), tostring(state.flask), tostring(state.battle),
            tostring(state.guardian), tostring(state.unclassifiedElixir)))
        MFD.Print(string.format("int=%s motw=%s fort=%s sprot=%s blessings=%s",
            tostring(state.AI), tostring(state.MOTW), tostring(state.FORT), tostring(state.SP),
            table.concat(state.blessings, " ")))
    end,
}
```

- [ ] **Step 2: Verify the tables against the client**

1. Buff yourself with everything you can: food, a flask, an elixir of each type if no flask, a weapon oil, and class buffs from group members.
2. `/mfd auras`. Every buff you can see on your buff bar appears in the name list. Every consumable lands in its slot. Anything showing as `unclassified` is an elixir name to add to `Data_Auras.lua`.
3. Fix any name mismatch in `Data_Auras.lua`, rerun, commit the corrections separately with the names that were wrong in the message.

- [ ] **Step 3: Documentation**

In `Docs/MarkedForDeath.md`, add a "Raid check" section after "Mid-pull behaviour" covering: the grid and what auto-opens it, the buff board and why it works in a pug, callouts and whispers, what needs the addon on the other client (weapon, durability, spec, version) and what does not, that blessings are shown not judged, that a buff nobody can cast is never reported missing, and `/mfd auras` for verifying names. Add every new command to the table: `check`, `buffs`, `missing`, `callout`, `auras`. Add the keybind to the keybinds line. Remove the "not in this build" sentence from the Versioning section.

- [ ] **Step 4: Diff the documented commands against the registered ones**

Run the same cross-check the marking plan used. It must report no differences.

- [ ] **Step 5: Bump to 1.0.0**

`## Version: 1.0.0` in the `.toc`, `MFD.VERSION = "1.0.0"` in `Core.lua`, and the README row. Both halves of the spec now ship, so the number is earned.

- [ ] **Step 6: Run everything**

- `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath` passes
- The syntax check over every Lua file passes
- The globals scan shows only `BINDING_*`, `SLASH_*` and `SlashCmdList`
- `/reload` with "Load out of date AddOns" off, BugSack empty, every new command in `/mfd help`

- [ ] **Step 7: Package and commit**

```bash
powershell -File scripts/package.ps1 -Flavor anniversary -Addon MarkedForDeath
```

Confirm `dist/MarkedForDeath-1.0.0-anniversary.zip`, send it with SendUserFile, then:

```bash
git -C /c/code/ic-addons add Docs/MarkedForDeath.md AddonProjects/anniversary/README.md AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc AddonProjects/anniversary/MarkedForDeath/Core.lua
git -C /c/code/ic-addons commit -m "Document the raid check and release 1.0.0"
```

Push the branch. Do not open a PR unless asked; the repo's CLAUDE.md is explicit that a PR is opened when the user asks for a merge.
