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
/ickit          the kit's version and the client build it is running on
/ickit test     run the built-in checks
```

## Contents

| Library | MINOR | What it does |
| --- | --- | --- |
| LibStub | — | Standard library loader |
| LibICUtil-1.0 | 1 | Pure helpers for text, tables and lists. Calls nothing in the game client |
| LibICTest-1.0 | 1 | The case runner behind every addon's `test` command, headless and in game |

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

## Running the cases

```
.\scripts\run-tests.ps1 -Flavor forever -Addon ICKit
```

The harness loads an addon's `## Dependencies` first, each from its own `.toc`, then the
addon, then runs `ns.Tests.Run()`. In game the same cases run with `/ickit test`.
