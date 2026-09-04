# ICLibs

Shared libraries for the Impulse Control guild addons, packaged as a small library addon
so the same code is loaded once and MalexisAuctionWatcher, TradeMaster, ICTemplate and
GuildRecruitment all use it.

## Install

Extract the zip of any addon that needs it; the `ICLibs` folder is included. It must sit
in `Interface\AddOns` next to the addon. The dependent addons list it under
`## Dependencies`, so the game refuses to load them without it and says why. The
third-party libraries every addon uses -- LibStub, CallbackHandler, LibDataBroker,
LibDBIcon -- load here once; no addon bundles its own copy.

The guild addons carry `## Category: Impulse Control`, so they collapse under one
heading in the in-game AddOns list, and a `## Group:` naming the addon that heads its area:
ICLibs for Core, MalexisAuctionWatcher for Auction, TradeMaster for Professions. A group's
value has to be an addon that exists -- a made-up name silently ungroups everything that
uses it -- so the area's name is whatever its head addon is called. The guild mark in
`Textures/ImpulseControl-64` is the icon for the addons with no art of their own.
CutMaster is the exception: it belongs to a collaborator and is not ours to edit, so it
carries neither directive and sits on its own in the alphabetical list.
`Docs/client-reference.md` has the rest.

## Contents

| Library | MINOR | What it does |
| --- | --- | --- |
| LibStub | — | Standard library loader |
| CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 | — | The minimap launcher, and what it stands on |
| LibICCore-1.0 | 1 | The plumbing every addon used to carry its own copy of: Print, the saved-variable bootstrap and its load check, Util, Log, the test harness, the slash dispatcher, reset, the minimap launcher, the probe |
| LibICTradeSkill-1.0 | 2 | Reads the open profession window into plain tables, merges scans into a per-profession book, and checks Bind on Pickup reagents |
| LibICUI-1.0 | 6 | Windows, tabs, buttons, lists and toolbars in the guild palette, plus relative ages and the brand itself |

The MINOR goes up whenever a library's API changes, and LibStub hands every caller the
highest one loaded. Bump it in the library source and in this table together, or a reader
has no way to tell whether a change that needed a bump got one.

## LibICCore-1.0

```lua
local Core = LibStub("LibICCore-1.0")
Core:Attach(ns, {
    name = addonName, prefix = "GuildRecruitment", version = VERSION,
    db = "GuildRecruitmentDB", cdb = "GuildRecruitmentCharDB",     -- cdb is optional
    defaults = Defaults, charDefaults = CharDefaults,
    schema = 1, migrations = Migrations, charSchema = 1,
    slash = { "/gr", "/guildrecruitment" }, slashKey = "GUILDRECRUITMENT",
    help = HELP, commands = COMMANDS,
    logKinds = { sent = "|cff44ff44" },     -- extra Log colours
    onLoad = function(info) end,          -- info.sawFile, info.firstRun, info.migrated
    onToggle = function(on) end, onReset = function(what) end,
    loadedHint = "/gr opens the window, /gr help lists commands.",   -- or a function
    log = false,                          -- only for an addon with a Log of its own shape
})
```

One call, and the namespace has everything the addons used to carry a copy of each,
under the names they already used:

| On `ns` | What |
| --- | --- |
| `Print`, `Printf`, `Debug` | Prefixed chat output on the frame `/x out` chose; `Debug` only when `settings.debug` |
| `Enabled`, `Now` | The master switch and the one clock |
| `DeepCopy`, `ApplyDefaults`, `Migrate` | The saved-variable helpers |
| `Util` | Trim, StripEscapes, Normalize, Truncate, SortedKeys, Serialize, Clean, Plural, OnOff, Duration, Freshness. An addon adds its own on top |
| `Log` | The two ring buffers: Add, Capture, Window, Filter, Recent, Sources, Describe, KIND_COLOR |
| `Tests` | Case, Eq, True, Near, With, Run; the result goes to `db.lastTestRun` |
| `Reset(what)` | `all`, `log`, or any top-level key of the defaults |
| `db`, `cdb`, `VERSION`, `Core` | Set at ADDON_LOADED |

