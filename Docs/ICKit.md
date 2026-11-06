# ICKit

The shared kit under the Impulse Control addons for WoW Forever (interface 16001). It is a
library addon: the Forever addons list it under `## Dependencies` and fetch what they need
with LibStub. On its own it adds one command and nothing on screen.

It is built bottom-up, one layer at a time. [forever/VISION.md](forever/VISION.md) has the
rules and the order. It is a different code base from [ICLibs](ICLibs.md), which serves the
TBC Anniversary addons, and the two are never installed on the same client.

## Install

Extract into `_forever_\Interface\AddOns` so you get `AddOns\ICKit\ICKit.toc`. Restart
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

`/ickit gallery` opens a small panel with one of every widget in the current theme, on three
tabs: Basics (buttons, a tick box, an edit box, a menu, a confirm, a slider, a choice and the
eight raid icons), List (two hundred sample rows; click a header to sort, a row to select it,
hover for its tooltip) and Text (a text area holding a little JSON, with a button that reads it
back). A fourth tab is disabled, to show how one looks. Drag it by its title bar and resize it
by its bottom-right corner; its place, size and tab are remembered per character.

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
| LibICJSON-1.0 | 1 | JSON text to and from tables, sorted and indented for people to read. Calls nothing in the game client |
| LibICEnv-1.0 | 2 | What this client offers (build, a feature probe, secret values) and what handlers cost (call and time counters, memory) |
| LibICRestrict-1.0 | 1 | What the client will not let an addon do or read right now: secret values, and combat, encounter and chat restrictions with a reason |
| LibICGroup-1.0 | 2 | Who is in the group: a roster snapshot of plain values, every field checked for secrets, and whether the player may mark |
| LibICChat-1.0 | 1 | Lines said in chat: decided before they go (send, hold until chat unlocks, or refuse with a reason), with a per-channel budget |
| LibICComm-1.0 | 1 | Addon messages between players on the same addon: tables in, tables out, framed to fit, own echo dropped, a version hello, and a queue through lockdowns |
| LibICStore-1.0 | 1 | Saved variables: defaults, schema, migrations, and whether the file really loaded |
| LibICConsole-1.0 | 1 | Prefixed printing and the slash-command dispatcher with its help |
| LibICTheme-1.0 | 2 | The theme registry: colour and font roles, the selected theme, change listeners |
| LibICWidgets-1.0 | 4 | Themed frames drawn from colour textures: panel, label, button, check box, edit box, slider, choice, scroll, tabs, list, resize grip, text area, raid icon, tooltip, menu, confirm |
| LibICSecure-1.0 | 1 | Secure buttons the player presses, for what addon Lua may not do (raid marks): macro and clear-all buttons, override key bindings, every change held until combat ends; the pure macro fitter |

The libraries never print. An addon decides what to say, in its own voice. Only
LibICWidgets and LibICSecure create frames, apart from the one event frame each of the
store and the restriction listener keeps.

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

## LibICJSON-1.0

```lua
local JSON = LibStub("LibICJSON-1.0")

local text, why = JSON.Encode(rules)          -- indented, keys sorted
local line = JSON.Encode(rules, { compact = true })
local back, why = JSON.Decode(pasted)
```

For anything a player copies out of the game and back in: a shared rule set, a capture
export, a backup. Two encodes of one table are byte for byte the same, so two exports can
be compared line by line.

| Call | Returns |
| --- | --- |
| `JSON.Encode(value, opts)` | The JSON text, or `nil, reason` when something in it has no JSON form: a function, infinity or NaN, a key that is neither text nor a number, a table that contains itself. `opts.compact = true` writes one line; `opts.indent` is one level of indent (two spaces by default). Never raises. |
| `JSON.Decode(text)` | The value, or `nil, reason` saying what was wrong and at which character. Never raises, so pasted text that is not JSON gets a message rather than a Lua error. |

