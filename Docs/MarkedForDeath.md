# Marked For Death

Automatic raid target icons for trash, by kill priority and crowd control job, coordinated
across everyone in the raid who runs it. Walk up to a pack and it is marked before you
reach it.

Flavor: anniversary (TBC). Slash command: `/mfd`. Minimap button: the skull.

## The one idea to understand

**Icons belong to jobs, not to mobs.** Each of the eight icons is bound to a *role*: a
durable job like "sheep number one" or "kill target number three". A rule for a mob only
says what should happen to it ("this gets sheeped"). The addon hands the mob the lowest
free role for that job, and the role supplies the icon.

That is why assignments never change under people. If Grimmtusk is pinned to sheep role
one, Grimmtusk is always Moon. A second mage inherits sheep role two and is always Star.
Nobody renegotiates, and it does not matter which mob the raid happened to look at first.

The default plan:

| Icon | Job |
| --- | --- |
| Skull | Kill 1 |
| Cross | Kill 2 |
| Square | Kill 3 |
| Circle | Kill 4 |
| Moon | Sheep 1 (pinned to Grimmtusk) |
| Star | Sheep 2 |
| Triangle | Banish 1 |
| Diamond | Banish 2 |

Change any of it in `/mfd config`. A job nobody in the group can do is skipped entirely:
with no mage present, sheep rules fall through to their fallback (usually kill) instead of
producing an icon nobody will honour.

## One window

Everything you configure lives in a single window with tabs: **Roles**, **Rules**,
**Raid check**, **Assignments**, **Deaths** and **Settings**. Open it by left clicking the minimap skull, or `/mfd`.
Switching tabs never closes anything, so you can jump between the role plan and the rule
list without losing your place.

Right click the minimap button to land straight on Rules. Middle click toggles the
assignment panel. Shift click gives a small menu with quick toggles for marking and pull
announcements.

Two panels stay separate on purpose. The **assignment panel** and the **buff board** are
things you glance at during a pull, not things you sit and adjust, and burying them in a
config window would mean opening one mid-fight. Both are on the shift-click menu, both
have keybinds, and both remember where you put them.

## Doing things mid-pull

Nothing you need during a fight requires typing. The **action bar** is a separate bar you
park wherever suits your layout:

| Button | What it does |
| --- | --- |
| Announce | Post the current assignments to raid chat now. |
| Clear | Take every icon off, hand-placed ones included. |
| Re-mark | Forget the current icons and work the pack out again. |
| Marking on/off | Stop or start placing icons. Shows which it is. |
| Tank calls | Cycle the tank death override. Shows which it is. |
| Healer calls | Cycle the healer death override. Shows which it is. |

**Drag it anywhere. Drag the corner to reshape it.** The buttons rewrap to whatever width
you give it, so it can be one long row along the bottom, a two-wide block beside your raid
frames, or a vertical strip down the edge. It remembers position and size per character.
Lock it in Settings once it is where you want it, and the grip disappears so a stray click
mid-fight cannot shove it across the screen.

It is on by default. `/mfd bar` hides and shows it, `/mfd bar lock` locks it, and
`/mfd bar reset` puts it back in the middle if it ends up somewhere unreachable.

**Every button is also bindable.** Key Bindings, Marked For Death: put Clear and Re-mark
on spare mouse buttons and you never reach for the bar at all. That is the better answer
while you are tanking. The most useful are on the minimap shift-click menu too.

Buttons, keybinds, menu entries and slash commands all run the same code, so they cannot
drift apart or behave differently from each other.

## Planning a raid before you walk in

You do not have to be standing in an instance, and the addon does not have to know the mob.

Open `/mfd rules`, click the filter button until it reads the instance you are planning
(Black Temple, Hyjal, whichever), and build the list from the bank in Shattrath if you
like. Rules go to the zone the filter names, not to wherever you are standing.

For a whole instance at once, click **Paste list** (or `/mfd bulk`) and paste a kill
order, best target first:

```
-- first pull
Illidari Nightlord = sheep
Shadowmoon Champion
Illidari Fearbringer = banish

-- second pull
Shadowmoon Houndmaster
22890 = trap
```

One mob per line. Add `= sheep`, `= banish`, `= trap` and so on for a job; anything without
one is a kill target. Blank lines and lines starting with `--` or `#` are ignored, so you
can annotate by pack. Line order is priority order: the first line gets Skull. A line the
addon cannot understand fails the whole paste rather than importing half a plan.

Mobs you have never seen are fine. A rule with just a name matches any mob with that name,
so a list typed from a guide works the first time the raid walks past. Once the addon has
seen a mob it will also appear in the search box, where **Add** files it by npc id, which
is more precise. Both kinds live in the same list and sort together.

### What the search box already knows

The addon ships with 295 raid creatures, trash included, so most of the time you can just
type part of a name and click Add:

| Raid | Creatures | Where the list came from |
| --- | --- | --- |
| Black Temple | 77 | spawn data |
| Karazhan | 59 | spawn data |
| Tempest Keep | 35 | id block (see below) |
| Sunwell Plateau | 33 | spawn data |
| Serpentshrine Cavern | 32 | spawn data |
| Zul'Aman | 29 | spawn data |
| Hyjal Summit | 19 | wave roster (see below) |
| Gruul's Lair | 8 | spawn data |
| Magtheridon's Lair | 3 | spawn data |

Names and ids come from Questie's TBC creature database, which is built for the same
client, so every name is the name the game reports.

Two raids needed more than spawn data. **Hyjal** summons its waves by script, so none of
its creatures carry a zone; its roster is taken from DBM's wave module (ghouls,
abominations, necromancers, banshees, crypt fiends, gargoyles, frost wyrms, fel stalkers,
infernals) and resolved to ids by name. **Tempest Keep** has no spawn data at all, and its
Bloodwarder and Sunseeker families are shared with the four five-man wings, so The Eye's
own trash is taken from the contiguous id block those creatures occupy.

Anything that could not be established either way was left out rather than guessed. A gap
costs you a search suggestion and nothing else, because you can always type the name.

## Death announcements

Everything about them is on the **Deaths** tab. The raid gets `Dezedin has died` as a raid
warning, posted by the Raid Lead's client only so it appears once.

**Tank calls and healer calls are configured completely separately.** Their own on/off,
their own trash setting, their own boss list, their own override, their own extra names.
Nothing you do to one touches the other, because wanting healer calls on Naj'entus and
tank calls on Illidan is a normal thing to want.

**Main tanks** are picked up automatically from the raid frame. Right click a portrait,
Set Main Tank, and they count. The Extra tanks box is only for tanks the raid does not
flag, separated by commas:

```
Dezedin, Moophie, Grimmtusk
```

**Healers** are recognised by spec: Holy, Discipline or Restoration. There is no healer
role on this client's raid roster the way there is a main tank flag, so spec is the honest
source, and it is why a shadow priest is never mistaken for one. Specs come from the same
inspection the raid check grid uses, so they fill in once you open the raid check tab or
run a ready check. The line under the Extra healers box says exactly who is currently
counted, worth reading before the pull rather than after somebody dies unannounced.

### Trash and bosses

**Trash is one yes or no per kind.** Nobody wants to tick five hundred mobs, and no raid
leader thinks about trash that way: either deaths there are worth hearing about or they
are not. Tanks ship with trash on, which is what they have always done. Healers ship off.

**Bosses are ticked one at a time**, because they individually are or are not worth a
callout. The list is every TBC raid encounter laid out by raid, with two ticks per row:
the left one calls tanks, the right one calls healers. Set it up before you ever walk in.
The **T** and **H** buttons next to a raid heading do that whole instance for that kind.

Two Karazhan encounters are missing on purpose: the Opera Event and the Chess Event. None
of their mobs appear in the bundled mob database, and shipping a toggle that silently
never fires would be worse than not offering it.

