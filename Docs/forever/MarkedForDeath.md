# Marked For Death (WoW Forever)

Marked For Death keeps a raid's crowd control and kill order the same every night. The
eight raid icons belong to seats (Kill 1 to 4, Sheep 1 and 2, Banish 1 and 2), a mob rule
names a job and never an icon, and the plan reaches the mobs through your own keypress.

This is the guide for the WoW Forever addon (interface 16001) in
`AddonProjects/forever/MarkedForDeath`. The Anniversary addon has its own guide,
[Docs/MarkedForDeath.md](../MarkedForDeath.md). The design is
`Docs/forever/specs/2026-11-05-mfd-forever-design.md`.

**Status: 0.1.0 is the scaffold.** It loads, keeps its saved settings and answers `/mfd`.
Marking, rules, the raid check and death calls arrive with the feature lanes; this guide is
written in full once they have landed (lane W).

## Installing

Install `ICKit` alongside it: Marked For Death lists it under `## Dependencies` and does not
load without it. Restart the client after installing or updating, since a `.toc` change is
not read on `/reload`.

## Commands

| Command | What it does |
| --- | --- |
| `/mfd`, `/mfd help` | Lists every command |
| `/mfd version` | The version running |
| `/mfd debug` | Turns debug lines on or off |
| `/mfd selftest` (or `/mfd test`) | Runs the built-in checks |

Each feature adds its own commands to `/mfd help` as it lands.

## The seat plan

A new install starts with this plan, with no players pinned:

| Icon | Seat |
| --- | --- |
| Skull | Kill 1 |
| Cross | Kill 2 |
| Square | Kill 3 |
| Circle | Kill 4 |
| Moon | Sheep 1 |
| Star | Sheep 2 |
| Triangle | Banish 1 |
| Diamond | Banish 2 |

## Marking

*To come (lanes A and B).*

## Rules

*To come (lanes A and G).*

## Raid check

| Command | What it does |
| --- | --- |
| `/mfd check` | Opens or closes the grid: one row per member, one cell per buff or consumable |
| `/mfd check missing` | Prints who is missing what, for you only |
| `/mfd check callout` | Says who is missing what in raid (or party) chat, one line per fix, at most four lines, once per 10 seconds |
| `/mfd check auras` | Lists your own buffs with their spell ids and what the check took each one for |
| `/mfd check board` | Opens or closes the buff board: a small window listing only the members missing something. Escape leaves it up, and it is still open after a reload |
| `/mfd check ready` | Starts the game's ready check (group leader or assistant) |

**When it reads.** On Forever the client hides auras in combat, so the check reads everyone
only out of combat: when you press Scan or run a command, on every ready check, and, while
the grid or board is open, whenever a buff or the group changes. When combat starts it
reads once more (the lock arrives a few seconds after the pull) and then shows that read,
with its age, until combat ends. Nothing is read or thrown away in combat. A closed grid
listens to nothing but the ready check.

**On a ready check** everyone's check reads the group. The grid opens by itself only for the
group's leader and assistants, so twenty four other screens stay clear.

**The columns.** Int, Mark, Fort, Spirit and SProt (the class buffs), Bless (the blessings a
member carries, one expected per paladin present), Flask, Food, Dur (durability) and Ver
(the addon version). Colours: green has it, red missing, grey could not be read, amber an
older version, dim nothing expected.

- A buff nobody present can cast is never missing. Divine Spirit counts only once somebody
  in the group is seen wearing it, since it is a talent and talents cannot be inspected
  here. Shadow Protection is shown and never called out.