How tables map: keys exactly `1..n` make a list; every other table, the empty one
included, is an object. A number key is written as text and comes back as text. Whole
numbers have no fraction (`22890`, not `22890.0`). `null` reads as nil, so a null in a
list leaves a hole at its index. `\u` escapes come back as UTF-8, surrogate pairs
included; a raw tab inside a string, which a text editor can leave, is kept.

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
| `Env.Try(label, fn, ...)` | Calls `fn` under `pcall`: `{ label, ok, n, values, text, secret }`, or `{ label, ok = false, err }`. For asking the client something it may not support. `values` are the returns untouched; `text` joins them for a report line with a secret one written as `<secret>` and its index set in `secret`. A return that will not become text at all leaves `text` as `<unreadable>` and `unreadable = true`; the call still counts as answered. |
| `Env.IsSecret(v)` | Whether `v` is a secret value: one the client hands back but will not let an addon read, compare or join into text. False on a client without them, and false rather than an error when the check fails. |
| `Env.SetSecretCheck(fn)` | Replaces the client's `issecretvalue`; nil goes back to it. A case hands in its own. |
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

## LibICRestrict-1.0

```lua
local Restrict = LibStub("LibICRestrict-1.0")

local hp = Restrict.Readable(UnitHealth(unit))      -- nil when the client hides it
local s = Restrict.State(reading)
if s.secure then return "not while " .. s.reason end
```

On Forever the client hides some values from addons (secret values: comparing or doing
arithmetic on one throws) and switches some actions off while a restriction is active.
This library is where an addon asks. `State` and `Changed` are the pure half: they take
what the client said and decide. `Read`, `Now` and `OnChange` ask the client, using only
what the in-game probe confirmed; every call is guarded, so a client without one reads as
that restriction off.

| Call | Returns |
| --- | --- |
| `Restrict.IsSecret(v)` | Whether `v` is a secret value (`Env.IsSecret`). |
| `Restrict.Readable(v, fallback)` | `v` when it can be read, else `fallback` (nil by default). `false` is a readable value. |
| `Restrict.State(reading)` | The decision, below. |
| `Restrict.Changed(a, b)` | Whether two States differ in a flag or in which restrictions are on. A first reading (`a` nil) always differs. |
| `Restrict.Read()` | The reading below, from the client now: each kind from `C_RestrictedActions.GetAddOnRestrictionState` (or `IsAddOnRestrictionActive` as 2 or 0), `InCombatLockdown()`, `C_ChatInfo.InChatMessagingLockdown()`, and whether the regen window is open. |
| `Restrict.Now()` | `State(Read())`. |
| `Restrict.InCombat()`, `ChatLocked()`, `Active(kind)` | Booleans from `Now()`: `combat`, `chat`, and whether that kind is on. |
| `Restrict.OnChange(fn)` | `fn(state, previous)` every time the State changes in a flag or in which restrictions are on. Not called for the State at the time of the call; read `Now()` for that. Returns a function that stops the listening. |

The first `OnChange` makes the library's one event frame, listening for
`ADDON_RESTRICTION_STATE_CHANGED` and `PLAYER_REGEN_DISABLED` / `ENABLED`; its handler is
wrapped, so `/ickit profile` shows it as "ICKit restrictions". The regen window only opens
while that frame is listening, so an addon that cares about the first seconds of combat
subscribes at load.

`reading` is what the client said, every field optional: `states` maps each
`Enum.AddOnRestrictionType` name (`Combat`, `Chat`, `Encounter`, `Map`, `ChallengeMode`,
`PvPMatch`) to the number the client gave, where 0 is off and anything else on (the change
event reports a start as 1, the state then reads 2); `lockdown` is `InCombatLockdown()`;
`regenDisabled` is true between `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`;
`chatLockdown` is `C_ChatInfo.InChatMessagingLockdown()`.

The State:

| Field | Meaning |
| --- | --- |
| `combat` | In combat by any sign: lockdown, the regen event, or the Combat restriction. The regen event comes a few seconds before the other two. |
| `encounter` | The Encounter restriction is on. |
| `chat` | Chat may not be sent: chat lockdown or the Chat restriction. |
| `secure` | Secure frames may not be changed: lockdown, or the regen event that comes before it. |
| `restricted` | Any of these, or any other restriction on. |
| `active`, `unknown` | `{ [kind] = true }` for each restriction on, and for each state that was secret or not a number. An unknown state is never taken as on. |
| `reason` | Words for the first thing on, combat before encounter before chat, then any other kinds by name; nil when nothing is. |

