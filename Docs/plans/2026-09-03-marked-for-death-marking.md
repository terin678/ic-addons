# Marked For Death: Marking Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a TBC Anniversary addon that automatically places raid target icons on trash mobs by kill priority and crowd control intent, coordinated across every raid member running it.

**Architecture:** Icons bind to durable seats rather than to mobs, so a pinned player keeps the same icon permanently. A pure allocator turns the set of visible mobs plus the merged rule set plus the resolved seat roster into an icon map, which makes the hard logic unit testable outside the game. One designated Raid Lead allocates over the union of every participant's sightings and publishes the result; backups place icons the lead cannot reach.

**Tech Stack:** Lua 5.1 (WoW client), LuaJIT 2.1 for headless tests, PowerShell 5.1 for deploy and packaging, no external Lua libraries.

**Spec:** `Docs/specs/2026-09-03-marked-for-death-design.md`

**Scope:** This plan covers the marking engine only. The raid check subsystem ships in the same addon but has its own plan, `Docs/plans/2026-09-03-marked-for-death-raidcheck.md`. This plan produces working, testable software on its own.

## Global Constraints

Copied from the spec and `CODING_STANDARDS.md`. Every task's requirements implicitly include this section.

- **Interface version is `20506`.** Verified against `Docs/client-reference.md` and installed addons on the client. `CutMaster.toc` says `20505`; that is stale, do not copy it.
- **One global only: `MarkedForDeath`.** Every file opens with `local MFD = _G.MarkedForDeath or {}` and closes with `_G.MarkedForDeath = MFD`. No other globals except frames that must be named for `UISpecialFrames`. The existing addons in this repo deviate from this; follow the written standard, not them.
- **No WoW API calls at file scope.** Caching a global into a local at file scope is fine and expected (`local GetRaidTargetIndex = GetRaidTargetIndex`). Calling one is not. Anything that creates a frame or reads client state does it in an `:Init()` invoked from `Core.lua` on `ADDON_LOADED`. This is what lets the headless harness load logic modules.
- **`Helpers.lua`, `Seats.lua`, `Rules.lua` and `Allocator.lua` call no WoW API at all.** Hard rule. It is what makes the allocation logic testable and what lets a backup marker provably agree with the lead.
- **Four-space indentation, no tabs. Unix line endings. No trailing whitespace. Files end with a newline.**
- `local` everything not deliberately exported. Colon syntax for functions on the addon table, `local function` for pure helpers.
- Booleans named as questions (`isMarkingEnabled`, `hasAssist`). Tables named as plural nouns. Constants `UPPER_SNAKE` at file top with a comment giving the unit.
- Prefer early returns over nested `if`.
- Comments say why, not what. A comment above a function states what it takes, what it returns, and any side effect the caller must know about.
- **Every wait is a state machine with a timeout and a visible failure message.** Never loop on a condition the client might not satisfy. Every stuck state has a way out that does not need `/reload`.
- `C_Timer.After` for delays. `OnUpdate` handlers throttled with an accumulator. Frame pools over frame churn.
- **Guard every optional dependency** (check the global exists and the field is a function) and `pcall` version-variant APIs.
- Chat output is prefixed with the addon name. Errors also go to `UIErrorsFrame`. Anything that can silently do nothing prints why.
- Colors: green good, red bad, amber external or derived, grey missing.
- **Every slash command appears in `/mfd help`** with a one-line description.
- Saved variables: one account-wide table, one per-character table, both declared in the `.toc`. Every field defaulted on `ADDON_LOADED`. Migrate schema in place, keep reading the old shape for one version, never delete user data. Timestamps as `time()` integers.
- **Version must match in three places:** `## Version:` in the `.toc`, the load message in `Core.lua`, and the packaged zip name.
- Never work on `main`. This work happens on `feature/marked-for-death`, already created.
- **Do not use Bash heredocs to write multi-line Lua on this machine.** The repo skill documents that it fails on some content. Use the Write and Edit tools.
- Deploying to this client needs `-WowRoot "C:\Program Files (x86)\World of Warcraft"`, because `scripts/deploy.ps1` defaults to `D:\`.
- **LuaJIT 2.1 is installed** at `C:\Users\Dillon\AppData\Local\Programs\LuaJIT\bin\luajit.exe` and is on the persisted PATH, but a shell opened before the install will not see it. If `luajit` is not found, open a new terminal rather than reinstalling. It reports `_VERSION` as `Lua 5.1` with `unpack`, `loadfile` and `setfenv` present, matching the client exactly.

## Deliberate divergences from the spec

Found during plan self-review. Each is a simplification the spec's comms table did not anticipate, recorded here so nobody treats them as omissions.

- **No `E` (election claim) message.** The spec listed one, but it is unnecessary: every client computes `ResolveAuthority` from the same `H` peer data and the same designation, so the election result is already identical everywhere. Broadcasting a claim would add a message type whose only job is to restate a conclusion both ends already reached, plus a disagreement window if it were ever lost.
- **No `RM` (merged rules on demand) message.** `RD` is broadcast to the whole raid rather than whispered to the authority, so every client accumulates the same `contributions` table and computes the same merge locally. The traffic is identical (one broadcast either way) and the rule editor can show merged rules with provenance on every client, not just the lead's.

## How literally to take the code in this plan

Every step for a pure or logic module contains the actual code to write. The three UI tasks (11, 12 and 13) contain full code for the first window and its shared row pool, then specify the remaining two windows as required behavior, widget types and exact call sequences rather than complete frame construction. That is deliberate: WoW frame layout is long, mechanical and easier to get right against a running client than to transcribe. The behavioral requirements in those steps are binding, particularly the "every mutation of `MFD.db.rules` is followed by `BumpVersion` then `Republish`" rule, which is the most likely source of a bug in this plan.

## File Structure

```
AddonProjects/anniversary/MarkedForDeath/
    MarkedForDeath.toc     Interface, metadata, saved variables, load order
    Bindings.xml           Keybind definitions (auto-loaded, not listed in the toc)
    Core.lua               Namespace, version, event frame, saved vars, slash router, Init dispatch
    Helpers.lua            Pure: GUID parsing, defaults walk, deterministic sorting
    Data_Mobs.lua          Pure data: compiled TBC raid NPC table
    Seats.lua              Pure: intent table, default seat plan, seat ownership resolution
    Rules.lua              Pure: rule normalisation, multi-contributor merge, ranked lookup
    Allocator.lua          Pure: candidates + rules + seats -> icon map
    Candidates.lua         Live hostile unit set, pure prune core
    Marker.lua             Icon application, defense, combat lock, release, permission and CVar guards
    Comms.lua              Addon channel, send queue, designation, election, rule sync, sighting merge
    UI_Config.lua          Seat editor, settings, rule editor, mob search
    UI_Assignments.lua     Shared assignment panel and chat announcements
    Tests.lua              Test case registry and runner, ships and runs in game

scripts/
    test-harness.lua       Headless loader for the logic modules
    run-tests.ps1          LuaJIT runner wrapper

Docs/
    MarkedForDeath.md      Player guide
```

**Responsibility boundaries.** `Seats` answers "who owns which icon". `Rules` answers "what should this mob get". `Allocator` combines those two with a candidate list and answers "which icon goes on which mob", with no knowledge of how mobs were found or how icons get applied. `Candidates` answers "what mobs can we see". `Marker` answers "how do we make the client's actual icons match the desired map". `Comms` answers "whose answer wins and how does everyone agree". Each of those can be understood and changed without reading the others.

---

### Task 1: Addon skeleton, saved variables, and the headless test harness

Establishes the namespace pattern, the saved-variable defaults walk, the slash router, and the test loop that every later task depends on. Nothing marks yet.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc`
- Create: `AddonProjects/anniversary/MarkedForDeath/Core.lua`
- Create: `AddonProjects/anniversary/MarkedForDeath/Helpers.lua`
- Create: `AddonProjects/anniversary/MarkedForDeath/Tests.lua`
- Create: `scripts/test-harness.lua`
- Create: `scripts/run-tests.ps1`

**Interfaces:**
- Consumes: nothing, this is the first task.
- Produces:
  - `MFD.VERSION` (string, `"0.1.0"`)
  - `MFD.H.SplitGUID(guid) -> npcID:number|nil, spawnUID:string|nil`
  - `MFD.H.KeyFromGUID(guid) -> string|nil` formatted `"npcID:spawnUID"`
  - `MFD.H.ApplyDefaults(target:table, defaults:table) -> table` (mutates and returns target)
  - `MFD.Print(msg:string)`, `MFD.Error(msg:string)`
  - `MFD.Tests.Case(name:string, fn:function)`, `MFD.Tests.Eq(actual, expected, label)`, `MFD.Tests.Run() -> boolean`
  - `MFD.RegisterInit(fn:function)` so later modules hook `ADDON_LOADED` without touching `Core.lua`
  - Slash `/mfd` with `help`, `version`, `selftest`

- [ ] **Step 1: Write the failing test**

Create `AddonProjects/anniversary/MarkedForDeath/Tests.lua`:

```lua
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

_G.MarkedForDeath = MFD
```

Create `scripts/test-harness.lua`:

```lua
-- Headless loader for an ic-addons addon's logic modules.
-- Usage: luajit scripts/test-harness.lua <path to addon folder>
--
-- Only modules that call no WoW API at file scope can be loaded here. Caching a
-- nil global into a local is harmless; calling one is not. See the addon's plan.
local addonDir = ...
assert(addonDir, "usage: luajit scripts/test-harness.lua <addon dir>")

-- The few client globals the logic modules and the runner touch.
_G.time = _G.time or os.time
_G.GetServerTime = function() return os.time() end

local files = {
    "Helpers.lua",
    "Seats.lua",
    "Rules.lua",
    "Allocator.lua",
    "Candidates.lua",
    "Marker.lua",
    "Comms.lua",
    "Tests.lua",
}

for _, name in ipairs(files) do
    local path = addonDir .. "/" .. name
    local f = io.open(path, "r")
    if f then
        f:close()
        local chunk, err = loadfile(path)
        if not chunk then
            io.stderr:write("load error in " .. name .. ": " .. tostring(err) .. "\n")
            os.exit(1)
        end
        chunk("MarkedForDeath")
    end
end

local MFD = _G.MarkedForDeath
if not (MFD and MFD.Tests) then
    io.stderr:write("no test registry found; did Tests.lua load?\n")
    os.exit(1)
end

os.exit(MFD.Tests.Run() and 0 or 1)
```

Create `scripts/run-tests.ps1`:

```powershell
<#
.SYNOPSIS
  Run an addon's pure-module test suite headlessly with LuaJIT.

.EXAMPLE
  .\scripts\run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet("era", "anniversary", "retail")][string]$Flavor,
    [Parameter(Mandatory = $true)][string]$Addon
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$addonDir = Join-Path $repoRoot "AddonProjects\$Flavor\$Addon"

if (-not (Test-Path $addonDir)) {
    Write-Error "No addon folder at $addonDir"
    exit 1
}

$luajit = Get-Command luajit -ErrorAction SilentlyContinue
if (-not $luajit) {
    Write-Error "luajit is not on PATH. Install it with: winget install --id DEVCOM.LuaJIT"
    exit 1
}

& $luajit.Source (Join-Path $PSScriptRoot "test-harness.lua") ($addonDir -replace '\\', '/')
exit $LASTEXITCODE
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: exits non-zero with `no test registry found` or a load error, because `Helpers.lua` does not exist yet and `Tests.lua` references `MFD.H.SplitGUID`.

- [ ] **Step 3: Write Helpers.lua**

Create `AddonProjects/anniversary/MarkedForDeath/Helpers.lua`:

```lua
-- Pure helpers. This file must never call a WoW API, so that it loads under the
-- headless test harness. Caching globals into locals is fine; calling is not.
local MFD = _G.MarkedForDeath or {}

MFD.H = MFD.H or {}
local H = MFD.H

-- GUID kinds that can carry a raid target icon. Player GUIDs have a different
-- shape and are rejected by the pattern anyway; this guards the rest.
local MARKABLE_GUID_TYPES = {
    Creature = true,
    Vehicle = true,
    Pet = true,
}

-- Takes a unit GUID string. Returns npcID as a number and spawnUID as a string,
-- or nil when the GUID is not a markable creature-shaped GUID. No side effects.
function H.SplitGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end

    local kind, npcID, spawnUID = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-(%x+)$")
    if not kind or not MARKABLE_GUID_TYPES[kind] then
        return nil
    end

    return tonumber(npcID), spawnUID
end

-- Takes a unit GUID. Returns the compact wire key "npcID:spawnUID" used as the
-- identity for a mob across the addon channel, or nil. Both ends of a message
-- derive this the same way, which is why full GUIDs never go over the wire.
function H.KeyFromGUID(guid)
    local npcID, spawnUID = H.SplitGUID(guid)
    if not npcID then
        return nil
    end
    return npcID .. ":" .. spawnUID
end

-- Takes a compact key. Returns the npcID as a number, or nil.
function H.NpcIDFromKey(key)
    if type(key) ~= "string" then
        return nil
    end
    return tonumber(key:match("^(%d+):"))
end

-- Fills every key of defaults that is missing from target, recursing into
-- tables. Mutates and returns target. Existing values are never overwritten,
-- which is what makes it safe to call on every ADDON_LOADED.
function H.ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            H.ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Returns a deep copy of t. Used when a merged rule is edited into the local
-- set, so the caller never aliases another contributor's table.
function H.DeepCopy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = H.DeepCopy(v)
    end
    return out
end

-- Returns the keys of t as an array sorted ascending by tostring. Table
-- iteration order is undefined in Lua, so anything whose result must match
-- across clients iterates through this instead of pairs().
function H.SortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

_G.MarkedForDeath = MFD
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `4 passed, 0 failed, 4 total`, exit code 0.

- [ ] **Step 5: Write the TOC and Core**

Create `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc`:

```
## Interface: 20506
## Title: Marked For Death
## Notes: Automatic raid target icons for trash by kill priority and crowd control intent, plus a raid buff and consumable check.
## Author: dillon_newport
## Version: 0.1.0
## SavedVariables: MarkedForDeathDB
## SavedVariablesPerCharacter: MarkedForDeathCharDB

Helpers.lua
Data_Mobs.lua
Seats.lua
Rules.lua
Allocator.lua
Candidates.lua
Marker.lua
Comms.lua
Core.lua
Tests.lua
UI_Config.lua
UI_Assignments.lua
```

`Data_Mobs.lua` through `Comms.lua` are created by later tasks. Add each filename to this list only in the task that creates the file, or the client will fail to load. For Task 1, the list is `Helpers.lua`, `Core.lua`, `Tests.lua` only.

Create `AddonProjects/anniversary/MarkedForDeath/Core.lua`:

```lua
-- Namespace, saved variables, event dispatch and the slash router.
local MFD = _G.MarkedForDeath or {}

-- Must match ## Version: in the toc and the packaged zip name.
MFD.VERSION = "0.1.0"

-- Bumped only when the saved-variable shape changes in a way that needs a
-- migration. See MFD:MigrateDB.
local SCHEMA_VERSION = 1

local CHAT_PREFIX = "|cff33ff99Marked For Death|r: "

local inits = {}

-- Registers fn to run once on ADDON_LOADED, after saved variables are ready.
-- Modules use this instead of creating frames or reading client state at file
-- scope, which is what keeps them loadable under the headless test harness.
function MFD.RegisterInit(fn)
    inits[#inits + 1] = fn
end

function MFD.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(msg))
end

-- Prints to chat and also to the on-screen error area, per the repo standard
-- that errors are visible without watching the chat frame.
function MFD.Error(msg)
    MFD.Print("|cffff4444" .. tostring(msg) .. "|r")
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage("Marked For Death: " .. tostring(msg), 1, 0.3, 0.3)
    end
end

local DB_DEFAULTS = {
    schemaVersion = SCHEMA_VERSION,
    seatPlan = {},
    rules = {},
    rulesVersion = { counter = 0, hash = "" },
    designatedLead = { name = "", setBy = "", setAt = 0 },
    learnedMobs = {},
    settings = {
        isMarkingEnabled = true,
        isAnnounceEnabled = true,
        isCvarWarnEnabled = true,
    },
    lastTestRun = {},
}

local CHAR_DB_DEFAULTS = {
    windows = {},
}

-- Migrates an existing saved-variable table in place. Reads the previous shape
-- for one version and never deletes user data.
function MFD:MigrateDB()
    local db = MarkedForDeathDB
    if not db.schemaVersion then
        db.schemaVersion = SCHEMA_VERSION
    end
end

local function onAddonLoaded()
    MarkedForDeathDB = MarkedForDeathDB or {}
    MarkedForDeathCharDB = MarkedForDeathCharDB or {}

    MFD:MigrateDB()
    MFD.H.ApplyDefaults(MarkedForDeathDB, DB_DEFAULTS)
    MFD.H.ApplyDefaults(MarkedForDeathCharDB, CHAR_DB_DEFAULTS)

    MFD.db = MarkedForDeathDB
    MFD.charDb = MarkedForDeathCharDB

    for _, fn in ipairs(inits) do
        local ok, err = pcall(fn)
        if not ok then
            MFD.Error("init failed: " .. tostring(err))
        end
    end

    MFD.Print("v" .. MFD.VERSION .. " loaded. /mfd help for commands.")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "MarkedForDeath" then
        onAddonLoaded()
    end
end)

-- Slash commands. Every entry here must also appear in the help output below,
-- which is enforced by the review checklist rather than by code.
local commands = {}

commands.help = {
    desc = "list commands",
    run = function()
        MFD.Print("commands:")
        for _, name in ipairs(MFD.H.SortedKeys(commands)) do
            MFD.Print("  /mfd " .. name .. " - " .. commands[name].desc)
        end
    end,
}

commands.version = {
    desc = "print the addon version",
    run = function()
        MFD.Print("version " .. MFD.VERSION)
    end,
}

commands.selftest = {
    desc = "run the test suite in game",
    run = function()
        if not MFD.Tests then
            MFD.Error("test suite not loaded")
            return
        end
        MFD.Tests.Run()
    end,
}

MFD.commands = commands

SLASH_MARKEDFORDEATH1 = "/mfd"
SLASH_MARKEDFORDEATH2 = "/markedfordeath"
SlashCmdList["MARKEDFORDEATH"] = function(input)
    local cmd, rest = string.match(input or "", "^(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")

    if cmd == "" then
        cmd = "help"
    end

    local entry = commands[cmd]
    if not entry then
        MFD.Error("unknown command '" .. cmd .. "'. Try /mfd help.")
        return
    end

    entry.run(rest)
end

_G.MarkedForDeath = MFD
```

