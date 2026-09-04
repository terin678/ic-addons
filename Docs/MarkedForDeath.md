# Marked For Death

Automatic raid target icons for trash, by kill priority and crowd control job, coordinated
across everyone in the raid who runs it. Walk up to a pack and it is marked before you
reach it.

Flavor: anniversary (TBC). Slash command: `/mfd`. Minimap button: the skull.

## The one idea to understand

**Icons belong to jobs, not to mobs.** Each of the eight icons is bound to a *seat*: a
durable job like "sheep number one" or "kill target number three". A rule for a mob only
says what should happen to it ("this gets sheeped"). The addon hands the mob the lowest
free seat for that job, and the seat supplies the icon.

That is why assignments never change under people. If Grimmtusk is pinned to sheep seat
one, Grimmtusk is always Moon. A second mage inherits sheep seat two and is always Star.
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

Everything you configure lives in a single window with tabs: **Seats**, **Rules**,
**Raid check** and **Settings**. Open it by left clicking the minimap skull, or `/mfd`.
Switching tabs never closes anything, so you can jump between the seat plan and the rule
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
| `/mfd config` | The seat editor: which icon means which job, and who is pinned. |
| `/mfd lead [name]` | Designate the Raid Lead, or clear it. Raid leader or assistant only. |
| `/mfd status` | Who is marking and why, who else is running the addon, and how many rules were merged from whom. |
| `/mfd debug` | If marking is not happening, this says exactly why, most fundamental reason first. |
| `/mfd mark` | Force a full re-mark of the visible pack. |
| `/mfd clear` | Clear every icon on visible mobs. |
| `/mfd where` | Current zone, its map id, and how many rules are active here. |
| `/mfd fixcvars` | Turn enemy nameplates on and set their range to 41 yards. |
| `/mfd export` | A string of your own rules to paste to someone. |
| `/mfd import` | Paste a rule string. It merges in; nothing of yours is deleted. |
| `/mfd coverage` | Mobs you have seen that the bundled database does not list. |
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
  death, which frees the seat for the next mob of that job.
- If someone clears or changes an icon the addon placed, it puts it back. After three
  corrections in five seconds it backs off and says so, rather than fighting a person
  who is changing it on purpose.
- On pull, the marker posts one line to raid chat: `[MFD] Skull>Kill | Moon>Sheep Grimmtusk`.
  For the people not running the addon. Throttled to one per five seconds.

## Raid check

Three ways to see the same data.

**The grid** (`/mfd check`) is one row per person: food, flask, both elixir slots, weapon
enchant, Intellect, Mark of the Wild, Fortitude, Shadow Protection, the blessings they
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

**Click a consumable column header** (Food, Flask, Battle, Guard, Weapon) to toggle
whether the raid expects it. Greyed headers are not expected and their absences are never
reported missing or called out. That is how you stop the addon nagging about battle
elixirs on a farm night.

**Spec works on anyone within about 28 yards**, no addon needed: the addon inspects
people one at a time while a raid check window is open or for twenty seconds after a
ready check, never in combat, and remembers each answer for a minute. Someone out of
range shows `?` until they wander closer.

Two cells do need the other player to be running this addon: weapon enchant and version.
No API and no other addon on the client can see another player's temporary weapon
enchant (this is true of MRT as well, whatever it looks like; on TBC it only ever shows
its own). People without the addon show `?` there and their name is amber to say the row
is scan-only. Everything else works on anyone.

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
rebinding a seat can make a rule wrong later. `/mfd sound` turns the noise off.

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
- no seats are configured
- enemy nameplates are off, or their range is too short
- no hostile mobs are visible
- no rules are active for this zone
- mobs are visible but none of them match a rule

If it says it is marking N of M mobs and you still see nothing, check BugSack.

## Versioning

The version appears in the `.toc`, the load message in `Core.lua`, and the zip name, and
must match.