## LibICGroup-1.0

```lua
local Group = LibStub("LibICGroup-1.0")

local roster = Group.Now()          -- out of combat
for _, m in ipairs(roster.members) do
    if m.role == "TANK" or m.mainTank then ... end
end
if roster.canMark == false then return "you need lead or assist" end
```

On Forever some unit values can come back secret, so a roster is read out of combat, every
field is checked, and the snapshot is kept: a pull reads the snapshot, not the client.

| Call | Returns |
| --- | --- |
| `Group.Snapshot(reading)` | The roster, below. Pure: a case hands in its own reading. |
| `Group.Read()` | The reading, from the client now: `IsInRaid`, `IsInGroup`, `GetNumGroupMembers`, `IsEveryoneAssistant`, `UnitGUID("player")`, and for each unit (`player` and `party1..4`, or `raid1..40`) `UnitGUID`, `UnitName`'s two returns, `UnitClass`, `UnitGroupRolesAssigned`, `GetPartyAssignment("MAINTANK")`, `UnitIsGroupLeader`, `UnitIsGroupAssistant`, `UnitIsConnected` and `UnitIsDeadOrGhost`. Every call is guarded; one that is missing or raises is no answer. |
| `Group.Now()` | `Snapshot(Read())`. |

The roster: `kind` (`solo`, `party` or `raid`), `kindKnown`, `size`, `members` in unit order, `byGuid`,
`me` (the player, found by guid), `leader`, `everyoneAssist`, `canMark` and `unknown` (how
many fields came back unreadable).

A member: `unit`, `guid`, `name` and `name2` (Forever names have two parts), `display` (both,
for showing), `class` (the token, `MAGE`) and `classLocal` (as the client shows it), `role`
(`TANK`, `HEALER`, `DAMAGER` or nil), `mainTank`, `rank` (`leader`, `assist` or `member`),
`online`, `dead`, `isMe`, and `unknown`, the fields that came back secret or unreadable.

Nothing is guessed. A field the client hid is nil and named in `unknown`, so read a nil as
"not known", not as "no". A rank that cannot be read is nil, and then `canMark` is nil in a
raid. `IsInRaid`, `UnitIsGroupAssistant` and `IsEveryoneAssistant` are not yet proven to
answer plainly, so: when `IsInRaid` cannot be read and nothing proves a raid (raid unit
tokens, or more members than a party holds), `kind` says `party` with `kindKnown = false`
and `canMark` is nil unless the player leads or assists; and in a raid, or a group that may
be one, a missing assist answer leaves the rank unknown rather than "member". `canMark` is the game's rule for raid target icons: always alone or in a party, in a
raid only as leader or assist or when everyone is assist. Raid units are read the same way
as party ones, but the probe has only seen a party so far.

There is no change event yet: call `Group.Now()` when you need a roster, out of combat.

## LibICChat-1.0

```lua
local Chat = LibStub("LibICChat-1.0")
local chat = Chat.New({ ttl = 10, onDrop = function(entry, reason) out.Debug("dropped: %s", reason) end })

-- A death call: wait for chat to unlock, up to ten seconds.
chat:Say({ text = "Healer down", channels = { "RAID_WARNING", "RAID" }, whenLocked = "queue" })

-- A pre-pull line: after the pull it is wrong, so never hold it.
local plan = chat:Say({ text = "Pull in 10", channel = "RAID" })
if plan.action == "refuse" then button:SetLabel(plan.reason) end
```

On Forever chat can be locked, and RAID, RAID_WARNING and INSTANCE_CHAT each have their own
rules, so every line is decided before it goes. The answer is a plan: `action` is `send`,
`queue` (held until it can go or its time runs out) or `refuse`, with the `channel` it uses
or would use, the cleaned `text`, and a `reason` in words.

