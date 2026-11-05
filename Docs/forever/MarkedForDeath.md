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

*To come (lane D).*

## Capture mode

*To come (lane E).*

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
