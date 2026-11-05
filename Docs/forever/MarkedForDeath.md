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

*To come (lane C).*

## Death calls and chat

When a tank or a healer dies, the Raid Lead's client says so: "Tank Tankard has died" as a
raid warning (raid chat without lead or assist, party chat in a party), plus the same line
across the Raid Lead's own screen with the raid warning sound. Nobody else's client says
anything, so the raid hears it once.

**Who counts.** A tank is anyone with the tank role icon or Set Main Tank (a raid marks
tanks both ways and they do not overlap), a healer anyone with the healer icon, and each
kind has an "Also counts" box for names the roster does not mark. Who counts is read out
of combat, at the pull, and kept for the fight.

**Where.** Each kind has its own switches and never reads the other's:

| Setting | What it does |
| --- | --- |
| Call tank / healer deaths | The kind on or off. Tanks start on, healers off. |
| On trash | Calls deaths outside a boss encounter. Tanks yes, healers no by default. |
| Boss ticks | One per boss in the list on the Deaths tab. A boss nobody touched is called for tanks and not for healers. |
| Right now | Per boss (the two above decide), Everywhere (every death of that kind) or Nowhere (none, ticks kept). For a change in the middle of a raid night. |

The boss comes from the encounter the client starts. If the client hides which encounter
it is, the fight still counts as a boss, with each kind's untouched-boss default.

**Once per person per fight.** The same person is never called twice in one fight; a tank
and a healer going down are both called. A pull starts everybody over. Ending combat does
not, so the Raid Lead dying and being battle-rezzed cannot call somebody twice.

**When chat is locked.** The line waits for chat to unlock for "Held lines wait" seconds
(10 by default) and is dropped if it does not; the alert on the Raid Lead's screen shows at
once either way. `/mfd log held` lists every line that was not sent and why, and every
tank or healer death that was not called and why.

**Announce.** The Announce button on the Deaths tab and `/mfd announce` post the seat plan
the current instance follows, Skull first, each crowd control seat with the player who
holds it: `Skull>Kill 1 | ... | Moon>Sheep 1 Frosty | Star>Sheep 2 (nobody)`. Only the Raid
Lead posts. It is refused, not held, while chat is locked, since a pre-pull line after the
pull is wrong. `/mfd announce off` (or the "Announce allowed" box) keeps it quiet until
switched back on.

**Chat cue.** A sound when one chosen word or phrase is said in party, raid or instance
chat, whole word, any case, at most once every 4 seconds. Off by default with no word and
no sound: on the Deaths tab, tick it, type the word, and give a sound kit id (a number) or
a sound file path. Nothing plays until all three are set. A message the client keeps
secret cannot be read, so it plays nothing.

| Command | What it does |
| --- | --- |
| `/mfd deaths` | Says how tank and healer calls are set |
| `/mfd deaths tank\|healer on\|off\|auto` | Sets that kind's Right now: everywhere, nowhere, or per boss |
| `/mfd deaths test` | Shows a death call on your screen only, with its sound |
| `/mfd announce` | Posts the seat plan to the group now |
| `/mfd announce on\|off` | Allows or stops the announce |

Not yet confirmed in a raid instance (the in-game probe ran in the open world): whether
chat is locked on raid maps outside encounters, whether a raid warning sends, and whether
the screen alert shows during an encounter.

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

## Raid Lead and sharing

| Command | What it does |
| --- | --- |
| `/mfd lead` | Says who the Raid Lead is, how they were chosen, and who is designated |
| `/mfd lead <name>` | Designates the Raid Lead. One name is enough when only one player has it; "Ann Smith" picks between two Anns. Group leader or assistant only (anyone when alone) |
| `/mfd lead clear` | Drops the designation, so the addon users elect one |
| `/mfd peers` | Who in the group runs Marked For Death and which version, whether addon messages are going out, the Raid Lead, and how many rules were merged from whom |
| `/mfd sync` | Says hello to the group again and re-asks for rules, if something looks out of step |
| `/mfd durability` | Asks the group for durability and lists the answers after three seconds |

**The Raid Lead** is the one player whose client says the raid's lines: the pre-pull
announce and the death calls. Marking does not need them: anyone with lead or assist
presses the same button. Every client works out the same Raid Lead on its own:

1. A designated Raid Lead who is in the group and online. The designation is remembered
   across nights and sent to every addon user when it changes; if two people set one, the
   later wins everywhere.
2. Otherwise the players heard running Marked For Death elect one: the group leader, then
   an assistant, then the name that sorts first.
3. If addon messages are not getting through (raids are still being checked on this
   client), the group leader.

The Raid Lead is only worked out again out of combat, so it never changes mid-pull.

**Rules from other people.** In a group, the addon users' rules for the instance you are
in are merged: where two players have a rule for the same mob, the Raid Lead's wins, and
anyone else's fills the gaps in name order, so every client ends up with the same set.
Merging never touches your saved rules; it lasts the session, and nobody else's rules can
change what you wrote. Rules travel only out of combat, in the same share format as a
file, and one bad rule refuses the whole message (it says whose and why). A very large
rule set is not sent; share it as a file instead.

**The published plan.** The Raid Lead's client sends its assignments out of combat, so
every assignment panel in the raid shows the same seats, owners and mobs.

**Durability.** `/mfd durability` asks in LibDurability's format, which BigWigs, DBM and
other addons answer, and every Marked For Death client answers it too. Your own is always
listed.

If addon messages do not go out, `/mfd peers` says why in amber, and each client plans
from its own rules.

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