- [ ] **Step 6: Deploy and verify in game**

Run: `powershell -File scripts/deploy.ps1 -Flavor anniversary -Addon MarkedForDeath -WowRoot "C:\Program Files (x86)\World of Warcraft"`

In game, with "Load out of date AddOns" unticked:
1. `/reload`
2. Confirm the chat line `Marked For Death: v0.1.0 loaded. /mfd help for commands.`
3. `/mfd help` lists help, selftest, version
4. `/mfd selftest` prints `4 passed, 0 failed, 4 total`
5. `/mfd bogus` prints the unknown-command error
6. BugSack is empty

- [ ] **Step 7: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath scripts/test-harness.lua scripts/run-tests.ps1
git commit -m "Add MarkedForDeath skeleton and headless test harness"
```

---

### Task 2: Seats

Pure. Turns a seat plan plus a raid roster into resolved seat ownership. This is the module that makes Grimmtusk permanently Moon.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/Seats.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` (add `Seats.lua` before `Core.lua`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append cases)

**Interfaces:**
- Consumes: `MFD.H.SortedKeys` from Task 1.
- Produces:
  - `MFD.Seats.INTENTS` -> `{ [intent] = { classes = {CLASSTOKEN,...} or nil, label = string } }`. `classes = nil` means no owner required (KILL).
  - `MFD.Seats.DEFAULT_PLAN` -> `{ [icon] = { intent, ordinal, pin } }`
  - `MFD.Seats.Resolve(seatPlan, roster) -> resolved`
    - `seatPlan`: `{ [icon:number] = { intent:string, ordinal:number, pin:string|nil } }`
    - `roster`: array of `{ name:string, class:string }`, class is an uppercase token like `"MAGE"`
    - `resolved`: `{ byIntent = { [intent] = array of { icon, ordinal, owner } sorted by ordinal }, byIcon = { [icon] = { intent, ordinal, owner } } }`. `owner` is a name string, or `false` when the seat is unowned, or `true` when the intent needs no owner.

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua`, immediately before the final `_G.MarkedForDeath = MFD` line:

```lua
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the seven new cases fail with `attempt to index field 'Seats' (a nil value)`.

- [ ] **Step 3: Write Seats.lua**

Create `AddonProjects/anniversary/MarkedForDeath/Seats.lua`:

```lua
-- Seat model. An icon binds to a seat, a seat is a durable job in the raid, and
-- a mob rule only names an intent. This file must never call a WoW API.
local MFD = _G.MarkedForDeath or {}

MFD.Seats = MFD.Seats or {}
local Seats = MFD.Seats

-- classes = nil means the intent needs no owner, so its seats are always
-- available. Anything with a class list is skipped entirely when nobody in the
-- raid can perform it, and its mobs resolve through their rule's fallback.
Seats.INTENTS = {
    KILL        = { label = "Kill",          classes = nil },
    SHEEP       = { label = "Sheep",         classes = { "MAGE" } },
    TRAP        = { label = "Trap",          classes = { "HUNTER" } },
    BANISH      = { label = "Banish",        classes = { "WARLOCK" } },
    SEDUCE      = { label = "Seduce",        classes = { "WARLOCK" } },
    ENSLAVE     = { label = "Enslave",       classes = { "WARLOCK" } },
    FEAR        = { label = "Fear",          classes = { "WARLOCK", "PRIEST" } },
    SAP         = { label = "Sap",           classes = { "ROGUE" } },
    SHACKLE     = { label = "Shackle",       classes = { "PRIEST" } },
    MINDCONTROL = { label = "Mind Control",  classes = { "PRIEST" } },
    HIBERNATE   = { label = "Hibernate",     classes = { "DRUID" } },
    ROOTS       = { label = "Roots",         classes = { "DRUID" } },
    REPENTANCE  = { label = "Repentance",    classes = { "PALADIN" } },
    IGNORE      = { label = "Never mark",    classes = nil },
}

-- Raid target icon indices, named so the plan below reads as intended.
local STAR, CIRCLE, DIAMOND, TRIANGLE, MOON, SQUARE, CROSS, SKULL = 1, 2, 3, 4, 5, 6, 7, 8

Seats.DEFAULT_PLAN = {
    [SKULL]    = { intent = "KILL",   ordinal = 1 },
    [CROSS]    = { intent = "KILL",   ordinal = 2 },
    [SQUARE]   = { intent = "KILL",   ordinal = 3 },
    [CIRCLE]   = { intent = "KILL",   ordinal = 4 },
    [MOON]     = { intent = "SHEEP",  ordinal = 1, pin = "Grimmtusk" },
    [STAR]     = { intent = "SHEEP",  ordinal = 2 },
    [TRIANGLE] = { intent = "BANISH", ordinal = 1 },
    [DIAMOND]  = { intent = "BANISH", ordinal = 2 },
}

local function isEligible(intent, class)
    local classes = Seats.INTENTS[intent] and Seats.INTENTS[intent].classes
    if not classes then
        return false
    end
    for _, c in ipairs(classes) do
        if c == class then
            return true
        end
    end
    return false
end

-- Takes a seat plan and a roster array of { name, class }. Returns
-- { byIntent = { [intent] = array of { icon, ordinal, owner } ordered by
-- ordinal }, byIcon = { [icon] = the same record } }.
--
-- owner is true when the intent needs no owner, a player name when a seat has
-- one, and false when the seat exists but nobody can fill it. Ordering is by
-- pin first then player name ascending, which is identical on every client and
-- is why backup markers agree without negotiating.
function Seats.Resolve(seatPlan, roster)
    local byIntent, byIcon = {}, {}

    for _, icon in ipairs(MFD.H.SortedKeys(seatPlan)) do
        local seat = seatPlan[icon]
        local record = { icon = icon, ordinal = seat.ordinal, pin = seat.pin, owner = false }
        byIntent[seat.intent] = byIntent[seat.intent] or {}
        table.insert(byIntent[seat.intent], record)
        byIcon[icon] = record
    end

    for _, records in pairs(byIntent) do
        table.sort(records, function(a, b)
            if a.ordinal ~= b.ordinal then
                return a.ordinal < b.ordinal
            end
            return a.icon < b.icon
        end)
    end

    -- Candidate owners per intent, sorted by name so the result is
    -- deterministic across clients without any coordination.
    local sortedRoster = {}
    for _, member in ipairs(roster) do
        sortedRoster[#sortedRoster + 1] = member
    end
    table.sort(sortedRoster, function(a, b) return a.name < b.name end)

    for intent, records in pairs(byIntent) do
        if not (Seats.INTENTS[intent] and Seats.INTENTS[intent].classes) then
            for _, record in ipairs(records) do
                record.owner = true
            end
        else
            local taken = {}

            -- Pins first, so a pinned player keeps their icon regardless of
            -- where they sort by name.
            for _, record in ipairs(records) do
                if record.pin then
                    for _, member in ipairs(sortedRoster) do
                        if member.name == record.pin and isEligible(intent, member.class) then
                            record.owner = member.name
                            taken[member.name] = true
                            break
                        end
                    end
                end
            end

            for _, record in ipairs(records) do
                if not record.owner then
                    for _, member in ipairs(sortedRoster) do
                        if not taken[member.name] and isEligible(intent, member.class) then
                            record.owner = member.name
                            taken[member.name] = true
                            break
                        end
                    end
                end
            end
        end
    end

    return { byIntent = byIntent, byIcon = byIcon }
end

_G.MarkedForDeath = MFD
```

- [ ] **Step 4: Add Seats.lua to the TOC**

Edit `MarkedForDeath.toc` so the file list reads:

```
Helpers.lua
Seats.lua
Core.lua
Tests.lua
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `11 passed, 0 failed, 11 total`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add seat model with pinned and roster-filled ownership"
```

---

### Task 3: Rules

Pure. Normalises rules, merges contributions from multiple players with the Raid Lead winning conflicts, and produces a ranked lookup for one instance.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/Rules.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` (add `Rules.lua` after `Seats.lua`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append cases)

**Interfaces:**
- Consumes: `MFD.H.SortedKeys`, `MFD.H.DeepCopy` from Task 1.
- Produces:
  - `MFD.Rules.RANK_STEP` -> `10`
  - `MFD.Rules.Merge(contributions, leadName) -> { [instanceKey] = { [npcID] = rule } }` where each returned rule carries `owner` naming the contributor it came from.
    - `contributions`: array of `{ owner = string, rules = { [instanceKey] = array of rule } }`
    - a rule is `{ npcID, name, intent, rank, fallback, maxCount }`
  - `MFD.Rules.Ranked(byNpcID) -> array of rule sorted by (rank asc, npcID asc)`
  - `MFD.Rules.NextRank(list) -> number`, the rank to give a newly appended rule
  - `MFD.Rules.Reorder(list, index, delta) -> list`, moves one rule up or down and rewrites ranks spaced by `RANK_STEP`

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua`, before the final `_G.MarkedForDeath = MFD` line:

```lua
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the nine new cases fail with `attempt to index field 'Rules' (a nil value)`.

- [ ] **Step 3: Write Rules.lua**

Create `AddonProjects/anniversary/MarkedForDeath/Rules.lua`:

```lua
-- Rule storage, multi-contributor merging and ranked lookup. This file must
-- never call a WoW API.
--
-- Rules carry an explicit rank rather than deriving priority from list
-- position, because two contributors' orderings for one instance have no
-- defined interleaving. Positions cannot merge; ranks sort.
local MFD = _G.MarkedForDeath or {}

MFD.Rules = MFD.Rules or {}
local Rules = MFD.Rules

-- Gap between adjacent ranks, so inserting between two rules rarely needs a
-- full renumber.
Rules.RANK_STEP = 10

-- Takes an array of { owner, rules = { [instanceKey] = array of rule } } and
-- the designated Raid Lead's name. Returns
-- { [instanceKey] = { [npcID] = rule } } where every rule carries an owner
-- field naming the contributor it came from.
--
-- Conflict resolution: the lead's rule wins outright, including its rank.
-- Otherwise the lowest contributor name ascending wins. Both are deterministic,
-- so every client computes the same table from the same inputs regardless of
-- the order contributions arrived in.
function Rules.Merge(contributions, leadName)
    local byOwner = {}
    for _, c in ipairs(contributions) do
        byOwner[c.owner] = c
    end

    local owners = MFD.H.SortedKeys(byOwner)
    local merged = {}

    local function absorb(contribution)
        for _, instanceKey in ipairs(MFD.H.SortedKeys(contribution.rules)) do
            merged[instanceKey] = merged[instanceKey] or {}
            for _, rule in ipairs(contribution.rules[instanceKey]) do
                if merged[instanceKey][rule.npcID] == nil then
                    local copy = MFD.H.DeepCopy(rule)
                    copy.owner = contribution.owner
                    merged[instanceKey][rule.npcID] = copy
                end
            end
        end
    end

    -- The lead goes first, so its rules claim every npcID they cover and later
    -- contributors can only fill gaps.
    if byOwner[leadName] then
        absorb(byOwner[leadName])
    end

    for _, owner in ipairs(owners) do
        if owner ~= leadName then
            absorb(byOwner[owner])
        end
    end

    return merged
end

