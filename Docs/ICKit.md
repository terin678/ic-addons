# ICKit

The shared kit under the Impulse Control addons for WoW Forever (interface 16001). It is a
library addon: the Forever addons list it under `## Dependencies` and fetch what they need
with LibStub. On its own it adds one command and nothing on screen.

It is built bottom-up, one layer at a time. [forever/VISION.md](forever/VISION.md) has the
rules and the order. It is a different code base from [ICLibs](ICLibs.md), which serves the
TBC Anniversary addons, and the two are never installed on the same client.

## Install

Extract into `_classic_beta_\Interface\AddOns` so you get `AddOns\ICKit\ICKit.toc`. Restart
the client after installing; a `/reload` does not pick up a new addon.

## Commands

```
/ickit                  the kit's version, the client build, and how often its saved tables have loaded
/ickit probe            check what this client offers and save the answers
/ickit profile [reset]  what the kit's handlers have cost: calls, time, memory
/ickit test             run the built-in checks
/ickit debug on|off     maintainer lines in chat
/ickit help
```

### The probe

Nobody has an interface source for the Forever client, so the layers above are built on what
`/ickit probe` finds. It asks whether some fifty globals exist, tries the frame templates
and the object methods the widgets would use, records a few values (the build, the screen
size, how the client names this character), and notes the order the load events arrived in.
The chat shows a short summary; the whole report is saved to `ICKitDB.probe` and reaches
disk at the next `/reload`, in `WTF\Account\<account>\SavedVariables\ICKit.lua`.

### The profile

`/ickit profile` lists every handler the kit has wrapped with how many times it has run and
how long it took, then the client's own memory and CPU figures for the addon when it offers
them. A handler whose call count keeps climbing while you stand still is doing work it
should not. The counters cost two clock reads a call and need no console variable.

## Contents

| Library | MINOR | What it does |
| --- | --- | --- |
| LibStub | — | Standard library loader |
| LibICUtil-1.0 | 1 | Pure helpers for text, tables and lists. Calls nothing in the game client |
| LibICTest-1.0 | 1 | The case runner behind every addon's `test` command, headless and in game |
| LibICEnv-1.0 | 1 | What this client offers (build, a feature probe) and what handlers cost (call and time counters, memory) |
| LibICStore-1.0 | 1 | Saved variables: defaults, schema, migrations, and whether the file really loaded |
| LibICConsole-1.0 | 1 | Prefixed printing and the slash-command dispatcher with its help |

The libraries never print. An addon decides what to say, in its own voice.

The MINOR goes up whenever a library's API changes. Bump it in the library source and in
this table together; `scripts/lint.py` fails when the two disagree.

## LibICUtil-1.0

```lua
local Util = LibStub("LibICUtil-1.0")
```

| Call | Returns |
| --- | --- |
| `Util.Trim(s)` | `s` with whitespace off both ends. |
| `Util.StripEscapes(s)` | `s` without colour codes, hyperlinks or inline textures; a link keeps its label. |
| `Util.Truncate(s, n)` | `s` cut to `n` bytes, never in the middle of a character or an escape. |
| `Util.Clean(s, maxLen)` | Text a person typed, made safe to store and draw: escapes and pipes out, line breaks and runs of spaces flattened, cut to `maxLen` (255 by default). |
| `Util.Plural(n, one, many)` | `one` when `n` is 1, else `many` (or `one` with an `s`). |
| `Util.SortedKeys(t)` | The table's keys in a stable order: numbers by value, then strings. |
| `Util.DeepCopy(t)` | A copy that shares no table with the original. |
| `Util.Clamp(n, lo, hi)` | `n` held inside `lo..hi`; a value that is not a number comes back as `lo`. |
| `Util.Move(list, from, to)` | Moves one element of a list and returns whether anything moved. |

Trim through DeepCopy are lifted from LibICCore-1.0, with one change: `SortedKeys` orders
numeric keys by value, where the original compared them as text and put 10 before 2.

## LibICTest-1.0

```lua
local Test = LibStub("LibICTest-1.0")
local T = Test.New({ print = Print, onDone = function(result) end })

T.Case("Notes: a blank line is refused", function()
    T.Eq(Notes.AddLine(note, "  "), false, "nothing to add")
end)

local passed, failed = T.Run()
```

| Call | What it does |
| --- | --- |
| `Test.New(opts)` | A new registry. `opts.print(line)` receives each failure and the summary; `opts.onDone(result)` receives `{ passed, failed, failures = { { name, err } } }`. |
| `T.Case(name, fn)` | Registers a case. |
| `T.Eq(actual, expected, label)` | Raises unless the two are equal. |
| `T.True(value, label)` | Raises unless the value is truthy. |
| `T.Near(actual, expected, tolerance, label)` | Raises unless within `tolerance` (0.001 by default). `T.Near(actual, expected, label)` works too. |
| `T.Run()` | Runs every case and returns `passed, failed`. |