- Flask: a flask, or any two elixirs. One elixir is called out as the other half ("Guardian
  elixir" after a battle one), or "Second elixir" when its kind is not known.
- **Grey is never red.** A member out of sight or offline, a buff the client hid, or an
  aura list that came back empty is "could not be read", never "missing", and a callout
  never names anyone for a grey cell. Hover a row for the reason.
- Other members' durability and versions come over the addon's comms (and durability from
  boss mods that answer LibDurability). A member nobody heard from is grey.

Buffs are matched by spell id. A flask, elixir or food whose id the addon does not know yet
still counts, matched by its name or icon, and `/mfd check auras` lists it under "matched by
name only" so its id can be added (capture mode records it too).

**For the maintainer.** `Data_Auras.lua` lists every id with its source: EllesmereUI's
Forever buff families and consumables, VuhDo's Forever flavor, the client's hotfix cache,
the probe, or `classic` for a classic-era id not yet seen on Forever. The `classic` ones
(Gift of Arthas, Greater Agility and a few more) wait on capture.

## Death calls and chat

*To come (lane D).*

## Capture mode

| Command | What it does |
| --- | --- |
| `/mfd capture` | Says whether capture is on, and lists the subcommands |
| `/mfd capture on`, `off` | Starts or stops recording; it stays on across reloads until turned off |
| `/mfd capture show` | What has been recorded: totals, hidden sightings, and a line per instance |
| `/mfd capture export` | Puts everything recorded in a box on screen as one line of text, ready to copy |
| `/mfd capture clear` | Forgets everything recorded, after a yes/no question |

Marked For Death ships with the ids of every Forever dungeon and its bosses, but the raids
that open on December 9 (Barrow Deeps, Hyjal Summit, Onyxia's Lair) have none anywhere yet.
Capture mode is how the guild fills them: turn it on before the first raid, play normally,
then export and hand the text to whoever keeps the addon.

While it is on it records the instance you are in (its id, name, size and difficulty),
each boss pull with its encounter id and whether it was a kill or a wipe, and, out of
combat only, the npc id and name of whatever you target, mouse over or see a nameplate
for. Inside instances the client often hides a mob's name from addons; those sightings are
counted, never stored, and `show` says how many. It also notes your own buffs out of combat
and the spells you cast, which is how a hunter's capture finds the Freezing Trap id. It
never reads the combat log and never places a raid icon. Off, it costs nothing: no event
is listened to.

The store keeps at most 2,000 mobs, 200 encounters, 200 instances and 500 buffs and casts;
past that the one seen longest ago is dropped.

**For the maintainer.** Save each export to a file and run
`luajit scripts/mfd-forever-capture.lua <files>`. It prints every change it would make to
`Data_Instances.lua` and `Data_Mobs.lua` and every conflict (a name the client gives
differently wins and is reported); add `--write` to apply them, then review the diff.
Buffs and casts are printed for `Data_Auras.lua`, which is edited by hand.

## Other addons and combat logging

| Command | What it does |
| --- | --- |
| `/mfd conflicts` | Lists other addons doing one of the same jobs, and the setting to change in each |
| `/mfd combatlog` | Says whether combat logging is on, how many instances are listed, and what is happening here |
| `/mfd combatlog here` | Inside an instance: adds it to the logging list, or takes it off if it is already listed |
| `/mfd combatlog on`, `off` | Turns combat logging on or off without touching the list |

**Other addons.** Marked For Death reads the saved settings of these addons and names any
that is doing one of its jobs. It never changes another addon's settings.

- EllesmereUI Quality of Life: Auto Logging on (combat logging); Raid Tools shown (raid icons)
- EllesmereUI Quickdraw: an action menu with raid icon slots (raid icons)
- Forever Dungeon Journal: its quest-giver map pins put a raid icon on a click (raid icons)
- Method Raid Tools, if installed: automarker, buff marks or auto logging

An addon is listed only while it is loaded and Marked For Death is doing the same job. At
login only the ones that act by themselves get a line (Auto Logging, MRT); the ones that
act only on your click are listed by `/mfd conflicts`.

**Combat logging.** Marked For Death switches the game's combat log file on when you
enter an instance you have listed, and off when you leave it. It checks again at every pull
in case something else switched it off. Nothing is listed on a new install, so nothing is
logged until you stand in an instance and type `/mfd combatlog here`. The open world is
never logged. A log you started yourself, or one another addon started outside your list,
is left alone.

On this client the log file stayed empty in the open world when tested. Whether it fills
inside an instance is still being checked, and `/mfd combatlog` says so while anything is
listed.

## Log

| Command | What it does |
| --- | --- |
| `/mfd log` | The newest 15 lines of what the addon did, oldest first, each with its age |
| `/mfd log 40` | The newest 40 lines (up to 500) |
| `/mfd log death`, `/mfd log 5 plan` | Only one kind of line |

The kinds are `plan` (the plan or the macro changed), `held` (something was not sent or
not written, and why), `say`, `death`, `lead`, `logging`, `conflict`, `capture` and
`error`. An unknown kind lists the real ones. The log keeps the last 500 lines in the
saved settings, so after a reload or logout it can also be read in
`SavedVariables\MarkedForDeath.lua`.

## Saved settings

Account-wide settings are in `MarkedForDeathDB`, per-character ones (window places, the bar)
in `MarkedForDeathCharDB`. If the addon says at login that the account settings did not
load, restart the client before you log out or reload, or the empty settings are written
over the file.