### Changing your mind mid raid

Each kind has its own **Right now** button, on the Deaths tab, on the action bar, and on
the minimap shift-click menu:

| State | What it does |
| --- | --- |
| Per boss | Follows that kind's ticks and its trash setting. The default. |
| On everywhere | Announces every death of that kind, trash included. |
| Off everywhere | Announces none of that kind. |

The other kind is never affected. From a macro:

```
/mfd deaths tank
```

`/mfd deaths healer on`, `off` or `auto` sets a specific state; `/mfd deaths` on its own
reports where both currently stand. `/mfd healers` prints who is counted as one.

The fight you are in comes from the boss's nameplate, which the addon is already watching
for marking, and from the combat log when the nameplate is not there. There is no
encounter API on this client, so one or the other has to do it. Once a boss is identified
it stays the active fight until combat ends, which matters if you lead from range.

None of that runs unless a setting asks for it.

## Sharing a rule set

The **Share** button on the Rules tab gives you a plain JSON file of every rule you have.
Copy it into a text file, post it on a forum, hand it to whoever is learning to lead. They
click **Load file**, paste, and have your whole kill order.

**Load file merges.** It updates rules for mobs the file names and leaves everything else
alone, so importing a Black Temple order does not touch your Hyjal list.

**Roles are deliberately not in the file.** Which icon means which job, and who is pinned
to it, is your raid's business and differs between guilds. Import somebody's kill order,
then set your own on the Roles tab. That is the one thing a new raid leader has to do for
themselves, and it takes a minute.

The **Format** button shows the file's shape with a worked example and what every field
means. It is ordinary JSON, sorted and indented, so it reads and diffs cleanly and can be
edited in any text editor without the addon.

A file that is not a Marked For Death export, or one made by a newer version, is refused
rather than half applied. So is a file with an unrecognised job in it: half a kill order
looks complete and is not.

## When two addons fight over the icons

Only one addon can own a raid icon. If another one is also marking, you will see marks
that will not stay put and a chat line like:

```
backing off 22879:00001AC1C6 for 5s, something keeps changing that icon
```

That is this addon giving up rather than fighting a human or another addon forever. Run
`/mfd conflicts`: it names any addon it can detect doing the same job and the exact click
to stop it. The most common one is Method Raid Tools, whose automarker is under
`/mrt`, Marks, Auto marks.

It is checked once at login too, and it will not touch another addon's settings for you.

## First night

1. Enemy nameplates must be on. The addon can only touch a mob it has a nameplate for.
   It warns you on login if they are off; `/mfd fixcvars` sets them.
2. Bind **Add target as a rule** under Key Bindings, Marked For Death. This is how rules
   get made: point at a mob, press the key, it is added as a kill rule and the editor
   opens so you can change the job. Do this as you clear; it takes seconds per pack.
3. In a raid, have the raid leader or an assistant run `/mfd lead <name>` to designate the
   Raid Lead. That person's client does the marking. Everyone else running the addon
   feeds them sightings and places icons they cannot reach.
4. Hover the minimap skull. It tells you the active rule count, who is marking, and
   warns in red if anything would stop marking from working.

### Reordering rules

Every rule row has a **grip** at its left, three short lines. Grab it and drag the row
anywhere in the list; a gold bar shows the gap it will land in, and a label follows the
cursor so you know what you are carrying. The arrows are still there for nudging something
one place, but you do not need ten clicks to move a rule ten rows.

Rules are filed per zone and switch automatically. They ship empty on purpose: the addon
never guesses your guild's kill order, because a confidently wrong mark is worse than no
mark.

## Commands

Every command is in `/mfd help`.

