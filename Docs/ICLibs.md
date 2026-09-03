# ICLibs

Shared libraries for the ic-addons guild addons, packaged as a small library addon so the
same code is loaded once and both MalexisAuctionWatcher and TradeMaster use it.

## Install

Extract the zip of any addon that needs it; the `ICLibs` folder is included. It must sit
in `Interface\AddOns` next to the addon. The dependent addons list it under
`## Dependencies`, so the game refuses to load them without it and says why.

## Contents

| Library | What it does |
| --- | --- |
| LibStub | Standard library loader |
| LibICTradeSkill-1.0 | Reads the open profession window into plain tables, merges scans into a per-profession book, and checks Bind on Pickup reagents |

## LibICTradeSkill-1.0

```lua
local Lib = LibStub("LibICTradeSkill-1.0")
```

| Call | Returns |
| --- | --- |
| `Lib:OpenLine()` | Name of the open profession window, or nil. Enchanting (Craft API) is not covered. |
| `Lib:ReadOpen(opts)` | `rows, failed`. One pass with the window's filters cleared and restored; `opts.keepFilters` leaves them. `failed` lists row indexes whose item was not cached. |
| `Lib:ScanOpen(callback, opts)` | Reads, retries once after half a second for uncached items while the same window is open, then `callback(rows, failed, lineName)`. Synchronous when no retry is needed. |
| `Lib:MergeBook(oldBook, rows, opts)` | `newBook, added`. Book keyed by product itemID. `opts.preserve` names fields carried over from the previous entry (user flags). Entries missing from the scan stay with `stale = true`. |
| `Lib:MissingBoP(row)` | `{ {itemID, need, have}, ... }` for Bind on Pickup reagents you hold too few of, bags plus bank. |
| `Lib:DescribeMissing(list, withCounts)` | `"Primal Nether"` or `"Primal Nether x1 (have 0)"`. |

A row holds `itemID`, `name` (product), `link`, `skillName` (the recipe line, e.g.
"Transmute: Primal Might"), `skillType`, `header`, `classID`, `subClassID`, `quality`,
`bindType`, `numMade`, `reagents` (`[itemID] = count`), `reagentList` (ordered, with
names and links) and `reagentBind`.

## Used by

- MalexisAuctionWatcher: scans every profession window into a per-character book and adds
  recipes from it (Recipes tab, Presets, "From your recipe book...").
- TradeMaster: the book scanner behind every tab.
