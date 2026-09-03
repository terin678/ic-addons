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
| LibICUI-1.0 | Windows, tabs, buttons, lists and toolbars in the guild palette, plus relative ages and the brand itself |

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
| `UI:Window(name, opts)` | A movable, escapable window wearing the guild mark. `f.body` is the area under the title bar, plus `f.title` and `f.status`. |
| `UI:TabStrip(parent, opts)` | A row of tab buttons; the live one goes gold. `strip:Select(name or index)` calls `onSelect`. |
| `UI:Button(parent, text, w, h, opts)` | A palette button. `opts.kind` is `"normal"`, `"accent"` or `"danger"`; `opts.template` adds a frame template such as `SecureActionButtonTemplate`. `SetText`, `Enable`, `Disable` and `SetEnabled` work as on a Blizzard button, and `b:SetActive(on)` shows a toggle's state. |
| `UI:EditBox(parent, w, h, opts)` | A single-line text box in the palette. |
| `UI:CheckBox(parent, label, opts)` | Blizzard's check button with a palette label; `opts.labelSide = "LEFT"` puts the label before it. |
| `UI:Tooltip(widget, builder)` | Wires a GameTooltip onto anything: `builder(widget)` adds the lines. `nil` takes it off again, which is what a pooled row needs. |
| `UI:Skin(frame, color, border)` / `UI:Panel(parent, opts)` | Paints a frame, or makes a raised panel. |
| `UI:ScrollList(parent, top, bottom, right)` | Plain scroll frame and content child. |
| `UI:Toolbar(parent, opts)` | A control row: `tb:Left(widget)` appends, `tb:Right(widget)` packs from the right. |
| `UI:Table(parent, opts)` | Header frame plus a pooled fixed-height row list. `t:Render(list, fill)`, `t:Row(i)`, `t:Set(row, key, text, color)`, `t:Span(row, text)`, `t:Tint(row, color)`, `t:SetSelected(item)`. |
| `UI:Logo(parent, size, large)` | The guild mark as a texture. |
| `UI:Hex(color)` | A `\|cffrrggbb` code from a brand colour. |

`Table` columns are descriptors: `{ key, label, width | "flex", justify, type = "text" |
"texture" | "check" | "custom", font, hit, make }`. One column may be `"flex"` and takes
the leftover width. `hit = true` puts an invisible button over the cell, at `row.hit[key]`,
for a tooltip or a click (a FontString takes neither); `type = "custom"` hands the cell to
your own `make(row, col, x, style)`, which is how a row gets arrows or icons.
`buttons = { { key, label, width, kind, template } }` adds a trailing button column packed
against the right edge; pass `makeButton` to build them yourself.

Every row comes back from the pool blank: cells are cleared and any tooltip from the
previous item is taken off, so `fill` only has to set what the row actually shows.
`t:Span(row, text)` turns a row into a full-width label for a section heading inside a
list, and `t:Tint(row, color)` marks a totals line.

### Theme

The palette is the default and nothing has to ask for it: a button, edit box, window or
tab built through this library is already in the guild colours. A style may set
`theme = false` to get plain Blizzard controls instead, per addon, without touching any
call site.

### Brand

`UI.Brand` carries the guild's identity so every addon looks like one family: `name`,
`logo` and `logoLarge` texture paths, and the colours `ink` (#152333, window ground),
`panel` (#192637), `gold` (#DF9C33, accents), `flame` (#C3402F, danger) and `bone`
(#F4E5C1, headings). The mark lives at `ICLibs/Textures/ImpulseControl-64.tga`; the
master image is `Docs/assets/impulse-control.png`. Never copy either into an addon folder.

## Used by

- MalexisAuctionWatcher: scans every profession window into a per-character book and adds
  recipes from it (Recipes tab, Presets, "From your recipe book..."), and builds its
  window, its six tabs, every list and its dialogs on LibICUI.
- TradeMaster: the book scanner behind every tab, and LibICUI for the window, the tabs,
  every list and every button.