A line: `text` (line breaks become spaces, cut to 255 bytes), `channels` (a list; the first
the group allows wins) or `channel`, `whenLocked = "queue"` to hold it rather than refuse,
`ttl` (seconds a held line lives; the sender's by default), and `pressed = true` when a key
press or click sent it.

| Call | What it does |
| --- | --- |
| `Chat.New(opts)` | A sender with its own queue and record of what it sent. `opts`: `ttl` (10), `maxQueue` (20), `budget` (`{ [channel] = { lines, seconds } }`, `"*"` for the rest), `instance` (`"follow"` trusts the client's chat lock; `"locked"` treats every instance as locked), `onSend(plan)`, `onDrop(entry, reason)`. |
| `sender:Say(line)` | Decides and acts: sends, holds, or refuses. Returns the plan. |
| `sender:Flush()` | Sends what may go now and drops what expired. It runs by itself when the restriction state changes, and once a second while a line is held, in case chat unlocks without the restriction event. |
| `sender:Queue()` | Held lines, oldest first: `{ line, expires, plan }`. |
| `sender.stop()` | Stops it listening for restriction changes. |
| `Chat.Decide(line, state)` | The plan, pure. `state`: `now`, `chat` (locked), `inInstance`, `instance`, `group` (`solo`, `party`, `raid`, or `group` for one that may be a raid, where RAID and RAID_WARNING are refused and PARTY still goes), `lead` (leader or assist in a raid; nil when unreadable), `instanceGroup`, `sent`, `budget`. |
| `Chat.Flush(queue, state)` | `{ send, dropped, keep }`, pure: each held line decided again in order, counting this round's sends against the budget. A dropped entry says why (`expired`, or the refusal). |
| `Chat.Budget(channel, state)` | 0 when a line may go now, else the seconds until one may. |

What each channel needs: PARTY a party or raid; RAID a raid; RAID_WARNING a raid and lead
or assist; INSTANCE_CHAT an instance group; SAY and YELL a key press (from a timer in combat
the probe saw SAY sent but never arrive). Over budget a line is held (when it may be) or
refused; the default is 2 raid warnings and 4 lines on any other channel per 10 seconds.

The sender reads the chat lock from LibICRestrict, the group from LibICGroup, the instance
type from `GetInstanceInfo`, and sends with `SendChatMessage`. Whether an instance locks
chat during trash, a boss or not at all is not known yet; `instance = "locked"` is the
setting for a client found to lock without saying so.

## LibICComm-1.0

```lua
local Comm = LibStub("LibICComm-1.0")
local comm = Comm.New("MarkedForDeath", { version = VERSION, onDrop = function(entry, reason) end })

comm:On("plan", function(msg, from, channel) ApplyPlan(msg.plan) end)
comm:Send({ t = "plan", plan = plan })      -- to the whole group
comm:Hello()                                -- peers answer with their versions
```

A message is a table with a type in `t`. It goes out as compact JSON (LibICJSON), cut into
frames that fit one addon message, and arrives whole on every other client in the group.
`Send` adds `f`, the player's guid; the copy the client loops back to you carries your own
guid and is dropped, so a handler only ever sees other players.

| Call | What it does |
| --- | --- |
| `Comm.New(prefix, opts)` | A sender for one prefix (1 to 16 characters): registers it and listens for `CHAT_MSG_ADDON` at once. `opts`: `version` (said in a hello), `ttl` (30 seconds a waiting message lives), `maxQueue` (50), `budget` (`{ frames, seconds }`, 8 per 10 by default), `raid` (`"follow"`, the default, or `"off"` to send nothing in a raid), `onDrop(entry, reason)`. |
| `comm:Send(msg, channel)` | Sends to the group (or `channel`). Returns `{ action = "send" \| "queue" \| "refuse", channel, reason }`. |
| `comm:On(t, fn)` | `fn(msg, from, channel)` for each message of type `t` from another player. `from` is the sender as the client names them ("First Second" on Forever). |
| `comm:Hello()` | Says this version. Every peer that hears it records it and answers once (not again within a minute), so both sides learn each other. |
| `comm:Peers()` | `{ [guid] = { name, version, at } }` from hellos heard. |
| `comm:Queue()` | Messages waiting, oldest first. |
| `comm.stop()` | Stops it trying the queue on restriction changes. |
| `Comm.Frame(text, n)` | The frames for message id `n`, pure: `S` and a two-character id for one frame, else `F`, `M`... `L`. |
| `Comm.Assemble(buffers, from, frame, now)` | The whole text when this frame completes one, else nil, pure. Senders and ids never mix; a frame with no first is dropped, and a partial older than 30 seconds is forgotten. |
| `Comm.Channel(state)` | The group's channel, or `nil, reason`, pure: INSTANCE_CHAT in an instance group, RAID in a raid (unless `raid = "off"`), PARTY in a party; a group that may be a raid is refused. |
| `Comm.Result(name)` | What a `SendAddonMessage` result means, pure: `sent`, `retry` (throttled), `hold` (`AddOnMessageLockdown`) or `drop`, with a reason. |
| `Comm.Newer(a, b)` | Whether version `a` is newer than `b`, part by part as numbers. |

A frame the client will not take now waits: `retry` and `hold` keep it queued, tried again
on every restriction change and once a second, until it goes or its time runs out, when
`onDrop` hears the last reason. A `drop` result reports it at once. Results are read by
name from the client's `Enum.SendAddonMessageResult`.

From the probe, open world: PARTY returns 0 and loops back, in combat too; INSTANCE_CHAT
outside an instance group returns 5 (`NotInGroup`). Whether a raid carries addon messages
out of combat is not known yet, which is what `raid = "off"` is for.

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
`check`, and the status text roles `good`, `warn` and `bad` (green, amber, red, each readable
as text on the theme's ground; `danger` is a button fill and is not). Each is `{ r, g, b, a }`. Font roles: `body`, `title`, `small`, `button`.

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
| `W.Tabs(parent, tabs, opts)` | A row of tabs with one selected. `tabs`: `{ { key, label, page }, ... }`; a tab's `page` (optional) is shown when it is selected and hidden otherwise, so a window switches pages with no code of its own. `opts`: `width` (tabs shrink alike to fit), `tabWidth` (96), `height` (22), `selected`, `onSelect(key, strip)` (a click, not `Select`). `strip:Select(key)`, `strip:GetSelected()`, `strip:SetLabel(key, text)`, `strip:SetDisabled(key, reason)` (greys the tab; the reason shows on hover; nil enables it), `strip.buttons[key]`. `W.TabLayout(count, width, tabW)` is the pure half. |
| `W.List(parent, w, h, opts)` | A list: a column header row in its own frame above a scroll of fixed-height, single-line rows. Only the rows in view exist, pooled and filled again in full as it scrolls, so thousands of items cost a screenful. `opts.columns`: `{ { key, label, width, justify, tip, text = fn(item) }, ... }`; a column with no width fills the rest, `tip` is the header's hover text, `text(item)` returns the cell's text and colour role (else `opts.cell(item, column)`, else `item[key]`). `opts`: `rowHeight` (18), `headerHeight` (20), `onClick(item, mouseButton, row)` (left or right), `tooltip(GameTooltip, item)` for the full values a cut cell hides, `selected(item)`, `onHeader(key, column)` (to sort), `empty` (shown with no items). `list:SetItems(items)`, `list:Refresh()`, `list:Resize(w, h)`, `list:ScrollTo(offset)`, `list:GetItems()`, `list:SetSortMark(key, ascending)` (an arrow after the sorted column's header). A row's tooltip follows the item when the wheel refills the row under the pointer. `W.ColumnLayout(columns, width)` and `W.VisibleRange(offset, rowH, viewH, count)` are the pure halves. |
| `W.Resize(frame, opts)` | A grip in the frame's bottom-right corner that resizes it. Place the frame by its top-left (`W.SetPlace` does), so it grows right and down. `opts`: `minWidth` (200), `minHeight` (120), `maxWidth` and `maxHeight` (the screen by default), `onResize(w, h, frame)` while dragging, `onResized(w, h, frame)` on release (save the size there). While held, and only then, it follows the pointer in an OnUpdate. `W.ResizeSize(startW, startH, dx, dy, minW, minH, maxW, maxH)` is the pure half. |
| `W.TextArea(parent, w, h, opts)` | Many lines: somewhere to paste a shared rule set, or a copy box to take an export from. A multi-line edit box in a themed scroll; the line being typed on stays in view, and a press anywhere in the area puts the cursor in it. `opts`: `text`, `maxBytes`, `readOnly = true` (a copy box: typing is undone and focus selects everything, ready for Ctrl+C), `onChange(text, area)` (the player's changes, not `SetText`). `area:SetText(text)` (back to the top), `area:GetText()`, `area:SelectAll()`, `area:Resize(w, h)`, `area.edit`, `area.scroll`. Escape drops focus; drop it yourself when combat starts. |
| `W.RaidIcon(parent, index, size)` | One raid target icon (1 star to 8 skull) as a texture on `parent`, `size` square (16). It draws from a plain number only: anything else, a secret index included, hides it. The client's `SetRaidTargetIconTexture` is not used, because it throws when handed a secret. `icon:SetIndex(index)` returns whether it shows; `icon:GetIndex()` is the index or false. `W.RaidIconCoords(index)` is the pure half: the texcoords, or nil. |
| `W.Tooltip(frame, builder, anchor)` | `builder(GameTooltip, frame)` adds the lines; nil removes it. It hooks, so a button keeps its hover highlight. The tooltip sits at the pointer (`ANCHOR_CURSOR_RIGHT`) unless `anchor` says otherwise. |
| `W.Slider(parent, opts)` | A number between two ends with its value written beside it. `opts`: `width`, `valueWidth`, `min`, `max`, `step`, `value`, `format(value)`, `live` (false waits for the thumb to be let go), `onChange(value, slider)`, `onType(text, slider)` (the value becomes a box to type into when clicked; Enter sends the text), `onHold(held)` (the thumb was picked up or let go), `trough` (false drops the rim drawn behind the track). `s:SetValue(v)` moves it without calling `onChange`; `s:GetValue()`. The bar is the client's `MinimalSliderWithSteppersTemplate`, so its art is not themed; the rim behind it is. `W.SliderValue(raw, min, max, step)` is the pure half: whole steps, with both ends reachable. |
| `W.Choice(parent, w, h, opts)` | One of a short list: a button showing the current choice, with a chevron, that opens a menu of them all. `opts`: `choices` as `{ { value, label }, ... }`, `value`, `onChange(value, choice)`, `disabled(value)` returning a reason to grey a choice out. `c:SetValue(v)`, `c:GetValue()`. |
| `W.Scroll(parent, w, h, opts)` | A window onto content taller than itself: parent rows to `s.content`, call `s:SetContentHeight(h)` when they change. The mouse wheel and a thin bar scroll it; the bar hides when everything fits. `opts.step` is one wheel notch; `opts.onScroll(offset, s)` hears every move. `s:SetViewHeight(h)` and `s:SetViewWidth(w)` when the window itself changes size. `s:ScrollTo(offset)`, `s:GetOffset()`. `W.ScrollClamp(offset, contentH, viewH)` is the pure half. |
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

`Gallery.lua` in the kit is the worked example: a movable, resizable panel with a title bar
that drags it, tabs that switch pages, a list with its header above the scroll, a text area,
its place and size saved per character, a menu and a confirm.

## LibICSecure-1.0

```lua
local Secure = LibStub("LibICSecure-1.0")

local text, kept, dropped = Secure.Fit(pairs, Secure.MACRO_LIMIT, "/targetlasttarget")
local pack = Secure.MacroButton("MFDMarkPack", { text = text, template = "UIPanelButtonTemplate" })
Secure.Bind(bar, { ["CTRL-1"] = "MFDMarkPack" })
-- later, a plan edit, in combat or out:
if Secure.SetMacro(pack, newText) == "held" then ShowStale() end
```

Some things on Forever only the player's own press may do. `SetRaidTarget` from addon Lua
is forbidden, but a secure button running a `/tm` macro, pressed through a key binding,
marks in combat ([client-reference.md](client-reference.md), "Secure buttons"). This
library makes those buttons in the one shape the probe proved, keeps their macros, binds
keys to them, and never changes one while the client forbids it: a change asked for in
combat is held and made when combat ends (`Restrict.State().secure` going false).

| Call | Returns |
| --- | --- |
| `Secure.Fit(entries, limit, tail)` | `text, kept, dropped`. `entries` is a list of strings or of line lists kept whole (a `/targetexact` and its `/tm`), most important first; `limit` is bytes (`Secure.MACRO_LIMIT`, 255, when nil); `tail` always ends the text and its room is kept first. Entries are kept in order and the first that does not fit ends the text, so a lower seat never takes a higher one's place; `dropped` lists the indexes left out. Pure. |
| `Secure.Words()` | `{ mark, exact, click, clearWorld }`: the client's slash words from `SLASH_TARGET_MARKER1`, `SLASH_TARGET_EXACT1`, `SLASH_CLICK1` and `SLASH_CLEAR_WORLD_MARKER1`, English (`/tm`, `/targetexact`, `/click`, `/cwm`) when one is missing. |
| `Secure.ClickBinding(name, mouseButton)` | `"CLICK <name>:LeftButton"`, the binding command for a `Bindings.xml` entry. Pure. |
| `Secure.ReadMark(value)` | What a `GetRaidTargetIndex` answer says: `"icon", n` for a plain 1 to 8, `"marked"` for a secret (a marked unit in combat: there is a mark, not which), `"none"` otherwise. Pure. |
| `Secure.MacroButton(name, opts)` | A named `SecureActionButtonTemplate` button of type `macro`, fired on the key's down edge (`RegisterForClicks("AnyDown")` and `useOnKeyDown`), or `nil` and why in combat. `opts`: `parent` (UIParent), `template` (a look added to the secure template, such as `UIPanelButtonTemplate`), `hidden` (pressed by key or `/click` only: shown but invisible, off screen and deaf to the mouse), `text` (the first macro), `onApplied(button, text)` each time its macro is written, a held one included. |
| `Secure.ClearAllButton(name, opts)` | The client's own clear-every-mark action (`type` `raidtarget`, `action` `clear-all`), no macro. Same options, without `text`. |
| `Secure.SetMacro(button, text)` | `"set"`, or `"held"` in combat: written when combat ends, and a later write replaces a held one. The button keeps its last macro meanwhile. |
| `Secure.Bind(owner, keys)` | `"set"` or `"held"`. `keys` is the whole override set for the frame `owner`: `{ [key] = buttonName or { buttonName, mouseButton } }`; `{}` clears it. Override bindings (`SetOverrideBindingClick`, priority) never touch the player's saved keys and last until changed or the UI reloads. |
| `Secure.Pending(button or owner)` | Whether a held change waits for it. |
| `Secure.Macro(button)` | The macro the button runs now, not a held one. |
| `Secure.Locked()` | `true, reason` while secure frames may not be changed. |

What it is built around:

- The button shape is the probe's: named (bindings and `/click` find a button by its
  global name), `AnyDown` with `useOnKeyDown` pinned (left unset, the edge follows the
  player's key-down setting), bound with `SetOverrideBindingClick`.
- Creating a button, setting an attribute and binding a key happen out of combat only.
  The probe saw attributes set in combat raise `ADDON_ACTION_BLOCKED`.
- Nothing reads marks back. In combat `GetRaidTargetIndex` on a marked mob is secret, so a
  caller tracks what it pressed; `ReadMark` says how much an answer tells.
- A mouse click puts the pointer on the button, so `[@mouseover]` there means the button.
  A button meant for `[@mouseover]` is bound to a key and made `hidden`.
- Keep the macro text to what the probe ran: `/tm` with a target, `/targetexact` then
  `/tm`. Which of the probe's ten buttons marked (clear-all, a 300-byte macro,
  conditionals, a `/click` chain) was not separated, so those stay unproven until a
  slower read-back says.

## Running the cases

```
.\scripts\run-tests.ps1 -Flavor forever -Addon ICKit
```

The harness loads an addon's `## Dependencies` first, each from its own `.toc`, then the
addon, then runs `ns.Tests.Run()`. In game the same cases run with `/ickit test`.
