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

Settings also appear in the game's own Interface options under AddOns, whichever you find
first.

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

Everything about them lives on the **Deaths** tab: who counts, and which fights it applies
to. The raid gets `Dezedin has died` as a raid warning, posted by the Raid Lead's client
only so it appears once.

**Main tanks** are picked up automatically from the raid frame. Right click a portrait,
Set Main Tank, and they count; you do not have to type anything. The Extra tanks box is
only for tanks the raid does not flag, separated by commas:

```
Dezedin, Moophie, Grimmtusk
```

Tank deaths announce everywhere, trash included, which is what they have always done.
Tick **Tank deaths only on the bosses ticked below** to hold them to the boss list too.

**Healers** are recognised by spec: Holy, Discipline or Restoration. There is no healer
role on this client's raid roster the way there is a main tank flag, so spec is the honest
source, and it is the reason a shadow priest is never mistaken for one. Specs come from
the same inspection the raid check grid uses, so they fill in once you open the raid check
tab or run a ready check. The line under the Extra healers box tells you exactly who is
currently counted, which is worth reading before the pull rather than after somebody dies
unannounced. Anyone the addon cannot see, type in.

Healer deaths are **always limited to the bosses you tick**, never trash. That is the
whole point of them: a healer dying on a trash pack is not news, and a raid night of
announcements is how the feature gets turned off for good.

### Picking the bosses

The boss list on the Deaths tab is every TBC raid encounter, laid out by raid. Tick the
ones worth calling out. You can set this up before you ever walk in: Naj'entus yes,
Supremus no. **all / none** next to a raid heading does the whole instance at once.

Two Karazhan encounters are missing on purpose: the Opera Event and the Chess Event. None
of their mobs appear in the bundled mob database, and shipping a toggle that silently
never fires would be worse than not offering it.

### Changing your mind mid raid

The **Right now** button at the top of the Deaths tab has three states:

| State | What it does |
| --- | --- |
| Per boss | Follows the ticks. The default. |
| On everywhere | Announces on any boss, ignoring the ticks. |
| Off everywhere | Announces nothing at all. |

Trash is never announced under any of the three. The button is also on the minimap
shift-click menu, and `/mfd deaths` cycles it from a macro:

```
/mfd deaths
```

`/mfd deaths on`, `off` or `auto` set a specific state instead of cycling. `/mfd healers`
prints who is currently counted as one.

The fight you are in is worked out from the boss's nameplate, which the addon is already
watching for marking, and from the combat log when the nameplate is not there. There is no
encounter API on this client, so one or the other has to do it. Once a boss is identified
it stays the active fight until combat ends, which matters if you lead from range: losing
the nameplate mid fight does not quietly stop the announcements.

None of that runs at all unless a setting asks for it. With healer deaths off and tank
deaths not held to the boss list, which is how it ships, the addon never looks.

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
| `/mfd mark` | Force a full re-mark of the visible pack, dropping any hand-placed holds. |
| `/mfd clear` | Clear every icon on visible mobs. |
| `/mfd announce` | Post the current assignments to raid chat now, for calling a pack out before the pull. Macro friendly. |
| `/mfd deaths [on|off|auto]` | Cycle or set the death announcement override. Macro friendly. |
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
- On pull, the marker posts one line to raid chat: `[MFD] Skull>Kill | Moon>Sheep Grimmtusk`.
  For the people not running the addon. Throttled to one per five seconds.

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
Intellect, Mark of the Wild, Fortitude, Shadow Protection, the blessings they
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

Buffs are recognised by name. If a flask or elixir you are wearing shows as unclassified
or does not show at all, run `/mfd auras` and send the name along; it is a one-line
addition to the tables.

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