-- Takes { [npcID] = rule }. Returns an array sorted by rank ascending, then
-- npcID ascending. The npcID tiebreak is what keeps two clients in agreement
-- when two rules share a rank.
function Rules.Ranked(byNpcID)
    local list = {}
    for _, npcID in ipairs(MFD.H.SortedKeys(byNpcID)) do
        list[#list + 1] = byNpcID[npcID]
    end

    table.sort(list, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.npcID < b.npcID
    end)

    return list
end

-- Returns the rank a newly appended rule should take.
function Rules.NextRank(list)
    local highest = 0
    for _, rule in ipairs(list) do
        if rule.rank > highest then
            highest = rule.rank
        end
    end
    return highest + Rules.RANK_STEP
end

-- Moves list[index] by delta places and rewrites every rank to a clean
-- multiple of RANK_STEP. Mutates and returns list. Out-of-range moves are a
-- no-op, so the caller can wire arrow buttons without bounds checks.
function Rules.Reorder(list, index, delta)
    local target = index + delta
    if target < 1 or target > #list or index < 1 or index > #list then
        return list
    end

    local moved = table.remove(list, index)
    table.insert(list, target, moved)

    for i, rule in ipairs(list) do
        rule.rank = i * Rules.RANK_STEP
    end

    return list
end

_G.MarkedForDeath = MFD
```

- [ ] **Step 4: Add Rules.lua to the TOC**

Edit `MarkedForDeath.toc` so the file list reads:

```
Helpers.lua
Seats.lua
Rules.lua
Core.lua
Tests.lua
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `20 passed, 0 failed, 20 total`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add rule merging with lead-wins conflict resolution"
```

---

### Task 4: Allocator

Pure, and the centre of the addon. Turns a candidate list plus merged rules plus resolved seats into an icon map. Every duplicate-mark and wrong-priority failure the user reported is a bug this module's tests catch.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/Allocator.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` (add `Allocator.lua` after `Rules.lua`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append cases)

**Interfaces:**
- Consumes: `MFD.Seats.Resolve` output shape from Task 2, `MFD.Rules.Merge` rule shape from Task 3, `MFD.H.SortedKeys` from Task 1.
- Produces:
  - `MFD.Allocator.Compute(candidates, rulesByNpcID, seats, locked) -> { list, byKey }`
    - `candidates`: array of `{ key:string, npcID:number }`
    - `rulesByNpcID`: `{ [npcID] = { intent, rank, fallback, maxCount } }`
    - `seats`: the table returned by `MFD.Seats.Resolve`
    - `locked`: `{ [key] = icon:number }` or nil
    - `list`: array of `{ key, icon, intent, owner }` where `owner` is a player name string or nil
    - `byKey`: `{ [key] = icon }`

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua`, before the final `_G.MarkedForDeath = MFD` line:

```lua
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the twelve new cases fail with `attempt to index field 'Allocator' (a nil value)`.

- [ ] **Step 3: Write Allocator.lua**

Create `AddonProjects/anniversary/MarkedForDeath/Allocator.lua`:

```lua
-- The allocator. Given what we can see, what the rules say and who owns which
-- seat, decide which icon goes on which mob.
--
-- This function is pure and its result depends only on its arguments, never on
-- table iteration order or on the order mobs were sighted. That property is
-- what removes the nameplate-arrival dependency that scrambles priority in
-- other addons, and it is what lets a backup marker agree with the lead
-- without negotiating. This file must never call a WoW API.
local MFD = _G.MarkedForDeath or {}

MFD.Allocator = MFD.Allocator or {}
local Allocator = MFD.Allocator

-- Returns the icon of the lowest-ordinal seat of intent that is both free and
-- owned, or nil. A seat whose owner is false exists but nobody in the raid can
-- perform it, so it is not usable.
local function takeSeat(seats, intent, usedIcons)
    local records = seats.byIntent[intent]
    if not records then
        return nil
    end

    for _, record in ipairs(records) do
        if not usedIcons[record.icon] and record.owner then
            return record.icon, record.owner
        end
    end

    return nil
end

-- Takes:
--   candidates    array of { key, npcID }
--   rulesByNpcID  { [npcID] = { intent, rank, fallback, maxCount } }
--   seats         the table returned by MFD.Seats.Resolve
--   locked        { [key] = icon } or nil, assignments frozen at combat start
--
-- Returns { list = array of { key, icon, intent, owner }, byKey = { [key] = icon } }.
-- Has no side effects and does not mutate any argument.
function Allocator.Compute(candidates, rulesByNpcID, seats, locked)
    locked = locked or {}

    local usedIcons, countByNpcID = {}, {}
    local list, byKey = {}, {}

    local byKeyCandidate = {}
    for _, candidate in ipairs(candidates) do
        byKeyCandidate[candidate.key] = candidate
    end

    local function record(key, icon, intent, owner, npcID)
        usedIcons[icon] = true
        countByNpcID[npcID] = (countByNpcID[npcID] or 0) + 1
        byKey[key] = icon
        list[#list + 1] = {
            key = key,
            icon = icon,
            intent = intent,
            owner = type(owner) == "string" and owner or nil,
        }
    end

    -- Locks first, so a frozen assignment keeps its icon and its seat even when
    -- a better mob has since walked into range.
    for _, key in ipairs(MFD.H.SortedKeys(locked)) do
        local candidate = byKeyCandidate[key]
        local icon = locked[key]
        local seat = seats.byIcon[icon]
        if candidate and seat and not usedIcons[icon] then
            local rule = rulesByNpcID[candidate.npcID]
            record(key, icon, rule and rule.intent or seat.intent, seat.owner, candidate.npcID)
        end
    end

    -- Everything else, in priority order. The key tiebreak makes the sort total
    -- so two clients never disagree on a tie.
    local eligible = {}
    for _, candidate in ipairs(candidates) do
        local rule = rulesByNpcID[candidate.npcID]
        if rule and rule.intent ~= "IGNORE" and not byKey[candidate.key] then
            eligible[#eligible + 1] = { candidate = candidate, rule = rule }
        end
    end

    table.sort(eligible, function(a, b)
        if a.rule.rank ~= b.rule.rank then
            return a.rule.rank < b.rule.rank
        end
        return a.candidate.key < b.candidate.key
    end)

    for _, entry in ipairs(eligible) do
        local candidate, rule = entry.candidate, entry.rule
        local used = countByNpcID[candidate.npcID] or 0

        if not rule.maxCount or used < rule.maxCount then
            local icon, owner = takeSeat(seats, rule.intent, usedIcons)
            local intent = rule.intent

            if not icon and rule.fallback then
                icon, owner = takeSeat(seats, rule.fallback, usedIcons)
                intent = rule.fallback
            end

            if icon then
                record(candidate.key, icon, intent, owner, candidate.npcID)
            end
        end
    end

    return { list = list, byKey = byKey }
end

_G.MarkedForDeath = MFD
```

- [ ] **Step 4: Add Allocator.lua to the TOC**

Edit `MarkedForDeath.toc` so the file list reads:

```
Helpers.lua
Seats.lua
Rules.lua
Allocator.lua
Core.lua
Tests.lua
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `32 passed, 0 failed, 32 total`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add pure allocator with rank ordering and seat allocation"
```

---

### Task 5: Candidates

The live set of observable hostile units. The pruning and list-building logic is pure and tested; only event registration touches the client.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/Candidates.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` (add `Candidates.lua` after `Allocator.lua`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append cases)

**Interfaces:**
- Consumes: `MFD.H.KeyFromGUID`, `MFD.H.SortedKeys` from Task 1; `MFD.RegisterInit` from Task 1.
- Produces:
  - `MFD.Candidates.GRACE_SECONDS` -> `3`
  - `MFD.Candidates.Prune(set, now, grace) -> array of removed keys` (mutates `set`)
  - `MFD.Candidates.ToList(set) -> array of { key, npcID }` sorted by key ascending
  - `MFD.Candidates.Observe(set, key, npcID, unit, now)` (mutates `set`)
  - `MFD.Candidates.Lose(set, key, now)` (mutates `set`, clears `unit` and stamps `lostAt`)
  - `MFD.Candidates.set` -> the live set, populated by events after `Init`
  - A set entry is `{ key, npcID, unit, seenAt, lostAt }`. `unit` is nil once the nameplate is gone; `lostAt` is nil while it is present.

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua`, before the final `_G.MarkedForDeath = MFD` line:

```lua
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the five new cases fail with `attempt to index field 'Candidates' (a nil value)`.

- [ ] **Step 3: Write Candidates.lua**

Create `AddonProjects/anniversary/MarkedForDeath/Candidates.lua`:

```lua
-- The live set of observable hostile units.
--
-- The set-manipulation functions are pure so they can be tested headlessly.
-- Only Init and the event handler touch the client, and neither runs at file
-- scope.
local MFD = _G.MarkedForDeath or {}

MFD.Candidates = MFD.Candidates or {}
local Candidates = MFD.Candidates

-- Seconds a unit stays in the set after its nameplate disappears. A nameplate
-- that flickers as the camera turns would otherwise churn the pack and cause
-- the allocator to reshuffle icons for no reason.
Candidates.GRACE_SECONDS = 3

local UnitGUID = UnitGUID
local UnitIsEnemy = UnitIsEnemy
local UnitIsDead = UnitIsDead

Candidates.set = {}

-- Records or refreshes a unit in set. Mutates set. Reobserving a unit that had
-- been lost restores its unit token and clears the loss stamp, so it will not
-- be pruned.
function Candidates.Observe(set, key, npcID, unit, now)
    local entry = set[key]
    if not entry then
        entry = { key = key, npcID = npcID }
        set[key] = entry
    end

    entry.unit = unit
    entry.seenAt = now
    entry.lostAt = nil
end

-- Marks a unit as no longer visible. Mutates set. The entry is kept until
-- Prune decides the grace window has passed.
function Candidates.Lose(set, key, now)
    local entry = set[key]
    if not entry then
        return
    end

    entry.unit = nil
    entry.lostAt = now
end

-- Removes entries lost longer than grace seconds ago. Mutates set. Returns an
-- array of the removed keys so the caller can release their seats.
function Candidates.Prune(set, now, grace)
    local removed = {}

    for _, key in ipairs(MFD.H.SortedKeys(set)) do
        local entry = set[key]
        if entry.lostAt and (entry.lostAt + grace) < now then
            removed[#removed + 1] = key
            set[key] = nil
        end
    end

    return removed
end

-- Returns the set as an array of { key, npcID } sorted by key ascending. The
-- allocator sorts again by rank, but starting from a deterministic order means
-- two clients with the same set always produce the same result.
function Candidates.ToList(set)
    local list = {}

    for _, key in ipairs(MFD.H.SortedKeys(set)) do
        list[#list + 1] = { key = key, npcID = set[key].npcID }
    end

    return list
end

-- Reads a unit token and records it if it is a live hostile creature. Returns
-- the key it recorded, or nil. Touches the client, so it is never called at
-- file scope.
function Candidates.ObserveUnit(unit, now)
    if not unit or not UnitGUID then
        return nil
    end

    local guid = UnitGUID(unit)
    if not guid then
        return nil
    end

    local key = MFD.H.KeyFromGUID(guid)
    if not key then
        return nil
    end

    if UnitIsDead and UnitIsDead(unit) then
        return nil
    end

    if UnitIsEnemy and not UnitIsEnemy("player", unit) then
        return nil
    end

    local npcID = MFD.H.NpcIDFromKey(key)
    Candidates.Observe(Candidates.set, key, npcID, unit, now)
    return key
end

local frame

MFD.RegisterInit(function()
    frame = CreateFrame("Frame")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:RegisterEvent("UNIT_TARGET")
    frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")

    frame:SetScript("OnEvent", function(_, event, unit)
        local now = GetTime()

        if event == "NAME_PLATE_UNIT_ADDED" then
            Candidates.ObserveUnit(unit, now)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            local guid = UnitGUID(unit)
            local key = guid and MFD.H.KeyFromGUID(guid)
            if key then
                Candidates.Lose(Candidates.set, key, now)
            end
        elseif event == "UNIT_TARGET" then
            Candidates.ObserveUnit(unit .. "target", now)
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            Candidates.ObserveUnit("mouseover", now)
        elseif event == "PLAYER_TARGET_CHANGED" then
            Candidates.ObserveUnit("target", now)
        end
    end)
end)

_G.MarkedForDeath = MFD
```

- [ ] **Step 4: Add Candidates.lua to the TOC**

Edit `MarkedForDeath.toc` so the file list reads:

```
Helpers.lua
Seats.lua
Rules.lua
Allocator.lua
Candidates.lua
Core.lua
Tests.lua
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `37 passed, 0 failed, 37 total`, exit code 0.

- [ ] **Step 6: Add a diagnostic command and verify in game**

Add to `Core.lua`, alongside the other command definitions:

```lua
commands.candidates = {
    desc = "list the hostile units the addon can currently see",
    run = function()
        local list = MFD.Candidates.ToList(MFD.Candidates.set)
        if #list == 0 then
            MFD.Print("no candidates visible. Are enemy nameplates enabled?")
            return
        end
        for _, c in ipairs(list) do
            MFD.Print(string.format("  %s (npc %d)", c.key, c.npcID))
        end
    end,
}
```

Deploy and verify in game:
1. `powershell -File scripts/deploy.ps1 -Flavor anniversary -Addon MarkedForDeath -WowRoot "C:\Program Files (x86)\World of Warcraft"`
2. `/reload`
3. Stand in a zone with enemies and enemy nameplates enabled. Run `/mfd candidates` and confirm it lists the mobs on screen with plausible npc ids.
4. Turn away so the nameplates drop. Wait five seconds, run `/mfd candidates` again, and confirm the list has shrunk.
5. Turn off enemy nameplates, `/reload`, run `/mfd candidates` and confirm it prints the nameplate hint rather than an empty list.
6. `/mfd selftest` reports 37 passed.
7. BugSack is empty.

- [ ] **Step 7: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add candidate set with grace-window pruning"
```

---

### Task 6: Marker

Applies the desired icon map to the client, defends icons that get cleared, freezes on combat and releases seats on death. The diff and defense logic is pure and tested; only the `SetRaidTarget` call and the permission checks are not.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/Marker.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` (add `Marker.lua` after `Candidates.lua`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Core.lua` (add `mark`, `clear`, `fixcvars` commands)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append cases)

**Interfaces:**
- Consumes: `MFD.Candidates.set`, `MFD.Candidates.ToList`, `MFD.Candidates.Prune` from Task 5; `MFD.Allocator.Compute` from Task 4; `MFD.Seats.Resolve` from Task 2; `MFD.RegisterInit`, `MFD.Print`, `MFD.Error` from Task 1.
- Produces:
  - `MFD.Marker.LIMITS` -> `{ maxActions = 4, defenseLimit = 3, defenseWindow = 5, tickInterval = 0.2 }` (counts, counts, seconds, seconds)
  - `MFD.Marker.ComputeDiff(desired, actual, defense, now, limits) -> { actions, yielded }`
    - `desired`: `{ [key] = icon }`
    - `actual`: `{ [key] = icon }`, icon absent or 0 when the mob carries none
    - `defense`: `{ [key] = { count, windowStart } }`, mutated in place by this call
    - `actions`: array of `{ key, icon, isDefense }`, sorted by key, at most `limits.maxActions` long
    - `yielded`: array of keys the addon has stopped fighting over
  - `MFD.Marker.locked` -> `{ [key] = icon }`
  - `MFD.Marker:CanMark() -> boolean, reason:string`
  - `MFD.Marker:CheckCvars() -> boolean, message:string`

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua`, before the final `_G.MarkedForDeath = MFD` line:

```lua
local MARKER_LIMITS = { maxActions = 4, defenseLimit = 3, defenseWindow = 5 }

T.Case("Marker: an unmarked mob produces a fresh apply", function()
    local out = MFD.Marker.ComputeDiff({ ["100:AAA"] = 8 }, {}, {}, 100, MARKER_LIMITS)
    T.Eq(#out.actions, 1, "one action")
    T.Eq(out.actions[1].icon, 8, "the desired icon")
    T.Eq(out.actions[1].isDefense, false, "a first placement is not a defense")
end)

T.Case("Marker: a mob already carrying the desired icon produces nothing", function()
    local out = MFD.Marker.ComputeDiff({ ["100:AAA"] = 8 }, { ["100:AAA"] = 8 }, {}, 100, MARKER_LIMITS)
    T.Eq(#out.actions, 0, "no work to do")
end)

T.Case("Marker: a cleared icon is re-applied as a defense", function()
    local defense = {}
    local out = MFD.Marker.ComputeDiff({ ["100:AAA"] = 8 }, { ["100:AAA"] = 0 }, defense, 100, MARKER_LIMITS)
    T.Eq(out.actions[1].isDefense, true, "counted as a defense")
    T.Eq(defense["100:AAA"].count, 1, "defense counter incremented")
end)

T.Case("Marker: defending stops after the limit inside the window", function()
    local defense = {}
    local desired, actual = { ["100:AAA"] = 8 }, { ["100:AAA"] = 0 }

    for i = 1, 3 do
        local out = MFD.Marker.ComputeDiff(desired, actual, defense, 100 + i, MARKER_LIMITS)
        T.Eq(#out.actions, 1, "defense " .. i .. " still acts")
    end

    local out = MFD.Marker.ComputeDiff(desired, actual, defense, 104, MARKER_LIMITS)
    T.Eq(#out.actions, 0, "fourth attempt inside the window yields")
    T.Eq(out.yielded[1], "100:AAA", "and reports which key it gave up on")
end)

T.Case("Marker: the defense window resets so a later clear is fought again", function()
    local defense = {}
    local desired, actual = { ["100:AAA"] = 8 }, { ["100:AAA"] = 0 }

    for i = 1, 3 do
        MFD.Marker.ComputeDiff(desired, actual, defense, 100 + i, MARKER_LIMITS)
    end

    local out = MFD.Marker.ComputeDiff(desired, actual, defense, 200, MARKER_LIMITS)
    T.Eq(#out.actions, 1, "a fresh window means we defend again")
    T.Eq(defense["100:AAA"].count, 1, "counter restarted")
end)

T.Case("Marker: actions are capped so a big pull does not burst", function()
    local desired = {}
    for i = 1, 10 do
        desired["10" .. i .. ":AAA"] = 1
    end
    local out = MFD.Marker.ComputeDiff(desired, {}, {}, 100, MARKER_LIMITS)
    T.Eq(#out.actions, 4, "capped at maxActions")
end)

T.Case("Marker: actions come out in a deterministic order", function()
    local desired = { ["300:CCC"] = 1, ["100:AAA"] = 2, ["200:BBB"] = 3 }
    local out = MFD.Marker.ComputeDiff(desired, {}, {}, 100, MARKER_LIMITS)
    T.Eq(out.actions[1].key, "100:AAA", "sorted by key")
    T.Eq(out.actions[2].key, "200:BBB", "second")
    T.Eq(out.actions[3].key, "300:CCC", "third")
end)

T.Case("Marker: a mob carrying the wrong icon is corrected", function()
    local out = MFD.Marker.ComputeDiff({ ["100:AAA"] = 8 }, { ["100:AAA"] = 5 }, {}, 100, MARKER_LIMITS)
    T.Eq(out.actions[1].icon, 8, "corrected to the desired icon")
    T.Eq(out.actions[1].isDefense, true, "an existing wrong icon counts as a defense")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the eight new cases fail with `attempt to index field 'Marker' (a nil value)`.

- [ ] **Step 3: Write Marker.lua**

Create `AddonProjects/anniversary/MarkedForDeath/Marker.lua`:

```lua
-- Makes the client's actual raid target icons match the desired map.
--
-- ComputeDiff is pure and carries the defense brake, which is the difference
-- between an addon that restores a mark someone accidentally cleared and one
-- that will not stop fighting a human who is deliberately changing it.
local MFD = _G.MarkedForDeath or {}

MFD.Marker = MFD.Marker or {}
local Marker = MFD.Marker

local SetRaidTarget = SetRaidTarget
local GetRaidTargetIndex = GetRaidTargetIndex
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetCVar = GetCVar

-- maxActions and defenseLimit are counts. defenseWindow and tickInterval are
-- seconds.
Marker.LIMITS = {
    maxActions = 4,
    defenseLimit = 3,
    defenseWindow = 5,
    tickInterval = 0.2,
}

-- Assignments frozen at combat start, { [key] = icon }.
Marker.locked = {}

-- Takes the desired map, the observed actual map, a mutable defense counter
-- table, the current time and the limits table. Returns
-- { actions = array of { key, icon, isDefense }, yielded = array of key }.
--
-- Mutates defense: each re-application increments a counter inside a rolling
-- window, and once the limit is hit inside that window the key is yielded
-- rather than fought over. Sorted output keeps the result deterministic.
function Marker.ComputeDiff(desired, actual, defense, now, limits)
    local actions, yielded = {}, {}

    for _, key in ipairs(MFD.H.SortedKeys(desired)) do
        local wanted = desired[key]
        local present = actual[key] or 0

        if present ~= wanted then
            local isDefense = present ~= 0 or (defense[key] ~= nil)

            if not isDefense then
                actions[#actions + 1] = { key = key, icon = wanted, isDefense = false }
            else
                local entry = defense[key]
                if not entry or (entry.windowStart + limits.defenseWindow) < now then
                    entry = { count = 0, windowStart = now }
                    defense[key] = entry
                end

                if entry.count < limits.defenseLimit then
                    entry.count = entry.count + 1
                    actions[#actions + 1] = { key = key, icon = wanted, isDefense = true }
                else
                    yielded[#yielded + 1] = key
                end
            end
        end
    end

    while #actions > limits.maxActions do
        table.remove(actions)
    end

    return { actions = actions, yielded = yielded }
end

-- Returns whether the player may place raid icons, and a reason when they may
-- not. Marking needs raid leader or assistant; solo and unled parties are
-- always allowed.
function Marker:CanMark()
    if IsInRaid and IsInRaid() then
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            return true, ""
        end
        return false, "you need raid assist to place icons"
    end

    if IsInGroup and IsInGroup() then
        if UnitIsGroupLeader("player") then
            return true, ""
        end
        return true, ""
    end

    return true, ""
end

-- Returns whether nameplate settings allow marking mobs the player is not
-- targeting, and a message describing the fix when they do not. Reading a CVar
-- can fail on an unexpected client build, so it is wrapped.
function Marker:CheckCvars()
    if not GetCVar then
        return true, ""
    end

    local ok, showEnemies = pcall(GetCVar, "nameplateShowEnemies")
    if not ok then
        return true, ""
    end

    if showEnemies ~= "1" then
        return false, "enemy nameplates are off, so mobs you are not targeting cannot be marked. Run /mfd fixcvars"
    end

    local okDist, distance = pcall(GetCVar, "nameplateMaxDistance")
    if okDist and tonumber(distance) and tonumber(distance) < 20 then
        return false, "nameplate distance is only " .. distance .. " yards, so packs will be marked late. Run /mfd fixcvars"
    end

    return true, ""
end

_G.MarkedForDeath = MFD
```

- [ ] **Step 4: Add the tick, the event wiring and the commands**

Append to `Marker.lua`, immediately before the final `_G.MarkedForDeath = MFD` line:

```lua
local defense = {}
local accumulator = 0
local isRunning = false

-- Builds the roster the seat resolver needs. Returns an array of
-- { name, class }. Reads client state, so it never runs at file scope.
local function currentRoster()
    local roster = {}

    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            if name and class then
                roster[#roster + 1] = { name = name, class = class }
            end
        end
        return roster
    end

    local _, playerClass = UnitClass("player")
    roster[#roster + 1] = { name = UnitName("player"), class = playerClass }

    if IsInGroup and IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            local _, class = UnitClass(unit)
            local name = UnitName(unit)
            if name and class then
                roster[#roster + 1] = { name = name, class = class }
            end
        end
    end

    return roster
end

-- Returns { [key] = icon } for the units the client can currently read, plus
-- a { [key] = unitToken } map for applying icons.
local function readActual()
    local actual, units = {}, {}

    for key, entry in pairs(MFD.Candidates.set) do
        if entry.unit then
            units[key] = entry.unit
            actual[key] = GetRaidTargetIndex(entry.unit) or 0
        end
    end

    return actual, units
end

-- Recomputes the desired map from the current candidates, rules and seats.
-- Returns the allocator result.
function Marker:Desired()
    local seats = MFD.Seats.Resolve(MFD.db.seatPlan, currentRoster())
    local rules = MFD.Rules.Active and MFD.Rules.Active() or {}
    return MFD.Allocator.Compute(MFD.Candidates.ToList(MFD.Candidates.set), rules, seats, Marker.locked)
end

function Marker:Tick(elapsed)
    accumulator = accumulator + elapsed
    if accumulator < Marker.LIMITS.tickInterval then
        return
    end
    accumulator = 0

    if not MFD.db.settings.isMarkingEnabled then
        return
    end

    local now = GetTime()

    for _, key in ipairs(MFD.Candidates.Prune(MFD.Candidates.set, now, MFD.Candidates.GRACE_SECONDS)) do
        Marker.locked[key] = nil
        defense[key] = nil
    end

    if not MFD.Comms or not MFD.Comms:IsAuthority() then
        return
    end

    local canMark = Marker:CanMark()
    if not canMark then
        return
    end

    local desired = Marker:Desired()
    local actual, units = readActual()
    local diff = Marker.ComputeDiff(desired.byKey, actual, defense, now, Marker.LIMITS)

    for _, action in ipairs(diff.actions) do
        local unit = units[action.key]
        if unit then
            SetRaidTarget(unit, action.icon)
        end
    end

    for _, key in ipairs(diff.yielded) do
        MFD.Print("giving up on " .. key .. ", something keeps changing that icon")
        defense[key] = nil
    end

    MFD.Marker.lastDesired = desired
end

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")

    frame:SetScript("OnUpdate", function(_, elapsed)
        local ok, err = pcall(Marker.Tick, Marker, elapsed)
        if not ok and not isRunning then
            isRunning = true
            MFD.Error("marking tick failed: " .. tostring(err))
        end
    end)

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Freeze the current map so nothing shifts under the raid mid-pull.
            local desired = Marker.lastDesired
            if desired then
                for key, icon in pairs(desired.byKey) do
                    Marker.locked[key] = icon
                end
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            wipe(Marker.locked)
            if MFD.db.settings.isCvarWarnEnabled then
                local ok, message = Marker:CheckCvars()
                if not ok then
                    MFD.Error(message)
                end
            end
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
            if subEvent == "UNIT_DIED" then
                local key = destGUID and MFD.H.KeyFromGUID(destGUID)
                if key then
                    Marker.locked[key] = nil
                    defense[key] = nil
                    MFD.Candidates.set[key] = nil
                end
            end
        end
    end)
end)
```

Add to `Core.lua` alongside the other commands:

```lua
commands.mark = {
    desc = "force a full re-mark of the visible pack",
    run = function()
        wipe(MFD.Marker.locked)
        MFD.Print("re-marking")
    end,
}

commands.clear = {
    desc = "clear every icon on visible mobs",
    run = function()
        local cleared = 0
        for _, entry in pairs(MFD.Candidates.set) do
            if entry.unit then
                SetRaidTarget(entry.unit, 0)
                cleared = cleared + 1
            end
        end
        wipe(MFD.Marker.locked)
        MFD.Print("cleared " .. cleared .. " icons")
    end,
}

commands.fixcvars = {
    desc = "set the nameplate settings marking needs",
    run = function()
        SetCVar("nameplateShowEnemies", 1)
        SetCVar("nameplateMaxDistance", 41)
        MFD.Print("enemy nameplates on, distance set to 41 yards")
    end,
}
```

- [ ] **Step 5: Add Marker.lua to the TOC and run the tests**

Edit `MarkedForDeath.toc` so the file list reads:

```
Helpers.lua
Seats.lua
Rules.lua
Allocator.lua
Candidates.lua
Marker.lua
Core.lua
Tests.lua
```

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `45 passed, 0 failed, 45 total`, exit code 0.

- [ ] **Step 6: Add a temporary rule source so marking can be verified before Task 7**

`Marker:Desired` calls `MFD.Rules.Active()`, which Task 7 provides. Add a placeholder to `Rules.lua` now, immediately before its final `_G.MarkedForDeath = MFD` line, so this task is independently testable:

```lua
-- Returns the merged rules for the current instance as { [npcID] = rule }.
-- Task 7 replaces this with the real instance-aware, comms-merged lookup.
function Rules.Active()
    return Rules.activeByNpcID or {}
end
```

And add a temporary command to `Core.lua` for hand-testing:

```lua
commands.testrule = {
    desc = "temporary: rule the current target as a kill target",
    run = function()
        local guid = UnitGUID("target")
        local npcID = guid and MFD.H.NpcIDFromKey(MFD.H.KeyFromGUID(guid) or "")
        if not npcID then
            MFD.Print("no valid creature targeted")
            return
        end
        MFD.Rules.activeByNpcID = MFD.Rules.activeByNpcID or {}
        MFD.Rules.activeByNpcID[npcID] = { npcID = npcID, intent = "KILL", rank = 10 }
        MFD.Print("npc " .. npcID .. " will now be marked as a kill target")
    end,
}
```

Both are removed in Task 7. Note that in the commit message.

- [ ] **Step 7: Verify in game**

Marking is gated on `MFD.Comms:IsAuthority()`, which Task 8 provides. Until then, add this stub to `Marker.lua` above the tick so the module is runnable, and delete it in Task 8:

```lua
-- Temporary until Comms lands in Task 8.
MFD.Comms = MFD.Comms or { IsAuthority = function() return true end }
```

Deploy and verify:
1. `powershell -File scripts/deploy.ps1 -Flavor anniversary -Addon MarkedForDeath -WowRoot "C:\Program Files (x86)\World of Warcraft"`
2. `/reload`, solo, somewhere with harmless low-level mobs
3. Target one mob, run `/mfd testrule`
4. Walk away until nameplates drop, walk back. The mob takes a skull within a second.
5. Manually clear the skull. It comes back. Clear it three more times quickly and confirm the addon prints "giving up on ..." and stops.
6. Wait ten seconds, clear it again, and confirm it defends once more (the window reset).
7. Target a second mob of the same type, `/mfd testrule` is already set for that npcID, and confirm it takes a cross.
8. `/mfd clear` removes both icons.
9. With enemy nameplates disabled, `/reload` and confirm the CVar warning prints. `/mfd fixcvars` then `/reload` and confirm it does not.
10. `/mfd selftest` reports 45 passed. BugSack is empty.

- [ ] **Step 8: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add mark applier with defense brake and combat lock"
```

---

### Task 7: Instance detection, active rules, and mob learning

Replaces the Task 6 placeholders. Rules become instance-scoped and auto-activate by zone, and every mob the addon sees is recorded so search self-heals gaps in the bundled database.

**Files:**
- Modify: `AddonProjects/anniversary/MarkedForDeath/Rules.lua` (replace the `Rules.Active` placeholder)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Candidates.lua` (record learned mobs)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Core.lua` (remove `testrule`, add `where`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append cases)

**Interfaces:**
- Consumes: `MFD.Rules.Merge` from Task 3, `MFD.Candidates.Observe` from Task 5.
- Produces:
  - `MFD.Rules.INSTANCE_KEYS` -> `{ [instanceMapID:number] = key:string }`
  - `MFD.Rules.InstanceKeyFor(instanceMapID) -> string|nil`
  - `MFD.Rules.SetContributions(contributions, leadName)` recomputes the merged set and caches it
  - `MFD.Rules.Active() -> { [npcID] = rule }` for the current instance, empty outside a known raid
  - `MFD.Rules.merged` -> the full `{ [instanceKey] = { [npcID] = rule } }`
  - `MFD.Rules.currentInstanceKey` -> string or nil
  - `MFD.Learned.Record(db, npcID, name, zone, now)` (pure, mutates `db.learnedMobs`)

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua`, before the final `_G.MarkedForDeath = MFD` line:

```lua
T.Case("Rules: known TBC raid map ids resolve to instance keys", function()
    T.Eq(MFD.Rules.InstanceKeyFor(532), "KARAZHAN", "Karazhan")
    T.Eq(MFD.Rules.InstanceKeyFor(564), "BLACKTEMPLE", "Black Temple")
    T.Eq(MFD.Rules.InstanceKeyFor(534), "HYJAL", "Hyjal Summit")
end)

T.Case("Rules: an unknown map id has no instance key", function()
    T.Eq(MFD.Rules.InstanceKeyFor(1), nil, "not a TBC raid")
    T.Eq(MFD.Rules.InstanceKeyFor(nil), nil, "nil is safe")
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

T.Case("Rules: Active is empty outside a known raid", function()
    MFD.Rules.SetContributions({
        { owner = "Dillon", rules = { BLACKTEMPLE = { { npcID = 22890, intent = "SHEEP", rank = 10 } } } },
    }, "Dillon")

    MFD.Rules.currentInstanceKey = nil
    T.Eq(next(MFD.Rules.Active()), nil, "nothing is marked outside a raid we have rules for")
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
    T.Eq(next(db.learnedMobs), nil, "nothing stored")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the seven new cases fail on `MFD.Rules.InstanceKeyFor` and `MFD.Learned` being nil.

- [ ] **Step 3: Replace the Rules.Active placeholder**

In `Rules.lua`, delete the placeholder added in Task 6:

```lua
-- Returns the merged rules for the current instance as { [npcID] = rule }.
-- Task 7 replaces this with the real instance-aware, comms-merged lookup.
function Rules.Active()
    return Rules.activeByNpcID or {}
end
```

and replace it with:

```lua
-- TBC raid instance map ids. Verify each against the live client with
-- /mfd where before trusting it; Blizzard map ids are stable but these were
-- compiled from documentation, not from this client.
Rules.INSTANCE_KEYS = {
    [532] = "KARAZHAN",
    [565] = "GRUUL",
    [544] = "MAGTHERIDON",
    [548] = "SERPENTSHRINE",
    [550] = "TEMPESTKEEP",
    [534] = "HYJAL",
    [564] = "BLACKTEMPLE",
    [568] = "ZULAMAN",
    [580] = "SUNWELL",
}

-- Takes an instance map id. Returns this addon's instance key, or nil when the
-- player is not in a TBC raid the addon knows about.
function Rules.InstanceKeyFor(instanceMapID)
    if type(instanceMapID) ~= "number" then
        return nil
    end
    return Rules.INSTANCE_KEYS[instanceMapID]
end

-- Set by the zone handler in Core. nil outside a known raid.
Rules.currentInstanceKey = nil
Rules.merged = {}

-- Recomputes the merged rule set from every contributor. Caches the result in
-- Rules.merged. Never writes to saved variables: merged rules are session
-- state, and a contributor's rules must never alter another player's config.
function Rules.SetContributions(contributions, leadName)
    Rules.merged = Rules.Merge(contributions, leadName)
end

local EMPTY = {}

-- Returns { [npcID] = rule } for the instance the player is currently in, or
-- an empty table outside a known raid. The allocator consumes this directly.
function Rules.Active()
    local key = Rules.currentInstanceKey
    if not key then
        return EMPTY
    end
    return Rules.merged[key] or EMPTY
end
```

- [ ] **Step 4: Add mob learning to Candidates.lua**

Append to `Candidates.lua`, immediately before its final `_G.MarkedForDeath = MFD` line:

```lua
MFD.Learned = MFD.Learned or {}

-- Records a sighting so the mob becomes searchable even when the bundled
-- database missed it. Mutates db.learnedMobs. Pure apart from that mutation.
-- Incomplete observations are dropped rather than stored half-formed.
function MFD.Learned.Record(db, npcID, name, zone, now)
    if type(npcID) ~= "number" or type(name) ~= "string" or name == "" then
        return
    end

    db.learnedMobs[npcID] = { name = name, zone = zone, seenAt = now }
end
```

Then, inside `Candidates.ObserveUnit`, replace the final two lines:

```lua
    local npcID = MFD.H.NpcIDFromKey(key)
    Candidates.Observe(Candidates.set, key, npcID, unit, now)
    return key
```

with:

```lua
    local npcID = MFD.H.NpcIDFromKey(key)
    Candidates.Observe(Candidates.set, key, npcID, unit, now)

    if MFD.db and not MFD.db.learnedMobs[npcID] then
        MFD.Learned.Record(MFD.db, npcID, UnitName(unit), GetRealZoneText(), time())
    end

    return key
```

- [ ] **Step 5: Wire zone detection and swap the commands in Core.lua**

Delete the temporary `commands.testrule` block added in Task 6.

Add to `Core.lua`:

```lua
commands.where = {
    desc = "print the current zone and whether the addon has rules for it",
    run = function()
        local name, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
        local key = MFD.Rules.InstanceKeyFor(instanceMapID)
        MFD.Print(string.format("%s (map %s) -> %s",
            tostring(name), tostring(instanceMapID), key or "|cff999999no rules for this zone|r"))
        if key then
            local count = 0
            for _ in pairs(MFD.Rules.Active()) do count = count + 1 end
            MFD.Print(count .. " active rules")
        end
    end,
}
```

And inside `onAddonLoaded`, after the init loop, register the zone watcher:

```lua
    local zoneFrame = CreateFrame("Frame")
    zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    zoneFrame:SetScript("OnEvent", function()
        local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
        MFD.Rules.currentInstanceKey = MFD.Rules.InstanceKeyFor(instanceMapID)
    end)
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `52 passed, 0 failed, 52 total`, exit code 0.

- [ ] **Step 7: Verify the map ids against the live client**

This is the step that turns compiled documentation into a verified fact. In game:

1. `/reload`
2. Run `/mfd where` in the open world. It should report no rules for the zone.
3. Zone into each TBC raid you have access to and run `/mfd where` at the entrance. Record the reported map id.
4. Correct any entry in `Rules.INSTANCE_KEYS` that does not match, and note in the commit message which ids you verified first-hand and which are still unverified.
5. Kill or walk past a few mobs, then confirm learning is working by checking that `MarkedForDeathDB.learnedMobs` is populated after a `/reload`.
6. BugSack is empty.

- [ ] **Step 8: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Scope rules to instances and record every mob seen"
```

---

### Task 8: Comms foundation, designation and authority

The addon channel, a rate-limited send queue, the Raid Lead designation and the election fallback. Encoding, queue draining and authority resolution are all pure and tested.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/Comms.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` (add `Comms.lua` after `Marker.lua`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Marker.lua` (delete the `MFD.Comms` stub from Task 6)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Core.lua` (add `lead` and `status`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append cases)

**Interfaces:**
- Consumes: `MFD.H.SortedKeys` from Task 1, `MFD.RegisterInit` from Task 1.
- Produces:
  - `MFD.Comms.PREFIX` -> `"MFD"`
  - `MFD.Comms.SEPARATOR` -> `"~"`
  - `MFD.Comms.PRIORITY` -> `{ B=1, A=1, L=1, S=2, RG=2, PC=3, RD=4, RM=4 }` (lower drains first)
  - `MFD.Comms.MAX_PER_SECOND` -> `8`
  - `MFD.Comms.HEARTBEAT_SECONDS` -> `5`, `MFD.Comms.PEER_TIMEOUT_SECONDS` -> `15`, `MFD.Comms.LEAD_FALLBACK_SECONDS` -> `10`
  - `MFD.Comms.Encode(msgType, fields) -> string`
  - `MFD.Comms.Decode(str) -> msgType:string|nil, fields:array`
  - `MFD.Comms.Drain(queue, budget) -> array of message` (mutates `queue`)
  - `MFD.Comms.ResolveAuthority(peers, designation, now) -> name:string|nil, mode:string, reason:string`
    - `peers`: array of `{ name, canMark, isLeader, isAssist, lastSeen, version }`
    - `designation`: `{ name, setAt }`
    - `mode` is `"designated"`, `"elected"` or `"none"`
  - `MFD.Comms:IsAuthority() -> boolean`

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua`, before the final `_G.MarkedForDeath = MFD` line:

```lua
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
    local name, mode, reason = MFD.Comms.ResolveAuthority(
        { peer("Dillon", { canMark = false }), peer("Grimmtusk", { isLeader = true }) },
        { name = "Dillon", setAt = 50 }, 100)
    T.Eq(name, "Grimmtusk", "elected instead")
    T.Eq(reason, "designated lead Dillon cannot place icons", "names the real problem")
end)

T.Case("Comms: the election prefers leader, then assist, then name", function()
    local name = MFD.Comms.ResolveAuthority(
        { peer("Zed", { isAssist = true }), peer("Alfred"), peer("Mira", { isLeader = true }) },
        { name = "", setAt = 0 }, 100)
    T.Eq(name, "Mira", "raid leader outranks assist")

    local second = MFD.Comms.ResolveAuthority(
        { peer("Zed", { isAssist = true }), peer("Alfred") },
        { name = "", setAt = 0 }, 100)
    T.Eq(second, "Zed", "assist outranks nobody")

    local third = MFD.Comms.ResolveAuthority(
        { peer("Zed"), peer("Alfred") },
        { name = "", setAt = 0 }, 100)
    T.Eq(third, "Alfred", "tie broken by name ascending")
end)

T.Case("Comms: peers that have gone silent are ignored", function()
    local name = MFD.Comms.ResolveAuthority(
        { peer("Mira", { isLeader = true, lastSeen = 10 }), peer("Alfred", { lastSeen = 99 }) },
        { name = "", setAt = 0 }, 100)
    T.Eq(name, "Alfred", "the stale raid leader does not win")
end)

T.Case("Comms: nobody eligible means no authority", function()
    local name, mode = MFD.Comms.ResolveAuthority({}, { name = "", setAt = 0 }, 100)
    T.Eq(name, nil, "no authority")
    T.Eq(mode, "none", "and it says so")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the ten new cases fail with `attempt to index field 'Comms' (a nil value)`.

- [ ] **Step 3: Write the pure half of Comms.lua**

Create `AddonProjects/anniversary/MarkedForDeath/Comms.lua`:

```lua
-- The addon channel: message encoding, a rate-limited send queue, the Raid
-- Lead designation and the election fallback.
--
-- Encode, Decode, Drain and ResolveAuthority are pure so the coordination
-- logic is testable headlessly. Everything that touches the client lives below
-- them and runs from RegisterInit.
local MFD = _G.MarkedForDeath or {}

MFD.Comms = MFD.Comms or {}
local Comms = MFD.Comms

Comms.PREFIX = "MFD"

-- Chosen over "|" because the chat system treats that as an escape introducer
-- and over "\n" because addon messages may not contain it. Player names and
-- npc ids can never contain it.
Comms.SEPARATOR = "~"

-- Lower drains first. The channel is throttled server side and that budget is
-- shared with every other addon the player runs, so bulk rule data must never
-- be able to starve a heartbeat or an assignment.
Comms.PRIORITY = {
    B = 1, A = 1, L = 1, E = 1, H = 1,
    S = 2, RG = 2, RV = 2, RQ = 2, C = 2,
    PC = 3,
    RD = 4, RM = 4,
}

Comms.MAX_PER_SECOND = 8         -- messages
Comms.HEARTBEAT_SECONDS = 5      -- seconds between authority heartbeats
Comms.PEER_TIMEOUT_SECONDS = 15  -- seconds of silence before a peer is ignored
Comms.LEAD_FALLBACK_SECONDS = 10 -- seconds before an invalid lead yields to the election

-- Joins a message type and its fields into a wire string.
function Comms.Encode(msgType, fields)
    local parts = { msgType }
    for _, value in ipairs(fields or {}) do
        parts[#parts + 1] = tostring(value)
    end
    return table.concat(parts, Comms.SEPARATOR)
end

-- Splits a wire string. Returns the message type and an array of field strings,
-- or nil when the input is not a message. Fields always come back as strings;
-- callers convert.
function Comms.Decode(str)
    if type(str) ~= "string" or str == "" then
        return nil
    end

    local fields = {}
    for part in string.gmatch(str, "([^" .. Comms.SEPARATOR .. "]+)") do
        fields[#fields + 1] = part
    end

    local msgType = table.remove(fields, 1)
    if not msgType then
        return nil
    end

    return msgType, fields
end

-- Removes up to budget messages from queue in priority order and returns them.
-- Mutates queue. Ties keep insertion order, so a burst of sightings goes out in
-- the order they were observed.
function Comms.Drain(queue, budget)
    local indexed = {}
    for i, message in ipairs(queue) do
        indexed[#indexed + 1] = { message = message, index = i }
    end

    table.sort(indexed, function(a, b)
        local pa = Comms.PRIORITY[a.message.msgType] or 9
        local pb = Comms.PRIORITY[b.message.msgType] or 9
        if pa ~= pb then
            return pa < pb
        end
        return a.index < b.index
    end)

    local sent, taken = {}, {}
    for i = 1, math.min(budget, #indexed) do
        sent[#sent + 1] = indexed[i].message
        taken[indexed[i].index] = true
    end

    for i = #queue, 1, -1 do
        if taken[i] then
            table.remove(queue, i)
        end
    end

    return sent
end

-- Takes the known peers, the current designation and the time. Returns the
-- authority's name, the mode ("designated", "elected" or "none") and a reason
-- string explaining any fallback.
--
-- A designated lead wins outright when they are present and able to mark.
-- Otherwise the election runs: raid leader, then assistant, then name
-- ascending. Peers silent past PEER_TIMEOUT_SECONDS are ignored entirely, so a
-- disconnected raid leader cannot hold the authority hostage.
function Comms.ResolveAuthority(peers, designation, now)
    local live = {}
    for _, p in ipairs(peers) do
        if (p.lastSeen + Comms.PEER_TIMEOUT_SECONDS) >= now then
            live[#live + 1] = p
        end
    end

    local reason = ""

    if designation and designation.name and designation.name ~= "" then
        local found
        for _, p in ipairs(live) do
            if p.name == designation.name then
                found = p
                break
            end
        end

        if found and found.canMark then
            return found.name, "designated", ""
        end

        if not found then
            reason = "designated lead " .. designation.name .. " is not in the group"
        else
            reason = "designated lead " .. designation.name .. " cannot place icons"
        end
    end

    local best
    for _, p in ipairs(live) do
        if p.canMark then
            local score = (p.isLeader and 1000 or 0) + (p.isAssist and 500 or 0)
            if not best or score > best.score or (score == best.score and p.name < best.peer.name) then
                best = { peer = p, score = score }
            end
        end
    end

    if not best then
        return nil, "none", reason ~= "" and reason or "nobody in the group can place icons"
    end

    return best.peer.name, "elected", reason
end

_G.MarkedForDeath = MFD
```

- [ ] **Step 4: Add Comms.lua to the TOC and run the tests**

Edit `MarkedForDeath.toc` so the file list reads:

```
Helpers.lua
Seats.lua
Rules.lua
Allocator.lua
Candidates.lua
Marker.lua
Comms.lua
Core.lua
Tests.lua
```

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `62 passed, 0 failed, 62 total`, exit code 0.

- [ ] **Step 5: Write the client half of Comms.lua**

Delete the temporary stub from `Marker.lua`:

```lua
-- Temporary until Comms lands in Task 8.
MFD.Comms = MFD.Comms or { IsAuthority = function() return true end }
```

Append to `Comms.lua`, immediately before its final `_G.MarkedForDeath = MFD` line:

```lua
local queue = {}
local peers = {}
local sendAccumulator = 0
local heartbeatAccumulator = 0

Comms.authority = nil
Comms.authorityMode = "none"
Comms.authorityReason = ""

local function playerName()
    return UnitName("player")
end

-- Queues a message. Nothing is ever sent directly, so the rate limit cannot be
-- bypassed by accident.
function Comms:Send(msgType, fields)
    queue[#queue + 1] = { msgType = msgType, body = Comms.Encode(msgType, fields) }
end

local function channel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    if IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function flush()
    local target = channel()
    if not target then
        wipe(queue)
        return
    end

    local sendFn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if type(sendFn) ~= "function" then
        return
    end

    for _, message in ipairs(Comms.Drain(queue, Comms.MAX_PER_SECOND)) do
        pcall(sendFn, Comms.PREFIX, message.body, target)
    end
end

-- Rebuilds the peer list into the shape ResolveAuthority consumes and caches
-- the result. Called on any roster, designation or heartbeat change.
function Comms:RecomputeAuthority()
    local now = GetTime()
    local list = {}

    for name, p in pairs(peers) do
        list[#list + 1] = {
            name = name,
            canMark = p.canMark,
            isLeader = p.isLeader,
            isAssist = p.isAssist,
            lastSeen = p.lastSeen,
            version = p.version,
        }
    end

    local name, mode, reason = Comms.ResolveAuthority(list, MFD.db.designatedLead, now)

    if reason ~= "" and reason ~= Comms.authorityReason then
        MFD.Print(reason)
    end

    Comms.authority, Comms.authorityMode, Comms.authorityReason = name, mode, reason
end

function Comms:IsAuthority()
    return Comms.authority == playerName()
end

-- Records our own state as a peer, so a solo player or the only addon user in
-- a raid still resolves to an authority.
local function refreshSelf()
    local canMark = MFD.Marker:CanMark()
    peers[playerName()] = {
        canMark = canMark,
        isLeader = UnitIsGroupLeader("player") or false,
        isAssist = (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) or false,
        lastSeen = GetTime(),
        version = MFD.VERSION,
    }
end

function Comms:SetLead(name)
    local canSet = UnitIsGroupLeader("player")
        or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        or not (IsInGroup and IsInGroup())

    if not canSet then
        MFD.Error("only the raid leader or an assistant can set the Raid Lead")
        return
    end

    MFD.db.designatedLead = { name = name or "", setBy = playerName(), setAt = time() }
    Comms:Send("L", { name or "", playerName(), MFD.db.designatedLead.setAt })
    Comms:RecomputeAuthority()

    if name and name ~= "" then
        MFD.Print("Raid Lead set to " .. name)
    else
        MFD.Print("Raid Lead cleared, falling back to the automatic election")
    end
end

local function onMessage(prefix, body, _, sender)
    if prefix ~= Comms.PREFIX then
        return
    end

    local msgType, fields = Comms.Decode(body)
    if not msgType then
        return
    end

    sender = string.match(sender or "", "^([^%-]+)") or sender

    if msgType == "H" then
        peers[sender] = {
            version = fields[1],
            canMark = fields[2] == "1",
            isLeader = fields[3] == "1",
            isAssist = fields[4] == "1",
            lastSeen = GetTime(),
        }
        Comms:RecomputeAuthority()
    elseif msgType == "B" then
        if peers[sender] then
            peers[sender].lastSeen = GetTime()
        end
    elseif msgType == "L" then
        local setAt = tonumber(fields[3]) or 0
        -- Last write wins, so two people setting the lead at once converges.
        if setAt >= (MFD.db.designatedLead.setAt or 0) then
            MFD.db.designatedLead = { name = fields[1] or "", setBy = fields[2] or sender, setAt = setAt }
            Comms:RecomputeAuthority()
            MFD.Print("Raid Lead set to " .. (fields[1] ~= "" and fields[1] or "nobody") .. " by " .. tostring(fields[2]))
        end
    end
end

MFD.RegisterInit(function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, Comms.PREFIX)
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            onMessage(...)
        else
            refreshSelf()
            Comms:RecomputeAuthority()
            Comms:Send("H", {
                MFD.VERSION,
                MFD.Marker:CanMark() and "1" or "0",
                UnitIsGroupLeader("player") and "1" or "0",
                (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) and "1" or "0",
            })
        end
    end)

    frame:SetScript("OnUpdate", function(_, elapsed)
        sendAccumulator = sendAccumulator + elapsed
        if sendAccumulator >= 1 then
            sendAccumulator = 0
            flush()
        end

        heartbeatAccumulator = heartbeatAccumulator + elapsed
        if heartbeatAccumulator >= Comms.HEARTBEAT_SECONDS then
            heartbeatAccumulator = 0
            refreshSelf()
            if Comms:IsAuthority() then
                Comms:Send("B", { MFD.VERSION })
            end
            Comms:RecomputeAuthority()
        end
    end)

    refreshSelf()
    Comms:RecomputeAuthority()
end)
```

- [ ] **Step 6: Add the lead and status commands**

Add to `Core.lua`:

```lua
commands.lead = {
    desc = "designate the Raid Lead, or clear it with no name",
    run = function(rest)
        MFD.Comms:SetLead(rest ~= "" and rest or nil)
    end,
}

commands.status = {
    desc = "show the authority, peers and rule counts",
    run = function()
        local mode = MFD.Comms.authorityMode
        MFD.Print("authority: " .. tostring(MFD.Comms.authority or "none") .. " (" .. mode .. ")")
        if MFD.Comms.authorityReason ~= "" then
            MFD.Print("  " .. MFD.Comms.authorityReason)
        end

        local designated = MFD.db.designatedLead.name
        MFD.Print("designated lead: " .. (designated ~= "" and designated or "|cff999999none|r"))

        local canMark, why = MFD.Marker:CanMark()
        MFD.Print("can place icons: " .. tostring(canMark) .. (why ~= "" and " (" .. why .. ")" or ""))

        local cvarsOk, cvarMessage = MFD.Marker:CheckCvars()
        if not cvarsOk then
            MFD.Print("|cffff4444" .. cvarMessage .. "|r")
        end

        local count = 0
        for _ in pairs(MFD.Rules.Active()) do count = count + 1 end
        MFD.Print("active rules: " .. count .. " for " .. tostring(MFD.Rules.currentInstanceKey or "no known raid"))
    end,
}
```

- [ ] **Step 7: Verify in game**

1. Deploy and `/reload`
2. Solo: `/mfd status` reports you as the authority in `elected` mode, and marking still works as in Task 6
3. `/mfd lead Grimmtusk` prints the designation, then `/mfd status` reports `designated lead Grimmtusk is not in the group` and falls back to electing you
4. `/mfd lead` with no name clears it and `/mfd status` returns to `elected`
5. In a group with a second person running the addon: `/mfd status` on both shows the same authority name. Have them `/mfd lead <your name>` and confirm both clients now report `designated` with you as authority.
6. Have the authority log out. Within 15 seconds the other client re-elects and `/mfd status` reflects it.
7. `/mfd selftest` reports 62 passed. BugSack is empty on both clients.

- [ ] **Step 8: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add addon channel, Raid Lead designation and authority election"
```

---

### Task 9: Rule serialisation, sync and merging over the channel

Peers send their own rules to the authority once, version gated. The authority merges and publishes back a compact digest of ruled npc ids. Serialisation, chunking, reassembly and hashing are pure and tested.

**Files:**
- Modify: `AddonProjects/anniversary/MarkedForDeath/Rules.lua` (serialiser and hash)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Comms.lua` (chunking and the sync flow)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append cases)

**Interfaces:**
- Consumes: `MFD.Rules.Merge`, `MFD.Rules.SetContributions` from Tasks 3 and 7; `MFD.Comms.Encode`, `Decode`, `Send` from Task 8.
- Produces:
  - `MFD.Rules.Serialize(rulesByInstance) -> string`
  - `MFD.Rules.Deserialize(str) -> rulesByInstance|nil, err:string|nil`
  - `MFD.Rules.Hash(rulesByInstance) -> string`
  - `MFD.Rules.BumpVersion(db)` recomputes `db.rulesVersion` from `db.rules`
  - `MFD.Comms.CHUNK_BYTES` -> `200`
  - `MFD.Comms.Chunk(payload, size) -> array of string`
  - `MFD.Comms.Reassemble(state, sender, index, total, chunk) -> payload:string|nil` (mutates `state`)
  - `MFD.Comms.TRANSFER_TIMEOUT_SECONDS` -> `20`
  - `MFD.Comms.SweepTransfers(state, now, timeout) -> array of abandoned sender names` (mutates `state`)

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua`, before the final `_G.MarkedForDeath = MFD` line:

```lua
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

T.Case("Rules: the hash is stable and change sensitive", function()
    local a = { BT = { { npcID = 1, intent = "KILL", rank = 10 } } }
    local b = { BT = { { npcID = 1, intent = "KILL", rank = 10 } } }
    local c = { BT = { { npcID = 1, intent = "SHEEP", rank = 10 } } }
    T.Eq(MFD.Rules.Hash(a), MFD.Rules.Hash(b), "same content, same hash")
    if MFD.Rules.Hash(a) == MFD.Rules.Hash(c) then
        error("changing an intent must change the hash")
    end
end)

T.Case("Comms: chunking splits and preserves the payload", function()
    local payload = string.rep("x", 450)
    local chunks = MFD.Comms.Chunk(payload, 200)
    T.Eq(#chunks, 3, "three chunks")
    T.Eq(#chunks[1], 200, "full first chunk")
    T.Eq(#chunks[3], 50, "remainder in the last")
    T.Eq(table.concat(chunks), payload, "concatenation restores it")
end)

T.Case("Comms: a short payload is a single chunk", function()
    T.Eq(#MFD.Comms.Chunk("short", 200), 1, "one chunk")
end)

T.Case("Comms: reassembly returns the payload only when complete", function()
    local state = {}
    T.Eq(MFD.Comms.Reassemble(state, "Zed", 1, 2, "hello "), nil, "incomplete")
    T.Eq(MFD.Comms.Reassemble(state, "Zed", 2, 2, "world"), "hello world", "complete")
    T.Eq(state.Zed, nil, "state cleaned up after completion")
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the eight new cases fail on `MFD.Rules.Serialize` and `MFD.Comms.Chunk` being nil.

- [ ] **Step 3: Add the serialiser to Rules.lua**

Append to `Rules.lua`, before its final `_G.MarkedForDeath = MFD` line:

```lua
-- Wire and export format. One rule per line:
--   instanceKey;npcID;intent;rank;fallback;maxCount;name
-- Fields are positional, name goes last because it is the only one that may
-- contain spaces. Empty means absent. A hand-rolled format is used rather than
-- a serialisation library because rule sets are small enough that compression
-- is not worth a dependency.
local FIELD = ";"
local LINE = "\n"

-- Takes { [instanceKey] = array of rule }. Returns a string. Iteration goes
-- through sorted keys so the same rules always serialise identically, which is
-- what makes the hash usable for version gating.
function Rules.Serialize(rulesByInstance)
    local lines = {}

    for _, instanceKey in ipairs(MFD.H.SortedKeys(rulesByInstance)) do
        for _, rule in ipairs(rulesByInstance[instanceKey]) do
            lines[#lines + 1] = table.concat({
                instanceKey,
                rule.npcID,
                rule.intent,
                rule.rank,
                rule.fallback or "",
                rule.maxCount or "",
                (rule.name or ""):gsub("[" .. FIELD .. LINE .. "]", " "),
            }, FIELD)
        end
    end

    return table.concat(lines, LINE)
end

-- Takes a serialised string. Returns { [instanceKey] = array of rule }, or nil
-- and a reason. A malformed line aborts the whole parse rather than silently
-- importing a partial rule set.
function Rules.Deserialize(str)
    if type(str) ~= "string" then
        return nil, "not a string"
    end

    local out = {}
    local lineNumber = 0

    for line in string.gmatch(str, "[^" .. LINE .. "]+") do
        lineNumber = lineNumber + 1

        local instanceKey, npcID, intent, rank, fallback, maxCount, name =
            string.match(line, "^([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);(.*)$")

        if not instanceKey or instanceKey == "" then
            return nil, "line " .. lineNumber .. " is not a rule"
        end

        if not tonumber(npcID) or not tonumber(rank) then
            return nil, "line " .. lineNumber .. " has a bad npc id or rank"
        end

        if not MFD.Seats.INTENTS[intent] then
            return nil, "line " .. lineNumber .. " has unknown intent '" .. tostring(intent) .. "'"
        end

        out[instanceKey] = out[instanceKey] or {}
        table.insert(out[instanceKey], {
            npcID = tonumber(npcID),
            intent = intent,
            rank = tonumber(rank),
            fallback = fallback ~= "" and fallback or nil,
            maxCount = tonumber(maxCount) or nil,
            name = name ~= "" and name or nil,
        })
    end

    return out
end

-- A cheap content hash over the serialised form, used only to decide whether a
-- peer's rules changed. Not a security primitive.
function Rules.Hash(rulesByInstance)
    local payload = Rules.Serialize(rulesByInstance)
    local hash = 5381

    for i = 1, #payload do
        hash = (hash * 33 + string.byte(payload, i)) % 4294967296
    end

    return tostring(hash) .. ":" .. #payload
end

-- Recomputes db.rulesVersion after a local rule edit. The counter rises so a
-- peer can tell newer from merely different, and the hash lets it skip a
-- transfer when nothing actually changed.
function Rules.BumpVersion(db)
    local hash = Rules.Hash(db.rules)
    if db.rulesVersion.hash == hash then
        return
    end
    db.rulesVersion = { counter = (db.rulesVersion.counter or 0) + 1, hash = hash }
end
```

- [ ] **Step 4: Add chunking and the sync flow to Comms.lua**

Append to `Comms.lua`, before its final `_G.MarkedForDeath = MFD` line:

```lua
-- Bytes per chunk. Addon messages cap at 255 including the prefix and the
-- envelope fields, so this leaves comfortable headroom.
Comms.CHUNK_BYTES = 200
Comms.TRANSFER_TIMEOUT_SECONDS = 20

-- Splits payload into chunks of at most size bytes. Returns an array with at
-- least one entry, even for an empty payload.
function Comms.Chunk(payload, size)
    local chunks = {}
    local position = 1

    repeat
        chunks[#chunks + 1] = string.sub(payload, position, position + size - 1)
        position = position + size
    until position > #payload

    return chunks
end

-- Accumulates a chunked transfer. Returns the complete payload once the last
-- chunk arrives, otherwise nil. Mutates state, keyed by sender, and clears the
-- sender's entry on completion.
--
-- Caller contract: when this function creates an entry it stamps startedAt as 0,
-- because it has no clock of its own and must stay pure. The client wiring
-- pre-creates the entry with a real startedAt before the first call, and
-- SweepTransfers would otherwise abandon the transfer immediately.
function Comms.Reassemble(state, sender, index, total, chunk)
    local entry = state[sender]

    if not entry or entry.total ~= total then
        entry = { total = total, parts = {}, received = 0, startedAt = 0 }
        state[sender] = entry
    end

    if not entry.parts[index] then
        entry.parts[index] = chunk
        entry.received = entry.received + 1
    end

    if entry.received < total then
        return nil
    end

    state[sender] = nil
    return table.concat(entry.parts)
end

-- Drops transfers that stalled. Returns the senders whose transfers were
-- abandoned so the caller can report it, because a silent stall is exactly the
-- kind of failure the repo standards forbid.
function Comms.SweepTransfers(state, now, timeout)
    local abandoned = {}

    for _, sender in ipairs(MFD.H.SortedKeys(state)) do
        local entry = state[sender]
        if (entry.startedAt + timeout) < now then
            abandoned[#abandoned + 1] = sender
            state[sender] = nil
        end
    end

    return abandoned
end
```

Then append the client wiring, still before the final `_G.MarkedForDeath = MFD` line:

```lua
local transfers = {}
local contributions = {}
local peerVersions = {}
local ruledDigest = {}

-- Rebuilds the merged rule set from every contribution we hold and publishes
-- the digest of ruled npc ids so backups know which mobs to report.
local function republish()
    local list = {}
    for owner, rules in pairs(contributions) do
        list[#list + 1] = { owner = owner, rules = rules }
    end

    MFD.Rules.SetContributions(list, MFD.db.designatedLead.name)

    if not Comms:IsAuthority() then
        return
    end

    local ids = {}
    for _, instanceKey in ipairs(MFD.H.SortedKeys(MFD.Rules.merged)) do
        for npcID in pairs(MFD.Rules.merged[instanceKey]) do
            ids[#ids + 1] = npcID
        end
    end

    table.sort(ids)
    for _, chunkText in ipairs(Comms.Chunk(table.concat(ids, ","), Comms.CHUNK_BYTES)) do
        Comms:Send("RG", { chunkText })
    end
end

Comms.Republish = republish

-- Sends our own rules to the authority, chunked.
local function sendRules()
    local payload = MFD.Rules.Serialize(MFD.db.rules)
    local chunks = Comms.Chunk(payload, Comms.CHUNK_BYTES)

    for i, chunkText in ipairs(chunks) do
        Comms:Send("RD", { i, #chunks, chunkText })
    end
end

Comms.SendRules = sendRules

function Comms:IsRuled(npcID)
    return ruledDigest[npcID] == true
end

-- Extends the message handler from Task 8. Call this from onMessage after the
-- existing branches.
function Comms:HandleRuleMessage(msgType, fields, sender)
    if msgType == "RV" then
        peerVersions[sender] = fields[1]
        if Comms:IsAuthority() and contributions[sender] == nil then
            Comms:Send("RQ", { sender })
        end
        return true
    end

    if msgType == "RQ" then
        if fields[1] == UnitName("player") then
            sendRules()
        end
        return true
    end

    if msgType == "RD" then
        local index, total = tonumber(fields[1]), tonumber(fields[2])
        if not index or not total then
            return true
        end

        if not transfers[sender] then
            transfers[sender] = { total = total, parts = {}, received = 0, startedAt = GetTime() }
        end

        local payload = Comms.Reassemble(transfers, sender, index, total, fields[3] or "")
        if payload then
            local parsed, err = MFD.Rules.Deserialize(payload)
            if not parsed then
                MFD.Error("could not read rules from " .. sender .. ": " .. tostring(err))
                return true
            end
            contributions[sender] = parsed
            republish()
            MFD.Print("merged rules from " .. sender)
        end
        return true
    end

    if msgType == "RG" then
        wipe(ruledDigest)
        for id in string.gmatch(fields[1] or "", "(%d+)") do
            ruledDigest[tonumber(id)] = true
        end
        return true
    end

    return false
end

function Comms:ContributionCounts()
    local counts = {}
    for owner, rules in pairs(contributions) do
        local total = 0
        for _, list in pairs(rules) do
            total = total + #list
        end
        counts[owner] = total
    end
    return counts
end
```

In `onMessage`, after the existing `elseif msgType == "L" then ... end` block, add:

```lua
    else
        Comms:HandleRuleMessage(msgType, fields, sender)
    end
```

In the `OnUpdate` handler added in Task 8, inside the heartbeat branch, add before `Comms:RecomputeAuthority()`:

```lua
            for _, sender in ipairs(Comms.SweepTransfers(transfers, GetTime(), Comms.TRANSFER_TIMEOUT_SECONDS)) do
                MFD.Error("rule transfer from " .. sender .. " timed out, will retry")
                peerVersions[sender] = nil
            end
```

And in the roster branch of the event handler, after the `H` send, add:

```lua
            MFD.Rules.BumpVersion(MFD.db)
            contributions[UnitName("player")] = MFD.db.rules
            republish()
            Comms:Send("RV", { MFD.db.rulesVersion.counter .. ":" .. MFD.db.rulesVersion.hash })
```

- [ ] **Step 5: Extend the status command**

In `Core.lua`, inside `commands.status.run`, before the active-rules line, add:

```lua
        local counts = MFD.Comms:ContributionCounts()
        for _, owner in ipairs(MFD.H.SortedKeys(counts)) do
            if owner ~= UnitName("player") then
                MFD.Print("|cffffcc66" .. counts[owner] .. " rules merged from " .. owner .. "|r")
            end
        end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `70 passed, 0 failed, 70 total`, exit code 0.

- [ ] **Step 7: Verify in game**

Rules cannot be created from the UI until Task 12, so seed them by hand for this test:

1. In game, run this once to create a local rule, then `/reload`:

```
/run MarkedForDeathDB.rules.BLACKTEMPLE = { { npcID = 22890, name = "Illidari Nightlord", intent = "KILL", rank = 10 } }
```

2. `/mfd status` shows one active rule when standing in Black Temple, zero elsewhere
3. With a second person running the addon, have them seed a different rule for a different npc id and `/reload`
4. Both clients' `/mfd status` should report the other's rules merged, with the contributor named in amber
5. Confirm `MarkedForDeathDB.rules` on each client still contains only that player's own rules after a `/reload`. This is the safety property: merging must never write to saved variables.
6. Have one client `/reload` mid-transfer repeatedly. Confirm you eventually see the timeout message rather than a silent stall.
7. BugSack is empty on both clients.

- [ ] **Step 8: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add rule serialisation, chunked sync and cross-raid merging"
```

---

### Task 10: Sighting merge, assignment publishing and backup placement

The coverage fix. Backups report ruled mobs they can see, the authority allocates over the union, and a backup places any icon the authority cannot reach.

**Files:**
- Modify: `AddonProjects/anniversary/MarkedForDeath/Comms.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/Marker.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/Tests.lua` (append cases)

**Interfaces:**
- Consumes: `MFD.Comms:IsRuled` and `Comms:Send` from Task 9; `MFD.Candidates.set` from Task 5; `MFD.Marker.ComputeDiff` from Task 6.
- Produces:
  - `MFD.Comms.SIGHTING_INTERVAL_SECONDS` -> `0.5`, `MFD.Comms.SIGHTINGS_PER_MESSAGE` -> `10`
  - `MFD.Comms.PendingSightings(set, reported, isRuled, max) -> array of "key:npcID"` (mutates `reported`)
  - `MFD.Marker.BACKUP_DELAY_SECONDS` -> `1.5`
  - `MFD.Marker.BackupActions(published, actual, firstSeenAt, now, delay) -> array of { key, icon }`
  - `MFD.Marker.published` -> `{ [key] = icon }` received from the authority

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua`, before the final `_G.MarkedForDeath = MFD` line:

```lua
T.Case("Comms: only ruled mobs are reported as sightings", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 10)
    MFD.Candidates.Observe(set, "999:BBB", 999, "nameplate2", 10)
    local isRuled = function(npcID) return npcID == 100 end
    local pending = MFD.Comms.PendingSightings(set, {}, isRuled, 10)
    T.Eq(#pending, 1, "the unruled mob is not worth channel bandwidth")
    T.Eq(pending[1], "100:AAA:100", "key and npc id")
end)

T.Case("Comms: a sighting is reported only once", function()
    local set = {}
    MFD.Candidates.Observe(set, "100:AAA", 100, "nameplate1", 10)
    local reported = {}
    local isRuled = function() return true end
    T.Eq(#MFD.Comms.PendingSightings(set, reported, isRuled, 10), 1, "first time reports")
    T.Eq(#MFD.Comms.PendingSightings(set, reported, isRuled, 10), 0, "second time is silent")
end)

T.Case("Comms: sightings are batched to a message budget", function()
    local set = {}
    for i = 1, 25 do
        MFD.Candidates.Observe(set, "10" .. i .. ":AAA", 100 + i, "nameplate1", 10)
    end
    local pending = MFD.Comms.PendingSightings(set, {}, function() return true end, 10)
    T.Eq(#pending, 10, "capped at the per-message budget")
end)

T.Case("Marker: a backup waits before placing an icon the authority published", function()
    local firstSeen = { ["100:AAA"] = 100 }
    local actions = MFD.Marker.BackupActions({ ["100:AAA"] = 8 }, {}, firstSeen, 101, 1.5)
    T.Eq(#actions, 0, "still inside the grace delay")
end)

T.Case("Marker: a backup places an icon the authority never managed to apply", function()
    local firstSeen = { ["100:AAA"] = 100 }
    local actions = MFD.Marker.BackupActions({ ["100:AAA"] = 8 }, {}, firstSeen, 102, 1.5)
    T.Eq(#actions, 1, "past the delay, the backup steps in")
    T.Eq(actions[1].icon, 8, "with the published icon")
end)

T.Case("Marker: a backup does nothing once the icon is already on the mob", function()
    local firstSeen = { ["100:AAA"] = 100 }
    local actions = MFD.Marker.BackupActions({ ["100:AAA"] = 8 }, { ["100:AAA"] = 8 }, firstSeen, 102, 1.5)
    T.Eq(#actions, 0, "the authority got there")
end)

T.Case("Marker: backup actions are deterministic in order", function()
    local firstSeen = { ["300:C"] = 100, ["100:A"] = 100, ["200:B"] = 100 }
    local actions = MFD.Marker.BackupActions(
        { ["300:C"] = 1, ["100:A"] = 2, ["200:B"] = 3 }, {}, firstSeen, 102, 1.5)
    T.Eq(actions[1].key, "100:A", "sorted by key")
    T.Eq(actions[3].key, "300:C", "third")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the seven new cases fail on `MFD.Comms.PendingSightings` and `MFD.Marker.BackupActions` being nil.

- [ ] **Step 3: Add sighting batching to Comms.lua**

Append to `Comms.lua`, before its final `_G.MarkedForDeath = MFD` line:

```lua
Comms.SIGHTING_INTERVAL_SECONDS = 0.5
Comms.SIGHTINGS_PER_MESSAGE = 10

-- Returns up to max "key:npcID" strings for ruled mobs in set that have not
-- been reported yet, and records them in reported. Mutates reported.
--
-- Filtering to ruled mobs and reporting each key once is what keeps the
-- coverage merge affordable: a raid walking through a zone reports a handful of
-- ids, not every mob on screen every half second.
function Comms.PendingSightings(set, reported, isRuled, max)
    local pending = {}

    for _, key in ipairs(MFD.H.SortedKeys(set)) do
        if #pending >= max then
            break
        end

        local entry = set[key]
        if not reported[key] and entry.unit and isRuled(entry.npcID) then
            reported[key] = true
            pending[#pending + 1] = key .. ":" .. entry.npcID
        end
    end

    return pending
end
```

Add to the `HandleRuleMessage` function, before its final `return false`:

```lua
    if msgType == "S" then
        -- Peer sightings are merged into our candidate set with no unit token,
        -- so the allocator can consider a mob we cannot see ourselves.
        if Comms:IsAuthority() then
            for key, npcID in string.gmatch(fields[1] or "", "([%d]+:%x+):(%d+)") do
                local existing = MFD.Candidates.set[key]
                if not existing then
                    MFD.Candidates.Observe(MFD.Candidates.set, key, tonumber(npcID), nil, GetTime())
                    MFD.Candidates.set[key].lostAt = nil
                    MFD.Candidates.set[key].source = "peer"
                end
            end
        end
        return true
    end

    if msgType == "A" then
        wipe(MFD.Marker.published)
        for key, icon, intent, owner in string.gmatch(fields[1] or "", "([%d]+:%x+)=(%d+)=(%u+)=([^,]*)") do
            MFD.Marker.published[key] = tonumber(icon)
            MFD.Marker.publishedDetail[key] = { intent = intent, owner = owner ~= "" and owner or nil }
            if MFD.Marker.firstPublishedAt[key] == nil then
                MFD.Marker.firstPublishedAt[key] = GetTime()
            end
        end
        return true
    end
```

- [ ] **Step 4: Add backup placement to Marker.lua**

Append to `Marker.lua`, before its final `_G.MarkedForDeath = MFD` line:

```lua
-- Seconds a backup waits for the authority to apply a published icon before
-- placing it. Long enough that the authority normally wins, short enough that
-- a pack is marked before the raid reaches it.
Marker.BACKUP_DELAY_SECONDS = 1.5

Marker.published = {}
Marker.publishedDetail = {}
Marker.firstPublishedAt = {}

-- Returns { key, icon } pairs a backup should place: icons the authority has
-- published, that are still not on the mob, and that have been outstanding
-- longer than delay. Sorted by key so two backups act in the same order.
function Marker.BackupActions(published, actual, firstSeenAt, now, delay)
    local actions = {}

    for _, key in ipairs(MFD.H.SortedKeys(published)) do
        local since = firstSeenAt[key]
        if since and (since + delay) <= now and (actual[key] or 0) ~= published[key] then
            actions[#actions + 1] = { key = key, icon = published[key] }
        end
    end

    return actions
end
```

Then in `Marker:Tick`, replace the early return:

```lua
    if not MFD.Comms or not MFD.Comms:IsAuthority() then
        return
    end
```

with the full authority-or-backup branch:

```lua
    local sightingAccumulatorReady = true

    if not MFD.Comms:IsAuthority() then
        -- Backup: report what we can see, then place anything the authority
        -- published but could not reach.
        local pending = MFD.Comms.PendingSightings(
            MFD.Candidates.set, MFD.Comms.reportedSightings,
            function(npcID) return MFD.Comms:IsRuled(npcID) end,
            MFD.Comms.SIGHTINGS_PER_MESSAGE)

        if #pending > 0 then
            MFD.Comms:Send("S", { table.concat(pending, ",") })
        end

        local actual, units = readActual()
        for _, action in ipairs(Marker.BackupActions(
            Marker.published, actual, Marker.firstPublishedAt, now, Marker.BACKUP_DELAY_SECONDS)) do
            local unit = units[action.key]
            if unit and Marker:CanMark() then
                SetRaidTarget(unit, action.icon)
                MFD.Comms:Send("C", { action.key })
            end
        end

        return
    end
```

And at the end of `Marker:Tick`, after `MFD.Marker.lastDesired = desired`, publish:

```lua
    local parts = {}
    for _, assignment in ipairs(desired.list) do
        parts[#parts + 1] = string.format("%s=%d=%s=%s",
            assignment.key, assignment.icon, assignment.intent, assignment.owner or "")
    end

    if #parts > 0 then
        MFD.Comms:Send("A", { table.concat(parts, ",") })
    end
```

Add to `Comms.lua`, near the other state locals:

```lua
Comms.reportedSightings = {}
```

And clear it alongside the candidate prune in `Marker:Tick`:

```lua
    for _, key in ipairs(MFD.Candidates.Prune(MFD.Candidates.set, now, MFD.Candidates.GRACE_SECONDS)) do
        Marker.locked[key] = nil
        defense[key] = nil
        MFD.Comms.reportedSightings[key] = nil
        Marker.published[key] = nil
        Marker.firstPublishedAt[key] = nil
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `77 passed, 0 failed, 77 total`, exit code 0.

- [ ] **Step 6: Verify in game with two clients**

This is the task that cannot be verified solo. You need a second account or a guildmate.

1. Both clients deploy and `/reload`, both seeded with the same rule for a common mob
2. Form a raid, both with assist. `/mfd lead <name>` to fix the authority.
3. Stand so that the authority can see a ruled mob and the backup cannot. Confirm it gets marked.
4. Now stand so the **backup** can see a ruled mob and the authority cannot, at a distance where the authority's nameplates cannot reach it. Confirm the mob still gets marked. **This is the core coverage claim of the whole design.** If it fails here, stop and debug before continuing.
5. Confirm no icon flicker or fighting between the two clients when both can see the same mob.
6. `/mfd status` on both agrees on the authority.
7. BugSack empty on both.

- [ ] **Step 7: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Merge peer sightings and let backups place unreachable icons"
```

---

### Task 11: Seat editor and settings window

The window where an icon is bound to an intent and a player is pinned to a seat. Everything before this task is configured by hand-editing saved variables.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/UI_Config.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` (add `UI_Config.lua` after `Tests.lua`)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Core.lua` (add `config`, seed the default seat plan)

**Interfaces:**
- Consumes: `MFD.Seats.INTENTS`, `MFD.Seats.DEFAULT_PLAN` from Task 2; `MFD.db` from Task 1.
- Produces:
  - `MFD.UI.Config:Toggle()`, `MFD.UI.Config:Refresh()`
  - `MFD.UI.AcquireRow(parent, pool, index, height) -> frame` a shared row pool helper reused by Tasks 12 and 13

- [ ] **Step 1: Seed the default seat plan**

In `Core.lua`, inside `onAddonLoaded`, after the `ApplyDefaults` calls, add:

```lua
    -- A first-run seat plan, because an empty plan marks nothing and would look
    -- like the addon is broken. Rules deliberately stay empty: guessing a
    -- guild's kill order produces confidently wrong marks.
    if not next(MarkedForDeathDB.seatPlan) then
        MarkedForDeathDB.seatPlan = MFD.H.DeepCopy(MFD.Seats.DEFAULT_PLAN)
    end
```

- [ ] **Step 2: Write UI_Config.lua**

Create `AddonProjects/anniversary/MarkedForDeath/UI_Config.lua`:

```lua
-- Seat editor and settings. Frames are built lazily on first Toggle and reused
-- from a pool on every refresh, never created and destroyed per row.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.Config = MFD.UI.Config or {}
local Config = MFD.UI.Config

local ROW_HEIGHT = 24     -- pixels
local ICON_ORDER = { 8, 7, 6, 2, 5, 1, 4, 3 }

-- Returns a reusable row from pool, creating it only when the pool is short.
-- Shared by every list in the addon so no list churns frames on refresh.
function MFD.UI.AcquireRow(parent, pool, index, height)
    local row = pool[index]
    if not row then
        row = CreateFrame("Frame", nil, parent)
        row:SetHeight(height)
        row:SetPoint("LEFT", parent, "LEFT", 8, 0)
        row:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
        pool[index] = row
    end
    row:SetPoint("TOP", parent, "TOP", 0, -((index - 1) * height) - 8)
    row:Show()
    return row
end

-- Hides every pooled row from index onward, so a shorter refresh does not leave
-- stale rows on screen.
function MFD.UI.ReleaseRows(pool, fromIndex)
    for i = fromIndex, #pool do
        if pool[i] then
            pool[i]:Hide()
        end
    end
end

local frame
local rows = {}

local function intentNames()
    local names = {}
    for intent in pairs(MFD.Seats.INTENTS) do
        names[#names + 1] = intent
    end
    table.sort(names)
    return names
end

local function buildRow(row, icon)
    if row.isBuilt then
        return
    end
    row.isBuilt = true

    row.texture = row:CreateTexture(nil, "ARTWORK")
    row.texture:SetSize(18, 18)
    row.texture:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")

    row.intentText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.intentText:SetPoint("LEFT", row.texture, "RIGHT", 8, 0)
    row.intentText:SetWidth(140)
    row.intentText:SetJustifyH("LEFT")

    row.cycle = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.cycle:SetSize(70, 20)
    row.cycle:SetPoint("LEFT", row.intentText, "RIGHT", 4, 0)
    row.cycle:SetText("Change")

    row.pinBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.pinBox:SetSize(120, 20)
    row.pinBox:SetPoint("LEFT", row.cycle, "RIGHT", 12, 0)
    row.pinBox:SetAutoFocus(false)

    row.ownerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.ownerText:SetPoint("LEFT", row.pinBox, "RIGHT", 10, 0)
    row.ownerText:SetWidth(140)
    row.ownerText:SetJustifyH("LEFT")

    row.cycle:SetScript("OnClick", function()
        local names = intentNames()
        local seat = MFD.db.seatPlan[icon]
        local current = seat and seat.intent
        local nextIndex = 1
        for i, name in ipairs(names) do
            if name == current then
                nextIndex = (i % #names) + 1
                break
            end
        end
        MFD.db.seatPlan[icon] = MFD.db.seatPlan[icon] or { ordinal = 1 }
        MFD.db.seatPlan[icon].intent = names[nextIndex]
        Config:Refresh()
    end)

    row.pinBox:SetScript("OnEnterPressed", function(box)
        local text = box:GetText()
        MFD.db.seatPlan[icon] = MFD.db.seatPlan[icon] or { intent = "KILL", ordinal = 1 }
        MFD.db.seatPlan[icon].pin = text ~= "" and text or nil
        box:ClearFocus()
        Config:Refresh()
    end)
end

-- Repaints every row from the current seat plan and the live roster, so the
-- Owner column shows who actually holds each seat right now.
function Config:Refresh()
    if not frame then
        return
    end

    local roster = MFD.Marker.CurrentRoster and MFD.Marker.CurrentRoster() or {}
    local resolved = MFD.Seats.Resolve(MFD.db.seatPlan, roster)

    for index, icon in ipairs(ICON_ORDER) do
        local row = MFD.UI.AcquireRow(frame.body, rows, index, ROW_HEIGHT)
        buildRow(row, icon)

        local seat = MFD.db.seatPlan[icon]
        SetRaidTargetIconTexture(row.texture, icon)
        row.intentText:SetText(seat and (MFD.Seats.INTENTS[seat.intent].label .. " " .. seat.ordinal) or "|cff999999unbound|r")
        row.pinBox:SetText(seat and seat.pin or "")

        local record = resolved.byIcon[icon]
        if not record then
            row.ownerText:SetText("|cff999999no seat|r")
        elseif record.owner == true then
            row.ownerText:SetText("|cff66ff66always available|r")
        elseif record.owner then
            row.ownerText:SetText("|cff66ff66" .. record.owner .. "|r")
        else
            row.ownerText:SetText("|cffff4444nobody can do this|r")
        end
    end

    MFD.UI.ReleaseRows(rows, #ICON_ORDER + 1)
end

function Config:Toggle()
    if not frame then
        frame = CreateFrame("Frame", "MarkedForDeathConfigFrame", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(620, 300)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.title:SetPoint("TOP", frame, "TOP", 0, -6)
        frame.title:SetText("Marked For Death: seats")

        frame.body = CreateFrame("Frame", nil, frame)
        frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -28)
        frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)

        tinsert(UISpecialFrames, "MarkedForDeathConfigFrame")
    end

    if frame:IsShown() then
        frame:Hide()
        return
    end

    Config:Refresh()
    frame:Show()
end

_G.MarkedForDeath = MFD
```

- [ ] **Step 3: Expose the roster builder and add the command**

In `Marker.lua`, change `local function currentRoster()` to `function Marker.CurrentRoster()` and update its two call sites inside that file.

Add to `Core.lua`:

```lua
commands.config = {
    desc = "open the seat editor",
    run = function()
        MFD.UI.Config:Toggle()
    end,
}
```

Add `UI_Config.lua` to the end of the TOC file list.

- [ ] **Step 4: Run the tests**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `77 passed, 0 failed, 77 total`. UI files are not loaded by the harness, so the count does not change. Confirm it did not drop.

- [ ] **Step 5: Verify in game**

1. Deploy, `/reload`, `/mfd config`
2. Eight rows appear, one per icon, with the correct icon textures and the default bindings: Skull/Cross/Square/Circle as Kill 1 to 4, Moon and Star as Sheep 1 and 2, Triangle and Diamond as Banish 1 and 2
3. Moon shows `Grimmtusk` in its pin box
4. Solo on a non-mage, Moon's owner column reads "nobody can do this" in red and Skull's reads "always available" in green
5. Click Change on Circle a few times and confirm the intent cycles and the owner column updates
6. Type a name into a pin box, press Enter, `/reload`, and confirm it persisted
7. Escape closes the window
8. BugSack is empty

- [ ] **Step 6: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add seat editor with live owner resolution"
```

---

### Task 12: Rule editor, mob search, and the add-target keybind

The workflow that makes rules practical to create. The keybind is the primary path; search is for planning away from the instance.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/Bindings.xml`
- Modify: `AddonProjects/anniversary/MarkedForDeath/UI_Config.lua` (rule tab)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Core.lua` (`rules`, `add` commands, binding globals)

**Interfaces:**
- Consumes: `MFD.Rules.NextRank`, `Reorder`, `BumpVersion` from Tasks 3 and 9; `MFD.UI.AcquireRow` from Task 11; `MFD.db.learnedMobs` from Task 7; `MFD.Data.Mobs` from Task 15 (guarded, may be absent until then).
- Produces:
  - `MFD.UI.Rules:Toggle()`, `MFD.UI.Rules:Refresh()`, `MFD.UI.Rules:OpenFor(npcID, name)`
  - `MFD.Search(query, instanceKey, bundled, learned) -> array of { npcID, name, source }` where source is `"bundled"` or `"learned"`. The two tables are arguments rather than globals so the function stays pure and testable; callers pass `MFD.Data and MFD.Data.Mobs or {}` and `MFD.db.learnedMobs`.
  - Bindings `MARKEDFORDEATH_ADD`, `MARKEDFORDEATH_REMARK`, `MARKEDFORDEATH_ASSIGNMENTS`

- [ ] **Step 1: Write the failing tests**

`MFD.Search` is pure, so it is tested. Append to `Tests.lua`, before the final `_G.MarkedForDeath = MFD` line:

```lua
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: the five new cases fail with `attempt to call field 'Search' (a nil value)`.

- [ ] **Step 3: Add Search to Helpers.lua**

Append to `Helpers.lua`, before its final `_G.MarkedForDeath = MFD` line:

```lua
-- Searches the bundled and learned mob tables. Takes a lowercase-insensitive
-- query, an optional instance key filter, the bundled table
-- ({ [npcID] = { name, instanceKey } }) and the learned table
-- ({ [npcID] = { name, zone } }). Returns an array of { npcID, name, source }
-- sorted by name. Pure, so the bundled and learned tables are arguments rather
-- than globals.
function MFD.Search(query, instanceKey, bundled, learned)
    local needle = string.lower(query or "")
    local results, seen = {}, {}

    for _, npcID in ipairs(H.SortedKeys(bundled)) do
        local entry = bundled[npcID]
        local matchesInstance = not instanceKey or entry[2] == instanceKey
        if matchesInstance and string.find(string.lower(entry[1]), needle, 1, true) then
            seen[npcID] = true
            results[#results + 1] = { npcID = npcID, name = entry[1], source = "bundled" }
        end
    end

    for _, npcID in ipairs(H.SortedKeys(learned)) do
        local entry = learned[npcID]
        if not seen[npcID] and entry.name and string.find(string.lower(entry.name), needle, 1, true) then
            results[#results + 1] = { npcID = npcID, name = entry.name, source = "learned" }
        end
    end

    table.sort(results, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.npcID < b.npcID
    end)

    return results
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath`

Expected: `82 passed, 0 failed, 82 total`, exit code 0.

- [ ] **Step 5: Write Bindings.xml and the keybind handlers**

Create `AddonProjects/anniversary/MarkedForDeath/Bindings.xml`:

```xml
<Bindings>
    <Binding name="MARKEDFORDEATH_ADD" header="MARKEDFORDEATH" category="ADDONS">
        MarkedForDeath.Bindings.AddTarget()
    </Binding>
    <Binding name="MARKEDFORDEATH_REMARK" category="ADDONS">
        MarkedForDeath.Bindings.Remark()
    </Binding>
    <Binding name="MARKEDFORDEATH_ASSIGNMENTS" category="ADDONS">
        MarkedForDeath.Bindings.ToggleAssignments()
    </Binding>
</Bindings>
```

Add to `Core.lua`, above the slash command block:

```lua
-- Binding display names. These must be globals; the client reads them by name
-- from the keybinding UI, which is the documented exception to the one-global
-- rule in CODING_STANDARDS.md.
BINDING_HEADER_MARKEDFORDEATH = "Marked For Death"
BINDING_NAME_MARKEDFORDEATH_ADD = "Add target as a rule"
BINDING_NAME_MARKEDFORDEATH_REMARK = "Re-mark the visible pack"
BINDING_NAME_MARKEDFORDEATH_ASSIGNMENTS = "Toggle the assignment panel"

MFD.Bindings = {}

-- Opens the rule editor pre-filled with whatever the player is pointing at.
-- This is the primary way rules get created; search is for planning at a desk.
function MFD.Bindings.AddTarget()
    local unit = UnitExists("target") and "target" or (UnitExists("mouseover") and "mouseover" or nil)
    if not unit then
        MFD.Error("target or mouse over a mob first")
        return
    end

    local guid = UnitGUID(unit)
    local key = guid and MFD.H.KeyFromGUID(guid)
    if not key then
        MFD.Error("that is not a creature")
        return
    end

    MFD.UI.Rules:OpenFor(MFD.H.NpcIDFromKey(key), UnitName(unit))
end

function MFD.Bindings.Remark()
    wipe(MFD.Marker.locked)
    MFD.Print("re-marking the visible pack")
end

function MFD.Bindings.ToggleAssignments()
    MFD.UI.Assignments:Toggle()
end
```

Add the matching commands:

```lua
commands.rules = {
    desc = "open the rule editor and mob search",
    run = function()
        MFD.UI.Rules:Toggle()
    end,
}

commands.add = {
    desc = "add the current target or mouseover as a rule",
    run = function()
        MFD.Bindings.AddTarget()
    end,
}
```

- [ ] **Step 6: Write the rule editor**

Append to `UI_Config.lua`, before its final `_G.MarkedForDeath = MFD` line, a `MFD.UI.Rules` table with:

- A `BasicFrameTemplateWithInset` frame named `MarkedForDeathRulesFrame`, registered in `UISpecialFrames`, movable, 700x420.
- A search `EditBox` at the top wired to `MFD.Search(text, filterKey, MFD.Data and MFD.Data.Mobs or {}, MFD.db.learnedMobs)` on `OnTextChanged`, repainting a results list built from `MFD.UI.AcquireRow` with a shared pool. Bundled rows use `GameFontNormal`, learned rows are prefixed with `|cffffcc66` per the amber standard.
- An instance filter button that cycles through `nil` then the sorted keys of `MFD.Rules.INSTANCE_KEYS`, defaulting to `MFD.Rules.currentInstanceKey`.
- A rule list below it, painted from `MFD.Rules.Ranked(MFD.Rules.merged[instanceKey] or {})`, each row showing icon-free text `rank`, `name`, `intent`, `fallback`, `maxCount`, an up arrow, a down arrow and a delete button. Rows whose `rule.owner` is not the player render in amber with `" (" .. rule.owner .. ")"` appended and their arrows and delete disabled, because merged rules are read only.
- Up and down call `MFD.Rules.Reorder(MFD.db.rules[instanceKey], index, -1 or 1)` then `MFD.Rules.BumpVersion(MFD.db)` then `MFD.Comms.Republish()` then `Refresh`.
- `OpenFor(npcID, name)` shows the frame, and if no local rule exists for that npcID in the current instance, appends `{ npcID = npcID, name = name, intent = "KILL", rank = MFD.Rules.NextRank(list) }` to `MFD.db.rules[instanceKey]`, bumps the version, republishes and refreshes with that row highlighted.
- Clicking a rule's intent cycles it through the sorted `MFD.Seats.INTENTS` keys, same as the seat editor.
- Editing a merged rule copies it into the local set first with `MFD.H.DeepCopy`, so a contributor's table is never aliased.

Every mutation of `MFD.db.rules` is followed by `MFD.Rules.BumpVersion(MFD.db)` and `MFD.Comms.Republish()`. Missing either leaves the raid out of sync, which is the single most likely bug in this task.

- [ ] **Step 7: Verify in game**

1. Deploy, `/reload`
2. Bind "Add target as a rule" in the keybinding UI under Marked For Death
3. Target a mob, press the bind. The rule editor opens with that mob added as a Kill rule at the bottom of the list.
4. Click its intent until it reads Sheep. Confirm the mob now takes Moon rather than Skull.
5. Add a second mob, use the up arrow to move it above the first, and confirm Skull moves to it.
6. Type part of a mob name in the search box and confirm results appear, with learned mobs in amber.
7. Set the instance filter and confirm the results narrow.
8. Delete a rule and confirm the icon disappears.
9. `/reload` and confirm every rule persisted.
10. With a second client, confirm a rule added on one appears on the other in amber, with the contributor's name, and that its arrows are disabled there.
11. `/mfd selftest` reports 82 passed. BugSack is empty.

- [ ] **Step 8: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add rule editor, mob search and the add-target keybind"
```

---

### Task 13: Assignment panel and chat announcements

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/UI_Assignments.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` (add it last)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Marker.lua` (announce on combat lock)

**Interfaces:**
- Consumes: `MFD.Marker.published`, `MFD.Marker.publishedDetail` from Task 10; `MFD.UI.AcquireRow` from Task 11.
- Produces:
  - `MFD.UI.Assignments:Toggle()`, `:Refresh()`
  - `MFD.Announce.Format(assignments) -> string` (pure)
  - `MFD.Announce.THROTTLE_SECONDS` -> `5`

- [ ] **Step 1: Write the failing tests**

Append to `Tests.lua`, before the final `_G.MarkedForDeath = MFD` line:

```lua
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
        { key = "1:A", icon = 8, intent = "KILL" },
    })
    T.Eq(line, "Skull>Kill | Moon>Sheep", "kill icons lead")
end)

T.Case("Announce: an empty assignment list produces nothing", function()
    T.Eq(MFD.Announce.Format({}), "", "nothing to say")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: three failures on `MFD.Announce` being nil.

- [ ] **Step 3: Write UI_Assignments.lua**

Create the file with:

```lua
-- The shared assignment panel and the raid-chat announcement.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.Assignments = MFD.UI.Assignments or {}
MFD.Announce = MFD.Announce or {}

MFD.Announce.THROTTLE_SECONDS = 5

-- Display order and names for the eight icons, kill icons first so the line
-- always opens with what dies first.
local ICON_NAMES = {
    [8] = "Skull", [7] = "Cross", [6] = "Square", [2] = "Circle",
    [5] = "Moon", [1] = "Star", [4] = "Triangle", [3] = "Diamond",
}
local ICON_ORDER = { 8, 7, 6, 2, 5, 1, 4, 3 }

-- Takes the allocator's assignment list. Returns one compact line for raid
-- chat, ordered by the display order above so it reads identically every pull.
-- Pure.
function MFD.Announce.Format(assignments)
    local byIcon = {}
    for _, a in ipairs(assignments) do
        byIcon[a.icon] = a
    end

    local parts = {}
    for _, icon in ipairs(ICON_ORDER) do
        local a = byIcon[icon]
        if a then
            local label = MFD.Seats.INTENTS[a.intent] and MFD.Seats.INTENTS[a.intent].label or a.intent
            parts[#parts + 1] = ICON_NAMES[icon] .. ">" .. label .. (a.owner and (" " .. a.owner) or "")
        end
    end

    return table.concat(parts, " | ")
end

_G.MarkedForDeath = MFD
```

Then append the panel: a small `BasicFrameTemplateWithInset` frame named `MarkedForDeathAssignmentsFrame`, in `UISpecialFrames`, movable, position saved to `MFD.charDb.windows.assignments`, painted from `MFD.Marker.published` and `MFD.Marker.publishedDetail` using `MFD.UI.AcquireRow`. Each row shows the raid icon texture via `SetRaidTargetIconTexture`, the intent label, and the owner. Refresh is driven from a 0.5 second accumulator on the frame's `OnUpdate`, and only while shown.

- [ ] **Step 4: Announce on combat lock**

In `Marker.lua`, inside the `PLAYER_REGEN_DISABLED` branch, after the lock loop, add:

```lua
            if MFD.db.settings.isAnnounceEnabled
                and MFD.Comms:IsAuthority()
                and desired
                and (GetTime() - (Marker.lastAnnounceAt or 0)) > MFD.Announce.THROTTLE_SECONDS then

                local line = MFD.Announce.Format(desired.list)
                if line ~= "" then
                    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
                    if channel then
                        SendChatMessage("[MFD] " .. line, channel)
                        Marker.lastAnnounceAt = GetTime()
                    end
                end
            end
```

- [ ] **Step 5: Run the tests**

Expected: `85 passed, 0 failed, 85 total`.

- [ ] **Step 6: Verify in game**

1. Deploy, `/reload`, add rules for two mob types
2. Bind and press "Toggle the assignment panel". It lists the current pack's icons, intents and owners.
3. Pull the pack. One `[MFD] Skull>Kill | Moon>Sheep Grimmtusk` line posts to party or raid chat.
4. Pull a second pack within five seconds and confirm no second line posts (throttled).
5. Move the panel, `/reload`, confirm the position persisted.
6. Turn announcements off via `MarkedForDeathDB.settings.isAnnounceEnabled = false` and confirm chat goes quiet while the panel still updates.
7. BugSack is empty.

- [ ] **Step 7: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add assignment panel and throttled raid announcements"
```

---

### Task 14: Rule set import and export

**Files:**
- Modify: `AddonProjects/anniversary/MarkedForDeath/Helpers.lua` (base64)
- Modify: `AddonProjects/anniversary/MarkedForDeath/UI_Config.lua` (a copy/paste box)
- Modify: `AddonProjects/anniversary/MarkedForDeath/Core.lua` (`export`, `import`)

**Interfaces:**
- Consumes: `MFD.Rules.Serialize`, `Deserialize` from Task 9.
- Produces: `MFD.H.Base64Encode(str) -> string`, `MFD.H.Base64Decode(str) -> string|nil`

- [ ] **Step 1: Write the failing tests**

```lua
T.Case("Base64: round-trips arbitrary bytes", function()
    for _, sample in ipairs({ "", "a", "ab", "abc", "Illidari Nightlord;22890;SHEEP;10" }) do
        T.Eq(MFD.H.Base64Decode(MFD.H.Base64Encode(sample)), sample, "round trip of [" .. sample .. "]")
    end
end)

T.Case("Base64: decoding rubbish returns nil rather than garbage", function()
    T.Eq(MFD.H.Base64Decode("not base64!!"), nil, "rejected")
end)

T.Case("Rules: a full export round-trips through base64", function()
    local rules = { BT = { { npcID = 1, name = "A", intent = "KILL", rank = 10 } } }
    local encoded = MFD.H.Base64Encode(MFD.Rules.Serialize(rules))
    local restored = MFD.Rules.Deserialize(MFD.H.Base64Decode(encoded))
    T.Eq(restored.BT[1].npcID, 1, "survived the trip")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: three failures on `MFD.H.Base64Encode` being nil.

- [ ] **Step 3: Implement base64 in Helpers.lua**

Append to `Helpers.lua`, before its final `_G.MarkedForDeath = MFD` line:

```lua
local B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP = {}
for i = 1, #B64_ALPHABET do
    B64_LOOKUP[string.sub(B64_ALPHABET, i, i)] = i - 1
end

-- Standard base64. Hand-rolled rather than pulled from a library so the addon
-- folder stays free of dependencies; rule sets are small enough that the extra
-- string length costs nothing worth a vendored lib.
function H.Base64Encode(str)
    local out = {}

    for i = 1, #str, 3 do
        local a, b, c = string.byte(str, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64

        out[#out + 1] = string.sub(B64_ALPHABET, c1 + 1, c1 + 1)
        out[#out + 1] = string.sub(B64_ALPHABET, c2 + 1, c2 + 1)
        out[#out + 1] = b and string.sub(B64_ALPHABET, c3 + 1, c3 + 1) or "="
        out[#out + 1] = c and string.sub(B64_ALPHABET, c4 + 1, c4 + 1) or "="
    end

    return table.concat(out)
end

-- Returns the decoded string, or nil when the input is not valid base64. A
-- mistyped import string must fail loudly rather than produce a corrupt rule
-- set, so both the length and every character are checked.
function H.Base64Decode(str)
    if type(str) ~= "string" then
        return nil
    end

    if str == "" then
        return ""
    end

    if #str % 4 ~= 0 then
        return nil
    end

    local out = {}

    for i = 1, #str, 4 do
        local values, padding = {}, 0

        for j = 1, 4 do
            local char = string.sub(str, i + j - 1, i + j - 1)
            if char == "=" then
                padding = padding + 1
                values[j] = 0
            else
                local value = B64_LOOKUP[char]
                if not value then
                    return nil
                end
                values[j] = value
            end
        end

        local n = values[1] * 262144 + values[2] * 4096 + values[3] * 64 + values[4]
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if padding < 2 then
            out[#out + 1] = string.char(math.floor(n / 256) % 256)
        end
        if padding < 1 then
            out[#out + 1] = string.char(n % 256)
        end
    end

    return table.concat(out)
end
```

- [ ] **Step 4: Add the commands and the UI box**

```lua
commands.export = {
    desc = "print a shareable string of your own rules",
    run = function()
        MFD.UI.Rules:ShowTransferBox(MFD.H.Base64Encode(MFD.Rules.Serialize(MFD.db.rules)), "export")
    end,
}

commands["import"] = {
    desc = "open a box to paste a rule string into",
    run = function()
        MFD.UI.Rules:ShowTransferBox("", "import")
    end,
}
```

`ShowTransferBox(text, mode)` is a multiline `EditBox` inside a scroll frame. In export mode it is read only with the text selected for copying. In import mode, an Import button decodes, deserialises, and on success **merges into rather than replaces** `MFD.db.rules`, keyed by instance and npcID, so a paste cannot silently destroy existing work. On failure it prints the reason from `Deserialize`. After a successful import it calls `MFD.Rules.BumpVersion(MFD.db)` and `MFD.Comms.Republish()`.

- [ ] **Step 5: Run the tests**

Expected: `88 passed, 0 failed, 88 total`.

- [ ] **Step 6: Verify in game**

1. `/mfd export` with several rules, copy the string
2. Delete one rule, `/mfd import`, paste, Import
3. Confirm the deleted rule returns and nothing else changed
4. Paste a deliberately corrupt string and confirm it prints a specific reason and changes nothing
5. `/reload` and confirm persistence
6. BugSack is empty

- [ ] **Step 7: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add rule set import and export strings"
```

---

### Task 15: Compiled TBC mob database

Built last, deliberately. It carries the only real external-data risk in the project, and everything else already works without it because of the learning layer.

**Files:**
- Create: `AddonProjects/anniversary/MarkedForDeath/Data_Mobs.lua`
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` (add after `Helpers.lua`)

**Interfaces:**
- Produces: `MFD.Data.Mobs` -> `{ [npcID] = { name:string, instanceKey:string } }`

- [ ] **Step 1: Source the data**

Compile `{ npcID, name, instanceKey }` for the nine TBC raids: Karazhan, Gruul's Lair, Magtheridon's Lair, Serpentshrine Cavern, Tempest Keep, Hyjal Summit, Black Temple, Zul'Aman, Sunwell Plateau. Include bosses and trash.

Cross-check every entry against a second source before accepting it. Do not accept a single source's word for an npc id. Where two sources disagree, omit the entry: a wrong id silently marks the wrong mob, while a missing id is filled in by the learning layer the first time the raid walks past it.

If sourcing produces fewer than roughly 300 verified entries, **ship the file with what you have and say so in the PR.** Partial data plus learning is strictly better than delaying the addon, and the whole point of building this last was that nothing depends on it.

- [ ] **Step 2: Write Data_Mobs.lua**

```lua
-- Compiled TBC raid NPC table. Pure data, no logic.
--
-- Entries are cross-checked against two sources; where sources disagreed the
-- entry was omitted rather than guessed, because the learning layer fills gaps
-- automatically and a wrong npc id silently marks the wrong mob.
local MFD = _G.MarkedForDeath or {}

MFD.Data = MFD.Data or {}

-- [npcID] = { name, instanceKey }
MFD.Data.Mobs = {
    [22890] = { "Illidari Nightlord", "BLACKTEMPLE" },
    -- ... remaining verified entries
}

_G.MarkedForDeath = MFD
```

- [ ] **Step 3: Add a coverage check command**

```lua
commands.coverage = {
    desc = "compare learned mobs against the bundled database",
    run = function()
        local bundled, learned, missing = 0, 0, {}
        for _ in pairs(MFD.Data.Mobs) do bundled = bundled + 1 end
        for npcID, entry in pairs(MFD.db.learnedMobs) do
            learned = learned + 1
            if not MFD.Data.Mobs[npcID] then
                missing[#missing + 1] = npcID .. " " .. tostring(entry.name)
            end
        end
        MFD.Print(bundled .. " bundled, " .. learned .. " learned, " .. #missing .. " seen but not bundled")
        for i = 1, math.min(#missing, 20) do
            MFD.Print("  |cffffcc66" .. missing[i] .. "|r")
        end
    end,
}
```

- [ ] **Step 4: Verify in game**

1. `/mfd rules`, search for a known Black Temple trash name, confirm it appears as bundled rather than amber
2. Run a raid, then `/mfd coverage` and confirm the "seen but not bundled" list is short
3. Feed any legitimate misses back into `Data_Mobs.lua`
4. Confirm names in the bundled table match what the client actually reports for the same npc id. A mismatch means the source used a different locale or a renamed spawn.

- [ ] **Step 5: Commit**

```bash
git add AddonProjects/anniversary/MarkedForDeath
git commit -m "Add compiled TBC raid mob database"
```

---

### Task 16: Documentation, versioning and the pull request

**Files:**
- Create: `Docs/MarkedForDeath.md`
- Modify: `AddonProjects/anniversary/README.md` (version table)
- Modify: `AddonProjects/anniversary/MarkedForDeath/MarkedForDeath.toc` and `Core.lua` (version bump)

- [ ] **Step 1: Write the player guide**

`Docs/MarkedForDeath.md` covering: what it does and the one-paragraph explanation of seats; first-run setup (open `/mfd config`, bind the add-target key, add rules as you raid); every slash command with its one-line description, matching `/mfd help` exactly; the Raid Lead designation and what happens when the lead is absent; how rule merging works and the fact that it never writes to your saved variables; the nameplate requirement and `/mfd fixcvars`; and a troubleshooting section keyed to what `/mfd status` reports.

- [ ] **Step 2: Bump the version to 1.0.0 in both places**

`## Version: 1.0.0` in the `.toc` and `MFD.VERSION = "1.0.0"` in `Core.lua`. These must match, and must match the zip name in the next step.

- [ ] **Step 3: Update the anniversary README table**

Add the row, matching the existing format:

```
| MarkedForDeath | 1.0.0 | [Docs/MarkedForDeath.md](../../Docs/MarkedForDeath.md) |
```

- [ ] **Step 4: Run the full checklist**

- `powershell -File scripts/run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath` passes
- Loads on the client with "Load out of date AddOns" off, BugSack empty
- Every command in `commands` appears in `/mfd help` and in `Docs/MarkedForDeath.md`
- Every wait has a timeout and a visible failure message: rule transfer, election fallback, defense brake
- No new globals other than the addon table, the three `BINDING_NAME_*` and one `BINDING_HEADER_*`, and the three named frames in `UISpecialFrames`
- The temporary `testrule` command and the `MFD.Comms` stub from Task 6 are both gone

- [ ] **Step 5: Package and deliver**

```bash
powershell -File scripts/package.ps1 -Flavor anniversary -Addon MarkedForDeath
```

Confirm the zip is named `MarkedForDeath-1.0.0-anniversary.zip` and send it to the user with SendUserFile.

- [ ] **Step 6: Open the pull request**

```bash
git push -u origin feature/marked-for-death
gh pr create --fill
```

Fill the template's "In-game steps run" section with the actual commands and clicks performed, and **state explicitly whether in-game verification was completed**, including which parts were verified with a second client and which were not. The repo requires this.

- [ ] **Step 7: Commit**

```bash
git add Docs/MarkedForDeath.md AddonProjects/anniversary/README.md AddonProjects/anniversary/MarkedForDeath
git commit -m "Document Marked For Death and release 1.0.0"
```