| Command | What it does |
| --- | --- |
| `/mfd help` | List every command with a one-line description. |
| `/mfd add [job]` | Rule whatever you are targeting or mousing over. `/mfd add sheep`, `/mfd add banish`. Defaults to kill. Run again on the same mob to change its job. |
| `/mfd list` | Rules for this zone, highest priority first. Rules merged from other players show in amber with their name. |
| `/mfd del <npcid>` | Remove one of your own rules. |
| `/mfd intents` | Every job a rule can use. |
| `/mfd rules` | The rule editor: search bundled and learned mobs, reorder, change jobs, delete. |
| `/mfd config` | The role editor: which icon means which job, and who is pinned. |
| `/mfd lead [name]` | Designate the Raid Lead, or clear it. Raid leader or assistant only. |
| `/mfd status` | Who is marking and why, who else is running the addon, and how many rules were merged from whom. |
| `/mfd debug` | If marking is not happening, this says exactly why, most fundamental reason first. |
| `/mfd mark` | Force a full re-mark of the visible pack, dropping any hand-placed holds. Also a button and a keybind. |
| `/mfd clear` | Clear every icon on visible mobs. Also a button and a keybind. |
| `/mfd announce` | Post the current assignments to raid chat now, for calling a pack out before the pull. Also a button and a keybind. |
| `/mfd deaths [tank|healer] [on|off|auto]` | Cycle or set one kind's death override. Bare, it reports both. Also buttons and keybinds. |
| `/mfd healers` | Who the addon currently counts as a healer, and why it might be nobody. |
| `/mfd where` | Current zone, its map id, and how many rules are active here. |
| `/mfd fixcvars` | Turn enemy nameplates on and set their range to 41 yards. |
| `/mfd export` | A string of your own rules to paste to someone. |
| `/mfd import` | Paste a rule string. It merges in; nothing of yours is deleted. |
| `/mfd whycheck` | If the raid check grid is empty or calling nobody out, this says exactly why. |
| `/mfd conflicts` | Check whether another addon is also placing raid icons. |
| `/mfd coverage` | Mobs you have seen that the bundled database does not list. |
| `/mfd readycheck` | Start a real ready check, the native one everybody sees. Raid leader or assistant. |
| `/mfd share` | A shareable JSON file of your rules, for posting or handing to a new raid leader. |
| `/mfd load` | Paste a shared rule file. It merges into yours; nothing of yours is deleted. |
| `/mfd off` | Stop the addon doing anything: no icons, no chat, no warnings. Nothing configured is lost. |
| `/mfd on` | Resume after `/mfd off`. |
| `/mfd minimap` | Hide or show the minimap button. |
| `/mfd log [count\|kind\|clear]` | What the addon has been doing. Also written to SavedVariables for reading after the fact. |
| `/mfd bar [lock|reset]` | Hide or show the action bar, lock it in place, or move it back to the middle. |
| `/mfd sound` | Toggle the sound played when a rule cannot work on its target. |
| `/mfd bulk` | Paste a whole kill order for a zone, one mob per line. |
| `/mfd addname <name>` | Add a rule by typing a mob name, for a mob the addon has never seen. |
| `/mfd options` | Settings: every toggle the addon has, and buttons to every window. |
| `/mfd check` | The full raid check grid: consumables, raid buffs, blessings, durability, spec and addon version for everyone. |
| `/mfd buffs` | The quick buff board: only the people missing something. Works in a pug, no ready check needed. |
| `/mfd missing` | The same as the buff board, as text in chat. |
| `/mfd callout` | Post who is missing what to raid chat, grouped by fix. |
| `/mfd auras` | List the buffs on you and how the addon classified each one. Use it to catch a name the tables do not know. |
| `/mfd candidates` | The hostile mobs the addon can currently see. |
| `/mfd selftest` | Run the built-in test suite. |
| `/mfd version` | Print the version. |

Keybinds, under Key Bindings then Marked For Death: add target as a rule, re-mark the
visible pack, toggle the rule editor, toggle the assignment panel, toggle the buff board.

## Who marks

Exactly one client places icons at a time, so two people never fight over a mob.

