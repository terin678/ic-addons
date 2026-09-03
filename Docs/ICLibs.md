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
| LibICUI-1.0 | List and toolbar widgets, relative ages, and the guild brand (mark and palette) |

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

## LibICUI-1.0

Window widgets that follow "Window layout" in `CODING_STANDARDS.md` by construction:
headers sit outside the scroll child, rows are a fixed height and never wrap, toolbars go
above the headers.

```lua
local UI = LibStub("LibICUI-1.0")
```

| Call | Returns |
| --- | --- |
| `UI:Age(seconds)` | Relative age for a list cell: `now`, `42s`, `7m`, `3h`, `2d`. |
| `UI:Style(name, style)` | Registers an addon's look (row height, fonts, colours) and fills in the rest from the default. Pass the name or the table as `opts.style`. |
| `UI:ScrollList(parent, top, bottom, right)` | Plain scroll frame and content child. |
| `UI:Toolbar(parent, opts)` | A control row: `tb:Left(widget)` appends, `tb:Right(widget)` packs from the right. |
| `UI:Table(parent, opts)` | Header frame plus a pooled fixed-height row list. `t:Render(list, fill)`, `t:Row(i)`, `t:Set(row, key, text)`, `t:SetSelected(item)`. |
| `UI:Logo(parent, size, large)` | The guild mark as a texture. |
| `UI:Hex(color)` | A `\|cffrrggbb` code from a brand colour. |

`Table` columns are descriptors: `{ key, label, width | "flex", justify, type = "text" |
"texture" | "check", font }`. One column may be `"flex"` and takes the leftover width.
`buttons = { { key, label, width } }` adds a trailing button column packed against the
right edge; pass `makeButton` to build them in the addon's own style.

### Brand

`UI.Brand` carries the guild's identity so every addon looks like one family: `name`,
`logo` and `logoLarge` texture paths, and the colours `ink` (#152333, window ground),
`panel` (#192637), `gold` (#DF9C33, accents), `flame` (#C3402F, danger) and `bone`
(#F4E5C1, headings). The mark lives at `ICLibs/Textures/ImpulseControl-64.tga`; the
master image is `Docs/assets/impulse-control.png`. Never copy either into an addon folder.

## Used by

- MalexisAuctionWatcher: scans every profession window into a per-character book and adds
  recipes from it (Recipes tab, Presets, "From your recipe book...").
- TradeMaster: the book scanner behind every tab, and LibICUI for every list and the
  branded window header.
