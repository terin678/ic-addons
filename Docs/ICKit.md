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
/ickit theme [name]     the look of every addon on the kit; no name lists them, "default" goes back
/ickit gallery          one of every widget, to look at
/ickit probe            check what this client offers and save the answers
/ickit profile [reset]  what the kit's handlers have cost: calls, time, memory
/ickit test             run the built-in checks
/ickit debug on|off     maintainer lines in chat
/ickit help
```

### Themes

Every addon built on the kit is drawn in one theme, chosen for the whole account:
**Forever** (the default: the game's own look, warm near-black panels, bronze edges and its
gold), **Impulse Control** (the guild's navy, gold and bone, for members who want it) and
**Paper** (dark ink on a yellow sticky note). `/ickit theme paper` switches, and everything
on screen repaints at once. The start of a name is enough, and `/ickit theme default` goes
back. Only a theme you picked is saved, so an account that never chose follows the default.

`/ickit gallery` opens a small panel with one of every widget in the current theme. Drag it
by its title bar; where you leave it is remembered per character.

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
| LibICTheme-1.0 | 1 | The theme registry: colour and font roles, the selected theme, change listeners |
| LibICWidgets-1.0 | 2 | Themed frames drawn from colour textures: panel, label, button, check box, edit box, slider, choice, scroll, tooltip, menu, confirm |

The libraries never print. An addon decides what to say, in its own voice. Only
LibICWidgets creates frames, apart from the store's one event frame.

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

## LibICTheme-1.0

```lua
local Theme = LibStub("LibICTheme-1.0")
```

A theme is a table of named roles. A widget asks for `ground` or `accent` and draws
whatever the selected theme says that is, so an addon never holds a colour of its own.

| Call | What it does |
| --- | --- |
| `Theme.Register(name, def)` | Adds a theme. Any role `def` leaves out is filled from the default, so a role added later never leaves an older theme without it. `def.logo` names a mark's texture; a theme without one has none. |
| `Theme.Get(name)` | The theme, or nil. |
| `Theme.Current()` | `theme, name`: the selected one, or the default. |
| `Theme.Select(name)` | Selects it and returns whether the name is a theme. Listeners run only when it changed. |
| `Theme.Find(text)` | A theme name from what a player typed: any case, or the start of exactly one name. |
| `Theme.Names()` | The names, sorted. |
| `Theme.OnChange(fn)` | `fn(theme, name)` on every change. Returns a function that stops the listening. |
| `Theme.Hex(color)` | A `\|cffrrggbb` code. |

`theme = { name, label, logo, colors, fonts }`. Colour roles: `ground` (a panel), `raised`
(a title bar), `field` (somewhere to type or tick), `edge`, `text`, `textDim`,
`textDisabled`, `done` (a finished line), `accent`, `accentHover`, `accentText`, `danger`,
`dangerHover`, `dangerText`, `button`, `buttonHover`, `buttonText`, `hover`, `selected`,
`check`. Each is `{ r, g, b, a }`. Font roles: `body`, `title`, `small`, `button`.

The kit itself saves a choice the player made (`ICKitDB.settings.theme`, absent until they
pick) and applies it at load; an addon does not select a theme, it only draws in the
current one. `Theme.DEFAULT` is "Forever".

## LibICWidgets-1.0

```lua
local W = LibStub("LibICWidgets-1.0")
```

Only what an addon has needed so far. Every widget is drawn from colour textures, uses no
Blizzard frame template, repaints when the theme changes, and runs no `OnUpdate`.

| Call | What you get |
| --- | --- |
| `W.Panel(parent, opts)` | A filled, edged frame. `opts`: `width`, `height`, `strata`, `role` (`ground`, `raised`, `field`), `edge = false`, `movable = true` with `onMoved(panel)`. `panel:SetLocked(true)` pins it. |
| `W.DragHandle(handle, panel, opts)` | Makes a child, a title bar usually, drag its panel. It owns the handle's mouse scripts, so ask for a right-click here: `opts.onRightClick(handle)`. |
| `W.Label(parent, text, opts)` | A font string. `opts`: `font` role, `color` role, `justify`, `wrap`. `label:SetRole(color)` recolours it. |
| `W.Button(parent, text, w, h, opts)` | `opts.kind` is `normal`, `accent`, `danger` or `flat` (no fill until hovered); `opts.onClick`; `opts.justify = "LEFT"` with `opts.font` and `opts.textRole` for a row of a list; `opts.onDragStart(button)` and `opts.onDragStop(button)` for a row that is picked up and put down, while a plain press stays a click. `b:SetLabel(text)`, `b:SetKind(kind)`, `b:SetTextRole(role)`. |
| `W.CheckBox(parent, opts)` | `opts`: `size`, `checked`, `onClick(checked, box)`. `box:SetChecked(on)`, `box:GetChecked()`. A click calls `onClick`; `SetChecked` does not. |
| `W.EditBox(parent, w, h, opts)` | One line. `opts`: `maxBytes`, `placeholder`, `onEnter(text, box)`, `onEscape(box)`, `onFocusLost(box)`, `onTab(box, backwards)` for Tab and Shift-Tab. Escape always drops focus. |
| `W.Tooltip(frame, builder, anchor)` | `builder(GameTooltip, frame)` adds the lines; nil removes it. It hooks, so a button keeps its hover highlight. The tooltip sits at the pointer (`ANCHOR_CURSOR_RIGHT`) unless `anchor` says otherwise. |
| `W.Slider(parent, opts)` | A number between two ends with its value written beside it. `opts`: `width`, `valueWidth`, `min`, `max`, `step`, `value`, `format(value)`, `live` (false waits for the thumb to be let go), `onChange(value, slider)`. `s:SetValue(v)` moves it without calling `onChange`; `s:GetValue()`. The bar is the client's `MinimalSliderWithSteppersTemplate`, so its art is not themed. `W.SliderValue(raw, min, max, step)` is the pure half: whole steps, with both ends reachable. |
| `W.Choice(parent, w, h, opts)` | One of a short list: a button showing the current choice that opens a menu of them all. `opts`: `choices` as `{ { value, label }, ... }`, `value`, `onChange(value, choice)`, `disabled(value)` returning a reason to grey a choice out. `c:SetValue(v)`, `c:GetValue()`. |
| `W.Scroll(parent, w, h, opts)` | A window onto content taller than itself: parent rows to `s.content`, call `s:SetContentHeight(h)` when they change. The mouse wheel and a thin bar scroll it; the bar hides when everything fits. `opts.step` is one wheel notch. `s:ScrollTo(offset)`, `s:GetOffset()`. `W.ScrollClamp(offset, contentH, viewH)` is the pure half. |
| `W.Menu(owner, items)` | A context menu. Items: `{ title }`, `{ text, onClick }`, `{ text, checked = fn, onClick }`, `{ text, radio = fn, onClick }` (one of several; picking closes the menu), `{ divider = true }`. An item may carry `disabled = true` or `disabled = "the reason"`. |
| `W.Confirm(text, onAccept)` | A yes/no dialog. |
| `W.Compartment(opts)` | An entry in the client's Addon Compartment, the list of addons beside the minimap: the modern way onto the minimap, costing no frame. `opts`: `text`, `icon`, `onClick(mouseButton)`, `tooltip`. Returns false on a client without one. |
| `W.MinimapButton(opts)` | A round button on the minimap's rim in the client's own art, for one-click access. `opts`: `icon`, `angle` (degrees; 0 east, 90 north), `onClick(button, mouseButton)`, `onMoved(angle)`, `tooltip`. Drag it round the rim; `button:SetAngle(degrees)`. |
| `W.GetPlace(frame)` / `W.SetPlace(frame, fx, fy)` | Where a frame's top-left sits, as fractions of the screen. Save these, not pixels: they survive a change of resolution or interface scale. `SetPlace` holds the whole frame on screen. |
| `W.Repaint()` | Redraws everything in the current theme. |

Offer the compartment entry always and the rim button as an extra a player can hide: the
compartment is the client's own mechanism, the rim button is what many players look for.

A move starts on the press and ends on the release. The client's drag event is not used:
it waits for the pointer to travel the drag threshold, and the frame then jumps the
distance it missed.

An edit box with focus takes every key, movement included. An addon that shows one drops
its focus (`box:ClearFocus()`) when combat starts.

`Gallery.lua` in the kit is the worked example: a movable panel with a title bar that drags
it, its place saved per character, a menu and a confirm.

## Running the cases

```
.\scripts\run-tests.ps1 -Flavor forever -Addon ICKit
```

The harness loads an addon's `## Dependencies` first, each from its own `.toc`, then the
addon, then runs `ns.Tests.Run()`. In game the same cases run with `/ickit test`.