The slash dispatcher parses `/x <sub> <rest>` and comes with `help`, `log [n]`, `probe`,
`status`, `test`, `enable`, `disable`, `out [n]`, `reset [...]`, `scale [pct]` and
`version`; a key in `commands` adds a sub-command or replaces a built-in, and `""`
is the bare command. `help` prints the `HELP` rows; a row with `needs = "Module"` is
shown only when `ns.Module` exists.

The bootstrap runs on the addon's own ADDON_LOADED: migrate, then default, then publish,
then log **whether the client handed the saved variables back at all**. An account that
has run the addon before and comes up empty gets a red line saying so before anything is
edited, because the damage is not the empty load but the logout after it. The cause is a
client that has been running across `.toc` edits; the cure is a restart.

Also on the library: `Core:MinimapButton(ns, { name, icon, onClick(button), tooltip(tt) })`
for a LibDBIcon launcher whose position lives in `settings.minimap`; `Core:Probe(ns, CHECKS)`
for the "does this client have X" list, installing `Rows`, `PrintChecks` and a default
`Run` on `ns.Probe`; and `Core:Bindings(key, header, names)` for the `BINDING_*` globals.

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
| `UI:Window(name, opts)` | A movable, escapable window wearing the guild mark. `f.body` is the area under the title bar, plus `f.title` and `f.status`. `opts.scalable` puts a drag grip in the bottom-right corner; with it come `f:SetWindowScale(s)`, `f:GetWindowScale()`, `f:FitToScreen()` and `opts.onScaleChanged(f, s)` for saving what the player chose. `opts.minScale`/`maxScale` default to 0.5 and 1.25. |
| `UI:TabStrip(parent, opts)` | A row of tab buttons; the live one goes gold. `strip:Select(name or index)` calls `onSelect`. |
| `UI:Button(parent, text, w, h, opts)` | A palette button. A disabled one still shows its tooltip, so a greyed control can say why. `opts.kind` is `"normal"`, `"accent"` or `"danger"`; `opts.template` adds a frame template such as `SecureActionButtonTemplate`. `SetText`, `Enable`, `Disable` and `SetEnabled` work as on a Blizzard button, and `b:SetActive(on)` shows a toggle's state. |
| `UI:EditBox(parent, w, h, opts)` | A single-line text box in the palette. |
| `UI:TextBox(parent, w, h, opts)` | A multi-line text area that scrolls: `box:SetText(s)`, `box:GetText()`, `box:SelectAllAndFocus()` for a Copy button, `opts.readOnly` and `opts.maxBytes`. |
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
master image is `Docs/assets/impulse-control.png`. An addon that depends on ICLibs takes the
mark from there and never copies it. AuctionatorSellingTweaks is the one exception: it does
not depend on ICLibs, so carrying its own copy is the only way it can reach the texture.

## Used by

All four attach through LibICCore, so the plumbing below is one implementation. On top
of it:

- MalexisAuctionWatcher: scans every profession window into a per-character book and adds
  recipes from it (Recipes tab, Presets, "From your recipe book..."), and builds its
  window, its six tabs, every list and its dialogs on LibICUI. It is also the first user of
  `opts.scalable`: its window is 1024x700, which covers most of a smaller monitor.
- TradeMaster: the book scanner behind every tab, and LibICUI for the window, the tabs,
  every list and every button.
- ICTemplate: all of LibICUI — its window is a live gallery of every widget
  here shown beside the source that built it, so it is also the smoke test after a change
  to this library.
- GuildRecruitment: the window, the tabs, the tables and the multi-line `TextBox` the
  message is composed in; and it is where the load check was born.