- If a Raid Lead has been designated with `/mfd lead` and they are present with assist,
  they mark. The designation is remembered across nights.
- Otherwise the addon elects: raid leader, then assistant, then alphabetical. Anyone who
  goes silent for fifteen seconds is dropped from the election, so a disconnected raid
  leader cannot hold it up.

Everyone else running the addon is a **backup**. Backups report ruled mobs they can see
to the marker, so the marker can assign icons to mobs outside its own nameplate range.
If the marker publishes an icon it cannot physically reach, a backup that can reach the
mob places it after a short delay. Coverage is the union of everyone's nameplates rather
than one person's.

`/mfd status` always says which mode is active and why.

## Rules from other people

Everyone's rules merge into one set for the raid. Where two people have a rule for the
same mob, the Raid Lead's wins. Where the lead has none, the other rule is used. Merged
rules show in amber with the contributor's name in `/mfd list` and the editor.

Merging never touches your saved rules. It happens in memory each session. Your rules
stay exactly as you wrote them, and nobody else's rules can alter your configuration.

Editing a merged rule copies it into your own set first. From then on it is yours.

## Mid-pull behaviour

- Before the pull, marks may re-shuffle if a higher priority mob walks into range.
- The moment combat starts, assignments freeze to their mobs. Nothing moves except by
  death, which frees the role for the next mob of that job.
- If someone clears an icon the addon placed, it puts it back. After three corrections in
  five seconds it backs off and says so, rather than fighting whatever keeps wiping it.
  Only a genuine wipe counts toward that: an icon that moved because you marked something
  by hand, or because the addon reshuffled the pack itself, is replaced without spending
  the budget.
- **The pack is announced as it is marked, not as it is pulled.** One line to raid chat:
  `[MFD] Skull>Kill | Moon>Sheep Grimmtusk`, for the people not running the addon. It
  waits three seconds for the assignments to stop changing, because walking up to a pack
  brings nameplates in one at a time and the first version of a kill order is usually
  wrong. Announcing at the pull was too late to be useful: the tank is going in while the
  crowd control is still reading.
- **Once the fight starts it goes quiet.** Three seconds into a pull, assignments moving
  around is no longer news: a mob died and its icon moved on, or something got re-marked.
  Announcing that is spam and buries the line that mattered. The exception is a mob nobody
  has been told about, because an add walking in is exactly what somebody needs to hear.
- **Adds are capped at one line every twenty seconds**, however many arrive. Hyjal is why:
  its waves trickle mobs in continuously by design, so an unlimited "new mob, new line"
  rule would post for the entire fight. A mob held back stays unannounced, so it gets its
  line late rather than never. Turn the whole add rule off in Settings for a Hyjal night;
  crowd control that turns up late still gets told either way, which is the part that
  actually needs acting on.
- **Late crowd control alerts are once per mob**, at most one every three seconds, and only
  for mobs that were not there at the pull.

## How much it talks

Everything the addon says to anybody goes through one limiter, so the answer to "how loud
can this get in a bad minute" is a single number rather than six features each with their
own opinion. In any twenty seconds it will send at most five lines to the group, of which
at most three are raid warnings, and never two closer together than a second and a half.

**Whispers are not spent from that budget.** A raid message interrupts twenty five people
and a raid warning writes across the middle of their screens; a whisper costs one person
who is being told something they have to act on. The addon can go quiet on the raid
without ever going quiet on the person who has to sheep something.

**Two things are never dropped.** Anything you pressed a button for, because swallowing a
button press is worse than a crowded chat frame. And a death, which is rare, already
guarded per name, and the one line nobody can afford to lose to an announcement about a
trash pack. What the budget is actually there for is the two things that can run away on
their own: pack announcements and late crowd control.

When it does hold something back it says so once in your own chat frame, so a quiet addon
never looks like a broken one.
- The pull is detected from the pack, not from you. The marking lead is often at range and
  enters combat seconds after the tank, and reading only their own combat flag would leave
  their client announcing into a fight that had already started.