An addon keeps its registry at `ns.Tests`; that is where the headless harness looks. A
registry knows nothing about saved variables or windows: model functions take their tables
as arguments, so a case builds its own input.

## LibICEnv-1.0

```lua
local Env = LibStub("LibICEnv-1.0")
```

| Call | Returns |
| --- | --- |
| `Env.Build()` | `{ version, build, date, interface }` from the client. |
| `Env.Resolve(path, root)` | The value at a dotted path such as `"C_Timer.After"`, or nil. `root` defaults to the global table. |
| `Env.Has(path, root)` | `present, kind`: whether it exists and its type, or `false, "missing"`. |
| `Env.Probe(checks, root)` | One row `{ path, present, kind, why }` per check. A check is a path or `{ path, why }`. |
| `Env.Try(label, fn, ...)` | Calls `fn` under `pcall`: `{ label, ok, n, values, text }`, or `{ label, ok = false, err }`. For asking the client something it may not support. |
| `Env.Wrap(label, fn)` | `fn`, counted: every call adds to the label's calls, total and worst time. |
| `Env.Counters()` | Rows `{ label, calls, total, max }` in milliseconds, costliest first. |
| `Env.ResetCounters()` | Zeroes every counter. |
| `Env.SetClock(fn)` | Replaces the millisecond clock; a case hands in its own. |
| `Env.Memory(addon)` | The client's memory figure for an addon in KB, or nil when it will not say. |
| `Env.Cpu(addon)` | `ms, source` from the client, or `nil, "unavailable"`. |

Wrap every event handler and slash command at the point it is registered:

```lua
frame:SetScript("OnEvent", Env.Wrap("Stickies events", function(self, event) ... end))
```

## LibICStore-1.0

```lua
local Store = LibStub("LibICStore-1.0")

Store.Register(addonName, {
    account = "StickiesDB",              -- ## SavedVariables
    character = "StickiesCharDB",        -- ## SavedVariablesPerCharacter, optional
    schema = 1, charSchema = 1,
    defaults = { settings = { debug = false } },
    charDefaults = {},
    migrations = { [1] = function(db) end },   -- keyed by the schema each upgrades FROM
    onReady = function(db, cdb, info) end,
})
```

Call `Register` at file scope. `onReady` runs once, when the client has handed the tables
back: migrations first, then defaults, then your function. `info` is
`{ sawFile, firstRun, migrated, lost }`. `lost` means the account file came back empty
although this character has run the addon before, which a client left running across
`.toc` edits will do; say so in red and tell the player not to log out, because that
writes the empty table over the file.

| Call | What it does |
| --- | --- |
| `Store.Boot(spec, globals)` | The same work on a table you hand in, returning `db, cdb, info`. This is what a case calls. |
| `Store.ApplyDefaults(target, defaults)` | Fills in what is missing and keeps what is there, a stored `false` included. |
| `Store.Migrate(db, steps, head)` | Runs the steps from the saved schema to `head` and returns how many ran. An empty table starts at the head. |

## LibICConsole-1.0

```lua
local Console = LibStub("LibICConsole-1.0")
local out = Console.New("Stickies", { debug = function() return ns.db.settings.debug end })

Console.Slash({
    key = "STICKIES", slash = { "/sticky", "/stickies" }, out = out,
    help = { { "", "show or hide every note" }, { "new [title]", "start a note" } },
    commands = { [""] = Toggle, new = function(rest, cmd) end },
})
```

| Call | What it does |
| --- | --- |
| `Console.New(prefix, opts)` | `out.Print(msg)`, `out.Printf(fmt, ...)`, and `out.Debug(fmt, ...)` which prints only while `opts.debug()` is true. `opts.color` is the prefix's `rrggbb`; `opts.frame()` picks the chat frame. |
| `Console.Parse(input)` | `cmd, rest`: the first word lower-cased, the remainder trimmed. |
| `Console.HelpLines(slash, rows)` | The lines a help command prints. |
| `Console.Dispatcher(spec)` | `handler, Help` without registering anything, for a case. |
| `Console.Slash(spec)` | Registers the command and returns `handler, taken`. `taken` says another addon already held the key. |

A command is `fn(rest, cmd)`. The bare command is the `""` entry. A word with no entry
prints the help.

## Running the cases

```
.\scripts\run-tests.ps1 -Flavor forever -Addon ICKit
```

The harness loads an addon's `## Dependencies` first, each from its own `.toc`, then the
addon, then runs `ns.Tests.Run()`. In game the same cases run with `/ickit test`.