- The pull announcement is still there as a backstop for a pack pulled before it settled,
  and stays quiet when the same line has already gone out. The same assignments are not
  announced twice within thirty seconds, however they were triggered.

## Marking something yourself

Put an icon on a mob by hand and it stays. The addon reads it as your decision, holds that
mob on that icon, and allocates everything else around it: mark a mob Skull yourself and
whatever the rules would have given Skull to drops to Cross instead. It works whether or
not the icon has a role in your plan, so a hand-placed Circle holds too.

The icon you reached for decides the job, not the mob's rule. Moon on something your rules
call a kill is read as a sheep call and announced to whoever owns Moon.

Take your mark off again and the mob goes back to the addon. Holds you placed survive the
end of combat, so marking the next pack before pulling it works. `/mfd clear`, `/mfd mark`
and zoning clear them along with everything else. Turn the whole behaviour off in Settings under
**A mark placed by hand wins**.

## Calling the pack out before you pull it

The **Announce to raid** button on the assignment panel posts the current assignments to
raid chat on demand, the same line the pull announcement uses. `/mfd announce` does the
same thing and is what you want in a macro:

```
/mfd announce
```

It recomputes rather than repeating the last line, so what it posts is what is on the mobs
right now. Only the marking client announces; a backup pressing it is told why nothing was
sent instead of the raid getting the line twice.

## Raid check

Three ways to see the same data.

The **Ready check** button on the grid starts a real one: everybody gets the game's own
ready check window, and the grid fills in behind it. `/mfd check` on its own only opens the
grid, it does not ask anybody anything.

**The grid** (`/mfd check`) is one row per person: food, flask, both elixir slots,
Intellect, Mark of the Wild, Fortitude, Spirit, Shadow Protection, the blessings they
hold, durability, spec and addon version. Green is present. Red is missing and worth
fixing. Grey is either not a problem (nobody here can cast it, or the raid does not expect
it) or unknown. It opens by itself on every ready check for the raid leader and
assistants, and only them; a checkbox on it turns that off. While it is open it updates
live, so you can watch it go green during the buff phase.

**The buff board** (`/mfd buffs` or its keybind) is the small one for between pulls: only
the people short something, and what. Tick Show all to see everyone. It needs nothing
from anyone else's client, so it works in a pug where you are the only one with the addon.

**Callouts.** Click any name on either window to whisper that person exactly what they
are missing. The Call out button (or `/mfd callout`) posts to raid chat grouped by fix,
so the paladin reads the Kings line and the mage reads the Int line. Throttled to one
per ten seconds.

**Durability works on nearly everyone** without them running this addon. It comes over
LibDurability, a shared protocol embedded in BigWigs, DBM and MRT, so anyone running any
of those answers. If a player somehow runs none of them, their durability shows `?`.

The durability cell shows `72% !1` in red when someone has a broken item, because a
broken weapon at 70% overall matters more than 40% spread evenly.

**Flask or both elixirs, never both.** A flask fills both elixir slots, so it is one
requirement with two ways to meet it and the addon checks it as one. A flask on its own is
fine. A battle elixir and a guardian elixir together is fine. One elixir on its own is
half the job and reads as missing. The three columns are still shown separately so you can
see what somebody is actually running; they just answer to one requirement.

**Click a consumable column header** (Food, or Flask for the flask-or-elixirs
requirement) to toggle whether the raid expects it. Greyed headers are not expected and
their absences are never reported missing or called out. That is how you stop the addon
nagging about elixirs on a farm night.

**Spec works on anyone within about 28 yards**, no addon needed: the addon inspects
people one at a time while a raid check window is open or for twenty seconds after a
ready check, never in combat, and remembers each answer for a minute. Someone out of
range shows `?` until they wander closer.

One cell needs the other player to be running this addon: the version column, by
definition. Everything else works on anyone.

**Blessings show which ones, and how many are missing.** Somebody with Kings but no
Salvation reads `Kings (1/2)` when two paladins are in the raid. How many you should have
is however many paladins are present, one each, so it moves with the roster. Which
blessings those should be is still your call.

A buff nobody present can cast is never reported missing; with no mage in the raid,
nobody is "missing Intellect". Blessings are shown, never judged: the grid tells you which
blessings each person has and leaves which they should have to you.

**The buff columns are icons, not words.** Full colour means they have it, a greyed red
one means it is missing and worth fixing, a dim grey one means it is absent but nobody's
problem. The blessings column shows the actual blessing icons somebody is carrying, with
the shortfall count beside them. The buff board does the same: a row of greyed icons for
what each person is short.

The icons are learned from the client rather than shipped as a list of texture paths. The
first time the addon sees Arcane Intellect on anybody it remembers that icon for good, so
the grid fills in over a raid night and is complete from then on. Anything not yet seen
falls back to the word, so a column is never blank.

Buffs are recognised by name. If a flask or elixir you are wearing shows as unclassified
or does not show at all, run `/mfd auras` and send the name along; it is a one-line
addition to the tables.

## Logging

Two separate things, both on by default.

**The addon keeps its own record** of what it did: marks placed, marks it backed off,
lines sent and lines held back, deaths called, late crowd control, errors. It lives in
`SavedVariables\MarkedForDeath.lua` and survives reloads, so "it marked the wrong thing
an hour ago" is answerable by reading the file rather than by remembering. Entries are
newest first, capped at four hundred, and each carries a readable timestamp and the zone,
because a log you have to decode against the addon's own tables is a puzzle rather than a
log.

```
/mfd log            the last 20 entries
/mfd log 50         the last 50
/mfd log yield      only the times it backed off a mob
/mfd log clear      start again
```

The kinds are `mark`, `yield`, `manual`, `say`, `held`, `death`, `cc`, `lead`, `logging`
and `error`.

**The game's own combat log** is turned on when you zone into a raid and off when you
leave, so there is always a `WoWCombatLog.txt` to upload. This is the same job MRT's
Logging does, done the same way: the decision waits two seconds after the zone event
because the client does not reliably know where you are the instant a loading screen ends.

It only ever stops a log it started itself. If you turned combat logging on by hand, or
another addon did, leaving the raid will not cut your file short. Heroic dungeons are off
by default; raids are the case worth having a file for.

If MRT's Logging is also enabled, `/mfd conflicts` names it, because two addons toggling
one switch is how a log ends up truncated.

## Crowd control that cannot work

Banish only lands on demons and elementals, shackle on undead, sap on humanoids, and so
on. When you make a rule the addon checks the target's creature type and warns you, with
a sound, if that job cannot work on it. The rule is still added, because you may know
something the table does not. `/mfd list` and the editor re-check every time, since
rebinding a role can make a rule wrong later. `/mfd sound` turns the noise off.

## The mob database

Search covers two sources. **Bundled** entries are the TBC raid bosses, taken from data
already on the maintainer's client (the DBM boss modules, cross-checked against
BigWigs). **Learned** entries are every mob you have personally seen, recorded as you
go, and shown in amber. Trash is not bundled, deliberately: there was no second source to
verify a scraped list against, and a wrong id would silently mark the wrong mob. In
practice this does not matter: the first time your raid walks past a pack it is learned
and searchable from then on. `/mfd coverage` shows what you have learned that is not
bundled.

## When it is not marking

Run `/mfd debug`. It reports the actual reason in order of how fundamental it is:

- marking is switched off
- someone else is the marker and you are a backup
- you have no assist, so you cannot place icons
- no roles are configured
- enemy nameplates are off, or their range is too short
- no hostile mobs are visible
- no rules are active for this zone
- mobs are visible but none of them match a rule

If it says it is marking N of M mobs and you still see nothing, check BugSack.

## Versioning

The version appears in the `.toc`, the load message in `Core.lua`, and the zip name, and
must match.
